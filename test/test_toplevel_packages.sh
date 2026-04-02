#!/bin/sh
# Copyright 2025 Zentrum für Digitale Souveränität der Öffentlichen Verwaltung (ZenDiS) GmbH.
# SPDX-License-Identifier: MIT
set -eu

pass=0
fail=0

ok()   { echo "  PASS: $*"; pass=$((pass + 1)); }
fail() { echo "  FAIL: $*"; fail=$((fail + 1)); }


# Check a path exists
check_file() {
  label="$1"
  path="$2"
  if [ -e "$path" ]; then
    ok "$label"
  else
    fail "$label ($path not found)"
  fi
}


echo "=== top-level packages: key files ==="

# ca-certificates
check_file "ca-certificates bundle"  /etc/ssl/certs/ca-certificates.crt
check_file "ca-certificates dir"     /etc/ssl/certs

# tzdata
check_file "tzdata UTC zone"         /usr/share/zoneinfo/UTC
check_file "tzdata Europe/Berlin"    /usr/share/zoneinfo/Europe/Berlin
check_file "localtime"               /etc/localtime

# libc6 / libssl3 — paths are architecture-specific
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)   TRIPLET="x86_64-linux-gnu" ;;
  aarch64)  TRIPLET="aarch64-linux-gnu" ;;
  *)        TRIPLET="$ARCH-linux-gnu" ;;
esac

check_file "libc.so"    /usr/lib/${TRIPLET}/libc.so.6
check_file "libssl.so"  /usr/lib/${TRIPLET}/libssl.so.3

echo ""
echo "=== results: $pass passed, $fail failed ==="
if [ "$fail" -gt 0 ]; then
  exit 1
fi
