"""Bastian's Book: the shelf (book.md "Filters and search") on 2,000 simulated wonders: every
filter, the counts beside the chips, the search, the sorts, the day's order, the front table."""

import pytest
from harness import WowRuntime

CORE, DATA, STRAT = "Bastians_Core", "Bastians_Data", "Bastians_Strategies"
SHELF = "Bastians:GetModule('Strategies').Shelf"
N = 2000

CTX = f"""
local S = {SHELF}
done = done or {{}}
ctx = {{
  isDone = function(id) return done[id] == true end,
  zoneOf = S.SimZone,
  today = "2026-11-16",
}}
"""


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA, STRAT)
    wow.run_frames(5)
    wow.execute(f"shelf = {SHELF}.Simulate({N}, 7)" + CTX)
    return wow


def count(wow: WowRuntime, filt: str) -> int:
    return wow.eval(f"#({SHELF}.Filter(shelf, {filt}, ctx))")


def ids(wow: WowRuntime, filt: str) -> list[str]:
    wow.execute(
        f"local out = {SHELF}.Filter(shelf, {filt}, ctx); got = {{}}; for i, e in ipairs(out) do got[i] = e.id end"
    )
    return list(wow.eval("got").values())


def chips(wow: WowRuntime, filt: str, dim: str) -> list[tuple]:
    wow.execute(f'chipsOut = {SHELF}.Counts(shelf, {filt}, ctx, "{dim}")')
    return [(c.value, c.n) for c in wow.eval("chipsOut").values()]


def test_the_simulation_is_the_same_for_the_same_seed(wow: WowRuntime):
    boot(wow)
    first = wow.eval(f"{SHELF}.Simulate(50, 7)[50].title")
    assert first == wow.eval(f"{SHELF}.Simulate(50, 7)[50].title")
    assert first != wow.eval(f"{SHELF}.Simulate(50, 8)[50].title")
    chapters = {v for v, _ in chips(wow, f"{SHELF}.NewFilter()", "chapter")}
    assert chapters == {"gold", "secrets", "collections", "camp", "rares"}  # E1
    assert (
        wow.eval(
            "(function() local n = 0 for _, e in ipairs(shelf) do if not e.zones then n = n + 1 end end return n end)()"
        )
        > 50
    )
    assert (
        wow.eval(
            "(function() local n = 0 for _, e in ipairs(shelf) do if not e.levelMin then n = n + 1 end end return n end)()"
        )
        > 50
    )
    assert wow.errors == []


@pytest.mark.parametrize("dim", ["chapter", "continent", "zone"])
def test_a_chips_count_is_what_a_click_leaves(wow: WowRuntime, dim):
    boot(wow)
    base = f"{SHELF}.NewFilter()"
    for value, n in chips(wow, base, dim):
        key = {"chapter": "chapter", "continent": "continent", "zone": "zone"}[dim]
        lit = f'"{value}"' if isinstance(value, str) else str(value)
        wow.execute(f"F = {base}; F.{key} = {lit}")
        assert count(wow, "F") == n, (dim, value)


@pytest.mark.parametrize(
    "chapter,key",
    [
        ("collections", "source"),
        ("rares", "type"),
        ("secrets", "kind"),
        ("camp", "profession"),
        ("camp", "skill"),
        ("gold", "kind"),
    ],
)
def test_a_facets_count_is_what_a_click_leaves(wow: WowRuntime, chapter, key):
    boot(wow)
    base = f'{SHELF}.NewFilter("{chapter}")'
    found = chips(wow, base, key)
    assert len(found) > 1
    for value, n in found:
        lit = f'"{value}"' if isinstance(value, str) else str(value)  # a skill is a number
        wow.execute(f'F = {base}; F.facets["{key}"] = {{ [{lit}] = true }}')
        assert count(wow, "F") == n


def test_the_chapters_have_their_own_facets_and_no_seen(wow: WowRuntime):
    """E1 and E2: the facet "seen in Forever" went with the label "Classic data"."""
    boot(wow)
    facets = {k: list(v.values()) for k, v in dict(wow.eval(f"{SHELF}.FACETS")).items()}
    assert facets == {
        "all": ["chapter", "side"],
        "gold": ["kind"],
        "secrets": ["kind", "side"],
        "collections": ["kind", "source", "side"],
        "camp": ["profession", "skill", "kind"],
        "rares": ["kind", "type"],
    }
    assert list(wow.eval(f"{SHELF}.CHAPTERS").values()) == [
        "gold",
        "secrets",
        "collections",
        "camp",
        "rares",
    ]
    assert (
        wow.eval(f'{SHELF}.FacetOf({{ facets = {{ seen = true }} }}, "seen")') is True
    )  # a plain facet


def test_what_nobody_reported_waits_behind_the_chip(wow: WowRuntime):
    """E2: an unknown wonder passes no filter until `unconfirmed` is on; the chip's count is what
    a click adds; it is never on the front table and never the surprise."""
    boot(wow)
    unknown = wow.eval(
        "(function() local n = 0 for _, e in ipairs(shelf) do if e.state == 'unknown' then n = n + 1 end end return n end)()"
    )
    assert 100 < unknown < N / 2
    base = f"{SHELF}.NewFilter()"
    shown = count(wow, base)
    assert shown == N - unknown
    assert wow.eval(f"{SHELF}.UnconfirmedCount(shelf, {base}, ctx)") == unknown
    wow.execute(f"F = {base}; F.unconfirmed = true")
    assert count(wow, "F") == N
    # the count follows the rest of the filter: a chapter, a zone, a search
    for setup in ('F.chapter = "rares"', "F.continent = 1", 'F.query = "wolf"'):
        wow.execute(f"F = {base}; {setup}")
        without = count(wow, "F")
        adds = wow.eval(f"{SHELF}.UnconfirmedCount(shelf, F, ctx)")
        wow.execute("F.unconfirmed = true")
        assert count(wow, "F") == without + adds, setup
        assert wow.eval(f"{SHELF}.UnconfirmedCount(shelf, F, ctx)") == adds  # on or off, the same
    # a chapter where everything is in has nothing behind the chip
    wow.execute(f'F = {SHELF}.NewFilter("camp")')
    assert wow.eval(f"{SHELF}.UnconfirmedCount(shelf, F, ctx)") == 0
    wow.execute(
        f"""
        local front = {SHELF}.Front(shelf, ctx)
        bad = 0
        if front.main.state == "unknown" then bad = bad + 1 end
        for _, e in ipairs(front.six) do if e.state == "unknown" then bad = bad + 1 end end
        for seed = 1, 200 do
          if {SHELF}.Surprise(shelf, ctx, seed * 7919).state == "unknown" then bad = bad + 1 end
        end
        """
    )
    assert wow.eval("bad") == 0
    assert wow.eval(f"{SHELF}.Unconfirmed({{ state = 'unknown' }})") is True
    assert wow.eval(f"{SHELF}.Unconfirmed({{ state = 'in' }})") is False
    assert wow.eval(f"{SHELF}.Unconfirmed({{}})") is False  # a pack without states: shown


def test_gold_is_newest_first_whatever_the_sort(wow: WowRuntime):
    """R4.8: the Gold shelf by the page's date, the undated last in the book's order; no sort
    changes it, and the day's shuffle does not either."""
    boot(wow)
    wow.execute(
        f"""
        local S = {SHELF}
        gold = {{
          S.FromPage("p:old", {{ name = "Old", chapter = "farming", updated = "2026-10-01" }}),
          S.FromPage("p:undated-b", {{ name = "B", chapter = "farming" }}),
          S.FromPage("p:new", {{ name = "New", chapter = "fishing", added = "2026-11-15" }}),
          S.FromPage("p:undated-a", {{ name = "A", chapter = "flips" }}),
          S.FromPage("p:mid", {{ name = "Mid", chapter = "trades", updated = "2026-11-02" }}),
        }}
        gold[2].order, gold[4].order = 7, 3  -- their places in the book's contents
        function goldIds(sort, today)
          local f = S.NewFilter("gold"); f.sort = sort
          local c = {{ today = today }}
          local out = {{}}
          for i, e in ipairs(S.Filter(gold, f, c)) do out[i] = e.id end
          return table.concat(out, " ")
        end
        """
    )
    want = "p:new p:mid p:old p:undated-a p:undated-b"
    for sort in ("newest", "level", "nearest", "az"):
        for today in ("2026-11-16", "2026-11-17"):
            assert wow.eval(f'goldIds("{sort}", "{today}")') == want, (sort, today)
    assert wow.eval(f"{SHELF}.FIXED_SORT.gold") == "dated"
    assert wow.eval(f"{SHELF}.FIXED_SORT.all") is None  # on Everything the sort stays
    wow.execute(
        f"""
        local f = {SHELF}.NewFilter(); f.sort = "az"
        local out = {SHELF}.Filter(gold, f, {{ today = "2026-11-16" }})
        firstAz = out[1].id
        """
    )
    assert wow.eval("firstAz") == "p:undated-a"


def test_a_pack_of_before_round_4_still_stands_on_the_shelves(wow: WowRuntime):
    """An older Data edition under a newer suite: its two old chapters are read by the kind, a
    record without a state is shown."""
    boot(wow)

    def entry(chapter: str, kind: str, extra: str = "") -> tuple:
        wow.execute(
            f'E = {SHELF}.FromWonder("x:1", {{ name = "X", chapter = "{chapter}", kind = "{kind}"{extra} }})'
        )
        return wow.eval("E.chapter"), wow.eval("E.kind"), wow.eval("E.state")

    assert entry("treasures", "secret") == ("secrets", "chain", None)
    assert entry("treasures", "secret", ", facets = { unsolved = true }")[:2] == (
        "secrets",
        "unsolved",
    )
    assert entry("treasures", "camping")[:2] == ("camp", "camping")
    assert entry("curiosities", "secret pet")[:2] == ("secrets", "pet")
    assert entry("curiosities", "library book")[:2] == ("collections", "library book")
    assert entry("curiosities", "camp item")[:2] == ("camp", "camp item")
    assert entry("collections", "mount", ', state = "unknown"') == (
        "collections",
        "mount",
        "unknown",
    )
    wow.execute(
        f'E = {SHELF}.FromWonder("pet:1", {{ name = "X", chapter = "collections", kind = "pet",'
        ' from = { { "drop", "npc:448" } } })'
    )
    assert wow.eval("E.from[1][2]") == "npc:448"  # the sources as references ride along (R4.3)


def test_facets_or_within_and_between(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f'F = {SHELF}.NewFilter("collections"); F.facets.source = {{ vendor = true, drop = true }}'
    )
    either = count(wow, "F")
    wow.execute("F.facets.source = { vendor = true }")
    vendor = count(wow, "F")
    wow.execute("F.facets.source = { drop = true }")
    drop = count(wow, "F")
    assert either == vendor + drop
    wow.execute("F.facets.source = { vendor = true }; F.facets.side = { A = true }")
    assert 0 < count(wow, "F") < vendor


def test_the_zone_chips_keep_the_continent(wow: WowRuntime):
    boot(wow)
    wow.execute(f"F = {SHELF}.NewFilter(); F.continent = 1")
    zones = dict(chips(wow, "F", "zone"))
    assert zones and all(wow.eval(f"{SHELF}.SimZone({z}).continent") == 1 for z in zones)
    for z, n in zones.items():
        wow.execute(f"F.zone = {z}")
        assert count(wow, "F") == n
    wow.execute("F.zone = nil")


def test_a_wonder_without_a_place_passes_only_everywhere(wow: WowRuntime):
    boot(wow)
    wow.execute(f"F = {SHELF}.NewFilter(); F.unconfirmed = true")  # every wonder, reported or not
    every = ids(wow, "F")
    wow.execute("F.continent = 0")
    east = set(ids(wow, "F"))
    placeless = set(
        wow.eval(
            "(function() local t = {} for _, e in ipairs(shelf) do if not e.zones then t[#t + 1] = e.id end end return t end)()"
        ).values()
    )
    assert placeless <= set(every) and not (placeless & east)


def test_the_level_range_overlaps_and_unknown_passes(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"""
        F = {SHELF}.NewFilter(); F.lo, F.hi = 18, 30
        local out = {SHELF}.Filter(shelf, F, ctx)
        bad, unknown = 0, 0
        for _, e in ipairs(out) do
          if e.levelMin then
            if e.levelMin > 30 or (e.levelMax or 60) < 18 then bad = bad + 1 end
          else unknown = unknown + 1 end
        end
        """
    )
    assert wow.eval("bad") == 0 and wow.eval("unknown") > 0
    assert list(wow.eval(f"{{ {SHELF}.MyLevel(24) }}").values()) == [21, 27]
    assert list(wow.eval(f"{{ {SHELF}.MyLevel(2) }}").values()) == [1, 5]
    assert wow.eval(f"{SHELF}.Fits({{ levelMin = 20, levelMax = 24 }}, 24)") is True
    assert wow.eval(f"{SHELF}.Fits({{ levelMin = 25, levelMax = 30 }}, 24)") is False
    assert wow.eval(f"{SHELF}.Fits({{}}, 24)") is False  # no band, never gold


def test_the_search_wants_every_word(wow: WowRuntime):
    boot(wow)
    wolf = ids(wow, f'(function() local f = {SHELF}.NewFilter(); f.query = "wolf"; return f end)()')
    both = ids(
        wow, f'(function() local f = {SHELF}.NewFilter(); f.query = "WOLF bag"; return f end)()'
    )
    assert wolf and both and set(both) <= set(wolf)
    for wid in both:
        text = wow.eval(
            f'(function() for _, e in ipairs(shelf) do if e.id == "{wid}" then return e.text end end end)()'
        )
        assert " wolf" in text and " bag" in text
    # a zone's name finds its wonders; accents fold; a word matches a word's start
    wow.execute(f'F = {SHELF}.NewFilter(); F.query = "elwyn"')
    elwynn = count(wow, "F")
    assert elwynn == dict(chips(wow, f"{SHELF}.NewFilter()", "zone"))[1429]
    wow.execute('F.query = "\\195\\137LWYNN"')  # an accented capital
    assert count(wow, "F") == elwynn > 0
    wow.execute('F.query = "lwynn"')  # inside a word: no
    assert count(wow, "F") == 0


def test_the_sorts(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"""
        local S = {SHELF}
        local out = S.Filter(shelf, S.NewFilter(), ctx)
        -- newest: the dated ones first, newest first
        okNewest, lastDate, undated = true, nil, false
        for _, e in ipairs(out) do
          if e.added then
            if undated or (lastDate and e.added > lastDate) then okNewest = false end
            lastDate = e.added
          else undated = true end
        end
        firstUndated = nil
        for _, e in ipairs(out) do if not e.added then firstUndated = e.id break end end
        local f = S.NewFilter(); f.sort = "level"
        local byLevel = S.Filter(shelf, f, ctx)
        okLevel, seenNil = true, false
        for i = 2, #byLevel do
          local a, b = byLevel[i - 1].levelMin, byLevel[i].levelMin
          if a and b and a > b then okLevel = false end
          if not a then seenNil = true elseif seenNil then okLevel = false end
        end
        f.sort = "az"
        local az = S.Filter(shelf, f, ctx)
        okAz = string.lower(az[1].title) <= string.lower(az[2].title)
        """
    )
    assert wow.eval("okNewest") and wow.eval("okLevel") and wow.eval("okAz")
    today = wow.eval("firstUndated")
    wow.execute('ctx.today = "2026-11-17"; for _, e in ipairs(shelf) do e.dayKey = nil end')
    tomorrow = ids(wow, f"{SHELF}.NewFilter()")
    wow.execute('ctx.today = "2026-11-16"')
    again = ids(wow, f"{SHELF}.NewFilter()")
    first_undated_today = next(
        i
        for i in again
        if wow.eval(
            f'(function() for _, e in ipairs(shelf) do if e.id == "{i}" then return e.added == nil end end end)()'
        )
    )
    assert first_undated_today == today  # the same all day
    assert tomorrow != again  # and another the next


def test_nearest_puts_your_zone_first(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"""
        ctx.here = {{ map = 1437, continent = 0 }}
        local f = {SHELF}.NewFilter(); f.sort = "nearest"
        local out = {SHELF}.Filter(shelf, f, ctx)
        firstZones = out[1].zones
        rank = {{}}
        for i, e in ipairs(out) do
          local r = 3
          for _, z in ipairs(e.zones or {{}}) do
            if z == 1437 then r = 0 elseif {SHELF}.SimZone(z).continent == 0 and r > 2 then r = 2 end
          end
          rank[i] = r
        end
        """
    )
    ranks = list(wow.eval("rank").values())
    assert ranks == sorted(ranks) and ranks[0] == 0


def test_done_leaves_the_shelf_and_is_counted(wow: WowRuntime):
    boot(wow)
    before = ids(wow, f'{SHELF}.NewFilter("rares")')
    wow.execute(f'done["{before[0]}"] = true; done["{before[1]}"] = true')
    wow.execute(f'out, hidden = {SHELF}.Filter(shelf, {SHELF}.NewFilter("rares"), ctx)')
    assert wow.eval("#out") == len(before) - 2 and wow.eval("hidden") == 2
    wow.execute(f'F = {SHELF}.NewFilter("rares"); F.showDone = true')
    assert count(wow, "F") == len(before)


def test_the_front_table(wow: WowRuntime):
    """The newest gold story and six more (W6; the chooser for ten characters is held in
    test_cabinet.py). ~~A hero, eight new ones and a strip of four per chapter~~."""
    boot(wow)
    wow.execute(
        f"""
        front = {SHELF}.Front(shelf, ctx)
        newest = nil
        for _, e in ipairs(shelf) do
          if e.chapter == "gold" and e.added and (not newest or e.added > newest) then
            newest = e.added
          end
        end
        """
    )
    assert wow.eval("front.main.added") == wow.eval("newest")
    assert wow.eval("#front.six") == 6
    # every wonder but the ones nobody reported yet (E2) counts for its chapter's entrance
    chapters = wow.eval("front.chapters")
    names = ["gold", "secrets", "collections", "camp", "rares"]
    assert sum(chapters[c].open for c in names) == count(wow, f"{SHELF}.NewFilter()") < N
    first = wow.eval("front.six[1].id")
    wow.execute(f'done["{first}"] = true; front = {SHELF}.Front(shelf, ctx)')
    assert wow.eval("front.six[1].id") != first  # done is not on the table
    assert wow.eval(f"{SHELF}.Surprise(shelf, ctx, 3).id") == wow.eval(
        f"{SHELF}.Surprise(shelf, ctx, 3).id"
    )


def test_new_is_seven_days(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f'{SHELF}.IsNew({{ added = "2026-11-10" }}, "2026-11-16")') is True
    assert wow.eval(f'{SHELF}.IsNew({{ added = "2026-11-09" }}, "2026-11-16")') is False
    assert wow.eval(f'{SHELF}.IsNew({{}}, "2026-11-16")') is False
    assert wow.eval(f'{SHELF}.DayNumber("2026-03-01") - {SHELF}.DayNumber("2026-02-28")') == 1
