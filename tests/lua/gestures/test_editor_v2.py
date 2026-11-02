"""The Gestures editor, version 2: the rings carry the
player's names, one picker with a live filter over every category (the game's emotes from the
client's EMOTE globals, my lines, commands, the suite's actions, the game's controls), a command
slot fired line by line, the new placeholders, and the game's controls refused in combat."""

from harness import WowRuntime
from test_gestures import MOD, E, R, boot, choices, click_choice, emotes, errors, sent

M = f"{MOD}.Model"
TARGET = "Mock.guids = { target = 'Player-1-00000002' }; Mock.unitNames = { target = 'Thalendra' }"


def open_editor(wow: WowRuntime) -> WowRuntime:
    boot(wow)
    wow.slash("/bgest")
    return wow


def labels(wow: WowRuntime) -> list[str]:
    return [c.label for c in choices(wow)]


def test_a_ring_takes_the_players_name_and_keeps_it(wow: WowRuntime):
    open_editor(wow)
    box = wow.eval(f"{E}.nameBoxes[1]")
    assert box.GetText(box) == "Gestures"
    box.SetText(box, "  My greetings ")
    wow.execute(f"local b = {E}.nameBoxes[1]; b:GetScript('OnEnterPressed')(b)")
    assert wow.eval(f"{MOD}.db.global.rings[1].name") == "My greetings"
    # an empty name keeps the old one
    assert wow.eval(f"{E}.RenameRing({MOD}.db.global.rings[2], '   ')") is False
    assert wow.eval(f"{MOD}.db.global.rings[2].name") == "Lines"
    # the open ring shows the name on its hub, the feed names it
    wow.execute(f"{R}.Open()")
    assert wow.eval(f"{R}.kit.title:GetText()") == "My greetings"
    wow.execute(f"{R}.Close()")
    # a ring saved without a name gets the shipped word back; the player's name survives a reload
    wow.execute(f"{MOD}.db.global.rings[3].name = nil; {M}.Ensure({MOD}.db.global)")
    assert wow.eval(f"{MOD}.db.global.rings[3].name") == "Actions"
    fresh = wow.reload()
    fresh.run_frames(5)
    assert fresh.eval(f"{MOD}.db.global.rings[1].name") == "My greetings"
    assert errors(fresh) == []


def test_the_filter_finds_an_emote_by_its_command_and_a_control_by_its_word(wow: WowRuntime):
    open_editor(wow)
    # the client's emotes are read from EMOTE<i>_TOKEN / _CMD<n> (ten in the mock)
    wow.execute(f"{E}.Choose({MOD}.db.global.rings[1], 8)")
    cats = [c.id for c in wow.eval(f"{E}.Catalogue()").values()]
    assert cats == ["gestures", "lines", "commands", "macros", "suite", "game", "other"]
    gestures = wow.eval(f"{E}.Catalogue()[1]")
    assert gestures.total == 60 + 6  # the curated sixty and six more tokens of the client
    # "/" is only in a command: the client's /apologize, a gesture not among the sixty
    wow.execute(f"{E}.SetFilter('/apolog')")
    rows = [c.row for c in choices(wow) if c.row]
    assert [(r.slot.token, r.label, r.group) for r in rows] == [("APOLOGIZE", "Apologize", "all")]
    # a curated gesture by the client's command; a second command of a token (/bravo) too
    wow.execute(f"{E}.SetFilter('/dance')")
    assert [c.row.slot.token for c in choices(wow) if c.row] == ["DANCE"]
    wow.execute(f"{E}.SetFilter('/bravo')")
    assert [c.row.slot.token for c in choices(wow) if c.row] == ["APPLAUD"]
    # typing in the box filters at once, across the categories
    wow.execute(f"{E}.filterBox:SetText('sheathe')")
    assert wow.eval(f"{E}.Filter()") == "sheathe"
    found = [(c.cat, c.label) for c in choices(wow) if c.row]
    assert found == [("game", "Sheathe or draw weapons")]
    click_choice(wow, "Sheathe or draw weapons")
    slot = wow.eval(f"{MOD}.db.global.rings[1].slots[8]")
    assert (slot.kind, slot.id) == ("game", "sheath")
    assert wow.eval(f"{E}.Picker()") is None  # back to the rings
    # the filter stays while the window is open, and goes when it closes
    wow.execute(f"{E}.Choose({MOD}.db.global.rings[1], 7)")
    assert wow.eval(f"{E}.filterBox:GetText()") == "sheathe"
    wow.execute(f"{E}.Close(); {E}.Open()")
    assert wow.eval(f"{E}.Filter()") == ""
    # a suite action without its app is offered, dimmed, with the app it needs
    wow.execute(f"{E}.Choose({MOD}.db.global.rings[3], 1)")
    suite = {c.label: c for c in choices(wow) if c.cat == "suite" and c.row}
    assert suite["Lore here"].row.dim == "Needs Bastian's Orbiter"
    assert suite["Clear the screen"].row.dim is None
    # a category opens and closes by its header
    wow.execute(f"{E}.Toggle('suite')")
    assert not [c for c in choices(wow) if c.cat == "suite" and c.row]
    assert errors(wow) == []


def test_a_line_already_placed_is_offered_again_as_a_copy(wow: WowRuntime):
    open_editor(wow)
    wow.execute(f"{E}.Choose({MOD}.db.global.rings[1], 5)")
    wow.execute(f"{E}.Toggle('lines')")
    assert "Well met" in labels(wow) and "A new line..." in labels(wow)
    click_choice(wow, "Well met")
    slot = wow.eval(f"{MOD}.db.global.rings[1].slots[5]")
    assert (slot.kind, slot.text) == ("line", "Well met, %t.")
    assert (
        wow.eval(f"rawequal({MOD}.db.global.rings[1].slots[5], {MOD}.db.global.rings[2].slots[1])")
        is False
    )
    assert errors(wow) == []


def test_a_command_slot_runs_its_lines_and_refuses_a_protected_one(wow: WowRuntime):
    open_editor(wow)
    wow.execute(TARGET)
    wow.execute(f"{E}.Choose({MOD}.db.global.rings[3], 8)")
    wow.execute(f"{E}.Toggle('commands')")
    click_choice(wow, "A command or macro...")
    assert wow.eval(f"{E}.Form().kind") == "command"
    wow.execute(
        f"{E}.Form().title = 'Party'; "
        f"{E}.Form().text = '#showtooltip\\n/dance\\n/say Hello %t, a fine %h.\\n/cast Hearthstone\\n"
        "/frobnicate\\n/e smiles at %t.'"
    )
    wow.execute("GetGameTime = function() return 8, 15 end")
    assert wow.eval(f"{E}.SaveCommand()") is True
    slot = wow.eval(f"{MOD}.db.global.rings[3].slots[8]")
    assert (slot.kind, slot.title) == ("command", "Party")
    # the editor's row and the ring's wedge show it
    assert wow.eval(f"({M}.Describe({MOD}.db.global.rings[3].slots[8]))") == "Party"
    wow.execute(f"{R}.SetPage(3); {R}.Open()")
    assert wow.eval(f"{R}.kit.items[8].label") == "Party"
    assert wow.eval(f"{R}.Fire(8)") is True
    assert emotes(wow) == [("DANCE", "target")]
    assert sent(wow) == [
        ("Hello Thalendra, a fine morning.", "SAY", None),
        ("smiles at Thalendra.", "EMOTE", None),
    ]
    assert any("/cast is a protected command" in line for line in wow.chat)
    # a command the app does not know goes to the client's chat, which answers an unknown one itself
    assert list(wow.eval("Mock.chatSent").values()) == ["/frobnicate"]
    # an addon's registered slash command runs (here the app's own: the next ring)
    wow.execute(
        f"{MOD}.db.global.rings[3].slots[7] = {{ kind = 'command', title = 'Next', text = '/bgest next' }}"
    )
    wow.execute(f"{R}.SetPage(3); {R}.Open()")
    assert wow.eval(f"{R}.Fire(7)") is True
    assert wow.eval(f"{R}.Page()") == 1
    assert errors(wow) == []


def test_the_new_placeholders_fill_and_ask_the_client_only_when_used(wow: WowRuntime):
    boot(wow)
    fill = f"{M}.Fill"
    ctx = (
        "{ myRace = 'Dwarf', myClass = 'Paladin', faction = 'Alliance', level = 42, sex = 'she', "
        "daytime = 'night', guild = 'Wardens' }"
    )
    assert wow.eval(f"{fill}('%m %k of the %f, %l, %e; %g at %h', {ctx})") == (
        "Dwarf Paladin of the Alliance, 42, she; Wardens at night"
    )
    assert wow.eval(f"{fill}('%g!', {{}})") == "!"  # unknown: nothing, never 0
    for hour, word in (
        (4, "night"),
        (5, "morning"),
        (12, "afternoon"),
        (17, "evening"),
        (21, "night"),
    ):
        assert wow.eval(f"{M}.DayTime({hour})") == word
    assert wow.eval(f"{M}.DayTime(nil)") is None
    assert wow.eval(f"{M}.SexWord(3)") == "she" and wow.eval(f"{M}.SexWord(1)") is None
    # from the client: a line with the new placeholders, fired from the ring
    wow.execute(TARGET)
    wow.execute(
        "UnitSex = function() return 2 end; GetGameTime = function() return 19, 5 end; "
        "GetGuildInfo = function(unit) if unit == 'target' then return 'Wardens' end end"
    )
    wow.execute(
        f"{MOD}.db.global.rings[2].slots[6] = {{ kind = 'line', title = 'Me', channel = 'SAY', "
        "text = '%n, a %m %k of the %f (%l): %e greets %t of %g this %h.' }"
    )
    wow.execute(f"{R}.SetPage(2); {R}.Open()")
    assert wow.eval(f"{R}.Fire(6)") is True
    assert sent(wow)[-1][0] == (
        "Mockchar, a Human Mage of the Alliance (12): he greets Thalendra of Wardens this evening."
    )
    # a line without them asks the client nothing of them (the unmocked stubs would raise)
    wow.execute(
        "UnitSex = function() error('asked') end; GetGameTime = function() error('asked') end"
    )
    wow.execute(f"{R}.Open()")
    assert wow.eval(f"{R}.Fire(1)") is True
    assert sent(wow)[-1][0] == "Well met, Thalendra."
    assert errors(wow) == []


def test_a_game_control_runs_out_of_combat_only(wow: WowRuntime):
    boot(wow)
    wow.execute(
        "Mock.sheathed = 0; ToggleSheath = function() Mock.sheathed = Mock.sheathed + 1 end"
    )
    wow.execute(f"{MOD}.db.global.rings[3].slots[1] = {{ kind = 'game', id = 'sheath' }}")
    wow.execute(f"{MOD}.db.global.rings[3].slots[2] = {{ kind = 'game', id = 'ui' }}")
    wow.execute(f"{R}.SetPage(3); {R}.Open()")
    assert wow.eval(f"{R}.kit.items[1].label") == "Sheathe or draw weapons"
    assert wow.eval(f"{R}.Fire(1)") is True
    assert wow.eval("Mock.sheathed") == 1
    # the interface off and on again
    wow.execute(f"{R}.Open()")
    assert wow.eval(f"{R}.Fire(2)") is True
    assert wow.eval("UIParent:IsShown()") is False
    wow.execute("UIParent:Show()")
    # in combat: refused, with a line that says why
    wow.execute("Mock.SetCombat(true)")
    wow.execute(f"{R}.Open()")
    assert wow.eval(f"{R}.Fire(1)") is False
    assert wow.eval("Mock.sheathed") == 1
    assert any("Sheathe or draw weapons: not in combat." in line for line in wow.chat)
    wow.execute("Mock.SetCombat(false)")
    # a control the client does not offer is dimmed on the ring and in the picker
    wow.execute("ShowHelm = nil")
    assert wow.eval(f"({R}.Available({{ kind = 'game', id = 'helm' }}))") is False
    wow.slash("/bgest")
    wow.execute(f"{E}.Choose({MOD}.db.global.rings[3], 3); {E}.SetFilter('helm')")
    helm = next(c for c in choices(wow) if c.row and c.cat == "game")
    assert helm.row.dim == "Not in this client"
    assert errors(wow) == []
