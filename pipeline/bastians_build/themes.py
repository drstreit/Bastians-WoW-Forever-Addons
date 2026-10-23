"""Themes (styling round ST3, ADR 0017): the colour and shape tokens of the UI, one TOML file per
theme in `pipeline/config/themes/`, compiled into `addons/Bastians_Core/UI/Themes.lua`.

The game cannot read TOML, so the build turns every theme into a Lua table of floats; the file is
committed (it is small and the same for both clients) and `--check` keeps it in step. Every theme
names every token of the reference theme (`teal`, today's look) and nothing else, so a theme can
never leave a colour undefined. Colours are `#RRGGBB` or `#RRGGBBAA`.
"""

from __future__ import annotations

import re
import tomllib
from dataclasses import dataclass
from pathlib import Path

from bastians_build.emit import HEADER, lua_value
from bastians_build.files import write_text

ROOT = Path(__file__).resolve().parents[2]
THEMES_DIR = ROOT / "pipeline" / "config" / "themes"
OUT = ROOT / "addons" / "Bastians_Core" / "UI" / "Themes.lua"
REFERENCE = "teal"
HEX = re.compile(r"^#([0-9a-fA-F]{6})([0-9a-fA-F]{2})?$")
SHAPE_KEYS = {"radius": (0, 24), "radiusSmall": (0, 16)}


class ThemeError(ValueError):
    """A theme file is malformed or incomplete."""


@dataclass(frozen=True)
class Theme:
    id: str
    name: str
    order: int
    colors: dict[str, list[float]]
    shape: dict[str, int]


def parse_color(text: object, where: str) -> list[float]:
    """'#RRGGBB' or '#RRGGBBAA' -> [r, g, b, a] in 0..1, three decimals."""
    match = HEX.match(text) if isinstance(text, str) else None
    if not match:
        raise ThemeError(f"{where}: {text!r} is no colour (#RRGGBB or #RRGGBBAA)")
    rgb, alpha = match.group(1), match.group(2) or "ff"
    values = [int(rgb[i : i + 2], 16) for i in (0, 2, 4)] + [int(alpha, 16)]
    return [round(v / 255, 3) for v in values]


def read_theme(path: Path) -> Theme:
    try:
        raw = tomllib.loads(path.read_text(encoding="utf-8"))
    except tomllib.TOMLDecodeError as err:
        raise ThemeError(f"{path.name}: {err}") from err
    for key in ("id", "name", "order", "colors", "shape"):
        if key not in raw:
            raise ThemeError(f"{path.name}: `{key}` is missing")
    if raw["id"] != path.stem:
        raise ThemeError(f"{path.name}: id {raw['id']!r} must match the file name")
    colors = {k: parse_color(v, f"{path.name} colors.{k}") for k, v in raw["colors"].items()}
    shape = {}
    for key, value in raw["shape"].items():
        if key not in SHAPE_KEYS:
            raise ThemeError(f"{path.name}: unknown shape token {key!r}")
        lo, hi = SHAPE_KEYS[key]
        if not isinstance(value, int) or not lo <= value <= hi:
            raise ThemeError(f"{path.name}: shape.{key} must be a whole number {lo}..{hi}")
        shape[key] = value
    return Theme(raw["id"], str(raw["name"]), int(raw["order"]), colors, shape)


def read_themes(folder: Path = THEMES_DIR) -> list[Theme]:
    """Every theme in the folder, by order; each names exactly the reference's tokens."""
    themes = [read_theme(p) for p in sorted(folder.glob("*.toml"))]
    by_id = {t.id: t for t in themes}
    if REFERENCE not in by_id:
        raise ThemeError(f"{folder}: the reference theme {REFERENCE}.toml is missing")
    ref = by_id[REFERENCE]
    for t in themes:
        missing = sorted(set(ref.colors) - set(t.colors))
        extra = sorted(set(t.colors) - set(ref.colors))
        if missing or extra:
            raise ThemeError(f"{t.id}: colours missing {missing}, unknown {extra}")
        if set(t.shape) != set(SHAPE_KEYS):
            raise ThemeError(f"{t.id}: shape needs {sorted(SHAPE_KEYS)}")
    return sorted(themes, key=lambda t: (t.order, t.id))


def emit_themes(themes: list[Theme]) -> str:
    table = [{"id": t.id, "name": t.name, "colors": t.colors, "shape": t.shape} for t in themes]
    return (
        f"{HEADER}\n"
        "-- The UI themes (ST3, ADR 0017): pipeline/config/themes/*.toml, compiled by\n"
        "-- `python -m bastians_build themes`. Style.lua reads them; the first is the default.\n"
        "local _, ns = ...\n"
        f"ns.THEMES = {lua_value(table)}\n"
    )


def build_themes(folder: Path = THEMES_DIR, out: Path = OUT, check: bool = False) -> bool:
    """Writes the Lua file; with `check` only compares. Returns True when the file is current."""
    text = emit_themes(read_themes(folder))
    if check:
        return out.is_file() and out.read_text(encoding="utf-8") == text
    write_text(out, text)
    return True
