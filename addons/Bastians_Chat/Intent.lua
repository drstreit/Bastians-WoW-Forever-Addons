-- Bastian's Chat, what a line wants (plan-chat-v3.md §5, §10): an offer (WTS, WTB) with its item,
-- count and price, a group (LFM, LFG) with its dungeon and roles, a question (where are you, item
-- level, level, a recipe, an invite, a price); and what the player gained (loot, money,
-- experience, reputation) for the ledger. Never for a secret line. A price that cannot be read
-- stays nil, never 0 (golden rule 2). Pure: the words of the client language are handed in.
local _, ns = ...
local Words, Record = ns.Words, ns.Record

local Intent = {}
ns.Intent = Intent

-- the chat types people write in; system lines carry no intent, only gains
Intent.PEOPLE = {
  SAY = true,
  YELL = true,
  CHANNEL = true,
  COMMUNITIES_CHANNEL = true,
  WHISPER = true,
  BN_WHISPER = true,
  GUILD = true,
  OFFICER = true,
  PARTY = true,
  PARTY_LEADER = true,
  RAID = true,
  RAID_LEADER = true,
  INSTANCE_CHAT = true,
  INSTANCE_CHAT_LEADER = true,
}
-- the questions one person asks another (whispers and the group's chats), in the order they are tried
-- thanks, congratulations and greetings last (V23): "hi, where are you?" asks where
Intent.ASKS = { "where", "ilvl", "level", "recipe", "invite", "price", "thanks", "gz", "hi" }
Intent.ASKED_IN = {
  WHISPER = true,
  BN_WHISPER = true,
  GUILD = true,
  OFFICER = true,
  PARTY = true,
  PARTY_LEADER = true,
  RAID = true,
  RAID_LEADER = true,
  INSTANCE_CHAT = true,
  INSTANCE_CHAT_LEADER = true,
}
-- the chat types everybody around reads: where offers, groups and services are sorted by their
-- words (V45), never a whisper, the guild or the group
Intent.PUBLIC = { SAY = true, YELL = true, CHANNEL = true, COMMUNITIES_CHANNEL = true }
local RECIPE_LINK = { enchant = true, trade = true } -- assumed on Forever (forever-api.md)
local SERVICE_LINK = { item = true, spell = true, enchant = true, trade = true }
local COPPER = { gold = 10000, silver = 100, copper = 1 }

-- The first amount of money written in `text` as copper ("5g 50s", "5g50", "3 Silver, 2 Copper",
-- "1.5g"), or nil when none is written. Amounts that follow each other closely add up; the next
-- amount after a gap is another price and is left alone.
function Intent.Money(text, w)
  if type(text) ~= "string" then
    return nil
  end
  local total, last, lastUnit = nil, nil, nil
  local init = 1
  while true do
    -- the unit in letters of any script: "5g", "5골", "5金", "5г" (V9)
    local s, e, num, unit = text:find("(%d+[%.,]?%d*)%s*([%a\128-\255]*)", init)
    if not s then
      break
    end
    init = e + 1
    local near = last and s - last <= 3
    if total and not near then
      break
    end
    local kind = w.units[unit]
    local n = tonumber((num:gsub(",", ".")))
    if kind and n then
      total = (total or 0) + math.floor(n * COPPER[kind] + 0.5)
      last, lastUnit = e + 1, kind
    elseif unit == "" and n and near and lastUnit == "gold" and n < 100 then
      total = total + n * 100 -- "5g50": the bare number after the gold is silver
      last, lastUnit = e + 1, "silver"
    elseif total then
      break
    end
  end
  return total
end

local function itemLinks(rec)
  local out = {}
  for _, link in ipairs(rec.links or {}) do
    if link.kind == "item" and link.id then
      out[#out + 1] = link
    end
  end
  return out
end

-- How many of the item the line offers: "[Linen Cloth]x20", "[Linen Cloth] x 20", "20x [Linen
-- Cloth]", "[Linen Cloth] 20x". Nil when not written.
local function count(plain)
  local n = plain:match("%]%s*x%s*(%d+)") or plain:match("(%d+)%s*x%s*%[") or plain:match("%]%s*(%d+)%s*x")
  return tonumber(n)
end

-- The part of the text after the first item link: where its price stands.
local function afterLink(plain)
  local _, e = plain:find("%b[]")
  return e and plain:sub(e + 1) or plain
end

local function offer(rec, w, plain)
  local items = itemLinks(rec)
  if #items == 0 then
    return nil
  end
  local kind
  if Words.Has(plain, w.wts, w.loose) then
    kind = "wts"
  elseif Words.Has(plain, w.wtb, w.loose) then
    kind = "wtb"
  end
  if not kind then
    return nil
  end
  local ids = {}
  for i, link in ipairs(items) do
    ids[i] = link.id
  end
  local rest = afterLink(plain)
  local it = { kind = kind, item = items[1].id, items = ids, quality = items[1].quality, qty = count(plain) }
  -- the count is not a price: "x20" and "20x" leave the text before the money is read
  local priced = rest:gsub("%f[%w]x%s*%d+", " ")
  priced = priced:gsub("%d+%s*x%f[%W]", " ")
  it.price = Intent.Money(priced, w)
  if Words.Has(rest, w.each, w.loose) then
    it.each = true
  elseif Words.Has(rest, w.stack, w.loose) then
    it.each = false
  end
  return it
end

local function lfCount(plain)
  local s, e, n = plain:find("lf(%d+)m")
  if not s then
    return nil
  end
  local before, after = plain:byte(s - 1), plain:byte(e + 1)
  local function letter(b)
    return b and ((b >= 97 and b <= 122) or b >= 128)
  end
  if letter(before) or letter(after) then
    return nil
  end
  return tonumber(n)
end

local function group(w, plain)
  local dungeon = Words.Dungeon(w, plain)
  local roles = Words.Roles(w, plain)
  local need = lfCount(plain)
  local kind
  if Words.Has(plain, w.lfg, w.loose) then
    kind = "lfg"
  elseif need or Words.Has(plain, w.lfm, w.loose) then
    kind = "lfm"
  elseif Words.Has(plain, w.lf, w.loose) and (#roles > 0 or dungeon) then
    kind = "lfm"
  end
  if not kind then
    return nil
  end
  return { kind = kind, dungeon = dungeon, roles = roles, need = need }
end

-- A craft or a service on offer or asked for where everybody reads (V45; the owner, Forever
-- 15.11.2026, on a yelled enchanting offer and a lockbox request in General: "I would filter
-- them into the trade window"): a recipe's link; a link of an item, a spell or a recipe beside a
-- service word; a locked box; a trade by its name beside an offer word, a "looking for" or an
-- "anyone". { kind = "service", link = { kind, id } | nil }.
local function service(rec, w, plain)
  if not Intent.PUBLIC[rec.chatType] then
    return nil
  end
  local recipe, linked
  for _, link in ipairs(rec.links or {}) do
    if RECIPE_LINK[link.kind] then
      recipe = recipe or link
    end
    if SERVICE_LINK[link.kind] then
      linked = linked or link
    end
  end
  local named = recipe ~= nil
    or (linked ~= nil and Words.Has(plain, w.service, w.loose) ~= nil)
    or Words.Has(plain, w.locks, w.loose) ~= nil
  if not named and Words.Has(plain, w.trades, w.loose) then
    named = Words.Has(plain, w.wts, w.loose) ~= nil
      or Words.Has(plain, w.wtb, w.loose) ~= nil
      or Words.Has(plain, w.lf, w.loose) ~= nil
      or Words.Has(plain, w.anyone, w.loose) ~= nil
  end
  if not named then
    return nil
  end
  local link = recipe or linked
  return { kind = "service", link = link and { kind = link.kind, id = link.id } or nil }
end

local function question(rec, w, plain)
  for _, ask in ipairs(Intent.ASKS) do
    if Words.Has(plain, w.ask[ask], w.loose) then
      local it = { kind = "ask", ask = ask }
      if ask == "recipe" then
        -- a recipe question names the recipe: a link of an item, a spell or an enchant
        local link = Record.Link(rec, "item") or Record.Link(rec, "spell") or Record.Link(rec, "enchant")
        if link then
          it.link = { kind = link.kind, id = link.id }
          return it
        end
      elseif ask == "price" then
        local item = Record.Link(rec, "item")
        it.item = item and item.id
        return it
      else
        return it
      end
    end
  end
  return nil
end

-- What a line of a person wants, or nil: an offer, a group, a service, a question.
function Intent.Parse(rec, w)
  if rec.secret or type(rec.plain) ~= "string" or not Intent.PEOPLE[rec.chatType] then
    return nil
  end
  local plain = rec.plain
  local it = offer(rec, w, plain) or group(w, plain) or service(rec, w, plain)
  if not it and Intent.ASKED_IN[rec.chatType] and not rec.own then
    it = question(rec, w, plain)
  end
  return it
end

-- The repost key (plan §1): the same sender with the same offer or group again replaces the older
-- line in the boards and the stream.
function Intent.Key(rec)
  local it, who = rec.intent, rec.who and rec.who.name
  if not it or not who then
    return nil
  end
  if it.kind == "wts" or it.kind == "wtb" then
    return who .. "|" .. it.kind .. "|" .. tostring(it.item)
  elseif it.kind == "lfm" or it.kind == "lfg" then
    return who .. "|" .. it.kind .. "|" .. (it.dungeon or "?")
  elseif it.kind == "service" then
    return who .. "|service|" .. tostring(it.link and it.link.id or "?")
  end
  return nil
end

function Intent.Apply(rec, w)
  rec.intent = Intent.Parse(rec, w)
  rec.key = Intent.Key(rec)
  return rec
end

-- What the player gained by a line of the stream `mine`, from the client string it matched
-- (Relevance put the entry and its captures on the record): { kind = "item", item, qty } |
-- { kind = "money", copper } | { kind = "xp", xp } | { kind = "rep", faction, rep }; nil when
-- the line gained nothing countable.
function Intent.Gain(rec, w)
  local entry, caps = rec.sys, rec.caps
  if not entry or not entry.gain or rec.secret then
    return nil
  end
  local g
  if entry.gain == "item" then
    local link = Record.Link(rec, "item")
    if link and link.id then
      g = { kind = "item", item = link.id, qty = entry.qty and tonumber(caps[entry.qty]) or 1 }
    end
  elseif entry.gain == "money" then
    local copper = Intent.Money(ns.Model.Strip(caps[entry.money or 1]):lower(), w)
    if copper then
      g = { kind = "money", copper = copper }
    end
  elseif entry.gain == "xp" then
    local xp = tonumber(caps[entry.num or 1])
    if xp then
      g = { kind = "xp", xp = xp }
    end
  elseif entry.gain == "rep" then
    local rep = tonumber(caps[entry.num or 2])
    local faction = caps[entry.name or 1]
    if rep and faction then
      g = { kind = "rep", rep = rep * (entry.sign or 1), faction = faction }
    end
  elseif entry.gain == "quest" then -- a quest the player completed (V22)
    local name = caps[entry.name or 1]
    if type(name) == "string" and name ~= "" then
      g = { kind = "quest", name = name }
    end
  end
  rec.gain = g
  return g
end
