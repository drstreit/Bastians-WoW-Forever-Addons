"""The Browser's search entry: with an
empty box it shows the views, the bookmarks and the recent pages; typing searches from the second
character through Core's providers with the type word first or last; a list in the navigation sets
the type (clicked again, every type); the search keeps its text, so a result's page opens beside
the results and Back returns to them."""

import re

from harness import WowRuntime
from pages import band, nav_click, nav_lists, nav_rows, pills

CORE, DATA, QUESTS, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Browser",
)
MOD = "Bastians:GetModule('Browser')"
BR = f"{MOD}.Browser"
SIZE = f"{MOD}.tree.scroll:SetSize(460, 400); {MOD}.tree:Refresh()"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA, QUESTS, BROWSER)
    wow.run_frames(10)
    wow.advance(0.3)
    return wow


def strip(text: str) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def flat(wow: WowRuntime) -> list[str]:
    return [strip(r.text) for r in wow.eval(f"{MOD}.tree.flat").values()]


def chips(wow: WowRuntime) -> list[str]:
    """The filter bar's pills (ADR 0016)."""
    return pills(wow, f"{MOD}.tree")


TYPES = {"Quests": "quest", "NPCs": "npc", "Zones": "zone"}


def click_chip(wow: WowRuntime, label: str) -> None:
    """A list in the navigation (ADR 0018; before, the type bar's chip)."""
    nav_click(wow, "nav:list:" + TYPES[label])


def test_open_lands_on_the_home_with_here_views_and_chips(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{BR}.Open()")
    wow.execute(SIZE)
    assert wow.eval(f"{BR}.Current().kind") == "home"
    assert wow.eval(f"{MOD}.win.title:GetText()") == "Search"
    assert wow.eval(f"{MOD}.toolbar.types") is None  # the dropdown is gone (ADR 0013 F)
    assert chips(wow) == []  # the types are the navigation's lists (ADR 0018)
    assert nav_lists(wow) == [
        "Farm spots",
        "Items",
        "NPCs",
        "Nodes",
        "Objects",
        "Quest chains",
        "Quests",
        "Recipes",
        "Zones",
    ]  # by name; chains from Quests
    texts = flat(wow)
    # the player's zone is Here in the navigation (ADR 0018), not a section of the home; the
    # detail pane shows the zone's page before any other
    assert texts[0] == "Quests" and "Here" not in texts
    assert nav_rows(wow)[0] == ("nav:here", "Here: Elwynn Forest")
    assert band(wow, f"{MOD}.dossier")["name"] == "Elwynn Forest"
    quests = texts.index("Quests")
    assert texts[quests + 1 : quests + 4] == [
        "My quests  2 in the log",
        "All quests",
        "Attunements",
    ]
    assert "Bookmarks" not in texts and "Recent" not in texts  # nothing yet
    # a view row opens its view
    wow.execute(
        f"for _, r in ipairs({MOD}.tree.flat) do "
        f"if r.view == 'quests.log' then {MOD}.tree.opts.onClick(r, 'LeftButton') break end end"
    )
    assert wow.eval(f"{BR}.Current().kind") == "view"
    assert wow.eval(f"{BR}.Current().id") == "quests.log"
    assert wow.eval("Bastians:GetModule('Browser').def.open ~= nil") is True
    assert wow.errors == []


def test_the_home_lists_bookmarks_and_recent_pages(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{BR}.Open('npc:448'); {BR}.Open('item:2589'); {BR}.Open('npc:448')")
    wow.execute(f"{BR}.ToggleBookmark('item:2589')")
    wow.execute(f"{BR}.Home()")
    wow.execute(SIZE)
    # the navigation lists them too (ADR 0018), each once, the recent pages newest first
    rows = nav_rows(wow)
    assert ("nav:bm:item:2589", "Linen Cloth") in rows
    recent = [t for rid, t in rows if rid.startswith("nav:recent:")]
    assert recent == ["Hogger", "Linen Cloth"]
    assert wow.eval(f"{BR}.Current().kind") == "home"
    texts = flat(wow)
    marks = texts.index("Bookmarks")
    assert texts[marks + 1] == "Linen Cloth  item"
    recent = texts.index("Recent")
    assert texts[recent + 1 : recent + 3] == [
        "Hogger  npc",
        "Linen Cloth  item",
    ]  # newest first, once
    wow.execute(f"{MOD}.tree.opts.onClick({MOD}.tree.flat[{recent + 2}], 'LeftButton')")
    assert wow.eval(f"{BR}.Current().ref") == "npc:448"
    assert wow.errors == []


def test_typing_searches_and_a_type_word_narrows(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{BR}.Open()")
    wow.execute(f"{MOD}.search:SetText('h')")
    wow.run_frames(10)
    assert flat(wow)[0].startswith("Start typing")
    wow.execute(f"{MOD}.search:SetText('hog')")
    wow.run_frames(20)
    rows = flat(wow)
    assert any(r.startswith("Hogger") and "npc" in r for r in rows)
    assert any("Hogger" in r and "quest" in r for r in rows)
    # the names that start with the text come first, a rule divides them from the rest (second
    # round 21.10.2026); the rule row is the divider kind the tree draws as a line
    kinds = [r.kind for r in wow.eval(f"{MOD}.tree.flat").values()]
    assert kinds.count("rule") == 1
    rule = kinds.index("rule")
    assert all(r.lower().startswith("hog") for r in rows[:rule]) and rows[:rule]
    assert rows[rule] == "" and not any(r.lower().startswith("hog") for r in rows[rule + 1 :])
    # the rows helper alone: no rule when one group is empty
    assert (
        wow.eval(
            f"#{BR}.HomeRows({{ {{ ref = 'npc:1', label = 'Hogger' }}, "
            "{ ref = 'npc:2', label = 'Hogan' } }, 'hog')"
        )
        == 2
    )
    assert (
        wow.eval(
            f"{BR}.HomeRows({{ {{ ref = 'npc:1', label = 'Hogger' }}, "
            "{ ref = 'npc:2', label = 'Big Hog' } }, 'hog')[2].kind"
        )
        == "rule"
    )
    wow.execute(f"{MOD}.search:SetText('npc hog')")
    wow.run_frames(20)
    # one line per result (ADR 0018 B): the name, then the type and the summary in grey
    assert flat(wow) == ["Hogger  npc - Level 11, elite, Elwynn Forest"]
    assert wow.eval(f"{MOD}.tree.flat[1].icon") is not None
    wow.execute(f"{MOD}.search:SetText('hog npc')")  # the type word last works too (ADR 0013 F)
    wow.run_frames(20)
    assert [r.split(" - ")[0] for r in flat(wow)] == ["Hogger  npc"]
    assert wow.eval(f"{MOD}.summary:GetText()") == "1 matches"
    # a result opens its page in the detail pane; the results stay in the list pane
    wow.execute(f"local ref = {MOD}.tree.flat[1].ref if ref then {BR}.Open(ref) end")
    assert wow.eval(f"{BR}.Current().kind") == "page"
    assert band(wow, f"{MOD}.dossier")["name"] == "Hogger"
    assert flat(wow)[0].startswith("Hogger  npc")
    assert wow.eval(f"{MOD}.search:GetText()") == "hog npc"
    assert wow.eval(f"{MOD}.tree.selectedID") == "s:npc:448"  # the result shown is marked
    wow.execute(f"{BR}.Back()")
    assert wow.eval(f"{BR}.Current().kind") == "home"
    assert wow.eval(f"{MOD}.search:GetText()") == "hog npc"  # the search kept its text
    assert wow.errors == []


def test_a_type_chip_sets_the_type(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{BR}.Open()")
    wow.execute(f"{MOD}.search:SetText('hog')")
    wow.run_frames(20)
    assert len(flat(wow)) > 1
    click_chip(wow, "Quests")
    wow.run_frames(20)
    assert wow.eval(f"{BR}.HomeType()") == "quest"
    rows = flat(wow)
    assert rows and all("quest" in r for r in rows)
    click_chip(wow, "NPCs")
    wow.run_frames(20)
    assert [r.split(" - ")[0] for r in flat(wow)] == ["Hogger  npc"]
    assert wow.eval(f"{MOD}.navTree.selectedID") == "nav:list:npc"  # the filter shows
    # a type word in the text wins over the list
    wow.execute(f"{MOD}.search:SetText('quest hog')")
    wow.run_frames(20)
    assert all("quest" in r for r in flat(wow))
    click_chip(wow, "NPCs")  # the filtering list again: every type
    wow.run_frames(20)
    assert wow.eval(f"{BR}.HomeType()") is None
    # a chip with nothing typed opens that type's list
    wow.execute(f"{MOD}.search:SetText('')")
    wow.run_frames(5)
    click_chip(wow, "Zones")
    wow.run_frames(10)
    assert wow.eval(f"{BR}.Current().kind") == "list"  # a list with nothing typed
    assert wow.eval(f"{BR}.Current().type") == "zone"
    assert wow.errors == []
