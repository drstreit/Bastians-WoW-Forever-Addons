-- The client wrappers Courtesy needs beyond Core's Compat, each assumed on Forever until its row in
-- docs/forever-api.md says otherwise; what the client refuses from a timer is in courtesy.md.
local _, ns = ...

local Compat = {}
ns.Compat = Compat

local function fnOf(name)
  local f = rawget(_G, name)
  return type(f) == "function" and f or nil
end

-- A table the addon may read: not a secret and not locked (canaccesstable, Forever probe 70532;
-- Forever handed UNIT_AURA's aura list over as a secret table, BugGrabber 08.11.2026).
function Compat.Readable(t)
  if type(Bastians.Compat.Plain(t)) ~= "table" then
    return false
  end
  local can = fnOf("canaccesstable")
  return not can or can(t) == true
end

-- The player's helpful auras, what Courtesy asks of each: `{ key, name, ends, source, instance,
-- fromPlayer }` (fromPlayer: `isFromPlayerOrPlayerPet`, in neither the docs nor the FrameXML of
-- Forever's client, so usually nil). nil when the client hides them or one cannot be read: then
-- nothing is known, not "no buffs" (GetAuraDataByIndex raises while hidden, BugGrabber 08.11.2026).
function Compat.HelpfulAuras()
  local api = rawget(_G, "C_UnitAuras")
  if not (api and type(api.GetAuraDataByIndex) == "function") or Bastians.Compat.AurasSecret() then
    return nil
  end
  local plain, out = Bastians.Compat.Plain, {}
  for i = 1, 80 do
    local a = api.GetAuraDataByIndex("player", i, "HELPFUL")
    if a == nil then
      return out
    elseif not Compat.Readable(a) then
      return nil
    end
    local key = plain(a.spellId)
    if key == nil then
      return nil
    end
    local ends = plain(a.expirationTime)
    out[#out + 1] = {
      key = key,
      name = plain(a.name),
      ends = type(ends) == "number" and ends > 0 and ends or true,
      source = plain(a.sourceUnit),
      instance = plain(a.auraInstanceID),
      fromPlayer = plain(a.isFromPlayerOrPlayerPet),
    }
  end
  return out
end

-- Who cast an aura on the player, also without a unit token (C_UnitAuras.GetAuraCasterGUID, in the P1
-- dump, assumed). nil when the client does not say.
function Compat.CasterGUID(instance)
  local api = rawget(_G, "C_UnitAuras")
  if not (instance and api and type(api.GetAuraCasterGUID) == "function") then
    return nil
  end
  local guid = Bastians.Compat.Plain(api.GetAuraCasterGUID("player", instance))
  return type(guid) == "string" and guid ~= "" and guid or nil
end

-- A player's name from a GUID, or nil.
function Compat.NameOfGUID(guid)
  local name = select(6, Compat.Call("GetPlayerInfoByGUID", guid))
  name = Bastians.Compat.Plain(name)
  return type(name) == "string" and name ~= "" and name or nil
end

-- The weather where the player is: "clear", "rain", "snow", "sandstorm" or "other", and its
-- intensity; nil when the client does not say. `clear` measured once, Forever 08.11.2026.
local WEATHER = { [0] = "clear", "rain", "snow", "sandstorm", "other" }

function Compat.Weather()
  local api = rawget(_G, "C_Weather")
  if not (api and type(api.GetCurrentWeather) == "function") then
    return nil
  end
  local info = api.GetCurrentWeather()
  if not Compat.Readable(info) then
    return nil
  end
  local kind = Bastians.Compat.Plain(info.type)
  return WEATHER[kind], Bastians.Compat.Plain(info.intensity)
end

-- Sends one chat message of at most 255 bytes. -> whether it was handed to the client. `SAY` and
-- `EMOTE` go out only from the player's click (measured, Forever 08.11.2026).
function Compat.SendChat(text, channel, target)
  local send = fnOf("SendChatMessage")
  if not send or type(text) ~= "string" or text == "" then
    return false
  end
  send(text, channel or "SAY", nil, target)
  return true
end

-- Declines a request (`CancelDuel`, `CloseTrade`, `DeclineGroup`) and hides its popup. -> whether
-- the client offered the call.
local DECLINE = { duel = "CancelDuel", trade = "CloseTrade", invite = "DeclineGroup" }
local POPUP = { duel = "DUEL_REQUESTED", invite = "PARTY_INVITE" }
function Compat.Decline(kind)
  local fn = DECLINE[kind] and fnOf(DECLINE[kind]) or nil
  if fn then
    fn()
  end
  local hide = POPUP[kind] and fnOf("StaticPopup_Hide") or nil
  if hide then
    hide(POPUP[kind])
  end
  return fn ~= nil
end

-- The unit token's player name, or nil when the client gives none (the unit left reach).
function Compat.UnitPlayerName(unit)
  local name = fnOf("UnitName")
  if not (name and unit) then
    return nil
  end
  local n = Bastians.Compat.Plain((name(unit)))
  return type(n) == "string" and n ~= "" and n or nil
end

-- Whether the unit is the player or in the player's group (no courtesy to those).
function Compat.IsMineOrGroup(unit)
  if not unit then
    return false
  end
  local isUnit, party, raid = fnOf("UnitIsUnit"), fnOf("UnitInParty"), fnOf("UnitInRaid")
  local plain = Bastians.Compat.Plain
  return (isUnit and plain(isUnit(unit, "player")) and true)
    or (party and plain(party(unit)) and true)
    or (raid and plain(raid(unit)) and true)
    or false
end

-- A global function's answer, or nil when the client has no such function.
function Compat.Call(name, ...)
  local f = fnOf(name)
  if not f then
    return nil
  end
  return f(...)
end
