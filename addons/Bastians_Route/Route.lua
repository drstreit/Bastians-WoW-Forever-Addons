-- Bastian's Route (route.md): the module. Builds the planner's inputs from Data (flight masters,
-- transports), the player's faction, the flight network setting, the learned flight times and the
-- hearth; provides the `travel` service; the `route.to` action picks the fastest of an entity's places;
-- the active route is a map layer (`route.path`), is followed once a second while active (step
-- completion, re-route when off course) and learns flight masters, flight durations, the mount speed
-- and the inn from what the player does. The arrow to the next step is Arrow.lua (S6). Optional
-- dependencies only add: without Map there is no line, without Quests the "known" network is
-- Route's own learned set.
local ADDON, ns = ...
local B = Bastians
local S = B.UI.Style
ns.L = ns.L or B.NewLocale()
local L = ns.L
local Graph, W = ns.Graph, ns.Window

local Route = {}
ns.Route = Route

Route.ARRIVE_YARDS = 40 -- a step ends when the player is this close to its end
Route.OFF_COURSE_YARDS = 150 -- re-route when farther than this from the current walking leg
Route.REPLAN_COOLDOWN = 10 -- seconds between automatic re-routes
Route.TICK = 1 -- seconds between position checks while a route is active
Route.MAX_LOCATIONS = 10 -- places of an entity that are planned to pick the nearest by time
Route.HEARTHSTONE_SPELL = 8690
Route.MAX_LEARNED_SPEED = 20 -- yards per second; anything above is a taxi or a fall

local FACTION_LETTER = { Alliance = "A", Horde = "H" }

local mod
local active -- { seconds, steps, start, goal, index, notes, ref }
local ticker
local lastReplan = -math.huge
local estimateCache, estimateCount = {}, 0
local taxiShown, taxiCurrent, taxiFlight -- the open taxi map, its current node, the flight in progress
local hearthingAt
local nameToID -- flight master name -> data id (built on demand)

local function db()
  return mod.db
end

local function data()
  return B:GetService("data")
end

local function progress()
  return B:GetService("progress")
end

local function playerFaction()
  local facts = B.Compat.GetPlayerFacts()
  return facts and FACTION_LETTER[facts.faction] or nil
end

-- { continent, wx, wy } of the player, or nil in instances.
local function playerPos()
  local c, wx, wy = B.Coords.Player()
  if not c then
    return nil
  end
  return { continent = c, wx = wx, wy = wy }
end

local function resetCache()
  estimateCache, estimateCount = {}, 0
end

-- ---------------------------------------------------------------------------------------------
-- Inputs for the planner
-- ---------------------------------------------------------------------------------------------

-- Flight masters the player can use: keys are node ids or names (what the taxi map gives).
local function knownKeys()
  local out = {}
  local p = progress()
  if p and p.KnownFlightPaths then
    for k in pairs(p:KnownFlightPaths() or {}) do
      out[k] = true
    end
  end
  for k in pairs(db().char.known or {}) do
    out[k] = true
  end
  if db().profile.network == "account" then
    for k in pairs(db().global.known or {}) do
      out[k] = true
    end
  end
  return out
end

function Route.Flights()
  local d = data()
  if not d then
    return {}
  end
  local faction = playerFaction()
  local network = db().profile.network or "known"
  local known = network ~= "all" and knownKeys() or nil
  local out = {}
  for _, id in ipairs(d:Each("flightpath") or {}) do
    local r = d:Get("flightpath", id)
    if
      r
      and r.continent
      and r.wx
      and r.wy
      and (r.faction == "both" or not faction or r.faction == faction)
    then
      if not known or known[id] or (r.name and known[r.name]) then
        out[#out + 1] = { id = id, name = r.name, continent = r.continent, wx = r.wx, wy = r.wy }
      end
    end
  end
  return out
end

function Route.Transports()
  local d = data()
  if not d then
    return {}
  end
  local faction = playerFaction()
  local out = {}
  for _, id in ipairs(d:Each("transport") or {}) do
    local r = d:Get("transport", id)
    local allowed = r
      and r.stops
      and (r.faction == "both" or not faction or FACTION_LETTER[r.faction] == faction)
    if allowed then
      local stops, ok = {}, true
      for i, s in ipairs(r.stops) do
        local w = r.world and r.world[i]
        local c, wx, wy
        if w then
          c, wx, wy = w[1], w[2], w[3]
        else
          c, wx, wy = B.Coords.ToWorld(s[1], s[2], s[3])
        end
        if not c then
          ok = false
          break
        end
        stops[i] = { continent = c, wx = wx, wy = wy, label = s[4] }
      end
      if ok and #stops >= 2 then
        out[#out + 1] = {
          id = id,
          name = r.name,
          kind = r.kind,
          stops = stops,
          ride = r.ride,
          cycle = r.cycle,
          verified = r.verified,
        }
      end
    end
  end
  return out
end

-- The hearth target when the stone is ready and the inn is known; otherwise nil plus a note.
function Route.Hearth(notes)
  local h = db().char.hearth
  local hs = B.Compat.GetHearthstone()
  local function note(text)
    if notes then
      notes[#notes + 1] = text
    end
  end
  if not (h and h.continent) then
    note(L["Hearth: inn unknown. Type /broute hearth while standing at your inn."])
    return nil
  end
  if hs.bindName and h.name and hs.bindName ~= h.name then
    note(string.format(L["Hearth: you are bound to %s now; type /broute hearth there."], hs.bindName))
    return nil
  end
  if not hs.hasStone then
    note(L["Hearth: no Hearthstone in your bags."])
    return nil
  end
  if not hs.ready then
    note(string.format(L["Hearth: ready in %s."], Graph.FormatSeconds(hs.remaining)))
    return nil
  end
  return { continent = h.continent, wx = h.wx, wy = h.wy, name = h.name or L["your inn"] }
end

function Route.Inputs(start, goal)
  local notes = {}
  return {
    start = start,
    goal = goal,
    flights = Route.Flights(),
    transports = Route.Transports(),
    hearth = Route.Hearth(notes),
    walkSpeed = db().char.maxSpeed or Graph.WALK_SPEED,
    flightTimes = db().global.flightTimes,
  },
    notes
end

-- A route from { continent, wx, wy } to { continent, wx, wy, name, ref }, or nil.
function Route.Plan(start, goal)
  local g, notes = Route.Inputs(start, goal)
  local route = Graph.Plan(g)
  if route then
    route.notes = notes
    route.index = 1
  end
  return route
end

-- ---------------------------------------------------------------------------------------------
-- The travel service (core-contracts §11)
-- ---------------------------------------------------------------------------------------------

local function cacheKey(from, to)
  return string.format(
    "%d:%d:%d>%d:%d:%d",
    from[1],
    math.floor(from[2] / 50),
    math.floor(from[3] / 50),
    to[1],
    math.floor(to[2] / 50),
    math.floor(to[3] / 50)
  )
end

local travel = {
  -- Estimate({ continent, wx, wy }, { continent, wx, wy }) -> seconds, mode ; nil when unreachable
  Estimate = function(_, from, to)
    if not (from and to and from[1] and to[1]) then
      return nil
    end
    local key = cacheKey(from, to)
    local hit = estimateCache[key]
    if hit then
      return hit[1] or nil, hit[2]
    end
    local route = Route.Plan(
      { continent = from[1], wx = from[2], wy = from[3] },
      { continent = to[1], wx = to[2], wy = to[3] }
    )
    if estimateCount > 2000 then
      resetCache()
    end
    estimateCount = estimateCount + 1
    if not route then
      estimateCache[key] = { false }
      return nil
    end
    local mode = Graph.Mode(route)
    estimateCache[key] = { route.seconds, mode }
    return route.seconds, mode
  end,
  Route = function(_, from, to)
    return Route.Plan(
      { continent = from[1], wx = from[2], wy = from[3] },
      { continent = to[1], wx = to[2], wy = to[3], name = to[4] }
    )
  end,
  -- Go({ continent, wx, wy, name }) -> true when a route was set from the player's position
  Go = function(_, to)
    return Route.ToPoint(to[1], to[2], to[3], to[4])
  end,
}
Route.travel = travel

-- ---------------------------------------------------------------------------------------------
-- The active route
-- ---------------------------------------------------------------------------------------------

function Route.Active()
  return active
end

local tick

local function startTicker()
  if not ticker then
    ticker = C_Timer.NewTicker(Route.TICK, tick)
  end
end

local function stopTicker()
  if ticker then
    ticker:Cancel()
    ticker = nil
  end
end

function Route.Set(route)
  active = route
  if route then
    startTicker()
  else
    stopTicker()
  end
  B:Fire("BASTIANS_LAYER_CHANGED", "route.path")
  B:Fire("BASTIANS_ROUTE_CHANGED", route)
end

function Route.Clear()
  if active then
    Route.Set(nil)
  end
end

-- Route to an entity: the fastest of its places from where the player stands.
function Route.To(ref)
  local start = playerPos()
  if not start then
    B:Say(L["No map position here (instance?)"])
    return false
  end
  local e = B:Entity(ref)
  local name = e:Name() or ref
  local best
  for i, loc in ipairs(e:Locations()) do
    if i > Route.MAX_LOCATIONS then
      break
    end
    local c, wx, wy = B.Coords.ToWorld(loc.map, loc.x, loc.y)
    if c then
      local route = Route.Plan(
        start,
        { continent = c, wx = wx, wy = wy, name = name, ref = ref, map = loc.map, x = loc.x, y = loc.y }
      )
      if route and (not best or route.seconds < best.seconds) then
        best = route
      end
    end
  end
  if not best then
    B:Say(L["No route to %s"], name)
    return false
  end
  -- already there (a route to a place a few yards away was drawn and
  -- cleared again a second later by the arrival check): say so, draw nothing
  if Graph.Distance(start.wx, start.wy, best.goal.wx, best.goal.wy) <= Route.ARRIVE_YARDS then
    B:Say(L["You are already there: %s"], name)
    return false
  end
  best.ref = ref
  Route.Set(best)
  B:Say(L["Route to %s: %s, %d steps"], name, Graph.FormatSeconds(best.seconds), #best.steps)
  if db().profile.openWindow ~= false then
    W.Open()
  end
  return true
end

-- Route to a world point (the map's right click, "Route here"): plans from the player, sets the route.
function Route.ToPoint(continent, wx, wy, name)
  local start = playerPos()
  if not start then
    B:Say(L["No map position here (instance?)"])
    return false
  end
  name = name or L["the marked spot"]
  local route = Route.Plan(start, { continent = continent, wx = wx, wy = wy, name = name })
  if not route then
    B:Say(L["No route to %s"], name)
    return false
  end
  Route.Set(route)
  B:Say(L["Route to %s: %s, %d steps"], name, Graph.FormatSeconds(route.seconds), #route.steps)
  if db().profile.openWindow ~= false then
    W.Open()
  end
  return true
end

-- Plan the active goal again from the player's position.
function Route.Replan(reason)
  if not active then
    return false
  end
  local start = playerPos()
  if not start then
    return false
  end
  lastReplan = GetTime()
  local goal = active.goal
  local route = Route.Plan(start, goal)
  if not route then
    -- a failed re-route keeps the route the player has (a route that vanished
    -- after two seconds); the next check tries again after the cooldown
    B:Say(L["Could not re-route to %s from here; keeping the route."], goal.name or "")
    return false
  end
  route.ref = active.ref
  route.reason = reason
  Route.Set(route)
  return true
end

-- Learn the mount speed from the fastest ground speed seen.
local function learnSpeed()
  local speed, _, onTaxi = B.Compat.GetMoveSpeed()
  if not speed then
    return -- the client keeps it secret right now (Forever 23.10.2026)
  end
  if not onTaxi and speed > (db().char.maxSpeed or Graph.WALK_SPEED) and speed <= Route.MAX_LEARNED_SPEED then
    db().char.maxSpeed = speed
    resetCache()
  end
end

-- Once a second while a route is active: step completion and the off-course check.
tick = function()
  if not active then
    stopTicker()
    return
  end
  learnSpeed()
  local pos = playerPos()
  if not pos then
    return
  end
  local step = active.steps[active.index or 1]
  if not step then
    return
  end
  if step.to.continent == pos.continent then
    if Graph.Distance(pos.wx, pos.wy, step.to.wx, step.to.wy) <= Route.ARRIVE_YARDS then
      active.index = (active.index or 1) + 1
      if active.index > #active.steps then
        B:Say(L["You have arrived: %s"], active.goal.name or "")
        Route.Clear()
      else
        B:Fire("BASTIANS_ROUTE_CHANGED", active)
      end
      return
    end
  end
  ns.Arrow.Refresh() -- the own arrow turns at least once a second while a route is active (S6)
  if step.mode == "walk" and step.from.continent == pos.continent then
    if GetTime() - lastReplan >= Route.REPLAN_COOLDOWN then
      local off = Graph.SegmentDistance(pos.wx, pos.wy, step.from.wx, step.from.wy, step.to.wx, step.to.wy)
      if off > Route.OFF_COURSE_YARDS then
        Route.Replan("off course")
      end
    end
  end
end

-- ---------------------------------------------------------------------------------------------
-- The map layer
-- ---------------------------------------------------------------------------------------------

local function pathPins(view)
  if not active then
    return {}
  end
  local pins = {}
  local points, approx
  local function flush()
    if points and #points >= 2 then
      pins[#pins + 1] = {
        kind = "path",
        points = points,
        color = S.C.path,
        width = 3,
        -- an approximate leg (a straight walk the graph has not measured: it may cross water or
        -- a mountain until the navmesh of ADR 0005) is drawn dashed; the step list says so
        style = approx and "dashed" or nil,
      }
    end
    points = nil
  end
  for i, step in ipairs(active.steps) do
    if i >= (active.index or 1) then
      local onView = step.from.continent == view.continent and step.to.continent == view.continent
      if onView and not step.jump then
        local stepApprox = step.approx and true or false
        if points and stepApprox ~= approx then
          local last = points[#points]
          flush()
          points = { last }
        end
        approx = stepApprox
        points = points or { { step.from.wx, step.from.wy } }
        points[#points + 1] = { step.to.wx, step.to.wy }
      else
        flush()
      end
    end
  end
  flush()
  local goal = active.goal
  if goal and goal.continent == view.continent then
    pins[#pins + 1] = {
      ref = active.ref,
      wx = goal.wx,
      wy = goal.wy,
      icon = B.UI.IconTexture("route"),
      label = goal.name,
      priority = 95,
      cluster = false,
      size = 24,
    }
  end
  -- the minimap overlay (Map S5) asks with `minimap`: the next step's end is a pin there too,
  -- so the rim arrow points the way (S6)
  if view.minimap then
    local t = ns.Arrow.Target()
    if t and t.continent == view.continent and not (goal and goal.wx == t.wx and goal.wy == t.wy) then
      pins[#pins + 1] = {
        ref = active.ref,
        wx = t.wx,
        wy = t.wy,
        icon = B.UI.IconTexture("route"),
        label = t.name,
        priority = 94,
        cluster = false,
        color = S.C.path,
        nextStep = true,
      }
    end
  end
  return pins
end

-- ---------------------------------------------------------------------------------------------
-- Learning: flight masters, flight durations, the inn
-- ---------------------------------------------------------------------------------------------

-- The data id of a taxi map node: its id when the data has it, else by name.
local function flightIDFor(n)
  local d = data()
  if not (n and d) then
    return nil
  end
  if n.id and d:Get("flightpath", n.id) then
    return n.id
  end
  if not nameToID then
    nameToID = {}
    for _, id in ipairs(d:Each("flightpath") or {}) do
      local r = d:Get("flightpath", id)
      if r and r.name then
        nameToID[r.name] = id
      end
    end
  end
  return n.name and nameToID[n.name] or nil
end

local function onTaxiMapOpened()
  local nodes = B.Compat.GetTaxiNodes()
  local known, charKnown = db().global.known, db().char.known
  taxiCurrent = nil
  for _, n in ipairs(nodes) do
    if n.state == "current" or n.state == "reachable" then
      local key = n.id or n.name
      if key then
        known[key] = true
        charKnown[key] = true
      end
    end
    if n.state == "current" then
      taxiCurrent = n
    end
  end
  taxiShown = nodes
  resetCache()
end

-- The flight master nearest the player, or nil when none is within reach.
local function nearestFlight(pos)
  local d = data()
  if not (d and pos) then
    return nil
  end
  local best, bestDist
  for _, id in ipairs(d:Each("flightpath") or {}) do
    local r = d:Get("flightpath", id)
    if r and r.continent == pos.continent and r.wx then
      local dist = Graph.Distance(pos.wx, pos.wy, r.wx, r.wy)
      if dist <= 100 and (not bestDist or dist < bestDist) then
        best, bestDist = id, dist
      end
    end
  end
  return best
end

local function onLanded()
  local flight = taxiFlight
  taxiFlight = nil
  if not flight then
    return
  end
  local _, _, onTaxi = B.Compat.GetMoveSpeed()
  if onTaxi then
    taxiFlight = flight -- a stop on a multi-hop flight; wait for the real landing
    return
  end
  local seconds = GetTime() - flight.startedAt
  local to = flight.to or nearestFlight(playerPos())
  if flight.from and to and seconds > 5 then
    local times = db().global.flightTimes
    seconds = math.floor(seconds + 0.5)
    times[Graph.FlightKey(flight.from, to)] = seconds
    times[Graph.FlightKey(to, flight.from)] = seconds
    resetCache()
    B:Fire("BASTIANS_ROUTE_CHANGED", active)
  end
end

local taxiHooked = false
local function hookTaxi()
  if taxiHooked or type(TakeTaxiNode) ~= "function" then
    return
  end
  taxiHooked = true
  hooksecurefunc("TakeTaxiNode", function(index)
    if not (mod and mod:IsEnabled()) then
      return
    end
    local target = taxiShown and taxiShown[index]
    taxiFlight = {
      from = flightIDFor(taxiCurrent),
      to = flightIDFor(target),
      startedAt = GetTime(),
    }
  end)
end

-- Remember the inn where the player stands as the hearth target.
function Route.SetHearthHere()
  local pos = playerPos()
  if not pos then
    B:Say(L["No map position here (instance?)"])
    return false
  end
  local hs = B.Compat.GetHearthstone()
  db().char.hearth = { name = hs.bindName, continent = pos.continent, wx = pos.wx, wy = pos.wy }
  resetCache()
  B:Say(L["Hearth set: %s"], hs.bindName or L["here"])
  return true
end

-- Settings hub line.
function Route.Note()
  local parts = {}
  local h = db().char.hearth
  local hs = B.Compat.GetHearthstone()
  if h and h.continent then
    parts[#parts + 1] = string.format(
      L["Hearth: %s, %s"],
      h.name or L["set"],
      hs.ready and L["ready"] or string.format(L["ready in %s"], Graph.FormatSeconds(hs.remaining))
    )
  else
    parts[#parts + 1] = L["Hearth: inn unknown (/broute hearth at your inn)"]
  end
  local known, flights = 0, 0
  for _ in pairs(db().char.known or {}) do
    known = known + 1
  end
  for _ in pairs(db().global.flightTimes or {}) do
    flights = flights + 1
  end
  parts[#parts + 1] =
    string.format(L["%d flight masters learned, %d flight times measured"], known, flights / 2)
  return table.concat(parts, ". ")
end

-- ---------------------------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------------------------

local NETWORKS = {
  known = "Known to this character",
  account = "Known to any of my characters",
  all = "All flight masters",
}

mod = B:NewModule("Route", {
  news = ns.NEWS, -- What's new (ADR 0021)
  addon = ADDON,
  open = function()
    W.Toggle()
  end,
  title = L["Route"],
  apiVersion = 1,
  data = { "world" },
  optional = { "Bastians_Data", "Bastians_Quests", "Bastians_Map", "TomTom" },
  defaults = {
    profile = { network = "known", openWindow = true, window = {}, tree = {} },
    char = { known = {}, hearth = false, maxSpeed = false },
    global = { known = {}, flightTimes = {} },
  },
  options = {
    { type = "header", label = L["Route"] },
    {
      type = "select",
      key = "network",
      label = L["Flight paths to use"],
      values = function()
        local out = {}
        for k, v in pairs(NETWORKS) do
          out[k] = L[v]
        end
        return out
      end,
    },
    { type = "toggle", key = "openWindow", label = L["Open the step list when a route starts"] },
    {
      type = "toggle",
      key = "arrow",
      label = L["Show an arrow to the next step while a route is active"],
      default = true,
    },
    {
      type = "toggle",
      key = "arrowTomTom",
      label = L["Use TomTom's arrow when TomTom is installed"],
      default = true,
    },
    {
      type = "note",
      text = function()
        return Route.Note()
      end,
    },
  },
  OnEnable = function(self)
    if db().char.hearth == false then
      db().char.hearth = nil
    end
    if db().char.maxSpeed == false then
      db().char.maxSpeed = nil
    end
    db().char.known = db().char.known or {}
    db().global.known = db().global.known or {}
    db().global.flightTimes = db().global.flightTimes or {}
    nameToID = nil
    resetCache()
    B:ProvideService(self, "travel", travel, { priority = 100 })
    -- the map's right click on empty ground opens the zone's menu with the point in the context
    B:RegisterAction(self, {
      id = "route.here",
      label = L["Route here"],
      icon = B.UI.IconTexture("route"),
      types = { "zone" },
      order = 14,
      when = function(_, ctx)
        return ctx ~= nil and type(ctx.point) == "table"
      end,
      run = function(_, ctx)
        local pt = ctx.point
        Route.ToPoint(pt[1], pt[2], pt[3], pt[4])
      end,
    })
    B:RegisterAction(self, {
      id = "route.to",
      label = L["Route to"],
      icon = B.UI.IconTexture("route"),
      types = "*",
      order = 15,
      when = function(ref)
        for _, loc in ipairs(B:Entity(ref):Locations()) do
          if B.Coords.ToWorld(loc.map, loc.x, loc.y) then
            return true
          end
        end
        return false
      end,
      run = function(ref)
        Route.To(ref)
      end,
    })
    B:RegisterMapLayer(self, {
      id = "route.path",
      label = L["Route"],
      defaultOn = true,
      minLevel = 0,
      query = pathPins,
    })
    self:RegisterEvent("TAXIMAP_OPENED", onTaxiMapOpened)
    self:RegisterEvent("PLAYER_CONTROL_GAINED", onLanded)
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(_, _, unit, _, spellID)
      if unit == "player" and spellID == Route.HEARTHSTONE_SPELL then
        hearthingAt = GetTime()
      end
    end)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
      if hearthingAt and GetTime() - hearthingAt < 60 then
        hearthingAt = nil
        C_Timer.After(1, function()
          local pos = playerPos()
          if pos and mod:IsEnabled() then
            local hs = B.Compat.GetHearthstone()
            db().char.hearth = { name = hs.bindName, continent = pos.continent, wx = pos.wx, wy = pos.wy }
            resetCache()
          end
        end)
      end
    end)
    pcall(self.RegisterEvent, self, "HEARTHSTONE_BOUND", function()
      Route.SetHearthHere()
    end)
    self:On("BASTIANS_DATA_LOADED", function()
      nameToID = nil
      resetCache()
    end)
    self:On("BASTIANS_SETTING_CHANGED", function(_, _, name, key)
      if name == self.name and key == "network" then
        resetCache()
      elseif name == self.name and (key == "arrow" or key == "arrowTomTom") then
        ns.Arrow.Update()
      end
    end)
    hookTaxi()
    W.Register(self)
    ns.Arrow.Register(self) -- the arrow to the next step (S6)
  end,
  OnDisable = function()
    Route.Clear()
    W.Hide()
    ns.Arrow.Unregister()
  end,
})
ns.mod = mod
mod.Arrow = ns.Arrow -- the arrow to the next step (Arrow.lua, S6)
mod.Route, mod.Graph, mod.Window = Route, Graph, W

BINDING_NAME_BASTIANS_ROUTE = L["Open Bastian's Route"]

SLASH_BASTIANSROUTE1 = "/broute"
SlashCmdList.BASTIANSROUTE = function(msg)
  msg = strtrim(msg or "")
  local cmd, arg = string.match(msg, "^(%S+)%s*(.*)$")
  cmd = string.lower(cmd or "")
  if cmd == "" then
    W.Toggle()
  elseif cmd == "clear" then
    Route.Clear()
  elseif cmd == "hearth" then
    Route.SetHearthHere()
  elseif cmd == "replan" then
    Route.Replan("command")
  elseif cmd == "to" and arg ~= "" then
    Route.To(arg)
  else
    B:Say("/broute [clear | hearth | replan | to <type:id>]")
  end
end
