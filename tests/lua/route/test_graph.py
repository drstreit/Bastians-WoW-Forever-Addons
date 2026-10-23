"""The planner (route.md acceptance 1 and 2): pure Dijkstra over flights, transports, hearth and straight
walks; optimal choices, hearth only when given, learned flight times, cross-continent only by transport,
text helpers, and the timing of a large graph."""

import pytest
from harness import WowRuntime

CORE, ROUTE = "Bastians_Core", "Bastians_Route"
G = "Bastians:GetModule('Route').Graph"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, ROUTE)
    wow.run_frames(3)
    return wow


def plan(wow: WowRuntime, g: str):
    wow.execute(f"route = {G}.Plan({g})")
    return wow.eval("route")


def modes(route) -> list:
    return [s.mode for s in route.steps.values()]


START = "start = { continent = 0, wx = 0, wy = 0 }"
FLIGHTS = (
    "flights = { { id = 1, name = 'A', continent = 0, wx = 0, wy = 10 },"
    " { id = 2, name = 'B', continent = 0, wx = 5000, wy = 0 } }"
)


def test_walk_only_route_is_one_straight_leg(wow: WowRuntime):
    boot(wow)
    route = plan(
        wow, f"{{ {START}, goal = {{ continent = 0, wx = 300, wy = 400, name = 'Target' }} }}"
    )
    assert modes(route) == ["walk"] and route.seconds == pytest.approx(500 / 7)
    step = route.steps[1]
    assert step.approx is True and step.yards == pytest.approx(500)
    assert wow.eval(f"{G}.StepText(route.steps[1])") == "Go 500 yd NW to Target (approx)"
    assert wow.eval(f"{G}.Mode(route)") == "walk"
    assert wow.eval(f"{G}.Plan({{ start = {{}}, goal = {{}} }})") is None


def test_flights_are_taken_when_faster_and_learned_times_win(wow: WowRuntime):
    boot(wow)
    goal = "goal = { continent = 0, wx = 5000, wy = 20, name = 'Far' }"
    route = plan(wow, f"{{ {START}, {goal}, {FLIGHTS} }}")
    assert modes(route) == ["walk", "fly", "walk"]
    fly = route.steps[2]
    assert fly.seconds == pytest.approx(5000.01 * 1.25 / 32 + 8, abs=0.1) and fly.approx is True
    assert route.seconds < 5000 / 7  # the walk alone would take longer
    assert wow.eval(f"{G}.StepText(route.steps[2])") == "Fly to B (approx)"
    assert wow.eval(f"{G}.Mode(route)") == "fly"
    learned = plan(wow, f"{{ {START}, {goal}, {FLIGHTS}, flightTimes = {{ ['1>2'] = 100 }} }}")
    assert learned.steps[2].seconds == 100 and learned.steps[2].approx is False
    assert wow.eval(f"{G}.StepText(route.steps[2], nil)") == "Fly to B"  # measured: no approx
    # only one flight master usable (the other is unknown): nothing to fly between
    one = plan(
        wow,
        f"{{ {START}, {goal}, flights = {{ {{ id = 1, name = 'A', continent = 0, wx = 0, wy = 10 }} }} }}",
    )
    assert modes(one) == ["walk"]


def test_hearth_only_when_given_and_it_jumps(wow: WowRuntime):
    boot(wow)
    goal = "goal = { continent = 0, wx = 5000, wy = 20, name = 'Far' }"
    hearth = "hearth = { continent = 0, wx = 5000, wy = 0, name = 'Inn' }"
    route = plan(wow, f"{{ {START}, {goal}, {FLIGHTS}, {hearth} }}")
    assert modes(route) == ["hearth", "walk"] and route.steps[1].jump is True
    assert route.seconds == pytest.approx(10 + 20 / 7)
    assert wow.eval(f"{G}.StepText(route.steps[1])") == "Hearth to Inn"
    assert wow.eval(f"{G}.Mode(route)") == "hearth"


BOAT = (
    "transports = { { id = 'b', name = 'Ferry', kind = 'boat', ride = 120, cycle = 480,"
    " stops = { { continent = 0, wx = -160, wy = -160, label = 'Elwynn dock' },"
    " { continent = 1, wx = -900, wy = -3770, label = 'Ratchet dock' } } } }"
)


def test_other_continents_need_a_transport_and_waits_count(wow: WowRuntime):
    boot(wow)
    goal = "goal = { continent = 1, wx = -800, wy = -3700, name = 'Ratchet' }"
    assert plan(wow, f"{{ {START}, {goal} }}") is None
    route = plan(wow, f"{{ {START}, {goal}, {BOAT} }}")
    assert modes(route) == ["walk", "boat", "walk"]
    boat = route.steps[2]
    assert (boat.seconds, boat.wait, boat.approx) == (360, 240, True)
    assert wow.eval(f"{G}.StepText(route.steps[2])") == "Take the boat to Ratchet dock (approx)"
    assert wow.eval(f"{G}.Mode(route)") == "boat"
    # a portal is instant and has no wait; an unknown ride time comes from the distance
    portal = plan(
        wow,
        f"{{ {START}, {goal}, transports = {{ {{ id = 'p', name = 'Portal', kind = 'portal', verified = true,"
        " stops = { { continent = 0, wx = 10, wy = 0, label = 'Here' },"
        " { continent = 1, wx = -800, wy = -3690, label = 'There' } } } } }",
    )
    assert modes(portal) == ["walk", "portal", "walk"]
    assert (portal.steps[2].seconds, portal.steps[2].jump, portal.steps[2].approx) == (
        3,
        True,
        False,
    )
    unknown = plan(
        wow,
        f"{{ {START}, {goal}, transports = {{ {{ id = 'z', name = 'Zep', kind = 'zeppelin',"
        " stops = { { continent = 0, wx = 0, wy = 0, label = 'Here' },"
        " { continent = 1, wx = -800, wy = -3700, label = 'There' } } } } }",
    )
    assert modes(unknown) == ["zeppelin"]  # zero-length walks are no steps
    assert unknown.steps[1].wait == 90


def test_text_helpers(wow: WowRuntime):
    boot(wow)
    assert [wow.eval(f"{G}.FormatSeconds({s})") for s in (54, 252, 3720, 0)] == [
        "0:54",
        "4:12",
        "1h 02",
        "0:00",
    ]
    assert [
        wow.eval(f"{G}.Heading({dx}, {dy})")
        for dx, dy in ((1, 0), (0, 1), (-1, 0), (0, -1), (1, 1), (1, -1))
    ] == [
        "N",
        "W",
        "S",
        "E",
        "NW",
        "NE",
    ]
    assert wow.eval(f"{G}.SegmentDistance(0, 10, 0, 0, 100, 0)") == 10
    assert wow.eval(f"{G}.SegmentDistance(150, 0, 0, 0, 100, 0)") == 50
    assert wow.eval(f"{G}.FlightKey(2, 4)") == "2>4"


def test_a_continent_sized_graph_plans_in_a_few_milliseconds(wow: WowRuntime):
    boot(wow)
    wow.execute(
        """
        local flights, transports = {}, {}
        for i = 1, 100 do
          flights[i] = { id = i, name = "F" .. i, continent = (i % 2), wx = (i * 137) % 15000 - 7500, wy = (i * 251) % 9000 - 4500 }
        end
        for i = 1, 10 do
          transports[i] = { id = "t" .. i, name = "T" .. i, kind = "boat", ride = 120, cycle = 400,
            stops = { { continent = 0, wx = i * 500, wy = -i * 300, label = "a" }, { continent = 1, wx = -i * 400, wy = i * 200, label = "b" } } }
        end
        big = { start = { continent = 0, wx = -7000, wy = 4000 }, goal = { continent = 1, wx = 7000, wy = -4000, name = "Far" },
          flights = flights, transports = transports, hearth = { continent = 0, wx = 0, wy = 0, name = "Inn" } }
        best = math.huge
        for _ = 1, 5 do
          local t0 = os.clock()
          result = Bastians:GetModule("Route").Graph.Plan(big)
          best = math.min(best, os.clock() - t0)
        end
        """
    )
    assert wow.eval("result") is not None and wow.eval("#result.steps") >= 3
    assert wow.eval("best") < 0.005, "route.md acceptance 2: a cross-continent route under 5 ms"
