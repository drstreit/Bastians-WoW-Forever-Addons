"""Lists near me first (C9, ADR 0014): a type list opens with the player's zone ("Here"), else the
continent, else everything; since ADR 0016 the level is the "Where" pill of the filter bar; a list
without places (items) has no such pill; the Zones list is the zone index with level bands; search
results are rows with the worth and open their page on a click."""

import re

from harness import WowRuntime
from pages import clear, menu, pick, pills

CORE, DATA, QUESTS, GOLD, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Gold",
    "Bastians_Browser",
)
MOD = "Bastians:GetModule('Browser')"
BR = f"{MOD}.Browser"
SIZE = f"{MOD}.tree.scroll:SetSize(440, 400); {MOD}.tree:Refresh()"
TREE = f"{MOD}.tree"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.execute('function GetRealmName() return "Classic Beta PvE" end')
    wow.start(CORE, DATA, QUESTS, GOLD, BROWSER)
    wow.run_frames(10)
    wow.advance(0.3)
    return wow


def strip(text: str | None) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def flat(wow: WowRuntime) -> list[str]:
    return [strip(r.text) for r in wow.eval(f"{MOD}.tree.flat").values()]


def chips(wow: WowRuntime) -> list[str]:
    """The filter bar's pills (ADR 0016)."""
    return pills(wow, TREE)


def open_list(wow: WowRuntime, typ: str) -> None:
    wow.execute(f"{BR}.List('{typ}')")
    wow.run_frames(10)
    wow.execute(SIZE)


def test_the_npc_list_opens_on_the_players_zone_then_widens(wow: WowRuntime):
    boot(wow)
    open_list(wow, "npc")
    current = wow.eval(f"{BR}.Current()")
    assert current.near == "here"
    assert chips(wow)[0] == "Where: Here"
    assert menu(wow, TREE, "where") == ["All  7", "Here  6", "Continent  7"]
    rows = flat(wow)
    assert len(rows) == 6 and not any("Gryan" in r for r in rows)  # Westfall's NPC is not here
    assert "Corina Steele  15" in rows
    # Continent: Westfall's NPC comes in; All: everything (the fixture has one continent)
    pick(wow, TREE, "where", "Continent")
    wow.execute(SIZE)
    assert wow.eval(f"{BR}.Current().near") == "continent"
    assert len(flat(wow)) == 7 and any("Gryan" in r for r in flat(wow))
    clear(wow, TREE, "where")  # the x: All
    assert wow.eval(f"{BR}.Current().near") is None and len(flat(wow)) == 7
    assert chips(wow)[0] == "Where: All"
    # the choice sticks on a re-render
    wow.execute(f"{BR}.Render()")
    assert wow.eval(f"{BR}.Current().near") is None
    assert wow.errors == []


def test_lists_without_places_open_with_everything(wow: WowRuntime):
    boot(wow)
    open_list(wow, "item")
    assert wow.eval(f"{BR}.Current().near") is None
    assert not any(c.startswith("Where") for c in chips(wow))  # no places, no Where pill
    assert len(flat(wow)) > 0 and not flat(wow)[0].startswith("No entries")
    # the zone index (R5): no near chips, the player's continent as the facet, band rows
    open_list(wow, "zone")
    assert wow.eval(f"{BR}.Current().near") is None
    assert wow.eval(f"{BR}.Current().picks.continent") == "Eastern Kingdoms"
    assert flat(wow) == ["Eastern Kingdoms", "Elwynn Forest  7-11", "Westfall  9-10"]
    # the player elsewhere without quest data for the zone: the continent level, never empty
    wow.execute("Mock.playerMap = 1436")
    wow.fire("ZONE_CHANGED_NEW_AREA")
    wow.advance(0.5)
    if wow.made_for(GOLD):  # the spots list is Gold's; no Gold on retail
        open_list(wow, "spot")
        assert wow.eval(f"{BR}.Current().near") in ("here", "continent", None)
        assert not flat(wow)[0].startswith("No entries")
    assert wow.errors == []


def test_search_results_carry_the_worth_and_open_their_page(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{BR}.Home()")
    wow.execute(f"{MOD}.search:SetText('linen')")
    wow.run_frames(20)
    wow.execute(SIZE)
    rows = flat(wow)
    assert any(r.startswith("Linen Cloth") for r in rows)
    pool = [f for f in wow.eval(f"{MOD}.tree.pool").values() if f.IsShown(f)]
    linen = next(f for f in pool if f.row.ref == "item:2589")
    # one line per result: the icon, the name,
    # the type and summary in grey, the worth in the value column (C3)
    assert linen.twoLine is False and "item" in strip(linen.text.GetText(linen.text))
    assert linen.icon.IsShown(linen.icon) is True
    # the worth: Gold's auction price; without Gold Data's vendor price
    worth = "AH " if wow.made_for(GOLD) else "vendor "
    assert strip(linen.value.GetText(linen.value)).startswith(worth)
    linen.Click(linen, "LeftButton")
    assert wow.eval(f"{BR}.Current().ref") == "item:2589"
    assert any(r.startswith("Linen Cloth") for r in flat(wow))  # the results stay beside the page
    assert wow.errors == []


def test_the_zones_list_merges_instances_and_lists_are_cached(wow: WowRuntime):
    """R5: one chip row for zones (the continents, Instances, Other),
    the player's continent first; dungeon floors merge by name; a built list is kept until a
    pack loads or the zone changes."""
    boot(wow)
    open_list(wow, "zone")
    assert chips(wow)[0] == "Continent: Eastern Kingdoms"  # no Where pill on the zone index
    assert menu(wow, TREE, "continent") == ["All  4", "Eastern Kingdoms  3", "Instances  1"]
    pick(wow, TREE, "continent", "Instances")
    wow.run_frames(3)
    assert flat(wow) == ["The Deadmines  2 floors"]
    assert wow.eval(f"{BR}.Current().picks.continent") == "Instances"
    # cached: the second open shows at once, no job; a zone change drops the cache
    assert wow.eval(f"{BR}.listCache.zone ~= nil") is True
    wow.execute(f"{BR}.List('npc')")
    wow.run_frames(10)
    wow.execute(f"{BR}.List('zone')")
    assert wow.eval(f"{MOD}.listJob") is None
    assert flat(wow)[0] != "Building the list ..."
    assert wow.eval(f"{BR}.listCache.zone.map") == 1429
    wow.execute("Mock.playerMap = 1436")
    wow.fire("ZONE_CHANGED_NEW_AREA")
    wow.advance(0.5)
    wow.execute(f"{BR}.List('npc')")
    wow.run_frames(10)
    wow.execute(f"{BR}.List('zone')")  # another zone: the list is rebuilt for it
    wow.run_frames(10)
    assert wow.eval(f"{BR}.listCache.zone.map") == 1436
    assert wow.errors == []


def test_nearest_first_sorts_rows_with_a_place_by_distance(wow: WowRuntime):
    """S2 (22.10.2026, map.md's "Near me" list): lists whose rows have a place offer a sort group
    By name / Nearest first (no All chip); nearest first orders by yards from the player with the
    distance in grey, rows without a place last; an item list offers no such chips."""
    boot(wow)
    open_list(wow, "npc")
    assert menu(wow, TREE, "sort")[:2] == ["Name", "Nearest"]  # a sort has no All
    pick(wow, TREE, "sort", "Nearest")
    wow.run_frames(3)
    rows = flat(wow)
    assert rows[0].startswith("Marshal Dughan") and rows[0].endswith(
        "0 yd"
    )  # where the player stands
    assert all(r.endswith("yd") for r in rows if "Hogger" in r)
    assert wow.eval(f"{BR}.Current().sort") == "near"
    assert chips(wow)[-1] == "Sort: Nearest"
    clear(wow, TREE, "sort")  # the x: back to the name order
    wow.run_frames(3)
    assert wow.eval(f"{BR}.Current().sort") is None and not flat(wow)[0].endswith("yd")
    open_list(wow, "item")
    if wow.made_for(GOLD):
        assert "Nearest" not in menu(wow, TREE, "sort")
    else:  # no Gold on retail: an item list has no sort group at all
        assert not any(c.startswith("Sort") for c in chips(wow))
    assert wow.errors == []


def test_repeated_names_say_where_they_are_and_merge_per_zone(wow: WowRuntime):
    """(G7): "Cathedral Square" 30 times in the Objects list without
    context. A repeated name carries its zone in grey; with mergeSame one name in one zone is one
    row with "N places"; the near and total counts follow (the filter bar counts the rows)."""
    boot(wow)
    wow.execute(
        """
        local recs = {
          [1] = { name = "Cathedral Square", zone = 1453 }, [2] = { name = "Cathedral Square", zone = 1453 },
          [3] = { name = "Cathedral Square", zone = 1453 }, [4] = { name = "Cathedral Square", zone = 1429 },
          [5] = { name = "Anvil", zone = 1429 },
        }
        local zones = { [1453] = { name = "Stormwind City" }, [1429] = { name = "Elwynn Forest" } }
        fakeData = { Get = function(_, typ, id) return typ == "zone" and zones[id] or recs[id] end }
        rowsIn = {
          { 1, "Cathedral Square", "sign", "here" }, { 2, "Cathedral Square", "sign", "here" },
          { 3, "Cathedral Square", "sign", "here" }, { 4, "Cathedral Square", "sign", "continent" },
          { 5, "Anvil", "anvil", "here" },
        }
        nearIn = { here = 4, continent = 5 }
        rowsOut, totalOut = Bastians:GetModule('Browser').Browser.TellApart(
          rowsIn, { mergeSame = true }, fakeData, "object", nearIn, 5)
        """
    )
    out = [(r[1], strip(r[6] or "")) for r in wow.eval("rowsOut").values()]
    assert out == [
        (1, "  Stormwind City, 3 places"),
        (4, "  Elwynn Forest"),
        (5, ""),  # a name of its own needs no place
    ]
    assert wow.eval("totalOut") == 3
    assert (wow.eval("nearIn.here"), wow.eval("nearIn.continent")) == (2, 3)
    assert wow.errors == []
