"""The quality ledger (plan-data-quality.md L1): per kind, the records, the known ones and their
sources, and what the probe saw in play, from a world built on the mini fixture."""

import json
from pathlib import Path

from bastians_build import quality
from bastians_build.build import build
from bastians_build.config import load_config
from bastians_build.probetruth import MerchantCheck, ProbeTruth, TargetCheck
from bastians_build.sources.fixture import read_fixture

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "tests" / "fixtures" / "world-mini"


def by_kind(rows):
    return {r["kind"]: r for r in rows}


def test_every_kind_counts_its_known_records_and_their_sources():
    world = read_fixture(WORLD, "forever")
    rows = by_kind(quality.ledger(world))
    npc = rows["npc places"]
    assert (
        npc["count"] == len(world.records["npc"]) and npc["known"] + npc["unknown"] == npc["count"]
    )
    assert sum(npc["sources"].values()) == npc["known"]
    vendor = rows["vendor prices"]
    assert (vendor["count"], vendor["known"], vendor["sources"]) == (2, 2, {"classic": 2})
    assert rows["dungeon bosses"]["known"] == 1
    assert set(rows) >= {"item prices", "drop chances", "quest givers and enders", "trainer costs"}


def test_a_vendor_rows_price_counts_by_its_own_source():
    """A CMaNGOS row that takes the engine's price names it in its sixth field (canon
    `engine_offer`): the ledger counts the price's source, not the row's."""
    from bastians_build.model import World

    world = World(client="forever")
    world.add(
        "npc",
        1,
        {
            "vendor": [
                [159, 25, 5, False, "classic", "client"],
                [18, 40, None, False, "classic"],
                [7, None, None, None, "questie"],
            ]
        },
    )
    vendor = by_kind(quality.ledger(world))["vendor prices"]
    assert (vendor["known"], vendor["unknown"]) == (2, 1)
    assert vendor["sources"] == {"classic": 1, "client": 1}


def test_test_items_are_counted_and_play_fills_its_columns():
    world = read_fixture(WORLD, "forever")
    world.records["item"][240993] = {"name": "Tim's Test Ranged Weapon", "sell": 1, "src": "client"}
    world.records["item"][88] = {"name": "Deprecated Old Pants", "src": "client"}
    world.records["item"][1] = {"name": "Contest Winner's Tabard", "src": "client"}  # no junk
    truth = ProbeTruth(
        talks=[
            TargetCheck("talked to (gossip)", "npc", 54, "Corina Steele", 1429, "ok", 0.1),
            TargetCheck("talked to (quest)", "npc", 9, "Nobody", 1429, "missing record"),
        ],
        merchants=[MerchantCheck(54, "Corina Steele", 2, 1, [], [4540], 0, [1185], "differs")],
    )
    rows = by_kind(quality.ledger(world, truth))
    assert rows["item prices"]["junk"] == 2
    assert (rows["npc places"]["seen_ok"], rows["npc places"]["seen_not_ok"]) == (1, 1)
    assert (rows["vendor prices"]["seen_ok"], rows["vendor prices"]["seen_not_ok"]) == (1, 1)
    text = "\n".join(quality.render(list(rows.values())))
    assert "## Quality ledger" in text and "| npc places |" in text and "1 ok, 1 not" in text
    assert "item prices (2 test or deprecated)" in text


def test_the_build_writes_the_ledger_beside_the_report(tmp_path):
    world = read_fixture(WORLD, "forever")
    result = build(world, load_config(), tmp_path / "out", report_dir=tmp_path)
    assert result.quality_path == tmp_path / "quality-forever.json"
    rows = json.loads(result.quality_path.read_text(encoding="utf-8"))
    assert rows[0]["kind"] == "npc places" and "## Quality ledger" in result.report
