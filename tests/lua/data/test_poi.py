"""The point-of-interest facet (ADR 0026, data.md "Points of interest"): roles by rule from NPC
services, object and node kinds and the travel types, through the facet registry."""

from harness import WowRuntime

CORE, DATA = "Bastians_Core", "Bastians_Data"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA)
    wow.run_frames(10)
    wow.execute('Bastians:GetService("data"):LoadPack("world")')
    return wow


def roles(wow: WowRuntime, ref: str) -> list[str] | None:
    facet = wow.eval(f"Bastians:Entity({ref!r}):Facet('poi')")
    return None if facet is None else list(facet.roles.values())


def test_fixture_places_have_their_roles(wow: WowRuntime):
    boot(wow)
    assert roles(wow, "npc:295") == ["rest.inn"]  # Innkeeper Farley
    assert roles(wow, "npc:240") == ["quest.giver"]  # Marshal Dughan
    assert roles(wow, "npc:448") is None  # Hogger: elite is a rank, not a role
    assert roles(wow, "npc:999999") is None  # unknown: no facet, never an empty answer


def test_trainer_kind_comes_from_the_subname(wow: WowRuntime):
    boot(wow)
    found = wow.eval(
        """(function()
          local data = Bastians:GetService("data")
          for _, id in ipairs(data:Each("npc")) do
            local r = data:Get("npc", id)
            if r.subname == "Mage Trainer" then return id end
          end
        end)()"""
    )
    assert found is not None
    assert roles(wow, f"npc:{found}") == ["trainer", "trainer.mage"]


def test_roles_by_rule_on_plain_records(wow: WowRuntime):
    boot(wow)
    cases = {
        "{ 'npc', { flags = { 'vendor', 'repair' } } }": ["vendor", "money.repair"],
        "{ 'npc', { flags = 'flightmaster' } }": ["travel.flightmaster"],
        "{ 'npc', { subname = 'First Aid Trainer' } }": ["trainer", "trainer.first-aid"],
        "{ 'object', { kind = 'mailbox' } }": ["money.mailbox"],
        "{ 'object', { kind = 'fire and forge', name = 'Anvil' } }": ["craft.anvil"],
        "{ 'object', { kind = 'fire and forge', name = 'Campfire' } }": ["craft.fire"],
        "{ 'object', { kind = 'door' } }": [],
        "{ 'node', { kind = 'herb' } }": ["gather.herb"],
        "{ 'flightpath', { name = 'Goldshire' } }": ["travel.flightmaster"],
        "{ 'transport', { kind = 'boat' } }": ["travel.dock"],
        "{ 'npc', nil }": [],
    }
    for case, want in cases.items():
        got = wow.eval(
            f"(function() local c = {case} return Bastians.Data.Poi.Roles(c[1], c[2]) end)()"
        )
        assert list(got.values()) == want, case


def test_the_facet_follows_the_data_module(wow: WowRuntime):
    boot(wow)
    assert wow.eval("Bastians:HasFacet('poi', 'npc')") is True
    assert wow.eval("Bastians:HasFacet('poi', 'quest')") is False
    wow.execute("Bastians:GetModule('Data'):Disable()")
    assert wow.eval("Bastians:HasFacet('poi', 'npc')") is False


def test_an_instance_entrance_is_an_entity_with_its_role(wow: WowRuntime):
    """ADR 0026, W4: entrances from the places table are `entrance:<instance>-<n>` entities."""
    boot(wow)
    e = "Bastians:Entity('entrance:36-1')"
    assert wow.eval(f"{e}:Name()") == "Deadmines"
    assert wow.eval(f"{e}:Summary()").startswith("Instance entrance, Requires level 10")
    assert roles(wow, "entrance:36-1") == ["travel.entrance"]
    assert wow.eval("Bastians:GetService('data'):Get('entrance', '36-1').instance") == 36
    assert roles(wow, "entrance:999-1") is None
