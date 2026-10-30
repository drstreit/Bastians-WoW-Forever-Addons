"""The walk sampler (world-graph.md §9, W11): while the character moves, its position is sampled
every two seconds against the network; a stretch farther than 40 yards from every waypoint is
learned as a walk when it is long enough, with the last point on the network before and the
first after as its ends; the walk is an edge of the graph for this player at once, with its own
points in the route's step. A short detour is nothing."""

from harness import WowRuntime
from test_graph_network import SETUP
from test_navnet_search import lua_pack

G = "Bastians.Data.Graph"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.execute(SETUP)
    wow.start("Bastians_Core", "Bastians_Data")
    wow.run_frames(5)
    wow.execute(lua_pack())
    wow.execute("Bastians.Deliver(); g = Bastians:GetService('graph')")
    return wow


def stand(wow: WowRuntime, x: float, y: float) -> None:
    """Puts the character at map fractions (x, y) of the test map: world (1000 y, 1000 - 2000 x)."""
    wow.execute(f"Mock.playerMapPos = {{ x = {x}, y = {y} }}")


def test_a_stretch_off_the_network_is_learned_as_a_walk_and_routes_at_once(wow: WowRuntime):
    boot(wow)
    # on the network at the start (100, 300), then across the "nowhere" cluster (no ground), then
    # back on at the east place (100, -300)
    stand(wow, 0.35, 0.1)
    assert wow.eval(f"{G}.Sample()") == "on"
    for x, y in ((0.05, 0.9), (0.05, 0.6), (0.05, 0.3)):  # world (900, 900), (600, 900), (300, 900)
        stand(wow, x, y)
        assert wow.eval(f"{G}.Sample()") == "off"
    stand(wow, 0.65, 0.1)
    assert wow.eval(f"{G}.Sample()") == "learned"
    walks = list(wow.eval("g:Learned().walk").values())
    assert len(walks) == 1 and walks[0].map == 0 and walks[0].len > 2000
    pts = list(walks[0].points.values())
    assert [tuple(p.values()) for p in (pts[0], pts[-1])] == [(100, 300), (100, -300)]
    assert len(pts) == 5  # the point on the network before, three off, the one after
    # the walk is an edge both ways for this player
    wow.execute(
        "EXTRA = {}; " + G + ".WalkEdges(Bastians.Data.Graph.NetFor(0), EXTRA, g:Learned().walk, 7)"
    )
    edges = [(k, list(v.values())) for k, v in wow.eval("EXTRA").items()]
    assert len(edges) == 2 and all(e[0].learned and e[0].mode == "walk" for _, e in edges)
    assert wow.errors == []


def test_short_detours_and_stops_off_the_network_are_not_walks(wow: WowRuntime):
    boot(wow)
    stand(wow, 0.35, 0.1)
    wow.fire("PLAYER_STARTED_MOVING")
    assert wow.eval(f"{G}.sampler.ticker ~= nil") is True
    stand(wow, 0.05, 0.9)
    wow.advance(2.1)  # one tick off the network
    wow.fire("PLAYER_STOPPED_MOVING")  # stopped out there: the stretch ends without an end on it
    assert wow.eval(f"{G}.sampler.ticker") is None
    assert len(wow.eval("g:Learned().walk")) == 0  # two points, 1000 yards: too few points
    # a learned walk needs a map and two points at least
    assert wow.eval("g:Learn({ kind = 'walk', points = { { 1, 2 }, { 3, 4 } } })") is False
    assert wow.eval("g:Learn({ kind = 'walk', map = 0, points = { { 1, 2 } } })") is False
    assert (
        wow.eval("g:Learn({ kind = 'walk', map = 0, points = { { 1, 2 }, { 3, 4 } }, len = 3 })")
        is True
    )
    assert wow.errors == []
