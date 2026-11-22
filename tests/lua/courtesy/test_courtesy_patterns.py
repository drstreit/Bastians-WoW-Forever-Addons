"""Patterns with variants (ADR 0089): a line's choice groups are realised when it is offered, tidy
and with capitals; a choice whose fact is unknown is not taken; memory, Never and the ring keep the
pattern, whichever variant was said; a player's own line may carry groups too."""

from harness import WowRuntime
from test_courtesy import MOD, boot, errors

V = f"{MOD}.Voice"
FACTS = "{ situation = 'buff', target = 'Mirelle', myName = 'Bastian', weather = 'rain' }"
NAMELESS = "{ situation = 'buff', myName = 'Bastian' }"


def realise_all(wow: WowRuntime, text: str, facts: str = FACTS, n: int = 200, act: str = "nil"):
    wow.execute(f"""
      math.randomseed(7)
      LINE = {{ 'buff', 'cheerful', {text}, act = {act} }}
      OUT = {{}}
      for i = 1, {n} do
        local r = {V}.Realise(LINE, {V}.Complete({facts}), math.random)
        OUT[i] = r and {{ text = r[3], act = r.act, same = r.pattern == LINE }} or false
      end
    """)
    return list(wow.eval("OUT").values())


def test_every_choice_comes_and_the_words_are_tidy(wow: WowRuntime):
    boot(wow)
    out = realise_all(wow, "'{oh, |}danke{ dir|}! {das kribbelt.|}'")
    texts = {r.text for r in out}
    assert texts == {
        "Oh, danke dir! Das kribbelt.",
        "Oh, danke! Das kribbelt.",
        "Danke dir! Das kribbelt.",
        "Danke! Das kribbelt.",
        "Oh, danke dir!",
        "Oh, danke!",
        "Danke dir!",
        "Danke!",
    }
    assert all(r.same for r in out)
    assert errors(wow) == []


def test_a_german_sentence_starts_with_a_capital_umlaut_but_not_after_dots(wow: WowRuntime):
    boot(wow)
    texts = {r.text for r in realise_all(wow, "'{|}übel war das. {|}ätzend! ah... danke.'", n=20)}
    assert texts == {"Übel war das. Ätzend! Ah... danke."}


def test_the_act_keeps_its_small_letter_and_no_space_before_a_stop(wow: WowRuntime):
    boot(wow)
    out = realise_all(wow, "false", act="'{nickt|winkt} {kurz|} .'", n=60)
    assert {r.act for r in out} == {"nickt kurz.", "nickt.", "winkt kurz.", "winkt."}


def test_a_choice_whose_fact_is_unknown_is_not_taken(wow: WowRuntime):
    boot(wow)
    out = realise_all(wow, "'Danke{, %t|}!'", facts=NAMELESS, n=40)
    assert {r.text for r in out} == {"Danke!"}
    named = {r.text for r in realise_all(wow, "'Danke{, %t|}!'", n=60)}
    assert named == {"Danke, %t!", "Danke!"}  # the slot is filled when the line is said


def test_a_group_without_a_known_choice_rules_the_line_out(wow: WowRuntime):
    boot(wow)
    assert realise_all(wow, "'Danke{, %t| an %t}!'", facts=NAMELESS, n=5) == [False] * 5
    wow.execute(
        "PICKS = { { 'buff', 'cheerful', 'Danke{, %t| an %t}!' }, { 'buff', 'polite', 'Merci.' } }"
    )
    for _ in range(20):
        line = wow.eval(f"{V}.Choose(PICKS, {V}.Complete({NAMELESS}), {{}})")
        assert line[3] == "Merci."


def test_memory_and_never_keep_the_pattern(wow: WowRuntime):
    boot(wow)
    wow.execute(f"""
      math.randomseed(3)
      PICKS = {{ {{ 'buff', 'cheerful', '{{Danke|Merci}}{{ dir|}}!' }}, {{ 'buff', 'cheerful', 'Oh, danke.' }} }}
      RECENT = {{}}
      FIRST = {V}.Choose({{ PICKS[1] }}, {V}.Complete({FACTS}), {{}})
      {V}.Remember(RECENT, FIRST)
      LATER = {{}}
      for i = 1, 20 do
        LATER[i] = {V}.Choose(PICKS, {V}.Complete({FACTS}), {{ recent = RECENT }})[3]
      end
    """)
    assert wow.eval("FIRST.pattern == PICKS[1]") is True
    assert set(wow.eval("LATER").values()) == {"Oh, danke."}
    assert wow.eval(f"{V}.Key(FIRST)") == "{Danke|Merci}{ dir|}!"
    assert wow.eval(f"{V}.Source(FIRST) == PICKS[1]") is True
    assert wow.eval(f"{V}.Source(PICKS[2]) == PICKS[2]") is True


def test_a_line_without_a_group_comes_back_as_it_is(wow: WowRuntime):
    boot(wow)
    wow.execute(f"PLAIN = {{ 'buff', 'polite', 'Thank you.' }}; R = {V}.Realise(PLAIN, {{}})")
    assert wow.eval("R == PLAIN") is True


def test_one_pattern_is_never_twice_in_a_ring(wow: WowRuntime):
    boot(wow)
    wow.execute(f"""
      math.randomseed(5)
      {V}.PACKS.test = {{ name = 'Test', short = 'TT', words = {{}}, lines = {{
        {{ 'buff', 'polite', '{{Danke|Vielen Dank|Danke schön|Merci}}{{, %t|}}.' }},
        {{ 'buff', 'cheerful', '{{Danke|Juhu, danke}}!' }},
        {{ 'buff', 'weary', '{{Ah|Oh}}... danke.' }},
      }} }}
      {V}.language = 'test'
      RINGS = {{}}
      local C = {MOD}.Courtesy
      for i = 1, 30 do
        local facts = {V}.Complete({{ situation = 'buff', target = 'Mirelle', myName = 'Bastian', lang = 'test' }})
        local ring = C.Lines(facts, 3, nil, 'say')
        local keys = {{}}
        for j, line in ipairs(ring) do keys[j] = {V}.Key(line) end
        RINGS[i] = keys
      end
    """)
    for ring in wow.eval("RINGS").values():
        keys = list(ring.values())
        assert len(keys) == len(set(keys)), keys
    assert errors(wow) == []


def test_an_own_line_with_an_open_brace_is_refused(wow: WowRuntime):
    boot(wow)
    problem = wow.eval(f"{V}.Problem({{ 'buff', 'polite', 'Danke{{ dir!' }}, {{ buff = true }})")
    assert problem == "a { choice | group } does not close"
    nested = wow.eval(f"{V}.Problem({{ 'buff', 'polite', '{{a{{b|c}}|d}}' }}, {{ buff = true }})")
    assert nested == "a { choice | group } does not close"
    stray = wow.eval(f"{V}.Problem({{ 'buff', 'polite', 'a | b' }}, {{ buff = true }})")
    assert stray == "a { choice | group } does not close"
    fine = wow.eval(f"{V}.Problem({{ 'buff', 'polite', '{{Danke|Merci}}!' }}, {{ buff = true }})")
    assert fine is None


def test_the_longest_variant_counts_for_the_length(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f"{V}.Longest('{{a|bbb|}}cc')") == 5
    assert wow.eval(f"{V}.Longest(nil)") == 0
    assert wow.eval(f"{V}.Longest('{{a')") is None
