"""The fact layer (Core Facts.lua, library.md §4, ADR 0028): state facts read on demand, happenings
raised from the client's events only while someone watches them, the injector (Fake, Emit) that
authors and these tests share, and the inspector's report."""

from harness import WowRuntime

F = "Bastians.Facts"
OWNER = "OWNER = OWNER or { name = 'Test', title = 'Test', errors = {}, undo = {}, jobs = {} }"
HOGGER = "Creature-0-1-0-1-448-0000000001"
WOLF = "Creature-0-1-0-1-299-0000000002"
ME = "Player-1-00000001"


def watch(wow: WowRuntime, name: str) -> None:
    """Collects every payload of the happening into GOT[name]."""
    wow.execute(
        f"{OWNER}; GOT = GOT or {{}}; GOT['{name}'] = {{}}; "
        f"{F}.Watch(OWNER, '{name}', function(_, p) table.insert(GOT['{name}'], p) end)"
    )


def got(wow: WowRuntime, name: str) -> list:
    return list(wow.eval(f"GOT['{name}']").values())


def test_state_facts_read_the_client(core: WowRuntime):
    core.execute("Mock.money = 12345; Mock.level = 7")
    player = core.eval(f"{F}.Get('player')")
    assert player.level == 7 and player.faction == "Alliance" and player.group == 1
    assert player.dead == "alive"
    core.execute(
        "Mock.player.stealthed = true; Mock.player.indoors = true; Mock.auras = { { name = 'Invisibility', spellId = 66 } }"
    )
    state = core.eval(f"{F}.Get('state')")
    assert state.stealthed is True and state.indoors is True and state.invisible is True
    assert state.combat is False and state.mounted is False
    pos = core.eval(f"{F}.Get('position')")
    assert pos.zone == "Elwynn Forest" and pos.subzone == "Goldshire" and pos.indoors is True
    assert pos.uiMapID == 1429
    t = core.eval(f"{F}.Get('time')")
    assert t.server == 1760000000 and 0 <= t.hour < 24 and isinstance(t.night, bool)
    # the target: a creature by its GUID, within 10 yards, turned to the character
    core.execute(
        f"Mock.guids = {{ target = '{HOGGER}' }}; Mock.unitNames.target = 'Hogger'; "
        "Mock.unitDistance.target = 6; Mock.unitTargets.target = 'player'; "
        "Mock.unitHealth.target = { 50, 200 }; Mock.unitLevels.target = 11; Mock.unitReaction.target = 2"
    )
    tgt = core.eval(f"{F}.Get('target')")
    assert tgt.ref == "npc:448" and tgt.name == "Hogger" and tgt.within == 10
    assert tgt.targetsPlayer is True and tgt.alive is True and tgt.level == 11
    assert abs(tgt.health - 0.25) < 1e-9 and tgt.reaction == 2
    core.execute("Mock.unitDistance.target = 20; Mock.unitTargets.target = nil")
    tgt = core.eval(f"{F}.Get('target')")
    assert tgt.within == 28 and tgt.targetsPlayer is False
    # in combat the distance stays unknown: retail blocks CheckInteractDistance there (31.10.2026)
    core.execute("Mock.SetCombat(true); Mock.distanceAsked = 0")
    core.execute(
        "local f = CheckInteractDistance; "
        "CheckInteractDistance = function(...) Mock.distanceAsked = Mock.distanceAsked + 1 "
        "return f(...) end"
    )
    tgt = core.eval(f"{F}.Get('target')")
    assert tgt.within is None and core.eval("Mock.distanceAsked") == 0
    core.execute("Mock.SetCombat(false)")
    assert core.eval(f"{F}.Get('mouseover')") is None  # no such unit
    assert core.eval(f"{F}.Get('no-such-fact')") is None
    assert core.errors == []


def test_the_injector_fakes_a_state_and_the_report_says_so(core: WowRuntime):
    core.execute(f"{F}.Fake('position', {{ map = 0, wx = -9460, wy = 62, zone = 'Faked' }})")
    assert core.eval(f"{F}.Get('position').zone") == "Faked"
    assert core.eval(f"{F}.IsFaked('position')") is True
    report = core.eval(f"{F}.Report()")
    assert report.position.zone == "Faked" and report.faked.position is True
    assert report.player.level == 12 and "player" not in report.faked
    core.execute(f"{F}.Fake('position', nil)")
    assert core.eval(f"{F}.Get('position').zone") == "Elwynn Forest"
    names = core.eval(f"{F}.Names()")
    assert "position" in names.states.values() and "say" in names.happenings.values()
    assert core.eval("Bastians:GetService('facts') == Bastians.Facts") is True


def test_events_are_registered_only_while_a_happening_is_watched(core: WowRuntime):
    assert core.eval(f"{F}.IsListening('CHAT_MSG_SAY')") is False
    core.execute(f"{OWNER}; ID1 = {F}.Watch(OWNER, 'say', function() end)")
    core.execute(f"ID2 = {F}.Watch(OWNER, 'say', function() end)")
    assert core.eval(f"{F}.IsListening('CHAT_MSG_SAY')") is True
    assert core.eval(f"{F}.IsListening('CHAT_MSG_GUILD')") is True
    core.execute(f"{F}.Unwatch(ID1)")
    assert core.eval(f"{F}.IsListening('CHAT_MSG_SAY')") is True
    core.execute(f"{F}.Unwatch(ID2)")
    assert core.eval(f"{F}.IsListening('CHAT_MSG_SAY')") is False
    # UnwatchAll drops every watcher of an owner, nothing of another's
    core.execute(
        f"OTHER = {{ name = 'O', errors = {{}}, undo = {{}} }}; {F}.Watch(OTHER, 'loot', function() end)"
    )
    core.execute(f"{F}.Watch(OWNER, 'loot', function() end); {F}.UnwatchAll(OWNER)")
    assert core.eval(f"{F}.IsListening('LOOT_OPENED')") is True
    core.execute(f"{F}.UnwatchAll(OTHER)")
    assert core.eval(f"{F}.IsListening('LOOT_OPENED')") is False
    assert core.eval(f"(pcall({F}.Watch, OWNER, 'no-such', function() end))") is False


def test_the_players_own_lines_are_said_other_peoples_are_not(core: WowRuntime):
    watch(core, "say")
    core.execute(f"Mock.guids = {{ target = '{HOGGER}' }}")
    core.fire(
        "CHAT_MSG_SAY",
        "Do you know anything about Mara?",
        "Mockchar-MockRealm",
        "Common",
        "",
        "",
        "",
        0,
        0,
        "",
        0,
        1,
        ME,
    )
    core.fire(
        "CHAT_MSG_SAY",
        "Mara who?",
        "Otherguy-MockRealm",
        "Common",
        "",
        "",
        "",
        0,
        0,
        "",
        0,
        2,
        "Player-1-00000002",
    )
    core.fire(
        "CHAT_MSG_GUILD", "hello guild", "Mockchar", "Common", "", "", "", 0, 0, "", 0, 3
    )  # no guid: by name
    lines = got(core, "say")
    assert [(p.channel, p.text) for p in lines] == [
        ("say", "Do you know anything about Mara?"),
        ("guild", "hello guild"),
    ]
    assert list(lines[0].words.values()) == ["do", "you", "know", "anything", "about", "mara"]
    assert lines[0].target == "npc:448"
    payload, at = core.eval(f"{F}.Last('say')")
    assert payload.text == "hello guild" and at == 1760000000


def test_gestures_own_received_and_heard(core: WowRuntime):
    watch(core, "emote")
    watch(core, "received")
    watch(core, "heard")
    core.execute(f"Mock.guids = {{ target = '{HOGGER}' }}")
    core.execute("DoEmote('kneel', 'target')")  # the hooked DoEmote: locale-free token
    core.execute("Bastians.Compat.Emote('BOW')")
    emotes = got(core, "emote")
    assert [(p.token, p.ref) for p in emotes] == [("KNEEL", "npc:448"), ("BOW", "npc:448")]
    core.fire(
        "CHAT_MSG_TEXT_EMOTE",
        "Otherguy hugs you.",
        "Otherguy-MockRealm",
        "",
        "",
        "",
        "",
        0,
        0,
        "",
        0,
        4,
        "Player-1-00000002",
    )
    core.fire(
        "CHAT_MSG_TEXT_EMOTE",
        "Otherguy dances.",
        "Otherguy-MockRealm",
        "",
        "",
        "",
        "",
        0,
        0,
        "",
        0,
        5,
        "Player-1-00000002",
    )
    core.fire(
        "CHAT_MSG_TEXT_EMOTE",
        "You kneel before Hogger.",
        "Mockchar",
        "",
        "",
        "",
        "",
        0,
        0,
        "",
        0,
        6,
        ME,
    )
    assert [p.text for p in got(core, "received")] == ["Otherguy hugs you."]
    core.fire(
        "CHAT_MSG_MONSTER_YELL",
        "Hear ye! The Defias ride tonight!",
        "Town Crier",
        "",
        "",
        "",
        "",
        0,
        0,
        "",
        0,
        7,
        HOGGER,
    )
    heard = got(core, "heard")
    assert heard[0].channel == "yell" and heard[0].npc == "Town Crier" and heard[0].ref == "npc:448"
    assert "defias" in heard[0].words.values()


def test_loot_is_an_item_taken_from_its_source(core: WowRuntime):
    watch(core, "loot")
    core.execute(
        f"Mock.loot = {{ fishing = false, slots = {{ {{ item = 2589, name = 'Linen Cloth', quantity = 2, source = '{HOGGER}' }},"
        " { item = 209, name = 'Red Defias Bandana', quantity = 1, source = '" + HOGGER + "' } } }"
    )
    core.fire("LOOT_OPENED")
    assert got(core, "loot") == []  # opening is not taking
    core.fire("LOOT_SLOT_CLEARED", 2)
    core.fire("LOOT_SLOT_CLEARED", 2)  # cleared once
    core.fire("LOOT_SLOT_CLEARED", 9)  # no such slot
    loot = got(core, "loot")
    assert len(loot) == 1
    assert loot[0].item == "item:209" and loot[0].count == 1 and loot[0].fishing is False
    assert core.eval("GOT.loot[1]['from']") == "npc:448"
    core.execute(
        "Mock.loot = { fishing = true, slots = { { item = 6291, name = 'Raw Brilliant Smallfish' } } }"
    )
    core.fire("LOOT_READY")
    core.fire("LOOT_SLOT_CLEARED", 1)
    fish = got(core, "loot")[-1]
    assert fish.item == "item:6291" and fish.fishing is True
    assert core.eval("GOT.loot[2]['from']") is None


def combat(wow: WowRuntime, subevent: str, source: str, dest: str, *rest) -> None:
    extra = ", ".join(repr(x) if isinstance(x, str) else str(x) for x in rest)
    wow.execute(
        f"Mock.combatLogEvent = {{ n = 15, 0, '{subevent}', false, '{source}', 'S', 0, 0, '{dest}', 'D', 0, 0"
        + (", " + extra if extra else "")
        + " }"
    )
    wow.fire("COMBAT_LOG_EVENT_UNFILTERED")


def test_kills_come_from_party_kill_by_me_or_the_group(core: WowRuntime):
    """Retail 12.x forbids the combat log; PARTY_KILL
    fires for the kills of the character and its group, as Total RP 3: Extended uses it."""
    watch(core, "kill")
    assert core.eval(f"{F}.IsListening('PARTY_KILL')") is True
    core.fire("PARTY_KILL", ME, HOGGER)
    core.execute(
        "Mock.groupSize = 2; Mock.guids = { party1 = 'Player-1-00000003' }; "
        "Mock.unitNames.party1 = 'Friend'"
    )
    core.fire("PARTY_KILL", "Player-1-00000003", WOLF)
    core.fire("PARTY_KILL", "Player-1-00000009", WOLF)  # neither me nor the group: unknown killer
    core.execute("SECRET = Mock.Secret()")
    core.eval(f"(pcall(function() Mock.Fire('PARTY_KILL', SECRET, '{WOLF}') end))")
    kills = got(core, "kill")
    assert [(p.ref, p.by) for p in kills[:3]] == [
        ("npc:448", "me"),
        ("npc:299", "group"),
        ("npc:299", None),
    ]
    assert kills[3].ref == "npc:299" and kills[3].by is None  # a secret killer is unknown
    assert core.errors == []


def test_the_combat_log_is_read_only_where_the_client_allows_it(core: WowRuntime):
    # closed (retail measured, Forever until the probe): nothing registers it, the facts stay unknown
    assert core.eval("Bastians.Compat.Has.CombatLog") is False
    for name in ("died", "damage", "healed"):
        watch(core, name)
        assert core.eval(f"{F}.Available('{name}')") is False
    assert core.eval(f"{F}.IsListening('COMBAT_LOG_EVENT_UNFILTERED')") is False
    assert (
        core.eval(f"{F}.Available('kill')") is True and core.eval(f"{F}.Available('say')") is True
    )
    core.execute(f"{F}.UnwatchAll(OWNER)")
    # open: deaths, damage and healing from the combat log
    core.execute("Bastians.Compat.Has.CombatLog = true")
    for name in ("died", "damage", "healed"):
        watch(core, name)
    assert core.eval(f"{F}.IsListening('COMBAT_LOG_EVENT_UNFILTERED')") is True
    combat(core, "UNIT_DIED", "", WOLF)
    combat(core, "SWING_DAMAGE", ME, WOLF, 12)
    combat(core, "SPELL_DAMAGE", ME, WOLF, 133, "Fireball", 4, 40)
    combat(core, "SPELL_HEAL", ME, HOGGER, 2050, "Lesser Heal", 2, 35)
    combat(core, "SPELL_DAMAGE", "Player-1-00000002", WOLF, 133, "Fireball", 4, 40)
    assert [p.ref for p in got(core, "died")] == ["npc:299"]
    assert [(p.ref, p.amount, p.spell) for p in got(core, "damage")] == [
        ("npc:299", 12, None),
        ("npc:299", 40, 133),
    ]
    assert [(p.ref, p.amount) for p in got(core, "healed")] == [("npc:448", 35)]
    assert core.errors == []


def test_reading_mail_windows_casts_and_the_rest(core: WowRuntime):
    for name in (
        "read",
        "mail",
        "opened",
        "cast",
        "quest",
        "level",
        "death",
        "zone",
        "combat",
        "money",
        "screenshot",
        "targeted",
        "moved",
    ):
        watch(core, name)
    core.execute(
        "Mock.itemText = { item = 'A Letter from Mara', text = 'Dear brother, the Defias took me north.', page = 1 }"
    )
    core.fire("ITEM_TEXT_READY")
    read = got(core, "read")[0]
    assert read.item == "A Letter from Mara" and "defias" in read.words.values() and read.page == 1
    core.fire("MAIL_SHOW")
    core.fire("MAIL_INBOX_UPDATE")
    core.fire("MAIL_SEND_SUCCESS")
    mail = got(core, "mail")
    assert [bool(p.opened) for p in mail] == [True, False, False] and mail[0].at.map is not None
    assert mail[1].received is True and mail[2].sent is True
    core.execute(f"Mock.guids = {{ npc = '{HOGGER}' }}")
    core.fire("GOSSIP_SHOW")
    core.fire("MERCHANT_SHOW")
    kinds = [(p.kind, p.ref) for p in got(core, "opened")]
    assert (
        ("gossip", "npc:448") in kinds
        and ("vendor", "npc:448") in kinds
        and ("mail", None) in kinds
    )
    core.fire("UNIT_SPELLCAST_SENT", "player", "Peacebloom", "Cast-1", 2366)
    core.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 2366)
    core.fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "Cast-2", 2366)
    casts = got(core, "cast")
    assert len(casts) == 1 and casts[0].spell == 2366 and casts[0].target == "Peacebloom"
    core.fire("QUEST_ACCEPTED", 1, 176)
    core.fire("QUEST_TURNED_IN", 176, 100, 50)
    core.fire("QUEST_REMOVED", 177)
    quests = got(core, "quest")
    assert quests[0].id == 176 and quests[0].accepted is True
    assert quests[1].id == 176 and quests[1].turned_in is True and quests[2].removed is True
    core.fire("PLAYER_LEVEL_UP", 13)
    assert got(core, "level")[0].level == 13
    core.fire("PLAYER_DEAD")
    core.fire("PLAYER_UNGHOST")
    death = got(core, "death")
    assert death[0].dead is True and death[0].at.map is not None and death[1].alive is True
    core.execute("Mock.subZoneText = 'Northshire Valley'")
    core.fire("ZONE_CHANGED")
    assert got(core, "zone")[0].subzone == "Northshire Valley"
    core.fire("PLAYER_REGEN_DISABLED")
    core.fire("PLAYER_REGEN_ENABLED")
    assert [bool(p.entered) for p in got(core, "combat")] == [True, False]
    core.execute("Mock.money = 1000")
    core.fire("PLAYER_MONEY")
    core.execute("Mock.money = 1250")
    core.fire("PLAYER_MONEY")
    money = got(core, "money")
    assert money[0].copper == 1000 and money[0].delta is None and money[1].delta == 250
    core.fire("SCREENSHOT_SUCCEEDED")
    assert got(core, "screenshot")[0].at.map is not None
    core.execute(f"Mock.guids.nameplate1 = '{WOLF}'; Mock.unitTargets.nameplate1 = 'player'")
    core.fire("UNIT_TARGET", "nameplate1")
    core.fire("UNIT_TARGET", "player")
    core.execute("Mock.unitTargets.nameplate1 = nil")
    core.fire("UNIT_TARGET", "nameplate1")
    targeted = got(core, "targeted")
    assert len(targeted) == 1 and targeted[0].ref == "npc:299" and targeted[0].unit == "nameplate1"
    core.fire("PLAYER_STARTED_MOVING")
    core.fire("PLAYER_STOPPED_MOVING")
    moved = got(core, "moved")
    assert moved[0].moving is True and moved[1].moving is False and moved[1].at.map is not None
    assert core.errors == []


def test_emit_injects_a_happening_and_a_failing_watcher_stops_nothing(core: WowRuntime):
    watch(core, "loot")
    core.execute(f"{F}.Watch(OWNER, 'loot', function() error('boom') end)")
    core.execute("N = 0; " + F + ".Watch(OWNER, 'loot', function() N = N + 1 end)")
    core.execute(f"{F}.Emit('loot', {{ item = 'item:1', count = 1 }})")
    assert got(core, "loot")[0].item == "item:1" and core.eval("N") == 1
    assert core.eval("#OWNER.errors") == 1  # the failing watcher was noted on its owner
    assert core.eval(f"{F}.Last('loot').item") == "item:1"
    assert (
        core.eval("Bastians.Compat.TakeScreenshot()") is True and core.eval("Mock.screenshots") == 1
    )


def test_the_facts_the_engine_reads_since_l4(core: WowRuntime):
    """library.md 8.4: the player's class and race tokens and health, the facing, the calendar
    day, the worn items, the turned-in quests; the happenings bags, equipment, xp, learned and
    social; the source-less happenings fire only from the injector."""
    core.execute(
        "Mock.equipped[1] = 752; Mock.unitHealth.player = { 50, 100 }; Mock.facing = math.pi / 2"
    )
    player = core.eval(f"{F}.Get('player')")
    assert (player["class"], player.race, player.health) == ("MAGE", "Human", 0.5)
    assert abs(core.eval(f"{F}.Get('position').facing") - 90) < 1e-9
    t = core.eval(f"{F}.Get('time')")
    assert 1 <= t.month <= 12 and 1 <= t.day <= 31
    assert dict(core.eval(f"{F}.Get('equipped')").items()) == {752: 1}
    assert isinstance(dict(core.eval(f"{F}.Get('quests')").items()), dict)
    for name in ("bags", "equipment", "xp", "learned", "social", "zone"):
        watch(core, name)
    core.fire("BAG_UPDATE_DELAYED")
    core.fire("PLAYER_EQUIPMENT_CHANGED", 1, False)
    core.fire("PLAYER_XP_UPDATE", "player")
    core.fire("LEARNED_SPELL_IN_TAB", 2383, 1)
    core.fire("GROUP_ROSTER_UPDATE")
    core.fire("PLAYER_GUILD_UPDATE")
    core.fire("PLAYER_UPDATE_RESTING")
    assert got(core, "bags")[0].changed is True
    assert got(core, "equipment")[0].slot == 1
    assert len(got(core, "xp")) == 1
    assert got(core, "learned")[0].spell == "spell:2383"
    assert len(got(core, "social")) == 2
    assert len(got(core, "zone")) == 1  # resting changes
    assert core.eval("Bastians.Compat.PlayFile('Interface\\AddOns\\X\\a.ogg', 'Dialog')") == 1
    core.execute("Bastians.Compat.StopFile(1)")
    assert core.eval("Mock.stopped[1]") == 1
    assert core.errors == []


def test_the_former_sourceless_facts_come_from_the_game(core: WowRuntime):
    """library.md 8.4: discovery, reputation, skills,
    PvP, duels, trades, pets and mounts, travel, the merchant, crafting and item use each come from
    the client's events, lines or hooks."""
    names = ("discovered", "reputation", "skills", "pvp", "duel", "traded", "tamed", "summoned")
    for name in (*names, "travel", "merchant", "crafted", "used"):
        watch(core, name)
        assert core.eval(f"{F}.Available('{name}')") is True, name
    core.fire("CHAT_MSG_SYSTEM", "Discovered Goldshire: 40 experience gained")
    core.fire("UI_INFO_MESSAGE", 0, "Discovered: Crystal Lake")
    assert [p.name for p in got(core, "discovered")] == ["Goldshire", "Crystal Lake"]
    core.fire("UPDATE_FACTION")
    assert len(got(core, "reputation")) == 1
    assert core.eval(f"{F}.Get('reputation', 'faction:529').standing") == 4
    core.fire("SKILL_LINES_CHANGED")
    assert len(got(core, "skills")) == 1
    core.execute("Mock.pvp = true")
    core.fire("PLAYER_FLAGS_CHANGED", "player")
    core.fire("PLAYER_FLAGS_CHANGED", "player")  # still flagged: once
    core.fire("CHAT_MSG_COMBAT_HONOR_GAIN", "honour")
    core.execute("Mock.instanceType = 'pvp'")
    core.fire("ZONE_CHANGED_NEW_AREA")
    core.execute("Mock.instanceType = 'none'")
    assert [p.kind for p in got(core, "pvp")] == ["flagged", "honor_kill", "battleground"]
    me = core.eval("UnitName('player')")
    core.fire("DUEL_FINISHED")
    core.fire("CHAT_MSG_SYSTEM", f"{me} has defeated Someone in a duel")
    core.fire("CHAT_MSG_SYSTEM", f"{me} has fled from Someone in a duel")
    duel = got(core, "duel")
    assert duel[0].finished is True and [d.result for d in duel[1:]] == ["won", "lost"]
    core.fire("UI_INFO_MESSAGE", 0, "Trade complete.")
    assert got(core, "traded")[0].traded is True
    core.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 1515)
    core.execute(f"Mock.guids = {{ pet = '{WOLF}' }}")
    core.fire("UNIT_PET", "player")
    assert got(core, "tamed")[0].ref == "npc:299"
    core.execute("Mock.mounted = true")
    core.fire("PLAYER_MOUNT_DISPLAY_CHANGED")
    assert [p.kind for p in got(core, "summoned")] == ["pet", "mount"]
    # a flight, then a hearth across Elwynn
    core.execute("Mock.onTaxi = true")
    core.fire("PLAYER_CONTROL_LOST")
    core.execute("Mock.onTaxi = false; Mock.playerMapPos = { x = 0.8, y = 0.65 }")
    core.fire("PLAYER_CONTROL_GAINED")
    core.advance(30)
    core.execute(f"{F}.JUMP_YARDS = 50")  # the mock's Elwynn is a few hundred yards wide
    core.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 8690)
    core.execute("Mock.playerMapPos = { x = 0.2, y = 0.3 }")
    core.fire("ZONE_CHANGED_NEW_AREA")
    travel = got(core, "travel")
    assert [p.kind for p in travel] == ["taxi", "hearth"]
    assert (travel[0]["from"].wx, travel[0]["from"].wy) != (travel[0].to.wx, travel[0].to.wy)
    # the merchant: the bags first, then the money; then a repair
    core.execute("Mock.money = 1000; Mock.bagSlots[0] = { { itemID = 159, count = 1 } }")
    core.fire("MERCHANT_SHOW")
    core.execute("Mock.bagSlots[0] = { { itemID = 159, count = 3 } }")
    core.fire("BAG_UPDATE_DELAYED")
    assert got(core, "merchant") == []  # the money has not moved yet
    core.execute("Mock.money = 950")
    core.fire("PLAYER_MONEY")
    core.execute("Mock.money = 1100; Mock.bagSlots[0] = { { itemID = 159, count = 1 } }")
    core.fire("PLAYER_MONEY")
    core.fire("BAG_UPDATE_DELAYED")
    core.execute("Mock.money = 1000")
    core.fire("UPDATE_INVENTORY_DURABILITY")
    shop = [(p.kind, p.item, p.count) for p in got(core, "merchant")]
    assert shop == [("bought", "item:159", 2), ("sold", "item:159", 2), ("repaired", None, None)]
    core.fire("MERCHANT_CLOSED")
    core.fire("CHAT_MSG_LOOT", "You create: |cffffffff|Hitem:2580::::::::|h[Elixir]|h|r.")
    core.fire("CHAT_MSG_LOOT", "You create: |cffffffff|Hitem:2581::::::::|h[Bandage]|h|rx2.")
    assert [(p.item, p.count) for p in got(core, "crafted")] == [("item:2580", 1), ("item:2581", 2)]
    core.execute(
        "Mock.bagSlots[0] = { { itemID = 6948, count = 1 } }; C_Container.UseContainerItem(0, 1)"
    )
    assert got(core, "used")[0].item == "item:6948"
    assert core.errors == []
