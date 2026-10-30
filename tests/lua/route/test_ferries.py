"""Departure times (route.md "Departure times", R26.6): the fixture ferry Elwynn - Ratchet (loop
480 s, it leaves Elwynn 60 s and Ratchet 240 s into the loop, 60 s at a dock) from the generator's
world; its loop learned when the character is carried away from the dock, shared, taken from a
friend when newer; the exact wait in a planned route and the live "leaves in" of the step list."""

import sys
from pathlib import Path

from harness import WowRuntime

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "data"))
from test_graph_network import SETUP, two_continents_pack

CORE, DATA, MAP, ROUTE = "Bastians_Core", "Bastians_Data", "Bastians_Map", "Bastians_Route"
MOD = "Bastians:GetModule('Route')"
F = f"{MOD}.Ferries"
R = f"{MOD}.Route"
BOAT = "boat-elwynn-ratchet"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.execute(SETUP)
    wow.start(CORE, DATA, MAP, ROUTE)
    wow.run_frames(5)
    wow.execute('Bastians:GetService("data"):LoadPack("world")')
    wow.execute(two_continents_pack())
    wow.execute("Bastians.Deliver()")
    return wow


def test_the_next_departure_from_a_learned_loop(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f"{F}.NextDeparture('{BOAT}', 1)") is None  # not learned yet
    wow.execute(f"NOW = {F}.Now(); {F}.Learn('{BOAT}', NOW - 100, NOW)")
    assert wow.eval(f"{F}.NextDeparture('{BOAT}', 1)") == 440  # (60 - 100) mod 480
    assert wow.eval(f"{F}.NextDeparture('{BOAT}', 2)") == 140  # 240 - 100
    assert wow.eval(f"{F}.NextDeparture('{BOAT}', 2, NOW + 200)") == 420
    # an older loop never replaces a newer one; an unknown transport is nothing
    assert wow.eval(f"{F}.Learn('{BOAT}', 5, NOW - 50)") is False
    assert wow.eval(f"{F}.Learn('no-such-boat', 5, NOW)") is False
    assert wow.errors == []


def test_carried_away_from_the_dock_the_loop_is_learned_and_shared(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.groupSize = 2; Mock.inGuild = true")
    step = (
        "{ mode = 'boat', from = { continent = 0, wx = -160, wy = -160, transport = "
        f"'{BOAT}', stop = 1 }}, to = {{ continent = 1, wx = -900, wy = -3770 }} }}"
    )
    wow.execute(f"STEP = {step}")
    # waiting at the dock (walking up to it: speed 7) for 25 seconds
    wow.execute(f"{F}.Observe(STEP, {{ continent = 0, wx = -165, wy = -160 }})")
    wow.advance(25)
    wow.execute(f"{F}.Observe(STEP, {{ continent = 0, wx = -165, wy = -161 }})")
    # standing on the boat (speed 0) while it moves 8 yards: carried away, the departure
    wow.execute("Mock.unitSpeed = 0")
    assert wow.eval(f"{F}.Observe(STEP, {{ continent = 0, wx = -173, wy = -160 }})") == BOAT
    cycle0, at = wow.eval(f"{F}.Phase('{BOAT}')")
    assert cycle0 == at - 60  # left Elwynn 60 s into the loop
    assert any("Learned when" in line for line in wow.chat[-2:])
    # the wait at the dock is a learned ride fact of the graph (W11: it rides in the captures)
    waits = wow.eval(f"Bastians:GetService('graph'):Learned().ride['transport:{BOAT}']")
    assert list(waits.values()) == [25]
    wow.advance(2)
    channels = sorted(m.channel for m in wow.eval("Mock.addonMessages").values())
    assert channels == ["GUILD", "PARTY"]
    # walking away from a dock is not a departure
    wow.execute(f"{MOD}.db.global.ferries = {{}}; Mock.unitSpeed = 7")
    wow.execute(f"{F}.Observe(STEP, {{ continent = 0, wx = -165, wy = -160 }})")
    assert wow.eval(f"{F}.Observe(STEP, {{ continent = 0, wx = -175, wy = -160 }})") is None
    assert wow.errors == []


def test_a_friend_s_loop_is_taken_when_newer_and_sane(wow: WowRuntime):
    boot(wow)
    now = wow.eval(f"{F}.Now()")
    ok = f"{{ v = 1, id = '{BOAT}', cycle0 = {now - 1000}, at = {now - 10} }}"
    assert wow.eval(f"{F}.Receive({ok})") is True
    future = f"{{ v = 1, id = '{BOAT}', cycle0 = 1, at = {now + 3600} }}"
    assert wow.eval(f"{F}.Receive({future})") is False
    assert wow.eval(f"{F}.Receive({{ v = 1, id = 'x', cycle0 = 1, at = {now} }})") is False
    assert wow.eval(f"{F}.Receive('nonsense')") is False
    wow.slash("/broute ferries")
    assert any("Elwynn - Ratchet ferry:" in line for line in wow.chat[-3:])
    assert wow.errors == []


def test_a_planned_route_waits_exactly_and_the_step_says_when_it_leaves(wow: WowRuntime):
    boot(wow)
    # the loop started 100 s ago: from the dock (at Elwynn) the boat leaves in 440 s
    wow.execute(f"NOW = {F}.Now(); {F}.Learn('{BOAT}', NOW - 100, NOW)")
    wow.execute(f"{R}.ToPoint(1, 100, -300, 'Far shore')")
    wow.run_frames(10)
    route = wow.eval(f"{R}.Active()")
    boat = next(s for s in route.steps.values() if s.mode == "boat")
    assert boat.exactWait is True and boat.seconds == boat.wait + 120  # the ride Elwynn -> Ratchet
    assert 0 <= boat.wait < 480
    assert abs(route.seconds - sum(s.seconds for s in route.steps.values())) < 1e-6
    w = f"{MOD}.Window"
    wow.execute(f"{w}.Open()")
    rows = [r.text for r in wow.eval(f"{w}.tree.rows").values() if r.text]
    assert any("leaves in" in t for t in rows)
    assert wow.errors == []
