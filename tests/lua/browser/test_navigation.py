"""Navigation defects of ADR 0013 (N1, 23.10.2026): the search box empties on every page change and
the filter follows, the type is a badge on the card (no dropdown), "Open in Browser" is not
offered on the page it would re-open but opens a page from a view's row."""

import re

from harness import WowRuntime
from pages import nav_click, nav_rows, page_rows

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


def test_the_search_is_global_and_the_type_chips_filter_it(wow: WowRuntime):
    """(N12): typing on a page mixed the page's own rows into the
    search ("Mangy" on the Elwynn page), and on a page the type chips did nothing. Now typing
    anywhere searches the world (on a list with the list's type as the filter); the chips filter
    the search on every entry, with an empty box they open their list (All: the home); Back
    returns to where the search started."""
    boot(wow)
    wow.slash("/bq log")
    wow.execute(SIZE)
    # typing on a view: the world search, the box keeps the text
    wow.execute(f"{MOD}.search:SetText('hog')")
    wow.run_frames(10)
    assert wow.eval(f"{BR}.Current().kind") == "home"
    assert wow.eval(f"{MOD}.search:GetText()") == "hog"
    assert any(r.startswith("Hogger") for r in flat(wow))
    wow.execute(f"{BR}.Back()")
    assert wow.eval(f"{BR}.Current().kind") == "view"
    assert wow.eval(f"{MOD}.search:GetText()") == ""
    # a page: the box is empty; typing there searches the world, not the page
    wow.execute("Bastians:RunAction('browser.open', 'npc:240', { source = 'map' })")
    assert wow.eval(f"{BR}.Current().ref") == "npc:240"
    assert wow.eval(f"{MOD}.search:GetText()") == ""
    assert "Overview" in page_rows(wow, DS)
    wow.execute(f"{MOD}.search:SetText('fargo')")
    wow.run_frames(10)
    assert wow.eval(f"{BR}.Current().kind") == "home"
    assert any("Fargodeep" in r for r in flat(wow))
    # a list in the navigation with text in the box filters the search (and is accented); the
    # same list again clears the filter (ADR 0018: the type bar's All is gone)
    nav_click(wow, "nav:list:item")
    wow.run_frames(10)
    assert wow.eval(f"{BR}.Current().kind") == "home" and wow.eval(f"{BR}.HomeType()") == "item"
    assert wow.eval(f"{MOD}.search:GetText()") == "fargo"
    assert wow.eval(f"{MOD}.navTree.selectedID") == "nav:list:item"
    nav_click(wow, "nav:list:item")
    wow.run_frames(10)
    assert wow.eval(f"{BR}.HomeType()") is None
    # a page opens beside the search, which keeps its text (ADR 0018); with an empty box a list
    # in the navigation opens that list
    wow.execute(f"{BR}.Open('npc:240')")
    assert wow.eval(f"{MOD}.search:GetText()") == "fargo"
    wow.execute(f"{MOD}.search:SetText('')")
    nav_click(wow, "nav:list:item")
    wow.run_frames(10)
    assert wow.eval(f"{BR}.Current().kind") == "list" and wow.eval(f"{BR}.Current().type") == "item"
    # typing on a list searches the world for that type
    wow.execute(f"{MOD}.search:SetText('linen')")
    wow.run_frames(10)
    assert wow.eval(f"{BR}.Current().kind") == "home" and wow.eval(f"{BR}.HomeType()") == "item"
    assert any(r.startswith("Linen Cloth") for r in flat(wow))
    wow.execute(f"{BR}.Open('npc:240')")
    wow.execute(f"{BR}.Home()")
    assert wow.eval(f"{BR}.Current().kind") == "home"
    # a re-render of the same entry keeps what is typed
    wow.execute(f"{MOD}.search:SetText('mine')")
    wow.run_frames(5)
    wow.execute(f"{BR}.Render()")
    assert wow.eval(f"{MOD}.search:GetText()") == "mine"
    assert wow.errors == []


def test_the_type_is_a_badge_on_the_card_not_a_dropdown(wow: WowRuntime):
    """ADR 0013 F: the type dropdown is gone; the card's badge says what the page is."""
    boot(wow)
    wow.execute(f"{BR}.Open('npc:240')")
    assert wow.eval(f"{MOD}.toolbar.types") is None
    assert wow.eval(f"{DS}.band.badge.label:GetText()") == "npc"
    wow.slash("/bq here")
    assert wow.eval(f"{DS}.band.badge.label:GetText()") == "zone"
    wow.execute(f"{BR}.Home()")
    assert wow.eval(f"{BR}.Current().kind") == "home"
    assert wow.errors == []


def test_open_in_browser_from_a_view_row_opens_the_page(wow: WowRuntime):
    boot(wow)
    wow.slash("/bq log")
    wow.execute(SIZE)
    # the entity menu of a quest row in the log view offers "Open in Browser"; it opens the page
    wow.execute(
        f"for _, r in ipairs({MOD}.tree.flat) do "
        f"if r.ref == 'quest:62' then {MOD}.tree.opts.onClick(r, 'RightButton') break end end"
    )
    assert wow.eval("Bastians.UI.EntityMenuFrame():IsShown()") is True
    labels = [
        strip(i.label.GetText(i.label))
        for i in wow.eval("Bastians.UI.EntityMenuFrame().items").values()
        if i.IsShown(i)
    ]
    assert "Open in Browser" in labels
    # inside the Browser the item is greyed: the row click opens the page;
    # a click on the greyed item leaves the menu open and changes nothing
    greyed = [
        i.action.id
        for i in wow.eval("Bastians.UI.EntityMenuFrame().items").values()
        if i.IsShown(i) and i.disabled
    ]
    assert greyed == ["browser.open"]
    wow.execute(
        "for _, it in ipairs(Bastians.UI.EntityMenuFrame().items) do "
        "if it.action and it.action.id == 'browser.open' then it:Click() end end"
    )
    assert wow.eval("Bastians.UI.EntityMenuFrame():IsShown()") is True
    assert wow.eval(f"{BR}.Current().kind") == "view"
    wow.execute("Bastians.UI.EntityMenuFrame():Hide()")
    wow.execute(
        f"for _, r in ipairs({MOD}.tree.flat) do "
        f"if r.ref == 'quest:62' then {MOD}.tree.opts.onClick(r, 'LeftButton') break end end"
    )
    assert wow.eval(f"{BR}.Current().kind") == "page"
    assert wow.eval(f"{BR}.Current().ref") == "quest:62"
    # the action stays listed everywhere; from the map it is greyed only on the page already shown
    enabled = lambda ref, source: wow.eval(  # noqa: E731
        f"Bastians:ActionEnabled('browser.open', '{ref}', {{ source = '{source}' }})"
    )
    assert enabled("quest:62", "browser") is False and enabled("quest:76", "browser") is False
    assert enabled("quest:62", "map") is False and enabled("quest:76", "map") is True
    ids = [a.id for a in wow.eval("Bastians:GetActions('quest:62', { source = 'map' })").values()]
    assert "browser.open" in ids
    wow.execute("Bastians:GetService('views'):Hide()")
    assert enabled("quest:62", "browser") is True  # the window is closed: it opens
    assert wow.errors == []


def test_my_quests_is_one_click_in_the_navigation(wow: WowRuntime):
    """The log view is pinned (RegisterView `pinned`): the navigation's second row, after Here
    (ADR 0018; before, a toolbar button after Home)."""
    boot(wow)
    wow.execute(f"{BR}.Open()")
    rows = nav_rows(wow)
    assert rows[0][0] == "nav:here" and rows[1] == (
        "nav:view:quests.log",
        "My quests  2 in the log",
    )
    assert ("nav:view:quests.all", "All quests") in rows  # the other views under their group
    nav_click(wow, "nav:view:quests.log")
    assert wow.eval(f"{BR}.Current().kind") == "view"
    assert wow.eval(f"{BR}.Current().id") == "quests.log"
    # the Quests addon off: the row goes; on again: it is back
    wow.execute("Bastians:GetModule('Quests'):Disable()")
    wow.advance(0.2)
    assert not any(rid.startswith("nav:view:") for rid, _ in nav_rows(wow))
    wow.execute("Bastians:GetModule('Quests'):Enable()")
    wow.advance(0.2)
    assert nav_rows(wow)[1][0] == "nav:view:quests.log"
    assert wow.errors == []
