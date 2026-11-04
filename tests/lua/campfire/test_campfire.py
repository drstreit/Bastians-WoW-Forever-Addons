"""Bastian's Campfire (campfire.md, plan-second-wave.md S5): the model (brackets, the card's states,
the beacon's message and expiry, the chat pickup, the planner's rows), the card on the auras, the
warmth's words and events, the camp ring through Core's ring registry and Gestures, the beacon
through Comm with its map layer, the planner view, the public API, and life without the optional
apps."""

from harness import WowRuntime

CORE, DATA, GESTURES, CAMP = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Gestures",
    "Bastians_Campfire",
)
MOD = "Bastians:GetModule('Campfire')"
M = f"{MOD}.Model"
CAMPDATA = f"{MOD}.Camp"
W = f"{MOD}.Watch"
CARD = f"{MOD}.Card"
BEACON = f"{MOD}.Beacon"
RING = f"{MOD}.CampRing"
PLAN = f"{MOD}.Planner"
NEARBY, RESTING, STAMINA, MANA = 1283391, 1229739, 1230124, 1230587


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.needs(CAMP)  # camping is Forever's: no Campfire on retail
    wow.start(*(addons or (CORE, DATA, GESTURES, CAMP)))
    wow.run_frames(5)
    return wow


def errors(wow: WowRuntime) -> list[str]:
    return wow.errors + [
        line.text
        for line in wow.eval("Bastians:GetLog()").values()
        if line.level == "error" and "registered no data" not in line.text
    ]


def auras(wow: WowRuntime, lua_list: str) -> None:
    wow.execute(f"Mock.auras = {lua_list}")
    wow.fire("UNIT_AURA", "player", {})
    wow.run_frames(2)


# ---- the model -----------------------------------------------------------------------------------


def test_brackets_give_the_literal_value_and_nil_beyond_or_unknown(wow: WowRuntime):
    boot(wow)
    mana = f"{CAMPDATA}.BENEFITS.mana.levels"
    assert wow.eval(f"{M}.Value({mana}, 15)") == 10  # Campfire Tooltips' live check: 10 at 15
    assert wow.eval(f"{M}.Value({mana}, 23)") == 10
    assert wow.eval(f"{M}.Value({mana}, 24)") == 15
    assert wow.eval(f"{M}.Value({mana}, 60)") == 29
    assert wow.eval(f"{M}.Value({mana}, 61)") is None
    assert wow.eval(f"{M}.Value({mana}, nil)") is None
    attack = f"{CAMPDATA}.BENEFITS.attack.levels"
    assert wow.eval(f"{M}.Value({attack}, 15)") == 20  # Lodestone at 15: 20 (the same source)
    lute = wow.eval(f"{M}.Values({CAMPDATA}.BENEFITS.lute, 35)")
    assert (lute.armor, lute.attributes, lute.resistances) == (163, 7, 6)


def test_every_feature_and_kit_has_its_item_spell_skill_and_a_known_benefit(wow: WowRuntime):
    boot(wow)
    features = list(wow.eval(f"{CAMPDATA}.FEATURES").values())
    assert len(features) == 36
    for f in features:
        assert f.item and f.spell and f.skill and f.rank in (20, 140, 300)
        assert f.tier == (3 if f.rank >= 300 else 2 if f.rank >= 140 else 1)
        assert (f.blueprint is None) == (f.rank == 20)
        if f.benefit:
            assert wow.eval(f"{CAMPDATA}.BENEFITS['{f.benefit}'] ~= nil")
    kits = list(wow.eval(f"{CAMPDATA}.KITS").values())
    assert [k.size for k in kits] == [3, 5, 10]
    assert wow.eval(f"{CAMPDATA}.BY_AURA[{STAMINA}]") == "stamina"
    assert wow.eval(f"{CAMPDATA}.BY_SPELL[1307259].name") == "Mana Well"


def card(wow: WowRuntime, inp: str):
    return wow.eval(f"{M}.Card({inp})")


def test_the_card_goes_near_warming_warm_fading_and_lingers_a_minute(wow: WowRuntime):
    boot(wow)
    c = card(wow, "{ now = 100, nearby = true, buffs = {}, carried = {} }")
    assert (c.state, c.show) == ("near", True)
    c = card(wow, "{ now = 100, nearby = true, resting = 142, buffs = {}, carried = {} }")
    assert (c.state, c.warmIn) == ("warming", 42)
    c = card(wow, "{ now = 100, nearby = true, resting = true, buffs = {}, carried = {} }")
    assert c.state == "warming" and c.warmIn is None
    c = card(
        wow, "{ now = 100, nearby = true, buffs = { stamina = 3700, mana = 2000 }, carried = {} }"
    )
    assert c.state == "warm" and c.left == 1900 and list(c.have.values()) == ["stamina", "mana"]
    c = card(wow, "{ now = 100, buffs = { stamina = 600 }, carried = {} }")
    assert c.state == "fading" and c.show is False
    c = card(wow, "{ now = 100, buffs = { stamina = true }, carried = {} }")
    assert c.state == "warm" and c.left is None  # an end the client did not give: unknown
    assert card(wow, "{ now = 150, seen = 100, buffs = {}, carried = {} }").show is True
    assert card(wow, "{ now = 161, seen = 100, buffs = {}, carried = {} }").show is False


def test_could_add_offers_only_what_the_camp_lacks_one_per_benefit(wow: WowRuntime):
    boot(wow)
    carried = (
        f"{{ {CAMPDATA}.BY_ITEM[279968], {CAMPDATA}.BY_ITEM[279940], {CAMPDATA}.BY_ITEM[279956],"
        f" {CAMPDATA}.BY_ITEM[279981] }}"
    )
    could = list(wow.eval(f"{M}.Could({carried}, {{ 'mana' }})").values())
    assert [f.name for f in could] == [
        "First Aid Kit"
    ]  # Toxin Study: the same benefit; the kit: no feature
    missing = list(wow.eval(f"{M}.Missing({{ 'stamina' }})").values())
    assert "stamina" not in missing and "tent" not in missing and "mana" in missing


def test_the_message_round_trip_and_what_a_receiver_refuses(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"P = {M}.Payload({{ map = 1429, x = 0.4, y = 0.6, features = {{ 'stamina', 'nope' }},"
        f" since = 40 }}, 100)"
    )
    p = wow.eval("P")
    assert (p.v, p.map, p.age) == (1, 1429, 60)
    assert list(p.features.values()) == ["stamina"]
    fire = wow.eval(f"{M}.CleanCamp(P, 5000)")
    assert (fire.map, fire.x, fire.at, fire.size) == (1429, 0.4, 4940, None)
    for bad in (
        "{ v = 1, map = 1429, x = 1.5, y = 0.5 }",
        "{ v = 1, map = -3, x = 0.5, y = 0.5 }",
        "{ map = 1429, x = 0.5, y = 0.5 }",
        "{ v = 1, map = 1429, x = 0.5, y = 0.5, age = 4000 }",
        "'camp'",
    ):
        assert wow.eval(f"({M}.CleanCamp({bad}, 100))") is None, bad
    odd = wow.eval(
        f"{M}.CleanCamp({{ v = 2, map = 1429, x = 0.5, y = 0.5, size = 7, extra = 'x' }}, 100)"
    )
    assert odd.size is None and odd.extra is None  # a newer sender's fields are ignored


def test_prune_drops_expired_fires_and_merges_one_place(wow: WowRuntime):
    boot(wow)
    kept = wow.eval(
        f"{M}.Prune({{ {{ map = 1, x = 0.5, y = 0.5, at = 100 }}, {{ map = 1, x = 0.502, y = 0.5, at = 200 }},"
        f" {{ map = 1, x = 0.9, y = 0.9, at = -5000 }} }}, 300)"
    )
    kept = list(kept.values())
    assert len(kept) == 1 and kept[0].at == 200


def test_the_chat_pickup_needs_a_map_pin_and_a_whole_camp_word(wow: WowRuntime):
    boot(wow)
    link = "|cffffff00|Hworldmap:1429:4200:6500|h[Map Pin]|h|r"
    words = "{ 'camp', 'fire' }"
    pick = wow.eval(f"{{ {M}.ChatCamp('Camp up at {link} come by', {words}) }}")
    assert list(pick.values()) == [1429, 0.42, 0.65]
    assert wow.eval(f"{M}.ChatCamp('Campaign at {link}', {words})") is None
    assert wow.eval(f"{M}.ChatCamp('a fire burns', {words})") is None
    assert wow.eval(f"({M}.ChatCamp('FIRE! {link}', {words}))") == 1429


def test_the_plan_marks_what_this_character_can_place(wow: WowRuntime):
    boot(wow)
    plan = list(wow.eval(f"{M}.Plan({{ level = 15 }})").values())
    assert all(e.canPlace is None for e in plan)  # the client did not say: unknown, not "no"
    first = plan[0]
    assert first.feature.benefit == "stamina" and first["amounts"].main == 8
    plan = list(
        wow.eval(
            f"{M}.Plan({{ level = 15, professions = {{ [171] = 150 }}, faction = 'Horde' }})"
        ).values()
    )
    by = {e.feature.name: e for e in plan}
    assert by["Mana Well"].canPlace is True and by["Fermenter"].canPlace is True
    assert by["Alchemy Laboratory"].canPlace is False and by["Lodestone"].canPlace is False
    banners = [e for e in plan if e.feature.name == "Faction Banner"]
    assert len(banners) == 1 and banners[0].feature.faction == "Horde"
    assert plan[-1].feature.benefit is None  # the services last


# ---- the app ---------------------------------------------------------------------------------------


def test_loads_alone_and_with_the_suite_and_survives_disable_and_enable(wow: WowRuntime):
    boot(wow, CORE, CAMP)
    assert wow.eval(f"{MOD}:IsEnabled()") is True
    wow.execute(f"{MOD}:Disable()")
    wow.execute(f"{MOD}:Enable()")
    wow.run_frames(2)
    assert wow.eval("Bastians:GetService('camps') ~= nil")
    assert errors(wow) == []


def test_the_card_follows_the_auras_and_the_warmth_speaks_once(wow: WowRuntime):
    boot(wow)
    wow.execute("Told = {} ; Bastians.Tell = function(_, _, kind, text) Told[#Told + 1] = text end")
    wow.execute(
        "Warmed = {} ; Bastians:GetModule('Core'):On('BASTIANS_CAMP_WARMED', function(_, _, who) Warmed[#Warmed + 1] = who or 'nil' end)"
    )
    assert wow.eval(f"{CARD}.IsShown()") is False
    auras(wow, f"{{ {{ name = 'Campfire Nearby', spellId = {NEARBY} }} }}")
    assert wow.eval(f"{CARD}.IsShown()") is True
    heading = wow.eval(f"{CARD}.Frame().heading:GetText()")
    assert heading == "A fire nearby"
    wow.execute("Mock.bags[279968] = 1")  # a First Aid Kit in the bags
    wow.fire("BAG_UPDATE_DELAYED")
    wow.advance(1)
    wow.run_frames(3)
    assert "You could add: First Aid Kit." in wow.eval(f"{CARD}.Frame().text:GetText()")
    now = wow.eval("GetTime()")
    auras(
        wow,
        f"{{ {{ spellId = {NEARBY} }}, {{ spellId = {RESTING}, expirationTime = {now + 42} }} }}",
    )
    assert "0:42 until you are warm." in wow.eval(f"{CARD}.Frame().text:GetText()")
    auras(
        wow,
        f"{{ {{ spellId = {NEARBY} }}, {{ spellId = {STAMINA}, expirationTime = {now + 3600} }},"
        f" {{ spellId = {MANA}, expirationTime = {now + 3500} }} }}",
    )
    assert wow.eval(f"{CARD}.Frame().heading:GetText()") == "You are warm"
    assert list(wow.eval("Told").values()) == ["You are warm."]
    assert list(wow.eval("Warmed").values()) == ["nil"]
    auras(
        wow,
        f"{{ {{ spellId = {NEARBY} }}, {{ spellId = {STAMINA}, expirationTime = {now + 3600} }} }}",
    )
    assert list(wow.eval("Told").values()) == ["You are warm."]  # once, not per aura change
    assert len(list(wow.eval(f"{MOD}.db.char.log").values())) == 1
    wow.advance(3000)  # ten minutes before the earliest end
    assert list(wow.eval("Told").values())[-1] == "The fire's warmth is fading."
    assert errors(wow) == []


def test_a_strangers_camp_asks_to_thank_the_host_in_gestures(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.guids = { party1 = 'Player-1-1' } ; Mock.unitNames = { party1 = 'Tobb' }")
    auras(
        wow,
        f"{{ {{ spellId = {STAMINA}, expirationTime = GetTime() + 3600, sourceUnit = 'party1' }} }}",
    )
    pending = wow.eval("Bastians:GetModule('Gestures').Courtesy.Pending()")
    assert pending.kind == "camp" and pending.who == "Tobb"
    assert (
        wow.eval(
            "Bastians:GetModule('Gestures').Courtesy.Words(Bastians:GetModule('Gestures').Courtesy.Pending())"
        )
        == "Tobb's camp warmed you"
    )


def test_the_camp_ring_is_a_fourth_ring_only_while_the_app_and_its_setting_are_on(wow: WowRuntime):
    boot(wow)
    g = "Bastians:GetModule('Gestures').Ring"
    assert wow.eval(f"{g}.Pages()") == 4
    ids = list(wow.eval(f"{RING}.Ids()").values())
    assert ids == ["sit", "warm", "offer", "invite", "thank", "story", "share", "bow"]
    wow.execute(f"{g}.SetPage(4)")
    assert wow.eval(f"{g}.Current().name") == "Camp"
    items = list(wow.eval(f"{RING}.Items()").values())
    offer = items[2]
    assert offer.disabled is True  # nothing in the bags the camp lacks
    wow.execute("Mock.bags[279956] = 1")
    wow.fire("BAG_UPDATE_DELAYED")
    wow.advance(1)
    offer = list(wow.eval(f"{RING}.Items()").values())[2]
    assert (
        offer.label == "Mana Well"
        and offer.secure.type == "item"
        and offer.secure.item == "item:279956"
    )
    assert wow.eval(f"{g}.Open()") is True
    assert wow.eval(f"{g}.Fire(1)") is True  # Sit
    assert [e.token for e in wow.eval("Mock.emotes").values()][-1] == "SIT"
    wow.execute(
        f"{MOD}.db.profile.ring = false ; Bastians:Fire('BASTIANS_SETTING_CHANGED', 'Campfire', 'ring', false)"
    )
    assert wow.eval(f"{g}.Pages()") == 3 and wow.eval(f"{g}.Page()") == 1
    wow.execute(
        f"{MOD}.db.profile.ring = true ; Bastians:Fire('BASTIANS_SETTING_CHANGED', 'Campfire', 'ring', true)"
    )
    assert wow.eval(f"{g}.Pages()") == 4
    wow.execute(f"{MOD}:Disable()")
    assert wow.eval(f"{g}.Pages()") == 3
    assert errors(wow) == []


def test_share_sends_a_camp_message_and_a_received_fire_is_a_pin_for_an_hour(wow: WowRuntime):
    boot(wow)
    wow.execute("Told = {} ; Bastians.Tell = function(_, _, kind, text) Told[#Told + 1] = text end")
    assert wow.eval(f"({BEACON}.Share())") is None  # no group, no guild
    wow.execute("Mock.groupSize = 2 ; Mock.inGuild = true")
    assert wow.eval(f"{BEACON}.Share()") == 2
    wow.advance(2)
    sent = [m for m in wow.eval("Mock.addonMessages").values() if "|camp|" in m.text]
    assert {m.channel for m in sent} == {"PARTY", "GUILD"}
    assert len(list(wow.eval(f"{BEACON}.Fires()").values())) == 1  # our own, marked mine
    value = "{ v = 1, map = 1453, x = 0.3, y = 0.7, features = { 'mana' }, age = 120 }"
    assert wow.eval(f"{BEACON}.Receive({value})") is True
    assert list(wow.eval("Told").values()) == ["A friend lit a fire in Stormwind City."]
    fires = list(wow.eval(f"{BEACON}.Fires()").values())
    assert len(fires) == 2 and all(f.chat is None for f in fires)
    saved = wow.eval(f"{MOD}.db.global.fires")
    assert all(getattr(f, "sender", None) is None for f in saved.values())  # no name is kept
    pins = list(
        wow.eval("Bastians:GetMapLayer('campfire.fires').query({ continent = 0 })").values()
    )
    assert len(pins) == 2 and {p.icon for p in pins} == {"campfire"}
    wow.execute("local t = time ; time = function() return t() + 3700 end")
    assert list(wow.eval(f"{BEACON}.Fires()").values()) == []
    assert errors(wow) == []


PUBLIC = f"{MOD}.Public"
FIRE = "1|{id}|1/1|camp|" + "t" + "s1:vn1;" + "s3:mapn1453;" + "s1:xn{x};" + "s1:yn0.7;" + "e"


def channel_fire(wow: WowRuntime, sender: str, i: int, x: float = 0.3) -> None:
    text = FIRE.replace("{id}", str(i)).replace("{x}", str(x))
    wow.execute(f"Bastians.Comm.Receive('Bastians', {text!r}, 'CHANNEL', {sender!r})")


def test_the_public_channel_is_off_until_switched_on_then_capped_and_blockable(wow: WowRuntime):
    """#20: off by default, no channel joined; switched on it joins a hidden temporary channel
    after a delay, a share goes there too (at most once in five minutes), a stranger's fire comes
    in once per five minutes with the name in memory only, a blocked name is dropped, twenty at
    most; switched off it leaves."""
    boot(wow)
    wow.advance(20)
    assert wow.eval(f"{MOD}.db.profile.public") is False
    assert wow.eval("Mock.channels.BastiansCamp") is None
    channel_fire(wow, "Stranger-Realm", 1)
    assert list(wow.eval(f"{BEACON}.Fires()").values()) == []  # off: nothing comes in
    wow.execute(f"{MOD}.db.profile.public = true; {PUBLIC}.Apply()")
    assert wow.eval(f"{PUBLIC}.Number()") == 1
    assert wow.eval("Mock.removedFrom.BastiansCamp") >= 1  # kept out of the chat windows
    channel_fire(wow, "Stranger-Realm", 2)
    channel_fire(wow, "Stranger-Realm", 3)  # the same sender again at once: dropped
    fires = list(wow.eval(f"{BEACON}.Fires()").values())
    assert len(fires) == 1 and fires[0].public is True
    saved = wow.eval(f"{MOD}.db.global.fires")
    assert all(getattr(f, "sender", None) is None for f in saved.values())  # no name saved
    pins = list(
        wow.eval("Bastians:GetMapLayer('campfire.fires').query({ continent = 0 })").values()
    )
    assert pins[0].label == "A fire burns here (since 0 min, shared by Stranger)"
    wow.execute(f"{MOD}.Campfire.Slash('block Pest')")
    assert wow.eval(f"{PUBLIC}.Blocked('Pest-OtherRealm')") is True
    channel_fire(wow, "Pest-OtherRealm", 4)
    assert len(list(wow.eval(f"{BEACON}.Fires()").values())) == 1
    assert wow.eval(f"{PUBLIC}.BlockedText()") == "pest"
    for n in range(30):  # many strangers: twenty at most
        channel_fire(wow, f"Many{n}-Realm", 100 + n, x=round(0.02 * n + 0.32, 2))
    assert len(list(wow.eval(f"{BEACON}.Fires()").values())) == 20
    # a share goes to the channel too, once in five minutes
    wow.execute("Mock.addonMessages = {}")
    assert wow.eval(f"{BEACON}.Share()") == 1
    assert wow.eval(f"({BEACON}.Share())") is None  # nobody else and the channel waits
    wow.advance(2)
    sent = [m for m in wow.eval("Mock.addonMessages").values() if "|camp|" in m.text]
    assert [(m.channel, m.target) for m in sent] == [("CHANNEL", 1)]
    wow.execute(f"{MOD}.db.profile.public = false; {PUBLIC}.Apply()")
    assert wow.eval("Mock.channels.BastiansCamp") is None and wow.eval(f"{PUBLIC}.Number()") is None
    assert errors(wow) == []


def test_a_camp_posted_in_chat_becomes_a_faded_pin(wow: WowRuntime):
    boot(wow)
    wow.fire("CHAT_MSG_SAY", "camp here |Hworldmap:1429:5000:5000|h[Map Pin]|h", "Grimtok")
    fires = list(wow.eval(f"{BEACON}.Fires()").values())
    assert len(fires) == 1 and fires[0].chat is True and fires[0].x == 0.5
    pins = list(
        wow.eval("Bastians:GetMapLayer('campfire.fires').query({ continent = 0 })").values()
    )
    assert pins[0].size == 12 and pins[0].color is not None
    wow.execute(f"{MOD}.db.profile.chatPickup = false")
    wow.fire("CHAT_MSG_SAY", "fire |Hworldmap:1429:1000:1000|h[Map Pin]|h", "Grimtok")
    assert len(list(wow.eval(f"{BEACON}.Fires()").values())) == 1


def test_the_planner_rows_and_unknown_values(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.level = 15")
    rows = list(wow.eval(f"({PLAN}.Rows())").values())
    titles = [r.text for r in rows]
    assert titles[0] == "My camp now"
    stamina = next(r for r in rows if r.text.startswith("Stamina"))
    kit = next(iter(stamina.children.values()))
    assert kit.title == "First Aid Kit" and kit.value == "+8 Stamina"
    assert "Power Word: Fortitude" in stamina.text
    wow.execute("Mock.level = 0")
    rows = list(wow.eval(f"({PLAN}.Rows())").values())
    stamina = next(r for r in rows if r.text.startswith("Stamina"))
    assert next(iter(stamina.children.values())).value == "unknown"
    assert errors(wow) == []


def test_the_public_api_reads_the_camp_and_says_nil_without_it(wow: WowRuntime):
    boot(wow, CORE, CAMP)
    camp = wow.eval("Bastians.API.Camp()")
    assert camp.state == "away" and camp.nearby is False and camp.buffs == 0 and camp.fires == 0
    wow.execute(f"{MOD}:Disable()")
    assert wow.eval("Bastians.API.Camp()") is None


def test_the_presets_set_the_campfire_sides(wow: WowRuntime):
    boot(wow)
    wow.execute("Bastians.UI.Settings.ApplyPlay('wanderer')")
    p = wow.eval(f"{MOD}.db.profile")
    assert (p.card, p.ring, p.beacon, p.planner) == (True, True, True, False)
    wow.execute("Bastians.UI.Settings.ApplyPlay('scholar')")
    p = wow.eval(f"{MOD}.db.profile")
    assert (p.card, p.ring, p.beacon, p.planner) == (True, False, True, True)
    assert wow.eval(f"{MOD}:IsEnabled()") is True
