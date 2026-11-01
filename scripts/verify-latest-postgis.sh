#!/usr/bin/env bash
set -euo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly MICROMAMBA="${MICROMAMBA:-$(command -v micromamba || true)}"
readonly DATABASE_ENV_PREFIX="${LATEST_POSTGIS_ENV_PREFIX:?Set LATEST_POSTGIS_ENV_PREFIX to the disposable database environment prefix}"
readonly IMPORTER_ENV_PREFIX="${IMPORTER_ENV_PREFIX:?Set IMPORTER_ENV_PREFIX to the importer environment prefix}"
readonly IMPORTER="${IMPORTER:-${REPOSITORY_ROOT}/importer/osm-history-importer}"
readonly DATABASE_PORT="${LATEST_POSTGIS_PORT:-55438}"
readonly MALDIVES_PBF="${MALDIVES_PBF:?Set MALDIVES_PBF to the verified Maldives .osh.pbf fixture}"

for executable in "${MICROMAMBA}" "${IMPORTER}"; do
    if [[ ! -x "${executable}" ]]; then
        printf 'Required executable is missing: %s\n' "${executable}" >&2
        exit 2
    fi
done

if [[ ! -x "${DATABASE_ENV_PREFIX}/bin/postgres" ]]; then
    "${MICROMAMBA}" create \
        --yes \
        --prefix "${DATABASE_ENV_PREFIX}" \
        --file "${REPOSITORY_ROOT}/environment-postgis-latest.yml"
fi

for executable in initdb pg_ctl createdb psql; do
    if [[ ! -x "${DATABASE_ENV_PREFIX}/bin/${executable}" ]]; then
        printf 'Database environment is missing %s\n' "${DATABASE_ENV_PREFIX}/bin/${executable}" >&2
        exit 2
    fi
done

cluster_root="$(mktemp -d /tmp/osm-history-pg18-postgis37.XXXXXX)"
readonly cluster_root
readonly data_directory="${cluster_root}/data"
readonly socket_directory="${cluster_root}/socket"
mkdir -p "${socket_directory}"

server_started=0
cleanup() {
    if (( server_started )); then
        "${DATABASE_ENV_PREFIX}/bin/pg_ctl" \
            --pgdata "${data_directory}" \
            --wait \
            --mode fast \
            stop >/dev/null 2>&1 || true
    fi
    if [[ "${cluster_root}" == /tmp/osm-history-pg18-postgis37.* ]]; then
        rm -rf -- "${cluster_root}"
    fi
}
trap cleanup EXIT INT TERM

"${DATABASE_ENV_PREFIX}/bin/initdb" \
    --pgdata "${data_directory}" \
    --auth-local trust \
    --auth-host reject \
    --no-locale \
    --encoding UTF8 >/dev/null

"${DATABASE_ENV_PREFIX}/bin/pg_ctl" \
    --pgdata "${data_directory}" \
    --wait \
    --options "-F -p ${DATABASE_PORT} -k ${socket_directory} -c listen_addresses='' -c fsync=off -c synchronous_commit=off -c full_page_writes=off" \
    start >/dev/null
server_started=1

readonly psql=(
    "${DATABASE_ENV_PREFIX}/bin/psql"
    -X
    -v ON_ERROR_STOP=1
    -h "${socket_directory}"
    -p "${DATABASE_PORT}"
)

printf 'Testing database stack: '
"${psql[@]}" -d postgres -Atc \
    "SELECT current_setting('server_version') || ' / PostGIS ' || default_version FROM pg_available_extensions WHERE name = 'postgis';"

env \
    POSTGRES_PREFIX="${DATABASE_ENV_PREFIX}" \
    POSTGRES_HOST="${socket_directory}" \
    POSTGRES_PORT="${DATABASE_PORT}" \
    IMPORTER_ENV_PREFIX="${IMPORTER_ENV_PREFIX}" \
    IMPORTER="${IMPORTER}" \
    OSM_HISTORY_FIXTURE_DB_PREFIX="osm_history_geos_upgrade_pg18pg37_fixture_" \
    "${REPOSITORY_ROOT}/scripts/verify-importer-fixtures.sh"

env \
    POSTGRES_PREFIX="${DATABASE_ENV_PREFIX}" \
    POSTGRES_HOST="${socket_directory}" \
    POSTGRES_PORT="${DATABASE_PORT}" \
    IMPORTER_ENV_PREFIX="${IMPORTER_ENV_PREFIX}" \
    IMPORTER="${IMPORTER}" \
    MALDIVES_PBF="${MALDIVES_PBF}" \
    OSM_HISTORY_TEST_DB="osm_history_geos_upgrade_maldives_pg18pg37" \
    "${REPOSITORY_ROOT}/scripts/verify-maldives-parity.sh"

printf 'Latest stable PostgreSQL/PostGIS compatibility gate passed.\n'
