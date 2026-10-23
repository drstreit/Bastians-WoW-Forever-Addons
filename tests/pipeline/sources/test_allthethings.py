"""AllTheThings reader: the constructor tree on the trimmed real-format fixture, the decoders."""

from pathlib import Path

import pytest

from bastians_build.sources.allthethings import (
    AllTheThingsError,
    Point,
    decode_coords,
    decode_level,
    decode_providers,
    read_allthethings,
)

FIXTURE = Path(__file__).resolve().parents[2] / "fixtures" / "sources" / "allthethings"


@pytest.fixture(scope="module")
def att():
    return read_allthethings(FIXTURE, "Standard")


def test_decode_coords_both_shapes():
    assert decode_coords({37: [[48.1, 42.9], [50, 50]]}) == [
        Point(37, 0.481, 0.429),
        Point(37, 0.5, 0.5),
    ]
    assert decode_coords([[48.1, 42.9, 37]]) == [Point(37, 0.481, 0.429)]
    # { [1] = { {x, y} } } (Durotar is uiMapID 1) reaches Python as a list of point lists
    assert decode_coords([[[43.3, 68.5]], [[10, 20]]]) == [
        Point(1, 0.433, 0.685),
        Point(2, 0.1, 0.2),
    ]
    assert decode_coords(None) == [] and decode_coords({37: "x"}) == []


def test_decode_level_and_providers():
    assert decode_level(5) == (5, None)
    assert decode_level([5, 13]) == (5, 13)
    assert decode_level(None) == (None, None) and decode_level(True) == (None, None)
    assert decode_providers([823, 823], [["o", 2076], ["i", 57247], ["x", 1]]) == [
        "npc:823",
        "object:2076",
        "item:57247",
    ]


def test_reads_version_and_counts(att):
    assert att.flavor == "Standard" and att.version == "5.4.3"
    assert set(att.quests) == {783, 28762, 26389, 5261, 29078, 8254, 4641, 999999}
    assert set(att.npcs) == {54, 197, 999998}  # negative ids are headers, not NPCs
    assert set(att.objects) == {2076}
    assert set(att.flightpaths) == {2}
    assert set(att.maps) == {13, 37, 425, 1}


def test_quest_fields_and_places(att):
    q = att.quests[28762]
    assert q.zone == 425 and q.places == [Point(425, 0.335, 0.531)]
    assert q.givers == ["npc:197"] and q.faction is None
    assert q.races == [1, 32] and q.classes == [2]
    assert q.targets == [49871] and q.rewards == [57255]  # s(sourceID, itemID): the item id
    assert q.added == 40003 and q.unavailable is None
    q = att.quests[26389]
    assert q.pre == [28817, 29083] and q.pre_required == 1 and q.items == [58361]
    assert q.rewards == [57247, 999]  # an inline function returning the item still counts
    q = att.quests[29078]
    assert q.min_level == 3 and q.givers == ["object:2076", "item:57247"]
    assert q.flags == {"daily"} and q.alt == [28762] and q.maps == [37]
    q = att.quests[5261]
    assert q.flags == {"breadcrumb"} and q.next == [33] and q.pre == [783]
    q = att.quests[8254]  # _.ResolveQuestData(...) returns a stub: the entry keeps only its id
    assert q.zone == 425 and q.places == [] and q.min_level is None


def test_same_id_in_several_places_is_merged(att):
    q = att.quests[783]
    assert q.zone == 425  # the first occurrence's map wins
    assert q.places == [Point(37, 0.481, 0.429), Point(1, 0.433, 0.685)]
    assert q.givers == ["npc:823"] and q.faction == "A"
    assert q.unavailable is None  # removed under Northshire (u=2), obtainable under Durotar
    assert q.removed == 40003
    n = att.npcs[197]
    assert n.places == [Point(425, 0.335, 0.531), Point(37, 0.334, 0.547)] and n.zone == 425


def test_unavailable_is_inherited_from_headers(att):
    assert att.quests[999999].unavailable == 1
    assert att.npcs[999998].unavailable == 1
    assert att.quests[4641].unavailable is None  # obtainable under Durotar, NYI copy elsewhere
    assert att.quests[4641].flags == {"worldquest"} and att.quests[4641].faction == "H"


def test_npc_object_flightpath_and_map(att):
    assert att.npcs[54].places == [Point(37, 0.415, 0.659)] and att.npcs[54].faction == "A"
    assert att.objects[2076].places == [Point(37, 0.422, 0.435), Point(37, 0.419, 0.441)]
    fp = att.flightpaths[2]
    assert fp.places == [Point(84, 0.71, 0.725)] and fp.creatures == [352] and fp.faction == "A"
    assert att.maps[37].level_lo == 1 and att.maps[37].level_hi == 10
    assert att.maps[37].maps == [38, 39, 40] and att.maps[13].level_lo is None


def test_object_names_from_the_localization_db(att):
    names = att.object_names
    assert names[2702] == "Stone of Inner Binding" and names[2076] == "Atal'Gral, Zuldazar"
    assert names[2846] == "Tattered Chest"
    # expressions the sandbox cannot resolve are skipped, not invented
    assert 61 not in names and 999001 not in names and 999003 not in names
    assert 999002 not in names  # L.HEADER_NAMES[-5] needs the live addon too
    assert 999004 not in names  # the loops after the table are not run


def test_errors():
    with pytest.raises(AllTheThingsError, match="flavor"):
        read_allthethings(FIXTURE, "Vanilla")
    with pytest.raises(AllTheThingsError, match="no data files"):
        read_allthethings(FIXTURE / "nowhere", "Standard")
