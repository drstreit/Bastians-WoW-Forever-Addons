-- Your own farm rate (gold.md "Your own rate at a spot", catalog review A5.6, 07.11.2026): while
-- the character stands inside a farm spot's radius, its kills (Core's `kill` happening), the
-- items it loots (`loot`, valued at the median of the moment) and the money it picks up (`money`
-- deltas, the mailbox closed) are added to the spot's record of this character, with the time
-- between events as farmed time (a gap longer than GAP starts a new session). From MIN_KILLS on
-- the spot's page says "Your rate here" beside the claim's gold per hour. Nothing is polled: the
-- happenings carry the moments. The rate (Farming.Rate) is pure; unknown stays unknown.
local _, ns = ...
local B = Bastians

local Farming = {}
ns.Farming = Farming

Farming.MIN_KILLS = 20 -- the rate shows from this many kills (Blackthornes Farmer's rule, taken)
Farming.GAP = 300 -- seconds without an event: the session ends
Farming.MIN_SECONDS = 60 -- a rate from less than a minute says nothing
Farming.MESSAGE = "BASTIANS_GOLD_FARMING"

local mod
local open -- { spot, lastAt }: the running session

local function records()
  local c = mod.db.char
  c.farming = type(c.farming) == "table" and c.farming or {}
  return c.farming
end

-- The farm spot the character stands in: the first whose radius (yards) holds the position.
function Farming.SpotHere()
  local continent, px, py = B.Coords.Player()
  if not continent then
    return nil
  end
  for _, s in ipairs(ns.Spots.All()) do
    if s.map and s.x and s.radius then
      local c, wx, wy = B.Coords.ToWorld(s.map, s.x, s.y)
      if c == continent then
        local dx, dy = wx - px, wy - py
        if dx * dx + dy * dy <= s.radius * s.radius then
          return s
        end
      end
    end
  end
  return nil
end

-- An event at the spot: the farmed time grows by the gap since the last event of the session.
local function touch(spotID, at)
  local recs = records()
  local r = recs[spotID]
  if not r then
    r = { seconds = 0, money = 0, items = 0, unpriced = 0, kills = 0, sessions = 0 }
    recs[spotID] = r
  end
  if open and open.spot == spotID and at - open.lastAt <= Farming.GAP then
    r.seconds = r.seconds + (at - open.lastAt)
  else
    r.sessions = r.sessions + 1
  end
  open = { spot = spotID, lastAt = at }
  r.last = time()
  mod:Coalesce("farming", 5, function()
    B:Fire(Farming.MESSAGE)
  end)
  return r
end

function Farming.OnKill(payload)
  if not (payload and payload.by == "me") then
    return
  end
  local s = Farming.SpotHere()
  if s then
    local r = touch(s.id, GetTime())
    r.kills = r.kills + 1
  end
end

function Farming.OnLoot(payload)
  local s = payload and payload.item and Farming.SpotHere()
  if not s then
    return
  end
  local r = touch(s.id, GetTime())
  local _, itemID = B.Entity.Parse(payload.item)
  local service = B:GetService("prices")
  local p = service and itemID and service:Price(itemID) or nil
  if p and p.median then
    r.items = r.items + p.median * (payload.count or 1)
  else
    r.unpriced = r.unpriced + (payload.count or 1)
  end
end

function Farming.OnMoney(payload)
  local delta = payload and payload.delta
  if not (delta and delta > 0) or ns.Income.MailOpen() then
    return
  end
  local s = Farming.SpotHere()
  if s then
    local r = touch(s.id, GetTime())
    r.money = r.money + delta
  end
end

-- This character's record of a spot, or nil.
function Farming.Record(spotID)
  return mod and records()[spotID] or nil
end

-- The rate of a record, pure: copper per hour from MIN_KILLS kills and MIN_SECONDS on; nil
-- before that, with the reason ("kills" | "time").
function Farming.Rate(r)
  if not r then
    return nil, "kills"
  end
  if (r.kills or 0) < Farming.MIN_KILLS then
    return nil, "kills"
  end
  if (r.seconds or 0) < Farming.MIN_SECONDS then
    return nil, "time"
  end
  return math.floor(((r.money or 0) + (r.items or 0)) / r.seconds * 3600 + 0.5)
end

function Farming.Register(module)
  mod = module
  mod.Farming = Farming
  B:DeclareMessage(Farming.MESSAGE)
  local Facts = B.Facts
  if Facts and Facts.Watch then
    Facts.Watch(mod, "kill", function(_, payload)
      Farming.OnKill(payload)
    end)
    Facts.Watch(mod, "loot", function(_, payload)
      Farming.OnLoot(payload)
    end)
    Facts.Watch(mod, "money", function(_, payload)
      Farming.OnMoney(payload)
    end)
  end
end
