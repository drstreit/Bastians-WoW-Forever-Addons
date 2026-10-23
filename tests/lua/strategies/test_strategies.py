"""Bastian's Strategies (strategies-design.md section 6): the book read from the generated fixture pack
(tests/fixtures/book-mini through the real compiler): the logic, the title page with What's new, the
contents with sealed pages, a page with its plate, live box, rumours, the places it names and the
reader's note, bookmarks and the last page across a reload, the back shelf and a tombstone, pages as
entities on the map, in the search and on the Browser pages of what they name."""

import re

from harness import WowRuntime

CORE, DATA, GOLD, BROWSER, STRAT = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Gold",
    "Bastians_Browser",
    "Bastians_Strategies",
)
MOD = "Bastians:GetModule('Strategies')"
WIN = f"{MOD}.Window"
BOOK = f"{MOD}.Book"


def boot(wow: WowRuntime, *addons: str, level: int | None = None) -> WowRuntime:
    # a realm Gold maps to the fixture market (gold.md), so the live boxes have prices
    wow.execute('function GetRealmName() return "Classic Beta PvE" end')
    if level is not None:
        wow.execute(f"Mock.level = {level}")
    wow.start(*(addons or (CORE, DATA, STRAT)))
    wow.run_frames(10)
    wow.advance(0.5)
    return wow


def strip(text) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", str(text or ""))
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def texts(wow: WowRuntime, side: str) -> list[str]:
    """The shown texts of a page (left or right): the text blocks and the clickable rows."""
    page = wow.eval(f"{WIN}.{side}")
    out = []
    for fs in page.fs.values():
        if fs.IsShown(fs):
            out.append(strip(fs.GetText(fs)))
    for row in page.rows.values():
        if row.IsShown(row):
            out.append(strip(row.label.GetText(row.label)))
    for box in page.boxes.values():
        if box.IsShown(box):
            out.extend(strip(f.GetText(f)) for f in box.fs.values() if f.IsShown(f))
    return out


def both(wow: WowRuntime) -> list[str]:
    return texts(wow, "left") + texts(wow, "right")


def click_row(wow: WowRuntime, side: str, startswith: str) -> None:
    wow.execute(
        f"for _, r in ipairs({WIN}.{side}.rows) do "
        f"if r:IsShown() and r.label:GetText():find({startswith!r}, 1, true) then r:Click() return end end "
        "error('no such row')"
    )


def test_the_logic_farm_flip_pairs_index_and_seals(core: WowRuntime):
    core.load_addon(STRAT)
    farm = core.eval(
        f"{BOOK}.Farm({{ 1, 2 }}, function(id) return ({{ [1] = {{ {{ 10, 50 }}, {{ 11, 4 }} }}, "
        "[2] = { { 10, 30 } } })[id] end, function(item) return ({ [10] = 100 })[item] end)"
    )
    # Wool at 1s, 40 % of the kills on average (50 and 30), after the 5 % cut: 38c a kill; the
    # item without a price is counted as unknown, never as 0 (golden rule 2)
    assert farm.perKill == 38 and farm.unknown == 1 and farm["items"][1]["item"] == 10
    flip = core.eval(f"{BOOK}.Flip(150, 200, 1)")
    assert (flip.margin, flip.open, flip.ownAH) == (50, True, 143)
    assert core.eval(f"{BOOK}.Flip(nil, 200).margin") is None  # no auction price: no verdict
    # a craft: the product's sale after the cut against the reagents; a reagent without a price:
    # no margin (never a margin that pretends the reagent is free)
    craft = core.eval(
        f"{BOOK}.Craft(1000, 1, {{ {{ 1, 2 }}, {{ 2, 1 }} }}, function(i) return ({{ 100, 300 }})[i] end)"
    )
    assert (craft.cost, craft.sale, craft.margin) == (500, 950, 450)
    gap = core.eval(f"{BOOK}.Craft(1000, 1, {{ {{ 3, 1 }} }}, function() return nil end)")
    assert gap.margin is None and gap.missing == 1
    # What's new: a second update on the same day is new; beta.8's date alone means all seen
    news = (
        "{ { date = '2026-10-23', text = 'b' }, { date = '2026-10-23', text = 'a' }, "
        "{ date = '2026-10-20', text = 'c' } }"
    )
    assert core.eval(f"{BOOK}.Unread({news}, '2026-10-23', {{ a = true }})") == 1
    assert core.eval(f"{BOOK}.Unread({news}, '2026-10-23', nil)") == 0
    assert core.eval(f"{BOOK}.Unread({news}, '2026-10-20', {{ c = true }})") == 2
    assert core.eval(f"{BOOK}.Unread({news}, nil)") == 3
    # the reading order: a chapter's pages, then its Rumour mill when it has one
    order = core.eval(
        f"{BOOK}.Order({{ chapters = {{ 'a', 'b' }}, pages = {{ a = {{ 'p1' }}, b = {{}} }} }}, "
        "function(c) return c == 'b' end)"
    )
    assert [(e.kind, e.id) for e in order.values()] == [("page", "p1"), ("mill", "b")]
    pairs = core.eval(
        f"{BOOK}.Pairs({{ {{ 1, 2, 1 }}, {{ 3, 4, 2 }} }}, function(i) return ({{ 13, 10, 150, 400 }})[i] end)"
    )
    assert round(pairs[1].gain, 2) == -0.23 and round(pairs[2].gain, 2) == 0.33
    page = "{ levelMin = 21, zones = { 1413 } }"
    assert core.eval(f"{BOOK}.IsOpen({page}, 18, {{}})") is False
    assert core.eval(f"{BOOK}.IsOpen({page}, 19, {{}})") is True  # two levels early
    assert core.eval(f"{BOOK}.IsOpen({page}, 5, {{ [1413] = true }})") is True  # been there
    assert core.eval(f"{BOOK}.Moment('https://www.youtube.com/watch?v=x&t=95s')") == "1:35"
    assert (
        core.eval(
            f"{BOOK}.Unread({{ {{ date = '2026-10-23' }}, {{ date = '2026-10-20' }} }}, '2026-10-21')"
        )
        == 1
    )


def test_the_title_page_shows_whats_new_and_marks_it_read(wow: WowRuntime):
    boot(wow)
    wow.slash("/bbook")
    assert wow.eval("BastiansStrategiesFrame:IsShown()") is True
    assert wow.eval(f"{WIN}.Current().kind") == "title"
    left, right = texts(wow, "left"), texts(wow, "right")
    assert "Bastian's Gold Rumours" in left
    assert right[0] == "WHAT'S NEW"
    assert "new  2026-10-23  New page: Hogger's Camp." in right  # a link to the page
    assert "new  2026-10-20  The book opens." in right
    assert wow.eval(f"{WIN}.News()[1].date") == "2026-10-23"  # newest first
    assert wow.eval(f"{MOD}.db.global.seen") == "2026-10-23"
    assert wow.eval(f"{MOD}.db.global.seenToday['New page: Hogger\\'s Camp.']") is True
    click_row(wow, "right", "New page")
    assert wow.eval(f"{WIN}.Current().id") == "hogger-camp"
    assert wow.errors == []


def test_contents_lists_the_chapters_and_seals_pages_by_level_and_zone(wow: WowRuntime):
    wow.execute("Mock.playerMap = 1436")  # Westfall: Elwynn not set foot in yet
    boot(wow, level=3)
    wow.slash("/bbook contents")
    left = texts(wow, "left")
    assert left[0] == "CONTENTS" and "Farming and easy kills" in left
    hogger = next(t for t in left if t.startswith("Hogger's Camp"))
    assert hogger.endswith("sealed")
    assert "The back shelf: 1 older pages, in the index" in left
    wow.slash("/bbook hogger-camp")
    assert any(
        t.startswith("This page is sealed. It opens at level 7") and "Elwynn Forest" in t
        for t in both(wow)
    )
    # entering Elwynn unseals it (SB3)
    wow.execute("Mock.playerMap = 1429")
    wow.fire("ZONE_CHANGED_NEW_AREA")
    wow.advance(0.5)
    assert wow.eval(f"{MOD}.db.char.entered[1429]") is True
    assert not any(t.startswith("This page is sealed") for t in both(wow))
    assert wow.errors == []


def test_a_page_with_its_plate_live_box_rumours_places_and_note(wow: WowRuntime):
    boot(wow, CORE, DATA, GOLD, STRAT)
    wow.slash("/bbook hogger-camp")
    shown = both(wow)
    assert (
        "Hogger's Camp" in shown and "Elwynn Forest  /  level 9 to 12  /  linen  /  alone" in shown
    )
    assert shown[0] == "FARMING AND EASY KILLS"
    assert any(
        t.startswith("I'm standing at the gnoll camp. The gnolls carry Linen Cloth and Hogger")
        for t in shown
    )
    # the tokens: the AH price through Gold's prices service, the vendor price from the data
    why = next(t for t in shown if t.startswith("Linen sells for"))
    assert "a vendor pays 13c" in why
    assert [t for t in shown if t[:2] in ("1.", "2.")] == [
        "1. Walk the loop.",
        "2. Kill Hogger when he is up. He is up often.",
    ]
    assert any(t.startswith("BASTIAN'S VERDICT  Fine for a beginner.") for t in shown)
    # the plate: dots, the loop, the landmark and the legend drawn from the precomputed geometry
    plate = wow.eval(f"{WIN}.left.plates[1] or {WIN}.right.plates[1]")
    assert plate.frame.IsShown(plate.frame) and plate.nt > 6
    # the live box: a kill's loot at the market's prices
    assert "WHAT IT PAYS ON YOUR MARKET" in shown
    assert any(t.endswith("per 100 kills.") for t in shown)
    # the rumours: the stamp, AHSync's own sentence, the reason, the source's line and link
    assert "[Checked] Hogger's camp in Elwynn drops a lot of Linen Cloth." in shown
    assert "[Half right] The Fargodeep Mine kobolds drop Linen Cloth too." in shown
    assert "Only the kobolds near the entrance." in shown
    click_row(wow, "right", "Fixture Channel")
    assert wow.eval("Mock.chatInput") == "https://www.youtube.com/watch?v=fixture1&t=85s"
    assert "Fixture Channel, 2026-10-13, at 1:25  copy the link" in shown
    # the places it names: without the Browser a click rings the place on the map
    assert "Linen Cloth" in shown and "Hogger" in shown
    assert wow.eval(f"{WIN}.OpenRef('npc:448')") != "browser"
    # the note: kept per account, by the page's id
    box = f"{WIN}.right.edits[1]"
    wow.execute(
        f"local b = {box}; b.text = 'come back at 11'; b:GetScript('OnTextChanged')(b, true)"
    )
    assert wow.eval(f"{MOD}.db.global.notes['hogger-camp']") == "come back at 11"
    assert wow.errors == []


def test_bookmarks_the_last_page_and_notes_survive_a_reload(wow: WowRuntime):
    boot(wow)
    wow.slash("/bbook hogger-camp")
    wow.execute(f"{WIN}.bar.mark:Click()")
    assert wow.eval(f"{MOD}.db.char.bookmarks[1]") == "hogger-camp"
    assert wow.eval(f"{WIN}.bar.mark.label:GetText()") == "Bookmarked"
    wow.execute(
        f"{MOD}.db.global.notes['hogger-camp'] = 'note'; {MOD}.db.char.bookmarks[2] = 'old-gnolls'"
    )
    fresh = wow.reload()
    fresh.run_frames(10)
    fresh.advance(0.5)
    fresh.slash("/bbook")  # opens where the character left it
    assert fresh.eval(f"{WIN}.Current().id") == "hogger-camp"
    assert fresh.eval(f"{MOD}.db.global.notes['hogger-camp']") == "note"
    fresh.slash("/bbook bookmarks")
    left = texts(fresh, "left")
    assert "Hogger's Camp" in left and "The Old Gnoll Camp  retired" in left
    # a retired page's bookmark still says what happened and where to read on
    click_row(fresh, "left", "The Old Gnoll Camp")
    shown = both(fresh)
    assert "Retired on 2026-10-22: The camp moved." in shown
    click_row(fresh, "left", "Read on: Hogger's Camp")
    assert fresh.eval(f"{WIN}.Current().id") == "hogger-camp"
    assert fresh.errors == []


def test_the_back_shelf_is_in_the_index_with_its_flow_plate_table_and_flip(wow: WowRuntime):
    boot(wow, CORE, DATA, GOLD, STRAT)
    wow.slash("/bbook index")
    shown = both(wow)
    assert "The Leather Trick  back shelf" in shown
    assert any(
        t.startswith("Linen Cloth  ") and "Hogger's Camp" in t for t in shown
    )  # a place or item
    click_row(wow, "left", "The Leather Trick")
    shown = both(wow)
    assert shown[0] == "FROM THE BACK SHELF"
    assert "AT THE VENDOR" in shown
    assert any(t.startswith("Linen Cloth (13c) as Light Leather (25c): +92") for t in shown)
    assert "TODAY ON YOUR MARKET" in shown
    assert any("Linen Cloth on the auction house:" in t for t in shown)
    assert wow.errors == []


def test_turning_pages_follows_the_reading_order(wow: WowRuntime):
    boot(wow)
    wow.slash("/bbook")
    wow.execute(f"{WIN}.folio.next:Click()")
    assert wow.eval(f"{WIN}.Current().kind") == "contents"  # no front matter in the fixture
    wow.execute(f"{WIN}.folio.next:Click()")
    assert wow.eval(f"{WIN}.Current().id") == "hogger-camp"
    wow.execute(f"{WIN}.folio.back:Click()")
    assert wow.eval(f"{WIN}.Current().kind") == "contents"
    assert wow.errors == []


def test_the_rumour_mill_follows_its_chapter_and_credits_the_travellers(wow: WowRuntime):
    boot(wow)
    order = [(e.kind, e.id) for e in wow.eval(f"{WIN}.Order()").values()]
    assert order.index(("mill", "farming")) == order.index(("page", "hogger-camp")) + 1
    wow.slash("/bbook contents")
    assert "Rumour mill: 1 rumours I have not tried yet" in texts(wow, "left")
    click_row(wow, "left", "Rumour mill:")
    assert (wow.eval(f"{WIN}.Current().kind"), wow.eval(f"{WIN}.Current().id")) == (
        "mill",
        "farming",
    )
    shown = both(wow)
    assert "THE RUMOUR MILL" in shown and "Farming and easy kills" in shown
    # the claim told by two channels and on no page (tests/fixtures/export-mini, claim 13)
    assert "[Heard, not checked] Hogger drops the Blood Saber about once in 30 kills." in shown
    assert "Elwynn Forest  /  told by 2 channels" in shown
    assert "Fixture Channel, 2026-10-13, at 0:40  copy the link" in shown
    assert "Other Channel, 2026-10-14, at 3:20  copy the link" in shown
    wow.execute(f"{WIN}.folio.back:Click()")
    assert wow.eval(f"{WIN}.Current().id") == "hogger-camp"
    wow.slash("/bbook mill")
    assert wow.eval(f"{WIN}.Current().kind") == "mill"
    wow.slash("/bbook mill crafting")  # a chapter without rumours says so
    assert "Nothing in the mill for this chapter today." in both(wow)
    assert wow.errors == []


def test_pages_are_entities_on_the_map_in_the_search_and_on_browser_pages(wow: WowRuntime):
    boot(wow, CORE, DATA, STRAT, BROWSER)
    e = "Bastians:Entity('page:hogger-camp')"
    assert wow.eval(f"{e}:Name()") == "Hogger's Camp"
    assert wow.eval(f"{e}:Summary()") == "Farming and easy kills, level 9-12"
    loc = wow.eval(f"{e}:Locations()[1]")
    assert (loc.map, loc.x, loc.y) == (1429, 0.285, 0.83)
    # the Rumours layer: a pin on the page's place for an open page
    pins = wow.eval(
        f"{MOD}.Strategies.RumourPins({{ continent = 0, x1 = -1e9, y1 = -1e9, x2 = 1e9, y2 = 1e9 }})"
    )
    refs = [p.ref for p in pins.values()]
    assert refs == ["page:hogger-camp"] or refs == []  # [] where the client has no transform
    # the page's action opens it in the book
    assert (
        wow.eval("Bastians:GetPrimaryAction('page:hogger-camp', { source = 'map' }).id")
        == "strategies.open"
    )
    wow.execute("Bastians:RunAction('strategies.open', 'page:hogger-camp', { source = 'map' })")
    assert wow.eval(f"{WIN}.Current().id") == "hogger-camp"
    # the search finds pages
    wow.execute(
        "STRAT_HITS = nil; Bastians:Search('hogger', { limit = 10, types = { page = true } }, "
        "function(results, done) if done then STRAT_HITS = results end end)"
    )
    wow.run_frames(20)
    assert [h.ref for h in wow.eval("STRAT_HITS").values()] == ["page:hogger-camp"]
    # Hogger's Browser page says which page of the book names him; with the Browser a place opens there
    sections = wow.eval("Bastians:GetDetailSections('npc:448')")
    book = next(s for s in sections.values() if s.id == "strategies.pages")
    assert [r.ref for r in book.rows.values()] == ["page:hogger-camp"]
    assert wow.eval(f"{WIN}.OpenRef('npc:448')") == "browser"
    assert wow.eval("Bastians:GetModule('Browser').Browser.ShownPage()") == "npc:448"
    assert wow.errors == []
