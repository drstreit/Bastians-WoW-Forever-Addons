"""TrinityCore TDB's locale tables: the retail game data in other languages (data.md "Game data in
other languages", ADR 0033). One pass over the dump reads, for every language of ours, the
creatures' name and title, the objects' name and the quests' title. GPL-2.0 or later like the rest
of TDB (sources.md).

Only names: the retail packs carry no English quest texts (the client shows its own quest log), so
the local details, offer and progress texts TDB has would lie over nothing; measured 29.10.2026
they made each retail language pack 16 to 19 MB.
"""

from __future__ import annotations

from pathlib import Path

from bastians_build.sources.cmangos import read_lines

WANTED: dict[str, tuple[str, ...]] = {
    "creature_template_locale": ("entry", "locale", "Name", "Title"),
    "gameobject_template_locale": ("entry", "locale", "name"),
    "quest_template_locale": ("ID", "locale", "LogTitle"),
}
# table -> (our record type, the id column, { our field: the table's column })
MAP = {
    "creature_template_locale": ("npc", "entry", {"name": "Name", "subname": "Title"}),
    "gameobject_template_locale": ("object", "entry", {"name": "name"}),
    "quest_template_locale": ("quest", "ID", {"name": "LogTitle"}),
}


def read_locales(sql: Path, locales: tuple[str, ...]) -> dict[str, dict[str, dict[int, dict]]]:
    """{ locale: { record type: { id: fields } } } for the given locales (esMX is read as esES only
    where esES has nothing: one Spanish)."""
    with sql.open(encoding="utf-8", errors="replace") as fh:
        tables = read_lines(fh, WANTED)
    out: dict[str, dict[str, dict[int, dict]]] = {loc: {} for loc in locales}
    for table, rows in tables.items():
        record_type, id_col, fields = MAP[table]
        for row in rows:
            locale = row.get("locale")
            if locale == "esMX" and "esES" in locales:
                locale, fallback = "esES", True
            else:
                fallback = False
            if locale not in out or not isinstance(row.get(id_col), int):
                continue
            rec = {
                f: row[c] for f, c in fields.items() if isinstance(row[c], str) and row[c].strip()
            }
            if not rec:
                continue
            target = out[locale].setdefault(record_type, {}).setdefault(row[id_col], {})
            for key, value in rec.items():
                if not (fallback and key in target):
                    target[key] = value
    return out
