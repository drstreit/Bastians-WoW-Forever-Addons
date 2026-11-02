-- The Gold feed for the community's broker displays (ADR 0043): today's net on the bar; today's
-- split, the week, the AH scan window, the prices and the bags' worth in the tooltip.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style

local Feed = {}
ns.Feed = Feed

local function signed(copper)
  if copper < 0 then
    return "-" .. B.UI.Money(-copper)
  end
  return "+" .. B.UI.Money(copper)
end

local function net(b)
  return (b.ah or 0) + (b.loot or 0) - (b.spent or 0)
end

-- "+12g 30s today"; nil while nothing was recorded today (unknown, not zero).
function Feed.Text()
  local day = ns.Income.Day()
  if not day then
    return nil
  end
  return string.format(L["%s today"], signed(net(day)))
end

function Feed.Tooltip(tt)
  local day = ns.Income.Day()
  if day then
    S.TipLine(tt, string.format(L["Today: %s"], signed(net(day))), "tipGold")
    tt:AddDoubleLine(L["Auction house"], B.UI.Money(day.ah or 0))
    tt:AddDoubleLine(L["Loot and sales"], B.UI.Money(day.loot or 0))
    tt:AddDoubleLine(L["Spent"], B.UI.Money(day.spent or 0))
  end
  S.TipLine(tt, string.format(L["Last 7 days: %s"], signed(net(ns.Income.Total(7)))), "tipText")
  local left = ns.Capture.WindowLeft()
  if left > 0 then
    S.TipLine(
      tt,
      string.format(L["AH scan: the window is taken for %d more min"], math.ceil(left / 60)),
      "tipDim"
    )
  else
    S.TipLine(tt, L["AH scan: the window is free"], "tipDim")
  end
  local note = ns.Prices.Note()
  if note and note ~= "" then
    S.TipLine(tt, note, "tipDim", true)
  end
  -- the bags' worth: priced only now, when the tooltip shows
  local groups = ns.Advisor.Build(ns.Advisor.BagItems())
  local post, vendor = groups.post, groups.vendor
  if post.total then
    tt:AddDoubleLine(string.format(L["To post on the AH (%d)"], #post.items), B.UI.Money(post.total))
  end
  if vendor.total then
    tt:AddDoubleLine(string.format(L["To sell to a vendor (%d)"], #vendor.items), B.UI.Money(vendor.total))
  end
end

-- The bag advisor's verdicts as item sets for the bag addons: { [itemID] = true } per verdict.
local function verdict(name)
  return function()
    local set = {}
    for _, a in ipairs(ns.Advisor.Build(ns.Advisor.BagItems())[name].items) do
      set[a.item.itemID] = true
    end
    return set
  end
end

function Feed.Register(mod)
  for _, s in ipairs({
    { id = "gold.ah", label = L["Bastian's: sell on AH"], kind = "category", verdict = "post" },
    { id = "gold.vendor", label = L["Bastian's: vendor"], kind = "junk", verdict = "vendor" },
  }) do
    B:RegisterItemSet(mod, {
      id = s.id,
      label = s.label,
      kind = s.kind,
      items = verdict(s.verdict),
      on = { "BASTIANS_PRICES_UPDATED" },
      events = { "BAG_UPDATE_DELAYED" },
    })
  end
  B:RegisterFeed(mod, {
    text = Feed.Text,
    tooltip = Feed.Tooltip,
    hint = L["Click: Gold. Right click: the bags."],
    click = function(button)
      if button == "RightButton" then
        ns.Window.Open("bags")
        return true
      end
    end,
    events = { "PLAYER_MONEY" },
  })
end
