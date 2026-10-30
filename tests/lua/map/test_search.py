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


def test_a_zone_from_the_search_fits_the_map_to_it(wow: WowRuntime):
    """ "Underc" found Undercity, a click did nothing."""
    boot(wow, CORE, DATA, MAP)
    wow.execute(f"{MAP_}.Fly(1, 0, 0, 6)")  # far away, on another continent
    wow.execute(f"{SEARCH}.box:SetText('elwynn')")
    wow.run_frames(20)
    assert "zone:1429" in results(wow)
    wow.execute(
        f"local l = {SEARCH}.list for _, r in ipairs({{ l:GetChildren() }}) do if r.ref == 'zone:1429' then r:Click() end end"
    )
    assert wow.eval(f"{SEARCH}.list:IsShown()") is False
    assert wow.eval(f"{MAP_}.Camera().continent") == 0  # the map shows Elwynn Forest now
    assert wow.errors == []


def test_the_arrow_keys_choose_a_result_and_a_choice_clears_the_box(wow: WowRuntime):
    """(R25.29)."""
    boot(wow)
    wow.execute(f"{SEARCH}.box:SetText('el')")
    wow.run_frames(20)
    found = results(wow)
    assert len(found) >= 2
    arrow = f"{SEARCH}.box:GetScript('OnArrowPressed')({SEARCH}.box, '%s')"
    wow.execute(arrow % "DOWN")
    wow.execute(arrow % "DOWN")
    assert wow.eval(f"{SEARCH}.selected") == 2
    wow.execute(arrow % "UP")
    assert wow.eval(f"{SEARCH}.selected") == 1
    wow.execute(arrow % "UP")  # wraps around to the last
    assert wow.eval(f"{SEARCH}.selected") == min(len(found), wow.eval(f"{SEARCH}.LIMIT"))
    wow.execute(f"{SEARCH}.box:GetScript('OnEnterPressed')({SEARCH}.box)")
    assert wow.eval(f"{SEARCH}.box:GetText()") == ""
    assert wow.eval(f"{SEARCH}.list:IsShown()") is False
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


def anchors(wow: WowRuntime, region: str) -> dict[str, str]:
    """A toolbar region's points as {point: "<what>:<relPoint>"}."""
    out = wow.eval(
        f"""(function()
          local r, tb = {region}, {MAP_}.toolbar
          local out = {{}}
          for i = 1, r:GetNumPoints() do
            local point, rel, relPoint = r:GetPoint(i)
            local name = "other"
            for _, key in ipairs({{ "continent", "player", "centred", "dock", "zoomOut", "full" }}) do
              if rel == tb[key] then name = key end
            end
            if rel == tb then name = "bar" end
            out[point] = name .. ":" .. relPoint
          end
          return out
        end)()"""
    )
    return dict(out)


def test_the_search_box_ends_before_the_right_hand_buttons(wow: WowRuntime):
    """(N1): the box covered Dock and half of Follow. It spans from
    Centred to the leftmost
    button of the right group, whatever modules added there."""
    boot(wow)
    assert anchors(wow, f"{SEARCH}.box") == {"LEFT": "centred:RIGHT", "RIGHT": "dock:LEFT"}
    assert wow.eval(f"{MAP_}.toolbar.rows") == 1
    assert wow.errors == []


def test_a_narrow_map_wraps_the_toolbar_into_rows(wow: WowRuntime):
    """in a narrow map the right-hand buttons lay over the search and
    the left-hand buttons. They go to a second row; the search to a row of its own when even
    that is too tight; the map starts under the last row."""
    boot(wow)
    bar = f"{MAP_}.toolbar"
    widths = wow.eval(
        f"""(function()
          local tb = {bar}
          local left = tb.continent:GetWidth() + 6 + tb.player:GetWidth() + 6 + tb.centred:GetWidth()
          local right = tb.full:GetWidth() + 6 + tb.zoomIn:GetWidth() + 2 + tb.zoomOut:GetWidth()
            + 8 + tb.dock:GetWidth()
          return {{ left, right }}
        end)()"""
    )
    left, right = widths[1], widths[2]
    search = wow.eval(f"{MAP_}.SEARCH_MIN")

    def resize(width: float) -> int:
        wow.execute(f"BastiansMapFrame:SetWidth({width + 14}); {MAP_}.LayoutToolbar()")
        return wow.eval(f"{bar}.rows")

    assert resize(left + search + right + 16) == 1
    # one pixel less: the right group goes to the second row, the search fills the first
    assert resize(left + search + right + 15) == 2
    assert anchors(wow, f"{SEARCH}.box") == {"LEFT": "centred:RIGHT", "TOPRIGHT": "bar:TOPRIGHT"}
    point = wow.eval(f"{{ {bar}.full:GetPoint(1) }}")
    assert (point[1], point[3], point[5]) == ("TOPRIGHT", "TOPRIGHT", -26)
    assert wow.eval(f"{bar}:GetHeight()") == 48
    clip = wow.eval(f"{{ {MAP_}.clip:GetPoint(1) }}")
    assert (
        clip[1] == "TOPLEFT"
        and clip[3] == "BOTTOMLEFT"
        and wow.eval(f"select(2, {MAP_}.clip:GetPoint(1)) == {bar}")
    )
    # narrower than the left group and the search: the search goes beside the right group
    if left + 8 + search > search + 8 + right:
        assert resize(left + 8 + search - 1) == 2
        assert anchors(wow, f"{SEARCH}.box") == {"TOPLEFT": "bar:TOPLEFT", "RIGHT": "dock:LEFT"}
    # too narrow for both: three rows, the search alone on the last
    assert resize(min(left + 8 + search, search + 8 + right) - 1) == 3
    assert anchors(wow, f"{SEARCH}.box") == {"TOPLEFT": "bar:TOPLEFT", "TOPRIGHT": "bar:TOPRIGHT"}
    assert wow.eval(f"{bar}:GetHeight()") == 74
    # wide again: one row
    assert resize(2000) == 1
    assert wow.eval(f"{bar}:GetHeight()") == 22
    assert wow.errors == []
