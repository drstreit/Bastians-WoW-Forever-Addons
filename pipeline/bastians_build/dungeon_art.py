"""Hand-drawn dungeon maps (ADR 0048, data.md "Dungeons"): config/dungeon_art.toml names, per
dungeon, the floors drawn by an artist (the tiles ship in Bastians_Core, tools/dungeon_art.py) and
our pins on them; they replace the dungeon's floors, boss spots and door. Pure: TOML in, record
fields plus notes out.

A floor becomes `{n, a, g, w, h, by}`: the art prefix of Core's tiles, the 4 x 3 grid of 256 px,
the map's 1024 x 682 pixels and the artist's key (the addon credits the artist under the map).
Boss pins are checked against the dungeon's bosses: an order the dungeon lacks or a name that
differs is a note in the build report, never a build failure.
"""

from __future__ import annotations

import tomllib
from pathlib import Path

from bastians_build.model import World

ART_PREFIX = "Interface\\AddOns\\Bastians_Core\\Media\\Dungeons\\"
GRID = (4, 3)
SIZE = (1024, 682)
ARTISTS = frozenset({"santiago"})


class DungeonArtError(ValueError):
    """The dungeon art file is malformed."""


def _point(where: str, row: object, floors: int) -> tuple[int, float, float]:
    if not isinstance(row, dict):
        raise DungeonArtError(f"{where}: must be a table")
    floor, x, y = row.get("floor"), row.get("x"), row.get("y")
    if not isinstance(floor, int) or not 1 <= floor <= floors:
        raise DungeonArtError(f"{where}: floor must be 1..{floors}")
    for value in (x, y):
        if not isinstance(value, int | float) or not 0 <= value <= 100:
            raise DungeonArtError(f"{where}: x and y must be 0..100")
    return floor, float(x), float(y)


def read_dungeon_art(path: Path) -> list[dict]:
    """The dungeons of one file, validated for shape; ids are unique."""
    with path.open("rb") as fh:
        data = tomllib.load(fh)
    rows = data.get("dungeon", [])
    if not isinstance(rows, list):
        raise DungeonArtError(f"{path.name}: [[dungeon]] must be an array of tables")
    seen: set[int] = set()
    out = []
    for i, row in enumerate(rows, 1):
        where = f"{path.name}: dungeon {i}"
        if not isinstance(row.get("id"), int):
            raise DungeonArtError(f"{where}: id must be the instance's map id")
        if row["id"] in seen:
            raise DungeonArtError(f"{where}: duplicate id {row['id']}")
        seen.add(row["id"])
        floors = row.get("floors")
        if not isinstance(floors, list) or not floors:
            raise DungeonArtError(f"{where}: floors must be a non-empty list")
        for n, f in enumerate(floors, 1):
            if not (isinstance(f, dict) and f.get("name") and f.get("art")):
                raise DungeonArtError(f"{where}: floor {n} needs name and art")
            if f.get("by") not in ARTISTS:
                raise DungeonArtError(f"{where}: floor {n} by must be one of {sorted(ARTISTS)}")
        door = row.get("door")
        bosses = []
        for n, b in enumerate(row.get("bosses", []), 1):
            if not (isinstance(b, dict) and isinstance(b.get("order"), int) and b.get("name")):
                raise DungeonArtError(f"{where}: boss {n} needs order and name")
            bosses.append((b["order"], b["name"], *_point(f"{where}: boss {n}", b, len(floors))))
        out.append(
            {
                "id": row["id"],
                "name": row.get("name"),
                "verified": bool(row.get("verified", False)),
                "floors": [(f["name"], f["art"], f["by"]) for f in floors],
                "door": _point(f"{where}: door", door, len(floors)) if door else None,
                "bosses": bosses,
            }
        )
    return out


def add_dungeon_art(world: World, path: Path) -> list[str]:
    """Lay the hand-drawn floors of `path` onto the world's dungeons; returns the notes."""
    notes: list[str] = []
    for row in read_dungeon_art(path):
        rec = world.get("dungeon", row["id"])
        if rec is None:
            notes.append(f"dungeon art {row['id']} {row['name']}: no dungeon record, left out")
            continue
        rec["floors"] = [
            {
                "n": name,
                "a": f"{ART_PREFIX}{art}_",
                "g": list(GRID),
                "w": SIZE[0],
                "h": SIZE[1],
                "by": by,
            }
            for name, art, by in row["floors"]
        ]
        known = {int(b[0]): str(b[2]) for b in rec.get("bosses") or []}
        spots = []
        for order, name, floor, x, y in sorted(row["bosses"]):
            if order not in known:
                notes.append(f"dungeon art {row['id']}: boss {order} ({name}) is not in the data")
                continue
            if known[order] != name:
                notes.append(
                    f"dungeon art {row['id']}: boss {order} is named {known[order]!r} in the"
                    f" data, the map says {name!r}"
                )
            spots.append([order, floor, x, y])
        rec["bossSpots"] = spots or None
        rec["door"] = list(row["door"]) if row["door"] else None
    world.notes.extend(notes)
    return notes
