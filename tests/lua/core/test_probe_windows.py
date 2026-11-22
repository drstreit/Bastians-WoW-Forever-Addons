"""The windows probe (W4 of plan-suite-waves.md, ADR 0084): every app with a window opened in
turn, measured, photographed and closed; what overflows named; the windows open before opened
again; once by itself after a login, `/bprobe windows` by hand; tools/look_windows.py prints the
record. On the mock nothing is laid out from its anchors as the client does, so what overflows in
the game is not held here: the record's shape, the order of the run and the named kinds are."""

import sys
from pathlib import Path

from harness import WowRuntime

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools"))
import look_windows

RESULTS = "BastiansProbeDB.results"
APPS = ("Bastians_Core", "Bastians_Notes", "Bastians_Alts")


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(*APPS)
    wow.run_frames(5)
    return wow


def load_probe(wow: WowRuntime) -> None:
    wow.load_addon("Bastians_Probe")
    wow.fire("ADDON_LOADED", "Bastians_Probe")


def wait(wow: WowRuntime, steps: int = 20) -> None:
    for _ in range(steps):
        wow.advance(0.7)


def test_every_apps_window_is_opened_photographed_and_closed(wow: WowRuntime):
    boot(wow)
    load_probe(wow)
    wow.execute("Bastians:OpenApp('Notes')")  # open before: closed for the run, opened after
    notes = "(function() for n, w in pairs(Bastians.UI.Windows) do if w.frame:IsShown() then return n end end end)()"
    before = wow.eval(notes)
    assert before is not None
    wow.slash("/bprobe windows")
    wait(wow)
    out = f"{RESULTS}.windows"
    assert wow.eval(f"{out}.look") == "book" and wow.eval(f"{out}.theme") == "folio"
    apps = {wow.eval(f"{out}.windows[{i}].app") for i in range(1, wow.eval(f"#{out}.windows") + 1)}
    assert {"Notes", "Alts"} <= apps
    first = f"{out}.windows[1]"
    assert wow.eval(f"{first}.screenshot.ok") is True
    assert wow.eval(f"{first}.width") > 0 and wow.eval(f"{first}.height") > 0
    for kind in ("cut", "wide", "outside"):
        assert wow.eval(f"type({first}.{kind})") == "table", kind
    # the window open before is open again, the ones the probe opened are closed
    assert wow.eval(f"Bastians.UI.Windows['{before}'].frame:IsShown()") is True
    for i in range(1, wow.eval(f"#{out}.windows") + 1):
        name = wow.eval(f"{out}.windows[{i}].window")
        if name != before:
            assert wow.eval(f"Bastians.UI.Windows['{name}'].frame:IsShown()") is False, name
    assert wow.eval("BastiansProbeDB.sequences['w4-1'].at ~= nil") is True
    lines = look_windows.report(wow.eval(out))
    assert lines[0].startswith("windows ") and "theme folio, look book" in lines[0]
    assert any("Notes / " in line for line in lines)
    assert wow.errors == []


LONG = "A label far too long for a button of sixty"


def test_a_cut_label_and_a_part_outside_are_named(wow: WowRuntime):
    boot(wow)
    load_probe(wow)
    wow.execute(
        f"""
        local S = Bastians.UI.Style
        local win
        Bastians:NewModule("ProbeTestApp", {{ addon = "Bastians_Core", open = function()
          if not win then
            win = Bastians.UI.Window("BastiansProbeTestWindow", {{ title = "Test" }})
            win.frame:SetSize(300, 200)
            local cut = S.button(win.content, {LONG!r}, 60, 20)
            cut:SetPoint("TOPLEFT", win.content, "TOPLEFT", 10, -10)
            local out = CreateFrame("Frame", "BastiansProbeTestOutside", win.frame)
            out:SetPoint("TOPLEFT", win.frame, "TOPLEFT", 0, 0)
            out:SetSize(340, 20) -- the mock lays a frame at 0,0: wider than its window
          end
          win:Show()
        end }})
        """
    )
    wow.slash("/bprobe windows")
    wait(wow)
    out = f"{RESULTS}.windows"
    n = wow.eval(f"#{out}.windows")
    mine = next(
        f"{out}.windows[{i}]"
        for i in range(1, n + 1)
        if wow.eval(f"{out}.windows[{i}].app") == "ProbeTestApp"
    )
    assert wow.eval(f"{mine}.cut[1]") == LONG
    assert wow.eval(f"{mine}.outside[1].what") == "BastiansProbeTestOutside"
    assert round(wow.eval(f"{mine}.outside[1].r")) == 40  # 40 units past the right edge
    lines = "\n".join(look_windows.report(wow.eval(out)))
    assert f"cut: {LONG}" in lines
    assert "outside: BastiansProbeTestOutside (right 40)" in lines
    assert wow.errors == []


def test_the_city_maps_pins_are_counted_and_undrawn_trainers_named(wow: WowRuntime):
    """ "on the separate city map, some trainers are missing": per sheet
    the query's pins by layer, the cap, and each trainer of the Trainers layer that is not drawn."""
    wow.start("Bastians_Core", "Bastians_Data", "Bastians_Map")
    wow.run_frames(5)
    wow.execute(
        """
        Bastians.Map = Bastians.Map or {}
        Bastians.Map.cities = { { ui = 1453, name = "Stormwind City", continent = 0,
          wx = { -9154.17, -7995.83 }, wy = { -14.584, 1722.92 }, w = 4008, h = 2672,
          rows = 3, cols = 4, path = "Cities/1453_" } }
        local real = Bastians.QueryLayer
        function Bastians:QueryLayer(id, view)
          if id == "map.trainers" then
            return { { ref = "npc:5159", label = "Daryl Riknussun (Cooking)", wx = -8800, wy = 700 },
              { kind = "path", points = {} } }
          end
          return real(self, id, view)
        end
        """
    )
    load_probe(wow)
    wow.slash("/bprobe windows")
    wait(wow)
    city = f"{RESULTS}.windows.cities[1]"
    assert wow.eval(f"{city}.ui") == 1453 and wow.eval(f"{city}.cap") == 300
    assert wow.eval(f"type({city}.total)") == "number"
    assert wow.eval(f"{city}.trainers") == 1  # the path is no trainer
    assert wow.eval(f"{city}.trainersOn") is False  # the layer is off in that window by default
    assert wow.eval(f"{city}.missing[1]") == "Daryl Riknussun (Cooking)"
    text = "\n".join(look_windows.report(wow.eval(f"{RESULTS}.windows")))
    assert "Stormwind City: " in text and "trainers 1 (layer off)" in text
    assert "trainers not drawn: Daryl Riknussun (Cooking)" in text
    assert wow.errors == []


def test_the_probe_runs_once_after_a_login_and_waits_out_a_fight(wow: WowRuntime):
    boot(wow)
    wow.execute("BastiansProbeDB = { sequences = { ['w2-1'] = { at = 'before' } } }")
    load_probe(wow)
    wow.set_combat(True)
    wow.login()
    wow.advance(31)
    assert wow.eval(f"{RESULTS}.windows") is None  # in a fight nothing opens
    wow.set_combat(False)
    wow.fire("PLAYER_REGEN_ENABLED")
    wait(wow)
    assert wow.eval(f"#{RESULTS}.windows.windows") >= 2
    # the next login does not run it again
    wow.execute(f"{RESULTS}.windows = nil")
    wow.login()
    wait(wow, 50)
    assert wow.eval(f"{RESULTS}.windows") is None
    assert wow.errors == []
