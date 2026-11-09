"""The canonical merge over the real-format reader fixtures (B3.3): precedence, labels, drops."""

import shutil
from pathlib import Path

import pytest

from bastians_build.build import build, render_report
from bastians_build.canon import (
    Sources,
    build_world,
    clean_name,
    derive_dungeon_quests,
    fix_loot_objectives,
    level_band,
    localized_name,
    merge_creatures,
    object_kind,
    zone_statistics,
)
from bastians_build.config import load_config
from bastians_build.derive import build_index
from bastians_build.load import SourcePaths, load_sources
from bastians_build.model import World
from bastians_build.sources import clientdump, cmangos, foreverdb, probe, questiedb
from bastians_build.sources.everything_quests import read_everything_quests

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures" / "sources"


def fixture_sources(*, with_probe: bool = True) -> Sources:
    """Sources straight from the reader fixtures (no AddOns folder layout needed)."""
    s = Sources(client="forever", build="fixture")
    s.eq = read_everything_quests(FIXTURES / "everything_quests", "Forever")
    fdb = FIXTURES / "foreverdb"
    s.fdb_npcs = foreverdb.read_npcs(fdb / "NPCs.lua")
    s.fdb_recipes = foreverdb.read_recipes(fdb / "Recipes.lua")
    s.fdb_gather = foreverdb.read_gather(fdb / "Gather.lua")
    s.fdb_quests = foreverdb.read_quests(fdb / "QuestForever.lua")
    s.fdb_items = foreverdb.read_items(fdb / "Items.lua")
    s.fdb_names = foreverdb.read_search_names(fdb / "SearchNames.lua")
    s.fdb_dungeons = foreverdb.read_dungeons(fdb / "Dungeons.lua")
    s.fdb_dungeon_maps = foreverdb.read_dungeon_maps(fdb / "DungeonMaps.lua")
    s.fdb_boss_creatures = foreverdb.read_boss_creatures(fdb / "Loot.lua")
    floors = FIXTURES / "clientdump-floors"
    s.floor_art = clientdump.read_floor_art(floors, "retail", floors / "listfile.csv")
    tables = cmangos.read_tables(FIXTURES / "cmangos" / "classicdb_mini.sql.gz")
    s.cm_quests = cmangos.quest_rows(tables)
    s.cm_creatures = tables["creature_template"]
    s.cm_objects = tables["gameobject_template"]
    s.cm_spawns = cmangos.spawn_rows(tables)
    s.cm_vendors = cmangos.vendor_rows(tables)
    s.cm_trainers = cmangos.trainer_services(tables)
    s.cm_loot = cmangos.loot_rows(tables)
    s.cm_items = cmangos.item_rows(tables)
    s.area_to_map = questiedb.read_area_to_ui_map_file(
        FIXTURES / "questiedb" / "areaIdToUiMapId.lua"
    ).mapping
    if with_probe:
        dump = probe.read_probe_dump(FIXTURES / "probe" / "2026-10-19-forever-fixture.lua")
        s.transforms = probe.transform_table(dump)
        s.map_names = probe.map_names(dump)
    return s


def test_level_band_trims_the_outliers_of_a_zone():
    """Elwynn showed "1-60" because a few class and holiday quests given there are level 60
    (Forever beta 22.10.2026): levels beyond Tukey's fences are left out once ten quests are in."""
    assert level_band([]) is None
    assert level_band([5, 7, 3]) == (3, 7, 5)  # few quests: min and max
    levels = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 60, 60]
    assert level_band(levels) == (1, 12, 8)
    assert level_band([60] * 3 + list(range(10, 20))) == (10, 19, 16)
    world = World(client="forever")
    for i, (level, flags) in enumerate(
        [(1, None), (2, None), (3, None), (4, None), (60, ["class"]), (60, ["repeatable"])]
    ):
        world.add("quest", i + 1, {"level": level, "zone": 1429, "flags": flags})
    zone_statistics(world)
    elwynn = world.get("zone", 1429)
    assert (elwynn["levelLo"], elwynn["levelHi"]) == (1, 4)  # class and repeatable levels left out
    assert elwynn["questsA"] == 6  # ... but every quest counts


def test_localized_forever_names_keep_the_classic_name():
    assert localized_name("Saldean le fermier") is True
    assert localized_name("Bauer Saldean und der Hund") is True
    assert localized_name("Hogger") is False
    assert localized_name("Marisa du'Paige") is False  # one token, an English name
    assert localized_name("Ptérodactyle") is True
    assert localized_name(None) is False
    world = build_world(fixture_sources())
    assert world.get("npc", 448)["name"] == "Hogger"


def test_loot_objectives_point_at_the_required_item():
    """CLUCK! listed "loot: Farmer Saldean" (the vendor of the feed) instead of the Special
    Chicken Feed item (Forever beta 22.10.2026)."""
    world = World(client="forever")
    world.add(
        "quest",
        3861,
        {
            "objectives": [["loot", "npc:233", 0], ["slay", "npc:620", 0], ["loot", "npc:9", 1]],
            "requiredItems": [[11109, 1], [11110, 2]],
        },
    )
    world.add("quest", 1, {"objectives": [["loot", "npc:5", 0]]})  # no required items: as it was
    fix_loot_objectives(world)
    assert world.get("quest", 3861)["objectives"] == [
        ["loot", "item:11109", 0, "npc:233"],
        ["slay", "npc:620", 0],
        ["loot", "item:11110", 1, "npc:9"],
    ]
    assert world.get("quest", 1)["objectives"] == [["loot", "npc:5", 0]]
    fix_loot_objectives(world)  # idempotent
    assert world.get("quest", 3861)["objectives"][0] == ["loot", "item:11109", 0, "npc:233"]


def test_clean_name():
    assert clean_name('Wanted:  "Hogger"') == 'Wanted: "Hogger"'
    assert clean_name("  ") is None and clean_name(None) is None


def test_hogger_merges_classic_facts_with_forever_names():
    world = build_world(fixture_sources())
    hogger = world.get("npc", 448)
    assert hogger["name"] == "Hogger" and hogger["level"] == 11
    assert "elite" in hogger["flags"]
    assert hogger["src"] == "classic"  # a quest target: named by CMaNGOS only
    spawns = hogger.get("spawns") or []
    assert spawns and all(s[3] == "classic" and s[0] == 1429 for s in spawns)
    assert all(0 <= s[1] <= 1 and 0 <= s[2] <= 1 for s in spawns)
    assert hogger["zone"] == 1429
    # the height as the fifth field and, where the creature roams, its radius as the sixth (W5)
    assert any(len(s) == 6 and s[4] == 39.6 and s[5] == 8.0 for s in spawns)
    assert hogger.get("loot"), "Classic loot of creature 448 is in the fixture"


def test_quest_givers_get_their_everything_quests_position():
    world = build_world(fixture_sources(with_probe=False))
    dughan = world.get("npc", 240)
    assert dughan["name"] == "Marshal Dughan" and dughan["src"] == "forever"
    eq_spawns = [s for s in dughan["spawns"] if s[3] == "eq"]
    assert eq_spawns and all(s[0] == 1429 for s in eq_spawns)
    assert dughan["zone"] == 1429


def test_forever_db_vendor_gets_forever_coordinates_as_fractions():
    world = build_world(fixture_sources())
    corina = world.get("npc", 54)
    assert corina["name"] == "Corina Steele" and corina["subname"] == "Weaponsmith"
    assert corina["faction"] == "A"
    assert [1429, 0.416, 0.658, "fdb"] in corina["spawns"]
    assert "vendor" in corina["flags"]


def test_classic_npc_flags_are_read_with_the_classic_table():
    """Stormwind's three auctioneers carried `repair` and its two stable masters `flightmaster`,
    and no NPC was an innkeeper, a banker or a flight master (Forever, 05.11.2026): CMaNGOS'
    NpcFlags are the Classic 1.12 bits (4096 auctioneer, 8192 stable master, 16384 repair,
    8 flight master, 4 vendor) and were read with the retail family's table. The rows carry the
    values of ClassicDB z2815."""
    rows = [
        {"Entry": 8670, "Name": "Auctioneer Chilton", "MinLevel": 50, "NpcFlags": 4096},
        {"Entry": 9977, "Name": "Sylista", "SubName": "Stable Master", "NpcFlags": 8193},
        {"Entry": 352, "Name": "Dungar Longdrink", "SubName": "Gryphon Master", "NpcFlags": 11},
        {"Entry": 6740, "Name": "Innkeeper Allison", "SubName": "Innkeeper", "NpcFlags": 135},
        {"Entry": 2455, "Name": "Olivia Burnside", "SubName": "Banker", "NpcFlags": 257},
        {"Entry": 1, "Name": "Gossip only", "NpcFlags": 1},
        {"Entry": 2, "Name": "No column"},
    ]
    world = World(client="forever", build="test")
    merge_creatures(world, Sources(client="forever", cm_creatures=rows))
    flags = {i: world.get("npc", i)["flags"] for i in (8670, 9977, 352, 6740, 2455, 1, 2)}
    assert flags == {
        8670: ["auctioneer"],
        9977: ["stablemaster"],
        352: ["questgiver", "flightmaster"],
        6740: ["questgiver", "vendor", "innkeeper"],
        2455: ["banker"],
        1: None,  # no service: unknown stays None, never an empty list
        2: None,
    }
    # the real-format fixture: Corina Steele's 16388 is vendor + repair (it was neither: the
    # ForeverDB title alone made her a vendor); the mage trainer's 19 is quest giver + trainer
    world = build_world(fixture_sources())
    assert world.get("npc", 54)["flags"] == ["vendor", "repair"]
    assert world.get("npc", 198)["flags"][:2] == ["questgiver", "trainer"]


def test_quest_176_takes_forever_names_and_classic_rewards():
    world = build_world(fixture_sources())
    q = world.get("quest", 176)
    assert q["name"] == 'Wanted: "Hogger"'
    assert q["starts"][0].startswith("object:") and q["ends"] == ["npc:240"]
    assert q["level"] == 11 and q["src"] == "forever"  # Everything Quests wins
    assert q["rewards"]["src"] == "classic"
    text = world.get("questText", 176)
    assert text["src"] == "classic" and text["objectives"]  # texts live in the text pack
    assert 1429 in q["spots"] and len(q["spots"][1429]) <= 8
    # the loot objective is the claw, looted from Hogger (23.10.2026; the EQ source stays)
    assert q["objectives"][0] == ["loot", "item:1931", 0, "npc:448"]
    fargodeep = world.get("quest", 62)
    assert (
        fargodeep["name"] == "The Fargodeep Mine" and fargodeep["minLevel"] == 4
    )  # Everything Quests gates


def test_items_recipes_and_nodes():
    world = build_world(fixture_sources())
    items = world.records["item"]
    assert items, "CMaNGOS items in the fixture"
    for rec in items.values():
        assert rec.get("src") in ("classic", "forever")
        assert "sell" not in rec or isinstance(rec["sell"], int)
    recipes = world.records["recipe"]
    assert all(r["src"] == "forever" and r["profession"] for r in recipes.values())
    nodes = world.records["node"]
    peacebloom = next(n for n in nodes.values() if n["name"] == "Peacebloom")
    assert peacebloom["kind"] == "herb" and peacebloom["item"] == 2447
    assert all(s[3] in ("classic", "fdb") for s in peacebloom["spawns"])


def test_the_game_objects_of_herbs_and_veins_are_an_index():
    """The client names a dot in its language and the text packs translate objects, not nodes:
    Tracked.lua goes through this index. Veins no gather kind lists come by their name."""
    world = build_world(fixture_sources())
    world.add("object", 73941, {"name": "Ooze Covered Gold Vein"})
    world.add("object", 2653, {"name": "Lesser Bloodstone Deposit"})
    world.add("object", 31, {"name": "Old Lion Statue"})
    index = build_index(world, "node.objects")
    assert index[1618] == "herb" and index[3724] == "herb"  # Peacebloom's two objects
    assert index[73941] == "mine" and index[2653] == "mine"
    assert 31 not in index
    assert 2956 not in index  # a skinnable creature is an NPC, no object
    assert list(index) == sorted(index)


def test_object_kinds_are_names_not_type_numbers():
    """ADR 0016: the Objects list showed chips "3", "5", "8" on the Forever beta (23.10.2026), the
    raw gameobject_template.type; data.md specifies names. Unknown stays None, an unlisted number
    is "other"."""
    world = build_world(fixture_sources())
    objects = world.records["object"]
    assert objects[35]["kind"] == "quest object"  # type 2
    assert objects[1617]["kind"] == "chest"  # type 3 (the herb is also a node)
    assert objects[68].get("kind") is None  # an Everything Quests object without a template
    assert object_kind(19) == "mailbox" and object_kind(8) == "fire and forge"
    assert object_kind(99) == "other" and object_kind(None) is None
    kinds = {r.get("kind") for r in objects.values()}
    assert not any(isinstance(k, int) for k in kinds)


def test_without_transforms_classic_spawns_are_dropped_with_a_reason():
    world = build_world(fixture_sources(with_probe=False))
    reasons = {reason for _, _, reason in world.dropped}
    assert any("no transform" in r for r in reasons)
    assert not any("instance map" in r and "map 0" in r for r in reasons)
    assert "spawns" not in world.get("npc", 448)
    report = render_report(build(world, load_config(), Path("unused"), write=False))
    assert "no transform" in report and "rows:" in report


def test_zones_come_from_the_probe_dump():
    world = build_world(fixture_sources())
    assert world.get("zone", 1429)["name"] == "Elwynn Forest"
    # ForeverDB's Classic fishing skill reaches the zone (catalog review A3.6, 07.11.2026); a zone
    # the world does not know (1411 in the fixture) makes no record
    assert world.get("zone", 1429)["fishing"] == 25
    assert world.get("zone", 1411) is None
    assert (
        world.get("zone", 1429)["parent"] == 1415 if "parent" in world.get("zone", 1429) else True
    )


def test_load_sources_from_an_addons_layout(tmp_path):
    addons = tmp_path / "AddOns"
    shutil.copytree(FIXTURES / "everything_quests", addons / "EverythingQuests")
    shutil.copytree(FIXTURES / "foreverdb", addons / "ForeverDB" / "Data")
    zones = addons / "QuestieDB" / "support" / "Forever" / "Zones"
    zones.mkdir(parents=True)
    shutil.copy(FIXTURES / "questiedb" / "areaIdToUiMapId.lua", zones)
    paths = SourcePaths(
        addons=addons,
        cmangos=FIXTURES / "cmangos" / "classicdb_mini.sql.gz",
        probe=FIXTURES / "probe" / "2026-10-19-forever-fixture.lua",
    )
    s = load_sources("forever", paths)
    assert s.eq is not None and s.fdb_npcs and s.cm_creatures and s.transforms and s.area_to_map
    assert any(name.startswith("Everything Quests") for name in s.source_names)
    assert s.build == "fixture"
    world = build_world(s)
    result = build(world, load_config(), tmp_path / "out", transforms=s.transforms)
    assert result.ok, result.problems
    assert (tmp_path / "out" / "Bastians_Data" / "Generated" / "MapTransforms.lua").is_file()
    text = (tmp_path / "out" / "Bastians_Data" / "Generated" / "MapTransforms.lua").read_text(
        encoding="utf-8"
    )
    assert text.startswith("-- GENERATED") and '"Data.RegisterTransforms",' in text
    assert {p.pack.name for p in result.packs} == {"world", "quests", "items", "text"}
    again = build(world, load_config(), tmp_path / "out", transforms=s.transforms)
    assert not any(p.changed for p in again.packs) and not again.transforms_changed


@pytest.mark.parametrize("record_type", ["npc", "quest", "item"])
def test_no_none_values_survive_in_records(record_type):
    world = build_world(fixture_sources())
    for rec in world.records[record_type].values():
        assert None not in rec.values()


def test_classic_spawns_yield_to_forever_places():
    """Precedence: an NPC with a Forever place keeps no converted Classic point; one without keeps
    them."""
    world = build_world(fixture_sources())
    dughan = world.records["npc"][240]
    assert dughan["spawns"] and all(s[3] != "classic" for s in dughan["spawns"])
    assert any(
        reason == "classic spawn superseded by a Forever place" and record_id == 240
        for record_type, record_id, reason in world.dropped
        if record_type == "npc"
    )
    classic_only = [
        rec
        for rec in world.records["npc"].values()
        if rec.get("spawns") and all(s[3] == "classic" for s in rec["spawns"])
    ]
    assert classic_only, "the fixture has NPCs that only Classic places"


def test_classic_spawns_are_thinned_to_a_spread_per_map():
    from bastians_build.canon import (
        MAX_CLASSIC_SPAWNS_PER_MAP,
        farthest_points,
        prune_classic_spawns,
    )
    from bastians_build.model import World

    world = World(client="forever")
    points = [[1429, i / 40, (i % 7) / 7, "classic"] for i in range(40)]
    world.add("npc", 1, {"name": "Swarm", "spawns": list(points)})
    world.add("npc", 2, {"name": "Rare", "spawns": [[1429, 0.5, 0.5, "classic"]]})
    world.add("npc", 3, {"name": "Seen", "spawns": [*points[:20], [1429, 0.1, 0.1, "eq"]]})
    prune_classic_spawns(world)
    swarm = world.records["npc"][1]["spawns"]
    assert len(swarm) == MAX_CLASSIC_SPAWNS_PER_MAP and swarm[0] == points[0]
    assert len({(s[1], s[2]) for s in swarm}) == MAX_CLASSIC_SPAWNS_PER_MAP  # distinct, spread
    assert world.records["npc"][2]["spawns"] == [[1429, 0.5, 0.5, "classic"]]  # few: untouched
    assert world.records["npc"][3]["spawns"] == [[1429, 0.1, 0.1, "eq"]]  # a Forever place wins
    reasons = {reason for _, record_id, reason in world.dropped if record_id == 1}
    assert reasons == {"classic spawns thinned to 12 per map"}
    assert farthest_points([[1, 0, 0, "c"], [1, 1, 1, "c"], [1, 0.5, 0.5, "c"]], 2) == [
        [1, 0, 0, "c"],
        [1, 1, 1, "c"],
    ]


def test_zones_carry_the_map_type_when_the_source_has_it():
    """R5: UiMap.Type per zone, so the Zones list can tell a dungeon
    floor from a zone; None when the source has no type."""
    from bastians_build.canon import merge_zones

    s = Sources(client="retail")
    s.map_names = {37: "Elwynn Forest", 242: "Blackrock Depths", 13: "Eastern Kingdoms"}
    s.map_parents = {37: (13, 0), 242: (32, 0), 13: (947, 0)}
    s.map_types = {37: 3, 242: 4}
    world = World(client="retail")
    merge_zones(world, s)
    assert world.get("zone", 37)["mapType"] == 3
    assert world.get("zone", 242)["mapType"] == 4
    assert world.get("zone", 13)["mapType"] is None
    # the probe dump's maps carry `mapType` (P3); a map without one is left out
    dump = probe.ProbeDump.__new__(probe.ProbeDump)
    dump.maps = {37: {"name": "Elwynn Forest", "mapType": 3}, 13: {"name": "Eastern Kingdoms"}}
    assert probe.map_types(dump) == {37: 3}


def test_zones_the_client_lacks_are_named_from_the_retail_map_table():
    """(N10): dungeon quests name their dungeon by the retail map id
    (300 Razorfen Downs); the Forever client has no dungeon maps, so the zone showed as
    "zone:300". The retail table names it, marked `nameSrc` "retail"; without a name it stays
    unnamed, never invented."""
    from bastians_build.canon import name_unnamed_zones

    s = Sources(client="forever")
    s.fallback_map_names = {300: "Razorfen Downs", 37: "Elwynn Forest (retail)"}
    s.fallback_map_types = {300: 4}
    world = World(client="forever")
    world.add("zone", 37, {"name": "Elwynn Forest", "mapType": 3})
    world.add("zone", 300, {"questsA": 3})
    world.add("zone", 999, {"questsA": 1})
    assert name_unnamed_zones(world, s) == 1
    assert world.get("zone", 300)["name"] == "Razorfen Downs"
    assert world.get("zone", 300)["mapType"] == 4 and world.get("zone", 300)["nameSrc"] == "retail"
    assert world.get("zone", 37)["name"] == "Elwynn Forest"  # the client's own name wins
    assert world.get("zone", 999).get("name") is None
    assert any("retail map table" in n for n in world.notes)


def test_dungeons_join_the_world_with_their_bosses_loot_and_quests():
    """data.md "Dungeons": ForeverDB's dungeons become records, their bosses npcs, the loot players
    saw joins the boss (chance unknown), the quests point back, the zone is found by name."""
    world = build_world(fixture_sources())
    deadmines = world.get("dungeon", 36)
    assert deadmines["name"] == "The Deadmines" and deadmines["kind"] == "dungeon"
    assert (deadmines["levelLo"], deadmines["levelHi"], deadmines["levelReq"]) == (15, 25, 10)
    assert deadmines["zone"] == 1429  # "Elwynn Forest" by name
    assert deadmines["bosses"][0] == [1, 644, "Rhahk'Zor"]
    assert [872, 1, "s"] in deadmines["loot"] and deadmines["quests"] == [6, 166]
    assert deadmines["src"] == "forever"
    # a boss no other source knows is an npc now: named, flagged, in its dungeon
    boss = world.get("npc", 644)
    assert boss["name"] == "Rhahk'Zor" and "boss" in boss["flags"] and boss["dungeon"] == 36
    # the loot players saw drops from him, its chance unknown and never zero; the client-tied
    # item (label c) and the instance's unassigned loot stay on the dungeon record only
    assert [872, None] in boss["loot"] and [1185, None] in boss["loot"]
    assert all(row[0] != 2169 for row in boss["loot"]) and boss["lootSrc"] == "forever"
    assert all(row[0] != 5187 for row in world.get("npc", 639).get("loot") or [])
    # the dungeon quests know their dungeon; an unknown quest id is no error
    assert (
        world.get("quest", 6)["dungeon"] == 36 and world.get("quest", 6)["dungeonSrc"] == "forever"
    )
    # a zone name we do not know is a note, not a failure; the raid keeps its kind and size
    assert world.get("dungeon", 34).get("zone") is None
    assert any("Nowhere Known" in note for note in world.notes)
    assert world.get("dungeon", 249)["kind"] == "raid" and world.get("dungeon", 249)["size"] == 40


def test_a_boss_is_its_creature_never_its_encounter_number():
    """02.11.2026 (owner's retail screenshot: Dalaran's first boss shown as Gabrielle Chase):
    ForeverDB's boss numbers are encounter ids. The creature comes from Loot.lua; a boss without
    one keeps its name on the dungeon, links nowhere, and is a build note; the creature its number
    happens to be (VanCleef's 448 is Hogger) is never touched."""
    world = build_world(fixture_sources())
    deadmines = world.get("dungeon", 36)
    assert deadmines["bosses"] == [
        [1, 644, "Rhahk'Zor"],
        [2, None, "Mr. Smite"],
        [3, 639, "Edwin VanCleef"],
    ]
    assert world.get("dungeon", 249)["bosses"] == [[1, 10184, "Onyxia"]]
    hogger = world.get("npc", 448)
    assert hogger["name"] == "Hogger" and "boss" not in (hogger.get("flags") or [])
    assert hogger.get("dungeon") is None and hogger.get("lootSrc") != "forever"
    assert not {872, 1185, 5443, 2169, 5187} & {row[0] for row in hogger.get("loot") or []}
    assert world.get("npc", 1145) is None and world.get("npc", 1144) is None
    assert any("no creature known for ['Mr. Smite']" in n for n in world.notes)
    # the seen loot of an unlinked boss stays on the dungeon only (5443: Mr. Smite's)
    assert [5443, 2, "s"] in deadmines["loot"]
    assert all(
        5443 not in [r[0] for r in (n.get("loot") or [])] for n in world.records["npc"].values()
    )


def test_retail_does_not_link_forevers_own_dungeons_bosses():
    """A creature id of a dungeon only Forever has would be another creature on retail."""
    s = fixture_sources()
    s.client = "retail"
    s.fdb_dungeons = [
        foreverdb.DungeonRow(
            2999,
            "Ruins of Lordaeron",
            "dungeon",
            5,
            15,
            22,
            15,
            None,
            (foreverdb.DungeonBoss(1, 3353, "Witherfang"),),
            (),
            (),
        )
    ]
    s.fdb_dungeon_maps = []
    world = build_world(s)
    assert world.get("dungeon", 2999)["bosses"] == [[1, None, "Witherfang"]]
    s.client = "forever"
    world = build_world(s)
    assert world.get("dungeon", 2999)["bosses"] == [[1, 250483, "Witherfang"]]


def test_a_client_without_foreverdb_takes_the_dungeons_file_given(tmp_path):
    """data.md "Dungeons": the retail test client shows Forever's dungeons
    from ForeverDB's file handed over by path; a client that has ForeverDB keeps its own."""
    addons = tmp_path / "AddOns"
    shutil.copytree(FIXTURES / "everything_quests", addons / "EverythingQuests")
    paths = SourcePaths(
        addons=addons,
        cmangos=FIXTURES / "cmangos" / "classicdb_mini.sql.gz",
        probe=FIXTURES / "probe" / "2026-10-19-forever-fixture.lua",
        dungeons=FIXTURES / "foreverdb" / "Dungeons.lua",
    )
    s = load_sources("forever", paths)
    assert [d.id for d in s.fdb_dungeons] == [34, 36, 249]
    assert any(name.startswith("ForeverDB Dungeons.lua") for name in s.source_names)
    world = build_world(s)
    assert world.get("dungeon", 36)["name"] == "The Deadmines"


def test_the_floors_are_the_clients_dungeon_maps_with_the_boss_spots_placed_through_the_world():
    """data.md "Dungeons": the floors come
    from retail's UiMap tables (name, UiMap id, the art files' prefix and grid when the listfile
    names the tiles, the visible size); ForeverDB's boss spots and the door go through the world
    (the floor's scale and corner) onto the floor whose region and height band hold them. The
    Deadmines: boss 1 lies on floor 1 only, boss 3 on both floors' regions and floor 1's height
    band, the door on floor 2 only."""
    world = build_world(fixture_sources())
    d = world.get("dungeon", 36)
    assert d["floors"] == [
        {
            "n": "The Deadmines 1",
            "m": 291,
            "w": 1002,
            "h": 668,
            "a": "interface/worldmap/thedeadmines/thedeadmines1_",
            "g": [4, 3],
        },
        {"n": "The Deadmines 2", "m": 292, "w": 1002, "h": 668},
    ]
    assert d["bossSpots"] == [[1, 1, 38.59, 60.88], [3, 1, 52.7, 50.53]]
    assert d["door"] == [2, 60.22, 84.32]
    # an instance the client has no map of keeps ForeverDB's plates: the minimap tiles on
    # Forever, the bare plate on retail (the tiles are the Forever client's files)
    ony = world.get("dungeon", 249)
    assert ony["floors"] == [
        {"n": "Part 1", "w": 400, "h": 300},
        {"n": "Part 2", "w": 200, "h": 150, "t": [[300001, 0, 0, 200, 150, 1]]},
    ]
    assert ony["bossSpots"] == [[1, 2, 50.0, 50.0]]
    assert ony.get("door") is None and any("can't be read" in n for n in world.notes)
    s = fixture_sources()
    s.client = "retail"
    retail = build_world(s).get("dungeon", 249)
    assert retail["floors"][1] == {"n": "Part 2", "w": 200, "h": 150}


def test_a_boss_several_floors_could_show_stays_off_the_maps_with_a_note():
    """Unknown is not zero: when the floors of a spire share their region and no height band
    tells them apart, the boss gets no pin and the report says so."""
    s = fixture_sources()
    for f in s.floor_art[36]:
        object.__setattr__(
            f,
            "regions",
            tuple((*r[:2], -10000.0, *r[3:5], 1000000.0) for r in s.floor_art[36][0].regions),
        )
    world = build_world(s)
    d = world.get("dungeon", 36)
    assert d.get("bossSpots") is None and d.get("door") is None
    assert any("bosses [1, 3] have no floor" in n for n in world.notes)


def test_a_quest_finds_its_dungeon_where_its_targets_spawn():
    """data.md "Dungeons", catalog review A2.1 (07.11.2026): a quest ForeverDB did not confirm is a
    dungeon quest when its kill target or every dropper of its item lives in one instance only;
    an outside dropper or a second instance makes no answer; ForeverDB's word stays."""
    from bastians_build.sources.cmangos import LootRow, SpawnRow

    world = World(client="forever")
    world.add("dungeon", 36, {"name": "The Deadmines"})
    world.add("dungeon", 33, {"name": "Shadowfang Keep"})
    world.add("quest", 1, {"objectives": [["kill", "npc:643", 1]]})  # Sneed, inside only
    world.add("quest", 2, {"requiredItems": [[5000, 1]]})  # an item only Deadmines creatures drop
    world.add("quest", 3, {"requiredItems": [[5001, 1]]})  # an item a world creature drops too
    world.add("quest", 4, {"objectives": [["kill", "npc:643", 1], ["kill", "npc:3887", 1]]})
    world.add("quest", 5, {"objectives": [["kill", "npc:448", 1]]})  # Hogger, outside
    world.add(
        "quest", 6, {"objectives": [["kill", "npc:643", 1]], "dungeon": 33, "dungeonSrc": "forever"}
    )
    world.add("quest", 7, {"objectives": [["kill", "npc:643", 1], ["talk", "npc:448", 1]]})
    s = Sources(client="forever", build="test")

    def spawn(entry, map_id):
        return SpawnRow("creature", entry, entry, map_id, 0.0, 0.0, None)

    s.cm_spawns = [spawn(643, 36), spawn(644, 36), spawn(3887, 33), spawn(448, 0), spawn(1000, 0)]
    s.cm_loot = [
        LootRow("reference", 50000, 5000, 10.0, False, 1, 1, 1, None),  # a shared list with 5000
        LootRow("creature", 644, None, 100.0, False, 0, 1, 1, 50000),  # Rhahk'Zor rolls the list
        LootRow("creature", 643, 5001, 20.0, False, 0, 1, 1, None),
        LootRow("creature", 1000, 5001, 1.0, False, 0, 1, 1, None),  # a world creature too
    ]
    assert derive_dungeon_quests(world, s) == 3
    assert (world.get("quest", 1)["dungeon"], world.get("quest", 1)["dungeonSrc"]) == (
        36,
        "classic",
    )
    assert world.get("quest", 2)["dungeon"] == 36  # through the shared loot list
    assert world.get("quest", 3).get("dungeon") is None  # a dropper outside: not a dungeon item
    assert world.get("quest", 4).get("dungeon") is None  # two instances: no answer
    assert world.get("quest", 5).get("dungeon") is None
    assert (world.get("quest", 6)["dungeon"], world.get("quest", 6)["dungeonSrc"]) == (
        33,
        "forever",
    )
    assert world.get("quest", 7)["dungeon"] == 36  # an outside target beside it is allowed
    assert any("3 dungeon quests derived" in n and "1 quests touch two" in n for n in world.notes)
    # nothing to derive without spawns or dungeons
    assert derive_dungeon_quests(World(client="forever"), s) == 0
