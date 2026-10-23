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


def test_borders_and_names_follow_the_zoom_level(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 2)")
    labels = [f for f in wow.eval(f"{IMG}.labelPool").values() if f.IsShown(f)]
    assert sorted(f.text.GetText(f.text) for f in labels) == ["Elwynn Forest", "Stormwind City"]
    lines = [t for t in wow.eval(f"{IMG}.linePool").values() if t.IsShown(t)]
    assert len(lines) == 8  # four edges per zone
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 0)")
    assert not [f for f in wow.eval(f"{IMG}.labelPool").values() if f.IsShown(f)]
    assert not [t for t in wow.eval(f"{IMG}.linePool").values() if t.IsShown(t)]
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 1)")
    elwynn = next(
        f for f in wow.eval(f"{IMG}.labelPool").values() if f.IsShown(f) and f.map == 1429
    )
    wow.execute("GameTooltip:ClearLines()")
    elwynn.GetScript(elwynn, "OnEnter")(elwynn)
    assert wow.eval("GameTooltip:NumLines()") == 2  # the name and "Level 7-11"
    assert wow.eval("GameTooltip.lines[2].left") == "Level 7-11"
    assert wow.errors == []


def test_imagery_without_data_uses_the_client_names_and_no_level_range(wow: WowRuntime):
    boot(wow, CORE, MAP)
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 2)")
    zones = list(wow.eval(f"{IMG}.Zones(0)").values())
    assert [z.name for z in zones] == ["Eastern Kingdoms", "Elwynn Forest", "Stormwind City"]
    assert wow.eval(f"{IMG}.stats.textures") == 9
    assert wow.errors == []
