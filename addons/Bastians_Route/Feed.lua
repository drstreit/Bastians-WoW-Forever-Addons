-- The Route feed for the community's broker displays (ADR 0043): the target and the time left on
-- the bar (counting down while a display shows it); the steps in the tooltip.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style

local Feed = {}
ns.Feed = Feed

local TIP_STEPS = 10

-- "Stormwind, 3:20"; nothing without a route.
function Feed.Text()
  local route = ns.Route.Active()
  if not route then
    return nil
  end
  local goal = route.tour and route.tour.name or route.goal and route.goal.name or L["the target"]
  return string.format(L["%s, %s"], goal, ns.Graph.FormatSeconds(ns.Graph.Remaining(route)))
end

function Feed.Tooltip(tt)
  local route = ns.Route.Active()
  if not route then
    S.TipLine(tt, L["No route. Right click anything with a place and choose Route to."], "tipDim", true)
    return
  end
  local from = route.index or 1
  for i = from, math.min(#route.steps, from + TIP_STEPS - 1) do
    S.TipLine(
      tt,
      string.format("%d. %s", i, ns.Graph.StepText(route.steps[i], L)),
      i == from and "tipGold" or "tipText"
    )
  end
  if #route.steps >= from + TIP_STEPS then
    S.TipLine(tt, string.format(L["and %d more"], #route.steps - from - TIP_STEPS + 1), "tipDim")
  end
end

function Feed.Register(mod)
  B:RegisterFeed(mod, {
    text = Feed.Text,
    tooltip = Feed.Tooltip,
    hint = L["Click: the steps. Right click: clear the route."],
    click = function(button)
      if button == "RightButton" then
        ns.Route.Clear()
        return true
      end
    end,
    on = { "BASTIANS_ROUTE_CHANGED" },
    every = function()
      return ns.Route.Active() and 1 or nil -- the time left counts down
    end,
  })
end
