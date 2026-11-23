# Upstream

| | |
|---|---|
| Source | https://gitlab.opencode.de/oci-community/images/zendis/base |
| Imported | branch `main` at `3e2f87d` (release 1.0.1) with all tags, on 2026-11-23 |
| Tooling | https://gitlab.opencode.de/oci-community/tools/container-hardening-work-bench at `9e5cecc` |
| License | MIT |

## Changes against upstream

| Change | Reason |
|---|---|
| Work bench fetched over HTTPS with a pinned revision | the SSH URL needs an account on gitlab.opencode.de; the repository is public |
| `.gitlab-ci.yml` and `.gitlab/` removed | the build runs on GitHub Actions (`.github/workflows/`) |
| `cosign.pub` removed | images here are signed keyless; the ZenDiS key does not sign them |
| README and SECURITY rewritten | registry, verification and reporting differ |

## Following upstream

The daily update job keeps the Debian packages current. Renovate keeps the GitHub Actions and the
`nixpkgs` lock current. The work bench pin and changes to the upstream package list or flake are
reviewed by hand and taken over as regular pull requests.
