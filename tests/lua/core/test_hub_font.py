"""The hub's menu after a font change: "after
choosing another font, one entry ('Notes', the selected one) kept the old font while the rest
changed". Not reproduced on the mock (core.md "Fonts and text size"); these tests keep the paths
that were checked: the General page's Font choice as the player picks it, a page selected before
and after, a preset applied while Notes is selected, a profile change, a change while the hub is
closed."""

from harness import WowRuntime

CORE = "Bastians:GetModule('Core')"
DEFAULT = "Fonts\\ARIALN.TTF"
FRIZ = "Fonts\\FRIZQT__.TTF"
MORPHEUS = "Fonts\\MORPHEUS.TTF"

FONTS = """
function HubFontTest()
  local out = {}
  for _, b in ipairs(Bastians.UI.Hub.navButtons) do
    if b:IsShown() then
      out[b.label:GetText()] = { font = (b.label:GetFont()), selected = b.line:IsShown() }
    end
  end
  return out
end
"""


def nav(wow: WowRuntime) -> dict[str, tuple[str, bool]]:
    """Every shown menu entry: its font file and whether it is the selected one."""
    return {k: (v.font, v.selected) for k, v in wow.eval("HubFontTest()").items()}


def pick_font(wow: WowRuntime, path: str) -> None:
    """Chooses a font in the General page's Font select, as the player does."""
    wow.execute("Bastians.UI.Hub.Open('Core')")
    lua_path = path.replace("\\", "\\\\")
    wow.execute(
        "local picked = false "
        "for _, w in ipairs(Bastians.UI.Hub.canvas.widgets) do "
        "  if w.label and w.label:GetText() == 'Font' then w:Open() "
        "    for _, item in ipairs(w.list.items) do "
        f"      if item:IsShown() and item.key == '{lua_path}' then item:Click() picked = true end "
        "    end "
        "  end "
        "end "
        f"assert(picked, 'no {lua_path} in the Font select')"
    )


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start("Bastians_Core", "Bastians_Notes", "Bastians_Map")
    wow.execute(FONTS)
    wow.execute("Bastians.UI.Hub.Open('Notes')")
    return wow


def assert_all(wow: WowRuntime, font: str, selected: str) -> None:
    entries = nav(wow)
    assert "Notes" in entries and len(entries) > 5
    assert {k for k, (_, on) in entries.items() if on} == {selected}
    assert {k: f for k, (f, _) in entries.items() if f != font} == {}


def test_every_menu_entry_takes_the_font_the_player_picks(wow: WowRuntime):
    boot(wow)
    assert_all(wow, DEFAULT, "Notes")
    pick_font(wow, FRIZ)
    assert_all(wow, FRIZ, "General")
    wow.execute("Bastians.UI.Hub.Open('Notes')")  # Notes the selected one again
    assert_all(wow, FRIZ, "Notes")
    pick_font(wow, MORPHEUS)
    wow.execute("Bastians.UI.Hub.Open('Notes')")
    assert_all(wow, MORPHEUS, "Notes")
    assert wow.errors == []


def test_a_preset_a_profile_and_a_closed_hub_change_every_entry(wow: WowRuntime):
    boot(wow)
    wow.execute(f"Bastians.UI.Settings.ApplyPreset({CORE}, 'wow')")  # Friz Quadrata
    assert_all(wow, FRIZ, "Notes")
    wow.execute(f"Bastians.UI.Settings.ApplyPreset({CORE}, 'parchment')")  # the default font
    assert_all(wow, DEFAULT, "Notes")
    wow.execute(f"{CORE}.db.profile.font = 'Fonts\\\\MORPHEUS.TTF'")
    wow.execute("Bastians.UI.Style.applyFont()")
    assert_all(wow, MORPHEUS, "Notes")
    wow.execute("Bastians:SetProfile('Other')")  # a new profile: the default font
    assert_all(wow, DEFAULT, "Notes")
    wow.execute("Bastians.UI.Hub.Toggle()")  # closed
    wow.execute(f"{CORE}.db.profile.font = 'Fonts\\\\FRIZQT__.TTF'")
    wow.execute("Bastians.UI.Style.applyFont()")
    wow.execute("Bastians.UI.Hub.Toggle()")  # open again on Notes
    assert_all(wow, FRIZ, "Notes")
    assert wow.errors == []
