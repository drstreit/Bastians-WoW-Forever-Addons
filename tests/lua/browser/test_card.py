"""The band (ADR 0013 B, N2; the dossier's band since C2): every entity page starts with the
entity's icon, name, the type badge, the summary (zone, level), the status words of a quest, and
the actions as labelled icon buttons plus the bookmark. The blocks below are the sections."""

import re

from harness import WowRuntime
from pages import band, band_buttons, page_rows

CORE, DATA, QUESTS, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Browser",
)
MOD = "Bastians:GetModule('Browser')"
BR = f"{MOD}.Browser"
DS = f"{MOD}.dossier"
SIZE = f"{MOD}.tree.scroll:SetSize(460, 400); {MOD}.tree:Refresh()"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, QUESTS, BROWSER)))
    wow.run_frames(10)
    wow.advance(0.3)
    return wow


def strip(text: str) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def flat(wow: WowRuntime) -> list[str]:
    return [strip(r.text) for r in wow.eval(f"{MOD}.tree.flat").values()]


def card(wow: WowRuntime) -> dict:
    c = band(wow, DS)
    c["shown"] = c["shown"] and wow.eval(f"{DS}:IsShown()")
    c["buttons"] = band_buttons(wow, DS)
    return c


def test_npc_quest_item_and_zone_pages_show_a_card(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{BR}.Open('npc:240')")
    wow.execute(SIZE)
    c = card(wow)
    assert c["shown"] and c["name"] == "Marshal Dughan" and c["badge"] == "npc"
    assert c["summary"] == "Level 10, Elwynn Forest"
    assert c["status"] == "0 yd"  # no status words: the distance alone (the player stands on him)
    assert c["buttons"] == ["Bookmark"]  # no Map, no Route: only the bookmark
    assert page_rows(wow, DS)[0] == "Overview"  # the blocks start with the sections
    assert wow.eval(f"{MOD}.header:GetHeight()") == 1  # the band is part of the dossier (C2)

    wow.execute(f"{BR}.Open('quest:62')")
    c = card(wow)
    assert c["name"] == "The Fargodeep Mine" and c["badge"] == "quest"
    assert c["status"] == "In the log, complete  0 yd"  # the distance to the hand-in (C1)
    assert c["buttons"] == ["Track", "Bookmark"]  # chains are a section, not an action
    assert "Chain" in page_rows(wow, DS)
    assert "Status" not in page_rows(wow, DS)  # the one status row moved onto the band
    assert c["height"] > 52

    wow.execute(f"{BR}.Open('item:2589')")
    c = card(wow)
    assert c["name"] == "Linen Cloth" and c["badge"] == "item" and c["status"] is None

    wow.execute(f"{BR}.Open('zone:1429')")
    c = card(wow)
    assert c["name"] == "Elwynn Forest" and c["badge"] == "zone"
    assert c["summary"] == "Level 7-11, Eastern Kingdoms"

    # the card as data, for every host
    data = wow.eval("Bastians.UI.DossierData('quest:176', nil, { source = 'browser' }).card")
    assert data.name == 'Wanted: "Hogger"' and data.typeLabel == "quest"
    assert data.icon is not None and data.status is not None
    ids = [a.id for a in data.actions.values()]
    assert "quests.track" in ids
    assert "browser.open" in ids  # another page is shown: opening this one is an action
    assert wow.eval(f"{BR}.IsBookmarked('quest:176')") is False
    assert wow.errors == []


def test_the_card_actions_run_and_follow_the_state(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{BR}.Open('quest:176')")
    wow.execute(SIZE)
    buttons = card(wow)["buttons"]
    assert buttons == ["Track", "Bookmark"]
    # Track runs the registered action: the quest is watched, the button turns into Untrack
    wow.execute(f"{DS}.buttons[1]:Click()")
    wow.run_frames(5)
    wow.advance(0.2)
    assert wow.eval("Bastians:GetModule('Quests').State.IsTracked(176)") is True
    assert card(wow)["buttons"][0] == "Untrack"
    # the bookmark toggles in place and shows in the bookmarks list
    wow.execute(f"{DS}.buttons[{DS}.buttonCount]:Click()")
    assert card(wow)["buttons"][-1] == "Bookmarked"
    assert wow.eval(f"{BR}.IsBookmarked('quest:176')") is True
    # a view (the log) fills the list pane with its control bar; the page stays in the detail
    # pane beside it (ADR 0018)
    wow.slash("/bq log")
    assert wow.eval(f"{BR}.Current().kind") == "view"
    assert wow.eval(f"{DS}:IsShown()") is True and card(wow)["name"] == 'Wanted: "Hogger"'
    assert wow.eval(f"{MOD}.controlBar:IsShown()") is True
    assert wow.eval(f"{MOD}.header:GetHeight()") == 22
    wow.execute(f"{BR}.Back()")
    assert wow.eval(f"{DS}:IsShown()") is True
    assert wow.eval(f"{MOD}.controlBar:IsShown()") is False
    # before any list the list pane shows Here (the zone's dossier), not the tree
    assert wow.eval(f"{MOD}.tree.scroll:IsShown()") is False
    assert wow.eval(f"{MOD}.hereDossier:IsShown()") is True
    # the search entry: the tree in the list pane, no control bar, the page still beside it
    wow.execute(f"{BR}.Home()")
    assert wow.eval(f"{DS}:IsShown()") is True
    assert wow.eval(f"{MOD}.tree.scroll:IsShown()") is True
    assert wow.eval(f"{MOD}.header:GetHeight()") == 1
    assert wow.errors == []


def test_a_page_without_data_has_a_card_with_the_ref(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{BR}.Open('npc:999999')")
    wow.execute(SIZE)
    c = card(wow)
    assert c["shown"] and c["name"] == "npc:999999" and c["badge"] == "npc"
    # the band says why it is empty (ADR 0018: on the page, not on the list's summary line)
    assert c["summary"].startswith("No data for this entity") and c["buttons"] == ["Bookmark"]
    assert wow.eval(f"{DS}.blockCount") == 0
    assert wow.errors == []
