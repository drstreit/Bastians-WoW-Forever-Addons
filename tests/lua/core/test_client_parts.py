"""What a client needs: the parts of the suite the installed
apps need, the optional addons per client (retail never hears of QuestieDB or Spoken), the login
lines (missing parts every login, the optional addons once at the first start and after every
update of any part), the General page, `/bastians addons` and Data's chat line for a pack built
for the other client."""

import re

from harness import WowRuntime

CORE, DATA, QUESTS, MAP, GOLD, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Map",
    "Bastians_Gold",
    "Bastians_Browser",
)
PACKS = ("Bastians_Data_Quests", "Bastians_Data_World", "Bastians_Data_Items")
SETTINGS = "Bastians.UI.Settings"
CLIENT_NAME = {"forever": "WoW Forever", "retail": "retail"}


def strip(text: str) -> str:
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text or "")
    return text.replace("|r", "")


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, QUESTS, MAP, GOLD, BROWSER)))
    wow.run_frames(5)
    return wow


def labels(wow: WowRuntime) -> list[str]:
    out = []
    for w in wow.eval("Bastians.UI.Hub.canvas.widgets").values():
        out.append(w.label.GetText(w.label) if w.label is not None else "")
    return out


def test_the_optional_addons_differ_per_client(wow: WowRuntime):
    boot(wow, CORE)
    names = [c.addon for c in wow.eval(f"{SETTINGS}.Companions()").values()]
    if wow.client == "forever":
        assert sorted(names) == ["QuestieDB", "Spoken", "TomTom"]
    else:
        assert names == ["TomTom"]  # QuestieDB and Spoken ship for the Classic flavours only
    assert len(list(wow.eval(f"{SETTINGS}.Companions('forever')").values())) == 3
    assert wow.eval(f"{SETTINGS}.AppliesHere('Spoken_Quests')") is (wow.client == "forever")
    assert wow.eval(f"{SETTINGS}.AppliesHere('TomTom')") is True
    assert wow.eval(f"{SETTINGS}.AppliesHere('Bastians_Map_Art')") is True
    assert wow.errors == []


def test_the_parts_follow_what_the_apps_declare(wow: WowRuntime):
    boot(wow)
    parts = {p.addon: p for p in wow.eval(f"{SETTINGS}.Parts()").values()}
    assert list(parts) == [
        "Bastians_Core",
        "Bastians_Data",
        "Bastians_Data_Quests",
        "Bastians_Data_World",
        "Bastians_Data_Items",
        "Bastians_Map_Art",
    ]  # the order of B.SUITE_ADDONS; Market is an optional pack, never required
    assert all(parts[a].required for a in (CORE, DATA, *PACKS))
    assert parts["Bastians_Map_Art"].required is False  # Map draws zone art without it
    assert parts["Bastians_Map_Art"].installed is True
    wow.execute("Mock.addons['Bastians_Map_Art'] = nil")  # optional: no missing part without it
    assert wow.eval(f"{SETTINGS}.Parts()[6].installed") is False
    assert sorted(parts["Bastians_Data_World"].neededBy.values()) == ["Browser", "Map", "Quests"]
    assert sorted(parts["Bastians_Data_Items"].neededBy.values()) == ["Browser", "Gold", "Quests"]
    assert wow.eval(f"{SETTINGS}.MissingParts()") is None
    before = len(wow.chat)
    assert wow.eval(f"{SETTINGS}.NoteParts()") is False and len(wow.chat) == before
    # a pack goes missing: said at every login, with the client and which zips to take
    wow.execute("Mock.addons['Bastians_Data_World'] = nil")
    missing = list(wow.eval(f"{SETTINGS}.MissingParts()").values())
    assert missing == ["Bastians_Data_World (needed by Quests, Map, Browser)"]
    assert wow.eval(f"{SETTINGS}.NoteParts()") is True
    assert wow.eval(f"{SETTINGS}.NoteParts()") is True  # every time while broken
    line = strip(wow.chat[-1])
    name = CLIENT_NAME[wow.client]
    assert f"Missing parts for {name}: Bastians_Data_World (needed by" in line
    assert f"Install the {name} files (the bundle or the -{wow.client} zips)" in line
    # installed but switched off in the AddOns list: as broken as missing, and said so
    wow.execute("Mock.addons['Bastians_Data_World'] = { meta = {}, files = {} }")
    wow.execute("Mock.disabledAddons = { Bastians_Data_Items = true }")
    missing = list(wow.eval(f"{SETTINGS}.MissingParts()").values())
    assert missing == [
        "Bastians_Data_Items (switched off in the AddOns list, needed by Quests, Gold, Browser)"
    ]
    assert wow.eval("Bastians.Compat.IsAddOnEnabled('Bastians_Data_Items')") is False
    assert wow.eval("Bastians.Compat.IsAddOnEnabled('Bastians_Data_Quests')") is True
    assert wow.eval("Bastians.Compat.IsAddOnEnabled('Nope')") is False
    wow.execute("Bastians.UI.Hub.Open('Core')")
    assert (
        "Bastians_Data_Items: Needed by Quests, Gold, Browser. "
        "Switched off in the AddOns list at character select." in labels(wow)
    )
    assert wow.errors == []


def test_the_login_says_missing_parts_and_the_optional_addons_once_per_update(wow: WowRuntime):
    wow.execute("Mock.addons = Mock.addons")  # the test addons as installed
    boot(wow)
    lines = [strip(x) for x in wow.chat]
    optional = [x for x in lines if "Optional addons for" in x]
    assert len(optional) == 1  # the first start
    if wow.client == "forever":
        assert "QuestieDB (installed)" in optional[0] and "TomTom (installed)" in optional[0]
    else:
        assert "Optional addons for retail: TomTom (installed)." in optional[0]
        assert "QuestieDB" not in optional[0] and "Spoken" not in optional[0]
    assert not any("Missing parts" in x for x in lines)  # the test install is complete
    noted = wow.eval("Bastians:GetModule('Core').db.global.companionsNoted")
    assert noted.startswith(wow.client + ";Bastians_Core=")
    # a reload: nothing new, the same suite
    fresh = wow.reload()
    fresh.run_frames(5)
    assert not any("Optional addons for" in strip(x) for x in fresh.chat)
    # an update of any part (not only Core): said again, once
    fresh.execute("Mock.addons['Bastians_Quests'].meta.Version = '9.9.9'")
    assert fresh.eval(f"{SETTINGS}.NoteCompanions()") is True
    assert fresh.eval(f"{SETTINGS}.NoteCompanions()") is False
    # a missing companion is said with what it would add
    fresh.execute("Mock.addons['TomTom'] = nil; Mock.addons['Bastians_Gold'].meta.Version = 'x'")
    assert fresh.eval(f"{SETTINGS}.NoteCompanions()") is True
    assert "TomTom (not installed: a waypoint arrow" in strip(fresh.chat[-1])
    assert fresh.errors == []


def test_the_general_page_and_the_app_pages_tell_this_clients_story(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.addons['QuestieDB'] = nil; Mock.addons['Bastians_Map_Art'] = nil")
    wow.execute("Bastians.UI.Hub.Open('Core')")
    texts = labels(wow)
    name = CLIENT_NAME[wow.client]
    parts = texts.index(f"Bastian's addons for {name}")
    optional = texts.index(f"Optional addons for {name}")
    assert parts < optional
    part_rows = texts[parts + 1 : optional]
    assert part_rows[0] == "Bastians_Core: Installed."
    assert "Bastians_Data_World: Needed by Quests, Map, Browser. Installed." in part_rows
    assert "Bastians_Map_Art: Needed by Map. Not installed (optional)." in part_rows
    companion_rows = [t for t in texts[optional + 1 :] if ": " in t][:3]
    if wow.client == "forever":
        assert any(r.startswith("QuestieDB:") and "Not installed:" in r for r in companion_rows)
    else:
        assert companion_rows[0].startswith("TomTom:") and not any(
            "QuestieDB" in r or "Spoken" in r for r in texts
        )
    # an app's page names its missing optional addon only where it exists
    wow.execute("Bastians.UI.Hub.Open('Quests')")
    quests = labels(wow)
    says = any(t.startswith("QuestieDB is not installed") for t in quests)
    assert says is (wow.client == "forever")
    # a required part missing: the page says MISSING with the client's files
    wow.execute("Mock.addons['Bastians_Data_Items'] = nil; Bastians.UI.Hub.Open('Core')")
    assert (
        f"Bastians_Data_Items: Needed by Quests, Gold, Browser. MISSING: install the {name} files."
        in labels(wow)
    )
    assert wow.errors == []


def test_slash_addons_lists_both(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.addons['Bastians_Map_Art'] = nil")
    before = len(wow.chat)
    wow.slash("/bastians addons")
    lines = [strip(x) for x in wow.chat[before:]]
    assert lines[0].endswith("Bastians_Core: installed")
    assert any(
        x.endswith("Bastians_Map_Art: not installed (optional) - needed by Map") for x in lines
    )
    assert "Optional addons for" in lines[-1]
    assert wow.errors == []


def test_a_pack_for_the_other_client_is_said_in_chat_once(wow: WowRuntime):
    boot(wow, CORE, DATA)
    other = "retail" if wow.client == "forever" else "forever"
    before = len(wow.chat)
    wow.execute(
        f"""
        Bastians.Data.RegisterPack('xa', {{ client = '{other}', schema = {{}} }})
        Bastians.Data.RegisterPack('xb', {{ client = '{other}', schema = {{}} }})
        """
    )
    wow.advance(0.6)
    wow.run_frames(3)
    said = [strip(x) for x in wow.chat[before:]]
    assert len(said) == 1  # one line for the burst
    assert f"Packs built for another client: xa ({other}), xb ({other})" in said[0]
    assert wow.errors == []


def test_the_curseforge_relations_match_the_game(wow: WowRuntime):
    """tools/curseforge.toml and the game tell the same story: the companions exist on the same
    clients, and every app whose data the hub calls required relates to Data as required."""
    import tomllib
    from pathlib import Path

    cfg = tomllib.loads(
        (Path(__file__).resolve().parents[3] / "tools" / "curseforge.toml").read_text("utf-8")
    )
    boot(wow, CORE, DATA, QUESTS, MAP, GOLD, BROWSER, "Bastians_Route")
    companions = {
        c.addon: sorted(c.clients.values()) for c in wow.eval("Bastians.COMPANIONS").values()
    }
    assert companions == {n: sorted(e["clients"]) for n, e in cfg["external"].items()}
    parts = {p.addon: p for p in wow.eval(f"{SETTINGS}.Parts()").values()}
    folder = {
        "Quests": "Bastians_Quests",
        "Map": "Bastians_Map",
        "Gold": "Bastians_Gold",
        "Browser": "Bastians_Browser",
        "Route": "Bastians_Route",
    }
    needing = list(parts["Bastians_Data"].neededBy.values())
    assert sorted(needing) == sorted(folder)  # every app declares data
    owner = {f: name for name, p in cfg["projects"].items() for f in p["folders"]}
    for app in needing:  # the project that ships the app requires Data's (ADR 0019: the suite)
        assert "Bastians_Data" in cfg["projects"][owner[folder[app]]]["required"], app
    assert wow.errors == []
