"""The vertical slice (B2.7, gate G1): Data pack -> entity -> Quests layer and section -> Browser page
-> tooltip line, on both clients, plus every addon working alone."""

import re

import pytest
from harness import WowRuntime
from pages import band, page_rows

CORE, DATA, QUESTS, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Browser",
)
ELWYNN_VIEW = "{ continent = 0, x1 = -300, y1 = -300, x2 = 300, y2 = 300, level = 3 }"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*addons)
    wow.run_frames(10)  # the pack-loading job runs in frames after login
    return wow


def texts(rows) -> list[str]:
    return [strip_textures(r.text) for r in rows.values()]


def strip_textures(text: str) -> str:
    return re.sub(r"\|T[^|]*\|t ?", "", text)


def log_errors(wow: WowRuntime) -> list[str]:
    """Error lines except the expected one about the empty placeholder pack."""
    return [
        line.text
        for line in wow.eval("Bastians:GetLog()").values()
        if line.level == "error" and "registered no data" not in line.text
    ]


def test_data_loads_the_packs_enabled_modules_declare(wow: WowRuntime):
    boot(wow, CORE, DATA, QUESTS)
    assert "Bastians_Data_World" in wow.loaded
    assert "Bastians_Data_Quests" in wow.loaded  # the fixture quests pack, built by the pipeline
    assert wow.eval("Bastians:GetService('data'):PackLoaded('quests')") is True
    data = "Bastians:GetService('data')"
    assert wow.eval(f"{data}:PackLoaded('world')") is True
    assert wow.eval(f"{data}:Get('npc', 448).name") == "Hogger"
    assert wow.eval(f"{data}:Get('npc', 448).level") == 11
    assert wow.eval(f"{data}:Get('npc', 1)") is None
    spawns = wow.eval(f"{data}:Spawns('npc:448')")
    assert [(s.map, s.src) for s in spawns.values()] == [(1429, "eq"), (1429, "questie")]
    assert list(wow.eval(f"{data}:Index('quest.byGiver', 'npc:240')").values()) == [62, 76]
    assert [
        i
        for i in wow.eval(
            f"(function() local t = {{}} for id in {data}:ByZone('npc', 1429) do t[#t+1] = id end return t end)()"
        ).values()
    ] == [54, 198, 240, 295, 327, 448]
    hits = wow.eval(f"{data}:Find('npc', 'hog', 5)")
    assert [(h.name, h.score) for h in hits.values()] == [("Hogger", 0.9)]
    assert wow.eval(f"{data}:Meta().packs.world.client") == "forever"
    assert wow.errors == [] and log_errors(wow) == []


def test_entities_come_from_data(wow: WowRuntime):
    boot(wow, CORE, DATA, QUESTS)
    assert wow.eval("Bastians:Entity('npc:448'):Name()") == "Hogger"
    assert wow.eval("Bastians:Entity('npc:448'):Summary()") == "Level 11, elite, Elwynn Forest"
    assert wow.eval("Bastians:Entity('zone:1429'):Name()") == "Elwynn Forest"
    assert wow.eval("Bastians:Entity('quest:62'):Name()") == "The Fargodeep Mine"
    assert len(wow.eval("Bastians:Entity('npc:448'):Locations()")) == 2
    assert wow.eval("Bastians:Entity('npc:999'):Name()") is None


def test_without_a_consumer_no_pack_is_loaded(wow: WowRuntime):
    boot(wow, CORE, DATA)
    assert "Bastians_Data_World" not in wow.loaded
    assert wow.eval("Bastians:GetService('data'):Get('npc', 448)") is None
    assert wow.eval("Bastians:Entity('npc:448'):Name()") is None
    assert wow.errors == []


def test_quests_layer_and_sections_use_the_data(wow: WowRuntime):
    boot(wow, CORE, DATA, QUESTS)
    pins = wow.eval(f"Bastians:QueryLayer('quests.turnin', {ELWYNN_VIEW})")
    by_ref = {p.ref: p for p in pins.values()}
    assert sorted(by_ref) == ["npc:240"]  # the taker of the two quests in the log
    assert by_ref["npc:240"].label == "Marshal Dughan"
    sections = wow.eval("Bastians:GetDetailSections('npc:240')")
    assert [s.id for s in sections.values()] == [
        "data.overview",
        "data.spawns",
        "quests.starts",
        "quests.ends",
        "data.zone",
    ]
    starts = sections[3]
    # the quests sit under category rows: 62 is complete in the log, 76 waits for it
    assert texts(starts.rows) == ["Ready to turn in", "Later"]
    quests = [row for cat in starts.rows.values() for row in cat.children.values()]
    names = [strip_textures(r.text).split("  ")[0] for r in quests]
    assert names == ["The Fargodeep Mine", "The Jasperlode Mine"]
    assert quests[0].ref == "quest:62" and quests[0].value == 7
    assert (
        texts(
            wow.eval("Bastians:GetDetailSections('npc:448')").values().__iter__().__next__().rows
        )[0]
        == "Level"
    )
    tips = wow.eval("Bastians:GetTooltipRows('npc:240')")
    assert [t.split("  ")[0] for t in texts(tips)] == ["The Fargodeep Mine", "The Jasperlode Mine"]
    # Hogger gives no quest; the log's quest 176 needs him (guide gaps, 23.10.2026)
    assert texts(wow.eval("Bastians:GetTooltipRows('npc:448')")) == [
        "Target of: The Fargodeep Mine"
    ]


def test_tooltip_line_shows_on_unit_hover(wow: WowRuntime):
    boot(wow, CORE, DATA, QUESTS)
    lines = wow.tooltip("Unit", 240)
    assert [strip_textures(line["left"]).split("  ")[0] for line in lines] == [
        "The Fargodeep Mine",
        "The Jasperlode Mine",
    ]
    assert lines[0]["right"] == "7"  # the level as the value column
    assert wow.tooltip("Unit", 999) == []
    item = wow.tooltip("Item", 2589)
    assert len(item) == 2 and not any("Wanted" in line["left"] for line in item)  # no quest line
    assert wow.errors == []


def test_browser_renders_the_entity_page(wow: WowRuntime):
    boot(wow, CORE, DATA, QUESTS, BROWSER)
    assert wow.eval("Bastians:RunAction('browser.open', 'npc:240', { source = 'test' })") is True
    assert wow.eval("BastiansBrowserFrame:IsShown()") is True
    dossier = "Bastians:GetModule('Browser').dossier"
    flat = page_rows(wow, dossier)
    # the name and the summary are on the band (ADR 0013 B, C2); the blocks are the sections
    assert band(wow, dossier)["name"] == "Marshal Dughan"
    assert band(wow, dossier)["summary"] == "Level 10, Elwynn Forest"
    assert flat[0] == "Overview"
    assert "Overview" in flat and "Starts quests" in flat
    assert any(t.startswith("The Fargodeep Mine") for t in flat)
    assert "Ends quests" in flat and any(t.startswith('Wanted: "Hogger"') for t in flat)
    wow.slash("/bb npc:448")  # the page shows in the detail pane (ADR 0018)
    assert band(wow, dossier)["name"] == "Hogger"
    assert "Locations" in page_rows(wow, dossier)
    wow.slash("/bb")
    assert wow.eval("BastiansBrowserFrame:IsShown()") is False
    wow.execute("Mock.PressEscape()")
    assert wow.errors == []


def test_browser_alone_shows_a_note_instead_of_a_page(wow: WowRuntime):
    boot(wow, CORE, BROWSER)
    wow.slash("/bb npc:240")
    browser = "Bastians:GetModule('Browser')"
    assert wow.eval(f"{browser}.dossier.blockCount") == 0
    # the band says so (ADR 0018: the note sits on the page, not on the list's summary line)
    assert "No data" in wow.eval(f"{browser}.dossier.band.meta:GetText()")
    wow.slash("/bb nonsense")
    assert any("Not an entity reference" in line for line in wow.chat)
    assert wow.errors == []


@pytest.mark.parametrize("addon", [DATA, QUESTS, BROWSER])
def test_every_addon_works_alone_with_core(wow: WowRuntime, addon: str):
    boot(wow, CORE, addon)
    assert wow.errors == []
    assert log_errors(wow) == []
    fresh = wow.reload()
    assert fresh.errors == []
