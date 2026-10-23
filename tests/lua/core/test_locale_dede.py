"""The German locale (deDE): every addon registers its strings from Locales/deDE.lua before its other
files load, so load-time labels and run-time texts come out German on a German client and stay
English on any other. The files are checked for load errors, Latin-1 only characters (the game fonts
cover umlauts and the sharp s, not typographic symbols), format directives that match the English
key, and a German text for every literal L["..."] in the addon's sources."""

import re

import pytest
from harness import ADDONS, WowRuntime
from lupa import lua51

APPS = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Map",
    "Bastians_Browser",
    "Bastians_Gold",
    "Bastians_Route",
    "Bastians_Strategies",
)
LOCALE_FILES = {app: ADDONS / app / "Locales" / "deDE.lua" for app in APPS}
LITERAL_KEY = re.compile(r"""\bL\[("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')\]""")
DIRECTIVE = re.compile(r"%[-+ #0]*\d*(?:\.\d+)?[a-zA-Z%]")


def registered_strings(app: str) -> dict[str, str]:
    """Run an app's deDE file against a stub Locale and return what it registers."""
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(
        """
        captured = {}
        local stub = { Register = function(_, locale, strings)
          assert(locale == "deDE", "registers another locale: " .. tostring(locale))
          captured = strings
        end }
        Bastians = { NewLocale = function() return stub end }
        ns_stub = { L = stub }
        """
    )
    path = LOCALE_FILES[app]
    chunk = lua.globals().loadstring(path.read_text(encoding="utf-8"), f"@{path.name}")
    assert not isinstance(chunk, tuple), chunk
    chunk(app, lua.globals().ns_stub)
    return {str(k): str(v) for k, v in lua.globals().captured.items()}


def source_keys(app: str) -> set[str]:
    """Every literal key of L["..."] in the addon's hand-written Lua files."""
    lua = lua51.LuaRuntime()
    keys: set[str] = set()
    for path in sorted((ADDONS / app).rglob("*.lua")):
        if {"Libs", "Generated", "Locales"} & set(path.relative_to(ADDONS / app).parts):
            continue
        for match in LITERAL_KEY.finditer(path.read_text(encoding="utf-8")):
            keys.add(lua.eval(match.group(1)))
    return keys


def labels(wow: WowRuntime) -> list[str]:
    """The texts on the settings page the hub shows."""
    return [
        w.label.GetText(w.label)
        for w in wow.eval("Bastians.UI.Hub.canvas.widgets").values()
        if w.label is not None
    ]


def german_client(wow: WowRuntime, locale: str, *addons: str) -> None:
    wow.mock.locale = locale
    wow.start(*addons)
    wow.run_frames(5)


@pytest.mark.parametrize("app", APPS)
def test_the_german_file_loads_and_stays_latin1(app: str):
    path = LOCALE_FILES[app]
    assert path.is_file()
    strings = registered_strings(app)
    assert len(strings) > 30
    for key, value in strings.items():
        assert value.strip(), key
        assert all(ord(c) < 256 for c in key + value), f"outside Latin-1 in {key!r}: {value!r}"
    # no key twice in the file (a Lua table constructor keeps the last one silently)
    written = re.findall(r'^\s*\["((?:[^"\\]|\\.)*)"\] =', path.read_text(encoding="utf-8"), re.M)
    assert len(written) == len(set(written)), sorted(k for k in written if written.count(k) > 1)


@pytest.mark.parametrize("app", APPS)
def test_the_directives_match_the_english_key(app: str):
    for key, value in registered_strings(app).items():
        assert DIRECTIVE.findall(key) == DIRECTIVE.findall(value), (key, value)
        assert key[:1].isspace() == value[:1].isspace(), (key, value)
        assert key[-1:].isspace() == value[-1:].isspace(), (key, value)
        assert key.count("|") == value.count("|"), (key, value)
        assert key.count("\n") == value.count("\n"), (key, value)


@pytest.mark.parametrize("app", APPS)
def test_every_literal_key_has_a_german_text(app: str):
    strings = registered_strings(app)
    missing = sorted(k for k in source_keys(app) if k not in strings and k != "Text")
    assert missing == []


def test_the_toc_loads_the_german_file_first(wow: WowRuntime):
    for app in APPS:
        files = [f for f in wow.mock.addons[app].files.values() if f.lower().endswith(".lua")]
        files = [f for f in files if not f.startswith("Libs")]
        expected = "Locale.lua" if app == "Bastians_Core" else None
        if expected:
            assert files[files.index(expected) + 1] == "Locales\\deDE.lua"
        else:
            assert files[0] == "Locales\\deDE.lua", app


def test_a_german_client_sees_german_load_time_labels_and_runtime_texts(wow: WowRuntime):
    german_client(
        wow,
        "deDE",
        "Bastians_Core",
        "Bastians_Data",
        "Bastians_Quests",
        "Bastians_Map",
        "Bastians_Browser",
        "Bastians_Gold",
        "Bastians_Route",
    )
    # Core: a run-time text and a theme name read at load time
    assert wow.eval("Bastians.L['Close']") == "Schließen"
    wow.execute("Bastians.UI.Hub.Open('Core')")
    assert "Farbschema" in labels(wow)
    # the apps' option labels are read while their files load
    expected = {
        "Quests": "Der Tracker (Meine Quests)",
        "Map": "Die Minimap",
        "Gold": "Verfügbare Spielzeit (Minuten)",
        "Route": "Zu nutzende Flugrouten",
    }
    for name, text in expected.items():
        wow.execute(f"Bastians.UI.Hub.Open('{name}')")
        assert text in labels(wow), name
    # Data names the kinds, the Browser groups by the English key
    d = "Bastians:GetService('data')"
    assert list(wow.eval(f"{{ {d}:Kind('object', 'mailbox') }}").values()) == [
        "Briefkasten",
        "Mailbox",
    ]
    assert list(wow.eval(f"{{ {d}:Kind('npc', 'flightmaster') }}").values()) == [
        "Flugmeister",
        "Flight master",
    ]
    # one English word, two German ones: the NPC rank is "Rar", the item quality "Selten"
    assert list(wow.eval(f"{{ {d}:Kind('npc', 'rare') }}").values()) == ["Rar", "Rare##rank"]
    wow.execute("Bastians.UI.Hub.Open('Browser')")
    assert "Den Zielverfolger des Spiels im schmalen Modus ausblenden" in labels(wow)
    assert wow.errors == []


def test_an_english_client_is_unchanged(wow: WowRuntime):
    german_client(
        wow,
        "enUS",
        "Bastians_Core",
        "Bastians_Data",
        "Bastians_Quests",
        "Bastians_Map",
        "Bastians_Browser",
        "Bastians_Gold",
    )
    assert wow.eval("Bastians.L['Close']") == "Close"
    wow.execute("Bastians.UI.Hub.Open('Quests')")
    assert "The tracker (My quests)" in labels(wow)
    wow.execute("Bastians.UI.Hub.Open('Gold')")
    assert "Play time available (minutes)" in labels(wow)
    d = "Bastians:GetService('data')"
    assert list(wow.eval(f"{{ {d}:Kind('object', 'mailbox') }}").values()) == [
        "Mailbox",
        "Mailbox",
    ]
    # a key's context after "##" never shows
    assert list(wow.eval(f"{{ {d}:Kind('npc', 'rare') }}").values()) == ["Rare", "Rare##rank"]
    assert wow.eval("Bastians.L['Rare##rank']") == "Rare"
    assert wow.errors == []
