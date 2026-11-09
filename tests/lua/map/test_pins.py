"""Pins, layers panel and waypoints (B8.3): layer queries on settle, pooled pins, clustering at low
zoom, labels, areas, path lines, clicks, the player arrow, the layers panel, the own waypoint (loud then
faint), the actions map.show, tomtom.waypoint and chat.way, and the right click on empty ground."""

import itertools

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


def bar_items(wow: WowRuntime) -> list:
    return [
        (i.kind, i.text, i.on)
        for i in wow.eval("Bastians:GetModule('Map').LayerBar.Items()").values()
    ]


def test_the_layer_bar_switches_every_layer_by_app_and_keeps_bookmarks(wow: WowRuntime):
    """a bar over the top of the map, not a Layers button; bookmarks."""
    boot(wow, CORE, DATA, QUESTS, GOLD, MAP)
    BAR = "Bastians:GetModule('Map').LayerBar"
    assert wow.eval(f"{MAP_}.toolbar.layers") is None
    panel = wow.eval(f"{BAR}.Panel()")
    assert panel.IsShown(panel) is True  # open by default
    items = bar_items(wow)
    groups = [t for k, t, _ in items if k == "gap"]  # icons only: the apps are gaps (R27.8)
    gold = wow.made_for(GOLD)  # the farm spots layer is Gold's; no Gold on retail (24.10.2026)
    assert groups == [*(["Gold"] if gold else []), "Map", "Quests", "Bookmarks"]
    pills = {t: on for k, t, on in items if k == "pill"}
    assert ("Farm spots" in pills) is gold
    assert pills["Quests to take"] is True and pills["Quests soon (level, prerequisite)"] is False
    # a click on a pill switches its layer
    wow.execute(
        f"""for _, it in ipairs({BAR}.Items()) do
              if it.id == "quests.soon" then it.onClick("LeftButton") end
            end"""
    )
    assert wow.eval(f"{MOD}.db.profile.layers['quests.soon']") is True
    wow.execute(f"{PINS}.SetLayerOn('quests.objectives', false)")
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 6)")
    wow.advance(0.2)
    assert wow.eval(f"{PINS}.stats.areas") == 0  # the objective areas are gone
    # bookmarks: + keeps the view, a click flies back, a right click removes it
    mark = wow.eval(f"{BAR}.AddBookmark()")
    assert mark.continent == 0 and (mark.wx, mark.wy, mark.level) == (0, 0, 6)
    assert mark.name in [i.text for i in wow.eval(f"{BAR}.BookmarkItems()").values()]
    wow.execute(f"{MAP_}.Fly(1, 500, 500, 3)")
    wow.execute(f"{BAR}.GoTo(1)")
    cam = wow.eval(f"{MAP_}.Camera()")
    assert (cam.continent, cam.wx, cam.wy, cam.level) == (0, 0, 0, 6)
    wow.execute(f"{BAR}.RemoveBookmark(1)")
    assert wow.eval(f"#{BAR}.Bookmarks()") == 0
    assert any("Bookmark removed" in line for line in wow.chat)
    # a bookmark is named when kept, renamed and removed from its right click menu
    wow.execute(
        f"P = {BAR}.Panel(); BOX = {BAR}.AskName(P, 'x', function(v) {BAR}.AddBookmark(v) end)"
    )
    wow.execute("BOX.edit:SetText('Hogger camp'); BOX.edit:GetScript('OnEnterPressed')(BOX.edit)")
    assert wow.eval(f"{BAR}.Bookmarks()[1].name") == "Hogger camp"
    wow.execute(f"M = {BAR}.BookmarkMenu(P, 1); M.rename:Click()")
    wow.execute("BOX.edit:SetText('Hogger'); BOX.edit:GetScript('OnEnterPressed')(BOX.edit)")
    assert wow.eval(f"{BAR}.Bookmarks()[1].name") == "Hogger"
    wow.execute(f"M = {BAR}.BookmarkMenu(P, 1); M.remove:Click()")
    assert wow.eval(f"#{BAR}.Bookmarks()") == 0
    # a layer out of its zoom range shows its pill dimmed
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 1)")
    dims = {i.id: i.dim for i in wow.eval(f"{BAR}.Items()").values() if i.kind == "pill"}
    assert dims["quests.soon"] is True and dims["map.waypoint"] is False
    # the tab slides the bar shut and open; the state is kept
    wow.execute(f"{BAR}.Tab():Click()")
    wow.run_frames(20)  # the slide (0.18 s)
    assert panel.IsShown(panel) is False and wow.eval(f"{MOD}.db.profile.barOpen") is False
    wow.execute(f"{BAR}.Tab():Click()")
    wow.run_frames(20)  # the slide (0.18 s)
    assert panel.IsShown(panel) is True
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


def test_map_show_and_way_actions_and_no_tomtom(wow: WowRuntime):
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
    # the shown entity is on the map ("always actually show what was
    # selected"): Hogger's icon and name at both spawns, the Monsters layer off, and he is the focus
    wow.advance(0.2)
    hogger = [p for p in shown(wow, "pinPool") if p.pin.ref == "npc:448"]
    assert len(hogger) == 2 and all(p.pin.label == "Hogger" and p.width == 24 for p in hogger)
    assert all(p.ring.IsShown(p.ring) for p in hogger)  # the focus ring
    assert wow.eval("Bastians:Focused()") == "npc:448"
    assert wow.eval(f"{MAP_}.strip.name:GetText()") == "Hogger"  # the context strip
    assert wow.eval(f"{PINS}.IsLayerOn(Bastians:GetMapLayer('map.monsters'))") is False
    # Esc clears the focus and the shown entity with it; the waypoint dot stays
    wow.execute(f"{MOD}.Focus.Escape()")
    wow.advance(0.2)
    assert not [p for p in shown(wow, "pinPool") if p.pin.ref == "npc:448"]
    assert wow.eval(f"{WP}.Shown()") is None and wow.eval(f"{WP}.Get().label") == "Hogger"
    wow.execute("Bastians:RunAction('chat.way', 'npc:448', { source = 'test' })")
    assert wow.eval("Mock.chatInput") == "/way Elwynn Forest 27.0 86.0 Hogger"
    # TomTom installed: still no TomTom waypoint
    wow.load_addon("TomTom")
    wow.run_frames(2)
    ids = [a.id for a in wow.eval("Bastians:GetActions('npc:448', { source = 'test' })").values()]
    assert "tomtom.waypoint" not in ids
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


def test_a_pin_with_one_quest_behind_it_opens_that_quests_sheet(wow: WowRuntime):
    """the quest sign must give the quest, not only the NPC; since ADR 0053
    on the quest sheet."""
    boot(wow, CORE, DATA, QUESTS, "Bastians_Browser", MAP)
    wow.execute(f"{PINS}.SetLayerOn('quests.soon', true)")  # Marshal Dughan: 76 waits for 62
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 6)")
    wow.run_frames(5)  # the giver index job
    wow.advance(0.3)  # the settle and the re-query the finished index asks for
    marshal = next(
        p for p in shown(wow, "pinPool") if p.pin.ref == "npc:240" and p.pin.status == "blocked"
    )
    assert list(marshal.pin.quests.values()) == [76] and "Jasperlode" in marshal.pin.lines[1]
    marshal.GetScript(marshal, "OnClick")(marshal, "LeftButton")
    assert wow.eval("Bastians:Focused()") == "quest:76"
    assert wow.eval("BastiansQuestSheet:IsShown()") is True
    assert wow.errors == []


def test_places_further_apart_than_the_view_open_at_the_nearest_group(wow: WowRuntime):
    """Riverpaw Gnoll Bounty has two camps; the map opened on Goldshire,
    their middle, and showed neither."""
    boot(wow)
    wow.slash("/bmap")
    wow.execute(f"{MAP_}.clip:SetSize(600, 400); {MAP_}.ViewChanged()")
    far = "{ { wx = 1000, wy = 1000 }, { wx = 1010, wy = 1000 }, { wx = -1000, wy = -1000 } }"
    near = wow.eval(f"{MAP_}.FitWorld(0, {far}, 5)")
    c = wow.eval(f"{MAP_}.Camera()")
    player = wow.eval(f"{MAP_}.PlayerWorld()")
    assert (near.wx, near.wy) == (-1000, -1000) or (near.wx, near.wy) == (1000, 1000)
    assert (round(c.wx), round(c.wy)) != (0, 0)  # never the middle between them
    assert player is not None
    group, first = wow.eval(
        f"(function() return {{ {MAP_}.NearestGroup({far}, 900, 900) }} end)()"
    ).values()
    assert len(list(group.values())) == 2 and (first.wx, first.wy) == (1000, 1000)
    group, first = wow.eval(f"(function() return {{ {MAP_}.NearestGroup({far}) }} end)()").values()
    assert (first.wx, first.wy) == (1000, 1000)  # no player here: the first place
    # places that fit stay centred between them
    assert (
        wow.eval(f"{MAP_}.FitWorld(0, {{ {{ wx = 0, wy = 0 }}, {{ wx = 100, wy = 0 }} }}, 5)")
        is None
    )
    c = wow.eval(f"{MAP_}.Camera()")
    assert (round(c.wx), round(c.wy)) == (50, 0)
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
    s = wow.eval(f"{WP}.Shown()")  # the point is shown with the entity's icon and the point's label
    assert (
        s.ref == "npc:448"
        and s.label == "the end"
        and (s.points[1].wx, s.points[1].wy) == (-10, 20)
    )
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


def test_the_bar_shows_icons_only_and_its_menus_work(wow: WowRuntime):
    """(R27.8): icons only, the text in the tooltip; the map style and
    the bookmarks are one icon each with a menu."""
    boot(wow, CORE, DATA, QUESTS, MAP)
    BAR = "Bastians:GetModule('Map').LayerBar"
    pills = [i for i in wow.eval(f"{BAR}.Items()").values() if i.kind == "pill"]
    # every layer names an icon the kit knows; none falls back to "other"
    for p in pills:
        assert wow.eval(f"Bastians.UI.IconTexture('{p.icon}') ~= nil") is True, p.id
    assert not [p.id for p in pills if p.icon == "other"]
    # the drawn pills carry no text: an icon, and the tooltip's title and hint
    wow.execute(f"{BAR}.Refresh()")
    frame = wow.eval(f"{BAR}.Panel()")
    shown = [c for c in frame.children.values() if c.IsShown(c) and c.icon]
    assert shown and all(c.label is None for c in shown)
    wow.execute("C = select(2, " + BAR + ".Panel():GetChildren())")
    title, text = wow.eval("C.tip(C)")
    assert title and text
    # the name shows at once, not after the tip delay
    wow.execute("GameTooltip:Hide(); C:GetScript('OnEnter')(C)")
    assert wow.eval("GameTooltip:IsShown() and GameTooltip:GetOwner() == C") is True
    wow.execute("C:GetScript('OnLeave')(C)")
    assert wow.eval("GameTooltip:IsShown()") is False
    # the style menu ticks the current style and switches
    wow.execute(f"M = {BAR}.StyleMenu({BAR}.Panel())")
    assert wow.eval("Bastians.UI.MenuFrame():IsShown()") is True
    # every entry with its icon in front, the chosen one on a lit row
    rows = [b for b in wow.eval("Bastians.UI.MenuFrame().items").values() if b.IsShown(b)]
    assert len(rows) == len(list(wow.eval(f"{BAR}.StyleItems()").values()))
    assert all(b.label.text.startswith("|T") and "Tiles" in b.label.text for b in rows)
    lit = [b.entry.label for b in rows if b.sel.IsShown(b.sel)]
    assert lit == [wow.eval(f"{MAP_}.StyleTitle({MAP_}.Style())")]
    wow.execute(
        f"for _, e in ipairs({BAR}.StyleItems()) do if e.id == 'style:physical' then e.onClick() end end"
    )
    assert wow.eval(f"{MAP_}.Style()") == "physical"
    # the bookmarks menu: keep this view, then fly back to it
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 6); {BAR}.AddBookmark('Here')")
    ids = [i.id for i in wow.eval(f"{BAR}.BookmarkItems()").values()]
    assert ids == ["bookmark:1", "bookmark:add", "bookmark:edit"]
    wow.execute(f"{MAP_}.Fly(1, 500, 500, 3); {BAR}.BookmarkItems()[1].onClick()")
    cam = wow.eval(f"{MAP_}.Camera()")
    assert (cam.continent, cam.wx, cam.wy) == (0, 0, 0)
    assert wow.errors == []


def test_the_bar_slides_shut_as_it_slides_open(wow: WowRuntime):
    """(R27.4): the bar slid open but snapped shut. The slide's time is
    summed from capped frame steps, so a long first frame cannot swallow it; the tab changes only
    when the panel is gone."""
    boot(wow, CORE, DATA, MAP)
    BAR = "Bastians:GetModule('Map').LayerBar"
    height = f"{BAR}.Panel():GetHeight()"
    full = wow.eval(height)
    wow.execute(f"{BAR}.SetOpen(false)")
    wow.run_frames(1, 0.5)  # the click's frame is a long one
    steps = [wow.eval(height)]
    assert steps[0] < full and steps[0] > full / 2  # one capped step, not the whole slide
    assert wow.eval(f"{BAR}.Tab().label:GetText()") == ""  # still the open tab while it slides
    for _ in range(10):
        wow.run_frames(1, 1 / 60)
        steps.append(wow.eval(height))
    assert all(a >= b for a, b in itertools.pairwise(steps))  # it slides, it does not snap
    wow.run_frames(20, 0.05)
    panel = wow.eval(f"{BAR}.Panel()")
    assert panel.IsShown(panel) is False and wow.eval(f"{BAR}.Tab().label:GetText()") == "Layers"
    assert wow.errors == []


def test_show_on_map_draws_the_entity_with_the_waypoint_layer_off(wow: WowRuntime):
    """ "the map I open per right click still has nothing to show on":
    with My waypoint switched off nothing drew the shown entity; Show on map switches the layer on."""
    boot(wow)
    wow.execute(f"{PINS}.SetLayerOn('map.waypoint', false)")
    wow.advance(0.2)
    assert wow.eval(f"{PINS}.IsLayerOn(Bastians:GetMapLayer('map.waypoint'))") is False
    wow.execute("Bastians:RunAction('map.show', 'npc:448', { source = 'voice' })")
    wow.advance(0.2)
    assert wow.eval(f"{PINS}.IsLayerOn(Bastians:GetMapLayer('map.waypoint'))") is True
    hogger = [p for p in shown(wow, "pinPool") if p.pin.ref == "npc:448"]
    assert len(hogger) == 2 and all(p.pin.label == "Hogger" for p in hogger)
    assert wow.eval("Bastians:Focused()") == "npc:448"
    assert wow.errors == []
