"""Dungeons (data.md "Dungeons"): the fixture World pack's Deadmines is an entity found by the search,
its page lists the bosses and the loot, its place is its door, a boss and a dungeon quest link back,
and Quests lists the dungeon's quests under the status headers."""

import re

from harness import WowRuntime

CORE, DATA, QUESTS = "Bastians_Core", "Bastians_Data", "Bastians_Quests"


def boot(wow: WowRuntime, *extra: str) -> WowRuntime:
    wow.start(CORE, DATA, *extra)
    wow.run_frames(10)
    wow.execute('Bastians:GetService("data"):LoadPack("world")')
    wow.execute('Bastians:GetService("data"):LoadPack("quests")')
    wow.execute('Bastians:GetService("data"):LoadPack("items")')
    wow.run_frames(5)
    return wow


def strip(text: str) -> str:
    return re.sub(r"\|T[^|]*\|t ?", "", text)


def search(wow: WowRuntime, text: str) -> list:
    wow.execute(
        f"_G.got = nil local q, types = Bastians.ParseSearch('{text}') "
        "Bastians:Search(q, { limit = 10, types = types }, function(r, done) "
        "if done then _G.got = r end end)"
    )
    wow.run_frames(10)
    return list(wow.eval("got").values())


def sections(wow: WowRuntime, ref: str) -> dict:
    return {s.id: s for s in wow.eval(f"Bastians:GetDetailSections('{ref}')").values()}


def test_the_dungeon_is_an_entity_the_search_finds(wow: WowRuntime):
    boot(wow)
    hits = [r for r in search(wow, "deadmines") if r.ref == "dungeon:36"]
    assert hits and hits[0].label == "The Deadmines"
    # "dungeon" and "raid" before or after the words keep the dungeons only
    assert [r.ref for r in search(wow, "dungeon dead")] == ["dungeon:36"]
    assert [r.ref for r in search(wow, "dead raid")] == ["dungeon:36"]
    assert wow.eval("Bastians:Entity('dungeon:36'):Name()") == "The Deadmines"
    assert (
        wow.eval("Bastians:Entity('dungeon:36'):Summary()")
        == "Dungeon, Level 15-25, 5 players, Westfall"
    )
    assert wow.errors == []


def test_the_dungeon_page_lists_bosses_in_order_and_the_loot_by_boss(wow: WowRuntime):
    boot(wow)
    page = sections(wow, "dungeon:36")
    bosses = list(page["data.bosses"].rows.values())
    assert [(r.ref, strip(r.text), r.value) for r in bosses] == [
        ("npc:644", "Rhahk'Zor", 1),
        ("npc:639", "Edwin VanCleef", 2),
    ]
    loot = list(page["data.dungeonloot"].rows.values())
    assert [(r.ref, strip(r.text), r.note) for r in loot] == [
        ("item:1185", "Blood Saber", "Rhahk'Zor"),
        ("item:2589", "Linen Cloth", None),  # the instance's loot without a boss named
    ]
    # Quests' section: the dungeon's quests, by status, with the game's status words
    assert "quests.dungeon" not in page  # Quests is not loaded here
    assert wow.errors == []


def test_the_dungeon_stands_at_its_door_and_the_door_the_boss_and_the_quest_link_back(
    wow: WowRuntime,
):
    boot(wow)
    places = list(wow.eval("Bastians:Entity('dungeon:36'):Locations()").values())
    door = list(wow.eval("Bastians:Entity('entrance:36-1'):Locations()").values())
    assert places and [(p.map, p.x, p.y) for p in places] == [(p.map, p.x, p.y) for p in door]
    for ref in ("npc:644", "entrance:36-1", "quest:62"):
        rows = list(sections(wow, ref)["data.dungeon"].rows.values())
        assert [(r.ref, strip(r.text)) for r in rows] == [("dungeon:36", "The Deadmines")], ref
    # an NPC outside any dungeon has no such section
    assert "data.dungeon" not in sections(wow, "npc:448")
    # a boss's loot seen in Forever has no chance: the note stays empty, never "0%"
    boss_loot = list(sections(wow, "npc:644")["data.loot"].rows.values())
    assert [(r.ref, r.note, r.chance) for r in boss_loot] == [("item:1185", None, None)]
    assert wow.errors == []


def test_quests_lists_the_dungeons_quests(wow: WowRuntime):
    boot(wow, QUESTS)
    rows = list(sections(wow, "dungeon:36")["quests.dungeon"].rows.values())
    # grouped: a status header row with the quests it holds as its children
    assert [r.kind for r in rows] == ["section"]
    assert [c.ref for c in rows[0].children.values()] == ["quest:62"]
    # the dungeon's attunement as a progress chain (DG2b): the list whose instance is the dungeon
    att = [
        re.sub(r"\|c[0-9a-fA-F]{8}", "", strip(r.text)).replace("|r", "")
        for r in sections(wow, "dungeon:36")["quests.attunement"].rows.values()
    ]
    assert att[0] == "Step 1 of 3. Next: The Fargodeep Mine" and att[1].endswith("<- you are here")
    assert len(att) == 4
    assert wow.errors == []


def test_the_dungeon_page_has_its_floors_with_the_boss_pins_and_the_door(wow: WowRuntime):
    """DG2c: one row
    per floor with the client's map (retail's UiMap id, the art files' prefix and grid for the
    Forever client), the bosses of that floor by number, name and ref, the door; a floor without
    any map says so when drawn. The dossier draws the rows as plates (Scenery mode "floors")."""
    boot(wow)
    rows = list(sections(wow, "dungeon:36")["data.floors"].rows.values())
    assert [r.text for r in rows] == ["The Deadmines 1", "The Deadmines 2"]
    one = rows[0].floor
    assert (one.w, one.h, one.uiMap, one.art, one.cols, one.rows) == (
        1002,
        668,
        291,
        "interface/worldmap/thedeadmines/thedeadmines1_",
        4,
        3,
    )
    assert one.tiles is None and one.dungeon == "The Deadmines"
    bosses = [list(b.values()) for b in one.bosses.values()]
    assert bosses == [[1, 38.59, 60.88, "Rhahk'Zor", "npc:644"]]
    assert one.door is None and one.note is None  # every boss has its floor
    two = rows[1].floor
    assert (two.uiMap, two.art) == (292, None)
    assert [list(b.values()) for b in two.bosses.values()] == [
        [2, 50.0, 50.0, "Edwin VanCleef", "npc:639"]
    ]
    assert list(two.door.values()) == [60.22, 84.32]
    # the block is drawn as floor plates: the dossier asks Scenery for the block's mode
    mode = wow.eval(
        "(function() for _, s in ipairs(Bastians:GetDetailSections('dungeon:36')) do "
        "if s.id == 'data.floors' then return Bastians.UI.Scenery.BlockMode(s) end end end)()"
    )
    assert mode == "floors"
    assert wow.errors == []


def test_a_floor_plate_draws_the_art_files_its_pins_open_the_boss_and_a_click_enlarges(
    wow: WowRuntime,
):
    """DG2c: without retail's UiMap art (the mock, the Forever client) the plate lays the art
    files' 4 x 3 tiles by name; a boss pin is a button that reports the boss to the dossier
    (its ref), a click on the plate opens the floor enlarged in the suite's floor window with
    the dungeon's floors as tabs."""
    boot(wow)
    wow.execute(
        """local rows = {}
        for _, s in ipairs(Bastians:GetDetailSections('dungeon:36')) do
          if s.id == 'data.floors' then for _, r in ipairs(s.rows) do rows[#rows + 1] = r end end
        end
        FloorRows = rows
        Clicks = {}
        Host = { opts = {}, RowClick = function(_, row, button) Clicks[#Clicks + 1] = { row.ref, button } end }
        BF = CreateFrame('Frame', nil, UIParent)
        Bastians.UI.Scenery.RenderCells(BF, 'floors', rows, 501, 0, Host)"""
    )
    assert wow.eval("#BF.cells") == 2
    assert (
        wow.eval("BF.cells[1].art[1]:GetTexture()")
        == "interface/worldmap/thedeadmines/thedeadmines1_1"
    )
    assert (
        wow.eval("BF.cells[1].art[12]:GetTexture()")
        == "interface/worldmap/thedeadmines/thedeadmines1_12"
    )
    assert wow.eval("BF.cells[1].art[12]:IsShown()") is True
    assert wow.eval("BF.cells[1].art[13]") is None
    assert round(wow.eval("BF.cells[1].cut:GetHeight()")) == 334  # 501 wide, 1002 x 668
    assert wow.eval("BF.cells[1].pins[1].label:GetText()") == "1"
    assert wow.eval("BF.cells[1].pins[1].name") == "Rhahk'Zor"
    wow.execute("BF.cells[1].pins[1]:Click('LeftButton')")
    assert [list(c.values()) for c in wow.eval("Clicks").values()] == [["npc:644", "LeftButton"]]
    # the second floor: no art file names, no retail art on the mock: the bare plate says so
    assert "(the client has no map of this floor)" in wow.eval("BF.cells[2].caption:GetText()")
    assert wow.eval("BF.cells[2].pins[2].name") is None  # the door: no tooltip, no click
    # the plate enlarges
    wow.execute("BF.cells[2]:Click('LeftButton')")
    assert wow.eval("Bastians.UI.Scenery.FloorWindow():IsShown()") is True
    assert wow.eval("BastiansFloorFrame:GetName()") == "BastiansFloorFrame"
    title = wow.eval("Bastians.UI.Scenery.FloorWindow().title:GetText()")
    assert title == "The Deadmines: The Deadmines 2"
    wow.execute("Bastians.UI.Scenery.FloorWindow():Hide()")
    assert wow.errors == []


def test_a_hand_drawn_floor_credits_its_artist_under_the_plate_and_in_the_window(
    wow: WowRuntime,
):
    """ADR 0048 ("clearly state this with a thank you, directly under the
    maps, with a link to his site"): a floor drawn by an artist (`by`) names the artist in the
    plate's caption; the enlarged floor thanks the artist and holds the address in a box to copy,
    which undoes a change; a floor of the client shows neither."""
    boot(wow)
    wow.execute(
        """local rows = {}
        for _, s in ipairs(Bastians:GetDetailSections('dungeon:36')) do
          if s.id == 'data.floors' then for _, r in ipairs(s.rows) do rows[#rows + 1] = r end end
        end
        rows[1].floor.by = 'santiago'
        Host = { opts = {}, RowClick = function() end }
        BF = CreateFrame('Frame', nil, UIParent)
        Bastians.UI.Scenery.RenderCells(BF, 'floors', rows, 501, 0, Host)"""
    )
    assert wow.eval("BF.cells[1].caption:GetText()") == "The Deadmines 1  -  Map by Santiago Reyes"
    assert "Map by" not in wow.eval("BF.cells[2].caption:GetText()")
    wow.execute("BF.cells[1]:Click('LeftButton')")
    win = "Bastians.UI.Scenery.FloorWindow()"
    assert wow.eval(f"{win}:IsShown()") is True
    assert wow.eval(f"{win}.credit:IsShown()") is True
    assert wow.eval(f"{win}.credit:GetText()") == (
        "Map by Santiago Reyes (Atlas of Azeroth: Forever), used with kind permission. Thank you!"
    )
    assert wow.eval(f"{win}.link:IsShown()") is True
    assert wow.eval(f"{win}.link:GetText()") == "https://www.artstation.com/sr433_20"
    # the floor tabs carry their names,
    # and the title names the dungeon once when the floor is named after it
    tabs = [strip(t.label.GetText(t.label)) for t in wow.eval(f"{win}.floor.tabs").values()]
    assert tabs[:2] == ["The Deadmines 1", "The Deadmines 2"]
    assert wow.eval(f"{win}.title:GetText()") == "The Deadmines: The Deadmines 1"
    wow.execute(
        f"local r = {win}.floor.rows[1]; r.text = r.floor.dungeon; "
        f"Bastians.UI.Scenery.OpenFloor({win}.floor.rows, 1, Host)"
    )
    assert wow.eval(f"{win}.title:GetText()") == "The Deadmines"
    wow.execute(f"{win}.floor.rows[1].text = 'The Deadmines 1'")
    # the address stays what it is
    wow.execute(f"local b = {win}.link; b:SetText('x'); b:GetScript('OnTextChanged')(b, true)")
    assert wow.eval(f"{win}.link:GetText()") == "https://www.artstation.com/sr433_20"
    # the client's own floor: no credit
    wow.execute("Bastians.UI.Scenery.OpenFloor(BF.cells[1].floorRows, 2, Host)")
    assert wow.eval(f"{win}.credit:IsShown()") is False
    assert wow.eval(f"{win}.link:IsShown()") is False
    wow.execute(f"{win}:Hide()")
    assert wow.errors == []


def test_a_boss_without_a_known_creature_is_its_name_alone(wow: WowRuntime):
    """02.11.2026: ForeverDB's boss numbers are encounter ids; a boss whose creature nothing names
    comes without one (`{order, nil, name}`): the page lists it by name without a link, its loot
    note and its pin say its name, and nothing errors."""
    boot(wow)
    wow.execute(
        """local pack = Bastians.Data.packs.world
        local raw = pack.dungeon[36]
        pack.dungeon[36] = raw:gsub('{ 2, 639, "Edwin VanCleef" }',
          '{ 2, 639, "Edwin VanCleef" }, { 3, nil, "Mr. Smite" }')
        assert(pack.dungeon[36] ~= raw, 'the fixture row changed shape')"""
    )
    rows = list(sections(wow, "dungeon:36")["data.bosses"].rows.values())
    smite = rows[-1]
    assert (smite.text, smite.ref, smite.value) == ("Mr. Smite", None, 3)
    assert rows[0].ref == "npc:644"
    assert wow.errors == []


def test_a_cell_that_drew_a_floor_is_a_place_cell_again(wow: WowRuntime):
    """a screenshot: after a dungeon's page an object's Locations
    showed a huge plate with the boss pins 1 to 5 and the door, and it stayed. A block's cells
    are pooled: a cell that drew a floor keeps nothing of it as a place (its plate's size, its
    pins, its click). A click on a place opens the map at that place; the "+N more" cell shows
    its words above its plate."""
    boot(wow)
    wow.execute(
        """local rows = {}
        for _, s in ipairs(Bastians:GetDetailSections('dungeon:36')) do
          if s.id == 'data.floors' then for _, r in ipairs(s.rows) do rows[#rows + 1] = r end end
        end
        Clicks, Shown = {}, {}
        Host = { opts = {}, RowClick = function(_, row, button) Clicks[#Clicks + 1] = { row.kind or row.ref, button } end }
        BF = CreateFrame('Frame', nil, UIParent)
        local Scenery = Bastians.UI.Scenery
        Scenery.RenderCells(BF, 'floors', rows, 501, 0, Host)
        Places = {
          { text = 'Elwynn Forest  42, 69', ref = 'object:1', place = { map = 1429, x = 0.42, y = 0.69 } },
          { text = '+5 more', kind = 'more', onClick = function() end },
        }
        Scenery.RenderCells(BF, 'places', Places, 501, 0, Host)
        Cell = BF.cells[1]"""
    )
    assert wow.eval("Cell.pins[1]:IsShown()") is False  # the boss pins are gone
    assert wow.eval("Cell.floorRows") is None
    assert round(wow.eval("Cell.cut:GetWidth()")) == wow.eval("Bastians.UI.Scenery.CUT_W")
    assert round(wow.eval("Cell.cut:GetHeight()")) == wow.eval("Bastians.UI.Scenery.CUT_H")
    # a click on the mini map: the map at that place, not the floor window, not the page again
    wow.execute(
        """Bastians:RegisterAction(Bastians:GetModule('Data'), { id = 'map.show', label = 'Show on map',
          types = '*', run = function(ref, ctx) Shown[#Shown + 1] = { ref, ctx.points[1].map, ctx.points[1].x } end })
        Cell:Click('LeftButton')"""
    )
    assert [list(s.values()) for s in wow.eval("Shown").values()] == [["object:1", 1429, 0.42]]
    win = wow.eval("Bastians.UI.Scenery.FloorWindow()")
    assert win is None or win.IsShown(win) is False
    # the right button is the host's, as on every row
    wow.execute("Cell:Click('RightButton')")
    assert [list(c.values()) for c in wow.eval("Clicks").values()] == [["object:1", "RightButton"]]
    # "+5 more": its words stand on a frame above the plate, and its click is the host's
    assert wow.eval("BF.cells[2].caption:GetText()") == "+5 more"
    assert wow.eval("BF.cells[2].caption:GetParent() == BF.cells[2].over") is True
    assert wow.eval("BF.cells[2].over:GetFrameLevel() > BF.cells[2].cut:GetFrameLevel()") is True
    wow.execute("BF.cells[2]:Click('LeftButton')")
    assert list(wow.eval("Clicks[2]").values()) == ["more", "LeftButton"]
    assert wow.errors == []
