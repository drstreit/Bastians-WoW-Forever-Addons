"""Reader for the AHSync market export (ahsync-export.md): manifest plus CSV tables.

The folder is `<root>/<YYYYMMDDTHHMMZ>/` named by `<root>/LATEST`, or the folder itself. Every
table is checked against the manifest's sha256 before it is parsed; the schema name must be
`bastians-export` and the major version 1. Cells are typed per column; an empty cell is None (the
contract's NULL), never 0. Timestamps are ISO-8601 `Z` and become integer Unix seconds.
"""

from __future__ import annotations

import csv
import hashlib
import json
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path

SCHEMA = "bastians-export"
MAJOR = 1

# column -> type per table; "ts" is ISO-8601 Z -> Unix seconds, "json" a JSON cell
COLUMNS: dict[str, dict[str, str]] = {
    "prices_latest": {
        "market": "str",
        "item_id": "int",
        "median": "int",
        "min_buyout": "int",
        "quantity": "int",
        "median_7d": "int",
        "median_30d": "int",
        "low_30d": "int",
        "high_30d": "int",
        "sales_per_day": "float",
        "scan_ts": "ts",
    },
    "claims": {
        "claim_id": "int",
        "kind": "str",
        "subject": "str",
        "item_id": "int",
        "ui_map_id": "int",
        "x": "float",
        "y": "float",
        "weight": "float",
        "reach": "int",
        "status": "str",
        "build": "str",
        "first_seen": "ts",
        "last_seen": "ts",
        "src": "str",
        "where": "str",
        "claim": "str",  # AHSync's own sentence (schema 1.2); the Strategies book shows it
        "sources": "json",  # [{channel, published, link}]: who said it, where in the video
    },
    "farm_spots": {
        "spot_id": "int",
        "name": "str",
        "ui_map_id": "int",
        "x": "float",
        "y": "float",
        "radius": "float",
        "level_min": "int",
        "level_max": "int",
        "items": "json",
        "status": "str",
        "claim_id": "int",
        "src": "str",
        "where": "str",
    },
    "signals": {
        "signal_id": "int",
        "module": "str",
        "action": "str",
        "item_id": "int",
        "market": "str",
        "horizon": "str",
        "confidence": "float",
        "rationale": "str",
        "capital_required": "int",
        "expected_profit": "int",
        "time_cost_minutes": "int",
        "flags": "json",
        "valid_until": "ts",
        "src": "str",
    },
}
REQUIRED = tuple(COLUMNS)
# columns a table may lack (added in schema 1.2: the place as English text); missing, they are None
OPTIONAL: dict[str, set[str]] = {"claims": {"where", "claim", "sources"}, "farm_spots": {"where"}}


class ExportError(ValueError):
    """The export folder is missing, corrupt or of another schema."""


@dataclass
class Export:
    folder: Path
    manifest: dict
    tables: dict[str, list[dict]] = field(default_factory=dict)

    @property
    def created_at(self) -> str | None:
        return self.manifest.get("created_at")

    @property
    def sources(self) -> list[dict]:
        return list(self.manifest.get("sources") or [])


def resolve_folder(root: Path) -> Path:
    """The export folder: `root` itself when it holds a manifest, else the one named in LATEST."""
    if (root / "manifest.json").is_file():
        return root
    latest = root / "LATEST"
    if not latest.is_file():
        raise ExportError(f"{root}: neither manifest.json nor LATEST found")
    name = latest.read_text(encoding="utf-8").strip()
    folder = root / name
    if not (folder / "manifest.json").is_file():
        raise ExportError(f"{root}: LATEST names {name!r}, which has no manifest.json")
    return folder


def _number(value: float) -> int | float:
    return int(value) if float(value).is_integer() else value


def parse_cell(kind: str, raw: str, where: str) -> object:
    if raw == "":
        return None
    try:
        if kind == "int":
            return int(raw)
        if kind == "float":
            return _number(float(raw))
        if kind == "ts":
            return int(
                datetime.fromisoformat(raw.replace("Z", "+00:00")).astimezone(UTC).timestamp()
            )
        if kind == "json":
            return json.loads(raw)
    except (ValueError, json.JSONDecodeError) as err:
        raise ExportError(f"{where}: {raw!r} is no {kind}") from err
    return raw


def read_table(path: Path, name: str) -> list[dict]:
    columns = COLUMNS[name]
    with path.open(encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh)
        header = reader.fieldnames or []
        missing = [c for c in columns if c not in header and c not in OPTIONAL.get(name, ())]
        if missing:
            raise ExportError(f"{path.name}: columns missing: {', '.join(missing)}")
        rows = []
        for number, raw in enumerate(reader, start=2):
            rows.append(
                {
                    c: parse_cell(kind, raw.get(c) or "", f"{path.name}:{number} {c}")
                    for c, kind in columns.items()
                }
            )
    return rows


def read_export(root: Path) -> Export:
    folder = resolve_folder(root)
    try:
        manifest = json.loads((folder / "manifest.json").read_text(encoding="utf-8"))
    except json.JSONDecodeError as err:
        raise ExportError(f"{folder}: manifest.json is not JSON ({err})") from err
    if manifest.get("schema") != SCHEMA:
        raise ExportError(f"{folder}: schema is {manifest.get('schema')!r}, expected {SCHEMA!r}")
    version = str(manifest.get("schema_version") or "")
    if not version.split(".")[0].isdigit() or int(version.split(".")[0]) != MAJOR:
        raise ExportError(f"{folder}: schema_version {version!r} is not {MAJOR}.x")
    listed = {t.get("name"): t for t in manifest.get("tables") or []}
    export = Export(folder=folder, manifest=manifest)
    for name in REQUIRED:
        entry = listed.get(name)
        if entry is None:
            raise ExportError(f"{folder}: table {name!r} missing from the manifest")
        path = folder / str(entry.get("file") or f"{name}.csv")
        if not path.is_file():
            raise ExportError(f"{folder}: {path.name} missing")
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if entry.get("sha256") and entry["sha256"] != digest:
            raise ExportError(f"{folder}: {path.name} does not match its sha256 in the manifest")
        export.tables[name] = read_table(path, name)
    return export
