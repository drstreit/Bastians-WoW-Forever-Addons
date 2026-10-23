"""The retail world from the AllTheThings and ItemDB reader fixtures (B4.2): what each source
contributes, what stays unknown, what is dropped and why, and that the packs build."""

from pathlib import Path

import pytest

from bastians_build.build import build
from bastians_build.canon import Sources, build_world, faction_mask, id_mask
from bastians_build.config import load_config
from bastians_build.sources.allthethings import read_allthethings
from bastians_build.sources.clientdump import read_quest_titles
from bastians_build.sources.itemdb import read_itemdb

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures" / "sources"


def retail_sources() -> Sources:
    s = Sources(client="retail", build="fixture")
    s.att = read_allthethings(FIXTURES / "allthethings", "Standard")
    s.idb = read_itemdb(FIXTURES / "itemdb", "Retail")
    s.map_names = {13: "Eastern Kingdoms", 37: "Elwynn Forest", 425: "Northshire", 1: "Durotar"}
    s.map_parents = {13: (947, 0), 37: (13, 0), 425: (37, 0), 1: (12, 1)}
    s.source_names = ["AllTheThings 5.4.3 (Standard)", "ItemDB-v1.6.0 (Retail)"]
    return s


@pytest.fixture(scope="module")
def world():
    return build_world(retail_sources())


def test_masks():
    assert id_mask([1, 32]) == (1 | 1 << 31, 0)
    assert id_mask([1, 34, 85]) == (1, 2)  # ids above 32 do not fit a 32-bit mask
    assert faction_mask("A") & 1 and not faction_mask("A") & 2
    assert faction_mask("H") & 2 and faction_mask(None) == 0


def test_quest_from_allthethings_has_places_gates_and_no_name(world):
    q = world.get("quest", 28762)
    assert "name" not in q and "level" not in q  # the client supplies the title at runtime
    assert q["starts"] == ["npc:197"] and q["startPlaces"] == [[425, 0.335, 0.531, "att"]]
    assert q["races"] == 1 | 1 << 31 and q["classes"] == 2
    assert q["zone"] == 425 and q["src"] == "att"
    assert q["objectives"] == [["target", "npc:49871", 0]]
    assert q["rewards"] == {"items": [[57255, None]], "src": "att"}  # one item: given
    q = world.get("quest", 26389)
    assert q["preAny"] == [28817, 29083] and "pre" not in q  # sqreq 1 of 2
    assert q["requiredItems"] == [[58361, None]]
    assert q["rewards"] == {"choices": [[57247, None], [999, None]], "src": "att"}
    assert q["races"] == id_mask([1, 3, 4, 7, 11, 22, 25, 29, 30, 32, 85, 86])[0]
    q = world.get("quest", 29078)
    assert q["minLevel"] == 3 and q["starts"] == ["object:2076", "item:57247"]
    assert q["flags"] == ["daily", "repeatable"] and q["excl"] == [28762]
    q = world.get("quest", 4641)  # faction only: every Horde race within the mask
    assert q["races"] == faction_mask("H") and q["flags"] == ["worldquest"]
    assert q["zone"] == 1


def test_removed_and_never_implemented_quests_are_dropped(world):
    assert world.get("quest", 5261) is None and world.get("quest", 999999) is None
    reasons = {(t, i): r for t, i, r in world.dropped}
    assert reasons[("quest", 5261)] == "AllTheThings: removed from the game"
    assert reasons[("quest", 999999)] == "AllTheThings: never implemented"
    assert reasons[("npc", 999998)] == "AllTheThings: never implemented"
    assert world.get("quest", 783) is not None  # obtainable in one place of the tree


def test_client_task_titles_name_quests_that_have_none():
    """D1 (22.10.2026): the client's QuestV2CliTask titles fill `name` where no source had one;
    a title for an unknown quest adds no record; the report counts what stays unnamed."""
    s = retail_sources()
    s.quest_titles = read_quest_titles(FIXTURES / "clientdump" / "QuestV2CliTask.json")
    w = build_world(s)
    assert w.get("quest", 26389)["name"] == "WANTED: The Fixture Poster"
    assert w.get("quest", 4641)["name"] == "Padded Title"
    assert "name" not in w.get("quest", 28762)  # no title: the client names it at runtime
    assert w.get("quest", 424242) is None
    assert any(n.startswith("QuestV2CliTask: 2 quests named") for n in w.notes)
    assert not any("QuestV2CliTask" in n for n in build_world(retail_sources()).notes)


def test_quest_races_above_the_mask_are_counted(world):
    assert any("race ids above 32" in n for n in world.notes)


def test_npc_places_names_and_flags(world):
    corina = world.get("npc", 54)  # ATT place and ItemDB name, side and place
    assert corina["name"] == "Corina Steele" and corina["faction"] == "A"
    assert corina["spawns"] == [[37, 0.415, 0.659, "att"], [37, 0.415, 0.659, "tdb"]]
    assert corina["zone"] == 37 and corina["src"] == "att"
    giver = world.get("npc", 197)  # placed through the quests it gives
    assert giver["spawns"] == [[425, 0.335, 0.531, "att"], [37, 0.334, 0.547, "att"]]
    assert giver["flags"] == ["questgiver"] and "name" not in giver
    flesh = world.get("npc", 3)  # ItemDB only: hostile to both, three points
    assert flesh["name"] == "Flesh Eater" and "faction" not in flesh
    assert len(flesh["spawns"]) == 3 and flesh["spawns"][0] == [47, 0.178, 0.36, "tdb"]
    assert flesh["zone"] == 47 and flesh["src"] == "tdb"


def test_objects_and_nodes(world):
    cauldron = world.get("object", 2076)
    assert cauldron["name"] == "Atal'Gral, Zuldazar"  # ATT's object names
    # its own places, then the place of the quest it gives (29078)
    assert cauldron["spawns"] == [
        [37, 0.422, 0.435, "att"],
        [37, 0.419, 0.441, "att"],
        [425, 0.335, 0.531, "att"],
    ]
    chest = world.get("object", 2846)
    assert chest["name"] == "Tattered Chest" and len(chest["spawns"]) == 3
    assert chest["loot"] == [[38, 100.0]] and chest["lootSrc"] == "tdb"
    herb = world.get("node", 252)  # a gathering object is a node, not an object
    assert world.get("object", 252) is None
    assert herb["name"] == "I Should not be here B" and herb["kind"] == "herb"
    assert herb["profession"] == "Herbalism" and herb["item"] == 38 and "spawns" not in herb


def test_items_are_the_referenced_ones_with_names_facts_and_sources(world):
    shirt = world.get("item", 38)
    assert shirt["name"] == "Recruit's Shirt" and shirt["quality"] == 2 and shirt["class"] == 4
    assert ["object:2846", 100.0, None] in shirt["drops"]  # equal chances sort by ref
    assert ["node:252", 100.0, None] in shirt["drops"] and shirt["dropsSrc"] == "tdb"
    assert "sell" not in shirt and "buy" not in shirt  # ItemDB retail has no prices
    cloth = world.get("item", 2589)
    assert cloth["name"] == "Linen Cloth" and "quality" not in cloth  # a name without a core row
    assert cloth["drops"][0] == ["object:2039", 58.64, None]  # highest chance first
    assert ["npc:61678", 50.0, None] in cloth["drops"]
    reaver = world.get("npc", 61678)
    assert reaver["name"] == "Corrupted Reaver" and reaver["loot"] == [[2589, 50.0]]
    assert "spawns" not in reaver  # only an instance place
    vendor = world.get("npc", 18672)
    assert vendor["vendor"] == [[38, None, None, None, "tdb"]] and "vendor" in vendor["flags"]
    reward = world.get("item", 57255)  # a quest reward ItemDB does not name: the record exists
    assert reward is not None and "name" not in reward and reward["src"] == "tdb"
    # named in ItemDB but referenced by nothing (ATT's vendor lists are not read): not packed
    assert world.get("item", 25) is None and world.get("item", 35) is None


def test_zone_statistics_count_both_factions(world):
    northshire = world.get("zone", 425)  # 783, 28762, 26389 Alliance; 29078, 8254 ungated
    assert northshire["questsA"] == 5 and northshire["questsH"] == 2
    durotar = world.get("zone", 1)  # 4641 Horde; 783 keeps its first zone (Northshire)
    assert durotar["questsH"] == 1 and durotar["questsA"] == 0


def test_retail_world_builds_within_the_schemas(tmp_path, world):
    result = build(world, load_config(), tmp_path)
    assert result.ok, result.problems
    names = {p.pack.name for p in result.packs}
    assert {"world", "quests", "items"} <= names
    text = (tmp_path / "Bastians_Data_Quests" / "Generated" / "Quests.lua").read_text("utf-8")
    assert 'client = "retail"' in text and "AllTheThings 5.4.3" in text
