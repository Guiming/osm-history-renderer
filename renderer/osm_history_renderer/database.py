"""Safe creation and cleanup of osm2pgsql-compatible history views."""

from __future__ import annotations

from contextlib import contextmanager
from datetime import datetime
from typing import Callable, Iterator, Sequence

RESERVED_VIEW_COLUMNS = {"osm_id", "z_order", "way", "way_area", "tags"}


def _dependencies():
    import psycopg
    from psycopg import sql

    return psycopg, sql


def _view_names(view_prefix: str) -> tuple[str, ...]:
    return tuple(f"{view_prefix}_{suffix}" for suffix in ("point", "line", "roads", "polygon"))


def _tag_expressions(sql, columns: Sequence[str], hstore: bool):
    if hstore:
        return [sql.SQL("tags AS tags")]
    conflicts = RESERVED_VIEW_COLUMNS.intersection(columns)
    if conflicts:
        names = ", ".join(sorted(conflicts))
        raise ValueError(f"tag columns conflict with required view columns: {names}")
    return [
        sql.SQL("tags -> {} AS {}").format(sql.Literal(column), sql.Identifier(column))
        for column in columns
    ]


def _select_list(sql, columns: Sequence[str], hstore: bool, kind: str):
    expressions = [sql.SQL("id AS osm_id"), *_tag_expressions(sql, columns, hstore)]
    if kind == "point":
        expressions.append(sql.SQL("0::integer AS z_order"))
    else:
        expressions.append(sql.SQL("z_order"))
    if kind == "polygon":
        expressions.append(sql.SQL("area AS way_area"))
    expressions.append(sql.SQL("geom AS way"))
    return sql.SQL(", ").join(expressions)


def create_history_views(
    dsn: str,
    db_prefix: str,
    view_prefix: str,
    hstore: bool,
    columns: Sequence[str],
    at: datetime,
    *,
    connect: Callable | None = None,
) -> None:
    """Create four typed views for a historical instant.

    PostGIS exposes ``geometry_columns`` as a view, so it is deliberately not
    modified. Identifier and literal composition is handled by Psycopg.
    """
    psycopg, sql = _dependencies()
    connector = connect or psycopg.connect
    view_names = _view_names(view_prefix)
    sources = {
        "point": f"{db_prefix}_point",
        "line": f"{db_prefix}_line",
        "roads": f"{db_prefix}_line",
        "polygon": f"{db_prefix}_polygon",
    }
    instant = sql.Literal(at)

    with connector(dsn) as connection:
        with connection.cursor() as cursor:
            for view_name in view_names:
                cursor.execute(
                    sql.SQL("DROP VIEW IF EXISTS {} CASCADE").format(sql.Identifier(view_name))
                )
            for kind, view_name in zip(("point", "line", "roads", "polygon"), view_names):
                cursor.execute(
                    sql.SQL(
                        "CREATE VIEW {} AS SELECT {} FROM {} "
                        "WHERE {} BETWEEN valid_from "
                        "AND COALESCE(valid_to, 'infinity'::timestamp)"
                    ).format(
                        sql.Identifier(view_name),
                        _select_list(sql, columns, hstore, "line" if kind == "roads" else kind),
                        sql.Identifier(sources[kind]),
                        instant,
                    )
                )


def drop_history_views(
    dsn: str,
    view_prefix: str,
    *,
    connect: Callable | None = None,
) -> None:
    """Drop all compatibility views, tolerating partial prior creation."""
    psycopg, sql = _dependencies()
    connector = connect or psycopg.connect
    with connector(dsn) as connection:
        with connection.cursor() as cursor:
            for view_name in reversed(_view_names(view_prefix)):
                cursor.execute(
                    sql.SQL("DROP VIEW IF EXISTS {} CASCADE").format(sql.Identifier(view_name))
                )


@contextmanager
def history_views(
    dsn: str,
    db_prefix: str,
    view_prefix: str,
    hstore: bool,
    columns: Sequence[str],
    at: datetime,
) -> Iterator[None]:
    """Create views for one render and always remove them afterward."""
    create_history_views(dsn, db_prefix, view_prefix, hstore, columns, at)
    try:
        yield
    finally:
        drop_history_views(dsn, view_prefix)


def infer_animation_start(
    dsn: str,
    db_prefix: str,
    bbox: tuple[float, float, float, float],
    *,
    connect: Callable | None = None,
) -> datetime | None:
    """Return the earliest point version intersecting a WGS84 bbox."""
    psycopg, sql = _dependencies()
    connector = connect or psycopg.connect
    query = sql.SQL(
        "SELECT MIN(valid_from) FROM {} "
        "WHERE geom && ST_Transform(ST_MakeEnvelope(%s, %s, %s, %s, 4326), 3857)"
    ).format(sql.Identifier(f"{db_prefix}_point"))
    with connector(dsn) as connection:
        with connection.cursor() as cursor:
            cursor.execute(query, bbox)
            row = cursor.fetchone()
    return row[0] if row else None
