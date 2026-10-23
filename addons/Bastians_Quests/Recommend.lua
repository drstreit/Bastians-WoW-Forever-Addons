-- Recommendations "here" and the next-area planner (quests.md "Recommendation scoring v1"). Pure:
-- every input comes through `ctx` (distances, travel, prices, weights, the quest log), so the scoring
-- runs in tests on the fixture world. Unknown inputs never invent value: they lower the confidence
-- and the reason says what was unknown.
local _, ns = ...
local B = Bastians
local L = ns.L
local Logic = ns.Logic

local Rec = {}
ns.Recommend = Rec

Rec.RUN_SPEED = 7 -- yards per second on foot
Rec.UNKNOWN_LEG_MINUTES = 3 -- a leg whose distance is unknown counts this much
Rec.UNLOCK_DEPTH = 3
Rec.DEFAULT_WEIGHTS = { gold = 2, unlock = 0.5, next = 300 } -- XP per silver; share of a follower's XP; XP
Rec.DEFAULT_TIMES = { slay = 0.75, loot = 1, object = 0.5, event = 2, delivery = 1 } -- minutes per unit
Rec.DEFAULT_COUNTS = { slay = 8, loot = 6, object = 4, event = 1 } -- when the data has no counts

-- ---------------------------------------------------------------------------------------------
-- Value
-- ---------------------------------------------------------------------------------------------

-- Full quest experience for a quest of this level (assumed curve, close to the Classic quest XP
-- table at levels 1-60; the exact per-quest value is not in the data).
function Rec.baseXP(questLevel)
  local l = questLevel or 1
  return 20 + l * 30 + l * l * 1.5
end

-- Share of the full XP by level difference: full down to 5 levels below, then 20 % less per level,
-- a tenth from 10 levels below (the Classic rule, assumed; verify in game).
function Rec.xpFactor(playerLevel, questLevel)
  if not (playerLevel and questLevel) then
    return 1
  end
  local d = playerLevel - questLevel
  if d <= 5 then
    return 1
  elseif d >= 10 then
    return 0.1
  end
  return 1 - (d - 5) * 0.2
end

function Rec.xp(questLevel, playerLevel)
  return Rec.baseXP(questLevel) * Rec.xpFactor(playerLevel, questLevel)
end

-- Reward money plus the best priced item (one choice is taken, other items are all given).
-- price(itemID) -> copper or nil. Returns copper, unknown (true when an item had no price).
function Rec.rewardValue(q, price)
  local rw = q and q.rewards
  if not rw then
    return 0, false
  end
  local total, unknown = rw.money or 0, false
  for _, it in ipairs(rw.items or {}) do
    local p = price and price(it[1]) or nil
    if p then
      total = total + p * (it[2] or 1)
    else
      unknown = true
    end
  end
  local best
  for _, it in ipairs(rw.choices or {}) do
    local p = price and price(it[1]) or nil
    if p then
      best = math.max(best or 0, p * (it[2] or 1))
    else
      unknown = true
    end
  end
  return total + (best or 0), unknown
end

-- Quests this one unlocks within UNLOCK_DEPTH, that the character can still take: count and the
-- XP they are worth (halved per depth).
function Rec.unlocks(qid, state)
  local n, value = 0, 0
  local seen = { [qid] = true }
  local function walk(id, depth)
    if depth > Rec.UNLOCK_DEPTH then
      return
    end
    for _, f in ipairs(Logic.next(id)) do
      if not seen[f] then
        seen[f] = true
        local fq = Logic.quest(f)
        local st = fq and Logic.status(f, state)
        if fq and st ~= "done" and st ~= "never" and st ~= "superseded" then
          n = n + 1
          value = value + Rec.xp(fq.level, state.level) * 0.5 ^ (depth - 1)
          walk(f, depth + 1)
        end
      end
    end
  end
  walk(qid, 1)
  return n, value
end

-- ---------------------------------------------------------------------------------------------
-- Time
-- ---------------------------------------------------------------------------------------------

local function place(list)
  local p = list and list[1]
  if p and p[1] then
    return p[1], p[2], p[3]
  end
  return nil
end

-- Nearest spot of the quest on `map` to a point (map fractions); nil without spots there.
local function nearestSpot(q, map, x, y)
  local list = q and q.spots and map and q.spots[map]
  if not list then
    return nil
  end
  local best, bd
  for _, s in ipairs(list) do
    local d = (x and s[1]) and ((x - s[1]) ^ 2 + (y - s[2]) ^ 2) or 0
    if not bd or d < bd then
      best, bd = s, d
    end
  end
  return map, best[1], best[2]
end

-- Minutes for one leg: the travel service, else a straight line at run speed, else the default.
local function legMinutes(ctx, m1, x1, y1, m2, x2, y2)
  if not (m1 and x1 and m2 and x2) then
    return Rec.UNKNOWN_LEG_MINUTES, true
  end
  if ctx.travel then
    local seconds = ctx.travel(m1, x1, y1, m2, x2, y2)
    if seconds then
      return seconds / 60, false
    end
  end
  local yards = ctx.distance and ctx.distance(m1, x1, y1, m2, x2, y2) or nil
  if yards then
    return yards / Rec.RUN_SPEED / 60, false
  end
  return Rec.UNKNOWN_LEG_MINUTES, true
end

-- Minutes of objective work from the live log entry (remaining counts) or the data's objectives.
function Rec.objectiveMinutes(q, entry, times, levelMod)
  local total = 0
  if entry and #(entry.objectives or {}) > 0 then
    for _, o in ipairs(entry.objectives) do
      if not o.finished then
        local kind = (o.kind == "monster" or o.kind == "slay") and "slay"
          or (o.kind == "item" and "loot")
          or (o.kind == "object" and "object")
          or "event"
        local left = (o.required or 1) - (o.fulfilled or 0)
        total = total + (times[kind] or 1) * math.max(1, left)
      end
    end
  elseif q and q.objectives and #q.objectives > 0 then
    for _, o in ipairs(q.objectives) do
      local kind = o[1] == "slay" and "slay"
        or o[1] == "loot" and "loot"
        or o[1] == "object" and "object"
        or "event"
      total = total + (times[kind] or 1) * (Rec.DEFAULT_COUNTS[kind] or 1)
    end
  else
    total = times.delivery or 1
  end
  return total * (levelMod or 1)
end

-- Travel and work in minutes for a quest from the player's place. Returns minutes, unknownLegs.
function Rec.minutes(q, entry, map, ctx, times, levelMod)
  local unknown = 0
  local minutes = 0
  local cm, cx, cy = map, ctx.px, ctx.py
  local function leg(m, x, y)
    local mins, unk = legMinutes(ctx, cm, cx, cy, m, x, y)
    minutes = minutes + mins
    if unk then
      unknown = unknown + 1
    end
    if m and x then
      cm, cx, cy = m, x, y
    end
  end
  local complete = entry and entry.isComplete
  if not entry then
    leg(place(q and q.startPlaces))
  end
  if not complete then
    local sm, sx, sy = nearestSpot(q, cm, cx, cy)
    if not sm then
      sm, sx, sy = nearestSpot(q, map, ctx.px, ctx.py)
    end
    if sm then
      leg(sm, sx, sy)
    end
    minutes = minutes + Rec.objectiveMinutes(q, entry, times, levelMod)
  end
  leg(place(q and q.endPlaces))
  return minutes, unknown
end

-- ---------------------------------------------------------------------------------------------
-- Ranking
-- ---------------------------------------------------------------------------------------------

local function isHard(questLevel, playerLevel)
  return questLevel ~= nil and playerLevel ~= nil and questLevel - playerLevel >= 3
end

local function money(copper)
  return B.UI.MoneyShort and B.UI.MoneyShort(copper) or tostring(copper)
end

-- One quest: value, minutes, score, reason and confidence. `entry` is the log entry when in the log.
function Rec.score(qid, entry, map, state, ctx)
  local q = Logic.quest(qid)
  if not q then
    return nil
  end
  local weights = ctx.weights or Rec.DEFAULT_WEIGHTS
  local times = ctx.objectiveTime or Rec.DEFAULT_TIMES
  local parts, flags = {}, {}
  local xp = Rec.xp(q.level, state.level)
  parts[#parts + 1] = string.format("%d %s", math.floor(xp + 0.5), L["xp"])
  local value = xp
  local reward, priceUnknown = Rec.rewardValue(q, ctx.price)
  if reward > 0 then
    value = value + (weights.gold or 0) * reward / 100
    parts[#parts + 1] = money(reward) .. " " .. L["reward"]
  end
  if priceUnknown then
    flags[#flags + 1] = L["item price unknown"]
  end
  local n, unlockValue = Rec.unlocks(qid, state)
  if n > 0 then
    value = value + (weights.unlock or 0) * unlockValue
    parts[#parts + 1] = string.format("+%d %s", n, n == 1 and L["unlock"] or L["unlocks"])
  end
  local leadsNext = false
  if ctx.nextZones then
    for _, m in ipairs(Logic.leadsTo(qid, map)) do
      if ctx.nextZones[m] then
        leadsNext = true
      end
    end
  end
  if leadsNext then
    value = value + (weights.next or 0)
    parts[#parts + 1] = L["leads to the next area"]
  end
  local hard = isHard(q.level, state.level)
  local minutes, unknownLegs = Rec.minutes(q, entry, map, ctx, times, hard and 1.5 or 1)
  parts[#parts + 1] = string.format("%d %s", math.max(1, math.floor(minutes + 0.5)), L["min"])
  if unknownLegs > 0 then
    flags[#flags + 1] = L["distance unknown"]
  end
  local score = value / math.max(minutes, 0.5)
  if Logic.isGroup(q) and not ctx.grouped then
    score = 0
    flags[#flags + 1] = L["group quest"]
  end
  if hard then
    score = score * 0.5
    flags[#flags + 1] = L["hard"]
  end
  local reason = table.concat(parts, ", ")
  if #flags > 0 then
    reason = reason .. " (" .. table.concat(flags, ", ") .. ")"
  end
  local confidence = math.max(0.2, 1 - 0.3 * ((priceUnknown and 1 or 0) + unknownLegs))
  return {
    qid = qid,
    inLog = entry ~= nil,
    value = value,
    minutes = minutes,
    score = score,
    reason = reason,
    confidence = confidence,
    unlocks = n,
    leadsNext = leadsNext,
  }
end

-- Candidates on `map`: quests to take here and log quests with work or a hand-in here.
function Rec.candidates(map, state, ctx)
  local list, seen = {}, {}
  local function add(qid, entry)
    if not seen[qid] then
      seen[qid] = true
      list[#list + 1] = { qid = qid, entry = entry }
    end
  end
  for qid, entry in pairs(ctx.log or {}) do
    local q = Logic.quest(qid)
    if q then
      local here = (q.spots and q.spots[map] ~= nil and not entry.isComplete) or Logic.turnInMap(q) == map
      if here then
        add(qid, entry)
      end
    end
  end
  local view = Logic.zoneView(map, state, ctx.px, ctx.py)
  for _, g in ipairs(view.available) do
    for _, qid in ipairs(g.quests) do
      add(qid, nil)
    end
  end
  return list
end

-- The ranked list for `map`, best first. ctx: { px, py, log, grouped, weights, objectiveTime,
-- distance(m1,x1,y1,m2,x2,y2) -> yards | nil, travel(...) -> seconds | nil, price(itemID) -> copper | nil,
-- nextZones = { [map] = true } }
function Rec.rank(map, state, ctx)
  ctx = ctx or {}
  local out = {}
  for _, c in ipairs(Rec.candidates(map, state, ctx)) do
    local rec = Rec.score(c.qid, c.entry, map, state, ctx)
    if rec then
      out[#out + 1] = rec
    end
  end
  table.sort(out, function(a, b)
    if a.score ~= b.score then
      return a.score > b.score
    end
    return a.qid < b.qid
  end)
  return out
end

-- ---------------------------------------------------------------------------------------------
-- Next-area planner: zones whose level band meets level+1..level+3, and what leads there from here
-- ---------------------------------------------------------------------------------------------

function Rec.nextAreas(map, state, faction)
  local lo, hi = state.level + 1, state.level + 3
  local out = {}
  for _, z in ipairs(Logic.zones(faction)) do
    if z.map ~= map and z.lo and z.hi and z.lo <= hi and z.hi >= lo then
      out[#out + 1] = { map = z.map, name = z.name, lo = z.lo, hi = z.hi, med = z.med, leads = {} }
    end
  end
  table.sort(out, function(a, b)
    if (a.med or 99) ~= (b.med or 99) then
      return (a.med or 99) < (b.med or 99)
    end
    return a.map < b.map
  end)
  if #out == 0 then
    return out
  end
  local byMap = {}
  for _, z in ipairs(out) do
    byMap[z.map] = z
  end
  for _, qid in ipairs(Logic.questsOfZone(map)) do
    local st = Logic.status(qid, state)
    if st ~= "done" and st ~= "never" and st ~= "superseded" then
      for _, m in ipairs(Logic.leadsTo(qid, map)) do
        local z = byMap[m]
        if z then
          z.leads[#z.leads + 1] = qid
        end
      end
    end
  end
  return out
end

function Rec.nextZoneSet(areas)
  local set = {}
  for _, z in ipairs(areas) do
    set[z.map] = true
  end
  return set
end
