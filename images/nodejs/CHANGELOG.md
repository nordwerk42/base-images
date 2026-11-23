# Changelog

Notable changes to the hardened Node.js image, newest first. Headings are the
Git tags of this repository.

Package versions apply to both `amd64` and `arm64`. The
[VeX and SBOM attestations](./README.md#3-review-attestations-and-reports) are
published per tag and are the authoritative record of what an image contains.

## oc.13 — 2026-09-18

### Changed

- Node.js 26: `26.8.2` → `26.9.0` — see the
  [upstream changelog](https://github.com/nodejs/node/blob/main/doc/changelogs/CHANGELOG_V26.md#26.9.0).
  Node.js 24 stays on `24.21.0`.
- The Debian package closure was re-resolved against the `20260918T000000Z`
  snapshot (only the snapshot URLs advanced).
- Build toolchain refreshed: newer `container-hardening-work-bench`, `devguard`
  and `nixpkgs` revisions.

## oc.12 — 2026-09-14

### Removed

- **The minimal images (`:24-minimal`, `:26-minimal`) no longer contain `npm`,
  `npx` or `corepack`.** They ship the Node.js runtime and nothing else, which
  drops 144 of the 165 components the minimal SBOM used to list.

  The standard images (`:24`, `:26`) still carry npm and npx.

  **Breaking if your container runs npm at runtime** (`npm start`, say): call
  `node` directly, or use the standard image. Installing dependencies in a
  builder stage and copying the result in keeps working — see
  [example/Containerfile](./example/Containerfile).

  Thanks to Philipp Schoenbach for reporting this.

### Security

Debian packages re-resolved against the Debian 13.7 point release:

| Package | From | To |
| --- | --- | --- |
| `libpcre2-8-0` | `10.46-1~deb13u1` | `10.46-1~deb13u2` |
| `libc6` | `2.41-12+deb13u3` | `2.41-12+deb13u4` |
| `libcap2` | `1:2.75-10+deb13u1+b1` | `1:2.75-10+deb13u1+b3` |

### Changed

- Node.js 24: `24.20.0` → `24.21.0`, Node.js 26: `26.8.1` → `26.8.2`. Both
  bundle OpenSSL 3.5.8; neither was published as a security release.

### Fixed

- The package refresh (`scripts/update`) now picks up fixed versions of
  transitive dependencies. It only ran `apt-get install`, which leaves an
  already-installed dependency alone as long as it still satisfies every
  version constraint, so packages inherited from the base image —
  `libpcre2-8-0` among them — stayed pinned to whatever that image shipped. The
  fix is in the `container-hardening-work-bench` resolver and applies to every
  image built with it; configs refreshed before it may be understating package
  versions.
- `scripts/test-images.sh` asserted the wrong architecture name on `amd64`, so
  every `-a amd64` run failed on that check alone.

## oc.11 — 2026-09-08

### Added

- Node.js 24 (Active LTS) alongside Node.js 26 (Current), both for `amd64` and
  `arm64` in the standard and minimal variants.
- `scripts/update`, a Go tool that refreshes the Debian package closure and the
  Node.js pins in one pass and reports what moved.
- `scripts/test-images.sh`, which builds each variant, loads it into Docker and
  smoke tests it.

### Changed

- Node.js 26: `26.7.0` → `26.8.1`. Node.js 24 enters at `24.20.0`.
- Node.js versions are pinned per stream in a `nodejsSources` attribute set in
  `flake.nix` instead of being hardcoded in the build.
- The Debian package set is shared by all streams: `config.26.<arch>.json`
  became `config.<arch>.json`.
- The SBOM records the runtime as `pkg:github.com/nodejs/node@v<version>`.
