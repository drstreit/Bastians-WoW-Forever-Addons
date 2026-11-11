"""Bastian's Voice (voice.md): the play action on quests, zones, areas, bosses and readables through
Spoken's test doubles, Voice's own Spoken source, the heard list, the Lore Orbit (compact, wide,
scale, place) and the conversation that replaces the game's quest windows."""

import math

from harness import WowRuntime
from pages import band_buttons, click_sheet_button

CORE, DATA, QUESTS, BROWSER, VOICE = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Browser",
    "Bastians_Voice",
)
SPOKEN = ("Spoken", "Spoken_Quests", "Spoken_Places", "Spoken_Readables", "Spoken_NPCs")
V = "Bastians:GetModule('Voice')"
M = f"{V}.Voice.Model"
ORBIT = f"{V}.Orbit"
TALK = f"{V}.Talk"


NO_VOICE = "Spoken is not installed, and the game lists no voice yet (Options, Accessibility, Text to Speech)"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, *SPOKEN, QUESTS, VOICE)))
    wow.run_frames(10)
    wow.advance(0.3)
    return wow


def actions(wow: WowRuntime, ref: str) -> list[str]:
    return [a.id for a in wow.eval(f"Bastians:GetActions('{ref}', {{ source = 'test' }})").values()]


def run(wow: WowRuntime, ref: str) -> None:
    wow.execute(f"Bastians:RunAction('voice.play', '{ref}', {{ source = 'test' }})")


def queue(wow: WowRuntime) -> list:
    return list(wow.eval("Spoken:GetQueue()").values())


def errors(wow: WowRuntime) -> list[str]:
    return wow.errors + [
        line.text
        for line in wow.eval("Bastians:GetLog()").values()
        if line.level == "error" and "registered no data" not in line.text
    ]


def bubbles(wow: WowRuntime) -> list:
    return [b.item for b in wow.eval(f"{ORBIT}.Visible()").values()]


def click(wow: WowRuntime, title: str) -> None:
    """Clicks the bubble titled so."""
    index = next(i for i, b in enumerate(bubbles(wow)) if b.title == title) + 1
    wow.execute(f"{ORBIT}.Visible()[{index}]:Click()")


def test_the_model_is_pure(core: WowRuntime):
    core.start(VOICE)
    assert core.eval(f"{M}.AreaKey('The Fargodeep Mine')") == "fargodeep mine"
    assert core.eval(f'{M}.AreaKey("Lion\'s Pride Inn")') == "lions pride inn"
    assert core.eval(f"{M}.AreaKey('')") is None
    # bearings: degrees clockwise from where the player faces (world x north, y west)
    assert core.eval(f"{M}.Bearing(0, 0, 0, 10, 0)") == 0  # ahead
    assert core.eval(f"{M}.Bearing(0, 0, 0, 0, 10)") == 270  # west is to the left
    assert core.eval(f"{M}.Bearing(0, 0, 0, -10, 0)") == 180  # behind
    assert core.eval(f"{M}.Bearing(0, 0, math.pi / 2, 0, 10)") == 0  # facing west, target west
    assert core.eval(f"{M}.Bearing(nil, 0, 0, 1, 1)") is None
    # a quest to this character
    assert core.eval(f"{M}.QuestStatus({{ minLevel = 5 }}, nil, true, 12)") is None
    assert core.eval(f"{M}.QuestStatus(nil, {{ readyForTurnIn = true }}, false, 12)") == "ready"
    assert core.eval(f"{M}.QuestStatus(nil, {{}}, false, 12)") == "log"
    assert core.eval(f"{M}.QuestStatus({{ minLevel = 20 }}, nil, false, 12)") is None
    assert core.eval(f"{M}.QuestStatus({{ minLevel = 5 }}, nil, false, 12)") == "available"
    # the caps: 6 places, 7 outer, 4 moons; the rest goes to the "+n" bubble
    core.execute(
        """
        places, outer = {}, {}
        for i = 1, 8 do places[i] = { kind = "area", title = "a" .. i } end
        for i = 1, 9 do outer[i] = { kind = "npc", title = "n" .. i, quests = {} } end
        for i = 1, 6 do outer[1].quests[i] = { kind = "quest", title = "q" .. i, status = "available" } end
        p, o, rest = M.Pick(places, outer)
        """.replace("M.", f"{M}.")
    )
    assert core.eval("#p, #o, #rest") == (6, 7, 6)
    assert core.eval("#o[1].quests, o[1].more") == (4, 2)
    # the layout: the first place at the top, an outer item at its bearing, its quests as moons
    core.execute(
        """
        layout = M.Layout({ { kind = "zone", size = "place", title = "z" }, { kind = "area", title = "a" } },
          { { kind = "npc", title = "n", bearing = 90, quests = { { kind = "quest", title = "q1" }, { kind = "quest", title = "q2" } } },
            { kind = "boss", title = "b", bearing = 95 } })
        """.replace("M.", f"{M}.")
    )
    slots = list(core.eval("layout").values())
    assert [s.kind for s in slots] == ["zone", "area", "npc", "quest", "quest", "boss"]
    assert round(slots[0].x) == 0 and round(slots[0].y) == 64 and slots[0].r == 20
    assert round(slots[2].x) == 109 and round(slots[2].y) == 0  # east at 90 degrees
    assert slots[5].deg >= slots[2].deg + 30  # two outer bubbles keep their gap
    assert slots[3].x > 109  # the moons fan outward from the giver
    # the saved place: the nearest corner and an offset that survives a resolution change
    assert core.eval(f"{M}.Corner(100, 1000, 1920, 1080)") == ("TOPLEFT", 100, -80)
    assert core.eval(f"{M}.Corner(1800, 100, 1920, 1080)") == ("BOTTOMRIGHT", -120, 100)
    assert core.eval(f"{M}.Place('TOPLEFT', 100, -80, 2560, 1440)") == (100, 1360)
    # the auto size: 36 % of the screen height, 50..200 % on top
    assert round(core.eval(f"{M}.Size(1080, 100)"), 1) == 388.8
    assert round(core.eval(f"{M}.Size(2880, 50)"), 1) == 518.4
    assert round(core.eval(f"{M}.Size(1080, 300)"), 1) == 777.6  # clamped to 200 %
    assert core.eval(f"{M}.CreatureID('Creature-0-1234-0-1-240-0000ABCD')") == 240
    assert core.eval(f"{M}.CreatureID('Player-1-00000001')") is None
    assert core.eval(f"{M}.ReadingTime('one two three')") == 6
    assert core.eval(f"{M}.Key('area', 1429, 'goldshire')") == "s:1429:goldshire"


def test_without_spoken_there_is_no_voice_and_quests_has_no_bridge(wow: WowRuntime):
    wow.execute("Mock.ttsVoices = {}")  # a client without text to speech either
    boot(wow, CORE, DATA, QUESTS, VOICE)
    assert "voice.play" not in actions(wow, "quest:176")
    assert wow.eval("Bastians:GetModule('Quests.Spoken')") is None
    assert wow.eval(f"{V}.options[1].text()") == NO_VOICE  # why nothing reads, not only "missing"
    assert wow.eval(f"{V}.title") == "Orbiter"  # "call it Orbiter"
    assert wow.eval("Bastians:GetModule('Voice.Talk').db.profile.pauseKey") == "shift"
    assert "map.lore" not in actions(wow, "zone:1429")
    # the orbit still shows (the quests of the zone need no voice pack)
    assert wow.eval("BastiansVoiceOrbit:IsShown()") is True
    kinds = sorted(set(b.kind for b in bubbles(wow)))
    assert kinds == ["area", "npc", "object", "zone"]
    assert errors(wow) == []


def test_lines_of_every_kind_play_through_spoken(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f"{V}.options[1].text()") == (
        "Spoken reads: quests, zones and areas, readables, boss stories"
    )
    has = "Bastians:GetAction('voice.play').has"
    # only where an installed pack has the line (ADR 0013)
    assert wow.eval(f"{has}('quest:176')") is True
    assert wow.eval(f"{has}('quest:999')") is False
    assert wow.eval(f"{has}('zone:1429')") is True
    assert wow.eval(f"{has}('zone:1453')") is False
    assert wow.eval(f"{has}('npc:448')") is True  # Hogger has a story
    assert wow.eval(f"{has}('npc:240')") is False
    assert wow.eval(f"{has}('object:1734')") is True  # the Wanted Poster is a readable
    assert wow.eval(f"{has}('item:1931')") is False
    # a zone plays in Voice's own source, and the same click stops it
    run(wow, "zone:1429")
    q = queue(wow)
    assert len(q) == 1 and q[0].key == "z:1429" and q[0].source.key == "bastians"
    assert q[0].path == "Interface\\AddOns\\SpokenPlacesAudio\\Sounds\\1429/zone.mp3"
    assert q[0].length == 161 and q[0].present.label == "Elwynn Forest"
    assert wow.eval("Bastians:GetAction('voice.play').active('zone:1429')") is True
    run(wow, "zone:1429")
    assert queue(wow) == []
    # a readable: one clip per page, grouped as one book; a page without a recorded length has none
    run(wow, "object:1734")
    q = queue(wow)
    assert [c.key for c in q] == ["r:41:501", "r:41:502"]
    assert q[0].group == "book:41" and q[0].length == 12 and q[1].length is None
    assert q[0].present.header == "Wanted Poster" and q[0].present.label == "page 1 of 2"
    wow.execute("Spoken:StopAll()")
    # a boss story is text only, shown in the narrator; refused when the narrator shows no words
    run(wow, "npc:448")
    q = queue(wow)
    assert len(q) == 1 and q[0].textOnly is True and "Riverpaw" in q[0].present.transcript
    assert q[0].length == 6 and q[0].present.label == "Hogger"
    wow.execute("Spoken:StopAll(); Spoken.narrator = false")
    run(wow, "npc:448")
    assert queue(wow) == [] and any("did not take" in line for line in wow.chat)
    wow.execute("Spoken.narrator = true")
    # a quest keeps Spoken Quests' player
    run(wow, "quest:176")
    q = queue(wow)
    assert len(q) == 1 and q[0].questID == 176 and q[0].origin == "Bastians_Voice"
    assert q[0].source.key == "quests" and q[0].name == "Marshal Dughan"
    run(wow, "quest:176")
    assert queue(wow) == []
    run(wow, "quest:999")
    assert any("No voice line" in line for line in wow.chat)
    assert errors(wow) == []


def test_a_finished_line_is_heard_and_hosts_hear_of_it(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"""seen = {{}}
        {V}:On('BASTIANS_ACTION_STATE', function(_, _, id) seen[#seen + 1] = id end)
        changed = 0
        {V}:On('BASTIANS_VOICE_CHANGED', function() changed = changed + 1 end)"""
    )
    run(wow, "zone:1429")
    assert wow.eval("seen[1]") == "voice.play"
    wow.execute("Spoken:Finish()")  # the clip played out
    assert wow.eval(f"{V}.Voice.IsHeard('z:1429')") is True
    assert wow.eval(f"{V}.db.char.heard['z:1429']") is True
    assert wow.eval("changed") >= 2
    # a stopped line is not heard
    run(wow, "object:1734")
    run(wow, "object:1734")
    assert wow.eval(f"{V}.Voice.IsHeard('r:41')") is False
    wow.execute(f"{V}.Voice.MarkHeard('r:41')")
    assert wow.eval(f"{V}.Voice.IsHeard('r:41')") is True
    wow.execute(f"{V}.Voice.MarkHeard('r:41', false)")
    assert wow.eval(f"{V}.Voice.IsHeard('r:41')") is False
    assert errors(wow) == []


def test_too_old_spoken_is_refused(wow: WowRuntime):
    wow.load_addon(CORE)
    wow.load_addon(DATA)
    for name in SPOKEN:
        wow.load_addon(name)
    wow.execute("Spoken.API_VERSION = 0")
    wow.load_addon(VOICE)
    wow.login()
    wow.run_frames(10)
    assert "voice.play" not in actions(wow, "quest:176")
    assert "too old" in wow.eval(f"{V}.options[1].text()")


def card_buttons(wow: WowRuntime) -> list[str]:
    return band_buttons(wow, "Bastians:GetModule('Browser').dossier")


def test_the_browser_card_and_the_quest_rows_play_and_stop(wow: WowRuntime):
    """playing the quest with Spoken must be prominent: the card's Play button
    (ADR 0013 B), Stop while the line plays; every quest row of an NPC page carries a Play button."""
    boot(wow, CORE, DATA, *SPOKEN, QUESTS, BROWSER, VOICE)
    browser = "Bastians:GetModule('Browser')"
    wow.execute(f"{browser}.Browser.Open('quest:176')")
    # a quest's page is the quest sheet (ADR 0056): Play is the first of its buttons
    assert card_buttons(wow)[0] == "Play"
    click_sheet_button(wow, f"{browser}.dossier", "Play")
    assert len(queue(wow)) == 1
    wow.run_frames(5)
    wow.advance(0.2)
    wow.run_frames(5)
    assert card_buttons(wow)[0] == "Stop"  # playing: stop
    click_sheet_button(wow, f"{browser}.dossier", "Stop")
    wow.run_frames(5)
    wow.advance(0.2)
    wow.run_frames(5)
    assert card_buttons(wow)[0] == "Play"
    # a zone page has Play too; a quest page without a line has none; an NPC without a story none
    wow.execute(f"{browser}.Browser.Open('zone:1429')")
    assert "Play" in card_buttons(wow)
    wow.execute(f"{browser}.Browser.Open('quest:999')")
    assert "Play" not in card_buttons(wow)
    wow.execute(f"{browser}.Browser.Open('npc:240')")
    assert "Play" not in card_buttons(wow)
    rows = wow.eval("Bastians:GetDetailSections('npc:240')[3].rows")
    quest_rows = [r for cat in rows.values() for r in cat.children.values()]
    assert quest_rows and all(r.button and r.button.label == ">" for r in quest_rows)
    # disabling Voice removes the action and Spoken's callbacks
    wow.execute(f"{V}:Disable()")
    assert "voice.play" not in actions(wow, "quest:176")
    assert wow.eval("#Spoken.callbacks") == 0
    assert wow.eval("BastiansVoiceOrbit:IsShown()") is False
    wow.execute(f"{V}:Enable()")
    assert "voice.play" in actions(wow, "quest:176")
    assert errors(wow) == []


def test_the_orbit_shows_what_is_around_the_player(wow: WowRuntime):
    boot(wow)
    assert wow.eval("BastiansVoiceOrbit:IsShown()") is True
    items = wow.eval(f"{ORBIT}.Items")
    places = [(p.kind, p.title, p.here or False) for p in items.places.values()]
    # the zone and the area the player stands in (Goldshire has no record of ours: Spoken's key
    # of the client's name finds its lore)
    assert places == [("zone", "Elwynn Forest", False), ("area", "Goldshire", True)]
    outer = list(items.outer.values())
    assert [(o.kind, o.title) for o in outer] == [
        ("npc", "Marshal Dughan"),  # a quest ready to hand in (62) comes first
        ("object", "Wanted Poster"),  # the quest in the log (176)
        ("read", "Wanted Poster"),  # the readable Spoken lists for Elwynn
    ]
    dughan = outer[0]
    assert [(q.questID, q.status) for q in dughan.quests.values()] == [
        (62, "ready"),
        (76, "available"),
    ]
    assert dughan.bearing == 0 and dughan.distance == 0  # he stands where the player stands
    assert dughan.creature == 240
    # compact at rest: the moons fold into the giver's badge
    assert [b.kind for b in bubbles(wow)] == ["zone", "area", "npc", "object", "read"]
    assert wow.eval(f"{ORBIT}.IsWide()") is False
    scale = wow.eval("BastiansVoiceOrbit:GetScale()")
    assert round(scale, 3) == round(1080 * 0.36 / 300 * 0.55, 3)
    # the pointer over it: wide, the moons out, the hub's buttons shown
    wow.execute(f"{ORBIT}.Hover(true)")
    wow.run_frames(20)  # the grow takes 0.22 s
    assert wow.eval(f"{ORBIT}.IsWide()") is True
    assert round(wow.eval("BastiansVoiceOrbit:GetScale()"), 3) == round(1080 * 0.36 / 300, 3)
    kinds = [b.kind for b in bubbles(wow)]
    assert kinds.count("quest") == 3 and kinds[:2] == ["zone", "area"]
    assert wow.eval(f"{ORBIT}.hub.stop:IsShown()") is True
    # a click on the giver plays its first unheard quest line (62, ready first)
    giver = next(i for i, b in enumerate(bubbles(wow)) if b.kind == "npc") + 1
    wow.execute(f"{ORBIT}.Visible()[{giver}]:Click()")
    assert [c.questID for c in queue(wow)] == [62]
    wow.execute("Spoken:StopAll()")
    # a click on the zone plays its lore; the hub shows the title and the progress ring
    wow.execute(f"{ORBIT}.Visible()[1]:Click()")
    assert [c.key for c in queue(wow)] == ["z:1429"]
    wow.run_frames(2)
    assert wow.eval(f"{ORBIT}.hub.name:GetText()") == "Playing: Elwynn Forest"  # what you clicked
    assert wow.eval(f"{ORBIT}.hub.play.kind") == "pause"  # a glyph, not a letter
    assert wow.eval(f"{ORBIT}.Visible()[1].mark:IsShown()") is True  # the voice-line mark
    wow.execute(f"{ORBIT}.hub.stop:Click()")
    assert queue(wow) == []
    wow.run_frames(2)
    assert wow.eval(f"{ORBIT}.hub.play.kind") == "play"
    # a bubble keeps its button over a render: the giver's face is not torn down (no flicker)
    wow.execute(f"FIRST = {ORBIT}.Visible()[{giver}].face; {ORBIT}.Render()")
    assert wow.eval(f"{ORBIT}.Visible()[{giver}].face == FIRST") is True
    assert wow.eval(f"{ORBIT}.Visible()[{giver}].face.creature") == 240
    # the pointer leaves: compact again after 0.6 s
    wow.execute(f"{ORBIT}.Hover(false)")
    wow.run_frames(10)
    assert wow.eval(f"{ORBIT}.IsWide()") is True  # not yet
    wow.run_frames(60)
    assert wow.eval(f"{ORBIT}.IsWide()") is False
    assert errors(wow) == []


def test_a_click_says_what_it_did_without_spoken_or_a_voice(wow: WowRuntime):
    wow.execute("Mock.ttsVoices = {}")  # a client without text to speech
    boot(wow, CORE, DATA, QUESTS, VOICE)
    wow.execute(f"{ORBIT}.Hover(true)")
    wow.run_frames(20)
    assert wow.eval(f"{ORBIT}.hub.name:GetText()").endswith(NO_VOICE + "|r")
    wow.execute(f"{ORBIT}.Visible()[1]:Click()")  # the zone, no line
    assert wow.eval(f"{ORBIT}.hub.name:GetText()") == "Spoken is not installed: nothing to play"
    assert wow.eval(f"{ORBIT}.Visible()[1].mark:IsShown()") is False
    assert "voice.play" not in actions(wow, "quest:176")
    wow.run_frames(300)  # the note goes after 4 s
    assert "nothing to play" not in wow.eval(f"{ORBIT}.hub.name:GetText()")
    assert errors(wow) == []


def test_without_spoken_the_games_voice_reads_the_quest_texts(wow: WowRuntime):
    """("we dont have spoken in retail ... fall back to blizzard"): the
    client's text to speech reads a quest's text where Spoken has no line."""
    wow.execute(
        "Mock.questLog[2].details = 'The Fargodeep Mine is overrun with kobolds.'; "
        "Mock.questLog[2].objectivesText = 'Explore the Fargodeep Mine.'"
    )
    boot(wow, CORE, DATA, QUESTS, VOICE)
    assert wow.eval(f"{V}.options[1].text()") == (
        "Spoken is not installed: the game's voice reads the quest texts"
    )
    # the log quest's text from the client; a quest without any text has no line
    assert "voice.play" in actions(wow, "quest:176")
    assert "voice.play" not in actions(wow, "quest:1000")
    line = wow.eval(f"{V}.Voice.Line('quest:176')")
    assert line.tts is True and line.key == "t:q:176:accept"
    assert "Fargodeep" in line.text
    run(wow, "quest:176")
    tts = list(wow.eval("Mock.tts").values())
    assert len(tts) == 1 and "Fargodeep" in tts[0].text
    # Zira over David the first; the Accessibility rate and volume
    assert (tts[0].voice, tts[0].rate, tts[0].volume) == (3, 1, 80)
    now = wow.eval(f"{V}.Voice.Now()")
    title = wow.eval("Bastians:Entity('quest:176'):Name()")  # the Data record's name
    assert now.tts is True and now.title == title and now.key == "t:q:176:accept"
    assert wow.eval("Bastians:GetAction('voice.play').active('quest:176')") is True
    # the orbit: the moon carries the dim mark, the hub says what plays
    wow.execute(f"{ORBIT}.Hover(true)")
    wow.run_frames(20)
    moon = next(b for b in bubbles(wow) if b.kind == "quest" and b.questID == 176)
    assert moon.line.tts is True
    assert wow.eval(f"{ORBIT}.hub.name:GetText()") == f"Playing: {title}"
    # the second click stops it; the voice finishing marks it heard
    run(wow, "quest:176")
    assert wow.eval("Mock.ttsStopped") >= 1 and wow.eval(f"{V}.Voice.Now()") is None
    run(wow, "quest:176")
    wow.fire("VOICE_CHAT_TTS_PLAYBACK_FINISHED", 2)
    assert wow.eval(f"{V}.Voice.IsHeard('t:q:176:accept')") is True
    assert wow.eval(f"{V}.Voice.Now()") is None
    # the setting lists the client's voices; a chosen one is taken, one the client lost falls back
    values = wow.eval(f"{V}.options[3].values()")
    assert dict(values) == {
        "auto": "A woman's voice (auto)",
        "2": "Microsoft David",
        "3": "Microsoft Zira",
    }
    wow.execute(f"{V}.db.profile.voice = '2'")
    run(wow, "quest:176")
    assert list(wow.eval("Mock.tts").values())[-1].voice == 2
    wow.execute(f"{V}.Voice.StopAll(); {V}.db.profile.voice = '99'")  # a click toggles: stop first
    run(wow, "quest:176")
    assert list(wow.eval("Mock.tts").values())[-1].voice == 3
    # a client with men's voices only: the first
    wow.execute(
        f"{V}.Voice.StopAll(); {V}.db.profile.voice = 'auto'; "
        "Mock.ttsVoices = { { voiceID = 2, name = 'Microsoft David' } }"
    )
    run(wow, "quest:176")
    assert list(wow.eval("Mock.tts").values())[-1].voice == 2
    # the switch off: no fallback lines
    wow.execute(
        f"{V}.db.profile.tts = false; Bastians:Fire('BASTIANS_SETTING_CHANGED', 'Voice', 'tts', false)"
    )
    assert "voice.play" not in actions(wow, "quest:176")
    assert errors(wow) == []


def test_with_spoken_the_games_voice_only_fills_the_gaps(wow: WowRuntime):
    boot(wow)
    line = wow.eval(f"{V}.Voice.Line('quest:176')")
    assert line.tts is None  # Spoken has the line
    assert "voice.play" not in actions(wow, "quest:999")  # no text known for it either
    assert errors(wow) == []


def test_the_orbit_scales_moves_and_keeps_its_corner(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{V}.db.profile.scale = 50; {ORBIT}.ApplyScale()")
    assert round(wow.eval("BastiansVoiceOrbit:GetScale()"), 3) == round(
        1080 * 0.36 / 300 * 0.55 * 0.5, 3
    )
    # the preset: top right, the centre in UI units; growing wide keeps that centre
    center = wow.eval(f"{ORBIT}.Center()")
    assert (round(center.x), round(center.y)) == (1920 - 238, 1080 - 281)
    point = wow.eval("BastiansVoiceOrbit.points[1]")
    assert point.point == "CENTER" and point.relPoint == "BOTTOMLEFT"
    assert round(point.x * wow.eval("BastiansVoiceOrbit:GetScale()")) == round(center.x)
    wow.execute(f"{ORBIT}.SetWide(true)")
    wow.run_frames(20)
    point = wow.eval("BastiansVoiceOrbit.points[1]")
    assert round(point.x * wow.eval("BastiansVoiceOrbit:GetScale()")) == round(center.x)
    assert round(point.y * wow.eval("BastiansVoiceOrbit:GetScale()")) == round(center.y)
    wow.execute(f"{ORBIT}.SetWide(false)")
    wow.run_frames(20)
    # dragged to the lower left: the nearest corner and the offset are kept; no lock sets itself
    wow.execute(
        """BastiansVoiceOrbit:ClearAllPoints()
        BastiansVoiceOrbit:SetPoint("CENTER", UIParent, "BOTTOMLEFT", 300, 200)"""
    )
    wow.execute(f"{ORBIT}.SavePlace()")
    orbit = wow.eval(f"{V}.db.profile.orbit")
    assert orbit.corner == "BOTTOMLEFT"
    assert wow.eval(f"{V}.db.profile.lock") is False
    # a bigger screen: the same corner, the same offset
    wow.execute("UIParent:SetSize(5120, 2880)")
    wow.fire("UI_SCALE_CHANGED")
    center = wow.eval(f"{ORBIT}.Center()")
    assert (round(center.x), round(center.y)) == (round(orbit.dx), round(orbit.dy))
    assert round(wow.eval(f"{M}.Size(2880, 50)") / 300 * 0.55, 3) == round(
        wow.eval("BastiansVoiceOrbit:GetScale()"), 3
    )
    # reset: back to the preset anchor and 100 %
    wow.slash("/bv reset")
    assert wow.eval(f"{V}.db.profile.orbit.corner") is None
    assert wow.eval(f"{V}.db.profile.scale") == 100
    center = wow.eval(f"{ORBIT}.Center()")
    assert round(center.x) == 5120 - round(0.22 * 2880)
    # /bv and /orbiter toggle it
    shown = wow.eval("BastiansVoiceOrbit:IsShown()")
    wow.slash("/orbiter")
    assert wow.eval("BastiansVoiceOrbit:IsShown()") is (not shown)
    wow.slash("/bv")
    assert wow.eval("BastiansVoiceOrbit:IsShown()") is shown
    # /bv toggles it
    wow.slash("/bv")
    assert wow.eval("BastiansVoiceOrbit:IsShown()") is False
    wow.slash("/bv")
    assert wow.eval("BastiansVoiceOrbit:IsShown()") is True
    assert errors(wow) == []


def test_in_a_dungeon_the_orbit_shows_its_story_and_its_bosses(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.instanceType = 'party'; Mock.instanceMap = 36; Mock.playerMap = nil")
    wow.fire("ZONE_CHANGED_NEW_AREA")
    wow.advance(0.3)
    wow.run_frames(5)
    items = wow.eval(f"{ORBIT}.Items")
    places = [(p.kind, p.title) for p in items.places.values()]
    assert places == [("dungeon", "The Deadmines")]
    assert items.places[1].line.key == "s:1436:deadmines"  # the story Spoken keeps under Westfall
    bosses = [(o.kind, o.title) for o in items.outer.values() if o.kind == "boss"]
    assert bosses == [("boss", "Edwin VanCleef")]  # Sneed has no story; our data names the creature
    assert errors(wow) == []


def test_the_conversation_replaces_the_quest_windows(wow: WowRuntime):
    boot(wow)
    assert wow.eval("Bastians:GetModule('Voice.Talk'):IsEnabled()") is False  # off by default
    wow.execute("Bastians:GetModule('Voice.Talk'):Enable()")
    wow.execute(
        """Mock.unitNames.npc = "Marshal Dughan"
        Mock.guids = { npc = "Creature-0-1-0-1-240-0000ABCD" }
        Mock.gossip = {
          active = { { questID = 62, title = "The Fargodeep Mine", isComplete = true } },
          available = { { questID = 76, title = "The Jasperlode Mine" } },
          options = { { gossipOptionID = 11, name = "Train me." } },
        }
        GossipFrame:Show()"""
    )
    wow.fire("GOSSIP_SHOW")
    state = wow.eval(f"{TALK}.state")
    assert (
        state.step == "gossip" and state.npc.name == "Marshal Dughan" and state.npc.creature == 240
    )
    assert wow.eval("GossipFrame:GetAlpha()") == 0  # the game's window stays shut
    assert wow.eval(f"{ORBIT}.IsWide()") is True
    items = bubbles(wow)
    assert sorted((b.kind, b.title) for b in items) == [
        ("quest", "The Fargodeep Mine"),
        ("quest", "The Jasperlode Mine"),
        ("say", "Farewell"),
        ("say", "Train me."),
    ]
    assert items[0].status == "ready" and items[1].status == "available"
    click(wow, "The Jasperlode Mine")  # the available quest: the giver tells about it
    assert wow.eval("Mock.npcCalls[#Mock.npcCalls]") == "gossip available 76"
    # the detail: Accept and Not now beside the quest
    wow.execute(
        """Mock.questFrame.title = "The Jasperlode Mine"
        Mock.questFrame.text = "Kobolds have been seen around the mine."
        Mock.questFrame.objectives = "Explore the Jasperlode Mine."
        Mock.questFrame.questID = 76
        QuestFrame:Show()"""
    )
    wow.fire("QUEST_DETAIL")
    state = wow.eval(f"{TALK}.state")
    assert state.step == "detail" and state.current.questID == 76
    assert state.current.text.startswith("Kobolds") and state.current.objectives.startswith(
        "Explore"
    )
    assert wow.eval("QuestFrame:GetAlpha()") == 0
    items = bubbles(wow)
    assert sorted((b.kind, b.title) for b in items) == [
        ("act", "Accept"),
        ("quest", "The Jasperlode Mine"),
        ("say", "Not now"),
    ]
    click(wow, "Accept")
    assert wow.eval("Mock.npcCalls[#Mock.npcCalls]") == "accept"
    wow.fire("QUEST_FINISHED")
    assert wow.eval(f"{TALK}.state") is None
    assert wow.eval("QuestFrame:GetAlpha()") == 1 and wow.eval("GossipFrame:GetAlpha()") == 1
    # the hand-in with a reward choice: Hand in waits for the choice
    wow.execute(
        """Mock.questFrame.title = "Wanted: Hogger"
        Mock.questFrame.questID = 176
        Mock.questFrame.choices = { { 1185, 1 }, { 2318, 2 } }"""
    )
    wow.fire("QUEST_COMPLETE")
    items = bubbles(wow)
    assert sorted((b.kind, b.title) for b in items) == [
        ("act", "Hand in"),
        ("object", "Blood Saber"),
        ("object", "Light Leather"),
        ("quest", "Wanted: Hogger"),
        ("say", "Not now"),
    ]
    assert next(b for b in items if b.kind == "act").disabled is True
    wow.execute(f"{TALK}.HandIn()")
    assert any("Choose a reward first" in line for line in wow.chat)
    assert "reward" not in wow.eval("Mock.npcCalls[#Mock.npcCalls]")
    # a reward shows the game's whole item tooltip, and how to choose it (owner, Forever
    # 08.11.2026: "I cannot see the exact reward stats when hovering over it")
    index = next(i for i, b in enumerate(bubbles(wow)) if b.title == "Light Leather") + 1
    wow.execute(
        f"GameTooltip:ClearLines() {ORBIT}.Visible()[{index}]:GetScript('OnEnter')({ORBIT}.Visible()[{index}])"
    )
    assert wow.eval("GameTooltip.itemID") == 2318
    lines = [str(ln.left) for ln in wow.eval("GameTooltip.lines").values()]
    assert lines == ["Click chooses this reward"]
    click(wow, "Light Leather")  # the second choice
    assert wow.eval(f"{TALK}.state.current.choice") == 2
    click(wow, "Hand in")
    assert wow.eval("Mock.npcCalls[#Mock.npcCalls]") == "reward 2"
    wow.fire("QUEST_FINISHED")
    # Farewell closes the gossip; the hub's button gives the game's window back for this visit
    wow.fire("GOSSIP_SHOW")
    click(wow, "Farewell")
    assert list(wow.eval("Mock.npcCalls").values())[-2:] == ["close gossip", "close quest"]
    wow.execute(f"{TALK}.ShowGameWindow()")
    assert wow.eval("GossipFrame:GetAlpha()") == 1 and wow.eval(f"{TALK}.state.gameWindow") is True
    wow.fire("GOSSIP_CLOSED")
    # Shift held while talking: the game's windows for that visit, no conversation on the orbit
    wow.execute("Mock.shift = true")
    wow.fire("GOSSIP_SHOW")
    assert wow.eval("GossipFrame:GetAlpha()") == 1
    assert wow.eval(f"{TALK}.state.hidden") is False
    wow.fire("GOSSIP_CLOSED")
    wow.execute("Mock.shift = false")
    # off: nothing happens
    wow.execute("Bastians:GetModule('Voice.Talk'):Disable()")
    wow.fire("GOSSIP_SHOW")
    assert wow.eval(f"{TALK}.state") is None and wow.eval("GossipFrame:GetAlpha()") == 1
    assert errors(wow) == []


def test_the_item_names_a_readable_by_its_english_name_only(wow: WowRuntime):
    """Readables are keyed by the English title (voice.md §2): the object's name must match."""
    boot(wow)
    assert list(wow.eval(f"{V}.SpokenData.BookPages('Wanted Poster')").values()) == [501, 502]
    assert list(wow.eval(f"{V}.SpokenData.BookPages('A Careworn Note')").values()) == [601]
    assert wow.eval(f"{V}.SpokenData.PageClip(601)") is None  # no recording
    assert wow.eval(f"{V}.SpokenData.BookPages('Steckbrief')") is None
    books = [b.title for b in wow.eval(f"{V}.SpokenData.ReadablesIn(1429)").values()]
    assert books == ["A Careworn Note", "Wanted Poster"]
    assert math.isclose(wow.eval(f"{V}.SpokenData.ZoneClip(1429).length"), 161)
    assert wow.eval(f"{V}.SpokenData.ZoneClip(1453)") is None
    assert wow.eval(f"{V}.SpokenData.AreaClip(1429, 'goldshire').path").endswith(
        "1429/goldshire.mp3"
    )
    assert wow.eval(f"{V}.SpokenData.Boss(448).key") == "hogger"
    assert wow.eval(f"{V}.SpokenData.Boss(643)") is None  # Sneed: no story


def test_the_bubbles_glide_to_their_new_slots_as_the_player_moves(wow: WowRuntime):
    """ "the updates of the npc nodes feel clumsy ... sliding around
    instead of jumping once per sec": the cloud follows twice a second from 3 yards on, and a
    bubble that changes its slot glides there over half a second."""
    boot(wow)
    wow.execute(f"{ORBIT}.Hover(true)")
    wow.run_frames(50)  # the grow (0.22 s) and the glide of the unfolded moons (0.45 s) are over
    before = {b.key: (b.cx, b.cy) for b in wow.eval(f"{ORBIT}.Visible()").values()}
    assert wow.eval(f"{ORBIT}.Gliding()") == 0
    # a step of 32 yards west: the givers' bearings change, their bubbles move
    wow.execute("Mock.playerMapPos = { x = 0.5, y = 0.65 }")
    wow.execute(f"{ORBIT}.Tick()")
    moving = wow.eval(f"{ORBIT}.Gliding()")
    assert moving >= 1
    now = {b.key: (b.cx, b.cy, b.tx, b.ty) for b in wow.eval(f"{ORBIT}.Visible()").values()}
    glider = next(k for k, v in now.items() if v[2] is not None and abs(v[0] - v[2]) > 10)
    assert now[glider][:2] == before[glider]  # still where it was: the glide has not advanced yet
    wow.run_frames(12)  # 0.2 s: on the way, neither here nor there
    mid = wow.eval(f"{ORBIT}.Visible()")
    g = next(b for b in mid.values() if b.key == glider)
    assert (g.cx, g.cy) != before[glider] and (g.cx, g.cy) != (g.tx, g.ty)
    wow.run_frames(30)  # 0.5 s more: arrived
    assert wow.eval(f"{ORBIT}.Gliding()") == 0
    for b in wow.eval(f"{ORBIT}.Visible()").values():
        if b.tx is not None:
            assert abs(b.cx - b.tx) < 1e-6 and abs(b.cy - b.ty) < 1e-6
    # a small step (under 3 yards) or a turn under 6 degrees does nothing
    wow.execute("Mock.playerMapPos = { x = 0.502, y = 0.65 }")
    wow.execute(f"{ORBIT}.Tick()")
    assert wow.eval(f"{ORBIT}.Gliding()") == 0
    assert errors(wow) == []


def test_the_playing_bubble_is_unmistakable(wow: WowRuntime):
    """ "it needs to be very clear what is active - coloured": the bubble
    that plays is filled with the accent and ringed bright; it goes back when the line stops."""
    boot(wow)
    S = "Bastians.UI.Style"
    wow.execute(f"{ORBIT}.Visible()[1]:Click()")  # the zone's lore
    wow.run_frames(2)
    assert wow.eval(f"{ORBIT}.Visible()[1].active") is True
    assert wow.eval(f"{S}.painted[{ORBIT}.Visible()[1].fill][1] == {S}.C.accent") is True
    assert wow.eval(f"{S}.painted[{ORBIT}.Visible()[1].fill][2]") == 0.9
    assert wow.eval(f"{S}.painted[{ORBIT}.Visible()[1].ring][1] == {S}.C.bright") is True
    assert wow.eval(f"{S}.painted[{ORBIT}.Visible()[1].mark][1] == {S}.C.bg") is True
    assert wow.eval(f"{ORBIT}.Visible()[2].active") is False
    wow.execute(f"{ORBIT}.hub.stop:Click()")
    wow.run_frames(2)
    assert wow.eval(f"{ORBIT}.Visible()[1].active") is False
    assert wow.eval(f"{S}.painted[{ORBIT}.Visible()[1].fill][1] == {S}.C.accent") is False
    assert errors(wow) == []


def test_the_games_voices_arrive_after_the_load(wow: WowRuntime):
    """text to speech switched on in the game's options and still only
    "Spoken is not installed": the client lists its voices later; the hub, the fallback lines and
    the About note follow the list, and `/bv voices` says what the game lists."""
    wow.execute(
        "Mock.ttsVoices = {}; Mock.questLog[2].details = 'The mine is overrun with kobolds.'"
    )
    boot(wow, CORE, DATA, QUESTS, VOICE)
    wow.execute(f"{ORBIT}.Hover(true)")
    wow.run_frames(20)
    assert wow.eval(f"{ORBIT}.hub.name:GetText()").endswith(NO_VOICE + "|r")
    assert "voice.play" not in actions(wow, "quest:176")
    wow.execute("Mock.ttsVoices = { { voiceID = 3, name = 'Microsoft Zira' } }")
    wow.fire("VOICE_CHAT_TTS_VOICES_UPDATE")
    wow.run_frames(2)
    assert wow.eval(f"{ORBIT}.hub.name:GetText()").endswith(
        "Spoken is not installed: the game's voice reads the quest texts|r"
    )
    assert "voice.play" in actions(wow, "quest:176")
    assert wow.eval(f"{V}.options[1].text()").startswith(
        "Spoken is not installed: the game's voice"
    )
    wow.execute("Bastians:GetModule('Voice').Voice.Slash('voices')")
    said = list(wow.eval("Mock.chat").values())
    assert any("lists 1 voice(s) for reading" in s for s in said)
    assert any("Microsoft Zira (3)" in s for s in said)
    # the game's voice switched off in the settings: the note says so
    wow.execute(f"{V}.db.profile.tts = false")
    assert wow.eval(f"{V}.options[1].text()").endswith("switched off in the Orbiter's settings")
    assert errors(wow) == []


def test_the_clear_screen_key_hides_the_orbiter_and_the_hub_drags_it(wow: WowRuntime):
    """ "the orbiter does not react to hidden by key" and "when left
    clicking into the middle, outside the sound play buttons, its draggable"."""
    boot(wow)
    assert wow.eval("BastiansVoiceOrbit:IsShown()") is True
    wow.execute("Bastians:Fire('BASTIANS_SUITE_HIDDEN', true)")
    assert wow.eval("BastiansVoiceOrbit:IsShown()") is False
    wow.execute("Bastians:Fire('BASTIANS_SUITE_HIDDEN', false)")
    assert wow.eval("BastiansVoiceOrbit:IsShown()") is True
    # hidden by hand before the key: the key's return leaves it hidden
    wow.execute(f"{ORBIT}.Hide()")
    wow.execute("Bastians:Fire('BASTIANS_SUITE_HIDDEN', true)")
    wow.execute("Bastians:Fire('BASTIANS_SUITE_HIDDEN', false)")
    assert wow.eval("BastiansVoiceOrbit:IsShown()") is False
    wow.execute(f"{ORBIT}.Show()")
    # the hub drags the whole panel; locked, it does not
    hub = f"{ORBIT}.hub"
    wow.execute(f"{hub}:GetScript('OnDragStart')({hub})")
    assert wow.eval(f"{ORBIT}.IsDragging()") is True
    wow.execute(f"{hub}:GetScript('OnDragStop')({hub})")
    assert wow.eval(f"{ORBIT}.IsDragging()") is False
    wow.execute(f"{V}.db.profile.lock = true")
    wow.execute(f"{hub}:GetScript('OnDragStart')({hub})")
    assert wow.eval(f"{ORBIT}.IsDragging()") is False
    # and says why
    assert wow.eval(f"{hub}.name:GetText()").startswith("Locked in place.")
    assert errors(wow) == []


def test_round_6_the_tick_the_model_and_the_answers_as_symbols(wow: WowRuntime):
    """screenshots: the Orbiter follows the page's tick for Voice,
    the creature's picture never takes the mouse from the controls, Accept and Not now are
    symbols with their words in the tooltip."""
    boot(wow)
    # unticked on the page "Hidden by the key": the key leaves the Orbiter alone
    wow.execute("Bastians:GetModule('Core').db.profile.screen_Voice = false")
    wow.execute("Bastians:Fire('BASTIANS_SUITE_HIDDEN', true)")
    assert wow.eval("BastiansVoiceOrbit:IsShown()") is True
    wow.execute("Bastians:Fire('BASTIANS_SUITE_HIDDEN', false)")
    assert wow.eval("BastiansVoiceOrbit:IsShown()") is True
    wow.execute("Bastians:GetModule('Core').db.profile.screen_Voice = nil")
    assert wow.eval("Bastians.UI.Screen.Hides('Voice')") is True
    # the conversation: the giver's picture under the controls, the answers as glyphs
    wow.execute("Bastians:GetModule('Voice.Talk'):Enable()")
    wow.execute(
        """Mock.unitNames.npc = "Marshal Dughan"
        Mock.guids = { npc = "Creature-0-1-0-1-240-0000ABCD" }
        Mock.gossip = { active = {}, available = { { questID = 76, title = "The Jasperlode Mine" } }, options = {} }
        GossipFrame:Show()"""
    )
    wow.fire("GOSSIP_SHOW")
    hub = f"{ORBIT}.hub"
    assert wow.eval(f"{hub}.face:IsShown()") is True
    assert wow.eval(f"{hub}.face:IsMouseEnabled()") is False
    assert wow.eval(f"{hub}.face.model:IsMouseEnabled()") is False
    assert wow.eval(f"{hub}.play:GetFrameLevel()") > wow.eval(f"{hub}.face.model:GetFrameLevel()")
    wow.execute(
        """Mock.questFrame.title = "The Jasperlode Mine"
        Mock.questFrame.text = "Kobolds have been seen around the mine."
        Mock.questFrame.objectives = "Explore the Jasperlode Mine."
        Mock.questFrame.questID = 76
        QuestFrame:Show()"""
    )
    wow.fire("QUEST_DETAIL")
    answers = {b.item.title: b for b in wow.eval(f"{ORBIT}.Visible()").values() if b.item.glyph}
    assert set(answers) == {"Accept", "Not now"}
    done = wow.eval("Bastians.UI.GLYPH_PATHS.done")
    never = wow.eval("Bastians.UI.GLYPH_PATHS.never")
    accept, notnow = answers["Accept"], answers["Not now"]
    assert (
        accept.glyph.GetTexture(accept.glyph) == done
        and accept.label.IsShown(accept.label) is False
    )
    assert notnow.glyph.GetTexture(notnow.glyph) == never
    assert errors(wow) == []


def test_the_quest_marks_tooltips_show_the_chain_and_the_rewards(wow: WowRuntime):
    """Owner, Forever launch night 05.11.2026: "you cannot see the reward from a quest using the
    orbiter ... gold, items and renown ... and also if part of a quest chain"."""
    boot(wow)
    wow.execute(
        """
        local Logic = Bastians:GetModule('Quests').Logic
        Mock.Keep(Logic.quest(62)).rewards = { money = 125, xp = 480, rep = { { 72, 150 } }, items = { { 2589, 5 } } }
        Mock.Keep(Logic.quest(76)).rewards = { money = 40 }
        Bastians:Fire("BASTIANS_QUESTS_CHANGED", {}, {})
        """
    )

    def tip_lines(index: int) -> list[str]:
        wow.execute(
            f"GameTooltip:ClearLines() {ORBIT}.Visible()[{index}]:GetScript('OnEnter')({ORBIT}.Visible()[{index}])"
        )
        return [
            str(ln.left or "") + (" | " + str(ln.right) if ln.right else "")
            for ln in wow.eval("GameTooltip.lines").values()
        ]

    # compact: the giver's badge folds its quests; its tooltip names each with status and rewards
    giver = next(i for i, b in enumerate(bubbles(wow)) if b.kind == "npc") + 1
    lines = tip_lines(giver)
    assert lines[0] == "Marshal Dughan"
    joined = "\n".join(lines)
    assert (
        "The Fargodeep Mine, Ready to hand in" in joined
    )  # the pack's name, as the orbit titles it
    assert "Money | " in joined and "Reputation: Faction 72 | +150" in joined
    assert "Linen Cloth" in joined
    assert "Experience" not in joined
    # wide: a quest mark shows the quest sheet beside the ring while the mouse is on it (ADR 0053)
    wow.execute(f"{ORBIT}.Hover(true)")
    wow.run_frames(20)
    moon = next(i for i, b in enumerate(bubbles(wow)) if b.kind == "quest" and b.questID == 62) + 1
    assert tip_lines(moon) == []  # the sheet, no tooltip
    assert wow.eval("BastiansQuestSheet:IsShown()") is True
    assert wow.eval("BastiansQuestSheet:IsMouseEnabled()") is False  # a look, nothing to click
    # the ring stands top right: the sheet opens to its left, where the room is (05.11.2026)
    point = wow.eval("BastiansQuestSheet.points[1]")
    assert (point.point, point.relPoint) == ("RIGHT", "LEFT")
    wow.execute(f"local b = {ORBIT}.Visible()[{moon}]; b:GetScript('OnLeave')(b)")
    assert wow.eval("BastiansQuestSheet:IsShown()") is False
    wow.execute(f"{ORBIT}.Hover(false)")
    assert errors(wow) == []


def test_the_lock_on_the_ring_toggles_dragging(wow: WowRuntime):
    """ "a small lock symbol in Orbiter to toggle the ability to move it freely
    around". The lock sits under the play button while the ring is wide, lit while locked; a click
    switches the same setting as the options' "Lock the position" and says what it did."""
    boot(wow)
    hub, lock = f"{ORBIT}.hub", f"{ORBIT}.hub.lock"
    wow.execute(f"{ORBIT}.SetWide(false)")
    assert wow.eval(f"{lock}:IsShown()") is False  # the compact ring keeps to the play button
    wow.execute(f"{ORBIT}.SetWide(true)")
    assert wow.eval(f"{lock}:IsShown()") is True
    assert wow.eval(f"select(5, {lock}:GetPoint(1))") < -15  # under the play button, on the hub
    assert wow.eval(f"{V}.db.profile.lock") is False and wow.eval(f"{lock}.locked") is False
    assert wow.eval(f"({lock}.tip())") == "Moves freely"
    wow.execute(f"{lock}:Click()")
    assert wow.eval(f"{V}.db.profile.lock") is True and wow.eval(f"{lock}.locked") is True
    assert wow.eval(f"{hub}.name:GetText()") == "Locked in place"
    assert wow.eval(f"({lock}.tip())") == "Locked in place"
    tint = [round(v, 3) for v in wow.eval(f"{{ {lock}.glyph:GetVertexColor() }}").values()][:3]
    assert tint == [round(v, 3) for v in wow.eval("Bastians.UI.Style.C.accent").values()][:3]
    wow.execute(f"{hub}:GetScript('OnDragStart')({hub})")
    assert wow.eval(f"{ORBIT}.IsDragging()") is False
    assert wow.eval(f"{hub}.name:GetText()").startswith("Locked in place. The lock")
    wow.execute(f"{lock}:Click()")  # unlocked again: it drags
    assert wow.eval(f"{V}.db.profile.lock") is False
    assert wow.eval(f"{hub}.name:GetText()") == "Moves freely"
    wow.execute(f"{hub}:GetScript('OnDragStart')({hub})")
    assert wow.eval(f"{ORBIT}.IsDragging()") is True
    wow.execute(f"{hub}:GetScript('OnDragStop')({hub})")
    assert errors(wow) == []
