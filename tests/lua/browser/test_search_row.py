"""The search box in the title row (ADR 0058, PH2; until then the search row of ADR 0056, PA1.2:
Back, Forward, the box and the chips in one row) and the row of Back, Forward and the filter
chips under the rail, flowing into more lines at the row's width. Where the list and the
search look is a chip inside the box (the list's "Where" of C9, taken out of the bar): a click
opens its choices, its x looks everywhere. A search typed on a list keeps the list's scope."""

import re

from harness import WowRuntime
from pages import clear, menu, near_by_default, pick, pills, scope

CORE, DATA, QUESTS, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Browser",
)
MOD = "Bastians:GetModule('Browser')"
BR = f"{MOD}.Browser"
TREE = f"{MOD}.tree"
HOST = f"{MOD}.filterHost"
SIZE = f"{TREE}.scroll:SetSize(440, 400); {TREE}:Refresh()"
TOOLBAR_H, CRUMB_H = 26, 18


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA, QUESTS, BROWSER)
    wow.run_frames(10)
    wow.advance(0.3)
    return wow


def strip(text: str | None) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    return re.sub(r"\|c[0-9a-fA-F]{8}", "", text).replace("|r", "")


def open_list(wow: WowRuntime, typ: str) -> None:
    wow.execute(f"{BR}.List('{typ}')")
    wow.run_frames(8)
    wow.execute(SIZE)


def resize(wow: WowRuntime, width: int) -> None:
    wow.execute(f"{MOD}.win.frame:SetWidth({width}); {MOD}.win.opts.onResize({MOD}.win, false)")
    wow.run_frames(3)


def names(wow: WowRuntime) -> list[str]:
    """The list tile's rows by their name line, without a provider's offer."""
    rows = wow.eval(f"{TREE}.flat").values()
    return [strip(r.title or r.text) for r in rows if not str(r.id).startswith("s:offer:")]


def search(wow: WowRuntime, text: str) -> None:
    wow.execute(f"{MOD}.search:SetText('{text}')")
    wow.run_frames(20)
    wow.execute(SIZE)


def tiles_top(wow: WowRuntime) -> float:
    return -wow.eval(f"select(5, {MOD}.listPane:GetPoint(1))")


def test_the_search_stands_in_the_title_row_and_the_chips_after_the_arrows(wow: WowRuntime):
    """ADR 0058, PH2: the search box lives in the title row, right of the title and before Dock;
    the row under the rail holds Back, Forward and the filter chips, which flow at the row's
    width. Under 640 units a magnifier stands in the title row; a click opens the box over the
    title, a second brings the title back."""
    boot(wow)
    open_list(wow, "npc")
    bar = f"{TREE}.filterBar"
    head = f"{MOD}.win.head"
    top = wow.eval(f"-select(5, {MOD}.toolbar:GetPoint(1))")
    assert wow.eval(f"{MOD}.search:GetParent() == {head}") is True
    assert wow.eval(f"select(2, {MOD}.search:GetPoint(1)) == {MOD}.toolbar.dock") is True
    assert (
        wow.eval(f"select(2, {MOD}.win.title:GetPoint(2)) == {MOD}.search") is True
    )  # the title ends at the box
    box = wow.eval(f"{MOD}.search:GetWidth()")
    assert 200 <= box <= 420 and wow.eval(f"{MOD}.search:IsShown()") is True
    assert wow.eval(f"{MOD}.toolbar.mag:IsShown()") is False
    # the chips' frame starts right of the arrows, on the row under the rail
    assert wow.eval(f"{HOST}:IsShown()") is True
    assert wow.eval(f"{bar}.frame:GetParent() == {HOST}") is True
    assert wow.eval(f"select(2, {HOST}:GetPoint(1)) == {MOD}.toolbar") is True
    assert wow.eval(f"(select(3, {HOST}:GetPoint(1)))") == "TOPLEFT"
    left = wow.eval(f"(select(4, {HOST}:GetPoint(1)))")
    arrows = wow.eval(f"{MOD}.toolbar.back:GetWidth() + 2 + {MOD}.toolbar.forward:GetWidth() + 8")
    assert left == arrows and wow.eval(f"select(5, {HOST}:GetPoint(1))") == 0
    assert left + wow.eval(f"{HOST}:GetWidth()") == 1000 - 12  # to the window's right edge
    lines = wow.eval(f"{bar}:Height()")
    assert tiles_top(wow) == top + max(TOOLBAR_H, lines - 4) + 4 + CRUMB_H + 4
    # the rows start at the top of the list tile: the tree keeps no room for the bar
    assert wow.eval(f"{TREE}.chips:GetHeight()") == 1
    # a narrow window: the magnifier in the title row, the box hidden; the chips keep their place
    resize(wow, 430)
    top = wow.eval(f"-select(5, {MOD}.toolbar:GetPoint(1))")
    assert wow.eval(f"{MOD}.toolbar.mag:IsShown()") is True
    assert (
        wow.eval(f"{MOD}.search:IsShown()") is False
        and wow.eval(f"{MOD}.win.title:IsShown()") is True
    )
    assert wow.eval(f"(select(3, {HOST}:GetPoint(1)))") == "TOPLEFT"
    assert wow.eval(f"{HOST}:GetWidth()") == 430 - 12 - arrows
    lines = wow.eval(f"{bar}:Height()")
    assert tiles_top(wow) == top + max(TOOLBAR_H, lines - 4) + 4 + CRUMB_H + 4
    # the magnifier opens the box over the title, and closes it again
    wow.execute(f"{MOD}.toolbar.mag:Click()")
    assert wow.eval(f"{BR}.IsSearching()") is True
    assert (
        wow.eval(f"{MOD}.search:IsShown()") is True
        and wow.eval(f"{MOD}.win.title:IsShown()") is False
    )
    assert wow.eval(f"select(2, {MOD}.search:GetPoint(2)) == {MOD}.toolbar.mag") is True
    wow.execute(f"{MOD}.toolbar.mag:Click()")
    assert (
        wow.eval(f"{MOD}.search:IsShown()") is False
        and wow.eval(f"{MOD}.win.title:IsShown()") is True
    )
    # a page takes the one tile: no list, no chips
    wow.execute(f"{BR}.Open('npc:240')")
    wow.run_frames(3)
    assert wow.eval(f"{MOD}.listPane:IsShown()") is False and wow.eval(f"{HOST}:IsShown()") is False
    page_top = -wow.eval(f"select(5, {MOD}.detailPane:GetPoint(1))")
    assert page_top == top + TOOLBAR_H + 4 + CRUMB_H + 4
    wow.execute(f"{BR}.SetListOpen(true)")
    wow.run_frames(3)
    assert wow.eval(f"{HOST}:IsShown()") is True
    # wide again: the box is back in the title row, the magnifier gone; Here filters nothing
    resize(wow, 1000)
    assert (
        wow.eval(f"{MOD}.search:IsShown()") is True
        and wow.eval(f"{MOD}.toolbar.mag:IsShown()") is False
    )
    wow.execute(f"{BR}.ShowHere()")
    wow.run_frames(5)
    assert wow.eval(f"{HOST}:IsShown()") is False and scope(wow) is None
    assert wow.errors == []


def test_the_scope_is_a_chip_inside_the_search_box(wow: WowRuntime):
    boot(wow)
    near_by_default(wow)  # the narrowing itself is what this test is about
    open_list(wow, "npc")
    chip = f"{MOD}.scope"
    assert scope(wow) == "in Elwynn Forest"  # the list opens on the player's zone (C9)
    assert wow.eval(f"{chip}:GetParent() == {MOD}.search") is True
    assert wow.eval(f"{chip}.clear:IsShown()") is True
    assert not any(p.startswith("Where") for p in pills(wow, TREE))  # no pill of the bar
    # the box's text ends before the chip
    inset = wow.eval(f"(select(2, {MOD}.search:GetTextInsets()))")
    assert inset == 22 + wow.eval(f"{chip}:GetWidth()") + 4
    # a click opens the choices with their counts, a second click shuts them
    assert menu(wow, TREE, "where") == ["All  6", "Here  5", "Continent  6"]
    wow.execute(f"{chip}:Click()")
    assert wow.eval("Bastians.UI.FilterMenuFrame():IsShown()") is True
    wow.execute(f"{chip}:Click()")
    assert wow.eval("Bastians.UI.FilterMenuFrame():IsShown()") is False
    pick(wow, TREE, "where", "Continent")
    assert scope(wow) == "in Eastern Kingdoms" and wow.eval(f"{BR}.Current().near") == "continent"
    assert "Gryan Stoutmantle" in names(wow)
    # the x: everywhere; the chip stays, quiet, to choose again
    clear(wow, TREE, "where")
    assert scope(wow) == "Everywhere" and wow.eval(f"{BR}.Current().near") is None
    assert wow.eval(f"{chip}.clear:IsShown()") is False
    pick(wow, TREE, "where", "Here")
    assert scope(wow) == "in Elwynn Forest" and "Gryan Stoutmantle" not in names(wow)
    # a list without places has no scope
    open_list(wow, "item")
    assert scope(wow) is None
    assert wow.eval(f"(select(2, {MOD}.search:GetTextInsets()))") == 22
    assert wow.errors == []


def test_a_search_typed_on_a_near_list_looks_everywhere(wow: WowRuntime):
    """the search is always global. Typed on a list kept to the zone it
    looks everywhere; the chip's choices narrow it, and who stands elsewhere is counted."""
    boot(wow)
    near_by_default(wow)
    open_list(wow, "npc")
    assert scope(wow) == "in Elwynn Forest"
    search(wow, "marshal")
    assert wow.eval(f"{BR}.ListEntry().kind") == "home"
    assert wow.eval(f"{BR}.ListEntry().scope") is None and scope(wow) == "Everywhere"
    assert "Marshal Dughan" in names(wow)
    search(wow, "gryan")
    assert names(wow) == ["Gryan Stoutmantle"] and scope(wow) == "Everywhere"
    # the chip's choices put the scope back; the continent holds Westfall
    pick(wow, TREE, "where", "Here")
    wow.run_frames(20)
    assert scope(wow) == "in Elwynn Forest" and "Gryan Stoutmantle" not in names(wow)
    # who stands elsewhere is left out, counted, and one click away
    assert names(wow) == ["1 more elsewhere. Click to look everywhere."]
    pick(wow, TREE, "where", "Continent")
    wow.run_frames(20)
    assert scope(wow) == "in Eastern Kingdoms" and names(wow) == ["Gryan Stoutmantle"]
    # the box emptied: the list is back, with its own scope; the search page at rest has none
    search(wow, "")
    assert wow.eval(f"{BR}.ListEntry().kind") == "list" and scope(wow) == "in Elwynn Forest"
    wow.execute(f"{BR}.Home()")
    wow.run_frames(5)
    assert scope(wow) is None
    assert wow.errors == []


def test_a_thing_without_a_place_stays_under_a_scope(wow: WowRuntime):
    """The scope says nothing about an item or a recipe: they have no place to be outside of."""
    boot(wow)
    wow.execute(f"{BR}.Search('linen', false, 'here')")
    wow.run_frames(20)
    wow.execute(SIZE)
    assert scope(wow) == "in Elwynn Forest"
    assert "Linen Cloth" in names(wow)
    # a search from the search page itself looks everywhere, as before
    wow.execute(f"{BR}.Home(); {MOD}.search:SetText('gryan')")
    wow.run_frames(20)
    wow.execute(SIZE)
    assert scope(wow) == "Everywhere" and names(wow) == ["Gryan Stoutmantle"]
    assert wow.errors == []


OFFER = """
Bastians:RegisterSearchProvider(Bastians:GetModule('Browser'), {
  id = "t.offer", label = "Offer", priority = 10,
  search = function()
    return { { label = "An offer of the test", score = 0.3,
      action = function() OFFER_TAKEN = true end } }
  end })
"""
BROKEN = """
Bastians:RegisterSearchProvider(Bastians:GetModule('Browser'), {
  id = "t.broken", label = "Broken", priority = 500,
  search = function() error("a provider that fails") end })
"""


def search_ends(wow: WowRuntime, text: str) -> list[str]:
    wow.execute(f"{BR}.Search('{text}')")
    wow.run_frames(30)
    assert wow.eval("Bastians.Jobs:Pending()") == 0
    assert "Searching" not in str(wow.eval(f"{MOD}.summary:GetText()"))
    return [str(r.text) for r in wow.eval(f"{TREE}.flat").values()]


def test_a_providers_offer_is_a_row_and_the_search_ends(wow: WowRuntime):
    """ "stays forever on Searching...". Quests offers to load the texts
    while that pack is not loaded: a result without a thing, which the rows could not draw."""
    boot(wow)
    wow.execute(OFFER)
    rows = search_ends(wow, "hogger")
    assert any("Hogger" in r for r in rows)
    assert any("An offer of the test" in r for r in rows[-2:])  # after the results
    wow.execute(
        f"for _, row in ipairs({TREE}.flat) do"
        " if row.id == 's:offer:An offer of the test' then row.onClick(row) break end end"
    )
    assert wow.eval("OFFER_TAKEN") is True
    assert wow.errors == []


def test_a_failing_provider_costs_only_its_own_results(wow: WowRuntime):
    boot(wow)
    wow.execute(BROKEN)
    rows = search_ends(wow, "hogger")
    assert any("Hogger" in r for r in rows)
    log = [line.text for line in wow.eval("Bastians:GetLog()").values() if line.level == "error"]
    assert any("search t.broken" in line for line in log)


def test_a_search_ends_when_its_caller_fails(wow: WowRuntime):
    boot(wow)
    wow.execute(
        """
        SEEN = {}
        Bastians:Search("hogger", {}, function(_, done)
          SEEN[#SEEN + 1] = done
          error("a caller that fails")
        end)
        """
    )
    wow.run_frames(30)
    seen = list(wow.eval("SEEN").values())
    assert seen[-1] is True and wow.eval("Bastians.Jobs:Pending()") == 0
