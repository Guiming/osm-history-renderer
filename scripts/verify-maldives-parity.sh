#!/usr/bin/env bash
set -euo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly DATABASE_NAME="${OSM_HISTORY_TEST_DB:-osm_history_geos_upgrade_maldives_315}"
readonly DATABASE_PREFIX="osm_history_geos_upgrade_"
readonly POSTGRES_PREFIX="${POSTGRES_PREFIX:?Set POSTGRES_PREFIX to the PostgreSQL installation prefix}"
readonly POSTGRES_HOST="${POSTGRES_HOST:?Set POSTGRES_HOST to the server socket directory or host}"
readonly POSTGRES_PORT="${POSTGRES_PORT:-55432}"
readonly IMPORTER_ENV_PREFIX="${IMPORTER_ENV_PREFIX:?Set IMPORTER_ENV_PREFIX to the importer environment prefix}"
readonly MICROMAMBA="${MICROMAMBA:-$(command -v micromamba || true)}"
readonly IMPORTER="${IMPORTER:-${REPOSITORY_ROOT}/importer/osm-history-importer}"
readonly DATASET="${MALDIVES_PBF:?Set MALDIVES_PBF to the verified Maldives .osh.pbf fixture}"
readonly EXPECTED_DATASET_SHA256="45186a1286f21cd2b0b0c6c4566f7da3c8fcb4e4f746717920ba59d2826fc42f"
readonly REUSE_EXISTING="${OSM_HISTORY_REUSE_DB:-0}"

if [[ "${DATABASE_NAME}" != "${DATABASE_PREFIX}"* ]]; then
    printf 'Refusing unsafe database name: %s\n' "${DATABASE_NAME}" >&2
    exit 2
fi

for executable in "${POSTGRES_PREFIX}/bin/createdb" "${POSTGRES_PREFIX}/bin/psql" "${MICROMAMBA}" "${IMPORTER}"; do
    if [[ ! -x "${executable}" ]]; then
        printf 'Required executable is missing: %s\n' "${executable}" >&2
        exit 2
    fi
done

if [[ ! -f "${DATASET}" ]]; then
    printf 'Maldives fixture is missing: %s\n' "${DATASET}" >&2
    exit 2
fi

actual_dataset_sha256="$(sha256sum "${DATASET}" | cut -d' ' -f1)"
if [[ "${actual_dataset_sha256}" != "${EXPECTED_DATASET_SHA256}" ]]; then
    printf 'Maldives fixture checksum mismatch: %s\n' "${actual_dataset_sha256}" >&2
    exit 2
fi

psql=("${POSTGRES_PREFIX}/bin/psql" -X -v ON_ERROR_STOP=1 -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}")

database_exists=0
if "${psql[@]}" -d postgres -Atc "SELECT 1 FROM pg_database WHERE datname = '${DATABASE_NAME}'" | grep -qx 1; then
    database_exists=1
fi

if (( database_exists )); then
    if [[ "${REUSE_EXISTING}" != "1" ]]; then
        printf 'Test database already exists; refusing to overwrite it: %s\n' "${DATABASE_NAME}" >&2
        exit 2
    fi
    printf 'Reusing existing parity database without modifying it: %s\n' "${DATABASE_NAME}"
else
    "${POSTGRES_PREFIX}/bin/createdb" \
        -h "${POSTGRES_HOST}" \
        -p "${POSTGRES_PORT}" \
        "${DATABASE_NAME}"

    "${psql[@]}" -d "${DATABASE_NAME}" -c \
        'CREATE EXTENSION postgis; CREATE EXTENSION hstore; CREATE EXTENSION btree_gist;'

    (
        cd "${REPOSITORY_ROOT}/importer"
        "${MICROMAMBA}" run -p "${IMPORTER_ENV_PREFIX}" \
            "${IMPORTER}" \
            --nodestore sparse \
            --dsn "host=${POSTGRES_HOST} port=${POSTGRES_PORT} dbname=${DATABASE_NAME}" \
            "${DATASET}"
    )
fi

declare -Ar expected_counts=(
    [hist_point]=690224
    [hist_line]=73587
    [hist_polygon]=84651
    [hist_relation]=3112
    [hist_relation_member]=1052280
    [hist_user]=1472
)

declare -Ar expected_hashes=(
    [hist_point]=eca37b81f650ec3dd115570f0972c5b066eaf965a5431b87c82c49aa4e84d424
    [hist_line]=d91a3a89cab93d61482a5823e5b3a291df13b0871fae3cb572ccdd3ccbe8247c
    [hist_polygon]=ac213b2ee9d17dac0b1dfa407f5f235fb1e593ebd508039c3497cebd704d6e60
    [hist_relation]=92dab89283889ff975d179ae3d37dda601ab737c4075dc768924e765655c387c
    [hist_relation_member]=00e8540a019ffb9c78cbd048e0871049cd3bb059885fabc034e648acbade9e50
    [hist_user]=78bfb6cc7763de923af8ed7c46cb2b6c3080cab80d480238de0ea2e1eedf5ace
)

declare -Ar order_by=(
    [hist_point]='id, version'
    [hist_line]='id, version, minor'
    [hist_polygon]='id, version, minor'
    [hist_relation]='id, version'
    [hist_relation_member]='relation_id, version, member_id, member_type, role'
    [hist_user]='user_id'
)

status=0
for table in hist_point hist_line hist_polygon hist_relation hist_relation_member hist_user; do
    count="$("${psql[@]}" -d "${DATABASE_NAME}" -Atc "SELECT count(*) FROM ${table}")"
    hash="$(
        "${psql[@]}" -d "${DATABASE_NAME}" -qAtc \
            "COPY (SELECT * FROM ${table} ORDER BY ${order_by[${table}]}) TO STDOUT" |
            sha256sum |
            cut -d' ' -f1
    )"

    if [[ "${count}" == "${expected_counts[${table}]}" && "${hash}" == "${expected_hashes[${table}]}" ]]; then
        printf 'PASS %-24s rows=%s sha256=%s\n' "${table}" "${count}" "${hash}"
    else
        printf 'FAIL %-24s rows=%s expected_rows=%s sha256=%s expected_sha256=%s\n' \
            "${table}" "${count}" "${expected_counts[${table}]}" \
            "${hash}" "${expected_hashes[${table}]}" >&2
        status=1
    fi
done

declare -Ar geometry_checks=(
    [hist_point]='637919|52305|0|0|0'
    [hist_line]='73586|1|0|0|5'
    [hist_polygon]='84645|6|0|0|929'
)

for table in hist_point hist_line hist_polygon; do
    expected_type=POINT
    [[ "${table}" == hist_line ]] && expected_type=LINESTRING
    [[ "${table}" == hist_polygon ]] && expected_type=POLYGON

    actual="$(${psql[@]} -d "${DATABASE_NAME}" -AtF '|' -c "
        SET client_min_messages = warning;
        SELECT
            count(geom),
            count(*) FILTER (WHERE geom IS NULL),
            count(*) FILTER (WHERE geom IS NOT NULL AND GeometryType(geom) <> '${expected_type}'),
            count(*) FILTER (WHERE geom IS NOT NULL AND ST_SRID(geom) <> 3857),
            count(*) FILTER (WHERE geom IS NOT NULL AND NOT ST_IsValid(geom))
        FROM ${table};
    " | tail -n 1)"

    if [[ "${actual}" == "${geometry_checks[${table}]}" ]]; then
        printf 'PASS %-24s geometry=%s\n' "${table}" "${actual}"
    else
        printf 'FAIL %-24s geometry=%s expected=%s\n' \
            "${table}" "${actual}" "${geometry_checks[${table}]}" >&2
        status=1
    fi
done

center_metrics="$(${psql[@]} -d "${DATABASE_NAME}" -AtF '|' -c "
    SELECT
        count(center),
        count(*) FILTER (WHERE center IS NULL),
        count(*) FILTER (WHERE center IS NOT NULL AND GeometryType(center) <> 'POINT'),
        count(*) FILTER (WHERE center IS NOT NULL AND ST_SRID(center) <> 3857),
        count(*) FILTER (
            WHERE geom IS NOT NULL AND center IS NOT NULL AND NOT ST_Covers(geom, center)
        )
    FROM hist_polygon;
")"
if [[ "${center_metrics}" == '0|84651|0|0|0' ]]; then
    printf 'PASS %-24s geometry=%s\n' hist_polygon_center "${center_metrics}"
else
    printf 'FAIL %-24s geometry=%s expected=%s\n' \
        hist_polygon_center "${center_metrics}" '0|84651|0|0|0' >&2
    status=1
fi

declare -Ar expected_minor_metrics=(
    [hist_line]='26591|10605|6521|26'
    [hist_polygon]='19765|10142|4132|35'
)
for table in hist_line hist_polygon; do
    actual="$(${psql[@]} -d "${DATABASE_NAME}" -AtF '|' -c "
        SELECT
            count(*) FILTER (WHERE minor > 0),
            count(DISTINCT id) FILTER (WHERE minor > 0),
            count(*) FILTER (WHERE minor > 0 AND valid_from = valid_to),
            max(minor)
        FROM ${table};
    ")"
    if [[ "${actual}" == "${expected_minor_metrics[${table}]}" ]]; then
        printf 'PASS %-24s minor_versions=%s\n' "${table}" "${actual}"
    else
        printf 'FAIL %-24s minor_versions=%s expected=%s\n' \
            "${table}" "${actual}" "${expected_minor_metrics[${table}]}" >&2
        status=1
    fi
done

printf 'Parity database retained for inspection: %s\n' "${DATABASE_NAME}"
exit "${status}"
