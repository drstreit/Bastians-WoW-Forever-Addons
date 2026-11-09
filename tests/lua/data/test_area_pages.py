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
    people = texts(area["data.people"].rows.values())
    assert any(t.startswith("Innkeeper Farley") for t in people)
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


def test_a_zones_people_stand_by_what_they_do(wow: WowRuntime):
    """ADR 0054, the sheet's People chapter: everyone in the zone who is not a monster, by what
    they do; the inn as its own row, the groups folded with their count; no monster among them.
    The gathering nodes are a block of the Places chapter (the fixture zone has none)."""
    boot(wow)
    zone = sections(wow, "zone:1429")
    rows = list(zone["data.people"].rows.values())
    heads = [strip(r.text) for r in rows]
    assert heads == [
        "Innkeeper Farley  Innkeeper",
        "Quest givers  1",
        "Vendors  1",
        "Trainers  1",
        "Auction house  1",
    ]
    givers = rows[1]
    assert givers.collapsed is True
    assert [(c.ref, strip(c.text)) for c in givers.children.values()] == [
        ("npc:240", "Marshal Dughan  Marshal")
    ]
    everyone = [c.ref for r in rows for c in (r.children.values() if r.children else [r])]
    assert "npc:448" not in everyone and "npc:295" in everyone  # Hogger is a monster
    assert zone["data.people"]["def"].chapter == "people"
    assert "data.places" not in zone and "data.gathering" not in zone
    assert wow.errors == []


def test_a_person_a_zone_and_a_dungeon_say_a_lead_sentence(wow: WowRuntime):
    """ADR 0054: the sheet's lead from the record alone. A person says what they are, where they
    stand and what they do; a zone its quest levels; a monster and a quest keep their summary."""
    boot(wow)

    def lead(ref: str):
        return wow.eval(f"Bastians:Entity('{ref}'):Lead()")

    assert lead("npc:240") == "Marshal in Elwynn Forest. Starts 2 quests."
    assert lead("npc:295") == "Innkeeper in Elwynn Forest."
    assert (
        lead("zone:1429") == "Quests from level 7 to 11. Eastern Kingdoms. Fishing from skill 25."
    )
    assert lead("npc:448") is None and lead("quest:62") is None and lead("zone:1453") is None
    assert wow.eval("Bastians:Entity('npc:448'):Summary()") == "Level 11, elite, Elwynn Forest"
    # a vendor and a trainer count what they offer, one or many
    wow.execute(
        """
        local d = Bastians:GetService('data')
        KEEP = { d:Get('npc', 54), d:Get('npc', 198) }
        KEEP[1].vendor, KEEP[2].trainer = { { 1 } }, { { 1 }, { 2 }, { 3 } }
        Bastians:InvalidateEntities('npc')
        """
    )
    assert lead("npc:54").endswith("Sells one item.")
    assert lead("npc:198").endswith("Teaches 3 skills.")
    assert wow.errors == []
