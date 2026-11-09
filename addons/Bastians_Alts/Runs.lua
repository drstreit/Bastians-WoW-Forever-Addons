-- Dungeon runs and lockouts per character (alts.md "Runs and lockouts", catalog review A2.5,
-- 07.11.2026): a run is counted when the character enters an instance it was not in before (a
-- reload inside counts nothing), the lockouts come from the client's raid info. Shown as the
-- section "Your runs" on a dungeon's page (every character that ran it, the lockouts) and as
-- "Dungeon runs" on the character's Overview. The summary (Runs.Summary) is pure.
local _, ns = ...
local B = Bastians
local L = ns.L
local Alts = ns.Alts

local Runs = {}
ns.Runs = Runs

local mod

local function now()
  return B.Compat.ServerTime and B.Compat.ServerTime() or time()
end

-- Entering the world: inside an instance the character was not in before, one run more.
function Runs.OnEnteringWorld()
  local c = Alts.Me()
  local id = B.Compat.InstanceMap()
  if id and c.inInstance ~= id then
    c.runs = type(c.runs) == "table" and c.runs or {}
    local r = c.runs[id] or { n = 0 }
    r.n, r.last = r.n + 1, now()
    c.runs[id] = r
    B:Fire("BASTIANS_ALTS_CHANGED")
  end
  c.inInstance = id
  if B.Compat.RequestRaidInfo then
    B.Compat.RequestRaidInfo() -- the lockouts arrive with UPDATE_INSTANCE_INFO
  end
end

-- The raid info arrived: the lockouts of this character, by the instance's map id.
function Runs.OnInstanceInfo()
  local saved = B.Compat.SavedInstances()
  if saved == nil then
    return -- the client cannot tell: the record stays as it was (unknown is not none)
  end
  local c = Alts.Me()
  local lockouts = {}
  local at = now()
  for _, s in ipairs(saved) do
    if s.instance and s.locked and s.reset and s.reset > 0 then
      lockouts[s.instance] = at + s.reset
    end
  end
  c.lockouts = lockouts
  B:Fire("BASTIANS_ALTS_CHANGED")
end

-- The characters' runs of one dungeon, pure: `characters` = { [key] = { name, runs, lockouts } },
-- `myKey` first, then by name; only characters with a run or a lockout. -> { { key, name, me, n,
-- last, lockedFor (seconds, nil when not locked) } }
function Runs.Summary(characters, dungeonID, myKey, nowTime)
  local out = {}
  for key, c in pairs(characters or {}) do
    if type(c) == "table" then
      local r = type(c.runs) == "table" and c.runs[dungeonID] or nil
      local until_ = type(c.lockouts) == "table" and c.lockouts[dungeonID] or nil
      local left = until_ and nowTime and until_ > nowTime and (until_ - nowTime) or nil
      if (r and r.n and r.n > 0) or left then
        out[#out + 1] = {
          key = key,
          name = c.name or key,
          me = key == myKey,
          n = r and r.n or 0,
          last = r and r.last or nil,
          lockedFor = left,
        }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.me ~= b.me then
      return a.me
    end
    return a.name < b.name
  end)
  return out
end

local function runsRows(ref)
  local typ, id = B.Entity.Parse(ref)
  if typ ~= "dungeon" or not mod then
    return nil
  end
  local _, myKey = Alts.Me()
  local rows = {}
  for _, e in ipairs(Runs.Summary(mod.db.global.characters, tonumber(id), myKey, now())) do
    local who = e.me and L["You"] or e.name
    local text
    if e.n == 1 then
      text = string.format(L["%s: one run"], who)
    elseif e.n > 1 then
      text = string.format(L["%s: %d runs"], who, e.n)
    else
      text = who
    end
    local last = e.last and Alts.Age(e.last)
    if last and e.n > 0 then
      text = text .. ", " .. string.format(L["last %s"], last)
    end
    if e.lockedFor then
      text = text .. ", " .. string.format(L["locked, resets in %s"], B.UI.Duration(e.lockedFor))
    end
    rows[#rows + 1] = { text = text, ref = "character:" .. e.key }
  end
  if #rows == 0 then
    rows[1] = { text = L["No run recorded yet."] }
  end
  return rows
end

-- The Overview row of a character: how many runs it recorded; nil without any.
function Runs.OverviewRow(c)
  local total = 0
  for _, r in pairs(type(c.runs) == "table" and c.runs or {}) do
    total = total + (r.n or 0)
  end
  if total == 0 then
    return nil
  end
  return { text = L["Dungeon runs"], value = total, valueKind = "number" }
end

function Runs.Register(module)
  mod = module
  mod.Runs = Runs
  mod:RegisterEvent("UPDATE_INSTANCE_INFO", Runs.OnInstanceInfo)
  B:RegisterDetailSection(mod, {
    id = "alts.runs",
    chapter = "runs", -- its own chapter before the book (core-contracts, the chapter table)
    title = L["Your runs"],
    types = { "dungeon" },
    order = 60,
    invalidateOn = { "BASTIANS_ALTS_CHANGED" },
    build = runsRows,
  })
end
