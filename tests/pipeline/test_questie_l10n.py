"""QuestieDB's l10n lookups -> the packs text_<locale> (data.md "Game data in other languages",
ADR 0033): the local names and objectives of the records our packs carry; the traces win over the
base set; a value outside Latin-1 is dropped; a locale without files builds a stub."""

from pathlib import Path

from bastians_build.build import build
from bastians_build.config import load_config
from bastians_build.l10n import add_l10n
from bastians_build.sources.fixture import read_fixture
from bastians_build.sources.questiedb_l10n import read_locale, source_commit

ROOT = Path(__file__).resolve().parents[1]
L10N = ROOT / "fixtures" / "questie-l10n"
WORLD = ROOT / "fixtures" / "world-mini"
CMANGOS = ROOT / "fixtures" / "cmangos-locales"


def test_a_locale_reads_every_lookup_and_the_traces_win():
    de = read_locale(L10N, "deDE")
    assert de["quest"][176] == {
        "name": 'Gesucht: "Hogger"',
        "objectives": "Bringt die riesige Gnollklaue zu Marschall Dughan in Goldhain.",
    }
    assert de["quest"][62] == {"name": "Die Mine von Tiefenhain"}  # no objectives in the source
    assert de["npc"][240] == {"name": "Marschall Dughan", "subname": "Marschall"}  # traces won
    assert de["npc"][448] == {"name": "Hogger"}  # the traces' Chinese name is dropped
    assert de["item"][2589] == {"name": "Leinenstoff"}
    assert de["object"][1734] == {"name": "Steckbrief"}
    fr = read_locale(L10N, "frFR")
    assert fr["npc"][240] == {"name": "Maréchal Dughan", "subname": "Maréchal"}
    assert fr["quest"] == {}  # a missing file is an empty type
    assert source_commit(L10N) == "fixture0000000000000000000000000000000000"


def test_only_what_our_packs_carry_goes_into_the_packs(tmp_path: Path):
    world = read_fixture(WORLD, "forever")
    added = add_l10n(world, L10N)
    assert set(added) == {"deDE", "frFR", "koKR"}  # no other folder in the fixture
    assert 99999 not in world.records.get("quest_deDE", {})  # not in our quests
    assert world.records["quest_deDE"][176]["name"] == 'Gesucht: "Hogger"'
    assert world.records["npc_frFR"][240]["subname"] == "Maréchal"
    assert any(s.startswith("QuestieDB l10n fixture") for s in world.sources)
    result = build(world, load_config(None), tmp_path, report_dir=tmp_path)
    assert result.ok, result.problems
    de = (tmp_path / "Bastians_Data_Text_deDE" / "Generated" / "Text_deDE.lua").read_text("utf-8")
    assert "Leinenstoff" in de and "Marschall Dughan" in de and "quest_deDE" in de
    es = (tmp_path / "Bastians_Data_Text_esES" / "Generated" / "Text_esES.lua").read_text("utf-8")
    assert "no data" in es and "RegisterPack" not in es  # a stub: the TOC finds its file
    assert de.splitlines()[1] == "if not ({ deDE = true })[GetLocale()] then"  # the guard


def test_cmangos_adds_the_long_quest_texts_in_german_and_chinese():
    """CMaNGOS' quest locales: German with every language's columns and no column list, Chinese
    with its own; QuestieDB's title stays, CMaNGOS' objectives win (they match the English)."""
    from bastians_build.sources.cmangos_locales import read_quest_texts

    de = read_quest_texts(CMANGOS, "deDE")
    assert de[176]["details"].startswith("Hogger terrorisiert") and "progress" not in de[176]
    zh = read_quest_texts(CMANGOS, "zhCN")
    assert zh[176]["name"] == "悬赏：霍格" and 99999 in zh  # noqa: RUF001
    assert read_quest_texts(CMANGOS, "frFR") == {}  # no French in CMaNGOS
    world = read_fixture(WORLD, "forever")
    add_l10n(world, L10N, CMANGOS)
    quest = world.records["quest_deDE"][176]
    assert quest["name"] == 'Gesucht: "Hogger"'  # QuestieDB's title kept
    assert quest["details"].startswith("Hogger terrorisiert")
    assert quest["offer"] == "Ihr habt Elwynn einen großen Dienst erwiesen."
    # Chinese: every text from CMaNGOS
    assert world.records["quest_zhCN"][176]["objectives"].startswith("把巨型")
    assert 99999 not in world.records["quest_zhCN"]
    assert "CMaNGOS quest locales" in world.sources


def test_tdb_gives_the_retail_records_in_every_language():
    """TDB's locale tables (retail): creatures with their title, objects and quest titles;
    esMX only fills what esES lacks (one Spanish); a language of no pack (itIT) is skipped."""
    from bastians_build.sources.tdb_locales import read_locales

    tdb = ROOT / "fixtures" / "tdb-locales.sql"
    got = read_locales(tdb, ("deDE", "frFR", "esES", "koKR"))
    assert got["deDE"]["npc"][240] == {"name": "Marschall Dughan", "subname": "Marschall"}
    assert got["esES"]["npc"][240] == {"name": "Mariscal Dughan", "subname": "Alguacil"}
    assert got["frFR"]["object"][1734] == {"name": "Avis de recherche"}
    # only the title: the retail packs carry no English quest texts to lie over
    assert got["koKR"]["quest"][176] == {"name": "현상 수배: 들창코 호그"}
    assert "itIT" not in got
    world = read_fixture(WORLD, "forever")  # the fixture world stands in for retail here
    add_l10n(world, None, None, tdb)
    assert world.records["npc_deDE"][240]["subname"] == "Marschall"
    assert world.records["quest_koKR"][176] == {"name": "현상 수배: 들창코 호그"}
    assert "TDB locales" in world.sources


def test_tdb_gives_the_asian_long_quest_texts_where_its_english_is_ours():
    """Forever: TDB's Korean and Traditional Chinese details, objectives, offer
    and progress texts, each only where TDB's English of that text is the one our text pack carries
    (spacing and a token's case aside); QuestieDB's title and objectives win."""
    from bastians_build.sources.tdb_locales import read_quest_texts, same_text

    tdb = ROOT / "fixtures" / "tdb-locales.sql"
    assert same_text("Hello $n,  friend.", "Hello $N, friend.")
    assert not same_text("Hello.", "Hello, $N.")
    assert not same_text("", "") and not same_text(None, "")
    world = read_fixture(WORLD, "forever")
    english = world.records["questText"]
    got = read_quest_texts(tdb, ("koKR", "zhTW", "zhCN"), english)
    # the offer's English is a retail one (", $n"), our quest has no progress text: both stay out
    assert got["koKR"][176] == {
        "objectives": "거대한 놀 발톱을 가져가십시오.",
        "details": "호그가 너무 오래 날뛰었습니다.",
    }
    assert got["zhTW"][176] == {
        "objectives": "把巨型豺狼人爪子交給閃金鎮的杜漢元帥。",
        "details": "霍格在艾爾文森林肆虐太久了。",
    }
    assert "zhCN" not in got  # nothing in that language
    add_l10n(world, L10N, None, None, None, tdb)
    ko = world.records["quest_koKR"][176]
    assert ko["details"] == "호그가 너무 오래 날뛰었습니다."
    lookup = read_locale(L10N, "koKR").get("quest", {}).get(176, {})
    for field in ("name", "objectives"):  # the lookups' own texts stay
        if field in lookup:
            assert ko[field] == lookup[field]
    assert world.records["quest_zhTW"][176]["details"].startswith("霍格")
    assert any(src.startswith("TDB quest texts (") for src in world.sources)


def test_tdb_gives_the_latin_languages_their_long_texts_in_latin1():
    """("all pending languages"): French, Spanish and German take TDB's long
    texts too; the typography becomes Latin-1, a text with a character the fonts lack is dropped,
    Spanish reads esMX where esES has none, German keeps CMaNGOS' text where it has one."""
    from bastians_build.sources.tdb_locales import read_quest_texts, to_latin1

    assert to_latin1("d\u2019Elwynn\u2026 \u0153uvre") == "d'Elwynn... oeuvre"
    assert to_latin1("\u4e2d") is None
    tdb = ROOT / "fixtures" / "tdb-locales.sql"
    world = read_fixture(WORLD, "forever")
    got = read_quest_texts(tdb, ("deDE", "frFR", "esES"), world.records["questText"])
    fr = got["frFR"][176]
    assert fr["details"] == (
        "Lardeur terrorise les fermes d'Elwynn depuis trop longtemps... oeuvrez !"
    )
    assert all(ord(c) < 256 for text in fr.values() for c in text)
    assert got["esES"][176]["details"].startswith("Hogger ha aterrorizado")  # from esMX
    world = read_fixture(WORLD, "forever")
    add_l10n(world, L10N, CMANGOS, None, None, tdb)
    assert world.records["quest_deDE"][176]["details"].startswith("Hogger terrorisiert")  # CMaNGOS
    assert world.records["quest_frFR"][176]["details"].startswith("Lardeur terrorise")
    assert world.records["quest_esES"][176]["objectives"].startswith("Lleva la garra")


def test_the_clients_names_in_a_latin_language_go_to_latin1_too():
    """The client's own item names (ADR 0035) carry the same typography (measured 02.11.2026:
    2,830 apostrophes in French); a name with another character stays the client's."""
    world = read_fixture(WORLD, "forever")
    names = {
        "frFR": {"item": {2589: {"name": "Sac d\u2019orge"}}},
        "koKR": {"item": {2589: {"name": "\u2019\uac00"}}},
    }
    add_l10n(world, None, None, None, names)
    assert world.records["item_frFR"][2589]["name"] == "Sac d'orge"
    assert world.records["item_koKR"][2589]["name"] == "\u2019\uac00"  # not a Latin one
