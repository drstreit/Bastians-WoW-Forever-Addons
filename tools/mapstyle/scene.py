"""The Bastian map's scene (ADR 0027): the layers `clientdump mapdata` writes per ADT tile, read
into numpy arrays, and a region of tiles joined into one scene. Names come from the community
listfile (build time only, nothing of it ships): a ground texture or a model is classed by its
path.

A tile's rasters are n x n pixels, row 0 at the tile's north edge, column 0 at its west edge
(client-extraction.md "mapdata"); a region puts tile (x, y) at rows y * n, columns x * n."""

from __future__ import annotations

import gzip
import struct
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

from .draw import grow, shrink

TILE_YARDS = 1600.0 / 3
ORIGIN = 32 * TILE_YARDS
DOODAD = np.dtype(
    [("fdid", "<u4")]
    + [(f, "<f4") for f in ("wx", "wy", "wz", "scale", "heading", "radius", "height")]
)
WMO = np.dtype([("fdid", "<u4"), ("wx", "<f4"), ("wy", "<f4"), ("wz", "<f4")])


@dataclass
class Tile:
    x: int
    y: int
    n: int
    ground: np.ndarray  # f32, NaN = a hole or no terrain
    liquid: np.ndarray  # u16 LiquidType, 0 = none
    surface: np.ndarray  # f32, NaN = no liquid
    building: np.ndarray  # f32, NaN = no WMO face
    indoor: np.ndarray  # u8
    interior: np.ndarray  # f32, NaN = no indoor WMO face (a building's footprint)
    floor: np.ndarray  # f32, the lowest indoor face; a roof lies where the top is well above it
    object: np.ndarray  # f32, NaN = no M2 collision face
    area: np.ndarray  # u32 16 x 16
    textures: dict[int, np.ndarray]  # FileDataID -> u8 weights
    doodads: np.ndarray  # rows: fdid, wx, wy, wz, scale, heading, radius, height
    wmos: np.ndarray  # rows: fdid, wx, wy, wz


def read_tile(path: Path) -> Tile:
    raw = gzip.decompress(path.read_bytes())
    if raw[:4] != b"BMDT":
        raise ValueError(f"{path}: not a mapdata tile")
    version, x, y, n = struct.unpack_from("<Iiii", raw, 4)
    if version != 3:
        raise ValueError(f"{path}: version {version}")
    pos = 20
    count = n * n

    def take(dtype: str, items: int) -> np.ndarray:
        nonlocal pos
        arr = np.frombuffer(raw, dtype=dtype, count=items, offset=pos)
        pos += arr.nbytes
        return arr

    ground = take("<f4", count).reshape(n, n)
    liquid = take("<u2", count).reshape(n, n)
    surface = take("<f4", count).reshape(n, n)
    building = take("<f4", count).reshape(n, n)
    indoor = take("u1", count).reshape(n, n)
    interior = take("<f4", count).reshape(n, n)
    floor = take("<f4", count).reshape(n, n)
    obj = take("<f4", count).reshape(n, n)
    area = take("<u4", 256).reshape(16, 16)
    textures: dict[int, np.ndarray] = {}
    (k,) = struct.unpack_from("<i", raw, pos)
    pos += 4
    for _ in range(k):
        (fdid,) = struct.unpack_from("<I", raw, pos)
        pos += 4
        textures[fdid] = take("u1", count).reshape(n, n)
    (k,) = struct.unpack_from("<i", raw, pos)
    pos += 4
    doodads = np.frombuffer(raw, dtype=DOODAD, count=k, offset=pos)
    pos += doodads.nbytes
    (k,) = struct.unpack_from("<i", raw, pos)
    pos += 4
    wmos = np.frombuffer(raw, dtype=WMO, count=k, offset=pos)
    return Tile(
        x,
        y,
        n,
        ground,
        liquid,
        surface,
        building,
        indoor,
        interior,
        floor,
        obj,
        area,
        textures,
        doodads,
        wmos,
    )


@dataclass
class Region:
    """Tiles x0..x1, y0..y1 joined; missing tiles stay NaN / 0."""

    x0: int
    y0: int
    cols: int
    rows: int
    n: int
    ground: np.ndarray
    liquid: np.ndarray
    surface: np.ndarray
    building: np.ndarray
    indoor: np.ndarray
    interior: np.ndarray
    floor: np.ndarray
    object: np.ndarray
    textures: dict[int, np.ndarray]
    doodads: np.ndarray
    wmos: np.ndarray
    # bool: the pixel lies in a tile the map has and is no empty hole (the rest is open sea)
    present: np.ndarray
    tiles: list[tuple[int, int]] = field(default_factory=list)
    top: int = 0  # pixel offsets of a cropped region inside its tiles
    left: int = 0

    @property
    def row0(self) -> int:
        """The world raster's row of pixel row 0 (tile rows of n pixels from the north edge)."""
        return self.y0 * self.n + self.top

    @property
    def col0(self) -> int:
        return self.x0 * self.n + self.left

    def crop(self, top: int, left: int, height: int, width: int) -> Region:
        """The pixels top..top+height, left..left+width; things far outside are dropped."""
        sl = (slice(top, top + height), slice(left, left + width))
        out = Region(
            self.x0,
            self.y0,
            self.cols,
            self.rows,
            self.n,
            self.ground[sl],
            self.liquid[sl],
            self.surface[sl],
            self.building[sl],
            self.indoor[sl],
            self.interior[sl],
            self.floor[sl],
            self.object[sl],
            {k: v[sl] for k, v in self.textures.items()},
            self.doodads,
            self.wmos,
            self.present[sl],
            self.tiles,
            self.top + top,
            self.left + left,
        )
        row, col = out.pixel_of(self.doodads["wx"].astype("f8"), self.doodads["wy"].astype("f8"))
        keep = (row >= -8) & (row < height + 8) & (col >= -8) & (col < width + 8)
        out.doodads = self.doodads[keep]
        return out

    @property
    def yards_per_pixel(self) -> float:
        return TILE_YARDS / self.n

    def pixel_of(self, wx: np.ndarray, wy: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        """World yards -> (row, col) in the region's pixels (floats)."""
        rx = ORIGIN - wy  # east
        rz = ORIGIN - wx  # south
        col = rx / self.yards_per_pixel - self.col0 - 0.5
        row = rz / self.yards_per_pixel - self.row0 - 0.5
        return row, col


def empty_holes(
    ground: np.ndarray, building: np.ndarray, obj: np.ndarray, liquid: np.ndarray, n: int
) -> np.ndarray:
    """The terrain holes with nothing in them (no WMO, no model, no liquid): open sea, not land.
    Zephras Isle floats inside tiles that are holes all around it, which were drawn as blocks of
    land (06.11.2026). A spot narrower than a chunk (n / 16 pixels) stays land and takes its
    neighbours' height; an inlet of a wide hole up to a chunk deep stays sea."""
    void = np.isnan(ground) & np.isnan(building) & np.isnan(obj) & (liquid == 0)
    if not void.any():
        return void
    r = max(1, n // 32)
    return void & grow(shrink(void, r), 2 * r)


def read_region(folder: Path, x0: int, y0: int, x1: int, y1: int, n: int | None = None) -> Region:
    """The tiles x0..x1, y0..y1 joined. `n` (a tile's pixels) allows a range without any tile: open
    sea; without it such a range is an error."""
    tiles = {}
    for path in sorted(folder.glob("*.bmd.gz")):
        tx, ty = (int(v) for v in path.name.split(".")[0].split("_"))
        if x0 <= tx <= x1 and y0 <= ty <= y1:
            tiles[(tx, ty)] = read_tile(path)
    if not tiles and n is None:
        raise ValueError(f"{folder}: no tiles in {x0},{y0} to {x1},{y1}")
    n = next(iter(tiles.values())).n if tiles else n
    cols, rows = x1 - x0 + 1, y1 - y0 + 1
    h, w = rows * n, cols * n

    def blank(dtype, fill):
        return np.full((h, w), fill, dtype=dtype)

    ground, surface = blank("f4", np.nan), blank("f4", np.nan)
    building, obj, interior = blank("f4", np.nan), blank("f4", np.nan), blank("f4", np.nan)
    floor = blank("f4", np.nan)
    liquid, indoor = blank("u2", 0), blank("u1", 0)
    present = blank("bool", False)
    textures: dict[int, np.ndarray] = {}
    doodads, wmos = [np.zeros(0, DOODAD)], [np.zeros(0, WMO)]
    for (tx, ty), t in sorted(tiles.items()):
        sl = (slice((ty - y0) * n, (ty - y0 + 1) * n), slice((tx - x0) * n, (tx - x0 + 1) * n))
        ground[sl], surface[sl], building[sl], obj[sl] = t.ground, t.surface, t.building, t.object
        liquid[sl], indoor[sl], interior[sl], floor[sl] = t.liquid, t.indoor, t.interior, t.floor
        present[sl] = True
        for fdid, wgt in t.textures.items():
            if fdid not in textures:
                textures[fdid] = blank("u1", 0)
            textures[fdid][sl] = wgt
        doodads.append(t.doodads)
        wmos.append(t.wmos)
    present &= ~empty_holes(ground, building, obj, liquid, n)
    return Region(
        x0,
        y0,
        cols,
        rows,
        n,
        ground,
        liquid,
        surface,
        building,
        indoor,
        interior,
        floor,
        obj,
        textures,
        np.concatenate(doodads),
        np.concatenate(wmos),
        present,
        sorted(tiles),
    )


def listfile_names(listfile: Path, wanted: set[int]) -> dict[int, str]:
    """FileDataID -> lower-case path for the ids asked for."""
    out: dict[int, str] = {}
    with listfile.open(encoding="utf-8", errors="replace") as f:
        for line in f:
            head, _, path = line.partition(";")
            if head.isdigit() and int(head) in wanted:
                out[int(head)] = path.strip().lower()
    return out


def classify(name: str, table: dict[str, list[str]]) -> str | None:
    """The first class whose keywords one appears in the path (table order)."""
    for cls, words in table.items():
        if any(w in name for w in words):
            return cls
    return None
