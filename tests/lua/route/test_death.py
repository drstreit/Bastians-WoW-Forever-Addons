"""The place of death (route.md "The place of death", R26.8): the corpse and the earlier deaths are
remembered, a ghost gets the way back, life again clears it, the map layer shows them; the client's
corpse position wins over the remembered one; a client without the events loses only the feature."""

from harness import WowRuntime

CORE, DATA, MAP, ROUTE = "Bastians_Core", "Bastians_Data", "Bastians_Map", "Bastians_Route"
MOD = "Bastians:GetModule('Route')"
DEATH = f"{MOD}.Death"
R = f"{MOD}.Route"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, MAP, ROUTE)))
    wow.run_frames(5)
    return wow


def die_and_release(wow: WowRuntime, graveyard=(0.30, 0.40)) -> None:
    wow.execute("Mock.deathState = 'dead'")
    wow.fire("PLAYER_DEAD")
    wow.execute(
        f"Mock.deathState = 'ghost'; Mock.playerMapPos = {{ x = {graveyard[0]}, y = {graveyard[1]} }}"
    )
    wow.fire("PLAYER_ALIVE")


def test_a_death_is_remembered_and_a_ghost_gets_the_way_back(wow: WowRuntime):
    boot(wow)
    here = wow.eval("{ Bastians.Coords.Player() }")
    die_and_release(wow)
    corpse = wow.eval(f"{DEATH}.Corpse()")
    assert (corpse.continent, corpse.wx, corpse.wy) == (here[1], here[2], here[3])
    assert corpse.exact is None  # the client gave no corpse position: the remembered place
    assert wow.eval(f"#{DEATH}.List()") == 1
    assert wow.eval(f"{R}.Active()") is None  # a second for the graveyard's position to settle
    wow.advance(1.1)
    route = wow.eval(f"{R}.Active()")
    assert route is not None, (wow.chat, wow.errors)
    assert (route.goal.wx, route.goal.wy) == (corpse.wx, corpse.wy)
    assert route.goal.name == "your corpse"
    # the corpse reclaimed: alive again, the route and the corpse are gone, the death stays listed
    wow.execute("Mock.deathState = 'alive'")
    wow.fire("PLAYER_UNGHOST")
    assert wow.eval(f"{R}.Active()") is None
    assert wow.eval(f"{DEATH}.Corpse()") is None
    assert wow.eval(f"#{DEATH}.List()") == 1
    assert wow.errors == []


def test_the_client_corpse_position_wins_and_the_setting_switches_the_way_back_off(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{MOD}.db.profile.corpseRoute = false")
    wow.execute("Mock.corpse = { map = 1429, x = 0.5, y = 0.5 }")
    die_and_release(wow)
    wow.advance(1.1)
    assert wow.eval(f"{R}.Active()") is None  # switched off
    corpse = wow.eval(f"{DEATH}.Corpse()")
    expected = wow.eval("{ Bastians.Coords.ToWorld(1429, 0.5, 0.5) }")
    assert corpse.exact is True and (corpse.wx, corpse.wy) == (expected[2], expected[3])
    # by hand: /broute corpse
    wow.slash("/broute corpse")
    route = wow.eval(f"{R}.Active()")
    assert route is not None and (route.goal.wx, route.goal.wy) == (expected[2], expected[3])
    assert wow.errors == []


def test_the_map_layer_shows_the_corpse_and_the_earlier_deaths(wow: WowRuntime):
    boot(wow)
    for pos in ((0.42, 0.65), (0.45, 0.60), (0.48, 0.55)):
        wow.execute(
            f"Mock.deathState = 'dead'; Mock.playerMapPos = {{ x = {pos[0]}, y = {pos[1]} }}"
        )
        wow.fire("PLAYER_DEAD")
        wow.execute("Mock.deathState = 'alive'")
        wow.fire("PLAYER_UNGHOST")
    wow.execute("Mock.deathState = 'dead'; Mock.playerMapPos = { x = 0.40, y = 0.70 }")
    wow.fire("PLAYER_DEAD")
    view = "{ continent = 0, x1 = -50000, y1 = -50000, x2 = 50000, y2 = 50000, level = 3 }"
    pins = list(wow.eval(f"Bastians:QueryLayer('route.deaths', {view})").values())
    assert [p.label for p in pins] == ["Your corpse", "Died here", "Died here", "Died here"]
    assert pins[0].size > pins[1].size and pins[0].cluster is False
    assert pins[0].icon == wow.eval("Bastians.UI.IconTexture('grave')")
    card = pins[0].card(pins[0])
    assert card.title == "Your corpse" and card.hint == "Click for the way back"
    assert card.lines[1].text == "Died 0 min ago"
    # a click on the corpse plans the way back
    wow.execute(f"local ps = Bastians:QueryLayer('route.deaths', {view}); ps[1].onClick(ps[1])")
    assert wow.eval(f"{R}.Active()") is not None
    # another continent's view: nothing
    other = view.replace("continent = 0", "continent = 1")
    assert len(wow.eval(f"Bastians:QueryLayer('route.deaths', {other})")) == 0
    # ten deaths at most
    for _ in range(12):
        wow.fire("PLAYER_DEAD")
    assert wow.eval(f"#{DEATH}.List()") == 10
    assert wow.errors == []


def test_alive_after_a_login_the_old_corpse_is_gone(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.deathState = 'dead'")
    wow.fire("PLAYER_DEAD")
    assert wow.eval(f"{DEATH}.Corpse()") is not None
    wow.execute("Mock.deathState = 'alive'")
    wow.fire("PLAYER_ENTERING_WORLD")
    assert wow.eval(f"{DEATH}.Corpse()") is None
    assert wow.errors == []


def test_without_the_map_and_without_the_events_route_still_works(wow: WowRuntime):
    wow.execute(
        "Mock.unknownEvents = { PLAYER_DEAD = true, PLAYER_ALIVE = true, PLAYER_UNGHOST = true }"
    )
    boot(wow, CORE, DATA, ROUTE)
    assert wow.eval(f"{MOD}:IsEnabled()") is True
    die_and_release(wow)  # nobody listens: the feature is gone, the addon is not
    wow.advance(1.1)
    assert wow.eval(f"{DEATH}.Corpse()") is None
    wow.slash("/broute corpse")
    assert "No corpse to go back to." in wow.chat[-1]
    assert wow.errors == []


def route_away(wow: WowRuntime) -> None:
    """A route somewhere else is running, as when the owner died on 08.11.2026."""
    wow.eval(f"{R}.ToPoint(0, -9000, 400, 'somewhere else')")
    wow.run_frames(5)
    assert wow.eval(f"{R}.Active().goal.name") == "somewhere else"


def goal_name(wow: WowRuntime):
    return wow.eval(f"{R}.Active() and {R}.Active().goal.name")


def arrow_shown(wow: WowRuntime):
    return wow.eval(f"{MOD}.Arrow.IsShown()")


def test_the_old_routes_arrow_goes_at_the_death_and_the_way_back_replaces_it(wow: WowRuntime):
    boot(wow)
    route_away(wow)
    assert arrow_shown(wow) is True
    wow.execute("Mock.deathState = 'dead'")
    wow.fire("PLAYER_DEAD")
    assert goal_name(wow) == "somewhere else"  # brought back before the release: it is still there
    assert arrow_shown(wow) is False
    wow.execute("Mock.deathState = 'ghost'; Mock.playerMapPos = { x = 0.30, y = 0.40 }")
    wow.fire("PLAYER_ALIVE")
    wow.advance(1.1)
    wow.run_frames(5)
    assert goal_name(wow) == "your corpse", wow.chat
    assert arrow_shown(wow) is True
    assert wow.errors == []


def test_brought_back_before_the_release_the_old_route_points_again(wow: WowRuntime):
    boot(wow)
    route_away(wow)
    wow.execute("Mock.deathState = 'dead'")
    wow.fire("PLAYER_DEAD")
    assert arrow_shown(wow) is False
    wow.execute("Mock.deathState = 'alive'")
    wow.fire("PLAYER_ALIVE")
    assert goal_name(wow) == "somewhere else" and arrow_shown(wow) is True
    assert wow.eval(f"{DEATH}.Corpse()") is None
    assert wow.errors == []


def test_the_ghost_flag_coming_after_player_alive_still_gets_the_way_back(wow: WowRuntime):
    """The order on the real client is not measured: the state decides, not the event."""
    boot(wow)
    route_away(wow)
    wow.execute("Mock.deathState = 'dead'")
    wow.fire("PLAYER_DEAD")
    wow.fire("PLAYER_ALIVE")  # the release, and the client still says "dead"
    wow.advance(1.1)
    assert goal_name(wow) == "somewhere else"
    wow.execute("Mock.deathState = 'ghost'; Mock.playerMapPos = { x = 0.30, y = 0.40 }")
    wow.advance(2.1)  # no event at all: the watch sees the ghost
    wow.run_frames(5)
    assert goal_name(wow) == "your corpse", wow.chat
    assert wow.errors == []


def test_without_any_death_event_a_running_route_notices_the_ghost(wow: WowRuntime):
    wow.execute(
        "Mock.unknownEvents = { PLAYER_DEAD = true, PLAYER_ALIVE = true, PLAYER_UNGHOST = true }"
    )
    boot(wow)
    route_away(wow)
    wow.execute(
        "Mock.deathState = 'ghost'; Mock.playerMapPos = { x = 0.30, y = 0.40 }; "
        "Mock.corpse = { map = 1429, x = 0.5, y = 0.5 }"
    )
    wow.advance(3.1)
    wow.run_frames(5)
    assert goal_name(wow) == "your corpse", wow.chat
    # the corpse is remembered from the client's answer, and life ends it without an event
    assert wow.eval(f"#{DEATH}.List()") == 1
    wow.execute("Mock.deathState = 'alive'; Mock.corpse = nil")
    wow.advance(2.1)
    assert wow.eval(f"{R}.Active()") is None
    assert wow.eval(f"{DEATH}.Corpse()") is None
    assert wow.errors == []


def test_a_route_the_ghost_chooses_after_the_way_back_stays(wow: WowRuntime):
    boot(wow)
    die_and_release(wow)
    wow.advance(1.1)
    wow.run_frames(5)
    assert goal_name(wow) == "your corpse"
    wow.advance(1.1)  # the watch sees it set, and ends
    route_away(wow)
    wow.advance(3.1)
    wow.run_frames(5)
    assert goal_name(wow) == "somewhere else" and arrow_shown(wow) is True
    assert wow.errors == []


def test_a_cleared_way_back_is_not_forced_again(wow: WowRuntime):
    boot(wow)
    die_and_release(wow)
    wow.advance(2.2)
    wow.run_frames(5)
    assert goal_name(wow) == "your corpse"
    wow.eval(f"{R}.Clear()")
    wow.advance(4)
    assert wow.eval(f"{R}.Active()") is None
    assert wow.errors == []


def test_a_loading_screen_or_reload_as_a_ghost_plans_the_way_back(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.deathState = 'dead'")
    wow.fire("PLAYER_DEAD")
    wow.execute("Mock.deathState = 'ghost'; Mock.playerMapPos = { x = 0.30, y = 0.40 }")
    wow.fire("PLAYER_ENTERING_WORLD")
    wow.advance(2.1)
    wow.run_frames(5)
    assert goal_name(wow) == "your corpse", wow.chat
    assert wow.errors == []


def test_the_way_back_is_on_foot_and_a_reroute_keeps_it_so(wow: WowRuntime):
    boot(wow)
    die_and_release(wow)
    wow.advance(2.2)
    wow.run_frames(5)
    assert wow.eval(f"{R}.Active().onFoot") is True
    assert wow.eval(f"{R}.Active().alternatives") is None  # no kinds: walking is the only one
    assert wow.eval(f"{R}.Replan('test')") is True
    wow.run_frames(5)
    assert wow.eval(f"{R}.Active().onFoot") is True
    assert not any(
        wow.eval(f"{R}.Active().steps[{i + 1}].mode") in ("fly", "hearth", "teleport", "portal")
        for i in range(wow.eval(f"#{R}.Active().steps"))
    )
    assert wow.errors == []


def test_the_corpse_is_the_loudest_mark_and_comes_on_with_a_switched_off_layer(wow: WowRuntime):
    boot(wow)
    wow.execute(
        "Test_shown = {}; local fire = Bastians.Fire; Bastians.Fire = function(self, m, id, how, ...) "
        "if id == 'route.deaths' then Test_shown[#Test_shown + 1] = how or 'plain' end "
        "return fire(self, m, id, how, ...) end"
    )
    wow.execute("Mock.deathState = 'dead'")
    wow.fire("PLAYER_DEAD")
    assert "show" in list(wow.eval("Test_shown").values())
    view = "{ continent = 0, x1 = -50000, y1 = -50000, x2 = 50000, y2 = 50000, level = 3 }"
    pin = wow.eval(f"Bastians:QueryLayer('route.deaths', {view})[1]")
    assert pin.size == wow.eval(f"{DEATH}.CORPSE_SIZE") and pin.size > 24  # a route's goal is 24
    assert wow.eval(
        f"Bastians:QueryLayer('route.deaths', {view})[1].color == Bastians.UI.Style.C.waypointLoud"
    )
    assert wow.errors == []


def test_the_setting_off_leaves_the_old_route_and_arrow_alone(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{MOD}.db.profile.corpseRoute = false")
    route_away(wow)
    die_and_release(wow)
    wow.advance(2.2)
    assert goal_name(wow) == "somewhere else" and arrow_shown(wow) is True
    assert wow.errors == []


def test_a_report_says_what_the_suite_sees(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.deathState = 'dead'")
    wow.fire("PLAYER_DEAD")
    wow.slash("/broute death")
    assert "state dead, remembered yes" in wow.chat[-1]
    assert wow.errors == []


def test_with_the_events_but_without_the_map(wow: WowRuntime):
    boot(wow, CORE, DATA, ROUTE)
    die_and_release(wow)
    wow.advance(1.1)
    assert wow.eval(f"{DEATH}.Corpse()") is not None
    assert wow.eval(f"{R}.Active()") is not None
    assert wow.errors == []
