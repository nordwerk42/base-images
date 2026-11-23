{
  description = "Minimal static OCI image with ca-certificates and tzdata";

  inputs = { 
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    container-hardening = {
      url = "git+ssh://git@gitlab.opencode.de/oci-community/tools/container-hardening-work-bench.git";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, container-hardening, ... }:
    let
      buildSystems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin"];
      targetSystems = ["x86_64-linux" "aarch64-linux"];
      versions = ["0"];
      
      # Helper: Convert system to architecture name
      systemToArch = system: if system == "x86_64-linux" then "amd64" else "arm64";
      
      build = buildSystem: targetSystem: version:
        let
          arch = systemToArch targetSystem;
          # Always use buildSystem for the actual build tools and scripts
          pkgs = import nixpkgs { system = buildSystem; };
          
          # Import SBOM generator and distroless helpers from container-hardening
          sbomGen = import "${container-hardening}/nix/sbom.nix" {
            inherit pkgs;
            debianArch = arch;
          };          
          # Create standard Linux directory structure
          # This runs on the build system, not the target system
          fhs = pkgs.runCommand "fhs" {} ''
            mkdir -p $out/tmp
            mkdir -p $out/var/tmp
            mkdir -p $out/var/log
            mkdir -p $out/var/cache
            mkdir -p $out/etc
            mkdir -p $out/home
            mkdir -p $out/root
            mkdir -p $out/usr/bin
            mkdir -p $out/usr/local
            mkdir -p $out/opt
          '';

          # Create passwd and group files for the user
          # This runs on the build system, not the target system
          userFiles = pkgs.runCommand "user-files" {} ''
            mkdir -p $out/etc
            
            # Create minimal passwd file
            cat > $out/etc/passwd <<EOF
            root:x:0:0:root:/root:/bin/sh
            nobody:x:65534:65534:nobody:/:/bin/false
            nonroot:x:53111:53111:nonroot user:/home/nonroot:/bin/sh
            EOF
            
            # Create minimal group file
            cat > $out/etc/group <<EOF
            root:x:0:
            nobody:x:65534:
            nonroot:x:53111:
            EOF
            
            # Create home directory
            mkdir -p $out/home/nonroot
          '';

          baseImage = pkgs.dockerTools.buildLayeredImage {
            name = "static";
            tag = "${version}-${arch}";
            contents = [ 
              pkgs.cacert 
              pkgs.tzdata
              fhs
              userFiles
            ];
            config = {
              Env = [
                "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
                "TZDIR=${pkgs.tzdata}/share/zoneinfo"
              ];
              WorkingDir = "/";
            };
            fakeRootCommands = ''
              chmod 1777 tmp
              chmod 1777 var/tmp
              chown 53111:53111 home/nonroot
            '';
          };
          
          # Fix architecture metadata
          image = pkgs.runCommand "static-${version}-${arch}.tar.gz" {
            buildInputs = [ pkgs.jq pkgs.gnutar pkgs.gzip ];
          } ''
            # Extract the base image
            mkdir -p work
            cd work
            tar -xzf ${baseImage}
            
            # Find and update the config file
            CONFIG=$(jq -r '.[0].Config' manifest.json)
            
            # Update architecture in config
            jq '.architecture = "${arch}"' "$CONFIG" > "$CONFIG.new"
            mv "$CONFIG.new" "$CONFIG"
            
            # Repackage
            tar -czf $out *
          '';
          busyboxPkg = pkgs.pkgsStatic.busybox.override {
            enableStatic = true;
            enableMinimal = false;
          };

          busyboxCycloneDX = {
            type = "library";
            "bom-ref" = "pkg:github.com/mirror/busybox@${pkgs.pkgsStatic.busybox.version}";
            name = "busybox";
            version = pkgs.pkgsStatic.busybox.version;
            purl = "pkg:github.com/mirror/busybox@${pkgs.pkgsStatic.busybox.version}";
          };
          
          packagesCycloneDX = [{
            type = "library";
            "bom-ref" = "pkg:github.com/NixOS/nixpkgs/cacert@${pkgs.cacert.version}";
            name = "ca-certificates";
            version = pkgs.cacert.version;
            purl = "pkg:github.com/NixOS/nixpkgs/cacert@${pkgs.cacert.version}";
          }
          {
            type = "library";
            "bom-ref" = "pkg:github.com/NixOS/nixpkgs/tzdata@${pkgs.tzdata.version}";
            name = "tzdata";
            version = pkgs.tzdata.version;
            purl = "pkg:github.com/NixOS/nixpkgs/tzdata@${pkgs.tzdata.version}";
          }];

          # Build busybox on the build system
          busybox = pkgs.runCommand "image-root-debug" { } ''
                set -euxo pipefail
                mkdir -p $out/bin
                cp ${busyboxPkg}/bin/busybox $out/bin/busybox
                
                # Create busybox symlinks for common shell utilities
                for cmd in sh ash cat ls cp mv rm mkdir rmdir ln chmod chown grep find ps top; do
                  ln -sf /bin/busybox $out/bin/$cmd
                done
              '';

          # Debug image with busybox
          baseDebugImage = pkgs.dockerTools.buildLayeredImage {
            name = "static";
            tag = "${version}-${arch}-debug";
            contents = [ 
              pkgs.cacert 
              pkgs.tzdata
              fhs
              userFiles
              busybox
            ];
            config = {
              Env = [
                "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
                "TZDIR=${pkgs.tzdata}/share/zoneinfo"
                "PATH=/bin"
              ];
              WorkingDir = "/";
              Cmd = [ "/bin/sh" ];
            };
            fakeRootCommands = ''
              chmod 1777 tmp
              chmod 1777 var/tmp
              chown 53111:53111 home/nonroot
            '';
          };
          
          # Fix architecture metadata
          debugImage = pkgs.runCommand "static-${version}-${arch}-debug.tar.gz" {
            buildInputs = [ pkgs.jq pkgs.gnutar pkgs.gzip ];
          } ''
            # Extract the base image
            mkdir -p work
            cd work
            tar -xzf ${baseDebugImage}
            
            # Find and update the config file
            CONFIG=$(jq -r '.[0].Config' manifest.json)
            
            # Update architecture in config
            jq '.architecture = "${arch}"' "$CONFIG" > "$CONFIG.new"
            mv "$CONFIG.new" "$CONFIG"
            
            # Repackage
            tar -czf $out *
          '';
          
          # Generate SBOM
          sbom = sbomGen.forImage {
            customPackages = [];
            purl = "pkg:oci/static";
            packages = packagesCycloneDX; # Empty since we're using Nix packages, not Debian
            topLevelPackages = packagesCycloneDX;
          };
          
          # Generate SBOM for debug image
          debugSbom = sbomGen.forImage {
            customPackages = [];
            purl = "pkg:oci/static";
            packages = [busyboxCycloneDX] ++ packagesCycloneDX;
            topLevelPackages = [busyboxCycloneDX] ++ packagesCycloneDX;
          };
          
        in {
          inherit image debugImage sbom debugSbom;
        };
      
      # Build packages for each combination
      packagesForBuildSystem = buildSystem:
        let
          makePackagesForVersion = version:
            builtins.concatMap (targetSystem:
              let
                arch = systemToArch targetSystem;
                pkg = build buildSystem targetSystem version;
              in [
                {
                  name = "static-${version}-${arch}";
                  value = pkg.image;
                }
                {
                  name = "static-${version}-${arch}-sbom";
                  value = pkg.sbom;
                }
                {
                  name = "static-debug-${version}-${arch}";
                  value = pkg.debugImage;
                }
                {
                  name = "static-debug-${version}-${arch}-sbom";
                  value = pkg.debugSbom;
                }
              ]
            ) targetSystems;
          
          allPackages = builtins.concatMap makePackagesForVersion versions;
        in builtins.listToAttrs allPackages;
      
    in {
      packages = builtins.listToAttrs (builtins.map (system: {
        name = system;
        value = packagesForBuildSystem system;
      }) buildSystems);
    };
}