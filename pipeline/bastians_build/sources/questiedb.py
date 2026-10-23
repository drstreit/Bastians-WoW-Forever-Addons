"""QuestieDB Forever build (GPL-3.0): the AreaTable id <-> uiMapID zone tables (ADR 0008).

``<AddOns>/QuestieDB/support/Forever/Zones/areaIdToUiMapId.lua`` and ``uiMapIdToAreaId.lua`` fill
``ZoneDB.private.<name>`` with ``[[return { ... }]]`` long strings: a main table and an
``...Override`` table (Questie aliases and display policy). The file calls
``QuestieLoader:ImportModule("ZoneDB")``, which the sandbox of ``luatable`` stubs.
Checked 19.10.2026 (area file reviewed through Forever DBC build 1.60.1.70291).

The override wins over the main table. A value of ``0`` means "no map" (Deeprun Tram, Hall of
Legends: display suppression); it is kept as ``0`` here so the caller decides to drop it.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from . import luatable

_BUILD = re.compile(r"^--.*\bbuild\s+(\d+(?:\.\d+)+)", re.M)
_REVIEWED = re.compile(
    r"^--\s*Reviewed Forever DBC relationships through build\s+(\d+(?:\.\d+)+)", re.M
)


@dataclass(frozen=True)
class ZoneTable:
    mapping: dict[int, int]  # main table with the override applied on top
    source_build: str | None  # Forever DBC build the file says it was reviewed/completed for


def _source_build(text: str) -> str | None:
    m = _REVIEWED.search(text) or _BUILD.search(text)
    return m.group(1) if m else None


def _tables(text: str, main: str, name: str) -> tuple[dict[int, int], dict[int, int]]:
    lua = luatable.new_runtime()
    chunk = lua.globals().loadstring(text.lstrip("\ufeff"), f"@{name}")
    if isinstance(chunk, tuple):
        raise luatable.LuaDataError(f"{name}: {chunk[1]}")
    chunk(name, lua.globals().ns)
    private: Any = lua.globals().ZoneDB.private

    def load(key: str) -> dict[int, int]:
        long_string = private[key]
        if long_string is None:
            return {}
        table = luatable.to_python(luatable.eval_long_string(lua, long_string))
        if isinstance(table, list):  # keys 1..n would come back as a list
            table = {i + 1: v for i, v in enumerate(table)}
        return {int(k): int(v) for k, v in table.items()}

    return load(main), load(main + "Override")


def _parse(text: str, main: str, name: str) -> ZoneTable:
    base, override = _tables(text, main, name)
    return ZoneTable({**base, **override}, _source_build(text))


def parse_area_to_ui_map(text: str) -> ZoneTable:
    """``areaIdToUiMapId.lua``: AreaTable id -> uiMapID."""
    return _parse(text, "areaIdToUiMapId", "areaIdToUiMapId.lua")


def parse_ui_map_to_area(text: str) -> ZoneTable:
    """``uiMapIdToAreaId.lua``: uiMapID -> AreaTable id."""
    return _parse(text, "uiMapIdToAreaId", "uiMapIdToAreaId.lua")


def read_zone_table(text: str) -> dict[int, int]:
    """AreaTable id -> uiMapID, override applied; ``0`` values kept."""
    return parse_area_to_ui_map(text).mapping


def read_ui_map_to_area(text: str) -> dict[int, int]:
    """uiMapID -> AreaTable id, override applied."""
    return parse_ui_map_to_area(text).mapping


def read_area_to_ui_map_file(path: Path) -> ZoneTable:
    return parse_area_to_ui_map(path.read_text(encoding="utf-8-sig"))


def read_ui_map_to_area_file(path: Path) -> ZoneTable:
    return parse_ui_map_to_area(path.read_text(encoding="utf-8-sig"))
