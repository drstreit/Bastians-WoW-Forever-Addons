"""QuestieDB's l10n lookups: the game data in other languages (data.md "Game data in other
languages", ADR 0033).

Layout (fetched by tools/fetch_questie_l10n.py from QuestieDB's ``l10n/Forever``):
``<root>/<locale>/lookup{Quests,Npcs,Items,Objects}.lua`` and the same under
``<root>/<locale>/traces/`` (names captured on the Forever client, read after the base set and
winning over it). Each file sets ``l10n.<lookup>[<locale>] = loadstring([[return { ... }]])``
behind a ``GetLocale()`` guard. Values: a quest ``{title, {objective lines}}``, an NPC
``{name, subname}``, an item or object a name. In the Latin languages a value with a character
outside Latin-1 is dropped (the traces carry stray Chinese names; those clients' fonts cannot draw
them), so the English name stays; the Asian clients bring fonts for every script.
"""

from __future__ import annotations

from pathlib import Path

from bastians_build.sources.luatable import LuaDataError, new_runtime, run_file, to_python

LOCALES = ("deDE", "frFR", "esES", "koKR", "zhCN", "zhTW")
LATIN1_LOCALES = frozenset({"deDE", "frFR", "esES"})
# our record type -> (file name, the l10n table the file fills)
LOOKUPS = {
    "quest": ("lookupQuests.lua", "questLookup"),
    "npc": ("lookupNpcs.lua", "npcNameLookup"),
    "item": ("lookupItems.lua", "itemLookup"),
    "object": ("lookupObjects.lua", "objectLookup"),
}


def _drawable(text: str, locale: str) -> bool:
    return locale not in LATIN1_LOCALES or all(ord(c) < 256 for c in text)


def _read_file(path: Path, locale: str, table: str) -> dict:
    lua = new_runtime()
    g = lua.globals()
    g.GetLocale = lua.eval(f'function() return "{locale}" end')
    g.l10n = lua.eval(
        "{ questLookup = {}, npcNameLookup = {}, itemLookup = {}, objectLookup = {}, private = {} }"
    )
    run_file(lua, path, "QuestieDB")
    loader = g.l10n[table][locale]
    if loader is None:
        raise LuaDataError(f"{path.name}: sets no {table}[{locale!r}]")
    data = loader() if callable(loader) else loader
    return to_python(data) or {}


def _slot(value, i: int):
    """Slot i (1-based) of a Lua array that may have holes (a dict then) or be short."""
    if isinstance(value, list):
        return value[i - 1] if len(value) >= i else None
    if isinstance(value, dict):
        return value.get(i)
    return None


def _record(record_type: str, value, locale: str) -> dict | None:
    """A lookup value -> our fields, or None when it carries nothing usable."""

    def text(v) -> str | None:
        return v if isinstance(v, str) and v and _drawable(v, locale) else None

    if record_type == "quest":
        raw = _slot(value, 2)
        if isinstance(raw, dict):
            raw = [raw[k] for k in sorted(k for k in raw if isinstance(k, int))]
        lines = [x for x in raw if text(x)] if isinstance(raw, list) else []
        rec = {"name": text(_slot(value, 1)), "objectives": "\n".join(lines) or None}
    elif record_type == "npc":
        rec = {"name": text(_slot(value, 1)), "subname": text(_slot(value, 2))}
    else:
        rec = {"name": text(value)}
    return rec if any(v is not None for v in rec.values()) else None


def read_locale(root: Path, locale: str) -> dict[str, dict[int, dict]]:
    """One locale's lookups: { record type: { id: fields } }; a missing file is an empty type."""
    out: dict[str, dict[int, dict]] = {}
    for record_type, (file_name, table) in LOOKUPS.items():
        rows: dict[int, dict] = {}
        for path in (root / locale / file_name, root / locale / "traces" / file_name):
            if not path.is_file():
                continue
            for key, value in _read_file(path, locale, table).items():
                rec = _record(record_type, value, locale)
                if rec is not None and isinstance(key, int):
                    merged = dict(rows.get(key, {}))
                    merged.update({k: v for k, v in rec.items() if v is not None})
                    rows[key] = merged
        out[record_type] = rows
    return out


def source_commit(root: Path) -> str | None:
    """The QuestieDB commit the files came from (tools/fetch_questie_l10n.py writes COMMIT)."""
    path = root / "COMMIT"
    return path.read_text(encoding="utf-8").strip() or None if path.is_file() else None
