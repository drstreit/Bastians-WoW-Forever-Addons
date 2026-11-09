"""The Market pack's records from an AHSync export (data.md "Market pack", roadmap B10.2).

`price` records keyed `"<market>:<itemID>"`, `signal` records keyed `"<market>:<signalID>"`, `spot`
records by spot id and `strategy` records (claims) by claim id. Markets without export rows can take
another market's prices and signals, labelled, when build.toml says so (`[[market.fill]]`): EU
players see the US beta range with its date instead of nothing. ~~The rows were copied under the
filled market's id~~ (23.10.2026: with the first real export, 16,870 prices of four US markets, the
copies would have tripled the pack): a fill is an alias, `market.list[to] = { alias = source,
label }`, and `signal.byMarket[to]` lists the source's signals; Gold reads the alias market's
records. The label of a market (`src` of its price rows and `market.list[market].label`) comes from
`[market.labels]` or is the market id. Claims and farm spots without a `ui_map_id` get one from
their place (`where`, the export's English text) when it names one of the world's zones.
"""

from __future__ import annotations

from bastians_build.config import MarketConfig, MarketFill  # noqa: F401  (re-exported for callers)
from bastians_build.model import World
from bastians_build.sources.ahsync_export import Export


def price_key(market: str, item_id: int) -> str:
    return f"{market}:{item_id}"


def _price_record(row: dict, label: str) -> dict:
    return {
        "median": row["median"],
        "minBuyout": row["min_buyout"],
        "quantity": row["quantity"],
        "median7d": row["median_7d"],
        "median30d": row["median_30d"],
        "low30d": row["low_30d"],
        "high30d": row["high_30d"],
        "salesPerDay": row["sales_per_day"],
        "scanTs": row["scan_ts"],
        "src": label,
    }


def _signal_record(row: dict, market: str, label: str) -> dict:
    flags = list(row["flags"]) if isinstance(row["flags"], list) else None
    return {
        "module": row["module"],
        "action": row["action"],
        "item": row["item_id"],
        "horizon": row["horizon"],
        "confidence": row["confidence"],
        "rationale": row["rationale"],
        "capital": row["capital_required"],
        "profit": row["expected_profit"],
        "minutes": row["time_cost_minutes"],
        "flags": flags,
        "validUntil": row["valid_until"],
        "src": row["src"] if market == row["market"] else label,
    }


def zone_names(world: World) -> dict[str, int]:
    """Lowercase zone name -> UiMap id: zones (type 3, or untyped) before any other map, then the
    smallest id, so "elwynn forest" is 1429 and never one of its floors."""
    ranked: dict[str, tuple[int, int]] = {}
    for zone_id, rec in world.records.get("zone", {}).items():
        name = str(rec.get("name") or "").strip().lower()
        if not name or not isinstance(zone_id, int):
            continue
        rank = (0 if rec.get("mapType") in (3, None) else 1, zone_id)
        if name not in ranked or rank < ranked[name]:
            ranked[name] = rank
    return {name: rank[1] for name, rank in ranked.items()}


def place_map(where: str | None, zones: dict[str, int]) -> int | None:
    """The zone a place text names: the whole text, else the part before the first comma; None
    when no zone has that name (unknown stays unknown)."""
    if not where:
        return None
    text = where.strip().lower()
    return zones.get(text) or zones.get(text.split(",")[0].strip())


MAX_CHAIN = 4  # markets a lookup walks, as Gold's prices do


def old_rows(prices: list[dict], days: int) -> set[int]:
    """The indexes of the rows more than `days` older than their market's newest scan. A row without
    a time is not among them: unknown is not old."""
    newest: dict[str, int] = {}
    for row in prices:
        ts = row.get("scan_ts")
        if ts is not None and ts > newest.get(row["market"], 0):
            newest[row["market"]] = ts
    return {
        i
        for i, row in enumerate(prices)
        if row.get("scan_ts") is not None and row["scan_ts"] < newest[row["market"]] - days * 86400
    }


def add_market(world: World, export: Export, config: MarketConfig) -> list[str]:
    """Add the export's market records to the world; returns the notes (fills applied/skipped)."""
    notes: list[str] = []
    zones = zone_names(world)
    placed = 0
    prices = export.tables.get("prices_latest", [])
    signals = export.tables.get("signals", [])
    keep = config.shipped()
    if keep is not None:
        # the first real export (23.10.2026): four US markets cost 7.5 MB of Lua memory, a
        # player reads one market; the build carries the configured ones and their fills' sources
        left = sum(1 for r in prices if r["market"] not in keep)
        prices = [r for r in prices if r["market"] in keep]
        signals = [r for r in signals if r["market"] in keep]
        notes.append(f"market rows left out (not shipped, [market] ship): {left} prices")
    old = old_rows(prices, config.max_age_days) if config.max_age_days else set()
    if old:
        notes.append(
            f"market rows older than their market: {len(old)} prices, as {config.old_label!r}"
        )
    markets = {row["market"] for row in prices} | {row["market"] for row in signals}
    for i, row in enumerate(prices):
        if row["item_id"] is None or not row["market"]:
            world.drop("price", row.get("item_id"), "price row without market or item")
            continue
        world.add(
            "price",
            price_key(row["market"], row["item_id"]),
            _price_record(row, config.old_label if i in old else config.label(row["market"])),
        )
    for row in signals:
        if row["signal_id"] is None or not row["market"]:
            world.drop("signal", row.get("signal_id"), "signal row without market or id")
            continue
        world.add(
            "signal",
            f"{row['market']}:{row['signal_id']}",
            _signal_record(row, row["market"], row["src"]),
        )
    sources = {f.to: f.source for f in config.fill}

    def answers(market: str) -> bool:
        """The market has prices, or reads a market that has: EU RP reads EU normal, which may
        itself read US normal."""
        for _ in range(MAX_CHAIN):
            if any(r["market"] == market and r["item_id"] is not None for r in prices):
                return True
            if market not in sources:
                return False
            market = sources[market]
        return False

    for fill in config.fill:
        if keep is not None and fill.to not in keep:
            continue
        rows = sum(1 for r in prices if r["market"] == fill.source and r["item_id"] is not None)
        if fill.to in markets:
            if answers(fill.source):  # thin, not empty: only the items it lacks come from there
                world.market_fallbacks[fill.to] = fill.source
                notes.append(f"market {fill.to}: falls back to {fill.source} per item")
            continue
        if answers(fill.source):
            world.market_aliases[fill.to] = (fill.source, fill.label)
            notes.append(
                f"market {fill.to}: reads the {rows} prices of {fill.source} as {fill.label!r}"
            )
        else:
            notes.append(f"market {fill.to}: nothing to fill, {fill.source} has no rows")
    for row in export.tables.get("farm_spots", []):
        if row["spot_id"] is None:
            world.drop("spot", None, "farm spot without id")
            continue
        items = row["items"] if isinstance(row["items"], list) else None
        spot_map = row["ui_map_id"] or place_map(row.get("where"), zones)
        placed += row["ui_map_id"] is None and spot_map is not None
        world.add(
            "spot",
            row["spot_id"],
            {
                "name": row["name"],
                "map": spot_map,
                "x": row["x"],
                "y": row["y"],
                "radius": row["radius"],
                "levelMin": row["level_min"],
                "levelMax": row["level_max"],
                "items": [list(i) for i in items] if items else None,
                "strategy": row["claim_id"],
                "src": row["src"],
            },
        )
    for row in export.tables.get("claims", []):
        if row["claim_id"] is None:
            world.drop("strategy", None, "claim without id")
            continue
        claim_map = row["ui_map_id"] or place_map(row.get("where"), zones)
        placed += row["ui_map_id"] is None and claim_map is not None
        world.add(
            "strategy",
            row["claim_id"],
            {
                "kind": row["kind"],
                "subject": row["subject"],
                "item": row["item_id"],
                "map": claim_map,
                "x": row["x"],
                "y": row["y"],
                "weight": row["weight"],
                "reach": row["reach"],
                "build": row["build"],
                "firstSeen": row["first_seen"],
                "lastSeen": row["last_seen"],
                "src": row["src"],
            },
        )
    if placed:
        notes.append(f"claims and farm spots placed in a zone by their place text: {placed}")
    names = ", ".join(str(s.get("name")) for s in export.sources if s.get("name"))
    notes.append(
        f"market export {export.folder.name} (created {export.created_at or '?'}): "
        f"sources {names or 'unknown'}"
    )
    world.notes.extend(notes)
    return notes


# --- indexes (derive.py calls these) ----------------------------------------------------------


def market_list(world: World) -> dict:
    """market -> { scanTs (newest), items, label } over the price records."""
    out: dict[str, dict] = {}
    for key, rec in sorted(world.records.get("price", {}).items()):
        market = str(key).rpartition(":")[0]
        entry = out.setdefault(
            market, {"scanTs": None, "items": 0, "label": rec.get("src") or market}
        )
        entry["items"] += 1
        ts = rec.get("scanTs")
        if ts is not None and (entry["scanTs"] is None or ts > entry["scanTs"]):
            entry["scanTs"] = ts
            entry["label"] = rec.get("src") or market  # the newest row's, never an old one's
    for to, source in sorted(world.market_fallbacks.items()):
        if source in out and to in out:
            out[to]["fallback"] = source
    for _ in range(MAX_CHAIN):  # an alias may read an alias
        for to, (source, label) in sorted(world.market_aliases.items()):
            if source in out and to not in out:
                out[to] = {**out[source], "label": label, "alias": source}
    return out


def signals_by_market(world: World) -> dict:
    out: dict[str, list[str]] = {}
    for key in world.records.get("signal", {}):
        market, _, sid = str(key).rpartition(":")
        out.setdefault(market, []).append((int(sid) if sid.isdigit() else sid, str(key)))
    lists = {
        m: [k for _, k in sorted(v, key=lambda p: (str(type(p[0])), p[0]))]
        for m, v in sorted(out.items())
    }
    chains = {**world.market_fallbacks}
    chains.update({to: source for to, (source, _) in world.market_aliases.items()})
    for to in sorted(chains):
        source, hops = chains[to], 0
        while source not in lists and source in chains and hops < MAX_CHAIN:
            source, hops = chains[source], hops + 1
        if source in lists and to not in lists:
            lists[to] = list(lists[source])  # it reads the nearest market's signals
    return lists


def spots_all(world: World) -> list:
    return sorted(world.records.get("spot", {}))


def spots_by_item(world: World) -> dict:
    out: dict[int, list] = {}
    for spot_id, rec in sorted(world.records.get("spot", {}).items()):
        for item in rec.get("items") or []:
            if item and item[0] is not None:
                out.setdefault(item[0], []).append(spot_id)
    return out


def strategies_all(world: World) -> list:
    return sorted(world.records.get("strategy", {}))
