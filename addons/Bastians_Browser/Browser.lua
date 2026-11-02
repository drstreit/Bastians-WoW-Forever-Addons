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

-- A list's `type` is its key (the type bar, the saved filters, the cache); `entity` the data type
-- of its records when the two differ (the Mobs list holds NPCs), `keep(r)` the records it takes.
Browser.LISTS = {
  {
    type = "npc",
    label = "NPCs",
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
      RANK_DIM,
      LEVEL_DIM,
    },
  },
  {
    type = "mob",
    entity = "npc",
    label = "Mobs",
    glyph = "mob",
    zoneSuffix = true,
    keep = isMob,
    ref = function(id)
      return "npc:" .. id
    end,
    dims = { RANK_DIM, LEVEL_DIM },
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
    },
  },
  {
    type = "node",
    label = "Nodes",
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
    dims = { LEVEL_DIM },
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
    dims = {
      {
        id = "status",
        title = "Status",
        value = function(r)
          return r.status or "unverified"
        end,
        labels = function(key)
          return L[string.upper(string.sub(key, 1, 1)) .. string.sub(key, 2)]
        end,
      },
    },
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
local syncingFilter -- the filter box follows the entry, nobody typed
local header -- the block above the list: a view's control bar
local dossier -- the detail pane's dossier: the page of the subject (ADR 0018)
local hereDossier -- the Here entry in the list pane: the player's zone in `here` mode (C4)
local nav, navTree -- the navigation pane (ADR 0018 A) and its tree of entries
local listPane, detailPane, splitter -- the list pane, the detail pane and the divider between them
local show -- show(entry, record): the one way an entry gets on screen, defined with the facade below
local NAV_W = 180 -- the navigation's width until the player drags its edge
local NAV_MIN, NAV_MAX = 140, 420
local navGrip -- the navigation's right edge: drag to widen
local LIST_MIN, DETAIL_MIN = 240, 300
local THREE_MIN = 880 -- narrower, the navigation waits behind the Lists button (ADR 0018 E)
local LIST_TAB_W = 18 -- the strip that slides the list out and in
local TOOLBAR_H = 26
-- entries { kind = "page" | "list" | "view" | "home" | "here" | "bookmarks", ref, type, id, text }
local history, cursor = {}, 0
local current -- the entry at the cursor
local shownList -- the entry the list pane shows: the newest that is not a page (ADR 0018)
local previewRef -- the row resting under the mouse, shown in the detail pane (ADR 0018 C)
local hereEntry = { kind = "here" } -- the list pane's entry before any other
local navOpen = false -- the navigation shown over the list in a narrow window
-- The list pane slides: shut by default (the page beside the
-- navigation), out when a category, a view or a search fills it, shut again with its tab.
local listOpen = false
local listFrac = 0 -- how far the list pane is out, 0..1 (animated)
local listSlide -- { from, to, start } while it slides
local listTab, slider
Browser.LIST_SLIDE = 0.18 -- seconds
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
    tree.bar:Show()
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
        local suffix
        if typ == "zone" and r.levelLo and r.levelHi then -- the zone index: band rows (C9)
          suffix = "  " .. S.H.muted .. r.levelLo .. "-" .. r.levelHi .. "|r"
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
  if list.suffixes[i] then
    text = text .. list.suffixes[i]
  end
  return text
end

-- Where a record is, relative to the player (C9): "here" (on the player's map), "continent" (on
-- the player's continent), else "all". Records without a place (items, recipes) are "all".
function Browser.NearOf(typ, id, r, d, map, continent)
  if not map then
    return "all"
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
    return "all"
  end
  if zone == map then
    return "here"
  end
  if continent ~= nil then
    local z = d:Get("zone", zone)
    if z and z.continent == continent then
      return "continent"
    end
  end
  return "all"
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
    for i = 1, list.n do
      low[i] = string.lower(list.names[i] or "")
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
local function renderDetail()
  local ref = previewRef or Browser.PageRef()
  if not ref then
    dossier:Clear()
    return
  end
  dossier:SetTrail(Browser.Trail(), function(item)
    Browser.GoTo(item.index)
  end)
  local sections = B:GetDetailSections(ref)
  dossier:SetSubject(ref, sections, { source = "browser" }, { preview = previewRef ~= nil })
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

-- The level a list opens on (C9): the player's zone when it has rows, else the continent, else
-- everything. Nothing opens empty.
function Browser.DefaultNear(counts)
  local near = counts and counts.near
  if near and near.here > 0 then
    return "here"
  elseif near and near.continent > 0 then
    return "continent"
  end
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
  if entry.sort == "near" and Browser.HasZones(list) then
    -- the zone groups of a Nearest list (ADR 0038): a toggle, remembered per list type
    out[#out + 1] = {
      id = "groups",
      title = L["Groups"],
      choices = { { key = "zone", label = L["By zone"] }, { key = "none", label = L["None"] } },
      active = Browser.GroupsOn(entry) and "zone" or "none",
      default = "zone",
      all = false,
      tip = L["Nearest first, the rows under their zone's name."],
      onSelect = function(key)
        Browser.SetGroups(entry, key ~= "none")
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
  tree:SetFilters(Browser.FilterDims(entry, result))
  tree:SetKeyRow(nil)
  fillGen = fillGen + 1
  local gen = fillGen
  local indexes = result.rows
  local grouped = entry.sort == "near" and Browser.GroupsOn(entry) and Browser.HasZones(list)
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
    if grouped then
      shown = Browser.GroupRows(rows, list, indexes, Browser.ZoneNames(list, indexes))
    else
      shown = {} -- a copy: the loading row below never lands in the rows that grow
      for j, row in ipairs(rows) do
        shown[j] = row
      end
    end
    if #shown == 0 then
      shown = { { text = S.H.muted .. L["No entries. Is the data pack loaded?"] .. "|r", kind = "para" } }
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
    local text = string.format(L["%d of %d shown"], #indexes, result.total)
    if result.total > #indexes then
      text = text .. " - " .. L["narrow with a filter or the search"]
    end
    if loaded < #indexes then
      text = text .. " - " .. string.format(L["%d loaded"], loaded)
    end
    if pending then
      text = text .. " - " .. L["Sorting ..."]
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

-- The zone groups toggle of a list type, remembered in the profile (on by default).
function Browser.GroupsOn(entry)
  local p = db()
  if type(p.listGroups) ~= "table" then
    return true -- nothing chosen yet: on
  end
  return p.listGroups[entry.type] ~= false
end

function Browser.SetGroups(entry, on)
  local p = db()
  if type(p.listGroups) ~= "table" then
    p.listGroups = {}
  end
  p.listGroups[entry.type] = on and nil or false
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
function Browser.GroupRows(rows, list, indexes, names)
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
  if elsewhere then
    out[#out + 1] = elsewhere
  end
  for _, g in ipairs(out) do
    local name = g.zone and names[g.zone] or L["Elsewhere"]
    g.text = tostring(name) .. "  " .. S.H.muted .. #g.children .. "|r"
  end
  return out
end

-- The search home: no list on open, results from
-- the second character through Core's providers, a type word first or last narrows ("npc wel"), the
-- type chips under the box set the type too; with an empty box the home shows "Here", the views,
-- the bookmarks and the recent pages.
local searchHandle
local SEARCH_MIN = 2
local SEARCH_LIMIT = 100
local HOME_RECENT = 8
local homeType -- the chip's type, nil for All (per session)
local homeKeep -- a list's keep rule over the search hits, with its type (Browser.Search)

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

-- The rows of the search home for Core's ranked results: the results whose name starts with the
-- search text first (in rank order), a horizontal rule, then the rest.
-- No rule when one of the two groups is empty.
function Browser.HomeRows(results, query)
  local needle = string.lower(query or "")
  local starts, rest = {}, {}
  for _, r in ipairs(results) do
    local label = r.label or r.ref
    -- one line per result (ADR 0018 B; ~~two lines, ~~ the detail pane shows the
    -- rest on a hover): the icon, the name, the type and what the entity is (level, zone) in grey,
    -- the worth on the right, cut by the row
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
      icon = e:Icon() or (entityType and B.UI.IconTexture(TYPE_GLYPH[entityType] or "other")),
    }
    local name = string.lower(label)
    if needle ~= "" and string.sub(name, 1, #needle) == needle then
      starts[#starts + 1] = row
    else
      rest[#rest + 1] = row
    end
  end
  local rows = starts
  if #starts > 0 and #rest > 0 then
    rows[#rows + 1] = { id = "s:rule", kind = "rule", text = "" }
  end
  for _, row in ipairs(rest) do
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
  homeType, homeKeep = key, nil
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

local function renderHome(text)
  win:SetTitle(L["Search"])
  noHeader()
  tree:SetChips({}, nil, nil)
  if searchHandle then
    searchHandle:Cancel()
    searchHandle = nil
  end
  local query, types = B.ParseSearch(text or "")
  if not types and homeType then
    types = { [homeType] = true } -- the chip is the type word when the text has none
  end
  if #query < SEARCH_MIN then
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
  summary:SetText(L["Searching ..."])
  local entry = shownList
  searchHandle = B:Search(query, { limit = SEARCH_LIMIT, types = types }, function(results, done)
    if shownList ~= entry or not (win and win:IsShown()) then
      return
    end
    if homeKeep then
      local kept, d = {}, data()
      for _, r in ipairs(results) do
        local typ, id = B.Entity.Parse(r.ref)
        local rec = d and typ and d:Get(typ, id) or nil
        if rec and homeKeep(rec) then
          kept[#kept + 1] = r
        end
      end
      results = kept
    end
    local rows = Browser.HomeRows(results, query)
    if #rows == 0 then
      rows[1] =
        { text = S.H.muted .. (done and L["No matches."] or L["Searching ..."]) .. "|r", kind = "para" }
    end
    tree:SetRows(rows)
    markSelected(Browser.ShownPage())
    summary:SetText(done and string.format(L["%d matches"], #results) or L["Searching ..."])
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
  else
    renderBookmarks()
  end
  if not db().slim then
    renderDetail()
    Browser.RenderNav()
  end
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
  if win and win:IsShown() and dossier and not db().slim then
    renderDetail()
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
    if
      db().slim
      or ref == Browser.PageRef()
      or GetTime() - lastWheel < Browser.WHEEL_QUIET
      or not previewAllowed()
    then
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
-- The navigation (ADR 0018 A): Here, the pinned views, the lists, the other views by group, the
-- bookmarks and the recent pages. A row with `nav` changes the list pane, a row with a ref opens
-- its page in the detail pane.
-- ---------------------------------------------------------------------------------------------

local NAV_RECENT = 8

local function entityIcon(ref)
  local entityType = B.Entity.Parse(ref)
  return B:Entity(ref):Icon() or B.UI.IconTexture(entityType and TYPE_GLYPH[entityType] or "other")
end

function Browser.NavRows()
  local rows = {}
  local zone = zoneRef()
  local zoneName = zone and B:Entity(zone):Name()
  rows[1] = {
    id = "nav:here",
    text = zoneName and string.format(L["Here: %s"], zoneName) or L["Here"],
    icon = B.UI.IconTexture("zone"),
    nav = { kind = "here" },
  }
  local groups, order = {}, {}
  for _, def in ipairs(shownViews()) do
    local text = tostring(def.title)
    if def.summary then
      local ok, words = pcall(def.summary)
      if ok and words then
        text = text .. "  " .. S.H.muted .. tostring(words) .. "|r"
      end
    end
    local row = {
      id = "nav:view:" .. def.id,
      text = text,
      icon = def.icon or B.UI.IconTexture(def.pinned and "questActive" or "other"),
      nav = { kind = "view", id = def.id },
    }
    if def.pinned then
      rows[#rows + 1] = row -- My quests, one click away
    else
      local group = tostring(def.group)
      if not groups[group] then
        groups[group] = {}
        order[#order + 1] = group
      end
      local list = groups[group]
      list[#list + 1] = row
    end
  end
  local lists = {}
  for _, def in ipairs(Browser.Lists()) do
    lists[#lists + 1] = {
      id = "nav:list:" .. def.type,
      text = L[def.label],
      icon = B.UI.IconTexture(def.glyph or TYPE_GLYPH[def.type] or "other"),
      nav = { kind = "list", type = def.type },
    }
  end
  rows[#rows + 1] = { id = "nav:lists", kind = "section", text = L["Lists"], children = lists }
  for _, group in ipairs(order) do
    rows[#rows + 1] = { id = "nav:group:" .. group, kind = "section", text = group, children = groups[group] }
  end
  local marks = {}
  for _, ref in ipairs(bookmarks()) do
    marks[#marks + 1] =
      { id = "nav:bm:" .. ref, ref = ref, text = B:Entity(ref):Name() or ref, icon = entityIcon(ref) }
  end
  if #marks > 0 then
    rows[#rows + 1] = { id = "nav:bookmarks", kind = "section", text = L["Bookmarks"], children = marks }
  end
  local recent, seen = {}, {}
  for i = #history, 1, -1 do
    local entry = history[i]
    if entry.kind == "page" and not seen[entry.ref] then
      seen[entry.ref] = true
      recent[#recent + 1] = {
        id = "nav:recent:" .. entry.ref,
        ref = entry.ref,
        text = B:Entity(entry.ref):Name() or entry.ref,
        icon = entityIcon(entry.ref),
      }
      if #recent >= NAV_RECENT then
        break
      end
    end
  end
  if #recent > 0 then
    rows[#rows + 1] = { id = "nav:recent", kind = "section", text = L["Recent"], children = recent }
  end
  return rows
end

-- The navigation row of what the list pane shows (accented), nil for the search and bookmarks.
function Browser.NavActive()
  local entry = shownList or Browser.ListEntry()
  if entry.kind == "here" then
    return "nav:here"
  elseif entry.kind == "list" then
    return "nav:list:" .. tostring(entry.type)
  elseif entry.kind == "view" then
    return "nav:view:" .. tostring(entry.id)
  elseif entry.kind == "home" and homeType then
    return "nav:list:" .. homeType -- the search's type filter
  end
  return nil
end

function Browser.RenderNav()
  if not navTree then
    return
  end
  navTree.selectedID = Browser.NavActive()
  navTree:SetRows(Browser.NavRows())
end

-- A navigation row: Here, a list (the search's type while text is in the box), a view.
function Browser.Navigate(target)
  if target.kind == "here" then
    return Browser.ShowHere()
  elseif target.kind == "list" then
    onTypeChip(target.type)
    return true
  elseif target.kind == "view" then
    return Browser.ShowView(target.id)
  end
  return false
end

-- ---------------------------------------------------------------------------------------------
-- Window: navigation, list and detail (ADR 0018), two panes below THREE_MIN, slim one column
-- ---------------------------------------------------------------------------------------------

-- The list pane's width: remembered in the profile, else about two fifths of what the navigation
-- leaves, never under LIST_MIN and never so wide that the detail falls under DETAIL_MIN.
-- The navigation's width: the player's (dragged at its right edge), else NAV_W (owner, retail
-- 28.10.2026: "Recent" was squeezed to "Qu..." and unreadable).
function Browser.NavWidth()
  local w = tonumber(db().navWidth) or NAV_W
  return math.max(NAV_MIN, math.min(NAV_MAX, w))
end

function Browser.SetNavWidth(width)
  db().navWidth = math.max(NAV_MIN, math.min(NAV_MAX, width))
  Browser.Layout()
end

function Browser.ListWidth()
  local total = (win and win.frame:GetWidth()) or 1000
  local avail = total - 16 - (total >= THREE_MIN and (Browser.NavWidth() + 8) or 0)
  local width = db().listWidth or math.floor(avail * 0.42)
  return math.max(LIST_MIN, math.min(width, avail - DETAIL_MIN))
end

function Browser.SetListWidth(width)
  if width then
    db().listWidth = width
  end
  Browser.Layout()
end

function Browser.IsNarrow()
  return not db().slim and win ~= nil and (win.frame:GetWidth() or 1000) < THREE_MIN
end

-- Places the panes for the window's width and mode.
function Browser.Layout()
  if not win then
    return
  end
  local content = win.content
  local slim = db().slim
  local narrow = Browser.IsNarrow()
  local top = -(TOOLBAR_H + 10)
  if slim then
    toolbar:Hide()
  else
    toolbar:Show()
  end
  toolbar.back:ClearAllPoints()
  if narrow then
    toolbar.lists:Show()
    toolbar.back:SetPoint("LEFT", toolbar.lists, "RIGHT", 4, 0)
  else
    toolbar.lists:Hide()
    toolbar.back:SetPoint("LEFT", toolbar, "LEFT", 0, 0)
  end
  local c = navOpen and S.C.accent or S.C.text
  toolbar.lists.label:SetTextColor(c[1], c[2], c[3])
  nav:ClearAllPoints()
  if slim or (narrow and not navOpen) then
    nav:Hide()
  else
    nav:SetPoint("TOPLEFT", content, "TOPLEFT", 6, top)
    nav:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 6, 6)
    nav:SetWidth(Browser.NavWidth())
    -- over the list in a narrow window, beside it otherwise
    nav:SetFrameLevel(listPane:GetFrameLevel() + (narrow and 20 or 0))
    nav:Show()
  end
  if navGrip then
    navGrip:SetShown(nav:IsShown() and not narrow)
  end
  listPane:ClearAllPoints()
  if slim then
    listPane:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -6)
    listPane:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -6, 6)
    listPane:Show() -- slim is the list alone, whatever the slide (R25.36)
    splitter:Hide()
    detailPane:Hide()
  else
    local left = narrow and 6 or (6 + Browser.NavWidth() + 8)
    detailPane:ClearAllPoints()
    listTab:ClearAllPoints()
    if listFrac > 0 then
      listPane:SetPoint("TOPLEFT", content, "TOPLEFT", left, top)
      listPane:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", left, 6)
      listPane:SetWidth(math.max(1, Browser.ListWidth() * listFrac))
      listPane:Show()
      splitter:Show()
      -- the tab: a strip as high as the panes between the splitter and the page, so the grip
      -- stays free
      listTab:SetPoint("TOPLEFT", splitter, "TOPRIGHT", 0, 0)
      listTab:SetPoint("BOTTOMLEFT", splitter, "BOTTOMRIGHT", 0, 0)
    else
      listPane:Hide()
      splitter:Hide()
      listTab:SetPoint("TOPLEFT", content, "TOPLEFT", left, top)
      listTab:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", left, 6)
    end
    listTab:SetWidth(LIST_TAB_W)
    detailPane:SetPoint("TOPLEFT", listTab, "TOPRIGHT", 4, 0)
    detailPane:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -6, 6)
    detailPane:Show()
    -- the suite's arrow: right slides the list out, left slides it back
    listTab.arrow:SetRotation(listOpen and math.pi or 0)
    listTab.tip = listOpen and L["Slide the list in"] or L["Slide the list out"]
    listTab:Show()
  end
  if slim then
    listTab:Hide()
  end
end

function Browser.IsListOpen()
  return listOpen
end

local function finishSlide()
  listFrac = listSlide.to
  listSlide = nil
  slider:SetScript("OnUpdate", nil) -- no work while nothing moves (CLAUDE.md golden rule 7)
  Browser.Layout()
end

-- Slides the list pane out (open) or in; at once without `animate` or while the window is hidden.
function Browser.SetListOpen(open, animate)
  open = open and true or false
  if open == listOpen and not listSlide then
    return
  end
  listOpen = open
  local to = open and 1 or 0
  local appearing = open and listFrac == 0 -- the pane's content is drawn as it comes into view
  if not (animate and win and win:IsShown() and slider) then
    listSlide = nil
    if slider then
      slider:SetScript("OnUpdate", nil)
    end
    listFrac = to
    Browser.Layout()
    if appearing and win and win:IsShown() then
      Browser.Render()
    end
    return
  end
  listSlide = { from = listFrac, to = to, start = GetTime() }
  if appearing then
    listFrac = 0.01
    Browser.Layout()
    Browser.Render()
  end
  slider:SetScript("OnUpdate", function()
    local t = (GetTime() - listSlide.start) / Browser.LIST_SLIDE
    if t >= 1 then
      finishSlide()
      return
    end
    local eased = 1 - (1 - t) * (1 - t)
    listFrac = listSlide.from + (listSlide.to - listSlide.from) * eased
    Browser.Layout()
  end)
end

-- The Lists button of a narrow window: the navigation over the list, or away again.
function Browser.ToggleNav(on)
  if on == nil then
    on = not navOpen
  end
  navOpen = on and true or false
  Browser.Layout()
  if navOpen then
    Browser.RenderNav()
  end
  return navOpen
end

-- A click on a row with a ref (list, Here, detail): the map rings it and its page opens in the
-- detail pane; a right click opens the entity menu; a row's own onClick wins.
local function rowClick(row, button, owner)
  if row.onClick and button ~= "RightButton" then
    row.onClick(row, button)
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
  win = B.UI.Window("BastiansBrowserFrame", {
    module = "Browser", -- the options button opens this page (R27.1)
    title = L["Browser"],
    width = 1000,
    height = 600,
    minWidth = LIST_MIN + DETAIL_MIN + 30,
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
      if listSlide then
        listSlide = nil
        slider:SetScript("OnUpdate", nil)
      end
      listOpen, listFrac = false, 0 -- the window opens with the list shut (R25.36)
      Browser.Layout()
      Browser.Render()
      Browser.UpdateTracker() -- slim: the game's tracker goes (C8)
    end,
    onHide = function()
      leaveView() -- a view's own frames (Quests' item bar) go with the window ...
      if hereDossier then
        hereDossier:NotifyHide() -- ... and so do the Here entry's (C4)
      end
      previewRef, hovered = nil, nil
      Browser.UpdateTracker() -- the game's tracker comes back (C8)
    end,
    onResize = function()
      if db().slim then
        db().slimWidth = win.frame:GetWidth()
      end
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
  toolbar = CreateFrame("Frame", nil, content)
  Browser.toolbar = toolbar -- for the tests and the tips check
  toolbar:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -6)
  toolbar:SetPoint("TOPRIGHT", content, "TOPRIGHT", -6, -6)
  -- the bar is 26 px with 30 px arrows: the owner wanted Back and Forward prominent (22.10.2026)
  toolbar:SetHeight(TOOLBAR_H)
  -- a narrow window's navigation (ADR 0018 E)
  toolbar.lists = S.action(toolbar, { icon = "buttons", label = L["Lists"], boxed = true, row = true })
  toolbar.lists.tip = function()
    return L["Lists"], L["Here, your quests, the lists, bookmarks and recent pages."]
  end
  toolbar.lists:SetPoint("LEFT", toolbar, "LEFT", 0, 0)
  toolbar.lists:SetScript("OnClick", function()
    Browser.ToggleNav()
  end)
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
  search = S.search(toolbar, L["Search: a name, or a type first (npc wel)"])
  search.queryFields = L["type (npc, item, quest, zone, ...)"] -- the world search's (ADR 0045)
  search:SetPoint("LEFT", toolbar.forward, "RIGHT", 8, 0)
  search:SetPoint("RIGHT", toolbar, "RIGHT", 0, 0)
  -- the keys (ADR 0038): while the box has focus, Up and Down move a lit row through the list,
  -- Enter opens it, Escape clears the box; the rows take no keys of their own
  search:SetScript("OnKeyDown", function(_, key)
    if key == "DOWN" or key == "UP" then
      Browser.MoveKeyRow(key == "DOWN" and 1 or -1)
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
      Browser.SetListOpen(true, true) -- the results show in the list (R25.36)
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
      -- typing anywhere searches the world; on a list the search
      -- keeps its type: the data type of its records, narrowed by its keep rule (owner, retail
      -- 31.10.2026: "wolf" on Mobs found nothing, no provider knows "mob")
      local def = entry.kind == "list" and listDef(entry.type) or nil
      Browser.Search(
        text,
        entry.kind == "list" and (def and def.entity or entry.type) or nil,
        def and def.keep or nil
      )
    end
  end)

  -- the navigation (ADR 0018 A): a tree of entries, its folds remembered
  nav = CreateFrame("Frame", nil, content)
  S.panel(nav, S.C.panel)
  S.inset(nav) -- the game's inset under its frames
  -- the navigation's right edge: a grip as the list's splitter, dragging widens the navigation
  navGrip = CreateFrame("Frame", nil, content)
  navGrip:SetWidth(8)
  navGrip:SetPoint("TOPLEFT", nav, "TOPRIGHT", 0, 0)
  navGrip:SetPoint("BOTTOMLEFT", nav, "BOTTOMRIGHT", 0, 0)
  navGrip.line = S.fill(navGrip, S.C.line)
  navGrip.line:ClearAllPoints()
  navGrip.line:SetPoint("TOP", 0, 0)
  navGrip.line:SetPoint("BOTTOM", 0, 0)
  navGrip.line:SetWidth(1)
  navGrip:EnableMouse(true)
  navGrip:SetScript("OnEnter", function(bar)
    S.tint(bar.line, S.C.accent, 0.8)
    bar.line:SetWidth(2)
  end)
  navGrip:SetScript("OnLeave", function(bar)
    S.tint(bar.line, S.C.line)
    bar.line:SetWidth(1)
  end)
  navGrip:SetScript("OnMouseDown", function(bar)
    bar:SetScript("OnUpdate", function(me)
      local x = GetCursorPosition() / (me:GetEffectiveScale() or 1)
      local left = nav:GetLeft()
      if left then
        Browser.SetNavWidth(x - left - 4)
      end
    end)
  end)
  navGrip:SetScript("OnMouseUp", function(bar)
    bar:SetScript("OnUpdate", nil) -- follows only while the button is held
  end)
  Browser.navGrip = navGrip
  navTree = B.UI.Tree(nav, {
    db = db().nav,
    worth = false,
    ctx = { source = "browser" },
    onClick = function(row, button, owner)
      if row.nav then
        Browser.SetListOpen(true, true) -- a category: the list slides out and loads (R25.36)
        Browser.Navigate(row.nav)
        if navOpen then
          Browser.ToggleNav(false)
        end
      else
        rowClick(row, button, owner)
      end
    end,
  })
  navTree.scroll:ClearAllPoints()
  navTree.scroll:SetPoint("TOPLEFT", nav, "TOPLEFT", 4, -4)
  navTree.scroll:SetPoint("BOTTOMRIGHT", nav, "BOTTOMRIGHT", -14, 4)

  -- the list pane: a view's control bar, the summary, the filter bar and the rows (the tree), or
  -- the Here entry (the player's zone as a dossier)
  listPane = CreateFrame("Frame", nil, content)
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
  tree = B.UI.Tree(listPane, {
    db = db().tree,
    twoLine = true, -- rows with `meta` (views: My quests) take two lines; list rows have none
    worth = Browser.ShowWorth,
    ctx = { source = "browser" },
    onHover = Browser.OnRowHover,
    onClick = rowClick,
  })
  tree.chips:ClearAllPoints()
  tree.chips:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", -2, -4)
  tree.chips:SetPoint("TOPRIGHT", summary, "BOTTOMRIGHT", -12, -4)
  tree.scroll:HookScript("OnMouseWheel", Browser.OnListWheel)
  tree.scroll:ClearAllPoints()
  tree.scroll:SetPoint("TOPLEFT", tree.chips, "BOTTOMLEFT", 0, -2)
  tree.scroll:SetPoint("BOTTOMRIGHT", listPane, "BOTTOMRIGHT", -14, 0)
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
  hereDossier.frame:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", -2, -4)
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

  -- the list's tab: slides it out and in (R25.36)
  -- as high as the panes, the arrow in its middle; hover lights the strip
  listTab = CreateFrame("Button", nil, content)
  listTab:SetWidth(LIST_TAB_W)
  listTab:SetFrameLevel((splitter:GetFrameLevel() or 1) + 5)
  S.panel(listTab, S.C.panel)
  listTab.arrow = listTab:CreateTexture(nil, "ARTWORK")
  listTab.arrow:SetTexture(S.ARROW)
  listTab.arrow:SetSize(14, 14)
  listTab.arrow:SetPoint("CENTER")
  S.tint(listTab.arrow, S.C.accent)
  listTab:SetScript("OnClick", function()
    Browser.SetListOpen(not listOpen, true)
  end)
  listTab:SetScript("OnEnter", function(tab)
    S.tint(tab.bg, S.C.faceHover)
    S.setEdges(tab.edges, S.C.accent, 0.8)
    tab.arrow:SetSize(18, 18)
    S.TipEnter(tab)
  end)
  listTab:SetScript("OnLeave", function(tab)
    S.tint(tab.bg, S.C.panel)
    S.setEdges(tab.edges, S.C.line)
    tab.arrow:SetSize(14, 14)
    S.TipLeave(tab)
  end)
  listPane:SetClipsChildren(true) -- the rows show as the pane slides out
  slider = CreateFrame("Frame", nil, content)

  -- the detail pane: the dossier of the kept page or the preview (ADR 0018)
  detailPane = CreateFrame("Frame", nil, content)
  S.inset(detailPane)
  detailPane:SetPoint("TOPLEFT", splitter, "TOPRIGHT", 4, 0)
  detailPane:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -6, 6)
  dossier = B.UI.Dossier(detailPane, {
    iconsAlways = true,
    portrait = true, -- the 3D model of a creature or a wearable item
    stats = true, -- the stats strip under the band (ADR 0038)
    worth = Browser.ShowWorth,
    ctx = { source = "browser" },
    buttons = Browser.BandButtons,
    onClick = rowClick,
  })

  -- the Slim / Wide toggle in the title bar (C8)
  toolbar.slim = S.action(win.head, { icon = "undock", label = L["Slim"], row = true })
  toolbar.slim.tip = function()
    local text = "Slim keeps only your quests (the tracker) in a narrow window and hides the"
      .. " game's quest tracker; Wide brings the lists and the page back."
    return L["Slim or wide"], L[text]
  end
  -- left of the window's options button
  toolbar.slim:SetPoint("RIGHT", win.options or win.close, "LEFT", -4, 0)
  toolbar.slim:SetScript("OnClick", function()
    Browser.ToggleSlim()
  end)
  -- Dock beside the map (ADR 0013 E) lives in the title bar too, so slim mode has it
  --
  toolbar.dock = S.action(win.head, { icon = "dock", label = L["Dock"], row = true })
  toolbar.dock.tip = function()
    return L["Dock to the map"],
      L["The window sits beside the map at its height and moves with it. Click again to undock."]
  end
  toolbar.dock:SetPoint("RIGHT", toolbar.slim, "LEFT", -4, 0)
  toolbar.dock:SetScript("OnClick", function()
    B.UI.ToggleDock()
    Browser.UpdateDock()
  end)

  self.win, self.tree, self.toolbar, self.summary, self.search = win, tree, toolbar, summary, search
  self.filterBox = filterBox
  self.header, self.controlBar, self.dossier, self.hereDossier = header, controlBar, dossier, hereDossier
  self.nav, self.navTree, self.listPane, self.detailPane = nav, navTree, listPane, detailPane
  self.listTab = listTab
  self.splitter = splitter
  Browser.Layout()
  if db().slim then
    Browser.SetSlim(true, true) -- the mode comes back with the profile
  end
end

-- Target follow (C6): with the setting on and the window shown, an NPC or object the player
-- targets becomes the subject; never in combat lockdown (nothing secure is touched, the rule keeps
-- the window quiet in fights); players give no entity and are ignored.
function Browser.FollowTarget()
  if not (mod and win and win:IsShown() and db().followTarget) or db().slim then
    return false -- the tracker stays the tracker while slim
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

-- ---------------------------------------------------------------------------------------------
-- Slim mode (C8): the log alone as the on-screen tracker; the game's objective tracker
-- hidden meanwhile (setting, out of combat only), back when the window widens or hides
-- ---------------------------------------------------------------------------------------------

local SLIM_DEFAULT = 260
local slimPrevious -- the entry shown before slim mode, back with Wide
-- The tracker follows the state: hidden while the window is shown slim and the setting says so.
-- Since R6 (22.10.2026) the claim goes through Core (`Bastians.UI.ClaimGameTracker`, shared with
-- Quests' tracker frame), which also keeps the wish through combat.
function Browser.UpdateTracker()
  local hide = db().slim and db().hideTracker ~= false and win ~= nil and win:IsShown()
  B.UI.ClaimGameTracker("browser-slim", hide and true or false)
end

function Browser.IsSlim()
  return db().slim == true
end

-- Slim: the window narrows to the list pane alone with the log view (its width remembered as
-- `slimWidth`), the navigation, the detail and the toolbar hide; wide: the remembered size and
-- the entry shown before come back.
local SLIM_MIN = 220
function Browser.SetSlim(on, silent)
  if not win then
    build(mod)
  end
  local p = db()
  on = on and true or false
  if on and not p.slim then
    p.wideSize = { win.frame:GetWidth(), win.frame:GetHeight() }
  end
  p.slim = on
  if on then
    -- the tracker (slim is "my open quests", what replaces the game's
    -- tracker): the log view alone in a narrow window
    local width = p.slimWidth or SLIM_DEFAULT
    if not (current and current.kind == "view" and current.id == "quests.log") then
      slimPrevious = current
    end
    previewRef = nil
    win.frame:SetResizeBounds(SLIM_MIN, 240, 1200, 1200)
    win.frame:SetWidth(width)
    Browser.Layout()
    if B:GetView("quests.log") then
      show({ kind = "view", id = "quests.log", args = {} }, false)
    end
  else
    local size = p.wideSize
    win.frame:SetResizeBounds(LIST_MIN + DETAIL_MIN + 30, 240, 1600, 1200)
    if size then
      win.frame:SetSize(size[1], size[2])
      p.window.size = { size[1], size[2] }
    end
    Browser.Layout()
    if slimPrevious and win:IsShown() then
      show(slimPrevious, false)
      slimPrevious = nil
    end
  end
  if toolbar and toolbar.slim then
    toolbar.slim.label:SetText(on and L["Wide"] or L["Slim"])
  end
  Browser.UpdateTracker()
  if not silent then
    if hereDossier then
      hereDossier:Refresh()
    end
    if dossier then
      dossier:Refresh()
    end
    if win:IsShown() then
      Browser.Render()
    end
  end
  return on
end

function Browser.ToggleSlim()
  return Browser.SetSlim(not db().slim)
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
  if win:IsShown() then
    Browser.Render()
  else
    win:Show() -- onShow renders
  end
  if entry.kind == "page" then
    mod:Fire("BASTIANS_PAGE_SHOWN", entry.ref) -- the map follows with Follow on (ADR 0013 D)
  end
end

-- The world search for `text`, filtered by a type (`typ`, nil keeps the current filter, false
-- clears it): a search entry in the list pane with the text in the box. Back returns to where it
-- was typed; the detail keeps its page.
function Browser.Search(text, typ, keep)
  if not (mod and mod:IsEnabled()) then
    return false
  end
  if typ ~= nil then
    homeType = typ or nil
    homeKeep = keep -- a list's keep rule over the hits (Mobs: the NPCs without a service)
  end
  local entry = Browser.ListEntry()
  if entry.kind == "home" and win and win:IsShown() and shownList == entry then
    entry.text = text
    syncSearchBox(entry)
    renderHome(text)
    Browser.RenderNav()
  else
    show({ kind = "home", text = text })
  end
  return true
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
  if db().slim and win then
    Browser.SetSlim(false) -- a page needs the wide window: a tracker row click widens it
  end
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
      nav = {}, -- the navigation's folds (ADR 0018)
      followTarget = true,
      hideTracker = true,
      slim = false,
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
      type = "toggle",
      key = "hideTracker",
      label = L["Hide the game's objective tracker in slim mode"],
      default = true,
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
      Slim = function(_, on) -- slim mode (C8): the log alone; nil toggles
        Browser.OpenWindow()
        if on == nil then
          return Browser.ToggleSlim()
        end
        return Browser.SetSlim(on)
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
      run = function(ref)
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
          return { { text = L["Right click: open in the Browser"] } }
        end,
      },
    })
    self:On("BASTIANS_DATA_LOADED", function(me)
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
    self:On("BASTIANS_SETTING_CHANGED", function(_, _, name)
      if name == "Browser" then
        Browser.Schedule() -- the worth switch and the like show at once
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
