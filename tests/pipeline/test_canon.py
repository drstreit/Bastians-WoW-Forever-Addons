"""The canonical merge over the real-format reader fixtures (B3.3): precedence, labels, drops."""

import shutil
from pathlib import Path

import pytest

from bastians_build.build import build, render_report
from bastians_build.canon import (
    Sources,
    build_world,
    clean_name,
    fix_loot_objectives,
    level_band,
    localized_name,
    object_kind,
    zone_statistics,
)
from bastians_build.config import load_config
from bastians_build.load import SourcePaths, load_sources
from bastians_build.model import World
from bastians_build.sources import cmangos, foreverdb, probe, questiedb
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
