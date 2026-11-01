# OSM history importer and renderer modernization verification

Date: 2026-10-30
Branch: `upgrade/geos-3.15-mapnik-4.3.2`
Starting commit: `b4afda8`
Delivery state: verified modernization prepared for publication

## Toolchain

| Component | Verified version |
|---|---|
| GEOS | 3.15.0 |
| libosmium | 2.23.1 |
| Renderer Python | 3.12.16 |
| Mapnik Python | 4.3.2 |
| Psycopg | 3.3.4 |
| Pillow | 13.0.0 |
| PostgreSQL | 15.4 |
| PostGIS | 3.4.0 |

The separate latest-stable compatibility gate used PostgreSQL 18.6 and PostGIS 3.7.0; the PostgreSQL 15.4/PostGIS 3.4.0 rows above describe the original local modernization baseline.

## PostgreSQL 18.6 / PostGIS 3.7.0 compatibility gate

`scripts/verify-latest-postgis.sh` completed successfully in a disposable, Unix-socket-only cluster on port 55438. The runner stopped the cluster through its exit trap and did not modify the persistent local PostgreSQL service.

- Database identity: PostgreSQL 18.6 / PostGIS 3.7.0.
- Tracked importer fixtures: 10/10 passed.

The final runner output was `Latest stable PostgreSQL/PostGIS compatibility gate passed.`

## Importer migration

- Replaced all GEOS C++ includes and `geos::` types with `geos_c.h` and reentrant `_r` calls.
- Added context-bound RAII for geometries and coordinate sequences.
- Preserved extended little-endian WKB with SRID 3857, polygon area, line/polygon classification, and optional point-on-surface calculation.
- Replaced hard-coded compiler/library paths with environment-discovered libpq and GEOS flags.
- The binary's dynamic dependency is `libgeos_c.so.1`; it has no direct `libgeos.so` dependency.
- `make -C importer clean all test` completed without project-source warnings.
- The focused GEOS test passed for polygon construction, type, area, EWKB/SRID, and point-on-surface.
- All 10 tracked `.osh` fixtures imported successfully through the guarded fixture runner.
- A compatibility check caught a `z_order` regression in the fresh branch. Restoring this fork's established trunk/motorway offset (`5`) preserved the intended behavior.

## Renderer modernization

- Retained executable `renderer/render.py` and `renderer/render-animation.py` wrappers.
- Added `osm-history-render` and `osm-history-render-animation` console commands.
- Replaced optparse/Psycopg 2/string-formatted SQL with argparse, dataclasses, pathlib, Psycopg 3 SQL composition, quoted identifiers, and parameterized bbox queries.
- Removed direct writes to the PostGIS `geometry_columns` view.
- Added default `try/finally` cleanup of temporary history views and explicit `--retain-views` opt-in.
- Replaced GraphicsMagick labels with Pillow.
- Replaced jQuery/jQuery UI animation output with self-contained HTML and browser-native JavaScript.
- Replaced the hard-coded zoom scale table with Web Mercator resolution calculation.

Final renderer suite:

```text
20 passed
```

Coverage includes parsing, zoom sizing, safe SQL composition, parameterized date inference, modern PostGIS metadata discovery, view cleanup, Mapnik PNG output, Pillow-independent HTML generation, a two-frame animation CLI run, and a real PostGIS/Mapnik render whose temporary views were verified absent afterward.

## Final static checks

- `git diff --check`: PASS
- no importer `#include <geos/...>` or `geos::` usage: PASS
- dynamic `libgeos_c.so.1` dependency: PASS
- no direct `libgeos.so` dependency: PASS
- installed and compatibility CLI `--help` checks: PASS
- generated binaries, environments, PBF files, credentials, and rendered outputs remain untracked/ignored: PASS

## Not run

A large-region import/performance benchmark was not required for semantic acceptance and was not run. The tracked importer fixtures and full renderer integration suite passed; the tutorial documents the order and evidence to capture if a large-region benchmark is run later.
