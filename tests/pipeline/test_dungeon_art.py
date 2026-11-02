"""Hand-drawn dungeon maps (ADR 0048): the shipped file parses, every map it names ships as twelve
BLP tiles in Core, malformed files are rejected, and the floors, pins and door replace the
dungeon's own, with a note for a boss the data lacks or names differently."""

import struct
import sys
from pathlib import Path

import pytest

from bastians_build.config import CONFIG_DIR
from bastians_build.dungeon_art import (
    ART_PREFIX,
    DungeonArtError,
    add_dungeon_art,
    read_dungeon_art,
)
from bastians_build.model import World

ROOT = Path(__file__).resolve().parents[2]
MEDIA = ROOT / "addons" / "Bastians_Core" / "Media" / "Dungeons"
sys.path.insert(0, str(ROOT / "tools"))
import dungeon_art as tool  # noqa: E402


def test_the_shipped_file_names_forevers_own_dungeons_and_their_tiles_ship():
    rows = read_dungeon_art(CONFIG_DIR / "dungeon_art.toml")
    assert [r["id"] for r in rows] == [2959, 2998, 3065, 2999]
    assert all(r["verified"] is False for r in rows)  # not checked in game yet
    keys = [art for r in rows for _, art, _ in r["floors"]]
    assert sorted(keys) == sorted(tool.MAPS)  # the tool makes exactly the maps the file names
    for key in keys:
        for i in range(1, 13):
            data = (MEDIA / f"{key}_{i}.blp").read_bytes()
            magic, _, encoding, _, _, _, w, h = struct.unpack("<4sI4B2I", data[:20])
            assert (magic, encoding, w, h) == (b"BLP2", 2, 256, 256)
    assert sorted(p.name for p in MEDIA.glob("*.blp")) == sorted(
        f"{k}_{i}.blp" for k in keys for i in range(1, 13)
    )
    dalaran = rows[0]
    assert [f[0] for f in dalaran["floors"]] == ["Dalaran Sewers", "City of Dalaran"]
    assert dalaran["door"] == (1, 18.0, 85.0)


def test_malformed_files_are_rejected(tmp_path):
    def write(text: str) -> Path:
        p = tmp_path / "a.toml"
        p.write_text(text, encoding="utf-8")
        return p

    floor = 'floors = [{ name = "A", art = "a", by = "santiago" }]'
    with pytest.raises(DungeonArtError, match="id"):
        read_dungeon_art(write(f"[[dungeon]]\n{floor}\n"))
    with pytest.raises(DungeonArtError, match="duplicate"):
        read_dungeon_art(write(f"[[dungeon]]\nid = 1\n{floor}\n[[dungeon]]\nid = 1\n{floor}\n"))
    with pytest.raises(DungeonArtError, match="by must be"):
        read_dungeon_art(write('[[dungeon]]\nid = 1\nfloors = [{ name = "A", art = "a" }]\n'))
    with pytest.raises(DungeonArtError, match=r"floor must be 1..1"):
        read_dungeon_art(
            write(f"[[dungeon]]\nid = 1\n{floor}\ndoor = {{ floor = 2, x = 1, y = 1 }}\n")
        )
    with pytest.raises(DungeonArtError, match=r"0..100"):
        read_dungeon_art(
            write(
                f"[[dungeon]]\nid = 1\n{floor}\n"
                'bosses = [{ order = 1, name = "B", floor = 1, x = 120, y = 1 }]\n'
            )
        )


def test_the_floors_pins_and_door_replace_the_dungeons_own(tmp_path):
    world = World(client="forever")
    world.add(
        "dungeon",
        2999,
        {
            "name": "Ruins of Lordaeron",
            "bosses": [[1, 3353, "Witherfang"], [4, 3354, "Rath'mael"], [7, 3412, "Bjork"]],
            "floors": [{"n": "Part 1", "w": 2048, "h": 2048}],
            "bossSpots": [[1, 1, 10.0, 10.0]],
            "door": None,
        },
    )
    path = tmp_path / "art.toml"
    path.write_text(
        """
[[dungeon]]
id = 2999
floors = [{ name = "Ruins of Lordaeron", art = "lordaeron", by = "santiago" }]
door = { floor = 1, x = 61.0, y = 21.5 }
bosses = [
  { order = 7, name = "Bjork", floor = 1, x = 37.0, y = 24.0 },
  { order = 4, name = "Rathmael", floor = 1, x = 38.0, y = 67.0 },
  { order = 9, name = "Nobody", floor = 1, x = 1.0, y = 1.0 },
]

[[dungeon]]
id = 1
floors = [{ name = "A", art = "a", by = "santiago" }]
""",
        encoding="utf-8",
    )
    notes = add_dungeon_art(world, path)
    rec = world.get("dungeon", 2999)
    assert rec["floors"] == [
        {
            "n": "Ruins of Lordaeron",
            "a": ART_PREFIX + "lordaeron_",
            "g": [4, 3],
            "w": 1024,
            "h": 682,
            "by": "santiago",
        }
    ]
    # in the order of the bosses; Witherfang has no pin now (no room named), unknown stays unknown
    assert rec["bossSpots"] == [[4, 1, 38.0, 67.0], [7, 1, 37.0, 24.0]]
    assert rec["door"] == [1, 61.0, 21.5]
    assert notes == [
        "dungeon art 2999: boss 4 is named \"Rath'mael\" in the data, the map says 'Rathmael'",
        "dungeon art 2999: boss 9 (Nobody) is not in the data",
        "dungeon art 1 None: no dungeon record, left out",
    ]
    assert world.notes == notes
