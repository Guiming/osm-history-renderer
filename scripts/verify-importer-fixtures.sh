#!/usr/bin/env bash
set -euo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly DATABASE_PREFIX="${OSM_HISTORY_FIXTURE_DB_PREFIX:-osm_history_geos_upgrade_fixture_}"
readonly REQUIRED_PREFIX="osm_history_geos_upgrade_"
readonly POSTGRES_PREFIX="${POSTGRES_PREFIX:?Set POSTGRES_PREFIX to the PostgreSQL installation prefix}"
readonly POSTGRES_HOST="${POSTGRES_HOST:?Set POSTGRES_HOST to the server socket directory or host}"
readonly POSTGRES_PORT="${POSTGRES_PORT:-55432}"
readonly IMPORTER_ENV_PREFIX="${IMPORTER_ENV_PREFIX:?Set IMPORTER_ENV_PREFIX to the importer environment prefix}"
readonly MICROMAMBA="${MICROMAMBA:-$(command -v micromamba || true)}"
readonly IMPORTER="${IMPORTER:-${REPOSITORY_ROOT}/importer/osm-history-importer}"

if [[ "${DATABASE_PREFIX}" != "${REQUIRED_PREFIX}"* ]]; then
    printf 'Refusing unsafe database prefix: %s\n' "${DATABASE_PREFIX}" >&2
    exit 2
fi

for executable in "${POSTGRES_PREFIX}/bin/createdb" "${POSTGRES_PREFIX}/bin/psql" "${MICROMAMBA}" "${IMPORTER}"; do
    if [[ ! -x "${executable}" ]]; then
        printf 'Required executable is missing: %s\n' "${executable}" >&2
        exit 2
    fi
done

mapfile -t fixtures < <(find "${REPOSITORY_ROOT}/importer/test" -maxdepth 1 -type f -name '*.osh' -printf '%f\n' | sort)
if (( ${#fixtures[@]} == 0 )); then
    printf 'No .osh fixtures found.\n' >&2
    exit 2
fi

psql=("${POSTGRES_PREFIX}/bin/psql" -X -v ON_ERROR_STOP=1 -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}")
passed=0
for filename in "${fixtures[@]}"; do
    suffix="${filename%.osh}"
    suffix="${suffix//-/_}"
    database="${DATABASE_PREFIX}${suffix}"
    if "${psql[@]}" -d postgres -Atc "SELECT 1 FROM pg_database WHERE datname = '${database}'" | grep -qx 1; then
        printf 'Fixture database exists; refusing to overwrite it: %s\n' "${database}" >&2
        exit 2
    fi

    "${POSTGRES_PREFIX}/bin/createdb" -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" "${database}"
    "${psql[@]}" -d "${database}" -q -c \
        'CREATE EXTENSION postgis; CREATE EXTENSION hstore; CREATE EXTENSION btree_gist;'
    (
        cd "${REPOSITORY_ROOT}/importer"
        "${MICROMAMBA}" run -p "${IMPORTER_ENV_PREFIX}" \
            "${IMPORTER}" \
            --nodestore sparse \
            --dsn "host=${POSTGRES_HOST} port=${POSTGRES_PORT} dbname=${database}" \
            "test/${filename}" >/dev/null
    )
    counts="$(${psql[@]} -d "${database}" -AtF '|' -c \
        'SELECT (SELECT count(*) FROM hist_point),
                (SELECT count(*) FROM hist_line),
                (SELECT count(*) FROM hist_polygon),
                (SELECT count(*) FROM hist_relation);')"
    printf 'PASS %-30s database=%s counts=%s\n' "${filename}" "${database}" "${counts}"
    ((passed += 1))
done

printf 'Fixture imports passed: %d/%d\n' "${passed}" "${#fixtures[@]}"
