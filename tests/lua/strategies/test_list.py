"""Bastian's Book: a shelf as a list (W8 of plan-suite-waves.md, R4.10; book.md "The views", E4;
book-look.md 10.4): the views and their default (pure), the two sorts the columns add (pure),
the columns' places, a source in words, the rows in the window with their head, the switch on
the filter band and its choice kept per chapter and character, and 2,000 wonders at the cost of
a screenful of rows."""

from harness import WowRuntime

CORE, DATA, STRAT = "Bastians_Core", "Bastians_Data", "Bastians_Strategies"
MOD = "Bastians:GetModule('Strategies')"
WIN = f"{MOD}.Window"
FRONT = f"{MOD}.Front"
SHELF = f"{MOD}.Shelf"
LIST = f"{MOD}.List"
S = "Bastians.UI.Style"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA, STRAT)
    wow.run_frames(10)
    wow.advance(0.3)
    wow.execute('Bastians:GetService("data"):LoadPack("book")')
    wow.run_frames(5)
    return wow


def size(wow: WowRuntime, w: int = 1100, h: int = 560) -> None:
    """The mock does not size frames from their anchors: the view's room by hand, then a render."""
    wow.execute(
        f"""
        local F = {FRONT}
        F.view:SetSize({w}, {h})
        local room = {h} - F.TABLE_TOP - F.view.filters:GetHeight()
        F.view.body:SetSize({w}, room + F.TABLE_TOP)
        F.view.shelf:SetSize({w} - 2 * F.BAND_SIDE + 10, room)
        F.list.scroll:SetSize({w} - 2 * F.BAND_SIDE, room)
        {WIN}.Render()
        """
    )


def kinds(wow: WowRuntime) -> list[str]:
    wow.execute(
        f"KINDS = {{}} for _, item in ipairs({FRONT}.list.items) do KINDS[#KINDS + 1] = item.kind end"
    )
    return list(wow.eval("KINDS").values())


def rows(wow: WowRuntime) -> None:
    """ROWS: the list's row frames in view, top first; HEAD: the head row."""
    wow.execute(
        f"""
        ROWS, HEAD = {{}}, nil
        for _, f in ipairs({FRONT}.list:Rows()) do
          if f.vlKind == "row" and f:IsShown() then ROWS[#ROWS + 1] = f end
          if f.vlKind == "listhead" and f:IsShown() then HEAD = f end
        end
        """
    )


def test_a_shelf_opens_as_tiles_and_collections_as_a_list(wow: WowRuntime):
    boot(wow)
    view = f"{SHELF}.ViewOf"
    assert wow.eval(f"{view}(nil, 'collections')") == "list"  # E4, decided on the book's board
    for chapter in ("all", "gold", "secrets", "camp", "rares"):
        assert wow.eval(f"{view}(nil, '{chapter}')") == "tiles"
    # the reader's own choice wins; a value no view has does not
    assert wow.eval(f"{view}({{ collections = 'tiles' }}, 'collections')") == "tiles"
    assert wow.eval(f"{view}({{ rares = 'list' }}, 'rares')") == "list"
    assert wow.eval(f"{view}({{ rares = 'table' }}, 'rares')") == "tiles"
    assert wow.eval(f"{view}({{ rares = 'list' }}, 'camp')") == "tiles"  # per chapter


def test_the_columns_add_two_sorts(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"""
        local function ids(list) local o = {{}} for i, e in ipairs(list) do o[i] = e.id end
          return table.concat(o, " ") end
        local list = {{
          {{ id = "a", title = "Zebra", from = {{ {{ "vendor", "npc:1" }} }} }},
          {{ id = "b", title = "apple", from = {{ {{ "drop", "npc:2" }} }} }},
          {{ id = "c", title = "Mule" }},
          {{ id = "d", title = "Bear", from = {{ {{ "drop", "npc:3" }} }} }},
        }}
        HOW = ids({SHELF}.Sort(list, "how", {{}}))
        local at = {{ a = 100, d = 300 }}
        HAVE = ids({SHELF}.Sort(list, "have", {{ doneAt = function(id) return at[id] end }}))
        BARE = ids({SHELF}.Sort(list, "have", {{}}))
        """
    )
    # by the way to get it, then the name; a wonder without a source last
    assert wow.eval("HOW") == "b d a c"
    # the reader's own first, the newest mark first; then the names
    assert wow.eval("HAVE") == "d a b c"
    assert wow.eval("BARE") == "b d c a"  # nothing known: the names alone


def test_the_columns_follow_the_window(wow: WowRuntime):
    boot(wow)
    cols = f"{LIST}.Columns"
    # a window 1,100 wide (the table 1,070): the picture, the name to 40 %, the rest, 170
    c = wow.eval(f"{cols}(1070)")
    assert (c.name.x, c.name.w) == (39, 375)
    assert (c.how.x, c.how.w) == (425, 464)
    assert (c.have.x, c.have.w) == (900, 170)
    # a narrow one: the name's column never ends before 320, how to get it keeps its least
    c = wow.eval(f"{cols}(570)")
    assert c.name.x + c.name.w == 320 - 15 - 11 and c.how.x == 305
    assert c.have.x == 425 and c.have.w == 145


def test_a_source_in_words(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"""
        local words = {FRONT}.SourceWords()
        local rows = {{
          {{ how = "drop", ref = "npc:1", name = "Dalaran Spellscribe", glyph = "mob",
            zoneName = "Silverpine Forest", levelMin = 12, levelMax = 13, odds = "1 in 50" }},
          {{ how = "vendor", ref = "npc:2", name = "A Vendor" }},
        }}
        A = {LIST}.How(rows, 12, words)
        B_ = {LIST}.How({{ {{ how = "fish", ref = "object:9", name = "A pool", glyph = "fish" }} }},
          12, words)
        NONE = {LIST}.How({{}}, 12, words)
        GOLD = {S}.H.folioGold
        """
    )
    assert wow.eval("A.word") == "a drop" and wow.eval("A.name") == "Dalaran Spellscribe"
    assert wow.eval("A.ref") == "npc:1" and wow.eval("A.more") == 1
    gold = wow.eval("GOLD")
    # the level that holds the reader's stands in gold; the odds as a reader says them
    assert wow.eval("A.rest") == f", Silverpine Forest, {gold}level 12 to 13|r, 1 in 50"
    # a way the filter has no word for says none; nothing known says nothing (never a zero)
    assert wow.eval("B_.word") is None and wow.eval("B_.rest") == "" and wow.eval("B_.more") == 0
    assert wow.eval("NONE") is None


def test_collections_reads_as_a_list_with_a_head_that_sorts(wow: WowRuntime):
    boot(wow)
    wow.slash("/bbook collections")
    wow.execute(f"{FRONT}.Filter('collections').unconfirmed = true")
    size(wow)
    k = kinds(wow)
    assert k[0] == "result" and k[1] == "listhead" and set(k[2:]) == {"row"}
    n = len(k) - 2
    assert n >= 3 and wow.eval(f"{FRONT}.list.items[1].title") == f"{n} wonders"
    rows(wow)
    assert wow.eval("#ROWS") == n and wow.eval("ROWS[1]:GetHeight()") == 36
    assert wow.eval("HEAD:GetHeight()") == 24
    # a row: the picture 28, the name, the columns at the window's places
    assert tuple(wow.eval("ROWS[1].pic:GetSize()")) == (28, 28)
    assert wow.eval("ROWS[1].name:GetText()") == wow.eval("ROWS[1].entry.title")
    assert wow.eval("(select(4, ROWS[1].name:GetPoint(1)))") == 39
    assert wow.eval("ROWS[1].name:GetWidth()") == 375
    # the head: the three names in small capitals, none sorted while the shelf is "newest"
    assert wow.eval("HEAD.cols.name.text:GetText()") == "name"
    assert wow.eval("HEAD.cols.how.text:GetText()") == "how to get it"
    assert wow.eval("HEAD.cols.have.text:GetText()") == "done"
    assert wow.eval("HEAD.cols.name.arrow:IsShown()") is False
    assert wow.eval(f"{S}.inked[HEAD.cols.name.text] == {S}.C.folioMuted") is True
    # a click on Name sorts A to Z: the head in gold with its arrow, the rows by name
    wow.execute("HEAD.cols.name:Click()")
    size(wow)
    rows(wow)
    assert wow.eval(f"{FRONT}.Filter('collections').sort") == "az"
    assert wow.eval("HEAD.cols.name.arrow:IsShown()") is True
    assert wow.eval(f"{S}.inked[HEAD.cols.name.text] == {S}.C.folioGold") is True
    names = [wow.eval(f"ROWS[{i}].entry.title") for i in range(1, n + 1)]
    assert names == sorted(names, key=str.lower)
    # a click on a row opens the wonder; the page turns to the row's neighbours
    first, second = wow.eval("ROWS[1].entry.id"), wow.eval("ROWS[2].entry.id")
    wow.execute("ROWS[1]:Click()")
    assert wow.eval(f"{WIN}.Current().id") == first
    wow.execute(f"{WIN}.Turn(1)")
    assert wow.eval(f"{WIN}.Current().id") == second
    assert wow.errors == []


def test_a_row_says_how_to_get_it_and_who_has_it(wow: WowRuntime):
    boot(wow)
    wow.slash("/bbook collections")
    wow.execute(f"{FRONT}.Filter('collections').unconfirmed = true")
    size(wow)
    rows(wow)
    n = wow.eval("#ROWS")
    # every row whose wonder names a source the packs know shows it: the pictogram, the link
    sourced = 0
    for i in range(1, n + 1):
        row = f"ROWS[{i}]"
        if wow.eval(f"{row}.how ~= nil"):
            sourced += 1
            assert wow.eval(f"{row}.link:IsShown()") is True
            assert wow.eval(f"{row}.link.ref") == wow.eval(f"{row}.how.ref")
            assert wow.eval(f"{row}.link.text:GetText()") == wow.eval(f"{row}.how.name")
            assert wow.eval(f"{row}.glyph:IsShown()") is True
        else:
            assert wow.eval(f"{row}.link:IsShown()") is False
            assert wow.eval(f"{row}.glyph:IsShown()") is False
    # nobody has anything yet: no stamp, no words
    assert wow.eval("ROWS[1].stamp:IsShown()") is False
    assert wow.eval("ROWS[1].have:IsShown()") is False
    # a mark of this character: the stamp in gold and its date
    wid = wow.eval("ROWS[1].entry.id")
    wow.execute(f"{MOD}.Record.Mark('{wid}', 'mark', 1795000000, 'x')")
    wow.execute(f"{FRONT}.Filter('collections').showDone = true")
    size(wow)
    wow.execute(
        f"""
        MINE = nil
        for _, f in ipairs({FRONT}.list:Rows()) do
          if f.vlKind == "row" and f:IsShown() and f.entry.id == "{wid}" then MINE = f end
        end
        """
    )
    assert wow.eval("MINE.stamp:IsShown()") is True
    assert wow.eval(f"{S}.painted[MINE.stamp][1] == {S}.C.folioGold") is True
    assert wow.eval("MINE.have:GetText()") == wow.eval("date('%d.%m.%Y', 1795000000)")
    # the column's head sorts the reader's own to the top
    rows(wow)
    wow.execute("HEAD.cols.have:Click()")
    size(wow)
    rows(wow)
    assert wow.eval("ROWS[1].entry.id") == wid
    assert sourced >= 0 and wow.errors == []


def test_the_switch_changes_the_view_and_keeps_the_choice(wow: WowRuntime):
    boot(wow)
    wow.slash("/bbook rares")
    size(wow)
    switch = f"{FRONT}.view.viewSwitch"
    assert wow.eval(f"{switch}:IsShown()") is True and wow.eval(f"{switch}.view") == "tiles"
    assert tuple(wow.eval(f"{switch}.list:GetSize()")) == (20, 20)
    assert wow.eval(f"{S}.painted[{switch}.tiles.icon][1] == {S}.C.folioGold") is True
    assert wow.eval(f"{S}.painted[{switch}.list.icon][1] == {S}.C.folioMuted") is True
    assert "tiles" in kinds(wow) and "row" not in kinds(wow)
    wow.execute(f"{switch}.list:Click()")
    size(wow)
    assert wow.eval(f"{switch}.view") == "list"
    assert "row" in kinds(wow) and "tiles" not in kinds(wow)
    assert wow.eval(f"{S}.painted[{switch}.list.icon][1] == {S}.C.folioGold") is True
    # kept for this character and this chapter (it survives a /reload with the saved variables)
    assert wow.eval(f"{MOD}.db.char.views.rares") == "list"
    assert wow.eval(f"{FRONT}.View('camp')") == "tiles"
    # Gold is always newest first: its list's head does not sort
    wow.slash("/bbook gold")
    wow.execute(f"{FRONT}.SetView('gold', 'list')")
    size(wow)
    assert wow.eval(f"{FRONT}.list.items[2].kind") == "listhead"
    assert wow.eval(f"{FRONT}.list.items[2].onSort") is None
    # the front table has no shelf, so no switch
    wow.slash("/bbook")
    wow.execute(f"{WIN}.Show({{ kind = 'front' }})")
    assert wow.eval(f"{switch}:IsShown()") is False
    assert wow.errors == []


def test_two_thousand_wonders_as_a_list_cost_a_screenful_of_rows(wow: WowRuntime):
    boot(wow)
    wow.slash("/bbook simulate 2000")
    wow.execute(f"{FRONT}.SetView('all', 'list')")
    size(wow)
    # a row each; the unconfirmed stay behind their chip
    assert wow.eval(f"#{FRONT}.list.items") > 1500
    for offset in (0, 3000, 9000, 40000):
        wow.execute(f"{FRONT}.list.scroll:SetVerticalScroll({offset}); {FRONT}.list:Render()")
    wow.execute(
        f"""
        FRAMES = 0
        for _, pool in pairs({FRONT}.list.pools or {{}}) do FRAMES = FRAMES + #pool end
        FRAMES = FRAMES + #({FRONT}.list.used or {{}})
        """
    )
    assert 0 < wow.eval("FRAMES") <= 40  # a room 536 high holds 15 rows of 36
    wow.slash("/bbook simulate 0")
    assert wow.errors == []
