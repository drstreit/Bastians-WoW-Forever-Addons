"""The Atlas with filters, its pure part (W8 of plan-suite-waves.md, R4.12; book.md "The Atlas
with filters"; book-look.md 10.10): which wonders stand on the world picture and in a zone, as
what and where; what has no place gets none; a zone's others are one disc with a count; tokens
never cover each other; a round visits the nearest next and at most twelve stops."""

import math

from harness import WowRuntime
from test_book_pages import MOD, boot

ATLAS = f"{MOD}.Atlas"
SHELF = f"{MOD}.Shelf"

# A small world of its own: every zone is two tiles square on the Eastern Kingdoms' part of the
# picture, its id says where; a zone from 9000 on has no world position at all.
WORLD = f"""
local TILE = 1600 / 3
local ORIGIN = 32 * TILE
local function corner(zone)
  return 25 + (zone % 5) * 4, 20 + (math.floor(zone / 5) % 5) * 6
end
CTX = {{
  level = 24,
  opened = {{}}, done = {{}},
  worldOf = function(zone, x, y)
    if zone >= 9000 then return nil end
    local c0, r0 = corner(zone)
    return 0, ORIGIN - (r0 + y * 2) * TILE, ORIGIN - (c0 + x * 2) * TILE
  end,
  mapOf = function(continent, wx, wy, zone)
    local c0, r0 = corner(zone)
    return ((ORIGIN - wy) / TILE - c0) / 2, ((ORIGIN - wx) / TILE - r0) / 2
  end,
  zoneOf = function(zone) return {{ name = "Zone " .. zone, continent = 0 }} end,
}}
CTX.isOpened = function(id) return CTX.opened[id] == true end
CTX.isDone = function(id) return CTX.done[id] == true end
function E(id, chapter, kind, zone, x, y, more)
  local e = {{ id = id, title = id, chapter = chapter, kind = kind, facets = {{}}, state = "in",
    zones = zone and {{ zone }} or nil, place = x and {{ zone, x, y }} or nil }}
  for k, v in pairs(more or {{}}) do e[k] = v end
  return e
end
F = {ATLAS}.NewFilter()
"""


def setup(wow: WowRuntime, entries: str) -> None:
    boot(wow)
    wow.execute(WORLD + f"\nLIST = {{ {entries} }}")


def world(wow: WowRuntime, w: int = 1532, h: int = 766) -> None:
    wow.execute(f"W = {ATLAS}.World(LIST, F, CTX, {w}, {h})")


def ids(wow: WowRuntime, expr: str) -> list[str]:
    wow.execute(f"IDS = {{}}; for _, t in ipairs({expr}) do IDS[#IDS + 1] = (t.entry or t).id end")
    return sorted(wow.eval("IDS").values())


def test_the_filter_is_a_shelfs_filter(wow: WowRuntime):
    setup(wow, "")
    wow.execute(f"F.chapters.rares = true; F.kinds.rare = true; S1 = {ATLAS}.ShelfFilter(F, CTX)")
    assert wow.eval("S1.facets.chapter.rares") is True and wow.eval("S1.facets.kind.rare") is True
    assert wow.eval(f"{ATLAS}.OneChapter(F)") == "rares"
    # with two chapters the kinds of one are no filter, and no chapter is "the one"
    wow.execute(f"F.chapters.gold = true; S2 = {ATLAS}.ShelfFilter(F, CTX)")
    assert wow.eval("S2.facets.kind") is None and wow.eval(f"{ATLAS}.OneChapter(F)") is None
    # a chip switched off again is no choice
    wow.execute(
        f"F.chapters.gold = false; F.chapters.rares = false; S3 = {ATLAS}.ShelfFilter(F, CTX)"
    )
    assert wow.eval("S3.facets.chapter") is None
    # my level: three below to three above, as on the shelves
    wow.execute(f"F.mine = true; S4 = {ATLAS}.ShelfFilter(F, CTX)")
    assert wow.eval("S4.lo") == 21 and wow.eval("S4.hi") == 27
    assert wow.errors == []


def test_on_the_world_some_stand_alone_and_a_zones_others_are_one_disc(wow: WowRuntime):
    setup(
        wow,
        """
        E("story", "gold", "farming", 7, 0.5, 0.5, { page = true }),
        E("chain:x", "secrets", "chain", 7, 0.2, 0.2),
        E("chain:camp", "camp", "camping", 8, 0.5, 0.5),
        E("rare:1", "rares", "rare", 7, 0.3, 0.6, { npc = 1 }),
        E("rare:2", "rares", "rare elite", 7, 0.7, 0.4, { npc = 2 }),
        E("book:3", "collections", "library book", 7, 0.5, 0.9),
        E("mount:4", "collections", "mount", 7),
        E("rare:5", "rares", "rare", 11, 0.5, 0.5, { npc = 5 }),
        """,
    )
    world(wow)
    assert ids(wow, "W.tokens") == ["chain:camp", "chain:x", "rare:5", "story"]
    assert wow.eval("#W.discs") == 1
    # the disc counts every other wonder of the zone, the one with only a zone too
    assert wow.eval("W.discs[1].zone") == 7 and wow.eval("W.discs[1].count") == 4
    assert wow.eval("W.discs[1].name") == "Zone 7"
    assert ids(wow, "W.discs[1].entries") == ["book:3", "mount:4", "rare:1", "rare:2"]
    # a zone's only wonder is itself, small as on the world
    wow.execute("for _, t in ipairs(W.tokens) do if t.entry.id == 'rare:5' then ONE = t end end")
    assert wow.eval("ONE.form.form") == "rare" and wow.eval("ONE.form.size") == 26
    assert wow.eval("W.shown") == 8 and wow.eval("W.offTotal") == 0
    assert wow.errors == []


def test_what_has_no_place_gets_no_spot(wow: WowRuntime):
    setup(
        wow,
        """
        E("page:auction", "gold", "auction", nil, nil, nil, { page = true }),
        E("page:cooking", "gold", "trades", nil, nil, nil, { page = true }),
        E("title:1", "collections", "title"),
        E("camp:2", "camp", "camp item"),
        E("rare:far", "rares", "rare", 9001, 0.5, 0.5),
        """,
    )
    world(wow)
    assert wow.eval("#W.tokens") == 0 and wow.eval("#W.discs") == 0
    assert ids(wow, "W.boards.market") == ["page:auction"]
    assert ids(wow, "W.boards.trades") == ["page:cooking"]
    assert wow.eval("W.off.collections") == 1 and wow.eval("W.off.camp") == 1
    assert wow.eval("W.off.rares") == 1  # a place the picture does not hold
    assert wow.eval("W.off.gold") is None and wow.eval("W.offTotal") == 5
    assert wow.errors == []


def test_the_filter_changes_the_map(wow: WowRuntime):
    setup(
        wow,
        """
        E("story", "gold", "farming", 7, 0.5, 0.5, { page = true, levelMin = 20, levelMax = 24 }),
        E("rare:low", "rares", "rare", 8, 0.5, 0.5, { levelMin = 10, levelMax = 10 }),
        E("rare:mine", "rares", "rare", 9, 0.5, 0.5, { levelMin = 25, levelMax = 25 }),
        E("rare:unseen", "rares", "rare elite", 12, 0.5, 0.5, { state = "unknown" }),
        E("rare:done", "rares", "rare", 13, 0.5, 0.5),
        """,
    )
    wow.execute("CTX.done['rare:done'] = true")
    world(wow)
    assert ids(wow, "W.tokens") == ["rare:low", "rare:mine", "story"]
    wow.execute(f"C = {ATLAS}.Counts(LIST, F, CTX)")
    assert wow.eval("C.chapters.rares") == 2 and wow.eval("C.chapters.gold") == 1
    assert wow.eval("C.unconfirmed") == 1 and wow.eval("C.done") == 1
    wow.execute("F.unconfirmed = true; F.showDone = true")
    world(wow)
    assert ids(wow, "W.tokens") == ["rare:done", "rare:low", "rare:mine", "rare:unseen", "story"]
    wow.execute("for _, t in ipairs(W.tokens) do FORM = FORM or {}; FORM[t.entry.id] = t.form end")
    assert wow.eval("FORM['rare:unseen'].unconfirmed") is True
    assert wow.eval("FORM['rare:unseen'].elite") is True
    assert wow.eval("FORM['rare:done'].done") is True and wow.eval("FORM['story'].done") is None
    # my level; a wonder without a level always passes (unknown is not zero)
    wow.execute("F.unconfirmed = false; F.showDone = false; F.mine = true")
    world(wow)
    assert ids(wow, "W.tokens") == ["rare:mine", "story"]
    wow.execute("F.mine = false; F.unconfirmed = true; F.showDone = true; F.chapters.rares = true")
    world(wow)
    assert "story" not in ids(wow, "W.tokens")
    wow.execute(f"C = {ATLAS}.Counts(LIST, F, CTX)")
    # a chapter's chip counts what choosing it would show; the kinds are the one chapter's
    assert wow.eval("C.chapters.gold") == 1
    assert wow.eval("C.kinds.rare") == 3 and wow.eval("C.kinds['rare elite']") == 1
    wow.execute("F.kinds['rare elite'] = true")
    world(wow)
    assert ids(wow, "W.tokens") == ["rare:unseen"]
    assert wow.errors == []


def test_at_most_four_stand_alone_in_a_zone(wow: WowRuntime):
    pages = "\n".join(
        f'E("page:{i}", "gold", "farming", 7, 0.{i}, 0.5, {{ page = true }}),' for i in range(1, 8)
    )
    setup(wow, pages)
    world(wow)
    assert wow.eval("#W.tokens") == 4
    assert wow.eval("#W.discs") == 1 and wow.eval("W.discs[1].count") == 3
    assert wow.errors == []


def test_tokens_never_cover_each_other_and_keep_off_the_boards(wow: WowRuntime):
    # six zones side by side and on top of each other, each with a page, a secret, a camp and rares
    parts = []
    for zone in (0, 1, 2, 5, 6, 7):
        parts.append(f'E("page:{zone}", "gold", "farming", {zone}, 0.5, 0.5, {{ page = true }}),')
        parts.append(f'E("chain:{zone}", "secrets", "chain", {zone}, 0.5, 0.5),')
        parts.append(f'E("chain:camp{zone}", "camp", "camping", {zone}, 0.52, 0.5),')
        for i in range(25):
            parts.append(f'E("rare:{zone}-{i}", "rares", "rare", {zone}, 0.{i:02d}, 0.5),')
    setup(wow, "\n".join(parts))
    world(wow)
    wow.execute(
        """
        ALL = {}
        for _, t in ipairs(W.tokens) do
          ALL[#ALL + 1] = { x = t.x, y = t.y, r = t.form.size / 2 + t.form.ring, id = t.entry.id }
        end
        for _, d in ipairs(W.discs) do
          ALL[#ALL + 1] = { x = d.x, y = d.y, r = (d.big and 36 or 30) / 2 + 2, id = "zone" .. d.zone }
        end
        """
    )
    pts = [dict(p) for p in wow.eval("ALL").values()]
    assert len(pts) == 6 * 4
    for i, a in enumerate(pts):
        for b in pts[i + 1 :]:
            d = math.hypot(a["x"] - b["x"], a["y"] - b["y"])
            assert d >= a["r"] + b["r"] + 6 - 0.6, (a["id"], b["id"], d)
        assert 1532 * 0.17 + 10 <= a["x"] <= 1532 - 1532 * 0.17 - 10, a
        assert 6 <= a["y"] <= 766 - 6, a
    assert wow.eval("W.discs[1].big") is True and wow.eval("W.discs[1].count") == 25
    # a pushed token keeps its true place and says that it moved
    wow.execute(
        "MOVED = 0; for _, t in ipairs(W.tokens) do if t.moved then MOVED = MOVED + 1 end end"
    )
    assert wow.eval("MOVED") > 0
    assert wow.errors == []


def test_two_thousand_wonders_cost_a_screenful_of_tokens(wow: WowRuntime):
    setup(wow, "")
    wow.execute(
        """
        LIST = {}
        local chapters = { { "gold", "farming" }, { "secrets", "chain" }, { "camp", "camping" },
          { "rares", "rare" }, { "collections", "library book" } }
        for i = 1, 2000 do
          local c = chapters[i % 5 + 1]
          LIST[i] = E(c[1] .. ":" .. i, c[1], c[2], math.floor(i / 5) % 25, (i * 37 % 100) / 100, (i * 53 % 100) / 100,
            { page = c[1] == "gold" or nil })
        end
        """
    )
    world(wow)
    assert wow.eval("W.shown") == 2000
    # 25 zones: four alone and one disc each
    assert wow.eval("#W.tokens") == 100 and wow.eval("#W.discs") == 25
    wow.execute("SUM = 0; for _, d in ipairs(W.discs) do SUM = SUM + d.count end")
    assert wow.eval("SUM") == 1900
    assert wow.errors == []


def test_a_zone_shows_every_wonder_on_its_spot(wow: WowRuntime):
    setup(
        wow,
        """
        E("story", "gold", "farming", 7, 0.5, 0.25, { page = true }),
        E("rare:1", "rares", "rare", 7, 0.3, 0.6, { npc = 1 }),
        E("rare:2", "rares", "rare elite", 7, 0.31, 0.6, { npc = 2 }),
        E("mount:4", "collections", "mount", 7),
        E("rare:other", "rares", "rare", 8, 0.5, 0.5),
        """,
    )
    # a place given on a sub map: zone 12 stands where zone 7's right half is
    wow.execute(
        "LIST[#LIST + 1] = E('book:sub', 'collections', 'library book', 7); LIST[#LIST].place = { 7, 0.9, 0.9 }"
    )
    wow.execute(f"Z = {ATLAS}.Zone(LIST, 7, F, CTX, 1149, 766)")
    assert ids(wow, "Z.tokens") == ["book:sub", "rare:1", "rare:2", "story"]
    assert ids(wow, "Z.somewhere") == ["mount:4"]
    assert wow.eval("Z.total") == 5
    assert wow.eval("Z.counts.rares") == 2 and wow.eval("Z.counts.collections") == 2
    wow.execute("T = {}; for _, t in ipairs(Z.tokens) do T[t.entry.id] = t end")
    assert wow.eval("T.story.x") == 0.5 * 1149 and wow.eval("T.story.y") == 0.25 * 766
    assert wow.eval("T.story.moved") is None
    # in a zone a rare is its full size, and the two that share a spot part
    assert wow.eval("T['rare:1'].form.size") == 33
    d = math.hypot(
        wow.eval("T['rare:1'].x") - wow.eval("T['rare:2'].x"),
        wow.eval("T['rare:1'].y") - wow.eval("T['rare:2'].y"),
    )
    assert d >= 2 * (33 / 2 + 2) + 6 - 0.6
    assert wow.eval("T['rare:1'].moved") is True and wow.eval("T['rare:1'].tx") == 0.3
    assert wow.errors == []


def test_a_place_on_another_map_is_found_through_the_world(wow: WowRuntime):
    setup(wow, 'E("cave", "gold", "farming", 7, nil, nil, { page = true }),')
    # zone 107 lies where zone 7 does (107 % 5 == 2, as 7), so its middle is zone 7's middle
    wow.execute("LIST[1].place = { 107, 0.25, 0.75 }")
    wow.execute(f"X, Y = {ATLAS}.InZone(LIST[1], 7, CTX)")
    assert abs(wow.eval("X") - 0.25) < 1e-9 and abs(wow.eval("Y") - 0.75) < 1e-9
    # a place outside the zone's painting is no spot there
    wow.execute("LIST[1].place = { 8, 0.5, 0.5 }")
    assert wow.eval(f"({ATLAS}.InZone(LIST[1], 7, CTX))") is None
    assert wow.errors == []


def test_a_sealed_secret_shows_no_trail(wow: WowRuntime):
    setup(
        wow,
        """
        E("chain:bag", "secrets", "chain", 7, 0.2, 0.2,
          { steps = { { place = { 7, 0.2, 0.2 } }, { place = { 7, 0.8, 0.8 } }, { place = { 8, 0.5, 0.5 } } } }),
        E("chain:camp", "camp", "camping", 8, 0.5, 0.5,
          { steps = { { place = { 8, 0.4, 0.4 } }, { place = { 7, 0.6, 0.1 } } } }),
        E("chain:open", "secrets", "unsolved", 7, 0.6, 0.6, { steps = { { place = { 7, 0.6, 0.6 } }, { } } }),
        """,
    )
    assert wow.eval(f"{ATLAS}.Form(LIST[1], CTX).form") == "seal"
    assert wow.eval(f"{ATLAS}.Form(LIST[3], CTX).form") == "broken"
    assert wow.eval(f"{ATLAS}.HasTrail(LIST[1], CTX)") is False
    assert wow.eval(f"#{ATLAS}.TrailWorld(LIST[1], CTX)") == 0
    wow.execute(f"Z = {ATLAS}.Zone(LIST, 7, F, CTX, 1000, 1000)")
    # the camp of the next zone has a step here; the sealed secret none; the unsolved never
    assert wow.eval("#Z.steps") == 1 and wow.eval("Z.steps[1].entry.id") == "chain:camp"
    assert wow.eval("Z.steps[1].n") == 2 and wow.eval("Z.steps[1].x") == 600
    wow.execute(f"CTX.opened['chain:bag'] = true; Z = {ATLAS}.Zone(LIST, 7, F, CTX, 1000, 1000)")
    assert wow.eval(f"{ATLAS}.Form(LIST[1], CTX).form") == "opened"
    assert wow.eval("#Z.steps") == 3
    assert wow.eval(f"#{ATLAS}.TrailWorld(LIST[1], CTX)") == 3
    assert wow.errors == []


def test_a_round_goes_to_the_nearest_next_and_holds_twelve(wow: WowRuntime):
    rares = "\n".join(
        f'E("rare:{i:02d}", "rares", "rare", 7, 0.{i:02d}, 0.5),' for i in range(5, 95, 5)
    )
    setup(wow, rares)
    wow.execute(f"Z = {ATLAS}.Zone(LIST, 7, F, CTX, 2000, 1400)")
    assert wow.eval("#Z.tokens") == 18
    # from the character at the right edge: the nearest first, twelve stops
    wow.execute(f"R = {ATLAS}.Round(Z.tokens, nil, {{ x = 1, y = 0.5 }})")
    assert wow.eval("#R") == 12
    assert ids(wow, "{ R[1], R[2], R[3] }") == ["rare:80", "rare:85", "rare:90"]
    assert wow.eval("R[1].entry.id") == "rare:90"
    # picked stops only
    wow.execute(
        f"R = {ATLAS}.Round(Z.tokens, {{ ['rare:10'] = true, ['rare:50'] = true }}, {{ x = 0, y = 0.5 }})"
    )
    assert wow.eval("#R") == 2 and wow.eval("R[1].entry.id") == "rare:10"
    # the route service's stops: an id, a name, the thing, a place in world yards
    wow.execute(f"LIST[2].npc = 77; STOPS = {ATLAS}.Stops(R, 7, CTX)")
    assert wow.eval("#STOPS") == 2 and wow.eval("STOPS[1].id") == "rare:10"
    assert wow.eval("STOPS[1].ref") == "npc:77" and wow.eval("STOPS[1].place.map") == 0
    assert wow.eval("STOPS[1].place.wx") is not None and wow.eval("STOPS[1].place.wy") is not None
    assert wow.eval(f"#{ATLAS}.Round({{}}, nil, nil)") == 0
    assert wow.errors == []


def test_the_thing_a_wonder_is(wow: WowRuntime):
    setup(wow, "")
    ref = f"{ATLAS}.RefOf"
    assert wow.eval(
        f"{ref}(E('duskwood-flanks', 'gold', 'farming', 7, nil, nil, {{ page = true }}))"
    ) == ("page:duskwood-flanks")
    assert (
        wow.eval(f"{ref}(E('rare:521', 'rares', 'rare', 7, nil, nil, {{ npc = 521 }}))")
        == "npc:521"
    )
    assert wow.eval(
        f"{ref}(E('book:1', 'collections', 'library book', 7, nil, nil, {{ gives = {{ 203754 }} }}))"
    ) == ("item:203754")
    assert wow.eval(f"{ref}(E('mount:1', 'collections', 'mount', 7))") == "zone:7"
    assert wow.eval(f"{ref}(E('title:1', 'collections', 'title'))") is None
    assert wow.errors == []


def test_a_hosted_layer_is_asked_for_the_picture(wow: WowRuntime):
    setup(wow, "")
    wow.execute(f"V = {ATLAS}.WorldViews()")
    assert (
        wow.eval("#V") == 2 and wow.eval("V[1].continent") == 0 and wow.eval("V[2].continent") == 1
    )
    assert wow.eval("V[1].x1 < V[1].x2") is True and wow.eval("V[1].y1 < V[1].y2") is True
    # a pin in the middle of the Eastern Kingdoms' part lies on the picture, one far off does not
    wow.execute(
        f"""
        PIN = {{ wx = (V[1].x1 + V[1].x2) / 2, wy = (V[1].y1 + V[1].y2) / 2 }}
        FX, FY = {ATLAS}.PinSpot(PIN, V[1], nil, CTX)
        OUT = {ATLAS}.PinSpot({{ wx = V[1].x2 + 5000, wy = PIN.wy }}, V[1], nil, CTX)
        """
    )
    assert 0.5 < wow.eval("FX") < 0.9 and 0.3 < wow.eval("FY") < 0.7
    assert wow.eval("OUT") is None
    # in a zone the pin lies on the zone's painting
    wow.execute(
        f"""
        ZV = {ATLAS}.ZoneView(7, CTX)
        local c, wx, wy = CTX.worldOf(7, 0.25, 0.75)
        ZX, ZY = {ATLAS}.PinSpot({{ wx = wx, wy = wy }}, ZV, 7, CTX)
        """
    )
    assert wow.eval("ZV.continent") == 0 and wow.eval("ZV.x1 < ZV.x2") is True
    assert abs(wow.eval("ZX") - 0.25) < 1e-6 and abs(wow.eval("ZY") - 0.75) < 1e-6
    assert wow.eval(f"{ATLAS}.ZoneView(9001, CTX)") is None
    assert wow.errors == []
