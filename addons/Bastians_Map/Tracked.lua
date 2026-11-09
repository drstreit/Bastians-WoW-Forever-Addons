-- The herbs and ore the game's tracking finds (Find Herbs, Find Minerals) on Bastian's own
-- minimap styles. Our tiles cover the game's minimap there and no API tells where its dots are;
-- the client only answers what the minimap's tooltip would say at a point
-- (Minimap:UpdateMouseoverAtPoint, C_TooltipInfo.GetMinimapMouseover). A sweep asks that over a
-- grid of the covered minimap, groups the points that answered the same name, and turns each
-- group's centre into world yards by the game minimap's own geometry: its size in our view and its
-- own zoom, never the camera's (our view is scaled, round or square, and zoomed
-- on its own). The tooltip names all that is on the minimap; only a name the data knows as a herb
-- or a vein is a dot here, not the player, a quest giver or a creature. The grid
-- only finds a dot; it never moves, so it then gets one fine pass over all that answers its name,
-- and the centre of that is its place (the positions are to be exact; Mapzeroth's
-- LeyScan.lua does the same). Creatures a tracking spell shows (Track Beasts and its kin, owner,
-- Forever 08.11.2026: "track beasts is not working on our maps") get a pin too, only while such a
-- spell is on and only for an NPC of the data with no service: they walk, so a creature's pin
-- follows its dot and gets no fine pass. The dots go to the overlay as
-- live pins (Minimap.lua MM.SetLive), beside the layers' pins and whatever the layers say: they are
-- no layer (no dots on our styles; the layer they had been was switched off in
-- the profile, one pill among the map's). Polling where no event exists (CLAUDE.md rule 7): only
-- while our frame shows one of our styles, a few frames per sweep, slower while nothing changes,
-- nothing in the game's style, where the dots show by themselves.
local _, ns = ...
local B = Bastians
local S = B.UI.Style
local Map = ns.Map -- the hook lists (Map.lua); `mod` below is the module once enabled
local L = ns.L
local mod

local Tracked = {}

Tracked.STEP = 8 -- minimap pixels between two probe points (a dot answers 10 to 20 around it)
Tracked.FINE = 2 -- minimap pixels between two probe points of a dot's fine pass
Tracked.FINE_TRIES = 3 -- fine passes that heard nothing before a dot keeps the sweeps' place
Tracked.PER_FRAME = 60 -- probe points per frame
Tracked.WAIT = 1.2 -- seconds between two sweeps while the player moves or the dots change
Tracked.IDLE = 3 -- seconds between two sweeps while the player stands and nothing changed
Tracked.KEEP = 1 -- sweeps a known dot survives unseen before its pin goes
Tracked.SAME = 12 -- yards: a dot found this close to a known one of the same name is that one
Tracked.FOLLOW = 30 -- yards: the same for a creature, which walks between two sweeps
Tracked.MOVED = 1 -- yards: a known dot moved less than this keeps the overlay as it is
Tracked.STILL = 2 -- yards: a player who moved less than this between two sweeps stands
Tracked.MEAN = 6 -- sweeps a dot's place is averaged over until its fine pass
Tracked.MAX = 40 -- pins at most, the nearest
Tracked.STRIKES = 3 -- failed sweeps in a row before they rest until the next login
Tracked.RETRY = 30 -- seconds until the next sweep after a failed one
Tracked.stats = { sweeps = 0, probes = 0, known = 0, answered = 0, dots = 0, fine = 0, errors = 0 }
-- the node kinds that get a pin -> the glyph of it (the data says "mine" on Forever, "ore" on retail)
Tracked.GLYPH = { herb = "herb", mine = "mine", ore = "mine" }

local driver -- the frame whose OnUpdate runs a sweep
local sweep -- the sweep in progress: { points, i, hits, answered, w, continent, blind }
local fine -- the fine pass in progress: { dots, at, k, side, i, n, wx, wy }
-- the dots found so far: { ref, name, continent, wx, wy, ax, ay, n, missed, reach, fine, tries }
local known = {}
local counter = 0
local nextAt = 0 -- GetTime() of the next sweep
local strikes = 0 -- failed sweeps in a row
local broken -- the game raised an error STRIKES times in a row: no more sweeps this session
local byName -- lower-cased name of a herb or a vein -> its node kind, built on first use
local creatures = {} -- lower-cased name -> whether it is a creature without a service, per session
local grid -- the probe points of the last sweep's size and shape: { half, shape, points }
local namesOf = {} -- a tooltip line -> the names in it (Tracked.Names), kept per session
local lastPlace -- { continent, px, py } of the player at the last sweep's end
local lastReport -- what the last debug line said, so that only a new result is logged
local geo = {} -- the minimap's and the player's geometry of this frame, reused
local cursorOn = false -- this frame switched the minimap's soft cursor on: it gives it back
local heard = {} -- the names the last point asked answered (listen)

local function db()
  return mod and mod.db and mod.db.profile or {}
end

local function cvarBool(name)
  local get = C_CVar and C_CVar.GetCVar or rawget(_G, "GetCVar")
  local v = get and get(name)
  return v == "1" or v == 1 or v == true
end

-- Whether this client answers the minimap's tooltip at a point and the data can tell a herb from the
-- rest; else the reason, for the settings.
function Tracked.Available()
  if broken then
    return nil, L["the game refused the minimap sweep; it rests until the next login"]
  end
  if not B:GetService("data") then
    return nil, L["needs Bastian's Data to tell herbs and ore from the rest"]
  end
  if
    not (
      Minimap
      and type(Minimap.UpdateMouseoverAtPoint) == "function"
      and type(Minimap.SetUsingSoftCursor) == "function"
      and C_TooltipInfo
      and type(C_TooltipInfo.GetMinimapMouseover) == "function"
    )
  then
    return nil, L["this client does not let an addon read the minimap's dots"]
  end
  return true
end

-- Whether a sweep is wanted now: the setting, our frame showing one of our styles.
function Tracked.Active()
  if db().miniTracked == false then
    return false
  end
  return ns.Mini.Taken() and ns.Mini.Style() ~= "game"
end

function Tracked.Running()
  return driver ~= nil and driver:GetScript("OnUpdate") ~= nil
end

-- A controller drives the minimap's soft cursor itself: switching it on and off under it would
-- fight the game (Mapzeroth and SLLCM step back the same way).
local function controller()
  local util = rawget(_G, "InputUtil")
  if util and type(util.IsGamepadUIEnabled) == "function" and util.IsGamepadUIEnabled() then
    return true
  end
  local cursor = rawget(_G, "SoftCursor")
  return cursor ~= nil and type(cursor.IsShown) == "function" and cursor:IsShown() == true
end

-- No sweep now, and the known dots stay as they are: in combat the tooltip's texts may be secret.
local function paused()
  return InCombatLockdown() or controller()
end

-- --- pure -------------------------------------------------------------------------------------

-- The names in one line of the minimap's tooltip: the client colours them, puts an icon in front
-- and may name several dots in one text, a line each.
function Tracked.Names(text)
  local out = {}
  text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
  text = string.gsub(text, "|r", "")
  text = string.gsub(text, "|T.-|t", "")
  text = string.gsub(text, "|A.-|a", "")
  for line in string.gmatch(text, "[^\r\n]+") do
    local name = string.match(line, "^%s*(.-)%s*$")
    if name ~= "" then
      out[#out + 1] = name
    end
  end
  return out
end

-- Groups of grid points that touch (8-neighbourhood at the grid's step): { u, v, n, reach } each,
-- the centre of every group, how many points it holds and how far around the centre a fine pass has
-- to look (what answers ends before the next grid point out); with world yards in a point's third
-- and fourth place also their mean as wx, wy.
function Tracked.Cluster(points, step)
  local reach = step * 1.5
  local group = {}
  local groups = {}
  for i, p in ipairs(points) do
    local g
    for j = 1, i - 1 do
      local q = points[j]
      if math.abs(p[1] - q[1]) <= reach and math.abs(p[2] - q[2]) <= reach then
        local other = group[j]
        if g == nil then
          g = other
        elseif other ~= g then
          -- two groups touch through this point: the second joins the first
          for k = 1, i - 1 do
            if group[k] == other then
              group[k] = g
            end
          end
        end
      end
    end
    if g == nil then
      g = #groups + 1
      groups[g] = true
    end
    group[i] = g
  end
  local sums = {}
  for i, p in ipairs(points) do
    local g = group[i]
    local s = sums[g]
    if not s then
      s = { u = 0, v = 0, n = 0, wx = 0, wy = 0, placed = 0, u0 = p[1], u1 = p[1], v0 = p[2], v1 = p[2] }
      sums[g] = s
    end
    s.u, s.v, s.n = s.u + p[1], s.v + p[2], s.n + 1
    s.u0, s.u1 = math.min(s.u0, p[1]), math.max(s.u1, p[1])
    s.v0, s.v1 = math.min(s.v0, p[2]), math.max(s.v1, p[2])
    if p[3] and p[4] then
      s.wx, s.wy, s.placed = s.wx + p[3], s.wy + p[4], s.placed + 1
    end
  end
  local out = {}
  for _, s in pairs(sums) do
    local placed = s.placed > 0
    out[#out + 1] = {
      u = s.u / s.n,
      v = s.v / s.n,
      n = s.n,
      reach = math.max(s.u1 - s.u0, s.v1 - s.v0) / 2 + step,
      wx = placed and s.wx / s.placed or nil,
      wy = placed and s.wy / s.placed or nil,
    }
  end
  table.sort(out, function(a, b)
    if a.u ~= b.u then
      return a.u < b.u
    end
    return a.v < b.v
  end)
  return out
end

-- A point du right, dv up (pixels from the game minimap's centre) as world yards: the inverse of
-- the overlay's Project (world wx grows north and wy west; a rotating minimap turns by the facing).
function Tracked.ToWorld(du, dv, pxPerYard, facing, px, py)
  local east, north = du / pxPerYard, dv / pxPerYard
  if facing then
    local c, s = math.cos(facing), math.sin(facing)
    east, north = east * c - north * s, east * s + north * c
  end
  return px + north, py - east
end

-- --- the node kind of a dot's name -----------------------------------------------------------

-- The client names a dot in its language. The text packs translate objects, not nodes: the index
-- node.objects leads from a game object to its kind, and a herb's name is its item's. The node
-- records' English names cover a pack without that index.
local function kindOf(name)
  if not byName then
    local map, any = {}, false
    local function add(text, kind)
      if text and Tracked.GLYPH[kind] then
        map[string.lower(text)] = kind
        any = true
      end
    end
    local d = B:GetService("data")
    if d then
      for id, kind in pairs(d:Index("node.objects") or {}) do
        local r = d:Get("object", id)
        add(r and r.name, kind)
      end
      for _, id in ipairs(d:Each("node") or {}) do
        local r = d:Get("node", id)
        if r then
          add(r.name, r.kind)
          local item = r.kind == "herb" and r.item and d:Get("item", r.item)
          add(item and item.name, r.kind)
        end
      end
    end
    if not any then
      return nil -- the packs are not there yet: asked again with the next dot
    end
    byName = map
  end
  return byName[string.lower(name)]
end

-- The npc flags that mean a person with a service, not something to hunt (Data's kinds).
local SERVICE = {
  questgiver = true,
  trainer = true,
  vendor = true,
  repair = true,
  flightmaster = true,
  innkeeper = true,
  banker = true,
  battlemaster = true,
  auctioneer = true,
  stablemaster = true,
}

-- A record's flags come as a list, a set or one word (data.md).
local function hasService(r)
  local flags = r.flags
  if type(flags) ~= "table" then
    return SERVICE[flags] == true
  end
  for key, value in pairs(flags) do
    if SERVICE[key] or SERVICE[value] then
      return true
    end
  end
  return false
end

-- Whether a name on the minimap is a creature to hunt: an NPC of the data, exact name, no service.
-- A player is no NPC, a quest giver has a service: those two made stray pins before (05.11.2026).
local function isCreature(name)
  local key = string.lower(name)
  if creatures[key] ~= nil then
    return creatures[key]
  end
  local d = B:GetService("data")
  local found = false
  for _, hit in ipairs(d and d:Find("npc", name, 8) or {}) do
    if type(hit.name) == "string" and string.lower(hit.name) == key then
      local r = d:Get("npc", hit.id)
      if r and not hasService(r) then
        found = true
        break
      end
    end
  end
  creatures[key] = found
  return found
end

local function card(pin)
  return { title = pin.label, lines = { { text = L["Found by the game's tracking"] } }, hint = "" }
end

-- The known dots as the overlay's live pins, the nearest MAX around the player; in the game's
-- yellow, to tell them from the layers' pins.
local function publish(px, py)
  local list = known
  if #list > Tracked.MAX and px then
    list = {}
    for i, k in ipairs(known) do
      list[i] = k
    end
    table.sort(list, function(a, b)
      local da = (a.wx - px) ^ 2 + (a.wy - py) ^ 2
      local dk = (b.wx - px) ^ 2 + (b.wy - py) ^ 2
      if da ~= dk then
        return da < dk
      end
      return a.ref < b.ref
    end)
  end
  local pins = {}
  for i = 1, math.min(#list, Tracked.MAX) do
    local k = list[i]
    pins[i] = {
      kind = "tracked",
      ref = k.ref,
      continent = k.continent,
      wx = k.wx,
      wy = k.wy,
      icon = B.UI.IconTexture(k.kind == "creature" and B.UI.MobKind() or Tracked.GLYPH[k.kind]),
      color = S.C.gold,
      label = k.name,
      card = card,
    }
  end
  Tracked.stats.known = #known
  ns.Minimap.SetLive(pins)
end

local function forget()
  if #known > 0 then
    known = {}
    publish()
  end
  Tracked.stats.known = 0
end

-- --- the sweep --------------------------------------------------------------------------------

local function gridPoints(half, shape)
  if grid and grid.half == half and grid.shape == shape then
    return grid.points
  end
  local points = {}
  local step = Tracked.STEP
  local limit = half - 2
  local v = -half + step / 2
  while v < half do
    local u = -half + step / 2
    while u < half do
      if shape == "SQUARE" or u * u + v * v <= limit * limit then
        points[#points + 1] = { u, v }
      end
      u = u + step
    end
    v = v + step
  end
  grid = { half = half, shape = shape, points = points }
  return points
end

-- Pixels per yard of the game's minimap at its own zoom: the client's view radius where it tells
-- it (indoors too), else the overlay's table.
local function pixelsPerYard(w)
  local api = rawget(_G, "C_Minimap")
  if api and type(api.GetViewRadius) == "function" then
    local radius = B.Compat.Plain(api.GetViewRadius())
    if type(radius) == "number" and radius > 0 then
      return (w / 2) / radius
    end
  end
  return ns.Minimap.Scale()
end

-- The game minimap's place on the screen and the player's in the world, now. False while the
-- minimap has no place yet; geo.continent nil in an instance; geo.turned nil while a rotating
-- minimap's facing is unknown.
local function geometry()
  local w, h = Minimap:GetWidth(), Minimap:GetHeight()
  local left, bottom = Minimap:GetLeft(), Minimap:GetBottom()
  local scale = Minimap:GetEffectiveScale()
  if not (w and w > 0 and left and bottom and scale and scale > 0) then
    return false
  end
  geo.w, geo.scale = w, scale
  geo.cx, geo.cy = left + w / 2, bottom + (h or w) / 2
  geo.pxPerYard = pixelsPerYard(w)
  geo.continent, geo.px, geo.py = B.Coords.Player()
  geo.facing, geo.turned = nil, true
  if cvarBool("rotateMinimap") then
    geo.facing = B.Compat.GetPlayerFacing()
    geo.turned = geo.facing ~= nil
  end
  return true
end

-- The soft cursor for this frame's share of asking (onUpdate takes it back, also after an error).
local function cursor()
  cursorOn = true
  Minimap:SetUsingSoftCursor(true)
end

-- What the minimap's tooltip says at a point: the names in `heard`, how many, and whether a line
-- was a secret (a dot is there, which one is unknown).
local function listen(u, v)
  local plain = B.Compat.Plain
  local n, secret = 0, false
  Minimap:UpdateMouseoverAtPoint((geo.cx + u) * geo.scale, (geo.cy + v) * geo.scale)
  local data = C_TooltipInfo.GetMinimapMouseover()
  local lines = data and data.lines
  for j = 1, lines and #lines or 0 do
    local raw = lines[j].leftText
    local text = plain(raw)
    if type(text) == "string" then
      local names = namesOf[text]
      if not names then
        names = Tracked.Names(text)
        namesOf[text] = names
      end
      for _, name in ipairs(names) do
        n = n + 1
        heard[n] = name
      end
    elseif raw ~= nil then
      secret = true
    end
  end
  return n, secret
end

-- One frame's share of the sweep: every point's tooltip, every name in it, the point in world yards
-- of this frame (the player moves on during a sweep).
local function batch()
  local points, hits = sweep.points, sweep.hits
  local last = math.min(sweep.i + Tracked.PER_FRAME - 1, #points)
  cursor()
  for i = sweep.i, last do
    local p = points[i]
    local n, secret = listen(p[1], p[2])
    sweep.blind = sweep.blind or secret
    if n > 0 then
      local wx, wy = Tracked.ToWorld(p[1], p[2], geo.pxPerYard, geo.facing, geo.px, geo.py)
      for j = 1, n do
        local list = hits[heard[j]]
        if not list then
          list = {}
          hits[heard[j]] = list
        end
        list[#list + 1] = { p[1], p[2], wx, wy }
      end
      sweep.answered = sweep.answered + 1
    end
  end
  Tracked.stats.probes = Tracked.stats.probes + last - sweep.i + 1
  sweep.i = last + 1
end

local function report(found)
  if not B.debug then
    return
  end
  local names = {}
  for i = 1, math.min(#found, 8) do
    names[i] = found[i].name
  end
  local text = string.format(
    "minimap sweep: %d points, %d answered, %d dots%s",
    #sweep.points,
    sweep.answered,
    #found,
    #names > 0 and (" (" .. table.concat(names, ", ") .. ")") or ""
  )
  if text ~= lastReport then
    lastReport = text
    B:Log(mod, "debug", "%s", text)
  end
end

-- The dots of a sweep against the known ones: a known dot found again keeps its pin (until its fine
-- pass at the mean of its places), an unseen one survives KEEP sweeps, a new one gets a pin. Then
-- the wait: short while the player moves or something changed.
local function finish(now)
  local names = {}
  for name in pairs(sweep.hits) do
    names[#names + 1] = name
  end
  table.sort(names)
  local found = {}
  local hunting = B.Compat.CreatureTrackingOn() ~= false -- unknown: the data's filter still holds
  local pet = B.Compat.Plain(UnitName("pet"))
  for _, name in ipairs(names) do
    local kind = kindOf(name)
    if not kind and hunting and name ~= pet and isCreature(name) then
      kind = "creature"
    end
    if kind then
      for _, g in ipairs(Tracked.Cluster(sweep.hits[name], Tracked.STEP)) do
        found[#found + 1] = { name = name, kind = kind, wx = g.wx, wy = g.wy, reach = g.reach }
      end
    end
  end
  local stats = Tracked.stats
  stats.sweeps, stats.answered, stats.dots = stats.sweeps + 1, sweep.answered, #found
  report(found)
  local continent, blind = sweep.continent, sweep.blind
  sweep = nil
  strikes = 0

  local changed, restless = false, false
  local same2, moved2 = Tracked.SAME * Tracked.SAME, Tracked.MOVED * Tracked.MOVED
  local follow2 = Tracked.FOLLOW * Tracked.FOLLOW
  local kept = {}
  for _, k in ipairs(known) do
    local best, bestD
    for _, f in ipairs(found) do
      if not f.used and f.name == k.name and k.continent == continent then
        local dx, dy = f.wx - k.ax, f.wy - k.ay
        local d = dx * dx + dy * dy
        if d <= (k.kind == "creature" and follow2 or same2) and (not bestD or d < bestD) then
          best, bestD = f, d
        end
      end
    end
    if best then
      best.used = true
      k.reach = best.reach
      if k.kind == "creature" then -- it walks: the pin goes where the dot is now
        k.ax, k.ay = best.wx, best.wy
      elseif not k.fine then -- else its place is measured: the grid only saw it again
        k.n = math.min(k.n + 1, Tracked.MEAN)
        k.ax, k.ay = k.ax + (best.wx - k.ax) / k.n, k.ay + (best.wy - k.ay) / k.n
      end
      local dx, dy = k.ax - k.wx, k.ay - k.wy
      if dx * dx + dy * dy > moved2 then
        k.wx, k.wy = k.ax, k.ay
        changed = true
      end
      k.missed = 0
      kept[#kept + 1] = k
    elseif blind or k.continent ~= continent then
      kept[#kept + 1] = k -- a sweep that could not read every name tells nothing about this one
    else
      k.missed = k.missed + 1
      restless = true
      if k.missed <= Tracked.KEEP then
        kept[#kept + 1] = k
      else
        changed = true
      end
    end
  end
  for _, f in ipairs(found) do
    if not f.used then
      counter = counter + 1
      kept[#kept + 1] = {
        ref = "tracked:" .. counter,
        name = f.name,
        kind = f.kind,
        continent = continent,
        wx = f.wx,
        wy = f.wy,
        ax = f.wx,
        ay = f.wy,
        n = 1,
        missed = 0,
        reach = f.reach,
        tries = 0,
      }
      changed = true
    end
  end
  known = kept
  stats.known = #known
  if changed then
    publish(geo.px, geo.py)
  end

  local stood = lastPlace ~= nil and lastPlace[1] == continent
  if stood then
    local dx, dy = geo.px - lastPlace[2], geo.py - lastPlace[3]
    stood = dx * dx + dy * dy <= Tracked.STILL * Tracked.STILL
  end
  lastPlace = { continent, geo.px, geo.py }
  nextAt = now + ((stood and not changed and not restless) and Tracked.IDLE or Tracked.WAIT)

  local dots = {}
  for _, k in ipairs(known) do
    if k.kind ~= "creature" and not k.fine and k.missed == 0 and k.tries < Tracked.FINE_TRIES then
      dots[#dots + 1] = k
    end
  end
  if #dots > 0 then
    fine = { dots = dots, at = 1 }
  end
end

-- --- the fine pass ----------------------------------------------------------------------------

-- Whether all a dot at (u, v) can answer lies on the minimap: the rim cuts it off and would pull
-- the centre inwards. Such a dot waits for the player to come closer.
local function onMinimap(u, v, reach)
  local limit = geo.w / 2 - 2
  if ns.Mini.Shape() == "SQUARE" then
    return math.max(math.abs(u), math.abs(v)) + reach <= limit
  end
  return math.sqrt(u * u + v * v) + reach <= limit
end

-- The next dot the fine pass can look at, false when none is left.
local function nextDot()
  while fine.at <= #fine.dots do
    local k = fine.dots[fine.at]
    local u, v = ns.Minimap.Project(k.ax, k.ay, geo.px, geo.py, geo.pxPerYard, geo.facing)
    if k.continent == geo.continent and onMinimap(u, v, k.reach) then
      fine.k, fine.side = k, math.floor(2 * k.reach / Tracked.FINE) + 1
      fine.i, fine.n, fine.wx, fine.wy = 0, 0, 0, 0
      return true
    end
    fine.at = fine.at + 1
  end
  fine = nil
  return false
end

-- A dot's pass is over: the centre of all that answered is its place.
local function placeDot()
  local k, n, wx, wy = fine.k, fine.n, fine.wx, fine.wy
  fine.k, fine.at = nil, fine.at + 1
  if n == 0 then
    k.tries = k.tries + 1 -- gone since the sweep, or a secret: the next sweep tells
    return
  end
  wx, wy = wx / n, wy / n
  if B.debug then
    local moved = math.sqrt((wx - k.wx) ^ 2 + (wy - k.wy) ^ 2)
    B:Log(mod, "debug", "minimap dot %s: %d points, %.1f yards from the grid's place", k.name, n, moved)
  end
  k.ax, k.ay, k.wx, k.wy, k.fine = wx, wy, wx, wy, true
  Tracked.stats.fine = Tracked.stats.fine + 1
  publish(geo.px, geo.py)
end

-- One frame's share of the fine pass: a grid of FINE pixels around the dot's place in this frame
-- (the player moves on), every point that answers its name in world yards.
local function fineBatch()
  if not (fine.k or nextDot()) then
    return
  end
  local k, side, step = fine.k, fine.side, Tracked.FINE
  local u, v = ns.Minimap.Project(k.ax, k.ay, geo.px, geo.py, geo.pxPerYard, geo.facing)
  local corner = (side - 1) * step / 2
  local last = math.min(fine.i + Tracked.PER_FRAME, side * side)
  cursor()
  for i = fine.i, last - 1 do
    local pu, pv = u - corner + (i % side) * step, v - corner + math.floor(i / side) * step
    local n = listen(pu, pv)
    for j = 1, n do
      if heard[j] == k.name then
        local wx, wy = Tracked.ToWorld(pu, pv, geo.pxPerYard, geo.facing, geo.px, geo.py)
        fine.n, fine.wx, fine.wy = fine.n + 1, fine.wx + wx, fine.wy + wy
        break
      end
    end
  end
  Tracked.stats.probes = Tracked.stats.probes + last - fine.i
  fine.i = last
  if last >= side * side then
    placeDot()
  end
end

-- A failed sweep: tried again later, and after STRIKES in a row no more this session.
local function fail(now, err)
  sweep, fine = nil, nil
  strikes = strikes + 1
  Tracked.stats.errors = Tracked.stats.errors + 1
  B:Log(mod, "warn", "minimap sweep failed: %s", tostring(err))
  if strikes >= Tracked.STRIKES then
    broken = true
    Tracked.Stop()
  else
    nextAt = now + Tracked.RETRY
  end
end

-- Everything of a frame that asks the client, under the one pcall of onUpdate (calls the client
-- only lists, forever-api.md): "wait" when no sweep can run now, "nowhere" in an instance, else
-- the frame's share was asked.
local function ask()
  if paused() or not geometry() or not geo.turned then
    return "wait"
  end
  if not geo.continent then
    return "nowhere"
  end
  if fine then
    fineBatch()
    return "asked"
  end
  if sweep and (sweep.w ~= geo.w or sweep.continent ~= geo.continent) then
    sweep = nil -- the minimap was sized or the continent left under the sweep: once more
  end
  if not sweep then
    sweep = {
      points = gridPoints(geo.w / 2, ns.Mini.Shape()),
      i = 1,
      hits = {},
      answered = 0,
      w = geo.w,
      continent = geo.continent,
    }
  end
  batch()
  return "asked"
end

local function onUpdate()
  local now = GetTime()
  if not sweep and not fine and now < nextAt then
    return
  end
  if not Tracked.Active() then
    Tracked.Stop()
    return
  end
  local ok, what = pcall(ask)
  if cursorOn then
    cursorOn = false
    pcall(Minimap.SetUsingSoftCursor, Minimap, false) -- never left on between two frames
  end
  if not ok then
    fail(now, what)
  elseif what == "wait" then
    sweep, fine = nil, nil -- a sweep cut short tells nothing; the known dots stay
    nextAt = now + Tracked.WAIT
  elseif what == "nowhere" then
    sweep, fine = nil, nil
    forget() -- an instance: no place for a dot
    nextAt = now + Tracked.IDLE
  elseif sweep and sweep.i > #sweep.points then
    finish(now)
  end
end

-- Starts or stops the sweeps as the style and the setting want (Mini.Render calls this).
function Tracked.Sync()
  if Tracked.Active() and Tracked.Available() then
    if not driver then
      driver = CreateFrame("Frame")
    end
    if not Tracked.Running() then
      nextAt = 0
      driver:SetScript("OnUpdate", onUpdate)
    end
  else
    Tracked.Stop()
  end
end

-- No more sweeps; the pins of the dots go (the game's own minimap shows them again).
function Tracked.Stop()
  if driver then
    driver:SetScript("OnUpdate", nil)
  end
  sweep, fine = nil, nil
  lastPlace = nil
  forget()
end

-- The player set off: the next sweep comes at the moving pace (Mini's frame hears the event).
function Tracked.Wake()
  if Tracked.Running() then
    nextAt = math.min(nextAt, GetTime() + Tracked.WAIT)
  end
end

-- The settings' note under the switch.
function Tracked.Note()
  local ok, why = Tracked.Available()
  if ok then
    return nil
  end
  return why
end

function Tracked.Known()
  return known
end

-- New data (the packs loaded): the names are looked up again.
function Tracked.Reset()
  byName = nil
  creatures = {}
end

ns.Tracked = Tracked
ns.mod.Tracked = Tracked

table.insert(Map.onEnable, function(self)
  mod = self
end)
table.insert(Map.onSetting, function(key)
  if key == "miniTracked" then
    Tracked.Sync()
  end
end)
