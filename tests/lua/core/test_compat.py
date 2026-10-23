"""Compat layers (B2.4): one normalized shape per wrapper on both clients, differences inside."""

from harness import WowRuntime


def report(core: WowRuntime) -> dict:
    return core.eval("Bastians.Compat.Report()")


def test_every_contract_entry_is_implemented(core: WowRuntime):
    rep = report(core)
    missing = [
        name
        for name, entry in rep.items()
        if name not in ("client", "Has") and entry.layer == "MISSING"
    ]
    assert missing == []
    assert rep.client == core.client
    assert not [line for line in core.eval("Bastians:GetLog()").values() if line.level == "error"]


def test_client_overrides_land_in_their_layer(core: WowRuntime):
    rep = report(core)
    expected = "forever" if core.client == "forever" else "modern"
    assert rep.SetTrainerFilter.layer == expected
    assert rep.GetTrainerService.layer == expected
    assert rep.GetItemInfo.layer == "shared"
    assert rep.GetQuestLogEntries.layer == "modern"


def test_capability_flags(core: WowRuntime):
    has = report(core).Has
    assert has.SettingsAPI is True
    assert has.TooltipDataProcessor is True
    assert has.ModernQuestLog is True
    assert has.ReplicateAH is True  # documented on both clients
    assert has.TrainerType is (core.client == "forever")


def test_quest_log_is_normalized(core: WowRuntime):
    entries = core.eval("Bastians.Compat.GetQuestLogEntries()")
    assert len(entries) == 2
    first = entries[1]
    assert (first.questID, first.title, first.level, first.header) == (
        176,
        "The Fargodeep Mine",
        7,
        "Elwynn Forest",
    )
    assert first.isComplete is False and first.readyForTurnIn is False
    objective = first.objectives[1]
    assert (
        objective.text,
        objective.kind,
        objective.finished,
        objective.fulfilled,
        objective.required,
    ) == ("Explore the Fargodeep Mine", "event", False, 0, 1)
    assert entries[2].isComplete is True
    assert list(core.eval("Bastians.Compat.GetCompletedQuestIDs()").values()) == [783, 7, 18]
    assert core.eval("Bastians.Compat.IsQuestCompleted(7)") is True
    assert core.eval("Bastians.Compat.IsQuestCompleted(8)") is False


def test_item_info(core: WowRuntime):
    item = core.eval("Bastians.Compat.GetItemInfo(2589)")
    assert (item.id, item.name, item.sellPrice, item.stack) == (2589, "Linen Cloth", 13, 20)
    assert core.eval("Bastians.Compat.GetItemInfo('item:2589::::::::1:::::')").id == 2589
    assert core.eval("Bastians.Compat.GetItemInfo(999999)") is None


def test_merchant_item(core: WowRuntime):
    assert core.eval("Bastians.Compat.GetNumMerchantItems()") == 1
    offer = core.eval("Bastians.Compat.GetMerchantItem(1)")
    assert (offer.itemID, offer.name, offer.price, offer.stack, offer.numAvailable) == (
        2589,
        "Linen Cloth",
        260,
        20,
        -1,
    )
    assert offer.isPurchasable is True and offer.hasExtendedCost is False
    assert core.eval("Bastians.Compat.GetMerchantItem(2)") is None


def test_trainer_service_has_the_same_shape_on_both_clients(core: WowRuntime):
    assert core.eval("Bastians.Compat.GetNumTrainerServices()") == 2
    first = core.eval("Bastians.Compat.GetTrainerService(1)")
    assert (first.name, first.kind, first.cost, first.levelReq) == (
        "Fireball",
        "available",
        1200,
        6,
    )
    assert first.skillReq is None
    second = core.eval("Bastians.Compat.GetTrainerService(2)")
    assert second.kind == "unavailable" and dict(second.skillReq.items()) == {
        "name": "Frost",
        "rank": 1,
    }
    if core.client == "forever":
        assert first.icon == 135812 and first.subtext is None
    else:
        assert first.subtext == "Rank 2" and first.icon is None
    assert core.eval("Bastians.Compat.GetTrainerService(3)") is None


def test_trainer_filter_uses_the_form_the_client_accepts(core: WowRuntime):
    core.execute("Bastians.Compat.SetTrainerFilter('available', true)")
    core.execute("Bastians.Compat.SetTrainerFilter('used', false)")
    calls = [(c.kind, c.on) for c in core.g.Mock.trainerFilterCalls.values()]
    if core.client == "forever":
        assert calls == [("available", True), ("used", False)]
    else:
        assert calls == [("available", 1), ("used", 0)]
    assert core.errors == []


def test_load_addon_defers_in_combat(core: WowRuntime):
    core.execute("loadedNames = {}")
    core.execute("onLoaded = function(name) loadedNames[#loadedNames + 1] = name end")
    core.set_combat(True)
    assert core.eval("Bastians.Compat.LoadAddOn('Bastians_Route', onLoaded)") == "deferred"
    assert core.loaded == ["Bastians_Core"]
    core.set_combat(False)
    assert core.loaded == ["Bastians_Core", "Bastians_Route"]
    assert list(core.g.loadedNames.values()) == ["Bastians_Route"]
    assert core.eval("Bastians.Compat.LoadAddOn('Bastians_Route')") == "loaded"
    assert core.eval("Bastians.Compat.LoadAddOn('Bastians_Nope')") == ("missing", "MISSING")


def test_addon_info(core: WowRuntime):
    info = core.eval("Bastians.Compat.GetAddOnInfo('Bastians_Route')")
    assert info.name == "Bastians_Route" and info.loaded is False and info.loadOnDemand is True
    assert core.eval("Bastians.Compat.GetAddOnInfo('Bastians_Core')").loaded is True
    assert core.eval("Bastians.Compat.GetAddOnInfo('Nope')") is None


def test_hook_tooltip_delivers_normalized_info(core: WowRuntime):
    core.execute(
        """
        seen = {}
        Bastians.Compat.HookTooltip("item", function(tt, info) seen[#seen + 1] = info end)
        Bastians.Compat.HookTooltip("item", function(tt, info) seen[#seen + 1] = "second" end)
        Bastians.Compat.HookTooltip("unit", function(tt, info) seen[#seen + 1] = info end)
        """
    )
    core.tooltip("Item", 2589)
    core.tooltip("Unit", 448)
    seen = list(core.g.seen.values())
    assert len(seen) == 3
    assert (seen[0].kind, seen[0].id) == ("item", 2589)
    assert seen[1] == "second"
    assert (seen[2].kind, seen[2].id) == ("unit", 448)  # parsed from the GUID
    assert report(core).HookTooltip.note == "TooltipDataProcessor"


def test_settings_category_registration(core: WowRuntime):
    core.execute(
        """
        local panel = CreateFrame("Frame")
        cat = Bastians.Compat.RegisterSettingsCategory(panel, "Bastians")
        sub = Bastians.Compat.RegisterSettingsCategory(CreateFrame("Frame"), "Quests", cat)
        Bastians.Compat.OpenSettings(sub)
        """
    )
    assert core.eval("cat.registered") is True
    assert core.eval("sub.parent == cat") is True
    assert core.eval("Mock.settingsOpened") == core.eval("sub:GetID()")


def test_map_pos_to_world_uses_the_api_then_the_table(core: WowRuntime):
    assert core.eval("Bastians.Compat.MapPosToWorld(1429, 0.25, 0.5)") == (0, 0, 100)
    assert core.eval("Bastians.Compat.MapPosToWorld(999, 0.5, 0.5)") is None
    core.execute("Bastians.Compat.SetTransformTable({ [999] = { 1, 10, 2, 0, 20, 0, 3 } })")
    assert core.eval("Bastians.Compat.MapPosToWorld(999, 0.5, 0.5)") == (1, 11, 21.5)
    assert report(core).MapPosToWorld.note == "transform table"
    assert core.eval("Bastians.Compat.MapPosToWorld(1429, 0, 0)") == (0, 200, 200)
    assert report(core).MapPosToWorld.note == "C_Map.GetWorldPosFromMapPos"


def test_report_covers_the_whole_contract_and_nothing_else(core: WowRuntime):
    contract = set(core.eval("Bastians.Compat.CONTRACT").keys())
    rep = report(core)
    assert set(rep.keys()) - {"client", "Has"} == contract
    assert all(callable(core.eval(f"Bastians.Compat.{name}")) for name in contract)


def test_add_mask_masks_a_texture_and_clears_it(core: WowRuntime):
    """Compat.AddMask (22.10.2026): the Map masks the sea out of native coast tiles."""
    core.execute(
        """
        maskHost = CreateFrame("Frame", nil, UIParent)
        maskTex = maskHost:CreateTexture(nil, "BACKGROUND")
        """
    )
    assert core.eval("Bastians.Compat.Has.MaskTexture") is True
    assert core.eval("Bastians.Compat.AddMask(maskTex, 'A/mask') ~= nil") is True
    assert core.eval("maskTex:GetNumMaskTextures()") == 1
    assert core.eval("maskTex.bastiansMask:GetTexture()") == "A/mask"
    core.execute("Bastians.Compat.AddMask(maskTex, 'A/other')")  # another mask: the same object
    assert core.eval("maskTex:GetNumMaskTextures()") == 1
    assert core.eval("maskTex.bastiansMask:GetTexture()") == "A/other"
    assert core.eval("Bastians.Compat.AddMask(maskTex, nil)") is None
    assert core.eval("maskTex:GetNumMaskTextures()") == 0
    assert core.eval("maskTex.bastiansMask:IsShown()") is False
    assert core.eval("Bastians.Compat.AddMask({}, 'x')") is None  # not a texture
    # a mask file the client does not load (GetTexture answers nil) is never applied: it would hide
    # the whole tile (Forever 22.10.2026, /bprobe mask)
    core.execute(
        "Bastians.Compat.AddMask(maskTex, 'A/mask'); "
        "maskTex.bastiansMask.GetTexture = function() return nil end"
    )
    assert core.eval("Bastians.Compat.AddMask(maskTex, 'A/broken')") is None
    assert core.eval("maskTex:GetNumMaskTextures()") == 0
    assert core.errors == []


def test_item_stats_and_the_equipped_item(core: WowRuntime):
    """Compat.GetItemStats and GetEquippedItem (S7, the reward comparison): the stats table with
    zero amounts dropped, nil for an uncached item; the worn item with the lowest level among the
    slots an equip location takes, the empty slot alone, nil for a location that is not worn."""
    core.execute(
        """
        Mock.items[1185] = { name = "Blood Saber", quality = 2, level = 7, equipLoc = "INVTYPE_WEAPON",
          sell = 200, stack = 1, icon = 1,
          stats = { ITEM_MOD_STRENGTH_SHORT = 3, ITEM_MOD_SPIRIT_SHORT = 0 } }
        Mock.items[2092] = { name = "Worn Dagger", quality = 1, level = 3, equipLoc = "INVTYPE_WEAPON",
          sell = 10, stack = 1, icon = 1 }
        Mock.items[4001] = { name = "Ring A", quality = 1, level = 9, equipLoc = "INVTYPE_FINGER",
          sell = 1, stack = 1, icon = 1 }
        Mock.items[4002] = { name = "Ring B", quality = 1, level = 4, equipLoc = "INVTYPE_FINGER",
          sell = 1, stack = 1, icon = 1 }
        Mock.equipped = { [16] = 2092, [11] = 4001, [12] = 4002 }
        """
    )
    assert dict(core.eval("Bastians.Compat.GetItemStats(1185)")) == {"ITEM_MOD_STRENGTH_SHORT": 3}
    assert dict(core.eval("Bastians.Compat.GetItemStats('item:1185')")) == {
        "ITEM_MOD_STRENGTH_SHORT": 3
    }
    assert core.eval("Bastians.Compat.GetItemStats(999)") is None
    worn = core.eval("Bastians.Compat.GetEquippedItem('INVTYPE_WEAPON')")
    assert (worn.slot, worn.id, worn.name, worn.level) == (16, 2092, "Worn Dagger", 3)
    assert "item:2092" in worn.link
    ring = core.eval("Bastians.Compat.GetEquippedItem('INVTYPE_FINGER')")
    assert (ring.slot, ring.id, ring.level) == (
        12,
        4002,
        4,
    )  # the lower ring is what an upgrade replaces
    core.execute("Mock.equipped[12] = nil")
    empty = core.eval("Bastians.Compat.GetEquippedItem('INVTYPE_FINGER')")
    assert (empty.slot, empty.id) == (12, None)  # the empty ring slot is the place
    # an empty off hand is no place for a one-hand weapon: the main hand is compared
    worn = core.eval("Bastians.Compat.GetEquippedItem('INVTYPE_WEAPON')")
    assert (worn.slot, worn.id) == (16, 2092)
    shield = core.eval("Bastians.Compat.GetEquippedItem('INVTYPE_SHIELD')")
    assert (shield.slot, shield.id) == (17, None)
    assert core.eval("Bastians.Compat.GetEquippedItem('')") is None
    assert core.eval("Bastians.Compat.GetEquippedItem('INVTYPE_NON_EQUIP')") is None
    assert core.eval("Bastians.Compat.GetEquippedItem(nil)") is None
    rep = report(core)
    assert rep.GetItemStats.layer == "shared" and rep.GetEquippedItem.layer == "shared"
    assert core.errors == []


def test_secret_values_are_unknown_never_compared(core: WowRuntime):
    """Forever 70532: GetUnitSpeed("player") came back as a secret number and
    Route compared it 244 times a session. Compat.Plain turns a secret value into nil; the
    wrappers that read such values answer unknown."""
    core.execute(
        """
        Mock.unitSpeed = Mock.Secret()
        Mock.facing = Mock.Secret()
        Mock.guids = { target = Mock.Secret() }
        """
    )
    assert core.eval("issecretvalue(Mock.unitSpeed)") is True
    assert core.eval("Bastians.Compat.Plain(Mock.unitSpeed)") is None
    assert (
        core.eval("Bastians.Compat.Plain(7)") == 7
        and core.eval("Bastians.Compat.Plain(false)") is False
    )
    speed, mounted, taxi = core.eval("Bastians.Compat.GetMoveSpeed()")
    assert speed is None and mounted is False and taxi is False
    assert core.eval("Bastians.Compat.GetPlayerFacing()") is None
    assert core.eval("Bastians.Compat.TargetEntity()") is None
    # the mock's secret value raises like the client's
    ok, _ = core.eval("pcall(function() return Mock.unitSpeed > 1 end)")
    assert ok is False
    assert core.errors == []
