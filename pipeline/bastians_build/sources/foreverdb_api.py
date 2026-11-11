"""ForeverDB's API rows, as AHSync stored them (sources.md "ForeverDB API", data.md "ForeverDB's
API fills gaps"): where players saw a quest's giver, its hand-in and a vendor in Forever.

The pipeline has no network and no key (CLAUDE.md section 6): AHSync fetches the API once a day
(`ahsync.collect.foreverdb_api`) and leaves `quests.json` and `vendors.json` in a folder this
reader gets as `--foreverdb-api`. Only rows the API marks as seen in WoW Forever are read: its
Classic rows are CMaNGOS' places, which the build has from the dump itself. Coordinates are map
percent 0..100 on the row's uiMapID.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

SEEN = "seen in wow forever"  # the API's source label of a place players recorded
SIDES = {"alliance": "A", "horde": "H", "both": "AH", "neutral": "AH", "a": "A", "h": "H"}
KINDS = ("npc", "object")


@dataclass(frozen=True)
class QuestPlace:
    quest_id: int
    role: str  # "start" or "end"
    kind: str  # "npc" or "object"
    source_id: int  # the giver's or taker's id
    ui_map_id: int
    x_pct: float  # map percent 0..100
    y_pct: float


@dataclass(frozen=True)
class Vendor:
    id: int
    name: str | None
    title: str | None
    side: str | None  # "A", "H", "AH" or None
    ui_map_id: int
    x_pct: float
    y_pct: float


@dataclass
class ApiRows:
    quest_places: list[QuestPlace] = field(default_factory=list)
    vendors: list[Vendor] = field(default_factory=list)
    build: str | None = None
    notes: list[str] = field(default_factory=list)


def _number(value: object) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return float(value)


def _place(location: object) -> tuple[int, float, float] | None:
    """(uiMapID, x percent, y percent) of an API location that players saw, else None."""
    if not isinstance(location, dict):
        return None
    if str(location.get("source") or "").strip().lower() != SEEN:
        return None
    ui_map, x, y = location.get("uiMapId"), _number(location.get("x")), _number(location.get("y"))
    if not isinstance(ui_map, int) or isinstance(ui_map, bool) or ui_map <= 0:
        return None
    if x is None or y is None or not (0 <= x <= 100 and 0 <= y <= 100):
        return None
    return ui_map, x, y


def parse_quests(rows: object) -> list[QuestPlace]:
    out: list[QuestPlace] = []
    for row in rows if isinstance(rows, list) else []:
        if not isinstance(row, dict) or not isinstance(row.get("id"), int):
            continue
        for role, key in (("start", "starts"), ("end", "ends")):
            entry = row.get(key)
            if not isinstance(entry, dict) or entry.get("type") not in KINDS:
                continue
            place = _place(entry.get("location"))
            if place is None or not isinstance(entry.get("id"), int):
                continue
            out.append(QuestPlace(row["id"], role, entry["type"], entry["id"], *place))
    return sorted(out, key=lambda p: (p.quest_id, p.role))


def parse_vendors(rows: object) -> list[Vendor]:
    out: list[Vendor] = []
    for row in rows if isinstance(rows, list) else []:
        if not isinstance(row, dict) or not isinstance(row.get("id"), int):
            continue
        if row.get("seenInForever") is not True:
            continue
        ui_map, x, y = row.get("mapId"), _number(row.get("x")), _number(row.get("y"))
        if not isinstance(ui_map, int) or isinstance(ui_map, bool) or ui_map <= 0:
            continue
        if x is None or y is None or not (0 <= x <= 100 and 0 <= y <= 100):
            continue
        side = SIDES.get(str(row.get("side") or "").strip().lower())
        name = row.get("name") if isinstance(row.get("name"), str) else None
        title = row.get("title") if isinstance(row.get("title"), str) else None
        out.append(Vendor(row["id"], name, title, side, ui_map, x, y))
    return sorted(out, key=lambda v: v.id)


def _read(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8")) if path.is_file() else None


def read_api(folder: Path) -> ApiRows:
    """The folder's `quests.json`, `vendors.json` and `meta.json`. A missing file is a note, a
    file that is no JSON an error (a half-written hand-over must not pass as "no rows")."""
    rows = ApiRows()
    quests, vendors = _read(folder / "quests.json"), _read(folder / "vendors.json")
    for name, value in (("quests.json", quests), ("vendors.json", vendors)):
        if value is None:
            rows.notes.append(f"ForeverDB API: no {name} in {folder}")
    rows.quest_places = parse_quests(quests)
    rows.vendors = parse_vendors(vendors)
    meta = _read(folder / "meta.json")
    if isinstance(meta, dict) and meta.get("build"):
        rows.build = str(meta["build"])
    return rows
