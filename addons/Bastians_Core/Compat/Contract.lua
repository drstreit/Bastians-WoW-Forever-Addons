-- Compat contract (core-contracts §10, ADR 0010): the wrappers every client must provide, layers, report.
local _, ns = ...
local B = ns.B

local Compat = { Has = {}, client = B.Client }
B.Compat = Compat
ns.Compat = Compat

local layers = {} -- wrapper -> layer that provided the current implementation
local notes = {} -- wrapper -> runtime path taken, e.g. "TooltipDataProcessor" or "script hooks"

-- Every wrapper with its normalized shape. Apps see only these; they never check the client.
Compat.CONTRACT = {
  GetAddOnInfo = "name -> { name, title, notes, loadable, reason, loaded, loadOnDemand } or nil",
  IsAddOnEnabled = "name -> bool ; installed and switched on for this character in the AddOns list"
    .. " (true when the client cannot tell)",
  LoadAddOn = "name[, onLoaded(name)] -> 'loaded' | 'deferred' | 'missing' | 'failed', reason",
  GetQuestLogEntries = "-> array of { index, questID, title, level, header, isComplete, readyForTurnIn,"
    .. " objectives = { { text, kind, finished, fulfilled, required } } }",
  GetCompletedQuestIDs = "-> array of questIDs, possibly empty",
  IsQuestCompleted = "questID -> bool",
  GetQuestItem = "questLogIndex -> { itemID, link, icon, charges, showWhenComplete, inBags } or nil",
  GetQuestText = "questID -> details, objectives (strings, client language) or nil",
  GetWatchedQuestIDs = "-> array of questIDs on the objective tracker, possibly empty",
  SetQuestWatched = "questID, on -> bool (changed)",
  GetPlayerFacts = "-> { level, raceID, classID, faction ('Alliance' | 'Horde' | 'Neutral'), class (the"
    .. " file token, 'WARRIOR'), race (the file token, 'Human'), health (0..1 or nil) }",
  IsInGroup = "-> bool (party or raid)",
  GetItemCount = "itemID -> number of that item in the bags (0 when none)",
  GetBagItems = "-> array of { bag, slot, itemID, count, quality, bound, noValue, icon, link } for every"
    .. " filled slot of the equipped bags, possibly empty",
  GetMoney = "-> copper the character carries",
  GetPlayerXP = "-> xp, xpMax, level of the character (nil, nil, level when the client has no XP bar)",
  GetFontFiles = "-> { [path] = true } of the font files the client's font objects use",
  GetPlayerFacing = "-> radians, or nil when unknown (instances, a secret value)",
  OpenChat = "text -> nil ; puts the text into the chat input for the player to send or edit",
  GetProfessions = "-> { [name] = rank } of the known professions, or nil when the client cannot tell",
  GetReputation = "factionID -> { name, standing (1 Hated .. 8 Exalted), value } or nil when unknown",
  GetHearthstone = "-> { bindName, hasStone, ready, remaining (seconds) } ; the bind location name and the"
    .. " cooldown of the Hearthstone (item 6948); remaining is 0 when ready",
  GetMoveSpeed = "-> yards per second the player moves right now (nil while the client keeps it"
    .. " secret), mounted (bool), onTaxi (bool)",
  GetDeathState = "-> 'alive' | 'dead' (the body, not released) | 'ghost' (released) of the player",
  GetTeleportState = "kind ('spell' | 'item' | 'toy'), id, reagent itemID or nil -> owned, ready,"
    .. " remaining ; owned nil when the client cannot tell, ready nil when the cooldown is unknown,"
    .. " ready false without the reagent (R26.7)",
  GetItemSpell = "itemID -> the spellID its use casts, or nil",
  GroupChannel = "-> 'RAID' | 'PARTY' | nil ; the addon message channel of the character's group",
  InGuild = "-> bool ; the character is in a guild",
  ServerTime = "-> the realm's time in seconds (GetServerTime), else the computer's",
  MaxLevel = "-> the level cap of the character's game, or nil",
  Friends = "-> { { name, online, area, level } } the character's friends list (C_FriendList), maybe empty",
  GroupUnits = "-> array of { unit, name } of the other members of the group (raid or party), possibly"
    .. " empty",
  RegisterAddonPrefix = "prefix -> bool ; the prefix may be used for addon messages (registered or"
    .. " already registered), false without the addon message API",
  SendAddonMessage = "prefix, text, channel ('PARTY' | 'RAID' | 'GUILD' | 'WHISPER'), target -> bool"
    .. " (handed to the client)",
  GetCorpsePosition = "-> uiMapID, x, y (map fractions) of the player's corpse, or nil (alive, no"
    .. " answer, or the corpse on no map of the player's map chain)",
  GetTaxiNodes = "-> array of { id (nil on the legacy path), name, map (uiMapID), x, y (map fractions),"
    .. " state = 'current' | 'reachable' | 'unreachable' } ; empty when no taxi map is open",
  GetItemInfo = "itemID or link -> { id, name, link, quality, level, minLevel, class, subclass, stack,"
    .. " equipLoc, icon, sellPrice, classID, subclassID } or nil (nil also while the item is not cached)",
  RequestItemData = "itemID -> bool (asked) ; asks the client to load the item, ITEM_DATA_LOAD_RESULT"
    .. " follows",
  GetItemStats = "itemID or link -> { [ITEM_MOD_* key] = amount } (non-zero amounts only) or nil"
    .. " while the item is not cached or no stats API answers",
  GetEquippedItem = "equipLoc -> { slot, id, link, name, level } for the worn item with the lowest"
    .. " level among the slots the location takes, { slot } alone when that slot is empty, nil for a"
    .. " location that is not equippable",
  GetQuestName = "questID -> name or nil (nil also while the client has not loaded the quest)",
  RequestQuestData = "questID -> bool (asked) ; asks the client to load the quest, QUEST_DATA_LOAD_RESULT"
    .. " follows",
  GetUnitNameByID = "npcID -> name or nil (a creature the client has not seen yet, or no tooltip API)",
  TargetEntity = "-> 'npc:<id>' | 'object:<id>' or nil ; the target's entity from UnitGUID('target'):"
    .. " Creature and Vehicle are npcs, GameObject objects; players, pets and no target give nil",
  SetObjectiveTrackerShown = "on -> bool (done) ; shows or hides the game's objective tracker"
    .. " (ObjectiveTrackerFrame on retail; the Forever frame is verified at launch); false in"
    .. " combat lockdown or without the frame, nothing touched then",
  GetQuestWaypoint = "questID, uiMapID -> x, y (map fractions) or nil ; the client's next step of a"
    .. " log quest on that map (C_QuestLog.GetNextWaypointForMap), nil without one",
  GetQuestsOnMap = "uiMapID -> array of { questID, x, y } (map fractions), possibly empty ; the"
    .. " client's quest POIs of the map (C_QuestLog.GetQuestsOnMap), empty without the API",
  GetNumMerchantItems = "-> number",
  GetMerchantItem = "index -> { index, itemID, link, name, icon, price (copper for `stack` units), stack,"
    .. " numAvailable (-1 = unlimited), isPurchasable, isUsable, hasExtendedCost, currencyID, spellID }"
    .. " or nil",
  GetNumTrainerServices = "-> number",
  GetTrainerService = "index -> { index, name, kind, icon, subtext, cost (copper), skillReq = { name, rank },"
    .. " levelReq, itemID, spellID, expanded (headers, retail order only) } or nil ;"
    .. " kind is 'available' | 'unavailable' | 'used' | 'header'",
  SetTrainerFilter = "kind, on -> nil ; kind is 'available' | 'unavailable' | 'used'",
  GetTrainerFilter = "kind -> bool, or nil when the client has no filter API",
  IsTradeskillTrainer = "-> bool, or nil when unknown",
  RegisterSettingsCategory = "frame, name[, parentCategory] -> category or nil",
  OpenSettings = "category -> nil",
  HookTooltip = "kind, fn(tooltip, info) -> nil ; kind 'unit' | 'item' | 'spell' | 'object' ;"
    .. " info = { kind, id, guid, link }",
  MapPosToWorld = "uiMapID, x, y (fractions) -> continent, wx, wy or nil",
  AddMask = "texture, path or nil -> mask or nil ; masks the texture with the alpha of the texture at"
    .. " path (clamped), nil clears it; nil also when the client has no mask textures",
  SetTransformTable = "table -> nil ; fallback per-uiMapID affine transforms supplied by Data",
  -- 3D portraits
  GetSpellName = "spellID -> name or nil ; a recipe's name on retail, whose packs carry none",
  NewModel = "parent -> a PlayerModel frame (DressUpModel where the client has no PlayerModel) or nil",
  ShowCreature = "model, npcID -> bool ; the creature's 3D model, false when the client cannot",
  ShowItem = "model, itemID -> bool ; the item's own 3D model (weapons, shields, held things, helms,"
    .. " shoulders), false when it has none or the client cannot",
  ZoomModel = "model, scale -> nil ; the camera's distance (1 the default, smaller is closer)",
  Animate = "model, animID -> bool ; plays a model animation (SetAnimation; the emote ids are assumed,"
    .. " ADR 0034)",
  HasAnimation = "model, animID -> bool, or nil when the client cannot tell (Model:HasAnimation)",
  NewBackdrop = "parent -> a frame that answers SetBackdrop (BackdropTemplate) or nil (ADR 0034)",
  ItemIcon = "itemID -> the icon (file id or path) from the client's item table, or nil for an item"
    .. " the client does not have",
  ItemQuality = "itemID -> quality (0 poor .. 7) or nil while the client does not know the item",
  QualityColor = "quality -> r, g, b of the game's quality colour, or nil",
  -- the fact layer (library.md §4, ADR 0028)
  UnitFacts = "unit -> { unit, ref, guid, name, alive, level, health (0..1), reaction (1 hostile .. 8),"
    .. " targetsPlayer, within (yards 10 | 28, nil farther or unknown) } or nil when the unit does not"
    .. " exist or is a player",
  PlayerState = "-> { combat, stealthed, swimming, submerged, falling, flying, mounted, onTaxi, resting,"
    .. " indoors } (false where the client cannot tell)",
  PlayerAuras = "-> { [spellID] = name } of the player's helpful auras, possibly empty",
  LootSlots = "-> array of { slot, item ('item:<id>'), count, from (entity or nil) }, fishing (bool) ;"
    .. " empty without a loot window",
  ItemText = "-> { item, text, page } of the readable text open (a book, a plaque, a letter), or nil",
  Emote = "token[, target] -> bool (done) ; performs the emote (DoEmote); false without the API or in"
    .. " combat lockdown",
  TakeScreenshot = "-> bool (asked) ; Screenshot()",
  EquippedItems = "-> { [itemID] = slot } of what the character wears, possibly empty",
  IsPvPFlagged = "-> bool ; the character's PvP flag (UnitIsPVP)",
  InstanceType = "-> 'none' | 'pvp' | 'arena' | 'party' | 'raid' | 'scenario' (IsInInstance's second value)",
  HookItemUse = "fn(itemID) -> bool (hooked) ; fn after the character uses an item from the bags",
  AreaName = "areaID -> the area's name (C_Map.GetAreaInfo) or nil",
  MapName = "uiMapID -> the map's name in the client's language (C_Map.GetMapInfo) or nil",
  PlayKit = "soundKitID -> nil ; plays one of the client's sounds (PlaySound)",
  PlayFile = "path, channel -> handle or nil ; plays a sound file (PlaySoundFile); nil when it will not",
  StopFile = "handle -> nil ; stops a sound PlayFile started",
  Speak = "text -> bool ; the client's text-to-speech reads the text aloud (C_VoiceChat.SpeakText, the"
    .. " first voice; assumed, library.md 10.3); false when the client has none",
  StopSpeaking = "-> nil ; stops what Speak reads",
  PickColor = "r, g, b, onChange(r, g, b) -> bool (shown) ; the game's colour picker: every change"
    .. " and a cancel (the old colour) go to onChange; false without it",
  CombatEvent = "-> { subevent, sourceGUID, sourceName, destGUID, destName, spellID, amount } of the"
    .. " current combat log event, or nil",
}

-- Layers call define(layer, name, fn); a later layer replaces an earlier one (Shared < Modern < client).
function ns.Compat.define(layer, name, fn)
  if not Compat.CONTRACT[name] then
    error(
      ("Compat: %s is not in the contract, add it to Compat/Contract.lua first"):format(tostring(name)),
      2
    )
  end
  Compat[name] = fn
  layers[name] = layer
end

function ns.Compat.note(name, text)
  notes[name] = text
end

-- Bastians.Compat.Report() -> { client, Has = {...}, [wrapper] = { layer, note } } for /bastians debug.
function Compat.Report()
  local out = { client = Compat.client, Has = {} }
  for name in pairs(Compat.CONTRACT) do
    out[name] = { layer = layers[name] or "MISSING", note = notes[name] }
  end
  for k, v in pairs(Compat.Has) do
    out.Has[k] = v
  end
  return out
end

-- Called by Core once all layers are loaded: every contract entry must have an implementation.
function ns.Compat.verify()
  local missing = {}
  for name in pairs(Compat.CONTRACT) do
    if type(Compat[name]) ~= "function" then
      missing[#missing + 1] = name
    end
  end
  table.sort(missing)
  if #missing > 0 then
    B:Log(nil, "error", "Compat: no implementation for %s", table.concat(missing, ", "))
  end
  return missing
end
