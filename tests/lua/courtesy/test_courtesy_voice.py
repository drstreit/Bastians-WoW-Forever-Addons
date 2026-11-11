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
        weather = 'sandstorm', zone = 'Stranglethorn Vale', subzone = "Nesingwary's Expedition",
        spell = 'Greater Blessing of Wisdom' }})
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


# ---------------------------------------------------------------------------------------------
# The matrix (courtesy.md "The matrix", ADR 0063's amendment of 11.11.2026): what happened as a
# tree, the six moods, and the moment's own facts.
# ---------------------------------------------------------------------------------------------

LANDS = {"forest", "jungle", "swamp", "plains", "desert", "mountains", "frost", "waste", "city"}
RACES = {"Human", "Dwarf", "NightElf", "Gnome", "Orc", "Troll", "Scourge", "Tauren"}
VALUES = {
    "land": LANDS,
    "level": {"higher", "lower", "peer"},
    "weather": {"clear", "rain", "snow", "sandstorm", "other"},
    "time": {"morning", "afternoon", "evening", "night"},
    "race": RACES,
    "mine": RACES,
    "class": {
        "WARRIOR",
        "PALADIN",
        "HUNTER",
        "ROGUE",
        "PRIEST",
        "SHAMAN",
        "MAGE",
        "WARLOCK",
        "DRUID",
    },
    "sex": {"m", "f"},
    "mysex": {"m", "f"},
    "kin": {True, False},
    "heavy": {True, False},
    "fight": {True, False},
    "hurt": {True, False},
    "many": {True, False},
}
ROWS = {
    "buff",
    "buff.mind",
    "buff.stamina",
    "buff.nature",
    "buff.nature.thorns",
    "buff.blessing",
    "buff.blessing.might",
    "buff.blessing.wisdom",
    "buff.blessing.kings",
    "buff.shield",
    "buff.heal",
    "rez",
    "emote.friendly",
    "emote.friendly.bow",
    "emote.friendly.cheer",
    "emote.friendly.love",
    "emote.friendly.thank",
    "emote.rude",
    "invite.accepted",
    "invite.declined",
    "duel.declined",
    "trade.gift",
    "camp",
}
BUFF_ONLY = {"fight", "many"}  # facts only a buff has


def wanted(value) -> list:
    return list(value.values()) if hasattr(value, "values") else [value]


def test_the_matrix_has_its_rows_and_every_cell_its_lines(wow: WowRuntime):
    boot(wow)
    lines = lines_of(wow)
    assert len(lines) >= 900
    assert set(wow.eval(f"{V}.Situations({MOD}.CourtesyLines)").keys()) == ROWS
    cells = {}
    for line in lines:
        cells[(line[1], line[2])] = cells.get((line[1], line[2]), 0) + 1
    moods = set(wow.eval(f"{V}.MOODS").values())
    thin = sorted((row, mood) for row in ROWS for mood in moods if cells.get((row, mood), 0) < 5)
    assert thin == []
    assert not set(wow.eval(f"{V}.CONDITIONS").keys()) ^ set(VALUES)


def test_a_condition_asks_only_for_a_value_that_exists(wow: WowRuntime):
    """A misspelt value would silently keep a line from ever being said."""
    boot(wow)
    for line in lines_of(wow):
        for key, value in (line.when or {}).items():
            for want in wanted(value):
                assert want in VALUES[key], (line[3] or line.act, key, want)
            if key in BUFF_ONLY:
                assert line[1].startswith("buff"), line[3] or line.act
        for part in (line[3], line.act):
            if part and "%s" in part:
                assert line[1].startswith("buff"), part  # only a buff has a spell


def test_every_cell_answers_a_moment_that_knows_only_the_name(wow: WowRuntime):
    """No race, class, place, hour or weather: a line is still there, and a stranger's buff whose
    caster the client does not name finds one without a name."""
    boot(wow)
    moods = sorted(wow.eval(f"{V}.MOODS").values())
    silent = []
    for row in sorted(ROWS):
        named = "" if row.startswith("buff") else "target = 'Mirelle', "
        for mood in moods:
            line = wow.eval(
                f"{V}.Choose({MOD}.CourtesyLines, {V}.Complete({{ situation = '{row}', {named}"
                f"myName = 'Bastian', mySex = 'f' }}), {{ moods = {{ {mood} = 1 }}, via = 'say' }})"
            )
            if line is None:
                silent.append((row, mood))
    assert silent == []


def test_a_line_serves_every_situation_below_it_and_the_deeper_one_is_likelier(wow: WowRuntime):
    boot(wow)
    wow.execute(f"""
      math.randomseed(7)
      LINES = {{
        {{ 'buff', 'polite', 'root' }},
        {{ 'buff.blessing', 'polite', 'branch' }},
        {{ 'buff.blessing.might', 'polite', 'leaf' }},
        {{ 'buff.blessing.kings', 'polite', 'sibling' }},
        {{ 'buff.mind', 'polite', 'cousin' }},
      }}
      COUNT = {{ root = 0, branch = 0, leaf = 0 }}
      for i = 1, 1300 do
        local line = {V}.Choose(LINES, {{ situation = 'buff.blessing.might' }})
        COUNT[line[3]] = COUNT[line[3]] + 1
      end
      BRANCH = {{}}
      for i = 1, 100 do
        BRANCH[{V}.Choose(LINES, {{ situation = 'buff.blessing' }})[3]] = true
      end
    """)
    root, branch, leaf = (wow.eval(f"COUNT.{k}") for k in ("root", "branch", "leaf"))
    assert root + branch + leaf == 1300  # never the sibling, never the cousin
    assert 0 < root < branch < leaf
    assert set(wow.eval("BRANCH").keys()) == {"root", "branch"}


def test_a_line_that_names_the_moment_is_likelier(wow: WowRuntime):
    boot(wow)
    wow.execute(f"""
      math.randomseed(11)
      LINES = {{ {{ 'buff', 'polite', 'plain' }}, {{ 'buff', 'polite', 'near %a with %s' }} }}
      COUNT = {{ plain = 0, named = 0 }}
      local facts = {V}.Complete({{ situation = 'buff', zone = 'Elwynn Forest', spell = 'Thorns' }})
      for i = 1, 600 do
        local line = {V}.Choose(LINES, facts)
        local key = line[3] == 'plain' and 'plain' or 'named'
        COUNT[key] = COUNT[key] + 1
      end
    """)
    plain, named = wow.eval("COUNT.plain"), wow.eval("COUNT.named")
    assert plain > 100 and named > plain * 1.5


@pytest.mark.parametrize(
    ("when", "fact"),
    [
        ("land = 'desert'", "land = 'desert'"),
        ("land = { 'swamp', 'desert' }", "land = 'desert'"),
        ("heavy = true", "heavy = true"),
        ("fight = true", "fight = true"),
        ("fight = false", "fight = false"),
        ("level = 'higher'", "level = 'higher'"),
        ("hurt = true", "hurt = true"),
        ("many = true", "many = true"),
    ],
)
def test_the_moments_facts_rule_a_line_in_and_out(wow: WowRuntime, when: str, fact: str):
    boot(wow)
    wow.execute(f"LINES = {{ {{ 'buff', 'polite', 'x', when = {{ {when} }} }} }}")
    assert wow.eval(f"{V}.Choose(LINES, {{ situation = 'buff', {fact} }})") is not None
    assert wow.eval(f"{V}.Choose(LINES, {{ situation = 'buff' }})") is None  # nobody knows
    other = "land = 'city', heavy = false, fight = 7, level = 'peer', hurt = false, many = false"
    assert wow.eval(f"{V}.Choose(LINES, {{ situation = 'buff', {other} }})") is None


def test_the_spell_and_the_near_place_in_words(wow: WowRuntime):
    boot(wow)
    wow.execute(f"""
      LINE = {{ 'buff', 'polite', '%s near %a, in %z.' }}
      INSIDE = {V}.Complete({{ situation = 'buff', spell = 'Thorns', zone = 'Elwynn Forest',
        subzone = 'Goldshire' }})
      OPEN = {V}.Complete({{ situation = 'buff', spell = 'Thorns', zone = 'Elwynn Forest' }})
    """)
    assert wow.eval(f"{V}.Words(LINE, INSIDE, 'say')") == "Thorns near Goldshire, in Elwynn Forest."
    # no named place around: the zone is the nearest name
    said = wow.eval(f"{V}.Words(LINE, OPEN, 'say')")
    assert said == "Thorns near Elwynn Forest, in Elwynn Forest."
    # no spell, no place: the line is not a candidate
    assert wow.eval(f"{V}.Choose({{ LINE }}, {V}.Complete({{ situation = 'buff' }}))") is None


def test_heavy_weather_the_level_gap_and_being_hurt(wow: WowRuntime):
    boot(wow)
    m = f"{MOD}.Model"
    assert wow.eval(f"{m}.Heavy('rain', 0.8)") is True
    assert wow.eval(f"{m}.Heavy('rain', 0.2)") is False
    assert wow.eval(f"{m}.Heavy('clear', 0.8)") is None  # no weather to be heavy
    assert wow.eval(f"{m}.Heavy('rain', nil)") is None
    assert wow.eval(f"{m}.Heavy(nil, 0.8)") is None
    assert wow.eval(f"{m}.LevelGap(40, 12)") == "higher"
    assert wow.eval(f"{m}.LevelGap(8, 30)") == "lower"
    assert wow.eval(f"{m}.LevelGap(14, 12)") == "peer"
    assert wow.eval(f"{m}.LevelGap(0, 12)") is None  # the client gives no level
    assert wow.eval(f"{m}.LevelGap(nil, 12)") is None
    assert wow.eval(f"{m}.Hurt(30, 100)") is True
    assert wow.eval(f"{m}.Hurt(80, 100)") is False
    assert wow.eval(f"{m}.Hurt(0, 100)") is None  # dead is not hurt
    assert wow.eval(f"{m}.Hurt(nil, 100)") is None


def test_every_kind_of_country_is_one_the_lines_and_the_try_know(wow: WowRuntime):
    boot(wow)
    assert set(wow.eval(f"{MOD}.Model.LANDS").values()) == LANDS
    for land in LANDS:
        w = wow.eval(f"{T}.Parse('{land}', {MOD}.CourtesyLines)")
        assert w.land == land and list(w.unknown.values()) == []


def test_the_spells_with_lines_of_their_own_sit_on_rows_of_the_matrix(wow: WowRuntime):
    boot(wow)
    for kind in set(wow.eval(f"{MOD}.Model.BUFFS").values()):
        assert f"buff.{kind}" in ROWS, kind


def test_the_surroundings_name_the_place_and_its_country(wow: WowRuntime):
    boot(wow)
    wow.execute("""
      Mock.zoneText, Mock.subZoneText, Mock.playerMap = 'Tanaris', 'Gadgetzan', 1446
      Mock.level, Mock.unitLevels = 12, { target = 40 }
      Mock.unitHealth.player = { 30, 100 }
      C_Weather = { GetCurrentWeather = function() return { type = 3, intensity = 0.9 } end }
    """)
    f = wow.eval(f"{V}.Complete({MOD}.Facts.Unit({MOD}.Facts.Surroundings({{}}), 'target'))")
    assert (f.zone, f.subzone, f.near, f.land) == ("Tanaris", "Gadgetzan", "Gadgetzan", "desert")
    assert (f.weather, f.heavy, f.hurt, f.level) == ("sandstorm", True, True, "higher")
    # a zone we have no country for, no named place, a level the client does not give
    wow.execute("""
      Mock.zoneText, Mock.subZoneText, Mock.playerMap = 'Zephras Isle', 'Zephras Isle', 2521
      Mock.unitLevels = {}
      UnitHealth = function() return Mock.Secret() end
    """)
    f = wow.eval(f"{V}.Complete({MOD}.Facts.Unit({MOD}.Facts.Surroundings({{}}), 'target'))")
    assert (f.zone, f.subzone, f.near, f.land) == ("Zephras Isle", None, "Zephras Isle", None)
    assert f.hurt is None and f.level is None
    assert errors(wow) == []


def test_try_knows_the_new_words_and_says_them(wow: WowRuntime):
    boot(wow)
    w = wow.eval(
        f"{T}.Parse('buff.shield weary desert higher fight heavy hurt many', {MOD}.CourtesyLines)"
    )
    assert (w.situation, w.mood, w.land, w.level) == ("buff.shield", "weary", "desert", "higher")
    assert (w.fight, w.heavy, w.hurt, w.many) == (True, True, True, True)
    assert list(w.unknown.values()) == []
    wow.execute("SlashCmdList.BASTIANSCOURTESY('try 1 buff.shield snarky rain desert lower fight')")
    last = chat(wow)[-1]
    assert "buff" in last and "desert, lower, fight" in last
    assert sent(wow) == [] and errors(wow) == []


def test_an_invented_moment_keeps_the_place_and_its_country_together(wow: WowRuntime):
    boot(wow)
    wow.execute(f"""
      math.randomseed(3)
      BAD = {{}}
      for i = 1, 60 do
        local w = {T}.Parse('buff.heal', {MOD}.CourtesyLines)
        local f = {T}.Invent(w, {MOD}.CourtesyLines, math.random)
        if not (f.land and f.zone and f.near and f.spell and f.fight ~= nil and f.many ~= nil) then
          BAD[#BAD + 1] = i
        end
        if f.weather == 'clear' and f.heavy ~= nil then BAD[#BAD + 1] = -i end
      end
      REZ = {T}.Invent({T}.Parse('rez', {MOD}.CourtesyLines), {MOD}.CourtesyLines, math.random)
    """)
    assert list(wow.eval("BAD").values()) == []
    assert wow.eval("REZ.spell") is None and wow.eval("REZ.fight") is None  # only a buff has them
