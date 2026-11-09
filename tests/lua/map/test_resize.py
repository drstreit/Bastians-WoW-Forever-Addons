"""Owner feedback of 21.10.2026 evening (map.md "second round"): a resize in progress only moves
what is live and draws the overview, the layer queries run once after the last event; the Full
button; pins with a radius as soft discs; dashed approximate path legs; `/bmap stats`."""

from pathlib import Path

from harness import WowRuntime

CORE, DATA, QUESTS, MAP = "Bastians_Core", "Bastians_Data", "Bastians_Quests", "Bastians_Map"
MOD = "Bastians:GetModule('Map')"
MAP_ = f"{MOD}.Map"
TILES = f"{MOD}.Tiles"
PINS = f"{MOD}.Pins"
OVERVIEW = f"{MOD}.Overview"
IMAGERY = f"{MOD}.Imagery"
FIXTURES = Path(__file__).resolve().parents[2] / "fixtures" / "mapart"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA, QUESTS, MAP)
    wow.run_frames(10)
    for golden in (FIXTURES / "MinimapTiles.lua", FIXTURES / "overview" / "Overview.lua"):
        wow.execute(
            golden.read_text(encoding="utf-8").replace(
                'client = "forever"', f'client = "{wow.client}"'
            )
        )
    wow.execute("Bastians.Deliver()")
    wow.execute(
        """
        queries = 0
        local m = Bastians:NewModule("CountLayer", { addon = "Bastians_Map" })
        Bastians:RegisterMapLayer(m, { id = "test.count", label = "Count", defaultOn = true,
          minLevel = 0, query = function() queries = queries + 1; return {} end })
        """
    )
    wow.slash("/bmap")
    wow.execute(f"{MAP_}.clip:SetSize(600, 400); {MAP_}.ViewChanged()")
    wow.advance(0.2)
    return wow


def point(region) -> tuple:
    p = region.GetPoint(region)
    return (round(p[3], 1), round(p[4], 1))


def screen(wow: WowRuntime, wx: float, wy: float) -> tuple:
    """Where the camera puts a world point, as SetPoint offsets (the y offset points up)."""
    sx, sy = wow.eval(f"{MAP_}.Camera():ToScreen({wx}, {wy})")
    return (round(sx, 1), round(-sy, 1))


def live_count(wow: WowRuntime) -> int:
    return len(list(wow.eval(f"{TILES}.live").values()))


def test_a_resize_in_progress_moves_the_live_textures_and_queries_once_at_the_end(
    wow: WowRuntime,
):
    boot(wow)
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 6)")  # 2 px per yard, four tiles meet at the view's centre
    wow.advance(0.2)
    queries = wow.eval("queries")
    assert wow.eval(f"{TILES}.stats.shown") == 5 and wow.eval(f"{PINS}.stats.pins") >= 2
    wow.execute(f"{TILES}.live[{32 * 64 + 32}].mark = 'kept'; {IMAGERY}.pool[1].mark = 'kept'")
    tile_before = point(wow.eval(f"{TILES}.live[{32 * 64 + 32}]"))
    art_before = point(wow.eval(f"{IMAGERY}.pool[1]"))
    marshal = next(
        f for f in wow.eval(f"{PINS}.pinPool").values() if f.IsShown(f) and f.pin.ref == "npc:240"
    )
    pin_before = point(marshal)
    assert tile_before == (300.0, -200.0)
    # the grip is held: the window grows, the Map hears sizing = true
    wow.execute(f"{MAP_}.clip:SetSize(800, 500); {MAP_}.win.sizing = true")
    wow.execute(f"{MAP_}.win.opts.onResize({MAP_}.win, true)")
    wow.advance(0.3)
    assert wow.eval("queries") == queries  # no layer query while sizing
    assert wow.eval(f"{MAP_}.Camera().width") == 800
    kept = wow.eval(f"{TILES}.live[{32 * 64 + 32}]")
    assert kept.mark == "kept" and point(kept) == (400.0, -250.0)  # moved with the centre
    assert live_count(wow) == 5  # nothing loaded: the new edge waits for the end
    art = wow.eval(f"{IMAGERY}.pool[1]")
    # the zone paintings under the overview cells are no longer drawn (
    # the Feralas stripe); a painting that is drawn moves with the centre
    if wow.eval(f"{IMAGERY}.stats.textures") > 0 and art.IsShown(art):
        assert art.mark == "kept" and point(art) != art_before
    assert point(marshal) != pin_before and point(marshal) == screen(wow, marshal.wx, marshal.wy)
    assert wow.eval(f"{OVERVIEW}.stats.shown") >= 1  # the overview is drawn in full
    # the mouse goes up: one full draw (Reposition never touches the stats, Render does) and one query
    wow.execute(f"{TILES}.stats.wanted = 0")
    wow.execute(f"{MAP_}.win.sizing = nil; {MAP_}.win.opts.onResize({MAP_}.win, false)")
    assert wow.eval(f"{TILES}.stats.wanted") == 5 and live_count(wow) == 5
    wow.advance(0.2)
    assert wow.eval("queries") == queries + 1
    assert wow.errors == []


def test_the_full_button_fills_the_screen_and_comes_back(wow: WowRuntime):
    boot(wow)
    width = wow.eval(f"{MAP_}.Camera().width")
    assert width == 600 and wow.eval(f"{MAP_}.toolbar.full.label:GetText()") == "Full"
    wow.execute(f"{MAP_}.toolbar.full:Click()")
    assert wow.eval(f"{MAP_}.win:IsFullScreen()") is True
    assert wow.eval(f"{MOD}.db.profile.window.full") is True
    assert wow.eval(f"{MAP_}.toolbar.full.label:GetText()") == "Window"
    assert wow.eval(f"{MAP_}.win.frame:GetWidth()") == 1920
    wow.execute(f"{MAP_}.toolbar.full:Click()")
    assert wow.eval(f"{MAP_}.win:IsFullScreen()") is False
    assert wow.eval(f"{MAP_}.win.frame:GetWidth()") == 760  # the Map's default size
    assert wow.eval(f"{MAP_}.toolbar.full.label:GetText()") == "Full"
    assert wow.errors == []


def test_areas_with_a_radius_are_soft_discs_under_the_pins(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 6)")
    wow.advance(0.2)
    assert wow.eval(f"{PINS}.stats.areas") >= 1
    area = next(a for a in wow.eval(f"{PINS}.areaPool").values() if a.IsShown(a))
    assert area.GetTexture(area) == "Interface\\CharacterFrame\\TempPortraitAlphaMask"
    assert area.blend == "BLEND" and area.GetVertexColor(area)[3] == 0.18
    radius = area.pin.radius * wow.eval(f"{MAP_}.Camera():Scale()")
    assert round(area.GetWidth(area), 2) == round(radius * 2, 2)
    assert point(area) == screen(wow, area.pin.wx, area.pin.wy)
    assert wow.eval(f"{PINS}.AreaRadius({{ radius = 1 }}, {MAP_}.Camera())") is None  # too small
    assert wow.errors == []


def test_dashed_paths_are_many_pieces_that_a_resize_moves(wow: WowRuntime):
    boot(wow)
    wow.execute(
        """
        pathStyle = "dashed"
        local m = Bastians:NewModule("PathLayer", { addon = "Bastians_Map" })
        Bastians:RegisterMapLayer(m, { id = "test.path", label = "Path", defaultOn = true, minLevel = 0,
          query = function()
            return { { kind = "path", style = pathStyle, points = { { 0, 0 }, { 0, 50 } }, color = { 1, 1, 1 } } }
          end })
        """
    )
    wow.execute(f"{PINS}.SetLayerOn('route.path', false)")
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 6)")  # 50 yards = 100 px: 100 / (10 + 7) = 5 dashes
    wow.advance(0.2)
    assert wow.eval(f"{PINS}.stats.lines") == 5
    pieces = [t for t in wow.eval(f"{PINS}.linePool").values() if t.IsShown(t)]
    assert len(pieces) == 5 and all(round(t.GetWidth(t), 1) == 10 for t in pieces)
    assert pieces[0].w1 is not None and round(pieces[-1].w2[2], 1) == 50
    first_before = point(pieces[0])
    # a resize in progress moves the pieces from their world end points
    wow.execute(f"{MAP_}.clip:SetSize(800, 500); {MAP_}.ViewChanged(true)")
    assert point(pieces[0]) != first_before and wow.eval(f"{PINS}.stats.lines") == 5
    # solid stays one piece; a short dashed segment is one piece; a long one is capped
    wow.execute("pathStyle = nil")
    wow.execute(f"{MAP_}.clip:SetSize(600, 400); {MAP_}.ViewChanged()")
    wow.advance(0.2)
    assert wow.eval(f"{PINS}.stats.lines") == 1
    wow.execute("pathStyle = 'dotted'")
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 3)")  # 50 yards = 12.5 px
    wow.advance(0.2)
    assert wow.eval(f"{PINS}.stats.lines") == 1
    wow.execute(f"{MAP_}.Fly(0, 0, 25, 8)")  # 50 yards = 400 px: 23 dashes
    wow.advance(0.2)
    assert wow.eval(f"{PINS}.stats.lines") == 23
    wow.execute(f"{PINS}.MAX_DASHES = 4")
    wow.execute(f"{MAP_}.Pan(1, 0)")
    assert wow.eval(f"{PINS}.stats.lines") == 4
    assert wow.errors == []


def test_bmap_stats_tells_what_the_layers_hold(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 6)")
    wow.advance(0.2)
    before = len(wow.chat)
    wow.slash("/bmap stats")
    lines = wow.chat[before:]
    text = "\n".join(lines)
    assert "zoom 6.0, 600x400 px" in text
    assert "Minimap tiles (Minimap tiles: Eastern Kingdoms 6, Kalimdor 1): shown 5" in text
    assert "2015 (31/31): id 500001 shown=true 1068x1068" in text  # with the overlap
    assert "Overview cells (Overview cells:" in text and "Zone art:" in text and "Pins:" in text
    assert wow.errors == []


def test_a_continent_switch_drops_the_other_continents_textures(wow: WowRuntime):
    """Keys are positions, the same on every continent: Kalimdor's cells stayed on screen over
    Eastern Kingdoms after "Player"."""
    boot(wow)
    wow.execute(
        "Bastians.Map.RegisterOverview({ client = Bastians.Client, span = 8, grid = 8, "
        "path = Bastians:GetModule('Map').Overview.File(0, 3, 5):sub(1, -6), "
        "continents = { [0] = { 29 }, [1] = { 29 } } })"
    )
    x1, y1, x2, y2 = wow.eval(f"{OVERVIEW}.WorldRect(3, 5)")
    wow.execute(f"{MAP_}.Fly(0, {(x1 + x2) / 2}, {(y1 + y2) / 2}, 1)")
    cell = wow.eval(f"{OVERVIEW}.live[29]")
    assert cell.GetTexture(cell) == wow.eval(f"{OVERVIEW}.File(0, 3, 5)")
    wow.execute(f"{MAP_}.Fly(1, {(x1 + x2) / 2}, {(y1 + y2) / 2}, 1)")
    cell = wow.eval(f"{OVERVIEW}.live[29]")
    assert cell.GetTexture(cell) == wow.eval(f"{OVERVIEW}.File(1, 3, 5)")
    assert wow.eval(f"{OVERVIEW}.continent") == 1
    assert wow.errors == []


def test_keep_centred_is_on_by_default_and_follows_the_player(wow: WowRuntime):
    """Centred is the default; R27.9: the player stays in the middle
    while moving and the layers still refresh while walking."""
    wow.start("Bastians_Core", "Bastians_Data", "Bastians_Map")
    wow.run_frames(5)
    wow.slash("/bmap")
    wow.execute(f"{MAP_}.clip:SetSize(600, 400); {MAP_}.ViewChanged()")
    assert wow.eval(f"{MAP_}.KeepCentred()") is True
    assert wow.eval(f"{MAP_}.toolbar.centred.token") == "accent"

    def offset() -> tuple[float, float]:
        cam = wow.eval(f"{MAP_}.Camera()")
        p = wow.eval(f"{MAP_}.PlayerWorld()")
        sx, sy = cam.ToScreen(cam, p[2], p[3])
        return abs(sx - 300), abs(sy - 200)

    wow.run_frames(1)
    assert max(offset()) < 1
    # walking: each frame the camera follows
    wow.execute("Mock.playerMapPos = { x = 0.45, y = 0.62 }")
    wow.run_frames(1)
    assert max(offset()) < 1
    # the layers are queried at least once a second while the view never stands still
    wow.execute(f"Q = 0; table.insert({MAP_}.onSettle, function() Q = Q + 1 end)")
    for i in range(30):
        wow.execute(f"Mock.playerMapPos = {{ x = 0.45 + {i} * 0.001, y = 0.62 }}")
        wow.run_frames(1, 0.05)
    assert wow.eval("Q") >= 1
    assert wow.errors == []


def test_looking_around_rests_centred_until_the_map_closes(wow: WowRuntime):
    """ "only if the player disables it it stays that way, currently it
    switches off all the time". A drag, another continent or a place flown to rest it for this
    opening (R27.9, R28.7: the view must stay where the player sent it); the next open follows."""
    wow.start("Bastians_Core", "Bastians_Data", "Bastians_Map")
    wow.run_frames(5)
    wow.slash("/bmap")
    wow.execute(f"{MAP_}.clip:SetSize(600, 400); {MAP_}.ViewChanged()")
    wow.run_frames(1)

    def press(x: int, y: int) -> None:
        wow.execute(
            f"Mock.cursorX, Mock.cursorY = {x}, {y}; "
            f"{MAP_}.clip:GetScript('OnMouseDown')({MAP_}.clip, 'LeftButton')"
        )

    def release() -> None:
        wow.execute(f"{MAP_}.clip:GetScript('OnMouseUp')({MAP_}.clip, 'LeftButton')")

    # a click's wobble is not looking around
    press(300, 200)
    wow.execute("Mock.cursorX = 302")
    wow.run_frames(1)
    release()
    assert wow.eval(f"{MAP_}.KeepCentred()") is True
    # a drag is: the map rests, the choice stays, and the view stays where it was dragged to
    press(300, 200)
    wow.execute("Mock.cursorX = 340")
    wow.run_frames(1)
    release()
    assert wow.eval(f"{MAP_}.KeepCentred()") is False
    assert wow.eval(f"{MAP_}.toolbar.centred.token") == "dim"
    assert wow.eval(f"{MOD}.db.profile.centred") is True
    x = wow.eval(f"{MAP_}.Camera().wx")
    wow.run_frames(3)
    assert wow.eval(f"{MAP_}.Camera().wx") == x
    # closing and opening again follows the player
    wow.slash("/bmap")
    wow.slash("/bmap")
    assert wow.eval(f"{MAP_}.KeepCentred()") is True
    assert wow.eval(f"{MAP_}.toolbar.centred.token") == "accent"
    # another continent rests it too and is not snapped back (R28.7)
    wow.execute(f"{MAP_}.SetContinent(1)")
    wow.run_frames(3)
    assert wow.eval(f"{MAP_}.Camera().continent") == 1
    assert wow.eval(f"{MAP_}.KeepCentred()") is False
    # the Player button follows again
    wow.execute(f"{MAP_}.toolbar.player:Click()")
    assert wow.eval(f"{MAP_}.Camera().continent") == 0
    assert wow.eval(f"{MAP_}.KeepCentred()") is True
    # a place flown to stays in view (a search result, a bookmark, a page's place)
    wow.execute(f"{MAP_}.Fly(0, 500, 500, 4)")
    wow.run_frames(3)
    cam = wow.eval(f"{MAP_}.Camera()")
    assert (cam.wx, cam.wy) == (500, 500) and wow.eval(f"{MAP_}.KeepCentred()") is False
    assert wow.errors == []


def test_only_the_button_switches_centred_off_for_good(wow: WowRuntime):
    """the button is the player's word, it stays over closing the map;
    the old saved value, which every drag wrote, means nothing."""
    wow.start("Bastians_Core", "Bastians_Data", "Bastians_Map")
    wow.run_frames(5)
    wow.slash("/bmap")
    # resting, a click on the button follows again instead of switching off
    wow.execute(f"{MAP_}.Fly(0, 500, 500, 4)")
    wow.execute(f"{MAP_}.toolbar.centred:Click()")
    assert wow.eval(f"{MAP_}.KeepCentred()") is True
    wow.execute(f"{MAP_}.toolbar.centred:Click()")
    assert wow.eval(f"{MAP_}.KeepCentred()") is False
    assert wow.eval(f"{MOD}.db.profile.centred") is False
    wow.slash("/bmap")
    wow.slash("/bmap")
    assert wow.eval(f"{MAP_}.KeepCentred()") is False
    wow.execute(f"{MAP_}.toolbar.centred:Click()")
    assert wow.eval(f"{MAP_}.KeepCentred()") is True
    assert wow.errors == []
