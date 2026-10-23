-- The planner (route.md "Graph"): pure. Nodes are the start, the goal, the usable flight masters, the
-- stops of every transport and the hearth target; edges are straight walks ("approx") between nodes of
-- one continent, flights between flight masters (learned duration or distance at flight speed),
-- transport rides (ride plus the expected wait) and the hearthstone. Costs are seconds; the search is
-- Dijkstra over a dense graph of at most a few hundred nodes, which runs in a few milliseconds.
local _, ns = ...

local Graph = {}
ns.Graph = Graph

Graph.WALK_SPEED = 7 -- yards per second on foot (Classic run speed); learned mount speeds replace it
Graph.FLY_SPEED = 32 -- taxi speed in yards per second (assumed; learned durations replace the estimate)
Graph.FLY_FACTOR = 1.25 -- flight paths detour: straight distance times this
Graph.BOARDING = 8 -- seconds to talk to the flight master and lift off
Graph.RIDE_SPEED = 12 -- yards per second for a boat or zeppelin when the ride time is unknown
Graph.WAIT_DEFAULT = 90 -- expected wait at a dock when the loop time is unknown
Graph.HEARTH_CAST = 10
Graph.PORTAL_SECONDS = 3

local sqrt, floor, huge = math.sqrt, math.floor, math.huge

local function dist(a, b)
  local dx, dy = a.wx - b.wx, a.wy - b.wy
  return sqrt(dx * dx + dy * dy)
end
Graph.Distance = function(ax, ay, bx, by)
  local dx, dy = ax - bx, ay - by
  return sqrt(dx * dx + dy * dy)
end

-- Compass heading of the way from a to b: north is +wx, west is +wy (coordinates.md).
local HEADINGS = { "N", "NW", "W", "SW", "S", "SE", "E", "NE" }
function Graph.Heading(dwx, dwy)
  if dwx == 0 and dwy == 0 then
    return ""
  end
  local angle = math.atan2(dwy, dwx) -- 0 = north, positive towards west
  local sector = floor(angle / (math.pi / 4) + 0.5) % 8
  return HEADINGS[sector + 1]
end

-- "0:54", "4:12", "1h 02"
function Graph.FormatSeconds(seconds)
  seconds = floor((seconds or 0) + 0.5)
  if seconds >= 3600 then
    return string.format("%dh %02d", floor(seconds / 3600), floor((seconds % 3600) / 60))
  end
  return string.format("%d:%02d", floor(seconds / 60), seconds % 60)
end

-- The flight key of two flight master ids, as the learned table stores it.
function Graph.FlightKey(fromID, toID)
  return tostring(fromID) .. ">" .. tostring(toID)
end

-- ---------------------------------------------------------------------------------------------
-- Nodes and edges
-- ---------------------------------------------------------------------------------------------

local function node(kind, src, extra)
  local n = {
    kind = kind,
    continent = src.continent,
    wx = src.wx,
    wy = src.wy,
    name = src.name,
    id = src.id,
    ref = src.ref,
  }
  if extra then
    for k, v in pairs(extra) do
      n[k] = v
    end
  end
  return n
end

-- Build the node list: 1 = start, 2 = goal, then flights, stops, hearth.
local function buildNodes(g)
  local nodes = { node("start", g.start), node("goal", g.goal) }
  for _, f in ipairs(g.flights or {}) do
    nodes[#nodes + 1] = node("flight", f, { ref = "flightpath:" .. tostring(f.id) })
  end
  for _, t in ipairs(g.transports or {}) do
    local first
    for i, s in ipairs(t.stops or {}) do
      local n = node(
        "stop",
        { continent = s.continent, wx = s.wx, wy = s.wy, name = s.label or t.name, id = t.id },
        { transport = t, stopIndex = i, ref = "transport:" .. tostring(t.id) }
      )
      nodes[#nodes + 1] = n
      if i == 1 then
        first = #nodes
      end
      n.firstIndex = first
    end
  end
  if g.hearth then
    nodes[#nodes + 1] = node("hearth", g.hearth)
    nodes[#nodes].index = #nodes
  end
  for i, n in ipairs(nodes) do
    n.index = i
  end
  return nodes
end

-- Seconds of a transport ride between two adjacent stops.
local function rideSeconds(t, a, b)
  if t.kind == "portal" then
    return t.ride or Graph.PORTAL_SECONDS, 0
  end
  local ride = t.ride or dist(a, b) / Graph.RIDE_SPEED
  local wait = t.cycle and t.cycle / 2 or Graph.WAIT_DEFAULT
  return ride, wait
end

-- Relaxes every edge out of node u through `relax(v, seconds, mode, approx, yards, wait, jump)`.
-- No edge tables are built: the planner runs once per plan over a dense graph, so allocations are
-- what would cost time.
local function relaxEdges(g, nodes, u, walkSpeed, flySpeed, relax)
  local flightTimes = g.flightTimes
  local uIsFlight = u.kind == "flight"
  local ux, uy, uc = u.wx, u.wy, u.continent
  for i = 1, #nodes do
    local v = nodes[i]
    if v ~= u and v.kind ~= "start" and v.kind ~= "hearth" and v.continent == uc then
      local dx, dy = ux - v.wx, uy - v.wy
      local d = sqrt(dx * dx + dy * dy)
      relax(i, d / walkSpeed, "walk", true, d)
      if uIsFlight and v.kind == "flight" then
        local learned = flightTimes and flightTimes[Graph.FlightKey(u.id, v.id)]
        relax(i, learned or (d * Graph.FLY_FACTOR / flySpeed + Graph.BOARDING), "fly", not learned, d)
      end
    end
  end
  if u.kind == "stop" then
    local t = u.transport
    for _, step in ipairs({ -1, 1 }) do
      local v = nodes[u.index + step]
      if v and v.kind == "stop" and v.transport == t and v.stopIndex == u.stopIndex + step then
        local ride, wait = rideSeconds(t, u, v)
        relax(v.index, ride + wait, t.kind, not t.verified, dist(u, v), wait, t.kind == "portal")
      end
    end
  end
  if g.hearth and u.kind ~= "hearth" then
    local h = nodes[#nodes]
    if h.kind == "hearth" then
      relax(h.index, Graph.HEARTH_CAST, "hearth", false, nil, nil, true)
    end
  end
end

-- ---------------------------------------------------------------------------------------------
-- Search
-- ---------------------------------------------------------------------------------------------

-- g = { start = { continent, wx, wy }, goal = { continent, wx, wy, name }, flights = { { id, name,
-- continent, wx, wy } }, transports = { { id, name, kind, stops = { { continent, wx, wy, label } },
-- ride, cycle, verified } }, hearth = { continent, wx, wy, name } or nil (only when ready),
-- walkSpeed, flySpeed, flightTimes = { ["from>to"] = seconds } }.
-- Returns { seconds, steps = { { mode, from, to, seconds, approx, yards, jump } }, start, goal } or nil.
function Graph.Plan(g)
  if not (g and g.start and g.goal and g.start.continent and g.goal.continent) then
    return nil
  end
  local walkSpeed = g.walkSpeed or Graph.WALK_SPEED
  local flySpeed = g.flySpeed or Graph.FLY_SPEED
  local nodes = buildNodes(g)
  local n = #nodes
  local best, via, done = {}, {}, {}
  for i = 1, n do
    best[i] = huge
  end
  best[1] = 0
  local u, ub
  local function relax(v, seconds, mode, approx, yards, wait, jump)
    local cost = ub + seconds
    if cost < best[v] then
      best[v] = cost
      local e = via[v]
      if not e then
        e = {}
        via[v] = e
      end
      e.from, e.seconds, e.mode, e.approx, e.yards, e.wait, e.jump =
        u, seconds, mode, approx, yards, wait, jump
    end
  end
  for _ = 1, n do
    u, ub = nil, huge
    for i = 1, n do
      if not done[i] and best[i] < ub then
        u, ub = i, best[i]
      end
    end
    if not u or u == 2 then
      break
    end
    done[u] = true
    relaxEdges(g, nodes, nodes[u], walkSpeed, flySpeed, relax)
  end
  if best[2] == huge then
    return nil
  end
  local steps = {}
  local at = 2
  while at ~= 1 do
    local e = via[at]
    table.insert(steps, 1, {
      mode = e.mode,
      from = nodes[e.from],
      to = nodes[at],
      seconds = e.seconds,
      approx = e.approx,
      yards = e.yards,
      wait = e.wait,
      jump = e.jump,
    })
    at = e.from
  end
  -- a walk of under a yard (the start is a node, or two nodes share a place) is no step
  for i = #steps, 1, -1 do
    if steps[i].mode == "walk" and (steps[i].yards or 0) < 1 and #steps > 1 then
      table.remove(steps, i)
    end
  end
  return { seconds = best[2], steps = steps, start = g.start, goal = g.goal }
end

-- ---------------------------------------------------------------------------------------------
-- Text
-- ---------------------------------------------------------------------------------------------

local MODE_VERBS = {
  walk = "Go",
  fly = "Fly",
  boat = "Take the boat",
  zeppelin = "Take the zeppelin",
  tram = "Take the tram",
  portal = "Take the portal",
  hearth = "Hearth",
}
Graph.MODE_VERBS = MODE_VERBS

-- "Fly to Sentinel Hill, Westfall", "Go 380 yd SE to Hogger (approx)". `locale` (a table or a
-- function) translates the fixed words.
function Graph.StepText(step, locale)
  local L
  if type(locale) == "table" then
    L = function(s)
      return locale[s]
    end
  else
    L = locale or function(s)
      return s
    end
  end
  local verb = L(MODE_VERBS[step.mode] or step.mode)
  local target = step.to.name or L("the target")
  if step.mode == "walk" then
    local yards = floor((step.yards or 0) + 0.5)
    local heading = Graph.Heading(step.to.wx - step.from.wx, step.to.wy - step.from.wy)
    local text = string.format("%s %d %s %s %s %s", verb, yards, L("yd"), heading, L("to"), target)
    return step.approx and (text .. " (" .. L("approx") .. ")") or text
  end
  local text = string.format("%s %s %s", verb, L("to"), target)
  if step.mode ~= "hearth" and step.approx then
    text = text .. " (" .. L("approx") .. ")"
  end
  return text
end

-- The dominant mode of a route: "walk" when it only walks, else the slowest non-walk mode, "mixed"
-- when several.
function Graph.Mode(route)
  local seen, modes = {}, 0
  for _, s in ipairs(route and route.steps or {}) do
    if s.mode ~= "walk" and not seen[s.mode] then
      seen[s.mode] = true
      modes = modes + 1
    end
  end
  if modes == 0 then
    return "walk"
  elseif modes == 1 then
    return (next(seen))
  end
  return "mixed"
end

-- Distance in yards from point p to the segment a-b (same continent assumed).
function Graph.SegmentDistance(px, py, ax, ay, bx, by)
  local vx, vy = bx - ax, by - ay
  local len2 = vx * vx + vy * vy
  local t = 0
  if len2 > 0 then
    t = ((px - ax) * vx + (py - ay) * vy) / len2
    if t < 0 then
      t = 0
    elseif t > 1 then
      t = 1
    end
  end
  return Graph.Distance(px, py, ax + t * vx, ay + t * vy)
end
