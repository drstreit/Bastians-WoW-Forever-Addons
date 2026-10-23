"""The harness and mock themselves: loading, events, timers, combat lockdown, saved variables."""

import pytest
from harness import LuaAddonError, WowRuntime

INTERFACE = {"forever": 16001, "retail": 120105}


def test_core_loads_and_logs_in_on_each_client(core: WowRuntime):
    assert core.loaded == ["Bastians_Core"]
    assert core.errors == []
    interface = core.eval("select(4, GetBuildInfo())")
    assert interface == INTERFACE[core.client]
    assert core.eval("(C_AddOns.IsAddOnLoaded('Bastians_Core'))") is True
    assert core.eval("C_AddOns.GetAddOnMetadata('Bastians_Core', 'Title')") == "Bastian's Core"


def test_missing_addon_is_an_error(wow: WowRuntime):
    with pytest.raises(LuaAddonError, match="no addon"):
        wow.load_addon("Bastians_Nope")


def test_events_dispatch_in_order_and_tolerate_unregister_inside_handler(wow: WowRuntime):
    wow.execute(
        """
        log = {}
        local a = CreateFrame("Frame"); a:RegisterEvent("TEST_EVENT")
        a:SetScript("OnEvent", function(self, event, arg)
          log[#log + 1] = "a:" .. arg; self:UnregisterEvent(event)
        end)
        local b = CreateFrame("Frame"); b:RegisterEvent("TEST_EVENT")
        b:SetScript("OnEvent", function(self, event, arg) log[#log + 1] = "b:" .. arg end)
        """
    )
    wow.fire("TEST_EVENT", 1)
    wow.fire("TEST_EVENT", 2)
    assert list(wow.g.log.values()) == ["a:1", "b:1", "b:2"]


def test_handler_errors_are_collected_not_raised(wow: WowRuntime):
    wow.execute(
        """
        local f = CreateFrame("Frame"); f:RegisterEvent("BOOM")
        f:SetScript("OnEvent", function() error("kaboom") end)
        """
    )
    wow.fire("BOOM")
    assert len(wow.errors) == 1 and "kaboom" in wow.errors[0]


def test_timers_run_in_time_order_and_tickers_cancel(wow: WowRuntime):
    wow.execute(
        """
        log = {}
        C_Timer.After(2, function() log[#log + 1] = "after2@" .. GetTime() end)
        C_Timer.After(1, function() log[#log + 1] = "after1@" .. GetTime() end)
        ticker = C_Timer.NewTicker(0.4, function() log[#log + 1] = "tick@" .. GetTime() end, 3)
        """
    )
    wow.advance(1.6)
    wow.advance(1.0)
    assert list(wow.g.log.values()) == ["tick@0.4", "tick@0.8", "after1@1", "tick@1.2", "after2@2"]
    assert wow.eval("ticker:IsCancelled()") is True


def test_on_update_runs_only_for_visible_frames(wow: WowRuntime):
    wow.execute(
        """
        count = 0
        local f = CreateFrame("Frame"); f:SetScript("OnUpdate", function() count = count + 1 end)
        local h = CreateFrame("Frame"); h:Hide()
        h:SetScript("OnUpdate", function() count = count + 100 end)
        """
    )
    wow.run_frames(3)
    assert wow.g.count == 3


def test_combat_lockdown_blocks_secure_frames_and_fires_regen_events(wow: WowRuntime):
    wow.execute(
        """
        events = {}
        local w = CreateFrame("Frame")
        w:RegisterEvent("PLAYER_REGEN_DISABLED"); w:RegisterEvent("PLAYER_REGEN_ENABLED")
        w:SetScript("OnEvent", function(_, e) events[#events + 1] = e end)
        btn = CreateFrame("Button", "SecureBtn", UIParent, "SecureActionButtonTemplate")
        plain = CreateFrame("Button")
        """
    )
    wow.set_combat(True)
    assert wow.eval("InCombatLockdown()") is True
    with pytest.raises(lua_error(), match="ADDON_ACTION_BLOCKED"):
        wow.execute("btn:SetAttribute('type', 'item')")
    wow.execute("plain:SetAttribute('type', 'item')")  # unprotected frames are fine
    wow.set_combat(False)
    wow.execute("btn:SetAttribute('type', 'item')")
    assert list(wow.g.events.values()) == ["PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED"]


def test_unknown_frame_method_raises_instead_of_returning_nil(wow: WowRuntime):
    with pytest.raises(lua_error(), match="not mocked"):
        wow.execute("CreateFrame('Frame'):SetFlibbertigibbet(1)")


def test_slash_commands_and_chat(wow: WowRuntime):
    wow.execute(
        """
        SLASH_BTEST1 = "/btest"; SLASH_BTEST2 = "/bt"
        SlashCmdList.BTEST = function(msg) print("got", msg) end
        """
    )
    wow.slash("/BT hello world")
    assert wow.chat == ["got hello world"]
    with pytest.raises(lua_error(), match="unknown slash"):
        wow.slash("/nothing")


def test_tooltip_post_calls_fire_per_kind(wow: WowRuntime):
    wow.execute(
        """
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
          tt:AddDoubleLine("Price", data.id * 2)
        end)
        """
    )
    lines = wow.tooltip("Item", 2589)
    assert lines == [{"left": "Price", "right": 5178}]
    assert wow.tooltip("Unit", 448) == []


def test_saved_variables_round_trip_through_reload(wow: WowRuntime):
    wow.start("Bastians_Core")
    wow.execute(
        """
        BastiansCoreDB = {
          profile = { pinSize = 18, name = "a \\"quoted\\" string" }, list = { 3, 1, 2 },
          global = { companionsNoted = Bastians.UI.Settings.Fingerprint() }, -- the login note is done
        }
        BastiansCoreCharDB = { seen = true }
        """
    )
    text = wow.saved_variables("Bastians_Core")
    assert text.startswith("BastiansCoreDB = {")
    fresh = wow.reload()
    assert fresh.loaded == ["Bastians_Core"]
    assert fresh.eval("BastiansCoreDB.profile.pinSize") == 18
    assert fresh.eval("BastiansCoreDB.profile.name") == 'a "quoted" string'
    assert list(fresh.g.BastiansCoreDB.list.values()) == [3, 1, 2]
    assert fresh.eval("BastiansCoreCharDB.seen") is True
    fresh.fire("PLAYER_LOGOUT")
    assert fresh.saved_variables("Bastians_Core") == text  # deterministic


def test_lua_can_load_an_addon_on_demand_through_the_harness(wow: WowRuntime):
    wow.start("Bastians_Core")
    wow.execute(
        """
        seen = {}
        local f = CreateFrame("Frame"); f:RegisterEvent("ADDON_LOADED")
        f:SetScript("OnEvent", function(_, _, name) seen[#seen + 1] = name end)
        ok, reason = C_AddOns.LoadAddOn("Bastians_Route")
        """
    )
    assert wow.g.ok is True
    assert wow.loaded == ["Bastians_Core", "Bastians_Route"]
    assert list(wow.g.seen.values()) == ["Bastians_Route"]
    assert wow.eval("(C_AddOns.IsAddOnLoaded('Bastians_Route'))") is True
    wow.set_combat(True)
    blocked = wow.eval("select(2, C_AddOns.LoadAddOn('Bastians_Map_Art'))")
    assert blocked == "INTERFACE_ACTION_BLOCKED"


def test_map_transforms_round_trip(wow: WowRuntime):
    cont, wx, wy = wow.eval(
        "(function() local c, p = C_Map.GetWorldPosFromMapPos(1429, CreateVector2D(0.25, 0.5)); "
        "return c, p:GetXY() end)()"
    )
    assert (cont, wx, wy) == (0, 0, 100)
    back = wow.eval(
        "(function() local _, p = C_Map.GetMapPosFromWorldPos("
        f"{cont}, CreateVector2D({wx}, {wy}), 1429); return p:GetXY() end)()"
    )
    assert back == (0.25, 0.5)


def test_documented_but_unmocked_api_raises(wow: WowRuntime):
    if wow.stub_count == 0:
        pytest.skip("generated API stubs not present yet (tools/api_stubs.py generate)")
    assert wow.stub_count > 1000
    with pytest.raises(lua_error(), match="not mocked"):
        wow.execute("C_QuestLog.GetQuestAdditionalHighlights(1)")  # documented, never mocked


def lua_error():
    from lupa import lua51

    return lua51.LuaError
