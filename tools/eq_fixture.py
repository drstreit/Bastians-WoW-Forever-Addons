"""Trim an installed Everything Quests folder to a fixture with a few quests, in the real format.

Usage: python tools/eq_fixture.py <EverythingQuests folder> <fixture folder> [--quests 6,7,62]

Each Data/*_Forever.lua (and QuestHolidays_Classic.lua) keeps its header comments verbatim and only
the entries of the chosen quests (sources keep the creatures and objects those quests reference), so
the reader is tested against the exact format it meets in the wild. Deterministic output.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "pipeline"))

from bastians_build.emit import lua_value  # noqa: E402
from bastians_build.files import write_text  # noqa: E402
from bastians_build.sources.everything_quests import FILES, TABLES  # noqa: E402
from bastians_build.sources.luatable import eval_long_string, new_runtime, run_file, to_python  # noqa: E402

DEFAULT_QUESTS = (6, 7, 62, 76, 176)


def header(text: str) -> str:
    """Everything before the first `ns.` assignment: the varargs line and the header comments."""
    lines = []
    for line in text.splitlines():
        if line.startswith("ns."):
            break
        lines.append(line)
    return "\n".join(lines).rstrip() + "\n"


def keep(table: dict, quests: set[int]) -> dict:
    return {k: v for k, v in table.items() if k in quests}


def referenced_sources(
    available: dict, turn_in: dict, quests: set[int]
) -> tuple[set[int], set[int]]:
    npcs, objs = set(), set()
    for table in (available.get("start") or {}, turn_in or {}):
        for quest_id, by_map in table.items():
            if quest_id not in quests:
                continue
            for packed_list in by_map.values():
                for packed in packed_list:
                    source_id = packed // 1_000_000_000
                    kind = (packed // 100_000_000) % 10
                    if kind > 4:
                        kind -= 4
                    if source_id:
                        (npcs if kind == 1 else objs).add(source_id)
    return npcs, objs


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("addon", type=Path)
    parser.add_argument("fixture", type=Path)
    parser.add_argument("--quests", default=",".join(map(str, DEFAULT_QUESTS)))
    parser.add_argument("--flavor", default="Forever")
    args = parser.parse_args(argv)
    quests = {int(q) for q in args.quests.split(",")}
    data = args.addon / "Data"
    out = args.fixture / "Data"
    texts: dict[str, str] = {}
    tables: dict[str, dict] = {}
    for key, pattern in FILES.items():
        path = data / pattern.format(f=args.flavor)
        texts[key] = path.read_text(encoding="utf-8-sig")
        lua = new_runtime()
        ns = run_file(lua, path)
        if key == "spawns":
            tables[key] = to_python(eval_long_string(lua, ns.CLASSIC_QUEST_SPAWNS_SRC))
        else:
            tables[key] = to_python(ns[TABLES[key]])
    available = tables["available"]
    trimmed_available = {k: keep(v, quests) for k, v in available.items()}
    npcs, objs = referenced_sources(available, tables["turn_in"], quests)
    sources = tables["sources"]
    trimmed = {
        "available": trimmed_available,
        "turn_in": keep(tables["turn_in"], quests),
        "coords": keep(tables["coords"], quests),
        "sources": {
            "npc": keep(sources.get("npc", {}), npcs),
            "obj": keep(sources.get("obj", {}), objs),
        },
        "npcs": keep(tables["npcs"], quests),
        "categories": keep(tables["categories"], quests),
        "spawns": keep(tables["spawns"], quests),
    }
    for key, pattern in FILES.items():
        name = pattern.format(f=args.flavor)
        body = header(texts[key])
        if key == "spawns":
            body += "ns.HAS_CLASSIC_SPAWNS = true\n"
            body += "ns.CLASSIC_QUEST_SPAWNS_SRC = [==[return " + lua_value(trimmed[key]) + "]==]\n"
        else:
            body += f"ns.{TABLES[key]} = " + lua_value(trimmed[key]) + "\n"
        write_text(out / name, body)
    holidays = data / "QuestHolidays_Classic.lua"
    if holidays.is_file():
        lua = new_runtime()
        ns = run_file(lua, holidays)
        names = to_python(ns.EQ_HOLIDAY_NAMES)
        events = to_python(ns.CLASSIC_QUEST_HOLIDAY)
        body = header(holidays.read_text(encoding="utf-8-sig"))
        body += "ns.EQ_HOLIDAY_NAMES = " + lua_value(names) + "\n"
        body += (
            "ns.CLASSIC_QUEST_HOLIDAY = "
            + lua_value({k: keep(v, quests) for k, v in events.items()})
            + "\n"
        )
        write_text(out / "QuestHolidays_Classic.lua", body)
    for toc in sorted(args.addon.glob("*.toc")):
        lines = [
            line
            for line in toc.read_text(encoding="utf-8-sig").splitlines()
            if line.startswith("## ")
        ]
        write_text(args.fixture / toc.name, "\n".join(lines) + "\n")
        break
    print(f"fixture written to {args.fixture} for quests {sorted(quests)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
