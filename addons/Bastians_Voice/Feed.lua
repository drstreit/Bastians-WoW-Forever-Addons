-- The Orbiter's feed for the community's broker displays (ADR 0043, plan-second-wave.md S12): what
-- plays now on the bar, the line's state in the tooltip; a click pauses or resumes it, or opens
-- the Orbiter when nothing plays; a right click stops everything.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Voice = ns.Voice

local Feed = {}
ns.Feed = Feed

-- The title of the line playing; nothing when the Orbiter is quiet.
function Feed.Text()
  local now = Voice.Now()
  return now and now.title or nil
end

function Feed.Tooltip(tt)
  local now = Voice.Now()
  if not now then
    S.TipLine(tt, L["Nothing plays."], "tipDim", true)
    return
  end
  S.TipLine(tt, tostring(now.title or ""), "tipGold", true)
  if now.paused then
    S.TipLine(tt, L["paused"], "tipDim")
  end
end

function Feed.Register(mod)
  B:RegisterFeed(mod, {
    text = Feed.Text,
    tooltip = Feed.Tooltip,
    hint = L["Click: pause or resume the line, or open the Orbiter. Right click: stop everything."],
    click = function(button)
      if button == "RightButton" then
        Voice.StopAll()
        return true
      end
      if Voice.Now() then
        Voice.TogglePause()
        return true
      end
    end,
    on = { "BASTIANS_VOICE_CHANGED" },
  })
end
