"""The skin: one section on the General page for
every look setting; Modern or Azeroth (Morpheus headings in gold, ornaments); the game's window
frames as a switch of their own; loot as a grid of icon cells, places as cuts of the map, the
zone's painting behind a creature, creatures that greet, faces in NPC rows, page sounds. Each
switch changes what it names; off gives back today's look."""

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
        None,  # Use the full WoW look (30.10.2026)
        None,  # Use the Modern look
        "skin",
        "skinFrames",
        "theme",
        "font",
        "fontScale",
        "windowColor",
        "windowAlpha",
        "rowPortraits",
        "placeCuts",
        "diorama",
        "modelMotion",
        "pageSounds",
    ]
    assert "Windows" not in [x[1] for x in labels]  # folded into the section
    profile = core.eval(PROFILE)
    assert profile.skin == "modern" and profile.skinFrames is True  # the frames are standard
    for key in ("rowPortraits", "placeCuts", "diorama", "modelMotion", "pageSounds"):
        assert profile[key] is True, key
    assert core.errors == []


def test_the_azeroth_skin_sets_the_headings_in_morpheus_and_gold(core: WowRuntime):
    core.execute("W = Bastians.UI.Window('SkinTestFrame', { title = 'T' }); W:Show()")
    font = core.eval("(W.title:GetFont())")
    assert font != "Fonts\\MORPHEUS.TTF"
    core.execute(
        """seen = {}
        local m = Bastians:NewModule("SkinWatch", { addon = "Bastians_Core" })
        m:On("BASTIANS_THEME_CHANGED", function() seen[#seen + 1] = 1 end)"""
    )
    set_option(core, "skin", "'azeroth'")
    assert core.eval("(W.title:GetFont())") == "Fonts\\MORPHEUS.TTF"
    assert core.eval("{ W.title:GetTextColor() }")[1] == core.eval(f"{S}.C.gold[1]")
    assert core.eval(f"{PROFILE}.skinFrames") is True  # the frames follow the skin
    seen = list(core.eval("seen").values())
    assert len(seen) >= 1  # every app draws again
    set_option(core, "skin", "'modern'")
    assert core.eval("(W.title:GetFont())") == font
    assert core.eval(f"{PROFILE}.skinFrames") is False
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
    assert core.eval(f"{S}.Azeroth()") is False  # the skin did not change
    set_option(core, "skinFrames", "true")
    assert core.eval("W.border:IsShown()") is True
    assert core.errors == []


def test_azeroth_section_titles_keep_their_case_over_an_ornament(app: WowRuntime):
    host(app)
    app.execute(TABLES)
    app.execute("dossier:SetSubject('npc:448')")
    bf = block(app, "LOOT")
    assert bf.line.IsShown(bf.line) is True and bf.orn.IsShown(bf.orn) is False
    set_option(app, "skin", "'azeroth'")
    app.execute("dossier:Refresh()")
    bf = block(app, "Loot")
    assert bf is not None and bf.orn.IsShown(bf.orn) is True and bf.line.IsShown(bf.line) is False
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


def test_places_show_as_cuts_of_the_map(app: WowRuntime):
    host(app)
    app.execute(TABLES)
    app.execute("dossier:SetSubject('npc:448')")
    where = block(app, "WHERE")
    assert where.mode == "places"
    shown = cells(where)
    assert [c.caption.GetText(c.caption) for c in shown] == [
        "Elwynn Forest  27, 20",
        "Nowhere  10, 10",
    ]
    elwynn, nowhere = shown
    assert elwynn.pin.IsShown(elwynn.pin) is True
    assert any(t.IsShown(t) for t in elwynn.art.values())  # the painting's tiles
    assert nowhere.pin.IsShown(nowhere.pin) is False  # a map without art: the caption only
    assert where.GetHeight(where) > 80  # a cut is taller than a row
    set_option(app, "placeCuts", "false")
    app.execute("dossier:Refresh()")
    where = block(app, "WHERE")
    assert where.mode is None and cells(where) == []
    assert app.errors == []


def test_npc_rows_show_the_creatures_face(core: WowRuntime):
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


def test_the_blizzard_skin_takes_the_frames_the_gold_scheme_and_the_games_type(core: WowRuntime):
    """ "a style that closely reflects Blizzard style across the whole suite": the
    third skin sets the frames, the Blizzard gold scheme and Friz Quadrata (all free to change
    after), headings in the kit's type in gold, and dresses every kit button in the game's own
    button textures; Modern takes the textures off again."""
    core.execute(
        "W = Bastians.UI.Window('BlizzTestFrame', { title = 'T' }); W:Show() "
        "Btn = Bastians.UI.Style.button(W.content, 'Go', 80, 20)"
    )
    assert core.eval("Btn:GetNormalTexture()") in (None, "")
    set_option(core, "skin", "'blizzard'")
    profile = core.eval(PROFILE)
    assert profile.skin == "blizzard" and profile.skinFrames is True
    assert profile.theme == "blizzard" and profile.font == "Fonts\\FRIZQT__.TTF"
    assert core.eval(f"{S}.ThemeId()") == "blizzard"
    assert core.eval("(W.title:GetFont())") == "Fonts\\FRIZQT__.TTF"  # the kit's type, not Morpheus
    assert core.eval("{ W.title:GetTextColor() }")[1] == core.eval(f"{S}.C.gold[1]")
    assert core.eval("W.border:IsShown()") is True
    assert core.eval("W.frame.bg:IsShown()") is False  # the game's dialog ground under the border
    assert core.eval("Btn:GetNormalTexture()") == "Interface\\Buttons\\UI-Panel-Button-Up"
    assert core.eval("Btn.face:IsShown()") is False
    # a button made under the skin is dressed at once
    core.execute("Btn2 = Bastians.UI.Style.button(W.content, 'Go', 80, 20)")
    assert core.eval("Btn2:GetNormalTexture()") == "Interface\\Buttons\\UI-Panel-Button-Up"
    set_option(core, "skin", "'modern'")
    assert core.eval("Btn:GetNormalTexture()") == "" and core.eval("Btn.face:IsShown()") is True
    assert core.eval(f"{PROFILE}.skinFrames") is False
    assert core.eval(f"{PROFILE}.theme") == "blizzard"  # the scheme stays the player's choice
    # the two buttons do the same as the select: the one-click WoW look is the full set
    core.execute("Bastians.UI.Settings.ChooseSkin(Bastians:GetModule('Core'), 'blizzard')")
    assert core.eval(f"{PROFILE}.skin") == "blizzard" and core.eval(f"{PROFILE}.skinFrames") is True
    assert core.eval("W.frame.bg:IsShown()") is False
    core.execute("Bastians.UI.Settings.ChooseSkin(Bastians:GetModule('Core'), 'modern')")
    assert core.eval(f"{PROFILE}.skin") == "modern" and core.eval("W.frame.bg:IsShown()") is True
    assert core.errors == []
