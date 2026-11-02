-- The Map feed for the community's broker displays (ADR 0043): the waypoint and how far it is on
-- the bar (zone and coordinates: every display ships them); nothing without a waypoint.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Map = ns.Map

local Feed = {}
ns.Feed = Feed

Feed.EVERY = 2 -- seconds between distance updates while a display shows a waypoint

local function distance(w)
  local c, px, py = B.Coords.Player()
  if not (c and w.wx) or c ~= w.continent then
    return nil -- another continent or an instance: unknown, not zero
  end
  return math.sqrt((w.wx - px) ^ 2 + (w.wy - py) ^ 2)
end

-- "Goldshire, 320 yd"; nothing without a waypoint.
function Feed.Text()
  local w = ns.Waypoints.Get()
  if not w then
    return nil
  end
  local label = w.label or L["Waypoint"]
  local d = B.UI.Distance(distance(w))
  return d and string.format(L["%s, %s"], label, d) or label
end

function Feed.Tooltip(tt)
  local w = ns.Waypoints.Get()
  if not w then
    S.TipLine(tt, L["No waypoint. Right click a place on the map to set one."], "tipDim", true)
    return
  end
  S.TipLine(tt, w.label or L["Waypoint"], "tipGold")
  if w.map and w.x then
    local zone = B:Entity("zone:" .. w.map):Name()
    S.TipLine(tt, string.format("%s %.1f, %.1f", zone or "", w.x * 100, w.y * 100), "tipText")
  end
end

table.insert(Map.onEnable, function(self)
  B:RegisterFeed(self, {
    text = Feed.Text,
    tooltip = Feed.Tooltip,
    hint = L["Click: the map. Right click: centre on you."],
    click = function(button)
      if button == "RightButton" then
        Map.Open()
        Map.CenterOnPlayer()
        return true
      end
    end,
    on = { "BASTIANS_LAYER_CHANGED" },
    every = function()
      return ns.Waypoints.Get() and Feed.EVERY or nil
    end,
  })
end)
