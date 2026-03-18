# Base Distroless Container Image

![CVSS Badge](https://api.devguard.opencode.de/api/v1/public/b9ee43d9-b565-4c2e-bbd7-c1e7fcfea6ea/refs/main/artifacts/pkg%3Aoci%2Fbase%3Frepository_url%3Dregistry.opencode.de%2Foci-community%2Fimages%2Fzendis%2Fbase%26arch%3Damd64%26tag%3Dmain-amd64/badges/cvss/)

[Badge Programm Results](https://badges.opencode.de/?repositoryUrl=https%3A%2F%2Fgitlab.opencode.de%2Foci-community%2Fimages%2Fzendis%2Fbase)

This base image is the hardened container image provide to you by openCode. The image was hardened for you using the [Container Hardening guide](https://gitlab.opencode.de/oci-community/tools/container-hardening-work-bench/-/blob/main/README.md?ref_type=heads) and [openCode DevGuard](https://devguard.opencode.de/)

## Why should I use this image?

This image was hardened and has less vulnerabilities, than the normal base image. By using this image you can be sure, that the vulnerabilities, which are present in the standard base image are mitigated following the best practices described in the [Container Hardening guide](https://gitlab.opencode.de/oci-community/tools/container-hardening-work-bench/-/blob/main/README.md?ref_type=heads)

## Which tags are available?

You can find all available tags in the [projects container registry](https://gitlab.opencode.de/oci-community/images/zendis/base/container_registry/2662).

### Standard Image

For troubleshooting and debugging purposes, Standard variants are available with a minimal busybox shell:

- `registry.opencode.de/oci-community/images/zendis/base:1.0.0-rc.2`

Standard images include:

- Busybox static binary at `/bin/busybox`
- Common shell utilities: `sh`, `ash`, `cat`, `ls`, `cp`, `mv`, `rm`, `mkdir`, `rmdir`, `ln`, `chmod`, `chown`, `grep`, `find`, `ps`, `top`
- Useful for inspecting the container filesystem and debugging runtime issues

### Minimal Image

- `registry.opencode.de/oci-community/images/zendis/base:1.0.0-rc.2-minimal`

## How do I verify this image?

### 1. Pin the digest for integrity

You should pin the digest `@sha256:...` in addition of your tag to ensure integrity.

### 2. Verify the image signature with Cosign

Verify the authenticity and integrity of the image:

```sh
cosign verify registry.opencode.de/oci-community/images/zendis/base:1.0.0-rc.2 --key cosign.pub --insecure-ignore-tlog=true
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

  - [base:main-amd64](https://api.devguard.opencode.de/api/v1/public/b9ee43d9-b565-4c2e-bbd7-c1e7fcfea6ea/refs/main/artifacts/pkg%3Aoci%2Fbase%3Frepository_url%3Dregistry.opencode.de%2Foci-community%2Fimages%2Fzendis%2Fbase%26arch%3Damd64%26tag%3Dmain-amd64/vex.json/)
  - [base:main-arm64](https://api.devguard.opencode.de/api/v1/public/b9ee43d9-b565-4c2e-bbd7-c1e7fcfea6ea/refs/main/artifacts/pkg%3Aoci%2Fbase%3Frepository_url%3Dregistry.opencode.de%2Foci-community%2Fimages%2Fzendis%2Fbase%26arch%3Darm64%26tag%3Dmain-arm64/vex.json/)

- Current Software Bill of Materials (SBOM):

  - [base:main-amd64](https://api.devguard.opencode.de/api/v1/public/b9ee43d9-b565-4c2e-bbd7-c1e7fcfea6ea/refs/main/artifacts/pkg%3Aoci%2Fbase%3Frepository_url%3Dregistry.opencode.de%2Foci-community%2Fimages%2Fzendis%2Fbase%26arch%3Damd64%26tag%3Dmain-amd64/sbom.json/)
  - [base:main-arm64](https://api.devguard.opencode.de/api/v1/public/b9ee43d9-b565-4c2e-bbd7-c1e7fcfea6ea/refs/main/artifacts/pkg%3Aoci%2Fbase%3Frepository_url%3Dregistry.opencode.de%2Foci-community%2Fimages%2Fzendis%2Fbase%26arch%3Darm64%26tag%3Dmain-arm64/sbom.json/)

## How was this image hardened?

1. The image is scanned for vulnerabilities using [openCode DevGuard](https://devguard.opencode.de/).
2. A secure build is being performed supported by the [Container Hardening Work Bench](https://gitlab.opencode.de/oci-community/tools/container-hardening-work-bench) tools.
3. The vulnerabilities found are reviewed and mitigated. This process is transparently documented in the openCode DevGuard Image Repository.
4. After the mitigation process, the vulnerability scan is run again.
5. If no unhandled vulnerabilities are found, the hardened image is released. [Shared Container Images - Group](https://gitlab.opencode.de/open-code/oci).

A detailed description of the process can be found in the [DevGuard Documentation](https://devguard.org/concept-guides/container-hardening/process)

To assure, that the image is hardened, matching the openCode process, we followed the [Container Hardening guide](https://gitlab.opencode.de/oci-community/tools/container-hardening-work-bench/-/blob/main/README.md?ref_type=heads).

## Notable Details

- **User**: nonroot (53111:53111)
- **Working Directory**: `/home/nonroot`
- **Dynamic Linker Symlinks**: 
  - `/lib/ld-linux-aarch64.so.1` → `/usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1`
  - `/lib64/ld-linux-x86-64.so.2` → `/usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2`