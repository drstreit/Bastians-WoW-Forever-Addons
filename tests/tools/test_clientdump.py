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


# Hotfixes (ADR 0039): the cache is refused unless it parses to its end and is the files' build.

needs_dotnet = pytest.mark.skipif(shutil.which("dotnet") is None, reason="dotnet not on PATH")


def _clientdump(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["dotnet", "run", "--project", str(PROJECT), "--", *args],
        capture_output=True,
        text=True,
        timeout=900,
        check=False,
    )


def _xfth(build: int, entries: list[bytes], version: int = 9) -> bytes:
    """A DBCache.bin: the header (magic, version, build, 32-byte hash), then the entries."""
    head = b"XFTH" + version.to_bytes(4, "little") + build.to_bytes(4, "little") + bytes(32)
    return head + b"".join(entries)


def _entry(push: int, record: int, data: bytes, declared: int | None = None) -> bytes:
    """One v9 entry: magic, region, push, unique id, table hash, record id, size, status + 3."""
    size = len(data) if declared is None else declared
    fields = (1, push, 7, 0x12345678, record, size)
    return b"XFTH" + b"".join(f.to_bytes(4, "little") for f in fields) + bytes([1, 0, 0, 0]) + data


def _db2_file_run(tmp_path: Path, cache: bytes) -> subprocess.CompletedProcess[str]:
    (tmp_path / "DBCache.bin").write_bytes(cache)
    return _clientdump(
        "db2",
        "--db2-file",
        str(tmp_path / "absent.db2"),
        "--build",
        "1.60.1.70707",
        "--table",
        "ItemSparse",
        "--out",
        str(tmp_path / "out.json"),
        "--hotfixes",
        str(tmp_path / "DBCache.bin"),
    )


@needs_dotnet
def test_hotfixes_of_another_build_are_refused(tmp_path):
    run = _db2_file_run(tmp_path, _xfth(70685, [_entry(5, 1, b"abcd")]))
    assert run.returncode == 1
    assert "is build 70685, the files are 1.60.1.70707: refused" in run.stderr
    assert not (tmp_path / "out.json").exists()


@needs_dotnet
def test_an_incomplete_hotfix_cache_is_refused(tmp_path):
    run = _db2_file_run(tmp_path, _xfth(70707, [_entry(5, 1, b"abcd", declared=100)]))
    assert run.returncode == 1
    assert "runs past the end" in run.stderr
    assert not (tmp_path / "out.json").exists()


@needs_dotnet
def test_a_hotfix_cache_of_another_format_is_refused(tmp_path):
    run = _db2_file_run(tmp_path, _xfth(70707, [], version=8))
    assert run.returncode == 1
    assert "version 8" in run.stderr


@needs_dotnet
def test_hotfixes_and_the_raw_copy_against_the_forever_client(tmp_path):
    client = os.environ.get("BASTIANS_FOREVER_CLIENT")
    defs = ROOT / ".local" / "WoWDBDefs" / "definitions"
    if not client or not (Path(client) / "Cache" / "ADB" / "enUS" / "DBCache.bin").is_file():
        pytest.skip("BASTIANS_FOREVER_CLIENT not set or without a hotfix cache")
    if not defs.is_dir():
        pytest.skip("WoWDBDefs not cloned into .local/WoWDBDefs")
    cache = tmp_path / "DBCache.bin"
    shutil.copyfile(Path(client) / "Cache" / "ADB" / "enUS" / "DBCache.bin", cache)
    common = ["--defs", str(defs), "--hotfixes", str(cache)]
    tact = ["--install", client, "--cache", str(tmp_path / "tact")]

    def dump(table: str, *extra: str) -> dict:
        out = tmp_path / f"{table}{len(list(tmp_path.iterdir()))}.json"
        run = _clientdump("db2", "--table", table, "--out", str(out), *common, *extra)
        if run.returncode and "refused (ADR 0039)" in run.stderr:
            pytest.skip("the client's hotfix cache is of another build: " + run.stderr.strip())
        assert run.returncode == 0, run.stderr
        return json.loads(out.read_text(encoding="utf-8"))

    client_read = dump("ItemSparse", *tact, "--raw-out", str(tmp_path / "ItemSparse.db2"))
    hot = client_read["hotfixes"]
    assert client_read["source"] == "client" and client_read["keys"] > 0
    assert hot["build"] == int(client_read["build"].rsplit(".", 1)[1])
    assert client_read["rowCount"] == hot["rowsFromFiles"] + hot["added"] - hot["deletesApplied"]

    raw = ["--db2-file", str(tmp_path / "ItemSparse.db2"), "--build", client_read["build"]]
    raw_read = dump("ItemSparse", *raw)
    assert raw_read["source"] == "db2-file" and "keys" not in raw_read
    assert raw_read["rows"] == client_read["rows"]

    item = dump("Item", *tact)  # the deletes of the files' rows are ignored
    assert item["rowCount"] >= item["hotfixes"]["rowsFromFiles"]
