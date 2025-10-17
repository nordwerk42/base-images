# Base Distroless Container Image

Minimal, secure, and reproducible base container image built with Nix from Debian packages. Contains only openssl, ca-certificates, glibc and timezone data.

![CVSS Badge](https://api.devguard.opencode.de/api/v1/badges/cvss/239bdfa1-d6a8-4973-ab60-1c4f43a1c6fe)

## Features

- **Minimal**: Only essential runtime dependencies
- **Secure**: Distroless design, non-root user (UID 53111)
- **Reproducible**: Built with Nix flakes, pinned package versions
- **Multi-arch**: Supports `amd64` and `arm64`
- **Debug Variants**: Debug images with busybox shell for troubleshooting
- **SBOM**: Includes Software Bill of Materials for supply chain security
- **VEX**: Vulnerability Exploitability eXchange data generation
- **SSL/TLS Ready**: Includes CA certificates for HTTPS connections

## Quick Start

**See the [example/](./example/) directory** for a complete application using this image.


## Image Variants

### Standard Images
- `registry.opencode.de/open-code/oci/base:latest` - Multi-arch manifest (amd64 & arm64)
- `registry.opencode.de/open-code/oci/base:amd64` - AMD64/x86_64 specific
- `registry.opencode.de/open-code/oci/base:arm64` - ARM64/aarch64 specific

### Debug Images (with busybox shell)
For troubleshooting and debugging purposes, debug variants are available with a minimal busybox shell:
- `registry.opencode.de/open-code/oci/base:latest-debug` - Multi-arch manifest (amd64 & arm64)
- `registry.opencode.de/open-code/oci/base:amd64-debug` - AMD64/x86_64 debug variant
- `registry.opencode.de/open-code/oci/base:arm64-debug` - ARM64/aarch64 debug variant

Debug images include:
- Busybox static binary at `/bin/busybox`
- Common shell utilities: `sh`, `ash`, `cat`, `ls`, `cp`, `mv`, `rm`, `mkdir`, `rmdir`, `ln`, `chmod`, `chown`, `grep`, `find`, `ps`, `top`
- Useful for inspecting the container filesystem and debugging runtime issues

**Example: Running a debug shell**
```bash
docker run -it --rm registry.opencode.de/open-code/oci/base:latest-debug sh
```

## Image Details

- **User**: `nonroot` (53111:53111)
- **Working Directory**: `/home/nonroot`
- **Dynamic Linker Symlinks**: 
  - `/lib/ld-linux-aarch64.so.1` → `/usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1`
  - `/lib64/ld-linux-x86-64.so.2` → `/usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2`