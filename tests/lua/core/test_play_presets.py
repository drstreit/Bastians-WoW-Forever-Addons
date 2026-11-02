"""Play presets: the Wanderer, the Scholar and
Everything write the apps' switches, the minimap buttons, a few app settings and the clear-screen
ticks at once; a switch changed by hand afterwards shows Custom; the Suite page carries the
choice."""

import re

from harness import WowRuntime

CORE, DATA, QUESTS, MAP, BROWSER, VOICE = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Map",
    "Bastians_Browser",
    "Bastians_Voice",
)
SETTINGS = "Bastians.UI.Settings"


def strip(text) -> str:
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", str(text or ""))
    return text.replace("|r", "")


def labels(wow: WowRuntime) -> list[str]:
    out = []
    for w in wow.eval("Bastians.UI.Hub.canvas.widgets").values():
        label = w.label
        out.append(strip(label.GetText(label)) if label is not None else "<button>")
    return out


def enabled(wow: WowRuntime, module: str) -> bool:
    return wow.eval(f"Bastians:GetModule('{module}'):IsEnabled()") is True


def test_the_wanderer_keeps_the_world_and_turns_the_desk_off(wow: WowRuntime):
    wow.start(CORE, DATA, QUESTS, MAP, BROWSER, VOICE)
    wow.run_frames(5)
    assert wow.eval(f"{SETTINGS}.PlayId()") is None  # nothing chosen before the first start
    assert wow.eval(f"{SETTINGS}.ApplyPlay('wanderer')") is True
    assert enabled(wow, "Map") and enabled(wow, "Voice")
    assert not enabled(wow, "Quests") and not enabled(wow, "Browser")
    # the conversation without windows is on, the suite's pins leave the minimap
    assert enabled(wow, "Voice.Talk")
    assert wow.eval("Bastians:GetModule('Map').db.profile.minimapPins") is False
    # the minimap buttons: the world's apps keep theirs, the desk's lose them
    assert wow.eval("Bastians.UI.Launcher.AppSettings('Map').hide") is None
    assert wow.eval("Bastians.UI.Launcher.AppSettings('Quests').hide") is True
    assert wow.eval("Bastians.UI.Launcher.AppSettings('Browser').hide") is True
    # the clear-screen key hides every game frame but the action bars
    p = wow.eval("Bastians:GetModule('Core').db.profile")
    assert p.screenMinimap is True and p.screenChat is True and p.screenUnits is True
    assert p.screenBars is False
    assert wow.eval(f"{SETTINGS}.PlayId()") == "wanderer"
    assert wow.errors == []


def test_the_scholar_turns_everything_on_and_the_switches_say_custom_after_a_hand_change(
    wow: WowRuntime,
):
    wow.start(CORE, DATA, QUESTS, MAP, BROWSER, VOICE)
    wow.run_frames(5)
    wow.execute(f"{SETTINGS}.ApplyPlay('wanderer')")
    wow.execute(f"{SETTINGS}.ApplyPlay('scholar')")
    assert enabled(wow, "Quests") and enabled(wow, "Browser") and enabled(wow, "Map")
    assert enabled(wow, "Voice") and not enabled(wow, "Voice.Talk")
    assert wow.eval("Bastians:GetModule('Map').db.profile.minimapPins") is True
    assert wow.eval("Bastians.UI.Launcher.AppSettings('Quests').hide") is None
    p = wow.eval("Bastians:GetModule('Core').db.profile")
    assert p.screenMinimap is False and p.screenBars is False
    assert wow.eval(f"{SETTINGS}.PlayId()") == "scholar"
    # a switch changed by hand on the Suite page: Custom
    wow.execute("Bastians.UI.Hub.Open('suite')")
    texts = labels(wow)
    assert texts[1] == "Play as"  # after the suite's sentence
    q = texts.index("Quests")
    switch = list(wow.eval("Bastians.UI.Hub.canvas.widgets").values())[q + 2]
    assert strip(switch.label.GetText(switch.label)) == "Enabled"
    switch.Click(switch)
    assert not enabled(wow, "Quests")
    assert wow.eval(f"{SETTINGS}.PlayId()") == "custom"
    assert wow.eval(f"{SETTINGS}.ApplyPlay('nothing')") is False
    assert wow.errors == []


def test_the_choice_survives_a_reload_and_every_preset_names_only_known_apps(wow: WowRuntime):
    wow.start(CORE, DATA, QUESTS, MAP)
    wow.run_frames(5)
    wow.execute(f"{SETTINGS}.ApplyPlay('everything')")
    wow = wow.reload()
    wow.run_frames(5)
    assert wow.eval(f"{SETTINGS}.PlayId()") == "everything"
    assert enabled(wow, "Quests") and enabled(wow, "Map")
    modules = {app.module for app in wow.eval("Bastians.APPS").values()}
    modules.add("Gestures")  # the addon of plan-launch-review R5.1, not built yet
    for preset in wow.eval(f"{SETTINGS}.PLAY_PRESETS").values():
        for name in dict(preset.apps):
            assert name in modules, (preset.id, name)
        for name in dict(preset.buttons):
            assert name in modules, (preset.id, name)
    choices = dict(wow.eval(f"{SETTINGS}.PlayChoices()"))
    assert set(choices) == {"wanderer", "scholar", "everything", "custom"}
    assert wow.errors == []
