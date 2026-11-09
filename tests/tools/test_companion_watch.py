"""tools/companion_watch.py: the companion addons of the
clients' AddOns folders become snapshots and reference pages with a dated change log; a required
companion that is missing, too old or of another API version writes an alert; a changed surface of
a bridged addon says which of our files to review; nothing is written outside the given folders."""

import json
from pathlib import Path

import companion_watch as cw

CONFIG = """
[[companion]]
folder = "Spoken"
required = true
min = "3.7.0"
api = { file = "API.lua", var = "Spoken.API_VERSION", value = 1 }
bridge = ["addons/Bastians_Voice/Bridge.lua"]
about = "The player."

[[companion]]
folder = "TomTom"
about = "Waypoints."
"""


def addon(addons: Path, folder: str, version: str, functions: list[str], api: int = 1) -> Path:
    root = addons / folder
    root.mkdir(parents=True, exist_ok=True)
    (root / f"{folder}.toc").write_text(
        f"## Interface: 16001\n## Version: {version}\n## Dependencies: Ace3\n"
        f"## SavedVariables: {folder}DB\n{folder}.lua\n",
        encoding="utf-8",
    )
    body = "\n".join(f"function {folder}:{f}()\n  return true\nend" for f in functions)
    (root / f"{folder}.lua").write_text(
        f'{folder} = {{}}\n{body}\nSLASH_{folder.upper()}1 = "/{folder.lower()}"\n'
        f'C_ChatInfo.RegisterAddonMessagePrefix("{folder}")\n',
        encoding="utf-8",
    )
    (root / "Libs").mkdir(exist_ok=True)
    (root / "Libs" / "AceDB.lua").write_text("function AceDB:New()\nend\n", encoding="utf-8")
    (root / "API.lua").write_text(f"{folder}.API_VERSION = {api}\n", encoding="utf-8")
    (root / "README.md").write_text(
        "<!-- generated -->\n# Hello\n\nThe first line.\n", encoding="utf-8"
    )
    return root


def setup(tmp_path: Path):
    config = tmp_path / "companions.toml"
    config.write_text(CONFIG, encoding="utf-8")
    addons = tmp_path / "forever" / "Interface" / "AddOns"
    addon(addons, "Spoken", "3.5.1", ["Play", "Stop", "AddSettingsLink"])
    kw = {
        "snapshots": tmp_path / "snap",
        "pages": tmp_path / "pages",
        "alert": tmp_path / "snap" / "ALERT.md",
    }
    return config, addons, kw


def test_a_snapshot_a_page_and_an_alert_for_a_too_old_required_companion(tmp_path: Path):
    config, addons, kw = setup(tmp_path)
    report = cw.watch({"forever": addons}, cw.load_companions(config), today="2026-11-01", **kw)
    assert report.alerts == ["Spoken 3.5.1 on forever is older than 3.7.0"]
    assert report.lines[0] == "! ALERT: Spoken 3.5.1 on forever is older than 3.7.0"
    assert "! Spoken (forever): new: 3.5.1" in report.lines
    assert not any(
        "review" in line for line in report.lines
    )  # a first snapshot: nothing to compare
    snap = json.loads((tmp_path / "snap" / "forever" / "Spoken" / "2026-11-01.json").read_text())
    assert snap["version"] == "3.5.1" and snap["api_value"] == 1
    assert snap["surface"]["functions"] == [
        "Spoken",
        "Spoken:AddSettingsLink",
        "Spoken:Play",
        "Spoken:Stop",
    ]
    assert "AceDB:New" not in snap["surface"]["functions"]  # Libs are not the surface
    assert snap["surface"]["commands"] == ["/spoken"] and snap["surface"]["prefixes"] == ["Spoken"]
    assert "Libs/AceDB.lua" in snap["files"] and snap["deps"] == ["Ace3"]
    assert snap["readme"] == ["# Hello", "The first line."]
    page = (tmp_path / "pages" / "Spoken.md").read_text(encoding="utf-8")
    assert "**Required** by the suite: at least 3.7.0, API 1." in page
    assert "| forever | 3.5.1 | 16001 | 1 | 5 | 0 | /spoken | Spoken |" in page
    assert "- 2026-11-01, forever: new: 3.5.1" in page
    alert = (tmp_path / "snap" / "ALERT.md").read_text(encoding="utf-8")
    assert "older than 3.7.0" in alert
    assert not (tmp_path / "pages" / "TomTom.md").exists()  # never there: nothing to say


def test_an_update_is_a_dated_change_and_a_review_line_and_clears_the_alert(tmp_path: Path):
    config, addons, kw = setup(tmp_path)
    companions = cw.load_companions(config)
    cw.watch({"forever": addons}, companions, today="2026-11-01", **kw)
    addon(addons, "Spoken", "3.7.0", ["Play", "Stop", "ShowsNarratorFor"])
    report = cw.watch({"forever": addons}, companions, today="2026-11-02", **kw)
    assert report.alerts == [] and not (tmp_path / "snap" / "ALERT.md").exists()
    assert report.lines[0].startswith("! Spoken (forever): version 3.5.1 -> 3.7.0")
    assert "functions: +Spoken:ShowsNarratorFor, -Spoken:AddSettingsLink" in report.lines[0]
    assert report.lines[1] == "  review addons/Bastians_Voice/Bridge.lua: Spoken's surface changed"
    assert sorted(p.name for p in (tmp_path / "snap" / "forever" / "Spoken").glob("*.json")) == [
        "2026-11-01.json",
        "2026-11-02.json",
    ]
    page = (tmp_path / "pages" / "Spoken.md").read_text(encoding="utf-8")
    assert page.index("- 2026-11-02, forever: version 3.5.1 -> 3.7.0") < page.index(
        "- 2026-11-01, forever: new: 3.5.1"
    )
    # a third run with nothing new: no snapshot, no line but "unchanged", the page's log kept
    again = cw.watch({"forever": addons}, companions, today="2026-11-03", **kw)
    assert again.lines == ["companions unchanged"] and again.changed == []
    assert len(list((tmp_path / "snap" / "forever" / "Spoken").glob("*.json"))) == 2
    assert "- 2026-11-01, forever: new: 3.5.1" in (tmp_path / "pages" / "Spoken.md").read_text()


def test_a_missing_required_companion_and_another_api_version_alert(tmp_path: Path):
    config, addons, kw = setup(tmp_path)
    companions = cw.load_companions(config)
    addon(addons, "Spoken", "3.7.0", ["Play"], api=2)
    report = cw.watch({"forever": addons}, companions, today="2026-11-01", **kw)
    assert report.alerts == ["Spoken on forever answers API 2, the suite expects 1"]
    retail = tmp_path / "retail" / "Interface" / "AddOns"
    retail.mkdir(parents=True)
    report = cw.watch({"forever": addons, "retail": retail}, companions, today="2026-11-02", **kw)
    assert report.alerts == ["Spoken on forever answers API 2, the suite expects 1"]  # Forever-only
    page = (tmp_path / "pages" / "Spoken.md").read_text(encoding="utf-8")
    assert "| retail | missing |" in page
    import shutil

    shutil.rmtree(addons / "Spoken")
    report = cw.watch({"forever": addons, "retail": retail}, companions, today="2026-11-03", **kw)
    assert report.alerts == ["Spoken is missing on forever"]
    assert "! Spoken (forever): missing: the folder is gone" in report.lines
    assert "  review addons/Bastians_Voice/Bridge.lua: Spoken's surface changed" in report.lines
    # the next run says it once, not again every day (TomTom's page, 04.11.2026); the alert stays
    report = cw.watch({"forever": addons, "retail": retail}, companions, today="2026-11-04", **kw)
    assert report.alerts == ["Spoken is missing on forever"]
    assert not any("folder is gone" in line for line in report.lines)
    page = (tmp_path / "pages" / "Spoken.md").read_text(encoding="utf-8")
    assert page.count("folder is gone") == 1
    # back again: reported as new
    addon(addons, "Spoken", "3.8.0", ["Play"])
    report = cw.watch({"forever": addons, "retail": retail}, companions, today="2026-11-05", **kw)
    assert "! Spoken (forever): new: 3.8.0" in report.lines


def test_daily_lines_never_raise_and_read_the_install_config(tmp_path: Path):
    assert cw.daily_lines(tmp_path, "2026-11-01") == [
        "companions: no client folders in .local/install.toml ([companions] or [clients])"
    ]
    (tmp_path / ".local").mkdir()
    (tmp_path / ".local" / "install.toml").write_text(
        f'[companions]\nforever = "{(tmp_path / "forever").as_posix()}"\n', encoding="utf-8"
    )
    (tmp_path / "tools").mkdir()
    (tmp_path / "tools" / "companions.toml").write_text(CONFIG, encoding="utf-8")
    addon(tmp_path / "forever" / "Interface" / "AddOns", "Spoken", "3.7.0", ["Play"])
    lines = cw.daily_lines(tmp_path, "2026-11-01")
    assert lines == ["companions ! Spoken (forever): new: 3.7.0"]
    assert (tmp_path / "docs" / "reference" / "companions" / "Spoken.md").is_file()
    assert (tmp_path / ".local" / "companions" / "forever" / "Spoken" / "2026-11-01.json").is_file()
    # the notebook's pages land outside the checkout (ops.toml companion_pages)
    addon(tmp_path / "forever" / "Interface" / "AddOns", "Spoken", "3.8.0", ["Play"])
    cw.daily_lines(tmp_path, "2026-11-02", pages=tmp_path / "out-of-repo")
    page = (tmp_path / "out-of-repo" / "Spoken.md").read_text(encoding="utf-8")
    assert "3.8.0" in page
    assert "3.8.0" not in (tmp_path / "docs" / "reference" / "companions" / "Spoken.md").read_text(
        encoding="utf-8"
    )


def test_the_diff_of_two_snapshots_names_what_changed():
    old = {"version": "1", "files": {"a.lua": [1, "x"]}, "surface": {"functions": ["A:B"]}}
    new = {
        "version": "2",
        "files": {"a.lua": [2, "y"], "b.lua": [1, "z"]},
        "surface": {"functions": []},
    }
    assert cw.diff(old, new) == [
        "version 1 -> 2",
        "+1 files: b.lua",
        "1 files changed: a.lua",
        "functions: -A:B",
    ]
    assert cw.diff(None, None) == [] and cw.diff(old, None) == ["missing: the folder is gone"]
    assert cw.version_key("3.10.0") > cw.version_key("3.7.0")


def lib(addons: Path, carrier: str, text: str, name: str = "LibDBIcon-1.0") -> None:
    path = addons / carrier / "Libs" / name / f"{name}.lua"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def test_an_embedded_library_names_the_copy_that_loads_and_its_carriers(tmp_path: Path):
    config, addons, kw = setup(tmp_path)
    config.write_text(CONFIG + '\n[[library]]\nname = "LibDBIcon-1.0"\nabout = "The button."\n')
    lib(
        addons,
        "Spoken",
        'local D = "LibDBIcon-1.0"\nlocal D_MINOR = 52 -- bump\n'
        "local lib = LibStub:NewLibrary(D, D_MINOR)\n",
    )
    lib(
        addons,
        "EverythingQuests",
        'local MAJOR, MINOR = "LibDBIcon-1.0", 55\nlocal lib = LibStub:NewLibrary(MAJOR, MINOR)\n',
    )
    libraries = cw.load_libraries(config)
    report = cw.watch(
        {"forever": addons},
        cw.load_companions(config),
        today="2026-11-04",
        libraries=libraries,
        **kw,
    )
    assert "  LibDBIcon-1.0 (forever): new: minor 55 (2 copies)" in report.lines
    snap = json.loads(
        (tmp_path / "snap" / "forever" / "LibDBIcon-1.0" / "2026-11-04.json").read_text()
    )
    assert snap["copies"] == {"EverythingQuests": 55, "Spoken": 52} and snap["minor"] == 55
    page = (tmp_path / "pages" / "LibDBIcon-1.0.md").read_text()
    assert "| forever | 55 | EverythingQuests (55), Spoken (52) |" in page
    # an update elsewhere: a dated change, the loaded minor moves
    lib(addons, "Spoken", 'local lib = LibStub:NewLibrary("LibDBIcon-1.0", 56)\n')
    report = cw.watch(
        {"forever": addons},
        cw.load_companions(config),
        today="2026-11-05",
        libraries=libraries,
        **kw,
    )
    assert (
        "  LibDBIcon-1.0 (forever): the loaded minor 55 -> 56; copies: Spoken 52 -> 56"
        in report.lines
    )
    page = (tmp_path / "pages" / "LibDBIcon-1.0.md").read_text()
    assert page.index("2026-11-05") < page.index("2026-11-04, forever")
    # unchanged: nothing new
    report = cw.watch(
        {"forever": addons},
        cw.load_companions(config),
        today="2026-11-06",
        libraries=libraries,
        **kw,
    )
    assert not any("LibDBIcon" in line for line in report.lines)


def test_a_computed_minor_is_unknown_not_zero():
    text = 'local lib = LibStub:NewLibrary("X-1.0", tonumber(("$Rev: 30 $"):match("%d+")))\n'
    assert cw.library_minor(text, "X-1.0") is None
    assert cw.library_minor('LibStub:NewLibrary("Y-1.0", 3)', "X-1.0") is None
