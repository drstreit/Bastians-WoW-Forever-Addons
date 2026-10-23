"""tools/data_update.py (ADR 0019): changed data (the book, the prices) is a new edition of the Data
project with its own version, an unchanged one that was sent is left alone, the file carries the
loader and every pack, the whole install boots, and the changelog is What's new since the last
sent edition."""

import shutil
import zipfile
from pathlib import Path

import build_client
import curseforge
import data_update

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
    common = {"ledger_path": ledger, "book_toml": book_toml, "today": "2026-10-25"}
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
    assert upload.problems  # no project id yet: nothing can be sent
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
