-- Bastian's Route: the /way command (route.md "The /way command", ADR 0062): answers it when no
-- other addon does, and on the player's word when one does. Parse, the zone names and the owner's
-- look-up are plain functions; TomTom's format is matched, none of its code is used.
local _, ns = ...
local B = Bastians
local L = ns.L

local Way = {}
ns.Way = Way

Way.COMMAND = "/way"
Way.KEY = "BASTIANSWAY"
Way.BURST = 0.1 -- seconds in which a macro's lines count as one route
Way.SHOWN = 7 -- zones named when several match
Way.USAGE = "/way [zone] <x> <y> [description] | /way #<map> <x> <y> | /way reset | /way list"

local mod
local pending -- the stops of the burst
local zones -- { { key, name, map, rank } }, built on first use
local wrapped -- the owner's key once its entry is wrapped
local counter = 0

local POINT = tonumber("1.5") and "." or ","

local function isNumber(text)
  return text ~= nil and tonumber(text) ~= nil
end

-- A /way line as plain values: { cmd = "reset" | "list" | "usage" } or { zone, x, y, desc } with x
-- and y as map fractions. Pure.
function Way.Parse(msg)
  local text = tostring(msg or "")
  text = text:gsub("(%d+[%.,]%d+),(%d)", "%1 %2") -- 45.2,67.3
  text = text:gsub("(%d)[%.,]%s+(%d)", "%1 %2") -- 45.2, 67.3
  text = text:gsub("(%d)[%.,](%d)", "%1" .. POINT .. "%2") -- the decimal separator of this client
  local tokens = {}
  for token in text:gmatch("%S+") do
    tokens[#tokens + 1] = token
  end
  local first = tokens[1] and tokens[1]:lower()
  if first == "reset" or first == "clear" then
    return { cmd = "reset" }
  elseif first == "list" then
    return { cmd = "list" }
  end
  local at
  for i, token in ipairs(tokens) do
    if isNumber(token) then
      at = i
      break
    end
  end
  if not (at and isNumber(tokens[at + 1])) then
    return { cmd = "usage" }
  end
  local x, y = tonumber(tokens[at]), tonumber(tokens[at + 1])
  if x < 0 or x > 100 or y < 0 or y > 100 then
    return { cmd = "usage" }
  end
  return {
    zone = at > 1 and table.concat(tokens, " ", 1, at - 1) or nil,
    x = x / 100,
    y = y / 100,
    desc = tokens[at + 2] and table.concat(tokens, " ", at + 2) or nil,
  }
end

local function squeeze(text)
  return (text:lower():gsub("%s", ""))
end

-- Every zone a /way can name, by its name in the client's language and in English.
local function zoneList()
  if zones then
    return zones
  end
  local d = B:GetService("data")
  if not d then
    return {}
  end
  local list = {}
  for _, id in ipairs(d:Each("zone")) do
    local r = d:Get("zone", id)
    if r and r.mapType ~= 4 and B.Coords.ToWorld(id, 0.5, 0.5) then
      local rank = r.mapType == 3 and 0 or 1
      for _, name in ipairs({ r.name or false, r.nameEN or false }) do
        if name then
          list[#list + 1] = { key = squeeze(name), name = r.name or name, map = id, rank = rank }
        end
      end
    end
  end
  if #list > 0 then
    zones = list
  end
  return list
end

local function better(a, b)
  return a.rank < b.rank or (a.rank == b.rank and a.map < b.map)
end

-- (uiMapID, its name) of a zone text, or nil and what to tell the player.
function Way.FindZone(text)
  local literal = text:match("^#(%d+)$")
  if literal then
    local map = tonumber(literal)
    if B.Coords.ToWorld(map, 0.5, 0.5) then
      return map, B.Compat.MapName(map) or text
    end
    return nil, string.format(L["No zone called %s."], text)
  end
  local wanted = squeeze(text)
  local exact, byName = nil, {}
  for _, z in ipairs(zoneList()) do
    if z.key == wanted then
      if not exact or better(z, exact) then
        exact = z
      end
    elseif z.key:find(wanted, 1, true) then
      if not byName[z.name] or better(z, byName[z.name]) then
        byName[z.name] = z
      end
    end
  end
  if exact then
    return exact.map, exact.name
  end
  local names = {}
  for name in pairs(byName) do
    names[#names + 1] = name
  end
  table.sort(names)
  if #names == 0 then
    return nil, string.format(L["No zone called %s."], text)
  elseif #names > 1 then
    local shown = table.concat(names, ", ", 1, math.min(#names, Way.SHOWN))
    return nil, string.format(L["Several zones match %s: %s"], text, shown)
  end
  return byName[names[1]].map, names[1]
end

-- A parsed line as a stop of a route; nil and what to tell the player.
function Way.Stop(line)
  local map, name
  if line.zone then
    map, name = Way.FindZone(line.zone)
    if not map then
      return nil, name
    end
  else
    map = C_Map.GetBestMapForUnit("player") -- this moment's map (verified on Forever)
    if not map then
      return nil, L["No map position here (instance?)"]
    end
    name = B.Compat.MapName(map) or ""
  end
  local continent, wx, wy = B.Coords.ToWorld(map, line.x, line.y)
  if not continent then
    return nil, string.format(L["No zone called %s."], line.zone or name)
  end
  counter = counter + 1
  return {
    id = "way:" .. counter,
    name = line.desc or string.format("%s %.1f %.1f", name, line.x * 100, line.y * 100),
    place = { map = continent, wx = wx, wy = wy },
    uiMap = map,
    x = line.x,
    y = line.y,
  }
end

-- The burst is over: a route, or stops behind the running one.
function Way.Flush()
  local batch = pending
  pending = nil
  if not (batch and mod:IsEnabled()) then
    return
  end
  local R = ns.Route
  local running = R.Active()
  if mod.db.profile.wayAdd and running and not running.onFoot then
    R.AddStops(batch, true)
  elseif #batch > 1 then
    R.AddStops(batch, false)
  else
    local st = batch[1]
    local waypoint = B:GetService("waypoint")
    if waypoint then
      waypoint:Set(st.place.map, st.place.wx, st.place.wy, st.name, st.uiMap, st.x, st.y)
    end
    R.ToPoint(st.place.map, st.place.wx, st.place.wy, st.name)
  end
end

local function reset()
  pending = nil
  local waypoint = B:GetService("waypoint")
  if waypoint then
    waypoint:Clear()
  end
  ns.Route.Clear()
end

local function list()
  local stops = ns.Route.StopsAhead()
  if #stops == 0 then
    B:Say(L["No route. Right click anything with a place and choose Route to."])
  end
  for i, st in ipairs(stops) do
    B:Say("%d. %s", i, st.name or "?")
  end
end

-- The command.
function Way.Run(msg)
  if not (mod and mod:IsEnabled()) then
    return
  end
  local line = Way.Parse(msg)
  if line.cmd == "reset" then
    reset()
  elseif line.cmd == "list" then
    list()
  elseif line.cmd == "usage" then
    B:Say("%s", Way.USAGE)
  else
    local stop, why = Way.Stop(line)
    if not stop then
      B:Say("%s", why)
      return
    end
    pending = pending or {}
    pending[#pending + 1] = stop
    mod:Coalesce("way", Way.BURST, Way.Flush)
  end
end

-- The key of another addon's entry that answers /way (TomTom's first), or nil.
function Way.FindOwner()
  if SlashCmdList.TOMTOM_WAY then
    return "TOMTOM_WAY"
  end
  for key in pairs(SlashCmdList) do
    if key ~= Way.KEY then
      local i = 1
      local command = _G["SLASH_" .. key .. i]
      while command do
        if type(command) == "string" and command:lower() == Way.COMMAND then
          return key
        end
        i = i + 1
        command = _G["SLASH_" .. key .. i]
      end
    end
  end
  return nil
end

-- What the window's button calls the owner.
function Way.OwnerName()
  if not Way.owner then
    return nil
  end
  return Way.owner == "TOMTOM_WAY" and "TomTom" or Way.owner
end

function Way.OverOwner()
  return Way.owner ~= nil and mod.db.profile.wayOverOwner == true
end

local function wrap(key)
  if wrapped == key or type(SlashCmdList[key]) ~= "function" then
    return
  end
  local original = SlashCmdList[key]
  wrapped = key
  SlashCmdList[key] = function(msg, ...)
    if mod:IsEnabled() and mod.db.profile.wayOverOwner == true then
      Way.Run(msg)
    else
      original(msg, ...)
    end
  end
  B.Compat.ForgetSlash(Way.COMMAND) -- the client may have kept the owner's own handler
end

-- The window's button: who answers /way while another addon has it.
function Way.SetOverOwner(on)
  mod.db.profile.wayOverOwner = on and true or false
  if on and Way.owner then
    wrap(Way.owner)
  end
end

local function own()
  SLASH_BASTIANSWAY1 = Way.COMMAND
  SlashCmdList[Way.KEY] = Way.Run
end

local function disown()
  if SlashCmdList[Way.KEY] then
    SlashCmdList[Way.KEY] = nil
    SLASH_BASTIANSWAY1 = nil
    B.Compat.ForgetSlash(Way.COMMAND)
  end
end

-- From Route's OnEnable (at the login or later: every other addon has registered its commands).
function Way.Register(module)
  mod = module
  zones = nil
  disown() -- a re-enable looks again
  Way.owner = Way.FindOwner()
  if not Way.owner then
    own()
  elseif Way.OverOwner() then
    wrap(Way.owner)
  end
end

function Way.Unregister()
  pending = nil
  disown()
end

ns.mod.Way = Way -- for the tests, as mod.Death
