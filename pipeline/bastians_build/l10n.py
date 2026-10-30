"""The game data in other languages (data.md "Game data in other languages", ADR 0033): the local
names and texts of the records our packs carry, as `<type>_<locale>` records for the packs
`text_<locale>`. Forever: QuestieDB's l10n lookups give the names, a quest's title and objectives;
CMaNGOS' quest locales (German, Simplified Chinese) add the details, offer and progress texts and
win for the objectives, which then match the English text pack's (both CMaNGOS). Retail: TDB's
locale tables give the creatures, objects and quests in every language. Both: the client's own
tables in every installed text language name the items and win over the others (ADR 0035)."""

from __future__ import annotations

from pathlib import Path

from bastians_build.model import World
from bastians_build.sources.cmangos_locales import read_quest_texts
from bastians_build.sources.questiedb_l10n import LOCALES, read_locale, source_commit
from bastians_build.sources.tdb_locales import read_locales


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
) -> dict[str, int]:
    """Adds every locale that has data; returns the records added per locale."""
    added: dict[str, int] = {}
    used_cmangos = False
    retail = read_locales(tdb, LOCALES) if tdb else {}
    for locale in LOCALES:
        rows = read_locale(root, locale) if root and (root / locale).is_dir() else {}
        texts = read_quest_texts(cmangos, locale) if cmangos else {}
        if texts:
            used_cmangos = True
            _merge(rows, {"quest": texts})
        if retail.get(locale):
            _merge(rows, retail[locale])
        for record_type, by_id in ((client_names or {}).get(locale) or {}).items():
            target = rows.setdefault(record_type, {})
            for record_id, fields in by_id.items():  # the client's own names win
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
    if added and client_names:
        world.sources.append(f"client names ({', '.join(sorted(client_names))})")
    return added
