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
-- area: the subzones (data.md "Areas"), Crystal Lake, Goldshire, ...
local TYPES = {
  "quest",
  "npc",
  "object",
  "item",
  "recipe",
  "zone",
  "area",
  "node",
  "flightpath",
  "transport",
  "entrance",
  "dungeon",
}
local SEARCH_SLICE = 200 -- records between yields in the search provider

-- The game data in the client's language (data.md "Game data in other languages", ADR 0033): the
-- pack `text_<locale>` carries `<type>_<locale>` records with the local name (and an NPC's
-- subname, a quest's objectives); esMX reads the Spanish pack. nil on an English
-- client, and on ruRU and ptBR (04.11.2026: no pack is built for them yet, they read the English
-- texts without a warning).
local LOCALE_PACKS = {
  deDE = "deDE",
  frFR = "frFR",
  esES = "esES",
  esMX = "esES",
  koKR = "koKR",
  zhCN = "zhCN",
  zhTW = "zhTW",
}
local LOCALIZED = { quest = true, npc = true, item = true, object = true }
local QUEST_TEXTS = { "details", "objectives", "offer", "progress" }
local CLIENT_NAMED = { item = true, quest = true, recipe = true } -- the client names them in its language
Data.locale = LOCALE_PACKS[type(GetLocale) == "function" and GetLocale() or ""]
Data.localePack = Data.locale and PACK_ADDON["text_" .. Data.locale] and ("text_" .. Data.locale) or nil

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

-- Called by Generated/Downloads.lua (tools/data_update.py, the daily edition): the CurseForge
-- download counts { at = "YYYY-MM-DD", suite = n, data = n } when the edition was built, for the
-- About page. Without the file (a release, a build without the read API) they stay unknown.
function Data.RegisterDownloads(info)
  if type(info) == "table" and type(info.suite) == "number" and type(info.data) == "number" then
    Data.downloads = { at = info.at, suite = info.suite, data = info.data }
  end
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
  -- the game data in the client's language, with whatever else is wanted (ADR 0033)
  if #order > 0 and Data.localePack and not wanted[Data.localePack] then
    order[#order + 1] = Data.localePack
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
  local loc = Data.locale
  if loc and (LOCALIZED[typ] or typ == "questText") then
    -- the client's language over the English record; the English name stays as nameEN
    local l = record((typ == "questText" and "quest" or typ) .. "_" .. loc, id)
    if l and typ == "questText" then
      -- the texts the source has (CMaNGOS: German and Chinese all four; QuestieDB the objectives)
      for _, field in ipairs(QUEST_TEXTS) do
        if l[field] then
          rec[field .. "EN"], rec[field] = rec[field], l[field]
        end
      end
    elseif l then
      if l.name then
        rec.nameEN, rec.name = rec.name, l.name
      end
      if l.subname then
        rec.subname = l.subname
      end
    end
  elseif loc and (typ == "zone" or typ == "area") then
    -- zones and subzones: the client names them in its own language (no pack needed)
    local name = typ == "zone" and B.Compat.MapName(id) or B.Compat.AreaName(id)
    if name and name ~= rec.name then
      rec.nameEN, rec.name = rec.name, name
    end
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

-- { {map, x, y, src, wz, r}, ... } positional -> { map =, x =, y =, src =, wz =, r = } (cached on
-- the record); `wz` is the height in world yards where the source has one (CMaNGOS, TaxiNodes),
-- `r` the radius in yards, the row's own or the record's (an area's, data.md "Areas")
local function spawns(rec)
  if rec._spawns then
    return rec._spawns
  end
  local out = {}
  for _, s in ipairs(rec.spawns or {}) do
    out[#out + 1] = { map = s[1], x = s[2], y = s[3], src = s[4], wz = s[5], r = s[6] or rec.r }
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

-- An area's zone and a test for map points inside it ("the subzone
-- information is quite limited ... I would expect the same information as in the main zone"):
-- the area's world place and radius (data.md "Areas") with about a chunk of slack, the radius
-- being that of a disc as large as its chunks. -> uiMapID, inside(map, x, y), or nil.
Data.AREA_SLACK = 35 -- yards
function service:AreaScope(id)
  local r = record("area", tonumber(id))
  if not (r and r.zone and r.wx and r.wy and r.continent ~= nil) then
    return nil
  end
  local reach = (r.r or 0) + Data.AREA_SLACK
  local reach2 = reach * reach
  return r.zone,
    function(map, x, y)
      if not (map and x and y) then
        return false
      end
      local c, wx, wy = B.Coords.ToWorld(map, x, y)
      return c == r.continent and (wx - r.wx) ^ 2 + (wy - r.wy) ^ 2 <= reach2
    end
end

-- The name of a record without asking the client: the pack's, else the one the client answered in
-- this or an earlier session (Names' store); nil when neither knows it. For long lists, where a
-- client request per row would flood the server (the Browser's quest list showed numbers on
-- retail, the retail packs carry no quest titles).
function service:KnownName(typ, id)
  local r = record(typ, id)
  if r and r.name then
    return r.name
  end
  local names = Data.Names
  local k = typ .. ":" .. tostring(id)
  local cached = names and names.cache[k]
  if cached then
    return cached
  end
  local stored = names and names.Store(typ)[id]
  return stored or nil
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
-- The zones' and subzones' names in the client's language (record() takes them from the client),
-- built once per session on the first search of the type: { [id] = name }.
local placeNames = {}
local function clientPlaceNames(typ, pack)
  if not placeNames[typ] then
    local out = {}
    for id in pairs(pack[typ] or {}) do
      local r = record(typ, id)
      if r and r.nameEN then
        out[id] = r.name
      end
    end
    placeNames[typ] = out
  end
  return placeNames[typ]
end

-- Does the record have every kind word (`type:vendor`)?
local function kindOk(typ, id, kinds)
  local words = service:KindWords(typ, id)
  if not words then
    return false
  end
  for _, kind in ipairs(kinds) do
    local found = false
    for _, w in ipairs(words) do
      if string.find(w, kind, 1, true) then
        found = true
        break
      end
    end
    if not found then
      return false
    end
  end
  return true
end

-- `text` a search text or a compiled query (ADR 0045: the suite's search syntax); a query's
-- `kinds` keep only records of those kinds.
function service:Find(typ, text, limit, yield)
  local q = B.Query.Of(text)
  limit = limit or 20
  local out = {}
  if q.empty then
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
        -- the name first (a plain find), the kind only for the names that match: a kind means
        -- decoding the record
        local score = q:Score(name)
        if score and q.kinds and not kindOk(typ, id, q.kinds) then
          score = nil
        end
        if score then
          seen[id] = true
          out[#out + 1] = { id = id, name = name, score = score, stored = store or nil }
        end
      end
    end
  end
  -- the client's language first, so a hit shows the local name; the English one still finds it
  local loc = Data.locale
  local localPack = loc and Data.localePack and Data.packs[Data.localePack]
  local localNames = localPack and localPack.names and localPack.names[typ .. "_" .. loc]
  if localNames then
    scan(localNames)
  end
  if loc and pack and (typ == "zone" or typ == "area") then
    scan(clientPlaceNames(typ, pack)) -- the client's names of zones and subzones
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

-- Whether the type has any record: true or false once its pack is loaded, nil before (unknown,
-- not "none"). Cheap: it builds nothing (the Browser hides a list without rows, ADR 0054 B14).
function service:Any(typ)
  local packName = Data.typePack[typ]
  if not (packName and Data.loaded[packName]) then
    return nil
  end
  local pack = Data.packs[packName]
  return pack ~= nil and pack[typ] ~= nil and next(pack[typ]) ~= nil
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

-- The kind words of a record, lower case (the search's `type:vendor`, ADR 0045): its flags or
-- kind, their group and their label; nil for a record without one.
function service:KindWords(typ, id)
  local r = record(typ, id)
  local flags = r and (r.flags or r.kind)
  if flags == nil then
    return nil
  end
  if type(flags) ~= "table" then
    flags = { flags }
  end
  local out = {}
  for _, f in ipairs(flags) do
    out[#out + 1] = string.lower(tostring(f))
    local label, group = service:Kind(typ, f)
    if group then
      out[#out + 1] = string.lower(group)
    end
    if label then
      out[#out + 1] = string.lower(label)
    end
  end
  return out
end

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
  return { client = B.Client, packs = packs, foreign = foreign, downloads = Data.downloads }
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
    -- a trainer says what it trains: its subname, and how many it
    -- teaches where the pack lists them (Forever; the retail sources carry no trainer lists)
    local trade = Data.Poi and Data.Poi.ServiceWords(r)
    if trade then
      parts[#parts + 1] = trade
      if type(r.trainer) == "table" and #r.trainer > 0 then
        parts[#parts + 1] = string.format(L["teaches %d"], #r.trainer)
      end
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
  -- a subzone (data.md "Areas"): the zone it lies in
  area = function(r)
    return zoneName(r.zone)
  end,
  -- an instance entrance (ADR 0026, places table): which door, the level it asks, the zone
  entrance = function(r)
    local parts = { L["Instance entrance"] }
    if r.label then
      parts[#parts + 1] = r.label
    end
    if r.level and r.level > 0 then
      parts[#parts + 1] = L["Requires level"] .. " " .. r.level
    end
    local zone = zoneName(r.zone)
    if zone then
      parts[#parts + 1] = zone
    end
    return table.concat(parts, ", ")
  end,
  -- a dungeon or raid (data.md "Dungeons"): its kind, level band, group size and zone
  dungeon = function(r)
    local parts = { r.kind == "raid" and L["Raid"] or L["Dungeon"] }
    if r.levelLo and r.levelHi then
      parts[#parts + 1] = L["Level"] .. " " .. r.levelLo .. "-" .. r.levelHi
    end
    if r.size then
      parts[#parts + 1] = string.format(L["%d players"], r.size)
    end
    local zone = zoneName(r.zone)
    if zone then
      parts[#parts + 1] = zone
    end
    return table.concat(parts, ", ")
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

-- The sheet's lead (ADR 0054): one or two sentences from the record alone, so they hold until
-- the data changes (the facade keeps them). A person says what they are, where they stand and
-- what they do for the player; a zone its quest levels; a dungeon its levels and its door. A type
-- without one keeps its summary as the lead.
local function counted(n, one, many)
  return n == 1 and one or string.format(many, n)
end

local LEAD = {
  npc = function(r, id)
    if service:IsMonster(r) then
      return nil
    end
    local parts = {}
    local zone = zoneName(r.zone)
    if r.subname and zone then
      parts[#parts + 1] = string.format(L["%s in %s."], r.subname, zone)
    elseif zone then
      parts[#parts + 1] = string.format(L["Stands in %s."], zone)
    end
    if type(r.vendor) == "table" and #r.vendor > 0 then
      parts[#parts + 1] = counted(#r.vendor, L["Sells one item."], L["Sells %d items."])
    end
    if type(r.trainer) == "table" and #r.trainer > 0 then
      parts[#parts + 1] = counted(#r.trainer, L["Teaches one skill."], L["Teaches %d skills."])
    end
    local quests = service:Index("quest.byGiver", "npc:" .. id)
    if type(quests) == "table" and #quests > 0 then
      parts[#parts + 1] = counted(#quests, L["Starts one quest."], L["Starts %d quests."])
    end
    return #parts > 0 and table.concat(parts, " ") or nil
  end,
  zone = function(r)
    if not (r.levelLo and r.levelHi) then
      return nil
    end
    local text = string.format(L["Quests from level %d to %d."], r.levelLo, r.levelHi)
    local parent = r.parent and zoneName(r.parent)
    text = parent and (text .. " " .. parent .. ".") or text
    if r.fishing then
      -- the Classic fishing skill the zone asks for (catalog review A3.6); nothing when unknown
      text = text .. " " .. string.format(L["Fishing from skill %d."], r.fishing)
    end
    return text
  end,
  dungeon = function(r)
    local parts = {}
    if r.levelLo and r.levelHi then
      local text = r.kind == "raid" and L["A raid for levels %d to %d."]
        or L["A dungeon for levels %d to %d."]
      parts[#parts + 1] = string.format(text, r.levelLo, r.levelHi)
    end
    local zone = zoneName(r.zone)
    if zone then
      parts[#parts + 1] = string.format(L["The door is in %s."], zone)
    end
    return #parts > 0 and table.concat(parts, " ") or nil
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
  area = "zone",
  node = "herb",
  flightpath = "flight",
  transport = "route",
  entrance = "keep",
  dungeon = "keep",
}

-- The reading order of each type's sheet (ADR 0054, core-contracts §7): the chapters a detail
-- section of any addon may name. A chapter without a title takes its first section's; the `tail`
-- ones come after a section that names no chapter. A monster reads in another order than a vendor.
local BOOK, NOTES = { id = "book", tail = true }, { id = "notes", tail = true }
local CHAPTERS = {
  npc = {
    { id = "sells" },
    { id = "teaches" },
    { id = "quests", title = L["Quests"] },
    { id = "drops" },
    { id = "where" },
    BOOK,
    NOTES,
  },
  monster = {
    { id = "drops" },
    { id = "quests", title = L["Wanted by quests"] },
    { id = "where" },
    BOOK,
    NOTES,
  },
  item = {
    { id = "get", title = L["Where to get it"] },
    { id = "use", title = L["What it is for"] },
    { id = "worth", title = L["Worth"] },
    { id = "yours", title = L["Yours"] },
    BOOK,
    NOTES,
  },
  object = {
    { id = "gathering" },
    { id = "where" },
    { id = "quests", title = L["Quests"] },
    { id = "drops" },
    BOOK,
    NOTES,
  },
  quest = {
    { id = "todo" },
    { id = "people", title = L["Giver and hand-in"] },
    { id = "rewards" },
    { id = "text" },
    NOTES,
  },
  zone = {
    { id = "quests", title = L["Your quests here"] },
    { id = "chains" }, -- Quests' "Chains here" (ADR 0055)
    { id = "places", title = L["Places"] },
    { id = "people" },
    { id = "monsters" },
    { id = "roads", title = L["Roads"] },
    BOOK,
    NOTES,
  },
  -- a dungeon reads in tabs (ADR 0058, PH5): Overview (the map with the facts, your runs, the
  -- notes), then Bosses, Quests, Attunement (always there), Loot, Strategy (the book's pages)
  dungeon = {
    { id = "map" },
    { id = "bosses", tab = true },
    { id = "quests", tab = true },
    { id = "attunement", tab = true, always = true, empty = L["No attunement needed."] },
    { id = "loot", tab = true },
    { id = "runs" }, -- Alts' "Your runs" (A2.5)
    {
      id = "book",
      tab = true,
      always = true,
      title = L["Strategy"],
      empty = L["No page of the book names this dungeon yet."],
    },
    NOTES,
  },
}
CHAPTERS.node, CHAPTERS.area = CHAPTERS.object, CHAPTERS.zone

local function registerTypes(self)
  for _, typ in ipairs(TYPES) do
    local chapters = CHAPTERS[typ]
    if typ == "npc" then
      chapters = function(id)
        local r = record("npc", id)
        return r and service:IsMonster(r) and CHAPTERS.monster or CHAPTERS.npc
      end
    end
    B:RegisterEntityType(self, {
      type = typ,
      priority = 100,
      chapters = chapters,
      -- the record's name, else the client's (Names.lua: retail packs carry no quest titles)
      name = function(id)
        local r = record(typ, id)
        if r and r.name and (r.nameEN or not Data.locale or not CLIENT_NAMED[typ]) then
          return r.name
        end
        -- on a client in another language an item or quest the language pack lacks takes the
        -- client's own name (ADR 0033), the English one until the client answers
        local client = Data.Names and Data.Names.Get(typ, id)
        return client or (r and r.name) or nil
      end,
      icon = function(id)
        local r = record(typ, id)
        if r and r.icon then
          return r.icon
        end
        if typ == "item" and type(id) == "number" then
          -- the item's own icon from the client: first
          -- from its item table, at once even for an item it has not cached (29.10.2026)
          local icon = B.Compat.ItemIcon(id)
          if icon then
            return icon
          end
          -- else a miss asks the client once, ITEM_DATA_LOAD_RESULT refreshes the entities
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
      lead = function(id)
        local r = record(typ, id)
        local fn = r and LEAD[typ]
        return fn and fn(r, id) or nil
      end,
      locations = function(id)
        local r = record(typ, id)
        if not r then
          return nil
        end
        if typ == "quest" then
          return questPlaces(r)
        end
        if typ == "dungeon" then
          -- a dungeon stands where its doors are (the entrance records of its instance)
          local out = {}
          for _, entranceID in ipairs(service:Index("entrance.byInstance", id) or {}) do
            local door = record("entrance", entranceID)
            for _, p in ipairs(door and spawns(door) or {}) do
              out[#out + 1] = p
            end
          end
          return out
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
  local onBand = typ == "quest" -- a quest's band says its level and zone (ADR 0052)
  if r.level and not onBand then
    rows[#rows + 1] = { text = L["Level"], value = r.level, valueKind = "number" }
  end
  if r.minLevel then
    rows[#rows + 1] = { text = L["Requires level"], value = r.minLevel, valueKind = "number" }
  end
  local zone = zoneName(r.zone)
  if zone and not onBand then
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
      place = { map = s.map, x = s.x, y = s.y }, -- a cut of the map under the skin (ADR 0034)
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
  -- by name, a to z
  table.sort(rows, function(a, b)
    if a.text ~= b.text then
      return a.text < b.text
    end
    return a.ref < b.ref
  end)
  return rows
end

-- Who knows a trainer's spell (alts.md "Knowledge", the `knowledge` service of Bastian's Alts):
-- the row's glyph in the state's colour (a tick in green: you; a tick in blue: one of your
-- characters; the trainer glyph in grey: nobody), the names as the note, a tooltip line; nothing
-- without the service.
local function knownBy(spellID)
  local knowledge = B:GetService("knowledge")
  local k = knowledge and spellID and knowledge:Known(spellID) or nil
  if not k then
    return nil
  end
  local names = {}
  if k.me then
    names[#names + 1] = L["you"]
  end
  for _, name in ipairs(k.alts or {}) do
    names[#names + 1] = name
  end
  if k.me then
    return B.UI.GLYPH_PATHS.done, "good", names
  elseif #names > 0 then
    return B.UI.GLYPH_PATHS.done, "water", names
  end
  return B.UI.GLYPH_PATHS.trainer, "dim", names
end

local function knownTip(tt, row)
  if row.ref then
    S.EntityTip(tt, row.ref, row.text)
  else
    S.TipLine(tt, row.text)
  end
  if row.known and #row.known > 0 then
    S.TipLine(tt, string.format(L["Known by: %s"], table.concat(row.known, ", ")), "tipGold")
  else
    S.TipLine(tt, L["Not known by any of your characters"], "tipDim")
  end
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
    -- the spell's name: the client's on a client in another language (ADR 0033), else the pack's
    local spell = Data.locale and t[1] and B.Compat.GetSpellName(t[1]) or t[2]
    local row = {
      text = (spell or (L["Spell"] .. " " .. tostring(t[1])))
        .. (#req > 0 and (" (" .. table.concat(req, ", ") .. ")") or ""),
      ref = t[6] and t[6] > 0 and ("item:" .. t[6]) or nil,
      value = t[3],
      valueKind = "money",
      note = CLASSIC_NOTE(t[7]),
      spell = t[1],
    }
    local icon, tint, names = knownBy(t[1])
    if icon then
      row.icon, row.tint, row.known, row.tooltip = icon, tint, names, knownTip
      if #names > 0 then
        row.note = table.concat(names, ", ")
      end
    end
    rows[#rows + 1] = row
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
      -- no chance: an item ForeverDB players saw drop in Forever, its rate unknown (never zero)
      note = l[2] and B.UI.FormatValue(l[2], "percent") or nil,
      chance = l[2],
    }
  end
  return rows
end

-- A dungeon's bosses in the client's order (data.md "Dungeons"); each boss's page carries its loot.
-- A boss without a known creature (`b[2]` nil, 02.11.2026) is its name alone, without a page.
local function bossRows(ref)
  local typ, id = B.Entity.Parse(ref)
  local r = typ == "dungeon" and record("dungeon", id)
  if not (r and r.bosses) then
    return nil
  end
  local rows = {}
  for _, b in ipairs(r.bosses) do
    local e = b[2] and B:Entity("npc:" .. b[2])
    rows[#rows + 1] = {
      text = e and e:Name() or b[3],
      ref = e and ("npc:" .. b[2]) or nil,
      icon = e and e:Icon() or nil,
      value = b[1],
      valueKind = "number",
    }
  end
  return rows
end

-- A dungeon's loot: every item ForeverDB ties to the instance, the boss it drops from in the note
local function dungeonLootRows(ref)
  local typ, id = B.Entity.Parse(ref)
  local r = typ == "dungeon" and record("dungeon", id)
  if not (r and r.loot) then
    return nil
  end
  local bossByOrder = {}
  for _, b in ipairs(r.bosses or {}) do
    bossByOrder[b[1]] = b
  end
  local rows = {}
  for _, l in ipairs(r.loot) do
    local boss = bossByOrder[l[2]]
    local e = B:Entity("item:" .. l[1])
    rows[#rows + 1] = {
      text = e:Name() or itemName(l[1]),
      ref = "item:" .. l[1],
      icon = e:Icon(),
      note = boss and (boss[2] and B:Entity("npc:" .. boss[2]):Name() or boss[3]) or nil,
    }
  end
  return rows
end

-- A dungeon's floors (DG2c): one row per floor with the plate's data (Scenery.FloorLayout draws
-- it): the client's map of the floor (`m` retail's UiMap, `a` the art files' prefix with `g` the
-- grid, `t` ForeverDB's minimap tiles; `by` an artist's map in Core, ADR 0048), the bosses of
-- that floor by number, name and ref (a pin
-- opens the boss), the door. A boss no floor shows is counted in the first floor's note.
local function floorTooltip(tip, row)
  tip:SetText(row.text or "")
  tip:AddLine(L["Click: enlarge"], 1, 1, 1)
end

local function floorRows(ref)
  local typ, id = B.Entity.Parse(ref)
  local r = typ == "dungeon" and record("dungeon", id)
  if not (r and r.floors) then
    return nil
  end
  local names, refs, placed = {}, {}, {}
  for _, b in ipairs(r.bosses or {}) do
    names[b[1]] = b[2] and B:Entity("npc:" .. b[2]):Name() or b[3]
    refs[b[1]] = b[2] and ("npc:" .. b[2]) or nil
  end
  for _, s in ipairs(r.bossSpots or {}) do
    placed[s[1]] = true
  end
  local unplaced = 0
  for _, b in ipairs(r.bosses or {}) do
    if not placed[b[1]] then
      unplaced = unplaced + 1
    end
  end
  local rows = {}
  for i, f in ipairs(r.floors) do
    local bosses = {}
    for _, s in ipairs(r.bossSpots or {}) do
      if s[2] == i then
        bosses[#bosses + 1] = { s[1], s[3], s[4], names[s[1]], refs[s[1]] }
      end
    end
    local door = r.door and r.door[1] == i and { r.door[2], r.door[3] } or nil
    local text = (f.n and f.n ~= "") and f.n or string.format(L["Floor %d"], i)
    rows[#rows + 1] = {
      text = text,
      tooltip = floorTooltip,
      floor = {
        w = f.w,
        h = f.h,
        uiMap = f.m,
        art = f.a,
        cols = f.g and f.g[1],
        rows = f.g and f.g[2],
        tiles = f.t,
        by = f.by, -- the artist of a hand-drawn map (ADR 0048), credited under it
        bosses = bosses,
        door = door,
        dungeon = r.name,
        note = (i == 1 and unplaced > 0)
            and string.format(L["%d bosses have no place on these maps yet"], unplaced)
          or nil,
      },
    }
  end
  return rows
end

-- The dungeon a boss, a dungeon quest or an entrance belongs to: one link row, else nothing
local function dungeonLinkRows(ref)
  local typ, id = B.Entity.Parse(ref)
  local r = record(typ, id)
  local dungeonID = r and (typ == "entrance" and r.instance or r.dungeon)
  local d = dungeonID and record("dungeon", dungeonID)
  if not d then
    return nil
  end
  return { { ref = "dungeon:" .. dungeonID, text = d.name, icon = B.UI.IconTexture("keep") } }
end

-- Item "Sources": drops [ref, chance, questDrop], a world drop [lowest level, highest level,
-- droppers], vendors (from the npc
-- records), made by
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
  local world = r.worldDrop
  if type(world) == "table" then
    local lo, hi, count = world[1], world[2], world[3]
    local text = L["World drop"]
    if lo and hi then
      -- a plain hyphen: the game fonts lack the dash (CLAUDE.md §12)
      text = text .. ": " .. string.format(L["creatures level %s"], lo == hi and lo or (lo .. "-" .. hi))
    end
    rows[#rows + 1] = {
      text = text,
      note = count and string.format(L["%d creatures"], count) or nil,
    }
  end
  if r.madeBy and not Data.RecipesBy().makes[id] then -- the recipes themselves: the block "Made by"
    rows[#rows + 1] =
      { text = L["Made by"] .. " " .. tostring(r.madeBy[1]) .. " (" .. tostring(r.madeBy[2]) .. ")" }
  end
  if r.sell then
    rows[#rows + 1] = { text = L["Vendor sell price"], value = r.sell, valueKind = "money" }
  end
  return rows
end

-- Recipe "Reagents": [item, count], each with the item's icon; the product has its own block
local function reagentRows(ref)
  local typ, id = B.Entity.Parse(ref)
  local r = typ == "recipe" and record("recipe", id)
  if not (r and r.reagents) then
    return nil
  end
  local rows = {}
  for _, rg in ipairs(r.reagents) do
    rows[#rows + 1] = {
      text = itemName(rg[1]),
      ref = "item:" .. rg[1],
      icon = B:Entity("item:" .. rg[1]):Icon(),
      value = rg[2],
      valueKind = "number",
    }
  end
  return rows
end

-- An item as the game describes it ("recipe information is extremely
-- flat - I would like to see the item it produces with picture and all stats"): the lines of the
-- game's tooltip after its name, in the theme's colours (a line with right-hand words as a row
-- with a value, the rest wrapped); while the client lacks the item, the pack's words, and the
-- item is asked for once (its load re-renders the page). `withName` puts the name in its
-- quality's colour first (a recipe's product; an item's own page has it on the band).
local function itemCardRows(itemID, count, withName)
  local r = record("item", itemID)
  local e = B:Entity("item:" .. itemID)
  local rows = {}
  if withName then
    local name = (r and r.name) or e:Name() or ("item " .. itemID)
    local times = count and count > 1 and ("  " .. S.H.muted .. "x" .. count .. "|r") or ""
    rows[1] =
      { ref = "item:" .. itemID, text = S.QualityText(r and r.quality, name) .. times, icon = e:Icon() }
  end
  local lines = B.Compat.ItemTooltipLines(itemID)
  if lines then
    for i = 2, #lines do -- the first line is the name
      local l = lines[i]
      if l.left ~= "" then
        local text = S.TipInk(l.r, l.g, l.b) .. l.left .. "|r"
        if l.right then
          rows[#rows + 1] = { text = text, value = l.right }
        else
          rows[#rows + 1] = { kind = "para", text = text }
        end
      end
    end
    return rows
  end
  if Data.Names then
    Data.Names.Want(itemID)
  end
  if r and r.level then
    rows[#rows + 1] = { text = L["Item level"], value = r.level, valueKind = "number" }
  end
  if r and r.reqLevel then
    rows[#rows + 1] = { text = L["Requires level"], value = r.reqLevel, valueKind = "number" }
  end
  if r and r.sell then
    rows[#rows + 1] = { text = L["Vendor sell price"], value = r.sell, valueKind = "money" }
  end
  return rows
end
Data.ItemCardRows = itemCardRows

-- Recipe "Makes": the product with its picture and the game's lines
local function productRows(ref)
  local typ, id = B.Entity.Parse(ref)
  local r = typ == "recipe" and record("recipe", id)
  if not (r and r.item) then
    return nil
  end
  return itemCardRows(r.item, r.count, true)
end

-- Item "Stats": the game's lines for the item of the page
local function statRows(ref)
  local typ, id = B.Entity.Parse(ref)
  if typ ~= "item" or type(id) ~= "number" then
    return nil
  end
  local rows = itemCardRows(id, nil, false)
  return #rows > 0 and rows or nil
end

-- The recipes by item ("the item detail page should like usage in
-- recipes"): which recipes take an item as a reagent and which make it, from the recipe records,
-- built on the first ask and again once the pack's ids change (a pack load).
local recipeIndex
local function recipesBy()
  local ids = service:Each("recipe")
  if recipeIndex and recipeIndex.ids == ids then
    return recipeIndex
  end
  local uses, makes = {}, {}
  local function add(map, item, recipe)
    if type(item) == "number" then
      local list = map[item]
      if not list then
        list = {}
        map[item] = list
      end
      list[#list + 1] = recipe
    end
  end
  for _, id in ipairs(ids) do
    local r = record("recipe", id)
    if r then
      for _, rg in ipairs(r.reagents or {}) do
        add(uses, rg[1], id)
      end
      add(makes, r.item, id)
    end
  end
  recipeIndex = { ids = ids, uses = uses, makes = makes }
  return recipeIndex
end
Data.RecipesBy = recipesBy

-- The rows of recipes: the recipe's name, its profession and skill in grey, the count of the item
-- it takes (`counts`) as the value
local function recipeRows(list, itemID, withCount)
  if not list or #list == 0 then
    return nil
  end
  local rows = {}
  for _, rid in ipairs(list) do
    local r = record("recipe", rid)
    local name = (r and r.name) or B:Entity("recipe:" .. rid):Name() or ("recipe " .. rid)
    local skill = r
        and r.profession
        and ("  " .. S.H.muted .. r.profession .. (r.skill and (" " .. r.skill) or "") .. "|r")
      or ""
    local count
    for _, rg in ipairs(withCount and r and r.reagents or {}) do
      if rg[1] == itemID then
        count = rg[2]
      end
    end
    rows[#rows + 1] = {
      text = name .. skill,
      ref = "recipe:" .. rid,
      icon = B.UI.IconTexture("trainer"),
      value = count,
      valueKind = count and "number" or nil,
    }
  end
  table.sort(rows, function(a, b)
    return a.text < b.text
  end)
  return rows
end

-- "Disenchants into" ("add disenchant information to all items where
-- possible"): the materials of the item's disenchant list (CMaNGOS, Classic values), each with
-- its icon and how many come, the chance as the value; nil for an item no list names (unknown,
-- or not disenchantable).
local function disenchantRows(ref)
  local typ, id = B.Entity.Parse(ref)
  local r = typ == "item" and record("item", id)
  local list = r and r.disenchant and record("disenchant", r.disenchant)
  if not (list and type(list.loot) == "table" and #list.loot > 0) then
    return nil
  end
  local rows = {}
  for _, l in ipairs(list.loot) do
    local lo, hi = l[3], l[4]
    local count = ""
    if lo and hi and hi > lo then
      count = "  " .. S.H.muted .. "x" .. lo .. "-" .. hi .. "|r"
    elseif lo then
      count = "  " .. S.H.muted .. "x" .. lo .. "|r"
    end
    rows[#rows + 1] = {
      text = itemName(l[1]) .. count,
      ref = "item:" .. l[1],
      icon = B:Entity("item:" .. l[1]):Icon(),
      value = l[2],
      valueKind = l[2] and "percent" or nil,
    }
  end
  return rows
end

local function disenchantTipRows(ref)
  local rows = disenchantRows(ref)
  for _, row in ipairs(rows or {}) do
    row.text = L["Disenchant"] .. ": " .. row.text -- the tooltip has no block title
    row.icon = nil
  end
  return rows
end

local function usedInRows(ref)
  local typ, id = B.Entity.Parse(ref)
  if typ ~= "item" then
    return nil
  end
  return recipeRows(recipesBy().uses[id], id, true)
end

local function madeByRows(ref)
  local typ, id = B.Entity.Parse(ref)
  if typ ~= "item" then
    return nil
  end
  return recipeRows(recipesBy().makes[id], id, false)
end

-- The people of a zone by what they do for the player (ADR 0013, the zone page; the sheet's
-- People chapter, ADR 0054): flight master and inn as they are, then quest givers, vendors,
-- trainers and the rest of the service NPCs as folded groups. From the byZone indexes; an NPC's
-- flags list names its services. "Near" (the Here column) reads the same groups.
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

-- The zone a zone or area page is about, and for an area the test of its places (the zone's
-- blocks list only what stands in the area).
local function scopeOf(ref)
  local typ, id = B.Entity.Parse(ref)
  if typ == "zone" then
    return tonumber(id), nil
  elseif typ == "area" then
    return service:AreaScope(id)
  end
  return nil
end

-- Whether one of the record's places passes `inside` (no test: every record).
local function standsIn(r, inside)
  if not inside then
    return true
  end
  for _, s in ipairs(spawns(r)) do
    if inside(s.map, s.x, s.y) then
      return true
    end
  end
  return false
end

local RANK_FLAGS = { elite = true, rareelite = true, rare = true, boss = true }
local function hasService(r)
  for flag in pairs(flagsOf(r)) do
    if not RANK_FLAGS[flag] then
      return true
    end
  end
  return false
end

-- A monster (the zone's Monsters, the Browser's Mobs list, the Map's monster areas; owner, retail
-- 31.10.2026): an NPC without a service and without a faction it belongs to.
function service:IsMonster(r)
  return type(r) == "table" and not r.faction and not hasService(r)
end

-- What a tile says of a record (ADR 0056; the facet "tile", core-contracts §4): the line under the
-- name, a badge, a mark, a note. Record facts only, so an answer holds until the data changes; a
-- badge carries its level and the tile's host colours it for the character. A type without a rule
-- here (an item, a recipe, an area) shows its summary as the line.
local function levelBadge(lo, hi)
  if type(lo) ~= "number" or lo <= 0 then
    return nil -- unknown is no badge, never a 0
  end
  if type(hi) == "number" and hi > lo then
    return { text = lo .. "-" .. hi, level = lo, levelHi = hi }
  end
  return { text = tostring(lo), level = lo }
end

local function joined(...)
  local parts = {}
  for i = 1, select("#", ...) do
    local part = select(i, ...)
    if part and part ~= "" then
      parts[#parts + 1] = part
    end
  end
  return #parts > 0 and table.concat(parts, ", ") or nil
end

local function placesNote(r)
  local n = #(r.spawns or {})
  return n > 1 and string.format(L["%d places"], n) or nil
end

-- A person's designation where the record has no subname: the first service it offers, the
-- quest giver last.
local SERVICE_ORDER = {
  "trainer",
  "innkeeper",
  "flightmaster",
  "banker",
  "auctioneer",
  "stablemaster",
  "battlemaster",
  "repair",
  "vendor",
  "questgiver",
}
local RANK_ORDER = { "boss", "rareelite", "rare", "elite" }
local function firstKind(flags, order)
  for _, flag in ipairs(order) do
    if flags[flag] then
      return (service:Kind("npc", flag))
    end
  end
  return nil
end

local TILE = {
  npc = function(r)
    local flags = flagsOf(r)
    local zone = zoneName(r.zone)
    if service:IsMonster(r) then
      local rank = firstKind(flags, RANK_ORDER)
      return {
        line = zone,
        badge = levelBadge(r.level, r.levelMax),
        mark = rank and { text = rank, token = "rare" } or nil,
        note = placesNote(r),
      }
    end
    -- a person's level says nothing to the player: no badge, also not the list's
    return { line = joined(r.subname or firstKind(flags, SERVICE_ORDER), zone), badge = false }
  end,
  quest = function(r)
    return { line = zoneName(r.zone), badge = levelBadge(r.level) }
  end,
  zone = function(r, id)
    local within = r.parent and zoneName(r.parent) or B.Coords.ContinentName(r.continent)
    return {
      line = within ~= r.name and within or nil, -- a continent lies in nothing
      badge = levelBadge(r.levelLo, r.levelHi),
      map = id, -- the tile's picture is the zone (ADR 0056)
    }
  end,
  object = function(r)
    return { line = joined((service:Kind("object", r.kind)), zoneName(r.zone)), note = placesNote(r) }
  end,
  node = function(r)
    local skill = (r.profession or "") .. (r.skill and (" " .. r.skill) or "")
    return { line = joined(skill, zoneName(r.zone)), note = placesNote(r) }
  end,
  -- the client's words: nil where it knows none, and the tile says the summary
  item = function(_, id)
    local kind, slot = B.Compat.ItemKind(id)
    return { line = joined(kind, slot) }
  end,
  -- what goes in: "2 Linen Cloth, Coarse Thread"
  recipe = function(r)
    local parts = {}
    for _, rg in ipairs(r.reagents or {}) do
      local name, count = itemName(rg[1]), rg[2] or 1
      parts[#parts + 1] = count > 1 and (count .. " " .. name) or name
    end
    return { line = #parts > 0 and table.concat(parts, ", ") or nil }
  end,
  dungeon = function(r)
    local bosses = type(r.bosses) == "table" and #r.bosses or 0
    local badge = levelBadge(r.levelLo, r.levelHi)
    if badge then
      badge.countdown = true -- the tile says "in 4 levels" while the band is ahead (A2.2)
    end
    return {
      line = joined(zoneName(r.zone), bosses > 0 and string.format(L["%d bosses"], bosses) or nil),
      badge = badge,
      mark = r.kind == "raid" and { text = L["Raid"] } or nil,
    }
  end,
}

local function registerTiles(self)
  local types = {}
  for typ in pairs(TILE) do
    types[#types + 1] = typ
  end
  table.sort(types)
  B:RegisterFacet(self, {
    facet = "tile",
    types = types,
    priority = 100,
    invalidateOn = { "BASTIANS_DATA_LOADED" },
    rule = function(ref)
      local typ, id = B.Entity.Parse(ref)
      local r = typ and record(typ, id)
      local facts = r and TILE[typ](r, id) or nil
      return facts and next(facts) ~= nil and facts or nil
    end,
  })
end

-- "People" (the sheet's chapter, ADR 0054): everyone in the zone who is not a monster. A person
-- with two services stands in both groups; a quest giver without a service among the quest
-- givers; who has neither among the others, one row per name (a city's guards are one row). A
-- group of one that is not folded is its own row; the folded groups carry their count.
local PEOPLE_GROUPS = { { "questgiver", "Quest givers", "quest", true } }
for i, g in ipairs(PLACE_GROUPS) do
  -- the flight master and the inn first, then the quest givers, then the rest
  table.insert(PEOPLE_GROUPS, i <= 2 and i or (i + 1), g)
end
PEOPLE_GROUPS[#PEOPLE_GROUPS + 1] = { "other", "Others", "service", true }

local function personRow(id, r, iconKind)
  local text = r.name or ("npc " .. id)
  if r.subname then
    text = text .. "  " .. S.H.muted .. r.subname .. "|r"
  end
  return { ref = "npc:" .. id, text = text, icon = B.UI.IconTexture(iconKind) }
end

local function peopleRows(ref)
  local map, inside = scopeOf(ref)
  if not map then
    return nil
  end
  local byFlag, named = {}, {}
  local function put(flag, id, r, iconKind)
    local list = byFlag[flag]
    if not list then
      list = {}
      byFlag[flag] = list
    end
    list[#list + 1] = personRow(id, r, iconKind)
  end
  for id in service:ByZone("npc", map) do
    local r = record("npc", id)
    if r and not service:IsMonster(r) and standsIn(r, inside) then
      local set = flagsOf(r)
      local grouped = false
      for _, g in ipairs(PEOPLE_GROUPS) do
        if set[g[1]] then
          put(g[1], id, r, g[3])
          grouped = true
        end
      end
      if not grouped and r.name and not named[r.name] then
        named[r.name] = true
        put("other", id, r, "service")
      end
    end
  end
  local rows = {}
  for _, g in ipairs(PEOPLE_GROUPS) do
    local list = byFlag[g[1]]
    if list then
      table.sort(list, function(x, y)
        return x.text < y.text
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
  return #rows > 0 and rows or nil
end

-- "Gathering" on a zone's sheet: the gathering nodes by profession, folded.
local function gatheringRows(ref)
  local map, inside = scopeOf(ref)
  if not map then
    return nil
  end
  local rows = {}
  local byProfession, professions = {}, {}
  for id in service:ByZone("node", map) do
    local r = record("node", id)
    if r and standsIn(r, inside) then
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
    table.sort(list, function(x, y)
      return x.text < y.text
    end)
    rows[#rows + 1] = {
      text = L[key] .. "  " .. S.H.muted .. #list .. "|r",
      icon = B.UI.IconTexture("herb"),
      children = list,
      collapsed = true,
    }
  end
  return #rows > 0 and rows or nil
end

-- "Near" (the Here column, C4): the service NPCs, mailboxes and gathering nodes of the zone by
-- travel time from the player (W8: the world graph's cache, Bastians.UI.Away), the kind and the
-- time after the name; the rows without a time after the others. Built again on a zone change and
-- when the graph's times move (BASTIANS_GRAPH_TIMES).
local NODE_ICON = { ore = "mine", fish = "fish" }
local function nearRows(ref)
  local _, map = B.Entity.Parse(ref)
  map = tonumber(map)
  if not map then
    return nil
  end
  local rows = {}
  local function add(entityRef, r, kindLabel, icon)
    local words = kindLabel
    local away, d = B.UI.Away(entityRef)
    if away then
      words = words .. ", " .. away
    end
    rows[#rows + 1] = {
      id = "near:" .. entityRef,
      ref = entityRef,
      text = (r.name or entityRef) .. "  " .. S.H.muted .. words .. "|r",
      icon = icon,
      d = d or math.huge,
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
-- "Areas" (data.md "Areas"): the zone's subzones by name, each leads to its own page
local function areaRows(ref)
  local _, map = B.Entity.Parse(ref)
  map = tonumber(map)
  if not map then
    return nil
  end
  local rows = {}
  for id in service:ByZone("area", map) do
    local r = record("area", id)
    if r and r.name then
      -- the area's place on the zone's map: a cut of the painting under the skin (ADR 0034)
      local s = type(r.spawns) == "table" and r.spawns[1]
      local place
      if s and tonumber(s[1]) and tonumber(s[2]) and tonumber(s[3]) then
        place = { map = s[1], x = s[2], y = s[3] }
      end
      rows[#rows + 1] = { ref = "area:" .. id, text = r.name, icon = B.UI.IconTexture("zone"), place = place }
    end
  end
  table.sort(rows, function(a, b)
    return a.text < b.text
  end)
  return #rows > 0 and rows or nil
end

-- The monsters of a zone: NPCs without a service, a faction or a quest to give, by level; their
-- rows carry the worth per kill through the worth registry when Gold is there.
local function monsterRows(ref)
  local map, inside = scopeOf(ref)
  if not map then
    return nil
  end
  local list, seen = {}, {}
  for id in service:ByZone("npc", map) do
    local r = record("npc", id)
    if r and r.name and r.level and service:IsMonster(r) and not seen[r.name] and standsIn(r, inside) then
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
    chapter = "gathering", -- on the sheet (ADR 0054)
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
    chapter = "get", -- on the sheet (ADR 0054)
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
    chapter = "monsters", -- on the sheet (ADR 0054)
    title = L["Monsters"],
    types = { "zone", "area" }, -- an area: the zone's that stand in it
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
    invalidateOn = { "BASTIANS_PLAYER_MOVED_ZONE", "BASTIANS_GRAPH_TIMES" },
    build = nearRows,
  })
  -- the dossier blocks (C2, ADR 0014): Overview and Places show more rows before "+N more", the
  -- lists eight; the "zone" link leads to the entity's zone page
  section({
    id = "data.people",
    chapter = "people", -- on the sheet (ADR 0054)
    title = L["People"],
    types = { "zone", "area" },
    order = 12,
    block = { wide = true, limit = 12 },
    build = peopleRows,
  })
  section({
    id = "data.gathering",
    chapter = "places", -- on the sheet (ADR 0054), under the areas
    title = L["Gathering"],
    types = { "zone", "area" },
    order = 15,
    block = { limit = 12 },
    build = gatheringRows,
  })
  section({
    id = "data.areas",
    chapter = "places", -- on the sheet (ADR 0054)
    title = L["Areas"],
    types = { "zone" },
    order = 14,
    block = { limit = 12 },
    build = areaRows,
  })
  section({
    id = "data.overview",
    chapter = "facts", -- on the sheet (ADR 0054)
    title = L["Overview"],
    types = "*",
    order = 10,
    block = { limit = 12 },
    build = overviewRows,
  })
  section({
    id = "data.spawns",
    chapter = "where", -- on the sheet (ADR 0054)
    title = L["Locations"],
    types = { "npc", "object", "node" },
    order = 15,
    build = spawnRows,
  })
  section({
    id = "data.vendor",
    chapter = "sells", -- on the sheet (ADR 0054)
    title = L["Sells"],
    types = { "npc" },
    order = 30,
    block = { limit = 8, table = true },
    build = vendorRows,
  })
  section({
    id = "data.trainer",
    chapter = "teaches", -- on the sheet (ADR 0054)
    title = L["Teaches"],
    types = { "npc" },
    order = 31,
    block = { limit = 12 }, -- what you can buy here, with who knows it
    invalidateOn = { "BASTIANS_ALTS_CHANGED" },
    build = trainerRows,
  })
  section({
    id = "data.loot",
    chapter = "drops", -- on the sheet (ADR 0054)
    title = L["Drops"],
    types = { "npc", "object" },
    order = 40,
    block = { limit = 8, table = true },
    build = lootRows,
  })
  section({
    id = "data.sources",
    chapter = "get", -- on the sheet (ADR 0054)
    title = L["Sources"],
    types = { "item" },
    order = 20,
    block = { limit = 8, table = true },
    build = sourceRows,
    tooltip = { max = 2 },
  })
  section({
    id = "data.reagents",
    chapter = "reagents", -- on the sheet (ADR 0054)
    title = L["Reagents"],
    types = { "recipe" },
    order = 20,
    build = reagentRows,
  })
  -- owner round 5 (retail, 31.10.2026): the product and the item's lines, an item's recipes
  section({
    id = "data.product",
    chapter = "makes", -- on the sheet (ADR 0054)
    title = L["Makes"],
    types = { "recipe" },
    order = 12,
    block = { wide = true, limit = 30 },
    invalidateOn = { "BASTIANS_ENTITY_CHANGED" }, -- the item's data arrives from the client
    build = productRows,
  })
  section({
    id = "data.stats",
    chapter = "facts", -- on the sheet (ADR 0054)
    title = L["Stats"],
    types = { "item" },
    order = 12,
    block = { wide = true, limit = 30 },
    invalidateOn = { "BASTIANS_ENTITY_CHANGED" },
    build = statRows,
  })
  section({
    id = "data.disenchant",
    chapter = "use", -- on the sheet (ADR 0054)
    title = L["Disenchants into"],
    types = { "item" },
    order = 24,
    block = { limit = 6 },
    build = disenchantRows,
    tooltip = { max = 3, build = disenchantTipRows },
  })
  section({
    id = "data.usedin",
    chapter = "use", -- on the sheet (ADR 0054)
    title = L["Used in recipes"],
    types = { "item" },
    order = 23,
    block = { limit = 8 },
    invalidateOn = { "BASTIANS_DATA_LOADED" },
    build = usedInRows,
    tooltip = { max = 2, build = usedInRows },
  })
  section({
    id = "data.madeby",
    chapter = "get", -- on the sheet (ADR 0054)
    title = L["Made by"],
    types = { "item" },
    order = 19,
    block = { limit = 8 },
    invalidateOn = { "BASTIANS_DATA_LOADED" },
    build = madeByRows,
  })
  -- dungeons (data.md "Dungeons"): the bosses in order, the loot of the instance, and the way back
  -- from a boss, a dungeon quest or a door to its dungeon
  section({
    id = "data.bosses",
    chapter = "bosses", -- on the sheet (ADR 0054)
    title = L["Bosses"],
    types = { "dungeon" },
    order = 20,
    build = bossRows,
    tooltip = { max = 3, build = bossRows },
  })
  -- the dungeon's facts as tiles on its overview (ADR 0058, PH5)
  section({
    id = "data.dungeonfacts",
    chapter = "map",
    title = L["Overview"],
    types = { "dungeon" },
    order = 10,
    block = { stats = true },
    build = function(ref)
      local _, id = B.Entity.Parse(ref)
      local r = record("dungeon", tonumber(id))
      if not r then
        return nil
      end
      local rows = {}
      rows[#rows + 1] =
        { text = L["Level"], value = r.levelLo and r.levelHi and (r.levelLo .. "-" .. r.levelHi) or nil }
      rows[#rows + 1] = { text = L["Bosses"], value = type(r.bosses) == "table" and #r.bosses or nil }
      rows[#rows + 1] = { text = L["Players"], value = r.size }
      local floors = type(r.floors) == "table" and #r.floors or nil
      rows[#rows + 1] = { text = L["Floors"], value = floors }
      return rows
    end,
  })
  section({
    id = "data.floors",
    chapter = "map", -- on the sheet (ADR 0054)
    title = L["Map"],
    types = { "dungeon" },
    order = 25,
    block = { limit = 8 },
    build = floorRows,
  })
  section({
    id = "data.dungeonloot",
    chapter = "loot", -- on the sheet (ADR 0054)
    title = L["Loot"],
    types = { "dungeon" },
    order = 40,
    block = { limit = 12, table = true },
    build = dungeonLootRows,
  })
  section({
    id = "data.dungeon",
    title = L["Dungeon"],
    types = { "npc", "quest", "entrance" },
    order = 88,
    link = L["dungeon"],
    build = dungeonLinkRows,
  })
  section({
    id = "data.zone",
    title = L["Zone"],
    types = { "npc", "object", "quest", "node", "item", "area" },
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
    search = function(query, limit, yield, q)
      local out = {}
      for _, typ in ipairs(TYPES) do
        for _, hit in ipairs(service:Find(typ, q or query, limit, yield)) do
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
  news = ns.NEWS, -- What's new (ADR 0021)
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
    {
      -- the captures as a text to share (catalog review B5, 07.11.2026; Export.lua)
      type = "execute",
      label = L["Copy my captures"],
      icon = "copy",
      desc = L["Your learned walks, flight times and ride waits as a text for a GitHub issue (Share your captures). Positions and times only, no names."], -- luacheck: ignore 631 (a locale key stays one literal)
      func = function()
        Data.Export.Show()
      end,
    },
  },
  OnEnable = function(self)
    B:ProvideService(self, "data", service, { priority = 100 })
    registerTypes(self)
    registerTiles(self) -- what a tile says of a record (ADR 0056)
    registerSections(self)
    registerSearch(self)
    -- an item's vendor price as its worth, below Gold's (priority 50): retail has no Gold since
    -- 24.10.2026 (owner: "Gold out, vendor prices only"), so its items still say what they fetch
    B:RegisterWorth(self, {
      types = { "item" },
      priority = 10,
      invalidateOn = { "BASTIANS_DATA_LOADED" },
      worth = function(ref)
        local _, id = B.Entity.Parse(ref)
        local r = service:Get("item", id)
        if not (r and r.sell) then
          return nil -- unknown: no worth line, never 0
        end
        return { text = L["vendor"] .. " " .. B.UI.Money(r.sell), copper = r.sell }
      end,
    })
    if Data.Names then
      Data.Names.Attach(self)
    end
    if Data.Poi then
      Data.Poi.Attach(self)
    end
    if Data.Activity then
      Data.Activity.Attach(self)
    end
    if Data.Graph then
      Data.Graph.Attach(self)
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
