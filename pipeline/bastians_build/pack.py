"""Packers: canonical records -> pack tables in format B (data.md), positional by the schema."""

from __future__ import annotations

from bastians_build import __version__
from bastians_build.config import PackConfig
from bastians_build.derive import build_index
from bastians_build.model import World


def pack_table(world: World, cfg: PackConfig) -> dict:
    """The table that becomes `Bastians.Data.RegisterPack(name, <table>)`."""
    table: dict[str, object] = {
        "version": __version__,
        "build": world.build,
        "client": world.client,
        "sources": list(world.sources),
        "schema": {t: list(fields) for t, fields in cfg.schema.items()},
    }
    names: dict[str, dict[object, str]] = {}
    for record_type, fields in cfg.schema.items():
        rows = {}
        for record_id, rec in sorted(world.records.get(record_type, {}).items()):
            values = [rec.get(f) for f in fields]
            while values and values[-1] is None:
                values.pop()  # trailing nils are the same slots in Lua and cost bytes
            rows[record_id] = values
            if isinstance(rec.get("name"), str):
                names.setdefault(record_type, {})[record_id] = rec["name"]
        table[record_type] = rows
    # names stay plain tables: the search provider reads them without decoding records (format A)
    table["names"] = names
    table["index"] = {name: build_index(world, name) for name in cfg.indexes}
    return table


def record_counts(world: World, cfg: PackConfig) -> dict[str, int]:
    return {t: world.count(t) for t in cfg.schema}
