-- The planner (route.md "Graph"): pure. Nodes are the start, the goal, the usable flight masters, the
-- stops of every transport and the hearth target; edges are straight walks ("approx") between nodes of
-- one continent, flights between flight masters (learned duration or distance at flight speed),
-- transport rides (ride plus the expected wait) and the hearthstone. Costs are seconds; the search is
-- Dijkstra with a heap. Where a continent has a walk network (route.md "Walk network", ADR 0025), its
-- nodes join the graph and walking follows its edges: the start, the goal and every node the network
-- does not hold join its nearest nodes by short straight legs ("approx").
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
Graph.SWIM_SPEED = 4.7 -- yards per second in water (assumed; a mount does not swim faster)
Graph.JOIN_YARDS = 600 -- a node off the walk network joins its nearest network nodes within this
Graph.JOIN_COUNT = 4
Graph.DIRECT_YARDS = 200 -- two places this close may walk straight even on a network continent
Graph.BUCKET = 300 -- yards per bucket of the nearest-node lookup

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

-- The route's verdict (route.md "The verdict", catalog review A4.3, 07.11.2026), pure: the worst
-- walk step's creatures against the character's level, an elite counting 3 levels more. "risky"
-- from RISKY_LEVELS above the character (the step's own "Careful" line), "careful" from
-- CAREFUL_LEVELS (creatures that still attack), "safe" below; nil when no step knows a creature
-- level or the character's level is unknown (unknown is not safe).
Graph.RISKY_LEVELS = 3
Graph.CAREFUL_LEVELS = -2
Graph.VERDICT_WORDS = { safe = "Safe trip", careful = "Watch out", risky = "Risky trip" }
Graph.VERDICT_TOKENS = { safe = "good", careful = "warn", risky = "bad" }

function Graph.Verdict(route, playerLevel)
  if not (route and route.steps and playerLevel) then
    return nil
  end
  local worst
  for _, step in ipairs(route.steps) do
    if step.danger then
      local d = step.danger - playerLevel + (step.elite and 3 or 0)
      if not worst or d > worst then
        worst = d
      end
    end
  end
  if worst == nil then
    return nil
  end
  if worst >= Graph.RISKY_LEVELS then
    return "risky"
  elseif worst >= Graph.CAREFUL_LEVELS then
    return "careful"
  end
  return "safe"
end

-- The verdict's words in the chat and the window; "" when there is none.
function Graph.VerdictText(route, playerLevel, L)
  local verdict = Graph.Verdict(route, playerLevel)
  return verdict and L[Graph.VERDICT_WORDS[verdict]] or "", verdict
end

-- The flight key of two flight master ids, as the learned table stores it.
function Graph.FlightKey(fromID, toID)
  return tostring(fromID) .. ">" .. tostring(toID)
end

-- ---------------------------------------------------------------------------------------------
-- The walk network (route.md "Walk network")
-- ---------------------------------------------------------------------------------------------

-- A `navnet` record decoded once: { n, x, y, adj = { [node] = { other, edge, other, edge, ... } },
-- len, swim, ea, eb (per edge), key = { ["flightpath:2"] = node }, buckets, paths }.
function Graph.DecodeNet(rec)
  if not (rec and type(rec.nodes) == "string" and type(rec.edges) == "string") then
    return nil
  end
  local x, y = {}, {}
  for a, b in string.gmatch(rec.nodes, "([^,;]+),([^;]+)") do
    x[#x + 1], y[#y + 1] = tonumber(a), tonumber(b)
  end
  local n = #x
  local adj, len, swim, ea, eb = {}, {}, {}, {}, {}
  for i = 1, n do
    adj[i] = {}
  end
  local e = 0
  for a, b, l, w in string.gmatch(rec.edges, "(%d+),(%d+),([^,]+),([^;]+)") do
    a, b = tonumber(a), tonumber(b)
    local la, lb = adj[a], adj[b]
    if la and lb then
      e = e + 1
      ea[e], eb[e], len[e], swim[e] = a, b, tonumber(l), tonumber(w)
      la[#la + 1], la[#la + 2] = b, e
      lb[#lb + 1], lb[#lb + 2] = a, e
    end
  end
  local key = {}
  for i, k in pairs(rec.keys or {}) do
    key[k] = i
  end
  local buckets, size = {}, Graph.BUCKET
  for i = 1, n do
    local bk = floor(x[i] / size) .. ":" .. floor(y[i] / size)
    local list = buckets[bk]
    if not list then
      list = {}
      buckets[bk] = list
    end
    list[#list + 1] = i
  end
  return {
    n = n,
    x = x,
    y = y,
    adj = adj,
    len = len,
    swim = swim,
    ea = ea,
    eb = eb,
    key = key,
    buckets = buckets,
    paths = rec.paths or {},
  }
end

-- The `count` nearest network nodes within `radius` yards: { { node, yards }, ... }, nearest first.
function Graph.NearestNodes(net, wx, wy, radius, count)
  local size = Graph.BUCKET
  local r = math.ceil(radius / size)
  local bx, by = floor(wx / size), floor(wy / size)
  local found = {}
  for i = bx - r, bx + r do
    for j = by - r, by + r do
      local list = net.buckets[i .. ":" .. j]
      if list then
        for _, k in ipairs(list) do
          local dx, dy = net.x[k] - wx, net.y[k] - wy
          local d = sqrt(dx * dx + dy * dy)
          if d <= radius then
            found[#found + 1] = { k, d }
          end
        end
      end
    end
  end
  table.sort(found, function(a, b)
    if a[2] ~= b[2] then
      return a[2] < b[2]
    end
    return a[1] < b[1]
  end)
  for i = #found, (count or #found) + 1, -1 do
    found[i] = nil
  end
  return found
end

-- The points of network edge `e` walked from node `from`: { { wx, wy }, ... } with both ends.
function Graph.EdgePoints(net, e, from)
  local inner = {}
  local text = net.paths[e]
  if text then
    for a, b in string.gmatch(text, "([^,;]+),([^;]+)") do
      inner[#inner + 1] = { tonumber(a), tonumber(b) }
    end
  end
  local forward = net.ea[e] == from
  local to = forward and net.eb[e] or net.ea[e]
  local pts = { { net.x[from], net.y[from] } }
  if forward then
    for i = 1, #inner do
      pts[#pts + 1] = inner[i]
    end
  else
    for i = #inner, 1, -1 do
      pts[#pts + 1] = inner[i]
    end
  end
  pts[#pts + 1] = { net.x[to], net.y[to] }
  return pts
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
      -- on a network continent two joined nodes walk over the network, straight only when close
      if not (u.joined and v.joined) or d <= Graph.DIRECT_YARDS then
        relax(i, d / walkSpeed, "walk", true, d)
      end
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
  local upper = #nodes

  -- the walk networks: their nodes are the indices after the others (no tables: plans run often)
  local continents = {}
  for c in pairs(g.nets or {}) do
    continents[#continents + 1] = c
  end
  table.sort(continents)
  local ranges, netOn, total = {}, {}, upper
  for _, c in ipairs(continents) do
    local net = g.nets[c]
    if net and net.n > 0 then
      ranges[#ranges + 1] = { base = total, net = net, continent = c }
      netOn[c] = ranges[#ranges]
      total = total + net.n
    end
  end
  local function rangeOf(i)
    for _, r in ipairs(ranges) do
      if i > r.base and i <= r.base + r.net.n then
        return r
      end
    end
  end
  -- every other node on a network continent joins it: by its key (a flight master or stop the
  -- network holds) or by straight legs to its nearest network nodes. Links back from the network go
  -- to the goal, the flight masters and the stops (never to the start or the hearth).
  local back = {}
  for i = 1, upper do
    local u = nodes[i]
    local r = netOn[u.continent]
    if r then
      local key = u.kind == "flight" and ("flightpath:" .. tostring(u.id))
        or u.kind == "stop" and ("transport:" .. tostring(u.id) .. ":" .. tostring(u.stopIndex))
        or nil
      local k = key and r.net.key[key]
      local joins = k and { { k, 0 } }
        or Graph.NearestNodes(r.net, u.wx, u.wy, Graph.JOIN_YARDS, Graph.JOIN_COUNT)
      if #joins > 0 then
        u.joined, u.joins, u.keyed = true, joins, k and true or nil
        if u.kind ~= "start" and u.kind ~= "hearth" then
          for _, j in ipairs(joins) do
            local at = r.base + j[1]
            local list = back[at]
            if not list then
              list = {}
              back[at] = list
            end
            list[#list + 1] = { i, j[2] }
          end
        end
      end
    end
  end

  local best, via, done = {}, {}, {}
  for i = 1, total do
    best[i] = huge
  end
  best[1] = 0
  -- a binary heap of (cost, node) with lazy deletion
  local hc, hn, hsize = {}, {}, 0
  local function push(cost, i)
    hsize = hsize + 1
    local at = hsize
    while at > 1 do
      local up = floor(at / 2)
      if hc[up] <= cost then
        break
      end
      hc[at], hn[at] = hc[up], hn[up]
      at = up
    end
    hc[at], hn[at] = cost, i
  end
  local function pop()
    local cost, i = hc[1], hn[1]
    local lc, ln = hc[hsize], hn[hsize]
    hc[hsize], hn[hsize] = nil, nil
    hsize = hsize - 1
    if hsize > 0 then
      local at = 1
      while true do
        local child = at * 2
        if child > hsize then
          break
        end
        if child < hsize and hc[child + 1] < hc[child] then
          child = child + 1
        end
        if hc[child] >= lc then
          break
        end
        hc[at], hn[at] = hc[child], hn[child]
        at = child
      end
      hc[at], hn[at] = lc, ln
    end
    return cost, i
  end
  local u, ub
  local function relax(v, seconds, mode, approx, yards, wait, jump, edge)
    local cost = ub + seconds
    if cost < best[v] then
      best[v] = cost
      local e = via[v]
      if not e then
        e = {}
        via[v] = e
      end
      e.from, e.seconds, e.mode, e.approx, e.yards, e.wait, e.jump, e.edge =
        u, seconds, mode, approx, yards, wait, jump, edge
      push(cost, v)
    end
  end
  push(0, 1)
  while hsize > 0 do
    local cost, i = pop()
    if not done[i] and cost <= best[i] then
      if i == 2 then
        break
      end
      u, ub = i, cost
      done[i] = true
      if i <= upper then
        local here = nodes[i]
        relaxEdges(g, nodes, here, walkSpeed, flySpeed, relax)
        if here.joins then
          local base = netOn[here.continent].base
          for _, j in ipairs(here.joins) do
            relax(base + j[1], j[2] / walkSpeed, "walk", not here.keyed, j[2])
          end
        end
      else
        local r = rangeOf(i)
        local net = r.net
        local adj = net.adj[i - r.base]
        for a = 1, #adj, 2 do
          local e = adj[a + 1]
          local swim = net.swim[e]
          local seconds = (net.len[e] - swim) / walkSpeed + swim / Graph.SWIM_SPEED
          relax(r.base + adj[a], seconds, "walk", false, net.len[e], nil, nil, e)
        end
        for _, b in ipairs(back[i] or {}) do
          relax(b[1], b[2] / walkSpeed, "walk", not nodes[b[1]].keyed, b[2])
        end
      end
    end
  end
  if best[2] == huge then
    return nil
  end

  local function nodeAt(i)
    if i <= upper then
      return nodes[i]
    end
    local r = rangeOf(i)
    local k = i - r.base
    return {
      kind = "net",
      continent = r.continent,
      wx = r.net.x[k],
      wy = r.net.y[k],
      net = r.net,
      netIndex = k,
    }
  end
  local raw = {}
  local at, atNode = 2, nodes[2]
  while at ~= 1 do
    local e = via[at]
    local fromNode = nodeAt(e.from)
    table.insert(raw, 1, {
      mode = e.mode,
      from = fromNode,
      to = atNode,
      seconds = e.seconds,
      approx = e.approx,
      yards = e.yards,
      wait = e.wait,
      jump = e.jump,
      edge = e.edge,
    })
    at, atNode = e.from, fromNode
  end
  -- consecutive walks are one step: its legs are the pieces of the path, each measured (a network
  -- edge) or approximate (a straight leg); the step is approximate when most of it is
  local steps = {}
  local function addLeg(step, r)
    local pts
    if r.edge then
      pts = Graph.EdgePoints(r.from.net, r.edge, r.from.netIndex)
    else
      pts = { { r.from.wx, r.from.wy }, { r.to.wx, r.to.wy } }
    end
    local approx = r.approx and true or false
    local last = step.legs[#step.legs]
    if last and last.approx == approx then
      for p = 2, #pts do
        last.points[#last.points + 1] = pts[p]
      end
    else
      step.legs[#step.legs + 1] = { approx = approx, points = pts }
    end
    if approx then
      step.approxYards = step.approxYards + (r.yards or 0)
    end
  end
  for _, r in ipairs(raw) do
    local last = steps[#steps]
    if r.mode == "walk" and last and last.mode == "walk" then
      last.to = r.to
      last.seconds = last.seconds + r.seconds
      last.yards = (last.yards or 0) + (r.yards or 0)
      addLeg(last, r)
    else
      if r.mode == "walk" then
        r.legs, r.approxYards = {}, 0
        addLeg(r, r)
      end
      steps[#steps + 1] = r
    end
  end
  for _, step in ipairs(steps) do
    step.edge = nil
    if step.legs then
      step.approx = step.approxYards > 0.5 * (step.yards or 0)
    end
  end
  -- a walk of under a yard (the start is a node, or two nodes share a place) is no step
  for i = #steps, 1, -1 do
    if steps[i].mode == "walk" and (steps[i].yards or 0) < 1 and #steps > 1 then
      table.remove(steps, i)
    end
  end
  return { seconds = best[2], steps = steps, start = g.start, goal = g.goal }
end

-- The points of a step's path in order: a walk's legs joined, else its two ends.
function Graph.StepPoints(step)
  if step._points then
    return step._points
  end
  local pts, approx = {}, {} -- approx[i]: the piece from point i to i + 1 is a straight join
  for _, leg in ipairs(step.legs or {}) do
    for i, p in ipairs(leg.points) do
      if i > 1 or #pts == 0 then
        pts[#pts + 1] = p
        if #pts > 1 then
          approx[#pts - 1] = leg.approx and true or false
        end
      end
    end
  end
  if #pts < 2 then
    pts = { { step.from.wx, step.from.wy }, { step.to.wx, step.to.wy } }
    approx = { step.approx and true or false }
  end
  step._points, step._approx = pts, approx
  return pts
end

-- Where a point stands along the step's path: the nearest
-- piece from `first` on (the progress only moves forward, a path may pass a place twice) ->
-- { i = piece, x, y = the point on it, off = yards from the path, along = yards walked of the
-- step's path, total = its length }.
function Graph.Progress(step, px, py, first)
  local pts = Graph.StepPoints(step)
  local cum = step._cum
  if not cum then
    cum = { 0 }
    for i = 2, #pts do
      cum[i] = cum[i - 1] + Graph.Distance(pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2])
    end
    step._cum = cum
  end
  local best
  for i = math.max(first or 1, 1), #pts - 1 do
    local a, b = pts[i], pts[i + 1]
    local dx, dy = b[1] - a[1], b[2] - a[2]
    local len2 = dx * dx + dy * dy
    local t = 0
    if len2 > 0 then
      t = math.max(0, math.min(1, ((px - a[1]) * dx + (py - a[2]) * dy) / len2))
    end
    local qx, qy = a[1] + t * dx, a[2] + t * dy
    local off = Graph.Distance(px, py, qx, qy)
    if not best or off < best.off - 1e-9 then
      best = { i = i, x = qx, y = qy, off = off, along = cum[i] + t * sqrt(len2) }
    end
  end
  if not best then
    return nil
  end
  best.total = cum[#pts]
  return best
end

-- The step's legs from the progress on: the line starts at the point on the path, the walked
-- part is gone; straight joins stay apart (drawn dashed).
function Graph.RemainingLegs(step, progress)
  local pts = Graph.StepPoints(step)
  local approx = step._approx or {}
  local legs, leg = {}, nil
  local last = { progress.x, progress.y }
  for i = progress.i, #pts - 1 do
    local a = approx[i] and true or false
    if not leg or leg.approx ~= a then
      leg = { approx = a, points = { last } }
      legs[#legs + 1] = leg
    end
    last = pts[i + 1]
    leg.points[#leg.points + 1] = last
  end
  return legs
end

-- Seconds left of a route: the steps ahead, and the current step by the share not walked yet.
function Graph.Remaining(route)
  local index = route.index or 1
  local left = 0
  for i = index, #route.steps do
    local s = route.steps[i]
    local seconds = s.seconds or 0
    local p = route.progress
    if i == index and p and p.step == i and p.total and p.total > 0 then
      seconds = seconds * math.max(0, 1 - p.along / p.total)
    end
    left = left + seconds
  end
  return left
end

-- How far a point is from the step's path, and the path's point to head for: the end of the nearest
-- piece, or the one after it when that end is within `reach` yards.
function Graph.PathProgress(step, px, py, reach)
  local pts = Graph.StepPoints(step)
  local bestD, bestI = huge, 1
  for i = 1, #pts - 1 do
    local a, b = pts[i], pts[i + 1]
    local d = Graph.SegmentDistance(px, py, a[1], a[2], b[1], b[2])
    if d < bestD then
      bestD, bestI = d, i
    end
  end
  local nextI = bestI + 1
  local p = pts[nextI]
  if p and nextI < #pts and Graph.Distance(px, py, p[1], p[2]) <= (reach or 0) then
    nextI = nextI + 1
  end
  return bestD, pts[nextI]
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
  teleport = "Teleport",
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
  if step.mode ~= "hearth" and step.mode ~= "teleport" and step.approx then
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
