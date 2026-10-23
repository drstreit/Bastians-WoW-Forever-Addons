"""The Strategies book (strategies-design.md sections 6 and 7): content/strategies -> book records.

A page is a Markdown file with a TOML header between `+++` lines; `book.toml` holds the chapters,
the What's new entries and the tombstones of retired pages. The build checks every id against the
world and every claim against the export, refuses text the game fonts cannot draw, turns the text
into blocks and precomputes the plates (the dots scaled to the plate, the farm's outline and the
loop, the yards across and the nearest flight point per faction when the build has transforms).
No language model runs here (CLAUDE.md section 11): the pages are authored source.
"""

from __future__ import annotations

import math
import re
import tomllib
from collections.abc import Mapping
from pathlib import Path

from bastians_build.model import World
from bastians_build.sources.ahsync_export import Export
from bastians_build.sources.probe import Transform

ROOT = Path(__file__).resolve().parents[2]
CONTENT_DIR = ROOT / "content" / "strategies"

ENTITY_TOKEN = re.compile(r"\{(item|npc|object|zone|price|vendor):(\d+)\}")
ANY_TOKEN = re.compile(r"\{[^{}]*\}")
MARKERS = {"{plate}": "plate", "{live}": "live", "{table}": "table"}
STEP = re.compile(r"^(\d+)\.\s+(.*)$")
STAMPS = ("true", "half", "lies", "open")
STATUS_STAMP = {"verified": "true", "refuted": "lies", "unverified": "open"}
SHELVES = ("active", "back")
PLATE_ASPECT = 1.62  # the plate's width over its height (340 x 210 px in the book)
PAD = 0.08  # air around the dots, as a share of the plate
LOOP_SHRINK = 0.72  # the loop runs a quarter inside the farm's outline
ROUND = 3  # decimals of the plate geometry (deterministic, small)
# the glyphs a plate may draw: Core's glyph atlas, one file per glyph
GLYPH_DIR = ROOT / "addons" / "Bastians_Core" / "Media" / "Glyphs"
TINTS = ("accent", "bad", "gold", "good", "muted", "warn")  # theme tokens (ADR 0017)


class BookError(ValueError):
    pass


def check_glyph(glyph: str | None, tint: str | None, where: str) -> None:
    """A plate's glyph must be in Core's atlas and its tint a theme token: the game would draw
    nothing for an unknown one, silently."""
    known = {p.stem for p in GLYPH_DIR.glob("*.tga")}
    if glyph is not None and known and glyph not in known:
        raise BookError(f"{where}: no glyph {glyph!r}; known: {', '.join(sorted(known))}")
    if tint is not None and tint not in TINTS:
        raise BookError(f"{where}: tint must be one of {', '.join(TINTS)}")


# ---- text -----------------------------------------------------------------------------------


def check_text(text: str, where: str) -> None:
    """ASCII only (the game fonts), no dashes as punctuation (the voice rule)."""
    for ch in text:
        if not (32 <= ord(ch) <= 126):
            raise BookError(f"{where}: character {ch!r} (U+{ord(ch):04X}) the game fonts lack")
    if " - " in text or "--" in text:
        raise BookError(f"{where}: a dash as punctuation (the voice rule): {text[:60]!r}")


def split_front(text: str, where: str) -> tuple[dict, str]:
    lines = text.replace("\r\n", "\n").split("\n")
    if not lines or lines[0].strip() != "+++":
        raise BookError(f"{where}: the page must start with a +++ header")
    try:
        end = next(i for i in range(1, len(lines)) if lines[i].strip() == "+++")
    except StopIteration as exc:
        raise BookError(f"{where}: the +++ header is not closed") from exc
    try:
        header = tomllib.loads("\n".join(lines[1:end]))
    except tomllib.TOMLDecodeError as exc:
        raise BookError(f"{where}: header: {exc}") from exc
    return header, "\n".join(lines[end + 1 :])


def parse_body(body: str, where: str) -> list[list]:
    """The text as blocks: ["opening"|"p"|"verdict", text], ["h", title], ["steps", [..]],
    ["plate"], ["live"], ["table"]."""
    blocks: list[list] = []
    para: list[str] = []
    steps: list[str] = []
    verdict_next = False
    seen_heading = False

    def flush_para() -> None:
        nonlocal verdict_next
        if not para:
            return
        text = " ".join(para)
        if verdict_next:
            kind = "verdict"
            verdict_next = False
        else:
            kind = "p" if seen_heading else "opening"
        blocks.append([kind, text])
        para.clear()

    def flush_steps() -> None:
        if steps:
            blocks.append(["steps", list(steps)])
            steps.clear()

    for raw in body.split("\n"):
        line = raw.strip()
        if not line:
            flush_para()
            flush_steps()
            continue
        if line.startswith("## "):
            flush_para()
            flush_steps()
            title = line[3:].strip()
            seen_heading = True
            if title.lower() == "verdict":
                verdict_next = True
            else:
                blocks.append(["h", title])
            continue
        if line in MARKERS:
            flush_para()
            flush_steps()
            blocks.append([MARKERS[line]])
            continue
        step = STEP.match(line)
        if step and not para:
            steps.append(step.group(2))
            continue
        if steps and raw[:1].isspace():  # an indented line continues the step
            steps[-1] += " " + line
            continue
        flush_steps()
        para.append(line)
    flush_para()
    flush_steps()
    if not any(b[0] in ("opening", "p") for b in blocks):
        raise BookError(f"{where}: no text")
    return blocks


def block_texts(blocks: list[list]) -> list[str]:
    out = []
    for b in blocks:
        if b[0] in ("opening", "p", "verdict", "h"):
            out.append(b[1])
        elif b[0] == "steps":
            out.extend(b[1])
    return out


def entity_refs(texts: list[str], world: World, where: str) -> list[str]:
    """Checks every token; returns the entity refs in the order they first appear."""
    refs: list[str] = []
    for text in texts:
        for token in ANY_TOKEN.findall(text):
            m = ENTITY_TOKEN.fullmatch(token)
            if not m:
                raise BookError(f"{where}: unknown token {token}")
            kind, raw = m.group(1), int(m.group(2))
            record_type = "item" if kind in ("price", "vendor") else kind
            if world.get(record_type, raw) is None:
                raise BookError(f"{where}: {token}: no {record_type} {raw} in the world")
            if kind == "vendor" and not (world.get("item", raw) or {}).get("sell"):
                raise BookError(f"{where}: {token}: the item has no vendor price")
            ref = f"{record_type}:{raw}"
            if kind not in ("price", "vendor") and ref not in refs:
                refs.append(ref)
    return refs


# ---- plates ---------------------------------------------------------------------------------


def _hull(points: list[tuple[float, float]]) -> list[tuple[float, float]]:
    pts = sorted(set(points))
    if len(pts) < 3:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower: list[tuple[float, float]] = []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    upper: list[tuple[float, float]] = []
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def _spawns(world: World, ids: list[int], map_id: int, where: str) -> list[tuple[float, float]]:
    points = []
    for raw in ids:
        rec = world.get("npc", raw) or world.get("object", raw)
        if rec is None:
            raise BookError(f"{where}: plate: no npc or object {raw}")
        for s in rec.get("spawns") or []:
            if s[0] == map_id:
                points.append((float(s[1]), float(s[2])))
    return points


def _r(value: float) -> float:
    return round(value, ROUND)


def _to_world(t: Transform, x: float, y: float) -> tuple[float, float]:
    return (t.wx0 + x * t.wx_dx + y * t.wx_dy, t.wy0 + x * t.wy_dx + y * t.wy_dy)


def spot_plate(
    spec: Mapping,
    world: World,
    transforms: Mapping[int, Transform] | None,
    where: str,
    zones: list[int] | None = None,
) -> dict:
    """The place from above: the dots of `farm` and `avoid` in plate coordinates (0..1 across,
    0..1 down, the box kept in the map's proportions), the farm's outline, the loop and its start,
    the landmark, the yards across and the nearest flight point per faction."""
    map_id = spec.get("map")
    if not isinstance(map_id, int) or world.get("zone", map_id) is None:
        raise BookError(f"{where}: plate: `map` must be a zone id of the world")
    farm = _spawns(world, list(spec.get("farm") or []), map_id, where)
    avoid = _spawns(world, list(spec.get("avoid") or []), map_id, where)
    if not farm:
        raise BookError(f"{where}: plate: no spawn of `farm` on map {map_id}")
    t = (transforms or {}).get(map_id)
    # the map's proportions: yards per map fraction across and down (1.5 : 1 without a transform)
    sx, sy = (math.hypot(t.wx_dx, t.wy_dx), math.hypot(t.wx_dy, t.wy_dy)) if t else (1.5, 1.0)
    everything = farm + avoid
    x0, x1 = min(p[0] for p in everything), max(p[0] for p in everything)
    y0, y1 = min(p[1] for p in everything), max(p[1] for p in everything)
    width, height = max((x1 - x0) * sx, 1e-6), max((y1 - y0) * sy, 1e-6)
    # fit into the plate's box (aspect PLATE_ASPECT), centred, PAD of air
    scale = min((1 - 2 * PAD) / width, (1 - 2 * PAD) / (height * PLATE_ASPECT))
    ox = 0.5 - scale * width / 2
    oy = 0.5 - scale * height * PLATE_ASPECT / 2

    def plate(p: tuple[float, float]) -> tuple[float, float]:
        return (
            _r(ox + (p[0] - x0) * sx * scale),
            _r(oy + (p[1] - y0) * sy * scale * PLATE_ASPECT),
        )

    farm_p = [plate(p) for p in farm]
    avoid_p = [plate(p) for p in avoid]
    hull = _hull(farm_p)
    cx = sum(p[0] for p in farm_p) / len(farm_p)
    cy = sum(p[1] for p in farm_p) / len(farm_p)
    loop = [(_r(cx + (x - cx) * LOOP_SHRINK), _r(cy + (y - cy) * LOOP_SHRINK)) for x, y in hull]
    start = min(loop, key=lambda p: (p[0], p[1])) if loop else (_r(cx), _r(cy))
    out: dict = {
        "kind": "spot",
        "farm": [list(p) for p in farm_p],
        "avoid": [list(p) for p in avoid_p],
        "hull": [list(p) for p in hull],
        "loop": [list(p) for p in loop],
        "start": list(start),
        "label": spec.get("label"),
        "labelAt": [_r(cx), _r(max(p[1] for p in farm_p))],
        # the farm's centre on its map (fractions): the Rumours map layer's pin
        "place": [
            map_id,
            _r(sum(p[0] for p in farm) / len(farm)),
            _r(sum(p[1] for p in farm) / len(farm)),
        ],
    }
    landmark = spec.get("landmark")
    if landmark:
        pts = avoid_p if landmark.get("at") == "avoid" and avoid_p else farm_p
        check_glyph(landmark.get("glyph", "spot"), None, f"{where}: plate landmark")
        out["landmark"] = {
            "glyph": landmark.get("glyph", "spot"),
            "label": landmark.get("label"),
            "at": [
                _r(sum(p[0] for p in pts) / len(pts)),
                _r(sum(p[1] for p in pts) / len(pts)),
            ],
        }
    if t:
        out["across"] = round(1 / scale)  # the plate's width in yards
        try:
            out["fp"] = nearest_flight_points(world, t, farm, list(zones or []), spec.get("fp"))
        except BookError as err:
            raise BookError(f"{where}: {err}") from None
    for text in (out.get("label"), (out.get("landmark") or {}).get("label")):
        if text:
            check_text(text, f"{where}: plate")
    return out


def nearest_flight_points(
    world: World,
    t: Transform,
    farm: list[tuple[float, float]],
    zones: list[int],
    chosen: Mapping[str, int] | None = None,
) -> list[dict]:
    """Per faction (A, H) the flight point to start from: the one the page names in `chosen`
    (`fp = { A = id }`: the author knows the road), else the nearest one in the page's own zones
    (the way a player travels; a straight line can cross mountains), else the nearest on the
    continent. Name, yards as the crow flies, and the direction from the farm's centre on the
    plate (radians in the plate's pixels, 0 = east, positive = down)."""
    chosen = dict(chosen or {})
    cx = sum(p[0] for p in farm) / len(farm)
    cy = sum(p[1] for p in farm) / len(farm)
    wx, wy = _to_world(t, cx, cy)
    sx, sy = math.hypot(t.wx_dx, t.wy_dx), math.hypot(t.wx_dy, t.wy_dy)
    det = t.wx_dx * t.wy_dy - t.wx_dy * t.wy_dx
    best: dict[str, tuple[tuple[int, float], dict]] = {}
    for fp_id, fp in sorted(world.records.get("flightpath", {}).items()):
        if fp.get("continent") != t.continent or fp.get("wx") is None or fp.get("wy") is None:
            continue
        d = math.hypot(fp["wx"] - wx, fp["wy"] - wy)
        spawns = fp.get("spawns") or []
        in_zone = bool(spawns) and spawns[0][0] in zones
        key = (0 if in_zone else 1, d)
        angle = None
        if det:
            # the direction in map fractions (x east, y south) times the yards per fraction of
            # each axis: the plate's pixels are square in yards
            dxw, dyw = fp["wx"] - wx, fp["wy"] - wy
            fx = (dxw * t.wy_dy - dyw * t.wx_dy) / det
            fy = (dyw * t.wx_dx - dxw * t.wy_dx) / det
            angle = _r(math.atan2(fy * sy, fx * sx))
        for faction in ("A", "H"):
            if fp.get("faction") not in (faction, "both"):
                continue
            rank = (0 if fp_id == chosen[faction] else 2, d) if faction in chosen else key
            if faction not in best or rank < best[faction][0]:
                best[faction] = (
                    rank,
                    {
                        "faction": faction,
                        "id": fp_id,
                        "name": fp.get("name"),
                        "yards": round(d),
                        "angle": angle,
                    },
                )
    for faction, fp_id in chosen.items():
        if faction not in ("A", "H") or best.get(faction, ((1,), {}))[1].get("id") != fp_id:
            raise BookError(
                f"plate fp: {faction} = {fp_id} is no {faction} flight point on continent "
                f"{t.continent}"
            )
    return [best[f][1] for f in ("A", "H") if f in best]


def flow_plate(spec: Mapping, where: str) -> dict:
    nodes = []
    for i, node in enumerate(spec.get("nodes") or [], 1):
        for key in ("glyph", "title"):
            if not node.get(key):
                raise BookError(f"{where}: plate node {i}: missing `{key}`")
        for key in ("title", "note"):
            if node.get(key):
                check_text(node[key], f"{where}: plate node {i}")
        check_glyph(node["glyph"], node.get("tint"), f"{where}: plate node {i}")
        nodes.append(
            {
                "glyph": node["glyph"],
                "title": node["title"],
                "note": node.get("note"),
                "tint": node.get("tint"),
            }
        )
    if len(nodes) < 2:
        raise BookError(f"{where}: a flow plate needs two nodes at least")
    out: dict = {"kind": "flow", "nodes": nodes}
    foot = spec.get("foot")
    if foot:
        check_text(foot.get("text", ""), f"{where}: plate foot")
        check_glyph(foot.get("glyph", "never"), foot.get("tint", "bad"), f"{where}: plate foot")
        out["foot"] = {
            "glyph": foot.get("glyph", "never"),
            "text": foot.get("text"),
            "tint": foot.get("tint", "bad"),
        }
    return out


# ---- live boxes and tables --------------------------------------------------------------------


def check_live(spec: Mapping, world: World, where: str) -> dict:
    kind = spec.get("kind")
    if kind == "farm":
        npcs = [int(n) for n in spec.get("npcs") or []]
        if not npcs:
            raise BookError(f"{where}: live farm: `npcs` is empty")
        for n in npcs:
            rec = world.get("npc", n) or world.get("object", n)
            if rec is None or not rec.get("loot"):
                raise BookError(f"{where}: live farm: {n} has no loot in the world")
        return {"kind": "farm", "npcs": npcs, "top": int(spec.get("top", 3))}
    if kind == "flip":
        buy, sell = spec.get("buy"), spec.get("sell")
        for item in (buy, sell):
            if world.get("item", item) is None:
                raise BookError(f"{where}: live flip: no item {item}")
        if not (world.get("item", sell) or {}).get("sell"):
            raise BookError(f"{where}: live flip: item {sell} has no vendor price")
        return {"kind": "flip", "buy": buy, "sell": sell, "per": int(spec.get("per", 1))}
    if kind == "craft":
        # a recipe's margin at today's prices: the product on the auction house against the
        # reagents (the auction house, else a vendor); the recipe is resolved here
        rid = spec.get("recipe")
        recipe = world.get("recipe", rid)
        if recipe is None or not recipe.get("item") or not recipe.get("reagents"):
            raise BookError(f"{where}: live craft: no recipe {rid} with a product and reagents")
        return {
            "kind": "craft",
            "recipe": rid,
            "item": recipe["item"],
            "count": recipe.get("count") or 1,
            "reagents": [[int(i), int(n)] for i, n in recipe["reagents"]],
        }
    if kind == "prices":
        items = [int(i) for i in spec.get("items") or []]
        if not items:
            raise BookError(f"{where}: live prices: `items` is empty")
        for item in items:
            if world.get("item", item) is None:
                raise BookError(f"{where}: live prices: no item {item}")
        return {"kind": "prices", "items": items}
    raise BookError(f"{where}: live: kind must be farm, flip, craft or prices")


def check_table(spec: Mapping, world: World, where: str) -> dict:
    if spec.get("kind") != "vendorpairs":
        raise BookError(f"{where}: table: kind must be vendorpairs")
    rows = []
    for pair in spec.get("rows") or []:
        cloth, made = int(pair[0]), int(pair[1])
        per = int(pair[2]) if len(pair) > 2 else 1
        for item in (cloth, made):
            if not (world.get("item", item) or {}).get("sell"):
                raise BookError(f"{where}: table: item {item} has no vendor price")
        rows.append([cloth, made, per])
    if not rows:
        raise BookError(f"{where}: table: no rows")
    return {"kind": "vendorpairs", "rows": rows}


# ---- the book -------------------------------------------------------------------------------


def _claims(export: Export | None) -> dict[int, dict]:
    if export is None:
        return {}
    return {row["claim_id"]: row for row in export.tables.get("claims", []) if row["claim_id"]}


TYPOGRAPHIC = {
    "\u2018": "'",
    "\u2019": "'",
    "\u201c": '"',
    "\u201d": '"',
    "\u2013": "-",
    "\u2014": "-",
    "\u2026": "...",
    "\u00a0": " ",
}


def plain(text: str | None) -> str | None:
    """Text the game fonts can draw, for AHSync's sentences (the book's own text is refused
    instead, check_text): typographic quotes and dashes as ASCII, anything else outside ASCII
    left out, the spaces collapsed."""
    if text is None:
        return None
    for a, b in TYPOGRAPHIC.items():
        text = text.replace(a, b)
    text = re.sub(r"[^\x20-\x7e]", "", text)
    return re.sub(r"\s+", " ", text).strip()


def rumour_record(row: Mapping) -> dict:
    """A claim of the export as the book shows it: AHSync's own sentence and the sources."""
    return {
        "claim": plain(row.get("claim") or row.get("subject")),
        "kind": row["kind"],
        "status": row["status"],
        "subject": plain(row.get("subject")),
        "sources": _sources(row),
    }


def _sources(row: Mapping) -> list[list]:
    out = []
    for s in row.get("sources") or []:
        link = s.get("link")
        if not link or not str(link).startswith("http"):
            continue  # only web links leave AHSync (B10, 5b22d70)
        out.append([s.get("channel"), s.get("published"), link])
    return out


def read_page(path: Path, root: Path) -> tuple[str, str, dict, str]:
    where = str(path.relative_to(root)).replace("\\", "/")
    chapter = path.parent.name
    slug = path.stem
    if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", slug):
        raise BookError(f"{where}: the file name is the page id: lowercase words and dashes")
    header, body = split_front(path.read_text(encoding="utf-8"), where)
    return slug, chapter, header, body


def add_book(
    world: World,
    export: Export | None,
    content: Path,
    transforms: Mapping[int, Transform] | None = None,
) -> list[str]:
    """Reads `content` (book.toml and <chapter>/<slug>.md) into the world's book records."""
    book_file = content / "book.toml"
    if not book_file.is_file():
        raise BookError(f"{book_file}: missing")
    with book_file.open("rb") as fh:
        book = tomllib.load(fh)
    clients = book.get("clients", ["forever"])
    if world.client not in clients:
        # the pages name one client's ids and places: another client's build carries no book
        note = f"book: written for {', '.join(clients)}, not built for {world.client}"
        world.notes.append(note)
        return [note]
    claims = _claims(export)
    chapters: dict[str, dict] = {}
    for c in book.get("chapter", []):
        for key in ("id", "name", "order"):
            if key not in c:
                raise BookError(f"book.toml chapter: missing `{key}`")
        check_text(c["name"], f"book.toml chapter {c['id']}")
        check_text(c.get("opening", ""), f"book.toml chapter {c['id']}")
        chapters[c["id"]] = {
            "name": c["name"],
            "order": c["order"],
            "opening": c.get("opening"),
            "active": int(c.get("active", 5)),
        }
    pages: dict[str, dict] = {}
    rumours: dict[int, dict] = {}
    for path in sorted(content.glob("*/*.md")):
        slug, chapter, header, body = read_page(path, content)
        where = f"{chapter}/{slug}.md"
        if chapter not in chapters:
            raise BookError(f"{where}: chapter {chapter} is not in book.toml")
        if slug in pages:
            raise BookError(f"{where}: the page id {slug} is used twice")
        for key in ("title", "levels", "added"):
            if key not in header:
                raise BookError(f"{where}: missing `{key}`")
        check_text(header["title"], where)
        for item in header.get("meta") or []:
            check_text(item, f"{where}: meta")
        levels = header["levels"]
        if not (isinstance(levels, list) and len(levels) == 2 and levels[0] <= levels[1]):
            raise BookError(f"{where}: `levels` is [low, high]")
        zones = [int(z) for z in header.get("zones") or []]
        for z in zones:
            if world.get("zone", z) is None:
                raise BookError(f"{where}: zone {z} is not in the world")
        shelf = header.get("shelf", "active")
        if shelf not in SHELVES:
            raise BookError(f"{where}: shelf must be one of {SHELVES}")
        blocks = parse_body(body, where)
        texts = block_texts(blocks)
        for text in texts:
            check_text(text, where)
        refs = entity_refs(texts, world, where)
        page_rumours = []
        for i, r in enumerate(header.get("rumours") or [], 1):
            claim_id = r.get("claim")
            row = claims.get(claim_id)
            if row is None:
                raise BookError(f"{where}: rumour {i}: claim {claim_id} is not in the export")
            stamp = r.get("stamp") or STATUS_STAMP.get(row["status"] or "", "open")
            if stamp not in STAMPS:
                raise BookError(f"{where}: rumour {i}: stamp must be one of {STAMPS}")
            if r.get("why"):
                check_text(r["why"], f"{where}: rumour {i}")
            page_rumours.append([claim_id, stamp, r.get("why")])
            rumours[claim_id] = rumour_record(row)
        markers = {b[0] for b in blocks}
        plate = None
        if header.get("plate"):
            spec = header["plate"]
            if spec.get("kind") == "spot":
                plate = spot_plate(spec, world, transforms, where, zones)
            elif spec.get("kind") == "flow":
                plate = flow_plate(spec, where)
            else:
                raise BookError(f"{where}: plate kind must be spot or flow")
        live = check_live(header["live"], world, where) if header.get("live") else None
        table = check_table(header["table"], world, where) if header.get("table") else None
        for name, value in (("plate", plate), ("live", live), ("table", table)):
            if (value is None) != (name not in markers):
                raise BookError(f"{where}: [{name}] and the {{{name}}} line go together")
        pages[slug] = {
            "name": header["title"],
            "chapter": chapter,
            "order": header.get("order", 50),
            "levelMin": levels[0],
            "levelMax": levels[1],
            "zones": zones or None,
            "meta": list(header.get("meta") or []) or None,
            "blocks": blocks,
            "rumours": page_rumours or None,
            "plate": plate,
            "live": live,
            "table": table,
            "refs": refs or None,
            "shelf": shelf,
            "pinned": bool(header.get("pinned", False)) or None,
            "added": header["added"],
            "updated": header.get("updated", header["added"]),
        }
    # tombstones: retired pages keep their id for good, so a bookmark still says what happened
    for i, t in enumerate(book.get("retired", []), 1):
        for key in ("id", "title", "date", "reason"):
            if key not in t:
                raise BookError(f"book.toml retired {i}: missing `{key}`")
        if t["id"] in pages:
            raise BookError(f"book.toml retired {i}: {t['id']} is still a page")
        if t.get("successor") and t["successor"] not in pages:
            raise BookError(f"book.toml retired {i}: successor {t['successor']} is not a page")
        check_text(t["title"], f"book.toml retired {t['id']}")
        check_text(t["reason"], f"book.toml retired {t['id']}")
        pages[t["id"]] = {
            "name": t["title"],
            "chapter": t.get("chapter"),
            "shelf": "retired",
            "retired": t["date"],
            "reason": t["reason"],
            "successor": t.get("successor"),
        }
    news = []
    for i, n in enumerate(book.get("news", []), 1):
        for key in ("date", "text"):
            if key not in n:
                raise BookError(f"book.toml news {i}: missing `{key}`")
        check_text(n["text"], f"book.toml news {i}")
        if n.get("page") and n["page"] not in pages:
            raise BookError(f"book.toml news {i}: page {n['page']} is not a page")
        news.append(n)
    # newest first; the entry's id is its place in that order
    news.sort(key=lambda n: (n["date"], n["text"]), reverse=True)
    for cid, c in sorted(chapters.items()):
        world.add("chapter", cid, c)
    for pid, p in sorted(pages.items()):
        world.add("page", pid, p)
    for claim_id, r in sorted(rumours.items()):
        world.add("rumour", claim_id, r)
    for i, n in enumerate(news, 1):
        world.add("news", i, {"date": n["date"], "text": n["text"], "page": n.get("page")})
    active = sum(1 for p in pages.values() if p["shelf"] == "active")
    notes = [
        f"book: {len(chapters)} chapters, {active} active pages, "
        f"{sum(1 for p in pages.values() if p['shelf'] == 'back')} on the back shelf, "
        f"{sum(1 for p in pages.values() if p['shelf'] == 'retired')} retired, "
        f"{len(rumours)} rumours, {len(news)} news"
    ]
    for cid, c in sorted(chapters.items()):
        n = sum(1 for p in pages.values() if p["chapter"] == cid and p["shelf"] == "active")
        if n > c["active"]:
            notes.append(f"book: chapter {cid} has {n} active pages, more than its {c['active']}")
    world.notes.extend(notes)
    return notes


def book_toc(world: World) -> dict:
    """Index book.toc: the chapters in order, each with its active pages in order."""
    chapters = sorted(
        world.records.get("chapter", {}).items(), key=lambda kv: (kv[1]["order"], kv[0])
    )
    pages = world.records.get("page", {})
    out: dict = {"chapters": [cid for cid, _ in chapters], "pages": {}}
    for cid, _ in chapters:
        ids = [
            pid
            for pid, p in pages.items()
            if p.get("chapter") == cid and p.get("shelf") == "active"
        ]
        ids.sort(key=lambda pid: (pages[pid].get("order", 50), pid))
        out["pages"][cid] = ids
    return out
