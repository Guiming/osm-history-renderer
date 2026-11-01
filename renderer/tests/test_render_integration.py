import os
from datetime import datetime
from pathlib import Path
from xml.sax.saxutils import escape

from PIL import Image
import psycopg
from psycopg.conninfo import conninfo_to_dict
import pytest

from osm_history_renderer.render import RenderConfig, render_map


@pytest.mark.integration
def test_render_from_temporary_history_view_and_cleanup(tmp_path):
    dsn = os.environ.get("OSM_HISTORY_TEST_DSN")
    if not dsn:
        pytest.skip("OSM_HISTORY_TEST_DSN is not set")
    connection = conninfo_to_dict(dsn)
    prefix = "geos315_mapnik_test"
    datasource_parameters = {
        "type": "postgis",
        "host": connection.get("host", ""),
        "port": connection.get("port", "5432"),
        "dbname": connection["dbname"],
        "table": f'(SELECT way FROM "{prefix}_point" WHERE way IS NOT NULL) AS points',
        "geometry_field": "way",
        "srid": "3857",
    }
    for optional in ("user", "password"):
        if connection.get(optional):
            datasource_parameters[optional] = connection[optional]
    datasource = "\n".join(
        f'<Parameter name="{name}">{escape(value)}</Parameter>'
        for name, value in datasource_parameters.items()
    )
    style = tmp_path / "postgis-smoke.xml"
    style.write_text(
        f"""<Map background-color="#f4f6fa" srs="EPSG:3857">
  <Style name="points">
    <Rule><MarkersSymbolizer fill="#e11d48" width="5" height="5" allow-overlap="true" /></Rule>
  </Style>
  <Layer name="history-points" srs="EPSG:3857">
    <StyleName>points</StyleName>
    <Datasource>{datasource}</Datasource>
  </Layer>
</Map>""",
        encoding="utf-8",
    )
    output = render_map(
        RenderConfig(
            style=style,
            output=tmp_path / "history-snapshot",
            output_type="png",
            size=(160, 160),
            bbox=(73.45, 4.10, 73.65, 4.30),
            at=datetime(2025, 1, 31),
            dsn=dsn,
            view_prefix=prefix,
            columns=("name",),
        )
    )
    assert output == Path(tmp_path / "history-snapshot.png")
    with Image.open(output) as image:
        assert image.size == (160, 160)
        assert len(image.getcolors(maxcolors=160 * 160)) > 1
    with psycopg.connect(dsn) as database:
        with database.cursor() as cursor:
            cursor.execute(
                "SELECT count(*) FROM information_schema.views "
                "WHERE table_schema = 'public' AND table_name LIKE %s",
                (f"{prefix}_%",),
            )
            assert cursor.fetchone()[0] == 0
