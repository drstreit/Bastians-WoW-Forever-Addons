"""Stepping inside (ADR 0056, PA4): a click on a card's "All N" or on the edge of a tile moves the
thing into the list tile: its own tile on top, then its parts as headings with their counts, one
open at a time with its things as tiles and its sections as chips. The page tile shows what is
picked there; the breadcrumb says where the two tiles are and every step of it is a way back."""

import re

from harness import WowRuntime
from pages import chip, chips, nav_active

CORE, DATA, QUESTS, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Browser",
)
MOD = "Bastians:GetModule('Browser')"
BR = f"{MOD}.Browser"
DS = f"{MOD}.dossier"
TREE = f"{MOD}.tree"
SIZE = f"{TREE}.scroll:SetSize(440, 700); {TREE}:Refresh()"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA, QUESTS, BROWSER)
    wow.run_frames(10)
    wow.advance(0.3)
    return wow


def strip(text: str | None) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    return re.sub(r"\|c[0-9a-fA-F]{8}", "", text).replace("|r", "")


def settle(wow: WowRuntime) -> None:
    wow.run_frames(5)
    wow.execute(SIZE)


def drawn(wow: WowRuntime) -> list[tuple]:
    """The list tile as drawn, top down: (ref or None, the first line, is it a tile)."""
    frames = [f for f in wow.eval(f"{TREE}.pool").values() if f.IsShown(f) and f.row]
    frames.sort(key=lambda f: f.index)
    return [(f.row.ref, strip(f.text.GetText(f.text)), bool(f.tile)) for f in frames]


def frame_of(row_id: str) -> str:
    return (
        f"(function() for _, f in ipairs({TREE}.pool) do "
        f"if f:IsShown() and f.row and f.row.id == '{row_id}' then return f end end end)()"
    )


def crumbs(wow: WowRuntime) -> list[tuple]:
    return [(c.kind, c.text) for c in wow.eval(f"{BR}.Crumbs()").values()]


def click_crumb(wow: WowRuntime, n: int) -> None:
    wow.execute(f"{MOD}.crumbs.buttons[{n}]:Click()")
    settle(wow)


def test_a_thing_with_parts_can_be_stepped_into(wow: WowRuntime):
    boot(wow)
    inside = f"{BR}.HasInside"
    assert wow.eval(f"{inside}('zone:1429')") is True and wow.eval(f"{inside}('npc:240')") is True
    assert wow.eval(f"{inside}('dungeon:36')") is True
    assert wow.eval(f"{inside}('quest:62')") is False  # a quest is one sheet (ADR 0056)
    assert wow.eval(f"{inside}('nonsense')") is False
    assert wow.errors == []


def test_the_list_tile_takes_the_thing_with_its_parts(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{BR}.List('zone')")
    settle(wow)
    wow.execute(f"{BR}.StepInside('zone:1429')")
    settle(wow)
    assert wow.eval(f"{BR}.Current().kind") == "inside"
    assert wow.eval(f"{BR}.PageRef()") == "zone:1429"  # the thing itself on the right
    assert wow.eval(f"{MOD}.win.title:GetText()") == "Elwynn Forest"
    # its own tile, then its parts with the number of their things; none open
    assert drawn(wow) == [
        ("zone:1429", "Elwynn Forest", True),
        (None, "+  Your quests here  5", False),
        (None, "+  Chains here  1", False),
        (None, "+  Places  1", False),
        (None, "+  People  5", False),
        (None, "+  Monsters  3", False),
        (None, "+  Roads  1", False),
    ]
    assert wow.eval(f"{frame_of('inside:part:quests')}:GetHeight()") == 28  # a target of 28
    assert crumbs(wow) == [("list", "Zones"), ("thing", "Elwynn Forest")]
    assert nav_active(wow) == "nav:list:zone"  # the list it was stepped into from stays lit
    # a part opens on a click: its things as tiles, by their own names
    wow.execute(f"{frame_of('inside:part:people')}:Click()")
    settle(wow)
    rows = drawn(wow)
    assert rows[4] == (None, "-  People  5", False)
    people = rows[5:10]
    assert all(tile and ref.startswith("npc:") for ref, _, tile in people)
    assert "Marshal Dughan" in [name for _, name, _ in people]
    assert rows[10] == (None, "+  Monsters  3", False)
    assert crumbs(wow)[-1] == ("part", "People")
    assert (
        strip(wow.eval(f"{MOD}.summary:GetText()")) == ""
    )  # unfiltered: the foot counts (ADR 0058)
    # one part open at a time: another opens, this one shuts
    wow.execute(f"{frame_of('inside:part:monsters')}:Click()")
    settle(wow)
    rows = drawn(wow)
    assert (None, "+  People  5", False) in rows and (None, "-  Monsters  3", False) in rows
    assert [name for ref, name, tile in rows if tile and ref != "zone:1429"] == [
        "Goldtooth",
        "Hogger",
        "Leprithus",  # the rare (A3.3)
    ]
    # a click on the open part shuts it
    wow.execute(f"{frame_of('inside:part:monsters')}:Click()")
    settle(wow)
    assert len(drawn(wow)) == 7 and wow.eval(f"{BR}.Current().part") is None
    assert wow.errors == []


def test_a_picked_tile_shows_on_the_page_and_the_crumbs_lead_back(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{BR}.List('zone')")
    settle(wow)
    wow.execute(f"{BR}.StepInside('zone:1429', 'monsters')")
    settle(wow)
    hogger = next(
        f"{TREE}.flat[{i}]" for i, r in wow.eval(f"{TREE}.flat").items() if r.ref == "npc:448"
    )
    wow.execute(f"local row = {hogger} {TREE}.opts.onClick(row, 'LeftButton', {TREE})")
    settle(wow)
    # the page tile shows the monster; the list tile keeps the zone with its open part
    assert wow.eval(f"{BR}.PageRef()") == "npc:448"
    assert wow.eval(f"{BR}.ListEntry().kind") == "inside"
    assert wow.eval(f"{BR}.ListEntry().part") == "monsters"
    assert crumbs(wow) == [
        ("list", "Zones"),
        ("thing", "Elwynn Forest"),
        ("part", "Monsters"),
        ("page", "Hogger"),
    ]
    # the thing's step: its page again, its parts shut
    click_crumb(wow, 2)
    assert wow.eval(f"{BR}.PageRef()") == "zone:1429"
    assert (
        wow.eval(f"{BR}.ListEntry().kind") == "inside"
        and wow.eval(f"{BR}.ListEntry().part") is None
    )
    # the first step: the list it was stepped into from
    click_crumb(wow, 1)
    assert (
        wow.eval(f"{BR}.ListEntry().kind") == "list"
        and wow.eval(f"{BR}.ListEntry().type") == "zone"
    )
    assert crumbs(wow)[0] == ("list", "Zones")
    # Back walks the same way
    wow.execute(f"{BR}.Back()")
    settle(wow)
    assert wow.eval(f"{BR}.ListEntry().kind") == "inside"
    assert wow.errors == []


def test_a_part_with_several_sections_has_them_as_chips(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{BR}.StepInside('zone:1429', 'quests')")
    settle(wow)
    labels = [(label, count) for label, count, _ in chips(wow)]
    assert labels[0] == ("All", 5)
    assert ("To do here", 2) in labels and ("Hand in", 1) in labels
    # a tile inside is the thing's own tile: the name alone, no level in brackets
    quests = [
        (ref, name) for ref, name, tile in drawn(wow) if tile and str(ref).startswith("quest:")
    ]
    assert len(quests) == 4 and not any("[" in name for _, name in quests)
    chip(wow, "Hand in")
    settle(wow)
    assert wow.eval(f"{BR}.Current().block") == "quests.zone.turnin"
    rows = [(ref, tile) for ref, _, tile in drawn(wow) if tile and ref != "zone:1429"]
    assert rows == [("quest:62", True)]
    assert strip(wow.eval(f"{MOD}.summary:GetText()")) == "1 of 5 shown"
    chip(wow, "Hand in")  # the same chip again: the whole part
    settle(wow)
    assert wow.eval(f"{BR}.Current().block") is None
    # a part of one section has no chips
    wow.execute(f"{BR}.StepInside('zone:1429', 'monsters')")
    settle(wow)
    assert wow.eval(f"{MOD}.filterHost:IsShown()") is False
    assert wow.errors == []


def test_no_tile_has_an_edge_and_a_cards_all_opens_where_it_stands(wow: WowRuntime):
    """(R2): "no not working - we better do as I said and have a filter
    in the right pane". ~~A tile's edge and a card's "All N" stepped inside (ADR 0056).~~ No tile
    has the edge or a double click; "All N" opens the card on the page."""
    boot(wow)
    wow.execute(f"{BR}.List('zone')")
    settle(wow)
    elwynn = frame_of("zone:1429")
    assert wow.eval(f"{elwynn}.edge == nil or not {elwynn}.edge:IsShown()") is True
    assert wow.eval(f"{elwynn}:GetScript('OnDoubleClick')") is None  # two clicks, no step
    # a card's "All N": the dossier opens the card itself (no host step)
    wow.execute(f"{BR}.Open('npc:240')")
    settle(wow)
    assert wow.eval(f"{DS}.opts.onChapter") is None
    assert wow.eval(f"{BR}.Current().kind") == "page"
    assert wow.errors == []


def test_the_page_tile_has_a_filter_that_narrows_every_list_of_the_page(wow: WowRuntime):
    """(R2): "we add a new filter to the right tile - only when more than
    1 node is listed there ... if I am in a dungeon and start typing in that filter, I expect that
    all node lists are reduced accordingly. pictures disappear when I type, only nodes are shown"."""
    boot(wow)
    wow.execute(f"{BR}.Open('zone:1429')")
    settle(wow)
    box = f"{MOD}.Browser.PageFilterBox()"
    assert wow.eval(f"{BR}.PageThings()") > 1
    assert wow.eval(f"{box}:IsShown()") is True
    assert wow.eval(f"{DS}.band:IsShown()") is True
    wow.execute(f"{box}:SetText('dughan')")
    settle(wow)
    assert wow.eval(f"{DS}:Searching()") is True
    assert wow.eval(f"{DS}.band:IsShown()") is False  # the head and its pictures go
    shown = [
        r.ref
        for c in wow.eval(f"{DS}.blockPool").values()
        if c.IsShown(c) and c.tree
        for r in c.tree.flat.values()
        if r.ref
    ]
    assert shown and set(shown) == {"npc:240"}, shown
    # a new page starts unfiltered; a page of one thing has no filter
    wow.execute(f"{BR}.Open('npc:240')")
    settle(wow)
    assert wow.eval(f"{box}:GetText()") == "" and wow.eval(f"{DS}:Searching()") is False
    assert wow.eval(f"{DS}.band:IsShown()") is True
    assert wow.errors == []


def test_a_narrow_window_shows_the_inside_as_its_list(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{BR}.OpenWindow()")
    wow.execute(f"{MOD}.win.frame:SetWidth(430); {MOD}.win.opts.onResize({MOD}.win, false)")
    wow.execute(f"{BR}.StepInside('zone:1429', 'people')")
    settle(wow)
    assert (
        wow.eval(f"{MOD}.listPane:IsShown()") is True
        and wow.eval(f"{MOD}.detailPane:IsShown()") is False
    )
    dughan = next(
        f"{TREE}.flat[{i}]" for i, r in wow.eval(f"{TREE}.flat").items() if r.ref == "npc:240"
    )
    wow.execute(f"local row = {dughan} {TREE}.opts.onClick(row, 'LeftButton', {TREE})")
    settle(wow)
    assert (
        wow.eval(f"{MOD}.detailPane:IsShown()") is True
        and wow.eval(f"{MOD}.listPane:IsShown()") is False
    )
    click_crumb(wow, 3)  # the part's step: back to the list tile
    assert wow.eval(f"{MOD}.listPane:IsShown()") is True
    assert wow.eval(f"{BR}.ListEntry().part") == "people"
    assert wow.errors == []


BRANCHED = """
local quests = {
  [1] = { name = "The Brotherhood", zone = 1429, level = 10 },
  [2] = { name = "The Brotherhood", zone = 1429, level = 12, pre = { 1 } },
  [3] = { name = "The Brotherhood", zone = 1436, level = 14, pre = { 2 } },
  [4] = { name = "The Brotherhood", zone = 1436, level = 18, pre = { 3 } },
  [5] = { name = "A Letter", zone = 1429, level = 12, pre = { 2 } },
  [6] = { name = "The Reply", zone = 1429, level = 13, pre = { 5 } },
  [8] = { name = "For the Horde", zone = 1436, level = 14, pre = { 3 }, races = 2 },
  [9] = { name = "Warrior's Trial", zone = 1436, level = 20, pre = { 4 }, classes = 2 },
  [20] = { name = "A Rumour", zone = 1429, level = 9 },
}
quests[2].preAny = { 20 }
local ids = {}
for id in pairs(quests) do ids[#ids + 1] = id end
table.sort(ids)
Bastians:GetModule('Quests').Logic.SetData({
  Get = function(_, typ, id) return typ == "quest" and quests[id] or nil end,
  Index = function(_, name, key)
    if name == "quest.byZone" then
      if key == nil then return { [1] = ids } end
      return key == 1 and ids or nil
    end
    return nil
  end,
})
"""


def test_what_hangs_on_a_chains_way_stands_under_its_step(wow: WowRuntime):
    """quests.md "The chain's sheet": a side quest hangs under the main step it follows, a quest
    of another race or class too, without a face and with a dashed outline (ADR 0056); another
    way into the chain stands in a row of its own before the way. The sheet says them, so the
    page has no cards for them."""
    boot(wow)
    wow.execute(BRANCHED)
    wow.execute(f"{BR}.Open('chain:1')")
    settle(wow)
    wow.execute(f"{DS}.scroll:SetSize(900, 700); {DS}:Refresh()")  # room for four steps in a row
    wow.run_frames(3)
    canvas = f"Bastians:GetModule('Quests').Sheet.Canvas({DS}.content)"
    tiles = [t for t in wow.eval(f"{canvas}.steps").values() if t.IsShown(t)]

    def at(t):
        _, _, _, x, y = t.GetPoint(t, 1)
        return (x, y)

    by_quest = {t.qid: t for t in tiles}
    assert sorted(by_quest) == [1, 2, 3, 4, 5, 6, 8, 9, 20]
    # the main line in a row, numbered; nothing begun: the first step can be taken
    main = [by_quest[q] for q in (1, 2, 3, 4)]
    assert [t.step for t in main] == [1, 2, 3, 4]
    assert len({at(t)[1] for t in main}) == 1
    assert main[0].kind == "take"
    assert main[0].sub.GetText(main[0].sub) == "Level 10 - You can take it now"
    # the side quests of step 2 under it, one below the other
    for q in (5, 6):
        assert at(by_quest[q])[0] == at(by_quest[2])[0] and by_quest[q].step is None
    assert at(by_quest[2])[1] > at(by_quest[5])[1] > at(by_quest[6])[1]
    # what the character cannot take: under its step, dashed, with the reason
    horde, trial = by_quest[8], by_quest[9]
    assert at(horde)[0] == at(by_quest[3])[0] and at(trial)[0] == at(by_quest[4])[0]
    assert (horde.why, trial.why) == ("race", "class")
    assert horde.sub.GetText(horde.sub) == "Level 14 - for another race"
    assert horde.face.IsShown(horde.face) is False
    assert sum(1 for d in horde.dashes.values() if d.IsShown(d)) > 20
    assert by_quest[5].why is None
    assert not any(d.IsShown(d) for d in (by_quest[5].dashes or {}).values())
    # another way in: above the way
    assert at(by_quest[20])[1] > at(by_quest[1])[1]
    words = [t.GetText(t) for t in wow.eval(f"{canvas}.texts").values() if t.IsShown(t)]
    assert "Another way into the chain" in words
    cards = [c.title.GetText(c.title) for c in wow.eval(f"{DS}.cardPool").values() if c.IsShown(c)]
    assert cards == ["Where it goes"]
    # a narrow page: every main step starts a row, what hangs on it stays under it
    wow.execute(f"{DS}.scroll:SetSize(300, 700); {DS}:Refresh()")
    wow.run_frames(3)
    tiles = {t.qid: t for t in wow.eval(f"{canvas}.steps").values() if t.IsShown(t)}
    assert len({at(tiles[q])[0] for q in tiles}) == 1  # one column
    order = sorted(tiles, key=lambda q: -at(tiles[q])[1])
    assert order == [20, 1, 2, 5, 6, 3, 8, 4, 9]
    # a click on a hanging tile opens that quest, as a step does
    wow.execute(f"for _, t in ipairs({canvas}.steps) do if t.qid == 5 then t:Click() end end")
    settle(wow)
    assert wow.eval(f"{BR}.PageRef()") == "quest:5"
    assert wow.errors == []


def test_a_chain_is_stepped_into_and_its_steps_show_their_quest_sheet(wow: WowRuntime):
    """ADR 0056, P8: stepped inside, the list tile holds a chain's steps top to bottom and the
    page tile the picked step's quest sheet. The chain's own page shows the way as a card."""
    boot(wow)
    root = wow.eval("Bastians:GetModule('Quests').Logic.chainRoot(76)")
    ref = f"chain:{root}"
    assert wow.eval(f"{BR}.HasInside('{ref}')") is True
    wow.execute(f"{BR}.Open('{ref}')")
    settle(wow)
    cards = [c.title.GetText(c.title) for c in wow.eval(f"{DS}.cardPool").values() if c.IsShown(c)]
    # the chain's page is its sheet of step tiles (PA5.3); what it does not draw stays a card
    assert cards == ["Where it goes"]
    canvas = f"Bastians:GetModule('Quests').Sheet.Canvas({DS}.content)"
    steps = [t for t in wow.eval(f"{canvas}.steps").values() if t.IsShown(t)]
    assert [(t.qid, t.kind) for t in steps] == [(62, "now"), (76, "later"), (11, "later")]
    assert steps[0].name.GetText(steps[0].name) == "1. The Fargodeep Mine"
    arrows = [a for a in wow.eval(f"{canvas}.arrows").values() if a.IsShown(a)]
    assert len(arrows) == 2  # between the three steps
    # the mouse on a step: its quest's sheet over the Browser, not behind it (owner, Forever
    # 07.11.2026: "the details for each quest open behind the browser window")
    wow.execute(f"local t = {canvas}.steps[2] t:GetScript('OnEnter')(t)")
    sheet = "Bastians:GetModule('Quests').Sheet.frame"
    assert wow.eval(f"{sheet}:IsShown()") is True
    assert wow.eval(f"{sheet}:GetFrameStrata()") == wow.eval(
        "BastiansBrowserFrame:GetFrameStrata()"
    )
    wow.execute(f"local t = {canvas}.steps[2] t:GetScript('OnLeave')(t)")
    wow.execute(f"{canvas}.steps[2]:Click()")  # a click on a step opens its quest
    settle(wow)
    assert wow.eval(f"{BR}.PageRef()") == "quest:76"
    wow.execute(f"{BR}.Open('{ref}')")
    settle(wow)
    wow.execute(f"{BR}.StepInside('{ref}', 'steps')")
    settle(wow)
    rows = drawn(wow)
    assert rows[0] == (ref, "The Fargodeep Mine", True)
    assert rows[1] == (None, "-  The way  3", False)
    # the steps in order, each a quest's own tile
    assert [r for r, _, tile in rows[2:5] if tile] == ["quest:62", "quest:76", "quest:11"]
    assert crumbs(wow)[1:] == [("thing", "The Fargodeep Mine"), ("part", "The way")]
    step = next(
        f"{TREE}.flat[{i}]" for i, r in wow.eval(f"{TREE}.flat").items() if r.ref == "quest:76"
    )
    wow.execute(f"local row = {step} {TREE}.opts.onClick(row, 'LeftButton', {TREE})")
    settle(wow)
    # the page tile: that step's quest sheet (Quests' own drawing), the list keeps the chain
    assert wow.eval(f"{BR}.PageRef()") == "quest:76" and wow.eval(f"{DS}.sheet ~= nil") is True
    assert wow.eval(f"{BR}.ListEntry().ref") == ref
    assert crumbs(wow)[-1] == ("page", "The Jasperlode Mine")
    assert wow.errors == []


def test_a_search_typed_inside_a_zone_looks_everywhere(wow: WowRuntime):
    """~~ADR 0056, PA4: the chip says the zone~~ the search is always
    global, inside a zone too; the page's own filter narrows the page."""
    wow.start(CORE, DATA, QUESTS, BROWSER)
    wow.run_frames(10)
    wow.advance(0.3)
    wow.execute("Mock.playerMap = 1411")  # the player is elsewhere: the chip is the thing's zone
    wow.execute(f"{BR}.Open('zone:1429')")
    wow.run_frames(5)
    wow.execute(f"{BR}.StepInside('zone:1429')")
    wow.run_frames(5)
    wow.execute(f"{MOD}.search:SetText('hog')")
    wow.run_frames(30)
    assert wow.eval(f"{BR}.Current().kind") == "home"
    words, active = wow.eval(f"{BR}.Scope()")
    assert words == "Everywhere" and active is None


def test_a_chain_has_no_one_place_to_look_in(wow: WowRuntime):
    wow.start(CORE, DATA, QUESTS, BROWSER)
    wow.run_frames(10)
    assert wow.eval(f"{BR}.WithinOf('chain:1')") is None
    assert wow.eval(f"{BR}.WithinOf('zone:1429').name") == "Elwynn Forest"
