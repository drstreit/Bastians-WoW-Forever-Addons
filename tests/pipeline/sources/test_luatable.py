"""The shared Lua data loader: runs a source data file in a sandbox and converts its tables."""

from pathlib import Path

import pytest

from bastians_build.sources import luatable
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


def test_other_peoples_files_reach_neither_files_nor_processes_nor_python(tmp_path):
    """02.11.2026 (the sources update themselves daily, tools/sources_update.py): a data file runs
    on a Lua without os, io, debug, package, require, dofile, loadfile, load and lupa's python;
    a file that tries one fails as a data error, the string and table libraries stay."""
    from bastians_build.sources import allthethings, itemdb, probe

    lua = luatable.new_runtime()
    for name in luatable.UNSAFE:
        assert lua.eval(f"rawget(_G, '{name}')") is None, name
    assert (
        lua.eval("string.format('%d', 7)") == "7" and lua.eval("type(table.insert)") == "function"
    )
    evil = tmp_path / "Evil.lua"
    evil.write_text('local _, ns = ...\nos.execute("echo pwned")\n', encoding="utf-8")
    with pytest.raises(luatable.LuaDataError, match="os"):
        luatable.run_file(lua, evil)
    sneaky = tmp_path / "Sneaky.lua"
    sneaky.write_text('local _, ns = ...\nns.f = io.open("x", "w")\n', encoding="utf-8")
    with pytest.raises(luatable.LuaDataError, match="io"):
        luatable.run_file(luatable.new_runtime(), sneaky)
    # the readers that build their own runtime use the same one
    for module in (allthethings, itemdb, probe):
        source = Path(module.__file__).read_text(encoding="utf-8")
        assert "safe_runtime()" in source and "lua51.LuaRuntime(" not in source, module.__name__
