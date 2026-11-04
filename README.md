# OpenStreetMap History Importer and Renderer

## Project Lineage

This modernization branch (`modernize-importer-renderer`) continues the work of the **OSM History Viewer** project, extending compatibility to newer dependency versions while preserving verified functionality.

### Previous Versions and Repositories

- **Original implementation**: [`MaZderMind/osm-history-renderer`](https://github.com/MaZderMind/osm-history-renderer) — The foundational OSM history importer/renderer created by @MaZderMind.
- **joto fork**: [`joto/osm-history-renderer`](https://github.com/joto/osm-history-renderer) — A fork of MaZderMind's original implementation with subsequent maintenance and modernization by @joto.
- **This repo's new-osmium-geos branch**: The previous modernization effort that upgraded GEOS to 3.11, tested with libosmium 2.6+ and newer GEOS versions. See [`Guiming/osm-history-renderer/new-osmium-geos`](https://github.com/Guiming/osm-history-renderer/tree/new-osmium-geos) for the continuation of that work.

This `modernize-importer-renderer` branch further advances compatibility to GEOS **3.15.0**, libosmium **2.23.1**, Mapnik Python **4.x**, and PostgreSQL 18 with PostGIS 3.6, while preserving the verified output of previous versions.

### Repository Layout

- `importer/` — C++ history importer and SQL schema
- `renderer/osm_history_renderer/` — installable Python renderer
- `renderer/render.py` — compatibility entry point for one image
- `renderer/render-animation.py` — compatibility entry point for frame sequences
- `scripts/verify-importer-fixtures.sh` — reproducible importer regression checks
- `environment-importer.yml` — pinned importer build dependencies
- `environment-renderer.yml` — pinned renderer/test dependencies
- `TUTORIAL.md` — complete build, import, render, and verification guide It preserves minor way versions caused by node movement, so geometry changes are represented even when the way itself was not edited.

The modernization branch targets supported dependency interfaces while preserving the verified importer output:

- GEOS **3.15.0** through the reentrant C API (`geos_c.h`)
- libosmium **2.23.1** and C++17
- Python **3.11+** (tested with 3.12.16)
- Mapnik Python **4.x** (tested with 4.3.2)
- Psycopg **3**, python-dateutil, and Pillow
- PostgreSQL **15** and PostGIS **3.4** in the verified local setup

## Repository layout

- `importer/` — C++ history importer and SQL schema
- `renderer/osm_history_renderer/` — installable Python renderer
- `renderer/render.py` — compatibility entry point for one image
- `renderer/render-animation.py` — compatibility entry point for frame sequences
- `scripts/verify-importer-fixtures.sh` — reproducible importer regression checks
- `environment-importer.yml` — pinned importer build dependencies
- `environment-renderer.yml` — pinned renderer/test dependencies
- `TUTORIAL.md` — complete build, import, render, and verification guide

## Quick start

Create the isolated environments:

```bash
micromamba create -y \
  -p "$HOME/.local/share/osm-history-geos315" \
  -f environment-importer.yml

micromamba create -y \
  -p "$HOME/.local/share/osm-history-renderer-modern" \
  -f environment-renderer.yml
```

Build and test the importer:

```bash
micromamba run -p "$HOME/.local/share/osm-history-geos315" \
  make -C importer clean all test
```

Install and test the renderer:

```bash
micromamba run -p "$HOME/.local/share/osm-history-renderer-modern" \
  python -m pip install --no-deps -e .

micromamba run -p "$HOME/.local/share/osm-history-renderer-modern" \
  pytest -q
```

Create a PostGIS database before importing:

```sql
CREATE EXTENSION postgis;
CREATE EXTENSION hstore;
CREATE EXTENSION btree_gist;
```

Then import a history extract that you are authorized to use:

```bash
micromamba run -p "$HOME/.local/share/osm-history-geos315" \
  importer/osm-history-importer \
  --nodestore sparse \
  --dsn "host=/path/to/postgres/socket port=5432 dbname=osm_history" \
  /path/to/region-internal.osh.pbf
```

Render a snapshot with an osm2pgsql-compatible Mapnik XML style:

```bash
micromamba run -p "$HOME/.local/share/osm-history-renderer-modern" \
  osm-history-render \
  --style /path/to/style.xml \
  --db "host=/path/to/postgres/socket port=5432 dbname=osm_history" \
  --bbox -0.15,51.49,-0.05,51.55 \
  --date 2025-01-31 \
  --zoom 12 \
  --file snapshot-2025
```

The compatibility command remains valid:

```bash
renderer/render.py --help
```

Temporary `hist_view_{point,line,roads,polygon}` views are removed after each render, including when rendering fails. Use `--retain-views` only for deliberate inspection.

## Importer verification

The repository includes small tracked `.osh` fixtures that exercise node, way,
relation, geometry, and minor-version behavior without requiring access to a
restricted download service. Run them with:

```bash
POSTGRES_PREFIX=/path/to/postgres \
POSTGRES_HOST=/path/to/postgres/socket \
POSTGRES_PORT=5432 \
IMPORTER_ENV_PREFIX="$HOME/.local/share/osm-history-geos315" \
scripts/verify-importer-fixtures.sh
```

For a project-specific extract, record its provenance and checksum and establish
your own expected row counts and semantic checks before treating it as a
regression baseline. Do not publish extracts or contributor metadata unless
their terms permit redistribution.

## Data and privacy

History extracts contain contributor metadata. Geofabrik makes full-metadata `.osh.pbf` files available through its authenticated internal download service and notes that the data is subject to EU data-protection requirements. Keep the extract local, respect the provider's terms, and never commit it, credentials, cookies, database files, or rendered private outputs to Git.

Record the source URL, download time, byte size, and SHA-256 checksum for every research dataset. See `TUTORIAL.md` for a credential-safe download pattern and the recommended validation order.

## Dependencies and PostgreSQL/PostGIS Compatibility

The verified baseline setup uses:
- **PostgreSQL 18** with **PostGIS 3.6** via the image `postgis/postgis:18-3.6@sha256:4a43e3c3e5d55b9208240fc71db543b79c638766280c625a425bd0a2390989c4`
- This combination is compatible with the importer and renderer tested in this branch

The `environment-postgis-latest.yml` file provides an optional edge test configuration with PostgreSQL 19 RC and PostGIS 3.7, but PostgreSQL 18/PostGIS 3.6 remains the production baseline.

If you use a custom PostgreSQL/PostGIS installation, verify compatibility by:
1. Ensuring `hist_*` tables can be created (requires PostGIS functions)
2. Checking that geometry types and SRIDs match expected profiles
3. Running the importer fixtures with your database to confirm row counts and checksums

## Importer Dependencies

The OSM history importer depends on:
- GEOS **3.15.0** via the reentrant C API (`geos_c.h`)
- libosmium **2.23.1**
- The compiled binary is built from source in `importer/` and installed as `/usr/local/bin/osm-history-import`

See the [`modernize-importer-renderer` branch](https://github.com/Guiming/osm-history-renderer/tree/modernize-importer-renderer) containing this OSM history importer.

## Current scope
