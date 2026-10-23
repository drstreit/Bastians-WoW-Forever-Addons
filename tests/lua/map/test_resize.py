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
    assert wow.eval(f"{MAP_}.toolbar.full.label:GetText()") == "Back"
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
