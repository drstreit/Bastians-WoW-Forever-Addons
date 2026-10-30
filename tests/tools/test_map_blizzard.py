"""tools/mapstyle/blizzard.py (ADR 0036): Blizzard's line breaks come back from the read boxes, the
names land in world yards and find their AreaTable ids (a shortened one too), neighbours are left
out; the quilt fills a gap only from the painted land; the emitted table carries the names."""

import gzip
import json
import struct
from pathlib import Path

import pytest

np = pytest.importorskip("numpy")
pytest.importorskip("PIL")

from mapstyle.blizzard import Atlas, labels, lines_of, quilt  # noqa: E402
from mapstyle.emit import style_lua  # noqa: E402
from mapstyle.scene import ORIGIN, TILE_YARDS  # noqa: E402

N = 32
X, Y = 31, 48
ELWYNN, GOLDSHIRE, NORTHSHIRE = 12, 87, 9


def tile_bytes(area: int) -> bytes:
    """A flat dry tile whose 16 x 16 chunks all belong to `area` (clientdump's mapdata v3)."""
    ground = np.zeros((N, N), "f4")
    nan = np.full((N, N), np.nan, "f4")
    out = b"BMDT" + struct.pack("<Iiii", 3, X, Y, N)
    for arr in (ground, np.zeros((N, N), "u2"), nan, nan, np.zeros((N, N), "u1"), nan, nan, nan):
        out += arr.tobytes()
    out += np.full(256, area, "<u4").tobytes()
    out += struct.pack("<i", 0) + struct.pack("<i", 0) + struct.pack("<i", 0)
    return gzip.compress(out, mtime=0)


def atlas() -> Atlas:
    """Elwynn's painting framing exactly tile (31, 48)."""
    maxx, maxy = ORIGIN - Y * TILE_YARDS, ORIGIN - X * TILE_YARDS
    frame = (maxx - TILE_YARDS, maxy - TILE_YARDS, maxx, maxy, 0.0, 0.0, 1.0, 1.0)
    return Atlas(
        uimaps={1429: {"ID": 1429, "Type": 3}},
        art_of={1429: 1},
        layer_of={1: {"LayerWidth": 1002, "LayerHeight": 668, "TileWidth": 256, "TileHeight": 256}},
        art_tiles={},
        overlays={},
        overlay_tiles={},
        frames={1429: frame},
        map_of={1429: 0},
        zone_of_area={ELWYNN: 1429, GOLDSHIRE: 1429, NORTHSHIRE: 1429},
        areas={
            ELWYNN: ("Elwynn Forest", 0, 0),
            GOLDSHIRE: ("Goldshire", ELWYNN, 0),
            NORTHSHIRE: ("Northshire Valley", ELWYNN, 0),
        },
    )


def test_blizzards_line_breaks_come_back_from_the_boxes():
    # two rows of boxes: the words split to match the rows' widths
    assert lines_of("Eastvale Logging Camp", [[790, 402, 850, 415], [773, 413, 868, 428]]) == [
        "Eastvale",
        "Logging Camp",
    ]
    # three rows, one word each (The / Great / Sea)
    assert lines_of(
        "The Great Sea", [[90, 250, 160, 275], [70, 275, 190, 300], [90, 300, 160, 325]]
    )
    assert (
        len(
            lines_of(
                "The Great Sea", [[90, 250, 160, 275], [70, 275, 190, 300], [90, 300, 160, 325]]
            )
        )
        == 3
    )
    # one tall box holding two lines (Sentinel Hill)
    assert lines_of("Sentinel Hill", [[500, 318, 585, 352]]) == ["Sentinel", "Hill"]
    assert lines_of("Goldshire", [[384, 445, 469, 461]]) == ["Goldshire"]


def test_the_names_land_in_world_yards_with_their_area_ids(tmp_path: Path):
    data = tmp_path / "Azeroth"
    data.mkdir()
    (data / f"{X}_{Y}.bmd.gz").write_bytes(tile_bytes(GOLDSHIRE))
    readings = tmp_path / "readings"
    readings.mkdir()
    (readings / "1429.json").write_text(
        json.dumps(
            {
                "ui": 1429,
                "name": "Elwynn Forest",
                "labels": [
                    {"text": "Goldshire", "kind": "place", "boxes": [[461, 326, 541, 342]]},
                    {"text": "Northshire", "kind": "place", "boxes": [[448, 284, 525, 299]]},
                    {
                        "text": "Burning Steppes",
                        "kind": "neighbour",
                        "boxes": [[666, 79, 940, 111]],
                    },
                    {"text": "The Great Sea", "kind": "sea", "boxes": [[20, 20, 160, 38]]},
                ],
            }
        ),
        encoding="utf-8",
    )
    found = {e["text"]: e for e in labels(atlas(), readings, data, 0)}
    assert set(found) == {"Goldshire", "Northshire", "The Great Sea"}  # the neighbour is left out
    gold = found["Goldshire"]
    # the box's centre is the painting's centre: the tile's centre in world yards
    assert gold["wx"] == pytest.approx(ORIGIN - (Y + 0.5) * TILE_YARDS, abs=1)
    assert gold["wy"] == pytest.approx(ORIGIN - (X + 0.5) * TILE_YARDS, abs=1)
    assert gold["area"] == GOLDSHIRE and gold["inside"] and gold["level"] == 2
    assert gold["height"] == pytest.approx(16 / 668 * TILE_YARDS, abs=0.1)
    assert found["Northshire"]["area"] == NORTHSHIRE  # Blizzard shortened Northshire Valley
    sea = found["The Great Sea"]
    assert sea["area"] is None and sea["level"] == 0


def test_the_quilt_fills_a_gap_only_from_the_painted_land():
    rng = np.random.default_rng(1)
    img = np.zeros((96, 96, 3), "f4")
    img[:, :48] = rng.choice([0.2, 0.8], size=(96, 48, 1))  # the painted land: two tones
    img[:, 48:] = 0.5  # the gap, holding the surroundings' diffused colour
    gap = np.zeros((96, 96), bool)
    gap[:, 48:] = True
    out = quilt(img, gap, ~gap)
    assert np.array_equal(out[:, :48], img[:, :48])  # the painting is never touched
    # every filled pixel comes from the land's tones (feathered seams may mix the two)
    filled = out[:, 48:, 0]
    assert ((filled >= 0.2 - 1e-6) & (filled <= 0.8 + 1e-6)).all()
    assert (np.abs(filled - 0.5) > 0.05).mean() > 0.5  # no longer the flat placeholder
    assert np.array_equal(quilt(img, gap, ~gap), out)  # deterministic


def test_the_emitted_table_carries_the_names():
    names = {
        0: [
            {
                "text": "The Great\nSea",
                "kind": "sea",
                "wx": -10000.0,
                "wy": 3000.0,
                "height": 120.0,
                "area": None,
                "level": 0,
            },
            {
                "text": "Goldshire",
                "kind": "place",
                "wx": -9460.0,
                "wy": 60.0,
                "height": 40.0,
                "area": GOLDSHIRE,
                "level": 2,
            },
        ]
    }
    lua = style_lua("blizzard", "forever", "test", {0: [(7, 11)]}, {0: [(3, 5)]}, names)
    assert 'key = "blizzard"' in lua and "Bastians_Map_Blizzard" in lua
    assert '{ "The Great\\nSea", -10000.0, 3000.0, 120.0, "sea", false, 0 },' in lua
    assert '{ "Goldshire", -9460.0, 60.0, 40.0, "place", 87, 2 },' in lua


def test_a_sea_drawing_brings_its_ink_and_nothing_else():
    """Blizzard's drawings in the sea come along; only the strokes darken our
    sea, in brown ink, fading in at the box's edges; the parchment's own tints stay out."""
    from mapstyle.blizzard import ink

    crop = np.full((60, 60, 3), 0.6, "f4")
    crop[30, 10:50] = 0.2  # a stroke
    crop[10:20, 10:20, 0] = 0.9  # a warm tint at a torn edge: lighter in red, not darker
    f = ink(crop)
    assert (f <= 1 + 1e-6).all()  # never lighter than our sea
    assert f[30, 30].max() < 0.7  # the stroke
    assert f[30, 30, 2] < f[30, 30, 0]  # brown: the blue darkened most
    assert np.allclose(f[15, 15], 1, atol=0.02)  # the tint is gone
    assert np.allclose(f[30, 0], 1)  # the box's edge: nothing
