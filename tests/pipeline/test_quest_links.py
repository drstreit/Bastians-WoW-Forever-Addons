"""The links the sources have beyond kills, chests and vendors (plan-quest-links.md G3 to G8,
package QD3): what an item is made from, held in, skinned from and fished out of; what a quest
hands over, counts and names as a place; the labels the steps' resolver reads."""

from test_canon import fixture_sources

from bastians_build import canon, steps
from bastians_build.canon import Sources
from bastians_build.model import World
from bastians_build.sources import cmangos, foreverdb
from bastians_build.sources.probe import Transform
from bastians_build.sources.questiedb_store import Store, StoreItem, StoreQuest

ELWYNN = 1429
# world x = 100 - 200 * the map's y, world y = 100 - 200 * the map's x: (0, 0) is the middle
FRAME = {ELWYNN: Transform(ELWYNN, 0, 100.0, 0.0, -200.0, 100.0, -200.0, 0.0, True)}


def links(**parts) -> cmangos.Links:
    empty = {
        name: {}
        for name in (
            "made",
            "uses",
            "spells",
            "focus_objects",
            "held",
            "skinned",
            "picked",
            "fished",
            "points",
            "triggers",
        )
    }
    return cmangos.Links(**(empty | parts))


def world() -> World:
    w = World(client="forever", build="test", sources=[])
    for item in (7206, 7207, 100, 101, 102, 103):
        w.add("item", item, {"name": f"Item {item}"})
    w.add("npc", 113, {"name": "Boar"})
    w.add("npc", 98, {"name": "Taskmaster", "vendor": [[100, 50, 1, False, "classic"]]})
    w.add("npc", 99, {"name": "New in Forever", "spawns": [[ELWYNN, 0.4, 0.4, "fdb"]]})
    w.add("object", 174794, {"name": "Mirror Lake Waterwall", "kind": "fire and forge"})
    w.add("object", 5, {"name": "Anvil", "kind": "fire and forge"})
    w.add("object", 6, {"name": "Cannon", "spawns": [[ELWYNN, 0.7, 0.7, "classic"]]})
    w.add("zone", ELWYNN, {"name": "Elwynn Forest"})
    return w


def test_the_ways_to_an_item_that_are_no_drop():
    flask = cmangos.Made(7207, 8919, 123, ())
    hammer = cmangos.Made(102, 9000, 1, ())  # at any anvil: a kind of place, not a place
    s = Sources(client="forever", area_to_map={12: ELWYNN, 87: ELWYNN, 40: 1436})
    s.cm_links = links(
        made={7206: [flask], 100: [hammer], 999: [flask]},
        focus_objects={123: [102414, 174794], 1: list(range(1, 9))},
        held={100: [(101, 5.0), (102, 95.0)]},
        skinned={100: [(113, 60.0), (4242, 50.0)]},  # creature 4242 is not in the world
        picked={101: [(98, 12.5)]},
        fished={100: [(12, 50.0), (87, 70.0), (40, 20.0)]},  # two areas of one zone; a zone unknown
    )
    s.questie = Store(
        items={
            100: StoreItem(100, item_drops=(103,)),  # CMaNGOS names its containers already
            103: StoreItem(103, item_drops=(101, 4711)),
        }
    )
    w = world()
    canon.merge_item_ways(w, s)
    # at the one object of the focus the world knows; unknown objects are no place
    assert w.get("item", 7206)["ways"] == [["make", "item:7207", None, "object:174794"]]
    assert w.get("item", 100)["ways"] == [
        ["make", "item:102"],  # no `at`: eight anvils are no place of this item
        ["container", "item:101", 5.0],
        ["container", "item:102", 95.0],
        ["skin", "npc:113", 60.0],
        ["fish", f"zone:{ELWYNN}", 70.0],  # the zone once, its best chance
    ]
    assert w.get("item", 101)["ways"] == [["pick", "npc:98", 12.5]]
    assert w.get("item", 103)["ways"] == [["container", "item:101"]]  # no chance: unknown
    # the object a quest's item is used at is a quest place, an anvil stays what it is (G8)
    assert w.get("object", 174794)["kind"] == "quest place"
    assert w.get("object", 5)["kind"] == "fire and forge"
    assert w.notes == [
        "item ways beyond drops (classic): container 3, fish 1, make 2, pick 1, skin 1"
    ]


def quest(entry: int, **columns) -> cmangos.QuestRow:
    return cmangos.quest_rows({"quest_template": [{"entry": entry, **columns}]})[0]


def test_what_a_quest_hands_over_counts_and_names_as_a_place():
    s = Sources(client="forever", transforms=FRAME, area_to_map={12: ELWYNN})
    s.cm_quests = [
        quest(1861, SrcItemId=7207, SrcItemCount=1, ReqItemId1=7206, ReqItemCount1=1),
        quest(
            905,
            SrcItemId=102,
            ReqCreatureOrGOId1=113,
            ReqCreatureOrGOCount1=8,
            ReqCreatureOrGOId3=-6,
            ReqSpellCast3=700,
            ReqItemId1=100,
            ReqItemCount1=2,
            PointMapId=0,
            PointX=50.0,
            PointY=50.0,
        ),
        quest(76),
    ]
    flask = cmangos.Made(7207, 8919, 123, ())
    totem = cmangos.Made(102, 701, None, (("object", 174794), ("npc", 4242)))
    s.cm_links = links(
        made={7206: [flask]},
        uses={7207: [flask], 102: [totem]},
        spells={102: (700, 701)},
        focus_objects={123: [174794]},
        points={
            905: [
                (-1, 0, ((0.0, 0.0),)),  # the hand-in
                (0, 0, ((10.0, 10.0), (30.0, 30.0))),  # the first column: the boar
                (2, 0, ((-20.0, -20.0),)),  # the third column: the cannon
                (4, 0, ((60.0, 60.0),)),  # the first item
                (16, 0, ((0.0, 0.0),)),  # an event: the quest's own
                (0, 530, ((1.0, 1.0),)),  # a map that is no continent here
            ]
        },
        triggers={76: [87, 88]},
    )
    s.fdb_triggers = {87: foreverdb.SeenPoint(ELWYNN, 60.2, 49.2)}
    s.questie = Store(
        quests={
            76: StoreQuest(
                76, None, None, None, None, None, None, trigger_end={12: [(61.9, 53.2)]}
            ),
            667: StoreQuest(
                667,
                None,
                None,
                None,
                None,
                None,
                None,
                source_item=103,
                extra=((("object:6",), {}),),
            ),
            1861: StoreQuest(1861, None, None, None, None, None, None, source_item=1),
        }
    )
    w = world()
    for quest_id in (1861, 905, 76, 667):
        w.add("quest", quest_id, {"name": str(quest_id)})
    w.get("quest", 905)["requiredItems"] = [[100, 2]]  # as the quest merge writes them
    canon.merge_quest_links(w, s)
    mirror, totems = w.get("quest", 1861), w.get("quest", 905)
    assert mirror["gives"] == [[7207, 1]]  # CMaNGOS' count stays; QuestieDB fills only a gap
    assert "castAt" not in mirror  # the flask makes the sample: the item's own way says where
    assert totems["gives"] == [[102, None]]  # no count: unknown is not 1
    assert totems["goals"] == [["npc:113", 8, None], ["object:6", None, 700]]
    # where the handed item is used: its spell's target the world knows, and the creature or
    # object the quest wants it cast on
    assert totems["castAt"] == [["item:102", "object:174794"], ["item:102", "object:6"]]
    assert totems["classicPoints"] == {
        "npc:113": [[ELWYNN, 0.4, 0.4]],  # the centre of the area
        "object:6": [[ELWYNN, 0.6, 0.6]],
        "item:100": [[ELWYNN, 0.2, 0.2]],
        "": [[ELWYNN, 0.5, 0.5], [ELWYNN, 0.25, 0.25]],  # the event, then PointX and PointY
    }
    # an area trigger is where the Forever client has it; QuestieDB's `triggerEnd` beside it
    assert w.get("quest", 76)["classicPoints"] == {
        "": [[ELWYNN, 0.602, 0.492], [ELWYNN, 0.619, 0.532]]
    }
    # a thing to do the log does not list: where it stands is the quest's own place
    hidden = w.get("quest", 667)
    assert hidden["gives"] == [[103]] and hidden["classicPoints"] == {"": [[ELWYNN, 0.7, 0.7]]}
    assert w.notes == [
        "quest links: 3 quests hand an item over, 1 name creatures or objects (CMaNGOS), 1 use "
        "the handed item at a place; Classic points for 3 subjects and 3 quests"
    ]
    # the resolver reads them: the cannon is cast on, the boar counted, the item placed
    steps.resolve(w)
    rows = [dict(zip(steps.ROW, row, strict=False)) for row in totems["steps"]]
    assert [(r["kind"], r["ref"], r["count"], r.get("src")) for r in rows] == [
        ("slay", "npc:113", 8, "classic"),
        ("cast", "object:6", None, "classic"),
        ("get", "item:100", 2, "classic"),
        ("cast", "object:174794", None, None),
    ]
    assert rows[1]["via"] == ["item:102"] and rows[1]["places"] == {ELWYNN: [[0.7, 0.7]]}
    assert rows[2]["places"] == {ELWYNN: [[0.2, 0.2]]} and rows[3]["how"] == "unknown"


def test_a_vendor_questiedb_names_gets_the_item_without_a_price():
    s = Sources(client="forever")
    s.cm_items = [cmangos.item_rows({"item_template": [{"entry": 100}]})[0]]
    s.questie = Store(
        items={
            100: StoreItem(100, vendors=(98, 99, 4242)),  # 98 lists it; 4242 is nobody
            101: StoreItem(101, vendors=(99,)),
            555: StoreItem(555, vendors=(99,)),  # an item the world does not have
        }
    )
    w = world()
    assert canon.merge_questie_vendors(w, s) == 2
    assert w.get("npc", 98)["vendor"] == [[100, 50, 1, False, "classic"]]
    new = w.get("npc", 99)
    assert new["vendor"] == [[100, None, None, None, "classic"], [101, None, None, None, "questie"]]
    assert new["flags"] == ["vendor"]
    assert w.notes == ["2 vendor rows from QuestieDB's item rows (no price)"]


def test_the_merge_labels_a_quests_spots_and_keeps_the_sources_rows():
    """What the resolver reads from the real merge (the reader fixtures): where a quest's spots
    come from, and Everything Quests' rows as the source has them."""
    w = canon.build_world(fixture_sources())
    quests = w.records["quest"]
    labels = {q.get("spotsSrc") for q in quests.values() if q.get("spots")}
    assert "eq" in labels and None not in labels  # every spot list says where it is from
    with_rows = [q for q in quests.values() if q.get("eqRows")]
    assert with_rows and all(len(row) == 3 for q in with_rows for row in q["eqRows"])
    # the rows the packs carry may have become items (`fix_loot_objectives`); these have not
    assert not any(str(row[1]).startswith("item:") for q in with_rows for row in q["eqRows"])
    # none of the build's own fields is in a pack
    from bastians_build.config import load_config

    schema = load_config().packs["quests"].schema["quest"]
    for name in ("eqRows", "spotsSrc", "seenSpots", "goals", "castAt", "classicPoints"):
        assert name not in schema
    assert "steps" in schema and "gives" in schema
