"""Several stops (route.md "Several stops", R26.4): the order of a tour (Graph.OrderStops, pure)
and graph:Tour over the generator's record of tests/fixtures/navnet-mini, the character at
waypoint 1 (100, 300) (test_graph_network.py)."""

import itertools
import random

import pytest
from harness import WowRuntime
from test_graph_network import SETUP
from test_navnet_search import lua_pack

ORDER = "Bastians.Data.Graph.OrderStops"


@pytest.fixture
def graph(wow: WowRuntime) -> WowRuntime:
    wow.execute(SETUP)
    wow.start("Bastians_Core", "Bastians_Data")
    wow.run_frames(5)
    wow.execute(lua_pack())
    wow.execute("Bastians.Deliver(); g = Bastians:GetService('graph')")
    return wow


def lua_matrix(t: list[list[float]]) -> str:
    rows = ", ".join(
        f"[{i}] = {{ " + ", ".join(f"[{j}] = {v}" for j, v in enumerate(row)) + " }"
        for i, row in enumerate(t)
    )
    return "{ " + rows + " }"


def lua_before(before: dict[int, set[int]]) -> str:
    return (
        "{ "
        + ", ".join(
            f"[{j}] = {{ " + ", ".join(f"[{i}] = true" for i in sorted(s)) + " }"
            for j, s in before.items()
        )
        + " }"
    )


def order(wow, t, before):
    n = len(t) - 1
    result, total = wow.eval(f"{ORDER}({lua_matrix(t)}, {n}, {lua_before(before)})")
    return list(result.values()), total


def cost(t, route):
    total, prev = 0, 0
    for j in route:
        total, prev = total + t[prev][j], j
    return total


def feasible(route, before):
    at = {j: p for p, j in enumerate(route)}
    return all(at[i] < at[j] for j, needs in before.items() for i in needs)


def test_stops_on_a_line_in_the_cheapest_order_that_keeps_the_needs(wow: WowRuntime):
    wow.start("Bastians_Core", "Bastians_Data")
    xs = [0, 5, 1, 3]  # the start at 0, stops at 5, 1 and 3
    t = [[abs(a - b) for b in xs] for a in xs]
    route, total = order(wow, t, {})
    assert route == [2, 3, 1] and total == 5  # 1, 3, 5 along the line
    route, total = order(wow, t, {2: {1}})  # the stop at 1 only after the one at 5
    assert feasible(route, {2: {1}}) and total == 9


def test_the_order_is_near_the_best_on_small_tours(wow: WowRuntime):
    """Against every order of six stops on fixed random maps: always feasible, within 10 % of the
    best, and the best in most of them."""
    wow.start("Bastians_Core", "Bastians_Data")
    rng = random.Random(26)
    best_hits = 0
    for _ in range(12):
        pts = [(rng.uniform(0, 100), rng.uniform(0, 100)) for _ in range(7)]
        t = [[round(((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2) ** 0.5, 3) for b in pts] for a in pts]
        before = {6: {1, 2}, 5: {3}}  # two turn-ins after their objectives
        route, total = order(wow, t, before)
        assert sorted(route) == [1, 2, 3, 4, 5, 6] and feasible(route, before)
        assert abs(total - cost(t, route)) < 1e-6
        best = min(
            cost(t, p) for p in itertools.permutations(range(1, 7)) if feasible(list(p), before)
        )
        assert total <= best * 1.10 + 1e-6
        best_hits += total <= best + 1e-6
    assert best_hits >= 8


def test_a_tour_over_the_network_keeps_the_turn_in_last(graph):
    """Two objectives (waypoints 4 and 5) and their turn-in at waypoint 2: the turn-in comes after
    both, every leg is a shaped route ending at its stop, a stop on another continent is skipped."""
    graph.execute(
        """T, WHY = nil, nil
        g:Tour('player', {
          { id = 'turnin', name = 'Marshal', place = { map = 0, wx = 100, wy = 150 },
            after = { 'hill', 'road' } },
          { id = 'hill', name = 'Hill', place = { map = 0, wx = 300, wy = 150 } },
          { id = 'road', name = 'Road', place = { map = 0, wx = 100, wy = -50 } },
          { id = 'far', name = 'Kalimdor', place = { map = 1, wx = 0, wy = 0 } },
        }, {}, function(t, why) T, WHY = t, why end)"""
    )
    graph.run_frames(20)
    t = graph.eval("T")
    assert t is not None, graph.eval("WHY")
    ids = list(t.order.values())
    assert sorted(ids) == ["hill", "road", "turnin"] and ids[-1] == "turnin"
    assert t.skipped.far == "another continent"
    legs = list(t.legs.values())
    assert [leg.goal for leg in legs] == [
        {"hill": "Hill", "road": "Road", "turnin": "Marshal"}[i] for i in ids
    ]
    assert abs(t.seconds - sum(leg.seconds for leg in legs)) < 0.01
    assert graph.errors == []
