"""The graph service over the network (ADR 0026, W6 step 2, W8): Ready, Route as a job, the distance
cache and the memo of places behind Time, the travel shim, on the generator's record of
tests/fixtures/navnet-mini (see
test_navnet_search.py for the fixture's shape). The character stands at waypoint 1 (100, 300)."""

import pytest
from harness import WowRuntime
from test_navnet_search import lua_pack

RUN, SWIM = 7.0, 4.7
FASTEST = 20 / RUN + 100 / SWIM + 100 / RUN + 250 / RUN  # lake, border, east road to 6

# a test map whose corners put (0.35, 0.1) at world (100, 300): wx = 1000 y, wy = 1000 - 2000 x
SETUP = """
Mock.maps[9000] = { name = "Test Vale", mapType = 3, c00 = { 0, 0, 1000 }, c11 = { 0, 1000, -1000 } }
Mock.playerMap = 9000
Mock.playerMapPos = { x = 0.35, y = 0.1 }
"""


@pytest.fixture
def graph(wow: WowRuntime) -> WowRuntime:
    wow.execute(SETUP)
    wow.start("Bastians_Core", "Bastians_Data")
    wow.run_frames(5)
    wow.execute(lua_pack())
    wow.execute("Bastians.Deliver(); g = Bastians:GetService('graph')")
    return wow


def test_the_network_is_ready_on_its_continent(graph):
    assert graph.eval("g:Ready(0)") is True
    assert graph.eval("g:Ready(1)") is False
    assert graph.eval("g:Ready()") is True  # the character's continent


def test_a_route_is_planned_in_a_job_and_shaped_for_the_apps(graph):
    graph.execute(
        "R, WHY = nil, nil; g:Route('player', { map = 0, wx = 100, wy = -300 }, {}, "
        "function(r, why) R, WHY = r, why end)"
    )
    assert graph.eval("R") is None  # a job: not yet
    graph.run_frames(5)
    r = graph.eval("R")
    assert r is not None, graph.eval("WHY")
    assert abs(r.seconds - FASTEST) < 0.05
    steps = list(r.steps.values())
    assert [s.mode for s in steps] == ["walk"]  # one walk, refined from the region level
    assert abs(steps[0].yards - 470) < 0.01  # 120 across the lake, 100 over the border, 250 east
    assert steps[0].to == "entrance:36-1"
    assert list(steps[0].areas.values()) == [87, 88]
    first, last = r.path[1], r.path[len(r.path)]
    assert (first.wx, first.wy) == (100, 300) and (last.wx, last.wy) == (100, -300)


def test_a_route_without_a_network_says_why(graph):
    graph.execute(
        "WHY = nil; g:Route('player', { map = 1, wx = 0, wy = 0 }, {}, function(r, why) WHY = why end)"
    )
    assert graph.eval("WHY") == "no network"  # the pack holds continent 0 only


def test_times_come_from_the_cache_filled_by_jobs(graph):
    graph.execute(
        """TIMES = 0
        Bastians:NewModule("Rows", { addon = "Bastians_TestApp" }):On("BASTIANS_GRAPH_TIMES",
          function() TIMES = TIMES + 1 end)"""
    )
    east = "{ map = 0, wx = 100, wy = -300 }"
    graph.run_frames(5)  # the nav pack's load already asked for the cache
    if graph.eval(f"g:Time({east})") is None:  # the east cluster is filled on first ask
        graph.run_frames(5)
    seconds, approx = graph.eval(f"g:Time({east})")
    assert abs(seconds - FASTEST) < 0.05 and approx is False
    assert graph.eval("TIMES") >= 1
    west = "g:Time({ map = 0, wx = 100, wy = 150 })"  # waypoint 2, the open cluster
    assert graph.eval(west) is None  # a row never searches: the place is queued
    graph.run_frames(5)
    assert graph.eval(west) is not None
    assert graph.eval("g:Time({ map = 1, wx = 0, wy = 0 })") is None  # another continent


def watch_times(graph) -> None:
    graph.execute(
        """TIMES = 0
        Bastians:NewModule("Rows", { addon = "Bastians_TestApp" }):On("BASTIANS_GRAPH_TIMES",
          function() TIMES = TIMES + 1 end)"""
    )
    graph.run_frames(5)  # the cache from the character


PLACES = {
    "east": "{ map = 0, wx = 100, wy = -300 }",
    "west": "{ map = 0, wx = 100, wy = 150 }",
    "nowhere": "{ map = 0, wx = 900, wy = 900 }",  # a cluster without ground
}


def test_rows_ask_many_places_and_hear_once_when_they_are_in(graph):
    watch_times(graph)
    before = graph.eval("TIMES")
    for p in PLACES.values():
        assert graph.eval(f"g:Time({p})") is None
    graph.run_frames(10)
    assert graph.eval("TIMES") == before + 1  # one drain, one message for every row
    seconds, approx = graph.eval(f"g:Time({PLACES['east']})")
    assert abs(seconds - FASTEST) < 0.05 and approx is False
    assert graph.eval(f"g:Time({PLACES['west']})") is not None
    # a place the network cannot reach has no time, and asking again queues nothing
    assert graph.eval(f"g:Time({PLACES['nowhere']})") is None
    graph.run_frames(10)
    assert graph.eval("TIMES") == before + 1
    assert graph.eval("g:Time('player')") == (0, False)
    assert graph.errors == []


def test_a_thing_answers_the_fastest_of_its_places(graph):
    # a test type with two places on the test map: east (0.65, 0.1) and next to waypoint 2
    graph.execute(
        """local m = Bastians:NewModule("Things", { addon = "Bastians_TestApp" })
        Bastians:RegisterEntityType(m, { type = "testthing", name = function() return "Thing" end,
          locations = function() return { { map = 9000, x = 0.65, y = 0.1 },
            { map = 9000, x = 0.425, y = 0.1 } } end })"""
    )
    watch_times(graph)
    assert graph.eval("g:Time('testthing:1')") is None
    graph.run_frames(10)
    seconds, _ = graph.eval("g:Time('testthing:1')")
    west, _ = graph.eval(f"g:Time({PLACES['west']})")
    assert seconds == west and seconds < FASTEST
    assert graph.eval("g:Time('nothing:1')") is None  # a thing without places has no time
    assert graph.errors == []


def test_the_travel_shim_answers_legs_from_the_character(graph):
    watch_times(graph)
    travel = "Bastians:GetService('travel')"
    here, east = "{ 0, 100, 300 }", "{ 0, 100, -300 }"
    assert graph.eval(f"{travel}:Estimate({here}, {east})") == (None, "unknown")  # queued
    graph.run_frames(10)
    assert abs(graph.eval(f"{travel}:Estimate({here}, {east})") - FASTEST) < 0.05
    # a leg between two other places: the cache has no answer, the caller's straight line may
    assert graph.eval(f"{travel}:Estimate({{ 0, 100, 150 }}, {east})") is None
    # a continent the nav pack does not hold: no network there
    assert graph.eval(f"{travel}:Estimate({here}, {{ 1, 0, 0 }})") is None
    assert graph.errors == []


def ride_pack() -> str:
    """The fixture network with waypoints 2 and 6 as the stops of the fixture world's tram
    (ride 10 s, cycle 60 s: 40 s with the expected wait)."""
    from test_navnet_search import FIXTURE

    from bastians_build.emit import emit_pack
    from bastians_build.navnet import build_network, graph_record, read_local

    level = read_local(FIXTURE)
    level.waypoints[1].key = "transport:tram-goldshire-stormwind:1"
    level.waypoints[5].key = "transport:tram-goldshire-stormwind:2"
    pack = {
        "version": "test",
        "build": "fixture",
        "client": "forever",
        "schema": {},
        "graph": {0: graph_record(build_network(level))},
        "names": {},
        "index": {},
    }
    return emit_pack("nav", pack, comment="test")


def plan(graph, opts="{}"):
    graph.execute(
        f"R = nil; g:Route('player', {{ map = 0, wx = 100, wy = -300 }}, {opts}, function(r) R = r end)"
    )
    graph.run_frames(5)
    return graph.eval("R")


def test_a_ride_takes_its_ride_and_half_a_cycle(wow: WowRuntime):
    wow.execute(SETUP)
    wow.start("Bastians_Core", "Bastians_Data")
    wow.run_frames(5)
    wow.execute('Bastians:GetService("data"):LoadPack("world")')
    wow.execute(ride_pack())
    wow.execute("Bastians.Deliver(); g = Bastians:GetService('graph')")
    r = plan(wow)
    assert abs(r.seconds - (150 / RUN + 40)) < 0.05  # walk to stop 1, then the tram to 6
    steps = list(r.steps.values())
    assert [s.mode for s in steps] == ["walk", "ride"]
    assert steps[1].kind == "tram" and steps[1].wait == 30 and steps[1].ride == 10
    assert (steps[1].toPlace.wx, steps[1].toPlace.wy) == (100, -300)
    # a Horde character may not take the Alliance tram
    horde = plan(wow, "{ faction = 'Horde' }")
    assert abs(horde.seconds - FASTEST) < 0.05


def test_the_hearth_jumps_from_the_start(graph):
    r = plan(graph, "{ jumpWorth = 0, hearth = { map = 0, wx = 100, wy = -300, name = 'Inn' } }")
    assert r.seconds == 10
    steps = list(r.steps.values())
    assert [s.mode for s in steps] == ["hearth"] and steps[0].name == "Inn"  # the step names it
    assert plan(graph, "{ hearth = { map = 1, wx = 0, wy = 0 } }").seconds > 10  # another continent


def test_the_stone_is_taken_only_when_it_saves_three_minutes(graph):
    """ "I am actually directly on the road to him. But the route
    somehow puts me in the inn in goldshire". The stone was ready, its cast is 10 seconds and
    the walk was 1:28, so the planner spent the hearthstone to save 70 seconds. A jump from
    wherever one stands is not free: it is taken when it saves at least Graph.JUMP_WORTH."""
    assert graph.eval("Bastians.Data.Graph.JUMP_WORTH") == 180
    hearth = "hearth = { map = 0, wx = 100, wy = -300, name = 'Inn' }"
    r = plan(graph, f"{{ {hearth} }}")  # the walk is 74 s: the stone would save 64
    assert abs(r.seconds - FASTEST) < 0.05
    assert "hearth" not in [s.mode for s in r.steps.values()]
    # a teleport is the same kind of jump
    tp = "teleports = { { map = 0, wx = 100, wy = -300, seconds = 10, name = 'Home' } }"
    assert abs(plan(graph, f"{{ {tp} }}").seconds - FASTEST) < 0.05
    # the threshold is the saving, not the walk: 64 s saved passes a worth of 60, not of 70
    assert plan(graph, f"{{ jumpWorth = 60, {hearth} }}").seconds == 10
    assert abs(plan(graph, f"{{ jumpWorth = 70, {hearth} }}").seconds - FASTEST) < 0.05
    assert graph.errors == []


def test_rows_show_the_graph_time_never_the_straight_line(graph):
    watch_times(graph)
    east = PLACES["east"]
    assert graph.eval(f"Bastians.UI.Away({east})") is None  # queued: no time yet, and no yards
    graph.run_frames(10)
    text, key = graph.eval(f"Bastians.UI.Away({east})")
    assert text == "1 min" and abs(key - FASTEST) < 0.05  # 74 s over the lake and the border
    assert graph.eval(f"Bastians.UI.Away({PLACES['nowhere']})") is None
    assert graph.errors == []


def two_continents_pack(keyed: bool = True) -> str:
    """The fixture network on continents 0 and 1; the fixture world's ferry (ride 120 s, cycle
    480 s) leaves from waypoint 6 on 0 and lands at waypoint 1 on 1."""
    from test_navnet_search import FIXTURE

    from bastians_build.emit import emit_pack
    from bastians_build.navnet import build_network, graph_record, read_local

    east, west = read_local(FIXTURE), read_local(FIXTURE)
    if keyed:
        east.waypoints[5].key = "transport:boat-elwynn-ratchet:1"
        west.waypoints[0].key = "transport:boat-elwynn-ratchet:2"
    pack = {
        "version": "test",
        "build": "fixture",
        "client": "forever",
        "schema": {},
        "graph": {0: graph_record(build_network(east)), 1: graph_record(build_network(west))},
        "names": {},
        "index": {},
    }
    return emit_pack("nav", pack, comment="test")


def boot_two(wow: WowRuntime, keyed: bool = True) -> WowRuntime:
    wow.execute(SETUP)
    wow.start("Bastians_Core", "Bastians_Data")
    wow.run_frames(5)
    wow.execute('Bastians:GetService("data"):LoadPack("world")')
    wow.execute(two_continents_pack(keyed))
    wow.execute("Bastians.Deliver(); g = Bastians:GetService('graph')")
    return wow


def test_a_route_crosses_to_another_continent_by_boat(wow: WowRuntime):
    boot_two(wow)
    wow.execute(
        "R, WHY = nil, nil; g:Route('player', { map = 1, wx = 100, wy = -300 }, {}, "
        "function(r, why) R, WHY = r, why end)"
    )
    wow.run_frames(10)
    r = wow.eval("R")
    assert r is not None, wow.eval("WHY")
    steps = list(r.steps.values())
    assert [s.mode for s in steps] == ["walk", "ride", "walk"]
    boat = steps[1]
    assert boat.kind == "boat" and boat.ride == 120 and boat.wait == 240
    assert boat.fromPlace.map == 0 and boat.toPlace.map == 1
    assert (boat.toPlace.wx, boat.toPlace.wy) == (100, 300)  # waypoint 1 on the far side
    assert abs(r.seconds - (FASTEST + 360 + FASTEST)) < 0.05
    first, last = r.path[1], r.path[len(r.path)]
    assert first.map == 0 and last.map == 1 and (last.wx, last.wy) == (100, -300)
    assert wow.errors == []


def test_the_hearth_reaches_another_continent(wow: WowRuntime):
    boot_two(wow)
    wow.execute(
        "R = nil; g:Route('player', { map = 1, wx = 100, wy = 300 }, "
        "{ hearth = { map = 1, wx = 100, wy = 300 } }, function(r) R = r end)"
    )
    wow.run_frames(10)
    r = wow.eval("R")
    assert [s.mode for s in r.steps.values()] == ["hearth"] and r.seconds == 10
    assert wow.errors == []


def test_without_a_ride_between_the_continents_the_route_says_why(wow: WowRuntime):
    boot_two(wow, keyed=False)
    wow.execute(
        "R, WHY = 1, nil; g:Route('player', { map = 1, wx = 100, wy = -300 }, {}, "
        "function(r, why) R, WHY = r, why end)"
    )
    wow.run_frames(10)
    assert wow.eval("R") is None and wow.eval("WHY") == "no ride between the continents"
    assert wow.errors == []


def test_a_walk_that_comes_back_along_itself_loses_the_spur(graph):
    # out to (100, 0) and back to (50, 0), then on: the out-and-back part (100 yards) goes
    graph.execute(
        """P = { { wx = 0, wy = 0 }, { wx = 50, wy = 0 }, { wx = 100, wy = 0 }, { wx = 51, wy = 0 },
          { wx = 50, wy = 50 } }
        CUT = Bastians.Data.Graph.CutSpurs(P)"""
    )
    assert abs(graph.eval("CUT") - 99) < 0.01
    pts = [(p.wx, p.wy) for p in graph.eval("P").values()]
    assert pts == [(0, 0), (50, 0), (50, 50)]


def test_a_place_with_a_height_is_reached_on_its_own_floor(graph):
    """R25.42: (205, 150) at the road's height joins the road (2), not the hill above (4) that
    the plane alone finds nearer; the route and the row's time both go by the height."""
    for wz, seconds in (("", (150 + 200 + 95) / RUN), (", wz = 12", (150 + 105) / RUN)):
        graph.execute(
            "R = nil; g:Route('player', { map = 0, wx = 205, wy = 150" + wz + " }, {}, "
            "function(r) R = r end)"
        )
        graph.run_frames(5)
        assert abs(graph.eval("R").seconds - seconds) < 0.01
    graph.run_frames(5)  # the cache from the character
    place = "{ map = 0, wx = 205, wy = 150, wz = 12 }"
    if graph.eval(f"g:Time({place})") is None:
        graph.run_frames(5)
    seconds, _ = graph.eval(f"g:Time({place})")
    assert abs(seconds - (150 + 105) / RUN) < 0.01


def test_a_teleport_jumps_from_the_start_like_the_hearth(graph):
    """R26.7: a ready teleport to waypoint 5 (east road), 10 s to cast, then 250 yards east."""
    tp = (
        "{ jumpWorth = 0, "
        "teleports = { { map = 0, wx = 100, wy = -50, wz = 11, seconds = 10, name = 'Stormwind' } } }"
    )
    r = plan(graph, tp)
    assert abs(r.seconds - (10 + 250 / RUN)) < 0.05 and r.seconds < FASTEST
    steps = list(r.steps.values())
    assert [s.mode for s in steps] == ["teleport", "walk"]
    assert steps[0].name == "Stormwind" and steps[0].jump is True
    # slower than walking: not taken
    slow = "{ teleports = { { map = 0, wx = 100, wy = -50, seconds = 100, name = 'Slow' } } }"
    assert abs(plan(graph, slow).seconds - FASTEST) < 0.05
    assert graph.errors == []


def test_a_teleport_reaches_another_continent(wow: WowRuntime):
    boot_two(wow)
    wow.execute(
        "R = nil; g:Route('player', { map = 1, wx = 100, wy = -300 }, "
        "{ teleports = { { map = 1, wx = 100, wy = -300, seconds = 10, name = 'Moonglade' } } }, "
        "function(r) R = r end)"
    )
    wow.run_frames(10)
    r = wow.eval("R")
    steps = list(r.steps.values())
    assert [s.mode for s in steps] == ["teleport"] and r.seconds == 10
    assert steps[0].name == "Moonglade"
    assert wow.errors == []


def test_a_walk_step_names_its_danger(graph):
    """R26.5: the fixture's level 12 elite at (100, 160) stands by the lake the fastest walk swims."""
    r = plan(graph)
    walk = r.steps[1]
    assert walk.mode == "walk" and walk.danger == 12 and walk.elite is True


def test_no_flight_costs_leaves_the_flights_out(wow: WowRuntime):
    """R26.5: `nocost` takes no flight between flight masters (they cost gold); the rest stays."""
    from test_navnet_search import FIXTURE

    from bastians_build.emit import emit_pack
    from bastians_build.navnet import TaxiRow, build_network, graph_record, read_local

    level = read_local(FIXTURE)
    level.waypoints[5].key = "taxinode:6"
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
    wow.execute(SETUP)
    wow.start("Bastians_Core", "Bastians_Data")
    wow.run_frames(5)
    wow.execute(emit_pack("nav", pack, comment="test"))
    wow.execute("Bastians.Deliver(); g = Bastians:GetService('graph')")
    known = "known = { [2] = true, [6] = true }"
    flown = plan(wow, f"{{ {known} }}")
    assert [s.mode for s in flown.steps.values()] == ["taxi"]
    walked = plan(wow, f"{{ {known}, profile = 'nocost' }}")
    assert "taxi" not in [s.mode for s in walked.steps.values()]
    assert abs(walked.seconds - FASTEST) < 0.05
    assert wow.errors == []
