"""Attunements view (B5.6): steps by quest status, bags and reputation. The Spoken bridge moved to
Bastian's Voice on 01.11.2026 (voice.md; `tests/lua/voice/test_voice.py`): Quests has no bridge of its
own any more."""

import re

from harness import WowRuntime

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
    # the progress chain: a head line, numbered steps with their
    # state, "you are here" on the step to act on
    assert texts == [
        "THE FARGODEEP ATTUNEMENT  0/3  fixture: the mine chain",
        "Step 1 of 3. Next: The Fargodeep Mine",
        "1. [7] The Fargodeep Mine  Chain 1/3  (Elwynn Forest)  in your log  <- you are here",
        "2. [9] The Jasperlode Mine  Chain 2/3  (Elwynn Forest)  after step 1",
        "3. [10] Riverpaw Gnoll Bounty  Chain 3/3  (Westfall)  after step 2",
        "THE GNOLL CLAW  0/3  unverified",
        "Step 1 of 3. Next: Huge Gnoll Claw",
        "1. Huge Gnoll Claw  not in your bags  <- you are here",
        "2. Argent Dawn: Honored  now Neutral",
        '3. [11] Wanted: "Hogger"  Group  (Elwynn Forest)  in your log',
    ]
    assert strip(wow.eval(f"{WIN}.summary:GetText()")) == "0 of 2 attunements complete"
    assert wow.eval(f"{WIN}.tree.flat[8].ref") == "item:1931"
    assert icons(wow)[7:9] == ["waiting", "waiting"]  # glyph kinds
    # the claw drops into the bags, Argent Dawn reaches Honored, Hogger is handed in: all three done
    wow.execute("Mock.bags[1931] = 1; Mock.reputation[529].reaction = 6")
    wow.execute("Mock.completedQuests = { 783, 7, 18, 176 }; table.remove(Mock.questLog, 2)")
    wow.fire("QUEST_TURNED_IN", 176, 1, 1)
    wow.fire("QUEST_LOG_UPDATE")
    wow.fire("UPDATE_FACTION")
    wow.advance(0.2)
    texts = flat(wow)
    assert texts[5] == "THE GNOLL CLAW  3/3  unverified"
    assert len(texts) == 6  # the complete list folds
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


def test_quests_alone_has_no_voice_action(wow: WowRuntime):
    boot(wow, CORE, DATA, "Spoken", "Spoken_Quests", QUESTS)
    ids = [a.id for a in wow.eval("Bastians:GetActions('quest:176', { source = 'test' })").values()]
    assert "voice.play" not in ids and "quests.voice" not in ids
    assert wow.eval("Bastians:GetModule('Quests.Spoken')") is None
    assert errors(wow) == []
