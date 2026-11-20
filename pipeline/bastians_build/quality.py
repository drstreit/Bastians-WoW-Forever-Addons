"""The quality ledger (plan-data-quality.md L1): per kind of record, how many there are, how many
are known, where the known ones come from, and how many the probe saw in play this build.

"Known" is what a player needs of that kind: a place for an NPC or object, a price for an item or
a vendor's row, a cost for a trainer's row, a chance for a drop, a giver and an ender for a quest,
the creatures of a dungeon's bosses, a zone's level band. The sources are the records' own labels
(`client` is the engine; `classic` the Classic debt), counted as they are: nothing is grouped by a
guess. The ledger has no time in it, so the same inputs give the same file
(`quality-<client>.json`, beside the report).
"""

from __future__ import annotations

import re
from collections import Counter

from bastians_build.model import World
from bastians_build.probetruth import ProbeTruth

# items no player can have: the client's own test and placeholder entries, which Forever keeps
# because the pack holds every item the client has (187 "Test" and 48 "Deprecated" on 15.11.2026)
JUNK = re.compile(r"(^(deprecated|old|\[ph\]|ph)\b)|\btest\b|\bunused\b", re.IGNORECASE)


def _row(kind: str, rows: list[tuple[bool, str]], **extra: int) -> dict:
    known = [src for ok, src in rows if ok]
    return {
        "kind": kind,
        "count": len(rows),
        "known": len(known),
        "unknown": len(rows) - len(known),
        "sources": dict(sorted(Counter(known).items())),
        **extra,
    }


def _place_source(rec: dict) -> str:
    spawns = rec.get("spawns") or []
    first = spawns[0] if spawns and isinstance(spawns[0], list) else None
    if first and len(first) > 3 and first[3]:
        return str(first[3])
    return str(rec.get("src") or "?")


def _price_source(row: list) -> str:
    if len(row) > 5 and row[5]:
        return str(row[5])
    return str(row[4]) if len(row) > 4 and row[4] else "?"


def ledger(world: World, truth: ProbeTruth | None = None) -> list[dict]:
    """One row per kind, in a fixed order."""
    r = world.records
    npcs, items = r.get("npc", {}), r.get("item", {})
    rows: list[dict] = []
    seen_npcs = Counter(
        "ok" if t.status == "ok" else "not ok"
        for t in (truth.talks if truth else [])
        if t.kind == "npc"
    )
    rows.append(
        _row(
            "npc places",
            [(bool(rec.get("spawns")), _place_source(rec)) for rec in npcs.values()],
            seen_ok=seen_npcs["ok"],
            seen_not_ok=seen_npcs["not ok"],
        )
    )
    rows.append(
        _row(
            "object places",
            [(bool(rec.get("spawns")), _place_source(rec)) for rec in r.get("object", {}).values()],
        )
    )
    # a vendor row's price comes from its sixth field's source when it has one (the engine's,
    # `client`), else from the row's own
    vendor = [
        (len(row) > 1 and row[1] is not None, _price_source(row))
        for rec in npcs.values()
        for row in rec.get("vendor") or []
        if isinstance(row, list) and row
    ]
    merchants = truth.merchants if truth else []
    rows.append(
        _row(
            "vendor prices",
            vendor,
            seen_ok=sum(m.ok for m in merchants),
            seen_not_ok=sum(len(m.differs) + len(m.not_in_pack) for m in merchants),
        )
    )
    trainer = [
        (len(row) > 2 and row[2] is not None, str(row[-1]) if row and row[-1] else "?")
        for rec in npcs.values()
        for row in rec.get("trainer") or []
        if isinstance(row, list) and row
    ]
    rows.append(_row("trainer costs", trainer))
    rows.append(
        _row(
            "item prices",
            [(rec.get("sell") is not None, str(rec.get("src") or "?")) for rec in items.values()],
            junk=sum(1 for rec in items.values() if JUNK.search(str(rec.get("name") or ""))),
        )
    )
    drops = [
        (len(row) > 1 and row[1] is not None, str(rec.get("dropsSrc") or "?"))
        for rec in items.values()
        for row in rec.get("drops") or []
        if isinstance(row, list) and row
    ]
    rows.append(_row("drop chances", drops))
    rows.append(
        _row(
            "quest givers and enders",
            [
                (bool(rec.get("starts")) and bool(rec.get("ends")), str(rec.get("src") or "?"))
                for rec in r.get("quest", {}).values()
            ],
        )
    )
    rows.append(
        _row(
            "dungeon bosses",
            [
                (
                    bool(rec.get("bosses"))
                    and all(len(b) > 1 and b[1] is not None for b in rec["bosses"]),
                    str(rec.get("src") or "?"),
                )
                for rec in r.get("dungeon", {}).values()
            ],
        )
    )
    rows.append(
        _row(
            "zone level bands",
            [
                (
                    rec.get("levelLo") is not None and rec.get("levelHi") is not None,
                    str(rec.get("src") or "?"),
                )
                for rec in r.get("zone", {}).values()
            ],
        )
    )
    return rows


def render(rows: list[dict]) -> list[str]:
    """The ledger as a section of the build report."""
    lines = [
        "## Quality ledger",
        "",
        "What is known of each kind, where it comes from (`client` is the engine), and what the",
        "probe saw in play this build (plan-data-quality.md L1).",
        "",
        "| Kind | Records | Known | Unknown | Sources of the known | Seen in play |",
        "|---|---|---|---|---|---|",
    ]
    for row in rows:
        sources = ", ".join(f"{k} {v}" for k, v in row["sources"].items()) or "-"
        seen = "-"
        if "seen_ok" in row and (row["seen_ok"] or row["seen_not_ok"]):
            seen = f"{row['seen_ok']} ok, {row['seen_not_ok']} not"
        kind = row["kind"] + (f" ({row['junk']} test or deprecated)" if row.get("junk") else "")
        lines.append(
            f"| {kind} | {row['count']} | {row['known']} | {row['unknown']} | {sources} | {seen} |"
        )
    lines.append("")
    return lines
