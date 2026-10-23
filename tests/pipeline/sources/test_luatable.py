"""The shared Lua data loader: runs a source data file in a sandbox and converts its tables."""

import pytest

from bastians_build.sources.luatable import (
    LuaDataError,
    eval_long_string,
    load_ns,
    new_runtime,
    run_file,
    to_python,
)


def test_load_ns_runs_a_data_file_with_varargs(tmp_path):
    path = tmp_path / "Data.lua"
    path.write_text(
        'local _, ns = ...\nns.npcs = {[54]={"Corina Steele","Weaponsmith",1429,41.6,65.8,"A",1}}\n'
        "ns.list = {10, 20, 30}\nns.sparse = {[1] = 'a', [3] = 'c'}\nns.flag = true\n",
        encoding="utf-8",
    )
    ns = load_ns(path)
    assert ns["npcs"] == {54: ["Corina Steele", "Weaponsmith", 1429, 41.6, 65.8, "A", 1]}
    assert ns["list"] == [10, 20, 30]
    assert ns["sparse"] == {1: "a", 3: "c"}  # not 1..n: stays a dict
    assert ns["flag"] is True


def test_long_strings_evaluate_to_tables(tmp_path):
    path = tmp_path / "Spawns.lua"
    path.write_text(
        "local _, ns = ...\n"
        "ns.SRC = [==[return { [6]={[1429]={1357524825}}, [7]={[1429]={1,2}} }]==]\n",
        encoding="utf-8",
    )
    lua = new_runtime()
    ns = run_file(lua, path)
    table = to_python(eval_long_string(lua, ns.SRC))
    assert table == {6: {1429: [1357524825]}, 7: {1429: [1, 2]}}


def test_stubbed_globals_and_errors(tmp_path):
    path = tmp_path / "Zones.lua"
    path.write_text(
        'local ZoneDB = QuestieLoader:ImportModule("ZoneDB")\n'
        "ZoneDB.private.areaIdToUiMapId = [[return { [7] = 1429 }]]\n"
        'local lib = LibStub("AceAddon-3.0"):NewAddon("X")\n',
        encoding="utf-8",
    )
    lua = new_runtime()
    run_file(lua, path)
    zones = to_python(eval_long_string(lua, lua.globals().ZoneDB.private.areaIdToUiMapId))
    assert zones == {7: 1429}
    bad = tmp_path / "Bad.lua"
    bad.write_text("local _, ns = ...\nns.x = {", encoding="utf-8")
    with pytest.raises(LuaDataError, match=r"Bad\.lua"):
        load_ns(bad)
    unsafe = tmp_path / "Unsafe.lua"
    unsafe.write_text("local _, ns = ...\nns.y = SomeUnknownGlobal()\n", encoding="utf-8")
    with pytest.raises(LuaDataError):
        load_ns(unsafe)


def test_utf8_bom_and_floats():
    assert to_python(3.0) == 3 and to_python(0.27) == 0.27
    assert to_python("x") == "x"
