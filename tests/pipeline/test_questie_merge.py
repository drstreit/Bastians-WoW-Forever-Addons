"""QuestieDB's store in the world model (sources.md, 06.11.2026): it fills what the other sources
leave open on the zones Forever added and replaces nothing; Classic points stay off those zones."""

from types import SimpleNamespace

from bastians_build import canon
from bastians_build.canon import (
    MAX_CLASSIC_SPAWNS_PER_MAP,
    Sources,
    merge_creatures,
    merge_fdb_quest_facts,
    merge_flightpaths,
    merge_item_spots,
    merge_objective_texts,
    merge_questie_items,
    merge_questie_quests,
    merge_questie_world,
    merge_vendors_and_trainers,
)
from bastians_build.model import World
from bastians_build.sources import foreverdb
from bastians_build.sources.clientdump import TaxiNode
from bastians_build.sources.cmangos import SpawnRow
from bastians_build.sources.probe import Transform
from bastians_build.sources.questiedb_store import (
    Store,
    StoreItem,
    StoreNpc,
    StoreObject,
    StoreQuest,
)

ISLAND = Transform(2521, 2991, 4956.25, 0.0, -3708.333, 4231.25, -5562.5, 0.0, True)


def npc(i: int, places: dict, **kw) -> StoreNpc:
    base = dict(
        name=f"Npc {i}",
        level=None,
        level_max=None,
        rank=0,
        faction_template=None,
        friendly=None,
        subname=None,
        npc_flags=None,
    )
    return StoreNpc(id=i, places=places, **{**base, **kw})


def sources(store: Store, **kw) -> Sources:
    s = Sources(client="forever", questie=store, **kw)
    s.transforms = {2521: ISLAND}
    s.area_to_map = {16593: 2521}
    return s


def world() -> World:
    return World(client="forever", build="test", sources=[])


def test_a_new_npc_comes_with_name_level_services_side_and_places():
    w = world()
    store = Store(
        npcs={
            254089: npc(
                254089,
                {16593: [(43.01, 43.23)]},
                name="Coriella Calmbreeze",
                level=10,
                level_max=10,
                friendly="A",
                subname="Innkeeper",
                npc_flags=128,
            )
        }
    )
    merge_questie_world(w, sources(store))
    rec = w.get("npc", 254089)
    assert rec["name"] == "Coriella Calmbreeze" and rec["subname"] == "Innkeeper"
    assert rec["level"] == 10 and rec.get("levelMax") is None
    assert rec["flags"] == ["innkeeper"] and rec["faction"] == "A"
    assert rec["spawns"] == [[2521, 0.4301, 0.4323, "questie"]]


def test_a_common_mob_is_thinned_and_a_rare_keeps_its_rank():
    points = [(10 + i * 0.5, 20.0) for i in range(60)]
    w = world()
    merge_questie_world(w, sources(Store(npcs={9: npc(9, {16593: points}, rank=4)})))
    rec = w.get("npc", 9)
    assert len(rec["spawns"]) == MAX_CLASSIC_SPAWNS_PER_MAP
    assert rec["flags"] == ["rare"]


def test_a_classic_creature_with_a_place_is_left_alone():
    w = world()
    w.add("npc", 5, {"name": "Classic", "spawns": [[1429, 0.5, 0.5, "classic"]]})
    s = sources(Store(npcs={5: npc(5, {16593: [(1.0, 1.0)]}, name="Other")}))
    s.cm_creatures = [{"Entry": 5}]
    merge_questie_world(w, s)
    assert w.get("npc", 5) == {"name": "Classic", "spawns": [[1429, 0.5, 0.5, "classic"]]}


def test_a_classic_creature_without_a_place_gets_one():
    w = world()
    w.add("npc", 5, {"name": "Stitches"})
    s = sources(Store(npcs={5: npc(5, {16593: [(50.0, 50.0)]})}))
    s.cm_creatures = [{"Entry": 5}]
    merge_questie_world(w, s)
    assert w.get("npc", 5)["spawns"] == [[2521, 0.5, 0.5, "questie"]]


def test_a_place_everything_quests_named_is_not_doubled():
    w = world()
    w.add("npc", 8, {"spawns": [[2521, 0.4300, 0.4320, "eq"]]})
    merge_questie_world(
        w, sources(Store(npcs={8: npc(8, {16593: [(43.01, 43.23), (70.0, 70.0)]})}))
    )
    assert w.get("npc", 8)["spawns"] == [
        [2521, 0.43, 0.432, "eq"],
        [2521, 0.7, 0.7, "questie"],
    ]


def test_an_unplaced_entity_of_no_use_makes_no_record_and_a_zone_without_a_map_no_place():
    w = world()
    store = Store(
        npcs={1: npc(1, {}), 2: npc(2, {99999: [(1.0, 1.0)]})},
        objects={3: StoreObject(3, "Mailbox", {16593: [(5.0, 5.0)]})},
    )
    merge_questie_world(w, sources(store))
    assert w.get("npc", 1) is None and w.get("npc", 2) is None
    assert w.get("object", 3)["kind"] == "mailbox"


def quest(i: int, **kw) -> StoreQuest:
    base = dict(name=f"Quest {i}", level=3, min_level=2, races=None, classes=None, zone=16593)
    return StoreQuest(id=i, **{**base, **kw})


def test_a_quest_gets_what_is_open_and_keeps_what_it_has():
    w = world()
    w.add("npc", 10, {"spawns": [[2521, 0.1, 0.2, "questie"]]})
    w.add("npc", 11, {"spawns": [[2521, 0.3, 0.4, "questie"], [2521, 0.5, 0.6, "questie"]]})
    w.add("quest", 1, {"name": "Open", "starts": ["npc:10"]})
    w.add(
        "quest",
        2,
        {"name": "Known", "ends": ["npc:99"], "objectives": [["slay", "npc:98", 0]]},
    )
    store = Store(
        quests={
            1: quest(1, ends_npc=(10,), creatures=(11,), rep=((2778, 50),), objective_text="Slay."),
            2: quest(2, ends_npc=(10,), creatures=(11,)),
        }
    )
    s = sources(store)
    merge_questie_quests(w, s)
    merge_objective_texts(w)
    one = w.get("quest", 1)
    assert one["ends"] == ["npc:10"] and one["endPlaces"] == [[2521, 0.1, 0.2, "questie"]]
    assert one["objectives"] == [["slay", "npc:11"]]
    assert one["spots"] == {2521: [[0.3, 0.4, "slay", 1], [0.5, 0.6, "slay", 1]]}
    assert one["rewards"] == {"rep": [[2778, 50]], "src": "forever"}
    assert w.get("questText", 1) == {"objectives": "Slay.", "src": "forever"}
    two = w.get("quest", 2)
    assert two["ends"] == ["npc:99"] and two["objectives"] == [["slay", "npc:98", 0]]


def test_an_objective_line_does_not_replace_a_classic_text():
    w = world()
    w.add("quest", 1, {"objectiveText": "New line."})
    w.add("questText", 1, {"objectives": "Classic line.", "src": "classic"})
    w.add("quest", 2, {"objectiveText": "Fills the gap."})
    w.add("questText", 2, {"details": "Text.", "src": "classic"})
    merge_objective_texts(w)
    assert w.get("questText", 1)["objectives"] == "Classic line."
    assert w.get("questText", 2)["objectives"] == "Fills the gap."


def test_a_quest_only_questie_has_needs_a_real_title_and_a_placed_starter():
    w = world()
    w.add("npc", 10, {"spawns": [[2521, 0.1, 0.2, "questie"]]})
    store = Store(
        quests={
            1: quest(1, name="Ravaging Ravagers", starts_npc=(10,)),
            2: quest(2, name="<NYI> Old Business", starts_npc=(10,)),
            3: quest(3, name="Nobody Offers This", starts_npc=(77,)),
        }
    )
    s = sources(store)
    merge_questie_quests(w, s)
    rec = w.get("quest", 1)
    assert rec["starts"] == ["npc:10"] and rec["zone"] == 2521 and rec["foreverOnly"] is True
    assert w.get("quest", 2) is None and w.get("quest", 3) is None
    assert {d[1] for d in w.dropped if d[0] == "quest"} == {2, 3}


def test_a_classic_point_stays_off_the_zones_forever_added():
    # Winterspring's rectangle overlaps Mount Hyjal's; Hyjal is the more central one for this point
    winterspring = Transform(1452, 1, 8000.0, 0.0, -4000.0, 2000.0, -6000.0, 0.0, True)
    hyjal = Transform(2482, 1, 6500.0, 0.0, -1000.0, -500.0, -1500.0, 0.0, True)
    s = Sources(client="forever")
    s.transforms = {1452: winterspring, 2482: hyjal}
    s.cm_creatures = [{"Entry": 7, "Name": "Winterfall Runner"}]
    s.cm_spawns = [SpawnRow("creature", 1, 7, 1, 6000.0, -1250.0, 10.0)]
    w = world()
    merge_creatures(w, s)
    assert [row[0] for row in w.get("npc", 7)["spawns"]] == [1452]


def test_measured_xp_wins_over_the_classic_value_and_a_bare_quest_gets_rewards():
    w = world()
    w.add("quest", 1, {"rewards": {"xp": 100, "money": 5, "src": "classic"}})
    w.add("quest", 2, {})
    s = Sources(client="forever")
    s.fdb_xp = {1: 170, 2: 80, 3: 60}  # 3: no such quest
    s.fdb_guide = {2: foreverdb.GuideRewards(2, 15, ((7, 2),), ((8, 1), (9, 1)))}
    merge_fdb_quest_facts(w, s)
    assert w.get("quest", 1)["rewards"] == {"xp": 170, "money": 5, "src": "classic"}
    assert w.get("quest", 2)["rewards"] == {
        "xp": 80,
        "money": 15,
        "items": [[7, 2]],
        "choices": [[8, 1], [9, 1]],
        "src": "forever",
    }


def test_sightings_fill_open_places_and_leave_named_ones():
    point = foreverdb.SeenPoint(2521, 50.0, 25.0)
    seen = foreverdb.QuestSeen(1, (point,), (point,), {2: (point,)})
    w = world()
    w.add("quest", 1, {"endPlaces": [[2521, 0.1, 0.1, "eq"]]})
    s = Sources(client="forever")
    s.fdb_seen = {1: seen}
    merge_fdb_quest_facts(w, s)
    rec = w.get("quest", 1)
    assert rec["startPlaces"] == [[2521, 0.5, 0.25, "fdb"]]
    assert rec["endPlaces"] == [[2521, 0.1, 0.1, "eq"]]
    assert rec["spots"] == {2521: [[0.5, 0.25, "area", 2]]}


def test_forever_stock_fills_an_empty_list_and_an_unknown_price_stays_unknown():
    w = world()
    w.add("npc", 1, {"name": "New seller", "flags": ["vendor"]})
    w.add("npc", 2, {"name": "Classic", "vendor": [[5, 10, None, False, "classic"]]})
    s = Sources(client="forever")
    s.fdb_sold = {
        1: [foreverdb.SoldRow(7, None, 5, True)],
        2: [foreverdb.SoldRow(8, 3, 1, False)],
        3: [foreverdb.SoldRow(9, 1, 1, False)],
    }
    merge_vendors_and_trainers(w, s)
    assert w.get("npc", 1)["vendor"] == [[7, None, 5, True, "fdb"]]
    assert w.get("npc", 2)["vendor"] == [[5, 10, None, False, "classic"]]
    assert w.get("npc", 3) is None


def test_a_trainer_guessed_a_vendor_by_title_is_a_trainer():
    w = world()
    w.add("npc", 1, {"flags": ["vendor"]})  # Nyassa, "Alchemist": the title's guess, sells nothing
    w.add("npc", 2, {"flags": ["vendor"], "vendor": [[5, 1, 1, False, "fdb"]]})
    s = Sources(client="forever")
    s.fdb_trainers = frozenset({1, 2})
    merge_vendors_and_trainers(w, s)
    assert w.get("npc", 1)["flags"] == ["trainer"]
    assert w.get("npc", 2)["flags"] == ["vendor", "trainer"]


def test_a_retired_flight_node_stays_out():
    w = world()
    s = Sources(client="forever")
    s.taxi = [
        TaxiNode(3208, "zzOLDPowderfuse Port, Riverglades", "both", 1, 1.0, 2.0, 3.0),
        TaxiNode(3209, "Powderfuse Port, Riverglades", "both", 0, 1.0, 2.0, 3.0),
    ]
    merge_flightpaths(w, s)
    assert w.get("flightpath", 3208) is None and w.get("flightpath", 3209) is not None


def test_a_spots_bit_counts_within_its_kind_as_everything_quests_do():
    """The addon reads a spot's bit as the n-th objective of that kind (Logic.SpotObjectives)."""

    class Places:
        def get(self, record_type, entity):
            return {"spawns": [[2521, 0.1 * entity, 0.5]]}

    quest = SimpleNamespace(creatures=[1, 2], objects=[3])
    spots = canon._questie_spots(Places(), quest)[2521]
    assert sorted((kind, bit) for _, _, kind, bit in spots) == [
        ("object", 1),
        ("slay", 1),
        ("slay", 2),
    ]


# ---------------------------------------------------------------------------------------------
# QuestieDB's item rows (package QD1, plan-quest-links.md G1 and G2)
# ---------------------------------------------------------------------------------------------

WATERWALL = [[1429, 0.2857, 0.6139, "classic"]]


def lake() -> World:
    """Mirror Lake as the build finds it: the item and the object are there, nothing links them."""
    w = world()
    w.add("item", 7206, {"name": "Mirror Lake Water Sample", "src": "classic"})
    w.add("object", 174794, {"name": "Mirror Lake Waterwall", "spawns": WATERWALL})
    w.add("quest", 1861, {"name": "Mirror Lake", "requiredItems": [[7206, 1]]})
    return w


def test_an_item_no_loot_table_knows_gets_its_droppers_without_a_chance():
    w = lake()
    w.add("item", 50, {"name": "Forever's own"})
    w.add("npc", 5, {"name": "No place"})
    w.add("npc", 6, {"name": "Placed", "spawns": [[1429, 0.5, 0.5, "eq"]]})
    w.add("object", 7, {"name": "Chest", "spawns": [[1429, 0.6, 0.6, "eq"]]})
    store = Store(
        items={
            7206: StoreItem(7206, object_drops=(174794,)),
            50: StoreItem(50, npc_drops=(5, 6, 99), object_drops=(7,), vendors=(8,)),
            51: StoreItem(51, npc_drops=(6,)),  # no record: the store does not make an item
        }
    )
    s = sources(store)
    s.cm_items = [SimpleNamespace(id=7206)]
    assert merge_questie_items(w, s) == 2
    water = w.get("item", 7206)
    assert water["drops"] == [["object:174794"]]  # unknown is not zero: no chance
    assert water["dropsSrc"] == "classic"
    own = w.get("item", 50)
    # those with a place first, creatures before objects; 99 is not in the world
    assert own["drops"] == [["npc:6"], ["object:7"], ["npc:5"]]
    assert own["dropsSrc"] == "questie"
    # the link is stored at both ends (the edge `drops`): the dropper lists the item, no chance
    assert w.get("object", 174794)["loot"] == [[7206]]
    assert w.get("object", 174794)["lootSrc"] == "classic"
    assert w.get("npc", 6)["loot"] == [[50]] and w.get("npc", 6)["lootSrc"] == "questie"
    assert w.get("item", 51) is None
    assert "2 items" in w.notes[-1] and "1 droppers" in w.notes[-1]


def test_an_item_with_drops_or_a_world_drop_keeps_them():
    w = world()
    w.add("npc", 6, {"spawns": [[1429, 0.5, 0.5, "eq"]]})
    w.add("item", 1, {"drops": [["npc:9", 45.5, False]], "dropsSrc": "classic"})
    w.add("item", 2, {"worldDrop": [10, 20, 40]})
    w.add("item", 3, {})
    store = Store(
        items={
            1: StoreItem(1, npc_drops=(6,)),
            2: StoreItem(2, npc_drops=(6,)),
            3: StoreItem(3, npc_drops=(77,), vendors=(6,)),  # nobody the world knows drops it
        }
    )
    assert merge_questie_items(w, sources(store)) == 0
    assert w.get("item", 1)["drops"] == [["npc:9", 45.5, False]]
    assert "drops" not in w.get("item", 2) and "drops" not in w.get("item", 3)
    assert "loot" not in w.get("npc", 6)
    assert w.notes == []


def test_a_droppers_own_loot_stays_and_a_full_list_takes_no_more():
    w = world()
    w.add("npc", 6, {"spawns": [[1429, 0.5, 0.5, "eq"]], "loot": [[9, 80.0]], "lootSrc": "classic"})
    full = [[1000 + i, 1.0] for i in range(canon.MAX_LOOT_PER_NPC)]
    w.add("npc", 7, {"spawns": [[1429, 0.6, 0.6, "eq"]], "loot": list(full)})
    w.add("item", 1, {})
    w.add("item", 9, {})
    store = Store(items={1: StoreItem(1, npc_drops=(6, 7)), 9: StoreItem(9, npc_drops=(6,))})
    assert merge_questie_items(w, sources(store)) == 2
    assert w.get("npc", 6)["loot"] == [[9, 80.0], [1]]  # 9 was there: not twice; 1 goes last
    assert w.get("npc", 6)["lootSrc"] == "classic"
    assert w.get("npc", 7)["loot"] == full


def test_many_droppers_are_cut_and_the_same_store_gives_the_same_rows():
    def build() -> list:
        w = world()
        w.add("item", 1, {})
        for i in range(30):
            w.add("npc", 100 + i, {"spawns": [[1429, 0.5, 0.5, "eq"]]} if i % 2 else {})
        ids = tuple(100 + i for i in reversed(range(30)))
        merge_questie_items(w, sources(Store(items={1: StoreItem(1, npc_drops=ids + ids[:3])})))
        return w.get("item", 1)["drops"]

    rows = build()
    assert len(rows) == canon.MAX_DROPS_PER_ITEM and rows == build()
    assert [r[0] for r in rows[:3]] == ["npc:101", "npc:103", "npc:105"]  # the placed, by id
    assert rows[15] == ["npc:100"]  # then those without a place


def test_mirror_lake_gets_its_place():
    """the quest's item has a dropper now, and the quest
    a spot where it stands, so a suite that reads `spots` alone is sent to the lake too. The
    spot says who stands there."""
    w = lake()
    store = Store(
        items={7206: StoreItem(7206, object_drops=(174794,))},
        quests={1861: quest(1861, items=(7206,))},
    )
    s = sources(store)
    merge_questie_items(w, s)
    merge_questie_quests(w, s)
    rec = w.get("quest", 1861)
    assert rec["objectives"] == [["loot", "item:7206"]] and rec.get("spots") is None
    assert merge_item_spots(w) == 1
    assert rec["spots"] == {1429: [[0.2857, 0.6139, "loot", 1, "object:174794"]]}
    assert merge_item_spots(w) == 0  # it has spots now: running twice changes nothing


def test_an_items_spot_bit_is_its_number_as_the_addon_counts():
    w = world()
    w.add("npc", 1, {"spawns": [[1429, 0.1, 0.1, "eq"]]})
    w.add("npc", 2, {"spawns": [[1429, 0.2, 0.2, "eq"]]})
    w.add("item", 10, {"drops": [["npc:1", 50.0, False]]})
    w.add("item", 11, {"drops": [["npc:2", 50.0, False]]})
    w.add("item", 12, {})  # nobody is known to have it: no spot
    # Everything Quests' numbered rows: the addon takes the n-th required item
    w.add(
        "quest",
        1,
        {"objectives": [["loot", "npc:1", 0]], "requiredItems": [[11, 3], [10, 1]]},
    )
    # rows without a number (QuestieDB's): the item counts among the loot rows
    w.add(
        "quest",
        2,
        {
            "objectives": [["slay", "npc:9"], ["loot", "item:12"], ["loot", "item:10"]],
            "requiredItems": [[10, 1], [12, 1]],
        },
    )
    # an item only the required items name is a step without a number: no spot nobody would read
    w.add("quest", 3, {"requiredItems": [[10, 1]]})
    assert merge_item_spots(w) == 2
    assert w.get("quest", 1)["spots"] == {
        1429: [[0.2, 0.2, "loot", 1, "npc:2"], [0.1, 0.1, "loot", 2, "npc:1"]],
    }
    assert w.get("quest", 2)["spots"] == {1429: [[0.1, 0.1, "loot", 2, "npc:1"]]}
    assert w.get("quest", 3).get("spots") is None
    assert "2 quests" in w.notes[-1]


def test_a_quest_with_spots_of_any_source_keeps_them():
    """The client's own areas and Everything Quests' spots were chosen for the quest; where the
    droppers stand is only where the item may be."""
    w = world()
    w.add("npc", 1, {"spawns": [[1429, 0.1, 0.1, "classic"]]})
    w.add("item", 10, {"drops": [["npc:1"]]})
    area = {1436: [[0.4371, 0.6904, "area", 1]]}
    w.add("quest", 1, {"objectives": [["loot", "item:10"]], "spots": dict(area)})
    assert merge_item_spots(w) == 0
    assert w.get("quest", 1)["spots"] == area and w.notes == []


def test_an_items_spots_come_from_its_first_droppers_and_are_spread():
    w = world()
    drops = []
    for i in range(canon.SPOT_DROPPERS + 3):
        w.add("npc", 100 + i, {"spawns": [[1000 + i, 0.5, 0.5, "eq"]]})
        drops.append([f"npc:{100 + i}", 90.0 - i, False])
    crowd = [[1429, round(0.01 * i, 2), 0.5, "eq"] for i in range(40)]
    w.add("npc", 7, {"spawns": crowd})
    w.add("item", 10, {"drops": drops})
    w.add("item", 11, {"drops": [["npc:7"], ["npc:404"], ["node:5"]]})  # 404: not in the world
    w.add("quest", 1, {"objectives": [["loot", "item:10"]]})
    w.add("quest", 2, {"objectives": [["loot", "item:11"]]})
    merge_item_spots(w)
    assert sorted(w.get("quest", 1)["spots"]) == [1000 + i for i in range(canon.SPOT_DROPPERS)]
    spread = w.get("quest", 2)["spots"][1429]
    assert len(spread) == canon.MAX_SPOTS_PER_MAP
    assert spread[0] == [0.0, 0.5, "loot", 1, "npc:7"] and spread[1][0] == 0.39


def test_only_a_forever_build_makes_item_spots(monkeypatch):
    """Retail's pack has no objective spots by design: a running quest's place there is the
    client's (data.md "Retail data")."""
    ran = []
    monkeypatch.setattr(canon, "merge_item_spots", lambda w: ran.append(w.client))
    canon.build_world(Sources(client="retail"))
    canon.build_world(Sources(client="forever"))
    assert ran == ["forever"]
