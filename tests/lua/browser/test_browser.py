"""Browser (B7.1-B7.3): the entity page with header, actions and sections; lists by type with facets
built as jobs; clickable refs with history, back and forward; bookmarks per character; the tooltip hint."""

import re

from harness import WowRuntime
from pages import (
    band,
    band_buttons,
    click_ref,
    menu,
    nav_click,
    nav_lists,
    page_refs,
    page_rows,
    pick,
    pills,
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
SIZE = f"{MOD}.tree.scroll:SetSize(440, 400); {MOD}.tree:Refresh()"
TREE = f"{MOD}.tree"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, QUESTS, BROWSER)))
    wow.run_frames(10)
    return wow


def strip(text: str) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def flat(wow: WowRuntime) -> list[str]:
    return [strip(r.text) for r in wow.eval(f"{MOD}.tree.flat").values()]


def title(wow: WowRuntime) -> str:
    return strip(wow.eval(f"{MOD}.win.title:GetText()"))


def actions(wow: WowRuntime) -> list[str]:
    """The labelled buttons of the page's band (ADR 0013 B, C2), the bookmark button excluded."""
    return [t for t in band_buttons(wow, DS) if t not in ("Bookmark", "Bookmarked")]


def subject(wow: WowRuntime) -> str:
    """The name on the detail pane's band: the page shown (ADR 0018)."""
    return band(wow, DS)["name"]


def chips(wow: WowRuntime) -> list[str]:
    """The filter bar's pills (ADR 0016)."""
    return pills(wow, TREE)


def test_entity_page_has_header_actions_and_sections_in_order(wow: WowRuntime):
    boot(wow)
    wow.slash("/bb npc:240")
    wow.execute(SIZE)
    # the page shows in the detail pane; the window names the list pane, Here before any list
    assert title(wow) == "Here: Elwynn Forest"
    assert subject(wow) == "Marshal Dughan"
    texts = page_rows(wow, DS)
    # the name and the summary are on the band (ADR 0013 B, C2); the blocks start with the
    # sections; no "Source" line
    assert texts[0] == "Overview"
    assert band(wow, DS)["name"] == "Marshal Dughan"
    assert band(wow, DS)["summary"] == "Level 10, Elwynn Forest"
    assert not any(t.startswith("Source:") for t in texts)
    assert [t for t in texts if t in ("Overview", "Locations", "Starts quests", "Ends quests")] == [
        "Overview",
        "Locations",
        "Starts quests",
        "Ends quests",
    ]
    # no action for an NPC without Map and Route: the page's own card does not offer to re-open
    # itself (ADR 0013, N1); in rows and menus the action is greyed while the Browser is open
    # and refuses to run
    assert actions(wow) == []
    assert (
        wow.eval("Bastians:RunAction('browser.open', 'npc:240', { source = 'browser' })") is False
    )
    assert "Open in Browser" in [
        a.label for a in wow.eval("Bastians:GetActions('npc:448', { source = 'browser' })").values()
    ]
    # quest rows sit under category rows: 62 is in the log, complete
    fargodeep = texts.index("The Fargodeep Mine")
    headers = [
        t for t in texts[:fargodeep] if t in ("Ready to turn in", "In your log", "Available")
    ]
    assert headers and headers[-1] == "Ready to turn in"
    quest_rows = [r for r in page_refs(wow, DS) if r.ref.startswith("quest:")]
    assert all(r.status for r in quest_rows)
    wow.slash("/bb quest:176")
    assert "Track" in actions(wow)  # Quests' action, no change here
    assert "Status" not in page_rows(wow, DS)  # the one status row sits on the band (ADR 0013 B)
    assert band(wow, DS)["status"] is not None
    assert wow.errors == []


def test_refs_in_rows_lead_to_their_pages_with_history(wow: WowRuntime):
    boot(wow)
    wow.slash("/bb npc:240")
    wow.execute(SIZE)
    # the quest row under "Starts quests" is a link: a left click opens that page
    assert click_ref(wow, DS, "quest:62") is True
    assert subject(wow) == "The Fargodeep Mine"
    history, cursor = wow.eval(f"{BR}.History()")
    assert [h.ref for h in history.values()] == ["npc:240", "quest:62"] and cursor == 2
    wow.execute(f"{BR}.Back()")
    assert subject(wow) == "Marshal Dughan"
    wow.execute(f"{BR}.Forward()")
    assert subject(wow) == "The Fargodeep Mine"
    wow.slash("/bb npc:448")  # a new page after going back truncates the forward branch
    wow.execute(f"{BR}.Back()")
    wow.execute(f"{BR}.Back()")
    wow.slash("/bb item:2589")
    history, cursor = wow.eval(f"{BR}.History()")
    assert [h.ref for h in history.values()] == ["npc:240", "item:2589"] and cursor == 2
    # a right click opens the entity menu instead
    assert click_ref(wow, DS, "npc:448", "RightButton") is True
    assert wow.eval("Bastians.UI.EntityMenuFrame():IsShown()") is True
    assert wow.errors == []


def test_lists_by_type_with_facets_are_built_as_jobs(wow: WowRuntime):
    boot(wow)
    wow.slash("/bb npcs")
    wow.execute(SIZE)
    assert flat(wow) == ["Building the list ..."]
    wow.run_frames(5)
    assert title(wow) == "NPCs"
    assert flat(wow) == [  # the list opens on the player's zone (C9): Westfall's Gryan is not here
        "Corina Steele  15",
        "Goldtooth  8",
        "Hogger  11",
        "Innkeeper Farley  6",
        "Marshal Dughan  10",
        "Zaldimar Wefhellt  30",
    ]
    # the list types are the navigation's Lists (ADR 0018; before, the type bar), the shown one
    # accented
    types = [
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
    assert nav_lists(wow) == types
    assert wow.eval(f"{MOD}.navTree.selectedID") == "nav:list:npc"
    # one filter bar (ADR 0016): a pill per dimension, the counts inside the dropdowns, given the
    # other filters (Here: Westfall's quest giver is not counted)
    assert chips(wow) == ["Where: Here", "Service: All", "Rank: All", "Level: All", "Sort: Name"]
    assert menu(wow, TREE, "where") == ["All  7", "Here  6", "Continent  7"]
    assert menu(wow, TREE, "service") == [
        "All  6",
        "Innkeeper  1",
        "Quest giver  1",
        "Trainer  1",
        "Vendor  1",
        "No service  2",  # Hogger (elite, no service) and Goldtooth
    ]
    assert menu(wow, TREE, "rank") == ["All  6", "Normal  5", "Elite  1"]
    assert menu(wow, TREE, "level") == ["All  6", "1-10  3", "11-20  2", "21-30  1"]
    assert strip(wow.eval(f"{MOD}.summary:GetText()")) == "6 of 6 shown"
    pick(wow, TREE, "service", "Quest giver")  # quest givers, within the zone
    assert flat(wow) == ["Marshal Dughan  10"]
    assert menu(wow, TREE, "where") == ["All  2", "Here  1", "Continent  2"]  # filters combine
    pick(wow, TREE, "where", "Continent")  # Continent: Westfall's giver too
    assert flat(wow) == ["Gryan Stoutmantle  20", "Marshal Dughan  10"]
    assert chips(wow)[:2] == ["Where: Continent", "Service: Quest giver"]
    nav_click(wow, "nav:list:zone")  # another list from the navigation
    wow.run_frames(5)
    assert title(wow) == "Zones" and any(r.startswith("Elwynn Forest") for r in flat(wow))
    wow.execute(f"{BR}.Home()")  # the search entry
    assert wow.eval(f"{BR}.Current().kind") == "home"
    wow.slash("/bb npcs")
    wow.run_frames(5)
    wow.execute(
        f"{BR}.List('item')"  # the type chips of the home lead here (ADR 0013 F)
    )  # the type menu
    wow.run_frames(5)
    assert title(wow) in (
        "Search",  # "All" sorts first in the type menu since 21.10.2026: the search home
        "Farm spots",
        "Items",
        "NPCs",
        "Nodes",
        "Objects",
        "Quests",
        "Recipes",
        "Zones",
    )
    wow.slash("/bb item")
    wow.run_frames(5)
    assert menu(wow, TREE, "class")[0:2] == ["All  4", "Trade Goods  2"]
    assert "Blood Saber  7" in flat(wow)
    wow.slash("/bb zones")
    wow.run_frames(5)
    assert any(r.startswith("Elwynn Forest") for r in flat(wow))  # the zone index, band rows (C9)
    wow.slash("/bb nodes")
    wow.run_frames(5)
    assert flat(wow) == ["No entries. Is the data pack loaded?"]
    assert wow.errors == []


def test_bookmarks_toggle_persist_and_list(wow: WowRuntime):
    boot(wow)
    wow.slash("/bb npc:448")
    wow.execute(SIZE)
    # the bookmark button is the band's last button (ADR 0013 B, C2)
    bookmark = f"{DS}.buttons[{DS}.buttonCount]"
    assert strip(wow.eval(f"{bookmark}.label:GetText()")) == "Bookmark"
    wow.execute(f"{bookmark}:Click()")
    assert strip(wow.eval(f"{bookmark}.label:GetText()")) == "Bookmarked"
    assert wow.eval(f"{BR}.IsBookmarked('npc:448')") is True
    wow.slash("/bb item:2589")
    wow.execute(f"{bookmark}:Click()")
    wow.slash("/bb bookmarks")
    assert title(wow) == "Bookmarks"
    assert flat(wow) == ["Hogger  npc:448", "Linen Cloth  item:2589"]
    fresh = wow.reload()
    fresh.run_frames(10)
    assert list(fresh.eval("BastiansBrowserCharDB.bookmarks").values()) == ["npc:448", "item:2589"]
    fresh.slash("/bb bookmarks")
    fresh.execute(SIZE)
    assert [strip(r.text) for r in fresh.eval(f"{MOD}.tree.flat").values()] == [
        "Hogger  npc:448",
        "Linen Cloth  item:2589",
    ]
    fresh.execute(f"{BR}.ToggleBookmark('npc:448')")
    assert fresh.eval(f"{BR}.IsBookmarked('npc:448')") is False
    assert fresh.errors == []


def test_tooltip_hint_line_only_with_the_browser(wow: WowRuntime):
    boot(wow, CORE, DATA, QUESTS)
    lines = [strip(line["left"]) for line in wow.tooltip("Unit", 240)]
    assert "Right click: open in the Browser" not in lines
    wow.load_addon(BROWSER)
    wow.run_frames(5)
    wow.execute("GameTooltip:Hide()")
    lines = [strip(line["left"]) for line in wow.tooltip("Unit", 240)]
    assert lines[-1] == "Right click: open in the Browser"
    assert "browser.hint" not in {
        s.id for s in wow.eval("Bastians:GetDetailSections('npc:240')").values()
    }  # a hint, not a page section


def test_gold_sections_and_actions_appear_on_the_right_pages(wow: WowRuntime):
    wow.execute('function GetRealmName() return "Classic Beta PvE" end')
    boot(wow, CORE, DATA, GOLD, BROWSER)
    wow.slash("/bb item:2589")
    wow.execute(SIZE)
    assert "Price" in page_rows(wow, DS) and "Where to farm" in page_rows(wow, DS)
    assert [k.relation for k in wow.eval(f"{DS}.data.links").values()] == [
        "best spot"
    ]  # Gold's link; no zone on an item
    assert "Prices" in actions(wow) and "Where to farm" in actions(wow)
    wow.slash("/bb spots")
    wow.run_frames(5)
    assert chips(wow)[:2] == ["Where: Here", "Status: All"] and "Hogger's camp" in flat(wow)
    assert wow.errors == []


def test_quest_chains_are_a_list_of_their_own(wow: WowRuntime):
    """(N9): "an easier way to find quest chains, a list of its own".
    Quests registers the list through Core (RegisterList); one row per chain the character can
    take, named after its first quest with the steps in grey; a row opens the first quest."""
    boot(wow)
    wow.slash("/bb chains")
    wow.run_frames(10)
    assert title(wow) == "Quest chains"
    rows = flat(wow)
    assert rows and all("steps" in r for r in rows)
    first = wow.eval(f"{MOD}.tree.flat[1]")
    assert first.ref.startswith("quest:")
    wow.execute(SIZE)
    wow.execute(f"{MOD}.tree.pool[1]:Click('LeftButton')")
    wow.run_frames(5)
    assert wow.eval(f"{BR}.Current().ref") == first.ref
    # without Quests there is no such list
    assert wow.eval("#Bastians:GetLists()") == 1
    assert wow.errors == []
