"""Everything Quests reader: the packed encodings of the file headers, and the trimmed fixture."""

from pathlib import Path

import pytest

from bastians_build.sources.everything_quests import (
    assemble,
    decode_categories,
    decode_coord,
    decode_gates,
    decode_objective,
    decode_source_place,
    decode_spawn,
    read_everything_quests,
)

FIXTURE = (
    Path(__file__).resolve().parents[3] / "tests" / "fixtures" / "sources" / "everything_quests"
)


def test_decode_spawn_matches_the_header_example():
    # Data/QuestSpawns_Forever.lua: [6]={[1429]={1357524825}}
    place = decode_spawn(1429, 1357524825)
    assert (place.ui_map_id, place.kind, place.objective_mask, place.entrance) == (
        1429,
        "loot",
        1,
        False,
    )
    assert (place.x, place.y) == (0.5752, 0.4825)
    entrance = decode_spawn(1429, 1_700_000_000 + 12340000 + 5678)
    assert (
        entrance.kind == "loot"
        and entrance.entrance is True
        and (entrance.x, entrance.y) == (0.1234, 0.5678)
    )


def test_decode_coord_is_the_same_point_with_the_map_in_front():
    # Data/QuestCoords_Forever.lua: [6]=142957524825 (the quest advances where its loot spot is)
    place = decode_coord(142957524825)
    assert (place.ui_map_id, place.x, place.y, place.kind) == (1429, 0.5752, 0.4825, "progress")


def test_decode_source_place():
    place = decode_source_place(1429, 823 * 10**9 + 1 * 10**8 + 4812 * 10**4 + 4270)
    assert (place.source_id, place.kind, place.x, place.y, place.entrance) == (
        823,
        "npc",
        0.4812,
        0.427,
        False,
    )
    item = decode_source_place(1429, 3 * 10**8 + 10 * 10**4 + 20)
    assert item.kind == "item" and item.source_id is None
    door = decode_source_place(1429, 261 * 10**9 + 6 * 10**8)
    assert door.kind == "object" and door.entrance is True and door.source_id == 261


def test_decode_gates_objective_categories():
    gates = decode_gates(5 * 10**11 + 7 * 10**9 + 1 * 10**8 + 1101 * 10**4 + 4)
    assert (gates.required_level, gates.quest_level, gates.special_flags) == (5, 7, 1)
    assert (gates.required_races, gates.required_classes, gates.repeatable) == (1101, 4, True)
    objective = decode_objective(110000095)  # Data/QuestNPCs_Forever.lua: [12]={110000095,10000504}
    assert (objective.index, objective.kind, objective.npc_id) == (1, "slay", 95)
    assert decode_objective(30000103) == decode_objective(30000103)
    assert decode_objective(30000103).kind == "loot" and decode_objective(30000103).npc_id == 103
    assert decode_categories(12) == {"event", "class"} and decode_categories(0) == set()


def test_assemble_is_pure_and_merges_all_tables():
    data = assemble(
        {
            "names": {62: "The Fargodeep Mine"},
            "gates": {62: 5 * 10**11 + 7 * 10**9},
            "start": {62: {1429: [240 * 10**9 + 1 * 10**8 + 4200 * 10**4 + 6500]}},
            "pre": {62: 7},
            "preAll": {62: [5, 6]},
            "chain": {62: 76},
            "skill": {76: 186 * 10**4 + 50},
            "minRep": {76: 72 * 10**6 + 4},
        },
        turn_in={62: {1429: [240 * 10**9 + 1 * 10**8 + 4200 * 10**4 + 6500]}},
        coords={62: 142938008200},
        sources={"npc": {240: "Marshal Dughan"}, "obj": {}},
        npcs={62: [30000103]},
        categories={62: 4},
        spawns={62: {1429: [1357524825]}},
        holidays={"event": {62: 2}, "window": {}},
        holiday_names=["Lunar Festival", "Love is in the Air"],
    )
    q = data.quests[62]
    assert (
        q.name == "The Fargodeep Mine" and q.gates.required_level == 5 and q.gates.quest_level == 7
    )
    assert q.starts[0].source_id == 240 and q.turn_ins[0].kind == "npc"
    assert (q.coord.ui_map_id, q.coord.x, q.coord.y) == (1429, 0.38, 0.82)
    assert q.pre_any == [7] and q.pre_all == [5, 6] and q.chain == 76
    assert q.objectives[0].npc_id == 103 and q.categories == {"event"}
    assert q.spawns[0].objective_mask == 1 and q.holiday == "Love is in the Air"
    assert data.quests[76].skill == (186, 50) and data.quests[76].min_rep == (72, 4)
    assert data.npc_names == {240: "Marshal Dughan"} and data.object_names == {}
    assert list(data.quests) == [62, 76]


@pytest.mark.skipif(not FIXTURE.is_dir(), reason="fixture not generated yet (tools/eq_fixture.py)")
def test_fixture_in_the_real_format():
    data = read_everything_quests(FIXTURE, "Forever")
    assert data.version is not None
    assert {6, 7, 62, 76, 176} <= set(data.quests)
    hogger = data.quests[176]
    assert hogger.name == 'Wanted:  "Hogger"'  # two spaces: what EQ ships; canon normalises later
    assert (
        hogger.starts and hogger.starts[0].kind == "object" and hogger.starts[0].ui_map_id == 1429
    )
    assert hogger.turn_ins and hogger.turn_ins[0].kind == "npc"
    assert hogger.spawns and all(p.ui_map_id == 1429 for p in hogger.spawns)
    assert all(0 <= p.x <= 1 and 0 <= p.y <= 1 for q in data.quests.values() for p in q.spawns)
    assert data.quests[62].gates is not None and data.quests[62].gates.quest_level == 7
    assert any(name == "Marshal Dughan" for name in data.npc_names.values())
    light = read_everything_quests(FIXTURE, "Forever", spawns=False)
    assert light.quests[176].spawns == [] and light.quests[176].name == hogger.name
