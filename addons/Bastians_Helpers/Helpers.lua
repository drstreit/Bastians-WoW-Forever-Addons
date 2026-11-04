-- Bastian's Helpers (helpers.md): the shared parts of the small helpers. The model (pure: plain
-- tables in and out, no WoW API), the notice strip that says what a helper did (never the chat),
-- the pause key, the never-sell and restock lists.
local _, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
local L = ns.L
local S = B.UI.Style

local Helpers = {}
ns.Helpers = Helpers

Helpers.NOTICE_SECONDS = 6 -- the strip stays this long
Helpers.DURABILITY_WARN = 0.2 -- the worst worn item below this fraction
Helpers.BAGS_WARN = 3 -- fewer free bag slots than this
Helpers.RECENT_MAX = 8 -- recipients remembered per character
Helpers.SEND_TO_MAX = 10 -- names in the mail's Send to column

-- ---------------------------------------------------------------------------------------------
-- The model
-- ---------------------------------------------------------------------------------------------

local Model = {}
Helpers.Model = Model

-- The stacks to sell: grey (quality 0), with a vendor price (not `noValue`), not on the
-- never-sell list. `priceOf(itemID)` is the unit vendor price or nil (unknown, sold anyway).
-- Rows { bag, slot, itemID, count, value } (value nil when the price is unknown).
function Model.Junk(slots, neverSell, priceOf)
  local out = {}
  for _, s in ipairs(slots or {}) do
    if s.itemID and s.quality == 0 and not s.noValue and not (neverSell and neverSell[s.itemID]) then
      local unit = priceOf and priceOf(s.itemID)
      out[#out + 1] = {
        bag = s.bag,
        slot = s.slot,
        itemID = s.itemID,
        count = s.count or 1,
        value = unit and unit * (s.count or 1) or nil,
      }
    end
  end
  return out
end

-- Who pays the repair: "guild", "self", "short" (not enough money) or nil (nothing to repair).
-- `r` is Compat.MerchantRepair()'s table; a guildMoney of nil is no limit.
function Model.Repair(r, money, useGuild)
  if not (r and r.canRepair and (r.cost or 0) > 0) then
    return nil
  end
  if useGuild and r.guild and (r.guildMoney == nil or r.guildMoney >= r.cost) then
    return "guild"
  end
  return (money or 0) >= r.cost and "self" or "short"
end

-- The purchases that top the restock list up: `want` { [itemID] = amount }, `have` { [itemID] =
-- count }, `offers` the merchant's items { index, itemID, stack, price (for `stack` units),
-- numAvailable (-1 unlimited, else stacks), maxStack }. Units come in the merchant's stack size,
-- a purchase at most `maxStack` units, all of them never more than `money`. Returns
-- { { index, itemID, count, cost } }.
function Model.Restock(want, have, offers, money)
  local out, done = {}, {}
  money = money or 0
  for _, o in ipairs(offers or {}) do
    local amount = o.itemID and want[o.itemID]
    if amount and not done[o.itemID] and o.price and o.price > 0 then
      done[o.itemID] = true
      local stack = math.max(1, o.stack or 1)
      local need = amount - ((have and have[o.itemID]) or 0)
      local stacks = need > 0 and math.ceil(need / stack) or 0
      if (o.numAvailable or -1) >= 0 then
        stacks = math.min(stacks, o.numAvailable)
      end
      stacks = math.min(stacks, math.floor(money / o.price))
      local per = math.max(1, math.floor((o.maxStack or stack) / stack)) -- stacks per purchase
      while stacks > 0 do
        local n = math.min(stacks, per)
        out[#out + 1] = { index = o.index, itemID = o.itemID, count = n * stack, cost = n * o.price }
        money = money - n * o.price
        stacks = stacks - n
      end
    end
  end
  return out
end

-- The cheapest other vendor of an item (issue #15): `here` the unit price paid, `offers`
-- { { npc, name, zone, price, stack } } from the packs' vendor lists. A unit price is known only
-- with the stack; an offer without one, or not cheaper, is left out (unknown is never cheaper).
-- -> { npc, name, zone, unit } or nil.
function Model.CheaperVendor(here, offers)
  local best
  for _, o in ipairs(offers or {}) do
    local unit = o.price and o.stack and o.stack > 0 and o.price / o.stack or nil
    if unit and here and unit < here then
      if not best or unit < best.unit or (unit == best.unit and tostring(o.name) < tostring(best.name)) then
        best = { npc = o.npc, name = o.name, zone = o.zone, unit = unit }
      end
    end
  end
  return best
end

-- The buyback indices that undo this visit's sales (`sold` { { itemID, count } }), highest first
-- (a buyback moves the later entries down). `buyback` is Compat.GetBuybackItems()'s array.
-- The kinds a mail rule names (#18, helpers.md "Mail rules"): the class and subclass the client
-- answers for an item (GetItemInfoInstant: classID, subclassID; Trade Goods = 7, Recipe = 9; the
-- retail family's numbers, assumed on Forever). `sub` nil takes the whole class.
Helpers.MAIL_KINDS = {
  { id = "herb", label = "Herbs", class = 7, sub = 9 },
  { id = "ore", label = "Metal and stone", class = 7, sub = 7 },
  { id = "leather", label = "Leather", class = 7, sub = 6 },
  { id = "cloth", label = "Cloth", class = 7, sub = 5 },
  { id = "meat", label = "Meat and fish", class = 7, sub = 8 },
  { id = "enchanting", label = "Enchanting materials", class = 7, sub = 12 },
  { id = "elemental", label = "Elemental", class = 7, sub = 10 },
  { id = "recipe", label = "Recipes", class = 9 },
}

-- What the mail rules would send now: { { kind, to, slots, count } } in the kinds' order, one per
-- kind with a rule and unbound stacks in the bags, never to me. `rules` = { [kind id] = name },
-- `classOf(itemID)` -> classID, subclassID or nil (unknown items are never sent).
function Model.MailBatches(slots, rules, kinds, classOf, me)
  local out = {}
  me = string.lower(me or "")
  for _, kind in ipairs(kinds) do
    local to = rules and rules[kind.id]
    if to and to ~= "" and string.lower(to) ~= me then
      local batch = { kind = kind, to = to, slots = {}, count = 0 }
      for _, slot in ipairs(slots or {}) do
        local class, sub = nil, nil
        if slot.itemID and not slot.bound then
          class, sub = classOf(slot.itemID)
        end
        if class == kind.class and (kind.sub == nil or sub == kind.sub) then
          batch.slots[#batch.slots + 1] = slot
          batch.count = batch.count + (slot.count or 1)
        end
      end
      if #batch.slots > 0 then
        out[#out + 1] = batch
      end
    end
  end
  return out
end

function Model.Undo(sold, buyback)
  local want = {}
  for _, s in ipairs(sold or {}) do
    local key = s.itemID .. ":" .. (s.count or 1)
    want[key] = (want[key] or 0) + 1
  end
  local out = {}
  for i = #(buyback or {}), 1, -1 do
    local b = buyback[i]
    local key = b.itemID .. ":" .. (b.count or 1)
    if (want[key] or 0) > 0 then
      want[key] = want[key] - 1
      out[#out + 1] = b.index
    end
  end
  return out
end

-- The next step of Take all over Compat.GetInboxMail()'s array: { index, what = "money" |
-- "items" }, or nil and why ("full" the bags, "done"). Cash-on-delivery mail is left alone.
function Model.NextMail(mails, free)
  for _, m in ipairs(mails or {}) do
    if (m.cod or 0) == 0 then
      if (m.money or 0) > 0 then
        return { index = m.index, what = "money" }
      elseif (m.items or 0) > 0 then
        if (free or 0) <= 0 then
          return nil, "full"
        end
        return { index = m.index, what = "items" }
      end
    end
  end
  return nil, "done"
end

-- How many mails Take all leaves for the player: cash on delivery.
function Model.CodLeft(mails)
  local n = 0
  for _, m in ipairs(mails or {}) do
    if (m.cod or 0) > 0 then
      n = n + 1
    end
  end
  return n
end

-- The names for the mail's Send to column: this account's other characters of the realm and
-- faction of `me` (by name), then the recent recipients not among them; `max` names at most.
function Model.Recipients(characters, meKey, recent, max)
  local me = characters and characters[meKey]
  local alts, seen = {}, {}
  for key, c in pairs(characters or {}) do
    if key ~= meKey and me and c.realm == me.realm and c.faction == me.faction and c.name then
      alts[#alts + 1] = c.name
    end
  end
  table.sort(alts)
  local out = {}
  local function add(name)
    if name and name ~= "" and not seen[string.lower(name)] and #out < (max or 10) then
      seen[string.lower(name)] = true
      out[#out + 1] = name
    end
  end
  if me and me.name then
    seen[string.lower(me.name)] = true
  end
  for _, name in ipairs(alts) do
    add(name)
  end
  for _, name in ipairs(recent or {}) do
    add(name)
  end
  return out
end

-- `recent` with `name` in front, once, `max` long.
function Model.Remember(recent, name, max)
  local out = { name }
  for _, n in ipairs(recent or {}) do
    if string.lower(n) ~= string.lower(name) and #out < (max or 8) then
      out[#out + 1] = n
    end
  end
  return out
end

-- The quest to pick from a gossip or greeting list: a finished one first, then an offered one.
-- `field` is the key that names it ("questID" for the gossip, "index" for the greeting).
-- Returns kind ("active" | "available"), the id; nil when there is none.
function Model.QuestPick(active, available, field)
  for _, q in ipairs(active or {}) do
    if q.complete then
      return "active", q[field]
    end
  end
  local first = available and available[1]
  if first then
    return "available", first[field]
  end
  return nil
end

-- The reward choice that pays the most at a vendor: index, value; nil when no price is known.
function Model.BestChoice(choices, priceOf)
  local best, value
  for _, c in ipairs(choices or {}) do
    local unit = c.itemID and priceOf(c.itemID)
    if unit and unit > 0 and (value == nil or unit * (c.count or 1) > value) then
      best, value = c.index, unit * (c.count or 1)
    end
  end
  return best, value
end

-- `amount` per hour over `seconds`; nil below a minute (no rate from a moment).
function Model.PerHour(amount, seconds)
  if not (amount and seconds) or seconds < 60 then
    return nil
  end
  return amount * 3600 / seconds
end

-- Seconds to the next level at `perHour` experience; nil without a rate.
function Model.ToLevel(left, perHour)
  if not (left and perHour) or perHour <= 0 then
    return nil
  end
  return left * 3600 / perHour
end

-- Experience gained between two readings { xp, max, level }: across a level the rest of the old
-- level and the new level's part.
function Model.XPGain(before, now)
  if not (before and now and before.xp and now.xp) then
    return 0
  end
  if now.level and before.level and now.level > before.level then
    return math.max(0, (before.max or before.xp) - before.xp) + now.xp
  end
  return math.max(0, now.xp - before.xp)
end

-- Whether a value just fell below the threshold (from at or above it, or from unknown).
function Model.Crossed(before, now, threshold)
  return now ~= nil and now < threshold and (before == nil or before >= threshold)
end

-- "1 h 12 min", "12 min", "less than a minute".
function Helpers.Duration(seconds)
  if not seconds then
    return nil
  end
  local m = math.floor(seconds / 60)
  if m < 1 then
    return L["less than a minute"]
  elseif m < 60 then
    return string.format(L["%d min"], m)
  end
  return string.format(L["%d h %d min"], math.floor(m / 60), m % 60)
end

-- ---------------------------------------------------------------------------------------------
-- The module's state (set by Module.lua)
-- ---------------------------------------------------------------------------------------------

function Helpers.Profile()
  return Helpers.mod.db.profile
end

function Helpers.On(key)
  local mod = Helpers.mod
  return mod ~= nil and mod:IsEnabled() and mod.db.profile[key] and true or false
end

function Helpers.Global()
  return Helpers.mod.db.global
end

function Helpers.Char()
  return Helpers.mod.db.char
end

-- The pause key held: every automation skips this visit.
function Helpers.Paused()
  return B.Compat.ModifierDown(Helpers.Profile().pauseKey or "shift")
end

function Helpers.Key()
  return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

-- The unit vendor price of an item, nil while unknown (CLAUDE.md §4.2).
function Helpers.SellPrice(itemID)
  local info = B.Compat.GetItemInfo(itemID)
  return info and info.sellPrice or nil
end

function Helpers.ItemName(itemID)
  local info = B.Compat.GetItemInfo(itemID)
  return (info and info.name) or B:Entity("item:" .. itemID):Name() or ("item " .. itemID)
end

-- ---------------------------------------------------------------------------------------------
-- The lists: never sell (the account), restock (this character)
-- ---------------------------------------------------------------------------------------------

function Helpers.NeverSell(itemID, on)
  Helpers.Global().neverSell[itemID] = on and true or nil
end

function Helpers.IsNeverSell(itemID)
  return Helpers.Global().neverSell[itemID] == true
end

-- Puts an item on the restock list with `amount` (nil: one stack of it; 0 or less removes it).
function Helpers.SetRestock(itemID, amount)
  if amount == nil then
    local info = B.Compat.GetItemInfo(itemID)
    amount = info and info.stack or 1
  end
  Helpers.Char().restock[itemID] = amount > 0 and amount or nil
  return Helpers.Char().restock[itemID]
end

-- The mail rules (#18): account-wide, a kind id -> the recipient's name; "" or nil removes it.
function Helpers.SetMailRule(kind, name)
  name = string.match(name or "", "^%s*(.-)%s*$")
  Helpers.Global().mailRules[kind] = name ~= "" and name or nil
  return Helpers.Global().mailRules[kind]
end

function Helpers.MailKind(id)
  for _, kind in ipairs(Helpers.MAIL_KINDS) do
    if kind.id == id then
      return kind
    end
  end
  return nil
end

-- The rules in words for the settings page, or nil without any.
function Helpers.MailRulesText()
  local parts = {}
  for _, kind in ipairs(Helpers.MAIL_KINDS) do
    local to = Helpers.Global().mailRules[kind.id]
    if to then
      parts[#parts + 1] = string.format(L["%s go to %s"], L[kind.label], to)
    end
  end
  return #parts > 0 and table.concat(parts, "; ") or nil
end

function Helpers.Restock(itemID)
  return Helpers.Char().restock[itemID]
end

-- ---------------------------------------------------------------------------------------------
-- The notice strip: one line near the top of the screen, at most one button
-- ---------------------------------------------------------------------------------------------

local strip
local shownAt = 0
Helpers.HISTORY = 8
Helpers.history = {} -- the session's notices, newest first (the feed's tooltip)

local function buildStrip()
  strip = CreateFrame("Frame", "BastiansHelpersNotice", UIParent)
  strip:SetSize(460, 30)
  strip:SetPoint("TOP", UIParent, "TOP", 0, -160)
  strip:SetFrameStrata("HIGH")
  S.panel(strip, S.C.panel)
  strip.text = S.text(strip, 12, S.C.text)
  strip.text:SetPoint("LEFT", strip, "LEFT", 10, 0)
  strip.text:SetPoint("RIGHT", strip, "RIGHT", -86, 0)
  strip.text:SetWordWrap(false)
  strip.button = S.button(strip, "", 70, 22, true)
  strip.button:SetPoint("RIGHT", strip, "RIGHT", -6, 0)
  strip.button:SetScript("OnClick", function()
    local run = strip.run
    strip.run = nil
    strip:Hide()
    if run then
      run()
    end
  end)
  strip:Hide()
end

-- Shows `text`; `button` = { label, run } adds the button. Gone after NOTICE_SECONDS. The same
-- line goes to the addon chat, never the normal chat.
function Helpers.Notice(text, button)
  -- the Addons chat tab, or the voice (Core's Words, plan-launch-review R5.3); the strip always
  B:Tell(Helpers.mod, "notice", text)
  if not strip then
    buildStrip()
  end
  Helpers.lastNotice = text
  table.insert(Helpers.history, 1, { text = text, at = GetTime() })
  table.remove(Helpers.history, Helpers.HISTORY + 1)
  B:UpdateFeed(Helpers.mod)
  strip.text:SetText(text)
  strip.run = button and button.run or nil
  strip.button:SetLabel(button and button.label or "")
  if button then
    strip.button:Show()
  else
    strip.button:Hide()
  end
  strip:Show()
  shownAt = shownAt + 1
  local mine = shownAt
  C_Timer.After(Helpers.NOTICE_SECONDS, function()
    if mine == shownAt and strip then
      strip:Hide()
    end
  end)
  return strip
end

function Helpers.NoticeStrip()
  return strip
end
