-- The Gestures feed for the community's broker displays (ADR 0043): the ring in front, the
-- courtesy mode in the tooltip; a click opens the options (a second click closes them; owner, retail
-- 02.11.2026: "should anyway open their options, not the radial menu"), a right click the editor.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style

local Feed = {}
ns.Feed = Feed

function Feed.Text()
  local ring = ns.Ring.Current()
  return ring and ring.name or L["Gestures"]
end

function Feed.Tooltip(tt)
  local p = ns.Gestures.mod.db.profile
  local modes = { ask = L["Ask"], auto = L["Automatic"], off = L["Off"] }
  S.TipLine(tt, string.format(L["Courtesy: %s"], modes[p.courtesy or "ask"] or p.courtesy), "tipText")
end

function Feed.Register(mod)
  B:RegisterFeed(mod, {
    text = Feed.Text,
    tooltip = Feed.Tooltip,
    hint = L["Click: the options. Right click: edit the rings."],
    click = function(button)
      if button == "RightButton" then
        ns.Editor.Open()
      else
        B.UI.Hub.TogglePage("Gestures")
      end
      return true
    end,
    on = { "BASTIANS_GESTURES_CHANGED" },
  })
end
