# GEOS 3.15 importer and renderer modernization verification

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
- Maldives fixture SHA-256: `45186a1286f21cd2b0b0c6c4566f7da3c8fcb4e4f746717920ba59d2826fc42f`.
- Maldives sorted table counts and SHA-256 hashes: 6/6 matched the established baseline.
- Geometry profiles: `hist_point`, `hist_line`, and `hist_polygon` matched.
- Polygon-center profile: matched (`0|84651|0|0|0`).
- Minor-version profiles: `hist_line` and `hist_polygon` matched.

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

## Maldives parity

Fixture SHA-256:

```text
45186a1286f21cd2b0b0c6c4566f7da3c8fcb4e4f746717920ba59d2826fc42f
```

Verification database:

```text
osm_history_geos_upgrade_maldives_315_final
```

All canonical sorted `COPY` streams matched:

| Table | Rows | SHA-256 | Result |
|---|---:|---|---|
| `hist_point` | 690,224 | `eca37b81f650ec3dd115570f0972c5b066eaf965a5431b87c82c49aa4e84d424` | PASS |
| `hist_line` | 73,587 | `d91a3a89cab93d61482a5823e5b3a291df13b0871fae3cb572ccdd3ccbe8247c` | PASS |
| `hist_polygon` | 84,651 | `ac213b2ee9d17dac0b1dfa407f5f235fb1e593ebd508039c3497cebd704d6e60` | PASS |
| `hist_relation` | 3,112 | `92dab89283889ff975d179ae3d37dda601ab737c4075dc768924e765655c387c` | PASS |
| `hist_relation_member` | 1,052,280 | `00e8540a019ffb9c78cbd048e0871049cd3bb059885fabc034e648acbade9e50` | PASS |
| `hist_user` | 1,472 | `78bfb6cc7763de923af8ed7c46cb2b6c3080cab80d480238de0ea2e1eedf5ace` | PASS |

Geometry and temporal-way profiles also matched the baseline:

| Check | Result tuple | Meaning |
|---|---|---|
| `hist_point` geometry | `637919|52305|0|0|0` | non-null, null, wrong type, wrong SRID, invalid |
| `hist_line` geometry | `73586|1|0|0|5` | non-null, null, wrong type, wrong SRID, invalid |
| `hist_polygon` geometry | `84645|6|0|0|929` | non-null, null, wrong type, wrong SRID, invalid |
| polygon center | `0|84651|0|0|0` | non-null, null, wrong type, wrong SRID, outside surface |
| line minor versions | `26591|10605|6521|26` | minor rows, distinct ways, zero-duration rows, maximum minor |
| polygon minor versions | `19765|10142|4132|35` | minor rows, distinct ways, zero-duration rows, maximum minor |

The non-zero invalid counts are pre-existing data characteristics and match the verified baseline exactly; they were not normalized or silently changed. Polygon centers are null because the reference import did not enable optional interior-point storage. The focused C++ test separately verifies point-on-surface behavior.

### Investigated mismatch

The first GEOS 3.15 import initially matched five hashes and differed only for `hist_line`. The first differing key was `(id=150618665, version=6, minor=0)`: geometry and every other field matched, while `z_order` was `9` instead of `5`.

The reference import used this fork's local trunk/motorway offset customization (`5`), but the fresh Git branch contained upstream offsets (`8`/`9`). Restoring the established fork values produced exact 6/6 parity. No output difference was accepted or normalized.

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

Coverage includes parsing, zoom sizing, safe SQL composition, parameterized date inference, modern PostGIS metadata discovery, view cleanup, Mapnik PNG output, Pillow-independent HTML generation, a two-frame animation CLI run, and a real Maldives/PostGIS render whose temporary views were verified absent afterward.

## Final static checks

- `git diff --check`: PASS
- no importer `#include <geos/...>` or `geos::` usage: PASS
- dynamic `libgeos_c.so.1` dependency: PASS
- no direct `libgeos.so` dependency: PASS
- installed and compatibility CLI `--help` checks: PASS
- generated binaries, environments, PBF files, credentials, and rendered outputs remain untracked/ignored: PASS

## Not run

A Greater London import/performance benchmark was not required for semantic acceptance and was not run. The deterministic Maldives gate and full renderer integration suite passed; the tutorial documents the order and evidence to capture if a large-region benchmark is run later.
