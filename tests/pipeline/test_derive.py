"""The quest graph indexes (B11.1): start and turn-in maps, followers and chain components, as
Quests' Logic.lua derives them when a pack lacks them. A synthetic world, so every rule shows."""

from bastians_build.derive import (
    BUILDERS,
    chain_from,
    chain_members,
    quest_followers,
    quests_by_start,
    quests_by_turn_in,
)
from bastians_build.model import World


def world() -> World:
    w = World(client="forever")
    w.add("quest", 1, {"name": "A", "zone": 10, "endPlaces": [[30, 0.5, 0.5]]})
    w.add("quest", 2, {"name": "B", "startPlaces": [[20, 0.1, 0.2]], "pre": [1]})
    w.add("quest", 3, {"name": "C", "parent": 1, "chain": 4, "preAny": [1]})  # no place, no zone
    w.add("quest", 4, {"name": "D", "zone": 10})
    w.add("quest", 5, {"name": "E", "zone": 11, "pre": [99]})  # 99 is not a quest
    w.add("quest", 6, {"name": "F", "zone": 11, "chain": 7})
    w.add("quest", 7, {"name": "G", "zone": 11})
    w.add("quest", 8, {"name": "H", "zone": 11, "startPlaces": [[20, 0.3, 0.3]]})  # given elsewhere
    return w


def test_start_and_turn_in_maps_follow_the_zone_and_the_first_place():
    w = world()
    # 8 belongs to zone 11 but its giver stands on map 20: both zone pages list it
    assert quests_by_start(w) == {10: [1, 4], 11: [5, 6, 7, 8], 20: [2, 8]}
    # 1 ends elsewhere, 2 ends where it starts, 3 has no map at all
    assert quests_by_turn_in(w) == {10: [4], 11: [5, 6, 7, 8], 20: [2, 8], 30: [1]}
    # every quest handed in where it starts (retail): the table is left out, byStart serves both
    del w.records["quest"][1]["endPlaces"]
    assert quests_by_turn_in(w) == {}


def test_followers_list_who_needs_a_quest_and_what_it_chains_into():
    assert quest_followers(world()) == {1: [2, 3], 3: [4], 6: [7], 99: [5]}


def test_chain_components_join_known_quests_only_and_root_at_the_smallest_id():
    w = world()
    assert chain_members(w) == {1: [1, 2, 3, 4], 6: [6, 7]}  # 5's only edge leads nowhere
    assert chain_from(w) == {4: [3], 7: [6]}


def test_the_indexes_are_registered():
    for name in (
        "quest.byStart",
        "quest.byTurnIn",
        "quest.followers",
        "quest.chainMembers",
        "quest.chainFrom",
    ):
        assert name in BUILDERS
