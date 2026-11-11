"""The City & dungeon map's houses (docs/addons/map.md "City plans", ADR 0065): turns the measured
output of the Stormwind prototype into `Bastians_Map_Art/Generated/Houses.lua`.

Usage: python tools/city_houses.py 1453 <prototype dir> [--addon addons/Bastians_Map_Art]

The prototype dir holds pins.json, houses.json and house_drawn.npy. Needs numpy and OpenCV (the
machine-learning venv of tools/mapstyle). Deterministic: the same input gives the same bytes.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "addons" / "Bastians_Map_Art"
WMO_ID = 21138  # Stormwind's placed model (measured, ADR 0065)
CONTINENT = 0

# the prototype's plan grid: minimap tile pixels, cut to the city
TILE = 1600.0 / 3
ORIGIN = 32 * TILE
N = 1024
YPP = TILE / N
TOP, LEFT, HEIGHT, WIDTH = 30, 340, 2070, 2140
ROW0, COL0 = 47 * N + TOP, 29 * N + LEFT

# names no client table gives, from memory until checked in game (map.md "A house's name")
AUTHORED = {84775: "The Stockade", 84833: "The Gilded Rose", 84612: "The Pig and Whistle"}
ROLE_ORDER = ["bank", "auction", "inn", "flight", "stable", "trainer", "vendor", "quest"]
SOURCE = {"the client": "client", "its people": "people", "authored": "authored"}
SIMPLIFY = 2.0  # pixels an outline may stray from the footprint
MIN_PART = 40  # pixels of the smallest part of a building that gets an outline
ROUND = 1  # decimals of a world yard


def to_world(col: float, row: float) -> tuple[float, float]:
    """A plan pixel in world yards: (wx, wy)."""
    return ORIGIN - (row + ROW0 + 0.5) * YPP, ORIGIN - (col + COL0 + 0.5) * YPP


def merged(pins: list[dict]) -> list[dict]:
    """The prototype's pins as houses: rooms sharing a landmark's client name are one house, the
    authored names go in, and one quest giver alone is an edge, not a house."""
    by_name: dict[str, dict] = {}
    out: list[dict] = []
    for pin in pins:
        pin = {**pin, "ids": [pin["id"]]}
        first = by_name.get(pin["name"]) if pin["src"] == "the client" else None
        if first:
            first["ids"].append(pin["id"])
            first["area"] += pin["area"]
            roles = set(first["roles"]) | set(pin["roles"])
            first["roles"] = sorted(roles, key=ROLE_ORDER.index)[:3]
            continue
        if pin["src"] == "the client":
            by_name[pin["name"]] = pin
        out.append(pin)
    final = []
    for pin in out:
        if pin["id"] in AUTHORED:
            pin["name"], pin["src"] = AUTHORED[pin["id"]], "authored"
        elif pin["roles"] == ["quest"] and len(pin["people"]) == 1 and pin["src"] == "its people":
            continue
        final.append(pin)
    return final


def people_of(keys: list[str], houses: dict) -> list[int]:
    """The NPC ids with a service or a quest in these rooms, each once, in the rooms' order."""
    seen: list[int] = []
    for key in keys:
        for resident in houses[key]["residents"]:
            if resident["useful"] and resident["id"] not in seen:
                seen.append(resident["id"])
    return seen


def outlines_of(keys: list[str], drawn) -> list[list[float]]:
    """Each part of the drawn footprint as a flat { wx, wy, ... } polygon, the largest first."""
    import cv2
    import numpy as np

    mask = np.isin(drawn, [int(k) for k in keys]).astype("u1")
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    parts = sorted(
        (c for c in contours if cv2.contourArea(c) >= MIN_PART),
        key=lambda c: (-cv2.contourArea(c), c[0][0].tolist()),
    )
    out = []
    for contour in parts:
        poly: list[float] = []
        for point in cv2.approxPolyDP(contour, SIMPLIFY, True):
            wx, wy = to_world(float(point[0][0]), float(point[0][1]))
            poly += [round(wx, ROUND), round(wy, ROUND)]
        if len(poly) >= 6:
            out.append(poly)
    return out


def records(pins: list[dict], houses: dict, drawn) -> list[dict]:
    """The house records, sorted by id. `houses` is keyed by room number as a string."""
    room_of = {min(v["groups"]): k for k, v in houses.items()}
    out = []
    for pin in merged(pins):
        keys = [room_of[i] for i in pin["ids"]]
        groups = [g for k in keys for g in houses[k]["groups"]]
        wx, wy = to_world(pin["x"] / 100 * WIDTH, pin["y"] / 100 * HEIGHT)
        doors = [[round(d[0], ROUND), round(d[1], ROUND)] for k in keys for d in houses[k]["doors"]]
        out.append(
            {
                "id": f"{WMO_ID}-{min(groups)}",
                "name": pin["name"],
                "src": SOURCE[pin["src"]],
                "district": pin["district"] or None,
                "roles": pin["roles"],
                "continent": CONTINENT,
                "wx": round(wx, ROUND),
                "wy": round(wy, ROUND),
                "under": pin["under"],
                "area": pin["area"],
                "doors": doors,
                "outlines": [] if pin["under"] else outlines_of(keys, drawn),
                "people": people_of(keys, houses),
            }
        )
    return sorted(out, key=lambda h: h["id"])


def lua_string(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def lua_list(values: list) -> str:
    return "{ " + ", ".join(str(v) for v in values) + " }" if values else "{}"


def manifest(by_ui: dict[int, list[dict]]) -> str:
    """Generated/Houses.lua."""
    out = [
        "-- GENERATED by tools/city_houses.py, do not edit",
        "local B = Bastians or {}",
        "Bastians = B",
        "B.Map = B.Map or {}",
        "B.Map.houses = {",
    ]
    for ui in sorted(by_ui):
        out.append(f"  [{ui}] = {{")
        for h in by_ui[ui]:
            fields = [
                f"id = {lua_string(h['id'])}",
                f"name = {lua_string(h['name'])}",
                f"src = {lua_string(h['src'])}",
            ]
            if h["district"]:
                fields.append(f"district = {lua_string(h['district'])}")
            roles = ", ".join(lua_string(r) for r in h["roles"])
            fields.append(f"roles = {{ {roles} }}")
            fields += [
                f"continent = {h['continent']}",
                f"wx = {h['wx']}",
                f"wy = {h['wy']}",
                f"area = {h['area']}",
            ]
            if h["under"]:
                fields.append("under = true")
            fields.append(f"people = {lua_list(h['people'])}")
            doors = ", ".join(lua_list(d) for d in h["doors"])
            fields.append(f"doors = {{ {doors} }}")
            outlines = ", ".join(lua_list(p) for p in h["outlines"])
            fields.append(f"outlines = {{ {outlines} }}")
            out.append("    { " + ", ".join(fields) + " },")
        out.append("  },")
    out.append("}")
    return "\n".join(out) + "\n"


def main() -> int:
    import numpy as np

    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("ui", type=int, choices=[1453])
    parser.add_argument("prototype", type=Path)
    parser.add_argument("--addon", type=Path, default=ADDON)
    args = parser.parse_args()
    pins = json.loads((args.prototype / "pins.json").read_text(encoding="utf-8"))
    houses = json.loads((args.prototype / "houses.json").read_text(encoding="utf-8"))
    drawn = np.load(args.prototype / "house_drawn.npy")
    rows = records(pins, houses, drawn)
    target = args.addon / "Generated" / "Houses.lua"
    target.parent.mkdir(parents=True, exist_ok=True)
    temp = target.with_name(target.name + ".tmp")
    temp.write_bytes(manifest({args.ui: rows}).encode("utf-8"))
    temp.replace(target)
    print(f"{args.ui}: {len(rows)} houses, {sum(len(h['people']) for h in rows)} people")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
