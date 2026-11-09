"""The sheet as data (ADR 0054, AT1.1): an entity type declares its reading order as chapters, a
detail section names the chapter it sits in, an action the types it is a main button for. The
dossier's data then answers the chapters, the facts, the lead and the buttons. All pure."""

from harness import WowRuntime

# an item type with four chapters; six sections, one of them for two types with two chapters, one
# without a chapter, one with a chapter the type does not know, one in the reserved "facts"
WORLD = """
local m = Bastians:GetModule("TestApp")
Bastians:RegisterEntityType(m, { type = "item", priority = 100,
  name = function(id) return id == 2589 and "Linen Cloth" or nil end,
  summary = function() return "Trade good" end,
  chapters = {
    { id = "get", title = "Where to get it" }, { id = "use", title = "What it is for" },
    { id = "worth", title = "Worth" }, { id = "yours" } } })
Bastians:RegisterEntityType(m, { type = "npc", priority = 100,
  name = function(id) return "Npc " .. id end,
  lead = function(id) return id == 1 and "Sells weapons in the Trade District" or nil end,
  chapters = function(id)
    return id == 1 and { { id = "sells", title = "Sells" }, { id = "quests", title = "Quests" } }
      or { { id = "quests", title = "Wanted by quests" } }
  end })
local function rows(n)
  return function()
    local out = {}
    for i = 1, n do out[i] = { text = "Row " .. i } end
    return out
  end
end
local function section(id, title, order, chapter, n, types)
  Bastians:RegisterDetailSection(m, { id = id, title = title, types = types or { "item" }, order = order,
    chapter = chapter, build = rows(n) })
end
section("t.stats", "Stats", 12, "facts", 3)
section("t.sources", "Sources", 20, "get", 4)
section("t.where", "Where to get it", 21, "get", 2)
section("t.price", "Price", 25, "worth", 1)
section("t.owned", "Owned", 17, "yours", 2)
section("t.starts", "Starts quests", 22, { item = "use", npc = "quests" }, 1, { "item", "npc" })
section("t.keepsake", "Keepsake", 90, nil, 1)
section("t.odd", "Odd", 30, "nowhere", 1)
Bastians:RegisterDetailSection(m, { id = "t.status", title = "Status", types = { "item" }, order = 1,
  card = true, build = function() return { { text = "You carry 23" } } end })
local function action(id, order, main)
  Bastians:RegisterAction(m, { id = id, label = id, types = { "item", "npc" }, order = order, main = main,
    run = function() end })
end
action("a.map", 10) action("a.route", 15) action("a.farm", 51, { "item" }) action("a.prices", 50, { "item" })
action("a.ask", 45, true) action("a.note", 60, { "item" }) action("a.npc", 70, { "npc" })
"""


def ids(table) -> list[str]:
    return [x.id for x in table.values()]


def test_the_chapters_follow_the_types_reading_order(app: WowRuntime):
    app.execute(WORLD)
    data = app.eval("Bastians.UI.DossierData('item:2589', nil, { source = 'test' })")
    # the catalogue's order, not the sections'; "use" comes before "worth"; a chapter without a
    # block does not show; then the section without a chapter and the one with an unknown chapter
    assert [(c.id, c.title, c.count) for c in data.chapters.values()] == [
        ("get", "Where to get it", 6),
        ("use", "What it is for", 1),
        ("worth", "Worth", 1),
        ("yours", "Owned", 2),  # a chapter without a title takes its first section's
        ("t.odd", "Odd", 1),
        ("t.keepsake", "Keepsake", 1),
    ]
    assert ids(data.chapters[1].blocks) == ["t.sources", "t.where"]  # the sections' order inside
    assert [c.own for c in data.chapters.values()] == [None, None, None, None, True, True]
    assert ids(data.facts) == ["t.stats"]  # under the figure, in no chapter
    assert len(data.blocks) == 8  # the blocks themselves are all still there


def test_a_type_without_chapters_gives_every_section_its_own(app: WowRuntime):
    app.execute(WORLD)
    app.execute(
        """
        local m = Bastians:GetModule("TestApp")
        Bastians:RegisterEntityType(m, { type = "zone", name = function() return "Elwynn" end })
        Bastians:RegisterDetailSection(m, { id = "z.b", title = "B", types = { "zone" }, order = 20,
          chapter = "x", build = function() return { { text = "b" } } end })
        Bastians:RegisterDetailSection(m, { id = "z.a", title = "A", types = { "zone" }, order = 10,
          build = function() return { { text = "a" } } end })
        """
    )
    data = app.eval("Bastians.UI.DossierData('zone:1429', nil, { source = 'test' })")
    assert [(c.id, c.own) for c in data.chapters.values()] == [("z.a", True), ("z.b", True)]
    assert app.eval("Bastians:GetChapters('zone', 1429)") is None


def test_tail_chapters_come_after_the_sections_without_a_chapter(app: WowRuntime):
    """The book and the notes end a sheet: a catalogue's `tail` chapters stand after a section
    that names no chapter, and a type without a reading order still ends on them."""
    app.execute(
        """
        local blocks = {
          { id = "notes.mine", title = "My notes", chapter = "notes", count = 1 },
          { id = "x.own", title = "Own", count = 1 },
          { id = "x.drops", title = "Drops", chapter = "drops", count = 2 },
          { id = "x.book", title = "In the book", chapter = "book", count = 1 },
        }
        listed = Bastians.UI.DossierUtil.chapters(blocks,
          { { id = "drops" }, { id = "book", tail = true }, { id = "notes", tail = true } })
        plain = Bastians.UI.DossierUtil.chapters(blocks)
        """
    )
    assert ids(app.eval("listed")) == ["drops", "x.own", "book", "notes"]
    assert ids(app.eval("plain")) == ["x.own", "x.drops", "book", "notes"]


def test_a_section_for_two_types_sits_in_a_chapter_of_each(app: WowRuntime):
    """`chapter` as a table by type; a type's chapters as a function of the id."""
    app.execute(WORLD)
    vendor = app.eval("Bastians.UI.DossierData('npc:1', nil, { source = 'test' })")
    assert [(c.id, c.title) for c in vendor.chapters.values()] == [("quests", "Quests")]
    monster = app.eval("Bastians.UI.DossierData('npc:2', nil, { source = 'test' })")
    assert [(c.id, c.title) for c in monster.chapters.values()] == [("quests", "Wanted by quests")]
    assert ids(monster.chapters[1].blocks) == ["t.starts"]
    util = "Bastians.UI.DossierUtil.chapterOf(%s, 'npc')"
    assert app.eval(util % "{ chapter = 'drops' }") == "drops"
    assert app.eval(util % "{ chapter = { item = 'use' } }") is None
    assert app.eval(util % "{}") is None


def test_the_lead_is_the_types_sentence_or_the_summary_then_the_status(app: WowRuntime):
    app.execute(WORLD)
    data = app.eval("Bastians.UI.DossierData('item:2589', nil, { source = 'test' })")
    assert data.lead == "Trade good. You carry 23."
    assert app.eval("Bastians.UI.DossierData('npc:1', nil, {}).lead") == (
        "Sells weapons in the Trade District."
    )
    assert app.eval("Bastians:Entity('npc:2'):Lead()") is None
    lead = "Bastians.UI.DossierUtil.lead(%s)"
    assert app.eval(lead % "{ summary = 'Level 11, Elwynn Forest', status = 'Done!' }") == (
        "Level 11, Elwynn Forest. Done!"
    )
    assert app.eval(lead % "{ status = '|cff00ff00Complete|r' }") == "|cff00ff00Complete|r."
    assert app.eval(lead % "{ summary = '  ' }") is None
    assert app.eval(lead % "{}") is None


def test_the_main_buttons_and_the_rest_in_more(app: WowRuntime):
    app.execute(WORLD)
    data = app.eval("Bastians.UI.DossierData('item:2589', nil, { source = 'test' })")
    # the marked ones in their order; every other action is in More
    assert ids(data.main) == ["a.ask", "a.prices", "a.farm", "a.note"]
    assert ids(data.more) == ["a.map", "a.route", "a.npc"]
    app.execute(
        "main, more = Bastians.UI.DossierUtil.mainActions(Bastians.UI.DossierData('item:2589').card.actions, 3)"
    )
    assert ids(app.eval("main")) == ["a.ask", "a.prices", "a.farm"]  # no more than the host asks
    assert ids(app.eval("more")) == ["a.map", "a.route", "a.note", "a.npc"]
    flags = [a.main for a in data.card.actions.values()]
    assert flags == [False, False, True, True, True, True, False]
    npc = app.eval("Bastians.UI.DossierData('npc:2', nil, { source = 'test' })")
    assert ids(npc.main) == ["a.ask", "a.npc"]  # `main = true` counts for every type
    # nothing marked: the first three stand in, as the band's order was
    app.execute(
        """
        main, more = Bastians.UI.DossierUtil.mainActions({
          { id = "a" }, { id = "b" }, { id = "c" }, { id = "d" } })
        """
    )
    assert ids(app.eval("main")) == ["a", "b", "c"] and ids(app.eval("more")) == ["d"]
