"""The guide gaps (23.10.2026): what AHSyncGuide showed, so it can be uninstalled. A monster's
tooltip says which log quest needs it and its drops worth most; a gathering node's tooltip says
what it gives, its skill and its places here; an item page says where to get it by zone; a zone
page lists its monsters. Objects are known by id, never by the tooltip's (secret) name."""

import re

from harness import WowRuntime
from pages import page_rows

CORE, DATA, QUESTS, GOLD, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Gold",
    "Bastians_Browser",
)


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.execute('function GetRealmName() return "Classic Beta PvE" end')
    wow.start(*(addons or (CORE, DATA, QUESTS, GOLD)))
    wow.run_frames(10)
    wow.advance(0.3)
    return wow


def strip(text) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", str(text or ""))
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def lines(wow: WowRuntime, kind: str, ref_id: int, guid: str | None = None) -> list[str]:
    g = f"'{guid}'" if guid else "nil"
    out = wow.eval(f"Mock.Tooltip(Enum.TooltipDataType.{kind}, {ref_id}, {g})")
    return [
        strip(line.left) + (("  =  " + strip(line.right)) if line.right else "")
        for line in out.values()
    ]


def test_a_monster_tooltip_says_target_of_and_its_best_drops(wow: WowRuntime):
    boot(wow)
    got = lines(wow, "Unit", 448)  # Hogger: quest 176 in the log needs his claw
    target = [line for line in got if line.startswith("Target of:")]
    # the log's title; no progress: the mock's log lists an exploration and no item, so the claw's
    # count is not known (it read the exploration's 0/1: plan-quest-links.md S3)
    assert target == ["Target of: The Fargodeep Mine"]
    drops = [line for line in got if "%" in line]
    if wow.made_for(GOLD):
        # chance x price: Blood Saber (3.2 % of 50s) before Linen Cloth (45.5 % of 38c)
        assert drops[0].startswith("Blood Saber  3.2 %  =  50s")
        assert drops[1].startswith("Linen Cloth  45.5 %")
    else:  # the drops are Gold's; no Gold on retail
        assert drops == []
    assert wow.errors == []


def test_target_of_matches_slay_loot_sources_and_item_droppers(wow: WowRuntime):
    boot(wow)
    wow.execute(
        """
        local Reg = Bastians:GetModule('Quests').Registrations
        local quests = { -- each quest's `steps` facet: the things to do with the log's counts
          [1] = { { step = "take" }, { step = "slay", ref = "npc:7", n = 1, have = 3, count = 8 },
            { step = "handin" } },
          [2] = { { step = "take" }, { step = "get", ref = "item:5", via = { "npc:8" }, n = 1,
            have = 1, count = 1, done = true }, { step = "handin" } },
          -- two things to do: the first is another's, the second the item this creature drops
          [3] = { { step = "take" }, { step = "slay", ref = "npc:99", n = 1, have = 0, count = 1 },
            { step = "get", ref = "item:6", n = 2, have = 2, count = 5 }, { step = "handin" } },
          [4] = { { step = "take" }, { step = "slay", refs = { "npc:99", "npc:10" } },
            { step = "get", ref = "item:7", places = { { map = 1, x = 0.1, y = 0.1, ref = "npc:11" } } },
            { step = "handin", ref = "npc:12" } },
        }
        local items = { [6] = { drops = { { "npc:9", 20 } } } }
        local log = { [1] = { title = "Wolves" }, [2] = { title = "Claws" }, [3] = { title = "Pelts" },
          [4] = { title = "Other" } }
        local function q(id) return quests[id] end
        local function it(id) return items[id] end
        hit7 = Reg.TargetOf("npc:7", log, q, it)
        hit8 = Reg.TargetOf("npc:8", log, q, it)
        hit9 = Reg.TargetOf("npc:9", log, q, it)
        hit10 = Reg.TargetOf("npc:10", log, q, it)
        hit11 = Reg.TargetOf("npc:11", log, q, it)
        miss = Reg.TargetOf("npc:1", log, q, it)
        taker = Reg.TargetOf("npc:12", log, q, it)
        """
    )
    assert [(r.text, r.value) for r in wow.eval("hit7").values()] == [("Wolves", "3/8")]
    assert [(r.text, r.value) for r in wow.eval("hit8").values()] == [("Claws", "done")]
    # its own step's count, not the first objective's (S3)
    assert [(r.text, r.value) for r in wow.eval("hit9").values()] == [("Pelts", "2/5")]
    # one of several that count, and who stands at a step's place; no count known: none shown
    assert [(r.text, r.value) for r in wow.eval("hit10").values()] == [("Other", None)]
    assert [(r.text, r.value) for r in wow.eval("hit11").values()] == [("Other", None)]
    assert len(wow.eval("miss")) == 0 and len(wow.eval("taker")) == 0  # the hand-in is no target
    assert wow.errors == []


def register_nodes(wow: WowRuntime) -> None:
    """A node pack of its own: Peacebloom (ForeverDB kind 77, three places in Elwynn) and the
    object 1618 of the same name, as the Forever packs have them."""
    wow.execute(
        """
        Bastians.Data.RegisterPack("guidetest", {
          client = Bastians.Client, schema = {
            node = { "name", "kind", "profession", "skill", "item", "icon", "spawns", "src" },
            object = { "name", "kind", "zone", "spawns", "loot", "lootSrc", "src" },
          },
          node = { [77] = { "Peacebloom", "herb", "Herbalism", 1, 2589, nil,
            { { 1429, 0.4, 0.5, "fdb" }, { 1429, 0.42, 0.52, "fdb" }, { 1429, 0.5, 0.6, "fdb" },
              { 1436, 0.3, 0.3, "fdb" } }, "forever" } },
          object = { [1618] = { "Peacebloom", "chest", 1429, nil, nil, nil, "classic" } },
        })
        """
    )


def test_a_node_tooltip_says_what_it_gives_its_skill_and_places_here(wow: WowRuntime):
    boot(wow)
    register_nodes(wow)
    got = lines(wow, "Object", 1618, "GameObject-0-1-0-1-1618-0000000001")
    assert got[0].startswith("Gives: Linen Cloth  =  ")  # the item's worth through Core
    assert "Herbalism 1" in got
    assert "3 places in Elwynn Forest" in got  # the player's map only
    # an id the packs do not know shows nothing; a secret id is unknown (Compat.Plain)
    assert lines(wow, "Object", 4242) == []
    assert wow.eval("(Bastians.Data.NodeOf(1618))") == 77
    assert wow.errors == []


def test_an_item_page_says_where_to_get_it_and_a_zone_lists_its_monsters(wow: WowRuntime):
    boot(wow, CORE, DATA, QUESTS, GOLD, BROWSER)
    register_nodes(wow)
    wow.slash("/bb item:2589")
    wow.run_frames(5)
    rows = page_rows(wow, "Bastians:GetModule('Browser').dossier")
    assert "Where to get it" in rows
    after = rows[rows.index("Where to get it") + 1 :]
    assert strip(after[0]).startswith("Elwynn Forest")  # the player's zone first
    assert any(strip(r).startswith("Westfall") for r in after[:4])
    wow.slash("/bb zone:1429")
    wow.run_frames(5)
    rows = page_rows(wow, "Bastians:GetModule('Browser').dossier")
    assert "Monsters" in rows
    monsters = rows[rows.index("Monsters") + 1 :]
    assert any(strip(r).startswith("Hogger") for r in monsters[:6])
    assert not any(strip(r).startswith("Marshal Dughan") for r in monsters[:6])  # a quest giver
    assert wow.errors == []
