"""Questie (GPL-3.0): the quests it hides on Forever (ADR 0051).

``Database/Corrections/QuestieQuestBlacklist.lua`` holds them as Lua: ``:Load()`` builds the table
of hidden quests from expressions such as ``Expansions.Current >= Expansions.Cata``, and the module
keeps ``InvasionQuests`` and ``AQWarEffortQuests`` beside it. Running the file on the sandbox with
Forever's values is the exact reading: on Forever ``Expansions.Current`` is ``Era``
(``Modules/Expansions.lua``) and ``ContentPhases.IsInvasionActive`` decides the invasion.

Only a value of ``true`` hides a quest for good; ``HIDE_ON_MAP`` rows are quests that exist. Event
quests sit in that table too (Children's Week 171, 172): Questie un-hides them while the event runs,
so ``Holidays/quests/*.lua`` says which ones they are.
Checked 05.11.2026 on Questie 12.6.0.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

from lupa import lua51

from . import luatable

BLACKLIST = Path("Database") / "Corrections" / "QuestieQuestBlacklist.lua"
PHASES = Path("Database") / "Corrections" / "ContentPhases" / "ContentPhases.lua"
EVENTS = Path("Database") / "Corrections" / "Holidays" / "quests"
TOC = "Questie_Forever.toc"

_VERSION = re.compile(r"^## Version:\s*(\S+)", re.M)
_EVENT = re.compile(r'tinsert\(eventQuests,\s*\{\s*"([^"]+)",\s*(\d+)')

# What the two files touch: Forever's flavour, and CreateModule beside the sandbox's ImportModule.
FOREVER = """
Questie = { IsForever = true, IsClassic = true }
Expansions = { Era = 1, Tbc = 2, Wotlk = 3, Cata = 4, MoP = 5, Current = 1 }
QuestieLoader.CreateModule = QuestieLoader.ImportModule
"""


@dataclass(frozen=True)
class QuestGates:
    absent: frozenset[int]  # not in the game on Forever
    dormant: frozenset[int]  # a one-time world event that does not run
    events: dict[int, str]  # quest -> the yearly world event it belongs to
    version: str | None


def _ids(table) -> frozenset[int]:
    """The keys of a Lua table whose value is exactly ``true``."""
    return frozenset(int(k) for k in table if table[k] is True)


def read_events(folder: Path) -> dict[int, str]:
    """Quest -> event name from the ``tinsert(eventQuests, {"Name", id, ...})`` rows."""
    out: dict[int, str] = {}
    for path in sorted(folder.glob("*.lua")):
        for name, quest_id in _EVENT.findall(path.read_text(encoding="utf-8-sig")):
            out.setdefault(int(quest_id), name)
    return out


def read_quest_gates(addon: Path) -> QuestGates:
    """The quests Questie hides on Forever, from the addon's folder."""
    lua = luatable.new_runtime()
    lua.execute(FOREVER)
    for rel in (PHASES, BLACKLIST):
        luatable.run_file(lua, addon / rel, "Questie")
    g = lua.globals()
    try:
        absent = _ids(g.QuestieQuestBlacklist.Load(g.QuestieQuestBlacklist))
    except lua51.LuaError as exc:
        raise luatable.LuaDataError(f"{BLACKLIST.name}: {exc}") from exc
    dormant = set(_ids(g.QuestieQuestBlacklist.AQWarEffortQuests))
    if not g.ContentPhases.IsInvasionActive[g.Expansions.Current]:
        dormant |= _ids(g.QuestieQuestBlacklist.InvasionQuests)
    toc = addon / TOC
    found = _VERSION.search(toc.read_text(encoding="utf-8-sig")) if toc.is_file() else None
    return QuestGates(
        absent, frozenset(dormant), read_events(addon / EVENTS), found.group(1) if found else None
    )
