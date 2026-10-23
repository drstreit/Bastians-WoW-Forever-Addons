"""ForeverDB (GPL-3.0, foreverdb.net) reader: ``<AddOns>/ForeverDB/Data/*.lua`` (ADR 0008).

ForeverDB reads the Forever client, adds what players saw ("seen in Forever") and Classic data from
CMaNGOS. Formats checked 19.10.2026 on addon 0.39.0, client build 1.60.1.70450.

Coordinates: ``x_pct``/``y_pct`` are **map percent 0..100** on ``ui_map_id`` (the file already has
percent, one decimal). Unknown stays ``None``; a bare ``0`` that the file uses for "none"
(makes-item 0) becomes ``None``. Facts that Classic data only approximates are labelled in the field
name (``classic``).

Every ``parse_*`` takes the file text and does no I/O; ``read_*`` read a file.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any, NamedTuple

from .luatable import to_python
from .luatext import run_text, sorted_items

# ---------------------------------------------------------------- Meta


@dataclass(frozen=True)
class ForeverMeta:
    version: str | None  # data version, e.g. "2026-10-19.1f762939"
    built: int | None  # unix time of the data build
    build: str | None  # client build the data was read from
    addon: str | None  # addon version, e.g. "0.39.0"


def parse_meta(text: str) -> ForeverMeta:
    meta = to_python(run_text(text, "Meta.lua").meta)
    return ForeverMeta(meta.get("version"), meta.get("built"), meta.get("build"), meta.get("addon"))


# ---------------------------------------------------------------- NPCs


@dataclass(frozen=True)
class NpcRow:
    id: int
    name: str
    title: str | None
    ui_map_id: int
    x_pct: float  # map percent 0..100
    y_pct: float
    side: str | None  # "A", "H", "AH" or None
    seen_in_forever: bool  # False = Classic position converted, nobody saw the NPC yet


def _int(v: Any) -> int | None:
    return None if v is None else int(v)


def parse_npcs(text: str) -> list[NpcRow]:
    """``ns.npcs = {[npc] = {name, title, map, x, y, side, seen}}``, sorted by npc id."""
    out = []
    for npc, rec in sorted_items(run_text(text, "NPCs.lua").npcs):
        out.append(
            NpcRow(
                id=npc,
                name=rec[1],
                title=rec[2] or None,
                ui_map_id=int(rec[3]),
                x_pct=float(rec[4]),
                y_pct=float(rec[5]),
                side=rec[6] or None,
                seen_in_forever=int(rec[7] or 0) == 1,
            )
        )
    return out


# ---------------------------------------------------------------- Recipes


@dataclass(frozen=True)
class RecipeRow:
    profession: str
    spell_id: int
    name: str
    skill: int  # often the Classic value, not what Forever trainers show (measured by the owner)
    yellow: int
    green: int
    grey: int
    item_id: int | None  # item the recipe makes; None when the file has 0
    count: int
    reagents: tuple[tuple[int, int], ...]  # (item id, count)
    source_kind: str | None  # "item" (recipe item), "auto", "trainer" or None (unknown)
    source_item_id: int | None  # the recipe item when source_kind == "item"
    camp_tier: int  # 0 = not a camp recipe
    new_in_forever: bool


def parse_reagents(s: str) -> tuple[tuple[int, int], ...]:
    """``"765:1,3371:1"`` -> ``((765, 1), (3371, 1))``."""
    out = []
    for part in s.split(","):
        part = part.strip()
        if part:
            item, _, n = part.partition(":")
            out.append((int(item), int(n or 1)))
    return tuple(out)


def parse_learned_from(s: str) -> tuple[str | None, int | None]:
    """``"i<recipeItem>"`` | ``"a"`` | ``"t"`` | ``""`` -> (kind, recipe item id)."""
    if not s:
        return None, None
    if s == "a":
        return "auto", None
    if s == "t":
        return "trainer", None
    if s[0] == "i" and s[1:].isdigit():
        return "item", int(s[1:])
    raise ValueError(f"unknown learned_from {s!r}")


def parse_recipes(text: str) -> list[RecipeRow]:
    """``ns.recipes = {[profession] = {{spell, name, skill, ...}, ...}}``; professions sorted by
    name, recipes in file order."""
    out = []
    for prof, rows in sorted_items(run_text(text, "Recipes.lua").recipes):
        for _, r in sorted_items(rows):
            kind, source_item = parse_learned_from(r[10] or "")
            out.append(
                RecipeRow(
                    profession=prof,
                    spell_id=int(r[1]),
                    name=r[2],
                    skill=int(r[3]),
                    yellow=int(r[4]),
                    green=int(r[5]),
                    grey=int(r[6]),
                    item_id=int(r[7]) or None,
                    count=int(r[8]),
                    reagents=parse_reagents(r[9] or ""),
                    source_kind=kind,
                    source_item_id=source_item,
                    camp_tier=int(r[11]),
                    new_in_forever=int(r[12]) == 1,
                )
            )
    return out


# ---------------------------------------------------------------- Gather


@dataclass(frozen=True)
class GatherKind:
    id: int
    name: str
    profession: str  # "herb", "mine", "fish", "skin"
    skill: int | None  # Classic rule (ForeverDB assumption for skinning)
    item_id: int | None
    icon_file_id: int | None
    object_ids: tuple[int, ...]  # game objects (herbs, ore, fishing pools)
    npc_ids: tuple[int, ...]  # skinnable creatures
    level_range: tuple[int, int] | None


@dataclass(frozen=True)
class GatherPoint:
    kind_id: int
    ui_map_id: int
    x_pct: float  # map percent 0..100, tenth of a percent resolution
    y_pct: float
    src: str  # "classic" (CMaNGOS spawn) or "forever" (a player saw it)
    weight: float | None  # relative abundance of the kind on that map as ForeverDB gives it


@dataclass(frozen=True)
class GatherZone:
    ui_map_id: int
    fishing_skill: int | None  # Classic fishing skill of the zone


def decode_points(s: str) -> list[tuple[float, float]]:
    """4 base-36 characters per point, x then y, in tenths of a percent -> (x_pct, y_pct)."""
    if len(s) % 4:
        raise ValueError(f"point string length {len(s)} is not a multiple of 4")
    return [
        (int(s[i : i + 2], 36) / 10, int(s[i + 2 : i + 4], 36) / 10) for i in range(0, len(s), 4)
    ]


def _id_list(table: Any) -> tuple[int, ...]:
    if table is None:
        return ()
    return tuple(int(v) for _, v in sorted_items(table))


def parse_gather(text: str) -> tuple[list[GatherKind], list[GatherPoint], list[GatherZone]]:
    """``ns.gatherData`` -> (kinds, points, zones), each sorted by ids."""
    data = run_text(text, "Gather.lua").gatherData
    kinds = []
    for kid, k in sorted_items(data.kinds):
        lv = k["lv"]
        kinds.append(
            GatherKind(
                id=kid,
                name=k["n"],
                profession=k["p"],
                skill=_int(k["sk"]),
                item_id=_int(k["item"]),
                icon_file_id=_int(k["ic"]),
                object_ids=_id_list(k["o"]),
                npc_ids=_id_list(k["npc"]),
                level_range=None if lv is None else (int(lv[1]), int(lv[2])),
            )
        )
    points: list[GatherPoint] = []
    zones: list[GatherZone] = []
    for map_id, z in sorted_items(data.zones):
        zones.append(GatherZone(map_id, _int(z["fish"])))
        for kid, entry in sorted_items(z["k"]):
            weight = None if entry["w"] is None else float(entry["w"])
            for src, enc in (("classic", entry["c"]), ("forever", entry["f"])):
                for x, y in decode_points(enc or ""):
                    points.append(GatherPoint(kid, map_id, x, y, src, weight))
    return kinds, points, zones


# ---------------------------------------------------------------- Quests


@dataclass(frozen=True)
class QuestRow:
    id: int
    title: str | None
    level: int | None
    min_level: int | None  # 0 in the file means "no minimum" and is kept as 0
    objective_text: str | None
    starts: tuple[str, ...]  # entity refs "npc:823", "object:1234"
    ends: tuple[str, ...]
    seen_by_players: int | None
    new_in_forever: bool


_REF_KINDS = {"n": "npc", "o": "object"}


def parse_entity_refs(s: str) -> tuple[str, ...]:
    """``"n823"`` / ``"o1234,n5"`` -> ``("npc:823",)`` / ``("object:1234", "npc:5")``."""
    out = []
    for part in s.split(","):
        part = part.strip()
        if not part:
            continue
        kind = _REF_KINDS.get(part[0])
        if kind is None or not part[1:].isdigit():
            raise ValueError(f"unknown entity ref {part!r}")
        out.append(f"{kind}:{int(part[1:])}")
    return tuple(out)


def _opt_int(s: str) -> int | None:
    return int(s) if s.strip() else None


def parse_quests(text: str) -> list[QuestRow]:
    """``ns.qfQuests = {[quest] = "title|level|min level|objective|starts|ends|seen|new"}``."""
    out = []
    for qid, s in sorted_items(run_text(text, "QuestForever.lua").qfQuests):
        parts = s.split("|")
        if len(parts) < 8:
            raise ValueError(f"quest {qid}: expected 8 fields, got {len(parts)}")
        # a stray "|" can only be in the free text: keep the first three and last four positions
        title, level, min_level = parts[0], parts[1], parts[2]
        objective = "|".join(parts[3:-4])
        starts, ends, seen, new = parts[-4:]
        out.append(
            QuestRow(
                id=qid,
                title=title or None,
                level=_opt_int(level),
                min_level=_opt_int(min_level),
                objective_text=objective or None,
                starts=parse_entity_refs(starts),
                ends=parse_entity_refs(ends),
                seen_by_players=_opt_int(seen),
                new_in_forever=new.strip() == "1",
            )
        )
    return out


# ---------------------------------------------------------------- Items


class MadeBy(NamedTuple):
    profession: str
    skill: int


class UsedIn(NamedTuple):
    recipes: int
    professions: tuple[str, ...]


class Vendors(NamedTuple):
    count: int
    first_vendor: str
    zone: str
    seen_in_forever: bool


class Drop(NamedTuple):
    source: str
    chance_pct: float
    classic: bool
    sources: int


class DropsSeen(NamedTuple):
    count: int
    players: int


class Reputation(NamedTuple):
    faction: str
    rank: str  # name from ns.repRanks


@dataclass(frozen=True)
class ItemFacts:
    id: int
    new_in_forever: bool
    changed_in_forever: bool
    made_by: MadeBy | None
    used_in: UsedIn | None
    vendors: Vendors | None
    drop: Drop | None
    quest: str | None
    drops_seen: DropsSeen | None
    reputation: Reputation | None
    raw: str  # the untouched fact string; also the home of anything not understood


def _name(names: list[str], index: str) -> str:
    return names[int(index)]  # the file indexes professions and ranks from 0


def parse_item_facts(
    item_id: int, raw: str, professions: list[str], rep_ranks: list[str]
) -> ItemFacts:
    """Facts of one item. Sub-fields are separated by ``~``; a fact that does not have the
    expected shape stays only in ``raw``. Chances are stored x10 in the file (``190`` = 19.0 %)."""
    new = changed = False
    made_by = used_in = vendors = drop = drops_seen = reputation = None
    quest = None
    for fact in raw.split("|"):
        tag, body = fact[:1], fact[1:]
        f = body.split("~")
        if tag == "n" and not body:
            new = True
        elif tag == "c" and not body:
            changed = True
        elif tag == "m" and len(f) == 2:
            made_by = MadeBy(_name(professions, f[0]), int(f[1]))
        elif tag == "u" and len(f) == 2:
            used_in = UsedIn(int(f[0]), tuple(_name(professions, p) for p in f[1].split(",") if p))
        elif tag == "v" and len(f) == 4:
            vendors = Vendors(int(f[0]), f[1], f[2], f[3] == "1")
        elif tag == "d" and len(f) == 4:
            drop = Drop(f[0], int(f[1]) / 10, f[2] == "1", int(f[3]))
        elif tag == "q" and body:
            quest = body
        elif tag == "s" and len(f) == 2:
            drops_seen = DropsSeen(int(f[0]), int(f[1]))
        elif tag == "r" and len(f) == 2:
            reputation = Reputation(f[0], _name(rep_ranks, f[1]))
    return ItemFacts(
        item_id,
        new,
        changed,
        made_by,
        used_in,
        vendors,
        drop,
        quest,
        drops_seen,
        reputation,
        raw,
    )


def parse_items(text: str) -> list[ItemFacts]:
    """``ns.items = {[item] = "<facts separated by |>"}``, sorted by item id."""
    ns = run_text(text, "Items.lua")
    professions = [v for _, v in sorted_items(ns.professions)]
    ranks = [v for _, v in sorted_items(ns.repRanks)]
    return [parse_item_facts(i, raw, professions, ranks) for i, raw in sorted_items(ns["items"])]


# ---------------------------------------------------------------- SearchNames


def parse_search_names(text: str) -> dict[int, str]:
    """``ns.searchItemNames = {[item] = name}``; names verbatim (see ``is_old``)."""
    return dict(sorted_items(run_text(text, "SearchNames.lua").searchItemNames))


def is_old(name: str) -> bool:
    """ForeverDB prefixes retired items with ``OLD``."""
    return name.startswith("OLD")


# ---------------------------------------------------------------- files


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig")


def read_meta(path: Path) -> ForeverMeta:
    return parse_meta(_read(path))


def read_npcs(path: Path) -> list[NpcRow]:
    return parse_npcs(_read(path))


def read_recipes(path: Path) -> list[RecipeRow]:
    return parse_recipes(_read(path))


def read_gather(path: Path) -> tuple[list[GatherKind], list[GatherPoint], list[GatherZone]]:
    return parse_gather(_read(path))


def read_quests(path: Path) -> list[QuestRow]:
    return parse_quests(_read(path))


def read_items(path: Path) -> list[ItemFacts]:
    return parse_items(_read(path))


def read_search_names(path: Path) -> dict[int, str]:
    return parse_search_names(_read(path))
