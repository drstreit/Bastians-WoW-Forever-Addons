"""A button of a fixed width never draws its label past its edge (plan-chat-one-window.md R13;
, screens 5 and 8: "Inbox (version 3, being built)" and "By the look (IBM
Plex Sans in Modern and Glass)" ran out of the settings' choice buttons). The label is cut to the
button and the whole label is the tooltip; the settings' choice button is as wide as its longest
choice again (its Fit was undone by the next SetLabel, which drew the button at its first width)."""

from harness import WowRuntime

S = "Bastians.UI.Style"
W = "Bastians.UI.Widgets"
CORE = "Bastians:GetModule('Core')"
SET = "Bastians.UI.Settings"
LONG = "By the look (IBM Plex Sans in Modern and Glass)"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start("Bastians_Core")
    wow.run_frames(3)
    return wow


def test_a_fixed_width_button_cuts_its_label_in_every_theme(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"""
        CutTest = {{}}
        CutTest.long = {S}.button(UIParent, {LONG!r}, 150, 20)
        CutTest.short = {S}.button(UIParent, 'Inbox', 150, 20)
        CutTest.told = {S}.button(UIParent, {LONG!r}, 150, 20)
        CutTest.told.tip = 'its own words'
        """
    )
    # ~~in every look (modern-dark, glass, parchment, wow)~~ one look since 20.11.2026 (ADR 0084)
    for preset in ("folio", "parchment", "teal"):
        wow.execute(f"Bastians.UI.Style.ApplyTheme('{preset}'); Bastians.UI.Style.ApplyLook()")
        label = "CutTest.long.label"
        assert wow.eval(f"{label}:GetText()") == LONG, preset  # the client cuts it with "..."
        width = wow.eval(f"{label}:GetWidth()")
        assert width is not None and 0 < width < 150, preset
        assert wow.eval(f"{label}.wordWrap") is False, preset
        assert wow.eval("CutTest.long:GetWidth()") == 150, preset
        assert wow.eval("CutTest.long.cutTip") == LONG, preset
        assert wow.eval("CutTest.short.cutTip") is None, preset
    # hovering shows the whole label; a tip of the button's own wins
    assert wow.eval("CutTest.long.tip") == LONG
    assert wow.eval("CutTest.told.tip") == "its own words"
    wow.execute("CutTest.long:GetScript('OnEnter')(CutTest.long)")
    wow.advance(2)
    lines = [line.left for line in (wow.eval("GameTooltip.lines") or {}).values()]
    assert any(LONG in str(x) for x in lines)
    # a shorter label later: no cut, no tip left behind
    wow.execute("CutTest.long:SetLabel('Inbox')")
    assert wow.eval("CutTest.long.tip") is None
    assert wow.errors == []


def test_the_choice_button_stays_as_wide_as_its_longest_choice(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"""
        CutTest = {{}}
        CutTest.sel = {W}.Select(UIParent, 'Heads and tabs',
          {{ auto = 'By the look', barlow = 'Barlow Condensed SemiBold' }}, function() end)
        CutTest.sel:SetValue('auto')
        """
    )
    button = "CutTest.sel.button"
    widest = wow.eval(f"{button}.label:GetStringWidth()")  # "By the look" is shown now
    width = wow.eval(f"{button}:GetWidth()")
    # Fit made it as wide as "Barlow Condensed SemiBold" (and its padding); SetValue kept that
    assert width > 160
    assert width > widest
    assert wow.eval(f"{button}.spec.width") == width
    assert wow.errors == []
