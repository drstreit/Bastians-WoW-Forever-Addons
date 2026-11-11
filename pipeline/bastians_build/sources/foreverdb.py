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

import re
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
    confirmed_previous: int | None = None  # the quest players were seen to need first; 0 is none
    lowest_level_seen: int | None = None  # the lowest level seen completing it; 0 is unknown
    # "A" or "H" as ForeverDB works it out from the quest's NPCs and the quest before it (0.57.24);
    # None is unknown. Read and not used yet: the quest's own `races` come from the other sources.
    side: str | None = None


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


_QUEST_HEADER = re.compile(r'^--\s*\[quest\]\s*=\s*"([^"]*)"', re.MULTILINE)
# The columns the reader reads, each by a word of its name in the file's own header. ForeverDB adds
# columns at the end: two with 0.57.14 (measured 08.11.2026, build 1.60.1.70862: the confirmed
# previous quest and the lowest level seen completing it), the side with 0.57.24 (11.11.2026).
# Each of them held the source for a day, because the reader knew layouts by their length. Since
# 11.11.2026 a column behind the ones named here is left unread (the sources step's shape check
# names it), and a known column that is not where it was stops the read.
_QUEST_COLUMNS = (
    "title",
    "level",
    "min level",
    "objective",
    "starts",
    "ends",
    "saw",
    "new in forever",
    "previous",
    "lowest",
    "side",
)
_QUEST_BASE = 8  # the layout of a file without the header, and the fewest a header may name
_SIDES = {"a": "A", "h": "H"}


def _quest_columns(text: str) -> int:
    """The file's own header names its columns; a row's field count cannot, a "|" may be in the
    free text. A file without the header is the 8-column layout."""
    header = _QUEST_HEADER.search(text)
    if not header:
        return _QUEST_BASE
    names = header.group(1).split("|")
    if len(names) < _QUEST_BASE:
        raise ValueError(
            f"QuestForever.lua has {len(names)} columns, the reader needs the first {_QUEST_BASE}"
        )
    for i, (name, word) in enumerate(zip(names, _QUEST_COLUMNS, strict=False), 1):
        if word not in name.lower():
            raise ValueError(
                f"QuestForever.lua: column {i} is {name.strip()!r}, the reader expects {word!r}"
            )
    return len(names)


def parse_quests(text: str) -> list[QuestRow]:
    """``ns.qfQuests = {[quest] = "title|level|min level|objective|starts|ends|seen|new"}``, with
    more columns at the end since ForeverDB 0.57.14 (``_QUEST_COLUMNS``)."""
    columns = _quest_columns(text)
    after_objective = columns - 4
    out = []
    for qid, s in sorted_items(run_text(text, "QuestForever.lua").qfQuests):
        parts = s.split("|")
        if len(parts) < columns:
            raise ValueError(f"quest {qid}: expected {columns} fields, got {len(parts)}")
        # a stray "|" can only be in the free text: keep the first three and the last positions
        title, level, min_level = parts[0], parts[1], parts[2]
        objective = "|".join(parts[3:-after_objective])
        # starts, ends, seen, new, then what later versions added; absent is empty
        tail = parts[-after_objective:] + [""] * 3
        starts, ends, seen, new, previous, lowest, side = tail[:7]
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
                confirmed_previous=_opt_int(previous) or None,
                lowest_level_seen=_opt_int(lowest) or None,
                side=_SIDES.get(side.strip().lower()),
            )
        )
    return out


# ---------------------------------------------------------------- Dungeons


@dataclass(frozen=True)
class DungeonBoss:
    order: int  # the client's order inside the instance, from 1
    # ForeverDB's boss number: the client's encounter id, NOT a creature id (02.11.2026: Onyxia is
    # 1084, her creature 10184; Shadowfang Keep's 2748 is the creature Archaedas). The creature
    # comes from Loot.lua (BossCreatures) or by name (canon._boss_creature).
    number: int
    name: str


@dataclass(frozen=True)
class DungeonLoot:
    item_id: int
    boss_order: int  # 0: the instance's loot without a boss named
    label: str  # "s" seen by ForeverDB players in Forever, "c" the client ties it to the instance


@dataclass(frozen=True)
class DungeonRow:
    id: int  # the instance's Map.db2 id (33 Shadowfang Keep, 3065 The Hall of Thanes)
    name: str
    kind: str  # "dungeon" | "raid"
    size: int | None  # group size
    level_lo: int | None
    level_hi: int | None
    level_req: int | None  # assumed (30.10.2026): the third number of `lv` is the entrance's level
    zone_name: str | None  # the zone's name as ForeverDB writes it
    bosses: tuple[DungeonBoss, ...]
    loot: tuple[DungeonLoot, ...]
    quests: tuple[int, ...]


def parse_dungeons(text: str) -> list[DungeonRow]:
    """``ns.dungeons = {[map] = {n, kind, size, lv = "lo:hi:req", ent, zone, boss =
    "order:number:name|...", loot = "item:order:label ...", q = "id id", guide}}`` (the header of
    ForeverDB's Dungeons.lua, 0.44.0). `ent` and `guide` are ForeverDB's own, not read."""
    out = []
    for map_id, raw in sorted_items(run_text(text, "Dungeons.lua").dungeons):
        rec = to_python(raw)
        levels = [_opt_int(x) for x in str(rec.get("lv") or "").split(":")] + [None] * 3
        bosses = []
        for part in str(rec.get("boss") or "").split("|"):
            if not part.strip():
                continue
            order, npc, name = part.split(":", 2)
            bosses.append(DungeonBoss(int(order), int(npc), name))
        loot = []
        for part in str(rec.get("loot") or "").split():
            item, order, label = part.split(":")
            loot.append(DungeonLoot(int(item), int(order), label))
        size = rec.get("size")
        out.append(
            DungeonRow(
                id=int(map_id),
                name=rec["n"],
                kind=rec.get("kind") or "dungeon",
                size=int(size) if size else None,
                level_lo=levels[0],
                level_hi=levels[1],
                level_req=levels[2],
                zone_name=rec.get("zone") or None,
                bosses=tuple(bosses),
                loot=tuple(loot),
                quests=tuple(int(q) for q in str(rec.get("q") or "").split()),
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


def read_dungeons(path: Path) -> list[DungeonRow]:
    return parse_dungeons(_read(path))


# ---------------------------------------------------------------- The bosses' creatures


@dataclass(frozen=True)
class BossCreatures:
    """Loot.lua's bosses with their creature ids (02.11.2026): Dungeons.lua's boss numbers are not
    creature ids (Shadowfang Keep's 2748 is the creature Archaedas, Dalaran's 3298 Gabrielle
    Chase), Loot.lua names the creature where ForeverDB knows it."""

    npcs: dict[int, dict[str, int]]  # instance id -> the boss's name, lower case -> creature id
    forever: frozenset[int]  # the instances only Forever has (`forever = true`)


_LOOT_INSTANCE = re.compile(r"^\s*\{ id = (\d+), name = ")
_LOOT_BOSS = re.compile(r'^\s*\{ npc = (\d+), name = "((?:[^"\\]|\\.)*)"')


def parse_boss_creatures(text: str) -> BossCreatures:
    npcs: dict[int, dict[str, int]] = {}
    forever: set[int] = set()
    current: int | None = None
    for line in text.splitlines():
        m = _LOOT_INSTANCE.match(line)
        if m:
            current = int(m.group(1))
            if "forever = true" in line:
                forever.add(current)
            continue
        m = _LOOT_BOSS.match(line)
        if m and current is not None:
            npcs.setdefault(current, {})[m.group(2).replace('\\"', '"').lower()] = int(m.group(1))
    return BossCreatures(npcs=npcs, forever=frozenset(forever))


def read_boss_creatures(path: Path) -> BossCreatures:
    return parse_boss_creatures(_read(path))


# ---------------------------------------------------------------- Dungeon maps


@dataclass(frozen=True)
class FloorTile:
    fdid: int  # the client's minimap tile, by file data id
    x: int  # floor pixels, from the floor's top left (may be negative: the tile is cropped)
    y: int
    w: int
    h: int
    q: int  # quarter turns the tile is drawn with


@dataclass(frozen=True)
class DungeonFloor:
    name: str
    width: int  # floor pixels
    height: int
    tiles: tuple[FloorTile, ...]  # empty when the client's file could not be read (ForeverDB `why`)
    # the floor's place in the world (`s` pixels per yard, `x`/`y` the world point of the floor's
    # top left corner, `z` its height band): a spot in percent of the floor becomes a world point
    # as wx = x0 - py / scale, wy = y0 - px / scale (checked 30.10.2026: Targorr the Dread's
    # Classic spawn 159.6, 1.3 from ForeverDB's spot 49.88 %, 30.11 % of the Stockade's floor)
    scale: float | None = None
    x0: float | None = None
    y0: float | None = None
    z_lo: float | None = None
    z_hi: float | None = None

    def world_point(self, x_pct: float, y_pct: float) -> tuple[float, float] | None:
        if not (self.scale and self.x0 is not None and self.y0 is not None):
            return None
        px, py = x_pct / 100 * self.width, y_pct / 100 * self.height
        return self.x0 - py / self.scale, self.y0 - px / self.scale

    @property
    def z_mid(self) -> float | None:
        if self.z_lo is None or self.z_hi is None:
            return None
        return (self.z_lo + self.z_hi) / 2


@dataclass(frozen=True)
class DungeonMapRow:
    id: int  # the instance's Map.db2 id
    floors: tuple[DungeonFloor, ...]
    boss_spots: tuple[tuple[int, int, float, float], ...]  # order, floor (from 1), x %, y %
    door: tuple[int, float, float] | None  # floor, x %, y % of the entrance
    why: str | None  # ForeverDB's note when a map is missing


def parse_dungeon_maps(text: str) -> list[DungeonMapRow]:
    """``ns.dungeonMaps = {[map] = {floors = {{n, w, h, s, x, y, z, t = "fdid:x:y:w:h:q ..."}},
    boss = "order:floor:x:y ...", ent = "floor:x:y", why = text}}`` (the header of ForeverDB's
    DungeonMaps.lua, 0.44.0); `s`, `x`, `y`, `z` place the floor in the world (DungeonFloor)."""
    out = []
    for map_id, raw in sorted_items(run_text(text, "DungeonMaps.lua").dungeonMaps):
        rec = to_python(raw)
        floors = []
        for f in (
            (rec.get("floors") or {}).values()
            if isinstance(rec.get("floors"), dict)
            else (rec.get("floors") or [])
        ):
            tiles = []
            for part in str(f.get("t") or "").split():
                fdid, x, y, w, h, q = (int(v) for v in part.split(":"))
                tiles.append(FloorTile(fdid, x, y, w, h, q))
            z_lo = z_hi = None
            if f.get("z"):
                lo, _, hi = str(f["z"]).partition(":")
                z_lo, z_hi = float(lo), float(hi or lo)
            floors.append(
                DungeonFloor(
                    str(f.get("n") or ""),
                    int(f["w"]),
                    int(f["h"]),
                    tuple(tiles),
                    float(f["s"]) if f.get("s") is not None else None,
                    float(f["x"]) if f.get("x") is not None else None,
                    float(f["y"]) if f.get("y") is not None else None,
                    z_lo,
                    z_hi,
                )
            )
        bosses = []
        for part in str(rec.get("boss") or "").split():
            order, floor, x, y = part.split(":")
            bosses.append((int(order), int(floor), float(x), float(y)))
        door = None
        if rec.get("ent"):
            floor, x, y = str(rec["ent"]).split(":")
            door = (int(floor), float(x), float(y))
        out.append(
            DungeonMapRow(int(map_id), tuple(floors), tuple(bosses), door, rec.get("why") or None)
        )
    return out


def read_dungeon_maps(path: Path) -> list[DungeonMapRow]:
    return parse_dungeon_maps(_read(path))


def read_items(path: Path) -> list[ItemFacts]:
    return parse_items(_read(path))


def read_search_names(path: Path) -> dict[int, str]:
    return parse_search_names(_read(path))


# ---------------------------------------------------------------- What players saw (06.11.2026)


def _items(table: Any) -> list[tuple[Any, Any]]:
    """A table the file may not have yet (older ForeverDB, the fixture): absent is empty."""
    return [] if table is None else list(sorted_items(table))


class SeenPoint(NamedTuple):
    ui_map_id: int
    x_pct: float
    y_pct: float


@dataclass(frozen=True)
class QuestSeen:
    """`qfSeen`: where players' Companion addons saw a quest offered, handed in and advanced."""

    id: int
    starts: tuple[SeenPoint, ...]
    ends: tuple[SeenPoint, ...]
    objectives: dict[int, tuple[SeenPoint, ...]]  # objective number (1-based) -> places


def parse_points(text: str | None) -> tuple[SeenPoint, ...]:
    """Space-separated base-36 numbers, each map * 1,000,000 + x * 10 * 1,000 + y * 10."""
    out = []
    for word in (text or "").split():
        value = int(word, 36)
        out.append(
            SeenPoint(value // 1_000_000, (value % 1_000_000) // 1000 / 10, (value % 1000) / 10)
        )
    return tuple(out)


def parse_quest_seen(text: str) -> dict[int, QuestSeen]:
    out = {}
    for quest, rec in _items(run_text(text, "QuestForever.lua").qfSeen):
        row = to_python(rec)
        spots = row.get("o") or {}
        if isinstance(spots, list):  # keys 1..n come back as a list
            spots = {i + 1: v for i, v in enumerate(spots)}
        out[quest] = QuestSeen(
            quest,
            parse_points(row.get("s")),
            parse_points(row.get("e")),
            {int(n): parse_points(v) for n, v in sorted(spots.items())},
        )
    return out


def read_quest_seen(path: Path) -> dict[int, QuestSeen]:
    return parse_quest_seen(path.read_text(encoding="utf-8"))


def parse_triggers(text: str) -> dict[int, SeenPoint]:
    """`qfArea`: where an area trigger is in the Forever client (ForeverDB 0.57.x; absent in
    an older file). A quest that is finished by reaching one names it (CMaNGOS)."""
    out = {}
    for trigger, where in _items(run_text(text, "QuestForever.lua").qfArea):
        points = parse_points(where)
        if points:
            out[int(trigger)] = points[0]
    return out


def read_triggers(path: Path) -> dict[int, SeenPoint]:
    return parse_triggers(path.read_text(encoding="utf-8"))


def parse_npc_names(text: str) -> dict[int, str]:
    """`qfNpcNames`: the creatures of Forever's quests by the name players saw."""
    return dict(_items(run_text(text, "QuestForever.lua").qfNpcNames))


def read_npc_names(path: Path) -> dict[int, str]:
    return parse_npc_names(path.read_text(encoding="utf-8"))


def parse_quest_xp(text: str) -> dict[int, int]:
    """`qxp.q`: a quest's full XP as players measured it in Forever."""
    return {int(k): int(v) for k, v in sorted_items(run_text(text, "QuestXP.lua").qxp.q)}


def read_quest_xp(path: Path) -> dict[int, int]:
    return parse_quest_xp(path.read_text(encoding="utf-8"))


@dataclass(frozen=True)
class GuideRewards:
    """What `qgQuests` says a quest pays, only what it marks as seen in Forever (source "f")."""

    id: int
    money: int | None
    items: tuple[tuple[int, int], ...]
    choices: tuple[tuple[int, int], ...]


def _reward_items(text: str) -> tuple[tuple[int, int], ...]:
    out = []
    for word in text.split():
        item, _, count = word.partition(":")
        out.append((int(item), int(count or 1)))
    return tuple(out)


def parse_quest_guide(text: str) -> dict[int, GuideRewards]:
    """`qgQuests[quest]` = "zone|text|objectives|their sources|money|its source|xp:level|items|
    choices|their source|reputation|..."; a source of "c" is Classic, which CMaNGOS gives too."""
    out = {}
    for quest, row in sorted_items(run_text(text, "QuestGuide.lua").qgQuests):
        parts = row.split("|")
        if len(parts) < 10:
            continue
        money = _opt_int(parts[4]) if parts[5] == "f" else None
        forever_items = parts[9] == "f"
        items = _reward_items(parts[7]) if forever_items else ()
        choices = _reward_items(parts[8]) if forever_items else ()
        if (money and money > 0) or items or choices:
            out[quest] = GuideRewards(quest, money if money and money > 0 else None, items, choices)
    return out


def read_quest_guide(path: Path) -> dict[int, GuideRewards]:
    return parse_quest_guide(path.read_text(encoding="utf-8"))


class SoldRow(NamedTuple):
    item: int
    price: int | None  # copper for the vendor stack; 0 in the file is unknown
    stack: int | None
    limited: bool


def parse_sold(text: str) -> dict[int, list[SoldRow]]:
    """`sold[item]` = {npc, price, stack, limited, npc, ...}, turned round to npc -> offers. The
    file keeps fewer vendors for an item many sell (`soldCount`), so a list can be short."""
    out: dict[int, list[SoldRow]] = {}
    for item, rec in _items(run_text(text, "NPCs.lua").sold):
        row = to_python(rec)
        for i in range(0, len(row) - 3, 4):
            npc, price, stack, limited = row[i : i + 4]
            out.setdefault(int(npc), []).append(
                SoldRow(int(item), int(price) or None, int(stack) or None, bool(limited))
            )
    return dict(sorted(out.items()))


def read_sold(path: Path) -> dict[int, list[SoldRow]]:
    return parse_sold(path.read_text(encoding="utf-8"))


def parse_trainers(text: str) -> frozenset[int]:
    """Every NPC of `classTrainers` and `profTrainers`."""
    ns = run_text(text, "NPCs.lua")
    ids: set[int] = set()
    for table in (ns.classTrainers, ns.profTrainers):
        for _, npcs in _items(table):
            ids.update(int(n) for n in to_python(npcs))
    return frozenset(ids)


def read_trainers(path: Path) -> frozenset[int]:
    return parse_trainers(path.read_text(encoding="utf-8"))
