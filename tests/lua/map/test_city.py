"""The City & dungeon map (map.md "City plans", ADR 0065): a window of its own, only with its art; its
filters are its own; the sheet never leaves the view; the Browser docks to it."""

import pytest
from harness import WowRuntime

CORE, DATA, BROWSER, MAP = "Bastians_Core", "Bastians_Data", "Bastians_Browser", "Bastians_Map"
MOD = "Bastians:GetModule('Map')"
MAP_ = f"{MOD}.Map"
CITY = "CITY"

ART = """
Bastians.Map = Bastians.Map or {}
Bastians.Map.cities = { { ui = 1453, name = "Stormwind City", continent = 0,
  wx = { -9154.17, -7995.83 }, wy = { -14.584, 1722.92 }, w = 4008, h = 2672, rows = 3, cols = 4,
  path = "Interface\\\\AddOns\\\\Bastians_Map_Art\\\\Generated\\\\Cities\\\\1453_" } }
"""

LAYERS = """
Bastians:RegisterMapLayer(Bastians:GetModule('Map'), { id = "test.a", label = "A", defaultOn = true,
  minLevel = 6, maxLevel = 8, query = function(view)
    TEST_LEVEL = view.level
    return { { ref = "npc:1", wx = -8800, wy = 700, priority = 10 },
             { wx = -8800, wy = 3000 }, { kind = "text", wx = -8800, wy = 700, label = "x" } }
  end })
Bastians:RegisterMapLayer(Bastians:GetModule('Map'), { id = "route.path", label = "R", defaultOn = true,
  query = function() return { { ref = "npc:2", wx = -8800, wy = 700 } } end })
"""


def boot(wow: WowRuntime, art: bool = True, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, BROWSER, MAP)))
    wow.run_frames(10)
    if art:
        wow.execute(ART)
    wow.slash("/bmap")
    wow.execute(f"CITY = {MOD}.City")
    return wow


def open_city(wow: WowRuntime) -> None:
    wow.execute(LAYERS)
    wow.execute(f"{MAP_}.toolbar.city:Click()")
    wow.execute("BastiansCityFrame:SetSize(900, 680)")
    wow.execute(f"{CITY}.clip:SetSize(800, 560); {CITY}.Open()")
    wow.advance(0.3)


def test_without_the_art_there_is_no_button(wow: WowRuntime):
    boot(wow, art=False)
    wow.execute(f"{MAP_}.LayoutToolbar()")
    assert wow.eval(f"{MAP_}.toolbar.city:IsShown()") is False
    assert wow.eval(f"{CITY}.Open()") is False
    assert wow.errors == []


def test_with_the_art_the_button_opens_the_window(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{MAP_}.LayoutToolbar()")
    assert wow.eval(f"{MAP_}.toolbar.city:IsShown()") is True
    open_city(wow)
    assert wow.eval("BastiansCityFrame:IsShown()") is True
    assert wow.eval(f"{CITY}.Current().ui") == 1453
    assert wow.errors == []


def test_the_sheet_never_leaves_the_view(wow: WowRuntime):
    boot(wow)
    open_city(wow)
    wow.execute(
        f"c = {CITY}.Camera(); c:SetLevel(0); c:Center(0, 0); {CITY}.Clamp(c, {CITY}.Current())"
    )
    fit = wow.eval(f"{CITY}.FitLevel({CITY}.Current(), c.width, c.height)")
    assert wow.eval("c.level") == pytest.approx(fit)
    assert wow.eval("c.wx") == pytest.approx((-9154.17 - 7995.83) / 2)
    wow.execute(f"c.level = 9; c:Center(-8000, -14); {CITY}.Clamp(c, {CITY}.Current())")
    assert wow.eval("c.level") == 7
    # pushed back so that the view's corners stay on the sheet
    assert wow.eval("(select(3, c:Bounds()))") <= -7995.83 + 0.01
    assert wow.eval("(select(2, c:Bounds()))") >= -14.584 - 0.01


def test_the_tiles_cover_the_picture_and_not_the_padding(wow: WowRuntime):
    boot(wow)
    open_city(wow)
    cur = f"{CITY}.Current()"
    assert wow.eval(f"(select(5, {CITY}.TileRect({cur}, 0, 0)))") == 1
    assert wow.eval(f"(select(5, {CITY}.TileRect({cur}, 0, 3)))") == pytest.approx(936 / 1024)
    assert wow.eval(f"select(6, {CITY}.TileRect({cur}, 2, 0))") == pytest.approx(624 / 1024)
    assert wow.eval(f"(select(3, {CITY}.TileRect({cur}, 2, 0)))") == pytest.approx(
        -9154.17, abs=0.01
    )
    assert wow.eval(f"(select(4, {CITY}.TileRect({cur}, 0, 3)))") == pytest.approx(
        -14.584, abs=0.01
    )


def test_pins_are_asked_at_close_zoom_only_on_the_sheet_and_without_the_route(wow: WowRuntime):
    boot(wow)
    open_city(wow)
    assert wow.eval("TEST_LEVEL") == 6
    refs = wow.eval(
        f"(function() local n = 0; for _, p in ipairs({CITY}.Query({CITY}.Current())) do "
        "if p.ref == 'npc:1' then n = n + 1 elseif p.ref == 'npc:2' then n = n + 100 end end return n end)()"
    )
    assert refs == 1


def test_its_filters_are_its_own(wow: WowRuntime):
    boot(wow)
    open_city(wow)
    d = "Bastians:GetMapLayer('test.a')"
    assert wow.eval(f"{CITY}.IsLayerOn({d})") is True
    wow.execute(f"{MOD}.db.profile.city.layers['test.a'] = false")
    assert wow.eval(f"{CITY}.IsLayerOn({d})") is False
    assert wow.eval(f"{MOD}.Pins.IsLayerOn({d})") is True  # the world map's stays
    wow.execute(
        f"{MOD}.Pins.SetLayerOn('test.a', false); {MOD}.db.profile.city.layers['test.a'] = true"
    )
    assert wow.eval(f"{CITY}.IsLayerOn({d})") is True
    assert wow.errors == []


def test_the_browser_docks_to_this_window_and_the_map_keeps_its_own(wow: WowRuntime):
    boot(wow)
    open_city(wow)
    leader = "BastiansCityFrame"
    wow.execute(f"{CITY}.bar.dock:Click()")
    assert wow.eval(f"Bastians.UI.IsDocked('{leader}')") is True
    assert wow.eval("Bastians.UI.IsDocked(Bastians.UI.DOCK.left)") is False
    assert wow.eval("BastiansBrowserFrame:IsShown()") is True
    wow.execute(f"{MAP_}.toolbar.dock:Click()")  # moves to the map
    assert wow.eval("Bastians.UI.IsDocked(Bastians.UI.DOCK.left)") is True
    assert wow.eval(f"Bastians.UI.IsDocked('{leader}')") is False
    wow.execute(f"{CITY}.bar.dock:Click()")  # and back
    assert wow.eval(f"Bastians.UI.IsDocked('{leader}')") is True
    wow.execute(f"{CITY}.bar.dock:Click()")  # a second press undocks
    assert wow.eval("Bastians.UI.IsDocked()") is False
    assert wow.errors == []


def test_a_right_click_offers_the_place_with_its_point(wow: WowRuntime):
    boot(wow)
    open_city(wow)
    wow.execute("""
      TEST_MENU = nil
      local old = Bastians.UI.EntityMenu
      Bastians.UI.EntityMenu = function(ref, anchor, ctx) TEST_MENU = { ref, ctx } end
    """)
    wow.execute(f"{CITY}.clip:GetScript('OnMouseDown')({CITY}.clip, 'RightButton')")
    wow.execute(f"{CITY}.clip:GetScript('OnMouseUp')({CITY}.clip, 'RightButton')")
    assert wow.eval("TEST_MENU[1]") == "zone:1453"
    assert wow.eval("type(TEST_MENU[2].point)") == "table"
    assert wow.eval("TEST_MENU[2].point[1]") == 0
    assert wow.errors == []


SIX = """
Bastians.Map.cities = {
  { ui = 1453, name = "Stormwind City", continent = 0, wx = { -9154.17, -7995.83 },
    wy = { -14.584, 1722.92 }, w = 4008, h = 2672, rows = 3, cols = 4, path = "x\\1453_" },
  { ui = 1454, name = "Orgrimmar", continent = 1, wx = { 1338.461, 2273.877 },
    wy = { -5083.206, -3680.601 }, w = 4008, h = 2672, rows = 3, cols = 4, path = "x\\1454_" },
  { ui = 1455, name = "Ironforge", continent = 0, wx = { -5096.846, -4569.241 },
    wy = { -1504.216, -713.591 }, w = 4008, h = 2672, rows = 3, cols = 4, path = "x\\1455_" },
}
"""


def test_a_small_place_zooms_to_its_own_pixels(wow: WowRuntime):
    boot(wow)
    wow.execute(SIX)
    stormwind, ironforge = "Bastians.Map.cities[1]", "Bastians.Map.cities[3]"
    assert wow.eval(f"{CITY}.MaxLevel({stormwind})") == 7  # as before: 6.2 its own pixels
    # Ironforge is 790 yards across on the same 4008 pixels: its own pixels are level 7.3
    assert wow.eval(f"{CITY}.MaxLevel({ironforge})") == pytest.approx(7.34 + 0.75, abs=0.01)
    open_city(wow)
    wow.execute(f"{CITY}.Show({ironforge})")
    wow.execute(f"c = {CITY}.Camera(); c.level = 12; {CITY}.Clamp(c, {ironforge})")
    assert wow.eval("c.level") == pytest.approx(8.09, abs=0.01)
    assert wow.errors == []


def test_a_bare_open_shows_where_the_player_stands(wow: WowRuntime):
    boot(wow)
    wow.execute(SIX)
    wow.execute("Mock.playerMap = 1429")
    wow.fire("ZONE_CHANGED_NEW_AREA")
    wow.advance(0.5)
    assert wow.eval(f"{CITY}.Default().ui") == 1453  # in no city: the own side's capital
    wow.execute("function UnitFactionGroup() return 'Horde', 'Horde' end")
    assert wow.eval(f"{CITY}.Default().ui") == 1454
    wow.execute(f"{CITY}.Open(Bastians.Map.cities[3])")
    assert wow.eval(f"{CITY}.Default().ui") == 1455  # then the last one shown
    wow.execute("Mock.playerMap = 1454")
    wow.fire("ZONE_CHANGED_NEW_AREA")
    wow.advance(0.5)
    wow.execute(f"{CITY}.win:Hide(); {CITY}.Toggle()")
    assert wow.eval(f"{CITY}.Current().ui") == 1454  # standing in a place: that one
    assert wow.errors == []


def test_places_without_room_go_into_the_more_menu(wow: WowRuntime):
    boot(wow)
    wow.execute(SIX)
    open_city(wow)
    bar = f"{CITY}.bar"
    wow.execute(f"{bar}:SetWidth(2000); {CITY}.Open()")
    assert wow.eval(f"{bar}.more:IsShown()") is False  # a wide window: every place has its button
    assert wow.eval(f"#{bar}.hidden") == 0
    wow.execute(f"{bar}:SetWidth(520); {CITY}.Open()")
    assert wow.eval(f"{bar}.more:IsShown()") is True
    hidden = wow.eval(f"#{bar}.hidden")
    assert 1 <= hidden <= 2
    # no place button reaches under the bar's own buttons
    assert wow.eval(f"{bar}.more:GetWidth() > 0") is True
    labels = [wow.eval(f"{CITY}.MoreItems()[{i}].label") for i in range(1, hidden + 1)]
    assert labels[-1] == "Ironforge"  # the registry's order: the last places go first
    # the menu's entry shows that place, and the button wears the accent while it is shown
    wow.execute(f"{CITY}.MoreItems()[{hidden}].onClick()")
    assert wow.eval(f"{CITY}.Current().ui") == 1455
    assert wow.eval(f"{bar}.more.token") == "accent"
    wow.execute(f"{CITY}.Show(Bastians.Map.cities[1])")
    assert wow.eval(f"{bar}.more.token") == "dim"
    assert wow.errors == []


def stand(wow: WowRuntime, ui_map: int, wx: float, wy: float) -> None:
    """The player at a world point of Eastern Kingdoms, on the given map (the mock's own map
    transform is not Stormwind's, so the point is given as the Core would answer it)."""
    wow.execute(
        f"Mock.playerMap = {ui_map}; "
        f"Bastians.Coords.Player = function() return 0, {wx}, {wy}, {ui_map}, 0.5, 0.5 end"
    )
    wow.fire("ZONE_CHANGED_NEW_AREA")
    wow.advance(0.5)
    wow.run_frames(5, 0.1)


def test_the_player_is_marked_above_the_pins(wow: WowRuntime):
    boot(wow)
    stand(wow, 1453, -8800, 700)
    open_city(wow)
    wow.run_frames(5, 0.1)
    you = f"{CITY}.you"
    assert wow.eval(f"{you}:IsShown()") is True
    sx = wow.eval(f"({CITY}.Camera():ToScreen(-8800, 700))")
    sy = wow.eval(f"(select(2, {CITY}.Camera():ToScreen(-8800, 700)))")
    point = wow.eval(f"{{ {you}:GetPoint(1) }}")
    assert point[4] == pytest.approx(sx) and point[5] == pytest.approx(-sy)
    # a city's pins must not cover it
    clip = wow.eval(f"{CITY}.clip:GetFrameLevel()")
    pin = wow.eval(f"{CITY}.pool[1]:GetFrameLevel()")
    assert pin == clip + 5
    assert wow.eval(f"{you}:GetFrameLevel()") > pin  # the arrow above the pins
    # nor its disc the pin the player stands on (Daryl Riknussun
    # "missing" while the player stood at him): the disc lies under the pins, shown with the arrow
    assert wow.eval(f"{you}.disc:GetFrameLevel()") < pin
    assert wow.eval(f"{you}.disc:IsShown()") is True
    assert wow.eval(f"{you}.rim:GetParent() == {you}.disc") is True
    assert wow.eval(f"{you}:IsMouseEnabled()") is not True  # a click goes through to the sheet
    assert wow.eval(f"{you}.disc:IsMouseEnabled()") is not True
    wow.execute(f"{you}:Hide()")
    assert wow.eval(f"{you}.disc:IsShown()") is False
    assert wow.errors == []


def test_outside_the_sheet_there_is_no_marker_and_the_button_says_so(wow: WowRuntime):
    boot(wow)
    stand(wow, 1429, -9500, 100)  # Goldshire, south of the sheet
    open_city(wow)
    wow.run_frames(5, 0.1)
    assert wow.eval(f"{CITY}.you:IsShown()") is False
    assert wow.eval(f"{CITY}.PlayerPlace()") is None
    assert wow.eval(f"{CITY}.bar.you.token") == "dim"
    assert wow.eval(f"{CITY}.ShowPlayer()") is False
    assert wow.eval(f"select(2, {CITY}.bar.you.tip())") == "You are not in a city with a map."
    assert wow.errors == []


def test_the_player_button_brings_the_player_into_view(wow: WowRuntime):
    boot(wow)
    wow.execute(SIX)
    stand(wow, 1453, -8800, 700)
    open_city(wow)
    wow.execute(f"{CITY}.Show(Bastians.Map.cities[3])")  # looking at Ironforge
    wow.run_frames(3, 0.1)
    assert wow.eval(f"{CITY}.you:IsShown()") is False
    assert wow.eval(f"{CITY}.bar.you.token") == "good"  # but standing on a sheet
    wow.execute(f"{CITY}.bar.you:Click()")
    assert wow.eval(f"{CITY}.Current().ui") == 1453
    cam = f"{CITY}.Camera()"
    fit = wow.eval(f"{CITY}.FitLevel({CITY}.Current(), {cam}.width, {cam}.height)")
    assert wow.eval(f"{cam}.level") == pytest.approx(fit + 1.5)
    assert wow.eval(f"{cam}.wx") == pytest.approx(-8800, abs=1)  # centred on the player
    assert wow.eval(f"{cam}.wy") == pytest.approx(700, abs=1)
    assert wow.eval(f"{CITY}.you:IsShown()") is True
    wow.execute(f"{cam}.level = {fit} + 3; {CITY}.bar.you:Click()")
    assert wow.eval(f"{cam}.level") == pytest.approx(fit + 3)  # never zooms out
    assert wow.errors == []
