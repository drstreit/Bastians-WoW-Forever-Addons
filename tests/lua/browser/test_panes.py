"""List and detail (ADR 0018, ST1): the navigation, the list and the detail pane. A row click shows
the page in the detail and keeps the list; a navigation click changes the list and keeps the page;
Back walks both. A row resting under the mouse shows in the detail as a preview after the tip
delay; a narrow window keeps the navigation behind the Lists button; list rows carry a glyph by
kind; loot, sells, sources and rewards are small tables."""

import re

from harness import WowRuntime
from pages import (
    band,
    hosted_sheet,
    nav_active,
    nav_click,
    nav_rows,
    rail_click,
    rail_rows,
    tab_rows,
)

CORE, DATA, QUESTS, GOLD, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Gold",
    "Bastians_Browser",
)
MOD = "Bastians:GetModule('Browser')"
BR = f"{MOD}.Browser"
DS = f"{MOD}.dossier"
SIZE = f"{MOD}.tree.scroll:SetSize(320, 400); {MOD}.tree:Refresh()"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, QUESTS, BROWSER)))
    wow.run_frames(10)
    wow.advance(0.3)
    return wow


def strip(text: str | None) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def open_npcs(wow: WowRuntime) -> None:
    wow.execute(f"{BR}.List('npc')")
    wow.run_frames(5)
    wow.execute(SIZE)


def row_frame(wow: WowRuntime, ref: str) -> str:
    """A Lua expression for the shown list row frame of `ref`."""
    return (
        f"(function() for _, f in ipairs({MOD}.tree.pool) do "
        f"if f:IsShown() and f.row and f.row.ref == '{ref}' then return f end end end)()"
    )


def hover(wow: WowRuntime, ref: str, entering: bool = True) -> None:
    script = "OnEnter" if entering else "OnLeave"
    wow.execute(f"local f = {row_frame(wow, ref)} f:GetScript('{script}')(f)")


def test_a_row_click_keeps_the_list_and_back_walks_both(wow: WowRuntime):
    boot(wow)
    open_npcs(wow)
    assert wow.eval(f"{BR}.ListEntry().kind") == "list"
    assert band(wow, DS)["name"] == "Elwynn Forest"  # no page yet: the player's zone
    wow.execute(f"local f = {row_frame(wow, 'npc:295')} f:Click('LeftButton')")
    farley = "Innkeeper Farley"
    assert wow.eval(f"{BR}.Current().ref") == "npc:295" and band(wow, DS)["name"] == farley
    assert wow.eval(f"{BR}.ListEntry().type") == "npc"  # the list stays
    assert wow.eval(f"{MOD}.tree.selectedID") == "npc:295"  # its row carries the mark
    assert any(
        strip(r.text).startswith("Corina Steele") for r in wow.eval(f"{MOD}.tree.flat").values()
    )
    # a navigation click changes the list and keeps the page
    nav_click(wow, "nav:list:item")
    wow.run_frames(5)
    assert wow.eval(f"{BR}.ListEntry().type") == "item" and band(wow, DS)["name"] == farley
    assert nav_active(wow) == "nav:list:item"
    # Back walks both: the NPC list with the innkeeper, then the list before the page
    wow.execute(f"{BR}.Back()")
    assert wow.eval(f"{BR}.ListEntry().type") == "npc" and band(wow, DS)["name"] == farley
    wow.execute(f"{BR}.Back()")
    assert wow.eval(f"{BR}.Current().kind") == "list"
    assert band(wow, DS)["name"] == "Elwynn Forest"
    assert wow.errors == []


def test_a_resting_row_shows_as_a_preview_and_a_click_keeps_it(wow: WowRuntime):
    boot(wow)
    open_npcs(wow)
    wow.execute(f"{BR}.Open('npc:240')")
    hover(wow, "npc:295")
    wow.advance(1.2)  # without Shift nothing previews
    assert band(wow, DS)["name"] == "Marshal Dughan"
    wow.execute("Mock.shift = true")
    hover(wow, "npc:295")
    wow.advance(0.5)  # before the tip delay (one second by default): nothing changes
    assert band(wow, DS)["name"] == "Marshal Dughan"
    wow.advance(0.6)
    assert band(wow, DS)["name"] == "Innkeeper Farley"
    assert wow.eval(f"{BR}.Previewing()") == "npc:295"
    assert wow.eval(f"{DS}.band.preview:IsShown()") is True
    assert wow.eval(f"{BR}.Current().ref") == "npc:240"  # the history is untouched
    hover(wow, "npc:295", entering=False)  # leaving: the kept page comes back
    wow.advance(0.2)
    assert band(wow, DS)["name"] == "Marshal Dughan"
    assert wow.eval(f"{DS}.band.preview:IsShown()") is False
    # leaving before the delay: no preview at all
    hover(wow, "npc:295")
    wow.advance(0.3)
    hover(wow, "npc:295", entering=False)
    wow.advance(1)
    assert band(wow, DS)["name"] == "Marshal Dughan" and wow.eval(f"{BR}.Previewing()") is None
    # rest, then click: the preview is kept as the page
    hover(wow, "npc:295")
    wow.advance(1.1)
    wow.execute(f"local f = {row_frame(wow, 'npc:295')} f:Click('LeftButton')")
    assert wow.eval(f"{BR}.Current().ref") == "npc:295" and wow.eval(f"{BR}.Previewing()") is None
    assert wow.eval(f"{DS}.band.preview:IsShown()") is False
    # R25.32: a preview carried into the detail pane stays there as the page
    wow.execute(f"{BR}.Open('npc:240')")
    hover(wow, "npc:295")
    wow.advance(1.1)
    hover(wow, "npc:295", entering=False)
    wow.execute(f"Mock.mouseOverFrame = {DS}.frame")
    wow.advance(0.2)
    assert wow.eval(f"{BR}.Current().ref") == "npc:295" and wow.eval(f"{BR}.Previewing()") is None
    wow.execute("Mock.mouseOverFrame = nil")
    # rows passing under the cursor while the list scrolls start no preview
    wow.execute(f"{BR}.Open('npc:240'); {BR}.OnListWheel()")
    hover(wow, "npc:295")
    wow.advance(1.1)
    assert wow.eval(f"{BR}.Previewing()") is None
    assert wow.errors == []


def test_a_narrow_window_shows_one_tile_at_a_time(wow: WowRuntime):
    """ADR 0056: two tiles, the list and the page; under 640 units one at a time. A category or
    the breadcrumb's first step shows the list, a row's click the page."""
    boot(wow)
    wow.execute(f"{BR}.OpenWindow()")
    assert wow.eval(f"{BR}.IsNarrow()") is False
    assert wow.eval(f"{MOD}.listPane:IsShown()") is True
    assert wow.eval(f"{MOD}.detailPane:IsShown()") is True
    assert wow.eval(f"{MOD}.splitter:IsShown()") is True
    assert wow.eval(f"{MOD}.listPane:GetWidth()") == wow.eval(f"{BR}.ListWidth()")
    assert wow.eval(f"{BR}.ListWidth()") == int((1000 - 16) * 0.36)  # 36 % until it is dragged
    wow.execute(f"{MOD}.win.frame:SetWidth(430); {MOD}.win.opts.onResize({MOD}.win, false)")
    assert wow.eval(f"{BR}.IsNarrow()") is True
    # the list tile alone; the rail stays, its pictograms alone
    assert wow.eval(f"{MOD}.rail:IsShown()") is True
    assert wow.eval(f"{MOD}.rail.buttons[1].spec.only") is True
    assert wow.eval(f"{MOD}.listPane:IsShown()") is True
    assert wow.eval(f"{MOD}.detailPane:IsShown()") is False
    assert wow.eval(f"{MOD}.splitter:IsShown()") is False
    nav_click(wow, "nav:list:zone")
    wow.run_frames(5)
    assert wow.eval(f"{BR}.ListEntry().type") == "zone"
    assert wow.eval(f"{MOD}.listPane:IsShown()") is True
    # a page: the page tile takes the window
    wow.execute(f"{BR}.Open('npc:240')")
    assert wow.eval(f"{BR}.IsListOpen()") is False
    assert wow.eval(f"{MOD}.listPane:IsShown()") is False
    assert wow.eval(f"{MOD}.detailPane:IsShown()") is True
    # the breadcrumb's first step is the way back to the list
    wow.execute(f"{MOD}.crumbs.buttons[1]:Click()")
    assert wow.eval(f"{BR}.IsListOpen()") is True
    assert wow.eval(f"{MOD}.listPane:IsShown()") is True
    assert wow.eval(f"{MOD}.detailPane:IsShown()") is False
    # wide again: both
    wow.execute(f"{MOD}.win.frame:SetWidth(1000); {MOD}.win.opts.onResize({MOD}.win, false)")
    assert wow.eval(f"{BR}.IsNarrow()") is False
    assert wow.eval(f"{MOD}.listPane:IsShown()") is True
    assert wow.eval(f"{MOD}.detailPane:IsShown()") is True
    assert wow.errors == []


def test_the_rail_and_the_tabs(wow: WowRuntime):
    """ADR 0058: a rail of seven on top, always the same; the shown section's lists and views as
    a row of tabs under it, which flows; the bars under them move down with its rows. The lit
    entry is the section of the list tile, the lit tab what it shows."""
    boot(wow)
    flow = f"{BR}.Flow"
    places = wow.eval(f"({flow}({{ 100, 100, 100 }}, 250, 4, 26))")
    assert [(q.x, q.y) for q in places.values()] == [(0, 0), (104, 0), (0, 30)]
    assert wow.eval(f"select(2, {flow}({{ 100, 100, 100 }}, 250, 4, 26))") == 56
    assert wow.eval(f"select(2, {flow}({{}}, 250, 4, 26))") == 0
    assert wow.eval(f"({flow}({{ 400 }}, 250, 4, 26))[1].x") == 0  # too wide: alone in its row
    wow.execute(f"{BR}.OpenWindow()")
    assert [r[0] for r in rail_rows(wow)] == [
        "here",
        "quests",
        "world",
        "dungeons",
        "gold",
        "characters",
        "more",
    ]
    assert [(r[0], r[2]) for r in rail_rows(wow) if r[2]] == [("here", True)]
    assert wow.eval(f"{MOD}.rail.count") == 7 and wow.eval(f"{MOD}.rail.active") == "here"
    assert tab_rows(wow) == []  # Here has no tabs
    rows = nav_rows(wow)
    assert rows[0] == ("nav:here", "Here")
    quests = rows.index(("nav:list:quest", "Quests"))
    assert rows[quests + 1] == ("nav:view:quests.log", "My quests")  # pinned: after its list
    assert rows[quests + 2] == ("nav:list:chain", "Chains")
    assert nav_active(wow) == "nav:here"  # Here is its own tab, drawn as the rail entry
    nav_click(wow, "nav:list:npc")
    wow.run_frames(5)
    assert nav_active(wow) == "nav:list:npc" and wow.eval(f"{BR}.ListEntry().type") == "npc"
    assert wow.eval(f"{MOD}.rail.active") == "world"
    assert [(t[1], t[2]) for t in tab_rows(wow)] == [
        ("Zones", False),
        ("People", True),
        ("Monsters", False),
        ("Objects", False),
    ]  # the fixture has no gathering nodes: no Gathering tab
    assert wow.eval(f"{MOD}.rail.buttons[3].spec.primary") is True
    assert wow.eval(f"{MOD}.rail.buttons[1].spec.primary") is None
    assert wow.eval(f"{MOD}.rail.buttons[1].spec.only") is None  # the words show when wide
    tabs_h = wow.eval(f"{MOD}.tabs.height")
    action = wow.eval("Bastians.UI.Style.G.action")
    # the search row sits under the rail and the tabs, the breadcrumb under the search row
    assert wow.eval(f"select(5, {MOD}.toolbar:GetPoint(1))") == -(6 + action + 4 + tabs_h + 6)
    wow.execute(f"{MOD}.win.frame:SetWidth(430); {MOD}.win.opts.onResize({MOD}.win, false)")
    assert wow.eval(f"{MOD}.rail.buttons[1].spec.only") is True  # pictograms alone when narrow
    assert wow.eval(f"{MOD}.rail.count") == 7  # the rail does not change shape
    more = wow.eval(f"{MOD}.tabs.height")
    assert more >= tabs_h
    bar = 6 + action + 4 + more + 6
    assert wow.eval(f"select(5, {MOD}.toolbar:GetPoint(1))") == -bar
    # (a narrow window: the filter chips flow into more lines right of the arrows, PH2)
    row = wow.eval(f"-select(5, {MOD}.crumbs:GetPoint(1))")
    chips_h = wow.eval(f"{MOD}.filterHost:IsShown() and {MOD}.filterHost:GetHeight() or 0")
    assert chips_h > 0
    assert row == bar + max(26, chips_h - 4) + 4
    # the breadcrumb: what the list tile shows, then the page
    crumbs = wow.eval(f"{BR}.Crumbs()")
    assert [(c.kind, c.text) for c in crumbs.values()] == [
        ("list", "People"),
        ("page", "Elwynn Forest"),
    ]
    wow.execute(f"{BR}.Open('npc:240')")
    crumbs = wow.eval(f"{BR}.Crumbs()")
    assert [(c.kind, c.text) for c in crumbs.values()] == [
        ("list", "People"),
        ("page", "Marshal Dughan"),
    ]
    assert wow.eval(f"{MOD}.crumbs.count") == 2
    assert "Marshal Dughan" in wow.eval(f"{MOD}.crumbs.buttons[2].text:GetText()")
    # a bookmark brings its tab under More
    assert not any(r[0] == "nav:bookmarks" for r in nav_rows(wow))
    wow.execute(f"{BR}.ToggleBookmark('npc:240'); {BR}.Render()")
    assert ("nav:bookmarks", "Bookmarks") in nav_rows(wow)
    nav_click(wow, "nav:bookmarks")
    assert wow.eval(f"{BR}.Current().kind") == "bookmarks" and nav_active(wow) == "nav:bookmarks"
    assert wow.eval(f"{MOD}.rail.active") == "more"
    # a rail entry opens its section's first tab; a section with one list draws no tab row
    rail_click(wow, "dungeons")
    wow.run_frames(5)
    assert wow.eval(f"{BR}.ListEntry().type") == "dungeon" and tab_rows(wow) == []
    assert wow.eval(f"{MOD}.tabs:IsShown()") is False
    assert wow.eval(f"select(5, {MOD}.toolbar:GetPoint(1))") == -(6 + action + 6)
    rail_click(wow, "quests")
    wow.run_frames(5)
    assert wow.eval(f"{BR}.ListEntry().type") == "quest" and tab_rows(wow)[0][2] is True
    assert wow.errors == []


def test_more_holds_what_names_no_rail_entry(wow: WowRuntime):
    """ADR 0058: More is a list of tiles with one line each: the other apps' views, the
    bookmarks, then the suite's own pages. A missing app dims its entry and says so."""
    boot(wow, CORE, DATA, QUESTS, "Bastians_Route", BROWSER)
    wow.execute(f"{BR}.OpenWindow()")
    rows = rail_rows(wow)
    chars = next(r for r in rows if r[0] == "characters")
    assert chars[3] == "Characters needs Bastian's Alts"  # not installed here
    assert wow.eval(f"{MOD}.rail.buttons[6].enabledFlat") is False
    gold = next(r for r in rows if r[0] == "gold")
    assert gold[1] == "Items" and gold[3] is None  # without Bastian's Gold the entry reads Items
    rail_click(wow, "characters")  # a dim entry does nothing
    assert wow.eval(f"{BR}.Current().kind") == "here"
    rail_click(wow, "more")
    wow.run_frames(5)
    assert wow.eval(f"{BR}.Current().kind") == "more" and wow.eval(f"{MOD}.rail.active") == "more"
    assert wow.eval(f"{MOD}.win.title:GetText()") == "More"
    texts = [strip(r.text) for r in wow.eval(f"{MOD}.tree.flat").values()]
    assert texts[0] == "Explore" and texts[-4:] == ["Settings", "Help", "What's new", "About"]
    more = wow.eval(f"{BR}.MoreRows()")
    assert [r.id for r in more.values()][:1] == ["more:nav:view:route.explore"]
    # a tile opens its view
    wow.execute(f"{BR}.MoreRows()[1].onClick()")
    wow.run_frames(5)
    assert (
        wow.eval(f"{BR}.Current().kind") == "view"
        and wow.eval(f"{BR}.Current().id") == "route.explore"
    )
    assert wow.eval(f"{MOD}.rail.active") == "more"  # a view without a rail entry lights More
    # the suite's pages open the hub
    wow.execute(f"{BR}.ShowMore()")
    wow.execute(f"local rows = {BR}.MoreRows() rows[#rows - 3].onClick()")
    assert wow.eval("Bastians.UI.Hub.current.suite") is True
    assert wow.errors == []


def test_a_list_row_is_a_tile(wow: WowRuntime):
    """ADR 0056: a row that stands for one thing is a tile: a plate of its own, a large picture,
    the name, a line under it; the chosen tile is its plate in the accent. A heading is no tile."""
    boot(wow)
    util = "Bastians.UI.TreeUtil"
    assert wow.eval(f"{util}.isTile({{ ref = 'npc:240', text = 'x' }})") is True
    assert wow.eval(f"{util}.isTile({{ text = 'x' }})") is False
    assert wow.eval(f"{util}.isTile({{ ref = 'npc:240', kind = 'section' }})") is False
    assert wow.eval(f"{util}.isTile({{ ref = 'npc:240', children = {{}} }})") is False
    assert wow.eval(f"{util}.isTile({{ ref = 'npc:240', tile = false }})") is False
    row = "{ ref = 'npc:240', text = 'x' }"
    assert wow.eval(f"{util}.rowHeight({row}, 300, true, false, true)") == 56
    assert wow.eval(f"{util}.rowHeight({row}, 300, true, false)") < 30  # a plain row elsewhere
    open_npcs(wow)
    wow.execute(f"{BR}.Open('npc:240')")
    wow.execute(SIZE)
    tile = row_frame(wow, "npc:240")
    assert wow.eval(f"{tile}.tile") is True
    assert wow.eval(f"{tile}:GetHeight()") == 52  # 56 with the gap under it
    assert wow.eval(f"{tile}.plate:IsShown()") is True
    assert strip(wow.eval(f"{tile}.text:GetText()")).startswith("Marshal Dughan")
    # the line under the name: the tile's own (what the person is and where), asked for the rows
    # in view; a person's level is no badge
    assert strip(wow.eval(f"{tile}.meta:GetText()")) == "Marshal, Elwynn Forest"
    assert wow.eval(f"{tile}.badge ~= nil and {tile}.badge:IsShown()") is False
    assert wow.eval(f"{tile}.div:IsShown()") is False  # a tile's edge is its plate
    # chosen: the plate's edge in the accent, no bar and no flat fill
    assert wow.eval(f"{tile}.plateEdge:IsShown()") is True
    assert wow.eval(f"{tile}.sel:IsShown()") is False
    other = (
        f"(function() for _, f in ipairs({MOD}.tree.pool) do "
        "if f:IsShown() and f.row and f.row.ref ~= 'npc:240' then return f end end end)()"
    )
    assert wow.eval(f"{other}.tile") is True and wow.eval(f"{other}.plateEdge:IsShown()") is False
    # rows of 56: the second tile starts 56 under the first
    first, second = f"{MOD}.tree.pool[1]", f"{MOD}.tree.pool[2]"
    assert wow.eval(f"select(5, {first}:GetPoint(1)) - select(5, {second}:GetPoint(1))") == 56
    assert wow.errors == []


def test_list_rows_carry_a_glyph_by_kind(wow: WowRuntime):
    boot(wow)
    open_npcs(wow)
    glyphs = "Interface\\AddOns\\Bastians_Core\\Media\\Tiles\\"  # the tiles since R25.38
    icons = {strip(r.text).split("  ")[0]: r.icon for r in wow.eval(f"{MOD}.tree.flat").values()}
    assert icons["Innkeeper Farley"] == glyphs + "innkeeper"
    assert icons["Marshal Dughan"] == glyphs + "quest"  # a quest giver
    wow.execute(f"{BR}.List('mob')")  # no service: a monster, in the Mobs list
    wow.run_frames(5)
    wow.execute(SIZE)
    icons = {strip(r.text).split("  ")[0]: r.icon for r in wow.eval(f"{MOD}.tree.flat").values()}
    assert icons["Hogger"] == wow.eval("Bastians.UI.IconTexture('mob')")
    assert wow.eval(f"{BR}.RowGlyph({{ type = 'zone', dims = {{}}, values = {{}} }}, 1)") == "zone"
    assert wow.errors == []


def test_loot_sells_and_rewards_are_small_tables(wow: WowRuntime):
    boot(wow, CORE, DATA, QUESTS, GOLD, BROWSER)
    wow.execute(f"{BR}.Open('npc:448')")
    wow.execute(f"{DS}.scroll:SetSize(420, 600); {DS}:Refresh()")

    def drops_block():
        for bf in wow.eval(f"{DS}.blockPool").values():
            if bf.IsShown(bf) and strip(bf.title.GetText(bf.title)).startswith("DROPS"):
                return bf
        return None

    # rows with the item's picture and name
    drops = drops_block()
    assert drops is not None and drops.mode is None and drops.tree.opts.table is True
    rows = [f for f in drops.tree.pool.values() if f.IsShown(f)]
    linen = next(f for f in rows if f.row.ref == "item:2589")
    assert strip(linen.note.GetText(linen.note)) == "46 %"  # the chance, a column
    assert linen.iconCount == 0  # no action icons in a table row
    # the money formats a chance that small as a decimal, never as zero (golden rule 2)
    fmt = "Bastians.UI.FormatValue"
    assert wow.eval(f"{fmt}(0.4, 'percent')") == "0.4 %"
    assert wow.eval(f"{fmt}(0.01, 'percent')") == "<0.1 %"
    assert wow.eval(f"{fmt}(45.5, 'percent')") == "46 %"
    assert wow.errors == []


def test_the_list_tile_stands_beside_the_page(wow: WowRuntime):
    """ADR 0056: "we only have two tiles - list and larger detail". The list no longer slides
    (R25.36 until then): a wide window shows it beside every page, opened from the map too."""
    boot(wow)
    wow.execute(f"{BR}.Open('npc:240')")
    assert wow.eval(f"{BR}.IsListOpen()") is True
    assert wow.eval(f"{MOD}.listPane:IsShown()") is True
    assert wow.eval(f"select(2, {MOD}.detailPane:GetPoint(1)) == {MOD}.splitter") is True
    assert wow.eval(f"{MOD}.listTab") is None  # no tab, nothing slides
    # the wish is remembered, and changes nothing while both fit
    wow.execute(f"{BR}.SetListOpen(false)")
    assert wow.eval(f"{BR}.IsListOpen()") is True and wow.eval(f"{MOD}.listPane:IsShown()") is True
    wow.execute(f"{MOD}.search:SetText('hog')")
    wow.run_frames(20)
    assert wow.eval(f"{BR}.IsListOpen()") is True
    assert wow.errors == []


STAGE = f"{MOD}.dossier.band.stage"


def test_the_page_shows_a_creature_or_the_item_itself(wow: WowRuntime):
    """3D art on the page; items as items, not on the character (it
    showed half naked or in the old outfit): an item with a model of its own (weapons, shields,
    helms, ...) as itself, any other item its icon large; a creature as itself."""
    boot(wow)
    wow.execute(f"{BR}.Open('npc:448')")
    wow.run_frames(2)
    assert wow.eval(f"{STAGE}.frame:IsShown()") is True
    assert wow.eval(f"{STAGE}.model.creature") == 448
    assert wow.eval(f"{MOD}.dossier.band.icon:IsShown()") is False
    # a weapon: its own model, nobody wearing it
    wow.execute("Mock.items[2589].equipLoc = 'INVTYPE_WEAPON'")
    wow.execute(f"{BR}.Open('item:2589')")
    wow.run_frames(2)
    assert wow.eval(f"{STAGE}.model.item") == 2589
    assert wow.eval(f"{STAGE}.model.unit") is None
    assert wow.eval(f"{STAGE}.model:IsShown()") is True
    # cloth: no model of its own, its icon large on the plate
    wow.execute("Mock.items[2589].equipLoc = nil")
    wow.execute(f"{BR}.Open('item:2589')")
    wow.run_frames(2)
    assert wow.eval(f"{STAGE}.frame:IsShown()") is True
    assert wow.eval(f"{STAGE}.model:IsShown()") is False
    assert wow.eval(f"{STAGE}.icon:IsShown()") is True
    assert wow.eval(f"{STAGE}.icon:GetWidth()") > 60
    assert wow.errors == []


def test_the_model_loads_with_dots_on_a_plate_sized_first(wow: WowRuntime):
    """a short loading animation; the showcase showed no model and the
    small plate sometimes none: a model set on a frame of no size stays empty, so the plate gets
    its size first."""
    boot(wow)
    wow.execute(f"{BR}.Open('npc:448')")
    wow.run_frames(2)
    assert wow.eval(f"{STAGE}.model.plateWidthAtSet") == 132
    assert all(d.IsShown(d) for d in wow.eval(f"{STAGE}.dots").values())
    wow.execute(f"{STAGE}.model:GetScript('OnModelLoaded')({STAGE}.model)")
    assert not any(d.IsShown(d) for d in wow.eval(f"{STAGE}.dots").values())
    assert wow.eval(f"{STAGE}.model.creature") == 448
    # a model that never reports: the dots stop after the timeout
    wow.execute(f"{BR}.Open('npc:240')")
    wow.run_frames(200, 1 / 60)
    assert not any(d.IsShown(d) for d in wow.eval(f"{STAGE}.dots").values())
    assert wow.eval(f"{STAGE}.model.creature") == 240
    assert wow.errors == []


def test_a_click_on_the_portrait_opens_the_showcase(wow: WowRuntime):
    """ "a click on the 3D model should open a larger window"; a drag
    turns the model and opens nothing; the wheel zooms the showcase's model."""
    boot(wow)
    wow.execute(f"{BR}.Open('npc:448')")
    wow.run_frames(2)
    model = f"{STAGE}.model"
    wow.execute("Mock.cursorX = 400")
    wow.execute(f"{model}:GetScript('OnMouseDown')({model}); Mock.cursorX = 460")
    wow.run_frames(1)
    wow.execute(f"{model}:GetScript('OnMouseUp')({model})")
    assert wow.eval("BastiansShowcase == nil or not BastiansShowcase:IsShown()") is True
    assert wow.eval(f"{model}.facing") != -0.3  # turned
    wow.execute(
        f"{model}:GetScript('OnMouseDown')({model}); {model}:GetScript('OnMouseUp')({model})"
    )
    assert wow.eval("BastiansShowcase:IsShown()") is True
    win = "Bastians.UI.ShowcaseWindow()"
    assert wow.eval(f"{win}.stage.model.creature") == 448
    assert wow.eval(f"{win}.title:GetText()") == wow.eval("Bastians:Entity('npc:448'):Name()")
    assert wow.eval(f"{win}.stage.frame:GetHeight()") > 300
    wow.execute(f"{win}.content:GetScript('OnMouseWheel')({win}.content, 1)")
    assert wow.eval(f"{win}.stage.model.camDistance") == 0.9
    # a zone's painting opens it too
    wow.execute(f"{BR}.Open('zone:1429')")
    wow.run_frames(2)
    wow.execute(f"{STAGE}.frame:GetScript('OnMouseUp')({STAGE}.frame)")
    assert wow.eval(f"{win}.ref") == "zone:1429"
    assert wow.errors == []


def test_a_quest_shows_its_giver_and_a_zone_its_painting(wow: WowRuntime):
    """("yes, do the less Excel things"): a quest's page shows its giver's
    model; a zone's page shows the zone's Blizzard painting with the areas the character explored,
    as wide as the painting's aspect."""
    boot(wow)
    wow.execute(f"{BR}.Open('quest:62')")
    wow.run_frames(2)
    # the quest's page is the quest sheet (ADR 0056): its giver stands on it as a figure
    assert hosted_sheet(wow, DS)["figures"] == [240]  # Marshal Dughan gives it
    wow.execute(
        """Mock.explored[1429] = { { textureWidth = 300, textureHeight = 200, offsetX = 10,
             offsetY = 20, fileDataIDs = { 501, 502 } } }"""
    )
    wow.execute(f"{BR}.Open('zone:1429')")
    wow.run_frames(2)
    assert wow.eval(f"{STAGE}.frame:IsShown()") is True
    assert wow.eval(f"{STAGE}.model:IsShown()") is False
    assert wow.eval(f"{STAGE}.frame:GetWidth()") == round(132 * 1002 / 668)
    art = [t for t in wow.eval(f"{STAGE}.art").values() if t.IsShown(t)]
    assert sorted(t.GetTexture(t) for t in art) == [501, 502, 1001, 1002, 1003]
    # back to an NPC: the painting goes, the model comes
    wow.execute(f"{BR}.Open('npc:448')")
    wow.run_frames(2)
    assert not [t for t in wow.eval(f"{STAGE}.art").values() if t.IsShown(t)]
    assert (
        wow.eval(f"{STAGE}.model:IsShown()") is True
        and wow.eval(f"{STAGE}.frame:GetWidth()") == 132
    )
    assert wow.errors == []


def test_dock_sits_left_of_the_options_button(wow: WowRuntime):
    """a title bar button lay on the window's options button (R27.1).
    Since Slim went (ADR 0056, PA1.3) Dock is the one beside it."""
    boot(wow)
    wow.execute(f"{BR}.Open('npc:448')")
    win = "Bastians.UI.Windows.BastiansBrowserFrame"
    assert wow.eval(f"select(2, {MOD}.toolbar.dock:GetPoint(1)) == {win}.options") is True
    assert wow.eval(f"{MOD}.toolbar.slim") is None
    assert wow.errors == []


def test_the_divider_is_dragged_and_the_width_kept(wow: WowRuntime):
    """The list tile's width is the player's once dragged (the navigation's grip of 28.10.2026
    went with the navigation pane, ADR 0056)."""
    boot(wow)
    wow.execute(f"{BR}.Open('npc:448')")
    wow.execute(f"{BR}.SetListWidth(420)")
    assert wow.eval(f"{MOD}.listPane:GetWidth()") == 420
    assert wow.eval(f"{MOD}.db.profile.listWidth") == 420
    wow.execute(f"{BR}.SetListWidth(5000)")  # the page keeps its least width
    assert wow.eval(f"{BR}.ListWidth()") == 1000 - 16 - 300
    assert wow.eval(f"{BR}.navGrip") is None and wow.eval(f"{MOD}.nav") is None
    assert wow.errors == []


def test_a_click_on_a_zone_painting_opens_the_zone_on_the_map(wow: WowRuntime):
    """in Zones, a click on the painting opens the zone in Bastian's
    Map (its style switch is there and remembered); without the Map the showcase."""
    boot(wow, CORE, DATA, QUESTS, BROWSER, "Bastians_Map")
    wow.execute(f"{BR}.Open('zone:1429')")
    wow.run_frames(2)
    wow.execute(f"{STAGE}.frame:GetScript('OnMouseUp')({STAGE}.frame)")
    assert wow.eval("BastiansMapFrame ~= nil and BastiansMapFrame:IsShown()") is True
    assert wow.eval("BastiansShowcase == nil or not BastiansShowcase:IsShown()") is True
    assert wow.errors == []


def test_the_newest_showcase_follows_the_page_ctrl_click_opens_another(wow: WowRuntime):
    """the large window follows a new row in the list; Ctrl+click opens
    another window, the old one stays as it is; only the newest follows."""
    boot(wow)
    wow.execute(f"{BR}.Open('npc:448')")
    wow.run_frames(2)
    frame = f"{STAGE}.frame"
    wow.execute(f"{frame}:GetScript('OnMouseUp')({frame})")
    first = "Bastians.UI.Showcases()[1]"
    assert wow.eval(f"{first}.ref") == "npc:448"
    assert wow.eval(f"{first}.stage.model.plateWidthAtSet") > 200  # sized before the model
    # a new page: the showcase follows
    wow.execute(f"{BR}.Open('npc:240')")
    wow.run_frames(2)
    assert wow.eval(f"{first}.ref") == "npc:240"
    assert wow.eval(f"{first}.stage.model.creature") == 240
    # Ctrl+click: another window, the first stays
    wow.execute(f"Mock.ctrl = true; {frame}:GetScript('OnMouseUp')({frame}); Mock.ctrl = false")
    assert wow.eval("#Bastians.UI.Showcases()") == 2
    second = "Bastians.UI.Showcases()[2]"
    assert wow.eval(f"{second}.frame:IsShown()") is True
    wow.execute(f"{BR}.Open('npc:448')")
    wow.run_frames(2)
    assert wow.eval(f"{second}.ref") == "npc:448"  # the newest follows
    assert wow.eval(f"{first}.ref") == "npc:240"  # the older one stays
    assert wow.errors == []


def test_the_preview_is_a_setting_shift_hover_or_never(wow: WowRuntime):
    """the Shift preview: a setting now. `shift` (default) as before,
    `hover` previews every resting row, `off` never."""
    boot(wow)
    open_npcs(wow)
    wow.execute(f"{BR}.Open('npc:240')")
    wow.execute(f"{MOD}.db.profile.preview = 'hover'")
    hover(wow, "npc:295")
    wow.advance(1.2)
    assert (
        band(wow, DS)["name"] == "Innkeeper Farley" and wow.eval(f"{BR}.Previewing()") == "npc:295"
    )
    hover(wow, "npc:295", entering=False)
    wow.advance(0.3)
    assert wow.eval(f"{BR}.Previewing()") is None
    wow.execute(f"{MOD}.db.profile.preview = 'off'; Mock.shift = true")
    hover(wow, "npc:295")
    wow.advance(1.2)
    assert band(wow, DS)["name"] == "Marshal Dughan" and wow.eval(f"{BR}.Previewing()") is None
    wow.execute(f"{MOD}.db.profile.preview = nil")  # the default: Shift
    hover(wow, "npc:295")
    wow.advance(1.2)
    assert wow.eval(f"{BR}.Previewing()") == "npc:295"
    wow.execute("Mock.shift = nil")
    labels = [o.key for o in wow.eval(f"{MOD}.def.options").values()]
    assert "preview" in labels
    assert wow.errors == []


def shown_tile(wow: WowRuntime, ref: str) -> dict:
    """What the list's tile of `ref` shows: its two lines, badge, mark, picture and value."""
    f = row_frame(wow, ref)

    def pill(key: str):
        if not wow.eval(f"{f}.{key} ~= nil and {f}.{key}:IsShown()"):
            return None
        return (wow.eval(f"{f}.{key}.label:GetText()"), wow.eval(f"{f}.{key}.token"))

    return {
        "name": strip(wow.eval(f"{f}.text:GetText()")),
        "line": strip(wow.eval(f"{f}.meta:GetText()")),
        "badge": pill("badge"),
        "mark": pill("mark"),
        "icon": wow.eval(f"{f}.icon:IsShown() and {f}.icon:GetTexture()"),
        "value": wow.eval(f"{f}.value:IsShown() and {f}.value:GetText()") or None,
    }


def open_list(wow: WowRuntime, typ: str) -> None:
    wow.execute(f"{BR}.List('{typ}')")
    wow.run_frames(8)
    wow.execute(SIZE)


def test_a_tile_says_what_its_type_is_about(wow: WowRuntime):
    """ADR 0056, PA2.2: one tile per type, its facts from the facet "tile". A quest: its state as
    the picture, the giver under the name, the level as a badge in the difficulty colour (never
    the colour of the name), its place in its chain as a mark. A monster: where, its level, its
    rank. A zone: its level band as the badge. The character is level 12."""
    boot(wow)
    glyphs = "Interface\\AddOns\\Bastians_Core\\Media\\Tiles\\"
    open_list(wow, "quest")
    mine = shown_tile(wow, "quest:62")  # in the log, ready to hand in, first of three
    assert (mine["name"], mine["line"]) == ("The Fargodeep Mine", "Marshal Dughan")
    assert mine["badge"] == ("7", "diffGreen") and mine["mark"] == ("1/3", None)
    assert mine["icon"] == glyphs + "done"
    hogger = shown_tile(wow, "quest:176")  # in the log, no chain
    assert hogger["line"] == "Wanted Poster, Group" and hogger["mark"] is None
    assert hogger["badge"] == ("11", "diffYellow") and hogger["icon"] == glyphs + "questActive"
    later = shown_tile(wow, "quest:76")
    assert later["mark"] == ("2/3", None) and later["icon"] == glyphs + "waiting"
    # the badge's words are inked against its ground, the name stays in the text colour
    f = row_frame(wow, "quest:176")
    ink = [round(v, 2) for v in wow.eval(f"{{ {f}.badge.label:GetTextColor() }}").values()][:3]
    assert ink == [round(v, 2) for v in wow.eval("Bastians.UI.Style.C.badgeInk").values()][:3]
    name = [round(v, 2) for v in wow.eval(f"{{ {f}.text:GetTextColor() }}").values()][:3]
    assert name == [round(v, 2) for v in wow.eval("Bastians.UI.Style.C.text").values()][:3]
    assert "|c" not in wow.eval(f"{f}.text:GetText()")
    # the quest abandoned: the tile follows without a new list
    wow.execute("table.remove(Mock.questLog, 3)")
    wow.fire("QUEST_LOG_UPDATE")
    wow.advance(0.6)
    wow.run_frames(8)
    wow.execute(SIZE)
    assert shown_tile(wow, "quest:62")["icon"] == glyphs + "quest"
    assert shown_tile(wow, "quest:176")["icon"] == glyphs + "questActive"

    open_list(wow, "mob")
    boss = shown_tile(wow, "npc:448")
    assert (boss["name"], boss["line"]) == ("Hogger", "Elwynn Forest")
    assert boss["badge"] == ("11", "diffYellow") and boss["mark"] == ("Elite", "rare")
    assert shown_tile(wow, "npc:327")["badge"] == ("8", "diffGreen")

    open_list(wow, "zone")
    elwynn = shown_tile(wow, "zone:1429")
    assert (elwynn["name"], elwynn["line"]) == ("Elwynn Forest", "Eastern Kingdoms")
    assert elwynn["badge"] == ("7-11", "diffYellow")  # the level in the band nearest the character
    assert shown_tile(wow, "zone:1415")["badge"] is None  # a continent has no levels

    open_list(wow, "dungeon")
    mines = shown_tile(wow, "dungeon:36")
    assert mines["line"] == "Westfall, 2 bosses" and mines["badge"] == ("15-25", "diffOrange")
    # a dungeon's tile says how far its band is (catalog review A2.2, 07.11.2026); a zone's does not
    level = wow.eval("UnitLevel('player')")
    assert mines["value"] == f"in {15 - level} levels"
    assert elwynn["value"] is None
    # one level away: "in 1 level" (Ragefire Chasm read "in 1 levels" on Forever, 07.11.2026)
    wow.execute("Mock.level = 14")
    open_list(wow, "zone")
    open_list(wow, "dungeon")
    assert shown_tile(wow, "dungeon:36")["value"] == "in 1 level"
    assert wow.errors == []


def test_a_badge_token_follows_the_level(wow: WowRuntime):
    boot(wow, CORE)
    token = "Bastians.UI.TreeUtil.badgeToken"
    assert wow.eval(f"{token}({{ token = 'rare', level = 3 }}, 12)") == "rare"
    assert wow.eval(f"{token}({{ level = 17 }}, 12)") == "diffRed"
    assert wow.eval(f"{token}({{ level = 12 }}, 12)") == "diffYellow"
    assert wow.eval(f"{token}({{ level = 1 }}, 30)") == "diffGrey"
    assert wow.eval(f"{token}({{ level = 10, levelHi = 20 }}, 12)") == "diffYellow"  # inside
    assert wow.eval(f"{token}({{ level = 10, levelHi = 20 }}, 60)") == "diffGrey"  # outgrown
    assert wow.eval(f"{token}({{ level = 30, levelHi = 40 }}, 12)") == "diffRed"  # ahead
    assert wow.eval(f"{token}({{ text = '3 floors' }}, 12)") is None  # a quiet badge
    assert wow.eval(f"{token}({{ level = 10 }}, nil)") is None  # unknown is not a colour
    assert wow.errors == []


def test_the_icons_under_the_mouse_take_the_place_of_a_tiles_value(wow: WowRuntime):
    """The first line belongs to the name and the badges: the action icons stand on the second
    line while the mouse is on the tile, where its value was, and give the place back."""
    boot(wow)
    open_list(wow, "mob")
    f = row_frame(wow, "npc:448")
    assert strip(wow.eval(f"{f}.value:GetText()")) == "2 places"  # the tile's note
    assert wow.eval(f"{f}.value:IsShown()") is True
    hover(wow, "npc:448")
    assert wow.eval(f"{f}.iconCount") > 0
    assert wow.eval(f"{f}.value:IsShown()") is False
    assert wow.eval(f"select(5, {f}.icons[1]:GetPoint(1))") < 0  # under the middle: line two
    hover(wow, "npc:448", entering=False)
    assert wow.eval(f"{f}.iconCount") == 0 and wow.eval(f"{f}.value:IsShown()") is True
    assert wow.errors == []


def test_a_page_is_cards_with_tiles(wow: WowRuntime):
    """ADR 0056, PA3.1: the page's parts are cards. A quest on a zone's or a person's card is the
    same tile as in the Quests list: its own name in the page's ink, its state as the picture,
    the level as a badge; nothing folds and no chapter heading of the reading column is left."""
    boot(wow)
    wow.execute(f"{BR}.Open('zone:1429')")
    wow.execute(f"{DS}.scroll:SetSize(760, 600); {DS}:Refresh()")
    wow.run_frames(3)
    assert wow.eval(f"{DS}.opts.cards") is True
    titles = [c.title.GetText(c.title) for c in wow.eval(f"{DS}.cardPool").values() if c.IsShown(c)]
    assert titles[0] == "Your quests here" and "People" in titles and "Monsters" in titles
    assert not any(h.IsShown(h) for h in wow.eval(f"{DS}.chapterPool").values())
    wow.execute(
        f"for _, bf in ipairs({DS}.blockPool) do if bf:IsShown() and bf.mode == 'tiles' then "
        "bf.tree:Refresh() end end"
    )
    quests = [
        f
        for bf in wow.eval(f"{DS}.blockPool").values()
        if bf.IsShown(bf) and bf.mode == "tiles"
        for f in bf.tree.pool.values()
        if f.IsShown(f) and f.tile and str(f.row.ref).startswith("quest:")
    ]
    assert quests
    for f in quests:
        name = f.text.GetText(f.text)
        assert "|c" not in name and "[" not in name  # the name alone, in the page's ink
        assert f.badge is not None and f.badge.IsShown(f.badge)  # the level is the badge
        assert f.icon.IsShown(f.icon)  # the state is the picture
    assert {f.text.GetText(f.text) for f in quests} >= {"The Fargodeep Mine", 'Wanted: "Hogger"'}
    assert wow.errors == []


def test_a_rows_own_click_that_opens_a_page_shows_the_page_tile_when_narrow(wow: WowRuntime):
    """ "when I scale it narrow, a click on the left pane simply does
    nothing as the right pane is not visible anymore". A row's own click (a view's row) that puts
    another page in the page tile shows that tile; one that leaves the page as it was does not."""
    boot(wow)
    wow.execute(f"{BR}.OpenWindow()")
    wow.execute(f"{MOD}.win.frame:SetWidth(430); {MOD}.win.opts.onResize({MOD}.win, false)")
    open_npcs(wow)
    assert wow.eval(f"{MOD}.listPane:IsShown()") is True
    # a view's row: it opens the page, then puts its own list back (as a view keeps its rows)
    wow.execute(
        f"local row = {{ onClick = function() {BR}.Open('npc:240'); {BR}.List('npc') end }} "
        f"{MOD}.tree.opts.onClick(row, 'LeftButton', {MOD}.tree)"
    )
    assert wow.eval(f"{BR}.PageRef()") == "npc:240"
    assert wow.eval(f"{MOD}.detailPane:IsShown()") is True
    assert wow.eval(f"{MOD}.listPane:IsShown()") is False
    # back to the list; a row whose click changes no page keeps the list tile
    wow.execute(f"{MOD}.crumbs.buttons[1]:Click()")
    assert wow.eval(f"{MOD}.listPane:IsShown()") is True
    wow.execute(
        f"local row = {{ onClick = function() end }} "
        f"{MOD}.tree.opts.onClick(row, 'LeftButton', {MOD}.tree)"
    )
    assert wow.eval(f"{MOD}.listPane:IsShown()") is True
    assert wow.errors == []


def test_the_rail_and_the_tabs_are_coloured_symbols_with_text(wow: WowRuntime):
    """(R4): "the top row buttons need colours, this is not well to read
    with green in green" - "remove them all with coloured symbols with text". Every rail entry and
    tab: its pictogram on a square of its section's colour and its word, no plate and no edge; the
    lit entry is underlined in its colour."""
    boot(wow)
    wow.execute(f"{BR}.OpenWindow()")
    rail = [b for b in wow.eval(f"{MOD}.rail.buttons").values() if b.IsShown(b)]
    assert len(rail) == 7
    style = "Bastians.UI.Style.C"
    for b in rail:
        assert b.spec.hue and b.spec.boxed is None
        assert b.hueSquare.IsShown(b.hueSquare) is True
        square = list(b.hueSquare.GetVertexColor(b.hueSquare))[:3]
        assert square == list(wow.eval(f"{style}.{b.spec.hue}").values())[:3]
        assert all(list(x.GetVertexColor(x))[3] == 0 for x in b.face.pieces.values())  # no plate
        assert b.hueLine.IsShown(b.hueLine) is (b.spec.primary is True)
    hues = {b.spec.hue for b in rail}
    assert len(hues) == 7  # one colour per section
    nav_click(wow, "nav:list:zone")
    wow.run_frames(5)
    tabs = [b for b in wow.eval(f"{MOD}.tabs.buttons").values() if b.IsShown(b)]
    assert tabs and all(t.spec.hue == "tileGreen" for t in tabs)  # World's colour
    assert sum(1 for t in tabs if t.hueLine.IsShown(t.hueLine)) == 1  # the lit tab
    assert wow.errors == []
