-- Bastian's Browser (browser.md): the entity page (header, actions, every registered detail section
-- in order), lists by type with facets built as Core jobs, history with back and forward, bookmarks
-- per character, and the "open in Browser" tooltip hint. Browser owns no detail sections: it renders
-- what Data, Quests and Gold register (core-contracts §7).
local ADDON, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
local L = ns.L
local S = B.UI.Style
local Widgets = B.UI.Widgets

local Browser = {}
ns.Browser = Browser

local MAX_ROWS = 1500 -- a list shows at most this many rows; the search and the facets narrow it
local LIST_SLICE = 200 -- records per job slice
local RENDER_DELAY = 0.05
Browser.listCache = {} -- type -> { rows, counts, total }, dropped when a pack loads or the zone changes

-- The list types in menu order with their dimensions (ADR 0016): each dimension is one pill of the
-- filter bar; `value(r, d)` gives a record's key (an English word for the locale), a list of keys
-- (an NPC's services) or nil ("Other"); `sortKey(key)` orders the choices where a count would not
-- (level bands, qualities).
local ITEM_CLASS = {
  [0] = "Consumable",
  [1] = "Container",
  [2] = "Weapon",
  [3] = "Gem",
  [4] = "Armor",
  [5] = "Reagent",
  [6] = "Projectile",
  [7] = "Trade Goods",
  [8] = "Generic",
  [9] = "Recipe",
  [10] = "Money",
  [11] = "Quiver",
  [12] = "Quest",
  [13] = "Key",
  [14] = "Permanent",
  [15] = "Miscellaneous",
}
local QUALITY = { [0] = "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Artifact", "Heirloom" }
local QUALITY_ORDER = {}
for q, name in pairs(QUALITY) do
  QUALITY_ORDER[name] = q
end
-- The Zones list: a
-- continent or zone (UiMap.Type 2, 3, or an old pack without `mapType`) files under its continent's
-- name, a dungeon floor (4) under "Instances", merged by name, everything else under "Other".
local UI_MAP_CONTINENT, UI_MAP_ZONE, UI_MAP_DUNGEON = 2, 3, 4
local function zoneFacet(r)
  local t = r.mapType
  if t == nil or t == UI_MAP_CONTINENT or t == UI_MAP_ZONE then
    return B.Coords.ContinentName(r.continent) or "Other"
  elseif t == UI_MAP_DUNGEON then
    return "Instances"
  end
  return "Other"
end
local function band(level)
  if not level then
    return "no level"
  end
  local lo = math.floor((level - 1) / 10) * 10 + 1
  return lo .. "-" .. (lo + 9)
end
-- Level bands in their own order ("1-10" before "11-20"), "no level" last.
local function bandOrder(key)
  return tonumber(string.match(tostring(key), "^(%d+)")) or 1000
end
Browser.Band = band

-- An NPC's flags (a list, or one word in old packs) split into services and the rank.
local RANKS = { elite = true, rareelite = true, boss = true, rare = true }
local function npcFlags(r)
  local flags = r.flags
  if type(flags) == "string" then
    flags = { flags }
  end
  return flags or {}
end
local function kindGroup(d, typ, kind)
  local _, group
  if d and d.Kind then
    _, group = d:Kind(typ, kind)
  end
  return group
end

-- A monster ("NPCs and mobs have different usage in game, and the lists
-- are long anyway"): an NPC without a service and without a faction it belongs to, the rule of
-- Data's Monsters section. Elite, rare and boss are ranks, no service: Hogger is a monster.
local function isMob(r)
  local d = B:GetService("data")
  if d and d.IsMonster then
    return d:IsMonster(r) -- one rule for the suite
  end
  if r.faction then
    return false
  end
  for _, flag in ipairs(npcFlags(r)) do
    if not RANKS[flag] then
      return false
    end
  end
  return true
end
Browser.IsMob = isMob

local RANK_DIM = {
  id = "rank",
  title = "Rank",
  kind = "rare", -- the pill's tile (ADR 0046)
  value = function(r, d)
    for _, flag in ipairs(npcFlags(r)) do
      if RANKS[flag] then
        return kindGroup(d, "npc", flag) or "Other"
      end
    end
    return "Normal"
  end,
}

local LEVEL_DIM = {
  id = "level",
  title = "Level",
  value = function(r)
    return band(r.level)
  end,
  sortKey = bandOrder,
}

-- Where a record stands, as a filter ("for dungeons a zone dropdown would
-- make sense - and not auto setting the zone"): the zone's name, in alphabetical order.
local ZONE_DIM = {
  id = "zone",
  title = "Zone",
  value = function(r, d)
    local map = r.zone or r.map or (r.spawns and r.spawns[1] and r.spawns[1][1])
    local z = map and d and d:Get("zone", map) or nil
    return z and z.name or nil
  end,
  sortKey = function(key)
    return key
  end,
}

-- A list's `type` is its key (the type bar, the saved filters, the cache); `entity` the data type
-- of its records when the two differ (the Mobs list holds NPCs), `keep(r)` the records it takes.
Browser.LISTS = {
  {
    type = "npc",
    label = "People", -- the model's words (ADR 0056); the type stays `npc`
    glyph = "service",
    zoneSuffix = true, -- a repeated name says its zone
    keep = function(r)
      return not isMob(r)
    end,
    dims = {
      {
        id = "service",
        title = "Service",
        chips = true, -- every service as a chip with its count, several at once (ADR 0038)
        value = function(r, d)
          local out = {}
          for _, flag in ipairs(npcFlags(r)) do
            if not RANKS[flag] then
              out[#out + 1] = kindGroup(d, "npc", flag) or "Other"
            end
          end
          if #out == 0 then
            return "No service"
          end
          return #out == 1 and out[1] or out
        end,
      },
      ZONE_DIM,
      RANK_DIM,
      LEVEL_DIM,
    },
  },
  {
    type = "mob",
    entity = "npc",
    label = "Monsters",
    glyph = "mob",
    zoneSuffix = true,
    keep = isMob,
    ref = function(id)
      return "npc:" .. id
    end,
    dims = { ZONE_DIM, RANK_DIM, LEVEL_DIM },
  },
  {
    type = "item",
    label = "Items",
    dims = {
      {
        id = "class",
        title = "Class",
        value = function(r)
          return ITEM_CLASS[r.class] or "Other"
        end,
      },
      {
        id = "quality",
        title = "Quality",
        value = function(r)
          return QUALITY[r.quality]
        end,
        sortKey = function(key)
          return QUALITY_ORDER[key] or 100
        end,
      },
    },
  },
  {
    type = "object",
    label = "Objects",
    zoneSuffix = true,
    mergeSame = true, -- one row per name and zone, "N places"
    dims = {
      {
        id = "kind",
        title = "Kind",
        value = function(r, d)
          return kindGroup(d, "object", r.kind) or "Other"
        end,
      },
      ZONE_DIM,
    },
  },
  {
    type = "node",
    label = "Gathering",
    zoneSuffix = true,
    mergeSame = true,
    dims = {
      {
        id = "kind",
        title = "Kind",
        value = function(r, d)
          return kindGroup(d, "node", r.kind) or "Other"
        end,
      },
      ZONE_DIM,
    },
  },
  {
    type = "zone",
    label = "Zones",
    noNear = true, -- one pill: the continents, Instances, Other (the player's continent first)
    mergeInstances = true,
    -- retail holds two zone maps of one name (Badlands 15 under Eastern Kingdoms 13 with its
    -- quests, Badlands 1245 under map 1208 with nothing; measured 31.10.2026): one row, the one
    -- with content (owner: "the empty one should be gone")
    mergeNamesakes = true,
    dims = {
      { id = "continent", title = "Continent", value = zoneFacet },
    },
  },
  {
    type = "recipe",
    label = "Recipes",
    dims = {
      {
        id = "profession",
        title = "Profession",
        value = function(r)
          return r.profession
        end,
      },
    },
  },
  {
    type = "quest",
    label = "Quests",
    dims = { ZONE_DIM, LEVEL_DIM },
  },
  -- dungeons and raids (data.md "Dungeons"): by kind and by the band their level range starts in
  {
    type = "dungeon",
    label = "Dungeons",
    dims = {
      {
        id = "kind",
        title = "Kind",
        value = function(r)
          return r.kind == "raid" and "Raid" or "Dungeon"
        end,
      },
      ZONE_DIM,
      {
        id = "level",
        title = "Level",
        value = function(r)
          return band(r.levelLo)
        end,
        sortKey = bandOrder,
      },
    },
  },
  {
    type = "spot",
    label = "Farm spots",
    dims = { ZONE_DIM },
  },
}

-- The dimensions of a list: its own, a registered list's facet (core-contracts §7c), then the
-- facets apps register for the type (§7d).
function Browser.Dims(def)
  local dims = {}
  for _, dim in ipairs(def.dims or {}) do
    dims[#dims + 1] = dim
  end
  if not def.dims and def.value then -- a registered list: its facet is its one dimension
    local name = tostring(def.facet or "facet")
    dims[1] = {
      id = name,
      title = string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2),
      value = def.value,
      sortKey = name == "level" and bandOrder or nil,
      chips = def.chips or nil, -- the chains' levels, several at once
      group = true, -- a registered list may be grouped by its facet (core-contracts 7c)
    }
  end
  for _, f in ipairs(B:GetFilters(def.entity or def.type, "facet")) do
    dims[#dims + 1] = {
      id = f.id,
      title = f.label,
      value = function(r, _, ref)
        return B:FilterValue(f, ref, r)
      end,
      labels = f.labels,
      sortKey = f.order,
      chips = f.chips or nil,
      group = f.group or nil, -- offered among the list's groups (core-contracts 7d)
    }
  end
  return dims
end

-- The generations of the facets a list's rows carry: a built list whose facets moved (a quest's
-- status after a hand-in) is built again.
local function facetGen(def)
  local parts = {}
  for _, f in ipairs(B:GetFilters(def.entity or def.type, "facet")) do
    parts[#parts + 1] = f.id .. "=" .. B:FilterGeneration(f.id)
  end
  return table.concat(parts, ",")
end

-- Every list of the type bar: the data types above and the lists apps register (Core's
-- RegisterList: Quests' chains), sorted by their shown name.
function Browser.Lists()
  local out = {}
  for _, def in ipairs(Browser.LISTS) do
    out[#out + 1] = def
  end
  for _, def in ipairs(B:GetLists()) do
    out[#out + 1] = def
  end
  table.sort(out, function(a, b)
    return tostring(L[a.label]) < tostring(L[b.label])
  end)
  return out
end

local mod, win, tree, summary, toolbar, search
local filterBox -- the list pane's own filter: narrows the rows shown as you type
local filterHost -- where the filter chips stand: beside the search, under it when narrow (ADR 0056)
local scope -- the scope chip inside the search box (ADR 0056)
local searching -- a narrow window: the magnifier opened the search box over the title (ADR 0058)
local layingOut -- Browser.Layout is giving the filter bar its width: its height comes back to it
local syncingFilter -- the filter box follows the entry, nobody typed
local header -- the block above the list: a view's control bar
local dossier -- the detail pane's dossier: the page of the subject (ADR 0018)
local hereDossier -- the Here entry in the list pane: the player's zone in `here` mode (C4)
local rail -- the rail of seven on top (ADR 0058; the category bar of ADR 0056 until then)
local tabs -- the shown section's lists and views as a row of tabs under the rail (ADR 0058)
local crumbs -- the breadcrumb row: where the two tiles are (ADR 0056)
local pageFilter -- the page tile's filter (R2)
local listPane, detailPane, splitter -- the list pane, the detail pane and the divider between them
local pager -- the list tile's foot (ADR 0058): the page you are on, and the arrows that turn it
local stats -- the stat tiles above the rows of the list tile (ADR 0058, PH4)
local show -- show(entry, record): the one way an entry gets on screen, defined with the facade below
local LIST_MIN, DETAIL_MIN = 240, 300
local ONE_MIN = 640 -- narrower, one tile at a time: the list or the page (ADR 0056)
local WIN_MIN = 320 -- the window's least width
local CAT_GAP = 4 -- between two tabs, and between their rows
local RAIL_GAP = 4 -- between two rail entries
local CRUMB_H = 18 -- the breadcrumb row
local PAGER_H = 22 -- the list tile's foot (ADR 0058)
local TOOLBAR_H = 26
-- entries { kind = "page" | "list" | "view" | "home" | "here" | "bookmarks", ref, type, id, text }
local history, cursor = {}, 0
local current -- the entry at the cursor
local shownList -- the entry the list pane shows: the newest that is not a page (ADR 0018)
local previewRef -- the row resting under the mouse, shown in the detail pane (ADR 0018 C)
local hereEntry = { kind = "here" } -- the list pane's entry before any other
-- Which tile a narrow window shows: the list (true) or the page. A wide window shows both
-- (ADR 0056; the sliding list pane of R25.36 went with it).
local listOpen = true
local listJob
local listJobType, listJobGen, listJobMap -- what the running list build builds
local fillJob, fillGen = nil, 0 -- the staged fill of the shown list (ADR 0038)
Browser.STAGE = 100 -- rows drawn at once; the rest in steps of as many
Browser.FILTER_W = 140 -- the list pane's filter box

local function db()
  return mod.db.profile
end

local function data()
  return B:GetService("data")
end

-- ---------------------------------------------------------------------------------------------
-- The page: the dossier of the subject (C2, ADR 0014); the Browser owns no sections, it renders
-- what Data, Quests and Gold register. The band's own button here is the bookmark.
-- ---------------------------------------------------------------------------------------------

-- Whether rows show their worth (the setting "Show what quests and items are worth").
function Browser.ShowWorth()
  return not (mod and mod.db and mod.db.profile.showWorth == false)
end

-- The host's buttons on the band: the bookmark toggle.
function Browser.BandButtons(ref)
  local on = Browser.IsBookmarked(ref)
  return {
    {
      label = on and L["Bookmarked"] or L["Bookmark"],
      tip = on and L["Kept in your bookmarks. Click to remove it."]
        or L["Keep this page: Home and Bookmarks list it."],
      accent = on,
      onClick = function()
        Browser.ToggleBookmark(ref)
        Browser.Render()
      end,
    },
  }
end

-- The list pane shows the tree (lists, the search, views, bookmarks) or the Here dossier (the
-- player's zone); the one going away lets its sections take their own frames (Quests' item bar).
local function showHere(on)
  if on then
    tree.chips:Hide()
    tree.scroll:Hide()
    tree.bar:Hide()
    hereDossier:Show()
  else
    if hereDossier:IsShown() then
      hereDossier:NotifyHide()
    end
    hereDossier:Hide()
    tree.chips:Show()
    tree.scroll:Show()
    if not tree.opts.pages then
      tree.bar:Show() -- pages have no scroll bar (ADR 0058)
    end
  end
end

-- What the panes show (ADR 0018): the list pane the newest entry at or before the cursor that is
-- not a page (Here before any other), the detail pane the newest page (the player's zone before
-- any). A row click pushes a page and keeps the list; a navigation click pushes a list and keeps
-- the page; Back and Forward walk both.
function Browser.ListEntry()
  if current and current.kind ~= "page" then
    return current
  end
  for i = cursor, 1, -1 do
    local entry = history[i]
    if entry and entry.kind ~= "page" then
      return entry
    end
  end
  return hereEntry
end

-- The page the detail pane keeps (not the preview), nil before the first page.
function Browser.ShownPage()
  if current and current.kind == "page" then
    return current.ref
  end
  for i = cursor, 1, -1 do
    local entry = history[i]
    if entry and entry.kind == "page" then
      return entry.ref
    end
  end
  return nil
end

local function zoneRef()
  local map = B.Coords.PlayerMap()
  if not map then
    map = select(4, B.Coords.Player())
  end
  return map and ("zone:" .. map) or nil
end

-- The subject of the detail pane: the kept page, else the player's zone.
function Browser.PageRef()
  return Browser.ShownPage() or zoneRef()
end

-- ---------------------------------------------------------------------------------------------
-- Lists by type, built as a job: rows with their dimension values; the filter bar counts them
-- ---------------------------------------------------------------------------------------------

local function listDef(typ)
  for _, def in ipairs(Browser.Lists()) do
    if def.type == typ then
      return def
    end
  end
  return nil
end

-- A dimension value as a key: a string, or a list of strings (an NPC with two services); a flags
-- table of an old pack and a number become their text, nothing "Other" (sorting mixed values threw
-- "attempt to compare two table values", Forever 21.10.2026).
local function facetKey(value)
  if type(value) == "table" then
    if #value == 0 then
      return "Other"
    elseif #value == 1 then
      return tostring(value[1])
    end
    local out = {}
    for i, v in ipairs(value) do
      out[i] = tostring(v)
    end
    return out
  end
  if value == nil or value == "" then
    return "Other"
  end
  return tostring(value)
end
Browser.FacetKey = facetKey

-- Names that repeat in a list say where they are ("Cathedral Square" 30
-- times in the Objects list, without context): the zone in grey after the name; with `mergeSame`
-- the rows of one name in one zone become one row, "N places" (the signposts of a square, the
-- anvils of a town). Returns the rows and the new total; the near counts follow.
function Browser.TellApart(rows, def, d, typ, near, total)
  local count = {}
  for _, row in ipairs(rows) do
    count[row[2]] = (count[row[2]] or 0) + 1
  end
  local out, seen = {}, {}
  for _, row in ipairs(rows) do
    if count[row[2]] > 1 then
      local r = d:Get(typ, row[1])
      local zone = r and (r.zone or (r.spawns and r.spawns[1] and r.spawns[1][1]))
      local z = zone and d:Get("zone", zone)
      local zoneName = z and z.name or nil
      local key = row[2] .. "|" .. tostring(zoneName)
      local first = def.mergeSame and seen[key]
      if first then
        first.places = first.places + 1
        total = total - 1
        if row[4] == "here" then
          near.here = near.here - 1
          near.continent = near.continent - 1
        elseif row[4] == "continent" then
          near.continent = near.continent - 1
        end
      else
        row.zoneName, row.places = zoneName, 1
        seen[key] = row
        out[#out + 1] = row
      end
    else
      out[#out + 1] = row
    end
  end
  for _, row in ipairs(out) do
    if row.places then
      local words = row.zoneName or L["place unknown"]
      if row.places > 1 then
        words = words .. ", " .. string.format(L["%d places"], row.places)
      end
      row[6] = (row[6] or "") .. "  " .. S.H.muted .. words .. "|r"
      row.zoneName, row.places = nil, nil
    end
  end
  return out, total
end

local ROW_DIMS = 9 -- a build row: id, name, unnamed, near, level, suffix, yards, ref, zone, then the dims

-- Builds the rows of a type list; `yield` between slices. Returns the list (compact arrays, every
-- row), counts ({ near = { here, continent }, distances, default }) and the total.
function Browser.BuildList(typ, yield)
  local def = listDef(typ)
  local d = data()
  if not (def and d) then
    return { type = typ, entity = typ, n = 0, dims = {}, values = {} }, {}, 0
  end
  local listType = typ
  typ = def.entity or typ -- the data type of the records from here on
  local dims = Browser.Dims(def)
  local rows, counts, total = {}, {}, 0
  local near = { here = 0, continent = 0 } -- how many rows each "near" level keeps (C9)
  if not def.noNear then
    counts.near = near
  end
  local map = B.Coords.PlayerMap()
  if not map then
    map = select(4, B.Coords.Player())
  end
  local playerZone = map and d:Get("zone", map) or nil
  local continent = playerZone and playerZone.continent or nil
  -- "Nearest first" (S2, 22.10.2026, map.md's "Near me" list): yards from the player at build
  -- time, from the record's first spawn, a zone's centre or a quest's zone; nil without a place
  local pc, px, py = B.Coords.Player()
  local function yards(r, id)
    if not pc then
      return nil
    end
    local m, x, y
    if typ == "zone" then
      m, x, y = id, 0.5, 0.5
    elseif r.spawns and r.spawns[1] then
      m, x, y = r.spawns[1][1], r.spawns[1][2], r.spawns[1][3]
    elseif r.map and r.x and r.y then -- a farm spot
      m, x, y = r.map, r.x, r.y
    elseif r.zone then
      m, x, y = r.zone, 0.5, 0.5
    end
    if not m then
      return nil
    end
    local c, wx, wy = B.Coords.ToWorld(m, x, y)
    if c ~= pc then
      return nil
    end
    return math.sqrt((wx - px) ^ 2 + (wy - py) ^ 2)
  end
  counts.distances = 0
  if def.noNear and continent ~= nil then
    -- the Zones list opens on the player's continent
    counts.default = B.Coords.ContinentName(continent)
  end
  -- The list is compact (R10, 22.10.2026: 30,000 item rows as tables held 27 MB): arrays in text
  -- order (ids, texts, dimension values, near levels); row tables exist only for the rows shown.
  local merged = {} -- instances by name: the index of the first floor, the floors counted (R5)
  local floors = {}
  local namesakes = {} -- zones by name and continent: the row index and the record it shows
  -- a zone record with something of its own; the namesake without it gives way
  local function richer(r, than)
    local a = (r.questsA or r.questsH or r.levelLo) ~= nil
    local b = (than.questsA or than.questsH or than.levelLo) ~= nil
    return a and not b
  end
  local function uncount(row)
    total = total - 1
    if row[4] == "here" then
      near.here = near.here - 1
      near.continent = near.continent - 1
    elseif row[4] == "continent" then
      near.continent = near.continent - 1
    end
    if row[7] then
      counts.distances = counts.distances - 1
    end
  end
  local n = 0
  for _, id in ipairs(def.ids and def.ids() or d:Each(typ)) do
    n = n + 1
    if yield and n % LIST_SLICE == 0 then
      yield()
    end
    local r
    if def.record then -- a registered list (RegisterList): its own records
      r = def.record(id)
    else
      r = d:Get(typ, id)
    end
    if r and def.keep and not def.keep(r) then
      r = nil -- another list's record (an NPC with a service, in the Mobs list)
    end
    if r then
      local instance = def.mergeInstances and r.mapType == UI_MAP_DUNGEON and r.name
      local sameKey = def.mergeNamesakes
        and not instance
        and r.name
        and (r.name .. "|" .. tostring(r.continent))
      local same = sameKey and namesakes[sameKey]
      if instance and merged[instance] then
        floors[merged[instance]] = floors[merged[instance]] + 1
      elseif not same or richer(r, same.rec) then -- a poorer namesake gets no row
        total = total + 1
        -- the name as the pack holds it (one string, shared), the level as a number, a band or
        -- floors suffix only where one exists: the row text is composed for the rows shown
        -- the pack's name, else one the client gave before; rows still without one ask the client
        -- when they are shown (Browser.ListText): a request per row of a long list would flood it
        local name = r.name or (d.KnownName and d:KnownName(typ, id))
        local unnamed = name == nil
        name = name or (typ .. " " .. tostring(id))
        local suffix, levelBand
        if typ == "zone" and r.levelLo and r.levelHi then -- the zone index: band rows (C9)
          levelBand = r.levelLo .. "-" .. r.levelHi -- on a tile it is the badge, not a word
        elseif def.suffix then
          local words = def.suffix(r)
          suffix = words and ("  " .. S.H.muted .. words .. "|r") or nil
        end
        local where = Browser.NearOf(typ, id, r, d, map, continent)
        if where == "here" then
          near.here = near.here + 1
          near.continent = near.continent + 1
        elseif where == "continent" then
          near.continent = near.continent + 1
        end
        local dist = yards(r, id)
        if dist then
          counts.distances = counts.distances + 1
        end
        local ref = def.ref and def.ref(id, r) or nil
        -- the zone the row belongs to (ADR 0038: the zone groups of a Nearest list): the first
        -- spawn's map, a spot's or quest's zone, a zone itself
        local zone = (r.spawns and r.spawns[1] and r.spawns[1][1])
          or r.map
          or r.zone
          or (typ == "zone" and id)
          or nil
        local row = { id, name, unnamed, where, r.level, suffix, dist, ref, zone }
        row.band = levelBand
        for k, dim in ipairs(dims) do
          row[ROW_DIMS + k] = facetKey(dim.value(r, d, ref or (typ .. ":" .. tostring(id))))
        end
        if same then
          uncount(rows[same.index]) -- the richer namesake takes the poorer one's row
          rows[same.index] = row
          same.rec = r
        else
          rows[#rows + 1] = row
          if sameKey then
            namesakes[sameKey] = { index = #rows, rec = r }
          end
        end
        if instance then
          merged[instance] = #rows
          floors[#rows] = 1
        end
      end
    end
  end
  for i, count in pairs(floors) do
    if count > 1 then
      rows[i][6] = (rows[i][6] or "") .. "  " .. S.H.muted .. string.format(L["%d floors"], count) .. "|r"
    end
  end
  if def.zoneSuffix then
    rows, total = Browser.TellApart(rows, def, d, typ, near, total)
  end
  table.sort(rows, function(a, b)
    if a[2] ~= b[2] then
      return a[2] < b[2]
    end
    return (a[5] or 0) < (b[5] or 0)
  end)
  local list = {
    type = listType,
    entity = typ,
    n = #rows,
    dims = dims,
    ids = {},
    names = {},
    unnamed = {}, -- rows whose name is still the type and the id: asked when shown
    values = {},
    nears = {},
    levels = {},
    bands = {}, -- a zone's level band ("7-11"), nil without one
    suffixes = {},
    dists = {},
    zones = {}, -- the zone (map id) of each row, nil without one (ADR 0038)
    refs = def.ref and {} or nil, -- a registered list's rows open their own entity (a chain's quest)
    sorts = {}, -- registered sorts: id -> { order, values }, computed when picked
  }
  for k = 1, #dims do
    list.values[k] = {}
  end
  local seen = {} -- the keys of each dimension: one key alone is nothing to filter by
  list.distinct = {}
  for k = 1, #dims do
    seen[k], list.distinct[k] = {}, 0
  end
  local function note(k, key)
    if not seen[k][key] then
      seen[k][key] = true
      list.distinct[k] = list.distinct[k] + 1
    end
  end
  for i, row in ipairs(rows) do
    list.ids[i], list.names[i], list.nears[i] = row[1], row[2], row[4]
    list.unnamed[i] = row[3] or nil
    list.levels[i], list.suffixes[i], list.dists[i] = row[5], row[6], row[7]
    list.bands[i] = row.band
    list.zones[i] = row[9]
    if list.refs then
      list.refs[i] = row[8]
    end
    for k = 1, #dims do
      local value = row[ROW_DIMS + k]
      list.values[k][i] = value
      if list.distinct[k] < 2 then
        if type(value) == "table" then
          for _, v in ipairs(value) do
            note(k, v)
          end
        else
          note(k, value)
        end
      end
    end
    rows[i] = nil
  end
  return list, counts, total
end

-- The row indexes nearest first (the rows without a distance after them, in name order), built
-- once per list when the sort is chosen.
local function nearOrder(list)
  if list.nearOrder then
    return list.nearOrder
  end
  local order = {}
  for i = 1, list.n do
    order[i] = i
  end
  table.sort(order, function(a, b)
    local da, db_ = list.dists[a], list.dists[b]
    if (da ~= nil) ~= (db_ ~= nil) then
      return da ~= nil
    end
    if da ~= nil and da ~= db_ then
      return da < db_
    end
    return a < b
  end)
  list.nearOrder = order
  return order
end

-- The ref a list row opens.
local function listRef(list, i)
  return list.refs and list.refs[i] or ((list.entity or list.type) .. ":" .. tostring(list.ids[i]))
end

Browser.NEAR_TIMED = 100 -- the rows nearest by straight line that the Nearest sort orders by time

-- The Nearest order by travel time (W8): the NEAR_TIMED rows nearest by straight line (the
-- candidates, never shown as a distance) ordered by the world graph's times from its cache, the
-- rows without a time yet after them; the rest as they were. Asked again on every render, so
-- BASTIANS_GRAPH_TIMES refines it. Without the graph's network the straight-line order stays.
local function timeOrder(list, order)
  local graph = B:GetService("graph")
  if not (graph and graph:Ready()) then
    return order
  end
  local n = math.min(#order, Browser.NEAR_TIMED)
  local top, secs, rank = {}, {}, {}
  for k = 1, n do
    local i = order[k]
    top[k], rank[i] = i, k
    secs[i] = graph:Time(listRef(list, i))
  end
  table.sort(top, function(a, b)
    local sa, sb = secs[a], secs[b]
    if (sa ~= nil) ~= (sb ~= nil) then
      return sa ~= nil
    end
    if sa ~= nil and sa ~= sb then
      return sa < sb
    end
    return rank[a] < rank[b]
  end)
  for k = n + 1, #order do
    top[k] = order[k]
  end
  return top
end

-- The text of a list row: the name, the level or the band or the floors in grey.
function Browser.ListText(list, i)
  if list.unnamed and list.unnamed[i] and (list.entity or not list.refs) then
    -- a shown row without a name: the entity asks the client (the name arrives with its load
    -- event and is kept for the next session)
    local name = B:Entity((list.entity or list.type) .. ":" .. tostring(list.ids[i])):Name()
    if name then
      list.names[i], list.unnamed[i] = name, nil
    end
  end
  local text = list.names[i]
  if list.levels[i] then
    text = text .. "  " .. S.H.muted .. tostring(list.levels[i]) .. "|r"
  end
  if list.bands and list.bands[i] then
    text = text .. "  " .. S.H.muted .. list.bands[i] .. "|r"
  end
  if list.suffixes[i] then
    text = text .. list.suffixes[i]
  end
  return text
end

-- Where a record is, relative to the player (C9): "here" (on the player's map), "continent" (on
-- the player's continent), else "all". Records without a place (items, recipes) are "all"; the
-- second value says whether the record has a place at all (the search's scope keeps the others).
function Browser.NearOf(typ, id, r, d, map, continent)
  if not map then
    return "all", false
  end
  local zone
  if typ == "zone" then
    zone = id
  elseif typ == "spot" then
    zone = r.map
  else
    zone = r.zone
    if not zone and r.spawns and r.spawns[1] then
      zone = r.spawns[1][1]
    end
  end
  if not zone then
    return "all", false
  end
  if zone == map then
    return "here", true
  end
  if continent ~= nil then
    local z = d:Get("zone", zone)
    if z and z.continent == continent then
      return "continent", true
    end
  end
  return "all", true
end

-- `want` is one key, or a set { [key] = true } of a chips dimension (any of them matches).
local function matches(value, want)
  if type(want) == "table" then
    if type(value) == "table" then
      for _, v in ipairs(value) do
        if want[v] then
          return true
        end
      end
      return false
    end
    return want[value] == true
  end
  if type(value) == "table" then
    for _, v in ipairs(value) do
      if v == want then
        return true
      end
    end
    return false
  end
  return value == want
end

local function addCount(counts, value)
  if type(value) == "table" then
    for _, v in ipairs(value) do
      counts[v] = (counts[v] or 0) + 1
    end
  elseif value ~= nil then
    counts[value] = (counts[value] or 0) + 1
  end
end

local function nearOk(near, where)
  if near == "here" then
    return where == "here"
  elseif near == "continent" then
    return where ~= "all"
  end
  return true
end

-- The filter pass (ADR 0016): the row indexes the state keeps, in `order` (nil: name order), at
-- most MAX_ROWS of them, and the counts of every choice given the other active filters (a row
-- that fails exactly one dimension counts for that dimension only). state = { near, picks =
-- { [dimId] = key } }. Returns { rows, total, near = { here, continent, all }, counts = { [k] =
-- { [key] = n } }, all = { [k] = rows passing every other dimension } }.
function Browser.Filter(list, state, order)
  local out = { rows = {}, total = 0, near = { here = 0, continent = 0, all = 0 }, counts = {}, all = {} }
  if not list or list.n == 0 then
    return out
  end
  local dims = list.dims or {}
  local nd = #dims
  local picks = state.picks or {}
  local want = {}
  for k, dim in ipairs(dims) do
    out.counts[k], out.all[k] = {}, 0
    local pick = picks[dim.id]
    if type(pick) == "table" and next(pick) == nil then
      pick = nil -- an empty set keeps everything
    end
    want[k] = pick
  end
  local near = state.near
  local nearCounts = out.near
  -- the pane's filter text: a row whose name does not match it is no
  -- row at all, before the cap, so the counts and the "N of M" follow it; the suite's search
  -- syntax with the list's fields (ADR 0045)
  local fields = Browser.ListFields(list)
  local q = state.filterText and B.Query.Compile(state.filterText, { fields = fields })
  if q and q.empty then
    q = nil
  end
  local low = q and Browser.LowNames(list) or nil
  -- typed on at the end of the last text: only the rows it kept are tested again (owner, retail
  -- 31.10.2026: every key took seconds on the full NPC list); `state.textKept` is that set
  local prev = state.textKept
  local within = q
      and prev
      and prev.list == list
      and B.Query.Narrows(prev.text, state.filterText, { fields = fields })
      and prev.set
    or nil
  local kept = q and {} or nil
  for kk = 1, list.n do
    local i = order and order[kk] or kk
    local where = list.nears[i]
    local fails, failed = 0, nil
    if low and ((within and not within[i]) or not q:MatchLower(low[i], i)) then
      fails, failed = 99, -1
    elseif not nearOk(near, where) then
      fails, failed = 1, 0
    end
    for k = 1, nd do
      if want[k] ~= nil and not matches(list.values[k][i], want[k]) then
        fails, failed = fails + 1, k
        if fails > 1 then
          break
        end
      end
    end
    if kept and fails ~= 99 then
      kept[i] = true
    end
    if fails <= 1 and (fails == 0 or failed == 0) then
      nearCounts.all = nearCounts.all + 1
      if where ~= "all" then
        nearCounts.continent = nearCounts.continent + 1
      end
      if where == "here" then
        nearCounts.here = nearCounts.here + 1
      end
    end
    if fails == 0 then
      out.total = out.total + 1
      for k = 1, nd do
        addCount(out.counts[k], list.values[k][i])
        out.all[k] = out.all[k] + 1
      end
      if #out.rows < MAX_ROWS then
        out.rows[#out.rows + 1] = i
      end
    elseif fails == 1 and failed > 0 then
      addCount(out.counts[failed], list.values[failed][i])
      out.all[failed] = out.all[failed] + 1
    end
  end
  state.textKept = kept and { list = list, text = state.filterText, set = kept } or nil
  return out
end

-- The names of a list in lower case, made once per list for the filter text.
function Browser.LowNames(list)
  if not list.lowNames then
    local low = {}
    local def = listDef(list.type)
    local words = def and def.record and def.words or nil -- what a registered list adds (§7c)
    for i = 1, list.n do
      local text = list.names[i] or ""
      local record = words and def.record(list.ids[i]) or nil
      local more = record and words(record) or nil
      low[i] = string.lower(more and (text .. " " .. more) or text)
    end
    list.lowNames = low
  end
  return list.lowNames
end

-- The glyph of a list row (ADR 0018 B), from the list's own facet values, so no record is decoded:
-- an NPC by its first service or its rank, an object or a node by its kind, the rest by type.
local TYPE_GLYPH = {
  npc = "mob",
  item = "item",
  object = "object", -- its own symbol
  node = "herb",
  zone = "zone",
  recipe = "trainer",
  quest = "quest",
  spot = "spot",
}
local KIND_GLYPH = {
  ["Vendor"] = "vendor",
  ["Trainer"] = "trainer",
  ["Flight master"] = "flight",
  ["Innkeeper"] = "innkeeper",
  ["Banker"] = "banker",
  ["Auctioneer"] = "auctioneer",
  ["Repair"] = "repair",
  ["Quest giver"] = "quest",
  ["Rare##rank"] = "rare",
  ["Rare elite"] = "rare",
  ["Chest"] = "treasure",
  ["Herb"] = "herb",
  ["Ore"] = "mine",
  ["Fishing pool"] = "fish",
  ["Treasure"] = "treasure",
  ["Quest object"] = "quest",
  ["Quest place"] = "quest",
}
Browser.KIND_GLYPH = KIND_GLYPH

local function dimIndex(list, id)
  for k, dim in ipairs(list.dims or {}) do
    if dim.id == id then
      return k
    end
  end
  return nil
end

function Browser.RowGlyph(list, i)
  for _, id in ipairs({ "service", "kind", "rank" }) do
    local k = dimIndex(list, id)
    local value = k and list.values[k][i]
    if type(value) == "table" then
      value = value[1]
    end
    if value and KIND_GLYPH[value] then
      return KIND_GLYPH[value]
    end
  end
  local def = listDef(list.type)
  return def and def.glyph or TYPE_GLYPH[list.type] or "other"
end

-- The row tables of a filter pass: one line each (ADR 0018 B), the glyph, the text with the sort's
-- words in grey (the distance, the loot per kill), the ref a click opens.
local function rowsOf(list, indexes, sortWords)
  local out = {}
  local typ = list.entity or list.type
  for _, i in ipairs(indexes) do
    local ref = list.refs and list.refs[i] or (typ .. ":" .. tostring(list.ids[i]))
    local text = Browser.ListText(list, i)
    local words = sortWords and sortWords(i)
    if words then
      text = text .. "  " .. S.H.muted .. words .. "|r"
    end
    out[#out + 1] = {
      id = ref,
      ref = ref,
      text = text,
      -- as a tile (ADR 0056): the name alone on the first line; the level is the badge (the
      -- entity's own where its tile has one), the sort's words stand where the worth would
      title = list.names[i] .. (list.suffixes[i] or ""),
      badge = list.levels[i] or (list.bands and list.bands[i]) or nil,
      value = words,
      near = list.nears[i],
      icon = B.UI.IconTexture(Browser.RowGlyph(list, i)),
    }
  end
  return out
end

-- ---------------------------------------------------------------------------------------------
-- Bookmarks (per character) and history
-- ---------------------------------------------------------------------------------------------

local function bookmarks()
  local list = mod.db.char.bookmarks
  if type(list) ~= "table" then
    list = {}
    mod.db.char.bookmarks = list
  end
  return list
end

function Browser.IsBookmarked(ref)
  for _, r in ipairs(bookmarks()) do
    if r == ref then
      return true
    end
  end
  return false
end

function Browser.ToggleBookmark(ref)
  local list = bookmarks()
  for i, r in ipairs(list) do
    if r == ref then
      table.remove(list, i)
      return false
    end
  end
  list[#list + 1] = ref
  return true
end

local function sameEntry(a, b)
  return a and b and a.kind == b.kind and a.ref == b.ref and a.type == b.type
end

local function push(entry)
  if sameEntry(history[cursor], entry) then
    return
  end
  for i = #history, cursor + 1, -1 do
    history[i] = nil
  end
  history[#history + 1] = entry
  cursor = #history
  while #history > 50 do
    table.remove(history, 1)
    cursor = cursor - 1
  end
end

function Browser.History()
  return history, cursor
end

-- The trail (C5): the pages up to the cursor, oldest first, at most TRAIL_MAX, each with its
-- place in the history so a click can go back there.
local TRAIL_MAX = 8
function Browser.Trail()
  local out = {}
  for i = 1, cursor do
    local entry = history[i]
    if entry and entry.kind == "page" then
      out[#out + 1] = { ref = entry.ref, index = i, name = B:Entity(entry.ref):Name() or entry.ref }
    end
  end
  while #out > TRAIL_MAX do
    table.remove(out, 1)
  end
  return out
end

-- ---------------------------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------------------------

-- The Dock button shows the state (accent while docked).
function Browser.UpdateDock()
  local dock = toolbar and toolbar.dock
  if not dock then
    return
  end
  local on = B.UI.IsDocked()
  local c = on and S.C.accent or S.C.text
  dock.label:SetTextColor(c[1], c[2], c[3])
  S.setEdges(dock.edges, on and S.C.accent or S.C.line, on and 0.8 or nil)
end

local function setNav()
  Browser.UpdateDock()
  toolbar.back.enabledFlat = cursor > 1
  toolbar.forward.enabledFlat = cursor < #history
  local back, fwd = S.C.dim, S.C.dim
  if cursor > 1 then
    back = S.C.text
  end
  if cursor < #history then
    fwd = S.C.text
  end
  toolbar.back.label:SetTextColor(back[1], back[2], back[3])
  toolbar.forward.label:SetTextColor(fwd[1], fwd[2], fwd[3])
end

-- The header block of an entry that is not a view: no control bar.
local function noHeader()
  header:SetHeight(1)
end

-- The list's row of the kept subject carries the selection mark.
local function markSelected(ref)
  if not tree then
    return
  end
  local id
  local function find(rows)
    for _, row in ipairs(rows or {}) do
      if row.ref ~= nil and row.ref == ref then
        return row.id
      end
      if row.children then
        local hit = find(row.children)
        if hit then
          return hit
        end
      end
    end
  end
  id = find(tree.rows)
  if tree.selectedID ~= id then
    tree.selectedID = id
    tree:Render()
  end
end

-- The detail pane (ADR 0018): the preview while a row rests under the mouse, else the kept page,
-- else the player's zone; the trail is the way to the kept page.
-- How many things the page lists (rows with a ref, in every chapter and tab).
function Browser.PageThings()
  local page = dossier and dossier.data
  local DossierUtil = B.UI.DossierUtil
  local n = 0
  for _, chapter in ipairs(page and page.chapters or {}) do
    for _, block in ipairs(chapter.blocks or {}) do
      for _, row in ipairs(DossierUtil.things(block)) do
        if row.ref then
          n = n + 1
        end
      end
    end
  end
  return n
end

-- The page filter shows while the page lists more than one thing; a new page starts unfiltered.
local filteredRef
local function placePageFilter(ref)
  if not pageFilter then
    return
  end
  if ref ~= filteredRef then
    filteredRef = ref
    if (pageFilter:GetText() or "") ~= "" then
      pageFilter:SetText("") -- OnTextChanged clears the dossier's query
    end
  end
  local shown = ref ~= nil and Browser.PageThings() > 1
  pageFilter:SetShown(shown)
  local frame = dossier.frame
  local _, _, _, x = frame:GetPoint(1)
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", detailPane, "TOPLEFT", x or 0, shown and -28 or 0)
  frame:SetPoint("BOTTOMRIGHT", detailPane, "BOTTOMRIGHT", -14, 0)
end
Browser.PlacePageFilter = placePageFilter

function Browser.PageFilterBox()
  return pageFilter
end

local function renderDetail()
  local ref = previewRef or Browser.PageRef()
  if not ref then
    dossier:Clear()
    placePageFilter(nil)
    return
  end
  dossier:SetTrail(Browser.Trail(), function(item)
    Browser.GoTo(item.index)
  end)
  local sections = dossier:Sections(ref) -- built in the page's palette (paper or the look's)
  if ref ~= filteredRef then
    placePageFilter(ref) -- a new page: its query cleared before it is laid out
  end
  dossier:SetSubject(ref, sections, { source = "browser" }, { preview = previewRef ~= nil })
  placePageFilter(ref)
  markSelected(Browser.ShownPage())
end
Browser.RenderDetail = renderDetail

local function renderList(typ)
  local def = listDef(typ)
  win:SetTitle(L[def and def.label or typ])
  noHeader()
  local entry = shownList
  -- a list built once is kept until a pack loads or the player changes zone (R5, owner
  -- 22.10.2026: "the lists are always rebuilt"); the entry takes the cached rows at once
  local cached = Browser.listCache[typ]
  local map = B.Coords.PlayerMap()
  local gen = def and facetGen(def) or ""
  if cached and cached.map == map then -- the near levels and the default facet are per zone
    entry.list, entry.counts, entry.total = cached.list, cached.counts, cached.total
    Browser.ShowList(entry)
    if cached.gen == gen then
      return
    end
    -- a facet moved (a quest handed in): the old rows stay while the new ones build
  else
    tree:SetFilters({})
    Browser.SetScope(nil)
    tree:SetRows({ { text = S.H.muted .. L["Building the list ..."] .. "|r", kind = "para" } })
    summary:SetText(L["Building the list ..."])
  end
  if listJob then
    if listJobType == typ and listJobGen == gen and listJobMap == map then
      return -- this build runs already: it shows the list when done (a quest event per loot)
    end
    listJob:Cancel()
  end
  listJobType, listJobGen, listJobMap = typ, gen, map
  listJob = B.Jobs:Run(mod, "browser-list-" .. typ, function(yield)
    local list, counts, total = Browser.BuildList(typ, yield)
    Browser.listCache[typ] = { list = list, counts = counts, total = total, map = map, gen = gen }
  end, {
    onDone = function()
      listJob = nil
      local now = shownList
      if not (now and now.kind == "list" and now.type == typ and win and win:IsShown()) then
        return
      end
      local built = Browser.listCache[typ]
      now.list, now.counts, now.total = built.list, built.counts, built.total
      Browser.ShowList(now)
      if def and facetGen(def) ~= gen then
        Browser.Schedule() -- the facets moved again while it built
      end
    end,
  })
end

-- What a list opens on: everything ("when I click on Dungeons it jumps
-- automatically to a zone ... instead of automatically setting that"). ~~C9: the player's zone when
-- it has rows, else the continent.~~ The player narrows it: the scope chip, the list's Zone filter.
function Browser.DefaultNear()
  return nil
end

-- The filter choices are kept per list type (ADR 0016) in the profile: { near = "here" |
-- "continent" | false (All), picks = { [dimId] = key }, sort = "near" | filter id | nil }.
local function savedFilters()
  local p = db()
  if type(p.listFilters) ~= "table" then
    p.listFilters = {}
  end
  return p.listFilters
end

function Browser.SaveFilters(entry)
  local picks = {}
  for k, v in pairs(entry.picks or {}) do
    if type(v) == "table" then -- a chips dimension's set, copied (ADR 0038)
      local set = {}
      for key in pairs(v) do
        set[key] = true
      end
      picks[k] = set
    else
      picks[k] = v
    end
  end
  savedFilters()[entry.type] = {
    near = entry.nearChosen and (entry.near or false) or nil,
    picks = picks,
    sort = entry.sort,
  }
end

-- An entry's first show: the remembered choices, else the defaults (the near level by C9, the
-- Zones list on the player's continent).
local function restoreFilters(entry)
  entry.restored = true
  local saved = savedFilters()[entry.type]
  entry.picks = {}
  if type(saved) == "table" then
    for k, v in pairs(saved.picks or {}) do
      if type(v) == "table" then
        local set = {}
        for key in pairs(v) do
          set[key] = true
        end
        entry.picks[k] = set
      else
        entry.picks[k] = v
      end
    end
    entry.sort = saved.sort
    if saved.near ~= nil then
      entry.near, entry.nearChosen = saved.near or nil, true
    end
    entry.remembered = true
  end
  if not entry.nearChosen then
    entry.near = Browser.DefaultNear(entry.counts)
  end
  if entry.counts and entry.counts.default and entry.picks.continent == nil and not entry.remembered then
    entry.picks.continent = entry.counts.default -- the Zones list opens on the player's continent (R5)
  end
end

-- The sorts of a list type: by name, nearest first where rows have a place (S2), the sorts apps
-- register (Loot per kill, Most XP, ...).
function Browser.Sorts(list, counts)
  local out = { { key = "name", label = L["Name"] } }
  if counts and (counts.distances or 0) > 0 then
    out[#out + 1] = { key = "near", label = L["Nearest"] }
  end
  for _, f in ipairs(B:GetFilters(list.entity or list.type, "sort")) do
    out[#out + 1] = { key = f.id, label = L[f.label], def = f }
  end
  return out
end

-- A registered sort over a built list, as a job: the value of every row through the provider,
-- then the order (rows without a value last, in name order). Kept with the list until a pack
-- loads or the sort's invalidateOn messages arrive.
local sortJob
local function computeSort(list, def, onDone)
  if sortJob then
    sortJob:Cancel()
  end
  local d = data()
  local ldef = listDef(list.type)
  local gen = B:FilterGeneration(def.id)
  sortJob = B.Jobs:Run(mod, "browser-sort-" .. def.id, function(yield)
    local values = {}
    for i = 1, list.n do
      if yield and i % LIST_SLICE == 0 then
        yield()
      end
      local ref = listRef(list, i)
      local r
      if ldef and ldef.record then -- a registered list's own record (a chain)
        r = ldef.record(list.ids[i])
      else
        r = d and d:Get(list.entity or list.type, list.ids[i]) or nil
      end
      local v = B:FilterValue(def, ref, r)
      values[i] = type(v) == "number" and v or nil
    end
    local order = {}
    for i = 1, list.n do
      order[i] = i
    end
    local asc = def.ascending
    table.sort(order, function(a, b)
      local va, vb = values[a], values[b]
      if (va ~= nil) ~= (vb ~= nil) then
        return va ~= nil
      end
      if va ~= nil and va ~= vb then
        if asc then
          return va < vb
        end
        return va > vb
      end
      return a < b
    end)
    list.sorts[def.id] = { order = order, values = values, gen = gen }
  end, {
    onDone = function()
      sortJob = nil
      onDone()
    end,
  })
end

-- The dimensions of the filter bar for a shown list: Where, the list's own, Sort.
local OTHER_KEYS = { Other = true, ["No service"] = true, ["no level"] = true }
local function choicesOf(dim, counts, active)
  local choices = {}
  for key, count in pairs(counts) do
    local label = dim.labels and dim.labels(key) or L[key]
    choices[#choices + 1] = { key = key, label = label, count = count }
  end
  local function keep(key) -- a choice with no rows left stays visible
    if counts[key] == nil then
      choices[#choices + 1] = { key = key, label = dim.labels and dim.labels(key) or L[key], count = 0 }
    end
  end
  if type(active) == "table" then
    for key in pairs(active) do
      keep(key)
    end
  elseif active ~= nil then
    keep(active)
  end
  table.sort(choices, function(a, b)
    local oa, ob = OTHER_KEYS[a.key] or false, OTHER_KEYS[b.key] or false
    if oa ~= ob then
      return ob -- "Other" and the like last
    end
    if dim.sortKey then
      local ka, kb = dim.sortKey(a.key), dim.sortKey(b.key)
      if ka ~= kb then
        return ka < kb
      end
    elseif a.count ~= b.count then
      return a.count > b.count
    end
    return tostring(a.label) < tostring(b.label)
  end)
  return choices
end

function Browser.FilterDims(entry, result)
  local list, counts = entry.list, entry.counts or {}
  local def = listDef(entry.type)
  local out = {}
  if not list or list.n == 0 then
    return out -- nothing to filter
  end
  local near = counts.near
  if near and near.continent > 0 and not (def and def.noNear) then
    out[#out + 1] = {
      id = "where",
      title = L["Where"],
      kind = "spot",
      choices = {
        { key = "here", label = L["Here"], count = result.near.here },
        { key = "continent", label = L["Continent"], count = result.near.continent },
      },
      active = entry.near,
      all = { label = L["All"], count = result.near.all },
      tip = L["Where the rows are: in your zone, on your continent, or everywhere."],
      onSelect = function(key)
        entry.near, entry.nearChosen = key, true
        Browser.SaveFilters(entry)
        Browser.ShowList(entry)
      end,
    }
  end
  for k, dim in ipairs(list.dims or {}) do
    local active = entry.picks[dim.id]
    if dim.chips and type(active) == "string" then
      active = { [active] = true } -- a choice remembered before the chips (ADR 0038)
      entry.picks[dim.id] = active
    end
    -- a dimension whose rows all share one key (retail objects have no kinds, retail quests no
    -- levels) shows no pill, unless a remembered choice is on it
    if active ~= nil or not list.distinct or (list.distinct[k] or 0) >= 2 then
      local choices = choicesOf(dim, result.counts[k] or {}, active)
      if dim.chips then
        for _, c in ipairs(choices) do -- the service's tile and colour on the chip (ADR 0038)
          local glyph = KIND_GLYPH[c.key]
          c.icon = glyph and B.UI.IconTexture(glyph) or nil
          c.token = S.ServiceToken(c.key)
        end
      end
      out[#out + 1] = {
        id = dim.id,
        title = L[dim.title],
        kind = dim.kind, -- the pill's tile (ADR 0046); a dimension without one has none
        chips = dim.chips or nil,
        choices = choices,
        active = active,
        all = { label = L["All"], count = result.all[k] },
        onSelect = function(key)
          if dim.chips then
            -- a chip toggles its key in the set; All empties it (ADR 0038)
            local set = type(entry.picks[dim.id]) == "table" and entry.picks[dim.id] or {}
            if key == nil then
              set = {}
            elseif set[key] then
              set[key] = nil
            else
              set[key] = true
            end
            entry.picks[dim.id] = next(set) and set or nil
          else
            entry.picks[dim.id] = key
          end
          Browser.SaveFilters(entry)
          Browser.ShowList(entry)
        end,
      }
    end
  end
  local groups, groupDefault = Browser.GroupChoices(entry)
  if groups then
    -- the groups of a list, remembered per list type: the zone groups of a Nearest list (ADR
    -- 0038), and the dimensions a list may be grouped by (a chain's progress, ADR 0055)
    out[#out + 1] = {
      id = "groups",
      title = L["Groups"],
      choices = groups,
      active = Browser.GroupOf(entry) or "none",
      default = groupDefault,
      all = false,
      tip = #groups > 2 and L["The rows under a heading: what they are grouped by."]
        or L["Nearest first, the rows under their zone's name."],
      onSelect = function(key)
        Browser.SetGroups(entry, key)
        Browser.ShowList(entry)
      end,
    }
  end
  local sorts = Browser.Sorts(list, counts)
  out[#out + 1] = {
    id = "sort",
    title = L["Sort"],
    choices = sorts,
    active = entry.sort or "name",
    default = "name",
    all = false,
    tip = L["The order of the rows."],
    onSelect = function(key)
      entry.sort = key ~= "name" and key or nil
      Browser.SaveFilters(entry)
      Browser.ShowList(entry)
    end,
  }
  return out
end

-- The order and the grey words of the entry's sort; a registered sort not computed yet starts its
-- job and shows the name order meanwhile (`pending`).
local function sortOf(entry)
  local list = entry.list
  local sort = entry.sort
  if sort == "near" then
    return timeOrder(list, nearOrder(list)), function(i)
      return (B.UI.Away(listRef(list, i)))
    end
  end
  local def = sort and B:GetFilter(sort)
  if not (def and def.kind == "sort") then
    return nil, nil
  end
  local done = list.sorts[def.id]
  if not done or done.gen ~= B:FilterGeneration(def.id) then -- prices moved: sorted again
    computeSort(list, def, function()
      if shownList == entry and win and win:IsShown() then
        Browser.ShowList(entry)
      end
    end)
    return nil, nil, true
  end
  return done.order,
    function(i)
      local v = done.values[i]
      if v == nil then
        return nil
      end
      if def.text then
        local ok, words = pcall(def.text, v)
        return ok and words or nil
      end
      return tostring(v)
    end
end

-- The row the keys point at in the list pane, or nil (ADR 0038).
function Browser.KeyRow()
  local i = tree and tree:KeyIndex()
  return i and tree.flat[i] or nil
end

-- Moves the lit row by `step` over the rows that open something (not a group's title).
function Browser.MoveKeyRow(step)
  if not tree then
    return
  end
  local flat = tree.flat
  local i = tree:KeyIndex() or (step > 0 and 0 or #flat + 1)
  local j = i + step
  while j >= 1 and j <= #flat do
    local row = flat[j]
    if row.ref or row.onClick then
      tree:SetKeyRow(row)
      return
    end
    j = j + step
  end
end

-- The pages of the list tile (ADR 0058, PH3): the foot says "1-12 of 430" and shows only
-- when there is more than one page; the tree's rows stop above it.
function Browser.UpdatePager()
  if not (pager and tree) then
    return
  end
  local index, count, first, last, n = tree:Page()
  local shown = count > 1
  if shown ~= pager.shown then
    pager.shown = shown
    pager:SetShown(shown)
    tree.scroll:ClearAllPoints()
    tree.scroll:SetPoint("TOPLEFT", tree.chips, "BOTTOMLEFT", 0, -2)
    if shown then
      tree.scroll:SetPoint("BOTTOMRIGHT", pager, "TOPRIGHT", 0, 2)
    else
      tree.scroll:SetPoint("BOTTOMRIGHT", listPane, "BOTTOMRIGHT", -14, 0)
    end
  end
  if shown then
    pager.text:SetText(string.format(L["%d-%d of %d"], first, last, n))
    pager.prev:SetEnabledFlat(index > 1)
    pager.next:SetEnabledFlat(index < count)
  end
  pager.page, pager.count = index, count
end

-- Turns the list tile's page by `step` (the foot's arrows, Page Up and Page Down in the boxes).
function Browser.TurnPage(step)
  if tree then
    tree:TurnPage(step)
  end
end

-- Whether the mouse is over the list's rows.
function Browser.ListUnderMouse()
  return tree ~= nil and tree.scroll:IsMouseOver() == true
end

-- The order the list shows: held while the mouse is over the list (
-- "when you click several times, the detail tile jumps to another entry that you never clicked";
-- the Nearest order took every new batch of travel times, so the rows moved under a resting
-- cursor and the next click hit another row). A new list, sort or filter takes the fresh order;
-- a held one is refreshed once the mouse has left the list (Browser.OnRowHover).
function Browser.HoldOrder(entry, order)
  local key = entry.sort or "name"
  local held = entry.held
  if held and held.list == entry.list and held.sort == key and Browser.ListUnderMouse() then
    entry.heldStale = true
    return held.order
  end
  entry.held = { list = entry.list, sort = key, order = order }
  entry.heldStale = nil
  return order
end

-- Shows a built list with the entry's filters (ADR 0016): the filter bar, the rows, the summary.
function Browser.ShowList(entry)
  if not entry.list then -- nothing built (no data service): an empty list, the bar empty too
    entry.list = { type = entry.type, n = 0, dims = {}, values = {}, nears = {}, sorts = {} }
  end
  if not entry.restored then
    restoreFilters(entry)
  end
  local list = entry.list
  if entry.sort and entry.sort ~= "near" and not B:GetFilter(entry.sort) then
    entry.sort = nil -- a sort whose app is gone
  end
  if entry.sort == "near" and not (entry.counts and (entry.counts.distances or 0) > 0) then
    entry.sort = nil
  end
  local order, words, pending = sortOf(entry)
  order = Browser.HoldOrder(entry, order)
  local result = Browser.Filter(list, entry, order)
  if result.total == 0 and entry.remembered and not entry.widened then
    -- remembered choices with no rows here (another zone, a kind that is gone): All, nothing
    -- opens empty (C9); the memory itself stays
    entry.widened = true
    entry.picks = {}
    entry.near, entry.nearChosen = Browser.DefaultNear(entry.counts), false
    result = Browser.Filter(list, entry, order)
  end
  local dims = Browser.FilterDims(entry, result)
  -- "Where" is the scope chip inside the search box (ADR 0056), the rest the chips beside it
  local where = dims[1] and dims[1].id == "where" and table.remove(dims, 1) or nil
  tree:SetFilters(dims)
  Browser.SetScope(where)
  tree:SetKeyRow(nil)
  fillGen = fillGen + 1
  local gen = fillGen
  local indexes = result.rows
  local grouped, groupK, groupDim = Browser.GroupOf(entry)
  local rows = {}
  local function put(from, to)
    local slice = {}
    for i = from, to do
      slice[#slice + 1] = indexes[i]
    end
    for _, row in ipairs(rowsOf(list, slice, words)) do
      rows[#rows + 1] = row
    end
  end
  local function draw(loaded)
    local shown
    if grouped == "zone" then
      shown = Browser.GroupRows(
        rows,
        list,
        indexes,
        Browser.ZoneNames(list, indexes),
        entry.sort ~= "near" -- nearest first keeps the zones in the order they come
      )
    elseif grouped then
      shown = Browser.GroupRowsBy(rows, list, indexes, groupK, groupDim)
    else
      shown = {} -- a copy: the loading row below never lands in the rows that grow
      for j, row in ipairs(rows) do
        shown[j] = row
      end
    end
    if #shown == 0 then
      local own = listDef(entry.type) -- a list empty by nature says so itself (`emptyWords`)
      local empty = own and own.emptyWords or L["No entries. Is the data pack loaded?"]
      shown = { { text = S.H.muted .. empty .. "|r", kind = "para" } }
      if list.n > 0 then
        shown[1].text = S.H.muted .. L["Nothing matches these filters. The x on a filter clears it."] .. "|r"
      end
    elseif loaded < #indexes then
      shown[#shown + 1] = {
        id = "loading",
        kind = "para",
        text = S.H.muted .. string.format(L["Loading %d of %d ..."], loaded, #indexes) .. "|r",
      }
    end
    tree:SetRows(shown)
    markSelected(Browser.ShownPage())
    -- the foot says the page and the count (ADR 0058); this line keeps the notes: a list
    -- narrowed by a filter or the search, one still loading, one still sorting
    local text = ""
    if result.total > #indexes then
      text = string.format(L["%d of %d shown"], #indexes, result.total)
        .. " - "
        .. L["narrow with a filter or the search"]
    end
    if loaded < #indexes then
      text = text .. (text ~= "" and " - " or "") .. string.format(L["%d loaded"], loaded)
    end
    if pending then
      text = text .. (text ~= "" and " - " or "") .. L["Sorting ..."]
    end
    summary:SetText(text)
  end
  -- the staged list (ADR 0038): the first STAGE rows at once, the rest from a job in steps
  local first = math.min(#indexes, Browser.STAGE)
  put(1, first)
  draw(first)
  if fillJob then
    fillJob:Cancel()
    fillJob = nil
  end
  if first < #indexes then
    fillJob = B.Jobs:Run(mod, "browser-fill", function(yield)
      local at = first
      while at < #indexes and gen == fillGen do
        local to = math.min(#indexes, at + Browser.STAGE)
        put(at + 1, to)
        at = to
        draw(at)
        yield()
      end
    end, {
      onDone = function()
        fillJob = nil
      end,
    })
  end
end

-- Whether any row of the list has a zone (ADR 0038: the zone groups).
function Browser.HasZones(list)
  return list and list.zones and next(list.zones) ~= nil or false
end

-- What a list type is grouped by, as the profile remembers it (`listGroups[type]`): nil =
-- nothing chosen (the list's default), false or "none" = no groups, "zone", or the id of one of
-- the list's dimensions.
local function savedGroups(entry)
  local p = db()
  if type(p.listGroups) ~= "table" then
    return nil
  end
  local saved = p.listGroups[entry.type]
  if saved == false then
    return "none" -- the toggle of ADR 0038, switched off
  end
  return type(saved) == "string" and saved or nil
end

-- The zone groups toggle of a list type (ADR 0038: on by default).
function Browser.GroupsOn(entry)
  return savedGroups(entry) ~= "none"
end

-- `key`: a group key ("zone", "none", a dimension's id); true and false as the toggle of ADR
-- 0038 (true = the list's default again).
function Browser.SetGroups(entry, key)
  local p = db()
  if type(p.listGroups) ~= "table" then
    p.listGroups = {}
  end
  local def = listDef(entry.type)
  local default = def and def.groupBy or "zone"
  if key == true or key == default then
    p.listGroups[entry.type] = nil
  elseif key == false or key == "none" then
    p.listGroups[entry.type] = false
  else
    p.listGroups[entry.type] = key
  end
end

-- The choices of the Groups pill and its default key, or nil when the list has nothing to
-- group by now. A list groups by zone under Nearest (ADR 0038); a list that names its groups
-- (`groupBy`, core-contracts 7c: the chains) by each of its dimensions marked `group` and by
-- zone, in every order.
function Browser.GroupChoices(entry)
  local list = entry.list
  local def = listDef(entry.type)
  local own = def and def.groupBy
  local out = {}
  if own then
    for _, dim in ipairs(list.dims or {}) do
      if dim.group then
        -- the list's own grouping first, the others as the dimensions stand
        table.insert(out, dim.id == own and 1 or #out + 1, { key = dim.id, label = L[dim.title] })
      end
    end
  end
  if Browser.HasZones(list) and (own or entry.sort == "near") then
    out[#out + 1] = { key = "zone", label = own and L["Zone"] or L["By zone"] }
  end
  if #out == 0 then
    return nil
  end
  out[#out + 1] = { key = "none", label = L["None"] }
  return out, own or "zone"
end

-- What the entry's list is grouped by now: "zone", or a dimension's id with its index and the
-- dimension; nil for no groups.
function Browser.GroupOf(entry)
  local choices, default = Browser.GroupChoices(entry)
  if not choices then
    return nil
  end
  local key = savedGroups(entry) or default
  local offered = false
  for _, c in ipairs(choices) do
    offered = offered or c.key == key
  end
  if not offered then
    key = default -- a remembered dimension that is gone
  end
  if key == "none" then
    return nil
  elseif key == "zone" then
    return Browser.HasZones(entry.list) and "zone" or nil
  end
  for k, dim in ipairs(entry.list.dims or {}) do
    if dim.id == key and dim.group then
      return key, k, dim
    end
  end
  return nil
end

-- The fields of a list's filter text (ADR 0045), the record being the row's index: `level`
-- (number), `zone` (the zone's name) and each dimension by its title in lower case without
-- spaces (its key and the key's label). Built once per list.
function Browser.ListFields(list)
  if list.queryFields then
    return list.queryFields
  end
  local d = data()
  local zoneNames = {}
  local fields = {
    level = {
      kind = "number",
      get = function(i)
        local v = list.levels and list.levels[i]
        if type(v) == "table" then
          v = v[1]
        end
        return tonumber(v)
      end,
    },
    zone = {
      get = function(i)
        local z = list.zones and list.zones[i]
        if not z then
          return nil
        end
        if zoneNames[z] == nil then
          local r = d and d:Get("zone", z) or nil
          zoneNames[z] = r and r.name or false
        end
        return zoneNames[z] or nil
      end,
    },
  }
  fields.lvl = fields.level
  -- a dimension's words of a row (its keys and their labels), made once per row and dimension:
  -- the filter asks for them on every key
  local words = {}
  local function dimWords(k, dim, i)
    local memo = words[k]
    if not memo then
      memo = {}
      words[k] = memo
    end
    local out = memo[i]
    if out == nil then
      local key = list.values[k] and list.values[k][i]
      if key == nil then
        out = false
      else
        out = {}
        for _, v in ipairs(type(key) == "table" and key or { key }) do
          out[#out + 1] = tostring(v)
          local label = dim.labels and dim.labels(v) or L[v]
          if label then
            out[#out + 1] = tostring(label)
          end
        end
      end
      memo[i] = out
    end
    return out or nil
  end
  -- `type:vendor`: any dimension's key or label
  local function anyDim(i)
    local out = {}
    for k, dim in ipairs(list.dims or {}) do
      for _, w in ipairs(dimWords(k, dim, i) or {}) do
        out[#out + 1] = w
      end
    end
    return out
  end
  fields.type = { get = anyDim }
  fields.is = fields.type
  for k, dim in ipairs(list.dims or {}) do
    local name = string.lower(string.gsub(tostring(dim.title or dim.id or ""), "[^%w]", ""))
    if name ~= "" and not fields[name] then
      fields[name] = {
        get = function(i)
          return dimWords(k, dim, i)
        end,
      }
    end
  end
  list.queryFields = fields
  return fields
end

-- The fields' names for the filter box's tooltip.
function Browser.ListFieldNames(list)
  local names = {}
  for name in pairs(Browser.ListFields(list)) do
    if name ~= "lvl" and name ~= "is" then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  return table.concat(names, ", ")
end

-- The names of the zones the rows `indexes` of `list` belong to: { [map] = name }.
function Browser.ZoneNames(list, indexes)
  local d = data()
  local names = {}
  for _, i in ipairs(indexes) do
    local z = list.zones[i]
    if z and names[z] == nil then
      local r = d and d:Get("zone", z) or nil
      names[z] = r and r.name or false
    end
  end
  return names
end

-- The rows of a Nearest list under their zone (ADR 0038): a foldable group row per zone in the
-- order the zones first appear (nearest first), its name and count, the rows without a zone
-- under "Elsewhere" last. `rows[j]` is the row of `indexes[j]`. Pure.
function Browser.GroupRows(rows, list, indexes, names, byName)
  local out, groups = {}, {}
  local elsewhere
  for j, row in ipairs(rows) do
    local z = list.zones[indexes[j]]
    local g
    if z and names[z] then
      g = groups[z]
      if not g then
        g = {
          id = "zone:" .. tostring(z),
          group = true,
          zone = z,
          children = {},
          icon = B.UI.IconTexture("zone"),
        }
        groups[z] = g
        out[#out + 1] = g
      end
    else
      elsewhere = elsewhere
        or { id = "zone:elsewhere", group = true, children = {}, icon = B.UI.IconTexture("zone") }
      g = elsewhere
    end
    g.children[#g.children + 1] = row
  end
  if byName then -- no order of the zones comes with the rows: by their names
    table.sort(out, function(a, b)
      return tostring(names[a.zone]) < tostring(names[b.zone])
    end)
  end
  if elsewhere then
    out[#out + 1] = elsewhere
  end
  for _, g in ipairs(out) do
    local name = g.zone and names[g.zone] or L["Elsewhere"]
    g.text = tostring(name) .. "  " .. S.H.muted .. #g.children .. "|r"
  end
  return out
end

-- The rows of a list under the values of one of its dimensions (core-contracts 7c: a chain's
-- progress, its level band): a foldable group row per value with its words and count, in the
-- dimension's own order (`sortKey`), else as the values first appear; "Other" last. A row with
-- several values stands under its first. `rows[j]` is the row of `indexes[j]`. Pure.
function Browser.GroupRowsBy(rows, list, indexes, k, dim)
  local out, groups = {}, {}
  local values = list.values[k] or {}
  for j, row in ipairs(rows) do
    local key = values[indexes[j]]
    if type(key) == "table" then
      key = key[1]
    end
    key = key or "Other"
    local g = groups[key]
    if not g then
      g = { id = "group:" .. tostring(dim.id) .. ":" .. key, group = true, key = key, children = {} }
      g.first = #out + 1
      groups[key] = g
      out[#out + 1] = g
    end
    g.children[#g.children + 1] = row
  end
  table.sort(out, function(a, b)
    local oa, ob = OTHER_KEYS[a.key] or false, OTHER_KEYS[b.key] or false
    if oa ~= ob then
      return ob
    end
    if dim.sortKey then
      local ka, kb = dim.sortKey(a.key), dim.sortKey(b.key)
      if ka ~= kb then
        return ka < kb
      end
    end
    return a.first < b.first
  end)
  for _, g in ipairs(out) do
    local label = dim.labels and dim.labels(g.key) or L[g.key]
    g.text = tostring(label) .. "  " .. S.H.muted .. #g.children .. "|r"
    g.first = nil
  end
  return out
end

-- ---------------------------------------------------------------------------------------------
-- The scope (ADR 0056, PA1.2): where the list and the search look: the player's zone, the
-- continent, everywhere. A chip inside the search box. For a list it is the "Where" dimension
-- (C9), taken out of the filter bar; a search typed on a list keeps the list's scope.
-- ---------------------------------------------------------------------------------------------

-- The player's map, its continent and its zone record.
local function playerPlace(d)
  local map = B.Coords.PlayerMap()
  if not map then
    map = select(4, B.Coords.Player())
  end
  local zone = d and map and d:Get("zone", map) or nil
  return map, zone and zone.continent or nil, zone
end

-- The chip's words: "in Elwynn Forest", "in Eastern Kingdoms", "Everywhere".
function Browser.ScopeWords(near)
  local _, continent, zone = playerPlace(data())
  if near == "here" then
    return zone and zone.name and string.format(L["in %s"], zone.name) or L["Here"]
  elseif near == "continent" then
    local name = continent ~= nil and B.Coords.ContinentName(continent) or nil
    return name and string.format(L["in %s"], name) or L["Continent"]
  end
  return L["Everywhere"]
end

-- Shows the chip for a dimension (a list's Where, the search's own), nil: no chip.
function Browser.SetScope(dim)
  if not scope then
    return
  end
  if scope.dim ~= dim then
    local m = B.UI.FilterMenuFrame()
    if m and m:IsShown() and m.anchor == scope then
      m:Hide() -- the menu belonged to the chip's old choices
    end
  end
  scope.dim = dim
  local inset = 22 -- the box's clearing x
  if dim then
    local on = dim.active ~= nil
    scope.label:SetText(dim.words or Browser.ScopeWords(dim.active))
    S.ink(scope.label, on and S.C.text or S.C.dim)
    S.tint(scope.face, on and S.C.accent or S.C.press, on and 0.25 or nil)
    scope.clear:SetShown(on)
    local width = math.floor((scope.label:GetStringWidth() or 0) + 0.5) + 16 + (on and 14 or 0)
    scope:SetWidth(width)
    scope.face:Show() -- lays the pill out for its new width
    scope:Show()
    inset = inset + width + 4
  else
    scope:Hide()
  end
  search:SetTextInsets(8, inset, 0, 0)
  -- beside a chip the box is short: the hint is one word
  search.hint:SetText(dim and L["Search"] or search.longHint)
  search.hint:ClearAllPoints()
  search.hint:SetPoint("LEFT", 8, 0)
  search.hint:SetPoint("RIGHT", -inset, 0)
end

-- The chip as the tests and the hub read it: its words and its choice, nil while it is hidden.
function Browser.Scope()
  if not (scope and scope:IsShown() and scope.dim) then
    return nil
  end
  return scope.label:GetText(), scope.dim.active
end

-- The search home: no list on open, results from
-- the second character through Core's providers, a type word first or last narrows ("npc wel"), the
-- type chips under the box set the type too; with an empty box the home shows "Here", the views,
-- the bookmarks and the recent pages.
-- The search that runs or ran: { query, handle, results, done }. A render of the same words draws
-- what it holds: an event must not start a search over ("I never get
-- any result", a search takes half a second and any event a little faster kept it from ending).
local lastSearch
local SEARCH_MIN = 2
local SEARCH_LIMIT = 100
local HOME_RECENT = 8
local homeType -- the list the search keeps to (its key), nil for All (per session)
local searchCounts -- what the last finished search found: { [list key] = n }, and `full`
local renderHome

local function typeTag(ref)
  local entityType = B.Entity.Parse(ref)
  return entityType and ("  " .. S.H.muted .. L[entityType] .. "|r") or ""
end

function Browser.HomeType()
  return homeType
end

-- The rows of the home with an empty box: the registered views by group (My quests, All quests,
-- ...), the bookmarks, the recent pages. The player's zone is the Here column since C4.
-- The views the Browser offers: all but those a list of its own covers (`coveredBy`, a list type:
-- Quests' All quests is the Quests list with its Status and Type filters, ).
local function shownViews()
  local out = {}
  for _, def in ipairs(B:GetViews()) do
    if not (def.coveredBy and listDef(def.coveredBy)) then
      out[#out + 1] = def
    end
  end
  return out
end

function Browser.IdleRows()
  local rows = {}
  local groups, order = {}, {}
  for _, def in ipairs(shownViews()) do
    local group = tostring(def.group)
    local list = groups[group]
    if not list then
      list = {}
      groups[group] = list
      order[#order + 1] = group
    end
    local text = tostring(def.title)
    if def.summary then
      local ok, words = pcall(def.summary)
      if ok and words then
        text = text .. "  " .. S.H.muted .. tostring(words) .. "|r"
      end
    end
    list[#list + 1] = {
      id = "home:view:" .. def.id,
      text = text,
      view = def.id,
      onClick = function()
        Browser.ShowView(def.id)
      end,
    }
  end
  for _, group in ipairs(order) do
    rows[#rows + 1] =
      { id = "home:group:" .. group, kind = "section", text = group, children = groups[group] }
  end
  local marks = {}
  for _, ref in ipairs(bookmarks()) do
    local e = B:Entity(ref)
    marks[#marks + 1] = { id = "home:bm:" .. ref, ref = ref, text = (e:Name() or ref) .. typeTag(ref) }
  end
  if #marks > 0 then
    rows[#rows + 1] = { id = "home:bookmarks", kind = "section", text = L["Bookmarks"], children = marks }
  end
  local recent, seen = {}, {}
  for i = #history, 1, -1 do
    local entry = history[i]
    if entry.kind == "page" and not seen[entry.ref] then
      seen[entry.ref] = true
      local e = B:Entity(entry.ref)
      recent[#recent + 1] = {
        id = "home:recent:" .. entry.ref,
        ref = entry.ref,
        text = (e:Name() or entry.ref) .. typeTag(entry.ref),
      }
      if #recent >= HOME_RECENT then
        break
      end
    end
  end
  if #recent > 0 then
    rows[#rows + 1] = { id = "home:recent", kind = "section", text = L["Recent"], children = recent }
  end
  if #rows == 0 then
    rows[1] = {
      kind = "para",
      text = S.H.muted
        .. L["Start typing to search: a name, or a type first (npc wel, quest hogger)."]
        .. "|r",
    }
  end
  return rows
end

-- The list a search hit belongs to: a function ref -> list definition, nil where no list shows
-- that type. Two lists of one type (People and Monsters) part by their keep rules; a record that
-- cannot be read goes to the list named like its type.
function Browser.HitList()
  local byEntity, d = {}, data()
  for _, def in ipairs(Browser.Lists()) do
    local typ = def.entity or def.type
    byEntity[typ] = byEntity[typ] or {}
    table.insert(byEntity[typ], def.type == typ and 1 or #byEntity[typ] + 1, def)
  end
  return function(ref)
    local typ, id = B.Entity.Parse(ref)
    local defs = typ and byEntity[typ]
    if not defs then
      return nil
    end
    local rec = #defs > 1 and d and d:Get(typ, id) or nil
    if rec then
      for _, def in ipairs(defs) do
        if def.keep and def.keep(rec) then
          return def
        end
      end
    end
    return defs[1]
  end
end

-- The rows of the search home for Core's ranked results: the results whose name starts with the
-- search text first (in rank order), a horizontal rule, then the rest.
-- No rule when one of the two groups is empty. Hits of several lists stand in a section per list
-- (ADR 0056), the list of the best hit first, each with its names that start with the text first.
function Browser.HomeRows(results, query)
  local needle = string.lower(query or "")
  local starts, rest, offers = {}, {}, {}
  local listOf = Browser.HitList()
  local place = {} -- row -> its section's key
  local titles, seen, kinds = {}, {}, 0
  for _, r in ipairs(results) do
    if r.ref then
      local label = r.label or r.ref
      -- one line per result (ADR 0018 B; ~~two lines, ~~ the detail pane shows the
      -- rest on a hover): the icon, the name, the type and what the entity is (level, zone) in
      -- grey, the worth on the right, cut by the row
      local entityType = B.Entity.Parse(r.ref)
      local e = B:Entity(r.ref)
      local what = e:Summary()
      local meta = entityType and L[entityType] or ""
      if what and what ~= "" then
        meta = meta ~= "" and (meta .. " - " .. what) or what
      end
      local row = {
        id = "s:" .. r.ref,
        ref = r.ref,
        text = label .. (meta ~= "" and ("  " .. S.H.muted .. meta .. "|r") or ""),
        -- as a tile (ADR 0056): the name, and under it the type and what the entity is
        title = label,
        meta = meta ~= "" and meta or nil,
        icon = e:Icon() or (entityType and B.UI.IconTexture(TYPE_GLYPH[entityType] or "other")),
      }
      local def = listOf(r.ref)
      local key = def and def.type or entityType or "other"
      place[row] = key
      -- a type without a list says its word (area, flightpath), as a head with a capital
      local word = def and L[def.label] or tostring(entityType and L[entityType] or L["Other"])
      titles[key] = string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2)
      if not seen[key] then
        seen[key] = true
        kinds = kinds + 1
      end
      local name = string.lower(label)
      if needle ~= "" and string.sub(name, 1, #needle) == needle then
        starts[#starts + 1] = row
      else
        rest[#rest + 1] = row
      end
    elseif r.action then
      -- a provider's offer, no thing of the world ("Load quest texts to search them"): a plain row
      -- after the results (it stopped every search while that pack was
      -- not loaded)
      offers[#offers + 1] = {
        id = "s:offer:" .. tostring(r.label),
        text = S.H.accent .. tostring(r.label) .. "|r",
        onClick = function()
          r.action()
          Browser.Schedule()
        end,
      }
    end
  end
  local rows = {}
  if kinds > 1 then
    local sections = {}
    for _, part in ipairs({ starts, rest }) do
      for _, row in ipairs(part) do
        local key = place[row]
        if not sections[key] then
          sections[key] = { id = "s:list:" .. key, kind = "section", children = {} }
          rows[#rows + 1] = sections[key]
        end
        table.insert(sections[key].children, row)
      end
    end
    for key, section in pairs(sections) do
      section.text = tostring(titles[key]) .. "  " .. S.H.muted .. #section.children .. "|r"
    end
  else
    rows = starts
    if #starts > 0 and #rest > 0 then
      rows[#rows + 1] = { id = "s:rule", kind = "rule", text = "" }
    end
    for _, row in ipairs(rest) do
      rows[#rows + 1] = row
    end
  end
  for _, row in ipairs(offers) do
    rows[#rows + 1] = row
  end
  return rows
end

-- A list in the navigation (ADR 0018; before, a type chip; "the search
-- is always global, the types filter it"): with text in the box it filters the world search, from
-- any entry; with an empty box it opens that type's list, nil the search home.
local function onTypeChip(key)
  local text = search and search:GetText() or ""
  if text ~= "" and key ~= nil and key == homeType then
    key = nil -- the filtering list once more: the search over every type again (ADR 0018)
  end
  homeType = key
  if text == "" then
    if key then
      Browser.List(key) -- nothing typed: the type's list with its facets
    else
      Browser.Home()
    end
    return
  end
  Browser.Search(text)
end

-- The search's scope as the chip's dimension: the search entry's own choice (`entry.scope`).
local function searchScope(entry)
  local choices = { { key = "here", label = L["Here"] }, { key = "continent", label = L["Continent"] } }
  local within = entry.within -- a search typed inside a zone looks there (PA4)
  if within then
    table.insert(choices, 1, { key = "within", label = within.name })
  end
  return {
    id = "where",
    title = L["Where"],
    choices = choices,
    active = entry.scope,
    words = within and entry.scope == "within" and string.format(L["in %s"], within.name) or nil,
    all = { label = L["All"] },
    tip = L["Where the search looks: in your zone, on your continent, or everywhere."],
    onSelect = function(key)
      entry.scope = key
      if shownList == entry then
        renderHome(entry.text or "")
      end
    end,
  }
end

-- Stops and forgets the search: new words, new data.
function Browser.ForgetSearch()
  if lastSearch and lastSearch.handle then
    lastSearch.handle:Cancel()
  end
  lastSearch = nil
end

-- The list tile of the search entry from what the search has found so far.
local function drawSearch(entry)
  local run = lastSearch
  local results, done = run.results, run.done
  local query, types = B.ParseSearch(entry.text or "")
  local typed = types ~= nil
  -- the list the search keeps to: the data type of its records, narrowed by its keep rule (owner,
  -- retail 31.10.2026: "wolf" on Mobs found nothing, no provider knows "mob")
  local def = homeType and listDef(homeType) or nil
  local want = def and def.entity or homeType
  if not types and homeType then
    types = { [want] = true } -- the chip is the type word when the text has none
  end
  local keep = types and want and types[want] and def and def.keep or nil
  local kept, d = {}, data()
  local scoped = entry.scope
  local map, continent
  if scoped == "within" then
    map = entry.within.map
  elseif scoped then
    map, continent = playerPlace(d)
  end
  local listOf = Browser.HitList()
  local counts, perType = {}, {}
  -- the scope: what has a place outside it is left out and counted; what has no place at all
  -- (an item, a recipe) stays, the scope says nothing about it
  local elsewhere = 0
  for _, r in ipairs(results) do
    local typ, id
    if r.ref then
      typ, id = B.Entity.Parse(r.ref)
    end
    if typ then
      perType[typ] = (perType[typ] or 0) + 1
      local rec = (scoped or keep) and d and d:Get(typ, id) or nil
      local inside = true
      if scoped and rec then
        local where, placed = Browser.NearOf(typ, id, rec, d, map, continent)
        inside = not placed or where == "here" or (where == "continent" and scoped == "continent")
      end
      if inside then
        local list = listOf(r.ref)
        if list then
          counts[list.type] = (counts[list.type] or 0) + 1
        end
      end
      if (not types or types[typ]) and (not keep or (rec and keep(rec))) then
        if inside then
          kept[#kept + 1] = r
        else
          elsewhere = elsewhere + 1
        end
      end
    elseif not types then
      kept[#kept + 1] = r -- a provider's offer: no type to keep to
    end
  end
  results = kept
  if done then
    searchCounts = { counts = counts, full = perType }
    Browser.RenderNav()
  end
  local rows = Browser.HomeRows(results, query)
  if #rows == 0 and elsewhere == 0 then
    rows[1] = { text = S.H.muted .. (done and L["No matches."] or L["Searching ..."]) .. "|r", kind = "para" }
  end
  if elsewhere > 0 then
    -- one click from the rest of the world
    rows[#rows + 1] = {
      id = "s:elsewhere",
      text = S.H.muted .. string.format(L["%d more elsewhere. Click to look everywhere."], elsewhere) .. "|r",
      onClick = function()
        entry.scope = nil
        if shownList == entry then
          renderHome(entry.text or "")
        end
      end,
    }
  end
  -- a search kept to a list and nothing there: the hits of the other lists are one click away
  local others = 0
  for _, n in pairs(counts) do
    others = others + n
  end
  if done and homeType and not typed and #results == 0 and others > 0 then
    rows[#rows + 1] = {
      id = "s:others",
      text = S.H.muted .. string.format(L["%d in the other lists. Click to look in all."], others) .. "|r",
      onClick = function()
        homeType = nil
        if shownList == entry then
          renderHome(entry.text or "")
          Browser.RenderNav()
        end
      end,
    }
  end
  tree:SetRows(rows)
  markSelected(Browser.ShownPage())
  summary:SetText(done and string.format(L["%d matches"], #results) or L["Searching ..."])
end

function renderHome(text)
  win:SetTitle(L["Search"])
  noHeader()
  tree:SetChips({}, nil, nil)
  local entry = shownList
  local query = B.ParseSearch(text or "")
  Browser.SetScope(#query >= SEARCH_MIN and entry and searchScope(entry) or nil)
  if #query < SEARCH_MIN then
    Browser.ForgetSearch()
    if searchCounts then
      searchCounts = nil
      Browser.RenderNav()
    end
    if query == "" then
      tree:SetRows(Browser.IdleRows())
    else
      tree:SetRows({
        {
          text = S.H.muted
            .. L["Start typing to search: a name, or a type first (npc wel, quest hogger)."]
            .. "|r",
          kind = "para",
        },
      })
    end
    summary:SetText("")
    return
  end
  if lastSearch and lastSearch.query == query then
    if lastSearch.results then
      drawSearch(entry) -- a render, a chip or a scope: what the search found, no new search
    end
    return
  end
  Browser.ForgetSearch()
  summary:SetText(L["Searching ..."])
  local run = { query = query }
  lastSearch = run
  local function shown()
    local now = shownList
    return lastSearch == run and now and now.kind == "home" and win and win:IsShown() and now or nil
  end
  -- every type is searched, whatever the chip says (Core only filters what the providers found):
  -- the category buttons say what the search found, also of the lists not shown
  run.handle = B:Search(query, {
    limit = SEARCH_LIMIT,
    onError = function()
      if shown() then
        tree:SetRows({})
        summary:SetText(L["The search failed. See /bastians log."])
      end
    end,
  }, function(results, done)
    if lastSearch == run then
      run.results, run.done = results, done
    end
    local now = shown()
    if now then
      drawSearch(now)
    end
  end)
end

local function renderBookmarks()
  win:SetTitle(L["Bookmarks"])
  noHeader()
  tree:SetChips({}, nil, nil)
  local rows = {}
  for _, ref in ipairs(bookmarks()) do
    local e = B:Entity(ref)
    rows[#rows + 1] =
      { id = "bm:" .. ref, ref = ref, text = (e:Name() or ref) .. "  " .. S.H.muted .. ref .. "|r" }
  end
  if #rows == 0 then
    rows[1] =
      { text = S.H.muted .. L["No bookmarks yet. Press + on a page to keep it."] .. "|r", kind = "para" }
  end
  tree:SetRows(rows)
  summary:SetText(string.format(L["%d bookmarks"], #bookmarks()))
end

-- More (ADR 0058): everything that names no rail entry, as tiles with one line each: the other
-- apps' views, the bookmarks, then the suite's own pages (the settings hub, Help, What's new,
-- About).
local MORE_PAGES = {
  { id = "suite", text = "Settings", line = "Every app, the looks, the keys.", icon = "settings" },
  { id = "help", text = "Help", line = "The story, the commands, the keys.", icon = "open" },
  { id = "news", text = "What's new", line = "The last releases.", icon = "ledger" },
  { id = "about", text = "About", line = "The sources and their licences.", icon = "other" },
}

function Browser.MoreRows()
  local rows = {}
  for _, section in ipairs(Browser.Sections()) do
    if section.id == "more" then
      for _, cat in ipairs(section.tabs) do
        local nav = cat.nav
        rows[#rows + 1] = {
          id = "more:" .. cat.id,
          text = cat.text,
          meta = cat.tip,
          icon = B.UI.IconTexture(cat.icon),
          onClick = function()
            Browser.SetListOpen(true)
            Browser.Navigate(nav)
          end,
        }
      end
    end
  end
  for _, page in ipairs(MORE_PAGES) do
    local id = page.id
    rows[#rows + 1] = {
      id = "more:page:" .. id,
      text = L[page.text],
      meta = L[page.line],
      icon = B.UI.IconTexture(page.icon),
      onClick = function()
        B.UI.Hub.Open(id)
      end,
    }
  end
  return rows
end

local function renderMore()
  win:SetTitle(L["More"])
  noHeader()
  tree:SetChips({}, nil, nil)
  tree:SetRows(Browser.MoreRows())
  summary:SetText(L["Everything else: the other apps' views, your bookmarks, the settings."])
end

function Browser.ShowMore()
  if not (mod and mod:IsEnabled()) then
    return false
  end
  show({ kind = "more" })
  Browser.SetListOpen(true)
  return true
end

-- ---------------------------------------------------------------------------------------------
-- Views (ADR 0012, core-contracts §7b): the Browser is the one window; apps' views render here
-- ---------------------------------------------------------------------------------------------

local controlBar -- the toolbar line of a view, in place of the action bar
local shownView -- id of the view whose onShow ran last
local viewJob -- the shown view's background job
local listening = {} -- bus messages the Browser re-renders on

local function leaveView()
  if viewJob then
    viewJob:Cancel()
    viewJob = nil
  end
  if shownView then
    local id = shownView
    shownView = nil
    B:ViewEvent(id, "hide")
  end
end
Browser.LeaveView = leaveView

-- The host a view renders into (core-contracts §7b).
local function viewHost(entry, def)
  local host = { args = entry.args, frame = win and win.frame, id = entry.id }
  function host.SetRows(_, rows)
    tree:SetRows(rows or {})
  end
  function host.SetSummary(_, text)
    summary:SetText(text or "")
  end
  function host.SetChips(_, chips, active, onChip, title)
    tree:SetChips(chips or {}, active, onChip, nil, title)
  end
  function host.SetControls(_, controls)
    controlBar:SetControls(controls)
  end
  function host.Job(_, name, fn, onDone)
    if viewJob then
      viewJob:Cancel()
    end
    viewJob = B.Jobs:Run(def.owner, name, fn, {
      onDone = function(job)
        if job.cancelled or shownList ~= entry then
          return
        end
        viewJob = nil
        if onDone then
          onDone()
        end
      end,
    })
    return viewJob
  end
  function host.Render()
    Browser.Render() -- a click in the view shows at once; events coalesce through invalidateOn
  end
  function host.IsShown()
    return win ~= nil and win:IsShown() and shownList == entry
  end
  return host
end

local function listen(def)
  for _, message in ipairs(def.invalidateOn or {}) do
    if not listening[message] then
      listening[message] = true
      mod:On(message, Browser.Schedule)
    end
  end
end

-- The rail entry whose stat tiles the list tile shows (ADR 0058, PH4): Here's on Here, a
-- section's on its first tab; none on the other tabs, a search, a thing stepped into.
function Browser.StatsRail()
  local entry = shownList or Browser.ListEntry()
  if not entry then
    return nil
  end
  if entry.kind == "here" then
    return "here"
  end
  if entry.kind ~= "list" and entry.kind ~= "view" then
    return nil
  end
  local nav = Browser.NavOf(entry)
  for _, section in ipairs(Browser.Sections()) do
    local first = section.tabs[1]
    if first and first.id == nav then
      return section.id
    end
  end
  return nil
end

local STAT_GAP = 6 -- between two stat tiles

-- Draws the rail entry's stat tiles (up to four) above the rows, or leaves the row a spacer.
function Browser.RenderStats()
  if not stats then
    return
  end
  local railID = Browser.StatsRail()
  local shown = {}
  if railID then
    for _, def in ipairs(B:GetStats(railID)) do
      if #shown >= 4 then
        break
      end
      listen(def)
      local got = B:BuildStat(def)
      if got then
        shown[#shown + 1] = { def = def, got = got }
      end
    end
  end
  local n = #shown
  local width = Browser.ListWidth() - 16
  local tileW = n > 0 and math.floor((width - STAT_GAP * (n - 1)) / n) or 0
  for i, it in ipairs(shown) do
    local t = stats.tiles[i]
    if not t then
      t = S.stat(stats, {})
      stats.tiles[i] = t
    end
    local got, def = it.got, it.def
    local ref, nav = got.ref, got.nav
    t:SetStat({
      label = tostring(def.title),
      value = got.value,
      note = got.note,
      unknown = L["unknown"],
      tip = got.tip,
      onClick = (ref or nav) and function()
        if ref then
          Browser.Open(ref)
        else
          Browser.SetListOpen(true)
          Browser.Navigate(nav)
        end
      end or nil,
    })
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", stats, "TOPLEFT", (i - 1) * (tileW + STAT_GAP), -2)
    t:SetWidth(math.max(60, tileW))
    t:Show()
  end
  for i = n + 1, #stats.tiles do
    stats.tiles[i]:Hide()
  end
  stats:SetHeight(n > 0 and (S.STAT_H + 8) or 4)
  stats.count, stats.rail = n, railID
end

-- The Browser's own stat tile (ADR 0058, PH4): the lands whose level band holds the player.
function Browser.RegisterStats(self)
  B:RegisterStat(self, {
    id = "browser.stat.lands",
    rail = "here",
    order = 30,
    title = L["Lands for you"],
    invalidateOn = { "BASTIANS_DATA_LOADED", "BASTIANS_QUESTS_CHANGED" },
    build = function()
      local d = data()
      if not (d and d.Each and d:Any("zone")) then
        return nil
      end
      local facts = B.Compat.GetPlayerFacts and B.Compat.GetPlayerFacts() or nil
      local level = facts and facts.level or UnitLevel("player")
      if not level then
        return nil
      end
      local n = 0
      for _, id in ipairs(d:Each("zone")) do
        local r = d:Get("zone", id)
        if r and r.levelLo and r.levelHi and r.levelLo <= level and r.levelHi >= level then
          n = n + 1
        end
      end
      return { value = n, note = L["at your level"], nav = { kind = "list", type = "zone" } }
    end,
  })
end

local function renderView(entry)
  local def = B:GetView(entry.id)
  noHeader()
  controlBar:Show()
  controlBar:SetControls({})
  header:SetHeight(22)
  tree:SetChips({}, nil, nil)
  summary:SetText("")
  if not def then
    leaveView()
    win:SetTitle(L["Not available"])
    tree:SetRows({
      { kind = "para", text = S.H.muted .. L["This view is not available: its addon is off."] .. "|r" },
    })
    return
  end
  win:SetTitle(tostring(def.group) .. ": " .. tostring(def.title))
  listen(def)
  local host = viewHost(entry, def)
  if shownView ~= entry.id then
    leaveView()
    shownView = entry.id
    B:ViewEvent(entry.id, "show", host)
  end
  B:RenderView(entry.id, host)
end

-- Opens a registered view (the `views` service); false when the Browser is off or there is no view.
function Browser.ShowView(id, args)
  if not (mod and mod:IsEnabled() and B:GetView(id)) then
    return false
  end
  local covered = B:GetView(id).coveredBy
  if covered and listDef(covered) then
    return Browser.List(covered) -- /bq all: the Quests list with its filters
  end
  local wasShown = win ~= nil and win:IsShown()
  Browser.Show({ kind = "view", id = id, args = args or {} })
  -- a view lives in the list pane: out with it (R25.36); sliding only in a window already open
  Browser.SetListOpen(true, wasShown)
  return true
end

-- The search box follows the list pane (ADR 0018): a search entry's own text, nothing on any
-- other entry, so a click on a result keeps the results and a list never inherits a filter.
local syncingBox = false
local function syncSearchBox(entry)
  if not search then
    return
  end
  local text = entry.kind == "home" and (entry.text or "") or ""
  if (search:GetText() or "") ~= text then
    syncingBox = true
    search:SetText(text)
    syncingBox = false
  end
  if tree and tree.query ~= "" then
    tree:SetQuery("")
  end
  if dossier and dossier.query and dossier.query ~= "" then
    dossier:SetQuery("")
  end
  if filterBox and filterBox.entry ~= entry then
    filterBox.entry = entry -- another entry: its own filter text (Back brings a list's back)
    local want = entry.filterText or ""
    if (filterBox:GetText() or "") ~= want then
      syncingFilter = true
      filterBox:SetText(want)
      syncingFilter = false
    end
    if want ~= "" and entry.kind ~= "list" then
      tree:SetQuery(want)
    end
    Browser.UpdateFilterCount()
  end
end

-- The list pane's filter ("a real time search filter to all listings
-- in the middle panel"): the rows the pane shows, narrowed to those whose words hold the text, as
-- you type; the count of the rows left in the box. The Here entry's dossier filters the same way.
-- A type list filters its built rows by name (all of them, not only the rows the cap shows);
-- a view, the search and the Here entry filter the rows they show.
Browser.FILTER_DELAY = 0.15 -- seconds after the last key before a big list filters
Browser.FILTER_LAZY_N = 1000 -- a list with that many rows waits for the typing to pause
local filterGen = 0

function Browser.FilterList(text)
  local entry = shownList or Browser.ListEntry()
  text = string.gsub(text or "", "^%s*(.-)%s*$", "%1") -- its case stays for OR/AND/NOT (ADR 0045)
  entry.filterText = text ~= "" and text or nil
  if entry.kind == "list" and entry.list and win and win:IsShown() then
    if entry.list.n >= Browser.FILTER_LAZY_N and text ~= "" then
      -- a big list: once the typing pauses, not on every key
      filterGen = filterGen + 1
      local gen = filterGen
      C_Timer.After(Browser.FILTER_DELAY, function()
        if gen == filterGen and shownList == entry and win and win:IsShown() then
          Browser.ShowList(entry)
          Browser.UpdateFilterCount()
        end
      end)
      return
    end
    filterGen = filterGen + 1 -- a pending lazy run is stale now
    Browser.ShowList(entry)
  elseif tree then
    tree:SetQuery(text)
  end
  if hereDossier then
    hereDossier:SetQuery(entry.kind == "here" and text or "")
  end
  Browser.UpdateFilterCount()
end

function Browser.UpdateFilterCount()
  if not (filterBox and tree) then
    return
  end
  -- the list's fields for the box's tooltip and its query look (ADR 0045)
  local entry = shownList
  local list = entry and entry.kind == "list" and entry.list or nil
  filterBox.queryOpts = list and { fields = Browser.ListFields(list) } or nil
  filterBox.queryFields = list and Browser.ListFieldNames(list) or nil
  if (tree.query or "") == "" then
    filterBox.count:SetText("") -- a type list says its count in the summary
    return
  end
  local n = 0
  for _, row in ipairs(tree.flat or {}) do
    if row.ref and not row.group then
      n = n + 1
    end
  end
  filterBox.count:SetText(tostring(n))
end

-- The Here entry in the list pane (C4, ADR 0018): the dossier of the player's zone (the `here`
-- sections), redrawn with every render (zone changes and quest events through Browser.Schedule).
function Browser.RenderHere()
  if not (win and win:IsShown() and hereDossier and hereDossier:IsShown()) then
    return
  end
  local ref = zoneRef()
  if ref then
    for _, def in ipairs(B:GetDetailSectionDefs(ref)) do
      listen(def) -- a section invalidated (a setting of its app, say) redraws the entry too
    end
    hereDossier:SetSubject(ref, nil, { source = "browser" })
  else
    hereDossier:Clear()
  end
end

-- ---------------------------------------------------------------------------------------------
-- Stepping inside (ADR 0056, PA4): the list tile takes a thing. Its own tile on top, then its
-- parts (the chapters of its page that hold things) as headings, one open at a time with its
-- things as tiles; the page tile shows what is picked there. An entry of the history:
-- { kind = "inside", ref, part (the open chapter's id), block (one section of it, by its chip) }.
-- ---------------------------------------------------------------------------------------------

local PART_H = 28 -- a part's heading: a target of 28 units (ADR 0056)

-- A section's or chapter's title as plain words: a section may write its count into its title
-- ("To do here  3", in grey); a heading and a chip carry the count themselves.
local function plainTitle(title)
  local words = string.gsub(tostring(title or ""), "|c%x%x%x%x%x%x%x%x", "")
  words = string.gsub(words, "|r", "")
  words = string.gsub(words, "%s+%d+%s*$", "")
  return (string.gsub(words, "%s+$", ""))
end

-- Whether a thing can be stepped into: its type has parts, and no app draws its page whole (a
-- quest is one sheet) unless that app says the thing has an inside all the same (a chain).
function Browser.HasInside(ref)
  local typ, id = B.Entity.Parse(ref)
  local sheet = typ and B:GetSheet(typ)
  if not typ or (sheet and not sheet.inside) then
    return false
  end
  return B:GetChapters(typ, id) ~= nil
end

-- The list tile's entry a thing was stepped into from: the newest entry before it that is
-- neither a page nor a thing's inside.
local function originOf(entry)
  local at
  for i = #history, 1, -1 do
    if history[i] == entry then
      at = i
      break
    end
  end
  for i = (at or (#history + 1)) - 1, 1, -1 do
    local e = history[i]
    if e.kind ~= "page" and e.kind ~= "inside" then
      return e
    end
  end
  return hereEntry
end

-- The rows of an inside entry and its parts { id, title, count, blocks = { { id, title, count } } }.
function Browser.InsideRows(entry)
  local DossierUtil = B.UI.DossierUtil
  local page = B.UI.DossierData(entry.ref, nil, { source = "browser" })
  local name = B:Entity(entry.ref):Name() or entry.ref
  local rows = { { id = "inside:self", ref = entry.ref, title = name, text = name, inside = false } }
  local parts = {}
  for _, chapter in ipairs(page.chapters or {}) do
    local open = entry.part == chapter.id
    local blocks, things, total = {}, {}, 0
    for _, block in ipairs(chapter.blocks) do
      local n = 0
      for _, row in ipairs(DossierUtil.things(block)) do
        if row.ref then
          n = n + 1
          if open and (entry.block == nil or entry.block == block.id) then
            row.entityName = true -- the thing's own name and line (one tile per type)
            row.id = "inside:" .. chapter.id .. ":" .. block.id .. ":" .. n
            things[#things + 1] = row
          end
        end
      end
      if n > 0 then
        blocks[#blocks + 1] = { id = block.id, title = block.title, count = n }
        total = total + n
      end
    end
    if total > 0 then
      local id = chapter.id
      local title = plainTitle(chapter.title or id)
      parts[#parts + 1] = { id = id, title = title, count = total, blocks = blocks, shown = #things }
      rows[#rows + 1] = {
        id = "inside:part:" .. tostring(id),
        kind = "section",
        height = PART_H,
        part = id,
        open = open,
        text = (open and "-  " or "+  ") .. title .. "  " .. S.H.muted .. total .. "|r",
        onClick = function()
          -- one part open at a time (P3): another opens and this one shuts; itself shuts
          entry.part = not open and id or nil
          entry.block = nil
          Browser.Render()
        end,
      }
      for _, row in ipairs(things) do
        rows[#rows + 1] = row
      end
    end
  end
  return rows, parts
end

-- ---------------------------------------------------------------------------------------------
-- A zone's open part on the map (ADR 0056, P4): until a tile is picked, the page tile shows the
-- zone in the chosen style with exactly that part's dots. The mouse on a dot names its thing, a
-- click picks it. A thing with no place in the zone has no dot.
-- ---------------------------------------------------------------------------------------------

local PART_MAP_TOP, PART_MAP_PAD = 30, 8
local partMap -- the frame over the page tile

-- The zone a part's dots stand on: a zone's own map, an area's zone; nil for every other thing.
function Browser.PartMapOf(ref)
  local typ, id = B.Entity.Parse(ref)
  if typ == "zone" then
    return tonumber(id)
  elseif typ == "area" then
    local place = B.UI.Scenery.FirstPlace(ref)
    return place and place.map or nil
  end
  return nil
end

-- The dots of a part's rows on `map`: { { x, y, row } }, each thing at least once before any has
-- many (a monster of a hundred spawns does not crowd out the rest), at most `limit`. Pure over
-- `placesOf(ref)`.
function Browser.PartDots(rows, map, placesOf, limit)
  local each, seen = {}, {}
  for _, row in ipairs(rows) do
    if row.ref and not seen[row.ref] then
      seen[row.ref] = true
      local here = {}
      for _, p in ipairs(placesOf(row.ref) or {}) do
        if p.map == map and p.x and p.y then
          here[#here + 1] = { x = p.x, y = p.y, row = row }
        end
      end
      if #here > 0 then
        each[#each + 1] = here
      end
    end
  end
  local out, round, more = {}, 1, true
  while more and #out < limit do
    more = false
    for _, here in ipairs(each) do
      if here[round] and #out < limit then
        out[#out + 1] = here[round]
        more = true
      end
    end
    round = round + 1
  end
  return out
end

local function partMapFrame()
  if partMap then
    return partMap
  end
  partMap = CreateFrame("Frame", nil, detailPane)
  partMap:SetPoint("TOPLEFT", detailPane, "TOPLEFT", 0, 0)
  partMap:SetPoint("BOTTOMRIGHT", detailPane, "BOTTOMRIGHT", 0, 0)
  partMap:SetFrameLevel((dossier.frame:GetFrameLevel() or 0) + 20)
  partMap:EnableMouse(true) -- the page under it takes no click
  partMap.ground = S.fill(partMap, S.C.panel, "BACKGROUND")
  partMap.title = S.heading(partMap, 15, 16, S.C.bright)
  partMap.title:SetPoint("TOPLEFT", partMap, "TOPLEFT", PART_MAP_PAD + 2, -8)
  partMap.picture = CreateFrame("Frame", nil, partMap)
  partMap.art = {}
  partMap.dots = {}
  partMap:Hide()
  mod.partMap = partMap
  return partMap
end

local function partDot(i)
  local dot = partMap.dots[i]
  if not dot then
    dot = CreateFrame("Button", nil, partMap.picture)
    dot:SetSize(12, 12)
    dot.tex = dot:CreateTexture(nil, "OVERLAY")
    dot.tex:SetTexture(S.DISC)
    dot.tex:SetPoint("CENTER")
    dot.tex:SetSize(8, 8)
    dot.tipNow = true
    dot:SetScript("OnEnter", S.TipEnter)
    dot:SetScript("OnLeave", S.TipLeave)
    dot:SetScript("OnClick", function(self)
      if self.row then
        tree.opts.onClick(self.row, "LeftButton", tree) -- as a click on its tile
      end
    end)
    partMap.dots[i] = dot
  end
  return dot
end

-- Draws the map for what the entry shows now, hides it when a tile is picked or nothing is open.
function Browser.RenderPartMap()
  local entry = Browser.ListEntry()
  local map = entry.kind == "inside"
    and entry.part
    and entry.things
    and Browser.ShownPage() == entry.ref
    and not previewRef
    and Browser.PartMapOf(entry.ref)
  if not map then
    if partMap then
      partMap:Hide()
    end
    return
  end
  local frame = partMapFrame()
  local width = (detailPane:GetWidth() or 0) - 2 * PART_MAP_PAD
  local height = (detailPane:GetHeight() or 0) - PART_MAP_TOP - PART_MAP_PAD
  local Scenery = B.UI.Scenery
  local box = Scenery.MapBox(map)
  local aspect = box and (box.west - box.east) / (box.north - box.south) or 1.5
  local w, h = width, width / aspect
  if h > height then
    w, h = height * aspect, height
  end
  if w < 1 or h < 1 then
    frame:Hide()
    return
  end
  S.tint(frame.ground, S.C.panel)
  S.ink(frame.title, S.C.bright)
  frame.title:SetText(string.format("%s: %s", B:Entity(entry.ref):Name() or "", entry.partTitle or ""))
  frame.picture:ClearAllPoints()
  frame.picture:SetPoint("TOPLEFT", frame, "TOPLEFT", PART_MAP_PAD, -PART_MAP_TOP)
  frame.picture:SetSize(w, h)
  local drawn = Scenery.DrawPicture(frame.picture, frame.art, map, 0, 0, 1, 1, w, h)
  if not drawn then
    frame:Hide() -- no style and no painting: the zone's sheet stays
    return
  end
  local dots = Browser.PartDots(entry.things, map, function(ref)
    return B:Entity(ref):Locations()
  end, Scenery.MAP_DOTS)
  for i, spot in ipairs(dots) do
    local dot = partDot(i)
    dot.row = spot.row
    dot.tip = spot.row.title or B:Entity(spot.row.ref):Name() or spot.row.text
    S.tint(dot.tex, S.C.waypointLoud)
    dot:ClearAllPoints()
    dot:SetPoint("CENTER", frame.picture, "TOPLEFT", spot.x * w, -spot.y * h)
    dot:Show()
  end
  for i = #dots + 1, #frame.dots do
    frame.dots[i]:Hide()
    frame.dots[i].row = nil
  end
  frame:Show()
  Scenery.MarkPlayer(frame.picture, map, w, h)
end

local function renderInside(entry)
  local name = B:Entity(entry.ref):Name() or entry.ref
  win:SetTitle(name)
  noHeader()
  for _, def in ipairs(B:GetDetailSectionDefs(entry.ref)) do
    listen(def) -- a section invalidated (a quest handed in) redraws the entry
  end
  local rows, parts = Browser.InsideRows(entry)
  local open
  for _, part in ipairs(parts) do
    if part.id == entry.part then
      open = part
    end
  end
  if entry.part ~= nil and not open then
    entry.part, entry.block = nil, nil -- the part is gone (its last thing done)
  end
  -- what the map of the open part shows (Browser.RenderPartMap)
  entry.things, entry.partTitle = nil, open and open.title or nil
  if open then
    entry.things = {}
    for _, row in ipairs(rows) do
      if row.ref and row.id ~= "inside:self" then
        entry.things[#entry.things + 1] = row
      end
    end
  end
  -- the open part's sections as chips, where it has several (a zone's quests: To do, Hand in ...):
  -- one at a time, a second click on it or All shows the whole part again
  local dims = {}
  if open and #open.blocks > 1 then
    local choices = {}
    for _, block in ipairs(open.blocks) do
      choices[#choices + 1] = { key = block.id, label = plainTitle(block.title), count = block.count }
    end
    dims[1] = {
      id = "part",
      title = open.title,
      chips = true,
      choices = choices,
      active = entry.block and { [entry.block] = true } or nil,
      all = { label = L["All"], count = open.count },
      onSelect = function(key)
        entry.block = key ~= entry.block and key or nil
        Browser.Render()
      end,
    }
  end
  tree:SetFilters(dims)
  tree:SetRows(rows)
  summary:SetText(
    (open and open.shown < open.count) and string.format(L["%d of %d shown"], open.shown, open.count) or ""
  )
  markSelected(Browser.ShownPage())
end

-- Steps inside a thing: its page in the page tile, the thing with its parts in the list tile,
-- `part` open (nil: none). Stepping into the thing already there opens the part.
function Browser.StepInside(ref, part)
  if not (mod and mod:IsEnabled()) or not B.Entity.Parse(ref) then
    return false
  end
  local entry = current and current.kind == "inside" and current or Browser.ListEntry()
  if entry.kind == "inside" and entry.ref == ref and win and win:IsShown() then
    entry.part, entry.block = part, nil
    Browser.SetListOpen(true)
    Browser.Render()
    return true
  end
  if Browser.ShownPage() ~= ref then
    show({ kind = "page", ref = ref }) -- the thing itself on the right, until a tile is picked
  end
  show({ kind = "inside", ref = ref, part = part })
  return true
end

local function renderHereEntry()
  local ref = zoneRef()
  local name = ref and B:Entity(ref):Name()
  win:SetTitle(name and string.format(L["Here: %s"], name) or L["Here"])
  noHeader()
  summary:SetText("")
  Browser.RenderHere()
end

function Browser.Render()
  if not (win and win:IsShown()) then
    return
  end
  setNav()
  local entry = Browser.ListEntry()
  if entry ~= shownList then
    shownList = entry
    syncSearchBox(entry)
  end
  if entry.kind ~= "view" then
    leaveView()
    controlBar:Hide()
  end
  showHere(entry.kind == "here")
  if entry.kind ~= "list" and entry.kind ~= "home" then
    Browser.SetScope(nil) -- a view, Here and the bookmarks look where they look
  end
  if entry.kind == "view" then
    renderView(entry)
  elseif entry.kind == "home" then
    renderHome(entry.text or "")
  elseif entry.kind == "list" then
    local def = listDef(entry.type)
    local cached = Browser.listCache[entry.type]
    local stale = def and cached and cached.gen ~= facetGen(def) -- a quest's status moved
    if entry.list and not stale then
      win:SetTitle(L[def and def.label or entry.type])
      noHeader()
      Browser.ShowList(entry)
    else
      renderList(entry.type)
    end
  elseif entry.kind == "here" then
    renderHereEntry()
  elseif entry.kind == "inside" then
    renderInside(entry)
  elseif entry.kind == "more" then
    renderMore()
  else
    renderBookmarks()
  end
  Browser.RenderStats()
  renderDetail()
  Browser.RenderNav()
  Browser.RenderCrumbs()
  Browser.Layout() -- the chips beside the search come and go with what the list tile shows
  Browser.RenderPartMap()
end

function Browser.Schedule()
  if mod and win and win:IsShown() then
    mod:Coalesce("rerender", RENDER_DELAY, Browser.Render)
  end
end

-- ---------------------------------------------------------------------------------------------
-- The hover preview (ADR 0018 C): a row resting under the mouse for the tip delay shows in the
-- detail pane, marked as a preview; leaving the row returns to the kept page; a click keeps it.
-- ---------------------------------------------------------------------------------------------

local hovered -- the ref under the mouse, while the delay runs
local lastWheel = -math.huge -- when the list was last scrolled with the mouse wheel
Browser.WHEEL_QUIET = 0.6 -- seconds after a scroll in which passing rows start no preview
Browser.LEAVE_DELAY = 0.15 -- seconds after leaving a row before the kept page comes back

function Browser.Preview(ref)
  if previewRef == ref then
    return
  end
  previewRef = ref
  if win and win:IsShown() and dossier then
    renderDetail()
    Browser.RenderPartMap()
  end
end

function Browser.Previewing()
  return previewRef
end

-- The rows' hover hook (the list tree and the Here dossier): entering starts the delay, leaving
-- ends a preview. (R25.32: "scrolling a quest's text jumps to another
-- quest"): rows passing under the cursor while the list scrolls start no preview, and a preview
-- the mouse carries into the detail pane (to read or scroll it) stays there as the page.
-- Whether a resting row may preview now: the setting `preview` (a
-- preview on every hover was "tricky to understand ... we stay on the one clicked", so Shift by
-- default; 01.11.2026: a setting, every hover or never as well).
local function previewAllowed()
  local mode = db().preview or "shift"
  if mode == "hover" then
    return true
  elseif mode == "off" then
    return false
  end
  return IsShiftKeyDown()
end
Browser.PreviewAllowed = previewAllowed

function Browser.OnRowHover(row, entering)
  if entering and row and row.ref then
    local ref = row.ref
    hovered = ref
    if ref == Browser.PageRef() or GetTime() - lastWheel < Browser.WHEEL_QUIET or not previewAllowed() then
      return
    end
    mod:Coalesce("preview", S.TipDelay() or 1, function()
      if hovered == ref and win and win:IsShown() and previewAllowed() then
        Browser.Preview(ref)
      end
    end)
  else
    hovered = nil
    local entry = shownList
    if entry and entry.heldStale then
      -- the order held while the mouse was over the list takes what came meanwhile
      mod:Coalesce("held", Browser.LEAVE_DELAY, function()
        if shownList == entry and entry.heldStale and not Browser.ListUnderMouse() then
          entry.heldStale = nil
          Browser.Schedule()
        end
      end)
    end
    if previewRef then
      mod:Coalesce("preview", Browser.LEAVE_DELAY, function()
        if hovered or not previewRef then
          return -- another row took over, or the preview went
        end
        if dossier and dossier.frame and dossier.frame:IsMouseOver() then
          local ref = previewRef
          previewRef = nil
          Browser.Open(ref) -- the mouse went into the page: the preview is the page now
        else
          Browser.Preview(nil)
        end
      end)
    end
  end
end

-- The list was scrolled with the wheel (a hook on the list's scroll frame).
function Browser.OnListWheel()
  lastWheel = GetTime()
end

-- ---------------------------------------------------------------------------------------------
-- The category buttons (ADR 0056): Here, the pinned views, the lists, the other views and the
-- bookmarks as one bar on top of the window that wraps into a second row. A button changes what
-- the list tile shows. The navigation pane of ADR 0018 A went with ADR 0056; the recent pages are
-- the history's, on Back.
-- ---------------------------------------------------------------------------------------------

-- Places boxes of `widths` left to right in rows of `maxWidth`: -> { { x, y }, ... } from the top
-- left (y down), and the height they take. Pure. A box wider than a row stands alone in its row.
function Browser.Flow(widths, maxWidth, gap, rowHeight)
  local out, x, y = {}, 0, 0
  for i, w in ipairs(widths) do
    if x > 0 and x + w > maxWidth then
      x, y = 0, y + rowHeight + gap
    end
    out[i] = { x = x, y = y }
    x = x + w + gap
  end
  return out, (#widths > 0) and (y + rowHeight) or 0
end

local CAT_ORDER = {
  zone = 1,
  quest = 2,
  chain = 3,
  npc = 4,
  mob = 5,
  item = 6,
  node = 7,
  object = 8,
  recipe = 9,
  dungeon = 10,
  character = 11,
  spot = 12,
  page = 13, -- Gold Stories
  note = 14, -- All Notes
}

-- Whether a list is known to have no rows: a data type whose loaded pack holds no record of
-- it, a registered list that says so (`empty`, core-contracts 7c). Unknown (the pack not loaded
-- yet, a list that does not say) is not empty.
function Browser.ListIsEmpty(def)
  if def.empty then
    local ok, none = pcall(def.empty)
    return ok and none == true
  end
  if def.ids or def.record then
    return false -- a registered list: only it knows
  end
  local d = data()
  return d ~= nil and d.Any ~= nil and d:Any(def.entity or def.type) == false
end

-- What the finished search found of a list, as the button says it: "12", "100+" where the
-- search's limit cut its type, nil without a search or without a hit (not 0: a list no provider
-- searches would say so too, and that is unknown).
function Browser.SearchCount(def)
  local n = searchCounts and shownList and shownList.kind == "home" and searchCounts.counts[def.type]
  if not n then
    return nil
  end
  local full = (searchCounts.full[def.entity or def.type] or 0) >= SEARCH_LIMIT
  return tostring(n) .. (full and "+" or "")
end

-- The buttons in order: { id, text, icon, nav, tip, count }. The ids are the navigation rows' of
-- old ("nav:here", "nav:list:<type>", "nav:view:<id>"), and "nav:bookmarks" while there are some.
function Browser.Categories()
  local out = {}
  local zone = zoneRef()
  local zoneName = zone and B:Entity(zone):Name()
  out[1] = {
    id = "nav:here",
    text = L["Here"],
    icon = "zone",
    nav = { kind = "here" },
    tip = zoneName and string.format(L["Here: %s"], zoneName) or nil,
    home = "here",
  }
  local later = {}
  for _, def in ipairs(shownViews()) do
    local words
    if def.summary then
      local ok, got = pcall(def.summary)
      words = ok and got and tostring(got) or nil
    end
    local cat = {
      id = "nav:view:" .. def.id,
      text = tostring(def.title),
      icon = def.icon or (def.pinned and "questActive" or "other"),
      nav = { kind = "view", id = def.id },
      tip = words, -- "11 in the log"
      home = Browser.RailOf(def), -- the rail entry the view named, else More (ADR 0058)
      order = def.order,
    }
    if def.pinned then
      out[#out + 1] = cat -- My quests, one click away
    else
      later[#later + 1] = cat
    end
  end
  -- the lists in the bar's order (ADR 0056: the world, who lives in it, what lies in it, yours;
  -- ~~by name~~ as the navigation's tree had them since 23.10.2026), others after them by name
  local lists = {}
  local shown = Browser.ListEntry()
  for i, def in ipairs(Browser.Lists()) do
    -- a list known to have no rows has no button (ADR 0054, B14), unless it is the one shown
    if not Browser.ListIsEmpty(def) or (shown and shown.kind == "list" and shown.type == def.type) then
      lists[#lists + 1] = { def = def, rank = CAT_ORDER[def.type] or (100 + i) }
    end
  end
  table.sort(lists, function(a, b)
    return a.rank < b.rank
  end)
  for _, entry in ipairs(lists) do
    local def = entry.def
    out[#out + 1] = {
      id = "nav:list:" .. def.type,
      text = L[def.label],
      icon = def.glyph or TYPE_GLYPH[def.type] or "other",
      nav = { kind = "list", type = def.type },
      count = Browser.SearchCount(def),
      home = Browser.RailOf(def),
      order = entry.rank,
    }
  end
  for _, cat in ipairs(later) do
    out[#out + 1] = cat
  end
  if #bookmarks() > 0 then
    out[#out + 1] = {
      id = "nav:bookmarks",
      text = L["Bookmarks"],
      icon = "bookmark",
      nav = { kind = "bookmarks" },
      home = "more",
    }
  end
  return out
end

-- ---------------------------------------------------------------------------------------------
-- The rail (ADR 0058): seven entries, always the same, in this order; the section's lists and
-- views as a row of tabs under it; everything that names no entry under More.
-- ---------------------------------------------------------------------------------------------

-- `hue`: the section's colour (, R4: "coloured symbols with text"
-- instead of green-on-green buttons): its pictogram on a square of it, the lit one underlined
Browser.RAIL = {
  { id = "here", label = "Here", icon = "zone", hue = "tileTeal" },
  { id = "quests", label = "Quests", icon = "quest", hue = "tileGold" },
  { id = "world", label = "World", icon = "route", hue = "tileGreen" },
  { id = "dungeons", label = "Dungeons", icon = "treasure", hue = "tileRed" },
  { id = "gold", label = "Gold", icon = "gold", hue = "tileBrown" },
  { id = "characters", label = "Characters", icon = "banker", hue = "tileBlue" },
  { id = "more", label = "More", icon = "other", hue = "tileGrey" },
}
-- where Data's lists live (a registered list or a view names its own with `rail`)
local LIST_RAIL = {
  zone = "world",
  npc = "world",
  mob = "world",
  node = "world",
  object = "world",
  quest = "quests",
  chain = "quests",
  dungeon = "dungeons",
  item = "gold",
  recipe = "gold",
  spot = "gold",
  page = "gold", -- Gold Stories
  character = "characters",
  note = "more", -- All Notes
}
-- the app an empty section would need (its module name): the entry is drawn dim and says so
local SECTION_NEEDS = { characters = "Alts" }
local RAIL_IDS = {}
for _, r in ipairs(Browser.RAIL) do
  RAIL_IDS[r.id] = true
end

-- The rail entry of a list or view definition: what it names, else the type's home, else More.
function Browser.RailOf(def)
  local home = def.rail
  if home == nil and def.type then
    home = LIST_RAIL[def.type]
  end
  if home and RAIL_IDS[home] and home ~= "here" then
    return home
  end
  return "more"
end

-- The order of the tabs inside a section: the lists in the bar's order, a pinned view right
-- after the first list (My quests after Quests), the other views by their order.
local function tabRank(cat)
  if cat.nav.kind == "list" then
    return (cat.order or 100) * 10
  elseif cat.nav.kind == "view" then
    local def = B:GetView(cat.nav.id)
    if def and def.first then
      return 5 -- the section's first tab (an app's overview)
    elseif def and def.pinned then
      return 25
    end
    return 1000 + (cat.order or 50)
  end
  return 5000
end

-- The seven sections with their tabs: { id, label, icon, tabs = { cat, ... }, needs }. A section
-- with no tab whose app is known is dim and says what it needs; Gold without Bastian's Gold
-- reads Items (its Items and Recipes stay).
function Browser.Sections()
  local out, byId = {}, {}
  for _, r in ipairs(Browser.RAIL) do
    local section = { id = r.id, label = L[r.label], icon = r.icon, hue = r.hue, tabs = {} }
    out[#out + 1] = section
    byId[r.id] = section
  end
  for _, cat in ipairs(Browser.Categories()) do
    local section = byId[cat.home] or byId.more
    section.tabs[#section.tabs + 1] = cat
  end
  for _, section in ipairs(out) do
    table.sort(section.tabs, function(a, b)
      local ra, rb = tabRank(a), tabRank(b)
      if ra ~= rb then
        return ra < rb
      end
      return tostring(a.text) < tostring(b.text)
    end)
    local needs = SECTION_NEEDS[section.id]
    if #section.tabs == 0 and needs then
      local module = B:GetModule(needs)
      local title = "Bastian's " .. tostring(module and module.title or needs) -- as Core's Works with
      section.needs = string.format(L["%s needs %s"], section.label, title)
    end
  end
  local gold = B:GetModule("Gold")
  if not (gold and gold:IsEnabled()) then
    byId.gold.label = L["Items"]
  end
  return out
end

-- The section of a tab id ("nav:list:npc"), or nil.
function Browser.SectionOf(navId)
  if navId == nil then
    return nil
  end
  if navId == "nav:more" then
    return "more"
  end
  for _, section in ipairs(Browser.Sections()) do
    for _, cat in ipairs(section.tabs) do
      if cat.id == navId then
        return section.id
      end
    end
  end
  return nil
end

-- The lit rail entry: the section of the lit tab; Here for a search without a type; More for
-- the More grid and the bookmarks.
function Browser.ActiveSection()
  local entry = shownList or Browser.ListEntry()
  if entry and entry.kind == "more" then
    return "more"
  end
  return Browser.SectionOf(Browser.NavActive()) or "here"
end

-- A rail entry clicked: Here, More, or the section's first tab.
function Browser.GoSection(id)
  if id == "here" then
    return Browser.ShowHere()
  elseif id == "more" then
    return Browser.ShowMore()
  end
  for _, section in ipairs(Browser.Sections()) do
    if section.id == id then
      local first = section.tabs[1]
      if first then
        Browser.SetListOpen(true)
        return Browser.Navigate(first.nav)
      end
      return false
    end
  end
  return false
end

-- A tab by its id, from any section (the keys, the tests): the section follows.
function Browser.NavClick(navId)
  if navId == "nav:more" then
    return Browser.ShowMore()
  end
  for _, cat in ipairs(Browser.Categories()) do
    if cat.id == navId then
      Browser.SetListOpen(true)
      return Browser.Navigate(cat.nav)
    end
  end
  return false
end

-- The button of what the list tile shows (drawn filled), nil for a search without a type.
function Browser.NavActive()
  return Browser.NavOf(shownList or Browser.ListEntry())
end

function Browser.NavOf(entry)
  if entry.kind == "here" then
    return "nav:here"
  elseif entry.kind == "list" then
    return "nav:list:" .. tostring(entry.type)
  elseif entry.kind == "view" then
    return "nav:view:" .. tostring(entry.id)
  elseif entry.kind == "bookmarks" then
    return "nav:bookmarks"
  elseif entry.kind == "more" then
    return "nav:more"
  elseif entry.kind == "home" and homeType then
    return "nav:list:" .. homeType -- the search's type filter
  elseif entry.kind == "inside" then
    return Browser.NavOf(originOf(entry)) -- the list the thing was stepped into from
  end
  return nil
end

local function railButton(i)
  local b = rail.buttons[i]
  if not b then
    b = S.action(rail, { label = "" })
    b:SetScript("OnClick", function(self)
      if self.section and not self.section.needs then
        Browser.GoSection(self.section.id)
      end
    end)
    rail.buttons[i] = b
  end
  return b
end

local function tabButton(i)
  local b = tabs.buttons[i]
  if not b then
    b = S.action(tabs, { label = "", row = true })
    b:SetScript("OnClick", function(self)
      if self.cat then
        Browser.SetListOpen(true) -- a tab fills the list tile
        Browser.Navigate(self.cat.nav)
      end
    end)
    tabs.buttons[i] = b
  end
  return b
end

-- Draws the rail (seven equal entries; pictograms alone when narrow) and the shown section's
-- tabs, which flow; the window lays out again when their rows change.
function Browser.RenderNav()
  if not rail then
    return
  end
  local sections = Browser.Sections()
  local activeSection = Browser.ActiveSection()
  local active = Browser.NavActive()
  local narrow = Browser.IsNarrow()
  local width = math.max(WIN_MIN, (win.frame:GetWidth() or 1000)) - 12
  local entryW = math.floor((width - RAIL_GAP * (#sections - 1)) / #sections)
  local shown
  for i, section in ipairs(sections) do
    local b = railButton(i)
    b.section = section
    b.spec.icon, b.spec.label = section.icon, section.label
    b.spec.hue = section.hue
    b.spec.only = narrow or nil
    b.spec.width = entryW
    b.spec.primary = (section.id == activeSection) or nil
    b.tip = function()
      return section.label, section.needs
    end
    b:SetEnabledFlat(not section.needs)
    b:Fit()
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", rail, "TOPLEFT", (i - 1) * (entryW + RAIL_GAP), 0)
    b:Show()
    if section.id == activeSection then
      shown = section
    end
  end
  rail.count, rail.active = #sections, activeSection
  -- the tabs: the section's lists and views; one list alone, Here and More draw no row
  local list = (shown and #shown.tabs > 1) and shown.tabs or {}
  local widths = {}
  for i, cat in ipairs(list) do
    local b = tabButton(i)
    b.cat = cat
    b.spec.icon, b.spec.label = cat.icon, cat.count and (cat.text .. "  " .. cat.count) or cat.text
    b.spec.hue = shown and shown.hue or nil
    b.spec.primary = (cat.id == active) or nil
    b.tip = cat.tip and function()
      return cat.text, cat.tip
    end or nil
    b:Fit()
    b:Show()
    widths[i] = b:GetWidth() or 60
  end
  for i = #list + 1, #tabs.buttons do
    tabs.buttons[i]:Hide()
    tabs.buttons[i].cat = nil
  end
  local places, height = Browser.Flow(widths, width, CAT_GAP, S.G.actionRow)
  for i, place in ipairs(places) do
    local b = tabs.buttons[i]
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", tabs, "TOPLEFT", place.x, -place.y)
  end
  tabs.count, tabs.active = #list, active
  tabs:SetShown(#list > 0)
  if height ~= tabs.height then
    tabs.height = height
    tabs:SetHeight(math.max(1, height))
    Browser.Layout()
  end
end

-- A category: Here, a list (the search's type while text is in the box), a view, the bookmarks.
function Browser.Navigate(target)
  if target.kind == "here" then
    return Browser.ShowHere()
  elseif target.kind == "list" then
    onTypeChip(target.type)
    return true
  elseif target.kind == "view" then
    return Browser.ShowView(target.id)
  elseif target.kind == "bookmarks" then
    return Browser.Bookmarks()
  elseif target.kind == "more" then
    return Browser.ShowMore()
  end
  return false
end

-- The breadcrumb (ADR 0056): where the two tiles are. The first step is what the list tile shows,
-- the last the page; stepping inside a thing (PA4) adds the steps between. -> { { kind, text, ref } }.
-- What a list tile's entry is called on the breadcrumb.
local function entryWords(entry)
  if entry.kind == "here" then
    return L["Here"]
  elseif entry.kind == "list" then
    local def = listDef(entry.type)
    return L[def and def.label or entry.type]
  elseif entry.kind == "view" then
    local def = B:GetView(entry.id)
    return def and tostring(def.title) or tostring(entry.id)
  elseif entry.kind == "home" then
    return L["Search"]
  elseif entry.kind == "more" then
    return L["More"]
  end
  return L["Bookmarks"]
end

-- Where the two tiles are (ADR 0056): the list, then the page; inside a thing: where it was
-- stepped into from, the thing, its open part, then what is picked there.
function Browser.Crumbs()
  local entry = shownList or Browser.ListEntry()
  local ref = Browser.PageRef()
  if entry.kind == "inside" then
    local origin = originOf(entry)
    local out = {
      { kind = "list", text = entryWords(origin), entry = origin },
      { kind = "thing", ref = entry.ref, text = B:Entity(entry.ref):Name() or entry.ref, entry = entry },
    }
    if entry.part then
      local _, parts = Browser.InsideRows(entry)
      for _, part in ipairs(parts) do
        if part.id == entry.part then
          out[#out + 1] = { kind = "part", text = part.title, entry = entry }
        end
      end
    end
    if ref and ref ~= entry.ref then
      out[#out + 1] = { kind = "page", ref = ref, text = B:Entity(ref):Name() or ref }
    end
    return out
  end
  local out = { { kind = "list", text = entryWords(entry) } }
  if ref then
    out[2] = { kind = "page", ref = ref, text = B:Entity(ref):Name() or ref }
  end
  return out
end

-- A step of the breadcrumb is a way back (ADR 0056): the list a thing was stepped into from,
-- the thing itself (its page, its parts shut), the open part (a narrow window's list).
function Browser.CrumbClick(crumb)
  if crumb.kind == "list" and crumb.entry then
    local origin = crumb.entry
    if origin.kind == "here" then
      Browser.ShowHere()
    else
      show(origin) -- the same entry again: its filters and its place are kept
    end
  elseif crumb.kind == "list" then
    Browser.SetListOpen(true) -- a narrow window goes back to its list
  elseif crumb.kind == "thing" then
    crumb.entry.part, crumb.entry.block = nil, nil
    Browser.Open(crumb.ref)
  elseif crumb.kind == "part" then
    Browser.SetListOpen(true)
  end
end

local function crumbButton(i)
  local b = crumbs.buttons[i]
  if not b then
    b = CreateFrame("Button", nil, crumbs)
    b:SetHeight(CRUMB_H)
    b.text = S.text(b, 11, S.C.dim)
    b.text:SetPoint("LEFT", b, "LEFT", 0, 0)
    b:SetScript("OnClick", function(self)
      if self.crumb then
        Browser.CrumbClick(self.crumb)
      end
    end)
    crumbs.buttons[i] = b
  end
  return b
end

function Browser.RenderCrumbs()
  if not crumbs then
    return
  end
  local list = Browser.Crumbs()
  local x = 2
  for i, crumb in ipairs(list) do
    local b = crumbButton(i)
    b.crumb = crumb
    local last = i == #list
    b.text:SetText((i > 1 and (S.H.muted .. ">|r  ") or "") .. crumb.text)
    S.ink(b.text, last and S.C.text or S.C.dim)
    local w = b.text:GetStringWidth() or 0
    if w == 0 then
      w = #crumb.text * 6 + (i > 1 and 14 or 0)
    end
    b:SetWidth(w)
    b:ClearAllPoints()
    b:SetPoint("LEFT", crumbs, "LEFT", x, 0)
    b:Show()
    x = x + w + 8
  end
  for i = #list + 1, #crumbs.buttons do
    crumbs.buttons[i]:Hide()
    crumbs.buttons[i].crumb = nil
  end
  crumbs.count = #list
end

-- ---------------------------------------------------------------------------------------------
-- Window (ADR 0056): the category buttons, the row of Back, Forward and the search, the
-- breadcrumb, then two tiles: the list and the page. Under ONE_MIN one tile at a time. (Slim,
-- the list alone as a tracker, went with ADR 0056, PA1.3: Quests has a tracker of its own.)
-- ---------------------------------------------------------------------------------------------

-- The list tile's width: remembered in the profile (dragged at the divider), else 36 % of the
-- window, never under LIST_MIN and never so wide that the page falls under DETAIL_MIN.
function Browser.ListWidth()
  local total = (win and win.frame:GetWidth()) or 1000
  local avail = total - 16
  local width = db().listWidth or math.floor(avail * 0.36)
  return math.max(LIST_MIN, math.min(width, avail - DETAIL_MIN))
end

function Browser.SetListWidth(width)
  if width then
    db().listWidth = width
  end
  Browser.Layout()
end

-- One tile at a time: the window is too narrow for a list beside a page.
function Browser.IsNarrow()
  return win ~= nil and (win.frame:GetWidth() or 1000) < ONE_MIN
end

-- Places the bars and the tiles for the window's width and mode.
-- Whether the filter chips show: the list tile shows rows that filter (not Here), and in a
-- narrow window the list is the tile on screen.
function Browser.FiltersShown()
  local entry = shownList or Browser.ListEntry()
  if not entry or entry.kind == "here" then
    return false
  end
  return listOpen or not Browser.IsNarrow()
end

local SEARCH_SHARE, SEARCH_W_MIN, SEARCH_W_MAX = 0.4, 200, 420 -- the box's part of the title row
local FILTER_TAIL = 4 -- the air a filter bar keeps under its last line

-- The search box in the title row (ADR 0058, PH2): right of the title, before Dock; under
-- ONE_MIN a magnifier stands there instead, and a click on it opens the box over the title.
local function placeSearch(narrow, width)
  local head = win.head
  local mag = toolbar.mag
  search:ClearAllPoints()
  win.title:ClearAllPoints()
  win.title:SetPoint("LEFT", head, "LEFT", 10, 0)
  mag:SetShown(narrow)
  if narrow then
    local open = searching == true
    search:SetShown(open)
    win.title:SetShown(not open)
    search:SetPoint("LEFT", head, "LEFT", 10, 0)
    search:SetPoint("RIGHT", mag, "LEFT", -4, 0)
    win.title:SetPoint("RIGHT", mag, "LEFT", -8, 0)
  else
    search:Show()
    win.title:Show()
    search:SetWidth(math.max(SEARCH_W_MIN, math.min(SEARCH_W_MAX, math.floor(width * SEARCH_SHARE))))
    search:SetPoint("RIGHT", toolbar.dock, "LEFT", -8, 0)
    win.title:SetPoint("RIGHT", search, "LEFT", -8, 0)
  end
end

-- The magnifier's click in a narrow window: the box over the title, or the title back.
function Browser.ToggleSearch(open)
  if open == nil then
    open = not searching
  end
  searching = open and true or false
  Browser.Layout()
  if searching and search:IsShown() then
    search:SetFocus()
  end
end

function Browser.IsSearching()
  return searching == true
end

function Browser.Layout()
  if not win then
    return
  end
  local content = win.content
  local narrow = Browser.IsNarrow()
  local bar = 6 + S.G.action + ((tabs:IsShown() and (4 + tabs.height)) or 0) + 6
  toolbar:ClearAllPoints()
  toolbar:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -bar)
  toolbar:SetPoint("TOPRIGHT", content, "TOPRIGHT", -6, -bar)
  local width = math.max(WIN_MIN, (win.frame:GetWidth() or 1000)) - 12
  placeSearch(narrow, width)
  -- the row under the rail (ADR 0058): Back, Forward, and right of them the filter chips; they
  -- flow into more lines at the row's width
  local arrows = (toolbar.back:GetWidth() or 0) + 2 + (toolbar.forward:GetWidth() or 0) + 8
  local hostW = math.max(120, width - arrows)
  local hostH = 0
  if Browser.FiltersShown() then
    layingOut = true
    tree:SetFilterWidth(hostW)
    layingOut = false
    hostH = tree.filterBar and tree.filterBar:Height() or 0
    if hostH <= 1 then
      hostH = 0 -- nothing to filter by
    end
  end
  local rowH = TOOLBAR_H
  filterHost:ClearAllPoints()
  filterHost:SetPoint("TOPLEFT", toolbar, "TOPLEFT", arrows, 0)
  if hostH > 0 then
    rowH = math.max(TOOLBAR_H, hostH - FILTER_TAIL)
  end
  filterHost:SetWidth(hostW)
  filterHost:SetShown(hostH > 0)
  crumbs:ClearAllPoints()
  crumbs:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -(bar + rowH + 4))
  crumbs:SetPoint("TOPRIGHT", content, "TOPRIGHT", -6, -(bar + rowH + 4))
  local top = -(bar + rowH + 4 + CRUMB_H + 4)
  listPane:ClearAllPoints()
  detailPane:ClearAllPoints()
  if narrow then
    local shown, hidden = listPane, detailPane
    if not listOpen then
      shown, hidden = detailPane, listPane
    end
    shown:SetPoint("TOPLEFT", content, "TOPLEFT", 6, top)
    shown:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -6, 6)
    shown:Show()
    hidden:Hide()
    splitter:Hide()
  else
    listPane:SetPoint("TOPLEFT", content, "TOPLEFT", 6, top)
    listPane:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 6, 6)
    listPane:SetWidth(Browser.ListWidth())
    listPane:Show()
    splitter:Show()
    detailPane:SetPoint("TOPLEFT", splitter, "TOPRIGHT", 4, 0)
    detailPane:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -6, 6)
    detailPane:Show()
  end
end

-- Whether the list tile shows: always beside the page in a wide window, by turns in a narrow one.
function Browser.IsListOpen()
  return listOpen or not Browser.IsNarrow()
end

-- A narrow window's tile: the list (true) or the page. A wide window shows both and only
-- remembers the wish. (`animate` is taken and ignored: the pane slid until ADR 0056.)
function Browser.SetListOpen(open, _animate)
  open = open and true or false
  if open == listOpen then
    return
  end
  listOpen = open
  if win and Browser.IsNarrow() then
    Browser.Layout()
    if win:IsShown() then
      Browser.Render()
    end
  end
end

-- A click on a row with a ref (list, Here, detail): the map rings it and its page opens in the
-- detail pane; a right click opens the entity menu; a row's own onClick wins.
local function rowClick(row, button, owner)
  if row.onClick and button ~= "RightButton" then
    -- a row's own click that puts another page in the page tile shows that tile in a narrow
    -- window ("when I scale it narrow, a click on the left pane
    -- simply does nothing as the right pane is not visible anymore")
    local before = Browser.PageRef()
    row.onClick(row, button)
    local after = Browser.PageRef()
    if after and after ~= before and Browser.IsNarrow() then
      Browser.SetListOpen(false)
    end
  elseif row.ref and button == "RightButton" then
    B.UI.EntityMenu(row.ref, nil, { source = "browser" })
  elseif row.ref then
    B:Focus(row.ref, { source = "browser" }) -- the map rings it (ADR 0013 D) ...
    Browser.Open(row.ref) -- ... and its page shows in the detail pane
  elseif row.hasChildren and owner and owner.ToggleFold then
    owner:ToggleFold(row)
  end
end

local function build(self)
  -- Slim went with ADR 0056 (PA1.3): a profile saved in slim mode gets its wide size back, and
  -- what the mode kept goes
  local saved = db()
  if saved.slim and type(saved.wideSize) == "table" and type(saved.window) == "table" then
    saved.window.size = { saved.wideSize[1], saved.wideSize[2] }
  end
  saved.slim, saved.slimWidth, saved.wideSize, saved.hideTracker = nil, nil, nil, nil
  win = B.UI.Window("BastiansBrowserFrame", {
    module = "Browser", -- the options button opens this page (R27.1)
    title = L["Browser"],
    width = 1000,
    height = 600,
    minWidth = WIN_MIN,
    gestures = { -- a right-button drag over the window goes back or forward
      back = function()
        Browser.Back()
      end,
      forward = function()
        Browser.Forward()
      end,
    },
    db = db().window,
    onShow = function()
      Browser.Layout()
      Browser.Render()
    end,
    onHide = function()
      leaveView() -- a view's own frames (Quests' item bar) go with the window ...
      if hereDossier then
        hereDossier:NotifyHide() -- ... and so do the Here entry's (C4)
      end
      previewRef, hovered = nil, nil
    end,
    onResize = function()
      Browser.RenderNav() -- the rail and the tabs follow the new width
      Browser.RenderCrumbs()
      Browser.Layout()
      if tree then
        tree:Refresh()
      end
      if hereDossier then
        hereDossier:Refresh()
      end
      if dossier then
        dossier:Refresh()
      end
    end,
  })
  local content = win.content
  -- the rail (ADR 0058): seven entries on top, then the shown section's tabs, as high as their rows
  rail = CreateFrame("Frame", nil, content)
  rail:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -6)
  rail:SetPoint("TOPRIGHT", content, "TOPRIGHT", -6, -6)
  rail:SetHeight(S.G.action)
  rail.buttons = {}
  tabs = CreateFrame("Frame", nil, content)
  tabs:SetPoint("TOPLEFT", rail, "BOTTOMLEFT", 0, -4)
  tabs:SetPoint("TOPRIGHT", rail, "BOTTOMRIGHT", 0, -4)
  tabs:SetHeight(1)
  tabs.buttons = {}
  tabs:Hide()
  toolbar = CreateFrame("Frame", nil, content)
  Browser.toolbar = toolbar -- for the tests and the tips check
  toolbar:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -(6 + S.G.action + 6)) -- Layout places it
  toolbar:SetPoint("TOPRIGHT", content, "TOPRIGHT", -6, -(6 + S.G.action + 6))
  -- the breadcrumb under the search row
  crumbs = CreateFrame("Frame", nil, content)
  crumbs:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -4)
  crumbs:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", 0, -4)
  crumbs:SetHeight(CRUMB_H)
  crumbs.buttons = {}
  -- the bar is 26 px with 30 px arrows: the owner wanted Back and Forward prominent (22.10.2026)
  toolbar:SetHeight(TOOLBAR_H)
  -- Back and Forward as declared actions (ADR 0046): the pictogram and the word in every look
  toolbar.back = S.action(toolbar, { icon = "back", label = L["Back"], boxed = true, row = true })
  toolbar.back.tip = function()
    return L["Back"], L["The page before. Also: hold the right mouse button and drag to the left."]
  end
  toolbar.back:SetPoint("LEFT", toolbar, "LEFT", 0, 0)
  toolbar.back:SetScript("OnClick", function()
    Browser.Back()
  end)
  toolbar.forward = S.action(toolbar, { icon = "forward", label = L["Forward"], boxed = true, row = true })
  toolbar.forward.tip = function()
    return L["Forward"], L["The page after. Also: hold the right mouse button and drag to the right."]
  end
  toolbar.forward:SetPoint("LEFT", toolbar.back, "RIGHT", 2, 0)
  toolbar.forward:SetScript("OnClick", function()
    Browser.Forward()
  end)
  -- ~~Target~~ (target follow, C6) left the toolbar (its use was never
  -- clear); following the target stays a setting (followTarget, on by default)
  -- the search box fills the bar after the arrows; typing searches the world
  search = S.search(win.head, L["Search: a name, or a type first (npc wel)"]) -- the title row (ADR 0058)
  search.queryFields = L["type (npc, item, quest, zone, ...)"] -- the world search's (ADR 0045)
  search:SetPoint("RIGHT", win.head, "RIGHT", -120, 0) -- Layout places it before Dock
  search.longHint = L["Search: a name, or a type first (npc wel)"]
  search.hint:SetWordWrap(false)
  search.hint:SetJustifyH("LEFT")
  -- the filter chips stand beside the box (ADR 0056); the list's tree draws its bar in here
  filterHost = CreateFrame("Frame", nil, content)
  filterHost:SetHeight(1)
  filterHost:Hide()
  -- the scope chip inside the box (ADR 0056): where the list and the search look. A click opens
  -- its choices, the x looks everywhere
  scope = CreateFrame("Button", nil, search)
  scope:SetHeight(18)
  scope:SetPoint("RIGHT", search.clear, "LEFT", -2, 0)
  scope.face = S.roundFill(scope, S.C.press, "pill")
  scope.label = S.text(scope, 11, S.C.text)
  scope.label:SetPoint("LEFT", 8, 0)
  scope.label:SetWordWrap(false)
  scope.tip = function(chip)
    return L["Where"], chip.dim and chip.dim.tip or nil
  end
  scope:SetScript("OnEnter", S.TipEnter)
  scope:SetScript("OnLeave", S.TipLeave)
  scope:SetScript("OnClick", function(chip)
    local m = B.UI.FilterMenuFrame()
    if m and m:IsShown() and m.anchor == chip then
      m:Hide()
    elseif chip.dim then
      B.UI.FilterMenu(chip.dim, chip)
    end
  end)
  scope.clear = CreateFrame("Button", nil, scope)
  scope.clear:SetSize(14, 18)
  scope.clear:SetPoint("RIGHT", -2, 0)
  scope.clear.label = S.text(scope.clear, 12, S.C.dim)
  scope.clear.label:SetPoint("CENTER")
  scope.clear.label:SetText("x")
  scope.clear.tip = L["Look everywhere"]
  scope.clear:SetScript("OnEnter", S.TipEnter)
  scope.clear:SetScript("OnLeave", S.TipLeave)
  scope.clear:SetScript("OnClick", function()
    B.UI.HideFilterMenu()
    local dim = scope.dim
    if dim and dim.onSelect then
      dim.onSelect(nil)
    end
  end)
  scope:Hide()
  -- the keys (ADR 0038): while the box has focus, Up and Down move a lit row through the list,
  -- Enter opens it, Escape clears the box; the rows take no keys of their own
  search:SetScript("OnKeyDown", function(_, key)
    if key == "DOWN" or key == "UP" then
      Browser.MoveKeyRow(key == "DOWN" and 1 or -1)
    elseif key == "PAGEDOWN" or key == "PAGEUP" then
      Browser.TurnPage(key == "PAGEDOWN" and 1 or -1)
    end
  end)
  search:SetScript("OnEnterPressed", function(box)
    local row = Browser.KeyRow()
    if row then
      rowClick(row, "LeftButton", tree)
    else
      box:ClearFocus()
    end
  end)
  search:SetScript("OnEscapePressed", function(box)
    box:SetText("")
    box:ClearFocus()
  end)
  search:SetScript("OnTextChanged", function(box)
    local text = box:GetText() or ""
    if text == "" then
      box.hint:Show()
      box.clear:Hide()
    else
      box.hint:Hide()
      box.clear:Show()
    end
    if syncingBox then
      return -- the box follows the list pane, nobody typed
    end
    if text ~= "" then
      Browser.SetListOpen(true) -- the results show in the list tile
    end
    local entry = shownList or Browser.ListEntry()
    local before = history[cursor - 1]
    if
      entry.kind == "home"
      and text == ""
      and before
      and (before.kind == "list" or before.kind == "here")
    then
      -- the search was typed on a list: emptied, the list shows whole again (owner, retail
      -- 31.10.2026: "the middle tile should again show the full list ... but it stays empty")
      Browser.Back()
    elseif entry.kind == "home" then
      entry.text = text
      renderHome(text) -- the search entry searches as you type
    elseif text ~= "" then
      -- The search is always global: every list, everywhere, the hits by list in the list tile
      -- ("Search field is always global and will change the left
      -- tile; the filter in the left tile filters the left tile"). ~~On a list it kept to that
      -- list and its scope, inside a zone to that zone~~: "wolf" typed on Zones found nothing and
      -- offered "284 in the other lists".
      Browser.Search(text, false, false)
    end
  end)

  -- the list pane: a view's control bar, the summary, the filter bar and the rows (the tree), or
  -- the Here entry (the player's zone as a dossier)
  listPane = CreateFrame("Frame", nil, content)
  S.panel(listPane, S.C.panel) -- the list tile has a face of its own (ADR 0056)
  S.inset(listPane)
  header = CreateFrame("Frame", nil, listPane)
  header:SetPoint("TOPLEFT", listPane, "TOPLEFT", 0, 0)
  header:SetPoint("TOPRIGHT", listPane, "TOPRIGHT", 0, 0)
  header:SetHeight(1)
  controlBar = Widgets.ControlBar(header)
  controlBar:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
  controlBar:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
  controlBar:Hide()
  -- the filter of the rows shown, beside the summary
  filterBox = S.search(listPane, L["Filter"])
  filterBox:SetHeight(20)
  filterBox:SetWidth(Browser.FILTER_W)
  filterBox:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -14, -2)
  filterBox.count = S.text(filterBox, 10, S.C.muted)
  filterBox.count:SetPoint("RIGHT", filterBox.clear, "LEFT", -2, 0)
  filterBox:SetScript("OnTextChanged", function(box)
    local text = box:GetText() or ""
    box.hint:SetShown(text == "")
    box.clear:SetShown(text ~= "")
    if not syncingFilter then
      Browser.FilterList(text)
    end
  end)
  filterBox:SetScript("OnKeyDown", function(_, key)
    if key == "DOWN" or key == "UP" then
      Browser.MoveKeyRow(key == "DOWN" and 1 or -1)
    elseif key == "PAGEDOWN" or key == "PAGEUP" then
      Browser.TurnPage(key == "PAGEDOWN" and 1 or -1)
    end
  end)
  filterBox:SetScript("OnEnterPressed", function(box)
    local row = Browser.KeyRow()
    if row then
      rowClick(row, "LeftButton", tree)
    else
      box:ClearFocus()
    end
  end)
  filterBox:SetScript("OnEscapePressed", function(box)
    box:SetText("")
    box:ClearFocus()
  end)
  summary = S.text(listPane, 11, S.C.dim)
  summary:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 2, -2)
  summary:SetPoint("RIGHT", filterBox, "LEFT", -6, 0)
  summary:SetHeight(20)
  -- the stat tiles (ADR 0058, PH4): a row of up to four above the rows; a spacer when none
  stats = CreateFrame("Frame", nil, listPane)
  stats:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", -2, 0)
  stats:SetPoint("TOPRIGHT", filterBox, "BOTTOMRIGHT", 0, 0)
  stats:SetHeight(4)
  stats.tiles = {}
  tree = B.UI.Tree(listPane, {
    db = db().tree,
    tiles = true, -- a row that stands for one thing is a tile (ADR 0056)
    filterHost = filterHost, -- the chips stand beside the search, not above the rows
    -- ~~a tile's edge steps inside the thing (ADR 0056)~~: the page tile's own filter does what
    -- it did (, R2: "we better do as I said and have a filter in the
    -- right pane")
    onFilterHeight = function()
      if not layingOut then
        Browser.Layout() -- more or fewer lines of chips: the tiles move
      end
    end,
    twoLine = true, -- rows with `meta` (views: My quests) take two lines; list rows have none
    worth = Browser.ShowWorth,
    ctx = { source = "browser" },
    onHover = Browser.OnRowHover,
    onClick = rowClick,
    pages = true, -- pages of what fits, not a scroll (ADR 0058, PH3)
    onRender = function()
      Browser.UpdatePager()
    end,
  })
  -- the foot of the list tile (ADR 0058): "1-12 of 430" between the arrows that turn the page
  pager = CreateFrame("Frame", nil, listPane)
  pager:SetHeight(PAGER_H)
  pager:SetPoint("BOTTOMLEFT", listPane, "BOTTOMLEFT", 0, 0)
  pager:SetPoint("BOTTOMRIGHT", listPane, "BOTTOMRIGHT", -14, 0)
  pager.prev = S.action(pager, { icon = "back", label = L["Previous page"], only = true, row = true })
  pager.prev:SetPoint("LEFT", pager, "LEFT", 2, 0)
  pager.prev:SetScript("OnClick", function()
    Browser.TurnPage(-1)
  end)
  pager.next = S.action(pager, { icon = "forward", label = L["Next page"], only = true, row = true })
  pager.next:SetPoint("RIGHT", pager, "RIGHT", -2, 0)
  pager.next:SetScript("OnClick", function()
    Browser.TurnPage(1)
  end)
  pager.text = S.text(pager, 11, S.C.dim)
  pager.text:SetPoint("CENTER", pager, "CENTER", 0, 0)
  pager:Hide()
  tree.chips:ClearAllPoints()
  tree.chips:SetPoint("TOPLEFT", stats, "BOTTOMLEFT", 0, 0)
  tree.chips:SetPoint("TOPRIGHT", stats, "BOTTOMRIGHT", -12, 0)
  tree.scroll:HookScript("OnMouseWheel", Browser.OnListWheel)
  tree.scroll:ClearAllPoints()
  tree.scroll:SetPoint("TOPLEFT", tree.chips, "BOTTOMLEFT", 0, -2)
  tree.scroll:SetPoint("BOTTOMRIGHT", listPane, "BOTTOMRIGHT", -14, 0) -- UpdatePager keeps the foot free
  hereDossier = B.UI.Dossier(listPane, {
    here = true,
    twoLine = true, -- quest rows on two lines: name and icons, then the meta
    iconsAlways = true, -- the map and route buttons on every row
    worth = Browser.ShowWorth, -- the worth on its own lines, or none
    ctx = { source = "browser" },
    host = { frame = win.frame },
    onHover = Browser.OnRowHover,
    onClick = rowClick,
  })
  hereDossier.frame:ClearAllPoints()
  hereDossier.frame:SetPoint("TOPLEFT", stats, "BOTTOMLEFT", 0, 0)
  hereDossier.frame:SetPoint("BOTTOMRIGHT", listPane, "BOTTOMRIGHT", -14, 0)
  hereDossier:Hide()

  -- the divider between list and detail: a grip wide enough to catch
  splitter = CreateFrame("Frame", nil, content)
  splitter:SetWidth(10)
  splitter:SetPoint("TOPLEFT", listPane, "TOPRIGHT", 0, 0)
  splitter:SetPoint("BOTTOMLEFT", listPane, "BOTTOMRIGHT", 0, 0)
  splitter.line = S.fill(splitter, S.C.line)
  splitter.line:ClearAllPoints()
  splitter.line:SetPoint("TOP", 0, 0)
  splitter.line:SetPoint("BOTTOM", 0, 0)
  splitter.line:SetWidth(2)
  splitter:EnableMouse(true)
  splitter:SetScript("OnEnter", function(bar)
    S.tint(bar.line, S.C.accent, 0.8)
    if GameTooltip then
      GameTooltip:SetOwner(bar, "ANCHOR_RIGHT")
      S.TipLine(GameTooltip, L["Drag to widen the list or the page"], "tipText")
      GameTooltip:Show()
    end
  end)
  splitter:SetScript("OnLeave", function(bar)
    S.tint(bar.line, S.C.line)
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  splitter:SetScript("OnMouseDown", function(bar)
    bar:SetScript("OnUpdate", function(me)
      local x = GetCursorPosition() / (me:GetEffectiveScale() or 1)
      local left = listPane:GetLeft()
      if left then
        Browser.SetListWidth(x - left - 5)
      end
    end)
  end)
  splitter:SetScript("OnMouseUp", function(bar)
    bar:SetScript("OnUpdate", nil)
    db().listWidth = listPane:GetWidth()
  end)

  -- the detail pane: the dossier of the kept page or the preview (ADR 0018)
  detailPane = CreateFrame("Frame", nil, content)
  S.inset(detailPane)
  detailPane:SetScript("OnSizeChanged", function()
    if partMap and partMap:IsShown() then
      Browser.RenderPartMap() -- the map fills the tile at its new size
    end
  end)
  detailPane:SetPoint("TOPLEFT", splitter, "TOPRIGHT", 4, 0)
  detailPane:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -6, 6)
  -- the page tile's filter: shown while the page lists more than
  -- one thing; what is typed narrows every list of the page, of every tab, and the pictures go
  pageFilter = S.search(detailPane, L["Filter this page"])
  pageFilter:SetHeight(20)
  pageFilter:SetWidth(Browser.FILTER_W)
  pageFilter:SetPoint("TOPRIGHT", detailPane, "TOPRIGHT", -14, -4)
  pageFilter:Hide()
  pageFilter:SetScript("OnTextChanged", function(box)
    local text = box:GetText() or ""
    box.hint:SetShown(text == "")
    box.clear:SetShown(text ~= "")
    if dossier then
      dossier:SetQuery(text)
    end
  end)
  pageFilter:SetScript("OnEscapePressed", function(box)
    box:SetText("")
    box:ClearFocus()
  end)
  dossier = B.UI.Dossier(detailPane, {
    -- a sheet's rows are quiet: their icons show under the mouse and on the focused row (ADR 0054)
    portrait = true, -- the 3D model of a creature or a wearable item
    cards = true, -- the page's parts are cards with tiles (ADR 0056)
    -- a card's "All N" opens the card where it stands (R2; ~~the list tile took the thing~~)
    stats = true, -- the stats strip under the band (ADR 0038)
    worth = Browser.ShowWorth,
    ctx = { source = "browser" },
    buttons = Browser.BandButtons,
    onClick = rowClick,
  })

  -- Dock beside the map (ADR 0013 E) lives in the title bar, left of the window's options
  -- button
  toolbar.dock = S.action(win.head, { icon = "dock", label = L["Dock"], row = true })
  toolbar.dock.tip = function()
    return L["Dock to the map"],
      L["The window sits beside the map at its height and moves with it. Click again to undock."]
  end
  toolbar.dock:SetPoint("RIGHT", win.options or win.close, "LEFT", -4, 0)
  toolbar.dock:SetScript("OnClick", function()
    B.UI.ToggleDock()
    Browser.UpdateDock()
  end)
  -- the magnifier of a narrow window (ADR 0058): the search box over the title on a click
  toolbar.mag = S.action(win.head, { icon = "search", label = L["Search"], only = true, row = true })
  toolbar.mag.tip = function()
    return L["Search"], L["Opens the search box over the title; a second click brings the title back."]
  end
  toolbar.mag:SetPoint("RIGHT", toolbar.dock, "LEFT", -4, 0)
  toolbar.mag:SetScript("OnClick", function()
    Browser.ToggleSearch()
  end)
  toolbar.mag:Hide()

  self.win, self.tree, self.toolbar, self.summary, self.search = win, tree, toolbar, summary, search
  self.filterBox, self.filterHost, self.scope = filterBox, filterHost, scope
  self.header, self.controlBar, self.dossier, self.hereDossier = header, controlBar, dossier, hereDossier
  self.rail, self.tabs, self.crumbs = rail, tabs, crumbs
  self.listPane, self.detailPane, self.pager, self.stats = listPane, detailPane, pager, stats
  self.splitter = splitter
  Browser.Layout()
end

-- Target follow (C6): with the setting on and the window shown, an NPC or object the player
-- targets becomes the subject; never in combat lockdown (nothing secure is touched, the rule keeps
-- the window quiet in fights); players give no entity and are ignored.
function Browser.FollowTarget()
  if not (mod and win and win:IsShown() and db().followTarget) then
    return false
  end
  if InCombatLockdown() then
    return false
  end
  local ref = B.Compat.TargetEntity()
  if not ref then
    return false
  end
  if Browser.ShownPage() == ref then
    return true
  end
  return Browser.Open(ref)
end

-- The Wowhead address of an entity: retail's site on retail, its Classic site on Forever (the
-- Classic world, the Classic ids). nil for a type Wowhead has no page for.
local WOWHEAD_TYPES = { quest = "quest", item = "item", npc = "npc", object = "object", spell = "spell" }
function Browser.WowheadLink(ref)
  local typ, id = B.Entity.Parse(ref or "")
  local page = typ and WOWHEAD_TYPES[typ]
  if not (page and tonumber(id)) then
    return nil
  end
  local site = B.Client == "forever" and "https://www.wowhead.com/classic/" or "https://www.wowhead.com/"
  return site .. page .. "=" .. id
end

function Browser.ToggleTarget()
  db().followTarget = not db().followTarget
  if db().followTarget then
    Browser.FollowTarget()
  end
end

-- Opens the window as it is (Here before anything else): `/bq` and the minimap button (C4).
function Browser.OpenWindow()
  if not (mod and mod:IsEnabled()) then
    return false
  end
  if not win then
    build(mod)
  end
  if win:IsShown() then
    win:Show() -- to the front
    return true
  end
  if current then
    win:Show() -- onShow renders the entry that was open
    return true
  end
  return Browser.ShowHere()
end

-- The minimap button: the window, or closed when it shows already ("opens
-- but does not close"); true when shown.
function Browser.ToggleWindow()
  if win and win:IsShown() then
    win:Hide()
    return false
  end
  return Browser.OpenWindow()
end

show = function(entry, record)
  if not win then
    build(mod)
  end
  current = entry
  previewRef = nil -- a click keeps what it opens (ADR 0018 C)
  if record ~= false then
    push(entry)
  end
  -- a narrow window shows one tile: the page for a page, the list for everything else
  local wantList = entry.kind ~= "page"
  if wantList ~= listOpen then
    listOpen = wantList
    if Browser.IsNarrow() then
      Browser.Layout()
    end
  end
  if win:IsShown() then
    win:Show() -- to the front
    Browser.Render()
  else
    win:Show() -- onShow renders
  end
  if entry.kind == "page" then
    mod:Fire("BASTIANS_PAGE_SHOWN", entry.ref) -- the map follows with Follow on (ADR 0013 D)
  end
end

-- The world search for `text`, kept to a list (`typ`, its key; nil keeps the current one, false
-- clears it): a search entry in the list pane with the text in the box. Back returns to where it
-- was typed; the detail keeps its page.
-- `scopeOf` (ADR 0056): "here" or "continent" keeps the search to the player's zone or
-- continent, "within" to the zone `within` ({ map, name }, Browser.WithinOf), false looks
-- everywhere, nil leaves the search entry's scope as it is.
function Browser.Search(text, typ, scopeOf, within)
  if not (mod and mod:IsEnabled()) then
    return false
  end
  if typ ~= nil then
    homeType = typ or nil
  end
  local entry = Browser.ListEntry()
  if entry.kind == "home" and win and win:IsShown() and shownList == entry then
    entry.text = text
    if scopeOf ~= nil then
      entry.scope = scopeOf or nil
      entry.within = within
    end
    syncSearchBox(entry)
    renderHome(text)
    Browser.RenderNav()
  else
    show({ kind = "home", text = text, scope = scopeOf or nil, within = within })
  end
  return true
end

-- The zone a thing stepped into stands for as a search's scope: a zone itself, an area its zone;
-- nil for what has no one place (a chain, a dungeon's bosses).
function Browser.WithinOf(ref)
  local typ, id = B.Entity.Parse(ref)
  local d = data()
  local rec = d and typ and d:Get(typ, id) or nil
  local map = typ == "zone" and id or (typ == "area" and rec and rec.zone) or nil
  local zone = map and d and d:Get("zone", map) or nil
  return zone and zone.name and { map = map, name = zone.name } or nil
end

-- The search entry with an empty box: the views, the bookmarks and the recent pages as rows.
function Browser.Home()
  if not (mod and mod:IsEnabled()) then
    return false
  end
  show({ kind = "home", text = "" })
  return true
end

-- The player's zone in the list pane (ADR 0018: the first navigation entry).
function Browser.ShowHere()
  if not (mod and mod:IsEnabled()) then
    return false
  end
  local wasShown = win ~= nil and win:IsShown()
  show({ kind = "here" })
  Browser.SetListOpen(true, wasShown) -- Here lives in the list pane: out with it (R25.36)
  return true
end

function Browser.Open(ref)
  if not mod or not mod:IsEnabled() then
    return false
  end
  if ref == nil then
    return Browser.Home()
  end
  if not B.Entity.Parse(ref) then
    B:Say(L["Not an entity reference: %s"], tostring(ref))
    return false
  end
  mod.current = ref
  show({ kind = "page", ref = ref })
  return true
end

function Browser.List(typ)
  if not (mod and mod:IsEnabled() and listDef(typ)) then
    return false
  end
  show({ kind = "list", type = typ })
  return true
end

function Browser.Bookmarks()
  if not (mod and mod:IsEnabled()) then
    return false
  end
  show({ kind = "bookmarks" })
  return true
end

function Browser.Back()
  if cursor > 1 then
    cursor = cursor - 1
    show(history[cursor], false)
  end
end

function Browser.Forward()
  if cursor < #history then
    cursor = cursor + 1
    show(history[cursor], false)
  end
end

-- Back to a point of the trail (C5): what came after it is dropped, as the mockup walks the graph.
function Browser.GoTo(index)
  local entry = history[index]
  if not entry then
    return false
  end
  for i = #history, index + 1, -1 do
    history[i] = nil
  end
  cursor = index
  show(entry, false)
  return true
end

function Browser.Current()
  return current
end

Browser.Show = show

-- ---------------------------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------------------------

mod = B:NewModule("Browser", {
  news = ns.NEWS, -- What's new (ADR 0021)
  addon = ADDON,
  open = function()
    Browser.ToggleWindow()
  end,
  title = L["Browser"],
  apiVersion = 1,
  data = { "world", "quests", "items" },
  optional = { "QuestieDB" },
  defaults = {
    profile = {
      window = {},
      tree = {},
      followTarget = true,
      showWorth = true, -- the worth (rewards, prices) on the rows
    },
    char = { bookmarks = {} },
  },
  options = {
    {
      type = "toggle",
      key = "showWorth",
      label = L["Show what quests and items are worth (rewards, prices) on the rows"],
      default = true,
    },
    {
      type = "toggle",
      key = "followTarget",
      label = L["Follow the target: an NPC or object you target becomes the subject"],
      default = true,
    },
    {
      -- "an option to set the browser map style - and then provide all
      -- minimap in that style"; the large map keeps its own
      type = "select",
      key = "miniMapStyle",
      label = L["Map style of the mini maps"],
      default = "map",
      values = function()
        local out = { map = L["As on the large map"], physical = L["The client's painting"] }
        local picture = B:GetService("mapPicture")
        for _, st in ipairs(picture and picture:Styles() or {}) do
          out[st.key] = st.title
        end
        return out
      end,
    },
    {
      -- the hover preview
      type = "select",
      key = "preview",
      label = L["Preview a row in the page pane"],
      default = "shift",
      values = {
        shift = L["While Shift is held"],
        hover = L["On every hover"],
        off = L["Never"],
      },
    },
  },
  OnEnable = function(self)
    Browser.RegisterStats(self) -- the Lands for you tile (ADR 0058, PH4)
    -- a note saved on the shown page shows at once ("it does not
    -- show up without reloading the node")
    self:On("BASTIANS_NOTES_CHANGED", function()
      -- a frame later: the registry drops the section's cache on the same message first
      C_Timer.After(0, function()
        if win and win:IsShown() and dossier and Browser.PageRef() then
          renderDetail()
        end
      end)
    end)
    listening = {
      BASTIANS_DATA_LOADED = true,
      BASTIANS_ENTITY_CHANGED = true,
      BASTIANS_REGISTRY_CHANGED = true,
      BASTIANS_QUESTS_CHANGED = true,
      BASTIANS_PRICES_UPDATED = true,
      BASTIANS_REWARD_INFO_CHANGED = true,
      BASTIANS_ACTION_STATE = true,
      BASTIANS_TRACKED_CHANGED = true,
      BASTIANS_ENTITY_FOCUSED = true,
    }
    -- the one window (ADR 0012): every app's views open here
    B:ProvideService(self, "views", {
      Show = function(_, id, args)
        return Browser.ShowView(id, args)
      end,
      ShowPage = function(_, ref)
        return Browser.Open(ref)
      end,
      IsShown = function(_, id)
        if id == nil then -- the window itself
          return win ~= nil and win:IsShown()
        end
        local entry = Browser.ListEntry()
        return win ~= nil and win:IsShown() and entry.kind == "view" and entry.id == id
      end,
      Open = function() -- the window as it is, Here before anything else (C4, ADR 0018)
        return Browser.OpenWindow()
      end,
      Current = function()
        local entry = Browser.ListEntry()
        if win and win:IsShown() and entry.kind == "view" then
          return entry.id, entry.args
        end
        return nil
      end,
      CurrentPage = function()
        if win and win:IsShown() then
          return Browser.ShownPage()
        end
        return nil
      end,
      Hide = function()
        if win then
          win:Hide()
        end
      end,
    }, { priority = 100 })
    -- the Wowhead page of a quest, item, NPC, object or spell: the game
    -- opens no browser, so the link goes into the chat input to copy (as the book's links)
    B:RegisterAction(self, {
      id = "browser.wowhead",
      label = L["Copy Wowhead link"],
      short = L["Wowhead"],
      icon = B.UI.IconTexture("copy"),
      types = { "quest", "item", "npc", "object", "spell" },
      order = 88,
      run = function(ref)
        local link = Browser.WowheadLink(ref)
        if link then
          B.Compat.OpenChat(link)
          B:Say(L["The link is in the chat input: copy it with Ctrl+C."])
        end
      end,
    })
    B:RegisterAction(self, {
      id = "browser.open",
      label = L["Open in Browser"],
      icon = B.UI.IconTexture("other"),
      types = "*",
      order = 20,
      -- the page's own card does not offer to re-open itself (ADR 0013, N1) ...
      when = function(ref, ctx)
        if ctx and ctx.source == "browser" and win and win:IsShown() then
          return Browser.ShownPage() ~= ref
        end
        return true
      end,
      -- ... and everywhere else the action is greyed instead of hidden: inside
      -- the Browser the row click opens the page already; from the map or a tooltip it opens the
      -- page unless the Browser already shows that page
      enabled = function(ref, ctx)
        if not (win and win:IsShown()) then
          return true
        end
        if ctx and ctx.source == "browser" then
          return false
        end
        return Browser.ShownPage() ~= ref
      end,
      -- `ctx.withList`: the thing's list in the list tile beside its page (Alts' /balts, owner
      -- Forever 07.11.2026: the characters on the left, the character's tabs on the right)
      run = function(ref, ctx)
        local typ = B.Entity.Parse(ref)
        if ctx and ctx.withList and typ and listDef(typ) then
          Browser.List(typ)
        end
        Browser.Open(ref)
      end,
    })
    -- the tooltip hint, only while the Browser is installed (browser.md)
    B:RegisterDetailSection(self, {
      id = "browser.hint",
      title = L["Browser"],
      types = "*",
      order = 999,
      build = function()
        return nil
      end,
      tooltip = {
        max = 1,
        build = function()
          local key = B.Compat.BindingKey(Browser.HOVERED_KEY)
          return key and { { text = string.format(L["%s: open in the Browser"], key) } } or nil
        end,
      },
    })
    self:RegisterEvent("UPDATE_BINDINGS", function()
      B:ForgetTooltipRows() -- the hint names the key
    end)
    self:On("BASTIANS_DATA_LOADED", function(me)
      Browser.ForgetSearch() -- new records: the words find more
      Browser.listCache = {}
      for _, entry in ipairs(history) do
        entry.list = nil -- lists are rebuilt from the new records
      end
      me:Coalesce("rerender", RENDER_DELAY, Browser.Render)
    end)
    self:On("BASTIANS_ENTITY_CHANGED", Browser.Schedule)
    -- a view or list came or went: the navigation follows (ADR 0018)
    self:On("BASTIANS_REGISTRY_CHANGED", Browser.Schedule)
    self:On("BASTIANS_QUESTS_CHANGED", Browser.Schedule)
    self:On("BASTIANS_REWARD_INFO_CHANGED", Browser.Schedule) -- a reward item loaded, gear changed (S7)
    B.UI.Scenery.SetStyle(db().miniMapStyle)
    self:On("BASTIANS_SETTING_CHANGED", function(_, _, name, key)
      if name == "Browser" and key == "miniMapStyle" then
        B.UI.Scenery.SetStyle(db().miniMapStyle)
      end
      if name == "Browser" or key == "mapStyle" then
        Browser.Schedule() -- the worth switch and the like show at once; the mini maps' style too
      end
    end)
    self:On("BASTIANS_PLAYER_MOVED_ZONE", Browser.Schedule) -- Here and the zone page follow the player (C4)
    self:RegisterEvent("PLAYER_TARGET_CHANGED", function()
      Browser.FollowTarget() -- the target becomes the subject (C6)
    end)
    self:On("BASTIANS_PRICES_UPDATED", Browser.Schedule)
    self:On("BASTIANS_GRAPH_TIMES", Browser.Schedule) -- travel times on rows and the card (W8)
    self:On("BASTIANS_THEME_CHANGED", Browser.Schedule) -- the rows' colour codes (ST3)
    self:On("BASTIANS_ACTION_STATE", Browser.Schedule) -- a play button turns into stop and back
    self:On("BASTIANS_TRACKED_CHANGED", Browser.Schedule) -- the card's Track turns into Untrack
    self:On("BASTIANS_ENTITY_FOCUSED", function(_, _, ref, ctx)
      -- a focus from elsewhere (a pin, the omnibox) opens the page while the window is shown; our
      -- own row click opened it already, and a cleared focus (nil) changes nothing here
      if ref and win and win:IsShown() and not (ctx and ctx.source == "browser") then
        Browser.Open(ref)
      end
    end)
    ns.Feed.Register(self) -- the broker displays' feed (ADR 0043)
  end,
  OnDisable = function()
    if win then
      win:Hide()
    end
  end,
})
ns.mod = mod
mod.Browser = Browser

-- The key that opens the page of what is under the mouse (browser.md "The key"): a tooltip cannot be
-- clicked, and a right click on a nameplate or an NPC belongs to the game.
Browser.HOVERED_KEY = "BASTIANS_BROWSER_HOVERED"
BINDING_HEADER_BASTIANS_BROWSER = "Bastian's Browser"
BINDING_NAME_BASTIANS_BROWSER_HOVERED = L["Open what is under the mouse in the Browser"]

function Browser.OpenHovered()
  local ref = B.UI.HoveredRef()
  if not ref or not mod:IsEnabled() then
    return false
  end
  Browser.Open(ref)
  return true
end

SLASH_BASTIANSBROWSER1 = "/bb"
SlashCmdList.BASTIANSBROWSER = function(msg)
  msg = strtrim(msg or "")
  if msg == "" then
    if win and win:IsShown() then
      win:Hide()
    elseif current then
      show(current, false)
    else
      Browser.List("npc")
    end
    return
  end
  if msg == "bookmarks" then
    Browser.Bookmarks()
  elseif listDef(msg) then
    Browser.List(msg)
  elseif listDef(string.gsub(msg, "s$", "")) then
    Browser.List((string.gsub(msg, "s$", "")))
  else
    Browser.Open(msg)
  end
end
