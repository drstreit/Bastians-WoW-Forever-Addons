"""The walk network in the planner (route.md "Walk network", ADR 0025): the fixture network of
tests/fixtures/nav-mini (built into tests/fixtures/addons/Bastians_Data_Nav by the real generator)
lies on continent 530, so the other Route tests keep their straight walks. A route goes around the
gap the network goes around, its legs are drawn (straight joins dashed), swimming costs more, a
flight master the network holds joins it without a straight leg, the arrow heads for the next bend,
and a network of the real size plans in a few milliseconds."""

import pytest
from harness import WowRuntime

CORE, DATA, MAP, ROUTE = "Bastians_Core", "Bastians_Data", "Bastians_Map", "Bastians_Route"
MOD = "Bastians:GetModule('Route')"
R = f"{MOD}.Route"
G = f"{MOD}.Graph"
TUNNEL = ((0 - -10) ** 2 + (1000 - 1500) ** 2) ** 0.5 * 2  # the fixture tunnel's two pieces


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, MAP, ROUTE)))
    wow.run_frames(5)
    return wow


def test_the_pack_decodes_into_nodes_edges_keys_and_paths(wow: WowRuntime):
    boot(wow)
    wow.execute(f"net = {R}.Net(530)")
    assert wow.eval("net.n") == 6
    assert wow.eval("net.key['flightpath:900']") == 1 and wow.eval("net.key['flightpath:901']") == 6
    assert wow.eval("#net.adj[1]") == 4  # two edges: to 2 and the gate to 6
    assert wow.eval("net.len[4]") == pytest.approx(round(TUNNEL, 1))
    pts = wow.eval(f"{G}.EdgePoints(net, 2, 3)")  # edge 2 walked backwards, from node 3 to node 2
    assert [tuple(p.values()) for p in pts.values()] == [(800, 1000), (820, 500), (800, 0)]
    near = wow.eval(f"{G}.NearestNodes(net, 10, 20, 600, 4)")
    assert [p[1] for p in near.values()] == [1]
    assert wow.eval(f"{R}.Net(0)") is None  # the fixture has no network for continent 0
    assert wow.errors == []


def test_a_route_goes_around_the_gap_the_network_goes_around(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"route = {R}.Plan({{ continent = 530, wx = 0, wy = -50 }}, "
        "{ continent = 530, wx = 0, wy = 2050, name = 'Beyond the tunnel' })"
    )
    steps = list(wow.eval("route.steps").values())
    assert [s.mode for s in steps] == ["walk"]  # one walk: joins and network edges fold into it
    step = steps[0]
    network = 800 + 1000 + 800 + round(TUNNEL, 1)
    assert step.yards == pytest.approx(50 + network + 50)
    swim = 100
    assert wow.eval("route.seconds") == pytest.approx(
        (50 + network + 50 - swim) / 7 + swim / 4.7, rel=1e-6
    )
    assert step.approx is False  # 100 of 3700 yards are straight joins
    legs = list(step.legs.values())
    assert [leg.approx for leg in legs] == [True, False, True]
    middle = [tuple(p.values()) for p in legs[1].points.values()]
    assert middle == [
        (0, 0),
        (400, -20),
        (800, 0),
        (820, 500),
        (800, 1000),
        (0, 1000),
        (-10, 1500),
        (0, 2000),
    ]
    # the map draws the network solid and the joins dashed
    wow.execute(f"{R}.Set(route)")
    pins = list(
        wow.eval("Bastians:QueryLayer('route.path', { continent = 530, level = 5 })").values()
    )
    paths = [p for p in pins if p.kind == "path"]
    assert [p.style for p in paths] == ["dashed", None, "dashed"]
    assert len(list(paths[1].points.values())) == 8
    assert wow.errors == []


def test_far_from_the_network_the_walk_stays_straight(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"route = {R}.Plan({{ continent = 530, wx = 5000, wy = 5000 }}, "
        "{ continent = 530, wx = 5300, wy = 5400, name = 'Off the map' })"
    )
    step = wow.eval("route.steps[1]")
    assert step.approx is True and step.yards == pytest.approx(500)
    assert wow.errors == []


def test_a_flight_master_on_the_network_joins_by_its_key(wow: WowRuntime):
    boot(wow, CORE, ROUTE)
    wow.execute(
        f"""
        local net = {G}.DecodeNet({{ nodes = "0,0;800,0", keys = {{ [2] = "flightpath:7" }},
          edges = "1,2,1000,0", paths = {{ [1] = "400,300" }} }})
        route = {G}.Plan({{ start = {{ continent = 9, wx = 0, wy = -10 }},
          goal = {{ continent = 9, wx = 802, wy = 3, name = "At the flight master" }},
          flights = {{ {{ id = 7, name = "F", continent = 9, wx = 802, wy = 3 }} }},
          nets = {{ [9] = net }} }})
        """
    )
    steps = list(wow.eval("route.steps").values())
    assert [s.mode for s in steps] == ["walk"]
    # start joins node 1 (10 yd, straight), the edge (1000 yd), node 2 is the flight master by
    # its key (0 yd), which stands on the goal; the goal's own straight join to node 2 is 3.6 yd
    assert steps[0].yards == pytest.approx(1010)
    assert wow.eval("route.seconds") == pytest.approx(1010 / 7)
    assert wow.errors == []


def test_the_arrow_heads_for_the_next_bend(wow: WowRuntime):
    boot(wow, CORE, ROUTE)
    wow.execute(
        """
        step = { from = { wx = 0, wy = 0 }, to = { wx = 800, wy = 1000 },
          legs = { { approx = false, points = { { 0, 0 }, { 800, 0 }, { 800, 1000 } } } } }
        """
    )
    off, p = wow.eval(f"{G}.PathProgress(step, 400, 30, 30)")
    assert off == pytest.approx(30) and tuple(p.values()) == (800, 0)
    _, p = wow.eval(f"{G}.PathProgress(step, 790, 10, 30)")  # at the bend: on to the next point
    assert tuple(p.values()) == (800, 1000)
    off, _ = wow.eval(f"{G}.PathProgress(step, 900, 500, 30)")
    assert off == pytest.approx(100)


def test_a_network_of_the_real_size_plans_in_a_few_milliseconds(wow: WowRuntime):
    boot(wow, CORE, ROUTE)
    wow.execute(
        f"""
        -- a 36 x 36 lattice every 400 yards (1,296 nodes, the size of Eastern Kingdoms' network)
        local nodes, edges = {{}}, {{}}
        local function id(r, c) return r * 36 + c + 1 end
        for r = 0, 35 do
          for c = 0, 35 do
            nodes[#nodes + 1] = (r * 400) .. "," .. (c * 400)
            if c < 35 then edges[#edges + 1] = id(r, c) .. "," .. id(r, c + 1) .. ",420,0" end
            if r < 35 then edges[#edges + 1] = id(r, c) .. "," .. id(r + 1, c) .. ",410,0" end
          end
        end
        net = {G}.DecodeNet({{ nodes = table.concat(nodes, ";"), edges = table.concat(edges, ";") }})
        local flights = {{}}
        for i = 1, 60 do
          flights[i] = {{ id = i, name = "F" .. i, continent = 0, wx = (i * 997) % 14000, wy = (i * 613) % 14000 }}
        end
        best = math.huge
        for _ = 1, 5 do
          local t0 = os.clock()
          result = {G}.Plan({{ start = {{ continent = 0, wx = 10, wy = 10 }},
            goal = {{ continent = 0, wx = 13990, wy = 13990, name = "Far corner" }},
            flights = flights, nets = {{ [0] = net }} }})
          best = math.min(best, os.clock() - t0)
        end
        """
    )
    assert wow.eval("net.n") == 1296
    assert wow.eval("result") is not None
    assert wow.eval("best") < 0.02, "route.md: a route on the real network under 20 ms"
