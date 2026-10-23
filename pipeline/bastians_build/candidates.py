"""The book's candidate report (strategies-design.md section 7): the export's claims grouped into
strategies and scored, so the daily run says which strategies would make a chapter's five pages.

A strategy is a group of claims: the claims one video makes about one place or trade, merged with
other videos' claims in the same chapter and zone that name the same things. The score is the sum
of parts the report prints, so the owner sees why a strategy ranks where it does:

| Part | Points |
|---|---|
| channels | 10 per independent channel, at most 30 |
| reach | up to 20, by the logarithm of the summed views (100,000 views: all 20) |
| freshness | 15 when last seen within 14 days, falling to 0 at 60 days before the export |
| verification | +15 for verified claims, -15 for refuted ones, by their share |
| level cap | 20 when the zone's lowest level is within the cap, 10 for no zone, else 0 |
| breadth | 2 per claim, at most 10 |

Evidence alone ranks how well a strategy is supported, not what it pays ("did
we structure, sort, identify nuggets from low value tips?"). Two more parts say that:

- value, up to 30, from our data and today's prices: farming and fishing by the loot worth per
  kill of the creatures the claims name (matched by name), the price of the items they name and a
  gold per hour a claim states; crafting by the recipe margin of the items named; flips by the
  spread between the vendor and the auction house; the auction house and trades by how many
  channels agree;
- nuggets, up to 10: the share of claims with a concrete, checkable number.

Known gap (23.10.2026): the packs carry no coin drops per creature (CMaNGOS has them), so a
humanoid farm's worth per kill counts its loot only and reads low (Bael'dun: cloth, ~55c).

The rank is half the evidence plus one and a half times the value plus the nuggets, so in the gold
chapters a well-paying strategy outranks a well-known one; a gold chapter's strategy without any
value found is marked "low value". Deterministic: same export, same world, same report. No language
model (CLAUDE.md section 11).
"""

from __future__ import annotations

import json
import math
import re
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path

from bastians_build.market import place_map, zone_names
from bastians_build.model import World
from bastians_build.sources.ahsync_export import Export

CHAPTER_OF = {
    "farm_spot": "farming",
    "grind_spot": "farming",
    "fishing_spot": "fishing",
    "craft_margin": "crafting",
    "vendor_flip": "flips",
    "ah_rule": "auction",
    "profession_choice": "trades",
}  # price_level claims are facts for stamps and the Rumour mill, not strategies of their own
CHAPTERS = ("farming", "fishing", "crafting", "flips", "auction", "trades")
STOP = frozenset(
    [
        "a",
        "an",
        "the",
        "and",
        "or",
        "of",
        "in",
        "on",
        "at",
        "to",
        "for",
        "from",
        "with",
        "by",
        "is",
        "are",
        "be",
        "this",
        "that",
        "these",
        "those",
        "it",
        "its",
        "farm",
        "farming",
        "spot",
        "spots",
        "mob",
        "mobs",
        "grind",
        "grinding",
        "level",
        "levels",
        "gold",
        "per",
        "hour",
        "fishing",
        "fish",
        "vendor",
        "vendors",
        "auction",
        "house",
        "ah",
        "price",
        "prices",
        "profit",
        "craft",
        "crafting",
        "near",
        "area",
        "zone",
        "start",
        "south",
        "north",
        "east",
        "west",
        "southern",
        "northern",
        "eastern",
        "western",
        "cave",
        "camp",
        "village",
        "pond",
        "little",
        "beta",
        "launch",
        "any",
        "good",
        "best",
    ]
)
WORD = re.compile(r"[a-z][a-z']+")
DEFAULT_CAP = 30


@dataclass
class Strategy:
    chapter: str
    zone: int | None
    claims: list[dict] = field(default_factory=list)
    tokens: set[str] = field(default_factory=set)
    score: float = 0.0
    parts: dict[str, float] = field(default_factory=dict)
    title: str = ""
    page: str | None = None  # the book page that already tells it
    evidence: float = 0.0
    value_notes: list[str] = field(default_factory=list)
    low_value: bool = False

    @property
    def channels(self) -> set[str]:
        return {
            s.get("channel")
            for c in self.claims
            for s in c.get("sources") or []
            if s.get("channel")
        }


def _video(claim: dict) -> str:
    for s in claim.get("sources") or []:
        link = str(s.get("link") or "")
        m = re.search(r"[?&]v=([\w-]+)", link)
        if m:
            return m.group(1)
        if link:
            return link
    return f"claim:{claim['claim_id']}"


def _tokens(text: str, zone_words: set[str]) -> set[str]:
    return {w.strip("'") for w in WORD.findall(text.lower())} - STOP - zone_words


def _ts(value) -> float | None:
    return float(value) if isinstance(value, (int, float)) else None


def group(export: Export, world: World) -> list[Strategy]:
    """The claims as strategies: per video, chapter and zone first, then merged across videos."""
    zones = zone_names(world)
    zone_words = {w for name in zones for w in WORD.findall(name)}
    by_key: dict[tuple, Strategy] = {}
    for claim in export.tables.get("claims", []):
        chapter = CHAPTER_OF.get(claim.get("kind") or "")
        if not chapter or claim.get("status") == "outdated":
            continue
        zone = claim.get("ui_map_id") or place_map(claim.get("where"), zones)
        key = (chapter, zone, _video(claim))
        s = by_key.setdefault(key, Strategy(chapter=chapter, zone=zone))
        s.claims.append(claim)
        s.tokens |= _tokens(f"{claim.get('subject') or ''} {claim.get('where') or ''}", zone_words)
    merged: list[Strategy] = []
    for s in sorted(by_key.values(), key=lambda x: (x.chapter, x.zone or 0, -len(x.claims))):
        for m in merged:
            if m.chapter != s.chapter or m.zone != s.zone:
                continue
            both = m.tokens | s.tokens
            if both and len(m.tokens & s.tokens) / len(both) >= 0.25:
                m.claims.extend(s.claims)
                m.tokens |= s.tokens
                break
        else:
            merged.append(s)
    return merged


CUT = 0.95  # the auction house keeps 5 % of a sale
GOLD_PER_HOUR = re.compile(
    r"(\d+(?:\.\d+)?)\s*(?:to\s*\d+(?:\.\d+)?\s*)?gold (?:per|an|a) hour", re.I
)
DIGIT = re.compile(r"\d")
GOLD_CHAPTERS = ("farming", "fishing", "crafting", "flips")


def money(copper: float) -> str:
    c = round(copper)
    g, rest = divmod(abs(c), 10000)
    sv, k = divmod(rest, 100)
    text = (f"{g}g " if g else "") + (f"{sv}s " if sv or g else "") + f"{k}c"
    return ("-" if c < 0 else "") + text


class Valuer:
    """What things are worth: an item's auction price (the median of the markets' 7-day medians in
    the export), its vendor prices, an NPC's loot worth per kill, a recipe's margin."""

    def __init__(self, export: Export, world: World):
        prices: dict[int, list[int]] = defaultdict(list)
        for row in export.tables.get("prices_latest", []):
            p = row.get("median_7d") or row.get("median")
            if row.get("item_id") and p:
                prices[row["item_id"]].append(p)
        self.ah = {i: sorted(v)[len(v) // 2] for i, v in prices.items()}
        self.world = world
        self.npcs_by_word: dict[str, list[int]] = defaultdict(list)
        for nid, npc in sorted(world.records.get("npc", {}).items()):
            if npc.get("loot"):
                for w in set(WORD.findall((npc.get("name") or "").lower())):
                    if len(w) >= 4:
                        self.npcs_by_word[w].append(nid)
        self.recipes: dict[int, list[dict]] = defaultdict(list)
        for _, r in sorted(world.records.get("recipe", {}).items()):
            if r.get("item"):
                self.recipes[r["item"]].append(r)

    def name(self, item: int) -> str:
        return str((self.world.get("item", item) or {}).get("name", item))

    def per_kill(self, nid: int) -> float | None:
        npc = self.world.get("npc", nid) or {}
        total, known = 0.0, False
        for item, chance in npc.get("loot") or []:
            p = self.ah.get(item)
            if p:
                total += p * (chance or 0) / 100 * CUT
                known = True
        return total if known else None

    def mobs(self, s: Strategy) -> list[tuple[float, str]]:
        """The creatures the claims name, with their loot worth per kill, the best match first:
        a creature of the strategy's zone that one word of the claims names (a word in more than
        40 names says nothing), elsewhere or without a zone one that two words name ("Bael'dun
        Excavator": Classic places can sit on a neighbouring map)."""
        hits: dict[int, int] = defaultdict(int)
        for token in s.tokens:
            ids = self.npcs_by_word.get(token, [])
            if 0 < len(ids) <= 40:
                for nid in ids:
                    hits[nid] += 1
        out = []
        for nid, n in hits.items():
            npc = self.world.get("npc", nid) or {}
            here = s.zone is not None and any(p[0] == s.zone for p in npc.get("spawns") or [])
            if n < (1 if here else 2):
                continue
            worth = self.per_kill(nid)
            if worth:
                out.append((n, worth, str(npc.get("name", nid))))
        out.sort(key=lambda x: (-x[0], -x[1], x[2]))
        return [(w, name) for _, w, name in out[:3]]

    def margin(self, item: int) -> float | None:
        best = None
        sale = self.ah.get(item)
        if not sale:
            return None
        for r in self.recipes.get(item, []):
            cost: float | None = 0.0
            for reagent, n in r.get("reagents") or []:
                p = self.ah.get(reagent) or (self.world.get("item", reagent) or {}).get("buy")
                if not p or cost is None:
                    cost = None
                    break
                cost += p * n
            if cost is not None:
                m = sale * (r.get("count") or 1) * CUT - cost
                best = m if best is None else max(best, m)
        return best

    def spread(self, item: int) -> float | None:
        """A flip's margin: buy at the vendor and sell on the auction house, or buy on the auction
        house and sell to a vendor, whichever pays."""
        rec = self.world.get("item", item) or {}
        ah = self.ah.get(item)
        if not ah:
            return None
        options = []
        if rec.get("buy"):
            options.append(ah * CUT - rec["buy"])
        if rec.get("sell"):
            options.append(rec["sell"] - ah)
        return max(options) if options else None


def _steps(amount: float | None, steps: tuple[float, float, float]) -> float:
    if amount is None:
        return 0.0
    if amount >= steps[2]:
        return 30.0
    if amount >= steps[1]:
        return 20.0
    return 10.0 if amount >= steps[0] else 0.0


def value(s: Strategy, v: Valuer) -> float:
    """The value part (0..30) with its notes, by chapter."""
    notes = s.value_notes
    items = sorted({c["item_id"] for c in s.claims if c.get("item_id")})
    claimed = [
        float(m.group(1)) for c in s.claims for m in GOLD_PER_HOUR.finditer(c.get("claim") or "")
    ]
    points = 0.0
    if claimed:
        notes.append(f"a claim says {max(claimed):g} gold an hour")
        points = 30.0 if max(claimed) >= 10 else 20.0 if max(claimed) >= 3 else 10.0
    if s.chapter in ("farming", "fishing"):
        # fishing is worth its catch, never a creature that happens to share a word
        for worth, name in v.mobs(s)[:1] if s.chapter == "farming" else []:
            notes.append(f"{name}: {money(worth)} a kill")
            points = max(points, _steps(worth, (30, 100, 250)))
        priced = sorted((v.ah[i], i) for i in items if i in v.ah)
        if priced:
            price, item = priced[-1]
            notes.append(f"{v.name(item)} sells for {money(price)}")
            points = max(points, _steps(price, (50, 500, 5000)))
    elif s.chapter == "crafting":
        margins = sorted((m, i) for i in items if (m := v.margin(i)) is not None)
        if margins:
            m, item = margins[-1]
            notes.append(f"{v.name(item)}: {money(m)} a craft")
            points = max(points, _steps(m, (20, 100, 500)))
    elif s.chapter == "flips":
        spreads = sorted((m, i) for i in items if (m := v.spread(i)) is not None)
        if spreads:
            m, item = spreads[-1]
            notes.append(f"{v.name(item)}: {money(m)} a flip")
            points = max(points, _steps(m, (20, 100, 1000)))
    else:  # the auction house and trades: knowledge, worth what the channels agree on
        n = len(s.channels)
        notes.append(f"{n} channels agree")
        points = 30.0 if n >= 3 else 20.0 if n == 2 else 10.0
    s.low_value = s.chapter in GOLD_CHAPTERS and points == 0
    return points


def score(s: Strategy, world: World, now: float, cap: int = DEFAULT_CAP) -> None:
    channels = len(s.channels)
    reach = sum(int(c.get("reach") or 0) for c in s.claims)
    last = max((_ts(c.get("last_seen")) or 0 for c in s.claims), default=0)
    days = (now - last) / 86400 if last else 999
    verified = sum(1 for c in s.claims if c.get("status") == "verified")
    refuted = sum(1 for c in s.claims if c.get("status") == "refuted")
    zone = world.get("zone", s.zone) if s.zone else None
    low = zone.get("levelLo") if zone else None
    parts = {
        "channels": float(min(30, 10 * channels)),
        "reach": round(min(20.0, 20 * math.log10(1 + reach) / 5), 1),
        "freshness": round(15.0 if days <= 14 else max(0.0, 15 * (60 - days) / 46), 1),
        "verification": round(15 * (verified - refuted) / len(s.claims), 1),
        "level cap": 10.0 if low is None else (20.0 if low <= cap else 0.0),
        "breadth": float(min(10, 2 * len(s.claims))),
    }
    s.parts = parts
    s.evidence = round(sum(parts.values()), 1)
    s.score = s.evidence
    words = sorted(
        s.tokens, key=lambda w: (-sum(w in (c.get("subject") or "").lower() for c in s.claims), w)
    )
    place = zone.get("name") if zone else "no zone"
    s.title = f"{place}: {', '.join(words[:3]) or s.claims[0].get('subject')}"


def candidates(
    export: Export, world: World, cap: int = DEFAULT_CAP, now: float | None = None
) -> dict[str, list[Strategy]]:
    """Per chapter the strategies, best first; a strategy a book page tells is marked with it."""
    if now is None:
        stamps = [_ts(c.get("last_seen")) for c in export.tables.get("claims", [])]
        now = max((t for t in stamps if t), default=datetime.now(UTC).timestamp())
    told: dict[int, str] = {}
    for page_id, page in world.records.get("page", {}).items():
        for r in page.get("rumours") or []:
            told[r[0]] = page_id
    out: dict[str, list[Strategy]] = {c: [] for c in CHAPTERS}
    valuer = Valuer(export, world)
    for s in group(export, world):
        score(s, world, now, cap)
        worth = value(s, valuer)
        concrete = sum(1 for c in s.claims if DIGIT.search(c.get("claim") or ""))
        s.parts["value"] = worth
        s.parts["nuggets"] = round(10 * concrete / len(s.claims), 1)
        s.score = round(s.evidence / 2 + 1.5 * worth + s.parts["nuggets"], 1)
        pages = {told[c["claim_id"]] for c in s.claims if c["claim_id"] in told}
        s.page = sorted(pages)[0] if pages else None
        out[s.chapter].append(s)
    for chapter in out:
        out[chapter].sort(key=lambda s: (-s.score, s.title))
    return out


def report(found: dict[str, list[Strategy]], top: int = 8) -> str:
    """The candidate report as Markdown: per chapter the best `top`, the five that would be the
    chapter's pages marked, the parts of every score, the claims with their channels."""
    lines = [
        "# The book's candidates",
        "",
        "Strategies grouped from the export's claims and scored (bastians_build/candidates.py);",
        "the first five of a chapter would be its pages. `page` names the book page that tells",
        "it.",
        "",
    ]
    for chapter, items in found.items():
        lines += [f"## {chapter} ({len(items)} strategies)", ""]
        for i, s in enumerate(items[:top], 1):
            mark = "**" if i <= 5 else ""
            parts = ", ".join(f"{k} {v:g}" for k, v in s.parts.items())
            page = f", page `{s.page}`" if s.page else ""
            if s.value_notes:
                page += "; " + "; ".join(s.value_notes)
            if s.low_value:
                page += "; **low value**"
            lines.append(
                f"{i}. {mark}{s.title}{mark}: {s.score:g} ({parts}); {len(s.claims)} claims, "
                f"{len(s.channels)} channels{page}"
            )
            for c in s.claims[:6]:
                lines.append(f"   - `{c['claim_id']}` {c.get('claim') or c.get('subject')}")
        lines.append("")
    return "\n".join(lines) + "\n"


def as_json(found: dict[str, list[Strategy]], top: int = 15) -> dict:
    """The report for tools and writers: per chapter the best `top` with every claim."""
    keys = ("claim_id", "kind", "subject", "where", "claim", "status")
    out: dict = {}
    for chapter, items in found.items():
        out[chapter] = [
            {
                "title": s.title,
                "score": s.score,
                "parts": s.parts,
                "value": s.value_notes,
                "lowValue": s.low_value,
                "page": s.page,
                "zone": s.zone,
                "claims": [
                    {k: c.get(k) for k in keys}
                    | {"sources": [src.get("link") for src in c.get("sources") or []]}
                    for c in s.claims
                ],
            }
            for s in items[:top]
        ]
    return out


def write_report(found: dict[str, list[Strategy]], report_dir: Path) -> Path:
    """build/book-candidates.md and its twin book-candidates.json, written atomically."""
    report_dir.mkdir(parents=True, exist_ok=True)
    path = report_dir / "book-candidates.md"
    twin = json.dumps(as_json(found), indent=1, sort_keys=True)
    for target, text in ((path, report(found)), (report_dir / "book-candidates.json", twin)):
        tmp = target.with_suffix(target.suffix + ".tmp")
        tmp.write_text(text, encoding="utf-8", newline="\n")
        tmp.replace(target)
    return path
