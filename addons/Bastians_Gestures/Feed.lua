-- The Gestures feed for the community's broker displays (ADR 0043): the ring in front; a
-- click opens the options (a second click closes them; owner, retail
-- 02.11.2026: "should anyway open their options, not the radial menu"), a right click the editor.
local _, ns = ...
local B = Bastians
local L = ns.L

local Feed = {}
ns.Feed = Feed

function Feed.Text()
  local ring = ns.Ring.Current()
  return ring and ring.name or L["Gestures"]
end

function Feed.Register(mod)
  B:RegisterFeed(mod, {
    text = Feed.Text,
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
