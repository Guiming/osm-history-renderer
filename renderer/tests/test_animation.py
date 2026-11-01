from datetime import datetime

import pytest

from osm_history_renderer.animation import build_animation_html, main, parse_step


def test_step_parser_advances_time():
    assert datetime(2024, 1, 31) + parse_step("months=+1") == datetime(2024, 2, 29)
    assert datetime(2024, 1, 1) + parse_step("weeks=+1 days=+2") == datetime(2024, 1, 10)


@pytest.mark.parametrize("value", ["", "days=0", "days=-1", "fortnights=1"])
def test_non_advancing_or_unknown_steps_fail(value):
    with pytest.raises(ValueError):
        parse_step(value)


def test_animation_html_is_local_and_dependency_free(tmp_path):
    output = tmp_path / "history.html"
    build_animation_html(output, "frames", 3, 2.0, 800, 600)
    html = output.read_text(encoding="utf-8")
    assert "frames/0000000000.png" in html
    assert 'max="2"' in html
    assert "jquery" not in html.lower()
    assert "https://" not in html
    assert "<script src=" not in html


def test_animation_cli_renders_frames_without_database(tmp_path):
    style = tmp_path / "empty.xml"
    style.write_text(
        '<Map background-color="#f4f6fa" srs="EPSG:3857"></Map>',
        encoding="utf-8",
    )
    output = tmp_path / "frames"
    result = main(
        [
            "--style",
            str(style),
            "--file",
            str(output),
            "--no-view",
            "--size",
            "64x48",
            "--bbox",
            "73.45,4.10,73.65,4.30",
            "--anistart",
            "2025-01-01",
            "--aniend",
            "2025-01-03",
            "--anistep",
            "days=+1",
        ]
    )
    assert result == 0
    assert (output / "0000000000.png").is_file()
    assert (output / "0000000001.png").is_file()
    assert output.with_suffix(".html").is_file()
