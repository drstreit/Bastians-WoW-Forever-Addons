"""Places (ADR 0026, W5): the entity facade's world positions over the packs' map places, with the
height the Classic spawns and the client's TaxiNodes carry."""

from harness import WowRuntime

CORE, DATA = "Bastians_Core", "Bastians_Data"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA)
    wow.run_frames(10)
    wow.execute('Bastians:GetService("data"):LoadPack("world")')
    return wow


def every_place(wow: WowRuntime, kind: str) -> list:
    """All places of every record of a type in the fixture packs."""
    return list(
        wow.eval(
            f"""(function()
              local out, data = {{}}, Bastians:GetService("data")
              for _, id in ipairs(data:Each("{kind}")) do
                for _, p in ipairs(Bastians:Entity("{kind}:" .. id):AllPlaces()) do
                  out[#out + 1] = p
                end
              end
              return out
            end)()"""
        ).values()
    )


def test_classic_spawns_carry_their_height_into_places(wow: WowRuntime):
    boot(wow)
    places = every_place(wow, "npc")
    assert places, "the fixture has npc places"
    classic = [p for p in places if p.src == "classic"]
    assert classic, "the fixture has CMaNGOS spawns"
    assert all(p.wz is not None for p in classic)
    # a place with a transform has a world position on its continent; the fractions stay
    placed = [p for p in places if p.wx is not None]
    assert placed and all(p.map in (0, 1) and p.ui and p.x is not None for p in placed)
    # sources without a height leave it nil, never 0 (unknown is not zero)
    assert all(p.wz is None for p in places if p.src not in ("classic", "client"))
