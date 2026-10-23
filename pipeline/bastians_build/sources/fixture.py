"""Reader for the hand-written fixture world (tests/fixtures/world-mini/*.toml).

The fixture is the source of truth for the test packs: `[meta]` plus one array of tables per record
type (`[[npc]]`, `[[zone]]`, ...), each with an `id` and the canonical field names.
"""

from __future__ import annotations

import tomllib
from pathlib import Path

from bastians_build.model import World


class FixtureError(ValueError):
    pass


def _int_keys(value):
    """TOML table keys are strings; keys that are integers (uiMapIDs, item IDs) become ints."""
    if isinstance(value, dict):
        return {
            (int(k) if isinstance(k, str) and k.lstrip("-").isdigit() else k): _int_keys(v)
            for k, v in value.items()
        }
    if isinstance(value, list):
        return [_int_keys(v) for v in value]
    return value


def read_fixture(folder: Path, client: str) -> World:
    files = sorted(folder.glob("*.toml"))
    if not files:
        raise FixtureError(f"no .toml files in {folder}")
    world = World(client=client)
    for path in files:
        with path.open("rb") as fh:
            data = tomllib.load(fh)
        meta = data.pop("meta", {})
        if meta:
            world.build = str(meta.get("build", world.build))
            for source in meta.get("sources", []):
                if source not in world.sources:
                    world.sources.append(source)
            for area, ui_map in (meta.get("area_to_map") or {}).items():
                world.area_to_map[int(area)] = int(ui_map)
            if "client" in meta and meta["client"] != client:
                raise FixtureError(
                    f"{path.name}: fixture is for {meta['client']}, building {client}"
                )
        for record_type, rows in data.items():
            if not isinstance(rows, list):
                raise FixtureError(f"{path.name}: [{record_type}] must be an array of tables")
            for row in rows:
                if "id" not in row:
                    raise FixtureError(f"{path.name}: a {record_type} row has no id")
                record = {k: _int_keys(v) for k, v in row.items()}
                record_id = record.pop("id")
                world.add(record_type, record_id, record)
    from bastians_build.canon import zone_statistics

    zone_statistics(world)
    return world
