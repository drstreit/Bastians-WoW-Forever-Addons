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
        *(f"ReqItemId{i}" for i in range(1, 5)),
        *(f"ReqItemCount{i}" for i in range(1, 5)),
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
    ),
    "creature": ("guid", "id", "map", "position_x", "position_y", "position_z"),
    "gameobject_template": ("entry", "type", "name"),
    "gameobject": ("guid", "id", "map", "position_x", "position_y", "position_z"),
    "npc_vendor": ("entry", "item", "maxcount", "incrtime"),
    "npc_trainer": _TRAINER_COLUMNS,
    "npc_trainer_template": _TRAINER_COLUMNS,
    "creature_loot_template": _LOOT_COLUMNS,
    "gameobject_loot_template": _LOOT_COLUMNS,
    "reference_loot_template": _LOOT_COLUMNS,
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
    ),
    "spell_template": (
        "Id",
        "SpellName",
        "Rank1",
        *(f"Effect{i}" for i in range(1, 4)),
        *(f"EffectTriggerSpell{i}" for i in range(1, 4)),
        *(f"EffectItemType{i}" for i in range(1, 4)),
    ),
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
        missing = [c for c in wanted[table] if c not in columns.get(table, [])]
        if missing:
            raise KeyError(f"{table}: no such column(s) {', '.join(missing)}")
        idx = [(c, columns[table].index(c)) for c in wanted[table]]
        for row in parse_values(line[m.end() :]):
            out[table].append({c: row[i] for c, i in idx})
    return out


def read_tables(
    path: Path, wanted: dict[str, tuple[str, ...]] | None = None
) -> dict[str, list[dict[str, Any]]]:
    """Stream the gzip dump; only the wanted columns of the wanted tables."""
    with gzip.open(path, "rt", encoding="utf-8", errors="replace") as fh:
        return read_lines(fh, wanted)


# ---------------------------------------------------------------- typed rows


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
            )
        )
    return out


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


def loot_rows(tables: dict[str, list[dict[str, Any]]]) -> list[LootRow]:
    """Loot rows of creatures, objects and reference lists; references are not expanded.

    A row with ``mincountOrRef < 0`` points at ``reference_loot_template`` entry ``-value``.
    """
    out: list[LootRow] = []
    for table, kind in LOOT_TABLES.items():
        by_entry: dict[int, list[dict[str, Any]]] = {}
        for r in tables.get(table, []):
            by_entry.setdefault(int(r["entry"]), []).append(r)
        for entry in sorted(by_entry):
            for r, chance in _group_chances(by_entry[entry]):
                minc = int(r["mincountOrRef"] or 0)
                is_ref = minc < 0
                out.append(
                    LootRow(
                        kind=kind,
                        entry=entry,
                        item_id=None if is_ref else int(r["item"]),
                        chance_pct=round(chance, 4),
                        quest_drop=float(r["ChanceOrQuestChance"] or 0) < 0,
                        group_id=_nz(r.get("groupid")),
                        min_count=None if is_ref else minc,
                        max_count=None if is_ref else _nz(r.get("maxcount")),
                        reference_id=-minc if is_ref else None,
                    )
                )
    return out


def spawn_rows(tables: dict[str, list[dict[str, Any]]]) -> list[SpawnRow]:
    out = []
    for table, kind in (("creature", "creature"), ("gameobject", "object")):
        for r in tables.get(table, []):
            out.append(
                SpawnRow(
                    kind=kind,
                    guid=r["guid"],
                    entry=r["id"],
                    map_id=r["map"],
                    position_x=float(r["position_x"]),
                    position_y=float(r["position_y"]),
                    position_z=None if r.get("position_z") is None else float(r["position_z"]),
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
        )
        for r in tables.get("item_template", [])
    ]
