-- The book's feed for the community's broker displays (ADR 0043): what is new in the book, else
-- how many pages it has, on the bar; the newest entries in the tooltip.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style

local Feed = {}
ns.Feed = Feed

local TIP_NEWS = 6

local function unread()
  local g = ns.mod.db.global
  return ns.Book.Unread(ns.Window.News(), g.seen, g.seenToday)
end

-- "2 new" or "26 pages"; nothing while the pages are not installed.
function Feed.Text()
  local d = B:GetService("data")
  if not (d and d:PackLoaded("book")) then
    return nil
  end
  local n = unread()
  if n > 0 then
    return string.format(L["%d new"], n)
  end
  local pages = 0
  for _, p in pairs(ns.Window.Pages()) do
    if p.shelf == "active" then
      pages = pages + 1
    end
  end
  return string.format(L["%d pages"], pages)
end

function Feed.Tooltip(tt)
  S.TipLine(tt, ns.Strategies.Note(), "tipDim", true)
  for i, entry in ipairs(ns.Book.Fold(ns.Window.News(), L)) do
    if i > TIP_NEWS then
      break
    end
    S.TipLine(tt, entry.date .. ": " .. tostring(entry.text), "tipText", true)
  end
end

function Feed.Register(mod)
  B:RegisterFeed(mod, {
    text = Feed.Text,
    tooltip = Feed.Tooltip,
    hint = L["Click: the book. Right click: its settings."],
    on = { "BASTIANS_DATA_LOADED" },
  })
end
