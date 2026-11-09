-- The trainer view (alts.md "The trainer view", catalog review A5.7, 07.11.2026): what this
-- character's class trainers teach and the character does not know yet, split into what can be
-- learned now (with the cost and the nearest trainer) and what later levels bring; "you know
-- every spell for your level" when nothing waits. The rule (Train.Plan) is pure over plain tables;
-- the glue reads Data's trainer rows and Alts' own knowledge. Unknown stays unknown.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Alts = ns.Alts

local Train = {}
ns.Train = Train

Train.VIEW = "alts.train"

local mod

-- The plan over `spells` = { { spell, name, cost, level, known (true | false | nil), trainers } }
-- for a character of `playerLevel`: `now` the unknown ones the level allows, `later` the rest by
-- level, both sorted by level then name; `unknown` how many the client could not tell about;
-- `known` how many are known; `nowCost` the sum of the known costs of `now`.
function Train.Plan(spells, playerLevel)
  local out = { now = {}, later = {}, unknown = 0, known = 0, nowCost = 0 }
  for _, s in ipairs(spells or {}) do
    if s.known == true then
      out.known = out.known + 1
    elseif s.known == nil then
      out.unknown = out.unknown + 1
    elseif playerLevel and s.level and s.level > playerLevel then
      out.later[#out.later + 1] = s
    else
      out.now[#out.now + 1] = s
      out.nowCost = out.nowCost + (s.cost or 0)
    end
  end
  local function byLevel(a, b)
    if (a.level or 0) ~= (b.level or 0) then
      return (a.level or 0) < (b.level or 0)
    end
    return (a.name or "") < (b.name or "")
  end
  table.sort(out.now, byLevel)
  table.sort(out.later, byLevel)
  return out
end

-- "Mage" of the class token "MAGE": the word the pack's trainer subnames carry.
local function classWord(facts)
  local token = facts and facts.class
  if type(token) ~= "string" or token == "" then
    return nil
  end
  return string.upper(string.sub(token, 1, 1)) .. string.lower(string.sub(token, 2))
end

-- The spells this character's class trainers teach, one entry per spell id with every trainer.
-- nil without Data or a class word.
function Train.Spells()
  local d = B:GetService("data")
  local word = classWord(B.Compat.GetPlayerFacts())
  if not (d and word) then
    return nil
  end
  local subname = word .. " Trainer"
  local by, out = {}, {}
  for _, id in ipairs(d:Each("npc") or {}) do
    local r = d:Get("npc", id)
    if r and r.subname == subname and type(r.trainer) == "table" then
      for _, t in ipairs(r.trainer) do
        local spell = t[1]
        if spell then
          local entry = by[spell]
          if not entry then
            local known = Alts.Known(spell)
            entry = {
              spell = spell,
              name = B.Compat.GetSpellName(spell) or t[2] or (L["Spell"] .. " " .. tostring(spell)),
              cost = t[3],
              level = t[5] and t[5] > 0 and t[5] or nil,
              known = known and known.me,
              trainers = {},
            }
            by[spell] = entry
            out[#out + 1] = entry
          end
          entry.trainers[#entry.trainers + 1] = id
        end
      end
    end
  end
  return out
end

-- The nearest of the spell's trainers: its ref and the way there in words (nil when unknown).
local function nearest(trainers)
  local bestRef, bestWords, bestKey
  for _, id in ipairs(trainers or {}) do
    local ref = "npc:" .. id
    local words, key = B.UI.Away(ref)
    if not bestRef or (key and (not bestKey or key < bestKey)) then
      bestRef, bestWords, bestKey = ref, words, key
    end
  end
  return bestRef, bestWords
end

local function spellRow(s, withCost)
  local ref, away = nearest(s.trainers)
  local trainer = ref and B:Entity(ref):Name() or nil
  local meta = trainer
      and (away and string.format(L["at %s, %s"], trainer, away) or string.format(L["at %s"], trainer))
    or nil
  local text = s.name
  if s.level then
    text = string.format("[%d] %s", s.level, text)
  end
  if meta then
    text = text .. "  " .. S.H.muted .. meta .. "|r"
  end
  return {
    ref = ref,
    title = s.name,
    text = text,
    meta = meta,
    value = withCost and s.cost or nil,
    valueKind = "money",
    spell = s.spell,
  }
end

-- The rows and the summary. -> rows (nil without Data), summary.
function Train.Rows()
  local spells = Train.Spells()
  if not spells then
    return nil, L["The trainer view needs Bastian's Data."]
  end
  local facts = B.Compat.GetPlayerFacts() or {}
  local plan = Train.Plan(spells, facts.level)
  local rows = {}
  if #plan.now > 0 then
    local header = {
      id = "train:now",
      text = string.format("%s  %d  %s", L["Learn now"], #plan.now, B.UI.Money(plan.nowCost)),
      kind = "section",
      children = {},
    }
    for _, s in ipairs(plan.now) do
      header.children[#header.children + 1] = spellRow(s, true)
    end
    rows[#rows + 1] = header
  end
  if #plan.later > 0 then
    local header = {
      id = "train:later",
      text = string.format("%s  %d", L["Later"], #plan.later),
      kind = "section",
      children = {},
      folded = true,
    }
    for _, s in ipairs(plan.later) do
      header.children[#header.children + 1] = spellRow(s, true)
    end
    rows[#rows + 1] = header
  end
  local summary
  if #plan.now == 0 and plan.unknown == 0 then
    summary = #plan.later > 0 and string.format(L["Nothing to learn now; %d at later levels"], #plan.later)
      or L["You know every spell for your level."]
  else
    summary = string.format(
      L["%d spells to learn now for %s; %d at later levels"],
      #plan.now,
      B.UI.Money(plan.nowCost),
      #plan.later
    )
  end
  if plan.unknown > 0 then
    summary = summary .. string.format(L["; %d unknown whether known"], plan.unknown)
  end
  return rows, summary
end

-- ---------------------------------------------------------------------------------------------
-- Gold goals (alts.md "Gold goals", catalog review A5.5): what the next training costs, what the
-- riding skill and a mount cost at their level; rows of the character's Overview
-- ---------------------------------------------------------------------------------------------

Train.RIDING_NAME = "Riding" -- the pack's name of the riding skill's trainer rows (both ranks)
Train.MOUNT_CLASS, Train.MOUNT_SUBCLASS = 15, 5 -- item class Miscellaneous, subclass Mount

local cache -- { riding = { { spell, cost, level } }, mount = { item, cost, level } }, per data load

-- The riding ranks the trainers teach and the cheapest mount a vendor sells, read once per data
-- load (every record is decoded for it).
local function scan()
  if cache then
    return cache
  end
  local d = B:GetService("data")
  if not d then
    return nil
  end
  cache = { riding = {}, mount = nil }
  local seen = {}
  for _, id in ipairs(d:Each("npc") or {}) do
    local r = d:Get("npc", id)
    for _, t in ipairs(r and r.trainer or {}) do
      if t[2] == Train.RIDING_NAME and t[1] and not seen[t[1]] then
        seen[t[1]] = true
        cache.riding[#cache.riding + 1] = { spell = t[1], cost = t[3], level = t[5] }
      end
    end
  end
  table.sort(cache.riding, function(a, b)
    return (a.level or 0) < (b.level or 0)
  end)
  for _, id in ipairs(d:Each("item") or {}) do
    local r = d:Get("item", id)
    if
      r
      and r.class == Train.MOUNT_CLASS
      and r.subclass == Train.MOUNT_SUBCLASS
      and r.buy
      and r.buy > 0
      and (not cache.mount or r.buy < cache.mount.cost)
    then
      cache.mount = { item = id, cost = r.buy, level = r.reqLevel }
    end
  end
  return cache
end

function Train.ClearCache()
  cache = nil
end

-- The goals as plain facts (pure): `plan` from Train.Plan, `riding` the ranks { spell, cost,
-- level, known }, `mount` { item, cost, level } or nil. -> { { key, cost, level, ref } }: the next
-- training (what can be learned now; else the first later level's spells), the first riding rank
-- not known, a mount from that rank's level on. A cost nobody knows makes no goal.
function Train.Goals(plan, riding, mount)
  local goals = {}
  if plan and #plan.now > 0 and plan.nowCost > 0 then
    goals[#goals + 1] = { key = "training", cost = plan.nowCost }
  elseif plan and #plan.later > 0 then
    local level, cost = plan.later[1].level, 0
    for _, s in ipairs(plan.later) do
      if s.level == level then
        cost = cost + (s.cost or 0)
      end
    end
    if cost > 0 then
      goals[#goals + 1] = { key = "trainingAt", cost = cost, level = level }
    end
  end
  local rank
  for _, r in ipairs(riding or {}) do
    if r.known ~= true and r.cost and r.cost > 0 then
      rank = r
      break
    end
  end
  if rank then
    goals[#goals + 1] = { key = "riding", cost = rank.cost, level = rank.level }
    if mount and mount.cost and mount.cost > 0 then
      goals[#goals + 1] =
        { key = "mount", cost = mount.cost, level = mount.level or rank.level, ref = "item:" .. mount.item }
    end
  end
  return goals
end

local GOAL_WORDS = {
  training = "Next training",
  trainingAt = "Training at level %d",
  riding = "Riding at level %d",
  mount = "A mount at level %d",
}

-- The Overview rows of the goals for this character; nil without Data.
function Train.GoalRows()
  local spells = Train.Spells()
  local found = scan()
  if not (spells and found) then
    return nil
  end
  local facts = B.Compat.GetPlayerFacts() or {}
  local riding = {}
  for i, r in ipairs(found.riding) do
    local known = Alts.Known(r.spell)
    riding[i] = { spell = r.spell, cost = r.cost, level = r.level, known = known and known.me }
  end
  local rows = {}
  for _, g in ipairs(Train.Goals(Train.Plan(spells, facts.level), riding, found.mount)) do
    local words = L[GOAL_WORDS[g.key]]
    rows[#rows + 1] = {
      text = g.level and string.format(words, g.level) or words,
      ref = g.ref,
      value = g.cost,
      valueKind = "money",
      goal = g.key,
    }
  end
  return rows
end

local function render(host)
  host:SetControls({})
  local rows, summary = Train.Rows()
  host:SetRows(rows or {})
  host:SetSummary(summary)
end

function Train.Open()
  return B:ShowView(Train.VIEW)
end

function Train.Register(module)
  mod = module
  mod.Train = Train -- for the tests and the probe (Train.lua loads after Alts.lua)
  mod:On("BASTIANS_DATA_LOADED", Train.ClearCache) -- the riding ranks and the mount, per data load
  B:RegisterView(mod, {
    id = Train.VIEW,
    title = L["Trainer"],
    group = L["Alts"],
    rail = "characters", -- the Atlas's rail entry (ADR 0058)
    order = 30,
    render = render,
    summary = function()
      return L["what your class trainers teach you next"]
    end,
    invalidateOn = {
      "BASTIANS_ALTS_CHANGED", -- a spell learned, a level gained (Alts records both)
      "BASTIANS_DATA_LOADED",
      "BASTIANS_GRAPH_TIMES", -- the way to the trainers got times
      "BASTIANS_PLAYER_MOVED_ZONE",
    },
  })
end
