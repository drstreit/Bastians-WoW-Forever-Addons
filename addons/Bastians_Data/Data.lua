-- Bastian's Data: loader and query API over the generated packs (data.md, core-contracts §11).
-- Packs are addons whose generated file queues Bastians.Data.RegisterPack(name, pack) through
-- Bastians.deferred (Init.lua); they load at startup since 20.10.2026, see data.md "Pack addons".
-- Query functions never load a pack; Data loads them itself in a Job after login (never in hot paths).
local ADDON, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
local L = ns.L
local S = B.UI.Style

local Data = { packs = {}, loaded = {}, typePack = {}, foreign = {}, noData = {} }
B.Data = Data
ns.Data = Data

local PACK_ADDON = B.PACK_ADDONS -- Core's one map of pack names to folders (ADR 0015)
Data.PACK_ADDON = PACK_ADDON
local OPTIONAL = B.OPTIONAL_PACKS -- built only when their source exists (data.md)
local TYPES = { "quest", "npc", "object", "item", "recipe", "zone", "node", "flightpath", "transport" }
local SEARCH_SLICE = 200 -- records between yields in the search provider

local decoded = setmetatable({}, { __mode = "v" }) -- "type:id" -> decoded record (weak values)
local mod

-- ---------------------------------------------------------------------------------------------
-- Packs
-- ---------------------------------------------------------------------------------------------

-- Called by a pack file at load. `pack` = { version, build, client, sources, schema = { type = fields },
-- [type] = { [id] = positional record }, index = { name = { key = value } } } (format B, data.md).
function Data.RegisterPack(name, pack)
  if type(name) ~= "string" or type(pack) ~= "table" or type(pack.schema) ~= "table" then
    error("RegisterPack(name, pack): pack needs a schema table", 2)
  end
  Data.packs[name] = pack
  Data.loaded[name] = true
  -- A pack built for the other client still loads (its format is the same), but its ids and places
  -- belong to that client: flagged for Meta and the settings hub (data.md, ADR 0010).
  if pack.client and B.Client ~= "unknown" and pack.client ~= B.Client then
    Data.foreign[name] = pack.client
    B:Log(mod, "warn", "pack %s was built for %s, this client is %s", name, pack.client, B.Client)
    if mod then -- said in chat too, once for all packs of a load burst (ADR 0015)
      mod:Coalesce("foreign", 0.5, function()
        local note = Data.ForeignNote()
        if note then
          B:Say(note)
        end
      end)
    end
  else
    Data.foreign[name] = nil
  end
  for typ in pairs(pack.schema) do
    Data.typePack[typ] = name
  end
  for k in pairs(decoded) do
    decoded[k] = nil
  end
  Data.allIDs = {}
  Data.nodeByName = nil -- rebuilt from the new records on the next node lookup
  B:Fire("BASTIANS_DATA_LOADED", name)
end

-- Called by Generated/MapTransforms.lua (pipeline, from probe P3 or client files): the per-uiMapID
-- affine transforms that Bastians.Coords and Compat.MapPosToWorld use when the API has no answer,
-- and the continent names { [Map.db2 id] = name } the Map lists (coordinates.md).
function Data.RegisterTransforms(transforms, continents)
  Data.transforms = transforms
  Data.continents = continents
  B.Coords.SetTransforms(transforms, continents)
end

-- Loads a pack now (out of combat; Compat defers in combat). Returns the Compat status.
function Data.LoadPack(name)
  local addon = PACK_ADDON[name]
  if not addon then
    return "missing", "unknown pack " .. tostring(name)
  end
  if Data.loaded[name] then
    return "loaded"
  end
  local status, reason = B.Compat.LoadAddOn(addon)
  if status == "loaded" and not Data.loaded[name] then
    if OPTIONAL[name] then
      if not Data.noData[name] then -- once, however often a consumer asks
        Data.noData[name] = true
        B:Log(mod, "info", "pack %s has no generated data (optional)", addon)
      end
    else
      B:Log(mod, "error", "pack %s loaded but registered no data (is its Generated file built?)", addon)
    end
    return "failed", "no data"
  end
  if status == "missing" then
    B:Log(mod, "info", "pack %s is not installed", addon)
  elseif status == "failed" then
    B:Log(mod, "warn", "pack %s failed to load: %s", addon, tostring(reason))
  end
  return status, reason
end

-- Pack names wanted by every initialized module (its `data` field), in load order.
local function wantedPacks()
  local wanted, order = {}, {}
  for _, m in B:IterateModules() do
    if m.state ~= "registered" and m:IsSwitchOn() then
      for _, name in ipairs(m.data or {}) do
        if PACK_ADDON[name] and not wanted[name] then
          wanted[name] = true
          order[#order + 1] = name
        end
      end
    end
  end
  return order
end

local function loadWantedPacks(self)
  B.Jobs:Run(self, "load-packs", function(yield)
    for _, name in ipairs(wantedPacks()) do
      if not Data.loaded[name] then
        Data.LoadPack(name)
        yield()
      end
    end
  end)
end

-- ---------------------------------------------------------------------------------------------
-- Records
-- ---------------------------------------------------------------------------------------------

-- A pack row is the record's Lua literal as a string (format A, data.md): compiled on first access,
-- then held in the weak cache. A row that is already a table (older packs, tests) is read as is.
local function decodeRow(raw, key)
  if type(raw) ~= "string" then
    return raw
  end
  local chunk = loadstring("return " .. raw, "=" .. key)
  if not chunk then
    B:Log(mod, "error", "pack record %s does not compile", key)
    return nil
  end
  local ok, row = pcall(chunk)
  if not ok or type(row) ~= "table" then
    B:Log(mod, "error", "pack record %s failed: %s", key, tostring(row))
    return nil
  end
  return row
end

local function record(typ, id)
  local key = typ .. ":" .. tostring(id)
  local rec = decoded[key]
  if rec then
    return rec
  end
  local packName = Data.typePack[typ]
  local pack = packName and Data.packs[packName]
  local raw = pack and pack[typ] and pack[typ][id]
  if not raw then
    return nil
  end
  local row = decodeRow(raw, key)
  if not row then
    return nil
  end
  rec = { id = id, type = typ }
  for i, field in ipairs(pack.schema[typ]) do
    rec[field] = row[i]
  end
  decoded[key] = rec
  return rec
end
Data.record = record

local function index(name)
  for _, pack in pairs(Data.packs) do
    local idx = pack.index and pack.index[name]
    if idx then
      return idx
    end
  end
  return nil
end

-- { {map, x, y, src}, ... } positional -> { map =, x =, y =, src = } (cached on the record)
local function spawns(rec)
  if rec._spawns then
    return rec._spawns
  end
  local out = {}
  for _, s in ipairs(rec.spawns or {}) do
    out[#out + 1] = { map = s[1], x = s[2], y = s[3], src = s[4] }
  end
  rec._spawns = out
  return out
end

-- ---------------------------------------------------------------------------------------------
-- The `data` service (data.md is the single definition)
-- ---------------------------------------------------------------------------------------------

local service = {}
Data.service = service

function service:Get(typ, id)
  return record(typ, id)
end

function service:ByZone(typ, map)
  local idx = index(typ .. ".byZone")
  local list = idx and idx[map] or {}
  local i = 0
  return function()
    i = i + 1
    return list[i]
  end
end

-- Name search over loaded records: exact 1.0, prefix 0.9, substring 0.7. `yield` is optional.
function service:Find(typ, text, limit, yield)
  text = string.lower(text or "")
  limit = limit or 20
  local out = {}
  if text == "" then
    return out
  end
  local packName = Data.typePack[typ]
  local pack = packName and Data.packs[packName]
  -- the pack's plain name table (format A); an older pack without one is searched record by record
  local names = pack and pack.names and pack.names[typ]
  if not names and pack and pack[typ] then
    local nameIndex
    for i, field in ipairs(pack.schema[typ]) do
      if field == "name" then
        nameIndex = i
      end
    end
    if not nameIndex then
      return out
    end
    names = {}
    for id, raw in pairs(pack[typ]) do
      local row = decodeRow(raw, typ .. ":" .. tostring(id))
      names[id] = row and row[nameIndex] or nil
    end
  end
  local n = 0
  local seen = {}
  local function scan(list, store)
    for id, name in pairs(list) do
      n = n + 1
      if yield and n % SEARCH_SLICE == 0 then
        yield()
      end
      if type(name) == "string" and not seen[id] then
        local low = string.lower(name)
        local score
        if low == text then
          score = 1
        elseif string.sub(low, 1, #text) == text then
          score = 0.9
        elseif string.find(low, text, 1, true) then
          score = 0.7
        end
        if score then
          seen[id] = true
          out[#out + 1] = { id = id, name = name, score = score, stored = store or nil }
        end
      end
    end
  end
  if names then
    scan(names)
  end
  -- the names the client answered in this or an earlier session (Names.Store, R4): on retail
  -- the log quests and everything looked at become searchable this way
  if Data.Names then
    scan(Data.Names.Store(typ), true)
  end
  table.sort(out, function(a, b)
    if a.score ~= b.score then
      return a.score > b.score
    end
    return a.name < b.name
  end)
  for i = #out, limit + 1, -1 do
    out[i] = nil
  end
  return out
end

function service:Spawns(ref)
  local typ, id = B.Entity.Parse(ref)
  local rec = typ and record(typ, id)
  if not rec then
    return {}
  end
  return spawns(rec)
end

function service:Index(name, key)
  local idx = index(name)
  if key == nil then
    return idx
  end
  return idx and idx[key] or nil
end

-- Every id of a type in ascending order (built once per pack load); empty when the pack is not loaded.
Data.allIDs = {}
function service:Each(typ)
  local ids = Data.allIDs[typ]
  if ids then
    return ids
  end
  ids = {}
  local packName = Data.typePack[typ]
  local pack = packName and Data.packs[packName]
  if pack and pack[typ] then
    for id in pairs(pack[typ]) do
      ids[#ids + 1] = id
    end
    table.sort(ids, function(a, b)
      if type(a) ~= type(b) then
        return type(a) < type(b)
      end
      return a < b
    end)
  end
  Data.allIDs[typ] = ids
  return ids
end

function service:PackLoaded(name)
  return Data.loaded[name] == true
end

function service:LoadPack(name)
  return Data.LoadPack(name)
end

function service:RequestPack(name)
  B.Jobs:Run(mod, "load-" .. tostring(name), function()
    Data.LoadPack(name)
  end)
end

-- The words of a record's kind (ADR 0016): the label a player reads and the group a list filters
-- by, both English keys for the locale. Object kinds a player looks for are their own group; the
-- technical ones (doors, levers, traps, chairs, ...) read as themselves but group as "Other". The
-- same for node kinds and NPC services and ranks. nil for no kind.
local KINDS = {
  object = {
    ["quest object"] = "Quest object",
    chest = "Chest",
    signpost = "Signpost",
    ["fire and forge"] = "Fire and forge",
    book = "Book",
    usable = "Usable",
    mailbox = "Mailbox",
    ["meeting stone"] = "Meeting stone",
    portal = "Portal",
    ["fishing pool"] = "Fishing pool",
    ["auction house"] = "Auction house",
  },
  node = { herb = "Herb", ore = "Ore", fish = "Fishing pool", treasure = "Treasure" },
  npc = {
    questgiver = "Quest giver",
    trainer = "Trainer",
    vendor = "Vendor",
    repair = "Repair",
    flightmaster = "Flight master",
    innkeeper = "Innkeeper",
    banker = "Banker",
    battlemaster = "Battlemaster",
    auctioneer = "Auctioneer",
    stablemaster = "Stable master",
    elite = "Elite",
    rareelite = "Rare elite",
    boss = "Boss",
    rare = "Rare##rank",
  },
}
Data.KINDS = KINDS

function service:Kind(typ, kind)
  if kind == nil or kind == "" then
    return nil, nil
  end
  local group = KINDS[typ] and KINDS[typ][kind]
  if group then
    return L[group], group
  end
  local word = tostring(kind)
  return L[string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2)], "Other"
end

function service:Meta()
  local packs = {}
  for name, pack in pairs(Data.packs) do
    packs[name] = { version = pack.version, build = pack.build, client = pack.client, sources = pack.sources }
  end
  local foreign = {}
  for name, client in pairs(Data.foreign) do
    foreign[name] = client
  end
  return { client = B.Client, packs = packs, foreign = foreign }
end

-- One line for the settings hub: which loaded packs were built for another client, or nil.
function Data.ForeignNote()
  local names = {}
  for name, client in pairs(Data.foreign) do
    names[#names + 1] = ("%s (%s)"):format(name, client)
  end
  if #names == 0 then
    return nil
  end
  table.sort(names)
  return ("%s: %s. %s"):format(
    L["Packs built for another client"],
    table.concat(names, ", "),
    L["Their ids and places belong to that client; install the packs for this one."]
  )
end

-- ---------------------------------------------------------------------------------------------
-- Registrations: entity types, search provider, data-only detail sections
-- ---------------------------------------------------------------------------------------------

local function zoneName(mapID)
  local z = mapID and record("zone", mapID)
  return z and z.name or nil
end

local SUMMARY = {
  npc = function(r)
    local parts = {}
    if r.level then
      parts[#parts + 1] = L["Level"] .. " " .. tostring(r.level)
    end
    if r.flags == "elite" then
      parts[#parts + 1] = L["elite"]
    end
    local zone = zoneName(r.zone)
    if zone then
      parts[#parts + 1] = zone
    end
    return #parts > 0 and table.concat(parts, ", ") or nil
  end,
  quest = function(r)
    local zone = zoneName(r.zone)
    return (r.level and (L["Level"] .. " " .. r.level) or "") .. (zone and (", " .. zone) or "")
  end,
  zone = function(r)
    local parts = {}
    if r.levelLo and r.levelHi then
      parts[#parts + 1] = L["Level"] .. " " .. r.levelLo .. "-" .. r.levelHi
    end
    local parent = r.parent and zoneName(r.parent)
    if parent then
      parts[#parts + 1] = parent
    end
    return #parts > 0 and table.concat(parts, ", ") or nil
  end,
  item = function(r)
    local parts = {}
    if r.level then
      parts[#parts + 1] = L["Item level"] .. " " .. r.level
    end
    if r.reqLevel then
      parts[#parts + 1] = L["Requires level"] .. " " .. r.reqLevel
    end
    if r.foreverNew then
      parts[#parts + 1] = L["new in Forever"]
    end
    return #parts > 0 and table.concat(parts, ", ") or nil
  end,
  recipe = function(r)
    return (r.profession or "") .. (r.skill and (" " .. r.skill) or "")
  end,
  node = function(r)
    return (r.profession or "") .. (r.skill and (" " .. r.skill) or "")
  end,
  -- what the object is and where (ADR 0016: the kinds have names)
  object = function(r)
    local parts = {}
    local kind = service:Kind("object", r.kind)
    if kind then
      parts[#parts + 1] = kind
    end
    local zone = zoneName(r.zone)
    if zone then
      parts[#parts + 1] = zone
    end
    return #parts > 0 and table.concat(parts, ", ") or nil
  end,
}

-- The places of a quest:
-- the giver places (else the givers' own first places), the objective spots per map, the
-- hand-in places (else the takers'); `kind` says which. Built once per record.
local function questPlaces(r)
  if r._places then
    return r._places
  end
  local out, seen = {}, {}
  local function add(map, x, y, kind, src)
    local key = map .. ":" .. math.floor(x * 1000) .. ":" .. math.floor(y * 1000)
    if map and x and y and not seen[key] then
      seen[key] = true
      out[#out + 1] = { map = map, x = x, y = y, kind = kind, src = src }
    end
  end
  local function entities(refs, kind)
    for _, ref in ipairs(refs or {}) do
      local loc = B:Entity(ref):Locations()[1]
      if loc then
        add(loc.map, loc.x, loc.y, kind, loc.src)
      end
    end
  end
  if r.startPlaces and #r.startPlaces > 0 then
    for _, p in ipairs(r.startPlaces) do
      add(p[1], p[2], p[3], "giver", p[4])
    end
  else
    entities(r.starts, "giver")
  end
  for map, list in pairs(r.spots or {}) do
    for _, s in ipairs(list) do
      add(map, s[1], s[2], "objective", "data")
    end
  end
  if r.endPlaces and #r.endPlaces > 0 then
    for _, p in ipairs(r.endPlaces) do
      add(p[1], p[2], p[3], "turnin", p[4])
    end
  else
    entities(r.ends, "turnin")
  end
  r._places = out
  return out
end

local ICON_KIND = {
  npc = "mob",
  quest = "quest",
  object = "treasure",
  item = "item",
  zone = "zone",
  node = "herb",
  flightpath = "flight",
  transport = "route",
}

local function registerTypes(self)
  for _, typ in ipairs(TYPES) do
    B:RegisterEntityType(self, {
      type = typ,
      priority = 100,
      -- the record's name, else the client's (Names.lua: retail packs carry no quest titles)
      name = function(id)
        local r = record(typ, id)
        if r and r.name then
          return r.name
        end
        return Data.Names and Data.Names.Get(typ, id) or nil
      end,
      icon = function(id)
        local r = record(typ, id)
        if r and r.icon then
          return r.icon
        end
        if typ == "item" and type(id) == "number" then
          -- the item's own icon from the client; a
          -- miss asks the client once, ITEM_DATA_LOAD_RESULT refreshes the entities (Names.lua)
          if Data.Names then
            Data.Names.Get("item", id)
          end
          local info = B.Compat.GetItemInfo(id)
          if info and info.icon then
            return info.icon
          end
        end
        return B.UI.IconTexture(ICON_KIND[typ] or "other")
      end,
      summary = function(id)
        local r = record(typ, id)
        if not r then
          return nil
        end
        local fn = SUMMARY[typ]
        return fn and fn(r) or nil
      end,
      locations = function(id)
        local r = record(typ, id)
        if not r then
          return nil
        end
        if typ == "quest" then
          return questPlaces(r)
        end
        return spawns(r)
      end,
      fields = function(id)
        return record(typ, id)
      end,
    })
  end
end

local function overviewRows(ref)
  local typ, id = B.Entity.Parse(ref)
  local r = typ and record(typ, id)
  if not r then
    return nil
  end
  local rows = {}
  if r.level then
    rows[#rows + 1] = { text = L["Level"], value = r.level, valueKind = "number" }
  end
  if r.minLevel then
    rows[#rows + 1] = { text = L["Requires level"], value = r.minLevel, valueKind = "number" }
  end
  local zone = zoneName(r.zone)
  if zone then
    rows[#rows + 1] = { text = L["Zone"] .. ": " .. zone, ref = "zone:" .. r.zone }
  end
  if r.flags then
    -- an NPC carries one flag ("elite"), a quest a list ({ "repeatable", "dungeon" }): a table as
    -- the row text stopped the Browser's tree at this row in game (22.10.2026, "CLUCK!")
    local flags = type(r.flags) == "table" and r.flags or { r.flags }
    local words = {}
    for _, flag in ipairs(flags) do
      words[#words + 1] = L[tostring(flag)]
    end
    if #words > 0 then
      rows[#rows + 1] = { text = table.concat(words, ", ") }
    end
  end
  return rows
end

local function spawnRows(ref)
  local list = service:Spawns(ref)
  if #list == 0 then
    return nil
  end
  local rows = {}
  for _, s in ipairs(list) do
    rows[#rows + 1] = {
      text = string.format("%s  %.0f, %.0f", zoneName(s.map) or tostring(s.map), s.x * 100, s.y * 100),
      ref = ref,
    }
  end
  return rows
end

-- No source note in the rows ("classic" in a column adds nothing for
-- the player; CLAUDE.md section 8 changed). The data keeps its `src` labels.
local CLASSIC_NOTE = function()
  return nil
end

local function itemName(id)
  local r = record("item", id)
  return r and r.name or (L["Item"] .. " " .. tostring(id))
end

-- NPC "Sells": vendor rows [item, stack price, stack, limited, src]; unit price only when the stack is known
local function vendorRows(ref)
  local typ, id = B.Entity.Parse(ref)
  local r = typ == "npc" and record("npc", id)
  if not (r and r.vendor) then
    return nil
  end
  local rows = {}
  for _, v in ipairs(r.vendor) do
    local item, price, stack, limited, src = v[1], v[2], v[3], v[4], v[5]
    local unit = (price and stack and stack > 0) and math.floor(price / stack + 0.5) or nil
    rows[#rows + 1] = {
      text = itemName(item)
        .. (stack and stack > 1 and (" x" .. stack) or "")
        .. (limited and (" " .. L["(limited)"]) or ""),
      ref = "item:" .. item,
      icon = B:Entity("item:" .. item):Icon(),
      value = unit or price,
      valueKind = "money",
      note = (not unit and price) and "per stack" or CLASSIC_NOTE(src),
    }
  end
  return rows
end

-- NPC "Teaches": trainer rows [spell, name, cost, skill, level, item, src]
local function trainerRows(ref)
  local typ, id = B.Entity.Parse(ref)
  local r = typ == "npc" and record("npc", id)
  if not (r and r.trainer) then
    return nil
  end
  local rows = {}
  for _, t in ipairs(r.trainer) do
    local req = {}
    if t[5] and t[5] > 0 then
      req[#req + 1] = L["level"] .. " " .. t[5]
    end
    if t[4] and t[4] > 0 then
      req[#req + 1] = L["skill"] .. " " .. t[4]
    end
    rows[#rows + 1] = {
      text = (t[2] or (L["Spell"] .. " " .. tostring(t[1])))
        .. (#req > 0 and (" (" .. table.concat(req, ", ") .. ")") or ""),
      ref = t[6] and t[6] > 0 and ("item:" .. t[6]) or nil,
      value = t[3],
      valueKind = "money",
      note = CLASSIC_NOTE(t[7]),
    }
  end
  return rows
end

-- NPC/object "Drops": loot rows [item, chance]; lootSrc "classic" (CMaNGOS) or "tdb" (retail)
local function lootRows(ref)
  local typ, id = B.Entity.Parse(ref)
  local r = (typ == "npc" or typ == "object") and record(typ, id)
  if not (r and r.loot) then
    return nil
  end
  local rows = {}
  for _, l in ipairs(r.loot) do
    -- a small table (ADR 0018 D): the chance in the note column, the item's worth as the value
    rows[#rows + 1] = {
      text = itemName(l[1]),
      ref = "item:" .. l[1],
      icon = B:Entity("item:" .. l[1]):Icon(),
      note = B.UI.FormatValue(l[2], "percent"),
      chance = l[2],
    }
  end
  return rows
end

-- Item "Sources": drops [ref, chance, questDrop], vendors (from the npc records), made by
local function sourceRows(ref)
  local typ, id = B.Entity.Parse(ref)
  local r = typ == "item" and record("item", id)
  if not r then
    return nil
  end
  local rows = {}
  for _, d in ipairs(r.drops or {}) do
    local e = B:Entity(d[1])
    -- dropped by: the dropper's icon, the chance in the value column (ADR 0018 D)
    rows[#rows + 1] = {
      text = (e:Name() or d[1]) .. (d[3] and (" " .. L["(quest drop)"]) or ""),
      ref = d[1],
      icon = e:Icon(),
      value = d[2],
      valueKind = "percent",
    }
  end
  if r.madeBy then
    rows[#rows + 1] =
      { text = L["Made by"] .. " " .. tostring(r.madeBy[1]) .. " (" .. tostring(r.madeBy[2]) .. ")" }
  end
  if r.sell then
    rows[#rows + 1] = { text = L["Vendor sell price"], value = r.sell, valueKind = "money" }
  end
  return rows
end

-- Recipe "Reagents": [item, count]
local function reagentRows(ref)
  local typ, id = B.Entity.Parse(ref)
  local r = typ == "recipe" and record("recipe", id)
  if not (r and r.reagents) then
    return nil
  end
  local rows = {}
  for _, rg in ipairs(r.reagents) do
    rows[#rows + 1] = { text = itemName(rg[1]), ref = "item:" .. rg[1], value = rg[2], valueKind = "number" }
  end
  if r.item then
    rows[#rows + 1] = {
      text = L["Makes"] .. " " .. itemName(r.item) .. (r.count and r.count > 1 and (" x" .. r.count) or ""),
      ref = "item:" .. r.item,
    }
  end
  return rows
end

-- The places of a zone that matter on the way (ADR 0013, the zone page): flight master, inn, then
-- vendors, trainers and the rest of the service NPCs as folded groups, and the gathering nodes by
-- profession. From the byZone indexes; an NPC's flags list names its services.
local PLACE_GROUPS = {
  { "flightmaster", "Flight master", "flight", false },
  { "innkeeper", "Inn", "innkeeper", false },
  { "vendor", "Vendors", "vendor", true },
  { "trainer", "Trainers", "trainer", true },
  { "repair", "Repair", "repair", true },
  { "banker", "Bank", "banker", true },
  { "auctioneer", "Auction house", "auctioneer", true },
  { "stablemaster", "Stable master", "service", true },
}

local function flagsOf(r)
  local flags = r.flags
  if type(flags) ~= "table" then
    flags = flags and { flags } or {}
  end
  local set = {}
  for _, f in ipairs(flags) do
    set[f] = true
  end
  return set
end

local function placeRows(ref)
  local _, map = B.Entity.Parse(ref)
  map = tonumber(map)
  if not map then
    return nil
  end
  local byFlag = {}
  for id in service:ByZone("npc", map) do
    local r = record("npc", id)
    if r then
      local set = flagsOf(r)
      for _, g in ipairs(PLACE_GROUPS) do
        if set[g[1]] then
          local list = byFlag[g[1]]
          if not list then
            list = {}
            byFlag[g[1]] = list
          end
          local text = r.name or ("npc " .. id)
          if r.subname then
            text = text .. "  " .. S.H.muted .. r.subname .. "|r"
          end
          list[#list + 1] = { ref = "npc:" .. id, text = text, icon = B.UI.IconTexture(g[3]) }
        end
      end
    end
  end
  local rows = {}
  for _, g in ipairs(PLACE_GROUPS) do
    local list = byFlag[g[1]]
    if list then
      table.sort(list, function(a, b)
        return a.text < b.text
      end)
      if g[4] or #list > 1 then
        rows[#rows + 1] = {
          text = L[g[2]] .. "  " .. S.H.muted .. #list .. "|r",
          icon = B.UI.IconTexture(g[3]),
          children = list,
          collapsed = g[4],
        }
      else
        rows[#rows + 1] = list[1]
      end
    end
  end
  local byProfession, professions = {}, {}
  for id in service:ByZone("node", map) do
    local r = record("node", id)
    if r then
      local key = r.profession or L["Nodes"]
      local list = byProfession[key]
      if not list then
        list = {}
        byProfession[key] = list
        professions[#professions + 1] = key
      end
      list[#list + 1] =
        { ref = "node:" .. id, text = r.name or ("node " .. id), icon = B.UI.IconTexture("herb") }
    end
  end
  table.sort(professions)
  for _, key in ipairs(professions) do
    local list = byProfession[key]
    table.sort(list, function(a, b)
      return a.text < b.text
    end)
    rows[#rows + 1] = {
      text = L[key] .. "  " .. S.H.muted .. #list .. "|r",
      icon = B.UI.IconTexture("herb"),
      children = list,
      collapsed = true,
    }
  end
  return rows
end

-- "Near" (the Here column, C4): the service NPCs, mailboxes and gathering nodes of the zone by
-- distance from the player, the kind and the distance after the name. Built once per zone; the
-- zone change drops it (the distances are from the moment of the build).
local NODE_ICON = { ore = "mine", fish = "fish" }
local function nearRows(ref)
  local _, map = B.Entity.Parse(ref)
  map = tonumber(map)
  if not map then
    return nil
  end
  local continent, wx, wy = B.Coords.Player()
  local rows = {}
  local function add(entityRef, r, kindLabel, icon)
    local best
    if continent then
      for _, s in ipairs(spawns(r)) do
        if s.map == map then
          local c, x, y = B.Coords.ToWorld(s.map, s.x, s.y)
          if c == continent then
            local d = (x - wx) ^ 2 + (y - wy) ^ 2
            if not best or d < best then
              best = d
            end
          end
        end
      end
    end
    local yards = best and math.sqrt(best) or nil
    local words = kindLabel
    local dist = B.UI.Distance(yards)
    if dist then
      words = words .. ", " .. dist
    end
    rows[#rows + 1] = {
      id = "near:" .. entityRef,
      ref = entityRef,
      text = (r.name or entityRef) .. "  " .. S.H.muted .. words .. "|r",
      icon = icon,
      d = yards or math.huge,
    }
  end
  for id in service:ByZone("npc", map) do
    local r = record("npc", id)
    if r then
      local set = flagsOf(r)
      for _, g in ipairs(PLACE_GROUPS) do
        if set[g[1]] then
          add("npc:" .. id, r, L[g[2]], B.UI.IconTexture(g[3]))
          break
        end
      end
    end
  end
  for id in service:ByZone("object", map) do
    local r = record("object", id)
    if r and type(r.kind) == "string" and string.find(string.lower(r.kind), "mailbox", 1, true) then
      add("object:" .. id, r, L["Mailbox"], B.UI.IconTexture("service"))
    end
  end
  for id in service:ByZone("node", map) do
    local r = record("node", id)
    if r then
      add("node:" .. id, r, r.profession or L["Node"], B.UI.IconTexture(NODE_ICON[r.kind] or "herb"))
    end
  end
  if #rows == 0 then
    return nil
  end
  table.sort(rows, function(a, b)
    if a.d ~= b.d then
      return a.d < b.d
    end
    return a.text < b.text
  end)
  return rows
end

-- ---------------------------------------------------------------------------------------------
-- The guide gaps (23.10.2026: what AHSyncGuide showed, so it can be uninstalled): a gathering
-- node's tooltip, where to get an item, the monsters of a zone. Prices only through the worth
-- registry (Gold's provider), never from Gold itself.
-- ---------------------------------------------------------------------------------------------

-- The node a hovered object is: the node of the same id (retail: ItemDB keys nodes by object id),
-- else the node of the object's name in the pack (Forever: nodes are ForeverDB gather kinds; the
-- name is the pack's, never the tooltip's, which is a secret value on Forever 70532).
function Data.NodeOf(objectID)
  if not objectID then
    return nil
  end
  local direct = record("node", objectID)
  if direct then
    return objectID, direct
  end
  local obj = record("object", objectID)
  local name = obj and obj.name and string.lower(obj.name)
  if not name then
    return nil
  end
  if not Data.nodeByName then
    local byName = {}
    for _, id in ipairs(service:Each("node")) do
      local r = record("node", id)
      local n = r and r.name and string.lower(r.name)
      if n and byName[n] == nil then
        byName[n] = id
      end
    end
    Data.nodeByName = byName
  end
  local id = Data.nodeByName[name]
  return id, id and record("node", id) or nil
end

-- Gives (the item and its worth), the skill, the places on the player's map.
local function nodeTooltipRows(ref)
  local typ, id = B.Entity.Parse(ref)
  local r
  if typ == "node" then
    r = record("node", id)
  else
    r = select(2, Data.NodeOf(id))
  end
  if not r then
    return nil
  end
  local rows = {}
  if r.item then
    local item = B:Entity("item:" .. r.item)
    local worth = item:Worth()
    rows[#rows + 1] = {
      text = L["Gives"] .. ": " .. (item:Name() or ("item " .. r.item)),
      icon = item:Icon(),
      value = worth and worth.copper or nil,
      valueKind = "money",
    }
  end
  if r.profession then
    rows[#rows + 1] = { text = r.profession .. (r.skill and (" " .. r.skill) or "") }
  end
  local map = B.Coords.PlayerMap()
  if map then
    local n = 0
    for _, s in ipairs(spawns(r)) do
      if s.map == map then
        n = n + 1
      end
    end
    if n > 0 then
      rows[#rows + 1] = { text = string.format(L["%d places in %s"], n, zoneName(map) or ("map " .. map)) }
    end
  end
  return #rows > 0 and rows or nil
end

-- Where to get an item, by zone: the monsters that drop it and the nodes that give it, with the
-- number of places; the player's zone first, then the zone with the most places.
local function whereRows(ref)
  local _, itemID = B.Entity.Parse(ref)
  local item = record("item", itemID)
  local zones, order = {}, {}
  local function add(map, why, places)
    if not map then
      return
    end
    local z = zones[map]
    if not z then
      z = { map = map, why = {}, places = 0 }
      zones[map] = z
      order[#order + 1] = z
    end
    if #z.why < 3 then
      z.why[#z.why + 1] = why
    end
    z.places = z.places + places
  end
  for _, d in ipairs(item and item.drops or {}) do
    local typ, id = B.Entity.Parse(d[1])
    local r = typ and record(typ, id)
    if r and (typ == "npc" or typ == "object") then
      local per = {}
      for _, s in ipairs(spawns(r)) do
        per[s.map] = (per[s.map] or 0) + 1
      end
      if not next(per) and r.zone then
        per[r.zone] = 0
      end
      local chance = d[2] and string.format(" %s %%", d[2]) or ""
      for map, n in pairs(per) do
        add(map, (r.name or d[1]) .. chance, n)
      end
    end
  end
  for _, id in ipairs(service:Each("node")) do
    local r = record("node", id)
    if r and r.item == itemID then
      local per = {}
      for _, s in ipairs(spawns(r)) do
        per[s.map] = (per[s.map] or 0) + 1
      end
      for map, n in pairs(per) do
        add(map, (r.profession or L["Node"]) .. ": " .. (r.name or ""), n)
      end
    end
  end
  if #order == 0 then
    return nil
  end
  local here = B.Coords.PlayerMap()
  table.sort(order, function(a, b)
    if (a.map == here) ~= (b.map == here) then
      return a.map == here
    end
    if a.places ~= b.places then
      return a.places > b.places
    end
    return a.map < b.map
  end)
  local rows = {}
  for _, z in ipairs(order) do
    local zr = record("zone", z.map)
    local band = zr
        and zr.levelLo
        and zr.levelHi
        and ("  " .. S.H.muted .. zr.levelLo .. "-" .. zr.levelHi .. "|r")
      or ""
    rows[#rows + 1] = {
      text = (zoneName(z.map) or ("map " .. z.map)) .. band,
      meta = table.concat(z.why, ", "),
      ref = "zone:" .. z.map,
      icon = B.UI.IconTexture("zone"),
      value = z.places > 0 and z.places or nil,
      valueKind = "number",
    }
  end
  return rows
end

-- An NPC's flags beyond its rank (elite, rare, boss are no service: Hogger is a monster).
local RANK_FLAGS = { elite = true, rareelite = true, rare = true, boss = true }
local function hasService(r)
  for flag in pairs(flagsOf(r)) do
    if not RANK_FLAGS[flag] then
      return true
    end
  end
  return false
end

-- The monsters of a zone: NPCs without a service, a faction or a quest to give, by level; their
-- rows carry the worth per kill through the worth registry when Gold is there.
local function monsterRows(ref)
  local _, map = B.Entity.Parse(ref)
  map = tonumber(map)
  if not map then
    return nil
  end
  local list, seen = {}, {}
  for id in service:ByZone("npc", map) do
    local r = record("npc", id)
    if r and r.name and r.level and not r.faction and not hasService(r) and not seen[r.name] then
      seen[r.name] = true
      list[#list + 1] = { id = id, r = r }
    end
  end
  table.sort(list, function(a, b)
    if a.r.level ~= b.r.level then
      return a.r.level < b.r.level
    end
    return a.r.name < b.r.name
  end)
  local rows = {}
  for _, m in ipairs(list) do
    local lvl = m.r.levelMax and (m.r.level .. "-" .. m.r.levelMax) or tostring(m.r.level)
    rows[#rows + 1] = {
      text = m.r.name .. "  " .. S.H.muted .. lvl .. "|r",
      ref = "npc:" .. m.id,
      icon = B.UI.IconTexture("mob"),
    }
  end
  return #rows > 0 and rows or nil
end

local function registerSections(self)
  local function section(def)
    B:RegisterDetailSection(self, def)
  end
  section({
    id = "data.node",
    title = L["Gathering"],
    types = { "object", "node" },
    order = 13,
    build = function()
      return nil -- tooltip lines only; the page has Overview and Locations
    end,
    tooltip = { max = 3, build = nodeTooltipRows },
  })
  section({
    id = "data.where",
    title = L["Where to get it"],
    types = { "item" },
    order = 21,
    block = { wide = true, limit = 6 },
    twoLine = true, -- the zone, then what gives the item there
    invalidateOn = { "BASTIANS_PLAYER_MOVED_ZONE" },
    build = whereRows,
  })
  section({
    id = "data.monsters",
    title = L["Monsters"],
    types = { "zone" },
    order = 30,
    block = { limit = 10 },
    build = monsterRows,
  })
  section({
    id = "data.near",
    title = L["Near"],
    types = { "zone" },
    order = 97,
    here = { order = 3, limit = 8, only = true },
    invalidateOn = { "BASTIANS_PLAYER_MOVED_ZONE" },
    build = nearRows,
  })
  -- the dossier blocks (C2, ADR 0014): Overview and Places show more rows before "+N more", the
  -- lists eight; the "zone" link leads to the entity's zone page
  section({
    id = "data.places",
    title = L["Places"],
    types = { "zone" },
    order = 12,
    block = { wide = true, limit = 12 },
    build = placeRows,
  })
  section({
    id = "data.overview",
    title = L["Overview"],
    types = "*",
    order = 10,
    block = { limit = 12 },
    build = overviewRows,
  })
  section({
    id = "data.spawns",
    title = L["Locations"],
    types = { "npc", "object", "node" },
    order = 15,
    build = spawnRows,
  })
  section({
    id = "data.vendor",
    title = L["Sells"],
    types = { "npc" },
    order = 30,
    block = { limit = 8, table = true },
    build = vendorRows,
  })
  section({
    id = "data.trainer",
    title = L["Teaches"],
    types = { "npc" },
    order = 31,
    block = { limit = 8 },
    build = trainerRows,
  })
  section({
    id = "data.loot",
    title = L["Drops"],
    types = { "npc", "object" },
    order = 40,
    block = { limit = 8, table = true },
    build = lootRows,
  })
  section({
    id = "data.sources",
    title = L["Sources"],
    types = { "item" },
    order = 20,
    block = { limit = 8, table = true },
    build = sourceRows,
    tooltip = { max = 2 },
  })
  section({
    id = "data.reagents",
    title = L["Reagents"],
    types = { "recipe" },
    order = 20,
    build = reagentRows,
  })
  section({
    id = "data.zone",
    title = L["Zone"],
    types = { "npc", "object", "quest", "node", "item" },
    order = 90,
    link = L["zone"],
    build = function(ref)
      local typ, id = B.Entity.Parse(ref)
      local r = record(typ, id)
      local zone = r and zoneName(r.zone)
      if not zone then
        return nil
      end
      return { { ref = "zone:" .. r.zone, text = zone, icon = B.UI.IconTexture("zone") } }
    end,
  })
end

local function registerSearch(self)
  B:RegisterSearchProvider(self, {
    id = "data.names",
    label = L["World database"],
    priority = 100,
    search = function(query, limit, yield)
      local out = {}
      for _, typ in ipairs(TYPES) do
        for _, hit in ipairs(service:Find(typ, query, limit, yield)) do
          out[#out + 1] =
            { ref = B.Entity.Make(typ, hit.id), label = hit.name, score = hit.score, note = L[typ] }
        end
      end
      return out
    end,
  })
end

-- ---------------------------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------------------------

mod = B:NewModule("Data", {
  addon = ADDON,
  title = L["Data"],
  apiVersion = 1,
  db = "BastiansDataDB",
  charDb = "BastiansDataCharDB",
  defaults = { profile = {}, global = { loadLog = {}, names = {} } }, -- names: Names.lua's store
  options = {
    {
      type = "note",
      text = function()
        return Data.ForeignNote() or L["Packs are built for this client."]
      end,
    },
  },
  OnEnable = function(self)
    B:ProvideService(self, "data", service, { priority = 100 })
    registerTypes(self)
    registerSections(self)
    registerSearch(self)
    if Data.Names then
      Data.Names.Attach(self)
    end
    -- a module that enables later (load-on-demand app, user switch) may want more packs
    self:On("BASTIANS_MODULE_STATE", function(me, _, _, enabled)
      if enabled then
        me:Coalesce("load-packs", 0.1, loadWantedPacks)
      end
    end)
    loadWantedPacks(self)
  end,
})
ns.mod = mod
