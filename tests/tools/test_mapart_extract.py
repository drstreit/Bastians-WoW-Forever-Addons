"""tools/mapart_extract.py: the per-continent clientdump plan (pure) and the dry run."""

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

import mapart_extract  # noqa: E402

from bastians_build.sources import clientdump  # noqa: E402

MAPS_JSON = ROOT / "tests" / "fixtures" / "sources" / "clientdump" / "Map.json"


def test_plan_runs_every_continent_once_and_skips_what_exists(tmp_path):
    maps = clientdump.read_maps(MAPS_JSON)
    continents = {0: "Eastern Kingdoms", 530: "Outland"}
    out, overview = tmp_path / "mm", tmp_path / "ov"
    jobs = mapart_extract.plan(continents, maps, out, overview)
    assert [(j.map_id, j.directory, j.skip) for j in jobs] == [
        (0, "Azeroth", None),
        (530, "Expansion01", None),
    ]
    assert jobs[0].wdt == maps[0].wdt_file_id
    # outputs present: skipped unless forced; --only picks one map by directory or id
    out.mkdir()
    overview.mkdir()
    (out / "Azeroth_tiles.txt").write_text("1\t1\t5\n", encoding="utf-8")
    (overview / "Azeroth_overview.json").write_text("{}", encoding="utf-8")
    jobs = mapart_extract.plan(continents, maps, out, overview)
    assert [j.skip for j in jobs] == ["exists", None]
    assert [j.skip for j in mapart_extract.plan(continents, maps, out, overview, force=True)] == [
        None,
        None,
    ]
    assert [
        j.skip for j in mapart_extract.plan(continents, maps, out, overview, only="expansion01")
    ] == ["not selected", None]
    assert [j.skip for j in mapart_extract.plan(continents, maps, out, overview, only="0")] == [
        "exists",
        "not selected",
    ]


def test_commands_name_the_map_its_wdt_and_the_resolution(tmp_path):
    job = mapart_extract.Job(0, "Eastern Kingdoms", "Azeroth", 775971, tmp_path, tmp_path, None)
    minimap, overview = mapart_extract.commands(
        job, Path("C:/wow/_retail_"), tmp_path / "mm", tmp_path / "ov", 8, 32
    )
    assert minimap[8] == "minimap" and overview[8] == "overview"
    assert "--wdt-fdid" in minimap and minimap[minimap.index("--wdt-fdid") + 1] == "775971"
    assert overview[overview.index("--pixels") + 1] == "32"
    assert overview[overview.index("--span") + 1] == "8"
    assert overview[overview.index("--alpha") + 1] == "dxt1"
    dxt5 = mapart_extract.commands(
        job, Path("C:/wow/_retail_"), tmp_path / "mm", tmp_path / "ov", 8, 32, "dxt5"
    )[1]
    assert dxt5[dxt5.index("--alpha") + 1] == "dxt5"
    assert "--sea" not in dxt5  # transparent water without a sea tone
    sea = mapart_extract.commands(
        job, Path("C:/wow/_retail_"), tmp_path / "mm", tmp_path / "ov", 8, 32, "dxt1", "b8a380"
    )[1]
    assert sea[sea.index("--sea") + 1] == "b8a380"  # the painted sea
    assert "--no-build" in minimap


def test_dry_run_prints_the_commands_without_a_client(tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(mapart_extract, "CONFIG_PATH", tmp_path / "install.toml")
    assert mapart_extract.main(["--client", "forever", "--prefix", "x", "--dry-run"]) == 2
    assert "no client folder" in capsys.readouterr().err
    (tmp_path / "install.toml").write_text(
        f'[clients]\nforever = "{tmp_path.as_posix()}"\n', encoding="utf-8"
    )
    dumps = tmp_path / "out"
    dumps.mkdir()
    for name in ("Map", "UiMap", "UiMapAssignment"):
        src = MAPS_JSON.with_name(f"{name}.json")
        (dumps / f"x_{name}.json").write_bytes(src.read_bytes())
    monkeypatch.setattr(mapart_extract, "DUMPS", dumps)
    code = mapart_extract.main(
        ["--client", "retail", "--prefix", "x", "--dry-run", "--out", str(tmp_path / "mm")]
    )
    out = capsys.readouterr()
    assert code == 2 and "no client folder for retail" in out.err
    code = mapart_extract.main(
        ["--client", "forever", "--prefix", "x", "--dry-run", "--out", str(tmp_path / "mm")]
    )
    out = capsys.readouterr().out
    assert code == 0
    assert "continents, span 8, 64 px per tile" in out
    assert " overview --install" in out and "--pixels 64" in out
    assert "next: python -m bastians_build mapart --client forever" in out


@pytest.mark.parametrize("client", ["forever", "retail"])
def test_resolution_follows_the_client(client):
    from bastians_build.config import load_config

    assert load_config().mapart.pixels_for(client) == 64  # full resolution
