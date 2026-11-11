"""Our authored quest places (ADR 0070 decision 5, data.md "Our authored table"): what a person
checked or read about where a quest's step is done, for a step no source places or places
wrongly, per client in ``pipeline/config/quest_places_<client>.toml``.

    [[place]]
    quest = 1861
    n = 1                    # the objective's number in the quest log; left out: the quest
    ref = "object:174794"    # optional: the creature or object that stands there
    map = 1429               # uiMapID
    x = 28.6                 # map percent
    y = 61.4
    src = "walked there"     # where the knowledge comes from, in words
    verified = ""            # date, build and how it was checked in game; empty: assumed

A row is the hand-made twin of a place learned from play (data.md "Step places from play"):
both name an objective by the number the game's own list gives it, the one thing a player sees
and no table knows. Several rows of one quest and number are several places of one step. The
rows go onto the quest records as `authored` (build-time only: no pack schema carries it), and
the steps' resolver (steps.py) puts them before every source.
"""

from __future__ import annotations

import re
import tomllib
from pathlib import Path

from bastians_build.model import World

KEYS = {"quest", "n", "ref", "map", "x", "y", "src", "verified", "note"}
REF = re.compile(r"^(npc|object):\d+$")


class QuestPlacesError(ValueError):
    pass


def _whole(value) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _number(value) -> bool:
    return isinstance(value, int | float) and not isinstance(value, bool)


def read_quest_places(path: Path) -> list[dict]:
    """The table's rows, validated, in the file's order."""
    raw = tomllib.loads(path.read_text(encoding="utf-8"))
    unknown = sorted(set(raw) - {"place"})
    if unknown:
        raise QuestPlacesError(f"{path.name}: unknown sections {', '.join(unknown)}")
    rows: list[dict] = []
    seen: set[tuple] = set()
    for i, row in enumerate(raw.get("place") or [], 1):
        where = f"{path.name} place {i}"
        extra = sorted(set(row) - KEYS)
        if extra:
            raise QuestPlacesError(f"{where}: unknown keys {', '.join(extra)}")
        if not _whole(row.get("quest")) or row["quest"] <= 0:
            raise QuestPlacesError(f"{where}: quest must be a quest id")
        n = row.get("n")
        if n is not None and (not _whole(n) or n < 1):
            raise QuestPlacesError(f"{where}: n is the objective's number in the quest log, from 1")
        ref = row.get("ref")
        if ref is not None and not (isinstance(ref, str) and REF.match(ref)):
            raise QuestPlacesError(f"{where}: ref must be 'npc:<id>' or 'object:<id>', got {ref!r}")
        if not _whole(row.get("map")) or row["map"] <= 0:
            raise QuestPlacesError(f"{where}: map must be a uiMapID")
        for axis in ("x", "y"):
            if not _number(row.get(axis)) or not 0 <= row[axis] <= 100:
                raise QuestPlacesError(f"{where}: {axis} must be map percent, 0 to 100")
        if not isinstance(row.get("src"), str) or not row["src"].strip():
            raise QuestPlacesError(f"{where}: src is required (where the knowledge comes from)")
        for key in ("verified", "note"):
            if key in row and not isinstance(row[key], str):
                raise QuestPlacesError(f"{where}: {key} must be text")
        key = (row["quest"], n, row["map"], row["x"], row["y"])
        if key in seen:
            raise QuestPlacesError(f"{where}: the same place of the same step twice")
        seen.add(key)
        rows.append(dict(row))
    return rows


def add_quest_places(world: World, rows: list[dict]) -> None:
    """Puts the rows onto their quests as `authored` = `{ { n, uiMapID, x, y, ref, verified } }`
    (map fractions; `verified` true when the row says how it was checked) and says in the
    build's notes how many there are and which name a quest the world does not have."""
    quests = world.records.get("quest", {})
    missing: list[int] = []
    placed: set[int] = set()
    checked = 0
    for row in rows:
        rec = quests.get(row["quest"])
        if rec is None:
            if row["quest"] not in missing:
                missing.append(row["quest"])
            continue
        verified = bool((row.get("verified") or "").strip())
        checked += verified
        placed.add(row["quest"])
        rec.setdefault("authored", []).append(
            [
                row.get("n"),
                row["map"],
                round(row["x"] / 100, 4),
                round(row["y"] / 100, 4),
                row.get("ref"),
                verified,
            ]
        )
    if rows:
        note = (
            f"authored quest places: {len(rows)} rows for {len(placed)} quests, "
            f"{checked} checked in game"
        )
        if missing:
            ids = ", ".join(str(q) for q in sorted(missing))
            note += f"; {len(missing)} quests are not in the world: {ids}"
        world.notes.append(note)
