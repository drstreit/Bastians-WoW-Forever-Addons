"""The owner's retail follow-ups to the Gestures editor v2 (01.11.2026, late; gestures.md): the
form's hints step aside for typed text, the client's own commands (/reload) go through the chat's
edit box, and a macro of the player's own runs from a secure button over its wedge, on a click
only, never in combat, dimmed when the macro is gone."""

from harness import WowRuntime
from test_gestures import MOD, E, R, boot, click_choice, cursor_on, errors

MACRO_TIP = "Click the wedge (a macro runs only on a click)"


def shown(wow: WowRuntime, expr: str) -> bool:
    return wow.eval(f"{expr}:IsShown()") is True


def command_form(wow: WowRuntime, ring: int, slot: int) -> None:
    wow.execute(f"{E}.Choose({MOD}.db.global.rings[{ring}], {slot})")
    if not wow.eval(f"{E}.Expanded('commands')"):
        wow.execute(f"{E}.Toggle('commands')")
    click_choice(wow, "A command or macro...")


def test_the_command_forms_hints_step_aside_for_the_text(wow: WowRuntime):
    boot(wow)
    wow.slash("/bgest")
    command_form(wow, 3, 7)
    title, text = f"{E}.titleBox", f"{E}.textBox"
    assert shown(wow, f"{title}.hint") and shown(wow, f"{text}.hint")
    wow.execute(f"{title}:SetText('Reload'); {text}:SetText('/reload')")
    assert not shown(wow, f"{title}.hint") and not shown(wow, f"{text}.hint")
    assert wow.eval(f"{E}.Form().title") == "Reload" and wow.eval(f"{E}.Form().text") == "/reload"
    # empty again: the hint is back; the focus alone hides it
    wow.execute(f"{text}:SetText('')")
    assert shown(wow, f"{text}.hint")
    wow.execute(f"{text}:SetFocus(); {text}:GetScript('OnEditFocusGained')({text})")
    assert not shown(wow, f"{text}.hint")
    wow.execute(f"{text}:ClearFocus(); {text}:GetScript('OnEditFocusLost')({text})")
    assert shown(wow, f"{text}.hint")
    # a saved command opens its form again with the text in, the hints hidden from the start
    wow.execute(f"{text}:SetText('/reload')")
    assert wow.eval(f"{E}.SaveCommand()") is True
    command_form(wow, 3, 7)
    assert wow.eval(f"{title}:GetText()") == "Reload"
    assert not shown(wow, f"{title}.hint") and not shown(wow, f"{text}.hint")
    # the line form's boxes follow the same rule
    wow.execute(f"{E}.Form().kind = nil; {E}.Choose({MOD}.db.global.rings[2], 6)")
    click_choice(wow, "A new line...")
    wow.execute(f"{E}.textBox:SetText('Well met')")
    assert not shown(wow, f"{E}.textBox.hint")
    assert errors(wow) == []


def test_the_clients_own_commands_go_through_the_chat(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"{MOD}.db.global.rings[3].slots[7] = {{ kind = 'command', title = 'Reload', "
        "text = '/reload\\n/played' }"
    )
    wow.execute(f"{R}.SetPage(3); {R}.Open()")
    assert wow.eval(f"{R}.Fire(7)") is True
    assert list(wow.eval("Mock.chatSent").values()) == ["/reload", "/played"]
    assert not any("Unknown command" in line for line in wow.chat)
    # where the client offers no chat send, the note says so
    wow.execute("ChatEdit_SendText = nil")
    wow.execute(f"{R}.Open()")
    assert wow.eval(f"{R}.Fire(7)") is False
    assert any(
        "Unknown command: /reload (the game's chat could not take it)" in line for line in wow.chat
    )
    assert errors(wow) == []


def test_a_macro_of_my_own_runs_from_a_secure_button_on_a_click(wow: WowRuntime):
    boot(wow)
    wow.slash("/bgest")
    # the picker lists the account's and the character's macros
    wow.execute(f"{E}.Choose({MOD}.db.global.rings[3], 8); {E}.Toggle('macros')")
    macros = {
        c.label: c for c in wow.eval(f"{E}.Choices()").values() if c.cat == "macros" and c.row
    }
    assert sorted(macros) == ["Hearth home", "Mount up"]
    assert macros["Hearth home"].row.tip == "A macro of this character"
    click_choice(wow, "Mount up")
    slot = wow.eval(f"{MOD}.db.global.rings[3].slots[8]")
    assert (slot.kind, slot.name) == ("macro", "Mount up")
    wow.execute(f"{E}.Close()")
    # the ring out of combat: a secure button over the wedge with the macro's attributes
    wow.execute(f"{R}.SetPage(3)")
    wow.execute(f"{R}.Key('down')")
    o = f"{R}.kit:Secure(8)"
    assert wow.eval(f"{o} ~= nil") is True
    assert wow.eval(f"{o}:IsProtected()") is True and shown(wow, o)
    assert wow.eval(f"{o}:GetAttribute('type')") == "macro"
    assert wow.eval(f"{o}:GetAttribute('macro')") == "Mount up"
    assert list(wow.eval(f"{o}.clicks").values()) == ["AnyUp"]
    assert wow.eval(f"{o}:GetParent() == UIParent") is True  # never the ring's child
    item = wow.eval(f"{R}.kit.items[8]")
    assert item.disabled is None and item.tip == MACRO_TIP
    # held and released over it: no click, nothing fires, the ring waits for the click
    cursor_on(wow, 8)
    wow.execute(f"{R}.Key('up')")
    assert wow.eval(f"{R}.IsOpen()") is True
    assert wow.eval(f"{R}.Fire(8)") is False
    # the click (the client runs the macro) closes the ring; the overlay goes with it
    wow.execute(f"local b = {o}; b:GetScript('PostClick')(b, 'LeftButton')")
    assert wow.eval(f"{R}.IsOpen()") is False and not shown(wow, o)
    # with the key toggling the ring, the tip is the plain one
    wow.execute(f"{MOD}.db.profile.toggle = true; {R}.Open()")
    assert wow.eval(f"{R}.kit.items[8].tip") is None
    wow.execute(f"{R}.Close(); {MOD}.db.profile.toggle = false")
    # in combat: no overlay, the wedge dimmed; after combat it is back on the open ring
    wow.execute("Mock.SetCombat(true)")
    wow.execute(f"{R}.Open()")
    assert not shown(wow, o)
    item = wow.eval(f"{R}.kit.items[8]")
    assert item.disabled is True and item.tip == "Not in combat."
    wow.execute("Mock.SetCombat(false)")
    assert shown(wow, o) and wow.eval(f"{R}.kit.items[8].disabled") is None
    wow.execute(f"{R}.Close()")
    assert errors(wow) == []


def test_a_gone_macro_dims_its_wedge_and_the_editor_empties_it(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{MOD}.db.global.rings[3].slots[8] = {{ kind = 'macro', name = 'Mount up' }}")
    wow.execute(f"{R}.SetPage(3); {R}.Open()")
    assert shown(wow, f"{R}.kit:Secure(8)")
    wow.execute(f"{R}.Close()")
    wow.execute("Mock.macros.account = {}")  # deleted in the game's macro window
    wow.execute(f"{R}.Open()")
    item = wow.eval(f"{R}.kit.items[8]")
    assert item.disabled is True and item.tip == "Macro not found: Mount up"
    assert not shown(wow, f"{R}.kit:Secure(8)")
    wow.execute(f"{R}.Close()")
    # never cleared by itself; the editor shows it and its Empty row clears it
    assert wow.eval(f"{MOD}.db.global.rings[3].slots[8].kind") == "macro"
    wow.slash("/bgest")
    row = next(
        r for r in wow.eval(f"{E}.Rows()").values() if r.ring.id == "actions" and r.index == 8
    )
    assert "Macro not found: Mount up" in row.button.spec.label
    wow.execute(f"{E}.Choose({MOD}.db.global.rings[3], 8)")
    assert wow.eval(f"{E}.Expanded('other')") is True
    click_choice(wow, "Empty")
    assert wow.eval(f"{MOD}.db.global.rings[3].slots[8]") is False
    assert errors(wow) == []
