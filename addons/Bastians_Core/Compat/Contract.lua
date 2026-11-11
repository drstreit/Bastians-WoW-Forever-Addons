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
  AbandonQuest = "questID -> 'asked' | false ; opens the game's own Abandon Quest confirmation for a log"
    .. " quest (its Yes abandons); false when the quest is not in the log or the client lacks the flow",
  GetPlayerFacts = "-> { level, raceID, classID, faction ('Alliance' | 'Horde' | 'Neutral'), class (the"
    .. " file token, 'WARRIOR'), race (the file token, 'Human'), health (0..1 or nil) }",
  IsInGroup = "-> bool (party or raid)",
  GetItemCount = "itemID, includeBank? -> number of that item in the bags, and the bank (0 when none)",
  ItemCooldown = "itemID -> seconds left on the item's cooldown (0 when ready), nil when unknown",
  HasMsp = "-> bool ; whether a roleplay addon (Total RP 3, MyRolePlay) offers the msp protocol",
  MspName = "unit or name -> { name, title, nick } of the player's roleplay profile, or nil (read only)",
  MspRequest = "unit or name -> asked (bool) ; asks for the name fields, at most every 30 s per player",
  GetInboxInvoices = "-> array of { kind ('buyer' | 'seller' | 'seller_temp_invoice'), item (name), bid,"
    .. " consignment, deposit, count, daysLeft } of the inbox's auction house mails; never the other"
    .. " player's name",
  GetBagItems = "-> array of { bag, slot, itemID, count, quality, bound, noValue, icon, link } for every"
    .. " filled slot of the equipped bags, possibly empty",
  GetContainerItems = "bagIDs -> the same rows as GetBagItems for the containers named (the bank's)",
  BankBags = "-> the container ids of the bank the client has (the bank slots, its bags or tabs, the"
    .. " reagent bank), each only while the bank is open readable",
  GetEquippedLinks = "-> { [slot] = link } for the worn items, slots 1 to 19",
  GetInboxItems = "-> rows { itemID, count, link, quality } of every attachment in the mailbox, and"
    .. " the money in it (copper); nil, nil without the mail API",
  MailPrepare = "recipient, subject -> bool ; the mail frame's send tab with both fields set (out of"
    .. " combat, the mail frame open)",
  MailAttach = "bag, slot -> bool ; attaches that stack to the open mail's next free slot",
  MailFreeSlots = "-> how many attachment slots of the mail being written are free, 0 without one",
  GetSendMailItems = "-> { [itemID] = count } attached to the mail being written",
  NewGameWindow = "parent -> the game's PortraitFrameTemplate frame (Bg, CloseButton, SetTitle,"
    .. " SetPortraitToAsset) or nil where the client lacks it",
  NewInset = "parent -> the game's InsetFrameTemplate frame (Bg) or nil",
  GetMoney = "-> copper the character carries",
  GetPlayerXP = "-> xp, xpMax, level of the character (nil, nil, level when the client has no XP bar)",
  GetFontFiles = "-> { [path] = true } of the font files the client's font objects use",
  GetPlayerFacing = "-> radians, or nil when unknown (instances, a secret value)",
  OpenChat = "text -> nil ; puts the text into the chat input for the player to send or edit",
  RegisterCompartment = "{ text, icon, func(button), onEnter(frame), onLeave(frame) } -> bool ; an entry"
    .. " in the Addon Compartment by the minimap (false when the client has none)",
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
  JoinChannel = "name -> the channel's number or nil ; joins a temporary custom channel (not saved in the"
    .. " chat settings) and keeps it out of every chat window",
  LeaveChannel = "name -> bool ; leaves that custom channel",
  ChannelNumber = "name -> the number of that joined channel, or nil",
  SendAddonMessage = "prefix, text, channel ('PARTY' | 'RAID' | 'GUILD' | 'WHISPER' | 'CHANNEL'), target"
    .. " (handed to the client)",
  CreatureTrackingOn = "-> true while a creature-tracking spell is on, false when none is or the"
    .. " class has none, nil when the client cannot say",
  AurasSecret = "-> true while the client hides auras from addons (reading one then raises)",
  ToyUsable = "toy item id -> true | false, nil when the client cannot tell",
  FullName = "unit -> the whole name the game delivers to (Forever: with the surname), or nil",
  ForgetSlash = "'/command' -> bool ; drops the client's cached handler of that command, if it keeps one",
  GetCorpsePosition = "-> uiMapID, x, y (map fractions) of the player's corpse, or nil (alive, no"
    .. " answer, or the corpse on no map of the player's map chain)",
  GetTaxiNodes = "-> array of { id (nil on the legacy path), name, map (uiMapID), x, y (map fractions),"
    .. " state = 'current' | 'reachable' | 'unreachable', slot = the TakeTaxiNode index } in no slot"
    .. " order; empty when no taxi map is open",
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
  ItemTooltipLines = "itemID -> { { left, right, r, g, b } } (the lines of the game's item tooltip,"
    .. " the first its name) or nil (the item not cached yet, or no tooltip API)",
  UnitEntity = "(unit) -> 'npc:<id>' | 'object:<id>' or nil ; a unit token's entity from its GUID",
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
  OpenKeyBindings = "-> opened (boolean)",
  BindingKey = "action -> key or nil",
  HookTooltip = "kind, fn(tooltip, info) -> nil ; kind 'unit' | 'item' | 'spell' | 'object' ;"
    .. " info = { kind, id, guid, link }",
  MapPosToWorld = "uiMapID, x, y (fractions) -> continent, wx, wy or nil",
  AddMask = "texture, path or nil -> mask or nil ; masks the texture with the alpha of the texture at"
    .. " path (clamped), nil clears it; nil also when the client has no mask textures",
  SetTransformTable = "table -> nil ; fallback per-uiMapID affine transforms supplied by Data",
  -- 3D portraits
  GetSpellName = "spellID -> name or nil ; a recipe's name on retail, whose packs carry none",
  IsSpellKnown = "spellID -> bool or nil ; whether this character knows the spell or recipe"
    .. " (C_SpellBook.IsSpellKnown, IsSpellKnown, IsPlayerSpell); nil when the client cannot tell",
  KnownSpells = "-> { [spellID] = true } or nil ; every spell of the character's spell book"
    .. " (C_SpellBook skill lines and items); nil when the client cannot list it",
  OpenRecipes = "-> { [recipeSpellID] = true } or nil ; the learned recipes of the profession window"
    .. " that is open (C_TradeSkillUI.GetAllRecipeIDs, GetRecipeInfo.learned); nil without one",
  NewModel = "parent -> a PlayerModel frame (DressUpModel where the client has no PlayerModel) or nil",
  ShowCreature = "model, npcID -> bool ; the creature's 3D model, false when the client cannot",
  ShowItem = "model, itemID -> bool ; the item's own 3D model (weapons, shields, held things, helms,"
    .. " shoulders), false when it has none or the client cannot",
  ZoomModel = "model, scale -> nil ; the camera's distance (1 the default, smaller is closer)",
  ItemKind = "itemID -> kind, slot ; the client's words (Mail, Chest), nil where it has none, no request",
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
  UnitAuras = "unit -> array of { spellId, name, expires (GetTime clock, nil when the aura does not"
    .. " end or the client keeps it secret), duration, source (unit token or nil) } of the unit's"
    .. " helpful auras, possibly empty (Bastian's Campfire, plan-second-wave.md S5)",
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
  CanSpeak = "-> bool ; the client's text-to-speech (C_VoiceChat.SpeakText) with at least one voice",
  Voices = "-> { { voiceID, name } } ; the voices the client's text-to-speech lists"
    .. " (C_VoiceChat.GetTtsVoices)",
  Speak = "text, voiceID? -> bool ; the client's text-to-speech reads the text aloud (C_VoiceChat.SpeakText)"
    .. " with the rate and volume of the Accessibility settings (C_TTSSettings) and the given voice where"
    .. " the client lists it, else a woman's voice by name, else the first voice; stops what spoke before"
    .. " (assumed, library.md 10.3, voice.md); false without a voice",
  StopSpeaking = "-> nil ; stops what Speak reads",
  PickColor = "r, g, b, onChange(r, g, b) -> bool (shown) ; the game's colour picker: every change"
    .. " and a cancel (the old colour) go to onChange; false without it",
  CombatEvent = "-> { subevent, sourceGUID, sourceName, destGUID, destName, spellID, amount } of the"
    .. " current combat log event, or nil",
  -- Bastian's Helpers (helpers.md): the merchant, the mailbox, quest givers, durability and bags
  MerchantRepair = "-> { canRepair, cost (copper), guild (bool: the guild bank may pay), guildMoney"
    .. " (copper the character may take, nil when unlimited or unknown) } or nil without a merchant",
  RepairAll = "useGuild -> bool (asked) ; repairs every item, from the guild bank when useGuild",
  SellBagItem = "bag, slot -> bool (sold) ; sells the stack to the open merchant; false (nothing done)"
    .. " when no merchant window is shown",
  MerchantBuy = "index, count -> bool (asked) ; buys count units of the merchant's item"
    .. " (a multiple of its stack size)",
  MerchantMaxStack = "index -> the most units one purchase buys, or nil",
  GetBuybackItems = "-> array of { index, itemID, count, price (copper) } of the buyback tab, possibly"
    .. " empty",
  Buyback = "index -> bool (asked) ; buys an item back from the buyback tab",
  GetInboxMail = "-> array of { index, sender, subject, money, cod (copper, 0 without), items (number"
    .. " of attachments) } of the open mailbox, possibly empty",
  TakeInboxMoney = "index -> bool (asked)",
  TakeInboxItems = "index -> bool (asked) ; takes every attachment of the mail into the bags",
  MailRecipient = "name -> bool ; puts the name into the send tab's recipient field (no tab switch)",
  MailRecipientText = "-> the send tab's recipient text, or nil without the mail frame",
  QuestAccept = "-> bool (asked) ; accepts the quest the quest frame offers (an escort's confirmation"
    .. " with QuestAccept('confirm'))",
  QuestProgress = "-> completable (bool), cost (copper the hand-in takes, 0 without) of the open"
    .. " quest frame",
  QuestContinue = "-> bool (asked) ; the progress step's Continue (CompleteQuest)",
  QuestChoices = "-> array of { index, itemID, count } of the reward choices of the open quest frame,"
    .. " possibly empty",
  QuestTakeReward = "index or nil -> bool (asked) ; finishes the quest with that reward choice",
  GetQuestLogRewards = "questID -> { money, xp, items, choices } or nil (not in the log, or the client"
    .. " says nothing) ; copper, experience, { { itemID, count } } ; the log's selection is restored",
  GetOfferRewards = "-> { money, xp, items, choices } or nil ; what the open quest frame offers",
  GreetingQuests = "-> active { { index, title, complete } }, available { { index, title } } of the"
    .. " quest greeting frame",
  NpcEntity = "-> 'npc:<id>' | 'object:<id>' or nil ; the entity of the open gossip or quest window",
  QuestTrivialRange = "-> how many levels below the character a quest may be before the client calls it"
    .. " trivial, or nil when the client does not say",
  CalendarNow = "-> { year, month, day, weekday (1 = Sunday), hour, minute } on the realm's clock, or nil",
  GossipQuests = "-> active { { questID, title, complete } }, available { { questID, title } } of the"
    .. " gossip frame",
  GossipOptions = "-> array of { id, name } of the gossip frame's options, possibly empty",
  NpcSelect = "frame ('gossip' | 'greeting'), kind ('option' | 'active' | 'available'), id -> bool"
    .. " (asked) ; the gossip takes option and quest ids, the greeting list indices",
  PushQuest = "questID -> bool (asked) ; shares a quest of the log with the group when it can be shared",
  QuestDetail = "-> { title, text, objectives, reward, progress } of the open quest frame (the detail's,"
    .. " progress's or hand-in's texts; strings or nil), or nil without a quest frame",
  QuestID = "-> the questID the quest frame shows (GetQuestID), or nil",
  QuestDecline = "-> bool (asked) ; declines the offered quest (DeclineQuest)",
  NpcClose = "-> bool (asked) ; closes the gossip and the quest frame (C_GossipInfo.CloseGossip, CloseQuest)",
  NpcFramesHidden = "hidden -> bool (changed) ; the game's GossipFrame and QuestFrame kept invisible and"
    .. " without mouse while a conversation is shown elsewhere (alpha 0, not re-parented, never in combat"
    .. " the first time), or given back",
  InstanceMap = "-> instance map (Map.db2 id), name ; nil outside a dungeon or raid (GetInstanceInfo)",
  SavedInstances = "-> { { name, instance (Map.db2 id), reset (seconds), locked, raid } } or nil ;"
    .. " the raid info (GetNumSavedInstances, GetSavedInstanceInfo), nil when the client lacks it",
  RequestRaidInfo = "-> bool ; asks the server for the raid info (UPDATE_INSTANCE_INFO follows)",
  GetDurability = "-> lowest (0..1 of the worn item with the least durability), broken (count) ; nil"
    .. " when no worn item has durability",
  BagSpace = "-> free, total of the general slots of the equipped bags",
  ModifierDown = "key ('shift' | 'ctrl' | 'alt') -> bool",
  ChatFrameNamed = "name -> the chat window whose tab carries that name (case ignored), or nil",
  EnableLinks = "frame -> bool: its texts' |H links fire OnHyperlinkEnter, Leave and Click",
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
