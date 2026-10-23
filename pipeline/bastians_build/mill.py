"""The Rumour mill (strategies-design.md section 7): per chapter the strongest strategies no page of
the book tells yet, one line each, rebuilt from every export.

The candidate report scores the strategies; the mill takes, per chapter of the book, the best
`MILL_CAP` that no page rests on, that are not marked "low value" and that at least
`MIN_CHANNELS` channels tell, and for each the claim that carries it best (verified first, then
the most sources, a concrete number, the reach) among those inside the level cap: no level above
it, no profession skill above what the cap allows (`SKILL_AT_CAP`). The line is
AHSync's own sentence (a claim, never a quote), its stamp from the export's status and the
sources, so the mill needs no prose and changes with every scan: a rumour that gains travellers
climbs, one that a page now tells leaves, a strong one is the next page's candidate.
"""

from __future__ import annotations

import re

from bastians_build.book import plain, rumour_record
from bastians_build.candidates import DEFAULT_CAP, DIGIT, Strategy
from bastians_build.model import World

MILL_CAP = 6  # lines per chapter
MIN_CHANNELS = 2  # a rumour one traveller tells is not in the mill yet
SKILL_AT_CAP = {30: 225}  # the highest profession skill a character of the cap can train
TRADES = (
    "skill|fishing|cooking|first aid|alchemy|blacksmithing|enchanting|engineering|herbalism|"
    "leatherworking|mining|skinning|tailoring"
)
# "level 27" is a character's level; "level 55 fishing" and "300 skill" are a profession's skill
LEVEL = re.compile(rf"\blevels?\s+(\d+)(?!\d|\s*(?:{TRADES})\b)", re.I)
SKILL = re.compile(
    rf"\b(?:levels?\s+)?(\d{{2,3}})\s+(?:{TRADES})\b|\bskill\s+(?:of\s+)?(\d{{2,3}})", re.I
)


def within_cap(claim: dict, cap: int = DEFAULT_CAP) -> bool:
    """No level above the cap and no skill above what the cap allows in the claim's sentence."""
    text = claim.get("claim") or ""
    limit = SKILL_AT_CAP.get(cap, 300)
    return all(int(m.group(1)) <= cap for m in LEVEL.finditer(text)) and all(
        int(m.group(1) or m.group(2)) <= limit for m in SKILL.finditer(text)
    )


def best_claim(s: Strategy, cap: int = DEFAULT_CAP) -> dict | None:
    """The claim that carries a strategy best among those inside the cap: verified, the most
    sources, a number, the reach; the lowest id where nothing decides (deterministic)."""

    def key(c: dict) -> tuple:
        return (
            c.get("status") == "verified",
            len(c.get("sources") or []),
            bool(DIGIT.search(c.get("claim") or "")),
            int(c.get("reach") or 0),
            -int(c["claim_id"]),
        )

    inside = [c for c in s.claims if within_cap(c, cap)]
    return max(inside, key=key) if inside else None


def add_mill(
    world: World,
    found: dict[str, list[Strategy]],
    cap: int = MILL_CAP,
    level_cap: int = DEFAULT_CAP,
) -> list[str]:
    """Adds the `mill` records (by claim id: chapter, rank, zone or the claim's own place) and the
    rumour records they show. Nothing without a book."""
    chapters = world.records.get("chapter", {})
    if not chapters:
        return []
    counts = []
    for chapter in sorted(found):
        if chapter not in chapters:
            continue
        rank = 0
        for s in found[chapter]:
            if rank >= cap:
                break
            if s.page or s.low_value or len(s.channels) < MIN_CHANNELS:
                continue
            claim = best_claim(s, level_cap)
            if claim is None:
                continue
            cid = int(claim["claim_id"])
            if world.get("mill", cid) is not None:
                continue
            rank += 1
            zone = s.zone if s.zone and world.get("zone", s.zone) is not None else None
            world.add(
                "mill",
                cid,
                {
                    "chapter": chapter,
                    "rank": rank,
                    "zone": zone,
                    "where": None if zone else plain(claim.get("where")) or None,
                    "channels": len(s.channels),
                    "claims": len(s.claims),
                },
            )
            if world.get("rumour", cid) is None:
                world.add("rumour", cid, rumour_record(claim))
        counts.append(f"{chapter} {rank}")
    note = "book: rumour mill " + ", ".join(counts)
    world.notes.append(note)
    return [note]


def mill_index(world: World) -> dict:
    """Index book.mill: per chapter the mill's claim ids, by rank."""
    out: dict[str, list[int]] = {}
    for cid, m in world.records.get("mill", {}).items():
        out.setdefault(m["chapter"], []).append(cid)
    for ids in out.values():
        ids.sort(key=lambda cid: (world.records["mill"][cid]["rank"], cid))
    return out
