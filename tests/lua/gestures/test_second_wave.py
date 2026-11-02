"""The three wedges that waited (plan-second-wave.md S6): Route's route.home, the Orbiter's
voice.heard and Quests' quests.tracker exist, light the Gestures wedges, do their work from the
ring, and show in no entity menu."""

from harness import WowRuntime
from test_gestures import CORE, DATA, GESTURES, QUESTS, ROUTE, VOICE, R, errors

SPOKEN = ("Spoken", "Spoken_Quests", "Spoken_Places", "Spoken_Readables", "Spoken_NPCs")


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA, *SPOKEN, QUESTS, ROUTE, VOICE, GESTURES)
    wow.run_frames(10)
    wow.advance(0.5)
    return wow


def test_the_three_actions_exist_for_the_ring_only(wow: WowRuntime):
    boot(wow)
    for action in ("route.home", "voice.heard", "quests.tracker"):
        assert wow.eval(f"Bastians:GetAction('{action}') ~= nil"), action
    # no entity menu offers them: the ring's source is the only context they answer
    menu = [
        a.id for a in wow.eval("Bastians:GetActions('zone:1429', { source = 'test' })").values()
    ]
    assert not any(a in menu for a in ("route.home", "voice.heard", "quests.tracker"))
    wow.execute(f"{R}.SetPage(3)")
    wow.execute(f"{R}.Key('down')")
    items = wow.eval(f"{R}.kit.items")
    labels = {items[i].label: items[i] for i in range(1, 9)}
    assert labels["Route home"].disabled is None
    assert labels["Mark heard"].disabled is None
    assert labels["Toggle the tracker"].disabled is None
    assert errors(wow) == []


def test_mark_heard_marks_the_place_here_and_unmarks_it_again(wow: WowRuntime):
    boot(wow)
    V = "Bastians:GetModule('Voice').Voice"
    line = wow.eval(f"{V}.HereLine()")
    assert line is not None and line.key
    assert wow.eval(f"{V}.IsHeard('{line.key}')") in (False, None)
    wow.execute(f"{R}.SetPage(3)")
    wow.execute(f"{R}.Key('down')")
    items = wow.eval(f"{R}.kit.items")
    heard = next(i for i in range(1, 9) if items[i].label == "Mark heard")
    assert wow.eval(f"{R}.Fire({heard})") is True
    assert wow.eval(f"{V}.IsHeard('{line.key}')") is True
    wow.execute(f"{R}.Key('down')")
    assert wow.eval(f"{R}.Fire({heard})") is True
    assert wow.eval(f"{V}.IsHeard('{line.key}')") in (False, None)
    assert errors(wow) == []


def test_toggle_the_tracker_from_the_ring(wow: WowRuntime):
    boot(wow)
    T = "Bastians:GetModule('Quests').Tracker"
    before = wow.eval(f"{T}.IsShown()")
    wow.execute(f"{R}.SetPage(3)")
    wow.execute(f"{R}.Key('down')")
    items = wow.eval(f"{R}.kit.items")
    tracker = next(i for i in range(1, 9) if items[i].label == "Toggle the tracker")
    assert wow.eval(f"{R}.Fire({tracker})") is True
    wow.run_frames(3)
    assert wow.eval(f"{T}.IsShown()") != before
    assert errors(wow) == []


def test_route_home_routes_to_the_hearths_area(wow: WowRuntime):
    boot(wow)
    Route = "Bastians:GetModule('Route').Route"
    wow.execute("Mock.bindLocation = 'Nowhere Such'")
    assert wow.eval(f"{Route}.HomeRef()") is None
    # the first area of the player's zone in the fixture world is the hearth's
    name = wow.eval(
        "(function() local d = Bastians:GetService('data') for id in d:ByZone('area', 1429) do"
        " local r = d:Get('area', id) if r and r.name then return r.name end end end)()"
    )
    assert isinstance(name, str)
    wow.execute(f"Mock.bindLocation = [[{name}]]")
    ref = wow.eval(f"{Route}.HomeRef()")
    assert isinstance(ref, str) and ref.startswith("area:")
    assert (
        wow.eval("Bastians:RunAction('route.home', 'zone:1429', { source = 'gestures' })") is True
    )
    assert errors(wow) == []
