-- The Alts feed for the community's broker displays (ADR 0043): the account's gold on the bar;
-- every character's money, level and zone in the tooltip.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style

local Feed = {}
ns.Feed = Feed

-- The recorded characters, richest first: { { key, c } }.
local function characters()
  local list = {}
  for key, c in pairs(ns.Alts.mod.db.global.characters) do
    list[#list + 1] = { key = key, c = c }
  end
  table.sort(list, function(a, b)
    if (a.c.money or -1) ~= (b.c.money or -1) then
      return (a.c.money or -1) > (b.c.money or -1)
    end
    return a.key < b.key
  end)
  return list
end

-- The account's gold: the sum of the money known, and how many characters it covers (nil, 0
-- when no money is known: unknown, not zero).
function Feed.Total()
  local total, known = nil, 0
  for _, entry in ipairs(characters()) do
    if entry.c.money then
      total = (total or 0) + entry.c.money
      known = known + 1
    end
  end
  return total, known
end

-- "1234g 05s on 5 characters"
function Feed.Text()
  local total, known = Feed.Total()
  if not total then
    return nil
  end
  return string.format(L["%s on %d characters"], B.UI.Money(total), known)
end

function Feed.Tooltip(tt)
  for _, entry in ipairs(characters()) do
    local c = entry.c
    local left = string.format("%s (%s)", c.name or entry.key, tostring(c.level or "?"))
    local zone = c.zone and B:Entity("zone:" .. c.zone):Name()
    if zone then
      left = left .. ", " .. zone
    end
    tt:AddDoubleLine(left, B.UI.Money(c.money) or L["unknown"])
  end
  S.TipLine(tt, L["Every character is recorded when it logs in."], "tipDim", true)
end

function Feed.Register(mod)
  B:RegisterFeed(mod, {
    text = Feed.Text,
    tooltip = Feed.Tooltip,
    hint = L["Click: your characters' window. Right click: its settings."],
    on = { "BASTIANS_ALTS_CHANGED" },
  })
end
