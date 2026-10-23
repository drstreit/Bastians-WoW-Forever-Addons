"""Here (C4, ADR 0014; since ADR 0018 the first navigation entry and the list pane's default):
the player's zone as a dossier of the `here` sections (Do here, My quests here, Near, Best spot
here) in the list pane, the page in the detail pane beside it. Here follows zone changes and
quest events, the quest items of "My quests here" sit on the secure bar beside the window, out of
combat only; `/bq` opens the window on Here; the home lost its Here section."""

import re

from harness import WowRuntime
from pages import band, block_rows, block_title, block_titles, nav_active, nav_click

CORE, DATA, QUESTS, GOLD, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Gold",
    "Bastians_Browser",
)
MOD = "Bastians:GetModule('Browser')"
BR = f"{MOD}.Browser"
HD = f"{MOD}.hereDossier"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.execute('function GetRealmName() return "Classic Beta PvE" end')
    wow.start(*(addons or (CORE, DATA, QUESTS, GOLD, BROWSER)))
    wow.run_frames(10)
    wow.advance(0.3)  # the zone announcement after PLAYER_ENTERING_WORLD
    return wow


def strip(text: str | None) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def values(wow: WowRuntime, title: str) -> list[str]:
    """The value of a Here block's drawn rows: the value column, or the worth in gold on its own
    lines under a two-line row."""

    def value(f) -> str:
        if f.value.IsShown(f.value):
            return strip(f.value.GetText(f.value))
        if f.worth.IsShown(f.worth):
            return strip(f.worth.GetText(f.worth))
        return ""

    for bf in wow.eval(f"{HD}.blockPool").values():
        if bf.IsShown(bf) and block_title(bf, True) == title.upper():
            return [value(f) for f in bf.tree.pool.values() if f.IsShown(f)]
    return []


def test_here_fills_the_list_pane_beside_the_page(wow: WowRuntime):
    boot(wow)
    wow.slash("/bb npc:240")
    # three panes (ADR 0018): the navigation, the list (Here before any list), the detail
    assert wow.eval(f"{MOD}.nav:IsShown()") is True and wow.eval(f"{MOD}.nav:GetWidth()") == 180
    assert nav_active(wow) == "nav:here"
    assert wow.eval(f"{MOD}.listPane:GetWidth()") == wow.eval(f"{BR}.ListWidth()")
    assert wow.eval(f"select(2, {MOD}.splitter:GetPoint(1)) == {MOD}.listPane") is True
    assert wow.eval(f"select(2, {MOD}.detailPane:GetPoint(1)) == {MOD}.splitter") is True
    assert wow.eval(f"{MOD}.search:GetParent() == {MOD}.toolbar") is True
    assert band(wow, f"{MOD}.dossier")["name"] == "Marshal Dughan"
    assert wow.eval(f"{HD}:IsShown()") is True
    b = band(wow, HD)
    assert b["name"] == "Elwynn Forest" and b["summary"] == "Level 7-11, Eastern Kingdoms"
    assert wow.eval(f"{HD}.buttonCount") == 0  # no action buttons in the column
    titles = block_titles(wow, HD)
    assert titles[:2] == ["DO HERE  2", "MY QUESTS HERE  2"]
    assert titles[2:] == ["NEAR  3", "BEST SPOT HERE  2"]  # every Here block carries its count
    # Do here: the ranking, best first, the worth in the value column instead of "/min"
    todo = block_rows(wow, HD, "Do here  2")
    assert todo[0].startswith("[7] The Fargodeep Mine II") and " xp, " in todo[0]
    assert all(v for v in values(wow, "Do here  2"))  # every row has a worth line
    assert "/min" not in values(wow, "Do here  2")[0]
    # My quests here: the hand-in and the objective, nearest first, each with a distance
    log = block_rows(wow, HD, "My quests here  2")
    assert all(t.endswith("yd") or t.endswith("distance unknown") for t in log)
    assert sorted(t[:4] for t in log) == ["[11]", "[7] "]  # the objective and the hand-in
    # Near: the places by distance, the kind and the distance after the name
    near = block_rows(wow, HD, "Near")
    assert len(near) == 3 and len(block_rows(wow, HD, "Best spot here")) == 2
    assert near[0].startswith("Marshal Dughan") or "yd" in near[0]
    assert all(", " in t and t.endswith("yd") for t in near)
    assert all(wow.eval(f"{HD}.blockPool[{i + 1}].block.wide") for i in range(len(titles)))
    # the list's width: the minimum, a drag, remembered in the profile, never squeezing the page
    wow.execute(f"{BR}.SetListWidth(150)")
    assert wow.eval(f"{MOD}.listPane:GetWidth()") == 240
    wow.execute(f"{BR}.SetListWidth(300)")
    assert wow.eval(f"{MOD}.listPane:GetWidth()") == 300
    assert wow.eval(f"{MOD}.db.profile.listWidth") == 300
    wow.execute(f"{BR}.SetListWidth(2000)")
    width = wow.eval("BastiansBrowserFrame:GetWidth()")
    assert wow.eval(f"{MOD}.listPane:GetWidth()") == width - 16 - 188 - 300
    assert wow.errors == []


def test_the_here_column_follows_the_zone_and_the_quests(wow: WowRuntime):
    boot(wow)
    wow.slash("/bb npc:240")
    assert band(wow, HD)["name"] == "Elwynn Forest"
    wow.execute("Mock.playerMap = 1436")
    wow.fire("ZONE_CHANGED_NEW_AREA")
    wow.advance(0.5)
    assert band(wow, HD)["name"] == "Westfall"
    assert "DO HERE  2" not in block_titles(wow, HD)
    # a quest event re-renders the column (coalesced): the hand-in moves to the objective
    wow.execute("Mock.playerMap = 1429")
    wow.fire("ZONE_CHANGED_NEW_AREA")
    wow.advance(0.5)
    before = block_rows(wow, HD, "My quests here  2")
    wow.execute("Mock.completedQuests = { 783, 7, 18, 62 }; Mock.questLog[3] = nil")
    wow.fire("QUEST_TURNED_IN", 62, 300, 150)
    wow.fire("QUEST_LOG_UPDATE")
    wow.advance(0.5)
    wow.run_frames(5)
    after = block_rows(wow, HD, "My quests here  1")
    assert len(before) == 2 and len(after) == 1 and after[0] in before
    assert wow.errors == []


def test_the_quest_item_bar_sits_beside_the_window_out_of_combat_only(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.questLog[2].item = { id = 2589, icon = 132889 }; Mock.bags[2589] = 1")
    wow.fire("BAG_UPDATE_DELAYED")
    wow.advance(0.3)
    wow.slash("/bq")
    wow.run_frames(5)
    wow.advance(0.3)
    assert wow.eval("BastiansBrowserFrame:IsShown()") is True
    assert wow.eval("BastiansQuestsItemBar:IsShown()") is True
    assert wow.eval("BastiansQuestsItem1:GetAttribute('item')") == "item:2589"
    assert (
        wow.eval("select(2, BastiansQuestsItemBar:GetPoint(1)) == UIParent") is True
    )  # never the host
    # in combat nothing secure moves: the wish waits for PLAYER_REGEN_ENABLED
    wow.set_combat(True)
    wow.execute(f"{BR}.Render()")
    assert wow.eval("Bastians:GetModule('Quests').Window.combatLocked") is True
    assert wow.errors == []  # no ADDON_ACTION_BLOCKED
    wow.set_combat(False)
    assert wow.eval("Bastians:GetModule('Quests').Window.combatLocked") is False
    # the window hides: the bar goes with it
    wow.execute("BastiansBrowserFrame:Hide()")
    assert wow.eval("BastiansQuestsItemBar:IsShown()") is False
    assert wow.errors == []


def test_bq_opens_the_window_on_here_and_toggles_it(wow: WowRuntime):
    boot(wow)
    wow.slash("/bq")
    assert wow.eval("BastiansBrowserFrame:IsShown()") is True
    assert wow.eval(f"{BR}.Current().kind") == "here"
    assert band(wow, HD)["name"] == "Elwynn Forest"
    assert wow.eval("Bastians:GetModule('Quests').Window.IsShown()") is True
    wow.slash("/bq")
    assert wow.eval("BastiansBrowserFrame:IsShown()") is False
    wow.slash("/bb item:2589")
    wow.execute("BastiansBrowserFrame:Hide()")
    wow.slash("/bq")  # opens what was open: the page, beside Here
    assert wow.eval(f"{BR}.Current().ref") == "item:2589"
    assert wow.eval(f"{HD}:IsShown()") is True
    wow.slash("/bq 76")
    assert wow.eval(f"{BR}.Current().ref") == "quest:76"
    wow.slash("/bq log")
    assert wow.eval(f"{BR}.Current().kind") == "view"
    assert wow.eval(f"{HD}:IsShown()") is False  # the log fills the list pane now ...
    nav_click(wow, "nav:here")  # ... and Here is one click away in the navigation
    assert wow.eval(f"{HD}:IsShown()") is True
    assert band(wow, f"{MOD}.dossier")["name"] == "The Jasperlode Mine"  # the page kept
    assert wow.errors == []


def test_the_home_lost_its_here_section(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{BR}.Home()")
    kinds = [(r.kind, strip(r.text)) for r in wow.eval(f"{MOD}.tree.flat").values()]
    assert kinds[0] == ("section", "Quests")  # the views first, no "Here" section
    assert not any(t == "Here" for _, t in kinds)
    assert wow.errors == []


def test_here_quest_rows_take_two_lines(wow: WowRuntime):
    """R2: quest
    rows in the Here column draw the name on one line and the chain, xp and reward on the next,
    the worth right of the meta; the Near rows stay one line."""
    boot(wow)
    wow.slash("/bb npc:240")
    wow.run_frames(5)
    for bf in wow.eval(f"{HD}.blockPool").values():
        if not bf.IsShown(bf):
            continue
        title = block_title(bf, False)
        frames = [f for f in bf.tree.pool.values() if f.IsShown(f)]
        if title in ("DO HERE", "MY QUESTS HERE"):
            assert frames and all(f.twoLine is True for f in frames), title
            assert all(strip(f.meta.GetText(f.meta)) for f in frames)  # chain, xp, minutes
            assert not any("xp" in strip(f.text.GetText(f.text)) for f in frames)  # the name alone
            # the worth on one or two lines of its own under the meta, never in the value column
            # over the icons
            for f in frames:
                # a row's own value (a distance) stays in the value column; a worth never does
                assert not (f.value.IsShown(f.value) and f.worth.IsShown(f.worth))
                if f.worth.IsShown(f.worth):
                    assert f.GetHeight(f) in (34 + 12 + 2, 34 + 24 + 2)
                else:
                    assert f.GetHeight(f) == 34
            if title == "DO HERE":
                assert any(f.worth.IsShown(f.worth) for f in frames)
        elif title == "NEAR":
            assert frames and all(not f.twoLine for f in frames)
    # the Browser's setting turns the worth off: plain two-line rows
    wow.execute("Bastians:GetModule('Browser').db.profile.showWorth = false")
    wow.execute("Bastians:Fire('BASTIANS_SETTING_CHANGED', 'Browser', 'showWorth', false)")
    wow.advance(0.3)
    wow.run_frames(5)
    for bf in wow.eval(f"{HD}.blockPool").values():
        if bf.IsShown(bf) and block_title(bf, False) == "DO HERE":
            frames = [f for f in bf.tree.pool.values() if f.IsShown(f)]
            assert frames and all(f.GetHeight(f) == 34 for f in frames)
            assert not any(f.worth.IsShown(f.worth) for f in frames)
    assert wow.errors == []


def test_a_hidden_quest_leaves_do_here_for_the_folded_hidden_block(wow: WowRuntime):
    """R3: the hide icon moves a quest from Do here into a "Hidden"
    block folded to its "+N more" row; expanded, the row is greyed and tagged; the icon unhides."""
    boot(wow)
    wow.slash("/bb npc:240")
    wow.run_frames(5)
    todo = block_rows(wow, HD, "Do here  2")
    assert len(todo) == 2 and "HIDDEN" not in block_titles(wow, HD)
    hidden_ref = next(
        r.ref
        for bf in wow.eval(f"{HD}.blockPool").values()
        if bf.IsShown(bf) and block_title(bf, False) == "DO HERE"
        for r in bf.tree.flat.values()
    )
    wow.execute(f"Bastians:RunAction('quests.hide', '{hidden_ref}', {{ source = 'test' }})")
    wow.advance(0.3)
    wow.run_frames(5)
    assert len(block_rows(wow, HD, "Do here  1")) == 1
    assert block_rows(wow, HD, "Hidden  1") == ["+1 more"]  # folded
    wow.execute(f"{HD}:Expand('quests.here.hidden')")
    wow.run_frames(2)
    rows = block_rows(wow, HD, "Hidden  1")
    assert len(rows) == 1 and "+1 more" not in rows
    drawn = [
        strip(f.text.GetText(f.text))
        for bf in wow.eval(f"{HD}.blockPool").values()
        if bf.IsShown(bf) and block_title(bf, False) == "HIDDEN"
        for f in bf.tree.pool.values()
        if f.IsShown(f)
    ]
    assert drawn and all("(hidden)" in t for t in drawn)
    wow.execute(f"Bastians:RunAction('quests.hide', '{hidden_ref}', {{ source = 'test' }})")
    wow.advance(0.3)
    wow.run_frames(5)
    assert len(block_rows(wow, HD, "Do here  2")) == 2 and "HIDDEN  1" not in block_titles(wow, HD)
    assert wow.errors == []
