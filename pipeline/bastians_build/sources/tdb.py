"""TrinityCore TDB (retail world database) reader: the retail counterpart of CMaNGOS (sources.md).

The dump (``TDB_full_world_<build>.sql``, from the release ``.7z``) is a MySQL dump in the same
shape as CMaNGOS', so the streaming parser of ``cmangos.read_lines`` reads it. Only Eastern Kingdoms
(map 0) and Kalimdor (map 1) are kept: the world graph's continents (ADR 0026).

Two client tables complete it (clientdump, client-extraction.md): ``FactionTemplate`` says whether
a creature is hostile to players and which side it stands with (group bits 1 player, 2 Alliance,
4 Horde, 8 monster); ``ContentTuning`` gives the level band a creature scales in (retail creatures
scale with the player inside it: ``MinLevelSquish`` .. ``MaxLevelSquish``; measured 26.10.2026,
build 12.1.5: Elwynn's creatures 1 to 30, Hogger among them).

Units: world yards (``position_x/y/z``), the TrinityCore frame, the same as CMaNGOS'. Unknown stays
``None``. Everything here is labelled ``tdb`` by the caller.
"""

from __future__ import annotations

import json
from collections.abc import Iterable
from dataclasses import dataclass, field
from pathlib import Path

from bastians_build.sources.cmangos import LootRow, read_lines

CONTINENT_MAPS = (0, 1)
OPEN_WORLD = 0  # creature_template_difficulty.DifficultyID of the open world

# npcflag bits -> service flags (data.md npc record): the retail family's bits. ~~the low bits
# match CMaNGOS'~~ They do not (05.11.2026): CMaNGOS classic-db carries the Classic 1.12 bits
# (``cmangos.NPC_FLAGS``; 4096 is an auctioneer there and a repairer here). Measured the same day
# on TDB 1210.26091 by the sub-titles per bit: 8192 = 616 flight masters, 65536 = 392 "Innkeeper"
# of 432, 131072 = 121 "Banker" of 129, 2097152 = 72 auctioneers, 4194304 = 255 "Stable Master".
NPC_FLAGS = {
    2: "questgiver",
    16: "trainer",
    128: "vendor",
    4096: "repair",
    8192: "flightmaster",
    65536: "innkeeper",
    131072: "banker",
    1048576: "battlemaster",
    2097152: "auctioneer",
    4194304: "stablemaster",
}
# creature_template.Classification -> rank (CreatureClassification: 1 elite, 2 rare elite,
# 3 boss, 4 rare; 5 trivial and 6 minus mob are no rank)
RANKS = {1: "elite", 2: "rareelite", 3: "boss", 4: "rare"}

GROUP_PLAYER, GROUP_ALLIANCE, GROUP_HORDE = 1, 2, 4

_LOOT = (
    "Entry",
    "ItemType",
    "Item",
    "Chance",
    "QuestRequired",
    "LootMode",
    "GroupId",
    "MinCount",
    "MaxCount",
)
WANTED: dict[str, tuple[str, ...]] = {
    "creature_template": ("entry", "name", "subname", "faction", "npcflag", "Classification"),
    "creature_template_difficulty": ("Entry", "DifficultyID", "ContentTuningID", "LootID"),
    "creature": ("guid", "id", "map", "position_x", "position_y", "position_z"),
    "gameobject_template": ("entry", "type", "name", "Data1"),
    "gameobject": ("guid", "id", "map", "position_x", "position_y", "position_z"),
    # the loot (28.10.2026: retail's drops and world drops; checked against TDB 1210.26091:
    # ItemType 0 an item, 1 a shared list, 2 a currency; LootMode bit 1 the normal loot)
    "creature_loot_template": _LOOT,
    "gameobject_loot_template": _LOOT,
    "reference_loot_template": _LOOT,
}
ITEM_TYPE_ITEM, ITEM_TYPE_REFERENCE = 0, 1
LOOT_MODE_DEFAULT = 1
OBJECT_CHEST = 3  # gameobject type whose Data1 is its loot list


@dataclass(frozen=True)
class Creature:
    id: int
    name: str | None
    subname: str | None
    services: tuple[str, ...]  # NPC_FLAGS names
    rank: str | None
    side: str | None  # "A" | "H" | None: the side whose players it stands with
    hostile: bool  # attacks players of both sides
    level: int | None  # the band it scales in (None: no content tuning)
    level_max: int | None


@dataclass(frozen=True)
class Spawn:
    entry: int
    map_id: int
    x: float
    y: float
    z: float | None


@dataclass
class Tdb:
    creatures: dict[int, Creature] = field(default_factory=dict)
    spawns: list[Spawn] = field(default_factory=list)  # creatures on CONTINENT_MAPS
    objects: dict[int, tuple[int, str | None]] = field(default_factory=dict)  # entry -> type, name
    object_spawns: list[Spawn] = field(default_factory=list)
    loot: list[LootRow] = field(default_factory=list)  # creatures', chests' and shared lists' rows
    name: str = ""  # the dump's file name, for the report


def table_rows(path: Path, table: str = "") -> list[dict]:
    data = json.loads(path.read_text(encoding="utf-8"))
    rows = data.get("rows")
    if isinstance(rows, dict):
        rows = list(rows.values())
    if not isinstance(rows, list):
        raise ValueError(f"{path}: rows missing ({table})")
    return rows


def faction_sides(rows: Iterable[dict]) -> dict[int, tuple[str | None, bool]]:
    """FactionTemplate rows -> { id: (side, hostile) }: side "A" or "H" for a template of one
    side's group, hostile when its enemies include the players (or both sides)."""
    out = {}
    for r in rows:
        group, enemy = int(r.get("FactionGroup") or 0), int(r.get("EnemyGroup") or 0)
        alliance, horde = bool(group & GROUP_ALLIANCE), bool(group & GROUP_HORDE)
        side = "A" if alliance and not horde else "H" if horde and not alliance else None
        hostile = bool(enemy & GROUP_PLAYER) or (
            bool(enemy & GROUP_ALLIANCE) and bool(enemy & GROUP_HORDE)
        )
        out[int(r["ID"])] = (side, hostile)
    return out


def tuning_levels(rows: Iterable[dict]) -> dict[int, tuple[int | None, int | None]]:
    """ContentTuning rows -> { id: (min, max) } from the squished levels; 0 is unknown."""
    out = {}
    for r in rows:
        lo, hi = int(r.get("MinLevelSquish") or 0), int(r.get("MaxLevelSquish") or 0)
        out[int(r["ID"])] = (lo or None, hi or None)
    return out


def _shares(rows: list[dict]) -> list[tuple[dict, float]]:
    """Percent per row of one loot list, as CMaNGOS': group 0 rows roll on their own; in a group one
    item drops and members without a chance share what the others leave."""
    out: list[tuple[dict, float]] = []
    groups: dict[int, list[dict]] = {}
    for r in rows:
        g = int(r.get("GroupId") or 0)
        if g == 0:
            out.append((r, float(r.get("Chance") or 0)))
        else:
            groups.setdefault(g, []).append(r)
    for members in groups.values():
        explicit = [float(r.get("Chance") or 0) for r in members]
        rest = max(0.0, 100.0 - sum(explicit))
        zeros = sum(1 for c in explicit if c == 0)
        for r, c in zip(members, explicit, strict=True):
            out.append((r, c if c > 0 else (rest / zeros if zeros else 0.0)))
    return out


def loot_rows(
    tables: dict[str, list[dict]],
    creature_lists: dict[int, list[int]],
    chest_lists: dict[int, list[int]],
) -> list[LootRow]:
    """The loot as CMaNGOS-shaped rows: a creature's list (``LootID``) and a chest's (``Data1``)
    become a row per creature or object that uses it; shared lists keep their own entry. Only the
    normal loot mode; currencies are left out."""
    out: list[LootRow] = []
    for table, kind, owners in (
        ("creature_loot_template", "creature", creature_lists),
        ("gameobject_loot_template", "object", chest_lists),
        ("reference_loot_template", "reference", None),
    ):
        by_entry: dict[int, list[dict]] = {}
        for r in tables.get(table, []):
            if int(r.get("LootMode") or LOOT_MODE_DEFAULT) & LOOT_MODE_DEFAULT == 0:
                continue
            if int(r.get("ItemType") or 0) not in (ITEM_TYPE_ITEM, ITEM_TYPE_REFERENCE):
                continue
            by_entry.setdefault(int(r["Entry"]), []).append(r)
        for entry in sorted(by_entry):
            users = [entry] if owners is None else owners.get(entry, [])
            for r, chance in _shares(by_entry[entry]):
                is_ref = int(r.get("ItemType") or 0) == ITEM_TYPE_REFERENCE
                for user in users:
                    out.append(
                        LootRow(
                            kind=kind,
                            entry=user,
                            item_id=None if is_ref else int(r["Item"]),
                            chance_pct=round(chance, 4),
                            quest_drop=bool(int(r.get("QuestRequired") or 0)),
                            group_id=int(r.get("GroupId") or 0) or None,
                            min_count=None if is_ref else int(r.get("MinCount") or 1),
                            max_count=None if is_ref else int(r.get("MaxCount") or 1),
                            reference_id=int(r["Item"]) if is_ref else None,
                        )
                    )
    return out


def build(
    tables: dict[str, list[dict]],
    sides: dict[int, tuple[str | None, bool]],
    levels: dict[int, tuple[int | None, int | None]],
) -> Tdb:
    """Typed rows from the parsed tables (pure: the tests feed small tables)."""
    tuning = {}
    creature_lists: dict[int, list[int]] = {}
    for r in tables.get("creature_template_difficulty", []):
        if r.get("DifficultyID") == OPEN_WORLD and r.get("ContentTuningID"):
            tuning[int(r["Entry"])] = int(r["ContentTuningID"])
        if r.get("DifficultyID") == OPEN_WORLD and r.get("LootID"):
            creature_lists.setdefault(int(r["LootID"]), []).append(int(r["Entry"]))
    t = Tdb()
    for r in tables.get("creature_template", []):
        entry = int(r["entry"])
        flags = int(r.get("npcflag") or 0)
        side, hostile = sides.get(int(r.get("faction") or 0), (None, False))
        lo, hi = levels.get(tuning.get(entry, 0), (None, None))
        t.creatures[entry] = Creature(
            id=entry,
            name=r.get("name") or None,
            subname=r.get("subname") or None,
            services=tuple(name for bit, name in NPC_FLAGS.items() if flags & bit),
            rank=RANKS.get(int(r.get("Classification") or 0)),
            side=side,
            hostile=hostile,
            level=lo,
            level_max=hi if hi and hi != lo else None,
        )
    for table, target in (("creature", t.spawns), ("gameobject", t.object_spawns)):
        for r in tables.get(table, []):
            if r.get("map") in CONTINENT_MAPS:
                z = r.get("position_z")
                target.append(
                    Spawn(
                        entry=int(r["id"]),
                        map_id=int(r["map"]),
                        x=float(r["position_x"]),
                        y=float(r["position_y"]),
                        z=None if z is None else float(z),
                    )
                )
    chest_lists: dict[int, list[int]] = {}
    for r in tables.get("gameobject_template", []):
        t.objects[int(r["entry"])] = (int(r.get("type") or 0), r.get("name") or None)
        if int(r.get("type") or 0) == OBJECT_CHEST and r.get("Data1"):
            chest_lists.setdefault(int(r["Data1"]), []).append(int(r["entry"]))
    t.loot = loot_rows(tables, creature_lists, chest_lists)
    return t


def read_tdb(sql: Path, faction_template: Path, content_tuning: Path) -> Tdb:
    """Stream the world dump (only the wanted tables) and join the two client tables."""
    with sql.open(encoding="utf-8", errors="replace") as fh:
        tables = read_lines(fh, WANTED)
    t = build(
        tables,
        faction_sides(table_rows(faction_template, "FactionTemplate")),
        tuning_levels(table_rows(content_tuning, "ContentTuning")),
    )
    t.name = sql.name
    return t
