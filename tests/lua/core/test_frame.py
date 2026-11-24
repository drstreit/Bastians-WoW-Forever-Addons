"""The frame (W5 of plan-suite-waves.md, ADR 0084 decisions 2 to 4 and 7; core.md "The frame"):
every window opens in one of two heads, the tall one for a window opened to read and the low one
for what stays on screen; the game's frame is the optional border around it with the look's own
ground inside; an app's parts stand in one bar that Core lays out; filters lie in a band; headings
and labels wear the book's faces."""

from harness import WowRuntime

S = "Bastians.UI.Style"
CORE = "Bastians:GetModule('Core')"
PROFILE = f"{CORE}.db.profile"
GAME = "Mock.templates.PortraitFrameTemplate = true; Mock.templates.InsetFrameTemplate = true"
FONTS = f"{S}.BOOK_FONTS"


def boot(wow: WowRuntime, game: bool = False) -> WowRuntime:
    if game:
        wow.execute(GAME)
    wow.start("Bastians_Core")
    wow.run_frames(5)
    if not game:
        wow.execute(f"{PROFILE}.gameFrames = false; {S}.ApplySkin()")
    return wow


def window(wow: WowRuntime, name: str, opts: str = "") -> str:
    wow.execute(
        f"{name} = Bastians.UI.Window('{name}Frame', {{ module = 'Core', title = 'My Quests', {opts} }});"
        f" {name}:Show()"
    )
    return name


def test_a_window_wears_the_low_head_unless_it_names_the_tall_one(wow: WowRuntime):
    boot(wow)
    low = window(wow, "LOW")
    tall = window(wow, "TALL", "head = 'tall'")
    assert wow.eval(f"{low}.headKind") == "low" and wow.eval(f"{tall}.headKind") == "tall"
    # the heights, the home mark and the name: the board's numbers (Window.HEADS)
    assert wow.eval(f"{low}.head:GetHeight()") == 30
    assert wow.eval(f"{tall}.head:GetHeight()") == 50
    assert wow.eval(f"{low}.mark:GetWidth()") == 20 and wow.eval(f"{tall}.mark:GetWidth()") == 34
    assert tuple(wow.eval(f"{tall}.title:GetFont()"))[:2] == (wow.eval(f"{FONTS}.bookDisplay"), 18)
    assert tuple(wow.eval(f"{low}.title:GetFont()"))[:2] == (wow.eval(f"{FONTS}.bookCaps"), 13)
    # a low head writes the name in small capitals: lower case letters in the labels' face
    assert wow.eval(f"{low}.title:GetText()") == "my quests"
    assert wow.eval(f"{tall}.title:GetText()") == "My Quests"
    wow.execute(f"{low}:SetTitle('Route'); {tall}:SetTitle('Gold')")
    assert wow.eval(f"{low}.title:GetText()") == "route"
    assert wow.eval(f"{tall}.title:GetText()") == "Gold"
    # the mark is the app's pictogram in the name's ink; the name stands after it
    assert wow.eval(f"{tall}.mark.icon:GetTexture()") is not None
    assert wow.eval(f"{S}.painted[{tall}.mark.icon][1] == {S}.C.headerText") is True
    assert wow.eval(f"select(2, {tall}.title:GetPoint(1)) == {tall}.mark") is True
    # a rule under the head, the content under it
    assert wow.eval(f"{tall}.head.rule:GetHeight()") == 1 and wow.eval(
        f"{tall}.head.rule:IsShown()"
    )
    assert tuple(wow.eval(f"{tall}:Insets()")) == (51, 1, 1)
    assert tuple(wow.eval(f"{low}:Insets()")) == (31, 1, 1)
    assert wow.errors == []


def test_the_windows_own_actions_are_quiet_pictograms(wow: WowRuntime):
    boot(wow)
    low = window(wow, "LOW", "lockable = true, db = {}")
    tall = window(wow, "TALL", "head = 'tall'")
    for win, glyph, height in ((low, 16, 22), (tall, 20, 28)):
        for part in ("close", "options"):
            b = f"{win}.{part}"
            assert wow.eval(f"{b}.spec.only") is True, part
            assert wow.eval(f"{b}.icon:GetWidth()") == glyph, (win, part)
            assert wow.eval(f"{b}:GetHeight()") == height, (win, part)
            assert wow.eval(f"{b}.label:GetText()") in ("", None)  # the word is the tooltip
            assert wow.eval(f"{b}.tip") is not None
    assert wow.eval(f"{low}.lock.spec.toggle") is True
    # the options open the app's page of the hub
    wow.execute(f"{tall}.options:Click()")
    assert wow.eval("Bastians.UI.Hub.current.mod.name") == "Core"
    assert wow.errors == []


def test_a_home_mark_with_a_way_home_is_a_button(wow: WowRuntime):
    boot(wow)
    wow.execute("HOME = 0")
    win = window(
        wow,
        "W",
        "head = 'tall', homeTip = 'The front table', onHome = function() HOME = HOME + 1 end",
    )
    plain = window(wow, "P", "head = 'tall'")
    assert wow.eval(f"{win}.mark:IsMouseEnabled()") is True
    assert wow.eval(f"{plain}.mark:IsMouseEnabled()") is False  # the head drags there too
    wow.execute(f"{win}.mark:Click()")
    assert wow.eval("HOME") == 1 and wow.eval(f"{win}.mark.tip") == "The front table"
    assert wow.errors == []


def test_a_tall_head_in_the_games_frame_takes_the_portrait_as_its_mark(wow: WowRuntime):
    boot(wow, game=True)
    wow.execute("HOME = 0")
    win = window(wow, "W", "head = 'tall', onHome = function() HOME = HOME + 1 end")
    assert wow.eval(f"{win}.gameFramed") is True
    chrome = f"{win}.chrome"
    assert wow.eval(f"{chrome}.TitleText:GetText()") == "My Quests"  # the game's strip has the name
    assert wow.eval(f"{chrome}.portrait:GetTexture()") is not None
    for part in ("title", "close", "mark"):
        assert wow.eval(f"{win}.{part}:IsShown()") is False, part
    assert wow.eval(f"{win}.options:IsShown()") is True
    # the head starts right of the ring under the strip, the content under the head
    assert tuple(wow.eval(f"select(4, {win}.head:GetPoint(1))")) == (58, -22)
    assert wow.eval(f"{win}.head:GetHeight()") == 50
    assert tuple(wow.eval(f"{win}:Insets()")) == (72, 6, 6)
    assert tuple(wow.eval(f"select(4, {win}.content:GetPoint(1))")) == (6, -72)
    assert wow.eval(f"{win}:HeadStart()") == 4 and wow.eval(f"{win}:NameStart()") == 4
    # the portrait is the home mark
    wow.execute(f"{win}.portraitButton:Click()")
    assert wow.eval("HOME") == 1
    # the game's red button closes
    wow.execute(f"{chrome}.CloseButton:Click()")
    assert wow.eval(f"{win}:IsShown()") is False
    assert wow.errors == []


def test_a_low_head_in_the_games_frame_has_no_ring(wow: WowRuntime):
    boot(wow, game=True)
    win = window(wow, "W")
    chrome = f"{win}.chrome"
    assert wow.eval(f"{win}.portraitGone") is True
    assert wow.eval(f"{chrome}.borderLayout") == "ButtonFrameTemplateNoPortrait"
    assert wow.eval(f"{chrome}.portrait:IsShown()") is False
    assert tuple(wow.eval(f"select(4, {win}.head:GetPoint(1))")) == (6, -22)
    assert wow.eval(f"{win}.head:GetHeight()") == 30
    assert tuple(wow.eval(f"{win}:Insets()")) == (52, 6, 6)
    assert wow.eval(f"{win}:HeadStart()") == 10
    # a client whose frame cannot take the portrait away keeps it: the head starts beside it
    wow.execute("Bastians.Compat.GameWindowPortrait = function() return false end")
    kept = window(wow, "K")
    assert wow.eval(f"{kept}.portraitGone") is False
    assert wow.eval(f"{kept}.chrome.portrait:GetTexture()") is not None
    assert tuple(wow.eval(f"select(4, {kept}.head:GetPoint(1))")) == (58, -22)
    assert wow.errors == []


def test_a_bare_low_head_has_no_band_in_the_games_frame(wow: WowRuntime):
    boot(wow, game=True)
    win = window(wow, "W", "bareHead = true")
    assert wow.eval(f"{win}:IsBare()") is True
    assert wow.eval(f"{win}.head:IsShown()") is False
    assert wow.eval(f"{win}.ground.band:IsShown()") is False
    assert tuple(wow.eval(f"{win}:Insets()")) == (22, 6, 6)
    # the options pictogram stands on the game's strip
    assert wow.eval(f"{win}.options:GetParent() == {win}.chrome") is True
    assert wow.eval(f"{win}.options:IsShown()") is True
    # off the game's frame the head is a plain low one again, the options back in it
    wow.execute(f"{PROFILE}.gameFrames = false; {S}.ApplySkin()")
    assert wow.eval(f"{win}.head:IsShown()") is True and wow.eval(f"{win}.head:GetHeight()") == 30
    assert wow.eval(f"{win}.options:GetParent() == {win}.head") is True
    assert tuple(wow.eval(f"{win}:Insets()")) == (31, 1, 1)
    # a lockable window is never bare: its lock needs the band
    locked = window(wow, "L", "bareHead = true, lockable = true, db = {}")
    assert wow.eval(f"{locked}:IsBare()") is False
    # a tall head is never bare
    assert wow.eval(f"{window(wow, 'T', 'head = [[tall]], bareHead = true')}:IsBare()") is False
    assert wow.errors == []


def test_inside_the_games_border_lies_the_looks_own_ground(wow: WowRuntime):
    boot(wow, game=True)
    win = window(wow, "W", "head = 'tall'")
    ground = f"{win}.ground"
    assert wow.eval(f"{ground}:IsShown()") is True
    # the table in the theme's ground at the window's opacity; the game's rock never shows
    assert wow.eval(f"{S}.painted[{ground}.table][1] == {S}.C.bg") is True
    assert wow.eval(f"{win}.chrome.Bg:GetAlpha()") == 0
    wow.execute(
        f"{PROFILE}.windowAlpha = 50; "
        "Bastians:Fire('BASTIANS_SETTING_CHANGED', 'Core', 'windowAlpha', 50)"
    )
    assert wow.eval(f"{S}.painted[{ground}.table][2]") == 0.5
    # the head's band under the strip in the header's colour, a rule under it
    band = f"{ground}.band"
    assert wow.eval(f"{band}:IsShown()") is True
    assert (
        wow.eval(f"{band}:GetHeight()") == 51
    )  # from the ground's top (21) to the head's foot (72)
    assert wow.eval(f"{S}.painted[{band}.fill][1] == {S}.C.header") is True
    assert wow.eval(f"{S}.painted[{band}.rule][1] == {S}.C.line") is True
    assert wow.eval(f"{band}.rule:GetHeight()") == 1
    # a head in a palette of its own (Bastian's Book's dark table) paints the band in it
    wow.execute(f"{win}:SetHeadPalette({S}.FolioPalette())")
    assert wow.eval(f"{S}.painted[{band}.fill][1] == {S}.C.folioBarTop") is True
    assert wow.eval(f"{S}.painted[{band}.rule][1] == {S}.C.folioRule") is True
    wow.execute(f"{win}:SetHeadPalette(nil)")
    assert wow.eval(f"{S}.painted[{band}.fill][1] == {S}.C.header") is True
    # off the game's frame the look's own edge and ground come back
    wow.execute(f"{PROFILE}.gameFrames = false; {S}.ApplySkin()")
    assert wow.eval(f"{ground}:IsShown()") is False
    assert (
        wow.eval(f"{win}.frame.bg:IsShown()") is True and wow.eval(f"{win}.title:IsShown()") is True
    )
    assert wow.errors == []


BAR = """
PICKED, CLICKED = nil, 0
BAR = W:Bar({
  tabs = {
    items = {
      { id = 'today', label = 'Today', icon = 'gold', tip = 'What to do today' },
      { id = 'spots', label = 'Farm spots', icon = 'spot' },
      { id = 'ledger', label = 'Ledger', icon = 'ledger' },
    },
    value = 'today',
    onChange = function(id) PICKED = id end,
  },
  search = { hint = 'Search gold' },
  tools = {
    { id = 'scan', label = 'Scan', tip = 'Reads the auction house', onClick = function() CLICKED = CLICKED + 1 end },
    { id = 'atlas', label = 'Atlas', icon = 'zone', primary = true },
  },
})
"""


def layout(wow: WowRuntime, width: int) -> None:
    wow.execute(
        f"W.frame:SetWidth({width}); W.head:SetWidth({width} - 2); W.content:SetWidth({width} - 2);"
        " BAR:Layout()"
    )


def test_the_bar_holds_an_apps_tabs_search_and_tools(wow: WowRuntime):
    boot(wow)
    window(wow, "W", "head = 'tall'")
    wow.execute(BAR)
    assert wow.eval("W:Bar() == BAR") is True  # one bar per window
    # the tabs: words in small capitals 13, 28 high, the shown one filled, no plate around them
    tabs = "BAR.tabs"
    assert wow.eval(f"{tabs}.spec.flat") is True and wow.eval(f"{tabs}.spec.value") == "today"
    assert wow.eval(f"{tabs}:GetHeight()") == 28
    first = f"{tabs}:Part('today')"
    assert wow.eval(f"{first}.label:GetText()") == "today"
    assert tuple(wow.eval(f"{first}.label:GetFont()"))[:2] == (wow.eval(f"{FONTS}.bookCaps"), 13)
    assert wow.eval(f"{first}.fill:IsShown()") is True
    assert wow.eval(f"{tabs}:Part('spots').fill:IsShown()") is False
    wow.execute(f"{tabs}:Part('spots'):Click()")
    assert wow.eval("PICKED") == "spots"
    # the tools: words in an outline 28 high, the primary the one filled plate in small capitals
    scan, atlas = "BAR.tools.scan", "BAR.tools.atlas"
    assert wow.eval(f"{scan}:GetHeight()") == 28 and wow.eval(f"{atlas}:GetHeight()") == 28
    assert wow.eval(f"{scan}.spec.boxed") is True and wow.eval(f"{scan}.spec.primary") is None
    assert tuple(wow.eval(f"{scan}.label:GetFont()"))[:2] == (wow.eval(f"{FONTS}.bookSans"), 13)
    assert wow.eval(f"{atlas}.spec.primary") is True
    assert wow.eval(f"{atlas}.label:GetText()") == "atlas"
    assert wow.eval(f"{atlas}.icon:GetWidth()") == 16
    assert wow.eval(f"{S}.painted[{atlas}.face][1] == {S}.C.accent") is True
    wow.execute(f"{scan}:Click()")
    assert wow.eval("CLICKED") == 1 and wow.eval(f"{scan}.tip") == "Reads the auction house"
    # the search: a field of the tools' height, 230 wide at most
    assert wow.eval("BAR.search:GetHeight()") == 28
    layout(wow, 1900)
    assert wow.eval("BAR.search:GetWidth()") == 230
    assert wow.errors == []


def test_a_head_too_narrow_gives_the_tabs_a_row_of_their_own(wow: WowRuntime):
    boot(wow)
    window(wow, "W", "head = 'tall'")
    wow.execute(BAR)
    layout(wow, 1900)
    assert wow.eval("BAR.row") is False and wow.eval("BAR:Room()") == 0
    assert wow.eval("BAR.tabs:GetParent() == W.head") is True
    assert wow.eval("BAR.rowFrame:IsShown()") is False
    need = wow.eval("W:HeadStart() + BAR.tabs:GetWidth()")
    # too narrow for the tabs beside the search and the tools: a row under the head
    layout(wow, int(need) + 150)
    assert wow.eval("BAR.row") is True and wow.eval("BAR:Room()") == 38
    assert wow.eval("BAR.tabs:GetParent() == BAR.rowFrame") is True
    assert wow.eval("BAR.rowFrame:IsShown()") is True
    assert wow.eval("BAR.tabs:Part('today').item.icon") is None  # the words still fit on the row
    # too narrow even for a row of words: the pictograms, the words in the tips
    wow.execute(
        "W.frame:SetWidth(120); W.head:SetWidth(118); W.content:SetWidth(118); BAR:Layout()"
    )
    assert wow.eval("BAR.tabs:Part('today').item.icon") == "gold"
    assert wow.eval("BAR.tabs:Part('spots').tip") == "Farm spots"
    assert wow.eval("BAR.tabs:Part('today').tip") == "What to do today"  # a tab's own tip stays
    layout(wow, 1900)
    assert wow.eval("BAR.row") is False
    assert wow.eval("BAR.tabs:Part('today').label:GetText()") == "today"
    # a tool that goes lets the others close up
    wow.execute("BAR.tools.atlas:Hide(); BAR:Layout()")
    assert wow.eval("select(2, BAR.tools.scan:GetPoint(1)) == W.options") is True
    assert wow.errors == []


def test_a_bar_that_wraps_its_tools_gives_them_rows_under_a_narrow_head(wow: WowRuntime):
    """W9 (the Map at its least width): with `wrapTools` the tools leave a head too narrow for
    the search at its least width and them; a tool added later stands where it was asked to."""
    boot(wow)
    window(wow, "W", "head = 'tall'")

    def lay(width: int) -> None:
        wow.execute(
            f"W.frame:SetWidth({width}); W.head:SetWidth({width} - 2);"
            f" W.content:SetWidth({width} - 2); TB:Layout()"
        )

    wow.execute(
        """
        TB = W:Bar({
          wrapTools = true,
          search = { hint = "Search" },
          tools = {
            { id = "a", label = "Eastern Kingdoms", menu = true },
            { id = "b", label = "Player" },
            { id = "z", label = "Full", primary = true },
          },
        })
        TB:AddTool({ id = "late", label = "Dock" }, "z")
        """
    )
    assert [
        wow.eval(f"TB.order[{i}] == TB.tools.{k}") for i, k in enumerate(("a", "b", "late", "z"), 1)
    ] == [True] * 4
    assert wow.eval("TB.tools.a.arrow:IsShown()") is True  # a select: the small arrow
    lay(1900)
    assert wow.eval("TB.toolRows") == 0 and wow.eval("TB:Room()") == 0
    assert wow.eval("TB.tools.late:GetParent() == W.head") is True
    assert wow.eval("select(2, TB.tools.late:GetPoint(1)) == TB.tools.z") is True
    # too narrow: the tools on a row under the head, left to right, 8 apart; the search stays
    lay(360)
    assert wow.eval("TB.toolRows") == 1 and wow.eval("TB:Room()") == 38
    assert wow.eval("TB.toolFrame:IsShown()") is True
    xs = [
        tuple(wow.eval(f"{{ TB.tools.{k}:GetPoint(1) }}").values())[3]
        for k in ("a", "b", "late", "z")
    ]
    assert xs[0] == 0 and xs == sorted(xs)
    assert xs[1] == wow.eval("TB.tools.a:GetWidth()") + 8
    assert wow.eval("TB.search:GetParent() == W.head") is True
    # narrower still: a second row
    lay(200)
    assert wow.eval("TB.toolRows") == 2 and wow.eval("TB:Room()") == 2 * 28 + 3 * 6 - 2
    lay(1900)
    assert wow.eval("TB.toolRows") == 0 and wow.eval("TB.tools.a:GetParent() == W.head") is True
    assert wow.errors == []


def test_the_band_flows_groups_of_parts_in_rows(wow: WowRuntime):
    boot(wow)
    wow.execute(
        """
        BAND = Bastians.UI.Band(UIParent)
        PARTS = {}
        for i = 1, 6 do
          PARTS[i] = CreateFrame("Frame", nil, BAND.frame)
        end
        function LAY(width)
          BAND:Begin(width)
          BAND:Group("where", true)
          BAND:Place(PARTS[1], 100, 22)
          BAND:Place(PARTS[2], 100, 22)
          BAND:Group("sort", false, 100)
          BAND:Place(PARTS[3], 100, 22)
          BAND:Group("level", true, nil, 34)
          BAND:Place(PARTS[4], 204, 34)
          BAND:Place(PARTS[5], 60, 22)
          return BAND:End()
        end
        """
    )
    # wide: where and sort share a row (a line between them), level on a row of 34
    assert wow.eval("LAY(900)") == 10 + 22 + 8 + 34 + 9
    assert wow.eval("BAND.frame:GetHeight()") == 83
    assert tuple(wow.eval("select(4, PARTS[1]:GetPoint(1))")) == (15 + 41, -10)
    assert tuple(wow.eval("select(4, PARTS[2]:GetPoint(1))")) == (15 + 41 + 100 + 5, -10)
    assert wow.eval("BAND.s") == 1 and wow.eval("BAND.seps[1]:GetHeight()") == 20
    assert wow.eval("select(5, PARTS[3]:GetPoint(1))") == -10  # on the first row
    assert tuple(wow.eval("select(4, PARTS[4]:GetPoint(1))")) == (56, -(10 + 22 + 8))
    # a part lower than its row stands on the row's middle
    assert wow.eval("select(5, PARTS[5]:GetPoint(1))") == -(10 + 22 + 8 + 6)
    # the labels: small capitals 11 in the dim ink
    assert wow.eval("BAND.labels[1]:GetText()") == "where"
    assert tuple(wow.eval("BAND.labels[1]:GetFont()"))[:2] == (wow.eval(f"{FONTS}.bookCaps"), 11)
    # the ground and the rule in the panel's and the line's colours
    assert wow.eval(f"{S}.painted[BAND.ground][1] == {S}.C.panel") is True
    assert wow.eval(f"{S}.painted[BAND.rule][1] == {S}.C.line") is True
    # narrow: sort does not fit after where and takes a row of its own, the part after the
    # slider too; no line between groups is left over
    assert wow.eval("LAY(300)") == 10 + 22 + 8 + 22 + 8 + 34 + 8 + 22 + 9
    assert wow.eval("BAND.s") == 0 and wow.eval("BAND.seps[1]:IsShown()") is False
    assert wow.eval("BAND.Centre(22, 22.00002)") == 0  # rounded, not cut (R4.14)
    assert wow.errors == []


DIMS = """
BARF = Bastians.UI.FilterBar(UIParent, { band = true })
BARF.frame:SetWidth(400)
ON = { vendor = true }
BARF:SetDims({
  { id = 'service', title = 'Service', chips = true, active = ON, onSelect = function(k) PICK = k end,
    choices = { { key = 'vendor', label = 'vendor', count = 4 }, { key = 'trainer', label = 'trainer' } } },
})
"""


def test_the_filter_bar_above_a_list_is_a_band(wow: WowRuntime):
    boot(wow)
    wow.execute(DIMS)
    # the band's ground and rule, its padding around one row of chips
    assert wow.eval("BARF.ground:IsShown()") is True and wow.eval("BARF.rule:IsShown()") is True
    assert wow.eval("BARF:Height()") == 10 + 22 + 9
    chips = wow.eval("#BARF:Chips()")
    assert chips == 3  # All, vendor, trainer
    first = "BARF.chips[1]"
    assert wow.eval(f"{first}:GetHeight()") == 22
    assert tuple(wow.eval(f"select(4, {first}:GetPoint(1))")) == (15, -10)
    # the chosen chip is filled in the accent with the ground's ink, the others quiet
    on, off = "BARF.chips[2]", "BARF.chips[3]"
    assert wow.eval(f"{on}.on") is True
    assert wow.eval(f"{S}.painted[{on}.face][1] == {S}.C.accent") is True
    assert wow.eval(f"{S}.painted[{on}.face][2]") == 1
    assert wow.eval(f"{S}.inked[{on}.label] == {S}.C.bg") is True
    assert wow.eval(f"{S}.painted[{off}.face][2]") == 0
    assert wow.eval(f"{S}.inked[{off}.label] == {S}.C.text") is True
    wow.execute(f"{off}:Click()")
    assert wow.eval("PICK") == "trainer"
    # nothing to choose: no band
    wow.execute("BARF:SetDims({})")
    assert wow.eval("BARF:Height()") == 1 and wow.eval("BARF.ground:IsShown()") is False
    # a bar hosted in an owner's frame stays bare: no ground, no padding
    wow.execute("BARE = Bastians.UI.FilterBar(UIParent); BARE.frame:SetWidth(400)")
    assert wow.eval("BARE.ground") is None and wow.eval("BARE.x0") == 0
    assert wow.errors == []


def test_headings_and_labels_wear_the_books_faces(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"""
        HOST = CreateFrame("Frame", nil, UIParent)
        HEAD = {S}.heading(HOST, 15, 17)
        SECTION = {S}.section(HOST, {{ title = "Hand in, this zone" }})
        BODY = {S}.text(HOST, 12)
        NUMBER = {S}.SetRole({S}.text(HOST, 11), "number")
        """
    )
    assert wow.eval("(HEAD:GetFont())") == wow.eval(f"{FONTS}.bookDisplay")
    assert wow.eval("(SECTION.title:GetFont())") == wow.eval(f"{FONTS}.bookCaps")
    assert wow.eval("(select(2, SECTION.title:GetFont()))") == 11  # the size it was given
    assert wow.eval("SECTION.title:GetText()") == "hand in, this zone"  # the face sets the capitals
    # the body and the numbers stay the reader's text font
    wow.execute(f"{PROFILE}.font = 'Fonts\\\\FRIZQT__.TTF'; {S}.applyFont()")
    assert wow.eval("(BODY:GetFont())") == "Fonts\\FRIZQT__.TTF"
    assert wow.eval("(NUMBER:GetFont())") == "Fonts\\FRIZQT__.TTF"
    assert wow.eval("(HEAD:GetFont())") == wow.eval(f"{FONTS}.bookDisplay")
    assert wow.eval(f"{S}.SmallCaps('Front Table')") == "front table"
    # a client that keeps its own font gets plain capitals
    wow.execute(f"{S}.CLIENT_FONT = true")
    assert wow.eval(f"{S}.SmallCaps('Front Table')") == "FRONT TABLE"
    wow.execute(f"{S}.CLIENT_FONT = false")
    assert wow.errors == []


def test_the_three_face_settings_are_gone_and_cleared_once(wow: WowRuntime):
    boot(wow)
    keys = [o.key for o in wow.eval(f"{CORE}.def.options").values() if o.key]
    assert "font" in keys and "fontScale" in keys
    for gone in ("headingFont", "labelFont", "numberFont"):
        assert gone not in keys, gone
    # migration 5 clears them from a profile that has them, and nothing else
    wow.execute(
        f"""
        local sv = {{ profiles = {{ Old = {{ headingFont = "a", labelFont = "b", numberFont = "c",
          font = "d", theme = "night" }}, Plain = {{ font = "e" }} }} }}
        {CORE}.def.migrations[5]({{ sv = sv, profile = sv.profiles.Old }})
        OLD, PLAIN = sv.profiles.Old, sv.profiles.Plain
        """
    )
    for gone in ("headingFont", "labelFont", "numberFont"):
        assert wow.eval(f"OLD.{gone}") is None
    assert wow.eval("OLD.font") == "d" and wow.eval("OLD.theme") == "night"
    assert wow.eval("PLAIN.font") == "e"
    assert wow.errors == []


def test_the_hub_wears_the_frame_and_the_theme(wow: WowRuntime):
    boot(wow, game=True)
    wow.execute(f"{PROFILE}.gameFrames = false; {S}.ApplySkin()")
    wow.execute("Bastians.UI.Hub.Open('Core')")
    hub = "Bastians.UI.Hub"
    win = f"{hub}.win"
    assert wow.eval(f"{win}.headKind") == "tall"
    # the suite's frame switch and theme, no palette or frame of its own
    assert wow.eval(f"{win}.gameFramed") is False
    assert wow.eval(f"{win}.frame.palette") is None
    wow.execute(f"{PROFILE}.gameFrames = true; {S}.ApplySkin()")
    assert wow.eval(f"{win}.gameFramed") is True
    # the rail on the band's ground with a rule beside it
    assert wow.eval(f"{S}.painted[{hub}.rail.bg][1] == {S}.C.panel") is True
    assert wow.eval(f"{hub}.rail.rule:GetWidth()") == 1
    # a section's header in the heading face 18, a toggle as the book's switch on a card
    widgets = f"{hub}.canvas.widgets"
    n = wow.eval(f"#{widgets}")
    header = switch = None
    for i in range(1, n + 1):
        w = f"{widgets}[{i}]"
        has = f"rawget({w}, 'label') ~= nil and rawget({w}, 'box')"
        if (
            header is None
            and wow.eval(f"{has} == nil and rawget({w}, 'SetText') ~= nil")
            and wow.eval(f"(select(2, {w}.label:GetFont()))") == 18
        ):
            header = w
        if switch is None and wow.eval(f"{has} ~= nil and rawget({w}, 'SetChecked') ~= nil"):
            switch = w
    assert header is not None and switch is not None
    assert wow.eval(f"({header}.label:GetFont())") == wow.eval(f"{FONTS}.bookDisplay")
    assert tuple(wow.eval(f"{switch}.box:GetSize()")) == (28, 15)
    before = wow.eval(f"{switch}:GetChecked()")
    wow.execute(f"{switch}:Click()")
    assert wow.eval(f"{switch}:GetChecked()") is (not before)
    assert wow.eval(f"{switch}.box.spec.on == true") is (not before)
    wow.execute(f"{switch}:Click()")  # back
    assert wow.errors == []


def test_an_apps_own_part_named_bar_survives_a_size_change(wow: WowRuntime):
    """Forever 23.11.2026: the minimap buttons' window keeps its scroll bar as `win.bar`; Core's
    size handler asked that part to lay out the head's bar ("attempt to call a nil value" on
    every size change). Core's bar is `headBar`, an app's `bar` is the app's."""
    boot(wow)
    window(wow, "own")
    wow.execute("own.bar = CreateFrame('Frame', nil, own.content)")
    wow.execute("own.frame:SetSize(500, 300); own.frame:GetScript('OnSizeChanged')(own.frame)")
    wow.execute(
        "laid = 0; local bar = own:Bar({}); local layout = bar.Layout;"
        " bar.Layout = function(...) laid = laid + 1; return layout(...) end"
    )
    wow.execute("own.frame:SetSize(520, 300); own.frame:GetScript('OnSizeChanged')(own.frame)")
    assert wow.eval("laid") >= 1  # the head's bar follows the window's width


def test_the_hubs_rail_scrolls_in_a_window_lower_than_its_rows(wow: WowRuntime):
    """Forever 23.11.2026, the windows probe: 22 rows are 790 units, and in a window 728 high the
    last four stood under its foot. The rows lie in a scroll frame; the row of the page the hub
    opens on comes into view."""
    boot(wow)
    hub = "Bastians.UI.Hub"
    wow.execute(f"{hub}.Open('Core')")
    # the mock lays nothing out by anchors: the rail's view gets its height by hand
    wow.execute(f"{hub}.navScroll:SetHeight(120); {hub}.Refresh()")
    view = wow.eval(f"{hub}.navScroll:GetHeight()")
    total = wow.eval(f"{hub}.navBar.total")
    assert total > view > 0
    assert wow.eval(f"{hub}.navBar:GetAlpha()") == 1  # the bar is there while it is needed
    assert wow.eval(f"{hub}.nav:GetParent() == {hub}.navScroll") is True
    assert wow.eval(f"{hub}.nav:GetHeight()") == total
    assert wow.eval(f"{hub}.navScroll:GetVerticalScroll()") == 0  # General is the second row
    wow.execute(f"{hub}.Open('about')")  # the last row
    off = wow.eval(f"{hub}.navScroll:GetVerticalScroll()")
    assert off == total - view  # the list's foot at the view's foot
    wow.execute(f"{hub}.Open('suite')")  # the first one again
    assert wow.eval(f"{hub}.navScroll:GetVerticalScroll()") == 0
    wow.execute(f"{hub}.navScroll:SetHeight(2000); {hub}.Refresh()")
    assert wow.eval(f"{hub}.navBar:GetAlpha()") == 0  # and gone beside a list that fits


def test_a_tab_can_change_and_be_disabled(wow: WowRuntime):
    """W9 (the Browser's sections): `bar:SetTab` changes a tab's word, tip and `disabled`; a
    disabled tab is dim and takes no click, its tip still says why. With `again` a click on the
    shown tab calls onChange too."""
    boot(wow)
    window(wow, "W", "head = 'tall'")
    wow.execute(
        """
        PICKS = {}
        BAR = W:Bar({
          tabs = {
            items = { { id = 'gold', label = 'Gold', icon = 'gold' }, { id = 'alts', label = 'Characters' } },
            value = 'gold',
            again = true,
            onChange = function(id) PICKS[#PICKS + 1] = id end,
          },
          search = { hint = 'Search' },
        })
        """
    )
    layout(wow, 1900)
    gold, alts = "BAR.tabs:Part('gold')", "BAR.tabs:Part('alts')"
    wow.execute(f"{gold}:Click()")  # the shown tab: onChange again
    assert list(wow.eval("PICKS").values()) == ["gold"]
    wow.execute(
        "BAR:SetTab('gold', { label = 'Items' });"
        " BAR:SetTab('alts', { disabled = true, tip = function() return 'Characters', 'needs Alts' end });"
        " BAR:Layout()"
    )
    assert (
        wow.eval(f"{gold}.label:GetText()") == "items" and wow.eval(f"{gold}.item.glyph") == "gold"
    )
    assert wow.eval(f"{gold}:GetAlpha()") == 1 and wow.eval(f"{alts}:GetAlpha()") == 0.4
    wow.execute(f"{alts}:Click()")
    assert (
        list(wow.eval("PICKS").values()) == ["gold"] and wow.eval("BAR.tabs.spec.value") == "gold"
    )
    assert list(wow.eval(f"{{ {alts}.tip({alts}) }}").values()) == ["Characters", "needs Alts"]
    # enabled again: the tip goes, a click is its tab
    wow.execute("BAR:SetTab('alts', {}); BAR:Layout()")
    assert wow.eval(f"{alts}:GetAlpha()") == 1 and wow.eval(f"{alts}.tip") is None
    wow.execute(f"{alts}:Click()")
    assert list(wow.eval("PICKS").values()) == ["gold", "alts"]
    assert wow.eval("BAR:SetTab('nobody', {})") is False
    assert wow.errors == []
