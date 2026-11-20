"""The client's data tables (ADR 0035, "client first"): items, recipes, quest chains, quest
objective areas and the names in every installed text language, from the clientdump JSON files that
``tools/client_tables.py`` writes into the dumps folder: ``<client>_<Table>.json`` and
``<client>_<Table>.<locale>.json``. Everything here is what the client itself holds, so it matches
the build; what the server holds (spawns, loot, vendors, quests) comes from elsewhere.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

CREATE_ITEM = 24  # SpellEffect.Effect: the spell makes an item (a recipe's product)
APPLY_AURA = 6  # SpellEffect.Effect: the spell puts an aura on its target
SUMMON = 28  # SpellEffect.Effect: the spell summons a creature (a companion)
MOUNTED = 78  # SpellEffect.EffectAura: the caster rides; the mount's creature in EffectMiscValue


@dataclass(frozen=True)
class ClientItem:
    id: int
    name: str | None
    quality: int | None
    level: int | None
    required_level: int | None
    item_class: int | None
    item_subclass: int | None
    sell: int | None
    buy: int | None
    stack: int | None
    starts_quest: int | None
    # how many a merchant sells for `buy` (VendorStackCount): the price is for that stack
    vendor_stack: int | None = None


@dataclass(frozen=True)
class ClientRecipe:
    spell: int
    name: str | None
    skill_line: int
    learned_at: (
        int | None
    )  # MinSkillLineRank when above 1 (the trainers' own levels live server-side)
    item: int | None
    count: int | None
    reagents: tuple[tuple[int, int], ...]


@dataclass(frozen=True)
class QuestArea:
    quest: int
    ui_map: int
    objective: int  # 0-based objective index; -1 the turn-in area
    points: tuple[tuple[float, float], ...]  # world yards (x, y) on the area's continent


@dataclass
class ClientTables:
    items: dict[int, ClientItem] = field(default_factory=dict)
    recipes: list[ClientRecipe] = field(default_factory=list)
    quest_lines: list[list[int]] = field(default_factory=list)  # each line's quests in order
    quest_areas: list[QuestArea] = field(default_factory=list)
    sources: list[str] = field(default_factory=list)


def _rows(path: Path) -> list[dict]:
    if not path.is_file():
        return []
    data = json.loads(path.read_text(encoding="utf-8"))
    rows = data.get("rows") if isinstance(data, dict) else data
    if isinstance(rows, dict):
        rows = list(rows.values())
    return rows if isinstance(rows, list) else []


def _int(value) -> int | None:
    return value if isinstance(value, int) else None


def _pos(value) -> int | None:
    return value if isinstance(value, int) and value > 0 else None


def _text(value) -> str | None:
    return value.strip() if isinstance(value, str) and value.strip() else None


def table_path(dumps: Path, client: str, table: str, locale: str | None = None) -> Path:
    return dumps / (f"{client}_{table}" + (f".{locale}" if locale else "") + ".json")


def read_items(dumps: Path, client: str) -> dict[int, ClientItem]:
    """ItemSparse (name, quality, levels, prices, stack, the quest it starts) and Item (class)."""
    classes = {
        r["ID"]: (_int(r.get("ClassID")), _int(r.get("SubclassID")))
        for r in _rows(table_path(dumps, client, "Item"))
        if isinstance(r.get("ID"), int)
    }
    out: dict[int, ClientItem] = {}
    for r in _rows(table_path(dumps, client, "ItemSparse")):
        item_id = r.get("ID")
        if not isinstance(item_id, int):
            continue
        cls, sub = classes.get(item_id, (None, None))
        out[item_id] = ClientItem(
            id=item_id,
            name=_text(r.get("Display_lang")),
            quality=_int(r.get("OverallQualityID")),
            level=_pos(r.get("ItemLevel")),
            required_level=_pos(r.get("RequiredLevel")),
            item_class=cls,
            item_subclass=sub,
            sell=_int(r.get("SellPrice")),
            buy=_int(r.get("BuyPrice")),
            stack=_pos(r.get("Stackable")),
            starts_quest=_pos(r.get("StartQuestID")),
            vendor_stack=_pos(r.get("VendorStackCount")),
        )
    return out


def read_names(dumps: Path, client: str, table: str, locale: str | None = None) -> dict[int, str]:
    """{ id: name } of a table's name column (ItemSparse, SpellName, SkillLine) in a language."""
    column = {"ItemSparse": "Display_lang", "SpellName": "Name_lang"}.get(table, "DisplayName_lang")
    out: dict[int, str] = {}
    for r in _rows(table_path(dumps, client, table, locale)):
        name = _text(r.get(column))
        if isinstance(r.get("ID"), int) and name:
            out[r["ID"]] = name
    return out


def read_recipes(dumps: Path, client: str, skill_lines: set[int]) -> list[ClientRecipe]:
    """Every ability of a profession's skill line: its spell, name, product and reagents."""
    names = read_names(dumps, client, "SpellName")
    products: dict[int, tuple[int, int | None]] = {}
    for r in _rows(table_path(dumps, client, "SpellEffect")):
        if r.get("Effect") == CREATE_ITEM and _pos(r.get("EffectItemType")):
            count = r.get("EffectBasePointsF")
            count = int(count) if isinstance(count, int | float) and count >= 1 else None
            products.setdefault(r["SpellID"], (r["EffectItemType"], count))
    reagents: dict[int, tuple[tuple[int, int], ...]] = {}
    for r in _rows(table_path(dumps, client, "SpellReagents")):
        pairs = tuple(
            (item, count)
            for item, count in zip(
                r.get("Reagent") or [], r.get("ReagentCount") or [], strict=False
            )
            if isinstance(item, int) and item > 0 and isinstance(count, int) and count > 0
        )
        if pairs:
            reagents[r["SpellID"]] = pairs
    out: dict[int, ClientRecipe] = {}
    for r in _rows(table_path(dumps, client, "SkillLineAbility")):
        spell, line = r.get("Spell"), r.get("SkillLine")
        if not (isinstance(spell, int) and line in skill_lines) or spell in out:
            continue
        product = products.get(spell)
        if product is None and spell not in reagents:
            continue  # a skill, not a recipe
        rank = _int(r.get("MinSkillLineRank"))
        out[spell] = ClientRecipe(
            spell=spell,
            name=names.get(spell),
            skill_line=line,
            learned_at=rank if rank and rank > 1 else None,
            item=product[0] if product else None,
            count=product[1] if product else None,
            reagents=reagents.get(spell, ()),
        )
    return [out[k] for k in sorted(out)]


def read_summons(dumps: Path, client: str) -> dict[int, int]:
    """{ spell: creature } of every spell that summons a companion (Effect 28) or puts its caster
    on a mount (an aura 78), the creature in EffectMiscValue[0]; the lowest effect index wins.
    Bastian's Book shows a mount's and a pet's model with it (book.md "Pictures", BK8; measured
    16.11.2026 on the dump of 1.60.1.70707: the Brown Horse's 458 rides creature 284, the
    Mechanical Squirrel's 4055 summons 2671)."""
    best: dict[int, tuple[int, int]] = {}
    for r in _rows(table_path(dumps, client, "SpellEffect")):
        spell, misc = r.get("SpellID"), r.get("EffectMiscValue")
        creature = misc[0] if isinstance(misc, list) and misc else None
        if not (isinstance(spell, int) and _pos(creature)):
            continue
        effect = r.get("Effect")
        if effect != SUMMON and not (effect == APPLY_AURA and r.get("EffectAura") == MOUNTED):
            continue
        index = _int(r.get("EffectIndex")) or 0
        if spell not in best or index < best[spell][0]:
            best[spell] = (index, creature)
    return {spell: best[spell][1] for spell in sorted(best)}


@dataclass(frozen=True)
class ClientIds:
    """The ids the client's own tables hold: its items (ItemSparse) and its spells (SpellName).
    Bastian's Book removes a wonder whose item or spell the client does not have (book.md "What
    is obtainable", E2). The client's Creature table is no such evidence: it holds 185 rows of
    build 1.60.1.70938, the creatures come from the server (measured 17.11.2026)."""

    items: frozenset[int]
    spells: frozenset[int]


def read_ids(dumps: Path, client: str) -> ClientIds | None:
    """The client's item and spell ids; None when one of the two tables is not dumped (then
    nothing is judged against them)."""

    def ids(table: str) -> frozenset[int]:
        rows = _rows(table_path(dumps, client, table))
        return frozenset(r["ID"] for r in rows if isinstance(r.get("ID"), int))

    items, spells = ids("ItemSparse"), ids("SpellName")
    if not items or not spells:
        return None
    return ClientIds(items, spells)


def read_quest_lines(dumps: Path, client: str) -> list[list[int]]:
    """Each quest line's quests in their order (QuestLineXQuest.OrderIndex)."""
    lines: dict[int, list[tuple[int, int]]] = {}
    for r in _rows(table_path(dumps, client, "QuestLineXQuest")):
        line, quest = r.get("QuestLineID"), r.get("QuestID")
        if isinstance(line, int) and isinstance(quest, int):
            lines.setdefault(line, []).append((_int(r.get("OrderIndex")) or 0, quest))
    return [[q for _, q in sorted(rows)] for _, rows in sorted(lines.items())]


def read_quest_areas(dumps: Path, client: str) -> list[QuestArea]:
    """QuestPOIBlob with its QuestPOIPoint corners: the areas the quest log draws."""
    points: dict[int, list[tuple[float, float]]] = {}
    for r in _rows(table_path(dumps, client, "QuestPOIPoint")):
        blob, x, y = r.get("QuestPOIBlobID"), r.get("X"), r.get("Y")
        if isinstance(blob, int) and isinstance(x, int | float) and isinstance(y, int | float):
            points.setdefault(blob, []).append((float(x), float(y)))
    out: list[QuestArea] = []
    for r in _rows(table_path(dumps, client, "QuestPOIBlob")):
        quest, ui_map, blob = r.get("QuestID"), r.get("UiMapID"), r.get("ID")
        if not (isinstance(quest, int) and isinstance(ui_map, int) and ui_map > 0):
            continue
        corners = points.get(blob)
        if corners:
            out.append(QuestArea(quest, ui_map, _int(r.get("ObjectiveIndex")) or 0, tuple(corners)))
    return out


def dump_name(dumps: Path, client: str, prefix: str | None) -> str:
    """The file prefix to read: the build's dump (``f70938_ItemSparse.json``, the same prefix as
    the map and travel tables) when it holds the item table, else the older ``<client>_`` files.
    Until 15.11.2026 only the latter were read, and they stayed at the build they were first
    dumped for (plan-data-quality.md, E1)."""
    if prefix and table_path(dumps, prefix, "ItemSparse").is_file():
        return prefix
    return client


def read_client_tables(
    dumps: Path, client: str, skill_lines: set[int], prefix: str | None = None
) -> ClientTables | None:
    """Everything above; None when the dumps folder has no item table for the client."""
    name = dump_name(dumps, client, prefix)
    if not table_path(dumps, name, "ItemSparse").is_file():
        return None
    t = ClientTables(
        items=read_items(dumps, name),
        recipes=read_recipes(dumps, name, skill_lines),
        quest_lines=read_quest_lines(dumps, name),
        quest_areas=read_quest_areas(dumps, name),
    )
    t.sources.append(f"client tables ({name})")
    return t


def localized_names(
    dumps: Path, client: str, prefix: str | None = None
) -> dict[str, dict[str, dict[int, dict]]]:
    """{ locale: { "item": { id: { name } } } } from every ``<name>_ItemSparse.<locale>.json``,
    ``<name>`` as `dump_name` picks it."""
    name = dump_name(dumps, client, prefix)
    out: dict[str, dict[str, dict[int, dict]]] = {}
    for path in sorted(dumps.glob(f"{name}_ItemSparse.*.json")):
        locale = path.name.split(".")[1]
        names = read_names(dumps, name, "ItemSparse", locale)
        if names:
            out[locale] = {"item": {i: {"name": n} for i, n in names.items()}}
    return out
