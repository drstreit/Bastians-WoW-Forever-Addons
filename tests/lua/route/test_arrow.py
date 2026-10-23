"""The arrow to the next step (route.md "The arrow", S6, 22.10.2026): the own arrow turns with the
facing toward the step's end and names it with the distance, follows the steps and goes with the
route, ticks only while the player moves; TomTom's crazy arrow instead when TomTom is installed
(a waypoint per step, replaced and removed); the setting; the next step as a minimap pin."""

import math

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
A = f"{MOD}.Arrow"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, MAP, ROUTE)))
    wow.run_frames(5)
    return wow


def move_player(wow: WowRuntime, x: float, y: float, map_id: int = 1429) -> None:
    wow.execute(f"Mock.playerMap = {map_id}; Mock.playerMapPos = {{ x = {x}, y = {y} }}")


def test_the_own_arrow_turns_toward_the_next_step_and_goes_with_the_route(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f"{A}.IsShown()") is False
    wow.execute(f"{R}.To('npc:448')")  # Hogger's second spawn (-120, 80) from (-60, 32)
    assert wow.eval(f"{A}.IsShown()") is True
    f = wow.eval(f"{A}.frame")
    assert f.name.GetText(f.name) == "Hogger" and f.dist.GetText(f.dist) == "77 yd"
    bearing = math.atan2(80 - 32, -120 - -60)  # west positive, counter-clockwise from north
    assert round(f.angle, 3) == round(bearing, 3)  # facing north
    # Core's arrow texture points east: the texture turns a quarter more than the angle
    assert round(f.tex.GetRotation(f.tex), 3) == round(bearing + math.pi / 2, 3)
    assert f.tex.GetTexture(f.tex) == wow.eval("Bastians.UI.Style.ARROW")
    # facing west (pi/2): the arrow turns back by that much
    wow.execute("Mock.facing = math.pi / 2")
    wow.execute(f"{A}.Refresh()")
    assert round(f.angle, 3) == round(bearing - math.pi / 2, 3)
    # the ticks run only while moving: a stop ends them after one more turn
    assert wow.eval(f"{A}.Ticking()") is False
    wow.fire("PLAYER_STARTED_MOVING")
    assert wow.eval(f"{A}.Ticking()") is True
    wow.execute("Mock.facing = 0")
    wow.run_frames(8)
    assert round(f.angle, 3) == round(bearing, 3)
    wow.fire("PLAYER_STOPPED_MOVING")
    wow.run_frames(8)
    assert wow.eval(f"{A}.Ticking()") is False
    # the route's own ticker turns the arrow once a second too
    wow.execute("Mock.facing = 1")
    wow.advance(1.1)
    assert round(f.angle, 3) == round(bearing - 1, 3)
    # the arrow is dragged: its place is remembered
    wow.execute(
        f"{A}.frame:ClearAllPoints(); {A}.frame:SetPoint('CENTER', UIParent, 'CENTER', 30, -40)"
    )
    f.GetScript(f, "OnDragStop")(f)
    saved = wow.eval(f"{MOD}.db.profile.arrow")
    assert saved is not None and len(saved) == 2  # the offset from the screen's centre
    # arrival: the route clears, the arrow hides
    move_player(wow, 0.30, 0.80)
    wow.advance(1.1)
    assert wow.eval(f"{R}.Active()") is None and wow.eval(f"{A}.IsShown()") is False
    # a right click clears a route (the player back at the start: at Hogger a route says "already there")
    move_player(wow, 0.42, 0.65)
    wow.execute(f"{R}.To('npc:448')")
    assert wow.eval(f"{A}.IsShown()") is True
    f.GetScript(f, "OnClick")(f, "RightButton")
    assert wow.eval(f"{R}.Active()") is None and wow.eval(f"{A}.IsShown()") is False
    assert wow.errors == []


def test_the_arrow_follows_the_steps_and_the_minimap_gets_the_next_step(wow: WowRuntime):
    boot(wow)
    move_player(wow, 0.42, 0.65)
    wow.execute(f"{R}.To('flightpath:2')")  # the Stormwind flight master at (200, 200)
    f = wow.eval(f"{A}.frame")
    assert f.name.GetText(f.name) == "Stormwind, Elwynn"
    # the minimap view gets the next step's end as a pin (the goal here: no second pin)
    pins = list(
        wow.eval(
            "Bastians:QueryLayer('route.path', { continent = 0, level = 6, minimap = true })"
        ).values()
    )
    assert [p.kind or "pin" for p in pins].count("pin") == 1 and pins[
        -1
    ].label == "Stormwind, Elwynn"
    # a multi-step route: the next step's end differs from the goal, so the minimap gets both
    wow.execute(f"{R}.ToPoint(1, -800, -3700, 'Ratchet')")  # across the sea by the fixture ferry
    route = wow.eval(f"{R}.Active()")
    assert len(route.steps) >= 2
    first_end = route.steps[1].to
    assert f.name.GetText(f.name) == (first_end.name or "Next step")
    pins = list(
        wow.eval(
            "Bastians:QueryLayer('route.path', { continent = 0, level = 6, minimap = true })"
        ).values()
    )
    next_pins = [p for p in pins if p.nextStep]
    assert len(next_pins) == 1 and round(next_pins[0].wx) == round(first_end.wx)
    assert wow.errors == []


def test_tomtom_takes_over_when_installed_and_the_setting_turns_everything_off(wow: WowRuntime):
    boot(wow)
    wow.load_addon("TomTom")
    wow.execute(f"{R}.To('npc:448')")
    assert wow.eval(f"{A}.IsShown()") is False  # TomTom's arrow, not ours
    wp = wow.eval("TomTom.waypoints[1]")
    assert wp.title == "Hogger" and wp.map == 1429 and wow.eval("#TomTom.waypoints") == 1
    # the place on the map, not nil (Forever 23.10.2026: TomTom failed on x = nil)
    assert 0 <= wp.x <= 1 and 0 <= wp.y <= 1
    assert wow.eval(f"{A}.TomTomWaypoint() ~= nil") is True
    # a route change with the same target keeps the waypoint; a new target replaces it
    wow.execute(
        "Bastians:Fire('BASTIANS_ROUTE_CHANGED', Bastians:GetModule('Route').Route.Active())"
    )
    assert wow.eval("#TomTom.waypoints") == 1
    move_player(wow, 0.42, 0.65)
    wow.execute(f"{R}.To('flightpath:2')")
    assert (
        wow.eval("#TomTom.waypoints") == 1
        and wow.eval("TomTom.waypoints[1].title") == "Stormwind, Elwynn"
    )
    # the route cleared: the waypoint goes
    wow.slash("/broute clear")
    assert wow.eval("#TomTom.waypoints") == 0 and wow.eval(f"{A}.TomTomWaypoint()") is None
    # TomTom's arrow declined: the own arrow again
    wow.execute(f"{MOD}.db.profile.arrowTomTom = false")
    wow.execute(f"{R}.To('npc:448')")
    assert wow.eval(f"{A}.IsShown()") is True and wow.eval("#TomTom.waypoints") == 0
    # the arrow setting off: nothing
    wow.execute(f"{MOD}.db.profile.arrow = false")
    wow.execute("Bastians:Fire('BASTIANS_SETTING_CHANGED', 'Route', 'arrow', false)")
    assert wow.eval(f"{A}.IsShown()") is False
    wow.execute(f"{MOD}.db.profile.arrow = true")
    wow.execute("Bastians:Fire('BASTIANS_SETTING_CHANGED', 'Route', 'arrow', true)")
    assert wow.eval(f"{A}.IsShown()") is True
    # the module disabled: the arrow goes
    wow.execute(f"{MOD}:Disable()")
    assert wow.eval(f"{A}.IsShown()") is False
    assert wow.errors == []


def test_a_secret_speed_never_breaks_the_route_ticker(wow: WowRuntime):
    """Forever 70532: 244x "attempt to compare local 'speed' (a secret
    number value)" from Route's speed learning. A secret speed is unknown: nothing learned."""
    boot(wow)
    wow.execute("Mock.unitSpeed = Mock.Secret()")
    wow.execute(f"{R}.To('npc:448')")
    assert wow.eval(f"{R}.Active()") is not None  # the ticker runs once a second
    wow.advance(3.5)
    wow.run_frames(5)
    assert wow.errors == []
    assert [
        line.text for line in wow.eval("Bastians:GetLog()").values() if line.level == "error"
    ] == []


def test_the_arrow_is_coloured_by_the_heading(wow: WowRuntime):
    """(P1): "a real arrow, as TomTom's": green straight ahead, gold
    to the side, red behind."""
    boot(wow)
    heading = f"{A}.Heading"
    assert wow.eval(f"{heading}(0)") == "ahead" and wow.eval(f"{heading}(0.3)") == "ahead"
    assert wow.eval(f"{heading}(1.2)") == "side" and wow.eval(f"{heading}(-1.2)") == "side"
    assert wow.eval(f"{heading}(math.pi)") == "behind"
    assert wow.eval(f"{heading}(2 * math.pi + 0.1)") == "ahead"  # folded
    wow.execute(f"{R}.To('npc:448')")
    f = wow.eval(f"{A}.frame")
    color = f.tex.GetVertexColor(f.tex)[:3]
    assert color in (
        tuple(list(wow.eval(f"{A}.COLORS.{k}").values())[:3]) for k in ("ahead", "side", "behind")
    )
    assert wow.errors == []
