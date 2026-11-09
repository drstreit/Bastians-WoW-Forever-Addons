"""Stat tiles (ADR 0058, PH4): four tiles above the rows on Here, on Gold's Overview and on
Characters; a figure nobody knows says unknown in dim ink; a tile with a thing behind it opens
it; the other tabs show none."""

import re

from harness import WowRuntime
from pages import nav_click, rail_click, tab_rows

CORE, DATA, QUESTS, GOLD, ALTS, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Gold",
    "Bastians_Alts",
    "Bastians_Browser",
)
MOD = "Bastians:GetModule('Browser')"
BR = f"{MOD}.Browser"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, QUESTS, GOLD, ALTS, BROWSER)))
    wow.run_frames(10)
    wow.advance(0.3)
    return wow


def strip(text: str | None) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    return re.sub(r"\|c[0-9a-fA-F]{8}", "", text).replace("|r", "")


def tiles(wow: WowRuntime) -> list[tuple[str, str, str]]:
    """The shown stat tiles as (label, value, note)."""
    wow.execute(
        f"Tiles = {{}} for _, t in ipairs({MOD}.stats.tiles) do if t:IsShown() then "
        "Tiles[#Tiles + 1] = { t.label:GetText() or '', t.value:GetText() or '', t.note:GetText() or '' } end end"
    )
    return [(strip(r[1]), strip(r[2]), strip(r[3])) for r in wow.eval("Tiles").values()]


def test_here_shows_the_tiles_and_an_unknown_figure_says_so(wow: WowRuntime):
    boot(wow)
    # a tile whose owner knows nothing yet: it says so, never 0
    wow.execute(
        f"""Bastians:RegisterStat({MOD}, {{ id = "test.stat", rail = "here", order = 35, title = "Test",
          build = function() return {{ value = nil, note = "no market" }} end }})"""
    )
    wow.execute(f"{BR}.OpenWindow()")
    rows = tiles(wow)
    assert [r[0] for r in rows[:3]] == ["To do here", "Hand in", "Lands for you"]
    assert rows[0][1].isdigit() and rows[1][1].isdigit()
    assert rows[2][1].isdigit() and rows[2][2] == "at your level"
    assert rows[3] == ("Test", "unknown", "no market") and len(rows) == 4  # four at most
    stat_h = wow.eval("Bastians.UI.Style.STAT_H")
    assert wow.eval(f"{MOD}.stats:GetHeight()") == stat_h + 8
    assert wow.eval(f"{MOD}.stats.rail") == "here" and wow.eval(f"{MOD}.stats.count") == 4
    dim = wow.eval("Bastians.UI.Style.C.dim")
    assert list(wow.eval(f"{{ {MOD}.stats.tiles[4].value:GetTextColor() }}").values())[:3] == [
        dim[1],
        dim[2],
        dim[3],
    ]
    # the tiles stand in one row of equal widths above the rows
    widths = [wow.eval(f"{MOD}.stats.tiles[{i}]:GetWidth()") for i in range(1, 5)]
    assert len(set(widths)) == 1 and widths[0] >= 60
    assert wow.eval(f"select(2, {MOD}.hereDossier.frame:GetPoint(1)) == {MOD}.stats") is True
    # a tile with a list behind it opens it; Zones is World's first tab and has no tiles of its own
    wow.execute(f"{MOD}.stats.tiles[3]:Click()")
    wow.run_frames(5)
    assert wow.eval(f"{BR}.Current().kind") == "list" and wow.eval(f"{BR}.Current().type") == "zone"
    assert tiles(wow) == [] and wow.eval(f"{MOD}.stats:GetHeight()") == 4
    assert wow.eval(f"select(2, {MOD}.tree.chips:GetPoint(1)) == {MOD}.stats") is True
    assert wow.errors == []


def test_golds_overview_and_characters_carry_their_figures(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{BR}.OpenWindow()")
    rail_click(wow, "gold")
    wow.run_frames(10)
    if wow.client == "retail":
        # Gold ships for Forever only (ADR 0022): the entry reads Items and shows no tiles
        assert wow.eval(f"{BR}.Current().kind") == "list" and tiles(wow) == []
        return
    # Gold's Overview is the section's first tab (RegisterView `first`), a view of Gold's
    assert (
        wow.eval(f"{BR}.Current().kind") == "view"
        and wow.eval(f"{BR}.Current().id") == "gold.overview"
    )
    assert tab_rows(wow)[0] == ("nav:view:gold.overview", "Overview", True)
    rows = tiles(wow)
    assert [r[0] for r in rows] == ["Gold on hand", "Income", "Spent", "Last 7 days"]
    assert rows[0][1] == strip(wow.eval("Bastians.UI.Money(GetMoney())"))
    assert rows[1][2].startswith("Today: ") and rows[2][2] == "Today"
    texts = [strip(r.text) for r in wow.eval(f"{MOD}.tree.flat").values()]
    assert texts and texts[0].startswith("INCOME")
    # the other tabs of the section show no tiles
    nav_click(wow, "nav:list:item")
    wow.run_frames(5)
    assert tiles(wow) == []
    # Characters: Alts' four
    rail_click(wow, "characters")
    wow.run_frames(5)
    assert wow.eval(f"{BR}.Current().type") == "character"
    rows = tiles(wow)
    assert [r[0] for r in rows] == ["Characters", "Gold on all", "Highest level", "Dungeon runs"]
    assert rows[0][1].isdigit() and rows[3][1].isdigit()
    if rows[0][1] != "0":
        assert rows[2][1].isdigit() and rows[2][2] != ""  # the highest character's name
    assert wow.errors == []


def test_without_gold_and_alts_here_keeps_the_quests_tiles(wow: WowRuntime):
    boot(wow, CORE, DATA, QUESTS, BROWSER)
    wow.execute(f"{BR}.OpenWindow()")
    assert [r[0] for r in tiles(wow)] == ["To do here", "Hand in", "Lands for you"]
    # the Quests addon off: its tiles go, the Browser's stays
    wow.execute("Bastians:GetModule('Quests'):Disable()")
    wow.advance(0.3)
    wow.run_frames(5)
    assert [r[0] for r in tiles(wow)] == ["Lands for you"]
    assert wow.errors == []
