# Contributing to the OSM History Viewer Modernization

Thank you for your interest in contributing! This repository is part of the **OSM History Viewer** project and welcomes contributions from the community.

## Project Lineage

Before contributing, understand where this code comes from:

1. **Original project**: [`joto/osm-history-renderer`](https://github.com/joto/osm-history-renderer) (2016–2024) — The original OSM history importer/renderer by @joto
2. **Community fork**: [`MaZderMind/osm-history-renderer`](https://github.com/MaZderMind/osm-history-renderer) — Extended with better documentation and features
3. **This repo**: [`Guiming/osm-history-renderer`](https://github.com/Guiming/osm-history-renderer) — Modernization effort upgrading GEOS (3.10 → 3.15), libosmium (2.6+ → 2.23.1), Mapnik (3.x → 4.x), and PostgreSQL compatibility

## Branch Purpose

- `main` or default branch — Stable modernization target with tested dependencies
- `upgrade/*` branches — Ongoing upgrade work-in-progress

## How to Contribute

### Reporting Issues

Open an issue for:
- Bugs that break functionality verified in the current branch
- Compatibility findings (e.g., "this breaks with GEOS 3.14 but works with 3.15")
- Documentation improvements

Attach a minimal reproducible test case when possible.

### Submitting Pull Requests

1. Fork and clone the repository
2. Create a new branch from `main`
3. Make focused changes (one concern per PR)
4. Ensure tests pass (`make -C importer test`, `pytest -q`)
5. Update documentation if adding/removing features
6. Sign the CLA if required by the project maintainers

#### Code Style

- Follow existing code formatting in `importer/` and `renderer/`
- Add comments for non-obvious logic
- Keep imports minimal and version-pinned where necessary
- Use meaningful commit messages

#### Testing

- Unit tests must pass before committing
- Integration tests require a PostGIS database; see `TUTORIAL.md` section 4
- For renderer changes, ensure the PNG output test produces valid images

### Documentation

- Update `README.md`, `TUTORIAL.md`, or docstrings as needed
- Add examples for new commands or environment variables
- Keep documentation current with tested dependency versions

### Code Reviews

PRs are reviewed on GitHub. Common review concerns:

- Does this change maintain backward compatibility with older `.osh` files?
- Are all modified tests passing?
- Is the code style consistent?
- Is documentation updated where necessary?

## License and Attribution

This modernization build is derived from work by @joto, with contributions from the MaZderMind community. The original code remains under its respective licenses; this fork's changes are subject to the same licensing terms.

When referring to this project in publications or presentations:
- Cite both the original (`joto/osm-history-renderer`) and this modernization branch
- Acknowledge the intermediate `new-osmium-geos` work if building on top of it
- Note that this is an independent project, not affiliated with the OSM Foundation

## License

See [LICENSE](./LICENSE) for terms.

## Contact

For questions or discussions: open an issue or comment on existing ones.
