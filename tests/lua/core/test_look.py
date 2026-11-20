"""The look engine (ADR 0046, 01.11.2026): widgets declared, drawn by the look in force; the
action button with its pictogram and text, the kind tile on the group's colour, the geometry
tokens of the theme, a preset change redrawing every widget; the look named by the preset's
`look`, the Glass and Parchment renderers (plan-round4 H4)."""

from harness import WowRuntime

S = "Bastians.UI.Style"
CORE = "Bastians:GetModule('Core')"
SET = "Bastians.UI.Settings"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start("Bastians_Core")
    wow.run_frames(3)
    return wow


def test_the_theme_carries_geometry_and_tile_tokens(wow: WowRuntime):
    boot(wow)
    g = wow.eval(f"{S}.G")
    assert g.action == 26 and g.actionRow == 22 and g.tile == 18 and g.tileBig == 26 and g.gap == 6
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
    assert wow.eval(f"{S}.LookId()") == "modern"
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


def test_pills_tabs_sections_and_toggles_in_both_looks(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"""
        LookTest = {{ changed = {{}} }}
        LookTest.pill = {S}.pill(UIParent, {{ kind = 'vendor', label = 'Vendor', count = 145, onClick = function() LookTest.picked = true end }})
        LookTest.tab = {S}.tab(UIParent, {{ kind = 'service', label = 'Trade', on = true }})
        LookTest.sec = {S}.section(UIParent, {{ icon = 'note', title = 'My notes' }})
        LookTest.tog = {S}.toggle(UIParent, {{ on = false, onChange = function(_, on) table.insert(LookTest.changed, on) end }})
        """
    )
    assert wow.eval("LookTest.pill:GetHeight()") == 26
    assert wow.eval("LookTest.pill.count:GetText()") == "145"
    assert wow.eval("LookTest.pill.tile.spec.kind") == "vendor"
    wow.execute("LookTest.pill:Click()")
    assert wow.eval("LookTest.picked") is True
    wow.execute("LookTest.pill:SetOn(true) LookTest.pill:SetCount(9)")
    assert wow.eval("LookTest.pill.count:GetText()") == "9"
    assert wow.eval("LookTest.tab:GetHeight()") == 26
    assert wow.eval("LookTest.tab.under:IsShown()") is True
    wow.execute("LookTest.tab:SetOn(false) LookTest.tab:SetBadge(3)")
    assert wow.eval("LookTest.tab.under:IsShown()") is False
    assert wow.eval("LookTest.tab.badge.text:GetText()") == "3"
    assert wow.eval("LookTest.sec.title:GetText()") == "MY NOTES"  # Modern: small capitals
    assert wow.eval("LookTest.sec.rule:IsShown()") is False
    assert wow.eval("LookTest.tog:GetWidth()") == 34
    wow.execute("LookTest.tog:Click()")
    assert wow.eval("LookTest.tog.spec.on") is True
    assert list(wow.eval("LookTest.changed").values()) == [True]
    # the WoW look: the section's heading face and rule, the toggle as a box with a cross
    assert wow.eval(f"{SET}.ApplyPreset({CORE}, 'wow')") is True
    assert wow.eval("LookTest.sec.title:GetText()") == "My notes"
    assert wow.eval("LookTest.sec.rule:IsShown()") is True
    assert wow.eval("LookTest.tog:GetWidth()") == 18
    assert wow.eval("LookTest.tog.mark:IsShown()") is True
    assert wow.eval("LookTest.tab:GetHeight()") == 24
    assert wow.errors == []


def test_the_wow_preset_redraws_every_widget_and_back(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"LookTest = {{}} LookTest.b = {S}.action(UIParent, {{ icon = 'map', label = 'Map' }})"
    )
    assert wow.eval(f"{SET}.ApplyPreset({CORE}, 'wow')") is True
    assert wow.eval(f"{S}.LookId()") == "wow"
    assert wow.eval("LookTest.b:GetHeight()") == 24  # the WoW geometry
    assert wow.eval("LookTest.b.gameArt.up[2]:GetTexture()") == wow.eval(f"{S}.BUTTON_UP")
    assert wow.eval("LookTest.b.gameArt.up[2]:IsShown()") is True
    assert wow.eval("LookTest.b.face:IsShown()") is False
    assert wow.eval(f"{SET}.ApplyPreset({CORE}, 'modern-dark')") is True
    assert wow.eval("LookTest.b:GetHeight()") == 26
    assert wow.eval("LookTest.b.face:IsShown()") is True
    assert (
        wow.eval("LookTest.b.gameArt.up[2]:IsShown()") is False
    )  # the red slices go with the look
    assert wow.errors == []


PAINTED = f"{S}.painted"


def test_the_look_is_the_presets_and_an_old_profile_reads_the_buttons_switch(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f"{S}.LookId()") == "modern"
    assert wow.eval(f"{SET}.ApplyPreset({CORE}, 'wow')") is True
    assert wow.eval(f"{CORE}.db.profile.look") == "wow" and wow.eval(f"{S}.LookId()") == "wow"
    # a profile saved before `look` existed: the game's buttons switch decides (ADR 0038)
    wow.execute(f"{CORE}.db.profile.look = nil")
    assert wow.eval(f"{S}.LookId()") == "wow"
    wow.execute(f"{CORE}.db.profile.gameButtons = false")
    assert wow.eval(f"{S}.LookId()") == "modern"
    wow.execute(f"{CORE}.db.profile.look = 'nonsense'")
    assert wow.eval(f"{S}.LookId()") == "modern"  # an unknown look never breaks the drawing
    assert wow.errors == []


def test_glass_puts_every_text_on_a_plate_and_rounds_the_corners(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"""
        LookTest = {{}}
        LookTest.b = {S}.action(UIParent, {{ icon = 'map', label = 'Map' }})
        LookTest.p = {S}.pill(UIParent, {{ kind = 'vendor', label = 'Vendor', gold = true }})
        LookTest.t = {S}.tile(UIParent, 'quest')
        LookTest.w = Bastians.UI.Window('GlassTestFrame', {{ title = 'G' }}); LookTest.w:Show()
        """
    )
    # Modern: a quiet action has no face, the theme's radii
    assert wow.eval(f"{PAINTED}[LookTest.b.face][2]") == 0
    assert wow.eval(f"{S}.SHAPE.radius") == 6 and wow.eval(f"{S}.SHAPE.radiusSmall") == 4
    assert wow.eval(f"{PAINTED}[LookTest.w.frame.bg][2]") == 1
    assert wow.eval(f"{SET}.ApplyPreset({CORE}, 'glass')") is True
    assert wow.eval(f"{S}.LookId()") == "glass" and wow.eval(f"{S}.ThemeId()") == "teal"
    # 10 px windows, 8 px buttons; the shapes laid out again with them
    assert wow.eval(f"{S}.SHAPE.radius") == 10 and wow.eval(f"{S}.SHAPE.radiusSmall") == 8
    assert wow.eval("LookTest.w.frame.bg:Radius()") == 10
    # the plate at 72 % with the sheen over it, no edge until the mouse comes
    assert wow.eval(f"{PAINTED}[LookTest.b.face][2]") == 0.72
    assert wow.eval("LookTest.b.sheen:IsShown()") is True
    assert wow.eval(f"{PAINTED}[LookTest.b.sheen][2]") == 0.05
    assert wow.eval(f"{PAINTED}[LookTest.b.edges][2]") == 0
    wow.execute("LookTest.b:GetScript('OnEnter')(LookTest.b)")
    assert wow.eval(f"{PAINTED}[LookTest.b.edges][2]") == 0.35
    wow.execute("LookTest.b:GetScript('OnLeave')(LookTest.b)")
    assert wow.eval(f"{PAINTED}[LookTest.b.edges][2]") == 0
    assert wow.eval(f"{PAINTED}[LookTest.p.face][2]") == 0.36  # a quiet pill: half the plate
    assert wow.eval(f"{PAINTED}[LookTest.t.edges][2]") == 0  # tiles without edges
    # the window ground is capped at 75 % whatever the opacity setting
    assert wow.eval(f"{PAINTED}[LookTest.w.frame.bg][2]") == 0.75
    # back to Modern: the sheen hides, the theme's radii return, the ground is opaque again
    assert wow.eval(f"{SET}.ApplyPreset({CORE}, 'modern-dark')") is True
    assert wow.eval("LookTest.b.sheen:IsShown()") is False
    assert wow.eval(f"{S}.SHAPE.radius") == 6 and wow.eval("LookTest.w.frame.bg:Radius()") == 6
    assert wow.eval(f"{PAINTED}[LookTest.w.frame.bg][2]") == 1
    assert wow.errors == []


def test_parchment_squares_the_tiles_and_writes_no_gold(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"""
        LookTest = {{}}
        LookTest.b = {S}.action(UIParent, {{ icon = 'map', label = 'Map', boxed = true }})
        LookTest.p = {S}.pill(UIParent, {{ kind = 'vendor', label = 'Vendor', gold = true }})
        LookTest.t = {S}.tile(UIParent, 'quest')
        LookTest.sec = {S}.section(UIParent, {{ icon = 'note', title = 'My notes' }})
        LookTest.w = Bastians.UI.Window('PaperTestFrame', {{ title = 'P' }}); LookTest.w:Show()
        """
    )
    assert wow.eval("LookTest.t.face:Radius()") == 4
    assert wow.eval(f"{SET}.ApplyPreset({CORE}, 'parchment')") is True
    assert wow.eval(f"{S}.LookId()") == "parchment" and wow.eval(f"{S}.ThemeId()") == "parchment"
    assert wow.eval(f"{CORE}.db.profile.gameFrames") is False  # never on the rock ground
    # square tiles with a sepia edge; the buttons keep the theme's small radius
    assert wow.eval(f"{S}.SHAPE.tile") == 0 and wow.eval("LookTest.t.face:Radius()") == 0
    assert wow.eval(f"{S}.SHAPE.radiusSmall") == 4 and wow.eval("LookTest.b.face:Radius()") == 4
    assert wow.eval(f"{PAINTED}[LookTest.t.edges][1] == {S}.C.muted") is True
    assert wow.eval(f"{PAINTED}[LookTest.b.edges][1] == {S}.C.muted") is True
    # a choice of value reads in the accent, not in gold
    assert wow.eval(f"{S}.inked[LookTest.p.label] == {S}.C.accent") is True
    # section titles in their own case over a rule; serif headings from the preset
    assert wow.eval("LookTest.sec.title:GetText()") == "My notes"
    assert wow.eval("LookTest.sec.rule:IsShown()") is True
    assert wow.eval("(LookTest.w.title:GetFont())") == wow.eval(f"{S}.SERIF_FONT")
    assert wow.eval(f"{SET}.ApplyPreset({CORE}, 'modern-light')") is True
    assert wow.eval(f"{S}.SHAPE.tile") == 4 and wow.eval("LookTest.t.face:Radius()") == 4
    assert wow.eval(f"{S}.inked[LookTest.p.label] == {S}.C.gold") is True
    assert wow.eval("(LookTest.w.title:GetFont())") != wow.eval(f"{S}.SERIF_FONT")
    assert wow.errors == []


def test_a_chosen_pill_is_filled_in_every_look(wow: WowRuntime):
    """ "selected filter need to be dramatically different from
    unselected": the chosen pill is filled with the accent (WoW: the game's gold), its words and
    count in the ground's ink; the mouse never takes the fill away."""
    boot(wow)
    wow.execute(
        f"""
        LookTest = {{}}
        LookTest.on = {S}.pill(UIParent, {{ label = 'Rares', count = 4, on = true }})
        LookTest.off = {S}.pill(UIParent, {{ label = 'Gold', count = 2 }})
        """
    )

    def filled(fill: str) -> None:
        assert wow.eval(f"{PAINTED}[LookTest.on.face][1] == {fill}") is True
        assert wow.eval(f"{S}.inked[LookTest.on.label] == {S}.C.bg") is True
        assert wow.eval(f"{S}.inked[LookTest.on.count] == {S}.C.bg") is True
        assert wow.eval(f"{PAINTED}[LookTest.off.face][1] == {fill}") is False
        assert wow.eval(f"{S}.inked[LookTest.off.label] == {S}.C.bg") is False

    filled(f"{S}.C.accent")
    wow.execute("LookTest.on:GetScript('OnEnter')(LookTest.on)")
    assert wow.eval(f"{PAINTED}[LookTest.on.face][1] == {S}.C.accent") is True
    wow.execute("LookTest.on:GetScript('OnLeave')(LookTest.on)")
    filled(f"{S}.C.accent")
    assert wow.eval(f"{SET}.ApplyPreset({CORE}, 'wow')") is True
    filled(f"{S}.Palette('blizzard').C.gold")
    assert wow.eval(f"{SET}.ApplyPreset({CORE}, 'parchment')") is True
    filled(f"{S}.C.accent")
    assert wow.eval(f"{SET}.ApplyPreset({CORE}, 'glass')") is True
    filled(f"{S}.C.accent")
    wow.execute("LookTest.on:SetOn(false)")
    assert wow.eval(f"{PAINTED}[LookTest.on.face][1] == {S}.C.accent") is False
    assert wow.errors == []


def test_an_unchosen_pill_is_quiet_and_a_flat_switch_has_no_plate(wow: WowRuntime):
    """ "quiet chips, every app": an unchosen pill has no plate and its
    edge the line token at its own faint opacity; the plate comes under the mouse. A `flat`
    segmented switch shows its words alone and fills the chosen part."""
    boot(wow)
    wow.execute(
        f"""
        LookTest = {{}}
        LookTest.p = {S}.pill(UIParent, {{ label = 'Gold', count = 2 }})
        LookTest.g = {S}.pill(UIParent, {{ label = 'my level', gold = true }})
        LookTest.s = {S}.segmented(UIParent, {{ flat = true, value = 'a',
          items = {{ {{ id = 'a', label = 'one' }}, {{ id = 'b', label = 'two' }} }} }})
        """
    )
    for preset in ("modern-dark", "wow", "parchment"):
        assert wow.eval(f"{SET}.ApplyPreset({CORE}, '{preset}')") is True, preset
        assert wow.eval(f"{PAINTED}[LookTest.p.face][2]") == 0, preset
        assert wow.eval(f"{S}.painted[LookTest.p.edges][2]") != 1, preset
        assert wow.eval(f"{S}.inked[LookTest.p.label] == {S}.C.bg") is False, preset
    wow.eval(f"{SET}.ApplyPreset({CORE}, 'modern-dark')")
    assert wow.eval(f"{PAINTED}[LookTest.p.edges][2]") is None  # the line token's own 10 %
    assert wow.eval(f"{PAINTED}[LookTest.g.edges][2]") == wow.eval(f"{S}.QUIET_GOLD")
    wow.execute("LookTest.p:GetScript('OnEnter')(LookTest.p)")
    assert wow.eval(f"{PAINTED}[LookTest.p.face][2]") == 1
    wow.execute("LookTest.p:GetScript('OnLeave')(LookTest.p)")
    assert wow.eval(f"{PAINTED}[LookTest.p.face][2]") == 0
    assert wow.eval("LookTest.s.face:IsShown()") is False
    assert wow.eval("LookTest.s.edges:IsShown()") is False
    assert wow.eval("LookTest.s:Part('a').fill:IsShown()") is True
    assert wow.eval("LookTest.s:Part('b').fill:IsShown()") is False
    assert wow.errors == []


def test_the_chosen_tab_wears_the_accent_frame(wow: WowRuntime):
    """ "hard to see what is menu tabs, what is text and what is active
    tab": the chosen tab reads in the accent inside an accent frame, the others in dim."""
    boot(wow)
    wow.execute(
        f"LookTest = {{}} LookTest.t = {S}.tab(UIParent, {{ kind = 'service', label = 'Trade', on = true }})"
    )
    assert wow.eval(f"{PAINTED}[LookTest.t.edges][2]") == 0.9
    assert wow.eval(f"{S}.inked[LookTest.t.label] == {S}.C.accent") is True
    wow.execute("LookTest.t:SetOn(false)")
    assert wow.eval(f"{PAINTED}[LookTest.t.edges][2]") == 0
    assert wow.eval(f"{S}.inked[LookTest.t.label] == {S}.C.dim") is True
    # a boxed Modern action: an accent plate with the pictogram in the accent
    wow.execute(
        f"LookTest.b = {S}.action(UIParent, {{ icon = 'map', label = 'Map', boxed = true }})"
    )
    assert wow.eval(f"{PAINTED}[LookTest.b.face][1] == {S}.C.accent") is True
    assert wow.eval(f"{PAINTED}[LookTest.b.face][2]") == 0.16
    assert wow.eval(f"{PAINTED}[LookTest.b.icon][1] == {S}.C.accent") is True
    assert wow.errors == []


def test_the_segmented_switch_the_flat_tab_and_the_lit_lock_in_every_look(wow: WowRuntime):
    """plan-chat-v3.md V27 ("The button look all the same color - hard
    to read"): a switch whose chosen part is filled, a flat tab with a line of its colour and a
    count, a toggle action lit while on; each drawn by every look."""
    boot(wow)
    wow.execute(
        f"""
        LookTest = {{ changed = {{}} }}
        LookTest.seg = {S}.segmented(UIParent, {{
          items = {{ {{ id = 'a', label = 'Inbox' }}, {{ id = 'b', label = 'Switchboard' }} }},
          value = 'a',
          onChange = function(_, id) table.insert(LookTest.changed, id) end,
        }})
        LookTest.tab = {S}.tab(UIParent, {{ label = 'Market', count = 3, line = 'tier3', on = true }})
        LookTest.lock = {S}.action(UIParent, {{ icon = 'lock', label = 'Lock', only = true, toggle = true }})
        """
    )
    for preset in ("modern-dark", "glass", "parchment", "wow"):
        assert wow.eval(f"{SET}.ApplyPreset({CORE}, '{preset}')") is True
        a, b = "LookTest.seg:Part('a')", "LookTest.seg:Part('b')"
        assert wow.eval(f"{a}.fill:IsShown()") is True, preset
        assert wow.eval(f"{b}.fill:IsShown()") is False, preset
        assert wow.eval(f"{S}.inked[{a}.label] ~= {S}.inked[{b}.label]") is True, preset
        width = wow.eval("LookTest.seg:GetWidth()")
        assert width >= wow.eval(f"{a}:GetWidth()") + wow.eval(f"{b}:GetWidth()") - 0.5, preset
        # the flat tab: no plate, no frame, the line under the chosen one, the count after it
        assert wow.eval(f"{PAINTED}[LookTest.tab.face][2]") == 0, preset
        assert wow.eval(f"{PAINTED}[LookTest.tab.edges][2]") == 0, preset
        assert wow.eval("LookTest.tab.under:IsShown()") is True, preset
        assert wow.eval(f"{PAINTED}[LookTest.tab.under][1] == {S}.Tok(LookTest.tab, 'tier3')")
        assert wow.eval("LookTest.tab.count:GetText()") == "3", preset
        # the lock's pictogram alone, dim while off
        assert wow.eval("LookTest.lock.label:GetText()") == "", preset
        assert wow.eval(f"{PAINTED}[LookTest.lock.icon][1] == {S}.Tok(LookTest.lock, 'dim')")
    upper = {"modern-dark": "MARKET", "glass": "MARKET", "parchment": "Market", "wow": "Market"}
    for preset, label in upper.items():
        wow.eval(f"{SET}.ApplyPreset({CORE}, '{preset}')")
        assert wow.eval("LookTest.tab.label:GetText()") == label, preset  # capitals as the sections
    wow.eval(f"{SET}.ApplyPreset({CORE}, 'modern-dark')")
    wow.execute("LookTest.lock:SetOn(true)")
    assert wow.eval(f"{PAINTED}[LookTest.lock.icon][1] == {S}.C.accent") is True
    # a click on the other part chooses it and says so; on the chosen one nothing happens
    wow.execute("LookTest.seg:Part('b'):Click(); LookTest.seg:Part('b'):Click()")
    assert wow.eval("LookTest.changed[1]") == "b" and wow.eval("#LookTest.changed") == 1
    assert wow.eval("LookTest.seg:Part('b').fill:IsShown()") is True
    wow.execute("LookTest.seg:SetValue(nil)")  # none chosen: no part filled
    assert wow.eval("LookTest.seg:Part('a').fill:IsShown()") is False
    assert wow.eval("LookTest.seg:Part('b').fill:IsShown()") is False
    wow.execute("LookTest.tab:SetOn(false)")
    assert wow.eval("LookTest.tab.under:IsShown()") is False
    assert wow.eval(f"{S}.inked[LookTest.tab.label] == {S}.C.dim") is True
    assert wow.errors == []


def test_a_pill_is_round_at_both_ends_and_a_chip_is_a_small_one(wow: WowRuntime):
    """core.md "Round corners": a pill is round at both ends in every look (owner, Forever
    17.11.2026, the book beside its concept board: "the buttons are rounder"; until then the
    theme's corner radius). `small` makes a chip: S.G.chip high, the small text. In the WoW look
    the chosen one is the game's gold, inside the book's dark table that table's gold."""
    boot(wow)
    wow.execute(
        f"""
        P = {S}.pill(UIParent, {{ label = 'Vendor', count = 3 }})
        C = {S}.pill(UIParent, {{ small = true, label = 'Wetlands', count = 3, on = true }})
        HOST = CreateFrame("Frame", nil, UIParent)
        HOST.palette = {S}.FolioPalette()
        F = {S}.pill(HOST, {{ small = true, label = 'farming', on = true }})
        Q = {S}.pill(HOST, {{ small = true, label = 'fishing' }})
        """
    )
    assert wow.eval(f"{S}.G.chip") == 22
    assert wow.eval("P:GetHeight()") == 26 and wow.eval("P.face.r") == 13
    assert wow.eval("P.edges.r") == 13
    assert wow.eval("C:GetHeight()") == 22 and wow.eval("C.face.r") == 11
    assert wow.eval("(select(2, C.label:GetFont()))") == 11
    assert wow.eval("(select(2, P.label:GetFont()))") == 12
    for preset in ("wow", "glass", "parchment"):
        assert wow.eval(f"{SET}.ApplyPreset({CORE}, '{preset}')") is True
        assert wow.eval("P.face.r") == 13 and wow.eval("C.face.r") == 11, preset
    wow.execute(f"{SET}.ApplyPreset({CORE}, 'wow')")
    gold = f"{S}.Palette('blizzard').C.gold"
    assert wow.eval(f"{S}.painted[C.face][1] == {gold}") is True
    assert wow.eval(f"{S}.painted[F.face][1] == {S}.C.folioGold") is True
    assert wow.eval(f"{S}.inked[F.label] == {S}.C.folioGoldInk") is True
    assert wow.eval(f"{S}.inked[Q.label] == {S}.C.folioText") is True
    assert wow.eval(f"{S}.Tok(Q, 'line') == {S}.C.folioRule") is True
    assert wow.errors == []


def test_a_heading_with_a_role_of_its_own_keeps_its_face_and_size(wow: WowRuntime):
    """R4.14 (Forever, 17.11.2026: the book's name drawn in Morpheus at 17 for its display face at
    18): a font, a text size or a look change draws a heading again; one that was given a role
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
    for change in (f"{S}.applyFont()", f"{SET}.ApplyPreset({CORE}, 'wow')", f"{S}.applyHeading(H)"):
        wow.execute(change)
        assert wow.eval("(H:GetFont())") == display, change
        assert wow.eval("(select(2, H:GetFont()))") == 18, change
    # a plain heading follows the look as before: the WoW look's heading font at its big size
    assert wow.eval("(PLAIN:GetFont())") == wow.eval(f"{S}.headingFont()")
    assert wow.eval("(select(2, PLAIN:GetFont()))") == 17
    assert wow.errors == []
