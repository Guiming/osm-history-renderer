import os
from datetime import datetime

import psycopg
import pytest

from osm_history_renderer.database import create_history_views, drop_history_views


@pytest.mark.integration
def test_history_views_on_postgis():
    dsn = os.environ.get("OSM_HISTORY_TEST_DSN")
    if not dsn:
        pytest.skip("OSM_HISTORY_TEST_DSN is not set")
    prefix = "geos315_renderer_test"
    try:
        create_history_views(dsn, "hist", prefix, False, ("name", "highway"), datetime(2025, 1, 31))
        with psycopg.connect(dsn) as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    "SELECT table_name FROM information_schema.views "
                    "WHERE table_schema = 'public' AND table_name LIKE %s ORDER BY table_name",
                    (f"{prefix}_%",),
                )
                assert [row[0] for row in cursor.fetchall()] == [
                    f"{prefix}_line",
                    f"{prefix}_point",
                    f"{prefix}_polygon",
                    f"{prefix}_roads",
                ]
                cursor.execute(
                    "SELECT f_table_name, type, srid FROM geometry_columns "
                    "WHERE f_table_name LIKE %s ORDER BY f_table_name",
                    (f"{prefix}_%",),
                )
                rows = cursor.fetchall()
                assert len(rows) == 4
                assert {row[2] for row in rows} == {3857}
    finally:
        drop_history_views(dsn, prefix)
