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
    wow.execute(f"local f = {row_frame(wow, 'npc:448')} f:Click('LeftButton')")
    assert wow.eval(f"{BR}.Current().ref") == "npc:448" and band(wow, DS)["name"] == "Hogger"
    assert wow.eval(f"{BR}.ListEntry().type") == "npc"  # the list stays
    assert wow.eval(f"{MOD}.tree.selectedID") == "npc:448"  # its row carries the mark
    assert any(
        strip(r.text).startswith("Corina Steele") for r in wow.eval(f"{MOD}.tree.flat").values()
    )
    # a navigation click changes the list and keeps the page
    nav_click(wow, "nav:list:item")
    wow.run_frames(5)
    assert wow.eval(f"{BR}.ListEntry().type") == "item" and band(wow, DS)["name"] == "Hogger"
    assert nav_active(wow) == "nav:list:item"
    # Back walks both: the NPC list with Hogger, then the list before the page
    wow.execute(f"{BR}.Back()")
    assert wow.eval(f"{BR}.ListEntry().type") == "npc" and band(wow, DS)["name"] == "Hogger"
    wow.execute(f"{BR}.Back()")
    assert wow.eval(f"{BR}.Current().kind") == "list"
    assert band(wow, DS)["name"] == "Elwynn Forest"
    assert wow.errors == []


def test_a_resting_row_shows_as_a_preview_and_a_click_keeps_it(wow: WowRuntime):
    boot(wow)
    open_npcs(wow)
    wow.execute(f"{BR}.Open('npc:240')")
    hover(wow, "npc:448")
    wow.advance(0.5)  # before the tip delay (one second by default): nothing changes
    assert band(wow, DS)["name"] == "Marshal Dughan"
    wow.advance(0.6)
    assert band(wow, DS)["name"] == "Hogger" and wow.eval(f"{BR}.Previewing()") == "npc:448"
    assert wow.eval(f"{DS}.band.preview:IsShown()") is True
    assert wow.eval(f"{BR}.Current().ref") == "npc:240"  # the history is untouched
    hover(wow, "npc:448", entering=False)  # leaving: the kept page comes back
    assert band(wow, DS)["name"] == "Marshal Dughan"
    assert wow.eval(f"{DS}.band.preview:IsShown()") is False
    # leaving before the delay: no preview at all
    hover(wow, "npc:448")
    wow.advance(0.3)
    hover(wow, "npc:448", entering=False)
    wow.advance(1)
    assert band(wow, DS)["name"] == "Marshal Dughan" and wow.eval(f"{BR}.Previewing()") is None
    # rest, then click: the preview is kept as the page
    hover(wow, "npc:448")
    wow.advance(1.1)
    wow.execute(f"local f = {row_frame(wow, 'npc:448')} f:Click('LeftButton')")
    assert wow.eval(f"{BR}.Current().ref") == "npc:448" and wow.eval(f"{BR}.Previewing()") is None
    assert wow.eval(f"{DS}.band.preview:IsShown()") is False
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
    glyphs = "Interface\\AddOns\\Bastians_Core\\Media\\Glyphs\\"
    icons = {strip(r.text).split("  ")[0]: r.icon for r in wow.eval(f"{MOD}.tree.flat").values()}
    assert icons["Innkeeper Farley"] == glyphs + "innkeeper"
    assert icons["Marshal Dughan"] == glyphs + "quest"  # a quest giver
    assert icons["Hogger"] == wow.eval("Bastians.UI.IconTexture('mob')")  # no service: a monster
    assert wow.eval(f"{BR}.RowGlyph({{ type = 'zone', dims = {{}}, values = {{}} }}, 1)") == "zone"
    assert wow.errors == []


def test_loot_sells_and_rewards_are_small_tables(wow: WowRuntime):
    boot(wow, CORE, DATA, QUESTS, GOLD, BROWSER)
    wow.execute(f"{BR}.Open('npc:448')")
    wow.execute(f"{DS}.scroll:SetSize(420, 600); {DS}:Refresh()")
    drops = None
    for bf in wow.eval(f"{DS}.blockPool").values():
        if bf.IsShown(bf) and strip(bf.title.GetText(bf.title)).startswith("DROPS"):
            drops = bf
    assert drops is not None and drops.tree.opts.table is True
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
