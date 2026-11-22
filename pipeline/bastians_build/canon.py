"""The canonical model (data.md): merge every source into one World, with explicit precedence.

Precedence per field, highest first: own captures > the client's own tables for what the client
holds (items, recipes, quest lines and areas; ADR 0035) > Forever sources (Everything Quests,
ForeverDB where a player saw it) > ForeverDB converted places > QuestieDB > Classic (CMaNGOS).
Every point carries its ``src``; Classic values are labelled ``classic`` (CLAUDE.md §8); unknown
stays ``None``.
Classic world positions are placed through the transform table or dropped with a reason.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from itertools import pairwise
from typing import Any

from bastians_build.areas import AreaBlock, add_areas
from bastians_build.coords import (
    CAPITALS,
    CMANGOS_CONTINENT,
    Spawn,
    best_map,
    named_map,
    pct_to_fraction,
    place_world_point,
    world_to_map,
)
from bastians_build.internal import drop_internal
from bastians_build.model import World
from bastians_build.sources import cmangos, foreverdb, foreverdb_api
from bastians_build.sources.client_tables import ClientTables
from bastians_build.sources.clientdump import (
    WHOLE_WORLD,
    AreaRow,
    FloorArt,
    TaxiNode,
    TaxiPath,
    floor_for_point,
)
from bastians_build.sources.everything_quests import EverythingQuests
from bastians_build.sources.probe import Transform
from bastians_build.sources.questie import QuestGates
from bastians_build.sources.questiedb_store import Store, StoreQuest

# Map ids of the world graph's continents: Eastern Kingdoms, Kalimdor (ADR 0026), Zephras Isle
GRAPH_CONTINENTS = (0, 1, 2991)
# The zones Forever added: their rectangles overlap old zones, and no Classic point lies in them
# (06.11.2026: 234 NPC and 98 object points of Winterspring, Mulgore and the Badlands landed on
# Mount Hyjal, Shen'dralas and the Riverglades)
FOREVER_NEW_MAPS = frozenset({2482, 2548, 2652})
MAX_SPOTS_PER_MAP = 8  # objective spots kept per quest and map (EQ orders densest first)
MAX_DROPS_PER_ITEM = 20
SPOT_DROPPERS = 12  # droppers an item's spots come from, as the addon follows it (Steps.lua)
MAX_LOOT_PER_NPC = 30
# An item that reaches this many creatures and objects through shared loot lists
# (``reference_loot_template``) is a world drop: the item keeps the droppers' level band and their
# count instead of hundreds of droppers ("World drop: creatures level
# 20-25").
WORLD_DROP_MIN_DROPPERS = 25

# The NpcFlags tables live with their sources, one per flag family: ``cmangos.NPC_FLAGS`` (Classic
# 1.12 bits) ~~and ``tdb.NPC_FLAGS`` (retail family)~~ (the retail world database left the build
# 15.11.2026, ADR 0037). Never decode one source with another's.
# titles of quests the game never finished, as QuestieDB keeps them
NOT_A_QUEST = re.compile(r"NYI|DEPRECATED|UNUSED|\[PH\]|<TXT>|^zz", re.IGNORECASE)
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
    # what players saw in Forever (06.11.2026): places, XP, rewards, stock, trainers
    fdb_seen: dict[int, foreverdb.QuestSeen] = field(default_factory=dict)
    fdb_npc_names: dict[int, str] = field(default_factory=dict)
    fdb_triggers: dict[int, foreverdb.SeenPoint] = field(default_factory=dict)  # `qfArea`
    fdb_xp: dict[int, int] = field(default_factory=dict)
    fdb_guide: dict[int, foreverdb.GuideRewards] = field(default_factory=dict)
    fdb_sold: dict[int, list[foreverdb.SoldRow]] = field(default_factory=dict)
    fdb_trainers: frozenset[int] = frozenset()
    fdb_items: list[foreverdb.ItemFacts] = field(default_factory=list)
    fdb_names: dict[int, str] = field(default_factory=dict)
    fdb_dungeons: list[foreverdb.DungeonRow] = field(default_factory=list)
    fdb_dungeon_maps: list[foreverdb.DungeonMapRow] = field(default_factory=list)
    fdb_boss_creatures: foreverdb.BossCreatures | None = None  # Loot.lua (02.11.2026)
    # ForeverDB's API rows AHSync fetched (10.11.2026): places players saw, for gaps only
    fdb_api: foreverdb_api.ApiRows | None = None
    # the client's dungeon maps by instance (the retail client's UiMap tables, DG2c): the
    # floors' art
    floor_art: dict[int, list[FloorArt]] = field(default_factory=dict)
    cm_quests: list[cmangos.QuestRow] = field(default_factory=list)
    cm_creatures: list[dict] = field(default_factory=list)  # creature_template rows
    cm_objects: list[dict] = field(default_factory=list)  # gameobject_template rows
    cm_spawns: list[cmangos.SpawnRow] = field(default_factory=list)
    cm_vendors: list[cmangos.VendorRow] = field(default_factory=list)
    cm_trainers: list[cmangos.TrainerService] = field(default_factory=list)
    cm_loot: list[cmangos.LootRow] = field(default_factory=list)
    cm_items: list[cmangos.ItemRow] = field(default_factory=list)
    cm_disenchant: dict[int, list[list[Any]]] = field(default_factory=dict)
    cm_links: cmangos.Links | None = None  # what is made, held, skinned; the quests' points
    cm_spell_names: dict[int, str] = field(default_factory=dict)  # spell_template SpellName
    # the client's FactionTemplate as { id: (side, hostile) } (sources/tdb.faction_sides):
    # the side and hostility of CMaNGOS' creatures (guards and the danger, R26.5)
    cm_factions: dict[int, tuple[str | None, bool]] = field(default_factory=dict)
    area_to_map: dict[int, int] = field(default_factory=dict)
    questie: Store | None = None  # QuestieDB's baked store (Forever, 06.11.2026)
    taxi: list[TaxiNode] = field(default_factory=list)  # clientdump TaxiNodes (flight masters)
    # clientdump TaxiPath + TaxiPathNode: the flights as the client flies them (ADR 0026, W4)
    taxi_paths: list[TaxiPath] = field(default_factory=list)
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
    questie_gates: QuestGates | None = None  # the quests Questie hides on Forever (ADR 0051)
    # the subzones (data.md "Areas"): the navmesh files' area blocks, the client's AreaTable and
    # its UiMapAssignment's area -> uiMapIDs; `areas_note` says why a build has none
    area_blocks: list[AreaBlock] = field(default_factory=list)
    area_table: dict[int, AreaRow] = field(default_factory=dict)
    area_maps: dict[int, list[int]] = field(default_factory=dict)
    areas_note: str | None = None
    # the client's own data tables (ADR 0035, sources/client_tables): items, recipes, quest lines
    # and objective areas; None without the dumps
    client_tables: ClientTables | None = None


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


def merge_areas(world: World, s: Sources) -> None:
    """The subzones as `area` records (areas.py); without navmesh or AreaTable none, and the
    report says why (unknown, never guessed)."""
    if s.area_blocks and s.area_table:
        add_areas(world, s.area_blocks, s.area_table, s.transforms, s.area_maps)
    elif s.areas_note:
        world.notes.append(s.areas_note)


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
        services = cmangos.npc_services(row.get("NpcFlags"))
        rank = RANKS.get(int(row.get("Rank") or 0))
        if rank:
            services.append(rank)
        rec["flags"] = services or None
        rec["src"] = "classic"
        side, hostile = s.cm_factions.get(int(row.get("Faction") or 0), (None, None))
        _set_if_missing(rec, "faction", side)
        if hostile is not None:
            rec["hostile"] = hostile  # build-time only: no pack schema carries it
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
    for npc_id, name in s.fdb_npc_names.items():  # who players met on Forever's quests
        _set_if_missing(_rec(world, "npc", npc_id), "name", clean_name(name))
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
    frame = s.transforms
    if frame:
        frame = {k: v for k, v in frame.items() if k not in FOREVER_NEW_MAPS}
    for spawn in s.cm_spawns:
        record_type = "npc" if spawn.kind == "creature" else "object"
        if spawn.map_id not in CMANGOS_CONTINENT:
            world.drop(
                record_type, spawn.entry, "classic spawn on an instance map: not placed (L+)"
            )
            continue
        placed = place_world_point(
            frame,
            spawn.map_id,
            spawn.position_x,
            spawn.position_y,
            "classic",
            spawn.position_z,
            spawn.spawndist if (spawn.spawndist or 0) >= 1 else None,
            CAPITALS.get(s.client, ()),  # the city rule (data.md): Stormwind's bankers
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


def _questie_rows(places: dict, s: Sources) -> list[list]:
    """A QuestieDB row's places as spawn rows: its zones are AreaTable ids, its points map percent,
    a common mob's hundreds thinned as Classic ones are."""
    rows: list[list] = []
    for zone in sorted(places):
        ui_map = s.area_to_map.get(zone)
        if ui_map is None or not s.transforms or ui_map not in s.transforms:
            continue
        points = [
            [ui_map, round(x / 100, 4), round(y / 100, 4), "questie"] for x, y in places[zone]
        ]
        rows.extend(farthest_points(points, MAX_CLASSIC_SPAWNS_PER_MAP))
    return rows


def _add_rows(rec: dict, rows: list[list]) -> None:
    """Adds the places a record lacks: a point within a hundredth of the map of one it has is that
    one (Everything Quests names the same givers)."""
    spawns = rec.setdefault("spawns", [])
    for row in rows:
        near = any(
            s[0] == row[0] and abs(s[1] - row[1]) < 0.01 and abs(s[2] - row[2]) < 0.01
            for s in spawns
        )
        if not near:
            spawns.append(row)


def merge_questie_world(world: World, s: Sources) -> None:
    """The NPCs and objects CMaNGOS does not have, or has no place for (sources.md): QuestieDB's
    Forever build is the one source of the creatures of the zones Forever added. A Classic creature
    with a place is left alone: QuestieDB's row for it is the same CMaNGOS point."""
    store = s.questie
    if store is None:
        return
    classic = {int(row["Entry"]) for row in s.cm_creatures}
    for npc_id, npc in sorted(store.npcs.items()):
        rec = world.get("npc", npc_id)
        new = npc_id not in classic
        if not new and (rec is None or rec.get("spawns")):
            continue
        rows = _questie_rows(npc.places, s)
        if rec is None and not rows:
            continue
        rec = _rec(world, "npc", npc_id)
        _set_if_missing(rec, "name", clean_name(npc.name))
        _set_if_missing(rec, "subname", clean_name(npc.subname))
        if new:
            _set_if_missing(rec, "level", npc.level)
            if npc.level_max != npc.level:
                _set_if_missing(rec, "levelMax", npc.level_max)
            services = cmangos.npc_services(npc.npc_flags)
            rank = RANKS.get(npc.rank)
            if rank:
                services.append(rank)
            if services:  # over ForeverDB's guess from the title
                rec["flags"] = services
            side, hostile = s.cm_factions.get(int(npc.faction_template or 0), (None, None))
            friendly = npc.friendly if npc.friendly in ("A", "H") else side
            _set_if_missing(rec, "faction", friendly)
            if hostile is not None:
                rec["hostile"] = hostile
        _add_rows(rec, rows)
        _set_if_missing(rec, "src", "forever")
    classic = {int(row["entry"]) for row in s.cm_objects}
    for object_id, obj in sorted(store.objects.items()):
        rec = world.get("object", object_id)
        if object_id in classic and (rec is None or rec.get("spawns")):
            continue
        rows = _questie_rows(obj.places, s)
        if rec is None and not rows:
            continue
        rec = _rec(world, "object", object_id)
        _set_if_missing(rec, "name", clean_name(obj.name))
        if "mailbox" in (rec.get("name") or "").lower():
            _set_if_missing(rec, "kind", "mailbox")
        _add_rows(rec, rows)
        _set_if_missing(rec, "src", "forever")


def assign_zones(world: World) -> None:
    """Zone of an npc, object or node without one: the map of its first spawn."""
    for record_type in ("npc", "object", "node"):
        for rec in world.records.get(record_type, {}).values():
            spawns = rec.get("spawns")
            if spawns and rec.get("zone") is None:
                rec["zone"] = spawns[0][0]


def engine_offer(s: Sources, item_id: int) -> tuple[int, int | None] | None:
    """(the price, the stack it buys) of an item at a merchant as the engine holds it: the
    client's ItemSparse `BuyPrice` for its `VendorStackCount`, with the server's hotfixes
    (plan-data-quality.md rule 3). Measured 16.11.2026 against ForeverDB 0.62.1's merchant scans:
    of 1,768 items seen priced in Forever, the engine and Classic agreed on 1,374, and of those
    where they differ the engine was right for 307 and Classic for none; the stack was right for
    all 1,768. None when the client lacks the item or names no price (0: unknown, an item paid
    otherwise)."""
    it = s.client_tables.items.get(item_id) if s.client_tables else None
    if it is None or not it.buy or it.buy < 0:
        return None
    return it.buy, it.vendor_stack


def merge_vendors_and_trainers(world: World, s: Sources) -> None:
    prices = {it.id: (it.buy_price, it.stackable) for it in s.cm_items}
    for v in s.cm_vendors:
        rec = world.get("npc", v.npc_id)
        if rec is None:
            world.drop("npc", v.npc_id, "vendor list for an unknown npc")
            continue
        # the merchant buy price is for the vendor stack (CLAUDE.md §12): the engine knows both;
        # CMaNGOS' dump has no stack size. The row stays CMaNGOS' (who sells it); its sixth
        # field names where the price comes from when that is another source
        offer = engine_offer(s, v.item_id)
        if offer is not None:
            row = [v.item_id, offer[0], offer[1], v.max_count is not None, "classic", "client"]
        else:
            price, _stack = prices.get(v.item_id, (None, None))
            row = [v.item_id, price, None, v.max_count is not None, "classic"]
        rec.setdefault("vendor", []).append(row)
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
    # Forever's own stock where CMaNGOS has no list: new NPCs, and Classic ones it does not sell
    for npc_id, offers in s.fdb_sold.items():
        rec = world.get("npc", npc_id)
        if rec is None:
            world.drop("npc", npc_id, "ForeverDB stock for an unknown npc")
        elif not rec.get("vendor"):
            rec["vendor"] = [[o.item, o.price, o.stack, o.limited, "fdb"] for o in offers]
    # ForeverDB's trainers name what a title alone guessed as a vendor
    classic = {int(row["Entry"]) for row in s.cm_creatures}
    for npc_id in sorted(s.fdb_trainers):
        rec = world.get("npc", npc_id)
        if rec is None:
            continue
        flags = list(rec.get("flags") or [])
        if npc_id not in classic and "vendor" in flags and not rec.get("vendor"):
            flags.remove("vendor")
        if "trainer" not in flags:
            flags.append("trainer")
        rec["flags"] = flags


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
            rec["leads"] = q.leads or None
            rec["maxLevel"] = q.max_level
            rec["skill"] = list(q.skill) if q.skill else None
            rec["minRep"] = list(q.min_rep) if q.min_rep else None
            flags = sorted(q.categories)
            if q.gates and q.gates.repeatable and "repeatable" not in flags:
                flags.append("repeatable")
            rec["flags"] = flags or None
            rec["holiday"] = q.holiday
            zone = quest_start_zone(q.coord, start_points)
            if zone is not None:
                rec["zone"] = zone
            rec["objectives"] = [[o.kind, f"npc:{o.npc_id}", o.index] for o in q.objectives] or None
            # the same rows for the steps' resolver (steps.py), which groups them by number
            # before `fix_loot_objectives` pairs them with the items by row; a row names an
            # object where no creature has the id (build-time only: no pack schema carries it)
            rec["eqRows"] = [
                [o.kind, _eq_ref(world, o.kind, o.npc_id), o.index] for o in q.objectives
            ] or None
            spots: dict[int, list] = {}
            for p in q.spawns:
                lst = spots.setdefault(p.ui_map_id, [])
                if len(lst) < MAX_SPOTS_PER_MAP:
                    lst.append([round(p.x, 4), round(p.y, 4), p.kind, p.objective_mask or 0])
            rec["spots"] = {m: v for m, v in sorted(spots.items())} or None
            rec["spotsSrc"] = "eq" if spots else None  # the resolver's label (steps.py)
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


def _eq_ref(world: World, kind: str, entry: int) -> str:
    """Everything Quests packs one id per row: a creature, or the object of an `object` row; a
    `loot` row names who has the item, a creature unless only an object has that id."""
    if kind == "object" or (
        kind == "loot" and world.get("npc", entry) is None and world.get("object", entry)
    ):
        return f"object:{entry}"
    return f"npc:{entry}"


def _seen_rows(points) -> list[list]:
    return [[p.ui_map_id, round(p.x_pct / 100, 4), round(p.y_pct / 100, 4), "fdb"] for p in points]


def merge_fdb_quest_facts(world: World, s: Sources) -> None:
    """What players measured in Forever (ForeverDB): a quest's XP over the value derived from
    Classic money, its rewards where the guide marks them as seen in Forever, and where it was
    offered, handed in and advanced where no source named a place."""
    for quest_id, xp in s.fdb_xp.items():
        rec = world.get("quest", quest_id)
        if rec is not None:
            rec.setdefault("rewards", {"src": "forever"})
            if rec["rewards"] is None:
                rec["rewards"] = {"src": "forever"}
            rec["rewards"]["xp"] = xp
    for quest_id, g in s.fdb_guide.items():
        rec = world.get("quest", quest_id)
        if rec is None:
            continue
        rewards = rec.get("rewards") or {"src": "forever"}
        if g.money:
            rewards["money"] = g.money
        if g.items:
            rewards["items"] = [list(x) for x in g.items]
        if g.choices:
            rewards["choices"] = [list(x) for x in g.choices]
        rec["rewards"] = rewards
    for quest_id, seen in s.fdb_seen.items():
        rec = world.get("quest", quest_id)
        if rec is None:
            continue
        if not rec.get("startPlaces"):
            rec["startPlaces"] = _seen_rows(seen.starts) or None
        if not rec.get("endPlaces"):
            rec["endPlaces"] = _seen_rows(seen.ends) or None
        # every objective players saw advance, for the steps' resolver (build-time only)
        rec["seenSpots"] = {
            number: [row[:3] for row in _seen_rows(points)]
            for number, points in sorted(seen.objectives.items())
            if points
        } or None
        if not rec.get("spots"):
            by_map: dict[int, list] = {}
            for number, points in seen.objectives.items():
                for p in points:
                    rows = by_map.setdefault(p.ui_map_id, [])
                    if len(rows) < MAX_SPOTS_PER_MAP:
                        mask = 1 << (number - 1)
                        rows.append(
                            [round(p.x_pct / 100, 4), round(p.y_pct / 100, 4), "area", mask]
                        )
            rec["spots"] = dict(sorted(by_map.items())) or None
            rec["spotsSrc"] = "fdb" if by_map else None


def merge_fdb_api(world: World, s: Sources) -> None:
    """ForeverDB's API (data.md "ForeverDB's API fills gaps"): where players saw a quest's giver,
    its hand-in and a vendor. It fills gaps only, after every other source: a quest without a
    start or end place gets the seen one, a giver or vendor without any place gets its spot, and
    a vendor no source knows becomes a record. Nothing that has a value is changed."""
    api = s.fdb_api
    if api is None:
        return
    filled = {"start": 0, "end": 0, "giver": 0, "vendor": 0, "new": 0}
    for p in api.quest_places:
        rec = world.get("quest", p.quest_id)
        if rec is None:
            continue
        row = pct_to_fraction(p.ui_map_id, p.x_pct, p.y_pct, "fdb").row()
        key = "startPlaces" if p.role == "start" else "endPlaces"
        if not rec.get(key):
            rec[key] = [row]
            filled[p.role] += 1
        _set_if_missing(rec, "starts" if p.role == "start" else "ends", [f"{p.kind}:{p.source_id}"])
        who = world.get(p.kind, p.source_id)
        if who is not None and not who.get("spawns"):
            who["spawns"] = [row]
            filled["giver"] += 1
    for v in api.vendors:
        rec = world.get("npc", v.id)
        row = pct_to_fraction(v.ui_map_id, v.x_pct, v.y_pct, "fdb").row()
        if rec is None:
            name = clean_name(v.name)
            if not name or localized_name(name):
                continue  # a vendor needs a name players can read in English
            world.add(
                "npc",
                v.id,
                {
                    "name": name,
                    "subname": clean_name(v.title),
                    "faction": v.side,
                    "flags": ["vendor"],
                    "spawns": [row],
                    "src": "forever",
                },
            )
            filled["new"] += 1
        elif not rec.get("spawns"):
            rec["spawns"] = [row]
            filled["vendor"] += 1
    world.notes.append(
        "ForeverDB API"
        + (f" (build {api.build})" if api.build else "")
        + f": {len(api.quest_places)} seen quest places and {len(api.vendors)} seen vendors read; "
        f"filled {filled['start']} quest starts, {filled['end']} hand-ins, "
        f"{filled['giver']} givers' places, {filled['vendor']} vendors' places, "
        f"{filled['new']} vendors no other source had"
    )
    world.notes.extend(api.notes)


def _places_of(world: World, refs: list[str], limit: int) -> list[list]:
    """Up to `limit` places of the things named, as a quest's place rows."""
    out: list[list] = []
    for ref in refs:
        kind, _, entity = ref.partition(":")
        rec = world.get(kind, int(entity))
        for row in (rec or {}).get("spawns") or ():
            if len(out) < limit:
                out.append(list(row[:4]))
    return out


def _questie_refs(npcs: tuple[int, ...], objects: tuple[int, ...]) -> list[str]:
    return [f"npc:{i}" for i in npcs] + [f"object:{i}" for i in objects]


def _questie_spots(world: World, q: StoreQuest) -> dict[int, list]:
    """Where a quest's creatures and objects stand, a spread of them per map, by objective bit."""
    rows: dict[int, list] = {}
    for kind, record_type, ids in (("slay", "npc", q.creatures), ("object", "object", q.objects)):
        # the bit counts within the kind, as Everything Quests' do: the addon reads both alike
        for bit, entity in enumerate(ids):
            rec = world.get(record_type, entity)
            for row in (rec or {}).get("spawns") or ():
                rows.setdefault(row[0], []).append([row[0], row[1], row[2], kind, 1 << bit])
    return {
        ui_map: [r[1:] for r in farthest_points(rows[ui_map], MAX_SPOTS_PER_MAP)]
        for ui_map in sorted(rows)
    }


def quest_start_zone(coord, start_points: list) -> int | None:
    """The map a quest starts on (data.md, the zone pages' "quests starting there"): the giver's.
    Everything Quests' coordinate is where the quest is advanced, for many an objective's spawn
    (Redridge Goulash: Hillsbrad Foothills, its giver in Lakeshire; 1134 of 4488 quests differed,
    09.11.2026), so it decides only among a giver's several maps, or when nobody is placed."""
    maps = [p[0] for p in start_points]
    if coord is not None and (not maps or coord.ui_map_id in maps):
        return coord.ui_map_id
    return maps[0] if maps else None


def _new_questie_quest(world: World, s: Sources, q: StoreQuest, classic: set[int]) -> dict | None:
    """A quest no other source has, when a player can be sent to it: a real title and a starter
    with a place. QuestieDB also keeps quests the game never finished."""
    title = clean_name(q.name)
    refs = _questie_refs(q.starts_npc, q.starts_object)
    places = _places_of(world, refs, 3)
    if not title or NOT_A_QUEST.search(title) or not places:
        return None
    rec = _rec(world, "quest", q.id)
    rec["name"] = title
    rec["level"] = q.level
    rec["minLevel"] = q.min_level
    rec["races"] = q.races
    rec["classes"] = q.classes
    rec["starts"] = refs
    rec["startPlaces"] = places
    rec["pre"] = list(q.pre_all) or None
    rec["preAny"] = list(q.pre_any) or None
    rec["excl"] = list(q.exclusive) or None
    rec["zone"] = places[0][0]
    if q.id not in classic:
        rec["foreverOnly"] = True
    rec["src"] = "forever"
    return rec


def merge_questie_quests(world: World, s: Sources) -> None:
    """What Everything Quests, ForeverDB and CMaNGOS leave open, from QuestieDB (sources.md): who
    takes a quest in, what it asks for and where, its objective line and its reputation. Runs after
    them: it fills gaps and replaces nothing."""
    store = s.questie
    if store is None:
        return
    classic = {q.id for q in s.cm_quests}
    for quest_id, q in sorted(store.quests.items()):
        rec = world.get("quest", quest_id) or _new_questie_quest(world, s, q, classic)
        if rec is None:
            world.drop("quest", quest_id, "QuestieDB only, no title or no placed starter")
            continue
        ends = _questie_refs(q.ends_npc, q.ends_object)
        _set_if_missing(rec, "ends", ends or None)
        if not rec.get("endPlaces"):
            rec["endPlaces"] = _places_of(world, rec.get("ends") or [], 3) or None
        if not rec.get("objectives"):
            rows = [["slay", f"npc:{i}"] for i in q.creatures]
            rows += [["object", f"object:{i}"] for i in q.objects]
            rows += [["loot", f"item:{i}"] for i in q.items]
            rec["objectives"] = rows or None
        if not rec.get("spots"):
            rec["spots"] = _questie_spots(world, q) or None
            rec["spotsSrc"] = "spawns" if rec["spots"] else None  # the subjects' own places
        if q.rep:
            rewards = rec.get("rewards") or {"src": "forever"}
            _set_if_missing(rewards, "rep", [list(r) for r in q.rep])
            rec["rewards"] = rewards
        _set_if_missing(rec, "objectiveText", clean_name(q.objective_text))


def merge_questie_items(world: World, s: Sources) -> int:
    """Who has an item no loot table knows (data.md "Links and steps", package QD1): QuestieDB's
    item rows name the creatures and objects, without a chance, which stays unknown. Mirror Lake's
    water sample comes from the Mirror Lake Waterwall, and nothing else said so. It fills a gap
    and replaces nothing: an item with drops or a world drop keeps them. Only droppers the world
    knows, those with a place first (the addon follows the first ones), then creatures before
    objects, then by id. Labelled `classic` for an item CMaNGOS has (the store's rows of those
    are Classic knowledge), `questie` for one of Forever's own. The link is stored at both ends
    (links.py, the edge `drops`): each of those droppers lists the item in its `loot`, without a
    chance, where its list has room. Returns how many items it filled."""
    store = s.questie
    if store is None or not store.items:
        return 0
    classic = {it.id for it in s.cm_items}
    filled = unknown = 0
    for item_id, row in sorted(store.items.items()):
        rec = world.get("item", item_id)
        if rec is None or rec.get("drops") is not None or rec.get("worldDrop") is not None:
            continue
        found = []
        for order, (kind, ids) in enumerate((("npc", row.npc_drops), ("object", row.object_drops))):
            for entity in sorted(set(ids)):
                dropper = world.get(kind, entity)
                if dropper is None:
                    unknown += 1
                else:
                    found.append((not dropper.get("spawns"), order, entity, f"{kind}:{entity}"))
        if not found:
            continue
        rec["drops"] = [[ref] for *_, ref in sorted(found)[:MAX_DROPS_PER_ITEM]]
        rec["dropsSrc"] = "classic" if item_id in classic else "questie"
        filled += 1
        for (ref,) in rec["drops"]:
            kind, _, raw = ref.partition(":")
            dropper = world.get(kind, int(raw))
            loot = dropper.get("loot") or []
            if len(loot) < MAX_LOOT_PER_NPC and all(row[0] != item_id for row in loot):
                dropper["loot"] = [*loot, [item_id]]
                _set_if_missing(dropper, "lootSrc", rec["dropsSrc"])
    if filled:
        world.notes.append(
            f"{filled} items without a loot table got their droppers from QuestieDB's item rows "
            f"(no chance); {unknown} droppers it names are not in the world"
        )
    return filled


def merge_objective_texts(world: World) -> None:
    """A quest's objective line into the text pack where CMaNGOS has no text for it: Forever's own
    quests have no text at all otherwise (06.11.2026: 0 of the 371 in the pack)."""
    for quest_id, rec in world.records.get("quest", {}).items():
        line = rec.get("objectiveText")
        if not line:
            continue
        text = world.get("questText", quest_id)
        if text is None:
            world.add("questText", quest_id, {"objectives": line, "src": "forever"})
        elif not text.get("objectives"):
            text["objectives"] = line


# ---------------------------------------------------------------------------------------------
# Items, recipes, loot
# ---------------------------------------------------------------------------------------------


def _either(a: float, b: float) -> float:
    """Percent that at least one of two independent rolls drops the item."""
    return 100.0 * (1.0 - (1.0 - a / 100.0) * (1.0 - b / 100.0))


def reference_items(loot: list[cmangos.LootRow]) -> dict[int, list[tuple[int, float, bool]]]:
    """Each shared loot list's items, nested lists expanded: ``{list: [(item, percent, quest)]}``,
    the percent of one roll of the list; a list that refers to itself again is cut."""
    lists: dict[int, list[cmangos.LootRow]] = {}
    for row in loot:
        if row.kind == "reference":
            lists.setdefault(row.entry, []).append(row)
    done: dict[int, list[tuple[int, float, bool]]] = {}

    def expand(list_id: int, seen: frozenset[int]) -> list[tuple[int, float, bool]]:
        if list_id in done:
            return done[list_id]
        if list_id in seen:
            return []
        items: dict[int, tuple[float, bool]] = {}

        def add(item: int, chance: float, quest: bool) -> None:
            old = items.get(item)
            items[item] = (_either(old[0], chance), old[1] and quest) if old else (chance, quest)

        for row in lists.get(list_id, []):
            if row.reference_id is not None:
                factor = (row.chance_pct or 100.0) / 100.0
                for item, chance, quest in expand(row.reference_id, seen | {list_id}):
                    add(item, chance * factor, quest)
            elif row.item_id is not None:
                add(row.item_id, row.chance_pct, row.quest_drop)
        done[list_id] = [(i, c, q) for i, (c, q) in sorted(items.items())]
        return done[list_id]

    for list_id in sorted(lists):
        expand(list_id, frozenset())
    return done


def _level_band(world: World, droppers: set[tuple[str, int]]) -> tuple[int | None, int | None]:
    """The lowest and highest level of the creatures among the droppers (objects have none)."""
    lows, highs = [], []
    for kind, entry in droppers:
        npc = world.get("npc", entry) if kind == "creature" else None
        if npc and npc.get("level") is not None:
            lows.append(int(npc["level"]))
            highs.append(int(npc.get("levelMax") or npc["level"]))
    return (min(lows), max(highs)) if lows else (None, None)


def merge_loot(world: World, rows: list[cmangos.LootRow], src: str) -> None:
    """Drops per item (top N), loot per npc/object and world drops from loot rows. The shared
    lists a creature or object rolls are expanded: an item few reach that way joins their drops,
    an item many reach is a world drop (WORLD_DROP_MIN_DROPPERS) with the droppers' level band.
    Drops and loot already set by another source stay. (~~`item_record`, `keep` and `levels`~~:
    the retail loot's hooks, out 15.11.2026.)"""
    by_item: dict[int, list] = {}
    by_entry: dict[tuple[str, int], list] = {}
    shared = reference_items(rows)
    via_lists: dict[int, dict[tuple[str, int], tuple[float, bool]]] = {}
    for row in rows:
        if row.kind == "reference":
            continue
        if row.reference_id is not None:
            factor = (row.chance_pct or 100.0) / 100.0
            for item, chance, quest in shared.get(row.reference_id, []):
                droppers = via_lists.setdefault(item, {})
                key = (row.kind, row.entry)
                old = droppers.get(key)
                droppers[key] = (
                    (_either(old[0], chance * factor), old[1] and quest)
                    if old
                    else (chance * factor, quest)
                )
            continue
        if row.item_id is None:
            continue
        ref = f"{'npc' if row.kind == 'creature' else 'object'}:{row.entry}"
        by_item.setdefault(row.item_id, []).append([ref, round(row.chance_pct, 2), row.quest_drop])
        by_entry.setdefault((row.kind, row.entry), []).append(
            [row.item_id, round(row.chance_pct, 2)]
        )

    for item_id, droppers in sorted(via_lists.items()):
        if len(droppers) >= WORLD_DROP_MIN_DROPPERS:
            rec = world.get("item", item_id)
            if rec is not None and rec.get("worldDrop") is None:
                lo, hi = _level_band(world, set(droppers))
                rec["worldDrop"] = [lo, hi, len(droppers)]
            continue
        for (kind, entry), (chance, quest) in sorted(droppers.items()):
            ref = f"{'npc' if kind == 'creature' else 'object'}:{entry}"
            by_item.setdefault(item_id, []).append([ref, round(chance, 2), quest])
            by_entry.setdefault((kind, entry), []).append([item_id, round(chance, 2)])
    for item_id, drops in by_item.items():
        rec = world.get("item", item_id)
        if rec is None or rec.get("drops") is not None:
            continue
        drops.sort(key=lambda d: (-d[1], d[0]))
        rec["drops"] = drops[:MAX_DROPS_PER_ITEM]
        rec["dropsSrc"] = src
    for (kind, entry), loot in by_entry.items():
        rec = world.get("npc" if kind == "creature" else "object", entry)
        if rec is None or rec.get("loot") is not None:
            continue
        loot.sort(key=lambda d: (-d[1], d[0]))
        rec["loot"] = loot[:MAX_LOOT_PER_NPC]
        rec["lootSrc"] = src


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
        if it.disenchant_id in s.cm_disenchant:
            rec["disenchant"] = it.disenchant_id  # the list's id: a few lists serve every item
    # the disenchant lists the items name
    used = {it.disenchant_id for it in s.cm_items if it.disenchant_id in s.cm_disenchant}
    for list_id in sorted(used):
        rec = _rec(world, "disenchant", list_id)
        rec["loot"] = s.cm_disenchant[list_id]
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
    # Classic loot: drops per item, loot per npc/object, world drops (merge_loot)
    merge_loot(world, s.cm_loot, "classic")
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


# The professions' skill lines (SkillLine.db2 ids, the same on both clients) as Forever's recipe
# files name them.
PROFESSION_SKILL_LINES = {
    164: "Blacksmithing",
    165: "Leatherworking",
    171: "Alchemy",
    182: "Herbalism",
    185: "Cooking",
    186: "Mining",
    197: "Tailoring",
    202: "Engineering",
    333: "Enchanting",
    356: "Fishing",
    393: "Skinning",
    755: "Jewelcrafting",
    773: "Inscription",
    129: "First Aid",
    794: "Archaeology",
}


def merge_questie_gates(world: World, s: Sources) -> None:
    """Questie's hidden quests as flags (ADR 0051): `absent`, not in the game, and `dormant`, a
    one-time world event. A quest ForeverDB saw players take keeps no flag: seen beats listed.
    Questie's event quests are hidden until their event runs: they get the event as `holiday`
    where no source named it, and never `absent`, or they would stay away during the event too."""
    gates = s.questie_gates
    if gates is None:
        return
    for quest_id, event in sorted(gates.events.items()):
        rec = world.get("quest", quest_id)
        if rec is not None:
            _set_if_missing(rec, "holiday", event)
    for flag, ids in (("absent", gates.absent), ("dormant", gates.dormant)):
        for quest_id in sorted(ids):
            rec = world.get("quest", quest_id)
            if rec is None or rec.get("seenBy") or (flag == "absent" and rec.get("holiday")):
                continue
            rec["flags"] = sorted({*(rec.get("flags") or []), flag})


def _needs(world: World, quest_id: int, target: int) -> bool:
    """Whether `quest_id` already waits for `target`, through any length of `pre` and `preAny`."""
    seen: set[int] = set()
    stack = [quest_id]
    while stack:
        current = stack.pop()
        if current == target:
            return True
        if current in seen:
            continue
        seen.add(current)
        rec = world.get("quest", current)
        if rec is not None:
            stack += [*(rec.get("pre") or []), *(rec.get("preAny") or [])]
    return False


def _masks_meet(a: int | None, b: int | None) -> bool:
    """Two race or class masks can hold the same character; an unknown mask says nothing."""
    return not a or not b or bool(a & b)


def link_breadcrumbs(world: World) -> None:
    """`crumbs` on a quest: the breadcrumbs whose `leads` name it (Everything Quests), so the
    addon sees without decoding every record that the quest is not offered while one of them is in
    the log, and that its `excl` naming one of them is the breadcrumb's link, not a branch."""
    quests = world.records.get("quest", {})
    crumbs: dict[int, list[int]] = {}
    for crumb_id, rec in sorted(quests.items()):
        for target in rec.get("leads") or []:
            if target in quests and target != crumb_id:
                crumbs.setdefault(target, []).append(crumb_id)
    for target, ids in crumbs.items():
        quests[target]["crumbs"] = ids
    if crumbs:
        world.notes.append(
            f"breadcrumbs: {sum(len(v) for v in crumbs.values())} lead to {len(crumbs)} quests"
        )


def merge_fdb_previous_quests(world: World, s: Sources) -> None:
    """The quest players were seen to need first (ForeverDB's column since 0.57.14) joins `pre`, as
    in ForeverDB's own addon. Never where it could lock the quest for good: one already named by
    the sources, or excluding it, a breadcrumb to it (a player may skip it), one no character of
    this quest can take, or a cycle."""
    added = refused = 0
    for fq in s.fdb_quests:
        previous = fq.confirmed_previous
        rec = world.get("quest", fq.id)
        other = world.get("quest", previous) if previous else None
        if rec is None or other is None:
            continue
        if previous in (rec.get("pre") or []) or previous in (rec.get("preAny") or []):
            continue
        if (
            previous == fq.id
            or previous in (rec.get("excl") or [])
            or fq.id in (other.get("leads") or [])
            or not _masks_meet(rec.get("races"), other.get("races"))
            or not _masks_meet(rec.get("classes"), other.get("classes"))
            or _needs(world, previous, fq.id)
        ):
            refused += 1
            continue
        rec["pre"] = [*(rec.get("pre") or []), previous]
        added += 1
    if added or refused:
        world.notes.append(
            f"ForeverDB previous quests: {added} joined `pre`, {refused} left out "
            "(would lock the quest)"
        )


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


def derive_dungeon_quests(world: World, s: Sources) -> int:
    """Dungeon quests by where their targets live (data.md "Dungeons", catalog review A2.1,
    07.11.2026): a quest ForeverDB did not confirm gets `dungeon` = the one instance that holds
    every spawn of a kill or object objective's target, or every known dropper (CMaNGOS creature
    and object loot, shared lists expanded) of a loot objective's or required item; targets outside
    any instance are allowed beside it, targets in two instances make no answer. Labelled
    `dungeonSrc` "classic" (ForeverDB's rows carry "forever"). Returns how many were derived."""
    instances = set(world.records.get("dungeon", {}))
    if not instances or not s.cm_spawns:
        return 0
    maps_of: dict[tuple[str, int], set[int]] = {}
    for sp in s.cm_spawns:
        kind = "npc" if sp.kind == "creature" else "object"
        maps_of.setdefault((kind, sp.entry), set()).add(sp.map_id)

    def only_inside(kind: str, entry: int) -> int | None:
        maps = maps_of.get((kind, entry))
        if not maps or not maps <= instances or len(maps) != 1:
            return None
        return next(iter(maps))

    droppers: dict[int, set[tuple[str, int]]] = {}
    shared = reference_items(s.cm_loot)
    for row in s.cm_loot:
        if row.kind == "reference":
            continue
        kind = "npc" if row.kind == "creature" else "object"
        items = [x[0] for x in shared.get(row.reference_id, [])] if row.reference_id else []
        if row.item_id is not None:
            items.append(row.item_id)
        for item in items:
            droppers.setdefault(item, set()).add((kind, row.entry))

    def item_dungeon(item: int) -> int | None:
        where = set()
        for kind, entry in droppers.get(item, ()):
            inside = only_inside(kind, entry)
            if inside is None:
                return None  # a dropper outside, or in several instances: no dungeon item
            where.add(inside)
        return next(iter(where)) if len(where) == 1 else None

    derived = ambiguous = 0
    for rec in world.records.get("quest", {}).values():
        if rec.get("dungeon") is not None:
            continue
        candidates: set[int] = set()
        for o in rec.get("objectives") or []:
            if not (isinstance(o, list) and len(o) > 1):
                continue
            kind, ref = o[0], str(o[1])
            typ, _, sid = ref.partition(":")
            if not sid.isdigit():
                continue
            if kind == "loot":
                # a loot objective names the item, and its droppers as further loot rows: only the
                # item decides (a world drop with one dungeon dropper is no dungeon quest)
                inside = item_dungeon(int(sid)) if typ == "item" else None
            elif typ in ("npc", "object"):
                inside = only_inside(typ, int(sid))
            else:
                inside = None
            if inside is not None:
                candidates.add(inside)
        for row in rec.get("requiredItems") or []:
            item = row[0] if isinstance(row, list) else row
            if isinstance(item, int):
                inside = item_dungeon(item)
                if inside is not None:
                    candidates.add(inside)
        if len(candidates) == 1:
            rec["dungeon"], rec["dungeonSrc"] = next(iter(candidates)), "classic"
            derived += 1
        elif candidates:
            ambiguous += 1
    if derived or ambiguous:
        world.notes.append(
            f"{derived} dungeon quests derived from where their targets spawn (classic); "
            f"{ambiguous} quests touch two instances and got none"
        )
    return derived


# ---------------------------------------------------------------------------------------------
# Links (ADR 0070, data.md "Links and steps", package QD3)
# ---------------------------------------------------------------------------------------------

# A spell focus with more objects than this is a kind of place, not a place: every campfire is
# focus 4 (2,276 objects), every anvil focus 1 (215), measured 11.11.2026
FOCUS_MAX = 6
MAX_WAYS = 12  # rows of one kind (who it is skinned from, where it is fished) per item
MAX_POINTS = 24  # Classic points kept per subject of a quest before the resolver spreads them
QUEST_PLACE = "quest place"


def _add_way(rec: dict, row: list) -> None:
    ways = rec.setdefault("ways", [])
    while row and row[-1] is None:
        row.pop()
    if row not in ways:
        ways.append(row)


def _at_refs(links: cmangos.Links, way: cmangos.Made) -> list[str]:
    """Where an item is used: the creatures and objects its spell is cast on, and the objects
    that are its spell focus when they are few enough to be a place."""
    refs = [f"{kind}:{entry}" for kind, entry in way.targets]
    objects = links.focus_objects.get(way.focus or 0, [])
    if len(objects) <= FOCUS_MAX:
        refs += [f"object:{o}" for o in objects]
    return refs


def merge_item_ways(world: World, s: Sources) -> None:
    """The ways an item is come by that are no drop (`item.ways` = { { how, ref, chance, at } }):
    `make` (using another item, `at` the object or creature it is used at or on), `container`
    (the item that holds it), `skin` and `pick` (the creature), `fish` (the zone). From CMaNGOS;
    QuestieDB's `itemDrops` names a container for an item CMaNGOS has none for. All of it is
    Classic knowledge. An object named as `at` is a quest place, not a forge (G8)."""
    links, store = s.cm_links, s.questie
    counts: dict[str, int] = {}

    def add(item_id: int, row: list) -> None:
        rec = world.get("item", item_id)
        if rec is not None:
            before = len(rec.get("ways") or ())
            _add_way(rec, row)
            counts[row[0]] = counts.get(row[0], 0) + len(rec["ways"]) - before

    if links is not None:
        for product, ways in links.made.items():
            for way in ways:
                places = [ref for ref in _at_refs(links, way) if _known(world, ref)]
                for at in places or [None]:
                    add(product, ["make", f"item:{way.item_id}", None, at])
                for ref in places:
                    _quest_place(world, ref)
        for item_id, rows in links.held.items():
            for holder, chance in rows[:MAX_WAYS]:
                add(item_id, ["container", f"item:{holder}", chance])
        for how, table in (("skin", links.skinned), ("pick", links.picked)):
            for item_id, rows in table.items():
                known = [(n, c) for n, c in rows if world.get("npc", n) is not None]
                for npc, chance in known[:MAX_WAYS]:
                    add(item_id, [how, f"npc:{npc}", chance])
        for item_id, rows in links.fished.items():
            zones: dict[int, float] = {}
            for area, chance in rows:
                ui_map = s.area_to_map.get(area)
                if ui_map is not None and world.get("zone", ui_map) is not None:
                    zones[ui_map] = max(zones.get(ui_map, 0.0), chance)
            ranked = sorted(zones.items(), key=lambda pair: (-pair[1], pair[0]))
            for ui_map, chance in ranked[:MAX_WAYS]:
                add(item_id, ["fish", f"zone:{ui_map}", chance])
    if store is not None:
        for item_id, row in sorted(store.items.items()):
            rec = world.get("item", item_id)
            if rec is None or any(w[0] == "container" for w in rec.get("ways") or ()):
                continue
            for holder in sorted(set(row.item_drops))[:MAX_WAYS]:
                if world.get("item", holder) is not None:
                    add(item_id, ["container", f"item:{holder}"])
    if counts:
        said = ", ".join(f"{how} {n}" for how, n in sorted(counts.items()))
        world.notes.append(f"item ways beyond drops (classic): {said}")


def _known(world: World, ref: str) -> bool:
    kind, _, raw = ref.partition(":")
    return raw.isdigit() and world.get(kind, int(raw)) is not None


def _quest_place(world: World, ref: str) -> None:
    """A spell focus object a quest's item is used at reads "quest place" (it read "fire and
    forge": the Mirror Lake Waterwall, )."""
    kind, _, raw = ref.partition(":")
    rec = world.get(kind, int(raw)) if kind == "object" and raw.isdigit() else None
    if rec is not None and rec.get("kind") == OBJECT_KINDS[cmangos.GO_SPELL_FOCUS]:
        rec["kind"] = QUEST_PLACE


def merge_questie_vendors(world: World, s: Sources) -> int:
    """QuestieDB's item rows name who sells an item (plan-quest-links.md G7): a vendor the world
    knows that does not list the item gets it, with the engine's price and stack where the client
    knows the item, else without a price (unknown stays unknown)."""
    store = s.questie
    if store is None:
        return 0
    classic = {it.id for it in s.cm_items}
    added = 0
    for item_id, row in sorted(store.items.items()):
        if world.get("item", item_id) is None:
            continue
        for npc_id in sorted(set(row.vendors)):
            npc = world.get("npc", npc_id)
            if npc is None or any(v[0] == item_id for v in npc.get("vendor") or ()):
                continue
            src = "classic" if item_id in classic else "questie"
            offer = engine_offer(s, item_id)  # the engine's price, else unknown stays unknown
            row = [item_id, None, None, None, src]
            if offer is not None:
                row = [item_id, offer[0], offer[1], None, src, "client"]
            npc["vendor"] = [*(npc.get("vendor") or []), row]
            if "vendor" not in (npc.get("flags") or []):
                npc["flags"] = [*(npc.get("flags") or []), "vendor"]
            added += 1
    if added:
        world.notes.append(f"{added} vendor rows from QuestieDB's item rows")
    return added


def _classic_frame(s: Sources) -> dict:
    """The maps a Classic world point may land on: not the zones Forever added."""
    frame = s.transforms
    if frame:
        frame = {k: v for k, v in frame.items() if k not in FOREVER_NEW_MAPS}
    return frame or {}


def _add_points(points: dict[str, list], key: str, rows: list[list]) -> None:
    for row in rows:
        have = points.setdefault(key, [])
        if row not in have and len(have) < MAX_POINTS:
            have.append(row)


def merge_quest_links(world: World, s: Sources) -> None:
    """What the resolver of a quest's steps needs beyond the objectives (steps.py), from CMaNGOS,
    QuestieDB and ForeverDB:

    - `gives`: the item the giver hands over, with its count (shipped: the edge `gives`).
    - `goals`: the creature and object columns with their counts and the spell to cast.
    - `castAt`: the handed item is used at or on a thing (its spell's focus or target), where
      that makes no item (an item it makes is the item's own way).
    - `classicPoints`: the quest log's map points of a later client, per subject: the centre of
      each area; and under `""` the quest's own: its event points, its `PointX`/`PointY`, the
      area triggers that finish it (placed by the Forever client's table), QuestieDB's
      `triggerEnd` and the places of what its hidden objectives name.

    Only `gives` is in a pack; the rest is the build's (no schema carries it)."""
    links = s.cm_links
    frame = _classic_frame(s)
    cities = CAPITALS.get(s.client, ())
    quests = world.records.get("quest", {})
    made_from = (
        {(w.item_id, w.spell_id) for ways in links.made.values() for w in ways} if links else set()
    )
    counts = {"gives": 0, "goals": 0, "castAt": 0, "points": 0, "own points": 0}
    for cq in s.cm_quests:
        rec = quests.get(cq.id)
        if rec is None:
            continue
        if cq.src_item_id:
            rec["gives"] = [[cq.src_item_id, cq.src_item_count]]
            counts["gives"] += 1
        if cq.goals:
            rec["goals"] = [[f"{g.kind}:{g.entry}", g.count, g.spell] for g in cq.goals]
            counts["goals"] += 1
        cast: list[list] = []
        for way in links.uses.get(cq.src_item_id or 0, []) if links else []:
            if (way.item_id, way.spell_id) not in made_from:
                cast += [[f"item:{way.item_id}", ref] for ref in _at_refs(links, way)]
        for goal in cq.goals:
            spells = links.spells.get(cq.src_item_id or 0, ()) if links else ()
            if goal.spell and goal.spell in spells:
                cast.append([f"item:{cq.src_item_id}", f"{goal.kind}:{goal.entry}"])
        cast = [row for i, row in enumerate(cast) if row not in cast[:i] and _known(world, row[1])]
        if cast:
            rec["castAt"] = cast
            counts["castAt"] += 1
            for row in cast:
                _quest_place(world, row[1])
        points: dict[str, list] = {}
        for index, cm_map, corners in links.points.get(cq.id, []) if links else []:
            if index < 0:
                continue  # the hand-in: the quest's `ends` say it
            wx = sum(p[0] for p in corners) / len(corners)
            wy = sum(p[1] for p in corners) / len(corners)
            placed = place_world_point(frame, cm_map, wx, wy, "classic", cities=cities)
            if placed is None:
                continue
            key = ""
            if index < 4:
                goal = next((g for g in cq.goals if g.column == index + 1), None)
                key = f"{goal.kind}:{goal.entry}" if goal else ""
            elif index < 8 and index - 4 < len(cq.required_items):
                key = f"item:{cq.required_items[index - 4][0]}"
            _add_points(points, key, [[placed.ui_map_id, placed.x, placed.y]])
        if cq.point:
            placed = place_world_point(frame, *cq.point, "classic", cities=cities)
            if placed is not None:
                _add_points(points, "", [[placed.ui_map_id, placed.x, placed.y]])
        for trigger in links.triggers.get(cq.id, []) if links else []:
            where = s.fdb_triggers.get(trigger)
            if where is not None:
                row = [where.ui_map_id, round(where.x_pct / 100, 4), round(where.y_pct / 100, 4)]
                _add_points(points, "", [row])
        if points:
            rec["classicPoints"] = points
    for quest_id, q in sorted(s.questie.quests.items()) if s.questie else ():
        rec = quests.get(quest_id)
        if rec is None:
            continue
        if q.source_item and not rec.get("gives"):
            rec["gives"] = [[q.source_item]]
            counts["gives"] += 1
        points = rec.get("classicPoints") or {}
        for places in [q.trigger_end or {}, *(pl for _refs, pl in q.extra)]:
            _add_points(points, "", [row[:3] for row in _questie_rows(places, s)])
        for refs, _places in q.extra:
            # where a thing to do that the log does not list is done: the quest's own place
            _add_points(points, "", [row[:3] for row in _places_of(world, list(refs), MAX_POINTS)])
        if points:
            rec["classicPoints"] = points
    for rec in quests.values():
        points = rec.get("classicPoints") or {}
        counts["points"] += sum(1 for key in points if key)
        counts["own points"] += "" in points
    if any(counts.values()):
        world.notes.append(
            f"quest links: {counts['gives']} quests hand an item over, {counts['goals']} name "
            f"creatures or objects (CMaNGOS), {counts['castAt']} use the handed item at a place; "
            f"Classic points for {counts['points']} subjects and {counts['own points']} quests"
        )


# ---------------------------------------------------------------------------------------------
# Gather nodes
# ---------------------------------------------------------------------------------------------


def merge_nodes(world: World, s: Sources) -> None:
    if not s.fdb_gather:
        return
    kinds, points, zones = s.fdb_gather
    # the Classic fishing skill a zone asks for (ForeverDB's `fish`), on zones the world knows;
    # catalog review A3.6, 07.11.2026
    for z in zones:
        rec = world.get("zone", z.ui_map_id)
        if rec is not None and z.fishing_skill is not None and z.fishing_skill > 0:
            rec["fishing"] = z.fishing_skill
    for k in kinds:
        rec = _rec(world, "node", k.id)
        rec["name"] = clean_name(k.name)
        rec["kind"] = k.profession
        rec["profession"] = k.profession
        rec["skill"] = k.skill
        rec["item"] = k.item_id
        rec["icon"] = k.icon_file_id
        rec["src"] = "forever"
        if k.profession in ("herb", "mine"):
            world.gather_objects.update(dict.fromkeys(k.object_ids, k.profession))
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


def _gives(world: World, source: str | None, item_id: int) -> bool:
    """Whether a table names `source` (npc:1, object:2) as giving the item: the item's droppers,
    the source's loot or its stock. Both loot lists are capped, so either side proves it."""
    kind, _, raw = (source or "").partition(":")
    if kind not in ("npc", "object") or not raw.isdigit():
        return False
    item = world.get("item", item_id) or {}
    rec = world.get(kind, int(raw)) or {}
    return (
        any(row[0] == source for row in item.get("drops") or ())
        or any(row[0] == item_id for row in rec.get("loot") or ())
        or any(row[0] == item_id for row in rec.get("vendor") or ())
    )


def _named_source(obj: list, item_ref: str) -> str | None:
    """The source a loot objective names: its fourth field, or its target before it became the
    item."""
    if len(obj) > 3:
        return obj[3]
    return obj[1] if obj[1] and obj[1] != item_ref else None


def fix_loot_objectives(world: World) -> None:
    """Everything Quests encodes a loot objective by the NPC or object the item comes from
    (CLUCK!: "loot npc:233", Farmer Saldean, who sells the Special Chicken Feed). The objective is
    the item: the n-th loot objective takes the n-th required item (CMaNGOS ReqItemId), and a
    source moves to a fourth field so the page can still say where to get it.

    Everything Quests' list is not one source per item (Redridge Goulash, 09.11.2026: Bellygrub, a
    condor and a boar beside three items, no spider), so an item takes the named source a table
    proves. An item whose droppers are known and none of them named has no source (unknown). An
    item without a table keeps the one at its position, unless that one is proven for another."""
    for rec in world.records.get("quest", {}).values():
        objectives = rec.get("objectives")
        items = rec.get("requiredItems")
        if not objectives or not items:
            continue
        loot = [o for o in objectives if o[0] == "loot"]
        pairs = [(o, items[n][0]) for n, o in enumerate(loot) if n < len(items) and items[n][0]]
        named = {id(o): _named_source(o, f"item:{item_id}") for o, item_id in pairs}
        sources = [s for s in named.values() if s]
        proven = {
            item_id: [s for s in sources if _gives(world, s, item_id)] for _, item_id in pairs
        }
        spoken_for = {s for given in proven.values() for s in given}
        for obj, item_id in pairs:
            own, given = named[id(obj)], proven[item_id]
            if given:
                source = own if own in given else given[0]
            elif (world.get("item", item_id) or {}).get("drops") or own in spoken_for:
                source = None
            else:
                source = own
            obj[1] = f"item:{item_id}"
            del obj[3:]
            if source:
                obj.extend([None] * (3 - len(obj)))
                obj.append(source)


def _item_bits(rec: dict) -> dict[int, int]:
    """The bit of each item a quest asks for, as the addon counts them (Steps.lua): with numbered
    rows (Everything Quests) the item's place among the required items, else its place among the
    loot rows. An item neither names has no bit: no step would read its spots."""
    rows = rec.get("objectives") or ()
    if any(len(o) > 2 and isinstance(o[2], int) for o in rows):
        required = rec.get("requiredItems") or ()
        return {row[0]: bit for bit, row in enumerate(required) if row[0]}
    bits: dict[int, int] = {}
    for bit, o in enumerate(o for o in rows if o[0] == "loot"):
        kind, _, raw = str(o[1]).partition(":")
        if kind == "item" and raw.isdigit():
            bits.setdefault(int(raw), bit)
    return bits


def merge_item_spots(world: World) -> int:
    """A quest without any spot gets, for each item it asks for, the places of who has the item
    (plan-quest-links.md G2, package QD1): the first SPOT_DROPPERS of the item's droppers, a
    spread per map, as spots of kind `loot` with the item's bit and, as a fifth field, who stands
    there. An item has no place of its own, and a reader that takes a quest's places from its
    spots alone (every suite before "Where a quest sends you") sent the player back to the giver.
    Runs last: a quest with spots of any source keeps them (the client's own areas too), and the
    loot rows are the items by then. Returns how many quests it placed."""
    placed = 0
    for _quest_id, rec in sorted(world.records.get("quest", {}).items()):
        if rec.get("spots"):
            continue
        rows: dict[int, list] = {}
        for item, bit in sorted(_item_bits(rec).items(), key=lambda pair: pair[1]):
            drops = (world.get("item", item) or {}).get("drops") or ()
            for drop in drops[:SPOT_DROPPERS]:
                kind, _, raw = str(drop[0]).partition(":")
                dropper = world.get(kind, int(raw)) if raw.isdigit() else None
                for row in (dropper or {}).get("spawns") or ():
                    rows.setdefault(row[0], []).append(
                        [row[0], row[1], row[2], "loot", 1 << bit, drop[0]]
                    )
        if rows:
            rec["spots"] = {
                ui_map: [r[1:] for r in farthest_points(rows[ui_map], MAX_SPOTS_PER_MAP)]
                for ui_map in sorted(rows)
            }
            rec["spotsSrc"] = "items"  # made from the items' droppers: the resolver asks them
            placed += 1
    if placed:
        world.notes.append(f"{placed} quests without a spot got the places of who has their items")
    return placed


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
        if node.name.lower().startswith("zz"):  # Blizzard's mark for a retired row
            world.drop("flightpath", node.id, "retired in the client")
            continue
        rec = _rec(world, "flightpath", node.id)
        rec["name"] = node.name
        rec["faction"] = node.faction
        rec["continent"] = node.continent
        rec["wx"] = node.wx
        rec["wy"] = node.wy
        rec["wz"] = node.wz  # not in the pack schema: only the walk network's nodes read it
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
            _add_spawn(rec, Spawn(ui_map_id, round(x, 4), round(y, 4), "client", node.wz))
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
FOREVER_SPAWN_SOURCES = {"eq", "fdb", "questie", "capture", "client", "config"}


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


# ---------------------------------------------------------------------------------------------
# The client's own tables (ADR 0035, "client first"): what the client holds wins, it is the build
# ---------------------------------------------------------------------------------------------


def merge_client_items(world: World, s: Sources) -> None:
    """ItemSparse and Item over the older sources (CMaNGOS' Classic values, ForeverDB): name,
    quality, levels, class, prices, stack. Every item the client has is kept (an item CMaNGOS
    lacks is new in Forever); ~~retail only the items something refers to~~ (retail out
    15.11.2026)."""
    t = s.client_tables
    if t is None:
        return
    items = world.records.setdefault("item", {})
    classic = {it.id for it in s.cm_items}
    for item_id, it in sorted(t.items.items()):
        if it.name is None and item_id not in items:
            continue
        rec = _rec(world, "item", item_id)
        values = {
            "name": clean_name(it.name),
            "quality": it.quality,
            "level": it.level,
            "reqLevel": it.required_level,
            "class": it.item_class,
            "subclass": it.item_subclass,
            "sell": it.sell,
            "buy": it.buy,
            "stack": it.stack,
        }
        for key, value in values.items():
            if value is not None:
                rec[key] = value
        if classic and item_id not in classic:
            _set_if_missing(rec, "foreverNew", True)
        if rec.get("src") in (None, "classic"):
            rec["src"] = "client"


def merge_client_recipes(world: World, s: Sources) -> None:
    """SkillLineAbility, SpellName, SpellEffect and SpellReagents: a recipe's profession, name,
    product and reagents. Every recipe of a profession is kept (~~retail filled the recipes
    AllTheThings lists~~, out 15.11.2026). The level a trainer teaches it at stays the other
    sources' (the server holds it); the client's own rank only where none is known."""
    t = s.client_tables
    if t is None:
        return
    for r in t.recipes:
        profession = PROFESSION_SKILL_LINES.get(r.skill_line)
        if profession is None:
            continue
        rec = _rec(world, "recipe", r.spell)
        if r.name:
            rec["name"] = clean_name(r.name)
        rec["profession"] = profession
        if r.item:
            rec["item"] = r.item
            rec["count"] = r.count
        if r.reagents:
            rec["reagents"] = [list(x) for x in r.reagents]
        _set_if_missing(rec, "skill", r.learned_at)
        _set_if_missing(rec, "src", "client")


def merge_client_quest_lines(world: World, s: Sources) -> None:
    """QuestLineXQuest: each quest of a line chains into the next one, where no other source
    named its successor."""
    t = s.client_tables
    if t is None:
        return
    quests = world.records.get("quest", {})
    for line in t.quest_lines:
        for a, b in pairwise(line):
            if a in quests and b in quests and a != b:
                _set_if_missing(quests[a], "chain", b)


def merge_client_quest_areas(world: World, s: Sources) -> None:
    """QuestPOIBlob and QuestPOIPoint: the areas the quest log draws, one spot per objective area
    (the centre of its corners, as a map fraction), kind `area`, for quests without spots; on the
    world graph's continents only (GRAPH_CONTINENTS), as the other places."""
    t = s.client_tables
    if t is None or not s.transforms:
        return
    quests = world.records.get("quest", {})
    found: dict[int, dict[int, list]] = {}
    for a in t.quest_areas:
        rec = quests.get(a.quest)
        transform = s.transforms.get(a.ui_map)
        if rec is None or rec.get("spots") or transform is None or a.objective < 0:
            continue
        if transform.continent not in GRAPH_CONTINENTS:
            continue
        wx = sum(p[0] for p in a.points) / len(a.points)
        wy = sum(p[1] for p in a.points) / len(a.points)
        xy = world_to_map(transform, wx, wy)
        if xy is None or not (0 <= xy[0] <= 1 and 0 <= xy[1] <= 1):
            continue
        spots = found.setdefault(a.quest, {}).setdefault(a.ui_map, [])
        if len(spots) < MAX_SPOTS_PER_MAP:
            spots.append([round(xy[0], 4), round(xy[1], 4), "area", 1 << min(a.objective, 30)])
    for quest_id, by_map in found.items():
        quests[quest_id]["spots"] = {m: v for m, v in sorted(by_map.items())}
        quests[quest_id]["spotsSrc"] = "client"


def merge_dungeons(world: World, s: Sources) -> None:
    """ForeverDB's dungeons and raids (data.md "Dungeons", 30.10.2026): a `dungeon` record per
    instance (id = its Map.db2 id, the key of our entrance rows), its bosses as npc records (named
    from ForeverDB where no other source knows them, flagged `boss`, the dungeon on them), the loot
    ForeverDB players saw in Forever added to each boss's loot (chance unknown, never zero), and the
    dungeon on its quests. Runs after the Classic loot, which keeps its measured chances."""
    zones_by_name = {
        rec["name"]: zone_id
        for zone_id, rec in world.records.get("zone", {}).items()
        if isinstance(rec.get("name"), str)
    }
    by_name: dict[str, list[int]] = {}
    for npc_id, npc in world.records.get("npc", {}).items():
        if isinstance(npc.get("name"), str):
            by_name.setdefault(npc["name"].lower(), []).append(npc_id)
    for d in s.fdb_dungeons:
        rec = _rec(world, "dungeon", d.id)
        rec["name"] = clean_name(d.name)
        rec["kind"] = d.kind
        rec["size"] = d.size
        rec["levelLo"], rec["levelHi"], rec["levelReq"] = d.level_lo, d.level_hi, d.level_req
        rec["zone"] = zones_by_name.get(d.zone_name) if d.zone_name else None
        if d.zone_name and rec["zone"] is None:
            world.notes.append(f"dungeon {d.id} {d.name}: zone {d.zone_name!r} is unknown here")
        creature = {b.order: _boss_creature(world, s, d, b, by_name) for b in d.bosses}
        rec["bosses"] = [[b.order, creature[b.order], b.name] for b in d.bosses] or None
        rec["loot"] = [[x.item_id, x.boss_order, x.label] for x in d.loot] or None
        rec["quests"] = list(d.quests) or None
        rec["src"] = "forever"
        unlinked = [b.name for b in d.bosses if creature[b.order] is None]
        if unlinked:
            world.notes.append(f"dungeon {d.id} {d.name}: no creature known for {unlinked}")
        for b in d.bosses:
            if creature[b.order] is None:
                continue  # the boss keeps its name on the dungeon, without a page of its own
            npc = _rec(world, "npc", creature[b.order])
            _set_if_missing(npc, "name", clean_name(b.name))
            flags = npc.get("flags")
            flags = [flags] if isinstance(flags, str) else list(flags or [])
            if "boss" not in flags:
                flags.append("boss")
            npc["flags"] = flags
            npc["dungeon"] = d.id
            _set_if_missing(npc, "src", "forever")
        for x in d.loot:
            npc_id = creature.get(x.boss_order)
            if npc_id is None or x.label != "s":
                continue  # unassigned loot and an unlinked boss's stay on the dungeon
            npc = world.get("npc", npc_id)
            loot = npc.get("loot") or []
            if not any(int(row[0]) == x.item_id for row in loot):
                loot.append([x.item_id, None])  # seen in Forever, chance unknown
            npc["loot"] = loot
            _set_if_missing(npc, "lootSrc", "forever")
        for quest_id in d.quests:
            quest = world.get("quest", quest_id)
            if quest is not None:
                quest["dungeon"] = d.id
                quest["dungeonSrc"] = "forever"
    # the floors: the
    # client's own dungeon maps from the retail client's UiMap tables (`floor_art`; the Forever
    # client has the same art under its file names), the boss spots and the door placed on them
    # through the world from ForeverDB's layout (DungeonFloor.world_point) and the floors' height
    # bands; an instance the client has no map of (Forever's own dungeons) keeps ForeverDB's
    # minimap plates (~~a bare plate on retail~~, out 15.11.2026)
    bosses_of = {d.id: d.bosses for d in s.fdb_dungeons}
    for m in s.fdb_dungeon_maps:
        rec = world.get("dungeon", m.id)
        if rec is None:
            world.notes.append(f"dungeon map {m.id}: no dungeon record for it, left out")
            continue
        art = s.floor_art.get(m.id) or []
        if art:
            rec["floors"] = [_floor_record(f) for f in art]
            heights = _boss_heights(s, m.id, bosses_of.get(m.id, ()))
            spots, lost = [], []
            for order, floor, x, y in m.boss_spots:
                placed = _place_on_floor(art, m, floor, x, y, heights.get(order))
                if placed is None:
                    lost.append(order)
                else:
                    spots.append([order, *placed])
            rec["bossSpots"] = spots or None
            door = m.door and _place_on_floor(art, m, m.door[0], m.door[1], m.door[2], None)
            rec["door"] = list(door) if door else None
            if lost:
                world.notes.append(
                    f"dungeon {m.id} {rec.get('name')}: bosses {lost} have no floor on the"
                    " client's maps (several floors share their region)"
                )
            continue
        floors = []
        for f in m.floors:
            row = {"n": f.name, "w": f.width, "h": f.height}
            if f.tiles:
                row["t"] = [[t.fdid, t.x, t.y, t.w, t.h, t.q] for t in f.tiles]
            floors.append(row)
        rec["floors"] = floors or None
        rec["bossSpots"] = [[o, fl, x, y] for o, fl, x, y in m.boss_spots] or None
        rec["door"] = list(m.door) if m.door else None
        if m.why:
            world.notes.append(f"dungeon map {m.id} {rec.get('name')}: {m.why}")


def _boss_creature(
    world: World, s: Sources, d: foreverdb.DungeonRow, b, by_name: dict[str, list[int]]
) -> int | None:
    """The creature id of a ForeverDB boss (02.11.2026): Dungeons.lua's boss numbers are not
    creature ids (Shadowfang Keep's 2748 is the creature Archaedas, Dalaran's 3298 Gabrielle
    Chase). In order: Loot.lua's creature for the boss of that instance; the CMaNGOS creature of
    that name with a spawn on the instance's map (the Classic dungeons); the only npc of that name
    in the data. None when nothing names it: never a guess. (~~Retail does not link Forever's own
    dungeons' bosses~~, out 15.11.2026.)"""
    name = clean_name(b.name).lower()
    known = s.fdb_boss_creatures
    if known is not None and name in known.npcs.get(d.id, {}):
        return known.npcs[d.id][name]
    entries = {
        int(row["Entry"]) for row in s.cm_creatures if str(row.get("Name") or "").lower() == name
    }
    spawned = sorted(
        {
            sp.entry
            for sp in s.cm_spawns
            if sp.kind == "creature" and sp.map_id == d.id and sp.entry in entries
        }
    )
    if len(spawned) == 1:
        return spawned[0]
    same = by_name.get(name, [])
    if len(same) == 1:
        return same[0]
    return None


def _floor_record(f: FloorArt) -> dict:
    """A floor as the pack carries it: `n` name, `m` the retail client's UiMap id (~~retail draws
    its art through C_Map~~), `a` the tiles' path prefix with `g` = {cols, rows} (Forever draws
    the files), `w` x `h` the visible art in pixels."""
    w, h = f.size
    row: dict = {"n": f.name, "m": f.ui_map_id, "w": w, "h": h}
    if f.art:
        row["a"] = f.art
        row["g"] = [f.cols, f.rows]
    return row


def _boss_heights(s: Sources, map_id: int, bosses) -> dict[int, list[tuple[float, float, float]]]:
    """Per boss order the Classic spawn points (x, y, z) of a creature of that name on the
    instance map (CMaNGOS; Forever renumbered its bosses, so the name is the join): the exact
    height picks the floor where the floors stack."""
    if not s.cm_spawns or not bosses:
        return {}
    wanted = {clean_name(b.name).lower(): b.order for b in bosses}
    entries: dict[int, int] = {}
    for row in s.cm_creatures:
        name = str(row.get("Name") or "").lower()
        if name in wanted:
            entries[int(row["Entry"])] = wanted[name]
    out: dict[int, list[tuple[float, float, float]]] = {}
    for sp in s.cm_spawns:
        on_map = sp.kind == "creature" and sp.map_id == map_id and sp.entry in entries
        if on_map and sp.position_z is not None:
            out.setdefault(entries[sp.entry], []).append(
                (sp.position_x, sp.position_y, sp.position_z)
            )
    return out


def _place_on_floor(
    art: list[FloorArt],
    m: foreverdb.DungeonMapRow,
    floor: int,
    x_pct: float,
    y_pct: float,
    heights: list[tuple[float, float, float]] | None,
) -> tuple[int, float, float] | None:
    """A ForeverDB spot (percent of its floor) on the client's floors: (floor index from 1, x %,
    y %) of the floor the client shows there, or None when ForeverDB's floor has no place in the
    world or no single floor fits."""
    if not 1 <= floor <= len(m.floors):
        return None
    f = m.floors[floor - 1]
    wp = f.world_point(x_pct, y_pct)
    if wp is None:
        return None
    wx, wy = wp
    z = f.z_mid
    if heights:
        _, _, z = min(heights, key=lambda p: (p[0] - wx) ** 2 + (p[1] - wy) ** 2)
    i = floor_for_point(art, wx, wy, z)
    if i is None:
        return None
    regions = [
        r for r in art[i - 1].regions if r[3] - r[0] <= WHOLE_WORLD and r[4] - r[1] <= WHOLE_WORLD
    ]
    region = next((r for r in regions if r[0] <= wx <= r[3] and r[1] <= wy <= r[4]), None)
    if region is None:
        return None
    min_x, min_y, _, max_x, max_y, _ = region
    px = (max_y - wy) / (max_y - min_y) * 100
    py = (max_x - wx) / (max_x - min_x) * 100
    return i, round(px, 2), round(py, 2)


def build_world(s: Sources) -> World:
    world = World(client=s.client, build=s.build, sources=list(s.source_names))
    world.notes.extend(s.notes)
    world.area_to_map = dict(s.area_to_map)
    merge_zones(world, s)
    merge_areas(world, s)
    merge_creatures(world, s)
    merge_questie_world(world, s)
    merge_vendors_and_trainers(world, s)
    merge_quests(world, s)
    merge_fdb_quest_facts(world, s)
    merge_fdb_api(world, s)
    merge_fdb_previous_quests(world, s)
    merge_questie_gates(world, s)
    merge_client_quest_titles(world, s)
    merge_items(world, s)
    merge_client_recipes(world, s)
    merge_client_items(world, s)
    merge_client_quest_lines(world, s)
    merge_questie_items(world, s)
    merge_questie_vendors(world, s)
    merge_item_ways(world, s)
    merge_questie_quests(world, s)
    link_breadcrumbs(world)
    merge_quest_links(world, s)
    merge_objective_texts(world)
    merge_client_quest_areas(world, s)
    merge_dungeons(world, s)
    derive_dungeon_quests(world, s)
    merge_nodes(world, s)
    merge_flightpaths(world, s)
    prune_classic_spawns(world)
    assign_zones(world)
    fix_loot_objectives(world)
    # the internal records leave before the statistics count them (data.md "Internal records")
    drop_internal(world, {row["Entry"]: row.get("UnitFlags") for row in s.cm_creatures})
    merge_item_spots(world)  # last: what the other sources place stays, and who is left is real
    zone_statistics(world)
    name_unnamed_zones(world, s)
    for rows in world.records.values():
        for rec in rows.values():
            for key in [k for k, v in rec.items() if v is None]:
                del rec[key]
    return world
