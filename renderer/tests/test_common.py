from datetime import datetime

import pytest

from osm_history_renderer.common import (
    parse_bbox,
    parse_columns,
    parse_datetime,
    parse_size,
    zoom_size,
)


def test_parsers_accept_legacy_shapes():
    assert parse_size("800x600") == (800, 600)
    assert parse_bbox("73.45,4.10,73.65,4.30") == (73.45, 4.10, 73.65, 4.30)
    assert parse_datetime("2025-01-31") == datetime(2025, 1, 31)
    assert parse_columns("name, highway,name") == ("name", "highway")


@pytest.mark.parametrize("value", ["800", "0x20", "20x-1", "abcx20"])
def test_invalid_sizes_fail(value):
    with pytest.raises(ValueError):
        parse_size(value)


def test_zoom_size_is_positive_and_doubles_each_zoom():
    bbox = parse_bbox("8.1777,49.7717,8.2056,49.7916")
    at_12 = zoom_size(bbox, 12)
    at_13 = zoom_size(bbox, 13)
    assert at_12[0] > 0 and at_12[1] > 0
    assert at_13[0] in {at_12[0] * 2, at_12[0] * 2 + 1}
    assert at_13[1] in {at_12[1] * 2, at_12[1] * 2 + 1}


def test_zoom_out_of_range_fails():
    with pytest.raises(ValueError):
        zoom_size((0.0, 0.0, 1.0, 1.0), 25)
