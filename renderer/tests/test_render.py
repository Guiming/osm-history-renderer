from datetime import datetime
from pathlib import Path

from PIL import Image

from osm_history_renderer.render import RenderConfig, build_parser, config_from_namespace, render_map


def test_legacy_arguments_build_a_typed_config():
    options = build_parser().parse_args(
        [
            "--date",
            "2025-01-31",
            "--size",
            "320x200",
            "--bbox",
            "73.45,4.10,73.65,4.30",
            "--extra-view-columns",
            "source",
        ]
    )
    config = config_from_namespace(options)
    assert config.size == (320, 200)
    assert config.at == datetime(2025, 1, 31)
    assert "source" in config.columns


def test_mapnik_png_smoke_without_database(tmp_path):
    style = tmp_path / "empty.xml"
    style.write_text(
        '<Map background-color="#f4f6fa" srs="EPSG:3857"></Map>',
        encoding="utf-8",
    )
    config = RenderConfig(
        style=style,
        output=tmp_path / "map",
        output_type="png",
        size=(64, 48),
        bbox=(-1.0, -1.0, 1.0, 1.0),
        at=datetime(2025, 1, 31),
        create_views=False,
    )
    output = render_map(config)
    assert output == Path(tmp_path / "map.png")
    with Image.open(output) as image:
        assert image.size == (64, 48)
