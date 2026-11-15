"""The dots layer of Bastian's minimap (ADR 0078, map.md "The dots layer"; owner, Forever
1.60.1.70938, 15.11.2026: "and the mining nodes are gone again?"). On our styles the game's
minimap, its ground switched off, lies between our tiles and our pins; it draws what the game's
tracking finds around the player at its own scale, so our view follows the player at that scale.
The wheel steps the game's zooms, a drag or a notch past the widest zoom hides the layer until
Recentre or walking, and everything goes back when the layer is not wanted, never in a fight."""

import math

import pytest
from harness import WowRuntime
from test_mini import MINI, MOD, boot, setting

TR = f"{MOD}.Tracked"
RADII = {0: 233.335, 1: 200, 2: 166.665, 3: 133.335, 4: 100, 5: 66.665}  # the mock's, half of HBD's


def our_style(wow: WowRuntime, style: str = "physical") -> None:
    wow.execute(f"{MOD}.db.profile.miniWarned = true; {MINI}.SetStyle('{style}')")
    wow.run_frames(2)


def shown(wow: WowRuntime) -> bool:
    return wow.eval(f"{MINI}.DotsShown()")


def why(wow: WowRuntime) -> str | None:
    return wow.eval(f"select(2, {MINI}.DotsWanted())")


def fitted(wow: WowRuntime) -> bool:
    """Our camera at the game's scale: half the game minimap's width for its view radius."""
    return wow.eval(
        f"""(function()
          local half = Minimap:GetWidth() / 2 * Minimap:GetEffectiveScale()
            / {MINI}.View():GetEffectiveScale()
          return math.abs({MINI}.Camera():Scale() - half / C_Minimap.GetViewRadius()) < 1e-9
        end)()"""
    )


def put_back(wow: WowRuntime) -> bool:
    """The game's state: its ground drawn, its minimap one level above the view, under our tiles."""
    return (
        wow.eval("Mock.ground") is True
        and wow.eval(f"Minimap:GetFrameLevel() == {MINI}.View():GetFrameLevel() + 1") is True
    )


def wheel(wow: WowRuntime, delta: int) -> None:
    wow.execute(f"{MINI}.catcher:GetScript('OnMouseWheel')({MINI}.catcher, {delta})")


def drag_on_the_game_minimap(wow: WowRuntime, dx: float = 40) -> None:
    wow.execute("Mock.cursorX, Mock.cursorY = 500, 500; Mock.SetMouseButton('LeftButton', true)")
    wow.execute("Minimap:GetScript('OnMouseDown')(Minimap, 'LeftButton')")
    wow.execute(f"Mock.cursorX = 500 + {dx}")
    wow.run_frames(2)


def release(wow: WowRuntime) -> None:
    wow.execute("Mock.SetMouseButton('LeftButton', false)")
    wow.execute("Minimap:GetScript('OnMouseUp')(Minimap, 'LeftButton')")
    wow.run_frames(2)


def test_the_level_from_half_a_width_and_a_radius():
    """Pure: the measured fits of 15.11.2026 (a 320 px view, ADR 0078's record)."""
    wow = WowRuntime()
    wow.start("Bastians_Core", "Bastians_Data", "Bastians_Map")
    fit = f"{MINI}.FitLevel"
    assert wow.eval(f"{fit}(160, 166.7)") == pytest.approx(4.94, abs=0.005)
    assert wow.eval(f"{fit}(160, 200)") == pytest.approx(4.68, abs=0.005)
    # 32 yards per pixel at level 0: 16 px for 512 yd is level 0
    assert wow.eval(f"{fit}(16, 512)") == pytest.approx(0)
    assert wow.eval(f"{fit}(160, 0)") is None
    assert wow.eval(f"{fit}(0, 100)") is None
    assert wow.eval(f"{fit}(160, nil)") is None


def test_our_style_lays_the_game_minimap_between_our_tiles_and_our_pins(wow: WowRuntime):
    boot(wow)
    assert shown(wow) is False and why(wow) == "game" and wow.eval("Mock.ground") is True
    wow.execute("Mock.minimapZoom = 2")
    our_style(wow)
    assert shown(wow) is True
    assert wow.eval("Mock.ground") is False  # the game's ground off, its dots on our tiles
    view = wow.eval(f"{MINI}.View():GetFrameLevel()")
    clip = wow.eval(f"{MINI}.clip:GetFrameLevel()")
    level = wow.eval("Minimap:GetFrameLevel()")
    overlay = wow.eval("BastiansMinimapOverlay:GetFrameLevel()")
    assert level == view + 12 and clip < level < overlay  # over the tiles, under the pins
    assert wow.eval(f"Minimap:GetParent() == {MINI}.View()") is True
    # our view on the player at the game's scale; the game's arrow is the player's mark
    assert fitted(wow) and wow.eval(f"{MINI}.Following()") is True
    cam = wow.eval(f"{MINI}.Camera()")
    player = wow.eval("{ Bastians.Coords.Player() }")
    assert (cam.continent, cam.wx, cam.wy) == (player[1], player[2], player[3])
    assert wow.eval(f"{MINI}.arrow:IsShown()") is False
    # the wheel reaches us over the game's minimap through the catcher; clicks stay the game's
    assert wow.eval(f"{MINI}.catcher:IsShown()") is True
    assert wow.eval(f"{MINI}.catcher:IsMouseEnabled()") is False
    # the sweep rests and its note is silent: the game's minimap draws the dots itself
    assert wow.eval(f"{TR}.Running()") is False
    assert wow.eval(f"{TR}.Note()") is None
    assert wow.eval("Mock.groundInCombat") == 0
    assert wow.errors == []


def test_the_wheel_steps_the_games_zooms_and_a_notch_past_the_widest_hides_it(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.minimapZoom = 2")
    our_style(wow)
    chosen = wow.eval(f"{MOD}.db.profile.miniLevel")
    wheel(wow, 1)
    assert wow.eval("Minimap:GetZoom()") == 3 and fitted(wow)
    wow.advance(0.05)  # the client's MINIMAP_UPDATE_ZOOM draws again: still fitted
    assert fitted(wow) and shown(wow) is True
    for _ in range(3):
        wheel(wow, -1)
    assert wow.eval("Minimap:GetZoom()") == 0 and fitted(wow) and shown(wow) is True
    widest = wow.eval(f"{MINI}.Camera().level")
    assert wow.eval(f"{MOD}.db.profile.miniLevel") == chosen  # the game's zoom is not ours
    # one notch out at the widest zoom: the layer goes, our own zoom takes over
    wheel(wow, -1)
    assert shown(wow) is False and why(wow) == "elsewhere"
    assert put_back(wow)
    assert wow.eval("Minimap:GetZoom()") == 0
    assert wow.eval(f"{MINI}.Camera().level") == pytest.approx(widest - 0.5)
    assert wow.eval(f"{MOD}.db.profile.miniLevel") == pytest.approx(widest - 0.5)
    assert wow.eval(f"{MINI}.recentre:IsShown()") is True
    assert (
        wow.eval(f"{MINI}.arrow:IsShown()") is True
        and wow.eval(f"{MINI}.catcher:IsShown()") is False
    )
    wow.execute(f"Mock.shift = true; {MINI}.clip:GetScript('OnMouseWheel')({MINI}.clip, -1)")
    wow.execute("Mock.shift = false")
    assert wow.eval(f"{MINI}.Camera().level") == pytest.approx(widest - 1)
    # Recentre: the player at the game's zoom, the dots with it
    wow.execute(f"{MINI}.recentre:Click()")
    assert shown(wow) is True and fitted(wow)
    assert wow.eval(f"{MINI}.Camera().level") == pytest.approx(widest)
    assert wow.eval(f"{MINI}.recentre:IsShown()") is False
    assert wow.errors == []


def test_a_drag_hides_the_layer_until_recentre_or_walking(wow: WowRuntime):
    boot(wow)
    our_style(wow)
    cam = wow.eval(f"{MINI}.Camera()")
    wx, wy, level = cam.wx, cam.wy, cam.level
    # a plain click pings (the game's own handler) and keeps the layer
    wow.execute("Mock.SetMouseButton('LeftButton', true)")
    wow.execute("Minimap:GetScript('OnMouseDown')(Minimap, 'LeftButton')")
    release(wow)
    assert shown(wow) is True and wow.eval(f"{MINI}.Following()") is True
    # a plain drag on the game's minimap is our drag: the view leaves the player, the layer goes
    drag_on_the_game_minimap(wow)
    assert wow.eval(f"{MINI}.Following()") is False and shown(wow) is False
    assert put_back(wow)
    cam = wow.eval(f"{MINI}.Camera()")
    assert (cam.wx, cam.wy) != (wx, wy)
    assert cam.level == level  # the scale it looked at stays
    assert wow.eval(f"{MINI}.recentre:IsShown()") is True
    release(wow)
    assert wow.eval("BastiansMiniMap:GetScript('OnUpdate')") is None  # nothing ticks when still
    wow.execute(f"{MINI}.recentre:Click()")
    assert shown(wow) is True and fitted(wow)
    cam = wow.eval(f"{MINI}.Camera()")
    assert (cam.wx, cam.wy) == (wx, wy)
    # walking brings it back too
    drag_on_the_game_minimap(wow)
    release(wow)
    assert shown(wow) is False
    wow.fire("PLAYER_STARTED_MOVING")
    wow.run_frames(2)
    assert shown(wow) is True and wow.eval(f"{MINI}.Following()") is True
    wow.fire("PLAYER_STOPPED_MOVING")
    wow.run_frames(2)
    assert wow.errors == []


def test_a_drag_whose_release_the_game_minimap_never_heard_ends(wow: WowRuntime):
    boot(wow)
    our_style(wow)
    drag_on_the_game_minimap(wow)
    wow.execute("Mock.SetMouseButton('LeftButton', false)")  # released, no OnMouseUp anywhere
    wow.run_frames(2)
    x = wow.eval(f"{MINI}.Camera().wy")
    wow.execute("Mock.cursorX = 700")
    wow.run_frames(3)
    assert wow.eval(f"{MINI}.Camera().wy") == x  # the view no longer follows the cursor
    assert wow.eval("BastiansMiniMap:GetScript('OnUpdate')") is None
    assert wow.errors == []


def test_alt_drag_moves_the_frame_and_the_right_click_opens_the_place_menu(wow: WowRuntime):
    boot(wow)
    our_style(wow)
    wow.execute(
        f"""M = nil
        {MOD}.Waypoints.PointMenu = function(c, wx, wy, source) M = {{ c, wx, wy, source }} return true end"""
    )
    wow.execute("Mock.alt = true; Minimap:GetScript('OnMouseDown')(Minimap, 'LeftButton')")
    assert wow.eval("BastiansMiniMap.moving") is True
    wow.execute("Minimap:GetScript('OnMouseUp')(Minimap, 'LeftButton'); Mock.alt = false")
    assert wow.eval("BastiansMiniMap.moving") is None
    assert shown(wow) is True  # the frame moved, the view still on the player
    top = wow.eval(f"{MINI}.clip:GetTop()")
    wow.execute(f"Mock.cursorX, Mock.cursorY = 30, {top} - 40")
    wow.execute("Minimap:GetScript('OnMouseUp')(Minimap, 'RightButton')")
    menu = wow.eval("M")
    expected = wow.eval(f"{{ {MINI}.Camera():ToWorld(30, 40) }}")
    assert menu[4] == "minimap" and (menu[2], menu[3]) == (expected[1], expected[2])
    assert wow.errors == []


def test_the_zoom_event_and_the_zone_events_set_the_scale_again(wow: WowRuntime):
    boot(wow)
    our_style(wow)
    wow.execute("Minimap:SetZoom(4)")  # the game's own zoom (another addon, a key binding)
    wow.advance(0.05)  # MINIMAP_UPDATE_ZOOM, a frame later
    assert fitted(wow)
    # indoors the client answers another radius; the zone event draws
    wow.execute("Mock.minimapViewRadius = 40")
    wow.fire("ZONE_CHANGED_INDOORS")
    assert fitted(wow) and shown(wow) is True
    # Alt+wheel sizes the view: half its width for the same radius
    wow.execute(f"Mock.alt = true; {MINI}.catcher:GetScript('OnMouseWheel')({MINI}.catcher, 2)")
    wow.execute("Mock.alt = false")
    wow.advance(0.05)
    assert wow.eval("Minimap:GetWidth()") == 220 and fitted(wow)
    assert wow.errors == []


def test_the_ground_switched_on_behind_our_back_goes_off_again(wow: WowRuntime):
    boot(wow)
    our_style(wow)
    wow.execute("Mock.ground = true")  # the game's own hybrid map gave it back
    wow.execute(f"{MINI}.Render()")
    assert wow.eval("Mock.ground") is False
    assert wow.errors == []


@pytest.mark.parametrize(
    ("leave", "reason"),
    [
        (f"{MINI}.SetStyle('game')", "game"),
        ("SETTING miniTracked false", "setting"),
        ("Mock.cvars.rotateMinimap = '1'; Mock.Fire('PLAYER_STARTED_TURNING')", "rotating"),
        (f"Mock.instanceType = 'party'; {MINI}.Render()", "instance"),
    ],
)
def test_leaving_puts_the_ground_back_and_our_level(wow: WowRuntime, leave: str, reason: str):
    """Put back: the ground on, the minimap under our tiles, our camera at the player's level.
    A rotating minimap (G4) and an instance (G3) are not measured: no layer there."""
    boot(wow)
    wow.execute(f"{MOD}.db.profile.miniLevel = 3")
    wow.execute("Mock.minimapZoom = 5")
    our_style(wow)
    assert shown(wow) is True and wow.eval(f"{MINI}.Camera().level") != 3
    if leave.startswith("SETTING"):
        setting(wow, "miniTracked", "false")
    else:
        wow.execute(leave)
    assert shown(wow) is False and why(wow) == reason
    assert put_back(wow)
    assert wow.eval(f"{MINI}.Camera().level") == 3
    assert wow.eval(f"{MINI}.arrow:IsShown()") is (reason != "game")  # the mock has a place
    assert wow.eval("Mock.groundInCombat") == 0
    assert wow.errors == []


def test_the_setting_brings_it_back_and_a_hidden_frame_puts_it_back(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{MOD}.db.profile.miniTracked = false")
    our_style(wow)
    assert shown(wow) is False and why(wow) == "setting"
    setting(wow, "miniTracked", "true")
    assert shown(wow) is True and fitted(wow)
    wow.execute("BastiansMiniMap:Hide()")
    assert shown(wow) is False and put_back(wow)
    wow.execute("BastiansMiniMap:Show()")
    assert shown(wow) is True
    assert wow.errors == []


def test_the_minimap_off_the_module_off_and_the_logout_give_everything_back(wow: WowRuntime):
    wow.start("Bastians_Core", "Bastians_Data", "Bastians_Map")
    wow.execute(f"{MOD}.db.profile.miniMap = false; {MINI}.Apply()")
    level = wow.eval("Minimap:GetFrameLevel()")  # the game's own, before the takeover
    wow.execute(f"{MOD}.db.profile.miniMap = true")
    wow.fire("PLAYER_ENTERING_WORLD")
    wow.run_frames(5)
    our_style(wow)
    assert shown(wow) is True
    setting(wow, "miniMap", "false")
    assert wow.eval("Mock.ground") is True and wow.eval("Minimap:GetFrameLevel()") == level
    setting(wow, "miniMap", "true")
    wow.run_frames(2)
    assert shown(wow) is True and wow.eval("Mock.ground") is False
    wow.execute(f"{MOD}:Disable()")
    assert wow.eval("Mock.ground") is True and wow.eval("Minimap:GetFrameLevel()") == level
    wow.execute(f"{MOD}:Enable()")
    wow.fire("PLAYER_ENTERING_WORLD")
    wow.run_frames(2)
    assert shown(wow) is True
    wow.fire("PLAYER_LOGOUT")
    assert wow.eval("Mock.ground") is True
    assert wow.errors == []


def test_nothing_changes_in_a_fight_and_the_wish_waits_for_its_end(wow: WowRuntime):
    boot(wow)
    our_style(wow)
    calls = wow.eval("Mock.groundCalls")
    wow.execute("Mock.combat = true")
    # no drag starts; a notch past the widest zoom does nothing; the wheel still steps the game's
    drag_on_the_game_minimap(wow)
    assert wow.eval(f"{MINI}.Following()") is True and shown(wow) is True
    release(wow)
    wow.execute("Minimap:SetZoom(0)")
    wheel(wow, -1)
    assert shown(wow) is True and wow.eval(f"{MINI}.Following()") is True
    wheel(wow, 1)
    assert wow.eval("Minimap:GetZoom()") == 1 and fitted(wow)
    # leaving waits: the style, then the frame hidden
    wow.execute(f"{MINI}.SetStyle('game')")
    assert shown(wow) is True and wow.eval("Mock.ground") is False
    wow.execute("BastiansMiniMap:Hide()")
    assert shown(wow) is True
    assert wow.eval("Mock.groundCalls") == calls and wow.eval("Mock.groundInCombat") == 0
    wow.execute("Mock.combat = false")
    wow.fire("PLAYER_REGEN_ENABLED")
    assert shown(wow) is False and put_back(wow)
    # and a take that falls into a fight waits too
    wow.execute("BastiansMiniMap:Show()")
    wow.execute("Mock.combat = true")
    our_style(wow)
    assert shown(wow) is False
    wow.execute("Mock.combat = false")
    wow.fire("PLAYER_REGEN_ENABLED")
    assert shown(wow) is True and fitted(wow)
    assert wow.eval("Mock.groundInCombat") == 0
    assert wow.errors == []


def test_a_client_without_the_switch_keeps_the_sweep(wow: WowRuntime):
    """ADR 0078 decision 7: the sweep stays where the switch is missing."""
    boot(wow)
    wow.execute("Mock.GroundSwitch(false)")
    our_style(wow, "physical")
    assert shown(wow) is False and why(wow) == "client"
    assert wow.eval(f"{TR}.Running()") is True
    assert wow.eval("Mock.ground") is True
    assert wow.errors == []


def test_without_the_data_the_layer_still_shows_and_says_nothing(wow: WowRuntime):
    """CLAUDE.md rule 4: the dots layer needs no Bastian's Data (the game draws the dots)."""
    boot(wow)
    wow.execute(
        """
        local service = Bastians.GetService
        Bastians.GetService = function(self, name)
          if name == "data" then return nil end
          return service(self, name)
        end
        """
    )
    our_style(wow)
    assert shown(wow) is True and wow.eval(f"{TR}.Note()") is None
    assert wow.errors == []


def test_the_scale_follows_every_zoom_of_the_game(wow: WowRuntime):
    boot(wow)
    our_style(wow)
    half = wow.eval("Minimap:GetWidth()") / 2
    for zoom, radius in RADII.items():
        wow.execute(f"Minimap:SetZoom({zoom})")
        wow.advance(0.05)
        level = wow.eval(f"{MINI}.Camera().level")
        assert level == pytest.approx(math.log2(half / radius * 32))
    assert wow.errors == []


def test_the_probe_leaves_the_ground_to_the_layer(wow: WowRuntime):
    """`/bprobe ground` was the layer's prototype; both switching the one ground would fight."""
    boot(wow)
    our_style(wow)
    wow.load_addon("Bastians_Probe")
    wow.fire("ADDON_LOADED", "Bastians_Probe")
    wow.slash("/bprobe ground")
    assert wow.eval("Mock.ground") is False and shown(wow) is True
    assert any("holds the ground" in line for line in wow.chat)
    assert wow.eval("BastiansProbeDB.results.ground") is None
    assert wow.errors == []
