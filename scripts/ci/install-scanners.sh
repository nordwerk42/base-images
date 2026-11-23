#!/usr/bin/env bash
# Installs Trivy and Grype from their GitHub releases and checks each archive against a pinned SHA-256.
set -euo pipefail

TRIVY_VERSION=0.76.2
GRYPE_VERSION=0.121.2

case "$(uname -m)" in
  x86_64)
    trivy_asset="trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"
    trivy_sha=bc0fc726e017b8927a62b2d3531d7a84ee01769daf5c99ed866dced54089fdbf
    grype_asset="grype_${GRYPE_VERSION}_linux_amd64.tar.gz"
    grype_sha=9c8965ced9df657e5e851c14021bae838802f711edd7a48f9bc3c923a8d28f12
    ;;
  aarch64)
    trivy_asset="trivy_${TRIVY_VERSION}_Linux-ARM64.tar.gz"
    trivy_sha=ab9d51f86e6a5fb936f605faff6b593ac51bc378fff4d3e8b9d58358b9c367c3
    grype_asset="grype_${GRYPE_VERSION}_linux_arm64.tar.gz"
    grype_sha=d7d2e160255b0f087280feabf6f213cf4c45d475690f3f1fe5dc336eb1037bf0
    ;;
  *) echo "unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
bin=${SCANNER_BIN:-$HOME/.local/bin}
mkdir -p "$bin"

fetch() {
  local url=$1 sha=$2 out=$3
  curl -fsSL --retry 3 -o "$out" "$url"
  echo "$sha  $out" | sha256sum -c --quiet -
}

fetch "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/${trivy_asset}" "$trivy_sha" "$dir/trivy.tar.gz"
fetch "https://github.com/anchore/grype/releases/download/v${GRYPE_VERSION}/${grype_asset}" "$grype_sha" "$dir/grype.tar.gz"
tar -xzf "$dir/trivy.tar.gz" -C "$bin" trivy
tar -xzf "$dir/grype.tar.gz" -C "$bin" grype
"$bin/trivy" --version | head -1
"$bin/grype" version | grep -E '^Version'
