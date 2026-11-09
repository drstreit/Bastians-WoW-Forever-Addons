"""Themes (styling round ST3, ADR 0017): the colour and shape tokens of the UI, one TOML file per
theme in `pipeline/config/themes/`, compiled into `addons/Bastians_Core/UI/Themes.lua`.

The game cannot read TOML, so the build turns every theme into a Lua table of floats; the file is
committed (it is small and the same for both clients) and `--check` keeps it in step. Every theme
names every token of the reference theme (`teal`, today's look) and nothing else, so a theme can
never leave a colour undefined. Colours are `#RRGGBB` or `#RRGGBBAA`.

Readability: every text token is
measured against every ground it sits on with the WCAG 2 contrast ratio, and a theme that fails
does not compile. Text at the UI's sizes (11 to 17 px) needs 4.5:1; text of 24 px and more and
the glyphs on the kind tiles (graphics, not text) need 3:1. A translucent ground is measured by
its own colour (what shows through it is the world, unknown at build time). The pairs are listed
in READABLE below; a new text token is added there with its grounds.
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
# the look's geometry (ADR 0046): heights and sizes of the widget set in px, a ground alpha in %
GEOMETRY_KEYS = {
    "action": (16, 40),  # an action button (pictogram and text)
    "actionRow": (14, 32),  # the same inside a row
    "pill": (16, 40),
    "tab": (16, 40),
    "row": (16, 48),
    "tile": (10, 32),  # the kind tile in rows and pills
    "tileBig": (16, 48),  # the kind tile in a header
    "gap": (0, 16),  # between a widget's icon and its text
    "groundAlpha": (20, 100),
}


# The readability pairs (H2): (text tokens, ground tokens, px size or "icon"). The UI's text
# tokens sit on the window ground and on panels (buttons, fields, rows); the title bar's words on
# the header; the tooltip tokens on the game's tooltip (near black, outside our themes); the
# map's words on the light rim drawn around them; the kind tiles carry a white glyph.
TOOLTIP_GROUND = "#0a0a0a"
TILE_GLYPH = "#ffffff"
UI_TEXT = (
    "text", "dim", "muted", "bright", "accent", "gold", "on", "good", "bad", "warn", "neutral",
    "rare", "water", "note1", "note2", "note3", "note4", "note5", "note6",
    "svcVendor", "svcQuest", "svcTrainer", "svcInn", "svcFlight", "svcRepair", "svcFriendly",
    "svcHostile", "typeNpc", "typeItem", "typeQuest", "typeObject", "typeNode", "typeZone",
    "typeRecipe", "typeSpot", "typeChain", "typeHere",
    "coinGold", "coinSilver", "coinCopper",
    "diffRed", "diffOrange", "diffYellow", "diffGreen", "diffGrey",
)  # fmt: skip
TILES = (
    "tileGold", "tileRed", "tileTeal", "tileGreen",
    "tileBlue", "tilePurple", "tileBrown", "tileGrey",
)  # fmt: skip
READABLE: tuple[tuple[tuple[str, ...], tuple[str, ...], int | str], ...] = (
    (UI_TEXT, ("bg", "panel"), 12),
    (("headerText",), ("header",), 15),
    (("tipText", "tipDim", "tipGold", "chat", "chatEmote"), (TOOLTIP_GROUND,), 12),
    (
        (
            "mapText",
            "mapTextDim",
            "mapDiffRed",
            "mapDiffOrange",
            "mapDiffYellow",
            "mapDiffGreen",
            "mapDiffGrey",
        ),
        ("mapTextRim",),
        11,
    ),
    ((TILE_GLYPH,), TILES, "icon"),
)
# The pocket atlas' grounds (ADR 0056, "readable by rule", PA7). A tile's plate lies over the
# window's ground and over a panel ("card/bg": the first composited over the second by its alpha).
# The quest sheet and the Browser's paper page are drawn on Core's Media/Parchment.tga: its mean
# colour is the ground (measured 06.11.2026; the darkest twentieth of it is #c29b62, where the same
# inks read at about 3.5:1). The theme PAPER_THEME lends its tokens to a paper page in every theme
# (Style.lua, S.Palette), so its words must read on the parchment and on a plate over it.
PAPER_GROUND = "#d5b175"
PAPER_THEME = "parchment"
SHEET_TEXT = ("sheetInk", "sheetDim", "sheetTitle", "sheetGood")
READABLE += (
    (UI_TEXT, ("card/bg", "card/panel"), 12),
    (SHEET_TEXT, (PAPER_GROUND,), 12),
    (("sheetTileText",), ("sheetTile",), 12),
)
PAPER_READABLE: tuple[tuple[tuple[str, ...], tuple[str, ...], int | str], ...] = (
    (UI_TEXT, (PAPER_GROUND, "card/" + PAPER_GROUND), 12),
)
LARGE_PX = 24  # text this big or bigger reads at 3:1 (WCAG 1.4.3)


def minimum_ratio(size: int | str) -> float:
    """4.5:1 for text under 24 px, 3:1 for larger text and for graphics ("icon")."""
    if size == "icon" or (isinstance(size, int) and size >= LARGE_PX):
        return 3.0
    return 4.5


def luminance(rgb: list[float]) -> float:
    """The relative luminance of an sRGB colour (WCAG 2, the alpha ignored)."""

    def linear(c: float) -> float:
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4

    return 0.2126 * linear(rgb[0]) + 0.7152 * linear(rgb[1]) + 0.0722 * linear(rgb[2])


def contrast(a: list[float], b: list[float]) -> float:
    """The WCAG 2 contrast ratio of two colours, 1 (equal) to 21 (black on white)."""
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def over(top: list[float], under: list[float]) -> list[float]:
    """A colour laid over another by its alpha (the lower one taken as opaque)."""
    alpha = top[3] if len(top) > 3 else 1.0
    return [top[i] * alpha + under[i] * (1 - alpha) for i in range(3)]


def unreadable(colors: dict[str, list[float]], paper: bool = False) -> list[str]:
    """The readability pairs a theme fails: 'text on ground 3.21 < 4.5', empty when it passes.
    `paper`: the theme is the paper palette, so the pairs of a paper page count too."""

    def colour(name: str) -> list[float]:
        if "/" in name:  # "card/bg": the first over the second
            top, under = name.split("/", 1)
            return over(colour(top), colour(under))
        if name.startswith("#"):
            return parse_color(name, "readability")
        return colors[name]

    out = []
    for texts, grounds, size in READABLE + (PAPER_READABLE if paper else ()):
        need = minimum_ratio(size)
        for text in texts:
            for ground in grounds:
                ratio = contrast(colour(text), colour(ground))
                if ratio < need:
                    out.append(f"{text} on {ground} {ratio:.2f} < {need}")
    return out


class ThemeError(ValueError):
    """A theme file is malformed or incomplete."""


@dataclass(frozen=True)
class Theme:
    id: str
    name: str
    order: int
    colors: dict[str, list[float]]
    shape: dict[str, int]
    geometry: dict[str, int]


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
    for key in ("id", "name", "order", "colors", "shape", "geometry"):
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
    geometry = {}
    for key, value in raw["geometry"].items():
        if key not in GEOMETRY_KEYS:
            raise ThemeError(f"{path.name}: unknown geometry token {key!r}")
        lo, hi = GEOMETRY_KEYS[key]
        if not isinstance(value, int) or not lo <= value <= hi:
            raise ThemeError(f"{path.name}: geometry.{key} must be a whole number {lo}..{hi}")
        geometry[key] = value
    return Theme(raw["id"], str(raw["name"]), int(raw["order"]), colors, shape, geometry)


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
        if set(t.geometry) != set(GEOMETRY_KEYS):
            raise ThemeError(f"{t.id}: geometry needs {sorted(GEOMETRY_KEYS)}")
        failing = unreadable(t.colors, paper=t.id == PAPER_THEME)
        if failing:
            raise ThemeError(f"{t.id}: unreadable (WCAG contrast): " + "; ".join(failing))
    return sorted(themes, key=lambda t: (t.order, t.id))


def emit_themes(themes: list[Theme]) -> str:
    table = [
        {"id": t.id, "name": t.name, "colors": t.colors, "shape": t.shape, "geometry": t.geometry}
        for t in themes
    ]
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
