"""The text keys of every box: the Windows and Word keys
(Ctrl+Backspace, Ctrl+Delete, Ctrl+Left/Right) for all, the readline set for the boxes that ask,
Ctrl+C, X, V and A left to the client. Bastians.TextKeys is pure: (text, cursor) in and out."""

import pytest
from harness import WowRuntime


def edit(core: WowRuntime, op: str, text: str, cursor: int, kill: str | None = None) -> tuple:
    k = "nil" if kill is None else repr(kill)
    out = core.eval(f"{{ Bastians.TextKeys.Edit('{op}', {text!r}, {cursor}, {k}) }}")
    return tuple(out[i] for i in (1, 2, 3))  # a missing index reads None


@pytest.mark.parametrize(
    ("op", "text", "cursor", "want"),
    [
        ("wordLeft", "say hello world", 15, ("say hello world", 10, None)),
        ("wordLeft", "say hello world", 10, ("say hello world", 4, None)),
        ("wordLeft", "say hello", 0, ("say hello", 0, None)),
        ("wordLeft", "a, b", 2, ("a, b", 1, None)),  # punctuation is a word of its own
        ("wordRight", "say hello world", 0, ("say hello world", 4, None)),
        ("wordRight", "say hello world", 3, ("say hello world", 4, None)),
        ("wordRight", "say hello", 9, ("say hello", 9, None)),
        ("wordEnd", "say hello world", 3, ("say hello world", 9, None)),
        ("deleteWordLeft", "say hello world", 15, ("say hello ", 10, None)),
        ("deleteWordLeft", "say hello  ", 11, ("say ", 4, None)),
        ("deleteWordRight", "say hello world", 4, ("say world", 4, None)),
        ("deleteWordRight", "say hello world", 15, ("say hello world", 15, None)),
        ("home", "say hello", 5, ("say hello", 0, None)),
        ("end", "say hello", 1, ("say hello", 9, None)),
        ("killLeft", "say hello", 4, ("hello", 0, "say ")),
        ("killRight", "say hello", 3, ("say", 3, " hello")),
        ("killWord", "say hello  world", 16, ("say hello  ", 11, "world")),
        ("killWord", "say", 0, ("say", 0, None)),
        ("killWordRight", "say hello world", 3, ("say world", 3, " hello")),
        ("transpose", "abc", 3, ("acb", 3, None)),
        ("transpose", "abc", 1, ("bac", 2, None)),
        ("transpose", "abc", 0, ("abc", 0, None)),
        ("wordLeft", "grüße dich", 6, ("grüße dich", 0, None)),  # letters beyond ASCII are letters
    ],
)
def test_the_edits(core: WowRuntime, op: str, text: str, cursor: int, want: tuple):
    assert edit(core, op, text, cursor) == want


def test_yank_puts_back_what_a_kill_took(core: WowRuntime):
    assert edit(core, "yank", "say ", 4, "hello") == ("say hello", 9, None)
    assert edit(core, "yank", "say ", 4) == ("say ", 4, None)
    assert core.eval("Bastians.TextKeys.Edit('nothing', 'x', 0)") is None


def test_the_keys_of_a_box(core: WowRuntime):
    def op(key: str, ctrl: bool, alt: bool, shell: bool):
        return core.eval(
            f"Bastians.TextKeys.Op('{key}', {str(ctrl).lower()}, {str(alt).lower()}, {str(shell).lower()})"
        )

    assert op("BACKSPACE", True, False, False) == "deleteWordLeft"
    assert op("DELETE", True, False, False) == "deleteWordRight"
    assert op("LEFT", True, False, False) == "wordLeft"
    assert op("RIGHT", True, False, True) == "wordRight"
    for key in ("C", "X", "V", "A"):
        assert op(key, True, False, False) is None  # the client's copy, cut, paste, select all
    for key in ("C", "X", "V"):
        assert op(key, True, False, True) is None
    assert op("A", True, False, True) == "home"  # the readline set, where a box asks for it
    assert op("Y", True, False, True) == "yank"
    assert op("B", False, True, True) == "wordLeft"
    assert op("B", False, True, False) is None
    assert op("LEFT", True, True, True) is None  # Ctrl+Alt is nothing of ours
    assert core.eval("Bastians.TextKeys.Op('R', true, false, false, { R = 'search' })") == "search"


def test_ctrl_shift_arrows_select_words(core: WowRuntime):
    """Ctrl+Shift+Right marks the next word, again the one after."""
    assert (
        core.eval("Bastians.TextKeys.Op('RIGHT', true, false, false, nil, true)")
        == "selectWordRight"
    )
    core.execute(
        """
        _G.box = Bastians.UI.Style.search(UIParent, 'Search')
        _G.lit = {}
        box.HighlightText = function(self, a, b) lit = { a, b } end
        box:SetText('grey wolf den')
        box:SetCursorPosition(0)
        """
    )

    def key(k: str) -> None:
        core.execute(
            f"Mock.ctrl = true Mock.shift = true box:GetScript('OnKeyDown')(box, '{k}') "
            "Mock.ctrl = false Mock.shift = false"
        )
        core.advance(0)

    key("RIGHT")
    assert list(core.eval("lit").values()) == [0, 5] and core.eval("box.cursor") == 5
    key("RIGHT")
    assert list(core.eval("lit").values()) == [0, 10]
    key("LEFT")
    assert list(core.eval("lit").values()) == [0, 5]
    assert core.errors == []
