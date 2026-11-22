"""One look for the suite (ADR 0084, W4 of plan-suite-waves.md, 20.11.2026): the presets of ADR 0038
and the looks of ADR 0046 are gone. A saved look is mapped once to a theme and the game's frame
(migration 4, decision 6), never lost to an error; an old preset's id still names its theme for a
window of its own (Bastian's Chat); the General page holds the theme and the frame. Replaces
test_presets.py (the presets' own tests, until 20.11.2026); the suite's ten fonts stay here."""

from harness import ADDONS, WowRuntime

S = "Bastians.UI.Style"
CORE = "Bastians:GetModule('Core')"
PROFILE = f"{CORE}.db.profile"
SET = "Bastians.UI.Settings"

GONE = ("preset", "look", "gameButtons", "ornaments", "skinFrames")


def test_every_saved_look_is_mapped_once(core: WowRuntime):
    """Decision 6, row by row: the WoW look to Folio in the game's frame; Modern dark and Glass to
    Folio with the frame as it was (Glass keeps its see-through); Modern light and Parchment to
    Paper; a scheme the player chose stays; a player's own preset gives its theme, faces, size,
    opacity and content switches; the looks' keys go, the saved presets stay one release."""
    core.execute(
        f"""
        profiles = {{
          wow = {{ preset = "wow", look = "wow", theme = "blizzard", gameFrames = true,
            gameButtons = true, ornaments = true, skinFrames = true }},
          dark = {{ preset = "modern-dark", theme = "teal", gameFrames = false }},
          untouched = {{}},
          glass = {{ preset = "glass", look = "glass", theme = "teal", windowAlpha = 90 }},
          glassLow = {{ preset = "glass", windowAlpha = 50 }},
          light = {{ preset = "modern-light", theme = "parchment" }},
          parch = {{ preset = "parchment", look = "parchment", theme = "parchment" }},
          night = {{ preset = "night", theme = "night" }},
          graphite = {{ preset = "modern-graphite", theme = "graphite", gameFrames = true }},
          custom = {{ preset = "custom", look = "wow", theme = "contrast" }},
          customGlass = {{ preset = "custom", look = "glass", theme = "graphite", windowAlpha = 100 }},
          customTeal = {{ preset = "custom", look = "modern", theme = "teal" }},
          user = {{ preset = "user:Mine", theme = "teal", headingFont = "Own" }},
          lost = {{ preset = "user:Missing", theme = "night" }},
        }}
        saved = {{ Mine = {{ theme = "night", font = "F", fontScale = 110, windowAlpha = 80,
          rowPortraits = false, look = "modern", headingFont = "Theirs", gameButtons = true }} }}
        Bastians:ClearLog()
        {CORE}.migrations[4]({{ sv = {{ profiles = profiles, global = {{ presets = saved }} }} }})
        """
    )
    p = core.eval("profiles")
    assert (p.wow.theme, p.wow.gameFrames) == ("folio", True)
    assert (p.dark.theme, p.dark.gameFrames) == ("folio", False)  # the frame as it was set
    assert (p.untouched.theme, p.untouched.gameFrames) == (None, False)  # the default: Folio
    assert (p.glass.theme, p.glass.windowAlpha) == ("folio", 75)  # Glass's see-through stays
    assert p.glassLow.windowAlpha == 50  # never more opaque than it was
    assert p.light.theme == "parchment" and p.parch.theme == "parchment"  # Paper
    assert p.night.theme == "night" and p.graphite.theme == "graphite"
    assert p.graphite.gameFrames is True
    # a look chosen by hand: the frame for WoW, the see-through for Glass, the scheme kept
    assert (p.custom.theme, p.custom.gameFrames) == ("contrast", True)
    assert (p.customGlass.theme, p.customGlass.windowAlpha) == ("graphite", 75)
    assert (p.customTeal.theme, p.customTeal.gameFrames) == ("teal", False)
    # a player's own preset: its theme, faces, size, opacity and switches; not its look parts
    assert (p.user.theme, p.user.font, p.user.fontScale) == ("night", "F", 110)
    assert p.user.windowAlpha == 80 and p.user.rowPortraits is False
    assert p.user.headingFont == "Own" and p.user.gameButtons is None
    assert p.lost.theme == "night"  # its preset is gone: what the profile had stays
    for name in ("wow", "dark", "glass", "light", "custom", "user", "lost", "untouched"):
        for key in GONE:
            assert p[name][key] is None, (name, key)
    assert core.eval("saved.Mine.theme") == "night"  # kept one release (decision 6)
    lines = [line.text for line in core.eval("Bastians:GetLog()").values()]
    assert any("one look for the suite: 13 profile(s)" in line for line in lines)
    assert core.errors == []


def test_the_old_migrations_lead_into_the_one_look(core: WowRuntime):
    """A profile from before 31.10.2026 passes migrations 2 and 3 on its way to 4: the game's look
    of old (the skins blizzard and azeroth, the Azeroth preset) ends in Folio in the game's frame."""
    core.execute(
        f"""
        profiles = {{
          gold = {{ skin = "blizzard", theme = "blizzard" }},
          az = {{ preset = "azeroth", theme = "azeroth", fontScale = 110 }},
          plain = {{ skin = "modern" }},
          light = {{ skin = "modern", theme = "parchment" }},
        }}
        local sv = {{ sv = {{ profiles = profiles, global = {{}} }} }}
        for n = 2, 4 do {CORE}.migrations[n](sv) end
        """
    )
    p = core.eval("profiles")
    assert (p.gold.theme, p.gold.gameFrames) == ("folio", True)
    assert (p.az.theme, p.az.gameFrames, p.az.fontScale) == ("folio", True, 110)
    assert (p.plain.theme, p.plain.gameFrames) == (None, False)
    assert p.light.theme == "parchment"
    for name in ("gold", "az", "plain", "light"):
        assert p[name].preset is None and p[name].skin is None, name
    assert core.errors == []


def test_a_fresh_profile_wears_folio_in_the_games_frame(core: WowRuntime):
    """No migration runs on a new install (DB.lua): the defaults are the board's (question 4)."""
    assert core.eval(f"{PROFILE}.theme") == "folio" and core.eval(f"{S}.ThemeId()") == "folio"
    assert core.eval(f"{PROFILE}.gameFrames") is True
    assert core.eval(f"{S}.LookId()") == "book" and core.eval(f"{S}.LOOKS.modern") is None
    for gone in ("PRESETS", "ApplyPreset", "SavePreset", "DeletePreset", "LOOK_KEYS"):
        assert core.eval(f"{SET}.{gone}") is None, gone
    assert core.errors == []


def test_an_old_id_names_its_theme_for_a_window(core: WowRuntime):
    """A window of its own (Window:SetPreset; Chat's `look`): a theme's id, or an old preset's
    mapped as migration 4 maps it; the choice an app offers is the themes."""
    assert dict(core.eval(f"{SET}.PresetValues('wow')")) == {"theme": "folio", "gameFrames": True}
    assert dict(core.eval(f"{SET}.PresetValues('glass')")) == {"theme": "folio"}
    assert dict(core.eval(f"{SET}.PresetValues('modern-light')")) == {"theme": "parchment"}
    assert dict(core.eval(f"{SET}.PresetValues('night')")) == {"theme": "night"}
    assert dict(core.eval(f"{SET}.PresetValues('folio')")) == {"theme": "folio"}
    assert core.eval(f"{SET}.PresetValues('nonsense')") is None
    assert core.eval(f"{SET}.PresetValues(nil)") is None
    choices = dict(core.eval(f"{SET}.Presets()"))
    assert choices == {
        "folio": "Folio",
        "teal": "Dark teal",
        "parchment": "Paper",
        "blizzard": "Blizzard gold",
        "contrast": "High contrast",
        "night": "Night",
        "graphite": "Graphite",
    }
    assert core.errors == []


def test_the_general_page_shows_the_theme_and_the_frame(core: WowRuntime):
    core.execute("Bastians.UI.Hub.Open('Core')")
    labels = [
        w.label.GetText(w.label)
        for w in core.eval("Bastians.UI.Hub.canvas.widgets").values()
        if w.label
    ]
    assert "Colour scheme" in labels and "The game's frame around every window" in labels
    for gone in ("Preset", "Use the WoW look", "The game's buttons", "The game's window frames"):
        assert gone not in labels, gone
    assert core.errors == []


def test_the_suites_ten_fonts_are_in_the_choices(core: WowRuntime):
    # five since 30.10.2026 (ADR 0038), five more 13.11.2026 (plan-chat-v3.md V17: "some variety")
    choices = dict(core.eval(f"{SET}.FontChoices()"))
    fonts = "Interface\\AddOns\\Bastians_Core\\Fonts\\"
    folder = ADDONS / "Bastians_Core" / "Fonts"
    for file, name in (
        ("Inter.ttf", "Inter"),
        ("Exo2.ttf", "Exo 2"),
        ("RobotoCondensed.ttf", "Roboto Condensed"),
        ("Alegreya.ttf", "Alegreya"),
        ("Cinzel.ttf", "Cinzel"),
        ("IBMPlexSans.ttf", "IBM Plex Sans"),
        ("IBMPlexMono.ttf", "IBM Plex Mono"),
        ("Oswald.ttf", "Oswald"),
        ("VarelaRound.ttf", "Varela Round"),
        ("Almendra.ttf", "Almendra"),
    ):
        assert choices[fonts + file] == name
        # the file ships, its licence beside it
        assert (folder / file).is_file(), file
        assert (folder / file.replace(".ttf", "-LICENSE.txt")).is_file(), file
    # the heading, the label and the number font offer the same plus "the text font"
    for key in ("headingFont", "labelFont", "numberFont"):
        values = dict(
            core.eval(
                f"""(function()
                  for _, o in ipairs({CORE}.def.options) do
                    if o.key == "{key}" then return o.values() end
                  end
                end)()"""
            )
        )
        assert values[""] == "Same as the text", key
        assert values[fonts + "Cinzel.ttf"] == "Cinzel", key
    # a window of its own may name them too (Chat's faces, V17)
    assert {"labelFont", "numberFont"} <= set(core.eval(f"{SET}.FRAME_KEYS").values())
    assert core.errors == []
