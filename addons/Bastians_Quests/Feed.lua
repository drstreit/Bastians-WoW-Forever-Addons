-- The Quests feed for the community's broker displays (ADR 0043): the log and what is ready to
-- turn in on the bar; ready quests, the next recommendation and the session in the tooltip.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style

local Feed = {}
ns.Feed = Feed

local TIP_QUESTS = 8 -- ready quests named in the tooltip

-- The quests of the log that can be turned in, in log order.
function Feed.Ready()
  return ns.State.Ready()
end

-- "14 in the log, 3 ready"; nil before the first snapshot (unknown, not zero).
function Feed.Text()
  local count = ns.State.count
  if count == nil then
    return nil
  end
  local ready = #Feed.Ready()
  if ready > 0 then
    return string.format(L["%d in the log, %d ready"], count, ready)
  end
  return string.format(L["%d in the log"], count)
end

local function questName(id, entry)
  local e = B:Entity("quest:" .. id)
  return entry and entry.title or (e and e:Name()) or ("#" .. id)
end

function Feed.Tooltip(tt)
  local ready = Feed.Ready()
  if #ready > 0 then
    S.TipLine(tt, L["Ready to turn in:"], "tipGold")
    for i, e in ipairs(ready) do
      if i > TIP_QUESTS then
        S.TipLine(tt, string.format(L["and %d more"], #ready - TIP_QUESTS), "tipDim")
        break
      end
      S.TipLine(tt, "  " .. questName(e.questID, e), "tipText")
    end
  end
  -- the next recommendation here: scored only now, when the tooltip shows
  local map = B.Coords.PlayerMap()
  if map and ns.Logic.knows(map) then
    for _, rec in ipairs(ns.Recommend.rank(map, ns.State.ForLogic(), ns.Window.RecommendContext(map))) do
      if not rec.inLog then
        S.TipLine(tt, L["Next here: "] .. questName(rec.qid), "tipText")
        break
      end
    end
  end
  local here = map and ns.Journey.Zone(map)
  if here then
    S.TipLine(tt, L["This session here: "] .. ns.Journey.Words(here), "tipDim", true)
  end
end

-- The items the quests in the log ask for (their loot objectives): an item set for the bag
-- addons, { [itemID] = true }.
function Feed.QuestItems()
  local set = {}
  for _, id in ipairs(ns.State.order or {}) do
    local q = ns.Logic.quest(id)
    for _, o in ipairs(q and q.objectives or {}) do
      local item = o[1] == "loot" and type(o[2]) == "string" and tonumber(string.match(o[2], "^item:(%d+)$"))
      if item then
        set[item] = true
      end
    end
  end
  return set
end

function Feed.Register(mod)
  B:RegisterItemSet(mod, {
    id = "quests.items",
    label = L["Bastian's: quest items"],
    kind = "mark",
    items = Feed.QuestItems,
    on = { "BASTIANS_QUESTS_CHANGED", "BASTIANS_DATA_LOADED" },
  })
  B:RegisterFeed(mod, {
    text = Feed.Text,
    tooltip = Feed.Tooltip,
    hint = L["Click: the quests. Right click: the tracker."],
    click = function(button)
      if button == "RightButton" then
        ns.Tracker.Toggle()
        return true
      end
    end,
    on = { "BASTIANS_QUESTS_CHANGED" },
  })
end
