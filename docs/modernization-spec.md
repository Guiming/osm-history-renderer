# OSM History Renderer Modernization Specification

## Objective

Modernize this fork without changing the history data model or the importer output:

1. Build and run the importer with GEOS 3.15.0 using the supported, stable GEOS C API.
2. Preserve the renderer, port it to current Python and Mapnik bindings, and remove unsafe SQL construction and obsolete browser dependencies.
3. Document a reproducible local setup and verify importer output against the existing Maldives reference dataset before using the Greater London integration dataset.

## Importer requirements

- Target GEOS 3.15.0 and libosmium 2.23.1.
- Use only the reentrant GEOS C API from `geos_c.h`; do not include GEOS C++ headers.
- Link to `geos_c` through package metadata instead of hard-coded include or library paths.
- Preserve EWKB with SRID 3857, polygon area, optional point-on-surface output, and line-versus-polygon behavior.
- Preserve the six Maldives reference table counts and sorted-stream SHA-256 hashes recorded in the checked-in verification report.
- Never alter or drop `osm_history_maldives` or `osm_history_maldives_source`. Test databases must start with `osm_history_geos_upgrade_`.

## Renderer requirements

- Require Python 3.11 or newer, Mapnik Python 4.2.2 or newer within major version 4, Psycopg 3, python-dateutil, and Pillow.
- Retain `renderer/render.py` and `renderer/render-animation.py` as executable compatibility entry points.
- Add installable commands `osm-history-render` and `osm-history-render-animation`.
- Use `argparse`, `pathlib`, typed dataclasses, context-managed database connections, SQL parameters, and quoted SQL identifiers.
- Work with modern PostGIS where `geometry_columns` is a view; never insert into or delete from it.
- Always clean up temporary history views after a render unless the user explicitly requests that they be retained.
- Generate animation HTML without jQuery or remote JavaScript.
- Add unit tests for parsing, SQL/view behavior, zoom sizing, date inference, and generated animation HTML.

## Documentation and delivery requirements

- Replace the obsolete Debian 6/Ubuntu 12 tutorial with current, versioned setup instructions.
- Document provenance, authenticated Geofabrik data handling, and the two-stage Maldives-then-London verification workflow.
- Do not commit PBF data, database files, credentials, generated images, compiled binaries, or local environments.
- Create local commits only after tests pass. Do not push to GitHub without an explicit request.
