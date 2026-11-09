"""Schema 1.3 of AHSync's export: the verdicts are gone. An
export without `status` reads, and a 1.2 export with it still does: the column is not read."""

import csv
import hashlib
import json
import shutil
from pathlib import Path

from bastians_build.sources.ahsync_export import read_export

ROOT = Path(__file__).resolve().parents[2]
EXPORT = ROOT / "tests" / "fixtures" / "export-mini"


def drop_status(folder: Path) -> None:
    manifest = json.loads((folder / "manifest.json").read_text(encoding="utf-8"))
    manifest["schema_version"] = "1.3"
    for table in manifest["tables"]:
        if table["name"] in ("claims", "farm_spots"):
            path = folder / table.get("file", f"{table['name']}.csv")
            with path.open(encoding="utf-8", newline="") as fh:
                rows = list(csv.DictReader(fh))
            names = [c for c in rows[0] if c != "status"]
            with path.open("w", encoding="utf-8", newline="") as fh:
                out = csv.DictWriter(fh, names, extrasaction="ignore")
                out.writeheader()
                out.writerows(rows)
            table["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
    (folder / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")


def test_an_export_without_status_reads(tmp_path: Path):
    folder = tmp_path / "export"
    shutil.copytree(EXPORT, folder)
    latest = folder / "LATEST"
    if latest.is_file():
        folder = folder / latest.read_text(encoding="utf-8").strip()
    drop_status(folder)
    export = read_export(folder)
    assert export.manifest["schema_version"] == "1.3"
    assert export.tables["claims"] and "status" not in export.tables["claims"][0]
    assert export.tables["farm_spots"] and "status" not in export.tables["farm_spots"][0]


def test_an_older_export_with_status_still_reads():
    export = read_export(EXPORT)
    assert export.tables["claims"] and "status" not in export.tables["claims"][0]
