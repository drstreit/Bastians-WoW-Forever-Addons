"""Bastian's Book's front table (W6 of plan-suite-waves.md; book.md "The front table", E3;
book-look.md 10.2 and 10.3; R4.6 and R4.7): the newest gold story as the main tile and six more
chosen for the character (pure, on 2,000 simulated wonders for ten characters), the cabinet's
cells at the spec's widths, the kinds of tile by what they hold, a tile as an object (it rises
under the mouse and sinks on a press), Bastian's note and the chapters' entrances."""

import pytest
from harness import WowRuntime

CORE, DATA, STRAT = "Bastians_Core", "Bastians_Data", "Bastians_Strategies"
MOD = "Bastians:GetModule('Strategies')"
SHELF = f"{MOD}.Shelf"
CAB = f"{MOD}.Cabinet"
FRONT = f"{MOD}.Front"
WIN = f"{MOD}.Window"
S = "Bastians.UI.Style"
N = 2000

# ten characters: a level and a zone of the simulation (Shelf.SIM_ZONES)
CHARACTERS = [
    (5, 1429),
    (12, 1436),
    (18, 1431),
    (24, 1437),
    (30, 1416),
    (36, 1434),
    (42, 1418),
    (48, 1446),
    (54, 1441),
    (60, 1413),
]

SETUP = f"""
local S = {SHELF}
shelf = S.Simulate({N}, 7)
done = {{}}
-- the simulation's zones on a line, 1,500 yards apart, each continent its own line
local order, at = {{}}, {{}}
for z in pairs(S.SIM_ZONES) do order[#order + 1] = z end
table.sort(order)
for i, z in ipairs(order) do at[z] = i * 1500 end
function character(level, map, today, side)
  return {{
    isDone = function(id) return done[id] == true end,
    zoneOf = S.SimZone,
    today = today or "2026-11-16",
    level = level,
    side = side,
    here = {{ map = map, continent = S.SimZone(map).continent }},
    worldOf = function(m, x, y)
      local zone = S.SimZone(m)
      if not zone then return nil end
      return zone.continent, at[m] + (x - 0.5) * 1000, (y - 0.5) * 1000
    end,
  }}
end
function ids(front)
  local out = {{}}
  for i, e in ipairs(front.six) do out[i] = e.id end
  return table.concat(out, ",")
end
"""


def boot(wow: WowRuntime, pack: bool = False) -> WowRuntime:
    wow.start(CORE, DATA, STRAT)
    wow.run_frames(10)
    if pack:
        wow.advance(0.3)
        wow.execute('Bastians:GetService("data"):LoadPack("book")')
        wow.run_frames(5)
    return wow


@pytest.mark.parametrize(("level", "zone"), CHARACTERS)
def test_the_table_is_chosen_for_the_character(wow: WowRuntime, level: int, zone: int):
    boot(wow)
    wow.execute(SETUP)
    wow.execute(f"ctx = character({level}, {zone}); front = {SHELF}.Front(shelf, ctx)")
    # the main tile: the newest gold story, whatever its level
    wow.execute(
        """
        newest = nil
        for _, e in ipairs(shelf) do
          if e.chapter == "gold" and e.added and (not newest or e.added > newest) then
            newest = e.added
          end
        end
        """
    )
    assert wow.eval("front.main.chapter") == "gold"
    assert wow.eval("front.main.added") == wow.eval("newest")
    # six more: open, obtainable, none of them the main tile, none twice
    six = list(wow.eval("front.six").values())
    assert len(six) == 6
    assert len({e.id for e in six}) == 6
    for e in six:
        assert e.state != "unknown", e.id  # E2: never what nobody reported in Forever yet
        assert e.id != wow.eval("front.main.id")
    # at most two of a chapter, three chapters where there are
    per: dict[str, int] = {}
    for e in six:
        per[e.chapter] = per.get(e.chapter, 0) + 1
    assert max(per.values()) <= 2 and len(per) >= 3
    # the best first: nothing left out scores higher than the first tile; a wonder in the
    # character's zone and level beats everything elsewhere (6 for the zone and 3 for the band)
    wow.execute(
        f"""
        best, fitsHere = 0, false
        for _, e in ipairs(shelf) do
          local s = front.score[e]
          if s and e ~= front.main then
            if s > best then best = s end
            if {SHELF}.Fits(e, {level}) then
              for _, z in ipairs(e.zones or {{}}) do if z == {zone} then fitsHere = true end end
            end
          end
        end
        first = front.score[front.six[1]]
        firstHere = false
        for _, z in ipairs(front.six[1].zones or {{}}) do
          if z == {zone} then firstHere = true end
        end
        """
    )
    assert abs(wow.eval("first") - wow.eval("best")) < 1e-9
    if wow.eval("fitsHere"):
        assert wow.eval("firstHere") is True and wow.eval("first") >= 9
    # the same all day, and after a reload (the same wonders read again)
    before = wow.eval("ids(front)")
    assert wow.eval(f"ids({SHELF}.Front(shelf, ctx))") == before
    wow.execute(f"shelf = {SHELF}.Simulate({N}, 7)")
    assert wow.eval(f"ids({SHELF}.Front(shelf, character({level}, {zone})))") == before
    # a new zone changes it, and so does another level
    other = 1413 if zone != 1413 else 1429
    assert wow.eval(f"ids({SHELF}.Front(shelf, character({level}, {other})))") != before
    far = 60 if level < 30 else 3
    assert wow.eval(f"ids({SHELF}.Front(shelf, character({far}, {zone})))") != before
    # the chapters' counts for the entrances: what is open, and what is in the zone
    chapters = wow.eval("front.chapters")
    for chapter in ("gold", "secrets", "collections", "camp", "rares"):
        assert chapters[chapter].open > 0 and 0 <= chapters[chapter].near <= chapters[chapter].open
    assert wow.errors == []


def test_done_the_other_side_and_the_back_shelf_stay_off_the_table(wow: WowRuntime):
    boot(wow)
    wow.execute(SETUP)
    wow.execute(f"ctx = character(24, 1437); front = {SHELF}.Front(shelf, ctx)")
    first = wow.eval("front.six[1].id")
    wow.execute(f'done["{first}"] = true; front = {SHELF}.Front(shelf, ctx)')
    assert first not in wow.eval("ids(front)").split(",")  # done is not on the table
    # the main tile is the newest gold story also when it is done
    main = wow.eval("front.main.id")
    wow.execute(f'done["{main}"] = true; front = {SHELF}.Front(shelf, ctx)')
    assert wow.eval("front.main.id") == main
    # a character of one side sees nothing of the other
    wow.execute(f'front = {SHELF}.Front(shelf, character(24, 1437, nil, "A"))')
    assert all(e.side in (None, "A") for e in wow.eval("front.six").values())
    # a page of the back shelf stands on no table
    wow.execute(
        f"""
        for _, e in ipairs(shelf) do if e.chapter == "gold" then e.back = true end end
        front = {SHELF}.Front(shelf, ctx)
        """
    )
    assert wow.eval("front.main") is None
    assert all(e.chapter != "gold" for e in wow.eval("front.six").values())
    assert wow.errors == []


def test_fewer_than_three_chapters_still_fill_the_table(wow: WowRuntime):
    boot(wow)
    wow.execute(SETUP)
    wow.execute(
        f"""
        local some = {{}}
        for _, e in ipairs(shelf) do
          if e.chapter == "rares" or e.chapter == "camp" then some[#some + 1] = e end
        end
        front = {SHELF}.Front(some, character(24, 1437))
        """
    )
    six = list(wow.eval("front.six").values())
    assert len(six) == 6 and {e.chapter for e in six} == {"rares", "camp"}
    assert wow.eval("front.main") is None  # no gold story: no main tile
    # nothing at all: an empty table, no error
    wow.execute(f"front = {SHELF}.Front({{}}, character(24, 1437))")
    assert wow.eval("#front.six") == 0 and wow.eval("front.main") is None
    assert wow.errors == []


def test_the_wide_tile_stands_for_a_collection(wow: WowRuntime):
    boot(wow)
    wow.execute(SETUP)
    wow.execute(
        f"""
        ctx = character(24, 1437)
        front = {SHELF}.Front(shelf, ctx)
        coll = front.collection
        total, have = 0, 0
        if coll then
          -- the character has two of that collection
          local n = 0
          for _, e in ipairs(shelf) do
            if e.chapter == "collections" and e.kind == coll.kind and e.state ~= "unknown"
              and e ~= coll.entry and n < 2 then
              done[e.id] = true
              n = n + 1
            end
          end
          front = {SHELF}.Front(shelf, ctx)
          coll = front.collection
          for _, e in ipairs(shelf) do
            if e.chapter == "collections" and e.kind == coll.kind and e.state ~= "unknown" then
              total = total + 1
            end
          end
          slots = {CAB}.Slots(front)
        end
        """
    )
    assert wow.eval("coll ~= nil") is True  # 2,000 wonders: a collectable is among the six
    assert wow.eval("coll.kind") in ("mount", "pet", "title", "library book")
    assert wow.eval("coll.have") == 2 and wow.eval("coll.total") == wow.eval("total")
    # the collection's wonder sits on the wide tile (slot 5), and the tile is drawn as one
    assert wow.eval("slots[5] == coll.entry") is True
    assert wow.eval(f"{CAB}.KindOf(slots[5], front, 5)") == "collection"
    assert wow.eval(f"{CAB}.KindOf(slots[5], front, 2)") != "collection"
    assert wow.errors == []


# book-look.md 10.2: the window's width -> columns, a cell's width and height, the main, the tall
# and the wide tile, the cabinet's height
CELLS = [
    (1100, 3, 349, 169, (709, 349), (349, 349), (709, 169), 709),
    (1325, 3, 424, 206, (859, 423), (424, 423), (859, 206), 857),
    (1532, 3, 493, 241, (997, 493), (493, 493), (997, 241), 997),
    (2100, 3, 682, 335, (1375, 681), (682, 681), (1375, 335), 1373),
    (880, 2, 419, 204, (849, 419), (419, 419), (849, 204), 1279),
    (560, 1, 530, 259, (530, 529), (530, 529), (530, 259), 2419),
]


@pytest.mark.parametrize(("window", "cols", "c", "h", "main", "tall", "wide", "height"), CELLS)
def test_the_cabinets_cells_follow_the_window(
    wow: WowRuntime, window, cols, c, h, main, tall, wide, height
):
    boot(wow)
    wow.execute(f"lay = {CAB}.Layout({window} - 2 * {CAB}.SIDE)")
    assert wow.eval("lay.cols") == cols and wow.eval("lay.c") == c and wow.eval("lay.h") == h
    assert wow.eval("lay.height") == height
    rects = {r.slot: r for r in wow.eval("lay.rects").values()}
    assert sorted(rects) == [0, 1, 2, 3, 4, 5, 6]  # seven tiles at every width
    assert (rects[0].w, rects[0].h) == main and rects[0].role == "main"
    assert (rects[1].w, rects[1].h) == tall and rects[1].role == "tall"
    assert (rects[5].w, rects[5].h) == wide and rects[5].role == "wide"
    for slot in (2, 3, 4, 6):
        assert (rects[slot].w, rects[slot].h) == (c, h), slot
    # the main tile at the top left; no two tiles overlap; nothing past the table's width
    assert (rects[0].x, rects[0].y) == (0, 0)
    boxes = [(r.x, r.y, r.x + r.w, r.y + r.h) for r in rects.values()]
    for i, a in enumerate(boxes):
        assert a[2] <= window - 30 and a[3] <= height
        for b in boxes[i + 1 :]:
            assert a[2] <= b[0] or b[2] <= a[0] or a[3] <= b[1] or b[3] <= a[1], (a, b)
    assert wow.errors == []


def test_the_entrances_stand_in_a_row_or_in_two_or_in_a_column(wow: WowRuntime):
    boot(wow)
    wow.execute(f"wide = {CAB}.Entrances(1532 - 30); mid = {CAB}.Entrances(880 - 30)")
    wow.execute(f"narrow = {CAB}.Entrances(560 - 30)")
    # five in a row: (the window - 2 x 15 - 4 x 11) / 5 wide, 92 high
    assert wow.eval("wide.per") == 5 and wow.eval("wide.height") == 92
    assert wow.eval("wide.rects[1].w") == (1532 - 30 - 44) // 5
    assert wow.eval("wide.rects[5].y") == 0
    # under 900: three and two
    assert wow.eval("mid.per") == 3 and wow.eval("mid.height") == 92 + 11 + 92
    assert wow.eval("mid.rects[4].y") == 103 and wow.eval("mid.rects[4].x") == 0
    # under 600: one column
    assert wow.eval("narrow.per") == 1 and wow.eval("narrow.height") == 5 * 92 + 4 * 11
    assert wow.eval("wide.lines") == 2 and wow.eval("mid.lines") == 2
    # at 1,100 the five cards are 205 wide: the sentence takes a third line and the card grows
    # by it (the windows probe, 24.11.2026: Collections' sentence needed three lines of two)
    wow.execute(f"tight = {CAB}.Entrances(1100 - 30)")
    assert wow.eval("tight.per") == 5 and wow.eval("tight.rects[1].w") == (1100 - 30 - 44) // 5
    assert wow.eval("tight.lines") == 3 and wow.eval("tight.height") == 92 + 15
    assert wow.errors == []


TILE = f"""
TILE = {CAB}.NewTile(UIParent)
CTX = {{ today = "2026-11-16", level = 24, isDone = function() return false end }}
function fill(e, role, slot, front)
  local rect = {{ x = 0, y = 0, w = role == "main" and 709 or 349, h = role == "single" and 169 or 349,
    slot = slot or 2, role = role }}
  return {CAB}.Fill(TILE, e, rect, front or {{ six = {{}}, chapters = {{}} }}, CTX)
end
"""


def test_a_tile_is_drawn_by_what_it_holds(wow: WowRuntime):
    boot(wow)
    wow.execute(TILE)
    # a gold story as the main tile: the picture, the fade, its words on it, the title at 27
    wow.execute(
        """
        KIND = fill({ id = "g1", chapter = "gold", kind = "farming", page = true, title = "Wolf Flanks",
          hook = "It is dark in Duskwood at noon.", added = "2026-11-12", levelMin = 20, levelMax = 24 },
          "main", 0)
        """
    )
    assert wow.eval("KIND") == "picture" and wow.eval("TILE.kind") == "picture"
    assert wow.eval("TILE.pic:IsShown()") is True and wow.eval("TILE.shade:IsShown()") is True
    assert wow.eval("TILE.paper:IsShown()") is False
    assert wow.eval("TILE.ti:GetText()") == "Wolf Flanks"
    assert tuple(wow.eval("TILE.ti:GetFont()"))[:2] == (wow.eval(f"{S}.BOOK_FONTS.bookDisplay"), 27)
    assert wow.eval("TILE.ti:GetWidth()") == 709 - 2 * 16  # never past the tile's edge
    assert wow.eval("TILE.ho:IsShown()") is True
    assert wow.eval("TILE.eb:GetText()") == "the newest gold story  -  12.11  -  level 20 to 24"
    assert wow.eval("TILE.ribbon:IsShown()") is True  # four days old: new
    assert wow.eval("TILE.shade:GetHeight()") == int(349 * 0.45)
    # a single cell: the title at 18, no line of Bastian's
    wow.execute(
        """
        KIND = fill({ id = "r1", chapter = "rares", kind = "rare", title = "Lupos",
          hook = "A grey wolf.", levelMin = 23, levelMax = 23 }, "single", 3)
        """
    )
    assert wow.eval("KIND") == "picture"
    assert wow.eval("(select(2, TILE.ti:GetFont()))") == 18
    assert wow.eval("TILE.ho:IsShown()") is False and wow.eval("TILE.ribbon:IsShown()") is False
    assert wow.eval("TILE.eb:GetText()") == "rare  -  level 23"
    # the tall tile carries Bastian's line too
    wow.execute(
        'fill({ id = "r1", chapter = "rares", kind = "rare", title = "Lupos", hook = "x" }, "tall", 1)'
    )
    assert wow.eval("TILE.ho:IsShown()") is True
    # a secret not yet opened: a sealed letter on paper, nothing of the tale
    wow.execute(
        """
        KIND = fill({ id = "s1", chapter = "secrets", kind = "chain", title = "The Bloody Map",
          hook = "do not show this" }, "single", 2)
        """
    )
    assert wow.eval("KIND") == "letter"
    assert wow.eval("TILE.paper:IsShown()") is True and wow.eval("TILE.pic:IsShown()") is False
    assert wow.eval("TILE.seal:IsShown()") is True and wow.eval("TILE.seal:GetWidth()") == 41
    assert wow.eval(f"{S}.painted[TILE.seal][1] == {S}.C.folioSeal") is True
    assert wow.eval("TILE.ho:IsShown()") is False
    assert wow.eval("TILE.eb:GetText()") == "a secret  -  sealed until you open it"
    assert wow.eval(f"{S}.inked[TILE.ti] == {S}.C.folioInk") is True  # the paper's ink
    # a camp item: a mat, its line with the profession and the skill, its name
    wow.execute(
        """
        KIND = fill({ id = "c1", chapter = "camp", kind = "camp item", title = "Tanning Rack",
          facets = { profession = "Leatherworking", skill = 150 } }, "single", 4)
        """
    )
    assert wow.eval("KIND") == "camp"
    assert wow.eval("TILE.mat:IsShown()") is True and wow.eval("TILE.icon:IsShown()") is True
    assert wow.eval("TILE.mat:GetHeight()") == 169 - 44
    assert wow.eval("TILE.eb:GetText()") == "camp  -  leatherworking 150"
    assert wow.eval("TILE.ti:GetText()") == "Tanning Rack"
    assert wow.eval("TILE.seal:IsShown()") is False  # nothing of the tile before is left
    # R4.9: a camp item with Bastian's drawing shows it over the whole mat, cut to it; the file
    # is named with a dash for the id's colon. Without the drawing the icon stays (above)
    assert wow.eval("TILE.drew") == "plate"
    wow.execute(
        """
        KIND = fill({ id = "camp:279938", chapter = "camp", kind = "camp item", art = true,
          title = "Tanning Rack", facets = { profession = "Leatherworking", skill = 150 } },
          "single", 4)
        """
    )
    assert wow.eval("KIND") == "camp" and wow.eval("TILE.drew") == "art"
    art = wow.eval("TILE.icon:GetTexture()")
    assert art.endswith(r"Generated\Art\camp-279938")
    left, right, top, bottom = wow.eval("TILE.icon:GetTexCoord()")[:4]
    assert (left, right) == (0, 1) and 0 < top < bottom < 1  # a mat wider than 2:1 cuts the height
    wow.execute(
        """
        KIND = fill({ id = "c2", chapter = "camp", kind = "camp item", title = "Anvil",
          facets = {} }, "single", 4)
        """
    )
    assert wow.eval("TILE.drew") == "plate"
    assert tuple(wow.eval("TILE.icon:GetTexCoord()")[:4]) == (0, 1, 0, 1)  # whole again
    assert wow.errors == []


def test_a_collection_tile_shows_its_count_and_slots(wow: WowRuntime):
    boot(wow)
    wow.execute(TILE)
    wow.execute(
        """
        E = { id = "m1", chapter = "collections", kind = "mount", title = "Brown Horse" }
        FRONTT = { six = { E }, chapters = {}, collection = { kind = "mount", have = 3, total = 18, entry = E } }
        TILE:Hide()
        local rect = { x = 0, y = 0, w = 709, h = 169, slot = 5, role = "wide" }
        KIND = Bastians:GetModule('Strategies').Cabinet.Fill(TILE, E, rect, FRONTT, CTX)
        """
    )
    assert wow.eval("KIND") == "collection"
    assert wow.eval("TILE.ti:GetText()") == "Mounts"
    assert wow.eval("TILE.ct:GetText()") == "3 of 18"
    # 18 slots of 22 with 4 between fit in 709 - 32; the first three are the book's gold
    assert wow.eval("TILE.shownSlots") == 18 and wow.eval("TILE.more:IsShown()") is False
    assert wow.eval("TILE.slots[1]:GetWidth()") == 22
    assert wow.eval(f"{S}.painted[TILE.slots[3].fill][2]") == 1
    assert wow.eval(f"{S}.painted[TILE.slots[4].fill][2]") == 0
    assert wow.eval("(select(4, TILE.slots[2]:GetPoint(1)))") == 26
    # a narrow tile: as many as fit, then "+ N"
    wow.execute(
        """
        local rect = { x = 0, y = 0, w = 300, h = 169, slot = 5, role = "wide" }
        Bastians:GetModule('Strategies').Cabinet.Fill(TILE, E, rect, FRONTT, CTX)
        """
    )
    shown = wow.eval("TILE.shownSlots")
    assert 0 < shown < 18 and wow.eval("TILE.more:GetText()") == f"+ {18 - shown}"
    assert wow.eval("TILE.slots[18]:IsShown()") is False
    assert wow.errors == []


def test_a_tile_rises_under_the_mouse_and_sinks_on_a_press(wow: WowRuntime):
    """R4.6 (book-look.md 10.3; the hover should be seen "without
    looking for it"): at rest a shadow 4 down and 12 soft; under the mouse 2 up, the shadow 8 and
    20, the edge 2 wide in the book's gold; pressed 1 down, the shadow 2 and 6, the edge stays."""
    boot(wow)
    wow.execute(TILE)
    wow.execute('TILE:Rest("TOPLEFT", UIParent, "TOPLEFT", 100, -50)')

    def state() -> tuple:
        return (
            wow.eval("TILE.objectState"),
            wow.eval("(select(5, TILE:GetPoint(1)))"),
            wow.eval("TILE.shadowDrop"),
            wow.eval("TILE.shadowSpread"),
            wow.eval(f"{S}.painted[TILE.lit.outer][2]"),
            wow.eval(f"{S}.painted[TILE.lit.inner][2]"),
        )

    assert state() == ("rest", -50, 4, 12, 0, 0)
    assert wow.eval("TILE.lit.top:GetHeight()") == 1 and wow.eval("TILE.lit.foot:GetHeight()") == 1
    assert wow.eval(f"{S}.painted[TILE.lit.top][1] == {S}.C.folioLight") is True
    assert wow.eval(f"{S}.painted[TILE.lit.foot][1] == {S}.C.folioDark") is True
    wow.execute("TILE:GetScript('OnEnter')(TILE)")
    assert state() == ("hover", -48, 8, 20, 1, 1)
    assert wow.eval(f"{S}.painted[TILE.lit.outer][1] == {S}.C.folioGold") is True
    wow.execute("TILE:GetScript('OnMouseDown')(TILE)")
    assert state() == ("press", -51, 2, 6, 1, 1)
    wow.execute("TILE:GetScript('OnLeave')(TILE)")
    assert state() == ("rest", -50, 4, 12, 0, 0)
    # a tile that goes while lifted comes back at rest
    wow.execute("TILE:GetScript('OnEnter')(TILE); TILE:Hide(); TILE:Show()")
    assert state() == ("rest", -50, 4, 12, 0, 0)
    # placed anew, it keeps the place it was given
    wow.execute('TILE:Rest("TOPLEFT", UIParent, "TOPLEFT", 10, -20)')
    assert wow.eval("(select(4, TILE:GetPoint(1)))") == 10
    assert wow.eval("(select(5, TILE:GetPoint(1)))") == -20
    assert wow.errors == []


def size(wow: WowRuntime, w: int = 1532, h: int = 843) -> None:
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


def test_the_front_table_in_the_window(wow: WowRuntime):
    """The fixture book: the cabinet first, Bastian's note under it, then one entrance per
    chapter; no strips of tiles and no "New on the table" any more."""
    boot(wow, pack=True)
    wow.slash("/bbook")
    assert wow.eval(f"{WIN}.Current().kind") == "front"
    size(wow)
    kinds = [item.kind for item in wow.eval(f"{FRONT}.list.items").values()]
    assert kinds == ["cabinet", "bnote", "entrances"]
    front = f"{FRONT}.list.items[1].front"
    assert wow.eval(f"{front}.main.page") is True  # a gold page of the book
    # E2: what nobody reported in Forever yet is never on the table
    table = {e.id for e in wow.eval(f"{front}.six").values()} | {wow.eval(f"{front}.main.id")}
    assert not table & {"mount:458", "pet:4055", "pet:10675", "rare:99", "rare:5912", "title:1258"}
    # the tiles in view are the table's, each in its cell
    wow.execute(
        f"""
        ROW = nil
        for _, row in ipairs({FRONT}.list:Rows()) do
          if row.layout and row.tiles then ROW = row end
        end
        """
    )
    assert wow.eval("ROW.layout.cols") == 3
    assert wow.eval("ROW.tiles[1].entry.id") == wow.eval(f"{front}.main.id")
    assert tuple(wow.eval("ROW.tiles[1]:GetSize()")) == (
        wow.eval("ROW.layout.rects[1].w"),
        wow.eval("ROW.layout.rects[1].h"),
    )
    shown = set(wow.eval(f"{FRONT}.TilesInView()").values())
    assert table <= shown
    # a click on a tile opens its page
    wow.execute("ROW.tiles[1]:Click()")
    assert wow.eval(f"{WIN}.Current().kind") == "page"
    assert wow.eval(f"{WIN}.Current().id") == wow.eval(f"{front}.main.id")
    assert wow.errors == []


def test_bastians_note_and_the_entrances(wow: WowRuntime):
    boot(wow, pack=True)
    wow.slash("/bbook")
    size(wow)
    items = f"{FRONT}.list.items"
    note = wow.eval(f"{items}[2].text")
    assert note.endswith("It changes when you move on.")
    assert wow.eval(f"{items}[2].act.label") == "Surprise me"
    # the note names the zone and the level where the character has both
    wow.execute(
        f"""
        ZONED = {CAB}.Note({{ level = 24, here = {{ map = 1431 }} }})
        PLAIN = {CAB}.Note({{}})
        """
    )
    assert "level 24" in wow.eval("ZONED") or wow.eval("ZONED") == wow.eval("PLAIN")
    # an entrance: the chapter's name, its sentence, what is open
    wow.execute(
        f"""
        ENT = nil
        for _, row in ipairs({FRONT}.list:Rows()) do
          if row.cards then ENT = row end
        end
        """
    )
    assert wow.eval("#ENT.cards") == 5
    names = [wow.eval(f"ENT.cards[{i}].ti:GetText()") for i in range(1, 6)]
    assert names == ["Gold", "Secrets", "Collections", "Camp", "Rares"]
    assert wow.eval("ENT.cards[5].line:GetText()") == "What is worth a hunt."
    assert " open" in wow.eval("ENT.cards[1].kd:GetText()")
    assert wow.eval(f"{CAB}.Count({{ open = 29, near = 3 }})") == "29 open, 3 near you"
    assert wow.eval(f"{CAB}.Count({{ open = 41, near = 0 }})") == "41 open"
    # an entrance is an object too, and a click opens its shelf
    wow.execute("ENT.cards[5]:GetScript('OnEnter')(ENT.cards[5])")
    assert wow.eval("ENT.cards[5].objectState") == "hover"
    wow.execute("ENT.cards[5]:Click()")
    assert (
        wow.eval(f"{WIN}.Current().kind") == "shelf" and wow.eval(f"{WIN}.Current().id") == "rares"
    )
    assert wow.errors == []
