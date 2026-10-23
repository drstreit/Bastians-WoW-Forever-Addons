"""ItemDB reader: names, core and places on trimmed copies of the real 1.6.0 retail files."""

from pathlib import Path

import pytest

from bastians_build.sources.itemdb import (
    SEP,
    ItemDBError,
    ItemSource,
    PlacePoint,
    decode_core,
    decode_entity,
    decode_item_sources,
    decode_place,
    read_itemdb,
)

FIXTURE = Path(__file__).resolve().parents[2] / "fixtures" / "sources" / "itemdb"


@pytest.fixture(scope="module")
def db():
    return read_itemdb(FIXTURE, "Retail")


def test_decode_core():
    core = decode_core(25, 2, SEP.join(["1", "7", "INVTYPE_WEAPONMAINHAND", "1", ""]))
    assert (core.quality, core.subclass_id, core.equip_loc, core.item_level) == (
        1,
        7,
        "INVTYPE_WEAPONMAINHAND",
        1,
    )
    sparse = decode_core(9, 0, SEP.join(["x", "-1", "", "", ""]))
    assert (sparse.quality, sparse.subclass_id, sparse.equip_loc, sparse.item_level) == (
        None,
        None,
        None,
        None,
    )


def test_decode_place():
    assert decode_place("47:54:17.8,36.0;20.4,46.2") == PlacePoint(
        47, 54, ((0.178, 0.36), (0.204, 0.462))
    )
    assert decode_place("37:1") == PlacePoint(37, 1, ())
    assert decode_place("@Deadmines:3") == ("Deadmines", 3)
    assert decode_place("junk") is None


def test_decode_entity():
    npc = decode_entity("c54", SEP.join(["Corina Steele", "A", "37:1:41.5,65.9"]))
    assert npc.kind == "npc" and npc.id == 54 and npc.side == "A" and npc.profession is None
    assert npc.places == [PlacePoint(37, 1, ((0.415, 0.659),))]
    obj = decode_entity("o252", SEP.join(["I Should not be here B", "Herbalism"]))
    assert obj.kind == "object" and obj.profession == "Herbalism" and obj.places == []
    hostile = decode_entity("c3", SEP.join(["Flesh Eater", "", "47:54:17.8,36.0"]))
    assert hostile.side is None
    assert decode_entity("x1", "Nothing") is None and decode_entity("c2", "") is None


def test_decode_item_sources():
    sources = decode_item_sources("v18672,g2846:100,d61678:-50:A,d1:5:s186,q5489:783,zz1,d2:1:qd")
    assert sources[0] == ItemSource("vendor", "c18672")
    assert sources[1] == ItemSource("object", "o2846", 100.0)
    assert sources[2] == ItemSource("drop", "c61678", 50.0, True, None, "Alliance")
    assert sources[3] == ItemSource("drop", "c1", 5.0, False, None, "skill", 186)
    assert sources[4] == ItemSource("quest", "c5489", None, False, 783)
    assert sources[5] == ItemSource("drop", "c2", 1.0, False, None, "questDone")
    assert len(sources) == 6


def test_reads_the_fixture(db):
    assert db.flavor == "Retail" and db.version == "ItemDB-v1.6.0" and db.build == "120100"
    assert db.names[25] == "Worn Shortsword" and db.names[2589] == "Linen Cloth"
    assert set(db.core) == {25, 35, 38, 117, 118, 282426}  # Effects.lua is not a core file
    assert db.core[25].class_id == 2 and db.core[38].class_id == 4 and db.core[117].class_id == 0
    assert db.core[282426].quality == 4 and db.core[282426].item_level == 197
    assert db.core[282426].equip_loc == "INVTYPE_NECK"
    assert 2589 not in db.core  # a name without a core row stays a name only


def test_places(db):
    entities = db.places.entities
    assert entities["c3"].name == "Flesh Eater" and entities["c3"].side is None
    assert entities["c3"].places[0].ui_map_id == 47 and entities["c3"].places[0].count == 54
    assert entities["c54"].side == "A" and entities["o252"].profession == "Herbalism"
    assert any(e.instances for e in entities.values())  # the "@instance:count" shape is read
    assert db.places.items[38][0] == ItemSource("vendor", "c18672")
    assert db.places.items[38][1] == ItemSource("object", "o2846", 100.0)
    drops = [s for s in db.places.items[2589] if s.kind == "drop"]
    assert drops and drops[0].entity == "c61678" and drops[0].chance == 50.0


def test_errors():
    with pytest.raises(ItemDBError, match="flavor"):
        read_itemdb(FIXTURE, "Vanilla")
    with pytest.raises(ItemDBError, match="no ItemDB core"):
        read_itemdb(FIXTURE / "nowhere", "Retail")
