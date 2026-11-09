-- Bastian's Quests: the quest round (R26.4, route.md "Several stops"): the open quests and the
-- hand-ins of the log as the stops of one route, planned by the `route` service (Route).
local _, ns = ...
local B = Bastians
local L = ns.L
local State = ns.State

local Round = {}
ns.Round = Round

Round.MAX = 12 -- stops of a round at most (graph:Tour's own limit), the nearest kept

local function data()
  return B:GetService("data")
end

-- The world place of a map point (fractions), or nil.
local function world(map, x, y)
  local c, wx, wy = B.Coords.ToWorld(map, x, y)
  return c and { map = c, wx = wx, wy = wy } or nil
end

-- The place nearest to the character on its continent (squared yards), else the first one.
local function nearest(places, pc, px, py)
  local best, bd
  for _, p in ipairs(places) do
    local d = (pc and p.map == pc and px) and ((p.wx - px) ^ 2 + (p.wy - py) ^ 2) or math.huge
    if not bd or d < bd then
      best, bd = p, d
    end
  end
  return best, bd
end

-- Where a quest is done: its objective spots; without them (retail has none in the pack) the
-- client's next step on the character's map.
local function doPlaces(id, q, map)
  local out = {}
  for spotMap, list in pairs(ns.Logic.OpenSpots(State.log[id], q)) do
    for _, s in ipairs(list) do
      out[#out + 1] = world(spotMap, s[1], s[2])
    end
  end
  if #out == 0 and map then
    local x, y = B.Compat.GetQuestWaypoint(id, map)
    out[#out + 1] = x and world(map, x, y) or nil
  end
  return out
end

-- Where a quest is handed in: its taker's places, else the turn-in places.
local function handInPlaces(q)
  local out = {}
  local ref = q and q.ends and q.ends[1]
  for _, p in ipairs(ref and B:Entity(ref):Places() or {}) do
    if p.wx then
      out[#out + 1] = { map = p.map, wx = p.wx, wy = p.wy, wz = p.wz }
    end
  end
  if #out == 0 then
    for _, p in ipairs(q and q.endPlaces or {}) do
      out[#out + 1] = world(p[1], p[2], p[3])
    end
  end
  return out, ref
end

-- The stops of the log: { { id, name, ref, place, after } } and the number of quests left out
-- (no place known). A quest still to do gives a stop where it is done and its hand-in after it;
-- a complete one its hand-in. More than MAX: the nearest by straight line, a hand-in only with
-- its quest's stop.
function Round.Stops()
  local d = data()
  local pc, px, py = B.Coords.Player()
  local map = B.Coords.PlayerMap()
  local stops, left = {}, 0
  for _, id in ipairs(State.order or {}) do
    local e = State.log[id]
    if e then -- the log holds quests only (`header` names the zone heading a quest stands under)
      local q = d and d:Get("quest", id)
      local name = e.title or (q and q.name) or tostring(id)
      local ready = e.isComplete or e.readyForTurnIn
      local doing
      if not ready then
        local p, dist = nearest(doPlaces(id, q, map), pc, px, py)
        doing = p and { id = id .. ":do", name = name, ref = "quest:" .. id, place = p, dist = dist }
      end
      local places, taker = handInPlaces(q)
      local p, dist = nearest(places, pc, px, py)
      local handIn = p
        and {
          id = id .. ":in",
          name = string.format(L["%s (hand in)"], name),
          ref = taker or ("quest:" .. id),
          place = p,
          dist = dist,
          after = doing and { doing.id } or nil,
        }
      if (not ready and not doing) or (ready and not handIn) then
        left = left + 1
      else
        stops[#stops + 1] = doing
        stops[#stops + 1] = handIn
      end
    end
  end
  table.sort(stops, function(a, b)
    if a.dist ~= b.dist then
      return a.dist < b.dist
    end
    return a.id < b.id
  end)
  -- nearest first; a hand-in nearer than its quest's stop waits for that stop
  local kept, taken, waiting = {}, {}, {}
  for _, st in ipairs(stops) do
    local needs = st.after and st.after[1]
    if #kept >= Round.MAX then
      break
    elseif needs and not taken[needs] then
      waiting[needs] = st
    else
      kept[#kept + 1], taken[st.id] = st, true
      local w = waiting[st.id]
      if w and #kept < Round.MAX then
        kept[#kept + 1], taken[w.id], waiting[st.id] = w, true, nil
      end
    end
  end
  return kept, left
end

-- /bq round and the button of My quests: hands the stops to the route service.
function Round.Start()
  local route = B:GetService("route")
  if not route then
    B:Say(L["The quest round needs Bastian's Route."])
    return false
  end
  local stops, left = Round.Stops()
  if #stops == 0 then
    B:Say(L["No quest of the log has a place to go to."])
    return false
  end
  if left > 0 then
    B:Say(L["%d quests without a known place are left out of the round."], left)
  end
  return route:Tour(stops, L["Quest round"])
end
