"""tools/release.py (B11.2, C10): deterministic zips per addon, data packs only with Generated/
files that name the client, the bundle, the manifest, and the boot of the result on the mock."""

import hashlib
import json
import shutil
import zipfile
from pathlib import Path

import pytest
import release

FIXTURE_ADDONS = Path(__file__).resolve().parents[1] / "fixtures" / "addons"
CODE_ADDONS = {
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Gold",
    "Bastians_Browser",
    "Bastians_Map",
    "Bastians_Route",
    "Bastians_Strategies",
}


def make_addons(tmp_path: Path) -> Path:
    addons = tmp_path / "addons"
    per_client = {"Bastians_Data_Quests": "Quests", "Bastians_Map_Art": "Overview"}
    for name in (
        "Bastians_Core",
        "Bastians_Data",
        "Bastians_Data_Quests",
        "Bastians_Probe",
        "Bastians_Map_Art",
    ):
        folder = addons / name
        folder.mkdir(parents=True)
        generated = f"Generated\\{per_client[name]}.lua\n" if name in per_client else ""
        (folder / f"{name}.toc").write_text(
            f"## Interface: 16001, 120105\n## Version: 0.2.0\n\n{name}.lua\n{generated}",
            encoding="utf-8",
        )
        (folder / f"{name}.lua").write_text("-- code\n", encoding="utf-8")
    (addons / "Bastians_Core" / "Libs").mkdir()
    (addons / "Bastians_Core" / "Libs" / "LibStub.lua").write_text("-- lib\n", encoding="utf-8")
    (addons / "Bastians_Core" / "scratch.tmp").write_text("x", encoding="utf-8")
    (addons / "Bastians_Core" / ".luacheckrc").write_text("x", encoding="utf-8")
    (addons / "notes").mkdir()  # no TOC: not an addon
    nav = addons / "Bastians_Data_Nav"  # a TOC that lists no file yet (the nav pack, L+)
    nav.mkdir()
    (nav / "Bastians_Data_Nav.toc").write_text(
        "## Interface: 16001, 120105\n## Version: 0.2.0\n# the file list comes later\n",
        encoding="utf-8",
    )
    return addons


def test_zips_are_deterministic_and_skip_dev_files(tmp_path):
    addons = make_addons(tmp_path)
    out = tmp_path / "out"
    packages, notes = release.release("forever", addons, out)
    names = sorted(p.path.name for p in packages)
    assert names == [
        "Bastians-v0.2.0-forever.zip",
        "Bastians_Core-v0.2.0.zip",
        "Bastians_Data-v0.2.0.zip",
    ]
    assert notes == [
        "Bastians_Data_Nav: skipped, the TOC lists no file",
        f"Bastians_Data_Quests: skipped, no Generated/*.lua in {addons / 'Bastians_Data_Quests'} "
        "(build the forever packs first)",
        f"Bastians_Map_Art: skipped, no Generated/*.lua in {addons / 'Bastians_Map_Art'} "
        "(build the forever packs first)",
    ]
    core = next(p for p in packages if p.addon == "Bastians_Core")
    with zipfile.ZipFile(core.path) as zf:
        entries = zf.namelist()
        assert entries == [
            "Bastians_Core/Bastians_Core.lua",
            "Bastians_Core/Bastians_Core.toc",
            "Bastians_Core/Libs/LibStub.lua",
        ]
        assert all(i.date_time == (1980, 1, 1, 0, 0, 0) for i in zf.infolist())
    first = core.path.read_bytes()
    release.release("forever", addons, out)
    assert core.path.read_bytes() == first  # byte-identical on a second run
    assert not list(out.glob("*.tmp"))
    manifest = json.loads((out / "manifest.json").read_text(encoding="utf-8"))
    assert manifest["client"] == "forever" and manifest["created_at"] == "1980-01-01T00:00:00Z"
    entry = next(e for e in manifest["packages"] if e["addon"] == "Bastians_Core")
    assert entry["sha256"] == hashlib.sha256(first).hexdigest() and entry["files"] == 3
    assert entry["client"] is None
    # the bundle holds every zipped addon folder and is listed apart from the addons
    bundle = packages[-1]
    assert bundle.addon == "Bastians" and bundle.client == "forever" and bundle.files == 5
    with zipfile.ZipFile(bundle.path) as zf:
        assert zf.namelist() == [
            *entries,
            "Bastians_Data/Bastians_Data.lua",
            "Bastians_Data/Bastians_Data.toc",
        ]
    assert manifest["bundle"]["file"] == "Bastians-v0.2.0-forever.zip"
    assert [e["addon"] for e in manifest["packages"]] == ["Bastians_Core", "Bastians_Data"]
    # a subset (--only) gets no bundle
    packages, _ = release.release("forever", addons, out, only={"Bastians_Core"})
    assert [p.addon for p in packages] == ["Bastians_Core"]


def test_an_addon_not_made_for_a_client_is_not_released_for_it(tmp_path):
    addons = make_addons(tmp_path)
    book = addons / "Bastians_Strategies"
    book.mkdir()
    (book / "Bastians_Strategies.toc").write_text(
        "## Interface: 16001\n## Version: 0.2.0\nBastians_Strategies.lua\n", encoding="utf-8"
    )
    (book / "Bastians_Strategies.lua").write_text("-- the book\n", encoding="utf-8")
    forever, _ = release.release("forever", addons, tmp_path / "f")
    retail, notes = release.release("retail", addons, tmp_path / "r")
    assert "Bastians_Strategies" in {p.addon for p in forever}
    assert "Bastians_Strategies" not in {p.addon for p in retail}
    assert "Bastians_Strategies: not for retail (its TOC names interface 16001)" in notes
    with zipfile.ZipFile(retail[-1].path) as zf:  # nor in the bundle
        assert not any(n.startswith("Bastians_Strategies/") for n in zf.namelist())
    # the real TOCs: the book, Gold and the prices they read are Forever's only
    for name in (
        "Bastians_Strategies",
        "Bastians_Data_Strategies",
        "Bastians_Gold",
        "Bastians_Data_Market",
    ):
        assert release.made_for(release.ADDONS_DIR / name, "forever")
        assert not release.made_for(release.ADDONS_DIR / name, "retail")
    for name in ("Bastians_Quests", "Bastians_Map", "Bastians_Browser", "Bastians_Route"):
        assert release.made_for(release.ADDONS_DIR / name, "retail")


def test_data_packs_carry_the_client_and_need_generated_files(tmp_path):
    addons = make_addons(tmp_path)
    generated = addons / "Bastians_Data_Quests" / "Generated"
    generated.mkdir()
    (generated / "Quests.lua").write_text(
        "-- GENERATED\n-- pack quests for retail, build 12.1.5.70448\n", encoding="utf-8"
    )
    (generated / "Quests.lua.tmp").write_text("half", encoding="utf-8")
    packages, notes = release.release(
        "retail", addons, tmp_path / "out", only={"Bastians_Data_Quests"}
    )
    assert notes == [] and [p.path.name for p in packages] == [
        "Bastians_Data_Quests-v0.2.0-retail.zip"
    ]
    with zipfile.ZipFile(packages[0].path) as zf:
        assert "Bastians_Data_Quests/Generated/Quests.lua" in zf.namelist()
        assert not any(n.endswith(".tmp") for n in zf.namelist())
    with pytest.raises(release.ReleaseError, match="built for retail, not forever"):
        release.release("forever", addons, tmp_path / "out", only={"Bastians_Data_Quests"})
    # Map_Art ships its textures per client too, and a file built for the other client is refused
    art = addons / "Bastians_Map_Art" / "Generated"
    (art / "Tiles").mkdir(parents=True)
    (art / "Tiles" / "0_3_6.blp").write_bytes(b"BLP2" + bytes(16))
    (art / "Overview.lua").write_text(
        '-- GENERATED\nBastians.Map.RegisterOverview({\n  client = "retail",\n})\n',
        encoding="utf-8",
    )
    packages, notes = release.release("retail", addons, tmp_path / "out", only={"Bastians_Map_Art"})
    assert [p.path.name for p in packages] == ["Bastians_Map_Art-v0.2.0-retail.zip"]
    with zipfile.ZipFile(packages[0].path) as zf:
        assert "Bastians_Map_Art/Generated/Tiles/0_3_6.blp" in zf.namelist()
    with pytest.raises(release.ReleaseError, match="built for retail, not forever"):
        release.release("forever", addons, tmp_path / "out", only={"Bastians_Map_Art"})
    # a generated file that names no client is refused: the release never guesses
    (generated / "Quests.lua").write_text("-- GENERATED\n", encoding="utf-8")
    assert release.generated_client(generated / "Quests.lua") is None
    with pytest.raises(release.ReleaseError, match="names no client"):
        release.release("retail", addons, tmp_path / "out", only={"Bastians_Data_Quests"})


@pytest.mark.parametrize(
    ("head", "client"),
    [
        ("-- x\n-- pack world for forever, build 70450\n", "forever"),
        ("-- x\n-- pack items for retail, build 12.1.5.70448\n", "retail"),
        ("-- x\n-- pack market: no data in this forever build (optional pack)\n", "forever"),
        ("-- x\n-- minimap tiles for retail (continent 0: 1176 tiles (Azeroth))\n", "retail"),
        ("-- x\n-- overview textures for forever (continent 0: 16 cells)\n", "forever"),
        ("-- x\n-- 55 maps; forever; from client\n", "forever"),
        ("-- x\n-- 375 maps on 39 continents, 375 exact; retail; from client\n", "retail"),
        ('-- x\nlocal t = {\n  client = "retail",\n}\n', "retail"),
        ("-- GENERATED by bastians_build 0.1.0, do not edit\n", None),
    ],
)
def test_generated_client_reads_every_header_the_pipeline_writes(tmp_path, head, client):
    path = tmp_path / "X.lua"
    path.write_text(head, encoding="utf-8")
    assert release.generated_client(path) == client


def test_generated_dir_replaces_the_addons_own_generated_folder(tmp_path):
    addons = make_addons(tmp_path)
    stale = addons / "Bastians_Data_Quests" / "Generated"  # addons/ holds the retail build
    stale.mkdir()
    (stale / "Quests.lua").write_text(
        "-- x\n-- pack quests for retail, build 1\n", encoding="utf-8"
    )
    build = tmp_path / "forever-build"
    fresh = build / "Bastians_Data_Quests" / "Generated"
    fresh.mkdir(parents=True)
    (fresh / "Quests.lua").write_text(
        "-- x\n-- pack quests for forever, build 2\n", encoding="utf-8"
    )
    packages, notes = release.release(
        "forever", addons, tmp_path / "out", only={"Bastians_Data_Quests"}, generated_dir=build
    )
    assert notes == [] and packages[0].path.name == "Bastians_Data_Quests-v0.2.0-forever.zip"
    with zipfile.ZipFile(packages[0].path) as zf:
        assert zf.namelist() == [
            "Bastians_Data_Quests/Bastians_Data_Quests.lua",
            "Bastians_Data_Quests/Bastians_Data_Quests.toc",
            "Bastians_Data_Quests/Generated/Quests.lua",
        ]
        assert b"for forever" in zf.read("Bastians_Data_Quests/Generated/Quests.lua")
    # the other way round the stale retail file is never touched: the build root decides
    _, notes = release.release(
        "forever", addons, tmp_path / "out", only={"Bastians_Map_Art"}, generated_dir=build
    )
    assert notes == [
        f"Bastians_Map_Art: skipped, no Generated/*.lua in {build / 'Bastians_Map_Art'} "
        "(build the forever packs first)"
    ]
    with pytest.raises(release.ReleaseError, match="not a folder"):
        release.release("forever", addons, tmp_path / "out", generated_dir=tmp_path / "nope")


def test_load_order_follows_the_toc_dependencies(tmp_path):
    install = tmp_path / "AddOns"
    for name, deps in (
        (
            "Bastians_Quests",
            "## Dependencies: Bastians_Core\n## OptionalDeps: Bastians_Data, TomTom",
        ),
        ("Bastians_Data_Quests", "## Dependencies: Bastians_Data"),
        # the loader names its packs as OptionalDeps while they require it: the hard edge decides
        ("Bastians_Data", "## RequiredDeps: Bastians_Core\n## OptionalDeps: Bastians_Data_Quests"),
        ("Bastians_Core", ""),
    ):
        (install / name).mkdir(parents=True)
        (install / name / f"{name}.toc").write_text(f"## Version: 1\n{deps}\n", encoding="utf-8")
    assert release.load_order(install) == [
        "Bastians_Core",
        "Bastians_Data",
        "Bastians_Data_Quests",
        "Bastians_Quests",
    ]
    (install / "Bastians_Core" / "Bastians_Core.toc").write_text(
        "## Dependencies: Bastians_Quests\n", encoding="utf-8"
    )
    with pytest.raises(release.ReleaseError, match="cycle"):
        release.load_order(install)


def test_verify_boots_the_zipped_suite_on_the_mock(tmp_path):
    # the real code addons from addons/, the fixture packs as the Forever build root
    build = tmp_path / "forever-build"
    for pack in FIXTURE_ADDONS.glob("Bastians_Data_*"):
        shutil.copytree(pack / "Generated", build / pack.name / "Generated")
    transforms = build / "Bastians_Data" / "Generated"
    transforms.mkdir(parents=True)
    (transforms / "MapTransforms.lua").write_text(
        "-- GENERATED\n-- 2 maps on 1 continent, 2 exact; forever; from the fixture\n",
        encoding="utf-8",
    )
    packs = {p.name for p in FIXTURE_ADDONS.glob("Bastians_Data_*")}
    packages, notes = release.release(
        "forever",
        release.ADDONS_DIR,
        tmp_path / "out",
        only=CODE_ADDONS | packs,
        generated_dir=build,
    )
    assert [n for n in notes if "Bastians_Map:" in n]  # no tile table in the build root: skipped
    assert {p.addon for p in packages} == (CODE_ADDONS - {"Bastians_Map"}) | packs
    assert release.verify(packages, "forever", tmp_path / "work") == []
    # a pack built for the other client is reported, so is a file that fails to load
    (transforms / "MapTransforms.lua").write_text(
        "-- GENERATED\n-- 2 maps; retail; from the fixture\n", encoding="utf-8"
    )
    with pytest.raises(release.ReleaseError, match="built for retail"):
        release.release(
            "forever",
            release.ADDONS_DIR,
            tmp_path / "out",
            only={"Bastians_Data"},
            generated_dir=build,
        )


def test_verify_reports_a_broken_install(tmp_path):
    addons = make_addons(tmp_path)
    (addons / "Bastians_Data" / "Bastians_Data.lua").write_text('error("boom")\n', encoding="utf-8")
    packages, _ = release.release("forever", addons, tmp_path / "out")
    problems = release.verify(packages, "forever", tmp_path / "work")
    assert any("boom" in p for p in problems)
    assert any("Bastians global" in p for p in problems)


def test_cli_and_errors(tmp_path, capsys):
    addons = make_addons(tmp_path)
    out = tmp_path / "out"
    argv = [
        "--client",
        "forever",
        "--addons-dir",
        str(addons),
        "--out",
        str(out),
        "--stamp",
        "2026-11-03T20:00:00Z",
    ]
    assert release.main(argv) == 0
    text = capsys.readouterr().out
    assert "Bastians_Core-v0.2.0.zip" in text and "gh release upload Bastians_Core-v0.2.0" in text
    assert "Bastians-v0.2.0-forever.zip" in text
    with zipfile.ZipFile(out / "Bastians_Core-v0.2.0.zip") as zf:
        assert zf.infolist()[0].date_time == (2026, 11, 3, 20, 0, 0)
    assert release.main([*argv, "--verify"]) == 1  # the stub addons never create Bastians
    assert "verify: Bastians_Core did not create" in capsys.readouterr().err
    assert release.main(["--client", "forever", "--addons-dir", str(tmp_path / "nope")]) == 2
    assert "error:" in capsys.readouterr().err
    (addons / "Bastians_Data" / "Bastians_Data.toc").write_text(
        "## Interface: 16001\nBastians_Data.lua\n", encoding="utf-8"
    )
    with pytest.raises(release.ReleaseError, match="no ## Version"):
        release.release("forever", addons, out)
    with pytest.raises(release.ReleaseError, match="1980"):
        release.parse_stamp("1970-01-01T00:00:00Z")
