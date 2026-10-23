"""Performance budgets on the mock (nfr.md, B11.1): the whole suite loaded, nothing runs while idle
(no shown frame with OnUpdate, no repeating timers), and the heavy paths (map pan with every layer,
a quest log refresh, the windows) stay within generous mock-time limits as a regression guard. Real
numbers come from `/bastians perf` in game and tools/perf_report.py."""

import time

from harness import WowRuntime

ALL = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Gold",
    "Bastians_Browser",
    "Bastians_Map",
    "Bastians_Route",
)
MAP_ = "Bastians:GetModule('Map').Map"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(*ALL)
    wow.run_frames(10)
    wow.advance(1)
    return wow


def updating_frames(wow: WowRuntime) -> list:
    return [
        f
        for f in wow.eval("Mock.frames").values()
        if f.scripts.OnUpdate is not None and not f.IsVisible(f)
    ]


def test_idle_suite_has_no_onupdate_on_hidden_frames_and_no_repeating_timers(wow: WowRuntime):
    boot(wow)
    # open and close every window once: closing must leave nothing ticking
    for cmd in ("/bq", "/bgold", "/bb", "/bmap", "/broute"):
        wow.slash(cmd)
        wow.run_frames(2)
        wow.slash(cmd)
    wow.run_frames(5)
    wow.advance(2)
    # hidden frames may keep an OnUpdate script (the client never runs it); the Jobs runner does
    assert all(f.GetName(f) is None for f in updating_frames(wow))
    shown_updating = [
        f
        for f in wow.eval("Mock.frames").values()
        if f.scripts.OnUpdate is not None and f.IsVisible(f)
    ]
    assert shown_updating == []  # nothing polls while every window is closed
    assert wow.eval("Mock.ActiveTimers(true)") == 0  # no repeating ticker while idle
    assert wow.errors == []


def test_heavy_paths_stay_within_mock_budgets(wow: WowRuntime):
    boot(wow)
    wow.slash("/bmap")
    wow.execute(f"{MAP_}.clip:SetSize(800, 600); {MAP_}.ViewChanged()")
    wow.execute(
        "for _, def in ipairs(Bastians:GetMapLayers()) do Bastians:GetModule('Map').Pins.SetLayerOn(def.id, true) end"
    )
    wow.advance(0.2)
    worst = 0.0
    for level in (2, 4, 6):
        for step in range(6):
            t0 = time.perf_counter()
            wow.execute(f"{MAP_}.Fly(0, {-300 + step * 100}, {-300 + step * 100}, {level})")
            wow.advance(0.2)  # the settle: every layer is queried and drawn
            worst = max(worst, time.perf_counter() - t0)
    assert worst < 0.25, (
        f"a map view change with every layer took {worst * 1000:.0f} ms on the mock"
    )
    t0 = time.perf_counter()
    wow.fire("QUEST_LOG_UPDATE")
    wow.advance(0.5)
    assert time.perf_counter() - t0 < 0.25
    stats = wow.eval("Bastians.Perf.modules")
    assert "Map" in stats and stats.Map.calls > 0  # the meter saw the work
    assert wow.errors == []
