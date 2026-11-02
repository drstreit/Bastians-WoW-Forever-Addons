-- The Notes feed for the community's broker displays (ADR 0043): how many notes there are on the
-- bar; the notes near the character and the reminders in the tooltip.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style

local Feed = {}
ns.Feed = Feed

Feed.NEAR_YARDS = 300 -- the tooltip's "near here"
local TIP_NOTES = 8

local function count(g)
  local n = 0
  for _, list in pairs(g.lists) do
    for _ in pairs(list.notes) do
      n = n + 1
    end
  end
  return n
end

-- "12 notes, 2 reminders"
function Feed.Text()
  local g = ns.Notes.Global()
  local notes, reminders = count(g), #ns.Notes.Model.Reminders(g)
  if reminders > 0 then
    return string.format(L["%d notes, %d reminders"], notes, reminders)
  end
  return string.format(L["%d notes"], notes)
end

-- The notes on the character's zone and those placed within NEAR_YARDS, nearest first.
function Feed.Near()
  local g = ns.Notes.Global()
  local c, px, py, map = B.Coords.Player()
  local out, seen = {}, {}
  if map then
    for _, n in ipairs(ns.Notes.Model.On(g, "zone:" .. map)) do
      seen[n] = true
      out[#out + 1] = { note = n, d = 0 }
    end
  end
  if c then
    for _, n in ipairs(ns.Notes.Model.Spots(g, c)) do
      if not seen[n] then
        for _, p in ipairs(ns.Notes.PlacesOf(n, c)) do
          local d = math.sqrt((p.wx - px) ^ 2 + (p.wy - py) ^ 2)
          if d <= Feed.NEAR_YARDS and not seen[n] then
            seen[n] = true
            out[#out + 1] = { note = n, d = d }
          end
        end
      end
    end
  end
  table.sort(out, function(a, b)
    return a.d < b.d
  end)
  return out
end

function Feed.Tooltip(tt)
  local near = Feed.Near()
  if #near == 0 then
    S.TipLine(tt, L["No notes near here."], "tipDim")
  else
    S.TipLine(tt, L["Near here:"], "tipGold")
    for i, entry in ipairs(near) do
      if i > TIP_NOTES then
        S.TipLine(tt, string.format(L["and %d more"], #near - TIP_NOTES), "tipDim")
        break
      end
      S.TipLine(tt, "  " .. ns.Notes.Coloured(entry.note), "tipText")
    end
  end
end

function Feed.Register(mod)
  B:RegisterFeed(mod, {
    text = Feed.Text,
    tooltip = Feed.Tooltip,
    hint = L["Click: the lists. Right click: a note here."],
    click = function(button)
      if button == "RightButton" then
        SlashCmdList.BASTIANSNOTES("add")
        return true
      end
    end,
    on = { "BASTIANS_NOTES_CHANGED" },
  })
end
