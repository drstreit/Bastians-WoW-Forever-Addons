"""The overview textures of Bastians_Map_Art (B8.5): clientdump overview output -> Generated/Tiles
and Generated/Overview.lua, checked against the per-client config and the budget."""

import json
import struct
from pathlib import Path

import pytest

from bastians_build.__main__ import main
from bastians_build.config import ConfigError, MapArtConfig, load_config
from bastians_build.mapart import MapArtError, directories_from_maps
from bastians_build.overview import (
    cell_key,
    emit_overview,
    find_overview_indexes,
    install_overview,
    overview_tables,
    read_overview_index,
    texture_size,
)

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests" / "fixtures" / "mapart"
OVERVIEW = FIXTURE / "overview"
GOLDEN = OVERVIEW / "Overview.lua"
MAPS_JSON = ROOT / "tests" / "fixtures" / "sources" / "clientdump" / "Map.json"
CONFIG = MapArtConfig(span=8, pixels=4, budget_kb=64)  # the fixture cells are 32 px
HINT = (
    'regenerate with: python -c "from bastians_build.overview import *; from pathlib import Path; '
    "from bastians_build.config import MapArtConfig; "
    "print(emit_overview('forever', MapArtConfig(span=8, pixels=4, budget_kb=64), "
    "overview_tables(find_overview_indexes(Path('tests/fixtures/mapart/overview')), "
    "MapArtConfig(span=8, pixels=4, budget_kb=64), 'forever')), end='')\" "
    "> tests/fixtures/mapart/overview/Overview.lua"
)


def test_config_carries_the_mapart_section():
    cfg = load_config().mapart
    assert cfg.addon == "Bastians_Map_Art" and cfg.span == 8
    # full resolution on both clients, 80 MB budget (retail: 75 MB)
    assert cfg.pixels_for("forever") == 64 and cfg.pixels_for("retail") == 64
    assert cfg.budget_kb == 81920


def test_bad_mapart_config_is_rejected(tmp_path):
    base = (ROOT / "pipeline" / "config" / "build.toml").read_text(encoding="utf-8")
    bad = tmp_path / "build.toml"
    bad.write_text(base.replace("pixels = 64", "pixels = 48"), encoding="utf-8")
    with pytest.raises(ConfigError, match="power of two"):
        load_config(bad)
    bad.write_text(base.replace("span = 8", "span = 7"), encoding="utf-8")
    with pytest.raises(ConfigError, match="divide 64"):
        load_config(bad)
    bad.write_text(base.replace('alpha = "dxt1"', 'alpha = "png"'), encoding="utf-8")
    with pytest.raises(ConfigError, match="dxt1 or dxt5"):
        load_config(bad)
    bad.write_text(base.replace('sea = "b8a380"', 'sea = "blue"'), encoding="utf-8")
    with pytest.raises(ConfigError, match="six hex digits"):
        load_config(bad)
    assert load_config().mapart.sea == "b8a380"  # the painted sea
    bad.write_text(base.replace('sea = "b8a380"', 'sea = "#B8A380"'), encoding="utf-8")
    assert load_config(bad).mapart.sea == "b8a380"


def test_texture_headers_are_read_without_decoding(tmp_path):
    assert texture_size(OVERVIEW / "Azeroth_3_6.blp") == (32, 32)
    tga = tmp_path / "x.tga"
    header = bytearray(18)
    header[2] = 2
    header[16] = 32
    struct.pack_into("<HH", header, 12, 64, 64)
    tga.write_bytes(bytes(header) + bytes(64 * 64 * 4))
    assert texture_size(tga) == (64, 64)
    (tmp_path / "bad.blp").write_bytes(b"BLP1" + bytes(2000))
    with pytest.raises(MapArtError, match="not a BLP2"):
        texture_size(tmp_path / "bad.blp")
    short = (OVERVIEW / "Azeroth_3_6.blp").read_bytes()[:1300]
    (tmp_path / "short.blp").write_bytes(short)
    with pytest.raises(MapArtError, match="truncated"):
        texture_size(tmp_path / "short.blp")
    (tmp_path / "x.png").write_bytes(bytes(2000))
    with pytest.raises(MapArtError, match="unknown texture format"):
        texture_size(tmp_path / "x.png")


def test_index_is_parsed_and_checked():
    index = read_overview_index(OVERVIEW / "Azeroth_overview.json")
    assert (index.directory, index.map_id, index.span, index.pixels) == ("Azeroth", 0, 8, 4)
    assert [(c.x, c.y, c.adts) for c in index.cells] == [(3, 5, 64), (3, 6, 10), (4, 6, 3)]
    assert index.cells[0].ext == "blp" and index.size == 3 * 1868
    assert cell_key(3, 6, 8) == 3 * 8 + 6


@pytest.mark.parametrize(
    ("patch", "message"),
    [
        (lambda d: d.pop("span"), "missing `span`"),
        (lambda d: d.update(span=7), "does not divide"),
        (lambda d: d.update(format="png"), "not one of"),
        (lambda d: d["cells"][0].update(x=9), "outside"),
        (lambda d: d["cells"].append(dict(d["cells"][0])), "listed twice"),
        (lambda d: d["cells"][0].update(file="nope.blp"), "is missing"),
        (lambda d: d["cells"][0].update(adts=0), "has 0 ADT"),
        (lambda d: d.update(pixels=8), "expected 64"),
        (lambda d: d.update(cells=[]), "no cells"),
    ],
)
def test_bad_indexes_are_rejected(tmp_path, patch, message):
    data = json.loads((OVERVIEW / "Azeroth_overview.json").read_text(encoding="utf-8"))
    for cell in data["cells"]:
        (tmp_path / cell["file"]).write_bytes((OVERVIEW / cell["file"]).read_bytes())
    patch(data)
    path = tmp_path / "Azeroth_overview.json"
    path.write_text(json.dumps(data), encoding="utf-8")
    with pytest.raises(MapArtError, match=message):
        read_overview_index(path)


def test_tables_check_the_client_config_and_the_continent(tmp_path):
    indexes = find_overview_indexes(OVERVIEW)
    assert sorted(indexes) == ["Azeroth", "Kalimdor"]
    tables = overview_tables(indexes, CONFIG, "forever")
    assert sorted(tables) == [0, 1] and len(tables[0].cells) == 3
    with pytest.raises(MapArtError, match="rerun clientdump overview --span 8 --pixels 64"):
        overview_tables(indexes, MapArtConfig(span=8, pixels=64), "forever")
    with pytest.raises(MapArtError, match=r"alpha dxt1 and sea transparent; .* wants .* dxt5"):
        overview_tables(indexes, MapArtConfig(span=8, pixels=4, alpha="dxt5"), "forever")
    # the fixture cells were stitched without a sea; a config with one rejects them and names it
    with pytest.raises(MapArtError, match=r"sea transparent; .* sea b8a380 .*--sea b8a380"):
        overview_tables(indexes, MapArtConfig(span=8, pixels=4, sea="b8a380"), "forever")
    assert load_config().mapart.alpha == "dxt1"
    # a map directory the Map table does not know, and a mapId that disagrees with it
    data = json.loads((OVERVIEW / "Kalimdor_overview.json").read_text(encoding="utf-8"))
    (tmp_path / "Kalimdor_3_3.blp").write_bytes((OVERVIEW / "Kalimdor_3_3.blp").read_bytes())
    data["map"] = "Expansion01"
    (tmp_path / "Kalimdor_3_3.blp").rename(tmp_path / "Expansion01_3_3.blp")
    data["cells"][0]["file"] = "Expansion01_3_3.blp"
    (tmp_path / "Expansion01_overview.json").write_text(json.dumps(data), encoding="utf-8")
    with pytest.raises(MapArtError, match="no continent"):
        overview_tables(find_overview_indexes(tmp_path), CONFIG, "forever")
    with pytest.raises(MapArtError, match="mapId 1 but the Map table says 530"):
        overview_tables(
            find_overview_indexes(tmp_path), CONFIG, "forever", directories_from_maps(MAPS_JSON)
        )
    (tmp_path / "empty").mkdir()
    with pytest.raises(MapArtError, match=r"no \*_overview.json"):
        find_overview_indexes(tmp_path / "empty")


def test_committed_golden_matches_a_fresh_emit():
    """The Lua tests register exactly what the generator produces."""
    text = emit_overview(
        "forever", CONFIG, overview_tables(find_overview_indexes(OVERVIEW), CONFIG, "forever")
    )
    assert GOLDEN.is_file(), f"{GOLDEN} missing; {HINT}"
    assert text == GOLDEN.read_text(encoding="utf-8"), HINT
    assert text.startswith("-- GENERATED by bastians_build")
    assert '"Map.RegisterOverview",' in text
    assert 'path = "Interface\\\\AddOns\\\\Bastians_Map_Art\\\\Generated\\\\Tiles\\\\"' in text
    assert "[0] = { 29, 30, 38 }" in text  # 3*8+5, 3*8+6, 4*8+6


def test_install_copies_cells_removes_stale_ones_and_is_idempotent(tmp_path):
    result = install_overview("forever", OVERVIEW, tmp_path, CONFIG)
    tiles = tmp_path / "Bastians_Map_Art" / "Generated" / "Tiles"
    assert sorted(p.name for p in tiles.iterdir()) == [
        "0_3_5.blp",
        "0_3_6.blp",
        "0_4_6.blp",
        "1_3_3.blp",
    ]
    assert (tiles / "0_3_6.blp").read_bytes() == (OVERVIEW / "Azeroth_3_6.blp").read_bytes()
    assert result.changed and result.copied == 4 and result.removed == 0
    assert result.counts == {0: 3, 1: 1} and result.size == 4 * 1868
    assert result.budget_kb == 64 and not result.over_budget
    assert result.path.read_text(encoding="utf-8") == GOLDEN.read_text(encoding="utf-8")
    # a second run changes nothing; a stale cell of ours goes, a foreign file stays
    (tiles / "0_7_7.blp").write_bytes(b"old")
    (tiles / "readme.txt").write_text("keep", encoding="utf-8")
    again = install_overview("forever", OVERVIEW, tmp_path, CONFIG)
    assert again.copied == 0 and again.removed == 1 and again.changed
    assert not (tiles / "0_7_7.blp").exists() and (tiles / "readme.txt").exists()
    third = install_overview("forever", OVERVIEW, tmp_path, CONFIG)
    assert not third.changed and not list(tiles.glob("*.tmp"))
    # the budget flag and the build string
    tight = install_overview(
        "forever",
        OVERVIEW,
        tmp_path,
        MapArtConfig(span=8, pixels=4, budget_kb=1),
        build="1.60.1.70450",
    )
    assert tight.over_budget and 'build = "1.60.1.70450"' in tight.path.read_text(encoding="utf-8")
    # a dry run writes nothing
    dry = install_overview(
        "retail", OVERVIEW, tmp_path / "dry", MapArtConfig(span=8, pixels=4), write=False
    )
    assert dry.counts == {0: 3, 1: 1} and not (tmp_path / "dry").exists()


def test_cli_installs_the_overview_with_the_tiles(tmp_path, capsys, monkeypatch):
    import bastians_build.__main__ as cli

    monkeypatch.setattr(cli, "load_config", lambda: type("C", (), {"mapart": CONFIG})())
    argv = [
        "mapart",
        "--client",
        "forever",
        "--tiles",
        str(FIXTURE),
        "--overview",
        str(OVERVIEW),
        "--out",
        str(tmp_path),
    ]
    assert main(argv) == 0
    out = capsys.readouterr().out
    assert "continent 0: 3 overview cells" in out and "4 copied" in out and "of 0 MB budget" in out
    assert (tmp_path / "Bastians_Map_Art" / "Generated" / "Overview.lua").is_file()
    assert (tmp_path / "Bastians_Map" / "Generated" / "MinimapTiles.lua").is_file()
    monkeypatch.setattr(
        cli,
        "load_config",
        lambda: type("C", (), {"mapart": MapArtConfig(span=8, pixels=4, budget_kb=1)})(),
    )
    assert main(argv) == 1
    assert "OVER BUDGET" in capsys.readouterr().out
    assert (
        main(
            [
                "mapart",
                "--client",
                "forever",
                "--tiles",
                str(FIXTURE),
                "--overview",
                str(tmp_path / "nope"),
            ]
        )
        == 2
    )
    assert "error:" in capsys.readouterr().err


def test_coast_masks_are_installed_for_the_tiles_that_stay_in_the_table(tmp_path):
    """the stitcher writes a sea mask per coast tile (masks/); the
    install copies those whose tile stays in the native table (sea share below skip_sea) into
    Generated/Masks and registers them; masks of left-out tiles and stale files go."""
    import shutil

    src = tmp_path / "ov"
    shutil.copytree(OVERVIEW, src)
    (src / "masks").mkdir()
    for name in ("Azeroth_31_31.blp", "Azeroth_32_31.blp"):
        shutil.copy(OVERVIEW / "Azeroth_3_5.blp", src / "masks" / name)
    index_path = src / "Azeroth_overview.json"
    index = json.loads(index_path.read_text(encoding="utf-8"))
    index["tiles"] = [[31, 31, 0.4], [32, 31, 0.99]]
    index["masks"] = [[31, 31], [32, 31]]
    index_path.write_text(json.dumps(index), encoding="utf-8")
    out = tmp_path / "out"
    (out / "Bastians_Map_Art" / "Generated" / "Masks").mkdir(parents=True)
    stale = out / "Bastians_Map_Art" / "Generated" / "Masks" / "0_1_1.blp"
    stale.write_bytes(b"old")
    result = install_overview("forever", src, out, CONFIG)
    masks = sorted(p.name for p in (out / "Bastians_Map_Art" / "Generated" / "Masks").iterdir())
    assert masks == ["0_31_31.blp"] and result.masks == 1  # 32/31 is all sea: out of the table
    assert not stale.exists()
    lua = result.path.read_text(encoding="utf-8")
    assert "masks = {" in lua and f"[0] = {{ {31 * 64 + 31} }}" in lua
    assert 'maskPath = "Interface\\\\AddOns\\\\Bastians_Map_Art\\\\Generated\\\\Masks\\\\"' in lua
    # a mask listed in the index but missing on disk is an error
    (src / "masks" / "Azeroth_31_31.blp").unlink()
    with pytest.raises(MapArtError, match=r"mask file masks/Azeroth_31_31\.blp is missing"):
        install_overview("forever", src, out, CONFIG)
    # the fixture without masks emits no mask table (the golden stays as it is)
    plain = install_overview("forever", OVERVIEW, tmp_path / "plain", CONFIG)
    assert "masks" not in plain.path.read_text(encoding="utf-8") and plain.masks == 0
