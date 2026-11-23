# Maintenance scripts

## Update the pins

Refreshes both Debian package configs and the Node.js release of every stream:

```sh
cd scripts/update && go run .
```

Needs Docker (Debian resolution), `nix` and Go. It writes `config.amd64.json`,
`config.arm64.json` and the `nodejsSources` block in `flake.nix`, then prints
what moved. If a package cannot be fetched, both configs are rolled back.

| Flag | |
| --- | --- |
| `-streams 24` | only these streams |
| `-skipDebian` | leave the configs alone |
| `-skipNode` | leave the pins alone |
| `-prefetch` | hash tarballs with `nix-prefetch-url` instead of `SHASUMS256.txt` |
| `-revertSnapshotOnly` | drop a config diff that only moved the snapshot date |
| `-failIfNoUpdate` | exit `3` when nothing is new (scheduled pipelines) |

```sh
cd scripts/update && go run . -streams 26 -skipDebian   # one stream only
cd scripts/update && go test ./...                      # test the updater
```

## Test the images

Builds every variant, loads it into Docker and smoke tests it:

```sh
./scripts/test-images.sh
```

Needs `nix` and Docker. Defaults to every stream in `flake.nix` on the host
architecture. Exits non-zero if any check fails.

| Flag | |
| --- | --- |
| `-v 24,26` | only these streams |
| `-a amd64,arm64` | these architectures (foreign ones need emulation) |
| `--rmi` | remove the loaded images again |

```sh
./scripts/test-images.sh -v 26 -a arm64 --rmi
```

## After an update

```sh
cd scripts/update && go run . && cd ../.. && ./scripts/test-images.sh
```
