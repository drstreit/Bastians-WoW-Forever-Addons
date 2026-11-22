"""The game's frame (ADR 0040; ADR 0084 decision 4, 20.11.2026: the optional border around the one
look, on by default): the client's own PortraitFrameTemplate around every window, the window
opacity reaching its ground; ~~the WoW look's InsetFrameTemplate behind the Browser's panes and the
game's red buttons~~ (until 20.11.2026: the table is the ground in every theme); a new profile
starts as a copy of this one; a dropdown as wide as its longest choice. The owner, retail
31.10.2026: "I need a clearly skinned style according to Blizzard examples"."""

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


def frames(wow: WowRuntime, on: bool) -> None:
    wow.execute(f"{PROFILE}.gameFrames = {'true' if on else 'false'}; {S}.ApplySkin()")


def theme(wow: WowRuntime, id_: str) -> None:
    wow.execute(f"{PROFILE}.theme = '{id_}'; {S}.ApplyTheme('{id_}'); {S}.ApplySkin()")


def test_every_window_wears_the_games_frame_by_default(wow: WowRuntime):
    boot(wow)
    win = omnibox(wow)
    assert wow.eval(f"{PROFILE}.gameFrames") is True  # the board's question 4, 17.11.2026
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
    # the switch off: the look's own edge and head again
    frames(wow, False)
    assert wow.eval(f"{chrome}:IsShown()") is False and wow.eval(f"{win}.title:IsShown()") is True
    assert wow.eval(f"{win}.frame.bg:IsShown()") is True
    assert tuple(wow.eval(f"{win}:Insets()"))[1:] == (1, 1)
    assert wow.errors == []


def test_the_window_opacity_reaches_the_games_grounds(wow: WowRuntime):
    boot(wow)
    win = omnibox(wow)
    wow.execute(f"{PROFILE}.windowAlpha = 50; Bastians.UI.ApplyWindowLook()")
    alpha = wow.eval(f"{win}.chrome.Bg:GetAlpha()")
    assert abs(alpha - 0.5) < 0.01  # the slider moves the rock (it did nothing before)
    assert abs(wow.eval(f"{S}.insetAlpha") - 0.5) < 0.01
    assert wow.errors == []


def test_the_browsers_panes_lie_on_the_table_in_every_theme(wow: WowRuntime):
    """ADR 0084 consequences: ADR 0040's insets behind the panes (the game's marble) go with the
    WoW look; the table is the ground in every theme, in the game's frame too."""
    wow.execute('function GetRealmName() return "Classic Beta PvE" end')
    boot(wow, True, "Bastians_Core", "Bastians_Data", "Bastians_Browser")
    wow.execute("Bastians:GetModule('Browser').Browser.OpenWindow()")
    nav = "Bastians:GetModule('Browser').listPane"  # the list tile (the navigation until ADR 0056)
    for id_ in ("folio", "parchment"):
        theme(wow, id_)
        assert wow.eval(f"{nav}.gameInset") is None, id_  # never made
        assert wow.eval(f"{nav}.bg:IsShown()") is True, id_  # its own flat fill
    assert wow.errors == []


def test_without_the_templates_the_window_keeps_its_own_frame(wow: WowRuntime):
    boot(wow, False)
    win = omnibox(wow)
    assert wow.eval(f"{win}.chrome") is False  # asked once, the client has none
    assert wow.eval(f"{win}.title:IsShown()") is True
    assert wow.errors == []


def test_a_new_profile_starts_as_a_copy_of_this_one(wow: WowRuntime):
    boot(wow)
    theme(wow, "blizzard")
    frames(wow, False)
    wow.execute("Bastians:SetProfile('Raid', true)")
    p = wow.eval(PROFILE)
    assert wow.eval("Bastians:GetProfile()") == "Raid"
    assert p.theme == "blizzard" and p.gameFrames is False  # not the defaults
    wow.execute("Bastians:SetProfile('Fresh')")  # without the copy: the defaults, as before
    assert wow.eval(f"{PROFILE}.theme") == "folio" and wow.eval(f"{PROFILE}.gameFrames") is True
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
    styling, it should always be the same - the WoW look": its fixed palette and the game's frame
    and inset, forced, until W5 puts Core's own windows on the one look's frame."""
    boot(wow)
    theme(wow, "parchment")  # Paper and brown ink elsewhere
    wow.execute("Bastians.UI.Hub.Open()")
    hub = "Bastians.UI.Hub"
    gold = list(wow.eval(f"{S}.Palette('blizzard').C.text").values())
    brown = list(wow.eval(f"{S}.C.text").values())
    assert gold != brown
    label = wow.eval(f"{hub}.navButtons[3].label")  # an app's entry, not the chosen one
    assert list(label.GetTextColor(label))[:3] == gold[:3]  # the menu in the gold scheme's text
    assert wow.eval(f"{hub}.win.chrome:IsShown()") is True  # the game's frame, whatever the look
    assert wow.eval(f"{hub}.nav.gameInset.Bg:GetTexture()").endswith("UI-Background-Marble")
    # a theme change elsewhere leaves the settings as they are (until W5 draws Core's windows)
    theme(wow, "teal")
    assert list(label.GetTextColor(label))[:3] == gold[:3]
    assert wow.eval(f"{hub}.win.chrome:IsShown()") is True
    assert wow.errors == []


def test_text_on_a_light_ground_has_no_shadow(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"""local f = CreateFrame("Frame", nil, UIParent)
        FS = {S}.text(f, 12)"""
    )
    assert list(wow.eval("{ FS:GetShadowOffset() }").values()) == [1, -1]
    theme(wow, "parchment")  # brown ink on Paper
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
