"""Bastian's minimap: the game's minimap taken into
our frame with a search bar, the zone line and a tools row; the game's style by default, the map's
styles after a one-time warning; wheel, drag, Recentre, Alt+wheel; the indicators kept; the
button box with the hovered button's name in its title; everything given back when off."""

import sys
from pathlib import Path

from harness import WowRuntime

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools"))
from mapstyle.emit import style_lua

CORE, DATA, MAP = "Bastians_Core", "Bastians_Data", "Bastians_Map"
MOD = "Bastians:GetModule('Map')"
MINI = f"{MOD}.Mini"
MB = f"{MOD}.MiniButtons"
NEAR = {0: [(7, 11), (7, 12), (8, 11), (8, 12)]}
FAR = {0: [(3, 5), (3, 6), (4, 5), (4, 6)]}

# the game's cluster and an indicator as the retail family names them
GAME_FRAMES = """
MinimapCluster = CreateFrame("Frame", "MinimapCluster", UIParent)
MinimapCluster:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
GameTimeFrame = CreateFrame("Button", "GameTimeFrame", MinimapCluster)
GameTimeFrame:SetSize(40, 40)
GameTimeFrame:SetPoint("TOPRIGHT", MinimapCluster, "TOPRIGHT", -5, -5)
Minimap:SetParent(MinimapCluster)
Minimap:SetPoint("CENTER", MinimapCluster, "CENTER", 0, 0)
Minimap.ZoomIn = CreateFrame("Button", nil, Minimap)
"""


def boot(wow: WowRuntime, game_frames: bool = True) -> WowRuntime:
    wow.start(CORE, DATA, MAP)
    if game_frames:
        # the game's frames exist before the world is entered; the takeover runs there
        wow.execute(f"{MOD}.db.profile.miniMap = false; {MINI}.Apply()")
        wow.execute(GAME_FRAMES)
        wow.execute(f"{MOD}.db.profile.miniMap = true")
    wow.fire("PLAYER_ENTERING_WORLD")
    wow.run_frames(5)
    return wow


def pencil(wow: WowRuntime) -> None:
    wow.execute(style_lua("pencil", wow.client, "test", NEAR, FAR))
    wow.execute("Bastians.Deliver()")


def setting(wow: WowRuntime, key: str, value: str) -> None:
    wow.execute(
        f"{MOD}.db.profile.{key} = {value}; "
        f"Bastians:Fire('BASTIANS_SETTING_CHANGED', {MOD}.name, '{key}', {value})"
    )


def test_the_game_minimap_moves_into_ours_and_goes_back_when_off(wow: WowRuntime):
    boot(wow)
    assert wow.eval("BastiansMiniMap:IsShown()") is True
    assert wow.eval(f"Minimap:GetParent() == {MINI}.view") is True
    assert wow.eval(f"{MINI}.Style()") == "game"  # the game's live minimap by default
    assert (
        wow.eval(f"{MINI}.clip:IsShown()") is False
        and wow.eval(f"{MINI}.catcher:IsShown()") is True
    )
    # the cluster waits on a hidden frame, its indicator sits in the tools row
    assert wow.eval("MinimapCluster:GetParent() ~= UIParent") is True
    assert wow.eval(f"GameTimeFrame:GetParent() == {MINI}.tools") is True
    assert wow.eval(f"{MINI}.stats.indicators") == 1
    # the game's zoom button is parked, not just hidden (the game shows it again on hover)
    assert wow.eval("Minimap.ZoomIn:GetParent() ~= Minimap") is True
    # the pins of the map's layers stay on the game's minimap
    assert wow.eval(f"{MOD}.Minimap.Host()") is None
    # off: everything where it was
    setting(wow, "miniMap", "false")
    assert wow.eval("BastiansMiniMap:IsShown()") is False
    assert wow.eval("Minimap:GetParent() == MinimapCluster") is True
    assert wow.eval("MinimapCluster:GetParent() == UIParent") is True
    assert wow.eval("GameTimeFrame:GetParent() == MinimapCluster") is True
    assert wow.eval("Minimap.ZoomIn:GetParent() == Minimap") is True
    point = wow.eval("{ GameTimeFrame:GetPoint(1) }")
    assert (point[1], point[3], point[4], point[5]) == ("TOPRIGHT", "TOPRIGHT", -5, -5)
    assert wow.errors == []


def test_a_failing_world_handler_does_not_keep_the_game_minimap(wow: WowRuntime):
    """after every reload the game's minimap showed although ours was
    on; switching the option off and on brought ours. A handler before Mini's on
    PLAYER_ENTERING_WORLD failed (a secret value in the player facts), and the rest of the list was
    skipped. Every handler runs now; the first error still reaches Core's guard."""
    wow.start(CORE, DATA, MAP)
    wow.execute(f"{MOD}.db.profile.miniMap = false; {MINI}.Apply()")
    wow.execute(GAME_FRAMES)
    wow.execute(f"{MOD}.db.profile.miniMap = true")
    wow.execute(f"table.insert({MOD}.Map.onWorld, 1, function() error('a broken handler') end)")
    wow.fire("PLAYER_ENTERING_WORLD")
    wow.run_frames(5)
    assert wow.eval(f"Minimap:GetParent() == {MINI}.view") is True
    errors = [x.text for x in wow.eval("Bastians:GetLog()").values() if x.level == "error"]
    assert any("a broken handler" in e for e in errors)


def test_nothing_moves_in_combat(wow: WowRuntime):
    """CLAUDE.md golden rule 6: the takeover and the give-back wait for the end of combat."""
    boot(wow)
    wow.execute("Mock.combat = true")
    setting(wow, "miniMap", "false")
    assert wow.eval(f"Minimap:GetParent() == {MINI}.view") is True
    wow.execute("Mock.combat = false")
    wow.fire("PLAYER_REGEN_ENABLED")
    assert wow.eval("Minimap:GetParent() == MinimapCluster") is True
    assert wow.errors == []


def test_our_styles_warn_once_then_draw_with_the_pins_on_our_view(wow: WowRuntime):
    boot(wow)
    pencil(wow)
    wow.execute(f"{MINI}.SetStyle('pencil')")
    # the warning first: what only the game's minimap shows
    assert wow.eval("BastiansMiniWarning:IsShown()") is True
    assert wow.eval(f"{MINI}.Style()") == "game"
    wow.execute(f"{MINI}.Warning().ok:Click()")
    assert wow.eval(f"{MINI}.Style()") == "pencil"
    assert wow.eval(f"{MOD}.db.profile.miniWarned") is True
    # our renderer draws the far cells on the clip, round by default; the overlay moves onto it
    wow.execute(f"{MINI}.Render()")
    assert (
        wow.eval(f"{MINI}.clip:IsShown()") is True
        and wow.eval(f"{MINI}.catcher:IsShown()") is False
    )
    live = list(wow.eval(f"{MINI}.layers.far.live").values())
    on_clip = f"(function() for _, t in pairs({MINI}.layers.far.live) do if t:GetParent() ~= {MINI}.clip then return false end end return true end)()"
    assert live and wow.eval(on_clip) is True
    assert all("Map_Pencil" in t.GetTexture(t) for t in live)
    masked = f"(function() for _, t in pairs({MINI}.layers.far.live) do if not (t.masks and t.masks[1] == {MINI}.clip.mask) then return false end end return true end)()"
    assert wow.eval(masked) is True
    assert wow.eval(f"{MOD}.Minimap.Host() == {MINI}.host") is True
    # square: the mask goes, the game's minimap is squared too
    setting(wow, "miniShape", "'SQUARE'")
    assert all(not list((t.masks or {}).values()) for t in live)
    # a second switch asks no more; back to the game's minimap, the overlay goes back too
    wow.execute(f"{MINI}.SetStyle('game'); {MINI}.SetStyle('pencil'); {MINI}.SetStyle('game')")
    assert wow.eval(f"{MINI}.Style()") == "game"
    assert wow.eval(f"{MOD}.Minimap.Host()") is None
    assert wow.eval(f"next({MINI}.layers.far.live)") is None
    assert wow.errors == []


def test_the_settings_page_asks_first_too(wow: WowRuntime):
    boot(wow)
    setting(wow, "miniStyle", "'physical'")
    assert wow.eval("BastiansMiniWarning:IsShown()") is True
    assert wow.eval(f"{MINI}.Style()") == "game"
    wow.execute(f"{MINI}.Warning().ok:Click()")
    assert wow.eval(f"{MINI}.Style()") == "physical"
    assert wow.errors == []


def test_wheel_drag_recentre_and_alt_wheel(wow: WowRuntime):
    boot(wow)
    # the game's style: the wheel zooms the game's minimap
    wow.execute("Mock.minimapZoom = 1")
    wow.execute(f"{MINI}.catcher:GetScript('OnMouseWheel')({MINI}.catcher, 1)")
    assert wow.eval("Minimap:GetZoom()") == 2
    # our style: Shift + wheel zooms our camera by half a level at the centre
    wow.execute(f"{MOD}.db.profile.miniWarned = true; {MINI}.SetStyle('physical')")
    level = wow.eval(f"{MINI}.Camera().level")
    wow.execute(f"Mock.shift = true; {MINI}.clip:GetScript('OnMouseWheel')({MINI}.clip, 1)")
    wow.execute("Mock.shift = false")
    assert wow.eval(f"{MINI}.Camera().level") == level + 0.5
    assert wow.eval(f"{MOD}.db.profile.miniLevel") == level + 0.5
    assert wow.eval(f"{MINI}.Following()") is True
    # Alt+wheel: the frame grows by a step
    wow.execute(
        f"Mock.alt = true; {MINI}.clip:GetScript('OnMouseWheel')({MINI}.clip, 1); Mock.alt = false"
    )
    assert wow.eval(f"{MINI}.Size()") == 210
    assert wow.eval(f"{MINI}.view:GetWidth()") == 210
    # a drag pans away from the player and lets go; Recentre comes back
    cam = wow.eval(f"{MINI}.Camera()")
    wx, wy = cam.wx, cam.wy
    wow.execute("Mock.cursorX, Mock.cursorY = 500, 500")
    wow.execute(f"{MINI}.clip:GetScript('OnMouseDown')({MINI}.clip, 'LeftButton')")
    wow.execute("Mock.cursorX = 540")
    wow.run_frames(2)
    wow.execute(f"{MINI}.clip:GetScript('OnMouseUp')({MINI}.clip, 'LeftButton')")
    wow.run_frames(2)
    cam = wow.eval(f"{MINI}.Camera()")
    assert wow.eval(f"{MINI}.Following()") is False and (cam.wx, cam.wy) != (wx, wy)
    assert wow.eval("BastiansMiniMap:GetScript('OnUpdate')") is None  # nothing ticks when still
    wow.execute(f"{MINI}.Recentre()")
    cam = wow.eval(f"{MINI}.Camera()")
    assert wow.eval(f"{MINI}.Following()") is True and (cam.wx, cam.wy) == (wx, wy)
    assert wow.errors == []


def test_the_search_jumps_the_minimap_and_recentre_comes_back(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f"{MINI}.search.box:GetParent() == {MINI}.bar") is True
    wow.execute(f"{MOD}.db.profile.miniWarned = true; {MINI}.SetStyle('physical')")
    places = list(wow.eval("Bastians:Entity('npc:448'):Places()").values())
    assert wow.eval(f"{MINI}.JumpTo('npc:448')") is True
    cam = wow.eval(f"{MINI}.Camera()")
    # one of its places, the nearest to where the view was
    assert (cam.continent, cam.wx, cam.wy) in [(p.map, p.wx, p.wy) for p in places]
    assert wow.eval(f"{MINI}.Following()") is False
    # the game's style cannot look elsewhere: the big map shows the place
    wow.execute(f"{MINI}.SetStyle('game'); {MINI}.JumpTo('npc:448')")
    assert wow.eval("BastiansMapFrame and BastiansMapFrame:IsShown()") is True
    assert wow.errors == []


def test_the_button_box_takes_the_buttons_and_names_the_hovered_one(wow: WowRuntime):
    boot(wow)
    wow.execute(
        """B1 = CreateFrame("Button", "LibDBIcon10_BugSack", Minimap)
        B1:SetSize(31, 31); B1:SetPoint("CENTER", Minimap, "CENTER", 50, 50)
        -- LibDBIcon 57 (BugSack's): MEDIUM and level 8, both fixed
        B1:SetFrameStrata("MEDIUM"); B1:SetFixedFrameStrata(true)
        B1:SetFrameLevel(8); B1:SetFixedFrameLevel(true)
        B2 = CreateFrame("Button", "WeakAurasMinimapButton", Minimap)
        B2:SetSize(31, 31)
        Z = CreateFrame("Button", "MinimapZoomIn", Minimap)"""
    )
    opener = "BastiansMiniMap.boxButton"
    wow.execute(f"{opener}:GetScript('OnEnter')({opener})")  # the mouse on it: no click
    win = f"{MB}.Window()"
    assert wow.eval(f"{win}:IsShown()") is True
    names = [e.name for e in wow.eval(f"{MB}.collected").values()]
    # the others and our apps' buttons; the suite's own is the badge, the game's zoom stays out
    # since 30.10.2026 the options window has a button too
    assert names == ["Bastian's Map", "Bastian's Options", "Bug Sack", "Weak Auras"]
    assert wow.eval(f"B1:GetParent() == {win}.grid") is True  # the grid scrolls (30.10.2026)
    # in the box on the window's layer, not under it
    assert wow.eval("B1:GetFrameStrata()") == wow.eval(f"{win}.frame:GetFrameStrata()")
    assert wow.eval(f"B1:GetFrameLevel() > {win}.content:GetFrameLevel()") is True
    # hovering shows the name in the title bar, leaving gives the box's title back
    wow.execute("B1:GetScript('OnEnter')(B1)")
    assert wow.eval(f"{win}.title:GetText()") == "Bug Sack"
    wow.execute("B1:GetScript('OnLeave')(B1)")
    assert wow.eval(f"{win}.title:GetText()") == "Minimap buttons"
    # off: the buttons go back where they were
    setting(wow, "miniButtonBox", "false")
    assert wow.eval("B1:GetParent() == Minimap") is True
    point = wow.eval("{ B1:GetPoint(1) }")
    assert (point[1], point[3], point[4], point[5]) == ("CENTER", "CENTER", 50, 50)
    assert wow.eval("B1:GetFrameStrata()") == "MEDIUM" and wow.eval("B1:GetFrameLevel()") == 8
    assert (
        wow.eval("B1:HasFixedFrameStrata()") is True and wow.eval("B1:HasFixedFrameLevel()") is True
    )
    assert wow.eval("BastiansMiniMap.boxButton:IsShown()") is False
    assert wow.errors == []


def test_pretty_names(wow: WowRuntime):
    boot(wow, game_frames=False)
    assert wow.eval(f"{MB}.Pretty('LibDBIcon10_BugSack')") == "Bug Sack"
    assert wow.eval(f"{MB}.Pretty('BastiansMinimapButtonQuests')") == "Bastian's Quests"
    assert wow.eval(f"{MB}.Pretty('Details_MinimapButton')") == "Details"


def test_the_info_sign_explains_both_ways_with_pros_and_cons(wow: WowRuntime):
    """an info sign on the minimap explaining the game's minimap and our styles,
    with what each gives and takes; it shows at once on hover."""
    boot(wow)
    info = f"{MINI}.tools.info"
    assert wow.eval(f"{info}:IsShown()") is True
    wow.execute(f"{info}:GetScript('OnEnter')({info})")
    assert wow.eval("GameTooltip:IsShown()") is True
    lines = [line.left for line in wow.eval("GameTooltip.lines").values()]
    assert "Two ways to use the minimap" in lines and "Now: Game minimap" in lines
    assert "Game minimap (the default)" in lines
    assert any(text.startswith("Bastian's styles") for text in lines)
    pros = [text for text in lines if text.startswith("+ ")]
    cons = [text for text in lines if text.startswith("- ")]
    assert len(pros) >= 4 and len(cons) == 2
    wow.execute(f"{info}:GetScript('OnLeave')({info})")
    assert wow.eval("GameTooltip:IsShown()") is False
    assert wow.errors == []


def test_the_game_minimap_takes_our_size_and_stays_in_our_view(wow: WowRuntime):
    """Alt+wheel in the game style only shifted the map, and an old
    larger minimap showed beside the view in our styles. The game's minimap gets the view's centre
    and size; the game moving it back is undone on the next frame."""
    boot(wow)
    assert wow.eval("Minimap:GetWidth()") == 200
    point = wow.eval("{ Minimap:GetPoint(1) }")
    assert (point[1], point[3]) == ("CENTER", "CENTER")
    assert wow.eval(f"select(2, Minimap:GetPoint(1)) == {MINI}.view") is True
    wow.execute(f"Mock.alt = true; {MINI}.catcher:GetScript('OnMouseWheel')({MINI}.catcher, 2)")
    wow.execute("Mock.alt = false")
    assert wow.eval("Minimap:GetWidth()") == 220 and wow.eval(f"{MINI}.view:GetWidth()") == 220
    # the game puts its minimap back in its cluster: ours again on the next frame
    wow.execute(
        "Minimap:ClearAllPoints(); Minimap:SetPoint('CENTER', MinimapCluster, 'CENTER', 0, 0)"
    )
    wow.advance(0.05)  # the next frame's timer
    assert wow.eval(f"select(2, Minimap:GetPoint(1)) == {MINI}.view") is True
    # Alt+drag on the game's minimap moves our frame
    wow.execute("Mock.alt = true; Minimap:GetScript('OnMouseDown')(Minimap, 'LeftButton')")
    assert wow.eval("BastiansMiniMap.moving") is True
    wow.execute("Minimap:GetScript('OnMouseUp')(Minimap, 'LeftButton'); Mock.alt = false")
    assert wow.eval("BastiansMiniMap.moving") is None
    assert wow.eval(f"{MOD}.db.profile.miniPos") is not None
    assert wow.errors == []


def test_no_blizzard_style_and_no_tracking_on_the_minimap(wow: WowRuntime):
    """ "Game minimap" beside "Blizzard" confused, and Blizzard's
    paintings show no detail at a minimap's zoom; the game's tracking is replaced by the map's
    layers, which show the travel and service places on every style now."""
    boot(wow)
    assert "blizzard" not in list(wow.eval(f"{MINI}.StyleList()").values())
    assert wow.eval(f"{MINI}.Style()") == "game"
    paths = [list(p.values()) for p in wow.eval(f"{MINI}.INDICATORS").values()]
    assert ["MinimapCluster", "Tracking"] not in paths and ["MiniMapTracking"] not in paths
    assert ["MiniMapTracking"] in [list(p.values()) for p in wow.eval(f"{MINI}.HIDE").values()]
    assert wow.errors == []


def test_a_frame_around_the_minimap_round_or_square_and_switched_off(wow: WowRuntime):
    """ "it looks strange without a frame"."""
    boot(wow)
    ring = f"{MINI}.view.ring"
    assert wow.eval(f"{ring}:IsShown()") is True
    # round: two discs cut by the round mask, smooth at any size (the corner pieces looked like
    # pixel art scaled to a whole circle, )
    assert wow.eval(f"{ring}.rim:IsShown()") is True and wow.eval(f"{ring}.band:IsShown()") is True
    assert wow.eval(f"{ring}.rim.masks[1] == {ring}.rimMask") is True
    assert wow.eval(f"{ring}.bg:IsShown()") is False
    setting(wow, "miniShape", "'SQUARE'")
    assert wow.eval(f"{ring}.rim:IsShown()") is False and wow.eval(f"{ring}.bg:IsShown()") is True
    assert wow.eval(f"{ring}.bg.radius") == "radiusSmall"
    setting(wow, "miniBorder", "false")
    assert wow.eval(f"{ring}:IsShown()") is False
    assert wow.errors == []


def test_the_wheel_zooms_at_the_cursor(wow: WowRuntime):
    """ "zoom exactly where my cursor is", Shift + wheel at the centre.
    The world point under the cursor stays under it; the view lets go of the player."""
    boot(wow)
    wow.execute(f"{MOD}.db.profile.miniWarned = true; {MINI}.SetStyle('physical')")
    top = wow.eval(f"{MINI}.clip:GetTop()")
    wow.execute(
        f"Mock.cursorX, Mock.cursorY = 50, {top} - 50"
    )  # 50 px right of and below the corner
    before = wow.eval(f"{{ {MINI}.Camera():ToWorld(50, 50) }}")
    wow.execute(f"{MINI}.clip:GetScript('OnMouseWheel')({MINI}.clip, 1)")
    after = wow.eval(f"{{ {MINI}.Camera():ToWorld(50, 50) }}")
    assert (round(after[1], 6), round(after[2], 6)) == (round(before[1], 6), round(before[2], 6))
    assert wow.eval(f"{MINI}.Following()") is False
    assert wow.errors == []


def test_right_click_on_the_minimap_ground_opens_the_place_menu(wow: WowRuntime):
    """nothing on right click; Route here, Note here, ... as on the big
    map, on our styles and on the game's minimap."""
    boot(wow)
    wow.execute(
        f"""M = nil
        {MOD}.Waypoints.PointMenu = function(c, wx, wy, source) M = {{ c, wx, wy, source }} return true end"""
    )
    # the game's minimap: the player's place plus the cursor's offset at the minimap's scale
    wow.execute("Minimap:GetScript('OnMouseUp')(Minimap, 'RightButton')")
    menu = wow.eval("M")
    assert menu is not None and menu[4] == "minimap" and menu[1] == 0
    # our styles: the camera's point under the cursor
    wow.execute(f"M = nil; {MOD}.db.profile.miniWarned = true; {MINI}.SetStyle('physical')")
    top = wow.eval(f"{MINI}.clip:GetTop()")
    wow.execute(f"Mock.cursorX, Mock.cursorY = 30, {top} - 40")
    wow.execute(f"{MINI}.clip:GetScript('OnMouseUp')({MINI}.clip, 'RightButton')")
    menu = wow.eval("M")
    expected = wow.eval(f"{{ {MINI}.Camera():ToWorld(30, 40) }}")
    assert (menu[2], menu[3]) == (expected[1], expected[2])
    assert wow.errors == []


def test_one_badge_an_options_button_and_a_centred_row(wow: WowRuntime):
    """the suite's one button on the minimap as a Bastian's badge, the
    options one click away, no addon counter, the row under the map centred."""
    boot(wow)
    badge = "BastiansMiniMap.badge"
    assert wow.eval(f"{badge}:IsShown()") is True
    assert wow.eval(f"{badge}.icon:GetTexture()").endswith("Bastians_Core" + chr(92) + "Icon")
    wow.execute("Bastians.UI.Launcher.OnClick = function(self, b) CLICKED = b end")
    wow.execute(f"{badge}:GetScript('OnClick')({badge}, 'RightButton')")
    assert wow.eval("CLICKED") == "RightButton"
    assert ["AddonCompartmentFrame"] in [
        list(p.values()) for p in wow.eval(f"{MINI}.HIDE").values()
    ]
    # the options button opens the minimap's own page of the Map's settings
    wow.execute(
        "Bastians.UI.Hub = { Open = function(name, page) OPENED = name .. ':' .. page end }"
    )
    wow.execute(f"{MINI}.tools.options:Click()")
    assert wow.eval("OPENED") == "Map:minimap"
    # the row starts left of the middle by half its width
    point = wow.eval(f"{{ {MINI}.tools.style:GetPoint(1) }}")
    assert (point[1], point[3]) == ("LEFT", "CENTER") and point[4] < 0
    assert wow.errors == []


def test_ctrl_click_moves_a_button_between_the_box_and_the_map(wow: WowRuntime):
    """a button taken out of the box could not go back; Ctrl+click puts
    it on the map (where its addon lets it be dragged) or back into the box, remembered. Any other
    click is the button's own. The box closes once the mouse left it and its button."""
    boot(wow)
    wow.execute(
        """B1 = CreateFrame("Button", "LibDBIcon10_BugSack", Minimap)
        B1:SetSize(31, 31); B1:SetPoint("CENTER", Minimap, "CENTER", 50, 50)
        B1:SetScript("OnClick", function() OWN = (OWN or 0) + 1 end)"""
    )
    opener = "BastiansMiniMap.boxButton"
    wow.execute(f"{opener}:GetScript('OnEnter')({opener})")
    win = f"{MB}.Window()"
    assert wow.eval(f"B1:GetParent() == {win}.grid") is True
    wow.execute("B1:Click()")
    assert wow.eval("OWN") == 1  # its own click
    wow.execute("Mock.ctrl = true; B1:Click(); Mock.ctrl = false")
    assert wow.eval("OWN") == 1
    assert wow.eval("B1:GetParent() == BastiansMiniMap") is True  # on the rim of ours
    assert wow.eval(f"{MOD}.db.profile.buttonHomes.LibDBIcon10_BugSack") == "map"
    wow.execute("Mock.ctrl = true; B1:Click(); Mock.ctrl = false")
    assert wow.eval(f"B1:GetParent() == {win}.grid") is True
    assert wow.eval(f"{MOD}.db.profile.buttonHomes.LibDBIcon10_BugSack") is None
    # the mouse away from the box and its button: the box goes after a moment
    wow.execute(f"{win}.frame.IsMouseOver = function() return false end")
    wow.execute(f"{opener}.IsMouseOver = function() return false end")
    wow.run_frames(40)
    assert wow.eval(f"{win}:IsShown()") is False
    assert wow.errors == []


def rim_point(wow: WowRuntime, name: str) -> tuple:
    """A button's anchor on the rim: point, whether relative to the view, x, y (rounded)."""
    p = wow.eval(
        f"(function() local p, rel, rp, x, y = {name}:GetPoint(1); "
        f"return {{ p, rel == {MINI}.View(), x, y }} end)()"
    ).values()
    p = list(p)
    return p[0], p[1], round(p[2]), round(p[3])


def test_a_button_put_on_the_map_sits_on_the_rim_of_ours_also_after_a_reload(wow: WowRuntime):
    """a button Ctrl+clicked out of the box was gone, a reload did not
    bring it back: its old place was the game's minimap cluster, which waits hidden while ours
    shows. On the map is the rim of Bastian's minimap; the buttons take their places in turn."""
    boot(wow)
    wow.execute(
        """B1 = CreateFrame("Button", "AlphaAddonMinimapButton", MinimapCluster)
        B1:SetSize(31, 31); B1:SetPoint("TOPLEFT", MinimapCluster, "TOPLEFT", 10, -10)
        B2 = CreateFrame("Button", "BetaAddonMinimapButton", MinimapCluster)
        B2:SetSize(31, 31); B2:SetPoint("TOPLEFT", MinimapCluster, "TOPLEFT", 40, -10)"""
    )
    opener = "BastiansMiniMap.boxButton"
    wow.execute(f"{opener}:GetScript('OnEnter')({opener})")
    wow.execute("Mock.ctrl = true; B1:Click(); B2:Click(); Mock.ctrl = false")
    for b in ("B1", "B2"):
        assert wow.eval(f"{b}:GetParent() == BastiansMiniMap and {b}:IsVisible()") is True, b
    r = wow.eval(f"{MB}.RimRadius()")
    assert r == wow.eval(f"{MINI}.Size() / 2 + {MINI}.BORDER - 1")  # the accent rim's middle
    # the first place is top left (135 degrees), the next one 25 degrees further on
    p, rel, x, y = rim_point(wow, "B1")
    # the offsets count in the button's scale (31 px high, shrunk to the box's 28): on the ring
    k = 28 / 31
    assert (p, rel) == ("CENTER", True) and (x, y) == (
        round(-r * 0.7071 / k),
        round(r * 0.7071 / k),
    )
    assert rim_point(wow, "B2")[2:] != (x, y)
    # above the view's layers, which cover its whole square (in game they hid the buttons)
    assert wow.eval(f"B1:GetFrameLevel() >= {MINI}.View():GetFrameLevel() + 20") is True
    # an addon putting it back on the game's minimap: the rim takes it back on the next frame
    wow.execute('B1:SetPoint("CENTER", Minimap, "CENTER", 0, 0)')
    wow.run_frames(2)
    assert rim_point(wow, "B1")[:2] == ("CENTER", True)
    # after a reload the remembered home puts it on the rim again
    homes = wow.eval(f"{MOD}.db.profile.buttonHomes")
    assert homes.AlphaAddonMinimapButton == "map" and homes.BetaAddonMinimapButton == "map"
    wow.execute(f"{MB}.Release()")
    assert wow.eval("B1:GetParent() == MinimapCluster") is True  # the box off: its own place
    wow.execute(f"{MB}.Collect()")
    assert wow.eval("B1:GetParent() == BastiansMiniMap and B1:IsVisible()") is True
    # a square minimap: on the square's edge
    setting(wow, "miniShape", "'SQUARE'")
    assert rim_point(wow, "B1")[2:] == (round(-r / k), round(r / k))
    # the settings page puts every button back into the box
    wow.execute(f"{MB}.AllIntoBox()")
    win = f"{MB}.Window()"
    assert wow.eval(f"B1:GetParent() == {win}.grid and B2:GetParent() == {win}.grid") is True
    assert wow.eval(f"{MOD}.db.profile.buttonHomes") is None
    assert wow.errors == []


def test_a_boxed_button_its_addon_moves_back_returns_to_the_box(wow: WowRuntime):
    """no other addon's button showed in the box. LibDBIcon puts its
    buttons back on the minimap on its own; the box takes them back. A button some addon put on the
    game's minimap cluster (which waits hidden) is found too."""
    boot(wow)
    wow.execute(
        """B1 = CreateFrame("Button", "LibDBIcon10_BugSack", Minimap)
        B1:SetSize(31, 31)
        B2 = CreateFrame("Button", "SomeAddonClusterButton", MinimapCluster)
        B2:SetSize(31, 31)"""
    )
    opener = "BastiansMiniMap.boxButton"
    wow.execute(f"{opener}:GetScript('OnEnter')({opener})")
    win = f"{MB}.Window()"
    assert wow.eval(f"B2:GetParent() == {win}.grid") is True
    # LibDBIcon's updatePosition: the button back around the minimap
    wow.execute("B1:ClearAllPoints(); B1:SetPoint('CENTER', Minimap, 'CENTER', 80, 0)")
    wow.advance(0.05)
    assert wow.eval(f"select(2, B1:GetPoint(1)) == {win}.grid") is True
    assert wow.errors == []


def test_the_minimap_has_its_own_page_in_the_options(wow: WowRuntime):
    """the minimap's options on a page of their own (core-contracts §8
    `pages`): a category after the Map in the game's options and an entry in the hub, its options
    only, written to the Map's settings as before."""
    boot(wow)
    root = wow.eval("Mock.settingsCategories")[1]
    names = [c.name for c in root.children.values()]
    assert names.index("Minimap") == names.index("Map") + 1
    wow.execute("Bastians.UI.Settings.Panels()['Map:minimap'].canvas:Show()")
    texts = [
        w.label.GetText(w.label)
        for w in wow.eval("Bastians.UI.Settings.Panels()['Map:minimap'].canvas.widgets").values()
        if w.label is not None
    ]
    assert texts[0].startswith("Bastian's minimap in place of the game's")
    assert "Map style" not in texts and "Enabled" not in texts
    # the hub: an entry of its own, opened from the minimap's options button
    wow.execute(f"{MINI}.tools.options:Click()")
    hub = "Bastians.UI.Hub"
    assert wow.eval(f"{hub}.current.page.id") == "minimap"
    nav = [b.label.GetText(b.label) for b in wow.eval(f"{hub}.nav:GetChildren()") if b.IsShown(b)]
    assert "Minimap" in nav and "Map" in nav
    # its switch writes the Map's setting and gives the game's minimap back
    wow.execute(f"{hub}.canvas.widgets[1]:Click()")
    assert wow.eval(f"{MOD}.db.profile.miniMap") is False
    assert wow.eval("Minimap:GetParent() == MinimapCluster") is True
    assert wow.errors == []


def test_walking_recentres_and_the_arrow_sits_above_the_pins(wow: WowRuntime):
    """ "the minimap does not center around my position". A zoom at the
    cursor had let go of the player and the pins in Goldshire covered the arrow. Walking brings the
    view back; the arrow is drawn on a frame above the overlay's pins."""
    boot(wow)
    wow.execute(f"{MOD}.db.profile.miniWarned = true; {MINI}.SetStyle('physical')")
    wow.execute(f"{MINI}.Zoom(1)")  # the mock's cursor is off the centre: a zoom at the cursor
    assert wow.eval(f"{MINI}.Following()") is False
    wow.fire("PLAYER_STARTED_MOVING")
    wow.run_frames(2)
    assert wow.eval(f"{MINI}.Following()") is True
    wow.fire("PLAYER_STOPPED_MOVING")
    wow.run_frames(2)
    assert wow.eval(f"{MINI}.arrow:GetParent() == {MINI}.arrowLayer") is True
    assert (
        wow.eval(f"{MINI}.arrowLayer:GetFrameLevel() > BastiansMinimapOverlay:GetFrameLevel() + 1")
        is True
    )
    assert wow.errors == []


def test_the_button_box_scales_with_its_width_and_scrolls_past_six_rows(wow: WowRuntime):
    """ "there are people with 50 addons, make sure that scales": the columns
    follow the window's width, the window grows to six rows, more rows scroll; the title never
    wraps."""
    boot(wow)
    wow.execute(
        """for i = 1, 50 do
          local b = CreateFrame("Button", "LibDBIcon10_Addon" .. i, Minimap)
          b:SetSize(31, 31)
        end"""
    )
    opener = "BastiansMiniMap.boxButton"
    wow.execute(f"{opener}:GetScript('OnEnter')({opener})")
    win = f"{MB}.Window()"
    assert wow.eval(f"{win}:IsShown()") is True
    assert len(list(wow.eval(f"{MB}.collected").values())) >= 50
    assert wow.eval(f"{MB}.cols") == 9 and wow.eval(f"{MB}.rows") == 6
    cell = wow.eval(f"{MB}.SIZE + {MB}.GAP")
    assert wow.eval(f"{win}.grid:GetHeight()") == 4 + 6 * cell
    # the window holds six rows: the header, the frame's inset, the filter, the grid, the hint
    inset = 9 if wow.eval(f"{win}.framed") else 1
    assert wow.eval(f"{win}.frame:GetHeight()") == 30 + 2 * inset + 26 + 4 + 6 * cell + 16 + 4
    # narrower: fewer columns, more rows, the window stays at six rows and the rest scrolls
    wow.execute(f"{win}.frame:SetWidth(150); {MB}.Layout()")
    assert wow.eval(f"{MB}.cols") == 4 and wow.eval(f"{MB}.rows") == 13
    assert wow.eval(f"{win}.grid:GetHeight()") == 4 + 13 * cell
    assert wow.eval(f"{win}.frame:GetHeight()") == 30 + 2 * inset + 26 + 4 + 6 * cell + 16 + 4
    assert wow.eval(f"{win}.bar ~= nil") is True
    assert wow.eval(f"{win}.title.wordWrap") is False
    assert wow.errors == []


def test_a_rim_button_keeps_the_angle_it_was_dragged_to(wow: WowRuntime):
    """ "you can drag them, but they lasso back to the original point":
    a button on the rim takes our drag, its angle is kept per button and survives a reload."""
    boot(wow)
    wow.execute(
        """B1 = CreateFrame("Button", "AlphaAddonMinimapButton", MinimapCluster)
        B1:SetSize(31, 31); B1:SetPoint("TOPLEFT", MinimapCluster, "TOPLEFT", 10, -10)
        B1.ownDrags = 0
        B1:SetScript("OnDragStart", function(self) self.ownDrags = self.ownDrags + 1 end)"""
    )
    opener = "BastiansMiniMap.boxButton"
    wow.execute(f"{opener}:GetScript('OnEnter')({opener})")
    wow.execute("Mock.ctrl = true; B1:Click(); Mock.ctrl = false")
    assert wow.eval("B1:GetParent() == BastiansMiniMap") is True
    r = wow.eval(f"{MB}.RimRadius()")
    k = 28 / 31
    # a drag to the right of the view's centre: angle 0, on the rim's right
    wow.execute(
        f"""local view = {MINI}.View()
        local vx, vy = view:GetCenter()
        local s = view:GetEffectiveScale()
        Mock.cursorX, Mock.cursorY = (vx + 100) * s, vy * s
        B1:GetScript("OnDragStart")(B1)
        B1:GetScript("OnUpdate")(B1, 0.05)
        B1:GetScript("OnDragStop")(B1)"""
    )
    assert wow.eval("B1.ownDrags") == 0  # the button's own drag stays out while on the rim
    assert round(wow.eval(f"{MOD}.db.profile.buttonAngles.AlphaAddonMinimapButton")) == 0
    assert rim_point(wow, "B1")[2:] == (round(r / k), 0)
    # an addon putting it back is undone to the dragged place, not the default slot
    wow.execute('B1:SetPoint("CENTER", Minimap, "CENTER", 0, 0)')
    wow.run_frames(2)
    assert rim_point(wow, "B1")[2:] == (round(r / k), 0)
    # the angle survives a reload; into the box, the button's own drag is back
    fresh = wow.reload()
    fresh.execute(f"{opener}:GetScript('OnEnter')({opener})")
    assert fresh.eval(f"{MOD}.db.profile.buttonAngles.AlphaAddonMinimapButton") == 0
    fresh.execute(f"{MB}.AllIntoBox()")
    assert fresh.eval(f"{MOD}.db.profile.buttonAngles") is None
    assert fresh.errors == []


def test_the_button_box_filters_by_name_as_you_type(wow: WowRuntime):
    """ "a real time text filter on top of the minimap button window"."""
    boot(wow)
    wow.execute(
        """for i = 1, 30 do
          local b = CreateFrame("Button", "LibDBIcon10_Addon" .. i, Minimap)
          b:SetSize(31, 31)
        end
        local b = CreateFrame("Button", "LibDBIcon10_BugSack", Minimap)
        b:SetSize(31, 31)"""
    )
    opener = "BastiansMiniMap.boxButton"
    wow.execute(f"{opener}:GetScript('OnEnter')({opener})")
    win = f"{MB}.Window()"
    assert wow.eval(f"{MB}.rows") == 4  # 31 buttons in 9 columns
    wow.execute(
        f"{win}.filter:SetText('bug'); {win}.filter:GetScript('OnTextChanged')({win}.filter)"
    )
    assert wow.eval(f"{MB}.rows") == 1
    assert wow.eval("LibDBIcon10_BugSack:IsShown()") is True
    assert wow.eval("LibDBIcon10_Addon7:IsShown()") is False
    wow.execute(
        f"{win}.filter:SetText('addon1'); {win}.filter:GetScript('OnTextChanged')({win}.filter)"
    )
    assert wow.eval(f"{MB}.rows") == 2  # Addon1 and Addon10 to Addon19
    wow.execute(f"{win}.filter:SetText(''); {win}.filter:GetScript('OnTextChanged')({win}.filter)")
    assert wow.eval(f"{MB}.rows") == 4 and wow.eval("LibDBIcon10_Addon7:IsShown()") is True
    assert wow.errors == []
