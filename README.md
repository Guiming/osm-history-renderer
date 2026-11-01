# OpenStreetMap History Importer and Renderer

## Project Lineage

This modernization branch (`upgrade/geos-3.15-mapnik-4.3.2`) continues the work of the **OSM History Viewer** project, extending compatibility to newer dependency versions while preserving verified functionality.

### Previous Versions and Repositories

- **Original implementation**: [`joto/osm-history-renderer`](https://github.com/joto/osm-history-renderer) — The foundational OSM history importer/renderer by @joto (2016–2024).
- **MaZderMind fork**: [`MaZderMind/osm-history-renderer`](https://github.com/MaZderMind/osm-history-renderer) — Enhanced the original with better documentation and community contributions.
- **This repo's new-osmium-geos branch**: The previous modernization effort that upgraded GEOS to 3.10, tested with libosmium 2.6+ and newer GEOS versions. See [`Guiming/osm-history-renderer/new-osmium-geos`](https://github.com/Guiming/osm-history-renderer/tree/new-osmium-geos) for the continuation of that work.

This `upgrade/geos-3.15-mapnik-4.3.2` branch further advances compatibility to GEOS **3.15.0**, libosmium **2.23.1**, Mapnik Python **4.x**, and PostgreSQL 18 with PostGIS 3.6, while preserving the verified output of previous versions.

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

## Current scope

The importer stores nodes, ways, relations, relation members, and users. It does not assemble relation multipolygons into the `hist_polygon` table; downstream systems needing relation polygons must run a separately validated relation-processing stage.

The renderer consumes Mapnik XML styles written for the temporary osm2pgsql-compatible view prefix. Animation output is a PNG sequence plus self-contained HTML. Use `ffmpeg` separately when a video container is required.
