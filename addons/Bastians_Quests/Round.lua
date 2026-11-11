-- Bastian's Quests: the quest round (R26.4, route.md "Several stops"): the open steps and the
-- hand-ins of the log's quests as the stops of one route, planned by the `route` service (Route).
local _, ns = ...
local B = Bastians
local L = ns.L
local State = ns.State

local Round = {}
ns.Round = Round

Round.MAX = 12 -- stops of a round at most (graph:Tour's own limit), the nearest kept
Round.SHARE_YARDS = 100 -- steps whose nearest places lie this close share a stop (ADR 0069)

-- The world place of a map point (fractions), or nil.
local function world(map, x, y)
  local c, wx, wy = B.Coords.ToWorld(map, x, y)
  return c and { map = c, wx = wx, wy = wy } or nil
end

-- The world places of a step's map places; one no transform holds is left out.
local function worldPlaces(places)
  local out = {}
  for _, p in ipairs(places or {}) do
    out[#out + 1] = world(p.map, p.x, p.y)
  end
  return out
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

-- The stops of one quest from its `steps` facet:
-- one per open thing to do at its place nearest to the character, steps whose nearest places lie
-- within SHARE_YARDS sharing one; without a placed step the client's place for the quest; then
-- the hand-in, after them. Complete: the hand-in alone. Returns the stops (nil when the quest has
-- no place to go to: it is left out). `at` = the character's continent and world position. Pure
-- over the facet and Coords.
function Round.QuestStops(id, name, steps, at)
  local pc, px, py = at.continent, at.wx, at.wy
  local stops, doing = {}, {}
  local handin = steps[#steps]
  if steps.state ~= "complete" then
    for i = 2, #steps - 1 do
      local step = steps[i]
      local p, dist = nearest(worldPlaces(step.open and step.places or nil), pc, px, py)
      local shared
      for _, st in ipairs(p and doing or {}) do
        local near = st.place.map == p.map
          and (st.place.wx - p.wx) ^ 2 + (st.place.wy - p.wy) ^ 2 <= Round.SHARE_YARDS ^ 2
        shared = shared or near
      end
      if p and not shared then
        doing[#doing + 1] = {
          id = id .. ":" .. i,
          name = step.text and (name .. ": " .. step.text) or name,
          ref = "quest:" .. id,
          place = p,
          dist = dist,
        }
      end
    end
    local w = #doing == 0 and steps.waypoint
    local p, dist = nearest(worldPlaces(w and { w } or nil), pc, px, py)
    if p then
      doing[1] = { id = id .. ":do", name = name, ref = "quest:" .. id, place = p, dist = dist }
    end
    if #doing == 0 and not (handin and handin.open) then
      return nil -- things to do, and nobody knows where
    end
  end
  local after = {}
  for _, st in ipairs(doing) do
    stops[#stops + 1] = st
    after[#after + 1] = st.id
  end
  local p, dist = nearest(worldPlaces(handin and handin.places), pc, px, py)
  if p then
    stops[#stops + 1] = {
      id = id .. ":in",
      name = string.format(L["%s (hand in)"], name),
      ref = handin.ref or ("quest:" .. id),
      place = p,
      dist = dist,
      after = #after > 0 and after or nil,
    }
  elseif #doing == 0 then
    return nil -- complete or a delivery, and no place for the hand-in
  end
  return stops
end

-- The stops of the log: { { id, name, ref, place, after } } and the number of quests left out
-- (no place known). More than MAX: the nearest by straight line, a hand-in only with all of its
-- quest's stops.
function Round.Stops()
  local pc, px, py = B.Coords.Player()
  local at = { continent = pc, wx = px, wy = py }
  local stops, left = {}, 0
  for _, id in ipairs(State.order or {}) do
    local e = State.log[id]
    if e then -- the log holds quests only (`header` names the zone heading a quest stands under)
      local steps = B:Entity("quest:" .. id):Facet("steps")
      local name = e.title or B:Entity("quest:" .. id):Name() or tostring(id)
      local own = steps and Round.QuestStops(id, name, steps, at)
      if own then
        for _, st in ipairs(own) do
          stops[#stops + 1] = st
        end
      else
        left = left + 1
      end
    end
  end
  table.sort(stops, function(a, b)
    if a.dist ~= b.dist then
      return a.dist < b.dist
    end
    return a.id < b.id
  end)
  -- nearest first; a hand-in nearer than its quest's stops waits for the last of them, and is
  -- left out when the limit cut one of them
  local kept, taken, waiting = {}, {}, {}
  local function ready(st)
    for _, need in ipairs(st.after or {}) do
      if not taken[need] then
        return false
      end
    end
    return true
  end
  for _, st in ipairs(stops) do
    if #kept >= Round.MAX then
      break
    elseif not ready(st) then
      waiting[#waiting + 1] = st
    else
      kept[#kept + 1], taken[st.id] = st, true
      for i = #waiting, 1, -1 do
        local w = waiting[i]
        if #kept < Round.MAX and ready(w) then
          kept[#kept + 1], taken[w.id] = w, true
          table.remove(waiting, i)
        end
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
