# Fetch a prebuilt Node.js release tarball and shape it into an image package.
# Version-agnostic: the stream (24, 26, ...) is decided by the caller in flake.nix.
#
# withNpm decides whether the bundled package managers come along. The minimal
# image runs an application that was installed elsewhere, so it ships the
# runtime only; the standard image keeps them for the same reason it keeps a
# shell.
{ nodeVersion, arch, pkgs, sha256, withNpm ? true }: rec {
  nodeArch = if arch == "amd64" then "x64" else arch;

  nodejsBinary = pkgs.fetchurl {
    url =
      "https://nodejs.org/dist/v${nodeVersion}/node-v${nodeVersion}-linux-${nodeArch}.tar.xz";
    sha256 = sha256;
  };

  # SBOM for npm and everything npm bundles in its own node_modules.
  #
  # The path filter keeps <node_modules>/<name> and <node_modules>/@<scope>/<name>
  # only: it picks up scoped packages and nested node_modules, while skipping the
  # per-directory marker package.json files (dist/esm, dist/commonjs, libcjs, ...)
  # that carry no name/version.
  #
  # The dependencies graph matters as much as the components: devguard-scanner
  # merge-sboms prunes every component that is not reachable from the SBOM root,
  # so a component list without edges collapses to just npm.
  nodejsSBOM = if !withNpm then
    null
  else
    pkgs.runCommand "nodejs-${nodeVersion}-npm-sbom" {
      nativeBuildInputs = with pkgs.buildPackages; [ findutils gnugrep jq ];
    } ''
      mkdir -p $out
      npmRoot="${nodejsPackage}/lib/node_modules/npm"
      npmVersion=$(jq -r '.version' "$npmRoot/package.json")

      find "$npmRoot/node_modules" -name package.json \
        | grep -E '/node_modules/(@[^/]+/)?[^/]+/package\.json$' \
        | while read -r f; do
            jq -c '{
              name,
              version,
              deps: (((.dependencies // {}) + (.optionalDependencies // {})) | keys)
            }' "$f"
          done \
        | jq -s --arg npmVersion "$npmVersion" '
            def ref: "pkg:npm/" + .name + "@" + .version;

            ([ .[] | select(.name and .version) ] | unique_by(.name + "@" + .version)) as $pkgs
            | ("pkg:npm/npm@" + $npmVersion) as $root
            | ($pkgs | map({ (.name): (. | ref) }) | add // {}) as $refByName
            | {
                bomFormat: "CycloneDX",
                specVersion: "1.6",
                version: 1,
                metadata: {
                  component: {
                    type: "library",
                    "bom-ref": $root,
                    name: "npm",
                    version: $npmVersion,
                    purl: $root
                  }
                },
                components: [
                  $pkgs[] | {
                    type: "library",
                    "bom-ref": ref,
                    name: .name,
                    version: .version,
                    purl: ref
                  }
                ],
                # npm -> every package it bundles, so nothing can be pruned, plus
                # the declared edges between the bundled packages themselves.
                dependencies: (
                  [ { ref: $root, dependsOn: [ $pkgs[] | ref ] } ]
                  + [ $pkgs[] | {
                        ref: ref,
                        dependsOn: [ .deps[]? | $refByName[.] // empty ]
                      } ]
                )
              }' \
        > $out/sbom.json
    '';

  # Extract and prepare the Node.js package structure
  nodejsPackage = pkgs.runCommand "nodejs-${nodeVersion}-custom" {
    nativeBuildInputs = with pkgs.buildPackages; [ gnutar xz ];
  } (''
    mkdir -p $out
    tar -xf ${nodejsBinary} -C $out --strip-components=1

    # Create symlinks pointing to /bin/* (container-absolute paths, not Nix store paths)
    mkdir -p $out/usr/bin
    ln -sf /bin/node $out/usr/bin/node
  '' + pkgs.lib.optionalString withNpm ''
    ln -sf /bin/npm $out/usr/bin/npm
    ln -sf /bin/npx $out/usr/bin/npx
  '' + pkgs.lib.optionalString (!withNpm) ''
    rm -f $out/bin/npm $out/bin/npx $out/bin/corepack
    rm -rf $out/lib/node_modules
    rmdir $out/lib 2>/dev/null || true

    for stale in npm npx corepack; do
      if [ -e "$out/bin/$stale" ] || [ -L "$out/bin/$stale" ]; then
        echo "bin/$stale survived removal" >&2
        exit 1
      fi
    done
  '');

  # Define custom package metadata for SBOM.
  #
  # The Node.js runtime is tracked in OSV through the GIT ranges of the CVE
  # records, which name the upstream repository and enumerate the affected
  # releases as "v26.5.0", "v24.18.0", ... (see CVE-2026-56847). The version
  # therefore has to carry the same leading "v": matching compares the version
  # string as published, so a bare "26.8.1" matches none of those rows.
  customPackages = [{
    name = "nodejs";
    version = nodeVersion;
    type = "application";
    purl =
      "pkg:github.com/nodejs/node@v${nodeVersion}?arch=${arch}&source=nodejs.org";
    path = nodejsPackage;
    sha256 = sha256;
    properties = [
      {
        name = "cdx:source:url";
        value = "https://nodejs.org/dist/v${nodeVersion}/";
      }
      {
        name = "cdx:source:type";
        value = "prebuilt-binary";
      }
      {
        name = "cdx:platform";
        value = "linux-${nodeArch}";
      }
    ];
    dependencies = [ ]; # Node.js binary is self-contained
  }];
}
