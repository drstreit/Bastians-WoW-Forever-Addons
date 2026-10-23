"""Quests registrations (B5.4): status layers, hand-in and objective layers, track actions, quest
detail sections, the "Needed for quests" item section and the quest-text search provider."""

import re

from harness import WowRuntime

CORE, DATA, QUESTS = "Bastians_Core", "Bastians_Data", "Bastians_Quests"
ELWYNN_VIEW = "{ continent = 0, x1 = -300, y1 = -300, x2 = 300, y2 = 300, level = 3 }"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, QUESTS)))
    wow.run_frames(10)
    wow.advance(0.2)  # the data-loaded refresh fires and queues the giver index job (B11.1)
    wow.run_frames(10)  # the job runs on frames
    return wow


def strip(text: str) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def pins(wow: WowRuntime, layer: str) -> dict:
    return {p.ref: p for p in wow.eval(f"Bastians:QueryLayer('{layer}', {ELWYNN_VIEW})").values()}


def sections(wow: WowRuntime, ref: str) -> dict:
    return {s.id: s for s in wow.eval(f"Bastians:GetDetailSections('{ref}')").values()}


def texts(rows) -> list[str]:
    return [strip(r.text) for r in rows.values()]


def actions(wow: WowRuntime, ref: str) -> list[str]:
    return [a.id for a in wow.eval(f"Bastians:GetActions('{ref}', {{ source = 'test' }})").values()]


def errors(wow: WowRuntime) -> list[str]:
    return wow.errors + [
        line.text
        for line in wow.eval("Bastians:GetLog()").values()
        if line.level == "error" and "registered no data" not in line.text
    ]


def test_giver_index_is_built_in_a_job_and_the_layers_query_only_its_cells(wow: WowRuntime):
    """B11.1 low-zoom queries: giver positions in spatial buckets, built once per data load in a
    job; the status layers touch only the cells under the view (110 ms cold before, nfr.md)."""
    boot(wow)
    reg = "Bastians:GetModule('Quests').Registrations"
    assert wow.eval(f"{reg}.indexed") >= 1 and wow.eval(f"{reg}.GiverIndex()[0] ~= nil")
    cells = wow.eval(
        f"(function() local n = 0 for _, list in pairs({reg}.GiverIndex()[0]) do n = n + #list / 3 end"
        " return n end)()"
    )
    assert cells >= 1  # Marshal Dughan's spawn in Elwynn
    assert list(pins(wow, "quests.soon")) == ["npc:240"]
    far = "{ continent = 0, x1 = 20000, y1 = 20000, x2 = 20100, y2 = 20100, level = 3 }"
    assert wow.eval(f"#Bastians:QueryLayer('quests.soon', {far})") == 0
    other = "{ continent = 1, x1 = -300, y1 = -300, x2 = 300, y2 = 300, level = 3 }"
    assert wow.eval(f"#Bastians:QueryLayer('quests.soon', {other})") == 0
    # a rebuild (new data) empties the layers until the job is done, then they change once
    wow.execute(
        """
        layers = {}
        local w = Bastians:NewModule("IndexWatcher", { addon = "Bastians_Quests" })
        w:On("BASTIANS_LAYER_CHANGED", function(_, _, id) layers[#layers + 1] = id end)
        """
    )
    wow.execute(f"{reg}.BuildGiverIndex(Bastians:GetModule('Quests'))")
    assert wow.eval(f"{reg}.GiverIndex()") is None and pins(wow, "quests.soon") == {}
    wow.run_frames(5)
    assert wow.eval(f"{reg}.GiverIndex()[0] ~= nil") and list(pins(wow, "quests.soon")) == [
        "npc:240"
    ]
    assert list(wow.eval("layers").values()) == ["quests.available", "quests.soon"]
    assert errors(wow) == []


def test_layers_show_givers_by_status_hand_ins_and_objectives(wow: WowRuntime):
    boot(wow)
    wow.execute(
        """
        layers = {}
        local w = Bastians:NewModule("LayerWatcher", { addon = "Bastians_Quests" })
        w:On("BASTIANS_LAYER_CHANGED", function(_, _, id) layers[#layers + 1] = id end)
        """
    )
    # level 12 with 176 and 62 in the log: nothing to take, 76 waits for 62 (soon layer, "blocked")
    assert pins(wow, "quests.available") == {}
    soon = pins(wow, "quests.soon")
    assert list(soon) == ["npc:240"] and soon["npc:240"].status == "blocked"
    turnin = pins(wow, "quests.turnin")
    assert list(turnin) == ["npc:240"]
    assert turnin["npc:240"].complete is True  # 62 is complete: the taker gets the hand-in colour
    assert list(turnin["npc:240"].color.values()) == list(
        wow.eval("Bastians.UI.Style.C.gold").values()
    )  # the token (ST3)
    assert turnin["npc:240"].label == "Marshal Dughan"
    spots = list(wow.eval(f"Bastians:QueryLayer('quests.objectives', {ELWYNN_VIEW})").values())
    assert [(p.ref, p.label, p.radius, p.cluster) for p in spots] == [
        ("quest:176", "The Fargodeep Mine", 60, False),
        ("quest:176", "The Fargodeep Mine", 60, False),
    ]
    assert wow.eval("Bastians.UI.GlyphKind")(spots[0].icon) == wow.eval(
        "Bastians.UI.MobKind()"
    )  # the monster glyph
    assert wow.eval("Bastians:GetMapLayer('quests.soon').defaultOn") is False
    assert wow.eval("Bastians:GetMapLayer('quests.available').defaultOn") is True
    # 62 handed in: 76 opens up, the giver moves from the soon layer to the available layer
    wow.execute("Mock.completedQuests = { 783, 7, 18, 62 }; table.remove(Mock.questLog, 3)")
    wow.fire("QUEST_TURNED_IN", 62, 300, 150)
    wow.fire("QUEST_LOG_UPDATE")
    wow.advance(0.2)
    available = pins(wow, "quests.available")
    assert list(available) == ["npc:240"] and available["npc:240"].status == "available"
    assert pins(wow, "quests.soon") == {}
    assert pins(wow, "quests.turnin")["npc:240"].complete is False  # only 176 left, not complete
    assert sorted(set(wow.g.layers.values())) == [
        "quests.available",
        "quests.objectives",
        "quests.soon",
        "quests.turnin",
    ]
    assert errors(wow) == []


def test_track_and_untrack_actions_follow_the_objective_tracker(wow: WowRuntime):
    boot(wow)
    wow.execute(
        """
        tracked = {}
        local w = Bastians:NewModule("TrackWatcher", { addon = "Bastians_Quests" })
        w:On("BASTIANS_TRACKED_CHANGED", function(_, _, ref, on) tracked[#tracked + 1] = ref .. "=" .. tostring(on) end)
        """
    )
    assert "quests.track" in actions(wow, "quest:176") and "quests.untrack" not in actions(
        wow, "quest:176"
    )
    assert not {"quests.track", "quests.untrack"} & set(actions(wow, "quest:76"))  # not in the log
    wow.execute("Bastians:RunAction('quests.track', 'quest:176', { source = 'test' })")
    assert list(wow.g["Mock"].watched.values()) == [176]
    assert list(wow.g.tracked.values()) == ["quest:176=true"]
    assert wow.eval("Bastians:GetModule('Quests').State.IsTracked(176)") is True
    assert "quests.untrack" in actions(wow, "quest:176") and "quests.track" not in actions(
        wow, "quest:176"
    )
    assert "tracked" in strip(sections(wow, "quest:176")["quests.status"].rows[1].text)
    wow.execute("C_QuestLog.RemoveQuestWatch(176)")  # another addon or the default UI
    assert list(wow.g.tracked.values()) == ["quest:176=true", "quest:176=false"]
    assert "quests.track" in actions(wow, "quest:176")
    assert errors(wow) == []


def test_quest_sections_status_chain_prerequisites_objectives_rewards_text(wow: WowRuntime):
    boot(wow)
    hogger = sections(wow, "quest:176")
    assert [s for s in hogger] == [
        "quests.status",
        "quests.givers",
        "quests.enders",
        "quests.rewards",
        "quests.choice",  # two choices: the comparison (S7)
        "quests.objectives",
        "data.overview",
        "quests.text",
        "data.zone",
    ]
    # the dossier markers (C2): one-cell blocks, Chain and Quest text across the row, links
    assert hogger["quests.givers"]["def"].block.columns == 1
    defs = {k: v["def"] for k, v in hogger.items()}
    assert defs["quests.text"].block.wide is True and defs["data.zone"].link == "zone"
    assert texts(hogger["quests.status"].rows) == ["In the log 0/1"]
    # who gives and takes the quest, with a link to their page
    givers = list(hogger["quests.givers"].rows.values())
    assert [r.ref for r in givers] == ["object:1734"]  # the fixture's Wanted poster
    enders = list(hogger["quests.enders"].rows.values())
    assert [r.ref for r in enders] == ["npc:240"] and enders[0].text.startswith("Marshal Dughan")
    assert texts(hogger["quests.objectives"].rows) == ["Explore the Fargodeep Mine  0/1"]  # live
    rewards = list(hogger["quests.rewards"].rows.values())
    assert [(strip(r.text), r.ref, r.value, r.valueKind, r.note) for r in rewards] == [
        ("Money", None, 150, "money", None),
        ("Choice: Blood Saber", "item:1185", None, None, None),  # no prices service: unknown
        ("Choice: Light Leather x2", "item:2318", None, None, None),
    ]
    assert texts(hogger["quests.text"].rows) == ["Quest texts are not loaded. Click to load them."]
    wow.execute("Bastians:GetDetailSections('quest:176')[8].rows[1].onClick()")  # the text
    wow.run_frames(5)
    text = sections(wow, "quest:176")["quests.text"].rows
    assert texts(text) == [
        "Hogger has terrorised the farms of Elwynn long enough.",
        "Bring Huge Gnoll Claw to Marshal Dughan in Goldshire.",
        "You have done Elwynn a great service.",
    ]
    assert all(r.note is None and r.kind == "para" for r in text.values())
    # out of the log: the objectives come from the data
    wow.execute("table.remove(Mock.questLog, 2)")
    wow.fire("QUEST_LOG_UPDATE")
    wow.advance(0.2)
    hogger = sections(wow, "quest:176")
    assert texts(hogger["quests.status"].rows) == ["Available"]
    objectives = list(hogger["quests.objectives"].rows.values())
    assert [(strip(r.text), r.ref) for r in objectives] == [("loot: Hogger", "npc:448")]
    # a chain quest: chain and prerequisites
    jasper = sections(wow, "quest:76")
    assert texts(jasper["quests.status"].rows) == ["Needs: The Fargodeep Mine"]
    assert texts(jasper["quests.chain"].rows) == [
        # where to go on: the first quest of the chain the player can act on (62 is in the log)
        "Continue the chain with: [7] The Fargodeep Mine  Chain 1/3  (Elwynn Forest)",
        "[7] The Fargodeep Mine  Chain 1/3",
        "[9] The Jasperlode Mine  Chain 2/3 - > Westfall",
        "[10] Riverpaw Gnoll Bounty  Chain 3/3  (Westfall)",
    ]
    assert jasper["quests.chain"].rows[1].ref == "quest:62"
    assert jasper["quests.chain"].rows[3].color is not None  # the quest itself, accented
    assert texts(jasper["quests.after"].rows) == [
        "one of: [7] The Fargodeep Mine  Chain 1/3",
    ]
    assert jasper["quests.after"]["def"].link == "after"
    assert [r.ref for r in jasper["quests.unlocks"].rows.values()] == ["quest:11"]
    assert "quests.unlocks" not in hogger  # nothing follows Hogger
    assert "quests.objectives" not in jasper
    # a quest without known rewards says so
    assert texts(jasper["quests.rewards"].rows)[0].startswith("No reward known")
    assert errors(wow) == []


def test_item_needed_for_quests_section_and_tooltip(wow: WowRuntime):
    boot(wow)
    claw = sections(wow, "item:1931")
    assert "quests.needed" in claw
    rows = list(claw["quests.needed"].rows.values())
    assert [(r.text, r.kind) for r in rows] == [("In your log", "section")]  # the category row
    assert [(strip(r.text), r.ref, r.value) for r in rows[0].children.values()] == [
        ('Wanted: "Hogger"  In your log 0/1', "quest:176", 11)
    ]
    tips = wow.eval("Bastians:GetTooltipRows('item:1931')")
    assert [strip(r.text) for r in tips.values()] == ['Wanted: "Hogger"  In your log 0/1']
    assert "quests.needed" not in sections(wow, "item:2589")
    assert errors(wow) == []


def test_search_provider_offers_the_text_pack_then_searches_it(wow: WowRuntime):
    boot(wow)
    search = """
      hits = nil
      Bastians:Search(%r, { limit = 10 }, function(results, done) if done then hits = results end end)
    """
    wow.execute(search % "terrorised")
    wow.run_frames(10)
    offer = [h for h in wow.g.hits.values() if h.ref is None]
    assert [h.label for h in offer] == ["Load quest texts to search them"]
    wow.execute("for _, h in ipairs(hits) do if h.action then h.action() end end")
    wow.run_frames(5)
    assert wow.eval("Bastians:GetService('data'):PackLoaded('text')") is True
    wow.execute(search % "terrorised")
    wow.run_frames(10)
    hits = [(h.ref, h.label, h.note, h.score) for h in wow.g.hits.values()]
    assert hits == [("quest:176", 'Wanted: "Hogger"', "quest text", 0.5)]
    wow.execute(search % "te")  # too short for a text search: no offer, no text hits
    wow.run_frames(10)
    assert not [h for h in wow.g.hits.values() if h.note == "quest text" or h.ref is None]
    assert errors(wow) == []


def test_rewards_show_money_xp_reputation_items_and_spell_or_say_none(wow: WowRuntime):
    """ "CLUCK!" showed no details; a quest page must say what the quest earns."""
    boot(wow)
    wow.execute(
        """
        local Logic = Bastians:GetModule('Quests').Logic
        local q = Logic.quest(62)
        q.rewards = { money = 125, xp = 480, rep = { { 72, 150 }, { 54, -25 } },
          spell = 13563, spellName = "Summon Chicken Egg", src = "classic" }
        Logic.quest(176).rewards = nil
        """
    )
    rows = list(sections(wow, "quest:62")["quests.rewards"].rows.values())
    got = [(strip(r.text), r.value) for r in rows]
    assert got[0] == ("Money", 125)
    assert got[1][0].startswith("Experience") and got[1][1] == 480
    assert got[2] == ("Reputation: Faction 72", "+150") and got[3] == (
        "Reputation: Faction 54",
        "-25",
    )
    assert rows[3].color is not None  # a loss is red
    # the side factions name themselves (Forever 23.10.2026: "Reputation: Faction 67")
    wow.execute(
        "Bastians:GetModule('Quests').Logic.quest(76).rewards = { rep = { { 67, 75 }, { 469, 75 } } }"
    )
    sides = [strip(r.text) for r in sections(wow, "quest:76")["quests.rewards"].rows.values()]
    assert "Reputation: Horde" in sides and "Reputation: Alliance" in sides
    assert got[4] == ("On completion: Summon Chicken Egg", None)
    assert all(r.note is None for r in rows)
    none = list(sections(wow, "quest:176")["quests.rewards"].rows.values())
    assert len(none) == 1 and strip(none[0].text).startswith("No reward known")
    assert errors(wow) == []


def test_hide_action_takes_a_quest_out_of_do_here_and_tags_it(wow: WowRuntime):
    """R3: the hide icon on a quest not in the log
    hides it from the ranking, the same icon unhides; the row tag says "(hidden)"; the set
    survives a reload per character."""
    boot(wow)
    assert "quests.hide" in actions(wow, "quest:76") and "quests.hide" not in actions(
        wow, "quest:176"
    )
    assert wow.eval("Bastians:RowTag('quest:76')") is None
    wow.execute("Bastians:RunAction('quests.hide', 'quest:76', { source = 'test' })")
    assert wow.eval("Bastians:GetModule('Quests').State.IsHidden(76)") is True
    assert wow.eval("Bastians:RowTag('quest:76')") == "hidden"
    assert wow.eval("Bastians:GetAction('quests.hide').active('quest:76')") is True
    assert wow.eval("Bastians:GetModule('Quests').db.char.hidden[76]") is True
    fresh = wow.reload()
    fresh.run_frames(5)
    assert fresh.eval("Bastians:GetModule('Quests').State.IsHidden(76)") is True
    fresh.execute("Bastians:RunAction('quests.hide', 'quest:76', { source = 'test' })")
    assert fresh.eval("Bastians:RowTag('quest:76')") is None
    assert fresh.eval("Bastians:GetModule('Quests').db.char.hidden[76]") is None
    assert errors(fresh) == []


def test_quest_places_follow_the_status_and_the_band_shows_giver_targets_hand_in(wow: WowRuntime):
    """R7: a quest's Locations() are the places of its next step (the
    giver before it is taken, the targets while open, the hand-in when complete; the client's
    waypoint fills in for missing targets); the actions Giver, Targets and Hand-in show each
    kind on the map and are greyed when no source has the place."""
    boot(wow, CORE, DATA, QUESTS, "Bastians_Map")
    REG = "Bastians:GetModule('Quests').Registrations"
    # not in the log (76): the giver; in the log and open (176, the fixture's log): the targets
    assert [p.kind for p in wow.eval("Bastians:Entity('quest:76'):Locations()").values()] == [
        "giver"
    ]
    assert wow.eval(f"{REG}.NextKind(76)") == "giver"
    assert wow.eval(f"{REG}.NextKind(176)") == "objective"
    assert all(
        p.kind == "objective" for p in wow.eval("Bastians:Entity('quest:176'):Locations()").values()
    )
    kinds = [p.kind for p in wow.eval("Bastians:Entity('quest:176'):AllLocations()").values()]
    assert "giver" in kinds and "objective" in kinds and "turnin" in kinds
    ids = actions(wow, "quest:176")
    assert {"quests.giver", "quests.targets", "quests.turnin"} <= set(ids)
    assert (
        wow.eval("Bastians:ActionEnabled('quests.giver', 'quest:176', { source = 'test' })") is True
    )
    assert (
        wow.eval("Bastians:ActionEnabled('quests.targets', 'quest:176', { source = 'test' })")
        is True
    )
    # complete: the hand-in
    wow.execute(
        "for _, e in ipairs(Mock.questLog) do if e.questID == 176 then e.complete = true end end"
    )
    wow.fire("QUEST_LOG_UPDATE")
    wow.advance(0.3)
    wow.run_frames(3)
    assert wow.eval(f"{REG}.NextKind(176)") == "turnin"
    assert [p.kind for p in wow.eval("Bastians:Entity('quest:176'):Locations()").values()] == [
        "turnin"
    ]
    # the Targets action shows the targets whatever the status: the waypoint lands on one
    wow.execute("Bastians:RunAction('quests.targets', 'quest:176', { source = 'test' })")
    wp = wow.eval("Bastians:GetModule('Map').Waypoints.Get()")
    assert wp is not None and wp.map == 1429
    targets = [
        (round(p.x, 2), round(p.y, 2))
        for p in wow.eval(f"{REG}.QuestPlaces('quest:176', 'objective')").values()
    ]
    assert (round(wp.x, 2), round(wp.y, 2)) in targets
    # a quest without targets in any source: Targets is listed but greyed
    assert wow.eval(f"#{REG}.QuestPlaces('quest:76', 'objective')") == 0
    assert (
        wow.eval("Bastians:ActionEnabled('quests.targets', 'quest:76', { source = 'test' })")
        is False
    )
    assert (
        wow.eval("Bastians:ActionEnabled('quests.giver', 'quest:76', { source = 'test' })") is True
    )
    assert errors(wow) == []


def test_which_reward_compares_the_choices_against_the_gear_and_follows_loads(wow: WowRuntime):
    """S7 (browser.md Should row): a quest with two choices or more gets the wide two-line block
    "Which reward": the client's kind, level and stats, the value, the worn item and the verdicts;
    an item the client has not cached is requested once and the block re-renders when it arrives;
    a gear change re-renders too; one choice or none: no block."""
    boot(wow)
    wow.execute(
        """
        Mock.items[1185] = { name = "Blood Saber", quality = 2, level = 7, class = "Weapon",
          subclass = "One-Handed Swords", equipLoc = "INVTYPE_WEAPON", sell = 200, stack = 1,
          icon = 135274, stats = { ITEM_MOD_STRENGTH_SHORT = 3, ITEM_MOD_STAMINA_SHORT = 2 } }
        Mock.items[2092] = { name = "Worn Dagger", quality = 1, level = 3, class = "Weapon",
          subclass = "Daggers", equipLoc = "INVTYPE_WEAPON", sell = 10, stack = 1, icon = 135641 }
        Mock.equipped[16] = 2092
        Mock.lateItems[2318] = { name = "Light Leather", quality = 1, level = 5,
          class = "Tradeskill", subclass = "Leather", equipLoc = "", sell = 25, stack = 20,
          icon = 134252 }
        """
    )
    hogger = sections(wow, "quest:176")
    assert list(hogger)[:6] == [
        "quests.status",
        "quests.givers",
        "quests.enders",
        "quests.rewards",
        "quests.choice",
        "quests.objectives",
    ]
    block = hogger["quests.choice"]["def"].block
    assert (block.wide, block.twoLine, block.limit) == (True, True, 6)
    rows = list(hogger["quests.choice"].rows.values())
    assert [(strip(r.title), r.meta, r.ref, r.value, r.valueKind) for r in rows] == [
        (
            "Blood Saber  best value, upgrade",  # both priced: the saber is worth more
            "One-Handed Swords, item level 7, +3 Strength, +2 Stamina, "
            "you wear Worn Dagger (item level 3), vendor price",
            "item:1185",
            200,
            "money",
        ),
        (
            "Light Leather x2",
            "not loaded by the client yet, vendor price",  # the pack's sell price (25 x 2)
            "item:2318",
            50,
            "money",
        ),
    ]
    assert rows[0].icon == 135274  # the client's icon; the entity's fallback for the other
    assert strip(rows[0].text).startswith("Blood Saber  best value, upgrade  One-Handed")  # cards
    requests = list(wow.eval("Mock.itemLoadRequests").values())
    assert set(requests) == {2318}  # asked (once by Quests, once by Data's icon provider)
    wow.eval("Bastians:GetDetailSections('quest:176')")  # a second build asks nothing new
    assert list(wow.eval("Mock.itemLoadRequests").values()) == requests
    # the load result arrives: the block says what the item is
    wow.advance(0.3)
    wow.run_frames(5)
    rows = list(sections(wow, "quest:176")["quests.choice"].rows.values())
    assert rows[1].meta == "Leather, vendor price"
    # the gear changes (the saber equipped): no upgrade any more
    wow.execute("Mock.equipped[16] = 1185")
    wow.fire("PLAYER_EQUIPMENT_CHANGED", 16, True)
    wow.advance(0.3)
    wow.run_frames(5)
    rows = list(sections(wow, "quest:176")["quests.choice"].rows.values())
    assert strip(rows[0].title) == "Blood Saber  best value, no upgrade"
    assert "you wear Blood Saber (item level 7)" in rows[0].meta
    # one choice or none: no block
    wow.execute(
        """
        local Logic = Bastians:GetModule('Quests').Logic
        Logic.quest(76).rewards = { choices = { { 1185, 1 } } }
        """
    )
    assert "quests.choice" not in sections(wow, "quest:76")
    assert "quests.choice" not in sections(wow, "quest:62")
    assert errors(wow) == []
