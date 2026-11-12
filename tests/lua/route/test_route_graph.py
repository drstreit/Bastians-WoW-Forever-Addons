"""Route as a view on the world graph (ADR 0026, W8): with Data's network for the continent, a
route is planned by `graph:Route` in a job and arrives in Route's shape (the step list, the path
layer, the arrow and the following read it); without it, Route's own planner as before.
The network is the generator's record of tests/fixtures/navnet-mini; the character stands at its
waypoint 1 (100, 300) on a test map (tests/lua/data/test_graph_network.py)."""

import sys
from pathlib import Path

from harness import WowRuntime

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "data"))
from test_graph_network import FASTEST, SETUP
from test_navnet_search import lua_pack

CORE, DATA, MAP, ROUTE = "Bastians_Core", "Bastians_Data", "Bastians_Map", "Bastians_Route"
R = "Bastians:GetModule('Route').Route"


def boot(wow: WowRuntime, with_graph: bool = True) -> WowRuntime:
    wow.execute(SETUP)
    wow.start(CORE, DATA, MAP, ROUTE)
    wow.run_frames(5)
    if with_graph:
        wow.execute(lua_pack())
        wow.execute("Bastians.Deliver()")
    return wow


def test_a_route_to_a_point_comes_over_the_graph(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f"{R}.ToPoint(0, 100, -300, 'The Deadmines')") is True
    assert wow.eval(f"{R}.Active()") is None  # planned in a job
    wow.run_frames(5)
    route = wow.eval(f"{R}.Active()")
    assert route is not None and route.graph is True
    assert abs(route.seconds - FASTEST) < 0.05
    steps = list(route.steps.values())
    assert [s.mode for s in steps] == ["walk"]
    walk = steps[0]
    assert walk.to.name == "The Deadmines" and (walk.to.wx, walk.to.wy) == (100, -300)
    pts = [tuple(p.values()) for leg in walk.legs.values() for p in leg.points.values()]
    assert pts[0] == (100, 300) and pts[-1] == (100, -300)
    # Route's own readers work on it: the step text, the path layer
    assert "The Deadmines" in wow.eval(
        f"Bastians:GetModule('Route').Graph.StepText({R}.Active().steps[1])"
    )
    pins = list(
        wow.eval("Bastians:QueryLayer('route.path', { continent = 0, level = 5 })").values()
    )
    paths = [p for p in pins if p.kind == "path"]
    # the character stands on waypoint 1 and the goal is waypoint 6: no straight joins, one solid
    # line along the network
    assert len(paths) == 1 and paths[0].style is None and len(paths[0].points) >= 4
    assert abs(walk.yards - 470) < 0.01 and walk.approx is False
    goal = next(p for p in pins if not p.kind)
    assert goal.label == "The Deadmines"
    assert wow.errors == []


def test_without_the_network_route_plans_as_before(wow: WowRuntime):
    boot(wow, with_graph=False)
    assert wow.eval(f"{R}.ToPoint(0, 100, -300, 'The Deadmines')") is True
    route = wow.eval(f"{R}.Active()")  # Route's planner: at once
    assert route is not None and route.graph is None


def test_the_joins_off_the_network_are_short_dashed_legs(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.playerMapPos = { x = 0.35, y = 0.13 }")  # 30 yards north of waypoint 1
    wow.execute(f"{R}.ToPoint(0, 100, -320, 'The Deadmines')")  # 20 yards past waypoint 6
    wow.run_frames(5)
    walk = wow.eval(f"{R}.Active().steps[1]")
    legs = [(leg.approx, len(leg.points)) for leg in walk.legs.values()]
    assert legs[0] == (True, 2) and legs[-1] == (True, 2) and legs[1][0] is False
    first = walk.legs[1].points
    assert (first[1][1], first[1][2]) == (130, 300) and (first[2][1], first[2][2]) == (100, 300)
    assert abs(walk.yards - (470 + 30 + 20)) < 0.01


def test_a_route_across_continents_comes_over_the_graph_with_its_boat(wow: WowRuntime):
    from test_graph_network import two_continents_pack

    boot(wow, with_graph=False)
    wow.execute(two_continents_pack())
    wow.execute("Bastians.Deliver()")
    assert wow.eval(f"{R}.ToPoint(1, 100, -300, 'Far shore')") is True
    wow.run_frames(10)
    route = wow.eval(f"{R}.Active()")
    assert route is not None and route.graph is True
    steps = list(route.steps.values())
    assert [s.mode for s in steps] == ["walk", "boat", "walk"]
    assert steps[1].wait == 240 and steps[1].to.continent == 1
    assert steps[2].to.name == "Far shore" and steps[2].to.continent == 1
    assert wow.errors == []


# a level 20 creature at (100, 120) on the lake and the road 2 - 3, not on 1 - 2 or the hill
DANGER = {"hostile": [[0, 100.0, 120.0, 20, False]], "guards": []}


def boot_danger(wow: WowRuntime) -> WowRuntime:
    wow.execute(SETUP)
    wow.start(CORE, DATA, MAP, ROUTE)
    wow.run_frames(5)
    wow.execute(lua_pack(DANGER))
    wow.execute("Bastians.Deliver()")
    return wow


def test_a_route_comes_in_three_kinds_and_the_player_picks_one(wow: WowRuntime):
    """R26.5: fastest first, safest and no flights in the background; equal kinds show once; a
    click switches and keeps the kind; the walk past the level 20 says so for a level 12."""
    boot_danger(wow)
    w = "Bastians:GetModule('Route').Window"
    wow.execute(f"{R}.ToPoint(0, 100, -300, 'The Deadmines')")
    wow.run_frames(20)
    route = wow.eval(f"{R}.Active()")
    assert route.kind == "fastest" and abs(route.seconds - FASTEST) < 0.05
    alts = route.alternatives
    assert {k for k in ("fastest", "safe", "nocost") if alts[k]} == {"fastest", "safe", "nocost"}
    assert alts.safe.seconds > alts.fastest.seconds  # the hill round the danger takes longer
    # the window: Fastest accented, Safest beside it, No flights left out (no flights here: equal)
    wow.execute(f"{w}.Open()")
    buttons = wow.eval(f"{w}.kindButtons")
    assert buttons.fastest.IsShown(buttons.fastest) and buttons.safe.IsShown(buttons.safe)
    assert buttons.nocost.IsShown(buttons.nocost) is False
    assert buttons.fastest.label.GetText(buttons.fastest.label).startswith("Fastest ")
    rows = [r.text for r in wow.eval(f"{w}.tree.rows").values() if r.text]
    assert any("Careful: level 20 creatures" in t for t in rows)
    # the verdict (A4.3): the fastest route passes the level 20, a level 12 reads "Risky trip"
    g = "Bastians:GetModule('Route').Graph"
    assert wow.eval(f"{g}.Verdict({R}.Active(), 12)") == "risky"
    assert "Risky trip" in wow.eval(f"{w}.summary:GetText()")
    # a click on Safest: that route, and the kind stays the default for the next route
    wow.execute(f"local b = {w}.kindButtons.safe; b:GetScript('OnClick')(b)")
    assert wow.eval(f"{R}.Active().kind") == "safe"
    assert wow.eval("Bastians:GetModule('Route').db.profile.routeKind") == "safe"
    rows = [r.text for r in wow.eval(f"{w}.tree.rows").values() if r.text]
    assert not any("Careful" in t for t in rows)
    wow.execute(f"{R}.Replan('test')")
    wow.run_frames(10)
    assert wow.eval(f"{R}.Active().kind") == "safe"  # a re-route keeps the kind
    assert wow.errors == []


STOPS = """{
  { id = 'turnin', name = 'Marshal', ref = 'npc:240', place = { map = 0, wx = 100, wy = 150 },
    after = { 'hill', 'road' } },
  { id = 'hill', name = 'Hill', place = { map = 0, wx = 300, wy = 150 } },
  { id = 'road', name = 'Road', place = { map = 0, wx = 100, wy = -50 } },
}"""


def test_a_tour_is_one_route_through_numbered_stops(wow: WowRuntime):
    """R26.4: the route service plans the stops in order (the turn-in last), one route whose steps
    know their stop, numbered pins for the stops before the last, and a re-route plans the stops
    still ahead again."""
    boot(wow)
    w = "Bastians:GetModule('Route').Window"
    assert wow.eval(f"Bastians:GetService('route'):Tour({STOPS}, 'Quest round')") is True
    wow.run_frames(20)
    route = wow.eval(f"{R}.Active()")
    assert route is not None and route.tour.name == "Quest round"
    names = [s.name for s in route.tour.stops.values()]
    assert sorted(names) == ["Hill", "Marshal", "Road"] and names[-1] == "Marshal"
    stops_of_steps = [s.stop for s in route.steps.values()]
    assert stops_of_steps == sorted(stops_of_steps) and stops_of_steps[-1] == 3
    assert route.goal.name == "3. Marshal" and route.goal.ref == "npc:240"
    pins = list(
        wow.eval("Bastians:QueryLayer('route.path', { continent = 0, level = 5 })").values()
    )
    labels = sorted(p.label for p in pins if p.label)
    assert labels == sorted([f"1. {names[0]}", f"2. {names[1]}", "3. Marshal"])
    wow.execute(f"{w}.Open()")
    assert wow.eval(f"{w}.summary:GetText()").startswith("Quest round: 3 stops, ")
    # walked past the first stop: a re-route plans the two ahead, the turn-in still last
    wow.execute(
        f"local r = {R}.Active(); for i, s in ipairs(r.steps) do if s.stop == 2 then r.index = i; "
        "break end end"
    )
    ahead = [s.id for s in wow.eval(f"{R}.TourAhead()").values()]
    assert len(ahead) == 2 and ahead[-1] == "turnin"
    wow.execute(f"{R}.Replan('test')")
    wow.run_frames(20)
    again = wow.eval(f"{R}.Active()")
    assert [s.name for s in again.tour.stops.values()][-1] == "Marshal"
    assert len(again.tour.stops) == 2
    assert wow.errors == []


def test_the_verdict_is_pure_and_unknown_is_not_safe(core: WowRuntime):
    core.start("Bastians_Core", "Bastians_Route")
    g = "Bastians:GetModule('Route').Graph"
    route = (
        "{ steps = { { mode = 'walk', danger = 15 }, { mode = 'fly' }, "
        "{ mode = 'walk', danger = 9 } } }"
    )
    assert core.eval(f"{g}.Verdict({route}, 12)") == "risky"  # 15 is 3 above
    assert core.eval(f"{g}.Verdict({route}, 14)") == "careful"  # 15 is 1 above
    assert core.eval(f"{g}.Verdict({route}, 18)") == "safe"  # every creature 3 or more below
    elite = "{ steps = { { mode = 'walk', danger = 12, elite = true } } }"
    assert core.eval(f"{g}.Verdict({elite}, 12)") == "risky"  # an elite counts 3 more
    assert core.eval(f"{g}.Verdict({{ steps = {{ {{ mode = 'fly' }} }} }}, 12)") is None
    assert core.eval(f"{g}.Verdict({route}, nil)") is None
    assert core.eval(f"{g}.Verdict(nil, 12)") is None
    assert core.errors == []


def test_a_stone_is_cast_where_one_stands_and_its_step_names_the_inn(wow: WowRuntime):
    """Forever 11.11.2026: "1. Go 3 yd E to the target (approx)",
    "2. Hearth to the target", "3. Go 78 yd W to Marshal Dughan". The first line was the walk
    to the network's nearest waypoint, which a hearthstone does not need, and the stone's step
    had no name for where it lands."""
    boot(wow)
    wow.execute(
        f"""
        local hearth = {{ mode = "hearth", jump = true, seconds = 10, name = "Goldshire",
          fromPlace = {{ map = 0, wx = 3, wy = 0 }}, toPlace = {{ map = 0, wx = 500, wy = 0 }},
          points = {{}} }}
        local walk = {{ mode = "walk", seconds = 11, yards = 78,
          points = {{ {{ wx = 500, wy = 0 }}, {{ wx = 578, wy = 0 }} }} }}
        route = {R}.FromGraph({{ seconds = 21, steps = {{ hearth, walk }} }},
          {{ continent = 0, wx = 0, wy = 0 }},
          {{ continent = 0, wx = 578, wy = 0, name = "Marshal Dughan" }})
        """
    )
    steps = list(wow.eval("route.steps").values())
    assert [s.mode for s in steps] == ["hearth", "walk"]  # no walk in front of the stone
    G = "Bastians:GetModule('Route').Graph"
    assert wow.eval(f"{G}.StepText(route.steps[1])") == "Hearth to Goldshire"
    assert (steps[0]["from"].wx, steps[0]["from"].wy) == (0, 0)  # from where the character stands
    assert wow.errors == []
