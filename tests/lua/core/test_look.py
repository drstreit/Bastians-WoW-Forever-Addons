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
    assert wow.eval(f"{PAINTED}[LookTest.p.face][2]") == 0.72
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
