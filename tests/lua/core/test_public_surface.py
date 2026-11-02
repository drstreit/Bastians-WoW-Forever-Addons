"""The common interfaces (plan-second-wave.md S12, "make sure all our addons
support common interfaces and API for other addons or data brokers"): every installed app of the
identity record has a LibDataBroker feed, a slash command, a hub page and API.Open; every service is
read by the public API or named internal with a reason; every public event is documented; the new
calls Known, Speak, Play and Open answer copies or nil."""

import re
from pathlib import Path

from harness import WowRuntime

ROOT = Path(__file__).resolve().parents[3]
DOC = ROOT / "API.md"
API = "Bastians.API"
SUITE = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Map",
    "Bastians_Browser",
    "Bastians_Gold",
    "Bastians_Route",
    "Bastians_Strategies",
    "Bastians_Notes",
    "Bastians_Alts",
    "Bastians_Helpers",
    "Bastians_Voice",
    "Bastians_Chat",
    "Bastians_Gestures",
    "Bastians_Campfire",
)
NO_WINDOW = {"Data"}  # the identity record's apps without a window: no feed, no slash


def apps(wow: WowRuntime) -> list[dict]:
    out = []
    for app in wow.eval("Bastians.UI.Settings.Apps()").values():
        out.append(
            {"module": app.module, "slash": app.slash, "addon": app.addon, "later": app.later}
        )
    return out


def test_every_installed_app_has_its_four_doors(wow: WowRuntime):
    wow.start(*SUITE)
    wow.run_frames(5)
    slashes = set(
        wow.eval(
            "(function() local t = {} for k, v in pairs(_G) do "
            "if type(k) == 'string' and k:match('^SLASH_%u+1$') then t[#t + 1] = v end end "
            "return t end)()"
        ).values()
    )
    seen = 0
    for app in apps(wow):
        name = app["module"]
        if wow.eval(f"Bastians:GetModule('{name}')") is None:
            continue  # not made for this client (Gold and the book: Forever)
        seen += 1
        if name in NO_WINDOW:
            continue
        assert wow.eval(f"Bastians:FeedObject('{name}') ~= nil"), f"{name}: no feed"
        assert app["slash"] in slashes, f"{name}: slash {app['slash']} not registered"
        wow.execute(f"Bastians.UI.Hub.Open('{name}')")
        assert wow.eval(f"Bastians.UI.Settings.AppByModule('{name}') ~= nil")
        if wow.eval(f"Bastians:GetModule('{name}'):IsEnabled()"):
            assert wow.eval(f"{API}.Open('{name}')") is True, f"{name}: Open"
        else:
            assert wow.eval(f"{API}.Open('{name}')") is None  # off: nil, never an error
    assert seen >= 10
    assert wow.errors == []


def test_every_service_is_public_or_named_internal_and_every_event_documented(wow: WowRuntime):
    wow.start("Bastians_Core")
    services = set(wow.eval("Bastians.SERVICES").keys())
    reads = set(wow.eval(f"{API}.READS").keys())
    internal = set(wow.eval(f"{API}.INTERNAL").keys())
    assert reads.isdisjoint(internal)
    assert services == reads | internal, sorted(services ^ (reads | internal))
    doc = DOC.read_text(encoding="utf-8")
    for call in wow.eval(f"{API}.READS").values():
        for name in str(call).split(", "):
            assert f"| `{name}(" in doc, name
    events = list(wow.eval(f"{API}.EVENTS").values())
    assert "BASTIANS_PLAY_CHANGED" in events and "BASTIANS_CHAT_UNREAD" in events
    documented = re.findall(r"^\| `(BASTIANS_\w+)`", doc, flags=re.M)
    assert set(events) <= set(documented)
    # the public table of the apps names every app that has a window
    for app in apps(wow):
        if app["module"] not in NO_WINDOW and not app["later"]:  # the Library is private
            assert f"| {app['module']}" in doc or f"| {app['module']} (" in doc, app["module"]


def test_known_speak_play_and_open_answer_copies_or_nil(wow: WowRuntime):
    wow.start("Bastians_Core")
    for call in ("Known(2589)", "Speak('x')", "Open('Quests')"):
        assert wow.eval(f"({API}.{call})") is None, call
    assert wow.eval(f"{API}.Play()") in ("custom", "everything", "wanderer", "scholar", None)
    wow.execute(
        "Bastians:ProvideService(Bastians:GetModule('Core'), 'knowledge',"
        " { Known = function(_, id) return { me = true, alts = { 'Marla', 'Tobb' } } end },"
        " { priority = 999 })"
    )
    known = wow.eval(f"{API}.Known(2589)")
    assert known.me is True and known.others == 2 and known.names == "Marla, Tobb"
    assert wow.eval(f"{API}.Known('x')") is None
    wow.execute(
        "Spoke = {} ; Bastians:ProvideService(Bastians:GetModule('Core'), 'voice',"
        " { Can = function() return true end,"
        " Speak = function(t) Spoke[#Spoke + 1] = t return true end }, { priority = 999 })"
    )
    assert wow.eval(f"{API}.Speak('Next: the road')") is True
    assert list(wow.eval("Spoke").values()) == ["Next: the road"]
    assert wow.eval(f"{API}.Speak('')") is None
    wow.execute("Bastians.UI.Settings.ApplyPlay('wanderer')")
    assert wow.eval(f"{API}.Play()") == "wanderer"
    wow.execute(
        "Heard = {} ; Bastians.API.RegisterCallback({}, 'BASTIANS_PLAY_CHANGED',"
        " function(e, id) Heard[#Heard + 1] = id end)"
    )
    wow.execute("Bastians.UI.Settings.ApplyPlay('scholar')")
    assert list(wow.eval("Heard").values()) == ["scholar"]
    assert wow.errors == []


def test_open_opens_a_window_and_refuses_in_combat(wow: WowRuntime):
    wow.start("Bastians_Core", "Bastians_Data", "Bastians_Notes")
    wow.run_frames(5)
    assert wow.eval(f"{API}.Open('Notes')") is True
    assert wow.eval(f"{API}.Open('Nope')") is None
    wow.execute("Mock.SetCombat(true)")
    assert wow.eval(f"{API}.Open('Notes')") is False
    wow.execute("Mock.SetCombat(false)")
    assert wow.errors == []
