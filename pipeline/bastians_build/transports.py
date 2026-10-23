"""Transports (route.md): hand-written tables per client (config/transports_<client>.toml) read into
`transport` records of the world pack. Pure: TOML in, records out.

File format (the TOML carries the field comments)::

    [[transport]]
    id = "boat-menethil-auberdine"
    kind = "boat"                      # boat | zeppelin | tram | portal
    name = "Menethil Harbor - Auberdine"
    faction = "both"                   # Alliance | Horde | both
    stops = [[1437, 0.048, 0.571, "Menethil Harbor"], [1439, 0.324, 0.436, "Auberdine"]]
    ride = 150                         # seconds one way, optional
    cycle = 420                        # seconds per loop, optional
    verified = false
    note = "..."

The record keeps the stops as given and derives `spawns` (one per stop, src `config`) so the
entity has locations; `world` (continent, wx, wy per stop) is filled from the transform table when
the build has one, so the planner never depends on the runtime conversion.
"""

from __future__ import annotations

import tomllib
from pathlib import Path

from bastians_build.model import World
from bastians_build.sources.probe import Transform

KINDS = ("boat", "zeppelin", "tram", "portal")
FACTIONS = ("Alliance", "Horde", "both")


class TransportError(ValueError):
    """The transport file is malformed."""


def read_transports(path: Path) -> list[dict]:
    """The transport rows of one file, validated for shape; ids are unique."""
    with path.open("rb") as fh:
        data = tomllib.load(fh)
    rows = data.get("transport", [])
    if not isinstance(rows, list):
        raise TransportError(f"{path.name}: [[transport]] must be an array of tables")
    seen: set[str] = set()
    out: list[dict] = []
    for i, row in enumerate(rows, 1):
        where = f"{path.name}: transport {i}"
        for key in ("id", "kind", "name", "faction", "stops"):
            if key not in row:
                raise TransportError(f"{where}: missing {key}")
        if row["id"] in seen:
            raise TransportError(f"{where}: duplicate id {row['id']!r}")
        seen.add(row["id"])
        if row["kind"] not in KINDS:
            raise TransportError(f"{where}: kind must be one of {KINDS}")
        if row["faction"] not in FACTIONS:
            raise TransportError(f"{where}: faction must be one of {FACTIONS}")
        stops = row["stops"]
        if not isinstance(stops, list) or len(stops) < 2:
            raise TransportError(
                f"{where}: stops needs at least two [uiMapID, x, y, label] entries"
            )
        for n, stop in enumerate(stops, 1):
            if (
                not isinstance(stop, list)
                or len(stop) != 4
                or not isinstance(stop[0], int)
                or not all(isinstance(v, int | float) for v in stop[1:3])
                or not isinstance(stop[3], str)
            ):
                raise TransportError(f"{where}: stop {n} must be [uiMapID, x, y, label]")
            if not (0 <= stop[1] <= 1 and 0 <= stop[2] <= 1):
                raise TransportError(f"{where}: stop {n} must use map fractions 0..1")
        for key in ("ride", "cycle"):
            value = row.get(key)
            if value is not None and (not isinstance(value, int | float) or value <= 0):
                raise TransportError(
                    f"{where}: {key} must be a positive number of seconds or absent"
                )
        out.append(
            {
                "id": row["id"],
                "kind": row["kind"],
                "name": row["name"],
                "faction": row["faction"],
                "stops": [list(s) for s in stops],
                "ride": row.get("ride"),
                "cycle": row.get("cycle"),
                "verified": bool(row.get("verified", False)),
                "note": row.get("note"),
            }
        )
    return out


def stop_world(transforms: dict[int, Transform] | None, stop: list) -> list | None:
    """[continent, wx, wy] of a stop through the transform table, or None without one."""
    t = transforms.get(stop[0]) if transforms else None
    if t is None:
        return None
    x, y = stop[1], stop[2]
    wx = t.wx0 + x * t.wx_dx + y * t.wx_dy
    wy = t.wy0 + x * t.wy_dx + y * t.wy_dy
    return [t.continent, round(wx, 2), round(wy, 2)]


def add_transports(
    world: World, path: Path, transforms: dict[int, Transform] | None = None
) -> list[str]:
    """Add the transports of `path` to the world; returns the notes (stops without a transform)."""
    notes: list[str] = []
    for row in read_transports(path):
        record = dict(row)
        record_id = record.pop("id")
        record["spawns"] = [[s[0], s[1], s[2], "config"] for s in record["stops"]]
        world_points = [stop_world(transforms, s) for s in record["stops"]]
        if transforms and any(p is None for p in world_points):
            missing = [
                s[3] for s, p in zip(record["stops"], world_points, strict=True) if p is None
            ]
            notes.append(f"transport {record_id}: no map transform for {', '.join(missing)}")
        record["world"] = world_points if all(p is not None for p in world_points) else None
        record["src"] = "measured" if record["verified"] else "assumed"
        world.add("transport", record_id, record)
    world.notes.extend(notes)
    return notes
