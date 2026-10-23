"""Imagery stage 2 (B8.4): the native minimap tile table, the tile math, and the tile manager
(visible set with a margin, textures keyed by tile and reused across pans, cap, level gate, setting)."""

from pathlib import Path

from harness import WowRuntime

CORE, DATA, MAP = "Bastians_Core", "Bastians_Data", "Bastians_Map"
MOD = "Bastians:GetModule('Map')"
MAP_ = f"{MOD}.Map"
TILES = f"{MOD}.Tiles"
GOLDEN = Path(__file__).resolve().parents[2] / "fixtures" / "mapart" / "MinimapTiles.lua"


def boot(wow: WowRuntime, table: bool = True) -> WowRuntime:
    wow.start(CORE, DATA, MAP)
    wow.run_frames(5)
    if table:
        # what the pipeline generates (golden), built for the client under test
        text = GOLDEN.read_text(encoding="utf-8").replace(
            'client = "forever"', f'client = "{wow.client}"'
        )
        wow.execute(text)
        wow.execute("Bastians.Deliver()")
    else:
        wow.execute("Bastians.Map.RegisterTiles(nil)")  # as a checkout without a generated table
    wow.slash("/bmap")
    wow.execute(f"{MAP_}.clip:SetSize(600, 400); {MAP_}.ViewChanged()")
    return wow


def live(wow: WowRuntime) -> dict:
    return {int(k): t for k, t in wow.eval(f"{TILES}.live").items()}


def test_tile_math_matches_the_adt_grid(wow: WowRuntime):
    boot(wow, table=False)
    assert wow.eval(f"{TILES}.TileAt(0, 0)") == (32, 32)
    assert wow.eval(f"{TILES}.TileAt(-8832.77, 478.62)") == (
        31,
        48,
    )  # Stormwind (client-extraction.md)
    wx1, wy1, wx2, wy2 = wow.eval(f"{TILES}.WorldRect(32, 32)")
    assert (round(wx1, 2), round(wy1, 2), wx2, wy2) == (-533.33, -533.33, 0, 0)
    wx1, wy1, wx2, wy2 = wow.eval(f"{TILES}.WorldRect(31, 48)")
    assert (round(wx1, 2), round(wx2, 2), round(wy1, 2), round(wy2, 2)) == (
        -9066.67,
        -8533.33,
        0,
        533.33,
    )
    assert wow.eval(f"{TILES}.Key(31, 48)") == 31 * 64 + 48
    assert wow.eval(f"{TILES}.Count(0)") == 0 and wow.eval(f"{TILES}.Enabled()") is False
    assert "No minimap tile table" in wow.eval(f"{TILES}.Note()")


def test_the_generated_table_registers_per_client(wow: WowRuntime):
    boot(wow)
    assert (wow.eval(f"{TILES}.Count(0)"), wow.eval(f"{TILES}.Count(1)")) == (6, 1)
    assert wow.eval(f"{TILES}.File(0, 31, 48)") == 204453
    assert wow.eval(f"{TILES}.Directory(0)") == "Azeroth"
    assert wow.eval(f"{TILES}.Path(0, 31, 48)") == "World\\Minimaps\\Azeroth\\map31_48"
    assert wow.eval(f"{TILES}.Path(5, 31, 48)") is None
    assert wow.eval(f"{TILES}.Note()") == "Minimap tiles: Eastern Kingdoms 6, Kalimdor 1"
    visible = list(wow.eval(f"{TILES}.Visible(0, -100, -150, 100, 150, 0)").values())
    assert sorted((v.x, v.y) for v in visible) == [(31, 31), (31, 32), (32, 31), (32, 32)]
    assert {v.path for v in visible} == {
        f"World\\Minimaps\\Azeroth\\map{v.x}_{v.y}" for v in visible
    }
    with_margin = wow.eval(f"#{TILES}.Visible(0, -100, -150, 100, 150, 1)")
    assert with_margin == 5  # plus (33, 32); (31, 48) is far away
    # a table for the other client is kept out and the note says so
    other = "retail" if wow.client == "forever" else "forever"
    wow.execute(
        f'Bastians.Map.RegisterTiles({{ client = "{other}", continents = {{ [0] = {{ [2015] = 1 }} }} }})'
    )
    assert wow.eval(f"{TILES}.Count(0)") == 0
    assert f"built for {other}" in wow.eval(f"{TILES}.Note()")
    assert wow.errors == []


def test_tiles_are_drawn_from_min_level_keyed_and_reused(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 6)")  # 2 px per yard: four tiles meet at the view's centre
    stats = wow.eval(f"{TILES}.stats")
    assert (stats.shown, stats.wanted, stats.skipped) == (5, 5, 0)
    textures = live(wow)
    south_east = textures[32 * 64 + 32]
    # the id first (it drew every tile on Forever 20.10.2026), the path only when the id leaves the
    # texture empty (22.10.2026: the path form left every tile blank in game)
    assert south_east.GetTexture(south_east) == 500004
    assert south_east.source == "id"
    point = south_east.GetPoint(south_east)
    assert (point[0], point[3], point[4]) == ("TOPLEFT", 300, -200)  # the origin is the view centre
    # one UI unit past the east and south edges: neighbours overlap, no rounding gap (23.10.2026)
    assert round(south_east.width, 2) == 1067.67 and round(south_east.height, 2) == 1067.67
    north_west = textures[31 * 64 + 31]
    assert (
        round(north_west.GetPoint(north_west)[3], 2),
        round(north_west.GetPoint(north_west)[4], 2),
    ) == (
        -766.67,
        866.67,
    )  # the north-west tile starts above and left of the view: y offsets point up
    # a pan keeps the same texture object for the same tile: no reload
    wow.execute(f"{TILES}.live[{32 * 64 + 32}].mark = 'first'")
    wow.execute(f"{MAP_}.Pan(40, 20)")
    again = live(wow)[32 * 64 + 32]
    assert again.mark == "first" and again.GetPoint(again)[3] == 340
    assert wow.eval(f"#{TILES}.free") == 0
    # below the minimum level nothing is drawn and the textures go back to the pool
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 2)")
    assert wow.eval(f"{TILES}.stats.shown") == 0 and wow.eval(f"#{TILES}.free") == 5
    assert not [t for t in wow.eval(f"{TILES}.free").values() if t.IsShown(t)]
    # the pool is reused when the view comes back
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 6)")
    assert wow.eval(f"#{TILES}.free") == 0 and wow.eval(f"{TILES}.stats.shown") == 5
    # another continent and a far-away spot
    wow.execute(f"{MAP_}.Fly(1, 500, 500, 6)")
    assert set(live(wow)) == {30 * 64 + 30}
    wow.execute(f"{MAP_}.Fly(0, 20000, 20000, 6)")
    assert wow.eval(f"{TILES}.stats.shown") == 0
    assert wow.errors == []


def test_a_view_that_needs_more_tiles_than_the_cap_shows_none(wow: WowRuntime):
    """Either every tile of the view or the overview underneath, never a sharp block in a blurry
    view (seen on a 2137 px window at level 3.5, Forever 20.10.2026)."""
    boot(wow)
    wow.execute(f"{MAP_}.Fly(0, -100, -100, 6)")  # 600x400 px at 2 px per yard: 2x2 tiles + margin
    assert wow.eval(f"{TILES}.Needed({MAP_}.Camera())") == 16
    assert wow.eval(f"{TILES}.stats.shown") == 5
    wow.execute(f"{TILES}.MAX_TEXTURES = 15")
    wow.execute(f"{MAP_}.Pan(1, 0)")
    assert wow.eval(f"{TILES}.stats.shown") == 0 and wow.eval(f"#{TILES}.free") == 5
    wow.execute(f"{TILES}.MAX_TEXTURES = 16")
    wow.execute(f"{MAP_}.Pan(-1, 0)")
    assert wow.eval(f"{TILES}.stats.shown") == 5
    # the draw cap itself still keeps the tiles nearest the centre when a caller passes a smaller one
    wow.execute(
        f"local x1, y1, x2, y2 = {MAP_}.Camera():Bounds(); "
        f"{TILES}.Draw({TILES}, {MAP_}.Camera(), {TILES}.Visible(0, x1, y1, x2, y2, 1), 2)"
    )
    assert sorted(live(wow)) == [31 * 64 + 32, 32 * 64 + 32]
    stats = wow.eval(f"{TILES}.stats")
    assert (stats.shown, stats.skipped) == (2, 3)


def test_the_setting_turns_native_tiles_off_and_on(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 6)")
    assert wow.eval(f"{TILES}.stats.shown") == 5
    wow.execute(f"{MOD}.db.profile.nativeTiles = false")
    wow.execute("Bastians:Fire('BASTIANS_SETTING_CHANGED', 'Map', 'nativeTiles', false)")
    assert wow.eval(f"{TILES}.stats.shown") == 0 and wow.eval(f"{TILES}.Enabled()") is False
    wow.execute(f"{MOD}.db.profile.nativeTiles = true")
    wow.execute("Bastians:Fire('BASTIANS_SETTING_CHANGED', 'Map', 'nativeTiles', true)")
    assert wow.eval(f"{TILES}.stats.shown") == 5
    # the zone art underneath is still drawn: the fallback never goes away
    assert wow.eval(f"{MOD}.Imagery.stats.textures") > 0
    assert wow.errors == []


def test_the_path_is_the_second_attempt_and_the_old_table_form_still_registers(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 6)")
    # a client that leaves the texture empty for the id (GetTexture answers nil) gets the path
    wow.execute(
        f"local t = {TILES}.live[{32 * 64 + 32}]; t.GetTexture = function(self) "
        "if type(self.texture) == 'number' then return nil end return self.texture end; "
        f"{TILES}.SetFile(t, {{ path = 'World\\\\Minimaps\\\\Azeroth\\\\map32_32', file = 500004 }})"
    )
    t = live(wow)[32 * 64 + 32]
    assert t.GetTexture(t) == "World\\Minimaps\\Azeroth\\map32_32" and t.source == "path"
    lines = list(wow.eval(f"{TILES}.Describe({TILES}, 2)").values())
    assert len(lines) == 2 and lines[0].startswith("2015 (31/31): id 500001 shown=true")
    assert "2080 (32/32): path World\\Minimaps\\Azeroth\\map32_32 shown=true" in "\n".join(
        list(wow.eval(f"{TILES}.Describe({TILES}, 9)").values())
    )
    # the table form before 22.10.2026 (ids only, no directory) still registers; no path then
    wow.execute(
        f'Bastians.Map.RegisterTiles({{ client = "{wow.client}", '
        "continents = { [0] = { [2080] = 777 } } })"
    )
    assert (
        wow.eval(f"{TILES}.File(0, 32, 32)") == 777 and wow.eval(f"{TILES}.Path(0, 32, 32)") is None
    )
    kept = live(wow)[32 * 64 + 32]
    assert (
        kept.GetTexture(kept) == "World\\Minimaps\\Azeroth\\map32_32"
    )  # a live tile keeps its texture
    wow.execute(f"{TILES}.live[{32 * 64 + 32}].GetTexture = nil")  # the mock's own answer again
    wow.execute(f"{TILES}.Clear({TILES}); {MAP_}.ViewChanged()")
    t = live(wow)[32 * 64 + 32]
    assert t.GetTexture(t) == 777 and t.source == "file"
    # a resize only moves the live textures: the same objects, new places, nothing loaded
    wow.execute(f"{TILES}.live[{32 * 64 + 32}].mark = 'kept'")
    wow.execute(f"{MAP_}.Camera():SetView(800, 400); {TILES}.Reposition({TILES}, {MAP_}.Camera())")
    t = live(wow)[32 * 64 + 32]
    assert t.mark == "kept" and t.GetPoint(t)[3] == 400
    assert wow.errors == []
