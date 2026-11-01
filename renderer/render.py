#!/usr/bin/env python3
"""Compatibility wrapper for :command:`osm-history-render`."""

from osm_history_renderer.render import main


if __name__ == "__main__":
    raise SystemExit(main())
