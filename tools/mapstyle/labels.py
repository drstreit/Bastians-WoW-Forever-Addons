"""The subzone names of the Bastian map (ADR 0027): every ADT chunk carries its AreaTable id
(clientdump mapdata); a subzone's largest connected patch of chunks gets its name at the patch's
centre. ~~Drawn into the near cells in the style's own face~~ since 27.10.2026 (owner, retail,
R27.6: baked names do not scale and cannot be hidden) the names are data: `names_lua` writes them
for the Map, which draws them live as the layer "Place names" (scaled with the zoom, a toggle)."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from .scene import ORIGIN, TILE_YARDS

CHUNK_YARDS = TILE_YARDS / 16
MIN_CHUNKS = 4  # a patch smaller than this gets no name (a corner of a bigger subzone)
SKIP_WORDS = ("UNUSED", "DND", "DEPRECATED")
LABEL_CHAR_YARDS = 32.0  # a letter at 28 px and 2.08 yards per pixel, with the halo
LABEL_LINE_YARDS = 70.0


@dataclass(frozen=True)
class Label:
    text: str
    wx: float
    wy: float
    chunks: int


def area_names(table: Path) -> dict[int, tuple[str, int]]:
    """AreaTable id -> (name, parent id) from the clientdump JSON dump."""
    data = json.loads(table.read_text(encoding="utf-8"))
    rows = data["rows"] if isinstance(data, dict) and "rows" in data else data
    items = rows.items() if isinstance(rows, dict) else [(r["ID"], r) for r in rows]
    out = {}
    for k, r in items:
        name = r.get("AreaName_lang") or ""
        out[int(k)] = (name, int(r.get("ParentAreaID") or 0))
    return out


def _components(mask: np.ndarray) -> list[np.ndarray]:
    """The 8-connected patches of a mask as boolean arrays, largest first."""
    h, w = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    out = []
    for r0, c0 in zip(*np.nonzero(mask), strict=True):
        if seen[r0, c0]:
            continue
        stack, patch = [(r0, c0)], np.zeros_like(mask, dtype=bool)
        seen[r0, c0] = True
        while stack:
            r, c = stack.pop()
            patch[r, c] = True
            for dr in (-1, 0, 1):
                for dc in (-1, 0, 1):
                    rr, cc = r + dr, c + dc
                    if 0 <= rr < h and 0 <= cc < w and mask[rr, cc] and not seen[rr, cc]:
                        seen[rr, cc] = True
                        stack.append((rr, cc))
        out.append(patch)
    out.sort(key=lambda p: -int(p.sum()))
    return out


def place_labels(
    chunks: dict[tuple[int, int], np.ndarray], names: dict[int, tuple[str, int]]
) -> list[Label]:
    """chunks: tile (x, y) -> its 16 x 16 area ids (row 0 north). One label per subzone (an area
    with a parent) at the centre of its largest patch of MIN_CHUNKS chunks or more."""
    if not chunks:
        return []
    xs = [x for x, _ in chunks]
    ys = [y for _, y in chunks]
    x0, y0 = min(xs), min(ys)
    grid = np.zeros(((max(ys) - y0 + 1) * 16, (max(xs) - x0 + 1) * 16), dtype=np.uint32)
    for (x, y), area in chunks.items():
        grid[(y - y0) * 16 : (y - y0 + 1) * 16, (x - x0) * 16 : (x - x0 + 1) * 16] = area
    out = []
    for area_id in np.unique(grid):
        name, parent = names.get(int(area_id), ("", 0))
        if not name or parent == 0 or any(w in name.upper() for w in SKIP_WORDS):
            continue
        patches = _components(grid == area_id)
        if not patches or patches[0].sum() < MIN_CHUNKS:
            continue
        rows, cols = np.nonzero(patches[0])
        row, col = rows.mean() + 0.5, cols.mean() + 0.5
        rx = (x0 * 16 + col) * CHUNK_YARDS
        rz = (y0 * 16 + row) * CHUNK_YARDS
        out.append(Label(name, ORIGIN - rz, ORIGIN - rx, int(patches[0].sum())))
    # two names whose boxes would overlap: the bigger patch keeps its name
    out.sort(key=lambda lb: (-lb.chunks, lb.text))
    kept: list[Label] = []
    for lb in out:
        w, h = len(lb.text) * LABEL_CHAR_YARDS / 2, LABEL_LINE_YARDS / 2
        if not any(
            abs(lb.wy - k.wy) < w + len(k.text) * LABEL_CHAR_YARDS / 2 and abs(lb.wx - k.wx) < 2 * h
            for k in kept
        ):
            kept.append(lb)
    kept.sort(key=lambda lb: (lb.text, lb.wx, lb.wy))
    return kept


# mapdata's folders -> Map.db2 ids; Zephras Isle's Map.db2 directory is its id
CONTINENT_DIRS = {"Azeroth": 0, "Kalimdor": 1, "2991": 2991}


def _num(v: float) -> str:
    return f"{v:.1f}".rstrip("0").rstrip(".")


def names_lua(
    client: str,
    build: str,
    labels: dict[int, list[Label]],
    named: dict[int, list[dict]] | None = None,
) -> str:
    """Bastians_Map/Generated/Names.lua: { text, wx, wy, chunks } per continent, deterministic;
    with `named` also Blizzard's labels (the Blizzard map's labels.json, ADR 0036), which every
    style shows since 29.10.2026."""
    from .emit import labels_lua

    blocks = []
    for continent in sorted(labels):
        rows = "\n".join(
            f"        {{ {_lua_str(lb.text)}, {_num(lb.wx)}, {_num(lb.wy)}, {lb.chunks} }},"
            for lb in sorted(labels[continent], key=lambda lb: (lb.text, lb.wx, lb.wy))
        )
        if not rows:
            blocks.append(f"      [{continent}] = {{}},")
            continue
        blocks.append(f"      [{continent}] = {{\n{rows}\n      }},")
    counts = ", ".join(f"continent {c}: {len(labels[c])}" for c in sorted(labels))
    named_block = ""
    if named:
        counts += "; Blizzard's labels " + ", ".join(
            f"continent {c}: {len(named[c])}" for c in sorted(named)
        )
        named_block = "\n    labels = {\n" + labels_lua(named, "      ") + "\n    },"
    return f"""-- GENERATED by tools/mapstyle, do not edit
-- The subzone names of the map for {client} ({counts}): the Map draws them as a layer (R27.6)
local B = Bastians or {{}}
Bastians = B
B.deferred = B.deferred or {{}}
B.deferred[#B.deferred + 1] = {{
  "Map.RegisterNames",
  {{
    client = "{client}",
    build = "{build}",
    continents = {{
{chr(10).join(blocks)}
    }},{named_block}
  }},
}}
"""


def _lua_str(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def write_names(
    data_root: Path,
    areas: Path,
    out: Path,
    client: str,
    build: str,
    named: dict[int, list[dict]] | None = None,
) -> dict[int, int]:
    """Every continent folder of `data_root` (mapdata), its labels into `out`, with Blizzard's
    labels when given; -> counts."""
    from .cells import continent_labels

    labels = {}
    for name, continent in CONTINENT_DIRS.items():
        folder = data_root / name
        if folder.is_dir():
            labels[continent] = continent_labels(folder, areas)
    text = names_lua(client, build, labels, named)
    out.parent.mkdir(parents=True, exist_ok=True)
    if not out.is_file() or out.read_text(encoding="utf-8") != text:
        tmp = out.with_suffix(".tmp")
        tmp.write_text(text, encoding="utf-8", newline="\n")
        tmp.replace(out)
    return {c: len(v) for c, v in labels.items()}
