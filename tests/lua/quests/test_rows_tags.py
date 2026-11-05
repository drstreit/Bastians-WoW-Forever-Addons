"""Owner, Forever launch night 05.11.2026: "Rows.lua:222: attempt to concatenate local 'color' (a nil
value)" on every zone view. The Forever-only tag used a colour name the token map did not know; retail
data never sets foreverOnly, so the line had never run before launch. Every colour name Rows uses
must resolve in every theme."""

from harness import WowRuntime

MOD = "Bastians:GetModule('Quests')"


def test_a_forever_only_quest_gets_its_tag_without_an_error(wow: WowRuntime):
    wow.start("Bastians_Core", "Bastians_Data", "Bastians_Quests")
    wow.run_frames(10)
    wow.execute(
        f"""local Logic = {MOD}.Logic
        local q = {{}}
        for k, v in pairs(Logic.quest(176)) do q[k] = v end
        q.foreverOnly = true
        TAGS = {MOD}.Rows.tags(176, q, {MOD}.State.ForLogic())"""
    )
    assert "Forever" in (wow.eval("TAGS") or "")
    assert wow.errors == []


def test_every_colour_name_used_by_rows_resolves_in_every_theme(wow: WowRuntime):
    wow.start("Bastians_Core", "Bastians_Data", "Bastians_Quests")
    wow.run_frames(10)
    for name in ("red", "orange", "yellow", "green", "grey", "white", "blue"):
        wow.execute(
            f"""MISSING = {{}}
            local S = Bastians.UI.Style
            for _, theme in ipairs(S.THEMES) do
              S.WithPalette(S.Palette(theme.id), function()
                if not {MOD}.Rows.COLOR["{name}"] then MISSING[#MISSING + 1] = theme.id end
              end)
            end"""
        )
        assert wow.eval("table.concat(MISSING, ',')") == "", f"{name} missing in themes"
    assert wow.errors == []
