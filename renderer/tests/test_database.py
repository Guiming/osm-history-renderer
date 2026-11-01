from datetime import datetime

from osm_history_renderer.database import create_history_views, infer_animation_start


class FakeCursor:
    def __init__(self, row=None):
        self.calls = []
        self.row = row

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def execute(self, query, parameters=None):
        self.calls.append((query, parameters))

    def fetchone(self):
        return self.row


class FakeConnection:
    def __init__(self, cursor):
        self._cursor = cursor

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def cursor(self):
        return self._cursor


def test_view_sql_quotes_identifiers_and_does_not_write_geometry_columns():
    cursor = FakeCursor()
    connect = lambda _dsn: FakeConnection(cursor)
    create_history_views(
        "",
        "hist",
        "unsafe;drop",
        False,
        ("name", "addr:housenumber"),
        datetime(2025, 1, 31),
        connect=connect,
    )
    statements = "\n".join(query.as_string(None) for query, _ in cursor.calls)
    assert '"unsafe;drop_point"' in statements
    assert '"addr:housenumber"' in statements
    assert "geometry_columns" not in statements
    assert "ALTER TABLE" not in statements


def test_date_inference_uses_query_parameters():
    expected = datetime(2012, 3, 4, 5, 6, 7)
    cursor = FakeCursor((expected,))
    connect = lambda _dsn: FakeConnection(cursor)
    bbox = (73.45, 4.10, 73.65, 4.30)
    assert infer_animation_start("", "hist", bbox, connect=connect) == expected
    query, parameters = cursor.calls[0]
    assert '"hist_point"' in query.as_string(None)
    assert parameters == bbox
