"""CMaNGOS classic-db (GPL-3.0) reader: a streaming reader for the MySQL dump (ADR 0008).

The dump (``Full_DB/ClassicDB_1_12_1_*.sql.gz``) is read line by line from the gzip, never loaded
whole. Column names come from the ``CREATE TABLE`` blocks, rows from the one-line
``INSERT INTO `x` VALUES (...),(...);`` statements. Everything in here is **Classic 1.12** data;
the caller labels it ``classic`` (CLAUDE.md section 8).

Checked 19.10.2026 against ``ClassicDB_1_12_1_z2815.sql.gz``: every column in ``WANTED`` exists in
the real ``CREATE TABLE`` statements, with these corrections to the first draft of the task:

* ``quest_template.RewXP`` does not exist (1.12 has no XP column; the client derives XP from the
  quest level). Dropped.
* ``spell_template.Rank`` does not exist, the column is ``Rank1`` (``Rank2``.. are other locales).
* ``reference_loot_template`` was added to ``WANTED`` so that reference rows stay identifiable.

Units: money in integer copper; ``position_x/y/z`` are world yards (CMaNGOS frame, not map percent);
chances are percent. Unknown stays ``None`` (an unset ``0`` id such as ``PrevQuestId`` becomes
``None``; a ``NULL`` stays ``None``).
"""

from __future__ import annotations

import gzip
import re
from collections.abc import Iterable, Iterator
from dataclasses import dataclass
from pathlib import Path
from typing import Any

EFFECT_CREATE_ITEM = 24
EFFECT_LEARN_SPELL = 36

_LOOT_COLUMNS = ("entry", "item", "ChanceOrQuestChance", "groupid", "mincountOrRef", "maxcount")
_TRAINER_COLUMNS = ("entry", "spell", "spellcost", "reqskill", "reqskillvalue", "reqlevel")

WANTED: dict[str, tuple[str, ...]] = {
    "quest_template": (
        "entry",
        "Title",
        "Details",
        "Objectives",
        "OfferRewardText",
        "RequestItemsText",
        "QuestLevel",
        "MinLevel",
        "Type",
        "ZoneOrSort",
        "RequiredRaces",
        "RequiredClasses",
        "RequiredSkill",
        "RequiredSkillValue",
        "RewOrReqMoney",
        "RewMoneyMaxLevel",
        "SrcItemId",
        "SrcItemCount",
        *(f"ReqItemId{i}" for i in range(1, 5)),
        *(f"ReqItemCount{i}" for i in range(1, 5)),
        # the creatures and objects a quest counts (negative: an object), and the spell to cast on
        # one instead of killing or using it (data.md "A quest's `steps`", package QD3)
        *(f"ReqCreatureOrGOId{i}" for i in range(1, 5)),
        *(f"ReqCreatureOrGOCount{i}" for i in range(1, 5)),
        *(f"ReqSpellCast{i}" for i in range(1, 5)),
        "SpecialFlags",
        "PointMapId",
        "PointX",
        "PointY",
        *(f"RewItemId{i}" for i in range(1, 5)),
        *(f"RewItemCount{i}" for i in range(1, 5)),
        *(f"RewChoiceItemId{i}" for i in range(1, 7)),
        *(f"RewChoiceItemCount{i}" for i in range(1, 7)),
        *(f"RewRepFaction{i}" for i in range(1, 6)),
        *(f"RewRepValue{i}" for i in range(1, 6)),
        "RewSpell",
        "RewSpellCast",
        "PrevQuestId",
        "NextQuestId",
        "ExclusiveGroup",
        "NextQuestInChain",
    ),
    "creature_template": (
        "Entry",
        "Name",
        "SubName",
        "MinLevel",
        "MaxLevel",
        "NpcFlags",
        "TrainerTemplateId",
        "Rank",
        "Faction",  # a FactionTemplate id: the client's table says side and hostility
        "UnitFlags",  # not selectable: a helper creature (internal.py, data.md "Internal records")
        "PickpocketLootId",  # the list in pickpocketing_loot_template
        "SkinningLootId",  # the list in skinning_loot_template
    ),
    "creature": ("guid", "id", "map", "position_x", "position_y", "position_z", "spawndist"),
    # data0: a spell focus object's (type 8) focus id; data1: a chest's (3) or a fishing hole's
    # (25) list in gameobject_loot_template
    "gameobject_template": ("entry", "type", "name", "data0", "data1"),
    "gameobject": ("guid", "id", "map", "position_x", "position_y", "position_z"),
    # a spawn with id 0 takes one of these entries at random (06.11.2026)
    "creature_spawn_entry": ("guid", "entry"),
    "gameobject_spawn_entry": ("guid", "entry"),
    "npc_vendor": ("entry", "item", "maxcount", "incrtime"),
    "npc_trainer": _TRAINER_COLUMNS,
    "npc_trainer_template": _TRAINER_COLUMNS,
    "creature_loot_template": _LOOT_COLUMNS,
    "gameobject_loot_template": _LOOT_COLUMNS,
    "reference_loot_template": _LOOT_COLUMNS,
    # what an item disenchants into: item_template.DisenchantID names the list
    "disenchant_loot_template": _LOOT_COLUMNS,
    "item_template": (
        "entry",
        "name",
        "Quality",
        "ItemLevel",
        "RequiredLevel",
        "class",
        "subclass",
        "BuyPrice",
        "SellPrice",
        "stackable",
        "DisenchantID",
        *(f"spellid_{i}" for i in range(1, 6)),
        *(f"spelltrigger_{i}" for i in range(1, 6)),
    ),
    "spell_template": (
        "Id",
        "SpellName",
        "Rank1",
        *(f"Effect{i}" for i in range(1, 4)),
        *(f"EffectTriggerSpell{i}" for i in range(1, 4)),
        *(f"EffectItemType{i}" for i in range(1, 4)),
        "RequiresSpellFocus",
    ),
    # where an item comes from besides a kill and a chest (plan-quest-links.md G7)
    "item_loot_template": _LOOT_COLUMNS,
    "skinning_loot_template": _LOOT_COLUMNS,
    "pickpocketing_loot_template": _LOOT_COLUMNS,
    "fishing_loot_template": _LOOT_COLUMNS,
    # the creature or object a spell is cast on (type 0 an object, 1 a creature, 2 a dead one)
    "spell_script_target": ("entry", "type", "targetEntry"),
    # the quest log's map points of a later client, carried back to 1.12 quests (G5)
    "quest_poi": ("questId", "poiId", "objIndex", "mapId"),
    "quest_poi_points": ("questId", "poiId", "x", "y"),
    "areatrigger_involvedrelation": ("id", "quest"),
}

# creature_template.NpcFlags bits -> service flags (data.md npc record). These are the **Classic
# 1.12** bits (mangos-classic ``enum NPCFlags``), not the retail family's that TrinityCore's dump
# carries (``tdb.NPC_FLAGS``: vendor 128, repair 4096, flight master 8192, auctioneer 2097152 ...).
# Measured 05.11.2026 on ClassicDB_1_12_1_z2815 by the sub-titles per bit: 8 = 61 flight masters
# ("Gryphon Master", "Wind Rider Master" ...), 128 = 45 "Innkeeper" of 54, 256 = 26 "Banker",
# 2048 = the battlemasters, 4096 = 33 rows, 32 of them named "Auctioneer ...", 8192 = 46 "Stable
# Master", 16384 = 299 smiths and armour merchants. Until that day the build read them with the
# retail table: auctioneers showed as repair, stable masters as flight masters, and no vendor (4),
# flight master, innkeeper or banker was found. The order is the retail table's, so a record's
# flags list reads the same on both clients. Bits without a service flag: 1 gossip, 32 spirit
# healer, 64 spirit guide, 512 petitioner, 1024 tabard designer.
NPC_FLAGS = {
    2: "questgiver",
    16: "trainer",
    4: "vendor",
    16384: "repair",
    8: "flightmaster",
    128: "innkeeper",
    256: "banker",
    2048: "battlemaster",
    4096: "auctioneer",
    8192: "stablemaster",
}

_CREATE = re.compile(r"^CREATE TABLE `(\w+)`")
_COLUMN = re.compile(r"^\s+`(\w+)`")
_INSERT = re.compile(r"^INSERT INTO `(\w+)` VALUES ")
_TOKEN = re.compile(
    r"'((?:[^'\\]|\\.|'')*)'|(NULL)|(-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)|(\()|(\))",
    re.S,
)
_UNESCAPE = re.compile(r"\\(.)|''", re.S)
_ESCAPES = {"n": "\n", "r": "\r", "t": "\t", "0": "\0", "Z": "\x1a"}


def unescape(s: str) -> str:
    """MySQL string escapes: backslash sequences and the doubled quote."""
    return _UNESCAPE.sub(
        lambda m: "'" if m.group(0) == "''" else _ESCAPES.get(m.group(1), m.group(1)), s
    )


def parse_values(text: str) -> Iterator[list[Any]]:
    """The tuples of one ``INSERT ... VALUES (...),(...);`` tail; values are str, int, float, None.

    A tokenizer, not a split: strings may contain commas, parentheses and escaped quotes.
    """
    row: list[Any] | None = None
    for m in _TOKEN.finditer(text):
        s, null, num, open_, close = m.groups()
        if open_:
            row = []
        elif close:
            if row is not None:
                yield row
            row = None
        elif row is None:
            continue
        elif s is not None:
            row.append(unescape(s))
        elif null:
            row.append(None)
        else:
            row.append(float(num) if "." in num or "e" in num.lower() else int(num))


# Columns a dump may lack (an older or a cut-down dump): their value is None then.
OPTIONAL: dict[str, tuple[str, ...]] = {
    "creature_template": ("UnitFlags", "PickpocketLootId", "SkinningLootId"),
    "gameobject_template": ("data0", "data1"),
    "item_template": (
        *(f"spellid_{i}" for i in range(1, 6)),
        *(f"spelltrigger_{i}" for i in range(1, 6)),
    ),
    "spell_template": ("RequiresSpellFocus",),
    "quest_template": (
        "SrcItemCount",
        *(f"ReqCreatureOrGOId{i}" for i in range(1, 5)),
        *(f"ReqCreatureOrGOCount{i}" for i in range(1, 5)),
        *(f"ReqSpellCast{i}" for i in range(1, 5)),
        "SpecialFlags",
        "PointMapId",
        "PointX",
        "PointY",
    ),
}


def read_lines(
    lines: Iterable[str], wanted: dict[str, tuple[str, ...]] | None = None
) -> dict[str, list[dict[str, Any]]]:
    """Pure core of ``read_tables``: any iterable of dump lines."""
    wanted = WANTED if wanted is None else wanted
    out: dict[str, list[dict[str, Any]]] = {t: [] for t in wanted}
    columns: dict[str, list[str]] = {}
    current: str | None = None
    for line in lines:
        if m := _CREATE.match(line):
            current = m.group(1)
            columns[current] = []
            continue
        if current and (m := _COLUMN.match(line)):
            columns[current].append(m.group(1))
            continue
        if line.startswith(")"):
            current = None
            continue
        m = _INSERT.match(line)
        if not m or m.group(1) not in wanted:
            continue
        table = m.group(1)
        have = columns.get(table, [])
        optional = OPTIONAL.get(table, ())
        missing = [c for c in wanted[table] if c not in have and c not in optional]
        if missing:
            raise KeyError(f"{table}: no such column(s) {', '.join(missing)}")
        idx = [(c, have.index(c) if c in have else None) for c in wanted[table]]
        for row in parse_values(line[m.end() :]):
            out[table].append({c: None if i is None else row[i] for c, i in idx})
    return out


def read_tables(
    path: Path, wanted: dict[str, tuple[str, ...]] | None = None
) -> dict[str, list[dict[str, Any]]]:
    """Stream the gzip dump; only the wanted columns of the wanted tables."""
    with gzip.open(path, "rt", encoding="utf-8", errors="replace") as fh:
        return read_lines(fh, wanted)


def npc_services(npc_flags: int | None) -> list[str]:
    """The service flags of a ``creature_template.NpcFlags`` value, in ``NPC_FLAGS`` order; a
    missing value and bits without a service flag give none."""
    flags = int(npc_flags or 0)
    return [name for bit, name in NPC_FLAGS.items() if flags & bit]


# ---------------------------------------------------------------- typed rows


@dataclass(frozen=True)
class QuestGoal:
    """One creature or object a quest counts (a ``ReqCreatureOrGOId`` column)."""

    kind: str  # "npc" | "object"
    entry: int
    count: int | None  # None when the column has none (unknown is not 1)
    spell: int | None  # ReqSpellCast: the spell to cast on it instead of killing or using it
    column: int = 1  # which of the four columns, from 1: the Classic points name it (minus one)


@dataclass(frozen=True)
class QuestRow:
    id: int
    title: str | None
    details: str | None
    objectives: str | None
    offer_reward_text: str | None
    request_items_text: str | None
    quest_level: int | None  # -1 = scales with the player in CMaNGOS, kept as is
    min_level: int | None
    type: int | None
    zone_or_sort: int | None  # positive: AreaTable id, negative: QuestSort id
    required_races: int | None  # bit mask, None = any
    required_classes: int | None  # bit mask, None = any
    required_skill: int | None
    required_skill_value: int | None
    reward_money: int  # copper; the quest gives money (RewOrReqMoney > 0)
    required_money: int  # copper; the quest asks for money (RewOrReqMoney < 0)
    reward_money_max_level: int  # copper instead of XP at max level
    src_item_id: int | None
    required_items: tuple[tuple[int, int], ...]
    reward_items: tuple[tuple[int, int], ...]
    choice_items: tuple[tuple[int, int], ...]
    prev_quest_id: int | None  # negative = that quest must be active, not finished (CMaNGOS)
    next_quest_id: int | None
    exclusive_group: int | None
    next_quest_in_chain: int | None
    reward_rep: tuple[
        tuple[int, int], ...
    ] = ()  # (faction id, reputation) gained, value may be < 0
    reward_spell: int | None = None  # the spell the quest teaches or casts at hand-in
    src_item_count: int | None = None  # how many of `src_item_id` the giver hands over
    goals: tuple[QuestGoal, ...] = ()  # the creature and object columns, in their order
    # PointMapId, PointX, PointY: a place the quest names itself (CMaNGOS map, world yards)
    point: tuple[int, float, float] | None = None
    exploration: bool = False  # SpecialFlags bit 2: finished by going somewhere or by an event


@dataclass(frozen=True)
class TrainerService:
    trainer_id: int
    trainer_name: str | None
    trainer_subname: str | None
    spell_id: int  # the trainer entry
    learned_spell_id: int  # what it teaches (spell_id itself when direct)
    name: str | None
    rank: str | None
    cost: int  # copper
    req_skill: int | None
    req_skill_value: int | None
    req_level: int | None
    item_id: int | None  # item a recipe creates


@dataclass(frozen=True)
class VendorRow:
    npc_id: int
    item_id: int
    max_count: int | None  # None = unlimited
    restock_seconds: int | None


@dataclass(frozen=True)
class LootRow:
    kind: str  # "creature" | "object" | "reference"
    entry: int
    item_id: int | None  # None for a reference row
    chance_pct: float  # percent; zero-chance members of a group share the rest of the group
    quest_drop: bool  # the dump stores quest drops as negative chances
    group_id: int | None
    min_count: int | None
    max_count: int | None
    reference_id: int | None  # set when the row points at reference_loot_template


@dataclass(frozen=True)
class SpawnRow:
    kind: str  # "creature" | "object"
    guid: int
    entry: int  # creature_template.Entry or gameobject_template.entry
    map_id: int  # CMaNGOS map (0 Eastern Kingdoms, 1 Kalimdor, ...)
    position_x: float  # world yards
    position_y: float
    position_z: float | None
    spawndist: float | None = None  # yards the creature roams around its spawn (W5: area runs)


@dataclass(frozen=True)
class ItemRow:
    id: int
    name: str | None
    quality: int | None
    item_level: int | None
    required_level: int | None
    item_class: int | None
    item_subclass: int | None
    buy_price: int | None  # copper, for the vendor stack (BuyCount)
    sell_price: int | None  # copper, per item
    stackable: int | None
    disenchant_id: int | None = None  # the disenchant_loot_template entry, None: not disenchantable


def _text(value: Any) -> str | None:
    """Dump text with whitespace folded; the server placeholders ($B $N $C $R $G..;) stay."""
    if not isinstance(value, str):
        return None
    return " ".join(value.split()) or None


def _nz(value: Any) -> int | None:
    """0 and NULL both mean "not set" for id-like columns."""
    return int(value) if value else None


def _pairs(row: dict[str, Any], ids: str, counts: str, n: int) -> tuple[tuple[int, int], ...]:
    return tuple(
        (int(row[f"{ids}{i}"]), int(row.get(f"{counts}{i}") or 0))
        for i in range(1, n + 1)
        if row.get(f"{ids}{i}")
    )


def quest_rows(tables: dict[str, list[dict[str, Any]]]) -> list[QuestRow]:
    out = []
    for r in tables.get("quest_template", []):
        money = r.get("RewOrReqMoney") or 0
        out.append(
            QuestRow(
                id=r["entry"],
                title=_text(r.get("Title")),
                details=_text(r.get("Details")),
                objectives=_text(r.get("Objectives")),
                offer_reward_text=_text(r.get("OfferRewardText")),
                request_items_text=_text(r.get("RequestItemsText")),
                quest_level=r.get("QuestLevel"),
                min_level=r.get("MinLevel"),
                type=r.get("Type"),
                zone_or_sort=r.get("ZoneOrSort"),
                required_races=_nz(r.get("RequiredRaces")),
                required_classes=_nz(r.get("RequiredClasses")),
                required_skill=_nz(r.get("RequiredSkill")),
                required_skill_value=_nz(r.get("RequiredSkillValue")),
                reward_money=max(money, 0),
                required_money=max(-money, 0),
                reward_money_max_level=r.get("RewMoneyMaxLevel") or 0,
                src_item_id=_nz(r.get("SrcItemId")),
                required_items=_pairs(r, "ReqItemId", "ReqItemCount", 4),
                reward_items=_pairs(r, "RewItemId", "RewItemCount", 4),
                choice_items=_pairs(r, "RewChoiceItemId", "RewChoiceItemCount", 6),
                reward_rep=tuple(
                    (int(r[f"RewRepFaction{i}"]), int(r.get(f"RewRepValue{i}") or 0))
                    for i in range(1, 6)
                    if r.get(f"RewRepFaction{i}") and r.get(f"RewRepValue{i}")
                ),
                reward_spell=_nz(r.get("RewSpell")) or _nz(r.get("RewSpellCast")),
                prev_quest_id=_nz(r.get("PrevQuestId")),
                next_quest_id=_nz(r.get("NextQuestId")),
                exclusive_group=_nz(r.get("ExclusiveGroup")),
                next_quest_in_chain=_nz(r.get("NextQuestInChain")),
                src_item_count=_nz(r.get("SrcItemCount")),
                goals=_goals(r),
                point=(int(r.get("PointMapId") or 0), float(r["PointX"]), float(r["PointY"]))
                if r.get("PointX") or r.get("PointY")
                else None,
                exploration=bool(int(r.get("SpecialFlags") or 0) & 2),
            )
        )
    return out


def _goals(row: dict[str, Any]) -> tuple[QuestGoal, ...]:
    out = []
    for i in range(1, 5):
        entry = int(row.get(f"ReqCreatureOrGOId{i}") or 0)
        if entry:
            out.append(
                QuestGoal(
                    kind="npc" if entry > 0 else "object",
                    entry=abs(entry),
                    count=_nz(row.get(f"ReqCreatureOrGOCount{i}")),
                    spell=_nz(row.get(f"ReqSpellCast{i}")),
                    column=i,
                )
            )
    return tuple(out)


def _spell_effect(spell: dict[str, Any], effect: int, field: str) -> int | None:
    for k in (1, 2, 3):
        if spell.get(f"Effect{k}") == effect and spell.get(f"{field}{k}"):
            return int(spell[f"{field}{k}"])
    return None


def trainer_services(tables: dict[str, list[dict[str, Any]]]) -> list[TrainerService]:
    """Every service of every trainer: direct ``npc_trainer`` rows plus the shared template list."""
    spells = {s["Id"]: s for s in tables.get("spell_template", [])}
    direct: dict[int, list[dict[str, Any]]] = {}
    for r in tables.get("npc_trainer", []):
        direct.setdefault(r["entry"], []).append(r)
    templates: dict[int, list[dict[str, Any]]] = {}
    for r in tables.get("npc_trainer_template", []):
        templates.setdefault(r["entry"], []).append(r)
    out = []
    for npc in tables.get("creature_template", []):
        offered = direct.get(npc["Entry"], []) + templates.get(
            npc.get("TrainerTemplateId") or -1, []
        )
        for r in offered:
            spell = spells.get(r["spell"], {})
            learned_id = (
                _spell_effect(spell, EFFECT_LEARN_SPELL, "EffectTriggerSpell") or r["spell"]
            )
            learned = spells.get(learned_id, spell)
            out.append(
                TrainerService(
                    trainer_id=npc["Entry"],
                    trainer_name=npc.get("Name") or None,
                    trainer_subname=npc.get("SubName") or None,
                    spell_id=r["spell"],
                    learned_spell_id=learned_id,
                    name=learned.get("SpellName") or spell.get("SpellName") or None,
                    rank=learned.get("Rank1") or spell.get("Rank1") or None,
                    cost=int(r["spellcost"] or 0),
                    req_skill=_nz(r.get("reqskill")),
                    req_skill_value=_nz(r.get("reqskillvalue")),
                    req_level=_nz(r.get("reqlevel")),
                    item_id=_spell_effect(learned, EFFECT_CREATE_ITEM, "EffectItemType"),
                )
            )
    return out


def vendor_rows(tables: dict[str, list[dict[str, Any]]]) -> list[VendorRow]:
    return [
        VendorRow(
            npc_id=r["entry"],
            item_id=r["item"],
            max_count=_nz(r.get("maxcount")),
            restock_seconds=_nz(r.get("incrtime")),
        )
        for r in tables.get("npc_vendor", [])
    ]


LOOT_TABLES = {
    "creature_loot_template": "creature",
    "gameobject_loot_template": "object",
    "reference_loot_template": "reference",
}


def _group_chances(rows: list[dict[str, Any]]) -> list[tuple[dict[str, Any], float]]:
    """Percent per row of one loot list. Group 0 rows roll independently; in a group one item
    drops, and members without an explicit chance share what the explicit ones leave."""
    out: list[tuple[dict[str, Any], float]] = []
    groups: dict[int, list[dict[str, Any]]] = {}
    for r in rows:
        g = int(r["groupid"] or 0)
        if g == 0:
            out.append((r, abs(float(r["ChanceOrQuestChance"] or 0))))
        else:
            groups.setdefault(g, []).append(r)
    for members in groups.values():
        explicit = [abs(float(r["ChanceOrQuestChance"] or 0)) for r in members]
        rest = max(0.0, 100.0 - sum(explicit))
        zeros = sum(1 for c in explicit if c == 0)
        for r, c in zip(members, explicit, strict=True):
            out.append((r, c if c > 0 else (rest / zeros if zeros else 0.0)))
    return out


GO_CHEST, GO_SPELL_FOCUS, GO_FISHING_HOLE = 3, 8, 25


def object_loot_owners(tables: dict[str, list[dict[str, Any]]]) -> dict[int, list[int]] | None:
    """``gameobject_loot_template`` is keyed by the list a chest or a fishing hole names in
    ``data1``, not by the object: list -> the objects that open it, ascending. None when the dump
    has no ``data1`` (a cut-down dump): the list id then stands for the object, as before.

    Measured 11.11.2026 on ClassicDB_1_12_1_z2815: all 573 lists are some chest's ``data1``, 90 of
    them are also an object's entry and only 2 of those the same object, so until that day an
    item from a chest named an object that does not hold it, or none."""
    owners: dict[int, list[int]] = {}
    known = False
    for r in tables.get("gameobject_template", []):
        known = known or r.get("data1") is not None
        if r.get("type") in (GO_CHEST, GO_FISHING_HOLE) and r.get("data1"):
            owners.setdefault(int(r["data1"]), []).append(int(r["entry"]))
    return {k: sorted(v) for k, v in owners.items()} if known else None


def loot_rows(tables: dict[str, list[dict[str, Any]]]) -> list[LootRow]:
    """Loot rows of creatures, objects and reference lists; references are not expanded.

    A row with ``mincountOrRef < 0`` points at ``reference_loot_template`` entry ``-value``. An
    object's rows are those of the list it names (``object_loot_owners``), once per object.
    """
    out: list[LootRow] = []
    owners = object_loot_owners(tables)
    for table, kind in LOOT_TABLES.items():
        by_entry: dict[int, list[dict[str, Any]]] = {}
        for r in tables.get(table, []):
            by_entry.setdefault(int(r["entry"]), []).append(r)
        rows: list[LootRow] = []
        for entry in sorted(by_entry):
            entries = [entry] if kind != "object" or owners is None else owners.get(entry, [])
            for r, chance in _group_chances(by_entry[entry]):
                minc = int(r["mincountOrRef"] or 0)
                is_ref = minc < 0
                for owner in entries:
                    rows.append(
                        LootRow(
                            kind=kind,
                            entry=owner,
                            item_id=None if is_ref else int(r["item"]),
                            chance_pct=round(chance, 4),
                            quest_drop=float(r["ChanceOrQuestChance"] or 0) < 0,
                            group_id=_nz(r.get("groupid")),
                            min_count=None if is_ref else minc,
                            max_count=None if is_ref else _nz(r.get("maxcount")),
                            reference_id=-minc if is_ref else None,
                        )
                    )
        rows.sort(key=lambda row: row.entry)  # stable: a list's rows keep their order
        out += rows
    return out


def spawn_rows(tables: dict[str, list[dict[str, Any]]]) -> list[SpawnRow]:
    out = []
    for table, kind in (("creature", "creature"), ("gameobject", "object")):
        entries: dict[int, list[int]] = {}
        for r in tables.get(f"{table}_spawn_entry", []):
            entries.setdefault(r["guid"], []).append(r["entry"])
        for r in tables.get(table, []):
            for entry in entries.get(r["guid"], ()) if not r["id"] else (r["id"],):
                out.append(
                    SpawnRow(
                        kind=kind,
                        guid=r["guid"],
                        entry=entry,
                        map_id=r["map"],
                        position_x=float(r["position_x"]),
                        position_y=float(r["position_y"]),
                        position_z=None if r.get("position_z") is None else float(r["position_z"]),
                        spawndist=None
                        if r.get("spawndist") in (None, "")
                        else float(r["spawndist"]),
                    )
                )
    return out


def item_rows(tables: dict[str, list[dict[str, Any]]]) -> list[ItemRow]:
    return [
        ItemRow(
            id=r["entry"],
            name=r.get("name") or None,
            quality=r.get("Quality"),
            item_level=r.get("ItemLevel"),
            required_level=r.get("RequiredLevel"),
            item_class=r.get("class"),
            item_subclass=r.get("subclass"),
            buy_price=r.get("BuyPrice"),
            sell_price=r.get("SellPrice"),
            stackable=r.get("stackable"),
            disenchant_id=_nz(r.get("DisenchantID")),
        )
        for r in tables.get("item_template", [])
    ]


def disenchant_lists(tables: dict[str, list[dict[str, Any]]]) -> dict[int, list[list[Any]]]:
    """Each disenchant list (``disenchant_loot_template`` entry): ``[item, percent, min, max]``
    rows, the likeliest first. In a group one material comes, and members without a chance share
    what the others leave (uncommon armour of list 1: Strange Dust 80 %, Lesser Magic Essence the
    other 20 %)."""
    by_entry: dict[int, list[dict[str, Any]]] = {}
    for r in tables.get("disenchant_loot_template", []):
        by_entry.setdefault(int(r["entry"]), []).append(r)
    out: dict[int, list[list[Any]]] = {}
    for entry in sorted(by_entry):
        rows = []
        for r, chance in _group_chances(by_entry[entry]):
            minc = int(r["mincountOrRef"] or 0)
            if minc < 0:
                continue  # a reference: none in the classic lists
            rows.append([int(r["item"]), round(chance, 4), minc or None, _nz(r.get("maxcount"))])
        rows.sort(key=lambda x: (-x[1], x[0]))
        out[entry] = rows
    return out


# ---------------------------------------------------------------- links (package QD3)


@dataclass(frozen=True)
class Made:
    """Using an item needs a place, and may make another item (``item_template.spellid`` -> the
    spell's focus, its script targets and its effect 24)."""

    item_id: int  # the item that is used
    spell_id: int
    focus: int | None  # RequiresSpellFocus: the kind of object it is used at
    targets: tuple[tuple[str, int], ...]  # spell_script_target: ("npc" | "object", entry)


@dataclass
class Links:
    """What the dump says about where things come from and where quests are done, beyond kills,
    chests and vendors (plan-quest-links.md G3 to G7). All of it is Classic knowledge."""

    made: dict[int, list[Made]]  # the product -> the ways it is made
    uses: dict[int, list[Made]]  # an item -> where its use spells are cast, product or not
    spells: dict[int, tuple[int, ...]]  # an item -> its use spells
    focus_objects: dict[int, list[int]]  # a spell focus id -> the objects that are one
    held: dict[int, list[tuple[int, float]]]  # item -> (the item that holds it, percent)
    skinned: dict[int, list[tuple[int, float]]]  # item -> (creature, percent)
    picked: dict[int, list[tuple[int, float]]]  # item -> (creature, percent)
    fished: dict[int, list[tuple[int, float]]]  # item -> (AreaTable id, percent)
    # quest -> (objective index, CMaNGOS map, the area's corner points in world yards). Index
    # -1 is the hand-in, 0..3 the creature and object columns, 4..7 the item columns, 16 an
    # event or a place to reach (measured 11.11.2026: 9,947 / 3,596 / 3,924 / 455 of 18,486)
    points: dict[int, list[tuple[int, int, tuple[tuple[float, float], ...]]]]
    triggers: dict[int, list[int]]  # quest -> the area triggers that finish it


USE_TRIGGERS = (0, 5)  # item_template.spelltrigger: on use, on use without a delay


def _lists(
    tables: dict[str, list[dict[str, Any]]], table: str, owners: dict[int, list[int]] | None
) -> dict[int, list[tuple[int, float]]]:
    """item -> (who has it, percent) from one loot table, the likeliest first. Only the rows a
    list names itself: a shared list (a lockbox rolls the world's green items) is no source."""
    out: dict[int, dict[int, float]] = {}
    by_entry: dict[int, list[dict[str, Any]]] = {}
    for r in tables.get(table, []):
        by_entry.setdefault(int(r["entry"]), []).append(r)
    for entry in sorted(by_entry):
        for r, chance in _group_chances(by_entry[entry]):
            if int(r["mincountOrRef"] or 0) < 0:
                continue
            for owner in [entry] if owners is None else owners.get(entry, []):
                found = out.setdefault(int(r["item"]), {})
                found[owner] = max(found.get(owner, 0.0), round(chance, 2))
    return {
        item: sorted(found.items(), key=lambda pair: (-pair[1], pair[0]))
        for item, found in sorted(out.items())
    }


def links(tables: dict[str, list[dict[str, Any]]]) -> Links:
    spells = {int(s["Id"]): s for s in tables.get("spell_template", [])}
    targets: dict[int, list[tuple[str, int]]] = {}
    for r in tables.get("spell_script_target", []):
        kind = "object" if int(r["type"] or 0) == 0 else "npc"
        targets.setdefault(int(r["entry"]), []).append((kind, int(r["targetEntry"])))
    made: dict[int, list[Made]] = {}
    uses: dict[int, list[Made]] = {}
    item_spells: dict[int, list[int]] = {}
    for r in tables.get("item_template", []):
        for i in range(1, 6):
            spell_id = _nz(r.get(f"spellid_{i}"))
            if not spell_id or int(r.get(f"spelltrigger_{i}") or 0) not in USE_TRIGGERS:
                continue
            item_spells.setdefault(int(r["entry"]), []).append(spell_id)
            spell = spells.get(spell_id)
            if spell is None:
                continue
            way = Made(
                item_id=int(r["entry"]),
                spell_id=spell_id,
                focus=_nz(spell.get("RequiresSpellFocus")),
                targets=tuple(sorted(set(targets.get(spell_id, [])))),
            )
            if way.focus or way.targets:
                uses.setdefault(way.item_id, []).append(way)
            for k in (1, 2, 3):
                product = _nz(spell.get(f"EffectItemType{k}"))
                creates = spell.get(f"Effect{k}") == EFFECT_CREATE_ITEM and product
                if creates and product != way.item_id and way not in made.get(product, ()):
                    made.setdefault(product, []).append(way)
    focus_objects: dict[int, list[int]] = {}
    skin: dict[int, list[int]] = {}
    pick: dict[int, list[int]] = {}
    for r in tables.get("gameobject_template", []):
        if r.get("type") == GO_SPELL_FOCUS and r.get("data0"):
            focus_objects.setdefault(int(r["data0"]), []).append(int(r["entry"]))
    for r in tables.get("creature_template", []):
        if r.get("SkinningLootId"):
            skin.setdefault(int(r["SkinningLootId"]), []).append(int(r["Entry"]))
        if r.get("PickpocketLootId"):
            pick.setdefault(int(r["PickpocketLootId"]), []).append(int(r["Entry"]))
    areas: dict[tuple[int, int], list[tuple[float, float]]] = {}
    for r in tables.get("quest_poi_points", []):
        areas.setdefault((int(r["questId"]), int(r["poiId"])), []).append(
            (float(r["x"]), float(r["y"]))
        )
    points: dict[int, list[tuple[int, int, tuple[tuple[float, float], ...]]]] = {}
    for r in tables.get("quest_poi", []):
        corners = areas.get((int(r["questId"]), int(r["poiId"])))
        if corners:
            points.setdefault(int(r["questId"]), []).append(
                (int(r["objIndex"]), int(r["mapId"]), tuple(corners))
            )
    triggers: dict[int, list[int]] = {}
    for r in tables.get("areatrigger_involvedrelation", []):
        triggers.setdefault(int(r["quest"]), []).append(int(r["id"]))
    return Links(
        made={k: v for k, v in sorted(made.items()) if v},
        uses=dict(sorted(uses.items())),
        spells={k: tuple(v) for k, v in sorted(item_spells.items())},
        focus_objects={k: sorted(v) for k, v in sorted(focus_objects.items())},
        held=_lists(tables, "item_loot_template", None),
        skinned=_lists(tables, "skinning_loot_template", skin),
        picked=_lists(tables, "pickpocketing_loot_template", pick),
        fished=_lists(tables, "fishing_loot_template", None),
        points=dict(sorted(points.items())),
        triggers={k: sorted(v) for k, v in sorted(triggers.items())},
    )
