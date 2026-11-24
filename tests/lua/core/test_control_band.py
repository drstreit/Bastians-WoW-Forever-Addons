"""A view's controls in a band, the foot and the quiet section headings (ADR 0084 decision 2, W9
of plan-suite-waves.md; core.md "A view's controls in a band"): the kit parts an app's window
takes in its own session. The numbers are the suite's board's."""

from harness import WowRuntime

W = "Bastians.UI.Widgets"
S = "Bastians.UI.Style"
CB = "CB"
CONTROLS = """{
  { id = "zone", kind = "label", text = "Elwynn Forest" },
  { id = "hide", kind = "toggle", on = true, align = "right", label = "Hide done",
    tooltip = "Hide the complete quests.", onClick = function() CLICKS.hide = (CLICKS.hide or 0) + 1 end },
  { id = "tracked", kind = "toggle", align = "right", label = "Tracked",
    onClick = function() CLICKS.tracked = true end },
  { id = "round", kind = "button", shape = "chip", align = "right", label = "Quest round",
    onClick = function() CLICKS.round = true end },
}"""


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start("Bastians_Core")
    wow.run_frames(5)
    wow.execute("CLICKS = {}; HOST = CreateFrame('Frame', nil, UIParent)")
    return wow


def band(wow: WowRuntime, opts: str = "") -> str:
    wow.execute(f"{CB} = {W}.ControlBand(HOST, {{ {opts} }})")
    return CB


def left(wow: WowRuntime, part: str) -> tuple[float, float]:
    """Where a part stands in the band: from its left edge, under its top."""
    point = tuple(wow.eval(f"{part}:GetPoint(1)"))
    assert point[0] == "TOPLEFT" and point[2] == "TOPLEFT"
    return point[3], -point[4]


def test_a_views_controls_stand_in_a_band(wow: WowRuntime):
    boot(wow)
    band(wow)
    # nothing to show: no band at all
    assert wow.eval(f"{CB}:Height()") == 1 and wow.eval(f"{CB}.band.ground:IsShown()") is False
    wow.execute(f"{CB}:SetControls({CONTROLS}); {CB}:Layout(344)")
    assert wow.eval(f"{CB}.band.ground:IsShown()") is True
    # a toggle is a chip, filled while on; a button named a chip is a quiet one
    hide, tracked, round_ = (f"{CB}.byId.{k}" for k in ("hide", "tracked", "round"))
    for chip in (hide, tracked, round_):
        assert wow.eval(f"{S}.widgets[{chip}]") == "pill" and wow.eval(f"{chip}.small") is True
        assert wow.eval(f"{chip}:GetHeight()") == 22
    assert wow.eval(f"{hide}.spec.on") is True
    assert wow.eval(f"{tracked}.spec.on") is None and wow.eval(f"{round_}.spec.on") is None
    assert wow.eval(f"{hide}.label:GetText()") == "Hide done"
    assert wow.eval(f"{CB}.byId.zone:GetText()") == "Elwynn Forest"
    # the label in small capitals at the row's start, in the band's padding
    assert wow.eval(f"{CB}.band.labels[1]:GetText()") == "elwynn forest"
    assert tuple(wow.eval(f"{CB}.band.labels[1]:GetPoint(1)"))[3] == 15
    # the right ones end at the row's right end, in their order, 5 apart, on the one row
    (hx, hy), (tx, ty), (rx, ry) = left(wow, hide), left(wow, tracked), left(wow, round_)
    assert hy == ty == ry == 10
    assert tx == hx + wow.eval(f"{hide}:GetWidth()") + 5
    assert rx == tx + wow.eval(f"{tracked}:GetWidth()") + 5
    assert rx + wow.eval(f"{round_}:GetWidth()") == 344 - 15
    assert wow.eval(f"{CB}:Height()") == 10 + 22 + 9
    # a click is the control's; the tip its tooltip
    wow.execute(f"{hide}:Click(); {tracked}:Click(); {round_}:Click()")
    assert wow.eval("CLICKS.hide") == 1 and wow.eval("CLICKS.tracked") and wow.eval("CLICKS.round")
    assert wow.eval(f"{hide}.tip({hide})") == "Hide the complete quests."
    assert wow.errors == []


def test_a_band_too_narrow_gives_the_controls_more_rows(wow: WowRuntime):
    boot(wow)
    band(wow)
    wow.execute(f"{CB}:SetControls({CONTROLS})")
    heights = []
    wow.execute(f"{CB}.onHeight = function(h) HEIGHTS = (HEIGHTS or 0) + 1 end")
    for width in (344, 300, 220):
        wow.execute(f"{CB}:Layout({width})")
        heights.append(wow.eval(f"{CB}:Height()"))
        # nothing stands past the band's padding
        for k in ("hide", "tracked", "round"):
            x, _ = left(wow, f"{CB}.byId.{k}")
            assert x >= 15 and x + wow.eval(f"{CB}.byId.{k}:GetWidth()") <= width - 15
    # one row, then the chips on a second, then on two of their own (rows 8 apart)
    assert heights == [41, 41 + 30, 41 + 60]
    assert wow.eval("HEIGHTS") == 2  # the owner hears of a change, not of every layout
    assert left(wow, f"{CB}.byId.hide") == (15, 10 + 30)
    assert left(wow, f"{CB}.byId.round")[1] == 10 + 60
    assert wow.errors == []


def test_a_select_is_a_tool_with_a_small_arrow_and_a_button_a_tool(wow: WowRuntime):
    boot(wow)
    band(wow, "search = 'Search quests ...'")
    wow.execute(
        f"""{CB}:SetControls({{
          {{ id = "kind", kind = "select", value = "any", onChange = function(key) PICKED = key end,
            options = {{ {{ key = "any", label = "Any type" }}, {{ key = "Group", label = "Group" }},
              {{ key = "Dungeon", label = "Dungeon" }} }} }},
          {{ id = "texts", kind = "button", align = "right", label = "load texts",
            onClick = function() CLICKS.texts = true end }},
        }}); {CB}:Layout(560)"""
    )
    kind, texts, search = f"{CB}.byId.kind", f"{CB}.byId.texts", f"{CB}.search"
    for tool in (kind, texts):
        assert wow.eval(f"{S}.widgets[{tool}]") == "action" and wow.eval(f"{tool}.spec.boxed")
        assert wow.eval(f"{tool}:GetHeight()") == 22
    assert wow.eval(f"{kind}.label:GetText()") == "Any type"
    assert wow.eval(f"{kind}.arrow:IsShown()") is True and wow.eval(f"{texts}.arrow") is None
    # the arrow stands 7 after the words and is counted in the tool's width
    assert wow.eval(f"{kind}:GetWidth()") == 8 + len("Any type") * 6 + 7 + 8 + 8
    # the search first, taking the room the controls leave; then the select; the button at the end
    sx, sy = left(wow, search)
    kx, _ = left(wow, kind)
    tx, _ = left(wow, texts)
    assert (sx, sy) == (15, 10)
    assert kx == sx + wow.eval(f"{search}:GetWidth()") + 5
    assert tx + wow.eval(f"{texts}:GetWidth()") == 560 - 15
    assert wow.eval(f"{search}:GetWidth()") > 300
    assert wow.eval(f"{CB}:Height()") == 41
    # the choices in the order given; a pick is the control's
    wow.execute(f"{kind}:Click()")
    items = [
        i.label.GetText(i.label)
        for i in wow.eval("Bastians.UI.FilterMenuFrame()")["items"].values()
        if i.IsShown(i)
    ]
    assert items == ["Any type", "Group", "Dungeon"]
    wow.execute("Bastians.UI.FilterMenuFrame().items[2]:Click()")
    assert wow.eval("PICKED") == "Group"
    # a band too narrow keeps the search at its least width and wraps the rest
    wow.execute(f"{CB}:Layout(250)")
    assert wow.eval(f"{search}:GetWidth()") == 150
    assert wow.eval(f"{CB}:Height()") == 41 + 30
    assert wow.errors == []


def test_an_owners_block_takes_a_row_of_its_own_with_its_label(wow: WowRuntime):
    boot(wow)
    band(wow, "search = 'Search'")
    wow.execute(
        f"BLOCK = CreateFrame('Frame', nil, HOST); {CB}.onBlockWidth = function(w) BW = w end;"
        f" {CB}:Layout(560); {CB}:SetBlock(BLOCK, 'status')"
    )
    assert wow.eval("BLOCK:IsShown()") is False  # nothing in it yet
    assert wow.eval(f"{CB}:Height()") == 41
    wow.execute(f"{CB}:SetBlockHeight(22)")
    assert wow.eval("BLOCK:IsShown()") is True and wow.eval(f"BLOCK:GetParent() == {CB}.frame")
    x, y = left(wow, "BLOCK")
    assert y == 10 + 30  # the second row
    assert x == 15 + len("status") * 6 + 8  # after its label
    assert wow.eval("BW") == 560 - 15 - x and wow.eval("BLOCK:GetWidth()") == 560 - 15 - x
    assert wow.eval(f"{CB}.band.labels[1]:GetText()") == "status"
    assert wow.eval(f"{CB}:Height()") == 41 + 30
    wow.execute(f"{CB}:SetBlockHeight(48)")  # two lines of chips
    assert wow.eval(f"{CB}:Height()") == 10 + 22 + 8 + 48 + 9
    wow.execute(f"{CB}:SetBlockHeight(1)")
    assert wow.eval("BLOCK:IsShown()") is False and wow.eval(f"{CB}:Height()") == 41
    assert wow.errors == []


def test_a_plain_bar_draws_a_toggle_as_a_button_with_a_lit_word(wow: WowRuntime):
    boot(wow)
    wow.execute(f"BAR = {W}.ControlBar(HOST); BAR:SetControls({CONTROLS})")
    on, off = (
        wow.eval("BAR.byId.hide.label:GetText()"),
        wow.eval("BAR.byId.tracked.label:GetText()"),
    )
    assert on == wow.eval(f"{S}.H.accent") + "Hide done|r"
    assert off == wow.eval(f"{S}.H.dim") + "Tracked|r"
    assert wow.eval("BAR.byId.round.label:GetText()") == "Quest round"
    wow.execute("BAR.byId.hide:Click()")
    assert wow.eval("CLICKS.hide") == 1
    assert wow.errors == []


def test_the_foot_is_a_band_at_the_windows_end(wow: WowRuntime):
    boot(wow)
    wow.execute(f"FOOT = {W}.Foot(HOST); FOOT:SetText('6 in the log - 1 to hand in')")
    assert wow.eval("FOOT:GetHeight()") == 34
    assert wow.eval("FOOT:GetText()") == "6 in the log - 1 to hand in"
    assert wow.eval("(FOOT:GetPoint(1))") == "BOTTOMLEFT"
    # on the band's ground with a rule over it, the small text in the dim ink, 12 from the left
    assert wow.eval(f"{S}.painted[FOOT.ground][1] == {S}.C.panel") is True
    assert wow.eval("FOOT.rule:GetHeight()") == 1
    assert wow.eval("(FOOT.rule:GetPoint(1))") == "TOPLEFT"
    assert tuple(wow.eval("FOOT.text:GetFont()"))[1] == 11
    assert tuple(wow.eval("FOOT.text:GetPoint(1)"))[3] == 12
    assert wow.errors == []


def test_a_foot_takes_tools_at_its_end(wow: WowRuntime):
    """W9 (the Route, Notes): tools at the foot's end, in the order added; the shown ones close
    up, clear of the window's grip, and the text ends before them."""
    boot(wow)
    wow.execute(
        f"""
        FOOT = {W}.Foot(HOST)
        FOOT:SetText("Click a step to see its end on the map.")
        A = FOOT:Tool({{ label = "Home", tip = "The way to your inn.", onClick = function() CLICKS.home = true end }})
        B2 = FOOT:Tool({{ label = "Replan" }})
        C = FOOT:Tool({{ label = "Clear" }})
        """
    )
    for tool in ("A", "B2", "C"):
        assert (
            wow.eval(f"{tool}:GetParent() == FOOT") is True
            and wow.eval(f"{tool}:GetHeight()") == 22
        )
        assert wow.eval(f"{tool}.spec.boxed") is True
        assert tuple(wow.eval(f"{tool}.label:GetFont()"))[1] == 11
    # the last one added at the end, 18 before the foot's edge; the others 5 apart before it
    assert tuple(wow.eval("{ C:GetPoint(1) }").values())[3] == -18
    assert wow.eval("select(2, C:GetPoint(1)) == FOOT") is True
    assert wow.eval("select(2, B2:GetPoint(1)) == C") is True
    assert tuple(wow.eval("{ B2:GetPoint(1) }").values())[3] == -5
    assert wow.eval("select(2, A:GetPoint(1)) == B2") is True
    assert wow.eval("select(2, FOOT.text:GetPoint(2)) == A") is True  # the text ends before them
    wow.execute("A:Click()")
    assert wow.eval("CLICKS.home") is True and wow.eval("A.tip") == "The way to your inn."
    # hidden tools take no room: the first shown one moves to the end
    wow.execute("B2:Hide(); C:Hide(); FOOT:Layout()")
    assert wow.eval("select(2, A:GetPoint(1)) == FOOT") is True
    assert tuple(wow.eval("{ A:GetPoint(1) }").values())[3] == -18
    wow.execute("A:Hide(); FOOT:Layout()")
    assert wow.eval("select(2, FOOT.text:GetPoint(2)) == FOOT") is True
    assert wow.errors == []


def test_a_trees_sections_as_quiet_headings(wow: WowRuntime):
    boot(wow)
    rows = """{
      { id = "s:a", kind = "section", title = "Hand in, this zone", count = 1, text = "HAND IN  1",
        children = { { id = "q1", text = "Kobold Candles" } } },
      { id = "s:b", kind = "section", title = "In progress", count = 3, suffix = "  7-11",
        text = "IN PROGRESS  3", children = { { id = "q2", text = "Gold Dust Exchange" } } },
    }"""
    wow.execute(
        f"PLAIN = Bastians.UI.Tree(CreateFrame('Frame', nil, UIParent), {{}});"
        f" CAPS = Bastians.UI.Tree(HOST, {{ capsSections = true }});"
        f" for _, t in ipairs({{ PLAIN, CAPS }}) do t.scroll:SetSize(300, 400); t:SetRows({rows}) end"
    )
    fonts = f"{S}.BOOK_FONTS"
    # the heading: small capitals 11 in the dim ink, the count in the accent, 24 high, no plate
    head = "CAPS.pool[1]"
    dim, accent = wow.eval(f"{S}.H.dim"), wow.eval(f"{S}.H.accent")
    assert wow.eval(f"{head}.text:GetText()") == f"{dim}hand in, this zone|r  {accent}1|r"
    assert wow.eval("CAPS.pool[3].text:GetText()") == f"{dim}in progress|r  {accent}3  7-11|r"
    assert tuple(wow.eval(f"{head}.text:GetFont()"))[:2] == (wow.eval(f"{fonts}.bookCaps"), 11)
    assert wow.eval("CAPS.heights[1]") == 24 and wow.eval(f"{head}.sec:IsShown()") is False
    assert tuple(wow.eval(f"{head}.text:GetPoint(1)"))[4] == -9
    # the row under it is a row as before, in the text's face again
    assert wow.eval("CAPS.pool[2].text:GetText()") == "Kobold Candles"
    assert tuple(wow.eval("CAPS.pool[2].text:GetFont()"))[1] == 12
    assert wow.eval("CAPS.heights[2]") == 18
    # the search finds a heading by its words still (the row's own text)
    assert wow.eval("CAPS.flat[1].text") == "HAND IN  1"
    # without the option nothing changes
    assert wow.eval("PLAIN.pool[1].text:GetText()") == "HAND IN  1"
    assert wow.eval("PLAIN.heights[1]") == 18 and wow.eval("PLAIN.pool[1].sec:IsShown()") is True
    assert wow.errors == []


def test_a_settings_select_is_a_tool_with_a_small_arrow_at_its_end(wow: WowRuntime):
    """ADR 0084 decision 2: "a select is a tool with a small arrow", on every settings page too."""
    boot(wow)
    wow.execute(
        f"SEL = {W}.Select(HOST, 'Theme', {{ folio = 'Folio', paper = 'Paper' }},"
        " function(key) PICKED = key end); SEL:SetValue('folio')"
    )
    button = "SEL.button"
    assert wow.eval(f"{button}.spec.menu") is True and wow.eval(f"{button}.arrow:IsShown()") is True
    # the chosen word from the left, the arrow at the button's end; the width keeps room for both
    assert wow.eval(f"{button}.label:GetText()") == "Folio"
    assert wow.eval(f"({button}.label:GetPoint(1))") == "LEFT"
    assert wow.eval(f"({button}.arrow:GetPoint(1))") == "RIGHT"
    assert wow.eval(f"{button}:GetWidth()") == 160  # the least width
    # a long choice widens the button by its words and the arrow, and is not cut
    wow.execute("SEL:SetValues({ long = string.rep('m', 40) }); SEL:SetValue('long')")
    assert wow.eval(f"{button}:GetWidth()") == 40 * 6 + 28 + 7 + 8
    assert wow.eval(f"{button}.cutTip") is None
    # it opens and picks as before
    wow.execute(f"{button}:Click()")
    assert wow.eval("SEL.list:IsShown()") is True
    wow.execute("SEL.list.items[1]:Click()")
    assert wow.eval("PICKED") == "long" and wow.eval("SEL.list:IsShown()") is False
    assert wow.errors == []


def test_a_value_in_words_takes_the_room_its_words_need(wow: WowRuntime):
    """The windows probe, 23.11.2026: Campfire's "+10 mana every 5 seconds" needed 161 units of the
    value column's 70. A value in words takes what it needs, up to half the row; a number keeps
    the column."""
    boot(wow)
    wow.execute(
        """
        T = Bastians.UI.Tree(HOST, {})
        T.scroll:SetSize(400, 300)
        T:SetRows({
          { id = "a", text = "Mana", value = "+10 mana every 5 seconds", valueKind = "text" },
          { id = "b", text = "Armor", value = "+8", valueKind = "text" },
          { id = "c", text = "Linen Cloth", value = 105, valueKind = "money" },
          { id = "d", text = "Spirit", value = string.rep("m", 80), valueKind = "text" },
        })
        """
    )
    widths = [wow.eval(f"T.pool[{i}].value:GetWidth()") for i in (1, 2, 3, 4)]
    assert widths[0] == len("+10 mana every 5 seconds") * 6 + 4  # its words, not the column's 70
    assert widths[1] == 70 and widths[2] == 70  # short words and a number: the column
    assert widths[3] == 170  # never more than the worth's room, nor half the row
    assert wow.errors == []


def test_a_stat_tiles_figure_stands_in_the_text_font(wow: WowRuntime):
    """The windows probe, 23.11.2026: on a character's page "17" read "I7", the heading face's
    old-style digits. Numbers stay the reader's text font (ADR 0084 decision 7)."""
    boot(wow)
    wow.execute(f"STAT = {S}.stat(HOST, {{ label = 'Level', value = 17, note = 'of 60' }})")
    font, size = tuple(wow.eval("STAT.value:GetFont()"))[:2]
    assert font == wow.eval(f"{S}.font()") and size == 17
    assert font != wow.eval(f"{S}.BOOK_FONTS.bookDisplay")
    assert wow.eval("STAT.value:GetText()") == "17"
    assert wow.errors == []


def test_a_tool_takes_a_pictogram_and_a_chip_a_count(wow: WowRuntime):
    """W9 (the Browser's band): a tool with `icon` draws its pictogram before the word, one with
    `enabled = false` is dim and takes no click; a chip with `count` says it after its word; a
    control with `tipTitle` shows its tooltip under that line."""
    boot(wow)
    band(wow)
    wow.execute(
        f"""{CB}:SetControls({{
          {{ id = "back", label = "Back", icon = "back", enabled = false, tipTitle = "Back",
            tooltip = "The page before.", onClick = function() CLICKS.back = true end }},
          {{ id = "fwd", label = "Forward", icon = "forward",
            onClick = function() CLICKS.fwd = true end }},
          {{ id = "npc", kind = "toggle", on = true, label = "People", count = 12 }},
        }}); {CB}:Layout(400)"""
    )
    back, fwd, npc = (f"{CB}.byId.{k}" for k in ("back", "fwd", "npc"))
    assert wow.eval(f"{S}.widgets[{back}]") == "action" and wow.eval(f"{back}:GetHeight()") == 22
    assert wow.eval(f"{back}.spec.icon") == "back" and wow.eval(f"{back}.icon:IsShown()") is True
    assert wow.eval(f"{back}.icon:GetWidth()") == 14
    assert wow.eval(f"{back}.enabledFlat") is False and wow.eval(f"{back}:GetAlpha()") == 0.4
    assert wow.eval(f"{fwd}.enabledFlat") is True and wow.eval(f"{fwd}:GetAlpha()") == 1
    wow.execute(f"{back}:Click(); {fwd}:Click()")
    assert wow.eval("CLICKS.back") is None and wow.eval("CLICKS.fwd") is True
    assert list(wow.eval(f"{{ {back}.tip({back}) }}").values()) == ["Back", "The page before."]
    assert wow.eval(f"{npc}.count:GetText()") == "12" and wow.eval(f"{npc}.count:IsShown()") is True
    # the same tool without them the next time: no pictogram, enabled
    wow.execute(f"{CB}:SetControls({{ {{ id = 'plain', label = 'Plain' }} }})")
    plain = f"{CB}.byId.plain"
    assert wow.eval(f"{plain} == {CB}.pools.tool[1]") is True  # the tool Back was drawn on
    assert wow.eval(f"{plain}.spec.icon") is None and wow.eval(f"{plain}.enabledFlat") is True
    assert wow.errors == []
