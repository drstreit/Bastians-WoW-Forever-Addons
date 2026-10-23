"""Owner feedback from the Forever beta, 21.10.2026: Browser lists crashed on mixed facet values,
dropdowns stayed open, the map's right click lost "Route here", the hub could not open a window."""

from harness import WowRuntime
from pages import pills

CORE, DATA, QUESTS, BROWSER, MAP, ROUTE = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Browser",
    "Bastians_Map",
    "Bastians_Route",
)
BR = "Bastians:GetModule('Browser')"


def test_facet_values_become_sortable_strings(wow: WowRuntime):
    wow.start(CORE, DATA, BROWSER)
    key = f"{BR}.Browser.FacetKey"
    # a list stays a list (an NPC with two services counts for both, ADR 0016), one item its text
    assert list(wow.eval(f"{key}({{ 'elite', 'questgiver' }})").values()) == ["elite", "questgiver"]
    assert wow.eval(f"{key}({{ 'vendor' }})") == "vendor"
    assert wow.eval(f"{key}(29)") == "29"
    assert wow.eval(f"{key}(nil)") == "Other" and wow.eval(f"{key}('')") == "Other"
    assert wow.eval(f"{key}('vendor')") == "vendor"


def test_npc_list_builds_with_chips_from_the_fixture_packs(wow: WowRuntime):
    wow.start(CORE, DATA, QUESTS, BROWSER)
    wow.run_frames(10)
    wow.execute(f"{BR}.Browser.List('npc')")
    wow.run_frames(30)
    chips = pills(wow, f"{BR}.tree")
    assert chips and chips[0] == "Where: Here"
    rows = [r.text for r in wow.eval(f"{BR}.tree.flat").values()]
    assert rows and "Building the list" not in rows[0]
    assert wow.errors == []


def test_select_list_closes_on_a_click_elsewhere(wow: WowRuntime):
    """The Browser's type dropdown is gone (ADR 0013 F); the Map's continent select is the same
    widget."""
    wow.start(CORE, DATA, MAP)
    wow.run_frames(5)
    wow.slash("/bmap")
    select = "Bastians:GetModule('Map').Map.toolbar.continent"
    wow.execute(f"{select}:Open()")
    assert wow.eval(f"{select}.list:IsShown()") is True
    wow.execute("Mock.cursorX, Mock.cursorY = -5000, -5000")  # far from the list and its button
    wow.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
    assert wow.eval(f"{select}.list:IsShown()") is False
    assert wow.errors == []


def test_route_here_is_offered_only_with_a_point_in_the_context(wow: WowRuntime):
    wow.start(CORE, DATA, MAP, ROUTE)
    wow.run_frames(10)
    labels = [
        a.label
        for a in wow.eval(
            "Bastians:GetActions('zone:1429', { source = 'map', point = { 0, -9000, 100, 'Goldshire road' } })"
        ).values()
    ]
    assert "Route here" in labels
    plain = [
        a.label for a in wow.eval("Bastians:GetActions('zone:1429', { source = 'map' })").values()
    ]
    assert "Route here" not in plain
    assert wow.eval("Bastians:GetService('travel').Go ~= nil") is True
    assert wow.errors == []


def test_hub_open_button_opens_the_app_window(app: WowRuntime):
    app.execute("Bastians.UI.Hub.Open('TestApp')")
    row = list(app.eval("Bastians.UI.Hub.canvas.widgets").values())[1]  # after the switch
    assert row.button.label.GetText(row.button.label) == "Open Test App"
    app.execute("Bastians.UI.Hub.canvas.widgets[2].button:Click()")
    assert app.eval("testAppOpened") == 1
    app.execute("Bastians.UI.Hub.canvas.widgets[1]:Click()")  # the enable switch: off
    app.execute("Bastians.UI.Hub.canvas.widgets[2].button:Click()")
    assert app.eval("testAppOpened") == 1  # a switched-off app says so instead of opening
    assert app.errors == []
