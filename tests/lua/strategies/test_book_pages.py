"""Bastian's Book in the window (book.md "The pages", ADR 0080): the front table, a chapter's page
with its filter, the details page of every kind of wonder, Your record; the wonders come from the
fixture book pack the generator built (tests/fixtures/forever-wonders)."""

from harness import WowRuntime

CORE, DATA, STRAT = "Bastians_Core", "Bastians_Data", "Bastians_Strategies"
MOD = "Bastians:GetModule('Strategies')"
WIN = f"{MOD}.Window"
FRONT = f"{MOD}.Front"
REC = f"{MOD}.Record"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA, STRAT)
    wow.run_frames(10)
    wow.advance(0.3)
    wow.execute('Bastians:GetService("data"):LoadPack("book")')
    wow.run_frames(5)
    return wow


def size(wow: WowRuntime, w: int = 928, h: int = 560) -> None:
    """The mock does not size frames from their anchors: the view's room by hand, then a render."""
    wow.execute(
        f"""
        local F = {FRONT}
        F.view:SetSize({w}, {h})
        local room = {h} - F.TABLE_TOP - F.view.filters:GetHeight()
        F.view.body:SetSize({w}, room + F.TABLE_TOP)
        F.view.shelf:SetSize({w} - 2 * F.BAND_SIDE + 10, room)  -- the table's padding, the bar's room
        F.list.scroll:SetSize({w} - 2 * F.BAND_SIDE, room)
        {WIN}.Render()
        """
    )


def tiles(wow: WowRuntime) -> list[str]:
    return list(wow.eval(f"{FRONT}.TilesInView()").values())


def heads(wow: WowRuntime) -> list[str]:
    """The headings of the list's items (in view or not)."""
    wow.execute(
        f"""
        HEADS = {{}}
        for _, item in ipairs({FRONT}.list.items) do
          if item.kind == "head" or item.kind == "result" then HEADS[#HEADS + 1] = item.title end
        end
        """
    )
    return list(wow.eval("HEADS").values())


def pills(wow: WowRuntime) -> list[str]:
    wow.execute(
        f"""
        PILLS = {{}}
        for _, p in ipairs({FRONT}.view.pills) do
          if p:IsShown() then PILLS[#PILLS + 1] = p.spec.label end
        end
        """
    )
    return list(wow.eval("PILLS").values())


def level(wow: WowRuntime, lo: int, hi: int) -> None:
    """The level's range slider let go at lo..hi."""
    wow.execute(f"{FRONT}.view.slider:Commit({lo}, {hi})")
    size(wow)


def unconfirmed(wow: WowRuntime, chapter: str) -> None:
    """The chapter's shelf with what nobody reported in Forever yet (the chip, E2)."""
    wow.execute(f"{FRONT}.Filter('{chapter}').unconfirmed = true")
    size(wow)


def click_pill(wow: WowRuntime, label: str) -> None:
    wow.execute(
        f"""
        for _, p in ipairs({FRONT}.view.pills) do
          if p:IsShown() and p.spec.label == "{label}" then p:Click() return end
        end
        error("no pill {label}")
        """
    )
    size(wow)


def text_of(wow: WowRuntime, side: str) -> list[str]:
    wow.execute(
        f"""
        TEXTS = {{}}
        local page = {WIN}.{side}
        for i = 1, page.nfs do TEXTS[#TEXTS + 1] = page.fs[i]:GetText() end
        for i = 1, page.nrows do TEXTS[#TEXTS + 1] = page.rows[i].label:GetText() end
        """
    )
    return list(wow.eval("TEXTS").values())


def click_row(wow: WowRuntime, side: str, label: str) -> None:
    wow.execute(
        f"""
        local page = {WIN}.{side}
        for i = 1, page.nrows do
          if page.rows[i].label:GetText() == "{label}" then page.rows[i]:Click() return end
        end
        error("no row {label}")
        """
    )


def test_the_front_table_shows_the_newest_and_a_strip_per_chapter(wow: WowRuntime):
    boot(wow)
    wow.slash("/bbook")
    assert wow.eval(f"{WIN}.Current().kind") == "front"
    size(wow)
    assert wow.eval(f"{FRONT}.view:IsShown()") is True
    assert wow.eval(f"{WIN}.left:IsShown()") is False
    shown = heads(wow)
    assert shown[0] == "New on the table"
    assert {"Secrets", "Collections", "Camp", "Rares"} <= set(shown)
    assert "Treasures" not in shown and "Curiosities" not in shown  # E1: they are dissolved
    assert tiles(wow)  # pictures on the table
    # E2: what nobody reported in Forever yet is never on the front table
    wow.execute(
        f"""
        ONTABLE = {{}}
        for _, item in ipairs({FRONT}.list.items) do
          if item.entry then ONTABLE[item.entry.id] = true end
          for _, e in ipairs(item.entries or {{}}) do ONTABLE[e.id] = true end
        end
        """
    )
    table = set(wow.eval("ONTABLE").keys())
    assert {"mount:5784", "rare:61", "title:144"} <= table
    assert not table & {"mount:458", "pet:4055", "pet:10675", "rare:99", "rare:5912", "title:1258"}
    assert wow.errors == []


def test_a_chapters_page_filters_by_clicks(wow: WowRuntime):
    boot(wow)
    wow.slash("/bbook collections")
    size(wow)
    assert wow.eval(f"{WIN}.bar.tabs.spec.value") == "collections"  # the chosen part filled
    labels = pills(wow)
    assert "Everywhere" in labels
    assert wow.eval(f"{FRONT}.view.hide.words:GetText()") == "Hide done"  # a switch, on
    assert wow.eval(f"{FRONT}.view.hide.on") is True
    assert {"mount", "pet", "title"} <= set(labels)  # the chapter's own facet
    assert set(tiles(wow)) == {"mount:5784", "pet:10683", "title:144"}  # what is in Forever
    unconfirmed(wow, "collections")
    every = {"mount:458", "mount:5784", "pet:4055", "pet:10675", "pet:10683"}
    assert set(tiles(wow)) == every | {"title:144", "title:1258"}
    click_pill(wow, "mount")
    assert set(tiles(wow)) == {"mount:458", "mount:5784"}
    assert heads(wow)[0] == "2 wonders"
    wow.execute(f"{FRONT}.Filter('collections').facets = {{}}")
    size(wow)
    level(wow, 40, 50)  # the riding level: the title of 55 leaves, what has no band stays
    assert "40 to 50" in pills(wow)  # the chosen range as a chip beside the slider
    assert set(tiles(wow)) == every | {"title:1258"}
    assert wow.errors == []


def test_what_nobody_reported_yet_waits_behind_one_chip(wow: WowRuntime):
    """E2 ("remove all things that are not obtainable in wow forever", "these
    three states"): a wonder that is in the client and nobody saw is off the shelf until the chip
    "unconfirmed" is on; the chip says how many it would add; its page says so."""
    boot(wow)
    wow.slash("/bbook rares")
    size(wow)
    assert tiles(wow) == ["rare:61"]
    assert heads(wow)[0] == "1 wonders"
    chip = f"""
        (function()
          for _, p in ipairs({FRONT}.view.pills) do
            if p:IsShown() and p.spec.label == "unconfirmed" then return p end
          end
        end)()
    """
    assert wow.eval(f"{chip}.spec.count") == 2 and wow.eval(f"{chip}.spec.on") is None
    assert "nobody has reported it" in wow.eval(f"{chip}.tip")
    click_pill(wow, "unconfirmed")
    assert set(tiles(wow)) == {"rare:61", "rare:99", "rare:5912"}
    assert wow.eval(f"{chip}.spec.on") is True and wow.eval(f"{chip}.spec.count") == 2
    click_pill(wow, "unconfirmed")
    assert tiles(wow) == ["rare:61"]
    # a chapter where everything is in has no chip
    wow.slash("/bbook camp")
    size(wow)
    assert "unconfirmed" not in pills(wow)
    assert set(tiles(wow)) == {"camp:279956", "camp:279981", "chain:camping-elwynn"}
    # a search that finds only an unconfirmed wonder says so with the chip
    wow.slash("/bbook all")
    wow.execute(f"{WIN}.Search('dustwallow horse')")
    size(wow)
    assert tiles(wow) == [] and "unconfirmed" in pills(wow)
    # the wonder's page says it, in place of "Classic data, may differ in Forever"
    wow.execute(f"{WIN}.Show({{ kind = 'wonder', id = 'rare:99' }})")
    both = text_of(wow, "left") + text_of(wow, "right")
    assert any("nobody has reported it in Forever yet" in t for t in both)
    wow.execute(f"{WIN}.Show({{ kind = 'wonder', id = 'rare:61' }})")
    both = text_of(wow, "left") + text_of(wow, "right")
    assert not any("nobody has reported it" in t or "Classic data" in t for t in both)
    assert wow.errors == []


def test_the_five_chapters_say_what_they_are(wow: WowRuntime):
    """E1: Gold, Secrets, Collections,
    Camp, Rares; a chapter's sentence at the head of its shelf and as its tab's tip; the camp's own
    facets."""
    boot(wow)
    wow.slash("/bbook")
    tabs = f"{WIN}.bar.tabs"
    order = [p.item.id for p in wow.eval(f"{tabs}.parts").values()]
    assert order == ["front", "all", "gold", "secrets", "collections", "camp", "rares"]
    assert wow.eval(f"{tabs}:Part('camp').tip") == "What you can build at your own fire."
    assert wow.eval(f"{tabs}:Part('all').tip") is None
    wow.slash("/bbook secrets")
    size(wow)
    assert wow.eval(f"{tabs}.spec.value") == "secrets"
    assert set(tiles(wow)) == {
        "chain:sleeping-bag",
        "chain:musical-gustjumper",
        "chain:keystone-fragment",
    }
    line = "What the world hides, and what nobody has solved yet."
    assert wow.eval(f"{FRONT}.list.items[1].note") == line  # an unfiltered shelf: its sentence
    assert {"chain", "pet", "unsolved"} <= set(pills(wow))
    click_pill(wow, "unsolved")
    assert tiles(wow) == ["chain:keystone-fragment"]
    assert wow.eval(f"{FRONT}.list.items[1].note") == "kind: unsolved"  # a filter: its words
    wow.slash("/bbook camp")
    size(wow)
    assert {"Alchemy", "Cooking", "camp kit", "camp item", "camping"} <= set(pills(wow))
    wow.execute(
        f"""
        SKILLS = {{}}
        for _, p in ipairs({FRONT}.view.pills) do
          if p:IsShown() and tonumber(p.spec.label) then SKILLS[#SKILLS + 1] = p.spec.label end
        end
        """
    )
    assert list(wow.eval("SKILLS").values()) == ["1", "20"]  # the skill needed, the lowest first
    click_pill(wow, "20")
    assert tiles(wow) == ["camp:279956"]
    # a chapter of before round 4 in a macro still leads somewhere
    wow.slash("/bbook treasures")
    assert wow.eval(f"{WIN}.Current().id") == "secrets"
    assert wow.errors == []


def test_gold_is_always_newest_first(wow: WowRuntime):
    """ "gold stories are always sorted by timestamp - newest first"
    (R4.8): the Gold shelf has no sort group; Everything keeps it."""
    boot(wow)
    wow.slash("/bbook gold")
    size(wow)
    assert not {"newest", "nearest", "A to Z"} & set(pills(wow))
    wow.execute(
        f"""
        local labels = {{}}
        for _, fs in ipairs({FRONT}.view.labels) do
          if fs:IsShown() then labels[fs:GetText()] = true end
        end
        HAS_SORT = labels["sort"] == true
        """
    )
    assert wow.eval("HAS_SORT") is False
    first = tiles(wow)
    assert first
    wow.execute(f"{FRONT}.Filter('gold').sort = 'az'")  # a sort left from before changes nothing
    size(wow)
    assert tiles(wow) == first
    wow.slash("/bbook all")
    size(wow)
    assert {"newest", "nearest", "A to Z"} <= set(pills(wow))
    assert wow.errors == []


def test_a_zone_a_continent_and_a_tiles_chip_narrow_the_shelf(wow: WowRuntime):
    boot(wow)
    wow.slash("/bbook rares")
    unconfirmed(wow, "rares")
    assert set(tiles(wow)) == {"rare:61", "rare:99", "rare:5912"}
    assert "Elwynn Forest" not in pills(wow)  # the zones wait for their continent
    click_pill(wow, "Eastern Kingdoms")
    click_pill(wow, "Elwynn Forest")  # the zones with wonders, with their counts
    assert tiles(wow) == ["rare:61"]
    assert wow.eval(f"{FRONT}.Filter('rares').zone") == 1429
    click_pill(wow, "Everywhere")
    assert set(tiles(wow)) == {"rare:61", "rare:99", "rare:5912"}
    # a tile's level chip takes its band
    wow.execute(
        f"""
        for _, row in ipairs({FRONT}.list:Rows()) do
          for _, t in ipairs(row.tiles or {{}}) do
            if t:IsShown() and t.entry.id == "rare:61" then
              for _, p in ipairs(t.chips) do
                if p:IsShown() and p.spec.label == "level 11" then p:Click() end
              end
            end
          end
        end
        """
    )
    size(wow)
    assert (wow.eval(f"{FRONT}.Filter('rares').lo"), wow.eval(f"{FRONT}.Filter('rares').hi")) == (
        11,
        11,
    )
    assert set(tiles(wow)) == {"rare:61", "rare:99"}  # Morgaine's 10 to 12 holds 11 too
    level(wow, 30, 40)
    assert tiles(wow) == []
    assert heads(wow)[0] == "0 wonders"
    assert wow.errors == []


def test_the_search_spans_the_chapters(wow: WowRuntime):
    boot(wow)
    wow.slash("/bbook bag")
    size(wow)
    assert wow.eval(f"{WIN}.Current().id") == "all"
    assert "chain:sleeping-bag" in tiles(wow)
    wow.execute(f"{WIN}.Search('dustwallow horse')")  # every word, the zone's name too
    unconfirmed(wow, "all")
    assert tiles(wow) == ["mount:458"]
    assert wow.errors == []


def test_a_treasure_keeps_its_steps_sealed_until_opened(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{WIN}.Show({{ kind = 'wonder', id = 'chain:sleeping-bag' }})")
    right = text_of(wow, "right")
    assert right[0] == "chain" and right[1] == "Cozy Sleeping Bag"  # small capitals
    assert "I have slept in more barns than most cows." in right  # Bastian's line
    assert "A bedroll you can unroll anywhere." in right  # the source's
    assert "nixie's envelope" in right
    assert not any(t.startswith("1. A note") for t in right)
    assert "Break the seal" in right
    left = text_of(wow, "left")
    assert "where it starts" in left and "a charred note" in left
    assert "it gives" in left
    click_row(wow, "right", "Break the seal")
    right = text_of(wow, "right")
    assert any(t.startswith("1. A note: Read the note.") for t in right)
    assert wow.eval(f"{REC}.IsOpened('chain:sleeping-bag')") is True
    assert wow.errors == []


def test_every_kind_of_wonder_has_its_page(wow: WowRuntime):
    boot(wow)
    for wid in (
        "chain:camping-elwynn",
        "chain:musical-gustjumper",
        "chain:keystone-fragment",
        "mount:458",
        "pet:4055",
        "title:144",
        "rare:61",
        "rare:99",
        "rare:5912",
        "camp:279981",
        "pet:10675",
        "title:1258",
    ):
        wow.execute(f"{WIN}.Show({{ kind = 'wonder', id = '{wid}' }})")
        right = text_of(wow, "right")
        assert right[1] == wow.eval(f"{FRONT}.Find('{wid}').title"), wid
        assert "Mark done" in right, wid
    wow.execute(f"{WIN}.Show({{ kind = 'wonder', id = 'rare:61' }})")
    assert "it drops" in text_of(wow, "left")
    assert wow.errors == []


def test_mark_done_leaves_the_shelf_and_stands_in_your_record(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{WIN}.Show({{ kind = 'wonder', id = 'rare:61' }})")
    click_row(wow, "right", "Mark done")
    assert wow.eval(f"{REC}.IsDone('rare:61')") is True
    assert any(t.startswith("Marked done on") for t in text_of(wow, "right"))
    wow.slash("/bbook rares")
    size(wow)
    assert tiles(wow) == []  # Morgaine and the dragon wait behind the chip
    unconfirmed(wow, "rares")
    assert set(tiles(wow)) == {"rare:99", "rare:5912"}
    # the hidden ones stand beside the switch, a link to Your record
    assert wow.eval(f"{FRONT}.view.done:IsShown()") is True
    assert wow.eval(f"{FRONT}.view.done.text:GetText()") == "1 done, in Your record"
    wow.slash("/bbook record")
    size(wow)
    assert "Done: Rares" in heads(wow)
    assert "rare:61" in tiles(wow)
    # Not done yet, from the record's chip
    wow.execute(
        f"""
        for _, row in ipairs({FRONT}.list:Rows()) do
          for _, t in ipairs(row.tiles or {{}}) do
            if t:IsShown() and t.entry.id == "rare:61" then
              for _, p in ipairs(t.chips) do
                if p:IsShown() and p.spec.label == "Not done yet" then p:Click() end
              end
            end
          end
        end
        """
    )
    assert wow.eval(f"{REC}.IsDone('rare:61')") is False
    assert wow.errors == []


def test_another_characters_done_shows_on_the_tile(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"""
        local g = {MOD}.db.global
        g.record["Bran-Realm"] = {{ name = "Bran", done = {{ ["chain:sleeping-bag"] = {{ how = "mark", at = 1 }} }} }}
        """
    )
    wow.slash("/bbook secrets")
    size(wow)
    assert "chain:sleeping-bag" in tiles(wow)  # not hidden: this character has not done it
    wow.execute(
        f"""
        ALT = nil
        for _, row in ipairs({FRONT}.list:Rows()) do
          for _, t in ipairs(row.tiles or {{}}) do
            if t:IsShown() and t.entry.id == "chain:sleeping-bag" and t.alt:IsShown() then
              ALT = t.alt.text:GetText()
            end
          end
        end
        """
    )
    assert wow.eval("ALT") == "Done by Bran"
    wow.slash("/bbook record")
    size(wow)
    assert "Your other characters" in heads(wow)
    assert wow.errors == []


def test_a_wonder_turns_to_the_next_of_its_shelf(wow: WowRuntime):
    boot(wow)
    wow.slash("/bbook rares")
    unconfirmed(wow, "rares")
    first, second = tiles(wow)[:2]
    wow.execute(f"{WIN}.Show({{ kind = 'wonder', id = '{first}' }})")
    assert wow.eval(f"{WIN}.folio.label:GetText()") == "- 1 of 3 -"
    wow.execute(f"{WIN}.Turn(1)")
    assert wow.eval(f"{WIN}.Current().id") == second
    assert wow.errors == []


def test_two_thousand_wonders_cost_a_screenful_of_frames(wow: WowRuntime):
    boot(wow)
    wow.slash("/bbook simulate 2000")
    size(wow)
    assert wow.eval(f"{WIN}.Current().id") == "all"
    assert wow.eval(f"#{FRONT}.Entries()") > 2000
    for offset in (0, 3000, 9000, 20000):
        wow.execute(f"{FRONT}.list.scroll:SetVerticalScroll({offset}); {FRONT}.list:Render()")
    assert 0 < wow.eval(f"{FRONT}.TileFrames()") <= 60
    click_pill(wow, "Rares")
    assert heads(wow)[0].endswith("wonders")
    wow.slash("/bbook simulate 0")
    assert wow.eval(f"#{FRONT}.Entries()") < 100
    assert wow.errors == []


def first_tile(wow: WowRuntime) -> None:
    """TILE: the first tile in view."""
    wow.execute(
        f"""
        TILE = nil
        for _, row in ipairs({FRONT}.list:Rows()) do
          for _, t in ipairs(row.tiles or {{}}) do
            if t:IsShown() and not TILE then TILE = t end
          end
        end
        """
    )


def test_a_tile_drawn_again_lets_go_of_the_mouse(wow: WowRuntime):
    """ "yellow hover effect does not go away": a tile is paper in every
    look, its edge lit in the book's gold under the mouse only, and plain when the list draws it
    again under a resting mouse."""
    boot(wow)
    wow.slash("/bbook rares")
    size(wow)
    first_tile(wow)
    S = "Bastians.UI.Style"
    paper = f"{S}.painted[TILE.face][1] == {S}.C.folioPaper"
    rim = f"{S}.painted[TILE.edges][2]"
    assert wow.eval(paper) is True and wow.eval(rim) == 0
    wow.execute("TILE:GetScript('OnEnter')(TILE)")
    assert wow.eval(paper) is True and wow.eval(rim) == 1
    wow.execute("TILE:GetScript('OnLeave')(TILE)")
    assert wow.eval(rim) == 0
    wow.execute("TILE:GetScript('OnEnter')(TILE)")
    wow.execute(f"{WIN}.Render()")  # the list hands the frame on, the mouse never left it
    assert wow.eval(rim) == 0
    # paper in the WoW look too: never the theme's card gold
    wow.execute("Bastians.UI.Settings.ApplyPreset(Bastians:GetModule('Core'), 'wow')")
    wow.execute(f"{WIN}.Render()")
    first_tile(wow)
    for state in ("OnEnter", "OnLeave"):
        wow.execute(f"TILE:GetScript('{state}')(TILE)")
        assert wow.eval(paper) is True, state
    assert wow.errors == []


def test_a_card_is_paper_in_the_books_faces_with_a_torn_picture(wow: WowRuntime):
    """ADR 0081: the picture the card's
    whole width with a torn foot, a soft shadow, the words in the book's faces on the paper's ink;
    a chip an outline, a level that fits filled in the gold."""
    boot(wow)
    wow.slash("/bbook rares")
    size(wow)
    first_tile(wow)
    S = "Bastians.UI.Style"
    assert wow.eval("TILE.pic:GetWidth() == TILE:GetWidth()") is True
    assert wow.eval("TILE.pic:GetHeight()") == wow.eval("math.floor(TILE:GetWidth() * 0.5)")
    assert wow.eval("TILE.tear:IsShown()") is True
    assert wow.eval("TILE.tear.tex:GetTexture()") == wow.eval(f"{FRONT}.DECKLE")
    assert wow.eval(f"{S}.painted[TILE.tear.tex][1] == {S}.C.folioPaper") is True
    assert wow.eval("#TILE.shadow") == 8
    fonts = wow.eval(f"{S}.BOOK_FONTS")
    assert wow.eval("(TILE.title:GetFont())") == fonts.bookDisplay
    assert wow.eval("(TILE.hook:GetFont())") == fonts.bookItalic
    assert wow.eval("(TILE.kind:GetFont())") == fonts.bookCaps
    assert wow.eval(f"{S}.inked[TILE.title] == {S}.C.folioInk") is True
    # the chips: an outline on the paper; the one that fits the character's level filled
    wow.execute(
        f"""
        FIT, PLAIN = nil, nil
        for _, row in ipairs({FRONT}.list:Rows()) do
          for _, t in ipairs(row.tiles or {{}}) do
            for _, c in ipairs(t.chips or {{}}) do
              if c:IsShown() then
                if c.fit then FIT = c else PLAIN = c end
              end
            end
          end
        end
        """
    )
    assert wow.eval("select(4, PLAIN.face:GetVertexColor())") == 0
    assert wow.eval(f"{S}.painted[PLAIN.edges][1] == {S}.C.folioPaperEdge") is True
    assert wow.eval("(PLAIN.label:GetFont())") == fonts.bookSans
    assert wow.errors == []


def test_the_tabs_are_words_and_share_the_head_when_there_is_room(wow: WowRuntime):
    """ "tabs yes" (words only) and the concept board's single bar: on a
    wide window the tabs sit in the window's head beside the book's name; a narrow one gives them a
    row of their own; too narrow for the words even there, the pictograms come back."""
    boot(wow)
    wow.slash("/bbook")

    def layout(width: int) -> None:
        wow.execute(
            f"""
            local W = {WIN}
            W.win.frame:SetWidth({width})
            W.win.head:SetWidth({width} - 2)
            W.win.content:SetWidth({width} - 2)
            W.bar.Layout()
            """
        )

    layout(1900)
    assert wow.eval(f"{WIN}.bar.oneBar") is True
    assert wow.eval(f"{WIN}.BarRoom()") == 0  # the band lies directly under the bar
    assert wow.eval(f"{WIN}.bar.tabs.spec.flat") is True
    assert wow.eval(f"{WIN}.bar.tabs.face:IsShown()") is False  # no plate around the words
    assert wow.eval(f"{WIN}.bar.front.item.icon") is None
    assert wow.eval(f"{WIN}.bar.front.label:GetText()") == "front table"
    assert wow.eval(f"({WIN}.bar.front.label:GetFont())") == wow.eval(
        "Bastians.UI.Style.BOOK_FONTS.bookCaps"
    )
    assert wow.eval(f"{WIN}.win.title:GetText()") == "Bastian's Book"
    layout(1000)
    assert wow.eval(f"{WIN}.bar.oneBar") is False
    assert wow.eval(f"{WIN}.BarRoom()") == 38
    assert wow.eval(f"{WIN}.bar.front.item.icon") is None  # the words still fit on their row
    layout(700)
    assert wow.eval(f"{WIN}.bar.front.item.icon") == "ledger"  # too narrow: the pictograms
    assert wow.errors == []


def test_a_drawing_is_cut_to_its_frame_never_stretched(wow: WowRuntime):
    """Bastian "stretched to a width it does not support ... show/hide
    simply it with resizing": the 2:1 drawing covers the frame, what does not fit is cut."""
    boot(wow)
    pic = f"{MOD}.Picture"

    def cover(w: int, h: int) -> list[float]:
        return list(wow.eval(f"{{ {pic}.Cover({w}, {h}) }}").values())

    left, right, top, bottom = cover(1000, 250)  # 4:1, wider than the drawing: its height cut
    assert (left, right) == (0, 1)
    assert abs((bottom - top) - 0.5) < 1e-9 and abs(top - 0.2) < 1e-9  # a little more of the top
    assert cover(100, 100) == [0.25, 0.75, 0, 1]  # a square: the sides cut evenly
    assert cover(512, 256) == [0, 1, 0, 1]  # its own shape: all of it
    # the hero: the window's width over 2.6, within its bounds
    assert wow.eval(f"{FRONT}.HeroHeight(900)") == 346
    assert wow.eval(f"{FRONT}.HeroHeight(2800)") == 480
    assert wow.eval(f"{FRONT}.HeroHeight(400)") == 220
    assert wow.errors == []


def test_back_and_forward_walk_the_pages_shown(wow: WowRuntime):
    """ "use the same right click mouse right/left for page back and
    forward like we do in browser": the window's right-button drag walks the history."""
    boot(wow)
    wow.slash("/bbook")
    wow.slash("/bbook rares")
    wow.execute(f"{WIN}.Show({{ kind = 'wonder', id = 'rare:61' }})")
    # the right button held and dragged 50 px to the left over the window: back
    wow.execute(f"Mock.mouseOverFrame = {WIN}.win.frame; Mock.cursorX = 500")
    wow.execute("Mock.SetMouseButton('RightButton', true)")
    wow.run_frames(2)
    wow.execute("Mock.cursorX = 450")
    wow.run_frames(2)
    wow.execute("Mock.SetMouseButton('RightButton', false)")
    wow.run_frames(2)
    assert (wow.eval(f"{WIN}.Current().kind"), wow.eval(f"{WIN}.Current().id")) == (
        "shelf",
        "rares",
    )
    wow.execute(f"{WIN}.Back()")
    assert wow.eval(f"{WIN}.Current().kind") == "front"
    assert wow.eval(f"{WIN}.Back()") is False  # the first page: nowhere further back
    wow.execute(f"{WIN}.Forward()")
    assert wow.eval(f"{WIN}.Current().id") == "rares"
    wow.slash("/bbook collections")  # a new way forward replaces the old one
    assert wow.eval(f"{WIN}.Forward()") is False
    wow.execute(f"{WIN}.Back()")
    assert wow.eval(f"{WIN}.Current().id") == "rares"
    assert wow.errors == []


def test_the_filter_says_what_each_chip_filters(wow: WowRuntime):
    """ "I selected pet and object ... the object is also a pet": the
    facet is where a wonder comes from, named so on its row, its tiles and the line over them."""
    boot(wow)
    wow.slash("/bbook collections")
    unconfirmed(wow, "collections")
    wow.execute(
        f"""
        LABELS = {{}}
        for _, fs in ipairs({FRONT}.view.labels) do
          if fs:IsShown() then LABELS[#LABELS + 1] = fs:GetText() end
        end
        """
    )
    labels = list(wow.eval("LABELS").values())
    assert {"where", "level", "kind", "comes from", "sort"} <= set(labels)  # small capitals
    assert {"a vendor", "a quest", "crafting"} <= set(pills(wow))
    click_pill(wow, "mount")
    click_pill(wow, "a vendor")
    assert tiles(wow) == ["mount:458"]
    note = wow.eval(f"{FRONT}.list.items[1].note")
    assert "kind: mount" in note and "comes from: a vendor" in note
    first_tile(wow)
    assert wow.eval("TILE.kind:GetText()") == "mount  -  from a vendor"
    assert wow.errors == []


def test_the_filter_band_holds_the_concept_boards_numbers(wow: WowRuntime):
    """, the book beside its concept board: "more space between filters",
    "the buttons are rounder" (docs/addons/book-look.md section 5): chips 22 high and round at
    both ends, rows 8 apart, groups divided by a thin line, the level a range slider (D4), Hide
    done a switch, the count of the hidden ones a link beside it."""
    boot(wow)
    wow.slash("/bbook collections")
    size(wow, 1532, 843)
    view = f"{FRONT}.view"
    wow.execute(
        f"""
        CHIPS, SEPS = {{}}, 0
        for _, p in ipairs({view}.pills) do
          if p:IsShown() then CHIPS[#CHIPS + 1] = p end
        end
        for _, line in ipairs({view}.seps) do
          if line:IsShown() then SEPS = SEPS + 1 end
        end
        """
    )
    assert wow.eval("#CHIPS") > 8
    assert wow.eval("CHIPS[1]:GetHeight()") == 22 and wow.eval("CHIPS[1].face.r") == 11
    assert wow.eval("(select(2, CHIPS[1].label:GetFont()))") == 11
    assert wow.eval("SEPS") >= 2  # kind | comes from | ... | sort on shared rows
    # the level's row is the slider's; every other row a chip's; 8 between two rows
    slider = f"{view}.slider"
    assert wow.eval(f"{slider}:IsShown()") is True
    assert (wow.eval(f"{slider}:GetWidth()"), wow.eval(f"{slider}:GetHeight()")) == (204, 34)
    height = wow.eval(f"{view}.filters:GetHeight()")
    assert (height - 10 - 9 - 22 - 8 - 34) % 30 == 0, height
    # a part stands on its row's middle in whole units, rounded: the game answers a chip's 22 as
    # 22.00002, and cutting sat every chip one unit too high (the padding 9 for 10, R4.14)
    assert wow.eval(f"{FRONT}.Centre(22, 22)") == 0
    assert wow.eval(f"{FRONT}.Centre(22, 22.00001907)") == 0
    assert wow.eval(f"{FRONT}.Centre(34, 22.00001907)") == 6
    assert wow.eval(f"{FRONT}.Centre(34, 34)") == 0
    assert wow.eval(f"{view}.band:IsShown()") is True and wow.eval(f"{view}.rule:IsShown()") is True
    # the result line: the count, the filter in words, Clear all as a word
    assert wow.eval(f"{FRONT}.list.items[1].kind") == "result"
    assert wow.eval(f"{FRONT}.list.items[1].acts[1].label") == "Clear all"
    assert wow.eval(f"{FRONT}.GAP") == 11
    # the switch: off shows the done ones again
    wow.execute(f"{view}.hide:Click()")
    size(wow, 1532, 843)
    assert wow.eval(f"{view}.hide.on") is False
    assert wow.eval(f"{FRONT}.Filter('collections').showDone") is True
    # the front table has no band
    wow.slash("/bbook front")
    size(wow, 1532, 843)
    assert wow.eval(f"{view}.band:IsShown()") is False
    assert wow.eval(f"{slider}:IsShown()") is False and wow.eval(f"{view}.hide:IsShown()") is False
    assert wow.errors == []


def test_the_level_slider_takes_a_range_and_marks_your_level(wow: WowRuntime):
    """D4: two knobs from 1 to the cap, never past each other; the
    whole track is every level; the range in the filter only when the knob is let go."""
    boot(wow)
    assert wow.eval(f"{FRONT}.LevelAt(0, 204)") == 1
    assert wow.eval(f"{FRONT}.LevelAt(204, 204)") == 60
    assert (
        wow.eval(f"{FRONT}.LevelAt(-50, 204)") == 1 and wow.eval(f"{FRONT}.LevelAt(999, 204)") == 60
    )
    assert wow.eval(f"{FRONT}.LevelAt(204 * 9 / 59, 204)") == 10
    wow.slash("/bbook rares")
    size(wow)
    s = f"{FRONT}.view.slider"
    f = f"{FRONT}.Filter('rares')"
    assert (wow.eval(f"{s}.lo"), wow.eval(f"{s}.hi")) == (1, 60)
    assert wow.eval(f"{s}.you:IsShown()") == (wow.eval(f"{FRONT}.Ctx().level") is not None)
    wow.execute(f"{s}:Grab(2); {s}:Drag(12)")
    assert wow.eval(f"{s}.hi") == 12 and wow.eval(f"{f}.hi") is None  # held: not chosen yet
    assert wow.eval(f"{s}.read:IsShown()") is True and wow.eval(f"{s}.read:GetText()") == "1 to 12"
    wow.execute(f"{s}:Release()")
    assert (wow.eval(f"{f}.lo"), wow.eval(f"{f}.hi")) == (1, 12)
    assert wow.eval(f"{s}:GetScript('OnUpdate')") is None  # nothing runs once the knob is let go
    size(wow)
    assert "1 to 12" in pills(wow)
    wow.execute(f"{s}:Grab(1); {s}:Drag(40); {s}:Release()")  # the low end stops at the high one
    assert (wow.eval(f"{f}.lo"), wow.eval(f"{f}.hi")) == (12, 12)
    level(wow, 1, 60)  # the whole track: every level
    assert wow.eval(f"{f}.lo") is None and wow.eval(f"{f}.hi") is None
    assert wow.errors == []


def test_the_dark_table_lies_under_the_book_in_the_wow_look_only(wow: WowRuntime):
    """ "background color in wow schema should be same as artifact", D2 "WoW
    look only" (book-look.md section 3): the band, its rule and the table in the board's darks,
    the chips in the book's gold; every other look keeps its own ground."""
    boot(wow)
    wow.slash("/bbook rares")
    size(wow)
    S = "Bastians.UI.Style"
    view = f"{FRONT}.view"
    assert wow.eval(f"{view}.filters.palette") is None
    assert wow.eval(f"{S}.painted[{view}.table][2]") == 0  # no table: the look's own ground
    assert wow.eval(f"{S}.painted[{view}.band][1] == {S}.C.panel") is True
    wow.execute("Bastians.UI.Settings.ApplyPreset(Bastians:GetModule('Core'), 'wow')")
    size(wow)
    assert wow.eval(f"{view}.filters.palette == {S}.FolioPalette()") is True
    assert wow.eval(f"{S}.painted[{view}.table][1] == {S}.C.folioTable") is True
    assert wow.eval(f"{S}.painted[{view}.table][2]") == 1
    assert wow.eval(f"{S}.painted[{view}.band][1] == {S}.C.folioBand") is True
    assert wow.eval(f"{S}.painted[{view}.rule][1] == {S}.C.folioRule") is True
    wow.execute(
        f"""
        ON, OFF = nil, nil
        for _, p in ipairs({view}.pills) do
          if p:IsShown() then
            if p.spec.on then ON = ON or p else OFF = OFF or p end
          end
        end
        """
    )
    # the chosen chip in the book's gold with its dark ink, never the game's yellow
    assert wow.eval(f"{S}.painted[ON.face][1] == {S}.C.folioGold") is True
    assert wow.eval(f"{S}.inked[ON.label] == {S}.C.folioGoldInk") is True
    assert wow.eval(f"{S}.inked[OFF.label] == {S}.C.folioText") is True
    assert wow.errors == []


def test_the_bar_is_the_concept_boards(wow: WowRuntime):
    """ "The header feels squeezed. make it higher", "Add the book
    bastian logo top left and make that clickable to the front page", "the 3 buttons top right are
    isolated from the rest and break the style" (docs/addons/book-look.md section 4): a head of
    50, tabs and tools 28 high, the crest before the name in the book's face, Your record and
    the bookmark as words in an outline, the Atlas the filled plate, the options a quiet pictogram."""
    boot(wow)
    wow.slash("/bbook rares")
    size(wow)
    S = "Bastians.UI.Style"
    bar = f"{WIN}.bar"
    win = f"{WIN}.win"
    assert wow.eval(f"{win}.head:GetHeight()") == 50
    assert wow.eval(f"({win}.title:GetFont())") == wow.eval(f"{S}.BOOK_FONTS.bookDisplay")
    assert wow.eval(f"(select(2, {win}.title:GetFont()))") == 18
    wow.execute(f"{S}.applyFont()")  # a font change draws every heading again: the name stays
    assert wow.eval(f"({win}.title:GetFont())") == wow.eval(f"{S}.BOOK_FONTS.bookDisplay")
    assert wow.eval(f"(select(2, {win}.title:GetFont()))") == 18
    assert wow.eval(f"{bar}.tabs:GetHeight()") == 28 and wow.eval(f"{bar}.search:GetHeight()") == 28
    assert wow.eval(f"(select(2, {bar}.front.label:GetFont()))") == 13
    for tool in ("record", "mark", "atlas"):
        assert wow.eval(f"{bar}.{tool}:GetHeight()") == 28, tool
    assert wow.eval(f"{bar}.record.label:GetText()") == "Your record"
    assert wow.eval(f"{S}.painted[{bar}.record.face][2]") == 0  # words in an outline, no plate
    assert wow.eval(f"{S}.painted[{bar}.atlas.face][2]") == 1  # the Atlas: the filled plate
    assert wow.eval(f"{bar}.atlas.label:GetText()") == "atlas"  # small capitals
    assert wow.eval(f"{bar}.atlas.icon:IsShown()") is True
    assert wow.eval(f"{win}.options:IsShown()") is False  # the bar has its own quiet pictogram
    assert wow.eval(f"{bar}.gear:GetWidth()") == 20
    # the logo: the crest, a click leads to the front table
    assert wow.eval(f"{bar}.logo:IsShown()") is True and wow.eval(f"{bar}.logo:GetWidth()") == 34
    assert wow.eval(f"{bar}.logo.icon:GetTexture()") == wow.eval(f"{S}.CREST")
    wow.execute(f"{bar}.logo:Click()")
    assert wow.eval(f"{WIN}.Current().kind") == "front"
    # Your record lights its tool; the tools still answer as Core's actions did
    wow.execute(f"{bar}.record:Click()")
    assert wow.eval(f"{WIN}.Current().kind") == "record"
    assert wow.eval(f"{bar}.record.spec.on") is True
    assert wow.eval(f"{bar}.ground:IsShown()") is False  # no dark bar outside the WoW look
    assert wow.eval(f"{bar}.palette") is None
    assert wow.errors == []


def test_the_bar_lies_on_the_dark_table_in_the_wow_look(wow: WowRuntime):
    """D2 and D6: in the game's frame the crest is the round portrait and a
    button to the front table, the bar's ground the board's gradient with a rule under it, the
    shown tab and the Atlas in the book's gold."""
    boot(wow)
    wow.execute("Mock.templates.PortraitFrameTemplate = true")  # the client has the game's frame
    wow.slash("/bbook rares")
    wow.execute("Bastians.UI.Settings.ApplyPreset(Bastians:GetModule('Core'), 'wow')")
    size(wow)
    wow.execute(f"{WIN}.bar.Layout()")
    S = "Bastians.UI.Style"
    bar = f"{WIN}.bar"
    win = f"{WIN}.win"
    assert wow.eval(f"{win}.gameFramed") is True
    assert wow.eval(f"{win}.head:GetHeight()") == 50
    assert wow.eval(f"{win}:ChromeTop()") == 72  # the game's title bar and the bar
    assert wow.eval(f"{win}.opts.portrait") == wow.eval(f"{S}.CREST_PORTRAIT")
    assert wow.eval(f"{bar}.logo:IsShown()") is False  # the portrait carries the crest
    assert wow.eval(f"{win}.portraitButton ~= nil") is True
    wow.execute(f"{WIN}.Show({{ kind = 'record' }})")
    wow.execute(f"{win}.portraitButton:Click()")
    assert wow.eval(f"{WIN}.Current().kind") == "front"
    assert wow.eval(f"{bar}.ground:IsShown()") is True
    assert wow.eval(f"{bar}.palette == {S}.FolioPalette()") is True
    assert wow.eval(f"{S}.painted[{bar}.ground.rule][1] == {S}.C.folioRule") is True
    assert wow.eval(f"{S}.painted[{bar}.atlas.face][1] == {S}.C.folioGold") is True
    assert wow.eval(f"{S}.inked[{bar}.atlas.label] == {S}.C.folioGoldInk") is True
    assert wow.eval(f"{S}.inked[{bar}.record.label] == {S}.C.folioText") is True
    # the shown tab in the book's gold, the others quiet
    wow.slash("/bbook rares")
    part = f"{bar}.tabs:Part('rares')"
    assert wow.eval(f"{S}.painted[{part}.fill][1] == {S}.C.folioGold") is True
    assert wow.eval(f"{S}.inked[{bar}.front.label] == {S}.C.folioMuted") is True
    assert wow.errors == []
