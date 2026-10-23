"""Attunements view and the Spoken bridge (B5.6): steps by quest status, bags and reputation; the
voice action only with Spoken and Spoken Quests present, play and stop through the test doubles."""

import re

from harness import WowRuntime
from pages import band_buttons

CORE, DATA, QUESTS = "Bastians_Core", "Bastians_Data", "Bastians_Quests"
MOD = "Bastians:GetModule('Quests')"
WIN = f"{MOD}.Window"
SIZE = f"{WIN}.tree.scroll:SetSize(500, 400); {WIN}.tree:Refresh()"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, QUESTS)))
    wow.run_frames(10)
    wow.advance(0.3)
    return wow


def strip(text: str) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def flat(wow: WowRuntime) -> list[str]:
    return [strip(r.text) for r in wow.eval(f"{WIN}.tree.flat").values()]


def icons(wow: WowRuntime) -> list[str]:
    out = []
    for r in wow.eval(f"{WIN}.tree.flat").values():
        m = re.match(r"\|T([^:|]*)", r.text or "")
        out.append(m.group(1).rsplit("\\", 1)[-1] if m else "")
    return out


def errors(wow: WowRuntime) -> list[str]:
    return wow.errors + [
        line.text
        for line in wow.eval("Bastians:GetLog()").values()
        if line.level == "error" and "registered no data" not in line.text
    ]


def test_attunements_tab_shows_steps_by_quest_bag_and_reputation(wow: WowRuntime):
    boot(wow)
    wow.slash("/bq attune")
    wow.execute(SIZE)
    texts = flat(wow)
    assert texts == [
        "THE FARGODEEP ATTUNEMENT  0/3  fixture: the mine chain",
        "[7] The Fargodeep Mine  Chain 1/3",
        "[9] The Jasperlode Mine  Chain 2/3",
        "[10] Riverpaw Gnoll Bounty  Chain 3/3",
        "THE GNOLL CLAW  0/3  unverified",
        "Huge Gnoll Claw",
        "Argent Dawn: Honored  (now Neutral)",
        '[11] Wanted: "Hogger"  Group',
    ]
    assert strip(wow.eval(f"{WIN}.summary:GetText()")) == "0 of 2 attunements complete"
    assert wow.eval(f"{WIN}.tree.flat[6].ref") == "item:1931"
    assert icons(wow)[5:7] == ["waiting", "waiting"]  # glyph kinds
    # the claw drops into the bags, Argent Dawn reaches Honored, Hogger is handed in: all three done
    wow.execute("Mock.bags[1931] = 1; Mock.reputation[529].reaction = 6")
    wow.execute("Mock.completedQuests = { 783, 7, 18, 176 }; table.remove(Mock.questLog, 2)")
    wow.fire("QUEST_TURNED_IN", 176, 1, 1)
    wow.fire("QUEST_LOG_UPDATE")
    wow.fire("UPDATE_FACTION")
    wow.advance(0.2)
    texts = flat(wow)
    assert texts[4] == "THE GNOLL CLAW  3/3  unverified"
    assert len(texts) == 5  # the complete list folds
    assert strip(wow.eval(f"{WIN}.summary:GetText()")) == "1 of 2 attunements complete"
    assert wow.eval(f"{WIN}.tree.flat[1].ref") is None
    assert errors(wow) == []


def test_attunements_follow_the_faction(wow: WowRuntime):
    wow.execute("function UnitFactionGroup() return 'Horde', 'Horde' end")
    boot(wow)
    wow.slash("/bq attune")
    wow.execute(SIZE)
    assert flat(wow)[0].startswith("THE GNOLL CLAW")  # the Alliance-only list is not shown
    assert wow.eval(f"#{MOD}.Logic.attunements('Horde')") == 1
    assert wow.eval(f"#{MOD}.Logic.attunements('Alliance')") == 2
    assert errors(wow) == []


def test_without_spoken_there_is_no_voice_action(wow: WowRuntime):
    boot(wow)
    ids = [a.id for a in wow.eval("Bastians:GetActions('quest:176', { source = 'test' })").values()]
    assert "quests.voice" not in ids
    assert wow.eval("Bastians:GetModule('Quests.Spoken'):IsEnabled()") is True
    note = wow.eval("Bastians:GetModule('Quests.Spoken').options[1].text()")
    assert note == "Spoken is not installed: no voice button"
    assert errors(wow) == []


def test_with_spoken_the_voice_action_plays_and_stops(wow: WowRuntime):
    boot(wow, CORE, DATA, "Spoken", "Spoken_Quests", QUESTS)
    note = wow.eval("Bastians:GetModule('Quests.Spoken').options[1].text()")
    assert note == "Spoken: quest lines play from every quest row"
    ids = [a.id for a in wow.eval("Bastians:GetActions('quest:176', { source = 'test' })").values()]
    assert "quests.voice" in ids
    # with Spoken every quest row of an NPC page carries a Play button
    wow.advance(0.2)
    wow.run_frames(5)
    rows = wow.eval("Bastians:GetDetailSections('npc:240')[3].rows")
    quest_rows = [r for cat in rows.values() for r in cat.children.values()]
    assert quest_rows and all(r.button and r.button.label == ">" for r in quest_rows)
    wow.execute("Bastians:RunAction('quests.voice', 'quest:176', { source = 'test' })")
    queue = list(wow.eval("Spoken:GetQueue()").values())
    assert len(queue) == 1
    assert (queue[0].questID, queue[0].event, queue[0].title, queue[0].origin) == (
        176,
        1,
        "The Fargodeep Mine",  # the client's title for 176 in the mock log
        "Bastians_Quests",
    )
    assert queue[0].unitGUID == "creature-240" and queue[0].name == "Marshal Dughan"
    assert wow.eval(f"{MOD}.Window.IsShown()") is False  # AUDIO_CHANGED only schedules when open
    wow.execute("Bastians:RunAction('quests.voice', 'quest:176', { source = 'test' })")
    assert list(wow.eval("Spoken:GetQueue()").values()) == []  # a second click stops the line
    # a quest without a line: a chat note, nothing queued
    wow.execute("Bastians:RunAction('quests.voice', 'quest:999', { source = 'test' })")
    assert any("No voice line" in line for line in wow.chat)
    assert list(wow.eval("Spoken:GetQueue()").values()) == []
    # ... and no action for it (ADR 0013: the play symbol only where a line exists); the answer
    # comes from Spoken Quests' PrepareSound without playing and is cached per quest id
    ids = [a.id for a in wow.eval("Bastians:GetActions('quest:999', { source = 'test' })").values()]
    assert "quests.voice" not in ids
    assert wow.eval("Bastians:GetAction('quests.voice').has('quest:176')") is True
    assert wow.eval("Bastians:GetAction('quests.voice').has('quest:999')") is False
    before = wow.eval("VoiceOver.prepared")
    wow.execute(f"{MOD}.SpokenBridge.HasLine(176); {MOD}.SpokenBridge.HasLine(999)")
    wow.execute("Bastians:GetActions('quest:176', { source = 'test' })")
    assert wow.eval("VoiceOver.prepared") == before
    assert list(wow.eval("Spoken:GetQueue()").values()) == []
    # disabling the sub-module removes the action and the callback
    wow.execute("Bastians:GetModule('Quests.Spoken'):Disable()")
    ids = [a.id for a in wow.eval("Bastians:GetActions('quest:176', { source = 'test' })").values()]
    assert "quests.voice" not in ids
    assert wow.eval("#Spoken.callbacks") == 0
    assert errors(wow) == []


def test_spoken_too_old_is_refused(wow: WowRuntime):
    wow.load_addon("Bastians_Core")
    wow.load_addon("Bastians_Data")
    wow.load_addon("Spoken")
    wow.load_addon("Spoken_Quests")
    wow.execute("Spoken.API_VERSION = 0")
    wow.load_addon(QUESTS)
    wow.login()
    wow.run_frames(10)
    ids = [a.id for a in wow.eval("Bastians:GetActions('quest:176', { source = 'test' })").values()]
    assert "quests.voice" not in ids
    assert "too old" in wow.eval("Bastians:GetModule('Quests.Spoken').options[1].text()")


def card_buttons(wow: WowRuntime) -> list[str]:
    return band_buttons(wow, "Bastians:GetModule('Browser').dossier")


def test_the_browser_card_plays_and_stops_the_voice_line(wow: WowRuntime):
    """playing the quest with Spoken must be prominent: the card's Play button
    (ADR 0013 B), Stop while the line plays."""
    boot(wow, CORE, DATA, "Spoken", "Spoken_Quests", QUESTS, "Bastians_Browser")
    browser = "Bastians:GetModule('Browser')"
    wow.execute(f"{browser}.Browser.Open('quest:176')")
    assert "Play" in card_buttons(wow)
    play = card_buttons(wow).index("Play") + 1
    wow.execute(f"{browser}.dossier.buttons[{play}]:Click()")
    assert len(list(wow.eval("Spoken:GetQueue()").values())) == 1
    wow.execute("Spoken:Fire('AUDIO_CHANGED')")  # Spoken says the queue changed
    wow.run_frames(5)
    wow.advance(0.2)
    assert card_buttons(wow)[play - 1] == "Stop"  # playing: stop
    wow.execute(f"{browser}.dossier.buttons[{play}]:Click()")
    wow.execute("Spoken:Fire('AUDIO_CHANGED')")
    wow.run_frames(5)
    wow.advance(0.2)
    assert card_buttons(wow)[play - 1] == "Play"
    # an NPC page has no voice button; a quest page without a line has none either
    wow.execute(f"{browser}.Browser.Open('npc:240')")
    assert "Play" not in card_buttons(wow)
    wow.execute(f"{browser}.Browser.Open('quest:999')")
    assert "Play" not in card_buttons(wow)
    assert wow.errors == []
