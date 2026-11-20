"""The probes of W2 (plan-suite-waves.md W2, package 5): `booklook small`, `bookmodel`,
`bookreveal`, the perf snapshot after login, and the one sequence that runs them on one restart.

On the mock no model is drawn and no file is missing, so what the client will answer is not held
here; the records' shape, that every call is tried and none raises, that the window comes back to
the reader's scale and size, and that the sequence runs once are."""

import sys
from pathlib import Path

from harness import WowRuntime
from test_book_pages import MOD, boot

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools"))
import book_look

RESULTS = "BastiansProbeDB.results"


def load_probe(wow: WowRuntime) -> None:
    wow.load_addon("Bastians_Probe")
    wow.fire("ADDON_LOADED", "Bastians_Probe")


def wait(wow: WowRuntime, steps: int = 12) -> None:
    for _ in range(steps):
        wow.advance(0.7)


def test_the_small_screen_is_measured_at_its_scale_and_the_window_put_back(wow: WowRuntime):
    boot(wow)
    wow.slash("/bbook")
    wow.execute(f"{MOD}.Window.win.db.size = {{ 940, 640 }}")
    load_probe(wow)
    wow.slash("/bprobe booklook small")
    wait(wow)
    out = f"{RESULTS}.booklookSmall"
    # the mock's screen is 1,920 x 1,080 units: scaled so it holds 768 of the window's units
    assert wow.eval(f"{out}.small.factor") == 1080 / 768
    assert wow.eval(f"{out}.room.height") == 768
    assert wow.eval(f"#{out}.runs") == 2
    assert [wow.eval(f"{out}.runs[{i}].asked") for i in (1, 2)] == [1100, 1365]
    # the wide one takes what the small screen has: 1,365 units less the probe's margin
    assert wow.eval(f"{out}.runs[2].width") == 1325
    assert wow.eval(f"{out}.runs[1].frame.height") == 688
    assert wow.eval(f"{out}.runs[1].head.height") == 50
    assert wow.eval(f"{out}.runs[1].chips[1].height") == 22
    assert wow.eval(f"{out}.runs[1].screenshot.ok") is True
    # the reader's own scale and size are back, and the plain record is untouched
    assert wow.eval(f"{MOD}.Window.win.frame:GetScale()") == wow.eval(f"{out}.small.scaleBefore")
    assert wow.eval(f"{MOD}.Window.win.frame:GetWidth()") == 940
    assert wow.eval(f"{RESULTS}.booklook") is None
    assert wow.errors == []


def test_the_tool_reports_the_small_record_beside_the_plain_one(wow: WowRuntime):
    boot(wow)
    wow.slash("/bbook")
    load_probe(wow)
    wow.slash("/bprobe booklook")
    wait(wow)
    wow.slash("/bprobe booklook small")
    wait(wow)
    lines, _ = book_look.report(wow.eval(f"{RESULTS}.booklook"))
    assert "the small screen" not in "\n".join(lines)
    lines, _ = book_look.report(wow.eval(f"{RESULTS}.booklookSmall"))
    text = "\n".join(lines)
    assert "the small screen: 768 units high" in text
    assert "width 1325 (asked 1365)" in text
    assert "ok  the head's height: spec 50, drawn 50" in text


def test_bookmodel_tries_every_way_and_takes_its_picture(wow: WowRuntime):
    boot(wow)
    load_probe(wow)
    before = wow.eval("Mock.screenshots")
    wow.slash("/bprobe bookmodel")
    wow.advance(3)
    out = f"{RESULTS}.bookmodel"
    keys = ("file", "fileFar", "scene", "item", "creature", "light", "fog", "grey")
    for key in keys:
        assert wow.eval(f"{out}.tests.{key}.created") is True, key
        if key != "scene":
            assert wow.eval(f"{out}.tests.{key}.set ~= nil") is True, key
    assert wow.eval(f"{out}.tests.file.arg") == 197466
    # the mock's frames make no actor: the miss is recorded, nothing raises
    assert wow.eval(f"{out}.tests.scene.actor.ok") is False
    assert wow.eval(f"{out}.tests.scene.camera.position ~= nil") is True
    assert wow.eval(f"{out}.tests.light.dark ~= nil") is True
    assert wow.eval(f"{out}.tests.fog.dark.far ~= nil") is True
    assert wow.eval(f"{out}.tests.grey.dark.set ~= nil") is True
    assert wow.eval(f"{out}.tests.creature.dark") is None
    assert wow.eval(f"{out}.screenshot.ok") is True
    assert wow.eval("Mock.screenshots") == before + 1
    # a second run uses the same frames
    wow.slash("/bprobe bookmodel")
    wow.advance(3)
    assert wow.eval("#BastiansProbeDisplay.models.cells") == len(keys)
    assert wow.errors == []


def test_bookreveal_draws_the_least_explored_zone_with_every_overlay(wow: WowRuntime):
    boot(wow)
    load_probe(wow)
    wow.execute(
        """
        for _, id in ipairs({ 1420, 1411, 1412 }) do
          Mock.maps[id] = { name = "Zone " .. id, mapType = 3, parent = 947 }
        end
        local seen = { textureWidth = 256, textureHeight = 256, offsetX = 10, offsetY = 20,
          fileDataIDs = { 4242 } }
        Mock.explored[1420] = { seen, seen }
        Mock.explored[1411] = { seen }
        """
    )
    wow.slash("/bprobe bookreveal")
    wow.advance(2)
    out = f"{RESULTS}.bookreveal"
    # Mulgore: nothing explored there, so the reveal is the whole difference
    assert wow.eval(f"{out}.map") == 1412
    assert wow.eval(f"{out}.zones[1420].exploredTiles") == 2
    assert wow.eval(f"{out}.explored.tiles") == 0
    assert wow.eval(f"{out}.revealed.tiles") == 18
    assert wow.eval(f"{out}.revealed.loaded") == 18
    assert wow.eval(f"#{out}.revealed.missing") == 0
    assert wow.eval(f"{out}.layer.width") == 1002
    assert wow.eval(f"{out}.screenshot.ok") is True
    # a zone by its id
    wow.slash("/bprobe bookreveal 1420")
    wow.advance(2)
    assert wow.eval(f"{out}.map") == 1420
    assert wow.eval(f"{out}.explored.tiles") == 2
    assert wow.eval(f"{out}.revealed.tiles") == 22
    assert wow.errors == []


def test_the_probe_takes_cores_snapshot_after_every_login(wow: WowRuntime):
    boot(wow)
    wow.execute("BastiansProbeDB = { sequences = { ['w2-1'] = { at = 'before' } } }")
    load_probe(wow)
    wow.login()
    wow.advance(29)
    assert wow.eval(f"{RESULTS}.perf") is None
    wow.advance(2)
    assert wow.eval(f"#{RESULTS}.perf") == 1
    snap = f"{RESULTS}.perf[1]"
    assert wow.eval(f"{snap}.note") == "30 s after login"
    assert wow.eval(f"{snap}.coreKB ~= nil") is True
    assert wow.eval(f"{snap}.addons") >= 3
    # Core keeps the same snapshot for tools/perf_report.py, marked as the probe's
    saved = "BastiansCoreDB.global.perf"
    assert wow.eval(f"{saved}[#{saved}].by") == "probe"
    assert wow.eval(f"{saved}[#{saved}].note") == "30 s after login"
    # the sequence has run before: it does not run again
    wait(wow, 20)
    assert wow.eval(f"{RESULTS}.bookmodel") is None
    assert wow.errors == []


def test_the_one_looks_probes_run_once_by_themselves(wow: WowRuntime):
    boot(wow)
    wow.slash("/bbook")
    wow.execute(f"{MOD}.Window.win.db.size = {{ 940, 640 }}")
    wow.execute(
        """
        for _, id in ipairs({ 1420, 1411, 1412 }) do
          Mock.maps[id] = { name = "Zone " .. id, mapType = 3, parent = 947 }
        end
        """
    )
    load_probe(wow)
    wow.set_combat(True)
    wow.login()
    wow.advance(31)
    # in a fight nothing opens
    assert wow.eval(f"{RESULTS}.bookmodel") is None
    wow.set_combat(False)
    wow.fire("PLAYER_REGEN_ENABLED")
    wait(wow, 30)
    assert wow.eval(f"{RESULTS}.bookmodel.screenshot.ok") is True
    assert wow.eval(f"{RESULTS}.bookreveal.screenshot.ok") is True
    assert wow.eval(f"#{RESULTS}.booklook.runs") == 3
    assert wow.eval(f"#{RESULTS}.booklookSmall.runs") == 2
    assert wow.eval("BastiansProbeDB.sequences['w2-1'].at ~= nil") is True
    assert wow.eval("BastiansProbeDisplay:IsShown()") is False
    assert wow.eval(f"{MOD}.Window.win.frame:GetWidth()") == 940
    # the next login takes the snapshot only
    wow.execute(f"{RESULTS}.bookmodel = nil")
    wow.login()
    wait(wow, 60)
    assert wow.eval(f"{RESULTS}.bookmodel") is None
    assert wow.eval(f"#{RESULTS}.perf") == 2
    assert wow.errors == []
