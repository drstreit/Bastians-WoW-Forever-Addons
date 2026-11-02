"""Courtesy for a duel, a trade and a group invite (plan-second-wave.md S7): the bubble asks with
Bow, Wave and Decline politely; the decline whispers the line and calls the game's decline; never
automatic; the partner of a trade is the unit NPC; the mock keeps what was declined."""

from harness import WowRuntime
from test_gestures import MOD, C, boot, emotes, errors, sent


def declined(wow: WowRuntime) -> list[str]:
    return list(wow.eval("Mock.declined").values())


def test_a_duel_asks_and_a_bow_or_a_wave_answers(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.Fire('DUEL_REQUESTED', 'Grimtok')")
    assert wow.eval(f"{C}.IsShown()") is True
    assert wow.eval("BastiansGesturesCourtesy.who:GetText()") == "Grimtok challenges you to a duel"
    assert wow.eval("BastiansGesturesCourtesy.ask:GetText()") == "Answer?"
    assert wow.eval("BastiansGesturesCourtesy.wave:IsShown()") is True
    wow.execute("BastiansGesturesCourtesy.emote:Click()")
    assert emotes(wow) == [("BOW", None)]
    assert declined(wow) == []  # a bow declines nothing: the game's popup stays
    wow.execute("Mock.Fire('DUEL_REQUESTED', 'Zug')")
    wow.execute("BastiansGesturesCourtesy.wave:Click()")
    assert emotes(wow)[-1][0] == "WAVE"
    # a buff after that: the bubble back to Thank, the wave button gone
    wow.execute(
        "Mock.unitNames = Mock.unitNames or {}; Mock.unitNames.nameplate3 = 'Thalendra';"
        " Mock.Fire('UNIT_AURA', 'player', { addedAuras = { { sourceUnit = 'nameplate3',"
        " isHelpful = true, name = 'Mark of the Wild' } } })"
    )
    assert wow.eval("BastiansGesturesCourtesy.ask:GetText()") == "Thank them?"
    assert wow.eval("BastiansGesturesCourtesy.wave:IsShown()") is False
    assert errors(wow) == []


def test_decline_politely_whispers_and_declines(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.Fire('PARTY_INVITE_REQUEST', 'Grimtok')")
    assert wow.eval(f"{C}.Pending().kind") == "invite"
    wow.execute("BastiansGesturesCourtesy.line:Click()")
    assert sent(wow) == [("Thank you, but not today, Grimtok.", "WHISPER", None)]
    assert declined(wow) == ["invite"]
    assert wow.eval(f"{C}.IsShown()") is False
    # a trade: the partner is the unit NPC; one of my group trades without a bubble
    wow.execute("Mock.unitNames = Mock.unitNames or {}; Mock.unitNames.NPC = 'Zug'")
    wow.execute("Mock.Fire('TRADE_SHOW')")
    assert wow.eval(f"{C}.Pending().who") == "Zug"
    wow.execute(f"{MOD}.db.profile.declines = {{ 'Another time, %t.' }}")
    wow.execute("BastiansGesturesCourtesy.line:Click()")
    assert sent(wow)[-1] == ("Another time, Zug.", "WHISPER", None)
    assert declined(wow) == ["invite", "trade"]
    wow.execute("Mock.groupUnits = { NPC = true }; Mock.groupSize = 2")
    wow.execute("Mock.Fire('TRADE_SHOW')")
    assert wow.eval(f"{C}.IsShown()") is False
    assert errors(wow) == []


def test_a_request_is_never_answered_automatically(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{MOD}.db.profile.courtesy = 'auto'")
    wow.execute("Mock.Fire('DUEL_REQUESTED', 'Grimtok')")
    assert wow.eval(f"{C}.IsShown()") is True  # asked, not answered
    assert emotes(wow) == [] and sent(wow) == [] and declined(wow) == []
    wow.execute("BastiansGesturesCourtesy.no:Click()")
    assert declined(wow) == []  # Not now leaves the game's popup to the player
    wow.execute(f"{MOD}.db.profile.courtesy = 'off'")
    wow.execute("Mock.Fire('DUEL_REQUESTED', 'Zug')")
    assert wow.eval(f"{C}.IsShown()") is False
    assert errors(wow) == []
