"""Internal records leave the pack (AT7 D2, data.md "Internal records", owner's ballot B17).

The sources carry what the game never shows a player: creatures nobody can select (triggers,
credit markers, spotlights), developers' leftovers ("[UNUSED] ...", "Test ...", "Deprecated ...")
and the weapons monsters hold ("Monster - Sword, ..."). A record goes only when it carries such a
mark **and** nothing real refers to it: no quest, no dungeon, no vendor, no loot table, no recipe.
"""

from __future__ import annotations

import re

from bastians_build.model import World

# creature_template.UnitFlags: the player cannot target or click the creature (CMaNGOS
# UNIT_FLAG_NOT_SELECTABLE). Measured 05.11.2026: 213 Classic creatures, the six test creatures of
# Stormwind among them, and five raid bosses that become selectable by script (they have loot).
NOT_SELECTABLE = 0x02000000
RANKS = frozenset({"elite", "rareelite", "rare", "boss"})

# The developers' marks in a name. Case matters: "Test of Faith" is a quest, "Field Testing Kit"
# a quest item, "High Test Eternium Fishing Line" a real line; "TEST", "(test)" and a name that
# starts with "Test " (but not "Test of ...") are not.
MARKS = re.compile(
    r"\bUNUSED\b|<UNUSED>|^Unused "
    r"|\bDEPRECATED\b|^Deprecated |\bDEP\]?$"
    r"|\bTEST\b|\(test\)|^Test (?!of\b)| test "
    r"|\bDEBUG\b|\bDebug\b"
    r"|\(DND\)|\[DND\]|\bDND\b|\(DNT\)"
    r"|\[PH\]|[Pp]laceholder"
    r"|\(OLD\)|^OLD |\(old\)| OLD$|^zzOLD"
    r"|<TXT>"
    r"|^Monster - "
)


def marked(name: object) -> bool:
    return isinstance(name, str) and MARKS.search(name) is not None


def _refs(value: object, out: dict[str, set[int]]) -> None:
    """Every 'npc:448' style reference anywhere inside a record's value."""
    if isinstance(value, str):
        kind, sep, raw = value.partition(":")
        if sep and raw.isdigit() and kind in out:
            out[kind].add(int(raw))
    elif isinstance(value, dict):
        for v in value.values():
            _refs(v, out)
    elif isinstance(value, (list, tuple)):
        for v in value:
            _refs(v, out)


def _firsts(rows: object) -> set[int]:
    """The ids of [[id, ...], ...] rows (loot, vendor, reagents, required items)."""
    return {
        row[0]
        for row in rows or []
        if isinstance(row, (list, tuple)) and row and isinstance(row[0], int)
    }


def referenced(world: World) -> dict[str, set[int]]:
    """What something real refers to: {"npc": ids, "item": ids, "object": ids}."""
    out: dict[str, set[int]] = {"npc": set(), "item": set(), "object": set()}
    get = world.records.get
    for quest in get("quest", {}).values():
        _refs(quest, out)
        out["item"] |= _firsts(quest.get("requiredItems"))
        rewards = quest.get("rewards") or {}
        out["item"] |= _firsts(rewards.get("items")) | _firsts(rewards.get("choices"))
    for dungeon in get("dungeon", {}).values():
        _refs(dungeon, out)
        out["npc"] |= {
            b[1] for b in dungeon.get("bosses") or [] if len(b) > 1 and isinstance(b[1], int)
        }
        out["item"] |= _firsts(dungeon.get("loot"))
    for kind in ("npc", "object", "disenchant"):
        for rec in get(kind, {}).values():
            out["item"] |= _firsts(rec.get("loot")) | _firsts(rec.get("vendor"))
    for recipe in get("recipe", {}).values():
        out["item"] |= _firsts(recipe.get("reagents"))
        for key in ("item", "sourceItem"):
            if isinstance(recipe.get(key), int):
                out["item"].add(recipe[key])
    for node in get("node", {}).values():
        if isinstance(node.get("item"), int):
            out["item"].add(node["item"])
    return out


def _flags(rec: dict) -> set[str]:
    flags = rec.get("flags") or []
    return set(flags if isinstance(flags, list) else [flags])


def internal_npc(rec: dict, unit_flags: int | None) -> bool:
    """A creature with a developers' mark, or one nobody can select that is nothing to a player:
    no loot, no rank, no service (a raid boss that a script makes selectable has loot)."""
    if marked(rec.get("name")):
        return True
    if not (unit_flags or 0) & NOT_SELECTABLE:
        return False
    return (
        not rec.get("loot") and not rec.get("vendor") and not rec.get("trainer") and not _flags(rec)
    )


def internal_item(rec: dict) -> bool:
    """An item with a developers' mark that has no known way to a player: no drop, no recipe."""
    return marked(rec.get("name")) and not (
        rec.get("drops") or rec.get("worldDrop") or rec.get("madeBy") or rec.get("questItem")
    )


def internal_object(rec: dict) -> bool:
    return marked(rec.get("name")) and not rec.get("loot")


def drop_internal(world: World, unit_flags: dict[int, int | None] | None = None) -> dict[str, int]:
    """Takes the internal records out of the world and notes how many per type. `unit_flags` is
    creature_template.UnitFlags by entry (Classic; without it only the names decide)."""
    unit_flags = unit_flags or {}
    tests = {
        "npc": lambda ident, rec: internal_npc(rec, unit_flags.get(ident)),
        "item": lambda _ident, rec: internal_item(rec),
        "object": lambda _ident, rec: internal_object(rec),
    }
    counts = dict.fromkeys(tests, 0)
    # until nothing changes: an item only a removed creature dropped is referred to by nothing
    # real any more, so one pass would leave a second run something to do
    while True:
        refs = referenced(world)
        removed = 0
        for kind, test in tests.items():
            records = world.records.get(kind, {})
            gone = sorted(i for i, rec in records.items() if i not in refs[kind] and test(i, rec))
            for ident in gone:
                del records[ident]
            counts[kind] += len(gone)
            removed += len(gone)
        if not removed:
            break
    if any(counts.values()):
        world.notes.append(
            "internal records left out (data.md): "
            + ", ".join(f"{n} {kind}" for kind, n in counts.items() if n)
        )
    return counts
