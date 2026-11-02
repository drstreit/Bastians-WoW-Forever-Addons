"""The minimap search: the minimap's box
finds only what the minimap shows (NPCs, quests, zones and subzones, the player's notes and
bookmarks, no items), a quest jumps to its giver and marks it, the mark goes on its own, a quest
without a giver place says so; the big map's box is unchanged."""

from harness import WowRuntime

CORE, DATA, QUESTS, MAP, NOTES = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Map",
    "Bastians_Notes",
)
MOD = "Bastians:GetModule('Map')"
MINI = f"{MOD}.Mini"
MM = f"{MOD}.Minimap"
BOX = f"{MINI}.search"
MAP_SEARCH = f"{MOD}.Search"


def boot(wow: WowRuntime, *extra: str) -> WowRuntime:
    wow.start(CORE, DATA, QUESTS, MAP, *extra)  # Quests brings the quests' places
    wow.fire("PLAYER_ENTERING_WORLD")
    wow.run_frames(5)
    return wow


def our_style(wow: WowRuntime) -> None:
    wow.execute(f"{MOD}.db.profile.miniWarned = true; {MINI}.SetStyle('physical')")


def search(wow: WowRuntime, text: str, box: str = BOX) -> list:
    wow.execute(f"{box}.box:SetText([[{text}]])")
    wow.run_frames(20)
    return [r.ref for r in wow.eval(f"{box}.results").values()]


def rows(wow: WowRuntime, box: str = BOX) -> list[str]:
    out = []
    for r in wow.eval(f"{{ {box}.list:GetChildren() }}").values():
        if r.IsShown(r) and r.label is not None:
            out.append(r.label.GetText(r.label))
    return out


def click(wow: WowRuntime, label: str, box: str = BOX) -> None:
    """Clicks the shown row whose text starts with `label`."""
    wow.execute(
        f"""for _, r in ipairs({{ {box}.list:GetChildren() }}) do
          if r:IsShown() and r.label and r.label:GetText():find([[{label}]], 1, true) == 1 then
            r:Click()
            return
          end
        end"""
    )


def giver(wow: WowRuntime, ref: str) -> tuple:
    places = wow.eval(f"Bastians:Entity('{ref}'):AllPlaces()").values()
    p = next(p for p in places if p.kind == "giver" and p.wx is not None)
    return (p.map, p.wx, p.wy)


def mark(wow: WowRuntime):
    return wow.eval(f"{MM}.Mark()")


def test_the_minimap_offers_what_it_shows_and_the_map_everything(wow: WowRuntime):
    boot(wow)
    # an item is not offered on the minimap: "linen" finds only Linen Cloth there
    assert "item:2589" not in search(wow, "linen")
    assert any("No matches." in t for t in rows(wow))
    # a type word the minimap cannot show: one line instead of results
    assert search(wow, "item linen") == []
    assert any("The minimap finds NPCs, quests, zones and your notes." in t for t in rows(wow))
    # NPCs, quests, zones, subzones are; items, flight paths, objects and rows without a place not
    kinds = set()
    for text in ("an", "el", "in", "er", "or"):
        kinds |= {ref.split(":")[0] for ref in search(wow, text)}
    assert kinds <= {"npc", "quest", "zone", "area"}
    assert "zone:1429" in search(wow, "elwynn")
    assert "area:18" in search(wow, "crystal")
    assert "npc:240" in search(wow, "dughan")
    assert "quest:62" in search(wow, "fargodeep")
    assert "object:1734" not in search(wow, "wanted poster")
    hog = search(wow, "hog")
    assert "npc:448" in hog and "quest:176" in hog and None not in hog  # no "Load quest texts"
    # the big map's box still finds everything
    wow.slash("/bmap")
    assert "item:2589" in search(wow, "linen", MAP_SEARCH)
    assert None in search(wow, "hog", MAP_SEARCH)  # Quests' "Load quest texts" row stays there
    assert wow.errors == []


def test_a_quest_jumps_to_its_giver_and_marks_it(wow: WowRuntime):
    boot(wow)
    our_style(wow)
    place = giver(wow, "quest:176")
    assert search(wow, "quest hog") == ["quest:176"]
    click(wow, 'Wanted: "Hogger"')
    cam = wow.eval(f"{MINI}.Camera()")
    assert (cam.continent, cam.wx, cam.wy) == place  # the giver, not the targets or the hand-in
    m = mark(wow)
    assert (m.ref, m.continent, m.wx, m.wy) == ("quest:176", *place)
    # drawn on our view: the overlay's first pin, on its disc, above the layers' pins
    pins = list(wow.eval(f"{MM}.Pins()").values())
    assert pins[0].isMark is True and (pins[0].wx, pins[0].wy) == place[1:]
    f = wow.eval(f"{MM}.pool[1]")
    assert f.IsShown(f) is True and f.ring.IsShown(f.ring) is True
    assert f.GetWidth(f) == wow.eval(f"{MM}.MARK_SIZE")
    assert wow.eval(f"{MM}.Host() == {MINI}.host") is True
    # no double of the marked entity on the same spot
    same = [p for p in pins[1:] if p.ref == "quest:176" and (p.wx, p.wy) == place[1:]]
    assert same == []
    assert wow.errors == []


def test_on_the_game_minimap_the_mark_is_drawn_and_the_big_map_shows_the_giver(wow: WowRuntime):
    boot(wow)
    place = giver(wow, "quest:176")
    assert wow.eval(f"{MINI}.Style()") == "game"
    assert wow.eval(f"{MINI}.JumpTo('quest:176')") is True
    m = mark(wow)
    assert (m.continent, m.wx, m.wy) == place
    assert wow.eval(f"{MM}.Host()") is None
    assert wow.eval(f"{MM}.Pins()[1].isMark") is True
    # the big map opened on the giver, its shown entity there (map.show with the point)
    assert wow.eval("BastiansMapFrame and BastiansMapFrame:IsShown()") is True
    shown = wow.eval(f"{MOD}.Waypoints.Shown()")
    assert shown.ref == "quest:176"
    point = shown.points[1]
    assert (point.wx, point.wy) == place[1:]
    assert wow.errors == []


def test_the_mark_goes_on_its_own(wow: WowRuntime):
    boot(wow)
    our_style(wow)
    # a new search clears it
    assert wow.eval(f"{MINI}.JumpTo('npc:448')") is True
    assert mark(wow) is not None
    search(wow, "hog")
    assert mark(wow) is None
    # Esc in the box clears it
    wow.execute(f"{MINI}.JumpTo('npc:448')")
    wow.execute(f"{BOX}.box:GetScript('OnEscapePressed')({BOX}.box)")
    assert mark(wow) is None
    # the timeout clears it, and the pin goes with it
    wow.execute(f"{MINI}.JumpTo('npc:448')")
    wow.advance(wow.eval(f"{MINI}.MARK_SECONDS") - 1)
    assert mark(wow) is not None
    wow.advance(2)
    assert mark(wow) is None
    assert all(p.isMark is not True for p in wow.eval(f"{MM}.Pins()").values())
    # a zone has no mark: the zone is the place
    wow.execute(f"{MINI}.JumpTo('npc:448'); {MINI}.JumpTo('zone:1429')")
    assert mark(wow) is None
    # the minimap switched off clears it
    wow.execute(f"{MINI}.JumpTo('npc:448')")
    wow.execute(
        f"{MOD}.db.profile.miniMap = false; "
        f"Bastians:Fire('BASTIANS_SETTING_CHANGED', {MOD}.name, 'miniMap', false)"
    )
    assert mark(wow) is None
    assert wow.errors == []


def test_a_quest_without_a_giver_place_says_so_and_stays(wow: WowRuntime):
    boot(wow)
    our_style(wow)
    before = wow.eval(f"{MINI}.Camera()")
    at = (before.continent, before.wx, before.wy)
    said = len(wow.chat)
    assert wow.eval(f"{MINI}.JumpTo('quest:11')") is False  # Riverpaw Gnoll Bounty: no giver place
    lines = wow.chat[said:]
    assert (
        len(lines) == 1
        and "No known place of the quest giver for Riverpaw Gnoll Bounty." in lines[0]
    )
    cam = wow.eval(f"{MINI}.Camera()")
    assert (cam.continent, cam.wx, cam.wy) == at
    assert wow.eval(f"{MINI}.Following()") is True
    assert mark(wow) is None
    assert wow.errors == []


def test_the_mark_shows_with_the_minimap_layers_off(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"{MOD}.db.profile.minimapPins = false; "
        f"Bastians:Fire('BASTIANS_SETTING_CHANGED', {MOD}.name, 'minimapPins', false)"
    )
    assert wow.eval("BastiansMinimapOverlay == nil or not BastiansMinimapOverlay:IsShown()") is True
    assert wow.eval(f"{MINI}.JumpTo('npc:448')") is True
    pins = list(wow.eval(f"{MM}.Pins()").values())
    assert len(pins) == 1 and pins[0].isMark is True and pins[0].ref == "npc:448"
    assert wow.eval("BastiansMinimapOverlay:IsShown()") is True
    wow.execute(f"{MINI}.ClearMark()")
    assert wow.eval("BastiansMinimapOverlay:IsShown()") is False
    assert list(wow.eval(f"{MM}.Pins()").values()) == []
    assert wow.errors == []


def test_notes_on_a_spot_and_bookmarks_are_found_and_marked(wow: WowRuntime):
    boot(wow, NOTES)
    our_style(wow)
    notes = "Bastians:GetModule('Notes').Notes"
    wow.execute(
        f"""{notes}.Save({{ on = {{ map = 0, wx = -9300, wy = 300 }}, title = 'Peacebloom patch' }})
        {notes}.Save({{ on = 'item:2589', title = 'Peacebloom for linen' }})
        Bastians:GetService('notes'):AddBookmark({{ name = 'Peaceful camp', continent = 0,
          wx = -9100, wy = 500, level = 4 }})"""
    )
    search(wow, "peace")
    texts = rows(wow)
    assert any(t.startswith("Peacebloom patch") and "Note" in t for t in texts)
    assert any(t.startswith("Peaceful camp") and "Bookmark" in t for t in texts)
    assert not any(t.startswith("Peacebloom for linen") for t in texts)  # a note on an item
    click(wow, "Peacebloom patch")
    cam = wow.eval(f"{MINI}.Camera()")
    assert (cam.continent, cam.wx, cam.wy) == (0, -9300, 300)
    m = mark(wow)
    assert (m.continent, m.wx, m.wy, m.label) == (0, -9300, 300, "Peacebloom patch")
    search(wow, "peaceful")
    click(wow, "Peaceful camp")
    m = mark(wow)
    assert (m.continent, m.wx, m.wy) == (0, -9100, 500)
    assert wow.errors == []
