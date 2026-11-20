"""The ways into the City & dungeon map: a pulsing button on
the minimap in a place with a sheet, and a "City map" button on the game's world map at such a place.
Without the art there is neither."""

from harness import WowRuntime

CORE, DATA, BROWSER, MAP = "Bastians_Core", "Bastians_Data", "Bastians_Browser", "Bastians_Map"
MOD = "Bastians:GetModule('Map')"
LINK = f"{MOD}.CityLink"
STORMWIND, ELWYNN = 1453, 1429

ART = """
Bastians.Map = Bastians.Map or {}
Bastians.Map.cities = { { ui = 1453, name = "Stormwind City", continent = 0,
  wx = { -9154.17, -7995.83 }, wy = { -14.584, 1722.92 }, w = 4008, h = 2672, rows = 3, cols = 4,
  path = "Interface\\\\AddOns\\\\Bastians_Map_Art\\\\Generated\\\\Cities\\\\1453_" } }
"""


def boot(wow: WowRuntime, art: bool = True, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, BROWSER, MAP)))
    wow.run_frames(10)
    if art:
        wow.execute(ART)  # as Map Art's manifest; the next zone change finds it
    enter(wow, ELWYNN)
    return wow


def enter(wow: WowRuntime, ui_map: int) -> None:
    wow.execute(f"Mock.playerMap = {ui_map}")
    wow.fire("ZONE_CHANGED_NEW_AREA")
    wow.advance(0.5)


def setting(wow: WowRuntime, key: str, value: str) -> None:
    wow.execute(
        f"{MOD}.db.profile.{key} = {value}; "
        f"Bastians:Fire('BASTIANS_SETTING_CHANGED', {MOD}.name, '{key}', {value})"
    )


def nudge_shown(wow: WowRuntime) -> bool:
    return wow.eval(f"{LINK}.Nudge() ~= nil and {LINK}.Nudge():IsShown()") is True


def test_entering_a_city_shows_a_pulsing_button_leaving_removes_it(wow: WowRuntime):
    boot(wow)
    enter(wow, ELWYNN)
    assert not nudge_shown(wow)
    enter(wow, STORMWIND)
    assert nudge_shown(wow)
    assert wow.eval(f"{LINK}.Nudge().pulsing") is True
    assert wow.eval(f"{LINK}.Here().ui") == STORMWIND
    wow.run_frames(10, 0.1)
    assert 0.1 <= wow.eval(f"{LINK}.Nudge().glow:GetAlpha()") <= 0.85  # the halo breathes
    wow.run_frames(13, 1.0)  # CityLink.PULSE: then it stays, still
    assert wow.eval(f"{LINK}.Nudge().glow:GetAlpha()") == 0
    assert wow.eval(f"{LINK}.Nudge():GetScript('OnUpdate')") is None  # no tick without a pulse
    assert nudge_shown(wow)
    assert wow.eval(f"{LINK}.Nudge().pulsing") is False
    enter(wow, ELWYNN)
    assert not nudge_shown(wow)
    assert wow.errors == []


def test_the_button_sits_on_bastians_minimap_or_on_the_games(wow: WowRuntime):
    boot(wow)
    enter(wow, STORMWIND)
    assert wow.eval(f"{LINK}.Nudge().host") == "bastian"
    setting(wow, "miniMap", "false")
    wow.run_frames(5)
    assert wow.eval(f"{LINK}.Nudge().host") == "game"
    assert wow.eval(f"{LINK}.Nudge():GetParent() == Minimap") is True
    assert wow.errors == []


def test_a_click_opens_the_window_on_the_place_and_a_second_closes_it(wow: WowRuntime):
    boot(wow)
    enter(wow, STORMWIND)
    wow.execute(f"{LINK}.Nudge():Click()")
    assert wow.eval("BastiansCityFrame:IsShown()") is True
    assert wow.eval(f"{MOD}.City.Current().ui") == STORMWIND
    assert wow.eval(f"{LINK}.Nudge().pulsing") is False
    wow.execute(f"{LINK}.Nudge():Click()")
    assert wow.eval("BastiansCityFrame:IsShown()") is False
    assert wow.errors == []


def test_the_setting_off_means_no_button(wow: WowRuntime):
    boot(wow)
    setting(wow, "cityNudge", "false")
    enter(wow, STORMWIND)
    assert not nudge_shown(wow)
    setting(wow, "cityNudge", "true")
    wow.run_frames(2)
    assert nudge_shown(wow)
    assert wow.errors == []


def test_the_games_map_at_a_city_offers_the_city_map(wow: WowRuntime):
    boot(wow)
    wow.execute("WorldMapFrame:Show(); WorldMapFrame:SetMapID(1429)")
    button = f"{LINK}.Provider().button"
    assert wow.eval(f"{button} == nil or not {button}:IsShown()") is True
    wow.execute("WorldMapFrame:SetMapID(1453)")
    assert wow.eval(f"{button}:IsShown()") is True
    assert wow.eval(f"{button}:GetParent() == WorldMapFrame.ScrollContainer") is True
    wow.execute(f"{button}:Click()")
    assert wow.eval("WorldMapFrame:IsShown()") is False
    assert wow.eval("BastiansCityFrame:IsShown()") is True
    assert wow.eval(f"{MOD}.City.Current().ui") == STORMWIND
    wow.execute("WorldMapFrame:Show(); WorldMapFrame:SetMapID(1429)")
    assert wow.eval(f"{button}:IsShown()") is False
    assert wow.errors == []


def test_in_a_fight_the_games_map_stays_and_the_window_opens(wow: WowRuntime):
    boot(wow)
    wow.execute("WorldMapFrame:Show(); WorldMapFrame:SetMapID(1453)")
    wow.execute("Mock.SetCombat(true)")
    wow.execute(f"{LINK}.Provider().button:Click()")
    assert wow.eval("WorldMapFrame:IsShown()") is True
    assert wow.eval("BastiansCityFrame:IsShown()") is True
    assert wow.errors == []


def test_without_the_art_there_is_no_button_anywhere(wow: WowRuntime):
    boot(wow, art=False)
    enter(wow, STORMWIND)
    assert not nudge_shown(wow)
    assert wow.eval(f"{LINK}.Provider()") is None
    wow.execute("WorldMapFrame:Show(); WorldMapFrame:SetMapID(1453)")
    assert wow.errors == []
