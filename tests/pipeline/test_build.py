"""The build: fixture world -> packs -> report; deterministic, atomic, golden pack committed."""

import dataclasses
from pathlib import Path

import pytest

from bastians_build.__main__ import main
from bastians_build.build import build, validate
from bastians_build.config import ConfigError, load_config
from bastians_build.files import write_text
from bastians_build.model import World
from bastians_build.sources.fixture import FixtureError, read_fixture

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests" / "fixtures" / "world-mini"
GOLDEN = ROOT / "tests" / "fixtures" / "addons" / "Bastians_Data_World" / "Generated" / "World.lua"


def test_fixture_reader_builds_the_world():
    world = read_fixture(FIXTURE, "forever")
    assert world.build == "fixture" and world.sources == ["hand-written fixture world-mini"]
    assert world.count("npc") == 7 and world.count("quest") == 5 and world.count("zone") == 5
    assert world.get("npc", 448)["name"] == "Hogger"
    assert world.get("npc", 327).get("flags") is None  # unknown stays None
    with pytest.raises(FixtureError, match="is for forever"):
        read_fixture(FIXTURE, "retail")


def test_build_is_deterministic_and_idempotent(tmp_path):
    config = load_config()
    world = read_fixture(FIXTURE, "forever")
    first = build(world, config, tmp_path / "a")
    second = build(read_fixture(FIXTURE, "forever"), config, tmp_path / "b")
    assert first.ok and second.ok
    for pa, pb in zip(first.packs, second.packs, strict=True):
        assert pa.path.read_bytes() == pb.path.read_bytes()
        assert pa.changed is True
    again = build(world, config, tmp_path / "a")
    assert all(p.changed is False for p in again.packs)  # nothing rewritten
    assert (tmp_path / "a" / "report.md").read_text(encoding="utf-8") == (
        tmp_path / "b" / "report.md"
    ).read_text(encoding="utf-8")


def test_committed_golden_pack_matches_a_fresh_build(tmp_path):
    """data.md acceptance 1: the Lua tests load exactly what the generator produces."""
    result = build(read_fixture(FIXTURE, "forever"), load_config(), tmp_path)
    hint = (
        "regenerate with: python -m bastians_build data --client forever "
        "--fixture tests/fixtures/world-mini --out tests/fixtures/addons"
    )
    for p in result.packs:
        golden = GOLDEN.parents[2] / p.pack.addon / "Generated" / p.pack.file
        assert golden.is_file(), f"{golden} missing; {hint}"
        assert p.path.read_text(encoding="utf-8") == golden.read_text(encoding="utf-8"), hint


def test_pack_content_follows_the_schema():
    result = build(read_fixture(FIXTURE, "forever"), load_config(), Path("unused"), write=False)
    by_name = {p.pack.name: p for p in result.packs}
    assert by_name["world"].counts == {
        "flightpath": 5,
        "node": 0,
        "npc": 7,
        "object": 1,
        "transport": 2,
        "zone": 5,
    }
    assert by_name["quests"].counts == {"attunement": 2, "quest": 5}
    assert by_name["world"].index_counts["npc.byZone"] == 2
    assert by_name["quests"].index_counts["quest.byGiver"] == 3
    from bastians_build.pack import pack_table

    config = load_config()
    world = pack_table(result.world, config.packs["world"])
    fields = config.packs["world"].schema["npc"]
    hogger = dict(zip(fields, world["npc"][448], strict=True))
    assert (hogger["name"], hogger["level"], hogger["zone"], hogger["flags"]) == (
        "Hogger",
        11,
        1429,
        "elite",
    )
    assert hogger["spawns"] == [[1429, 0.27, 0.86, "eq"], [1429, 0.3, 0.8, "questie"]]
    assert hogger["subname"] is None  # positional nil for an unknown field
    assert world["index"]["npc.byZone"][1429] == [54, 198, 240, 295, 327, 448]
    quests = pack_table(result.world, config.packs["quests"])
    assert quests["index"]["quest.byGiver"]["npc:240"] == [62, 76]


def test_validation_reports_bad_refs_and_unknown_types():
    config = load_config()
    world = World(client="forever")
    world.add("quest", 1, {"name": "Q", "starts": ["npc:1", "nonsense", "dragon:3"]})
    world.add("mystery", 7, {"name": "?"})
    problems = validate(world, config)
    assert any("bad ref 'nonsense'" in p for p in problems)
    assert any("unknown type 'dragon'" in p for p in problems)
    assert any("'mystery'" in p for p in problems)
    result = build(world, config, Path("unused"), write=False)
    assert not result.ok and result.packs == []


def test_report_lists_sizes_budgets_and_dropped_rows(tmp_path):
    world = read_fixture(FIXTURE, "forever")
    world.drop("npc", 999, "no spawn fits a Forever map")
    build(world, load_config(), tmp_path)
    text = (tmp_path / "report.md").read_text(encoding="utf-8")
    assert "| world | Bastians_Data_World |" in text and "12288 KB" in text
    assert "npc 7" in text and "quest.byGiver 3" in text
    assert "- no spawn fits a Forever map: 1 rows: npc 999" in text
    assert "20" not in text.split("Client")[0]  # no date in the header


def test_budget_breach_is_flagged(tmp_path):
    config = load_config()
    packs = dict(config.packs)
    packs["world"] = dataclasses.replace(packs["world"], budget_kb=0)
    config = dataclasses.replace(config, packs=packs)
    result = build(read_fixture(FIXTURE, "forever"), config, tmp_path)
    assert result.packs[0].over_budget and not result.ok
    assert "**OVER**" in (tmp_path / "report.md").read_text(encoding="utf-8")


def test_atomic_write_leaves_no_temp_file(tmp_path):
    target = tmp_path / "deep" / "file.lua"
    assert write_text(target, "a\n") is True
    assert write_text(target, "a\n") is False
    assert write_text(target, "b\n") is True
    assert sorted(p.name for p in target.parent.iterdir()) == ["file.lua"]
    assert target.read_bytes() == b"b\n"


def test_config_rejects_a_type_in_two_packs(tmp_path):
    bad = tmp_path / "build.toml"
    bad.write_text(
        '[packs.a]\naddon="A"\nfile="A.lua"\n[packs.a.schema]\nnpc=["name"]\n'
        '[packs.b]\naddon="B"\nfile="B.lua"\n[packs.b.schema]\nnpc=["name"]\n',
        encoding="utf-8",
    )
    with pytest.raises(ConfigError, match="in packs a and b"):
        load_config(bad)


def test_cli_builds_checks_and_reports_errors(tmp_path, capsys):
    # the report goes to the temp folder: the default is the repo's build/ (CLAUDE.md section 7)
    report = ["--report-dir", str(tmp_path / "report")]
    assert (
        main(
            [
                "data",
                "--client",
                "forever",
                "--fixture",
                str(FIXTURE),
                "--out",
                str(tmp_path),
                *report,
            ]
        )
        == 0
    )
    out = capsys.readouterr().out
    assert "written:" in out and "report:" in out
    assert (
        main(
            [
                "check",
                "--client",
                "forever",
                "--fixture",
                str(FIXTURE),
                "--out",
                str(tmp_path / "x"),
                *report,
            ]
        )
        == 0
    )
    assert not (tmp_path / "x").exists()
    assert (
        main(["data", "--client", "retail", "--fixture", str(FIXTURE), "--out", str(tmp_path)]) == 2
    )
    assert "is for forever" in capsys.readouterr().err
    assert main(["data", "--client", "forever", "--out", str(tmp_path)]) == 2
