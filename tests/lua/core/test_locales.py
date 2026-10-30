"""French, Spanish, Korean and Chinese: every addon of the suite but
the Library registers its strings from Locales/frFR.lua, esES.lua, koKR.lua, zhCN.lua and
zhTW.lua, right after the German file. One Spanish text serves both Spanish clients: esES.lua
registers its table for esES and esMX. The files are checked as the German ones
(test_locale_dede.py): they load, keep the format directives of the English key, and translate
every literal L["..."] of the addon's sources; the Latin languages stay Latin-1 (the game fonts),
the Asian ones are drawn by their client's own fonts."""

import re

import pytest
from harness import ADDONS, WowRuntime
from lupa import lua51
from test_locale_dede import DIRECTIVE, labels, source_keys

APPS = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Map",
    "Bastians_Browser",
    "Bastians_Gold",
    "Bastians_Route",
    "Bastians_Strategies",
    "Bastians_Notes",
)
# the file of a locale and the client locales it registers for
LOCALES = {
    "frFR": ("frFR",),
    "esES": ("esES", "esMX"),
    "koKR": ("koKR",),
    "zhCN": ("zhCN",),
    "zhTW": ("zhTW",),
}
LATIN1 = {"frFR", "esES"}  # the Asian clients bring the fonts for their scripts
CASES = [(app, loc) for app in APPS for loc in LOCALES]


def registered(app: str, locale: str) -> dict[str, dict[str, str]]:
    """Run an app's locale file against a stub Locale: { client locale = strings }."""
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(
        """
        captured = {}
        local stub = { Register = function(_, locale, strings) captured[locale] = strings end }
        Bastians = { NewLocale = function() return stub end }
        ns_stub = { L = stub }
        """
    )
    path = ADDONS / app / "Locales" / f"{locale}.lua"
    chunk = lua.globals().loadstring(path.read_text(encoding="utf-8"), f"@{path.name}")
    assert not isinstance(chunk, tuple), chunk
    chunk(app, lua.globals().ns_stub)
    out = {}
    for loc, strings in lua.globals().captured.items():
        out[str(loc)] = {str(k): str(v) for k, v in strings.items()}
    return out


@pytest.mark.parametrize(("app", "locale"), CASES)
def test_the_file_loads_registers_its_clients_and_stays_latin1(app: str, locale: str):
    path = ADDONS / app / "Locales" / f"{locale}.lua"
    assert path.is_file(), path
    tables = registered(app, locale)
    assert sorted(tables) == sorted(LOCALES[locale])
    strings = tables[locale]
    assert all(t == strings for t in tables.values())  # esMX reads the esES text
    assert len(strings) >= 20
    for key, value in strings.items():
        assert value.strip(), key
        if locale in LATIN1:
            assert all(ord(c) < 256 for c in key + value), f"outside Latin-1: {key!r}: {value!r}"
    written = re.findall(r'^\s*\["((?:[^"\\]|\\.)*)"\] =', path.read_text(encoding="utf-8"), re.M)
    assert len(written) == len(set(written)), sorted(k for k in written if written.count(k) > 1)


@pytest.mark.parametrize(("app", "locale"), CASES)
def test_the_directives_match_the_english_key(app: str, locale: str):
    for key, value in registered(app, locale)[locale].items():
        assert DIRECTIVE.findall(key) == DIRECTIVE.findall(value), (key, value)
        assert key[:1].isspace() == value[:1].isspace(), (key, value)
        assert key[-1:].isspace() == value[-1:].isspace(), (key, value)
        assert key.count("|") == value.count("|"), (key, value)
        assert key.count("\n") == value.count("\n"), (key, value)


@pytest.mark.parametrize(("app", "locale"), CASES)
def test_every_literal_key_has_a_text(app: str, locale: str):
    strings = registered(app, locale)[locale]
    missing = sorted(k for k in source_keys(app) if k not in strings and k != "Text")
    assert missing == []


@pytest.mark.parametrize(("app", "locale"), CASES)
def test_every_german_key_has_a_text_too(app: str, locale: str):
    # words that reach L[variable] (kinds, statuses, types) are listed in the German file only
    german = ADDONS / app / "Locales" / "deDE.lua"
    keys = set(
        re.findall(r'^\s*\["((?:[^"\\]|\\.)*)"\] =', german.read_text(encoding="utf-8"), re.M)
    )
    strings = registered(app, locale)[locale]
    missing = sorted(k for k in keys if k.replace('\\"', '"') not in strings)
    assert missing == []


def test_the_toc_loads_them_right_after_the_german_file(wow: WowRuntime):
    for app in APPS:
        files = [f for f in wow.mock.addons[app].files.values() if f.lower().endswith(".lua")]
        i = files.index("Locales\\deDE.lua")
        assert files[i + 1 : i + 6] == [
            "Locales\\frFR.lua",
            "Locales\\esES.lua",
            "Locales\\koKR.lua",
            "Locales\\zhCN.lua",
            "Locales\\zhTW.lua",
        ], app


@pytest.mark.parametrize("locale", ["frFR", "esES", "esMX", "koKR", "zhCN", "zhTW"])
def test_a_client_in_that_language_sees_it(wow: WowRuntime, locale: str):
    wow.mock.locale = locale
    wow.start(
        "Bastians_Core", "Bastians_Data", "Bastians_Quests", "Bastians_Map", "Bastians_Browser"
    )
    wow.run_frames(5)
    file = "esES" if locale == "esMX" else locale
    core = registered("Bastians_Core", file)[file]
    assert wow.eval("Bastians.L['Close']") == core["Close"] != "Close"
    wow.execute("Bastians.UI.Hub.Open('Core')")
    assert core["Colour scheme"] in labels(wow)
    assert wow.errors == []
