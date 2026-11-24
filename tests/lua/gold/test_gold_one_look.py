"""Gold in the one look (ADR 0084, W9 of plan-suite-waves.md; gold.md "The one look"): the five
views as the head's tabs, the line of what is shown, quiet section headings, a bag's row on two
lines, the hint in a foot. The numbers are the suite's board's."""

import re

from harness import WowRuntime

CORE, DATA, GOLD = "Bastians_Core", "Bastians_Data", "Bastians_Gold"
MOD = "Bastians:GetModule('Gold')"
WIN = f"{MOD}.Window"
S = "Bastians.UI.Style"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.execute('function GetRealmName() return "Classic Beta PvE" end')
    wow.start(*(addons or (CORE, DATA, GOLD)))
    wow.run_frames(10)
    return wow


def strip(text: str | None) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def size(wow: WowRuntime, width: int = 520) -> None:
    """The mock gives anchors no size: the window, its head and the rows' view by hand."""
    wow.execute(
        f"local w = {WIN}.win; w.frame:SetWidth({width}); w.head:SetWidth({width} - 2);"
        f" w.content:SetWidth({width} - 2); w.headBar:Layout();"
        f" {WIN}.tree.scroll:SetSize({width} - 28, 300); {WIN}.tree:Refresh()"
    )


def test_the_five_views_are_the_heads_tabs(wow: WowRuntime):
    boot(wow)
    wow.slash("/bgold")
    win, tabs = f"{WIN}.win", f"{WIN}.tabs.tabs"
    assert wow.eval(f"{win}.headKind") == "tall" and wow.eval(f"{win}.title:GetText()") == "Gold"
    words = [p.item.word for p in wow.eval(f"{tabs}.parts").values()]
    assert words == ["Today", "Farm spots", "Price", "Bags", "Ledger"]
    assert wow.eval(f"{tabs}.spec.value") == "today"
    # every tab says what it shows, and keeps its pictogram for a row too narrow for words
    assert wow.eval(f"{tabs}:Part('bags').tip") == "What to sell, post or keep from your bags."
    assert wow.eval(f"{tabs}:Part('today').item.glyph") == "gold"
    # a wide head carries them; the line of what is shown stands 8 under it, in the text size 13
    size(wow, 1100)
    assert wow.eval(f"{WIN}.tabs.row") is False and wow.eval(f"{WIN}.tabs:Room()") == 0
    assert tuple(wow.eval(f"{{ {WIN}.summary:GetPoint(1) }}").values())[3:] == (15, -8)
    assert tuple(wow.eval(f"{WIN}.summary:GetFont()"))[1] == 13
    # a head too narrow for them: the tabs take a row under it; the line moves under that row
    size(wow, 420)
    assert wow.eval(f"{WIN}.tabs.row") is True and wow.eval(f"{WIN}.tabs:Room()") == 38
    assert tuple(wow.eval(f"{{ {WIN}.summary:GetPoint(1) }}").values())[3:] == (15, -46)
    # a tab is its view
    wow.execute(f"{tabs}:Part('ledger'):Click()")
    wow.run_frames(5)
    assert wow.eval(f"{MOD}.db.profile.view") == "ledger"
    assert wow.eval(f"{tabs}.spec.value") == "ledger"
    wow.slash("/bgold bags")
    assert wow.eval(f"{tabs}.spec.value") == "bags"
    # the foot: the hint on the band's ground, the rows end on it
    assert wow.eval(f"{WIN}.hint:GetHeight()") == 34
    assert wow.eval(f"{WIN}.hint:GetText()") == "Right click a line for its entity menu."
    assert wow.eval(f"select(2, {WIN}.tree.scroll:GetPoint(2)) == {WIN}.hint") is True
    assert wow.errors == []


def test_a_bags_row_takes_two_lines_under_quiet_headings(wow: WowRuntime):
    """The windows probe, 23.11.2026: every row of Bags needed about 400 units of 256 for the
    item and its reason on one line. The item stands on the first line, the reason under it."""
    boot(wow)
    wow.execute(
        "Mock.items[7073] = { name = 'Broken Fang', quality = 0, level = 1, class = 'Junk', sell = 7,"
        " stack = 5, icon = 133712 };"
        " Mock.bagSlots[0] = { [3] = { itemID = 7073, count = 2 },"
        " [5] = { itemID = 6948, count = 1, bound = true } }"
    )
    wow.slash("/bgold bags")
    size(wow)
    tree = f"{WIN}.tree"
    assert (
        wow.eval(f"{tree}.opts.twoLine") is True and wow.eval(f"{tree}.opts.capsSections") is True
    )
    flat = list(wow.eval(f"{tree}.flat").values())
    assert flat[0].kind == "section" and flat[0].title == "Sell to a vendor, the vendor pays"
    assert flat[1].title == "Broken Fang x2" and strip(flat[1].meta) == "grey, the vendor pays 7c"
    assert (
        strip(flat[1].text) == "Broken Fang x2  grey, the vendor pays 7c"
    )  # what the search reads
    # drawn: the heading in small capitals, 24 high; the row 34 with the reason on its second line
    dim = wow.eval(f"{S}.H.dim")
    assert wow.eval(f"{tree}.pool[1].text:GetText()") == f"{dim}sell to a vendor, the vendor pays|r"
    assert wow.eval(f"{tree}.heights[1]") == 24 and wow.eval(f"{tree}.heights[2]") == 34
    # no worth line under the reason: the reason says the prices already, and a third line of
    # "price unknown" made every row 52 high (seen on the review board's sketch, 24.11.2026)
    assert all(r.worth is False for r in flat if r.title and r.kind != "section")
    assert wow.eval(f"{tree}.pool[2].text:GetText()") == "Broken Fang x2"
    assert strip(wow.eval(f"{tree}.pool[2].meta:GetText()")) == "grey, the vendor pays 7c"
    assert wow.errors == []


def test_todays_headings_carry_their_counts(wow: WowRuntime):
    boot(wow)
    wow.slash("/bgold")
    size(wow)
    flat = list(wow.eval(f"{WIN}.tree.flat").values())
    sections = [r for r in flat if r.kind == "section"]
    assert sections and sections[0].title == "Income, gold per day"
    assert all(r.title for r in sections)
    assert wow.errors == []


def test_gold_works_with_core_alone(wow: WowRuntime):
    """W9's gate (ADR 0083): the app loads and works with Core alone: no Data, no other app."""
    boot(wow, CORE, GOLD)
    assert wow.eval(f"{MOD}:IsEnabled()") is True
    for view in ("today", "spots", "bags", "ledger"):  # Price opens from an item
        wow.slash(f"/bgold {view}")
        wow.run_frames(5)
        assert wow.eval(f"{WIN}.IsShown()") is True
        assert wow.eval(f"{WIN}.tabs.tabs.spec.value") == view
    assert wow.errors == []
