-- Farm spots and strategies (gold.md): entity types `spot` and `strategy` from the Market pack, the
-- map layer gold.farmspots with a gold-per-hour estimate from current prices and the claim's
-- evidence, the sections "Strategy" (spot) and "Where to farm" (item), the search provider and the
-- actions gold.farm and gold.prices. Everything answers from memory; unknown prices are left out of
-- the estimate and the estimate says so.
local _, ns = ...
local B = Bastians
local S = B.UI.Style
ns.L = ns.L or B.NewLocale()
local L = ns.L

local Spots = {}
ns.Spots = Spots

local STATUS_COLOR = {
  verified = S.C.good,
  unverified = S.C.neutral,
  refuted = S.C.bad,
}

local function data()
  return B:GetService("data")
end

local function prices()
  return B:GetService("prices")
end

local function spot(id)
  local d = data()
  return d and d:Get("spot", id) or nil
end

local function strategy(id)
  local d = data()
  return d and d:Get("strategy", id) or nil
end

local function itemName(itemID)
  return B:Entity("item:" .. itemID):Name() or (L["Item"] .. " " .. tostring(itemID))
end

-- Gold per hour from the spot's items per hour and the current prices. Returns copper (or nil when
-- no item has a price) and how many items had no price.
function Spots.GoldPerHour(s)
  local service = prices()
  local total, known, unknown = 0, 0, 0
  for _, it in ipairs(s.items or {}) do
    local p = service and service:Price(it[1]) or nil
    local price = p and p.median or nil
    if price then
      total = total + price * (it[2] or 0)
      known = known + 1
    else
      unknown = unknown + 1
    end
  end
  if known == 0 then
    return nil, unknown
  end
  return math.floor(total), unknown
end

-- "12g/h (1 item without price)" or "gold/h unknown"
function Spots.GoldPerHourText(s)
  local gph, unknown = Spots.GoldPerHour(s)
  if not gph then
    return L["gold/h unknown"]
  end
  local text = B.UI.MoneyShort(gph) .. "/h"
  if unknown > 0 then
    text = text .. " " .. string.format(L["(%d items without price)"], unknown)
  end
  return text
end

-- "verified (3 channels, reach 12,000)" from the strategy behind a spot.
local function evidence(s)
  local st = s.strategy and strategy(s.strategy) or nil
  local status = L[s.status or "unverified"]
  if not st then
    return status
  end
  local parts = { status }
  if st.weight then
    parts[#parts + 1] = string.format(st.weight == 1 and L["%d channel"] or L["%d channels"], st.weight)
  end
  if st.reach then
    parts[#parts + 1] = string.format(L["reach %d"], st.reach)
  end
  return table.concat(parts, ", ")
end

local function allSpots()
  local d = data()
  local ids = d and d:Index("spot.all") or {}
  local out = {}
  for _, id in ipairs(ids) do
    local s = spot(id)
    if s then
      out[#out + 1] = s
    end
  end
  return out
end
Spots.All = allSpots

-- ---------------------------------------------------------------------------------------------
-- Entity types
-- ---------------------------------------------------------------------------------------------

local function registerEntities(mod)
  B:RegisterEntityType(mod, {
    type = "spot",
    priority = 100,
    name = function(id)
      local s = spot(id)
      return s and s.name or nil
    end,
    icon = function()
      return B.UI.IconTexture("spot")
    end,
    summary = function(id)
      local s = spot(id)
      if not s then
        return nil
      end
      local parts = {}
      if s.levelMin and s.levelMax then
        parts[#parts + 1] = L["level"] .. " " .. s.levelMin .. "-" .. s.levelMax
      end
      parts[#parts + 1] = Spots.GoldPerHourText(s)
      parts[#parts + 1] = evidence(s)
      return table.concat(parts, ", ")
    end,
    locations = function(id)
      local s = spot(id)
      if not (s and s.map and s.x) then
        return {}
      end
      return { { map = s.map, x = s.x, y = s.y, kind = "spot", src = s.src } }
    end,
    fields = spot,
  })
  B:RegisterEntityType(mod, {
    type = "strategy",
    priority = 100,
    name = function(id)
      local st = strategy(id)
      return st and st.subject or nil
    end,
    icon = function()
      return B.UI.IconTexture("gold")
    end,
    summary = function(id)
      local st = strategy(id)
      if not st then
        return nil
      end
      local parts = { L[st.kind or "claim"], L[st.status or "unverified"] }
      if st.weight then
        parts[#parts + 1] = string.format(st.weight == 1 and L["%d channel"] or L["%d channels"], st.weight)
      end
      return table.concat(parts, ", ")
    end,
    locations = function(id)
      local st = strategy(id)
      if not (st and st.map and st.x) then
        return {}
      end
      return { { map = st.map, x = st.x, y = st.y, kind = "strategy", src = st.src } }
    end,
    fields = strategy,
  })
end

-- ---------------------------------------------------------------------------------------------
-- Layer
-- ---------------------------------------------------------------------------------------------

local function spotPins(view)
  local pins = {}
  for _, s in ipairs(allSpots()) do
    if s.map and s.x then
      local continent, wx, wy = B.Coords.ToWorld(s.map, s.x, s.y)
      if
        continent == view.continent
        and wx >= view.x1
        and wx <= view.x2
        and wy >= view.y1
        and wy <= view.y2
      then
        local gph = Spots.GoldPerHour(s)
        pins[#pins + 1] = {
          ref = "spot:" .. s.id,
          wx = wx,
          wy = wy,
          icon = B.UI.IconTexture("spot"),
          color = STATUS_COLOR[s.status] or STATUS_COLOR.unverified,
          label = s.name .. (gph and (" (" .. B.UI.MoneyShort(gph) .. "/h)") or ""),
          priority = 55,
          cluster = true,
          radius = s.radius,
          status = s.status,
          goldPerHour = gph,
        }
      end
    end
  end
  return pins
end

-- ---------------------------------------------------------------------------------------------
-- Sections
-- ---------------------------------------------------------------------------------------------

local function spotRows(ref)
  local _, id = B.Entity.Parse(ref)
  local s = spot(id)
  if not s then
    return nil
  end
  local rows = {}
  local gph, unknown = Spots.GoldPerHour(s)
  rows[#rows + 1] = {
    text = L["Gold per hour"]
      .. (unknown > 0 and (" " .. string.format(L["(%d items without price)"], unknown)) or ""),
    value = gph,
    valueKind = gph and "money" or nil,
  }
  local service = prices()
  for _, it in ipairs(s.items or {}) do
    local p = service and service:Price(it[1]) or nil
    rows[#rows + 1] = {
      text = itemName(it[1]) .. string.format(" x%s/h", tostring(it[2])),
      ref = "item:" .. it[1],
      value = p and p.median and math.floor(p.median * (it[2] or 0)) or nil,
      valueKind = "money",
    }
  end
  if s.levelMin and s.levelMax then
    rows[#rows + 1] = { text = L["Level"] .. " " .. s.levelMin .. "-" .. s.levelMax }
  end
  rows[#rows + 1] = { text = L["Evidence"] .. ": " .. evidence(s), color = STATUS_COLOR[s.status] }
  local st = s.strategy and strategy(s.strategy) or nil
  if st then
    local when = st.lastSeen and type(date) == "function" and date("!%Y-%m-%d", st.lastSeen) or nil
    rows[#rows + 1] = {
      text = st.subject
        .. (when and ("  " .. L["last seen"] .. " " .. when) or "")
        .. (st.build and ("  " .. st.build) or ""),
      ref = "strategy:" .. st.id,
    }
  end
  return rows
end

local function whereToFarmRows(ref)
  local _, itemID = B.Entity.Parse(ref)
  local d = data()
  local ids = d and type(itemID) == "number" and d:Index("spot.byItem", itemID) or nil
  if not ids or #ids == 0 then
    return nil
  end
  local rows = {}
  for _, id in ipairs(ids) do
    local s = spot(id)
    if s then
      local gph = Spots.GoldPerHour(s)
      rows[#rows + 1] = {
        text = s.name .. "  " .. S.H.muted .. evidence(s) .. "|r",
        ref = "spot:" .. s.id,
        value = gph,
        valueKind = gph and "money" or nil,
      }
    end
  end
  return rows
end

-- ---------------------------------------------------------------------------------------------
-- Search, actions, wiring
-- ---------------------------------------------------------------------------------------------

function Spots.Register(mod)
  registerEntities(mod)
  B:RegisterMapLayer(mod, {
    id = "gold.farmspots",
    label = L["Farm spots"],
    defaultOn = true,
    minLevel = 1,
    query = spotPins,
  })
  B:RegisterDetailSection(mod, {
    id = "gold.strategy",
    title = L["Strategy"],
    types = { "spot" },
    order = 15,
    invalidateOn = { "BASTIANS_PRICES_UPDATED" },
    build = spotRows,
  })
  B:RegisterDetailSection(mod, {
    id = "gold.farm",
    title = L["Where to farm"],
    types = { "item" },
    order = 26,
    block = { limit = 8 }, -- the dossier block (C2)
    invalidateOn = { "BASTIANS_PRICES_UPDATED" },
    build = whereToFarmRows,
    tooltip = { max = 1 },
  })
  -- "Best spot here" (the Here column, C4): the farm spots on the player's zone, the richest first
  B:RegisterDetailSection(mod, {
    id = "gold.here.spot",
    title = L["Best spot here"],
    types = { "zone" },
    order = 98,
    here = { order = 4, limit = 3, only = true },
    invalidateOn = { "BASTIANS_PRICES_UPDATED" },
    build = function(ref)
      local _, map = B.Entity.Parse(ref)
      map = tonumber(map)
      local list = {}
      for _, s in ipairs(allSpots()) do
        if s.map == map then
          local gph = Spots.GoldPerHour(s)
          list[#list + 1] = { s = s, gph = gph }
        end
      end
      if #list == 0 then
        return nil
      end
      table.sort(list, function(a, b)
        if (a.gph or -1) ~= (b.gph or -1) then
          return (a.gph or -1) > (b.gph or -1)
        end
        return a.s.name < b.s.name
      end)
      local rows = {}
      for _, it in ipairs(list) do
        rows[#rows + 1] = {
          id = "here:spot:" .. it.s.id,
          ref = "spot:" .. it.s.id,
          text = it.s.name .. "  " .. S.H.muted .. evidence(it.s) .. "|r",
        }
      end
      return rows
    end,
  })
  -- the "best spot" link (C2): the farm spot with the highest gold per hour, else the first known
  B:RegisterDetailSection(mod, {
    id = "gold.bestspot",
    title = L["Best spot"],
    types = { "item" },
    order = 60,
    link = L["best spot"],
    invalidateOn = { "BASTIANS_PRICES_UPDATED" },
    build = function(ref)
      local rows = whereToFarmRows(ref)
      if not rows then
        return nil
      end
      local best = rows[1]
      for _, row in ipairs(rows) do
        if row.value and (not best.value or row.value > best.value) then
          best = row
        end
      end
      return { best }
    end,
  })
  B:RegisterSearchProvider(mod, {
    id = "gold.spots",
    label = L["Farm spots and strategies"],
    priority = 60,
    search = function(query, limit)
      local out = {}
      local function add(ref, name, note)
        local low = string.lower(name)
        local score
        if low == query then
          score = 1
        elseif string.sub(low, 1, #query) == query then
          score = 0.9
        elseif string.find(low, query, 1, true) then
          score = 0.7
        end
        if score and #out < (limit or 50) then
          out[#out + 1] = { ref = ref, label = name, score = score, note = note }
        end
      end
      for _, s in ipairs(allSpots()) do
        add("spot:" .. s.id, s.name, L["farm spot"])
      end
      local d = data()
      for _, id in ipairs(d and d:Index("strategy.all") or {}) do
        local st = strategy(id)
        if st then
          add("strategy:" .. id, st.subject, L["strategy"])
        end
      end
      return out
    end,
  })
  B:RegisterAction(mod, {
    id = "gold.farm",
    label = L["Where to farm"],
    icon = B.UI.IconTexture("spot"),
    types = { "item" },
    order = 51,
    when = function(ref)
      local _, itemID = B.Entity.Parse(ref)
      local d = data()
      local ids = d and type(itemID) == "number" and d:Index("spot.byItem", itemID) or nil
      return ids ~= nil and #ids > 0
    end,
    run = function(ref)
      local _, itemID = B.Entity.Parse(ref)
      ns.Window.Open("spots", itemID)
    end,
  })
  B:RegisterAction(mod, {
    id = "gold.prices",
    label = L["Prices"],
    icon = B.UI.IconTexture("gold"),
    types = { "item" },
    order = 50,
    when = function(ref)
      local _, itemID = B.Entity.Parse(ref)
      local service = prices()
      return service ~= nil and service:Price(itemID) ~= nil
    end,
    run = function(ref)
      local _, itemID = B.Entity.Parse(ref)
      ns.Window.Open("price", itemID)
    end,
  })
  mod:On("BASTIANS_PRICES_UPDATED", function(me)
    me:Fire("BASTIANS_LAYER_CHANGED", "gold.farmspots") -- the gold-per-hour labels moved
    ns.Window.Schedule()
  end)
end
