{
  description = "Minimal distroless OCI images from Debian packages";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    container-hardening = {
      # Optional: pin to specific commit for reproducibility
      url =
        "git+https://gitlab.opencode.de/oci-community/tools/container-hardening-work-bench.git?rev=21f38fed9c32a39a694ba0fec32b933bfc0dbcd0";
      flake = false;
    };
    devguard.url =
      "git+https://gitlab.opencode.de/oci-community/images/l3montree/devguard/devguard.git?rev=113c19d90f439d48afcb6ba0dd5d9660dab84c98";
  };

  outputs = { self, container-hardening, nixpkgs, devguard, ... }:
    let
      # All supported build systems
      buildSystems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];

      # Target systems (what you're building for)
      targetSystems = [ "x86_64-linux" "aarch64-linux" ];

      # Node.js streams to build, pinned to the current upstream release of
      # each stream. The hashes are the sha256 of the prebuilt linux tarballs
      # as published in https://nodejs.org/dist/v<version>/SHASUMS256.txt.
      # Refresh with: cd scripts/update && go run .
      nodejsSources = {
        "24" = {
          version = "24.22.3";
          hashes = {
            amd64 = "sha256-TysXWm1TpcYXqA26JnYjigaIzvKMbaTro1x9hE5m/Ps=";
            arm64 = "sha256-blGiraAPABHMJm9l2YkitAPXrYj4CcoqphWl/hzm6Gw=";
          };
        };
        "26" = {
          version = "26.13.1";
          hashes = {
            amd64 = "sha256-XAY+Rrqw+8HBfMRF1/8SnL3NBHG+btg7arhk+BQ7yGQ=";
            arm64 = "sha256-ieGFMTjbUei4LT6YupwNPylWoo5eVeobfhLSWq6S1d0=";
          };
        };
      };

      nodejsVersions = builtins.attrNames nodejsSources;

      # Helper: Convert system to architecture name
      systemToArch = system:
        if system == "x86_64-linux" then "amd64" else "arm64";

      # Generate packages for a specific build system
      packagesForBuildSystem = buildSystem:
        let
          # Build a single Node.js image for a specific target system and version
          buildNodejsPackage = targetSystem: version:
            let
              arch = systemToArch targetSystem;
              source = nodejsSources.${version};
              tag = "${version}-${arch}";
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

              nodejsFor = withNpm:
                import ./node-custom.nix {
                  inherit pkgs arch withNpm;
                  nodeVersion = source.version;
                  sha256 = source.hashes.${arch};
                };

              nodejsMinimal = nodejsFor false;
              nodejsStandard = nodejsFor true;

              mergeSboms = extraSboms: baseSbom:
                let
                  mergeConfig = pkgs.writeText "sbom-merge-config.json"
                    (builtins.toJSON {
                      purl = "pkg:oci/nodejs";
                      sboms = [ "${baseSbom}" ] ++ extraSboms;
                    });
                in pkgs.runCommand "sbom-merged" {
                  nativeBuildInputs =
                    [ devguard.packages.${buildSystem}.devguardScanner ];
                } ''
                  devguard-scanner merge-sboms ${mergeConfig} > $out
                '';
            in {

              # The regular image package, published as the "-minimal" tag
              image = distrolessHelpers.buildImage {
                inherit tag;
                customPackages = nodejsMinimal.customPackages;
                name = config.name;
                symlinks = config.symlinks;
                debPackages = config.packages;
              };

              # The debug image package (with busybox shell)
              debugImage = distrolessHelpers.buildDebugImage {
                inherit tag;
                customPackages = nodejsStandard.customPackages;
                name = config.name;
                symlinks = config.symlinks;
                debPackages = config.packages;
              };

              sbom =
                let baseSbom = sbomGen.forImage {
                  customPackages = nodejsMinimal.customPackages;
                  purl = "pkg:oci/nodejs";
                  packages = config.packages;
                  topLevelPackages = config.topLevelPackages;
                };
                in mergeSboms [ ] baseSbom;
              # The SBOM package for debug image
              debugSbom =
                let baseSbom = sbomGen.forImage {
                  customPackages = nodejsStandard.customPackages;
                  purl = "pkg:oci/nodejs";
                  packages = config.packages ++ distrolessHelpers.debugPackages;
                  topLevelPackages = config.topLevelPackages
                    ++ distrolessHelpers.debugPackages;
                };
                in mergeSboms [ "${nodejsStandard.nodejsSBOM}/sbom.json" ] baseSbom;
            };

          # Build all packages: for each version, for each target system
          makePackagesForVersion = version:
            builtins.listToAttrs (map (targetSystem:
              let
                arch = systemToArch targetSystem;
                pkg = buildNodejsPackage targetSystem version;
              in {
                # Create attribute name like "nodejs-22-amd64"
                name = "nodejs-${version}-${arch}";
                value = pkg.image;
              }) targetSystems ++ map (targetSystem:
                let
                  arch = systemToArch targetSystem;
                  pkg = buildNodejsPackage targetSystem version;
                in {
                  # Create attribute name like "nodejs-debug-22-amd64"
                  name = "nodejs-debug-${version}-${arch}";
                  value = pkg.debugImage;
                }) targetSystems ++ map (targetSystem:
                  let
                    arch = systemToArch targetSystem;
                    pkg = buildNodejsPackage targetSystem version;
                  in {
                    # Create attribute name like "nodejs-22-amd64-sbom"
                    name = "nodejs-${version}-${arch}-sbom";
                    value = pkg.sbom;
                  }) targetSystems ++ map (targetSystem:
                    let
                      arch = systemToArch targetSystem;
                      pkg = buildNodejsPackage targetSystem version;
                    in {
                      # Create attribute name like "nodejs-debug-22-amd64-sbom"
                      name = "nodejs-debug-${version}-${arch}-sbom";
                      value = pkg.debugSbom;
                    }) targetSystems);

          # Combine packages for all Node.js versions
          allVersionPackages = map makePackagesForVersion nodejsVersions;

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
