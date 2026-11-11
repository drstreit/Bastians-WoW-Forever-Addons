"""Packers: canonical records -> pack tables in format B (data.md), positional by the schema."""

from __future__ import annotations

from bastians_build import __version__, links
from bastians_build.config import PackConfig
from bastians_build.derive import build_index
from bastians_build.model import World

# The pack's shape (data.md "Old and new packs"): 2 since package QD3, `steps`, `edges` and
# `item.ways` beside `objectives` and `spots`. A suite refuses a pack above the shapes it knows
# (Data.lua `Data.SHAPE`); 3 is the day `objectives` and `spots` leave, on the owner's word.
SHAPE = 2


def pack_table(world: World, cfg: PackConfig) -> dict:
    """The table that becomes `Bastians.Data.RegisterPack(name, <table>)`."""
    table: dict[str, object] = {
        "version": __version__,
        "shape": SHAPE,
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
    table["index"] = {name: build_index(world, name) for name in index_names(cfg)}
    # the edge registry's rows for this pack's types (data.md "The edge registry"): the addon's
    # graph reads a link from either end by them
    edges = links.manifest(set(cfg.schema))
    if edges:
        table["edges"] = edges
    return table


def index_names(cfg: PackConfig) -> list[str]:
    """The pack's indexes: those build.toml lists, then the indexes of the edges stored on the
    pack's types (links.py), so a new edge needs no line in the configuration."""
    names = list(cfg.indexes)
    names += [name for name in links.indexes_for(set(cfg.schema)) if name not in names]
    return names


def record_counts(world: World, cfg: PackConfig) -> dict[str, int]:
    return {t: world.count(t) for t in cfg.schema}
