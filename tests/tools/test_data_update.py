"""tools/data_update.py (ADR 0019): changed data (the book, the prices) is a new edition of the Data
project with its own version, an unchanged one that was sent is left alone, the file carries the
loader and every pack, the whole install boots, and the changelog is What's new since the last
sent edition."""

import json
import shutil
import zipfile
from pathlib import Path

import build_client
import curseforge
import data_update
import pytest

ROOT = Path(__file__).resolve().parents[2]
FIXTURE_ADDONS = ROOT / "tests" / "fixtures" / "addons"

BOOK = """
clients = ["forever"]

[[news]]
date = "2026-10-23"
text = "The book opens with two strategies."
page = "baeldun-dig"

[[news]]
date = "2026-10-25"
text = "Four new farming pages."
"""


def fake_build(extra: dict[str, list[str]] | None = None):
    """The fixture packs as the build's output; `extra` = { pack folder: lines } appended to that
    pack's generated file (a changed book, new prices)."""

    def build(inputs: build_client.BuildInputs, packs: Path) -> None:
        # copyfile, not copytree: the copied folder attributes can make the next run's
        # overwrite fail on Windows
        for pack in FIXTURE_ADDONS.glob("Bastians_Data_*"):
            target = packs / pack.name / "Generated"
            target.mkdir(parents=True, exist_ok=True)
            for lua in (pack / "Generated").glob("*.lua"):
                shutil.copyfile(lua, target / lua.name)
                with (target / lua.name).open("a", encoding="utf-8") as fh:
                    fh.writelines(f"-- {line}\n" for line in (extra or {}).get(pack.name, []))
        nav = packs / "Bastians_Data_Nav" / "Generated"
        nav.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(
            FIXTURE_ADDONS / "Bastians_Data_Nav" / "Generated" / "Nav.lua", nav / "Nav.lua"
        )
        transforms = packs / "Bastians_Data" / "Generated"
        transforms.mkdir(parents=True, exist_ok=True)
        (transforms / "MapTransforms.lua").write_text(
            "-- GENERATED\n-- 2 maps on 1 continent, 2 exact; forever; from the fixture\n",
            encoding="utf-8",
        )
        (transforms / "Downloads.lua").write_text(  # the build's stub (build.py)
            "-- GENERATED\n-- no download counts in this forever build\n", encoding="utf-8"
        )

    return build


def inputs(tmp_path: Path) -> build_client.BuildInputs:
    export = tmp_path / "export"
    export.mkdir(exist_ok=True)
    (export / "LATEST").write_text("20261025T0600Z\n", encoding="utf-8")
    return build_client.BuildInputs(client="forever", addons=tmp_path, prefix="beta", export=export)


def test_an_edition_without_the_walk_network_is_refused(tmp_path):
    """2.0.0 and every release before shipped without Bastians_Data_Nav (06.11.2026)."""
    packs = tmp_path / "packs"
    fake_build()(inputs(tmp_path), packs)
    data_update.check_nav(packs)
    nav = packs / data_update.NAV
    nav.write_text(
        "-- GENERATED\n-- pack nav: no walk network in this forever build\n", encoding="utf-8"
    )
    with pytest.raises(data_update.DataUpdateError, match="stub"):
        data_update.check_nav(packs)
    nav.unlink()
    with pytest.raises(data_update.DataUpdateError, match="wrote no"):
        data_update.check_nav(packs)


def test_the_build_runs_the_nav_step_too(tmp_path, monkeypatch):
    ran = []
    monkeypatch.setattr(data_update, "stream", lambda cmd, cwd: ran.append(cmd[3]) or 0)
    data_update.run_build(inputs(tmp_path), tmp_path / "packs")
    assert ran == ["data", "nav"]


def test_the_suite_brings_its_data_and_the_data_its_packs():
    cfg = curseforge.load_config()
    install = data_update.project_folders(cfg, "Bastians_Suite")
    assert install[0] == "Bastians_Core" and "Bastians_Strategies" in install
    assert "Bastians_Data_World" in install and "Bastians_Data_Strategies" in install
    data = data_update.project_folders(cfg, "Bastians_Data")
    assert data[0] == "Bastians_Data" and "Bastians_Core" not in data  # optional back: no cycle


def test_editions_are_numbered_per_day_and_follow_the_data():
    ledger = {"editions": []}
    first, new = data_update.next_edition(ledger, "a", "2026-10-24")
    assert new and first["n"] == 1
    ledger["editions"].append(first)
    assert data_update.next_edition(ledger, "a", "2026-10-25") == (first, False)
    second, new = data_update.next_edition(ledger, "b", "2026-10-24")
    assert new and second["n"] == 2
    ledger["editions"].append(second)
    third, _ = data_update.next_edition(ledger, "c", "2026-10-25")
    assert third["n"] == 1
    assert data_update.version_suffix(second) == "+data.20261024.2"


def test_the_changelog_is_whats_new_since_the_last_sent_edition():
    import tomllib

    book = tomllib.loads(BOOK)
    log = data_update.changelog(book, {"The book opens with two strategies."}, "20261025T0600Z")
    assert "Four new farming pages." in log and "two strategies" not in log
    assert "AHSync export 20261025T0600Z" in log
    assert "two strategies" in data_update.changelog(book, set(), None)
    texts = {n["text"] for n in book["news"]}
    assert "up to date" in data_update.changelog(book, texts, None)


def test_a_daily_run_ships_changed_data_once(tmp_path: Path):
    ledger = tmp_path / "editions.json"
    book_toml = tmp_path / "book.toml"
    book_toml.write_text(BOOK, encoding="utf-8")
    common = {
        "ledger_path": ledger,
        "book_toml": book_toml,
        "today": "2026-10-25",
        "book_states": tmp_path / "states",
    }
    out = tmp_path / "out"

    edition, uploads = data_update.update(inputs(tmp_path), out, build=fake_build(), **common)
    assert (edition["n"], edition["sent"]) == (1, False)
    (upload,) = uploads
    assert upload.project == "Bastians_Data"
    toc = data_version()
    assert upload.version == f"{toc}+data.20261025.1"
    assert upload.zip_path.name == f"Bastians_Data-v{toc}+data.20261025.1-forever.zip"
    assert upload.metadata["displayName"] == f"Bastian's Data {toc}+data.20261025.1 (WoW Forever)"
    with zipfile.ZipFile(upload.zip_path) as zf:
        tops = {n.split("/")[0] for n in zf.namelist()}
        names = set(zf.namelist())
    assert "Bastians_Data_Strategies/Generated/Book.lua" in names
    assert "Bastians_Data/Generated/MapTransforms.lua" in names
    assert all(t.startswith("Bastians_Data") for t in tops)  # the apps stay out of the daily file
    # the game shows the edition: every TOC of the file carries it (ADR 0021)
    with zipfile.ZipFile(upload.zip_path) as zf:
        tocs = [zf.read(n).decode() for n in zf.namelist() if n.endswith(".toc")]
    assert tocs and all(f"## Version: {toc}+data.20261025.1" in t for t in tocs)
    assert upload.problems == []  # the projects exist (23.10.2026): ready to send
    assert "Four new farming pages." in upload.metadata["changelog"]

    # the same data again: the same edition, planned again because it was not sent
    again, uploads = data_update.update(
        inputs(tmp_path), out, build=fake_build(), boot=False, **common
    )
    assert again == edition and uploads
    data_update.mark_sent(ledger, edition, 4711)
    same, uploads = data_update.update(
        inputs(tmp_path), out, build=fake_build(), boot=False, **common
    )
    assert uploads is None and same["file_id"] == 4711

    # new prices the same day: edition 2, its changelog has only news the sent one lacked
    prices = fake_build({"Bastians_Data_Market": ["a new scan"]})
    changed, uploads = data_update.update(inputs(tmp_path), out, build=prices, boot=False, **common)
    assert changed["n"] == 2 and uploads[0].version.endswith("+data.20261025.2")
    assert "up to date" in uploads[0].metadata["changelog"]
    # and a changed book after that: edition 3
    book = fake_build({"Bastians_Data_Market": ["a new scan"], "Bastians_Data_Strategies": ["x"]})
    third, _ = data_update.update(inputs(tmp_path), out, build=book, boot=False, **common)
    assert third["n"] == 3
    assert len(data_update.read_ledger(ledger)["editions"]) == 3


def data_version() -> str:
    import release

    return release.addon_version(ROOT / "addons" / "Bastians_Data")


def test_a_build_without_its_forever_sources_is_refused(tmp_path: Path):
    # the build skips a missing source silently: the edition must not ship hollow packs
    with pytest.raises(data_update.DataUpdateError, match="EverythingQuests, ForeverDB/Data"):
        data_update.update(inputs(tmp_path), tmp_path / "out", ledger_path=tmp_path / "e.json")
    for path in data_update.SOURCES:
        target = tmp_path / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.mkdir() if "." not in target.name else target.write_text("", encoding="utf-8")
    assert data_update.missing_sources(tmp_path) == []


def test_the_hash_follows_packs_and_code_but_not_the_version_line(tmp_path: Path):
    packs = tmp_path / "packs"
    fake_build()(inputs(tmp_path), packs)
    addons = tmp_path / "addons"
    loader = addons / "Bastians_Data"
    loader.mkdir(parents=True)
    toc = loader / "Bastians_Data.toc"
    toc.write_text("## Interface: 16001\n## Version: 1.0.0-beta.9\nData.lua\n", encoding="utf-8")
    (loader / "Data.lua").write_text("-- the loader\n", encoding="utf-8")
    folders = ["Bastians_Data", "Bastians_Data_World"]
    first = data_update.data_hash(packs, folders, addons)
    toc.write_text("## Interface: 16001\n## Version: 1.0.0-beta.10\nData.lua\n", encoding="utf-8")
    assert data_update.data_hash(packs, folders, addons) == first  # a version bump alone
    (loader / "Data.lua").write_text("-- the loader, fixed\n", encoding="utf-8")
    assert data_update.data_hash(packs, folders, addons) != first  # a loader fix ships


def state_build(news: list[dict], seen_previous: list):
    """The fixture packs plus a book state the way the pipeline writes it (--book-state); records
    the --book-previous the build was given."""
    base = fake_build()

    def build(inp: build_client.BuildInputs, packs: Path) -> None:
        base(inp, packs)
        extra = inp.extra
        state = Path(extra[extra.index("--book-state") + 1])
        state.write_text(json.dumps({"schema": 1, "pages": {}, "mill": {}, "news": news}))
        seen_previous.append(
            extra[extra.index("--book-previous") + 1] if "--book-previous" in extra else None
        )

    return build


def test_the_book_state_of_the_last_sent_edition_feeds_the_next_build(tmp_path: Path):
    ledger, states = tmp_path / "editions.json", tmp_path / "states"
    book_toml = tmp_path / "book.toml"
    book_toml.write_text(BOOK, encoding="utf-8")
    common = {"ledger_path": ledger, "book_toml": book_toml, "book_states": states, "boot": False}
    generated = [{"date": "2026-10-25", "text": "Farming: 2 new rumours in the mill.", "n": 2}]
    previous: list = []
    out = tmp_path / "out"
    edition, uploads = data_update.update(
        inputs(tmp_path),
        out,
        build=state_build(generated, previous),
        today="2026-10-25",
        commit="abc123",
        notes=lambda since, cfg: [f"notes since {since}"],
        **common,
    )
    assert previous == [None]  # nothing sent yet: nothing to compare with
    assert edition["book_state"] == "2026-10-25.1.json" and (states / "2026-10-25.1.json").is_file()
    assert edition["commit"] == "abc123" and edition["export"] == "20261025T0600Z"
    assert "Farming: 2 new rumours in the mill." in edition["news"]
    log = uploads[0].metadata["changelog"]
    assert "Farming: 2 new rumours in the mill." in log and "Four new farming pages." in log
    assert "notes since None" in log
    data_update.mark_sent(ledger, edition, 1)
    # the next run compares with the sent edition's state and lists the notes since its commit
    more = fake_build({"Bastians_Data_Market": ["new prices"]})

    def build(inp, packs):
        state_build([], previous)(inp, packs)
        more(inp, packs)

    _second, uploads = data_update.update(
        inputs(tmp_path),
        out,
        build=build,
        today="2026-10-26",
        notes=lambda since, cfg: [f"notes since {since}"],
        **common,
    )
    assert previous[-1] == str(states / "2026-10-25.1.json")
    assert "notes since abc123" in uploads[0].metadata["changelog"]
    assert "Farming: 2 new rumours" not in uploads[0].metadata["changelog"]  # already sent


def test_the_edition_boots_with_the_suite_players_have(tmp_path: Path):
    book_toml = tmp_path / "book.toml"
    book_toml.write_text(BOOK, encoding="utf-8")
    common = {"ledger_path": tmp_path / "e.json", "book_toml": book_toml, "today": "2026-10-25"}
    out = tmp_path / "out"
    data_update.update(inputs(tmp_path), out, build=fake_build(), boot=False, **common)
    # the Suite's file as curseforge.py would have sent it, built from this release
    cfg = curseforge.load_config()
    rel = out / "release"
    packages = curseforge.read_manifest(rel, "forever")
    suite = tmp_path / "Bastians_Suite.zip"
    folders = cfg["projects"]["Bastians_Suite"]["folders"]
    assert curseforge.project_zip(rel, packages, folders, suite)
    edition, uploads = data_update.update(
        inputs(tmp_path), out, build=fake_build(), suite_zip=suite, **common
    )
    assert uploads and edition["n"] == 1  # booted clean: the same edition, planned again


def test_send_marks_the_edition_keeps_the_file_and_says_why_curseforge_refused(
    tmp_path: Path, monkeypatch
):
    import io
    import urllib.error

    ledger = tmp_path / "editions.json"
    book_toml = tmp_path / "book.toml"
    book_toml.write_text(BOOK, encoding="utf-8")
    edition, uploads = data_update.update(
        inputs(tmp_path),
        tmp_path / "out",
        build=fake_build(),
        boot=False,
        ledger_path=ledger,
        book_toml=book_toml,
        today="2026-10-25",
    )

    def transport(request):
        if request.full_url.endswith("/api/game/versions"):
            return json.dumps([{"id": 17053, "name": "1.60.1"}]).encode()
        return json.dumps({"id": 9400001}).encode()

    sent = data_update.send(edition, uploads, transport, ledger, token="t")
    assert sent == [("Bastians_Data", 9400001)]
    (e,) = data_update.read_ledger(ledger)["editions"]
    assert e["sent"] and e["file_id"] == 9400001 and e["sent_at"].endswith("Z")
    assert curseforge.kept("Bastians_Data", "forever") is not None

    def refuse(request):
        if request.full_url.endswith("/api/game/versions"):
            return json.dumps([{"id": 17053, "name": "1.60.1"}]).encode()
        raise urllib.error.HTTPError(
            request.full_url, 400, "Bad", {}, io.BytesIO(b'{"errorMessage": "nope"}')
        )

    with pytest.raises(data_update.DataUpdateError, match=r"HTTP 400.*nope"):
        data_update.send(edition, uploads, refuse, ledger, token="t")
    monkeypatch.setattr(curseforge, "api_token", lambda: None)  # never the owner's real token
    with pytest.raises(data_update.DataUpdateError, match="no upload token"):
        data_update.send(edition, uploads, transport, ledger)


def test_the_pictures_come_from_the_export_else_from_the_approved_local_set(tmp_path: Path):
    export = tmp_path / "export"
    folder = export / "20261025T0600Z"
    (folder / "art").mkdir(parents=True)
    (export / "LATEST").write_text("20261025T0600Z", encoding="utf-8")
    local = tmp_path / "local-art"
    local.mkdir()
    (local / "baeldun-dig.jpg").write_bytes(b"")
    # an export without pictures (AHSync's generator not yet running): the approved local set
    assert data_update.art_folder(export, local) == local
    (folder / "art" / "baeldun-dig.jpg").write_bytes(b"")
    assert data_update.art_folder(export, local) == folder / "art"  # the export wins
    assert data_update.art_folder(None, tmp_path / "none") is None
    assert data_update.art_folder(None) is None  # the tests' .local points at an empty folder


CONFIG = {"projects": {"Bastians_Suite": {"id": 1}, "Bastians_Data": {"id": 2}}}


def test_the_download_counts_ride_along_outside_the_editions_hash(tmp_path: Path):
    def transport(request):
        count = 30 if request.full_url.endswith("/1") else 40
        return json.dumps({"data": {"downloadCount": count}}).encode()

    counts = data_update.downloads(CONFIG, transport, key="k", today="2026-10-29")
    assert counts == {"at": "2026-10-29", "suite": 30, "data": 40}

    def down(request):  # unknown is not zero: no answer, no counts
        raise data_update.urllib.error.URLError("offline")

    assert data_update.downloads(CONFIG, down, key="k") is None
    packs = tmp_path / "packs"
    fake_build()(inputs(tmp_path), packs)
    folders = ["Bastians_Data", "Bastians_Data_World"]
    before = data_update.data_hash(packs, folders, tmp_path / "none")
    path = data_update.write_downloads(packs, counts)
    text = path.read_text(encoding="utf-8")
    assert "for forever" in text  # release.py's client mark
    assert '"Data.RegisterDownloads", { at = "2026-10-29", suite = 30, data = 40 }' in text
    assert data_update.data_hash(packs, folders, tmp_path / "none") == before
    data_update.write_downloads(packs, None)  # no counts: what the build wrote stays
    assert path.read_text(encoding="utf-8") == text


def test_confirm_waits_for_curseforge_and_tells_live_refused_and_pending():
    def answering(*states):
        queue = list(states)

        def transport(request):
            status, available = queue.pop(0) if len(queue) > 1 else queue[0]
            return json.dumps({"data": {"fileStatus": status, "isAvailable": available}}).encode()

        return transport

    slept = []
    kw = {"config": CONFIG, "key": "k", "sleep": slept.append, "wait_s": 90, "step_s": 30}
    state, words = data_update.confirm(9, transport=answering((1, False), (4, True)), **kw)
    assert (state, words) == ("live", "approved and live") and slept == [30]
    state, words = data_update.confirm(9, transport=answering((5, False)), **kw)
    assert state == "refused" and "rejected" in words
    slept.clear()
    state, words = data_update.confirm(9, transport=answering((3, False)), **kw)
    assert state == "pending" and "under review after 2 min" in words and slept == [30, 30, 30]
    assert data_update.confirm(9, config=CONFIG, key="", transport=None)[0] == "unknown"

    # The read API answers 404 until CurseForge approved the file (30.10.2026, the first run of
    # the check): the run keeps asking, then says pending; any other HTTP error is "not checked".
    def not_listed_then(*states):
        """404 on the first call, then `states`; 404 forever without any."""
        live = answering(*states) if states else None
        calls = []

        def transport(request):
            calls.append(request)
            if live is None or len(calls) == 1:
                raise data_update.urllib.error.HTTPError(
                    request.full_url, 404, "Not Found", {}, None
                )
            return live(request)

        return transport

    slept.clear()
    state, words = data_update.confirm(9, transport=not_listed_then((4, True)), **kw)
    assert (state, words) == ("live", "approved and live") and slept == [30]
    slept.clear()
    state, words = data_update.confirm(9, transport=not_listed_then(), **kw)
    assert state == "pending" and "not yet listed" in words and "after 2 min" in words
    assert slept == [30, 30, 30]

    def forbidden(request):
        raise data_update.urllib.error.HTTPError(request.full_url, 403, "Forbidden", {}, None)

    assert data_update.confirm(9, transport=forbidden, **kw) == (
        "unknown",
        "not checked: CurseForge did not answer (HTTP Error 403: Forbidden)",
    )


def test_what_curseforge_said_is_kept_with_the_edition(tmp_path: Path):
    ledger = tmp_path / "editions.json"
    data_update.write_ledger(ledger, {"editions": [{"file_id": 9, "sent": True}, {"file_id": 8}]})
    data_update.mark_status(ledger, 9, "pending")
    assert data_update.read_ledger(ledger)["editions"][0] == {
        "file_id": 9,
        "sent": True,
        "curseforge": "pending",
    }
    data_update.mark_status(ledger, 9, "live")
    assert data_update.read_ledger(ledger)["editions"][0]["live"] is True


REPORT = """# Build report

Client: forever. Build: 70790. Sources: ForeverDB.

## Packs

| Pack | Addon | Size | Budget | Records | Indexes |
|---|---|---|---|---|---|
| world | Bastians_Data_World | 8.3 KB | 12288 KB | %s | area.byZone 1 |
| quests | Bastians_Data_Quests | 4.0 KB | 6144 KB | quest 4851 | quest.byGiver 3 |

## Notes

- market forever/rp/alliance/eu: reads the 0 prices of forever/normal/alliance/eu as 'EU normal'

## Ground truth

| Place | Expected | Found | Off |
|---|---|---|---|
| Stormwind 1 2 3 | a | b | 5 |
"""


def build_with_report(records: str):
    # the report is no pack: the market pack carries the words too, so each run is a new edition
    base = fake_build({"Bastians_Data_Market": [records]})

    def build(inputs: build_client.BuildInputs, packs: Path) -> None:
        base(inputs, packs)
        (packs / "report.md").write_text(REPORT % records, encoding="utf-8", newline="\n")

    return build


def test_an_edition_whose_rows_fell_by_a_tenth_is_held(tmp_path: Path, capsys):
    """Catalog review B2 (07.11.2026): the build report's counts ride with the edition; the next
    edition is held when a pack type's rows fell by more than a tenth since the last sent one,
    unless --allow-drift; a type under fifty rows and a gain are only lines."""
    assert data_update.drift(
        {"world": {"npc": 100, "zone": 10}}, {"world": {"npc": 89, "zone": 2}}
    ) == (
        ["world npc 100 -> 89"],
        ["world npc 100 -> 89", "world zone 10 -> 2"],
    )
    assert data_update.drift({"world": {"npc": 100}}, {}) == (
        ["world npc 100 -> 0"],
        ["world npc 100 -> 0"],
    )
    assert data_update.drift(None, {"world": {"npc": 1}}) == ([], [])
    ledger = tmp_path / "editions.json"
    book_toml = tmp_path / "book.toml"
    book_toml.write_text(BOOK, encoding="utf-8")
    common = {
        "ledger_path": ledger,
        "book_toml": book_toml,
        "today": "2026-11-07",
        "book_states": tmp_path / "states",
        "boot": False,
    }
    out = tmp_path / "out"
    first, _ = data_update.update(
        inputs(tmp_path), out, build=build_with_report("npc 10000, zone 71, area 809"), **common
    )
    assert first["records"] == {
        "world": {"npc": 10000, "zone": 71, "area": 809},
        "quests": {"quest": 4851},
    }  # the ground-truth table is no pack
    data_update.mark_sent(ledger, first, 1)
    # the NPCs fell by a fifth: held, with the line that says so
    with pytest.raises(
        data_update.DataUpdateError,
        match=r"rows fell by more than a tenth.*world npc 10000 -> 8000",
    ):
        data_update.update(
            inputs(tmp_path), out, build=build_with_report("npc 8000, zone 71, area 809"), **common
        )
    # a small fall, a gain and a new type pass, each a line
    capsys.readouterr()
    second, _ = data_update.update(
        inputs(tmp_path),
        out,
        build=build_with_report("npc 9500, zone 71, area 900, node 634"),
        **common,
    )
    lines = [line for line in capsys.readouterr().out.splitlines() if line.startswith("drift:")]
    assert lines == ["drift: world area 809 -> 900", "drift: world npc 10000 -> 9500"]
    assert second["records"]["world"]["node"] == 634
    # the fall that is right ships with --allow-drift
    third, _ = data_update.update(
        inputs(tmp_path),
        out,
        build=build_with_report("npc 8000, zone 71, area 809"),
        allow_drift=True,
        **common,
    )
    assert third["records"]["world"]["npc"] == 8000
    # a build without a report says so and is not checked (the fake build leaves the last
    # report where a real one rewrites it: take it away)
    capsys.readouterr()

    def build_without_report(inputs_, packs: Path) -> None:
        fake_build({"Bastians_Data_Market": ["x"]})(inputs_, packs)
        (packs / "report.md").unlink(missing_ok=True)

    data_update.update(inputs(tmp_path), out, build=build_without_report, **common)
    assert "drift: no build report" in capsys.readouterr().out
