"""Pins, layers panel and waypoints (B8.3): layer queries on settle, pooled pins, clustering at low
zoom, labels, areas, path lines, clicks, the player arrow, the layers panel, the own waypoint (loud then
faint), the actions map.show, tomtom.waypoint and chat.way, and the right click on empty ground."""

from harness import WowRuntime

CORE, DATA, QUESTS, GOLD, MAP = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Gold",
    "Bastians_Map",
)
MOD = "Bastians:GetModule('Map')"
MAP_ = f"{MOD}.Map"
PINS = f"{MOD}.Pins"
WP = f"{MOD}.Waypoints"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, QUESTS, MAP)))
    wow.run_frames(10)
    wow.slash("/bmap")
    wow.execute(f"{MAP_}.clip:SetSize(600, 400); {MAP_}.ViewChanged()")
    wow.advance(0.2)  # the view settles: layers are queried
    return wow


def shown(wow: WowRuntime, pool: str) -> list:
    return [f for f in wow.eval(f"{PINS}.{pool}").values() if f.IsShown(f)]


def test_layers_are_queried_on_settle_and_drawn_from_pools(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 6)")  # Elwynn at 2 px per yard: no clustering
    wow.advance(0.2)
    stats = wow.eval(f"{PINS}.stats")
    assert (
        stats.clusters == 0 and stats.pins >= 2
    )  # the quest layers: Marshal Dughan and the objectives
    pins = shown(wow, "pinPool")
    refs = sorted(p.pin.ref for p in pins if p.pin.ref)
    assert "npc:240" in refs and "quest:176" in refs
    assert stats.areas >= 1  # the objective spots carry a radius
    # the same number of frames after another view change: pooled
    wow.execute(f"{MAP_}.Pan(3, 3)")
    assert len(shown(wow, "pinPool")) == stats.pins
    assert wow.errors == []


def test_clustering_at_low_zoom_and_cluster_click_zooms_in(wow: WowRuntime):
    boot(wow)
    wow.execute(
        """
        local m = Bastians:NewModule("ManyLayer", { addon = "Bastians_Map" })
        Bastians:RegisterMapLayer(m, { id = "test.many", label = "Many", defaultOn = true, minLevel = 0,
          query = function()
            return { { ref = "npc:54", wx = 0, wy = 0, priority = 40 }, { ref = "npc:198", wx = 20, wy = 10, priority = 70 },
                     { ref = "npc:295", wx = -15, wy = 5 } }
          end })
        """
    )
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 2)")  # 8 yards per pixel: the three pins share one grid cell
    wow.advance(0.2)
    stats = wow.eval(f"{PINS}.stats")
    assert stats.clusters >= 1
    cluster = next(p for p in shown(wow, "pinPool") if p.pin.isCluster)
    assert cluster.pin.count >= 2 and cluster.count.GetText(cluster.count) == str(
        int(cluster.pin.count)
    )
    wow.execute(f"({PINS}.pinPool[1]).pin = ({PINS}.pinPool[1]).pin")  # no-op, keeps the frame
    cluster.GetScript(cluster, "OnClick")(cluster, "LeftButton")
    assert wow.eval(f"{MAP_}.Camera().level") == 4
    assert wow.errors == []


def test_labels_and_pin_clicks(wow: WowRuntime):
    boot(wow)
    wow.execute(
        """
        focused = {}
        local w = Bastians:NewModule("FocusWatcher", { addon = "Bastians_Map" })
        w:On("BASTIANS_ENTITY_FOCUSED", function(_, _, ref) focused[#focused + 1] = ref end)
        """
    )
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 6)")
    wow.advance(0.2)
    labels = [fs.GetText(fs) for fs in shown(wow, "labelPool")]
    assert "Marshal Dughan" in labels  # the hand-in pin has priority 55 and a label
    marshal = next(p for p in shown(wow, "pinPool") if p.pin.ref == "npc:240")
    marshal.GetScript(marshal, "OnClick")(marshal, "LeftButton")
    # the primary action for an NPC here is map.show, so a click focuses the entity instead
    assert list(wow.g.focused.values()) == ["npc:240"]
    marshal.GetScript(marshal, "OnClick")(marshal, "RightButton")
    assert wow.eval("Bastians.UI.EntityMenuFrame():IsShown()") is True
    # a hover shows the mini-card (C7), not the game tooltip
    wow.execute("GameTooltip:ClearLines()")
    marshal.GetScript(marshal, "OnEnter")(marshal)
    assert wow.eval("GameTooltip:NumLines()") == 0
    assert wow.eval(f"{PINS}.miniCard:IsShown()") is True
    assert wow.eval(f"{PINS}.miniCard.name:GetText()") == "Marshal Dughan"
    marshal.GetScript(marshal, "OnLeave")(marshal)
    assert wow.eval(f"{PINS}.miniCard:IsShown()") is False
    assert wow.errors == []


def test_player_arrow_follows_position_and_facing(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.facing = 1.5")
    wow.execute(f"{MAP_}.Fly(0, -60, 32, 5)")  # the player's position
    arrow = wow.eval(f"{PINS}.Arrow()")
    assert arrow.IsShown(arrow) is True and arrow.rotation == 1.5
    point = arrow.GetPoint(arrow)
    assert (point[3], point[4]) == (300, -200)  # the centre of the 600 x 400 view
    wow.execute(f"{MAP_}.Fly(1, 0, 0, 5)")  # another continent: no arrow
    assert arrow.IsShown(arrow) is False


def test_layers_panel_lists_every_layer_by_owner_and_toggles(wow: WowRuntime):
    boot(wow, CORE, DATA, QUESTS, GOLD, MAP)
    wow.execute(f"{PINS}.TogglePanel()")
    panel = wow.eval(f"{PINS}.Panel()")
    assert panel.IsShown(panel) is True
    rows = [(r.kind, r.label.GetText(r.label)) for r in panel.rows.values() if r.IsShown(r)]
    headers = [t for k, t in rows if k == "header"]
    toggles = [t for k, t in rows if k == "toggle"]
    gold = wow.made_for(GOLD)  # the farm spots layer is Gold's; no Gold on retail
    assert headers == [*(["Gold"] if gold else []), "Map", "Quests"]
    assert ("Farm spots" in toggles) is gold
    assert "Quests to take" in toggles and "Waypoint" in toggles
    soon = next(
        r
        for r in panel.rows.values()
        if r.IsShown(r) and r.kind == "toggle" and r.layerID == "quests.soon"
    )
    assert soon.checked is False  # off by default
    soon.GetScript(soon, "OnClick")(soon)
    assert wow.eval(f"{MOD}.db.profile.layers['quests.soon']") is True
    assert soon.checked is True
    wow.execute(f"{PINS}.SetLayerOn('quests.objectives', false)")
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 6)")
    wow.advance(0.2)
    assert wow.eval(f"{PINS}.stats.areas") == 0  # the objective areas are gone
    assert wow.errors == []


def test_own_waypoint_is_loud_then_faint_and_the_right_click_sets_one(wow: WowRuntime):
    boot(wow, CORE, DATA, QUESTS, "Bastians_Browser", MAP)  # the Browser gives zones an action
    wow.execute(f"{WP}.Set(0, -60, 32, 'Here')")
    wow.advance(0.2)
    pin = next(p for p in shown(wow, "pinPool") if p.pin.label == "Here")
    assert pin.width == 32 and list(pin.pin.color.values()) == list(
        wow.eval("Bastians.UI.Style.C.waypointLoud").values()
    )
    wow.advance(3.2)  # the loud phase ends: the layer is re-queried
    pins = shown(wow, "pinPool")
    faint = [p for p in pins if p.pin.priority == 90]
    assert len(faint) == 1 and faint[0].width == 8 and faint[0].pin.label is None
    assert wow.eval(f"{WP}.Get().map") == 1429
    assert wow.eval(f"{WP}.WayLine(0, -60, 32, 'Here')") == "/way Elwynn Forest 42.0 65.0 Here"
    # right click on empty ground: a waypoint at the point and the zone's menu
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 4)")
    wow.execute(f"{MAP_}.OnRightClick(300, 200)")
    assert wow.eval(f"{WP}.Get().label").startswith("Elwynn Forest 50.0, 50.0")
    assert wow.eval("Bastians.UI.EntityMenuFrame():IsShown()") is True
    assert any("Elwynn Forest 50.0, 50.0" in line for line in wow.chat)
    wow.execute(f"{WP}.Clear()")
    assert wow.eval(f"{WP}.Get()") is None
    assert wow.errors == []


def test_map_show_tomtom_and_way_actions(wow: WowRuntime):
    boot(wow)
    ids = [a.id for a in wow.eval("Bastians:GetActions('npc:448', { source = 'test' })").values()]
    assert "map.show" in ids and "chat.way" in ids and "tomtom.waypoint" not in ids  # no TomTom
    assert "map.show" not in [
        a.id for a in wow.eval("Bastians:GetActions('item:2589', { source = 'test' })").values()
    ]
    wow.slash("/bmap")  # hide
    wow.execute("Bastians:RunAction('map.show', 'npc:448', { source = 'test' })")
    assert wow.eval(f"{MAP_}.IsShown()") is True
    c = wow.eval(f"{MAP_}.Camera()")
    assert (round(c.wx), round(c.wy), c.level) == (-132, 86, 5)  # the box centre of both spawns
    assert wow.eval(f"{WP}.Get().label") == "Hogger"
    wow.execute("Bastians:RunAction('chat.way', 'npc:448', { source = 'test' })")
    assert wow.eval("Mock.chatInput") == "/way Elwynn Forest 27.0 86.0 Hogger"
    # with TomTom present the waypoint action appears and hands the map position over
    wow.load_addon("TomTom")
    wow.run_frames(2)
    ids = [a.id for a in wow.eval("Bastians:GetActions('npc:448', { source = 'test' })").values()]
    assert "tomtom.waypoint" in ids
    wow.execute("Bastians:RunAction('tomtom.waypoint', 'npc:448', { source = 'test' })")
    wp = wow.eval("TomTom.waypoints[1]")
    assert (wp.map, wp.x, wp.y, wp.title) == (1429, 0.27, 0.86, "Hogger")
    assert wow.errors == []


def test_focus_highlights_a_visible_entity_and_path_pins_draw_lines(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 4)")
    wow.execute("Bastians:Fire('BASTIANS_ENTITY_FOCUSED', 'npc:240', { source = 'quests' })")
    assert wow.eval(f"{WP}.Get().label") == "Marshal Dughan"
    wow.execute(
        """
        local m = Bastians:NewModule("PathLayer", { addon = "Bastians_Map" })
        Bastians:RegisterMapLayer(m, { id = "test.path", label = "Path", defaultOn = true, minLevel = 0,
          query = function() return { { kind = "path", points = { { 0, 0 }, { 100, 0 }, { 100, 100 } }, color = { 1, 0, 0 } } } end })
        """
    )
    wow.advance(0.2)
    assert wow.eval(f"{PINS}.stats.lines") == 2
    seg = next(t for t in wow.eval(f"{PINS}.linePool").values() if t.IsShown(t))
    assert round(seg.width, 1) == 50.0  # 100 yards at 0.5 px per yard
    assert wow.errors == []


def test_a_pin_with_one_quest_behind_it_opens_that_quest_in_the_browser(wow: WowRuntime):
    """the quest sign must give the quest, not only the NPC."""
    boot(wow, CORE, DATA, QUESTS, "Bastians_Browser", MAP)
    wow.execute(f"{PINS}.SetLayerOn('quests.soon', true)")  # Marshal Dughan: 76 waits for 62
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 6)")
    wow.run_frames(5)  # the giver index job
    wow.advance(0.3)  # the settle and the re-query the finished index asks for
    marshal = next(p for p in shown(wow, "pinPool") if p.pin.ref == "npc:240" and p.pin.quests)
    assert list(marshal.pin.quests.values()) == [76] and "Jasperlode" in marshal.pin.lines[1]
    marshal.GetScript(marshal, "OnClick")(marshal, "LeftButton")
    browser = "Bastians:GetModule('Browser').Browser"
    assert wow.eval(f"{browser}.Current().ref") == "quest:76"
    assert wow.eval("BastiansBrowserFrame:IsShown()") is True
    assert wow.errors == []


def test_show_on_map_keeps_the_players_zoom_and_a_zone_opens_whole(wow: WowRuntime):
    """three spawns fitted at a far zoom became one icon. The view
    centres on the places at the player's zoom, zoomed in to level 5 at least, never out; a
    point in the context wins (a route step's end); a zone page opens the map on the whole zone."""
    boot(wow)
    wow.slash("/bmap")
    wow.execute(f"{MAP_}.clip:SetSize(600, 400); {MAP_}.ViewChanged()")
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 7)")
    wow.execute("Bastians:RunAction('map.show', 'npc:448', { source = 'test' })")
    c = wow.eval(f"{MAP_}.Camera()")
    assert (round(c.wx), round(c.wy), c.level) == (-132, 86, 7)  # centred, the zoom kept
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 2)")
    wow.execute("Bastians:RunAction('map.show', 'npc:448', { source = 'test' })")
    assert wow.eval(f"{MAP_}.Camera().level") == 5  # zoomed in to the show level, not out
    wow.execute(
        "Bastians:RunAction('map.show', 'npc:448', { source = 'test', point = { 0, -10, 20, 'the end' } })"
    )
    c = wow.eval(f"{MAP_}.Camera()")
    assert (round(c.wx), round(c.wy)) == (-10, 20) and wow.eval(f"{WP}.Get().label") == "the end"
    ids = [a.id for a in wow.eval("Bastians:GetActions('zone:1429', { source = 'test' })").values()]
    assert "map.zone" in ids and "map.show" not in ids
    assert "map.zone" not in [
        a.id for a in wow.eval("Bastians:GetActions('npc:448', { source = 'test' })").values()
    ]
    wow.slash("/bmap")  # hide
    wow.execute("Bastians:RunAction('map.zone', 'zone:1429', { source = 'test' })")
    assert wow.eval(f"{MAP_}.IsShown()") is True
    c = wow.eval(f"{MAP_}.Camera()")
    assert c.continent == 0 and c.level <= 5
    assert wow.errors == []
