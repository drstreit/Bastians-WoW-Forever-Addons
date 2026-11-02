"""Owner round 5 (retail, 31.10.2026): "the subzones can be reached by clicking a nice small map -
but then the subzone information is quite limited, not even that map is there ... I would expect
the same information as in the main zone". An area's page carries its zone's blocks, narrowed to
what stands in the area, and a cut of the zone's painting around it.

The fixture's Crystal Lake lies at (40, -40) in the mock's Elwynn Forest (400 yards across); the
tests give it a radius of 160 yards, so with the slack it reaches 195 yards: the town's NPCs and
Goldtooth (190 yards) stand in it, Hogger (200 and 226 yards) does not."""

import re

from harness import WowRuntime

CORE, DATA, QUESTS, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Browser",
)


def boot(wow: WowRuntime) -> WowRuntime:
    wow.execute('function GetRealmName() return "Classic Beta PvE" end')
    wow.start(CORE, DATA, QUESTS, BROWSER)
    wow.run_frames(10)
    wow.execute('Bastians:GetService("data"):LoadPack("world")')
    wow.run_frames(5)
    # Data keeps decoded records weakly: hold the area, or a collection brings back the pack's
    wow.execute("AREA = Bastians:GetService('data'):Get('area', 18); AREA.r = 160")
    return wow


def strip(text: str) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def sections(wow: WowRuntime, ref: str) -> dict:
    return {s.id: s for s in wow.eval(f"Bastians:GetDetailSections('{ref}')").values()}


def texts(rows) -> list[str]:
    out = []
    for r in rows:
        out.append(strip(r.text))
        if r.children:
            out.extend(texts(r.children.values()))
    return out


def test_the_area_scope_tests_its_places(wow: WowRuntime):
    boot(wow)
    wow.execute("MAP, IN = Bastians:GetService('data'):AreaScope(18)")
    assert wow.eval("MAP") == 1429
    assert wow.eval("IN(1429, 0.42, 0.65)") is True  # Marshal Dughan
    assert wow.eval("IN(1429, 0.38, 0.82)") is True  # Goldtooth, 190 yards
    assert wow.eval("IN(1429, 0.30, 0.80)") is False  # Hogger's nearer place, 200 yards
    assert wow.eval("IN(1453, 0.5, 0.5)") is False  # another map, far away
    assert wow.eval("Bastians:GetService('data'):AreaScope(99999)") is None
    assert wow.errors == []


def test_an_area_page_has_the_zones_blocks_for_what_stands_in_it(wow: WowRuntime):
    boot(wow)
    area = sections(wow, "area:18")
    zone = sections(wow, "zone:1429")
    monsters = texts(area["data.monsters"].rows.values())
    assert monsters == ["Goldtooth  8"]  # Hogger stands outside the lake
    assert "Hogger  11" in texts(zone["data.monsters"].rows.values())
    places = texts(area["data.places"].rows.values())
    assert any(t.startswith("Innkeeper Farley") for t in places)
    assert "data.areas" not in area  # an area lists no subzones of its own
    quests = [k for k in area if k.startswith("quests.zone.")]
    assert quests, list(area)  # the zone's quest blocks, narrowed
    assert area["data.zone"].rows[1].ref == "zone:1429"  # the way back to the zone
    assert wow.errors == []


def test_the_area_shows_its_cut_of_the_zone(wow: WowRuntime):
    boot(wow)
    wow.execute(
        """local parent = CreateFrame("Frame", nil, UIParent)
        ST = Bastians.UI.Stage(parent)
        W = ST:Show("area:18", 96)"""
    )
    width = wow.eval("W")
    # the mock has map art for Elwynn only when its tiles are set; without art no plate
    has_art = wow.eval("Bastians.Coords.MapArt(1429) ~= nil")
    assert (width == 96) is has_art
    assert wow.errors == []
