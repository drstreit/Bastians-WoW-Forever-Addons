"""One window (ADR 0012, ADR 0013): the Browser hosts the views apps register (core-contracts §7b)
and the pages apps open through it (`ShowPage`). With the Browser, /bq opens the player's zone page
and the Quests views open in it; without it, they open in Quests' own fallback window."""

import re

from harness import WowRuntime
from pages import band, click_ref, page_rows

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


def test_bq_opens_the_zone_page_in_the_browser(wow: WowRuntime):
    boot(wow)
    wow.slash("/bq here")  # /bq alone opens the window with the Here column since C4
    wow.execute(SIZE)
    assert wow.eval("BastiansBrowserFrame:IsShown()") is True
    assert wow.eval("BastiansQuestsFrame == nil or not BastiansQuestsFrame:IsShown()") is True
    assert wow.eval(f"{BR}.Current().kind") == "page"
    assert wow.eval(f"{BR}.Current().ref") == "zone:1429"
    # the window names the list pane (Here), the zone's page is the detail (ADR 0018)
    assert strip(wow.eval(f"{MOD}.win.title:GetText()")) == "Here: Elwynn Forest"
    assert wow.eval(f"{DS}:IsShown()") is True
    assert band(wow, DS)["name"] == "Elwynn Forest"
    assert band(wow, DS)["summary"] == "Level 7-11, Eastern Kingdoms"
    texts = page_rows(wow, DS)
    assert texts[0] == "To do here  2" and "Hand in  1" in texts and "Places" in texts
    assert wow.eval("Bastians:GetModule('Quests').Window.IsShown()") is True
    assert wow.eval("Bastians:ShowPage('zone:1436')") is True
    assert wow.eval(f"{BR}.Current().ref") == "zone:1436"
    assert wow.eval("Bastians:ShowPage('nonsense')") is False
    # the views that remain are rows of the Browser's home; the old ones are gone
    views = [r.view for r in wow.eval(f"{BR}.IdleRows()[1].children").values()]  # no Here (C4)
    assert views == ["quests.log", "quests.all", "quests.attune"]
    assert wow.errors == []


def test_pages_and_views_share_one_history(wow: WowRuntime):
    boot(wow)
    wow.slash("/bq here")
    wow.execute(SIZE)
    # a zone row (Onward, Neighbours) opens that zone's page; a quest row opens the quest's page
    assert click_ref(wow, DS, "zone:1436") is True
    assert wow.eval(f"{BR}.Current().ref") == "zone:1436"
    assert band(wow, DS)["name"] == "Westfall"
    wow.execute(f"{BR}.Back()")
    assert wow.eval(f"{BR}.Current().ref") == "zone:1429"
    assert click_ref(wow, DS, "quest:62") is True
    assert wow.eval(f"{BR}.Current().ref") == "quest:62"
    assert wow.eval(f"{DS}:IsShown()") is True
    assert wow.eval(f"{MOD}.controlBar:IsShown()") is False
    assert "Chain" in page_rows(wow, DS)  # the chain lives on the quest page (ADR 0013 A)
    # a view in the same history: Back from it returns to the page
    wow.slash("/bq log")
    assert wow.eval(f"{BR}.Current().kind") == "view"
    assert wow.eval(f"{BR}.Current().id") == "quests.log"
    assert wow.eval(f"{MOD}.win.title:GetText()") == "Quests: My quests"
    # the view fills the list pane; the quest's page stays in the detail pane (ADR 0018)
    assert wow.eval(f"{DS}:IsShown()") is True and band(wow, DS)["name"] == "The Fargodeep Mine"
    assert wow.eval(f"{MOD}.controlBar:IsShown()") is True
    assert flat(wow)[0] == "HAND IN HERE  1"
    wow.execute(f"{BR}.Back()")
    assert wow.eval(f"{BR}.Current().ref") == "quest:62"
    # /bq <id> opens that quest's page
    wow.slash("/bq 76")
    assert wow.eval(f"{BR}.Current().ref") == "quest:76"
    assert wow.errors == []


def test_the_item_bar_follows_the_log_view_in_the_browser(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.questLog[2].item = { id = 2589, icon = 132889 }; Mock.bags[2589] = 1")
    wow.slash("/bq log")
    wow.execute(SIZE)
    assert wow.eval(f"{MOD}.win.title:GetText()") == "Quests: My quests"
    assert wow.eval("BastiansQuestsItemBar:IsShown()") is True
    assert wow.eval("BastiansQuestsItem1:GetAttribute('item')") == "item:2589"
    # a page: the view is left, but the Here column's "My quests here" keeps the bar (C4)
    wow.execute(f"{BR}.Open('npc:240')")
    assert wow.eval("BastiansQuestsItemBar:IsShown()") is True
    wow.execute(f"{BR}.Back()")
    assert wow.eval("BastiansQuestsItemBar:IsShown()") is True
    wow.execute("BastiansBrowserFrame:Hide()")
    assert wow.eval("BastiansQuestsItemBar:IsShown()") is False
    assert wow.errors == []


def test_a_quest_change_re_renders_the_view_in_the_browser(wow: WowRuntime):
    boot(wow)
    wow.slash("/bq log")
    wow.execute(SIZE)
    wow.execute(
        "Mock.questLog[2].objectives[1].numFulfilled = 1; Mock.questLog[2].objectives[1].finished = true"
    )
    wow.fire("QUEST_LOG_UPDATE")
    wow.advance(0.3)
    assert any(t.endswith("The Fargodeep Mine  Group  1/1") for t in flat(wow))
    # the zone page follows too: its sections are rebuilt on the quest change
    wow.slash("/bq here")
    assert any("1/1 objectives" in t for t in page_rows(wow, DS))
    assert wow.errors == []


def test_without_the_browser_the_quests_window_hosts_views_and_pages(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{MOD}:Disable()")
    wow.slash("/bq")
    assert wow.eval("BastiansQuestsFrame:IsShown()") is True
    assert wow.eval("BastiansBrowserFrame == nil or not BastiansBrowserFrame:IsShown()") is True
    assert wow.eval("Bastians:GetModule('Quests').Window.IsShown()") is True
    assert wow.eval("Bastians:GetService('views'):CurrentPage()") == "zone:1429"
    # the Browser comes back: the next open goes to it again
    wow.execute("BastiansQuestsFrame:Hide()")
    wow.execute(f"{MOD}:Enable()")
    wow.slash("/bq all")
    assert wow.eval("BastiansBrowserFrame:IsShown()") is True
    assert wow.eval(f"{MOD}.win.title:GetText()") == "Quests: All quests"
    assert wow.errors == []


def test_a_view_of_an_addon_that_is_off_says_so(wow: WowRuntime):
    boot(wow)
    wow.slash("/bq log")
    wow.execute("Bastians:GetModule('Quests'):Disable()")
    wow.execute(f"{BR}.Render()")
    assert wow.eval(f"{MOD}.win.title:GetText()") == "Not available"
    assert flat(wow)[0].startswith("This view is not available")
    assert wow.errors == []
