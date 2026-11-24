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


def head_layout(wow: WowRuntime, width: float) -> int:
    """Lays the map's window out `width` wide (the mock gives anchors no size) -> its rows."""
    wow.execute(
        f"local w = {MAP_}.win; w.frame:SetWidth({width}); w.head:SetWidth({width} - 2);"
        f" w.content:SetWidth({width} - 2); {MAP_}.LayoutToolbar()"
    )
    return wow.eval(f"{MAP_}.toolbar.rows")


def test_the_search_box_stands_in_the_head_and_ends_before_the_tools(wow: WowRuntime):
    """(N1): the box covered Dock and half of Follow. Since W9 (ADR
    0084) the search and the toolbar's parts are the head's: Core's bar lays the box out after
    the name and the tools before the window's own pictograms."""
    boot(wow)
    bar, head = f"{MAP_}.toolbar", f"{MAP_}.win.headBar"
    assert wow.eval(f"{head}.search == {SEARCH}.box") is True
    assert wow.eval(f"{SEARCH}.box:GetParent() == {MAP_}.win.head") is True
    assert wow.eval(f"{SEARCH}.box:GetHeight()") == 28  # a tall head's tool
    assert head_layout(wow, 1458) == 1
    # every part is a tool of the head, in the board's order; Full the one filled plate
    names = (
        "continent",
        "player",
        "centred",
        "browser",
        "route",
        "dock",
        "city",
        "zoomOut",
        "zoomIn",
        "full",
    )
    order = wow.eval(
        f"""(function()
          local out = {{}}
          for _, t in ipairs({head}.order) do
            for _, k in ipairs({{ "{'", "'.join(names)}" }}) do
              if {bar}[k] == t then out[#out + 1] = k end
            end
          end
          return table.concat(out, " ")
        end)()"""
    )
    assert order == " ".join(names)
    assert wow.eval(f"{bar}.full.spec.primary") is True
    assert wow.eval(f"{bar}.continent.spec.menu") is True  # a select: a small arrow
    for k in ("continent", "player", "centred", "dock", "zoomOut", "zoomIn"):
        assert wow.eval(f"{bar}.{k}:GetParent() == {MAP_}.win.head") is True
        assert wow.eval(f"{bar}.{k}:GetHeight()") == 28
    # the tools from the right: Full before the options, each tool left of the next shown one
    assert wow.eval(f"select(2, {bar}.full:GetPoint(1)) == {MAP_}.win.options") is True
    assert wow.eval(f"select(2, {bar}.zoomIn:GetPoint(1)) == {bar}.full") is True
    assert wow.eval(f"select(2, {bar}.zoomOut:GetPoint(1)) == {bar}.zoomIn") is True
    assert wow.eval(f"select(2, {bar}.dock:GetPoint(1)) == {bar}.zoomOut") is True
    # the box after the name, as wide as the bar allows; the map begins under the head
    assert wow.eval(f"{SEARCH}.box:GetWidth()") == 230
    assert tuple(wow.eval(f"{{ {MAP_}.clip:GetPoint(1) }}").values())[3:] == (0, 0)
    # the foot: 20 high on the band's ground with a rule over it; the map ends on it
    assert wow.eval(f"{MAP_}.footer:GetHeight()") == 20
    assert wow.eval(f"{MAP_}.footer.rule:GetHeight()") == 1
    assert tuple(wow.eval(f"{{ {MAP_}.clip:GetPoint(2) }}").values())[3:] == (0, 20)
    assert wow.errors == []


def test_a_narrow_map_puts_the_tools_under_the_head(wow: WowRuntime):
    """in a narrow map the right-hand buttons lay over the search and
    the left-hand buttons. Since W9 the head keeps the search at its least width and the tools
    take rows of their own under it; the map starts under the last row."""
    boot(wow)
    bar, head = f"{MAP_}.toolbar", f"{MAP_}.win.headBar"
    tools = wow.eval(
        f"""(function()
          local w, n = 0, 0
          for _, t in ipairs({head}.order) do
            if t:IsShown() then w, n = w + t:GetWidth(), n + 1 end
          end
          return w + (n - 1) * 8
        end)()"""
    )
    # what the head needs for the search at its least width, the tools and its own pictograms
    start = wow.eval(f"{MAP_}.win:HeadStart()")
    right = wow.eval(f"select(2, {MAP_}.win:HeadEnd())")
    need = start + 150 + 15 + tools + 15 + right
    assert head_layout(wow, need + 2) == 1 and wow.eval(f"{head}:Room()") == 0
    # one unit less: the tools leave the head for a row under it
    assert head_layout(wow, need + 1) == 2
    assert wow.eval(f"{bar}.full:GetParent() == {head}.toolFrame") is True
    assert wow.eval(f"{head}.toolFrame:IsShown()") is True and wow.eval(f"{head}:Room()") == 38
    assert wow.eval(f"{SEARCH}.box:GetParent() == {MAP_}.win.head") is True  # the search stays
    assert wow.eval(f"{SEARCH}.box:GetWidth()") >= 150
    assert tuple(wow.eval(f"{{ {MAP_}.clip:GetPoint(1) }}").values())[3:] == (0, -38)
    # the least width: the tools wrap on their rows, none past the window's edge
    assert head_layout(wow, 400) >= 3
    rows = wow.eval(f"{head}.toolRows")
    assert wow.eval(f"{head}:Room()") == rows * 28 + (rows + 1) * 6 - 2
    for k in ("continent", "player", "centred", "dock", "zoomOut", "zoomIn", "full"):
        point = tuple(wow.eval(f"{{ {bar}.{k}:GetPoint(1) }}").values())
        assert point[3] + wow.eval(f"{bar}.{k}:GetWidth()") <= 400 - 2 - 2 * 15
    # wide again: one row, the tools in the head
    assert head_layout(wow, 2000) == 1
    assert wow.eval(f"{bar}.full:GetParent() == {MAP_}.win.head") is True
    assert wow.eval(f"{head}.toolFrame:IsShown()") is False
    assert wow.errors == []


def test_the_continent_is_a_select_of_the_head(wow: WowRuntime):
    boot(wow)
    continent = f"{MAP_}.toolbar.continent"
    assert wow.eval(f"{continent}.label:GetText()") == wow.eval(
        f"{continent}.values[{continent}:GetValue()]"
    )
    wow.execute(f"{continent}:Click()")
    menu = wow.eval("Bastians.UI.FilterMenuFrame()")
    labels = [i.label.GetText(i.label) for i in menu["items"].values() if i.IsShown(i)]
    assert labels == sorted(labels) and len(labels) >= 2  # by name
    other = next(
        k
        for k, v in dict(wow.eval(f"{continent}.values")).items()
        if k != wow.eval(f"{continent}:GetValue()")
    )
    wow.execute(f"{MAP_}.SetContinent({other})")
    assert wow.eval(f"{continent}:GetValue()") == other
    assert wow.eval(f"{continent}.label:GetText()") == wow.eval(f"{continent}.values[{other}]")
    assert wow.errors == []
