"""Tests for tools/clientdump (.NET). The real run needs a WoW install and is skipped in CI."""

import json
import os
import shutil
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "tools" / "clientdump"
CSPROJ = PROJECT / "clientdump.csproj"


def test_csproj_parses_and_pins_versions():
    tree = ET.parse(CSPROJ)
    refs = {r.get("Include"): r.get("Version") for r in tree.iter("PackageReference")}
    assert {"TACTSharp", "DBCD", "BLPSharp"} <= set(refs)
    for name, version in refs.items():
        assert version and "*" not in version and "[" not in version, name


def test_build_output_is_ignored():
    ignored = (ROOT / ".gitignore").read_text(encoding="utf-8")
    assert "tools/clientdump/bin/" in ignored
    assert "tools/clientdump/obj/" in ignored


@pytest.mark.skipif(shutil.which("dotnet") is None, reason="dotnet not on PATH")
def test_db2_dump_against_retail_client(tmp_path):
    client = os.environ.get("BASTIANS_RETAIL_CLIENT")
    defs = ROOT / ".local" / "WoWDBDefs" / "definitions"
    if not client or not Path(client).exists():
        pytest.skip("BASTIANS_RETAIL_CLIENT not set or missing")
    if not defs.is_dir():
        pytest.skip("WoWDBDefs not cloned into .local/WoWDBDefs")
    out = tmp_path / "TaxiNodes.json"
    run = subprocess.run(
        [
            "dotnet",
            "run",
            "--project",
            str(PROJECT),
            "--",
            "db2",
            "--install",
            client,
            "--table",
            "TaxiNodes",
            "--out",
            str(out),
            "--defs",
            str(defs),
            "--cache",
            str(tmp_path / "cache"),
        ],
        capture_output=True,
        text=True,
        timeout=600,
        check=False,
    )
    assert run.returncode == 0, run.stderr
    data = json.loads(out.read_text(encoding="utf-8"))
    assert data["rowCount"] == len(data["rows"]) > 0
    assert "ID" in data["columns"]
