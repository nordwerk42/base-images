# Maintenance scripts

## Update the base image

Re-resolves the Debian package closure of both architectures:

```sh
cd scripts/update && go run .
```

Needs Docker, `nix` and Go. It writes `config.amd64.json` and
`config.arm64.json`, then prints what moved. If a package cannot be fetched,
both configs are rolled back.

| Flag | |
| --- | --- |
| `-debianVersion 13` | Debian suite to resolve against |
| `-revertSnapshotOnly` | drop a config diff that only moved the snapshot date |
| `-failIfNoUpdate` | exit `3` when nothing is new (scheduled pipelines) |

```sh
cd scripts/update && go test ./...
```

## Test the images

Builds every variant and checks it against the image contract:

```sh
./scripts/test-images.sh
```

Checked per variant: the image is built for the expected architecture, runs as
`53111:53111` in `/home/nonroot`, ships the CA bundle, the timezone data, libc,
libssl and the dynamic linker with every symlink resolving, and the minimal
image has no shell while the debug image has busybox.

The checks read the built tarball, so both architectures can be tested on any
host. `test/test_toplevel_packages.sh` additionally runs inside the debug image
when Docker can execute that architecture. Exits non-zero if any check fails.

| Flag | |
| --- | --- |
| `-a amd64,arm64` | architectures to test (default: both) |
| `--no-docker` | skip the container smoke test |
| `--rmi` | remove the loaded images again |

```sh
./scripts/test-images.sh -a arm64 --rmi
```

## After an update

```sh
cd scripts/update && go run . && cd ../.. && ./scripts/test-images.sh
```
