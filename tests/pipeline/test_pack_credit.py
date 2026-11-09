"""ForeverDB's licence asks that its credit line stays with its data (GPL-3.0 section 7(b))."""

from bastians_build.build import pack_comment
from bastians_build.emit import emit_pack
from bastians_build.model import World


def world(*sources: str) -> World:
    return World(client="forever", build="70862", sources=list(sources))


def test_a_pack_with_its_data_carries_the_line_the_licence_names():
    text = emit_pack("quests", {}, comment=pack_comment("quests", world("ForeverDB 0.57.15")))
    lines = text.splitlines()
    assert lines[1] == "-- pack quests for forever, build 70862"  # tools/release.py reads this one
    assert lines[2].startswith("-- Data: ForeverDB.net (https://foreverdb.net)")


def test_the_language_packs_carry_it_too():
    assert "ForeverDB.net" in pack_comment("text_deDE", world("ForeverDB 0.57.15"), localized=True)


def test_a_pack_without_its_data_or_a_build_without_the_source_does_not():
    assert "ForeverDB.net" not in pack_comment("market", world("ForeverDB 0.57.15"))
    assert "ForeverDB.net" not in pack_comment("quests", world("Everything Quests 2.10.0"))
