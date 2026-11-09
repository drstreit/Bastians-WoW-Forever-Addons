"""The dossier renderer (C1, ADR 0014; a sheet since ADR 0054): Bastians.UI.Dossier draws one entity
as a head, the registered sections as chapters in one reading column (beside the figure when the
host is wide), and the sections marked `link` as relation rows with chips. Pooled frames, nothing
built while hidden."""

import re

from harness import WowRuntime

CORE, DATA, QUESTS, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Browser",
)

# a world of one NPC with places, actions (one of them listed but disabled) and five sections:
# the status (card), a one-row overview, seven quests (capped at five), a wide text, a link
WORLD = """
local m = Bastians:GetModule("TestApp")
Bastians:RegisterEntityType(m, { type = "npc", priority = 100,
  name = function(id) return id == 448 and "Hogger" or nil end,
  summary = function(id) return "Level 11, Elwynn Forest" end,
  locations = function(id)
    return { { map = 1429, x = 0.27, y = 0.86 }, { map = 1429, x = 0.5, y = 0.5 }, { map = 999, x = 0.1, y = 0.1 } }
  end })
Bastians:RegisterEntityType(m, { type = "quest", name = function(id) return "Quest " .. id end })
Bastians:RegisterEntityType(m, { type = "item", name = function(id) return "Item " .. id end })
ran = {}
Bastians:RegisterAction(m, { id = "map.show", label = "Show on map", short = "Map", types = { "npc" }, order = 10,
  run = function(ref, ctx) ran[#ran + 1] = "map " .. ref .. "@" .. ctx.source end })
Bastians:RegisterAction(m, { id = "route.to", label = "Route", types = { "npc" }, order = 20,
  enabled = function() return false end, run = function() ran[#ran + 1] = "route" end })
local function hogger(rows) -- the sections exist for Hogger only
  return function(ref) return ref == "npc:448" and rows() or nil end
end
Bastians:RegisterDetailSection(m, { id = "t.status", title = "Status", types = { "npc" }, order = 1, card = true,
  build = hogger(function() return { { text = "Alive and angry" } } end) })
Bastians:RegisterDetailSection(m, { id = "t.overview", title = "Overview", types = { "npc" }, order = 10,
  build = hogger(function() return { { text = "Level 11", value = 1100, valueKind = "money" } } end) })
Bastians:RegisterDetailSection(m, { id = "t.quests", title = "Wanted by", types = { "npc" }, order = 20,
  block = { columns = 1 },
  build = hogger(function()
    local rows = {}
    for i = 1, 7 do rows[i] = { text = "Quest " .. i, ref = "quest:" .. i } end
    return rows
  end) })
Bastians:RegisterDetailSection(m, { id = "t.text", title = "Lore", types = { "npc" }, order = 30,
  block = { wide = true },
  build = hogger(function() return { { kind = "para", text = string.rep("Hogger is a gnoll. ", 20) } } end) })
Bastians:RegisterDetailSection(m, { id = "t.needs", title = "Needs", types = { "npc" }, order = 40,
  link = "drops",
  build = hogger(function() return { { text = "Huge Gnoll Claw", ref = "item:1931", value = 12345, valueKind = "money" },
    { text = "Linen Cloth", ref = "item:2589" } } end) })
"""

HOST = """
host = CreateFrame("Frame", nil, UIParent)
host:SetSize(%d, 500)
clicked = {}
dossier = Bastians.UI.Dossier(host, { ctx = { source = "test" },
  onClick = function(row, button) clicked[#clicked + 1] = (row.ref or row.text) .. "/" .. button end,
  buttons = function(ref) return { { label = "Bookmark", onClick = function() clicked[#clicked + 1] = "bookmark" end } } end })
dossier.scroll:SetSize(%d, 500)
"""


def strip(text):
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def host(wow: WowRuntime, width: int) -> None:
    wow.execute(HOST % (width + 14, width))


def blocks(wow: WowRuntime) -> list[dict]:
    out = []
    for bf in wow.eval("dossier.blockPool").values():
        if bf.IsShown(bf):
            _, _, _, x, y = bf.GetPoint(bf, 1)
            out.append(
                {
                    "title": bf.title.GetText(bf.title),
                    "bare": not bf.title.IsShown(bf.title),
                    "count": bf.count.GetText(bf.count) if bf.count.IsShown(bf.count) else None,
                    "x": x,
                    "y": -y,
                    "w": bf.GetWidth(bf),
                    "h": bf.GetHeight(bf),
                    "rows": [strip(r.text) for r in bf.tree.flat.values()],
                }
            )
    return out


def heads(wow: WowRuntime) -> list[dict]:
    out = []
    for head in wow.eval("dossier.chapterPool").values():
        if head.IsShown(head):
            _, _, _, x, y = head.GetPoint(head, 1)
            out.append(
                {
                    "title": head.title.GetText(head.title),
                    "count": head.count.GetText(head.count)
                    if head.count.IsShown(head.count)
                    else None,
                    "x": x,
                    "y": -y,
                    "w": head.GetWidth(head),
                }
            )
    return out


def contents(wow: WowRuntime) -> list[str]:
    return [
        strip(b.label.GetText(b.label))
        for b in wow.eval("dossier.contentsPool").values()
        if b.IsShown(b)
    ]


def band(wow: WowRuntime) -> dict:
    b = wow.eval("dossier.band")
    return {
        "shown": b.IsShown(b),
        "name": b.name.GetText(b.name),
        "badge": b.badge.label.GetText(b.badge.label),
        "meta": b.meta.GetText(b.meta) if b.meta.IsShown(b.meta) else None,
        "status": strip(b.status.GetText(b.status)) if b.status.IsShown(b.status) else None,
        "worth": b.worth.GetText(b.worth) if b.worth.IsShown(b.worth) else None,
        "buttons": [
            (strip(x.label.GetText(x.label)), x.GetAlpha(x))
            for x in wow.eval("dossier.buttons").values()
            if x.IsShown(x)
        ],
        "height": b.GetHeight(b),
    }


def chips(wow: WowRuntime) -> list[str]:
    return [
        strip(c.label.GetText(c.label))
        for c in wow.eval("dossier.chipPool").values()
        if c.IsShown(c)
    ]


def test_distance_to_the_nearest_place_on_the_players_continent(app: WowRuntime):
    """Coords.DistanceTo: the nearest of the entity's places through the transforms; a place on a
    map without a transform is skipped; nil without a player position or places."""
    app.execute(WORLD)
    yards, point = app.eval("Bastians.Coords.DistanceTo('npc:448')")
    # elwynn mock: wx = 200 - 400*y, wy = 200 - 400*x; player (0.42, 0.65) -> (-60, 32)
    assert yards == 68 and (point.x, point.y) == (0.5, 0.5)  # the map centre is nearest
    assert app.eval("Bastians.Coords.DistanceTo('quest:1')") is None  # no places
    app.execute("Mock.playerMap = nil")
    assert app.eval("Bastians.Coords.DistanceTo('npc:448')") is None
    assert app.eval("Bastians.UI.Distance(103.2)") == "103 yd"
    assert app.eval("Bastians.UI.Distance(1234)") == "1.2 k yd"
    assert app.eval("Bastians.UI.Distance(nil)") is None
    assert app.eval("Bastians.UI.Duration(3)") == "< 1 min"
    assert app.eval("Bastians.UI.Duration(42)") == "1 min"
    assert app.eval("Bastians.UI.Duration(150)") == "3 min"
    assert app.eval("Bastians.UI.Duration(3900)") == "1 h 05"
    assert app.eval("Bastians.UI.Duration(nil)") is None


def test_the_data_splits_sections_into_band_blocks_and_links(app: WowRuntime):
    app.execute(WORLD)
    data = app.eval("Bastians.UI.DossierData('npc:448', nil, { source = 'test' })")
    assert data.card.name == "Hogger" and data.card.status == "Alive and angry"
    assert data.card.away == "68 yd"  # no graph network here: the straight line stands in
    assert [b.id for b in data.blocks.values()] == [
        "t.overview",
        "t.quests",
        "t.text",
    ]  # no status block
    quests = data.blocks[2]
    assert (quests.span, quests.wide, quests.limit, quests.count) == (1, False, 5, 7)
    assert data.blocks[3].wide is True
    assert [(k.id, k.relation) for k in data.links.values()] == [("t.needs", "drops")]
    assert app.eval("Bastians.UI.DossierUtil.columns(400)") == 1
    assert app.eval("Bastians.UI.DossierUtil.columns(420)") == 2
    assert app.eval("Bastians.UI.DossierUtil.columns(680)") == 3
    status = "Bastians.UI.DossierUtil.statusLine(%s)"
    assert strip(app.eval(status % "{ status = 'Done', away = '3 min' }")) == "Done  3 min"
    assert app.eval(status % "{ away = '3 min' }") == "3 min"
    assert app.eval(status % "{ status = 'Done' }") == "Done"
    assert app.eval(status % "{}") is None


def test_the_grid_flows_blocks_left_to_right_and_wraps(app: WowRuntime):
    """Pure placement: two columns of 100 px, a wide block takes the row, a block that does not fit
    the rest of a row starts the next, a row is as tall as its tallest block."""
    app.execute(
        """
        placed, total = Bastians.UI.DossierUtil.grid({
          { id = "a", rows = {} }, { id = "b", rows = {}, span = 2 }, { id = "c", rows = {} },
          { id = "d", rows = {} }, { id = "e", rows = {}, wide = true } },
          2, 100, 10, function(block, w) return block.id == "c" and 60 or 30 end)
        """
    )
    placed = [(p.block.id, p.x, p.y, p.w, p.h) for p in app.eval("placed").values()]
    assert placed == [
        ("a", 0, 0, 100, 30),
        ("b", 0, 40, 210, 30),  # a 2-span block does not fit beside "a": next row, full width
        ("c", 0, 80, 100, 60),
        ("d", 110, 80, 100, 30),
        ("e", 0, 150, 210, 30),  # wide: the whole row
    ]
    assert app.eval("total") == 180


def test_the_band_shows_the_card_and_its_buttons(app: WowRuntime):
    app.execute(WORLD)
    host(app, 460)
    app.execute("dossier:SetSubject('npc:448')")
    b = band(app)
    assert b["shown"] and b["name"] == "Hogger" and b["badge"] == "npc"
    assert b["meta"] == "Level 11, Elwynn Forest"
    assert b["status"] == "Alive and angry  68 yd"
    assert b["worth"] is None  # no worth provider yet (C3): the line is absent, never "0"
    assert b["buttons"] == [("Map", 1), ("Route", 0.4), ("Bookmark", 1)]  # Route listed, greyed
    assert b["height"] > 52  # the icon plus padding is the minimum
    app.execute("dossier.buttons[1]:Click()")
    app.execute("dossier.buttons[2]:Click()")  # disabled: nothing runs
    app.execute("dossier.buttons[3]:Click()")
    assert list(app.eval("ran").values()) == ["map npc:448@test"]
    assert list(app.eval("clicked").values()) == ["bookmark"]
    # an entity without data: the ref as the name, the badge, no lines
    app.execute("dossier:SetSubject('npc:7')")
    b = band(app)
    assert b["name"] == "npc:7" and b["badge"] == "npc" and b["status"] == "68 yd"
    assert app.eval("dossier.blockCount") == 0 and app.eval("dossier.links:IsShown()") is False
    assert app.errors == []


def test_chapters_read_in_one_column_under_the_head(app: WowRuntime):
    """A sheet (ADR 0054): every section without a chapter is a chapter of its own, a heading and
    under it its block without a title of its own, one under the other at the column's width."""
    app.execute(WORLD)
    host(app, 460)
    app.execute("dossier:SetSubject('npc:448')")
    assert app.eval("dossier.pages") == 1 and app.eval("dossier.columns") is None
    bl, hd = blocks(app), heads(app)
    assert [h["title"] for h in hd] == ["Overview", "Wanted by", "Lore"]
    assert [h["count"] for h in hd] == [None, "7", None]  # the rows, where there are several
    assert all(b["bare"] for b in bl)  # the heading names the block
    assert [b["x"] for b in bl] == [0, 0, 0] and [b["w"] for b in bl] == [460, 460, 460]
    for h, b in zip(hd, bl, strict=True):
        assert (h["x"], h["w"]) == (0, 460) and b["y"] == h["y"] + 30  # the block under its heading
    assert hd[1]["y"] == bl[0]["y"] + bl[0]["h"] + 6 and hd[2]["y"] == bl[1]["y"] + bl[1]["h"] + 6
    assert bl[2]["h"] > 18 + 6  # the paragraph wraps
    # the contents line stands between the head and the first chapter; a click scrolls there
    assert contents(app) == ["Overview", "Wanted by  7", "Lore"]
    assert hd[0]["y"] == band(app)["height"] + 2 + 22 + 2
    app.execute("dossier.contentsPool[3]:Click('LeftButton')")
    assert app.eval("dossier.scroll:GetVerticalScroll()") > 0
    assert app.eval("dossier.height") > bl[2]["y"] + bl[2]["h"]

    # wide without a figure: still one column, no wider than a line reads well
    app.execute("host:SetSize(900 + 14, 500); dossier.scroll:SetSize(900, 500); dossier:Refresh()")
    assert app.eval("dossier.pages") == 1
    assert [b["w"] for b in blocks(app)] == [680, 680, 680]
    assert app.eval("#dossier.blockPool") == 3  # frames pooled, none created on re-layout
    assert app.eval("#dossier.chapterPool") == 3
    geo = "{ Bastians.UI.DossierUtil.pages(%d) }"
    assert list(app.eval(geo % 699).values()) == [False, 132, 0, 699]
    assert list(app.eval(geo % 700).values()) == [True, 238, 264, 436]
    assert list(app.eval(geo % 1200).values()) == [True, 320, 346, 680]
    assert app.errors == []


def test_two_pages_put_the_figure_left_and_the_reading_right(app: WowRuntime):
    """A wide host with a portrait: the figure a third of the width, the head, the contents and
    the chapters beside it; the facts under the figure."""
    app.execute(WORLD)
    app.execute(
        """
        local m = Bastians:GetModule("TestApp")
        Bastians:RegisterDetailSection(m, { id = "t.facts", title = "Facts", types = { "npc" }, order = 5,
          chapter = "facts", build = function() return { { text = "Elite" } } end })
        host = CreateFrame("Frame", nil, UIParent)
        host:SetSize(914, 500)
        dossier = Bastians.UI.Dossier(host, { ctx = { source = "test" }, portrait = true })
        dossier.scroll:SetSize(900, 500)
        dossier:SetSubject('npc:448')
        """
    )
    assert app.eval("dossier.pages") == 2
    figure = 306  # a third of 900, within its limits
    x = figure + 2 * 6 + 14
    stage = app.eval("dossier.band.stage.frame")
    assert stage.IsShown(stage) and stage.GetHeight(stage) == figure
    b = app.eval("dossier.band")
    assert b.name.GetPoint(b.name, 1)[3] == x and b.badge.GetPoint(b.badge, 1)[3] == x
    bl, hd = blocks(app), heads(app)
    facts = bl[0]
    assert facts["rows"] == ["Elite"] and facts["bare"]
    assert (facts["x"], facts["w"], facts["y"]) == (6, figure, 6 + figure + 14)  # under the figure
    assert [h["title"] for h in hd] == ["Overview", "Wanted by", "Lore"]  # facts are no chapter
    assert all(h["x"] == x and h["w"] == 900 - x for h in hd)
    assert all(blk["x"] == x and blk["w"] == 900 - x for blk in bl[1:])
    assert hd[0]["y"] < 6 + figure  # the reading starts beside the figure, not under it
    assert app.errors == []


def test_a_capped_block_shows_more_and_expands_in_place(app: WowRuntime):
    app.execute(WORLD)
    host(app, 460)
    app.execute("dossier:SetSubject('npc:448')")
    quests = blocks(app)[1]
    assert quests["rows"] == ["Quest 1", "Quest 2", "Quest 3", "Quest 4", "Quest 5", "+2 more"]
    assert heads(app)[1]["count"] == "7"  # the heading says how many there are
    before = quests["h"]
    # the more row: a click expands the block, the chapters below move down, the more row goes
    app.execute("dossier.blockPool[2].tree.pool[6]:Click('LeftButton')")
    quests = blocks(app)[1]
    assert quests["rows"] == [f"Quest {i}" for i in range(1, 8)]
    assert quests["h"] == before + 18
    assert heads(app)[2]["y"] == quests["y"] + quests["h"] + 6  # the next chapter moved down
    assert list(app.eval("clicked").values()) == []  # the more row is not a row click
    # a row click goes to the host
    app.execute("dossier.blockPool[2].tree.pool[3]:Click('LeftButton')")
    assert list(app.eval("clicked").values()) == ["quest:3/LeftButton"]
    # a new subject forgets the expansion
    app.execute("dossier:SetSubject('npc:7'); dossier:SetSubject('npc:448')")
    assert blocks(app)[1]["rows"][-1] == "+2 more"
    assert app.errors == []


def test_a_chapter_groups_its_sections_and_more_holds_the_other_actions(app: WowRuntime):
    """A type with chapters: two sections in one chapter keep their own titles under its heading;
    three main buttons, then More with the entity menu, then the host's button."""
    app.execute(WORLD)
    app.execute(
        """
        local m = Bastians:GetModule("TestApp")
        Bastians:RegisterEntityType(m, { type = "npc", priority = 200,
          lead = function() return "The gnoll of the hill" end,
          chapters = { { id = "quests", title = "Quests" }, { id = "about", title = "About" } } })
        Bastians:RegisterDetailSection(m, { id = "t.quests", title = "Wanted by", types = { "npc" }, order = 20,
          chapter = "quests", build = function() return { { text = "Quest 1" }, { text = "Quest 2" } } end })
        Bastians:RegisterDetailSection(m, { id = "t.starts", title = "Starts", types = { "npc" }, order = 21,
          chapter = "quests", build = function() return { { text = "Quest 9" } } end })
        Bastians:RegisterDetailSection(m, { id = "t.text", title = "Lore", types = { "npc" }, order = 30,
          chapter = "about", build = function() return { { text = "A gnoll." } } end })
        for i, id in ipairs({ "a.one", "a.two", "a.three" }) do
          Bastians:RegisterAction(m, { id = id, label = id, types = { "npc" }, order = 30 + i, main = true,
            run = function() end })
        end
        """
    )
    host(app, 460)
    app.execute("dossier:SetSubject('npc:448')")
    hd, bl = heads(app), blocks(app)
    assert [(h["title"], h["count"]) for h in hd] == [
        ("Quests", "3"),
        ("About", None),
        ("Overview", None),
    ]
    assert [(b["title"], b["bare"]) for b in bl] == [
        ("WANTED BY", False),
        ("STARTS", False),
        ("LORE", True),
        ("OVERVIEW", True),
    ]
    assert bl[1]["y"] == bl[0]["y"] + bl[0]["h"]  # one under the other inside the chapter
    b = band(app)
    assert b["meta"] == "The gnoll of the hill"  # the type's own lead instead of the summary
    assert [x[0] for x in b["buttons"]] == ["a.one", "a.two", "a.three", "More", "Bookmark"]
    app.execute("dossier.buttons[4]:Click('LeftButton')")
    menu = app.eval("Bastians.UI.EntityMenuFrame()")
    assert menu.IsShown(menu) and menu.ref == "npc:448"
    assert app.errors == []


def test_links_render_relation_rows_with_chips(app: WowRuntime):
    app.execute(WORLD)
    host(app, 460)
    app.execute("dossier:SetSubject('npc:448')")
    assert app.eval("dossier.links:IsShown()") is True
    assert app.eval("dossier.labelPool[1]:GetText()") == "DROPS"
    assert chips(app) == ["Huge Gnoll Claw  1g 23s", "Linen Cloth"]
    _, _, _, _, y = app.eval("dossier.links:GetPoint(1)")
    last = blocks(app)[-1]
    assert -y == last["y"] + last["h"] + 14  # below the blocks
    app.execute("dossier.chipPool[2]:Click('LeftButton')")
    assert list(app.eval("clicked").values()) == ["item:2589/LeftButton"]
    # the default click without a host handler: the primary action
    app.execute(
        "dossier.opts.onClick = nil; dossier.chipPool[1]:Click('RightButton')"
    )  # menu, no error
    assert app.errors == []


def test_nothing_is_built_while_hidden(app: WowRuntime):
    app.execute(WORLD)
    host(app, 460)
    app.execute("host:Hide(); dossier:SetSubject('npc:448')")
    assert app.eval("#dossier.blockPool") == 0 and app.eval("dossier.band:IsShown()") is False
    assert app.eval("dossier.dirty") is True
    app.execute("host:Show(); dossier.frame:Hide(); dossier.frame:Show()")
    assert app.eval("#dossier.blockPool") == 3 and app.eval("dossier.band:IsShown()") is True
    assert app.eval("dossier.dirty") is False
    app.execute("dossier:Clear()")
    assert (
        app.eval("dossier.band:IsShown()") is False
        and app.eval("dossier.blockPool[1]:IsShown()") is False
    )
    assert app.errors == []


def test_flat_tree_mode_has_no_fold_markers_and_opens_every_branch(core: WowRuntime):
    core.execute(
        """
        host = CreateFrame("Frame", nil, UIParent)
        host:SetSize(300, 200)
        tree = Bastians.UI.Tree(host, { flat = true })
        tree.scroll:SetSize(300, 200)
        tree:SetRows({ { text = "Vendors", collapsed = true, children = { { text = "Corina", ref = "npc:1", icon = "x" } } },
          { text = "Inn" } })
        """
    )
    assert [r.text for r in core.eval("tree.flat").values()] == ["Vendors", "Corina", "Inn"]
    assert core.eval("tree.pool[1].fold:IsShown()") is False
    assert core.eval("tree.bar:IsShown()") is False and core.eval("tree.chips:IsShown()") is False
    assert core.eval("(select(4, tree.pool[2]:GetPoint(1)))") == 8  # a small step for children
    assert core.eval("(select(4, tree.pool[1].text:GetPoint(1)))") == 3  # no room kept for a marker
    # the NPC's face (16 px, the skin's row portraits, ADR 0034), then the text
    assert core.eval("(select(4, tree.pool[2].text:GetPoint(1)))") == 22
    assert core.errors == []


def test_the_fixture_world_renders_as_a_dossier(wow: WowRuntime):
    """Data's real sections on the fixture world: Marshal Dughan's dossier has blocks, the band
    carries the distance to his spawn, and no section is lost on the way."""
    wow.start(CORE, DATA, QUESTS, BROWSER)  # the packs load for the modules that want them
    wow.run_frames(10)
    wow.advance(0.3)
    host(wow, 460)
    wow.execute("dossier:SetSubject('npc:240')")
    b = band(wow)
    assert (
        b["name"] == "Marshal Dughan" and b["meta"] == "Marshal in Elwynn Forest. Starts 2 quests."
    )
    assert b["status"] is not None and b["status"].endswith("yd")
    titles = [x["title"] for x in blocks(wow)]
    sections = wow.eval("Bastians:GetDetailSections('npc:240')").values()
    expected = [s.title.upper() for s in sections if not s["def"].link]
    # no section is lost; the type's reading order (ADR 0054), in one column the facts last
    assert sorted(titles) == sorted(expected) and titles[-1] == "OVERVIEW"
    assert [h["title"] for h in heads(wow)] == ["Quests", "Locations"]
    assert chips(wow) == ["Elwynn Forest"]  # Data's zone link (C2)
    assert wow.errors == []


def test_a_block_marked_two_line_draws_its_meta_rows_on_two_lines(app: WowRuntime):
    """S7: `block = { twoLine = true }` makes that block's rows with `meta` two lines high (the
    reward comparison); the other blocks of the same dossier stay one line, the pooled tree frame
    is switched per block."""
    app.execute(WORLD)
    app.execute(
        """
        local m = Bastians:GetModule("TestApp")
        Bastians:RegisterDetailSection(m, { id = "t.choice", title = "Which", types = { "npc" },
          order = 15, block = { wide = true, twoLine = true },
          build = function(ref) return ref == "npc:448" and {
            { title = "Saber", meta = "+3 Strength", text = "Saber  +3 Strength", value = 200,
              valueKind = "money" },
            { title = "Leather", meta = "AH median", text = "Leather  AH median" } } or nil end })
        Bastians:RegisterDetailSection(m, { id = "t.one", title = "One line", types = { "npc" },
          order = 16,
          build = function(ref) return ref == "npc:448" and {
            { title = "Plain", meta = "ignored here", text = "Plain  ignored here" } } or nil end })
        """
    )
    host(app, 700)
    app.execute("dossier:SetSubject('npc:448', nil, { source = 'test' })")
    app.run_frames(3)
    by_title = {b["title"]: b for b in blocks(app)}
    assert by_title["WHICH"]["rows"] == ["Saber  +3 Strength", "Leather  AH median"]
    # on a sheet every row with a meta takes two lines (ADR 0054): two 34 px rows against one
    assert by_title["WHICH"]["h"] == by_title["ONE LINE"]["h"] + 34
    frames = {}
    for bf in app.eval("dossier.blockPool").values():
        if bf.IsShown(bf):
            frames[bf.title.GetText(bf.title)] = [
                (f.text.GetText(f.text), f.meta.GetText(f.meta) if f.meta.IsShown(f.meta) else None)
                for f in bf.tree.pool.values()
                if f.IsShown(f)
            ]
    assert frames["WHICH"] == [("Saber", "+3 Strength"), ("Leather", "AH median")]
    assert frames["ONE LINE"] == [("Plain", "ignored here")]  # on a sheet too, unmarked
    assert app.errors == []


PAPER = """
local S = Bastians.UI.Style
paper, theme = S.Palette("parchment"), { C = S.C, H = S.H }
function rgb(c) return math.floor(c[1] * 1000 + 0.5) .. " " .. math.floor(c[2] * 1000 + 0.5) .. " "
  .. math.floor(c[3] * 1000 + 0.5) end
function ink(fs) local r, g, b = fs:GetTextColor() return rgb({ r, g, b }) end
function tone(tex) local r, g, b = tex:GetVertexColor() return rgb({ r, g, b }) end
local m = Bastians:GetModule("TestApp")
Bastians:RegisterDetailSection(m, { id = "t.coded", title = "Coded", types = { "npc" }, order = 12,
  build = function(ref) return { { text = S.H.dim .. "quiet words|r", ref = "npc:448" } } end })
"""


def test_a_page_on_paper_draws_in_the_papers_colours_also_later(app: WowRuntime):
    """AT1 leftover: what a page on parchment draws after its layout is the paper's too: the
    colour codes a section writes into its rows, the icons under the mouse (a listed action that
    cannot run is greyed in the paper's dim), a tree that renders again on its own."""
    app.execute(WORLD)
    app.execute(PAPER)
    host(app, 460)
    app.execute("sections = dossier:Sections('npc:448') dossier:SetSubject('npc:448', sections)")
    assert app.eval("dossier.palette == paper and paper.H.dim ~= theme.H.dim")
    coded = next(b for b in app.eval("dossier.blockPool").values() if b.block.id == "t.coded")
    app.execute(
        "coded = nil for _, b in ipairs(dossier.blockPool) do"
        " if b.block and b.block.id == 't.coded' then coded = b end end"
    )
    assert coded.block.rows[1].text.startswith(app.eval("paper.H.dim"))
    # the row under the mouse: Route cannot run, its icon is greyed in the paper's dim
    app.execute(
        """
        row = coded.tree.pool[1]
        row:GetScript("OnEnter")(row)
        greyed = nil
        for _, b in ipairs(row.icons) do if b:IsShown() and b.disabled then greyed = b end end
        """
    )
    assert app.eval("greyed ~= nil and tone(greyed.tex) == rgb(paper.C.dim)")
    assert app.eval("tone(coded.tree.blockFill or row.hl) ~= ''")
    # a render of the tree on its own (a fold, a selection) keeps the paper's text colour
    app.execute("coded.tree:Render()")
    assert app.eval("ink(row.text) == rgb(paper.C.text)")
    assert app.eval("Bastians.UI.Style.C == theme.C")  # the theme is back after each of them
    assert app.errors == []


def test_the_parchment_option_switches_an_open_page(app: WowRuntime):
    """AT1 leftover: `sheetParchment` off takes the paper away and gives the page the look's
    colours at its next layout, on brings them back; no reload."""
    app.execute(WORLD)
    app.execute(PAPER)
    host(app, 460)
    app.execute("dossier:SetSubject('npc:448', dossier:Sections('npc:448'))")
    name = "dossier.band.name"
    assert app.eval(f"dossier.paper:IsShown() and ink({name}) == rgb(paper.C.accent)")
    app.execute(
        """
        Bastians:GetModule("Core").db.profile.sheetParchment = false
        Bastians.UI.Style.ApplySkin()
        dossier:SetSubject('npc:448', dossier:Sections('npc:448'))
        """
    )
    assert app.eval("dossier.palette == nil and dossier.frame.palette == nil")
    assert app.eval(f"not dossier.paper:IsShown() and ink({name}) == rgb(theme.C.accent)")
    app.execute(
        "coded = nil for _, b in ipairs(dossier.blockPool) do"
        " if b.block and b.block.id == 't.coded' then coded = b end end"
    )
    assert app.eval("coded.block.rows[1].text:sub(1, 10) == theme.H.dim")
    assert app.eval(
        "ink(coded.tree.pool[1].text) == rgb(theme.C.text) and coded.tree.palette == nil"
    )
    app.execute(
        """
        Bastians:GetModule("Core").db.profile.sheetParchment = true
        Bastians.UI.Style.ApplySkin()
        dossier:Refresh()
        """
    )
    assert app.eval(f"dossier.paper:IsShown() and ink({name}) == rgb(paper.C.accent)")
    assert app.eval("ink(coded.tree.pool[1].text) == rgb(paper.C.text)")
    assert app.errors == []


def test_the_left_page_stays_while_the_reading_scrolls(app: WowRuntime):
    """AT1 leftover: on two pages the figure and the facts under it stay in view while the
    reading scrolls; a left page taller than the view scrolls until its end shows."""
    shift = "Bastians.UI.DossierUtil.leftShift"
    assert app.eval(f"{shift}(0, 500, 320, 2000)") == 0
    assert app.eval(f"{shift}(300, 500, 320, 2000)") == 300  # it fits: it stays at the top
    assert app.eval(f"{shift}(300, 500, 700, 2000)") == 100  # taller: its end stays in view
    assert app.eval(f"{shift}(1900, 500, 320, 2000)") == 1680  # never past the sheet's end
    app.execute(WORLD)
    app.execute(
        """
        local m = Bastians:GetModule("TestApp")
        Bastians:RegisterDetailSection(m, { id = "t.facts", title = "Facts", types = { "npc" }, order = 5,
          chapter = "facts", build = function() return { { text = "Elite" } } end })
        Bastians:RegisterDetailSection(m, { id = "t.long", title = "Long", types = { "npc" }, order = 25,
          block = { limit = 80 }, build = function()
            local rows = {}
            for i = 1, 60 do rows[i] = { text = "Row " .. i } end
            return rows
          end })
        host = CreateFrame("Frame", nil, UIParent)
        host:SetSize(914, 500)
        dossier = Bastians.UI.Dossier(host, { ctx = { source = "test" }, portrait = true })
        dossier.scroll:SetSize(900, 500)
        dossier:SetSubject('npc:448')
        """
    )
    assert app.eval("dossier.pages == 2 and dossier.height > 1000")
    stage = app.eval("dossier.band.stage.frame")
    facts = app.eval("dossier.leftBlocks[1].frame")
    assert stage.GetPoint(stage, 1)[4] == -6 and facts.GetPoint(facts, 1)[4] == -(6 + 306 + 14)
    app.execute("dossier.bar.ScrollTo(250)")
    assert stage.GetPoint(stage, 1)[4] == -256 and facts.GetPoint(facts, 1)[4] == -(
        6 + 306 + 14 + 250
    )
    app.execute("dossier.bar.ScrollTo(0)")
    assert stage.GetPoint(stage, 1)[4] == -6
    assert app.errors == []
