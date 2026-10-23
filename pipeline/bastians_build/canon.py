"""The canonical model (data.md): merge every source into one World, with explicit precedence.

Precedence per field, highest first: own captures > Forever sources (Everything Quests, ForeverDB
where a player saw it) > ForeverDB converted places > QuestieDB > Classic (CMaNGOS). Every point
carries its ``src``; Classic values are labelled ``classic`` (CLAUDE.md §8); unknown stays ``None``.
Classic world positions are placed through the transform table or dropped with a reason.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

from bastians_build.coords import (
    CMANGOS_CONTINENT,
    Spawn,
    best_map,
    named_map,
    pct_to_fraction,
    place_world_point,
)
from bastians_build.model import World
from bastians_build.sources import cmangos, foreverdb
from bastians_build.sources.allthethings import AllTheThings
from bastians_build.sources.clientdump import TaxiNode
from bastians_build.sources.everything_quests import EverythingQuests
from bastians_build.sources.itemdb import ItemDB
from bastians_build.sources.probe import Transform

MAX_SPOTS_PER_MAP = 8  # objective spots kept per quest and map (EQ orders densest first)
MAX_DROPS_PER_ITEM = 20
MAX_LOOT_PER_NPC = 30

# CMaNGOS NpcFlags bits -> service flags (data.md npc record)
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
RANKS = {1: "elite", 2: "rareelite", 3: "boss", 4: "rare"}
# CMaNGOS gameobject_template.type -> the object kind (data.md object record, ADR 0016): the
# Browser shows the kinds a player looks for and folds the technical ones into "Other". A type
# number not listed here is "other".
OBJECT_KINDS = {
    0: "door",
    1: "button",
    2: "quest object",
    3: "chest",
    4: "binder",
    5: "signpost",
    6: "trap",
    7: "chair",
    8: "fire and forge",
    9: "book",
    10: "usable",
    11: "elevator",
    12: "area damage",
    13: "camera",
    14: "map object",
    15: "ship",
    16: "duel flag",
    17: "bobber",
    18: "ritual",
    19: "mailbox",
    20: "auction house",
    21: "guard post",
    22: "portal",
    23: "meeting stone",
    24: "flag stand",
    25: "fishing pool",
    26: "flag drop",
    27: "mini game",
    28: "lottery kiosk",
    29: "capture point",
    30: "aura",
}
WS = re.compile(r"\s+")


def object_kind(type_number) -> str | None:
    """The kind word of a game-object type number; None stays unknown, never a guess."""
    if type_number is None:
        return None
    return OBJECT_KINDS.get(int(type_number), "other")


def clean_name(name: str | None) -> str | None:
    """Collapse whitespace (EQ ships 'Wanted:  "Hogger"'); empty -> None."""
    if name is None:
        return None
    text = WS.sub(" ", name).strip()
    return text or None


@dataclass
class Sources:
    """Everything the readers produced; any part may be None when that source is not available."""

    client: str
    build: str = "unknown"
    eq: EverythingQuests | None = None
    fdb_npcs: list[foreverdb.NpcRow] = field(default_factory=list)
    fdb_recipes: list[foreverdb.RecipeRow] = field(default_factory=list)
    fdb_gather: tuple[list, list, list] | None = None
    fdb_quests: list[foreverdb.QuestRow] = field(default_factory=list)
    fdb_items: list[foreverdb.ItemFacts] = field(default_factory=list)
    fdb_names: dict[int, str] = field(default_factory=dict)
    cm_quests: list[cmangos.QuestRow] = field(default_factory=list)
    cm_creatures: list[dict] = field(default_factory=list)  # creature_template rows
    cm_objects: list[dict] = field(default_factory=list)  # gameobject_template rows
    cm_spawns: list[cmangos.SpawnRow] = field(default_factory=list)
    cm_vendors: list[cmangos.VendorRow] = field(default_factory=list)
    cm_trainers: list[cmangos.TrainerService] = field(default_factory=list)
    cm_loot: list[cmangos.LootRow] = field(default_factory=list)
    cm_items: list[cmangos.ItemRow] = field(default_factory=list)
    cm_spell_names: dict[int, str] = field(default_factory=dict)  # spell_template SpellName
    area_to_map: dict[int, int] = field(default_factory=dict)
    att: AllTheThings | None = None  # retail: AllTheThings db/Standard (quests, places)
    idb: ItemDB | None = None  # retail: ItemDB names, item facts, places
    taxi: list[TaxiNode] = field(default_factory=list)  # clientdump TaxiNodes (flight masters)
    quest_titles: dict[int, str] = field(default_factory=dict)  # clientdump QuestV2CliTask (D1)
    transforms: dict[int, Transform] = field(default_factory=dict)
    transforms_source: str | None = None  # where the transform table came from
    notes: list[str] = field(default_factory=list)  # reader notes for the report
    map_names: dict[int, str] = field(default_factory=dict)
    map_parents: dict[int, tuple[int | None, int | None]] = field(
        default_factory=dict
    )  # parent, continent
    # UiMap.Type per map: 2 continent, 3 zone, 4 dungeon, 5 micro, 6 orphan (R5)
    map_types: dict[int, int] = field(default_factory=dict)
    continents: dict[int, str] = field(default_factory=dict)  # Map.db2 id -> name (clientdump)
    # The retail client's UiMap names and types, for maps the build's own client lacks (the
    # Forever client has no dungeon maps, its quests name them by the shared retail ids: zone 300
    # Razorfen Downs showed as "zone:300", )
    fallback_map_names: dict[int, str] = field(default_factory=dict)
    fallback_map_types: dict[int, int] = field(default_factory=dict)
    source_names: list[str] = field(default_factory=list)


def _rec(world: World, record_type: str, record_id: int) -> dict:
    rec = world.get(record_type, record_id)
    if rec is None:
        rec = {}
        world.add(record_type, record_id, rec)
    return rec


def _add_spawn(rec: dict, spawn: Spawn) -> None:
    spawns = rec.setdefault("spawns", [])
    row = spawn.row()
    if row not in spawns:
        spawns.append(row)


def quest_xp(money_at_max_level: int | None) -> int | None:
    """The XP of a 1.12 quest from the money it pays at level 60 instead (6 copper per 10 XP),
    rounded to 5 like the client's values; None when the quest pays nothing at 60."""
    if not money_at_max_level or money_at_max_level <= 0:
        return None
    return round(money_at_max_level / 0.6 / 5) * 5


def _set_if_missing(rec: dict, key: str, value) -> None:
    if value is not None and rec.get(key) is None:
        rec[key] = value


# ---------------------------------------------------------------------------------------------
# Zones
# ---------------------------------------------------------------------------------------------


def merge_zones(world: World, s: Sources) -> None:
    for ui_map_id, name in sorted(s.map_names.items()):
        rec = _rec(world, "zone", ui_map_id)
        rec["name"] = clean_name(name)
        parent, continent = s.map_parents.get(ui_map_id, (None, None))
        rec["parent"] = parent
        rec["continent"] = continent
        rec["mapType"] = s.map_types.get(ui_map_id)  # None when the source has no type


# ---------------------------------------------------------------------------------------------
# NPCs and objects
# ---------------------------------------------------------------------------------------------


# Words that give a ForeverDB name away as a localized client's ("Saldean le fermier", Forever
# beta 22.10.2026): French and German function words as whole tokens, or any non-ASCII letter.
# Marisa du'Paige keeps her name: "du'Paige" is one token.
LOCALIZED_WORDS = frozenset(
    [
        "le",
        "la",
        "les",
        "du",
        "des",
        "de",
        "et",
        "au",
        "aux",
        "der",
        "die",
        "das",
        "den",
        "dem",
        "des",
        "und",
        "von",
        "zum",
        "zur",
    ]
)


def localized_name(name: str | None) -> bool:
    """Whether a name looks like a translation rather than the English name."""
    if not name:
        return False
    if any(ord(ch) > 127 for ch in name):
        return True
    return any(token.lower() in LOCALIZED_WORDS for token in name.split())


def level_band(levels: list[int], trim_from: int = 10) -> tuple[int, int, int] | None:
    """(lo, hi, median) of a zone's quest levels. With `trim_from` quests or more, levels more than
    one interquartile range beyond the quartiles are left out, so a handful of high-level quests
    given in a starting zone no longer make it "1-60" (Elwynn and Westfall, Forever beta
    22.10.2026); fewer quests give min and max."""
    if not levels:
        return None
    levels = sorted(levels)
    n = len(levels)
    median = levels[n // 2]
    if n < trim_from:
        return levels[0], levels[-1], median
    q1, q3 = levels[n // 4], levels[(3 * n) // 4]
    spread = max(1, q3 - q1)
    low_fence, high_fence = q1 - spread, q3 + spread
    kept = [level for level in levels if low_fence <= level <= high_fence]
    return kept[0], kept[-1], median


# Quest flags whose levels say nothing about the zone's band (repeatable: the Darkmoon Faire's
# level-60 turn-ins stand in Elwynn and Mulgore)
BAND_EXCLUDED_FLAGS = frozenset(
    {"class", "profession", "instance", "event", "holiday", "repeatable"}
)


def merge_creatures(world: World, s: Sources) -> None:
    # Classic baseline: names, levels, flags for every creature
    for row in s.cm_creatures:
        rec = _rec(world, "npc", int(row["Entry"]))
        _set_if_missing(rec, "name", clean_name(row.get("Name")))
        _set_if_missing(rec, "subname", clean_name(row.get("SubName")))
        lo, hi = row.get("MinLevel"), row.get("MaxLevel")
        if lo is not None:
            rec["level"] = int(lo)
            rec["levelMax"] = int(hi) if hi is not None and hi != lo else None
        flags = int(row.get("NpcFlags") or 0)
        services = [name for bit, name in NPC_FLAGS.items() if flags & bit]
        rank = RANKS.get(int(row.get("Rank") or 0))
        if rank:
            services.append(rank)
        rec["flags"] = services or None
        rec["src"] = "classic"
    for row in s.cm_objects:
        rec = _rec(world, "object", int(row["entry"]))
        _set_if_missing(rec, "name", clean_name(row.get("name")))
        rec["kind"] = object_kind(row.get("type"))
        rec["src"] = "classic"
    # EQ names for quest givers and takers (Forever) win over Classic names
    if s.eq:
        for npc_id, name in s.eq.npc_names.items():
            rec = _rec(world, "npc", npc_id)
            rec["name"] = clean_name(name) or rec.get("name")
            rec["src"] = "forever"
        for obj_id, name in s.eq.object_names.items():
            rec = _rec(world, "object", obj_id)
            rec["name"] = clean_name(name) or rec.get("name")
            rec["src"] = "forever"
    # ForeverDB vendors and trainers: Forever coordinates (converted Classic places unless seen)
    for npc in s.fdb_npcs:
        rec = _rec(world, "npc", npc.id)
        if npc.seen_in_forever or rec.get("name") is None:
            name = clean_name(npc.name)
            if name and rec.get("name") and localized_name(name):
                world.notes.append(
                    f"npc {npc.id}: ForeverDB name {name!r} looks localized, kept {rec['name']!r}"
                )
            else:
                rec["name"] = name or rec.get("name")
        _set_if_missing(rec, "subname", clean_name(npc.title))
        rec["faction"] = npc.side
        if not rec.get("flags"):
            # ForeverDB lists vendors and trainers only; without Classic NpcFlags the title decides
            title = (npc.title or "").lower()
            rec["flags"] = ["trainer"] if "trainer" in title or "master" in title else ["vendor"]
        src = "fdb" if npc.seen_in_forever else "fdb-classic"
        _add_spawn(rec, pct_to_fraction(npc.ui_map_id, npc.x_pct, npc.y_pct, src))
        if npc.seen_in_forever:
            rec["src"] = "forever"
    # Classic spawns through the transform table
    for spawn in s.cm_spawns:
        record_type = "npc" if spawn.kind == "creature" else "object"
        if spawn.map_id not in CMANGOS_CONTINENT:
            world.drop(
                record_type, spawn.entry, "classic spawn on an instance map: not placed (L+)"
            )
            continue
        placed = place_world_point(
            s.transforms, spawn.map_id, spawn.position_x, spawn.position_y, "classic"
        )
        if placed is None:
            world.drop(
                record_type, spawn.entry, f"classic spawn on map {spawn.map_id} has no transform"
            )
            continue
        rec = world.get(record_type, spawn.entry)
        if rec is None:
            world.drop(record_type, spawn.entry, "spawn of an unknown entry")
            continue
        _add_spawn(rec, placed)
    # Everything Quests start and turn-in places carry the Forever position of the giver or taker
    if s.eq:
        for q in s.eq.quests.values():
            for place in (*q.starts, *q.turn_ins):
                if place.source_id and place.kind in ("npc", "object") and not place.entrance:
                    rec = _rec(world, place.kind, place.source_id)
                    _add_spawn(
                        rec, Spawn(place.ui_map_id, round(place.x, 4), round(place.y, 4), "eq")
                    )
                    _set_if_missing(rec, "src", "forever")


def assign_zones(world: World) -> None:
    """Zone of an npc, object or node without one: the map of its first spawn."""
    for record_type in ("npc", "object", "node"):
        for rec in world.records.get(record_type, {}).values():
            spawns = rec.get("spawns")
            if spawns and rec.get("zone") is None:
                rec["zone"] = spawns[0][0]


def merge_vendors_and_trainers(world: World, s: Sources) -> None:
    prices = {it.id: (it.buy_price, it.stackable) for it in s.cm_items}
    for v in s.cm_vendors:
        rec = world.get("npc", v.npc_id)
        if rec is None:
            world.drop("npc", v.npc_id, "vendor list for an unknown npc")
            continue
        price, _stack = prices.get(v.item_id, (None, None))
        # the merchant buy price is for the vendor stack; the dump has no stack size (CLAUDE.md §12)
        rec.setdefault("vendor", []).append(
            [v.item_id, price, None, v.max_count is not None, "classic"]
        )
    for t in s.cm_trainers:
        rec = world.get("npc", t.trainer_id)
        if rec is None:
            continue
        rec.setdefault("trainer", []).append(
            [
                t.learned_spell_id,
                t.name,
                t.cost,
                t.req_skill_value,
                t.req_level,
                t.item_id,
                "classic",
            ]
        )


# ---------------------------------------------------------------------------------------------
# Quests
# ---------------------------------------------------------------------------------------------


def _place_refs(places) -> tuple[list[str], list[list]]:
    refs, points = [], []
    for p in places:
        if p.source_id and p.kind in ("npc", "object"):
            ref = f"{p.kind}:{p.source_id}"
            if ref not in refs:
                refs.append(ref)
        points.append([p.ui_map_id, round(p.x, 4), round(p.y, 4), "eq"])
    return refs, points


def merge_quests(world: World, s: Sources) -> None:
    if s.eq:
        for quest_id, q in s.eq.quests.items():
            rec = _rec(world, "quest", quest_id)
            rec["name"] = clean_name(q.name)
            if q.gates:
                rec["level"] = q.gates.quest_level or None
                rec["minLevel"] = q.gates.required_level or None
                rec["races"] = q.gates.required_races or None
                rec["classes"] = q.gates.required_classes or None
            starts, start_points = _place_refs(q.starts)
            ends, end_points = _place_refs(q.turn_ins)
            rec["starts"] = starts or None
            rec["startPlaces"] = start_points or None
            rec["ends"] = ends or None
            rec["endPlaces"] = end_points or None
            rec["pre"] = q.pre_all or None
            rec["preAny"] = q.pre_any or None
            rec["excl"] = q.exclusive or None
            rec["chain"] = q.chain
            rec["parent"] = q.parent
            rec["skill"] = list(q.skill) if q.skill else None
            rec["minRep"] = list(q.min_rep) if q.min_rep else None
            flags = sorted(q.categories)
            if q.gates and q.gates.repeatable and "repeatable" not in flags:
                flags.append("repeatable")
            rec["flags"] = flags or None
            rec["holiday"] = q.holiday
            if q.coord:
                rec["zone"] = q.coord.ui_map_id
            elif start_points:
                rec["zone"] = start_points[0][0]
            rec["objectives"] = [[o.kind, f"npc:{o.npc_id}", o.index] for o in q.objectives] or None
            spots: dict[int, list] = {}
            for p in q.spawns:
                lst = spots.setdefault(p.ui_map_id, [])
                if len(lst) < MAX_SPOTS_PER_MAP:
                    lst.append([round(p.x, 4), round(p.y, 4), p.kind, p.objective_mask or 0])
            rec["spots"] = {m: v for m, v in sorted(spots.items())} or None
            rec["src"] = "forever"
    # ForeverDB quest facts: Forever-new flag, players who saw it, fallback names and places
    for fq in s.fdb_quests:
        rec = _rec(world, "quest", fq.id)
        _set_if_missing(rec, "name", clean_name(fq.title))
        _set_if_missing(rec, "level", fq.level or None)
        _set_if_missing(rec, "minLevel", fq.min_level or None)
        _set_if_missing(rec, "starts", list(fq.starts) or None)
        _set_if_missing(rec, "ends", list(fq.ends) or None)
        _set_if_missing(rec, "objectiveText", clean_name(fq.objective_text))
        if fq.new_in_forever:
            rec["foreverOnly"] = True
        rec["seenBy"] = fq.seen_by_players
        _set_if_missing(rec, "src", "forever")
    # Classic rewards and texts (labelled classic)
    for cq in s.cm_quests:
        rec = _rec(world, "quest", cq.id)
        _set_if_missing(rec, "name", clean_name(cq.title))
        _set_if_missing(
            rec, "level", cq.quest_level if cq.quest_level and cq.quest_level > 0 else None
        )
        _set_if_missing(rec, "minLevel", cq.min_level or None)
        if cq.zone_or_sort and cq.zone_or_sort > 0 and rec.get("zone") is None:
            rec["zone"] = s.area_to_map.get(cq.zone_or_sort)
        rec["qtype"] = (
            cq.type or None
        )  # CMaNGOS quest Type: 1 group, 41 PvP, 62 raid, 81 dungeon, 84 escort
        rewards = {
            "money": cq.reward_money or None,
            "items": [list(x) for x in cq.reward_items] or None,
            "choices": [list(x) for x in cq.choice_items] or None,
            # 1.12 has no XP column: at level 60 a quest pays its XP as money, 6 copper per 10 XP
            # (Kobold Camp Cleanup 102 copper -> 170 XP); rounded to the client's step of 5
            "xp": quest_xp(cq.reward_money_max_level),
            "rep": [list(x) for x in cq.reward_rep] or None,
            "spell": cq.reward_spell,
            "spellName": clean_name(s.cm_spell_names.get(cq.reward_spell))
            if cq.reward_spell
            else None,
            "src": "classic",
        }
        rec["rewards"] = rewards
        rec["requiredItems"] = [list(x) for x in cq.required_items] or None
        if cq.details or cq.objectives or cq.offer_reward_text or cq.request_items_text:
            # quest texts live in the text pack (data.md), labelled classic
            world.add(
                "questText",
                cq.id,
                {
                    "details": cq.details,
                    "objectives": cq.objectives,
                    "offer": cq.offer_reward_text,
                    "progress": cq.request_items_text,
                    "src": "classic",
                },
            )
        _set_if_missing(rec, "src", "classic")


# ---------------------------------------------------------------------------------------------
# Items, recipes, loot
# ---------------------------------------------------------------------------------------------


def merge_items(world: World, s: Sources) -> None:
    for it in s.cm_items:
        rec = _rec(world, "item", it.id)
        rec["name"] = clean_name(it.name)
        rec["quality"] = it.quality
        rec["level"] = it.item_level
        rec["reqLevel"] = it.required_level
        rec["class"] = it.item_class
        rec["subclass"] = it.item_subclass
        rec["sell"] = it.sell_price
        rec["buy"] = it.buy_price
        rec["stack"] = it.stackable
        rec["src"] = "classic"
    for item_id, name in s.fdb_names.items():
        if foreverdb.is_old(name):
            continue
        rec = _rec(world, "item", item_id)
        if rec.get("name") is None:
            rec["name"] = clean_name(name)
            rec["src"] = "forever"
    for facts in s.fdb_items:
        rec = _rec(world, "item", facts.id)
        _set_if_missing(rec, "src", "forever")
        if facts.new_in_forever:
            rec["foreverNew"] = True
            rec["src"] = "forever"
        if facts.changed_in_forever:
            rec["foreverChanged"] = True
        if facts.made_by:
            rec["madeBy"] = [facts.made_by.profession, facts.made_by.skill]
        if facts.quest:
            rec["questItem"] = True
    # Classic loot: drops per item (top N) and loot per npc/object
    by_item: dict[int, list] = {}
    by_entry: dict[tuple[str, int], list] = {}
    for row in s.cm_loot:
        if row.item_id is None or row.kind == "reference":
            continue
        ref = f"{'npc' if row.kind == 'creature' else 'object'}:{row.entry}"
        by_item.setdefault(row.item_id, []).append([ref, round(row.chance_pct, 2), row.quest_drop])
        by_entry.setdefault((row.kind, row.entry), []).append(
            [row.item_id, round(row.chance_pct, 2)]
        )
    for item_id, drops in by_item.items():
        rec = world.get("item", item_id)
        if rec is None:
            continue
        drops.sort(key=lambda d: (-d[1], d[0]))
        rec["drops"] = drops[:MAX_DROPS_PER_ITEM]
        rec["dropsSrc"] = "classic"
    for (kind, entry), loot in by_entry.items():
        rec = world.get("npc" if kind == "creature" else "object", entry)
        if rec is None:
            continue
        loot.sort(key=lambda d: (-d[1], d[0]))
        rec["loot"] = loot[:MAX_LOOT_PER_NPC]
        rec["lootSrc"] = "classic"
    for r in s.fdb_recipes:
        rec = _rec(world, "recipe", r.spell_id)
        rec["name"] = clean_name(r.name)
        rec["profession"] = r.profession
        rec["skill"] = r.skill
        rec["item"] = r.item_id
        rec["count"] = r.count
        rec["reagents"] = [list(x) for x in r.reagents] or None
        rec["source"] = r.source_kind
        rec["sourceItem"] = r.source_item_id
        rec["foreverNew"] = True if r.new_in_forever else None
        rec["src"] = "forever"


# ---------------------------------------------------------------------------------------------
# Retail sources: AllTheThings (quests, places) and ItemDB (names, item facts, places)
# ---------------------------------------------------------------------------------------------

# Race ids per faction on retail. Race masks are bit i-1 for race id i, and the Lua `bit` library
# and the double-precision numbers of Lua 5.1 stop at 32 bits, so races with an id above 32
# (Dark Iron Dwarf 34, Vulpera 35, Mag'har 36, Mechagnome 37, Dracthyr 52/70, Earthen 84/85,
# Haranir 86/91) cannot be in the mask; a quest limited to such races keeps no race gate and the
# build report counts them (data.md "Retail data").
RETAIL_ALLIANCE_RACES = (1, 3, 4, 7, 11, 22, 25, 29, 30, 32)
RETAIL_HORDE_RACES = (2, 5, 6, 8, 9, 10, 24, 26, 27, 28, 31)
MAX_MASK_BIT = 32
ATT_UNOBTAINABLE = {1: "AllTheThings: never implemented", 2: "AllTheThings: removed from the game"}
NODE_KINDS = {"Herbalism": "herb", "Mining": "ore", "Fishing": "fish"}


def id_mask(ids) -> tuple[int, int]:
    """(bitmask of the ids within 32 bits, number of ids that do not fit)."""
    mask, lost = 0, 0
    for i in ids:
        if 1 <= i <= MAX_MASK_BIT:
            mask |= 1 << (i - 1)
        else:
            lost += 1
    return mask, lost


def faction_mask(faction: str | None) -> int:
    if faction == "A":
        return id_mask(RETAIL_ALLIANCE_RACES)[0]
    if faction == "H":
        return id_mask(RETAIL_HORDE_RACES)[0]
    return 0


def _place_rows(places, src: str) -> list[list]:
    return [[p.ui_map_id, round(p.x, 4), round(p.y, 4), src] for p in places]


def merge_att_quests(world: World, s: Sources) -> None:
    """AllTheThings quests: places, givers, gates, chains, flags; no names (the client has them).
    Entries ATT marks never implemented or removed are dropped with that reason."""
    att = s.att
    if att is None:
        return
    races_lost = 0
    for quest_id, q in sorted(att.quests.items()):
        if q.unavailable in ATT_UNOBTAINABLE:
            world.drop("quest", quest_id, ATT_UNOBTAINABLE[q.unavailable])
            continue
        placed = q.givers or q.places or q.zone is not None
        if not placed and world.get("quest", quest_id) is None:
            # hidden tracking quests and the like: nothing to show and no name to show it under
            world.drop("quest", quest_id, "AllTheThings: no giver, place or zone")
            continue
        rec = _rec(world, "quest", quest_id)
        _set_if_missing(rec, "minLevel", q.min_level)
        if q.races:
            mask, lost = id_mask(q.races)
            races_lost += lost
        else:
            mask = faction_mask(q.faction)
        if mask and rec.get("races") is None:
            rec["races"] = mask
        if q.classes and rec.get("classes") is None:
            rec["classes"] = id_mask(q.classes)[0] or None
        givers = [ref for ref in q.givers if ref.split(":")[0] in ("npc", "object", "item")]
        _set_if_missing(rec, "starts", givers or None)
        _set_if_missing(rec, "startPlaces", _place_rows(q.places, "att") or None)
        if q.pre:
            if q.pre_required is not None and q.pre_required < len(q.pre):
                _set_if_missing(rec, "preAny", list(q.pre))
            else:
                _set_if_missing(rec, "pre", list(q.pre))
        _set_if_missing(rec, "excl", list(q.alt) or None)
        flags = set(q.flags)
        if flags & {"daily", "weekly", "monthly", "yearly"}:
            flags.add("repeatable")
        if flags and rec.get("flags") is None:
            rec["flags"] = sorted(flags)
        zone = q.zone if q.zone is not None else (q.places[0].ui_map_id if q.places else None)
        _set_if_missing(rec, "zone", zone)
        if q.targets and rec.get("objectives") is None:
            rec["objectives"] = [["target", f"npc:{n}", i] for i, n in enumerate(q.targets)]
        if q.items and rec.get("requiredItems") is None:
            rec["requiredItems"] = [[item, None] for item in q.items]
        if q.rewards and rec.get("rewards") is None:
            # ATT lists the reward items without telling fixed from choice: one item counts as
            # given, several as a choice (data.md "Retail data")
            rows = [[item, None] for item in q.rewards]
            rec["rewards"] = (
                {"items": rows, "src": "att"} if len(rows) == 1 else {"choices": rows, "src": "att"}
            )
        _set_if_missing(rec, "src", "att")
    if races_lost:
        world.notes.append(
            f"AllTheThings: {races_lost} race restrictions on race ids above {MAX_MASK_BIT} "
            "cannot be expressed in a 32-bit mask and were not applied"
        )


def merge_att_places(world: World, s: Sources) -> None:
    """AllTheThings NPC and object places, object names, and the givers' places from the quests."""
    att = s.att
    if att is None:
        return
    for record_type, placed in (("npc", att.npcs), ("object", att.objects)):
        for record_id, p in sorted(placed.items()):
            if p.unavailable in ATT_UNOBTAINABLE:
                world.drop(record_type, record_id, ATT_UNOBTAINABLE[p.unavailable])
                continue
            rec = _rec(world, record_type, record_id)
            for pt in p.places:
                _add_spawn(rec, Spawn(pt.ui_map_id, pt.x, pt.y, "att"))
            if record_type == "npc":
                _set_if_missing(rec, "faction", p.faction)
            if not p.places:  # with places, the zone is the first place's map (assign_zones)
                _set_if_missing(rec, "zone", p.zone)
            _set_if_missing(rec, "src", "att")
    for _, q in sorted(att.quests.items()):
        if q.unavailable in ATT_UNOBTAINABLE:
            continue
        for ref in q.givers:
            kind, _, raw = ref.partition(":")
            if kind not in ("npc", "object"):
                continue
            rec = _rec(world, kind, int(raw))
            for pt in q.places:
                _add_spawn(rec, Spawn(pt.ui_map_id, pt.x, pt.y, "att"))
            if kind == "npc" and "questgiver" not in (rec.get("flags") or []):
                rec["flags"] = [*(rec.get("flags") or []), "questgiver"]
            _set_if_missing(rec, "src", "att")
    for object_id, rec in world.records.get("object", {}).items():
        name = att.object_names.get(object_id)
        if name and rec.get("name") is None:
            rec["name"] = clean_name(name)


def merge_client_quest_titles(world: World, s: Sources) -> None:
    """The client's quest-task titles (clientdump QuestV2CliTask, D1) name the quests that have no
    name yet; the report counts how many quests stay without one (the client supplies those at
    runtime through Data.Names). A title for a quest the world does not hold adds nothing."""
    if not s.quest_titles:
        return
    quests = world.records.get("quest", {})
    named = 0
    for quest_id, rec in quests.items():
        if rec.get("name") is None:
            title = clean_name(s.quest_titles.get(quest_id))
            if title:
                rec["name"] = title
                named += 1
    unnamed = sum(1 for rec in quests.values() if rec.get("name") is None)
    world.notes.append(
        f"QuestV2CliTask: {named} quests named from the client's task table, "
        f"{unnamed} of {len(quests)} without a name (the client supplies those at runtime)"
    )


def merge_itemdb_places(world: World, s: Sources) -> None:
    """ItemDB places: creature and object names, sides and spawns (from the TrinityCore world
    database, labelled ``tdb``); objects with a gathering profession become nodes."""
    idb = s.idb
    if idb is None:
        return
    yields: dict[str, list[int]] = {}  # entity key -> item ids it yields, in file order
    for item_id, sources in sorted(idb.places.items.items()):
        for src in sources:
            if src.kind in ("object", "drop"):
                yields.setdefault(src.entity, []).append(item_id)
    for key, e in sorted(idb.places.entities.items()):
        if e.kind == "object" and e.profession in NODE_KINDS:
            rec = _rec(world, "node", e.id)
            _set_if_missing(rec, "name", clean_name(e.name))
            rec["kind"] = NODE_KINDS[e.profession]
            rec["profession"] = e.profession
            items = yields.get(key) or []
            _set_if_missing(rec, "item", items[0] if items else None)
        else:
            rec = _rec(world, e.kind, e.id)
            _set_if_missing(rec, "name", clean_name(e.name))
            if e.kind == "npc" and e.side in ("A", "H"):
                _set_if_missing(rec, "faction", e.side)
        for place in e.places:
            for x, y in place.points:
                _add_spawn(rec, Spawn(place.ui_map_id, x, y, "tdb"))
        _set_if_missing(rec, "src", "tdb")


def merge_itemdb_items(world: World, s: Sources) -> None:
    """ItemDB names and facts for every item something refers to (drops, vendors, nodes, quest
    rewards and quest items): the whole retail item list (176k names) does not fit the pack and
    the client knows the rest at runtime (data.md "Retail data"). Drops and vendor rows come from
    the places, labelled ``tdb``."""
    idb = s.idb
    if idb is None:
        return
    wanted: set[int] = set(idb.places.items)
    for rec in world.records.get("quest", {}).values():
        for row in (rec.get("rewards") or {}).get("items") or []:
            wanted.add(int(row[0]))
        for row in (rec.get("rewards") or {}).get("choices") or []:
            wanted.add(int(row[0]))
        for row in rec.get("requiredItems") or []:
            wanted.add(int(row[0]))
        for ref in rec.get("starts") or []:
            if ref.startswith("item:"):
                wanted.add(int(ref[5:]))
    for rec in world.records.get("node", {}).values():
        if rec.get("item"):
            wanted.add(int(rec["item"]))
    by_entry: dict[tuple[str, int], list] = {}
    for item_id in sorted(wanted):
        rec = _rec(world, "item", item_id)
        _set_if_missing(rec, "name", clean_name(idb.names.get(item_id)))
        core = idb.core.get(item_id)
        if core is not None:
            _set_if_missing(rec, "quality", core.quality)
            _set_if_missing(rec, "level", core.item_level)
            _set_if_missing(rec, "class", core.class_id)
            _set_if_missing(rec, "subclass", core.subclass_id)
        drops = []
        for src in idb.places.items.get(item_id) or []:
            entity = idb.places.entities.get(src.entity)
            if entity is None:
                continue
            if src.kind in ("drop", "object") and src.chance is not None:
                is_node = entity.kind == "object" and entity.profession in NODE_KINDS
                ref = f"{'node' if is_node else entity.kind}:{entity.id}"
                drops.append([ref, round(src.chance, 2), src.quest_only or None])
                by_entry.setdefault((entity.kind, entity.id), []).append(
                    [item_id, round(src.chance, 2)]
                )
            elif src.kind == "vendor" and entity.kind == "npc":
                npc = world.get("npc", entity.id)
                if npc is not None:
                    npc.setdefault("vendor", []).append([item_id, None, None, None, "tdb"])
                    if "vendor" not in (npc.get("flags") or []):
                        npc["flags"] = [*(npc.get("flags") or []), "vendor"]
        if drops and rec.get("drops") is None:
            drops.sort(key=lambda d: (-d[1], d[0]))
            rec["drops"] = drops[:MAX_DROPS_PER_ITEM]
            rec["dropsSrc"] = "tdb"
        _set_if_missing(rec, "src", "tdb")
    for (kind, entry), loot in by_entry.items():
        rec = world.get(kind, entry)
        if rec is None or rec.get("loot") is not None:
            continue
        loot.sort(key=lambda d: (-d[1], d[0]))
        rec["loot"] = loot[:MAX_LOOT_PER_NPC]
        rec["lootSrc"] = "tdb"


def merge_att_flightpaths(world: World, s: Sources) -> None:
    """A flight master without a place from the transform table takes AllTheThings' place."""
    att = s.att
    if att is None:
        return
    for node_id, fp in sorted(att.flightpaths.items()):
        rec = world.get("flightpath", node_id)
        if rec is None or rec.get("spawns") or not fp.places:
            continue
        for pt in fp.places:
            _add_spawn(rec, Spawn(pt.ui_map_id, pt.x, pt.y, "att"))


# ---------------------------------------------------------------------------------------------
# Gather nodes
# ---------------------------------------------------------------------------------------------


def merge_nodes(world: World, s: Sources) -> None:
    if not s.fdb_gather:
        return
    kinds, points, _zones = s.fdb_gather
    for k in kinds:
        rec = _rec(world, "node", k.id)
        rec["name"] = clean_name(k.name)
        rec["kind"] = k.profession
        rec["profession"] = k.profession
        rec["skill"] = k.skill
        rec["item"] = k.item_id
        rec["icon"] = k.icon_file_id
        rec["src"] = "forever"
    for p in points:
        rec = world.get("node", p.kind_id)
        if rec is None:
            world.drop("node", p.kind_id, "gather point of an unknown kind")
            continue
        _add_spawn(
            rec,
            pct_to_fraction(
                p.ui_map_id, p.x_pct, p.y_pct, "fdb" if p.src == "forever" else "classic"
            ),
        )


# ---------------------------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------------------------


ALLIANCE_RACES = 0b01001101  # Human, Dwarf, Night Elf, Gnome (bits 0, 2, 3, 6)
HORDE_RACES = 0b10110010  # Orc, Undead, Tauren, Troll (bits 1, 4, 5, 7)


def fix_loot_objectives(world: World) -> None:
    """Everything Quests encodes a loot objective by the NPC or object the item comes from
    (CLUCK!: "loot npc:233", Farmer Saldean, who sells the Special Chicken Feed). The objective is
    the item: the n-th loot objective takes the n-th required item (CMaNGOS ReqItemId), and the
    source moves to a fourth field so the page can still say where to get it."""
    for rec in world.records.get("quest", {}).values():
        objectives = rec.get("objectives")
        items = rec.get("requiredItems")
        if not objectives or not items:
            continue
        loot_index = 0
        for obj in objectives:
            if obj[0] != "loot":
                continue
            if loot_index < len(items) and items[loot_index][0]:
                target = obj[1]
                obj[1] = f"item:{items[loot_index][0]}"
                if target and target != obj[1] and len(obj) < 4:
                    obj.append(target)
            loot_index += 1


def zone_statistics(world: World) -> None:
    """Per zone: quests starting there for each faction and the level band (lo, hi, median)."""
    stats: dict[int, dict] = {}
    for rec in world.records.get("quest", {}).values():
        zone = rec.get("zone")
        if zone is None:
            continue
        st = stats.setdefault(zone, {"a": 0, "h": 0, "levels": []})
        races = rec.get("races") or 0
        if races == 0 or races & ALLIANCE_RACES:
            st["a"] += 1
        if races == 0 or races & HORDE_RACES:
            st["h"] += 1
        if rec.get("level") and not (set(rec.get("flags") or ()) & BAND_EXCLUDED_FLAGS):
            st["levels"].append(rec["level"])
    for zone, st in stats.items():
        rec = _rec(world, "zone", zone)
        rec["questsA"], rec["questsH"] = st["a"], st["h"]
        band = level_band(st["levels"])
        if band:
            rec["levelLo"], rec["levelHi"], rec["levelMed"] = band


def name_unnamed_zones(world: World, s: Sources) -> int:
    """Zones that quests or places name but the client's map table lacks get the retail table's
    name and type (`nameSrc` "retail"); without one they stay unnamed. Returns how many."""
    named = 0
    for zone_id, rec in world.records.get("zone", {}).items():
        if rec.get("name"):
            continue
        name = s.fallback_map_names.get(zone_id)
        if not name:
            continue
        rec["name"] = clean_name(name)
        rec["nameSrc"] = "retail"
        _set_if_missing(rec, "mapType", s.fallback_map_types.get(zone_id))
        named += 1
    if named:
        world.notes.append(f"{named} zones named from the retail map table (the client lacks them)")
    return named


def merge_flightpaths(world: World, s: Sources) -> None:
    """Flight masters from the client's TaxiNodes table (route.md): world yards per node, plus the
    map place through the transform table when the build has one (else the runtime converts).
    The place is the map the node's own name gives ("Tarren Mill, Hillsbrad": the place, then the
    zone) when that map contains the point, else the containing rectangle (coordinates.md)."""
    by_name = by_rect = 0
    for node in s.taxi:
        rec = _rec(world, "flightpath", node.id)
        rec["name"] = node.name
        rec["faction"] = node.faction
        rec["continent"] = node.continent
        rec["wx"] = node.wx
        rec["wy"] = node.wy
        rec["src"] = "client"
        hit = None
        if s.transforms:
            parts = node.name.split(",")
            hit = named_map(s.transforms, s.map_names, node.continent, node.wx, node.wy, parts)
            if hit is not None:
                by_name += 1
            else:
                hit = best_map(s.transforms, node.continent, node.wx, node.wy)
                if hit is not None:
                    by_rect += 1
        if hit is not None:
            ui_map_id, x, y = hit
            _add_spawn(rec, Spawn(ui_map_id, round(x, 4), round(y, 4), "client"))
        elif s.transforms:
            world.notes.append(
                f"flightpath {node.id} ({node.name}): no map contains ({node.wx}, {node.wy})"
            )
    if by_name or by_rect:
        world.notes.append(
            f"flightpaths placed: {by_name} on the map their name gives, "
            f"{by_rect} by the containing rectangle"
        )


# spawn sources that are places of the built client's own world (not converted Classic points)
FOREVER_SPAWN_SOURCES = {"eq", "fdb", "questie", "capture", "client", "config", "att", "tdb"}


MAX_CLASSIC_SPAWNS_PER_MAP = (
    12  # a common mob has hundreds of Classic points; the pack keeps a spread
)


def farthest_points(points: list, limit: int) -> list:
    """Up to `limit` points spread over the set (greedy farthest-point sampling, first kept)."""
    if len(points) <= limit:
        return list(points)
    chosen = [points[0]]
    rest = points[1:]
    while len(chosen) < limit and rest:
        best_i, best_d = 0, -1.0
        for i, pt in enumerate(rest):
            d = min((pt[1] - c[1]) ** 2 + (pt[2] - c[2]) ** 2 for c in chosen)
            if d > best_d:
                best_i, best_d = i, d
        chosen.append(rest.pop(best_i))
    return chosen


def prune_classic_spawns(world: World) -> None:
    """Classic places yield to Forever ones and are thinned (data.md): an NPC or object with a
    Forever place keeps no converted Classic point (it adds nothing and is wrong where the world
    changed);
    one with Classic places only keeps at most MAX_CLASSIC_SPAWNS_PER_MAP per map, spread by
    farthest-point sampling, labelled `classic`."""
    for record_type in ("npc", "object"):
        for record_id, rec in world.records.get(record_type, {}).items():
            spawns = rec.get("spawns") or []
            if not spawns:
                continue
            if any(s[3] in FOREVER_SPAWN_SOURCES for s in spawns if len(s) > 3):
                kept = [s for s in spawns if len(s) > 3 and s[3] in FOREVER_SPAWN_SOURCES]
                if len(kept) < len(spawns):
                    world.drop(
                        record_type, record_id, "classic spawn superseded by a Forever place"
                    )
                    rec["spawns"] = kept
                continue
            by_map: dict[int, list] = {}
            for s in spawns:
                by_map.setdefault(s[0], []).append(s)
            if all(len(v) <= MAX_CLASSIC_SPAWNS_PER_MAP for v in by_map.values()):
                continue
            thinned = []
            for ui_map_id in sorted(by_map):
                thinned.extend(farthest_points(by_map[ui_map_id], MAX_CLASSIC_SPAWNS_PER_MAP))
            world.drop(
                record_type,
                record_id,
                f"classic spawns thinned to {MAX_CLASSIC_SPAWNS_PER_MAP} per map",
            )
            rec["spawns"] = thinned


def build_world(s: Sources) -> World:
    world = World(client=s.client, build=s.build, sources=list(s.source_names))
    world.notes.extend(s.notes)
    world.area_to_map = dict(s.area_to_map)
    merge_zones(world, s)
    merge_creatures(world, s)
    merge_att_places(world, s)
    merge_itemdb_places(world, s)
    merge_vendors_and_trainers(world, s)
    merge_quests(world, s)
    merge_att_quests(world, s)
    merge_client_quest_titles(world, s)
    merge_items(world, s)
    merge_itemdb_items(world, s)
    merge_nodes(world, s)
    merge_flightpaths(world, s)
    merge_att_flightpaths(world, s)
    prune_classic_spawns(world)
    assign_zones(world)
    fix_loot_objectives(world)
    zone_statistics(world)
    name_unnamed_zones(world, s)
    for rows in world.records.values():
        for rec in rows.values():
            for key in [k for k, v in rec.items() if v is None]:
                del rec[key]
    return world
