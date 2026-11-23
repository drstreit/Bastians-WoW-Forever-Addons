"""The cities inside the ground on the world map (map.md "Cities inside the ground"; owner, Forever
20.11.2026: in Ironforge "the map shows the surface, the minimap the city"): a place whose manifest
row names `ground` tiles draws those tiles of its sheet as the ground from level 3 on, each cut out
to the city's plan by its mask; the other capitals keep their terrain; nothing without the art.

21.11.2026 (owner, Forever: the Undercity's whole parchment "covers the map"): only the masked
tiles, and a tile whose mask does not load stays hidden, never the parchment."""

from harness import WowRuntime

CORE, DATA, MAP = "Bastians_Core", "Bastians_Data", "Bastians_Map"
MOD = "Bastians:GetModule('Map')"
MAP_ = f"{MOD}.Map"
INDOOR = f"{MOD}.Indoor"

# the manifest as tools/city_sheet.py writes it after tools/city_ground.py (Ironforge with five
# tiles of its plan, Stormwind without ground)
ART = """
Bastians.Map = Bastians.Map or {}
Bastians.Map.cities = {
  { ui = 1453, name = "Stormwind City", continent = 0, wx = { -9154.17, -7995.83 },
    wy = { -14.584, 1722.92 }, w = 4008, h = 2672, rows = 3, cols = 4, path = "Cities/1453_" },
  { ui = 1455, name = "Ironforge", continent = 0, wx = { -5096.846, -4569.241 },
    wy = { -1504.216, -713.591 }, w = 4008, h = 2672, rows = 3, cols = 4, path = "Cities/1455_",
    ground = { "0_0", "1_1", "1_2", "2_1", "2_3" } },
}
"""
IRONFORGE = (-4833.0, -1108.9)  # the middle of its sheet, world yards
STORMWIND = (-8575.0, 854.2)


def boot(wow: WowRuntime, art: bool = True) -> WowRuntime:
    wow.start(CORE, DATA, MAP)
    wow.run_frames(5)
    if art:
        wow.execute(ART)
    wow.slash("/bmap")
    wow.execute(f"{MAP_}.clip:SetSize(600, 400); {MAP_}.ViewChanged()")
    return wow


def fly(wow: WowRuntime, at: tuple[float, float], level: float, continent: int = 0) -> None:
    wow.execute(f"{MAP_}.Fly({continent}, {at[0]}, {at[1]}, {level})")


def live(wow: WowRuntime) -> dict:
    return {int(k): t for k, t in wow.eval(f"{INDOOR}.live").items()}


def test_ironforge_draws_its_plan_tiles_masked(wow: WowRuntime):
    boot(wow)
    fly(wow, IRONFORGE, 4)
    tiles = live(wow)
    assert sorted(tiles) == [145500, 145511, 145512, 145521, 145523]  # the ground tiles alone
    assert wow.eval(f"{INDOOR}.stats.shown") == 5 and wow.eval(f"{INDOOR}.stats.unmasked") == 0
    first, last = tiles[145500], tiles[145523]  # row 0, col 0 and row 2, col 3
    assert first.GetTexture(first) == "Cities/1455_0_0"
    assert last.GetTexture(last) == "Cities/1455_2_3"
    for t in tiles.values():  # each with its own mask, shown
        mask = t.bastiansMask
        assert t.maskPath == t.GetTexture(t) + "_ground.tga"
        assert mask.GetTexture(mask) == t.maskPath and t.GetNumMaskTextures(t) == 1
        assert t.IsShown(t)
    # the sheet's tiles cover its region: the north-west tile starts at the region's corner
    rect = first.rect
    assert (round(rect.x2, 3), round(rect.y2, 3)) == (-4569.241, -713.591)
    # the padding of the edge tiles is cut off: 4008 x 2672 in tiles of 1024
    wanted = wow.eval(f"{INDOOR}.Wanted({MAP_}.Camera())")
    edge = next(t for t in wanted.values() if t.key == 145523)
    assert round(edge.tc[1], 4) == round((4008 - 3 * 1024) / 1024, 4)
    assert round(edge.tc[2], 4) == round((2672 - 2 * 1024) / 1024, 4)
    # above the styles' paintings and the native tiles
    assert wow.eval(f"{INDOOR}.sublevel") > wow.eval(f"{MOD}.Tiles.sublevel")
    assert wow.errors == []


def test_a_mask_that_does_not_load_hides_its_tile(wow: WowRuntime):
    boot(wow)
    # a new mask file the client has not seen yet (CLAUDE.md section 12): never the bare parchment
    wow.execute("Mock.unseen = { ['Cities/1455_1_1_ground.tga'] = true }")
    fly(wow, IRONFORGE, 4)
    tiles = live(wow)
    assert len(tiles) == 5
    hidden = tiles[145511]
    assert hidden.maskPath is None and not hidden.IsShown(hidden)
    assert all(t.IsShown(t) for key, t in tiles.items() if key != 145511)
    assert wow.eval(f"{INDOOR}.stats.unmasked") == 1 and wow.eval(f"{INDOOR}.stats.shown") == 4
    fly(wow, (IRONFORGE[0] + 20, IRONFORGE[1]), 4)  # a pan redraws: it stays hidden
    assert not hidden.IsShown(hidden)
    assert wow.errors == []


def test_far_out_elsewhere_and_without_ground_none(wow: WowRuntime):
    boot(wow)
    fly(wow, IRONFORGE, 2)  # the overview's levels: the land as before
    assert live(wow) == {}
    fly(wow, STORMWIND, 4)  # a city on the ground keeps its terrain
    assert live(wow) == {}
    fly(wow, IRONFORGE, 4)
    assert len(live(wow)) == 5
    fly(wow, (500, 500), 4, continent=1)  # another continent: gone
    assert live(wow) == {} and wow.eval(f"#{INDOOR}.free") == 5
    # a manifest without ground (the art before tools/city_ground.py): the terrain
    wow.execute("Bastians.Map.cities[2].ground = nil")
    fly(wow, IRONFORGE, 4)
    assert live(wow) == {}
    assert wow.errors == []


def test_without_the_art_the_terrain_stays(wow: WowRuntime):
    boot(wow, art=False)
    fly(wow, IRONFORGE, 4)
    assert live(wow) == {}
    assert wow.errors == []
