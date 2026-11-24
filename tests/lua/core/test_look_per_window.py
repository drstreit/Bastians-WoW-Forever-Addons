"""A theme per window (ADR 0046's open point; plan-chat-v3.md §9, package V13): a frame takes values
of its own (S.SetFramePreset), its theme as the palette, whatever the suite's; its widgets and
window frame follow it, a part under it with a palette of its own keeps that one, and nil puts the
suite's back. ~~Its renderer as the look, its corners~~ (until 20.11.2026: one look, ADR 0084). Since V17 (13.11.2026) its fonts too: a kit text has a role (text, heading,
label, number), each role the font its window's preset names, else the suite's."""

from harness import WowRuntime

S = "Bastians.UI.Style"
SET = "Bastians.UI.Settings"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start("Bastians_Core")
    wow.run_frames(3)
    return wow


def test_the_themes_are_there_for_an_app(wow: WowRuntime):
    """ADR 0084: a window of its own wears a theme; an old preset's id still names one."""
    boot(wow)
    assert wow.eval(f"{SET}.PresetValues('wow').theme") == "folio"
    assert wow.eval(f"{SET}.PresetValues('glass').theme") == "folio"
    assert wow.eval(f"{SET}.PresetValues('parchment').theme") == "parchment"
    assert wow.eval(f"{SET}.PresetValues('nonsense')") is None
    names = dict(wow.eval(f"{SET}.Presets()").items())
    assert names["folio"] == "Folio" and names["parchment"] == "Paper"
    assert "wow" not in names and "custom" not in names


def test_a_frame_draws_in_a_theme_of_its_own(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"""
        T = {{}}
        T.f = CreateFrame("Frame", nil, UIParent)
        T.child = CreateFrame("Frame", nil, T.f)
        T.b = {S}.action(T.child, {{ icon = "close", label = "Close" }})
        T.tex = {S}.fill(T.child, {S}.C.panel)
        {S}.SetFramePreset(T.f, {SET}.PresetValues("parchment"))
        """
    )
    assert wow.eval(f"{S}.LookOf(T.b)") == "book"  # one look, whatever the frame's theme
    assert wow.eval(f"{S}.PaletteOf(T.b).id") == "parchment"
    # what the kit drew under it took the palette's token
    assert wow.eval(f"{S}.painted[T.tex][1] == {S}.Palette('parchment').C.panel") is True
    assert wow.eval(f"{S}.painted[T.b.edges][1] == {S}.Palette('parchment').C.line") is True
    # nil: the suite's again, the tokens back to the theme's
    wow.execute(f"{S}.SetFramePreset(T.f, nil)")
    assert wow.eval(f"{S}.PaletteOf(T.b)") is None
    assert wow.eval(f"{S}.painted[T.tex][1] == {S}.C.panel") is True
    assert wow.errors == []


def test_a_part_with_a_palette_of_its_own_keeps_it(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"""
        T = {{}}
        T.f = CreateFrame("Frame", nil, UIParent)
        T.area = CreateFrame("Frame", nil, T.f)
        T.area.palette = {S}.Palette("blizzard")
        T.mark = T.area:CreateTexture()
        {S}.tint(T.mark, {S}.Palette("blizzard").C.tier0, 1)
        {S}.SetFramePreset(T.f, {SET}.PresetValues("parchment"))
        {S}.SetFramePreset(T.f, nil)
        """
    )
    # the window went from Paper back to the theme; the area's own mark, drawn in a palette of
    # its own, stays it
    assert wow.eval(f"{S}.painted[T.mark][1] == {S}.Palette('blizzard').C.tier0") is True
    assert wow.errors == []


def test_corners_are_the_suites_in_every_frame(wow: WowRuntime):
    """~~A frame of a look of its own took that look's corners (Glass rounder)~~ until 20.11.2026:
    one look has one set of corners (ADR 0084)."""
    boot(wow)
    wow.execute(
        f"""
        T = {{}}
        T.f = CreateFrame("Frame", nil, UIParent)
        T.f:SetSize(200, 100)
        {S}.SetFramePreset(T.f, {SET}.PresetValues("glass"))
        """
    )
    assert wow.eval(f"{S}.RadiusOf(T.f, 'radius')") == wow.eval(f"{S}.SHAPE.radius") == 6
    assert wow.eval(f"{S}.RadiusOf(T.f, 'radiusSmall')") == 4


def test_a_window_takes_its_own_frame_or_the_suites(wow: WowRuntime):
    """A window's own values name the game's frame where they say (an old WoW preset's id: on);
    else it follows the suite's switch (since 20.11.2026, ADR 0084: one switch beside the theme)."""
    boot(wow)
    wow.execute(
        """
        T = {}
        T.win = Bastians.UI.Window("TestLookWindow", { title = "Test" })
        """
    )
    assert wow.eval("T.win:Skin('gameFrames')") == wow.eval(f"{S}.Skin('gameFrames')") is True
    wow.execute(f"T.win:SetPreset({SET}.PresetValues('parchment'))")
    assert wow.eval("T.win:Skin('gameFrames')") is True  # the suite's
    wow.execute("Bastians:GetModule('Core').db.profile.gameFrames = false")
    assert wow.eval("T.win:Skin('gameFrames')") is False
    wow.execute(f"T.win:SetPreset({SET}.PresetValues('wow'))")
    assert wow.eval("T.win:Skin('gameFrames')") is True  # its own says so
    assert wow.eval("T.win.frame.look") is None
    wow.execute("T.win:SetPreset(nil)")
    assert wow.eval("T.win.frame.presetValues") is None
    assert wow.errors == []


def test_a_list_draws_in_the_palette_its_window_has_now(wow: WowRuntime):
    boot(wow)
    wow.execute(
        """
        T = {}
        T.f = CreateFrame("Frame", nil, UIParent)
        T.list = Bastians.UI.VirtualList.New(T.f, { kinds = {} })
        """
    )
    assert wow.eval("T.list:Palette()") is None
    wow.execute(f"{S}.SetFramePreset(T.f, {SET}.PresetValues('parchment'))")
    assert wow.eval("T.list:Palette().id") == "parchment"


FONTS = "Interface\\AddOns\\Bastians_Core\\Fonts\\"
OWN = {
    "font": FONTS + "Inter.ttf",
    "headingFont": FONTS + "Cinzel.ttf",
    "labelFont": FONTS + "Oswald.ttf",
    "numberFont": FONTS + "IBMPlexMono.ttf",
}


def fonts_frame(wow: WowRuntime) -> None:
    """A frame with a text of each role, a section, a tab and a pill under it."""
    wow.execute(
        f"""
        T = {{}}
        T.f = CreateFrame("Frame", nil, UIParent)
        T.text = {S}.text(T.f, 12)
        T.num = {S}.SetRole({S}.text(T.f, 11), "number")
        T.head = {S}.heading(T.f, 14, 16)
        T.sec = {S}.section(T.f, {{ title = "Needs you" }})
        T.tab = {S}.tab(T.f, {{ label = "Market" }})
        T.pill = {S}.pill(T.f, {{ label = "Guild", count = 3 }})
        """
    )


def font_of(wow: WowRuntime, fs: str) -> tuple:
    path, size, _ = wow.eval(f"{{ ({fs}):GetFont() }}").values()
    return path, size


def own_values(wow: WowRuntime) -> str:
    """The modern-dark preset with the four fonts of OWN, as an app builds its window's values."""
    pairs = ", ".join(f"{k} = [[{v}]]" for k, v in OWN.items())  # long strings: no escapes
    wow.execute(
        f"""
        T.values = {{}}
        for k, v in pairs({SET}.PresetValues("modern-dark")) do T.values[k] = v end
        for k, v in pairs({{ {pairs} }}) do T.values[k] = v end
        """
    )
    return "T.values"


def test_a_window_draws_its_texts_in_its_presets_fonts(wow: WowRuntime):
    boot(wow)
    fonts_frame(wow)
    suite = wow.eval(f"{S}.font()")
    # the suite's labels wear the book's small capitals (ADR 0084 decision 7, W5)
    caps = wow.eval(f"{S}.BOOK_FONTS.bookCaps")
    assert font_of(wow, "T.sec.title")[0] == caps
    wow.execute(f"{S}.SetFramePreset(T.f, {own_values(wow)})")
    scale = wow.eval(f"{S}.scale()")
    assert font_of(wow, "T.text")[0] == OWN["font"]
    assert font_of(wow, "T.num")[0] == OWN["numberFont"]
    assert font_of(wow, "T.head")[0] == OWN["headingFont"]
    assert font_of(wow, "T.head")[1] == round(16 * scale)  # a heading face of its own: bigSize
    # a section's title and a tab's label are labels, a pill's count a number
    assert font_of(wow, "T.sec.title") == (OWN["labelFont"], round((11 + 2) * scale))
    assert font_of(wow, "T.tab.label")[0] == OWN["labelFont"]
    assert font_of(wow, "T.pill.count")[0] == OWN["numberFont"]
    assert font_of(wow, "T.pill.label")[0] == OWN["font"]
    # a text made later under the frame takes them at once
    wow.execute(f"T.late = {S}.SetRole({S}.text(T.f, 10), 'number')")
    assert font_of(wow, "T.late")[0] == OWN["numberFont"]
    # a frame elsewhere keeps the suite's
    assert font_of(wow, f"{S}.text(CreateFrame('Frame', nil, UIParent), 12)")[0] == suite
    # nil: the suite's fonts again, the label at its own size
    wow.execute(f"{S}.SetFramePreset(T.f, nil)")
    assert font_of(wow, "T.num")[0] == suite
    assert font_of(wow, "T.sec.title") == (caps, round(11 * scale))
    assert wow.errors == []


def test_label_and_number_fall_back_to_the_windows_text_font(wow: WowRuntime):
    boot(wow)
    fonts_frame(wow)
    values = own_values(wow)
    wow.execute(f"{values}.labelFont = nil; {values}.numberFont = nil")
    wow.execute(f"{S}.SetFramePreset(T.f, {values})")
    assert font_of(wow, "T.sec.title")[0] == OWN["font"]
    assert font_of(wow, "T.num")[0] == OWN["font"]
    assert font_of(wow, "T.pill.count")[0] == OWN["font"]
    assert wow.errors == []


def test_the_suites_faces_reach_every_window_whatever_a_profile_still_holds(wow: WowRuntime):
    """ADR 0084 decision 7 (W5, 23.11.2026): labels in the book's small capitals, headings in its
    display face, numbers and the body in the reader's text font. ~~The suite's label and number
    fonts were settings~~ (V17): a profile that still holds them changes nothing."""
    boot(wow)
    fonts_frame(wow)
    wow.execute(
        f"""
        local p = Bastians:GetModule("Core").db.profile
        p.labelFont = [[{OWN["labelFont"]}]]
        p.numberFont = [[{OWN["numberFont"]}]]
        p.headingFont = [[{OWN["headingFont"]}]]
        {S}.applyFont()
        """
    )
    suite = wow.eval(f"{S}.font()")
    assert font_of(wow, "T.sec.title")[0] == wow.eval(f"{S}.BOOK_FONTS.bookCaps")
    assert font_of(wow, "T.tab.label")[0] == wow.eval(f"{S}.BOOK_FONTS.bookCaps")
    assert font_of(wow, "T.head")[0] == wow.eval(f"{S}.BOOK_FONTS.bookDisplay")
    assert font_of(wow, "T.num")[0] == suite
    assert font_of(wow, "T.text")[0] == suite
    assert wow.errors == []


def test_a_text_with_a_font_of_its_own_is_left_alone(wow: WowRuntime):
    boot(wow)
    fonts_frame(wow)
    wow.execute(
        f"""
        {S}.OwnFont(T.text)
        T.text:SetFont([[Fonts\\SKURRI.TTF]], 15, "OUTLINE")
        {S}.SetFramePreset(T.f, {own_values(wow)})
        {S}.applyFont()
        """
    )
    assert font_of(wow, "T.text") == ("Fonts\\SKURRI.TTF", 15)
    assert wow.errors == []


def test_a_client_with_its_own_script_keeps_its_font_for_every_role(wow: WowRuntime):
    boot(wow)
    fonts_frame(wow)
    wow.execute(f"{S}.CLIENT_FONT = true; {S}.SetFramePreset(T.f, {own_values(wow)})")
    suite = wow.eval(f"{S}.font()")
    for fs in ("T.text", "T.num", "T.head", "T.sec.title", "T.pill.count"):
        assert font_of(wow, fs)[0] == suite, fs
    assert wow.errors == []


def test_a_rounded_fill_takes_the_windows_palette(wow: WowRuntime):
    """Found 13.11.2026 (V25): a shape is no region, so a window of a light look of its own kept its
    header's rounded fill in the suite's dark colour, and its buttons read dark on dark."""
    boot(wow)
    wow.execute(
        f"""
        T = {{ f = CreateFrame("Frame", nil, UIParent) }}
        T.f:SetSize(100, 40)
        T.shape = {S}.roundFill(T.f, {S}.C.header, "radius")
        {S}.SetFramePreset(T.f, {SET}.PresetValues("modern-light"))
        """
    )
    assert wow.eval(f"{S}.painted[T.shape][1] == {S}.Palette('parchment').C.header") is True
    assert wow.errors == []


def test_the_games_codes_read_on_a_light_look(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"""
        T = {{ light = CreateFrame("Frame", nil, UIParent), dark = CreateFrame("Frame", nil, UIParent) }}
        {S}.SetFramePreset(T.light, {SET}.PresetValues("modern-light"))
        {S}.SetFramePreset(T.dark, {SET}.PresetValues("modern-dark"))
        """
    )
    white = "|cffffffff[Linen Cloth]|r"
    light = wow.eval(f"{S}.ReadableText({white!r}, T.light)")
    assert light != white and light.endswith("[Linen Cloth]|r")
    assert wow.eval(f"{S}.ReadableText({white!r}, T.dark)") == white  # a dark look keeps it
    # the colour keeps its hue and reads at 4.5:1 on the light panel
    r, g, b = (int(light[4 + 2 * i : 6 + 2 * i], 16) / 255 for i in range(3))
    assert r == g == b  # white stays grey
    rare = wow.eval(f"{S}.ReadableText('|cff0070ddx|r', T.light)")
    assert rare[4:10] != "0070dd" and int(rare[8:10], 16) > int(rare[4:6], 16)  # still blue
    assert wow.errors == []
