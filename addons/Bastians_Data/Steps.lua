-- Bastian's Data: a quest's steps without a state (ADR 0069, ADR 0070; data.md "Links and steps"):
-- the giver, each thing to do with its own places, the hand-in. Bastian's Quests adds the log's state.
local _, ns = ...
local B = Bastians
local Data = ns.Data

local Steps = {}
Data.Steps = Steps

local ipairs, pairs, type, floor, sort = ipairs, pairs, type, math.floor, table.sort

Steps.DROPPERS = 12 -- creatures an item is looked for on, the likeliest first: spider meat has 76
Steps.ENDS = 8 -- places of one giver or taker at most

-- An objective's kind in a pack without `steps`, and the step it is.
local STEP_OF = { slay = "slay", object = "use", loot = "get" }

-- Whether a spot { x, y, kind, mask } serves the objective of that number; no mask: not known.
local function spotServes(spot, number)
  return type(spot[4]) == "number" and floor(spot[4] / 2 ^ (number - 1)) % 2 == 1
end

-- The keys of a table by map in ascending order: the same steps from the same record, every time.
local function sortedMaps(byMap)
  local maps = {}
  for map in pairs(byMap or {}) do
    maps[#maps + 1] = map
  end
  sort(maps)
  return maps
end

-- An item's droppers by its own loot record, the likeliest first.
local function droppersOf(itemID, read)
  local rec = read.item(itemID)
  local refs = {}
  for i, drop in ipairs(rec and rec.drops or {}) do
    if i > Steps.DROPPERS then
      break
    end
    refs[#refs + 1] = drop[1]
  end
  return refs
end

-- The spots of a kind with the bit of that number into `places`; true when there was one. A
-- spot's fifth field names who stands there (an item's spots are its droppers' places, QD1).
local function ownSpots(r, maps, kind, number, claimed, places)
  for _, map in ipairs(maps) do
    for _, s in ipairs(r.spots[map]) do
      if s[3] == kind and spotServes(s, number) then
        claimed[s] = true
        places[#places + 1] = { map = map, x = s[1], y = s[2], ref = s[5] }
      end
    end
  end
  return #places > 0
end

-- Where the things themselves are, into `places`; a place names its thing when it is not `own`.
local function spawnPlaces(refs, own, read, places)
  for _, from in ipairs(refs) do
    for _, s in ipairs(type(from) == "string" and read.spawns(from) or {}) do
      if s.map and s.x and s.y then
        places[#places + 1] = {
          map = s.map,
          x = s.x,
          y = s.y,
          wz = s.wz,
          r = s.r,
          src = s.src,
          ref = from ~= own and from or nil,
        }
      end
    end
  end
end

-- One step with its places: the quest's own spots of the kind with the number's bit, without
-- any where the things in `from` are.
local function placed(step, r, maps, kind, number, claimed, from, read)
  if number and ownSpots(r, maps, kind, number, claimed, step.places) then
    step.src = "data"
  else
    spawnPlaces(from, step.ref, read, step.places)
  end
  return step
end

-- Who has an item, said on its step (data.md "Links and steps"): `via` the refs in order, `how`
-- by the first of them (a creature drops it, an object is opened).
local function sourced(step, from)
  local first = from[1]
  if type(first) == "string" then
    step.via = from
    step.how = first:find("^object:") and "open" or "loot"
  end
  return step
end

-- Rows with a number (Everything Quests): a row is one creature or object that counts for the
-- objective of that number within its kind, zero-based; several rows may share one objective
-- (two kinds of kobold, twelve wolves that drop the flank). So the things to do are the groups,
-- and the items are the quest's required items in their order: the n-th is the n-th item
-- objective, and the loot group of that number names who has it when the item's own loot record
-- names nobody. The pipeline's item rows (the n-th loot row's target replaced by the n-th item)
-- pair by row and are not read. `nth` is the step's number among the client's objectives of its
-- kind.
local function fromNumberedRows(r, read, out, maps, claimed)
  local groups, order = {}, {}
  for _, o in ipairs(r.objectives) do
    if type(o) == "table" and o[1] and type(o[3]) == "number" then
      local key = o[1] .. ":" .. o[3]
      local g = groups[key]
      if not g then
        g = { kind = o[1], nth = o[3] + 1, refs = {} }
        groups[key] = g
        order[#order + 1] = g
      end
      if type(o[2]) == "string" and not o[2]:find("^item:") then
        g.refs[#g.refs + 1] = o[2]
      end
    end
  end
  for _, g in ipairs(order) do
    if g.kind ~= "loot" then
      local step = {
        step = STEP_OF[g.kind] or g.kind,
        nth = g.nth,
        ref = g.refs[1],
        refs = #g.refs > 1 and g.refs or nil,
        places = {},
      }
      out[#out + 1] = placed(step, r, maps, g.kind, g.nth, claimed, g.refs, read)
    end
  end
  local items = type(r.requiredItems) == "table" and r.requiredItems or {}
  for i, it in ipairs(items) do
    local g = groups["loot:" .. (i - 1)]
    local from = it[1] and droppersOf(it[1], read) or {}
    if #from == 0 and g then
      from = g.refs
    end
    local step =
      { step = "get", nth = i, ref = it[1] and ("item:" .. it[1]) or nil, count = it[2], places = {} }
    out[#out + 1] = placed(sourced(step, from), r, maps, "loot", i, claimed, from, read)
  end
  for _, g in ipairs(order) do
    if g.kind == "loot" and g.nth > #items then -- an item the pack does not name: who has it
      local step = { step = "get", nth = g.nth, refs = #g.refs > 0 and g.refs or nil, places = {} }
      out[#out + 1] = placed(sourced(step, g.refs), r, maps, "loot", g.nth, claimed, g.refs, read)
    end
  end
end

-- Rows without a number (QuestieDB's store): a row is an objective, its target the subject. An
-- item is where its droppers are (the row's fourth field names one source by position and only
-- serves an item without a loot record). A required item no row names is a step of its own.
local function fromPlainRows(r, read, out, maps, claimed)
  local nthOf, named = {}, {}
  for _, o in ipairs(r.objectives or {}) do
    if type(o) == "table" and o[1] then
      local kind = o[1]
      nthOf[kind] = (nthOf[kind] or 0) + 1
      local ref = type(o[2]) == "string" and o[2] or nil
      local itemID = ref and tonumber(ref:match("^item:(%d+)$"))
      local from = { ref }
      if itemID then
        named[itemID] = true
        from = droppersOf(itemID, read)
        if #from == 0 then
          from = { o[4] }
        end
      end
      local step = { step = STEP_OF[kind] or kind, ref = ref, places = {} }
      if itemID then
        sourced(step, from)
      end
      out[#out + 1] = placed(step, r, maps, kind, kind ~= "area" and nthOf[kind] or nil, claimed, from, read)
    end
  end
  for _, it in ipairs(type(r.requiredItems) == "table" and r.requiredItems or {}) do
    if it[1] and not named[it[1]] then
      local step = { step = "get", ref = "item:" .. it[1], count = it[2], places = {} }
      local from = droppersOf(it[1], read)
      out[#out + 1] = placed(sourced(step, from), r, maps, "loot", nil, claimed, from, read)
    end
  end
end

-- The things to do of a pack without `steps`, from `objectives`, `requiredItems` and `spots`.
--   A step's places are the quest's own spots of its kind with its bit (the bit counts within
--   the kind), without any where the thing itself is.
--   An `area` spot is the client's own quest area and its bits are the client's objective
--   numbers: a `reach` step with that `n` per number. Which thing to do that is, only the log
--   can say (Bastian's Quests joins the two).
--   A spot nothing claims is one `reach` step at the end, so nothing the pack knows is lost.
local function fromObjectives(r, read, out)
  local claimed = {}
  local maps = sortedMaps(r.spots)
  local numbered = false
  for _, o in ipairs(r.objectives or {}) do
    numbered = numbered or (type(o) == "table" and type(o[3]) == "number")
  end
  if numbered then
    fromNumberedRows(r, read, out, maps, claimed)
  else
    fromPlainRows(r, read, out, maps, claimed)
  end
  local areas, numbers = {}, {}
  for _, map in ipairs(maps) do
    for _, s in ipairs(r.spots[map]) do
      if s[3] == "area" and type(s[4]) == "number" and s[4] > 0 then
        claimed[s] = true
        local mask, n = s[4], 1
        while mask > 0 do
          if mask % 2 == 1 then
            local step = areas[n]
            if not step then
              step = { step = "reach", n = n, places = {}, src = "data" }
              areas[n] = step
              numbers[#numbers + 1] = n
            end
            step.places[#step.places + 1] = { map = map, x = s[1], y = s[2] }
          end
          mask, n = floor(mask / 2), n + 1
        end
      end
    end
  end
  sort(numbers)
  for _, n in ipairs(numbers) do
    out[#out + 1] = areas[n]
  end
  local rest = {}
  for _, map in ipairs(maps) do
    for _, s in ipairs(r.spots[map]) do
      if not claimed[s] then
        rest[#rest + 1] = { map = map, x = s[1], y = s[2] }
      end
    end
  end
  if #rest > 0 then
    out[#out + 1] = { step = "reach", places = rest, src = "data" }
  end
end

-- A place row of the pack is { x, y, ref }: where a creature or object itself stands, its own
-- record has the rest (the height, the yards it roams, the place's source). `known` keeps each
-- thing's places for one quest.
local function standing(place, from, read, known)
  if type(from) ~= "string" or from:find("^item:") then
    return place
  end
  local spawns = known[from]
  if not spawns then
    spawns = read.spawns(from) or {}
    known[from] = spawns
  end
  for _, s in ipairs(spawns) do
    if s.map == place.map and s.x == place.x and s.y == place.y then
      place.wz, place.r, place.src = s.wz, s.r, s.src
      break
    end
  end
  return place
end

-- The things to do of a pack with `steps` (data.md): rows { n, kind, ref, count, how, via,
-- places = { [uiMapID] = { { x, y, ref } } }, src, nth, more }. The build resolved them
-- (pipeline steps.py); this only unpacks. `nth` is the number within the kind, `more` the other
-- creatures that count for the step: `refs` is all of them, the subject first.
local function fromSteps(r, out, read)
  local known = {}
  for _, row in ipairs(r.steps) do
    local step = {
      step = row[2],
      n = row[1],
      ref = row[3],
      count = row[4],
      how = row[5],
      via = row[6],
      src = row[8],
      nth = row[9],
      places = {},
    }
    if type(row[10]) == "table" and #row[10] > 0 then
      step.refs = {}
      if row[3] then -- an item no source names has no subject of its own, only who has it
        step.refs[1] = row[3]
      end
      for _, ref in ipairs(row[10]) do
        step.refs[#step.refs + 1] = ref
      end
    end
    for _, map in ipairs(sortedMaps(row[7])) do
      for _, p in ipairs(row[7][map]) do
        local place = { map = map, x = p[1], y = p[2], ref = p[3] }
        step.places[#step.places + 1] = standing(place, p[3] or row[3], read, known)
      end
    end
    out[#out + 1] = step
  end
end

-- Where a quest is taken or handed in: its own places, else the places of each who gives or
-- takes it (a notice board stands in several villages), the first Steps.ENDS of each.
local function endPlaces(refs, places, read)
  local out = {}
  if places and #places > 0 then
    for _, p in ipairs(places) do
      out[#out + 1] = { map = p[1], x = p[2], y = p[3], src = p[4] }
    end
    return out
  end
  for _, ref in ipairs(refs or {}) do
    for i, p in ipairs(read.places(ref) or {}) do
      if i > Steps.ENDS then
        break
      end
      if p.map and p.x and p.y then
        out[#out + 1] = { map = p.map, x = p.x, y = p.y, src = p.src, ref = ref }
      end
    end
  end
  return out
end

-- The steps of a quest record: `take` first, each thing to do, `handin` last; every step
-- { step, ref, n, count, how, via, src, places = { { map, x, y, ref, src, wz, r } } }
-- (core-contracts §4 "Steps"). No state: Bastian's Quests knows what is open. Pure:
-- read = { spawns = fn(ref) -> { { map, x, y, src } }, item = fn(itemID) -> record or nil,
--          places = fn(ref) -> { { map, x, y, src } } }.
function Steps.Of(r, read)
  if not r then
    return nil
  end
  local out = {
    {
      step = "take",
      ref = r.starts and r.starts[1] or nil,
      places = endPlaces(r.starts, r.startPlaces, read),
    },
  }
  if type(r.steps) == "table" then
    fromSteps(r, out, read)
  else
    fromObjectives(r, read, out)
  end
  out[#out + 1] = {
    step = "handin",
    ref = r.ends and r.ends[1] or nil,
    places = endPlaces(r.ends, r.endPlaces, read),
  }
  return out
end

local READ = {
  spawns = function(ref)
    return Data.service:Spawns(ref)
  end,
  item = function(id)
    return Data.service:Get("item", id)
  end,
  places = function(ref)
    return B:Entity(ref):Locations()
  end,
}

-- data:Steps("quest:1861"): the quest's steps without a state; nil for anything else, an unknown
-- quest, or before the pack is loaded.
function Data.service:Steps(ref)
  local typ, id = B.Entity.Parse(ref or "")
  if typ ~= "quest" then
    return nil
  end
  return Steps.Of(Data.service:Get("quest", id), READ)
end

function Steps.Attach(module)
  B:RegisterFacet(module, {
    facet = "steps",
    types = { "quest" },
    priority = 100,
    invalidateOn = { "BASTIANS_DATA_LOADED" },
    rule = function(ref)
      return Data.service:Steps(ref)
    end,
  })
end
