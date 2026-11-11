"""Bastian's Courtesy (courtesy.md, ADR 0064): the ring of four answers for a kind deed and for a
request, what a click sends, the decision, a secret aura list, what comes over from Gestures, and
life alone."""

from harness import WowRuntime

CORE, DATA, GESTURES, COURTESY = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Gestures",
    "Bastians_Courtesy",
)
MOD = "Bastians:GetModule('Courtesy')"
M = f"{MOD}.Model"
C = f"{MOD}.Courtesy"
R = f"{MOD}.Medallion"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, GESTURES, COURTESY)))
    wow.run_frames(5)
    wow.execute(
        "UnitSex = function() return 3 end; GetGameTime = function() return 9, 0 end;"
        " C_Weather = { GetCurrentWeather = function() return { type = 0, intensity = 0 } end };"
        " UnitIsPlayer = function() return true end"
    )
    wow.advance(6)  # the first seconds after a login only note what is there
    return wow


def errors(wow: WowRuntime) -> list[str]:
    return wow.errors + [
        line.text
        for line in wow.eval("Bastians:GetLog()").values()
        if line.level == "error" and "registered no data" not in line.text
    ]


def emotes(wow: WowRuntime) -> list[tuple]:
    return [(e.token, e.target) for e in wow.eval("Mock.emotes").values()]


def sent(wow: WowRuntime) -> list[tuple]:
    return [(s.text, s.type, s.language) for s in wow.eval("Mock.sentChat").values()]


def declined(wow: WowRuntime) -> list[str]:
    return list(wow.eval("Mock.declined").values())


def spell_id(spell: str) -> int:
    return 1000 + sum(ord(c) * (i + 1) for i, c in enumerate(spell))


def cast(wow: WowRuntime, fields: str) -> None:
    """An aura lands or is cast again: its end moves later, UNIT_AURA says only "something changed"."""
    wow.execute(
        f"""Mock.stamp = (Mock.stamp or 7000) + 100
        Mock.auras = {{ {{ {fields}, expirationTime = Mock.stamp }} }}
        Mock.Fire('UNIT_AURA', 'player', {{}})"""
    )
    wow.advance(0.3)


def buff(wow: WowRuntime, unit: str, name: str, spell: str = "Mark of the Wild") -> None:
    wow.execute(
        f"""Mock.unitNames = Mock.unitNames or {{}}; Mock.unitNames['{unit}'] = '{name}';
        Mock.guids = Mock.guids or {{}}; Mock.guids['{unit}'] = 'Player-1-' .. '{name}';"""
    )
    cast(wow, f"name = '{spell}', spellId = {spell_id(spell)}, sourceUnit = '{unit}'")


def click(wow: WowRuntime, i: int) -> None:
    wow.execute(f"{C}.Fire({i}, {R}.Item({i}))")


def test_the_decision(wow: WowRuntime):
    boot(wow)
    wow.execute("ST = { seen = {} }")
    ask = f"{M}.Courtesy({{ kind = 'buff', who = 'Thalendra' }}, ST, %d, {{ mode = 'ask' }})"
    assert wow.eval(ask % 100) == "ask"
    assert wow.eval(ask % 200) is None
    assert wow.eval(ask % 800) == "ask"
    again = f"{M}.Courtesy({{ kind = 'accepted', who = 'Thalendra', again = true }}, ST, 801, {{ mode = 'ask' }})"
    assert wow.eval(again) == "ask"
    y = "{ kind = 'buff', who = 'Y' }"
    assert wow.eval(f"{M}.Courtesy({y}, ST, 1, {{ mode = 'off' }})") is None
    assert wow.eval(f"{M}.Courtesy({y}, ST, 1, {{ mode = 'auto', inCombat = true }})") is None
    assert wow.eval(f"{M}.Courtesy({y}, ST, 1, {{ mode = 'auto', inInstance = true }})") is None
    wide = "{ mode = 'auto', inInstance = true, instances = true }"
    assert wow.eval(f"{M}.Courtesy({y}, ST, 1, {wide})") == "auto"
    assert wow.eval(f"{M}.AimedAtMe('Grimtok waves at you.')") is True
    assert wow.eval(f"{M}.AimedAtMe('Grimtok waves at Bob.')") is False
    assert errors(wow) == []


def test_the_situation_of_a_moment(wow: WowRuntime):
    boot(wow)
    of = f"{M}.Situation"
    kind = "function(n) return n == 'Arcane Intellect' and 'mind' or nil end"
    assert wow.eval(f"{of}({{ kind = 'buff', what = 'Arcane Intellect' }}, {kind})") == "buff.mind"
    assert wow.eval(f"{of}({{ kind = 'buff', what = 'Sprint' }}, {kind})") == "buff"
    assert wow.eval(f"{of}({{ kind = 'emote', text = 'Zug waves at you.' }})") == "emote.friendly"
    assert wow.eval(f"{of}({{ kind = 'emote', text = 'Zug spits on you.' }})") == "emote.rude"
    assert wow.eval(f"{of}({{ kind = 'accepted' }})") == "invite.accepted"
    assert wow.eval(f"{of}({{ kind = 'trade' }})") is None
    assert wow.eval(f"{M}.DayKey(4)") == "night"
    assert wow.eval(f"{M}.DayKey(9)") == "morning"
    assert wow.eval(f"{M}.DayKey(nil)") is None


def test_a_buff_opens_the_ring_with_three_lines_and_the_gesture(wow: WowRuntime):
    boot(wow)
    buff(wow, "nameplate3", "Thalendra")
    assert wow.eval(f"{C}.IsShown()") is True
    assert wow.eval(f"{C}.Pending().who") == "Thalendra"
    assert wow.eval(f"{R}.Caption()") == "Thalendra cast Mark of the Wild on you"
    assert "app_courtesy" in wow.eval(f"{R}.Symbol()")
    lines = [wow.eval(f"{R}.Item({i}).line") for i in (1, 2, 3)]
    assert all(lines)
    assert len({wow.eval(f"{R}.Item({i}).label") for i in (1, 2, 3)}) == 3  # three moods
    assert wow.eval(f"{R}.Item(4).emote") == "THANK"
    assert errors(wow) == []


def test_the_petals_fly_out(wow: WowRuntime):
    boot(wow)
    buff(wow, "nameplate3", "Thalendra")
    start = wow.eval(f"select(5, {R}.Petal(1):GetPoint(1))")
    wow.run_frames(6)
    middle = wow.eval(f"select(5, {R}.Petal(1):GetPoint(1))")
    wow.run_frames(30)
    end = wow.eval(f"select(5, {R}.Petal(1):GetPoint(1))")
    assert start < middle < end
    assert round(end) == 70
    assert errors(wow) == []


def test_a_click_sends_the_line_as_the_line_asks(wow: WowRuntime):
    boot(wow)
    wow.execute(
        "Bastians:AddCourtesyLines({"
        " { 'rez', 'polite', 'SPOKEN, %t.' },"
        " { 'rez', 'roleplay', 'WITH ACT, %t.', act = 'bows to %t.', emote = 'BOW' },"
        "})"
    )
    wow.execute("Mock.Fire('RESURRECT_REQUEST', 'Aquinne')")
    labels = {wow.eval(f"{R}.Item({i}).label"): i for i in (1, 2, 3)}
    assert {"Polite", "Roleplay"} <= set(labels)
    wow.execute(f"SAVED = {R}.Item({labels['Roleplay']})")
    wow.execute(f"{C}.Fire({labels['Roleplay']}, SAVED)")
    assert sent(wow) == [('bows to Aquinne. "WITH ACT, Aquinne."', "EMOTE", None)]
    assert emotes(wow)[-1][0] == "BOW"
    assert wow.eval(f"{C}.IsShown()") is False
    assert wow.eval(f"{C}.Pending()") is None
    wow.execute(f"{C}.Show({{ kind = 'rez', who = 'Zug' }})")
    labels = {wow.eval(f"{R}.Item({i}).label"): i for i in (1, 2, 3)}
    click(wow, labels["Polite"])
    assert sent(wow)[-1] == ("SPOKEN, Zug.", "SAY", None)
    assert errors(wow) == []


def test_the_gesture_the_centre_and_the_time(wow: WowRuntime):
    boot(wow)
    buff(wow, "nameplate3", "Thalendra")
    click(wow, 4)
    assert emotes(wow) == [("THANK", "nameplate3")]
    assert sent(wow) == []
    # the same person within ten minutes: nothing
    buff(wow, "nameplate3", "Thalendra")
    assert wow.eval(f"{C}.IsShown()") is False
    # another one, closed by hand: nothing is sent
    buff(wow, "nameplate4", "Grimtok", "Power Word: Fortitude")
    wow.execute(f"{R}.Close()")
    assert wow.eval(f"{C}.Pending()") is None
    assert sent(wow) == []
    # the twelve seconds
    buff(wow, "nameplate5", "Bob")
    wow.advance(11)
    wow.run_frames(2)
    assert wow.eval(f"{C}.IsShown()") is True
    wow.advance(2)
    wow.run_frames(2)
    assert wow.eval(f"{C}.IsShown()") is False
    assert len(emotes(wow)) == 1 and sent(wow) == []
    assert errors(wow) == []


def test_mine_and_group_buffs_open_nothing(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.groupUnits = { party1 = true }; Mock.groupSize = 2")
    buff(wow, "party1", "Friend")
    cast(wow, f"name = 'Thorns', spellId = {spell_id('Thorns')}, sourceUnit = 'player'")
    assert wow.eval(f"{C}.IsShown()") is False
    assert errors(wow) == []


def test_hidden_auras_open_nothing_and_raise_nothing(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.aurasSecret = true")  # the mock raises as the client does when they are read
    cast(wow, "name = 'Thorns', spellId = 777, sourceUnit = 'nameplate3'")
    assert wow.eval(f"{C}.IsShown()") is False
    wow.execute("Mock.aurasSecret = false ; Mock.auras = {}")
    cast(wow, "name = 'Base', spellId = 778")  # a reading again
    wow.execute("issecretvalue = function(v) return v == 777 end")
    cast(
        wow, "name = 'Thorns', spellId = 777, sourceUnit = 'nameplate3'"
    )  # its id is secret: unknown
    assert wow.eval(f"{C}.IsShown()") is False
    assert errors(wow) == []


def test_an_emote_and_a_resurrection(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.Fire('RESURRECT_REQUEST', 'Sister Aquinne')")
    assert wow.eval(f"{C}.Pending().kind") == "rez"
    wow.execute(f"{C}.Hide()")
    wow.execute("Mock.Fire('CHAT_MSG_TEXT_EMOTE', 'Zug bows before you.', 'Zug-Realm')")
    assert wow.eval(f"{C}.Pending().who") == "Zug"
    click(wow, 4)
    assert emotes(wow)[-1][0] == "WAVE"
    wow.execute("Mock.Fire('CHAT_MSG_TEXT_EMOTE', 'Mog waves at Bob.', 'Mog-Realm')")
    assert wow.eval(f"{C}.IsShown()") is False
    assert errors(wow) == []


def test_the_other_persons_facts_come_from_the_guid(wow: WowRuntime):
    boot(wow)
    wow.execute(
        "GetPlayerInfoByGUID = function() return 'Mage', 'MAGE', 'Dwarf', 'Dwarf', 3, 'Zug' end"
    )
    facts = wow.eval(
        f"{MOD}.Facts.Moment({{ kind = 'emote', who = 'Zug', text = 'x', guid = 'G-1' }})"
    )
    assert (facts.raceKey, facts.classKey, facts.sex, facts.target) == ("Dwarf", "MAGE", "f", "Zug")
    # a name and nothing else: unknown stays unknown
    facts = wow.eval(f"{MOD}.Facts.Moment({{ kind = 'rez', who = 'Zug' }})")
    assert facts.raceKey is None and facts.target == "Zug"
    assert errors(wow) == []


def test_a_request_shows_four_answers(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.Fire('DUEL_REQUESTED', 'Grimtok')")
    assert wow.eval(f"{C}.IsShown()") is True
    assert wow.eval(f"{R}.Caption()") == "Grimtok challenges you to a duel"
    labels = [wow.eval(f"{R}.Item({i}).label") for i in (1, 2, 3, 4)]
    assert labels == ["Bow", "Wave", "Decline", "Not now"]
    click(wow, 1)
    assert emotes(wow) == [("BOW", None)]
    assert declined(wow) == []  # a bow declines nothing: the game's popup stays
    wow.execute("Mock.Fire('DUEL_REQUESTED', 'Zug')")
    click(wow, 2)
    assert emotes(wow)[-1][0] == "WAVE"
    wow.execute("Mock.Fire('DUEL_REQUESTED', 'Mog')")
    click(wow, 4)
    assert declined(wow) == [] and len(emotes(wow)) == 2  # Not now does nothing at all
    assert errors(wow) == []


def test_decline_whispers_and_declines(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.Fire('PARTY_INVITE_REQUEST', 'Grimtok')")
    assert wow.eval(f"{C}.Pending().kind") == "invite"
    click(wow, 3)
    assert sent(wow)[-1][1] == "WHISPER"
    assert wow.eval("Mock.sentChat[1].target") == "Grimtok"
    assert declined(wow) == ["invite"]
    assert wow.eval(f"{C}.IsShown()") is False
    # a trade has no line of its own: the plain no; one of my group trades without a ring
    wow.execute("Mock.unitNames = Mock.unitNames or {}; Mock.unitNames.NPC = 'Zug'")
    wow.execute("Mock.Fire('TRADE_SHOW')")
    assert wow.eval(f"{C}.Pending().who") == "Zug"
    click(wow, 3)
    assert sent(wow)[-1] == ("Thank you, but not today, Zug.", "WHISPER", None)
    assert declined(wow) == ["invite", "trade"]
    wow.execute("Mock.groupUnits = { NPC = true }; Mock.groupSize = 2")
    wow.execute("Mock.Fire('TRADE_SHOW')")
    assert wow.eval(f"{C}.IsShown()") is False
    assert errors(wow) == []


def test_a_joined_group_after_an_invite_says_thank_you(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.Fire('PARTY_INVITE_REQUEST', 'Grimtok')")
    wow.execute("Mock.Fire('GROUP_JOINED')")
    assert wow.eval(f"{C}.Pending().kind") == "accepted"
    assert wow.eval(f"{R}.Caption()") == "You joined Grimtok's group"
    assert wow.eval(f"{R}.Item(1).line") is not None
    wow.execute(f"{C}.Hide()")
    wow.execute("Mock.Fire('GROUP_JOINED')")  # no invite before it
    assert wow.eval(f"{C}.IsShown()") is False
    assert errors(wow) == []


def test_a_request_is_never_answered_automatically(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{MOD}.db.profile.courtesy = 'auto'")
    wow.execute("Mock.Fire('DUEL_REQUESTED', 'Grimtok')")
    assert wow.eval(f"{C}.IsShown()") is True  # asked, not answered
    assert emotes(wow) == [] and sent(wow) == [] and declined(wow) == []
    wow.execute(f"{C}.Hide()")
    wow.execute(f"{MOD}.db.profile.courtesy = 'off'")
    wow.execute("Mock.Fire('DUEL_REQUESTED', 'Zug')")
    assert wow.eval(f"{C}.IsShown()") is False
    assert errors(wow) == []


def test_automatic_gestures_and_says_nothing(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{MOD}.db.profile.courtesy = 'auto'")
    buff(wow, "nameplate3", "Thalendra")
    assert wow.eval(f"{C}.IsShown()") is False
    assert emotes(wow) == [("THANK", "nameplate3")]
    assert sent(wow) == []
    assert errors(wow) == []


def test_combat_off_and_instances(wow: WowRuntime):
    boot(wow)
    buff(wow, "nameplate3", "Thalendra")
    assert wow.eval(f"{C}.IsShown()") is True
    wow.execute("Mock.SetCombat(true); Mock.Fire('PLAYER_REGEN_DISABLED')")
    assert wow.eval(f"{C}.IsShown()") is False  # combat closes an open ring
    buff(wow, "nameplate4", "Grimtok")
    assert wow.eval(f"{C}.IsShown()") is False
    wow.execute("Mock.SetCombat(false)")
    assert wow.eval(f"{C}.Pending().who") == "Grimtok"  # a buff of a short fight asks afterwards
    wow.execute(f"{C}.Hide()")
    wow.execute(f"{MOD}.db.profile.courtesy = 'off'")
    buff(wow, "nameplate5", "Aquinne")
    assert wow.eval(f"{C}.IsShown()") is False
    wow.execute(f"{MOD}.db.profile.courtesy = 'ask'")
    wow.execute("IsInInstance = function() return true, 'party' end")
    buff(wow, "nameplate6", "Bob")
    assert wow.eval(f"{C}.IsShown()") is False
    wow.execute(f"{MOD}.db.profile.courtesyInstances = true")
    buff(wow, "nameplate7", "Carl")
    assert wow.eval(f"{C}.IsShown()") is True
    assert wow.eval(f"{C}.Remembered()") >= 1
    assert errors(wow) == []


def test_a_mood_switched_off_is_not_offered(wow: WowRuntime):
    boot(wow)
    for mood in ("polite", "roleplay", "philosophic", "cheerful", "weary"):
        wow.execute(f"{MOD}.db.profile.mood_{mood} = false")
    buff(wow, "nameplate3", "Thalendra")
    labels = {wow.eval(f"{R}.Item({i}).label") for i in (1, 2, 3)}
    assert labels == {"Snarky"}
    assert errors(wow) == []


def test_the_ring_can_be_tried_alone_and_a_click_sends(wow: WowRuntime):
    boot(wow)
    wow.slash("/bcourtesy try ring rez snarky morning")
    assert wow.eval(f"{C}.IsShown()") is True
    assert wow.eval(f"{R}.Caption()") == "A moment to try: rez"
    assert sent(wow) == []  # opening sends nothing
    assert wow.eval(f"{R}.Item(1).label") == "Snarky"
    click(wow, 1)
    assert len(sent(wow)) == 1
    assert wow.eval(f"{C}.Remembered()") == 0  # a try is not a person answered
    assert errors(wow) == []


def test_the_settings_of_gestures_come_over_once(wow: WowRuntime):
    wow.execute(
        """BastiansGesturesDB = { profiles = { Default = { courtesy = 'auto', courtesyInstances = true,
          thanks = { 'Thank you, %t!', 'Bless your boots, %t.' }, declines = { 'Not today, %t.' } } } }"""
    )
    boot(wow)
    profile = wow.eval("Bastians:GetProfile()")
    if profile != "Default":
        wow.execute(
            f"BastiansGesturesDB.profiles['{profile}'] = BastiansGesturesDB.profiles.Default"
        )
        wow.execute(f"{MOD}.db.profile.adopted = nil; {MOD}.Main.Adopt({MOD}.db)")
    db = f"{MOD}.db.profile"
    assert wow.eval(f"{db}.courtesy") == "auto"
    assert wow.eval(f"{db}.courtesyInstances") is True
    kept = [(k[1], k[3]) for k in wow.eval(f"{db}.keptLines").values()]
    assert ("buff", "Bless your boots, %t.") in kept
    assert ("invite.declined", "Not today, %t.") in kept
    assert not any(text == "Thank you, %t!" for _, text in kept)  # the shipped ones stay behind
    wow.execute(f"{db}.courtesy = 'off'; {MOD}.Main.Adopt({MOD}.db)")
    assert wow.eval(f"{db}.courtesy") == "off"  # once
    assert errors(wow) == []


def test_it_loads_alone(wow: WowRuntime):
    boot(wow, CORE, COURTESY)
    buff(wow, "nameplate3", "Thalendra")
    assert wow.eval(f"{C}.IsShown()") is True
    assert errors(wow) == []


def test_it_switches_off_and_on(wow: WowRuntime):
    boot(wow)
    buff(wow, "nameplate3", "Thalendra")
    wow.execute(f"{MOD}:Disable()")
    assert wow.eval(f"{C}.IsShown()") is False
    buff(wow, "nameplate4", "Grimtok")
    assert wow.eval(f"{C}.IsShown()") is False
    wow.execute(f"{MOD}:Enable()")
    wow.advance(6)  # switched on: what is there now is noted first
    buff(wow, "nameplate5", "Bob")
    assert wow.eval(f"{C}.IsShown()") is True
    assert errors(wow) == []


def test_decline_of_a_trade_whispers_the_whole_name(wow: WowRuntime):
    boot(wow)
    wow.execute(
        """UnitName = function(u) if u == "NPC" then return "Zug", "Stonefist" end return "Mockchar" end
        Mock.Fire('TRADE_SHOW')"""
    )
    assert wow.eval(f"{C}.Pending().who") == "Zug"
    click(wow, 3)
    sep = " " if wow.eval("Bastians.Client") == "forever" else "-"
    assert wow.eval("Mock.sentChat[1].target") == f"Zug{sep}Stonefist"
    assert errors(wow) == []


def unseen(wow: WowRuntime, spell: str = "Arcane Intellect", from_player: str = "true") -> None:
    cast(
        wow,
        f"name = '{spell}', spellId = {spell_id(spell)}, isFromPlayerOrPlayerPet = {from_player}",
    )


def test_a_caster_the_client_has_no_handle_on_still_opens_the_ring(wow: WowRuntime):
    """a stranger's buff, and nothing showed."""
    boot(wow)
    unseen(wow)
    assert wow.eval(f"{C}.IsShown()") is True
    assert wow.eval(f"{R}.Caption()") == "Someone cast Arcane Intellect on you"
    assert wow.eval(f"{C}.Pending().who") is None
    # no line that asks for a name is offered
    for i in (1, 2, 3):
        item = wow.eval(f"{R}.Item({i})")
        if item:
            assert "%t" not in str(item.line[3]) and "%t" not in str(item.line.act)
    click(wow, 4)
    assert emotes(wow)[-1] == ("THANK", None)
    unseen(wow)  # the same spell again within ten minutes: nothing
    assert wow.eval(f"{C}.IsShown()") is False
    unseen(wow, "Power Word: Fortitude")  # another one asks
    assert wow.eval(f"{C}.IsShown()") is True
    assert errors(wow) == []


def test_an_npcs_or_items_buff_opens_nothing(wow: WowRuntime):
    boot(wow)
    unseen(wow, "Songflower Serenade", "false")
    assert wow.eval(f"{C}.IsShown()") is False
    unseen(wow, "Well Fed", "nil")  # unknown is not yes
    assert wow.eval(f"{C}.IsShown()") is False
    assert errors(wow) == []


def test_why_says_what_became_of_each_buff(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f"{C}.Why()") is False
    buff(wow, "nameplate3", "Thalendra")
    wow.execute(f"{C}.Hide()")
    buff(wow, "nameplate3", "Thalendra")
    unseen(wow, "Well Fed", "false")
    wow.execute("Mock.aurasSecret = true")
    cast(wow, "name = 'Hidden', spellId = 5")
    wow.execute("Mock.aurasSecret = false ; Mock.chat = {}")
    assert wow.eval(f"{C}.Why()") is True
    said = [str(line) for line in wow.eval("Mock.chat").values()]
    words = " | ".join(said)
    assert "auras hidden" in words
    assert "not from a player, Well Fed" in words
    assert "answered lately, Mark of the Wild" in words
    assert "ask, Mark of the Wild" in words
    assert errors(wow) == []


def test_my_own_gesture_opens_nothing(wow: WowRuntime):
    """the ring came when using a gesture of the wheel."""
    boot(wow)
    assert wow.eval(f"{M}.AimedAtMe('You wave at Bob.')") is False
    assert wow.eval(f"{M}.AimedAtMe('You wave at your friend.')") is False
    wow.execute(
        """Mock.Fire('CHAT_MSG_TEXT_EMOTE', 'You wave at Bob.', 'Mockchar Surname', '', '', '', '', 0, 0, '', 0, 0,
          UnitGUID('player'))"""
    )
    assert wow.eval(f"{C}.IsShown()") is False
    wow.execute(
        """Mock.Fire('CHAT_MSG_TEXT_EMOTE', 'Mockchar waves at you.', 'Mockchar Surname', '', '', '', '', 0, 0, '', 0, 0,
          UnitGUID('player'))"""
    )
    assert wow.eval(f"{C}.IsShown()") is False  # the GUID decides, whatever the line says
    wow.execute(
        """Mock.Fire('CHAT_MSG_TEXT_EMOTE', 'Zug bows before you.', 'Zug Stonefist', '', '', '', '', 0, 0, '', 0, 0,
          'Player-1-Zug')"""
    )
    assert wow.eval(f"{C}.Pending().who") == "Zug"  # the first name, a surname or not
    assert errors(wow) == []


def test_a_buff_cast_again_by_someone_else_asks(wow: WowRuntime):
    boot(wow)
    buff(wow, "nameplate3", "Thalendra")
    wow.execute(f"{C}.Hide()")
    buff(wow, "nameplate4", "Grimtok")  # the same spell: not new, its end moved
    assert wow.eval(f"{C}.Pending().who") == "Grimtok"
    wow.execute(f"{C}.Hide() ; Mock.Fire('UNIT_AURA', 'player', {{}})")
    wow.advance(0.3)  # something else changed: the buff is what it was
    assert wow.eval(f"{C}.IsShown()") is False
    assert errors(wow) == []


def test_the_casters_guid_names_a_stranger_without_a_unit(wow: WowRuntime):
    boot(wow)
    wow.execute(
        "Mock.players = { ['Player-1-Zara'] = { name = 'Zara', class = 'Mage', file = 'MAGE' } }"
    )
    cast(wow, "name = 'Arcane Intellect', spellId = 11, casterGUID = 'Player-1-Zara'")
    assert wow.eval(f"{R}.Caption()") == "Zara cast Arcane Intellect on you"
    wow.execute(f"{C}.Hide()")
    cast(wow, "name = 'Songflower', spellId = 12, casterGUID = 'Creature-0-1-2-3-4-5'")
    assert wow.eval(f"{C}.IsShown()") is False  # an NPC's
    cast(wow, "name = 'Thorns', spellId = 13, casterGUID = UnitGUID('player')")
    assert wow.eval(f"{C}.IsShown()") is False  # my own
    assert errors(wow) == []


def test_an_npcs_unit_opens_nothing(wow: WowRuntime):
    boot(wow)
    wow.execute("UnitIsPlayer = function(u) return u == 'player' end")
    buff(wow, "nameplate3", "Elder")
    assert wow.eval(f"{C}.IsShown()") is False
    assert errors(wow) == []


def test_without_a_name_only_a_class_buff_asks(wow: WowRuntime):
    """`isFromPlayerOrPlayerPet` is in neither the docs nor the FrameXML of Forever's client."""
    boot(wow)
    wow.execute(
        "Bastians.Compat.GetSpellName = function(id) return id == 1459 and 'Arcane Intellect' or nil end"
    )
    unseen(wow, "Arcane Intellect", "nil")
    assert wow.eval(f"{R}.Caption()") == "Someone cast Arcane Intellect on you"
    wow.execute(f"{C}.Hide()")
    unseen(wow, "Well Fed", "nil")
    assert wow.eval(f"{C}.IsShown()") is False
    assert errors(wow) == []


def test_a_buff_in_a_short_fight_asks_afterwards(wow: WowRuntime):
    boot(wow)
    wow.fire("PLAYER_REGEN_DISABLED")
    wow.execute("Mock.combat = true")
    buff(wow, "nameplate3", "Thalendra")
    assert wow.eval(f"{C}.IsShown()") is False
    wow.advance(10)
    wow.execute("Mock.combat = false")
    wow.fire("PLAYER_REGEN_ENABLED")
    assert wow.eval(f"{C}.Pending().who") == "Thalendra"
    assert errors(wow) == []


def trace(wow: WowRuntime) -> list[tuple]:
    rows = wow.eval("Bastians:GetModule('Courtesy').db.global.trace").values()
    return [(r.word, r.spell, r.how) for r in rows]


def test_after_a_long_fight_a_buff_without_a_landing_time_gets_no_ring(wow: WowRuntime):
    boot(wow)
    wow.fire("PLAYER_REGEN_DISABLED")
    wow.execute("Mock.combat = true")
    buff(wow, "nameplate3", "Thalendra")  # an end, no duration: when it landed is not known
    wow.advance(61)
    wow.execute("Mock.combat = false")
    wow.fire("PLAYER_REGEN_ENABLED")
    assert wow.eval(f"{C}.IsShown()") is False
    assert trace(wow)[0] == ("long fight", "Mark of the Wild", None)  # and the trace says so
    assert errors(wow) == []


def long_fight(wow: WowRuntime, seconds: int) -> None:
    """A stranger's buff lands at the start of a fight of `seconds`; the aura says when."""
    wow.fire("PLAYER_REGEN_DISABLED")
    wow.execute(
        """Mock.combat = true
        Mock.unitNames = { nameplate3 = 'Thalendra' }; Mock.guids = { nameplate3 = 'Player-1-Thalendra' }
        Mock.auras = { { name = 'Power Word: Fortitude', spellId = 1243, sourceUnit = 'nameplate3',
          duration = 1800, expirationTime = GetTime() + 1800 } }
        Mock.Fire('UNIT_AURA', 'player', {})"""
    )
    wow.advance(seconds)
    wow.execute("Mock.combat = false")
    wow.fire("PLAYER_REGEN_ENABLED")


def test_a_buff_of_a_long_fight_asks_afterwards_when_the_aura_says_when_it_landed(wow: WowRuntime):
    """ "It really happens often that I get buffed from a player but
    courtesy does not show up". Every buff of a fight longer than a minute was dropped."""
    boot(wow)
    long_fight(wow, 200)
    assert wow.eval(f"{C}.Pending().who") == "Thalendra"
    assert trace(wow)[0] == ("ask", "Power Word: Fortitude", "unit")
    assert errors(wow) == []


def test_a_buff_that_landed_long_ago_in_a_fight_gets_no_ring(wow: WowRuntime):
    boot(wow)
    long_fight(wow, 400)  # more than five minutes ago: the moment is over
    assert wow.eval(f"{C}.IsShown()") is False
    assert trace(wow)[0] == ("long fight", "Power Word: Fortitude", None)
    assert errors(wow) == []


def test_the_trace_leaves_out_my_own_casts_and_says_when_a_guid_has_no_name(wow: WowRuntime):
    """The owner's saved trace, 10.11.2026: 25 of 30 lines were the player's own auras."""
    boot(wow)
    cast(wow, "name = 'Drink', spellId = 430, sourceUnit = 'player'")
    wow.execute("Mock.guids = Mock.guids or {}; Mock.guids.player = 'Player-1-Me'")
    cast(wow, "name = 'Frost Armor', spellId = 168, casterGUID = 'Player-1-Me'")
    assert trace(wow) == []
    cast(wow, "name = 'Well Fed', spellId = 19705, casterGUID = 'Player-9-Unnamed'")
    assert trace(wow) == [("not from a player", "Well Fed", "guid without a name")]
    assert errors(wow) == []


def test_what_is_there_after_a_loading_screen_is_nobodys_kindness(wow: WowRuntime):
    boot(wow)
    wow.fire("PLAYER_ENTERING_WORLD")
    buff(wow, "nameplate3", "Thalendra")
    assert wow.eval(f"{C}.IsShown()") is False
    wow.advance(6)
    assert wow.eval(f"{C}.IsShown()") is False
    buff(wow, "nameplate4", "Grimtok")
    assert wow.eval(f"{C}.Pending().who") == "Grimtok"
    assert errors(wow) == []


def test_the_trace_is_kept_without_a_name(wow: WowRuntime):
    boot(wow)
    buff(wow, "nameplate3", "Thalendra")
    trace = list(wow.eval("Bastians:GetModule('Courtesy').db.global.trace").values())
    assert (trace[0].word, trace[0].spell, trace[0].how) == ("ask", "Mark of the Wild", "unit")
    assert "Thalendra" not in {trace[0].word, trace[0].spell, trace[0].how}
    assert errors(wow) == []


def test_a_spoken_line_goes_through_the_games_secure_macro(wow: WowRuntime):
    """ "I clicked, nothing in chat"; the client refuses the addon's call."""
    boot(wow)
    unseen(wow)  # no name to whisper to: the line is said aloud
    button = f"{R}.Secure(1)"
    assert wow.eval(f"{button}:GetAttribute('type')") == "macro"
    # , clicking and nothing in chat: an addon's secure button follows
    # ActionButtonUseKeyDown, and a button that hears only the release must be told to act on it
    assert list(wow.eval(f"{button}.clicks").values()) == ["AnyUp"]
    assert wow.eval(f"{button}:GetAttribute('useOnKeyDown')") is False
    text = wow.eval(f"{button}:GetAttribute('macrotext')")
    assert text[:3] in ("/s ", "/e ") and len(text) <= 255
    wow.execute("Mock.sentChat = {}")
    wow.execute(f"local b = {button} ; b:GetScript('PostClick')(b, 'LeftButton')")
    assert wow.eval(f"{C}.IsShown()") is False  # sent by the game, the ring goes
    assert list(wow.eval("Mock.sentChat").values()) == []  # never by the addon
    assert errors(wow) == []


def test_the_person_gets_a_whisper_by_the_whole_name(wow: WowRuntime):
    """ "directly address the person who buffed or invited me, without
    losing my current target". A whisper needs no target; on Forever it needs the surname."""
    boot(wow)
    wow.execute(
        """local real = UnitName
        UnitName = function(u)
          if u == "nameplate3" then return "Thalendra", "Moonbrook" end
          return real(u)
        end"""
    )
    buff(wow, "nameplate3", "Thalendra")
    sep = " " if wow.eval("Bastians.Client") == "forever" else "-"
    whole = f"Thalendra{sep}Moonbrook"
    assert wow.eval(f"{C}.Pending().full") == whole
    assert wow.eval(f"{R}.Item(1).secure") is None  # a whisper needs no secure button
    assert wow.eval(f"{R}.Item(1).tip").startswith("/w Thalendra ")
    wow.execute(f"Mock.sentChat = {{}}; Mock.emotes = {{}}; {C}.Fire(1, {R}.Item(1))")
    text, channel, _ = sent(wow)[-1]
    assert channel == "WHISPER" and text
    assert wow.eval("Mock.sentChat[1].target") == whole
    assert emotes(wow) == []  # nothing public goes with it
    assert wow.eval(f"{C}.IsShown()") is False
    assert errors(wow) == []


def test_a_guid_gives_the_whole_name_or_the_line_is_said_aloud(wow: WowRuntime):
    """, a buff from another realm: "No player named 'First Surname
    REALM' is currently playing". The GUID's seventh value is the realm, never a surname; Forever's
    sixth holds first name and surname, and its whisper takes no realm."""
    boot(wow)
    forever = wow.eval("Bastians.Client") == "forever"
    zara = "Zara Moonbrook" if forever else "Zara"  # the sixth value, as each client gives it
    wow.execute(
        f"""Mock.players = {{
          ['Player-2-Zara'] = {{ name = '{zara}', realm = 'OtherRealm', class = 'Mage', file = 'MAGE' }},
          ['Player-1-Ulf'] = {{ name = 'Ulf', realm = '', class = 'Mage', file = 'MAGE' }},
          ['Player-2-Odo'] = {{ name = 'Odo', realm = 'OtherRealm', class = 'Mage', file = 'MAGE' }},
        }}"""
    )
    whole = "Zara Moonbrook" if forever else "Zara-OtherRealm"
    cast(wow, "name = 'Arcane Intellect', spellId = 11, casterGUID = 'Player-2-Zara'")
    assert wow.eval(f"{C}.Pending().full") == whole
    assert wow.eval(f"{C}.Pending().who") == "Zara"  # the first name, as a unit gives it
    assert wow.eval(f"{R}.Item(1).tip").startswith("/w Zara ")
    wow.execute(f"Mock.sentChat = {{}}; {C}.Fire(1, {R}.Item(1))")
    assert wow.eval("Mock.sentChat[1].target") == whole
    # no surname: on Forever a whisper to the first name alone finds nobody (forever-api.md)
    cast(wow, "name = 'Thorns', spellId = 13, casterGUID = 'Player-1-Ulf'")
    assert wow.eval(f"{C}.Pending().full") == (None if forever else "Ulf")
    assert (wow.eval(f"{R}.Item(1).secure") is None) is (not forever)
    wow.execute(f"{C}.Hide()")
    # a first name and a realm: never "First Realm" as a whole name
    cast(wow, "name = 'Renew', spellId = 17, casterGUID = 'Player-2-Odo'")
    assert wow.eval(f"{C}.Pending().full") == (None if forever else "Odo-OtherRealm")
    assert errors(wow) == []


def test_a_unit_whose_first_value_holds_both_names_gets_no_realm(wow: WowRuntime):
    """Blizzard's NameUtil.GetUnitFirstName (1.60.1.70862): "name can be both name + surname"."""
    boot(wow)
    if wow.eval("Bastians.Client") != "forever":
        return  # retail's names hold no space
    wow.execute(
        """local real = UnitName
        UnitName = function(u)
          if u == "nameplate3" then return "Thalendra Moonbrook", "OtherRealm" end
          return real(u)
        end"""
    )
    assert wow.eval("Bastians.Compat.FullName('nameplate3')") == "Thalendra Moonbrook"
    assert errors(wow) == []


def test_only_a_spoken_petal_is_secure(wow: WowRuntime):
    boot(wow)
    buff(wow, "nameplate3", "Thalendra")
    assert wow.eval(f"{R}.Item(4).secure") is None  # the gesture: DoEmote needs none
    wow.execute("Mock.Fire('DUEL_REQUESTED', 'Zug')")
    for i in (1, 2, 3, 4):
        assert wow.eval(f"{R}.Item({i}).secure") is None  # bows, a whisper, not now
    assert errors(wow) == []


def test_the_own_wave_of_the_screenshot_opens_nothing(wow: WowRuntime):
    """the player's own wave at someone opened the ring."""
    boot(wow)
    wow.execute(
        "Mock.Fire('CHAT_MSG_TEXT_EMOTE', 'You wave at Thalendra Mistvale.', 'Zug Stonehand')"
    )
    assert wow.eval(f"{C}.IsShown()") is False
    assert errors(wow) == []


# ---------------------------------------------------------------------------------------------
# What exactly happened (courtesy.md "The matrix"): the spell, a fight, several buffs, the gesture.
# ---------------------------------------------------------------------------------------------

SPELLS = "Mock.spellNames[467] = 'Thorns'; Mock.spellNames[19740] = 'Blessing of Might'"


def test_the_spell_decides_the_row_and_is_named(wow: WowRuntime):
    boot(wow)
    wow.execute(SPELLS)
    buff(wow, "nameplate3", "Thalendra", "Thorns")
    facts = wow.eval(f"{C}.PendingFacts()")
    assert (facts.situation, facts.spell) == ("buff.nature.thorns", "Thorns")
    assert (facts.fight, facts.many) == (False, False)  # read all along, one buff
    assert (facts.zone, facts.near, facts.land) == ("Elwynn Forest", "Goldshire", "forest")
    wow.execute(f"{C}.Hide()")
    buff(wow, "nameplate4", "Borin", "Sprint")  # no line of its own: the general row, still named
    facts = wow.eval(f"{C}.PendingFacts()")
    assert (facts.situation, facts.spell) == ("buff", "Sprint")
    assert errors(wow) == []


def test_a_buff_that_landed_in_a_fight_says_so(wow: WowRuntime):
    boot(wow)
    wow.fire("PLAYER_REGEN_DISABLED")
    wow.execute("Mock.combat = true")
    buff(wow, "nameplate3", "Thalendra")
    wow.advance(10)
    wow.execute("Mock.combat = false")
    wow.fire("PLAYER_REGEN_ENABLED")
    assert wow.eval(f"{C}.PendingFacts().fight") is True
    wow.execute(f"{C}.Hide()")
    buff(wow, "nameplate4", "Borin")  # the next one, in peace
    assert wow.eval(f"{C}.PendingFacts().fight") is False
    assert errors(wow) == []


def test_two_buffs_of_one_caster_are_one_answer_for_the_one_we_can_name(wow: WowRuntime):
    boot(wow)
    wow.execute(SPELLS)
    wow.execute(
        """Mock.unitNames = { nameplate3 = 'Thalendra' }; Mock.guids = { nameplate3 = 'Player-1-T' }
        Mock.auras = {
          { name = 'Sprint', spellId = 2983, sourceUnit = 'nameplate3', expirationTime = 9000 },
          { name = 'Blessing of Might', spellId = 19740, sourceUnit = 'nameplate3',
            expirationTime = 9000 },
        }
        Mock.Fire('UNIT_AURA', 'player', {})"""
    )
    wow.advance(0.3)
    facts = wow.eval(f"{C}.PendingFacts()")
    assert (facts.situation, facts.spell, facts.many) == (
        "buff.blessing.might",
        "Blessing of Might",
        True,
    )
    words = [row[0] for row in trace(wow)[:2]]
    assert sorted(words) == ["answered lately", "ask"]  # once per person
    assert errors(wow) == []


def test_what_the_gesture_was_decides_the_row(wow: WowRuntime):
    boot(wow)
    of = f"{M}.Situation"
    for text, row in [
        ("Zug thanks you.", "emote.friendly.thank"),
        ("Zug hugs you.", "emote.friendly.love"),
        ("Zug blows you a kiss.", "emote.friendly.love"),
        ("Zug bows before you.", "emote.friendly.bow"),
        ("Zug salutes you with respect.", "emote.friendly.bow"),
        ("Zug cheers at you.", "emote.friendly.cheer"),
        ("Zug applauds at you. Bravo!", "emote.friendly.cheer"),
        ("Zug waves at you.", "emote.friendly"),
        ("Zug smiles at you.", "emote.friendly"),
        ("Zug spits on you.", "emote.rude"),
    ]:
        assert wow.eval(f"{of}({{ kind = 'emote', text = '{text}' }})") == row, text
    wow.execute("Mock.Fire('CHAT_MSG_TEXT_EMOTE', 'Zug thanks you.', 'Zug-Realm')")
    assert wow.eval(f"{C}.PendingFacts().situation") == "emote.friendly.thank"
    lines = [wow.eval(f"{R}.Item({i}).line") for i in (1, 2, 3)]
    assert all(line[1].startswith("emote.friendly") for line in lines)
    assert errors(wow) == []
