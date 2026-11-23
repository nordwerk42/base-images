# Decisions

Newest first.

| Date | Decision | Why |
|---|---|---|
| 2026-11-23 | Tags `latest` and `stable`. `stable` follows `latest` after 3 days with a clean rescan of the SBOM, or at once by a manual run of `promote`. | Production pins a tested image; fixes can still go out the same day. |
| 2026-11-23 | Debian 13 is the base of every image. A runtime that Debian 13 does not ship in the needed version (for example newer CPython or Node.js) is built from the upstream release on the Debian root filesystem and listed as its own SBOM component, as upstream does. Debian 14 follows when upstream moves. | Same base as upstream, security support until about 2030, reproducible package pins, scanners match Debian packages. |
| 2026-11-23 | Fork of ZenDiS `base`, built on GitHub Actions, signed keyless, rootless. | See [upstream.md](upstream.md). |
