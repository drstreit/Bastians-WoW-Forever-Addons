"""Your diary (W8 of plan-suite-waves.md, R4.11; book.md "Your record becomes the diary";
book-look.md 10.9): a mark keeps the zone and the level of the find, the journal is days newest
first with a line per find, progress is a row of slots per collection and zone, the album shows a
companion or a mount the reader lacks as a dark shape, and a done wonder wears the stamp with its
date on tile and page. The wonders come from the fixture book pack the generator built."""

from harness import WowRuntime
from test_book_pages import FRONT, MOD, REC, WIN, boot, click_row, size, text_of

S = "Bastians.UI.Style"
DIARY = f"{MOD}.Diary"
SHELF = f"{MOD}.Shelf"
PIC = f"{MOD}.Picture"
LEFT, RIGHT = f"{WIN}.left", f"{WIN}.right"
DAY = 86400
T0 = 1795000000  # 18.11.2026 on the mock's clock


def show(wow: WowRuntime) -> None:
    wow.execute(f"{WIN}.Show({{ kind = 'record' }})")


def words(wow: WowRuntime, page: str) -> list[str]:
    """The diary's own words on a page (its counts, the texts between a line's links)."""
    wow.execute(
        f"""
        WORDS = {{}}
        local d = {page}.diary
        for i = 1, d.nwords do WORDS[#WORDS + 1] = d.words[i]:GetText() end
        """
    )
    return list(wow.eval("WORDS").values())


def links(wow: WowRuntime, page: str) -> list[str]:
    wow.execute(
        f"""
        LINKS = {{}}
        for i = 1, {page}.nlinks do LINKS[#LINKS + 1] = {page}.links[i].text:GetText() end
        """
    )
    return list(wow.eval("LINKS").values())


def test_a_mark_keeps_the_zone_and_the_level_of_the_find(wow: WowRuntime):
    boot(wow)
    here = f"{REC}.Here()"
    assert wow.eval(f"{here}.zone") == 1429 and wow.eval(f"{here}.level") == 12
    wow.execute(f"{REC}.Mark('rare:61', 'mark', {T0}, 'Narg', {here})")
    mark = f"{REC}.Entry('rare:61')"
    assert wow.eval(f"{mark}.zone") == 1429 and wow.eval(f"{mark}.level") == 12
    assert wow.eval(f"{mark}.name") == "Narg" and wow.eval(f"{mark}.at") == T0
    # a mark without them reads as before (unknown is not zero)
    wow.execute(f"{REC}.Mark('rare:99', 'mark', {T0}, 'Morgaine')")
    assert wow.eval(f"{REC}.Entry('rare:99').zone") is None
    assert wow.eval(f"{REC}.Entry('rare:99').level") is None
    # the scan hands on what it is given
    wow.execute(
        f"""
        Bastians.Compat.GetItemCount = function(id) return id == 5 and 1 or 0 end
        local shelf = {{ {{ id = "pet:5", title = "A Found Pet", done = {{ item = 5 }} }},
                        {{ id = "pet:6", title = "Another", done = {{ item = 5 }} }} }}
        {REC}.Scan({MOD}, {{ shelf[1] }}, nil, {{ zone = 1413, level = 30 }})
        {REC}.Scan({MOD}, {{ shelf[2] }})
        """
    )
    assert wow.eval(f"{REC}.Entry('pet:5').zone") == 1413
    assert wow.eval(f"{REC}.Entry('pet:5').level") == 30
    assert wow.eval(f"{REC}.Entry('pet:6').how") == "found"
    assert wow.eval(f"{REC}.Entry('pet:6').zone") is None
    assert wow.errors == []


def test_what_the_first_look_after_a_login_finds_keeps_no_place(wow: WowRuntime):
    """What a character had before this login was not found here: the first scan with the shelf's
    wonders keeps neither zone nor level; a find while playing keeps both."""
    wow.start("Bastians_Core", "Bastians_Data", "Bastians_Strategies")
    wow.run_frames(10)
    wow.advance(0.3)
    wow.execute(
        f"""
        ITEMS = {{}}
        Bastians.Compat.GetItemCount = function(id) return ITEMS[id] or 0 end
        Bastians:GetService("data"):LoadPack("book")
        FIRST, LATER = nil, nil
        for _, e in ipairs({MOD}.Front.Entries()) do
          if e.done and e.done.item and not e.done.spell then
            if not FIRST then FIRST = e elseif not LATER then LATER = e end
          end
        end
        ITEMS[FIRST.done.item] = 1  -- in the bags before the book looked
        """
    )
    assert wow.eval("FIRST ~= nil and LATER ~= nil") is True
    wow.run_frames(5)
    wow.advance(2.5)
    wow.run_frames(5)
    first = f"{REC}.Entry(FIRST.id)"
    assert wow.eval(f"{first}.how") == "found"
    assert wow.eval(f"{first}.zone") is None and wow.eval(f"{first}.level") is None
    wow.execute("ITEMS[LATER.done.item] = 1")
    wow.fire("BAG_UPDATE_DELAYED")
    wow.advance(2.5)
    wow.run_frames(5)
    later = f"{REC}.Entry(LATER.id)"
    assert wow.eval(f"{later}.how") == "found"
    assert wow.eval(f"{later}.zone") == 1429 and wow.eval(f"{later}.level") == 12
    assert wow.errors == []


def test_the_journal_is_days_newest_first(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"""
        local R = {REC}
        R.Mark("rare:61", "mark", {T0} - 4 * {DAY}, "Narg")
        R.Mark("mount:5784", "found", {T0}, "A Ram", {{ zone = 1429, level = 24 }})
        R.Mark("pet:10683", "found", {T0} + 60, "A Pet")
        J = R.Journal()
        """
    )
    assert wow.eval("#J") == 2
    assert wow.eval("J[1].day") == "2026-11-18" and wow.eval("J[2].day") == "2026-11-14"
    assert [m.id for m in wow.eval("J[1].marks").values()] == ["pet:10683", "mount:5784"]
    assert wow.eval("J[1].marks[2].zone") == 1429 and wow.eval("J[1].marks[2].level") == 24
    assert wow.eval("J[1].marks[2].how") == "found" and wow.eval("J[1].marks[2].name") == "A Ram"
    assert wow.eval("J[2].marks[1].id") == "rare:61" and wow.eval("J[2].marks[1].zone") is None
    assert wow.eval(f"{DIARY}.DayTitle({T0})") == "18 November"
    assert wow.eval(f"{DIARY}.DayTitle({T0} - 10 * {DAY})") == "8 November"  # no leading zero
    assert wow.errors == []


def test_a_finds_line_in_bastians_hand(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"""
        local zone = function(z) return ({{ [1429] = "Elwynn Forest", [1413] = "The Barrens" }})[z] end
        local e = {{ id = "pet:1", title = "Black Tabby", zones = {{ 1413 }} }}
        local function flat(parts)
          local out = {{}}
          for _, p in ipairs(parts) do
            out[#out + 1] = p.link and ("[" .. p.link .. "]") or p.text
          end
          return table.concat(out)
        end
        local L = {DIARY}.Line
        FOUND = L({{ id = "pet:1", how = "found", zone = 1429, level = 24 }}, e, zone)
        A = flat(FOUND)
        B2 = flat(L({{ id = "pet:1", how = "mark" }}, e, zone))
        GONE = L({{ id = "pet:9", how = "found", name = "Lost Kitten", level = 7 }}, nil, zone)
        C = flat(GONE)
        D = flat(L({{ id = "pet:8", how = "found" }}, nil, zone))
        E = flat(L({{ id = "pet:1", how = "found", zone = 77 }}, e, zone))
        """
    )
    # the zone of the find, the level the mark kept
    assert wow.eval("A") == "[Black Tabby], [Elwynn Forest]. Level 24."
    assert wow.eval("FOUND[1].wonder") == "pet:1" and wow.eval("FOUND[3].ref") == "zone:1429"
    # a mark by hand says so; without a zone of its own the wonder's first zone, and no level
    assert wow.eval("B2") == "[Black Tabby], [The Barrens]. Marked by hand."
    # a wonder that left the pack: its saved name as words, no link; then its id
    assert wow.eval("C") == "Lost Kitten. Level 7."
    assert wow.eval("GONE[1].link") is None
    assert wow.eval("D") == "pet:8."
    assert wow.eval("E") == "[Black Tabby]."  # a zone nobody can name is not written
    assert wow.errors == []


def test_the_slots_of_a_row(wow: WowRuntime):
    boot(wow)
    slots = f"{DIARY}.Slots"
    assert tuple(wow.eval(f"{slots}(464, 18)")) == (18, 0)  # 18 discs of 22, 4 apart: 464
    assert tuple(wow.eval(f"{slots}(463, 18)")) == (16, 2)  # one short: room for "+ 2"
    assert tuple(wow.eval(f"{slots}(464, 34)")) == (16, 18)
    assert tuple(wow.eval(f"{slots}(10, 5)")) == (0, 5)
    assert tuple(wow.eval(f"{slots}(300, 0)")) == (0, 0)
    # a row's name: the cabinet's for a kind, the chapter's; the library's as the board writes it
    name = f"{DIARY}.RowName"
    assert wow.eval(f"{name}({{ kind = 'mount', chapter = 'collections' }})") == "Mounts"
    assert (
        wow.eval(f"{name}({{ kind = 'library book', chapter = 'collections' }})") == "The library"
    )
    assert wow.eval(f"{name}({{ chapter = 'rares' }})") == "Rares"


def test_progress_counts_what_can_be_had(wow: WowRuntime):
    """E2: a total counts what is in Forever, never what nobody reported yet, unless the reader
    has it, which is the proof."""
    boot(wow)
    wow.execute(
        f"""
        {REC}.Mark("rare:61", "mark", {T0}, "Narg")
        P = {SHELF}.Progress({FRONT}.Entries(), {FRONT}.Ctx())
        ROWS = {{}}
        for _, r in ipairs(P.rows) do ROWS[#ROWS + 1] = r.id .. " " .. r.have .. "/" .. r.total end
        ZONES = {{}}
        for _, z in ipairs(P.zones) do ZONES[#ZONES + 1] = z.name .. " " .. z.have .. "/" .. z.total end
        """
    )
    # the library has no book in the fixture: its row is left out; a gold page is no wonder
    assert list(wow.eval("ROWS").values()) == [
        "mount 0/1",
        "pet 0/1",
        "title 0/1",
        "secrets 0/3",
        "camp 0/3",
        "rares 1/1",
    ]
    # the zone the reader stands in first (Elwynn: the camping chain and the rare)
    assert list(wow.eval("ZONES").values()) == ["Elwynn Forest 1/2"]
    counted = f"{SHELF}.Counted"
    ctx = f"{FRONT}.Ctx()"
    assert tuple(wow.eval(f"{counted}({FRONT}.Find('pet:4055'), {ctx})")) == (False, False)
    wow.execute(f"{REC}.Mark('pet:4055', 'found', {T0}, 'x')")
    assert tuple(wow.eval(f"{counted}({FRONT}.Find('pet:4055'), {ctx})")) == (True, True)
    wow.execute(f"P = {SHELF}.Progress({FRONT}.Entries(), {FRONT}.Ctx())")
    assert wow.eval("P.rows[2].have") == 1 and wow.eval("P.rows[2].total") == 2
    assert tuple(wow.eval(f"{counted}({FRONT}.Find('hogger-camp'), {ctx})")) == (False, False)
    # the other side's wonder does not count for a character whose side is known
    other = "{ id = 'x', chapter = 'collections', kind = 'mount', side = 'H' }"
    assert wow.eval(f"({counted}({other}, {{ side = 'A' }}))") is False
    assert wow.eval(f"({counted}({other}, {{}}))") is True
    assert wow.errors == []


def test_the_diary_is_a_spread_of_two_paper_pages(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"""
        local R = {REC}
        R.Mark("rare:61", "mark", {T0} - 4 * {DAY}, "Narg")
        R.Mark("mount:5784", "found", {T0}, "A Ram", {{ zone = 1429, level = 24 }})
        local char = {MOD}.db.char
        char.bookmarks[#char.bookmarks + 1] = "chain:sleeping-bag"
        char.bookmarks[#char.bookmarks + 1] = "hogger-camp"
        """
    )
    wow.slash("/bbook diary")
    assert wow.eval(f"{WIN}.Current().kind") == "record"
    assert wow.eval(f"{WIN}.pageTitle") == "Your diary"
    assert wow.eval(f"{FRONT}.view:IsShown()") is False  # ~~a list of tiles~~ until 24.11.2026
    assert wow.eval(f"{WIN}.folio:IsShown()") is False  # one spread: nothing to turn to
    for page in (LEFT, RIGHT):
        assert wow.eval(f"{page}:IsShown()") is True and wow.eval(f"{page}.onPaper") is True
        assert wow.eval(f"{S}.painted[{page}.bg][1] == {S}.C.folioPaper") is True
    left = text_of(wow, "left")
    assert left[0] == "the journal - newest first"
    # a day's date in the display face at 18, in the paper's ink
    assert left[1] == "18 November" and "14 November" in left
    day = f"{LEFT}.fs[2]"
    assert tuple(wow.eval(f"{day}:GetFont()"))[:2] == (wow.eval(f"{S}.BOOK_FONTS.bookDisplay"), 18)
    assert wow.eval(f"{S}.inked[{day}] == {S}.C.folioInk") is True
    # a line: the stamp's disc of 16 in the book's gold, then the wonder and the zone as links
    ram = wow.eval(f"{FRONT}.Find('mount:5784').title")
    narg = wow.eval(f"{FRONT}.Find('rare:61').title")
    assert links(wow, LEFT)[:3] == [ram, "Elwynn Forest", narg]
    assert wow.eval(f"{LEFT}.diary.ndiscs") == 2
    disc = f"{LEFT}.diary.discs[1]"
    assert wow.eval(f"{disc}:GetWidth()") == 16
    assert wow.eval(f"{S}.painted[{disc}][1] == {S}.C.folioGold") is True
    said = words(wow, LEFT)
    assert ". Level 24." in said and ". Marked by hand." in said
    line = f"{LEFT}.links[1]"
    assert tuple(wow.eval(f"{line}.text:GetFont()"))[:2] == (
        wow.eval(f"{S}.BOOK_FONTS.bookItalic"),
        13,
    )
    assert wow.eval(f"{LEFT}.links[2].ref") == "zone:1429"
    # kept for later: the bookmarks as links in one running line
    assert "kept for later" in left
    hogger = wow.eval(f"{FRONT}.Find('hogger-camp').title")
    bag = wow.eval(f"{FRONT}.Find('chain:sleeping-bag').title")
    assert links(wow, LEFT)[4:6] == [bag, hogger]
    # the right page: progress, a row per collection and for the zone the reader stands in
    right = text_of(wow, "right")
    assert right[0] == "progress"
    assert links(wow, RIGHT) == [
        "Mounts",
        "Companions",
        "Titles",
        "Secrets",
        "Camp",
        "Rares",
        "Elwynn Forest",
    ]
    counts = words(wow, RIGHT)
    assert counts[0] == "1 of 1" and counts[3] == "0 of 3" and counts[-1] == "1 of 2"
    name = f"{RIGHT}.links[1]"
    assert tuple(wow.eval(f"{name}.text:GetFont()"))[:2] == (
        wow.eval(f"{S}.BOOK_FONTS.bookDisplay"),
        15,
    )
    # the slots: discs of 22, the owned ones first in the book's gold
    assert wow.eval(f"{RIGHT}.diary.nslots") == 1 + 1 + 1 + 3 + 3 + 1 + 2
    first, second = f"{RIGHT}.diary.slots[1]", f"{RIGHT}.diary.slots[2]"
    assert wow.eval(f"{first}:GetWidth()") == 22 and wow.eval(f"{first}.on") is True
    assert wow.eval(f"{second}.on") is False
    assert (
        wow.eval(f"{S}.painted[{first}.fill][2]") == 1
        and wow.eval(f"{S}.painted[{second}.fill][2]") == 0
    )
    # a wonder's link opens its page, a gold page's its page
    wow.execute(f"{LEFT}.links[1]:Click()")
    assert wow.eval(f"{WIN}.Current().kind") == "wonder"
    assert wow.eval(f"{WIN}.Current().id") == "mount:5784"
    # the wonder's page took the diary's parts away
    assert wow.eval(f"{LEFT}.diary.discs[1]:IsShown()") is False
    assert wow.eval(f"{RIGHT}.diary.slots[1]:IsShown()") is False
    show(wow)
    wow.execute(f"{LEFT}.links[6]:Click()")
    assert (
        wow.eval(f"{WIN}.Current().kind") == "page"
        and wow.eval(f"{WIN}.Current().id") == "hogger-camp"
    )
    # a collection's name opens its shelf on that kind
    show(wow)
    wow.execute(f"{RIGHT}.links[2]:Click()")
    assert wow.eval(f"{WIN}.Current().kind") == "shelf"
    assert wow.eval(f"{WIN}.Current().id") == "collections"
    assert wow.eval(f"{FRONT}.Filter('collections').facets.kind.pet") is True
    # another page takes the theme's ground again
    wow.execute(f"{WIN}.Show({{ kind = 'title' }})")
    assert wow.eval(f"{LEFT}.onPaper") is None
    assert wow.eval(f"{WIN}.folio:IsShown()") is True
    assert wow.errors == []


def test_an_empty_diary_says_what_to_do(wow: WowRuntime):
    boot(wow)
    show(wow)
    left = text_of(wow, "left")
    assert any(t.startswith("Nothing done yet on this character.") for t in left)
    assert "Bookmark a page to keep it here." in left
    assert "your other characters" not in left
    assert wow.eval(f"{LEFT}.diary.ndiscs") == 0
    # the other characters' finds, a line each with who did it
    wow.execute(
        f"""
        local g = {MOD}.db.global
        g.record["Bran-Realm"] = {{ name = "Bran", done = {{ ["chain:sleeping-bag"] = {{ how = "mark", at = 1 }} }} }}
        """
    )
    show(wow)
    assert "your other characters" in text_of(wow, "left")
    assert wow.eval(f"{FRONT}.Find('chain:sleeping-bag').title") in links(wow, LEFT)
    assert "- Done by Bran" in words(wow, LEFT)
    assert wow.errors == []


def test_the_journal_opens_its_earlier_days(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"""
        for i = 1, {DIARY}.DAYS + 3 do
          {REC}.Mark("x:" .. i, "mark", {T0} - i * {DAY}, "Wonder " .. i)
        end
        """
    )
    show(wow)
    assert wow.eval(f"{LEFT}.diary.ndiscs") == wow.eval(f"{DIARY}.DAYS")
    # a wonder the pack does not hold is written by its saved name, without a link
    assert words(wow, LEFT)[:2] == ["Wonder 1", ". Marked by hand."]
    assert links(wow, LEFT) == ["3 earlier days"]
    click_row(wow, "left", "3 earlier days")
    assert wow.eval(f"{LEFT}.diary.ndiscs") == wow.eval(f"{DIARY}.DAYS") + 3
    assert "3 earlier days" not in links(wow, LEFT)
    assert wow.errors == []


def album(wow: WowRuntime) -> None:
    """The fixture's companion and mount get a creature to show; the companion is the reader's."""
    wow.execute(
        f"""
        {FRONT}.Find("pet:10683").npc = 7385
        {FRONT}.Find("mount:5784").npc = 4710
        {REC}.Mark("pet:10683", "found", {T0}, "x")
        """
    )


def test_the_album_shows_what_the_reader_lacks_as_a_dark_shape(wow: WowRuntime):
    boot(wow)
    album(wow)
    wow.execute(
        """
        LIGHTS = {}
        CreateVector3D = function(x, y, z) return { x = x, y = y, z = z } end
        """
    )
    show(wow)
    right = text_of(wow, "right")
    assert "the album - companions" in right and "the album - mounts" in right
    assert wow.eval(f"{RIGHT}.diary.nframes") == 2
    own, lacking = f"{RIGHT}.diary.frames[1]", f"{RIGHT}.diary.frames[2]"
    # six frames in a row, 8 apart, square
    w = wow.eval(f"{RIGHT}.width")
    side = (w - 5 * 8) // 6
    assert tuple(wow.eval(f"{own}:GetSize()")) == (side, side)
    # the mat in a border of 3 in the paper's light, a line of 1 around it
    assert wow.eval(f"{S}.painted[{own}.mat][1] == {S}.C.folioAlbum") is True
    assert wow.eval(f"{S}.painted[{own}.border][1] == {S}.C.folioSealText") is True
    assert wow.eval(f"{S}.painted[{own}.line][1] == {S}.C.folioPaperEdge") is True
    # the reader's own: the model lit, 74 % of the frame wide
    assert wow.eval(f"{own}.entry.id") == "pet:10683" and wow.eval(f"{own}.have") is True
    assert wow.eval(f"{own}.drew") is True and wow.eval(f"{own}.lit:IsShown()") is True
    assert wow.eval(f"{own}.dark") is None
    assert wow.eval(f"{own}.lit:GetWidth()") == int(side * 0.74)
    assert wow.eval(f"{own}.name:IsShown()") is False
    # the one the reader lacks: its own model frame, lit black
    assert wow.eval(f"{lacking}.entry.id") == "mount:5784" and wow.eval(f"{lacking}.have") is False
    assert wow.eval(f"{lacking}.drew") is True and wow.eval(f"{lacking}.dark:IsShown()") is True
    assert wow.eval(f"{lacking}.lit") is None
    light = f"{lacking}.dark.light"
    assert wow.eval(f"{light}.enabled") is True
    assert wow.eval(f"{light}.light.ambientIntensity") == 0
    assert wow.eval(f"{light}.light.diffuseIntensity") == 0
    assert wow.eval(f"{light}.light.omnidirectional") is False
    assert wow.eval(f"{own}.lit.light") is None  # the reader's own keeps the game's light
    assert wow.eval(f"{lacking}.tip") == wow.eval(f"{FRONT}.Find('mount:5784').title")
    # a frame opens its wonder; its models stop drawing with the page
    wow.execute(f"{lacking}:Click()")
    assert wow.eval(f"{WIN}.Current().id") == "mount:5784"
    assert (
        wow.eval(f"{lacking}:IsShown()") is False and wow.eval(f"{lacking}.dark:IsShown()") is False
    )
    assert wow.eval(f"{own}.lit:IsShown()") is False
    assert wow.errors == []


def test_without_the_dark_light_a_lacking_frame_keeps_its_name(wow: WowRuntime):
    """The board's note: where a model cannot be drawn as a dark shape, the frame of what the
    reader lacks stays empty with its name; never the lit model."""
    boot(wow)
    album(wow)
    assert wow.eval("CreateVector3D") is None  # the mock has no such light
    show(wow)
    own, lacking = f"{RIGHT}.diary.frames[1]", f"{RIGHT}.diary.frames[2]"
    assert wow.eval(f"{own}.drew") is True
    assert wow.eval(f"{lacking}.drew") is False
    assert wow.eval(f"{lacking}.dark:IsShown()") is False
    assert wow.eval(f"{lacking}.name:IsShown()") is True
    title = wow.eval(f"{FRONT}.Find('mount:5784').title")
    assert wow.eval(f"{lacking}.name:GetText()") == title.lower()
    assert wow.errors == []


def test_a_done_wonder_wears_the_stamp_on_tile_and_page(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"""
        {REC}.Mark("chain:sleeping-bag", "found", {T0}, "x")
        {REC}.Mark("rare:61", "mark", {T0}, "y")
        """
    )
    assert wow.eval(f"{PIC}.StampText({{ how = 'found', at = {T0} }})") == "found - 18.11"
    assert wow.eval(f"{PIC}.StampText({{ how = 'mark', at = {T0} }})") == "done - 18.11"
    # the page: on the plate's top right, 16 in and 14 down, above the picture's rim
    wow.execute(f"{WIN}.Show({{ kind = 'wonder', id = 'rare:61' }})")
    stamp = f"{WIN}.left.wonderMat.stamp"
    assert wow.eval(f"{stamp}:IsShown()") is True
    assert wow.eval(f"{stamp}.text:GetText()") == "done - 18.11"
    point = tuple(wow.eval(f"{stamp}:GetPoint(1)"))
    assert point[0] == "TOPRIGHT" and point[2] == "TOPRIGHT" and point[3:] == (-16, -14)
    assert wow.eval(f"{S}.inked[{stamp}.text] == {S}.C.folioSeal") is True
    # padded 4 and 8 around words of 11, a border of 2 in the seal's red on the paper at 70 %
    w, h = wow.eval(f"{stamp}:GetWidth()"), wow.eval(f"{stamp}:GetHeight()")
    assert h == 19 and w > 16
    assert tuple(wow.eval(f"{stamp}.sides[1]:GetSize()")) == (w, 2)
    assert tuple(wow.eval(f"{stamp}.sides[3]:GetSize()")) == (2, h)
    assert wow.eval(f"{S}.painted[{stamp}.sides[1]][1] == {S}.C.folioSeal") is True
    assert wow.eval(f"{S}.painted[{stamp}.ground][1] == {S}.C.folioPaper") is True
    assert wow.eval(f"{S}.painted[{stamp}.ground][2]") == 0.7
    # a wonder that is not done has none
    wow.execute(f"{WIN}.Show({{ kind = 'wonder', id = 'mount:5784' }})")
    assert wow.eval(f"{stamp}:IsShown()") is False
    # the tile: with the done ones shown, the stamp; a done secret wears it in the seal's place
    wow.slash("/bbook secrets")
    wow.execute(f"{FRONT}.Filter('secrets').showDone = true")
    size(wow)
    wow.execute(
        f"""
        TILE, OPEN = nil, nil
        for _, row in ipairs({FRONT}.list:Rows()) do
          for _, t in ipairs(row.tiles or {{}}) do
            if t:IsShown() and t.entry.id == "chain:sleeping-bag" then TILE = t end
            if t:IsShown() and t.entry.id == "chain:keystone-fragment" then OPEN = t end
          end
        end
        """
    )
    assert wow.eval("TILE.stamp:IsShown()") is True
    assert wow.eval("TILE.stamp.text:GetText()") == "found - 18.11"
    assert wow.eval("TILE.seal:IsShown()") is False
    assert wow.eval("OPEN.stamp == nil or not OPEN.stamp:IsShown()") is True
    assert wow.eval("OPEN.seal:IsShown()") is True
    assert wow.errors == []


def test_a_pooled_link_opens_its_own_thing_again(wow: WowRuntime):
    """Until 24.11.2026 a link that had been "N more sources" kept that click: the next page's
    first link opened the sources instead of its thing."""
    boot(wow)
    wow.execute(f"{WIN}.Show({{ kind = 'wonder', id = 'pet:10675' }})")
    wow.execute(
        f"""
        FOCUSED, OWN = nil, nil
        local w = Bastians:NewModule("DiaryLinkWatch", {{ addon = "Bastians_Core" }})
        w:On("BASTIANS_ENTITY_FOCUSED", function(_, _, ref) FOCUSED = ref end)
        local P, page = {MOD}.Wonder.Paper, {RIGHT}
        P.start(page)
        local b = P.link(page)
        P.set(b, "3 more sources", nil, 13)
        b:SetScript("OnClick", function() OWN = true end)
        P.start(page)
        local again = P.link(page)
        SAME = again == b
        P.set(again, "Hogger", "npc:448", 13)
        again:Click()
        """
    )
    assert wow.eval("SAME") is True
    assert wow.eval("FOCUSED") == "npc:448" and wow.eval("OWN") is None
    assert wow.errors == []
