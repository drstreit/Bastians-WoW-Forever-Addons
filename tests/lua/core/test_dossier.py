"""The dossier renderer (C1, ADR 0014): Bastians.UI.Dossier draws one entity as a header band, the
registered sections as blocks in a grid of one to three columns by width, and the sections marked
`link` as relation rows with chips. Pooled frames, nothing built while hidden."""

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
                    "count": bf.count.GetText(bf.count) if bf.count.IsShown(bf.count) else None,
                    "x": x,
                    "y": -y,
                    "w": bf.GetWidth(bf),
                    "h": bf.GetHeight(bf),
                    "rows": [strip(r.text) for r in bf.tree.flat.values()],
                }
            )
    return out


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


def test_the_data_splits_sections_into_band_blocks_and_links(app: WowRuntime):
    app.execute(WORLD)
    data = app.eval("Bastians.UI.DossierData('npc:448', nil, { source = 'test' })")
    assert data.card.name == "Hogger" and data.card.status == "Alive and angry"
    assert data.card.distance == 68
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
    assert strip(app.eval(status % "{ status = 'Done', distance = 50 }")) == "Done  50 yd"
    assert app.eval(status % "{ distance = 50 }") == "50 yd"
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


def test_blocks_flow_into_columns_by_width(app: WowRuntime):
    app.execute(WORLD)
    host(app, 460)  # two columns
    app.execute("dossier:SetSubject('npc:448')")
    assert app.eval("dossier.columns") == 2
    bl = blocks(app)
    assert [b["title"] for b in bl] == ["OVERVIEW", "WANTED BY", "LORE"]
    assert bl[0]["x"] == 0 and bl[1]["x"] > 0 and bl[0]["y"] == bl[1]["y"]  # side by side
    assert bl[2]["x"] == 0 and bl[2]["y"] > bl[1]["y"] and bl[2]["w"] == 460  # wide, below
    assert (
        bl[2]["y"] == bl[0]["y"] + max(bl[0]["h"], bl[1]["h"]) + 14
    )  # a row is as tall as its tallest
    assert bl[2]["h"] > 18 + 20  # the paragraph wraps
    band_h = band(app)["height"]
    assert bl[0]["y"] == band_h + 14
    assert app.eval("dossier.height") > bl[2]["y"] + bl[2]["h"]

    app.execute("host:SetSize(400 + 14, 500); dossier.scroll:SetSize(400, 500); dossier:Refresh()")
    assert app.eval("dossier.columns") == 1
    bl = blocks(app)
    assert [b["x"] for b in bl] == [0, 0, 0] and bl[1]["y"] > bl[0]["y"]
    assert len(set(b["w"] for b in bl)) == 1

    app.execute("host:SetSize(760 + 14, 500); dossier.scroll:SetSize(760, 500); dossier:Refresh()")
    assert app.eval("dossier.columns") == 3
    bl = blocks(app)
    assert bl[0]["y"] == bl[1]["y"] and bl[2]["y"] > bl[0]["y"]  # wide still takes its own row
    assert bl[2]["w"] == 760
    assert app.eval("#dossier.blockPool") == 3  # frames pooled, none created on re-layout
    assert app.errors == []


def test_a_capped_block_shows_more_and_expands_in_place(app: WowRuntime):
    app.execute(WORLD)
    host(app, 460)
    app.execute("dossier:SetSubject('npc:448')")
    quests = blocks(app)[1]
    assert quests["rows"] == ["Quest 1", "Quest 2", "Quest 3", "Quest 4", "Quest 5", "+2 more"]
    assert quests["count"] == "7"
    before = quests["h"]
    # the more row: a click expands the block, the grid re-flows, the more row goes
    app.execute("dossier.blockPool[2].tree.pool[6]:Click('LeftButton')")
    quests = blocks(app)[1]
    assert quests["rows"] == [f"Quest {i}" for i in range(1, 8)] and quests["count"] is None
    assert quests["h"] == before + 18
    assert blocks(app)[2]["y"] == quests["y"] + quests["h"] + 14  # the wide block moved down
    assert list(app.eval("clicked").values()) == []  # the more row is not a row click
    # a row click goes to the host
    app.execute("dossier.blockPool[2].tree.pool[3]:Click('LeftButton')")
    assert list(app.eval("clicked").values()) == ["quest:3/LeftButton"]
    # a new subject forgets the expansion
    app.execute("dossier:SetSubject('npc:7'); dossier:SetSubject('npc:448')")
    assert blocks(app)[1]["rows"][-1] == "+2 more"
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
    assert core.eval("(select(4, tree.pool[2].text:GetPoint(1)))") == 18  # icon, then the text
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
    assert b["name"] == "Marshal Dughan" and b["meta"] == "Level 10, Elwynn Forest"
    assert b["status"] is not None and b["status"].endswith("yd")
    titles = [x["title"] for x in blocks(wow)]
    sections = wow.eval("Bastians:GetDetailSections('npc:240')").values()
    expected = [s.title.upper() for s in sections if not s["def"].link]
    assert titles == expected and "OVERVIEW" in titles
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
    assert by_title["WHICH"]["h"] > by_title["ONE LINE"]["h"] + 34  # two 34 px rows against one
    frames = {}
    for bf in app.eval("dossier.blockPool").values():
        if bf.IsShown(bf):
            frames[bf.title.GetText(bf.title)] = [
                (f.text.GetText(f.text), f.meta.GetText(f.meta) if f.meta.IsShown(f.meta) else None)
                for f in bf.tree.pool.values()
                if f.IsShown(f)
            ]
    assert frames["WHICH"] == [("Saber", "+3 Strength"), ("Leather", "AH median")]
    assert frames["ONE LINE"] == [("Plain  ignored here", None)]
    assert app.errors == []
