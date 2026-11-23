# base-images

Distroless OCI base images built from Debian 13 (trixie) packages with Nix.

This repository is a fork of [ZenDiS `base`](https://gitlab.opencode.de/oci-community/images/zendis/base)
and uses the [Container Hardening Work Bench](https://gitlab.opencode.de/oci-community/tools/container-hardening-work-bench).
The build idea and the tooling come from there. What differs here:

| | This fork |
|---|---|
| Rebuild | automatic: a daily job resolves the newest Debian snapshot and opens a pull request |
| Signature | keyless with Sigstore (GitHub OIDC identity of the build workflow, Rekor transparency log) |
| Provenance | SLSA build provenance attestation |
| SBOM | CycloneDX, attached to every image as an attestation |
| Scanning | Trivy and Grype on every build; accepted findings only via OpenVEX in `vex/` |
| Pins | every action by commit SHA, Renovate keeps them current |

See [docs/upstream.md](docs/upstream.md) for what was taken over and what was changed.

## Images

| Image | Content |
|---|---|
| `ghcr.io/nordwerk42/base:13-minimal` | glibc, OpenSSL, CA certificates, tzdata. No shell, no package manager. User `53111:53111`, working directory `/home/nonroot`. |

Tags: `13-minimal` (moves with every rebuild), `13-minimal-<debian-snapshot>` (for example `13-minimal-20261122T000000Z`) and `sha-<commit>`. `13` is the Debian release. Pin the digest in addition to the tag.

## Verify

```sh
IMAGE=ghcr.io/nordwerk42/base:13-minimal

cosign verify "$IMAGE" \
  --certificate-identity-regexp '^https://github\.com/nordwerk42/base-images/\.github/workflows/build\.yml@refs/heads/main$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

cosign verify-attestation "$IMAGE" --type cyclonedx \
  --certificate-identity-regexp '^https://github\.com/nordwerk42/base-images/\.github/workflows/build\.yml@refs/heads/main$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

gh attestation verify "oci://$IMAGE" --repo nordwerk42/base-images
```

## Build locally

```sh
nix build .#base-0-amd64          # image tarball (docker load < result)
nix build .#base-0-amd64-sbom     # CycloneDX SBOM
nix build .#base-debug-0-amd64    # same image plus busybox, for debugging
```

Replace `amd64` with `arm64` on an aarch64 machine.

## Update packages

```sh
git clone https://gitlab.opencode.de/oci-community/tools/container-hardening-work-bench.git ../container-hardening-work-bench
git -C ../container-hardening-work-bench checkout "$(jq -r '.nodes["container-hardening"].locked.rev' flake.lock)"
(cd scripts/update && go run . -config ../../config -revertSnapshotOnly)
```

The package list lives in `config.amd64.json` and `config.arm64.json`. Each package is pinned to a
snapshot.debian.org URL with its hash.

## License

MIT, see [LICENSE.md](LICENSE.md). Copyright of the original work: Zentrum für Digitale Souveränität
der Öffentlichen Verwaltung (ZenDiS) GmbH.
