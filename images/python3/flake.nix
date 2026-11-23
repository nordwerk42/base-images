{
  description = "Minimal distroless OCI images from Debian packages";

  inputs = {
    # Pinned to a nixpkgs whose glibc (2.40) is not newer than Debian 13's
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    container-hardening = {
      url =
        "git+ssh://git@gitlab.opencode.de/oci-community/tools/container-hardening-work-bench.git";
      flake = false;
    };
  };

  outputs = { self, container-hardening, nixpkgs, ... }:
    let
      # All supported build systems
      buildSystems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];

      # Target systems (what you're building for)
      targetSystems = [ "x86_64-linux" "aarch64-linux" ];

      # Python versions to build, pinned to the current upstream patch release.
      # Refresh with: ./update-python-sources.sh
      pythonSources = {
        "3.10" = {
          version = "3.10.22";
          hash = "sha256-xh/psaGn7CoLA4jmZBh8N4pTJaieNgbSIKv1vfzLJUM=";
        };
        "3.11" = {
          version = "3.11.18";
          hash = "sha256-kSDgplOGj242mNNs3ZnlpYkD7JRp5EjyHZj3sW2PopA=";
        };
        "3.12" = {
          version = "3.12.16";
          hash = "sha256-tXlpFdxF/3Rc+06ZCn58k9b1RjKKECzjFEjWnrw3V1w=";
        };
        "3.13" = {
          version = "3.13.18";
          hash = "sha256-q7AQLm1K4CdQm8uCMn2d2FUVtEo7qK1TjPxemEcCn2g=";
        };
        "3.14" = {
          version = "3.14.10";
          hash = "sha256-3kFKVxGavvUnhNiZPjQdU67WNfwrBcJgfZ+YosW3IDI=";
        };
      };

      pythonVersions = builtins.attrNames pythonSources;

      # Helper: Convert system to architecture name
      systemToArch = system:
        if system == "x86_64-linux" then "amd64" else "arm64";

      # Helper: "3.13" -> "python313"
      pythonAttr = version:
        "python${builtins.replaceStrings [ "." ] [ "" ] version}";

      # Debian packages CPython is linked against or reads data from at runtime.
      # Used to give the CPython SBOM component a real dependency graph.
      pythonRuntimeDeps = [
        "libc6"
        "libgcc-s1"
        "libcrypt1"
        "libssl3t64"
        "zlib1g"
        "libbz2-1.0"
        "liblzma5"
        "libzstd1"
        "libexpat1"
        "libffi8"
        "libmpdec4"
        "libncursesw6"
        "libtinfo6"
        "libreadline8t64"
        "libuuid1"
        "libsqlite3-0"
        "libgdbm6t64"
        "libgdbm-compat4t64"
        "ca-certificates"
        "tzdata"
        "media-types"
        "netbase"
      ];

      # Generate packages for a specific build system
      packagesForBuildSystem = buildSystem:
        let
          # Build a single Python image for a specific target system and version
          buildPythonPackage = targetSystem: version:
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

              # Same PURL shape sbom.nix builds for Debian packages, so the
              # CPython component can reference them as dependencies.
              debianPurl = pkg:
                "pkg:deb/debian/${pkg.name}@${pkg.version}?arch=${arch}&distro=debian-${pkg.distroVersion}";
              debianDependencies = map debianPurl (builtins.filter
                (pkg: builtins.elem pkg.name pythonRuntimeDeps)
                config.packages);

              # CPython comes from nixpkgs, relinked against the Debian rootfs
              python = import ./python-custom.nix {
                inherit pkgs arch debianDependencies;
                python = pkgs.${pythonAttr version};
                inherit (pythonSources.${version}) version hash;
              };

              customPackages = python.customPackages;
              tag = "${version}-${arch}";
            in {
              # The regular image package
              image = distrolessHelpers.buildImage {
                inherit customPackages tag;
                name = config.name;
                symlinks = config.symlinks;
                debPackages = config.packages;
                # Matches the official python image; resolved via PATH=/usr/bin:/bin.
                # The debug image keeps its /bin/sh default.
                cmd = [ "python3" ];
              };

              # The debug image package (with busybox shell)
              debugImage = distrolessHelpers.buildDebugImage {
                inherit customPackages tag;
                name = config.name;
                symlinks = config.symlinks;
                debPackages = config.packages;
              };

              # The SBOM package
              sbom = sbomGen.forImage {
                inherit customPackages;
                purl = "pkg:oci/python3";
                packages = config.packages;
                topLevelPackages = config.topLevelPackages;
              };

              # The SBOM package for debug image
              debugSbom = sbomGen.forImage {
                inherit customPackages;
                purl = "pkg:oci/python3";
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
                pkg = buildPythonPackage targetSystem version;
              in {
                # Create attribute name like "python3-3.13-amd64"
                name = "python3-${version}-${arch}";
                value = pkg.image;
              }) targetSystems ++ map (targetSystem:
                let
                  arch = systemToArch targetSystem;
                  pkg = buildPythonPackage targetSystem version;
                in {
                  # Create attribute name like "python3-debug-3.13-amd64"
                  name = "python3-debug-${version}-${arch}";
                  value = pkg.debugImage;
                }) targetSystems ++ map (targetSystem:
                  let
                    arch = systemToArch targetSystem;
                    pkg = buildPythonPackage targetSystem version;
                  in {
                    # Create attribute name like "python3-3.13-amd64-sbom"
                    name = "python3-${version}-${arch}-sbom";
                    value = pkg.sbom;
                  }) targetSystems ++ map (targetSystem:
                    let
                      arch = systemToArch targetSystem;
                      pkg = buildPythonPackage targetSystem version;
                    in {
                      # Create attribute name like "python3-debug-3.13-amd64-sbom"
                      name = "python3-debug-${version}-${arch}-sbom";
                      value = pkg.debugSbom;
                    }) targetSystems);

          # Combine packages for all Python versions
          allVersionPackages = map makePackagesForVersion pythonVersions;

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
