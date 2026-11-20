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
    beta = tmp_path / "wow" / "_classic_beta_"
    (beta / "Interface" / "AddOns").mkdir(parents=True)
    config = tmp_path / "install.toml"
    config.write_text(f'[clients]\nforever = "{beta.as_posix()}"\n' + build, encoding="utf-8")
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
    with pytest.raises(build_client.BuildClientError, match="client must be"):
        build_client.read_inputs("retail", config)  # no client of ours since 15.11.2026
    with pytest.raises(build_client.BuildClientError, match="missing"):
        build_client.read_inputs("forever", tmp_path / "nope.toml")
    config.write_text("[clients]\n", encoding="utf-8")
    with pytest.raises(build_client.BuildClientError, match="no client folder"):
        build_client.read_inputs("forever", config)


def _engine(tmp_path: Path, monkeypatch, version: str, sets: tuple[str, ...]) -> Path:
    """A client with `.build.info` above it (as on the desktop) and the named dump sets."""
    config = make_config(tmp_path)
    info = tmp_path / "wow" / ".build.info"
    info.write_text(f"Product!STRING:0|Version!STRING:0\nwowf|{version}\n", encoding="utf-8")
    dumps = tmp_path / "out"
    dumps.mkdir()
    for prefix in sets:
        for table in ("Map", "ItemSparse"):
            (dumps / f"{prefix}_{table}.json").write_text("{}", encoding="utf-8")
    monkeypatch.setattr(build_client, "DUMPS", dumps)
    return config


def test_the_build_takes_the_dumps_of_the_clients_own_build(tmp_path, monkeypatch):
    # plan-data-quality.md E2 to E4: no prefix pinned by hand; tools/engine.py writes f<build>
    config = _engine(tmp_path, monkeypatch, "1.60.1.70938", ("f70862", "f70938"))
    inputs = build_client.read_inputs("forever", config)
    assert (inputs.prefix, inputs.prefix_note) == ("f70938", None)


def test_without_the_builds_dumps_the_newest_older_set_and_a_note(tmp_path, monkeypatch):
    config = _engine(tmp_path, monkeypatch, "1.60.1.70950", ("f70862", "f70938", "f71000"))
    inputs = build_client.read_inputs("forever", config)
    assert inputs.prefix == "f70938"
    assert inputs.prefix_note == "no engine dumps for 1.60.1.70950 yet: built on f70938"


def test_a_pinned_prefix_still_wins_and_the_mirror_keeps_build_info_at_its_root(
    tmp_path, monkeypatch
):
    config = _engine(tmp_path, monkeypatch, "1.60.1.70938", ("f70938",))
    pinned = config.read_text(encoding="utf-8") + '[build.dump_prefix]\nforever = "f70862"\n'
    config.write_text(pinned, encoding="utf-8")
    assert build_client.read_inputs("forever", config).prefix == "f70862"
    mirror = tmp_path / "mirror"
    mirror.mkdir()
    (mirror / ".build.info").write_text("Product!STRING:0|Version!STRING:0\nwowf|1.60.1.70938\n")
    assert build_client.engine_prefix(mirror) == ("f70938", None)
    assert build_client.engine_prefix(tmp_path / "nowhere")[0] == "beta"


def test_the_source_addons_can_live_outside_a_client_that_is_gone(tmp_path):
    # 24.10.2026: the Forever beta was uninstalled; its source addons are kept apart
    kept = tmp_path / "sources" / "forever"
    kept.mkdir(parents=True)
    config = make_config(tmp_path, f'[build.sources]\nforever = "{kept.as_posix()}"\n')
    (tmp_path / "wow" / "_classic_beta_" / "Interface" / "AddOns").rmdir()
    assert build_client.read_inputs("forever", config).addons == kept
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
    assert build_client.main(["--client", "forever", "--dry-run", "--config", str(config)]) == 0
    out = capsys.readouterr().out
    assert "> data --client forever --addons" in out and "note: no tile lists" in out
    assert build_client.main(["--client", "forever", "--config", str(tmp_path / "x.toml")]) == 2


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
    found by itself or named in install.toml."""
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


def test_the_long_texts_come_from_tdb_texts_else_the_tdb_dump(tmp_path):
    """Forever's long quest texts (data.md "Game data in other languages"): [build.tdb_texts], else
    [build.tdb] as a path or under the `retail` key an install.toml of the retail days names it."""
    dump = tmp_path / "TDB_full_world.sql"
    dump.write_text("x", encoding="utf-8")
    for build in (
        f'[build.tdb_texts]\nforever = "{dump.as_posix()}"\n',
        f'[build]\ntdb = "{dump.as_posix()}"\n',
        f'[build.tdb]\nretail = "{dump.as_posix()}"\n',
    ):
        config = make_config(tmp_path / str(len(build)), build)
        inputs = build_client.read_inputs("forever", config)
        assert inputs.tdb_texts == dump, build
        data = build_client.commands(inputs, tmp_path / "packs", skip_mapart=True)[0]
        assert data[data.index("--tdb-texts") + 1] == str(dump) and "--tdb" not in data
    assert build_client.read_inputs("forever", make_config(tmp_path / "none")).tdb_texts is None


def test_the_build_takes_the_newest_probe_of_the_clients_build(tmp_path, monkeypatch):
    # plan-data-quality.md E5: [build.probe] "auto", the records tools/engine.py imports
    config = _engine(tmp_path, monkeypatch, "1.60.1.70938", ("f70938",))
    imported, kept = tmp_path / "local-probe", tmp_path / "data-probe"
    imported.mkdir()
    kept.mkdir()
    for folder, name in (
        (kept, "2026-10-23-forever-70532.lua"),
        (imported, "2026-11-16-forever-70938.lua"),
        (imported, "2026-11-18-forever-70938.lua"),
    ):
        (folder / name).write_text("BastiansProbeDB = {}\n", encoding="utf-8")
    client = tmp_path / "wow" / "_classic_beta_"
    path, note = build_client.engine_probe(client, (imported, kept))
    assert path == imported / "2026-11-18-forever-70938.lua" and note is None
    (imported / "2026-11-16-forever-70938.lua").unlink()
    (imported / "2026-11-18-forever-70938.lua").unlink()
    path, note = build_client.engine_probe(client, (imported, kept))
    assert path == kept / "2026-10-23-forever-70532.lua"
    assert note.startswith("the probe is of build 70532 (2026-10-23), the client 1.60.1.70938")
    assert build_client.engine_probe(client, (tmp_path / "none",)) == (
        None,
        "no probe record: the build's checks against the game are missing",
    )
    config.write_text(config.read_text("utf-8") + '[build.probe]\nforever = "auto"\n', "utf-8")
    monkeypatch.setattr(build_client, "engine_probe", lambda c: (kept / "x.lua", "a note"))
    inputs = build_client.read_inputs("forever", config)
    assert (inputs.probe, inputs.probe_note) == (kept / "x.lua", "a note")
