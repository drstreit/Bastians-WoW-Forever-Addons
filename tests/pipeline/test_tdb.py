"""TrinityCore's retail world database (sources/tdb.py, sources.md): the dump's tables in CMaNGOS'
shape, the client's FactionTemplate (side, hostility) and ContentTuning (the level band), the
merge into the retail world (services, rank, level, side, places of the NPCs that serve, the
objects a player looks for) and the danger points straight from its spawns."""

from bastians_build.canon import Sources, merge_tdb, merge_tdb_loot
from bastians_build.model import World
from bastians_build.navnet import tdb_danger
from bastians_build.sources.cmangos import read_lines
from bastians_build.sources.probe import Transform
from bastians_build.sources.tdb import WANTED, build, faction_sides, tuning_levels

# a few lines in the dump's shape (column lists cut to what the reader wants, plus one it skips)
DUMP = """CREATE TABLE `creature_template` (
  `entry` int unsigned NOT NULL DEFAULT '0',
  `name` text,
  `subname` text,
  `faction` smallint unsigned NOT NULL DEFAULT '0',
  `npcflag` bigint unsigned NOT NULL DEFAULT '0',
  `speed_walk` float NOT NULL DEFAULT '1',
  `Classification` tinyint NOT NULL DEFAULT '0'
) ENGINE=InnoDB;
INSERT INTO `creature_template` VALUES (448,'Hogger','',20,0,1,1);
INSERT INTO `creature_template` VALUES (295,'Innkeeper Farley','Innkeeper',12,66179,1,0);
INSERT INTO `creature_template` VALUES (68,'Stormwind City Guard','',12,1,1,0);
INSERT INTO `creature_template` VALUES (1,'Waypoint','Visual',35,0,1,0);
CREATE TABLE `creature_template_difficulty` (
  `Entry` int unsigned NOT NULL,
  `DifficultyID` tinyint unsigned NOT NULL DEFAULT '0',
  `ContentTuningID` int NOT NULL DEFAULT '0',
  `LootID` int unsigned NOT NULL DEFAULT '0'
) ENGINE=InnoDB;
INSERT INTO `creature_template_difficulty` VALUES (448,0,73,448),(448,1,99,0),(295,0,73,0);
CREATE TABLE `creature` (
  `guid` bigint unsigned NOT NULL,
  `id` int unsigned NOT NULL,
  `map` smallint unsigned NOT NULL,
  `position_x` float NOT NULL,
  `position_y` float NOT NULL,
  `position_z` float NOT NULL
) ENGINE=InnoDB;
INSERT INTO `creature` VALUES (1,448,0,-9500,100,50),(2,295,0,-9460,60,58);
INSERT INTO `creature` VALUES (3,68,0,-9000,800,90),(4,448,530,1,2,3);
CREATE TABLE `gameobject_template` (
  `entry` int unsigned NOT NULL,
  `type` tinyint unsigned NOT NULL,
  `name` text,
  `Data1` int NOT NULL DEFAULT '0'
) ENGINE=InnoDB;
INSERT INTO `gameobject_template` VALUES (143983,19,'Mailbox',0),(1,3,'Chest',500);
CREATE TABLE `gameobject` (
  `guid` bigint unsigned NOT NULL,
  `id` int unsigned NOT NULL,
  `map` smallint unsigned NOT NULL,
  `position_x` float NOT NULL,
  `position_y` float NOT NULL,
  `position_z` float NOT NULL
) ENGINE=InnoDB;
INSERT INTO `gameobject` VALUES (9,143983,0,-9465,70,58),(10,1,0,-9400,0,40);
CREATE TABLE `creature_loot_template` (
  `Entry` int unsigned NOT NULL DEFAULT '0',
  `ItemType` tinyint NOT NULL DEFAULT '0',
  `Item` int unsigned NOT NULL DEFAULT '0',
  `Chance` float NOT NULL DEFAULT '100',
  `QuestRequired` tinyint(1) NOT NULL DEFAULT '0',
  `LootMode` smallint unsigned NOT NULL DEFAULT '1',
  `GroupId` tinyint unsigned NOT NULL DEFAULT '0',
  `MinCount` tinyint unsigned NOT NULL DEFAULT '1',
  `MaxCount` tinyint unsigned NOT NULL DEFAULT '1',
  `Comment` varchar(255) DEFAULT NULL
) ENGINE=InnoDB;
INSERT INTO `creature_loot_template` VALUES (448,0,1931,40,1,1,0,1,1,'claw');
INSERT INTO `creature_loot_template` VALUES (448,1,24000,100,0,1,0,1,1,'shared');
INSERT INTO `creature_loot_template` VALUES (448,0,999,50,0,4,0,1,1,'hard mode');
CREATE TABLE `gameobject_loot_template` (
  `Entry` int unsigned NOT NULL DEFAULT '0',
  `ItemType` tinyint NOT NULL DEFAULT '0',
  `Item` int unsigned NOT NULL DEFAULT '0',
  `Chance` float NOT NULL DEFAULT '100',
  `QuestRequired` tinyint(1) NOT NULL DEFAULT '0',
  `LootMode` smallint unsigned NOT NULL DEFAULT '1',
  `GroupId` tinyint unsigned NOT NULL DEFAULT '0',
  `MinCount` tinyint unsigned NOT NULL DEFAULT '1',
  `MaxCount` tinyint unsigned NOT NULL DEFAULT '1',
  `Comment` varchar(255) DEFAULT NULL
) ENGINE=InnoDB;
INSERT INTO `gameobject_loot_template` VALUES (500,0,2318,100,0,1,0,1,1,'leather');
CREATE TABLE `reference_loot_template` (
  `Entry` int unsigned NOT NULL DEFAULT '0',
  `ItemType` tinyint NOT NULL DEFAULT '0',
  `Item` int unsigned NOT NULL DEFAULT '0',
  `Chance` float NOT NULL DEFAULT '100',
  `QuestRequired` tinyint(1) NOT NULL DEFAULT '0',
  `LootMode` smallint unsigned NOT NULL DEFAULT '1',
  `GroupId` tinyint unsigned NOT NULL DEFAULT '0',
  `MinCount` tinyint unsigned NOT NULL DEFAULT '1',
  `MaxCount` tinyint unsigned NOT NULL DEFAULT '1',
  `Comment` varchar(255) DEFAULT NULL
) ENGINE=InnoDB;
INSERT INTO `reference_loot_template` VALUES (24000,0,2589,10,0,1,0,1,1,'linen');
INSERT INTO `reference_loot_template` VALUES (24000,2,1,100,0,1,0,1,1,'a currency');
"""

FACTIONS = [
    {"ID": 20, "FactionGroup": 8, "EnemyGroup": 1},  # monster, hostile to players
    {"ID": 12, "FactionGroup": 2, "EnemyGroup": 4},  # Stormwind
    {"ID": 85, "FactionGroup": 5, "EnemyGroup": 10},  # Orgrimmar: players and Horde
    {"ID": 35, "FactionGroup": 0, "FriendGroup": 1, "EnemyGroup": 0},  # friendly to all
]
TUNING = [{"ID": 73, "MinLevelSquish": 1, "MaxLevelSquish": 30}]

# a test map over the dump's Elwynn corner: wx -10000..-9000, wy -500..1500
ELWYNN = Transform(
    ui_map_id=37,
    continent=0,
    wx0=-9000.0,
    wx_dx=0.0,
    wx_dy=-1000.0,
    wy0=1500.0,
    wy_dx=-2000.0,
    wy_dy=0.0,
    exact=True,
)


def tdb():
    tables = read_lines(DUMP.splitlines(keepends=True), WANTED)
    return build(tables, faction_sides(FACTIONS), tuning_levels(TUNING))


def test_the_dump_reads_into_typed_creatures_and_spawns():
    t = tdb()
    hogger, farley, guard = t.creatures[448], t.creatures[295], t.creatures[68]
    assert (hogger.rank, hogger.hostile, hogger.side, hogger.services) == ("elite", True, None, ())
    assert (hogger.level, hogger.level_max) == (1, 30)  # open world only (difficulty 0)
    assert farley.services == (
        "questgiver",
        "vendor",
        "innkeeper",
    )  # 66179: gossip, food vendor too
    assert (farley.subname, farley.side, farley.hostile) == ("Innkeeper", "A", False)
    assert guard.level is None  # no content tuning: unknown, not 0
    assert t.creatures[1].subname == "Visual" and t.creatures[1].hostile is False
    assert [(s.entry, s.map_id) for s in t.spawns] == [(448, 0), (295, 0), (68, 0)]  # 530 left out
    assert t.objects[143983] == (19, "Mailbox")


def test_faction_sides_and_hostility():
    sides = faction_sides(FACTIONS)
    assert sides[20] == (None, True)
    assert sides[12] == ("A", False)
    assert sides[85] == ("H", False)  # hostile to the Alliance only: a side, not a monster
    assert sides[35] == (None, False)
    assert tuning_levels([{"ID": 1, "MinLevelSquish": 0, "MaxLevelSquish": 0}])[1] == (None, None)


def test_the_merge_gives_services_levels_and_places():
    world = World(client="retail", build="test")
    world.add("npc", 448, {"name": "Hogger", "spawns": [[37, 0.5, 0.5, "att"]]})  # ATT knows him
    s = Sources(client="retail", transforms={37: ELWYNN}, tdb=tdb())
    merge_tdb(world, s)
    hogger = world.get("npc", 448)
    assert hogger["flags"] == ["elite"] and hogger["level"] == 1 and hogger["levelMax"] == 30
    assert hogger["spawns"] == [[37, 0.5, 0.5, "att"]]  # no service: his TDB places stay out
    farley = world.get("npc", 295)  # new: an innkeeper with a place
    assert farley["name"] == "Innkeeper Farley" and farley["subname"] == "Innkeeper"
    assert farley["flags"] == ["questgiver", "vendor", "innkeeper"]
    assert farley["faction"] == "A" and farley["src"] == "tdb"
    assert len(farley["spawns"]) == 1 and farley["spawns"][0][0] == 37
    assert farley["spawns"][0][3:] == ["tdb", 58.0]
    assert world.get("npc", 68) is None  # no service, unknown to the retail sources
    mailbox = world.get("object", 143983)
    assert mailbox["kind"] == "mailbox" and len(mailbox["spawns"]) == 1
    assert world.get("object", 1) is None  # a chest is not a kind placed from the TDB
    assert merge_tdb(World(client="retail"), Sources(client="retail")) is None  # no TDB: nothing


def test_the_danger_comes_from_the_spawns():
    d = tdb_danger(tdb())
    assert d["hostile"] == [[0, -9500.0, 100.0, 1, True]]  # Hogger at his band's lowest, elite
    assert d["guards"] == [[0, -9000.0, 800.0, "A"]]
    assert tdb_danger(None) == {"hostile": [], "guards": []}


def test_cmangos_creatures_get_their_side_and_hostility_from_the_client():
    """Forever had no guards (0 found, 26.10.2026): CMaNGOS' creatures had no side. The Faction
    column through the client's FactionTemplate gives it, and the hostility for the danger."""
    from bastians_build.canon import merge_creatures

    rows = [
        {"Entry": 68, "Name": "Stormwind City Guard", "MinLevel": 55, "Faction": 12},
        {"Entry": 448, "Name": "Hogger", "MinLevel": 11, "Faction": 20, "Rank": 1},
        {"Entry": 721, "Name": "Rabbit", "MinLevel": 1, "Faction": 35},
        {"Entry": 9, "Name": "Unknown", "MinLevel": 3, "Faction": 999},
    ]
    s = Sources(client="forever", cm_creatures=rows, cm_factions=faction_sides(FACTIONS))
    world = World(client="forever", build="test")
    merge_creatures(world, s)
    guard, hogger, rabbit, unknown = (world.get("npc", i) for i in (68, 448, 721, 9))
    assert guard["faction"] == "A" and guard["hostile"] is False
    assert hogger.get("faction") is None and hogger["hostile"] is True
    assert rabbit.get("faction") is None and rabbit["hostile"] is False
    assert "hostile" not in unknown  # a template the client lacks: unknown, the Monsters rule


def test_the_loot_reads_by_loot_list_normal_mode_only():
    """28.10.2026: retail's drops and world drops from TrinityCore's loot tables. A creature's list
    is its LootID, a chest's its Data1; shared lists stay lists; the hard modes and the
    currencies are left out."""
    rows = {(r.kind, r.entry, r.item_id, r.reference_id): r for r in tdb().loot}
    claw = rows[("creature", 448, 1931, None)]
    assert (claw.chance_pct, claw.quest_drop) == (40.0, True)
    assert ("creature", 448, None, 24000) in rows
    assert not any(k[2] == 999 for k in rows)  # LootMode 4: a hard mode
    assert ("object", 1, 2318, None) in rows  # the chest's list 500
    assert ("reference", 24000, 2589, None) in rows
    assert not any(k[0] == "reference" and k[2] == 1 for k in rows)  # a currency


def test_the_loot_merges_into_drops_on_the_continents():
    s = Sources(client="retail")
    s.tdb = tdb()
    world = World("retail")
    for item in (1931, 2589, 2318):
        world.add("item", item, {"name": f"Item {item}"})
    world.add("npc", 448, {"name": "Hogger"})
    merge_tdb_loot(world, s)
    assert world.get("item", 1931)["drops"] == [["npc:448", 40.0, True]]
    assert world.get("item", 2589)["drops"] == [["npc:448", 10.0, False]]  # via the shared list
    assert world.get("item", 2318)["drops"] == [["object:1", 100.0, False]]
    assert world.get("item", 1931)["dropsSrc"] == "tdb"
    assert world.get("npc", 448)["loot"][0] == [1931, 40.0]
