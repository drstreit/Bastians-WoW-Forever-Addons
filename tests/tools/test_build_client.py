"""tools/build_client.py: the one-command rebuild of a client's generated files (inputs from
.local/install.toml, the data and mapart invocations, dry run)."""

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

import build_client  # noqa: E402


def make_config(tmp_path: Path, build: str = "") -> Path:
    client = tmp_path / "wow" / "_retail_"
    (client / "Interface" / "AddOns").mkdir(parents=True)
    beta = tmp_path / "wow" / "_classic_beta_"
    (beta / "Interface" / "AddOns").mkdir(parents=True)
    config = tmp_path / "install.toml"
    config.write_text(
        f'[clients]\nforever = "{beta.as_posix()}"\nretail = "{client.as_posix()}"\n' + build,
        encoding="utf-8",
    )
    return config


def test_inputs_come_from_the_install_config(tmp_path):
    cmangos = tmp_path / "db" / "cmangos"  # absolute on every platform (CI runs on Linux)
    config = make_config(
        tmp_path,
        f'[build]\ncmangos = "{cmangos.as_posix()}"\n'
        '[build.ground_truth]\nforever = "data/ground-truth/x.csv"\n'
        '[build.probe]\nforever = "data/probe/x.lua"\n'
        '[build.dump_prefix]\nforever = "beta2"\n',
    )
    forever = build_client.read_inputs("forever", config)
    assert forever.addons == tmp_path / "wow" / "_classic_beta_" / "Interface" / "AddOns"
    assert forever.probe == ROOT / "data" / "probe" / "x.lua"
    assert "--probe" in build_client.commands(forever, tmp_path)[0]
    assert forever.prefix == "beta2" and forever.cmangos == cmangos
    assert forever.ground_truth == ROOT / "data" / "ground-truth" / "x.csv"
    retail = build_client.read_inputs("retail", config)
    assert retail.prefix == "retail" and retail.cmangos is None  # CMaNGOS is Forever data only
    assert retail.ground_truth is None  # the measured places are Forever's
    with pytest.raises(build_client.BuildClientError, match="client must be"):
        build_client.read_inputs("classic", config)
    with pytest.raises(build_client.BuildClientError, match="missing"):
        build_client.read_inputs("retail", tmp_path / "nope.toml")
    config.write_text("[clients]\n", encoding="utf-8")
    with pytest.raises(build_client.BuildClientError, match="no client folder"):
        build_client.read_inputs("retail", config)


def test_commands_run_data_then_mapart_when_the_extracts_exist(tmp_path, monkeypatch):
    dumps = tmp_path / "out"
    dumps.mkdir()
    monkeypatch.setattr(build_client, "DUMPS", dumps)
    inputs = build_client.BuildInputs(
        "forever",
        tmp_path / "AddOns",
        "beta",
        cmangos=Path("C:/db"),
        ground_truth=Path("C:/gt.csv"),
    )
    cmds = build_client.commands(inputs, tmp_path / "addons")
    assert len(cmds) == 1 and cmds[0][3] == "data"
    data = cmds[0]
    assert data[data.index("--dump-prefix") + 1] == "beta"
    assert (
        data[data.index("--cmangos") + 1] == "C:\\db"
        or data[data.index("--cmangos") + 1] == "C:/db"
    )
    assert "--ground-truth" in data and "--export" not in data
    (dumps / "mm_beta").mkdir()
    (dumps / "beta_Map.json").write_text("{}", encoding="utf-8")
    cmds = build_client.commands(inputs, tmp_path / "addons")
    assert [c[3] for c in cmds] == ["data", "mapart"]
    assert "--overview" not in cmds[1]
    (dumps / "ov_beta").mkdir()
    cmds = build_client.commands(inputs, tmp_path / "addons")
    assert cmds[1][cmds[1].index("--overview") + 1] == str(dumps / "ov_beta")
    assert build_client.commands(inputs, tmp_path / "addons", skip_mapart=True)[-1][3] == "data"


def test_dry_run_prints_the_commands(tmp_path, monkeypatch, capsys):
    config = make_config(tmp_path)
    monkeypatch.setattr(build_client, "DUMPS", tmp_path / "out")
    assert build_client.main(["--client", "retail", "--dry-run", "--config", str(config)]) == 0
    out = capsys.readouterr().out
    assert "> data --client retail --addons" in out and "note: no tile lists" in out
    assert build_client.main(["--client", "retail", "--config", str(tmp_path / "x.toml")]) == 2
