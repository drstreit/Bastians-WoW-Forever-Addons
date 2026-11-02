-- The camp ring of Bastian's Campfire (campfire.md "The camp ring", decision F): a ring of eight
-- wedges registered with Core's ring registry while the app and its ring setting are on; Bastian's
-- Gestures shows it after its own three. Offer a feature uses the camp item through the ring kit's
-- secure button (set out of combat only); everything else is the player's own emote or line.
local _, ns = ...
local B = Bastians
local L = ns.L
local Camp = ns.Camp

local CampRing = {}
ns.CampRing = CampRing

CampRing.ID = "campfire.camp"

local mod

-- One chat line (SendChatMessage; the retail family's call, assumed on Forever).
local function say(text, channel)
  local send = rawget(_G, "SendChatMessage")
  if type(send) ~= "function" or text == "" then
    return false
  end
  send(text, channel or "SAY")
  return true
end

local function inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

local function zone()
  local text = type(GetZoneText) == "function" and GetZoneText() or nil
  return type(text) == "string" and text ~= "" and text or nil
end

-- The unit whose camp warmed the player, read now from the camp auras' source (never stored).
local function hostUnit()
  for _, a in ipairs(B.Compat.UnitAuras("player")) do
    if
      Camp.BY_AURA[a.spellId]
      and type(a.source) == "string"
      and a.source ~= "player"
      and UnitExists(a.source)
    then
      return a.source
    end
  end
  return nil
end

-- The feature the player would offer: the first carried one the camp lacks.
function CampRing.Offer()
  local card = ns.Watch.Card()
  return card.could[1]
end

local WEDGES = {
  { id = "sit", label = "Sit", kind = "invite" },
  { id = "warm", label = "Warm your hands", kind = "service" },
  { id = "offer", label = "Offer a feature", kind = "campfire" },
  { id = "invite", label = "Invite to camp", kind = "service" },
  { id = "thank", label = "Thank the host", kind = "invite" },
  { id = "story", label = "The place's story", kind = "voice" },
  { id = "share", label = "Share the fire", kind = "spot" },
  { id = "bow", label = "Bow", kind = "invite" },
}
CampRing.WEDGES = WEDGES

-- The ring kit's items: each wedge with its word, its tile, and why it cannot fire now.
function CampRing.Items()
  local items = {}
  for i, w in ipairs(WEDGES) do
    local item = { id = w.id, label = L[w.label], kind = w.kind }
    if w.id == "offer" then
      local feature = CampRing.Offer()
      if not feature then
        item.disabled, item.tip = true, L["No camp item in your bags that this camp lacks."]
      elseif inCombat() then
        item.disabled, item.tip = true, L["Not in combat."]
      else
        item.label = L[feature.name]
        item.tip = L["Click to place it (the camp item is used)."]
        item.secure = { type = "item", item = "item:" .. feature.item }
      end
    elseif w.id == "story" and not B:GetAction("voice.play") then
      item.disabled, item.tip = true, L["Needs Bastian's Orbiter"]
    elseif w.id == "share" and not mod.db.profile.beacon then
      item.disabled, item.tip = true, L["The beacon is off on the Campfire page."]
    elseif w.id == "thank" then
      item.tip = L["/thank at the one whose camp warmed you (or your target)."]
    end
    items[i] = item
  end
  return items
end

-- Fires a wedge (the ring host closed the ring already). -> whether something happened.
function CampRing.Fire(_, item)
  local id = item and item.id
  local target = UnitExists("target") and "target" or nil
  if id == "sit" then
    return B.Compat.Emote("SIT")
  elseif id == "warm" then
    return say(L["warms their hands by the fire."], "EMOTE")
  elseif id == "invite" then
    local where = zone()
    local text = where and string.format(L["A fire burns here in %s; come and sit with us."], where)
      or L["A fire burns here; come and sit with us."]
    return say(text, "SAY")
  elseif id == "thank" then
    return B.Compat.Emote("THANK", hostUnit() or target)
  elseif id == "story" then
    local map = C_Map.GetBestMapForUnit("player")
    return map and B:RunAction("voice.play", "zone:" .. map, { source = "campfire" }) or false
  elseif id == "share" then
    return ns.Beacon.Share() ~= nil
  elseif id == "bow" then
    return B.Compat.Emote("BOW", target)
  end
  return false
end

-- After the secure wedge's click (the item was used): the card reads the camp again.
function CampRing.Secure()
  B:Fire("BASTIANS_CAMP_CHANGED")
end

-- Registers or removes the ring with the setting.
function CampRing.Apply()
  if mod:IsEnabled() and mod.db.profile.ring then
    B:RegisterRing(mod, {
      id = CampRing.ID,
      name = L["Camp"],
      order = 50,
      items = CampRing.Items,
      fire = CampRing.Fire,
      secure = CampRing.Secure,
    })
  else
    B:UnregisterRing(mod, CampRing.ID)
  end
end

function CampRing.Attach(m)
  mod = m
  CampRing.Apply()
end

-- The model's words for the wedges (tests): the ids in order.
function CampRing.Ids()
  local out = {}
  for _, w in ipairs(WEDGES) do
    out[#out + 1] = w.id
  end
  return out
end
