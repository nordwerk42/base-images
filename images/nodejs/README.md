# Node.js Distroless Container Image

![CVSS Badge](https://api.devguard.opencode.de/api/v1/public/0451b5eb-2618-4504-a75a-a4ea440d5634/refs/main/artifacts/pkg%3Aoci%2Fnodejs%3Frepository_url%3Dregistry.opencode.de%2Foci-community%2Fimages%2Fzendis%2Fnodejs%26arch%3Damd64%26tag%3D26-main-minimal-amd64/badges/cvss/)

[Badge Programm Results](https://badges.opencode.de/?repositoryUrl=https%3A%2F%2Fgitlab.opencode.de%2Foci-community%2Fimages%2Fzendis%2Fnodejs)

This node.js image is the hardened container image provide to you by openCode. The image was hardened for you using the [Container Hardening guide](https://gitlab.opencode.de/oci-community/tools/container-hardening-work-bench/-/blob/main/README.md?ref_type=heads) and [openCode DevGuard](https://devguard.opencode.de/)

## Why should i use this image?

This image was hardened and has less vulnerabilities, than the normal node.js image. By using this image you can be sure, that the vulnerabilities, which are present in the standard node.js image are mitigated following the best practices described in the [Container Hardening guide](https://gitlab.opencode.de/oci-community/tools/container-hardening-work-bench/-/blob/main/README.md?ref_type=heads)

> **Notice:** Node.js 20 has reached End of Life and is no longer officially supported as an LTS release. Images for Node.js 20 are no longer provided. Please migrate to Node.js 24 (Active LTS) or Node.js 26 (Current).

## Which tags are available?

You can find all available tags in the [projects container registry](https://gitlab.opencode.de/oci-community/images/zendis/nodejs/container_registry/2659).

### Standard Image

For troubleshooting and debugging purposes, Standard variants are available with a minimal busybox shell:

- `registry.opencode.de/oci-community/images/zendis/nodejs:24`
- `registry.opencode.de/oci-community/images/zendis/nodejs:26`

Standard images include:

- Busybox static binary at `/bin/busybox`
- Common shell utilities: `sh`, `ash`, `cat`, `ls`, `cp`, `mv`, `rm`, `mkdir`, `rmdir`, `ln`, `chmod`, `chown`, `grep`, `find`, `ps`, `top`
- `npm` and `npx`
- Useful for inspecting the container filesystem and debugging runtime issues

### Minimal Image

- `registry.opencode.de/oci-community/images/zendis/nodejs:24-minimal`
- `registry.opencode.de/oci-community/images/zendis/nodejs:26-minimal`

Minimal images ship the Node.js runtime and nothing else: no shell, and no
`npm`, `npx` or `corepack`. Install your dependencies in a builder stage and
copy the result in — see [example/Containerfile](./example/Containerfile).

If your entrypoint shells out to `npm` at runtime (`npm start`, say), call
`node` directly or use the standard image instead.

## How do I verify this image?

### 1. Pin the digest for integrity

You should pin the digest `@sha256:...` in addition of your tag to ensure integrity.

### 2. Verify the image signature with Cosign

Verify the authenticity and integrity of the image:

```sh
cosign verify registry.opencode.de/oci-community/images/zendis/nodejs:26 --key cosign.pub --insecure-ignore-tlog=true
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

  - [nodejs:26-main-amd64](https://api.devguard.opencode.de/api/v1/public/0451b5eb-2618-4504-a75a-a4ea440d5634/refs/main/artifacts/pkg%3Aoci%2Fnodejs%3Frepository_url%3Dregistry.opencode.de%2Foci-community%2Fimages%2Fzendis%2Fnodejs%26arch%3Damd64%26tag%3D26-main-amd64/vex.json/)

- Current Software Bill of Materials (SBOM):

  - [nodejs:26-main-amd64](https://api.devguard.opencode.de/api/v1/public/0451b5eb-2618-4504-a75a-a4ea440d5634/refs/main/artifacts/pkg%3Aoci%2Fnodejs%3Frepository_url%3Dregistry.opencode.de%2Foci-community%2Fimages%2Fzendis%2Fnodejs%26arch%3Damd64%26tag%3D26-main-amd64/sbom.json/)

- Current [Badge Programm Results](https://badges.opencode.de/?repositoryUrl=https%3A%2F%2Fgitlab.opencode.de%2Foci-community%2Fimages%2Fzendis%2Fnodejs)

## How was this image hardened?

1. The image is scanned for vulnerabilities using [openCode DevGuard](https://devguard.opencode.de/).
2. A secure build is being performed supported by the [Container Hardening Work Bench](https://gitlab.opencode.de/oci-community/tools/container-hardening-work-bench) tools.
3. The vulnerabilities found are reviewed and mitigated. This process is transparently documented in the openCode DevGuard Image Repository.
4. After the mitigation process, the vulnerability scan is run again.
5. If no unhandled vulnerabilities are found, the hardened image is released. [OCI Community Images - Group](https://gitlab.opencode.de/oci-community/images).

A detailed description of the process can be found in the [DevGuard Documentation](https://devguard.org/concept-guides/container-hardening/process)

To assure, that the image is hardened, matching the openCode process, we followed the [Container Hardening guide](https://gitlab.opencode.de/oci-community/tools/container-hardening-work-bench/-/blob/main/README.md?ref_type=heads).

## Notable Details

- User: nonroot (53111:53111)
- **SBOM**: the runtime is listed as `pkg:github.com/nodejs/node@v<version>`
