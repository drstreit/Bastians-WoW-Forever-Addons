-- Income per day: gold per day, the auction
-- house apart from loot, for the account with a line per character. PLAYER_MONEY deltas: a gain
-- while the mailbox is open is AH (sales arrive as mail), any other gain is loot (drops, quests,
-- vendor sales), a loss is spent. Kept per day in BastiansGoldDB.global.income, the last 60 days.
local _, ns = ...

local Income = {}
ns.Income = Income

Income.KEEP_DAYS = 60
Income.KINDS = { "ah", "loot", "spent" }

local mod
local last -- the money at the last look, nil until the first
local mailOpen = false

local function dayKey(offset)
  return date("%Y-%m-%d", time() - (offset or 0) * 86400)
end
Income.DayKey = dayKey

local function charKey()
  return (UnitName("player") or "?") .. " - " .. (GetRealmName() or "?")
end
Income.CharKey = charKey

local function store()
  local g = mod.db.global
  if type(g.income) ~= "table" then
    g.income = {}
  end
  return g.income
end

local function empty()
  return { ah = 0, loot = 0, spent = 0 }
end

local function bucket(day)
  local s = store()
  local b = s[day]
  if not b then
    b = empty()
    b.chars = {}
    s[day] = b
  end
  return b
end

-- Days older than KEEP_DAYS go (the keys sort as dates).
local function prune()
  local s = store()
  local oldest = dayKey(Income.KEEP_DAYS)
  for day in pairs(s) do
    if day < oldest then
      s[day] = nil
    end
  end
end

local function add(kind, copper)
  local b = bucket(dayKey())
  b[kind] = (b[kind] or 0) + copper
  local name = charKey()
  local c = b.chars[name]
  if not c then
    c = empty()
    b.chars[name] = c
  end
  c[kind] = (c[kind] or 0) + copper
  prune()
end

-- Called on PLAYER_MONEY: the difference to the last look, filed by what was open.
function Income.OnMoney()
  local now = GetMoney() or 0
  if last == nil then
    last = now
    return
  end
  local delta = now - last
  last = now
  if delta > 0 then
    add(mailOpen and "ah" or "loot", delta)
  elseif delta < 0 then
    add("spent", -delta)
  end
end

-- The day's figures: { ah, loot, spent, chars = { [name] = { ah, loot, spent } } } or nil.
function Income.Day(day)
  return mod and store()[day or dayKey()] or nil
end

-- The sum over the last `days` days (today included), per kind.
function Income.Total(days)
  local out = empty()
  if not mod then
    return out
  end
  local s = store()
  for i = 0, (days or 1) - 1 do
    local b = s[dayKey(i)]
    if b then
      for _, kind in ipairs(Income.KINDS) do
        out[kind] = out[kind] + (b[kind] or 0)
      end
    end
  end
  return out
end

function Income.MailOpen()
  return mailOpen
end

-- One handler per event per module (Core): the Window registers PLAYER_MONEY and calls
-- Income.OnMoney first, then its own re-render.
function Income.Register(self)
  mod = self
  last = GetMoney() or 0
  self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    last = GetMoney() or 0 -- a login or a zone load is no income
  end)
  self:RegisterEvent("MAIL_SHOW", function()
    mailOpen = true
  end)
  self:RegisterEvent("MAIL_CLOSED", function()
    mailOpen = false
  end)
end
