"""The voice of courtesy (courtesy.md, ADR 0063): the shipped lines are well formed, the
choice honours facts, moods and memory, a fact nobody knows rules a line out, and /bcourtesy try
prints without sending."""

import re
from pathlib import Path

import pytest
from harness import WowRuntime
from test_courtesy import MOD, boot, errors, sent

ROOT = Path(__file__).resolve().parents[3]
V = f"{MOD}.Voice"
T = f"{MOD}.Try"

FACTS = """{ situation = 'buff.mind', target = 'Mirelle', myName = 'Bastian', myRace = 'Human',
  myRaceKey = 'Human', mySex = 'f', race = 'Dwarf', raceKey = 'Dwarf', class = 'Mage',
  classKey = 'MAGE', sex = 'm', time = 'night', weather = 'rain', zone = 'Elwynn Forest' }"""


def lines_of(wow: WowRuntime) -> list:
    return list(wow.eval(f"{MOD}.CourtesyLines").values())


def choose(wow: WowRuntime, facts: str = FACTS, opts: str = "nil"):
    return wow.eval(f"{V}.Choose({MOD}.CourtesyLines, {V}.Complete({facts}), {opts})")


def chat(wow: WowRuntime) -> list[str]:
    return [str(line) for line in wow.eval("Mock.chat").values()]


def test_the_shipped_lines_are_well_formed(wow: WowRuntime):
    boot(wow)
    lines = lines_of(wow)
    assert len(lines) >= 200
    moods = set(wow.eval(f"{V}.MOODS").values())
    conditions = set(wow.eval(f"{V}.CONDITIONS").keys())
    slots = set(wow.eval(f"{V}.SLOTS").keys())
    tokens = {e[1] for e in wow.eval("Bastians:GetModule('Gestures').Model.EMOTES").values()}
    seen = {}
    for line in lines:
        situation, mood, text = line[1], line[2], line[3]
        assert mood in moods, text
        assert text or line.act, situation
        assert (text, line.act) not in seen, text
        seen[(text, line.act)] = True
        if line.when:
            assert set(line.when.keys()) <= conditions, text
        if line.emote:
            assert line.emote in tokens, line.emote
        for part in (text, line.act):
            if part:
                assert set(re.findall(r"%(\w+)", part)) <= slots, part
                assert part.isascii(), part


def test_every_situation_has_every_mood_with_a_spoken_line(wow: WowRuntime):
    boot(wow)
    lines = lines_of(wow)
    moods = set(wow.eval(f"{V}.MOODS").values())
    parents = {}
    for line in lines:
        if line[3] and not line.when:
            parents.setdefault(line[1], set()).add(line[2])
    assert "buff" in parents
    for situation, have in parents.items():
        family = have | (parents["buff"] if situation.startswith("buff.") else set())
        assert family == moods, situation


def test_every_filled_line_fits_one_chat_message(wow: WowRuntime):
    boot(wow)
    wow.execute(f"""
      local long = 'Thalendrianna-Silbermond'
      local facts = {V}.Complete({{ target = long, myName = long, myRace = 'Night Elf',
        race = 'Night Elf', class = 'Warlock', mySex = 'f', sex = 'f', time = 'afternoon',
        weather = 'sandstorm', zone = 'The Barrens' }})
      TOO_LONG = {{}}
      for _, line in ipairs({MOD}.CourtesyLines) do
        local words = {V}.Words(line, facts, 'emote')
        if #words > {V}.MAX_BYTES then TOO_LONG[#TOO_LONG + 1] = words end
      end
    """)
    assert list(wow.eval("TOO_LONG").values()) == []


def test_a_fact_nobody_knows_rules_a_line_out(wow: WowRuntime):
    boot(wow)
    wow.execute(f"""
      LINES = {{
        {{ 'buff', 'polite', 'rainy', when = {{ weather = 'rain' }} }},
        {{ 'buff', 'polite', 'sir %o' }},
        {{ 'buff', 'polite', 'name %t' }},
      }}
      FOUND = {{}}
      for i = 1, 50 do
        local line = {V}.Choose(LINES, {V}.Complete({{ situation = 'buff', target = 'Mirelle' }}))
        FOUND[line[3]] = true
      end
    """)
    assert list(wow.eval("FOUND").keys()) == ["name %t"]
    assert (
        wow.eval(f"{V}.Choose(LINES, {V}.Complete({{ situation = 'buff' }}))") is None
    )  # no name either


def test_the_words_of_say_and_of_emote(wow: WowRuntime):
    boot(wow)
    wow.execute(f"""
      F = {V}.Complete({FACTS})
      BOTH = {{ 'buff', 'polite', 'Thank you, %t.', act = 'bows to %t with %p hat.' }}
      SPEECH = {{ 'buff', 'polite', 'Thank you, %t.' }}
      SILENT = {{ 'buff', 'polite', false, act = 'nods to %t.' }}
    """)
    assert wow.eval(f"{V}.Words(BOTH, F, 'say')") == "Thank you, Mirelle."
    assert (
        wow.eval(f"{V}.Words(BOTH, F, 'emote')")
        == 'bows to Mirelle with her hat. "Thank you, Mirelle."'
    )
    assert wow.eval(f"{V}.Words(SPEECH, F, 'emote')") == 'says, "Thank you, Mirelle."'
    assert wow.eval(f"{V}.Words(SILENT, F, 'emote')") == "nods to Mirelle."
    assert wow.eval(f"{V}.Words(SILENT, F, 'say')") is None


def test_a_mood_filter_and_the_say_filter(wow: WowRuntime):
    boot(wow)
    for _ in range(40):
        assert choose(wow, opts="{ moods = { snarky = 1 } }")[2] == "snarky"
    wow.execute("""
      LINES = { { 'buff', 'polite', false, act = 'nods.' }, { 'buff', 'polite', 'Thanks.' } }
    """)
    for _ in range(20):
        line = wow.eval(f"{V}.Choose(LINES, {{ situation = 'buff' }}, {{ via = 'say' }})")
        assert line[3] == "Thanks."


def test_a_line_that_fits_better_is_likelier_but_not_the_only_one(wow: WowRuntime):
    boot(wow)
    wow.execute(f"""
      math.randomseed(42)
      LINES = {{
        {{ 'buff', 'polite', 'plain' }},
        {{ 'buff', 'polite', 'rain', when = {{ weather = 'rain' }} }},
      }}
      COUNT = {{ plain = 0, rain = 0 }}
      local facts = {V}.Complete({{ situation = 'buff', weather = 'rain' }})
      for i = 1, 400 do
        local line = {V}.Choose(LINES, facts)
        COUNT[line[3]] = COUNT[line[3]] + 1
      end
    """)
    plain, rain = wow.eval("COUNT.plain"), wow.eval("COUNT.rain")
    assert plain > 0 and rain > plain * 2


def test_a_child_situation_also_hears_its_parent_and_never_a_sibling(wow: WowRuntime):
    boot(wow)
    wow.execute(f"""
      LINES = {{
        {{ 'buff', 'polite', 'parent' }},
        {{ 'buff.mind', 'polite', 'child' }},
        {{ 'buff.nature', 'polite', 'sibling' }},
        {{ 'rez', 'polite', 'other' }},
      }}
      FOUND = {{}}
      for i = 1, 200 do
        FOUND[{V}.Choose(LINES, {{ situation = 'buff.mind' }})[3]] = true
      end
    """)
    assert set(wow.eval("FOUND").keys()) == {"parent", "child"}


def test_no_repeat_while_another_line_exists_then_rather_again_than_silence(wow: WowRuntime):
    boot(wow)
    wow.execute(f"""
      LINES = {{ {{ 'buff', 'polite', 'one' }}, {{ 'buff', 'polite', 'two' }} }}
      RECENT = {{}}
      SAID = {{}}
      for i = 1, 3 do
        local line = {V}.Choose(LINES, {{ situation = 'buff' }}, {{ recent = RECENT }})
        {V}.Remember(RECENT, line)
        SAID[i] = line[3]
      end
    """)
    said = list(wow.eval("SAID").values())
    assert len(said) == 3 and said[0] != said[1]


def test_the_memory_forgets_the_oldest(wow: WowRuntime):
    boot(wow)
    wow.execute(f"""
      RECENT = {{}}
      FIRST = {{ 'a' }}
      {V}.Remember(RECENT, FIRST)
      for i = 1, {V}.RECENT do {V}.Remember(RECENT, {{ i }}) end
    """)
    assert wow.eval("RECENT[FIRST]") is None


def test_try_reads_its_words_in_any_order(wow: WowRuntime):
    boot(wow)
    w = wow.eval(
        f"{T}.Parse('20 Snarky buff.mind rain night dwarf f mage me:orc me:m', {MOD}.CourtesyLines)"
    )
    assert (w.count, w.mood, w.situation, w.weather, w.time) == (
        20,
        "snarky",
        "buff.mind",
        "rain",
        "night",
    )
    assert (w.race, w.sex, w["class"], w.myRace, w.mySex) == ("dwarf", "f", "mage", "orc", "m")
    assert list(w.unknown.values()) == []


def test_try_prints_and_sends_nothing(wow: WowRuntime):
    boot(wow)
    before = len(chat(wow))
    wow.execute("SlashCmdList.BASTIANSCOURTESY('try 12 me:dwarf')")
    wow.advance(5)
    assert len(chat(wow)) - before == 12
    assert sent(wow) == []
    assert list(wow.eval("Mock.emotes").values()) == []
    assert errors(wow) == []


def test_try_on_named_facts_says_them(wow: WowRuntime):
    boot(wow)
    wow.execute("SlashCmdList.BASTIANSCOURTESY('try 1 rez snarky rain night orc m shaman')")
    last = chat(wow)[-1]
    assert "rez, snarky, rain, night, Orc, m, Shaman" in last
    assert errors(wow) == []


def test_an_unknown_word_explains_itself(wow: WowRuntime):
    boot(wow)
    wow.execute("SlashCmdList.BASTIANSCOURTESY('try gibberish')")
    lines = chat(wow)
    assert "Unknown word: gibberish" in lines[-2]
    assert "/bcourtesy try" in lines[-1]
    assert sent(wow) == []


@pytest.mark.parametrize(
    ("kind", "word"), [(0, "clear"), (1, "rain"), (2, "snow"), (3, "sandstorm"), (4, "other")]
)
def test_the_weather_in_words(wow: WowRuntime, kind: int, word: str):
    boot(wow)
    wow.execute(
        f"C_Weather = {{ GetCurrentWeather = function() return {{ type = {kind}, intensity = 0.5 }} end }}"
    )
    assert wow.eval(f"({MOD}.Compat.Weather())") == word


def test_unknown_weather_stays_unknown(wow: WowRuntime):
    boot(wow)
    wow.execute("C_Weather = nil")
    assert wow.eval(f"({MOD}.Compat.Weather())") is None
    wow.execute(
        "C_Weather = { GetCurrentWeather = function() return { type = Mock.Secret() } end }"
    )
    assert wow.eval(f"({MOD}.Compat.Weather())") is None


TEMPLATE = ROOT / "addons/Bastians_Courtesy/Template/Bastians_MyLines"
OWN = """Bastians:AddCourtesyLines({
  { 'rez', 'polite', 'MY OWN LINE, %t.' },
  { 'rez', 'polite', false, act = 'MY OWN ACT toward %t.', when = { time = 'night' } },
})"""
REZ_MORNING = FACTS.replace("buff.mind", "rez").replace("'night'", "'morning'")


def choose_mine(wow: WowRuntime, facts: str = FACTS):
    return wow.eval(f"{MOD}.Mine.Choose({V}.Complete({facts}))")


def problem(wow: WowRuntime, line: str):
    return wow.eval(f"{V}.Problem({line}, {V}.Situations({MOD}.CourtesyLines))")


def switch(wow: WowRuntime, on: bool) -> None:
    wow.execute(f"{MOD}.db.profile.myLines = {'true' if on else 'false'}")


def uses_ours(wow: WowRuntime) -> bool:
    return wow.eval(f"{MOD}.Mine.Pool() == {MOD}.CourtesyLines")


def test_without_the_addon_our_lines_and_the_check_says_how_to_install(wow: WowRuntime):
    boot(wow)
    assert uses_ours(wow)
    assert wow.eval(f"{MOD}.Mine.Report()") is False
    said = " ".join(chat(wow))
    assert "Bastians_MyLines is not installed" in said
    assert "Template/Bastians_MyLines" in said
    assert not errors(wow)


def test_on_takes_my_line_where_one_fits_and_ours_where_none_does(wow: WowRuntime):
    boot(wow)
    wow.execute(OWN)
    assert wow.eval(f"{MOD}.db.profile.myLines") is True
    # the silent line of mine needs the night and it is morning, so only the spoken one fits
    for _ in range(30):
        assert choose_mine(wow, REZ_MORNING)[3] == "MY OWN LINE, %t."
    # I wrote nothing for a buff: one of ours, not silence
    wow.execute(f"OURS = {MOD}.Mine.Choose({V}.Complete({FACTS}))")
    assert wow.eval("OURS") is not None
    assert wow.eval(f"{MOD}.Mine.Owns(OURS)") is False


def test_off_means_ours_alone(wow: WowRuntime):
    boot(wow)
    wow.execute(OWN)
    switch(wow, False)
    assert uses_ours(wow)
    for _ in range(40):
        assert "MY OWN" not in str(choose_mine(wow, REZ_MORNING)[3])
    wow.eval(f"{MOD}.Mine.Report()")
    assert any("switch is off" in line for line in chat(wow))


def test_on_without_a_usable_line_is_ours(wow: WowRuntime):
    boot(wow)
    wow.execute("Bastians:AddCourtesyLines({ { 'rez', 'grumpy', 'bad' } })")
    assert uses_ours(wow)


@pytest.mark.parametrize(
    ("line", "word"),
    [
        ("'just text'", "not a line"),
        ("{ 'sneeze', 'polite', 'x' }", "situation"),
        ("{ 'rez', 'grumpy', 'x' }", "mood"),
        ("{ 'rez', 'polite', false }", "text or an act"),
        ("{ 'rez', 'polite', 5 }", "text or an act"),
        ("{ 'rez', 'polite', 'x', emote = 5 }", "emote"),
        ("{ 'rez', 'polite', 'hello %q' }", "%q"),
        ("{ 'rez', 'polite', false, act = 'nods at %q' }", "%q"),
        ("{ 'rez', 'polite', 'x', when = { moon = 'full' } }", "moon"),
        ("{ 'rez', 'polite', 'x', when = 'night' }", "condition"),
        (f"{{ 'rez', 'polite', '{'x' * 230}' }}", "too long"),
    ],
)
def test_a_bad_line_is_named(wow: WowRuntime, line: str, word: str):
    boot(wow)
    assert word in str(problem(wow, line))


def test_a_good_line_passes_and_a_bad_one_does_not_stop_the_rest(wow: WowRuntime):
    boot(wow)
    assert problem(wow, "{ 'rez', 'polite', 'Fine, %t.', when = { time = 'night' } }") is None
    wow.execute(
        "Bastians:AddCourtesyLines({ { 'rez', 'grumpy', 'bad' }, { 'rez', 'polite', 'GOOD, %t.' } })"
    )
    assert wow.eval(f"{MOD}.Mine.Report()") is True
    said = chat(wow)
    assert any("1 can be used, 1 cannot" in line for line in said)
    assert any("Line 1:" in line and "grumpy" in line for line in said)
    assert choose_mine(wow, REZ_MORNING)[3] == "GOOD, %t."


def test_try_follows_the_switch_and_tags_my_line(wow: WowRuntime):
    boot(wow)
    wow.execute(OWN)
    wow.eval(f"{T}.Run('5 polite morning')")
    assert sum("my line" in line for line in chat(wow)) == 5
    assert not sent(wow)
    wow.execute("Mock.chat = {}")
    switch(wow, False)
    wow.eval(f"{T}.Run('5 rez polite morning')")
    assert not any("my line" in line for line in chat(wow))


def test_the_slash_command_reports(wow: WowRuntime):
    boot(wow)
    wow.execute(OWN)
    wow.execute("SlashCmdList.BASTIANSCOURTESY('mine')")
    assert any("2 can be used, 0 cannot" in line for line in chat(wow))


def test_the_template_as_shipped_is_valid(wow: WowRuntime):
    boot(wow)
    wow.execute((TEMPLATE / "MyLines.lua").read_text(encoding="utf-8"))
    assert wow.eval(f"{MOD}.Mine.Report()") is True
    assert any(", 0 cannot" in line for line in chat(wow))
    assert not errors(wow)
    assert not uses_ours(wow)


def test_the_template_is_an_addon_of_its_own():
    toc = (TEMPLATE / "Bastians_MyLines.toc").read_text(encoding="utf-8")
    assert "## Dependencies: Bastians_Core" in toc
    assert "\nMyLines.lua" in toc


def test_the_core_registry_refuses_what_is_not_a_table(wow: WowRuntime):
    boot(wow)
    assert wow.eval("(pcall(Bastians.AddCourtesyLines, Bastians, 'nope'))") is False
