"""Houses on the City & dungeon map (map.md "City plans", ADR 0065): the entity and its page, the way
back from a person, the pin and its filter, the outline on hover, a click on the building."""

import pytest
from harness import WowRuntime

CORE, DATA, BROWSER, MAP = "Bastians_Core", "Bastians_Data", "Bastians_Browser", "Bastians_Map"
MOD = "Bastians:GetModule('Map')"
MAP_ = f"{MOD}.Map"
CITY = "CITY"
HOUSES = "HOUSES"
REF = "house:21138-100"

ART = """
Bastians.Map = Bastians.Map or {}
Bastians.Map.cities = { { ui = 1453, name = "Stormwind City", continent = 0,
  wx = { -9154.17, -7995.83 }, wy = { -14.584, 1722.92 }, w = 4008, h = 2672, rows = 3, cols = 4,
  path = "Interface\\\\AddOns\\\\Bastians_Map_Art\\\\Generated\\\\Cities\\\\1453_" } }
Bastians.Map.houses = { [1453] = {
  { id = "21138-100", name = "Bank", src = "people", district = "Trade District", roles = { "bank", "vendor" },
    continent = 0, wx = -8800, wy = 700, area = 400, people = { 501, 502 }, doors = { { -8810, 700 } },
    outlines = { { -8790, 690, -8790, 710, -8810, 710, -8810, 690 } } },
  { id = "21138-200", name = "Vault", src = "client", roles = { "bank" }, continent = 0,
    wx = -8800, wy = 700, area = 50, people = { 503 }, doors = {},
    outlines = { { -8795, 695, -8795, 705, -8805, 705, -8805, 695 } } },
  { id = "21138-300", name = "Cellar", src = "client", roles = { "vendor" }, continent = 0, under = true,
    wx = -8700, wy = 600, area = 90, people = { 504 }, doors = {}, outlines = {} },
} }
"""


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, BROWSER, MAP)))
    wow.run_frames(10)
    wow.execute(ART)
    wow.slash("/bmap")
    wow.execute(f"CITY = {MOD}.City; HOUSES = {MOD}.Houses")
    return wow


def open_city(wow: WowRuntime) -> None:
    wow.execute(f"{MAP_}.toolbar.city:Click()")
    wow.execute("BastiansCityFrame:SetSize(900, 680)")
    wow.execute(f"{CITY}.clip:SetSize(800, 560); {CITY}.Open()")
    wow.advance(0.3)


def test_a_house_is_an_entity(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f"Bastians:Entity('{REF}'):Name()") == "Bank"
    assert "Trade District" in wow.eval(f"Bastians:Entity('{REF}'):Summary()")
    assert wow.eval(f"{HOUSES}.Get('21138-100').wx") == -8800
    assert wow.eval("Bastians:Entity('house:21138-999'):Name()") is None  # unknown stays unknown
    assert wow.errors == []


def test_without_the_art_a_house_is_nothing(wow: WowRuntime):
    wow.start(CORE, DATA, BROWSER, MAP)
    wow.run_frames(10)
    assert wow.eval(f"Bastians:Entity('{REF}'):Name()") is None
    assert wow.eval(f"{MOD}.Houses.OfNpc(501)") is None
    assert wow.errors == []


def test_the_page_lists_its_people_and_a_person_links_back(wow: WowRuntime):
    boot(wow)
    ids = wow.eval(
        f"(function() local t = {{}}; for _, s in ipairs(Bastians:GetDetailSections('{REF}')) do "
        "t[s.id] = #s.rows end return t end)()"
    )
    assert ids["map.house.people"] == 2
    rows = "Bastians:GetDetailSections('npc:501')"
    link = wow.eval(
        f"(function() for _, s in ipairs({rows}) do if s.id == 'map.house.of' then "
        "return s.rows[1].ref end end end)()"
    )
    assert link == REF
    assert wow.errors == []


@pytest.mark.parametrize(
    ("wx", "wy", "name"),
    [(-8800, 700, "Vault"), (-8792, 700, "Bank"), (-8780, 700, None), (-8700, 600, None)],
)
def test_the_smallest_room_under_a_point_wins(wow: WowRuntime, wx, wy, name):
    boot(wow)
    found = f"{HOUSES}.At(1453, {wx}, {wy})"
    assert wow.eval(f"{found} and {found}.name or nil") == name  # a cellar has no outline to hover


def test_the_filter_takes_the_house_pins_away(wow: WowRuntime):
    boot(wow)
    open_city(wow)
    count = (
        f"(function() local n = 0; for _, p in ipairs({CITY}.Query({CITY}.Current())) do "
        "if p.house then n = n + 1 end end return n end)()"
    )
    assert wow.eval(count) == 3
    wow.execute(f"{MOD}.db.profile.city.layers['city.houses'] = false")
    assert wow.eval(count) == 0
    assert wow.errors == []


def test_hover_lights_the_outline_and_leaving_clears_it(wow: WowRuntime):
    boot(wow)
    open_city(wow)
    wow.execute(f"c = {CITY}.Camera(); c:SetView(800, 560); c.level = 6; c:Center(-8800, 700)")
    wow.execute(f"{CITY}.HoverAt(-8792, 700)")
    assert wow.eval(f"{CITY}.Hovered().name") == "Bank"
    assert wow.eval(f"{CITY}.OutlinePieces()") >= 1
    wow.execute(f"{CITY}.HoverAt(nil)")
    assert wow.eval(f"{CITY}.Hovered()") is None
    assert wow.eval(f"{CITY}.OutlinePieces()") == 0
    wow.execute(f"{MOD}.db.profile.city.layers['city.houses'] = false")
    wow.execute(f"{CITY}.HoverAt(-8792, 700)")  # switched off: nothing to hover
    assert wow.eval(f"{CITY}.Hovered()") is None
    assert wow.errors == []


def test_a_click_on_the_building_focuses_the_house(wow: WowRuntime):
    boot(wow)
    open_city(wow)
    wow.execute(f"{CITY}.HoverAt(-8792, 700)")
    wow.execute(f"{CITY}.clip:GetScript('OnMouseDown')({CITY}.clip, 'LeftButton')")
    wow.execute(f"{CITY}.clip:GetScript('OnMouseUp')({CITY}.clip, 'LeftButton')")
    assert wow.eval("Bastians:Focused()") == REF
    assert wow.errors == []


def test_open_city_map_works_from_a_house(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f"Bastians:GetAction('map.city').when('{REF}')") is True
    wow.execute(f"Bastians:RunAction('map.city', '{REF}', {{ source = 'test' }})")
    assert wow.eval("BastiansCityFrame:IsShown()") is True
    assert wow.eval("Bastians:Focused()") == REF
    assert wow.errors == []
