"""The Route window in the one look (ADR 0084, W9 of plan-suite-waves.md; route.md "The one
look"): the line of what the route is, the kinds as chips in a band, the hint and the tools Home,
Replan and Clear in a foot. The numbers are the suite's board's."""

import sys
from pathlib import Path

from harness import WowRuntime

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "data"))
from test_graph_network import SETUP
from test_navnet_search import lua_pack

CORE, DATA, ROUTE = "Bastians_Core", "Bastians_Data", "Bastians_Route"
# a level 20 creature on the road, so the safest way differs from the fastest (test_route_graph.py)
DANGER = {"hostile": [[0, 100.0, 120.0, 20, False]], "guards": []}
MOD = "Bastians:GetModule('Route')"
R = f"{MOD}.Route"
W = f"{MOD}.Window"
S = "Bastians.UI.Style"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, ROUTE)))
    wow.run_frames(5)
    return wow


def boot_graph(wow: WowRuntime) -> WowRuntime:
    """Data's network of the fixture, and a route over it in its three kinds."""
    wow.execute(SETUP)
    wow.start(CORE, DATA, ROUTE)
    wow.run_frames(5)
    wow.execute(lua_pack(DANGER))
    wow.execute("Bastians.Deliver()")
    wow.execute(f"{R}.ToPoint(0, 100, -300, 'The Deadmines')")
    wow.run_frames(20)
    return wow


def right_edge(wow: WowRuntime, button: str) -> tuple:
    """A foot tool's anchor: what it stands before, and how far."""
    point = tuple(wow.eval(f"{{ {button}:GetPoint(1) }}").values())
    return point[0], point[2], point[3]


def test_without_a_route_the_window_is_the_line_and_home(wow: WowRuntime):
    boot(wow)
    wow.slash("/broute")
    win = f"{W}.win"
    assert wow.eval(f"{win}.headKind") == "low" and wow.eval(f"{win}.opts.bareHead") is True
    # the line in the text size 13, 15 from the side and 8 under the top
    assert tuple(wow.eval(f"{W}.summary:GetFont()"))[1] == 13
    assert tuple(wow.eval(f"{{ {W}.summary:GetPoint(1) }}").values())[3:] == (15, -8)
    assert wow.eval(f"{W}.summary:GetText()").startswith("No route.")
    # the hint takes two lines: on one it needed 402 units of the window's 398 (the windows
    # probe, 24.11.2026); nothing stands under it without a route
    assert wow.eval(f"{W}.summary.wordWrap") is True
    assert wow.eval(f"{W}.summary:GetHeight()") == 30
    # no kinds: no band; the foot keeps Home alone at its end and says nothing
    assert wow.eval(f"{W}.band.frame:GetHeight()") == 1
    assert wow.eval(f"{W}.band.ground:IsShown()") is False
    assert wow.eval(f"{W}.hint:GetHeight()") == 34 and wow.eval(f"{W}.hint:GetText()") == ""
    home, replan, clear = f"{W}.homeButton", f"{W}.replanButton", f"{W}.clearButton"
    assert wow.eval(f"{home}:IsShown()") is True
    assert wow.eval(f"{replan}:IsShown()") is False and wow.eval(f"{clear}:IsShown()") is False
    assert right_edge(wow, home) == ("RIGHT", "RIGHT", -18)  # clear of the window's grip
    assert wow.errors == []


def test_a_route_has_its_kinds_as_chips_and_its_tools_in_the_foot(wow: WowRuntime):
    boot_graph(wow)
    wow.execute(f"{W}.Open()")
    wow.execute(f"{W}.win.content:SetWidth(438); {W}.Render()")
    assert wow.eval(f"{W}.summary:GetText()").startswith("To The Deadmines: ")
    assert wow.eval(f"{W}.summary.wordWrap") is False  # one line over the chips
    assert wow.eval(f"{W}.summary:GetHeight()") == 14
    # the kinds: chips on the band, the kind in use filled; No flights equals Fastest here
    kinds = f"{W}.kindButtons"
    shown = [k for k in ("fastest", "safe", "nocost") if wow.eval(f"{kinds}.{k}:IsShown()")]
    assert shown == ["fastest", "safe"]
    for k in shown:
        chip = f"{kinds}.{k}"
        assert wow.eval(f"{S}.widgets[{chip}]") == "pill" and wow.eval(f"{chip}.small") is True
        assert wow.eval(f"{chip}:GetHeight()") == 22
        assert wow.eval(f"{chip}:GetParent() == {W}.band.frame") is True
    assert (
        wow.eval(f"{kinds}.fastest.spec.on") is True and wow.eval(f"{kinds}.safe.spec.on") is None
    )
    assert wow.eval(f"{kinds}.fastest.label:GetText()").startswith("Fastest ")
    assert tuple(wow.eval(f"{{ {kinds}.fastest:GetPoint(1) }}").values())[3:] == (15, -10)
    fx = wow.eval(f"{kinds}.fastest:GetWidth()")
    assert tuple(wow.eval(f"{{ {kinds}.safe:GetPoint(1) }}").values())[3:] == (15 + fx + 5, -10)
    # a click on Safest: that route, its chip filled
    wow.execute(f"{kinds}.safe:Click()")
    assert wow.eval(f"{R}.Active().kind") == "safe" and wow.eval(f"{kinds}.safe.spec.on") is True
    assert wow.eval(f"{kinds}.fastest.spec.on") is None
    assert wow.eval(f"{W}.band.frame:GetHeight()") == 10 + 22 + 9
    assert wow.eval(f"{W}.band.ground:IsShown()") is True
    # the foot: the hint, then Home, Replan, Clear as tools (words in an outline, 22 high)
    assert wow.eval(f"{W}.hint:GetText()") == "Click a step to see its end on the map."
    home, replan, clear = f"{W}.homeButton", f"{W}.replanButton", f"{W}.clearButton"
    for tool in (home, replan, clear):
        assert wow.eval(f"{tool}:IsShown()") is True and wow.eval(f"{tool}:GetHeight()") == 22
        assert wow.eval(f"{tool}.spec.boxed") is True and wow.eval(f"{tool}.spec.icon") is None
        assert wow.eval(f"{tool}:GetParent() == {W}.hint") is True and wow.eval(f"{tool}.tip")
    assert right_edge(wow, clear) == ("RIGHT", "RIGHT", -18)
    assert wow.eval(f"select(2, {replan}:GetPoint(1)) == {clear}") is True
    assert wow.eval(f"select(2, {home}:GetPoint(1)) == {replan}") is True
    # the hint ends before Home (the windows probe, 23.11.2026: it ran under the button)
    assert wow.eval(f"select(2, {W}.hint.text:GetPoint(2)) == {home}") is True
    # Clear takes the route, its band and its tools away
    wow.execute(f"{clear}:Click()")
    wow.advance(0.1)
    assert wow.eval(f"{R}.Active()") is None
    assert wow.eval(f"{W}.band.frame:GetHeight()") == 1 and wow.eval(f"{clear}:IsShown()") is False
    assert right_edge(wow, home) == ("RIGHT", "RIGHT", -18)
    assert wow.errors == []


def test_route_works_with_core_alone(wow: WowRuntime):
    """W9's gate (ADR 0083): the app loads and works with Core alone: no Data, no Map."""
    boot(wow, CORE, ROUTE)
    assert wow.eval(f"{MOD}:IsEnabled()") is True
    wow.slash("/broute")
    assert wow.eval(f"{W}.IsShown()") is True
    assert wow.eval(f"{W}.summary:GetText()").startswith("No route.")
    assert wow.eval(f"{W}.homeButton:IsShown()") is True
    # a way on the continent the character stands on needs no data: Route's own planner
    wow.execute(
        f"P = {R}.Plan({{ continent = 0, wx = 0, wy = 0 }},"
        f" {{ continent = 0, wx = 300, wy = 400, name = 'the mill' }}); {R}.Set(P); {W}.Render()"
    )
    assert wow.eval(f"{W}.summary:GetText()").startswith("To the mill: ")
    assert wow.eval(f"{W}.clearButton:IsShown()") is True
    assert wow.errors == []
