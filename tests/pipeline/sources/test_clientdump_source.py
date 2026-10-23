"""clientdump TaxiNodes JSON -> flight masters (route.md, B9.2): faction bits, continents and
dummies."""

from pathlib import Path

import pytest

from bastians_build.canon import Sources, build_world
from bastians_build.sources.clientdump import (
    ClientDumpError,
    faction_of,
    read_quest_titles,
    read_taxi_nodes,
)
from bastians_build.sources.probe import Transform

FIXTURE = Path(__file__).resolve().parents[2] / "fixtures" / "sources" / "clientdump"


def test_faction_bits():
    assert (faction_of(1025), faction_of(1026), faction_of(1027), faction_of(1024)) == (
        "A",
        "H",
        "both",
        None,
    )


def test_real_flight_masters_are_kept_and_dummies_dropped_with_a_reason():
    dump = read_taxi_nodes(FIXTURE / "TaxiNodes.json")
    assert dump.build == "1.60.1.70450"
    assert [(n.id, n.name, n.faction, n.continent) for n in dump.nodes] == [
        (2, "Stormwind, Elwynn", "A", 0),
        (4, "Sentinel Hill, Westfall", "A", 0),
        (23, "Orgrimmar, Durotar", "H", 1),
        (80, "Ratchet, The Barrens", "both", 1),
    ]
    stormwind = dump.nodes[0]
    assert (stormwind.wx, stormwind.wy) == (-8832.77, 478.62)  # world X north, Y west
    reasons = {d[0]: d[2] for d in dump.dropped}
    assert "dummy" in reasons[1] and "dummy" in reasons[3]
    assert "continent 30" in reasons[300]


def test_quest_titles_come_from_the_client_task_table():
    """D1 (22.10.2026): QuestV2CliTask is the only retail table with quest titles; empty titles
    are skipped, padding trimmed, a wrong table rejected."""
    titles = read_quest_titles(FIXTURE / "QuestV2CliTask.json")
    assert titles == {
        26389: "WANTED: The Fixture Poster",
        424242: "A Task Nobody Can Take",
        4641: "Padded Title",
    }
    with pytest.raises(ClientDumpError, match="QuestV2CliTask"):
        read_quest_titles(FIXTURE / "TaxiNodes.json")


def test_bad_dumps_are_rejected(tmp_path):
    bad = tmp_path / "x.json"
    bad.write_text("{", encoding="utf-8")
    with pytest.raises(ClientDumpError, match="not JSON"):
        read_taxi_nodes(bad)
    bad.write_text('{"table": "Map", "rows": []}', encoding="utf-8")
    with pytest.raises(ClientDumpError, match="TaxiNodes"):
        read_taxi_nodes(bad)


def test_flightpath_records_carry_world_yards_and_a_place_when_transforms_exist():
    dump = read_taxi_nodes(FIXTURE / "TaxiNodes.json")
    # a transform whose map contains Stormwind's node only
    stormwind = Transform(1453, 0, -9000.0, 0.0, 400.0, 300.0, 400.0, 0.0, True)
    s = Sources(client="forever", taxi=dump.nodes, transforms={1453: stormwind})
    world = build_world(s)
    rec = world.records["flightpath"][2]
    assert (rec["name"], rec["faction"], rec["continent"], rec["wx"], rec["wy"]) == (
        "Stormwind, Elwynn",
        "A",
        0,
        -8832.77,
        478.62,
    )
    assert rec["spawns"][0][0] == 1453 and 0 <= rec["spawns"][0][1] <= 1
    assert (
        "spawns" not in world.records["flightpath"][4]
    )  # outside every map: unknown stays unknown
    assert any("flightpath 4" in note for note in world.notes)
    assert "flightpaths placed: 0 on the map their name gives, 1 by the containing rectangle" in (
        world.notes
    )
    plain = build_world(Sources(client="forever", taxi=dump.nodes))
    assert "spawns" not in plain.records["flightpath"][2] and plain.notes == []


def test_flightpath_place_follows_the_node_name_before_the_containing_rectangle():
    """Sentinel Hill's node also lies in a wide Elwynn-like rectangle that would win by
    centrality; the name "Sentinel Hill, Westfall" puts it on Westfall (coordinates.md)."""
    dump = read_taxi_nodes(FIXTURE / "TaxiNodes.json")
    sentinel = next(n for n in dump.nodes if n.name == "Sentinel Hill, Westfall")
    # Westfall: the node sits at its edge; the wide map holds it near the centre
    westfall = Transform(
        1436, 0, sentinel.wx + 100.0, 0.0, -1000.0, sentinel.wy + 500.0, -1000.0, 0.0, True
    )
    wide = Transform(
        1429, 0, sentinel.wx + 1200.0, 0.0, -2400.0, sentinel.wy + 1200.0, -2400.0, 0.0, True
    )
    table = {1436: westfall, 1429: wide}
    names = {1436: "Westfall", 1429: "Elwynn Forest"}
    assert best_map(table, 0, sentinel.wx, sentinel.wy)[0] == 1429
    world = build_world(
        Sources(client="forever", taxi=dump.nodes, transforms=table, map_names=names)
    )
    assert world.records["flightpath"][4]["spawns"][0][0] == 1436
    assert any(
        note.startswith("flightpaths placed: 1 on the map their name gives") for note in world.notes
    )
    # without names the rectangle rule stands
    world = build_world(Sources(client="forever", taxi=dump.nodes, transforms=table))
    assert world.records["flightpath"][4]["spawns"][0][0] == 1429


# --- UiMap and UiMapAssignment: the transform table from the client -----------------------------

from bastians_build.coords import best_map  # noqa: E402
from bastians_build.sources.clientdump import (  # noqa: E402
    map_parents,
    read_ui_map_assignments,
    read_ui_maps,
    transform_table,
)


def test_ui_maps_give_names_parents_and_types():
    ui_maps = read_ui_maps(FIXTURE / "UiMap.json")
    assert ui_maps[1429].name == "Elwynn Forest" and ui_maps[1429].parent == 1415
    assert ui_maps[947].parent is None and ui_maps[947].type == 1 and ui_maps[1415].type == 2


def test_assignments_become_the_measured_elwynn_transform():
    """The Elwynn fit measured in game (test_pipeline_coords.py) equals the client's assignment."""
    table, notes = transform_table(read_ui_map_assignments(FIXTURE / "UiMapAssignment.json"))
    elwynn = table[1429]
    assert elwynn.continent == 0 and elwynn.exact is True
    assert (elwynn.wx0, elwynn.wx_dx, elwynn.wx_dy) == (-7939.583, 0.0, -2314.583)
    assert (elwynn.wy0, elwynn.wy_dx, elwynn.wy_dy) == (1535.4166, -3470.8332, 0.0)
    assert 947 not in table and notes == [
        "1 uiMap(s) with several assignments, no single transform: 947 (2)"
    ]
    assert sorted(table) == [1411, 1414, 1415, 1429, 1436, 1453, 1454, 1455]
    assert table[1454].continent == 1


def test_many_multi_assignment_maps_give_one_note():
    """Retail has 1178 such maps; the report lists ten ids and a count, not a line each."""
    from bastians_build.sources.clientdump import Assignment

    rows = []
    for ui_map_id in range(100, 115):
        for _ in range(2):
            rows.append(Assignment(ui_map_id, 0, 0.0, 0.0, 100.0, 100.0, (0.0, 0.0), (1.0, 1.0)))
    rows.append(Assignment(200, 0, 0.0, 0.0, 100.0, 100.0, (0.0, 0.0), (1.0, 1.0)))
    table, notes = transform_table(rows)
    assert list(table) == [200]
    assert len(notes) == 1
    assert notes[0].startswith(
        "15 uiMap(s) with several assignments, no single transform: 100 (2), "
    )
    assert notes[0].endswith("109 (2), ...")


def test_flight_masters_land_in_their_zones_through_the_client_transforms():
    table, _ = transform_table(read_ui_map_assignments(FIXTURE / "UiMapAssignment.json"))
    nodes = {n.name: n for n in read_taxi_nodes(FIXTURE / "TaxiNodes.json").nodes}
    stormwind = nodes["Stormwind, Elwynn"]
    hit = best_map(table, stormwind.continent, stormwind.wx, stormwind.wy)
    assert hit is not None and hit[0] == 1453  # the smallest containing map: Stormwind City
    sentinel = nodes["Sentinel Hill, Westfall"]
    assert best_map(table, sentinel.continent, sentinel.wx, sentinel.wy)[0] == 1436
    orgrimmar = nodes["Orgrimmar, Durotar"]
    assert best_map(table, orgrimmar.continent, orgrimmar.wx, orgrimmar.wy)[0] in (1411, 1454)
    parents = map_parents(read_ui_maps(FIXTURE / "UiMap.json"), table)
    assert parents[1429] == (1415, 0) and parents[947] == (None, None)


def test_every_world_map_with_a_zone_is_a_continent_when_the_map_dump_is_there():
    """coordinates.md: a continent is a Map.db2 id; with the Map dump Outland and a single-zone
    world count, the tram (no zone) and instances do not; the name is the continent UiMap's,
    else the one zone's, else the map's own."""
    from bastians_build.sources.clientdump import read_maps, world_continents

    maps = read_maps(FIXTURE / "Map.json")
    assert maps[530].directory == "Expansion01" and maps[530].wdt_file_id == 828395
    assert maps[3217].wdt_file_id is None and maps[33].instance_type == 1
    ui_maps = read_ui_maps(FIXTURE / "UiMap.json")
    assignments = read_ui_map_assignments(FIXTURE / "UiMapAssignment.json")
    continents = world_continents(maps, assignments, ui_maps)
    assert continents == {
        0: "Eastern Kingdoms",
        1: "Kalimdor",
        530: "Outland",
        2991: "Zephras Isle",
    }
    table, _ = transform_table(assignments, continents)
    assert table[100].continent == 530 and table[2200].continent == 2991
    assert 2201 not in table  # the tram's map is no continent
    default, _ = transform_table(assignments)
    assert 100 not in default and 2200 not in default  # without the dump: Azeroth only
    nodes = read_taxi_nodes(FIXTURE / "TaxiNodes.json", continents)
    assert all(n.continent in continents for n in nodes.nodes)
    assert "continent 30" in {d[0]: d[2] for d in nodes.dropped}[300]
