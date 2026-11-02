-- The Campfire feed for the community's broker displays (ADR 0043): the fire's state and the
-- warmth's time left; the tooltip lists the buffs, what the player could add and the shared fires.
-- A click opens the planner, a right click shares the fire.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Model = ns.Model

local Feed = {}
ns.Feed = Feed

function Feed.Text()
  local card = ns.Watch.Card()
  if card.state == "warm" or card.state == "fading" then
    return card.left and string.format(L["Warm %s"], Model.Clock(card.left)) or L["Warm"]
  elseif card.state == "warming" then
    return L["Getting warm"]
  elseif card.state == "near" then
    return L["A fire nearby"]
  end
  return L["No fire"]
end

function Feed.Tooltip(tt)
  local card = ns.Watch.Card()
  for _, key in ipairs(card.have) do
    S.TipLine(tt, ns.Card.Label(key), "tipText")
  end
  if #card.could > 0 then
    local names = {}
    for _, feature in ipairs(card.could) do
      names[#names + 1] = L[feature.name]
    end
    S.TipLine(tt, string.format(L["You could add: %s."], table.concat(names, ", ")), "tipDim", true)
  end
  local fires = #ns.Beacon.Fires()
  if fires > 0 then
    S.TipLine(tt, string.format(L["Shared fires: %d"], fires), "tipDim")
  end
end

function Feed.Register(mod)
  B:RegisterFeed(mod, {
    text = Feed.Text,
    tooltip = Feed.Tooltip,
    hint = L["Click: the planner. Right click: share the fire."],
    click = function(button)
      if button == "RightButton" then
        ns.Beacon.Share()
      else
        ns.Campfire.Toggle()
      end
      return true
    end,
    on = { "BASTIANS_CAMP_CHANGED" },
  })
end
