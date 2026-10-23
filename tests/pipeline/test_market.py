"""The Market pack from the AHSync export (data.md "Market pack", B10.2): reader, records, fills,
indexes, the optional pack and the committed golden the Lua tests load."""

import json
from pathlib import Path

import pytest

from bastians_build.__main__ import main
from bastians_build.build import build
from bastians_build.config import MarketConfig, MarketFill, load_config
from bastians_build.market import add_market, place_map, zone_names
from bastians_build.model import World
from bastians_build.pack import pack_table
from bastians_build.sources.ahsync_export import ExportError, read_export, resolve_folder
from bastians_build.sources.fixture import read_fixture

ROOT = Path(__file__).resolve().parents[2]
EXPORT = ROOT / "tests" / "fixtures" / "export-mini"
WORLD = ROOT / "tests" / "fixtures" / "world-mini"
GOLDEN = (
    ROOT / "tests" / "fixtures" / "addons" / "Bastians_Data_Market" / "Generated" / "Market.lua"
)
HINT = (
    "regenerate with: python -m bastians_build data --client forever "
    "--fixture tests/fixtures/world-mini --export tests/fixtures/export-mini "
    "--out tests/fixtures/addons"
)
US, EU_RETAIL = "forever/normal/alliance/us", "retail/normal/neutral/eu"


def test_reader_resolves_latest_checks_sums_and_types_cells():
    export = read_export(EXPORT)
    assert export.folder.name == "20261019T1200Z" and resolve_folder(export.folder) == export.folder
    prices = export.tables["prices_latest"]
    assert len(prices) == 3
    linen = next(r for r in prices if r["item_id"] == 2589 and r["market"] == US)
    assert (linen["median"], linen["sales_per_day"], linen["scan_ts"]) == (38, 21.9, 1760000000)
    saber = next(r for r in prices if r["item_id"] == 1185)
    assert saber["median_7d"] is None  # NULL stays unknown, never 0
    spot = export.tables["farm_spots"][0]
    assert spot["items"] == [[2589, 30], [1931, 1]] and spot["level_min"] == 8
    westfall = export.tables["farm_spots"][2]
    assert westfall["claim_id"] is None
    assert export.tables["signals"][1]["flags"] == ["spot:1"]
    assert [s["name"] for s in export.sources] == ["ahledger", "fixture"]


def test_reader_rejects_bad_exports(tmp_path):
    with pytest.raises(ExportError, match=r"neither manifest\.json nor LATEST"):
        read_export(tmp_path)
    folder = tmp_path / "x"
    folder.mkdir()
    (folder / "manifest.json").write_text('{"schema": "other"}', encoding="utf-8")
    with pytest.raises(ExportError, match="schema is"):
        read_export(folder)
    (folder / "manifest.json").write_text(
        '{"schema": "bastians-export", "schema_version": "2.0", "tables": []}', encoding="utf-8"
    )
    with pytest.raises(ExportError, match=r"not 1\.x"):
        read_export(folder)
    src = EXPORT / "20261019T1200Z"
    manifest = json.loads((src / "manifest.json").read_text(encoding="utf-8"))
    for t in manifest["tables"]:
        (folder / t["file"]).write_bytes((src / t["file"]).read_bytes())
    (folder / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    assert len(read_export(folder).tables["signals"]) == 8
    (folder / "signals.csv").write_text("tampered", encoding="utf-8")
    with pytest.raises(ExportError, match="sha256"):
        read_export(folder)
    manifest["tables"] = [t for t in manifest["tables"] if t["name"] != "claims"]
    (folder / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    with pytest.raises(ExportError, match="'claims' missing"):
        read_export(folder)


def test_records_fills_and_indexes():
    world = World(client="forever")
    config = MarketConfig(
        labels={US: "US beta"},
        fill=[
            MarketFill(to="forever/normal/alliance/eu", source=US, label="US beta"),
            MarketFill(
                to="forever/normal/horde/eu", source="forever/normal/horde/us", label="US beta"
            ),
            MarketFill(to=EU_RETAIL, source=US, label="never"),
        ],
    )
    notes = add_market(world, read_export(EXPORT), config)
    prices = world.records["price"]
    assert prices[f"{US}:2589"]["src"] == "US beta" and prices[f"{US}:2589"]["median"] == 38
    assert prices[f"{EU_RETAIL}:2589"]["src"] == EU_RETAIL  # no label configured: the market id
    # a fill is an alias, no copies (23.10.2026: the first real export had 16,870 prices)
    assert "forever/normal/alliance/eu:2589" not in prices
    assert world.market_aliases["forever/normal/alliance/eu"] == (US, "US beta")
    assert "forever/normal/horde/eu" not in world.market_aliases  # the source has no rows
    assert prices[f"{EU_RETAIL}:2589"]["median"] == 40  # own rows win
    assert notes[:3] == [
        "market forever/normal/alliance/eu: reads the 2 prices of forever/normal/alliance/us "
        "as 'US beta'",
        "market forever/normal/horde/eu: nothing to fill, forever/normal/horde/us has no rows",
        "market retail/normal/neutral/eu has its own rows; "
        "fill from forever/normal/alliance/us not applied",
    ]
    signals = world.records["signal"]
    assert signals[f"{US}:2"]["flags"] == ["spot:1"] and signals[f"{US}:2"]["src"] == "ahsync"
    assert "forever/normal/alliance/eu:2" not in signals
    assert (
        world.records["spot"][3]["strategy"] is None
        and world.records["strategy"][11]["reach"] == 12000
    )
    assert any("sources ahledger, fixture" in n for n in world.notes)
    cfg = load_config().packs["market"]
    table = pack_table(world, cfg)
    assert table["index"]["market.list"][US] == {
        "scanTs": 1760000000,
        "items": 2,
        "label": "US beta",
    }
    assert table["index"]["market.list"]["forever/normal/alliance/eu"] == {
        "scanTs": 1760000000,
        "items": 2,
        "label": "US beta",
        "alias": US,
    }
    assert table["index"]["signal.byMarket"][US] == [f"{US}:{i}" for i in range(1, 8)]
    assert (
        table["index"]["signal.byMarket"]["forever/normal/alliance/eu"]
        == table["index"]["signal.byMarket"][US]
    )
    assert table["index"]["spot.byItem"] == {1185: [2], 1931: [1], 2589: [1, 2], 424242: [3]}
    assert table["index"]["spot.all"] == [1, 2, 3] and table["index"]["strategy.all"] == [
        11,
        12,
        13,
    ]


def test_market_pack_is_optional_and_the_golden_matches(tmp_path):
    config = load_config()
    world = read_fixture(WORLD, "forever")
    result = build(world, config, tmp_path)
    assert all(p.pack.name != "market" for p in result.packs)
    assert result.skipped == ["market", "book"]  # the Strategies book is optional too
    # the client still finds the file its TOC lists: a stub that registers nothing (21.10.2026)
    stub = (tmp_path / "Bastians_Data_Market" / "Generated" / "Market.lua").read_text(
        encoding="utf-8"
    )
    assert (
        stub.startswith("-- GENERATED by bastians_build")
        and "no data in this forever build" in stub
    )
    assert "deferred" not in stub
    add_market(world, read_export(EXPORT), config.market)
    result = build(world, config, tmp_path)
    market = next(p for p in result.packs if p.pack.name == "market")
    # 3 own prices and 8 signals; the EU markets read the US rows through aliases
    assert market.counts == {"price": 3, "signal": 8, "spot": 3, "strategy": 3}
    assert GOLDEN.is_file(), f"{GOLDEN} missing; {HINT}"
    assert market.path.read_text(encoding="utf-8") == GOLDEN.read_text(encoding="utf-8"), HINT


def test_cli_takes_an_export(tmp_path, capsys):
    argv = [
        "data",
        "--client",
        "forever",
        "--fixture",
        str(WORLD),
        "--report-dir",
        str(tmp_path / "report"),  # not the repo's build/ (CLAUDE.md section 7)
        "--export",
        str(EXPORT),
        "--out",
        str(tmp_path),
    ]
    assert main(argv) == 0
    out = capsys.readouterr().out
    assert "Bastians_Data_Market" in out
    assert main([*argv[:-4], "--export", str(tmp_path / "nope"), "--out", str(tmp_path)]) == 2
    assert "neither manifest.json" in capsys.readouterr().err


def test_a_place_text_names_a_zone():
    """Schema 1.2: claims and farm spots carry their place as English text (`where`); AHSync has
    no map ids, the world's zone names give one. A zone wins over a floor of the same name; an
    unknown place stays unknown."""
    world = World(client="forever")
    world.add("zone", 1429, {"name": "Elwynn Forest", "mapType": 3})
    world.add("zone", 1, {"name": "Elwynn Forest", "mapType": 5})
    world.add("zone", 1436, {"name": "Westfall"})
    zones = zone_names(world)
    assert place_map("elwynn forest", zones) == 1429
    assert place_map("Westfall, Defias camps in the south", zones) == 1436
    assert place_map("the deadmines", zones) is None and place_map(None, zones) is None


def test_the_ship_list_keeps_its_markets_and_their_fill_sources():
    """build.toml `[market] ship` (23.10.2026): a build carries the named markets and the markets
    their fills read; the rest of the export stays out (four US markets were 7.5 MB in memory)."""
    world = World(client="forever")
    config = MarketConfig(
        labels={US: "US beta"},
        fill=[MarketFill(to="forever/rp/alliance/eu", source=US, label="US beta")],
        ship=("forever/rp/alliance/eu",),
    )
    assert config.shipped() == {"forever/rp/alliance/eu", US}
    notes = add_market(world, read_export(EXPORT), config)
    markets = {str(k).rpartition(":")[0] for k in world.records["price"]}
    assert markets == {US}  # the retail EU rows are left out
    assert world.market_aliases == {"forever/rp/alliance/eu": (US, "US beta")}
    assert any(n.startswith("market rows left out") for n in notes)
    assert MarketConfig().shipped() is None  # no list: every market
