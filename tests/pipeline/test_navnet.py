"""The world graph's network pack (ADR 0026, W3b): clusters, borders, the region level per base
profile, danger, the pack strings; on the hand-written local level tests/fixtures/navnet-mini."""

import json
from pathlib import Path

import pytest

from bastians_build.model import World
from bastians_build.navnet import (
    NavnetError,
    apply_danger,
    build_network,
    cluster_of,
    danger_points,
    graph_record,
    read_local,
    tile_of,
)
from bastians_build.sources.clientdump import TaxiPath
from bastians_build.sources.probe import Transform

FIXTURE = Path(__file__).resolve().parents[1] / "fixtures" / "navnet-mini" / "0.json"
WEST, EAST = 495, 527  # the fixture's two clusters: wy > 0 and wy < 0 near the origin
DANGER = {
    "hostile": [[0, 100.0, 160.0, 12, True], [1, 100.0, 160.0, 60, False]],
    "guards": [[0, 100.0, -300.0, "A"]],
}


def network():
    level = read_local(FIXTURE)
    apply_danger(level, DANGER)
    return build_network(level)


def test_tiles_and_clusters_follow_the_adt_grid():
    # coordinates.md: tile 32/32 starts at the origin, x grows east (falling wy), y south
    assert tile_of(-8832.77, 478.62) == (31, 48)  # the Stormwind taxi node (verified 19.10.2026)
    assert cluster_of(100, 300) == WEST and cluster_of(100, -50) == EAST
    assert cluster_of(-8832.77, 478.62) == 15 * 32 + 24


def test_waypoints_are_numbered_per_cluster_and_the_borders_found():
    net = network()
    assert net.clusters == {WEST: (1, 4), EAST: (5, 6)}
    assert [w.id for w in net.order] == [1, 2, 3, 4, 5, 6]
    # region nodes: the borders (3 and 5, joined by the way across) and the keyed nodes (1, 6)
    assert net.region_nodes == {WEST: [1, 3], EAST: [5, 6]}


def test_the_region_level_keeps_the_best_path_per_profile():
    net = network()
    best = {(a, b, p): facts for a, b, p, facts, *_ in net.region}
    # fastest swims the lake (24 s against 32 s on the road); noswim takes the road
    assert best[(1, 3, "f")]["swim"] == 100 and best[(1, 3, "f")]["len"] == 120
    assert best[(1, 3, "n")]["swim"] == 0 and best[(1, 3, "n")]["road"] == 250
    # without water fastest's path is noswim's too: stored once, as fastest's
    assert (5, 6, "n") not in best and best[(5, 6, "f")]["indoor"] == 40
    # no region edge leaves its cluster: that is what the ways across are for
    assert all(net.cluster_of_wp[a] == net.cluster_of_wp[b] for a, b, *_ in net.region)


def test_danger_and_guards_along_the_ways():
    net = network()
    ways = {(w.a, w.b): w for w in net.level.ways}
    assert ways[(1, 2)].danger == 12 and ways[(1, 2)].elite is True
    assert ways[(3, 5)].danger is None  # unknown is nil: no hostile near it, not 0
    assert ways[(5, 6)].guards == "A"
    # the level 60 spawn stands on the other continent and counts nowhere here
    assert max(w.danger or 0 for w in net.level.ways) == 12


def test_the_join_field_is_runs_of_waypoints_per_cluster():
    """(route.md "The join"): the nearest waypoint on foot per cell."""
    net = network()
    assert "join" not in graph_record(net)  # no field in the level: the key stays away
    second = net.order[1].id
    # cell (205, 150): column 507, row 505 of the world, 27 and 25 of cluster 495
    net.level.join = [507, 505, second, 507, 400, 99999]  # an unknown waypoint is dropped
    rec = graph_record(net)
    assert rec["join"] == {WEST: "0*827,2,0*196"}


def test_the_pack_strings():
    net = network()
    taxi = [
        TaxiPath(12, 6, 2, 110, 0, ((0, 0, 0), (1, 1, 1)), 6310.0),
        TaxiPath(13, 2, 6, 110, 0, ((0, 0, 0),), 7757.0),
        TaxiPath(99, 2, 7, 0, 1, ((0, 0, 0),), 50.0),  # another continent
    ]
    rec = graph_record(net, taxi, taxi_nodes={2, 6})
    assert rec["clusters"] == {WEST: "1,4", EAST: "5,6"}
    assert rec["wp"][WEST].split(";")[0] == "100,300,10,n,87"
    assert rec["wp"][WEST].split(";")[3] == "300,150,30,g,"
    ways = rec["ways"][WEST].split(";")
    assert ways[0] == "1,2,150,150,0,2,0,0,87,12,e"  # whole yards; flags: an elite counts
    assert "4,3,220,0,0,0,18,0,,,o" in ways  # one way, no area, no danger
    assert rec["ways"][EAST] == "5,6,250,250,0,0,6,40,88,,A"
    assert rec["bends"][EAST] == "100,-200:120,-250"
    assert rec["keys"] == {1: "taxinode:2", 6: "entrance:36-1"}
    assert rec["anchors"] == {"entrance": "36-1,1,6,0", "npc": "448,1,2,30"}
    assert rec["taxi"] == "6,2,6310;2,6,7757"
    # the ways across clusters, in the cluster each direction leaves: 3 -> 5 and back
    assert rec["links"] == {WEST: "3,5,100,100,0,0,1,0,88,,", EAST: "5,3,100,100,0,1,0,0,88,,"}
    # region: "a,b,p,len,road,swim,indoor,danger,flags"; noswim only where it avoids the lake
    assert rec["region"] == {
        WEST: "1,3,f,120,0,100,0,12,e;1,3,n,250,250,0,0,12,e;3,1,f,120,0,100,0,12,e;"
        "3,1,n,250,250,0,0,12,e",
        EAST: "5,6,f,250,250,0,40,,A;6,5,f,250,250,0,40,,A",
    }


def test_the_record_is_deterministic():
    a, b = graph_record(network()), graph_record(network())
    assert json.dumps(a, sort_keys=True) == json.dumps(b, sort_keys=True)


def test_a_bad_local_level_is_refused(tmp_path):
    raw = json.loads(FIXTURE.read_text(encoding="utf-8"))
    raw["ways"][0]["b"] = 99
    path = tmp_path / "0.json"
    path.write_text(json.dumps(raw), encoding="utf-8")
    with pytest.raises(NavnetError, match="two known waypoints"):
        read_local(path)
    raw = json.loads(FIXTURE.read_text(encoding="utf-8"))
    raw["ways"][0]["len"] = -1
    path.write_text(json.dumps(raw), encoding="utf-8")
    with pytest.raises(NavnetError, match="len must be"):
        read_local(path)
    raw["version"] = 2
    path.write_text(json.dumps(raw), encoding="utf-8")
    with pytest.raises(NavnetError, match="version"):
        read_local(path)


def test_danger_points_from_the_world():
    world = World(client="forever", build="test")
    world.add("npc", 1, {"name": "Kobold", "level": 7, "spawns": [[1429, 0.5, 0.5, "classic"]]})
    world.add(
        "npc",
        2,
        {"name": "Brute", "level": 9, "flags": ["elite"], "spawns": [[1429, 0.25, 0.5, "classic"]]},
    )
    world.add(
        "npc",
        3,
        {
            "name": "Stormwind Guard",
            "level": 55,
            "faction": "A",
            "spawns": [[1429, 0.5, 0.25, "eq"]],
        },
    )
    world.add(
        "npc",
        4,
        {
            "name": "Innkeeper",
            "level": 30,
            "flags": ["innkeeper"],
            "spawns": [[1429, 0.5, 0.5, "eq"]],
        },
    )
    world.add("npc", 5, {"name": "No level", "spawns": [[1429, 0.5, 0.5, "eq"]]})
    t = Transform(
        ui_map_id=1429,
        continent=0,
        wx0=0.0,
        wx_dx=0.0,
        wx_dy=-1000.0,
        wy0=0.0,
        wy_dx=-1000.0,
        wy_dy=0.0,
        exact=True,
    )
    points = danger_points(world, {1429: t})
    assert points["hostile"] == [[0, -500.0, -500.0, 7, False], [0, -500.0, -250.0, 9, True]]
    assert points["guards"] == [[0, -250.0, -500.0, "A"]]
    assert danger_points(world, None) == {"hostile": [], "guards": []}


def test_flight_masters_are_keyed_as_taxi_nodes(tmp_path):
    raw = json.loads(FIXTURE.read_text(encoding="utf-8"))
    raw["waypoints"][0]["key"] = "flightpath:2"  # how the data build's nodes name them
    path = tmp_path / "0.json"
    path.write_text(json.dumps(raw), encoding="utf-8")
    assert read_local(path).waypoints[0].key == "taxinode:2"


def test_bends_are_simplified_for_drawing():
    from bastians_build.navnet import simplify

    line = [(0, 0), (50, 1), (100, 0), (100, 100)]
    assert simplify(line, 2.0) == [(0, 0), (100, 0), (100, 100)]  # 1 yard off the line: gone
    assert simplify(line, 0.5) == line
    assert simplify([(0, 0), (5, 5)], 2.0) == [(0, 0), (5, 5)]


def test_a_region_edge_through_another_region_node_is_dropped():
    from bastians_build.navnet import _dominated

    # a -> m -> b costs 10 + 10; a -> b costs 20 directly: the chain does as well
    best = {1: {2: (10.0, None), 3: (20.0, None)}, 2: {3: (10.0, None)}, 3: {}}
    assert _dominated(1, 3, 20.0, [1, 2, 3], best) is True
    assert _dominated(1, 3, 19.0, [1, 2, 3], best) is False  # 5 % faster alone: kept


def test_a_creature_known_not_to_be_hostile_is_no_danger():
    """R26.5: with the client's FactionTemplate a neutral beast or critter (hostile False) is left
    out; a creature without that knowledge keeps the Monsters rule."""
    world = World(client="forever", build="test")
    spawn = [[1429, 0.5, 0.5, "classic"]]
    world.add("npc", 1, {"name": "Rabbit", "level": 1, "hostile": False, "spawns": spawn})
    world.add("npc", 2, {"name": "Kobold", "level": 7, "hostile": True, "spawns": spawn})
    world.add("npc", 3, {"name": "Wolf", "level": 5, "spawns": spawn})
    t = Transform(
        ui_map_id=1429,
        continent=0,
        wx0=0.0,
        wx_dx=0.0,
        wx_dy=-1000.0,
        wy0=0.0,
        wy_dx=-1000.0,
        wy_dy=0.0,
        exact=True,
    )
    levels = [p[3] for p in danger_points(world, {1429: t})["hostile"]]
    assert levels == [7, 5]
