"""The game's tracking dots on Bastian's minimap styles:
our tiles cover the game's minimap there, so its dots (Find Herbs, Find Minerals) are read back by
asking the minimap's tooltip over a grid, grouped by name, placed in world yards by the game
minimap's own size and zoom, and shown as pins of the overlay. Nothing runs in the game's style,
nothing without the client's calls, nothing while our frame is hidden."""

import math

from harness import WowRuntime
from test_mini import MINI, MOD, boot, pencil, setting

TR = f"{MOD}.Tracked"
MM = f"{MOD}.Minimap"


def our_style(wow: WowRuntime) -> None:
    pencil(wow)
    wow.execute(f"{MOD}.db.profile.miniWarned = true; {MINI}.SetStyle('pencil')")
    wow.run_frames(2)


def blips(wow: WowRuntime, *dots: tuple[float, float, str]) -> None:
    rows = ", ".join(f"{{ u = {u}, v = {v}, name = '{name}' }}" for u, v, name in dots)
    wow.execute(f"Mock.minimapBlips = {{ {rows} }}")


def sweep(wow: WowRuntime, frames: int = 16) -> None:
    """One sweep: the wait, the frames of probing, then the overlay's coalesced query."""
    wow.advance(1.5)
    wow.run_frames(frames)
    wow.advance(0.3)
    wow.run_frames(2)


def tracked_pins(wow: WowRuntime) -> dict[str, object]:
    out = {}
    for pin in wow.eval(f"{MM}.Pins()").values():
        if str(pin.ref).startswith("tracked:"):
            out[pin.label] = pin
    return out


def settle(wow: WowRuntime) -> None:
    """The overlay's coalesced query after a stop or a style change."""
    wow.run_frames(3)
    wow.advance(0.3)
    wow.run_frames(2)


def player(wow: WowRuntime) -> tuple[float, float]:
    vals = wow.eval("Bastians.Coords.Player()")  # continent, wx, wy, and the map behind them
    return vals[1], vals[2]


def test_nothing_runs_in_the_games_style_or_without_the_calls(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f"{MINI}.Style()") == "game"
    assert wow.eval(f"{TR}.Running()") is False
    blips(wow, (20, 0, "Peacebloom"))
    sweep(wow)
    assert wow.eval("Mock.minimapProbes") == 0
    assert tracked_pins(wow) == {}
    # our style, but the client lacks the calls: nothing runs, the settings' note says why (the mock
    # raises on an unknown PascalCase method, so the absence is a non-function value)
    wow.execute("Minimap.UpdateMouseoverAtPoint = false")
    our_style(wow)
    assert wow.eval(f"{TR}.Running()") is False
    assert wow.eval(f"({TR}.Available()) == nil") is True
    assert "minimap" in wow.eval(f"{TR}.Note()")
    sweep(wow)
    assert wow.eval("Mock.minimapProbes") == 0
    assert wow.errors == []


def test_the_dots_become_pins_at_their_place_in_world_yards(wow: WowRuntime):
    boot(wow)
    our_style(wow)
    assert wow.eval(f"{TR}.Available() == true") is True
    assert wow.eval(f"{TR}.Running()") is True
    assert wow.eval(f"{TR}.Note()") is None
    # 20 px right of the centre, 30 px up: east and north of the player at the game minimap's scale
    blips(wow, (20, 0, "Peacebloom"), (0, 30, "Copper Vein"))
    sweep(wow)
    assert wow.eval("Mock.minimapProbes") > 0
    assert wow.eval("Minimap.softCursor") is False  # given back after the sweep
    pins = tracked_pins(wow)
    assert set(pins) == {"Peacebloom", "Copper Vein"}
    px, py = player(wow)
    scale = wow.eval(f"{MM}.Scale()")  # pixels per yard of the game's minimap at its own zoom
    tolerance = wow.eval(f"{TR}.STEP") / scale  # a grid point's reach
    herb, ore = pins["Peacebloom"], pins["Copper Vein"]
    assert math.isclose(herb.wx, px, abs_tol=tolerance) and math.isclose(
        herb.wy, py - 20 / scale, abs_tol=tolerance
    )
    assert math.isclose(ore.wx, px + 30 / scale, abs_tol=tolerance) and math.isclose(
        ore.wy, py, abs_tol=tolerance
    )
    assert herb.card(herb).title == "Peacebloom"
    # the pins are drawn by the overlay on our style
    shown = [f.pin.label for f in wow.eval(f"{MM}.pool").values() if f.IsShown(f) and f.pin]
    assert "Peacebloom" in shown and "Copper Vein" in shown
    assert wow.errors == []


def test_a_dot_found_again_keeps_its_pin_and_a_gone_one_leaves_after_two_sweeps(wow: WowRuntime):
    boot(wow)
    our_style(wow)
    blips(wow, (20, 0, "Peacebloom"), (-40, -10, "Peacebloom"))
    sweep(wow)
    pins = wow.eval(f"{TR}.Known()")
    assert len(pins) == 2  # two dots of one name, apart: two pins
    refs = sorted(p.ref for p in pins.values())
    sweep(wow)
    assert (
        sorted(p.ref for p in wow.eval(f"{TR}.Known()").values()) == refs
    )  # found again: the same
    blips(wow, (20, 0, "Peacebloom"))
    sweep(wow)
    assert len(wow.eval(f"{TR}.Known()")) == 2  # unseen once: kept
    sweep(wow)
    assert len(wow.eval(f"{TR}.Known()")) == 2
    sweep(wow)
    assert len(wow.eval(f"{TR}.Known()")) == 1  # unseen three times: gone
    assert wow.errors == []


def test_the_games_style_the_setting_and_a_hidden_frame_stop_the_sweep(wow: WowRuntime):
    boot(wow)
    our_style(wow)
    blips(wow, (20, 0, "Peacebloom"))
    sweep(wow)
    assert len(tracked_pins(wow)) == 1
    wow.execute(f"{MINI}.SetStyle('game')")
    settle(wow)
    assert wow.eval(f"{TR}.Running()") is False
    assert tracked_pins(wow) == {}
    wow.execute(f"{MINI}.SetStyle('pencil')")
    sweep(wow)
    assert len(tracked_pins(wow)) == 1
    setting(wow, "miniTracked", "false")
    settle(wow)
    assert wow.eval(f"{TR}.Running()") is False and tracked_pins(wow) == {}
    setting(wow, "miniTracked", "true")
    sweep(wow)
    assert wow.eval(f"{TR}.Running()") is True
    setting(wow, "miniMap", "false")
    assert wow.eval(f"{TR}.Running()") is False
    assert wow.errors == []


def test_the_grouping_and_the_yard_conversion_are_pure(wow: WowRuntime):
    boot(wow)
    groups = wow.eval(
        f"{TR}.Cluster({{ {{ 0, 0 }}, {{ 8, 0 }}, {{ 0, 8 }}, {{ 8, 8 }}, {{ 100, 100 }}, {{ 108, 100 }} }}, 8)"
    )
    assert [(g.u, g.v, g.n) for g in groups.values()] == [(4.0, 4.0, 4), (104.0, 100.0, 2)]
    # 10 px right at 0.5 px per yard: 20 yd east, which is 20 yd less wy; up is north, more wx
    assert tuple(wow.eval(f"{TR}.ToWorld(10, 0, 0.5, nil, 1000, 2000)")) == (1000, 1980)
    assert tuple(wow.eval(f"{TR}.ToWorld(0, 10, 0.5, nil, 1000, 2000)")) == (1020, 2000)
    # a rotating minimap: facing east (a quarter turn) puts "ahead" up, so up is east
    wx, wy = wow.eval(f"{TR}.ToWorld(0, 10, 0.5, -math.pi / 2, 1000, 2000)")
    assert math.isclose(wx, 1000, abs_tol=1e-6) and math.isclose(wy, 1980, abs_tol=1e-6)
