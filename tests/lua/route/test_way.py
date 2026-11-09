"""The /way command (route.md "The /way command", ADR 0062): the suite answers it when no other addon
does and on the player's word when one does; a line is parsed as TomTom's format, a macro's lines
are one route in their order, and a running route is replaced or added to."""

import sys
from pathlib import Path

from harness import WowRuntime

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "data"))
from test_graph_network import SETUP
from test_navnet_search import lua_pack

CORE, DATA, MAP, ROUTE = "Bastians_Core", "Bastians_Data", "Bastians_Map", "Bastians_Route"
MOD = "Bastians:GetModule('Route')"
R = f"{MOD}.Route"
WAY = f"{MOD}.Way"
WIN = f"{MOD}.Window"
TOMTOM = "SLASH_TOMTOM_WAY1 = '/way'; SlashCmdList.TOMTOM_WAY = function(m) Test_tomtom = m end"


def boot(wow: WowRuntime, *before: str) -> WowRuntime:
    wow.execute(SETUP)
    for code in before:
        wow.execute(code)
    wow.start(CORE, DATA, MAP, ROUTE)
    wow.run_frames(5)
    wow.execute(lua_pack())
    wow.execute("Bastians.Deliver()")
    return wow


def parsed(wow: WowRuntime, line: str):
    return wow.eval(f"{WAY}.Parse([[{line}]])")


def flush(wow: WowRuntime) -> None:
    wow.advance(0.2)
    wow.run_frames(30)


def world_of(wow: WowRuntime, map_id: int, x: float, y: float):
    return wow.eval(f"{{ Bastians.Coords.ToWorld({map_id}, {x}, {y}) }}")


def test_the_forms_of_a_line_are_parsed(wow: WowRuntime):
    boot(wow)
    p = parsed(wow, "Elwynn Forest 42.5 65 The old mill")
    assert (p.zone, p.x, p.y, p.desc) == ("Elwynn Forest", 0.425, 0.65, "The old mill")
    p = parsed(wow, "42,5 65,5")  # the German separator
    assert p.zone is None and (p.x, p.y) == (0.425, 0.655) and p.desc is None
    p = parsed(wow, "42.5, 65.5")
    assert (p.x, p.y) == (0.425, 0.655)
    p = parsed(wow, "42.5,65.5")
    assert (p.x, p.y) == (0.425, 0.655)
    p = parsed(wow, "#1429 42 65")
    assert (p.zone, p.x, p.y) == ("#1429", 0.42, 0.65)
    assert parsed(wow, "reset").cmd == "reset" and parsed(wow, "CLEAR").cmd == "reset"
    assert parsed(wow, "list").cmd == "list"
    for bad in ("", "Elwynn", "42", "Elwynn 142 3", "Elwynn 42 x"):
        assert parsed(wow, bad).cmd == "usage", bad
    assert wow.errors == []


def test_zones_match_whole_part_and_english_and_say_what_is_wrong(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f"({WAY}.FindZone('Elwynn Forest'))") == 1429
    assert wow.eval(f"({WAY}.FindZone('elwynnforest'))") == 1429
    assert wow.eval(f"({WAY}.FindZone('elwy'))") == 1429
    assert wow.eval(f"({WAY}.FindZone('#1429'))") == 1429
    missing = wow.eval(f"{{ {WAY}.FindZone('Nowhere') }}")
    assert missing[1] is None or len(missing) == 0 or missing[2] == "No zone called Nowhere."
    assert wow.eval(f"select(2, {WAY}.FindZone('Nowhere'))") == "No zone called Nowhere."
    assert wow.eval(f"select(2, {WAY}.FindZone('#999999'))") == "No zone called #999999."
    assert wow.errors == []


def test_several_matching_zones_are_named_and_nothing_is_set(wow: WowRuntime):
    boot(wow)
    wow.execute(
        "local d = Bastians:GetService('data'); local each, get = d.Each, d.Get; "
        "d.Each = function(s, t) if t == 'zone' then return { 1429, 9000 } end return each(s, t) end; "
        "d.Get = function(s, t, id) if t == 'zone' then "
        "return ({ [1429] = { name = 'Forest One', mapType = 3 }, "
        "[9000] = { name = 'Forest Two', mapType = 3 } })[id] end return get(s, t, id) end"
    )
    why = wow.eval(f"select(2, {WAY}.FindZone('forest'))")
    assert why == "Several zones match forest: Forest One, Forest Two"
    wow.slash("/way forest 42 65")
    flush(wow)
    assert wow.eval(f"{R}.Active()") is None
    assert "Several zones match" in wow.chat[-1]
    assert wow.errors == []


def test_a_client_in_another_language_also_finds_the_english_name(wow: WowRuntime):
    boot(wow)
    wow.execute(
        "local d = Bastians:GetService('data'); local get = d.Get; "
        "d.Get = function(s, t, id) local r = get(s, t, id); "
        "if t == 'zone' and id == 1429 then "
        "return { name = 'Wald von Elwynn', nameEN = 'Elwynn Forest', mapType = 3 } end "
        "return r end"
    )
    assert wow.eval(f"({WAY}.FindZone('Elwynn Forest'))") == 1429
    assert wow.eval(f"({WAY}.FindZone('Wald von Elwynn'))") == 1429
    assert wow.errors == []


def test_without_tomtom_the_suite_answers_and_sets_the_pin_and_the_route(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f"{WAY}.owner") is None
    wow.slash("/way Elwynn Forest 42 65 Test place")
    assert wow.eval(f"{R}.Active()") is None  # a burst may still be coming
    flush(wow)
    route = wow.eval(f"{R}.Active()")
    assert route is not None and route.goal.name == "Test place", wow.chat
    expected = world_of(wow, 1429, 0.42, 0.65)
    assert (route.goal.wx, route.goal.wy) == (expected[2], expected[3])
    pin = wow.eval("Bastians:GetService('waypoint'):Get()")
    assert (pin.wx, pin.wy, pin.label) == (expected[2], expected[3], "Test place")
    assert wow.errors == []


def test_without_a_zone_the_players_map_is_meant(wow: WowRuntime):
    boot(wow)
    wow.slash("/way 42 65")
    flush(wow)
    expected = world_of(wow, 9000, 0.42, 0.65)
    route = wow.eval(f"{R}.Active()")
    assert route is not None and (route.goal.wx, route.goal.wy) == (expected[2], expected[3])
    assert "42.0 65.0" in route.goal.name
    assert wow.errors == []


def test_with_tomtom_it_stays_tomtoms_until_the_button_and_back_at_once(wow: WowRuntime):
    boot(wow, TOMTOM)
    assert wow.eval(f"{WAY}.owner") == "TOMTOM_WAY" and wow.eval(f"{WAY}.OwnerName()") == "TomTom"
    assert wow.eval("SlashCmdList.BASTIANSWAY") is None
    original = "Test_original = SlashCmdList.TOMTOM_WAY"
    wow.execute(original)
    assert wow.eval("SlashCmdList.TOMTOM_WAY == Test_original")  # untouched until asked
    wow.slash("/way 42 65")
    flush(wow)
    assert wow.eval("Test_tomtom") == "42 65" and wow.eval(f"{R}.Active()") is None
    # the player hands it over, and the client's cached handler goes
    wow.execute("hash_SlashCmdList = { ['/WAY'] = function() end }")
    wow.execute(f"{WAY}.SetOverOwner(true); Test_tomtom = nil")
    assert wow.eval("hash_SlashCmdList['/WAY']") is None
    wow.slash("/way 42 65")
    flush(wow)
    assert wow.eval("Test_tomtom") is None and wow.eval(f"{R}.Active()") is not None, (
        wow.chat,
        wow.errors,
    )
    # and back
    wow.execute(f"{WAY}.SetOverOwner(false); {R}.Clear()")
    wow.slash("/way 50 50")
    flush(wow)
    assert wow.eval("Test_tomtom") == "50 50" and wow.eval(f"{R}.Active()") is None
    assert wow.errors == []


def test_the_handover_survives_a_login(wow: WowRuntime):
    boot(wow, TOMTOM)
    wow.execute(
        f"{MOD}.db.profile.wayOverOwner = true; {MOD}:Disable(); {MOD}:Enable(); Test_tomtom = nil"
    )
    wow.slash("/way 42 65")
    flush(wow)
    assert wow.eval("Test_tomtom") is None and wow.eval(f"{R}.Active()") is not None, (
        wow.chat,
        wow.errors,
    )
    assert wow.errors == []


def test_a_macros_lines_are_one_route_in_their_order(wow: WowRuntime):
    boot(wow)
    for line in ("#9000 42.5 10 First", "#9000 42.5 30 Second", "#9000 52.5 10 Third"):
        wow.slash(f"/way {line}")
    flush(wow)
    route = wow.eval(f"{R}.Active()")
    assert route is not None and route.tour is not None, wow.chat
    assert [s.name for s in route.tour.stops.values()] == ["First", "Second", "Third"]
    assert wow.errors == []


def test_new_route_replaces_and_add_puts_the_place_behind(wow: WowRuntime):
    boot(wow)
    wow.slash("/way #9000 42.5 10 First")
    flush(wow)
    wow.slash("/way #9000 42.5 30 Second")
    flush(wow)
    assert wow.eval(f"{R}.Active().goal.name") == "Second"  # the default: a new route
    wow.execute(f"{MOD}.db.profile.wayAdd = true")
    wow.slash("/way #9000 52.5 10 Third")
    flush(wow)
    assert [s.name for s in wow.eval(f"{R}.Active().tour.stops").values()] == ["Second", "Third"]
    wow.slash("/way #9000 65 10 Fourth")
    flush(wow)
    assert [s.name for s in wow.eval(f"{R}.Active().tour.stops").values()] == [
        "Second",
        "Third",
        "Fourth",
    ]
    wow.slash("/way list")
    assert wow.chat[-1].endswith("3. Fourth")
    wow.slash("/way reset")
    assert wow.eval(f"{R}.Active()") is None
    assert wow.eval("Bastians:GetService('waypoint'):Get()") is None
    assert wow.errors == []


def test_add_with_nothing_running_is_a_plain_route_and_a_ghosts_way_is_not_added_to(
    wow: WowRuntime,
):
    boot(wow)
    wow.execute(f"{MOD}.db.profile.wayAdd = true")
    wow.slash("/way #9000 42.5 10 Only")
    flush(wow)
    route = wow.eval(f"{R}.Active()")
    assert route.tour is None and route.goal.name == "Only"
    wow.execute(f"{R}.Active().onFoot = true")
    wow.slash("/way #9000 42.5 30 Next")
    flush(wow)
    assert wow.eval(f"{R}.Active().tour") is None
    assert wow.errors == []


def test_add_to_route_is_offered_while_a_route_runs(wow: WowRuntime):
    boot(wow)
    ctx = "{ point = { 0, 100, 150, 'Spot' } }"
    assert wow.eval(f"Bastians:GetActions('zone:1429', {ctx})") is not None

    def ids():
        return [a.id for a in wow.eval(f"Bastians:GetActions('zone:1429', {ctx})").values()]

    assert "route.addhere" not in ids()
    wow.eval(f"{R}.ToPoint(0, 100, -300, 'Goal')")
    wow.run_frames(30)
    assert "route.addhere" in ids()
    wow.execute(f"Bastians:RunAction('route.addhere', 'zone:1429', {ctx})")
    wow.run_frames(30)
    stops = wow.eval(f"{R}.Active().tour.stops")
    assert [s.name for s in stops.values()] == ["Goal", "Spot"]
    assert wow.errors == []


def test_the_windows_buttons_follow_who_answers(wow: WowRuntime):
    boot(wow, TOMTOM)
    wow.execute(f"{WIN}.Open()")
    owner, mode = f"{WIN}.wayOwnerButton", f"{WIN}.wayModeButton"
    assert wow.eval(f"{owner}:IsShown()") is True
    assert wow.eval(f"{owner}.spec.label") == "/way: TomTom"
    assert wow.eval(f"{mode}:IsShown()") is False  # TomTom answers: our mode means nothing
    wow.execute(f"{owner}:GetScript('OnClick')({owner})")
    assert wow.eval(f"{owner}.spec.label") == "/way: Route"
    assert wow.eval(f"{mode}:IsShown()") is True
    assert wow.eval(f"{mode}.spec.label") == "/way: New route"
    wow.execute(f"{mode}:GetScript('OnClick')({mode})")
    assert wow.eval(f"{mode}.spec.label") == "/way: Add to route"
    assert wow.eval(f"{MOD}.db.profile.wayAdd") is True
    assert wow.errors == []


def test_without_tomtom_the_window_has_only_the_mode(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{WIN}.Open()")
    assert wow.eval(f"{WIN}.wayOwnerButton:IsShown()") is False
    assert wow.eval(f"{WIN}.wayModeButton:IsShown()") is True
    assert wow.errors == []


def test_a_disabled_route_gives_the_command_up(wow: WowRuntime):
    boot(wow)
    assert wow.eval("SlashCmdList.BASTIANSWAY") is not None
    wow.execute(f"{MOD}:Disable()")
    assert wow.eval("SlashCmdList.BASTIANSWAY") is None
    assert wow.eval("SLASH_BASTIANSWAY1") is None
    wow.execute(f"{MOD}:Enable()")
    assert wow.eval("SLASH_BASTIANSWAY1") == "/way"
    assert wow.errors == []


def test_route_alone_without_the_map(wow: WowRuntime):
    wow.execute(SETUP)
    wow.start(CORE, DATA, ROUTE)
    wow.run_frames(5)
    wow.slash("/way #1429 42 65 Solo")
    flush(wow)
    assert wow.eval(f"{R}.Active().goal.name") == "Solo"
    assert wow.errors == []
