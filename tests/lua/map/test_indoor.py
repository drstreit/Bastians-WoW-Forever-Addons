"""The cities inside the ground on the world map (map.md "Cities inside the ground"; owner, Forever
20.11.2026: in Ironforge "the map shows the surface, the minimap the city"): a place in
`Indoor.CITIES` draws its sheet of the City & dungeon map as the ground from level 3 on; the other
capitals keep their terrain; nothing without the art.

Since 21.11.2026 no place is in the list (owner, Forever: the Undercity's whole parchment "covers
the map"): the world map shows the terrain everywhere. The tests that draw put Ironforge in the
list themselves, for the machinery a cut-out sheet would use."""

from harness import WowRuntime

CORE, DATA, MAP = "Bastians_Core", "Bastians_Data", "Bastians_Map"
MOD = "Bastians:GetModule('Map')"
MAP_ = f"{MOD}.Map"
INDOOR = f"{MOD}.Indoor"

# the manifest as tools/city_sheet.py writes it (Ironforge's and Stormwind's rows, 20.11.2026)
ART = """
Bastians.Map = Bastians.Map or {}
Bastians.Map.cities = {
  { ui = 1453, name = "Stormwind City", continent = 0, wx = { -9154.17, -7995.83 },
    wy = { -14.584, 1722.92 }, w = 4008, h = 2672, rows = 3, cols = 4, path = "Cities/1453_" },
  { ui = 1455, name = "Ironforge", continent = 0, wx = { -5096.846, -4569.241 },
    wy = { -1504.216, -713.591 }, w = 4008, h = 2672, rows = 3, cols = 4, path = "Cities/1455_" },
}
"""
IRONFORGE = (-4833.0, -1108.9)  # the middle of its sheet, world yards
STORMWIND = (-8575.0, 854.2)


def boot(wow: WowRuntime, art: bool = True, ironforge: bool = True) -> WowRuntime:
    wow.start(CORE, DATA, MAP)
    wow.run_frames(5)
    if art:
        wow.execute(ART)
    if ironforge:
        wow.execute(f"{INDOOR}.CITIES[1455] = true")
    wow.slash("/bmap")
    wow.execute(f"{MAP_}.clip:SetSize(600, 400); {MAP_}.ViewChanged()")
    return wow


def fly(wow: WowRuntime, at: tuple[float, float], level: float, continent: int = 0) -> None:
    wow.execute(f"{MAP_}.Fly({continent}, {at[0]}, {at[1]}, {level})")


def live(wow: WowRuntime) -> dict:
    return {int(k): t for k, t in wow.eval(f"{INDOOR}.live").items()}


def test_ironforge_draws_its_sheet_as_the_ground(wow: WowRuntime):
    boot(wow)
    fly(wow, IRONFORGE, 4)
    tiles = live(wow)
    assert len(tiles) == 12 and wow.eval(f"{INDOOR}.stats.shown") == 12
    first, last = tiles[145500], tiles[145523]  # row 0, col 0 and row 2, col 3
    assert first.GetTexture(first) == "Cities/1455_0_0"
    assert last.GetTexture(last) == "Cities/1455_2_3"
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


def test_far_out_elsewhere_and_without_the_art_none(wow: WowRuntime):
    boot(wow)
    fly(wow, IRONFORGE, 2)  # the overview's levels: the land as before
    assert live(wow) == {}
    fly(wow, STORMWIND, 4)  # a city on the ground keeps its terrain
    assert live(wow) == {}
    fly(wow, IRONFORGE, 4)
    assert len(live(wow)) == 12
    fly(wow, (500, 500), 4, continent=1)  # another continent: gone
    assert live(wow) == {} and wow.eval(f"#{INDOOR}.free") == 12
    assert wow.errors == []


def test_no_city_draws_its_sheet_since_21_11(wow: WowRuntime):
    # the shipped list is empty: Ironforge and the Undercity show their terrain
    boot(wow, ironforge=False)
    assert wow.eval(f"next({INDOOR}.CITIES)") is None
    fly(wow, IRONFORGE, 4)
    assert live(wow) == {}
    assert wow.errors == []


def test_without_the_art_the_terrain_stays(wow: WowRuntime):
    boot(wow, art=False)
    fly(wow, IRONFORGE, 4)
    assert live(wow) == {}
    assert wow.errors == []
