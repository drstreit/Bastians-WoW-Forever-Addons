"""The Strategies book compiler (strategies-design.md sections 6 and 7): content files -> book
records, checked against the fixture world and export; the plates precomputed; the pack and its
index; the tombstones and the back shelf; every refusal says where and why."""

import math
import shutil
from pathlib import Path

import pytest

from bastians_build.__main__ import main
from bastians_build.book import BookError, add_book, book_toc, parse_body, spot_plate
from bastians_build.build import build
from bastians_build.config import load_config
from bastians_build.model import World
from bastians_build.sources.ahsync_export import read_export
from bastians_build.sources.fixture import read_fixture
from bastians_build.sources.probe import Transform

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "tests" / "fixtures" / "world-mini"
EXPORT = ROOT / "tests" / "fixtures" / "export-mini"
BOOK = ROOT / "tests" / "fixtures" / "book-mini"


def world_with_book(content: Path = BOOK, transforms=None):
    world = read_fixture(WORLD, "forever")
    add_book(world, read_export(EXPORT), content, transforms)
    return world


def copy_book(tmp_path: Path) -> Path:
    target = tmp_path / "book"
    shutil.copytree(BOOK, target)
    return target


def test_pages_chapters_rumours_news_and_the_tombstone():
    world = world_with_book()
    assert world.get("chapter", "farming")["name"] == "Farming and easy kills"
    page = world.get("page", "hogger-camp")
    assert page["name"] == "Hogger's Camp" and page["chapter"] == "farming"
    assert (page["levelMin"], page["levelMax"], page["zones"]) == (9, 12, [1429])
    assert page["shelf"] == "active" and page["updated"] == "2026-10-23"
    # the text as blocks: the opening before the first heading, the steps with a continued line
    assert [b[0] for b in page["blocks"]] == [
        "opening",
        "h",
        "p",
        "plate",
        "h",
        "steps",
        "live",
        "verdict",
    ]
    assert page["blocks"][5][1] == [
        "Walk the loop.",
        "Kill {npc:448} when he is up. He is up often.",
    ]
    assert page["blocks"][-1] == ["verdict", "Fine for a beginner."]
    # the entities named in the text, in order; price and vendor tokens are no entities
    assert page["refs"] == ["item:2589", "npc:448"]
    # the rumours: the export's status as the stamp unless the page sets its own
    assert page["rumours"] == [
        [11, "true", None],
        [12, "half", "Only the kobolds near the entrance."],
    ]
    rumour = world.get("rumour", 11)
    assert rumour["claim"] == "Hogger's camp in Elwynn drops a lot of Linen Cloth."
    # only web links leave AHSync: the local guide path is dropped
    assert rumour["sources"] == [
        ["Fixture Channel", "2026-10-13", "https://www.youtube.com/watch?v=fixture1&t=85s"]
    ]
    back = world.get("page", "leather-trick")
    assert back["shelf"] == "back" and back["table"] == {
        "kind": "vendorpairs",
        "rows": [[2589, 2318, 1]],
    }
    assert back["live"] == {"kind": "flip", "buy": 2589, "sell": 2318, "per": 1}
    tomb = world.get("page", "old-gnolls")
    assert tomb["shelf"] == "retired" and tomb["successor"] == "hogger-camp"
    assert "blocks" not in tomb
    # What's new, newest first
    assert [world.get("news", i)["text"] for i in (1, 2)] == [
        "New page: Hogger's Camp.",
        "The book opens.",
    ]
    assert any(
        n.startswith("book: 2 chapters, 1 active pages, 1 on the back shelf, 1 retired")
        for n in world.notes
    )


def test_the_spot_plate_is_precomputed_in_plate_coordinates():
    world = world_with_book()
    plate = world.get("page", "hogger-camp")["plate"]
    assert plate["kind"] == "spot" and plate["label"] == "the camp"
    pts = plate["farm"] + plate["avoid"]
    assert all(0 <= x <= 1 and 0 <= y <= 1 for x, y in pts)
    assert len(plate["farm"]) == 2 and len(plate["avoid"]) == 1
    assert plate["landmark"] == {"glyph": "keep", "label": "Goldtooth", "at": plate["avoid"][0]}
    # the loop runs inside the farm's outline; the start is its west end
    assert plate["start"] == min(plate["loop"])
    assert "across" not in plate and "fp" not in plate  # no transforms in a fixture build
    assert plate["place"] == [1429, 0.285, 0.83]  # Hogger's two spawns, averaged: the map pin


def test_a_transform_gives_the_yards_across_and_the_nearest_flight_point():
    world = read_fixture(WORLD, "forever")
    # Elwynn: 3000 yards across, 2000 down, origin at (-1000, 0) on continent 0
    t = Transform(1429, 0, -1000.0, 3000.0, 0.0, 0.0, 0.0, 2000.0, True)
    spec = {"map": 1429, "farm": [448], "avoid": [327]}
    plate = spot_plate(spec, world, {1429: t}, "test")
    assert 100 < plate["across"] < 400  # the dots span about 0.12 of 3000 yards plus the air
    fps = {fp["faction"]: fp for fp in plate["fp"]}
    assert set(fps) <= {"A", "H"} and "A" in fps
    fp = fps["A"]
    assert fp["yards"] > 0 and isinstance(fp["name"], str) and -math.pi <= fp["angle"] <= math.pi
    # a flight point in the page's own zones wins over a nearer one elsewhere (mountains between)
    near = spot_plate(spec, world, {1429: t}, "test")["fp"][0]
    zoned = spot_plate(spec, world, {1429: t}, "test", zones=[1453])["fp"][0]
    assert near["name"] == "Sentinel Hill, Westfall" and zoned["name"] == "Stormwind, Elwynn"
    # the page can name the flight point a player really uses (the harpy cave: not Un'Goro)
    chosen = spot_plate({**spec, "fp": {"A": 6}}, world, {1429: t}, "test")["fp"][0]
    assert chosen["name"] == "Ironforge, Dun Morogh" and chosen["yards"] > near["yards"]
    with pytest.raises(BookError, match="A = 23 is no A flight point"):
        spot_plate({**spec, "fp": {"A": 23}}, world, {1429: t}, "x.md")  # Orgrimmar is Horde


def test_the_toc_lists_active_pages_by_chapter_in_order():
    toc = book_toc(world_with_book())
    assert toc["chapters"] == ["farming", "crafting"]
    assert toc["pages"] == {"farming": ["hogger-camp"], "crafting": []}  # back and retired: out


@pytest.mark.parametrize(
    ("edit", "message"),
    [
        (lambda t: t.replace("I'm standing", "I" + chr(0x2019) + "m standing"), "U+2019"),
        (lambda t: t.replace("I'm standing at", "I'm standing - at"), "dash"),
        (lambda t: t.replace("{item:2589} and", "{item:99999} and"), "no item 99999"),
        (lambda t: t.replace("{item:2589} and", "{thing:1} and"), "unknown token"),
        (lambda t: t.replace("claim = 12", "claim = 777"), "claim 777 is not in the export"),
        (lambda t: t.replace('title = "Hogger\'s Camp"\n', ""), "missing `title`"),
        (lambda t: t.replace("{live}\n", ""), "[live] and the {live} line go together"),
        (lambda t: t.replace('stamp = "half"', 'stamp = "maybe"'), "stamp must be one of"),
        (lambda t: t.replace("zones = [1429]", "zones = [4242]"), "zone 4242"),
    ],
)
def test_refusals_name_the_page_and_the_reason(tmp_path, edit, message):
    content = copy_book(tmp_path)
    page = content / "farming" / "hogger-camp.md"
    page.write_text(edit(page.read_text(encoding="utf-8")), encoding="utf-8")
    with pytest.raises(BookError) as err:
        world_with_book(content)
    assert message in str(err.value) and "farming/hogger-camp.md" in str(err.value)


def test_page_ids_are_file_names_and_unique(tmp_path):
    content = copy_book(tmp_path)
    shutil.copy(content / "farming" / "hogger-camp.md", content / "farming" / "Hogger_Camp.md")
    with pytest.raises(BookError, match="lowercase words and dashes"):
        world_with_book(content)
    (content / "farming" / "Hogger_Camp.md").unlink()
    shutil.copy(content / "farming" / "hogger-camp.md", content / "crafting" / "hogger-camp.md")
    with pytest.raises(BookError, match="used twice"):
        world_with_book(content)


def test_a_tombstone_must_not_shadow_a_page(tmp_path):
    content = copy_book(tmp_path)
    toml = content / "book.toml"
    toml.write_text(
        toml.read_text(encoding="utf-8").replace('id = "old-gnolls"', 'id = "hogger-camp"'),
        encoding="utf-8",
    )
    with pytest.raises(BookError, match="is still a page"):
        world_with_book(content)


def test_parse_body_without_text_is_refused():
    with pytest.raises(BookError, match="no text"):
        parse_body("## Why it pays\n{plate}\n", "x.md")


def test_the_pack_is_written_deterministically_and_only_with_content(tmp_path):
    config = load_config()
    world = world_with_book()
    result = build(world, config, tmp_path / "a")
    book = next(p for p in result.packs if p.pack.name == "book")
    assert book.counts == {"chapter": 2, "page": 3, "rumour": 2, "news": 2, "mill": 0}
    text = book.path.read_text(encoding="utf-8")
    assert text.startswith("-- GENERATED by bastians_build") and '"book"' in text
    assert book.path.as_posix().endswith("Bastians_Data_Strategies/Generated/Book.lua")
    again = build(world_with_book(), config, tmp_path / "b")
    other = next(p for p in again.packs if p.pack.name == "book")
    assert other.path.read_bytes() == book.path.read_bytes()


def test_the_cli_takes_a_book_with_an_export_only(tmp_path, capsys):
    base = ["data", "--client", "forever", "--fixture", str(WORLD), "--out", str(tmp_path)]
    base += ["--report-dir", str(tmp_path)]
    assert main([*base, "--book", str(BOOK)]) == 2
    assert "--book needs --export" in capsys.readouterr().err
    assert main([*base, "--book", str(BOOK), "--export", str(EXPORT)]) == 0
    assert (tmp_path / "Bastians_Data_Strategies" / "Generated" / "Book.lua").is_file()


def test_another_clients_build_carries_no_book():
    world = World(client="retail")
    notes = add_book(world, read_export(EXPORT), BOOK)
    assert notes == ["book: written for forever, not built for retail"]
    assert world.count("page") == 0


def test_live_craft_resolves_the_recipe_and_prices_lists_items():
    from bastians_build.book import check_live

    world = read_fixture(WORLD, "forever")
    craft = check_live({"kind": "craft", "recipe": 2152}, world, "x.md")
    assert craft == {
        "kind": "craft",
        "recipe": 2152,
        "item": 2304,
        "count": 1,
        "reagents": [[2318, 1]],
    }
    assert check_live({"kind": "prices", "items": [2589]}, world, "x.md") == {
        "kind": "prices",
        "items": [2589],
    }
    with pytest.raises(BookError, match="no recipe 9"):
        check_live({"kind": "craft", "recipe": 9}, world, "x.md")
    with pytest.raises(BookError, match="kind must be farm, flip, craft or prices"):
        check_live({"kind": "guess"}, world, "x.md")


def test_a_plate_refuses_unknown_glyphs_and_tints():
    from bastians_build.book import flow_plate

    ok = {"glyph": "cloth", "title": "Silk"}
    with pytest.raises(BookError, match="no glyph 'ghost'"):
        flow_plate({"nodes": [ok, {"glyph": "ghost", "title": "Boo"}]}, "x.md")
    with pytest.raises(BookError, match="tint must be one of"):
        flow_plate({"nodes": [ok, {"glyph": "vendor", "title": "V", "tint": "red"}]}, "x.md")
    assert flow_plate({"nodes": [ok, {"glyph": "vendor", "title": "V", "tint": "gold"}]}, "x.md")
