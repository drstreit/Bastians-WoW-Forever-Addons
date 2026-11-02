"""The welcome v2: at
every login until "Don't show again" (the General page turns it back on), never in combat, not
after an update with news; a returning player with a way opens on the first five minutes; five
panes: choose your way (two equal cards with pictures), your pack, the first five minutes (steps
that tick from the suite's events, per character), roleplay, where things are."""

from harness import WowRuntime

CORE, DATA, QUESTS, MAP, VOICE, GESTURES = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Map",
    "Bastians_Voice",
    "Bastians_Gestures",
)
WELCOME = "Bastians.UI.Welcome"
SETTINGS = "Bastians.UI.Settings"
GLOBAL = "Bastians:GetModule('Core').db.global"


def shown(wow: WowRuntime) -> bool:
    return wow.eval(f"{WELCOME}.IsShown()") is True


def widgets(wow: WowRuntime) -> list:
    return list(wow.eval(f"{WELCOME}.canvas.widgets").values())


def steps(wow: WowRuntime, way: str) -> dict[str, bool]:
    return {s.id: s.done for s in wow.eval(f"{WELCOME}.Steps('{way}')").values()}


def test_the_welcome_shows_at_every_login_until_switched_off(wow: WowRuntime):
    wow.start(CORE, DATA, QUESTS)
    wow.run_frames(5)
    assert not shown(wow)
    wow.advance(4)  # News.Check runs three seconds after login
    assert shown(wow) and wow.eval(f"{WELCOME}.page") == 1
    wow.execute(f"{WELCOME}.Hide()")
    fresh = wow.reload()
    fresh.advance(4)
    assert fresh.eval(f"{WELCOME}.IsShown()") is True  # again: every login
    off = fresh.eval(f"{WELCOME}.footer.off")
    off.Click(off)  # Don't show again
    assert fresh.eval(f"{WELCOME}.IsShown()") is False
    assert fresh.eval(f"{GLOBAL}.welcomeAtLogin") is False
    again = fresh.reload()
    again.advance(4)
    assert again.eval(f"{WELCOME}.IsShown()") is False
    again.slash("/bastians welcome")  # still there on demand
    assert again.eval(f"{WELCOME}.IsShown()") is True
    again.execute(f"{GLOBAL}.welcomeAtLogin = true")  # the General page's switch
    last = again.reload()
    last.advance(4)
    assert last.eval(f"{WELCOME}.IsShown()") is True
    assert last.errors == []


def test_in_combat_the_welcome_waits_for_the_end_of_combat(wow: WowRuntime):
    wow.start(CORE)
    wow.run_frames(5)
    wow.execute("Mock.SetCombat(true)")
    wow.advance(4)
    assert not shown(wow)
    wow.execute("Mock.SetCombat(false)")  # PLAYER_REGEN_ENABLED
    assert shown(wow)
    assert wow.errors == []


def test_after_an_update_with_news_the_welcome_waits_a_login(wow: WowRuntime):
    wow.start(CORE)
    wow.run_frames(5)
    assert wow.eval(f"{WELCOME}.AtLogin(true)") is False
    assert wow.eval(f"{WELCOME}.AtLogin(false)") is True


def test_the_cards_are_two_equal_ways_and_choosing_applies_the_preset(wow: WowRuntime):
    wow.start(CORE, DATA, QUESTS, MAP, VOICE)
    wow.run_frames(5)
    cards = list(wow.eval(f"{WELCOME}.Cards()").values())
    assert [c.id for c in cards] == ["wanderer", "scholar"]
    assert all(len(list(c.gets.values())) == 4 for c in cards)
    assert cards[0].picture.endswith("_wanderer") and cards[1].picture.endswith("_scholar")
    assert wow.eval(f"{WELCOME}.RaceKey('Scourge', 'Horde')") == "undead"
    assert (
        wow.eval(f"{WELCOME}.RaceKey('BloodElf', 'Horde')") == "orc"
    )  # beyond the eight: the faction's
    assert wow.eval(f"{WELCOME}.RaceKey(nil, nil)") == "human"
    assert (cards[0].tone, cards[1].tone) == ("wayWanderer", "wayScholar")
    wow.execute(f"{WELCOME}.Show(1)")
    drawn = [w for w in widgets(wow) if getattr(getattr(w, "spec", None), "id", None) is not None]
    assert [w.spec.id for w in drawn] == ["wanderer", "scholar"]
    drawn[0].Click(drawn[0])
    assert wow.eval(f"{SETTINGS}.PlayId()") == "wanderer"
    assert wow.eval("Bastians:GetModule('Quests'):IsEnabled()") is False
    assert wow.eval("Bastians:GetModule('Voice.Talk'):IsEnabled()") is True
    assert next(iter(wow.eval(f"{WELCOME}.Cards()").values())).chosen
    assert wow.eval(f"{WELCOME}.footer.back:IsShown()") is False
    assert wow.eval(f"{WELCOME}.footer.next:IsShown()") is True
    assert wow.eval(f"{WELCOME}.footer.off:IsShown()") is True
    assert wow.errors == []


def test_a_returning_player_with_a_way_opens_on_the_first_five_minutes(wow: WowRuntime):
    wow.start(CORE, DATA, QUESTS, MAP, VOICE)
    wow.run_frames(5)
    wow.execute(f"{SETTINGS}.ApplyPlay('scholar')")
    wow.advance(4)
    assert shown(wow) and wow.eval(f"{WELCOME}.page") == 3
    texts = [w.text for w in widgets(wow) if getattr(w, "text", None)]
    assert "Your first five minutes" in texts and "Look something up" in texts
    header = next(w for w in widgets(wow) if getattr(w, "way", None))
    assert header.way == "scholar"
    assert wow.errors == []


def test_the_steps_tick_from_the_suites_events_and_stay_per_character(wow: WowRuntime):
    wow.start(CORE, DATA, QUESTS, MAP, VOICE, GESTURES)
    wow.run_frames(5)
    assert steps(wow, "wanderer") == {"hear": False, "greet": False, "clear": False, "talk": False}
    wow.execute("Bastians:Fire('BASTIANS_VOICE_CHANGED')")
    wow.execute("Bastians:Fire('BASTIANS_SUITE_HIDDEN', false)")  # shown again: no tick
    assert steps(wow, "wanderer")["hear"] and not steps(wow, "wanderer")["clear"]
    wow.execute("Bastians.UI.Screen.Toggle()")
    wow.execute(
        "Bastians:GetModule('Gestures').Ring.SetPage(1) ; Bastians:GetModule('Gestures').Ring.Open()"
    )
    wow.execute("Bastians:GetModule('Gestures').Ring.Fire(1)")  # a wave
    assert wow.eval(f"{WELCOME}.AllDone('wanderer')") is True
    wow.execute("Bastians:Fire('BASTIANS_ROUTE_CHANGED', nil)")
    assert not steps(wow, "scholar")["route"]
    wow.execute("Bastians:Fire('BASTIANS_ROUTE_CHANGED', { goal = 'x' })")
    wow.execute("Bastians:Fire('BASTIANS_PAGE_SHOWN', 'npc:1')")
    assert steps(wow, "scholar") == {"lookup": True, "route": True, "worth": False}
    fresh = wow.reload()
    assert fresh.eval(f"{WELCOME}.Steps('scholar')[2].done") is True  # kept over a reload
    # per character: the ticks live in Core's character saved variables, not the account's
    assert fresh.eval("Bastians:GetModule('Core').db.char.welcomeSteps.route") is True
    assert fresh.eval(f"{GLOBAL}.welcomeSteps") is None
    assert wow.errors == []


def test_the_third_pane_glows_when_all_is_done_and_try_it_greets(wow: WowRuntime):
    wow.start(CORE, DATA, QUESTS, MAP, VOICE)
    wow.run_frames(5)
    wow.execute(f"{SETTINGS}.ApplyPlay('wanderer')")
    wow.execute(f"{WELCOME}.Show(3)")
    assert wow.eval(f"{WELCOME}.Try('greet')") is True
    assert [e.token for e in wow.eval("Mock.emotes").values()][-1] == "WAVE"
    wow.execute(f"{WELCOME}.Mark('hear') ; {WELCOME}.Mark('clear')")
    texts = [w.text for w in widgets(wow) if getattr(w, "text", None)]
    assert "You know the way." in texts
    assert wow.eval(f"{WELCOME}.footer.next.spec.on") is True
    assert wow.errors == []


def test_the_roleplay_pane_says_what_is_missing(wow: WowRuntime):
    wow.start(CORE, DATA, VOICE)
    wow.run_frames(5)
    rows = {r.id: r for r in wow.eval(f"{WELCOME}.Roleplay()").values()}
    assert rows["voice"].on is True and rows["voice"].needs is None
    assert rows["gestures"].on is False and "Gestures" in rows["gestures"].needs
    assert rows["screen"].on is True
    wow.execute(f"{WELCOME}.Show(4)")
    wow.execute(f"{WELCOME}.ShowPane(5)")
    assert wow.eval(f"{WELCOME}.footer.done:IsShown()") is True
    assert wow.eval(f"{WELCOME}.footer.next:IsShown()") is False
    assert wow.errors == []


def test_the_pack_pane_lists_the_way_apps_settings_and_keys(wow: WowRuntime):
    wow.start(CORE, DATA, QUESTS, MAP, VOICE)
    wow.run_frames(5)
    wow.execute(f"{SETTINGS}.ApplyPlay('wanderer')")
    wow.execute(f"{WELCOME}.Show(2)")
    texts = [w.text for w in widgets(wow) if getattr(w, "text", None)]
    assert "Your pack" in texts and "Your keys" in texts and "Look" in texts
    assert "Bastian's Map" in texts or "Map" in texts
    assert "Quests" not in texts  # off in the Wanderer's pack
    packed = wow.eval(f"{WELCOME}.PackSettings('wanderer')").values()
    keys = [s["def"].key for s in packed]  # `def` is a Python keyword: read it by name
    assert "minimapPins" in keys and "wordsReminder" in keys
    assert wow.errors == []


def test_the_scholar_sees_the_information_layer_and_the_wanderer_a_clear_view(wow: WowRuntime):
    wow.start(CORE, DATA, QUESTS, MAP, VOICE)
    wow.run_frames(5)
    assert (
        wow.eval(f"{WELCOME}.InfoLabel({WELCOME}.INFO[1])")
        == "Highpeak  1860 yd high, 4200 yd away"
    )
    assert wow.eval(f"{WELCOME}.InfoLabel({WELCOME}.INFO[4])") is None  # a tile without words
    px = wow.eval(
        f"{{ {WELCOME}.Place(0.5, 0.5, {{ x0 = 0, x1 = 1, y0 = 0.25, y1 = 0.75 }}, 200, 100) }}"
    )
    assert list(px.values()) == [100, 50]
    assert (
        wow.eval(f"{WELCOME}.Place(0.5, 0.9, {{ x0 = 0, x1 = 1, y0 = 0.25, y1 = 0.75 }}, 200, 100)")
        is None
    )
    wow.execute(f"{WELCOME}.Show(1)")
    cards = {w.spec.id: w for w in widgets(wow) if getattr(getattr(w, "spec", None), "id", None)}
    assert cards["wanderer"].layer is None  # the Wanderer's view stays clear
    marks = list(cards["scholar"].layer.marks.values())
    kinds = {m.kind for m in marks if m.kind}
    assert kinds == {"peak", "herb", "quest", "flight"}
    labels = [m.text for m in marks if getattr(m, "text", None)]
    assert "Peacebloom  210 yd away" in labels and len(labels) == 3
    for m in marks:
        if m.kind in ("herb", "quest", "flight"):
            assert m.GetWidth(m) <= 12  # small
    assert wow.errors == []
