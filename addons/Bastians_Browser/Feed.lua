-- The Browser's feed for the community's broker displays (ADR 0043): a launcher with no text,
-- the home on a click and the bookmarks on a right click.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style

local Feed = {}
ns.Feed = Feed

function Feed.Register(mod)
  B:RegisterFeed(mod, {
    text = function()
      return nil
    end,
    tooltip = function(tt)
      S.TipLine(tt, L["Everything the suite knows: quests, NPCs, items, places."], "tipText", true)
    end,
    hint = L["Click: the Browser. Right click: the bookmarks."],
    click = function(button)
      if button == "RightButton" then
        ns.Browser.Bookmarks()
        return true
      end
    end,
  })
end
