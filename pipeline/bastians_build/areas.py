"""Areas (data.md "Areas: the subzones as places"): the client's subzones as `area` records.

In: the navmesh files `clientdump navmesh` writes per continent (`<Map>.navmesh`, version 2; the
layout in tools/clientdump/Navmesh.cs `Write`), whose area block holds per built ADT tile its 256
terrain chunks' AreaTable ids, and the client's AreaTable (names, parents). No client is needed.

Out: one `area` record per subzone with at least one chunk: its name, the zone it lies in, one
world place (the chunk nearest the mean of its chunks, so a ring or a bent valley still gets a
point inside it), the radius of a disc as large as its chunks (never below one chunk) and the
chunk count. Areas inside cities and instances (WMO interiors, no terrain) have no chunks: they
stay out, unknown, not zero.
"""

from __future__ import annotations

import math
import struct
import zlib
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path

from bastians_build.coords import Spawn, best_map, world_to_map
from bastians_build.model import World
from bastians_build.sources.clientdump import AreaRow
from bastians_build.sources.probe import Transform

TILE = 1600 / 3  # an ADT tile's side in yards
CHUNK = TILE / 16  # a terrain chunk's side (MCNK), 33.3 yards
ORIGIN = 32 * TILE  # the world origin's distance from the tile grid's corner
CHUNKS_PER_TILE = 256
TILE_BYTES = 8 + 4 * CHUNKS_PER_TILE  # i32 x, i32 y, 256 x u32
SLACK = 0.02  # how far outside its zone map's rectangle an area's place may lie (map fractions)


class AreasError(ValueError):
    pass


@dataclass(frozen=True)
class AreaBlock:
    """One navmesh file's area block: area id -> the world centres (wx, wy) of its chunks."""

    map_id: int  # Map.db2 id: 0 Eastern Kingdoms, 1 Kalimdor
    build: str
    version: int
    chunks: dict[int, list[tuple[float, float]]]


@dataclass(frozen=True)
class AreaPlace:
    wx: float
    wy: float
    r: float  # yards
    chunks: int


def chunk_centre(tile_x: int, tile_y: int, cx: int, cy: int) -> tuple[float, float]:
    """World yards of a terrain chunk's centre: tile (x, y) of the grid, chunk (cx, cy) in it."""
    rx = tile_x * TILE + (cx + 0.5) * CHUNK
    rz = tile_y * TILE + (cy + 0.5) * CHUNK
    return ORIGIN - rz, ORIGIN - rx


def read_area_block(path: Path) -> AreaBlock:
    """The area block of a navmesh file; a version 1 file has none (empty `chunks`)."""
    with path.open("rb") as fh:
        head = fh.read(13)
        if len(head) < 13 or head[:4] != b"BNAV":
            raise AreasError(f"{path.name}: not a navmesh file (BNAV)")
        version, map_id = struct.unpack_from("<Ii", head, 4)
        build_len = head[12]
        build = fh.read(build_len).decode("utf-8", "replace")
        if version < 2:
            return AreaBlock(map_id, build, version, {})
        # settings (7 f32, 2 i32) and the Detour parameters (5 f32, 2 i32), then the tile index
        fh.seek(13 + build_len + 9 * 4 + 7 * 4)
        (blocks,) = struct.unpack("<i", fh.read(4))
        fh.seek(blocks * 20, 1)
        tail = fh.read(12)
        if len(tail) < 12:
            raise AreasError(f"{path.name}: file ends before the area block's header")
        tiles, offset, length = struct.unpack("<iii", tail)
        fh.seek(offset)
        packed = fh.read(length)
    if len(packed) != length:
        raise AreasError(f"{path.name}: area block cut short ({len(packed)} of {length} bytes)")
    try:
        raw = zlib.decompress(packed)
    except zlib.error as err:
        raise AreasError(f"{path.name}: area block does not inflate ({err})") from err
    if len(raw) != tiles * TILE_BYTES:
        raise AreasError(
            f"{path.name}: area block holds {len(raw)} bytes, {tiles} tiles need "
            f"{tiles * TILE_BYTES}"
        )
    chunks: dict[int, list[tuple[float, float]]] = {}
    for t in range(tiles):
        base = t * TILE_BYTES
        tile_x, tile_y = struct.unpack_from("<ii", raw, base)
        ids = struct.unpack_from(f"<{CHUNKS_PER_TILE}I", raw, base + 8)
        for i, area_id in enumerate(ids):
            if area_id:
                cy, cx = divmod(i, 16)
                chunks.setdefault(area_id, []).append(chunk_centre(tile_x, tile_y, cx, cy))
    return AreaBlock(map_id, build, version, chunks)


def read_navmesh_dir(folder: Path) -> list[AreaBlock]:
    """Every `*.navmesh` of a folder, by file name."""
    return [read_area_block(p) for p in sorted(folder.glob("*.navmesh"))]


def area_place(points: list[tuple[float, float]]) -> AreaPlace:
    """The chunk nearest the chunks' mean, and the radius of a disc as large as the chunks."""
    n = len(points)
    mx = sum(p[0] for p in points) / n
    my = sum(p[1] for p in points) / n
    wx, wy = min(points, key=lambda p: ((p[0] - mx) ** 2 + (p[1] - my) ** 2, p[0], p[1]))
    r = max(CHUNK, CHUNK * math.sqrt(n / math.pi))
    return AreaPlace(round(wx, 1), round(wy, 1), round(r, 1), n)


def _inside(t: Transform, wx: float, wy: float) -> tuple[float, float] | None:
    pos = world_to_map(t, wx, wy)
    if pos is None:
        return None
    x, y = pos
    if -SLACK <= x <= 1 + SLACK and -SLACK <= y <= 1 + SLACK:
        return min(max(x, 0.0), 1.0), min(max(y, 0.0), 1.0)
    return None


def zone_of(
    area: AreaRow,
    table: Mapping[int, AreaRow],
    area_to_map: Mapping[int, int],
    area_maps: Mapping[int, list[int]],
    transforms: Mapping[int, Transform],
    continent: int,
    wx: float,
    wy: float,
) -> int | None:
    """The uiMapID of the zone an area lies in: its parent area's (and up the chain) through
    `area.toMap`, else through the client's UiMapAssignment (the parent's maps that hold the
    place), else the map whose rectangle holds the place most centrally; None without any."""
    parent, seen = area.parent, set()
    while parent and parent not in seen:
        seen.add(parent)
        ui_map = area_to_map.get(parent)
        if ui_map:
            return ui_map
        for ui_map in area_maps.get(parent, []):
            t = transforms.get(ui_map)
            if t and t.continent == continent and _inside(t, wx, wy):
                return ui_map
        row = table.get(parent)
        parent = row.parent if row else 0
    if transforms:
        hit = best_map(dict(transforms), continent, wx, wy)
        if hit:
            return hit[0]
    return None


def add_areas(
    world: World,
    blocks: list[AreaBlock],
    table: Mapping[int, AreaRow],
    transforms: Mapping[int, Transform],
    area_maps: Mapping[int, list[int]] | None = None,
) -> int:
    """Adds an `area` record per named subzone with chunks; returns how many. Report notes say
    how many found a zone and a map place."""
    area_maps = area_maps or {}
    added = no_zone = no_spawn = 0
    skipped: dict[str, int] = {}
    for block in blocks:
        if block.version < 2:
            world.notes.append(
                f"areas: navmesh of map {block.map_id} is version {block.version}, no area block "
                "(rebuild it with clientdump navmesh)"
            )
            continue
        for area_id, points in sorted(block.chunks.items()):
            row = table.get(area_id)
            if row is None:
                reason = "not in AreaTable"
            elif row.parent == 0:
                reason = "zones"  # a zone stays a `zone`
            elif not row.name:
                reason = "unnamed"
            elif row.continent != block.map_id:
                reason = "of another continent"
            else:
                reason = None
            if reason:
                skipped[reason] = skipped.get(reason, 0) + 1
                continue
            assert row is not None
            place = area_place(points)
            zone = zone_of(
                row,
                table,
                world.area_to_map,
                area_maps,
                transforms,
                block.map_id,
                place.wx,
                place.wy,
            )
            rec: dict[str, object] = {
                "name": row.name,
                "zone": zone,
                "continent": block.map_id,
                "wx": place.wx,
                "wy": place.wy,
                "r": place.r,
                "chunks": place.chunks,
                "src": "client",
            }
            # the map place for drawing: on the zone's map, else the map that holds it best
            hit = None
            t = transforms.get(zone) if zone is not None else None
            pos = _inside(t, place.wx, place.wy) if t and t.continent == block.map_id else None
            if pos:
                hit = (zone, pos[0], pos[1])
            elif transforms:
                hit = best_map(dict(transforms), block.map_id, place.wx, place.wy)
            if hit:
                rec["spawns"] = [Spawn(hit[0], hit[1], hit[2], "client").row()]
            else:
                no_spawn += 1
            if zone is None:
                no_zone += 1
            world.add("area", area_id, rec)
            added += 1
    parts = [f"{added} from the navmesh area blocks of maps {sorted(b.map_id for b in blocks)}"]
    if no_zone:
        parts.append(f"{no_zone} without a zone")
    if no_spawn:
        parts.append(f"{no_spawn} without a map place")
    if skipped:
        parts.append("left out: " + ", ".join(f"{n} {why}" for why, n in sorted(skipped.items())))
    world.notes.append("areas: " + "; ".join(parts))
    return added
