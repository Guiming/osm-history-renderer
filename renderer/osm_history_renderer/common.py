"""Shared argument parsing and Web Mercator calculations."""

from __future__ import annotations

from datetime import datetime
from math import log, pi, radians, tan

DEFAULT_COLUMNS = (
    "access,addr:housename,addr:housenumber,addr:interpolation,admin_level,"
    "aerialway,aeroway,amenity,area,barrier,bicycle,brand,bridge,boundary,"
    "building,construction,covered,culvert,cutting,denomination,disused,"
    "embankment,foot,generator:source,harbour,highway,tracktype,capital,ele,"
    "historic,horse,intermittent,junction,landuse,layer,leisure,lock,man_made,"
    "military,motorcar,name,natural,oneway,operator,population,power,"
    "power_source,place,railway,ref,religion,route,service,shop,sport,surface,"
    "toll,tourism,tower:type,tunnel,water,waterway,wetland,width,wood"
)

WEB_MERCATOR_RADIUS = 6_378_137.0
WEB_MERCATOR_MAX_LATITUDE = 85.0511287798066
INITIAL_RESOLUTION = 2.0 * pi * WEB_MERCATOR_RADIUS / 256.0


def parse_size(value: str) -> tuple[int, int]:
    """Parse WIDTHxHEIGHT, rejecting zero or negative dimensions."""
    try:
        width_text, height_text = value.lower().split("x", maxsplit=1)
        width, height = int(width_text), int(height_text)
    except (TypeError, ValueError) as error:
        raise ValueError("size must use WIDTHxHEIGHT") from error
    if width <= 0 or height <= 0:
        raise ValueError("size dimensions must be positive")
    return width, height


def parse_bbox(value: str) -> tuple[float, float, float, float]:
    """Parse and validate a WGS84 left,bottom,right,top bounding box."""
    try:
        values = tuple(float(part) for part in value.split(","))
    except (AttributeError, ValueError) as error:
        raise ValueError("bbox must contain four comma-separated numbers") from error
    if len(values) != 4:
        raise ValueError("bbox must contain exactly four numbers")
    left, bottom, right, top = values
    if left >= right or bottom >= top:
        raise ValueError("bbox must satisfy left < right and bottom < top")
    if not (-180.0 <= left <= 180.0 and -180.0 <= right <= 180.0):
        raise ValueError("bbox longitudes must be between -180 and 180")
    if not (-90.0 <= bottom <= 90.0 and -90.0 <= top <= 90.0):
        raise ValueError("bbox latitudes must be between -90 and 90")
    return left, bottom, right, top


def parse_datetime(value: str) -> datetime:
    """Parse an ISO date or timestamp."""
    normalized = value.strip().replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(normalized)
    except ValueError as error:
        raise ValueError("date must be ISO-8601 (YYYY-MM-DD or timestamp)") from error


def parse_columns(value: str) -> tuple[str, ...]:
    """Return a stable, de-duplicated list of hstore keys."""
    columns: list[str] = []
    seen: set[str] = set()
    for raw_column in value.split(","):
        column = raw_column.strip()
        if column and column not in seen:
            columns.append(column)
            seen.add(column)
    return tuple(columns)


def _mercator_xy(longitude: float, latitude: float) -> tuple[float, float]:
    latitude = max(-WEB_MERCATOR_MAX_LATITUDE, min(WEB_MERCATOR_MAX_LATITUDE, latitude))
    x = WEB_MERCATOR_RADIUS * radians(longitude)
    y = WEB_MERCATOR_RADIUS * log(tan(pi / 4.0 + radians(latitude) / 2.0))
    return x, y


def zoom_size(bbox: tuple[float, float, float, float], zoom: int) -> tuple[int, int]:
    """Calculate pixel dimensions for a WGS84 bbox at a slippy-map zoom."""
    if not 0 <= zoom <= 24:
        raise ValueError("zoom must be between 0 and 24")
    left, bottom, right, top = bbox
    min_x, min_y = _mercator_xy(left, bottom)
    max_x, max_y = _mercator_xy(right, top)
    metres_per_pixel = INITIAL_RESOLUTION / (2**zoom)
    return (
        max(1, int((max_x - min_x) / metres_per_pixel)),
        max(1, int((max_y - min_y) / metres_per_pixel)),
    )
