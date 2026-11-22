"""Both packs speak in patterns (ADR 0089): every cell of the matrix, the rules of
tools/courtesy_lines_check.py on every variant, and a ring that says only its language, a variant
at a time, never a stitched answer. English joined on 22.11.2026."""

import sys
from pathlib import Path

import pytest
from harness import WowRuntime
from test_courtesy import MOD, boot, errors

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))
import courtesy_lines_check as check  # noqa: E402

V = f"{MOD}.Voice"


def plain(value):
    """A Lua table as Python: lists for arrays, dicts for the rest."""
    if not hasattr(value, "items"):
        return value
    keys = list(value.keys())
    if keys and keys == list(range(1, len(keys) + 1)):
        return [plain(value[k]) for k in keys]
    return {k: plain(v) for k, v in value.items()}


def pack_lines(wow: WowRuntime, lang: str) -> list[dict]:
    out = []
    for line in wow.eval(f"{V}.PACKS.{lang}.lines").values():
        entry = {k: plain(v) for k, v in line.items()}
        out.append(entry)
    return out


@pytest.mark.parametrize("lang", ["deDE", "enUS"])
def test_each_pack_is_complete_and_holds_to_the_rules(wow: WowRuntime, lang: str):
    boot(wow)
    lines = pack_lines(wow, lang)
    assert len(lines) >= 600
    assert check.check(lines, lang) == []
    assert check.thin(lines) == []
    pack = wow.eval(f"{V}.PACKS.{lang}")
    assert pack.react is None and pack.greet is None  # no parts: nothing is stitched together
    assert errors(wow) == []


@pytest.mark.parametrize("lang", ["deDE", "enUS"])
def test_a_ring_speaks_its_language_one_variant_at_a_time(wow: WowRuntime, lang: str):
    boot(wow)
    wow.execute(f"{V}.language = '{lang}'")
    wow.execute(f"""
      math.randomseed(9)
      OUT = {{}}
      for i, situation in ipairs({{ 'buff.stamina', 'rez', 'emote.friendly.bow', 'camp.greet',
          'ambient', 'duel.declined', 'buff' }}) do
        for j = 1, 12 do
          local facts = {MOD}.Facts.Surroundings({MOD}.Facts.Speaker())
          facts.situation, facts.target, facts.lang = situation, 'Mirelle', '{lang}'
          local line = {MOD}.Mine.Choose({V}.Complete(facts), {{}})
          local known = false
          for _, l in ipairs({V}.PACKS.{lang}.lines) do
            if l == {V}.Source(line) then known = true end
          end
          OUT[#OUT + 1] = {{ text = line[3], known = known, parts = line.parts ~= nil,
            situation = situation }}
        end
      end
    """)
    for answer in wow.eval("OUT").values():
        assert answer.known, answer.text
        assert not answer.parts, answer.text
        assert "{" not in answer.text and "|" not in answer.text, answer.text
        assert answer.text[0].isupper() or answer.text.startswith("%"), answer.text
    assert errors(wow) == []


def test_a_deed_is_thanked_in_every_german_variant(wow: WowRuntime):
    """The check enumerates the variants; here one ring per deed row, as a player gets it."""
    boot(wow)
    wow.execute(f"""
      math.randomseed(4)
      OUT = {{}}
      for _, situation in ipairs({{ 'buff.heal', 'rez', 'trade.gift', 'invite.accepted', 'camp' }}) do
        local facts = {V}.Complete({{ situation = situation, target = 'Mirelle', myName = 'Bastian',
          lang = 'deDE' }})
        for _, line in ipairs({MOD}.Courtesy.Lines(facts, 3, nil, 'say')) do
          OUT[#OUT + 1] = line[3]
        end
      end
    """)
    said = list(wow.eval("OUT").values())
    assert len(said) == 15
    assert all("dank" in text.lower() for text in said), said
