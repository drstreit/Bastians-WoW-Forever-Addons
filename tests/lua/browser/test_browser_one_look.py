"""The Browser in the one look (ADR 0084, W9 of plan-suite-waves.md; browser.md "The one look"):
the seven sections as the head's tabs, the search after them and Dock as the head's tool, and
under the head one band with Back, Forward, the section's lists as chips and the list's filter
chips. The numbers are the suite's board's (the figure "browser")."""

from harness import WowRuntime
from pages import nav_click, rail_click, rail_rows, tab_rows

CORE, DATA, QUESTS, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Browser",
)
MOD = "Bastians:GetModule('Browser')"
BR = f"{MOD}.Browser"
HEAD = f"{MOD}.head"
TABS = f"{HEAD}.tabs"
BAND = f"{MOD}.band"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, QUESTS, BROWSER)))
    wow.run_frames(10)
    wow.advance(0.3)
    return wow


def size(wow: WowRuntime, width: int) -> None:
    """The mock gives anchors no size: the window, its head and its content by hand."""
    wow.execute(
        f"local w = {MOD}.win; w.frame:SetWidth({width}); w.head:SetWidth({width} - 2);"
        f" w.content:SetWidth({width} - 2); w.opts.onResize(w, false)"
    )
    wow.run_frames(3)


def test_the_seven_sections_are_the_heads_tabs(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{BR}.OpenWindow()")
    win = f"{MOD}.win"
    assert wow.eval(f"{win}.headKind") == "tall" and wow.eval(f"{win}.headBar == {HEAD}") is True
    words = [p.item.word for p in wow.eval(f"{TABS}.parts").values()]
    assert words == ["Here", "Quests", "World", "Dungeons", "Items", "Characters", "More"]
    assert wow.eval(f"{TABS}.spec.value") == "here"
    assert wow.eval(f"{TABS}:Part('here').item.glyph") == "zone"  # kept for a row too narrow
    # a wide head carries them, the search after them and Dock before the window's pictograms
    size(wow, 1100)
    assert wow.eval(f"{HEAD}.row") is False and wow.eval(f"{HEAD}:Room()") == 0
    assert wow.eval(f"{TABS}:GetParent() == {win}.head") is True
    assert wow.eval(f"{HEAD}.tools.dock == {MOD}.toolbar.dock") is True
    assert wow.eval(f"select(2, {MOD}.toolbar.dock:GetPoint(1)) == {win}.options") is True
    assert wow.eval(f"{MOD}.toolbar.dock:GetHeight()") == 28
    assert wow.eval(f"select(5, {BAND}.frame:GetPoint(1))") == 0  # the band right under the head
    # the box is Core's: 230 at most, however wide the head (where the list looks is the band's)
    size(wow, 1500)
    assert wow.eval(f"{MOD}.search:GetWidth()") == 230
    # a head too narrow for them: the tabs take a row under it, the band moves under that row
    size(wow, 800)
    assert wow.eval(f"{HEAD}.row") is True and wow.eval(f"{HEAD}:Room()") == 38
    assert wow.eval(f"{HEAD}.words") is True  # the words still fit on the row
    assert wow.eval(f"select(5, {BAND}.frame:GetPoint(1))") == -38
    assert wow.eval(f"-select(5, {MOD}.crumbs:GetPoint(1))") == 38 + 41 + 4
    # a row too narrow for the words: the pictograms, each with its name at once
    size(wow, 430)
    assert wow.eval(f"{HEAD}.words") is False
    world = f"{TABS}:Part('world')"
    assert wow.eval(f"{world}.item.icon") == "route" and wow.eval(f"{world}.tip") == "World"
    assert wow.eval(f"{world}.tipNow") is True
    assert wow.eval(f"{MOD}.toolbar.mag:IsShown()") is True  # and the magnifier of ADR 0058
    size(wow, 1100)
    assert wow.eval(f"{HEAD}.row") is False and wow.eval(f"{HEAD}.words") is True
    assert wow.eval(f"{MOD}.toolbar.mag:IsShown()") is False
    assert wow.errors == []


def test_a_tab_is_its_section_and_the_name_stays(wow: WowRuntime):
    """A click opens the section's first list; the lit tab leads there again (Here from a search).
    The window's name stays "Browser": the lit tab, the lit chip and the trail say the rest."""
    boot(wow)
    wow.execute(f"{BR}.OpenWindow()")
    title = f"{MOD}.win.title:GetText()"
    assert wow.eval(title) == "Browser" and wow.eval(f"{BR}.Title()") == "Here: Elwynn Forest"
    rail_click(wow, "world")
    wow.run_frames(5)
    assert (
        wow.eval(f"{BR}.ListEntry().type") == "zone" and wow.eval(f"{TABS}.spec.value") == "world"
    )
    assert wow.eval(title) == "Browser" and wow.eval(f"{BR}.Title()") == "Zones"
    nav_click(wow, "nav:list:npc")
    wow.run_frames(5)
    assert wow.eval(f"{BR}.Title()") == "People" and wow.eval(title) == "Browser"
    rail_click(wow, "world")  # the lit tab: back to the section's first list
    wow.run_frames(5)
    assert wow.eval(f"{BR}.ListEntry().type") == "zone"
    # a search without a type lights Here, and Here leads out of it
    wow.execute(f"{MOD}.search:SetText('dughan')")
    wow.run_frames(20)
    assert wow.eval(f"{BR}.ListEntry().kind") == "home" and wow.eval(f"{TABS}.spec.value") == "here"
    rail_click(wow, "here")
    wow.run_frames(5)
    assert wow.eval(f"{BR}.ListEntry().kind") == "here"
    assert wow.errors == []


def test_a_section_without_its_app_is_dim_and_says_what_it_needs(wow: WowRuntime):
    boot(wow, CORE, DATA, BROWSER)
    wow.execute(f"{BR}.OpenWindow()")
    chars = f"{TABS}:Part('characters')"
    assert wow.eval(f"{chars}.item.disabled") is True and wow.eval(f"{chars}:GetAlpha()") == 0.4
    assert list(wow.eval(f"{{ {chars}.tip({chars}) }}").values()) == [
        "Characters",
        "Characters needs Bastian's Alts",
    ]
    rail_click(wow, "characters")  # a click does nothing
    assert wow.eval(f"{BR}.ListEntry().kind") == "here" and wow.eval(f"{TABS}.spec.value") == "here"
    rows = {r[0]: r for r in rail_rows(wow)}
    assert rows["gold"][1] == "Items" and rows["gold"][3] is None  # without Bastian's Gold
    assert wow.eval(f"{TABS}:Part('gold'):GetAlpha()") == 1
    assert wow.eval(f"{TABS}:Part('gold').label:GetText()") == "items"  # small capitals
    assert wow.errors == []


def test_back_forward_and_the_lists_stand_in_one_band(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{BR}.OpenWindow()")
    size(wow, 1100)
    # Here: Back and Forward alone, tools 22 high with a pictogram, 15 from the side, 10 under
    # the band's top; the band 41 high on the panel's ground with a rule under it
    back, forward = f"{BAND}.byId.back", f"{BAND}.byId.forward"
    assert wow.eval(f"{BAND}.count") == 2 and tab_rows(wow) == []
    assert tuple(wow.eval(f"{back}:GetPoint(1)"))[3:] == (15, -10)
    assert wow.eval(f"{back}:GetHeight()") == 22 and wow.eval(f"{back}.spec.boxed") is True
    assert wow.eval(f"{back}.spec.icon") == "back" and wow.eval(f"{forward}.spec.icon") == "forward"
    assert wow.eval(f"{back}.label:GetText()") == "Back"
    assert wow.eval(f"{BAND}:Height()") == 41 and wow.eval(f"{BAND}.band.ground:IsShown()") is True
    assert wow.eval(f"{back}.enabledFlat") is False and wow.eval(f"{back}:GetAlpha()") == 0.4
    # World: its lists as chips after the arrows, the shown one filled; a chip is its list
    nav_click(wow, "nav:list:npc")
    wow.run_frames(5)
    assert [(t[1], t[2]) for t in tab_rows(wow)] == [
        ("Zones", False),
        ("People", True),
        ("Monsters", False),
        ("Objects", False),
    ]
    chips = f"{MOD}.tabs.chips"
    assert wow.eval(f"{chips}[1].small") is True and wow.eval(f"{chips}[1]:GetHeight()") == 22
    fx = wow.eval(f"(select(4, {forward}:GetPoint(1))) + {forward}:GetWidth()")
    assert tuple(wow.eval(f"{chips}[1]:GetPoint(1)"))[3:] == (fx + 5, -10)  # 5 apart, one row
    assert wow.eval(f"{back}.enabledFlat") is True  # a page before this one now
    wow.execute(f"{chips}[3]:Click()")
    wow.run_frames(5)
    assert (
        wow.eval(f"{BR}.ListEntry().type") == "mob"
        and wow.eval(f"{MOD}.tabs.active") == "nav:list:mob"
    )
    # the list's filter chips on rows of their own under them, 8 apart; the tiles under the trail
    chips_h = wow.eval(f"{BAND}.blockH")
    assert chips_h > 0 and wow.eval(f"{MOD}.filterHost:GetParent() == {BAND}.frame") is True
    assert tuple(wow.eval(f"{MOD}.filterHost:GetPoint(1)"))[3:] == (15, -(10 + 22 + 8))
    assert wow.eval(f"{BAND}:Height()") == 10 + 22 + 8 + chips_h + 9
    top = wow.eval(f"{BAND}:Height()") + 4 + 18 + 4
    assert wow.eval(f"-select(5, {MOD}.listPane:GetPoint(1))") == top
    # the line of what the list shows stands in the text size 13, dim (the one look's line)
    assert tuple(wow.eval(f"{MOD}.summary:GetFont()"))[1] == 13
    # Back is the band's tool
    wow.execute(f"{back}:Click()")
    wow.run_frames(5)
    assert wow.eval(f"{BR}.ListEntry().type") == "npc"
    assert wow.eval(f"{forward}.enabledFlat") is True
    assert wow.errors == []


def test_the_browser_works_with_core_alone(wow: WowRuntime):
    """W9's gate (ADR 0083): the app loads and works with Core alone: no Data, no other app."""
    boot(wow, CORE, BROWSER)
    assert wow.eval(f"{MOD}:IsEnabled()") is True
    wow.execute(f"{BR}.OpenWindow()")
    wow.run_frames(5)
    assert wow.eval(f"{MOD}.win:IsShown()") is True
    assert len(rail_rows(wow)) == 7 and wow.eval(f"{TABS}.spec.value") == "here"
    rail_click(wow, "more")
    wow.run_frames(5)
    assert wow.eval(f"{BR}.Current().kind") == "more" and wow.eval(f"{TABS}.spec.value") == "more"
    assert wow.eval(f"{BAND}.count") == 2  # Back and Forward
    assert wow.errors == []


def test_a_views_controls_stand_in_the_band(wow: WowRuntime):
    """A view hands its host controls (core-contracts 7b); the Browser draws them in its band,
    after the section's lists: a label behind a thin line, the right ones at the row's end.
    ~~A bar of their own at the list tile's top~~ (until W9)."""
    boot(wow)
    wow.execute(f"{BR}.OpenWindow()")
    size(wow, 1100)
    wow.execute(f"{BR}.ShowView('quests.log')")
    wow.run_frames(5)
    hide, tracked = f"{BAND}.byId.logHideDone", f"{BAND}.byId.logTrackedOnly"
    assert wow.eval(f"{hide}:GetParent() == {BAND}.frame") is True
    assert wow.eval(f"{hide}.small") is True and wow.eval(f"{hide}:GetHeight()") == 22
    # on the row of Back, Forward and the lists; the last one ends 15 before the band's edge
    assert wow.eval(f"select(5, {hide}:GetPoint(1))") == -10
    right = wow.eval(f"(select(4, {tracked}:GetPoint(1))) + {tracked}:GetWidth()")
    assert right == 1098 - 15 and wow.eval(f"{BAND}:Height()") == 41
    assert wow.eval(f"{MOD}.header:GetHeight()") == 1  # the list tile keeps no row for them
    assert [t[2] for t in tab_rows(wow)].count(True) == 1  # the lists stay, My quests lit
    # a click is the view's
    before = wow.eval("Bastians:GetModule('Quests').db.profile.logHideDone")
    wow.execute(f"{hide}:Click()")
    wow.run_frames(5)
    assert wow.eval("Bastians:GetModule('Quests').db.profile.logHideDone") is not before
    assert wow.eval(f"{BAND}.byId.logHideDone.spec.on") is (not before)
    # a list has none of them
    nav_click(wow, "nav:list:quest")
    wow.run_frames(5)
    assert wow.eval(f"{BAND}.byId.logHideDone") is None
    assert wow.errors == []
