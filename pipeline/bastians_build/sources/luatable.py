"""Load Lua data files of other addons into Python (ADR 0008).

Source addons ship their data as Lua files that begin with ``local _, ns = ...`` and fill ``ns``
with tables (sometimes as long strings holding ``return { ... }``). Running them on a sandboxed
Lua 5.1 (lupa) with the game globals stubbed is the exact parser: what the client sees, we see.
Conversion rules: a table with keys 1..n in order becomes a list, any other table a dict; integral
numbers become ``int``; no functions or userdata survive.
"""

from __future__ import annotations

from pathlib import Path

from lupa import lua51

SANDBOX = """
local ns = {}
_G.ns = ns
-- the few globals source data files touch; anything else raises so a new need is noticed
LibStub = setmetatable({}, {
  __call = function()
    return setmetatable({}, { __index = function() return function() end end })
  end,
})
QuestieLoader = {
  ImportModule = function(_, name)
    _G[name] = _G[name] or { private = {} }
    return _G[name]
  end,
}
GetLocale = function() return "enUS" end
"""


class LuaDataError(ValueError):
    pass


def new_runtime() -> lua51.LuaRuntime:
    lua = lua51.LuaRuntime(
        unpack_returned_tuples=True, register_eval=False, register_builtins=False
    )
    lua.execute(SANDBOX)
    return lua


def run_file(lua: lua51.LuaRuntime, path: Path, addon_name: str = "Source"):
    """Run a data file with the (ADDON, ns) varargs the client passes; returns the sandbox `ns`."""
    chunk = lua.globals().loadstring(path.read_text(encoding="utf-8-sig"), f"@{path.name}")
    if isinstance(chunk, tuple):
        raise LuaDataError(f"{path.name}: {chunk[1]}")
    try:
        chunk(addon_name, lua.globals().ns)
    except lua51.LuaError as exc:
        raise LuaDataError(f"{path.name}: {exc}") from exc
    return lua.globals().ns


def eval_long_string(lua: lua51.LuaRuntime, text: str):
    """Evaluate a ``return { ... }`` chunk shipped as a long string."""
    chunk = lua.globals().loadstring(text, "@longstring")
    if isinstance(chunk, tuple):
        raise LuaDataError(f"long string: {chunk[1]}")
    return chunk()


def to_python(value):
    """Lua value -> Python: lists for 1..n arrays, dicts otherwise, ints for integral numbers."""
    if isinstance(value, float):
        return int(value) if value.is_integer() and abs(value) < 2**53 else value
    if not hasattr(value, "keys"):
        return value
    keys = list(value.keys())
    n = len(keys)
    if n and all(isinstance(k, int | float) for k in keys):
        ints = sorted(int(k) for k in keys)
        if ints == list(range(1, n + 1)):
            return [to_python(value[i]) for i in range(1, n + 1)]
    out = {}
    for k in keys:
        key = int(k) if isinstance(k, float) and k.is_integer() else k
        out[key] = to_python(value[k])
    return out


def load_ns(path: Path, addon_name: str = "Source") -> dict:
    """Run one file and return its `ns` as Python."""
    lua = new_runtime()
    return to_python(run_file(lua, path, addon_name))
