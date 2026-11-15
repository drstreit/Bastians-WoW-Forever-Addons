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
    # a build without a report is refused once a sent edition carried counts: the check must
    # not fall silent (10.11.2026: it had never run, the report lay in another folder)
    capsys.readouterr()

    def build_without_report(inputs_, packs: Path) -> None:
        fake_build({"Bastians_Data_Market": ["x"]})(inputs_, packs)
        (packs / "report.md").unlink(missing_ok=True)

    with pytest.raises(data_update.DataUpdateError, match="no build report"):
        data_update.update(inputs(tmp_path), out, build=build_without_report, **common)
    data_update.update(
        inputs(tmp_path), out, build=build_without_report, allow_drift=True, **common
    )
    assert "drift: no build report" in capsys.readouterr().out


def test_the_builds_report_is_put_beside_the_packs(tmp_path: Path):
    """The build writes build/report.md; the drift check reads the packs folder. A report older
    than the build belongs to another build and stays out."""
    report = tmp_path / "build" / "report.md"
    report.parent.mkdir()
    report.write_text("## Packs\n", encoding="utf-8")
    packs = tmp_path / "packs"
    packs.mkdir()
    data_update.place_report(report, packs, report.stat().st_mtime + 60)
    assert not (packs / "report.md").exists()
    data_update.place_report(report, packs, report.stat().st_mtime - 5)
    assert (packs / "report.md").read_text(encoding="utf-8") == "## Packs\n"
    data_update.place_report(tmp_path / "none.md", packs, 0)  # no report: nothing happens


def test_a_report_equal_to_the_last_builds_is_still_this_builds(tmp_path: Path):
    """The release of 2.2.0 (11.11.2026) built the packs twice within minutes. The second build
    found its report already there with the same content and left the file alone, as the build
    does with every unchanged file; its old time made it "another build's", and the edition
    went out with "the row counts were not checked". The last build's files are removed before
    a build, so what lies there afterwards was written by it."""
    import os
    import time

    from bastians_build.files import write_text

    report = tmp_path / "build" / "report.md"
    links = tmp_path / "build" / "links-forever.json"
    packs = tmp_path / "packs"
    packs.mkdir()
    words, numbers = "## Packs\n", '{"steps": 7, "unplaced": 2, "classic": 3}\n'
    write_text(report, words)
    write_text(links, numbers)
    hour_ago = time.time() - 3600
    for path in (report, links):
        os.utime(path, (hour_ago, hour_ago))  # the build before this one
        (packs / path.name).write_text("stale", encoding="utf-8")
    started = time.time()
    # without the fix: the same content is not written again and keeps its old time
    assert write_text(report, words) is False
    data_update.place_report(report, packs, started)
    assert (packs / "report.md").read_text(encoding="utf-8") == "stale"
    # with it
    data_update.forget_reports(packs, (report, links))
    assert not report.exists() and not (packs / "report.md").exists()
    write_text(report, words)
    write_text(links, numbers)
    data_update.place_report(report, packs, started)
    data_update.place_report(links, packs, started)
    assert (packs / "report.md").read_text(encoding="utf-8") == words
    assert data_update.link_counts(packs) == {"steps": 7, "unplaced": 2, "classic": 3}


def build_with_links(tag: str, links: dict | None):
    """The fixture packs with the build's quest step numbers beside them (None: no file); the
    tag makes each run a new edition."""
    base = fake_build({"Bastians_Data_Market": [tag]})

    def build(inputs: build_client.BuildInputs, packs: Path) -> None:
        base(inputs, packs)
        path = packs / data_update.LINKS.name
        path.unlink(missing_ok=True)
        if links is not None:
            path.write_text(json.dumps(links), encoding="utf-8")

    return build


def test_an_edition_whose_quest_steps_jumped_by_a_tenth_is_held(tmp_path: Path, capsys):
    """data.md "The count and the watch": the build's numbers ride
    with the edition. A rise of the steps without a place or of the Classic debt is the watch's
    alarm and ships; only a jump of more than a tenth (the resolver or a source gone wrong)
    holds the edition, unless --allow-drift."""
    drift = data_update.links_drift
    before = {"steps": 6697, "unplaced": 775, "classic": 512}
    assert drift(before, {"steps": 6700, "unplaced": 780, "classic": 512}) == (
        [],
        ["quest steps 6697 -> 6700", "steps without a place 775 -> 780"],
    )
    assert drift(before, {"steps": 6697, "unplaced": 775, "classic": 564})[0] == [
        "Classic-only steps 512 -> 564"
    ]
    assert drift(before, {"steps": 6000, "unplaced": 775, "classic": 512})[0] == [
        "quest steps 6697 -> 6000"
    ]
    # falling debt and more steps are good news; a small number says nothing; no number before
    assert drift(before, {"steps": 9000, "unplaced": 10, "classic": 0})[0] == []
    assert drift({"classic": 10}, {"classic": 40})[0] == []
    assert drift(None, before) == ([], []) and drift(before, {}) == ([], [])
    ledger = tmp_path / "editions.json"
    book_toml = tmp_path / "book.toml"
    book_toml.write_text(BOOK, encoding="utf-8")
    common = {
        "ledger_path": ledger,
        "book_toml": book_toml,
        "today": "2026-11-11",
        "book_states": tmp_path / "states",
        "boot": False,
    }
    out = tmp_path / "out"
    # the last edition was sent before the build counted its steps: nothing to hold against
    old, _ = data_update.update(inputs(tmp_path), out, build=build_with_links("a", None), **common)
    assert "links" not in old
    data_update.mark_sent(ledger, old, 1)
    first, _ = data_update.update(
        inputs(tmp_path), out, build=build_with_links("b", {**before, "given": 806}), **common
    )
    assert first["links"] == before  # the three numbers, nothing else of the file
    data_update.mark_sent(ledger, first, 2)
    with pytest.raises(
        data_update.DataUpdateError,
        match=r"quest steps jumped by more than a tenth.*steps without a place 775 -> 900",
    ):
        data_update.update(
            inputs(tmp_path),
            out,
            build=build_with_links("c", {**before, "unplaced": 900}),
            **common,
        )
    # a rise below a tenth ships, each change a line: the watch alarms, the edition goes out
    capsys.readouterr()
    risen = {"steps": 6697, "unplaced": 770, "classic": 530}
    second, _ = data_update.update(
        inputs(tmp_path), out, build=build_with_links("d", risen), **common
    )
    lines = [line for line in capsys.readouterr().out.splitlines() if line.startswith("steps:")]
    assert lines == [
        "steps: steps without a place 775 -> 770",
        "steps: Classic-only steps 512 -> 530",
    ]
    assert second["links"] == risen
    # the jump that is right ships with --allow-drift
    third, _ = data_update.update(
        inputs(tmp_path),
        out,
        build=build_with_links("e", {**before, "unplaced": 900}),
        allow_drift=True,
        **common,
    )
    assert third["links"]["unplaced"] == 900
    # a build without the file is refused once a sent edition carried the numbers
    with pytest.raises(data_update.DataUpdateError, match=r"no links-forever\.json"):
        data_update.update(inputs(tmp_path), out, build=build_with_links("f", None), **common)


def test_the_builds_step_numbers_are_put_beside_the_packs(tmp_path: Path):
    links = tmp_path / "build" / "links-forever.json"
    links.parent.mkdir()
    links.write_text('{"steps": 7, "unplaced": 2, "classic": 3, "given": true}', encoding="utf-8")
    packs = tmp_path / "packs"
    packs.mkdir()
    assert data_update.link_counts(packs) == {}
    data_update.place_report(links, packs, links.stat().st_mtime - 5)
    assert data_update.link_counts(packs) == {"steps": 7, "unplaced": 2, "classic": 3}
    (packs / "links-forever.json").write_text("not json", encoding="utf-8")
    assert data_update.link_counts(packs) == {}


def cf_name(version: str, client: str = "WoW Forever") -> str:
    return f"Bastian's Data {version} ({client})"


def test_curseforges_forever_files_are_listed_oldest_first(capsys):
    """CurseForge's file list is the one place both machines' files show up
    (plan-nightly-content.md F2); retail's Data files share the project and are left out."""
    config = {"projects": {"Bastians_Data": {"id": 2}}}
    asked = []

    def transport(request):
        asked.append(request.full_url)
        files = [
            {
                "id": 131,
                "displayName": cf_name("2.1.0+data.20261110.1"),
                "isAvailable": True,
                "downloadUrl": "https://edge.forgecdn.net/files/131/x.zip",
                "fileLength": 7,
                "hashes": [{"value": "md5", "algo": 2}, {"value": "abc", "algo": 1}],
            },
            {"id": 132, "displayName": cf_name("2.1.0", "retail"), "isAvailable": True},
            {"id": 120, "displayName": cf_name("2.0.0+data.20261109.1"), "fileDate": "x"},
        ]
        return json.dumps({"data": files}).encode()

    unknown = {"url": "", "length": 0, "sha1": ""}  # what CurseForge did not say
    assert data_update.listed_files(config, transport, key="k") == [
        {"id": 120, "name": cf_name("2.0.0+data.20261109.1"), "at": "x", "available": False}
        | unknown,
        {
            "id": 131,
            "name": cf_name("2.1.0+data.20261110.1"),
            "at": "",
            "available": True,
            "url": "https://edge.forgecdn.net/files/131/x.zip",
            "length": 7,
            "sha1": "abc",  # algo 1 is SHA-1, the one the boot test's download is checked by
        },
    ]
    assert asked[0].endswith("/v1/mods/2/files?pageSize=20")

    def down(request):
        raise OSError("no route")

    assert data_update.listed_files(config, down, key="k") is None
    assert "file list was not read" in capsys.readouterr().out


def test_a_file_another_machine_sent_is_taken_into_the_ledger():
    """12.11.2026: the desktop's Suite release 2.4.1 sent Data as 2.4.1+data.20261112.1, and the
    notebook's edition that evening went out under the same name, its ledger not knowing the
    first. Both machines take the newer files in; a Suite release's is a line, any other an
    alarm, once."""
    ledger = {
        "editions": [
            {"date": "2026-11-11", "n": 1, "sha256": "a", "sent": True, "file_id": 100},
            {"date": "2026-11-11", "n": 2, "sha256": "b", "sent": False},
        ]
    }
    listed = [
        {"id": 90, "name": cf_name("2.3.0+data.20261110.1"), "at": "", "available": True},
        {"id": 100, "name": cf_name("2.3.0+data.20261111.1"), "at": "", "available": True},
        {
            "id": 110,
            "name": cf_name("2.4.1+data.20261112.1"),
            "at": "2026-11-12T11:20:39.993Z",
            "available": True,
        },
        {"id": 120, "name": cf_name("2.4.1+data.20261112.2"), "at": "", "available": False},
        {"id": 130, "name": "Bastian's Data (WoW Forever)", "at": "2026-11-13T09:00:00Z"},
    ]
    releases = {"2.4.1": "d" * 40, "2.3.0": "c" * 40}
    added, alerts, lines = data_update.adopt(ledger, listed, releases.get)
    assert [e["file_id"] for e in added] == [110, 120, 130]
    assert ledger["editions"][-3:] == added  # after what the ledger had: the order of sending
    release, second, unreadable = added
    assert release == {
        "by": "Suite release 2.4.1",
        "commit": "d" * 40,
        "date": "2026-11-12",
        "file_id": 110,
        "live": True,
        "n": 1,
        "name": cf_name("2.4.1+data.20261112.1"),
        "sent": True,
        "sent_at": "2026-11-12T11:20:39Z",
    }
    assert lines == [
        f"CurseForge has Data file 110 ({cf_name('2.4.1+data.20261112.1')}), sent with the "
        "Suite release 2.4.1 (dddddddd): taken into this machine's ledger"
    ]
    # the second file of a version is no release's: another machine sends editions
    assert second["by"] == "another machine" and "live" not in second
    assert (second["date"], second["n"]) == ("2026-11-12", 2)
    assert (unreadable["date"], unreadable["n"]) == ("2026-11-13", 0)
    assert len(alerts) == 2 and all("no Suite release explains" in a for a in alerts)
    assert "Data file 120" in alerts[0] and "exactly one may hold [edition] send" in alerts[0]
    # this machine's next edition is numbered after them, and nothing is taken twice
    edition, new = data_update.next_edition(ledger, "e", "2026-11-12")
    assert new and edition["n"] == 3
    assert data_update.adopt(ledger, listed, releases.get) == ([], [], [])
    # a ledger that never sent compares with nothing
    assert data_update.adopt({"editions": [{"date": "x"}]}, listed, releases.get) == ([], [], [])
    assert data_update.last_sent(ledger) is unreadable
    assert data_update.last_built(ledger)["file_id"] == 100


def test_adopt_foreign_writes_the_ledger_only_when_it_took_a_file(tmp_path: Path):
    path = tmp_path / "editions.json"
    own = {"date": "2026-11-12", "n": 1, "sha256": "a", "sent": True, "file_id": 100}
    data_update.write_ledger(path, {"editions": [own]})
    config = {"projects": {"Bastians_Data": {"id": 2}}}
    files = [{"id": 101, "name": cf_name("2.4.1+data.20261112.1"), "at": "", "available": True}]
    nothing = {"listed": lambda c: None, "release": lambda v: None}
    assert data_update.adopt_foreign(config, path, **nothing) == ([], [])
    assert len(data_update.read_ledger(path)["editions"]) == 1
    alerts, lines = data_update.adopt_foreign(
        config, path, listed=lambda c: files, release={"2.4.1": "d" * 40}.get
    )
    assert alerts == [] and "sent with the Suite release 2.4.1" in lines[0]
    assert [e["file_id"] for e in data_update.read_ledger(path)["editions"]] == [100, 101]
    before = path.stat().st_mtime_ns
    taken = {"listed": lambda c: files, "release": lambda v: None}
    assert data_update.adopt_foreign(config, path, **taken) == ([], [])
    assert path.stat().st_mtime_ns == before


def test_a_release_commit_is_found_by_its_exact_subject(tmp_path: Path):
    import subprocess

    repo = tmp_path / "r"
    repo.mkdir()

    def git(*args: str) -> str:
        return subprocess.run(
            ["git", "-C", str(repo), *args], capture_output=True, text=True, check=True
        ).stdout

    git("init", "-q", "-b", "main")
    git("config", "user.email", "t@example.org")
    git("config", "user.name", "T")
    git("commit", "-q", "--allow-empty", "-m", "Release: Bastian's Suite 2.4.1\n\nnotes")
    sha = git("rev-parse", "HEAD").strip()
    git("commit", "-q", "--allow-empty", "-m", "Docs: Release: Bastian's Suite 2.4 is planned")
    assert data_update.release_commit("2.4.1", repo) == sha
    assert data_update.release_commit("2.4", repo) is None
    assert data_update.release_commit("2.4.1", tmp_path / "none") is None


def test_the_next_build_is_held_against_this_machines_last_edition(tmp_path: Path):
    """A file another machine sent carries no row counts, book state or news: the build after it
    is checked against the last edition this machine built, and numbered after the other's."""
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
    data_update.mark_sent(ledger, first, 1)
    data = data_update.read_ledger(ledger)
    data["editions"].append(
        {"by": "Suite release 9.9.9", "date": "2026-11-07", "n": 2, "sent": True, "file_id": 2}
    )
    data_update.write_ledger(ledger, data)
    with pytest.raises(data_update.DataUpdateError, match="world npc 10000 -> 8000"):
        data_update.update(
            inputs(tmp_path), out, build=build_with_report("npc 8000, zone 71, area 809"), **common
        )
    third, uploads = data_update.update(
        inputs(tmp_path), out, build=build_with_report("npc 9900, zone 71, area 809"), **common
    )
    assert third["n"] == 3 and uploads[0].version.endswith("+data.20261107.3")
    # the news the own edition carried are not said again
    assert "Four new farming pages." not in uploads[0].metadata["changelog"]


def test_the_boot_tests_suite_is_the_one_players_install_today(tmp_path: Path):
    """R5 (12.11.2026): CurseForge's newest approved Forever Suite file, kept in place of the old
    one after its length and SHA-1 are checked; the kept copy when it is that file already."""
    import hashlib

    folder = tmp_path / "forever"
    folder.mkdir()
    (folder / "Bastians_Suite.zip").write_bytes(b"old")
    meta = {"project": "Bastians_Suite", "version": "2.1.0", "file_id": 9523382}
    (folder / "Bastians_Suite.json").write_text(json.dumps(meta), encoding="utf-8")
    new = b"the suite 2.4.1"

    def files(sha: str = hashlib.sha1(new).hexdigest(), length: int = len(new)):
        return lambda config, project_name: [
            {
                "id": 9523382,
                "name": "Bastian's Suite 2.1.0 (WoW Forever)",
                "available": True,
                "url": "u1",
                "length": 3,
                "sha1": "",
            },
            {
                "id": 9572800,
                "name": "Bastian's Suite 2.4.1 (WoW Forever)",
                "available": True,
                "url": "https://cdn/2.4.1.zip",
                "length": length,
                "sha1": sha,
            },
            {
                "id": 9580000,
                "name": "Bastian's Suite 2.5.0 (WoW Forever)",
                "available": False,
                "url": "u3",
                "length": 1,
                "sha1": "",
            },  # not approved yet: no player has it
        ]

    fetched = []
    fetch = lambda url: fetched.append(url) or new  # noqa: E731
    zip_path, lines, alerts = data_update.current_suite(
        {}, listed=files(), fetch=fetch, root=tmp_path
    )
    assert fetched == ["https://cdn/2.4.1.zip"] and alerts == []
    assert zip_path == folder / "Bastians_Suite.zip" and zip_path.read_bytes() == new
    assert lines == [
        "boot test: Suite 2.4.1 (file 9572800) from CurseForge, was 2.1.0 (file 9523382)"
    ]
    kept = json.loads((folder / "Bastians_Suite.json").read_text(encoding="utf-8"))
    assert kept == {"project": "Bastians_Suite", "version": "2.4.1", "file_id": 9572800}
    # the next night: the kept copy is that file, nothing is fetched
    again = data_update.current_suite({}, listed=files(), fetch=fetch, root=tmp_path)
    assert again[1] == ["boot test: Suite 2.4.1 (file 9572800), as players have it"]
    assert len(fetched) == 1
    # a download that is not CurseForge's file is refused, and the old copy stays
    (folder / "Bastians_Suite.json").write_text(json.dumps(meta), encoding="utf-8")
    (folder / "Bastians_Suite.zip").write_bytes(b"old")
    bad = data_update.current_suite({}, listed=files(sha="0" * 40), fetch=fetch, root=tmp_path)
    assert (
        bad[0].read_bytes() == b"old" and "SHA-1" in bad[2][0] and "players have 2.4.1" in bad[2][0]
    )
    # CurseForge does not answer: the kept copy, said so, no alarm
    quiet = data_update.current_suite({}, listed=lambda config, project_name: None, root=tmp_path)
    assert quiet[0] == folder / "Bastians_Suite.zip" and quiet[2] == []
    assert "were not read" in quiet[1][0]
