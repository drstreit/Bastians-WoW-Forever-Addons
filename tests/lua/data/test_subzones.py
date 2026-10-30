"""Areas (data.md "Areas: the subzones as places"): the fixture World pack's Crystal Lake is found
by the search provider, its zone's page lists it, and its places give the centre and radius."""

import re

from harness import WowRuntime

CORE, DATA = "Bastians_Core", "Bastians_Data"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA)
    wow.run_frames(10)
    wow.execute('Bastians:GetService("data"):LoadPack("world")')
    return wow


def strip(text: str) -> str:
    return re.sub(r"\|T[^|]*\|t ?", "", text)


def search(wow: WowRuntime, text: str) -> list:
    """As the Map's and the Browser's boxes ask: a type word first or last keeps that type."""
    wow.execute(
        f"_G.got = nil local q, types = Bastians.ParseSearch('{text}') "
        "Bastians:Search(q, { limit = 10, types = types }, function(r, done) "
        "if done then _G.got = r end end)"
    )
    wow.run_frames(10)
    return list(wow.eval("got").values())


def sections(wow: WowRuntime, ref: str) -> dict:
    return {s.id: s for s in wow.eval(f"Bastians:GetDetailSections('{ref}')").values()}


def test_the_search_finds_an_area_by_name(wow: WowRuntime):
    boot(wow)
    hits = [r for r in search(wow, "crystal") if r.ref == "area:18"]
    assert hits and hits[0].label == "Crystal Lake" and hits[0].note == "area"
    # "subzone" in the query keeps the areas only
    assert [r.ref for r in search(wow, "subzone lake")] == ["area:18"]
    assert wow.eval("Bastians:Entity('area:18'):Name()") == "Crystal Lake"
    assert wow.eval("Bastians:Entity('area:18'):Summary()") == "Elwynn Forest"
    assert wow.errors == []


def test_the_zone_page_lists_its_areas_and_the_area_links_its_zone(wow: WowRuntime):
    boot(wow)
    elwynn = sections(wow, "zone:1429")
    rows = list(elwynn["data.areas"].rows.values())
    assert [(r.ref, strip(r.text)) for r in rows] == [("area:18", "Crystal Lake")]
    # its place on the zone's map, so the skin draws it as a cut of the painting (ADR 0034)
    place = rows[0].place
    assert (place.map, place.x, place.y) == (1429, 0.6, 0.4)
    lake = sections(wow, "area:18")
    zone = list(lake["data.zone"].rows.values())
    assert (zone[0].ref, strip(zone[0].text)) == ("zone:1429", "Elwynn Forest")
    # a zone without areas has no such section
    assert "data.areas" not in sections(wow, "zone:1415")


def test_an_areas_places_give_its_centre_and_radius(wow: WowRuntime):
    boot(wow)
    (place,) = wow.eval("Bastians:Entity('area:18'):Places()").values()
    assert (place.map, place.ui, place.src) == (0, 1429, "client")
    assert abs(place.wx - 40) < 0.01 and abs(place.wy + 40) < 0.01
    assert place.r == 221.7 and place.wz is None  # no height: unknown, not zero
    (loc,) = wow.eval("Bastians:Entity('area:18'):Locations()").values()
    assert (loc.map, loc.x, loc.y) == (1429, 0.6, 0.4)
