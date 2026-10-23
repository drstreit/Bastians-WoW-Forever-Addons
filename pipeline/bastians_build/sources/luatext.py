"""Run Lua data text (not a file) in the sandbox of ``luatable`` (ADR 0008).

``luatable.run_file`` wants a path; the parsers of the source readers take the file text so tests
need no files. This is the same run on a string, plus small helpers to read raw Lua tables in a
deterministic order.
"""

from __future__ import annotations

from collections.abc import Iterator
from typing import Any

from lupa import lua51

from . import luatable


def run_text(text: str, name: str, addon_name: str = "Source") -> Any:
    """Run a data file's text with the (ADDON, ns) varargs; returns the sandbox `ns` Lua table."""
    lua = luatable.new_runtime()
    chunk = lua.globals().loadstring(text.lstrip("﻿"), f"@{name}")
    if isinstance(chunk, tuple):
        raise luatable.LuaDataError(f"{name}: {chunk[1]}")
    try:
        chunk(addon_name, lua.globals().ns)
    except lua51.LuaError as exc:
        raise luatable.LuaDataError(f"{name}: {exc}") from exc
    return lua.globals().ns


def sorted_items(table: Any) -> Iterator[tuple[Any, Any]]:
    """(key, value) of a Lua table with integer keys as ``int``, sorted by key."""
    pairs = [
        (int(k) if isinstance(k, float) and k.is_integer() else k, v) for k, v in table.items()
    ]
    yield from sorted(pairs, key=lambda kv: (isinstance(kv[0], str), kv[0]))
