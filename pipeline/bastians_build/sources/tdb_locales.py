"""TrinityCore TDB's locale tables: the retail game data in other languages (data.md "Game data in
other languages", ADR 0033). One pass over the dump reads, for every language of ours, the
creatures' name and title, the objects' name and the quests' title. GPL-2.0 or later like the rest
of TDB (sources.md).

Only names: the retail packs carry no English quest texts (the client shows its own quest log), so
the local details, offer and progress texts TDB has would lie over nothing; measured 29.10.2026
they made each retail language pack 16 to 19 MB.

Forever: ``read_quest_texts`` gives the long
quest texts of the languages CMaNGOS lacks, but only where TDB's English text is word for word the
English one our text pack carries (most old quests kept their text into retail; one rewritten in
Cataclysm keeps its English). Measured 02.11.2026 against CMaNGOS z2815: 82 to 92 % of the texts
are the same; TDB then has Korean details and objectives (no Korean offer or progress texts) and
Traditional Chinese for all four. Owner, the same day ("finish all the text pipelines for all
pending languages"): French, Spanish (esMX where esES has none) and German too; the Latin
languages' typography goes to Latin-1 (the game fonts, as QuestieDB's l10n reader keeps it).
"""

from __future__ import annotations

import re
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


# the long quest texts: table -> (the id column, { our field: the table's column }); the English
# in the plain tables, every language's in the _locale ones
TEXT_TABLES = {
    "quest_template": {"objectives": "LogDescription", "details": "QuestDescription"},
    "quest_offer_reward": {"offer": "RewardText"},
    "quest_request_items": {"progress": "CompletionText"},
}
_TOKEN = re.compile(r"\$([A-Za-z])")
LATIN1_LOCALES = frozenset({"deDE", "frFR", "esES"})
# TDB's typography in the Latin languages (measured 02.11.2026: French writes 121,462 typographic
# apostrophes, 3,799 oe ligatures) -> Latin-1, which the game fonts draw
_LATIN1 = str.maketrans(
    {
        "\u2018": "'",
        "\u2019": "'",
        "\u201c": '"',
        "\u201d": '"',
        "\u2026": "...",
        "\u2013": "-",
        "\u2014": "-",
        "\u2015": "-",
        "\u2009": " ",
        "\u0153": "oe",
        "\u0152": "OE",
    }
)


def to_latin1(text: str) -> str | None:
    """A Latin language's text in Latin-1, or None when a character is left the fonts lack."""
    text = text.translate(_LATIN1)
    return text if all(ord(c) < 256 for c in text) else None


def same_text(a: object, b: object) -> bool:
    """One text in two dumps: the case of a $N or $B token and the spacing may differ."""
    if not (isinstance(a, str) and isinstance(b, str)):
        return False

    def norm(s: str) -> str:
        return " ".join(_TOKEN.sub(lambda m: "$" + m.group(1).upper(), s).split())

    return bool(norm(a)) and norm(a) == norm(b)


def read_quest_texts(
    sql: Path, locales: tuple[str, ...], english: dict[int, dict]
) -> dict[str, dict[int, dict[str, str]]]:
    """{ locale: { quest id: { details, objectives, offer, progress } } }: a language's text only
    where TDB's English of that field is ours (`english`: { quest id: our English fields })."""
    wanted: dict[str, tuple[str, ...]] = {}
    for table, fields in TEXT_TABLES.items():
        wanted[table] = ("ID", *fields.values())
        wanted[f"{table}_locale"] = ("ID", "locale", *fields.values())
    with sql.open(encoding="utf-8", errors="replace") as fh:
        tables = read_lines(fh, wanted)
    same: dict[int, set[str]] = {}  # quest id -> our fields whose English TDB has
    for table, fields in TEXT_TABLES.items():
        for row in tables[table]:
            ours = english.get(row["ID"])
            if not ours:
                continue
            for field, col in fields.items():
                if same_text(row[col], ours.get(field)):
                    same.setdefault(row["ID"], set()).add(field)
    out: dict[str, dict[int, dict[str, str]]] = {loc: {} for loc in locales}
    mexican: dict[int, dict[str, str]] = {}  # esMX, for what esES lacks (one Spanish)
    for table, fields in TEXT_TABLES.items():
        for row in tables[f"{table}_locale"]:
            locale, quest = row["locale"], row["ID"]
            if locale == "esMX" and "esES" in out:
                target = mexican
            elif locale in out:
                target = out[locale]
            else:
                continue
            if quest not in same:
                continue
            for field, col in fields.items():
                value = row[col]
                if not (field in same[quest] and isinstance(value, str) and value.strip()):
                    continue
                if locale in LATIN1_LOCALES or locale == "esMX":
                    value = to_latin1(value)
                if value:
                    target.setdefault(quest, {})[field] = value
    for quest, fields in mexican.items():
        out["esES"][quest] = {**fields, **out["esES"].get(quest, {})}
    return {loc: by_id for loc, by_id in out.items() if by_id}
