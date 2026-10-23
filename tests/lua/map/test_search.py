"""The map's search bar (B8.6): results from the second character, a type word narrows, a click
flies the map to the entity, Route is offered when Route is there, the list closes on an outside
click and on Escape."""

from harness import WowRuntime

CORE, DATA, MAP, ROUTE = "Bastians_Core", "Bastians_Data", "Bastians_Map", "Bastians_Route"
MOD = "Bastians:GetModule('Map')"
MAP_ = f"{MOD}.Map"
SEARCH = f"{MOD}.Search"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, MAP)))
    wow.run_frames(10)
    wow.slash("/bmap")
    wow.execute(f"{MAP_}.clip:SetSize(600, 400); {MAP_}.ViewChanged()")
    return wow


def results(wow: WowRuntime) -> list[str]:
    return [r.ref for r in wow.eval(f"{SEARCH}.results").values()]


def children(wow: WowRuntime) -> list:
    return list(wow.eval(f"{{ {SEARCH}.list:GetChildren() }}").values())


def visible_rows(wow: WowRuntime) -> list[str]:
    out = []
    for r in children(wow):
        if r.IsShown(r) and r.label is not None:
            out.append(r.label.GetText(r.label))
    return out


def test_typing_searches_from_the_second_character(wow: WowRuntime):
    boot(wow, CORE, DATA, "Bastians_Quests", MAP)  # Quests brings the quest-text provider
    box = f"{SEARCH}.box"
    wow.execute(f"{box}:SetText('h')")
    wow.run_frames(10)
    assert results(wow) == [] and wow.eval(f"{SEARCH}.list:IsShown()") is False
    wow.execute(f"{box}:SetText('hog')")
    wow.run_frames(20)
    assert "npc:448" in results(wow)  # Hogger, from the fixture World pack
    assert wow.eval(f"{SEARCH}.list:IsShown()") is True
    assert any("Hogger" in t for t in visible_rows(wow))
    # a type word narrows: the quest 'Wanted: "Hogger"' is a quest, not an npc
    wow.execute(f"{box}:SetText('quest hog')")
    wow.run_frames(20)
    assert all(ref.startswith("quest:") for ref in results(wow)) and results(wow)
    wow.execute(f"{box}:SetText('npc hog')")
    wow.run_frames(20)
    assert results(wow) == ["npc:448"]
    assert wow.errors == []


def test_a_click_flies_the_map_and_route_is_offered_with_route(wow: WowRuntime):
    boot(wow, CORE, DATA, MAP, ROUTE)
    wow.execute(f"{SEARCH}.box:SetText('npc hog')")
    wow.run_frames(20)
    assert results(wow) == ["npc:448"]
    row = next(r for r in children(wow) if r.IsShown(r) and r.ref == "npc:448")
    assert row.route.IsShown(row.route) is True  # Route registers route.to
    before = wow.eval(f"{MAP_}.Camera().wx")
    wow.execute(
        f"local l = {SEARCH}.list for _, r in ipairs({{ l:GetChildren() }}) do if r.ref == 'npc:448' then r:Click() end end"
    )
    assert wow.eval(f"{SEARCH}.list:IsShown()") is False
    assert wow.eval(f"{MAP_}.Camera().wx") != before  # flew to Hogger (map.show)
    assert wow.eval(f"{MAP_}.Camera().level") >= 5
    assert wow.errors == []


def test_without_route_no_route_button_and_escape_closes(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{SEARCH}.box:SetText('hog')")
    wow.run_frames(20)
    row = next(r for r in children(wow) if r.IsShown(r) and r.ref == "npc:448")
    assert row.route.IsShown(row.route) is False
    wow.execute(f"{SEARCH}.box:GetScript('OnEscapePressed')({SEARCH}.box)")
    assert (
        wow.eval(f"{SEARCH}.list:IsShown()") is False and wow.eval(f"{SEARCH}.box:GetText()") == ""
    )
    # a click elsewhere closes the open list too
    wow.execute(f"{SEARCH}.box:SetText('hog')")
    wow.run_frames(20)
    assert wow.eval(f"{SEARCH}.list:IsShown()") is True
    wow.execute("Mock.cursorX, Mock.cursorY = -5000, -5000")
    wow.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
    assert wow.eval(f"{SEARCH}.list:IsShown()") is False
    assert wow.errors == []


def test_the_search_box_ends_before_the_right_hand_buttons(wow: WowRuntime):
    """(N1): the box covered Dock and half of Follow. It spans from Player
    to the leftmost button of the right group, whatever modules added there."""
    boot(wow)
    anchors = wow.eval(
        f"""(function()
          local box, tb = {SEARCH}.box, {MAP_}.toolbar
          local out = {{}}
          for i = 1, box:GetNumPoints() do
            local point, rel, relPoint = box:GetPoint(i)
            local name = rel == tb.player and "player" or rel == tb.dock and "dock" or "other"
            out[point] = name .. ":" .. relPoint
          end
          return out
        end)()"""
    )
    assert dict(anchors) == {"LEFT": "player:RIGHT", "RIGHT": "dock:LEFT"}
    assert wow.errors == []
