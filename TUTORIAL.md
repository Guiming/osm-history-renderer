# Modern setup, import, render, and verification guide

This guide replaces the former Debian 6/Ubuntu 12 instructions. It uses isolated environments and an empty test database so system libraries and verified baseline databases remain untouched.

## 1. Prerequisites

Install or provide:

- Git
- Micromamba (or an equivalent Conda-compatible client)
- PostgreSQL 15+ with PostGIS, hstore, and btree_gist
- at least enough disk for the raw history extract, imported tables, indexes, and temporary database work
- a Mapnik XML style whose datasource table names use the selected view prefix

The checked-in environments pin the versions used for this modernization:

- importer: GEOS 3.15.0 and libosmium 2.23.1
- renderer: Python 3.12 and Mapnik 4.3.2

## 2. Create isolated environments

From the repository root:

```bash
micromamba create -y \
  -p "$HOME/.local/share/osm-history-geos315" \
  -f environment-importer.yml

micromamba create -y \
  -p "$HOME/.local/share/osm-history-renderer-modern" \
  -f environment-renderer.yml
```

Verify the main versions:

```bash
micromamba run -p "$HOME/.local/share/osm-history-geos315" \
  geos-config --version

micromamba run -p "$HOME/.local/share/osm-history-renderer-modern" \
  python -c "import importlib.metadata; print(importlib.metadata.version('mapnik'))"
```

Expected values are `3.15.0` and `4.3.2`.

For VS Code, select:

```text
~/.local/share/osm-history-renderer-modern/bin/python
```

Run C++ builds through the importer environment rather than changing system include/library paths.

## 3. Build and test the importer

```bash
micromamba run -p "$HOME/.local/share/osm-history-geos315" \
  make -C importer clean all test
```

Confirm the binary uses the GEOS C library and no project source uses the removed C++ API:

```bash
ldd importer/osm-history-importer | grep geos
rg -n '#include <geos/|geos::' importer \
  --glob '*.cpp' --glob '*.hpp'
```

`ldd` should show `libgeos_c`; the `rg` command should produce no matches.

## 4. Install and test the renderer

Install this checkout in editable mode:

```bash
micromamba run -p "$HOME/.local/share/osm-history-renderer-modern" \
  python -m pip install --no-deps -e .
```

Run the portable tests:

```bash
micromamba run -p "$HOME/.local/share/osm-history-renderer-modern" \
  pytest -q
```

To include the PostGIS and Mapnik integration tests, point them at a disposable imported database:

```bash
OSM_HISTORY_TEST_DSN="host=/path/to/postgres/socket port=5432 dbname=osm_history_test" \
micromamba run -p "$HOME/.local/share/osm-history-renderer-modern" \
  pytest -q
```

The integration tests create uniquely prefixed views and remove them in `finally` cleanup.

## 5. Obtain and record history data

The importer requires history data (`.osh` or `.osh.pbf`), not an ordinary current-state `.osm.pbf` extract.

Geofabrik's public extracts omit contributor identifiers. Full-metadata history files are available to OpenStreetMap contributors through Geofabrik's authenticated internal server and are subject to data-protection requirements. Use the authenticated provider workflow in a browser or a provider-supported credential store; do not put an OSM password, cookie, token, or signed URL in this repository, shell history, documentation, or test output.

After downloading, record provenance outside the dataset itself:

```bash
stat --printf='bytes=%s modified=%y\n' /secure/data/region-internal.osh.pbf
sha256sum /secure/data/region-internal.osh.pbf
```

For reproducible work, retain:

- provider and region page
- exact filename
- retrieval timestamp in UTC
- byte size
- SHA-256 checksum
- clipping boundary or `.poly` file when applicable

Do not add the PBF to Git. The repository `.gitignore` excludes `*.pbf` and `*.osh.pbf` as an additional guard.

## 6. Create an empty import database

Use a new database. The importer owns its `hist_*` tables; do not point it at a database containing data you need to preserve.

```bash
createdb osm_history_test

psql -X -v ON_ERROR_STOP=1 -d osm_history_test <<'SQL'
CREATE EXTENSION postgis;
CREATE EXTENSION hstore;
CREATE EXTENSION btree_gist;
SQL
```

When PostgreSQL uses a non-default Unix socket or port, add the same `-h` and `-p` values to both commands.

## 7. Import history

Small extracts can use the default nodestore. Use the sparse nodestore for realistic regional history files:

```bash
micromamba run -p "$HOME/.local/share/osm-history-geos315" \
  importer/osm-history-importer \
  --nodestore sparse \
  --dsn "host=/path/to/postgres/socket port=5432 dbname=osm_history_test" \
  /secure/data/region-internal.osh.pbf
```

The resulting core tables are:

- `hist_point`
- `hist_line`
- `hist_polygon`
- `hist_relation`
- `hist_relation_member`
- `hist_user`

`hist_line` and `hist_polygon` contain `minor` versions generated when member-node movement changes a way geometry without a new way version.

## 8. Run the Maldives golden-data gate

Before a large regional import, run the exact Maldives gate. The script refuses arbitrary database names, never drops a database, and retains the result for inspection.

On the verified VM:

```bash
OSM_HISTORY_TEST_DB=osm_history_geos_upgrade_maldives_315_check \
MALDIVES_PBF=/absolute/path/to/maldives-internal.osh.pbf \
scripts/verify-maldives-parity.sh
```

The run must pass:

1. all six table counts;
2. all six sorted-table SHA-256 hashes;
3. geometry type, SRID, null, and validity profiles;
4. polygon-center values;
5. line and polygon minor-version metrics.

To recheck a retained database without modifying it:

```bash
OSM_HISTORY_TEST_DB=osm_history_geos_upgrade_maldives_315_check \
OSM_HISTORY_REUSE_DB=1 \
MALDIVES_PBF=/absolute/path/to/maldives-internal.osh.pbf \
scripts/verify-maldives-parity.sh
```

Do not proceed to a large-region performance run after a mismatch. Identify the first differing primary key and column first.

## 9. Render one historical instant

The renderer creates temporary osm2pgsql-shaped views named `<view-prefix>_{point,line,roads,polygon}`. PostGIS discovers their geometry metadata automatically; the renderer does not modify the `geometry_columns` view.

```bash
micromamba run -p "$HOME/.local/share/osm-history-renderer-modern" \
  osm-history-render \
  --style /absolute/path/to/style.xml \
  --db "host=/path/to/postgres/socket port=5432 dbname=osm_history_test" \
  --dbprefix hist \
  --view-prefix hist_view \
  --bbox 73.45,4.10,73.65,4.30 \
  --date "2025-01-31 00:00:00" \
  --zoom 12 \
  --file output/maldives-2025
```

Output is `output/maldives-2025.png`. The temporary views are removed even if Mapnik raises an error. Add `--retain-views` only when debugging a style.

The legacy entry point has the same arguments:

```bash
micromamba run -p "$HOME/.local/share/osm-history-renderer-modern" \
  renderer/render.py --help
```

## 10. Render an animation

```bash
micromamba run -p "$HOME/.local/share/osm-history-renderer-modern" \
  osm-history-render-animation \
  --style /absolute/path/to/style.xml \
  --db "host=/path/to/postgres/socket port=5432 dbname=osm_history_test" \
  --bbox 73.45,4.10,73.65,4.30 \
  --anistart 2024-01-01 \
  --aniend 2025-01-01 \
  --anistep months=+1 \
  --fps 2 \
  --label '%Y-%m-%d' \
  --file output/maldives-history
```

This creates numbered PNG frames in `output/maldives-history/` and a self-contained `output/maldives-history.html` player. The player uses browser-native JavaScript and makes no jQuery/CDN requests. Labels are drawn with Pillow.

To create a video, run `ffmpeg` separately, for example:

```bash
ffmpeg -framerate 2 \
  -i output/maldives-history/%010d.png \
  -c:v libx264 -pix_fmt yuv420p \
  output/maldives-history.mp4
```

## 11. Large-region validation order

Use this order for a Greater London or other large extract:

1. pass the focused C++ GEOS test;
2. pass the complete Maldives import and exact parity script;
3. pass all renderer unit and PostGIS integration tests;
4. record the large extract's provenance and checksum;
5. import it into a new database;
6. run bounded geometry/row-count checks before performance measurement;
7. render a small known bbox/date before starting a full animation;
8. record wall time, peak RSS, database size, PostgreSQL/PostGIS versions, and command lines.

Large-region timings are performance evidence, not a substitute for the deterministic Maldives parity gate.
