"""The session plan (world-graph.md §10, W10 step 3): Graph.PlanSession is pure (greedy by gain per
second within the budget, hourly stops worked for what is left, adjacent swaps that shorten the
way, nothing beyond the budget); g:Session plans over the activities in reach on the network
fixture and Explore shows the plan and hands it to the route service as a tour."""

import sys
from pathlib import Path

from harness import WowRuntime

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "route"))
from test_explore import boot, settle

PLAN = "Bastians.Data.Graph.PlanSession"


def plan(wow: WowRuntime, cands: str, budget: int, opts: str = "{}"):
    return wow.eval(f"{PLAN}({cands}, {budget}, {opts})")


def test_the_planner_fills_the_budget_by_gain_per_second(wow: WowRuntime):
    wow.start("Bastians_Core", "Bastians_Data")
    wow.run_frames(5)
    cands = """{
      { ref = "a", kind = "quest", value = 600, takes = 300, seconds = 60, place = { map = 0, wx = 0, wy = 0 } },
      { ref = "b", kind = "quest", value = 100, takes = 60, seconds = 30, place = { map = 0, wx = 50, wy = 0 } },
      { ref = "c", kind = "spot", value = 3600, hourly = true, seconds = 120, place = { map = 0, wx = 100, wy = 0 } },
      { ref = "far", kind = "quest", value = 9000, takes = 300, seconds = 5000, place = { map = 0, wx = 9000, wy = 0 } },
      { ref = "elsewhere", kind = "quest", value = 9000, takes = 60, seconds = 10, place = { map = 1, wx = 0, wy = 0 } },
    }"""
    p = plan(wow, cands, 1800, "{ speed = 7, stay = 3600, map = 0 }")
    order = [s.ref for s in p.stops.values()]
    # greedy: b (100 in 90 s beats a's 600 in 360 s), a, then the spot for what is left (b-a-c
    # and b-c-a walk the same way, so no swap); the far quest does not fit, the other continent
    # is out of reach
    assert order == ["b", "a", "c"]
    stops = list(p.stops.values())
    assert stops[0].arrive == 30 and stops[0].leave == 90 and stops[0].approx is False
    assert stops[1].approx is True and abs(stops[1].travel - 50 * 1.3 / 7) < 1e-6
    assert stops[2].hourly is True and abs(stops[2].leave - 1800) < 1e-6  # worked to the budget
    assert abs(p.total - 1800) < 1e-6 and abs(p.value - (100 + 600 + stops[2].gain)) < 1e-6
    assert abs(stops[2].gain - 3600 * stops[2].stay / 3600) < 1e-6
    # too little time for an hourly stop: left out
    # a short budget: a alone (the best gain per second; greedy, so b-then-a's 700 in 399 s is
    # not found), and no time for an hourly stop
    short = plan(wow, cands, 400, "{ speed = 7, stay = 3600, map = 0 }")
    assert [s.ref for s in short.stops.values()] == ["a"]
    assert wow.errors == []


def test_adjacent_swaps_shorten_the_way(wow: WowRuntime):
    wow.start("Bastians_Core", "Bastians_Data")
    wow.run_frames(5)
    # three equal quests in a line east of the character: greedy takes the nearest first, then the
    # farthest-but-best score may leave a zigzag; the swap pass straightens it
    cands = """{
      { ref = "near", kind = "quest", value = 100, takes = 60, seconds = 10, place = { map = 0, wx = 0, wy = -10 } },
      { ref = "mid", kind = "quest", value = 100, takes = 60, seconds = 100, place = { map = 0, wx = 0, wy = -500 } },
      { ref = "far", kind = "quest", value = 100, takes = 60, seconds = 200, place = { map = 0, wx = 0, wy = -1000 } },
    }"""
    p = plan(wow, cands, 3600, "{ speed = 7 }")
    assert [s.ref for s in p.stops.values()] == ["near", "mid", "far"]
    assert p.travel < 10 + 2 * 500 * 1.3 / 7 + 1
    assert wow.errors == []


def test_the_service_plans_over_the_activities_in_reach(wow: WowRuntime):
    boot(wow)
    assert wow.eval("g:Session(60, {})") is None  # the ways are being timed
    settle(wow)
    # the farm's gain per second beats the quick run's: it comes first and, worked for what is
    # left, fills the hour on its own
    p = wow.eval("g:Session(60, { by = 'gold' })")
    assert [s.ref for s in p.stops.values()] == ["testthing:2"]
    farm = p.stops[1]
    assert farm.hourly is True and abs(farm.leave - 3600) < 1e-6 and farm.gain > 0
    assert p.by == "copper" and p.budget == 3600 and p.waiting == 0
    # a stay of 30 minutes at most: the quick run too, first (the swap pass: it is nearer), the
    # farm last and stretched over what the shorter way saved
    p = wow.eval("g:Session(60, { by = 'gold', stay = 30 })")
    assert [s.ref for s in p.stops.values()] == ["testthing:1", "testthing:2"]
    assert p.stops[2].approx is True and abs(p.stops[2].leave - 3600) < 1e-6
    assert wow.errors == []


def test_explore_shows_the_plan_and_routes_it(wow: WowRuntime):
    boot(wow, "Bastians_Core", "Bastians_Data", "Bastians_Map", "Bastians_Route")
    explore = "Bastians:GetModule('Route').Explore"
    settle(wow)
    rows, summary, _ = wow.eval(f"{explore}.BuildPlan(60, 'gold')")
    assert summary.startswith("Plan for 60 min: 1 stops")
    assert (
        rows[1].title == "1. Thing 2"
        and "arrive in" in rows[1].meta
        and rows[1].valueKind == "money"
    )
    rows, _, _ = wow.eval(f"{explore}.BuildPlan(10, 'xp')")
    assert rows[1].title == "1. Thing 1" and rows[1].valueKind == "text"
    # the plan as a tour through the route service
    assert wow.eval(f"{explore}.RoutePlan(select(3, {explore}.BuildPlan(60, 'gold')))") is True
    wow.run_frames(40)
    active = wow.eval("Bastians:GetModule('Route').Route.Active()")
    assert active and active.tour and active.tour.name == "My plan" and len(active.tour.stops) == 1
    assert wow.errors == []
