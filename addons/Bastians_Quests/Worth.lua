-- Bastian's Quests: what a quest is worth (quests.md "Worth", C3): money, XP, reputation, the best
-- reward's value (AH median when a prices service knows it, the vendor sell price else) and what
-- it unlocks, as one line for the band and the rows. Pure: plain tables in, a plain table out.
-- Unknown stays unknown ("reward price unknown"), never 0.
local _, ns = ...
local B = Bastians
local L = ns.L

local Worth = {}
ns.Worth = Worth

-- The best of the reward items by value: AH price first, vendor sell else; counts how many items
-- had no price at all. ctx.price(itemID) and ctx.sell(itemID) give copper or nil.
local function bestReward(rw, ctx)
  local best, unknown = nil, 0
  local function consider(list)
    for _, it in ipairs(list or {}) do
      local itemID, count = it[1], it[2] or 1
      local copper = ctx.price and ctx.price(itemID) or nil
      local kind = copper and "ah" or nil
      if not copper then
        copper = ctx.sell and ctx.sell(itemID) or nil
        kind = copper and "vendor" or nil
      end
      if copper and copper > 0 then
        local value = copper * count
        if not best or value > best.copper then
          best = { copper = value, kind = kind, itemID = itemID }
        end
      elseif not copper then
        unknown = unknown + 1
      end -- a known zero (no vendor value) is neither a reward worth naming nor unknown
    end
  end
  consider(rw.items)
  consider(rw.choices)
  return best, unknown
end

-- Worth.quest(q, ctx) -> { text, copper, xp } for a known quest record (rewards: money, xp,
-- rep = { { factionID, value } }, items and choices = { { itemID, count } }); nil for no record.
-- ctx = { price = fn(itemID), sell = fn(itemID), factionName = fn(factionID), unlocks = n }.
function Worth.quest(q, ctx)
  if not q then
    return nil
  end
  ctx = ctx or {}
  local rw = q.rewards or {}
  local parts, copper, xp = {}, nil, nil
  if rw.money and rw.money > 0 then
    parts[#parts + 1] = B.UI.Money(rw.money)
    copper = rw.money
  end
  if rw.xp and rw.xp > 0 then
    parts[#parts + 1] = tostring(rw.xp) .. " " .. L["XP"]
    xp = rw.xp
  end
  for _, rep in ipairs(rw.rep or {}) do
    local value = rep[2] or 0
    if value ~= 0 then
      local name = ctx.factionName and ctx.factionName(rep[1]) or nil
      parts[#parts + 1] = (value > 0 and "+" or "")
        .. value
        .. " "
        .. (name or (L["faction"] .. " " .. rep[1]))
    end
  end
  local best, unknown = bestReward(rw, ctx)
  if best then
    local text = string.format(L["reward %s"], B.UI.Money(best.copper))
    if best.kind == "vendor" then
      text = text .. " " .. L["(vendor)"]
    end
    parts[#parts + 1] = text
    copper = (copper or 0) + best.copper
  elseif unknown > 0 then
    parts[#parts + 1] = L["reward price unknown"]
  end
  if ctx.unlocks and ctx.unlocks > 0 then
    parts[#parts + 1] = string.format(L["unlocks %d"], ctx.unlocks)
  end
  if #parts == 0 then
    return { text = L["worth unknown"] }
  end
  return { text = table.concat(parts, " - "), copper = copper, xp = xp }
end

-- The stat name the client shows for an ITEM_MOD_* key, else the key in words ("Crit rating").
local function statWords(key)
  local words = string.gsub(string.gsub(key, "^ITEM_MOD_", ""), "_SHORT$", "")
  words = string.lower(string.gsub(words, "_", " "))
  return (string.gsub(words, "^%l", string.upper))
end

local MAX_STATS = 4

-- Worth.choices(choices, ctx) -> one comparison per reward choice, in the given order (S7,
-- browser.md "Item comparison of quest reward choices"): what the client knows of the item (kind,
-- level, the biggest stats), its value (AH median x count when known, else the vendor sell price
-- x count), what the player wears where it would go, and the verdicts: `best` on the one choice
-- worth the most when every choice has a value, `upgrade` true / false against the worn item's
-- level (true for an empty slot), nil when the item is not equippable. Items the client has not
-- loaded carry `loaded = false` and say so. Pure: ctx = { name(itemID), info(itemID) (the
-- Compat.GetItemInfo shape), stats(itemID), equipped(equipLoc) (the Compat.GetEquippedItem
-- shape), price(itemID), sell(itemID), statName(key) }.
function Worth.choices(choices, ctx)
  ctx = ctx or {}
  local out = {}
  local priced, maxValue, maxCount = 0, nil, 0
  for i, entry in ipairs(choices or {}) do
    local itemID, count = entry[1], entry[2] or 1
    local info = ctx.info and ctx.info(itemID) or nil
    local c = { itemID = itemID, count = count, loaded = info ~= nil, stats = {} }
    c.name = (ctx.name and ctx.name(itemID)) or (info and info.name) or (L["Item"] .. " " .. itemID)
    c.icon = info and info.icon or nil
    local copper = ctx.price and ctx.price(itemID) or nil
    local kind = copper and "ah" or nil
    if not copper then
      copper = ctx.sell and ctx.sell(itemID) or nil
      kind = copper and "vendor" or nil
    end
    if copper and copper > 0 then
      c.value = { copper = copper * count, kind = kind }
      priced = priced + 1
      if not maxValue or c.value.copper > maxValue then
        maxValue, maxCount = c.value.copper, 1
      elseif c.value.copper == maxValue then
        maxCount = maxCount + 1
      end
    end
    if info then
      c.level = info.level
      c.kind = info.subclass
      c.equipLoc = info.equipLoc
      for key, amount in pairs((ctx.stats and ctx.stats(itemID)) or {}) do
        c.stats[#c.stats + 1] = {
          key = key,
          name = (ctx.statName and ctx.statName(key)) or statWords(key),
          amount = amount,
        }
      end
      table.sort(c.stats, function(a, b)
        if a.amount ~= b.amount then
          return a.amount > b.amount
        end
        return a.key < b.key
      end)
      local worn = info.equipLoc and info.equipLoc ~= "" and ctx.equipped and ctx.equipped(info.equipLoc)
        or nil
      if worn then
        c.worn = worn
        if worn.id then
          c.delta = (c.level or 0) - (worn.level or 0)
          c.upgrade = c.delta > 0
        else
          c.upgrade = true -- the slot is empty: the item fills it
        end
      end
    end
    out[i] = c
  end
  local all = #out
  for _, c in ipairs(out) do
    c.best = priced == all and all > 1 and maxCount == 1 and c.value ~= nil and c.value.copper == maxValue
      or nil
    -- the words: the title with its tag, the meta line (kind, level, stats; the worn item; the
    -- price's source)
    c.title = c.name .. (c.count > 1 and (" x" .. c.count) or "")
    local tags = {}
    if c.best then
      tags[#tags + 1] = L["best value"]
    end
    if c.upgrade == true then
      tags[#tags + 1] = (c.worn and c.worn.id) and L["upgrade"] or L["fills an empty slot"]
    elseif c.upgrade == false then
      tags[#tags + 1] = L["no upgrade"]
    end
    c.tag = #tags > 0 and table.concat(tags, ", ") or nil
    c.tagGood = (c.best or c.upgrade == true) and true or false
    local parts = {}
    if not c.loaded then
      parts[#parts + 1] = L["not loaded by the client yet"]
    else
      if c.kind and c.kind ~= "" then
        parts[#parts + 1] = c.kind
      end
      if c.level and c.level > 0 and c.worn then
        parts[#parts + 1] = string.format(L["item level %d"], c.level)
      end
      for i = 1, math.min(MAX_STATS, #c.stats) do
        local s = c.stats[i]
        parts[#parts + 1] = (s.amount > 0 and "+" or "") .. s.amount .. " " .. s.name
      end
      if c.worn and c.worn.id then
        parts[#parts + 1] = string.format(
          L["you wear %s (item level %d)"],
          c.worn.name or (L["Item"] .. " " .. c.worn.id),
          c.worn.level or 0
        )
      elseif c.worn then
        parts[#parts + 1] = L["the slot is empty"]
      end
    end
    if c.value then
      parts[#parts + 1] = c.value.kind == "ah" and L["AH median"] or L["vendor price"]
    else
      parts[#parts + 1] = L["price unknown"]
    end
    c.meta = table.concat(parts, ", ")
  end
  return out
end

-- The worth provider (core-contracts §4): quests, with the prices and data services when there.
function Worth.Register(mod)
  local Logic = ns.Logic
  mod.Worth = Worth -- for the tests
  B:RegisterWorth(mod, {
    types = { "quest" },
    invalidateOn = { "BASTIANS_PRICES_UPDATED", "BASTIANS_DATA_LOADED", "BASTIANS_QUESTS_CHANGED" },
    worth = function(ref)
      local _, id = B.Entity.Parse(ref)
      local q = type(id) == "number" and Logic.quest(id) or nil
      if not q then
        return nil
      end
      local prices = B:GetService("prices")
      local data = B:GetService("data")
      return Worth.quest(q, {
        price = function(itemID)
          local p = prices and prices:Price(itemID) or nil
          return p and p.median or nil
        end,
        sell = function(itemID)
          local r = data and data:Get("item", itemID) or nil
          return r and r.sell or nil
        end,
        factionName = ns.Rows.factionName, -- the client's name, a side faction's (Horde, Alliance)
        unlocks = #Logic.next(id),
      })
    end,
  })
  -- The sorts of the Quests list (ADR 0016): the most XP, the largest reputation gain.
  local function questOf(ref)
    local _, id = B.Entity.Parse(ref)
    return type(id) == "number" and Logic.quest(id) or nil
  end
  B:RegisterFilter(mod, {
    id = "quests.xp",
    kind = "sort",
    types = { "quest" },
    label = L["Most XP"],
    value = function(ref)
      local q = questOf(ref)
      local xp = q and q.rewards and q.rewards.xp
      return xp and xp > 0 and xp or nil
    end,
    text = function(xp)
      return xp .. " " .. L["XP"]
    end,
  })
  B:RegisterFilter(mod, {
    id = "quests.rep",
    kind = "sort",
    types = { "quest" },
    label = L["Largest reputation"],
    value = function(ref)
      local q = questOf(ref)
      local best
      for _, rep in ipairs(q and q.rewards and q.rewards.rep or {}) do
        if rep[2] and rep[2] > 0 and (best == nil or rep[2] > best) then
          best = rep[2]
        end
      end
      return best
    end,
    text = function(value)
      return "+" .. value .. " " .. L["reputation"]
    end,
  })
end
