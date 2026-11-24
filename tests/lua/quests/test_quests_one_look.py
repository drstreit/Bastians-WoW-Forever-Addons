"""Quests in the one look (ADR 0084, W9 of plan-suite-waves.md; quests.md "The one look"): the
tracker with Lock as its head's tool, the view's controls in a band, quiet section headings and
the summary in a foot; Quests' own window with the views as the head's tabs and one band for the
search, the controls and the status chips. The numbers are the suite's board's."""

import re

from harness import WowRuntime

CORE, DATA, QUESTS, ROUTE = "Bastians_Core", "Bastians_Data", "Bastians_Quests", "Bastians_Route"
MOD = "Bastians:GetModule('Quests')"
TRACKER = f"{MOD}.Tracker"
WIN = f"{MOD}.Window"
S = "Bastians.UI.Style"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, QUESTS)))
    wow.run_frames(10)
    wow.advance(0.3)
    wow.fire("QUEST_LOG_UPDATE")
    wow.run_frames(5)
    wow.advance(0.2)
    return wow


def strip(text: str) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def part_left(wow: WowRuntime, part: str) -> tuple[float, float]:
    point = tuple(wow.eval(f"{part}:GetPoint(1)"))
    return point[3], -point[4]


def test_the_tracker_wears_the_low_head_with_lock_as_its_tool(wow: WowRuntime):
    boot(wow)
    win = f"{TRACKER}.win"
    assert wow.eval(f"{win}.headKind") == "low" and wow.eval(f"{win}.head:GetHeight()") == 30
    assert wow.eval(f"{win}.title:GetText()") == "my quests"  # small capitals
    # a fresh frame is the board's width, so the band stands on one row
    assert tuple(wow.eval(f"{{ {win}.frame:GetSize() }}").values()) == (344, 420)
    lock = f"{TRACKER}.lock"
    # a tool of the low head: words in an outline, 22 high, the small text
    assert wow.eval(f"{lock}.spec.boxed") is True and wow.eval(f"{lock}:GetHeight()") == 22
    assert wow.eval(f"{lock}.label:GetText()") == "Lock" and wow.eval(f"{lock}.spec.icon") is None
    assert tuple(wow.eval(f"{lock}.label:GetFont()"))[1] == 11
    # locked: the word says so in the accent, and the bar is laid out for the longer word
    before = wow.eval(f"{lock}:GetWidth()")
    wow.execute(f"{lock}:Click()")
    assert wow.eval(f"{lock}.label:GetText()") == "Locked" and wow.eval(f"{lock}.spec.on") is True
    assert wow.eval(f"{lock}:GetWidth()") > before
    assert wow.eval(f"select(2, {lock}:GetPoint(1)) == {win}.options") is True
    assert wow.errors == []


def test_the_trackers_controls_stand_in_a_band_under_the_head(wow: WowRuntime):
    boot(wow, CORE, DATA, QUESTS, ROUTE)
    bar = f"{TRACKER}.bar"
    assert wow.eval(f"select(2, {bar}.frame:GetPoint(1)) == {TRACKER}.win.content") is True
    # the zone as the band's label, then Hide done, Tracked and the quest round at the row's end
    assert wow.eval(f"{bar}.band.labels[1]:GetText()") == "elwynn forest"
    order = [
        wow.eval(f"{bar}.byId.{k}.label:GetText()")
        for k in ("logHideDone", "logTrackedOnly", "round")
    ]
    assert order == ["Hide done", "Tracked", "Quest round"]
    widths = {}
    for width in (344, 300, 220):
        wow.execute(f"{bar}:Layout({width})")
        widths[width] = wow.eval(f"{bar}:Height()")
        xs = [part_left(wow, f"{bar}.byId.{k}") for k in ("logHideDone", "logTrackedOnly", "round")]
        assert xs == sorted(xs, key=lambda p: (p[1], p[0]))  # left to right, row by row
        last = f"{bar}.byId.round"
        assert part_left(wow, last)[0] + wow.eval(f"{last}:GetWidth()") <= width - 15
    assert widths == {344: 41, 300: 71, 220: 101}  # one row at the board's width
    # Hide done is a chip that is filled while on; a click flips the setting and draws it again
    wow.execute(f"{bar}:Layout(344)")
    assert wow.eval(f"{bar}.byId.logHideDone.spec.on") is None
    wow.execute(f"{bar}.byId.logHideDone:Click()")
    wow.run_frames(5)
    assert wow.eval(f"{MOD}.db.profile.logHideDone") is True
    assert wow.eval(f"{bar}.byId.logHideDone.spec.on") is True
    assert wow.eval(f"{bar}.byId.round.spec.on") is None  # the round is a quiet chip, never on
    # without Route there is no quest round to offer
    assert wow.errors == []


def test_the_tracker_without_route_offers_no_round(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f"{TRACKER}.bar.byId.round") is None
    assert wow.eval(f"{TRACKER}.bar.byId.logHideDone:IsShown()") is True
    assert wow.errors == []


def test_the_trackers_headings_rows_and_foot(wow: WowRuntime):
    boot(wow)
    tree = f"{TRACKER}.tree"
    wow.execute(f"{tree}.scroll:SetSize(300, 400); {tree}:Refresh()")
    assert wow.eval(f"{tree}.opts.capsSections") is True
    # a heading: small capitals, the count in the accent, 24 high; a quest's two lines 34
    dim, accent = wow.eval(f"{S}.H.dim"), wow.eval(f"{S}.H.accent")
    assert wow.eval(f"{tree}.pool[1].text:GetText()") == f"{dim}hand in, this zone|r  {accent}1|r"
    assert wow.eval(f"{tree}.heights[1]") == 24 and wow.eval(f"{tree}.heights[2]") == 34
    # under "hand in" a done quest's line is who takes it, not "Done. Hand in to ..."
    assert strip(wow.eval(f"{tree}.flat[2].meta")) == "Marshal Dughan"
    # the foot: the summary on the band's ground, the rows end on it
    foot = f"{TRACKER}.summary"
    assert wow.eval(f"{foot}:GetHeight()") == 34
    assert strip(wow.eval(f"{foot}:GetText()")) == "2 in the log - 1 to hand in - 1 objectives here"
    assert wow.eval(f"select(2, {tree}.scroll:GetPoint(2)) == {foot}") is True
    assert wow.errors == []


def test_the_here_column_keeps_the_whole_hand_in_sentence(wow: WowRuntime):
    """ "My quests here" is one list without the view's headings: its done quest says what to do."""
    boot(wow)
    rows = wow.eval(
        "(function() for _, s in ipairs(Bastians:GetDetailSections('zone:1429', { here = true })) do"
        " if s.id == 'quests.here.log' then return s.rows end end end)()"
    )
    metas = [strip(r.meta) for r in rows.values()]
    assert "Done. Hand in to Marshal Dughan" in metas
    assert wow.errors == []


def test_quests_own_window_has_the_views_as_tabs_and_one_band(wow: WowRuntime):
    boot(wow)
    wow.slash("/bq all")
    wow.execute(f"{WIN}.tree.scroll:SetSize(500, 400); {WIN}.tree:Refresh()")
    wow.run_frames(10)
    win, bar = f"{WIN}.win", f"{WIN}.bar"
    assert wow.eval(f"{win}.headKind") == "tall" and wow.eval(f"{win}.title:GetText()") == "Quests"
    # the four views as the head's tabs, the shown one filled
    tabs = f"{WIN}.tabs.tabs"
    words = [p.item.word for p in wow.eval(f"{tabs}.parts").values()]
    assert words == ["My quests", "All quests", "Attunements", "Class quests"]
    assert wow.eval(f"{tabs}.spec.value") == "quests.all"
    # the band: the search first, the selects as tools with an arrow, load texts at the row's end
    assert wow.eval(f"{WIN}.search == {bar}.search") is True
    wow.execute(f"{bar}:Layout(560)")
    assert part_left(wow, f"{bar}.search") == (15, 10)
    kind, band_, texts = (f"{bar}.byId.{k}" for k in ("kind", "band", "texts"))
    assert wow.eval(f"{kind}.label:GetText()") == "Any type" and wow.eval(f"{kind}.arrow:IsShown()")
    assert wow.eval(f"{band_}.label:GetText()") == "Any level"
    assert part_left(wow, texts)[0] + wow.eval(f"{texts}:GetWidth()") == 560 - 15
    # the status chips on a row of their own in the same band, after their label
    host = f"{WIN}.tree.filterBar.frame:GetParent()"
    assert wow.eval(f"{host}:GetParent() == {bar}.frame") is True and wow.eval(f"{host}:IsShown()")
    assert part_left(wow, host)[1] == 10 + 30
    assert wow.eval(f"{bar}.band.labels[1]:GetText()") == "status"
    assert wow.eval(f"{bar}:Height()") == 10 + 22 + 8 + 22 + 9
    # the line under the band says what is shown, in the text size 13
    assert strip(wow.eval(f"{WIN}.summary:GetText()")).startswith("6 quests shown")
    assert tuple(wow.eval(f"{WIN}.summary:GetFont()"))[1] == 13
    # a tab is its view
    wow.execute(f"{tabs}.parts[3]:Click()")
    wow.run_frames(10)
    assert wow.eval(f"{tabs}.spec.value") == "quests.attune"
    assert wow.eval(f"{host}:IsShown()") is False  # no status chips there: the band is one row
    assert wow.eval(f"{bar}:Height()") == 41
    # a page is no view: its name in the head, no tab filled, the band keeps the search
    wow.slash("/bq 176")
    wow.run_frames(10)
    assert strip(wow.eval(f"{win}.title:GetText()")) == 'Wanted: "Hogger"'
    assert wow.eval(f"{tabs}.spec.value") is None
    assert wow.eval(f"{bar}:Height()") == 41
    assert wow.errors == []


def test_quests_works_with_core_alone(wow: WowRuntime):
    """W9's gate (ADR 0083): the app loads and works with Core alone: no Data, no other app."""
    wow.start(CORE, QUESTS)
    wow.run_frames(10)
    wow.advance(0.3)
    wow.fire("QUEST_LOG_UPDATE")
    wow.run_frames(5)
    wow.advance(0.2)
    assert wow.eval(f"{MOD}:IsEnabled()") is True
    # the tracker shows the client's log, its band and its foot
    assert wow.eval(f"{TRACKER}.IsShown()") is True
    assert strip(wow.eval(f"{TRACKER}.summary:GetText()")).startswith("2 in the log")
    assert wow.eval(f"{TRACKER}.bar.byId.logHideDone:IsShown()") is True
    # the window opens every view
    for view in ("log", "all", "attune", "class"):
        wow.slash(f"/bq {view}")
        wow.run_frames(10)
        assert wow.eval(f"{WIN}.tabs.tabs.spec.value") == f"quests.{view}"
    assert wow.errors == []
