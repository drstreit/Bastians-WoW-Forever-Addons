"""The WoW look ("the full WoW look is not working - hardly readable through
the transparency, not even close to WoW look ... I need a clearly skinned style according to
Blizzard examples"): the client's own PortraitFrameTemplate behind every window and its
InsetFrameTemplate behind the Browser's panes (marble on the dark scheme, our parchment on the
light one), the window opacity reaching those grounds; a new profile starts as a copy of this one;
a dropdown as wide as its longest choice."""

from harness import WowRuntime

S = "Bastians.UI.Style"
CORE = "Bastians:GetModule('Core')"
PROFILE = f"{CORE}.db.profile"
SET = "Bastians.UI.Settings"
GAME = "Mock.templates.PortraitFrameTemplate = true; Mock.templates.InsetFrameTemplate = true"


def boot(wow: WowRuntime, templates: bool = True, *addons: str) -> WowRuntime:
    if templates:
        wow.execute(GAME)
    wow.start(*(addons or ("Bastians_Core",)))
    wow.run_frames(5)
    return wow


def omnibox(wow: WowRuntime) -> str:
    wow.execute("Bastians.UI.Omnibox.Open()")
    return "Bastians.UI.Windows.BastiansOmniboxFrame"


def test_the_wow_preset_wears_the_games_own_window(wow: WowRuntime):
    boot(wow)
    win = omnibox(wow)
    assert wow.eval(f"{win}.chrome") is None  # Modern: no game window made
    assert wow.eval(f"{SET}.ApplyPreset({CORE}, 'wow')") is True
    p = wow.eval(PROFILE)
    assert p.gameFrames is True and p.theme == "blizzard" and p.gameButtons is True
    chrome = f"{win}.chrome"
    assert wow.eval(f"{chrome}:IsShown()") is True
    assert wow.eval(f"{chrome}.TitleText:GetText()") == "Search"  # the title in the game's bar
    assert wow.eval(f"{chrome}.portrait:GetTexture()") == "Interface\\AddOns\\Bastians_Core\\Icon"
    assert (
        wow.eval(f"{win}.title:IsShown()") is False and wow.eval(f"{win}.close:IsShown()") is False
    )
    assert wow.eval(f"{win}.frame.bg:IsShown()") is False  # the rock is the ground now
    assert tuple(wow.eval(f"{win}:Insets()")) == (56, 6, 6)
    point = wow.eval(f"{{ {win}.content:GetPoint(1) }}")
    assert point[5] == -56  # the content under the band beside the portrait
    # the game's red button closes our window
    wow.execute(f"{chrome}.CloseButton:GetScript('OnClick')({chrome}.CloseButton)")
    assert wow.eval(f"{win}.frame:IsShown()") is False
    # a title set later reaches the game's bar
    wow.execute(f"{win}:SetTitle('Elsewhere')")
    assert wow.eval(f"{chrome}.TitleText:GetText()") == "Elsewhere"
    # back to Modern: our own frame again
    wow.execute(f"{SET}.ApplyPreset({CORE}, 'modern-dark')")
    assert wow.eval(f"{chrome}:IsShown()") is False and wow.eval(f"{win}.title:IsShown()") is True
    assert wow.eval(f"{win}.frame.bg:IsShown()") is True
    assert wow.errors == []


def test_the_window_opacity_reaches_the_games_grounds(wow: WowRuntime):
    boot(wow)
    win = omnibox(wow)
    wow.execute(f"{SET}.ApplyPreset({CORE}, 'wow')")
    wow.execute(f"{PROFILE}.windowAlpha = 50; Bastians.UI.ApplyWindowLook()")
    alpha = wow.eval(f"{win}.chrome.Bg:GetAlpha()")
    assert abs(alpha - 0.5) < 0.01  # the slider moves the rock (it did nothing before)
    assert abs(wow.eval(f"{S}.insetAlpha") - 0.5) < 0.01
    assert wow.errors == []


def test_the_browsers_panes_sit_in_the_games_insets(wow: WowRuntime):
    wow.execute('function GetRealmName() return "Classic Beta PvE" end')
    boot(wow, True, "Bastians_Core", "Bastians_Data", "Bastians_Browser")
    wow.execute("Bastians:GetModule('Browser').Browser.OpenWindow()")
    wow.execute(f"{SET}.ApplyPreset({CORE}, 'wow')")
    nav = "Bastians:GetModule('Browser').listPane"  # the list tile (the navigation until ADR 0056)
    inset = f"{nav}.gameInset"
    assert wow.eval(f"{inset}:IsShown()") is True
    assert wow.eval(f"{inset}.Bg:GetTexture()") == "Interface\\FrameGeneral\\UI-Background-Marble"
    assert wow.eval(f"{nav}.bg:IsShown()") is False  # its own flat fill gives way
    # a light scheme under the game's frames: our parchment in the same insets, so brown ink reads
    wow.execute(
        f"{CORE}.db.profile.theme = 'parchment'; {S}.ApplyTheme('parchment'); {S}.ApplySkin()"
    )
    assert (
        wow.eval(f"{inset}.Bg:GetTexture()") == "Interface\\AddOns\\Bastians_Core\\Media\\Parchment"
    )
    wow.execute(f"{SET}.ApplyPreset({CORE}, 'modern-dark')")
    assert wow.eval(f"{inset}:IsShown()") is False and wow.eval(f"{nav}.bg:IsShown()") is True
    assert wow.errors == []


def test_without_the_templates_the_window_keeps_its_own_frame(wow: WowRuntime):
    boot(wow, False)
    win = omnibox(wow)
    wow.execute(f"{SET}.ApplyPreset({CORE}, 'wow')")
    assert wow.eval(f"{win}.chrome") is False  # asked once, the client has none
    assert wow.eval(f"{win}.title:IsShown()") is True
    assert wow.errors == []


def test_a_new_profile_starts_as_a_copy_of_this_one(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{SET}.ApplyPreset({CORE}, 'wow')")
    wow.execute("Bastians:SetProfile('Raid', true)")
    p = wow.eval(PROFILE)
    assert wow.eval("Bastians:GetProfile()") == "Raid"
    assert p.preset == "wow" and p.theme == "blizzard"  # not the defaults (Modern)
    wow.execute("Bastians:SetProfile('Fresh')")  # without the copy: the defaults, as before
    assert wow.eval(f"{PROFILE}.preset") in (None, "modern-dark")
    assert wow.errors == []


def test_a_dropdown_is_as_wide_as_its_longest_choice(wow: WowRuntime):
    boot(wow)
    wow.execute(
        """local parent = CreateFrame("Frame", nil, UIParent)
        SEL = Bastians.UI.Widgets.Select(parent, "Skin", { a = "Short",
          b = "Blizzard (the game's frames, gold and type)" })
        SHORT = Bastians.UI.Widgets.Select(parent, "X", { a = "One" })"""
    )
    wide = wow.eval("SEL.button:GetWidth()")
    assert wide > 160 and wow.eval("SEL.list:GetWidth()") == wide
    assert wow.eval("SHORT.button:GetWidth()") == 160  # never narrower than before
    assert wow.errors == []


def test_the_settings_always_wear_the_wow_look(wow: WowRuntime):
    """ "option fonts are not readable ... leave the menu out of the
    styling, it should always be the same - the WoW look"."""
    boot(wow)
    wow.execute(f"{SET}.ApplyPreset({CORE}, 'modern-light')")  # parchment and brown ink elsewhere
    wow.execute("Bastians.UI.Hub.Open()")
    hub = "Bastians.UI.Hub"
    gold = list(wow.eval(f"{S}.Palette('blizzard').C.text").values())
    brown = list(wow.eval(f"{S}.C.text").values())
    assert gold != brown
    label = wow.eval(f"{hub}.navButtons[3].label")  # an app's entry, not the chosen one
    assert list(label.GetTextColor(label))[:3] == gold[:3]  # the menu in the gold scheme's text
    assert wow.eval(f"{hub}.win.chrome:IsShown()") is True  # the game's frame, whatever the look
    assert wow.eval(f"{hub}.nav.gameInset.Bg:GetTexture()").endswith("UI-Background-Marble")
    # a theme change elsewhere leaves the settings as they are
    wow.execute(f"{SET}.ApplyPreset({CORE}, 'modern-light')")
    assert list(label.GetTextColor(label))[:3] == gold[:3]
    assert wow.eval(f"{hub}.win.chrome:IsShown()") is True
    assert wow.errors == []


def test_text_on_a_light_ground_has_no_shadow(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"""{SET}.ApplyPreset({CORE}, 'modern-dark')
        local f = CreateFrame("Frame", nil, UIParent)
        FS = {S}.text(f, 12)"""
    )
    assert list(wow.eval("{ FS:GetShadowOffset() }").values()) == [1, -1]
    wow.execute(f"{SET}.ApplyPreset({CORE}, 'modern-light')")  # brown ink on parchment
    assert list(wow.eval("{ FS:GetShadowOffset() }").values()) == [0, 0]
    assert wow.errors == []


def test_a_tree_survives_a_pruned_fold_table(wow: WowRuntime):
    """Retail 31.10.2026: after a profile switch Quests stopped on "attempt to index field
    'collapsed'": the switch pruned the empty table out of the old profile the tree still held."""
    boot(wow)
    wow.execute(
        """local parent = CreateFrame("Frame", nil, UIParent)
        DBT = {}
        T = Bastians.UI.Tree(parent, { db = DBT })
        T.scroll:SetSize(300, 200)
        DBT.collapsed = nil
        T:SetRows({ { id = "s", text = "Section", kind = "section", collapsed = true,
          children = { { text = "row" } } } })
        T:ToggleFold(T.flat[1])"""
    )
    assert wow.eval("type(DBT.collapsed)") == "table"
    assert wow.errors == []


def test_a_wide_game_button_keeps_its_caps(wow: WowRuntime):
    """the wide settings buttons looked strange, the game's button art
    stretched whole. It is three slices now: 12/22 of the height per cap, the middle stretches."""
    boot(wow)
    wow.execute(f"{SET}.ApplyPreset({CORE}, 'wow')")
    wow.execute(f"TestB = {S}.button(UIParent, 'Wide', 600, 22)")
    art = "TestB.gameArt"
    # the look sizes the button (ADR 0046: the WoW geometry, 24 px), the caps follow its height
    h = wow.eval("TestB:GetHeight()")
    assert h == 24
    assert wow.eval(f"{art}.up[1]:GetWidth()") == round(h * 12 / 22)
    assert wow.eval(f"{art}.up[3]:GetWidth()") == round(h * 12 / 22)
    assert wow.eval(f"{art}.up[1]:GetTexture()") == "Interface\\Buttons\\UI-Panel-Button-Up"
    coords = list(wow.eval(f"{{ {art}.up[2]:GetTexCoord() }}").values())
    assert coords[:2] == [0.09375, 0.53125]
    assert wow.eval(f"{art}.up[1]:IsShown()") is True
    assert wow.eval(f"{art}.down[1]:IsShown()") is False
    assert wow.eval("TestB:GetNormalTexture()") is None  # nothing stretched whole
    # pressed: the down art; released: the up art again
    wow.execute("TestB:GetScript('OnMouseDown')(TestB, 'LeftButton')")
    assert wow.eval(f"{art}.down[2]:IsShown()") is True
    assert wow.eval(f"{art}.up[2]:IsShown()") is False
    wow.execute("TestB:GetScript('OnMouseUp')(TestB, 'LeftButton')")
    assert wow.eval(f"{art}.up[2]:IsShown()") is True
    assert wow.eval(f"{art}.down[2]:IsShown()") is False
    # a narrow one: the caps never pass the middle
    wow.execute("TestB:SetSize(16, 22); TestB:GetScript('OnSizeChanged')(TestB, 16, 22)")
    assert wow.eval(f"{art}.up[1]:GetWidth()") == 8
    # back to Modern: our own face, no game art
    wow.execute(f"{SET}.ApplyPreset({CORE}, 'modern-dark')")
    assert wow.eval(f"{art}.up[2]:IsShown()") is False
    assert wow.eval("TestB.face:IsShown()") is True
    assert wow.errors == []
