"""B2.9: minimap button and LDB launcher, omnibox search window, perf meter and /bastians perf."""

from harness import WowRuntime


def test_libraries_are_embedded_and_register_once(core: WowRuntime):
    assert core.eval("LibStub ~= nil") is True
    assert core.eval("LibStub('CallbackHandler-1.0', true) ~= nil") is True
    assert core.eval("LibStub('LibDataBroker-1.1', true) ~= nil") is True


def test_minimap_button_exists_moves_and_hides(core: WowRuntime):
    assert core.eval("BastiansMinimapButton:IsShown()") is True
    assert core.eval("BastiansMinimapButton:GetParent() == Minimap") is True
    core.execute(
        "Mock.cursorX, Mock.cursorY = 2000, 70"
    )  # far right of the mock minimap centre (70, 70)
    core.execute(
        "local b = BastiansMinimapButton; b:GetScript('OnDragStart')(b); b:GetScript('OnUpdate')(b); b:GetScript('OnDragStop')(b)"
    )
    angle = core.eval("Bastians:GetModule('Core').db.profile.minimap.angle")
    assert -10 < angle < 10  # cursor to the right: angle near 0
    assert core.eval("BastiansMinimapButton:GetScript('OnUpdate')") is None
    core.execute(
        "Bastians:GetModule('Core').db.profile.minimap.hide = true; Bastians.UI.Launcher.UpdateVisibility()"
    )
    assert core.eval("BastiansMinimapButton:IsShown()") is False
    fresh = core.reload()
    assert fresh.eval("BastiansMinimapButton:IsShown()") is False
    assert round(fresh.eval("Bastians:GetModule('Core').db.profile.minimap.angle")) == round(angle)


def test_launcher_clicks_open_omnibox_and_menu(core: WowRuntime):
    core.execute("BastiansMinimapButton:Click('LeftButton')")
    assert core.eval("BastiansOmniboxFrame:IsShown()") is True
    core.execute("BastiansMinimapButton:Click('LeftButton')")
    assert core.eval("BastiansOmniboxFrame:IsShown()") is False
    core.execute(
        """
        local m = Bastians:NewModule("App", { addon = "Bastians_Core", title = "An App" })
        opened = 0
        Bastians.UI.Launcher.Add(m, { label = "An App", order = 10, onClick = function() opened = opened + 1 end })
        BastiansMinimapButton:Click("RightButton")
        """
    )
    assert core.eval("BastiansLauncherMenu:IsShown()") is True
    labels = [
        b.label.GetText(b.label)
        for b in core.eval("BastiansLauncherMenu.items").values()
        if b.IsShown(b)
    ]
    assert labels == ["An App", "Settings"]
    core.execute("BastiansLauncherMenu.items[1]:Click()")
    assert core.g.opened == 1 and core.eval("BastiansLauncherMenu:IsShown()") is False
    core.execute("Bastians:GetModule('App'):Disable(); Bastians.UI.Launcher.ShowMenu(UIParent)")
    labels = [
        b.label.GetText(b.label)
        for b in core.eval("BastiansLauncherMenu.items").values()
        if b.IsShown(b)
    ]
    assert labels == ["Settings"]  # owner-tracked: gone with the module


def test_broker_launcher_object(core: WowRuntime):
    obj = core.eval("Bastians.UI.Launcher.Broker()")
    assert obj is not None and obj.type == "launcher"
    assert core.eval("LibStub('LibDataBroker-1.1'):GetDataObjectByName('Bastians') ~= nil") is True
    core.execute("Bastians.UI.Launcher.Broker().OnClick(nil, 'LeftButton')")
    assert core.eval("BastiansOmniboxFrame:IsShown()") is True
    core.execute(
        "GameTooltip:ClearLines(); Bastians.UI.Launcher.Broker().OnTooltipShow(GameTooltip)"
    )
    assert core.eval("GameTooltip:NumLines()") == 3


def test_omnibox_searches_and_opens_results(wow: WowRuntime):
    wow.start("Bastians_Core", "Bastians_Data", "Bastians_Quests", "Bastians_Browser")
    wow.run_frames(10)
    wow.execute("Bastians.UI.Omnibox.Open('hog')")
    wow.execute(
        "Bastians.UI.Omnibox.tree.scroll:SetSize(400, 300)"
    )  # the mock has no anchor layout
    wow.run_frames(10)
    rows = wow.eval("Bastians.UI.Omnibox.tree.flat")
    assert [r.text for r in rows.values()] == [
        "Hogger",
        'Wanted: "Hogger"',
        "Load quest texts to search them",  # the Quests provider's offer (core-contracts 7a), last
    ]
    assert rows[1].ref == "npc:448" and rows[1].note == "npc"
    assert rows[3].ref is None
    assert wow.eval("Bastians.UI.Omnibox.status:GetText()") == "3 results"
    wow.execute("Bastians.UI.Omnibox.tree.pool[1]:Click('LeftButton')")
    assert wow.eval("BastiansBrowserFrame:IsShown()") is True
    # the page shows in the detail pane (ADR 0018)
    assert wow.eval("Bastians:GetModule('Browser').dossier.band.name:GetText()").startswith(
        "Hogger"
    )
    wow.execute(
        "Bastians.UI.Omnibox.box:SetText('zzz'); Bastians.UI.Omnibox.box:GetScript('OnTextChanged')(Bastians.UI.Omnibox.box)"
    )
    wow.run_frames(10)
    assert [r.text for r in wow.eval("Bastians.UI.Omnibox.tree.flat").values()] == [
        "Load quest texts to search them"  # nothing by name; the texts might know it
    ]
    wow.slash("/bs farley")
    wow.run_frames(10)
    assert [r.text for r in wow.eval("Bastians.UI.Omnibox.tree.flat").values()] == [
        "Innkeeper Farley",
        "Load quest texts to search them",
    ]
    assert wow.errors == []


def test_omnibox_without_browser_opens_the_entity_menu(wow: WowRuntime):
    wow.start("Bastians_Core", "Bastians_Data", "Bastians_Quests")
    wow.run_frames(10)
    wow.execute(
        """
        local m = Bastians:NewModule("Acts", { addon = "Bastians_Core" })
        Bastians:RegisterAction(m, { id = "map.show", label = "Show on map", types = "*", run = function() end })
        Bastians.UI.Omnibox.Open("hogger")
        Bastians.UI.Omnibox.tree.scroll:SetSize(400, 300)
        """
    )
    wow.run_frames(10)
    wow.execute("Bastians.UI.Omnibox.tree.pool[1]:Click('LeftButton')")
    assert wow.eval("Bastians.UI.EntityMenuFrame():IsShown()") is True


def test_perf_meter_counts_calls_and_snapshots(app: WowRuntime):
    for i in range(5):
        app.fire("TEST_EVENT", i)
    stats = app.eval("Bastians.Perf.modules.TestApp")
    assert stats.calls >= 5 and stats.ms >= 0
    app.execute("Mock.cpuStep = 1")
    app.fire("TEST_EVENT", 9)
    assert app.eval("Bastians.Perf.modules.TestApp.maxMs") >= 1
    app.slash("/bastians perf")
    assert any("Performance since login" in line for line in app.chat)
    assert any(line.strip().startswith("TestApp") for line in app.chat)
    assert any("Bastians_Core" in line and "KB" in line for line in app.chat)
    snaps = app.eval("Bastians:GetModule('Core').db.global.perf")
    assert len(snaps) == 1 and snaps[1].client == app.client
    assert snaps[1].modules.TestApp.calls >= 6
    for _ in range(25):
        app.execute("Bastians.Perf.Snapshot()")
    assert len(app.eval("Bastians:GetModule('Core').db.global.perf")) == 20


def test_key_binding_names_exist(core: WowRuntime):
    assert core.eval("BINDING_HEADER_BASTIANS") == "Bastian's"
    assert core.eval("BINDING_NAME_BASTIANS_OMNIBOX") == "Open the search (omnibox)"
