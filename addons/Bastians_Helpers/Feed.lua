-- The Helpers feed for the community's broker displays (ADR 0043): what a helper did last on the
-- bar; the session's notices, newest first, in the tooltip. A click opens the session panel, a
-- right click the settings (Core's defaults).
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Helpers = ns.Helpers

local Feed = {}
ns.Feed = Feed

-- "just now", "3 min ago"
function Feed.Age(seconds)
  local minutes = math.floor(math.max(0, seconds) / 60)
  if minutes < 1 then
    return L["just now"]
  end
  return string.format(L["%d min ago"], minutes)
end

function Feed.Text()
  local last = Helpers.history[1]
  return last and last.text or ""
end

function Feed.Tooltip(tt)
  if #Helpers.history == 0 then
    S.TipLine(tt, L["Nothing done yet this session."], "tipDim")
    return
  end
  local now = GetTime()
  for _, n in ipairs(Helpers.history) do
    S.TipLine(tt, n.text .. "  " .. Feed.Age(now - n.at), "tipText")
  end
end

function Feed.Register(mod)
  B:RegisterFeed(mod, {
    text = Feed.Text,
    tooltip = Feed.Tooltip,
    hint = L["Click: the session panel. Right click: the Helpers settings."],
    -- no `on`: Helpers.Notice calls B:UpdateFeed (the voice may speak a notice without the bus)
  })
end
