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
