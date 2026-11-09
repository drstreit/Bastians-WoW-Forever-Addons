"""Dungeon runs and lockouts (alts.md "Runs and lockouts", catalog review A2.5, 07.11.2026): a run
per entry into an instance, not per reload; the lockouts from the raid info; the section on the
dungeon's page and the Overview row; the pure summary."""

import re

from harness import WowRuntime

CORE, DATA, ALTS = "Bastians_Core", "Bastians_Data", "Bastians_Alts"
A = "Bastians:GetModule('Alts').Alts"
R = "Bastians:GetModule('Alts').Runs"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA, ALTS)
    wow.run_frames(10)
    return wow


def strip(text: str) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def sections(wow: WowRuntime, ref: str) -> dict:
    return {s.id: s for s in wow.eval(f"Bastians:GetDetailSections('{ref}')").values()}


def test_a_run_counts_per_entry_and_the_lockouts_come_from_the_raid_info(wow: WowRuntime):
    boot(wow)
    assert "No run recorded yet." in [
        strip(r.text) for r in sections(wow, "dungeon:36")["alts.runs"].rows.values()
    ]
    wow.execute("Mock.instanceType = 'party'; Mock.instanceMap = 36")
    wow.fire("PLAYER_ENTERING_WORLD")
    assert wow.eval(f"{A}.Me().runs[36].n") == 1
    wow.fire("PLAYER_ENTERING_WORLD")  # a reload inside: no new run
    assert wow.eval(f"{A}.Me().runs[36].n") == 1
    wow.execute("Mock.instanceType = 'none'")
    wow.fire("PLAYER_ENTERING_WORLD")
    wow.execute("Mock.instanceType = 'party'")
    wow.fire("PLAYER_ENTERING_WORLD")
    assert wow.eval(f"{A}.Me().runs[36].n") == 2
    # the raid info: locked to the Deadmines for an hour; an unlocked entry is no lockout
    wow.execute(
        "Mock.savedInstances = { { name = 'The Deadmines', reset = 3600, locked = true, instanceID = 36 },"
        " { name = 'Shadowfang Keep', reset = 0, locked = false, instanceID = 33 } }"
    )
    wow.fire("UPDATE_INSTANCE_INFO")
    assert wow.eval(f"{A}.Me().lockouts[36] ~= nil") is True
    assert wow.eval(f"{A}.Me().lockouts[33]") is None
    rows = [strip(r.text) for r in sections(wow, "dungeon:36")["alts.runs"].rows.values()]
    assert rows == ["You: 2 runs, last 0 min ago, locked, resets in 1 h 00"]
    assert sections(wow, "dungeon:36")["alts.runs"].rows[1].ref.startswith("character:")
    # the Overview counts the runs
    me = wow.eval(f"select(2, {A}.Me())")
    overview = sections(wow, f"character:{me}")["alts.overview"].rows.values()
    assert ("Dungeon runs", 2) in [(strip(r.text), r.value) for r in overview]
    assert wow.errors == []


def test_the_summary_is_pure_and_puts_this_character_first(core: WowRuntime):
    core.start(CORE, ALTS)
    chars = (
        "{ b = { name = 'Bankalt', runs = { [36] = { n = 1, last = 100 } } },"
        " me = { name = 'Me', runs = { [36] = { n = 3, last = 200 } }, lockouts = { [36] = 1000 } },"
        " c = { name = 'Nobody', runs = { [33] = { n = 2 } } },"
        " d = { name = 'Locked', lockouts = { [36] = 500 } },"
        " e = { name = 'Expired', lockouts = { [36] = 50 } } }"
    )
    out = list(core.eval(f"{R}.Summary({chars}, 36, 'me', 300)").values())
    assert [(e.name, e.me, e.n, e.lockedFor) for e in out] == [
        ("Me", True, 3, 700),
        ("Bankalt", False, 1, None),
        ("Locked", False, 0, 200),
    ]
    assert len(core.eval(f"{R}.Summary(nil, 36, 'me', 300)")) == 0
    assert core.eval("Bastians.Compat.SavedInstances()") is not None
    assert core.errors == []
