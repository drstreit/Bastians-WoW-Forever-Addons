"""List and detail (ADR 0018, ST1): the navigation, the list and the detail pane. A row click shows
the page in the detail and keeps the list; a navigation click changes the list and keeps the page;
Back walks both. A row resting under the mouse shows in the detail as a preview after the tip
delay; a narrow window keeps the navigation behind the Lists button; list rows carry a glyph by
kind; loot, sells, sources and rewards are small tables."""

import re

from harness import WowRuntime
from pages import band, nav_active, nav_click

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


def test_a_narrow_window_keeps_the_navigation_behind_lists(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{BR}.OpenWindow()")
    assert wow.eval(f"{MOD}.nav:IsShown()") is True
    assert wow.eval(f"{MOD}.toolbar.lists:IsShown()") is False
    wow.execute(f"{MOD}.win.frame:SetWidth(800); {MOD}.win.opts.onResize({MOD}.win, false)")
    assert wow.eval(f"{BR}.IsNarrow()") is True
    assert wow.eval(f"{MOD}.nav:IsShown()") is False
    assert wow.eval(f"{MOD}.toolbar.lists:IsShown()") is True
    assert wow.eval(f"{MOD}.detailPane:IsShown()") is True  # two panes: list and detail
    wow.execute(f"{MOD}.toolbar.lists:Click()")  # the navigation over the list
    assert wow.eval(f"{MOD}.nav:IsShown()") is True
    nav_click(wow, "nav:list:zone")  # a choice closes it again
    wow.run_frames(5)
    assert wow.eval(f"{MOD}.nav:IsShown()") is False
    assert wow.eval(f"{BR}.ListEntry().type") == "zone"
    wow.execute(f"{MOD}.win.frame:SetWidth(1000); {MOD}.win.opts.onResize({MOD}.win, false)")
    assert wow.eval(f"{MOD}.nav:IsShown()") is True and wow.eval(f"{BR}.IsNarrow()") is False
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


def test_the_list_slides_out_for_a_category_and_shuts_with_its_tab(wow: WowRuntime):
    """(R25.36): the middle list stayed as last used and drew the eye
    away from what was clicked. Shut by default (opened from the map too); a category in the
    navigation slides it out; its tab slides it in again."""
    boot(wow)
    wow.execute(f"{BR}.Open('npc:240')")
    assert wow.eval(f"{BR}.IsListOpen()") is False
    assert wow.eval(f"{MOD}.listPane:IsShown()") is False
    assert wow.eval(f"select(2, {MOD}.detailPane:GetPoint(1)) == {MOD}.splitter") is False
    # a category in the navigation: the list slides out
    wow.execute(
        f"""{MOD}.navTree.opts.onClick({{ nav = {{ kind = "list", type = "npc" }} }}, "LeftButton")"""
    )
    assert wow.eval(f"{BR}.IsListOpen()") is True
    wow.run_frames(20)  # the slide (0.18 s)
    assert wow.eval(f"{MOD}.listPane:IsShown()") is True
    assert wow.eval(f"{MOD}.listPane:GetWidth()") == wow.eval(f"{BR}.ListWidth()")
    # its tab: a strip as high as the panes beside the splitter, lit on hover (owner, retail
    # 28.10.2026: the small tab at the top was hard to find)
    tab = f"{MOD}.listTab"
    assert wow.eval(f"select(2, {tab}:GetPoint(1)) == {MOD}.splitter") is True
    assert [wow.eval(f"({tab}:GetPoint({i}))") for i in (1, 2)] == ["TOPLEFT", "BOTTOMLEFT"]
    assert wow.eval(f"select(2, {MOD}.detailPane:GetPoint(1)) == {tab}") is True
    wow.execute(f"{tab}:GetScript('OnEnter')({tab})")
    assert wow.eval(f"{tab}.arrow:GetWidth()") == 18
    wow.execute(f"{tab}:GetScript('OnLeave')({tab})")
    assert wow.eval(f"{tab}.arrow:GetWidth()") == 14
    # its tab slides it back in
    wow.execute(f"{MOD}.listTab:Click()")
    wow.run_frames(20)
    assert (
        wow.eval(f"{BR}.IsListOpen()") is False and wow.eval(f"{MOD}.listPane:IsShown()") is False
    )
    # shut, the strip runs down the left edge of the page, as high as it
    assert [wow.eval(f"({tab}:GetPoint({i}))") for i in (1, 2)] == ["TOPLEFT", "BOTTOMLEFT"]
    assert wow.eval(f"select(2, {MOD}.detailPane:GetPoint(1)) == {tab}") is True
    # typing a search shows the results: out again
    wow.execute(f"{MOD}.search:SetText('hog')")
    wow.run_frames(20)
    assert wow.eval(f"{BR}.IsListOpen()") is True
    # the window opens shut again
    wow.execute("BastiansBrowserFrame:Hide()")
    wow.execute(f"{BR}.Open('npc:448')")
    assert wow.eval(f"{BR}.IsListOpen()") is False
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
    assert wow.eval(f"{STAGE}.frame:IsShown()") is True
    assert wow.eval(f"{STAGE}.model.creature") == 240  # Marshal Dughan gives it
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


def test_slim_sits_left_of_the_options_button(wow: WowRuntime):
    """Slim lay on the window's options button (R27.1)."""
    boot(wow)
    wow.execute(f"{BR}.Open('npc:448')")
    win = "Bastians.UI.Windows.BastiansBrowserFrame"
    assert wow.eval(f"select(2, {MOD}.toolbar.slim:GetPoint(1)) == {win}.options") is True
    assert wow.errors == []


def test_the_navigation_is_as_wide_as_the_player_drags_it(wow: WowRuntime):
    """ "Recent" was squeezed to "Qu..."; the navigation's right edge is
    a grip, its width kept (140 to 420 px)."""
    boot(wow)
    wow.execute(f"{BR}.Open('npc:448')")
    assert wow.eval(f"{BR}.NavWidth()") == 180
    grip = f"{BR}.navGrip"
    assert wow.eval(f"{grip}:IsShown()") is True
    wow.execute(f"{BR}.SetNavWidth(300)")
    assert wow.eval(f"{MOD}.nav:GetWidth()") == 300
    assert wow.eval(f"{MOD}.db.profile.navWidth") == 300
    wow.execute(f"{BR}.SetNavWidth(2000)")
    assert wow.eval(f"{BR}.NavWidth()") == 420
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
