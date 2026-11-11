"""tools/build_client.py: the one-command rebuild of a client's generated files (inputs from
.local/install.toml, the data, mapart and nav invocations, dry run)."""

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

import build_client  # noqa: E402


@pytest.fixture(autouse=True)
def no_real_api_rows(tmp_path: Path, monkeypatch):
    """AHSync's fetch of ForeverDB's API on this machine is no input of these tests."""
    monkeypatch.setattr(build_client, "FOREVERDB_API", tmp_path / "no-api")


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


def test_the_source_addons_can_live_outside_a_client_that_is_gone(tmp_path):
    # 24.10.2026: the Forever beta was uninstalled; its source addons are kept apart
    kept = tmp_path / "sources" / "forever"
    kept.mkdir(parents=True)
    config = make_config(tmp_path, f'[build.sources]\nforever = "{kept.as_posix()}"\n')
    (tmp_path / "wow" / "_classic_beta_" / "Interface" / "AddOns").rmdir()
    assert build_client.read_inputs("forever", config).addons == kept
    assert build_client.read_inputs("retail", config).addons.name == "AddOns"  # unchanged
    config.write_text(
        config.read_text(encoding="utf-8").replace(kept.as_posix(), (tmp_path / "x").as_posix()),
        encoding="utf-8",
    )
    with pytest.raises(build_client.BuildClientError, match=r"\[build.sources\] forever"):
        build_client.read_inputs("forever", config)


def test_commands_run_data_then_mapart_when_the_extracts_exist_then_nav(tmp_path, monkeypatch):
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
    assert [c[3] for c in cmds] == ["data", "nav"]  # nav writes the stub without graphs
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
    assert [c[3] for c in cmds] == ["data", "mapart", "nav"]
    assert "--overview" not in cmds[1]
    (dumps / "ov_beta").mkdir()
    cmds = build_client.commands(inputs, tmp_path / "addons")
    assert cmds[1][cmds[1].index("--overview") + 1] == str(dumps / "ov_beta")
    skipped = build_client.commands(inputs, tmp_path / "addons", skip_mapart=True)
    assert [c[3] for c in skipped] == ["data", "nav"]


def test_dry_run_prints_the_commands(tmp_path, monkeypatch, capsys):
    config = make_config(tmp_path)
    monkeypatch.setattr(build_client, "DUMPS", tmp_path / "out")
    assert build_client.main(["--client", "retail", "--dry-run", "--config", str(config)]) == 0
    out = capsys.readouterr().out
    assert "> data --client retail --addons" in out and "note: no tile lists" in out
    assert build_client.main(["--client", "retail", "--config", str(tmp_path / "x.toml")]) == 2


def test_a_forever_build_passes_the_books_pictures_and_last_state(tmp_path, monkeypatch, capsys):
    """after a build_client run the book showed no picture of Bastian
    and only generic marks on its story map; the pages lost their picture flag because only
    tools/data_update.py passed --art and --book-previous. A Forever build passes both now."""
    import data_update

    art = tmp_path / "art"
    art.mkdir()
    (art / "some-page.jpg").write_bytes(b"x")
    states = tmp_path / "states"
    states.mkdir()
    (states / "s1.json").write_text("{}", encoding="utf-8")
    ledger = tmp_path / "ledger.json"
    ledger.write_text(
        '{"editions": [{"date": "2026-11-06", "n": 1, "sha256": "a", "sent": true,'
        ' "book_state": "s1.json"}]}',
        encoding="utf-8",
    )
    monkeypatch.setattr(data_update, "LEDGER", ledger)
    monkeypatch.setattr(data_update, "BOOK_STATES", states)
    monkeypatch.setattr(data_update, "LOCAL_ART", art)
    config = make_config(tmp_path)
    inputs = build_client.read_inputs("forever", config)
    extra, folder = build_client.book_args(inputs)
    assert extra == ["--book-previous", str(states / "s1.json"), "--art", str(art)]
    assert folder == art
    monkeypatch.setattr(build_client, "DUMPS", tmp_path / "out")
    assert build_client.main(["--client", "forever", "--dry-run", "--config", str(config)]) == 0
    out = capsys.readouterr().out
    assert f"--art {art}" in out and "--book-previous" in out


def test_this_machines_inputs_have_a_hash_and_say_what_they_are(tmp_path: Path):
    """plan-nightly-content.md F8 and F14: a new client dump, mirror commit or language lookup is
    new input for the edition, and two machines can compare what they build from."""
    dumps = tmp_path / "out"
    dumps.mkdir()
    (dumps / "f70862_Map.json").write_text("{}", encoding="utf-8")
    (dumps / "other_Map.json").write_text("{}{}", encoding="utf-8")
    mirror = tmp_path / "cmangos"
    (mirror / ".git" / "refs" / "heads").mkdir(parents=True)
    (mirror / ".git" / "HEAD").write_text("ref: refs/heads/master\n", encoding="utf-8")
    (mirror / ".git" / "refs" / "heads" / "master").write_text("ec4f596aaaaabbbbb\n", "utf-8")
    l10n = tmp_path / "l10n"
    l10n.mkdir()
    (l10n / "frFR.lua").write_text("x" * 10, encoding="utf-8")
    inputs = build_client.BuildInputs("forever", tmp_path, "f70862", cmangos=mirror, l10n=l10n)
    first, parts = build_client.local_inputs(inputs, dumps)
    assert parts == [
        "dumps f70862: 1 files, 2 bytes",
        "cmangos: ec4f596aaaaa",
        "l10n: 1 files, 10 bytes",
        "long texts: 0 files, 0 bytes",
        "ForeverDB API: 0 files, 0 bytes",
    ]
    assert build_client.local_inputs(inputs, dumps)[0] == first  # the same inputs, the same hash
    (l10n / "frFR.lua").write_text("x" * 11, encoding="utf-8")
    assert build_client.local_inputs(inputs, dumps)[0] != first
    bare = build_client.BuildInputs("forever", tmp_path, "none")
    assert build_client.local_inputs(bare, tmp_path / "missing")[1][:2] == [
        "dumps none: 0 files, 0 bytes",
        "cmangos: none",
    ]


def test_the_api_rows_ride_the_forever_build_when_ahsync_fetched_them(tmp_path, monkeypatch):
    """ForeverDB's API (data.md): AHSync's last complete fetch is an input of the Forever build,
    found by itself or named in install.toml; retail never reads it."""
    monkeypatch.setattr(build_client, "DUMPS", tmp_path / "out")
    config = make_config(tmp_path)
    assert build_client.read_inputs("forever", config).foreverdb_api is None
    latest = tmp_path / "latest"
    latest.mkdir()
    (latest / "quests.json").write_text("[]", encoding="utf-8")
    monkeypatch.setattr(build_client, "FOREVERDB_API", latest)
    inputs = build_client.read_inputs("forever", config)
    assert inputs.foreverdb_api == latest
    data = build_client.commands(inputs, tmp_path / "packs", skip_mapart=True)[0]
    assert data[data.index("--foreverdb-api") + 1] == str(latest)
    assert build_client.read_inputs("retail", config).foreverdb_api is None
