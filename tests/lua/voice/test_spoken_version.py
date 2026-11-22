"""Spoken 3.7.0 or newer: the hub's note says when the
installed Spoken is newer or older than the suite was tested with; the suite's words never talk over
Spoken's line or another addon's text to speech (Spoken Players); the Orbiter has a feed."""

import itertools

from harness import WowRuntime
from test_voice import CORE, DATA, QUESTS, SPOKEN, VOICE, V, boot, run

TESTED = "3.8.0"


def test_the_note_names_a_newer_or_older_spoken(wow: WowRuntime):
    boot(wow)
    assert wow.eval("Bastians.TESTED_WITH.Spoken") == TESTED
    assert wow.eval(f"{V}.options[1].text()") == (
        "Spoken reads: quests, zones and areas, readables, boss stories"
    )  # the double is 3.8.0: nothing to say
    wow.execute("Spoken.ADDON_VERSION = '3.10.1'")
    assert wow.eval(f"{V}.options[1].text()").endswith(
        "Spoken 3.10.1 is newer than the suite was tested with (3.8.0)"
    )
    wow.execute("Spoken.ADDON_VERSION = '3.5.1'")
    assert "older than 3.8.0: boss stories" in wow.eval(f"{V}.options[1].text()")
    wow.execute("Spoken.ADDON_VERSION = nil")
    assert wow.eval(f"{V}.options[1].text()").endswith("boss stories")
    assert wow.eval(f"{V}.Voice.VersionCompare('3.7.0', '3.10.0')") == -1
    assert wow.eval(f"{V}.Voice.VersionCompare('3.7', '3.7.0')") == 0
    assert wow.errors == []


def test_the_words_wait_for_another_addons_line(wow: WowRuntime):
    boot(wow, CORE, DATA, VOICE)  # the game's voice, no Spoken
    speak = "Bastians:GetService('voice').Speak('Marshal Dughan')"
    assert wow.eval(speak) is True  # our own line: the started event is ours, no hold
    assert wow.eval("#Mock.tts") == 1
    # another addon's line (Spoken Players): the event without our call, 3 seconds long
    wow.execute("Mock.Fire('VOICE_CHAT_TTS_PLAYBACK_STARTED', 77, 3000)")
    assert wow.eval(f"{V}.Voice.OtherTtsPlaying()") is True
    assert wow.eval(speak) is False
    assert wow.eval("#Mock.tts") == 1
    wow.advance(3.1)
    assert wow.eval(f"{V}.Voice.OtherTtsPlaying()") is False
    assert wow.eval(speak) is True
    # a line without a duration holds ten seconds, the finished event ends it early
    wow.execute("Mock.Fire('VOICE_CHAT_TTS_PLAYBACK_STARTED', 78)")
    assert wow.eval(speak) is False
    wow.execute("Mock.Fire('VOICE_CHAT_TTS_PLAYBACK_FINISHED', 78)")
    assert wow.eval(speak) is True
    assert wow.errors == []


def test_the_words_never_talk_over_spoken(wow: WowRuntime):
    boot(wow)
    run(wow, "quest:176")  # Spoken plays a quest line
    assert wow.eval("Spoken:IsPlaying()") is True
    assert wow.eval("Bastians:GetService('voice').Speak('Next: the road')") is False
    wow.execute("Spoken:StopAll()")
    assert wow.eval("Bastians:GetService('voice').Speak('Next: the road')") is True
    assert wow.errors == []


def test_the_orbiter_has_a_feed(wow: WowRuntime):
    boot(wow, CORE, DATA, *SPOKEN, QUESTS, VOICE)
    o = "Bastians:FeedObject('Voice')"
    assert wow.eval(f"{o}.type") == "data source"
    assert wow.eval(f"{o}.label") == "Orbiter"
    assert wow.eval(
        "LibStub('LibDataBroker-1.1'):GetDataObjectByName([[Bastian's Orbiter]]) ~= nil"
    )
    assert wow.eval(f"{o}.text") == ""
    wow.execute(
        "TipLines = {} ; local tt = { AddLine = function(_, t) TipLines[#TipLines + 1] = t end,"
        " AddDoubleLine = function(_, a, b) TipLines[#TipLines + 1] = a end }"
        f" ; {o}.OnTooltipShow(tt)"
    )
    lines = list(wow.eval("TipLines").values())
    assert any("Nothing plays." in line for line in lines)
    assert lines[-1].startswith("Click")
    run(wow, "quest:176")
    wow.advance(2)  # Core refreshes a feed a moment after its message
    wow.run_frames(3)
    assert wow.eval(f"{o}.text") == 'Wanted: "Hogger"'
    wow.execute(f"{o}.OnClick(nil, 'RightButton')")
    assert wow.eval("Spoken:IsPlaying()") is False
    wow.advance(2)
    wow.run_frames(3)
    assert wow.eval(f"{o}.text") == ""
    assert wow.errors == []


def test_the_conversations_options_spread_over_an_arc(wow: WowRuntime):
    """the options overlapped at the top; now 60 degrees apart on an arc
    centred on top, at most 240 degrees wide; the facing arrow above the ring is gone."""
    boot(wow, CORE, DATA, VOICE)
    T = "Bastians:GetModule('Voice').Talk"
    items = wow.eval(
        f"(function() local _, outer = {T}.OrbitItems({{ quests = {{}}, options = {{"
        " { kind = 'say', label = 'a' }, { kind = 'say', label = 'b' },"
        " { kind = 'say', label = 'c' }, { kind = 'say', label = 'd' } } }) return outer end)()"
    )
    assert [round(o.bearing) for o in items.values()] == [270, 330, 30, 90]
    one = wow.eval(
        f"(function() local _, outer = {T}.OrbitItems({{ quests = {{}}, options = {{"
        " { kind = 'say', label = 'a' } } }) return outer end)()"
    )
    assert [round(o.bearing) for o in one.values()] == [0]
    six = wow.eval(
        f"(function() local _, outer = {T}.OrbitItems({{ quests = {{}}, options = {{"
        " {}, {}, {}, {}, {}, {} } }) return outer end)()"
    )
    bearings = [round(o.bearing) for o in six.values()]
    assert bearings == [240, 288, 336, 24, 72, 120]  # 240 degrees, never wider
    assert wow.eval("BastiansVoiceOrbit.facing") is None
    assert wow.errors == []


def test_a_guards_many_answers_never_share_a_place(wow: WowRuntime):
    """a guard's fifteen directions lay two on one place ("most of the
    answers are doubled"). Past eleven the answers come in pages of nine behind "More"."""
    boot(wow, CORE, DATA, VOICE)
    T = "Bastians:GetModule('Voice').Talk"
    wow.execute(
        "Shown = {}; State = { quests = {}, options = {} }; "
        "for i = 1, 15 do State.options[i] = { kind = 'say', label = 'Where ' .. i } end; "
        "State.options[16] = { kind = 'say', label = 'Farewell' }; "
    )

    def outer() -> list:
        return list(
            wow.eval(f"(function() local _, o = {T}.OrbitItems(State) return o end)()").values()
        )

    first = outer()
    labels = [o.label for o in first]
    assert labels == [f"Where {i}" for i in range(1, 10)] + ["More", "Farewell"]
    bearings = sorted(round(o.bearing) % 360 for o in first)
    gaps = [(b - a) for a, b in itertools.pairwise(bearings)]
    gaps.append(bearings[0] + 360 - bearings[-1])
    assert min(gaps) >= wow.eval("Bastians:GetModule('Voice').Voice.MIN_GAP")
    more = next(o for o in first if o.label == "More")
    wow.execute(f"{T}.Page(State)[10].onClick()")
    assert more.glyph == "more"
    second = [o.label for o in outer()]
    assert second == [f"Where {i}" for i in range(10, 16)] + ["More", "Farewell"]
    wow.execute(f"{T}.Page(State)[7].onClick()")
    assert next(o.label for o in outer()) == "Where 1"  # round again
    # eleven fit without pages; no two words side by side above the hub
    for n in range(1, 12):
        b = [round(x) for x in wow.eval(f"{T}.Bearings({n})").values()]
        near = [x for x in b if abs(x) < 20]
        assert len(near) <= 1, (n, b)
    assert wow.errors == []
