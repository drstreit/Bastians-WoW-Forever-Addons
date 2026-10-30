"""Every window's options and one look for all: a window that names its
app gets a button to that app's settings page (R27.1); Core's General page sets one background
colour (the game's colour picker, back to the theme's) and one opacity for every window (R27.2)."""

from harness import WowRuntime

PAINTED = "Bastians.UI.Style.painted"

# the game's colour picker as the retail family has it since 10.2.5 (SetupColorPickerAndShow)
PICKER = """
ColorPickerFrame = { r = 1, g = 1, b = 1 }
function ColorPickerFrame:SetupColorPickerAndShow(info)
  self.info, self.r, self.g, self.b = info, info.r, info.g, info.b
end
function ColorPickerFrame:GetColorRGB() return self.r, self.g, self.b end
"""


def window(app: WowRuntime, name: str, module: str | None) -> None:
    mod = f"module = '{module}', " if module else ""
    app.execute(
        f"{name} = Bastians.UI.Window('{name}Frame', {{ {mod}title = 'T' }}); {name}:Show()"
    )


def test_a_window_that_names_its_app_opens_that_page_of_the_settings(app: WowRuntime):
    window(app, "W", "TestApp")
    window(app, "V", None)
    assert app.eval("W.options ~= nil") is True
    assert app.eval("V.options") is None  # a window of no app has no options button
    assert app.eval("W.options.tip") == "Options of this window"
    app.execute("W.options:Click()")
    assert app.eval("Bastians.UI.Hub.current.mod.name") == "TestApp"
    hub = app.eval("Bastians.UI.Windows.BastiansHubFrame.frame")
    assert hub.IsShown(hub) is True
    assert app.errors == []


def test_one_background_colour_and_opacity_for_every_window(app: WowRuntime):
    window(app, "W", "TestApp")
    window(app, "V", None)
    core = "Bastians:GetModule('Core').db.profile"
    # the theme's background at full opacity by default
    assert app.eval(f"{PAINTED}[W.frame.bg][2]") == 1
    assert app.eval(f"{PAINTED}[W.frame.bg][1] == Bastians.UI.Style.C.bg") is True
    # opacity and a colour of the player's for all windows at once
    app.execute(
        f"{core}.windowAlpha = 50; "
        "Bastians:Fire('BASTIANS_SETTING_CHANGED', 'Core', 'windowAlpha', 50)"
    )
    assert app.eval(f"{PAINTED}[W.frame.bg][2]") == 0.5
    assert app.eval(f"{PAINTED}[V.frame.bg][2]") == 0.5
    app.execute(
        f"{core}.windowColor = {{ 0.1, 0.2, 0.3 }}; "
        "Bastians:Fire('BASTIANS_SETTING_CHANGED', 'Core', 'windowColor', {})"
    )
    c = list(app.eval(f"{PAINTED}[V.frame.bg][1]").values())
    assert c == [0.1, 0.2, 0.3]
    # a window built later takes the same look; the header stays opaque
    window(app, "U", None)
    assert app.eval(f"{PAINTED}[U.frame.bg][2]") == 0.5
    assert app.eval(f"({PAINTED}[U.head.bg] or {{}})[2]") != 0.5
    # nonsense in the saved table: the theme's colour, the opacity clamped
    app.execute(
        f"{core}.windowColor = {{ 'x' }}; {core}.windowAlpha = 3; Bastians.UI.ApplyWindowLook()"
    )
    assert app.eval(f"{PAINTED}[W.frame.bg][1] == Bastians.UI.Style.C.bg") is True
    assert app.eval(f"{PAINTED}[W.frame.bg][2]") == 0.2
    assert app.errors == []


def test_the_colour_row_uses_the_games_picker_and_goes_back_to_the_theme(app: WowRuntime):
    app.execute(PICKER)
    app.execute(
        "VALUE = nil; ROW = Bastians.UI.Widgets.Color(UIParent, 'Background', "
        "function() return VALUE end, function(v) VALUE = v end, Bastians.UI.Style.C.bg)"
    )
    app.execute("ROW.swatch:Click()")
    assert app.eval("ColorPickerFrame.info ~= nil") is True
    # a change in the picker goes to the setting at once
    app.execute("ColorPickerFrame.r, ColorPickerFrame.g, ColorPickerFrame.b = 0.4, 0.5, 0.6")
    app.execute("ColorPickerFrame.info.swatchFunc()")
    assert list(app.eval("VALUE").values()) == [0.4, 0.5, 0.6]
    assert list(app.eval(f"{PAINTED}[ROW.swatch.fill][1]").values()) == [0.4, 0.5, 0.6]
    # the theme button clears the choice
    app.execute("ROW.reset:Click()")
    assert app.eval("VALUE") is None
    assert app.eval(f"{PAINTED}[ROW.swatch.fill][1] == Bastians.UI.Style.C.bg") is True
    # without the game's picker: one line, no error
    app.execute("ColorPickerFrame = nil; ROW.swatch:Click()")
    assert any("colour picker is not available" in line for line in app.chat)
    # the General page carries the window look
    app.execute("Bastians.UI.Hub.Open('Core')")
    assert app.errors == []


def test_an_app_can_colour_and_fade_its_own_window(app: WowRuntime):
    """a colour and an opacity per window, in the app's profile; nil means the
    General setting for every window."""
    window(app, "W", "TestApp")
    window(app, "V", None)
    core = "Bastians:GetModule('Core').db.profile"
    own = "Bastians:GetModule('TestApp').db.profile"
    app.execute(f"{core}.windowAlpha = 80; {own}.windowAlpha = 40; Bastians.UI.ApplyWindowLook()")
    assert app.eval(f"{PAINTED}[W.frame.bg][2]") == 0.4  # the app's own
    assert app.eval(f"{PAINTED}[V.frame.bg][2]") == 0.8  # the General setting
    app.execute(f"{own}.windowColor = {{ 0.5, 0.6, 0.7 }}; Bastians.UI.ApplyWindowLook()")
    assert list(app.eval(f"{PAINTED}[W.frame.bg][1]").values()) == [0.5, 0.6, 0.7]
    assert app.eval(f"{PAINTED}[V.frame.bg][1] == Bastians.UI.Style.C.bg") is True
    app.execute(f"{own}.windowColor = nil; {own}.windowAlpha = nil; Bastians.UI.ApplyWindowLook()")
    assert app.eval(f"{PAINTED}[W.frame.bg][2]") == 0.8
    # the app's page carries the two rows after Open and the minimap button
    app.execute("Bastians.UI.Hub.Open('TestApp')")
    texts = [
        w.label.GetText(w.label) if w.label is not None else ""
        for w in app.eval("Bastians.UI.Hub.canvas.widgets").values()
    ]
    assert "Window background" in texts and "Window opacity (%)" in texts
    assert app.errors == []
