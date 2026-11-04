# Modern setup, import, render, and verification guide

## Project Lineage

This guide describes the `modernize-importer-renderer` branch of the `osm-history-renderer` project lineage. It extends compatibility to GEOS **3.15.0**, libosmium **2.23.1**, and Mapnik Python **4.x** and is consumed downstream by [`osm-history-time-machine`](https://github.com/Guiming/osm-history-time-machine).

### Previous Versions and Repositories

For background on earlier work:

- [`MaZderMind/osm-history-renderer`](https://github.com/MaZderMind/osm-history-renderer) — The original implementation created by @MaZderMind.
- [`joto/osm-history-renderer`](https://github.com/joto/osm-history-renderer) — A fork of MaZderMind's original implementation with subsequent maintenance and modernization by @joto.
- [`Guiming/osm-history-renderer/new-osmium-geos`](https://github.com/Guiming/osm-history-renderer/tree/new-osmium-geos) — The previous modernization effort that upgraded GEOS to 3.11 and tested compatibility with libosmium 2.6+.

This `modernize-importer-renderer` branch advances the compatibility boundary further while preserving verified output across versions.

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

## 8. Run the reproducible importer checks

Before a large regional import, run the focused GEOS test and the small tracked
history fixtures. These checks are included in the repository and do not depend
on an account-protected dataset:

```bash
micromamba run -p "$HOME/.local/share/osm-history-geos315" \
  make -C importer test

POSTGRES_PREFIX=/path/to/postgres \
POSTGRES_HOST=/path/to/postgres/socket \
POSTGRES_PORT=5432 \
IMPORTER_ENV_PREFIX="$HOME/.local/share/osm-history-geos315" \
scripts/verify-importer-fixtures.sh
```

For an additional project-specific regression gate, use an extract that you are
authorized to access and define expected row counts, geometry profiles, and
checksums locally. Keep restricted data and derived contributor records out of
the repository.

## 9. Render one historical instant

The renderer creates temporary osm2pgsql-shaped views named `<view-prefix>_{point,line,roads,polygon}`. PostGIS discovers their geometry metadata automatically; the renderer does not modify the `geometry_columns` view.

```bash
micromamba run -p "$HOME/.local/share/osm-history-renderer-modern" \
  osm-history-render \
  --style /absolute/path/to/style.xml \
  --db "host=/path/to/postgres/socket port=5432 dbname=osm_history_test" \
  --dbprefix hist \
  --view-prefix hist_view \
  --bbox -0.15,51.49,-0.05,51.55 \
  --date "2025-01-31 00:00:00" \
  --zoom 12 \
  --file output/history-snapshot
```

Output is `output/history-snapshot.png`. The temporary views are removed even if Mapnik raises an error. Add `--retain-views` only when debugging a style.

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
  --bbox -0.15,51.49,-0.05,51.55 \
  --anistart 2024-01-01 \
  --aniend 2025-01-01 \
  --anistep months=+1 \
  --fps 2 \
  --label '%Y-%m-%d' \
  --file output/history-animation
```

This creates numbered PNG frames in `output/history-animation/` and a self-contained `output/history-animation.html` player. The player uses browser-native JavaScript and makes no jQuery/CDN requests. Labels are drawn with Pillow.

To create a video, run `ffmpeg` separately, for example:

```bash
ffmpeg -framerate 2 \
  -i output/history-animation/%010d.png \
  -c:v libx264 -pix_fmt yuv420p \
  output/history-animation.mp4
```

## 11. Large-region validation order

Use this order for a Greater London or other large extract:

1. pass the focused C++ GEOS test;
2. pass all tracked importer fixtures;
3. pass all renderer unit and PostGIS integration tests;
4. record the large extract's provenance and checksum;
5. import it into a new database;
6. run bounded geometry/row-count checks before performance measurement;
7. render a small known bbox/date before starting a full animation;
8. record wall time, peak RSS, database size, PostgreSQL/PostGIS versions, and command lines.

Large-region timings are performance evidence, not a substitute for deterministic fixture and semantic checks.
