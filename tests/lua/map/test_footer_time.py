"""The footer's travel time (catalog review A4.2, 07.11.2026): the time from the character to the
point under the cursor, from the graph's time cache on the synthetic network of
tests/fixtures/navnet-mini (test_graph_network.py: the character stands at waypoint 1 (100, 300),
the east cluster at (100, -300) is FASTEST seconds away). Nothing without a network or before the
cache has the cell; the footer never searches."""

import sys
from pathlib import Path

from harness import WowRuntime

sys.path.insert(
    0, str(Path(__file__).resolve().parents[1] / "data")
)  # the graph tests' fixture pack
from test_graph_network import FASTEST, SETUP
from test_navnet_search import lua_pack

MAP_ = "Bastians:GetModule('Map').Map"


def open_map_at(wow: WowRuntime, wx: float, wy: float) -> None:
    wow.slash("/bmap")
    wow.execute(f"{MAP_}.clip:SetSize(600, 400); {MAP_}.ViewChanged()")
    wow.execute(f"{MAP_}.Fly(0, {wx}, {wy}, 3)")
    wow.advance(0.5)
    wow.execute(
        "Mock.cursorX, Mock.cursorY = 300, 200"
    )  # the centre of the clip: the flown-to point
    wow.execute(f"{MAP_}.UpdateFooter()")


def test_the_footer_says_how_far_the_point_under_the_cursor_is(wow: WowRuntime):
    wow.execute(SETUP)
    wow.start("Bastians_Core", "Bastians_Data", "Bastians_Map")
    wow.run_frames(5)
    # without a network: the footer says nothing of a time
    open_map_at(wow, 100, -300)
    assert "min" not in wow.eval(f"{MAP_}.footer:GetText()")
    assert wow.eval(f"{MAP_}.TimeTo(0, 100, -300)") is None
    # the network arrives; the first ask queues the cell, a job fills it, the next refresh shows it
    wow.execute(lua_pack())
    wow.execute("Bastians.Deliver()")
    wow.run_frames(5)
    wow.execute(f"{MAP_}.UpdateFooter()")
    if wow.eval(f"{MAP_}.TimeTo(0, 100, -300)") is None:
        wow.run_frames(5)
        wow.execute(f"{MAP_}.UpdateFooter()")
    expected = wow.eval(f"Bastians.UI.Duration({FASTEST})")
    assert expected == "1 min"
    footer = wow.eval(f"{MAP_}.footer:GetText()")
    assert f"   {expected}   " in footer and "zoom 3.0" in footer
    # another continent than the character's: no time (the graph's rule)
    assert wow.eval(f"{MAP_}.TimeTo(1, 0, 0)") is None
    # the character's own place: the first ask queues the cell, the job answers "< 1 min"
    wow.eval(f"{MAP_}.TimeTo(0, 100, 300)")
    wow.run_frames(5)
    assert wow.eval(f"{MAP_}.TimeTo(0, 100, 300)") == "< 1 min"
    assert wow.errors == []
