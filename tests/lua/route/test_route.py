"""The Route module (route.md): the travel service, route.to over an entity's places, the path layer,
step completion and re-routing while following, the flight network modes with learning from the taxi
map and real flights, the hearth, the step list window, and life without Map or Quests."""

from harness import WowRuntime

CORE, DATA, QUESTS, MAP, ROUTE = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Map",
    "Bastians_Route",
)
MOD = "Bastians:GetModule('Route')"
R = f"{MOD}.Route"
W = f"{MOD}.Window"
TRAVEL = "Bastians:GetService('travel')"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, MAP, ROUTE)))
    wow.run_frames(5)
    wow.execute(
        """
        routes = {}
        local w = Bastians:NewModule("RouteWatcher", { addon = "Bastians_Route" })
        w:On("BASTIANS_ROUTE_CHANGED", function(_, _, route) routes[#routes + 1] = route or false end)
        """
    )
    return wow


def move_player(wow: WowRuntime, x: float, y: float, map_id: int = 1429) -> None:
    wow.execute(f"Mock.playerMap = {map_id}; Mock.playerMapPos = {{ x = {x}, y = {y} }}")


def test_travel_service_estimates_and_goes_away_with_the_module(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f"{TRAVEL} ~= nil") is True
    seconds, mode = wow.eval(f"{TRAVEL}:Estimate({{ 0, 0, 0 }}, {{ 0, 100, 0 }})")
    assert round(seconds, 2) == 14.29 and mode == "walk"
    # the fixture ferry carries the player to Kalimdor
    seconds, mode = wow.eval(f"{TRAVEL}:Estimate({{ 0, 0, 0 }}, {{ 1, -800, -3700 }})")
    assert mode == "boat" and seconds > 360
    assert wow.eval(f"{TRAVEL}:Estimate({{ 0, 0, 0 }}, {{ 5, 0, 0 }})") is None  # no way there
    route = wow.eval(f"{TRAVEL}:Route({{ 0, 0, 0 }}, {{ 1, -800, -3700, 'Ratchet' }})")
    assert [s.mode for s in route.steps.values()] == ["walk", "boat", "walk"]
    wow.execute(f"{MOD}:Disable()")
    assert wow.eval(f"{TRAVEL}") is None
    wow.execute(f"{MOD}:Enable()")
    assert wow.eval(f"{TRAVEL} ~= nil") is True
    assert wow.errors == []


def test_route_to_picks_the_nearest_place_by_time_and_announces(wow: WowRuntime):
    boot(wow)
    ids = [a.id for a in wow.eval("Bastians:GetActions('npc:448', { source = 'test' })").values()]
    assert "route.to" in ids
    assert "route.to" not in [
        a.id for a in wow.eval("Bastians:GetActions('item:2589', { source = 'test' })").values()
    ]
    wow.execute("Bastians:RunAction('route.to', 'npc:448', { source = 'test' })")
    route = wow.eval(f"{R}.Active()")
    assert route.ref == "npc:448" and route.goal.name == "Hogger"
    # the player stands at (-60, 32); Hogger's second spawn (-120, 80) is nearer than the first
    assert (round(route.goal.wx), round(route.goal.wy)) == (-120, 80)
    assert [s.mode for s in route.steps.values()] == ["walk"] and round(route.seconds, 1) == 11.0
    assert len(wow.eval("routes")) == 1
    assert any("Route to Hogger: 0:11, 1 steps" in line for line in wow.chat)
    assert wow.eval(f"{W}.IsShown()") is True
    rows = list(wow.eval(f"{W}.tree.rows").values())
    assert rows[0].text == "1. Go 77 yd SW to Hogger (approx)" and rows[0].value == "0:11"
    assert rows[0].ref == "npc:448"
    # the path layer: one line with two points and the goal pin
    pins = list(
        wow.eval("Bastians:QueryLayer('route.path', { continent = 0, level = 5 })").values()
    )
    kinds = sorted(p.kind or "pin" for p in pins)
    assert kinds == ["path", "pin"]
    path = next(p for p in pins if p.kind == "path")
    assert len(path.points) == 2 and round(path.points[2][1]) == -120
    assert path.style == "dashed"  # an approximate leg: the map draws it dashed (21.10.2026)
    assert any("draws them dashed" in r.text for r in rows[1:])
    goal = next(p for p in pins if not p.kind)
    assert goal.ref == "npc:448" and goal.label == "Hogger"
    assert wow.eval("#Bastians:QueryLayer('route.path', { continent = 1, level = 5 })") == 0
    wow.slash("/broute clear")
    assert wow.eval(f"{R}.Active()") is None and wow.eval("routes[2]") is False
    assert wow.errors == []


def test_following_completes_steps_and_reroutes_when_off_course(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{R}.To('npc:448')")
    move_player(wow, 0.30, 0.80)  # at Hogger's second spawn
    wow.advance(1.1)
    assert wow.eval(f"{R}.Active()") is None
    assert any("You have arrived: Hogger" in line for line in wow.chat)
    # a longer walk to the Stormwind flight master, then wander far off the line
    move_player(wow, 0.42, 0.65)
    wow.execute(f"{R}.To('flightpath:2')")
    first = wow.eval(f"{R}.Active()")
    assert (round(first.goal.wx), round(first.goal.wy)) == (200, 200) and round(
        first.start.wx
    ) == -60
    move_player(wow, 0.9, 0.1)  # world (160, -160): about 280 yards from the planned line
    wow.advance(1.1)
    second = wow.eval(f"{R}.Active()")
    assert second.reason == "off course" and round(second.start.wx) == 160
    assert second.ref == "flightpath:2" and second.goal.name == "Stormwind, Elwynn"
    # the re-route is rate limited: another wander within the cooldown changes nothing
    move_player(wow, 0.42, 0.65)
    wow.advance(1.1)
    assert (
        wow.eval(f"{R}.Active()").reason == "off course"
        and round(wow.eval(f"{R}.Active().start.wx")) == 160
    )
    assert wow.errors == []


def test_flight_network_modes_learn_from_the_taxi_map_and_real_flights(wow: WowRuntime):
    boot(wow)

    def flights() -> list:
        return sorted(f.id for f in wow.eval(f"{R}.Flights()").values())

    wow.execute(f"{MOD}.db.profile.network = 'all'")
    assert flights() == [2, 4, 6, 80]  # Alliance and neutral masters; Orgrimmar is Horde only
    wow.execute(f"{MOD}.db.profile.network = 'known'")
    assert flights() == []
    wow.fire(
        "TAXIMAP_OPENED", 1
    )  # the mock shows Stormwind (current), Sentinel Hill, Ironforge (far)
    assert flights() == [2, 4]
    assert sorted(wow.eval(f"{MOD}.db.global.known").keys()) == [2, 4]
    wow.execute(f"{MOD}.db.char.known = {{}}")
    assert flights() == []
    wow.execute(f"{MOD}.db.profile.network = 'account'")
    assert flights() == [2, 4]
    # a real flight: the hook remembers where it started, the landing measures it
    wow.fire("TAXIMAP_OPENED", 1)
    wow.execute("TakeTaxiNode(2)")  # the second node shown: Sentinel Hill
    wow.advance(100)
    wow.execute("Mock.onTaxi = false")
    wow.fire("PLAYER_CONTROL_GAINED")
    times = wow.eval(f"{MOD}.db.global.flightTimes")
    assert times["2>4"] == 100 and times["4>2"] == 100
    seconds, mode = wow.eval(f"{TRAVEL}:Estimate({{ 0, 200, 200 }}, {{ 0, -700, 500 }})")
    assert seconds == 100 and mode == "fly"
    note = wow.eval(f"{R}.Note()")
    assert "2 flight masters learned, 1 flight times measured" in note
    assert wow.errors == []


def test_quests_progress_service_feeds_the_known_network(wow: WowRuntime):
    boot(wow, CORE, DATA, QUESTS, ROUTE)
    wow.fire("TAXIMAP_OPENED", 1)
    wow.execute(f"{MOD}.db.char.known = {{}}; {MOD}.db.global.known = {{}}")
    assert sorted(f.id for f in wow.eval(f"{R}.Flights()").values()) == [2, 4]
    assert wow.errors == []


def test_hearth_is_learned_and_used_only_when_ready(wow: WowRuntime):
    boot(wow)
    far, near = (
        "{ continent = 0, wx = 2500, wy = -300 }",
        "{ continent = 0, wx = -60, wy = 40, name = 'Home' }",
    )
    route = wow.eval(f"{R}.Plan({far}, {near})")
    assert [s.mode for s in route.steps.values()] == ["walk"]
    assert any("inn unknown" in n for n in route.notes.values())
    wow.slash("/broute hearth")  # standing in Goldshire at (-60, 32)
    hearth = wow.eval(f"{MOD}.db.char.hearth")
    assert (hearth.name, round(hearth.wx), round(hearth.wy)) == ("Goldshire", -60, 32)
    route = wow.eval(f"{R}.Plan({far}, {near})")
    assert any("no Hearthstone" in n for n in route.notes.values())
    wow.execute("Mock.bags[6948] = 1")
    route = wow.eval(f"{R}.Plan({far}, {near})")
    assert [s.mode for s in route.steps.values()] == ["hearth", "walk"]
    assert round(route.seconds, 1) == 11.1 and route.steps[1].to.name == "Goldshire"
    wow.execute("Mock.itemCooldowns[6948] = { start = GetTime(), duration = 1800 }")
    route = wow.eval(f"{R}.Plan({far}, {near})")
    assert [s.mode for s in route.steps.values()] == ["walk"]
    assert any("ready in 30:00" in n for n in route.notes.values())
    wow.execute("Mock.itemCooldowns[6948] = nil; Mock.bindLocation = 'Stormwind'")
    route = wow.eval(f"{R}.Plan({far}, {near})")
    assert any("bound to Stormwind now" in n for n in route.notes.values())
    assert "Hearth: Goldshire" in wow.eval(f"{R}.Note()")
    assert wow.errors == []


def test_window_and_service_work_without_map(wow: WowRuntime):
    boot(wow, CORE, DATA, ROUTE)
    wow.execute(f"{R}.Set({TRAVEL}:Route({{ 0, 0, 0 }}, {{ 1, -800, -3700, 'Ratchet' }}))")
    wow.slash("/broute")
    assert wow.eval(f"{W}.IsShown()") is True
    rows = list(wow.eval(f"{W}.tree.rows").values())
    texts = [r.text for r in rows]
    assert texts[0].startswith("1. Go 226 yd SE to Elwynn dock (approx)")
    assert (
        texts[1].startswith("2. Take the boat to Ratchet dock (approx)")
        and "wait up to 8:00" in texts[1]
    )
    assert rows[1].ref == "transport:boat-elwynn-ratchet"
    assert any("approx" in t for t in texts[3:])  # the explanation paragraph
    assert wow.eval(f"{W}.summary:GetText()").startswith("To Ratchet: ")
    assert wow.eval(f"{W}.win.content ~= nil") is True  # the window exists without Map
    wow.execute(f"{R}.Clear()")
    wow.advance(0.1)  # the render is coalesced
    assert wow.eval(f"{W}.tree.rows[1]") is None
    assert (
        wow.eval("Bastians:GetMapLayer('route.path') ~= nil") is True
    )  # registered even without Map
    assert wow.errors == []


def test_mount_speed_is_learned_from_movement(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{R}.To('npc:448')")
    wow.execute("Mock.unitSpeed = 14")
    wow.advance(1.1)
    assert wow.eval(f"{MOD}.db.char.maxSpeed") == 14
    wow.execute("Mock.unitSpeed = 60; Mock.onTaxi = true")  # a taxi does not count
    wow.advance(1.1)
    assert wow.eval(f"{MOD}.db.char.maxSpeed") == 14
    wow.execute("Mock.onTaxi = false")
    seconds = wow.eval(
        f"{R}.Plan({{ continent = 0, wx = 0, wy = 0 }}, {{ continent = 0, wx = 140, wy = 0 }}).seconds"
    )
    assert seconds == 10  # 140 yards at the learned 14 yards per second
    assert wow.errors == []


def test_a_route_to_a_place_at_hand_says_so_and_a_failed_reroute_keeps_the_route(wow: WowRuntime):
    """a route was drawn and gone two seconds later. Two causes closed:
    the goal within the arrival distance (now "already there", nothing drawn) and a re-route that
    fails (now the route stays, the chat says so)."""
    boot(wow)
    move_player(wow, 0.27, 0.86)  # at Hogger's first spawn
    assert wow.eval(f"{R}.To('npc:448')") is False
    assert wow.eval(f"{R}.Active()") is None
    assert any("You are already there: Hogger" in line for line in wow.chat)
    move_player(wow, 0.42, 0.65)
    wow.execute(f"{R}.To('flightpath:2')")
    assert wow.eval(f"{R}.Active() ~= nil") is True
    # far off the line the re-route runs; when the planner finds nothing the route is kept
    wow.execute(f"{R}.Plan = function() return nil end")
    move_player(wow, 0.9, 0.1)
    wow.advance(1.1)
    assert wow.eval(f"{R}.Active() ~= nil") is True and wow.eval(f"{R}.Active().reason") is None
    assert any("Could not re-route" in line for line in wow.chat)
    assert wow.errors == []


def test_a_step_click_shows_its_end_on_the_map(wow: WowRuntime):
    """a step row shows the step's end point, not every place of the
    entity it leads to (a boat's two ends fitted the map to the world)."""
    boot(wow)
    wow.execute("Bastians:RunAction('route.to', 'npc:448', { source = 'test' })")
    rows = list(wow.eval(f"{W}.tree.rows").values())
    assert rows[0].onClick is not None
    wow.execute(f"{W}.tree.rows[1].onClick({W}.tree.rows[1], 'LeftButton')")
    wp = wow.eval("Bastians:GetModule('Map').Waypoints.Get()")
    assert (round(wp.wx), round(wp.wy)) == (-120, 80)  # the nearer spawn: the step's end
    assert wp.label.startswith("Go 77 yd")
    assert wow.errors == []
