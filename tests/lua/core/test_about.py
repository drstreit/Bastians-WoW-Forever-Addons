"""The About page of the hub (core.md "About page"): versions, addons, data packs, credits; and the
cross-check that its source list matches docs/data/sources.md and README."""

import re
from pathlib import Path

from harness import WowRuntime

ROOT = Path(__file__).resolve().parents[3]
ABOUT = ROOT / "addons" / "Bastians_Core" / "UI" / "About.lua"
SOURCES = ROOT / "docs" / "data" / "sources.md"
README = ROOT / "README.md"


def lines(wow: WowRuntime) -> list[tuple[str, str]]:
    return [(row.kind, row.text) for row in wow.eval("Bastians.UI.About.Lines()").values()]


def test_about_lines_name_the_versions_client_and_credits(app: WowRuntime):
    rows = lines(app)
    kinds = [k for k, _ in rows]
    assert kinds[0] == "header" and rows[0][1].startswith("Bastian's WoW Forever addons ")
    assert kinds.count("header") == 5
    text = "\n".join(t for _, t in rows)
    assert f"Core API 1. Client: {app.client}," in text
    assert "GPL-3.0" in text and "github.com/" in text
    assert "Everything Quests (MIT)" in text and "CMaNGOS classic-db (GPL-3.0)" in text
    assert "TACTSharp, DBCD, BLPSharp" in text
    # the fixture app and Core are listed with their TOC versions and states
    addon_rows = [t for _, t in rows if " (on)" in t or " (off)" in t]
    assert any(t.startswith("Bastian's Core ") for t in addon_rows)
    assert any("Test App" in t or "Bastians_TestApp" in t for t in addon_rows)
    assert "No data packs are loaded." in text


def test_about_lists_loaded_data_packs_and_flags_foreign_ones(wow: WowRuntime):
    wow.start("Bastians_Core", "Bastians_Data", "Bastians_Data_World")
    wow.run_frames(5)
    text = "\n".join(t for _, t in lines(wow))
    assert "world: build " in text and "No data packs" not in text
    other = "retail" if wow.client == "forever" else "forever"
    wow.execute(
        f'Bastians.Data.RegisterPack("items", {{ client = "{other}", build = "x", schema = {{}}, item = {{}} }})'
    )
    text = "\n".join(t for _, t in lines(wow))
    assert f"items: build x (built for {other}, not this client)" in text
    assert wow.errors == []


def test_hub_shows_about_last_and_the_slash_command_opens_it(app: WowRuntime):
    app.slash("/bastians about")
    assert app.eval("BastiansHubFrame:IsShown()") is True
    assert app.eval("Bastians.UI.Hub.current.about") is True
    labels = [
        b.label.GetText(b.label)
        for b in app.eval("Bastians.UI.Hub.nav:GetChildren()")
        if b.IsShown(b) and b.label is not None
    ]
    assert labels[-1] == "About" and labels[0] == "General"
    widgets = list(app.eval("Bastians.UI.Hub.canvas.widgets").values())
    assert widgets[0].text.startswith("Bastian's WoW Forever addons")
    assert len(widgets) == len(lines(app))
    assert app.eval("Bastians.UI.Hub.canvas.contentHeight") > 200
    # switching to a module page and back re-renders without leftovers
    app.execute("Bastians.UI.Hub.Open('Core')")
    assert app.eval("Bastians.UI.Hub.current.about") is None
    app.execute("Bastians.UI.Hub.Open('about')")
    assert len(list(app.eval("Bastians.UI.Hub.canvas.widgets").values())) == len(lines(app))
    assert app.errors == []


def test_every_credited_source_is_in_sources_md_and_readme():
    """The static lists in About.lua must not drift from the documents (CLAUDE.md §8)."""
    lua = ABOUT.read_text(encoding="utf-8")
    block = lua[lua.index("About.SOURCES = {") : lua.index("About.LIBRARIES = {")]
    names = re.findall(r'^\s*\{ "([^"]+)",', block, flags=re.M)
    names += re.findall(r'^\s*"([^"]+)",\n\s*"[^"]+",\n', block, flags=re.M)
    assert len(names) >= 9, names
    # docs/ is private: the public copy checks the README only
    sources = SOURCES.read_text(encoding="utf-8") if SOURCES.is_file() else None
    readme = README.read_text(encoding="utf-8")
    aliases = {
        "ItemDB / LibItemDB": "ItemDB",
        "Blizzard client files": "client files",
        "CMaNGOS classic-db": "CMaNGOS",
    }
    for name in names:
        key = aliases.get(name, name)
        assert sources is None or key.lower() in sources.lower(), (
            f"{name} is credited in About.lua but not in sources.md"
        )
        assert key.split(" ")[0].lower() in readme.lower(), f"{name} is not credited in README"
