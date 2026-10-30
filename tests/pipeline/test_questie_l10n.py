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
