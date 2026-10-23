"""Quests logic (B5.1): status reasons, chains, zone view, onward zones and the zone list; pure Lua."""

from harness import WowRuntime

CORE, DATA, QUESTS = "Bastians_Core", "Bastians_Data", "Bastians_Quests"

STATE = """
state = {
  level = %(level)d, raceID = %(race)d, classID = 8, faction = %(faction)r,
  doneSet = {%(done)s}, logSet = {%(log)s},
  done = function(id) return state.doneSet[id] == true end,
  inLog = function(id) return state.logSet[id] == true end,
  isComplete = function() return false end,
  skills = {}, rep = function() return nil end,
}
"""


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA, QUESTS)
    wow.run_frames(10)
    return wow


def state(wow: WowRuntime, level=10, race=1, faction="Alliance", done=(), log=()):
    wow.execute(
        STATE
        % {
            "level": level,
            "race": race,
            "faction": faction,
            "done": ", ".join(f"[{d}] = true" for d in done),
            "log": ", ".join(f"[{d}] = true" for d in log),
        }
    )


def logic(wow: WowRuntime, expr: str):
    """Evaluate `expr` with the Logic table and its `quest` accessor in scope."""
    return wow.eval(
        "(function() local L = Bastians:GetModule('Quests').Logic; local quest = L.quest; "
        f"return L.{expr} end)()"
    )


def test_status_reasons(wow: WowRuntime):
    boot(wow)
    state(wow, level=10)
    assert logic(wow, "status(62, state)") == "available"
    assert logic(wow, "status(76, state)")[0] == "prereq"
    _, missing = logic(wow, "status(76, state)")
    assert list(missing.values()) == [62]
    state(wow, level=10, done=(62,))
    assert logic(wow, "status(76, state)") == "available"
    assert logic(wow, "status(62, state)") == "done"
    state(wow, level=10, log=(76,))
    assert logic(wow, "status(76, state)") == "log"
    state(wow, level=3)
    assert logic(wow, "status(62, state)") == "level"  # minLevel 4
    state(wow, level=20, race=1)
    assert logic(wow, "status(1000, state)") == "never"  # Horde-only races mask
    state(wow, level=20, race=2)  # Orc
    assert logic(wow, "status(1000, state)") == "available"
    assert logic(wow, "status(424242, state)") == "never"


def test_chain_is_ordered_by_depth(wow: WowRuntime):
    boot(wow)
    state(wow)
    chain = logic(wow, "chain(76, state)")
    assert list(chain.quests.values()) == [62, 76, 11]  # 62 -> 76 -> 11 (Westfall)
    assert chain.name == "The Fargodeep Mine" and chain.pos[11] == 3
    assert logic(wow, "chain(176, state)") is None  # stands alone
    assert logic(wow, "category(62, state)") == "chain"
    assert logic(wow, "category(176, state)") == "single"


def test_a_huge_component_shows_the_line_through_the_quest(wow: WowRuntime):
    """Retail storylines join hundreds of quests through their prerequisites (K'aresh: 219 in one
    component, ): above CHAIN_MAX the chain is the line through the
    quest, back along the deepest predecessor, forward along the longest continuation."""
    boot(wow)
    state(wow)
    wow.execute(
        """
        local quests, ids = {}, {}
        for i = 1, 40 do quests[i] = { name = "Q" .. i, zone = 1 }; ids[i] = i end
        for i = 2, 30 do quests[i].pre = { 1 } end -- a hub: 1 unlocks 2..30
        quests[3].pre = { 2 }; quests[4].pre = { 3 }; quests[5].pre = { 4 } -- the story line
        for i = 31, 40 do quests[i].pre = { 30 } end -- side quests behind 30
        BST_FAKE = {
          Get = function(_, typ, id) return typ == "quest" and quests[id] or nil end,
          Index = function(_, name, key)
            if name == "quest.byZone" then
              if key == nil then return { [1] = ids } end
              return key == 1 and ids or nil
            end
            return nil
          end,
        }
        Bastians:GetModule('Quests').Logic.SetData(BST_FAKE)
        """
    )
    assert logic(wow, "IndexSource()") is None
    chain = logic(wow, "chain(3, state)")
    assert list(chain.quests.values()) == [1, 2, 3, 4, 5]
    assert chain.pos[3] == 3 and chain.line is True and chain.name == "Q1"
    chain = logic(wow, "chain(35, state)")
    assert list(chain.quests.values()) == [1, 30, 35]
    chain = logic(wow, "chain(1, state)")
    assert list(chain.quests.values()) == [1, 2, 3, 4, 5]  # the longest continuation
    assert logic(wow, "IndexSource()") == "decoded"
    # a small component is the whole chain, as before
    wow.execute("Bastians:GetModule('Quests').Logic.SetData(Bastians:GetService('data'))")
    chain = logic(wow, "chain(76, state)")
    assert list(chain.quests.values()) == [62, 76, 11] and chain.line is None
    assert wow.errors == []


def test_marks_and_group(wow: WowRuntime):
    boot(wow)
    assert list(logic(wow, "marks(quest(176))").values()) == ["Group"]
    assert logic(wow, "isGroup(quest(176))") is True
    assert logic(wow, "isGroup(quest(62))") is False
    assert list(logic(wow, "marks(quest(62))").values()) == []


def test_zone_view_groups_by_giver_nearest_first(wow: WowRuntime):
    boot(wow)
    state(wow, level=10, log=(62,))
    view = logic(wow, "zoneView(1429, state, 0.42, 0.66)")
    counts = dict(view.counts.items())
    assert counts == {"turnin": 0, "active": 1, "available": 1, "soon": 0, "blocked": 0, "done": 0}
    available = list(view.available.values())
    assert len(available) == 1 and available[0].ref == "object:1734"  # 176 (level 5+) at the poster
    assert list(available[0].quests.values()) == [176]
    active = list(view.active.values())
    assert active[0].ref == "npc:240" and list(active[0].quests.values()) == [62]
    # 76 waits for 62 which starts here: not "blocked" (same zone)
    assert len(view.blocked) == 0
    state(wow, level=10)
    view = logic(wow, "zoneView(1436, state, nil, nil)")
    assert (
        len(view.blocked) == 1
        and view.blocked[1].qid == 11
        and list(view.blocked[1].missing.values()) == [76]
    )


def test_soon_and_done(wow: WowRuntime):
    boot(wow)
    state(wow, level=2)  # 62 needs 4: soon (within 3 levels); 176 needs 5: soon
    view = logic(wow, "zoneView(1429, state, nil, nil)")
    assert dict(view.counts.items())["soon"] == 2
    state(wow, level=10, done=(62, 176))
    view = logic(wow, "zoneView(1429, state, nil, nil)")
    assert (
        dict(view.counts.items())["done"] == 2 and dict(view.counts.items())["available"] == 1
    )  # 76


def test_onward_and_leads_to(wow: WowRuntime):
    boot(wow)
    state(wow)
    onward = list(logic(wow, "onward(1429, state)").values())
    assert [(o.map, o.n, o.name) for o in onward] == [(1436, 1, "Westfall")]
    assert list(logic(wow, "leadsTo(76, 1429)").values()) == [1436]
    assert list(logic(wow, "next(62)").values()) == [76]


def test_zone_list_by_faction(wow: WowRuntime):
    boot(wow)
    alliance = [z.map for z in logic(wow, "zones('Alliance')").values()]
    horde = [z.map for z in logic(wow, "zones('Horde')").values()]
    assert alliance == [1429, 1436]  # Elwynn (median 9) before Westfall (median 10)
    assert horde == [1429, 1436]  # both zones have faction-free quests too
    elwynn = logic(wow, "zoneInfo(1429)")
    assert (elwynn.lo, elwynn.hi, elwynn.med, elwynn.a, elwynn.h) == (7, 11, 9, 3, 3)
    westfall = logic(wow, "zoneInfo(1436)")
    assert (westfall.a, westfall.h) == (1, 2)  # the Horde-only errand counts for Horde only
    assert logic(wow, "neighbor(1429, 'Alliance', 1)") == 1436
    assert logic(wow, "neighbor(1436, 'Alliance', 1)") is None
    assert logic(wow, "knows(1429)") is True and logic(wow, "knows(99)") is False
    # a dungeon (UiMap type 4) or a zone without a name is no neighbour (owner, Forever
    # 23.10.2026: "Zone 253" among Elwynn's neighbours)
    wow.execute(
        """
        local d = Bastians:GetService("data")
        realGet = d.Get
        d.Get = function(self, typ, id)
          local r = realGet(self, typ, id)
          if typ == "zone" and id == 1436 and r then
            local copy = {}
            for k, v in pairs(r) do copy[k] = v end
            copy.mapType = 4
            return copy
          end
          return r
        end
        """
    )
    assert [z.map for z in logic(wow, "zones('Alliance')").values()] == [1429]
    assert logic(wow, "neighbor(1429, 'Alliance', 1)") is None
    wow.execute("Bastians:GetService('data').Get = realGet")


def test_quest_graph_comes_from_the_pack_and_falls_back_to_decoding(wow: WowRuntime):
    """B11.1: the pack ships byStart, byTurnIn, followers and the chain components; a pack without
    them gets the same answers from every record decoded (0.5 s on the retail pack, nfr.md)."""
    boot(wow)
    state(wow, level=10)
    assert logic(wow, "IndexSource()") is None  # nothing queried yet
    assert logic(wow, "knows(1429)") is True
    assert logic(wow, "IndexSource()") == "pack"
    shipped = {
        "view": [g.ref for g in logic(wow, "zoneView(1429, state, 0.42, 0.65).available").values()],
        "next": list(logic(wow, "next(62)").values()),
        "chain": list(logic(wow, "chain(76, state).quests").values()),
        "onward": [z.map for z in logic(wow, "onward(1429, state)").values()],
    }
    assert shipped["next"] == [76] and shipped["chain"] == [62, 76, 11]
    # the same pack without the graph: Logic derives it from the records
    wow.execute(
        """
        local idx = Bastians.Data.packs.quests.index
        for _, name in ipairs({ "quest.byStart", "quest.byTurnIn", "quest.followers",
                                "quest.chainMembers", "quest.chainFrom" }) do
          idx[name] = nil
        end
        Bastians:GetModule('Quests').Logic.Reset()
        """
    )
    assert logic(wow, "knows(1429)") is True
    assert logic(wow, "IndexSource()") == "decoded"
    decoded = {
        "view": [g.ref for g in logic(wow, "zoneView(1429, state, 0.42, 0.65).available").values()],
        "next": list(logic(wow, "next(62)").values()),
        "chain": list(logic(wow, "chain(76, state).quests").values()),
        "onward": [z.map for z in logic(wow, "onward(1429, state)").values()],
    }
    assert decoded == shipped
    assert wow.errors == []
