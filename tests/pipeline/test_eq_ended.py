"""Everything Quests 2.17.0's `ended`, `daily` and `giverSide` ("use the new
fields where it helps"): flags the Quests app already reads (ADR 0051) and the races of a quest
whose givers serve one faction."""

from bastians_build.canon import (
    ALLIANCE_RACES,
    HORDE_RACES,
    Sources,
    merge_eq_gates,
    merge_quests,
    side_by_giver,
)
from bastians_build.model import World
from bastians_build.sources.everything_quests import assemble


def built(available: dict, records: dict | None = None) -> tuple[World, Sources]:
    world = World(client="forever", build="test", sources=[])
    for typ, recs in (records or {}).items():
        world.records[typ] = {k: dict(v) for k, v in recs.items()}
    s = Sources(client="forever")
    s.eq = assemble(available)
    return world, s


def test_the_reader_takes_the_three_tables():
    eq = assemble(
        {
            "names": {8041: "Strength of Mount Mugamba", 5: "Jitters"},
            "ended": {8041: 4, 787: 1},
            "daily": {5: 1},
            "giverSide": {376: 2, 988: 1, 99: 7},
        }
    )
    assert eq.quests[8041].ended == 4 and eq.quests[787].ended == 1
    assert eq.quests[5].ended is None and eq.quests[5].daily
    assert not eq.quests[8041].daily
    assert eq.giver_sides == {376: "A", 988: "H"}  # an unknown side is no side


def test_an_ended_quest_gets_the_flag_unless_players_took_it_or_an_event_decides():
    world, s = built(
        {
            "names": {1: "a", 2: "b", 3: "c", 4: "d", 5: "e", 6: "f"},
            "ended": {1: 1, 2: 2, 3: 3, 4: 4, 5: 4, 6: 2},
        }
    )
    merge_quests(world, s)
    q = world.records["quest"]
    q[5]["seenBy"] = 3  # ForeverDB saw players take it: seen beats listed
    q[6]["holiday"] = "Hallow's End"  # a recurring event: the event decides while it runs
    merge_eq_gates(world, s)
    assert q[1]["flags"] == ["absent"] and q[4]["flags"] == ["absent"]
    assert q[2]["flags"] == ["dormant"] and q[3]["flags"] == ["dormant"]
    assert not q[5].get("flags") and not q[6].get("flags")
    assert any("4 quests not offered today" in n for n in world.notes)
    merge_eq_gates(world, s)  # twice: the same flags, counted once
    assert q[1]["flags"] == ["absent"]


def test_a_daily_quest_is_repeatable_and_daily():
    world, s = built({"names": {9: "Fish"}, "daily": {9: 1}})
    merge_quests(world, s)
    assert world.records["quest"][9]["flags"] == ["daily", "repeatable"]


def test_a_quest_whose_givers_serve_one_faction_takes_its_races():
    world, s = built(
        {"giverSide": {376: 2, 988: 1, 989: 1}},
        {
            "npc": {376: {}, 988: {"faction": "H"}, 989: {}},
            "quest": {
                10: {"starts": ["npc:376"]},  # Alliance's
                11: {"starts": ["npc:988", "npc:989"]},  # Horde's, two givers
                12: {"starts": ["npc:376", "npc:988"]},  # both: stays open
                13: {"starts": ["npc:376", "object:5"]},  # an object too: stays open
                14: {"starts": ["npc:376"], "races": 1},  # already gated: kept
                15: {"starts": ["npc:777"]},  # a giver not in the list
                16: {},
            },
        },
    )
    assert side_by_giver(world, s) == 2
    q = world.records["quest"]
    assert q[10]["races"] == ALLIANCE_RACES and q[11]["races"] == HORDE_RACES
    assert not q[12].get("races") and not q[13].get("races") and not q[15].get("races")
    assert q[14]["races"] == 1 and not q[16].get("races")
    assert world.records["npc"][376]["faction"] == "A"  # a giver without a faction takes it
    assert world.records["npc"][988]["faction"] == "H"


def test_a_one_sided_givers_start_place_names_its_side():
    """The Islander: offered by the warrior trainers of both factions; each row says whose."""
    a = 2786 * 10**9 + 1 * 10**8 + 8000 * 10**4 + 3000  # npc 2786 (Alliance) at 0.8, 0.3
    h = 2787 * 10**9 + 1 * 10**8 + 4000 * 10**4 + 7000  # npc 2787 (Horde) at 0.4, 0.7
    n = 9 * 10**9 + 1 * 10**8 + 5000 * 10**4 + 5000  # npc 9: no giverSide
    world, s = built(
        {
            "names": {1718: "The Islander"},
            "start": {1718: {1453: [a], 1454: [h], 1429: [n]}},
            "giverSide": {2786: 2, 2787: 1},
        }
    )
    merge_quests(world, s)
    rows = sorted(world.records["quest"][1718]["startPlaces"])
    assert rows == [
        [1429, 0.5, 0.5, "eq"],
        [1453, 0.8, 0.3, "eq", "A"],
        [1454, 0.4, 0.7, "eq", "H"],
    ]


def test_without_everything_quests_nothing_changes():
    world = World(client="forever", build="test", sources=[])
    world.records["quest"] = {1: {"starts": ["npc:376"]}}
    s = Sources(client="forever")
    merge_eq_gates(world, s)
    assert side_by_giver(world, s) == 0
    assert world.records["quest"][1] == {"starts": ["npc:376"]}
