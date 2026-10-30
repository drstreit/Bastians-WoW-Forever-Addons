"""CMaNGOS classic-db's quest texts in other languages (data.md "Game data in other languages",
ADR 0033): ``<checkout>/locales/German/locales_quest_german.sql`` (every language's columns, the
German ones filled: loc3) and ``<checkout>/locales/Chinese/locales_quest.sql`` (Simplified
Chinese: loc4). They carry what QuestieDB's lookups lack: a quest's details, the offer and the
progress texts, besides the title and the objectives. GPL-3.0 like the rest of CMaNGOS.
"""

from __future__ import annotations

import re
from pathlib import Path

from bastians_build.sources.cmangos import parse_values

# locale -> (file under <checkout>/locales, the locale's column suffix)
FILES = {
    "deDE": ("German/locales_quest_german.sql", 3),
    "zhCN": ("Chinese/locales_quest.sql", 4),
}
# our field -> the column without its _loc<n>
FIELDS = {
    "name": "Title",
    "details": "Details",
    "objectives": "Objectives",
    "offer": "OfferRewardText",
    "progress": "RequestItemsText",
}
_INSERT = re.compile(r"INSERT INTO `locales_quest` (?:\(([^)]*)\) )?VALUES", re.S)
# the table's own column order (Full_DB's CREATE TABLE), for an INSERT without a column list (the
# German file): entry, then each text for loc1 to loc8
_TABLE_COLUMNS = ["entry"] + [
    f"{col}_loc{n}"
    for col in (
        "Title",
        "Details",
        "Objectives",
        "OfferRewardText",
        "RequestItemsText",
        "EndText",
        "ObjectiveText1",
        "ObjectiveText2",
        "ObjectiveText3",
        "ObjectiveText4",
    )
    for n in range(1, 9)
]


def locales_dir(cmangos: Path) -> Path:
    """The checkout's locales folder, from the checkout or from its Full_DB dump file."""
    base = cmangos if cmangos.is_dir() else cmangos.parent.parent
    return base / "locales"


def read_quest_texts(cmangos: Path, locale: str) -> dict[int, dict[str, str]]:
    """{ quest id: { name, details, objectives, offer, progress } } with the empty fields left out;
    empty when the checkout has no file for the locale."""
    spec = FILES.get(locale)
    if not spec:
        return {}
    path = locales_dir(cmangos) / spec[0]
    if not path.is_file():
        return {}
    text = path.read_text(encoding="utf-8", errors="replace")
    suffix = f"_loc{spec[1]}"
    out: dict[int, dict[str, str]] = {}
    matches = list(_INSERT.finditer(text))
    for i, m in enumerate(matches):
        columns = (
            [c.strip().strip("`") for c in m.group(1).split(",")] if m.group(1) else _TABLE_COLUMNS
        )
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        idx = {
            f: columns.index(col + suffix) for f, col in FIELDS.items() if col + suffix in columns
        }
        if "entry" not in columns or not idx:
            continue
        entry = columns.index("entry")
        for row in parse_values(text[m.end() : end]):
            if len(row) != len(columns) or not isinstance(row[entry], int):
                continue
            rec = {f: row[j] for f, j in idx.items() if isinstance(row[j], str) and row[j].strip()}
            if rec:
                out.setdefault(row[entry], {}).update(rec)
    return out
