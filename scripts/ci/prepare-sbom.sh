#!/usr/bin/env bash
# Makes a CycloneDX SBOM from the Nix build scannable and prints the runtime version.
# Adds the Debian release as operating-system component and, for the runtime built
# from upstream source, a CPE so that Grype can match its advisories.
# Usage: prepare-sbom.sh <nix-sbom> <out.json> <debian-release> <runtime-name|-> <cpe-prefix|->
set -euo pipefail

src=$1
out=$2
release=$3
runtime=$4
cpe_prefix=$5

[ -d "$src" ] && src=$(ls "$src"/*.json)
jq -e '.bomFormat == "CycloneDX"' "$src" >/dev/null

jq --arg rel "$release" --arg rt "$runtime" --arg cpe "$cpe_prefix" '
  (if any(.components[]?; .type == "operating-system") then .
   else .components += [{"type":"operating-system","name":"debian","version":$rel,"bom-ref":"os-debian"}] end)
  | if $rt != "-" then
      .components |= map(if .name == $rt and (.cpe // "") == "" then .cpe = "\($cpe):\(.version):*:*:*:*:*:*:*" else . end)
    else . end
' "$src" > "$out"

if [ "$runtime" != "-" ]; then
  version=$(jq -r --arg rt "$runtime" '[.components[] | select(.name == $rt) | .version][0] // empty' "$out")
  [ -n "$version" ] || { echo "runtime component $runtime missing in SBOM" >&2; exit 1; }
  echo "$version"
fi
