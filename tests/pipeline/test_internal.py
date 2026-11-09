"""Internal records leave the pack (AT7 D2, data.md "Internal records"): a developers' mark in the
name or a creature nobody can select, and nothing real that refers to it."""

import pytest

from bastians_build.internal import NOT_SELECTABLE, drop_internal, marked, referenced
from bastians_build.model import World
from bastians_build.sources.cmangos import read_lines


@pytest.mark.parametrize(
    "name",
    [
        "[UNUSED] Henria Derth",
        "Loranna Dawnfyre UNUSED (Reuse me)",
        "Unused Black Night Elf Pants",
        "Deprecated Work Shirt",
        "Vessel of Rebirth DEPRECATED",
        "Lok'delar, Stave of the Ancient Keepers DEP",
        "[PH] Nature Resist Potion [DEP]",
        "Test Stationery",
        "Warlock (TEST)",
        "Weapon of Mass Destruction (test)",
        "pnagle's test dude",
        "Ribbon Pole Debug Target",
        "Spirit Healer (DND)",
        "Hidden Belt (DNT)",
        "Placeholder - Jasperlode Mine",
        "(OLD)Medium Throwing Knife",
        "Large Moneybag (old)",
        "<TXT>Crown Guard Capture Quest Doodad",
        "Monster - Sword2H, Broadsword",
    ],
)
def test_a_developers_mark_is_seen(name: str):
    assert marked(name)


@pytest.mark.parametrize(
    "name",
    [
        "Test of Faith",
        "The Test of Righteousness",
        "Field Testing Kit",
        "High Test Eternium Fishing Line",
        "Testing Equipment",
        "Unstable Trigger",
        "Target Dummy",
        "Gold Dust Exchange",
        "Deputy Willem",
        "Old Blanchy",
        "Bolder Mace",
        "Monster Slayer's Axe",
        None,
    ],
)
def test_a_real_name_is_not_a_mark(name):
    assert not marked(name)


def world() -> World:
    w = World(client="forever")
    w.records = {
        "npc": {
            1: {"name": "[UNUSED] Greeby Mudwhisker TEST", "loot": [[20, 5.0]], "flags": ["elite"]},
            2: {"name": "World Trigger", "spawns": [[1453, 0.5, 0.5, "classic"]]},
            3: {
                "name": "Nefarian",
                "loot": [[21, 100.0]],
                "flags": ["boss"],
            },  # selectable by script
            4: {"name": "Lunar Firework Credit Marker"},  # a quest counts it
            5: {"name": "Marshal Dughan", "flags": ["questgiver"]},
            6: {"name": "[UNUSED] Sulhasa"},  # marked, but a quest starts with it
        },
        "item": {
            20: {"name": "Deprecated Work Shirt"},
            21: {"name": "Monster - Sword2H, Broadsword"},  # in a loot table: it stays
            22: {"name": "Test Stationery"},
            23: {"name": "DEPRECATED ITEM"},  # a quest asks for it
            24: {"name": "Deprecated Maiden's Anguish", "drops": [["npc:3", 2.0]]},
            25: {"name": "Linen Cloth"},
        },
        "object": {
            30: {"name": "[PH] Alliance A1 Tower Banner BIG"},
            31: {"name": "TEST Chest", "loot": [[25, 100.0]]},
            32: {"name": "Mailbox"},
        },
        "quest": {
            100: {
                "name": "Lunar Fireworks",
                "starts": ["npc:6"],
                "objectives": [["slay", "npc:4", 8]],
                "requiredItems": [[23, 1]],
            },
        },
    }
    return w


def test_what_something_real_refers_to():
    refs = referenced(world())
    assert refs["npc"] == {4, 6}
    assert refs["item"] == {20, 21, 23, 25}  # two loot tables and the quest's item
    assert refs["object"] == set()


def test_internal_records_leave_and_what_is_referred_to_stays():
    w = world()
    unit = {2: NOT_SELECTABLE | 0x300, 3: NOT_SELECTABLE, 4: NOT_SELECTABLE, 5: 0x1200}
    counts = drop_internal(w, unit)
    # the marked creature goes even with loot and a rank; the trigger goes; the boss and the
    # quest's credit marker stay, and so does the marked giver of a quest
    assert sorted(w.records["npc"]) == [3, 4, 5, 6]
    # 21 is in a kept loot table, 23 in a quest, 24 has a drop; the test item goes, and so does
    # the shirt that only the removed creature dropped
    assert sorted(w.records["item"]) == [21, 23, 24, 25]
    assert sorted(w.records["object"]) == [31, 32]  # a marked object with loot stays
    assert counts == {"npc": 2, "item": 2, "object": 1}
    assert w.notes == ["internal records left out (data.md): 2 npc, 2 item, 1 object"]
    assert drop_internal(w, unit) == {
        "npc": 0,
        "item": 0,
        "object": 0,
    }  # running twice changes nothing
    assert len(w.notes) == 1


def test_without_the_classic_flags_only_the_names_decide():
    w = world()
    drop_internal(w)
    assert 2 in w.records["npc"] and 1 not in w.records["npc"]


def test_a_dump_without_the_unit_flags_still_reads():
    dump = [
        "CREATE TABLE `creature_template` (",
        "  `Entry` int,",
        "  `Name` char,",
        ") ENGINE=x;",
        "INSERT INTO `creature_template` VALUES (1,'Hogger');",
    ]
    rows = read_lines(dump, {"creature_template": ("Entry", "Name", "UnitFlags")})
    assert rows["creature_template"] == [{"Entry": 1, "Name": "Hogger", "UnitFlags": None}]
    with pytest.raises(KeyError):
        read_lines(dump, {"creature_template": ("Entry", "Rank")})
