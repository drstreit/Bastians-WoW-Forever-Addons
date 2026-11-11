"""QuestieDB's baked store (sources.md): TOC lines of base64 CBOR -> typed rows."""

import base64

from bastians_build.sources.questiedb_store import parse_store


def cbor(value) -> bytes:
    if value is None:
        return b"\xf6"
    if isinstance(value, float):
        import struct

        return b"\xfb" + struct.pack(">d", value)
    if isinstance(value, int):
        return _head(0, value) if value >= 0 else _head(1, -1 - value)
    if isinstance(value, str):
        data = value.encode("utf-8")
        return _head(3, len(data)) + data
    if isinstance(value, list):
        return _head(4, len(value)) + b"".join(cbor(v) for v in value)
    return _head(5, len(value)) + b"".join(cbor(k) + cbor(v) for k, v in value.items())


def _head(major: int, n: int) -> bytes:
    if n < 24:
        return bytes([major << 5 | n])
    if n < 256:
        return bytes([major << 5 | 24, n])
    if n < 65536:
        return bytes([major << 5 | 25]) + n.to_bytes(2, "big")
    return bytes([major << 5 | 26]) + n.to_bytes(4, "big")


def line(key: str, value) -> str:
    return f"## X-{key}: {base64.b64encode(cbor(value)).decode('ascii')}\n"


def test_a_row_and_a_field_of_its_own_make_one_npc():
    store = parse_store(
        [
            "## Title: QuestieDB\n",
            line(
                "Npc-254089-S", {1: "Coriella Calmbreeze", 4: 10, 5: 10, 13: "AH", 15: 132, "p": 64}
            ),
            line("Npc-254089-7", {16593: [[43.01, 43.23]]}),
        ]
    )
    npc = store.npcs[254089]
    assert npc.name == "Coriella Calmbreeze"
    assert (npc.level, npc.level_max, npc.friendly, npc.npc_flags) == (10, 10, "AH", 132)
    assert npc.places == {16593: [(43.01, 43.23)]}


def test_a_row_may_be_an_array_and_a_field_may_come_in_parts():
    whole = base64.b64encode(cbor({16593: [[1.5, 2.5], [3.5, 4.5]]})).decode("ascii")
    store = parse_store(
        [
            line("Npc-7-S", ["Mob", None, None, 9999, 9999, 4]),
            "## X-Npc-7-7: ~2~\n",
            f"## X-Npc-7-7-1: {whole[:8]}\n",
            f"## X-Npc-7-7-2: {whole[8:]}\n",
        ]
    )
    npc = store.npcs[7]
    assert npc.rank == 4
    assert npc.level is None and npc.level_max is None  # 9999 is the addon's placeholder
    assert npc.places == {16593: [(1.5, 2.5), (3.5, 4.5)]}


def test_points_off_the_map_and_rows_without_a_point_are_left_out():
    store = parse_store(
        [line("Object-5-S", {1: "Chest", 4: {16593: [[-1, -1], [50.0, 50.0]], 12: [[None, None]]}})]
    )
    assert store.objects[5].places == {16593: [(50.0, 50.0)]}


def test_a_quest_reads_its_positional_groups_as_array_or_map():
    store = parse_store(
        [
            line(
                "Quest-92465-S",
                {
                    1: "Agitators",
                    2: [[249363]],
                    3: [[249363], [55]],
                    4: 2,
                    5: 3,
                    8: ["Slay 6 Roiling Winds", "and 7 Converts."],
                    10: [[[251160, None, 0], [251143, None, 0]]],
                    17: 16593,
                    26: [[2778, 50]],
                },
            ),
            line("Quest-93459-S", {1: "More Ears", 10: {3: [[258771, None, 0]]}}),
        ]
    )
    q = store.quests[92465]
    assert q.starts_npc == (249363,) and q.ends_npc == (249363,) and q.ends_object == (55,)
    assert q.creatures == (251160, 251143) and q.items == ()
    assert q.objective_text == "Slay 6 Roiling Winds and 7 Converts."
    assert (q.level, q.min_level, q.rep) == (3, 2, ((2778, 50),))
    assert store.quests[93459].items == (258771,)  # the map form: groups 1 and 2 are empty
    assert store.quests[93459].creatures == ()


def test_an_item_row_names_who_drops_holds_and_sells_it():
    """Package QD1 (plan-quest-links.md G1): the field numbers of the addon's itemMeta.lua.
    Mirror Lake's water sample is the store's own row, 1.0.13: object 174794 in a field of its
    own."""
    store = parse_store(
        [
            "## X-Item-7206-3: gRoAAqrK\n",
            "## X-Item-7206-15: gRkHRA==\n",
            "## X-Item-7206-S: pAFYGE1pcnJvciBMYWtlIFdhdGVyIFNhbXBsZQkBDAxBcBlABA==\n",
            line("Item-10-S", {1: "Pelt", 2: [5, 6], 4: [77], 14: [8], 9: 12}),
            line("Item-11-S", {1: "Sword", 9: 30}),  # an item nobody is known to have
            line("Item-12-2", {1: 9, 2: 4}),  # an id list kept as a map: in the order of its keys
        ]
    )
    water = store.items[7206]
    assert water.object_drops == (174794,)
    assert (water.npc_drops, water.item_drops, water.vendors) == ((), (), ())
    pelt = store.items[10]
    assert (pelt.npc_drops, pelt.item_drops, pelt.vendors) == ((5, 6), (77,), (8,))
    assert 11 not in store.items
    assert store.items[12].npc_drops == (9, 4)
    assert store.npcs == {} and store.quests == {}
