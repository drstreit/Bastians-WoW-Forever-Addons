-- The Gold window (gold.md): tabs Today (the ranked lines), Farm spots (all spots, or those of one
-- item), Price (one item's price section) and Bags (the bag advisor, S4). One window over the
-- shared tree; rebuilds are coalesced.
local _, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
local L = ns.L
local S = B.UI.Style
local Today, Spots = ns.Today, ns.Spots

local W = {}
ns.Window = W

local TABS = { { "today", "Today" }, { "spots", "Farm spots" }, { "price", "Price" }, { "bags", "Bags" } }
-- what each tab shows, after the hover delay
local TAB_TIPS = {
  today = L["Your income today and this week, and what the market does."],
  spots = L["Farm spots and strategies with gold per hour."],
  price = L["The price of an item: auction house, vendor, history."],
  bags = L["What to sell, post or keep from your bags."],
}
local TAB_W = 100
local RENDER_DELAY = 0.05

local mod, win, tree, summary, hint
local tabs = {}
local filterItem -- the item of the Farm spots tab (nil = all) and of the Price tab

local function db()
  return mod.db.profile
end

local function view()
  return db().view or "today"
end

local function data()
  return B:GetService("data")
end

local function prices()
  return B:GetService("prices")
end

-- The signals of the player's market from the Market pack, as records with their ids.
local function marketSignals()
  local d, service = data(), prices()
  local market = service and service:Market() or nil
  if not (d and market and d:PackLoaded("market")) then
    return nil
  end
  local out = {}
  for _, key in ipairs(d:Index("signal.byMarket", market.id) or {}) do
    local s = d:Get("signal", key)
    if s then
      out[#out + 1] = s
    end
  end
  return out
end

-- The context of the Today filters: capital, time, professions, now.
function W.Context()
  local p = db()
  return {
    capital = B.Compat.GetMoney(),
    minutes = p.minutes,
    professions = B.Compat.GetProfessions(),
    now = GetServerTime(),
    maxLines = Today.MAX_LINES,
  }
end

local function setTabs()
  for _, b in ipairs(tabs) do
    local on = b.view == view()
    local c = on and S.C.accent or S.C.dim
    b.label:SetTextColor(c[1], c[2], c[3])
    S.setEdges(b.edges, on and S.C.accent or S.C.line, on and 0.8 or nil)
  end
end

-- The income block: gold per day, AH apart from loot, the
-- account's total with a line per character, today and the last seven days.
local function incomeRows()
  local Income = ns.Income
  local today = Income.Day() or { ah = 0, loot = 0, spent = 0, chars = {} }
  local week = Income.Total(7)
  local function words(b)
    return string.format(
      "%s %s, %s %s, %s %s",
      L["AH"],
      B.UI.Money(b.ah or 0),
      L["loot"],
      B.UI.Money(b.loot or 0),
      L["spent"],
      B.UI.Money(b.spent or 0)
    )
  end
  local rows = {
    {
      id = "income:today",
      text = L["Today"] .. "  " .. S.H.muted .. words(today) .. "|r",
      value = (today.ah or 0) + (today.loot or 0),
      valueKind = "money",
    },
    {
      id = "income:week",
      text = L["Last 7 days"] .. "  " .. S.H.muted .. words(week) .. "|r",
      value = (week.ah or 0) + (week.loot or 0),
      valueKind = "money",
    },
  }
  local names = {}
  for name in pairs(today.chars or {}) do
    names[#names + 1] = name
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local c = today.chars[name]
    rows[#rows + 1] = {
      id = "income:char:" .. name,
      text = name .. "  " .. S.H.muted .. words(c) .. "|r",
      value = (c.ah or 0) + (c.loot or 0),
      valueKind = "money",
    }
  end
  return {
    id = "today:income",
    kind = "section",
    text = S.accent() .. string.upper(L["Income"]) .. "|r  " .. S.H.muted .. L["gold per day"] .. "|r",
    children = rows,
  }
end

local function todayRows()
  local signals = marketSignals()
  if not signals then
    local service = prices()
    local market = service and service:Market() or nil
    local text = market and string.format(L["no market data yet for %s"], market.id)
      or L["no market data yet"]
    return { incomeRows(), { text = S.H.muted .. text .. "|r", kind = "para" } },
      L["Today: no market data yet"]
  end
  local ctx = W.Context()
  local lines, dropped, total = Today.build(signals, ctx)
  local roots = { incomeRows() }
  for _, group in ipairs(Today.groups(lines)) do
    local rows = {}
    for _, line in ipairs(group.lines) do
      local name = line.item and (B:Entity("item:" .. line.item):Name() or (L["Item"] .. " " .. line.item))
        or "?"
      rows[#rows + 1] = {
        id = "today:" .. tostring(line.key),
        ref = line.item and ("item:" .. line.item) or nil,
        text = name .. "  " .. S.H.muted .. Today.reason(line) .. "|r",
        value = line.profit,
        valueKind = line.profit and "money" or nil,
        tooltip = function(tt)
          S.TipLine(tt, name, "tipGold")
          S.TipLine(tt, line.rationale or "", "tipText", true)
          tt:AddLine(
            string.format(
              "%s %s, %s %s",
              L["module"],
              tostring(line.module),
              L["horizon"],
              tostring(line.horizon)
            ),
            0.6,
            0.6,
            0.6
          )
        end,
      }
    end
    roots[#roots + 1] = {
      id = "today:" .. group.action,
      kind = "section",
      text = S.accent() .. string.upper(L[group.action]) .. "|r  " .. S.H.muted .. #rows .. "|r",
      children = rows,
    }
  end
  if #roots == 0 then
    roots[1] = {
      text = S.H.muted
        .. L["Nothing for you today: every signal needs more capital, time or a profession you lack."]
        .. "|r",
      kind = "para",
    }
  end
  local parts = {
    string.format(
      L["%d of %d signals"],
      #lines,
      total + dropped.capital + dropped.time + dropped.profession + dropped.expired
    ),
  }
  if dropped.capital > 0 then
    parts[#parts + 1] = string.format(L["%d need more capital"], dropped.capital)
  end
  if dropped.time > 0 then
    parts[#parts + 1] = string.format(L["%d need more time"], dropped.time)
  end
  if dropped.profession > 0 then
    parts[#parts + 1] = string.format(L["%d need a profession"], dropped.profession)
  end
  parts[#parts + 1] =
    string.format(L["capital %s, %d min"], B.UI.MoneyShort(ctx.capital or 0), ctx.minutes or 0)
  return roots, table.concat(parts, " - ")
end

local function spotRows()
  local all = Spots.All()
  local list = {}
  for _, s in ipairs(all) do
    local keep = filterItem == nil
    for _, it in ipairs(s.items or {}) do
      if it[1] == filterItem then
        keep = true
      end
    end
    if keep then
      list[#list + 1] = s
    end
  end
  table.sort(list, function(a, b)
    local ga, gb = Spots.GoldPerHour(a) or -1, Spots.GoldPerHour(b) or -1
    if ga ~= gb then
      return ga > gb
    end
    return a.name < b.name
  end)
  local rows = {}
  for _, s in ipairs(list) do
    local gph = Spots.GoldPerHour(s)
    rows[#rows + 1] = {
      id = "spot:" .. s.id,
      ref = "spot:" .. s.id,
      text = s.name .. "  " .. S.H.muted .. (B:Entity("spot:" .. s.id):Summary() or "") .. "|r",
      value = gph,
      valueKind = gph and "money" or nil,
      children = B:GetDetailSections("spot:" .. s.id)[1] and B:GetDetailSections("spot:" .. s.id)[1].rows
        or nil,
      collapsed = true,
    }
  end
  if #rows == 0 then
    rows[1] = {
      text = S.H.muted
        .. (filterItem and L["No farm spot known for this item."] or L["No farm spots in the market data."])
        .. "|r",
      kind = "para",
    }
  end
  local text = string.format(L["%d farm spots"], #list)
  if filterItem then
    text = text
      .. " "
      .. L["for"]
      .. " "
      .. (B:Entity("item:" .. filterItem):Name() or ("item:" .. filterItem))
  end
  return rows, text
end

local function priceRows()
  if not filterItem then
    return {
      {
        text = S.H.muted .. L["Pick an item: right click it anywhere and choose Prices."] .. "|r",
        kind = "para",
      },
    },
      ""
  end
  local ref = "item:" .. filterItem
  local roots = {}
  for _, section in ipairs(B:GetDetailSections(ref)) do
    if section.id == "gold.price" or section.id == "gold.farm" then
      roots[#roots + 1] =
        { id = "section:" .. section.id, text = section.title, kind = "section", children = section.rows }
    end
  end
  return roots, B:Entity(ref):Name() or ref
end

-- The bag advisor (S4): three groups, post, vendor and keep, each item with its count, the
-- reason in grey and what the advised way brings in the value column.
local function bagRows()
  local items = ns.Advisor.BagItems()
  if #items == 0 then
    local empty = { { text = S.H.muted .. L["Your bags are empty."] .. "|r", kind = "para" } }
    return empty, L["Bags: nothing to advise"]
  end
  local groups = ns.Advisor.Build(items)
  local titles = {
    post = { L["Post on the auction house"], L["expected after the cut"] },
    vendor = { L["Sell to a vendor"], L["the vendor pays"] },
    keep = { L["Keep"], L["nothing to gain by selling"] },
  }
  local roots = {}
  for _, verdict in ipairs(ns.Advisor.VERDICTS) do
    local g = groups[verdict]
    if #g.items > 0 then
      local rows = {}
      for _, a in ipairs(g.items) do
        local it = a.item
        rows[#rows + 1] = {
          id = "bag:" .. tostring(it.bag) .. ":" .. tostring(it.slot),
          ref = "item:" .. it.itemID,
          icon = it.icon,
          text = it.name
            .. (it.count > 1 and (" x" .. it.count) or "")
            .. "  "
            .. S.H.muted
            .. a.reason
            .. "|r",
          value = a.total,
          valueKind = a.total and "money" or nil,
        }
      end
      roots[#roots + 1] = {
        id = "bags:" .. verdict,
        kind = "section",
        text = S.accent()
          .. string.upper(titles[verdict][1])
          .. "|r  "
          .. S.H.muted
          .. titles[verdict][2]
          .. "|r",
        value = g.total,
        valueKind = g.total and "money" or nil,
        children = rows,
      }
    end
  end
  local text = string.format(
    L["%d items: post %d, vendor %d, keep %d"],
    #items,
    #groups.post.items,
    #groups.vendor.items,
    #groups.keep.items
  )
  return roots, text
end

function W.Render()
  if not (win and win:IsShown()) then
    return
  end
  setTabs()
  local v = view()
  local rows, text
  if v == "spots" then
    rows, text = spotRows()
  elseif v == "price" then
    rows, text = priceRows()
  elseif v == "bags" then
    rows, text = bagRows()
  else
    rows, text = todayRows()
  end
  summary:SetText(text or "")
  tree:SetRows(rows)
end

function W.Schedule()
  if mod and win and win:IsShown() then
    mod:Coalesce("render", RENDER_DELAY, W.Render)
  end
end

-- A render only while that tab shows (the bag events are frequent).
function W.ScheduleIf(which)
  if view() == which then
    W.Schedule()
  end
end

local function build()
  win = B.UI.Window("BastiansGoldFrame", {
    title = L["Gold"],
    width = 520,
    height = 480,
    db = db().window,
    onShow = function()
      W.Render()
    end,
    onHide = function()
      ns.Advisor.WindowHidden() -- closed by hand: the shop's close must not close it again
    end,
    onResize = function()
      if tree then
        tree:Refresh()
      end
    end,
  })
  local content = win.content
  local x = 6
  for i, t in ipairs(TABS) do
    local b = S.button(content, L[t[2]], TAB_W, 22)
    b.tip = TAB_TIPS[t[1]]
    b:SetPoint("TOPLEFT", content, "TOPLEFT", x, -6)
    b.view = t[1]
    b:SetScript("OnClick", function()
      W.Open(t[1])
    end)
    tabs[i] = b
    x = x + TAB_W + 4
  end
  summary = S.text(content, 11, S.C.dim)
  summary:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -34)
  summary:SetPoint("TOPRIGHT", content, "TOPRIGHT", -8, -34)
  summary:SetHeight(14)
  hint = S.text(content, 10, S.C.dim)
  hint:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 8, 4)
  hint:SetText(L["Right click a line for its entity menu."])
  tree = B.UI.Tree(content, { db = db().tree, ctx = { source = "gold" } })
  tree.chips:ClearAllPoints()
  tree.chips:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -52)
  tree.chips:SetPoint("TOPRIGHT", content, "TOPRIGHT", -20, -52)
  tree.scroll:ClearAllPoints()
  tree.scroll:SetPoint("TOPLEFT", tree.chips, "BOTTOMLEFT", 0, -2)
  tree.scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -20, 18)
  W.win, W.tree, W.summary, W.tabs = win, tree, summary, tabs
end

-- Open a tab: "today", "spots" (arg = itemID or nil), "price" (arg = itemID), "bags".
function W.Open(which, arg)
  if not (mod and mod:IsEnabled()) then
    return false
  end
  if not win then
    build()
  end
  if which then
    db().view = which
  end
  if which == "spots" or which == "price" then
    filterItem = arg
  end
  if win:IsShown() then
    W.Render()
  else
    win:Show()
  end
  return true
end

function W.Toggle()
  if win and win:IsShown() then
    win:Hide()
  else
    W.Open()
  end
end

function W.Hide()
  if win then
    win:Hide()
  end
end

function W.IsShown()
  return win ~= nil and win:IsShown()
end

function W.Register(self)
  mod = self
  self:On("BASTIANS_DATA_LOADED", W.Schedule)
  self:On("BASTIANS_THEME_CHANGED", W.Schedule) -- the colour codes of the rows (ST3)
  self:RegisterEvent("PLAYER_MONEY", function()
    ns.Income.OnMoney() -- the day's income first (R9; one handler per event per module)
    W.Schedule()
  end)
end
