-- The public beacon of Bastian's Campfire (campfire.md "The public channel", plan-second-wave.md S5
-- v2, decision B, #20): behind a switch that is off, the character joins a temporary custom channel
-- and "Share the fire" goes there too; fires from that channel come in rate-limited and capped, a
-- name on the block list is dropped. The senders' names stay in memory only (the pin's label), the
-- saved fires hold positions as every other fire.
local _, ns = ...
local B = Bastians
local Model = ns.Model

local Public = {}
ns.Public = Public

Public.CHANNEL = "BastiansCamp" -- one channel for the realm and faction
Public.JOIN_DELAY = 15 -- seconds after the login: the game's own channels keep their numbers
Public.SEND_EVERY = 300 -- seconds: one public share at most this often
Public.FROM_EVERY = 300 -- seconds: one fire per sender at most this often
Public.MAX_FIRES = 20 -- public fires kept at once (the rest wait until older ones expire)

local mod
local number -- the channel's number while joined
local sentAt -- GetTime() of our last public share
local heard = {} -- sender -> GetTime() of their last fire (memory only)
local senders = setmetatable({}, { __mode = "k" }) -- fire -> sender name (memory only)

local function on()
  return mod and mod:IsEnabled() and mod.db.profile.public == true
end

local function short(name)
  return string.lower(string.match(name or "", "^([^%-]+)") or "")
end

function Public.Blocked(name)
  return mod.db.global.blocked[short(name)] == true
end

-- Adds or removes a name from the block list. -> true when the name is blocked afterwards.
function Public.Block(name, blocked)
  local key = short(name)
  if key == "" then
    return nil
  end
  mod.db.global.blocked[key] = blocked ~= false or nil
  return mod.db.global.blocked[key] == true
end

-- The block list in words for the settings page, or nil when empty.
function Public.BlockedText()
  local names = {}
  for name in pairs(mod.db.global.blocked) do
    names[#names + 1] = name
  end
  table.sort(names)
  return #names > 0 and table.concat(names, ", ") or nil
end

function Public.Number()
  return number
end

-- Joins or leaves the channel as the switch says (out of combat is not needed: a chat channel
-- is no secure frame).
function Public.Apply()
  if on() then
    if not number then
      number = B.Compat.JoinChannel(Public.CHANNEL)
    end
  elseif number or B.Compat.ChannelNumber(Public.CHANNEL) then
    B.Compat.LeaveChannel(Public.CHANNEL)
    number = nil
  end
  return number
end

-- "Share the fire" to the channel too (Beacon.Share calls it with its payload). -> true when sent.
function Public.Share(payload)
  if not (on() and number) then
    return false
  end
  local now = GetTime()
  if sentAt and now - sentAt < Public.SEND_EVERY then
    return false, "soon"
  end
  if not B.Comm.Send(Model.KIND, payload, "CHANNEL", number) then
    return false
  end
  sentAt = now
  return true
end

local function publicCount()
  local n = 0
  for _, fire in ipairs(ns.Beacon.Fires()) do
    if fire.public then
      n = n + 1
    end
  end
  return n
end

-- A fire from the channel. -> the fire kept, or nil and why.
function Public.Receive(value, sender)
  if not on() then
    return nil, "off"
  end
  if Public.Blocked(sender) then
    return nil, "blocked"
  end
  local now = GetTime()
  local key = short(sender)
  if heard[key] and now - heard[key] < Public.FROM_EVERY then
    return nil, "soon"
  end
  if publicCount() >= Public.MAX_FIRES then
    return nil, "full"
  end
  local fire = Model.CleanCamp(value, time())
  if not fire then
    return nil, "form"
  end
  heard[key] = now
  fire.public = true
  senders[fire] = string.match(sender or "", "^([^%-]+)")
  ns.Beacon.Add(fire)
  B:Fire("BASTIANS_CAMP_SHARED", fire.map, fire.x, fire.y)
  return fire
end

-- Who shared a public fire (memory only; nil after a /reload).
function Public.Sender(fire)
  return senders[fire]
end

function Public.Attach(m)
  mod = m
  if type(rawget(mod.db.global, "blocked")) ~= "table" then
    rawset(mod.db.global, "blocked", {})
  end
  C_Timer.After(Public.JOIN_DELAY, Public.Apply)
end

function Public.Detach()
  if number then
    B.Compat.LeaveChannel(Public.CHANNEL)
    number = nil
  end
end
