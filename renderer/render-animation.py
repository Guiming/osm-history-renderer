#!/usr/bin/env python3
"""Compatibility wrapper for :command:`osm-history-render-animation`."""

from osm_history_renderer.animation import main


if __name__ == "__main__":
    raise SystemExit(main())
