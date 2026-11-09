"""The trainer view (alts.md "The trainer view", catalog review A5.7, 07.11.2026): what the class
trainers teach and the character does not know, now and later, with the cost and the nearest
trainer; the pure plan; the view registered."""

import re

from harness import WowRuntime

CORE, DATA, ALTS = "Bastians_Core", "Bastians_Data", "Bastians_Alts"
T = "Bastians:GetModule('Alts').Train"


def boot(wow: WowRuntime, level: int = 12) -> WowRuntime:
    wow.execute(f"Mock.level = {level}")  # the mock's character is a mage
    wow.start(CORE, DATA, ALTS)
    wow.run_frames(10)
    wow.execute("Bastians:GetService('data'):LoadPack('world')")
    return wow


def strip(text: str) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def test_the_view_says_what_to_learn_now_and_later(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.spells[116] = true")  # Frostbolt (Rank 1) known; Fireball (Rank 2) not
    rows, summary = wow.eval(f"{T}.Rows()")
    assert strip(summary) == "1 spells to learn now for 12s 00c; 0 at later levels"
    header = next(iter(rows.values()))
    assert strip(header.text) == "Learn now  1  12s 00c" and header.kind == "section"
    row = next(iter(header.children.values()))
    assert (row.spell, row.value, row.valueKind, row.ref) == (133, 1200, "money", "npc:198")
    assert strip(row.text).startswith("[6] Fireball (Rank 2)  at Zaldimar Wefhellt")
    # the level too low: Fireball waits for level 6
    wow.execute("Mock.level = 5")
    rows, summary = wow.eval(f"{T}.Rows()")
    assert summary == "Nothing to learn now; 1 at later levels"
    assert strip(next(iter(rows.values())).text) == "Later  1"
    # everything known
    wow.execute("Mock.level = 12; Mock.spells[133] = true")
    rows, summary = wow.eval(f"{T}.Rows()")
    assert len(rows) == 0 and summary == "You know every spell for your level."
    assert wow.errors == []


def test_another_class_has_no_trainer_in_the_fixture(wow: WowRuntime):
    wow.execute("Mock.classID = 7")  # a shaman: no Shaman Trainer in the fixture world
    boot(wow)
    rows, summary = wow.eval(f"{T}.Rows()")
    assert len(rows) == 0 and summary == "You know every spell for your level."
    assert wow.eval("Bastians:GetView('alts.train').title") == "Trainer"
    assert wow.errors == []


def test_the_plan_is_pure_and_unknown_stays_unknown(core: WowRuntime):
    core.start(CORE, ALTS)
    spells = (
        "{ { spell = 1, name = 'B', cost = 100, level = 4, known = false },"
        " { spell = 2, name = 'A', cost = 200, level = 4, known = false },"
        " { spell = 3, name = 'C', cost = 300, level = 20, known = false },"
        " { spell = 4, name = 'D', cost = 400, level = 2, known = true },"
        " { spell = 5, name = 'E', cost = 500, level = 2 } }"
    )
    plan = core.eval(f"{T}.Plan({spells}, 12)")
    assert [s.name for s in plan.now.values()] == ["A", "B"]  # by level, then name
    assert [s.name for s in plan.later.values()] == ["C"]
    assert (plan.nowCost, plan.known, plan.unknown) == (300, 1, 1)
    plan = core.eval(f"{T}.Plan({spells}, nil)")
    assert [s.name for s in plan.now.values()] == ["A", "B", "C"]  # no level: nothing is "later"
    assert core.eval(f"{T}.Plan(nil, 12).nowCost") == 0
    assert core.errors == []


def test_the_goals_are_pure_and_show_on_the_characters_overview(wow: WowRuntime):
    boot(wow)
    g = f"{T}.Goals"
    plan = "{ now = { { cost = 500 } }, later = {}, nowCost = 500 }"
    riding = "{ { spell = 33388, cost = 900000, level = 40, known = false }, { spell = 33391, cost = 9000000, level = 60, known = false } }"
    goals = list(
        wow.eval(f"{g}({plan}, {riding}, {{ item = 2411, cost = 200000, level = 40 }})").values()
    )
    assert [(x.key, x.cost, x.level) for x in goals] == [
        ("training", 500, None),
        ("riding", 900000, 40),
        ("mount", 200000, 40),
    ]
    assert goals[2].ref == "item:2411"
    # nothing to learn now: the first later level's spells; the first rank known: the next one
    later = "{ now = {}, later = { { cost = 100, level = 10 }, { cost = 200, level = 10 }, { cost = 999, level = 12 } }, nowCost = 0 }"
    known = "{ { spell = 33388, cost = 900000, level = 40, known = true }, { spell = 33391, cost = 9000000, level = 60, known = false } }"
    goals = list(wow.eval(f"{g}({later}, {known}, nil)").values())
    assert [(x.key, x.cost, x.level) for x in goals] == [
        ("trainingAt", 300, 10),
        ("riding", 9000000, 60),
    ]
    assert len(wow.eval(f"{g}(nil, nil, nil)")) == 0
    # the character's Overview: the next training from the fixture's Mage Trainer, no riding there
    rows = wow.eval(
        "Bastians:GetDetailSections('character:' .. select(2, Bastians:GetModule('Alts').Alts.Me()))"
    )
    overview = next(s for s in rows.values() if s.id == "alts.overview")
    goal_rows = [(strip(r.text), r.value) for r in overview.rows.values() if r.goal]
    assert goal_rows == [("Next training", 1700)]  # Fireball 12s + Frostbolt 5s, neither known
    assert wow.errors == []
