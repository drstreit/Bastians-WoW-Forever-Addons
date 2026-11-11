"""Bastian's Gestures (gestures.md, plan-launch-review R5.1 and R5.2): the model (placeholders,
the split, the wedge under the cursor), the ring on the key (a gesture, a
line with its language, a sub-ring, a dimmed action), the editor,
and life with the clear-screen key."""

from harness import WowRuntime

CORE, DATA, GESTURES = "Bastians_Core", "Bastians_Data", "Bastians_Gestures"
VOICE, MAP, ROUTE, NOTES, QUESTS = (
    "Bastians_Voice",
    "Bastians_Map",
    "Bastians_Route",
    "Bastians_Notes",
    "Bastians_Quests",
)
MOD = "Bastians:GetModule('Gestures')"
M = f"{MOD}.Model"
R = f"{MOD}.Ring"
E = f"{MOD}.Editor"
KIT = "Bastians.UI.Ring"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, GESTURES)))
    wow.run_frames(5)
    return wow


def errors(wow: WowRuntime) -> list[str]:
    return wow.errors + [
        line.text
        for line in wow.eval("Bastians:GetLog()").values()
        if line.level == "error" and "registered no data" not in line.text
    ]


def emotes(wow: WowRuntime) -> list[tuple]:
    return [(e.token, e.target) for e in wow.eval("Mock.emotes").values()]


def sent(wow: WowRuntime) -> list[tuple]:
    return [(s.text, s.type, s.language) for s in wow.eval("Mock.sentChat").values()]


def choices(wow: WowRuntime) -> list:
    """The picker's buttons drawn now (the editor v2): label, category, row, button."""
    return list(wow.eval(f"{E}.Choices()").values())


def click_choice(wow: WowRuntime, label: str) -> None:
    b = next(c.button for c in choices(wow) if c.label == label)
    b.Click(b)


def cursor_on(wow: WowRuntime, index: int) -> None:
    """Puts the cursor over wedge `index` of the open ring (the hub's centre plus the slot)."""
    wow.execute(
        f"""local kit = {R}.kit
        local cx, cy = kit.cx, kit.cy
        local dx, dy = Bastians.UI.Ring.Slot({index}, kit.opts.wedges, kit.opts.radius)
        local s = UIParent:GetEffectiveScale()
        local fs = kit.frame:GetScale() or 1
        Mock.cursorX, Mock.cursorY = (cx + dx * fs) * s, (cy + dy * fs) * s"""
    )


def test_the_model_fills_splits_and_finds_the_wedge(wow: WowRuntime):
    boot(wow)
    fill = f"{M}.Fill"
    ctx = "{ target = 'Thalendra', zone = 'Elwynn Forest', area = 'Goldshire', race = 'Night Elf' }"
    assert wow.eval(f"{fill}('Well met, %t. From %z to %a.', {ctx})") == (
        "Well met, Thalendra. From Elwynn Forest to Goldshire."
    )
    assert wow.eval(f"{fill}('%rp or %r', {ctx})") == " or Night Elf"  # unknown value: nothing
    assert wow.eval(f"{fill}('%t!', {{}})") == "!"  # never "0"
    assert wow.eval(f"{fill}('100%x stays', {{}})") == "100%x stays"  # not a placeholder
    assert wow.eval(f"{fill}('%tsomething', {ctx})") == "Thalendrasomething"
    parts = list(wow.eval(f"{M}.Split(string.rep('word ', 60))").values())
    assert len(parts) == 2 and all(len(p.encode()) <= 255 for p in parts)
    assert parts[0].endswith(" (1/2)") and parts[1].endswith(" (2/2)")
    assert list(wow.eval(f"{M}.Split('short')").values()) == ["short"]
    # the wedge under the cursor: 8 wedges, the first at the top, clockwise; the hub and the rim give nil
    hov = f"{M}.Hovered"
    assert wow.eval(f"{hov}(0, 80, 8, 38, 126)") == 1
    assert wow.eval(f"{hov}(80, 0, 8, 38, 126)") == 3
    assert wow.eval(f"{hov}(0, -80, 8, 38, 126)") == 5
    assert wow.eval(f"{hov}(-80, 0, 8, 38, 126)") == 7
    assert wow.eval(f"{hov}(0, 10, 8, 38, 126)") is None
    assert wow.eval(f"{hov}(0, 200, 8, 38, 126)") is None
    assert wow.eval(f"{KIT}.Hovered(-57, 57, 8, 38, 126)") == 8
    assert len(wow.eval(f"{M}.FindEmotes('wa')")) >= 2  # Wave, Wait, ...
    assert errors(wow) == []


def test_the_addon_loads_alone_and_with_every_neighbour(wow: WowRuntime):
    boot(wow, CORE, GESTURES)
    assert wow.eval(f"{MOD}:IsEnabled()") is True
    rings = list(wow.eval(f"{MOD}.db.global.rings").values())
    assert [r.id for r in rings] == ["gestures", "lines", "actions"]
    assert errors(wow) == []
    wow2 = WowRuntime(client=wow.client)
    boot(wow2, CORE, DATA, QUESTS, MAP, ROUTE, NOTES, VOICE, GESTURES)
    assert wow2.eval(f"{MOD}:IsEnabled()") is True
    # the Notes actions are there, the Orbiter's play action too; Route's home action since S6
    assert wow2.eval(f"{R}.Available({{ kind = 'action', id = 'note' }})") is True
    assert wow2.eval(f"{R}.Available({{ kind = 'action', id = 'home' }})") is True
    assert wow2.eval(f"{R}.Available({{ kind = 'action', id = 'heard' }})") is True
    assert wow2.eval(f"{R}.Available({{ kind = 'action', id = 'tracker' }})") is True
    wow2.execute(f"{MOD}:Disable()")
    assert wow2.eval(f"{R}.IsOpen()") is False
    wow2.execute(f"{MOD}:Enable()")
    assert errors(wow2) == []


def test_the_key_opens_the_ring_at_the_cursor_and_fires_a_gesture(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.cursorX, Mock.cursorY = 700, 400")
    wow.execute(f"{R}.Key('down')")
    assert wow.eval(f"{R}.IsOpen()") is True
    cx, cy = wow.eval(f"{R}.kit.cx"), wow.eval(f"{R}.kit.cy")
    assert abs(cx - 700) < 1 and abs(cy - 400) < 1
    items = wow.eval(f"{R}.kit.items")
    assert items[1].label == "Wave" and items[4].sub is True
    cursor_on(wow, 1)
    assert wow.eval(f"{R}.kit:HoveredIndex()") == 1
    wow.execute(f"{R}.Key('up')")
    assert emotes(wow) == [("WAVE", None)]
    assert wow.eval(f"{R}.IsOpen()") is False
    # with a target the gesture goes at it
    wow.execute(
        "Mock.guids = { target = 'Player-1-00000002' }; Mock.unitNames = { target = 'Thalendra' }"
    )
    wow.execute(f"{R}.Key('down')")
    cursor_on(wow, 2)
    wow.execute(f"{R}.Key('up')")
    assert emotes(wow)[-1] == ("BOW", "target")
    # the key released off the ring fires nothing
    wow.execute(f"{R}.Key('down')")
    wow.execute("Mock.cursorX, Mock.cursorY = 10, 10")
    wow.execute(f"{R}.Key('up')")
    assert len(emotes(wow)) == 2 and wow.eval(f"{R}.IsOpen()") is False
    # near the screen's edge the ring stays inside
    wow.execute("Mock.cursorX, Mock.cursorY = 5, 5")
    wow.execute(f"{R}.Key('down')")
    cx, cy = wow.eval(f"{R}.kit.cx"), wow.eval(f"{R}.kit.cy")
    assert cx > 100 and cy > 100
    wow.execute(f"{R}.Close()")
    assert errors(wow) == []


def test_a_line_fills_its_placeholders_and_speaks_a_known_language(wow: WowRuntime):
    boot(wow)
    wow.execute(
        "Mock.guids = { target = 'Player-1-00000002' }; Mock.unitNames = { target = 'Thalendra' }"
    )
    wow.execute("Mock.languages = { { 'Common', 7 }, { 'Darnassian', 2 } }")
    wow.execute(f"{R}.SetPage(2)")
    wow.execute(f"{R}.Key('down')")
    assert wow.eval(f"{R}.kit.items[1].label") == "Well met"
    cursor_on(wow, 1)
    wow.execute(f"{R}.Key('up')")
    assert sent(wow) == [("Well met, Thalendra.", "SAY", None)]
    # a line in a language the character knows goes in it; an unknown language falls to Common
    wow.execute(
        f"{MOD}.db.global.rings[2].slots[6] = {{ kind = 'line', title = 'Stars', "
        "text = 'May the stars guide you, %t.', channel = 'SAY', language = 'Darnassian' }"
    )
    wow.execute(
        f"{MOD}.db.global.rings[2].slots[7] = {{ kind = 'line', title = 'Orcish', "
        "text = 'Lok-tar.', channel = 'YELL', language = 'Orcish' }"
    )
    wow.execute(f"{R}.Key('down')")
    cursor_on(wow, 6)
    wow.execute(f"{R}.Key('up')")
    assert sent(wow)[-1] == ("May the stars guide you, Thalendra.", "SAY", "Darnassian")
    wow.execute(f"{R}.Key('down')")
    cursor_on(wow, 7)
    wow.execute(f"{R}.Key('up')")
    assert sent(wow)[-1] == ("Lok-tar.", "YELL", None)
    # an emote line goes as EMOTE; the long one splits
    wow.execute(f"{R}.Key('down')")
    cursor_on(wow, 2)
    wow.execute(f"{R}.Key('up')")
    assert sent(wow)[-1][1] == "EMOTE"
    wow.execute(
        f"{MOD}.db.global.rings[2].slots[8] = {{ kind = 'line', title = 'Long', "
        "text = string.rep('A long tale. ', 30), channel = 'SAY' }"
    )
    before = len(sent(wow))
    wow.execute(f"{R}.Key('down')")
    cursor_on(wow, 8)
    wow.execute(f"{R}.Key('up')")
    assert len(sent(wow)) - before == 2
    assert errors(wow) == []


def test_the_wheel_cycles_the_rings_and_a_wedge_opens_its_sub_ring(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{R}.Key('down')")
    assert wow.eval(f"{R}.Page()") == 1
    wow.execute(f"{R}.Cycle(1)")  # wheel up: the next ring to the right
    assert wow.eval(f"{R}.Page()") == 2 and wow.eval(f"{R}.kit.items[1].label") == "Well met"
    wow.execute(f"{R}.Cycle(-1)")
    assert wow.eval(f"{R}.Page()") == 1
    # the Greetings wedge opens its ring in place; the hub goes back
    wow.execute(f"{R}.Fire(4)")
    assert wow.eval(f"{R}.IsOpen()") is True
    assert wow.eval(f"{R}.kit.items[1].label") == "Hail"
    assert wow.eval(f"{R}.Current().name") == "Greetings"
    cursor_on(wow, 4)
    wow.execute(f"{R}.Key('up')")
    assert emotes(wow) == [("HUG", None)]
    wow.execute(f"{R}.Key('down')")
    wow.execute(f"{R}.Fire(4)")
    wow.execute(f"{R}.kit.opts.onHub('LeftButton')")
    assert wow.eval(f"{R}.Current().id") == "gestures"
    # "only closing on key press". The centre goes back, it never closes,
    # and the game's close-all list (Escape) does not hold the ring
    wow.execute(f"{R}.kit.opts.onHub('LeftButton')")
    assert wow.eval(f"{R}.IsOpen()") is True
    assert wow.eval("tContains(UISpecialFrames, 'BastiansGesturesRing')") is not True
    wow.execute(f"{R}.Close()")
    # the toggle setting: the key opens and closes, a click fires
    wow.execute(f"{MOD}.db.profile.toggle = true")
    wow.execute(f"{R}.Key('down')")
    wow.execute(f"{R}.Key('up')")
    assert wow.eval(f"{R}.IsOpen()") is True
    wow.execute(f"{R}.kit.wedges[1]:Click()")
    assert emotes(wow)[-1] == ("WAVE", None)
    assert wow.eval(f"{R}.IsOpen()") is True  # it stays until the key is pressed again
    wow.execute(f"{R}.Key('down')")
    assert wow.eval(f"{R}.IsOpen()") is False
    assert errors(wow) == []


def test_an_action_without_its_app_is_dimmed_and_does_nothing(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{R}.SetPage(3)")
    wow.execute(f"{R}.Key('down')")
    items = wow.eval(f"{R}.kit.items")
    assert items[1].label == "Lore here" and items[1].disabled is True
    assert items[1].tip == "Needs Bastian's Orbiter"
    assert items[2].label == "Clear the screen" and items[2].disabled is None
    assert wow.eval(f"{R}.Fire(1)") is False and wow.eval(f"{R}.IsOpen()") is True
    # clear the screen is Core's: it works alone; the screenshot hides, shoots, shows
    assert wow.eval(f"{R}.Fire(2)") is True
    assert wow.eval("Bastians.UI.Screen.Hidden()") is True
    wow.execute("Bastians.UI.Screen.Toggle()")
    wow.execute(f"{R}.Key('down')")
    assert wow.eval(f"{R}.Fire(3)") is True
    assert wow.eval("Bastians.UI.Screen.Hidden()") is True
    wow.run_frames(3)
    assert wow.eval("Mock.screenshots") == 1
    assert wow.eval("Bastians.UI.Screen.Hidden()") is False
    assert wow.eval(f"{R}.Pending()") is False
    assert errors(wow) == []


def buff(wow: WowRuntime, unit: str, name: str, spell: str = "Mark of the Wild") -> None:
    wow.execute(
        f"""Mock.unitNames = Mock.unitNames or {{}}
        Mock.unitNames['{unit}'] = '{name}'
        Mock.guids = Mock.guids or {{}}
        Mock.guids['{unit}'] = 'Player-1-' .. '{name}'
        Mock.Fire('UNIT_AURA', 'player', {{ addedAuras = {{ {{ sourceUnit = '{unit}', isHelpful = true,
          name = '{spell}' }} }} }})"""
    )


def test_the_editor_changes_a_slot_and_the_change_survives_a_reload(wow: WowRuntime):
    boot(wow)
    wow.slash("/bgest")
    assert wow.eval(f"{E}.IsShown()") is True
    rows = list(wow.eval(f"{E}.Rows()").values())
    assert len(rows) == 24  # three rings of eight
    assert rows[0].slot.token == "WAVE" and rows[8].slot.kind == "line"
    # slot 6 of the Lines ring becomes a line of my own: the picker (editor v2; the slot menu of
    # version one is gone), its "A new line..." row opens the form
    wow.execute(f"{E}.Choose({MOD}.db.global.rings[2], 6)")
    assert wow.eval(f"{E}.Expanded('lines')") is True  # the slot's own category opens first
    click_choice(wow, "A new line...")
    assert wow.eval(f"{E}.Form().index") == 6
    wow.execute(f"{E}.Form().title = 'Stars'; {E}.Form().text = 'May the stars guide you, %t.'")
    wow.execute(f"{E}.Form().channel = 'EMOTE'")
    assert wow.eval(f"{E}.SaveLine()") is True
    slot = wow.eval(f"{MOD}.db.global.rings[2].slots[6]")
    assert (slot.kind, slot.title, slot.channel) == ("line", "Stars", "EMOTE")
    # the picker filters and picks a gesture
    wow.execute(f"{E}.Choose({MOD}.db.global.rings[1], 8)")
    assert wow.eval(f"{E}.Picker().index") == 8
    wow.execute(f"{E}.SetFilter('danc')")
    tokens = [c.row.slot.token for c in choices(wow) if c.row and c.row.slot]
    assert tokens == ["DANCE"]
    assert wow.eval(f"{E}.PickEmote('DANCE')") is True
    assert wow.eval(f"{MOD}.db.global.rings[1].slots[8].token") == "DANCE"
    # a sub-ring from the picker, entered and left
    wow.execute(f"{E}.SetFilter('')")
    wow.execute(f"{E}.Choose({MOD}.db.global.rings[3], 7)")
    wow.execute(f"{E}.Toggle('other')")
    click_choice(wow, "A ring of its own")
    assert wow.eval(f"{MOD}.db.global.rings[3].slots[7].kind") == "ring"
    assert len(wow.eval(f"{E}.Path()")) == 1
    wow.execute(f"{E}.Back()")
    assert len(wow.eval(f"{E}.Path()")) == 0
    # the change survives a reload; Default rings restores the shipped ones
    fresh = wow.reload()
    fresh.run_frames(5)
    assert fresh.eval(f"{MOD}.db.global.rings[2].slots[6].title") == "Stars"
    assert fresh.eval(f"{MOD}.db.global.rings[1].slots[8].token") == "DANCE"
    fresh.execute(f"{E}.Open(); {E}.Defaults()")
    assert fresh.eval(f"{MOD}.db.global.rings[1].slots[8].token") == "BYE"
    assert errors(fresh) == []


def test_a_ring_the_key_toggles_is_permanent(wow: WowRuntime):
    """ "It should be permanent, currently it gets destroyed on reload
    and in many other context. Should be a toggle per key, but no way to automatically get hidden
    again"."""
    boot(wow)
    wow.execute(f"{MOD}.db.profile.toggle = true")
    wow.execute("Mock.cursorX, Mock.cursorY = 400, 300")
    wow.execute(f"{R}.Key('down')")
    wow.execute(f"{R}.Cycle(1)")
    at = (wow.eval(f"{R}.kit.cx"), wow.eval(f"{R}.kit.cy"))

    def there(w: WowRuntime) -> bool:
        return (
            w.eval(f"{R}.IsOpen()") is True
            and w.eval(f"{R}.Page()") == 2
            and (w.eval(f"{R}.kit.cx"), w.eval(f"{R}.kit.cy")) == at
            and w.eval(f"{R}.kit.items")[1].label == "Well met"
        )

    assert there(wow)
    wow.execute("Mock.cursorX, Mock.cursorY = 900, 600")  # it comes back where it was, not here
    # the clear-screen key hides it with the screen and brings it back, as a window
    wow.execute("Bastians.UI.Screen.Toggle()")
    assert wow.eval(f"{R}.IsOpen()") is False
    wow.execute("Bastians.UI.Screen.Toggle()")
    assert there(wow)
    # the addon off and on
    wow.execute(f"{MOD}:Disable()")
    assert wow.eval(f"{R}.IsOpen()") is False
    wow.execute(f"{MOD}:Enable()")
    assert there(wow)
    # a reload
    fresh = wow.reload()
    fresh.run_frames(5)
    assert there(fresh)
    # only the key closes it, and then it stays closed
    fresh.execute(f"{R}.Key('down')")
    assert fresh.eval(f"{R}.IsOpen()") is False
    assert fresh.eval(f"{MOD}.db.profile.shown") is None
    again = fresh.reload()
    again.run_frames(5)
    assert again.eval(f"{R}.IsOpen()") is False
    assert errors(wow) == [] and errors(fresh) == [] and errors(again) == []


def test_a_ring_held_on_the_key_is_not_kept(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{R}.Key('down')")
    assert wow.eval(f"{R}.IsOpen()") is True
    assert wow.eval(f"{MOD}.db.profile.shown") is None
    # a ring left open by the toggle is forgotten once the setting is off and the key lets go
    wow.execute(f"{R}.Close(); {MOD}.db.profile.toggle = true; {R}.Key('down')")
    assert wow.eval(f"{MOD}.db.profile.shown") is not None
    wow.execute(f"{MOD}.db.profile.toggle = false")
    wow.execute("Mock.cursorX, Mock.cursorY = 10, 10")
    wow.execute(f"{R}.Key('down'); {R}.Key('up')")
    assert wow.eval(f"{R}.IsOpen()") is False
    fresh = wow.reload()
    fresh.run_frames(5)
    assert fresh.eval(f"{R}.IsOpen()") is False
    assert errors(wow) == [] and errors(fresh) == []


def test_the_rings_secure_buttons_come_back_with_the_interface(wow: WowRuntime):
    """The interface hidden and shown (Alt+Z, a cinematic) hides the ring's frame and shows it
    again: the kit lays the secure buttons again, they used to stay away."""
    boot(wow)
    wow.execute(
        f"""local kit = {R}.kit
        kit:SetItems({{ {{ label = 'Macro', secure = {{ type = 'macro', macro = 'Mount up' }} }} }})
        kit:OpenAt(500, 400)"""
    )
    assert wow.eval(f"{R}.kit:Secure(1):IsShown()") is True
    wow.execute(f"{R}.kit.frame:Hide()")
    assert wow.eval(f"{R}.kit:Secure(1):IsShown()") is False
    wow.execute(f"{R}.kit.frame:Show()")
    assert wow.eval(f"{R}.kit:Secure(1):IsShown()") is True
    assert errors(wow) == []


def test_the_clear_screen_key_closes_the_ring_and_the_feed_names_the_ring(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{R}.Key('down')")
    assert wow.eval(f"{R}.IsOpen()") is True
    wow.execute("Bastians.UI.Screen.Toggle()")
    assert wow.eval(f"{R}.IsOpen()") is False and wow.eval(f"{R}.HiddenByKey()") is True
    assert wow.eval(f"{R}.Open()") is False
    wow.execute("Bastians.UI.Screen.Toggle()")
    assert wow.eval(f"{R}.HiddenByKey()") is False
    assert wow.eval(f"{R}.Open()") is True
    wow.execute(f"{R}.Close()")
    # unticked on the page: the ring stays usable
    wow.execute("Bastians:GetModule('Core').db.profile.screen_Gestures = false")
    wow.execute("Bastians.UI.Screen.Toggle()")
    assert wow.eval(f"{R}.HiddenByKey()") is False
    wow.execute("Bastians.UI.Screen.Toggle()")
    # the feed
    obj = wow.eval("LibStub('LibDataBroker-1.1'):GetDataObjectByName(\"Bastian's Gestures\")")
    assert obj is not None and obj.text == "Gestures"
    wow.execute(f"{R}.Cycle(1)")
    wow.advance(1)
    wow.run_frames(3)
    obj = wow.eval("LibStub('LibDataBroker-1.1'):GetDataObjectByName(\"Bastian's Gestures\")")
    assert obj.text == "Lines"
    assert errors(wow) == []
