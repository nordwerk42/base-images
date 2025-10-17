# Node.js Distroless Container Image

Minimal, secure, and reproducible Node.js container image built with Nix from Debian packages.

![CVSS Badge](https://api.devguard.opencode.de/api/v1/badges/cvss/239bdfa1-d6a8-4973-ab60-1c4f43a1c6fe)

## Features

- **Minimal**: Only essential Node.js runtime dependencies
- **Secure**: Distroless design, non-root user (UID 53111)
- **Reproducible**: Built with Nix flakes, pinned package versions
- **Multi-arch**: Supports `amd64` and `arm64`
- **Debug Variants**: Debug images with busybox shell for troubleshooting
- **SBOM**: Includes Software Bill of Materials for supply chain security
- **VEX**: Vulnerability Exploitability eXchange data generation
- **SSL/TLS Ready**: Includes CA certificates for HTTPS connections

## Quick Start

**See the [example/](./example/) directory** for a complete Node.js application using this image.

### Using the Image

This is a distroless image without package managers. Use a multi-stage build:

```dockerfile
# Builder stage: install dependencies
FROM node:20-bookworm-slim AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . ./

# Runtime stage: minimal distroless image
FROM registry.opencode.de/open-code/oci/nodejs:20
WORKDIR /app
COPY --from=builder --chown=53111:53111 /app /app
ENV NODE_ENV=production
CMD ["/usr/bin/node", "app.js"]
```


## Image Variants

### Standard Images
- `registry.opencode.de/open-code/oci/nodejs:20`
- `registry.opencode.de/open-code/oci/nodejs:22`
- `registry.opencode.de/open-code/oci/nodejs:20-amd64`
- `registry.opencode.de/open-code/oci/nodejs:20-arm64`
- `registry.opencode.de/open-code/oci/nodejs:22-amd64`
- `registry.opencode.de/open-code/oci/nodejs:22-arm64`

### Debug Images (with busybox shell)
For troubleshooting and debugging purposes, debug variants are available with a minimal busybox shell:
- `registry.opencode.de/open-code/oci/nodejs:20-debug`
- `registry.opencode.de/open-code/oci/nodejs:22-debug`
- `registry.opencode.de/open-code/oci/nodejs:20-amd64-debug`
- `registry.opencode.de/open-code/oci/nodejs:20-arm64-debug`
- `registry.opencode.de/open-code/oci/nodejs:22-amd64-debug`
- `registry.opencode.de/open-code/oci/nodejs:22-arm64-debug`

Debug images include:
- Busybox static binary at `/bin/busybox`
- Common shell utilities: `sh`, `ash`, `cat`, `ls`, `cp`, `mv`, `rm`, `mkdir`, `rmdir`, `ln`, `chmod`, `chown`, `grep`, `find`, `ps`, `top`
- Useful for inspecting the container filesystem and debugging runtime issues

**Example: Running a debug shell**
```bash
docker run -it --rm registry.opencode.de/open-code/oci/nodejs:22-debug sh
```

## Image Details

- **Base**: Debian Bookworm packages
- **Node.js Version**: 20.19.2 / 22.18.0
- **User**: `nonroot` (53111:53111)
- **Working Directory**: `/home/nonroot`
- **Dynamic Linker Symlinks**: 
  - `/lib/ld-linux-aarch64.so.1` → `/usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1`
  - `/lib64/ld-linux-x86-64.so.2` → `/usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2`