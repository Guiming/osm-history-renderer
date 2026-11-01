"""Render a dated PNG sequence and a self-contained HTML player."""

from __future__ import annotations

import argparse
from dataclasses import replace
from datetime import datetime
from html import escape
import json
from pathlib import Path
import sys

from dateutil.relativedelta import relativedelta

from .common import DEFAULT_COLUMNS, parse_bbox, parse_columns, parse_datetime, parse_size, zoom_size
from .database import infer_animation_start
from .render import RenderConfig, _argument_type, render_map


def parse_step(value: str) -> relativedelta:
    """Parse ``months=+1 days=+2`` into a positive relativedelta."""
    arguments: dict[str, int] = {}
    allowed = {"years", "months", "weeks", "days", "hours", "minutes", "seconds"}
    try:
        for part in value.replace(",", " ").split():
            key, raw_number = part.split("=", maxsplit=1)
            if key not in allowed:
                raise ValueError(f"unsupported step unit: {key}")
            arguments[key] = int(raw_number)
    except (TypeError, ValueError) as error:
        if isinstance(error, ValueError) and str(error).startswith("unsupported"):
            raise
        raise ValueError("step must look like 'months=+1' or 'days=+14'") from error
    if not arguments:
        raise ValueError("step cannot be empty")
    step = relativedelta(**arguments)
    reference = datetime(2000, 1, 1)
    if reference + step <= reference:
        raise ValueError("step must advance time")
    return step


def build_animation_html(
    output: Path,
    frame_directory: str,
    frame_count: int,
    fps: float,
    width: int,
    height: int,
) -> None:
    """Write a local-only HTML player with no remote JavaScript."""
    if frame_count <= 0:
        raise ValueError("cannot build an animation without frames")
    directory_json = json.dumps(frame_directory)
    title = escape(output.stem)
    html = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{title}</title>
  <style>
    body {{ margin: 0; padding: 2rem; color: #172033; background: #f4f6fa; font: 16px system-ui, sans-serif; }}
    main {{ width: min(100%, {width}px); margin: auto; }}
    img {{ display: block; width: 100%; height: auto; background: white; box-shadow: 0 4px 24px #0002; }}
    .controls {{ display: grid; grid-template-columns: auto 1fr auto; gap: .75rem; align-items: center; margin-top: 1rem; }}
    button {{ padding: .5rem 1rem; }}
    input {{ width: 100%; }}
  </style>
</head>
<body>
<main>
  <img id="frame" src="{escape(frame_directory)}/0000000000.png" width="{width}" height="{height}" alt="Historical map frame">
  <div class="controls">
    <button id="toggle" type="button">Pause</button>
    <input id="position" type="range" min="0" max="{frame_count - 1}" value="0" step="1" aria-label="Animation frame">
    <output id="counter">1 / {frame_count}</output>
  </div>
</main>
<script>
(() => {{
  const directory = {directory_json};
  const count = {frame_count};
  const delay = 1000 / {fps!r};
  const image = document.querySelector('#frame');
  const slider = document.querySelector('#position');
  const counter = document.querySelector('#counter');
  const toggle = document.querySelector('#toggle');
  let playing = true;
  let timer;
  const show = (index) => {{
    const normalized = ((Number(index) % count) + count) % count;
    slider.value = normalized;
    image.src = `${{directory}}/${{String(normalized).padStart(10, '0')}}.png`;
    counter.value = `${{normalized + 1}} / ${{count}}`;
  }};
  const schedule = () => {{
    clearTimeout(timer);
    if (playing) timer = setTimeout(() => {{ show(Number(slider.value) + 1); schedule(); }}, delay);
  }};
  slider.addEventListener('input', () => {{ show(slider.value); schedule(); }});
  toggle.addEventListener('click', () => {{
    playing = !playing;
    toggle.textContent = playing ? 'Pause' : 'Play';
    schedule();
  }});
  schedule();
}})();
</script>
</body>
</html>
"""
    output.write_text(html, encoding="utf-8")


def add_label(path: Path, text: str, gravity: str) -> None:
    """Draw a readable date label with Pillow."""
    from PIL import Image, ImageDraw, ImageFont

    with Image.open(path) as source:
        image = source.convert("RGBA")
    draw = ImageDraw.Draw(image)
    font = ImageFont.load_default(size=18)
    left, top, right, bottom = draw.textbbox((0, 0), text, font=font)
    text_width, text_height = right - left, bottom - top
    margin = 12
    normalized = gravity.lower()
    x = margin if "west" in normalized else image.width - text_width - margin if "east" in normalized else (image.width - text_width) // 2
    y = margin if "north" in normalized else image.height - text_height - margin if "south" in normalized else (image.height - text_height) // 2
    padding = 5
    draw.rounded_rectangle(
        (x - padding, y - padding, x + text_width + padding, y + text_height + padding),
        radius=4,
        fill=(255, 255, 255, 210),
    )
    draw.text((x, y), text, fill="black", font=font)
    image.convert("RGB").save(path, "PNG")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-s", "--style", type=Path, default=Path("/usr/share/osm-mapnik/osm.xml"))
    parser.add_argument("-f", "--file", dest="output", type=Path, default=Path("animap"))
    parser.add_argument("-x", "--size", type=_argument_type(parser, parse_size), default=parse_size("800x600"))
    parser.add_argument("-b", "--bbox", type=_argument_type(parser, parse_bbox), default=parse_bbox("-180,-85,180,85"))
    parser.add_argument("-z", "--zoom", type=int)
    parser.add_argument("-v", "--view", dest="create_views", action="store_true", default=True)
    parser.add_argument("--no-view", dest="create_views", action="store_false")
    parser.add_argument("--retain-views", action="store_true")
    parser.add_argument("-p", "--view-prefix", default="hist_view")
    parser.add_argument("-o", "--view-hstore", dest="hstore", action="store_true")
    parser.add_argument("-c", "--view-columns", default=DEFAULT_COLUMNS)
    parser.add_argument("-e", "--extra-view-columns", default="")
    parser.add_argument("-A", "--anistart", type=_argument_type(parser, parse_datetime))
    parser.add_argument("-Z", "--aniend", type=_argument_type(parser, parse_datetime))
    parser.add_argument("-S", "--anistep", type=_argument_type(parser, parse_step), default=parse_step("months=+1"))
    parser.add_argument("-F", "--fps", type=float, default=2.0)
    parser.add_argument("-L", "--label")
    parser.add_argument(
        "-G", "--label-gravity", default="South", choices=("North", "NorthEast", "East", "SouthEast", "South", "SouthWest", "West", "NorthWest", "Center")
    )
    parser.add_argument("-D", "--db", dest="dsn", default="")
    parser.add_argument("-P", "--dbprefix", dest="db_prefix", default="hist")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    options = parser.parse_args(argv)
    if options.fps <= 0:
        parser.error("--fps must be positive")
    start = options.anistart or infer_animation_start(options.dsn, options.db_prefix, options.bbox)
    if start is None:
        print("error: no point history intersects the requested bbox", file=sys.stderr)
        return 1
    end = options.aniend or datetime.now(tz=start.tzinfo)
    if end <= start:
        parser.error("--aniend must be later than --anistart")
    output_directory: Path = options.output
    output_html = output_directory.with_suffix(".html")
    if output_directory.exists() or output_html.exists():
        print(f"error: output already exists: {output_directory} or {output_html}", file=sys.stderr)
        return 1
    output_directory.mkdir(parents=True)
    size = zoom_size(options.bbox, options.zoom) if options.zoom is not None else options.size
    columns = parse_columns(
        ",".join(value for value in (options.view_columns, options.extra_view_columns) if value)
    )
    base = RenderConfig(
        style=options.style,
        output=output_directory / "0000000000",
        output_type="png",
        size=size,
        bbox=options.bbox,
        at=start,
        dsn=options.dsn,
        db_prefix=options.db_prefix,
        view_prefix=options.view_prefix,
        create_views=options.create_views,
        retain_views=options.retain_views,
        hstore=options.hstore,
        columns=columns,
    )
    frame_count = 0
    current = start
    try:
        while current < end:
            frame_base = output_directory / f"{frame_count:010d}"
            frame_path = render_map(replace(base, output=frame_base, at=current))
            if options.label:
                add_label(frame_path, current.strftime(options.label), options.label_gravity)
            frame_count += 1
            current += options.anistep
        build_animation_html(output_html, output_directory.name, frame_count, options.fps, *size)
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(f"rendered {frame_count} frames and {output_html}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
