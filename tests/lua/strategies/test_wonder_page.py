"""The wonder's page (W7 of plan-suite-waves.md; book.md "The wonder's page", R4.4; book-look.md
10.5): a spread of two paper pages; how to get it as a row per source, each a link with where it
is, its level, the odds or a vendor's price, Show on map and Route there; what it gives as links;
the acts as tools at the foot. The wonders come from the fixture book pack the generator built."""

from harness import WowRuntime
from test_book_pages import MOD, WIN, boot, click_row, text_of

S = "Bastians.UI.Style"
SRC = f"{MOD}.Sources"
RIGHT = f"{WIN}.right"
LEFT = f"{WIN}.left"


def show(wow: WowRuntime, wid: str) -> None:
    wow.execute(f"{WIN}.Show({{ kind = 'wonder', id = '{wid}' }})")


def test_the_odds_read_as_a_reader_says_them(wow: WowRuntime):
    boot(wow)
    odds = f"{SRC}.Odds"
    assert wow.eval(f"{odds}(2)") == "1 in 50"
    assert wow.eval(f"{odds}(0.4)") == "1 in 250"
    assert wow.eval(f"{odds}(12.5)") == "1 in 8"
    assert wow.eval(f"{odds}(24.9)") == "1 in 4"
    assert wow.eval(f"{odds}(25)") == "about 25 %" and wow.eval(f"{odds}(40.4)") == "about 40 %"
    assert wow.eval(f"{odds}(100)") == "about 100 %"
    # unknown is nothing, never "0" (golden rule 2)
    for unknown in ("nil", "0", "-1", "'x'"):
        assert wow.eval(f"{odds}({unknown})") is None, unknown


def test_a_source_reads_its_facts_from_the_packs(wow: WowRuntime):
    boot(wow)
    wow.execute(f"E = {MOD}.Front.Find('pet:10675'); ROWS = {SRC}.Of(E)")
    assert wow.eval("#ROWS") == 3
    hogger = "ROWS[1]"
    assert wow.eval(f"{hogger}.how") == "drop" and wow.eval(f"{hogger}.ref") == "npc:448"
    assert wow.eval(f"{hogger}.name") == "Hogger" and wow.eval(f"{hogger}.glyph") == "mob"
    assert wow.eval(f"{hogger}.zoneName") == "Elwynn Forest" and wow.eval(f"{hogger}.zone") == 1429
    assert wow.eval(f"{hogger}.levelMin") == 11
    assert wow.eval(f"{hogger}.odds") == "about 46 %" and wow.eval(f"{hogger}.price") is None
    assert wow.eval(f"{SRC}.Where({hogger})") == "Elwynn Forest  -  level 11"
    assert wow.eval("ROWS[2].odds") == "1 in 8"
    vendor = "ROWS[3]"
    assert wow.eval(f"{vendor}.how") == "vendor" and wow.eval(f"{vendor}.glyph") == "vendor"
    assert wow.eval(f"{vendor}.price") == 260 and wow.eval(f"{vendor}.odds") is None
    # a quest: no odds, no price; what the packs do not know stays unknown
    wow.execute(f"Q = {SRC}.Of({MOD}.Front.Find('pet:10683'))[1]")
    assert wow.eval("Q.how") == "quest" and wow.eval("Q.name") == "The Fargodeep Mine"
    assert wow.eval("Q.odds") is None and wow.eval("Q.price") is None
    # a source no pack knows is left out, a wonder without sources has none
    wow.execute(
        f"NONE = {SRC}.Of({{ id = 'x', from = {{ {{ 'drop', 'npc:999999' }} }}, gives = {{ 1 }} }})"
    )
    assert wow.eval("#NONE") == 0 and wow.eval(f"#{SRC}.Of({{ id = 'y' }})") == 0
    assert wow.errors == []


def test_the_page_is_a_spread_of_paper_with_the_title_at_27(wow: WowRuntime):
    boot(wow)
    show(wow, "pet:10675")
    for page in (LEFT, RIGHT):
        assert wow.eval(f"{page}.onPaper") is True
        assert wow.eval(f"{S}.painted[{page}.bg][1] == {S}.C.folioPaper") is True
        assert wow.eval(f"{page}.shadow[1]:IsShown()") is True
    right = text_of(wow, "right")
    assert right[0] == "pet  -  from drop" or right[0].startswith("pet")  # the kind, small capitals
    title = f"{RIGHT}.fs[2]"
    assert wow.eval(f"{title}:GetText()") == wow.eval(f"{MOD}.Front.Find('pet:10675').title")
    assert tuple(wow.eval(f"{title}:GetFont()"))[:2] == (
        wow.eval(f"{S}.BOOK_FONTS.bookDisplay"),
        27,
    )
    assert wow.eval(f"{S}.inked[{title}] == {S}.C.folioInk") is True  # the paper's ink
    assert wow.eval(f"{RIGHT}.rules[1]:IsShown()") is True  # a rule under the head
    # the plate on a mat of 5, 2 : 1, on the left page
    w = wow.eval(f"{LEFT}.width")
    assert wow.eval(f"{LEFT}.wonderMat:IsShown()") is True
    assert tuple(wow.eval(f"{LEFT}.wonderPic:GetSize()")) == (w - 10, (w - 10) // 2)
    # another page takes the theme's ground again and the wonder's parts go
    wow.execute(f"{WIN}.Show({{ kind = 'title' }})")
    for page in (LEFT, RIGHT):
        assert wow.eval(f"{page}.onPaper") is None
        assert wow.eval(f"{S}.painted[{page}.bg][1] == {S}.C.panel") is True
        assert wow.eval(f"{page}.shadow[1]:IsShown()") is False
    assert wow.eval(f"{LEFT}.wonderMat:IsShown()") is False
    assert wow.eval(f"{RIGHT}.sources[1]:IsShown()") is False
    assert wow.errors == []


def test_how_to_get_it_is_a_row_per_source(wow: WowRuntime):
    boot(wow)
    show(wow, "pet:10675")
    assert "how to get it" in text_of(wow, "right")
    assert wow.eval(f"{RIGHT}.nsources") == 3
    row = f"{RIGHT}.sources[1]"
    assert wow.eval(f"{row}:GetHeight()") == 40
    assert wow.eval(f"{row}.glyph:GetWidth()") == 20
    assert wow.eval(f"{row}.name.text:GetText()") == "Hogger"
    assert wow.eval(f"{row}.name.ref") == "npc:448"
    assert wow.eval(f"(select(2, {row}.name.text:GetFont()))") == 13
    assert wow.eval(f"{row}.zone.text:GetText()") == "Elwynn Forest"
    assert wow.eval(f"{row}.zone.ref") == "zone:1429"
    assert wow.eval(f"{row}.where:GetText()") == "-  level 11"
    assert wow.eval(f"{row}.odds:GetText()") == "about 46 %"
    # a vendor's row shows the price in coins, no odds
    vendor = f"{RIGHT}.sources[3]"
    assert wow.eval(f"{vendor}.name.text:GetText()") == "Corina Steele"
    assert "2" in wow.eval(f"{vendor}.odds:GetText()")  # 2 silver 60 copper, as Core writes money
    # a link on paper: the paper's ink over a line in the paper's edge, the seal's red under the mouse
    link = f"{row}.name"
    assert wow.eval(f"{S}.inked[{link}.text] == {S}.C.folioInk") is True
    assert wow.eval(f"{S}.painted[{link}.line][1] == {S}.C.folioPaperEdge") is True
    assert wow.eval(f"{link}.line:GetHeight()") == 1
    wow.execute(f"{link}:GetScript('OnEnter')({link})")
    assert wow.eval(f"{S}.inked[{link}.text] == {S}.C.folioSeal") is True
    wow.execute(f"{link}:GetScript('OnLeave')({link})")
    assert wow.eval(f"{S}.inked[{link}.text] == {S}.C.folioInk") is True
    # a left click opens the thing (Core's focus without the Browser), a right click its menu
    wow.execute(
        """
        FOCUSED = nil
        local w = Bastians:NewModule("WonderPageWatch", { addon = "Bastians_Core" })
        w:On("BASTIANS_ENTITY_FOCUSED", function(_, _, ref) FOCUSED = ref end)
        """
    )
    wow.execute(f"{link}:GetScript('OnClick')({link}, 'LeftButton')")
    assert wow.eval("FOCUSED") == "npc:448"
    wow.execute(f"{link}:GetScript('OnClick')({link}, 'RightButton')")
    assert wow.errors == []


def test_what_it_gives_and_the_acts(wow: WowRuntime):
    boot(wow)
    show(wow, "pet:10675")
    right = text_of(wow, "right")
    assert "it gives" in right
    assert "Mark done" in right and "Bookmark" in right
    # the main act is the one filled plate, 28 high; the others words in an outline
    wow.execute(
        f"""
        ACTS = {{}}
        for i = 1, {RIGHT}.ntools do
          local b = {RIGHT}.tools[i]
          ACTS[b.spec.label] = b
        end
        """
    )
    assert wow.eval("ACTS['Mark done'].spec.primary") is True
    assert wow.eval("ACTS['Mark done']:GetHeight()") == 28
    assert (
        wow.eval("ACTS['Bookmark'].spec.boxed") is True
        and wow.eval("ACTS['Bookmark'].spec.primary") is None
    )
    # the item it gives is a link to the item
    wow.execute(
        f"""
        ITEM = nil
        for i = 1, {RIGHT}.nlinks do
          local b = {RIGHT}.links[i]
          if b.ref and b.ref:find("^item:") then ITEM = b end
        end
        """
    )
    assert wow.eval("ITEM.ref") == "item:2589"
    click_row(wow, "right", "Mark done")
    assert wow.eval(f"{MOD}.Record.IsDone('pet:10675')") is True
    right = text_of(wow, "right")
    assert "Not done yet" in right and any(t.startswith("Marked done on") for t in right)
    assert wow.errors == []


def test_more_sources_than_five_wait_behind_a_link(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"""
        local e = {MOD}.Front.Find('pet:10675')
        KEEP = e.from
        e.from = {{}}
        for i = 1, 4 do
          e.from[#e.from + 1] = {{ "drop", "npc:448" }}
          e.from[#e.from + 1] = {{ "drop", "npc:327" }}
        end
        """
    )
    show(wow, "pet:10675")
    assert wow.eval(f"{RIGHT}.nsources") == 5
    assert "3 more sources" in text_of(wow, "right")
    click_row(wow, "right", "3 more sources")
    assert wow.eval(f"{RIGHT}.nsources") == 8
    assert "3 more sources" not in text_of(wow, "right")
    wow.execute(f"{MOD}.Front.Find('pet:10675').from = KEEP")
    assert wow.errors == []


def test_without_a_source_the_sentence_stays(wow: WowRuntime):
    boot(wow)
    show(wow, "chain:sleeping-bag")  # a chain: no reference, its start as a sentence
    right = text_of(wow, "right")
    assert "how to get it" in right and "a charred note" in right
    assert wow.eval(f"{RIGHT}.nsources") == 0
    # a wonder with neither shows no such block
    wow.execute(
        f"""
        local e = {MOD}.Front.Find('pet:10675')
        KEEP, e.from = e.from, nil
        KEEPS, e.start = e.start, nil
        """
    )
    show(wow, "pet:10675")
    assert "how to get it" not in text_of(wow, "right")
    wow.execute(f"local e = {MOD}.Front.Find('pet:10675'); e.from, e.start = KEEP, KEEPS")
    assert wow.errors == []
