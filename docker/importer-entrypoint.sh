#!/usr/bin/env bash
set -euo pipefail

if (( $# > 0 )); then
    exec osm-history-importer "$@"
fi

input_file="${OSM_HISTORY_IMPORT_FILE:-}"
if [[ -z "${input_file}" ]]; then
    printf 'OSM_HISTORY_IMPORT_FILE is required (for example /history/maldives-internal.osh.pbf).\n' >&2
    exit 2
fi
if [[ ! -f "${input_file}" ]]; then
    printf 'History input is not a readable file: %s\n' "${input_file}" >&2
    exit 2
fi

export PGPASSWORD="${OSM_HISTORY_DB_PASSWORD:-${POSTGRES_PASSWORD:-}}"
dsn="host=${OSM_HISTORY_DB_HOST:-db} port=${OSM_HISTORY_DB_PORT:-5432} dbname=${OSM_HISTORY_DB_NAME:-osm_history_planet} user=${OSM_HISTORY_DB_USER:-postgres}"

exec osm-history-importer \
    --nodestore "${OSM_HISTORY_NODESTORE:-sparse}" \
    --dsn "${dsn}" \
    --prefix "${OSM_HISTORY_IMPORT_PREFIX:-hist_planet_}" \
    "${input_file}"
