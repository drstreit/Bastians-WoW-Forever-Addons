-- Bastian's Data: the world graph's network search (ADR 0026, data.md "The `graph` record"):
-- decodes one continent's record per cluster on demand into flat arrays and searches it
-- hierarchically. Pure: plain tables in and out, no WoW API (CLAUDE.md §7).
--
-- Memory (measured 25.10.2026 on the Forever pack): a table per edge cost 94 MB for both
-- continents; so nothing is decoded at load, a cluster's region level and links decode on their
-- own (a search crossing a cluster needs no more), its local level only where a search opens it,
-- all into arrays of numbers, and a bounded cache keeps the recently used ones.
local _, ns = ...
local Data = ns.Data

local Net = {}
Data.Net = Net

local floor, sqrt, abs, min, max = math.floor, math.sqrt, math.abs, math.min, math.max
local tonumber, ipairs, pairs, next = tonumber, ipairs, pairs, next
local insert = table.insert

Net.TILE = 1600 / 3
Net.RUN_SPEED = 7 -- yards a second on foot
Net.SWIM_SPEED = 4.7
Net.TAXI_SPEED = 29.85 -- measured on Forever 25.10.2026 (world-graph.md §6.3)
Net.NOSWIM_FACTOR = 20
Net.JOIN_YARDS = 300 -- a place farther than this from every waypoint of its cluster is not joined
Net.JOIN_Z_WEIGHT = 3 -- a yard of height counts as three on the ground when a place has a height
Net.CACHE_LOCAL = 24 -- clusters whose local level stays decoded between searches
Net.CACHE_REGION = 160 -- clusters whose region level and links stay decoded
Net.AVOID_FACTOR = 20 -- the safe profile's weight of a deadly way (route.md "Route options")
Net.SAFE_RING = 0 -- clusters around the fastest route the safe search opens besides its own

-- --- decoding -------------------------------------------------------------------------------

-- calls fn(record) per record of "a,b;c,d" (sep ";") or "a|b" (sep "|")
local function eachRecord(text, sep, fn)
  if not text or text == "" then
    return
  end
  local pattern = sep == "|" and "([^|]*)|" or "([^;]*);"
  for r in (text .. sep):gmatch(pattern) do
    fn(r)
  end
end

-- "a,,c" -> { "a", "", "c" }: empty fields kept
local function fields(text)
  local out = {}
  for f in (text .. ","):gmatch("([^,]*),") do
    out[#out + 1] = f
  end
  return out
end

local function opt(f)
  return f ~= "" and tonumber(f) or nil
end

function Net.ClusterKey(x, y)
  local tx = floor(32 - y / Net.TILE)
  local ty = floor(32 - x / Net.TILE)
  return floor(tx / 2) * 32 + floor(ty / 2)
end

-- A network over one continent's `graph` record; decodes nothing yet.
function Net.New(rec)
  local net = { rec = rec, ranges = {}, keys = rec.keys or {}, byKey = {} }
  for key, range in pairs(rec.clusters or {}) do
    local f = fields(range)
    net.ranges[#net.ranges + 1] = { first = tonumber(f[1]), last = tonumber(f[2]), key = key }
  end
  table.sort(net.ranges, function(a, b)
    return a.first < b.first
  end)
  for wp, key in pairs(net.keys) do
    net.byKey[key] = wp
  end
  net.cache = { {}, {} } -- [1] local levels, [2] region levels: key -> decoded (false: none)
  net.used = { {}, {} } -- key -> stamp
  net.stamp = 0
  return net
end

-- The cluster key of a waypoint number, by its range.
function Net.ClusterOf(net, n)
  local lo, hi = 1, #net.ranges
  while lo <= hi do
    local mid = floor((lo + hi) / 2)
    local r = net.ranges[mid]
    if n < r.first then
      hi = mid - 1
    elseif n > r.last then
      lo = mid + 1
    else
      return r.key
    end
  end
  return nil
end

local function remember(net, level, key, value, limit)
  net.stamp = net.stamp + 1
  local cache, used = net.cache[level], net.used[level]
  cache[key], used[key] = value, net.stamp
  local count, oldest, oldestKey = 0, nil, nil
  for k, s in pairs(used) do
    count = count + 1
    if not oldest or s < oldest then
      oldest, oldestKey = s, k
    end
  end
  if count > limit and oldestKey ~= key then
    cache[oldestKey], used[oldestKey] = nil, nil
  end
  return value
end

local function touch(net, level, key)
  local v = net.cache[level][key]
  if v ~= nil then
    net.stamp = net.stamp + 1
    net.used[level][key] = net.stamp
  end
  return v
end

local function wayArrays()
  return {
    a = {},
    b = {},
    len = {},
    road = {},
    swim = {},
    up = {},
    down = {},
    indoor = {},
    area = {},
    danger = {},
    flags = {},
  }
end

-- "a,b,len,road,swim,up,down,indoor,area,danger,flags" rows into the arrays of t; the count
local function decodeWays(text, t)
  local n = 0
  eachRecord(text, ";", function(r)
    local f = fields(r)
    n = n + 1
    t.a[n], t.b[n] = tonumber(f[1]), tonumber(f[2])
    t.len[n], t.road[n], t.swim[n] = tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
    t.up[n], t.down[n], t.indoor[n] = tonumber(f[6]), tonumber(f[7]), tonumber(f[8])
    t.area[n], t.danger[n], t.flags[n] = opt(f[9]), opt(f[10]), f[11] or ""
  end)
  return n
end

local function oneway(flags)
  return flags:find("o", 1, true) ~= nil
end

-- The cluster's local level: waypoints x, y, z (by number) and its ways with an adjacency of
-- signed way indices (+w along the way, -w against it), decoded once into arrays.
function Net.Cluster(net, key)
  local c = touch(net, 1, key)
  if c ~= nil then
    return c or nil
  end
  local range = net.rec.clusters and net.rec.clusters[key]
  if not range then
    return remember(net, 1, key, false, Net.CACHE_LOCAL) or nil
  end
  local f = fields(range)
  c = { key = key, first = tonumber(f[1]), last = tonumber(f[2]), x = {}, y = {}, z = {}, adj = {} }
  local n = c.first
  eachRecord(net.rec.wp and net.rec.wp[key], ";", function(r)
    local w = fields(r)
    c.x[n], c.y[n], c.z[n] = tonumber(w[1]), tonumber(w[2]), tonumber(w[3])
    n = n + 1
  end)
  c.w = wayArrays()
  local count = decodeWays(net.rec.ways and net.rec.ways[key], c.w)
  c.w.bends = {}
  local i = 0
  eachRecord(net.rec.bends and net.rec.bends[key], "|", function(r)
    i = i + 1
    c.w.bends[i] = r
  end)
  for w = 1, count do
    local a, b = c.w.a[w], c.w.b[w]
    c.adj[a] = c.adj[a] or {}
    insert(c.adj[a], w)
    if not oneway(c.w.flags[w]) and b >= c.first and b <= c.last then
      c.adj[b] = c.adj[b] or {}
      insert(c.adj[b], -w)
    end
  end
  return remember(net, 1, key, c, Net.CACHE_LOCAL)
end

-- The cluster's region level ("a,b,p,len,road,swim,indoor,danger,flags") and its links (the ways
-- leaving it, in the format of the ways), decoded once into arrays with per-node row lists.
function Net.Region(net, key)
  local r = touch(net, 2, key)
  if r ~= nil then
    return r or nil
  end
  if not (net.rec.clusters and net.rec.clusters[key]) then
    return remember(net, 2, key, false, Net.CACHE_REGION) or nil
  end
  r = {
    b = {},
    len = {},
    road = {},
    swim = {},
    indoor = {},
    danger = {},
    flags = {},
    nOnly = {},
    from = {},
  }
  local n = 0
  eachRecord(net.rec.region and net.rec.region[key], ";", function(row)
    local f = fields(row)
    n = n + 1
    local a = tonumber(f[1])
    r.b[n], r.nOnly[n] = tonumber(f[2]), f[3] == "n"
    r.len[n], r.road[n], r.swim[n] = tonumber(f[4]), tonumber(f[5]), tonumber(f[6])
    r.indoor[n], r.danger[n], r.flags[n] = tonumber(f[7]), opt(f[8]), f[9] or ""
    r.from[a] = r.from[a] or {}
    insert(r.from[a], n)
  end)
  r.l = wayArrays()
  r.lfrom = {}
  local count = decodeWays(net.rec.links and net.rec.links[key], r.l)
  for w = 1, count do
    local a = r.l.a[w]
    r.lfrom[a] = r.lfrom[a] or {}
    insert(r.lfrom[a], w)
  end
  return remember(net, 2, key, r, Net.CACHE_REGION)
end

-- The position of a waypoint (decodes its cluster's local level).
function Net.Point(net, n)
  local key = Net.ClusterOf(net, n)
  local c = key and Net.Cluster(net, key)
  if c and c.x[n] then
    return { x = c.x[n], y = c.y[n], z = c.z[n] }
  end
  return nil
end

-- The nearest waypoint to (x, y) in its cluster by straight line: n, yards; nil when the cluster
-- has none within JOIN_YARDS. With a height z the choice weighs height over ground
-- (JOIN_Z_WEIGHT), so a place under another floor (Undercity under the ruins) joins its own
-- floor, not the one above (R25.42); the yards are then the straight line in three dimensions.
-- Without z (the character: UnitPosition's height is always 0, measured 22./23.10.2026) the plane.
function Net.Join(net, x, y, z)
  local c = Net.Cluster(net, Net.ClusterKey(x, y))
  if not c then
    return nil
  end
  local wz = Net.JOIN_Z_WEIGHT
  local best, bestScore, bestFlat, bestDz
  for n = c.first, c.last do
    local px = c.x[n]
    if px then
      local dx, dy = px - x, c.y[n] - y
      local flat = dx * dx + dy * dy
      local dz = z and c.z[n] and (c.z[n] - z) or 0
      local score = flat + wz * wz * dz * dz
      if not bestScore or score < bestScore then
        best, bestScore, bestFlat, bestDz = n, score, flat, dz
      end
    end
  end
  if best and sqrt(bestFlat) <= Net.JOIN_YARDS then
    return best, sqrt(bestFlat + bestDz * bestDz)
  end
  return nil
end

-- Seconds along len, swim and indoor yards for the speeds (indoor: no mount on Forever indoors).
local function secondsOf(len, swim, indoor, gs, is, ss)
  swim = swim or 0
  indoor = min(indoor or 0, len - swim)
  return max(len - swim - indoor, 0) / gs + indoor / is + swim / ss
end

-- Seconds along facts { len, swim, indoor } for the character's speeds { ground, indoor, swim }.
function Net.Seconds(f, speeds)
  speeds = speeds or {}
  return secondsOf(
    f.len,
    f.swim,
    f.indoor,
    speeds.ground or Net.RUN_SPEED,
    speeds.indoor or Net.RUN_SPEED,
    speeds.swim or Net.SWIM_SPEED
  )
end

-- The safe profile's weight of a way for a character (R26.5, route.md "Route options"): d = the
-- way's danger (the highest hostile level within 20 yards) minus the character's level, three more
-- with an elite; 1 up to d = -5, 1.5 at d = 0, one more per level above, at most AVOID_FACTOR; the
-- other faction's guards along the way weigh AVOID_FACTOR. Pure.
function Net.SafeFactor(danger, flags, level, faction)
  local f = 1
  if danger and level then
    local d = danger - level
    if flags and flags:find("e", 1, true) then
      d = d + 3
    end
    if d > -5 then
      f = d <= 0 and 1 + 0.1 * (d + 5) or 1.5 + d
    end
  end
  local other = faction == "A" and "H" or faction == "H" and "A" or nil
  if other and flags and flags:find(other, 1, true) then
    f = Net.AVOID_FACTOR
  end
  return min(f, Net.AVOID_FACTOR)
end

-- --- a binary heap of keys with their nodes (two arrays, no table per entry) -----------------

local function push(hk, hn, k, n)
  local i = #hk + 1
  hk[i], hn[i] = k, n
  while i > 1 do
    local p = floor(i / 2)
    if hk[p] <= hk[i] then
      break
    end
    hk[p], hk[i], hn[p], hn[i] = hk[i], hk[p], hn[i], hn[p]
    i = p
  end
end

local function pop(hk, hn)
  local k, n = hk[1], hn[1]
  local last = #hk
  hk[1], hn[1] = hk[last], hn[last]
  hk[last], hn[last] = nil, nil
  local size, i = last - 1, 1
  while true do
    local l, r, s = 2 * i, 2 * i + 1, i
    if l <= size and hk[l] < hk[s] then
      s = l
    end
    if r <= size and hk[r] < hk[s] then
      s = r
    end
    if s == i then
      break
    end
    hk[s], hk[i], hn[s], hn[i] = hk[i], hk[s], hn[i], hn[s]
    i = s
  end
  return k, n
end

-- --- the search -----------------------------------------------------------------------------

-- Dijkstra from the seeds { [n] = seconds }: times { [n] = seconds }, the trace (for each node
-- reached the node before, the kind: "w" local way, "r" region edge, "l" link, "x" extra; the
-- cluster key; the row index or the extra edge) and the costs. opts: speeds, profile, open =
-- { [key] = true } (clusters whose local level is searched), extra = { [n] = { { b, seconds,
-- mode } } }, localOnly, goal, goals = { [n] = true } (stops once every one is settled), limit
-- (seconds of cost), yield; safe = { level, faction } weighs each way's cost by its danger
-- (Net.SafeFactor; the times stay real seconds); target = { x, y } and vmax (yards a
-- second, the fastest way to move in play) turn it into A*: the heuristic is the straight line from
-- the node's cluster centre to the target, less the cluster's half diagonal, at vmax (admissible,
-- not consistent: a node found cheaper later is opened again).
function Net.Search(net, seeds, opts)
  opts = opts or {}
  local speeds = opts.speeds or {}
  local gs, is = speeds.ground or Net.RUN_SPEED, speeds.indoor or Net.RUN_SPEED
  local ss = speeds.swim or Net.SWIM_SPEED
  local noswim = opts.profile == "noswim"
  local penalty = noswim and (Net.NOSWIM_FACTOR - 1) / ss or 0
  local safe = opts.safe
  local lvl, side = safe and safe.level, safe and safe.faction
  local function weight(danger, flags)
    if not safe or not (danger or (flags and flags ~= "")) then
      return 1
    end
    return Net.SafeFactor(danger, flags, lvl, side)
  end
  local open, extra, localOnly = opts.open or {}, opts.extra, opts.localOnly
  local goal, limit, yield = opts.goal, opts.limit, opts.yield
  local goals, left = opts.goals, 0
  for _ in pairs(goals or {}) do
    left = left + 1
  end
  local target, vmax = opts.target, opts.vmax
  local hcache = {}
  local radius = Net.TILE * sqrt(2)
  local function h(n)
    if not target then
      return 0
    end
    local key = Net.ClusterOf(net, n)
    local v = key and hcache[key]
    if v == nil then
      v = 0
      if key then
        local cx, cy = floor(key / 32), key % 32
        local dx, dy = (31 - 2 * cy) * Net.TILE - target.x, (31 - 2 * cx) * Net.TILE - target.y
        local d = sqrt(dx * dx + dy * dy) - radius
        v = d > 0 and d / vmax or 0
        hcache[key] = v
      end
    end
    return v
  end
  local heldL, heldR = {}, {} -- the clusters this search uses stay alive while it runs
  local best, secs, done, hk, hn = {}, {}, {}, {}, {}
  local tf, tk, tkey, ti = {}, {}, {}, {}
  for n, s in pairs(seeds) do
    best[n], secs[n] = s, s
    push(hk, hn, s + h(n), n)
  end
  local function try(n, k, b, step, swim, kind, key, idx, factor)
    local nk = k + step * (factor or 1) + (swim or 0) * penalty
    local old = best[b]
    if not old or nk < old - 1e-9 then
      best[b], secs[b] = nk, secs[n] + step
      tf[b], tk[b], tkey[b], ti[b] = n, kind, key, idx
      done[b] = nil
      push(hk, hn, nk + h(b), b)
    end
  end
  local popped = 0
  while #hk > 0 do
    local priority, n = pop(hk, hn)
    popped = popped + 1
    if yield and popped % 256 == 0 then
      yield()
    end
    local k = best[n]
    if not done[n] and priority <= k + h(n) + 1e-9 then
      done[n] = true
      if n == goal or (limit and k > limit) then
        break
      end
      if goals and goals[n] then
        left = left - 1
        if left == 0 then
          break
        end
      end
      local key = Net.ClusterOf(net, n)
      if key and open[key] then
        local c = heldL[key]
        if c == nil then
          c = Net.Cluster(net, key) or false
          heldL[key] = c
        end
        if c then
          local w = c.w
          for _, s in ipairs(c.adj[n] or {}) do
            local i = abs(s)
            local b = s > 0 and w.b[i] or w.a[i]
            local step = secondsOf(w.len[i], w.swim[i], w.indoor[i], gs, is, ss)
            try(n, k, b, step, w.swim[i], "w", key, s, weight(w.danger[i], w.flags[i]))
          end
        end
      end
      if key and not localOnly then
        local r = heldR[key]
        if r == nil then
          r = Net.Region(net, key) or false
          heldR[key] = r
        end
        if r then
          for _, i in ipairs(r.from[n] or {}) do
            if noswim or not r.nOnly[i] then
              try(
                n,
                k,
                r.b[i],
                secondsOf(r.len[i], r.swim[i], r.indoor[i], gs, is, ss),
                r.swim[i],
                "r",
                key,
                i,
                weight(r.danger[i], r.flags[i])
              )
            end
          end
          local l = r.l
          for _, i in ipairs(r.lfrom[n] or {}) do
            local step = secondsOf(l.len[i], l.swim[i], l.indoor[i], gs, is, ss)
            try(n, k, l.b[i], step, l.swim[i], "l", key, i, weight(l.danger[i], l.flags[i]))
          end
        end
      end
      if not localOnly and extra and extra[n] then
        for _, e in ipairs(extra[n]) do
          try(n, k, e.b, e.seconds, 0, "x", nil, e)
        end
      end
    end
  end
  return secs, { from = tf, kind = tk, key = tkey, idx = ti }, best
end

-- The leg's edge as a table (only for the legs of a found route): facts, area, bends, mode.
local function edgeOf(net, kind, key, idx)
  if kind == "x" then
    return idx
  end
  if kind == "w" then
    local w = Net.Cluster(net, key).w
    local i = abs(idx)
    local rev = idx < 0
    return {
      facts = {
        len = w.len[i],
        road = w.road[i],
        swim = w.swim[i],
        indoor = w.indoor[i],
        up = rev and w.down[i] or w.up[i],
        down = rev and w.up[i] or w.down[i],
      },
      area = w.area[i],
      danger = w.danger[i],
      flags = w.flags[i],
      bends = w.bends[i] or "",
      reverse = rev,
    }
  end
  local r = Net.Region(net, key)
  if kind == "r" then
    return {
      region = true,
      facts = { len = r.len[idx], road = r.road[idx], swim = r.swim[idx], indoor = r.indoor[idx] },
      danger = r.danger[idx],
      flags = r.flags[idx],
    }
  end
  local l = r.l
  return {
    link = true,
    facts = {
      len = l.len[idx],
      road = l.road[idx],
      swim = l.swim[idx],
      indoor = l.indoor[idx],
      up = l.up[idx],
      down = l.down[idx],
    },
    area = l.area[idx],
    danger = l.danger[idx],
    flags = l.flags[idx],
  }
end

local function legsTo(net, trace, from, to)
  local legs, n = {}, to
  while n ~= from and trace.from[n] do
    insert(legs, 1, {
      from = trace.from[n],
      to = n,
      edge = edgeOf(net, trace.kind[n], trace.key[n], trace.idx[n]),
    })
    n = trace.from[n]
  end
  return legs
end
Net.LegsTo = legsTo -- the legs back from `to` to `from` (nil: to the search's seed)

-- The route between two positions { x, y, z } (z optional) on this continent: { seconds, legs =
-- { { from, to, edge } }, from, to, joinFrom, joinTo }, or nil and the reason.
function Net.Route(net, from, to, opts)
  opts = opts or {}
  local a, da = Net.Join(net, from.x, from.y, from.z)
  local b, db = Net.Join(net, to.x, to.y, to.z)
  if not a then
    return nil, "start off the network"
  end
  if not b then
    return nil, "goal off the network"
  end
  local ground = (opts.speeds or {}).ground or Net.RUN_SPEED
  local extra = opts.extra
  if opts.startEdges then
    -- edges from wherever the character stands (the hearth): on the start waypoint
    local copy = {}
    for n, list in pairs(extra or {}) do
      copy[n] = list
    end
    local here = {}
    for _, e in ipairs(copy[a] or {}) do
      here[#here + 1] = e
    end
    for _, e in ipairs(opts.startEdges) do
      here[#here + 1] = e
    end
    copy[a], extra = here, copy
  end
  local open = { [Net.ClusterOf(net, a)] = true, [Net.ClusterOf(net, b)] = true }
  local search = {
    speeds = opts.speeds,
    profile = opts.profile,
    extra = extra,
    open = open,
    goal = b,
    yield = opts.yield,
    target = to,
    vmax = opts.vmax or Net.Fastest(extra, ground),
  }
  local secs, trace = Net.Search(net, { [a] = da / ground }, search)
  if not secs[b] then
    return nil, "no way"
  end
  if opts.safe then
    -- the region level was chosen by time: open the local ways along the fastest route (and
    -- SAFE_RING clusters around it), where the detours around danger lie, and search weighed
    for _, leg in ipairs(legsTo(net, trace, a, b)) do
      for _, n in ipairs({ leg.from, leg.to }) do
        local key = Net.ClusterOf(net, n)
        if key then
          local cx, cy = floor(key / 32), key % 32
          for dx = -Net.SAFE_RING, Net.SAFE_RING do
            for dy = -Net.SAFE_RING, Net.SAFE_RING do
              local x, y = cx + dx, cy + dy
              if x >= 0 and x < 32 and y >= 0 and y < 32 then
                open[x * 32 + y] = true
              end
            end
          end
        end
      end
    end
    search.safe = opts.safe
    secs, trace = Net.Search(net, { [a] = da / ground }, search)
    if not secs[b] then
      return nil, "no way"
    end
  end
  return {
    seconds = secs[b] + db / ground,
    legs = legsTo(net, trace, a, b),
    joinFrom = da,
    joinTo = db,
    from = a,
    to = b,
  }
end

-- The fastest way to move among the extra edges (yards over seconds; a jump such as the hearth or
-- a portal is infinitely fast) and the ground speed: the A* heuristic's speed.
function Net.Fastest(extra, ground)
  local v = ground or Net.RUN_SPEED
  for _, list in pairs(extra or {}) do
    for _, e in ipairs(list) do
      if e.jump or not e.len then
        return math.huge
      end
      if e.seconds > 0 then
        v = max(v, e.len / e.seconds)
      end
    end
  end
  return v
end

-- A region edge refined into its local ways (for drawing and the steps): { { from, to, edge } }.
function Net.Refine(net, leg, opts)
  if not leg.edge.region then
    return { leg }
  end
  local key = Net.ClusterOf(net, leg.from)
  local secs, trace = Net.Search(net, { [leg.from] = 0 }, {
    speeds = opts and opts.speeds,
    profile = opts and opts.profile,
    open = { [key] = true },
    goal = leg.to,
    localOnly = true,
  })
  if not secs[leg.to] then
    return { leg } -- the local level could not reproduce it; keep the region edge
  end
  return legsTo(net, trace, leg.from, leg.to)
end

local function bendPoints(text, out, reverse)
  local pts = {}
  for pt in (text .. ":"):gmatch("([^:]*):") do
    if pt ~= "" then
      local f = fields(pt)
      pts[#pts + 1] = { x = tonumber(f[1]), y = tonumber(f[2]) } -- 2D: the bends are for drawing
    end
  end
  if reverse then
    for i = #pts, 1, -1 do
      out[#out + 1] = pts[i]
    end
  else
    for _, p in ipairs(pts) do
      out[#out + 1] = p
    end
  end
end

-- A link's bends live with its way in the cluster where the way starts (either end's cluster).
local function linkBends(net, from, to)
  for _, side in ipairs({ { from, to, false }, { to, from, true } }) do
    local c = Net.Cluster(net, Net.ClusterOf(net, side[1]))
    for _, s in ipairs(c and c.adj[side[1]] or {}) do
      if s > 0 and c.w.b[s] == side[2] then
        return c.w.bends[s] or "", side[3]
      end
    end
  end
  return "", false
end

-- The points of a way or link leg in travel order: from, its bends, to.
function Net.LegPoints(net, leg)
  local out = {}
  local p = Net.Point(net, leg.from)
  if p then
    out[#out + 1] = p
  end
  local e = leg.edge
  if e.bends and e.bends ~= "" then
    bendPoints(e.bends, out, e.reverse)
  elseif e.link then
    local text, reverse = linkBends(net, leg.from, leg.to)
    bendPoints(text, out, reverse)
  end
  local q = Net.Point(net, leg.to)
  if q then
    out[#out + 1] = q
  end
  return out
end

-- Every time from the seeds over the region level and the open clusters (the distance cache).
function Net.Spread(net, seeds, opts)
  return Net.Search(net, seeds, opts)
end

-- Times inside one cluster, seeded with the times its waypoints already have.
function Net.ClusterTimes(net, key, times, opts)
  local c = Net.Cluster(net, key)
  if not c then
    return {}
  end
  local seeds = {}
  for n = c.first, c.last do
    if times[n] then
      seeds[n] = times[n]
    end
  end
  if next(seeds) == nil then
    return {}
  end
  local secs = Net.Search(net, seeds, {
    speeds = opts and opts.speeds,
    profile = opts and opts.profile,
    open = { [key] = true },
    localOnly = true,
  })
  local out = {}
  for n = c.first, c.last do
    out[n] = secs[n]
  end
  return out
end

-- The taxi flights of the continent as extra edges { [waypoint] = { { b, seconds, mode, ref } } }:
-- only between nodes in `known` ({ [nodeID] = true }; nil: every node), timed by `learned`
-- ({ ["taxinode:a>taxinode:b"] = seconds }), else by the pack's captured time (the flight's
-- fourth field, W11), else by the path's length at TAXI_SPEED.
function Net.TaxiEdges(net, known, learned, extra)
  extra = extra or {}
  eachRecord(net.rec.taxi, ";", function(r)
    local f = fields(r)
    local from, to, len = tonumber(f[1]), tonumber(f[2]), tonumber(f[3])
    local a, b = net.byKey["taxinode:" .. from], net.byKey["taxinode:" .. to]
    if a and b and (not known or (known[from] and known[to])) then
      local ref = "taxinode:" .. from .. ">taxinode:" .. to
      local seconds = learned and learned[ref] or opt(f[4] or "") or len / Net.TAXI_SPEED
      extra[a] = extra[a] or {}
      insert(extra[a], { b = b, seconds = seconds, mode = "taxi", ref = ref, len = len })
    end
  end)
  return extra
end
