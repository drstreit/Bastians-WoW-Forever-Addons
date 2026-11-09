"""The mini map is the button (ADR 0056, PA6): a person's page shows their zone with a dot where
they stand and has no Map button; a click opens the large map at that place; a zone's figure is its
map; the action stays in More; the page follows a change of the style."""

import sys
from pathlib import Path

from harness import WowRuntime
from pages import band_buttons

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools"))
from mapstyle.emit import style_lua

CORE, DATA, QUESTS, MAP, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Map",
    "Bastians_Browser",
)
MOD = "Bastians:GetModule('Browser')"
BR = f"{MOD}.Browser"
DS = f"{MOD}.dossier"
PERSON = "npc:240"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, QUESTS, MAP, BROWSER)))
    wow.run_frames(10)
    wow.advance(0.3)
    return wow


def open_page(wow: WowRuntime, ref: str) -> None:
    wow.execute(f"{BR}.Open('{ref}')")
    wow.run_frames(5)
    wow.execute(f"{DS}.scroll:SetSize(800, 700); {DS}:Refresh()")
    wow.run_frames(3)


def map_cells(wow: WowRuntime) -> list:
    out = []
    for bf in wow.eval(f"{DS}.blockPool").values():
        if bf.IsShown(bf) and bf.mode == "maps":
            out.extend(c for c in bf.cells.values() if c.IsShown(c))
    return out


def test_a_persons_place_is_a_mini_map_and_the_page_has_no_map_button(wow: WowRuntime):
    boot(wow)
    open_page(wow, PERSON)
    cells = map_cells(wow)
    assert len(cells) == 1
    cell = cells[0]
    assert cell.caption.GetText(cell.caption).startswith("Elwynn Forest")
    assert sum(1 for d in cell.dots.values() if d.IsShown(d)) >= 1
    assert "Show on map" not in band_buttons(wow, DS) and "Map" not in band_buttons(wow, DS)
    # it stays in the menu of every action behind More
    assert "More" in band_buttons(wow, DS)
    ids = [a.id for a in wow.eval(f"Bastians:GetActions('{PERSON}', {{}})").values()]
    assert "map.show" in ids
    assert wow.errors == []


def test_a_click_opens_the_large_map_at_the_place(wow: WowRuntime):
    boot(wow)
    open_page(wow, PERSON)
    wow.execute(
        """
        RAN = {}
        local run = Bastians.RunAction
        Bastians.RunAction = function(self, id, ref, ctx)
          RAN[#RAN + 1] = { id = id, ref = ref, point = ctx and ctx.points and ctx.points[1] }
          return true
        end
        """
    )
    cell = map_cells(wow)[0]
    cell.Click(cell, "LeftButton")
    ran = wow.eval("RAN[1]")
    place = cell.places[1].place
    assert (ran.id, ran.ref) == ("map.show", PERSON)
    assert (ran.point.map, ran.point.x, ran.point.y) == (place.map, place.x, place.y)
    assert wow.errors == []


def test_a_zones_figure_is_its_map_and_it_has_no_map_button(wow: WowRuntime):
    boot(wow)
    open_page(wow, "zone:1429")
    buttons = band_buttons(wow, DS)
    assert "Zone on map" not in buttons and "Map" not in buttons
    assert wow.errors == []


def test_without_the_map_nothing_breaks(wow: WowRuntime):
    boot(wow, CORE, DATA, QUESTS, BROWSER)
    open_page(wow, PERSON)
    assert len(map_cells(wow)) == 1
    assert wow.eval("Bastians:GetService('mapPicture')") is None
    assert wow.errors == []


def test_the_page_follows_a_change_of_the_style(wow: WowRuntime):
    boot(wow)
    # around Marshal Dughan's Elwynn: every cell the mock's map asks for
    wow.execute(
        style_lua(
            "pencil",
            wow.client,
            "test",
            {0: [(7, 7), (7, 8), (8, 7), (8, 8)]},
            {0: [(3, 3), (3, 4), (4, 3), (4, 4)]},
        )
    )
    wow.execute("Bastians.Deliver()")
    open_page(wow, PERSON)
    cell = map_cells(wow)[0]

    def styled() -> bool:
        shown = [t for t in cell.art.values() if t.IsShown(t)]
        return any("Bastians_Map_Pencil" in str(t.GetTexture(t)) for t in shown)

    assert styled() is False
    wow.execute("Bastians:GetModule('Map').Map.SetStyle('pencil')")
    wow.advance(0.3)
    wow.run_frames(5)
    assert styled() is True
    assert wow.errors == []


def test_a_zones_tile_carries_the_zone(wow: WowRuntime):
    boot(wow)
    assert wow.eval("Bastians:Entity('zone:1429'):Facet('tile').map") == 1429
    assert wow.eval("Bastians:Entity('npc:240'):Facet('tile').map") is None
    wow.execute(f"{BR}.List('zone')")
    wow.run_frames(5)
    tree = f"{MOD}.tree"
    wow.execute(f"{tree}.scroll:SetSize(440, 700); {tree}:Refresh()")
    tiles = [f for f in wow.eval(f"{tree}.pool").values() if f.IsShown(f) and f.tile]
    elwynn = next(f for f in tiles if f.row.ref == "zone:1429")
    assert elwynn.mini.IsShown(elwynn.mini) is True
    assert any(t.IsShown(t) for t in elwynn.mini.art.values())  # the painting: no style chosen
    assert elwynn.icon.IsShown(elwynn.icon) is False
    # a pooled frame that shows another type next: the map goes
    wow.execute(f"{BR}.List('npc')")
    wow.run_frames(5)
    wow.execute(f"{tree}.scroll:SetSize(440, 700); {tree}:Refresh()")
    for frame in wow.eval(f"{tree}.pool").values():
        if frame.IsShown(frame) and frame.mini:
            assert frame.mini.IsShown(frame.mini) is False
    assert wow.errors == []


def test_the_dots_of_a_part_give_every_thing_its_place_first(wow: WowRuntime):
    """Browser.PartDots, pure."""
    boot(wow)
    wow.execute(
        f"""
        local places = {{
          a = {{ {{ map = 1, x = 0.1, y = 0.1 }}, {{ map = 1, x = 0.2, y = 0.2 }}, {{ map = 1, x = 0.3, y = 0.3 }} }},
          b = {{ {{ map = 2, x = 0.5, y = 0.5 }}, {{ map = 1, x = 0.6, y = 0.6 }} }},
          c = {{ {{ map = 2, x = 0.7, y = 0.7 }} }},
        }}
        local rows = {{ {{ ref = "a" }}, {{ ref = "b" }}, {{ ref = "c" }}, {{ ref = "a" }}, {{ text = "no ref" }} }}
        local function of(ref) return places[ref] end
        DOTS = {BR}.PartDots(rows, 1, of, 10)
        FEW = {BR}.PartDots(rows, 1, of, 2)
        """
    )
    assert [(d.row.ref, d.x) for d in wow.eval("DOTS").values()] == [
        ("a", 0.1),
        ("b", 0.6),  # its place in this zone; c has none here
        ("a", 0.2),
        ("a", 0.3),
    ]
    assert [d.row.ref for d in wow.eval("FEW").values()] == ["a", "b"]  # both before a's second
    assert wow.errors == []


def test_a_zones_open_part_is_the_map_with_its_dots(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{BR}.List('zone')")
    wow.run_frames(5)
    wow.execute(f"{MOD}.detailPane:SetSize(800, 600)")
    wow.execute(f"{BR}.StepInside('zone:1429')")
    wow.run_frames(5)
    assert wow.eval(f"{MOD}.partMap") is None  # no part open: the zone's sheet
    wow.execute(f"{BR}.StepInside('zone:1429', 'people')")
    wow.run_frames(5)
    panel = wow.eval(f"{MOD}.partMap")
    assert panel.IsShown(panel) is True
    assert panel.title.GetText(panel.title) == "Elwynn Forest: People"
    dots = [d for d in panel.dots.values() if d.IsShown(d)]
    assert len(dots) >= 3
    names = {d.tip for d in dots}
    assert "Marshal Dughan" in names
    assert any(t.IsShown(t) for t in panel.art.values())
    # a click on a dot picks its thing: the sheet comes back
    dughan = next(d for d in dots if d.tip == "Marshal Dughan")
    dughan.Click(dughan, "LeftButton")
    wow.run_frames(5)
    assert wow.eval(f"{BR}.PageRef()") == dughan.row.ref
    assert panel.IsShown(panel) is False
    assert wow.eval(f"{BR}.ListEntry().part") == "people"  # the list keeps the part
    # back on the thing, the part shut: no map
    wow.execute(f"{BR}.Back()")
    wow.run_frames(5)
    assert panel.IsShown(panel) is True
    wow.execute(f"{BR}.ListEntry().part = nil; {BR}.Render()")
    wow.run_frames(3)
    assert panel.IsShown(panel) is False
    assert wow.errors == []


def test_a_person_has_no_map_of_their_parts(wow: WowRuntime):
    """Only a zone and an area are maps of their parts."""
    boot(wow)
    assert wow.eval(f"{BR}.PartMapOf('npc:240')") is None
    assert wow.eval(f"{BR}.PartMapOf('zone:1429')") == 1429
    wow.execute(f"{BR}.List('npc')")
    wow.run_frames(5)
    wow.execute(f"{MOD}.detailPane:SetSize(800, 600)")
    wow.execute(f"{BR}.StepInside('npc:240', 'where')")
    wow.run_frames(5)
    assert wow.eval(f"{MOD}.partMap") is None
    assert wow.errors == []


def mark_of(wow: WowRuntime):
    """The player's mark on the first mini map of the page, nil where it has none."""
    for cell in map_cells(wow):
        return cell.cut.playerMark
    return None


def test_the_player_stands_on_the_mini_map_of_their_zone(wow: WowRuntime):
    """ADR 0056, PA6: a mark on a mini map of the player's map, at their place; it follows while
    it is seen, and the timer stops when no mark is seen."""
    boot(wow)
    wow.execute("Mock.playerMap = 1429; Mock.playerMapPos = { x = 0.5, y = 0.25 }")
    open_page(wow, PERSON)
    mark = mark_of(wow)
    assert mark is not None and mark.IsShown(mark) is True
    w, h = mark.w, mark.h
    assert mark.GetPoint(mark, 1)[3] == 0.5 * w
    assert mark.GetPoint(mark, 1)[4] == -0.25 * h
    # the player walks: the mark follows without a redraw of the page
    wow.execute("Mock.playerMapPos = { x = 0.25, y = 0.25 }")
    wow.advance(1.1)
    assert mark.GetPoint(mark, 1)[3] == 0.25 * w
    # another map: no mark
    wow.execute("Mock.playerMap = 1411")
    wow.advance(1.1)
    assert mark.IsShown(mark) is False
    # the window shut: the timer ends with the last mark seen
    wow.execute("Mock.playerMap = 1429")
    wow.execute(f"{MOD}.win:Hide()")
    wow.advance(2.2)
    wow.execute("Mock.playerMapPos = { x = 0.75, y = 0.25 }")
    wow.advance(1.1)
    assert mark.GetPoint(mark, 1)[3] == 0.25 * w
