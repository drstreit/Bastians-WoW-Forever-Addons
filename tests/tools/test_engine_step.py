"""tools/engine.py: every client build and hotfix push dumped, compared and handed to the notebook
(ADR 0039, plan-data-quality.md E2 to E4), against a fake clientdump."""

import io
import json
import subprocess
import tarfile
from pathlib import Path

import engine


class FakeClient:
    """Stands in for clientdump and ssh: writes small dumps the way clientdump does."""

    def __init__(self, files_build=70938, cache_build=70938, push=100):
        self.files_build = files_build
        self.cache_build = cache_build
        self.push = push
        self.rows = {}  # table -> rows, else one row
        self.fail = set()
        self.calls = []
        self.sent = None

    def __call__(self, cmd, **kw):
        if cmd[0] == "ssh":
            self.sent = (cmd, kw.get("input"))
            return subprocess.CompletedProcess(cmd, 0)
        opt = {cmd[i]: cmd[i + 1] for i in range(1, len(cmd) - 1) if cmd[i].startswith("--")}
        table, out = opt["--table"], Path(opt["--out"])
        self.calls.append((table, opt.get("--locale"), "--hotfixes" in opt))
        if table in self.fail:
            return subprocess.CompletedProcess(cmd, 1)
        data = {
            "table": table,
            "build": f"1.60.1.{self.files_build}",
            "columns": ["ID", "Name"],
            "rows": self.rows.get(table, [[1, f"{table} one"]]),
        }
        if "--hotfixes" in opt:
            if self.cache_build != self.files_build:
                return subprocess.CompletedProcess(cmd, 1)  # clientdump refuses another build's
            data["hotfixes"] = {"build": self.cache_build, "highestPush": self.push}
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(data), encoding="utf-8")
        return subprocess.CompletedProcess(cmd, 0)


def setup(tmp_path: Path, version="1.60.1.70938"):
    install = tmp_path / "Spiele" / "_forever_"
    cache = install / "Cache" / "ADB" / "enUS" / "DBCache.bin"
    cache.parent.mkdir(parents=True)
    cache.write_bytes(b"XFTH one")
    info = tmp_path / "Spiele" / ".build.info"
    info.write_text(
        "Product!STRING:0|Version!STRING:0|Tags!STRING:0\n"
        f"wowf|{version}|Windows x86_64 EU? deDE speech?:deDE text?:enUS speech?:enUS text?\n",
        encoding="utf-8",
    )
    dumps = tmp_path / "out"
    dumps.mkdir()
    return install, info, dumps


def run_step(tmp_path, fake, *, version="1.60.1.70938", running=False, send=False, **kw):
    install, info, dumps = tmp_path / "Spiele" / "_forever_", None, tmp_path / "out"
    info = tmp_path / "Spiele" / ".build.info"
    return engine.step(
        install=install,
        build_info=info,
        dumps=dumps,
        state_path=dumps / "engine-forever.json",
        records=tmp_path / "records",
        copies=tmp_path / "hotfixes",
        do_send=send,
        run=fake,
        running=lambda: running,
        client_build=lambda _p: version,
        **kw,
    )


def state(tmp_path):
    return json.loads((tmp_path / "out" / "engine-forever.json").read_text(encoding="utf-8"))


def test_a_new_build_is_dumped_with_the_hotfixes_in_the_caches_language_only(tmp_path):
    setup(tmp_path)
    fake = FakeClient()
    res = run_step(tmp_path, fake)
    assert not res.failed and res.dumped == "f70938"
    assert engine.complete(tmp_path / "out", "f70938", ["deDE"])
    dumped = [c for c in fake.calls if c[0] != engine.PROBE_TABLE or c[1]]
    # an English cache over the German names turned them English (15.11.2026): never there
    assert all(not hot for _t, loc, hot in fake.calls if loc)
    assert any(loc == "deDE" for _t, loc, _h in dumped)
    assert all(hot for t, loc, hot in fake.calls[2:] if not loc), "the base tables get the cache"
    s = state(tmp_path)
    assert (s["build"], s["prefix"], s["push"], s["hotfixes"]) == (
        "1.60.1.70938",
        "f70938",
        100,
        True,
    )
    assert (tmp_path / "hotfixes" / "1.60.1.70938" / "100.bin").read_bytes() == b"XFTH one"
    assert (tmp_path / "records" / "forever-1.60.1.70938-100.md").is_file()
    assert "with hotfix push 100" in res.lines[-1]
    assert not list((tmp_path / "out").glob(".engine-*"))  # the temp folder is gone


def test_nothing_is_read_while_a_game_client_runs(tmp_path):
    setup(tmp_path)
    fake = FakeClient()
    res = run_step(tmp_path, fake, running=True)
    assert "a game client runs" in res.lines[0] and fake.calls == []


def test_a_client_still_patching_waits_for_the_next_hour(tmp_path):
    setup(tmp_path, "1.60.1.70950")
    fake = FakeClient(files_build=70938)
    res = run_step(tmp_path, fake, version="1.60.1.70950")
    assert "patching" in res.lines[0]
    assert not engine.complete(tmp_path / "out", "f70950", ["deDE"])
    assert not (tmp_path / "out" / "engine-forever.json").exists()


def test_an_unchanged_cache_reads_nothing(tmp_path):
    setup(tmp_path)
    run_step(tmp_path, FakeClient())
    fake = FakeClient()
    res = run_step(tmp_path, fake)
    assert "hotfix cache unchanged" in res.lines[0] and fake.calls == []


def test_a_rewritten_cache_without_a_new_push_dumps_nothing_more(tmp_path):
    install, _info, _dumps = setup(tmp_path)
    run_step(tmp_path, FakeClient())
    (install / "Cache" / "ADB" / "enUS" / "DBCache.bin").write_bytes(b"XFTH rewritten")
    fake = FakeClient(push=100)
    res = run_step(tmp_path, fake)
    assert "push 100 not new" in res.lines[0]
    assert [c[0] for c in fake.calls] == [engine.PROBE_TABLE, engine.PROBE_TABLE]
    assert state(tmp_path)["sha256"] == engine.sha256(install / "Cache/ADB/enUS/DBCache.bin")


def test_a_grown_push_dumps_the_build_again_and_compares_push_to_push(tmp_path):
    install, _info, _dumps = setup(tmp_path)
    run_step(tmp_path, FakeClient(push=100))
    (install / "Cache" / "ADB" / "enUS" / "DBCache.bin").write_bytes(b"XFTH two")
    fake = FakeClient(push=101)
    fake.rows["ItemSparse"] = [[1, "ItemSparse one"], [2, "a hotfixed item"]]
    res = run_step(tmp_path, fake)
    assert res.dumped == "f70938" and state(tmp_path)["push"] == 101
    text = (tmp_path / "records" / "forever-1.60.1.70938-101.md").read_text(encoding="utf-8")
    assert "| ItemSparse | 1 -> 2 | 1 | 0 | 0 |" in text
    assert "Needs a rebuild: nothing" in text


def test_another_builds_cache_is_not_applied(tmp_path):
    setup(tmp_path)
    fake = FakeClient(cache_build=70862)
    res = run_step(tmp_path, fake)
    assert res.dumped == "f70938" and "without hotfixes" in res.lines[-1]
    assert state(tmp_path)["hotfixes"] is False and state(tmp_path)["push"] is None
    assert not (tmp_path / "hotfixes").exists()


def test_a_failed_table_keeps_the_set_before(tmp_path):
    setup(tmp_path)
    fake = FakeClient()
    fake.fail = {"TaxiNodes"}
    res = run_step(tmp_path, fake)
    assert res.failed and "1 tables failed (TaxiNodes.json)" in res.lines[-1]
    assert not list((tmp_path / "out").glob("f70938_*"))
    assert not (tmp_path / "out" / "engine-forever.json").exists()


def test_a_new_build_is_compared_with_the_one_before_and_names_the_rebuilds(tmp_path):
    setup(tmp_path)
    old = tmp_path / "out" / "f70862_UiMap.json"
    old.write_text(
        json.dumps(
            {"build": "1.60.1.70862", "columns": ["ID", "Name"], "rows": [[1, "an older map"]]}
        ),
        encoding="utf-8",
    )
    for table in ("Map", "TaxiNodes"):
        (tmp_path / "out" / f"f70862_{table}.json").write_text(
            json.dumps({"columns": ["ID", "Name"], "rows": [[1, f"{table} one"]]}),
            encoding="utf-8",
        )
    res = run_step(tmp_path, FakeClient())
    assert "against f70862: 1 of 3 tables changed" in res.lines[-1]
    assert "needs a rebuild: map art" in res.lines[-1]
    assert state(tmp_path)["previous"] == "f70862"


def test_the_set_and_the_state_go_to_the_notebook(tmp_path):
    setup(tmp_path)
    fake = FakeClient()
    res = run_step(tmp_path, fake, send=True)
    assert res.lines[-1] == "engine: f70938 sent to nbb"
    cmd, data = fake.sent
    assert cmd[:3] == ["ssh", "-o", "BatchMode=yes"] and engine.NOTEBOOK_OUT in cmd[-1]
    with tarfile.open(fileobj=io.BytesIO(data)) as tar:
        sent = tar.getnames()
    assert "engine-forever.json" in sent and "f70938_ItemSparse.deDE.json" in sent
    assert len([n for n in sent if n.startswith("f70938_")]) == len(engine.names(["deDE"]))
    assert state(tmp_path)["sent"]


def test_a_set_holds_every_table_the_build_reads():
    names = engine.names(["deDE", "frFR"])
    assert "ItemSparse.json" in names and "UiMapArtTile.json" in names
    assert "SpellName.frFR.json" in names and "Map.frFR.json" not in names
    assert len(engine.names([])) == len(engine.MAP_TABLES) + len(engine.client_tables.TABLES)
    assert engine.prefix_of("1.60.1.70938") == "f70938"


def saved_probe(tmp_path: Path, meta_build="70938", auto_build="70938", client="forever"):
    """Bastians_Probe's saved variables as the client writes them (the auto block first)."""
    install = tmp_path / "Spiele" / "_forever_"
    sv = install / "WTF" / "Account" / "ACCOUNT" / "SavedVariables" / "Bastians_Probe.lua"
    sv.parent.mkdir(parents=True, exist_ok=True)
    auto = f'["auto"] = {{\n["parts"] = "P1, P3, P2",\n["build"] = "{auto_build}",\n}},\n'
    meta = (
        f'["meta"] = {{\n["client"] = "{client}",\n["build"] = "{meta_build}",\n'
        '["updated"] = "2026-11-16T07:00:00Z",\n},\n'
    )
    sv.write_text("BastiansProbeDB = {\n" + (auto if auto_build else "") + meta + "}\n", "utf-8")
    return install


def test_a_finished_probe_run_is_imported_once_and_sent(tmp_path):
    install = saved_probe(tmp_path)
    fake = FakeClient()
    lines = engine.probe_step(install, tmp_path / "probes", run=fake)
    assert (tmp_path / "probes" / "2026-11-16-forever-70938.lua").is_file()
    assert lines[0] == "engine: the probe's record 2026-11-16-forever-70938.lua imported"
    cmd, data = fake.sent
    assert engine.NOTEBOOK_PROBES in cmd[-1] and data
    assert engine.probe_step(install, tmp_path / "probes", run=FakeClient()) == []  # once


def test_a_probe_run_not_finished_for_the_live_build_waits(tmp_path):
    # logged in on 70950, the automatic run of 70938 is the last finished one: not this build's
    install = saved_probe(tmp_path, meta_build="70950", auto_build="70938")
    lines = engine.probe_step(install, tmp_path / "probes", do_send=False)
    assert lines == ["engine: the probe has no finished run of build 70950 yet"]
    install = saved_probe(tmp_path / "b", auto_build=None)
    assert "no finished run" in engine.probe_step(install, tmp_path / "probes", do_send=False)[0]
    assert not (tmp_path / "probes").exists()
    assert "no probe record" in engine.probe_step(tmp_path / "nowhere", tmp_path / "p")[0]


def test_the_maps_tile_lists_are_extracted_once_for_every_build(tmp_path):
    """20.11.2026: the client went to 70959, the engine step dumped its tables, and the release
    cut did not boot: nobody had run tools/mapart_extract.py for the new prefix."""
    dumps = tmp_path / "out"
    dumps.mkdir()
    calls = []

    def run(cmd, **kw):
        calls.append(cmd)
        (dumps / "mm_f70959").mkdir(exist_ok=True)
        (dumps / "mm_f70959" / "Azeroth_tiles.txt").write_text("x", encoding="utf-8")
        (dumps / "ov_f70959").mkdir(exist_ok=True)
        (dumps / "ov_f70959" / "Azeroth_art.json").write_text("{}", encoding="utf-8")
        return subprocess.CompletedProcess(cmd, 0, "", "")

    common = {"dumps": dumps, "client_build": lambda info: "1.60.1.70959"}
    info = tmp_path / ".build.info"
    # the build's tables are not dumped yet: the next hour
    assert engine.map_art_step(info, run=run, running=lambda: False, **common) == []
    (dumps / "f70959_Map.json").write_text("{}", encoding="utf-8")
    # the game runs: clientdump cannot read the archives
    waits = engine.map_art_step(info, run=run, running=lambda: True, **common)
    assert "wait for the game client to close" in waits[0] and calls == []
    lines = engine.map_art_step(info, run=run, running=lambda: False, **common)
    assert lines == ["engine: the map's tile lists and overview of f70959 extracted"]
    assert calls[0][-4:] == ["--client", "forever", "--prefix", "f70959"]
    assert calls[0][1].endswith("mapart_extract.py")
    # a set that is there is left alone
    assert engine.map_art_step(info, run=run, running=lambda: False, **common) == []
    assert len(calls) == 1
    # a failure is one line with the tool's last words; no build known: nothing to do

    def broken(cmd, **kw):
        return subprocess.CompletedProcess(cmd, 2, "", "error: no client\n")

    other = {"dumps": dumps, "client_build": lambda info: "1.60.1.70960"}
    (dumps / "f70960_Map.json").write_text("{}", encoding="utf-8")
    failed = engine.map_art_step(info, run=broken, running=lambda: False, **other)
    assert failed == ["engine: the map's tile lists of f70960 failed: error: no client"]
    assert engine.map_art_step(info, dumps=dumps, client_build=lambda info: None) == []
