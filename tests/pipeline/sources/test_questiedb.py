"""QuestieDB zone tables against trimmed copies of the real Forever build files."""

from pathlib import Path

from bastians_build.sources import questiedb as qdb

FIX = Path(__file__).resolve().parents[2] / "fixtures" / "sources" / "questiedb"


def text(name: str) -> str:
    return (FIX / name).read_text(encoding="utf-8")


def test_area_to_ui_map_main_and_override():
    table = qdb.parse_area_to_ui_map(text("areaIdToUiMapId.lua"))
    assert table.source_build == "1.60.1.70291"
    m = table.mapping
    assert m[1] == 1426  # main table: Dun Morogh
    assert m[9] == 1429  # Northshire Valley -> Elwynn Forest
    assert m[10073] == 1414  # override: Kalimdor continent map


def test_zero_means_no_map_and_is_kept():
    m = qdb.read_zone_table(text("areaIdToUiMapId.lua"))
    assert m[0] == 0
    assert m[2257] == 0  # Deeprun Tram: display suppression
    assert all(isinstance(k, int) and isinstance(v, int) for k, v in m.items())


def test_override_wins_over_main():
    src = (
        "local ZoneDB = QuestieLoader:ImportModule('ZoneDB')\n"
        "ZoneDB.private.areaIdToUiMapIdOverride = [[return { [5] = 0, [6] = 7 }]]\n"
        "ZoneDB.private.areaIdToUiMapId = [[return { [5] = 11, [6] = 12, [8] = 13 }]]\n"
    )
    table = qdb.parse_area_to_ui_map(src)
    assert table.mapping == {5: 0, 6: 7, 8: 13}
    assert table.source_build is None  # no build comment: unknown


def test_missing_override_table_is_fine():
    src = (
        "local ZoneDB = QuestieLoader:ImportModule('ZoneDB')\n"
        "ZoneDB.private.areaIdToUiMapId = [[return { [1] = 2 }]]\n"
    )
    assert qdb.read_zone_table(src) == {1: 2}


def test_ui_map_to_area():
    table = qdb.parse_ui_map_to_area(text("uiMapIdToAreaId.lua"))
    assert table.source_build == "1.60.1.69893"  # "Manually completed ... for build" line
    m = table.mapping
    assert m[1411] == 14  # Durotar
    assert m[1414] == 10073  # override: Kalimdor synthetic area
    assert m[947] == 10089
    assert qdb.read_ui_map_to_area(text("uiMapIdToAreaId.lua")) == m


def test_file_helpers():
    assert qdb.read_area_to_ui_map_file(FIX / "areaIdToUiMapId.lua").mapping[1] == 1426
    assert qdb.read_ui_map_to_area_file(FIX / "uiMapIdToAreaId.lua").mapping[1412] == 215
