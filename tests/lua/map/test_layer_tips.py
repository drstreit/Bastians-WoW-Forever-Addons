"""An icon without words says its name at once (the map's layers stay icons
in their sliding panel, "but we need immediate hover text"; before, retail 31.10.2026:
"superfast - really immediately"). The name is the icon's only label, so it shows whatever the
tip delay and the tips switch say; a button with words keeps the delay and the switch."""

from harness import WowRuntime

CORE, DATA, MAP = "Bastians_Core", "Bastians_Data", "Bastians_Map"
MOD = "Bastians:GetModule('Map')"
MAP_ = f"{MOD}.Map"
PROFILE = "Bastians:GetModule('Core').db.profile"
ICONS = f"""(function()
  local out = {{}}
  for _, f in ipairs({{ {MAP_}.bar.Panel():GetChildren() }}) do
    if f:IsShown() and f.tip then out[#out + 1] = f end
  end
  return out
end)()"""


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA, MAP)
    wow.run_frames(10)
    wow.slash("/bmap")
    wow.execute(f"{MAP_}.clip:SetSize(600, 400); {MAP_}.ViewChanged()")
    wow.execute(f"ICONS = {ICONS}")
    return wow


def shown_for(wow: WowRuntime, widget: str) -> bool:
    return wow.eval(f"GameTooltip:IsShown() and GameTooltip:GetOwner() == {widget}") is True


def enter(wow: WowRuntime, widget: str) -> None:
    wow.execute(f"GameTooltip:Hide(); local w = {widget}; w:GetScript('OnEnter')(w)")


def leave(wow: WowRuntime, widget: str) -> None:
    wow.execute(f"local w = {widget}; w:GetScript('OnLeave')(w)")


def test_a_layers_icon_says_its_name_at_once(wow: WowRuntime):
    boot(wow)
    count = wow.eval("#ICONS")
    assert count >= 8  # the map's own layers, the style, the bookmarks
    for i in range(1, count + 1):
        icon = f"ICONS[{i}]"
        assert wow.eval(f"{icon}.tipNow") is True
        enter(wow, icon)
        assert shown_for(wow, icon), i  # no frame passed: at once
        assert wow.eval(f"({icon}.tip())") not in (None, "")  # it has a name
        leave(wow, icon)
        assert wow.eval("GameTooltip:IsShown()") is False
    assert wow.errors == []


def test_the_name_shows_with_the_tips_switched_off_and_a_long_delay(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{PROFILE}.tips = false; {PROFILE}.tipDelay = 5")
    enter(wow, "ICONS[1]")
    assert shown_for(wow, "ICONS[1]")
    leave(wow, "ICONS[1]")
    # the panel's tab (an arrow), the zoom's signs and the window's own pictograms too
    bar = f"{MAP_}.toolbar"
    for widget in (
        f"{MAP_}.bar.Tab()",
        f"{bar}.zoomOut",
        f"{bar}.zoomIn",
        f"{MAP_}.win.options",
        f"{MAP_}.win.close",
    ):
        enter(wow, widget)
        assert shown_for(wow, widget), widget
        leave(wow, widget)
    # a tool with words explains itself: the switch and the delay are its
    enter(wow, f"{bar}.player")
    wow.advance(6)
    assert wow.eval("GameTooltip:IsShown()") is False
    wow.execute(f"{PROFILE}.tips = true; {PROFILE}.tipDelay = 1")
    enter(wow, f"{bar}.player")
    assert wow.eval("GameTooltip:IsShown()") is False  # not yet
    wow.advance(1.1)
    assert shown_for(wow, f"{bar}.player")
    assert wow.errors == []
