"""Map camera and window (B8.1): world <-> screen round trips, zoom to the cursor, pan, bounds, the
layer view, fitting bounds; the window opens on the player, zooms with the wheel, pans by drag and keys,
shows the zone and map percent under the cursor, and does no work while hidden."""

import math

from harness import WowRuntime

CORE, DATA, MAP = "Bastians_Core", "Bastians_Data", "Bastians_Map"
CAM = "Bastians:GetModule('Map').Camera"
MAP_ = "Bastians:GetModule('Map').Map"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, MAP)))
    wow.run_frames(5)
    return wow


def cam(wow: WowRuntime, code: str):
    return wow.eval(f"(function() local cam = {CAM}.new(0, 600, 400) {code} end)()")


def test_continent_list_and_names_come_from_the_transform_table(wow: WowRuntime):
    """coordinates.md: continents are Map.db2 ids named by the transform table (every world map
    with a zone on retail); the window lists them and the footer names them."""
    boot(wow)
    wow.execute("""
      Bastians.Data.RegisterTransforms(
        { [900] = { 530, 0, 0, 1000, 0, 1000, 0 } },
        { [0] = "Eastern Kingdoms", [1] = "Kalimdor", [530] = "Outland" })
    """)
    wow.slash("/bmap")
    values = dict(wow.eval(f"{MAP_}.toolbar.continent.values"))
    assert values == {0: "Eastern Kingdoms", 1: "Kalimdor", 530: "Outland"}
    assert wow.eval(f"{MAP_}.Describe(530, 5000, 5000)")[0] == "Outland"  # no zone holds the point
    assert wow.eval(f"{MAP_}.Describe(530, 300, 100)")[0] == "map 900 10.0, 30.0"  # unnamed zone
    assert (
        wow.eval(f"{MAP_}.CONTINENTS[530]") == "Outland"
        and wow.eval(f"{MAP_}.CONTINENTS[7]") is None
    )
    wow.eval(f"{MAP_}.SetContinent(530)")
    assert wow.eval(f"{MAP_}.Camera().continent") == 530
    assert wow.errors == []


def test_world_screen_round_trip_and_axes(wow: WowRuntime):
    boot(wow, CORE, MAP)
    # level 0: 32 yards per pixel; the centre of the view is the camera centre
    assert cam(wow, "cam:Center(100, 50) return cam:ToScreen(100, 50)") == (300, 200)
    # north (bigger wx) is up, west (bigger wy) is left
    sx, sy = cam(wow, "cam:Center(0, 0) return cam:ToScreen(320, 640)")
    assert (sx, sy) == (300 - 20, 200 - 10)
    wx, wy = cam(wow, "cam:Center(0, 0) cam:SetLevel(3) return cam:ToWorld(300 + 40, 200 - 80)")
    assert (round(wx, 6), round(wy, 6)) == (320, -160)  # level 3: 4 yards per pixel
    for level in (0, 2.5, 8):
        back = cam(
            wow,
            f"cam:Center(1234.5, -678.9) cam:SetLevel({level}) "
            "local sx, sy = cam:ToScreen(1000, -500) return cam:ToWorld(sx, sy)",
        )
        assert abs(back[0] - 1000) < 1e-6 and abs(back[1] + 500) < 1e-6


def test_zoom_keeps_the_point_under_the_cursor_and_clamps(wow: WowRuntime):
    boot(wow, CORE, MAP)
    before = cam(wow, "cam:Center(0, 0) cam:SetLevel(2) return cam:ToWorld(100, 50)")
    after = cam(
        wow,
        "cam:Center(0, 0) cam:SetLevel(2) cam:ZoomAt(100, 50, 1.5) return cam:ToWorld(100, 50)",
    )
    assert abs(after[0] - before[0]) < 1e-6 and abs(after[1] - before[1]) < 1e-6
    assert cam(wow, "cam:SetLevel(2) cam:ZoomAt(100, 50, 1.5) return cam.level") == 3.5
    assert cam(wow, "cam:SetLevel(8) return cam:ZoomAt(0, 0, 1)") is False  # already at the cap
    assert cam(wow, "cam:SetLevel(0) cam:ZoomAt(0, 0, -5) return cam.level") == 0
    assert cam(wow, "cam:SetLevel(1) return cam:Scale()") == 1 / 16


def test_pan_bounds_view_and_fit(wow: WowRuntime):
    boot(wow, CORE, MAP)
    # dragging right by 32 px at level 0 moves the centre 1024 yards west
    assert cam(wow, "cam:Center(0, 0) cam:Pan(32, 0) return cam.wx, cam.wy") == (0, 1024)
    assert cam(wow, "cam:Center(0, 0) cam:Pan(0, -10) return cam.wx, cam.wy") == (-320, 0)
    x1, y1, x2, y2 = cam(wow, "cam:Center(0, 0) cam:SetLevel(0) return cam:Bounds()")
    assert (x1, y1, x2, y2) == (-6400, -9600, 6400, 9600)  # 400 px tall = 12,800 yards, 600 wide
    view = cam(wow, "cam:Center(10, 20) cam:SetLevel(2.6) return cam:View({ 0, 1, 2 })")
    assert (view.continent, view.level, list(view.player.values())) == (0, 3, [0, 1, 2])
    assert view.x1 < 10 < view.x2 and view.y1 < 20 < view.y2
    fit = cam(wow, "cam:FitBounds(-200, -200, 200, 200) return cam.wx, cam.wy, cam.level")
    assert (fit[0], fit[1]) == (0, 0)
    # 440 yards with margin must fit 400 px: 0.909 px per yard -> level log2(0.909 * 32) = 4.86
    assert abs(fit[2] - math.log2(400 / 440 * 32)) < 1e-6
    assert cam(wow, "cam:Center(0, 0) return cam:Contains(0, 0), cam:Contains(99999, 0)") == (
        True,
        False,
    )


def test_window_opens_on_the_player_and_reacts_to_wheel_drag_and_keys(wow: WowRuntime):
    boot(wow)
    wow.slash("/bmap")
    assert wow.eval(f"{MAP_}.IsShown()") is True
    wow.execute(f"{MAP_}.clip:SetSize(600, 400); {MAP_}.ViewChanged()")
    c = wow.eval(f"{MAP_}.Camera()")
    assert (c.continent, c.level) == (0, 3)
    assert (round(c.wx, 6), round(c.wy, 6)) == (
        -60,
        32,
    )  # the player's world position (test_coords)
    # the footer names the zone and map percent under the cursor: the centre is the player
    wow.execute("Mock.cursorX, Mock.cursorY = 300, 200")
    wow.execute(f"{MAP_}.UpdateFooter()")
    footer = wow.eval(f"{MAP_}.footer:GetText()")
    assert footer.startswith("Elwynn Forest 42.0, 65.0") and "zoom 3.0" in footer
    # wheel up zooms in half a level keeping the cursor point
    wow.execute("Mock.cursorX, Mock.cursorY = 400, 300")
    wow.execute(f"{MAP_}.clip:GetScript('OnMouseWheel')({MAP_}.clip, 1)")
    c = wow.eval(f"{MAP_}.Camera()")
    assert c.level == 3.5
    # drag: mouse down, cursor moves, OnUpdate follows, mouse up
    before = (c.wx, c.wy)
    wow.execute("Mock.cursorX, Mock.cursorY = 100, 100")
    wow.execute(f"{MAP_}.clip:GetScript('OnMouseDown')({MAP_}.clip, 'LeftButton')")
    wow.execute("Mock.cursorX, Mock.cursorY = 150, 80")
    wow.run_frames(1)
    wow.execute(f"{MAP_}.clip:GetScript('OnMouseUp')({MAP_}.clip, 'LeftButton')")
    c = wow.eval(f"{MAP_}.Camera()")
    scale = 2**3.5 / 32
    assert (
        abs(c.wy - (before[1] + 50 / scale)) < 1e-6 and abs(c.wx - (before[0] + 20 / scale)) < 1e-6
    )
    # double-click: two left clicks within 0.4 s at the same spot zoom in one level (a Frame has
    # no OnDoubleClick script; the client refused it on 20.10.2026), a slow second click does not
    wow.execute("Mock.cursorX, Mock.cursorY = 150, 80")
    wow.execute(f"{MAP_}.clip:GetScript('OnMouseUp')({MAP_}.clip, 'LeftButton')")
    wow.advance(0.2)
    wow.execute(f"{MAP_}.clip:GetScript('OnMouseUp')({MAP_}.clip, 'LeftButton')")
    assert wow.eval(f"{MAP_}.Camera().level") == 4.5
    wow.execute(f"{MAP_}.clip:GetScript('OnMouseUp')({MAP_}.clip, 'LeftButton')")
    wow.advance(1)
    wow.execute(f"{MAP_}.clip:GetScript('OnMouseUp')({MAP_}.clip, 'LeftButton')")
    assert wow.eval(f"{MAP_}.Camera().level") == 4.5
    assert wow.eval(f"{MAP_}.clip:GetScript('OnDoubleClick')") is None
    wow.execute(f"{MAP_}.clip:GetScript('OnKeyDown')({MAP_}.clip, 'NUMPADPLUS')")
    # keys
    wow.execute(f"{MAP_}.clip:GetScript('OnKeyDown')({MAP_}.clip, 'NUMPADMINUS')")
    wow.execute(f"{MAP_}.clip:GetScript('OnKeyDown')({MAP_}.clip, 'NUMPADMINUS')")
    wow.execute(f"{MAP_}.clip:GetScript('OnKeyDown')({MAP_}.clip, 'NUMPADMINUS')")
    assert wow.eval(f"{MAP_}.Camera().level") == 2.5
    wy = wow.eval(f"{MAP_}.Camera().wy")
    wow.execute(f"{MAP_}.clip:GetScript('OnKeyDown')({MAP_}.clip, 'LEFT')")
    assert wow.eval(f"{MAP_}.Camera().wy") > wy
    wow.execute(f"{MAP_}.clip:GetScript('OnKeyDown')({MAP_}.clip, 'HOME')")
    c = wow.eval(f"{MAP_}.Camera()")
    assert (round(c.wx, 6), round(c.wy, 6)) == (-60, 32)
    # the settle callback fires once after the burst of changes
    wow.execute(
        f"settled = 0; table.insert({MAP_}.onSettle, function(cam, view) settled = settled + 1; lastView = view end)"
    )
    wow.execute(f"{MAP_}.Pan(10, 0); {MAP_}.Pan(10, 0); {MAP_}.Pan(10, 0)")
    wow.advance(0.05)
    assert wow.g.settled == 0
    wow.advance(0.1)
    assert (
        wow.g.settled == 1
        and wow.eval("lastView.continent") == 0
        and wow.eval("lastView.level") == 3
    )
    assert wow.errors == []


def test_continents_keep_their_cameras_and_hidden_map_does_nothing(wow: WowRuntime):
    boot(wow)
    wow.slash("/bmap")
    wow.execute(f"{MAP_}.clip:SetSize(600, 400)")
    wow.execute(f"{MAP_}.Fly(1, 500, 600, 4)")
    c = wow.eval(f"{MAP_}.Camera()")
    assert (c.continent, c.wx, c.wy, c.level) == (1, 500, 600, 4)
    assert wow.eval(f"{MAP_}.toolbar.continent:GetValue()") == 1
    wow.slash("/bmap ek")
    c = wow.eval(f"{MAP_}.Camera()")
    assert c.continent == 0 and round(c.wx, 6) == -60  # the Eastern Kingdoms camera as left
    wow.slash("/bmap kalimdor")
    assert wow.eval(f"{MAP_}.Camera().level") == 4
    assert wow.eval(f"({MAP_}.Describe(1, 500, 600))") == "Kalimdor"  # no zone there in the mock
    wow.slash("/bmap")
    assert wow.eval(f"{MAP_}.IsShown()") is False
    assert wow.eval(f"{MAP_}.clip:GetScript('OnUpdate')") is None  # no OnUpdate while hidden
    saved = wow.eval("Bastians:GetModule('Map').db.profile.cameras[1]")
    assert (saved.wx, saved.wy, saved.level) == (500, 600, 4)
    fresh = wow.reload()
    fresh.run_frames(5)
    fresh.slash("/bmap kalimdor")
    c = fresh.eval(f"{MAP_}.Camera()")
    assert (c.wx, c.wy, c.level) == (500, 600, 4)  # the camera survives /reload
    assert fresh.eval("BINDING_NAME_BASTIANS_MAP") == "Open Bastian's Map"
    assert fresh.errors == []


def test_map_alone_with_core_opens_without_data(wow: WowRuntime):
    boot(wow, CORE, MAP)
    wow.slash("/bmap")
    assert wow.eval(f"{MAP_}.IsShown()") is True
    wow.execute(
        f"{MAP_}.clip:SetSize(600, 400); Mock.cursorX, Mock.cursorY = 300, 200; {MAP_}.UpdateFooter()"
    )
    assert wow.eval(f"{MAP_}.footer:GetText()").startswith(
        "Elwynn Forest 42.0, 65.0"
    )  # the client API
    assert wow.errors == []
