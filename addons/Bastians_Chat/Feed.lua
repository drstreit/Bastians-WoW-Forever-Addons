-- The Chat feed for the community's broker displays (ADR 0043): how many whispers wait unread in
-- the Messenger; who wrote, newest first, in the tooltip. A click opens the Messenger, a right
-- click marks every conversation read.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style

local Feed = {}
ns.Feed = Feed

local TIP_PEOPLE = 8

-- "2 whispers" (the conversations with unread lines), "" when none
function Feed.Text()
  local n = #ns.Messenger.UnreadConvos()
  if n == 0 then
    return ""
  end
  return n == 1 and L["1 whisper"] or string.format(L["%d whispers"], n)
end

function Feed.Tooltip(tt)
  local list = ns.Messenger.UnreadConvos()
  if #list == 0 then
    S.TipLine(tt, L["No unread whispers."], "tipDim")
    return
  end
  for i, c in ipairs(list) do
    if i > TIP_PEOPLE then
      S.TipLine(tt, string.format(L["and %d more"], #list - TIP_PEOPLE), "tipDim")
      break
    end
    S.TipLine(tt, string.format("%s (%d)", c.name or "?", c.unread), "tipText")
  end
end

function Feed.Register(mod)
  B:RegisterFeed(mod, {
    text = Feed.Text,
    tooltip = Feed.Tooltip,
    hint = L["Click: the Messenger. Right click: mark all read."],
    click = function(button)
      if button == "RightButton" then
        ns.Messenger.MarkAllRead()
      else
        ns.Messenger.Show()
      end
      return true
    end,
    on = { "BASTIANS_CHAT_UNREAD" },
  })
end
