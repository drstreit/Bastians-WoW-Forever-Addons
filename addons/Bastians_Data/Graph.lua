-- Bastian's Data: the world graph's service `graph` (ADR 0026, data.md "The world graph"): places,
-- what is around, the named edges between things, facets, the character and what it learned.
-- Over the nav pack's network (W6 step 2): Route, the distance cache behind Time and Nearest; the
-- `travel` shim (W8); the activities nearby by their value per hour (R26.11, W10 step 1) and the
-- session plan over them (W10 step 3). Reach answers nil until W10.
local _, ns = ...
local B = Bastians
local Data = ns.Data

local Graph = {}
Data.Graph = Graph

local ipairs, pairs, type, next = ipairs, pairs, type, next
local sqrt, floor, abs = math.sqrt, math.floor, math.abs

local service = {}
Graph.service = service

local function data()
  return B:GetService("data")
end

local function parse(ref)
  return B.Entity.Parse(ref)
end

-- A ref, a place or "player" -> a place { map, wx, wy, wz } or nil.
local function placeOf(target)
  if target == "player" then
    local continent, wx, wy = B.Coords.Player()
    if continent and wx and wy then
      return { map = continent, wx = wx, wy = wy }
    end
    return nil
  end
  if type(target) == "table" then
    return target.wx and target or nil
  end
  if type(target) == "string" and parse(target) then
    for _, p in ipairs(B:Entity(target):Places()) do
      if p.wx then
        return p
      end
    end
  end
  return nil
end
Graph.PlaceOf = placeOf

-- ---------------------------------------------------------------------------------------------
-- The named edges (world-graph.md §4.5) over the records' fields and the generated indexes.
-- out(rec, ref) and into(rec, ref) answer { { ref, props } }; rec is {} when the record is not
-- loaded; a direction no field or index gives is absent.

local function refsOf(list, props)
  local out = {}
  for _, ref in ipairs(list or {}) do
    if type(ref) == "string" then
      out[#out + 1] = { ref = ref, props = props }
    end
  end
  return out
end

local function questsOf(ids)
  local out = {}
  for _, id in ipairs(ids or {}) do
    out[#out + 1] = { ref = "quest:" .. id }
  end
  return out
end

local function questRefs(ids, props)
  local out = {}
  for _, id in ipairs(ids or {}) do
    out[#out + 1] = { ref = "quest:" .. id, props = props }
  end
  return out
end

local function byIndex(name)
  return function(_, ref)
    local d = data()
    return questsOf(d and d:Index(name, ref))
  end
end

local EDGES = {
  starts = {
    out = {
      npc = byIndex("quest.byGiver"),
      object = byIndex("quest.byGiver"),
      item = byIndex("quest.byGiver"),
    },
    into = {
      quest = function(r)
        return refsOf(r.starts)
      end,
    },
  },
  ends = {
    out = { npc = byIndex("quest.byEnder"), object = byIndex("quest.byEnder") },
    into = {
      quest = function(r)
        return refsOf(r.ends)
      end,
    },
  },
  needs = {
    out = {
      quest = function(r)
        local out = questRefs(r.pre, { all = true })
        for _, e in ipairs(questRefs(r.preAny, { any = true })) do
          out[#out + 1] = e
        end
        return out
      end,
    },
  },
  excludes = {
    out = {
      quest = function(r)
        return questRefs(r.excl)
      end,
    },
  },
  chains = {
    out = {
      quest = function(r)
        return r.chain and { { ref = "quest:" .. r.chain } } or {}
      end,
    },
  },
  targets = {
    out = {
      quest = function(r)
        local out = {}
        for _, o in ipairs(r.objectives or {}) do
          if type(o) == "table" and type(o[2]) == "string" then
            out[#out + 1] = { ref = o[2], props = { kind = o[1] } }
          end
        end
        return out
      end,
    },
  },
  rewards = {
    out = {
      quest = function(r)
        local out, rw = {}, r.rewards or {}
        for _, it in ipairs(rw.items or {}) do
          out[#out + 1] = { ref = "item:" .. it[1], props = { count = it[2] } }
        end
        for _, it in ipairs(rw.choices or {}) do
          out[#out + 1] = { ref = "item:" .. it[1], props = { count = it[2], choice = true } }
        end
        return out
      end,
    },
  },
  drops = {
    out = {
      npc = function(r)
        local out = {}
        for _, l in ipairs(r.loot or {}) do
          out[#out + 1] = { ref = "item:" .. l[1], props = { chance = l[2] } }
        end
        return out
      end,
    },
    into = {
      item = function(r)
        local out = {}
        for _, d in ipairs(r.drops or {}) do
          if type(d[1]) == "string" then
            out[#out + 1] = { ref = d[1], props = { chance = d[2] } }
          end
        end
        return out
      end,
    },
  },
  sells = {
    out = {
      npc = function(r)
        local out = {}
        for _, v in ipairs(r.vendor or {}) do
          out[#out + 1] = { ref = "item:" .. v[1], props = { price = v[2], stack = v[3], limited = v[4] } }
        end
        return out
      end,
    },
  },
  teaches = {
    out = {
      npc = function(r)
        local out = {}
        for _, t in ipairs(r.trainer or {}) do
          out[#out + 1] = { ref = "spell:" .. t[1], props = { cost = t[3], skill = t[4], level = t[5] } }
        end
        return out
      end,
    },
  },
  makes = {
    out = {
      recipe = function(r)
        return r.item and { { ref = "item:" .. r.item, props = { count = r.count } } } or {}
      end,
    },
  },
  uses = {
    out = {
      recipe = function(r)
        local out = {}
        for _, g in ipairs(r.reagents or {}) do
          out[#out + 1] = { ref = "item:" .. g[1], props = { count = g[2] } }
        end
        return out
      end,
    },
  },
}
Graph.EDGES = EDGES
-- the object loot is an object's drops, as the NPC's
EDGES.drops.out.object = EDGES.drops.out.npc

-- ---------------------------------------------------------------------------------------------
-- The service

function service:Ready(map)
  local nav = Data.packs and Data.packs.nav
  local graph = nav and nav.graph
  if not graph then
    return false
  end
  if map == nil then
    map = B.Coords.Player()
  end
  return map ~= nil and graph[map] ~= nil
end

function service:Place(ref)
  if type(ref) ~= "string" or not parse(ref) then
    return nil
  end
  local places = B:Entity(ref):Places()
  return #places > 0 and places or nil
end

local AROUND_TYPES = { "npc", "object", "node", "entrance", "flightpath", "transport" }

local function wanted(ref, filter)
  if filter.roles then
    local poi = B:Entity(ref):Facet("poi")
    if not poi then
      return false
    end
    for _, want in ipairs(filter.roles) do
      for _, have in ipairs(poi.roles) do
        if want == have then
          return true
        end
      end
    end
    return false
  end
  if filter.facet then
    return B:Entity(ref):Facet(filter.facet) ~= nil
  end
  return true
end

-- Refs near a position by straight line: { { ref, place, yards } }, nearest first, at most n (20).
-- Step 1 reads the zone indexes of the map that holds the position; the cluster index comes with
-- the nav pack (W3).
function service:Around(pos, filter, n)
  local here = placeOf(pos)
  local d = data()
  if not (here and d) then
    return {}
  end
  filter = filter or {}
  n = n or 20
  local ui = B.Coords.BestMap(here.map, here.wx, here.wy)
  if not ui then
    return {}
  end
  local found = {}
  for _, typ in ipairs(filter.types or AROUND_TYPES) do
    for id in d:ByZone(typ, ui) do
      local ref = typ .. ":" .. id
      if wanted(ref, filter) then
        local best, bestPlace
        for _, p in ipairs(B:Entity(ref):AllPlaces()) do
          if p.map == here.map and p.wx then
            local dx, dy = p.wx - here.wx, p.wy - here.wy
            local yards = sqrt(dx * dx + dy * dy)
            if not best or yards < best then
              best, bestPlace = yards, p
            end
          end
        end
        if best then
          found[#found + 1] = { ref = ref, place = bestPlace, yards = best }
        end
      end
    end
  end
  table.sort(found, function(a, b)
    if a.yards ~= b.yards then
      return a.yards < b.yards
    end
    return a.ref < b.ref
  end)
  for i = #found, n + 1, -1 do
    found[i] = nil
  end
  return found
end

-- ---------------------------------------------------------------------------------------------
-- The network (W6 step 2): routes, times and the nearest places over the nav pack's `graph`.

local nets = {} -- continent -> network over the current record

local function netFor(map)
  local nav = Data.packs and Data.packs.nav
  local rec = map ~= nil and nav and nav.graph and nav.graph[map]
  if not rec then
    return nil
  end
  local net = nets[map]
  if not net or net.rec ~= rec then
    net = Data.Net.New(rec)
    net.map = map
    nets[map] = net
  end
  return net
end
Graph.NetFor = netFor

-- The taxi nodes the character may fly between: nil for "all", else the overlay's and Quests'.
local function knownTaxi(opts)
  if opts and opts.known then
    return opts.known -- the caller's set ({ [nodeID] = true }), e.g. Route's network setting
  end
  if opts and opts.network == "all" then
    return nil
  end
  local known = {}
  for id in pairs(Graph.char and Graph.char.taxi or {}) do
    known[tonumber(id) or id] = true
  end
  if opts and opts.network == "account" then
    for id in pairs(Graph.account and Graph.account.taxi or {}) do
      known[tonumber(id) or id] = true
    end
  end
  local progress = B:GetService("progress")
  if progress and progress.KnownFlightPaths then
    for id in pairs(progress:KnownFlightPaths() or {}) do
      if type(id) == "number" then
        known[id] = true
      end
    end
  end
  return known
end

local function speedsOf(opts)
  return opts and opts.speeds or (Graph.char and Graph.char.speeds) or {}
end

Graph.RIDE_SPEED = 12 -- yards a second on a boat, zeppelin or tram whose ride is unknown (route.md)
Graph.RIDE_WAIT = 90 -- seconds of wait when a ride's cycle is unknown (route.md)
Graph.PORTAL_SECONDS = 3
Graph.HEARTH_SECONDS = 10
Graph.TELEPORT_SECONDS = 10 -- a teleport's cast when the route's teleport gives none (R26.7)

local FACTION_OK = { both = true }

-- The rides of the continent: the transports whose consecutive stops are keyed waypoints, both
-- ways, timed as Route's planner did (route.md B9.2): the ride or its length at RIDE_SPEED, plus
-- half the cycle as the wait (RIDE_WAIT when unknown); portals PORTAL_SECONDS without a wait.
local function rideEdges(net, extra, faction)
  local d = data()
  if not d then
    return extra
  end
  for _, id in ipairs(d:Each("transport") or {}) do
    local t = d:Get("transport", id)
    local ok = t and t.world and (FACTION_OK[t.faction] or not faction or t.faction == faction)
    for i = 1, ok and #t.world - 1 or 0 do
      for _, pair in ipairs({ { i, i + 1 }, { i + 1, i } }) do
        local a = net.byKey["transport:" .. id .. ":" .. pair[1]]
        local b = net.byKey["transport:" .. id .. ":" .. pair[2]]
        local p, q = t.world[pair[1]], t.world[pair[2]]
        if a and b and p and q then
          local len = sqrt((q[2] - p[2]) ^ 2 + (q[3] - p[3]) ^ 2)
          local portal = t.kind == "portal"
          local ride = t.ride or (portal and Graph.PORTAL_SECONDS or len / Graph.RIDE_SPEED)
          -- R26.6: each way's ride from the departures (it leaves pair[1] and is at pair[2] a dock
          -- before it leaves there)
          local dep = t.departs
          if dep and t.cycle and dep[pair[1]] and dep[pair[2]] then
            ride = (dep[pair[2]] - (t.dock or 0) - dep[pair[1]]) % t.cycle
          end
          local wait = portal and 0 or (t.cycle and t.cycle / 2 or Graph.RIDE_WAIT)
          extra[a] = extra[a] or {}
          table.insert(extra[a], {
            b = b,
            seconds = ride + wait,
            mode = portal and "portal" or "ride",
            kind = t.kind,
            ref = "transport:" .. id,
            wait = wait,
            ride = ride,
            len = len,
            jump = portal or nil,
          })
        end
      end
    end
  end
  return extra
end

-- The extra edges of a search: the flights between known flight masters (not for `nocost`:
-- flights cost gold, R26.5) and the rides.
-- The learned walks of this continent as edges both ways between the waypoints their ends join
-- (world-graph.md §9, W11): a way the mesh missed works for this player at once.
function Graph.WalkEdges(net, extra, walks, speed)
  local Net = Data.Net
  for _, w in ipairs(walks or {}) do
    local pts = w.points
    if w.map == net.map and type(pts) == "table" and #pts >= 2 then
      local first, last = pts[1], pts[#pts]
      local a = Net.Join(net, first[1], first[2])
      local b = Net.Join(net, last[1], last[2])
      if a and b and a ~= b then
        local seconds = (w.len or 0) / (speed or Net.RUN_SPEED)
        extra[a] = extra[a] or {}
        extra[b] = extra[b] or {}
        local back = {}
        for i = #pts, 1, -1 do
          back[#back + 1] = pts[i]
        end
        table.insert(
          extra[a],
          { b = b, seconds = seconds, mode = "walk", learned = true, len = w.len, points = pts }
        )
        table.insert(
          extra[b],
          { b = a, seconds = seconds, mode = "walk", learned = true, len = w.len, points = back }
        )
      end
    end
  end
  return extra
end

local function extraFor(net, opts)
  local extra = {}
  if not (opts and opts.profile == "nocost") then
    extra = Data.Net.TaxiEdges(net, knownTaxi(opts), Graph.learned and Graph.learned.taxi)
  end
  extra = rideEdges(net, extra, opts and opts.faction)
  return Graph.WalkEdges(net, extra, Graph.learned and Graph.learned.walk, speedsOf(opts).ground)
end

local FACTION_LETTER = { Alliance = "A", Horde = "H", A = "A", H = "H" }

-- The safe profile's character (R26.5): { level, faction letter } for Net.Search, or nil.
local function safeOf(opts)
  if not (opts and opts.profile == "safe") then
    return nil
  end
  local level = opts.level
  if not level then
    local facts = B.Compat.GetPlayerFacts and B.Compat.GetPlayerFacts() or nil
    level = facts and facts.level
  end
  return { level = level, faction = FACTION_LETTER[opts.faction or ""] }
end
Graph.SafeOf = safeOf

-- The jumps the character has ready (R26.7): the hearth (opts.hearth = { map, wx, wy, wz } when
-- the stone is ready) and the teleports (opts.teleports = { { map, wx, wy, wz, seconds, name, id }
-- }) as { place, seconds, mode, name, id }.
local function jumpsOf(opts)
  local out = {}
  local h = opts and opts.hearth
  if h and h.wx then
    out[#out + 1] = { place = h, seconds = Graph.HEARTH_SECONDS, mode = "hearth" }
  end
  for _, t in ipairs(opts and opts.teleports or {}) do
    if t.map and t.wx then
      local seconds = t.seconds or Graph.TELEPORT_SECONDS
      out[#out + 1] = { place = t, seconds = seconds, mode = "teleport", name = t.name, id = t.id }
    end
  end
  return out
end

-- The jumps landing on this continent as edges from wherever the character stands.
local function startEdges(net, opts)
  local edges
  for _, j in ipairs(jumpsOf(opts)) do
    local n = j.place.map == net.map and Data.Net.Join(net, j.place.wx, j.place.wy, j.place.wz)
    if n then
      edges = edges or {}
      edges[#edges + 1] = { b = n, seconds = j.seconds, mode = j.mode, name = j.name, jump = true }
    end
  end
  return edges
end

Graph.SPUR_YARDS = 3 -- a walk back within this of a point it passed is a spur
Graph.SPUR_WINDOW = 150 -- points ahead searched for the way back (spurs are short)

-- Cuts the out-and-back spurs of a walk's points in place: a way of the network may run past a
-- junction to its waypoint, and the next way comes back along it (Stormwind's gate, retail
-- 25.10.2026). Returns the yards cut.
local function cutSpurs(points)
  local cut, i = 0, 1
  local near = Graph.SPUR_YARDS * Graph.SPUR_YARDS
  while i < #points do
    local p, back = points[i], nil
    for j = math.min(#points, i + Graph.SPUR_WINDOW), i + 2, -1 do
      local q = points[j]
      local dx, dy = q.wx - p.wx, q.wy - p.wy
      if dx * dx + dy * dy <= near then
        back = j
        break
      end
    end
    if back then
      for k = i, back - 1 do
        local a, b = points[k], points[k + 1]
        cut = cut + sqrt((b.wx - a.wx) ^ 2 + (b.wy - a.wy) ^ 2)
      end
      for _ = i + 1, back do
        table.remove(points, i + 1)
      end
    end
    i = i + 1
  end
  return cut
end
Graph.CutSpurs = cutSpurs

-- The route's steps and path in the service's shape (data.md "The world graph").
local function shape(net, result, opts, goalName)
  local Net = Data.Net
  local speeds = speedsOf(opts)
  local steps, path = {}, {}
  local walk
  local current -- the step whose points are being collected
  local function point(p)
    local last = path[#path]
    if not (last and last.wx == p.x and last.wy == p.y) then
      path[#path + 1] = { map = net.map, wx = p.x, wy = p.y }
    end
    local pts = current and current.points
    local lastOwn = pts and pts[#pts]
    if pts and not (lastOwn and lastOwn.wx == p.x and lastOwn.wy == p.y) then
      pts[#pts + 1] = { map = net.map, wx = p.x, wy = p.y }
    end
  end
  local function key(n)
    return net.keys[n]
  end
  local function place(n)
    local p = Net.Point(net, n)
    return p and { map = net.map, wx = p.x, wy = p.y, wz = p.z }
  end
  for _, leg in ipairs(result.legs) do
    local e = leg.edge
    if e.mode then
      walk = nil
      steps[#steps + 1] = {
        mode = e.mode,
        kind = e.kind,
        ref = e.ref,
        from = key(leg.from),
        to = key(leg.to),
        fromPlace = place(leg.from),
        toPlace = place(leg.to),
        seconds = e.seconds,
        wait = e.wait,
        ride = e.ride,
        yards = e.len,
        jump = e.jump,
        name = e.name, -- a teleport's destination
        learned = e.learned, -- a walk this player taught the graph (W11)
      }
      current = steps[#steps]
      current.points = {}
      local from, to = Net.Point(net, leg.from), Net.Point(net, leg.to)
      if from then
        point(from)
      end
      for _, p in ipairs(e.points or {}) do
        point({ x = p[1], y = p[2] })
      end
      if to then
        point(to)
      end
    else
      for _, part in ipairs(Net.Refine(net, leg, { speeds = speeds, profile = opts and opts.profile })) do
        local f = part.edge.facts
        if not walk then
          walk = {
            mode = "walk",
            from = key(part.from),
            fromPlace = place(part.from),
            seconds = 0,
            yards = 0,
            areas = {},
            points = {},
          }
          steps[#steps + 1] = walk
          current = walk
        end
        walk.seconds = walk.seconds + Net.Seconds(f, speeds)
        walk.yards = walk.yards + f.len
        walk.to = key(part.to)
        walk.toPlace = place(part.to)
        local area = part.edge.area
        if area and walk.areas[#walk.areas] ~= area then
          walk.areas[#walk.areas + 1] = area
        end
        -- the highest hostile level along the walk, and whether an elite counts (R26.5)
        local danger = part.edge.danger
        if danger and (not walk.danger or danger > walk.danger) then
          walk.danger = danger
        end
        local flags = part.edge.flags
        if danger and flags and flags:find("e", 1, true) then
          walk.elite = true
        end
        for _, p in ipairs(Net.LegPoints(net, part)) do
          point(p)
        end
      end
    end
  end
  -- the spurs of the walks go, from the drawing and from the time
  local seconds = result.seconds
  local ground = speeds.ground or Net.RUN_SPEED
  for _, step in ipairs(steps) do
    if step.mode == "walk" then
      local cut = cutSpurs(step.points)
      if cut > 0 then
        step.yards = math.max(step.yards - cut, 0)
        step.seconds = math.max(step.seconds - cut / ground, 0)
        seconds = seconds and math.max(seconds - cut / ground, 0)
      end
    end
  end
  path = {}
  for _, step in ipairs(steps) do
    for _, p in ipairs(step.points or {}) do
      local last = path[#path]
      if not (last and last.wx == p.wx and last.wy == p.wy) then
        path[#path + 1] = p
      end
    end
  end
  local notes = {}
  if result.joinFrom > 0 or result.joinTo > 0 then
    notes[#notes + 1] = "joined by straight line"
  end
  return {
    seconds = seconds,
    steps = steps,
    path = path,
    notes = notes,
    goal = goalName,
    approx = result.joinFrom > 50 or result.joinTo > 50,
  }
end

-- --- across continents (W8) -------------------------------------------------------------------

Graph.RIDE_UNKNOWN = 180 -- seconds of a ride between continents whose ride time nobody measured

-- The rides from netA's continent to netB's: the consecutive stops of a transport, one on each,
-- both keyed in their network: { { a, b, seconds, wait, ride, mode, kind, ref, jump, approx } }.
local function crossings(netA, netB, faction)
  local out = {}
  local d = data()
  for _, id in ipairs(d and d:Each("transport") or {}) do
    local t = d:Get("transport", id)
    local ok = t and t.world and (FACTION_OK[t.faction] or not faction or t.faction == faction)
    for i = 1, ok and #t.world - 1 or 0 do
      for _, pair in ipairs({ { i, i + 1 }, { i + 1, i } }) do
        local p, q = t.world[pair[1]], t.world[pair[2]]
        local a = p and p[1] == netA.map and netA.byKey["transport:" .. id .. ":" .. pair[1]]
        local b = q and q[1] == netB.map and netB.byKey["transport:" .. id .. ":" .. pair[2]]
        if a and b then
          local portal = t.kind == "portal"
          local ride = t.ride or (portal and Graph.PORTAL_SECONDS or Graph.RIDE_UNKNOWN)
          local wait = portal and 0 or (t.cycle and t.cycle / 2 or Graph.RIDE_WAIT)
          out[#out + 1] = {
            a = a,
            b = b,
            seconds = ride + wait,
            wait = wait,
            ride = ride,
            mode = portal and "portal" or "ride",
            kind = t.kind,
            ref = "transport:" .. id,
            jump = portal or nil,
            approx = not t.ride or nil,
          }
        end
      end
    end
  end
  return out
end

-- The start's edges merged into the extra edges at waypoint n (the hearth from where one stands).
local function withStart(extra, n, edges)
  if not edges then
    return extra
  end
  local copy = {}
  for k, list in pairs(extra or {}) do
    copy[k] = list
  end
  local here = {}
  for _, e in ipairs(copy[n] or {}) do
    here[#here + 1] = e
  end
  for _, e in ipairs(edges) do
    here[#here + 1] = e
  end
  copy[n] = here
  return copy
end

-- Joins two shaped halves and the step between them into one route.
local function joinShapes(first, middle, second, seconds)
  local steps, path, notes = {}, {}, {}
  for _, part in ipairs({ first, second }) do
    for _, n in ipairs(part and part.notes or {}) do
      notes[#notes + 1] = n
    end
  end
  for _, s in ipairs(first and first.steps or {}) do
    steps[#steps + 1] = s
  end
  for _, p in ipairs(first and first.path or {}) do
    path[#path + 1] = p
  end
  steps[#steps + 1] = middle
  for _, s in ipairs(second.steps) do
    steps[#steps + 1] = s
  end
  for _, p in ipairs(second.path) do
    path[#path + 1] = p
  end
  return {
    seconds = seconds,
    steps = steps,
    path = path,
    notes = notes,
    goal = second.goal,
    approx = (first and first.approx) or second.approx or middle.approx or false,
  }
end

-- A route from a on netA's continent to b on netB's: one search from the start out to every
-- departure (Dijkstra until all are settled), the rides (and the hearth and the teleports that land
-- on the goal's continent) seed one A* search on the goal's continent. -> route or nil, reason.
local function crossRoute(netA, netB, a, b, opts, yield, goalName)
  local Net = Data.Net
  local speeds = speedsOf(opts)
  local ground = speeds.ground or Net.RUN_SPEED
  local start, ds = Net.Join(netA, a.wx, a.wy, a.wz)
  local goal, dg = Net.Join(netB, b.wx, b.wy, b.wz)
  if not start then
    return nil, "start off the network"
  end
  if not goal then
    return nil, "goal off the network"
  end
  local rides = crossings(netA, netB, opts and opts.faction)
  local landings = {} -- waypoint on netB -> the fastest jump landing there
  for _, j in ipairs(jumpsOf(opts)) do
    local n = j.place.map == netB.map and Net.Join(netB, j.place.wx, j.place.wy, j.place.wz)
    if n and (not landings[n] or j.seconds < landings[n].seconds) then
      landings[n] = j
    end
  end
  if #rides == 0 and next(landings) == nil then
    return nil, "no ride between the continents"
  end
  local goals, openA = {}, { [Net.ClusterOf(netA, start)] = true }
  for _, r in ipairs(rides) do
    goals[r.a] = true
    openA[Net.ClusterOf(netA, r.a)] = true
  end
  local secsA, traceA = {}, nil
  if #rides > 0 then
    secsA, traceA = Net.Search(netA, { [start] = ds / ground }, {
      speeds = speeds,
      profile = opts and opts.profile,
      safe = safeOf(opts),
      extra = withStart(extraFor(netA, opts), start, startEdges(netA, opts)),
      open = openA,
      goals = goals,
      yield = yield,
    })
  end
  local seeds, via = {}, {}
  local openB = { [Net.ClusterOf(netB, goal)] = true }
  for _, r in ipairs(rides) do
    local t = secsA[r.a] and secsA[r.a] + r.seconds
    if t and (not seeds[r.b] or t < seeds[r.b]) then
      seeds[r.b], via[r.b] = t, r
      openB[Net.ClusterOf(netB, r.b)] = true
    end
  end
  for n, j in pairs(landings) do
    if not seeds[n] or j.seconds < seeds[n] then
      seeds[n], via[n] = j.seconds, j
      openB[Net.ClusterOf(netB, n)] = true
    end
  end
  if next(seeds) == nil then
    return nil, "no way"
  end
  local extraB = extraFor(netB, opts)
  local secsB, traceB = Net.Search(netB, seeds, {
    speeds = speeds,
    profile = opts and opts.profile,
    safe = safeOf(opts),
    extra = extraB,
    open = openB,
    goal = goal,
    yield = yield,
    target = { x = b.wx, y = b.wy },
    vmax = Net.Fastest(extraB, ground),
  })
  if not secsB[goal] then
    return nil, "no way"
  end
  local legsB = Net.LegsTo(netB, traceB, nil, goal)
  local seed = legsB[1] and legsB[1].from or goal
  local r = via[seed]
  local p = Net.Point(netB, seed)
  local landing = p and { map = netB.map, wx = p.x, wy = p.y, wz = p.z }
  local first, middle
  if r.place then -- a jump: the hearth or a teleport
    middle =
      { mode = r.mode, name = r.name, jump = true, seconds = r.seconds, toPlace = landing, points = {} }
  else
    local legsA = Net.LegsTo(netA, traceA, start, r.a)
    first = shape(netA, { legs = legsA, joinFrom = ds, joinTo = 0, seconds = secsA[r.a] }, opts)
    local q = Net.Point(netA, r.a)
    middle = {
      mode = r.mode,
      kind = r.kind,
      ref = r.ref,
      from = netA.keys[r.a],
      to = netB.keys[r.b],
      fromPlace = q and { map = netA.map, wx = q.x, wy = q.y, wz = q.z },
      toPlace = landing,
      seconds = r.seconds,
      wait = r.wait,
      ride = r.ride,
      jump = r.jump,
      approx = r.approx,
      points = {},
    }
  end
  local second =
    shape(netB, { legs = legsB, joinFrom = 0, joinTo = dg, seconds = secsB[goal] }, opts, goalName)
  return joinShapes(first, middle, second, secsB[goal] + dg / ground)
end

-- service:Route(from, to, opts, callback): a job; callback(route) or callback(nil, reason).
-- Across continents over the rides between them (W8).
function service:Route(from, to, opts, callback)
  local a, b = placeOf(from), placeOf(to)
  local reason
  if not (a and b) then
    reason = "no place"
  end
  local net = not reason and netFor(a.map)
  local netB = not reason and a.map ~= b.map and netFor(b.map)
  if not reason and not (net and (a.map == b.map or netB)) then
    reason = "no network"
  end
  if reason then
    if callback then
      callback(nil, reason)
    end
    return nil
  end
  local goalName = type(to) == "string" and to or nil
  if netB then
    local cross = function(yield)
      local route, why = crossRoute(net, netB, a, b, opts, yield, goalName)
      if callback then
        callback(route, why)
      end
    end
    if Graph.module then
      return B.Jobs:Run(Graph.module, "graph-route", cross, { budgetMs = 4 })
    end
    cross(nil)
    return nil
  end
  local run = function(yield)
    local o = {}
    for k, v in pairs(opts or {}) do
      o[k] = v
    end
    o.extra, o.yield = extraFor(net, opts), yield
    o.startEdges = startEdges(net, opts)
    o.safe = safeOf(opts)
    local result, why = Data.Net.Route(
      net,
      { x = a.wx, y = a.wy, z = a.wz },
      { x = b.wx, y = b.wy, z = b.wz },
      o
    )
    if callback then
      if result then
        callback(shape(net, result, opts, goalName))
      else
        callback(nil, why)
      end
    end
  end
  if Graph.module then
    return B.Jobs:Run(Graph.module, "graph-route", run, { budgetMs = 4 })
  end
  run(nil)
  return nil
end

-- --- several stops (R26.4, route.md "Several stops") ---------------------------------------------

Graph.TOUR_MAX = 12 -- stops of a tour at most
Graph.UNREACHABLE = 1e9 -- the seconds of a leg the network cannot walk
Graph.TOUR_PASSES = 20 -- rounds of single-stop moves after the insertion

-- The order of n stops after the start (index 0) by the seconds t[i][j] (i, j in 0..n), every
-- stop j after the stops in before[j] (a set of indexes): cheapest insertion of the stops whose
-- needs are placed, at a place after the last of them, then moves of single stops while the total
-- falls. The path is open. Pure. -> order (indexes 1..n; a stop caught in a cycle of needs is left
-- out), total seconds.
function Graph.OrderStops(t, n, before)
  before = before or {}
  local function cost(route)
    local sum, prev = 0, 0
    for _, j in ipairs(route) do
      sum, prev = sum + t[prev][j], j
    end
    return sum
  end
  local function fits(route)
    local at = {}
    for pos, j in ipairs(route) do
      at[j] = pos
    end
    for _, j in ipairs(route) do
      for i in pairs(before[j] or {}) do
        if at[i] and at[i] > at[j] then
          return false
        end
      end
    end
    return true
  end
  local route, placed = {}, {}
  for _ = 1, n do
    local bestJ, bestPos, bestD
    for j = 1, n do
      local ready = not placed[j]
      for i in pairs(ready and before[j] or {}) do
        if i >= 1 and i <= n and not placed[i] then
          ready = false
        end
      end
      if ready then
        local first = 0 -- after the last stop it needs
        for pos, k in ipairs(route) do
          if (before[j] or {})[k] then
            first = pos
          end
        end
        for pos = first, #route do
          local a, b = pos == 0 and 0 or route[pos], route[pos + 1]
          local d = t[a][j] + (b and (t[j][b] - t[a][b]) or 0)
          if not bestD or d < bestD then
            bestJ, bestPos, bestD = j, pos, d
          end
        end
      end
    end
    if not bestJ then
      break
    end
    table.insert(route, bestPos + 1, bestJ)
    placed[bestJ] = true
  end
  local total = cost(route)
  local improved, passes = true, 0
  while improved and passes < Graph.TOUR_PASSES do
    improved, passes = false, passes + 1
    for from = 1, #route do
      for to = 1, #route do
        if to ~= from then
          local trial = {}
          for k, v in ipairs(route) do
            trial[k] = v
          end
          table.insert(trial, to, table.remove(trial, from))
          if fits(trial) then
            local c = cost(trial)
            if c < total - 1e-6 then
              route, total, improved = trial, c, true
            end
          end
        end
      end
    end
  end
  return route, total
end

-- service:Tour(from, stops, opts, callback): a job; callback({ seconds, order = { ids }, legs =
-- { shaped routes }, skipped = { [id] = reason } }) or callback(nil, reason). stops = { { id,
-- name, place = { map, wx, wy, wz }, after = { ids } } } (route.md "Several stops").
function service:Tour(from, stops, opts, callback)
  local a = placeOf(from)
  local net = a and netFor(a.map)
  if not net then
    if callback then
      callback(nil, a and "no network" or "no place")
    end
    return nil
  end
  local run = function(yield)
    local Net = Data.Net
    local speeds = speedsOf(opts)
    local ground = speeds.ground or Net.RUN_SPEED
    local nodes, skipped, open = {}, {}, {}
    local function add(place, stop)
      local w, d = Net.Join(net, place.wx, place.wy, place.wz)
      if not w then
        if stop then
          skipped[stop.id] = "off the network"
        end
        return false
      end
      nodes[#nodes + 1] = { place = place, stop = stop, w = w, d = d }
      open[Net.ClusterOf(net, w)] = true
      return true
    end
    if not add(a, nil) then
      callback(nil, "start off the network")
      return
    end
    for _, st in ipairs(stops or {}) do
      local pl = st.place
      if #nodes > Graph.TOUR_MAX then
        skipped[st.id] = "too many stops"
      elseif not (pl and pl.map == net.map and pl.wx) then
        skipped[st.id] = "another continent"
      else
        add(pl, st)
      end
    end
    local n = #nodes - 1
    local index, before = {}, {}
    for k = 2, #nodes do
      index[nodes[k].stop.id] = k - 1
    end
    for k = 2, #nodes do
      for _, need in ipairs(nodes[k].stop.after or {}) do
        if index[need] then
          before[k - 1] = before[k - 1] or {}
          before[k - 1][index[need]] = true
        end
      end
    end
    local extra, safe = extraFor(net, opts), safeOf(opts)
    local t, traces = {}, {}
    for i = 0, n do
      local nd = nodes[i + 1]
      local goals = {}
      for k, other in ipairs(nodes) do
        if k ~= i + 1 then
          goals[other.w] = true
        end
      end
      local secs, trace = Net.Search(net, { [nd.w] = 0 }, {
        speeds = speeds,
        profile = opts and opts.profile,
        safe = safe,
        extra = extra,
        open = open,
        goals = goals,
        yield = yield,
      })
      t[i], traces[i] = {}, trace
      for j = 0, n do
        local m = nodes[j + 1]
        local between = j == i and 0 or secs[m.w]
        t[i][j] = between and (nd.d / ground + between + m.d / ground) or Graph.UNREACHABLE
      end
    end
    local order = Graph.OrderStops(t, n, before)
    local legs, ids, seconds, prev = {}, {}, 0, 0
    for _, j in ipairs(order) do
      local stop = nodes[j + 1].stop
      if t[prev][j] >= Graph.UNREACHABLE then
        skipped[stop.id] = "no way"
      else
        local here, there = nodes[prev + 1], nodes[j + 1]
        local leg = shape(net, {
          legs = Net.LegsTo(net, traces[prev], here.w, there.w),
          joinFrom = here.d,
          joinTo = there.d,
          seconds = t[prev][j],
        }, opts, stop.name)
        legs[#legs + 1], ids[#ids + 1] = leg, stop.id
        seconds, prev = seconds + (leg.seconds or t[prev][j]), j
      end
    end
    for k = 2, #nodes do
      local id = nodes[k].stop.id
      local inOrder = false
      for _, o in ipairs(ids) do
        inOrder = inOrder or o == id
      end
      if not inOrder and not skipped[id] then
        skipped[id] = "its needs were not met"
      end
    end
    if callback then
      callback({ seconds = seconds, order = ids, legs = legs, skipped = skipped })
    end
  end
  if Graph.module then
    return B.Jobs:Run(Graph.module, "graph-tour", run, { budgetMs = 4 })
  end
  run(nil)
  return nil
end

-- --- the distance cache from the character ---------------------------------------------------

local cache = { generation = 0 } -- map, key (the character's cluster), times, clusters, pending
Graph.cache = cache

-- The memo of places' times (below) starts over with every cache.
local function clearMemo()
  cache.memo, cache.approx, cache.memoCount, cache.queue, cache.refPlaces = {}, {}, 0, {}, {}
end
clearMemo()

function Graph.RefreshTimes(force)
  local map, wx, wy = B.Coords.Player()
  local net = map and netFor(map)
  if not (net and wx) then
    cache.map, cache.times = nil, nil
    clearMemo()
    return
  end
  local key = Data.Net.ClusterKey(wx, wy)
  if not force and cache.map == map and cache.key == key and cache.times then
    return
  end
  if cache.pending then
    return
  end
  cache.pending = true
  local run = function(yield)
    local n, d = Data.Net.Join(net, wx, wy)
    local times = {}
    if n then
      local speeds = speedsOf(nil)
      times = Data.Net.Spread(net, { [n] = d / (speeds.ground or Data.Net.RUN_SPEED) }, {
        speeds = speeds,
        open = { [key] = true },
        extra = extraFor(net, nil),
        yield = yield,
      })
    end
    cache.map, cache.key, cache.times, cache.clusters = map, key, times, {}
    clearMemo()
    cache.pending = nil
    cache.generation = cache.generation + 1
    B:Fire("BASTIANS_GRAPH_TIMES", cache.generation)
  end
  if Graph.module then
    B.Jobs:Run(Graph.module, "graph-times", run, { budgetMs = 4 })
  else
    run(nil)
  end
end

-- --- the times of places, for rows (world-graph.md principle 7) ------------------------------
-- A row's time is one lookup in a memo by place. A place not in the memo is queued and answers
-- nil; one job joins the queued places to the network cluster by cluster (another cluster's
-- times come from a local search seeded with the cache), fills the memo and fires
-- BASTIANS_GRAPH_TIMES once, so the rows draw again and find their times. A place the network
-- cannot reach is remembered as false: no time, and no second try until the cache is rebuilt.

Graph.TIME_PLACES = 8 -- a thing's places asked for a time: the nearest by straight line
Graph.MEMO_MAX = 6000 -- places remembered per cache; the memo starts over beyond that
Graph.APPROX_YARDS = 50 -- a place joined by a longer straight line has an approximate time

-- The memo's key of a place: its 4-yard cell (a continent spans less than 40,000 yards).
local function memoKey(wx, wy)
  return (floor(wx / 4) + 5000) * 10001 + floor(wy / 4) + 5000
end

-- A cluster's times, seeded with the cache's (the character's own cluster was searched in full).
local function clusterTimes(net, key)
  if key == cache.key then
    return cache.times
  end
  local filled = cache.clusters[key]
  if not filled then
    filled = Data.Net.ClusterTimes(net, key, cache.times, { speeds = speedsOf(nil) })
    cache.clusters[key] = filled
  end
  return filled
end

-- Joins the queued places to the network, one cluster per slice; reads the cache afresh for each
-- cluster, so a cache rebuilt meanwhile answers the rest (the positions stay valid).
local function drain(yield)
  local Net = Data.Net
  while next(cache.queue) and cache.times do
    local queue = cache.queue
    cache.queue = {}
    local byCluster, order = {}, {}
    for k, p in pairs(queue) do
      local key = Net.ClusterKey(p[1], p[2])
      if not byCluster[key] then
        byCluster[key] = {}
        order[#order + 1] = key
      end
      byCluster[key][k] = p
    end
    table.sort(order)
    for _, key in ipairs(order) do
      local net = cache.times and netFor(cache.map)
      if not net then
        break
      end
      local times = clusterTimes(net, key)
      local ground = speedsOf(nil).ground or Net.RUN_SPEED
      for k, p in pairs(byCluster[key]) do
        local n, d = Net.Join(net, p[1], p[2], p[3])
        local t = n and times[n]
        if cache.memoCount >= Graph.MEMO_MAX then
          cache.memo, cache.approx, cache.memoCount = {}, {}, 0
        end
        cache.memo[k] = t and t + d / ground or false
        cache.approx[k] = t and d > Graph.APPROX_YARDS or nil
        cache.memoCount = cache.memoCount + 1
      end
      if yield then
        yield()
      end
    end
  end
  cache.queue = {}
  cache.draining = nil
  cache.generation = cache.generation + 1
  B:Fire("BASTIANS_GRAPH_TIMES", cache.generation)
end

local function startDrain()
  if cache.draining then
    return
  end
  cache.draining = true
  if Graph.module then
    B.Jobs:Run(Graph.module, "graph-time-rows", drain, { budgetMs = 4 })
  else
    drain(nil)
  end
end

-- Seconds and the approx flag of a place on the cache's continent; nil while queued or unknown.
-- The height (optional) joins the place to its own floor.
local function placeTime(wx, wy, wz)
  local k = memoKey(wx, wy)
  local t = cache.memo[k]
  if t == nil then
    if not cache.queue[k] then
      cache.queue[k] = { wx, wy, wz }
    end
    startDrain()
    return nil
  end
  if not t then
    return nil
  end
  return t, cache.approx[k] or false
end

-- A thing's places on the cache's continent, the TIME_PLACES nearest the character first; kept
-- until the cache is rebuilt.
local function refPlaces(ref)
  local list = cache.refPlaces[ref]
  if list then
    return list
  end
  local _, px, py = B.Coords.Player()
  list = {}
  for _, p in ipairs(B:Entity(ref):Places()) do
    if p.map == cache.map and p.wx then
      list[#list + 1] = { p.wx, p.wy, px and ((p.wx - px) ^ 2 + (p.wy - py) ^ 2) or 0, p.wz }
    end
  end
  if #list > Graph.TIME_PLACES then
    table.sort(list, function(a, b)
      return a[3] < b[3]
    end)
    for i = #list, Graph.TIME_PLACES + 1, -1 do
      list[i] = nil
    end
  end
  cache.refPlaces[ref] = list
  return list
end

-- Seconds and an approx flag from the cache, never a search; nil when unknown or not cached yet
-- (BASTIANS_GRAPH_TIMES says when to ask again). A ref answers the fastest of its places.
function service:Time(target)
  if not cache.times then
    if not cache.pending then
      Graph.RefreshTimes()
    end
    return nil
  end
  if target == "player" then
    return 0, false
  end
  if type(target) == "string" then
    if not parse(target) then
      return nil
    end
    local best, bestApprox
    for _, p in ipairs(refPlaces(target)) do
      local t, approx = placeTime(p[1], p[2], p[4])
      if t and (not best or t < best) then
        best, bestApprox = t, approx
      end
    end
    if not best then
      return nil
    end
    return best, bestApprox
  end
  if not (type(target) == "table" and target.wx and target.map == cache.map) then
    return nil
  end
  return placeTime(target.wx, target.wy, target.wz)
end

-- Places with the role nearest the character by travel time: { { ref, place, seconds, approx } }.
function service:Nearest(role, n)
  if not cache.times then
    self:Time("player")
    return nil
  end
  local out = {}
  for _, hit in ipairs(self:Around("player", { roles = { role } }, 50)) do
    local seconds, approx = self:Time(hit.place)
    if seconds then
      out[#out + 1] = { ref = hit.ref, place = hit.place, seconds = seconds, approx = approx }
    end
  end
  table.sort(out, function(a, b)
    if a.seconds ~= b.seconds then
      return a.seconds < b.seconds
    end
    return a.ref < b.ref
  end)
  for i = #out, (n or 5) + 1, -1 do
    out[i] = nil
  end
  return out
end

Graph.EXPLORE_MINUTES = 10 -- the way limit by default (R26.11)
Graph.STAY_MINUTES = 60 -- how long an hourly activity is worked, by default

-- Whether a place of the thing on this continent is still queued (an unreachable one is not).
local function timing(ref)
  for _, p in ipairs(refPlaces(ref)) do
    if cache.memo[memoKey(p[1], p[2])] == nil then
      return true
    end
  end
  return false
end

local function worthOf(itemID)
  local w = B:Entity("item:" .. tostring(itemID)):Facet("worth")
  return w and w.copper or nil
end

-- The activities the apps offer within the way limit, by gold or XP per hour with the way there
-- (route.md "Explore"): { { ref, kind, activity, seconds, approx, gold, xp, unpriced } }, and how
-- many candidates on this continent wait for their time. filter = { minutes, stay, kinds, by }.
function service:Activities(filter, n)
  filter = filter or {}
  if not cache.times then
    self:Time("player")
    return nil, 0
  end
  local limit = (filter.minutes or Graph.EXPLORE_MINUTES) * 60
  local stay = (filter.stay or Graph.STAY_MINUTES) * 60
  local by = filter.by == "xp" and "xp" or "gold"
  local out, waiting = {}, 0
  for _, ref in ipairs(B:FacetCandidates("activity", filter)) do
    local act = B:Entity(ref):Facet("activity")
    if act and (not filter.kinds or filter.kinds[act.kind]) then
      local seconds, approx = self:Time(ref)
      if seconds == nil then
        if timing(ref) then
          waiting = waiting + 1
        end
      elseif seconds <= limit then
        local gold, xp, unpriced = Data.Activity.Rate(act, seconds, stay, worthOf)
        out[#out + 1] = {
          ref = ref,
          kind = act.kind,
          activity = act,
          seconds = seconds,
          approx = approx,
          gold = gold,
          xp = xp,
          unpriced = unpriced,
        }
      end
    end
  end
  table.sort(out, function(a, b)
    local x, y = a[by], b[by]
    if (x == nil) ~= (y == nil) then
      return x ~= nil
    end
    if x and x ~= y then
      return x > y
    end
    if a.seconds ~= b.seconds then
      return a.seconds < b.seconds
    end
    return a.ref < b.ref
  end)
  for i = #out, (n or 50) + 1, -1 do
    out[i] = nil
  end
  return out, waiting
end

-- Not yet (W6 step 3, W10): the isochrone, the session plan.
function service:Reach()
  return nil
end
-- ---------------------------------------------------------------------------------------------
-- The session plan (world-graph.md §10, W10 step 3): "what should I do for the next hour" as an
-- orienteering problem over the activities in reach: greedy by gain per second, then adjacent
-- swaps that shorten the way; bounded (SESSION_STOPS stops, two passes). Pure: plain tables in,
-- a plain table out. The first leg is the cache's time; the legs between stops are straight
-- lines at the ground speed with a detour factor (approx).
-- ---------------------------------------------------------------------------------------------

Graph.SESSION_STOPS = 12
Graph.SESSION_DETOUR = 1.3 -- a straight line between two stops, as walked
Graph.SESSION_MIN_STAY = 600 -- seconds an hourly activity is worked at least to be worth the way

local function legBetween(a, b, speed)
  if not (a and b) or a.map ~= b.map then
    return nil
  end
  return sqrt((a.wx - b.wx) ^ 2 + (a.wy - b.wy) ^ 2) * Graph.SESSION_DETOUR / speed
end

-- cands = { { ref, kind, value, hourly, takes, seconds, place = { map, wx, wy, wz } } }: `value`
-- per run, or per hour when `hourly`; `takes` the run's seconds; `seconds` the way from the
-- character. budget in seconds; opts = { speed (yards per second), stay (seconds an hourly stop
-- is worked at most), map (the character's continent: a place elsewhere is out) }.
-- -> { total, value, travel, stops = { { ref, kind, arrive, leave, travel,
-- stay, gain, place, approx } } }
function Graph.PlanSession(cands, budget, opts)
  opts = opts or {}
  local speed = opts.speed or Data.Net.RUN_SPEED
  local stay = opts.stay or Graph.STAY_MINUTES * 60
  local plan = { stops = {}, total = 0, value = 0, travel = 0 }
  local left = {}
  for _, c in ipairs(cands or {}) do
    local here = opts.map == nil or (c.place and c.place.map == opts.map)
    if here and c.place and c.value and (c.hourly or c.takes) then
      left[#left + 1] = c
    end
  end
  local at, clock = nil, 0
  local function fit(c, from)
    local leg = from and legBetween(from, c.place, speed) or c.seconds
    if not leg then
      return nil
    end
    local there
    if c.hourly then
      there = math.min(stay, budget - clock - leg)
      if there < Graph.SESSION_MIN_STAY then
        return nil
      end
    else
      there = c.takes
    end
    if leg + there > budget - clock then
      return nil
    end
    local gain = c.hourly and c.value * there / 3600 or c.value
    return leg, there, gain
  end
  while #plan.stops < Graph.SESSION_STOPS do
    local best, bestScore, bestLeg, bestStay, bestGain
    for i, c in ipairs(left) do
      local leg, there, gain = fit(c, at)
      if leg then
        local score = gain / math.max(leg + there, 1)
        if not best or score > bestScore then
          best, bestScore, bestLeg, bestStay, bestGain = i, score, leg, there, gain
        end
      end
    end
    if not best then
      break
    end
    local c = table.remove(left, best)
    plan.stops[#plan.stops + 1] = {
      ref = c.ref,
      kind = c.kind,
      travel = bestLeg,
      stay = bestStay,
      gain = bestGain,
      place = c.place,
      hourly = c.hourly,
      value = c.value,
      seconds = c.seconds,
      approx = at ~= nil,
    }
    clock = clock + bestLeg + bestStay
    at = c.place
  end
  -- adjacent swaps that shorten the way (two passes), then the clock again
  local stops = plan.stops
  local function legTo(i, from)
    return from and legBetween(from, stops[i].place, speed) or stops[i].seconds
  end
  for _ = 1, 2 do
    for i = 1, #stops - 1 do
      local prev = i > 1 and stops[i - 1].place or nil
      local nextPlace = stops[i + 2] and stops[i + 2].place or nil
      local a, b = stops[i], stops[i + 1]
      local now = (legTo(i, prev) or math.huge) + (legBetween(a.place, b.place, speed) or math.huge)
      local then_ = (legTo(i + 1, prev) or math.huge) + (legBetween(b.place, a.place, speed) or math.huge)
      if nextPlace then
        now = now + (legBetween(b.place, nextPlace, speed) or math.huge)
        then_ = then_ + (legBetween(a.place, nextPlace, speed) or math.huge)
      end
      if then_ < now - 1 then
        stops[i], stops[i + 1] = b, a
      end
    end
  end
  clock, at = 0, nil
  local kept = {}
  for i, s in ipairs(stops) do
    local leg = legTo(i, at)
    if not leg or clock + leg + s.stay > budget then
      break
    end
    s.travel, s.approx = leg, at ~= nil
    s.arrive, s.leave = clock + leg, clock + leg + s.stay
    clock = s.leave
    at = s.place
    plan.value = plan.value + s.gain
    plan.travel = plan.travel + leg
    kept[#kept + 1] = s
  end
  -- the time the shorter way saved goes to the last stop when it is an hourly one
  local last = kept[#kept]
  if last and last.hourly and clock < budget then
    local more = budget - clock
    last.stay, last.leave = last.stay + more, last.leave + more
    last.gain = last.value * last.stay / 3600
    plan.value = plan.value + last.value * more / 3600
    clock = budget
  end
  plan.stops, plan.total = kept, clock
  return plan
end

-- The plan for the next `minutes` over the activities in reach (filter as Activities: kinds, by,
-- stay); callback(plan) at once, or callback(nil, why). The plan's stops carry the activities'
-- refs; the route service's Tour takes them as stops.
function service:Session(minutes, filter, callback)
  filter = filter or {}
  local budget = (minutes or 60) * 60
  local hits, waiting = self:Activities({ minutes = budget / 60, kinds = filter.kinds, by = filter.by }, 50)
  if not hits then
    if callback then
      callback(nil, "timing")
    end
    return nil
  end
  local by = filter.by == "xp" and "xp" or "copper"
  local cands = {}
  for _, hit in ipairs(hits) do
    local run, hour = Data.Activity.Value(hit.activity, worthOf)
    local places = refPlaces(hit.ref)
    local p = places[1]
    local hourly = run[by] == nil and hour[by] ~= nil
    local value = hourly and hour[by] or run[by]
    if p and value and (hourly or hit.activity.takes) then
      cands[#cands + 1] = {
        ref = hit.ref,
        kind = hit.kind,
        value = value,
        hourly = hourly,
        takes = hit.activity.takes,
        seconds = hit.seconds,
        place = { map = cache.map, wx = p[1], wy = p[2], wz = p[4] },
      }
    end
  end
  local plan = Graph.PlanSession(cands, budget, {
    speed = speedsOf(filter).ground or Data.Net.RUN_SPEED,
    stay = (filter.stay or Graph.STAY_MINUTES) * 60,
    map = cache.map,
  })
  plan.by, plan.budget, plan.waiting = by, budget, waiting
  if callback then
    callback(plan)
  end
  return plan
end

-- { { ref, props } } along the named edge; dir "out" (default) or "in"; nil for an unknown edge.
function service:Edges(ref, edge, dir)
  local def = EDGES[edge]
  local typ, id = parse(ref or "")
  if not (def and typ) then
    return nil
  end
  local side = dir == "in" and def.into or def.out
  local fn = side and side[typ]
  if not fn then
    return {}
  end
  local d = data()
  return fn(d and d:Get(typ, id) or {}, ref)
end

function service:Facet(ref, facet)
  if type(ref) ~= "string" or not parse(ref) then
    return nil
  end
  return B:Entity(ref):Facet(facet)
end

local BASE_PROFILES = { "fastest", "noswim", "safe", "nocost" }

function service:Profiles()
  local out = {}
  for _, p in ipairs(BASE_PROFILES) do
    out[#out + 1] = p
  end
  local names = {}
  for name, ext in pairs(B:GraphExtensions()) do
    for profile in pairs(ext.profiles or {}) do
      names[#names + 1] = name .. "." .. profile
    end
  end
  table.sort(names)
  for _, p in ipairs(names) do
    out[#out + 1] = p
  end
  return out
end

-- The character overlay (world-graph.md §9), read only: { taxi = { [nodeID] = true }, hearth }.
function service:Character()
  return Graph.char
end

-- Learned facts (world-graph.md §9): { kind = "taxi", from, to, seconds } keeps the newest time per
-- pair, in the direction flown (from and to are taxi node ids or `taxinode:<id>` refs);
-- { kind = "taxinode", id, account } marks a flight master known to the character and the account
-- (`account = true`: the account only); { kind = "ride", ref, wait } and { kind = "walk", points }
-- are kept for the build's captures (W11). Returns true when the fact was stored.
local LEARNED_KINDS = { taxi = true, taxinode = true, ride = true, walk = true }
Graph.WALKS_KEPT = 200

-- 2, "2" or "taxinode:2" -> 2; nil for anything else.
local function taxiID(v)
  if type(v) == "string" then
    v = v:match("^taxinode:(%d+)$") or v
  end
  return tonumber(v)
end
Graph.TaxiNodeID = taxiID

function service:Learn(fact)
  local learned = Graph.learned
  if not (learned and type(fact) == "table" and LEARNED_KINDS[fact.kind]) then
    return false
  end
  if fact.kind == "taxinode" then
    local id = taxiID(fact.id)
    if not (id and Graph.char and Graph.account) then
      return false
    end
    if Graph.account.taxi[id] and (fact.account or Graph.char.taxi[id]) then
      return false -- known already: nothing changed
    end
    Graph.account.taxi[id] = true
    if not fact.account then
      Graph.char.taxi[id] = true
    end
    B:Fire("BASTIANS_GRAPH_CHANGED", "character")
    return true
  end
  if fact.kind == "taxi" then
    local from, to = taxiID(fact.from), taxiID(fact.to)
    if not (from and to and type(fact.seconds) == "number" and fact.seconds > 0) then
      return false
    end
    learned.taxi["taxinode:" .. from .. ">taxinode:" .. to] = fact.seconds
  elseif fact.kind == "ride" then
    if not (fact.ref and type(fact.wait) == "number") then
      return false
    end
    local list = learned.ride[fact.ref] or {}
    learned.ride[fact.ref] = list
    list[#list + 1] = fact.wait
  else
    if type(fact.points) ~= "table" or #fact.points < 2 or type(fact.map) ~= "number" then
      return false
    end
    local walks = learned.walk
    walks[#walks + 1] = { map = fact.map, points = fact.points, len = fact.len, at = fact.at }
    while #walks > Graph.WALKS_KEPT do
      table.remove(walks, 1)
    end
  end
  B:Fire("BASTIANS_GRAPH_CHANGED", "learned")
  return true
end

-- ---------------------------------------------------------------------------------------------
-- The `travel` service as a shim over the graph (core-contracts §11), until the end of W8.

Graph.FROM_PLAYER_YARDS = 50 -- a leg that starts this close to the character starts at the cache

-- Estimate({ continent, wx, wy }, { continent, wx, wy }) -> seconds; or nil, "unknown" when the
-- graph holds the goal's continent but has no time for it (not cached yet, unreachable); or nil
-- without a network there, or for a leg that does not start at the character (the cache's only
-- origin): there the caller's straight line may stand in (data.md "Shims until W8").
Graph.travel = {
  Estimate = function(_, from, to)
    if not (from and to and from[1] and to[1] and to[2]) or not service:Ready(to[1]) then
      return nil
    end
    local c, wx, wy = B.Coords.Player()
    local near = c ~= nil
      and from[1] == c
      and abs(from[2] - wx) <= Graph.FROM_PLAYER_YARDS
      and abs(from[3] - wy) <= Graph.FROM_PLAYER_YARDS
    if not near then
      return nil
    end
    local seconds = service:Time({ map = to[1], wx = to[2], wy = to[3] })
    if seconds then
      return seconds
    end
    return nil, "unknown"
  end,
}

-- ---------------------------------------------------------------------------------------------
-- The walk sampler (world-graph.md §9, W11): while the character moves, its position every
-- SAMPLE_SECONDS; a stretch farther than OFF_NETWORK_YARDS from every waypoint of the continent's
-- network is a way the mesh missed (a tunnel, a building, a path through what it calls rock).
-- When the character is back on the network or stops, the stretch is learned as a walk when it
-- is long enough, and works for this player at once (Graph.WalkEdges). Captures carry it to the
-- build (tools/capture_import.py); positions and times only.
-- ---------------------------------------------------------------------------------------------

Graph.SAMPLE_SECONDS = 2
Graph.OFF_NETWORK_YARDS = 40 -- farther than this from every waypoint: off the network
Graph.WALK_MIN_YARDS = 40
Graph.WALK_MIN_POINTS = 3

local sampler = { ticker = nil, walk = nil } -- walk = { map, points, len, lastOn = { wx, wy } }
Graph.sampler = sampler

local function walkLength(points)
  local len = 0
  for i = 2, #points do
    len = len + sqrt((points[i][1] - points[i - 1][1]) ^ 2 + (points[i][2] - points[i - 1][2]) ^ 2)
  end
  return len
end

-- Ends the current stretch: learned when long enough; -> the fact or nil.
function Graph.CloseWalk(onPoint)
  local w = sampler.walk
  sampler.walk = nil
  if not w then
    return nil
  end
  local points = {}
  if w.lastOn then
    points[1] = w.lastOn
  end
  for _, p in ipairs(w.points) do
    points[#points + 1] = p
  end
  if onPoint then
    points[#points + 1] = onPoint
  end
  local len = walkLength(points)
  if #points < Graph.WALK_MIN_POINTS or len < Graph.WALK_MIN_YARDS then
    return nil
  end
  local fact = { kind = "walk", map = w.map, points = points, len = floor(len * 10 + 0.5) / 10, at = time() }
  if service:Learn(fact) then
    return fact
  end
  return nil
end

-- One sample: where the character stands against the network.
function Graph.Sample()
  local c, wx, wy = B.Coords.Player()
  local net = c and netFor(c)
  if not net then
    Graph.CloseWalk(nil)
    return nil
  end
  local Net = Data.Net
  local _, d = Net.Join(net, wx, wy)
  local on = d ~= nil and d <= Graph.OFF_NETWORK_YARDS
  local w = sampler.walk
  if on then
    if w and w.map == c then
      return Graph.CloseWalk({ wx, wy }) and "learned" or "on"
    end
    sampler.walk = nil
    sampler.lastOn = { c, { wx, wy } }
    return "on"
  end
  if not w or w.map ~= c then
    local lastOn = sampler.lastOn
    sampler.walk = { map = c, points = {}, lastOn = lastOn and lastOn[1] == c and lastOn[2] or nil }
    w = sampler.walk
  end
  local last = w.points[#w.points]
  if not (last and last[1] == wx and last[2] == wy) then
    w.points[#w.points + 1] = { wx, wy }
  end
  return "off"
end

function Graph.StartSampling()
  if sampler.ticker or not (C_Timer and C_Timer.NewTicker) then
    return
  end
  sampler.ticker = C_Timer.NewTicker(Graph.SAMPLE_SECONDS, Graph.Sample)
end

function Graph.StopSampling()
  if sampler.ticker then
    sampler.ticker:Cancel()
    sampler.ticker = nil
  end
  Graph.Sample() -- the last position, then the stretch ends
  Graph.CloseWalk(nil)
end

-- The learned facts, read only: { taxi = { ["taxinode:a>taxinode:b"] = seconds }, ride, walk }.
function service:Learned()
  return Graph.learned
end

-- What any character of the account knows, read only: { taxi = { [nodeID] = true } }.
function service:Account()
  return Graph.account
end

-- The taxi node id of a node of the open taxi map (Compat.GetTaxiNodes): its id when the data
-- knows it, else by the flight master's name; nil when neither matches.
local nameToTaxi
function Graph.TaxiIDOf(node)
  local d = data()
  if not (node and d) then
    return nil
  end
  if node.id and d:Get("flightpath", node.id) then
    return node.id
  end
  if not nameToTaxi then
    nameToTaxi = {}
    for _, id in ipairs(d:Each("flightpath") or {}) do
      local r = d:Get("flightpath", id)
      if r and r.name then
        nameToTaxi[r.name] = id
      end
    end
  end
  return node.name and nameToTaxi[node.name] or nil
end

-- TAXIMAP_OPENED: the current and reachable flight masters become known (world-graph.md §9);
-- returns how many were new.
function Graph.LearnTaxiMap()
  local new = 0
  for _, n in ipairs(B.Compat.GetTaxiNodes()) do
    if n.state == "current" or n.state == "reachable" then
      local id = Graph.TaxiIDOf(n)
      if id and service:Learn({ kind = "taxinode", id = id }) then
        new = new + 1
      end
    end
  end
  return new
end

-- Called from the Data module's OnEnable.
function Graph.Attach(module)
  local db = module:GetDB()
  if type(db.global.learned) ~= "table" then
    db.global.learned = {}
  end
  local learned = db.global.learned
  for _, k in ipairs({ "taxi", "ride", "walk" }) do
    if type(learned[k]) ~= "table" then
      learned[k] = {}
    end
  end
  Graph.learned = learned
  if type(db.char.graph) ~= "table" then
    db.char.graph = {}
  end
  if type(db.char.graph.taxi) ~= "table" then
    db.char.graph.taxi = {}
  end
  Graph.char = db.char.graph
  if type(db.global.graph) ~= "table" then
    db.global.graph = {}
  end
  if type(db.global.graph.taxi) ~= "table" then
    db.global.graph.taxi = {}
  end
  Graph.account = db.global.graph -- what any character of the account knows
  Graph.module = module
  B:ProvideService(module, "graph", service, { priority = 100 })
  B:ProvideService(module, "travel", Graph.travel, { priority = 100 })
  -- the distance cache follows the character: a new zone, standing still in another cluster, new
  -- data, a learned fact (no polling: these events say when to look)
  module:On("BASTIANS_PLAYER_MOVED_ZONE", function()
    Graph.RefreshTimes()
  end)
  module:RegisterEvent("TAXIMAP_OPENED", function()
    Graph.LearnTaxiMap()
  end)
  module:On("BASTIANS_DATA_LOADED", function(_, _, pack)
    nameToTaxi = nil
    if pack == "nav" then
      Graph.RefreshTimes(true)
    end
  end)
  module:On("BASTIANS_GRAPH_CHANGED", function()
    Graph.RefreshTimes(true)
  end)
  module:RegisterEvent("PLAYER_STARTED_MOVING", function()
    Graph.StartSampling()
  end)
  module:RegisterEvent("PLAYER_STOPPED_MOVING", function()
    Graph.StopSampling()
    Graph.RefreshTimes()
  end)
end
