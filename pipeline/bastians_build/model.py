"""The canonical model (data.md): plain records per type, keyed by game ID, plus build metadata.

Unknown values stay ``None`` (CLAUDE.md golden rule 2). Coordinates are map fractions with their
uiMapID and source: a spawn is ``[map, x, y, src]``.
"""

from __future__ import annotations

from dataclasses import dataclass, field

Record = dict[str, object]


@dataclass
class World:
    client: str
    build: str = "unknown"
    sources: list[str] = field(default_factory=list)
    records: dict[str, dict[int, Record]] = field(default_factory=dict)
    notes: list[str] = field(default_factory=list)  # report notes that do not fail a build
    dropped: list[tuple[str, object, str]] = field(default_factory=list)  # (type, id, reason)
    area_to_map: dict[int, int] = field(default_factory=dict)  # AreaTable id -> uiMapID (QuestieDB)
    # filled market -> (source market, label): the Market pack's fills (market.py)
    market_aliases: dict[str, tuple[str, str]] = field(default_factory=dict)

    def add(self, record_type: str, record_id: int, record: Record) -> None:
        self.records.setdefault(record_type, {})[record_id] = record

    def get(self, record_type: str, record_id: int) -> Record | None:
        return self.records.get(record_type, {}).get(record_id)

    def drop(self, record_type: str, record_id: object, reason: str) -> None:
        self.dropped.append((record_type, record_id, reason))

    def count(self, record_type: str) -> int:
        return len(self.records.get(record_type, {}))


def parse_ref(ref: str) -> tuple[str, int | str]:
    """'npc:448' -> ('npc', 448); 'node:herb-2' -> ('node', 'herb-2')."""
    record_type, _, raw_id = ref.partition(":")
    if not record_type or not raw_id:
        raise ValueError(f"not an entity reference: {ref!r}")
    return record_type, int(raw_id) if raw_id.isdigit() else raw_id
