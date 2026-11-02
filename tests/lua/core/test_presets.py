"""Looks as presets: the
built-in presets write every look setting at once, a change by hand reads Custom, the current look
can be saved as a preset of the player's own (account-wide) and deleted again; the skin of ADR
0034 migrates; the Azeroth preset is gone and its profiles moved to WoW (migration 3); the suite's
five fonts are in the font choices."""

from harness import WowRuntime

S = "Bastians.UI.Style"
CORE = "Bastians:GetModule('Core')"
PROFILE = f"{CORE}.db.profile"
SET = "Bastians.UI.Settings"
MORPHEUS = "Fonts\\MORPHEUS.TTF"
FRIZ = "Fonts\\FRIZQT__.TTF"
ARIALN = "Fonts\\ARIALN.TTF"


def change(wow: WowRuntime, key: str, value: str) -> None:
    """A look setting changed by hand on the General page: the value, its handler, the message."""
    wow.execute(
        f"""
        local core = {CORE}
        for _, o in ipairs(core.def.options) do
          if o.key == '{key}' then
            core.db.profile[o.key] = {value}
            if o.set then o.set({value}, core) end
            Bastians:Fire("BASTIANS_SETTING_CHANGED", core.name, o.key, {value})
          end
        end
        """
    )


def look(wow: WowRuntime) -> dict:
    keys = list(wow.eval(f"{SET}.LOOK_KEYS").values())
    p = wow.eval(PROFILE)
    return {k: p[k] for k in keys}


def test_the_built_in_presets_write_every_look_setting(core: WowRuntime):
    core.execute(
        "W = Bastians.UI.Window('PresetTestFrame', { title = 'T' }); W:Show() "
        "Btn = Bastians.UI.Style.button(W.content, 'Go', 80, 20)"
    )
    assert core.eval(f"{PROFILE}.preset") == "modern-dark"
    assert core.eval(f"{SET}.ApplyPreset({CORE}, 'wow')") is True
    p = core.eval(PROFILE)
    assert p.preset == "wow" and p.skinFrames is True and p.theme == "blizzard"
    assert p.font == FRIZ and p.headingFont == MORPHEUS
    assert p.gameButtons is True and p.ornaments is True and p.gameFrames is True
    assert core.eval(f"{S}.ThemeId()") == "blizzard"
    assert core.eval("(W.title:GetFont())") == MORPHEUS
    assert core.eval("{ W.title:GetTextColor() }")[1] == core.eval(f"{S}.C.headerText[1]")  # gold
    assert core.eval("W.border:IsShown()") is True
    assert core.eval("W.frame.bg:IsShown()") is True  # the ground stays inside the frame
    # the game's button art in three slices (ADR 0043's branch, retail 31.10.2026: no stretched caps)
    up = "Interface\\Buttons\\UI-Panel-Button-Up"
    assert core.eval("Btn.gameArt.up[2]:GetTexture()") == up
    assert core.eval("Btn.gameArt.up[2]:IsShown()") is True
    assert core.eval("Btn.face:IsShown()") is False
    # a button made under the preset is dressed at once
    core.execute("Btn2 = Bastians.UI.Style.button(W.content, 'Go', 80, 20)")
    assert core.eval("Btn2.gameArt.up[2]:GetTexture()") == up

    assert core.eval(f"{SET}.ApplyPreset({CORE}, 'modern-light')") is True
    p = core.eval(PROFILE)
    assert p.preset == "modern-light" and p.theme == "parchment" and p.font == ARIALN
    assert p.headingFont is None and p.gameButtons is False and p.ornaments is False
    assert p.skinFrames is True  # the game's frames are the standard under every preset
    assert core.eval("(W.title:GetFont())") == ARIALN
    assert core.eval("Btn.gameArt.up[2]:IsShown()") is False
    assert core.eval("Btn.face:IsShown()") is True

    assert core.eval(f"{SET}.ApplyPreset({CORE}, 'modern-dark')") is True
    assert core.eval(f"{PROFILE}.theme") == "teal" and core.eval(f"{S}.ThemeId()") == "teal"
    assert core.eval(f"{SET}.ApplyPreset({CORE}, 'no-such-preset')") is False
    assert core.eval(f"{SET}.ApplyPreset({CORE}, 'azeroth')") is False  # gone (ADR 0046)
    assert core.eval(f"{PROFILE}.preset") == "modern-dark"
    assert core.errors == []


def test_a_change_by_hand_reads_custom_and_a_preset_restores_it(core: WowRuntime):
    core.execute(
        """seen = {}
        local m = Bastians:NewModule("PresetWatch", { addon = "Bastians_Core" })
        m:On("BASTIANS_SETTING_CHANGED", function(_, _, mod, key, value)
          if key == "preset" then seen[#seen + 1] = value end
        end)"""
    )
    core.execute(f"{SET}.ApplyPreset({CORE}, 'modern-light')")
    change(core, "theme", "'contrast'")
    assert core.eval(f"{PROFILE}.preset") == "custom"
    assert core.eval(f"{S}.ThemeId()") == "contrast"
    change(core, "tips", "false")  # not a look setting: no change of the preset
    assert core.eval(f"{PROFILE}.preset") == "custom"
    choices = dict(core.eval(f"{SET}.PresetChoices({CORE})"))
    assert choices["custom"] == "Custom" and choices["modern-dark"] == "Modern dark"
    assert choices["wow"] == "WoW (the game's windows)"  #
    assert "azeroth" not in choices  # the Azeroth preset went (ADR 0046, 01.11.2026)
    core.execute(f"{SET}.ApplyPreset({CORE}, 'modern-light')")
    assert core.eval(f"{PROFILE}.preset") == "modern-light"
    assert core.eval(f"{S}.ThemeId()") == "parchment"
    assert list(core.eval("seen").values()) == ["modern-light", "modern-light"]
    assert core.errors == []


def test_a_saved_preset_is_account_wide_and_can_be_deleted(core: WowRuntime):
    core.execute(f"{SET}.ApplyPreset({CORE}, 'wow')")
    change(core, "fontScale", "120")
    change(core, "ornaments", "false")
    assert core.eval(f"{PROFILE}.preset") == "custom"
    assert core.eval(f"{SET}.SavePreset({CORE}, '  Mine ')") is True
    assert core.eval(f"{SET}.SavePreset({CORE}, '   ')") is False
    assert core.eval(f"{PROFILE}.preset") == "user:Mine"
    saved = core.eval(f"{CORE}.db.global.presets.Mine")
    assert saved.theme == "blizzard" and saved.fontScale == 120 and saved.ornaments is False
    assert saved.headingFont == MORPHEUS and saved.gameButtons is True
    mine = look(core)
    choices = dict(core.eval(f"{SET}.PresetChoices({CORE})"))
    assert choices["user:Mine"] == "Mine"
    # another profile of the account lists it and can pick it
    core.execute("Bastians:SetProfile('Second')")
    assert core.eval(f"{PROFILE}.preset") == "modern-dark"
    assert "user:Mine" in dict(core.eval(f"{SET}.PresetChoices({CORE})"))
    assert core.eval(f"{SET}.ApplyPreset({CORE}, 'user:Mine')") is True
    assert look(core) == mine and core.eval(f"{PROFILE}.preset") == "user:Mine"
    assert core.eval(f"{S}.ThemeId()") == "blizzard"
    # deleting keeps the look and reads Custom; deleting again does nothing
    assert core.eval(f"{SET}.DeletePreset({CORE})") is True
    assert core.eval(f"{PROFILE}.preset") == "custom" and look(core) == mine
    assert core.eval(f"{CORE}.db.global.presets.Mine") is None
    assert core.eval(f"{SET}.DeletePreset({CORE})") is False
    assert "user:Mine" not in dict(core.eval(f"{SET}.PresetChoices({CORE})"))
    assert core.errors == []


def test_the_hub_renders_the_section_and_the_edit_row_saves(core: WowRuntime):
    core.execute("Bastians.UI.Hub.Open('Core')")
    assert core.errors == []
    # the Save row goes through the option like the hub's edit box does
    core.execute(
        f"""
        local core = {CORE}
        for _, o in ipairs(core.def.options) do
          if o.key == 'newPreset' then o.set('Night', core) end
        end
        """
    )
    assert core.eval(f"{PROFILE}.preset") == "user:Night"
    assert core.eval(f"{CORE}.db.global.presets.Night.theme") == "teal"
    assert core.errors == []


def test_the_skin_of_adr_0034_migrates_to_a_preset(core: WowRuntime):
    core.execute(
        f"""
        profiles = {{
          plain = {{ skin = "modern" }},
          light = {{ skin = "modern", theme = "parchment" }},
          gold = {{ skin = "blizzard", theme = "blizzard", font = "{FRIZ.replace(chr(92), chr(92) * 2)}" }},
          az = {{ skin = "azeroth" }},
          fresh = {{}},
          kept = {{ skin = "azeroth", preset = "modern-light" }},
        }}
        {CORE}.migrations[2]({{ sv = {{ profiles = profiles }} }})
        """
    )
    p = core.eval("profiles")
    assert p.plain.preset == "custom" and p.plain.skin is None
    assert p.light.preset == "modern-light"
    # the game's look of old is the game's look of now; since the
    # Azeroth preset went (ADR 0046) the Azeroth skin lands on WoW too
    assert p.gold.preset == "wow" and p.gold.gameFrames is True and p.gold.gameButtons is True
    assert p.gold.theme == "blizzard"
    assert p.az.preset == "wow" and p.az.ornaments is True and p.az.headingFont == MORPHEUS
    assert p.az.gameFrames is True and p.az.theme == "blizzard"
    assert p.fresh.preset is None  # nothing was chosen: the default (modern-dark) applies
    assert p.kept.preset == "modern-light" and p.kept.skin is None  # already migrated
    assert core.errors == []


def test_the_azeroth_preset_migrates_to_wow_with_a_line_in_the_log(core: WowRuntime):
    """ADR 0046: a profile on Azeroth wears WoW after
    the update, every look setting written; a custom look or a saved preset on the Azeroth scheme
    takes Parchment; everything else is left alone."""
    core.execute(
        f"""
        profiles = {{
          az = {{ preset = "azeroth", theme = "azeroth", ornaments = true, fontScale = 110 }},
          custom = {{ preset = "custom", theme = "azeroth", fontScale = 90 }},
          dark = {{ preset = "modern-dark", theme = "teal" }},
          user = {{ preset = "user:Mine", theme = "blizzard" }},
        }}
        saved = {{ Mine = {{ theme = "azeroth", fontScale = 100 }}, Teal = {{ theme = "teal" }} }}
        Bastians:ClearLog()
        {CORE}.migrations[3]({{ sv = {{ profiles = profiles, global = {{ presets = saved }} }} }})
        """
    )
    p = core.eval("profiles")
    assert p.az.preset == "wow" and p.az.theme == "blizzard" and p.az.gameFrames is True
    assert p.az.headingFont == MORPHEUS and p.az.fontScale == 100  # every look setting written
    assert (
        p.custom.preset == "custom" and p.custom.theme == "parchment" and p.custom.fontScale == 90
    )
    assert p.dark.preset == "modern-dark" and p.dark.theme == "teal"
    assert p.user.preset == "user:Mine" and p.user.theme == "blizzard"
    saved = core.eval("saved")
    assert saved.Mine.theme == "parchment" and saved.Mine.fontScale == 100
    assert saved.Teal.theme == "teal"
    lines = [line.text for line in core.eval("Bastians:GetLog()").values()]
    assert any("Azeroth look is gone: 1 profile" in line for line in lines)
    # a profile that wore Azeroth on its own scheme falls back to the first theme, never errors
    core.execute(f"{S}.ApplyTheme('azeroth')")
    assert core.eval(f"{S}.ThemeId()") == "teal"
    assert core.errors == []


def test_the_seven_presets_each_name_a_look_and_a_scheme(core: WowRuntime):
    """plan-round4 H5 (01.11.2026): Modern dark, Modern light, Modern graphite, Night, Glass,
    Parchment, WoW; applying one puts its look and its scheme in force, and the choice lists all."""
    presets = [(p.id, p.name, p["values"]) for p in core.eval(f"{SET}.PRESETS").values()]
    assert [p[0] for p in presets] == [
        "modern-dark",
        "modern-light",
        "modern-graphite",
        "night",
        "glass",
        "parchment",
        "wow",
    ]
    expected = {
        "modern-dark": ("modern", "teal"),
        "modern-light": ("modern", "parchment"),
        "modern-graphite": ("modern", "graphite"),
        "night": ("modern", "night"),
        "glass": ("glass", "teal"),
        "parchment": ("parchment", "parchment"),
        "wow": ("wow", "blizzard"),
    }
    for pid, _, values in presets:
        assert (values.look, values.theme) == expected[pid], pid
        assert core.eval(f"{SET}.ApplyPreset({CORE}, '{pid}')") is True
        assert core.eval(f"{S}.LookId()") == expected[pid][0], pid
        assert core.eval(f"{S}.ThemeId()") == expected[pid][1], pid
    choices = dict(core.eval(f"{SET}.PresetChoices({CORE})"))
    assert choices["night"] == "Night" and choices["glass"] == "Glass"
    assert choices["parchment"] == "Parchment" and choices["modern-graphite"] == "Modern graphite"
    # only the two looks with a frame of their own keep the game's frames on
    for pid, _, values in presets:
        assert values.gameFrames is (pid == "wow"), pid
    assert core.errors == []


def test_the_suites_five_fonts_are_in_the_choices(core: WowRuntime):
    choices = dict(core.eval(f"{SET}.FontChoices()"))
    fonts = "Interface\\AddOns\\Bastians_Core\\Fonts\\"
    for file, name in (
        ("Inter.ttf", "Inter"),
        ("Exo2.ttf", "Exo 2"),
        ("RobotoCondensed.ttf", "Roboto Condensed"),
        ("Alegreya.ttf", "Alegreya"),
        ("Cinzel.ttf", "Cinzel"),
    ):
        assert choices[fonts + file] == name
    # the heading font offers the same plus "the text font"
    values = dict(
        core.eval(
            f"""(function()
              for _, o in ipairs({CORE}.def.options) do
                if o.key == "headingFont" then return o.values() end
              end
            end)()"""
        )
    )
    assert values[""] == "Same as the text" and values[fonts + "Cinzel.ttf"] == "Cinzel"
