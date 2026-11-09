"""The skin: one section on the General page for
every look setting; Modern or Azeroth (Morpheus headings in gold, ornaments); the game's window
frames as a switch of their own; loot as a grid of icon cells, places as cuts of the map, the
zone's painting behind a creature, creatures that greet, faces in NPC rows, page sounds. Each
switch changes what it names; off gives back today's look."""

import pytest
from harness import WowRuntime

CORE, DATA, QUESTS, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Browser",
)
S = "Bastians.UI.Style"
SC = "Bastians.UI.Scenery"
PROFILE = "Bastians:GetModule('Core').db.profile"
MOD = "Bastians:GetModule('Browser')"
BR = f"{MOD}.Browser"
STAGE = f"{MOD}.dossier.band.stage"


def set_option(wow: WowRuntime, key: str, value: str) -> None:
    """Sets a General page option as the hub does: the value, its handler, the bus message."""
    wow.execute(
        f"""
        local core = Bastians:GetModule('Core')
        for _, o in ipairs(core.def.options) do
          if o.key == '{key}' then
            core.db.profile[o.key] = {value}
            if o.set then o.set({value}, core) end
          end
        end
        """
    )


# ---------------------------------------------------------------------------------------------
# Pure helpers
# ---------------------------------------------------------------------------------------------


def test_the_grid_and_the_cut_window(core: WowRuntime):
    shape = core.eval(f"{{ {SC}.GridShape(9, 250, 56, 56, 4) }}")
    assert list(shape.values()) == [4, 3, 3 * 56 + 2 * 4]  # four a row, three rows
    assert list(core.eval(f"{{ {SC}.GridShape(0, 250, 56, 56, 4) }}").values()) == [4, 0, 0]
    assert core.eval(f"{SC}.GridShape(3, 10, 56, 56, 4)")[0] == 1  # never fewer than one a row
    # a cut around the middle of a 1000 x 600 painting, 30 % wide, half as tall as wide
    w = list(core.eval(f"{{ {SC}.CutWindow(0.5, 0.5, 1000, 600, 0.3, 0.5) }}").values())
    assert w == [350, 225, 300, 150, 150, 75]
    # at the edge the window stays on the painting and the point moves in it
    w = list(core.eval(f"{{ {SC}.CutWindow(0.02, 0.98, 1000, 600, 0.3, 0.5) }}").values())
    assert w[:2] == [0, 450] and w[4] == 20 and w[5] == 138
    # a tile half inside the window: its texture coordinates are cut to the part inside
    crop = list(
        core.eval(
            f"{{ {SC}.Crop({{ px1 = 0, py1 = 0, px2 = 256, py2 = 256, tcRight = 1, tcBottom = 1 }},"
            " 128, 0, 300, 150) }"
        ).values()
    )
    assert crop == [0.5, 1, 0, 150 / 256, 128, 0, 256, 150]
    assert core.eval(f"{SC}.Crop({{ px1 = 0, py1 = 0, px2 = 10, py2 = 10 }}, 20, 20, 5, 5)") is None
    assert core.errors == []


def test_the_greeting_follows_the_services(core: WowRuntime):
    g = f"{SC}.Greeting"
    assert core.eval(f"{g}({{ flags = {{ 'vendor', 'repair' }} }})") == "wave"
    assert core.eval(f"{g}({{ flags = 'trainer' }})") == "bow"
    assert core.eval(f"{g}({{ flags = 'questgiver' }})") == "exclaim"
    assert core.eval(f"{g}({{ flags = 'elite' }})") == "roar"  # no service: a creature roars
    assert core.eval(f"{g}(nil)") == "roar"
    assert core.errors == []


# ---------------------------------------------------------------------------------------------
# The section, the skin, the frames
# ---------------------------------------------------------------------------------------------


def test_one_section_holds_every_look_setting(core: WowRuntime):
    options = list(core.eval("Bastians:GetModule('Core').def.options").values())
    labels = [(o["type"], o.label, o.key) for o in options]
    start = next(i for i, x in enumerate(labels) if x[1] == "Skin (every Bastian's addon)")
    end = next(i for i in range(start + 1, len(labels)) if labels[i][0] == "header")
    keys = [x[2] for x in labels[start + 1 : end]]
    assert keys == [
        None,  # Use the WoW look
        None,  # Use the Modern look (the Azeroth row went with ADR 0046)
        "preset",
        "newPreset",  # Save as new preset
        None,  # Delete this preset
        "gameFrames",  # the game's own windows and insets
        "skinFrames",
        "theme",
        "font",
        "headingFont",
        "fontScale",
        "windowColor",
        "windowAlpha",
        "gameButtons",
        "ornaments",
        "sheetParchment",
        "rowPortraits",
        "placeCuts",
        "diorama",
        "modelMotion",
        "pageSounds",
    ]
    assert "Windows" not in [x[1] for x in labels]  # folded into the section
    profile = core.eval(PROFILE)
    assert profile.preset == "modern-dark" and profile.skinFrames is True  # the frames are standard
    for key in ("rowPortraits", "placeCuts", "diorama", "modelMotion", "pageSounds"):
        assert profile[key] is True, key
    assert core.errors == []


def test_the_heading_font_is_a_setting_of_its_own(core: WowRuntime):
    """ADR 0038: window titles, page names and section titles take `headingFont` (nil: the text
    font) in the title bar's colour; Morpheus and the like draw at the heading's bigger size."""
    core.execute("W = Bastians.UI.Window('SkinTestFrame', { title = 'T' }); W:Show()")
    font, size = core.eval("W.title:GetFont()")[:2]
    assert font != "Fonts\\MORPHEUS.TTF"
    set_option(core, "headingFont", "'Fonts\\\\MORPHEUS.TTF'")
    assert core.eval("(W.title:GetFont())") == "Fonts\\MORPHEUS.TTF"
    assert core.eval("(select(2, W.title:GetFont()))") > size
    assert core.eval("{ W.title:GetTextColor() }")[1] == core.eval(f"{S}.C.headerText[1]")
    set_option(core, "headingFont", "nil")
    assert core.eval("(W.title:GetFont())") == font
    assert core.eval(f"{PROFILE}.preset") == "modern-dark"  # set_option fires no message: no Custom
    assert core.errors == []


def test_the_games_window_frames_are_a_switch_of_their_own(core: WowRuntime):
    core.execute("W = Bastians.UI.Window('FrameTestFrame', { title = 'T' }); W:Show()")
    # the frames are the standard: on from the first window
    assert core.eval("W.border:IsShown()") is True
    assert core.eval("(select(4, W.head:GetPoint(1)))") == 9  # moved in by the frame's width
    assert core.eval("W.frame.edges:IsShown()") is False  # the round outline goes
    assert core.eval("W.frame.bg:IsShown()") is True  # Modern keeps its flat ground inside
    set_option(core, "skinFrames", "false")
    assert core.eval("W.border:IsShown()") is False
    assert core.eval("(select(4, W.head:GetPoint(1)))") == 1
    assert core.eval("W.frame.edges:IsShown()") is True
    assert core.eval(f"{S}.Ornaments()") is False  # the other settings did not change
    set_option(core, "skinFrames", "true")
    assert core.eval("W.border:IsShown()") is True
    assert core.errors == []


def test_section_titles_keep_their_case_over_an_ornament(app: WowRuntime):
    host(app)
    app.execute(TABLES)
    app.execute("dossier:SetSubject('npc:448')")
    # a section alone in its chapter: the chapter's heading names it and carries the rule
    # (ADR 0054); the block's own title, in capitals, does not show
    bf, head = block(app, "LOOT"), app.eval("dossier.chapterPool[1]")
    assert bf.title.IsShown(bf.title) is False and bf.line.IsShown(bf.line) is False
    assert head.title.GetText(head.title) == "Loot"
    assert head.line.IsShown(head.line) is True and head.orn.IsShown(head.orn) is False
    set_option(app, "ornaments", "true")
    app.execute("dossier:Refresh()")
    assert block(app, "Loot") is not None  # a block title keeps its case over an ornament
    assert head.orn.IsShown(head.orn) is True and head.line.IsShown(head.line) is False
    assert app.errors == []


# ---------------------------------------------------------------------------------------------
# Lists without the spreadsheet
# ---------------------------------------------------------------------------------------------

HOST = """
host = CreateFrame("Frame", nil, UIParent)
host:SetSize(434, 600)
clicked = {}
dossier = Bastians.UI.Dossier(host, { ctx = { source = "test" },
  onClick = function(row, button) clicked[#clicked + 1] = (row.ref or row.text) .. "/" .. button end })
dossier.scroll:SetSize(420, 600)
"""

TABLES = """
local m = Bastians:GetModule("TestApp")
Bastians:RegisterEntityType(m, { type = "npc", name = function(id) return "Npc " .. id end })
Bastians:RegisterEntityType(m, { type = "item", name = function(id) return "Item " .. id end })
Bastians:RegisterDetailSection(m, { id = "t.loot", title = "Loot", types = { "npc" }, order = 10,
  block = { limit = 2, table = true },
  build = function(ref)
    local rows = {}
    for i = 1, 5 do
      rows[i] = { text = "Item " .. i, ref = "item:" .. (i == 1 and 2589 or i), icon = 132889, note = i .. "0 %" }
    end
    return rows
  end })
Bastians:RegisterDetailSection(m, { id = "t.mixed", title = "Mixed", types = { "npc" }, order = 11,
  block = { table = true },
  build = function(ref) return { { text = "With", ref = "item:2589", icon = 132889 }, { text = "World drop" } } end })
Bastians:RegisterDetailSection(m, { id = "t.where", title = "Where", types = { "npc" }, order = 12,
  build = function(ref) return { { text = "Elwynn Forest  27, 20", ref = ref, place = { map = 1429, x = 0.27, y = 0.2 } },
    { text = "Nowhere  10, 10", ref = ref, place = { map = 4242, x = 0.1, y = 0.1 } } } end })
"""


def host(app: WowRuntime) -> None:
    app.execute(HOST)


def block(app: WowRuntime, title: str):
    for bf in app.eval("dossier.blockPool").values():
        if bf.IsShown(bf) and bf.title.GetText(bf.title) == title:
            return bf
    return None


def cells(bf) -> list:
    return [c for c in (bf.cells or {}).values() if c.IsShown(c)]


def test_loot_is_rows_with_the_picture_and_the_name(app: WowRuntime):
    """the loot grid showed placeholder squares; items are rows with
    their picture and name, and a row that links an entity without a picture of its own shows the
    entity's."""
    host(app)
    app.execute(TABLES)
    app.execute(
        """Bastians:RegisterEntityType(Bastians:GetModule("TestApp"), { type = "zone",
          name = function(id) return "Zone " .. id end, icon = function() return 136000 end })
        Bastians:RegisterDetailSection(Bastians:GetModule("TestApp"), { id = "t.link",
          title = "Link", types = { "npc" }, order = 13,
          build = function() return { { text = "Zone: Elwynn", ref = "zone:1429" },
            { text = "Bare", ref = "zone:1429", icon = false } } end })"""
    )
    app.execute("dossier:SetSubject('npc:448')")
    loot = block(app, "LOOT")
    assert loot.mode is None and loot.tree.scroll.IsShown(loot.tree.scroll) is True
    rows = [f for f in loot.tree.pool.values() if f.IsShown(f)]
    assert [f.row.text for f in rows][:2] == ["Item 1", "Item 2"]
    assert rows[0].icon.IsShown(rows[0].icon) is True
    link = [f for f in block(app, "LINK").tree.pool.values() if f.IsShown(f)]
    assert link[0].icon.IsShown(link[0].icon) is True  # the zone's picture
    assert link[0].icon.GetTexture(link[0].icon) == 136000
    assert link[1].icon.IsShown(link[1].icon) is False  # icon = false: bare
    assert app.eval("Bastians.UI.Style.Skin('lootGrid')") is None  # the switch is gone
    assert app.errors == []


def test_the_places_of_one_thing_show_as_a_mini_map_per_zone(app: WowRuntime):
    """ADR 0056: "one mini map per zone with every place on it"."""
    host(app)
    app.execute(TABLES)
    app.execute("dossier:SetSubject('npc:448')")
    where = block(app, "WHERE")
    assert where.mode == "maps"
    shown = cells(where)
    # no zone record in this world: the row's own words
    assert [c.caption.GetText(c.caption) for c in shown] == [
        "Elwynn Forest  27, 20",
        "Nowhere  10, 10",
    ]
    elwynn, nowhere = shown
    dots = [d for d in elwynn.dots.values() if d.IsShown(d)]
    assert len(dots) == 1 and elwynn.pin.IsShown(elwynn.pin) is False
    assert any(t.IsShown(t) for t in elwynn.art.values())  # no style: the painting's tiles
    assert not any(d.IsShown(d) for d in nowhere.dots.values())  # no art: the caption only
    assert where.GetHeight(where) > 160  # a mini map is taller than a row
    # a dot sits by its map fraction
    w, h = elwynn.cut.GetWidth(elwynn.cut), elwynn.cut.GetHeight(elwynn.cut)
    _, _, _, x, y = dots[0].GetPoint(dots[0], 1)
    assert (round(x / w, 2), round(-y / h, 2)) == (0.27, 0.2)
    # a second place in the zone: one map, the count under it
    grouped = app.eval(
        "Bastians.UI.Scenery.PlaceMaps({ { place = { map = 1, x = 0, y = 0 } },"
        " { place = { map = 2, x = 0, y = 0 } }, { place = { map = 1, x = 1, y = 1 } } })"
    )
    assert [(e.map, len(list(e.rows.values()))) for e in grouped.values()] == [(1, 2), (2, 1)]
    # the skin's switch off: rows again
    set_option(app, "placeCuts", "false")
    app.execute("dossier:Refresh()")
    where = block(app, "WHERE")
    assert where.mode is None and cells(where) == []
    assert app.errors == []


def test_the_places_of_several_things_stay_cuts_of_the_map(app: WowRuntime):
    """A zone's areas: each has a page of its own, so each keeps a cut."""
    host(app)
    app.execute(TABLES)
    app.execute(
        """
        BST_ROWS = { rows = {
          { text = "One", ref = "area:1", place = { map = 1429, x = 0.3, y = 0.3 } },
          { text = "Two", ref = "area:2", place = { map = 1429, x = 0.6, y = 0.6 } } } }
        """
    )
    assert app.eval("Bastians.UI.Scenery.BlockMode(BST_ROWS)") == "places"
    app.execute("BST_ROWS.rows[2].ref = 'area:1'")
    assert app.eval("Bastians.UI.Scenery.BlockMode(BST_ROWS)") == "maps"
    app.execute("BST_ROWS.rows[1].ref, BST_ROWS.rows[2].ref = nil, nil")
    assert app.eval("Bastians.UI.Scenery.BlockMode(BST_ROWS)") == "places"
    assert app.errors == []


def test_a_click_finds_the_nearest_place(app: WowRuntime):
    host(app)
    nearest = "Bastians.UI.Scenery.NearestPlace"
    rows = "{ { n = 1, place = { x = 0.1, y = 0.1 } }, { n = 2, place = { x = 0.8, y = 0.7 } } }"
    assert app.eval(f"{nearest}({rows}, 0.7, 0.6).n") == 2
    assert app.eval(f"{nearest}({rows}, 0.2, 0.3).n") == 1
    assert app.eval(f"{nearest}({rows}, nil, nil).n") == 1  # the mouse unknown: the first
    assert app.errors == []


def test_npc_rows_show_the_creatures_face(core: WowRuntime):
    # a model gets its creature only once it has its place (the quest
    # sheet's people tiles showed no picture; a model set with no place stays empty)
    core.execute(
        """
        placedAtSet = {}
        local show = Bastians.Compat.ShowCreature
        Bastians.Compat.ShowCreature = function(m, id)
          placedAtSet[#placedAtSet + 1] = m:GetNumPoints() > 0 and m:IsShown()
          return show(m, id)
        end
        """
    )
    core.execute(
        """
        host = CreateFrame("Frame", nil, UIParent)
        host:SetSize(300, 200)
        tree = Bastians.UI.Tree(host, { flat = true })
        tree.scroll:SetSize(300, 200)
        tree:SetRows({ { text = "Corina", ref = "npc:7", icon = "x" }, { text = "Cloth", ref = "item:2589", icon = "x" } })
        """
    )
    face = core.eval("tree.faces.byNpc[7]")
    assert face is not None and face.creature == 7 and face.portraitZoom == 1
    assert list(core.eval("placedAtSet").values()) == [True]
    assert face.IsShown(face) is True
    assert core.eval("tree.pool[1].icon:IsShown()") is False  # the face in place of the glyph
    assert core.eval("tree.pool[2].icon:IsShown()") is True  # an item keeps its icon
    # scrolling the same creature onto another row frame re-anchors its model, no second load
    core.execute(
        "tree:SetRows({ { text = 'Cloth', ref = 'item:2589' }, { text = 'Corina', ref = 'npc:7' } })"
    )
    assert core.eval("#tree.faces.models") == 1
    set_option(core, "rowPortraits", "false")
    core.execute("tree:Refresh()")
    assert face.IsShown(face) is False
    assert core.errors == []


# ---------------------------------------------------------------------------------------------
# Models brought to life, page sounds (the Browser on the fixture world)
# ---------------------------------------------------------------------------------------------


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA, QUESTS, BROWSER)
    wow.run_frames(10)
    wow.advance(0.3)
    return wow


def test_a_creature_stands_in_its_zone_and_greets(wow: WowRuntime):
    boot(wow)
    # Marshal Dughan, a quest giver in Elwynn; the mock's painting has a full set of tiles
    wow.execute("Mock.maps[1429].textures = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 }")
    wow.execute(f"{BR}.Open('npc:240')")
    wow.run_frames(2)
    scene = [t for t in wow.eval(f"{STAGE}.scene").values() if t.IsShown(t)]
    assert scene and all(abs(t.GetAlpha(t) - 0.55) < 1e-6 for t in scene)
    model = f"{STAGE}.model"
    assert wow.eval(f"{model}.animation") is None  # nothing before the model is there
    wow.execute(f"{model}:GetScript('OnModelLoaded')({model})")
    assert wow.eval(f"{model}.animation") == 64  # a quest giver exclaims
    wow.execute(f"{model}:GetScript('OnAnimFinished')({model})")
    assert wow.eval(f"{model}.animation") == 0  # then he stands
    wow.execute(f"{model}:GetScript('OnEnter')({model})")
    assert wow.eval(f"{model}.animation") == 60  # he talks while the mouse rests on him
    wow.execute(f"{model}:GetScript('OnLeave')({model})")
    assert wow.eval(f"{model}.animation") == 0
    # Hogger has no service: he roars
    wow.execute(f"{BR}.Open('npc:448')")
    wow.execute(f"{model}:GetScript('OnModelLoaded')({model})")
    assert wow.eval(f"{model}.animation") == 74
    # off: no scenery, no greeting
    set_option(wow, "diorama", "false")
    set_option(wow, "modelMotion", "false")
    wow.execute(f"{BR}.Open('npc:240')")
    wow.execute(f"{model}.animation = nil; {model}:GetScript('OnModelLoaded')({model})")
    assert wow.eval(f"{model}.animation") is None
    assert not any(t.IsShown(t) for t in wow.eval(f"{STAGE}.scene").values())
    # an item's model gets no scenery either
    wow.execute("Mock.items[2589].equipLoc = 'INVTYPE_WEAPON'")
    set_option(wow, "diorama", "true")
    wow.execute(f"{BR}.Open('item:2589')")
    assert not any(t.IsShown(t) for t in wow.eval(f"{STAGE}.scene").values())
    assert wow.errors == []


def test_after_the_greeting_a_creature_plays_random_emotes_it_has(wow: WowRuntime):
    """ "a random animation for everything that supports it"."""
    boot(wow)
    model = f"{STAGE}.model"
    # the dice: the shortest wait, the first emote left
    wow.execute(f"{SC}.random = function(a, b) return a end")
    wow.execute(f"{BR}.Open('npc:240')")
    wow.execute(f"{model}:GetScript('OnModelLoaded')({model})")
    wow.execute(f"{model}:GetScript('OnAnimFinished')({model})")  # the greeting ends: he stands
    assert wow.eval(f"{model}.animation") == 0
    wow.advance(6.1)
    assert wow.eval(f"{model}.animation") == 60  # the first emote: talk
    wow.execute(f"{model}:GetScript('OnAnimFinished')({model})")
    wow.advance(6.1)
    assert wow.eval(f"{model}.animation") == 64  # never the same twice in a row
    # an emote that never reports its end: he stands after ONCE_MAX seconds anyway
    wow.advance(5.1)
    assert wow.eval(f"{model}.animation") == 0
    # only what the model has: this one knows the wave alone
    wow.execute(f"{model}.HasAnimation = function(_, id) return id == 67 end")
    wow.advance(6.1)
    assert wow.eval(f"{model}.animation") == 67
    # a greeting the model lacks gives way to an emote it has
    wow.execute(f"{BR}.Open('npc:448')")  # Hogger would roar
    wow.execute(f"{model}:GetScript('OnModelLoaded')({model})")
    assert wow.eval(f"{model}.animation") == 67
    # a new subject cancels the old one's emotes; a hidden model plays none
    wow.execute(f"{model}:GetScript('OnAnimFinished')({model})")
    wow.execute(f"{model}.HasAnimation = nil; {model}.animations = {{}}")
    wow.execute(f"{STAGE}.frame:Hide()")
    wow.advance(20)
    assert list(wow.eval(f"{model}.animations").values()) == []
    assert wow.errors == []


def test_a_page_sounds_as_it_opens(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.kits = {}")
    wow.execute(f"{BR}.Open('npc:240')")
    wow.advance(0.3)
    wow.execute(f"{BR}.Open('quest:{QUEST}')")
    kits = list(wow.eval("Mock.kits").values())
    assert kits == [836, 844]  # the page turn, then the quest log's sound
    wow.execute(f"{BR}.Open('npc:448')")  # within 0.2 s of the last: quiet
    assert len(list(wow.eval("Mock.kits").values())) == 2
    wow.advance(0.3)
    wow.execute(f"{MOD}.dossier:SetSubject('npc:240', nil, nil, {{ preview = true }})")
    assert len(list(wow.eval("Mock.kits").values())) == 2  # a preview is quiet
    set_option(wow, "pageSounds", "false")
    wow.advance(0.3)
    wow.execute(f"{BR}.Open('npc:8719')")
    assert len(list(wow.eval("Mock.kits").values())) == 2
    assert wow.errors == []


QUEST = 62  # The Fargodeep Mine, from Marshal Dughan


def test_a_floor_plate_lays_its_tiles_and_pins_out_by_the_width(core: WowRuntime):
    """DG2 (data.md "Dungeons"): the pure layout of a dungeon floor: the plate's height from the
    floor's aspect (never taller than wide), the tiles scaled from floor pixels, the bosses and the
    door as pins in plate pixels."""
    core.execute(
        """floor = { w = 1000, h = 500, tiles = { { 205041, -100, 0, 500, 500, 2 }, { 211425, 500, 250, 250, 250, 0 } },
          bosses = { { 1, 20, 50, "Boss" } }, door = { 90, 10 } }
        H, T, P = Bastians.UI.Scenery.FloorLayout(floor, 400)
        tall = { w = 100, h = 300 }
        H2 = Bastians.UI.Scenery.FloorLayout(tall, 400)"""
    )
    assert core.eval("H") == 200  # 400 wide, the floor's aspect 0.5
    assert core.eval("H2") == 400  # capped at square
    tiles = [list(t.values()) for t in core.eval("T").values()]
    assert tiles == [[205041, -40, 0, 200, 200, 2], [211425, 200, 100, 100, 100, 0]]
    pins = [list(p.values()) for p in core.eval("P").values()]
    assert pins == [[80, 100, "1", "boss", "Boss"], [360, 20, "", "door"]]
    assert core.eval(
        "Bastians.UI.Scenery.FloorsHeight({ { floor = floor }, { floor = tall } }, 400)"
    ) == (200 + 16 + 6 + 400 + 16 + 6)
    assert core.errors == []


@pytest.mark.parametrize(
    ("locale", "want"),
    [
        ("enUS", (False, False, False)),
        ("deDE", (False, False, False)),
        ("ptBR", (False, False, False)),
        ("koKR", (True, True, True)),
        ("zhTW", (True, True, True)),
        ("ruRU", (True, False, True)),
    ],
)
def test_a_client_with_its_own_script_keeps_its_fonts(wow: WowRuntime, locale: str, want: tuple):
    """ADR 0033: the Asian clients and ruRU (Cyrillic unverified in ARIALN and Morpheus, assumed
    04.11.2026) draw in STANDARD_TEXT_FONT and keep it for headings; S.CJK stays Asian only; a
    Latin client (de, pt) keeps the suite's fonts."""
    wow.mock.locale = locale
    wow.start(CORE)
    wow.run_frames(3)
    got = wow.eval(
        f"{{ {S}.CLIENT_FONT, {S}.CJK, {S}.DEFAULT_FONT == STANDARD_TEXT_FONT,"
        f" {S}.headingFont() == {S}.font() }}"
    )
    assert (got[1], got[2], got[3]) == want
    if want[0]:
        assert got[4] is True
    assert wow.errors == []
