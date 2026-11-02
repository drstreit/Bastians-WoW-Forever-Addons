"""Feeds for the community's addons (ADR 0043, core-contracts §7f): one LibDataBroker data source
per app, every attribute set from the start (Titan watches only those), the text read again after
its messages and events (coalesced), "off" while the app is switched off, both clicks, the tooltip
only on hover; the suite's Addon Compartment entry; minimap buttons through LibDBIcon when another
addon loaded it; bus messages as WeakAuras events with scalar arguments only."""

from harness import WowRuntime

# A test app with a window and a feed, in Core's own addon (loaded, so it enables at login).
APP = """
TestCount, TestReads, TestTips, TestOpened = 3, 0, 0, 0
TestApp = Bastians:NewModule("Testapp", {
  addon = "Bastians_Core",
  title = "Test app",
  open = function() TestOpened = TestOpened + 1 end,
  OnEnable = function(self)
    Bastians:RegisterFeed(self, {
      text = function() TestReads = TestReads + 1; return TestCount .. " things" end,
      tooltip = function(tt) TestTips = TestTips + 1; tt:AddLine("tip line") end,
      on = { "BASTIANS_NOTES_CHANGED" },
      events = { "PLAYER_MONEY" },
    })
  end,
})
"""


def obj(wow: WowRuntime, attr: str):
    return wow.eval(f"Bastians:FeedObject('Testapp').{attr}")


def test_a_feed_is_a_data_source_with_every_attribute_and_follows_its_messages(wow: WowRuntime):
    wow.start("Bastians_Core")
    wow.execute(APP)
    assert obj(wow, "type") == "data source"
    assert wow.eval(
        "LibStub('LibDataBroker-1.1'):GetDataObjectByName(\"Bastian's Testapp\") ~= nil"
    )
    assert obj(wow, "text") == "3 things"
    assert obj(wow, "label") == "Test app"
    assert obj(wow, "icon")
    assert obj(wow, "tocname") == "Bastians_Core"
    # a message changes it once, after the coalescing window
    reads = wow.eval("TestReads")
    wow.execute("TestCount = 5")
    for _ in range(3):
        wow.execute("Bastians:Fire('BASTIANS_NOTES_CHANGED')")
    assert obj(wow, "text") == "3 things"
    wow.advance(0.5)
    assert obj(wow, "text") == "5 things"
    assert wow.eval("TestReads") == reads + 1
    # a game event too
    wow.execute("TestCount = 7")
    wow.fire("PLAYER_MONEY")
    wow.advance(0.5)
    assert obj(wow, "text") == "7 things"
    # the tooltip is built only when shown
    assert wow.eval("TestTips") == 0
    wow.execute(
        "TestLines = {} ; local tt = { AddLine = function(_, t) TestLines[#TestLines + 1] = t end }"
        " ; Bastians:FeedObject('Testapp').OnTooltipShow(tt)"
    )
    lines = list(wow.eval("TestLines").values())
    assert lines[0] == "Bastian's Test app" and "tip line" in lines
    assert wow.eval("TestTips") == 1
    # left click opens the app, right click its settings page
    wow.execute("Bastians:FeedObject('Testapp').OnClick(nil, 'LeftButton')")
    assert wow.eval("TestOpened") == 1
    wow.execute("Bastians:FeedObject('Testapp').OnClick(nil, 'RightButton')")
    assert wow.eval("BastiansHubFrame:IsShown()") is True
    assert wow.errors == []


def test_a_switched_off_app_says_off_and_comes_back(wow: WowRuntime):
    wow.start("Bastians_Core")
    wow.execute(APP)
    wow.execute("TestApp:Disable()")
    assert obj(wow, "text") == "off"
    wow.execute("Bastians:FeedObject('Testapp').OnClick(nil, 'LeftButton')")
    assert wow.eval("TestOpened") == 0
    assert any("switched off" in line for line in wow.chat)
    reads = wow.eval("TestReads")
    wow.execute("Bastians:Fire('BASTIANS_NOTES_CHANGED')")
    wow.advance(0.5)
    assert wow.eval("TestReads") == reads  # no work for a switched-off app
    wow.execute("TestApp:Enable()")
    assert obj(wow, "text") == "3 things"
    assert wow.errors == []


def test_every_runs_only_while_a_display_listens(wow: WowRuntime):
    wow.start("Bastians_Core")
    wow.execute(
        """
        Ticks = 0
        Ticker = Bastians:NewModule("Ticker", {
          addon = "Bastians_Core",
          OnEnable = function(self)
            Bastians:RegisterFeed(self, {
              text = function() Ticks = Ticks + 1; return tostring(Ticks) end,
              every = function() return 1 end,
            })
          end,
        })
        """
    )
    wow.advance(3.5)
    assert wow.eval("Ticks") == 1  # nobody shows it: no timer
    wow.execute(
        """
        local ldb = LibStub('LibDataBroker-1.1')
        Display = {}
        ldb.RegisterCallback(Display, "LibDataBroker_AttributeChanged_Bastian's Ticker_text", function() end)
        Bastians:UpdateFeed(Ticker)
        """
    )
    wow.advance(0.5)
    first = wow.eval("Ticks")
    wow.advance(3.2)
    assert wow.eval("Ticks") >= first + 3
    assert wow.errors == []


def test_the_suite_is_in_the_addon_compartment(wow: WowRuntime):
    wow.execute(
        "Compartment = {} ; AddonCompartmentFrame = { RegisterAddon = function(self, e)"
        " Compartment[#Compartment + 1] = e end }"
    )
    wow.start("Bastians_Core")
    entries = list(wow.eval("Compartment").values())
    assert len(entries) == 1 and entries[0].text == "Bastian's"
    wow.execute("Compartment[1].func(nil, { buttonName = 'RightButton' })")
    assert wow.eval("BastiansLauncherMenu:IsShown()") is True
    wow.execute("Compartment[1].funcOnEnter(UIParent)")
    assert wow.eval("GameTooltip:IsShown()") is True
    assert wow.errors == []


def test_without_a_compartment_nothing_breaks(wow: WowRuntime):
    wow.execute("AddonCompartmentFrame = nil")
    wow.start("Bastians_Core")
    assert wow.eval("Bastians.UI.Launcher.Compartment()") is False
    assert wow.errors == []


# A stand-in LibDBIcon-1.0 (the real one is All Rights Reserved, never in this repository).
DBICON = """
local lib = LibStub:NewLibrary("LibDBIcon-1.0", 1)
lib.objects = {}
function lib:Register(name, object, db)
  local b = CreateFrame("Button", "LibDBIcon10_" .. name, Minimap)
  b.dataObject, b.db = object, db
  b:SetScript("OnClick", function(self, mouse) object.OnClick(self, mouse) end)
  self.objects[name] = b
  if db.hide then b:Hide() else b:Show() end
end
function lib:IsRegistered(name) return self.objects[name] ~= nil end
function lib:GetMinimapButton(name) return self.objects[name] end
function lib:Drag(name, pos) self.objects[name].db.minimapPos = pos end
"""


def test_minimap_buttons_through_libdbicon_when_another_addon_loaded_it(wow: WowRuntime):
    wow.load_addon("Bastians_Core")
    wow.execute(DBICON)
    wow.load_addon("Bastians_Data")
    wow.load_addon("Bastians_Map")
    wow.login()
    wow.run_frames(5)
    lib = "LibStub('LibDBIcon-1.0')"
    assert wow.eval(f"{lib}:IsRegistered('Bastians')") is True
    assert wow.eval("BastiansMinimapButton") is None  # not ours as well
    assert wow.eval(f'{lib}:IsRegistered("Bastian\'s Map")') is True
    assert wow.eval("BastiansMinimapButtonMap") is None
    # the map's button is made from the Map's feed object
    assert wow.eval(f"{lib}.objects[\"Bastian's Map\"].dataObject == Bastians:FeedObject('Map')")
    assert wow.eval(f'{lib}:IsRegistered("Bastian\'s Options")') is True
    # a drag lands in our settings, the switch hides the button
    wow.execute(f'{lib}:Drag("Bastian\'s Map", 123)')
    assert wow.eval("Bastians.UI.Launcher.AppSettings('Map').angle") == 123
    wow.execute("Bastians.UI.Launcher.SetAppButton('Map', false)")
    assert wow.eval(f'{lib}.objects["Bastian\'s Map"]:IsShown()') is False
    assert wow.errors == []


SUITE = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Map",
    "Bastians_Browser",
    "Bastians_Gold",
    "Bastians_Route",
    "Bastians_Strategies",
    "Bastians_Notes",
    "Bastians_Alts",
    "Bastians_Helpers",
    "Bastians_Chat",
    "Bastians_Voice",
)
# one feed per app with a window
FEEDS = (
    "Quests",
    "Map",
    "Browser",
    "Gold",
    "Route",
    "Strategies",
    "Notes",
    "Alts",
    "Helpers",
    "Chat",
    "Voice",  # the Orbiter
)
TIP = (
    "TipLines = {} ; local tt = { AddLine = function(_, t) TipLines[#TipLines + 1] = t end,"
    " AddDoubleLine = function(_, a, b) TipLines[#TipLines + 1] = a .. ' | ' .. tostring(b) end }"
)


def test_every_app_publishes_its_feed(wow: WowRuntime):
    wow.start(*SUITE)
    wow.run_frames(5)
    for name in FEEDS:
        if wow.eval(f"Bastians:GetModule('{name}')") is None:
            continue  # not made for this client (Gold and the book: Forever)
        o = f"Bastians:FeedObject('{name}')"
        assert wow.eval(f"{o} ~= nil and {o}.type") == "data source", name
        assert isinstance(wow.eval(f"{o}.text"), str), name
        wow.execute(f"{TIP} ; {o}.OnTooltipShow(tt)")
        lines = list(wow.eval("TipLines").values())
        assert lines[0].startswith("Bastian's "), (name, lines)
        if wow.eval(f"Bastians:GetModule('{name}'):IsEnabled()"):
            assert lines[-1].startswith("Click"), (name, lines)
        else:  # Chat ships off: Core says so, and that a click leads to its switch
            assert lines[-2].endswith("switched off."), (name, lines)
            assert lines[-1] == "Click: its page, to switch it on.", (name, lines)
    # the texts the apps know at once
    quests = wow.eval("Bastians:FeedObject('Quests').text")
    assert quests == "2 in the log, 1 ready"  # the mock's quest log
    assert wow.eval("Bastians:FeedObject('Route').text") == ""  # no route: nothing, not 0
    assert "notes" in wow.eval("Bastians:FeedObject('Notes').text")
    alts = wow.eval("Bastians:FeedObject('Alts').text")
    assert alts == "" or "on 1 characters" in alts
    assert wow.errors == []


def test_the_gold_feed_follows_the_money(wow: WowRuntime):
    wow.needs("Bastians_Gold")
    wow.start("Bastians_Core", "Bastians_Data", "Bastians_Gold")
    wow.run_frames(2)
    wow.execute("Mock.money = 62345")  # the day's count starts at login with 0 copper
    wow.fire("PLAYER_MONEY")
    wow.advance(0.5)
    text = wow.eval("Bastians:FeedObject('Gold').text")
    assert text.startswith("+6") and text.endswith("today"), text
    assert wow.errors == []


def test_a_section_in_ellesmereuis_options(wow: WowRuntime):
    wow.execute(
        """
        Rows = {}
        local function row(kind) return function(_, _, text, y, a, b) Rows[#Rows + 1] = { kind = kind,
          text = text, get = a, set = b } ; return {}, 20 end end
        EllesmereUI = { Widgets = { SectionHeader = row("header"), Toggle = row("toggle"),
          WideButton = row("button") } }
        function EllesmereUI.RegisterPlugin(id, spec) PluginId, Plugin = id, spec ; return true end
        """
    )
    wow.start("Bastians_Core", "Bastians_Data", "Bastians_Map")
    assert wow.eval("PluginId") == "Bastians_Core"
    assert wow.eval("Plugin.label") == "Bastian's"
    height = wow.eval("Plugin.modules[1].buildPage(Plugin.modules[1].pages[1], {}, -10)")
    assert height > 0
    rows = [dict(r.items()) for r in wow.eval("Rows").values()]
    toggles = {r["text"]: r for r in rows if r["kind"] == "toggle"}
    assert "Bastian's" in toggles and "Map" in toggles
    # the Map's switch is the hub's
    wow.execute("for _, r in ipairs(Rows) do if r.text == 'Map' then r.set(false) end end")
    assert wow.eval("Bastians.UI.Launcher.AppSettings('Map').hide") is True
    wow.execute("for _, r in ipairs(Rows) do if r.kind == 'button' then r.get() end end")  # onClick
    assert wow.eval("BastiansHubFrame:IsShown()") is True
    assert wow.errors == []


def test_bus_messages_reach_weakauras_with_scalar_arguments_only(wow: WowRuntime):
    wow.start("Bastians_Core")
    wow.execute(
        "Scanned = {} ; WeakAuras = { ScanEvents = function(e, a, b, c)"
        " Scanned[#Scanned + 1] = { e = e, a = a, b = b, c = c } end }"
    )
    wow.execute("Bastians:Fire('BASTIANS_ROUTE_CHANGED', { steps = {} })")
    wow.execute("Bastians:Fire('BASTIANS_PLAYER_MOVED_ZONE', 1429, 0)")
    wow.execute("Bastians:Fire('BASTIANS_THEME_CHANGED', 'dark')")  # not on the list
    got = [dict(x.items()) for x in wow.eval("Scanned").values()]
    assert got == [
        {"e": "BASTIANS_ROUTE_CHANGED"},
        {"e": "BASTIANS_PLAYER_MOVED_ZONE", "a": 1429, "b": 0},
    ]
    assert wow.errors == []
