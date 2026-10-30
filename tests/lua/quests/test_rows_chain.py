"""(R25.26): "job quests-all: Rows.lua:226: attempt to concatenate field
'?' (a nil value)": a retail chain that does not list the quest naming it."""

from harness import WowRuntime


def test_a_chain_without_the_quest_gives_no_chain_tag_and_no_error(wow: WowRuntime):
    wow.start("Bastians_Core", "Bastians_Data", "Bastians_Quests")
    wow.run_frames(10)
    mod = "Bastians:GetModule('Quests')"
    wow.execute(
        f"""local Logic = {mod}.Logic
        Logic.chain = function() return {{ pos = {{}}, quests = {{ 1, 2, 3 }} }} end
        TAGS = {mod}.Rows.tags(176, Logic.quest(176), {mod}.State.ForLogic())"""
    )
    assert "Chain" not in (wow.eval("TAGS") or "")
    assert wow.errors == []
