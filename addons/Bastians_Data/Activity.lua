-- Bastian's Data: the activity facet of quests (ADR 0026, world-graph.md §10, data.md "Activities"):
-- the quest record seen as something a character spends time on, without a second quest record;
-- and the value per hour with the way there (R26.11, route.md "Explore").
local _, ns = ...
local B = Bastians
local Data = ns.Data

local Activity = {}
Data.Activity = Activity

local ipairs, max = ipairs, math.max

Activity.MIN_SECONDS = 30 -- the shortest time an activity with a fixed time counts

local function questRefs(ids)
  local out = {}
  for _, id in ipairs(ids or {}) do
    out[#out + 1] = "quest:" .. id
  end
  return #out > 0 and out or nil
end

-- The activity of a quest record: { kind, places, needs, takes, gives, window, src }. `takes` stays
-- nil (no source times quests yet); amounts the record lacks are left out, never 0.
function Activity.OfQuest(ref, r)
  if not r then
    return nil
  end
  local gives = {}
  local rw = r.rewards or {}
  if rw.money and rw.money > 0 then
    gives[#gives + 1] = { kind = "copper", amount = rw.money }
  end
  if rw.xp and rw.xp > 0 then
    gives[#gives + 1] = { kind = "xp", amount = rw.xp }
  end
  for _, it in ipairs(rw.items or {}) do
    gives[#gives + 1] = { kind = "item", id = it[1], amount = it[2] or 1 }
  end
  for _, it in ipairs(rw.choices or {}) do
    gives[#gives + 1] = { kind = "item", id = it[1], amount = it[2] or 1, choice = true }
  end
  for _, rep in ipairs(rw.rep or {}) do
    gives[#gives + 1] = { kind = "rep", id = rep[1], amount = rep[2] }
  end
  if rw.spell then
    gives[#gives + 1] = { kind = "unlock", id = rw.spell }
  end
  local needs = {
    level = r.minLevel,
    races = r.races,
    classes = r.classes,
    quests = questRefs(r.pre),
    anyQuest = questRefs(r.preAny),
    skill = r.skill,
    reputation = r.minRep,
  }
  local places = {}
  for _, p in ipairs(B:Entity(ref):AllPlaces()) do
    places[#places + 1] = p
  end
  return {
    kind = "quest",
    places = places,
    needs = needs,
    takes = nil,
    gives = gives,
    window = r.holiday and { event = r.holiday } or nil,
    src = r.src,
  }
end

-- What an activity gives: { copper, xp } per run and { copper, xp } per hour (each nil when it
-- gives none of it), and how many items had no worth. worthOf(itemID) -> copper or nil. A choice
-- of reward items counts its best one; an item without a worth is counted, never 0.
function Activity.Value(act, worthOf)
  local run, hour, unpriced = {}, {}, act and act.unpriced or 0
  local best, choiceUnknown
  local function add(into, key, amount)
    into[key] = (into[key] or 0) + amount
  end
  for _, g in ipairs(act and act.gives or {}) do
    local into = g.per == "hour" and hour or run
    if g.kind == "copper" and g.amount then
      add(into, "copper", g.amount)
    elseif g.kind == "xp" and g.amount then
      add(into, "xp", g.amount)
    elseif g.kind == "item" and g.id then
      local each = worthOf and worthOf(g.id) or nil
      if g.choice then
        if each then
          best = max(best or 0, each * (g.amount or 1))
        else
          choiceUnknown = true
        end
      elseif each then
        add(into, "copper", each * (g.amount or 1))
      else
        unpriced = unpriced + 1
      end
    end
  end
  if best then
    add(run, "copper", best)
  elseif choiceUnknown then
    unpriced = unpriced + 1
  end
  return run, hour, unpriced
end

-- Gold (copper) and XP per hour with the way there (seconds), each nil when unknown. A fixed-time
-- activity (`takes` seconds): value x 3600 / (takes + way); an hourly one, worked for `stay`
-- seconds: rate x stay / (stay + way). A per-run gain without `takes` has no rate.
function Activity.Rate(act, way, stay, worthOf)
  local run, hour, unpriced = Activity.Value(act, worthOf)
  way = way or 0
  local rate = {}
  local function put(key, perHour)
    if perHour then
      rate[key] = (rate[key] or 0) + perHour
    end
  end
  if act.takes then
    local seconds = max(act.takes + way, Activity.MIN_SECONDS)
    put("copper", run.copper and run.copper * 3600 / seconds)
    put("xp", run.xp and run.xp * 3600 / seconds)
  end
  if stay and stay > 0 then
    local share = stay / (stay + way)
    put("copper", hour.copper and hour.copper * share)
    put("xp", hour.xp and hour.xp * share)
  end
  return rate.copper, rate.xp, unpriced
end

function Activity.Attach(module)
  B:RegisterFacet(module, {
    facet = "activity",
    types = { "quest" },
    priority = 100,
    invalidateOn = { "BASTIANS_DATA_LOADED" },
    rule = function(ref)
      local _, id = B.Entity.Parse(ref)
      local data = B:GetService("data")
      return Activity.OfQuest(ref, data and data:Get("quest", id))
    end,
  })
end
