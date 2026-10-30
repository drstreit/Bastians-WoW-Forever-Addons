"""Our places table (ADR 0026, data.md "Our authored tables"): what the client's tables do not give
the world graph, authored per client in ``pipeline/config/places_<client>.toml``.

Instance entrances and, since 25.10.2026, the transports (boats, zeppelins, the tram, portals:
``[[transport]]``, read and validated by ``transports.py``); since 26.10.2026 the teleports a
character may have (``[[teleport]]``, route.md "Home and every way back"). Every validated
entrance becomes an ``entrance`` record of the world pack: its world position (``continent``,
``wx``, ``wy``, ``wz``: the canonical place, coordinates.md) and, for drawing, a map place through
the transform table (``spawns``), the instance's Map.db2 id and name, the required level, and
``verified`` (date, build and how it was checked in game; None until then).
"""

from __future__ import annotations

import re
import tomllib
from pathlib import Path

from bastians_build.coords import best_map
from bastians_build.model import World
from bastians_build.sources.probe import Transform

ENTRANCE_ID = re.compile(r"^(\d+)-(\d+)$")  # <instance Map.db2 id>-<n>, n from 1
ENTRANCE_KEYS = {"id", "instance", "name", "label", "place", "level", "src", "verified", "note"}
TELEPORT_ID = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
TELEPORT_KEYS = {
    "id",
    "name",
    "kind",
    "spell",
    "item",
    "place",
    "hearth",
    "cast",
    "faction",
    "class",
    "reagent",
    "src",
    "verified",
    "note",
}
TELEPORT_KINDS = {"spell", "item", "toy"}
TELEPORT_CAST = 10  # seconds a teleport takes when its row gives none


class PlacesError(ValueError):
    pass


def _number(value) -> bool:
    return isinstance(value, int | float) and not isinstance(value, bool)


def read_places(path: Path) -> dict[str, list[dict]]:
    """The table's sections, validated: ``{"entrance": [row, ...], "teleport": [row, ...]}``."""
    raw = tomllib.loads(path.read_text(encoding="utf-8"))
    unknown = sorted(set(raw) - {"entrance", "transport", "teleport"})
    if unknown:
        raise PlacesError(f"{path.name}: unknown sections {', '.join(unknown)}")
    entrances, seen = [], set()
    for n, row in enumerate(raw.get("entrance") or [], 1):
        where = f"{path.name} entrance {n}"
        extra = sorted(set(row) - ENTRANCE_KEYS)
        if extra:
            raise PlacesError(f"{where}: unknown keys {', '.join(extra)}")
        rid = row.get("id")
        m = ENTRANCE_ID.match(rid) if isinstance(rid, str) else None
        if not m or int(m.group(2)) < 1:
            raise PlacesError(f"{where}: id must be '<instance>-<n>', got {rid!r}")
        if rid in seen:
            raise PlacesError(f"{where}: id {rid} twice")
        seen.add(rid)
        instance = row.get("instance")
        if not isinstance(instance, int) or int(m.group(1)) != instance:
            raise PlacesError(f"{where}: instance must be the id's first number ({m.group(1)})")
        if not isinstance(row.get("name"), str) or not row["name"]:
            raise PlacesError(f"{where}: name is required")
        place = row.get("place")
        if (
            not isinstance(place, list)
            or len(place) not in (3, 4)
            or not isinstance(place[0], int)
            or not all(_number(v) for v in place[1:])
        ):
            raise PlacesError(f"{where}: place must be [map, wx, wy] or [map, wx, wy, wz]")
        level = row.get("level")
        if level is not None and (not isinstance(level, int) or level < 0):
            raise PlacesError(f"{where}: level must be a whole number")
        if not isinstance(row.get("src"), str) or not row["src"]:
            raise PlacesError(f"{where}: src is required (where the place comes from)")
        entrances.append(dict(row))
    return {"entrance": entrances, "teleport": _teleports(path, raw.get("teleport") or [])}


def _place_ok(place) -> bool:
    return (
        isinstance(place, list)
        and len(place) in (3, 4)
        and isinstance(place[0], int)
        and all(_number(v) for v in place[1:])
    )


def _teleports(path: Path, rows: list[dict]) -> list[dict]:
    out, seen = [], set()
    for n, row in enumerate(rows, 1):
        where = f"{path.name} teleport {n}"
        extra = sorted(set(row) - TELEPORT_KEYS)
        if extra:
            raise PlacesError(f"{where}: unknown keys {', '.join(extra)}")
        rid = row.get("id")
        if not isinstance(rid, str) or not TELEPORT_ID.match(rid) or rid in seen:
            raise PlacesError(f"{where}: id must be a unique lower-case slug, got {rid!r}")
        seen.add(rid)
        if not isinstance(row.get("name"), str) or not row["name"]:
            raise PlacesError(f"{where}: name is required")
        kind = row.get("kind")
        if kind not in TELEPORT_KINDS:
            raise PlacesError(f"{where}: kind must be one of {sorted(TELEPORT_KINDS)}")
        key = "spell" if kind == "spell" else "item"
        if not isinstance(row.get(key), int) or row[key] <= 0:
            raise PlacesError(f"{where}: a {kind} needs its {key} id")
        hearth = row.get("hearth", False)
        if not isinstance(hearth, bool):
            raise PlacesError(f"{where}: hearth is true or false")
        if hearth == ("place" in row):
            raise PlacesError(f"{where}: give either place or hearth = true")
        if "place" in row and not _place_ok(row["place"]):
            raise PlacesError(f"{where}: place must be [map, wx, wy] or [map, wx, wy, wz]")
        cast = row.get("cast", TELEPORT_CAST)
        if not _number(cast) or cast < 0:
            raise PlacesError(f"{where}: cast must be seconds")
        if row.get("faction") not in (None, "A", "H"):
            raise PlacesError(f"{where}: faction must be A or H")
        for k in ("class", "reagent"):
            if k in row and (not isinstance(row[k], int) or row[k] <= 0):
                raise PlacesError(f"{where}: {k} must be an id")
        if not isinstance(row.get("src"), str) or not row["src"]:
            raise PlacesError(f"{where}: src is required (where the place comes from)")
        out.append(dict(row))
    return out


def add_teleports(world: World, rows: list[dict]) -> None:
    """Add the teleports to the world as ``teleport`` records (a character's way back, route.md)."""
    for row in rows:
        place = row.get("place")
        world.add(
            "teleport",
            row["id"],
            {
                "name": row["name"],
                "kind": row["kind"],
                "spell": row.get("spell"),
                "item": row.get("item"),
                "faction": row.get("faction"),
                "class": row.get("class"),
                "reagent": row.get("reagent"),
                "hearth": True if row.get("hearth") else None,
                "continent": place[0] if place else None,
                "wx": float(place[1]) if place else None,
                "wy": float(place[2]) if place else None,
                "wz": float(place[3]) if place and len(place) > 3 else None,
                "cast": row.get("cast", TELEPORT_CAST),
                "verified": row.get("verified") or None,
                "note": row.get("note"),
                "src": "measured" if row.get("verified") else "places",
            },
        )


def add_entrances(
    world: World, rows: list[dict], transforms: dict[int, Transform] | None = None
) -> list[str]:
    """Add the entrances to the world; returns the notes (places no map contains)."""
    notes: list[str] = []
    for row in rows:
        place = row["place"]
        continent, wx, wy = place[0], float(place[1]), float(place[2])
        wz = float(place[3]) if len(place) > 3 else None
        record = {
            "name": row["name"],
            "label": row.get("label"),
            "instance": row["instance"],
            "level": row.get("level"),
            "continent": continent,
            "wx": wx,
            "wy": wy,
            "wz": wz,
            "verified": row.get("verified") or None,
            "note": row.get("note"),
            "src": "measured" if row.get("verified") else "places",
        }
        if transforms:
            hit = best_map(transforms, continent, wx, wy)
            if hit is None:
                notes.append(f"entrance {row['id']} ({row['name']}): no map contains the place")
            else:
                ui_map_id, x, y = hit
                spawn = [ui_map_id, round(x, 4), round(y, 4), "places"]
                if wz is not None:
                    spawn.append(round(wz, 1))
                record["spawns"] = [spawn]
                record["zone"] = ui_map_id
        world.add("entrance", row["id"], record)
    world.notes.extend(notes)
    return notes
