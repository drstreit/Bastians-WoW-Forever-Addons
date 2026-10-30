-- Bastian's Route: Explore, what is worth doing nearby (route.md "Explore", R26.11): the activities
-- the apps offer within a few minutes' way, by gold or XP per hour with the way there, from the
-- graph's `Activities`.
local _, ns = ...
local B = Bastians
local S = B.UI.Style
local L = ns.L

local Explore = {}
ns.Explore = Explore

Explore.VIEW = "route.explore"
Explore.MINUTES = { 5, 10, 20, 30, 60 } -- the way limits on offer (minutes)
Explore.PLANS = { 30, 60, 90, 120, 180 } -- the session plans on offer (minutes)
Explore.KIND_WORDS =
  { quest = "quest", spot = "farm spot", flip = "sale at the auction house", craft = "craft" }

local mod

local function db()
  return mod.db.profile
end

local function graph()
  return B:GetService("graph")
end

-- XP below the level cap, gold at it (and when the client does not tell the cap: XP).
function Explore.DefaultOrder()
  local cap = B.Compat.MaxLevel()
  local level = B.Compat.GetPlayerFacts().level
  if cap and level and level >= cap then
    return "gold"
  end
  return "xp"
end

local function xpText(xp)
  return string.format("%d %s", math.floor(xp + 0.5), L["XP/h"])
end

local function goldText(copper)
  return B.UI.MoneyShort(copper) .. "/h"
end

-- One row: the name, in grey the kind, the way and the other rate; the value the chosen rate.
function Explore.Row(hit, by)
  local e = B:Entity(hit.ref)
  local parts = { L[Explore.KIND_WORDS[hit.kind] or hit.kind] }
  parts[#parts + 1] = string.format(L["%s away"], B.UI.Duration(hit.seconds))
  local other = by == "xp" and hit.gold and goldText(hit.gold) or (by ~= "xp" and hit.xp and xpText(hit.xp))
  if other then
    parts[#parts + 1] = other
  end
  if hit.unpriced and hit.unpriced > 0 then
    parts[#parts + 1] = string.format(L["%d without price"], hit.unpriced)
  end
  local meta = table.concat(parts, ", ")
  local rate = hit[by]
  local row = {
    ref = hit.ref,
    title = e:Name() or hit.ref,
    icon = e:Icon(),
    meta = meta,
    text = (e:Name() or hit.ref) .. "  " .. S.H.muted .. meta .. "|r",
  }
  if rate and by == "gold" then
    row.value, row.valueKind = rate, "money"
  elseif rate then
    row.value, row.valueKind = xpText(rate), "text"
  else
    row.value, row.valueKind = L["unknown"], "text"
  end
  return row
end

-- The rows and the summary for a way limit (minutes) and an order ("gold" | "xp").
function Explore.Build(minutes, by)
  local g = graph()
  if not g then
    return {}, L["Explore needs Bastian's Data."]
  end
  local hits, waiting = g:Activities({ minutes = minutes, by = by }, 50)
  if not hits then
    return {}, L["Timing the ways from here..."]
  end
  local rows = {}
  for _, hit in ipairs(hits) do
    rows[#rows + 1] = Explore.Row(hit, by)
  end
  local summary = string.format(L["%d things to do within %d min"], #rows, minutes)
  if waiting > 0 then
    summary = summary .. ", " .. string.format(L["%d ways still being timed"], waiting)
  end
  return rows, summary
end

-- The plan for the next `minutes` (W10 step 3): the stops in order, each with its arrival, its
-- stay and its gain; the summary the whole. Returns rows, summary, plan (nil while the ways are
-- still being timed).
function Explore.BuildPlan(minutes, by)
  local g = graph()
  if not g then
    return {}, L["Explore needs Bastian's Data."], nil
  end
  local plan, why = g:Session(minutes, { by = by })
  if not plan then
    return {}, why == "timing" and L["Timing the ways from here..."] or tostring(why), nil
  end
  local rows = {}
  for k, s in ipairs(plan.stops) do
    local e = B:Entity(s.ref)
    local name = e:Name() or s.ref
    local gainText = by == "xp" and string.format("%d %s", math.floor(s.gain + 0.5), L["XP"])
      or B.UI.MoneyShort(s.gain)
    local meta = string.format(
      L["arrive in %s, %s there, +%s"],
      B.UI.Duration(s.arrive),
      B.UI.Duration(s.stay),
      gainText
    )
    if s.approx then
      meta = meta .. " " .. L["(way estimated)"]
    end
    rows[#rows + 1] = {
      ref = s.ref,
      title = string.format("%d. %s", k, name),
      icon = e:Icon(),
      meta = meta,
      text = string.format("%d. %s", k, name) .. "  " .. S.H.muted .. meta .. "|r",
      value = by == "xp" and gainText or s.gain,
      valueKind = by == "xp" and "text" or "money",
    }
  end
  local total = by == "xp" and string.format("%d %s", math.floor(plan.value + 0.5), L["XP"])
    or B.UI.MoneyShort(plan.value)
  local summary = #plan.stops == 0 and string.format(L["Nothing fits into %d min from here."], minutes)
    or string.format(
      L["Plan for %d min: %d stops, %s, %s"],
      minutes,
      #plan.stops,
      B.UI.Duration(plan.total),
      total
    )
  if (plan.waiting or 0) > 0 then
    summary = summary .. ", " .. string.format(L["%d ways still being timed"], plan.waiting)
  end
  return rows, summary, plan
end

-- Hands the plan's stops to the route service as a tour; false without one.
function Explore.RoutePlan(plan)
  local route = B:GetService("route")
  if not (route and route.Tour and plan and #plan.stops > 0) then
    return false
  end
  local stops = {}
  for k, s in ipairs(plan.stops) do
    stops[k] = {
      id = k,
      name = B:Entity(s.ref):Name() or s.ref,
      ref = s.ref,
      place = { map = s.place.map, wx = s.place.wx, wy = s.place.wy, wz = s.place.wz },
    }
  end
  return route:Tour(stops, L["My plan"]) ~= false
end

local function render(host)
  local p = db()
  local minutes = p.exploreMinutes or 10
  local by = p.exploreBy or Explore.DefaultOrder()
  local planMinutes = p.explorePlan or 0
  local chips = {}
  for _, m in ipairs(Explore.MINUTES) do
    chips[#chips + 1] = { key = m, label = string.format(L["%d min"], m) }
  end
  local planOptions = { { key = 0, label = L["List"] } }
  for _, m in ipairs(Explore.PLANS) do
    planOptions[#planOptions + 1] = { key = m, label = string.format(L["Plan %d min"], m) }
  end
  local controls = {
    {
      kind = "select",
      value = by,
      options = { { key = "xp", label = L["XP per hour"] }, { key = "gold", label = L["Gold per hour"] } },
      onChange = function(key)
        p.exploreBy = key
        host:Render()
      end,
    },
    {
      kind = "select",
      value = planMinutes,
      options = planOptions,
      onChange = function(key)
        p.explorePlan = key
        host:Render()
      end,
    },
  }
  local rows, summary, plan
  if planMinutes > 0 then
    rows, summary, plan = Explore.BuildPlan(planMinutes, by)
    if plan and #plan.stops > 0 and B:GetService("route") then
      controls[#controls + 1] = {
        kind = "button",
        label = L["Route the plan"],
        tooltip = L["A route through the plan's stops, in order."],
        onClick = function()
          Explore.RoutePlan(plan)
        end,
      }
    end
    host:SetChips({}, nil, nil, nil)
  else
    host:SetChips(chips, minutes, function(key)
      p.exploreMinutes = key
      host:Render()
    end, L["Way"])
    rows, summary = Explore.Build(minutes, by)
  end
  host:SetControls(controls)
  host:SetRows(rows)
  host:SetSummary(summary)
end

function Explore.Open()
  if not B:ShowView(Explore.VIEW) then
    local rows, summary = Explore.Build(db().exploreMinutes or 10, db().exploreBy or Explore.DefaultOrder())
    B:Say(summary)
    for i = 1, math.min(5, #rows) do
      B:Say("%s: %s", rows[i].title, rows[i].meta)
    end
  end
end

function Explore.Register(module)
  mod = module
  B:RegisterView(module, {
    id = Explore.VIEW,
    title = L["Explore"],
    group = L["Route"],
    order = 10,
    render = render,
    summary = function()
      return L["what is worth doing nearby"]
    end,
    invalidateOn = {
      "BASTIANS_GRAPH_TIMES",
      "BASTIANS_PRICES_UPDATED",
      "BASTIANS_QUESTS_CHANGED",
      "BASTIANS_PLAYER_MOVED_ZONE",
    },
  })
end

ns.mod.Explore = Explore -- for the tests
