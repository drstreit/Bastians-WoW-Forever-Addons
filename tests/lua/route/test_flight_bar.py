"""The flight bar (route.md "The flight bar", catalog review A4.1, 07.11.2026): while the character
flies, a bar names the flight and counts the time left from the flight time Route measured on an
earlier flight of the pair; without one it counts the time flown and fills nothing; the landing
hides it; the setting; the clear-screen key."""

from harness import WowRuntime

CORE, DATA, ROUTE = "Bastians_Core", "Bastians_Data", "Bastians_Route"
MOD = "Bastians:GetModule('Route')"
F = f"{MOD}.Flight"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA, ROUTE)
    wow.run_frames(5)
    return wow


def take_off(wow: WowRuntime) -> None:
    wow.fire("TAXIMAP_OPENED", 1)  # the mock shows Stormwind (current), Sentinel Hill, Ironforge
    wow.execute("TakeTaxiNode(2)")  # to Sentinel Hill


def land(wow: WowRuntime) -> None:
    wow.execute("Mock.onTaxi = false")
    wow.fire("PLAYER_CONTROL_GAINED")


def text(wow: WowRuntime) -> str:
    return wow.eval(f"{F}.frame.text:GetText()")


def test_the_bar_counts_the_time_flown_and_then_the_time_left(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f"{F}.IsShown()") is False
    # the first flight of the pair: no measured time, the bar counts what was flown, fills nothing
    take_off(wow)
    assert wow.eval(f"{F}.IsShown()") is True
    assert text(wow) == "Stormwind to Sentinel Hill   0:00"
    assert wow.eval(f"{F}.frame.fill:IsShown()") is False
    wow.advance(100)
    wow.run_frames(16)  # the clock moves with Advance, the bar's OnUpdate ticks with frames
    assert text(wow) == "Stormwind to Sentinel Hill   1:40"
    land(wow)
    assert wow.eval(f"{F}.IsShown()") is False
    assert wow.eval("Bastians:GetService('graph'):Learned().taxi['taxinode:2>taxinode:4']") == 100
    # the second flight knows its time: the time left, and the bar fills with the share flown
    take_off(wow)
    assert text(wow) == "Stormwind to Sentinel Hill   1:40 left"
    assert wow.eval(f"{F}.frame.fill:IsShown()") is True
    wow.advance(40)
    wow.run_frames(16)
    assert text(wow) == "Stormwind to Sentinel Hill   1:00 left"
    assert abs(wow.eval(f"{F}.frame.fill:GetWidth()") - 238 * 0.4) < 2
    wow.advance(70)  # a late flight: the count stops at zero, the bar is full
    wow.run_frames(16)
    assert text(wow) == "Stormwind to Sentinel Hill   0:00 left"
    assert round(wow.eval(f"{F}.frame.fill:GetWidth()")) == 238
    land(wow)
    assert wow.eval(f"{F}.IsShown()") is False
    assert wow.errors == []


def test_the_flight_is_the_slot_the_game_took_not_the_nth_of_the_list(wow: WowRuntime):
    # the shape of the Forever dump of 23.10.2026: the current node last, slot 1; every other one
    # sits one place before its slot. Position 2 is not slot 2.
    boot(wow)
    wow.execute(
        """Mock.taxiNodes = {
          { nodeID = 4, name = "Sentinel Hill, Westfall", x = 0.56, y = 0.52, state = 1, slot = 2 },
          { nodeID = 6, name = "Ironforge, Dun Morogh", x = 0.59, y = 0.24, state = 1, slot = 3 },
          { nodeID = 2, name = "Stormwind, Elwynn", x = 0.66, y = 0.47, state = 0, slot = 1 },
        }"""
    )
    take_off(wow)
    assert wow.eval(f"{F}.Current().to") == 4
    assert text(wow) == "Stormwind to Sentinel Hill   0:00"
    land(wow)
    wow.fire("TAXIMAP_OPENED", 1)
    wow.execute("TakeTaxiNode(18)")  # a slot the list leaves out: unknown, no guess
    assert wow.eval(f"{F}.Current()") is None
    assert wow.errors == []


def test_the_legacy_list_is_in_slot_order(wow: WowRuntime):
    boot(wow)
    wow.execute("C_TaxiMap.GetAllTaxiNodes = nil")
    take_off(wow)
    assert wow.eval(f"{F}.Current().to") == 4  # no node id on this path: found by its name
    assert wow.errors == []


def test_without_a_landing_event_the_taxi_flag_ends_the_flight(wow: WowRuntime):
    """Forever 11.11.2026 (owner): "I flew from stormwind to sentinel hill and the timer never
    went away and kept counting". Forever fires no PLAYER_CONTROL_GAINED at a landing
    (forever-api.md, P7, measured 21.10.2026), so no flight time had ever been learned there
    either. While a flight is in progress a ticker asks whether the character is still on the
    taxi; it runs at no other time."""
    boot(wow)
    learned = "Bastians:GetService('graph'):Learned().taxi['taxinode:2>taxinode:4']"
    take_off(wow)
    wow.advance(80)
    wow.fire("PLAYER_CONTROL_GAINED")  # Forever's event, if it comes, comes while still flying
    wow.run_frames(4)
    assert wow.eval(f"{F}.IsShown()") is True
    wow.execute("Mock.onTaxi = false")  # the landing: no event says so
    wow.advance(1)
    assert wow.eval(f"{F}.IsShown()") is False and wow.eval(f"{F}.Current()") is None
    assert 80 <= wow.eval(learned) <= 81
    # on the ground nothing ticks and nothing is learned again
    wow.advance(600)
    assert 80 <= wow.eval(learned) <= 81
    # a flight that never began (no money, the map closed) is given up, and times nothing
    wow.fire("TAXIMAP_OPENED", 1)
    wow.execute("TakeTaxiNode(3); Mock.onTaxi = false")  # the hook ran, the character stayed
    assert wow.eval(f"{F}.IsShown()") is True
    wow.advance(20)
    assert wow.eval(f"{F}.IsShown()") is False and wow.eval(f"{F}.Current()") is None
    assert wow.eval("Bastians:GetService('graph'):Learned().taxi['taxinode:2>taxinode:6']") is None
    # the module switched off in the air: no bar, no ticker, nothing learned at the landing
    take_off(wow)
    wow.advance(30)
    wow.execute(f"{MOD}:Disable()")
    wow.execute("Mock.onTaxi = false")
    wow.advance(5)
    assert 80 <= wow.eval(learned) <= 81
    assert wow.errors == []


def test_a_stop_on_the_way_keeps_the_bar_and_the_setting_and_the_key_hide_it(wow: WowRuntime):
    boot(wow)
    take_off(wow)
    wow.advance(30)
    wow.fire("PLAYER_CONTROL_GAINED")  # a stop on a multi-hop flight: still on the taxi
    assert wow.eval(f"{F}.IsShown()") is True
    # the clear-screen key hides it and gives it back
    wow.execute("Bastians:Fire('BASTIANS_SUITE_HIDDEN', true)")
    assert wow.eval(f"{F}.IsShown()") is False
    wow.execute("Bastians:Fire('BASTIANS_SUITE_HIDDEN', false)")
    assert wow.eval(f"{F}.IsShown()") is True
    land(wow)
    # the setting off: no bar on the next flight
    wow.execute(f"{MOD}.db.profile.flightBar = false")
    take_off(wow)
    assert wow.eval(f"{F}.IsShown()") is False
    assert wow.eval(f"{F}.Current() ~= nil") is True  # the flight is still measured
    land(wow)
    assert wow.errors == []
