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

local TABS = {
  { "today", "Today" },
  { "spots", "Farm spots" },
  { "price", "Price" },
  { "bags", "Bags" },
  { "ledger", "Ledger" },
}
-- what each tab shows, after the hover delay
local TAB_TIPS = {
  today = L["Your income today and this week, and what the market does."],
  spots = L["Farm spots and strategies with gold per hour."],
  price = L["The price of an item: auction house, vendor, history."],
  bags = L["What to sell, post or keep from your bags."],
  ledger = L["What you bought and sold, and when the market runs high."],
}
-- the tabs' pictograms (ADR 0046): income, farm spots, the price of an item, the bags
local TAB_ICONS = { today = "gold", spots = "spot", price = "ledger", bags = "item", ledger = "note" }
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

local function prices()
  return B:GetService("prices")
end

-- The signals of the player's market from the Market pack, as records with their ids.
local function marketSignals()
  return ns.Signals.Market()
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
    b:SetOn(b.view == view()) -- the look draws the chosen tab (ADR 0046)
  end
end

-- The income block: gold per day, AH apart from loot, the
-- account's total with a line per character, today and the last seven days.
-- "AH 25s, loot 1g 80s, spent 1g 30s"
local function incomeWords(b)
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

local function incomeRows()
  local Income = ns.Income
  local today = Income.Day() or { ah = 0, loot = 0, spent = 0, chars = {} }
  local week = Income.Total(7)
  local words = incomeWords
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
      text = s.name
        .. "  "
        .. S.H.muted
        .. (B:Entity("spot:" .. s.id):Summary() or "")
        .. Spots.Away(s)
        .. "|r",
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

-- The ledger: the book by item, then the market's hours (gold.md "The ledger").
local function ledgerRows()
  local roots, text = ns.Ledger.Tree()
  local hours = ns.History.HourRows()
  if #hours > 0 then
    roots[#roots + 1] = {
      id = "ledger:hours",
      kind = "section",
      text = S.accent() .. string.upper(L["When the market runs high"]) .. "|r",
      children = hours,
    }
  end
  return roots, text
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
  elseif v == "ledger" then
    rows, text = ledgerRows()
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
    module = "Gold", -- the options button opens this page (R27.1)
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
    local b = S.action(content, { icon = TAB_ICONS[t[1]], label = L[t[2]], boxed = true })
    b.tip = TAB_TIPS[t[1]]
    b:SetPoint("TOPLEFT", content, "TOPLEFT", x, -6)
    b.view = t[1]
    b:SetScript("OnClick", function()
      W.Open(t[1])
    end)
    tabs[i] = b
    x = x + b:GetWidth() + 4
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

-- Open a tab: "today", "spots" (arg = itemID or nil), "price" (arg = itemID), "bags", "ledger".
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
    win:Show() -- to the front
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

-- Gold's Overview on the Atlas (ADR 0058, PH4): the income per day, the farm spots here.
function W.OverviewRows()
  local rows = { incomeRows() }
  local map = B.Coords.PlayerMap()
  local list = map and ns.Spots.HereList(map) or {}
  if #list > 0 then
    local children = {}
    for _, it in ipairs(list) do
      children[#children + 1] = {
        id = "overview:spot:" .. it.s.id,
        ref = "spot:" .. it.s.id,
        text = it.s.name .. "  " .. S.H.muted .. ns.Spots.Words(it.s) .. "|r",
      }
    end
    rows[#rows + 1] = {
      id = "overview:spots",
      kind = "section",
      text = S.accent() .. string.upper(L["Farm spots here"]) .. "|r",
      children = children,
    }
  end
  return rows
end

-- The stat tiles (ADR 0058, PH4): Gold's four on its Overview, the best spot here on Here.
local function registerStats(self)
  local Income = ns.Income
  local INCOME = { "BASTIANS_GOLD_INCOME" }
  B:RegisterStat(self, {
    id = "gold.stat.money",
    rail = "gold",
    order = 10,
    title = L["Gold on hand"],
    invalidateOn = INCOME,
    build = function()
      local money = B.Compat.GetMoney()
      return { value = money and B.UI.Money(money) or nil }
    end,
  })
  B:RegisterStat(self, {
    id = "gold.stat.income",
    rail = "gold",
    order = 20,
    title = L["Income"],
    invalidateOn = INCOME,
    build = function()
      local t = Income.Day() or { ah = 0, loot = 0, spent = 0 }
      return { value = B.UI.Money((t.ah or 0) + (t.loot or 0)), note = L["Today"] .. ": " .. incomeWords(t) }
    end,
  })
  B:RegisterStat(self, {
    id = "gold.stat.spent",
    rail = "gold",
    order = 30,
    title = L["Spent"],
    invalidateOn = INCOME,
    build = function()
      local t = Income.Day() or { spent = 0 }
      return { value = B.UI.Money(t.spent or 0), note = L["Today"] }
    end,
  })
  B:RegisterStat(self, {
    id = "gold.stat.week",
    rail = "gold",
    order = 40,
    title = L["Last 7 days"],
    invalidateOn = INCOME,
    build = function()
      local w = Income.Total(7)
      local net = (w.ah or 0) + (w.loot or 0) - (w.spent or 0)
      return { value = (net < 0 and "-" or "") .. B.UI.Money(math.abs(net)), note = incomeWords(w) }
    end,
  })
  B:RegisterStat(self, {
    id = "gold.stat.spot",
    rail = "here",
    order = 40,
    title = L["Best spot here"],
    invalidateOn = { "BASTIANS_PRICES_UPDATED", "BASTIANS_PLAYER_MOVED_ZONE", "BASTIANS_DATA_LOADED" },
    build = function()
      local map = B.Coords.PlayerMap()
      local best = map and ns.Spots.HereList(map)[1] or nil
      if not best then
        return nil -- no spot on this zone: no tile
      end
      return {
        value = best.gph and (B.UI.Money(best.gph) .. "/h") or nil, -- no market: unknown, not 0
        note = best.s.name,
        ref = "spot:" .. best.s.id,
      }
    end,
  })
end

function W.Register(self)
  mod = self
  self:On("BASTIANS_DATA_LOADED", W.Schedule)
  self:On("BASTIANS_GRAPH_TIMES", W.Schedule) -- the spots' travel times (W8)
  self:On("BASTIANS_THEME_CHANGED", W.Schedule) -- the colour codes of the rows (ST3)
  B:DeclareMessage("BASTIANS_GOLD_INCOME") -- the day's income moved (the stat tiles, the Overview)
  self:RegisterEvent("PLAYER_MONEY", function()
    ns.Income.OnMoney() -- the day's income first (R9; one handler per event per module)
    self:Fire("BASTIANS_GOLD_INCOME")
    W.Schedule()
  end)
  registerStats(self)
  B:RegisterView(self, {
    id = "gold.overview",
    title = L["Overview"],
    group = L["Gold"],
    rail = "gold", -- the Atlas's rail entry, its first tab (ADR 0058)
    first = true,
    order = 1,
    invalidateOn = {
      "BASTIANS_GOLD_INCOME",
      "BASTIANS_PRICES_UPDATED",
      "BASTIANS_PLAYER_MOVED_ZONE",
      "BASTIANS_GRAPH_TIMES",
    },
    render = function(host)
      host:SetRows(W.OverviewRows())
      host:SetSummary(L["gold per day"])
    end,
  })
  -- Bags (ADR 0058, PH6; A5.4): one answer per bag item with the reason; a tab of Gold
  B:RegisterView(self, {
    id = "gold.bags",
    title = L["Bags"],
    group = L["Gold"],
    rail = "gold",
    order = 60,
    invalidateOn = { "BASTIANS_PRICES_UPDATED", "BASTIANS_ALTS_CHANGED", "BASTIANS_GOLD_INCOME" },
    render = function(host)
      local rows, words = W.BagAnswerRows()
      host:SetRows(rows)
      host:SetSummary(words)
    end,
  })
end

-- The rows of the Bags view (ADR 0058, PH6): a tile per bag slot, the answer as its badge, the
-- reason under the name, what the way brings as the value. -> rows, the summary line.
local ANSWER_WORDS =
  { sell = "Sell", auction = "Auction", disenchant = "Disenchant", mail = "Mail to %s", keep = "Keep" }

function W.BagAnswerRows()
  local answers = ns.Advisor.Answers()
  if #answers == 0 then
    return { { text = S.H.muted .. L["Your bags are empty."] .. "|r", kind = "para" } },
      L["Bags: nothing to advise"]
  end
  local rows, counts = {}, {}
  for _, a in ipairs(answers) do
    local it = a.item
    counts[a.answer] = (counts[a.answer] or 0) + 1
    local word = a.answer == "mail" and string.format(L[ANSWER_WORDS.mail], a.to or "?")
      or L[ANSWER_WORDS[a.answer]]
    rows[#rows + 1] = {
      id = "bag:" .. tostring(it.bag) .. ":" .. tostring(it.slot),
      ref = "item:" .. it.itemID,
      icon = it.icon,
      text = it.name .. (it.count > 1 and (" x" .. it.count) or ""),
      meta = a.reason,
      badge = word,
      answer = a.answer,
      value = a.total,
      valueKind = a.total and "money" or nil,
    }
  end
  local words = string.format(
    L["%d items: %d to sell, %d to auction, %d to disenchant, %d to mail"],
    #answers,
    counts.sell or 0,
    counts.auction or 0,
    counts.disenchant or 0,
    counts.mail or 0
  )
  return rows, words
end
