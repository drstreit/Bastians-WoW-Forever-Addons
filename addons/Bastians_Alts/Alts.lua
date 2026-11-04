-- Bastian's Alts (alts.md, ADR 0041): the account's characters and what each carries. The model
-- (pure, over the saved `global` table), the recording of this character, and the registrations
-- that show it in the Browser: the character entity and list, its page, an item's holders, the
-- search, and asking another character for an item by mail (Mail.lua writes the mail).
local ADDON, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
local L = ns.L
local S = B.UI.Style

local Alts = {}
ns.Alts = Alts

Alts.SCAN_DELAY = 0.5 -- seconds after the last bag event before the bags are read again
Alts.LINK_QUALITY = 2 -- a row keeps its link from this quality on (a suffix lives in the link)
Alts.SLOT_NAMES = {
  [1] = "Head",
  [2] = "Neck",
  [3] = "Shoulder",
  [4] = "Shirt",
  [5] = "Chest",
  [6] = "Waist",
  [7] = "Legs",
  [8] = "Feet",
  [9] = "Wrist",
  [10] = "Hands",
  [11] = "Finger",
  [12] = "Finger",
  [13] = "Trinket",
  [14] = "Trinket",
  [15] = "Back",
  [16] = "Main hand",
  [17] = "Off hand",
  [18] = "Ranged",
  [19] = "Tabard",
}
Alts.PLACES = { "bags", "bank", "mail", "worn" }
Alts.PLACE_WORDS = { bags = "Bags", bank = "Bank", mail = "Mail", worn = "Worn" }

local mod
local ownerIndex -- Alts.Owned's index over every character's items, dropped by changed()

-- a character's record or a request changed (core-contracts §16)
B:DeclareMessage("BASTIANS_ALTS_CHANGED")

-- ---------------------------------------------------------------------------------------------
-- The model: plain tables in and out (the saved `global` table is handed in), no WoW API
-- ---------------------------------------------------------------------------------------------

local Model = {}
Alts.Model = Model

function Model.Ensure(global)
  global.characters = type(global.characters) == "table" and global.characters or {}
  global.requests = type(global.requests) == "table" and global.requests or {}
  return global
end

-- The item id of a link ("|Hitem:2589:..." or "item:2589"), nil for anything else.
function Model.LinkID(link)
  return type(link) == "string" and tonumber(string.match(link, "item:(%d+)")) or nil
end

-- Compat's container rows as the saved rows { itemID, count, bound, link }.
function Model.Rows(slots)
  local out = {}
  for _, s in ipairs(slots or {}) do
    if s.itemID then
      local link = (s.quality or 0) >= Alts.LINK_QUALITY and s.link or nil
      out[#out + 1] = { s.itemID, s.count or 1, s.bound and true or nil, link }
    end
  end
  return out
end

-- Where a character holds what: { [itemID] = { bags, bank, mail, worn, bound } } (counts; `bound`
-- the soulbound part of bags and bank, which mail cannot carry).
function Model.Places(c)
  local out = {}
  local function add(id, place, n, bound)
    local e = out[id]
    if not e then
      e = { bags = 0, bank = 0, mail = 0, worn = 0, bound = 0 }
      out[id] = e
    end
    e[place] = e[place] + n
    if bound and (place == "bags" or place == "bank") then
      e.bound = e.bound + n
    end
  end
  for _, place in ipairs({ "bags", "bank", "mail" }) do
    for _, r in ipairs(c[place] or {}) do
      add(r[1], place, r[2] or 1, r[3])
    end
  end
  for _, link in pairs(c.equipped or {}) do
    local id = Model.LinkID(link)
    if id then
      add(id, "worn", 1, true)
    end
  end
  return out
end

-- The characters holding an item: { key, char, bags, bank, mail, worn, total, free } by total,
-- `free` what mail can carry (bags and bank, not soulbound).
function Model.Holders(global, itemID)
  local out = {}
  for key, c in pairs(global.characters or {}) do
    local e = Model.Places(c)[itemID]
    if e then
      local total = e.bags + e.bank + e.mail + e.worn
      out[#out + 1] = {
        key = key,
        char = c,
        bags = e.bags,
        bank = e.bank,
        mail = e.mail,
        worn = e.worn,
        total = total,
        free = math.max(0, e.bags + e.bank - e.bound),
      }
    end
  end
  table.sort(out, function(a, b)
    if a.total ~= b.total then
      return a.total > b.total
    end
    return a.key < b.key
  end)
  return out
end

-- Whether a mail can go from one character to the other: the same realm and faction.
function Model.CanMail(a, b)
  return a ~= nil and b ~= nil and a.realm == b.realm and a.faction == b.faction
end

-- The holders `asker` may ask for an item: other characters it can mail with, something free.
function Model.Askable(global, asker, itemID)
  local me = global.characters[asker]
  local out = {}
  for _, h in ipairs(Model.Holders(global, itemID)) do
    if h.key ~= asker and h.free > 0 and Model.CanMail(me, h.char) then
      out[#out + 1] = h
    end
  end
  return out
end

-- Asks every askable holder for all it can send; an earlier request of the same asker for the
-- item goes. Returns the new requests.
function Model.Ask(global, asker, itemID, now)
  local keep = {}
  for _, r in ipairs(global.requests) do
    if not (r.asker == asker and r.item == itemID) then
      keep[#keep + 1] = r
    end
  end
  local made = {}
  for _, h in ipairs(Model.Askable(global, asker, itemID)) do
    local r = { item = itemID, count = h.free, holder = h.key, asker = asker, at = now }
    keep[#keep + 1] = r
    made[#made + 1] = r
  end
  global.requests = keep
  return made
end

-- What others ask of `holder`, by asker in the order asked: { { asker, items = { {item, count} } } }.
function Model.RequestsFor(global, holder)
  local groups, byAsker = {}, {}
  for _, r in ipairs(global.requests) do
    if r.holder == holder then
      local g = byAsker[r.asker]
      if not g then
        g = { asker = r.asker, items = {} }
        byAsker[r.asker] = g
        groups[#groups + 1] = g
      end
      g.items[#g.items + 1] = { r.item, r.count }
    end
  end
  return groups
end

-- The requests a character made or received: { request, index } (the index cancels it).
function Model.RequestsOf(global, key)
  local out = {}
  for i, r in ipairs(global.requests) do
    if r.holder == key or r.asker == key then
      out[#out + 1] = { request = r, index = i }
    end
  end
  return out
end

function Model.Cancel(global, index)
  table.remove(global.requests, index)
end

-- The key of the character named `name` on `realm` (a mail's recipient), nil when not recorded.
function Model.KeyOf(global, name, realm)
  if type(name) ~= "string" then
    return nil
  end
  local short, other = string.match(name, "^([^%-]+)%-(.+)$")
  name, realm = short or name, other or realm
  local want = string.lower(name)
  for key, c in pairs(global.characters) do
    if string.lower(c.name or "") == want and (realm == nil or c.realm == realm) then
      return key
    end
  end
  return nil
end

-- A mail went from `holder` to `recipient` (a name): the requests it answers go down by what it
-- carried, and the recipient's recorded mailbox gains the items. `items` = { [itemID] = count }.
function Model.Sent(global, holder, recipient, items, now)
  local from = global.characters[holder]
  local to = Model.KeyOf(global, recipient, from and from.realm)
  if not to then
    return nil
  end
  local keep = {}
  for _, r in ipairs(global.requests) do
    local went = r.holder == holder and r.asker == to and items[r.item]
    if went then
      r.count = r.count - went
    end
    if not (went and r.count <= 0) then
      keep[#keep + 1] = r
    end
  end
  global.requests = keep
  local c = global.characters[to]
  if c then
    c.mail = c.mail or {}
    for id, n in pairs(items) do
      c.mail[#c.mail + 1] = { id, n }
    end
    c.mailAt = c.mailAt or now
  end
  return to
end

-- ---------------------------------------------------------------------------------------------
-- Recording this character
-- ---------------------------------------------------------------------------------------------

local function global()
  return mod.db.global
end

function Alts.Key()
  return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local function now()
  return B.Compat.ServerTime and B.Compat.ServerTime() or time()
end

function Alts.Me()
  local key = Alts.Key()
  local c = global().characters[key]
  if not c then
    c = {}
    global().characters[key] = c
  end
  return c, key
end

local function changed()
  ownerIndex = nil
  B:InvalidateEntities("character")
  B:Fire("BASTIANS_ALTS_CHANGED")
end

function Alts.RecordFacts()
  local c = Alts.Me()
  local facts = B.Compat.GetPlayerFacts()
  c.name, c.realm = UnitName("player"), GetRealmName()
  c.class, c.race, c.faction, c.level = facts.class, facts.race, facts.faction, facts.level
  c.money = B.Compat.GetMoney()
  c.zone = B.Coords.PlayerMap() or c.zone
  c.seen = now()
end

function Alts.RecordBags()
  local c = Alts.Me()
  c.bags, c.bagsAt = Model.Rows(B.Compat.GetBagItems()), now()
end

function Alts.RecordEquipped()
  local c = Alts.Me()
  c.equipped = B.Compat.GetEquippedLinks()
end

function Alts.RecordBank()
  local c = Alts.Me()
  c.bank, c.bankAt = Model.Rows(B.Compat.GetContainerItems(B.Compat.BankBags())), now()
end

function Alts.RecordMail()
  local rows, money = B.Compat.GetInboxItems()
  if not rows then
    return
  end
  local c = Alts.Me()
  c.mail, c.mailMoney, c.mailAt = Model.Rows(rows), money, now()
end

-- What this character knows (alts.md "Knowledge", "known by you,
-- MyAltName, MyAltName2"): the spell book at login and when it changes, the open profession's
-- learned recipes whenever its window lists them. `ids` = { [spellID] = true }; nil adds nothing.
function Alts.RecordKnown(ids)
  if type(ids) ~= "table" then
    return false
  end
  local c = Alts.Me()
  c.known = c.known or {}
  local added = false
  for id in pairs(ids) do
    if c.known[id] == nil then
      added = true
    end
    c.known[id] = true
  end
  c.knownAt = now()
  return added
end

-- Who knows a spell or recipe: this character (the client's answer, else the record), and the
-- other characters that recorded it, by name.
function Alts.Known(spellID)
  spellID = tonumber(spellID)
  if not spellID then
    return nil
  end
  local mine, myKey = Alts.Me()
  local me = B.Compat.IsSpellKnown(spellID)
  if me == nil then
    me = mine.known and mine.known[spellID] == true or nil
  end
  local alts = {}
  for key, c in pairs(global().characters) do
    if key ~= myKey and type(c) == "table" and c.known and c.known[spellID] then
      alts[#alts + 1] = c.name or key
    end
  end
  table.sort(alts)
  return { me = me, alts = alts }
end

-- Everything this character can read now (the bank and the mailbox only while open).
function Alts.RecordAll()
  Alts.RecordFacts()
  Alts.RecordBags()
  Alts.RecordEquipped()
  Alts.RecordKnown(B.Compat.KnownSpells())
  changed()
end

-- Who owns an item (the Browser's Owned filter): "You", "Your characters" or "Nobody"; an index
-- over every character's places, built on the first ask and dropped when anything changes.
local ownerIndexGen -- the filter generation the index was built at (Core bumps it on the message)
function Alts.Owned(itemID)
  local gen = B:FilterGeneration("alts.owned")
  if not ownerIndex or ownerIndexGen ~= gen then
    ownerIndex, ownerIndexGen = {}, gen
    local myKey = select(2, Alts.Me())
    for key, c in pairs(global().characters) do
      if type(c) == "table" then
        local function own(id)
          if id then
            local o = ownerIndex[id] or {}
            ownerIndex[id] = o
            if key == myKey then
              o.me = true
            else
              o.alt = true
            end
          end
        end
        for id in pairs(Model.Places(c)) do -- bags, bank, mail and worn (Model.Places)
          own(id)
        end
      end
    end
  end
  local o = ownerIndex[tonumber(itemID) or 0]
  if o and o.me then
    return "You"
  elseif o and o.alt then
    return "Your characters"
  end
  return "Nobody"
end
local OWNED_ORDER = { You = 1, ["Your characters"] = 2, Nobody = 3 }

-- The card row of an item's page: "You have it: worn, bags 2; Bankalt: bank 40", nil when nobody.
function Alts.OwnedRow(ref)
  local typ, id = B.Entity.Parse(ref)
  if typ ~= "item" or type(id) ~= "number" or not mod then
    return nil
  end
  local myKey = select(2, Alts.Me())
  local parts = {}
  local holders = Model.Holders(global(), id)
  table.sort(holders, function(a, b) -- you first, then the others by what they hold
    if (a.key == myKey) ~= (b.key == myKey) then
      return a.key == myKey
    end
    return (a.total or 0) > (b.total or 0)
  end)
  for _, h in ipairs(holders) do
    local places = {}
    for _, place in ipairs(Alts.PLACES) do
      if h[place] > 0 then
        places[#places + 1] = place == "worn" and L["worn"]
          or (string.lower(L[Alts.PLACE_WORDS[place]]) .. " " .. h[place])
      end
    end
    local who = h.key == myKey and L["You have it"] or (h.char.name or h.key)
    parts[#parts + 1] = who .. ": " .. table.concat(places, ", ")
  end
  if #parts == 0 then
    return nil
  end
  return { { text = table.concat(parts, "; "), color = S.C.good } }
end

-- The card row of a recipe's page: "Known by: you, Bankalt" (a recipe's id is its spell's).
function Alts.KnownRow(ref)
  local typ, id = B.Entity.Parse(ref)
  if typ ~= "recipe" or type(id) ~= "number" then
    return nil
  end
  local k = Alts.Known(id)
  local names = {}
  if k and k.me then
    names[#names + 1] = L["you"]
  end
  for _, name in ipairs(k and k.alts or {}) do
    names[#names + 1] = name
  end
  if #names == 0 then
    return nil
  end
  return { { text = string.format(L["Known by: %s"], table.concat(names, ", ")), color = S.C.good } }
end

-- ---------------------------------------------------------------------------------------------
-- The pages (core-contracts §4, §7)
-- ---------------------------------------------------------------------------------------------

local function charOf(ref)
  local typ, key = B.Entity.Parse(ref)
  if typ ~= "character" or not mod then
    return nil
  end
  return global().characters[tostring(key)], tostring(key)
end

local function className(c)
  local classes = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
  return c.class and (type(classes) == "table" and classes[c.class] or L[c.class]) or nil
end

function Alts.ClassIcon(c)
  if c and c.class then
    return "Interface\\Icons\\ClassIcon_" .. c.class
  end
  return B.UI.IconTexture("other")
end

local function zoneName(map)
  return map and B:Entity("zone:" .. map):Name() or nil
end

local function itemText(id, link)
  local name = B:Entity("item:" .. id):Name() or (link and string.match(link, "%[(.-)%]")) or ("item " .. id)
  return name
end

-- "3 h ago", "2 days ago" for a time read; nil without one.
function Alts.Age(at, nowTime)
  if not at then
    return nil
  end
  local s = math.max(0, (nowTime or now()) - at)
  if s < 3600 then
    return string.format(L["%d min ago"], math.floor(s / 60))
  elseif s < 86400 then
    return string.format(L["%d h ago"], math.floor(s / 3600))
  end
  return string.format(L["%d days ago"], math.floor(s / 86400))
end

-- The rows of one place, one per item (stacks summed), by name.
local function placeRows(list)
  if not list then
    return nil
  end
  local sum, links, order = {}, {}, {}
  for _, r in ipairs(list) do
    local id = r[1]
    if not sum[id] then
      order[#order + 1] = id
      sum[id] = 0
    end
    sum[id] = sum[id] + (r[2] or 1)
    links[id] = links[id] or r[4]
  end
  local rows = {}
  for _, id in ipairs(order) do
    rows[#rows + 1] = {
      text = itemText(id, links[id]),
      ref = "item:" .. id,
      icon = B:Entity("item:" .. id):Icon(),
      value = sum[id],
      valueKind = "number",
    }
  end
  table.sort(rows, function(a, b)
    return a.text < b.text
  end)
  return rows
end

local function placeTitle(word, field)
  return function(ref)
    local c = charOf(ref)
    local age = c and Alts.Age(c[field])
    return L[word] .. (age and ("  " .. S.H.muted .. age .. "|r") or "")
  end
end

local function overviewRows(ref)
  local c = charOf(ref)
  if not c then
    return nil
  end
  local rows = {}
  if c.level then
    rows[#rows + 1] = { text = L["Level"], value = c.level, valueKind = "number" }
  end
  if c.money then
    rows[#rows + 1] = { text = L["Money"], value = c.money, valueKind = "money" }
  end
  if c.mailMoney and c.mailMoney > 0 then
    rows[#rows + 1] = { text = L["Money in the mail"], value = c.mailMoney, valueKind = "money" }
  end
  local zone = zoneName(c.zone)
  if zone then
    rows[#rows + 1] = { text = L["Last in"] .. ": " .. zone, ref = "zone:" .. c.zone }
  end
  local seen = Alts.Age(c.seen)
  if seen then
    rows[#rows + 1] = { text = L["Last seen"], value = seen }
  end
  return rows
end

local function equipmentRows(ref)
  local c = charOf(ref)
  if not (c and c.equipped and next(c.equipped)) then
    return nil
  end
  local rows = {}
  for slot = 1, 19 do
    local link = c.equipped[slot]
    local id = Model.LinkID(link)
    if id then
      rows[#rows + 1] = {
        text = itemText(id, link) .. "  " .. S.H.muted .. L[Alts.SLOT_NAMES[slot]] .. "|r",
        ref = "item:" .. id,
        icon = B:Entity("item:" .. id):Icon(),
      }
    end
  end
  return rows
end

local function requestRows(ref)
  local c, key = charOf(ref)
  if not c then
    return nil
  end
  local rows = {}
  for _, e in ipairs(Model.RequestsOf(global(), key)) do
    local r = e.request
    local other = global().characters[r.holder == key and r.asker or r.holder]
    local who = other and other.name or "?"
    local words = r.holder == key and string.format(L["%s asks for it"], who)
      or string.format(L["asked of %s"], who)
    local index = e.index
    rows[#rows + 1] = {
      text = itemText(r.item) .. "  " .. S.H.muted .. words .. "|r",
      icon = B:Entity("item:" .. r.item):Icon(),
      value = r.count,
      valueKind = "number",
      tooltip = function(tip)
        S.TipLine(tip, itemText(r.item), "tipText")
        S.TipLine(tip, L["Click: cancel this request"], "tipDim")
      end,
      onClick = function()
        Model.Cancel(global(), index)
        changed()
      end,
    }
  end
  return #rows > 0 and rows or nil
end

-- "Your characters have it" on an item's page: a row per holder, its places in grey.
function Alts.HolderRows(ref)
  local typ, id = B.Entity.Parse(ref)
  if typ ~= "item" or type(id) ~= "number" or not mod then
    return nil
  end
  local rows = {}
  for _, h in ipairs(Model.Holders(global(), id)) do
    local parts = {}
    for _, place in ipairs(Alts.PLACES) do
      if h[place] > 0 then
        parts[#parts + 1] = L[Alts.PLACE_WORDS[place]] .. " " .. h[place]
      end
    end
    rows[#rows + 1] = {
      text = (h.char.name or h.key) .. "  " .. S.H.muted .. table.concat(parts, ", ") .. "|r",
      ref = "character:" .. h.key,
      icon = Alts.ClassIcon(h.char),
      value = h.total,
      valueKind = "number",
    }
  end
  return #rows > 0 and rows or nil
end

local function holderTipRows(ref)
  local rows = Alts.HolderRows(ref)
  for _, row in ipairs(rows or {}) do
    row.text = string.gsub(row.text, "  .*$", "") .. ": " .. row.value -- "Bankalt: 60"
    row.value, row.icon = nil, nil
  end
  return rows
end

-- ---------------------------------------------------------------------------------------------
-- Asking for an item
-- ---------------------------------------------------------------------------------------------

function Alts.Ask(itemID)
  local made = Model.Ask(global(), Alts.Key(), itemID, now())
  if #made == 0 then
    B:Say(L["None of your characters on this realm and side has this item to send."])
  else
    local names = {}
    for _, r in ipairs(made) do
      local c = global().characters[r.holder]
      names[#names + 1] = string.format("%s (%d)", c and c.name or r.holder, r.count)
    end
    B:Say(
      string.format(
        L["Asked %s for %s. Their next visit to a mailbox fills the mail."],
        table.concat(names, ", "),
        itemText(itemID)
      )
    )
  end
  changed()
  return made
end

-- ---------------------------------------------------------------------------------------------
-- Search (core-contracts §7a): items the characters hold, by name
-- ---------------------------------------------------------------------------------------------

function Alts.Search(query, limit, yield, q)
  q = q or B.Query.Compile(query) -- the suite's search syntax (ADR 0045)
  if q.empty or not mod then
    return {}
  end
  local totals, seen = {}, {}
  for _, c in pairs(global().characters) do
    for id, e in pairs(Model.Places(c)) do
      totals[id] = (totals[id] or 0) + e.bags + e.bank + e.mail + e.worn
      seen[id] = true
    end
  end
  local out, n = {}, 0
  for id in pairs(seen) do
    n = n + 1
    if yield and n % 200 == 0 then
      yield()
    end
    local name = B:Entity("item:" .. id):Name()
    local score = q:Score(name)
    if score then
      out[#out + 1] = {
        ref = "item:" .. id,
        label = name,
        score = score >= 0.9 and 80 or 60,
        note = L["Alts"] .. ": " .. totals[id],
      }
    end
  end
  table.sort(out, function(a, b)
    return a.label < b.label
  end)
  while limit and #out > limit do
    out[#out] = nil
  end
  return out
end

-- ---------------------------------------------------------------------------------------------
-- The module
-- ---------------------------------------------------------------------------------------------

local function register(self)
  B:RegisterEntityType(self, {
    type = "character",
    name = function(key)
      local c = global().characters[tostring(key)]
      return c and c.name or nil
    end,
    icon = function(key)
      local c = global().characters[tostring(key)]
      return c and Alts.ClassIcon(c) or nil
    end,
    summary = function(key)
      local c = global().characters[tostring(key)]
      if not c then
        return nil
      end
      local parts = {}
      if c.level then
        parts[#parts + 1] = L["Level"] .. " " .. c.level .. (className(c) and (" " .. className(c)) or "")
      end
      local zone = zoneName(c.zone)
      if zone then
        parts[#parts + 1] = zone
      end
      return #parts > 0 and table.concat(parts, ", ") or nil
    end,
    fields = function(key)
      local c = global().characters[tostring(key)]
      return c and { level = c.level, realm = c.realm, faction = c.faction } or nil
    end,
  })
  B:RegisterList(self, {
    type = "character",
    label = "Characters",
    glyph = "banker",
    facet = "realm",
    noNear = true, -- a handful of rows: every character, wherever it stands
    ids = function()
      local keys = {}
      for key in pairs(global().characters) do
        keys[#keys + 1] = key
      end
      table.sort(keys)
      return keys
    end,
    record = function(key)
      local c = global().characters[key]
      if not c then
        return nil
      end
      return { name = c.name or key, level = c.level, zone = c.zone, realm = c.realm, c = c }
    end,
    value = function(r)
      return r.realm
    end,
    suffix = function(r)
      local words = {}
      words[#words + 1] = className(r.c)
      if r.c.money then
        words[#words + 1] = B.UI.Money(r.c.money)
      end
      return #words > 0 and table.concat(words, ", ") or nil
    end,
    ref = function(key)
      return "character:" .. key
    end,
  })
  local INVALIDATE = { "BASTIANS_ALTS_CHANGED" }
  local function section(def)
    def.invalidateOn = def.invalidateOn or INVALIDATE
    B:RegisterDetailSection(self, def)
  end
  -- the Owned facet of the item lists ("a filter 'owned by you' and
  -- 'owned by an alt'")
  B:RegisterFilter(self, {
    id = "alts.owned",
    kind = "facet",
    types = { "item" },
    label = L["Owned"],
    invalidateOn = INVALIDATE,
    value = function(ref)
      local typ, id = B.Entity.Parse(ref)
      return typ == "item" and Alts.Owned(id) or nil
    end,
    labels = function(key)
      return L[key]
    end,
    order = function(key)
      return OWNED_ORDER[key] or 9
    end,
  })
  -- the account service (#14): the gold of the account's characters as last seen
  B:ProvideService(self, "account", {
    Money = function()
      return ns.Feed.Total()
    end,
  }, { priority = 100 })
  -- the knowledge service (core-contracts section 11): who knows a spell or recipe
  B:ProvideService(self, "knowledge", {
    Known = function(_, spellID)
      return Alts.Known(spellID)
    end,
  }, { priority = 100 })
  section({
    id = "alts.overview",
    title = L["Overview"],
    types = { "character" },
    order = 10,
    build = overviewRows,
  })
  section({
    id = "alts.equipment",
    title = L["Equipment"],
    types = { "character" },
    order = 20,
    block = { limit = 19 },
    build = equipmentRows,
  })
  section({
    id = "alts.bags",
    title = placeTitle("Bags", "bagsAt"),
    types = { "character" },
    order = 30,
    block = { limit = 12 },
    build = function(ref)
      local c = charOf(ref)
      return c and placeRows(c.bags) or nil
    end,
  })
  section({
    id = "alts.bank",
    title = placeTitle("Bank", "bankAt"),
    types = { "character" },
    order = 31,
    block = { limit = 12 },
    build = function(ref)
      local c = charOf(ref)
      return c and placeRows(c.bank) or nil
    end,
  })
  section({
    id = "alts.mail",
    title = placeTitle("Mail", "mailAt"),
    types = { "character" },
    order = 32,
    block = { limit = 12 },
    build = function(ref)
      local c = charOf(ref)
      return c and placeRows(c.mail) or nil
    end,
  })
  section({
    id = "alts.requests",
    title = L["Requests"],
    types = { "character" },
    order = 15,
    cache = false, -- a click cancels a row at once
    build = requestRows,
  })
  section({
    id = "alts.holders",
    title = L["Your characters have it"],
    types = { "item" },
    order = 18,
    block = { limit = 6 },
    build = Alts.HolderRows,
    tooltip = { max = 3, build = holderTipRows },
  })
  -- the band says it at once ("a clear indication on each node's detail
  -- page if I or an alt owns it"): one card row, the status words under the name
  section({
    id = "alts.owned",
    title = L["Owned"],
    types = { "item" },
    order = 17,
    card = true,
    build = Alts.OwnedRow,
  })
  section({
    id = "alts.known",
    title = L["Known by"],
    types = { "recipe" },
    order = 17,
    card = true,
    build = Alts.KnownRow,
  })
  B:RegisterAction(self, {
    id = "alts.ask",
    label = L["Ask my characters for this"],
    types = { "item" },
    order = 45,
    when = function(ref)
      local _, id = B.Entity.Parse(ref)
      return type(id) == "number" and #Model.Askable(global(), Alts.Key(), id) > 0
    end,
    run = function(ref)
      local _, id = B.Entity.Parse(ref)
      Alts.Ask(id)
    end,
  })
  B:RegisterSearchProvider(self, {
    id = "alts.items",
    label = L["Your characters"],
    priority = 60,
    search = Alts.Search,
  })
end

local function scheduleBags(self)
  self:Coalesce("bags", Alts.SCAN_DELAY, function()
    Alts.RecordBags()
    if Alts.bankOpen then
      Alts.RecordBank()
    end
    changed()
  end)
end

mod = B:NewModule("Alts", {
  news = ns.NEWS, -- What's new (ADR 0021)
  addon = ADDON,
  open = function()
    Alts.Toggle() -- the launcher's second click closes (7fce01a)
  end,
  title = L["Alts"],
  apiVersion = 1,
  optional = { "Bastians_Data", "Bastians_Browser" },
  defaults = {
    profile = { window = {}, tree = {} }, -- the window's place and size, its folds (Window.lua)
    global = { characters = {}, requests = {} },
  },
  OnEnable = function(self)
    Model.Ensure(self.db.global)
    register(self)
    ns.Feed.Register(self) -- the broker displays' feed (ADR 0043)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
      Alts.RecordAll()
    end)
    self:RegisterEvent("BAG_UPDATE_DELAYED", scheduleBags)
    -- the spell book and the open profession window (alts.md "Knowledge")
    self:RegisterEvent("SPELLS_CHANGED", function(me)
      me:Coalesce("known", 2, function()
        if Alts.RecordKnown(B.Compat.KnownSpells()) then
          changed()
        end
      end)
    end)
    for _, event in ipairs({ "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_SHOW" }) do
      self:RegisterEvent(event, function(me)
        me:Coalesce("recipes", 0.5, function()
          if Alts.RecordKnown(B.Compat.OpenRecipes()) then
            changed()
          end
        end)
      end)
    end
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function()
      Alts.RecordEquipped()
      changed()
    end)
    for _, event in ipairs({ "PLAYER_MONEY", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA", "PLAYER_LOGOUT" }) do
      self:RegisterEvent(event, function()
        Alts.RecordFacts()
        changed()
      end)
    end
    self:RegisterEvent("BANKFRAME_OPENED", function()
      Alts.bankOpen = true
      Alts.RecordBank()
      changed()
    end)
    self:RegisterEvent("BANKFRAME_CLOSED", function()
      Alts.bankOpen = false
    end)
    self:RegisterEvent("PLAYERBANKSLOTS_CHANGED", scheduleBags)
    self:RegisterEvent("MAIL_INBOX_UPDATE", function()
      Alts.RecordMail()
      changed()
    end)
    if ns.Mail then
      ns.Mail.Attach(self)
    end
    ns.Window.Register(self)
    -- one bus handler per message per module (Core replaces an earlier one): the mail strip and
    -- the window both follow a change
    self:On("BASTIANS_ALTS_CHANGED", function()
      if ns.Mail then
        ns.Mail.Update()
      end
      ns.Window.Schedule()
    end)
    if IsLoggedIn and IsLoggedIn() then
      Alts.RecordAll()
    end
  end,
})
Alts.mod = mod
mod.Alts = Alts

-- `/balts`: the window on this character (Window.lua; before 02.11.2026 the Browser's page).
function Alts.Open()
  return ns.Window.Open(Alts.Key())
end

function Alts.Toggle()
  return ns.Window.Toggle()
end

SLASH_BASTIANSALTS1 = "/balts"
SlashCmdList.BASTIANSALTS = function()
  Alts.Open()
end
