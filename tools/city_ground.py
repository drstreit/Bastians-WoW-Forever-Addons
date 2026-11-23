"""The cities inside the ground on the world map (docs/addons/map.md "Cities inside the ground"):
each sheet tile's mask, cut to the city's plan from the walk mesh, so the world map draws the city
and not the parchment around it.

Usage: python tools/city_ground.py [<ui map id> ...] [--addon addons/Bastians_Map_Art]
           [--meshes .local/out/navmesh_forever] [--clientdump <exe>]

The places are those tools/cities.toml marks `ground = true` (Ironforge and the Undercity). For
each the walk mesh is rastered onto a quarter of its sheet (`clientdump navmesh-walk` through the
place's UiMap bounds, from its seed, as tools/city_fit.py does), and the indoor floors become the
plan: closed over the walls between them, holes filled (the Great Forge, the Undercity's inner
ring), specks dropped, grown a little past the floor so the painted walls show, the edge feathered.
Each tile with some of the plan gets `Generated/Cities/<ui>_<row>_<col>_ground.tga` (128 px, white,
the alpha is the plan, over the tile's visible part); a tile without any gets none, and the world
map leaves it out. Masks of a place no longer marked, or of tiles that lost their plan, are
removed. Then the manifest is written again (tools/city_sheet.py), naming each place's masked
tiles (`ground`). Deterministic. Needs the sheet's tiles (city_sheet.py), the walk mesh
(`tools/nav_build.py --navmesh`), a built clientdump, numpy and Pillow.
"""

from __future__ import annotations

import argparse
import importlib.util
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCALE = 4  # sheet pixels per raster pixel: about a yard in Ironforge and the Undercity
CLOSE = 8  # raster pixels: the walls between two floors are closed over
GROW = 3  # raster pixels past the floor: the painted wall around it
FEATHER = 3.0  # raster pixels of the edge's blur
MIN_AREA = 1500  # raster pixels: a piece of plan smaller than this is a speck (a cellar, a stair)
MASK = 128  # pixels of a tile's mask, square
EMPTY = 4  # a tile whose mask stays below this alpha everywhere has no plan
INDOOR, DEEP = 4, 16  # the walk raster's bits (NavmeshView.Walk)


def tool(name: str):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(f"{name}.py"))
    module = importlib.util.module_from_spec(spec)
    sys.modules.setdefault(name, module)
    spec.loader.exec_module(module)
    return module


def _grow(img, r: int):
    from PIL import ImageFilter

    return img.filter(ImageFilter.MaxFilter(2 * r + 1)) if r > 0 else img


def _shrink(img, r: int):
    from PIL import ImageFilter

    return img.filter(ImageFilter.MinFilter(2 * r + 1)) if r > 0 else img


def pieces(mask):
    """The 4-connected pieces of a boolean array: each pixel of a piece gets the flat index of its
    first pixel, every other pixel -1 (numpy alone: each step takes the smallest label of the
    neighbours, then every label jumps to its label's label)."""
    import numpy as np

    h, w = mask.shape
    big = np.iinfo(np.int64).max
    lab = np.where(mask, np.arange(h * w, dtype=np.int64).reshape(h, w), big)
    while True:
        low = lab.copy()
        low[1:, :] = np.minimum(low[1:, :], lab[:-1, :])
        low[:-1, :] = np.minimum(low[:-1, :], lab[1:, :])
        low[:, 1:] = np.minimum(low[:, 1:], lab[:, :-1])
        low[:, :-1] = np.minimum(low[:, :-1], lab[:, 1:])
        low = np.where(mask, low, big)
        flat = low.ravel()
        on = flat != big
        flat[on] = flat[flat[on]]  # a label is a pixel of the same piece with a smaller label
        if np.array_equal(low, lab):
            break
        lab = low
    return np.where(mask, lab, -1)


def _fill_holes(img):
    """Every pixel the outside cannot reach becomes plan."""
    import numpy as np
    from PIL import Image

    plan = np.asarray(img) > 0
    lab = pieces(np.pad(~plan, 1, constant_values=True))
    outside = (lab == 0)[1:-1, 1:-1]  # the piece of the padded corner
    return Image.fromarray(np.where(outside, 0, 255).astype("u1"))


def _drop_specks(img, min_area: int):
    """The pieces of plan (4-connected) of at least min_area pixels."""
    import numpy as np
    from PIL import Image

    lab = pieces(np.asarray(img) > 0)
    ids, counts = np.unique(lab[lab >= 0], return_counts=True)
    keep = np.isin(lab, ids[counts >= min_area])
    return Image.fromarray(np.where(keep, 255, 0).astype("u1"))


def footprint(
    walk, close: int = CLOSE, grow: int = GROW, feather: float = FEATHER, min_area: int = MIN_AREA
):
    """The city's plan from a walk raster (bits per pixel, NavmeshView.Walk): the indoor floors
    that are no deep water, closed, filled, without specks, grown and feathered. -> the alpha,
    a uint8 array of the raster's shape."""
    import numpy as np
    from PIL import Image, ImageFilter

    h, w = walk.shape
    floor = ((walk & INDOOR) != 0) & ((walk & DEEP) == 0)
    pad = close + 2
    img = Image.new("L", (w + 2 * pad, h + 2 * pad), 0)
    img.paste(Image.fromarray(floor.astype("u1") * 255), (pad, pad))
    img = _shrink(_grow(img, close), close).crop((pad, pad, pad + w, pad + h))
    img = _drop_specks(_fill_holes(img), min_area)
    img = _grow(img, grow)
    if feather > 0:
        img = img.filter(ImageFilter.GaussianBlur(feather))
    return np.asarray(img, dtype="u1")


def tile_masks(alpha, width: int, height: int, tile: int = 1024, size: int = MASK) -> dict:
    """Each tile's mask over its visible part of the sheet (width x height pixels, the padding
    left out as the world map's texture coordinates leave it out): (row, col) -> a size x size
    RGBA image, or None for a tile without plan."""
    import numpy as np
    from PIL import Image

    h, w = alpha.shape
    fx, fy = w / width, h / height
    plane = Image.fromarray(alpha)
    out = {}
    rows, cols = -(-height // tile), -(-width // tile)
    for row in range(rows):
        for col in range(cols):
            x0, x1 = col * tile, min(width, (col + 1) * tile)
            y0, y1 = row * tile, min(height, (row + 1) * tile)
            box = (x0 * fx, y0 * fy, x1 * fx, y1 * fy)
            part = plane.resize((size, size), Image.BILINEAR, box=box)
            if int(np.asarray(part).max()) < EMPTY:
                out[row, col] = None
                continue
            white = Image.new("L", (size, size), 255)
            out[row, col] = Image.merge("RGBA", (white, white, white, part))
    return out


def tga(image) -> bytes:
    """An uncompressed 32-bit TGA, top-left origin, 8 bits of alpha; no footer, so the same image
    gives the same bytes."""
    import numpy as np

    w, h = image.size
    head = bytes([0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0]) + w.to_bytes(2, "little")
    head += h.to_bytes(2, "little") + bytes([32, 0x28])  # 32 bpp, 8 alpha bits, top-left
    rgba = np.asarray(image.convert("RGBA"), dtype="u1")
    return head + rgba[..., [2, 1, 0, 3]].tobytes()


def write_masks(ui: int, place: dict, alpha, entry: dict, addon: Path, cs) -> int:
    """Writes the place's masks, removes the ones of tiles without plan. -> how many."""
    written = 0
    for (row, col), image in sorted(tile_masks(alpha, entry["w"], entry["h"]).items()):
        path = cs.ground_file(addon, ui, row, col)
        if image is None:
            path.unlink(missing_ok=True)
            continue
        cs.atomic_write(path, tga(image))
        written += 1
    return written


def remove_masks(ui: int, addon: Path) -> int:
    gone = 0
    for path in (addon / "Generated" / "Cities").glob(f"{ui}_*_ground.tga"):
        path.unlink()
        gone += 1
    return gone


def raster(place: dict, entry: dict, mesh: Path, exe: Path, fit):
    """The walk raster on a quarter of the sheet, or a reason why not."""
    import numpy as np

    w, h = round(entry["w"] / SCALE), round(entry["h"] / SCALE)
    with tempfile.TemporaryDirectory(prefix="bastians-ground-") as tmp:
        raw = Path(tmp) / "walk.bin"
        cmd = fit.walk_command(exe, mesh, raw, place, w, h)
        done = subprocess.run(cmd, capture_output=True, text=True, check=False)
        if done.returncode != 0 or not raw.is_file():
            return f"clientdump failed: {done.stderr.strip()[-300:]}"
        return np.fromfile(raw, "u1").reshape(h, w)


def main() -> int:
    cs, fit = tool("city_sheet"), tool("city_fit")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("ui", type=int, nargs="*")
    parser.add_argument("--addon", type=Path, default=cs.ADDON)
    parser.add_argument("--meshes", type=Path, default=ROOT / ".local" / "out" / "navmesh_forever")
    parser.add_argument(
        "--clientdump",
        type=Path,
        default=ROOT / "tools" / "clientdump" / "bin" / "Release" / "net10.0" / "clientdump.exe",
    )
    args = parser.parse_args()
    unknown = sorted(set(args.ui) - set(cs.PLACES))
    if unknown:
        parser.error(f"not in {cs.REGISTRY.name}: {unknown}")
    failed = 0
    for ui, place in sorted(cs.PLACES.items()):
        if args.ui and ui not in args.ui:
            continue
        if not place["ground"]:
            gone = remove_masks(ui, args.addon)
            if gone:
                print(f"{ui} {place['name']}: not marked ground, {gone} masks removed")
            continue
        entry = cs.kept(ui, place, args.addon)
        mesh = args.meshes / f"{fit.MESHES[place['continent']]}.navmesh"
        if not (entry and mesh.is_file()):
            lacks = f"mesh {mesh.name}" if entry else "tiles (tools/city_sheet.py)"
            print(f"{ui} {place['name']}: skipped, no {lacks}")
            failed += 1
            continue
        walk = raster(place, entry, mesh, args.clientdump, fit)
        if isinstance(walk, str):
            print(f"{ui} {place['name']}: {walk}")
            failed += 1
            continue
        alpha = footprint(walk)
        written = write_masks(ui, place, alpha, entry, args.addon, cs)
        share = float((alpha >= 128).mean())
        print(
            f"{ui} {place['name']}: {written} of {entry['rows'] * entry['cols']} tiles masked, "
            f"the plan is {share:.0%} of the sheet"
        )
    entries = cs.relist(args.addon)
    print(
        f"manifest: {len(entries)} places, ground on "
        f"{[e['ui'] for e in entries if e.get('ground')]}"
    )
    print("new files need a full restart of the game (CLAUDE.md section 12)")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
