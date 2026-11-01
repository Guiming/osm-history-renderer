# OpenStreetMap History Importer and Renderer

This fork imports `.osh`/`.osh.pbf` OpenStreetMap history into PostgreSQL/PostGIS and renders a selected historical instant with Mapnik. It preserves minor way versions caused by node movement, so geometry changes are represented even when the way itself was not edited.

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
- `scripts/verify-maldives-parity.sh` — guarded, reproducible importer parity gate
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

Then import an authenticated history extract:

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
  --bbox 73.45,4.10,73.65,4.30 \
  --date 2025-01-31 \
  --zoom 12 \
  --file maldives-2025
```

The compatibility command remains valid:

```bash
renderer/render.py --help
```

Temporary `hist_view_{point,line,roads,polygon}` views are removed after each render, including when rendering fails. Use `--retain-views` only for deliberate inspection.

## Importer parity

The Maldives fixture is the required golden-data gate. A verified run produced exact matches for all six tables:

| Table | Rows | SHA-256 of sorted `COPY` stream |
|---|---:|---|
| `hist_point` | 690,224 | `eca37b81f650ec3dd115570f0972c5b066eaf965a5431b87c82c49aa4e84d424` |
| `hist_line` | 73,587 | `d91a3a89cab93d61482a5823e5b3a291df13b0871fae3cb572ccdd3ccbe8247c` |
| `hist_polygon` | 84,651 | `ac213b2ee9d17dac0b1dfa407f5f235fb1e593ebd508039c3497cebd704d6e60` |
| `hist_relation` | 3,112 | `92dab89283889ff975d179ae3d37dda601ab737c4075dc768924e765655c387c` |
| `hist_relation_member` | 1,052,280 | `00e8540a019ffb9c78cbd048e0871049cd3bb059885fabc034e648acbade9e50` |
| `hist_user` | 1,472 | `78bfb6cc7763de923af8ed7c46cb2b6c3080cab80d480238de0ea2e1eedf5ace` |

The parity script also checks geometry types, SRIDs, null and validity profiles, polygon-center values, and line/polygon minor-version metrics. It only creates databases whose names start with `osm_history_geos_upgrade_`; it never drops a database.

## Data and privacy

History extracts contain contributor metadata. Geofabrik makes full-metadata `.osh.pbf` files available through its authenticated internal download service and notes that the data is subject to EU data-protection requirements. Keep the extract local, respect the provider's terms, and never commit it, credentials, cookies, database files, or rendered private outputs to Git.

Record the source URL, download time, byte size, and SHA-256 checksum for every research dataset. See `TUTORIAL.md` for a credential-safe download pattern and the required Maldives-before-large-region validation order.

## Current scope

The importer stores nodes, ways, relations, relation members, and users. It does not assemble relation multipolygons into the `hist_polygon` table; downstream systems needing relation polygons must run a separately validated relation-processing stage.

The renderer consumes Mapnik XML styles written for the temporary osm2pgsql-compatible view prefix. Animation output is a PNG sequence plus self-contained HTML. Use `ffmpeg` separately when a video container is required.
