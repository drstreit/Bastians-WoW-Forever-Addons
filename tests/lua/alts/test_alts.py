"""Bastian's Alts (alts.md, ADR 0041): the account's characters and what they carry, shown in the
Browser, searchable, and a character asking another for items by mail."""

import re

from harness import WowRuntime

CORE, DATA, BROWSER, ALTS = "Bastians_Core", "Bastians_Data", "Bastians_Browser", "Bastians_Alts"
A = "Bastians:GetModule('Alts').Alts"
G = "Bastians:GetModule('Alts').db.global"
ME = "Mockchar-Mock Realm"

# a second character of the account, recorded on an earlier login: the same realm and side
BANKALT = """{
  name = "Bankalt", realm = "Mock Realm", class = "WARRIOR", faction = "Alliance", level = 20,
  money = 50000, zone = 1429, seen = 1,
  bags = { { 2589, 20 }, { 2589, 20 }, { 1185, 1, true } }, bagsAt = 1,
  bank = { { 2589, 15 } }, bankAt = 1,
  equipped = { [16] = "item:1185" },
}"""
HORDE = """{
  name = "Orcalt", realm = "Mock Realm", class = "SHAMAN", faction = "Horde", level = 30,
  bags = { { 2589, 99 } },
}"""


def strip(text: str | None) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.execute(
        """Mock.money = 1234
        Mock.bagSlots[0] = { slots = 16, { itemID = 2589, count = 20 }, { itemID = 2318, count = 3 } }
        Mock.items[1185] = { name = "Blood Saber", quality = 2, level = 7 }
        Mock.equipped[16] = 1185"""
    )
    wow.start(*(addons or (CORE, DATA, BROWSER, ALTS)))
    wow.run_frames(10)
    for pack in ("world", "items"):
        wow.execute(f'Bastians:GetService("data"):LoadPack("{pack}")')
    wow.run_frames(5)
    return wow


def with_alts(wow: WowRuntime) -> None:
    wow.execute(f"{G}.characters['Bankalt-Mock Realm'] = {BANKALT}")
    wow.execute(f"{G}.characters['Orcalt-Mock Realm'] = {HORDE}")
    wow.execute("Bastians:InvalidateEntities('character'); Bastians:Fire('BASTIANS_ALTS_CHANGED')")


def sections(wow: WowRuntime, ref: str) -> dict:
    return {s.id: s for s in wow.eval(f"Bastians:GetDetailSections('{ref}')").values()}


def rows(wow: WowRuntime, ref: str, section: str) -> list:
    return list(sections(wow, ref)[section].rows.values())


def test_the_model_counts_places_and_whom_a_character_can_ask(core: WowRuntime):
    core.start(ALTS)
    core.execute(
        f"""M = {A}.Model
        GL = M.Ensure({{}})
        GL.characters.Me = {{ name = "Me", realm = "R", faction = "Alliance", bags = {{ {{ 7, 5 }} }} }}
        GL.characters.Alt = {{ name = "Alt", realm = "R", faction = "Alliance",
          bags = {{ {{ 7, 10 }}, {{ 7, 2, true }} }}, bank = {{ {{ 7, 4 }} }}, mail = {{ {{ 7, 1 }} }},
          equipped = {{ [1] = "|cff1eff00|Hitem:7::::::::|h[Hat]|h|r" }} }}
        GL.characters.Far = {{ name = "Far", realm = "Other", faction = "Alliance", bags = {{ {{ 7, 9 }} }} }}
        GL.characters.Orc = {{ name = "Orc", realm = "R", faction = "Horde", bags = {{ {{ 7, 9 }} }} }}"""
    )
    places = core.eval("M.Places(GL.characters.Alt)[7]")
    assert (places.bags, places.bank, places.mail, places.worn, places.bound) == (12, 4, 1, 1, 2)
    holders = [(h.key, h.total, h.free) for h in core.eval("M.Holders(GL, 7)").values()]
    assert holders[0] == ("Alt", 18, 14)  # bags and bank, the soulbound two left out
    askable = [h.key for h in core.eval("M.Askable(GL, 'Me', 7)").values()]
    assert askable == ["Alt"]  # not the other realm, not the other side, not itself
    made = core.eval("M.Ask(GL, 'Me', 7, 100)")
    assert len(made) == 1 and made[1].count == 14 and made[1].holder == "Alt"
    core.execute("M.Ask(GL, 'Me', 7, 200)")  # asking again replaces the request
    assert len(core.eval("GL.requests")) == 1 and core.eval("GL.requests[1].at") == 200
    groups = core.eval("M.RequestsFor(GL, 'Alt')")
    assert groups[1].asker == "Me" and list(groups[1]["items"][1].values()) == [7, 14]
    assert core.eval("M.KeyOf(GL, 'me', 'R')") == "Me"
    assert core.eval("M.KeyOf(GL, 'Far-Other', 'R')") == "Far"  # a name with its realm
    core.execute("M.Sent(GL, 'Alt', 'Me', { [7] = 10 }, 300)")
    assert core.eval("GL.requests[1].count") == 4  # four still asked for
    core.execute("M.Sent(GL, 'Alt', 'Me', { [7] = 4 }, 400)")
    assert len(core.eval("GL.requests")) == 0
    assert core.eval("M.Places(GL.characters.Me)[7].mail") == 14  # in the recipient's mailbox
    assert core.errors == []


def test_this_character_is_recorded_with_bags_equipment_bank_and_mail(wow: WowRuntime):
    boot(wow)
    me = f"{G}.characters['{ME}']"
    assert wow.eval(f"{me}.name") == "Mockchar" and wow.eval(f"{me}.money") == 1234
    assert wow.eval(f"{me}.faction") == "Alliance" and wow.eval(f"{me}.level") == 12
    bags = [list(r.values()) for r in wow.eval(f"{me}.bags").values()]
    assert bags == [[2589, 20], [2318, 3]]
    assert wow.eval(f"{A}.Model.LinkID({me}.equipped[16])") == 1185  # the link, by slot
    assert wow.eval(f"{me}.bank") is None  # not read yet: unknown, never empty
    wow.execute(
        "Mock.bagSlots[6] = { slots = 24, { itemID = 2589, count = 7 } }  -- the first bank tab"
    )
    wow.execute("Mock.Fire('BANKFRAME_OPENED')")
    assert [list(r.values()) for r in wow.eval(f"{me}.bank").values()] == [[2589, 7]]
    wow.execute("Mock.inbox = { { money = 500, items = { { 1185, 1 } } }, { money = 25 } }")
    wow.execute("Mock.OpenMailbox()")
    assert [list(r.values())[:2] for r in wow.eval(f"{me}.mail").values()] == [[1185, 1]]
    assert wow.eval(f"{me}.mailMoney") == 525
    # a bag change is read again shortly after
    wow.execute("Mock.bagSlots[0][2] = nil; Mock.Fire('BAG_UPDATE_DELAYED')")
    wow.advance(0.6)
    wow.run_frames(3)
    assert [list(r.values()) for r in wow.eval(f"{me}.bags").values()] == [[2589, 20]]
    assert wow.errors == []


def test_an_items_page_and_tooltip_say_which_characters_have_it(wow: WowRuntime):
    boot(wow)
    with_alts(wow)
    got = rows(wow, "item:2589", "alts.holders")
    texts = [strip(r.text) for r in got]
    assert texts[0] == "Orcalt  Bags 99"  # the most first, every character of the account
    assert "Bankalt  Bags 40, Bank 15" in texts and "Mockchar  Bags 20" in texts
    assert got[0].ref == "character:Orcalt-Mock Realm" and got[0].value == 99
    tips = [strip(r.text) for r in wow.eval("Bastians:GetTooltipRows('item:2589')").values()]
    assert "Bankalt: 55" in tips
    assert wow.errors == []


def test_a_characters_page_lists_what_it_carries(wow: WowRuntime):
    boot(wow)
    with_alts(wow)
    ref = "character:Bankalt-Mock Realm"
    assert wow.eval(f"Bastians:Entity('{ref}'):Name()") == "Bankalt"
    assert wow.eval(f"Bastians:Entity('{ref}'):Summary()").startswith("Level 20")
    assert wow.eval(f"Bastians:Entity('{ref}'):Icon()") == "Interface\\Icons\\ClassIcon_WARRIOR"
    page = sections(wow, ref)
    assert {"alts.overview", "alts.equipment", "alts.bags", "alts.bank"} <= set(page)
    assert "alts.mail" not in page  # its mailbox was never opened
    bags = [(strip(r.text), r.value) for r in page["alts.bags"].rows.values()]
    assert bags == [("Blood Saber", 1), ("Linen Cloth", 40)]  # stacks summed, by name
    worn = [strip(r.text) for r in page["alts.equipment"].rows.values()]
    assert worn == ["Blood Saber  Main hand"]
    money = [r for r in page["alts.overview"].rows.values() if strip(r.text) == "Money"]
    assert money[0].value == 50000 and money[0].valueKind == "money"
    # the Characters list in the Browser
    wow.execute("Bastians:GetModule('Browser').Browser.List('character')")
    wow.run_frames(10)
    tree = "Bastians:GetModule('Browser').tree"
    wow.execute(f"{tree}.scroll:SetSize(440, 400); {tree}:Refresh()")
    names = [strip(r.text).split("  ")[0] for r in wow.eval(f"{tree}.flat").values()]
    assert {"Bankalt", "Mockchar", "Orcalt"} <= set(names)
    assert wow.errors == []


def test_the_search_finds_what_the_characters_hold(wow: WowRuntime):
    boot(wow)
    with_alts(wow)
    hits = list(wow.eval(f"{A}.Search('linen', 10)").values())
    assert [(h.ref, h.note) for h in hits] == [("item:2589", "Alts: 174")]  # 20 + 55 + 99
    assert list(wow.eval(f"{A}.Search('zzz', 10)").values()) == []
    assert wow.errors == []


def test_asking_an_alt_and_filling_its_mail(wow: WowRuntime):
    boot(wow)
    with_alts(wow)
    actions = [
        a.id for a in wow.eval("Bastians:GetActions('item:2589', { source = 'test' })").values()
    ]
    assert "alts.ask" in actions
    wow.execute("Bastians:RunAction('alts.ask', 'item:2589', { source = 'test' })")
    reqs = list(wow.eval(f"{G}.requests").values())
    assert [(r.holder, r.count) for r in reqs] == [("Bankalt-Mock Realm", 55)]  # not the Horde alt
    me = rows(wow, f"character:{ME}", "alts.requests")
    assert strip(me[0].text) == "Linen Cloth  asked of Bankalt" and me[0].value == 55
    # Bankalt logs in: its bags are what the client reads now
    wow.execute(
        """Mock.playerName = "Bankalt"
        Mock.bagSlots[0] = { slots = 16, { itemID = 2589, count = 20 }, { itemID = 2589, count = 20 },
          { itemID = 1185, count = 1, bound = true } }
        Mock.bagSlots[6] = nil"""
    )
    wow.execute(f"{A}.RecordAll()")
    wow.execute("Mock.OpenMailbox()")
    strip_frame = "BastiansAltsMailStrip"
    assert wow.eval(f"{strip_frame}:IsShown()") is True
    words = strip(wow.eval(f"{strip_frame}.text:GetText()"))
    assert words == "Mockchar asks for: Linen Cloth x55 (15 in the bank)"
    wow.execute(f"{strip_frame}.fill:Click()")
    assert wow.eval("SendMailNameEditBox:GetText()") == "Mockchar"
    assert wow.eval("SendMailSubjectEditBox:GetText()") == "Bastian's Alts: your request"
    sent = [list(it.values()) for it in wow.eval("Mock.sendItems").values()]
    assert sent == [[2589, 20], [2589, 20]]  # whole stacks from the bags, never the bound saber
    wow.execute('SendMail("Mockchar", "Your request", "")')
    assert wow.eval("Mock.sentMail.recipient") == "Mockchar"
    wow.advance(0.1)
    wow.run_frames(3)
    reqs = list(wow.eval(f"{G}.requests").values())
    assert [r.count for r in reqs] == [15]  # the bank's fifteen are still asked for
    mail = [list(r.values()) for r in wow.eval(f"{G}.characters['{ME}'].mail").values()]
    assert mail == [[2589, 40]]  # in Mockchar's recorded mailbox at once
    assert wow.errors == []


def test_without_the_browser_the_app_still_records_and_searches(wow: WowRuntime):
    boot(wow, CORE, DATA, ALTS)
    with_alts(wow)
    assert wow.eval(f"{G}.characters['{ME}'].bags") is not None
    assert len(list(wow.eval(f"{A}.Search('linen', 10)").values())) == 1
    assert wow.eval("Bastians:GetDetailSections('item:2589')") is not None
    assert wow.errors == []


def test_what_each_character_knows_and_who_knows_a_trainers_spell(wow: WowRuntime):
    """ "known by you, MyAltName, MyAltName2 ... the tiles for these are
    color coded". The spell book and the open profession window are recorded per character; the
    `knowledge` service answers who knows a spell; Data's Teaches rows draw it."""
    wow.execute("Mock.spells[116] = true")  # Frostbolt (Rank 1), known at login
    boot(wow)
    known = wow.eval(f"{G}.characters['{ME}'].known")
    assert known[116] is True and known[133] is None
    # the open profession window lists its recipes: the learned ones are recorded
    wow.execute("Mock.openRecipes = { [2330] = true, [2331] = false }")
    wow.fire("TRADE_SKILL_LIST_UPDATE")
    wow.advance(0.6)
    known = wow.eval(f"{G}.characters['{ME}'].known")
    assert known[2330] is True and known[2331] is None
    # a spell learned later
    wow.execute("Mock.spells[133] = true")
    wow.fire("SPELLS_CHANGED")
    wow.advance(2.1)
    assert wow.eval(f"{G}.characters['{ME}'].known[133]") is True
    wow.execute("Mock.spells[133] = nil")  # the client says no again: the record is what alts see
    with_alts(wow)
    wow.execute(f"{G}.characters['Bankalt-Mock Realm'].known = {{ [133] = true }}")
    wow.execute("Bastians:Fire('BASTIANS_ALTS_CHANGED')")
    k = wow.eval("Bastians:GetService('knowledge'):Known(133)")
    assert k.me is False and list(k.alts.values()) == ["Bankalt"]
    k = wow.eval("Bastians:GetService('knowledge'):Known(116)")
    assert k.me is True and list(k.alts.values()) == []
    assert wow.eval("Bastians:GetService('knowledge'):Known(9999).me") is False
    # Data's Teaches rows: Fireball (133) known by Bankalt in blue, Frostbolt (116) by you in green
    teaches = rows(wow, "npc:198", "data.trainer")
    fireball, frostbolt = teaches[0], teaches[1]
    assert fireball.tint == "water" and fireball.note == "Bankalt"
    assert fireball.icon == wow.eval("Bastians.UI.GLYPH_PATHS.done")
    assert frostbolt.tint == "good" and frostbolt.note == "you"
    assert list(fireball.known.values()) == ["Bankalt"] and list(frostbolt.known.values()) == [
        "you"
    ]
    # nobody knows it: the trainer glyph in grey, the tooltip says so
    wow.execute(
        f"{G}.characters['Bankalt-Mock Realm'].known = nil; Bastians:Fire('BASTIANS_ALTS_CHANGED')"
    )
    fireball = rows(wow, "npc:198", "data.trainer")[0]
    assert fireball.tint == "dim" and fireball.note is None
    assert fireball.icon == wow.eval("Bastians.UI.GLYPH_PATHS.trainer")
    wow.execute("TIP = {} ; local r = Bastians:GetDetailSections('npc:198')")
    wow.execute(
        """local tt = { lines = {}, AddLine = function(self, t) self.lines[#self.lines + 1] = t end }
        local s; for _, x in ipairs(Bastians:GetDetailSections('npc:198')) do if x.id == 'data.trainer' then s = x end end
        s.rows[1].tooltip(tt, s.rows[1]); TIP = tt.lines"""
    )
    tip = list(wow.eval("TIP").values())
    assert tip[-1] == "Not known by any of your characters"
    # the summary of a trainer says what it trains and how many it teaches
    assert (
        wow.eval("Bastians:Entity('npc:198'):Summary()")
        == "Level 30, Mage Trainer, teaches 2, Elwynn Forest"
    )
    assert wow.errors == []


def test_the_owned_facet_of_the_item_lists(wow: WowRuntime):
    """ "a filter 'owned by you' and 'owned by an alt'"."""
    boot(wow)
    with_alts(wow)
    wow.execute(f"{G}.characters['Bankalt-Mock Realm'].bags = {{ {{ 4306, 5 }} }}")  # Silk Cloth
    wow.execute("Bastians:Fire('BASTIANS_ALTS_CHANGED')")
    assert wow.eval(f"{A}.Owned(2589)") == "You"  # Linen Cloth in my bags
    assert wow.eval(f"{A}.Owned(4306)") == "Your characters"
    assert wow.eval(f"{A}.Owned(1185)") == "You"  # worn by me (and by Bankalt)
    assert wow.eval(f"{A}.Owned(99999)") == "Nobody"
    facets = {f.id: f for f in wow.eval("Bastians:GetFilters('item', 'facet')").values()}
    f = facets["alts.owned"]
    assert f.label == "Owned"
    assert (
        wow.eval("Bastians:FilterValue(Bastians:GetFilter('alts.owned'), 'item:4306')")
        == "Your characters"
    )
    assert wow.eval("Bastians:GetFilter('alts.owned').order('You')") == 1
    assert wow.eval("Bastians:GetFilter('alts.owned').labels('Nobody')") == "Nobody"
    # a change of the bags drops the index: the next ask sees it
    wow.execute(
        f"{G}.characters['Bankalt-Mock Realm'].bags = {{}}; Bastians:Fire('BASTIANS_ALTS_CHANGED')"
    )
    wow.run_frames(2)  # the bus delivers on the next frame
    assert wow.eval(f"{A}.Owned(4306)") == "Nobody"
    assert wow.errors == []


def test_the_pages_say_who_owns_an_item_and_who_knows_a_recipe(wow: WowRuntime):
    """ "a clear indication on each node's detail page if I or an alt
    owns it": a card row on the band of an item's page and of a recipe's page."""
    boot(wow)
    with_alts(wow)
    row = rows(wow, "item:2589", "alts.owned")
    assert len(row) == 1
    assert row[0].text == "You have it: bags 20; Orcalt: bags 99; Bankalt: bags 40, bank 15"
    assert wow.eval("Bastians.UI.Card('item:2589').status") == row[0].text
    assert "alts.owned" not in sections(wow, "item:99999")
    wow.execute(
        f"{G}.characters['Bankalt-Mock Realm'].known = {{ [2330] = true }}; Mock.spells[2330] = true"
    )
    wow.execute("Bastians:Fire('BASTIANS_ALTS_CHANGED')")
    wow.run_frames(2)
    known = rows(wow, "recipe:2330", "alts.known")
    assert len(known) == 1 and known[0].text == "Known by: you, Bankalt"
    assert wow.errors == []


def test_the_characters_filter_finds_all_we_know(wow: WowRuntime):
    """ "name, class, place, really all info we have ... inventory"."""
    boot(wow)
    with_alts(wow)
    browser = "Bastians:GetModule('Browser').Browser"
    wow.execute(f"CHARS = {browser}.BuildList('character')")

    def found(text: str) -> set[str]:
        out = wow.eval(f"{browser}.Filter(CHARS, {{ filterText = {text!r} }})")
        return {wow.eval(f"CHARS.names[{i}]") for i in out.rows.values()}

    assert found("bankalt") == {"Bankalt"}
    assert "Bankalt" in found("warrior")  # the class
    assert "Bankalt" in found("elwynn")  # the place
    assert found("horde") == {"Orcalt"}  # the faction
    assert found("shaman") == {"Orcalt"}
    assert "Bankalt" in found("blood saber") and "Orcalt" not in found(
        "blood saber"
    )  # what it holds
    assert "Orcalt" in found("linen")  # in the bags of both
    assert found("nosuchthing") == set()
    assert wow.errors == []


def test_a_deleted_character_can_be_forgotten(wow: WowRuntime):
    """a character deleted in the game stays in the lists."""
    boot(wow, CORE, DATA, BROWSER, ALTS, "Bastians_Helpers")
    with_alts(wow)
    key = "Bankalt-Mock Realm"
    ref = f"character:{key}"
    helpers = "Bastians:GetModule('Helpers').Helpers.Global().characters"
    wow.execute(f"{helpers}['{key}'] = {{ name = 'Bankalt' }}")
    wow.execute(
        f"{G}.requests[1] = {{ item = 2589, count = 1, holder = '{key}', asker = '{ME}', at = 1 }}"
    )
    ids = [a.id for a in wow.eval(f"Bastians:GetActions('{ref}')").values()]
    assert "alts.forget" in ids
    me = [a.id for a in wow.eval(f"Bastians:GetActions('character:{ME}')").values()]
    assert "alts.forget" not in me  # never the one playing
    assert wow.eval(f"{A}.Forget('{key}')") is False  # the first use asks
    assert wow.eval(f"{G}.characters['{key}'].name") == "Bankalt"
    wow.advance(6)
    assert wow.eval(f"{A}.Forget('{key}')") is False  # too late: it asks again
    assert wow.eval(f"{A}.Forget('{key}')") is True
    assert wow.eval(f"{G}.characters['{key}']") is None
    assert len(wow.eval(f"{G}.requests")) == 0
    assert wow.eval(f"{helpers}['{key}']") is None
    assert wow.errors == []


def test_a_mail_to_a_whole_name_finds_the_character(wow: WowRuntime):
    boot(wow)
    with_alts(wow)
    wow.execute(f"{G}.characters['Bankalt-Mock Realm'].full = 'Bankalt Farmadr'")
    key = f"{A}.Model.KeyOf({G}, %s, 'Mock Realm')"
    assert wow.eval(key % "'Bankalt Farmadr'") == "Bankalt-Mock Realm"
    assert wow.eval(key % "'Bankalt'") == "Bankalt-Mock Realm"
    assert wow.eval(key % "'Nobody Farmadr'") is None


def test_a_reload_at_the_mailbox_raises_nothing(wow: WowRuntime):
    """(BugGrabber): "bad argument #1 to 'ipairs'" in RequestsFor. Core
    prunes the empty request list at the logout, then the mail strip was refreshed from it."""
    boot(wow)
    wow.fire("MAIL_SHOW")
    # Core was first: the client picks the order of the event's frames
    wow.execute(f"rawset({G}, 'requests', nil)")
    wow.fire("PLAYER_LOGOUT")
    assert wow.errors == []
    assert not [e for e in wow.eval("Bastians:GetLog()").values() if e.level == "error"]
