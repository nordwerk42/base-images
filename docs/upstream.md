# Upstream

| | |
|---|---|
| Source | https://gitlab.opencode.de/oci-community/images/zendis/base |
| Imported | branch `main` at `3e2f87d` (release 1.0.1) with all tags, on 2026-11-23 |
| Tooling | https://gitlab.opencode.de/oci-community/tools/container-hardening-work-bench at `9e5cecc` |
| License | MIT |

## Runtime images

`images/static`, `images/python3` and `images/nodejs` are `git subtree` imports (squashed) of the ZenDiS
projects of the same name, branch `main`, on 2026-11-23. Each keeps its upstream README, CHANGELOG and license.

| Directory | Source | Builds here |
|---|---|---|
| `images/static` | https://gitlab.opencode.de/oci-community/images/zendis/static | `static` |
| `images/python3` | https://gitlab.opencode.de/oci-community/images/zendis/python3 | CPython 3.13 and 3.14 on the Debian 13 root filesystem |
| `images/nodejs` | https://gitlab.opencode.de/oci-community/images/zendis/nodejs | Node.js 24 and 26 on the Debian 13 root filesystem |

Take over upstream changes with

```sh
git subtree pull --squash --prefix images/python3 https://gitlab.opencode.de/oci-community/images/zendis/python3.git main
```

and redo the HTTPS change below if the flake inputs changed.

## Changes against upstream

| Change | Reason |
|---|---|
| Work bench fetched over HTTPS with a pinned revision | the SSH URL needs an account on gitlab.opencode.de; the repository is public |
| `.gitlab-ci.yml` and `.gitlab/` removed | the build runs on GitHub Actions (`.github/workflows/`) |
| `cosign.pub` removed | images here are signed keyless; the ZenDiS key does not sign them |
| Runtime images: `.gitlab-ci.yml`, `.gitlab/`, `cosign.pub` removed; flake inputs (work bench, DevGuard scanner) over HTTPS at the locked revision | as for `base` |
| Runtime SBOMs get a CPE for CPython and Node.js in CI (`scripts/ci/prepare-sbom.sh`) | upstream lists them with a `pkg:github.com/...` purl only, which no scanner matches against advisories |
| README and SECURITY rewritten | registry, verification and reporting differ |

## Following upstream

The daily update job keeps the Debian packages current. Renovate keeps the GitHub Actions and the
`nixpkgs` lock current. The work bench pin and changes to the upstream package list or flake are
reviewed by hand and taken over as regular pull requests.
