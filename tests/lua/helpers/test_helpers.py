"""Bastian's Helpers (helpers.md): the merchant, the mailbox, quest givers, tooltips, warnings and
the session panel; nothing of it goes to the chat."""

import re

from harness import WowRuntime

CORE, DATA, BROWSER, HELPERS = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Browser",
    "Bastians_Helpers",
)
H = "Bastians:GetModule('Helpers').Helpers"
P = "Bastians:GetModule('Helpers').db.profile"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.execute(
        """Mock.money = 10000
        Mock.items[3300] = { name = "Rabbit's Foot", quality = 0, level = 1, sell = 27, stack = 10, icon = 1 }
        Mock.items[3301] = { name = "Broken Fang", quality = 0, level = 1, sell = 5, stack = 10, icon = 1 }
        Mock.items[1185] = { name = "Blood Saber", quality = 2, level = 7, sell = 300, stack = 1,
          equipLoc = "INVTYPE_WEAPON", icon = 1 }
        Mock.bagSlots[0] = { slots = 16, { itemID = 3300, count = 4 }, { itemID = 2589, count = 20 },
          { itemID = 3301, count = 2 } }"""
    )
    wow.start(*(addons or (CORE, HELPERS)))
    wow.run_frames(5)
    wow.execute("Mock.chat = {}")  # Core's own login lines: what follows must stay out of the chat
    return wow


def strip(text: str | None) -> str | None:
    if text is None:
        return None
    return re.sub(r"\|c[0-9a-fA-F]{8}", "", text).replace("|r", "")


def notice(wow: WowRuntime) -> str | None:
    return strip(wow.eval(f"{H}.lastNotice"))


def test_the_model_decides_without_the_game(core: WowRuntime):
    core.start(HELPERS)
    core.execute(f"M = {H}.Model")
    junk = core.eval(
        """M.Junk({ { bag = 0, slot = 1, itemID = 7, quality = 0, count = 3 },
          { bag = 0, slot = 2, itemID = 8, quality = 0, noValue = true },
          { bag = 0, slot = 3, itemID = 9, quality = 1 },
          { bag = 0, slot = 4, itemID = 10, quality = 0 } }, { [10] = true }, function(id) return 5 end)"""
    )
    assert [(j.itemID, j.value) for j in junk.values()] == [(7, 15)]  # never-sell and no value stay
    assert (
        core.eval("M.Repair({ canRepair = true, cost = 500, guild = true }, 100, true)") == "guild"
    )
    assert (
        core.eval(
            "M.Repair({ canRepair = true, cost = 500, guild = true, guildMoney = 10 }, 600, true)"
        )
        == "self"
    )
    assert core.eval("M.Repair({ canRepair = true, cost = 500 }, 100, false)") == "short"
    assert core.eval("M.Repair({ canRepair = true, cost = 0 }, 100, false)") is None
    buys = core.eval(
        """M.Restock({ [5] = 30 }, { [5] = 5 },
          { { index = 2, itemID = 5, stack = 5, price = 100, numAvailable = -1, maxStack = 10 } }, 450)"""
    )
    # 25 wanted in stacks of 5 = 5 stacks, the money pays 4, two units of stacks per purchase
    assert [(b.index, b.count, b.cost) for b in buys.values()] == [(2, 10, 200), (2, 10, 200)]
    undo = core.eval(
        """M.Undo({ { itemID = 7, count = 3 } },
          { { index = 1, itemID = 7, count = 3 }, { index = 2, itemID = 8, count = 1 }, { index = 3, itemID = 7, count = 3 } })"""
    )
    assert list(undo.values()) == [3]  # the latest sale of it, once
    pick = core.eval(
        "M.NextMail({ { index = 1, cod = 50, money = 9 }, { index = 2, items = 2 } }, 0)"
    )
    assert pick == (None, "full")  # the cash-on-delivery mail is passed, the bags take nothing
    assert core.eval("M.NextMail({ { index = 1, cod = 50 } }, 5)") == (None, "done")
    assert core.eval("M.NextMail({ { index = 1, money = 9, items = 1 } }, 0).what") == "money"
    names = core.eval(
        """M.Recipients({ me = { name = "Me", realm = "R", faction = "A" },
          b = { name = "Bob", realm = "R", faction = "A" }, o = { name = "Orc", realm = "R", faction = "H" },
          a = { name = "Ann", realm = "R", faction = "A" } }, "me", { "bob", "Zed", "Me" }, 10)"""
    )
    assert list(names.values()) == [
        "Ann",
        "Bob",
        "Zed",
    ]  # alts by name, then recent ones not yet named
    assert list(core.eval("M.Remember({ 'A', 'B' }, 'b', 8)").values()) == ["b", "A"]
    assert (
        core.eval(
            "select(2, M.QuestPick({ { index = 1, complete = false }, { index = 2, complete = true } }, {}, 'index'))"
        )
        == 2
    )
    assert core.eval(
        "M.BestChoice({ { index = 1, itemID = 7 }, { index = 2, itemID = 8, count = 2 } }, "
        "function(id) return id == 7 and 10 or 6 end)"
    ) == (2, 12)
    assert core.eval("M.BestChoice({ { index = 1, itemID = 7 } }, function() return nil end)") == (
        None,
        None,
    )
    assert (
        core.eval(
            "M.XPGain({ xp = 900, max = 1000, level = 4 }, { xp = 50, max = 1400, level = 5 })"
        )
        == 150
    )
    assert core.eval("M.PerHour(100, 30)") is None and core.eval("M.PerHour(100, 1800)") == 200
    assert (
        core.eval("M.Crossed(0.5, 0.1, 0.2)") is True
        and core.eval("M.Crossed(0.15, 0.1, 0.2)") is False
    )
    assert core.errors == []


def test_at_a_merchant_junk_is_sold_with_undo_and_the_gear_repaired(wow: WowRuntime):
    boot(wow)
    wow.execute(
        "Mock.repair = { cost = 500, can = true, merchant = true, guild = true, guildMoney = 9999 }"
    )
    wow.execute("Mock.OpenMerchant()")
    wow.advance(0.5)
    assert wow.eval("Mock.repaired[1].guild") is False  # the guild switch is off by default
    assert wow.eval("Mock.bagSlots[0][1]") is None and wow.eval("Mock.bagSlots[0][3]") is None
    assert wow.eval("Mock.bagSlots[0][2].itemID") == 2589  # white cloth stays
    assert notice(wow).startswith("Sold 2 items for 1")  # 4 x 27 + 2 x 5 copper
    strip = "BastiansHelpersNotice"
    assert wow.eval(f"{strip}.button.label:GetText()") == "Undo"
    wow.execute(f"{strip}.button:Click()")
    assert list(wow.eval("Mock.boughtBack").values()) == [3301, 3300]
    assert notice(wow) == "Bought back 2 items"
    assert wow.chat == []
    assert wow.errors == []


def test_never_sell_the_pause_key_and_the_guild_repair(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{H}.NeverSell(3300, true); {P}.guildRepair = true")
    wow.execute(
        "Mock.repair = { cost = 500, can = true, merchant = true, guild = true, guildMoney = 9999 }"
    )
    wow.execute("Mock.OpenMerchant()")
    wow.advance(0.5)
    assert wow.eval("Mock.bagSlots[0][1].itemID") == 3300  # on the never-sell list
    assert wow.eval("Mock.bagSlots[0][3]") is None
    assert wow.eval("Mock.repaired[1].guild") is True
    assert notice(wow) is not None
    wow.execute(
        "Mock.CloseMerchant(); Mock.shift = true; Mock.bagSlots[0][3] = { itemID = 3301, count = 1 }"
    )
    wow.execute("Mock.repair = { cost = 500, can = true, merchant = true }")
    wow.execute("Mock.OpenMerchant()")
    wow.advance(0.5)
    assert wow.eval("Mock.bagSlots[0][3].itemID") == 3301  # the pause key held: nothing happens
    assert len(wow.eval("Mock.repaired")) == 1
    assert wow.errors == []


def test_the_restock_list_and_alt_click(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{P}.sellJunk = false; Mock.bags[2589] = 5")
    wow.execute(f"{H}.SetRestock(2589, 30)")
    wow.execute("Mock.OpenMerchant()")
    bought = [list(b.values()) for b in wow.eval("Mock.bought").values()]
    assert bought == [[1, 40]]  # 25 wanted, sold in twenties
    assert notice(wow) == "Restocked Linen Cloth x40 for 5s 20c"
    wow.execute("Mock.bought = {}; Mock.alt = true")
    wow.execute(
        "MerchantItemButton_OnModifiedClick({ GetID = function() return 1 end }, 'LeftButton')"
    )
    assert [list(b.values()) for b in wow.eval("Mock.bought").values()] == [
        [1, 400]
    ]  # one full purchase
    assert wow.errors == []


def test_the_item_actions_set_the_lists(wow: WowRuntime):
    boot(wow, CORE, DATA, BROWSER, HELPERS)
    ids = [a.id for a in wow.eval("Bastians:GetActions('item:2589', { source = 'test' })").values()]
    assert (
        "helpers.neversell" in ids and "helpers.restock" in ids and "helpers.allowsell" not in ids
    )
    wow.execute("Bastians:RunAction('helpers.restock', 'item:2589', { source = 'test' })")
    wow.execute("Bastians:RunAction('helpers.neversell', 'item:2589', { source = 'test' })")
    assert wow.eval(f"{H}.Restock(2589)") == 20  # one stack
    sections = {s.id: s for s in wow.eval("Bastians:GetDetailSections('item:2589')").values()}
    texts = [r.text for r in sections["helpers.item"].rows.values()]
    assert texts == ["Never sold to a vendor", "Restocked at vendors to"]
    wow.execute("SlashCmdList.BASTIANSHELPERS('restock 2589 0')")
    assert wow.eval(f"{H}.Restock(2589)") is None
    assert wow.chat == []
    assert wow.errors == []


def test_take_all_leaves_cash_on_delivery_mail(wow: WowRuntime):
    boot(wow)
    wow.execute(
        """Mock.inbox = { { money = 500 }, { items = { { 2589, 5 } } }, { cod = 100, items = { { 2318, 1 } } },
          { money = 25, items = { { 2318, 2 } } } }"""
    )
    wow.execute("Mock.OpenMailbox()")
    wow.execute(f"{H}.Mail.button:Click()")
    for _ in range(10):
        wow.advance(0.6)
        wow.run_frames(2)
    assert len(wow.eval("Mock.inbox")) == 1 and wow.eval("Mock.inbox[1].cod") == 100
    assert wow.eval("Mock.money") == 10525
    assert notice(wow) == "Took 5s 25c and 2 items from 3 mails; 1 cash-on-delivery mails left"
    assert wow.chat == []
    assert wow.errors == []


def test_send_to_and_the_last_recipient(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"""{H}.Global().characters['Bankalt-Mock Realm'] = {{ name = "Bankalt", realm = "Mock Realm",
          faction = "Alliance" }}"""
    )
    wow.execute("Mock.OpenMailbox()")
    assert wow.eval("BastiansHelpersSendTo:IsShown()") is True
    assert list(wow.eval(f"{H}.Mail.Names()").values()) == ["Bankalt"]
    wow.execute("BastiansHelpersSendTo.buttons[1]:Click()")
    assert wow.eval("SendMailNameEditBox:GetText()") == "Bankalt"
    wow.execute('SendMail("Friendly", "Hi", "")')
    assert list(wow.eval(f"{H}.Char().recent").values()) == ["Friendly"]
    wow.execute("Mock.Fire('MAIL_CLOSED'); SendMailNameEditBox:SetText('')")
    wow.execute("Mock.OpenMailbox()")
    wow.advance(0.2)
    assert wow.eval("SendMailNameEditBox:GetText()") == "Friendly"
    assert list(wow.eval(f"{H}.Mail.Names()").values()) == ["Bankalt", "Friendly"]
    assert wow.errors == []


def test_quest_givers_are_left_alone_by_default(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f"{P}.autoQuest") is False and wow.eval(f"{P}.skipGossip") is False
    wow.execute(
        """Mock.gossip = { active = {}, available = { { questID = 176, title = "Wanted" } },
          options = { { gossipOptionID = 9, name = "Fly" } } }
        Mock.questFrame.completable = true"""
    )
    for event in ("GOSSIP_SHOW", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE"):
        wow.execute(f"Mock.Fire('{event}')")
    assert list(wow.eval("Mock.npcCalls").values()) == []
    assert wow.errors == []


def test_accept_and_hand_in_when_switched_on(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{P}.autoQuest = true")
    wow.execute(
        """Mock.gossip = { active = { { questID = 7, title = "Open", isComplete = false },
          { questID = 8, title = "Done", isComplete = true } }, available = { { questID = 176 } }, options = {} }"""
    )
    wow.execute("Mock.Fire('GOSSIP_SHOW')")
    wow.execute("Mock.Fire('QUEST_DETAIL')")
    wow.execute("Mock.questFrame.completable = true; Mock.Fire('QUEST_PROGRESS')")
    wow.execute("Mock.questFrame.choices = { { 1185, 1 } }; Mock.Fire('QUEST_COMPLETE')")
    calls = list(wow.eval("Mock.npcCalls").values())
    assert calls == ["gossip active 8", "accept", "continue", "reward 1"]  # the finished one first
    # a choice is never taken without the click
    wow.execute("Mock.npcCalls = {}; Mock.questFrame.choices = { { 2589, 1 }, { 1185, 1 } }")
    wow.execute("Mock.Fire('QUEST_COMPLETE')")
    assert list(wow.eval("Mock.npcCalls").values()) == []
    assert notice(wow) == "Choose your reward: Blood Saber pays the most at a vendor (3s 00c)"
    wow.execute("BastiansHelpersNotice.button:Click()")
    assert list(wow.eval("Mock.npcCalls").values()) == ["reward 2"]
    # a hand-in that costs money stays the player's; the greeting list picks too
    wow.execute("Mock.npcCalls = {}; Mock.questFrame.money = 100; Mock.Fire('QUEST_PROGRESS')")
    wow.execute(
        "Mock.greeting = { active = {}, available = { { title = 'A' } } }; Mock.Fire('QUEST_GREETING')"
    )
    assert list(wow.eval("Mock.npcCalls").values()) == ["greeting available 1"]
    assert wow.chat == []
    assert wow.errors == []


def test_skip_gossip_and_share_quests(wow: WowRuntime):
    boot(wow)
    wow.execute(
        "Mock.gossip = { active = {}, available = {}, options = { { gossipOptionID = 9, name = 'Fly' } } }"
    )
    wow.execute("Mock.Fire('GOSSIP_SHOW')")
    assert list(wow.eval("Mock.npcCalls").values()) == []  # off by default
    wow.execute(f"{P}.skipGossip = true; Mock.Fire('GOSSIP_SHOW')")
    assert list(wow.eval("Mock.npcCalls").values()) == ["gossip option 9"]
    wow.execute("Mock.npcCalls = {}")
    wow.execute(
        "Mock.gossip.options[2] = { gossipOptionID = 10, name = 'Bank' }; Mock.Fire('GOSSIP_SHOW')"
    )
    assert list(wow.eval("Mock.npcCalls").values()) == []  # two options: the player chooses
    wow.execute("Mock.pushable[176] = true; Mock.Fire('QUEST_ACCEPTED', 176)")
    assert list(wow.eval("Mock.npcCalls").values()) == []  # not in a group
    wow.execute("Mock.groupSize = 2; Mock.Fire('QUEST_ACCEPTED', 176)")
    assert list(wow.eval("Mock.npcCalls").values()) == ["push 176"]
    assert wow.errors == []


def test_tooltips_show_ids_and_the_item_level(wow: WowRuntime):
    boot(wow)
    lines = [ln.left for ln in wow.eval("Mock.Tooltip(Enum.TooltipDataType.Item, 1185)").values()]
    assert lines[-2:] == ["Item level 7", "Item ID 1185"]
    lines = [ln.left for ln in wow.eval("Mock.Tooltip(Enum.TooltipDataType.Item, 2589)").values()]
    assert "Item ID 2589" in lines and not any(str(t).startswith("Item level") for t in lines)
    lines = [ln.left for ln in wow.eval("Mock.Tooltip(Enum.TooltipDataType.Unit, 448)").values()]
    assert "NPC ID 448" in lines
    wow.execute(f"{P}.tooltipIDs = false")
    lines = [ln.left for ln in wow.eval("Mock.Tooltip(Enum.TooltipDataType.Item, 3300)").values()]
    assert not any(str(t).startswith("Item ID") for t in lines)
    assert wow.errors == []


def test_warnings_and_the_session_panel(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.durability[16] = { 10, 100 }; Mock.Fire('UPDATE_INVENTORY_DURABILITY')")
    assert notice(wow) == "Your gear is at 10%: time for a repair"
    wow.execute(f"{H}.lastNotice = nil; Mock.Fire('UPDATE_INVENTORY_DURABILITY')")
    assert notice(wow) is None  # once per drop
    wow.execute("Mock.bagSlots[0].slots = 4; Mock.bagSlots[0][4] = { itemID = 3300 }")
    wow.execute("Mock.Fire('BAG_UPDATE_DELAYED')")
    assert notice(wow) == "Your bags are full"
    wow.execute("Mock.money = 13600")
    wow.advance(1800)
    assert wow.eval("SlashCmdList.BASTIANSHELPERS('')") is None  # the panel opens (no chat line)
    assert wow.eval("BastiansHelpersPanel:IsShown()") is True
    lines = {ln.label: strip(ln.value) for ln in wow.eval(f"{H}.Info.Lines()").values()}
    assert lines["This session"] == "30 min"
    assert lines["Money"] == "36s 00c  (72s 00c per hour)"
    assert lines["Durability"] == "10%" and lines["Free bag slots"] == "0 / 4"
    assert wow.chat == []
    assert wow.errors == []


def test_notices_go_to_the_addon_chat_tab_too(wow: WowRuntime):
    boot(wow)
    wow.execute(
        "Mock.heard = {}; Bastians:GetModule('Helpers'):On('BASTIANS_NOTICE', "
        "function(_, _, text, who) Mock.heard[#Mock.heard + 1] = who .. ': ' .. text end)"
    )
    wow.execute("Mock.durability[16] = { 10, 100 }; Mock.Fire('UPDATE_INVENTORY_DURABILITY')")
    assert wow.chat == []  # without an "Addons" tab the normal chat stays untouched
    assert list(wow.eval("Mock.heard").values()) == [
        "Helpers: Your gear is at 10%: time for a repair"
    ]
    wow.execute("Mock.AddChatTab(3, 'Addons')")
    wow.execute("Mock.durability[16] = { 100, 100 }; Mock.Fire('UPDATE_INVENTORY_DURABILITY')")
    wow.execute("Mock.durability[16] = { 5, 100 }; Mock.Fire('UPDATE_INVENTORY_DURABILITY')")
    lines = [strip(t) for t in wow.eval("Mock.chatTabs.Addons").values()]
    assert lines == ["Helpers: Your gear is at 5%: time for a repair"]
    assert wow.chat == []
    assert wow.errors == []


def test_switched_off_the_helpers_do_nothing(wow: WowRuntime):
    boot(wow)
    wow.execute("Bastians:GetModule('Helpers'):Disable()")
    wow.execute("Mock.OpenMerchant()")
    wow.advance(0.5)
    assert wow.eval("Mock.bagSlots[0][1].itemID") == 3300
    lines = [ln.left for ln in wow.eval("Mock.Tooltip(Enum.TooltipDataType.Item, 2589)").values()]
    assert not any(str(t).startswith("Item ID") for t in lines)
    wow.execute("Bastians:GetModule('Helpers'):Enable(); Mock.CloseMerchant(); Mock.OpenMerchant()")
    wow.advance(0.5)
    assert wow.eval("Mock.bagSlots[0][1]") is None
    assert wow.errors == []


def test_a_restock_says_where_the_item_is_cheaper(wow: WowRuntime):
    """Issue #15: the packs' vendor lists (Data's npc.bySoldItem) name a vendor that sells the
    restocked item for less; the same price or an unknown stack says nothing. Helpers never loads
    the packs for it: here Quests does."""
    boot(wow, CORE, DATA, "Bastians_Quests", HELPERS)
    m = f"{H}.Model"
    best = wow.eval(
        f"""{m}.CheaperVendor(20, {{ {{ npc = 1, name = "B", price = 260, stack = 20 }},
          {{ npc = 2, name = "A", price = 13, stack = 1 }}, {{ npc = 3, name = "C", price = 1 }},
          {{ npc = 4, name = "D", price = 400, stack = 20 }} }})"""
    )
    assert (best.npc, best.name, best.unit) == (2, "A", 13)  # a tie goes by name; no stack, no unit
    assert wow.eval(f"{m}.CheaperVendor(13, {{ {{ npc = 1, price = 260, stack = 20 }} }})") is None
    assert wow.eval(f"{m}.CheaperVendor(nil, {{ {{ npc = 1, price = 1, stack = 1 }} }})") is None
    # this merchant asks 20c a cloth; the fixture's vendor in Elwynn sells twenty for 260
    wow.execute(f"{P}.sellJunk = false; Mock.bags[2589] = 0; Mock.merchant[1].price = 400")
    wow.execute(f"{H}.SetRestock(2589, 20)")
    wow.execute("Mock.OpenMerchant()")
    text = notice(wow)
    vendor = wow.eval("Bastians:Entity('npc:54'):Name()")
    assert text == (
        f"Restocked Linen Cloth x20 for 4s 00c. Linen Cloth is cheaper at {vendor} (Elwynn Forest): "
        "13c each, here 20c."
    )
    # at the same price nothing more is said
    wow.execute("Mock.CloseMerchant(); Mock.bags[2589] = 0; Mock.merchant[1].price = 260")
    wow.execute("Mock.OpenMerchant()")
    assert notice(wow) == "Restocked Linen Cloth x20 for 2s 60c"
    assert wow.errors == []


def test_mail_rules_put_the_kind_into_a_mail_the_player_sends(wow: WowRuntime):
    """#18: "herbs go to my alchemist": a rule per kind (class and subclass), a button per rule
    with stacks in the bags beside the send tab; it fills recipient, subject and attachments,
    never a bound stack, never a mail to me; the player presses Send."""
    wow.execute(
        """Mock.items[2453] = { name = "Bruiseweed", quality = 1, level = 1, sell = 10, stack = 20,
          icon = 1, classID = 7, subclassID = 9 }
        Mock.items[765] = { name = "Silverleaf", quality = 1, level = 1, sell = 5, stack = 20,
          icon = 1, classID = 7, subclassID = 9 }"""
    )
    boot(wow)
    wow.execute(
        """Mock.bagSlots[1] = { slots = 16, { itemID = 2453, count = 7 }, { itemID = 765, count = 3,
          bound = true }, { itemID = 765, count = 12 } }
        Mock.Fire('BAG_UPDATE_DELAYED')"""
    )
    edits = wow.eval(
        "(function() local n = 0 for _, o in ipairs(Bastians:GetModule('Helpers').options) do "
        "if o.type == 'edit' then n = n + 1 end end return n end)()"
    )
    assert edits == 8  # one row per kind
    wow.execute(f"{H}.SetMailRule('herb', '  Alchemist ')")
    assert wow.eval(f"{H}.MailRulesText()") == "Herbs go to Alchemist"
    wow.execute("Mock.OpenMailbox()")
    batches = wow.eval(f"{H}.Mail.Batches()")
    assert len(batches) == 1 and batches[1].to == "Alchemist" and len(batches[1].slots) == 2
    assert batches[1].count == 19  # the bound stack stays
    button = "BastiansHelpersSendTo.rules[1]"
    assert wow.eval(f"{button}:IsShown()") is True
    wow.execute(f"{button}:Click()")
    assert wow.eval("SendMailNameEditBox:GetText()") == "Alchemist"
    assert wow.eval("SendMailSubjectEditBox:GetText()") == "Herbs"
    sent = sorted(
        wow.eval(f"GetSendMailItem({i})")[1] for i in (1, 2) if wow.eval(f"GetSendMailItem({i})")
    )
    assert sent == [765, 2453]
    assert notice(wow) == "Herbs for Alchemist: 2 stacks in the mail, press Send."
    # a rule naming me sends nothing; an empty name removes the rule
    wow.execute(f"{H}.SetMailRule('herb', UnitName('player'))")
    assert len(wow.eval(f"{H}.Mail.Batches()")) == 0
    wow.execute(f"{H}.SetMailRule('herb', '')")
    assert wow.eval(f"{H}.MailRulesText()") is None
    assert wow.chat == [] and wow.errors == []


def test_a_rare_creature_targeted_or_under_the_mouse_is_named_once(wow: WowRuntime):
    """helpers.md "Warnings", the rare alert (catalog review A3.3, 07.11.2026)."""
    boot(wow, CORE, DATA, HELPERS)
    guid = "Creature-0-1-0-1-%d-0000000001"
    wow.execute(f"Mock.guids = {{ target = '{guid % 1260}' }}; Mock.Fire('PLAYER_TARGET_CHANGED')")
    assert notice(wow) == "Rare: Leprithus"
    assert wow.eval("BastiansHelpersNotice.button:IsShown()") is False  # no Map: no button
    wow.execute(f"{H}.lastNotice = nil; Mock.Fire('PLAYER_TARGET_CHANGED')")
    assert notice(wow) is None  # once per creature and session
    wow.execute(f"Mock.guids.mouseover = '{guid % 448}'; Mock.Fire('UPDATE_MOUSEOVER_UNIT')")
    assert notice(wow) is None  # Hogger is elite, not rare
    wow.execute("Mock.guids.target = 'Player-1-00000002'; Mock.Fire('PLAYER_TARGET_CHANGED')")
    assert notice(wow) is None
    assert wow.eval(f"{H}.Model.IsRare({{ 'elite', 'rareelite' }})") is True
    assert wow.eval(f"{H}.Model.IsRare('rare')") is True
    assert wow.eval(f"{H}.Model.IsRare(nil)") is False
    assert wow.errors == []


def test_the_rare_alert_offers_the_map_and_follows_its_setting(wow: WowRuntime):
    boot(wow, CORE, DATA, "Bastians_Map", HELPERS)
    wow.execute(f"{P}.warnRares = false")
    wow.execute("Mock.guids = { mouseover = 'Creature-0-1-0-1-1260-0000000001' }")
    wow.execute("Mock.Fire('UPDATE_MOUSEOVER_UNIT')")
    assert notice(wow) is None  # the setting off: nothing, and the creature is not used up
    wow.execute(f"{P}.warnRares = true; Mock.Fire('UPDATE_MOUSEOVER_UNIT')")
    assert notice(wow) == "Rare: Leprithus"
    assert wow.eval("BastiansHelpersNotice.button.label:GetText()") == "Map"
    wow.execute("BastiansHelpersNotice.button:Click()")
    assert wow.eval("Bastians:GetModule('Map').Map.IsShown()") is True
    assert wow.errors == []


def test_a_send_to_button_says_who_it_is(wow: WowRuntime):
    """ "the mail buttons should state the class, level and place"."""
    boot(wow)
    wow.execute(
        f"""{H}.Global().characters['Bankalt-Mock Realm'] = {{ name = "Bankalt", realm = "Mock Realm",
          faction = "Alliance", className = "Mage", level = 4, zone = "Stormwind City" }}
        {H}.Global().characters['Oldalt-Mock Realm'] = {{ name = "Oldalt", realm = "Mock Realm",
          faction = "Alliance" }}"""
    )
    wow.execute("Mock.OpenMailbox()")
    first = "BastiansHelpersSendTo.buttons[1]"
    assert wow.eval(f"{first}.label:GetText()") == "Bankalt"
    assert wow.eval(f"{first}.detail:GetText()") == "Level 4 Mage, Stormwind City"
    assert wow.eval(f"{first}:GetHeight()") == 34
    # recorded before the level and the place were: the name alone, and nothing made up
    second = "BastiansHelpersSendTo.buttons[2]"
    assert wow.eval(f"{second}.label:GetText()") == "Oldalt"
    assert wow.eval(f"{second}.detail:IsShown()") is False
    assert wow.eval(f"{second}:GetHeight()") < 34
    assert wow.errors == []


def test_describe_says_only_what_is_known(wow: WowRuntime):
    boot(wow)
    d = f"{H}.Model.Describe"
    assert (
        wow.eval(f"{d}({{ level = 4, zone = 'Goldshire' }}, 'Mage')") == "Level 4 Mage, Goldshire"
    )
    assert wow.eval(f"{d}({{ level = 4 }})") == "Level 4"
    assert wow.eval(f"{d}({{ zone = 'Goldshire' }})") == "Goldshire"
    assert wow.eval(f"{d}({{}})") is None
    assert wow.eval(f"{d}(nil, 'Mage')") is None


def test_the_record_follows_the_level_and_the_zone(wow: WowRuntime):
    boot(wow)
    me = f"{H}.Global().characters[{H}.Key()]"
    wow.execute("Mock.Fire('PLAYER_LEVEL_UP', 37)")
    assert wow.eval(f"{me}.level") == 37
    zone = wow.eval("GetZoneText()")
    assert wow.eval(f"{me}.zone") == zone
    wow.execute("GetZoneText = function() return '' end; Mock.Fire('ZONE_CHANGED_NEW_AREA')")
    assert wow.eval(f"{me}.zone") == zone  # a zone not known yet keeps the last one
    assert wow.errors == []


def test_a_send_to_button_writes_the_whole_name(wow: WowRuntime):
    """ "you need the surname now, first name alone will not send it"."""
    boot(wow)
    wow.execute(
        f"""{H}.Global().characters['Bankalt-Mock Realm'] = {{ name = "Bankalt", full = "Bankalt Farmadr",
          realm = "Mock Realm", faction = "Alliance" }}"""
    )
    wow.execute("Mock.OpenMailbox()")
    wow.execute("BastiansHelpersSendTo.buttons[1]:Click()")
    assert wow.eval("BastiansHelpersSendTo.buttons[1].label:GetText()") == "Bankalt"
    assert wow.eval("SendMailNameEditBox:GetText()") == "Bankalt Farmadr"
    # sent to in full, the recent list does not name the alt a second time
    wow.execute('SendMail("Bankalt Farmadr", "Hi", "")')
    assert list(wow.eval(f"{H}.Mail.Names()").values()) == ["Bankalt"]
    assert wow.errors == []


def test_my_record_keeps_the_surname(wow: WowRuntime):
    boot(wow)
    me = f"{H}.Global().characters[{H}.Key()]"
    assert wow.eval(f"{me}.full") == wow.eval(f"{me}.name")  # no second value: the name is whole
    wow.execute(
        """UnitName = function() return "Arnhild", "Farmadr" end
        Mock.Fire('ZONE_CHANGED_NEW_AREA')"""
    )
    assert wow.eval(f"{me}.name") == "Arnhild"
    sep = " " if wow.eval("Bastians.Client") == "forever" else "-"  # a surname, or a realm
    assert wow.eval(f"{me}.full") == f"Arnhild{sep}Farmadr"
    assert wow.errors == []


def test_an_alt_that_has_not_logged_in_gets_my_surname_a_stranger_does_not(wow: WowRuntime):
    """ "I need name and surname (with a space in between)"."""
    boot(wow)
    wow.execute(
        f"""Bastians.Client = "forever"
        UnitName = function() return "Arnhild", "Farmadr" end
        Mock.Fire('ZONE_CHANGED_NEW_AREA')
        for key, c in pairs({H}.Global().characters) do
          if c.name == "Mockchar" then {H}.Global().characters[key] = nil end -- the boot's name
        end
        {H}.Global().characters['Bankalt-Mock Realm'] = {{ name = "Bankalt", realm = "Mock Realm",
          faction = "Alliance" }}
        {H}.Char().recent = {{ "Stranger", "Bankalt Farmadr" }}
        Mock.OpenMailbox()"""
    )
    assert wow.eval("BastiansHelpersSendTo.buttons[1].label:GetText()") == "Bankalt"
    wow.execute("BastiansHelpersSendTo.buttons[1]:Click()")
    assert wow.eval("SendMailNameEditBox:GetText()") == "Bankalt Farmadr"
    assert wow.eval("BastiansHelpersSendTo.buttons[2].label:GetText()") == "Stranger"
    wow.execute("BastiansHelpersSendTo.buttons[2]:Click()")
    assert wow.eval("SendMailNameEditBox:GetText()") == "Stranger"
    assert wow.eval("BastiansHelpersSendTo.buttons[3]") is None  # no second Bankalt
    assert wow.errors == []


def test_the_mail_name_prefers_the_alts_own_and_guesses_nothing_without_a_surname(wow: WowRuntime):
    boot(wow)
    m = f"{H}.Model"
    assert wow.eval(f"{m}.Surname({{ name = 'Ann', full = 'Ann Oak' }})") == "Oak"
    assert wow.eval(f"{m}.Surname({{ name = 'Ann', full = 'Ann' }})") is None
    assert wow.eval(f"{m}.Surname(nil)") is None
    assert wow.eval(f"{m}.MailName({{ name = 'Ann', full = 'Ann Oak' }}, 'Elm')") == "Ann Oak"
    assert wow.eval(f"{m}.MailName({{ name = 'Ann', full = 'Ann' }}, 'Elm')") == "Ann Elm"
    assert wow.eval(f"{m}.MailName({{ name = 'Ann' }}, 'Elm')") == "Ann Elm"
    assert (
        wow.eval(f"{m}.MailName({{ name = 'Ann' }}, nil)") is None
    )  # the button keeps the first name
    assert wow.eval(f"{m}.MailName(nil, 'Elm')") is None
    assert wow.errors == []


def test_no_surname_is_guessed_when_the_accounts_surnames_differ(wow: WowRuntime):
    """ "you can have as many surnames as you want"."""
    boot(wow)
    m = f"{H}.Model"
    one = "{ a = { name = 'A', full = 'A Oak' }, b = { name = 'B', full = 'B Oak' }, c = { name = 'C' } }"
    two = "{ a = { name = 'A', full = 'A Oak' }, b = { name = 'B', full = 'B Elm' } }"
    assert wow.eval(f"{m}.SharedSurname({one})") == "Oak"
    assert wow.eval(f"{m}.SharedSurname({two})") is None
    assert wow.eval(f"{m}.SharedSurname({{ c = {{ name = 'C' }} }})") is None
    assert wow.errors == []
