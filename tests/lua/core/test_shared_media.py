"""LibSharedMedia's borders and backgrounds (plan-chat-v3.md V25; "i want sharedmedia
borders and colors, that the point on skinning"): a window draws the border and the background a
player picked from LibSharedMedia, in their colours, per window where a window has a look of its
own; without the library, or for a name it does not know, nothing changes (golden rule 4)."""

from harness import WowRuntime

S = "Bastians.UI.Style"
CORE = "Bastians:GetModule('Core')"
PROFILE = f"{CORE}.db.profile"
# a stand-in for LibSharedMedia-3.0: two borders, a background, a sound
LSM = """
local media = {
  border = { Thin = [[Interface\\Media\\Thin]], Thick = [[Interface\\Media\\Thick]] },
  background = { Marble = [[Interface\\Media\\Marble]] },
  sound = { Ding = [[Sound\\Media\\Ding.ogg]] },
}
local lsm = LibStub:NewLibrary("LibSharedMedia-3.0", 1)
lsm.HashTable = function(_, kind) return media[kind] or {} end
lsm.Fetch = function(_, kind, name) return media[kind] and media[kind][name] end
"""


def window(wow: WowRuntime, name: str = "TestMedia") -> str:
    wow.execute(f"T = T or {{}}; T[{name!r}] = Bastians.UI.Window({name!r}, {{ title = 'Test' }})")
    return f"T[{name!r}]"


def look(wow: WowRuntime, **values) -> None:
    """Settings of the General page, then every window drawn again."""
    sets = "; ".join(f"{PROFILE}.{k} = {v}" for k, v in values.items())
    wow.execute(f"{sets}; Bastians.UI.ApplyWindowLook()")


def test_without_the_library_nothing_changes(core: WowRuntime):
    win = window(core)
    look(core, windowBorder="'Thin'", windowTexture="'Marble'")
    assert core.eval(f"{S}.HasMedia()") is False
    assert core.eval(f"{win}.media") is None
    assert core.eval(f"{win}.frame.bg:IsShown()") is True  # the look's flat ground
    assert core.errors == []


def test_a_border_and_a_background_in_their_colours(core: WowRuntime):
    core.execute(LSM)
    win = window(core)
    look(
        core,
        windowBorder="'Thin'",
        windowTexture="'Marble'",
        windowBorderColor="{ 0.8, 0.1, 0.2, 1 }",
        windowAlpha="80",
    )
    m = f"{win}.media"
    assert core.eval(f"{m}:IsShown()") is True
    assert core.eval(f"{m}.backdrop.edgeFile") == "Interface\\Media\\Thin"
    assert core.eval(f"{m}.backdrop.bgFile") == "Interface\\Media\\Marble"
    border = core.eval(f"{m}.backdropBorderColor")
    assert [round(border[i], 2) for i in (1, 2, 3)] == [0.8, 0.1, 0.2]
    assert round(core.eval(f"{m}.backdropColor[4]"), 2) == 0.8  # the window's opacity
    assert core.eval(f"{win}.frame.bg:IsShown()") is False  # the texture takes the ground's place
    # back to none: the flat ground again
    look(core, windowBorder="nil", windowTexture="nil")
    assert core.eval(f"{m}:IsShown()") is False
    assert core.eval(f"{win}.frame.bg:IsShown()") is True
    assert core.errors == []


def test_a_window_of_its_own_look_takes_its_own_border(core: WowRuntime):
    core.execute(LSM)
    mine, other = window(core, "TestMine"), window(core, "TestOther")
    look(core, windowBorder="'Thin'")
    core.execute(
        f"""
        local v = {{}}
        for k, x in pairs(Bastians.UI.Settings.PresetValues("modern-dark")) do v[k] = x end
        v.windowBorder = "Thick"
        {mine}:SetPreset(v)
        """
    )
    assert core.eval(f"{mine}.media.backdrop.edgeFile") == "Interface\\Media\\Thick"
    assert core.eval(f"{other}.media.backdrop.edgeFile") == "Interface\\Media\\Thin"
    # a preset that names none takes the suite's; "none" is none
    core.execute(f"{mine}:SetPreset(Bastians.UI.Settings.PresetValues('modern-dark'))")
    assert core.eval(f"{mine}.media.backdrop.edgeFile") == "Interface\\Media\\Thin"
    core.execute(
        f"""
        local v = {{}}
        for k, x in pairs(Bastians.UI.Settings.PresetValues("modern-dark")) do v[k] = x end
        v.windowBorder = "none"
        {mine}:SetPreset(v)
        """
    )
    assert core.eval(f"{mine}.media:IsShown()") is False
    assert core.errors == []


def test_a_name_the_library_does_not_know_changes_nothing(core: WowRuntime):
    core.execute(LSM)
    win = window(core)
    look(core, windowBorder="'Gone'")
    assert core.eval(f"{win}.media") is None
    assert core.eval(f"{win}.frame.bg:IsShown()") is True
    assert core.errors == []


def test_the_general_page_offers_the_librarys_names(core: WowRuntime):
    core.execute(LSM)
    values = dict(core.eval("Bastians.UI.Settings.MediaChoices('border', 'None')").items())
    assert values == {"": "None", "Thin": "Thin", "Thick": "Thick"}
    assert core.eval(f"{S}.MediaNames('background')")[1] == "Marble"
    assert {"windowBorder", "windowBorderColor", "windowTexture"} <= set(
        core.eval("Bastians.UI.Settings.FRAME_KEYS").values()  # a window may have its own
    )
    assert core.errors == []
