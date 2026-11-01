"""Render a historical OpenStreetMap snapshot with Mapnik."""

from __future__ import annotations

import argparse
from contextlib import nullcontext
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
import sys

from .common import DEFAULT_COLUMNS, parse_bbox, parse_columns, parse_datetime, parse_size, zoom_size
from .database import create_history_views, history_views


def _argument_type(parser, converter):
    del parser

    def convert(value: str):
        try:
            return converter(value)
        except ValueError as error:
            raise argparse.ArgumentTypeError(str(error)) from error

    return convert


@dataclass(frozen=True)
class RenderConfig:
    style: Path
    output: Path
    output_type: str
    size: tuple[int, int]
    bbox: tuple[float, float, float, float]
    at: datetime
    dsn: str = ""
    db_prefix: str = "hist"
    view_prefix: str = "hist_view"
    create_views: bool = True
    retain_views: bool = False
    hstore: bool = False
    columns: tuple[str, ...] = ()

    @property
    def output_path(self) -> Path:
        extension = "jpg" if self.output_type == "jpeg" else self.output_type
        if self.output.suffix.lower() == f".{extension}":
            return self.output
        return self.output.with_suffix(f".{extension}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    size_type = _argument_type(parser, parse_size)
    bbox_type = _argument_type(parser, parse_bbox)
    date_type = _argument_type(parser, parse_datetime)
    parser.add_argument("-s", "--style", type=Path, default=Path("/usr/share/osm-mapnik/osm.xml"))
    parser.add_argument("-f", "--file", dest="output", type=Path, default=Path("map"))
    parser.add_argument(
        "-t", "--type", dest="output_type", choices=("png", "jpeg", "svg", "pdf", "ps"), default="png"
    )
    parser.add_argument("-x", "--size", type=size_type, default=parse_size("800x600"))
    parser.add_argument("-b", "--bbox", type=bbox_type, default=parse_bbox("-180,-85,180,85"))
    parser.add_argument("-z", "--zoom", type=int, help="slippy-map zoom; overrides --size")
    parser.add_argument("-d", "--date", dest="at", type=date_type, required=True)
    parser.add_argument("-v", "--view", dest="create_views", action="store_true", default=True)
    parser.add_argument("--no-view", dest="create_views", action="store_false")
    parser.add_argument("--retain-views", action="store_true")
    parser.add_argument("-p", "--view-prefix", default="hist_view")
    parser.add_argument("-o", "--view-hstore", dest="hstore", action="store_true")
    parser.add_argument("-c", "--view-columns", default=DEFAULT_COLUMNS)
    parser.add_argument("-e", "--extra-view-columns", default="")
    parser.add_argument("-D", "--db", dest="dsn", default="")
    parser.add_argument("-P", "--dbprefix", dest="db_prefix", default="hist")
    return parser


def config_from_namespace(options: argparse.Namespace) -> RenderConfig:
    columns = parse_columns(
        ",".join(value for value in (options.view_columns, options.extra_view_columns) if value)
    )
    size = zoom_size(options.bbox, options.zoom) if options.zoom is not None else options.size
    return RenderConfig(
        style=options.style,
        output=options.output,
        output_type=options.output_type,
        size=size,
        bbox=options.bbox,
        at=options.at,
        dsn=options.dsn,
        db_prefix=options.db_prefix,
        view_prefix=options.view_prefix,
        create_views=options.create_views,
        retain_views=options.retain_views,
        hstore=options.hstore,
        columns=columns,
    )


def _load_mapnik():
    try:
        import mapnik
    except ImportError as error:
        raise RuntimeError("Mapnik 4 Python bindings are required; install the renderer environment") from error
    version = getattr(mapnik, "mapnik_version", lambda: 0)()
    if version and version < 4_000_00:
        raise RuntimeError("Mapnik 4 or newer is required")
    return mapnik


def _render_with_mapnik(config: RenderConfig) -> Path:
    mapnik = _load_mapnik()
    if not config.style.is_file():
        raise FileNotFoundError(f"Mapnik style does not exist: {config.style}")
    width, height = config.size
    output = config.output_path
    output.parent.mkdir(parents=True, exist_ok=True)

    map_object = mapnik.Map(width, height)
    mapnik.load_map(map_object, str(config.style))
    wgs84 = mapnik.Projection("+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs")
    web_mercator = mapnik.Projection(
        "+proj=merc +a=6378137 +b=6378137 +lat_ts=0.0 +lon_0=0.0 "
        "+x_0=0.0 +y_0=0 +k=1.0 +units=m +nadgrids=@null +no_defs +over"
    )
    bounds = mapnik.ProjTransform(wgs84, web_mercator).forward(mapnik.Box2d(*config.bbox))
    map_object.zoom_to_box(bounds)

    if config.output_type in {"png", "jpeg"}:
        image = mapnik.Image(width, height)
        mapnik.render(map_object, image)
        image.save(str(output), config.output_type)
        return output

    try:
        import cairo
    except ImportError as error:
        raise RuntimeError("pycairo is required for SVG, PDF, and PostScript output") from error
    surface_class = {
        "svg": cairo.SVGSurface,
        "pdf": cairo.PDFSurface,
        "ps": cairo.PSSurface,
    }[config.output_type]
    surface = surface_class(str(output), width, height)
    try:
        mapnik.render(map_object, surface)
    finally:
        surface.finish()
    return output


def render_map(config: RenderConfig) -> Path:
    """Render one frame, cleaning temporary views even after failures."""
    if not config.create_views:
        context = nullcontext()
    elif config.retain_views:
        create_history_views(
            config.dsn,
            config.db_prefix,
            config.view_prefix,
            config.hstore,
            config.columns,
            config.at,
        )
        context = nullcontext()
    else:
        context = history_views(
            config.dsn,
            config.db_prefix,
            config.view_prefix,
            config.hstore,
            config.columns,
            config.at,
        )
    with context:
        return _render_with_mapnik(config)


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    options = parser.parse_args(argv)
    try:
        config = config_from_namespace(options)
        output = render_map(config)
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(f"rendered {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
