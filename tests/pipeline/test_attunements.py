"""Attunement lists (B5.6): the config files parse, steps are validated, labels are checked against
the quest names of the world, and the records land in the quests pack with a faction index."""

from pathlib import Path

import pytest

from bastians_build.attunements import AttunementError, add_attunements, read_attunements
from bastians_build.build import build
from bastians_build.config import CONFIG_DIR, load_config
from bastians_build.derive import build_index
from bastians_build.sources.fixture import read_fixture

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests" / "fixtures" / "world-mini"


def test_shipped_files_parse_for_both_clients():
    forever = read_attunements(CONFIG_DIR / "attunements_forever.toml")
    ids = [a["id"] for a in forever]
    assert ids == [
        "onyxia-alliance",
        "onyxia-horde",
        "molten-core",
        "blackwing-lair",
        "ubrs-key",
        "scholomance-key",
        "naxxramas",
    ]
    assert all(a["verified"] is False for a in forever)  # nothing checked on Forever yet
    assert forever[-1]["steps"] == [["rep", 529, "Argent Dawn", 6]]
    assert read_attunements(CONFIG_DIR / "attunements_retail.toml") == []


def test_malformed_files_are_rejected(tmp_path):
    def write(text: str) -> Path:
        p = tmp_path / "a.toml"
        p.write_text(text, encoding="utf-8")
        return p

    with pytest.raises(AttunementError, match="missing steps"):
        read_attunements(write('[[attunement]]\nid = "x"\nname = "X"\nfaction = "both"\n'))
    with pytest.raises(AttunementError, match="faction"):
        read_attunements(
            write('[[attunement]]\nid = "x"\nname = "X"\nfaction = "Elves"\nsteps = []\n')
        )
    with pytest.raises(AttunementError, match="step 1"):
        read_attunements(
            write(
                '[[attunement]]\nid = "x"\nname = "X"\nfaction = "both"\nsteps = [["quest", 1]]\n'
            )
        )
    with pytest.raises(AttunementError, match="standing"):
        read_attunements(
            write(
                '[[attunement]]\nid = "x"\nname = "X"\nfaction = "both"\n'
                'steps = [["rep", 529, "Argent Dawn", 9]]\n'
            )
        )
    with pytest.raises(AttunementError, match="duplicate"):
        read_attunements(
            write(
                '[[attunement]]\nid = "x"\nname = "X"\nfaction = "both"\nsteps = []\n'
                '[[attunement]]\nid = "x"\nname = "Y"\nfaction = "both"\nsteps = []\n'
            )
        )


def test_labels_are_checked_against_the_world(tmp_path):
    world = read_fixture(FIXTURE, "forever")
    before = world.count("attunement")
    p = tmp_path / "a.toml"
    p.write_text(
        '[[attunement]]\nid = "test"\nname = "Test"\nfaction = "both"\n'
        'steps = [["quest", 62, "The Fargodeep Mine"], ["quest", 76, "Wrong Name"], '
        '["quest", 999, "Nowhere"], ["item", 1931, "Huge Gnoll Claw"]]\n',
        encoding="utf-8",
    )
    notes = add_attunements(world, p)
    assert notes == [
        "attunement test: quest 76 is named 'The Jasperlode Mine' in the data, "
        "the list says 'Wrong Name'",
        "attunement test: quest 999 (Nowhere) is not in the data",
    ]
    assert world.count("attunement") == before + 1
    rec = world.get("attunement", "test")
    assert rec["src"] == "config" and rec["verified"] is False and rec["note"] is None
    assert notes == world.notes[-2:]


def test_fixture_attunements_are_packed_with_a_faction_index(tmp_path):
    world = read_fixture(FIXTURE, "forever")
    index = build_index(world, "attunement.byFaction")
    assert index == {"Alliance": ["fargodeep", "gnoll-claw"], "Horde": ["gnoll-claw"]}
    result = build(world, load_config(), tmp_path)
    assert result.ok
    quests = next(p for p in result.packs if p.pack.name == "quests")
    assert quests.counts["attunement"] == 2
    text = quests.path.read_text(encoding="utf-8")
    assert "fargodeep" in text and '"The Fargodeep Mine"' in text and "gnoll-claw" in text
    assert "## Notes" not in (tmp_path / "report.md").read_text(encoding="utf-8")
