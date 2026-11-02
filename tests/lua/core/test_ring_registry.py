"""Core's ring registry (core-contracts §13 "Rings", plan-second-wave.md decision F): an app offers
a ring while it is enabled; the host reads the registry by order; the registration goes with the
owner's disable and with UnregisterRing, both announced on the bus."""

from harness import WowRuntime


def test_rings_register_sort_and_go_with_their_owner(wow: WowRuntime):
    wow.start("Bastians_Core")
    wow.execute(
        """
        Seen = {}
        Bastians:GetModule('Core'):On('BASTIANS_REGISTRY_CHANGED', function(_, _, kind, id, added)
          if kind == 'ring' then Seen[#Seen + 1] = id .. (added and '+' or '-') end
        end)
        A = Bastians:NewModule('RingA', { addon = 'Bastians_Core', apiVersion = 1 })
        A:Enable()
        local items = function() return { { label = 'x' } } end
        local fire = function() return true end
        Bastians:RegisterRing(A, { id = 'b', name = 'B', order = 60, items = items, fire = fire })
        Bastians:RegisterRing(A, { id = 'a', name = 'A', order = 40, items = items, fire = fire })
        """
    )
    assert [r.id for r in wow.eval("Bastians:GetRings()").values()] == ["a", "b"]
    wow.execute("Bastians:UnregisterRing(A, 'a')")
    assert [r.id for r in wow.eval("Bastians:GetRings()").values()] == ["b"]
    wow.execute("A:Disable()")
    assert list(wow.eval("Bastians:GetRings()").values()) == []
    assert list(wow.eval("Seen").values()) == ["b+", "a+", "a-", "b-"]
    ok = wow.eval("(pcall(Bastians.RegisterRing, Bastians, A, { id = 'c' }))")
    assert ok is False  # items and fire are required
    assert wow.errors == []
