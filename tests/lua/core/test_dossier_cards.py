"""A sheet as cards (ADR 0056, PA3.1; the Dossier's `cards` option): every chapter a card, its
things as tiles that say the thing's own name and line. A card with six things or fewer shows
them all, a larger one the first four and "All N"; nothing folds; a card with running text, a
small table or pictures takes the page's width, the others stand two side by side where they fit."""

import re

from harness import WowRuntime

WORLD = """
local m = Bastians:GetModule("TestApp")
Bastians:RegisterEntityType(m, { type = "npc", priority = 100,
  name = function(id) return id == 448 and "Hogger" or ("Gnoll " .. id) end,
  summary = function(id) return "Level 11, Elwynn Forest" end })
Bastians:RegisterEntityType(m, { type = "quest", name = function(id) return "Quest " .. id end,
  summary = function(id) return "Level " .. id end })
Bastians:RegisterEntityType(m, { type = "item", name = function(id) return "Item " .. id end })
local function hogger(rows)
  return function(ref) return ref == "npc:448" and rows() or nil end
end
local function quests(from, to)
  local rows = {}
  for i = from, to do
    -- the row's own words: a level in brackets, a colour, a line of its own
    rows[#rows + 1] = { text = "|cffff0000[" .. i .. "] Quest " .. i .. "|r", ref = "quest:" .. i,
      meta = "the row's own second line" }
  end
  return rows
end
-- three things, in two groups: nothing folds, the groups give their rows
Bastians:RegisterDetailSection(m, { id = "t.few", title = "Starts", types = { "npc" }, order = 10,
  build = hogger(function()
    return { { text = "Here", children = quests(1, 2) }, { text = "Elsewhere", collapsed = true, children = quests(3, 3) } }
  end) })
-- nine things in a chapter of two sections
Bastians:RegisterDetailSection(m, { id = "t.todo", title = "To do", types = { "npc" }, order = 20, chapter = "wanted",
  build = hogger(function() return quests(11, 13) end) })
Bastians:RegisterDetailSection(m, { id = "t.later", title = "Later", types = { "npc" }, order = 21, chapter = "wanted",
  build = hogger(function() return quests(21, 26) end) })
Bastians:RegisterDetailSection(m, { id = "t.text", title = "Lore", types = { "npc" }, order = 30,
  build = hogger(function() return { { kind = "para", text = string.rep("Hogger is a gnoll. ", 20) } } end) })
Bastians:RegisterDetailSection(m, { id = "t.loot", title = "Drops", types = { "npc" }, order = 40,
  block = { table = true },
  build = hogger(function() return { { text = "Item 1", ref = "item:1", note = "12 %", value = 5, valueKind = "money" } } end) })
"""

HOST = """
host = CreateFrame("Frame", nil, UIParent)
host:SetSize(%d, 500)
stepped = {}
dossier = Bastians.UI.Dossier(host, { cards = true, ctx = { source = "test" }%s })
dossier.scroll:SetSize(%d, 500)
dossier:SetSubject("npc:448")
"""
INSIDE = ", onChapter = function(chapter) stepped[#stepped + 1] = chapter.id end"


def strip(text):
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    return re.sub(r"\|c[0-9a-fA-F]{8}", "", text).replace("|r", "")


def boot(app: WowRuntime, width: int, inside: bool = False) -> None:
    app.execute(
        "Bastians:RegisterEntityType(Bastians:GetModule('TestApp'), { type = 'npc', priority = 5, "
        "chapters = { { id = 'wanted', title = 'Wanted by quests' } } })"
    )
    app.execute(WORLD)
    app.execute(HOST % (width + 14, INSIDE if inside else "", width))


def cards(app: WowRuntime) -> list[dict]:
    """The shown cards: title, count, the words of "All N", place and width."""
    out = []
    for card in app.eval("dossier.cardPool").values():
        if card.IsShown(card):
            _, _, _, x, y = card.GetPoint(card, 1)
            out.append(
                {
                    "title": card.title.GetText(card.title),
                    "count": card.count.IsShown(card.count) and card.count.GetText(card.count),
                    "all": card.all.IsShown(card.all)
                    and strip(card.all.label.GetText(card.all.label)),
                    "x": x,
                    "y": -y,
                    "w": card.GetWidth(card),
                    "h": card.GetHeight(card),
                }
            )
    return out


def tiles(app: WowRuntime) -> list[tuple]:
    """Every tile drawn on the sheet: (name, line), in block order."""
    out = []
    for bf in app.eval("dossier.blockPool").values():
        if bf.IsShown(bf) and bf.mode == "tiles":
            for f in bf.tree.pool.values():
                if f.IsShown(f) and f.tile:
                    out.append((f.text.GetText(f.text), f.meta.GetText(f.meta)))
    return out


def size_tiles(app: WowRuntime) -> None:
    app.execute(
        "for _, bf in ipairs(dossier.blockPool) do if bf:IsShown() and bf.mode == 'tiles' then "
        "bf.tree:Refresh() end end"
    )


def test_a_card_model_caps_at_four_of_more_than_six(core: WowRuntime):
    util = "Bastians.UI.DossierUtil"
    core.execute(
        f"""
        local function rows(n)
          local out = {{}}
          for i = 1, n do out[i] = {{ text = "q" .. i, ref = "quest:" .. i }} end
          return out
        end
        local grouped = {{ {{ text = "group", children = rows(2) }}, {{ text = "a line" }} }}
        leaves = {util}.leaves(grouped)
        six = {util}.card({{ id = "c", blocks = {{ {{ id = "a", title = "A", rows = rows(6), limit = 5 }} }} }})
        nine = {{ id = "c", blocks = {{ {{ id = "a", title = "A", rows = rows(3), limit = 5 }},
          {{ id = "b", title = "B", rows = rows(6), limit = 5 }} }} }}
        capped = {util}.card(nine)
        open = {util}.card(nine, nil, true)
        found = {util}.card(nine, nil, false, "q3")
        special = {util}.card(nine, function(block) return block.id == "b" end)
        text = {util}.card({{ id = "t", blocks = {{ {{ id = "p", title = "P", limit = 5,
          rows = {{ {{ kind = "para", text = "words" }} }} }} }} }})
        """
    )
    assert [r.text for r in core.eval("leaves").values()] == ["q1", "q2", "a line"]
    six = core.eval("six")
    assert (six.things, six.capped, len(six.parts), six.wide) == (6, False, 1, False)
    assert six.parts[1].label is False and len(six.parts[1].rows) == 6
    capped = core.eval("capped")
    assert (capped.things, capped.capped) == (9, True)
    # the first four, in reading order: the first part whole, one of the second; parts are labelled
    assert [len(p.rows) for p in capped.parts.values()] == [3, 1]
    assert capped.parts[1].label is True
    assert [len(p.rows) for p in core.eval("open").parts.values()] == [3, 6]
    found = core.eval("found")  # a query: what matches, uncapped
    assert (found.things, found.capped) == (2, False)  # q3 of each part
    special = core.eval("special")  # a block with its own drawing is no tiles and never capped
    assert (special.things, special.capped, special.wide) == (3, False, True)
    assert special.parts[2].special is True and special.parts[2].rows is None
    assert core.eval("text").wide is True  # running text reads at the page's width
    assert core.errors == []


def test_chapters_are_cards_with_tiles(app: WowRuntime):
    boot(app, 900)
    size_tiles(app)
    shown = cards(app)
    assert [c["title"] for c in shown] == ["Wanted by quests", "Starts", "Lore", "Drops"]
    wanted, starts, lore, drops = shown
    # nine things: the first four and "All 9"; three things: all of them, no count of one
    assert (wanted["count"], wanted["all"]) == ("9", "All 9")
    assert (starts["count"], starts["all"]) == ("3", False)
    assert lore["all"] is False and drops["all"] is False
    # two cards side by side where they fit; text and a table take the page's width
    assert wanted["x"] != starts["x"] and wanted["y"] == starts["y"]
    assert wanted["w"] == starts["w"] and wanted["w"] >= 280
    assert lore["x"] == wanted["x"] and lore["w"] > 2 * wanted["w"]
    assert lore["y"] >= max(wanted["y"] + wanted["h"], starts["y"] + starts["h"])
    assert drops["w"] == lore["w"] and drops["y"] > lore["y"]
    # a tile says the thing's own name and line, never the row's coloured words
    drawn = tiles(app)
    assert ("Quest 11", "Level 11") in drawn and ("Quest 3", "Level 3") in drawn  # folded: shown
    assert len(drawn) == 4 + 3
    assert not any("|c" in name or "[" in name for name, _ in drawn)
    assert not any(line == "the row's own second line" for _, line in drawn)
    # nothing folds, no contents line, no chapter headings of the reading column
    assert not any(
        bf.IsShown(bf) and bf.fold.IsShown(bf.fold) for bf in app.eval("dossier.blockPool").values()
    )
    assert not any(b.IsShown(b) for b in app.eval("dossier.contentsPool").values())
    assert not any(h.IsShown(h) for h in app.eval("dossier.chapterPool").values())
    # the table keeps its own drawing
    table = [
        bf
        for bf in app.eval("dossier.blockPool").values()
        if bf.IsShown(bf) and bf.block.id == "t.loot"
    ]
    assert table and table[0].mode != "tiles" and table[0].tree.opts.table is True
    assert app.errors == []


def test_all_opens_the_rest_in_place_or_asks_the_host(app: WowRuntime):
    boot(app, 900)
    app.execute("dossier.cardPool[1].all:Click()")
    size_tiles(app)
    assert cards(app)[0]["all"] is False and len(tiles(app)) == 9 + 3
    # a host that steps inside gets the chapter instead (ADR 0056: the list tile takes it)
    app.execute("dossier:Hide()")
    boot2 = HOST % (914, INSIDE, 900)
    app.execute(boot2)
    app.execute("dossier.cardPool[1].all:Click()")
    assert list(app.eval("stepped").values()) == ["wanted"]
    assert cards(app)[0]["all"] == "All 9"  # the card stays as it was
    assert app.errors == []


def test_a_narrow_page_stacks_the_cards_and_a_query_shows_what_matches(app: WowRuntime):
    boot(app, 420)
    shown = cards(app)
    assert len({c["x"] for c in shown}) == 1  # one column
    assert [c["y"] for c in shown] == sorted(c["y"] for c in shown)
    app.execute("dossier:SetQuery('Quest 2')")
    size_tiles(app)
    shown = cards(app)
    assert [c["title"] for c in shown] == ["Wanted by quests", "Starts"]
    assert shown[0]["all"] is False  # a query is never capped
    # the query's words are lit in the names; both words must be there
    assert sorted(strip(name) for name, _ in tiles(app)) == [
        "Quest 12",
        "Quest 2",
        "Quest 21",
        "Quest 22",
        "Quest 23",
        "Quest 24",
        "Quest 25",
        "Quest 26",
    ]
    assert app.errors == []


SHEET = """
local m = Bastians:GetModule("TestApp")
drawn, hidden = {}, 0
Bastians:RegisterSheet(m, { types = { "npc" }, covers = { "t.text" },
  draw = function(ref, host)
    drawn[#drawn + 1] = { ref = ref, width = host.width, frame = host.frame, source = host.ctx.source,
      buttons = host.buttons, refresh = host.refresh }
    return 120
  end,
  hide = function(host) hidden = hidden + 1 end })
"""


def test_a_registered_sheet_draws_the_page_of_its_type(app: WowRuntime):
    """ADR 0056, one quest sheet: an app registers the drawing of a type's page
    (Bastians:RegisterSheet); a sheet of cards hosts it in place of its head, hands it its frame,
    width, context and the host's buttons, leaves out the sections it says itself and draws the
    rest as cards under it."""
    boot(app, 900)
    assert app.eval("Bastians:GetSheet('npc')") is None
    app.execute("watch = {}")
    app.execute(
        "Bastians:GetModule('TestApp'):On('BASTIANS_REGISTRY_CHANGED', function(_, _, kind, id, on) "
        "if kind == 'sheet' then watch[#watch + 1] = id .. ':' .. tostring(on) end end)"
    )
    app.execute(SHEET)
    assert list(app.eval("watch").values()) == ["npc:true"]
    assert app.eval("Bastians:GetSheet('npc').covers[1]") == "t.text"
    assert app.eval("Bastians:GetSheet('quest')") is None
    app.execute("dossier:Refresh()")
    call = app.eval("drawn[#drawn]")
    assert (call.ref, call.width, call.source) == ("npc:448", 900, "test")
    assert app.eval("drawn[#drawn].frame == dossier.content") is True
    assert [b.label for b in call.buttons.values()] == ["More"]  # the host's own, then More
    assert app.eval("dossier.band:IsShown()") is False  # the app's drawing is the head
    shown = cards(app)
    assert [c["title"] for c in shown] == ["Wanted by quests", "Starts", "Drops"]  # no Lore
    assert min(c["y"] for c in shown) >= 120  # under what the sheet drew
    assert shown[0]["x"] == 0  # at the page's width: no figure column
    # the host draws again when the sheet's app asks
    before = app.eval("#drawn")
    app.execute("drawn[#drawn].refresh()")
    assert app.eval("#drawn") == before + 1
    # another type's page: the kit's own head again, and the sheet is told to go
    app.execute("dossier:SetSubject('quest:1')")
    assert app.eval("hidden") == 1 and app.eval("dossier.sheet") is None
    assert app.eval("dossier.band:IsShown()") is True
    # a sheet that fails draws nothing and breaks no page
    app.execute(
        "Bastians:RegisterSheet(Bastians:GetModule('TestApp'), { types = { 'npc' }, "
        "draw = function() error('boom') end })"
    )
    app.execute("dossier:SetSubject('npc:448')")
    assert cards(app)[0]["title"] == "Wanted by quests"
    # the owner goes: so does its sheet
    app.execute("Bastians:GetModule('TestApp'):Disable()")
    assert app.eval("Bastians:GetSheet('npc')") is None


TABBED = """
Bastians:RegisterEntityType(Bastians:GetModule('TestApp'), { type = 'npc', priority = 5,
  chapters = { { id = 'wanted', title = 'Wanted by quests', tab = true },
    { id = 'attune', title = 'Attunement', tab = true, always = true, empty = 'No attunement needed.' } } })
local m = Bastians:GetModule("TestApp")
Bastians:RegisterDetailSection(m, { id = "t.facts", title = "Facts", types = { "npc" }, order = 5,
  block = { stats = true },
  build = function(ref) return ref == "npc:448" and {
    { text = "Level", value = 11, valueKind = "number" },
    { text = "Worth", value = 1234, valueKind = "money", note = "at the median" },
    { text = "Runs", stat = true },
    { text = "Last in: Elwynn Forest", ref = "zone:1429" },
  } or nil end })
"""


def test_a_tabbed_sheet_reads_one_chapter_at_a_time_and_facts_as_tiles(app: WowRuntime):
    """ADR 0058, PH5: a type whose reading order marks chapters `tab` reads in tabs: Overview
    first (the other chapters and the facts), then one tab per marked chapter; an `always`
    chapter is there with nothing to show and says so; a block of facts draws its rows with a
    value as stat tiles, the rest as rows."""
    app.execute(WORLD)
    app.execute(TABBED)
    app.execute(HOST % (700 + 14, "", 700))
    app.run_frames(2)
    tabs = app.eval("dossier:Tabs()")
    assert [(t.id, strip(t.title)) for t in tabs.values()] == [
        ("overview", "Overview"),
        ("wanted", "Wanted by quests"),
        ("attune", "Attunement"),
    ]
    assert app.eval("dossier.tabId") == "overview" and app.eval("dossier.tabCount") == 3
    labels = [strip(b.spec.label) for b in app.eval("dossier.tabPool").values() if b.IsShown(b)]
    assert labels == ["Overview", "Wanted by quests  9", "Attunement"]
    assert app.eval("dossier.tabPool[1].spec.primary") is True
    # the overview: the chapters without the mark (Starts, Lore, Drops) and the facts
    cards = [c.chapter.id for c in app.eval("dossier.cards").values()]
    assert cards == ["t.facts", "t.few", "t.text", "t.loot"]  # the facts block is a card of its own
    tiles = [
        (
            strip(t.label.GetText(t.label)),
            strip(t.value.GetText(t.value)),
            strip(t.note.GetText(t.note) or ""),
        )
        for t in app.eval("dossier.blockPool[1].statPool").values()
        if t.IsShown(t)
    ]
    assert (
        tiles[0] == ("Level", "11", "")
        and tiles[1][0] == "Worth"
        and tiles[1][2] == "at the median"
    )
    assert tiles[2] == ("Runs", "unknown", "")  # a value nobody knows, never 0
    assert len(tiles) == 3  # the row without a value stays a row under the tiles
    rows = [strip(r.text) for r in app.eval("dossier.blockPool[1].tree.flat").values()]
    assert rows == ["Last in: Elwynn Forest"]
    # the wanted tab: its chapter alone, as a card
    app.execute("dossier.tabPool[2]:Click()")
    app.run_frames(2)
    assert app.eval("dossier.tabId") == "wanted"
    assert [c.chapter.id for c in app.eval("dossier.cards").values()] == ["wanted"]
    assert (
        app.eval("dossier.tabPool[2].spec.primary") is True
        and app.eval("dossier.tabPool[1].spec.primary") is None
    )
    # the attunement tab: nothing to show, so it says so
    app.execute("dossier:SetTab('attune')")
    app.run_frames(2)
    cards = list(app.eval("dossier.cards").values())
    assert len(cards) == 1 and cards[0].chapter.id == "attune"
    texts = [strip(r.text) for r in app.eval("dossier.blockPool[1].tree.flat").values()]
    assert texts == ["No attunement needed."]
    # another subject opens on its overview again
    app.execute("dossier:SetSubject('npc:449')")
    app.run_frames(2)
    assert app.eval("dossier.tabId") == "overview"
    assert app.errors == []
