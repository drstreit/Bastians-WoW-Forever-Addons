"""Data's own detail sections (B3.5): vendor, trainer, loot, item sources, reagents, summaries."""

import re

from harness import WowRuntime
from pages import page_rows

CORE, DATA, QUESTS, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Browser",
)


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA, QUESTS, BROWSER)
    wow.run_frames(10)
    return wow


def strip(text: str) -> str:
    return re.sub(r"\|T[^|]*\|t ?", "", text)


def sections(wow: WowRuntime, ref: str) -> dict:
    return {s.id: s for s in wow.eval(f"Bastians:GetDetailSections('{ref}')").values()}


def test_vendor_section_shows_unit_prices_and_stacks(wow: WowRuntime):
    boot(wow)
    corina = sections(wow, "npc:54")
    assert list(corina) == ["data.overview", "data.spawns", "data.vendor", "data.zone"]
    assert corina["data.zone"]["def"].link == "zone"  # the zone link (C2)
    zone = list(corina["data.zone"].rows.values())
    assert (zone[0].ref, strip(zone[0].text)) == ("zone:1429", "Elwynn Forest")
    rows = list(corina["data.vendor"].rows.values())
    assert strip(rows[0].text) == "Linen Cloth x20" and rows[0].ref == "item:2589"
    assert (rows[0].value, rows[0].valueKind, rows[0].note) == (13, "money", None)  # 260 / 20
    assert strip(rows[1].text) == "Blood Saber (limited)" and rows[1].value == 1000
    assert wow.eval("Bastians:Entity('npc:54'):Summary()") == "Level 15, Elwynn Forest"


def test_trainer_section(wow: WowRuntime):
    boot(wow)
    rows = list(sections(wow, "npc:198")["data.trainer"].rows.values())
    assert [strip(r.text) for r in rows] == [
        "Fireball (Rank 2) (level 6)",
        "Frostbolt (Rank 1) (level 4)",
    ]
    assert rows[0].value == 1200 and rows[0].valueKind == "money" and rows[0].note is None
    assert rows[0].ref is None  # no recipe item


def test_loot_and_item_sources_point_at_each_other(wow: WowRuntime):
    boot(wow)
    hogger = sections(wow, "npc:448")
    loot = list(hogger["data.loot"].rows.values())
    # a small table (ADR 0018 D): the chance in the note column, the item's worth as the value
    assert [(strip(r.text), r.ref, r.chance, r.note) for r in loot] == [
        ("Linen Cloth", "item:2589", 45.5, "46 %"),
        ("Blood Saber", "item:1185", 3.2, "3.2 %"),
    ]
    assert all(r.value is None and r.icon is not None for r in loot)
    assert hogger["data.loot"]["def"]["block"]["table"] is True
    linen = sections(wow, "item:2589")
    # "Where to get it" (guide gaps, 23.10.2026): Hogger drops it in Elwynn
    assert list(linen) == ["data.overview", "data.sources", "data.where"]
    rows = list(linen["data.sources"].rows.values())
    assert (strip(rows[0].text), rows[0].ref, rows[0].value) == ("Hogger", "npc:448", 45.5)
    assert (strip(rows[1].text), rows[1].ref) == ("Goldtooth", "npc:327")
    assert (
        rows[-1].text == "Vendor sell price"
        and rows[-1].value == 13
        and rows[-1].valueKind == "money"
    )
    tips = [strip(r.text) for r in wow.eval("Bastians:GetTooltipRows('item:2589')").values()]
    assert tips == ["Hogger", "Goldtooth", "Right click: open in the Browser"]  # capped at 2 + hint
    assert wow.eval("Bastians:Entity('item:2589'):Summary()") == "Item level 5"


def test_recipe_reagents_and_summary(wow: WowRuntime):
    boot(wow)
    assert wow.eval("Bastians:Entity('recipe:2152'):Name()") == "Light Armor Kit"
    assert wow.eval("Bastians:Entity('recipe:2152'):Summary()") == "Leatherworking 1"
    rows = list(sections(wow, "recipe:2152")["data.reagents"].rows.values())
    assert (strip(rows[0].text), rows[0].ref, rows[0].value, rows[0].valueKind) == (
        "Light Leather",
        "item:2318",
        1,
        "number",
    )
    assert strip(rows[1].text).startswith(
        "Makes Item 2304"
    )  # the product is not in the fixture: id shown


def test_sections_are_absent_when_the_record_lacks_the_data(wow: WowRuntime):
    boot(wow)
    goldtooth = sections(wow, "npc:327")
    assert (
        "data.vendor" not in goldtooth
        and "data.trainer" not in goldtooth
        and "data.loot" not in goldtooth
    )
    assert (
        "data.sources" not in sections(wow, "item:1185")
        or [r for r in sections(wow, "item:1185")["data.sources"].rows.values()][-1].text
        == "Vendor sell price"
    )
    assert wow.errors == []


def test_quest_text_pack_loads_on_request(wow: WowRuntime):
    boot(wow)
    assert (
        wow.eval("Bastians:GetService('data'):Get('questText', 176)") is None
    )  # text loads on request
    assert wow.eval("(Bastians:GetService('data'):LoadPack('text'))") == "loaded"
    text = wow.eval("Bastians:GetService('data'):Get('questText', 176)")
    assert text.objectives.startswith("Bring Huge Gnoll Claw") and text.src == "classic"


def test_a_quests_flag_list_becomes_one_overview_line_and_the_page_draws_on(wow: WowRuntime):
    """In game a quest's flags list ({ "repeatable" }) became a table as row text and stopped the
    Browser's tree after Overview ("CLUCK!", 22.10.2026)."""
    boot(wow)
    wow.execute(
        "local q = Bastians:GetService('data'):Get('quest', 176); q.flags = { 'repeatable', 'elite' }"
    )
    overview = [r.text for r in sections(wow, "quest:176")["data.overview"].rows.values()]
    assert overview[-1] == "repeatable, elite"
    wow.execute("Bastians:GetModule('Browser').Browser.Open('quest:176')")
    texts = page_rows(wow, "Bastians:GetModule('Browser').dossier")
    assert "Rewards" in texts  # the page goes on after the Overview
    assert wow.errors == []
