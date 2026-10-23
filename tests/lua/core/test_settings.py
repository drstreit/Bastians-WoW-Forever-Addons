"""Settings (B2.8): schema renderer, hub, Blizzard panel categories, profiles, LoD switches, notes."""

from harness import WowRuntime


def widgets(app: WowRuntime):
    return list(app.eval("Bastians.UI.Hub.canvas.widgets").values())


def labels(app: WowRuntime) -> list[str]:
    out = []
    for w in widgets(app):
        label = w.label
        out.append(label.GetText(label) if label is not None else "<header?>")
    return out


def test_hub_opens_and_lists_modules(app: WowRuntime):
    app.slash("/bastians")
    assert app.eval("BastiansHubFrame:IsShown()") is True
    names = [
        b.label.GetText(b.label)
        for b in app.eval("Bastians.UI.Hub.nav:GetChildren()")
        if b.IsShown(b)
    ]
    assert names[0] == "General"
    assert "Test App" in names
    assert any(
        n.startswith("Bastian's Route") for n in names
    )  # load-on-demand app without its module
    assert "Probe" not in names
    app.slash("/bastians")
    assert app.eval("BastiansHubFrame:IsShown()") is False


def test_module_page_renders_every_option_type_and_writes_values(app: WowRuntime):
    app.execute("Bastians.UI.Hub.Open('TestApp')")
    texts = labels(app)
    assert texts[0] == "Enabled"
    assert any("Bastians_Nope is not installed" in t for t in texts)
    assert not any(
        "QuestieDB is not installed" in t for t in texts
    )  # a QuestieDB fixture addon exists
    assert (
        "Minimap button" in texts
        and "Pin size" in texts
        and "Flight paths" in texts
        and "Reset" in texts
    )
    assert any(t.startswith("Pins: 16") for t in texts)
    assert "Sub" in texts  # the sub-module header
    app.execute(
        "changes = {}; Bastians:GetModule('TestApp'):On('BASTIANS_SETTING_CHANGED', function(_, _, m, k, v) changes[#changes + 1] = m .. '.' .. tostring(k) .. '=' .. tostring(v) end)"
    )
    toggle = next(i for i, t in enumerate(labels(app)) if t == "Minimap button")
    assert app.eval(f"Bastians.UI.Hub.canvas.widgets[{toggle + 1}]:GetChecked()") is True
    app.execute(f"Bastians.UI.Hub.canvas.widgets[{toggle + 1}]:Click()")
    assert app.eval("Bastians:GetModule('TestApp').db.profile.showMinimapButton") is False
    slider = next(i for i, t in enumerate(labels(app)) if t == "Pin size")
    assert app.eval(f"Bastians.UI.Hub.canvas.widgets[{slider + 1}]:GetValue()") == 16
    app.execute(f"Bastians.UI.Hub.canvas.widgets[{slider + 1}].slider:SetValue(24)")
    assert app.eval("Bastians:GetModule('TestApp').db.profile.pinSize") == 24
    select = next(i for i, t in enumerate(labels(app)) if t == "Flight paths")
    app.execute(
        f"local w = Bastians.UI.Hub.canvas.widgets[{select + 1}]; w:Open(); w.list.items[1]:Click()"
    )
    assert (
        app.eval("Bastians:GetModule('TestApp').db.profile.network") == "all"
    )  # "All" sorts before "Known only"
    reset = next(i for i, t in enumerate(labels(app)) if t == "Reset")
    app.execute(f"Bastians.UI.Hub.canvas.widgets[{reset + 1}]:Click()")
    assert list(app.g.TestLog.values())[-1] == "reset"
    assert list(app.g.changes.values()) == [
        "TestApp.showMinimapButton=false",
        "TestApp.pinSize=24",
        "TestApp.network=all",
    ]


def test_enable_switch_disables_and_enables_the_module(app: WowRuntime):
    app.execute("Bastians.UI.Hub.Open('TestApp')")
    app.execute("Bastians.UI.Hub.canvas.widgets[1]:Click()")
    assert app.eval("Bastians:GetModule('TestApp'):IsEnabled()") is False
    assert list(app.g.TestLog.values())[-2:] == ["sub-disable", "disable"]
    assert app.eval("Bastians.UI.Hub.canvas.widgets[1]:GetChecked()") is False  # re-rendered
    app.execute("Bastians.UI.Hub.canvas.widgets[1]:Click()")
    assert app.eval("Bastians:GetModule('TestApp'):IsEnabled()") is True


def test_error_disabled_module_shows_a_note(app: WowRuntime):
    app.execute("TestThrow = true")
    for i in range(11):
        app.fire("TEST_EVENT", i)
    app.execute("Bastians.UI.Hub.Open('TestApp')")
    assert any("repeated errors" in t for t in labels(app))


def test_blizzard_panel_categories(app: WowRuntime):
    cats = app.eval("Mock.settingsCategories")
    assert len(cats) == 1 and cats[1].name == "Bastians"
    children = sorted(c.name for c in cats[1].children.values())
    assert children == ["Test App"]
    panels = app.eval("Bastians.UI.Settings.Panels()")
    assert set(panels.keys()) == {"Core", "TestApp"}
    app.execute("Bastians.UI.Settings.Open(Bastians:GetModule('TestApp'))")
    assert app.eval("Mock.settingsOpened") == app.eval(
        "Bastians.UI.Settings.Panels().TestApp.category:GetID()"
    )
    app.execute("Bastians.UI.Settings.Panels().TestApp.canvas:Show()")  # Blizzard shows the canvas
    assert app.eval("#Bastians.UI.Settings.Panels().TestApp.canvas.widgets") > 5
    app.execute("Bastians:NewModule('Late', { addon = 'Bastians_TestApp', title = 'Late One' })")
    assert app.eval("Bastians.UI.Settings.Panels().Late ~= nil") is True


def test_general_page_and_slash_commands(app: WowRuntime):
    app.execute("Bastians.UI.Hub.Open('Core')")
    texts = labels(app)
    assert texts[0] == "Profiles" and "Extra tooltip lines" in texts and "Font" in texts
    assert "Enabled" not in texts  # Core has no switch
    app.slash("/bastians profile Alt")
    assert app.eval("Bastians:GetProfile()") == "Alt"
    assert any("Profile: Alt" in line for line in app.chat)
    app.slash("/bastians debug")
    assert (
        app.eval("Bastians.debug") is True
        and app.eval("Bastians:GetModule('Core').db.global.debug") is True
    )
    app.slash("/bastians debug")
    app.execute("Bastians:Log(nil, 'info', 'hello log')")
    app.slash("/bastians log 5")
    assert any("hello log" in line for line in app.chat)
    app.slash("/bastians nonsense")
    assert any("/bastians:" in line for line in app.chat)
    app.execute("Bastians:GetModule('Core').db.profile.tooltipLines = 1")
    fresh = app.reload()
    assert fresh.eval("Bastians:GetModule('Core').db.profile.tooltipLines") == 1
    assert fresh.eval("Bastians:GetProfile()") == "Alt"


def test_load_on_demand_switch_loads_the_app_at_login(wow: WowRuntime):
    wow.start("Bastians_Core")
    assert "Bastians_Route" not in wow.loaded
    assert list(wow.eval("Bastians.UI.Settings.LodApps()").keys()) == ["Bastians_Route"]
    wow.execute("Bastians.UI.Settings.SetLod('Bastians_Route', true)")
    assert "Bastians_Route" in wow.loaded
    fresh = wow.reload()
    assert "Bastians_Route" in fresh.loaded  # loaded at login from the switch
    fresh.execute("Bastians.UI.Settings.SetLod('Bastians_Route', false)")
    assert any("next /reload" in line for line in fresh.chat)
    again = fresh.reload()
    assert "Bastians_Route" not in again.loaded


def test_font_setting_applies_to_kit_text(app: WowRuntime):
    assert app.eval("Bastians.UI.Style.font()") == "Fonts\\ARIALN.TTF"
    app.execute(
        "Bastians:GetModule('Core').db.profile.font = 'Fonts\\\\FRIZQT__.TTF'; Bastians.UI.Style.applyFont()"
    )
    assert app.eval("Bastians.UI.Style.font()") == "Fonts\\FRIZQT__.TTF"
    app.execute("Bastians.UI.Hub.Open('Core')")
    assert app.eval("(Bastians.UI.Hub.win.title:GetFont())") == "Fonts\\FRIZQT__.TTF"


def test_every_client_font_and_a_text_size(app: WowRuntime):
    """(T1): "only 4 fonts in the options, I want them all, and a size".
    The choice lists every file the client's font objects use (GetFonts), named where known, plus
    LibSharedMedia's fonts when another addon loads it; the text size scales every kit text and
    keeps each text's own base size."""
    choices = dict(app.eval("Bastians.UI.Settings.FontChoices()"))
    assert choices["Fonts\\ARIALN.TTF"] == "Arial Narrow"
    assert choices["Fonts\\K_Pagetext.TTF"] == "Pagetext"  # from the client's QuestFont
    assert choices["Fonts\\2002B.TTF"] == "2002 Bold"
    assert len(choices) >= 6
    # LibSharedMedia's fonts join when it is there
    app.execute(
        """
        LibStub:NewLibrary("LibSharedMedia-3.0", 1).HashTable = function(_, kind)
          return kind == "font" and { ["Expressway"] = "Interface\\\\AddOns\\\\SharedMedia\\\\expressway.ttf" } or {}
        end
        """
    )
    choices = dict(app.eval("Bastians.UI.Settings.FontChoices()"))
    assert choices["Interface\\AddOns\\SharedMedia\\expressway.ttf"] == "Expressway"
    # the size: 120 percent of each text's own size, back to 100
    app.execute(
        """
        local S = Bastians.UI.Style
        sizeA = S.text(UIParent, 12)
        sizeB = S.text(UIParent, 10)
        Bastians:GetModule('Core').db.profile.fontScale = 120
        S.applyFont()
        """
    )
    assert app.eval("(select(2, sizeA:GetFont()))") == 14  # 12 x 1.2 = 14.4
    assert app.eval("(select(2, sizeB:GetFont()))") == 12
    app.execute(
        "Bastians:GetModule('Core').db.profile.fontScale = 100; Bastians.UI.Style.applyFont()"
    )
    assert app.eval("(select(2, sizeA:GetFont()))") == 12
    # a text set to its own size through the kit keeps it across a change
    app.execute("Bastians.UI.Style.setSize(sizeB, 16); Bastians.UI.Style.applyFont()")
    assert app.eval("(select(2, sizeB:GetFont()))") == 16
    app.execute("Bastians.UI.Hub.Open('Core')")
    labels = [
        w.label.GetText(w.label)
        for w in app.eval("Bastians.UI.Hub.canvas.widgets").values()
        if w.label is not None
    ]
    assert "Text size (percent)" in labels
    assert app.errors == []
