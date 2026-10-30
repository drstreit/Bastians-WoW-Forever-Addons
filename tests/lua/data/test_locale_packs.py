"""The game data in the client's language (data.md "Game data in other languages", ADR 0033): on a
German or French client the records carry their local names, an NPC its local subname, a quest
text its local objectives; the search finds the local and the English name; an English client and
a client whose pack is a stub (the fixture has no Spanish) are unchanged."""

from harness import WowRuntime

CORE, DATA = "Bastians_Core", "Bastians_Data"
D = 'Bastians:GetService("data")'
LOCALE_PACK = {"esMX": "esES", "enUS": "deDE"}  # an English client asks for a pack it never reads


def boot(wow: WowRuntime, locale: str) -> WowRuntime:
    wow.mock.locale = locale
    wow.start(CORE, DATA)
    wow.run_frames(10)
    for pack in ("world", "quests", "items", "text", "text_" + LOCALE_PACK.get(locale, locale)):
        wow.execute(f"{D}:LoadPack('{pack}')")
    return wow


def found(wow: WowRuntime, typ: str, text: str) -> list:
    return [(h.id, h.name) for h in wow.eval(f"{D}:Find('{typ}', '{text}')").values()]


def test_a_german_client_reads_the_german_names_and_objectives(wow: WowRuntime):
    boot(wow, "deDE")
    assert wow.eval("Bastians.Data.locale") == "deDE"
    dughan = wow.eval(f"{D}:Get('npc', 240)")
    assert (dughan.name, dughan.subname, dughan.nameEN) == (
        "Marschall Dughan",
        "Marschall",
        "Marshal Dughan",
    )
    assert wow.eval(f"{D}:Get('item', 2589).name") == "Leinenstoff"
    assert wow.eval(f"{D}:Get('object', 1734).name") == "Steckbrief"
    assert wow.eval(f"{D}:Get('quest', 176).name") == 'Gesucht: "Hogger"'
    text = wow.eval(f"{D}:Get('questText', 176)")
    assert text.objectives == "Bringt die riesige Gnollklaue zu Marschall Dughan in Goldhain."
    # CMaNGOS' German quest locales give the long texts; the objectives are CMaNGOS' too
    assert text.details == "Hogger terrorisiert die Höfe des Waldes von Elwynn schon zu lange."
    assert text.offer == "Ihr habt Elwynn einen großen Dienst erwiesen."
    assert text.detailsEN == "Hogger has terrorised the farms of Elwynn long enough."
    assert wow.eval("Bastians:Entity('npc:240'):Name()") == "Marschall Dughan"
    # the search: the German name, and the English one still finds the record
    assert found(wow, "item", "leinen") == [(2589, "Leinenstoff")]
    assert found(wow, "item", "linen") == [(2589, "Linen Cloth")]
    assert wow.errors == []


def test_zones_take_the_clients_names(wow: WowRuntime):
    """Zones and subzones need no pack: the client names them in its own language."""
    wow.mock.locale = "deDE"
    wow.start(CORE, DATA)
    wow.execute("Mock.maps[1429].name = 'Wald von Elwynn'")
    wow.run_frames(10)
    wow.execute(f"{D}:LoadPack('world')")
    zone = wow.eval(f"{D}:Get('zone', 1429)")
    assert (zone.name, zone.nameEN) == ("Wald von Elwynn", "Elwynn Forest")
    assert found(wow, "zone", "wald") == [(1429, "Wald von Elwynn")]
    assert found(wow, "zone", "elwynn")[0][0] == 1429  # the English name still finds it
    assert wow.errors == []


def test_a_french_client_reads_the_french_pack(wow: WowRuntime):
    boot(wow, "frFR")
    dughan = wow.eval(f"{D}:Get('npc', 240)")
    assert (dughan.name, dughan.subname) == ("Maréchal Dughan", "Maréchal")
    assert wow.eval(f"{D}:Get('item', 2589).name") == "Linen Cloth"  # not in the French fixture
    assert wow.errors == []


def test_an_english_client_and_a_stub_pack_change_nothing(wow: WowRuntime):
    boot(wow, "enUS")
    assert wow.eval("Bastians.Data.locale") is None
    dughan = wow.eval(f"{D}:Get('npc', 240)")
    assert (dughan.name, dughan.nameEN) == ("Marshal Dughan", None)
    assert wow.eval(f"{D}:Get('questText', 176).objectives") == (
        "Bring Huge Gnoll Claw to Marshal Dughan in Goldshire."
    )
    fresh = WowRuntime(wow.client, wow.addons_dir, wow.extra_dirs)
    boot(fresh, "esMX")  # Mexican reads the Spanish pack: a stub in the fixture
    assert fresh.eval("Bastians.Data.locale") == "esES"
    assert fresh.eval(f"{D}:Get('npc', 240).name") == "Marshal Dughan"
    assert wow.errors == [] and fresh.errors == []


def test_a_korean_and_a_chinese_client_read_their_packs(wow: WowRuntime):
    boot(wow, "koKR")
    dughan = wow.eval(f"{D}:Get('npc', 240)")
    assert (dughan.name, dughan.subname) == ("보안관 듀간", "보안관")
    assert wow.errors == []
    fresh = WowRuntime(wow.client, wow.addons_dir, wow.extra_dirs)
    boot(fresh, "zhCN")  # CMaNGOS' Simplified Chinese quest texts
    assert fresh.eval(f"{D}:Get('quest', 176).name") == "悬赏：霍格"  # noqa: RUF001
    assert fresh.eval(f"{D}:Get('questText', 176).details").startswith("霍格在艾尔文森林")
    assert fresh.errors == []


def test_an_item_the_pack_lacks_takes_the_clients_name(wow: WowRuntime):
    """On a client in another language the client's own name wins over the English pack name."""
    claw = (
        "Mock.items[1931] = { name = 'Riesige Gnollklaue', quality = 1, level = 1, "
        "class = 'Quest', sell = 0, stack = 1, icon = 1 }"
    )
    boot(wow, "deDE")
    wow.execute(claw)
    assert wow.eval("Bastians:Entity('item:1931'):Name()") == "Riesige Gnollklaue"
    assert wow.eval("Bastians:Entity('item:2589'):Name()") == "Leinenstoff"  # the pack's
    fresh = WowRuntime(wow.client, wow.addons_dir, wow.extra_dirs)
    boot(fresh, "enUS")
    fresh.execute(claw)
    assert fresh.eval("Bastians:Entity('item:1931'):Name()") == "Huge Gnoll Claw"  # the pack's
    assert wow.errors == [] and fresh.errors == []
