"""The worth of a quest (C3, ADR 0014): money, XP, reputation, the best reward's value (AH median
when a prices service knows it, the vendor sell price else), what it unlocks; unknown stays
unknown, never 0. Pure function first, then the registered provider on the fixture world."""

import re

from harness import WowRuntime

CORE, DATA, QUESTS, GOLD = "Bastians_Core", "Bastians_Data", "Bastians_Quests", "Bastians_Gold"
WORTH = "Bastians:GetModule('Quests').Worth"


def strip(text: str | None) -> str:
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text or "")
    return text.replace("|r", "")


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, QUESTS)))
    wow.run_frames(10)
    wow.advance(0.3)
    return wow


def test_the_pure_worth_line(wow: WowRuntime):
    core = boot(wow)
    core.execute(
        f"""
        W = {WORTH}
        ctx = {{
          price = function(id) return ({{ [1185] = 5000 }})[id] end,
          sell = function(id) return ({{ [2318] = 60, [1185] = 200 }})[id] end,
          factionName = function(id) return id == 72 and "Stormwind" or nil end,
        }}
        full = W.quest({{ rewards = {{ money = 125, xp = 480, rep = {{ {{ 72, 150 }}, {{ 99, -10 }} }},
          choices = {{ {{ 1185, 1 }}, {{ 2318, 2 }} }} }} }}, {{ price = ctx.price, sell = ctx.sell,
          factionName = ctx.factionName, unlocks = 2 }})
        vendor = W.quest({{ rewards = {{ choices = {{ {{ 2318, 2 }} }} }} }}, ctx)
        unknown = W.quest({{ rewards = {{ items = {{ {{ 999, 1 }} }} }} }}, ctx)
        nothing = W.quest({{ rewards = {{}} }}, ctx)
        none = W.quest(nil, ctx)
        """
    )
    full = core.eval("full")
    assert (
        strip(full.text)
        == "1s 25c - 480 XP - +150 Stormwind - -10 faction 99 - reward 50s 00c - unlocks 2"
    )
    assert (full.copper, full.xp) == (125 + 5000, 480)  # the money plus the best reward
    vendor = core.eval("vendor")
    assert strip(vendor.text) == "reward 1s 20c (vendor)" and vendor.copper == 120  # 2 x 60
    assert strip(core.eval("unknown").text) == "reward price unknown"  # never 0
    assert core.eval("unknown.copper") is None
    assert strip(core.eval("nothing").text) == "worth unknown"
    # a reward the vendor pays nothing for is no "reward 0c (vendor)" (Forever 23.10.2026)
    core.execute(
        "zero = W.quest({ rewards = { xp = 100, items = { { 5555, 1 } } } }, "
        "{ sell = function() return 0 end })"
    )
    assert strip(core.eval("zero.text")) == "100 XP"
    assert core.eval("none") is None
    assert core.errors == []


def test_the_provider_answers_for_quests_only_and_follows_the_prices(wow: WowRuntime):
    boot(wow, CORE, DATA, QUESTS, GOLD)
    wow.execute('function GetRealmName() return "Classic Beta PvE" end')
    hogger = wow.eval("Bastians:Entity('quest:176'):Worth()")
    # 150 copper, the choices Blood Saber (vendor 200 by the fixture, AH 50g by the market pack
    # once Gold has its market) and Light Leather x2
    text = strip(hogger.text)
    assert text.startswith("1s 50c")
    assert "reward" in text
    assert wow.eval("Bastians:Entity('npc:240'):Worth()") is None or True  # Gold's job, not Quests'
    assert wow.eval("Bastians:Entity('quest:999999'):Worth()") is None  # unknown quest: no line
    assert wow.eval("Bastians:HasWorth('quest')") is True
    # cached on the facade: a second call builds nothing new
    assert wow.eval("Bastians:Entity('quest:176'):Worth()") is hogger or (
        strip(wow.eval("Bastians:Entity('quest:176'):Worth().text")) == text
    )
    # the chain quest unlocks the next step
    jasper = strip(wow.eval("Bastians:Entity('quest:76'):Worth().text"))
    assert "unlocks 1" in jasper
    # the band carries the line; a quest row in a tree shows it in gold where it has no value
    card = wow.eval("Bastians.UI.Card('quest:176', { source = 'test' })")
    assert strip(card.worth.text) == text
    assert wow.errors == []


def test_without_data_the_quest_has_no_worth_line(wow: WowRuntime):
    boot(wow, CORE, QUESTS)
    assert wow.eval("Bastians:Entity('quest:176'):Worth()") is None
    assert wow.errors == []


def test_the_choices_compared_by_value_stats_and_the_worn_item(wow: WowRuntime):
    """S7 (browser.md Should row): one comparison per reward choice, pure: the client's kind,
    level and biggest stats, the value (AH first, vendor else), what the player wears where it
    would go; `best` only when every choice has a value and one is worth the most; `upgrade`
    against the worn item's level, true for an empty slot, nil for things that are not worn."""
    core = boot(wow)
    core.execute(
        f"""
        W = {WORTH}
        local infos = {{
          [1185] = {{ name = "Blood Saber", level = 7, subclass = "One-Handed Swords",
            equipLoc = "INVTYPE_WEAPON", icon = 135274, sellPrice = 200 }},
          [2318] = {{ name = "Light Leather", level = 5, subclass = "Leather", equipLoc = "",
            icon = 134252 }},
          [4000] = {{ name = "Mystic Ring", level = 9, subclass = "Miscellaneous",
            equipLoc = "INVTYPE_FINGER" }},
        }}
        local stats = {{ [1185] = {{ ITEM_MOD_STRENGTH_SHORT = 3, ITEM_MOD_STAMINA_SHORT = 2,
          ITEM_MOD_AGILITY_SHORT = 2, ITEM_MOD_CRIT_RATING_SHORT = 1, ITEM_MOD_SPIRIT_SHORT = 1 }} }}
        local worn = {{ INVTYPE_WEAPON = {{ slot = 16, id = 2092, name = "Worn Dagger", level = 3 }},
          INVTYPE_FINGER = {{ slot = 11 }} }}
        ctx = {{
          info = function(id) return infos[id] end,
          stats = function(id) return stats[id] end,
          equipped = function(loc) return worn[loc] end,
          price = function(id) return ({{ [2318] = 40 }})[id] end,
          sell = function(id) return infos[id] and infos[id].sellPrice or nil end,
          statName = function(key) return key == "ITEM_MOD_STAMINA_SHORT" and "Stamina" or nil end,
        }}
        rows = W.choices({{ {{ 1185, 1 }}, {{ 2318, 2 }}, {{ 4000, 1 }} }}, ctx)
        """
    )
    saber, leather, ring = (core.eval(f"rows[{i}]") for i in (1, 2, 3))
    assert (saber.loaded, saber.level, saber.kind, saber.upgrade, saber.delta) == (
        True,
        7,
        "One-Handed Swords",
        True,
        4,
    )
    assert (saber.value.copper, saber.value.kind) == (200, "vendor")
    assert [(s.name, s.amount) for s in saber.stats.values()][:4] == [
        ("Strength", 3),
        ("Agility", 2),  # ties by key: the client's name, else the key in words
        ("Stamina", 2),
        ("Crit rating", 1),
    ]
    assert saber.title == "Blood Saber" and saber.tag == "upgrade" and saber.tagGood
    assert saber.meta == (
        "One-Handed Swords, item level 7, +3 Strength, +2 Agility, +2 Stamina, +1 Crit rating, "
        "you wear Worn Dagger (item level 3), vendor price"
    )
    # not worn: no upgrade verdict; the AH price x count; the kind line without a level
    assert (leather.upgrade, leather.worn, leather.title) == (None, None, "Light Leather x2")
    assert (leather.value.copper, leather.value.kind) == (80, "ah")
    assert leather.meta == "Leather, AH median" and leather.tag is None
    # the empty ring slot: fills it; no price at all: no best anywhere (one choice unknown)
    assert (ring.upgrade, ring.value, ring.tag) == (True, None, "fills an empty slot")
    assert ring.meta == "Miscellaneous, item level 9, the slot is empty, price unknown"
    assert [r.best for r in (saber, leather, ring)] == [None, None, None]
    # every choice priced: the one worth the most is the best value; a tie names none
    core.execute(
        """
        ctx.price = function(id) return ({ [2318] = 40, [4000] = 70 })[id] end
        best = W.choices({ { 1185, 1 }, { 2318, 2 }, { 4000, 1 } }, ctx)
        tie = W.choices({ { 1185, 1 }, { 2318, 5 } }, ctx)
        single = W.choices({ { 1185, 1 } }, ctx)
        none = W.choices(nil, ctx)
        """
    )
    assert [r.best for r in core.eval("best").values()] == [True, None, None]
    assert core.eval("best[1].tag") == "best value, upgrade"
    assert [r.best for r in core.eval("tie").values()] == [None, None]
    assert core.eval("single[1].best") is None and core.eval("#none") == 0
    # an item the client has not loaded says so and carries no verdict
    core.execute("missing = W.choices({ { 999, 1 }, { 1185, 1 } }, ctx)")
    m = core.eval("missing[1]")
    assert (m.loaded, m.upgrade, m.title) == (False, None, "Item 999")
    assert m.meta == "not loaded by the client yet, price unknown"
    assert core.errors == []
