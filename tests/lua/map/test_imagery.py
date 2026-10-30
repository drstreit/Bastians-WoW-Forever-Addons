"""Imagery stage 1 (B8.2): zone art tiles placed in world coordinates, only for zones in view, pooled
and capped; zone borders and names from the configured level on, level range on hover."""

from harness import WowRuntime

CORE, DATA, MAP = "Bastians_Core", "Bastians_Data", "Bastians_Map"
MOD = "Bastians:GetModule('Map')"
MAP_ = f"{MOD}.Map"
IMG = "Bastians:GetModule('Map').Imagery"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, MAP)))
    wow.run_frames(5)
    wow.slash("/bmap")
    wow.execute(f"{MAP_}.clip:SetSize(600, 400); {MAP_}.ViewChanged()")
    return wow


def shown_textures(wow: WowRuntime) -> list:
    return [t for t in wow.eval(f"{IMG}.pool").values() if t.IsShown(t)]


def test_zones_of_the_continent_with_their_world_rectangles_and_tiles(wow: WowRuntime):
    boot(wow)
    zones = list(wow.eval(f"{IMG}.Zones(0)").values())
    assert [(z.map, z.depth, z.name) for z in zones] == [
        (1415, 0, "Eastern Kingdoms"),
        (1429, 1, "Elwynn Forest"),
        (1453, 1, "Stormwind City"),
    ]
    elwynn = zones[1]
    assert (elwynn.x1, elwynn.y1, elwynn.x2, elwynn.y2) == (-200, -200, 200, 200)
    tiles = list(elwynn.tiles.values())
    assert len(tiles) == 3  # the mock lists three textures for a 4 x 3 grid
    assert (tiles[0].file, tiles[0].fx1, tiles[0].fy1, round(tiles[0].fx2, 4)) == (
        1001,
        0,
        0,
        0.2555,
    )
    assert (tiles[0].tcRight, tiles[0].tcBottom) == (1, 1)
    assert round(tiles[2].fx2, 4) == 0.7665  # three full tiles of 256 over 1002 px
    assert wow.eval(f"#{IMG}.Zones(1)") == 0  # no Kalimdor maps in the mock


def test_render_places_tiles_in_world_coordinates_and_pools_them(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 3)")  # the centre of Elwynn at 4 yards per pixel
    stats = wow.eval(f"{IMG}.stats")
    assert (stats.zones, stats.textures) == (3, 9)  # continent, Elwynn and Stormwind art in view
    shown = shown_textures(wow)
    assert len(shown) == 9
    files = sorted(t.GetTexture(t) for t in shown)
    assert files == [1001, 1001, 1001, 1002, 1002, 1002, 1003, 1003, 1003]
    # Elwynn's first tile covers map fractions 0..0.2555 x 0..0.3832 of a 400 yard square: north-west
    first = next(t for t in shown if t.GetTexture(t) == 1001 and 20 < t.width < 30)
    assert (
        round(first.width, 1) == 25.5 and round(first.height, 1) == 38.3
    )  # 0.2555 * 400 yd * 0.25 px
    point = first.GetPoint(first)
    assert (point[0], point[3], point[4]) == ("TOPLEFT", 250, -150)  # Elwynn's north-west corner
    # the continent art (2,000 yards) is five times as large and starts above the view
    big = next(t for t in shown if t.GetTexture(t) == 1001 and t.width > 100)
    assert round(big.width, 1) == 127.7 and big.GetPoint(big)[4] == 50
    assert first.GetTexCoord(first) == (0, 1, 0, 1)
    # a second render reuses the pool
    wow.execute(f"{MAP_}.Pan(5, 5)")
    assert wow.eval(f"{IMG}.stats.pool") == 9 and len(shown_textures(wow)) == 9
    # far away: nothing in view, every texture hidden, the pool stays
    wow.execute(f"{MAP_}.Fly(0, 50000, 50000, 3)")
    assert len(shown_textures(wow)) == 0 and wow.eval(f"{IMG}.stats.pool") == 9
    assert wow.errors == []


def test_texture_cap_is_respected(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{IMG}.MAX_TEXTURES = 4")
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 3)")
    assert len(shown_textures(wow)) == 4 and wow.eval(f"{IMG}.stats.textures") == 4


def test_imagery_draws_no_zone_rectangles_and_no_names(wow: WowRuntime):
    """the zone names doubled over map.zones, and "the border around the
    tile structure is back ... remove them": Imagery draws the art only."""
    boot(wow)
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 2)")
    assert wow.eval(f"{IMG}.labelPool") is None and wow.eval(f"{IMG}.linePool") is None
    assert wow.eval(f"{IMG}.stats.zones") > 0
    assert wow.errors == []


def test_imagery_without_data_uses_the_client_names_and_no_level_range(wow: WowRuntime):
    boot(wow, CORE, MAP)
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 2)")
    zones = list(wow.eval(f"{IMG}.Zones(0)").values())
    assert [z.name for z in zones] == ["Eastern Kingdoms", "Elwynn Forest", "Stormwind City"]
    assert wow.eval(f"{IMG}.stats.textures") == 9
    assert wow.errors == []


def test_retail_numbers_its_continent_maps_differently(wow: WowRuntime):
    """(R28.4): the Blizzard style drew nothing, /bmap stats said "maps 0".
    Retail has no uiMap 1415: its Eastern Kingdoms is 13 (probe P3, 12.1.5.70575). The continent
    map comes from the client: the known id when it exists, else the continent map above the
    transform table's maps."""
    wow.start(CORE, DATA, MAP)
    wow.execute(
        """Mock.maps[13] = Mock.maps[1415]; Mock.maps[1415] = nil
        for _, m in pairs(Mock.maps) do if m.parent == 1415 then m.parent = 13 end end"""
    )
    wow.run_frames(5)
    assert wow.eval("Bastians.Coords.ContinentMap(0)") == 13
    wow.slash("/bmap")
    wow.execute(
        f"{MAP_}.SetStyle('blizzard'); {MAP_}.clip:SetSize(600, 400); {MAP_}.Fly(0, 0, 0, 0)"
    )
    zones = list(wow.eval(f"{IMG}.Zones(0)").values())
    assert [(z.map, z.depth) for z in zones] == [(13, 0), (1429, 1), (1453, 1)]
    assert shown_textures(wow)  # the continent's painting, zoomed out
    assert wow.eval("Bastians.Coords.ContinentMap(1)") is None  # no Kalimdor maps in the mock
    # an id neither client is known for: the continent map above the transform table's maps
    wow.execute(
        """Mock.maps[5000] = Mock.maps[13]; Mock.maps[13] = nil
        for _, m in pairs(Mock.maps) do if m.parent == 13 then m.parent = 5000 end end
        Bastians.Coords.SetTransforms({ [1429] = { 0, 200, 0, -400, 200, -400, 0 } })"""
    )
    assert wow.eval("Bastians.Coords.ContinentMap(0)") == 5000
    assert wow.errors == []


def test_caves_dungeons_and_orphan_maps_get_no_art_and_no_border(wow: WowRuntime):
    """retail lists Fargodeep Mine (a cave, type 5) and others under
    Elwynn; their paintings lay over the zone and their rectangles cluttered the continent."""
    wow.start(CORE, DATA, MAP)
    wow.execute(
        """Mock.maps[38] = { name = "Fargodeep Mine", mapType = 5, parent = 1429,
             c00 = { 0, 50, 50 }, c11 = { 0, -50, -50 } }"""
    )
    wow.run_frames(5)
    wow.slash("/bmap")
    wow.execute(f"{MAP_}.clip:SetSize(600, 400); {MAP_}.Fly(0, 0, 0, 3)")
    zones = {z.map: z for z in wow.eval(f"{IMG}.Zones(0)").values()}
    assert zones[38].mapType == 5 and wow.eval(f"{IMG}.IsZone({IMG}.Zones(0)[4])") is False
    # the continent, Elwynn and Stormwind, three tiles each in the mock; the mine none
    assert wow.eval(f"{IMG}.stats.textures") == 9
    assert wow.errors == []


def test_the_explored_areas_are_cut_as_blizzard_cuts_them(wow: WowRuntime):
    """Core's cut of Blizzard's explored areas (the Browser's zone cards use it): 256 px tiles, the
    last row and column from the smallest power-of-two file; mouse-over areas left out."""
    boot(wow)
    tiles = list(
        wow.eval(
            """Bastians.Coords.OverlayTiles({
              { textureWidth = 300, textureHeight = 200, offsetX = 10, offsetY = 20,
                 fileDataIDs = { 501, 502 }, isDrawOnTopLayer = false },
              { textureWidth = 64, textureHeight = 64, offsetX = 0, offsetY = 0,
                 fileDataIDs = { 600 }, isShownByMouseOver = true },
            })"""
        ).values()
    )
    assert [(t.file, t.px1, t.py1, t.px2, t.py2) for t in tiles] == [
        (501, 10, 20, 266, 220),
        (502, 266, 20, 310, 220),
    ]
    assert (tiles[0].tcRight, tiles[0].tcBottom) == (1, 200 / 256)
    assert (tiles[1].tcRight, tiles[1].tcBottom) == (44 / 64, 200 / 256)  # 44 px in a 64 px file
    assert wow.errors == []
