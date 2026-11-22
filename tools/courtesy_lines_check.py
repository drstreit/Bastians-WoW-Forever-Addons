"""Check Courtesy patterns before they join a language pack, and write them into it (ADR 0089).

Usage: python tools/courtesy_lines_check.py --lang deDE <fragment.lua> [...] [--mood M] [--write]

A fragment is a Lua chunk `return { lines = { ... } }`; ANYONE, DEEDS and EVERYWHERE are known
names. A line is { situation or { situations }, mood, text, act = ..., when = {...}, emote = ... }
whose text and act may hold choice groups `{a|b|}` (one choice each, an empty one says nothing).
Every variant is realised as the addon does it (Voice.Realise) and checked. Prints each problem
and the cells still thin (for one mood with --mood); exit 1 when there is any. With --write the
lines replace what stands between `-- LINES BEGIN` and `-- LINES END` in
addons/Bastians_Courtesy/Lines_<lang>.lua, refused when the whole pack fails the check.
The rules are ADR 0089 decision 5; tests/lua/courtesy/test_courtesy_lines.py holds the packs
to them.
"""

from __future__ import annotations

import argparse
import itertools
import random
import re
import sys
from collections import Counter
from pathlib import Path

from lupa import lua51

ROOT = Path(__file__).resolve().parent.parent
MOODS = ("polite", "roleplay", "snarky", "philosophic", "cheerful", "weary")
BUFF_ROWS = (
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
)
OTHER_ROWS = (
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
    "camp.greet",
    "ambient",
)
ROWS = BUFF_ROWS + OTHER_ROWS
ROOTS = {"buff", "rez", "emote", "invite", "duel", "trade", "camp", "ambient"}
RACES = ("Human", "Dwarf", "NightElf", "Gnome", "Orc", "Troll", "Scourge", "Tauren")
CLASSES = ("WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID")
VALUES = {
    "land": {
        "forest",
        "jungle",
        "swamp",
        "plains",
        "desert",
        "mountains",
        "frost",
        "waste",
        "city",
    },
    "level": {"higher", "lower", "peer"},
    "weather": {"clear", "rain", "snow", "sandstorm", "other"},
    "time": {"morning", "afternoon", "evening", "night"},
    "race": set(RACES),
    "mine": set(RACES),
    "class": set(CLASSES),
    "sex": {"m", "f"},
    "mysex": {"m", "f"},
    "kin": {True, False},
    "heavy": {True, False},
    "fight": {True, False},
    "hurt": {True, False},
    "many": {True, False},
    "foe": {True, False},
}
BUFF_ONLY = {"fight", "many"}


def emote_tokens() -> set[str]:
    text = (ROOT / "addons" / "Bastians_Gestures" / "Model.lua").read_text(encoding="utf-8")
    return set(re.findall(r'\{ "([A-Z]+)", "', text))


def load_chunk(path: Path) -> dict:
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(
        """
        ANYONE = { "buff", "rez", "emote", "invite", "duel", "trade", "camp" }
        DEEDS = { "buff", "rez", "camp", "trade.gift", "invite.accepted" }
        EVERYWHERE = { "buff", "rez", "emote", "invite", "duel", "trade", "camp", "ambient" }
        """
    )
    chunk = lua.globals().loadstring(path.read_text(encoding="utf-8"), f"@{path.name}")
    if isinstance(chunk, tuple):
        raise SystemExit(f"{path}: does not load: {chunk[1]}")
    data = chunk()

    def py(value):
        if lua.globals().type(value) == "table":
            keys = list(value.keys())
            if (
                keys
                and all(isinstance(k, int) for k in keys)
                and keys == list(range(1, len(keys) + 1))
            ):
                return [py(value[k]) for k in keys]
            return {k: py(v) for k, v in value.items()}
        return value

    out = py(data) or {}
    for kind, parts in out.items():
        if isinstance(parts, list):
            out[kind] = [
                {i + 1: v for i, v in enumerate(part)} if isinstance(part, list) else part
                for part in parts
            ]
    return out


def situations(part) -> list[str]:
    s = part.get(1) if isinstance(part, dict) else part[0]
    return s if isinstance(s, list) else [s]


def serves(row_of_part: str, row: str) -> bool:
    return row == row_of_part or row.startswith(row_of_part + ".")


DEEDS = ("buff", "rez", "camp", "trade.gift", "invite.accepted")
SLOTS = {"enUS": set("twnk"), "deDE": set("twnk")}
THANKS = {"enUS": re.compile(r"thank", re.I), "deDE": re.compile(r"dank", re.I)}
PATTERN_MAX = 140  # Voice.PATTERN_MAX: bytes of the longest variant's text and act
SENTENCES_MAX = 2
CELL_MIN = 4  # patterns a cell has of its own row
ENUMERATE_MAX = 3000  # variants checked one by one; above, a sample of SAMPLE
SAMPLE = 600
# German: the old courtly register (ADR 0089: du, always) and what a chat types, not a voice says
STILTED = {
    "deDE": [
        r"\bSeid\b",
        r"\bHabt\b",
        r"\b(?:Euch|Euer|Eure[mnrs]?)\b",
        r"\bIhnen\b",
        r"\bwohlan\b",
        r"\bverbindlich",
        r"\bergebenst",
        r"\bVerehrung\b",
        r"\bGestattet\b",
        r"\bgedenken\b",
        r"\bvergolten\b",
    ],
    # English: the same register the old set had (22.11.2026, "Much obliged, sir")
    "enUS": [
        r"\bthee\b",
        r"\bthou\b",
        r"\bthy\b",
        r"\bwell met\b",
        r"\bobliged\b",
        r"\bmy lady\b",
        r"\bsir\b",
        r"\bmadam\b",
        r"\blass\b",
        r"\blad\b",
        r"\bprithee\b",
        r"\bverily\b",
        r"\bmay the\b",
        r"\bfreely given\b",
    ],
}
TYPED = [r"[:;]-?[()DPp]", r"\bxD\b", r"\blol\b", r"\bthx\b", r"\bty\b"]
ALLOWED_CHARS = {
    "deDE": re.compile(r"^[\x20-\x7eäöüÄÖÜß]*$"),
    "enUS": re.compile(r"^[\x20-\x7e]*$"),
}
NAMED = {
    ("buff", "rez", "emote", "invite", "duel", "trade", "camp"): "ANYONE",
    ("buff", "rez", "camp", "trade.gift", "invite.accepted"): "DEEDS",
    ("buff", "rez", "emote", "invite", "duel", "trade", "camp", "ambient"): "EVERYWHERE",
}
# conditions the whole pack carries at least so often (a moment that names them is heard)
NEEDS = (
    [
        ("weather", "rain", 12),
        ("weather", "snow", 8),
        ("weather", "sandstorm", 6),
        ("fight", True, 8),
        ("many", True, 4),
        ("hurt", True, 8),
        ("foe", True, 8),
        ("kin", True, 4),
    ]
    + [("time", t, 6) for t in sorted(VALUES["time"])]
    + [("land", land, 3) for land in sorted(VALUES["land"])]
)


def parse(text: str) -> list | None:
    """The pieces of a text: a str is said as it stands, a list a group's choices. None when a
    brace does not close, a group holds another, or | or } stands outside a group."""
    out: list = []
    at = 0
    while True:
        start = text.find("{", at)
        if start < 0:
            rest = text[at:]
            return None if re.search(r"[|}]", rest) else [*out, rest]
        close = text.find("}", start + 1)
        lit = text[at:start]
        if close < 0 or re.search(r"[|}]", lit):
            return None
        inner = text[start + 1 : close]
        if "{" in inner:
            return None
        out += [lit, inner.split("|")]
        at = close + 1


def tidy(text: str, capitals: bool) -> str:
    text = re.sub(r"\s+", " ", text).strip()
    text = re.sub(r" ([,.!?])", r"\1", text)
    if capitals:
        text = text.replace("...", "\x01")
        text = re.sub(r"^([a-zäöü])", lambda m: m.group(1).upper(), text)
        text = re.sub(r"([.!?] )([a-zäöü])", lambda m: m.group(1) + m.group(2).upper(), text)
        text = text.replace("\x01", "...")
    return text


def variants(text: str | None, capitals: bool, rand: random.Random) -> list[str]:
    if not text:
        return [""]
    pieces = parse(text)
    if pieces is None:
        return []
    groups = [p if isinstance(p, list) else [p] for p in pieces]
    total = 1
    for g in groups:
        total *= len(g)
    if total <= ENUMERATE_MAX:
        combos = itertools.product(*groups)
    else:
        combos = (tuple(rand.choice(g) for g in groups) for _ in range(SAMPLE))
    return sorted({tidy("".join(c), capitals) for c in combos})


def count_variants(text: str | None) -> int:
    pieces = parse(text or "") or []
    n = 1
    for p in pieces:
        if isinstance(p, list):
            n *= len(p)
    return n


def sentences(text: str) -> int:
    """Sentences of two words or more: a word added after them ("Fast.", "Halbwegs.") is heard as
    part of the one before."""
    body = text.replace("...", "\x01")
    said = [s for s in re.split(r"(?<=[.!?])\s+", body) if s.strip()]
    return max(1, sum(1 for s in said if len(s.split()) > 1))


def name_optional(text: str) -> bool:
    """%t only in a group with a choice that does without it, and never outside a group."""
    pieces = parse(text) or []
    for p in pieces:
        if isinstance(p, str) and "%t" in p:
            return False
        if isinstance(p, list) and any("%t" in c for c in p) and all("%t" in c for c in p):
            return False
    return True


def rows_of(line: dict) -> list[str]:
    s = line.get(1)
    return s if isinstance(s, list) else [s]


def is_deed(rows: list[str]) -> bool:
    """A line heard after a deed: its row is one, lies below one, or holds one below it. Sitting
    down by a fire (camp.greet) greets the company; nobody did anything yet."""
    return any((serves(d, r) or serves(r, d)) and r != "camp.greet" for r in rows for d in DEEDS)


def check(lines: list[dict], lang: str) -> list[str]:
    problems: list[str] = []
    tokens = emote_tokens()
    seen: set[str] = set()
    rand = random.Random(89)
    stilted = [re.compile(p, re.I if lang == "enUS" else 0) for p in STILTED[lang]]
    typed = [re.compile(p, re.I) for p in TYPED]
    for i, line in enumerate(lines, 1):
        if not isinstance(line, dict):
            problems.append(f"lines[{i}]: not a table")
            continue
        rows, mood, text = rows_of(line), line.get(2), line.get(3)
        act, when = line.get("act"), line.get("when") or {}
        where = f"lines[{i}] {text!r}"
        for row in rows:
            if not isinstance(row, str) or not (row in ROWS or row in ROOTS):
                problems.append(f"{where}: unknown situation {row!r}")
        if mood not in MOODS:
            problems.append(f"{where}: unknown mood {mood!r}")
        if not isinstance(text, str) or not text.strip():
            problems.append(f"{where}: needs a text: a line is said")
            continue
        if text in seen:
            problems.append(f"{where}: written twice")
        seen.add(text)
        if parse(text) is None or (act and parse(act) is None):
            problems.append(f"{where}: a {{ choice | group }} does not close or nests")
            continue
        whole = text + (act or "")
        slots = re.findall(r"%(\w)", whole)
        for slot in slots:
            if slot not in SLOTS[lang]:
                allowed = sorted(SLOTS[lang])
                problems.append(f"{where}: slot %{slot} is not allowed (ADR 0089: {allowed})")
        if "t" in slots and not name_optional(text):
            problems.append(f"{where}: the name only sometimes: %t in a group with an empty choice")
        if rows == ["ambient"] and "t" in slots:
            problems.append(f"{where}: an ambient line has nobody to name")
        for key, value in when.items():
            if key not in VALUES:
                problems.append(f"{where}: unknown condition {key!r}")
                continue
            for want in value if isinstance(value, list) else [value]:
                if want not in VALUES[key]:
                    problems.append(f"{where}: {key} = {want!r} does not exist")
            if key in BUFF_ONLY and not all(r.startswith("buff") for r in rows):
                problems.append(f"{where}: {key} is known on a buff only")
            if key == "foe" and not all(r.startswith("emote") for r in rows):
                # the other faction can wave at me; it cannot resurrect, duel, invite or trade
                problems.append(f"{where}: foe is heard on an emote only")
        if line.get("emote") and line["emote"] not in tokens:
            problems.append(f"{where}: unknown emote {line['emote']!r}")
        deed = is_deed(rows)
        acts = variants(act, False, rand) if act else [""]
        for said in variants(text, True, rand):
            if said.count("%t") > 1:
                problems.append(f"{where}: {said!r} names twice")
            n = sentences(said)
            if n > SENTENCES_MAX:
                problems.append(f"{where}: {said!r} has {n} sentences, at most {SENTENCES_MAX}")
            if said[-1:] not in ".!?":
                problems.append(f"{where}: {said!r} does not end like a sentence")
            longest = len(said.encode("utf-8")) + max(len(a.encode("utf-8")) for a in acts)
            if longest > PATTERN_MAX:
                problems.append(f"{where}: {said!r} {longest} bytes, at most {PATTERN_MAX}")
            if deed and not THANKS[lang].search(said):
                problems.append(f"{where}: {said!r} does not thank, and its row is a deed")
            if not ALLOWED_CHARS[lang].match(said):
                problems.append(f"{where}: {said!r} has a sign the game's fonts may lack")
            for rule in stilted:
                if rule.search(said):
                    problems.append(f"{where}: {said!r} stilted ({rule.pattern})")
            for rule in typed:
                if rule.search(said):
                    problems.append(f"{where}: {said!r} typed, not spoken ({rule.pattern})")
            if "  " in said or " ," in said:
                problems.append(f"{where}: {said!r} spaces")
    return problems


def plain(line: dict) -> bool:
    """Needs nothing but a name it can also do without: no condition, slots only %t and %n."""
    whole = (line.get(3) or "") + (line.get("act") or "")
    return not line.get("when") and set(re.findall(r"%(\w)", whole)) <= {"t", "n"}


def thin(lines: list[dict], mood: str | None = None) -> list[str]:
    out = []
    for row in ROWS:
        for m in MOODS if mood is None else (mood,):
            own = [x for x in lines if x.get(2) == m and row in rows_of(x)]
            if len(own) < CELL_MIN:
                out.append(f"{row} {m}: {len(own)} of {CELL_MIN} of its own row")
            elif not any(plain(x) for x in own):
                out.append(f"{row} {m}: none that needs no fact")
    if mood is None:
        counts: Counter = Counter()
        for x in lines:
            for key, value in (x.get("when") or {}).items():
                for want in value if isinstance(value, list) else [value]:
                    counts[(key, want)] += 1
        for key, value, n in NEEDS:
            if counts[(key, value)] < n:
                out.append(f"condition {key}={value}: {counts[(key, value)]} of {n}")
    return out


def load(path: Path) -> list[dict]:
    data = load_chunk(path)
    return data.get("lines") or []


def lua_line(line: dict) -> str:
    def value(v):
        if isinstance(v, bool):
            return "true" if v else "false"
        if isinstance(v, list):
            return "{ " + ", ".join(value(x) for x in v) + " }"
        return '"' + str(v).replace("\\", "\\\\").replace('"', '\\"') + '"'

    rows = line[1]
    where = NAMED.get(tuple(rows)) if isinstance(rows, list) else None
    fields = [where or value(rows), value(line[2]), value(line[3])]
    when = line.get("when")
    if when:
        inner = ", ".join(f"{k} = {value(when[k])}" for k in sorted(when))
        fields.append("when = { " + inner + " }")
    for key in ("act", "emote"):
        if line.get(key):
            fields.append(f"{key} = {value(line[key])}")
    return "    { " + ", ".join(fields) + " },"


def write(lines: list[dict], lang: str) -> Path:
    target = ROOT / "addons" / "Bastians_Courtesy" / f"Lines_{lang}.lua"
    text = target.read_text(encoding="utf-8")
    head, rest = text.split("-- LINES BEGIN", 1)
    _, tail = rest.split("-- LINES END", 1)
    order = {m: i for i, m in enumerate(MOODS)}
    rank = {r: i for i, r in enumerate(ROWS)}

    def key(x):
        first = rows_of(x)[0]
        return (rank.get(first, -1), order.get(x[2], 9))

    body = ["-- LINES BEGIN", "  lines = {"]
    body += [lua_line(x) for x in sorted(lines, key=key)]
    body += ["  },", "-- LINES END"]
    tmp = target.with_suffix(".tmp")
    tmp.write_text(head + "\n".join(body) + tail, encoding="utf-8", newline="\n")
    tmp.replace(target)
    return target


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("fragments", nargs="+", type=Path)
    p.add_argument("--lang", choices=sorted(SLOTS), required=True)
    p.add_argument("--mood", choices=MOODS)
    p.add_argument("--write", action="store_true")
    args = p.parse_args(argv)
    lines = [x for path in args.fragments for x in load(path)]
    problems = check(lines, args.lang)
    gaps = thin(lines, args.mood)
    for line in problems:
        print("PROBLEM", line)
    for line in gaps:
        print("THIN", line)
    total = sum(count_variants(x.get(3)) for x in lines)
    print(f"{len(lines)} patterns, {total} variants, {len(problems)} problems, {len(gaps)} thin")
    if problems or gaps:
        return 1
    if args.write:
        print("written:", write(lines, args.lang).name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
