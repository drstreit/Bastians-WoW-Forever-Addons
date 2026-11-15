"""The game's windows move by a drag (helpers.md "The game's windows",
"make all blizzard windows movable as part of general Bastian options"): every window the panel
manager places and the loot window, the kept place laid again when the window shows, nothing done
to a protected window in a fight, the button that puts them back, the switch."""

from harness import WowRuntime
from test_helpers import HELPERS, H, P, boot, notice

W = f"{H}.Windows"

# the game's panel manager as the retail family has it (FrameXML UIParentPanelManager): a table of
# the windows it places, ShowUIPanel, and UpdateUIPanelPositions placing the shown ones
PANELS = """
UIPanelWindows = { CharacterFrame = { area = "left" }, MerchantFrame = { area = "left" } }
for name in pairs(UIPanelWindows) do
  local f = CreateFrame("Frame", name, UIParent)
  f:SetSize(380, 520)
  f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
  f:EnableMouse(true)
  f:Hide()
end
LootFrame = CreateFrame("Frame", "LootFrame", UIParent)
LootFrame:EnableMouse(true)
UpdateUIPanelPositions = function()
  -- the game's own code is secure: the mock's combat check is meant for addons, so it is lifted
  -- here and holds again for the hooks that run after this function
  local fight = Mock.combat
  Mock.combat = false
  for name in pairs(UIPanelWindows) do
    local f = _G[name]
    if f and f:IsShown() then
      f:ClearAllPoints()
      f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116) -- the manager's own place
    end
  end
  Mock.combat = fight
end
ShowUIPanel = function(f)
  f:Show()
  UpdateUIPanelPositions()
end
HideUIPanel = function(f) f:Hide() end
"""


def start(wow: WowRuntime, on: bool = True) -> WowRuntime:
    wow.execute(PANELS)
    if not on:
        wow.execute(
            "BastiansHelpersDB = { profileKeys = {}, profiles = { Default = { moveWindows = false } } }"
        )
    boot(wow, "Bastians_Core", HELPERS)
    return wow


def drag(wow: WowRuntime, name: str, x: float, y: float) -> None:
    """A drag on the window: picked up, moved by the player (the client's StartMoving), let go."""
    wow.execute(f"{name}:GetScript('OnDragStart')({name}, 'LeftButton')")
    wow.execute(
        f"{name}:ClearAllPoints(); {name}:SetPoint('TOPLEFT', UIParent, 'TOPLEFT', {x}, {y})"
    )
    wow.execute(f"{name}:GetScript('OnDragStop')({name})")


def point(wow: WowRuntime, name: str) -> tuple:
    p = wow.eval(f"{{ {name}:GetPoint(1) }}")
    return (p[1], p[3], p[4], p[5])


def test_every_window_of_the_panel_manager_and_the_loot_window_moves(wow: WowRuntime):
    start(wow)
    for name in ("CharacterFrame", "MerchantFrame", "LootFrame"):
        assert wow.eval(f"{name}:IsMovable()") is True, name
        assert wow.eval(f"{W}.Taken({name})") == name
    drag(wow, "CharacterFrame", 400, -200)
    assert wow.eval(f"{P}.windows.CharacterFrame[3]") == 400
    # the manager places it again when it shows: the kept place goes on after it
    wow.execute("ShowUIPanel(CharacterFrame)")
    assert point(wow, "CharacterFrame") == ("TOPLEFT", "TOPLEFT", 400, -200)
    wow.execute("HideUIPanel(CharacterFrame); CharacterFrame:Show()")  # shown without the manager
    assert point(wow, "CharacterFrame") == ("TOPLEFT", "TOPLEFT", 400, -200)
    assert wow.errors == []


def test_a_window_loaded_later_moves_from_its_first_showing(wow: WowRuntime):
    start(wow)
    wow.execute(
        "AuctionHouseFrame = CreateFrame('Frame', 'AuctionHouseFrame', UIParent);"
        " AuctionHouseFrame:Hide()"
    )
    assert wow.eval(f"{W}.Taken(AuctionHouseFrame)") is None
    # a Blizzard addon loaded on demand registers its window with the manager
    wow.execute("UIPanelWindows.AuctionHouseFrame = { area = 'doublewide' }")
    wow.fire("ADDON_LOADED", "Blizzard_AuctionHouseUI")
    assert wow.eval(f"{W}.Taken(AuctionHouseFrame)") == "AuctionHouseFrame"
    # a window the table never named: taken when the manager shows it
    wow.execute("TaxiFrame = CreateFrame('Frame', 'TaxiFrame', UIParent); ShowUIPanel(TaxiFrame)")
    assert wow.eval("TaxiFrame:IsMovable()") is True
    assert wow.errors == []


def test_the_places_outlive_a_reload(wow: WowRuntime):
    start(wow)
    drag(wow, "MerchantFrame", 600, -150)
    # a /reload as harness.reload does it, with the game's own frames there before the addons
    wow.fire("PLAYER_LOGOUT")
    saved = wow.saved_variables(*wow.loaded)
    fresh = WowRuntime(wow.client, wow.addons_dir, wow.extra_dirs)
    fresh.execute(saved)
    fresh.execute(PANELS)
    fresh.start(*[n for n in wow.loaded if not wow.is_load_on_demand(n)])
    fresh.execute("ShowUIPanel(MerchantFrame)")
    assert point(fresh, "MerchantFrame") == ("TOPLEFT", "TOPLEFT", 600, -150)
    assert fresh.errors == []


def test_a_protected_window_is_left_alone_in_a_fight(wow: WowRuntime):
    start(wow)
    drag(wow, "CharacterFrame", 400, -200)
    wow.execute("ShowUIPanel(CharacterFrame)")  # open before the fight, at its kept place
    wow.execute("CharacterFrame.protected = true; Mock.combat = true")
    wow.execute("CharacterFrame:GetScript('OnDragStart')(CharacterFrame, 'LeftButton')")
    wow.execute("UpdateUIPanelPositions()")  # the game places it in the fight (secure, allowed)
    assert point(wow, "CharacterFrame") == ("TOPLEFT", "TOPLEFT", 16, -116)  # ours not laid on
    # a protected window first met in a fight is taken at its end
    wow.execute(
        "SpellBookFrame = CreateFrame('Frame', 'SpellBookFrame', UIParent); SpellBookFrame.protected = true;"
        " UIPanelWindows.SpellBookFrame = { area = 'left' }"
    )
    wow.fire("ADDON_LOADED", "Blizzard_PlayerSpells")
    assert wow.eval("SpellBookFrame:IsMovable()") is not True
    wow.execute("Mock.combat = false")
    wow.fire("PLAYER_REGEN_ENABLED")
    assert wow.eval("SpellBookFrame:IsMovable()") is True
    assert wow.errors == []


def test_the_button_puts_them_back_and_the_switch_stops_it(wow: WowRuntime):
    start(wow)
    drag(wow, "CharacterFrame", 400, -200)
    wow.execute(f"{W}.Reset()")
    assert "back in their places" in notice(wow)
    wow.execute("ShowUIPanel(CharacterFrame)")
    assert point(wow, "CharacterFrame") == ("TOPLEFT", "TOPLEFT", 16, -116)
    drag(wow, "CharacterFrame", 400, -200)
    wow.execute(
        f"{P}.moveWindows = false;"
        " Bastians:Fire('BASTIANS_SETTING_CHANGED', 'Helpers', 'moveWindows', false)"
    )
    wow.execute("ShowUIPanel(CharacterFrame)")
    assert point(wow, "CharacterFrame") == ("TOPLEFT", "TOPLEFT", 16, -116)  # not laid again
    drag(wow, "CharacterFrame", 500, -300)
    assert wow.eval(f"{P}.windows.CharacterFrame[3]") == 400  # off: nothing picked up
    assert wow.errors == []


def test_switched_off_from_the_start_no_window_is_touched(wow: WowRuntime):
    start(wow, on=False)
    assert wow.eval("CharacterFrame:IsMovable()") is not True
    wow.execute(
        f"{P}.moveWindows = true;"
        " Bastians:Fire('BASTIANS_SETTING_CHANGED', 'Helpers', 'moveWindows', true)"
    )
    assert wow.eval("CharacterFrame:IsMovable()") is True
    assert wow.errors == []


def test_a_window_without_the_panel_manager_still_loads(wow: WowRuntime):
    """A client without UIPanelWindows, ShowUIPanel and UpdateUIPanelPositions: the loot window
    alone, no error (every app works alone)."""
    wow.execute("LootFrame = CreateFrame('Frame', 'LootFrame', UIParent)")
    boot(wow, "Bastians_Core", HELPERS)
    assert wow.eval("LootFrame:IsMovable()") is True
    assert wow.errors == []
