"""The world graph's network search (ADR 0026, W6 step 2), on the record the real generator makes
from tests/fixtures/navnet-mini (data contract: generator and addon cannot drift apart).

The fixture: two clusters split at wy = 0; west 1 (taxi node) - 2 - 3 along a road (250 yards) or
1 - 3 across a lake (120 yards, 100 swum); 2 - 4 - 3 over a hill whose 4 -> 3 is a drop (one way);
3 - 5 across the border; 5 - 6 (entrance) with 40 yards indoors.
"""

from pathlib import Path

import pytest
from harness import WowRuntime

from bastians_build.emit import emit_pack
from bastians_build.navnet import apply_danger, build_network, graph_record, read_local

FIXTURE = Path(__file__).resolve().parents[2] / "fixtures" / "navnet-mini" / "0.json"
RUN, SWIM = 7.0, 4.7


def lua_pack(danger: dict | None = None) -> str:
    level = read_local(FIXTURE)
    apply_danger(level, danger or {"hostile": [[0, 100.0, 160.0, 12, True]], "guards": []})
    record = graph_record(build_network(level))
    pack = {
        "version": "test",
        "build": "fixture",
        "client": "forever",
        "schema": {},
        "graph": {0: record},
        "names": {},
        "index": {},
    }
    return emit_pack("nav", pack, comment="test")


@pytest.fixture
def net(wow: WowRuntime) -> WowRuntime:
    wow.start("Bastians_Core", "Bastians_Data")
    wow.execute(lua_pack())
    wow.execute(
        "Bastians.Deliver(); Net = Bastians.Data.Net; N = Net.New(Bastians.Data.packs.nav.graph[0])"
    )
    return wow


def route(wow, frm, to, opts="{}"):
    return wow.eval(
        f"Net.Route(N, {{ x = {frm[0]}, y = {frm[1]} }}, {{ x = {to[0]}, y = {to[1]} }}, {opts})"
    )


def test_cluster_keys_match_the_generator(net):
    assert net.eval("Net.ClusterKey(100, 300)") == 495
    assert net.eval("Net.ClusterKey(100, -50)") == 527
    assert net.eval("Net.ClusterOf(N, 4)") == 495 and net.eval("Net.ClusterOf(N, 5)") == 527
    assert net.eval("Net.ClusterOf(N, 99)") is None


def test_on_foot_the_fastest_way_swims_the_lake(net):
    r = route(net, (100, 300), (100, -300))
    swim_leg = 20 / RUN + 100 / SWIM
    assert abs(r.seconds - (swim_leg + 100 / RUN + 250 / RUN)) < 0.01
    legs = [(leg["from"], leg.to) for leg in r.legs.values()]
    assert legs[0] == (1, 3) and legs[-1][1] == 6


def test_noswim_and_a_mount_take_the_road(net):
    noswim = route(net, (100, 300), (100, -300), "{ profile = 'noswim' }")
    assert abs(noswim.seconds - (250 / RUN + 100 / RUN + 250 / RUN)) < 0.01
    # its first leg is the west cluster's noswim region edge: the road, as the refinement shows
    first = noswim.legs[1]
    assert (first["from"], first.to, first.edge.facts.swim, first.edge.facts.road) == (1, 3, 0, 250)
    net.execute(
        "R = Net.Route(N, { x = 100, y = 300 }, { x = 100, y = -300 }, { profile = 'noswim' })"
    )
    refined = net.eval("Net.Refine(N, R.legs[1], { profile = 'noswim' })")
    assert [(leg["from"], leg.to) for leg in refined.values()] == [(1, 2), (2, 3)]
    # mounted at 14 yd/s outdoors (7 indoors): the road beats the lake by the facts, not the build
    mounted = route(net, (100, 300), (100, -300), "{ speeds = { ground = 14, indoor = 7 } }")
    assert abs(mounted.seconds - (250 / 14 + 100 / 14 + 210 / 14 + 40 / 7)) < 0.01


def test_a_drop_goes_one_way_only(net):
    down = route(net, (300, 150), (100, 50))  # 4 -> 3 straight down
    assert [(leg["from"], leg.to) for leg in down.legs.values()] == [(4, 3)]
    up = route(net, (100, 50), (300, 150))  # 3 -> 4 has to go round by 2
    assert [(leg["from"], leg.to) for leg in up.legs.values()] == [(3, 2), (2, 4)]


def test_extra_edges_carry_taxis_and_rides(net):
    r = route(
        net,
        (100, 300),
        (100, -300),
        "{ extra = { [1] = { { b = 6, seconds = 5, mode = 'taxi' } } } }",
    )
    assert r.seconds == 5 and r.legs[1].edge.mode == "taxi"


def test_places_off_the_network_are_not_joined(net):
    r = net.eval("select(2, Net.Route(N, { x = 5000, y = 5000 }, { x = 100, y = -300 }, {}))")
    assert r == "start off the network"


def test_a_region_edge_refines_into_its_ways_and_points(net):
    # the noswim route's first leg is the west cluster's region edge 1 -> 3; it refines into the
    # road 1 -> 2 -> 3, and the way 2 -> 3 draws from 2 to 3 (its straight bend at (100, 100) is
    # simplified away: 2 yards, 2D, the bends are for drawing)
    net.execute(
        "R = Net.Route(N, { x = 100, y = 300 }, { x = 100, y = -300 }, { profile = 'noswim' }); "
        "LEGS = Net.Refine(N, R.legs[1], { profile = 'noswim' })"
    )
    assert net.eval("R.legs[1].edge.region") is True
    assert [(leg["from"], leg.to) for leg in net.eval("LEGS").values()] == [(1, 2), (2, 3)]
    points = net.eval("Net.LegPoints(N, LEGS[2])")
    assert [(p.x, p.y) for p in points.values()] == [(100, 150), (100, 50)]
    # the link 3 -> 5 draws its way's bends; the way 5 -> 6 its two bends
    last = net.eval(
        "Net.LegPoints(N, Net.Route(N, { x = 100, y = -50 }, { x = 100, y = -300 }, {}).legs[1])"
    )
    assert [(p.x, p.y) for p in last.values()] == [
        (100, -50),
        (100, -200),
        (120, -250),
        (100, -300),
    ]


def test_the_distance_cache_spreads_and_fills_a_cluster(net):
    net.execute("T = Net.Spread(N, { [1] = 0 }, { open = { [495] = true } })")
    assert abs(net.eval("T[5]") - (20 / RUN + 100 / SWIM + 100 / RUN)) < 0.01
    assert net.eval("T[6]") is not None  # by the east cluster's region edge 5 -> 6
    east = net.eval("Net.ClusterTimes(N, 527, T, {})")
    assert abs(east[6] - net.eval("T[6]")) < 0.01


def test_taxi_edges_between_known_nodes(wow: WowRuntime):
    """The record's taxi paths become extra edges, timed by length at 29.85 yd/s or the learned
    time, only between flight masters the character knows."""
    level = read_local(FIXTURE)
    level.waypoints[5].key = "taxinode:6"  # the fixture's east node as a second flight master
    from bastians_build.navnet import TaxiRow

    record = graph_record(build_network(level), [TaxiRow(12, 2, 6, 0, 597.0)])
    pack = {
        "version": "test",
        "build": "fixture",
        "client": "forever",
        "schema": {},
        "graph": {0: record},
        "names": {},
        "index": {},
    }
    wow.start("Bastians_Core", "Bastians_Data")
    wow.execute(emit_pack("nav", pack, comment="test"))
    wow.execute(
        "Bastians.Deliver(); Net = Bastians.Data.Net; N = Net.New(Bastians.Data.packs.nav.graph[0])"
    )
    e = wow.eval("Net.TaxiEdges(N, nil, nil)[1][1]")
    assert e.b == 6 and abs(e.seconds - 597 / 29.85) < 1e-6 and e.mode == "taxi"
    learned = wow.eval("Net.TaxiEdges(N, nil, { ['taxinode:2>taxinode:6'] = 42 })[1][1].seconds")
    assert learned == 42
    # the pack's captured time (the fourth field, W11) beats the length, the learned one beats it
    wow.execute("N.rec.taxi = '2,6,597,101'")
    assert wow.eval("Net.TaxiEdges(N, nil, nil)[1][1].seconds") == 101
    assert wow.eval("Net.TaxiEdges(N, nil, { ['taxinode:2>taxinode:6'] = 42 })[1][1].seconds") == 42
    wow.execute("N.rec.taxi = '2,6,597'")
    assert wow.eval("next(Net.TaxiEdges(N, { [2] = true }, nil))") is None  # 6 not known
    r = wow.eval(
        "Net.Route(N, { x = 100, y = 300 }, { x = 100, y = -300 }, "
        "{ extra = Net.TaxiEdges(N, nil, nil) })"
    )
    assert abs(r.seconds - 20) < 1e-6


def test_a_goal_does_not_join_by_the_field(net):
    """Trade District to Gakin looped out by the harbour. A goal has no
    height either, and the field's one waypoint per cell can lie on another floor: Gakin's lay on
    the hidden ground 40 yards under Stormwind's streets. The field is for the character."""
    net.execute(
        "Bastians.Data.packs.nav.graph[0].join = { [495] = '0*827,2,0*196' };"
        "N = Net.New(Bastians.Data.packs.nav.graph[0])"
    )
    assert net.eval("Net.Join(N, 205, 150, nil, true)") == (4, 95)
    r = net.eval("Net.Route(N, { x = 100, y = 50 }, { x = 205, y = 150 }, {})")
    assert r.to == 4


def test_the_character_joins_the_waypoint_nearest_on_foot(net):
    """a route began across a mountain. At (205, 150) the hill (4) is
    nearest in a straight line; the join field says the road (2) is nearest on foot. The cell is
    row 25, column 27 of the cluster; a place with a height keeps its own rule."""
    assert net.eval("Net.Join(N, 205, 150)") == (4, 95)  # no field yet: the straight line
    elsewhere = net.eval("Net.Join(N, 205, 200)")
    net.execute(
        "Bastians.Data.packs.nav.graph[0].join = { [495] = '0*827,2,0*196' };"
        "N = Net.New(Bastians.Data.packs.nav.graph[0])"
    )
    assert net.eval("Net.Join(N, 205, 150)") == (2, 105)
    # a cell the field does not cover: the straight line again
    assert net.eval("Net.Join(N, 205, 200)") == elsewhere
    # a height is not the character: its own floor as before
    n, _ = net.eval("Net.Join(N, 205, 150, 30)")
    assert n == 4
    # the route starts where the field says
    r = net.eval("Net.Route(N, { x = 205, y = 150 }, { x = 100, y = 50 }, {})")
    assert [(leg["from"], leg.to) for leg in r.legs.values()] == [(2, 3)]
    assert net.errors == []


def test_a_place_with_a_height_joins_its_own_floor(net):
    """R25.42: a goal under another floor (Undercity under the ruins) joined the floor above, by the
    plane alone. At (205, 150) the hill's top (4, height 30) is 95 yards away, the road below
    (2, height 12) 105: a place standing on the road's level joins the road."""
    assert net.eval("Net.Join(N, 205, 150)") == (4, 95)  # no height: the plane, as before
    n, d = net.eval("Net.Join(N, 205, 150, 12)")
    assert (n, d) == (2, 105)
    n, d = net.eval("Net.Join(N, 205, 150, 30)")  # at the hill's height: the hill
    assert n == 4 and abs(d - 95) < 1e-9
    # the height is the straight line's third side
    n, d = net.eval("Net.Join(N, 100, 150, 15)")
    assert n == 2 and abs(d - 3) < 1e-9
    # a route from there starts on the road, not with the hill's drop
    r = net.eval("Net.Route(N, { x = 205, y = 150, z = 12 }, { x = 100, y = 50 }, {})")
    assert [(leg["from"], leg.to) for leg in r.legs.values()] == [(2, 3)]
    r = net.eval("Net.Route(N, { x = 205, y = 150 }, { x = 100, y = 50 }, {})")
    assert [(leg["from"], leg.to) for leg in r.legs.values()] == [(4, 3)]


def test_the_safe_weight_follows_the_level_gap(net):
    """R26.5 (route.md "Route options"): 1 up to five levels below, 1.5 at even, one more per
    level above, capped at 20; an elite counts three levels more; the other faction's guards are
    deadly, the own ones are not."""
    f = "Net.SafeFactor"
    assert net.eval(f"{f}(5, '', 30)") == 1  # a level 30 ignores a level 5
    assert net.eval(f"{f}(10, '', 15)") == 1
    assert abs(net.eval(f"{f}(10, '', 10)") - 1.5) < 1e-9
    assert abs(net.eval(f"{f}(5, '', 1)") - 5.5) < 1e-9  # a level 5 for a level 1: deadly enough
    assert abs(net.eval(f"{f}(5, 'e', 4)") - 5.5) < 1e-9  # elite: three levels more
    assert net.eval(f"{f}(60, '', 1)") == 20  # capped
    assert net.eval(f"{f}(nil, 'H', 10, 'A')") == 20  # Horde guards for an Alliance character
    assert net.eval(f"{f}(nil, 'A', 10, 'A')") == 1
    assert net.eval(f"{f}(nil, '', 10)") == 1  # no danger known: no weight


def test_the_safe_route_goes_round_the_danger_for_a_low_level(wow: WowRuntime):
    """A level 20 creature at (100, 120) stands on the road 2 - 3 only: a level 10 character's safe
    route takes the hill 2 - 4 - 3 (420 yards), a level 30 one keeps the road (100 yards); the
    seconds stay real time."""
    wow.start("Bastians_Core", "Bastians_Data")
    wow.execute(lua_pack({"hostile": [[0, 100.0, 120.0, 20, False]], "guards": []}))
    wow.execute(
        "Bastians.Deliver(); Net = Bastians.Data.Net; N = Net.New(Bastians.Data.packs.nav.graph[0])"
    )

    def legs(opts):
        wow.execute(f"R = Net.Route(N, {{ x = 100, y = 150 }}, {{ x = 100, y = 50 }}, {opts})")
        r, refined = wow.eval("R"), []
        for i in range(1, len(r.legs) + 1):
            for part in wow.eval(f"Net.Refine(N, R.legs[{i}], {{}})").values():
                refined.append((part["from"], part.to))
        return r, refined

    fastest, way = legs("{}")
    assert way == [(2, 3)] and abs(fastest.seconds - 100 / RUN) < 0.01
    low, way = legs("{ safe = { level = 10 } }")
    assert way == [(2, 4), (4, 3)] and abs(low.seconds - 420 / RUN) < 0.01
    high, way = legs("{ safe = { level = 30 } }")
    assert abs(high.seconds - 100 / RUN) < 0.01
    assert way == [(2, 3)]
