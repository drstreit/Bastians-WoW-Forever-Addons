-- Bastian's Route (route.md): the module. Builds the planner's inputs from Data (flight masters,
-- transports), the player's faction, the flight network setting, the learned flight times and the
-- hearth; the `route.to` action picks the fastest of an entity's places;
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
Route.OFF_COURSE_YARDS = 50 -- re-route when farther than this from the current walking leg (was
-- 150; follow like a car navigator)
Route.OFF_COURSE_TICKS = 2 -- ... on this many checks in a row (a sidestep is no detour)
Route.REPLAN_COOLDOWN = 4 -- seconds between automatic re-routes (was 10)
Route.TRIM_YARDS = 5 -- the line is drawn again once the player got this much further along it
Route.TICK = 1 -- seconds between position checks while a route is active
Route.MAX_LOCATIONS = 10 -- places of an entity that are planned to pick the nearest by time
Route.HEARTHSTONE_SPELL = 8690
Route.MAX_LEARNED_SPEED = 20 -- yards per second; anything above is a taxi or a fall
Route.LANDING_WAIT = 5 -- seconds after a teleport's cast before its landing is read without a loading screen
Route.LANDING_MOVED = 200 -- yards the character must have moved for that landing to count
-- the kinds of a route (R26.5, route.md "Route options"): the graph's profiles
Route.KINDS = { "fastest", "safe", "nocost" }
Route.CAREFUL_LEVELS = 3 -- a walk through creatures this many levels above the character says so

-- ", Risky trip" for the chat's route line (A4.3); "" without a verdict.
function Route.VerdictSuffix(route)
  local words, verdict = Graph.VerdictText(route, (B.Compat.GetPlayerFacts() or {}).level, L)
  return verdict and (", " .. words) or ""
end

local FACTION_LETTER = { Alliance = "A", Horde = "H" }

local mod
local active -- { seconds, steps, start, goal, index, notes, ref }
local ticker
local lastReplan = -math.huge
local offTicks = 0 -- checks in a row off the way
local taxiShown, taxiCurrent, taxiFlight -- the open taxi map, its current node, the flight in progress
local hearthingAt
local addCount = 0 -- the ids of the stops added to a route
local teleporting -- { id, at, from } while a teleport of the table was just cast (R26.7)
local nameToID -- flight master name -> data id (built on demand)
local nets = {} -- continent -> decoded walk network, or false (route.md "Walk network")

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

-- ---------------------------------------------------------------------------------------------
-- Inputs for the planner
-- ---------------------------------------------------------------------------------------------

local function graph()
  return B:GetService("graph")
end

-- Flight masters the player can use: keys are node ids or names (what the taxi map gives). Data's
-- graph learns them (W8): this character's, the account's for the "account" network, plus Quests'.
local function knownKeys()
  local out = {}
  local p = progress()
  if p and p.KnownFlightPaths then
    for k in pairs(p:KnownFlightPaths() or {}) do
      out[k] = true
    end
  end
  local g = graph()
  local char = g and g:Character()
  for k in pairs(char and char.taxi or {}) do
    out[k] = true
  end
  if db().profile.network == "account" then
    local account = g and g.Account and g:Account()
    for k in pairs(account and account.taxi or {}) do
      out[k] = true
    end
  end
  return out
end

-- The measured flight times in the planner's keys ("2>4"), from the graph's learned facts.
function Route.FlightTimes()
  local out = {}
  local g = graph()
  local learned = g and g:Learned()
  for key, seconds in pairs(learned and learned.taxi or {}) do
    local a, b = key:match("^taxinode:(%d+)>taxinode:(%d+)$")
    if a then
      out[Graph.FlightKey(tonumber(a), tonumber(b))] = seconds
    end
  end
  return out
end

-- Once (W8): the flight masters and flight times Route learned before Data did move into the graph.
local function moveLearned()
  local g = graph()
  if not g or db().global.movedToGraph then
    return
  end
  for k in pairs(db().char.known or {}) do
    local id = type(k) == "number" and k or Graph.TaxiIDFor({ name = k })
    if id then
      g:Learn({ kind = "taxinode", id = id })
    end
  end
  for k in pairs(db().global.known or {}) do
    local id = type(k) == "number" and k or Graph.TaxiIDFor({ name = k })
    if id then
      g:Learn({ kind = "taxinode", id = id, account = true })
    end
  end
  for key, seconds in pairs(db().global.flightTimes or {}) do
    local a, b = tostring(key):match("^(%d+)>(%d+)$")
    if a then
      g:Learn({ kind = "taxi", from = tonumber(a), to = tonumber(b), seconds = seconds })
    end
  end
  db().char.known, db().global.known, db().global.flightTimes = {}, {}, {}
  db().global.movedToGraph = true
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

-- The teleports of the table the character has ready (R26.7, route.md "Home and every way back"):
-- { { map, wx, wy, wz, seconds, name, id } } for graph:Route. A landing learned in game wins over
-- the table's place; a teleport to the hearth lands at the learned inn.
function Route.Teleports()
  local d = data()
  local out = {}
  if not d then
    return out
  end
  local facts = B.Compat.GetPlayerFacts() or {}
  local letter = FACTION_LETTER[facts.faction]
  local landings = db().global.landings or {}
  local inn = db().char.hearth
  for _, id in ipairs(d:Each("teleport")) do
    local t = d:Get("teleport", id)
    local fits = t and (not t.faction or t.faction == letter) and (not t.class or t.class == facts.classID)
    local owned, ready
    if fits then
      owned, ready = B.Compat.GetTeleportState(t.kind, t.kind == "spell" and t.spell or t.item, t.reagent)
    end
    if owned and ready then
      local place
      if t.hearth then
        place = inn and inn.continent and { map = inn.continent, wx = inn.wx, wy = inn.wy, name = inn.name }
      else
        local l = landings[id]
        if l then
          place = { map = l.continent, wx = l.wx, wy = l.wy }
        elseif t.continent and t.wx then
          place = { map = t.continent, wx = t.wx, wy = t.wy, wz = t.wz }
        end
      end
      if place then
        place.seconds, place.id = t.cast, id
        place.name = place.name or t.name
        out[#out + 1] = place
      end
    end
  end
  return out
end

-- Home: the way to the inn the hearth is bound to (as learned); every ready jump takes part.
function Route.Home()
  local h = db().char.hearth
  if not (h and h.continent) then
    B:Say(L["Hearth: inn unknown. Type /broute hearth while standing at your inn."])
    return false
  end
  return Route.ToPoint(h.continent, h.wx, h.wy, h.name or L["your inn"])
end

-- /broute teleports: the table with what this character has, what is ready, what was learned.
function Route.TeleportReport()
  local d = data()
  local ids = d and d:Each("teleport") or {}
  if #ids == 0 then
    B:Say(L["No teleport table in the data."])
    return
  end
  local landings = db().global.landings or {}
  for _, id in ipairs(ids) do
    local t = d:Get("teleport", id)
    local owned, ready, left =
      B.Compat.GetTeleportState(t.kind, t.kind == "spell" and t.spell or t.item, t.reagent)
    local state
    if owned == nil then
      state = L["unknown"]
    elseif not owned then
      state = L["not yours"]
    elseif ready then
      state = L["ready"]
    elseif ready == false and left then
      state = string.format(L["ready in %s"], Graph.FormatSeconds(left))
    elseif ready == false then
      state = L["not castable now"]
    else
      state = L["cooldown unknown"]
    end
    B:Say("%s: %s%s", t.name, state, landings[id] and (" - " .. L["landing learned"]) or "")
  end
end

-- The walk network of a continent from the `nav` pack, decoded once; nil without one.
function Route.Net(continent)
  if nets[continent] == nil then
    local d = data()
    local rec = d and d:Get("navnet", continent)
    nets[continent] = rec and Graph.DecodeNet(rec) or false
  end
  return nets[continent] or nil
end

function Route.Inputs(start, goal)
  local notes = {}
  local byContinent = {}
  for _, c in ipairs({ start and start.continent, goal and goal.continent }) do
    byContinent[c] = byContinent[c] or Route.Net(c)
  end
  return {
    nets = byContinent,
    start = start,
    goal = goal,
    flights = Route.Flights(),
    transports = Route.Transports(),
    hearth = Route.Hearth(notes),
    walkSpeed = db().char.maxSpeed or Graph.WALK_SPEED,
    flightTimes = Route.FlightTimes(),
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
-- The world graph (ADR 0026, W8): Route as a view on Data's `graph:Route`
-- ---------------------------------------------------------------------------------------------

local GRAPH_MODE = { taxi = "fly", hearth = "hearth", portal = "portal", teleport = "teleport" }
local FACTION_NAME = { A = "Alliance", H = "Horde" }

-- A graph key's node for the step list and the arrow: name and place.
local function graphNode(key, place)
  local node = place and { continent = place.map, wx = place.wx, wy = place.wy } or {}
  if type(key) ~= "string" then
    return node
  end
  local typ, rest = key:match("^([^:]+):(.+)$")
  if typ == "taxinode" then
    node.kind, node.ref = "flight", "flightpath:" .. rest
    node.name = B:Entity(node.ref):Name()
  elseif typ == "transport" then
    local id, stop = rest:match("^(.+):(%d+)$")
    local d = data()
    local r = id and d and d:Get("transport", tonumber(id) or id)
    local s = r and r.stops and r.stops[tonumber(stop)]
    node.kind, node.ref, node.name = "stop", "transport:" .. tostring(id), s and s[4] or (r and r.name)
    node.transport, node.stop = id, tonumber(stop) -- the departures (R26.6)
  else
    node.ref = key
    node.name = B:Entity(key):Name()
  end
  return node
end

local function pointPairs(list)
  local out = {}
  for _, p in ipairs(list or {}) do
    out[#out + 1] = { p.wx, p.wy }
  end
  return out
end

-- The graph's route in Route's shape (the step list, the path layer, the arrow and the following
-- read it): steps with Route's modes and nodes, walks with their legs; the straight joins at both
-- ends are approximate legs.
function Route.FromGraph(r, start, goal, notes)
  local steps = {}
  for _, s in ipairs(r.steps or {}) do
    local mode = GRAPH_MODE[s.mode] or (s.mode == "ride" and s.kind) or s.mode
    local step = {
      mode = mode,
      from = graphNode(s.from, s.fromPlace),
      to = graphNode(s.to, s.toPlace),
      seconds = s.seconds,
      yards = s.yards,
      wait = s.wait,
      jump = s.jump,
      approx = false,
    }
    if s.name and step.to then
      step.to.name = s.name -- a teleport's destination names the step's end
    end
    if mode == "walk" then
      step.legs = { { approx = false, points = pointPairs(s.points) } }
      step.approxYards = 0
      step.danger, step.elite = s.danger, s.elite -- R26.5
    end
    steps[#steps + 1] = step
  end
  local function join(step, a, b, atStart)
    local yards = Graph.Distance(a.wx, a.wy, b.wx, b.wy)
    if yards < 1 then
      return
    end
    local leg = { approx = true, points = { { a.wx, a.wy }, { b.wx, b.wy } } }
    if atStart then
      table.insert(step.legs, 1, leg)
    else
      step.legs[#step.legs + 1] = leg
    end
    step.yards = (step.yards or 0) + yards
    step.approxYards = (step.approxYards or 0) + yards
  end
  -- the network's first and last waypoints: where the straight joins from the start and to the
  -- goal meet the route; a route that begins or ends with a taxi or a ride gets a walk for them
  local first, last = steps[1], steps[#steps]
  if not first or first.mode ~= "walk" then
    local at = first and first.from or {}
    first = { mode = "walk", seconds = 0, yards = 0, legs = {}, approxYards = 0, from = at, to = at }
    table.insert(steps, 1, first)
    last = steps[#steps]
  end
  if last.mode ~= "walk" then
    last = { mode = "walk", seconds = 0, yards = 0, legs = {}, approxYards = 0, from = last.to, to = last.to }
    steps[#steps + 1] = last
  end
  local firstAt, lastAt = first.from, last.to
  first.from = { continent = start.continent, wx = start.wx, wy = start.wy }
  if firstAt and firstAt.wx then
    join(first, start, firstAt, true)
  end
  last.to = { continent = goal.continent, wx = goal.wx, wy = goal.wy, name = goal.name, ref = goal.ref }
  if lastAt and lastAt.wx then
    join(last, lastAt, goal, false)
  end
  for _, step in ipairs(steps) do
    if step.legs then
      step.approx = (step.approxYards or 0) > 0.5 * math.max(step.yards or 0, 1)
    end
  end
  for i = #steps, 1, -1 do -- a walk of under a yard is no step (as Route's planner)
    if steps[i].mode == "walk" and (steps[i].yards or 0) < 1 and #steps > 1 then
      table.remove(steps, i)
    end
  end
  local all = notes or {}
  for _, n in ipairs(r.notes or {}) do
    all[#all + 1] = n
  end
  return {
    seconds = r.seconds,
    steps = steps,
    start = start,
    goal = goal,
    notes = all,
    index = 1,
    graph = true,
  }
end

-- Plans from start to goal and calls back with the route (or nil): over the world graph when
-- its network holds the continents of both (across them over the rides, W8), else with Route's
-- planner (a build without the network), and with Route's planner too when the graph finds no way.
-- The kind of route the player chose (R26.5): fastest, safe or nocost.
function Route.Kind()
  local k = db().profile.routeKind
  return (k == "safe" or k == "nocost") and k or "fastest"
end

function Route.PlanAsync(start, goal, callback, kind)
  local g = graph()
  if not (g and g:Ready(start.continent) and g:Ready(goal.continent)) then
    callback(Route.Plan(start, goal))
    return
  end
  -- on foot (a ghost, Death.lua): no flight master, hearthstone or teleport serves it
  kind = goal.onFoot and "nocost" or kind or Route.Kind()
  local facts = B.Compat.GetPlayerFacts() or {}
  local notes = {}
  local hearth = not goal.onFoot and Route.Hearth(notes) or nil
  local known = {}
  for _, f in ipairs(goal.onFoot and {} or Route.Flights()) do
    known[f.id] = true
  end
  g:Route({ map = start.continent, wx = start.wx, wy = start.wy }, {
    map = goal.continent,
    wx = goal.wx,
    wy = goal.wy,
  }, {
    known = known,
    faction = FACTION_NAME[playerFaction() or ""],
    hearth = hearth and { map = hearth.continent, wx = hearth.wx, wy = hearth.wy } or nil,
    teleports = not goal.onFoot and Route.Teleports() or nil,
    speeds = { ground = db().char.maxSpeed or Graph.WALK_SPEED },
    profile = kind ~= "fastest" and kind or nil,
    level = facts.level,
  }, function(r)
    if r then
      local route = ns.Ferries.Adjust(Route.FromGraph(r, start, goal, notes)) -- exact ferry waits
      route.kind = kind
      callback(route)
    else
      callback(Route.Plan(start, goal))
    end
  end)
end

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
  local new = route ~= nil and route ~= active
  active = route
  if route then
    startTicker()
  else
    stopTicker()
  end
  -- a new route is meant to be seen: "show" switches the layer on in the map
  B:Fire("BASTIANS_LAYER_CHANGED", "route.path", new and "show" or nil)
  B:Fire("BASTIANS_ROUTE_CHANGED", route)
end

function Route.Clear()
  if active then
    Route.Set(nil)
  end
end

-- Route to an entity: the fastest of its places from where the player stands.
-- The area the hearthstone is bound to (GetBindLocation through Compat.GetHearthstone), found by
-- its name in the world data, as an entity ref; nil without a bind, the data or a match
-- (plan-second-wave.md S6: Gestures' "Route home").
function Route.HomeRef()
  local hearth = B.Compat.GetHearthstone and B.Compat.GetHearthstone()
  local name = hearth and hearth.bindName
  local d = B:GetService("data")
  if type(name) ~= "string" or name == "" or not (d and d.Find) then
    return nil
  end
  local wanted = string.lower(name)
  for _, hit in ipairs(d:Find("area", name, 5)) do
    if type(hit.name) == "string" and string.lower(hit.name) == wanted then
      return "area:" .. tostring(hit.id)
    end
  end
  return nil
end

function Route.To(ref)
  local start = playerPos()
  if not start then
    B:Say(L["No map position here (instance?)"])
    return false
  end
  local e = B:Entity(ref)
  local name = e:Name() or ref
  local goals = {}
  for i, loc in ipairs(e:Locations()) do
    if i > Route.MAX_LOCATIONS then
      break
    end
    local c, wx, wy = B.Coords.ToWorld(loc.map, loc.x, loc.y)
    if c then
      goals[#goals + 1] =
        { continent = c, wx = wx, wy = wy, name = name, ref = ref, map = loc.map, x = loc.x, y = loc.y }
    end
  end
  local best, waiting, answered = nil, #goals, false
  local function finish()
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
    Route.Alternatives(best, start)
    B:Say(
      L["Route to %s: %s, %d steps"] .. Route.VerdictSuffix(best),
      name,
      Graph.FormatSeconds(best.seconds),
      #best.steps
    )
    if db().profile.openWindow ~= false then
      W.Open()
    end
    return true
  end
  if waiting == 0 then
    return finish()
  end
  local result
  for _, goal in ipairs(goals) do
    Route.PlanAsync(start, goal, function(route)
      if route and (not best or route.seconds < best.seconds) then
        best = route
      end
      waiting = waiting - 1
      if waiting == 0 and not answered then
        answered = true
        result = finish()
      end
    end)
  end
  -- planned at once (Route's planner): the answer is known; over the graph it comes later
  if answered then
    return result
  end
  return true
end

-- Route to a world point (the map's right click, "Route here"): plans from the player, sets the
-- route. `opts.onFoot`: walking only (a ghost), one kind of route, kept by a re-route.
function Route.ToPoint(continent, wx, wy, name, opts)
  local start = playerPos()
  if not start then
    B:Say(L["No map position here (instance?)"])
    return false
  end
  name = name or L["the marked spot"]
  local onFoot = opts and opts.onFoot or nil
  local result
  local goal = { continent = continent, wx = wx, wy = wy, name = name, onFoot = onFoot }
  Route.PlanAsync(start, goal, function(route)
    if not route then
      B:Say(L["No route to %s"], name)
      result = false
      return
    end
    route.onFoot = onFoot
    Route.Set(route)
    if not onFoot then
      Route.Alternatives(route, start)
    end
    B:Say(
      L["Route to %s: %s, %d steps"] .. Route.VerdictSuffix(route),
      name,
      Graph.FormatSeconds(route.seconds),
      #route.steps
    )
    if db().profile.openWindow ~= false then
      W.Open()
    end
    result = true
  end)
  if result == nil then
    return true -- over the graph: the route comes in a moment
  end
  return result
end

-- A route through several stops (R26.4, route.md "Several stops"): stops = { { id, name, ref,
-- place = { map, wx, wy, wz }, after = { ids } } }. graph:Tour orders them; the legs become one
-- route whose steps know their stop (step.stop) and whose `tour` keeps the stops in order.
function Route.Tour(stops, name)
  local start = playerPos()
  if not start then
    B:Say(L["No map position here (instance?)"])
    return false
  end
  local g = graph()
  if not (g and g:Ready(start.continent)) then
    B:Say(L["Several stops need the route network of this continent."])
    return false
  end
  name = name or L["Tour"]
  local byId = {}
  for _, st in ipairs(stops or {}) do
    byId[st.id] = st
  end
  local facts = B.Compat.GetPlayerFacts() or {}
  local known = {}
  for _, f in ipairs(Route.Flights()) do
    known[f.id] = true
  end
  local kind = Route.Kind()
  g:Tour({ map = start.continent, wx = start.wx, wy = start.wy }, stops, {
    known = known,
    faction = FACTION_NAME[playerFaction() or ""],
    speeds = { ground = db().char.maxSpeed or Graph.WALK_SPEED },
    profile = kind ~= "fastest" and kind or nil,
    level = facts.level,
  }, function(t, why)
    if not (t and #t.order > 0) then
      B:Say(L["No route through the stops (%s)."], why or L["no way"])
      return
    end
    local steps, ordered, from = {}, {}, start
    for k, id in ipairs(t.order) do
      local stop = byId[id]
      local pl = stop.place
      local goal = {
        continent = pl.map,
        wx = pl.wx,
        wy = pl.wy,
        name = string.format("%d. %s", k, stop.name or "?"),
        ref = stop.ref,
      }
      for _, step in ipairs(Route.FromGraph(t.legs[k], from, goal, {}).steps) do
        step.stop = k
        steps[#steps + 1] = step
      end
      ordered[k] = stop
      from = { continent = pl.map, wx = pl.wx, wy = pl.wy }
    end
    ns.Ferries.Adjust({ steps = steps }) -- exact ferry waits along the tour (R26.6)
    local seconds = 0
    for _, step in ipairs(steps) do
      seconds = seconds + (step.seconds or 0)
    end
    local last = steps[#steps].to
    local route = {
      seconds = seconds,
      steps = steps,
      start = start,
      goal = { continent = last.continent, wx = last.wx, wy = last.wy, name = last.name, ref = last.ref },
      notes = {},
      index = 1,
      graph = true,
      kind = kind,
      tour = { name = name, stops = ordered },
    }
    local left = 0
    for _ in pairs(t.skipped or {}) do
      left = left + 1
    end
    if left > 0 then
      route.notes[1] = string.format(L["%d stops left out: another continent, or no way there."], left)
    end
    Route.Set(route)
    B:Say(L["%s: %d stops, %s"], name, #ordered, Graph.FormatSeconds(t.seconds))
    if db().profile.openWindow ~= false then
      W.Open()
    end
  end)
  return true
end

-- The stops of the active tour still ahead (the current step's stop on), with the needs already
-- met dropped: what a re-route plans again.
function Route.TourAhead()
  local tour = active and active.tour
  if not tour then
    return nil
  end
  local step = active.steps[active.index or 1]
  local k = step and step.stop or 1
  local done, ahead = {}, {}
  for i = 1, k - 1 do
    done[tour.stops[i].id] = true
  end
  for i = k, #tour.stops do
    local st = tour.stops[i]
    local after = {}
    for _, need in ipairs(st.after or {}) do
      if not done[need] then
        after[#after + 1] = need
      end
    end
    ahead[#ahead + 1] = { id = st.id, name = st.name, ref = st.ref, place = st.place, after = after }
  end
  return ahead
end

-- Whether places can be added to the route that runs: not to a ghost's way back (ADR 0062).
function Route.CanAdd()
  return active ~= nil and not active.onFoot
end

-- The stops a new one comes behind: a tour's still ahead, or the goal of a plain route.
function Route.StopsAhead()
  if not active then
    return {}
  end
  if active.tour then
    return Route.TourAhead()
  end
  local g = active.goal
  return {
    {
      id = "goal",
      name = g.name,
      ref = g.ref or active.ref,
      place = { map = g.continent, wx = g.wx, wy = g.wy },
    },
  }
end

-- One route through `new`, in that order; `keep`: behind the stops still ahead (ADR 0062).
function Route.AddStops(new, keep)
  local all = keep and Route.StopsAhead() or {}
  local last = all[#all]
  for _, st in ipairs(new) do
    st.after = last and { last.id } or nil
    all[#all + 1] = st
    last = st
  end
  return Route.Tour(all, keep and active and active.tour and active.tour.name or L["Waypoints"])
end

-- An entity behind the stops ahead: its place nearest the route's goal.
function Route.AddRef(ref)
  local e, g, best, bestYards = B:Entity(ref), active and active.goal, nil, math.huge
  for _, loc in ipairs(e:Locations()) do
    local c, wx, wy = B.Coords.ToWorld(loc.map, loc.x, loc.y)
    if c then
      local yards = g and c == g.continent and Graph.Distance(g.wx, g.wy, wx, wy) or math.huge
      if not best or yards < bestYards then
        best, bestYards = { map = c, wx = wx, wy = wy }, yards
      end
    end
  end
  if not best then
    B:Say(L["No route to %s"], e:Name() or ref)
    return false
  end
  addCount = addCount + 1
  return Route.AddStops(
    { { id = "add:" .. addCount, name = e:Name() or ref, ref = ref, place = best } },
    true
  )
end

-- A point of the map behind the stops ahead.
function Route.AddPoint(continent, wx, wy, name)
  addCount = addCount + 1
  local place = { map = continent, wx = wx, wy = wy }
  return Route.AddStops(
    { { id = "add:" .. addCount, name = name or L["the marked spot"], place = place } },
    true
  )
end

-- The other kinds of the route just set, planned in the background (R26.5): route.alternatives =
-- { [kind] = route } shared by all of them; the step list shows them as they come. Only over the
-- graph (Route's own planner knows no kinds).
function Route.Alternatives(route, start)
  if not (route and route.graph and route.kind and start) then
    return
  end
  local alts = { [route.kind] = route }
  route.alternatives = alts
  for _, kind in ipairs(Route.KINDS) do
    if kind ~= route.kind then
      Route.PlanAsync(start, route.goal, function(alt)
        if alt and alt.graph and route.alternatives == alts then
          alt.ref, alt.alternatives = route.ref, alts
          alts[kind] = alt
          W.Schedule()
        end
      end, kind)
    end
  end
end

-- Switches to another kind of the active route and keeps the kind as the default.
function Route.UseKind(kind)
  db().profile.routeKind = kind
  local alt = active and active.alternatives and active.alternatives[kind]
  if alt and alt ~= active then
    alt.index = 1
    Route.Set(alt)
    return true
  end
  return false
end

-- A route to a member of the group (R26.9): a name, or 1 to 4 for the party's order.
function Route.ToMember(which)
  which = strtrim(which or "")
  local units = B.Compat.GroupUnits()
  local member = units[tonumber(which) or 0]
  for _, m in ipairs(units) do
    if not member and m.name:lower() == which:lower() then
      member = m
    end
  end
  if not member then
    B:Say(L["No member of your group called %s."], which)
    return false
  end
  local c, wx, wy = B.Coords.Unit(member.unit)
  if not c then
    B:Say(L["%s has no map position for you (another zone or an instance)."], member.name)
    return false
  end
  return Route.ToPoint(c, wx, wy, member.name)
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
  if active.tour then -- the stops still ahead, ordered again from here (R26.4)
    return Route.Tour(Route.TourAhead(), active.tour.name)
  end
  local was = active
  local goal = was.goal
  if was.onFoot then
    goal = { continent = goal.continent, wx = goal.wx, wy = goal.wy, name = goal.name, onFoot = true }
  end
  local result
  Route.PlanAsync(start, goal, function(route)
    if active ~= was then
      result = false
      return -- the player chose another route meanwhile
    end
    if not route then
      -- a failed re-route keeps the route the player has (a route that
      -- vanished after two seconds); the next check tries again after the cooldown
      B:Say(L["Could not re-route to %s from here; keeping the route."], goal.name or "")
      result = false
      return
    end
    route.ref = was.ref
    route.reason = reason
    route.onFoot = was.onFoot
    Route.Set(route)
    result = true
  end, was.kind)
  if result == nil then
    return true
  end
  return result
end

-- Learn the mount speed from the fastest ground speed seen.
local function learnSpeed()
  local speed, _, onTaxi = B.Compat.GetMoveSpeed()
  if not speed then
    return -- the client keeps it secret right now (Forever 23.10.2026)
  end
  if not onTaxi and speed > (db().char.maxSpeed or Graph.WALK_SPEED) and speed <= Route.MAX_LEARNED_SPEED then
    db().char.maxSpeed = speed
  end
end

-- Once a second while a route is active: step completion and the off-course check.
tick = function()
  if not active then
    stopTicker()
    return
  end
  learnSpeed()
  ns.Death.Sync() -- the case of the stale arrow: a route runs, and the character may have died
  if not active or ns.Death.Silenced() then
    return -- life cleared the way back, or a route the death made wrong: no step, no re-route
  end
  local pos = playerPos()
  if not pos then
    return
  end
  local step = active.steps[active.index or 1]
  if not step then
    return
  end
  ns.Ferries.Observe(step, pos) -- a boat or zeppelin leaving with the character: its loop (R26.6)
  if step.to.continent == pos.continent then
    if Graph.Distance(pos.wx, pos.wy, step.to.wx, step.to.wy) <= Route.ARRIVE_YARDS then
      active.index = (active.index or 1) + 1
      if active.index > #active.steps then
        -- the arrival: a chat line, or the voice (Core's Words, plan-launch-review R5.3)
        B:Tell(mod, "arrival", string.format(L["You have arrived: %s"], active.goal.name or ""), function(t)
          B:Say("%s", t)
        end)
        Route.Clear()
      else
        local following = active.steps[active.index]
        if following then
          -- the next step, spoken for the Wanderer; the text form is the step list and the arrow
          B:Tell(mod, "step", string.format(L["Next: %s"], Graph.StepText(following, L)), function() end)
        end
        B:Fire("BASTIANS_ROUTE_CHANGED", active)
      end
      return
    end
  end
  ns.Arrow.Refresh() -- the own arrow turns at least once a second while a route is active (S6)
  if step.mode == "walk" and step.from.continent == pos.continent then
    local index = active.index or 1
    local last = active.progress
    local first = last and last.step == index and last.i - 2 or 1
    local p = Graph.Progress(step, pos.wx, pos.wy, first)
    if not p then
      return
    end
    if p.off <= Route.OFF_COURSE_YARDS then
      offTicks = 0
      -- the car navigator: the walked part goes, the line starts where the player is
      if not (last and last.step == index) or math.abs(p.along - last.along) >= Route.TRIM_YARDS then
        p.step = index
        active.progress = p
        B:Fire("BASTIANS_LAYER_CHANGED", "route.path")
        W.Schedule() -- the remaining time
      end
    else
      offTicks = offTicks + 1
      if offTicks >= Route.OFF_COURSE_TICKS and GetTime() - lastReplan >= Route.REPLAN_COOLDOWN then
        offTicks = 0
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
        -- a walk draws its legs (network paths solid, straight legs dashed); others their ends;
        -- the current walk only from the player on (the car navigator)
        local walked = active.progress
        local legs = (
          i == (active.index or 1)
          and walked
          and walked.step == i
          and Graph.RemainingLegs(step, walked)
        )
          or step.legs
          or {
            {
              approx = step.approx and true or false,
              points = { { step.from.wx, step.from.wy }, { step.to.wx, step.to.wy } },
            },
          }
        for _, leg in ipairs(legs) do
          if points and leg.approx ~= approx then
            local last = points[#points]
            flush()
            points = { last }
          end
          approx = leg.approx
          points = points or { leg.points[1] }
          for p = 2, #leg.points do
            points[#points + 1] = leg.points[p]
          end
        end
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
  -- a tour's stops before the last, numbered (R26.4); the last is the goal pin above
  local tour = active.tour
  for k, st in ipairs(tour and tour.stops or {}) do
    if k < #tour.stops and st.place.map == view.continent then
      pins[#pins + 1] = {
        ref = st.ref,
        wx = st.place.wx,
        wy = st.place.wy,
        icon = B.UI.IconTexture("route"),
        label = string.format("%d. %s", k, st.name or "?"),
        priority = 93,
        cluster = false,
        size = 20,
      }
    end
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

-- A teleport of the table was cast (its spell, or the spell of its item or toy): its landing is
-- read after the loading screen, or a few seconds later when there was none (R26.7).
function Route.TeleportCast(spellID)
  local d = data()
  if not (d and spellID) then
    return nil
  end
  for _, id in ipairs(d:Each("teleport")) do
    local t = d:Get("teleport", id)
    local cast = t and (t.kind == "spell" and t.spell or (t.item and B.Compat.GetItemSpell(t.item)))
    if cast == spellID and not t.hearth then
      teleporting = { id = id, at = GetTime(), from = playerPos() }
      C_Timer.After(Route.LANDING_WAIT, function()
        local pos, from = playerPos(), teleporting and teleporting.from
        if pos and from and teleporting.id == id then
          local far = pos.continent ~= from.continent
            or Graph.Distance(pos.wx, pos.wy, from.wx, from.wy) >= Route.LANDING_MOVED
          if far then
            Route.LearnLanding()
          end
        end
      end)
      return id
    end
  end
  return nil
end

-- Keeps where the character stands as the landing of the teleport just cast (account wide).
function Route.LearnLanding()
  local pos = playerPos()
  if not (teleporting and pos and mod:IsEnabled()) then
    return nil
  end
  local landings = db().global.landings or {}
  db().global.landings = landings
  landings[teleporting.id] = { continent = pos.continent, wx = pos.wx, wy = pos.wy, at = time() }
  local id = teleporting.id
  teleporting = nil
  return id
end

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
Graph.TaxiIDFor = flightIDFor

-- The open taxi map, for the flight hook (the flight masters themselves Data's graph learns).
local function onTaxiMapOpened()
  local nodes = B.Compat.GetTaxiNodes()
  taxiCurrent = nil
  for _, n in ipairs(nodes) do
    if n.state == "current" then
      taxiCurrent = n
    end
  end
  taxiShown = nodes
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
  ns.Flight.End()
  local seconds = GetTime() - flight.startedAt
  local to = flight.to or nearestFlight(playerPos())
  local g = graph()
  if g and flight.from and to and seconds > 5 then
    -- the direction flown only: the path's length times the other way better than a mirror
    -- (Ironforge to Stormwind 211 s, back 260 s, route.md)
    g:Learn({ kind = "taxi", from = flight.from, to = to, seconds = math.floor(seconds + 0.5) })
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
    ns.Flight.Begin(taxiFlight) -- the flight bar (A4.1)
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
  local g = graph()
  local char, learned = g and g:Character(), g and g:Learned()
  for _ in pairs(char and char.taxi or {}) do
    known = known + 1
  end
  for _ in pairs(learned and learned.taxi or {}) do
    flights = flights + 1
  end
  parts[#parts + 1] = string.format(L["%d flight masters learned, %d flight times measured"], known, flights)
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
  data = { "world", "nav" },
  optional = { "Bastians_Data", "Bastians_Quests", "Bastians_Map" },
  defaults = {
    profile = {
      network = "known",
      openWindow = true,
      corpseRoute = true,
      routeKind = "fastest",
      wayAdd = false, -- /way while a route runs: false a new route, true behind its stops (ADR 0062)
      wayOverOwner = false, -- another addon has /way: true hands it to Route
      window = {},
      tree = {},
    },
    char = { known = {}, hearth = false, maxSpeed = false },
    global = { known = {}, flightTimes = {}, landings = {} },
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
      key = "corpseRoute",
      label = L["Route back to the corpse after releasing"],
    },
    {
      type = "select",
      key = "routeKind",
      label = L["Route by default"],
      values = function()
        return { fastest = L["Fastest"], safe = L["Safest"], nocost = L["No flights"] }
      end,
    },
    {
      type = "toggle",
      key = "arrow",
      label = L["Show an arrow to the next step while a route is active"],
      default = true,
    },
    {
      type = "toggle",
      key = "flightBar",
      label = L["Show a flight bar with the time left while flying"],
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
    db().global.landings = db().global.landings or {} -- teleports' landings (R26.7)
    nameToID = nil
    moveLearned()
    -- the map's right click on empty ground opens the zone's menu with the point in the context
    B:RegisterAction(self, {
      id = "route.here",
      main = true, -- a button of the sheet (ADR 0054)
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
      main = {
        "npc",
        "object",
        "node",
        "quest",
        "chain", -- to the step the player is on
        "dungeon",
        "spot",
        "area",
        "entrance",
        "flightpath",
        "transport",
      }, -- a button of the sheet (ADR 0054)
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
    -- add to the running route instead of a new one
    B:RegisterAction(self, {
      id = "route.add",
      label = L["Add to route"],
      icon = B.UI.IconTexture("route"),
      types = "*",
      order = 16,
      when = function(ref, ctx)
        if not Route.CanAdd() or (ctx and ctx.point) then
          return false
        end
        for _, loc in ipairs(B:Entity(ref):Locations()) do
          if B.Coords.ToWorld(loc.map, loc.x, loc.y) then
            return true
          end
        end
        return false
      end,
      run = function(ref)
        Route.AddRef(ref)
      end,
    })
    B:RegisterAction(self, {
      id = "route.addhere",
      label = L["Add to route"],
      icon = B.UI.IconTexture("route"),
      types = { "zone" },
      order = 15,
      when = function(_, ctx)
        return Route.CanAdd() and ctx ~= nil and type(ctx.point) == "table"
      end,
      run = function(_, ctx)
        local pt = ctx.point
        Route.AddPoint(pt[1], pt[2], pt[3], pt[4])
      end,
    })
    -- Gestures' "Route home" (plan-second-wave.md S6): offered to the ring only (ctx.source)
    B:RegisterAction(self, {
      id = "route.home",
      label = L["Route home"],
      icon = B.UI.IconTexture("innkeeper"),
      types = "*",
      order = 16,
      when = function(_, ctx)
        return ctx ~= nil and ctx.source == "gestures" and Route.HomeRef() ~= nil
      end,
      run = function()
        local ref = Route.HomeRef()
        if ref then
          Route.To(ref)
        end
      end,
    })
    B:RegisterMapLayer(self, {
      id = "route.path",
      icon = "route", -- the layer bar shows its icon (R27.8)
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
      elseif unit == "player" then
        Route.TeleportCast(spellID)
      end
    end)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
      ns.Death.OnEnteringWorld() -- alive after a login: an old corpse is gone (R26.8)
      if teleporting and GetTime() - teleporting.at < 60 then
        C_Timer.After(1, Route.LearnLanding)
      end
      if hearthingAt and GetTime() - hearthingAt < 60 then
        hearthingAt = nil
        C_Timer.After(1, function()
          local pos = playerPos()
          if pos and mod:IsEnabled() then
            local hs = B.Compat.GetHearthstone()
            db().char.hearth = { name = hs.bindName, continent = pos.continent, wx = pos.wx, wy = pos.wy }
          end
        end)
      end
    end)
    pcall(self.RegisterEvent, self, "HEARTHSTONE_BOUND", function()
      Route.SetHearthHere()
    end)
    self:On("BASTIANS_DATA_LOADED", function()
      nameToID = nil
      nets = {}
    end)
    self:On("BASTIANS_SETTING_CHANGED", function(_, _, name, key)
      if name == self.name and key == "arrow" then
        ns.Arrow.Update()
      end
    end)
    -- the clear-screen key (plan-round4 F1, plan-launch-review R5.6): the arrow follows, only while
    -- the page "Hidden by the key" ticks Route; the key's return always passes
    self:On("BASTIANS_SUITE_HIDDEN", function(_, _, hidden)
      local Screen = B.UI.Screen
      if hidden and Screen and Screen.Hides and not Screen.Hides("Route") then
        return
      end
      ns.Arrow.HideByKey(hidden == true)
      ns.Flight.HideByKey(hidden == true)
    end)
    hookTaxi()
    W.Register(self)
    ns.Arrow.Register(self) -- the arrow to the next step (S6)
    ns.Flight.Register(self) -- the flight bar (A4.1)
    ns.Death.Register(self) -- the place of death and the way back (R26.8)
    ns.Way.Register(self) -- the /way command (ADR 0062)
    ns.Ferries.Register(self) -- the departures of boats and zeppelins (R26.6)
    ns.Explore.Register(self) -- what is worth doing nearby (R26.11)
    ns.Feed.Register(self) -- the broker displays' feed (ADR 0043)
    -- the route service (core-contracts §11): other apps ask for a route without calling Route
    B:ProvideService(self, "route", {
      Tour = function(_, stops, name)
        return Route.Tour(stops, name)
      end,
      To = function(_, ref)
        return Route.To(ref)
      end,
      -- a point on a continent (world yards): the Strategies plates' "Route there" (29.10.2026)
      ToPoint = function(_, continent, wx, wy, name)
        return Route.ToPoint(continent, wx, wy, name)
      end,
      -- the active route in plain values (the public API's Route, ADR 0044); nil without one
      Current = function()
        local r = Route.Active()
        if not r then
          return nil
        end
        local goal = r.goal or {}
        return {
          goal = r.tour and r.tour.name or goal.name,
          continent = goal.continent,
          wx = goal.wx,
          wy = goal.wy,
          seconds = Graph.Remaining(r),
          step = r.index or 1,
          steps = #r.steps,
        }
      end,
    }, { priority = 100 })
  end,
  OnDisable = function()
    Route.Clear()
    W.Hide()
    ns.Death.Unregister()
    ns.Way.Unregister()
    ns.Arrow.Unregister()
    ns.Flight.Unregister()
  end,
})
ns.mod = mod
mod.Arrow = ns.Arrow -- the arrow to the next step (Arrow.lua, S6)
mod.Flight = ns.Flight -- the flight bar (Flight.lua, A4.1)
mod.Route, mod.Graph, mod.Window = Route, Graph, W

BINDING_HEADER_BASTIANS_ROUTE = "Bastian's Route" -- one header per addon (plan-launch-review I4)
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
  elseif cmd == "corpse" then
    ns.Death.RouteBack()
  elseif cmd == "death" then
    ns.Death.Report()
  elseif cmd == "home" then
    Route.Home()
  elseif cmd == "member" then
    Route.ToMember(arg)
  elseif cmd == "teleports" then
    Route.TeleportReport()
  elseif cmd == "ferries" then
    ns.Ferries.Report()
  elseif cmd == "explore" then
    ns.Explore.Open()
  elseif cmd == "to" and arg ~= "" then
    Route.To(arg)
  else
    B:Say(
      "/broute [clear | corpse | death | explore | ferries | hearth | home | member <name> | replan | "
        .. "teleports | to <type:id>]"
    )
  end
end
