"""Build configuration: pipeline/config/build.toml (packs, schemas, budgets, clients)."""

from __future__ import annotations

import tomllib
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONFIG_DIR = ROOT / "pipeline" / "config"
CLIENTS = ("forever", "retail")


class ConfigError(ValueError):
    pass


@dataclass(frozen=True)
class PackConfig:
    name: str
    addon: str
    file: str
    schema: dict[str, list[str]]  # type -> field order
    indexes: list[str]
    budget_kb: int | None = None
    optional: bool = False  # not written when every type of the pack has zero records
    budget_kb_by_client: dict[str, int] = field(default_factory=dict)  # overrides per client

    def budget_for(self, client: str) -> int | None:
        return self.budget_kb_by_client.get(client, self.budget_kb)


@dataclass(frozen=True)
class MarketFill:
    to: str
    source: str
    label: str


@dataclass(frozen=True)
class MarketConfig:
    """[market]: labels per market and the fills for markets without export rows (data.md)."""

    labels: dict[str, str] = field(default_factory=dict)
    fill: list[MarketFill] = field(default_factory=list)
    ship: tuple[str, ...] = ()  # the markets the pack carries (empty: all) and their fills' sources

    def label(self, market: str) -> str:
        return self.labels.get(market, market)

    def shipped(self) -> set[str] | None:
        """The markets whose rows go into the pack: the ship list and the sources its fills read;
        None for every market."""
        if not self.ship:
            return None
        keep = set(self.ship)
        keep |= {f.source for f in self.fill if f.to in keep}
        return keep


@dataclass(frozen=True)
class MapArtConfig:
    """[mapart]: the overview textures of Bastians_Map_Art (map.md "Imagery pipeline")."""

    addon: str = "Bastians_Map_Art"
    span: int = 8  # ADT tiles per overview cell and axis
    pixels: int = 64  # pixels per ADT in the stored texture
    pixels_by_client: dict[str, int] = field(default_factory=dict)
    budget_kb: int | None = None
    alpha: str = "dxt1"  # how partly filled cells carry their transparency: dxt1 | dxt5
    skip_sea: float = 0.98  # the tile table drops native tiles whose sea share is at least this
    sea: str | None = (
        None  # "rrggbb": paint the sea into every cell (opaque cells, no transparency)
    )

    def pixels_for(self, client: str) -> int:
        return self.pixels_by_client.get(client, self.pixels)


@dataclass(frozen=True)
class BuildConfig:
    packs: dict[str, PackConfig]
    pack_order: list[str] = field(default_factory=list)
    market: MarketConfig = field(default_factory=MarketConfig)
    mapart: MapArtConfig = field(default_factory=MapArtConfig)

    def pack_for_type(self, record_type: str) -> PackConfig | None:
        for name in self.pack_order:
            if record_type in self.packs[name].schema:
                return self.packs[name]
        return None


def load_config(path: Path | None = None) -> BuildConfig:
    path = path or CONFIG_DIR / "build.toml"
    with path.open("rb") as fh:
        raw = tomllib.load(fh)
    packs: dict[str, PackConfig] = {}
    order: list[str] = []
    for name, p in raw.get("packs", {}).items():
        for key in ("addon", "file", "schema"):
            if key not in p:
                raise ConfigError(f"pack {name}: missing `{key}`")
        by_client = {c: p[f"budget_kb_{c}"] for c in CLIENTS if f"budget_kb_{c}" in p}
        packs[name] = PackConfig(
            name=name,
            addon=p["addon"],
            file=p["file"],
            schema={t: list(fields) for t, fields in p["schema"].items()},
            indexes=list(p.get("indexes", [])),
            budget_kb=p.get("budget_kb"),
            optional=bool(p.get("optional", False)),
            budget_kb_by_client=by_client,
        )
        order.append(name)
    seen: dict[str, str] = {}
    for name in order:
        for record_type in packs[name].schema:
            if record_type in seen:
                raise ConfigError(f"type {record_type} is in packs {seen[record_type]} and {name}")
            seen[record_type] = name
    raw_market = raw.get("market", {})
    fills = []
    for i, f in enumerate(raw_market.get("fill", []), 1):
        for key in ("to", "from", "label"):
            if key not in f:
                raise ConfigError(f"market.fill {i}: missing `{key}`")
        fills.append(MarketFill(to=f["to"], source=f["from"], label=f["label"]))
    market = MarketConfig(
        labels=dict(raw_market.get("labels", {})),
        fill=fills,
        ship=tuple(str(m) for m in raw_market.get("ship", [])),
    )
    raw_art = raw.get("mapart", {})
    span, pixels = int(raw_art.get("span", 8)), int(raw_art.get("pixels", 64))
    if span < 1 or 64 % span:
        raise ConfigError(f"mapart.span must divide 64, got {span}")
    pixels_by_client = {c: int(raw_art[f"pixels_{c}"]) for c in CLIENTS if f"pixels_{c}" in raw_art}
    for px in (pixels, *pixels_by_client.values()):
        if px < 4 or px & (px - 1):
            raise ConfigError(f"mapart.pixels must be a power of two of at least 4, got {px}")
    alpha = str(raw_art.get("alpha", "dxt1"))
    if alpha not in ("dxt1", "dxt5"):
        raise ConfigError(f"mapart.alpha must be dxt1 or dxt5, got {alpha!r}")
    sea = raw_art.get("sea")
    if sea is not None:
        sea = str(sea).lstrip("#").lower()
        if len(sea) != 6 or any(ch not in "0123456789abcdef" for ch in sea):
            raise ConfigError(f"mapart.sea must be six hex digits (rrggbb), got {raw_art['sea']!r}")
    skip_sea = float(raw_art.get("skip_sea", 0.98))
    if not 0 < skip_sea <= 1:
        raise ConfigError(f"mapart.skip_sea must be in (0, 1], got {skip_sea}")
    mapart = MapArtConfig(
        addon=str(raw_art.get("addon", "Bastians_Map_Art")),
        span=span,
        pixels=pixels,
        pixels_by_client=pixels_by_client,
        budget_kb=raw_art.get("budget_kb"),
        alpha=alpha,
        sea=sea,
        skip_sea=skip_sea,
    )
    return BuildConfig(packs=packs, pack_order=order, market=market, mapart=mapart)
