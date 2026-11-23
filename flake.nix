{
  description = "Minimal distroless OCI images from Debian packages";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    container-hardening = {
      url =
        "git+https://gitlab.opencode.de/oci-community/tools/container-hardening-work-bench.git?rev=9e5cecc35d8871b92d8f00d9effe8f5f0c7b16dd";
      flake = false;
    };
  };

  outputs = { self, container-hardening, nixpkgs, ... }:
    let
      # All supported build systems
      buildSystems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];

      # Target systems (what you're building for)
      targetSystems = [ "x86_64-linux" "aarch64-linux" ];

      versions = [ "0" ];

      # Helper: Convert system to architecture name
      systemToArch = system:
        if system == "x86_64-linux" then "amd64" else "arm64";

      # Generate packages for a specific build system
      packagesForBuildSystem = buildSystem:
        let
          # Build a single Node.js image for a specific target system and version
          buildPackage = targetSystem: version:
            let
              arch = systemToArch targetSystem;
              configFile = ./config.${arch}.json;
              config = builtins.fromJSON (builtins.readFile configFile);
              distrolessHelpers =
                import "${container-hardening}/nix/build-distroless.nix" {
                  inherit pkgs nixpkgs;
                  debianArch = arch;
                };
              pkgs = distrolessHelpers.getPkgsFor buildSystem targetSystem;

              sbomGen = import "${container-hardening}/nix/sbom.nix" {
                inherit pkgs;
                debianArch = arch;
              };

              customPackages = [ ];
            in {
              # The regular image package
              image = distrolessHelpers.buildImage {
                inherit customPackages;
                name = config.name;
                tag = config.tag;
                symlinks = config.symlinks;
                debPackages = config.packages;
                extraFakeRootCommands = ''
                  ln -sf /usr/share/zoneinfo/UTC ./etc/localtime
                '';
              };

              # The debug image package (with busybox shell)
              debugImage = distrolessHelpers.buildDebugImage {
                inherit customPackages;
                name = config.name;
                tag = config.tag;
                symlinks = config.symlinks;
                debPackages = config.packages;
                extraFakeRootCommands = ''
                  ln -sf /usr/share/zoneinfo/UTC ./etc/localtime
                '';
              };

              # The SBOM package
              sbom = sbomGen.forImage {
                inherit customPackages;
                purl = "pkg:oci/base";
                packages = config.packages;
                topLevelPackages = config.topLevelPackages;
              };
              # The SBOM package for debug image
              debugSbom = sbomGen.forImage {
                purl = "pkg:oci/base";
                packages = config.packages ++ distrolessHelpers.debugPackages;
                topLevelPackages = config.topLevelPackages
                  ++ distrolessHelpers.debugPackages;
              };
            };

          # Build all packages: for each version, for each target system
          makePackagesForVersion = version:
            builtins.listToAttrs (map (targetSystem:
              let
                arch = systemToArch targetSystem;
                pkg = buildPackage targetSystem version;
              in {
                # Create attribute name like "base-22-amd64"
                name = "base-${version}-${arch}";
                value = pkg.image;
              }) targetSystems ++ map (targetSystem:
                let
                  arch = systemToArch targetSystem;
                  pkg = buildPackage targetSystem version;
                in {
                  # Create attribute name like "base-debug-22-amd64"
                  name = "base-debug-${version}-${arch}";
                  value = pkg.debugImage;
                }) targetSystems ++ map (targetSystem:
                  let
                    arch = systemToArch targetSystem;
                    pkg = buildPackage targetSystem version;
                  in {
                    # Create attribute name like "base-22-amd64-sbom"
                    name = "base-${version}-${arch}-sbom";
                    value = pkg.sbom;
                  }) targetSystems ++ map (targetSystem:
                    let
                      arch = systemToArch targetSystem;
                      pkg = buildPackage targetSystem version;
                    in {
                      # Create attribute name like "base-debug-22-amd64-sbom"
                      name = "base-debug-${version}-${arch}-sbom";
                      value = pkg.debugSbom;
                    }) targetSystems);

          # Combine packages for all Node.js versions
          allVersionPackages = map makePackagesForVersion versions;

          # Merge all version packages into one attribute set
          mergedPackages =
            builtins.foldl' (a: b: a // b) { } allVersionPackages;
        in mergedPackages;
    in {
      packages = builtins.listToAttrs (map (buildSystem: {
        name = buildSystem;
        value = packagesForBuildSystem buildSystem;
      }) buildSystems);
    };
}
