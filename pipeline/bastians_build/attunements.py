"""Attunements (quests.md): hand-written lists per client (config/attunements_<client>.toml) read
into `attunement` records of the quests pack. Pure: TOML in, records plus notes out.

File format::

    [[attunement]]
    id = "onyxia-alliance"          # stable key, lowercase, dashes
    name = "Onyxia's Lair"
    faction = "Alliance"            # "Alliance" | "Horde" | "both"
    verified = false                # true once the list was checked in game on this client
    note = "..."                    # optional, shown to the player
    steps = [
      ["quest", 4182, "Dragonkin Menace"],   # kind, id, label
      ["rep", 529, "Argent Dawn", 6],         # faction id, name, standing (1 Hated .. 8 Exalted)
      ["item", 13704, "Skeleton Key"],       # item id, name
    ]

Quest step labels are checked against the quest names of the world: a mismatch is a note in the
build report (the list may be ahead of the data, or the ID may be wrong), never a build failure.
"""

from __future__ import annotations

import tomllib
from pathlib import Path

from bastians_build.model import World

FACTIONS = ("Alliance", "Horde", "both")
KINDS = {"quest": 3, "rep": 4, "item": 3}  # kind -> step length
STANDINGS = range(1, 9)


class AttunementError(ValueError):
    """The attunement file is malformed."""


def read_attunements(path: Path) -> list[dict]:
    """The attunement rows of one file, validated for shape; ids are unique."""
    with path.open("rb") as fh:
        data = tomllib.load(fh)
    rows = data.get("attunement", [])
    if not isinstance(rows, list):
        raise AttunementError(f"{path.name}: [[attunement]] must be an array of tables")
    seen: set[str] = set()
    out: list[dict] = []
    for i, row in enumerate(rows, 1):
        where = f"{path.name}: attunement {i}"
        for key in ("id", "name", "faction", "steps"):
            if key not in row:
                raise AttunementError(f"{where}: missing {key}")
        if row["id"] in seen:
            raise AttunementError(f"{where}: duplicate id {row['id']!r}")
        seen.add(row["id"])
        if row["faction"] not in FACTIONS:
            raise AttunementError(f"{where}: faction must be one of {FACTIONS}")
        steps = []
        for n, step in enumerate(row["steps"], 1):
            kind = step[0] if isinstance(step, list) and step else None
            if kind not in KINDS or len(step) != KINDS[kind]:
                raise AttunementError(f"{where}: step {n} must be [kind, id, label(, standing)]")
            if not isinstance(step[1], int):
                raise AttunementError(f"{where}: step {n} id must be an integer")
            if kind == "rep" and step[3] not in STANDINGS:
                raise AttunementError(f"{where}: step {n} standing must be 1..8")
            steps.append(list(step))
        out.append(
            {
                "id": row["id"],
                "name": row["name"],
                "faction": row["faction"],
                "verified": bool(row.get("verified", False)),
                "note": row.get("note"),
                "steps": steps,
                "src": "config",
            }
        )
    return out


def add_attunements(world: World, path: Path) -> list[str]:
    """Add the attunements of `path` to the world; returns the notes (mismatches, unknown ids)."""
    notes: list[str] = []
    quests = world.records.get("quest", {})
    for row in read_attunements(path):
        record = dict(row)
        record_id = record.pop("id")
        for step in record["steps"]:
            if step[0] != "quest":
                continue
            quest = quests.get(step[1])
            if quest is None:
                notes.append(
                    f"attunement {record_id}: quest {step[1]} ({step[2]}) is not in the data"
                )
            elif quest.get("name") and quest["name"] != step[2]:
                notes.append(
                    f"attunement {record_id}: quest {step[1]} is named {quest['name']!r} "
                    f"in the data, the list says {step[2]!r}"
                )
        world.add("attunement", record_id, record)
    world.notes.extend(notes)
    return notes
