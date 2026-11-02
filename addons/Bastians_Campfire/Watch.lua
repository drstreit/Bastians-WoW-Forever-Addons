-- The camp watch of Bastian's Campfire (campfire.md "The fire card"): reads what the client gives
-- on its events (the player's and the group's auras, the bags, the player's own casts), never by
-- polling, and turns it into the card's state, the warmth's words and the features' ready word.
-- No name of another player is kept: a host's name is read live from the aura's source unit.
local _, ns = ...
local B = Bastians
local L = ns.L
local Camp = ns.Camp
local Model = ns.Model

local Watch = {}
ns.Watch = Watch

local mod
local st -- the live state (RAM only)
local fadeTimer, readyTimer

local function now()
  return GetTime()
end

local function reset()
  st = {
    nearby = false,
    resting = nil,
    buffs = {},
    features = {},
    seen = nil,
    since = nil,
    warm = false,
    carried = {},
  }
end
reset()

local function cancel(t)
  if t then
    t:Cancel()
  end
end

local GROUP = { "party1", "party2", "party3", "party4" }

-- The benefits the group's members carry from a camp (their auras are readable in a group: C5).
local function groupBenefits(into)
  for _, unit in ipairs(GROUP) do
    if UnitExists(unit) then
      for _, a in ipairs(B.Compat.UnitAuras(unit)) do
        local key = Camp.BY_AURA[a.spellId]
        if key then
          into[key] = true
        end
      end
    end
  end
end

-- How many of the group carry a camp aura now (the camp log counts, never names).
local function groupAtCamp()
  local n = 0
  for _, unit in ipairs(GROUP) do
    if UnitExists(unit) then
      for _, a in ipairs(B.Compat.UnitAuras(unit)) do
        if Camp.BY_AURA[a.spellId] then
          n = n + 1
          break
        end
      end
    end
  end
  return n
end

-- The live name of a source unit (shown, never stored).
local function hostName(unit)
  if type(unit) ~= "string" or unit == "player" or not UnitExists(unit) then
    return nil
  end
  local name = UnitName(unit)
  return type(name) == "string" and name ~= "" and name or nil
end

function Watch.State()
  return st
end

-- The card's input from the live state.
function Watch.Input()
  local features = {}
  for key in pairs(st.features) do
    features[#features + 1] = key
  end
  table.sort(features)
  return {
    now = now(),
    nearby = st.nearby,
    resting = st.resting,
    buffs = st.buffs,
    seen = st.seen,
    carried = st.carried,
    features = features,
  }
end

function Watch.Card()
  return Model.Card(Watch.Input())
end

local function tell(text)
  if mod.db.profile.words then
    B:Tell(mod, "reminder", text)
  end
end

local function scheduleFading()
  cancel(fadeTimer)
  fadeTimer = nil
  local card = Watch.Card()
  if not card.left then
    return
  end
  local wait = card.left - Camp.FADING_SECONDS
  local function fading()
    fadeTimer = nil
    local left = Watch.Card().left
    if st.warm and left then
      tell(L["The fire's warmth is fading."])
      B:Fire("BASTIANS_CAMP_FADING", math.floor(left))
    end
  end
  if wait <= 0 then
    return -- already within the last minutes when it landed: no second word
  end
  fadeTimer = C_Timer.NewTimer(wait, fading)
end

local function logCamp()
  local log = mod.db.char.log
  local map = C_Map.GetBestMapForUnit("player")
  local info = map and C_Map.GetMapInfo(map)
  table.insert(log, 1, { zone = info and info.name or nil, day = date("%Y-%m-%d"), others = groupAtCamp() })
  while #log > 20 do
    table.remove(log)
  end
end

-- Reads the player's auras (UNIT_AURA on the player, at enable): the fire nearby, the rest, the
-- camp buffs; then the transitions: warm (a word and BASTIANS_CAMP_WARMED), cold again.
function Watch.Read()
  local nearby, resting, buffs, host = false, nil, {}, nil
  local landed = false
  for _, a in ipairs(B.Compat.UnitAuras("player")) do
    if a.spellId == Camp.NEARBY then
      nearby = true
    elseif Camp.RESTING[a.spellId] then
      resting = a.expires or true
    else
      local key = Camp.BY_AURA[a.spellId]
      if key then
        buffs[key] = a.expires or true
        host = host or a.source
        if not st.buffs[key] then
          landed = true
        end
      end
    end
  end
  local features = {}
  for key in pairs(buffs) do
    features[key] = true
  end
  groupBenefits(features)
  local changed = nearby ~= st.nearby
    or (resting ~= nil) ~= (st.resting ~= nil)
    or landed
    or next(buffs) == nil and next(st.buffs) ~= nil
  if (nearby or resting) and not st.since then
    st.since = now() -- the beacon's age: since the player first saw this fire
  elseif not (nearby or resting or next(buffs)) then
    st.since = nil
  end
  st.nearby, st.resting, st.buffs, st.features = nearby, resting, buffs, features
  if nearby or resting or landed then
    st.seen = now()
  end
  if next(buffs) and not st.warm then
    st.warm = true
    local who = hostName(host)
    tell(L["You are warm."])
    logCamp()
    B:Fire("BASTIANS_CAMP_WARMED", who)
    scheduleFading()
  elseif next(buffs) and landed then
    scheduleFading() -- another buff: the earliest end may have moved
  elseif not next(buffs) and st.warm then
    st.warm = false
    cancel(fadeTimer)
    fadeTimer = nil
  end
  if changed then
    B:Fire("BASTIANS_CAMP_CHANGED")
  end
end

-- The camp items in the bags (BAG_UPDATE_DELAYED, coalesced; at enable).
function Watch.Bags()
  local carried = {}
  for _, feature in ipairs(Camp.FEATURES) do
    if B.Compat.GetItemCount(feature.item) > 0 then
      carried[#carried + 1] = feature
    end
  end
  for _, kit in ipairs(Camp.KITS) do
    if B.Compat.GetItemCount(kit.item) > 0 then
      carried[#carried + 1] = kit
    end
  end
  st.carried = carried
  B:Fire("BASTIANS_CAMP_CHANGED")
end

-- The features' ready word: at the end of the item's cooldown (the client's number, probe C3);
-- without a number no word (never a guessed hour).
local function scheduleReady()
  cancel(readyTimer)
  readyTimer = nil
  local at = mod.db.char.readyAt
  if type(at) ~= "number" then
    return
  end
  local wait = at - time()
  if wait <= 0 then
    mod.db.char.readyAt = nil
    return
  end
  readyTimer = C_Timer.NewTimer(wait, function()
    readyTimer = nil
    mod.db.char.readyAt = nil
    tell(L["Your camp features are ready again."])
    B:Fire("BASTIANS_CAMP_CHANGED")
  end)
end

-- Seconds until the player's features can be placed again, or nil when unknown.
function Watch.ReadyIn()
  local at = mod.db.char.readyAt
  return type(at) == "number" and math.max(0, at - time()) or nil
end

-- UNIT_SPELLCAST_SUCCEEDED on the player with a placement spell (probe C2): the feature's
-- cooldown read a moment later (the client sets it after the cast).
function Watch.OnCast(_, _, unit, _, spellID)
  local feature = unit == "player" and Camp.BY_SPELL[spellID]
  if not feature then
    return
  end
  local map = C_Map.GetBestMapForUnit("player")
  mod.db.char.placed = { item = feature.item, map = map, at = time() }
  C_Timer.After(0.5, function()
    local left = B.Compat.ItemCooldown(feature.item)
    if left and left > 1.5 then
      mod.db.char.readyAt = time() + math.floor(left + 0.5)
      scheduleReady()
    end
    B:Fire("BASTIANS_CAMP_CHANGED")
  end)
end

function Watch.Attach(m)
  mod = m
  reset()
  m:RegisterEvent("UNIT_AURA", function(_, _, unit)
    if unit == "player" then
      Watch.Read()
    elseif unit and unit:match("^party%d$") then
      m:Coalesce("campfire-group", 0.5, Watch.Read)
    end
  end)
  m:RegisterEvent("GROUP_ROSTER_UPDATE", function()
    m:Coalesce("campfire-group", 0.5, Watch.Read)
  end)
  m:RegisterEvent("BAG_UPDATE_DELAYED", function()
    m:Coalesce("campfire-bags", 0.3, Watch.Bags)
  end)
  m:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", Watch.OnCast)
  Watch.Bags()
  Watch.Read()
  scheduleReady()
end

function Watch.Detach()
  cancel(fadeTimer)
  cancel(readyTimer)
  fadeTimer, readyTimer = nil, nil
  reset()
end
