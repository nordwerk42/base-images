#!/usr/bin/env bash
# Scans a CycloneDX SBOM with Trivy and Grype.
# Fails on any CRITICAL finding and on HIGH findings that have a fix.
# Findings stated in OpenVEX documents under vex/ are not counted.
# Usage: scan-sbom.sh <sbom.json> <report-dir>
set -euo pipefail

sbom=$1
out=$2
mkdir -p "$out"

vex_trivy=()
vex_grype=()
for f in vex/*.json; do
  [ -e "$f" ] || continue
  vex_trivy+=(--vex "$f")
  vex_grype+=(--vex "$f")
done

packages=$(jq '[.components[]? | select((.purl // "") | startswith("pkg:deb/"))] | length' "$sbom")
echo "SBOM: $packages Debian packages"
if [ "$packages" -eq 0 ]; then
  echo "SBOM lists no Debian packages, a scan would find nothing" >&2
  exit 1
fi

trivy sbom --quiet --list-all-pkgs --format json --output "$out/trivy.json" "${vex_trivy[@]}" "$sbom"
scanned=$(jq '[.Results[]?.Packages[]?] | length' "$out/trivy.json")
echo "Trivy: $scanned packages scanned"
if [ "$scanned" -eq 0 ]; then
  echo "Trivy did not recognise the packages in the SBOM" >&2
  exit 1
fi
trivy convert --format table --output "$out/trivy.txt" "$out/trivy.json"

grype "sbom:$sbom" --output json --file "$out/grype.json" "${vex_grype[@]}"
grype "sbom:$sbom" --output table --file "$out/grype.txt" "${vex_grype[@]}"

fail=0
trivy_crit=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' "$out/trivy.json")
trivy_high_fix=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH" and (.FixedVersion // "") != "")] | length' "$out/trivy.json")
grype_crit=$(jq '[.matches[] | select(.vulnerability.severity=="Critical")] | length' "$out/grype.json")
grype_high_fix=$(jq '[.matches[] | select(.vulnerability.severity=="High" and .vulnerability.fix.state=="fixed")] | length' "$out/grype.json")

printf '| Scanner | CRITICAL | HIGH with fix |\n|---|---|---|\n| Trivy | %s | %s |\n| Grype | %s | %s |\n' \
  "$trivy_crit" "$trivy_high_fix" "$grype_crit" "$grype_high_fix" | tee "$out/summary.md"

for n in "$trivy_crit" "$trivy_high_fix" "$grype_crit" "$grype_high_fix"; do
  [ "$n" -eq 0 ] || fail=1
done
exit "$fail"
