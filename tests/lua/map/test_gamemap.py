"""The game's world map and ours (map.md Should rows, 22.10.2026): with "Open with M" on, the
game's map hides when it shows and ours opens at that map, an instance without a transform stays
on the game's map; with the overlay on, a data provider draws our overview cells over the game's
map canvas through the transforms; both settings off by default."""

from harness import WowRuntime

CORE, DATA, QUESTS, MAP = "Bastians_Core", "Bastians_Data", "Bastians_Quests", "Bastians_Map"
MOD = "Bastians:GetModule('Map')"
MAP_ = f"{MOD}.Map"
GM = f"{MOD}.GameMap"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA, QUESTS, MAP)
    wow.run_frames(10)
    wow.execute(
        "Bastians.Map.RegisterOverview({ client = Bastians.Client, span = 8, grid = 8, path = 'P/', "
        "continents = { [0] = { 36, 37, 44, 45 } } })"
    )
    return wow


def setting(wow: WowRuntime, key: str, on: bool) -> None:
    wow.execute(f"{MOD}.db.profile.{key} = {str(on).lower()}")
    wow.execute(f"Bastians:Fire('BASTIANS_SETTING_CHANGED', 'Map', '{key}', {str(on).lower()})")


def test_m_opens_our_map_and_instances_stay_on_the_games(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f"{MOD}.db.profile.openWithM") in (None, False)
    wow.execute("ToggleWorldMap()")
    assert wow.eval("WorldMapFrame:IsShown()") is True and wow.eval(f"{MAP_}.IsShown()") is False
    wow.execute("ToggleWorldMap()")
    setting(wow, "openWithM", True)
    wow.execute("ToggleWorldMap()")  # M: the game's map shows, goes, ours opens on Elwynn
    assert wow.eval("WorldMapFrame:IsShown()") is False
    assert wow.eval(f"{MAP_}.IsShown()") is True
    assert wow.eval(f"{MAP_}.Camera().continent") == 0
    wow.execute("ToggleWorldMap()")  # M again: ours closes too
    assert wow.eval("WorldMapFrame:IsShown()") is False and wow.eval(f"{MAP_}.IsShown()") is False
    # an instance (no transform of ours): the game's map stays
    wow.execute("WorldMapFrame.mapID = 99999")
    wow.execute("ToggleWorldMap()")
    assert wow.eval("WorldMapFrame:IsShown()") is True and wow.eval(f"{MAP_}.IsShown()") is False
    wow.execute("ToggleWorldMap(); WorldMapFrame.mapID = nil")
    # the setting off again: the game's map is left alone
    setting(wow, "openWithM", False)
    wow.execute("ToggleWorldMap()")
    assert wow.eval("WorldMapFrame:IsShown()") is True and wow.eval(f"{MAP_}.IsShown()") is False
    assert wow.errors == []


def test_the_overlay_draws_our_cells_over_the_games_map_through_the_transforms(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f"{GM}.Provider()") is None  # off by default
    setting(wow, "overlayGameMap", True)
    assert wow.eval(f"{GM}.Provider() ~= nil") is True
    wow.execute("WorldMapFrame:SetMapID(1429)")  # Elwynn: the cells around the origin
    n = wow.eval(f"{GM}.Provider().shown")
    assert 1 <= n <= 4
    tex = wow.eval(f"{GM}.Provider().textures[1]")
    assert tex.GetTexture(tex).startswith("P/0_")
    point = wow.eval(f"{{ {GM}.Provider().textures[1]:GetPoint(1) }}")
    assert point[1] == "TOPLEFT" and 0 <= point[4] <= 1002 and -668 <= point[5] <= 0
    assert tex.GetWidth(tex) > 1 and tex.GetHeight(tex) > 1
    # a map without a transform draws nothing; the setting off removes the provider
    wow.execute("WorldMapFrame:SetMapID(99999)")
    assert wow.eval(f"{GM}.Provider().shown") == 0
    setting(wow, "overlayGameMap", False)
    assert wow.eval(f"{GM}.Provider()") is None
    assert wow.eval("#WorldMapFrame.dataProviders") == 0
    assert wow.errors == []
