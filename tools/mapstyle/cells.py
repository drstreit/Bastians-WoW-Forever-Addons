"""The Bastian map's cells (ADR 0027): a continent drawn in every style as the textures the Map
loads.

Near cells hold 4 x 4 ADT tiles at 256 pixels each (1024 x 1024, levels 3 and up); far cells hold
8 x 8 tiles at 64 pixels each (512 x 512, levels 0 to 2), made from the near cells and, where the
map has no tile, from sea cells: drawn like a near cell, so a far cell's sea is the style's own
drawn sea everywhere, but kept out of the addon (`<style>/sea/`). The far cells fill the rectangle
around the continent. A near cell is
drawn from its tiles plus a border of `MARGIN` pixels on every side, then cut to its own square, so
blurs and edges see their neighbours and the cells meet without a seam; the paper's grain, the
strokes and the tones are anchored at the world (draw.noise), not at the image.

Each cell is written as a raw RGBA file (`RGBA`, u32 width, u32 height, then the pixels) for
`clientdump blp`, which encodes them as BLP with DXT1 and mipmaps."""

from __future__ import annotations

import json
import struct
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np
from PIL import Image

from .labels import Label, place_labels
from .render import prepare, render
from .scene import listfile_names, read_region, read_tile

NEAR_SPAN = 4  # ADT tiles per near cell side
FAR_SPAN = 8
FAR_PIXELS = 64  # per ADT in a far cell
MARGIN = 32  # pixels drawn around a near cell (66 yards at 256 px per ADT)


def tiles_of(folder: Path) -> list[tuple[int, int]]:
    out = []
    for path in folder.glob("*.bmd.gz"):
        x, y = (int(v) for v in path.name.split(".")[0].split("_"))
        out.append((x, y))
    return sorted(out)


def write_rgba(path: Path, img: Image.Image) -> None:
    rgba = img.convert("RGBA")
    tmp = path.with_suffix(".tmp")
    tmp.write_bytes(b"RGBA" + struct.pack("<II", rgba.width, rgba.height) + rgba.tobytes())
    tmp.replace(path)


def read_rgba(path: Path) -> Image.Image:
    raw = path.read_bytes()
    w, h = struct.unpack_from("<II", raw, 4)
    return Image.frombytes("RGBA", (w, h), raw[12:])


def sea_slots(cells: list[tuple[int, int]]) -> list[tuple[int, int]]:
    """The near cells' places without a tile inside the rectangle of far cells around `cells`."""
    per = FAR_SPAN // NEAR_SPAN
    xs, ys = [cx // per for cx, _ in cells], [cy // per for _, cy in cells]
    have = set(cells)
    return [
        (cx, cy)
        for cx in range(min(xs) * per, (max(xs) + 1) * per)
        for cy in range(min(ys) * per, (max(ys) + 1) * per)
        if (cx, cy) not in have
    ]


def near_cell(job: dict) -> list[str]:
    """Draws one near cell (or sea cell: `part`) in every style; returns the files written."""
    folder, cx, cy = Path(job["data"]), job["cx"], job["cy"]
    cfg, out, part = job["cfg"], Path(job["out"]), job.get("part", "near")
    files = [out / style / part / f"{job['continent']}_{cx}_{cy}.rgba" for style in job["styles"]]
    if not job.get("force") and all(f.is_file() for f in files):
        return []  # drawn by an earlier run: the build resumes
    x0, y0 = cx * NEAR_SPAN, cy * NEAR_SPAN
    region = read_region(folder, x0 - 1, y0 - 1, x0 + NEAR_SPAN, y0 + NEAR_SPAN, job["n"])
    n = region.n
    # the region starts at tile x0 - 1 (or later when the map has none there): cut to the cell plus
    # the margin, in the region's pixels
    top = (y0 - region.y0) * n - MARGIN
    left = (x0 - region.x0) * n - MARGIN
    size = NEAR_SPAN * n + 2 * MARGIN
    region = _pad_crop(region, top, left, size)
    ids = set(region.textures) | {int(f) for f in region.doodads["fdid"]}
    names = {i: job["names"][str(i)] for i in ids if str(i) in job["names"]}
    p = prepare(region, names, {int(k): v for k, v in job["liquids"].items()}, cfg)
    written = []
    for style in job["styles"]:
        img = render(p, style, cfg)  # no names in the cells since R27.6: the Map draws them
        img = img.crop((MARGIN, MARGIN, MARGIN + NEAR_SPAN * n, MARGIN + NEAR_SPAN * n))
        path = out / style / part / f"{job['continent']}_{cx}_{cy}.rgba"
        path.parent.mkdir(parents=True, exist_ok=True)
        write_rgba(path, img)
        written.append(str(path))
    return written


def _pad_crop(region, top: int, left: int, size: int):
    """A crop that may reach outside the region's tiles (the map's edge): the region is read with a
    tile of border, so a negative start only happens where the map has no tile; there the rows and
    columns stay outside `present` (open sea)."""
    h, w = region.ground.shape
    if top >= 0 and left >= 0 and top + size <= h and left + size <= w:
        return region.crop(top, left, size, size)
    pad_t, pad_l = max(0, -top), max(0, -left)
    pad_b, pad_r = max(0, top + size - h), max(0, left + size - w)

    def pad(a, fill):
        return np.pad(a, ((pad_t, pad_b), (pad_l, pad_r)), constant_values=fill)

    region.ground = pad(region.ground, np.nan)
    region.surface = pad(region.surface, np.nan)
    region.building = pad(region.building, np.nan)
    region.interior = pad(region.interior, np.nan)
    region.floor = pad(region.floor, np.nan)
    region.object = pad(region.object, np.nan)
    region.liquid = pad(region.liquid, 0)
    region.indoor = pad(region.indoor, 0)
    region.present = pad(region.present, False)
    region.textures = {k: pad(v, 0) for k, v in region.textures.items()}
    region.top -= pad_t
    region.left -= pad_l
    return region.crop(top + pad_t, left + pad_l, size, size)


def far_cells(out: Path, continent: int, style: str) -> list[str]:
    """Far cells from the near and sea cells: each scaled to FAR_PIXELS per ADT, four to a far
    cell. A far cell with a cell still undrawn (a run of some tiles only) is left as it is."""
    near = {}
    for part in ("near", "sea"):
        for path in (out / style / part).glob(f"{continent}_*.rgba"):
            _, cx, cy = path.stem.split("_")
            near[(int(cx), int(cy))] = path
    per = FAR_SPAN // NEAR_SPAN
    side = NEAR_SPAN * FAR_PIXELS
    written = []
    for fx, fy in sorted({(cx // per, cy // per) for cx, cy in near}):
        slots = [(dx, dy) for dx in range(per) for dy in range(per)]
        if any((fx * per + dx, fy * per + dy) not in near for dx, dy in slots):
            continue
        canvas = Image.new("RGBA", (FAR_SPAN * FAR_PIXELS,) * 2)
        for dx, dy in slots:
            img = read_rgba(near[(fx * per + dx, fy * per + dy)])
            img = img.resize((side, side), Image.Resampling.LANCZOS)
            canvas.paste(img, (dx * side, dy * side))
        path = out / style / "far" / f"{continent}_{fx}_{fy}.rgba"
        path.parent.mkdir(parents=True, exist_ok=True)
        write_rgba(path, canvas)
        written.append(str(path))
    return written


def names_for(listfile: Path, folder: Path, cache: Path) -> dict[str, str]:
    """The listfile names of the continent's textures and models, cached beside the tiles."""
    if cache.is_file():
        return json.loads(cache.read_text(encoding="utf-8"))
    ids: set[int] = set()
    for path in sorted(folder.glob("*.bmd.gz")):
        t = read_tile(path)
        ids |= set(t.textures) | {int(f) for f in t.doodads["fdid"]}
    names = {str(k): v for k, v in sorted(listfile_names(listfile, ids).items())}
    cache.write_text(json.dumps(names, sort_keys=True), encoding="utf-8")
    return names


def continent_labels(data: Path, areas: Path | None) -> list[Label]:
    """The subzone labels of the continent from every tile's chunk areas and the AreaTable dump;
    none without the dump."""
    if not (areas and areas.is_file()):
        return []
    from .labels import area_names

    chunks = {}
    for path in sorted(data.glob("*.bmd.gz")):
        t = read_tile(path)
        chunks[(t.x, t.y)] = t.area
    return place_labels(chunks, area_names(areas))


def build(
    data: Path,
    continent: int,
    out: Path,
    cfg: dict,
    styles: list[str],
    names: dict[str, str],
    liquids: dict[int, str],
    workers: int,
    only: tuple[int, int, int, int] | None = None,
) -> dict:
    """Every near and sea cell of the continent (or of the range `only`), then the far cells."""
    xy = tiles_of(data)
    cells = sorted({(x // NEAR_SPAN, y // NEAR_SPAN) for x, y in xy})
    sea = sea_slots(cells)
    if only:
        x0, y0, x1, y1 = only

        def wanted(cx: int, cy: int) -> bool:
            return (
                x0 // NEAR_SPAN <= cx <= x1 // NEAR_SPAN
                and y0 // NEAR_SPAN <= cy <= y1 // NEAR_SPAN
            )

        cells = [c for c in cells if wanted(*c)]
        sea = [c for c in sea if wanted(*c)]
    n = read_tile(data / f"{xy[0][0]}_{xy[0][1]}.bmd.gz").n
    jobs = [
        {
            "data": str(data),
            "n": n,
            "cx": cx,
            "cy": cy,
            "part": part,
            "cfg": cfg,
            "out": str(out),
            "styles": styles,
            "names": names,
            "liquids": {str(k): v for k, v in liquids.items()},
            "continent": continent,
        }
        for part, slots in (("near", cells), ("sea", sea))
        for cx, cy in slots
    ]
    done = 0
    if workers > 1:
        with ProcessPoolExecutor(max_workers=workers) as pool:
            for _ in pool.map(near_cell, jobs):
                done += 1
                if done % 10 == 0 or done == len(jobs):
                    print(f"  {done}/{len(jobs)} near and sea cells", flush=True)
    else:
        for job in jobs:
            near_cell(job)
    far = {style: far_cells(out, continent, style) for style in styles}
    return {"near": cells, "sea": sea, "far": far}
