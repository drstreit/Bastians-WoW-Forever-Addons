"""Deferred registrations (Init.lua, core-contracts "Generated files"): a generated file may run
before Core or before its consumer exists, as the Forever beta client did on 20.10.2026 with
remembered load-on-demand addons; its queued call is delivered once the target function is there."""

from pathlib import Path

from harness import WowRuntime

ROOT = Path(__file__).resolve().parents[3]
WORLD = ROOT / "tests" / "fixtures" / "addons" / "Bastians_Data_World" / "Generated" / "World.lua"
TILES = ROOT / "tests" / "fixtures" / "mapart" / "MinimapTiles.lua"


def test_a_pack_file_that_runs_before_core_is_registered_when_data_loads(wow: WowRuntime):
    assert wow.eval("Bastians") is None
    wow.execute(WORLD.read_text(encoding="utf-8"))  # the client ran the pack before Core
    assert wow.eval("#Bastians.deferred") == 1 and wow.eval("Bastians.Data") is None
    wow.start("Bastians_Core", "Bastians_Data")
    assert wow.eval("Bastians.Data.packs.world ~= nil") is True
    assert wow.eval("#Bastians.deferred") == 0
    assert wow.eval("Bastians.API_VERSION") == 1  # Init.lua kept the table the pack created
    assert wow.errors == []


def test_map_art_before_the_map_and_the_tile_table_before_both(wow: WowRuntime):
    text = TILES.read_text(encoding="utf-8").replace(
        'client = "forever"', f'client = "{wow.client}"'
    )
    wow.execute(text)
    wow.load_addon("Bastians_Map_Art")  # the client loaded it before Bastians_Map
    assert wow.eval("Bastians.Map.artLoaded") == "Bastians_Map_Art"
    wow.start("Bastians_Core", "Bastians_Data", "Bastians_Map")
    assert wow.eval("Bastians.Map.artLoaded") == "Bastians_Map_Art"
    assert wow.eval("Bastians:GetModule('Map').Tiles.Count(0)") == 6
    assert wow.eval("#Bastians.deferred") == 0
    assert wow.errors == []


def test_deliver_keeps_entries_without_a_target_and_ignores_junk(core: WowRuntime):
    core.execute(
        "Bastians.deferred[#Bastians.deferred + 1] = { 'Nope.Register', 1 }; "
        "Bastians.deferred[#Bastians.deferred + 1] = 'junk'; "
        "Bastians.Probe = { Hit = function(a, b) _G.hit = { a, b } end }; "
        "Bastians.deferred[#Bastians.deferred + 1] = { 'Probe.Hit', 'x', 2 }"
    )
    assert core.eval("Bastians.Deliver()") == 1
    assert list(core.eval("hit").values()) == ["x", 2]
    assert (
        core.eval("#Bastians.deferred") == 1
        and core.eval("Bastians.deferred[1][1]") == "Nope.Register"
    )
    assert core.eval("Bastians.Deliver()") == 0
    # a runtime LoadAddOn delivers what the loaded addon queued
    core.execute("Bastians.Nope = { Register = function(v) _G.nope = v end }")
    assert core.eval("Bastians.Compat.LoadAddOn('Bastians_Data')") == "loaded"
    assert core.eval("nope") == 1 and core.eval("#Bastians.deferred") == 0
