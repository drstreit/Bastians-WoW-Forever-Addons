"""The game data in other languages (data.md "Game data in other languages", ADR 0033): the local
names and texts of the records our packs carry, as `<type>_<locale>` records for the packs
`text_<locale>`. Forever: QuestieDB's l10n lookups give the names, a quest's title and objectives;
CMaNGOS' quest locales (German, Simplified Chinese) add the details, offer and progress texts and
win for the objectives, which then match the English text pack's (both CMaNGOS). Retail: TDB's
locale tables give the creatures, objects and quests in every language. Forever's languages also
take TDB's long quest texts where its English is ours (TDB_TEXT_LOCALES; they fill only what
QuestieDB and CMaNGOS lack). Both: the client's own tables in every installed text language name
the items and win over the others (ADR 0035)."""

from __future__ import annotations

from pathlib import Path

from bastians_build.model import World
from bastians_build.sources.cmangos_locales import read_quest_texts
from bastians_build.sources.questiedb_l10n import LOCALES, read_locale, source_commit
from bastians_build.sources.tdb_locales import LATIN1_LOCALES, read_locales, to_latin1
from bastians_build.sources.tdb_locales import read_quest_texts as read_tdb_texts

# the languages that take TDB's long quest texts on Forever (the Asian ones,
# then "all pending languages"); each fills only what QuestieDB and CMaNGOS lack
TDB_TEXT_LOCALES = LOCALES


def _latin1(value: object) -> object:
    """A client name in a Latin language with its typography in Latin-1 (`to_latin1`); a name
    with another character stays the client's own."""
    return (to_latin1(value) or value) if isinstance(value, str) else value


def _merge(rows: dict[str, dict[int, dict]], extra: dict[str, dict[int, dict]]) -> None:
    """Extra fields over the lookups' rows; a name the lookups have stays."""
    for record_type, by_id in extra.items():
        target = rows.setdefault(record_type, {})
        for record_id, fields in by_id.items():
            rec = dict(target.get(record_id, {}))
            for key, value in fields.items():
                if key != "name" or "name" not in rec:
                    rec[key] = value
            target[record_id] = rec


def add_l10n(
    world: World,
    root: Path | None,
    cmangos: Path | None = None,
    tdb: Path | None = None,
    client_names: dict[str, dict[str, dict[int, dict]]] | None = None,
    tdb_texts: Path | None = None,
) -> dict[str, int]:
    """Adds every locale that has data; returns the records added per locale."""
    added: dict[str, int] = {}
    used_cmangos = False
    retail = read_locales(tdb, LOCALES) if tdb else {}
    english = world.records.get("questText", {})
    long_texts = read_tdb_texts(tdb_texts, TDB_TEXT_LOCALES, english) if tdb_texts else {}
    for locale in LOCALES:
        rows = read_locale(root, locale) if root and (root / locale).is_dir() else {}
        texts = read_quest_texts(cmangos, locale) if cmangos else {}
        if locale in LATIN1_LOCALES:  # CMaNGOS' German typography to Latin-1 as well
            texts = {q: {k: _latin1(v) for k, v in f.items()} for q, f in texts.items()}
        if texts:
            used_cmangos = True
            _merge(rows, {"quest": texts})
        if retail.get(locale):
            _merge(rows, retail[locale])
        quests = rows.setdefault("quest", {})
        for quest_id, fields in (long_texts.get(locale) or {}).items():
            quests[quest_id] = {**fields, **quests.get(quest_id, {})}  # only what the others lack
        for record_type, by_id in ((client_names or {}).get(locale) or {}).items():
            target = rows.setdefault(record_type, {})
            for record_id, fields in by_id.items():  # the client's own names win
                if locale in LATIN1_LOCALES:  # its typography too goes to Latin-1 where it can
                    fields = {k: _latin1(v) for k, v in fields.items()}
                target[record_id] = {**target.get(record_id, {}), **fields}
        if not any(rows.values()):
            continue
        n = 0
        for record_type, by_id in rows.items():
            ours = world.records.get(record_type, {})
            for record_id, fields in sorted(by_id.items()):
                if record_id in ours:  # only what our packs carry
                    world.add(f"{record_type}_{locale}", record_id, dict(fields))
                    n += 1
        added[locale] = n
    if added and root:
        commit = source_commit(root)
        world.sources.append(f"QuestieDB l10n {commit[:12]}" if commit else "QuestieDB l10n")
    if added and used_cmangos:
        world.sources.append("CMaNGOS quest locales")
    if added and retail:
        world.sources.append("TDB locales")
    if added and long_texts:
        world.sources.append(f"TDB quest texts ({', '.join(sorted(long_texts))})")
    if added and client_names:
        world.sources.append(f"client names ({', '.join(sorted(client_names))})")
    return added
