"""A Lua test that edits a data record holds it with `Mock.Keep`.

Data keeps its decoded records in a weak table (data.md "Pack format"): a record nobody else
holds is collected and decoded again from the pack, without what a test wrote onto it. When a
collection runs depends on how much the run allocated, so such a test passes for months and
fails after a change that has nothing to do with it. Found 11.11.2026: the public snapshot of
2.3.0 failed `test_the_quest_marks_tooltips_show_the_chain_and_the_rewards[retail]` because the
release had added one line to each locale file; the same test passed in the private checkout.
"""

import re
from pathlib import Path

from harness import WowRuntime

HERE = Path(__file__).resolve().parent
# `Logic.quest(62).rewards = ...`, `data:Get('item', 1185).worldDrop = ...`; not a comparison
EDIT = re.compile(r"""(?:Logic\.quest\(\d+\)|Get\(["'][a-z]+["'], ?\d+\))\.[A-Za-z_]+ ?=(?!=)""")


def test_no_test_edits_a_data_record_without_keeping_it():
    found = []
    for path in sorted(HERE.rglob("test_*.py")):
        if path.name == Path(__file__).name:
            continue
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if EDIT.search(line):
                found.append(f"{path.relative_to(HERE).as_posix()}:{number}: {line.strip()[:80]}")
    assert not found, "wrap the record in Mock.Keep(...):\n" + "\n".join(found)


def test_a_kept_record_survives_a_collection(wow: WowRuntime):
    wow.start("Bastians_Core", "Bastians_Data", "Bastians_Quests")  # Quests asks for its pack
    wow.run_frames(10)
    wow.advance(0.3)  # the packs load after the first frames
    wow.execute(
        """
        local d = Bastians:GetService('data')
        Mock.Keep(d:Get('quest', 62)).rewards = { money = 125 }
        collectgarbage("collect")
        collectgarbage("collect")
        """
    )
    assert wow.eval("Bastians:GetService('data'):Get('quest', 62).rewards.money") == 125
    assert wow.errors == []
