"""The look engine (ADR 0046) in the one look (ADR 0084, W4 of plan-suite-waves.md, 20.11.2026):
widgets declared by the apps, drawn by Core in the book's shape language (book-look.md), coloured
by a theme. The renderer test draws every widget kind in each theme and holds the numbers to
book-look.md sections 4 and 5. ~~The Modern, WoW, Glass and Parchment renderers~~ (until
20.11.2026; their tests were replaced by these, not skipped)."""

import pytest
from harness import WowRuntime

S = "Bastians.UI.Style"
PAINTED = f"{S}.painted"
THEMES = ("folio", "parchment", "teal", "night")


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start("Bastians_Core")
    wow.run_frames(3)
    return wow


def theme(wow: WowRuntime, id_: str) -> None:
    wow.execute(f"Bastians:GetModule('Core').db.profile.theme = '{id_}'; {S}.ApplyTheme('{id_}')")
    wow.execute(f"{S}.ApplyLook()")


def tok(wow: WowRuntime, region: str, token: str) -> bool:
    """Whether the kit painted `region` with the theme's `token` (the table itself)."""
    return wow.eval(f"{PAINTED}[{region}][1] == {S}.C.{token}") is True


def ink(wow: WowRuntime, region: str, token: str) -> bool:
    return wow.eval(f"{S}.inked[{region}] == {S}.C.{token}") is True


def alpha(wow: WowRuntime, region: str):
    return wow.eval(f"{PAINTED}[{region}][2]")


WIDGETS = f"""
W = {{ changed = {{}} }}
W.quiet = {S}.action(UIParent, {{ icon = 'map', label = 'Map' }})
W.tool = {S}.action(UIParent, {{ icon = 'map', label = 'Your record', boxed = true }})
W.main = {S}.action(UIParent, {{ icon = 'map', label = 'Atlas', primary = true }})
W.only = {S}.action(UIParent, {{ icon = 'settings', label = 'Options', only = true }})
W.on = {S}.pill(UIParent, {{ label = 'Rares', count = 4, on = true }})
W.off = {S}.pill(UIParent, {{ label = 'Gold', count = 2 }})
W.chip = {S}.pill(UIParent, {{ small = true, label = 'Wetlands', count = 3 }})
W.tab = {S}.tab(UIParent, {{ label = 'Trade', on = true }})
W.other = {S}.tab(UIParent, {{ label = 'Guild' }})
W.sec = {S}.section(UIParent, {{ icon = 'note', title = 'My notes' }})
W.sw = {S}.toggle(UIParent, {{ on = true, onChange = function(_, on) table.insert(W.changed, on) end }})
W.card = {S}.card(UIParent, {{ stripe = 'tier1' }})
W.seg = {S}.segmented(UIParent, {{ value = 'a',
  items = {{ {{ id = 'a', label = 'one' }}, {{ id = 'b', label = 'two' }} }} }})
W.slider = {S}.slider(UIParent, {{ title = 'Size', min = 0, max = 10, value = 5 }})
W.slider:SetWidth(200)
W.stat = {S}.stat(UIParent, {{ label = 'Gold', value = 12 }})
W.tile = {S}.tile(UIParent, 'quest')
"""


def test_the_theme_carries_geometry_and_tile_tokens(wow: WowRuntime):
    boot(wow)
    g = wow.eval(f"{S}.G")
    assert g.action == 26 and g.actionRow == 22 and g.tile == 18 and g.tileBig == 26 and g.gap == 6
    assert g.chip == 22  # book-look.md section 5: a chip 22 high
    for token in (
        "tileGold",
        "tileRed",
        "tileTeal",
        "tileGreen",
        "tileBlue",
        "tilePurple",
        "tileBrown",
        "tileGrey",
    ):
        assert wow.eval(f"{S}.C.{token}") is not None
    assert wow.eval(f"{S}.LookId()") == "book" and wow.eval(f"{S}.LookOf(UIParent)") == "book"
    assert sorted(wow.eval(f"{S}.LOOKS").keys()) == ["book"]  # one renderer (decision 1)
    assert wow.errors == []


@pytest.mark.parametrize("theme_id", THEMES)
def test_every_widget_kind_in_the_one_look(wow: WowRuntime, theme_id: str):
    """ADR 0084 decision 2 and its consequences ("a renderer test draws every widget kind in the
    one look in each theme and checks the geometry against book-look.md")."""
    boot(wow)
    theme(wow, theme_id)
    wow.execute(WIDGETS)
    # the action: a quiet one the pictogram and the word alone; a tool the words in an outline of
    # the line; the primary the one filled plate in the accent with the ground's ink
    assert alpha(wow, "W.quiet.face") == 0 and alpha(wow, "W.quiet.edges") == 0
    assert alpha(wow, "W.tool.face") == 0 and alpha(wow, "W.tool.edges") == 1
    assert tok(wow, "W.tool.edges", "line") and ink(wow, "W.tool.label", "text")
    assert tok(wow, "W.main.face", "accent") and alpha(wow, "W.main.face") == 1
    assert alpha(wow, "W.main.edges") == 0 and ink(wow, "W.main.label", "bg")
    assert tok(wow, "W.main.icon", "bg")
    assert tok(wow, "W.only.icon", "muted") and wow.eval("W.only.label:GetText()") == ""  # quiet
    assert wow.eval("W.tool:GetHeight()") == 26 and wow.eval("W.quiet:GetHeight()") == 26
    # a tool's side padding 10 (book-look.md section 4), a quiet word's 7
    assert wow.eval("(select(4, W.tool.icon:GetPoint(1)))") == 10
    assert wow.eval("(select(4, W.quiet.icon:GetPoint(1)))") == 7
    # the pill: quiet, the chosen one filled in the accent with the ground's ink; round at both ends
    assert alpha(wow, "W.off.face") == 0 and ink(wow, "W.off.label", "text")
    assert tok(wow, "W.on.face", "accent") and alpha(wow, "W.on.face") == 1
    assert ink(wow, "W.on.label", "bg") and ink(wow, "W.on.count", "bg")
    assert wow.eval("W.on.face.r") == 13 and wow.eval("W.chip.face.r") == 11
    assert wow.eval("W.chip:GetHeight()") == 22
    # the tab: a word; the shown one filled in the accent, top corners round; the other dim
    assert tok(wow, "W.tab.face", "accent") and alpha(wow, "W.tab.face") == 1
    assert ink(wow, "W.tab.label", "bg") and wow.eval("W.tab.face.corners") == "top"
    assert alpha(wow, "W.other.face") == 0 and ink(wow, "W.other.label", "dim")
    assert alpha(wow, "W.tab.edges") == 0 and wow.eval("W.tab.under:IsShown()") is False
    # the section: small capitals in the dim ink, no rule
    # small capitals: the labels' face makes them of lower case letters (W5)
    assert wow.eval("W.sec.title:GetText()") == "my notes" and ink(wow, "W.sec.title", "dim")
    assert wow.eval("W.sec.rule:IsShown()") is False
    # the switch: the book's 28 x 15, a knob of 11, the accent while on, the muted ink while off
    assert wow.eval("W.sw:GetWidth()") == 28 and wow.eval("W.sw:GetHeight()") == 15
    assert wow.eval("W.sw.knob:GetWidth()") == 11
    assert tok(wow, "W.sw.track", "accent") and tok(wow, "W.sw.knob.fill", "bg")
    assert wow.eval("(W.sw.knob:GetPoint(1))") == "RIGHT"
    assert wow.eval("W.sw.mark:IsShown()") is False  # no box with a cross
    wow.execute("W.sw:Click()")
    assert tok(wow, "W.sw.track", "muted") and wow.eval("(W.sw.knob:GetPoint(1))") == "LEFT"
    assert list(wow.eval("W.changed").values()) == [False]
    # the card: the theme's plate and edge
    assert tok(wow, "W.card.face", "card") and tok(wow, "W.card.edges", "cardEdge")
    # the segmented switch: the chosen part filled
    assert wow.eval("W.seg:Part('a').fill:IsShown()") is True
    assert wow.eval("W.seg:Part('b').fill:IsShown()") is False
    assert ink(wow, "W.seg:Part('a').label", "bg") and ink(wow, "W.seg:Part('b').label", "text")
    # the slider: a track of 4, a round knob of 12 in the accent, the track filled up to it
    assert wow.eval("W.slider.rail:GetHeight()") == 4 and wow.eval("W.slider.knob:GetWidth()") == 12
    assert tok(wow, "W.slider.knob", "accent") and tok(wow, "W.slider.fill", "accent")
    assert tok(wow, "W.slider.track", "line")
    # the stat and the tile keep their plate and a thin edge
    assert tok(wow, "W.stat.face", "card") and tok(wow, "W.stat.edges", "line")
    assert tok(wow, "W.tile.edges", "line") and wow.eval("W.tile:GetWidth()") == 18
    assert wow.eval("W.quiet.sheen") is None and wow.eval("W.quiet.gameArt") is None
    assert wow.errors == []


def test_the_mouse_lights_a_tool_and_brings_a_quiet_plate(wow: WowRuntime):
    """book-look.md section 4: a tool's edge in the accent under the mouse; a quiet pictogram
    brighter; a quiet word on a faint plate; the primary keeps its plate."""
    boot(wow)
    wow.execute(WIDGETS)
    for name in ("tool", "quiet", "only", "main"):
        wow.execute(f"W.{name}:GetScript('OnEnter')(W.{name})")
    assert tok(wow, "W.tool.edges", "accent")
    assert tok(wow, "W.quiet.face", "faceHover") and alpha(wow, "W.quiet.face") == 1
    assert tok(wow, "W.only.icon", "text")
    assert tok(wow, "W.main.face", "accent") and alpha(wow, "W.main.face") == 1
    for name in ("tool", "quiet", "only", "main"):
        wow.execute(f"W.{name}:GetScript('OnLeave')(W.{name})")
    assert tok(wow, "W.tool.edges", "line") and alpha(wow, "W.quiet.face") == 0
    assert tok(wow, "W.only.icon", "muted")
    wow.execute("W.tool:SetOn(true)")
    assert tok(wow, "W.tool.edges", "accent") and ink(wow, "W.tool.label", "accent")
    assert wow.errors == []


def test_a_theme_change_redraws_every_widget(wow: WowRuntime):
    """A theme changes colours, never shapes (ADR 0084 decision 5)."""
    boot(wow)
    wow.execute(WIDGETS)
    sizes = {n: wow.eval(f"W.{n}:GetWidth()") for n in ("tool", "on", "tab", "sw")}
    before = list(wow.eval("{ W.on.face:GetVertexColor() }").values())
    theme(wow, "parchment")
    after = list(wow.eval("{ W.on.face:GetVertexColor() }").values())
    assert after != before and after[:3] == list(wow.eval(f"{S}.C.accent").values())[:3]
    assert {n: wow.eval(f"W.{n}:GetWidth()") for n in sizes} == sizes
    assert wow.eval(f"{S}.SHAPE.radius") == 6 and wow.eval(f"{S}.SHAPE.radiusSmall") == 4
    assert wow.errors == []


def test_an_action_draws_pictogram_and_text_and_sizes_itself(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"LookTest = {{}} LookTest.b = {S}.action(UIParent, {{ icon = 'map', label = 'Map', tip = 'Show on the map', "
        "onClick = function() LookTest.clicked = true end })"
    )
    b = "LookTest.b"
    assert wow.eval(f"{b}.icon:GetTexture()") == wow.eval("Bastians.UI.Pictogram('map')")
    assert wow.eval("Bastians.UI.Pictogram('map')") == wow.eval(
        "Bastians.UI.GLYPH_PATHS.zone"
    )  # a path, not an inline code
    assert wow.eval(f"{b}.label:GetText()") == "Map"
    assert wow.eval(f"{b}:GetHeight()") == 26
    assert wow.eval(f"{b}:GetWidth()") > 26
    assert wow.eval(f"{S}.widgets[{b}]") == "action"
    wow.execute(f"{b}:Click()")
    assert wow.eval("LookTest.clicked") is True
    # a row button is smaller; `only` draws the pictogram alone; a badge counts
    wow.execute(
        f"LookTest.r = {S}.action(UIParent, {{ icon = 'route', label = 'Route', row = true }})"
    )
    assert wow.eval("LookTest.r:GetHeight()") == 22
    wow.execute(
        f"LookTest.m = {S}.action(UIParent, {{ icon = 'copy', label = 'More', only = true }})"
    )
    assert wow.eval("LookTest.m.label:GetText()") == ""
    assert wow.eval("LookTest.m:GetWidth()") < wow.eval(f"{b}:GetWidth()")
    wow.execute(f"{b}:SetBadge(3)")
    assert wow.eval(f"{b}.badge:IsShown()") is True and wow.eval(f"{b}.badge.text:GetText()") == "3"
    wow.execute(f"{b}:SetBadge(0)")
    assert wow.eval(f"{b}.badge:IsShown()") is False
    # a name without a pictogram yet: the text alone, no error
    wow.execute(f"LookTest.n = {S}.action(UIParent, {{ icon = 'nonsense', label = 'Nonsense' }})")
    assert not wow.eval("LookTest.n.icon:GetTexture()")  # the mock answers "" for no texture
    assert wow.eval("LookTest.n.label:GetText()") == "Nonsense"
    assert wow.errors == []


def test_a_tile_takes_its_groups_colour(wow: WowRuntime):
    boot(wow)
    wow.execute(f"LookTest = {{}} LookTest.t = {S}.tile(UIParent, 'quest')")
    assert wow.eval("LookTest.t:GetWidth()") == 18
    assert wow.eval("Bastians.UI.TileGroup('quest')") == "tileGold"
    assert wow.eval("Bastians.UI.TileGroup('herb')") == "tileGreen"
    assert wow.eval("Bastians.UI.TileGroup('item')") == "tileBrown"
    assert wow.eval("Bastians.UI.TileGroup('nonsense')") == "tileGrey"
    assert wow.eval("LookTest.t.glyph:GetTexture()") == wow.eval("Bastians.UI.GLYPH_PATHS.quest")
    wow.execute("LookTest.t:SetKind('zone')")
    assert wow.eval("LookTest.t.glyph:GetTexture()") == wow.eval("Bastians.UI.GLYPH_PATHS.zone")
    wow.execute(f"LookTest.big = {S}.tile(UIParent, 'npc', true)")
    assert wow.eval("LookTest.big:GetWidth()") == 26
    assert wow.errors == []


def test_a_chosen_pill_stays_filled_under_the_mouse(wow: WowRuntime):
    """ "selected filter need to be dramatically different from
    unselected": the chosen pill is filled with the accent, its words and count in the ground's
    ink; the mouse never takes the fill away; a quiet one shows its plate only under the mouse."""
    boot(wow)
    wow.execute(WIDGETS)
    wow.execute("W.on:GetScript('OnEnter')(W.on)")
    assert tok(wow, "W.on.face", "accent") and alpha(wow, "W.on.face") == 1
    wow.execute("W.on:GetScript('OnLeave')(W.on)")
    assert tok(wow, "W.on.face", "accent")
    wow.execute("W.off:GetScript('OnEnter')(W.off)")
    assert alpha(wow, "W.off.face") == 1
    wow.execute("W.off:GetScript('OnLeave')(W.off)")
    assert alpha(wow, "W.off.face") == 0
    wow.execute("W.on:SetOn(false)")
    assert alpha(wow, "W.on.face") == 0 and ink(wow, "W.on.label", "text")
    # a choice of value: gold words in a faint gold edge
    wow.execute(f"G = {S}.pill(UIParent, {{ label = 'my level', gold = true }})")
    assert alpha(wow, "G.edges") == wow.eval(f"{S}.QUIET_GOLD") and ink(wow, "G.label", "gold")
    assert wow.errors == []


def test_the_segmented_switch_the_flat_tab_and_the_lit_lock(wow: WowRuntime):
    """plan-chat-v3.md V27 ("The button look all the same color - hard
    to read"): a switch whose chosen part is filled, a flat tab with a line of its colour and a
    count, a toggle action lit while on. A flat switch is a row of words (the book's tabs): no
    plate, the parts not chosen in the dim ink."""
    boot(wow)
    wow.execute(
        f"""
        LookTest = {{ changed = {{}} }}
        LookTest.seg = {S}.segmented(UIParent, {{
          items = {{ {{ id = 'a', label = 'Inbox' }}, {{ id = 'b', label = 'Switchboard' }} }},
          value = 'a',
          onChange = function(_, id) table.insert(LookTest.changed, id) end,
        }})
        LookTest.flat = {S}.segmented(UIParent, {{ flat = true, value = 'a',
          items = {{ {{ id = 'a', label = 'one' }}, {{ id = 'b', label = 'two' }} }} }})
        LookTest.tab = {S}.tab(UIParent, {{ label = 'Market', count = 3, line = 'tier3', on = true }})
        LookTest.lock = {S}.action(UIParent, {{ icon = 'lock', label = 'Lock', only = true, toggle = true }})
        """
    )
    a, b = "LookTest.seg:Part('a')", "LookTest.seg:Part('b')"
    width = wow.eval("LookTest.seg:GetWidth()")
    assert width >= wow.eval(f"{a}:GetWidth()") + wow.eval(f"{b}:GetWidth()") - 0.5
    assert wow.eval("LookTest.flat.face:IsShown()") is False
    assert wow.eval("LookTest.flat.edges:IsShown()") is False
    assert ink(wow, "LookTest.flat:Part('b').label", "dim")
    # the flat tab: no plate, no frame, the line under the chosen one, the count after it
    assert alpha(wow, "LookTest.tab.face") == 0 and alpha(wow, "LookTest.tab.edges") == 0
    assert wow.eval("LookTest.tab.under:IsShown()") is True
    assert wow.eval(f"{PAINTED}[LookTest.tab.under][1] == {S}.Tok(LookTest.tab, 'tier3')")
    assert wow.eval("LookTest.tab.count:GetText()") == "3"
    assert wow.eval("LookTest.tab.label:GetText()") == "market"  # small capitals as the sections
    # the lock's pictogram alone, dim while off, the accent while on
    assert wow.eval("LookTest.lock.label:GetText()") == ""
    assert tok(wow, "LookTest.lock.icon", "dim")
    wow.execute("LookTest.lock:SetOn(true)")
    assert tok(wow, "LookTest.lock.icon", "accent")
    # a click on the other part chooses it and says so; on the chosen one nothing happens
    wow.execute("LookTest.seg:Part('b'):Click(); LookTest.seg:Part('b'):Click()")
    assert wow.eval("LookTest.changed[1]") == "b" and wow.eval("#LookTest.changed") == 1
    assert wow.eval("LookTest.seg:Part('b').fill:IsShown()") is True
    wow.execute("LookTest.seg:SetValue(nil)")  # none chosen: no part filled
    assert wow.eval("LookTest.seg:Part('a').fill:IsShown()") is False
    assert wow.eval("LookTest.seg:Part('b').fill:IsShown()") is False
    wow.execute("LookTest.tab:SetOn(false)")
    assert wow.eval("LookTest.tab.under:IsShown()") is False
    assert ink(wow, "LookTest.tab.label", "dim")
    assert wow.errors == []


def test_a_dashed_chip_keeps_its_round_ends(wow: WowRuntime):
    """The board's dashed outline (book-look.md section 11, the chip "unconfirmed"; W4): the
    straight top and bottom become dashes in the edge's colour, the round ends stay; a pooled
    chip drawn again without it gets its lines back."""
    boot(wow)
    wow.execute(
        f"""
        D = {S}.pill(UIParent, {{ small = true, label = 'unconfirmed', count = 200, dashed = true }})
        """
    )
    shown = "(function() local n = 0 for _, d in ipairs(D.dashes) do if d:IsShown() then n = n + 1 end end return n end)()"
    assert wow.eval("D.edges:Piece(5):IsShown()") is False
    assert wow.eval("D.edges:Piece(6):IsShown()") is False
    assert wow.eval("D.edges:Piece(1):IsShown()") is True  # a round end
    width, r = wow.eval("D:GetWidth()"), wow.eval("D.edges.r")
    per_side = int((width - 2 * r + 3) // 7)
    assert per_side > 0 and wow.eval(shown) == 2 * per_side
    assert wow.eval(f"{PAINTED}[D.dashes[1]][1] == {PAINTED}[D.edges][1]") is True
    wow.execute("D.spec = { small = true, label = 'Wetlands' }; Bastians.UI.Style.Draw(D)")
    assert wow.eval(shown) == 0 and wow.eval("D.edges:Piece(5):IsShown()") is True
    assert wow.errors == []


def test_a_pill_inside_the_books_table_takes_its_gold(wow: WowRuntime):
    """core.md "Round corners": a pill is round at both ends ("the
    buttons are rounder"); `small` makes a chip: S.G.chip high, the small text. Inside a palette
    of its own (the book's dark table) the chosen one takes that palette's accent, its gold."""
    boot(wow)
    wow.execute(
        f"""
        HOST = CreateFrame("Frame", nil, UIParent)
        HOST.palette = {S}.FolioPalette()
        F = {S}.pill(HOST, {{ small = true, label = 'farming', on = true }})
        Q = {S}.pill(HOST, {{ small = true, label = 'fishing' }})
        P = {S}.pill(UIParent, {{ label = 'Vendor', count = 3 }})
        C = {S}.pill(UIParent, {{ small = true, label = 'Wetlands', count = 3, on = true }})
        """
    )
    assert wow.eval("P:GetHeight()") == 26 and wow.eval("P.face.r") == 13
    assert wow.eval("P.edges.r") == 13
    assert wow.eval("C:GetHeight()") == 22 and wow.eval("C.face.r") == 11
    assert wow.eval("(select(2, C.label:GetFont()))") == 11
    assert wow.eval("(select(2, P.label:GetFont()))") == 12
    assert tok(wow, "F.face", "folioGold") and ink(wow, "F.label", "folioGoldInk")
    assert ink(wow, "Q.label", "folioText")
    assert wow.eval(f"{S}.Tok(Q, 'line') == {S}.C.folioRule") is True
    assert wow.errors == []


def test_a_heading_with_a_role_of_its_own_keeps_its_face_and_size(wow: WowRuntime):
    """R4.14 (Forever, 17.11.2026: the book's name drawn in Morpheus at 17 for its display face at
    18): a font, a text size or a theme change draws a heading again; one that was given a role
    (S.SetRole) keeps that role's face and the size set for it."""
    boot(wow)
    wow.execute(
        f"""
        local S = {S}
        H = S.heading(UIParent, 15, 17, S.C.headerText)
        PLAIN = S.heading(UIParent, 15, 17, S.C.headerText)
        S.SetRole(H, "bookDisplay")
        S.setSize(H, 18)
        """
    )
    display = wow.eval(f"{S}.BOOK_FONTS.bookDisplay")
    assert wow.eval("(H:GetFont())") == display and wow.eval("(select(2, H:GetFont()))") == 18
    core = "Bastians:GetModule('Core').db.profile"
    for change in (
        f"{S}.applyFont()",
        f"{core}.headingFont = 'Fonts\\\\MORPHEUS.TTF'; {S}.ApplySkin()",
        f"{S}.ApplyTheme('parchment')",
        f"{S}.applyHeading(H)",
    ):
        wow.execute(change)
        assert wow.eval("(H:GetFont())") == display, change
        assert wow.eval("(select(2, H:GetFont()))") == 18, change
    # a plain heading follows the setting: the heading font at its big size
    assert wow.eval("(PLAIN:GetFont())") == wow.eval(f"{S}.headingFont()")
    assert wow.eval("(select(2, PLAIN:GetFont()))") == 17
    assert wow.errors == []
