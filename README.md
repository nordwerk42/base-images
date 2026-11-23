# Python3 hardened Image

![CVSS Badge](https://api.devguard.opencode.de/api/v1/public/edbe3483-e769-424c-bd25-b88b44164715/refs/main/artifacts/pkg%3Aoci%2Fpython3%3Frepository_url%3Dregistry.opencode.de%2Foci-community%2Fimages%2Fzendis%2Fpython3%26arch%3Damd64%26tag%3D3.13-main-minimal-amd64/badges/cvss/)

[Badge Programm Results](https://badges.opencode.de/de/?repositoryUrl=https%3A%2F%2Fgitlab.opencode.de%2Fopen-code%2Foci%2Fpython3)

This python3 image is the hardened container image provide to you by openCode. The image was hardened for you using the [Container Hardening guide](https://gitlab.opencode.de/oci-community/images/zendis/container-hardening-work-bench/-/blob/main/README.md?ref_type=heads) and [openCode DevGuard](https://devguard.opencode.de/)

## Why should i use this image?

This image was hardened and has less vulnerabilities, than the normal python3 image. By using this image you can be sure, that the vulnerabilities, which are present in the standard python3 image are mitigated following the best practices described in the [Container Hardening guide](https://gitlab.opencode.de/oci-community/images/zendis/container-hardening-work-bench/-/blob/main/README.md?ref_type=heads)

## Which tags are available?

You can find all available tags in the [projects container registry](https://gitlab.opencode.de/oci-community/images/zendis/python3/container_registry/2652).

### Standard Image

For troubleshooting and debugging purposes, Standard variants are available with a minimal busybox shell:

- `registry.opencode.de/oci-community/images/zendis/python3:3.10`
- `registry.opencode.de/oci-community/images/zendis/python3:3.11`
- `registry.opencode.de/oci-community/images/zendis/python3:3.12`
- `registry.opencode.de/oci-community/images/zendis/python3:3.13`
- `registry.opencode.de/oci-community/images/zendis/python3:3.14`

Standard images include:

- Busybox static binary at `/bin/busybox`
- Common shell utilities: `sh`, `ash`, `cat`, `ls`, `cp`, `mv`, `rm`, `mkdir`, `rmdir`, `ln`, `chmod`, `chown`, `grep`, `find`, `ps`, `top`
- Useful for inspecting the container filesystem and debugging runtime issues

### Minimal Image

- `registry.opencode.de/oci-community/images/zendis/python3:3.10-minimal`
- `registry.opencode.de/oci-community/images/zendis/python3:3.11-minimal`
- `registry.opencode.de/oci-community/images/zendis/python3:3.12-minimal`
- `registry.opencode.de/oci-community/images/zendis/python3:3.13-minimal`
- `registry.opencode.de/oci-community/images/zendis/python3:3.14-minimal`

Minimal images contain the CPython interpreter, its runtime libraries, and the
supporting Debian data packages (no shell).

## How do I verify this image?

### 1. Pin the digest for integrity

You should pin the digest `@sha256:...` in addition of your tag to ensure integrity.

### 2. Verify the image signature with Cosign

Verify the authenticity and integrity of the image:

```sh
cosign verify registry.opencode.de/oci-community/images/zendis/python3:3.11 --key cosign.pub --insecure-ignore-tlog=true
```

**Public Key:**

```
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEXdVDz6n39PDj9ZezqYgmZ/qCDV4h
bQwmuDfxix8BMRTZB9UHcOX4EgmAHWyXsbANB6tG8XWoqFpYRReNUvsG6g==
-----END PUBLIC KEY-----
```

### 3. Review attestations and reports

- SBOM
- VeX
- Build Provenance
- Badge Programm Report (SARIF)
- Test Results (SARIF)

- Current Vulnerability Exploitability Exchange (VeX):

  - [python3:3.11-main-amd64](https://api.devguard.opencode.de/api/v1/public/edbe3483-e769-424c-bd25-b88b44164715/refs/main/artifacts/pkg%3Aoci%2Fpython3%3Frepository_url%3Dregistry.opencode.de%2Foci-community%2Fimages%2Fzendis%2Fpython3%26arch%3Damd64%26tag%3D3.11-main-amd64/vex.json/)
  - [python3:3.13-main-amd64](https://api.devguard.opencode.de/api/v1/public/edbe3483-e769-424c-bd25-b88b44164715/refs/main/artifacts/pkg%3Aoci%2Fpython3%3Frepository_url%3Dregistry.opencode.de%2Foci-community%2Fimages%2Fzendis%2Fpython3%26arch%3Damd64%26tag%3D3.13-main-amd64/vex.json/)

- Current Software Bill of Materials (SBOM):

  - [python3:3.11-main-amd64](https://api.devguard.opencode.de/api/v1/public/edbe3483-e769-424c-bd25-b88b44164715/refs/main/artifacts/pkg%3Aoci%2Fpython3%3Frepository_url%3Dregistry.opencode.de%2Foci-community%2Fimages%2Fzendis%2Fpython3%26arch%3Damd64%26tag%3D3.11-main-amd64/sbom.json/)
  - [python3:3.13-main-amd64](https://api.devguard.opencode.de/api/v1/public/edbe3483-e769-424c-bd25-b88b44164715/refs/main/artifacts/pkg%3Aoci%2Fpython3%3Frepository_url%3Dregistry.opencode.de%2Foci-community%2Fimages%2Fzendis%2Fpython3%26arch%3Damd64%26tag%3D3.13-main-amd64/sbom.json/)

- Current [Badge Programm Results](https://badges.opencode.de/?repositoryUrl=https%3A%2F%2Fgitlab.opencode.de%2Foci-community%2Fimages%2Fzendis%2Fpython3)

## How was this image hardened?

1. The image is scanned for vulnerabilities using [openCode DevGuard](https://devguard.opencode.de/).
2. A secure build is being performed supported by the [Container Hardening Work Bench](https://gitlab.opencode.de/oci-community/images/zendis/container-hardening-work-bench) tools.
3. The vulnerabilities found are reviewed and mitigated. This process is transparently documented in the openCode DevGuard Image Repository.
4. After the mitigation process, the vulnerability scan is run again.
5. If no unhandled vulnerabilities are found, the hardened image is released. [Shared Container Images - Group](https://gitlab.opencode.de/open-code/oci).

A detailed description of the process can be found in the [DevGuard Documentation](https://devguard.org/concept-guides/container-hardening/process)

To assure, that the image is hardened, matching the openCode process, we followed the [Container Hardening guide](https://gitlab.opencode.de/oci-community/images/zendis/container-hardening-work-bench/-/blob/main/README.md?ref_type=heads).

## Where does Python come from?

Debian ships only one Python version per release, so the interpreter is not
taken from Debian. It is built from the upstream CPython release tarball
(`https://www.python.org/ftp/python/`, pinned by hash in `flake.nix`) using the
nixpkgs build recipe, then installed under `/usr` and relinked against the
Debian rootfs: `--set-interpreter` to Debian's loader and `--set-rpath` to
`/usr/lib/<triplet>`. Everything CPython links against — glibc, OpenSSL,
SQLite, ncurses, readline, libffi, mpdecimal, gdbm, zlib, bzip2, lzma, zstd,
expat, uuid, crypt — comes from the pinned Debian snapshot, and so do
`ca-certificates`, `tzdata`, `media-types` and `netbase`.

The image contains no Nix store paths; the build enforces this with
`allowedReferences = [ ]`.

Because CPython is relinked onto Debian's glibc, the nixpkgs pin must not be
newer than Debian's glibc (2.41 on Debian 13). `nixos-25.11` provides glibc
2.40 and is pinned for that reason — glibc 2.42 re-versions the termios
`cf*speed` symbols, which Debian 13 cannot resolve.

Run `./update-python-sources.sh` to check for newer CPython patch releases; it
prints the `pythonSources` block to copy into `flake.nix`.

## Notable Details

- **User**: nonroot (53111:53111)
- **Python prefix**: `/usr` — `python3` resolves via `/usr/bin/python3`,
  `/usr/local/bin/python3` and `/usr/bin/python3.<minor>`
- **SBOM**: the interpreter is listed as
  `pkg:github.com/python/cpython@v<version>`; every other component is a
  `pkg:deb/debian/...` package
