"""Imagery stage 3 (B8.5): the overview cells of Bastians_Map_Art, their registration per client, the
cell math, the renderer (whole continent at level 0, beneath the native tiles at close zoom, keyed
and reused), the load-on-demand of Map_Art when the map opens, and the setting."""

from pathlib import Path

from harness import WowRuntime

CORE, DATA, MAP = "Bastians_Core", "Bastians_Data", "Bastians_Map"
MOD = "Bastians:GetModule('Map')"
MAP_ = f"{MOD}.Map"
OV = f"{MOD}.Overview"
TILES = f"{MOD}.Tiles"
FIXTURES = Path(__file__).resolve().parents[2] / "fixtures" / "mapart"
GOLDEN = FIXTURES / "overview" / "Overview.lua"
TILE_GOLDEN = FIXTURES / "MinimapTiles.lua"
PATH = "Interface\\AddOns\\Bastians_Map_Art\\Generated\\Tiles\\"


def boot(wow: WowRuntime, table: bool = True, tiles: bool = False) -> WowRuntime:
    wow.start(CORE, DATA, MAP)
    wow.run_frames(5)
    wow.slash("/bmap")  # builds the window: the Map asks for Map_Art here
    wow.run_frames(2)
    if table:
        text = GOLDEN.read_text(encoding="utf-8").replace(
            'client = "forever"', f'client = "{wow.client}"'
        )
        wow.execute(text)  # what Bastians_Map_Art/Generated/Overview.lua would run
        wow.execute("Bastians.Deliver()")
    if tiles:
        text = TILE_GOLDEN.read_text(encoding="utf-8").replace(
            'client = "forever"', f'client = "{wow.client}"'
        )
        wow.execute(text)
        wow.execute("Bastians.Deliver()")
    wow.execute(f"{MAP_}.clip:SetSize(600, 400); {MAP_}.ViewChanged()")
    return wow


def live(wow: WowRuntime) -> dict:
    return {int(k): t for k, t in wow.eval(f"{OV}.live").items()}


def test_map_art_is_loaded_on_demand_when_the_map_opens(wow: WowRuntime):
    wow.start(CORE, DATA, MAP)
    wow.run_frames(5)
    assert not wow.eval("(C_AddOns.IsAddOnLoaded('Bastians_Map_Art'))")
    assert "loads when the map opens" in wow.eval(f"{OV}.Note()")
    wow.slash("/bmap")
    wow.run_frames(2)
    assert wow.eval("(C_AddOns.IsAddOnLoaded('Bastians_Map_Art'))")
    assert wow.eval("Bastians.Map.artLoaded") == "Bastians_Map_Art"
    # the art addon is there but a fresh checkout has no generated textures
    assert "no overview textures" in wow.eval(f"{OV}.Note()")
    assert wow.eval(f"{OV}.Enabled()") is False and wow.eval(f"{OV}.Count(0)") == 0
    assert wow.errors == []


def test_the_generated_table_registers_per_client(wow: WowRuntime):
    boot(wow)
    assert (wow.eval(f"{OV}.Count(0)"), wow.eval(f"{OV}.Count(1)")) == (3, 1)
    assert wow.eval(f"{OV}.Key(3, 6)") == 30
    assert wow.eval(f"{OV}.File(0, 3, 6)") == PATH + "0_3_6"
    assert wow.eval(f"{OV}.File(0, 7, 7)") is None and wow.eval(f"{OV}.File(5, 3, 6)") is None
    assert wow.eval(f"{OV}.Note()") == "Overview cells: Eastern Kingdoms 3, Kalimdor 1"
    # a table for the other client is kept out and the note says so
    other = "retail" if wow.client == "forever" else "forever"
    wow.execute(
        f'Bastians.Map.RegisterOverview({{ client = "{other}", span = 8, grid = 8, path = "x", continents = {{ [0] = {{ 1 }} }} }})'
    )
    assert wow.eval(f"{OV}.Count(0)") == 0 and wow.eval(f"{OV}.Enabled()") is False
    assert f"built for {other}" in wow.eval(f"{OV}.Note()")
    assert wow.errors == []


def test_cell_math_covers_eight_by_eight_tiles(wow: WowRuntime):
    boot(wow, table=False)
    assert wow.eval(f"{OV}.CellAt(0, 0)") == (4, 4)  # tile (32, 32) lies in cell (4, 4)
    assert wow.eval(f"{OV}.CellAt(-8832.77, 478.62)") == (3, 6)  # Stormwind: tile (31, 48)
    wx1, wy1, wx2, wy2 = wow.eval(f"{OV}.WorldRect(4, 4)")
    assert (round(wx1, 2), round(wy1, 2), wx2, wy2) == (-4266.67, -4266.67, 0, 0)
    wx1, wy1, wx2, wy2 = wow.eval(f"{OV}.WorldRect(3, 6)")  # tiles 24..31 x 48..55
    assert (round(wx1, 2), round(wx2, 2), round(wy1, 2), round(wy2, 2)) == (
        -12800.0,
        -8533.33,
        0,
        4266.67,
    )


def test_the_whole_continent_shows_at_level_zero_and_cells_are_reused(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{MAP_}.Fly(0, -9000, 1000, 0)")  # 1/32 px per yard: the view spans the continent
    stats = wow.eval(f"{OV}.stats")
    assert (stats.shown, stats.wanted, stats.skipped) == (3, 3, 0)
    textures = live(wow)
    assert sorted(textures) == [29, 30, 38]
    stormwind = textures[30]
    assert stormwind.GetTexture(stormwind) == PATH + "0_3_6"
    # one UI unit of overlap with the neighbours: no seam between cells
    assert round(stormwind.width, 2) == 134.33 and round(stormwind.height, 2) == 134.33
    # cell (3, 6) starts 4266.67 yards west and 12800 south of the origin: on the screen that is left
    # and below the origin, which sits at (-9000 + 300*32, 1000 + 300*32) relative to the view
    point = stormwind.GetPoint(stormwind)
    assert point[0] == "TOPLEFT"
    assert (round(point[3], 2), round(point[4], 2)) == (
        round(300 - (4266.67 - 1000) / 32, 2),
        -round(200 - (-8533.33 + 9000) / 32, 2),
    )
    wow.execute(f"{OV}.live[30].mark = 'first'")
    wow.execute(f"{MAP_}.Pan(40, 20)")
    assert live(wow)[30].mark == "first"
    assert wow.eval(f"#{OV}.free") == 0
    # at close zoom the cell under the view stays, plus the margin's neighbours (prefetched)
    wow.execute(f"{MAP_}.Fly(0, -8832.77, 478.62, 6)")
    assert sorted(live(wow)) == [29, 30, 38]
    wow.execute(f"{OV}.MARGIN = 0")
    wow.execute(f"{MAP_}.Pan(1, 0)")
    assert sorted(live(wow)) == [30] and wow.eval(f"#{OV}.free") == 2
    wow.execute(f"{MAP_}.Fly(1, 500, 500, 0)")
    assert sorted(live(wow)) == [27]
    wow.execute(f"{MAP_}.Fly(0, 20000, 20000, 6)")
    assert wow.eval(f"{OV}.stats.shown") == 0
    assert wow.errors == []


def test_overview_sits_between_zone_art_and_native_tiles(wow: WowRuntime):
    boot(wow, tiles=True)
    wow.execute(f"{OV}.MARGIN = 0")
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 6)")
    native = wow.eval(f"{TILES}.stats.shown")
    assert (
        native == 5 and wow.eval(f"{OV}.stats.shown") == 0
    )  # no cell at the origin in the fixture
    wow.execute(f"{MAP_}.Fly(0, -8832.77, 478.62, 6)")
    assert wow.eval(f"{OV}.stats.shown") == 1 and wow.eval(f"{TILES}.stats.shown") == 1
    assert wow.eval(f"{OV}.sublevel") == 1 and wow.eval(f"{TILES}.sublevel") == 2
    assert wow.eval(f"{MOD}.Imagery.stats.textures") >= 0  # the zone art fallback is still rendered
    assert wow.errors == []


def test_the_setting_turns_the_overview_off_and_on(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{MAP_}.Fly(0, -9000, 1000, 0)")
    assert wow.eval(f"{OV}.stats.shown") == 3
    wow.execute(f"{MOD}.db.profile.overviewArt = false")
    wow.execute("Bastians:Fire('BASTIANS_SETTING_CHANGED', 'Map', 'overviewArt', false)")
    assert wow.eval(f"{OV}.stats.shown") == 0 and wow.eval(f"{OV}.Enabled()") is False
    assert wow.eval(f"#{OV}.free") == 3
    wow.execute(f"{MOD}.db.profile.overviewArt = true")
    wow.execute("Bastians:Fire('BASTIANS_SETTING_CHANGED', 'Map', 'overviewArt', true)")
    assert wow.eval(f"{OV}.stats.shown") == 3 and wow.eval(f"#{OV}.free") == 0
    assert wow.errors == []


def test_the_map_does_not_load_art_when_the_setting_is_off(wow: WowRuntime):
    wow.start(CORE, DATA, MAP)
    wow.run_frames(5)
    wow.execute(f"{MOD}.db.profile.overviewArt = false")
    wow.slash("/bmap")
    wow.run_frames(2)
    assert not wow.eval("(C_AddOns.IsAddOnLoaded('Bastians_Map_Art'))")
    wow.execute(f"{MOD}.db.profile.overviewArt = true")
    wow.execute("Bastians:Fire('BASTIANS_SETTING_CHANGED', 'Map', 'overviewArt', true)")
    assert wow.eval("(C_AddOns.IsAddOnLoaded('Bastians_Map_Art'))")
    assert wow.errors == []


def test_coast_tiles_get_their_sea_mask_while_the_cells_are_drawn(wow: WowRuntime):
    """at close zoom the native tiles' black sea covered the parchment.
    Map_Art registers a sea mask per coast tile; the native layer masks those tiles (Compat.AddMask)."""
    boot(wow, tiles=True)
    wow.execute(
        "Bastians.Map.RegisterOverview({ client = Bastians.Client, span = 8, grid = 8, path = 'P/', "
        "maskPath = 'M/', "
        "continents = { [0] = { 36 } }, masks = { [0] = { 32 * 64 + 32 } } })"
    )
    assert wow.eval(f"{OV}.MaskCount(0)") == 1
    assert wow.eval(f"{OV}.Mask(0, 32, 32)") == ("M/0_32_32")
    assert wow.eval(f"{OV}.Mask(0, 31, 31)") is None
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 6)")  # four native tiles meet at the centre
    tiles = {int(k): t for k, t in wow.eval(f"{TILES}.live").items()}
    coast, land = tiles[32 * 64 + 32], tiles[31 * 64 + 31]
    assert coast.maskPath.endswith("0_32_32") and coast.GetNumMaskTextures(coast) == 1
    mask = coast.bastiansMask
    assert mask.GetTexture(mask).endswith("0_32_32") and mask.IsShown(mask)
    assert land.maskPath is None and land.GetNumMaskTextures(land) == 0
    assert "masked" in "\n".join(wow.eval(f"{TILES}.Describe({TILES}, 9)").values())
    # the cells switched off: the masks go with them (Blizzard's water again)
    wow.execute(f"{MOD}.db.profile.overviewArt = false")
    wow.execute("Bastians:Fire('BASTIANS_SETTING_CHANGED', 'Map', 'overviewArt', false)")
    tiles = {int(k): t for k, t in wow.eval(f"{TILES}.live").items()}
    coast = tiles[32 * 64 + 32]
    assert coast.maskPath is None and coast.GetNumMaskTextures(coast) == 0
    assert wow.errors == []
