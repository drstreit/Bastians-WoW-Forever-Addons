-- Bastian's Gold: the session plan (gold.md "The session plan", W10 step 3), what fits into the next
-- 30 to 180 minutes from the graph's `Session`, as a view in the Browser. Off by default (owner: a
-- plan to the minute spoils the fun of exploring); moved here from Route's Explore 04.11.2026.
local _, ns = ...
local B = Bastians
local S = B.UI.Style
ns.L = ns.L or B.NewLocale()
local L = ns.L

local Plan = {}
ns.Plan = Plan

Plan.VIEW = "gold.plan"
Plan.MINUTES = { 30, 60, 90, 120, 180 } -- the plans on offer (minutes)

local mod

local function db()
  return mod.db.profile
end

local function amount(by, value)
  if by == "xp" then
    return string.format("%d %s", math.floor(value + 0.5), L["XP"])
  end
  return B.UI.MoneyShort(value)
end

-- The plan for the next `minutes` by "gold" | "xp": the stops in order, each with its arrival, its
-- stay and its gain; the summary the whole. Returns rows, summary, plan (nil while the ways are
-- still being timed).
function Plan.Build(minutes, by)
  local g = B:GetService("graph")
  if not g then
    return {}, L["The session plan needs Bastian's Data."], nil
  end
  local plan, why = g:Session(minutes, { by = by })
  if not plan then
    return {}, why == "timing" and L["Timing the ways from here..."] or tostring(why), nil
  end
  local rows = {}
  for k, s in ipairs(plan.stops) do
    local e = B:Entity(s.ref)
    local name = e:Name() or s.ref
    local gainText = amount(by, s.gain)
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
  local summary = #plan.stops == 0 and string.format(L["Nothing fits into %d min from here."], minutes)
    or string.format(
      L["Plan for %d min: %d stops, %s, %s"],
      minutes,
      #plan.stops,
      B.UI.Duration(plan.total),
      amount(by, plan.value)
    )
  if (plan.waiting or 0) > 0 then
    summary = summary .. ", " .. string.format(L["%d ways still being timed"], plan.waiting)
  end
  return rows, summary, plan
end

-- Hands the plan's stops to the route service as a tour; false without one.
function Plan.Route(plan)
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
  local minutes = p.planMinutes or 60
  local by = p.planBy or "gold"
  local options = {}
  for _, m in ipairs(Plan.MINUTES) do
    options[#options + 1] = { key = m, label = string.format(L["Plan %d min"], m) }
  end
  local controls = {
    {
      kind = "select",
      value = by,
      options = { { key = "gold", label = L["Gold per hour"] }, { key = "xp", label = L["XP per hour"] } },
      onChange = function(key)
        p.planBy = key
        host:Render()
      end,
    },
    {
      kind = "select",
      value = minutes,
      options = options,
      onChange = function(key)
        p.planMinutes = key
        host:Render()
      end,
    },
  }
  local rows, summary, plan = Plan.Build(minutes, by)
  if plan and #plan.stops > 0 and B:GetService("route") then
    controls[#controls + 1] = {
      kind = "button",
      label = L["Route the plan"],
      tooltip = L["A route through the plan's stops, in order."],
      onClick = function()
        Plan.Route(plan)
      end,
    }
  end
  host:SetChips({}, nil, nil, nil)
  host:SetControls(controls)
  host:SetRows(rows)
  host:SetSummary(summary)
end

-- The view while the option is on (off by default), taken back when it is switched off.
function Plan.Apply()
  if mod and mod:IsEnabled() and db().sessionPlan then
    if not B:GetView(Plan.VIEW) then
      B:RegisterView(mod, {
        id = Plan.VIEW,
        title = L["Session plan"],
        group = L["Gold"],
        order = 40,
        render = render,
        summary = function()
          return L["what fits into the next 30 to 180 minutes"]
        end,
        invalidateOn = {
          "BASTIANS_GRAPH_TIMES",
          "BASTIANS_PRICES_UPDATED",
          "BASTIANS_QUESTS_CHANGED",
          "BASTIANS_PLAYER_MOVED_ZONE",
        },
      })
    end
  else
    B:UnregisterView(Plan.VIEW)
  end
end

-- Opens the plan; false while it is switched off or no host shows views.
function Plan.Open()
  return db().sessionPlan == true and B:ShowView(Plan.VIEW) or false
end

function Plan.Register(module)
  mod = module
  Plan.Apply()
end
