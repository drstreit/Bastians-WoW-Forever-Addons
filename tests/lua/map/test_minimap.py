"""The minimap overlay (map.md "The minimap overlay", S5, 22.10.2026): the map's layers on the
game's minimap, the nearest N pins around the player placed by the minimap's yards per zoom step,
pins beyond the rim pulled to it with an arrow, rotation with the player's facing, the layer
toggles and the setting, nothing in an instance, no ticks while hidden."""

import math

from harness import WowRuntime

CORE, DATA, QUESTS, MAP = "Bastians_Core", "Bastians_Data", "Bastians_Quests", "Bastians_Map"
MOD = "Bastians:GetModule('Map')"
MM = f"{MOD}.Minimap"
PINS = f"{MOD}.Pins"
LAYER = """
local m = Bastians:NewModule("NearLayer", { addon = "Bastians_Map" })
Bastians:RegisterMapLayer(m, { id = "test.near", label = "Near", defaultOn = true, minLevel = 0,
  query = function(view)
    local p = view.player
    return {
      { ref = "npc:54", wx = p[2] + 50, wy = p[3], icon = 1, color = { 1, 0, 0 } },      -- 50 yd north
      { ref = "npc:198", wx = p[2], wy = p[3] + 30, icon = 2 },                          -- 30 yd west
      { ref = "npc:295", wx = p[2] - 400, wy = p[3], icon = 3 },                         -- 400 yd south
      { ref = "npc:299", wx = p[2] + 900, wy = p[3], icon = 4 },                         -- beyond the range
      { kind = "path", points = { { p[2], p[3] }, { p[2] + 100, p[3] }, { p[2] + 100, p[3] + 900 } },
        color = { 0.3, 0.8, 1 }, width = 3 },                                            -- a path, no pin
    }
  end })
"""


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, QUESTS, MAP)))
    wow.run_frames(10)
    wow.advance(0.3)
    return wow


def setting(wow: WowRuntime, key: str, on: bool) -> None:
    wow.execute(f"{MOD}.db.profile.{key} = {str(on).lower()}")
    wow.execute(f"Bastians:Fire('BASTIANS_SETTING_CHANGED', 'Map', '{key}', {str(on).lower()})")


def shown(wow: WowRuntime) -> dict[str, object]:
    out = {}
    for f in wow.eval(f"{MM}.pool").values():
        if f.IsShown(f) and f.pin:
            out[f.pin.ref] = f
    return out


def offset(f) -> tuple[float, float]:
    _, _, _, x, y = f.GetPoint(f, 1)
    return round(x, 1), round(y, 1)


def test_the_nearest_pins_sit_around_the_player_at_the_minimaps_scale(wow: WowRuntime):
    boot(wow)
    wow.execute(LAYER)
    wow.advance(0.2)  # the registration re-queries (coalesced)
    assert wow.eval(f"{MM}.frame:IsShown()") is True
    pins = shown(wow)
    assert set(pins) >= {"npc:54", "npc:198", "npc:295"} and "npc:299" not in pins
    # outdoors at zoom 0 the minimap shows 466.67 yards across 140 px: 0.3 px per yard
    assert round(wow.eval(f"{MM}.Scale()"), 3) == 0.3
    assert offset(pins["npc:54"]) == (0, 15)  # north is up
    assert offset(pins["npc:198"]) == (-9, 0)  # west is left
    # 400 yd south would be 120 px down: pulled to the rim (70 - 7 px) with the arrow pointing down
    f = pins["npc:295"]
    assert offset(f) == (0, -63) and f.arrow.IsShown(f.arrow) and f.GetWidth(f) == 10
    assert round(f.arrow.GetRotation(f.arrow), 2) == round(-math.pi, 2)
    assert not pins["npc:54"].arrow.IsShown(pins["npc:54"].arrow)
    assert pins["npc:54"].GetWidth(pins["npc:54"]) == 14
    assert pins["npc:54"].icon.GetTexture(pins["npc:54"].icon) == 1
    stats = wow.eval(f"{MM}.stats")
    assert stats.edge == 1 and stats.shown == stats.queried
    # the path: 100 yd north is 30 px, three pieces of 10 px; the leg east of it 900 yd (270 px)
    # is cut at the rim: pieces only inside 63 px of the centre (S6)
    assert 3 <= stats.pieces <= 3 + 7
    drawn = [t for t in wow.eval(f"{MM}.pieces").values() if t.IsShown(t)]
    assert len(drawn) == stats.pieces
    first = drawn[0]
    assert round(first.GetWidth(first)) == 10 and first.GetHeight(first) == 3
    assert round(first.GetRotation(first), 3) == round(math.pi / 2, 3)  # straight up
    _, _, _, px, py = first.GetPoint(first, 1)
    assert (round(px), round(py)) == (0, 5)
    assert all(math.hypot(*t.GetPoint(t, 1)[3:5]) <= 63 for t in drawn)
    # the nearest first: with a cap of 5 the far one is dropped before the near ones
    wow.execute(f"{MOD}.db.profile.minimapMax = 1")
    wow.execute(f"{MM}.Query()")
    only = list(shown(wow))
    assert len(only) == 1 and only[0] == wow.eval(f"{MM}.Pins()[1].ref")
    assert (
        wow.eval(f"{MM}.Pins()[1].distance") <= 30
    )  # the quest fixture's hand-in or the 30 yd pin
    wow.execute(f"{MOD}.db.profile.minimapMax = 20")
    wow.execute(f"{MM}.Query()")
    # zooming in: a closer zoom step means more pixels per yard (the client keeps the outdoor
    # zoom in the cvar minimapZoom, so the zoom buttons change both)
    wow.execute('Mock.minimapZoom = 5; Mock.cvars.minimapZoom = "5"')
    wow.fire("MINIMAP_UPDATE_ZOOM")
    assert round(wow.eval(f"{MM}.Scale()"), 2) == 1.05
    assert offset(shown(wow)["npc:54"]) == (0, 52.5)
    assert wow.eval(f"{MM}.Indoors()") is False
    # indoors: the minimap's zoom equals the inside cvar
    wow.execute("Mock.minimapZoom = 1")
    wow.fire("MINIMAP_UPDATE_ZOOM")
    assert wow.eval(f"{MM}.Indoors()") is True
    assert round(wow.eval(f"{MM}.Scale()"), 3) == round(140 / 240, 3)
    assert wow.eval("Mock.minimapZoom") == 1  # the zoom probe leaves the zoom as it was
    assert wow.errors == []


def test_rotation_follows_the_facing_and_the_player_moving_moves_the_pins(wow: WowRuntime):
    boot(wow)
    wow.execute(LAYER)
    wow.advance(0.2)
    # the minimap rotates: facing west (pi/2) puts the western pin ahead, that is up
    wow.execute('Mock.cvars.rotateMinimap = "1"; Mock.facing = math.pi / 2')
    wow.execute(f"{MM}.Reposition()")
    pins = shown(wow)
    assert offset(pins["npc:198"]) == (0, 9)
    assert offset(pins["npc:54"]) == (15, 0)  # north is now to the right
    wow.execute('Mock.cvars.rotateMinimap = "0"')
    # the player walks 20 yd north: the ticks move the pins without a new query
    queried = wow.eval(f"{MM}.stats.queried")
    wow.execute("Mock.playerMapPos.x = Mock.playerMapPos.x")  # unchanged so far
    cont, wx, wy = wow.eval("Bastians.Coords.Player()")[0:3]
    wow.execute(f"{MM}.Query()")
    pin = wow.eval(f"{MM}.Pins()[1]")
    before = offset(shown(wow)[pin.ref])
    # move the pin instead of the player (the mock's player position is a map fraction): same effect;
    # the ticks run only between PLAYER_STARTED_MOVING and PLAYER_STOPPED_MOVING (nfr.md: idle = 0)
    wow.run_frames(8)
    assert wow.eval(f"{MM}.Ticking()") is False
    wow.execute(f"{MM}.Pins()[1].wx = {MM}.Pins()[1].wx + 20")
    wow.fire("PLAYER_STARTED_MOVING")
    assert wow.eval(f"{MM}.Ticking()") is True
    wow.run_frames(8)  # 8 frames at 1/60 s: one tick (0.1 s)
    after = offset(shown(wow)[pin.ref])
    assert after[1] == before[1] + 6 and wow.eval(f"{MM}.stats.queried") == queried
    wow.fire("PLAYER_STOPPED_MOVING")
    wow.run_frames(8)
    assert wow.eval(f"{MM}.Ticking()") is False  # one last move, then nothing
    assert wow.eval(f"{MM}.frame:GetScript('OnUpdate')") is None
    assert cont is not None and wx is not None and wy is not None
    assert wow.errors == []


def test_layer_toggles_the_setting_instances_and_disable(wow: WowRuntime):
    boot(wow)
    wow.execute(LAYER)
    wow.advance(0.2)
    assert "npc:54" in shown(wow)
    # the layer turned off on the map is off on the minimap too
    wow.execute(f"{PINS}.SetLayerOn('test.near', false)")
    wow.fire("ZONE_CHANGED_NEW_AREA")
    wow.advance(0.2)
    assert "npc:54" not in shown(wow)
    wow.execute(f"{PINS}.SetLayerOn('test.near', true)")
    wow.execute("Bastians:Fire('BASTIANS_LAYER_CHANGED', 'test.near')")
    wow.advance(0.2)
    assert "npc:54" in shown(wow)
    # the setting off: everything gone, the frame hidden (no OnUpdate on a hidden frame)
    setting(wow, "minimapPins", False)
    wow.advance(0.2)
    assert shown(wow) == {} and wow.eval(f"{MM}.frame:IsShown()") is False
    setting(wow, "minimapPins", True)
    wow.advance(0.2)
    assert "npc:54" in shown(wow)
    # an instance (no map position): the overlay hides until the next zone
    wow.execute("Mock.playerMap = nil")
    wow.fire("ZONE_CHANGED_NEW_AREA")
    wow.advance(0.2)
    assert wow.eval(f"{MM}.frame:IsShown()") is False
    wow.execute("Mock.playerMap = 1429")
    wow.fire("PLAYER_ENTERING_WORLD")
    wow.advance(0.5)
    assert wow.eval(f"{MM}.frame:IsShown()") is True and "npc:54" in shown(wow)
    # the hover and the click are the map's: the mini-card names the NPC, a click focuses it
    f = shown(wow)["npc:54"]
    f.GetScript(f, "OnEnter")(f)
    assert wow.eval(f"{PINS}.miniCard:IsShown()") is True
    f.GetScript(f, "OnLeave")(f)
    f.GetScript(f, "OnClick")(f, "LeftButton")
    assert wow.eval("Bastians:Focused()") == "npc:54"
    # the module disabled: the overlay goes
    wow.execute(f"{MOD}:Disable()")
    assert wow.eval(f"{MM}.frame:IsShown()") is False
    assert wow.errors == []


def test_the_zoom_probe_never_feeds_itself(wow: WowRuntime):
    """(T18, Z1): the Map spent about 82 ms of every second, 33 calls a
    second all session. The indoor probe set the minimap's zoom from MINIMAP_UPDATE_ZOOM; the
    client answers a zoom change with that event, so the handler fed itself every frame. Now the
    probe runs once per zone or indoor change, and only when the outdoor and indoor zoom cvars are
    equal; the zoom event moves the pins and nothing else."""
    boot(wow)
    wow.execute('Mock.cvars.minimapZoom = "0"; Mock.cvars.minimapInsideZoom = "0"')
    wow.execute("Mock.minimapZoom = 0")
    wow.execute("Bastians.Perf.Reset()")
    wow.fire("ZONE_CHANGED_INDOORS")  # the probe: two zoom changes, two events later
    wow.fire("MINIMAP_UPDATE_ZOOM")  # and the player's own zoom
    wow.advance(2)
    wow.run_frames(120)
    probes = wow.eval(f"{MM}.probes")
    assert probes is not None and probes <= 2
    calls = wow.eval("Bastians.Perf.Snapshot().modules.Map")
    assert calls is None or calls.calls < 20  # was one per frame for the whole session
    assert wow.eval("Mock.minimapZoom") == 0  # the probe leaves the zoom as it was
    # unequal cvars answer without a probe
    wow.execute('Mock.cvars.minimapInsideZoom = "1"; Mock.minimapZoom = 1')
    before = wow.eval(f"{MM}.probes")
    wow.fire("ZONE_CHANGED_INDOORS")
    wow.run_frames(5)
    assert wow.eval(f"{MM}.probes") == before and wow.eval(f"{MM}.Indoors()") is True
    assert wow.errors == []
