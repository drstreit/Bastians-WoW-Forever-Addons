"""Reader for Bastians_Probe dumps (data/probe/<date>-<client>-<build>.lua): map transforms.

Probe P3 calls ``C_Map.GetWorldPosFromMapPos`` at the map corners (0,0), (1,1) and (1,0) for every
uiMapID. Three corners fix the affine transform ``world = origin + fractions * matrix`` exactly
(coordinates.md); with two corners the axis orientation is an assumption and the entry is marked.
The table feeds ``Bastians.Coords`` (same row shape as Compat.SetTransformTable):
``[uiMapID] = { continent, wx0, wxDx, wxDy, wy0, wyDx, wyDy }``.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from lupa import lua51

from bastians_build.sources.luatable import to_python


@dataclass(frozen=True)
class Transform:
    ui_map_id: int
    continent: int
    wx0: float
    wx_dx: float
    wx_dy: float
    wy0: float
    wy_dx: float
    wy_dy: float
    exact: bool  # three corners measured; False = orientation assumed from two corners

    def row(self) -> list[float]:
        return [self.continent, self.wx0, self.wx_dx, self.wx_dy, self.wy0, self.wy_dx, self.wy_dy]


@dataclass
class ProbeDump:
    client: str | None
    build: str | None
    interface: int | None
    maps: dict[int, dict]
    results: dict


def parse_probe_dump(text: str) -> ProbeDump:
    """The saved-variable file is plain Lua: `BastiansProbeDB = { ... }`."""
    lua = lua51.LuaRuntime(
        unpack_returned_tuples=True, register_eval=False, register_builtins=False
    )
    lua.execute(text)
    db = to_python(lua.globals().BastiansProbeDB)
    if not isinstance(db, dict):
        raise ValueError("no BastiansProbeDB table in the dump")
    meta = db.get("meta") or {}
    results = db.get("results") or {}
    p3 = results.get("P3") or {}
    maps = p3.get("maps") or {}
    return ProbeDump(
        client=meta.get("client"),
        build=str(meta["build"]) if meta.get("build") is not None else None,
        interface=meta.get("interface"),
        maps={int(k): v for k, v in maps.items()},
        results=results,
    )


def read_probe_dump(path: Path) -> ProbeDump:
    return parse_probe_dump(path.read_text(encoding="utf-8"))


def _corner(entry: dict, key: str) -> tuple[int, float, float] | None:
    c = entry.get(key)
    if not isinstance(c, dict) or "x" not in c or "y" not in c:
        return None
    return int(c["continent"]), float(c["x"]), float(c["y"])


def transform_for(ui_map_id: int, entry: dict) -> Transform | None:
    """The affine transform of one map, or None when the API gave no world position for it."""
    c00, c11, c10 = _corner(entry, "c00"), _corner(entry, "c11"), _corner(entry, "c10")
    if c00 is None or c11 is None:
        return None
    continent, wx0, wy0 = c00
    if c10 is not None and c10[0] == continent:
        # (1,0) gives the x-axis column; the (1,1) corner then gives the y-axis column
        wx_dx, wy_dx = c10[1] - wx0, c10[2] - wy0
        wx_dy, wy_dy = c11[1] - wx0 - wx_dx, c11[2] - wy0 - wy_dx
        exact = True
    else:
        # WoW convention: the map's x axis (east) runs along world -y, its y axis (south) along -x
        wx_dx, wy_dx = 0.0, c11[2] - wy0
        wx_dy, wy_dy = c11[1] - wx0, 0.0
        exact = False
    return Transform(ui_map_id, continent, wx0, wx_dx, wx_dy, wy0, wy_dx, wy_dy, exact)


def transform_table(dump: ProbeDump) -> dict[int, Transform]:
    out: dict[int, Transform] = {}
    for ui_map_id, entry in sorted(dump.maps.items()):
        t = transform_for(ui_map_id, entry)
        if t is not None and (t.wx_dx or t.wx_dy) and (t.wy_dx or t.wy_dy):
            out[ui_map_id] = t
    return out


def map_names(dump: ProbeDump) -> dict[int, str]:
    return {m: e["name"] for m, e in dump.maps.items() if isinstance(e, dict) and e.get("name")}


def map_types(dump: ProbeDump) -> dict[int, int]:
    """UiMap.Type per map from the P3 dump (`mapType`): 2 continent, 3 zone, 4 dungeon (R5)."""
    return {
        m: int(e["mapType"])
        for m, e in dump.maps.items()
        if isinstance(e, dict) and isinstance(e.get("mapType"), int | float)
    }
