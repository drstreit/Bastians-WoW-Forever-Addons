"""Quests pages and views in the fallback window (B5.3, ADR 0012, ADR 0013: without the Browser the
Quests views and the entity pages show in this addon's own window): the zone page with its sections
and counts, the quest page and its chain's page, the log view (My quests) with the secure quest-item bar
that is never touched in combat, All quests, search, refresh on quest and zone changes."""

import re

from harness import WowRuntime
from pages import (
    band,
    band_buttons,
    block_rows,
    block_titles,
    click_ref,
    menu,
    page_entries,
    page_rows,
    pick,
    pills,
)

CORE, DATA, QUESTS = "Bastians_Core", "Bastians_Data", "Bastians_Quests"
WIN = "Bastians:GetModule('Quests').Window"
DS = f"{WIN}.dossier"
SIZE = (
    f"{WIN}.tree.scroll:SetSize(500, 400); {WIN}.tree:Refresh()"  # anchors give no size on the mock
)


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, QUESTS)))
    wow.run_frames(10)
    wow.advance(0.3)  # the zone announcement after PLAYER_ENTERING_WORLD
    return wow


def open_view(wow: WowRuntime, command: str) -> None:
    wow.slash(command)
    wow.execute(SIZE)
    wow.run_frames(10)  # the All view builds in a job


def strip(text: str) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    text = re.sub(r"\|H[^|]*\|h", "", text)
    return text.replace("|r", "").replace("|h", "")


def flat(wow: WowRuntime) -> list[str]:
    return [strip(r.text) for r in wow.eval(f"{WIN}.tree.flat").values()]


def chips(wow: WowRuntime) -> list[str]:
    """The filter bar's pills (ADR 0016)."""
    return pills(wow, f"{WIN}.tree")


def summary(wow: WowRuntime) -> str:
    return strip(wow.eval(f"{WIN}.summary:GetText()"))


def title(wow: WowRuntime) -> str:
    return strip(wow.eval(f"{WIN}.win.title:GetText()"))


def errors(wow: WowRuntime) -> list[str]:
    return wow.errors + [
        line.text
        for line in wow.eval("Bastians:GetLog()").values()
        if line.level == "error" and "registered no data" not in line.text
    ]


def test_bq_opens_the_zone_page_with_its_sections_and_counts(wow: WowRuntime):
    boot(wow)
    open_view(wow, "/bq")
    assert wow.eval(f"{WIN}.IsShown()") is True
    assert wow.eval("Bastians:GetService('views'):CurrentPage()") == "zone:1429"
    assert title(wow) == "Elwynn Forest"
    assert band(wow, DS)["name"] == "Elwynn Forest"
    assert (
        band(wow, DS)["summary"]
        == "Quests from level 7 to 11. Eastern Kingdoms. Fishing from skill 25."
    )
    assert page_rows(wow, DS) == [
        "To do here  2",
        "[7] The Fargodeep Mine II  Chain 1/3  304 xp, +2 unlocks, 3 min (distance unknown)",
        "[11] The Fargodeep Mine  Group  532 xp, 1s reward, 5 min (item price unknown, distance "
        "unknown, group quest)",
        "Hand in  1",
        "Marshal Dughan",
        "[7] The Fargodeep Mine  Chain 1/3",
        "In progress  1",
        "Marshal Dughan",
        '[11] Wanted: "Hogger"  Group  0/1 objectives',
        "Onward  1",
        "> Westfall  9-10 - 1 quest leads there",
        "Chains here",  # the zone's chains (ADR 0055), after its quests
        "The Fargodeep Mine",
        "People",  # Data's people by what they do (ADR 0054, 05.11.2026; "Places" before)
        "Innkeeper Farley  Innkeeper",
        "Quest givers  1",
        "Vendors  1",
        "Trainers  1",
        "Auction house  1",  # the fixture auctioneer (W10 step 2)
        "Neighbours",
        "> Westfall  9-10",
        "Areas",  # Data's subzones (data.md "Areas", 28.10.2026)
        "Crystal Lake",
        "Monsters",  # Data's block (guide gaps, 23.10.2026): no service, by level
        "Goldtooth  8",
        "Hogger  11",
        "Leprithus  18",  # the rare of the Helpers alert (A3.3)
    ]
    assert chips(wow) == []  # no facet chips on a page
    rows = page_entries(wow, DS)
    assert rows[4].ref == "npc:240" and rows[5].ref == "quest:62"  # the taker group is the NPC
    assert (
        rows[14].ref == "npc:295" and rows[20].ref == "zone:1436"
    )  # one row down: the auction house; one more: the quest givers; two: the zone's chains
    assert summary(wow) == ""
    # the sections are the registered ones: the ranking first, then by status, the places, the zone's
    # neighbours; Done folded (it has no rows here)
    ids = [s.id for s in wow.eval("Bastians:GetDetailSections('zone:1429')").values()]
    assert ids == [
        "quests.zone.todo",
        "quests.zone.turnin",
        "quests.zone.active",
        "quests.zone.onward",
        "quests.zone.chains",  # ADR 0055
        "data.people",  # "data.places" before 05.11.2026 (ADR 0054)
        "quests.zone.neighbours",
        "data.areas",  # the subzones (data.md "Areas", 28.10.2026)
        "data.monsters",  # guide gaps, 23.10.2026
        "quests.here.todo",  # the Here column's sections (C4), not drawn on the page
        "quests.here.log",
        "data.near",
    ]
    assert wow.eval("Bastians:GetAction('quests.open')") is None  # chains live on the quest page
    assert errors(wow) == []


def test_the_zone_sections_follow_the_quests_and_the_done_section_folds(wow: WowRuntime):
    boot(wow)
    open_view(wow, "/bq")
    wow.execute("Mock.completedQuests = { 783, 7, 18, 62 }; Mock.questLog[3] = nil")
    wow.fire("QUEST_TURNED_IN", 62, 300, 150)
    wow.fire("QUEST_LOG_UPDATE")
    wow.advance(0.3)
    wow.run_frames(5)
    texts = page_rows(wow, DS)
    assert not any(t.startswith("Hand in") for t in texts)
    assert "To take  1" in texts and "Done  1" in texts
    assert any("[9] The Jasperlode Mine" in t for t in texts)  # 76 is available now
    # the Done block is folded on the sheet (ADR 0054: what cannot be acted on opens on a click);
    # opened, the taker group and its quest show
    assert block_rows(wow, DS, "Done  1") == []
    wow.execute(
        f"""
        for _, bf in ipairs({DS}.blockPool) do
          if bf:IsShown() and bf.block and bf.block.id == "quests.zone.done" then
            bf.fold:Click("LeftButton")
          end
        end
        """
    )
    assert block_rows(wow, DS, "Done  1") == ["Marshal Dughan", "[7] The Fargodeep Mine  Chain 1/3"]
    assert errors(wow) == []


def test_zone_rows_lead_to_their_pages_and_bq_follows_the_player(wow: WowRuntime):
    boot(wow)
    open_view(wow, "/bq")
    # the Westfall row of Neighbours opens the Westfall page
    assert click_ref(wow, DS, "zone:1436") is True
    assert wow.eval("Bastians:GetService('views'):CurrentPage()") == "zone:1436"
    assert title(wow) == "Westfall"
    texts = page_rows(wow, DS)
    assert "Prerequisite elsewhere  1" in texts  # 11 waits for 76
    assert any("first: The Jasperlode Mine (Elwynn Forest)" in t for t in texts)
    assert "< Elwynn Forest  7-11" in texts
    # a quest row opens the quest page, an NPC row the NPC page
    assert click_ref(wow, DS, "quest:11") is True
    assert wow.eval("Bastians:GetService('views'):CurrentPage()") == "quest:11"
    assert title(wow) == "Riverpaw Gnoll Bounty"
    # /bq toggles the zone page of the zone the player stands in
    wow.slash("/bq")
    assert wow.eval("Bastians:GetService('views'):CurrentPage()") == "zone:1429"
    wow.slash("/bq")
    assert wow.eval(f"{WIN}.IsShown()") is False
    wow.execute("Mock.playerMap = 1436")
    wow.fire("ZONE_CHANGED_NEW_AREA")
    wow.fire("ZONE_CHANGED")
    wow.advance(0.5)
    wow.slash("/bq")
    assert wow.eval("Bastians:GetService('views'):CurrentPage()") == "zone:1436"
    assert errors(wow) == []


def test_the_quest_page_leads_to_its_chain(wow: WowRuntime):
    """ADR 0055: the chain is a subject of its own. A quest's page no longer lists it; its Chain
    button opens the chain's page, here in this window: the way as rows, then where it goes."""
    boot(wow)
    open_view(wow, "/bq 76")
    assert wow.eval("Bastians:GetService('views'):CurrentPage()") == "quest:76"
    b = band(wow, DS)
    assert (b["name"], b["summary"], b["status"]) == (
        "The Jasperlode Mine",
        "Level 9, Elwynn Forest",
        "Needs: The Fargodeep Mine  0 yd",
    )
    assert "Chain" not in page_rows(wow, DS)
    assert "Chain" in band_buttons(wow, DS)
    wow.execute(
        f"for _, x in pairs({DS}.buttons) do"
        " if x:IsShown() and x.label:GetText() == 'Chain' then x:Click() end end"
    )
    wow.run_frames(10)
    root = wow.eval("Bastians:GetModule('Quests').Logic.chainRoot(76)")
    assert wow.eval("Bastians:GetService('views'):CurrentPage()") == f"chain:{root}"
    assert band(wow, DS)["name"] == "The Fargodeep Mine"
    texts = page_rows(wow, DS)
    way = texts.index("The way")
    assert texts[way + 1 : way + 4] == [
        "1. The Fargodeep Mine",
        "2. The Jasperlode Mine",
        "3. Riverpaw Gnoll Bounty",
    ]
    assert "Where it goes" in texts
    open_view(wow, "/bq 176")
    assert "Chain" not in band_buttons(wow, DS)  # not part of a chain: no button
    assert errors(wow) == []


def test_log_view_lists_each_quest_on_two_lines(wow: WowRuntime):
    """ADR 0053: the name, then the one thing to know; nothing under a quest, no chain steps."""
    boot(wow)
    open_view(wow, "/bq log")
    assert title(wow) == "My quests"
    assert strip(wow.eval(f"{WIN}.bar.byId.zone:GetText()")) == "Elwynn Forest"
    assert summary(wow) == "2 in the log - 1 to hand in - 1 objectives here"
    assert flat(wow) == [
        "HAND IN, THIS ZONE  1",
        "[7] The Fargodeep Mine II  Done. Hand in to Marshal Dughan",  # the client's title wins
        "IN PROGRESS  1",
        "[11] The Fargodeep Mine  0/1 Explore the Fargodeep Mine",
    ]
    done, open_ = wow.eval(f"{WIN}.tree.flat[2]"), wow.eval(f"{WIN}.tree.flat[4]")
    kind = wow.eval("Bastians.UI.IconKind")
    assert kind(done.icon) == "done" and kind(open_.icon) == "questActive"  # done looks done
    assert strip(open_.title) == "[11] The Fargodeep Mine"
    assert strip(open_.meta) == "0/1 Explore the Fargodeep Mine"
    assert open_.children is None and done.worth is False and done.value is None
    # the nearest of the two known spots (player at 0.42, 0.65)
    assert (open_.target, open_.map, open_.x, open_.y) == ("objective", 1429, 0.40, 0.70)
    assert wow.eval(f"{WIN}.CurrentMap()") == 1429
    open_view(wow, "/bq active")  # the old name still works
    assert title(wow) == "My quests"
    assert errors(wow) == []


def test_a_click_on_a_quest_of_my_quests_opens_its_sheet(wow: WowRuntime):
    boot(wow)
    open_view(wow, "/bq log")
    wow.execute(f"{WIN}.tree.flat[4].onClick({WIN}.tree.flat[4], 'LeftButton')")
    assert wow.eval("BastiansQuestSheet:IsShown()") is True
    assert errors(wow) == []


def test_quest_item_bar_is_filled_out_of_combat_only(wow: WowRuntime):
    """The log view's usable quest items sit in a secure bar of their own beside the host window
    (ADR 0012: the host's tree holds no secure buttons); in combat nothing secure is touched."""
    boot(wow)
    wow.execute("Mock.questLog[2].item = { id = 2589, icon = 132889 }; Mock.bags[2589] = 1")
    open_view(wow, "/bq log")
    button = "BastiansQuestsItem1"
    assert wow.eval("BastiansQuestsItemBar:IsShown()") is True
    assert wow.eval(f"{button}:IsShown()") is True
    assert wow.eval(f"{button}:GetAttribute('item')") == "item:2589"
    assert wow.eval(f"{button}:GetAttribute('type')") == "item"
    assert wow.eval("BastiansQuestsItem2:IsShown()") is False  # one button per item
    # the item changes in combat: nothing secure is touched until combat ends
    wow.set_combat(True)
    wow.execute("Mock.questLog[2].item = { id = 1931, icon = 132889 }; Mock.bags[1931] = 1")
    wow.fire("BAG_UPDATE_DELAYED")
    wow.advance(0.2)
    assert wow.eval(f"{button}:GetAttribute('item')") == "item:2589"
    assert wow.eval(f"{WIN}.combatLocked") is True
    assert errors(wow) == []  # no ADDON_ACTION_BLOCKED
    wow.set_combat(False)
    assert wow.eval(f"{button}:GetAttribute('item')") == "item:1931"
    assert wow.eval(f"{WIN}.combatLocked") is False
    wow.execute("Mock.bags[1931] = 0")
    wow.fire("BAG_UPDATE_DELAYED")
    wow.advance(0.2)
    assert wow.eval("BastiansQuestsItemBar:IsShown()") is False  # not in the bags: no bar
    # a page: the bar goes away
    wow.execute("Mock.bags[1931] = 1")
    open_view(wow, "/bq log")
    assert wow.eval("BastiansQuestsItemBar:IsShown()") is True
    open_view(wow, "/bq zone")
    assert wow.eval("BastiansQuestsItemBar:IsShown()") is False
    assert errors(wow) == []


def test_all_view_builds_in_a_job_with_filters(wow: WowRuntime):
    boot(wow)
    wow.slash("/bq all")
    assert flat(wow) == ["Building the list ..."]
    wow.execute(SIZE)
    wow.run_frames(10)
    assert flat(wow) == ["ELWYNN FOREST  3  7-11", "WESTFALL  3  9-10"]  # zone sections, folded
    assert chips(wow) == ["Status: All"]  # one pill of the filter bar (ADR 0016)
    assert menu(wow, f"{WIN}.tree", "chips1") == [
        "All",
        "Available  1",  # the mage's errand (A3.1)
        "In log  2",
        "Blocked  2",
        "Not for this character  1",
    ]
    assert summary(wow).startswith("6 quests shown")
    wow.execute(f"{WIN}.tree:ToggleFold({WIN}.tree.flat[1])")
    assert flat(wow) == [
        "ELWYNN FOREST  3  7-11",
        "[7] The Fargodeep Mine  Chain 1/3",
        "[9] The Jasperlode Mine  Chain 2/3 - > Westfall",
        '[11] Wanted: "Hogger"  Group',
        "WESTFALL  3  9-10",
    ]
    pick(wow, f"{WIN}.tree", "chips1", "In log")
    wow.run_frames(10)
    assert [t for t in flat(wow) if "[" in t] == [
        "[7] The Fargodeep Mine  Chain 1/3",
        '[11] Wanted: "Hogger"  Group',
    ]
    pick(wow, f"{WIN}.tree", "chips1", "All")
    wow.run_frames(10)
    wow.execute("Bastians:GetModule('Quests').db.profile.allKind = 'Group'")
    wow.execute(f"{WIN}.Render()")
    wow.run_frames(10)
    assert summary(wow).startswith("1 quests shown")
    wow.execute("Bastians:GetModule('Quests').db.profile.allKind = 'any'")
    wow.execute("Bastians:GetModule('Quests').db.profile.allBand = '1-10'")
    wow.execute(f"{WIN}.Render()")
    wow.run_frames(10)
    assert summary(wow).startswith("5 quests shown")  # the mage's errand is level 10 (A3.1)
    assert errors(wow) == []


def test_search_filters_the_tree(wow: WowRuntime):
    boot(wow)
    open_view(wow, "/bq")
    wow.execute(f"{WIN}.search:SetText('hogger')")
    wow.execute(f"{WIN}.search:GetScript('OnTextChanged')({WIN}.search)")
    # the page keeps the blocks with a match: the quest and the monster
    assert block_titles(wow, DS) == ["IN PROGRESS  1", "MONSTERS"]
    assert block_rows(wow, DS, "In progress  1") == [
        "Marshal Dughan",
        '[11] Wanted: "Hogger"  Group  0/1 objectives',
    ]
    wow.execute(f"{WIN}.search:SetText('')")
    wow.execute(f"{WIN}.search:GetScript('OnTextChanged')({WIN}.search)")
    assert block_titles(wow, DS)[0] == "TO DO HERE  2"


def test_window_without_data_shows_the_client_log_only(wow: WowRuntime):
    boot(wow, CORE, QUESTS)
    open_view(wow, "/bq")
    assert band(wow, DS)["name"] == "zone:1429" and wow.eval(f"{DS}.blockCount") == 0
    assert summary(wow) == "No data for this entity. Is Bastian's Data installed and loaded?"
    open_view(wow, "/bq log")
    assert flat(wow) == [
        "ELSEWHERE  1",
        "Unknown place  1",
        "[7] The Fargodeep Mine  0/1 Explore the Fargodeep Mine",
        "COMPLETE, PLACE UNKNOWN  1",
        "[9] The Fargodeep Mine II  Done.",
    ]
    assert summary(wow) == "2 in the log - 0 to hand in - 0 objectives here"
    assert errors(wow) == []


def test_window_refreshes_on_quest_changes_and_hides_on_disable(wow: WowRuntime):
    boot(wow)
    open_view(wow, "/bq log")
    wow.execute(
        "Mock.questLog[2].objectives[1].numFulfilled = 1; Mock.questLog[2].objectives[1].finished = true"
    )
    wow.fire("QUEST_LOG_UPDATE")
    wow.advance(0.2)
    assert any("The Fargodeep Mine  1/" in t for t in flat(wow))  # its finished objective shows
    wow.execute("Bastians:GetModule('Quests'):Disable()")
    assert wow.eval(f"{WIN}.IsShown()") is False
    assert wow.eval(f"{WIN}.Open('zone')") is False
    wow.execute("Bastians:GetModule('Quests'):Enable()")
    assert wow.eval(f"{WIN}.Open('zone')") is True
    wow.execute("Mock.PressEscape()")
    assert wow.eval(f"{WIN}.IsShown()") is False
    assert wow.eval("BINDING_NAME_BASTIANS_QUESTS") == "Open Bastian's Quests"
    assert wow.eval(f"{WIN}.Open('chains')") is False  # no such view any more
    assert errors(wow) == []


def test_level_colour_follows_the_classic_rule(wow: WowRuntime):
    boot(wow, CORE, QUESTS)

    def color(level, player):
        return wow.eval(f"Bastians:GetModule('Quests').Rows.levelColor({level}, {player})")

    assert color(17, 12) == "|cffff3838"
    assert color(15, 12) == "|cffff8040"
    assert color(12, 12) == "|cffffff00"
    assert color(10, 12) == "|cffffff00"
    assert color(7, 12) == "|cff40c040"  # the green range at level 12 is 6 levels
    assert (
        color(5, 12) == "|cff888888"
    )  # the grey of the teal scheme (4.5:1 on the panel and on a tile over it)
    assert color("nil", 12) == "|cffffffff"
    assert wow.eval("Bastians:GetModule('Quests').Rows.greenRange(45)") == 10


def test_the_quest_page_starts_with_what_to_do(wow: WowRuntime):
    """ADR 0052: the first block, across the page, the task before the objectives; the story
    alone in Quest text; no stats strip, no worth filler, no level and zone in Overview."""
    boot(wow)
    wow.execute("Bastians:GetService('data'):LoadPack('text')")
    wow.run_frames(5)
    open_view(wow, "/bq 176")
    titles = block_titles(wow, DS)
    assert titles[:2] == ["WHAT TO DO", "GIVEN BY"]
    assert "OBJECTIVES" not in titles
    texts = page_rows(wow, DS)
    assert texts[:3] == [
        "What to do",
        "Bring Huge Gnoll Claw to Marshal Dughan in Goldshire.",
        "Explore the Fargodeep Mine  0/1",
    ]
    assert texts.count("Bring Huge Gnoll Claw to Marshal Dughan in Goldshire.") == 1  # said once
    assert not any(t.startswith("Zone:") or t == "Level" for t in texts)
    assert wow.eval(f"{DS}.data.card.noStats") is True
    assert errors(wow) == []


def test_objective_labels_lose_the_clients_count_only_when_we_print_one(wow: WowRuntime):
    boot(wow)
    label = "Bastians:GetModule('Quests').Rows.objectiveLabel"
    for text, required, want in [
        ("0/6 Shiny Junk", 6, "Shiny Junk"),
        ("Shiny Junk: 0/6", 6, "Shiny Junk"),
        ("Shiny Junk 0/6", 6, "Shiny Junk"),
        ("Explore the Mine", 1, "Explore the Mine"),
        ("0/6 Shiny Junk", 0, "0/6 Shiny Junk"),  # no count of ours: the client's stays
    ]:
        assert wow.eval(f"{label}({{ text = '{text}', required = {required} }})") == want


def test_a_quest_counts_its_one_objective_and_else_its_objectives(wow: WowRuntime):
    boot(wow)
    text = "Bastians:GetModule('Quests').Rows.progressText"
    assert wow.eval(f"{text}({{ objectives = {{ {{ fulfilled = 2, required = 6 }} }} }})") == "2/6"
    assert wow.eval(f"{text}({{ objectives = {{ {{ finished = false }} }} }})") == "0/1"
    both = "{ { finished = true, required = 8 }, { finished = false, required = 3 } }"
    assert wow.eval(f"{text}({{ objectives = {both} }})") == "1/2"
    assert wow.eval(f"{text}({{ objectives = {{}} }})") == ""
