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
        transforms = packs / "Bastians_Data" / "Generated"
        transforms.mkdir(parents=True, exist_ok=True)
        (transforms / "MapTransforms.lua").write_text(
            "-- GENERATED\n-- 2 maps on 1 continent, 2 exact; forever; from the fixture\n",
            encoding="utf-8",
        )

    return build


def inputs(tmp_path: Path) -> build_client.BuildInputs:
    export = tmp_path / "export"
    export.mkdir(exist_ok=True)
    (export / "LATEST").write_text("20261025T0600Z\n", encoding="utf-8")
    return build_client.BuildInputs(client="forever", addons=tmp_path, prefix="beta", export=export)


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
