# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-09-18

First stable release.

### Added

- Hardened static distroless image, built with Nix for `amd64` and `arm64`.
- Standard variant with a static busybox shell for debugging, and a `-minimal` variant without it.
- Bundled `ca-certificates` and `tzdata`, nonroot user (53111:53111) and a standard Linux directory layout.
- Cosign signatures, SBOM, VEX and build provenance attestations published per image.
