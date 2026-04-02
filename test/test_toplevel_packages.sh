#!/bin/sh
# Copyright 2025 Zentrum für Digitale Souveränität der Öffentlichen Verwaltung (ZenDiS) GmbH.
# SPDX-License-Identifier: MIT
set -eu

pass=0
fail=0

ok()   { echo "  PASS: $*"; pass=$((pass + 1)); }
fail() { echo "  FAIL: $*"; fail=$((fail + 1)); }

# Run a command and check it exits 0
check_run() {
  label="$1"
  shift
  if "$@" > /dev/null 2>&1; then
    ok "$label"
  else
    fail "$label ($* exited $?)"
  fi
}

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

# Check a package is marked as installed in the dpkg status file
# (the dpkg binary itself is not present in this distroless image)
check_pkg() {
  pkg="$1"
  if grep -q "^Package: ${pkg}$" /var/lib/dpkg/status 2>/dev/null; then
    ok "$pkg is installed"
  else
    fail "$pkg is not installed"
  fi
}

echo "=== top-level packages: command execution ==="

check_run "openssl" openssl version

echo ""
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

check_file "libc.so"    /lib/${TRIPLET}/libc.so.6
check_file "libssl.so"  /usr/lib/${TRIPLET}/libssl.so.3

echo ""
echo "=== all packages: dpkg status ==="

# Packages that ship only libraries / data — verify dpkg status file
check_pkg "ca-certificates"
check_pkg "debconf"
check_pkg "gcc-14-base"
check_pkg "libc6"
check_pkg "libgcc-s1"
check_pkg "libssl3t64"
check_pkg "libzstd1"
check_pkg "openssl"
check_pkg "openssl-provider-legacy"
check_pkg "tzdata"
check_pkg "zlib1g"

echo ""
echo "=== results: $pass passed, $fail failed ==="
if [ "$fail" -gt 0 ]; then
  exit 1
fi
