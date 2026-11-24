"""Bastian's Book: ForeverDB's special content as the book's wonders (ADR 0080)."""

import json
from pathlib import Path

import pytest

from bastians_build.__main__ import main
from bastians_build.book import BookError
from bastians_build.build import pack_comment
from bastians_build.model import World
from bastians_build.sources.client_tables import ClientIds, read_ids, read_summons
from bastians_build.sources.fixture import read_fixture
from bastians_build.sources.foreverdb_wonders import (
    parse_books,
    parse_camp,
    parse_collections,
    parse_rares,
    parse_special_quests,
    read_wonders,
)
from bastians_build.wonders import add_wonders, chain_done

ROOT = Path(__file__).resolve().parents[2]
# the fixture ForeverDB files, also the fixture book pack's wonders (the Lua tests' data contract)
DATA = ROOT / "tests" / "fixtures" / "forever-wonders" / "ForeverDB" / "Data"
FIXTURES = ROOT / "tests" / "fixtures"
GOLDEN = FIXTURES / "addons" / "Bastians_Data_Strategies" / "Generated" / "Book.lua"
# every wonder of the fixture pack before round 4 (16.11.2026): none of them changed its id
IDS_BEFORE = {
    "camp:279956",
    "camp:279981",
    "chain:camping-elwynn",
    "chain:keystone-fragment",
    "chain:musical-gustjumper",
    "chain:sleeping-bag",
    "mount:458",
    "mount:5784",
    "pet:4055",
    "rare:61",
    "rare:99",
    "title:144",
}


def text(name: str) -> str:
    return (DATA / name).read_text(encoding="utf-8")


SPECIAL, COLLECTIONS = text("SpecialQuests.lua"), text("Collections.lua")
RARES, BOOKS, CAMP = text("Rares.lua"), text("Books.lua"), text("Camp.lua")


def a_world() -> World:
    w = World(client="forever")
    w.add("zone", 1445, {"name": "Dustwallow Marsh", "continent": 1})
    w.add("zone", 1429, {"name": "Elwynn Forest", "continent": 0})
    w.add("item", 203754, {"name": "Rumi of Gnomeregan"})
    return w


def hooks(folder: Path, text: str = "") -> Path:
    path = folder / "wonders.toml"
    path.write_text("[hooks]\n" + text, encoding="utf-8")
    return path


def test_the_readers_take_each_file():
    chains = parse_special_quests(SPECIAL)
    assert [c.key for c in chains] == [
        "sleeping-bag",
        "camping-elwynn",
        "musical-gustjumper",
        "keystone-fragment",
    ]
    assert chains[0].level == 14 and chains[0].steps[0].side == "H"
    assert chains[1].steps[1].any_quests == (97915, 97916)
    col = parse_collections(COLLECTIONS)
    assert col.mounts[0].source.zone_name == "Dustwallow Marsh"
    assert col.mounts[1].item is None and col.mounts[1].cls == "WARLOCK"
    assert col.titles[0].level == 55
    rares = parse_rares(RARES)
    assert rares[0].seen and rares[0].spots == ((1429, 49.8, 83.7),)  # the seen spot first
    assert rares[0].loot == (6203, 6202) and rares[0].rank == "rare"
    assert not rares[1].seen and {s[0] for s in rares[1].spots} == {1418, 1427}
    assert rares[1].rank == "rare elite"
    books = parse_books(BOOKS)
    assert books[0].places[0][0] == 1429  # the most finds first
    assert parse_camp(CAMP)[0].kit


def test_a_chain_is_done_by_its_last_quest_or_item():
    chains = {c.key: c for c in parse_special_quests(SPECIAL)}
    assert chain_done(chains["sleeping-bag"]) == {"quests": {"A": [79976], "H": [79976]}}
    assert chain_done(chains["camping-elwynn"]) == {"quests": {"A": [97915, 97916]}}
    assert chain_done(chains["musical-gustjumper"]) == {"item": 268109}
    assert chain_done(chains["keystone-fragment"]) is None  # a mark by hand


def test_the_wonders_join_the_world(tmp_path):
    world = a_world()
    data = DATA
    line = '"chain:sleeping-bag" = "I have slept in more barns than most cows."\n'
    n = add_wonders(world, read_wonders(data), hooks(tmp_path, line))
    w = world.records["wonder"]
    # chains, mounts, pets, titles, rares, book, camp
    assert n == len(w) == 4 + 2 + 3 + 2 + 3 + 1 + 2
    bag = w["chain:sleeping-bag"]
    assert bag["chapter"] == "secrets" and bag["kind"] == "chain"
    assert bag["hook"].startswith("I have slept")
    assert bag["levelMin"] == 14 and "levelMax" not in bag  # unknown stays out
    assert bag["zones"] == [1413, 1436, 1437]
    assert bag["place"] == [1413, 0.463, 0.739]  # map fractions
    assert bag["gives"] == [211527, 216619]
    assert bag["steps"][0]["side"] == "H" and bag["steps"][2]["title"] == "The end"
    camp = w["chain:camping-elwynn"]
    assert camp["side"] == "A" and (camp["chapter"], camp["kind"]) == ("camp", "camping")
    assert "—" not in camp["tale"]  # the game fonts lack it
    frog = w["chain:musical-gustjumper"]
    assert (frog["chapter"], frog["kind"]) == ("secrets", "pet")
    riddle = w["chain:keystone-fragment"]
    assert (riddle["chapter"], riddle["kind"]) == ("secrets", "unsolved")
    assert "facets" not in riddle  # "seen" and "unsolved" are the state and the kind now
    horse = w["mount:458"]
    assert horse["zones"] == [1445]
    assert horse["tale"] == "Sold by Gregor MacVince, Dustwallow Marsh."
    assert horse["done"] == {"spell": 458, "item": 5656}
    assert horse["facets"] == {"source": "vendor"}
    assert "zones" not in w["mount:5784"]  # a quest, no zone named
    assert w["title:144"]["done"] == {"title": 144} and w["title:144"]["levelMin"] == 55
    rare = w["rare:61"]
    assert rare["npc"] == 61 and rare["kind"] == "rare" and rare["facets"] == {"type": "Humanoid"}
    assert rare["tale"] == "A rare humanoid, level 11. Comes back after 1h 30 to 2h 30."
    assert w["rare:99"]["tale"].startswith("A rare elite humanoid, level 10 to 12.")
    book = w["book:203754"]
    assert book["name"] == "Rumi of Gnomeregan" and book["side"] == "A"
    assert book["chapter"] == "collections" and book["facets"] == {"source": "object"}
    assert book["done"] == {"item": 203754, "quests": {"A": [79091]}}
    assert "book:215683" not in w  # only in the client's files
    assert "book:999" not in w and ("wonder", "book:999") in [d[:2] for d in world.dropped]
    assert w["camp:279956"]["tale"] == "Levels 24-33."  # the en dash as ASCII
    assert w["camp:279956"]["facets"] == {"profession": "Alchemy", "skill": 20}
    kit = w["camp:279981"]
    assert (kit["chapter"], kit["kind"]) == ("camp", "camp kit")


def test_a_line_for_a_wonder_that_does_not_exist_is_refused(tmp_path):
    data = DATA
    with pytest.raises(BookError, match="chain:nothing"):
        add_wonders(a_world(), read_wonders(data), hooks(tmp_path, '"chain:nothing" = "Hm."\n'))


def test_a_scene_names_a_wonder_or_a_chapter_and_passes_the_text_check(tmp_path):
    """The drawings' scene lines (D5) stand beside Bastian's lines and are held the same way."""
    good = (
        '[scenes]\n"chain:sleeping-bag" = "Low angle: a hayloft."\n'
        '"chapter:camp" = "Close-up: a fire."\n"mount:10795" = "Wide shot: no raptor."\n'
    )
    world = a_world()
    add_wonders(world, read_wonders(DATA), hooks(tmp_path, good))  # one that is out keeps its scene
    assert "scene" not in world.records["wonder"]["chain:sleeping-bag"]  # not in the pack
    nothing = hooks(tmp_path, '[scenes]\n"chain:nothing" = "Hm."\n')
    with pytest.raises(BookError, match="scenes for wonders that do not exist: chain:nothing"):
        add_wonders(a_world(), read_wonders(DATA), nothing)
    dash = hooks(tmp_path, '[scenes]\n"rare:61" = "A - b."\n')
    with pytest.raises(BookError, match="dash"):
        add_wonders(a_world(), read_wonders(DATA), dash)


def test_bastians_lines_pass_the_text_check(tmp_path):
    data = DATA
    bad = '"chain:sleeping-bag" = "A bed - for me."\n'
    with pytest.raises(BookError, match="dash"):
        add_wonders(a_world(), read_wonders(data), hooks(tmp_path, bad))


def test_the_book_pack_carries_the_credit_with_wonders(tmp_path):
    world = World(client="forever")
    assert "ForeverDB" not in pack_comment("book", world)
    add_wonders(world, read_wonders(DATA), hooks(tmp_path))
    assert "Data: ForeverDB.net (https://foreverdb.net)" in pack_comment("book", world)


def test_the_real_lines_name_real_wonders():
    """content/strategies/wonders.toml against ForeverDB's chains (when the source is here)."""
    data = ROOT / ".local" / "sources" / "forever" / "ForeverDB" / "Data"
    if not (data / "SpecialQuests.lua").is_file():
        pytest.skip("ForeverDB is not in .local/sources")
    world = World(client="forever")
    add_wonders(world, read_wonders(data), ROOT / "content" / "strategies" / "wonders.toml")
    w = world.records["wonder"]
    assert sum(1 for x in w.values() if x.get("hook")) >= 15
    assert len(w) > 600
    assert {r["chapter"] for r in w.values()} == {"secrets", "collections", "camp", "rares"}


def spell_effects(folder: Path, rows: list[dict]) -> Path:
    """A dump of SpellEffect as the clientdump writes it, under the build's prefix."""
    (folder / "f1_SpellEffect.json").write_text(json.dumps({"rows": rows}), encoding="utf-8")
    return folder


def effect(spell: int, effect: int, misc: int, aura: int = 0, index: int = 0) -> dict:
    return {
        "SpellID": spell,
        "Effect": effect,
        "EffectAura": aura,
        "EffectIndex": index,
        "EffectMiscValue": [misc, 0],
    }


def test_the_client_names_the_creature_of_a_mount_and_a_pet(tmp_path):
    dumps = spell_effects(
        tmp_path,
        [
            effect(458, 6, 284, aura=78),  # the Brown Horse: mounted, creature 284
            effect(458, 6, 999, aura=32, index=1),  # its speed aura: no creature
            effect(4055, 28, 2671),  # the Mechanical Squirrel: summoned
            effect(10673, 28, 7385, index=1),
            effect(10673, 28, 7386, index=2),  # the lower index wins
            effect(133, 2, 0),  # a fireball: nothing
            effect(1, 28, 0),  # a summon of nothing
        ],
    )
    assert read_summons(dumps, "f1") == {458: 284, 4055: 2671, 10673: 7385}
    assert read_summons(tmp_path / "missing", "f1") == {}


def test_a_mount_and_a_pet_take_their_creature_for_the_model(tmp_path):
    world = a_world()
    add_wonders(world, read_wonders(DATA), hooks(tmp_path, ""), {458: 284, 4055: 2671})
    w = world.records["wonder"]
    assert w["mount:458"]["npc"] == 284
    assert w["pet:4055"]["npc"] == 2671
    assert "npc" not in w["mount:5784"]  # unknown stays out: the plate


# ---------------------------------------------------------------- round 4 (book.md "Round 4")


def the_fixture_world() -> World:
    """world-mini: Hogger and Goldtooth drop Linen Cloth, Corina Steele sells it and the Blood
    Saber, the quest Wanted: "Hogger" gives the Blood Saber."""
    return read_fixture(FIXTURES / "world-mini", "forever")


def wonders_of(world: World, tmp_path: Path, client: ClientIds | None = None) -> dict:
    add_wonders(world, read_wonders(DATA), hooks(tmp_path), None, client)
    return world.records["wonder"]


def test_every_wonder_has_its_state(tmp_path):
    """E2: in when players saw it in Forever or it is Forever's own with its way told; unknown
    when it is in the client and nobody saw it."""
    world = a_world()
    w = wonders_of(world, tmp_path)
    states = {wid: rec["state"] for wid, rec in w.items()}
    assert set(states.values()) == {"in", "unknown"}
    seen = ("mount:5784", "pet:10683", "rare:61", "book:203754")
    assert all(states[wid] == "in" for wid in seen)
    own = ("chain:sleeping-bag", "chain:keystone-fragment", "camp:279956", "title:144")
    assert all(states[wid] == "in" for wid in own)  # a chain nobody solved is told as unsolved
    nobody_saw = ("mount:458", "pet:4055", "pet:10675", "rare:99", "rare:5912", "title:1258")
    assert all(states[wid] == "unknown" for wid in nobody_saw)
    assert "wonders: 11 in, 6 unknown, 4 out (the client not read)" in world.notes[0]
    assert "mount 1 in, 1 unknown, 1 out" in world.notes[0]


def test_what_is_out_is_dropped_with_its_reason(tmp_path):
    """E2: a mount no item teaches, a rare with no place at all, an item or a spell the client
    does not hold. The report names each."""
    world = a_world()
    w = wonders_of(world, tmp_path)
    out = {wid: why for kind, wid, why in world.dropped if kind == "wonder"}
    assert out == {
        "mount:10795": "no item in the client teaches it, and no other way is known",
        "rare:777": "the creature has no place",
        "book:999": "the item has no name in the world",
        "title:1312": "a placeholder name in the client: not finished",
    }
    assert not set(out) & set(w)
    assert "rare:5912" in w  # a dungeon's rare has no place on a map and is no less there
    # the same against a client that holds neither the horse's bridle nor the raptor's spell
    world = a_world()
    client = ClientIds(
        items=frozenset({4401, 2589, 1185, 203754, 279956, 279981}),
        spells=frozenset({458, 5784, 4055, 10675, 10683}),
    )
    w = wonders_of(world, tmp_path, client)
    out = {wid: why for kind, wid, why in world.dropped if kind == "wonder"}
    assert out["mount:458"] == "its item is not in the client"
    assert out["mount:10795"] == "its spell is not in the client"
    assert out["book:999"] == "its item is not in the client"
    assert "mount:458" not in w and "mount:5784" in w  # the class mount has no item to miss
    assert "(held against the client's items and spells)" in world.notes[0]
    # a rare the world places stays, though ForeverDB has no spot for it
    world = a_world()
    world.add("npc", 777, {"name": "Lost Stray", "spawns": [[1429, 0.5, 0.5, "classic"]]})
    assert "rare:777" in wonders_of(world, tmp_path)


def test_the_client_names_its_items_and_spells(tmp_path):
    (tmp_path / "f1_ItemSparse.json").write_text(
        json.dumps({"rows": [{"ID": 5656}, {"ID": 2589}, {"ID": "x"}]}), encoding="utf-8"
    )
    assert read_ids(tmp_path, "f1") is None  # no spell table: nothing is judged
    (tmp_path / "f1_SpellName.json").write_text(
        json.dumps({"rows": [{"ID": 458}]}), encoding="utf-8"
    )
    assert read_ids(tmp_path, "f1") == ClientIds(frozenset({5656, 2589}), frozenset({458}))


def test_a_source_is_a_reference(tmp_path):
    """R4.3: a drop, a vendor, a quest, a crafted one, a name that matches nothing."""
    world = the_fixture_world()
    world.add("item", 4401, {"name": "Mechanical Squirrel Box"})
    world.add("recipe", 3928, {"name": "Mechanical Squirrel", "item": 4401})
    w = wonders_of(world, tmp_path)
    # a drop: the creature ForeverDB names first, then the item's other ways in the world
    assert w["pet:10675"]["from"] == [
        ["drop", "npc:448"],
        ["drop", "npc:327"],
        ["vendor", "npc:54"],
    ]
    assert w["pet:10675"]["tale"] == "Drops from Hogger."  # the sentence stays for a suite alone
    # a quest by its name without the level, once, and the vendor the world knows beside it
    assert w["pet:10683"]["from"] == [["quest", "quest:176"], ["vendor", "npc:54"]]
    # a crafted one: the recipe that makes the item
    assert w["pet:4055"]["from"] == [["craft", "recipe:3928"]]
    # a name that matches nothing: the sentence stays, the miss is in the report
    assert "from" not in w["mount:458"] and w["mount:458"]["tale"].startswith("Sold by Gregor")
    assert "from" not in w["mount:5784"]
    note = world.notes[1]
    assert note.startswith("wonder sources: 3 wonders name their sources as references; 2 named")
    assert "mount:458 (no npc is named 'Gregor MacVince, Dustwallow Marsh')" in note
    assert "mount:5784 (no quest is named 'Summon Felsteed')" in note
    assert "pet:4055" not in note  # a profession is no entity: nothing to miss
    # nothing is copied: no chance, no price, no place
    assert all(len(row) == 2 for rec in w.values() for row in rec.get("from") or [])


def test_a_name_two_creatures_carry_is_settled_or_stays_a_sentence(tmp_path):
    def twins(**second) -> World:
        world = the_fixture_world()
        world.add("zone", 1445, {"name": "Dustwallow Marsh", "continent": 1})
        world.add("npc", 4885, {"name": "Gregor MacVince", "spawns": [[1429, 0.1, 0.1, "fdb"]]})
        world.add("npc", 9001, {"name": "Gregor MacVince", **second})
        return world

    # by the one that sells the item
    world = twins(vendor=[[5656, 200000, 1, False, "classic"]])
    assert wonders_of(world, tmp_path)["mount:458"]["from"][0] == ["vendor", "npc:9001"]
    # by the zone in the source's text
    world = twins(spawns=[[1445, 0.65, 0.51, "fdb"]])
    assert wonders_of(world, tmp_path)["mount:458"]["from"] == [["vendor", "npc:9001"]]
    # by neither: a sentence, and the report says why
    world = twins()
    assert "from" not in wonders_of(world, tmp_path)["mount:458"]
    assert "mount:458 (2 npcs are named 'Gregor MacVince')" in world.notes[1]


def test_no_wonder_changed_its_id(tmp_path):
    """E1 moves wonders between chapters and never renames one: every mark and bookmark stays."""
    w = wonders_of(a_world(), tmp_path)
    assert set(w) >= IDS_BEFORE
    chapters = {wid: rec["chapter"] for wid, rec in w.items()}
    assert chapters["chain:sleeping-bag"] == chapters["chain:musical-gustjumper"] == "secrets"
    assert chapters["camp:279981"] == chapters["chain:camping-elwynn"] == "camp"
    assert chapters["book:203754"] == chapters["title:144"] == "collections"


def test_the_real_pack_keeps_its_ids_and_names_what_is_out():
    """The real ForeverDB (when the source is here): the ids as before round 4, every wonder in
    one of the four chapters with a state, the ones that are out named."""
    data = ROOT / ".local" / "sources" / "forever" / "ForeverDB" / "Data"
    if not (data / "SpecialQuests.lua").is_file():
        pytest.skip("ForeverDB is not in .local/sources")
    world = World(client="forever")
    add_wonders(world, read_wonders(data), ROOT / "content" / "strategies" / "wonders.toml")
    w = world.records["wonder"]
    kinds = {"chain", "mount", "pet", "title", "rare", "book", "camp"}
    assert all(wid.split(":")[0] in kinds for wid in w)
    assert all(r["state"] in ("in", "unknown") for r in w.values())
    out = {wid for kind, wid, _ in world.dropped if kind == "wonder"}
    assert out and not out & set(w)


def test_the_fixture_book_pack_is_what_the_generator_writes(tmp_path, capsys):
    """The Lua tests load the wonders the real generator makes (CLAUDE.md section 7)."""
    hint = (
        "regenerate with: python -m bastians_build data --client forever "
        "--fixture tests/fixtures/world-mini --export tests/fixtures/export-mini "
        "--book tests/fixtures/book-mini --wonders tests/fixtures/forever-wonders/ForeverDB/Data "
        "--out <a temp folder> --report-dir <a temp folder>, then copy "
        "Bastians_Data_Strategies/Generated/Book.lua to tests/fixtures/addons"
    )
    args = [
        "data",
        "--client",
        "forever",
        "--fixture",
        str(FIXTURES / "world-mini"),
        "--export",
        str(FIXTURES / "export-mini"),
        "--book",
        str(FIXTURES / "book-mini"),
        "--wonders",
        str(DATA),
        "--out",
        str(tmp_path / "out"),
        "--report-dir",
        str(tmp_path / "report"),
    ]
    assert main(args) == 0
    capsys.readouterr()
    fresh = tmp_path / "out" / "Bastians_Data_Strategies" / "Generated" / "Book.lua"
    assert fresh.read_text(encoding="utf-8") == GOLDEN.read_text(encoding="utf-8"), hint
    report = (tmp_path / "report" / "report.md").read_text(encoding="utf-8")
    assert "wonders: 10 in, 6 unknown, 5 out (the client not read)" in report
    assert "mount:10795" in report and "no item in the client teaches it" in report


def test_a_wonder_with_a_drawing_is_marked(tmp_path):
    """R4.9: a wonder whose drawing lies in the pictures' folder (its id with a dash for the
    colon) gets `art`, as a page does; the others carry no mark, and the report counts them."""
    art = tmp_path / "art"
    art.mkdir()
    (art / "chain-sleeping-bag.jpg").write_bytes(b"jpeg")
    (art / "chain-nothing.jpg").write_bytes(b"jpeg")  # a picture of no wonder marks nothing
    world = a_world()
    add_wonders(world, read_wonders(DATA), hooks(tmp_path, ""), art=art)
    w = world.records["wonder"]
    assert w["chain:sleeping-bag"]["art"] is True
    assert [wid for wid, rec in w.items() if rec.get("art")] == ["chain:sleeping-bag"]
    assert "wonder pictures: 1 wonders have a drawing in art/" in world.notes
    plain = a_world()
    add_wonders(plain, read_wonders(DATA), hooks(tmp_path, ""))
    assert not any(rec.get("art") for rec in plain.records["wonder"].values())
    assert not any(n.startswith("wonder pictures") for n in plain.notes)
