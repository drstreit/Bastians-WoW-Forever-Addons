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

local LEVEL_DIM = {
  id = "level",
  title = "Level",
  value = function(r)
    return band(r.level)
  end,
  sortKey = bandOrder,
}

Browser.LISTS = {
  {
    type = "npc",
    label = "NPCs",
    zoneSuffix = true, -- a repeated name says its zone
    dims = {
      {
        id = "service",
        title = "Service",
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
      {
        id = "rank",
        title = "Rank",
        value = function(r, d)
          for _, flag in ipairs(npcFlags(r)) do
            if RANKS[flag] then
              return kindGroup(d, "npc", flag) or "Other"
            end
          end
          return "Normal"
        end,
      },
      LEVEL_DIM,
    },
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
    }
  end
  for _, f in ipairs(B:GetFilters(def.type, "facet")) do
    dims[#dims + 1] = {
      id = f.id,
      title = f.label,
      value = function(r, _, ref)
        return B:FilterValue(f, ref, r)
      end,
      labels = f.labels,
    }
  end
  return dims
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
local header -- the block above the list: a view's control bar
local dossier -- the detail pane's dossier: the page of the subject (ADR 0018)
local hereDossier -- the Here entry in the list pane: the player's zone in `here` mode (C4)
local nav, navTree -- the navigation pane (ADR 0018 A) and its tree of entries
local listPane, detailPane, splitter -- the list pane, the detail pane and the divider between them
local show -- show(entry, record): the one way an entry gets on screen, defined with the facade below
local NAV_W = 180
local LIST_MIN, DETAIL_MIN = 240, 300
local THREE_MIN = 880 -- narrower, the navigation waits behind the Lists button (ADR 0018 E)
local TOOLBAR_H = 26
-- entries { kind = "page" | "list" | "view" | "home" | "here" | "bookmarks", ref, type, id, text }
local history, cursor = {}, 0
local current -- the entry at the cursor
local shownList -- the entry the list pane shows: the newest that is not a page (ADR 0018)
local previewRef -- the row resting under the mouse, shown in the detail pane (ADR 0018 C)
local hereEntry = { kind = "here" } -- the list pane's entry before any other
local navOpen = false -- the navigation shown over the list in a narrow window
local listJob

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

local ROW_DIMS = 8 -- a build row: id, name, (unused), near, level, suffix, yards, ref, then the dims

-- Builds the rows of a type list; `yield` between slices. Returns the list (compact arrays, every
-- row), counts ({ near = { here, continent }, distances, default }) and the total.
function Browser.BuildList(typ, yield)
  local def = listDef(typ)
  local d = data()
  if not (def and d) then
    return { type = typ, n = 0, dims = {}, values = {} }, {}, 0
  end
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
    if r then
      local instance = def.mergeInstances and r.mapType == UI_MAP_DUNGEON and r.name
      if instance and merged[instance] then
        floors[merged[instance]] = floors[merged[instance]] + 1
      else
        total = total + 1
        -- the name as the pack holds it (one string, shared), the level as a number, a band or
        -- floors suffix only where one exists: the row text is composed for the rows shown
        local name = r.name or (typ .. " " .. tostring(id))
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
        local row = { id, name, false, where, r.level, suffix, dist, ref }
        for k, dim in ipairs(dims) do
          row[ROW_DIMS + k] = facetKey(dim.value(r, d, ref or (typ .. ":" .. tostring(id))))
        end
        rows[#rows + 1] = row
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
    type = typ,
    n = #rows,
    dims = dims,
    ids = {},
    names = {},
    values = {},
    nears = {},
    levels = {},
    suffixes = {},
    dists = {},
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
    list.levels[i], list.suffixes[i], list.dists[i] = row[5], row[6], row[7]
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

-- The text of a list row: the name, the level or the band or the floors in grey.
function Browser.ListText(list, i)
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

local function matches(value, want)
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
    want[k] = picks[dim.id]
  end
  local near = state.near
  local nearCounts = out.near
  for kk = 1, list.n do
    local i = order and order[kk] or kk
    local where = list.nears[i]
    local fails, failed = 0, nil
    if not nearOk(near, where) then
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
  return out
end

-- The glyph of a list row (ADR 0018 B), from the list's own facet values, so no record is decoded:
-- an NPC by its first service or its rank, an object or a node by its kind, the rest by type.
local TYPE_GLYPH = {
  npc = "mob",
  item = "item",
  object = "other",
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
  local typ = list.type
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
  for _, row in ipairs(tree.rows or {}) do
    if row.ref ~= nil and row.ref == ref then
      id = row.id
      break
    end
  end
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
  if cached and cached.map == map then -- the near levels and the default facet are per zone
    entry.list, entry.counts, entry.total = cached.list, cached.counts, cached.total
    Browser.ShowList(entry)
    return
  end
  tree:SetFilters({})
  tree:SetRows({ { text = S.H.muted .. L["Building the list ..."] .. "|r", kind = "para" } })
  summary:SetText(L["Building the list ..."])
  if listJob then
    listJob:Cancel()
  end
  listJob = B.Jobs:Run(mod, "browser-list-" .. typ, function(yield)
    local list, counts, total = Browser.BuildList(typ, yield)
    entry.list, entry.counts, entry.total = list, counts, total
    Browser.listCache[typ] = { list = list, counts = counts, total = total, map = map }
  end, {
    onDone = function()
      listJob = nil
      if shownList ~= entry or not (win and win:IsShown()) then
        return
      end
      Browser.ShowList(entry)
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
    picks[k] = v
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
      entry.picks[k] = v
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
  for _, f in ipairs(B:GetFilters(list.type, "sort")) do
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
      local ref = list.refs and list.refs[i] or (list.type .. ":" .. tostring(list.ids[i]))
      local r
      if ldef and ldef.record then -- a registered list's own record (a chain)
        r = ldef.record(list.ids[i])
      else
        r = d and d:Get(list.type, list.ids[i]) or nil
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
  if active ~= nil and counts[active] == nil then -- a choice with no rows left stays visible
    choices[#choices + 1] =
      { key = active, label = dim.labels and dim.labels(active) or L[active], count = 0 }
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
    -- a dimension whose rows all share one key (retail objects have no kinds, retail quests no
    -- levels) shows no pill, unless a remembered choice is on it
    if active ~= nil or not list.distinct or (list.distinct[k] or 0) >= 2 then
      out[#out + 1] = {
        id = dim.id,
        title = L[dim.title],
        choices = choicesOf(dim, result.counts[k] or {}, active),
        active = active,
        all = { label = L["All"], count = result.all[k] },
        onSelect = function(key)
          entry.picks[dim.id] = key
          Browser.SaveFilters(entry)
          Browser.ShowList(entry)
        end,
      }
    end
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
    return nearOrder(list),
      function(i)
        return list.dists[i] and B.UI.Distance(list.dists[i]) or nil
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
  local rows = rowsOf(list, result.rows, words)
  if #rows == 0 then
    rows = { { text = S.H.muted .. L["No entries. Is the data pack loaded?"] .. "|r", kind = "para" } }
    if list.n > 0 then
      rows[1].text = S.H.muted .. L["Nothing matches these filters. The x on a filter clears it."] .. "|r"
    end
  end
  tree:SetRows(rows)
  markSelected(Browser.ShownPage())
  local text = string.format(L["%d of %d shown"], #result.rows, result.total)
  if result.total > #result.rows then
    text = text .. " - " .. L["narrow with a filter or the search"]
  end
  if pending then
    text = text .. " - " .. L["Sorting ..."]
  end
  summary:SetText(text)
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

local function typeTag(ref)
  local entityType = B.Entity.Parse(ref)
  return entityType and ("  " .. S.H.muted .. L[entityType] .. "|r") or ""
end

function Browser.HomeType()
  return homeType
end

-- The rows of the home with an empty box: the registered views by group (My quests, All quests,
-- ...), the bookmarks, the recent pages. The player's zone is the Here column since C4.
function Browser.IdleRows()
  local rows = {}
  local groups, order = {}, {}
  for _, def in ipairs(B:GetViews()) do
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
  Browser.Show({ kind = "view", id = id, args = args or {} })
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
    if entry.list then
      local def = listDef(entry.type)
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
-- ends a preview.
function Browser.OnRowHover(row, entering)
  if entering and row and row.ref then
    local ref = row.ref
    hovered = ref
    if db().slim or ref == Browser.PageRef() then
      return
    end
    mod:Coalesce("preview", S.TipDelay() or 1, function()
      if hovered == ref and win and win:IsShown() then
        Browser.Preview(ref)
      end
    end)
  else
    hovered = nil
    if previewRef then
      Browser.Preview(nil)
    end
  end
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
  for _, def in ipairs(B:GetViews()) do
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
function Browser.ListWidth()
  local total = (win and win.frame:GetWidth()) or 1000
  local avail = total - 16 - (total >= THREE_MIN and (NAV_W + 8) or 0)
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
    nav:SetWidth(NAV_W)
    -- over the list in a narrow window, beside it otherwise
    nav:SetFrameLevel(listPane:GetFrameLevel() + (narrow and 20 or 0))
    nav:Show()
  end
  listPane:ClearAllPoints()
  if slim then
    listPane:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -6)
    listPane:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -6, 6)
    splitter:Hide()
    detailPane:Hide()
  else
    local left = narrow and 6 or (6 + NAV_W + 8)
    listPane:SetPoint("TOPLEFT", content, "TOPLEFT", left, top)
    listPane:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", left, 6)
    listPane:SetWidth(Browser.ListWidth())
    splitter:Show()
    detailPane:Show()
  end
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
  toolbar.lists = S.button(toolbar, L["Lists"], 46, 22) -- a narrow window's navigation (ADR 0018 E)
  toolbar.lists.tip = function()
    return L["Lists"], L["Here, your quests, the lists, bookmarks and recent pages."]
  end
  toolbar.lists:SetPoint("LEFT", toolbar, "LEFT", 0, 0)
  toolbar.lists:SetScript("OnClick", function()
    Browser.ToggleNav()
  end)
  toolbar.back = S.button(toolbar, "<", 30, TOOLBAR_H)
  toolbar.back.tip = function()
    return L["Back"], L["The page before. Also: hold the right mouse button and drag to the left."]
  end
  S.setSize(toolbar.back.label, 16)
  toolbar.back:SetPoint("LEFT", toolbar, "LEFT", 0, 0)
  toolbar.back:SetScript("OnClick", function()
    Browser.Back()
  end)
  toolbar.forward = S.button(toolbar, ">", 30, TOOLBAR_H)
  toolbar.forward.tip = function()
    return L["Forward"], L["The page after. Also: hold the right mouse button and drag to the right."]
  end
  S.setSize(toolbar.forward.label, 16)
  toolbar.forward:SetPoint("LEFT", toolbar.back, "RIGHT", 2, 0)
  toolbar.forward:SetScript("OnClick", function()
    Browser.Forward()
  end)
  toolbar.target = S.button(toolbar, L["Target"], 54, 22) -- target follow (C6)
  toolbar.target.tip = function()
    local text = "While on (accented), the page shows what you target in the world: click an NPC"
      .. " or an object, and its page opens here. Never in combat, never for players. Click to"
      .. " turn it on or off."
    return L["Follow your target"], L[text]
  end
  toolbar.target:SetPoint("RIGHT", toolbar, "RIGHT", 0, 0)
  toolbar.target:SetScript("OnClick", function()
    Browser.ToggleTarget()
  end)
  Browser.UpdateTarget()
  -- the search box fills the bar between the arrows and Target; typing searches the world
  search = S.search(toolbar, L["Search: a name, or a type first (npc wel)"])
  search:SetPoint("LEFT", toolbar.forward, "RIGHT", 8, 0)
  search:SetPoint("RIGHT", toolbar.target, "LEFT", -6, 0)
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
    local entry = shownList or Browser.ListEntry()
    if entry.kind == "home" then
      entry.text = text
      renderHome(text) -- the search entry searches as you type
    elseif text ~= "" then
      -- typing anywhere searches the world; on a list the search
      -- keeps its type
      Browser.Search(text, entry.kind == "list" and entry.type or nil)
    end
  end)

  -- the navigation (ADR 0018 A): a tree of entries, its folds remembered
  nav = CreateFrame("Frame", nil, content)
  S.panel(nav, S.C.panel)
  navTree = B.UI.Tree(nav, {
    db = db().nav,
    worth = false,
    ctx = { source = "browser" },
    onClick = function(row, button, owner)
      if row.nav then
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
  header = CreateFrame("Frame", nil, listPane)
  header:SetPoint("TOPLEFT", listPane, "TOPLEFT", 0, 0)
  header:SetPoint("TOPRIGHT", listPane, "TOPRIGHT", 0, 0)
  header:SetHeight(1)
  controlBar = Widgets.ControlBar(header)
  controlBar:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
  controlBar:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
  controlBar:Hide()
  summary = S.text(listPane, 11, S.C.dim)
  summary:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 2, -4)
  summary:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -2, -4)
  summary:SetHeight(14)
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

  -- the detail pane: the dossier of the kept page or the preview (ADR 0018)
  detailPane = CreateFrame("Frame", nil, content)
  detailPane:SetPoint("TOPLEFT", splitter, "TOPRIGHT", 4, 0)
  detailPane:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -6, 6)
  dossier = B.UI.Dossier(detailPane, {
    iconsAlways = true,
    worth = Browser.ShowWorth,
    ctx = { source = "browser" },
    buttons = Browser.BandButtons,
    onClick = rowClick,
  })

  -- the Slim / Wide toggle in the title bar (C8)
  toolbar.slim = S.button(win.head, L["Slim"], 44, 20)
  toolbar.slim.tip = function()
    local text = "Slim keeps only your quests (the tracker) in a narrow window and hides the"
      .. " game's quest tracker; Wide brings the lists and the page back."
    return L["Slim or wide"], L[text]
  end
  toolbar.slim:SetPoint("RIGHT", win.close, "LEFT", -4, 0)
  toolbar.slim:SetScript("OnClick", function()
    Browser.ToggleSlim()
  end)
  -- Dock beside the map (ADR 0013 E) lives in the title bar too, so slim mode has it
  --
  toolbar.dock = S.button(win.head, L["Dock"], 46, 20)
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
  self.header, self.controlBar, self.dossier, self.hereDossier = header, controlBar, dossier, hereDossier
  self.nav, self.navTree, self.listPane, self.detailPane = nav, navTree, listPane, detailPane
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

-- The toolbar's Target toggle mirrors the setting (accented while on).
function Browser.UpdateTarget()
  local b = toolbar and toolbar.target
  if not b then
    return
  end
  local on = db().followTarget
  local c = on and S.C.accent or S.C.dim
  b.label:SetTextColor(c[1], c[2], c[3])
  S.setEdges(b.edges, on and S.C.accent or S.C.line, on and 0.8 or nil)
end

function Browser.ToggleTarget()
  db().followTarget = not db().followTarget
  Browser.UpdateTarget()
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
function Browser.Search(text, typ)
  if not (mod and mod:IsEnabled()) then
    return false
  end
  if typ ~= nil then
    homeType = typ or nil
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
  show({ kind = "here" })
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
    Browser.OpenWindow()
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
  },
  OnEnable = function(self)
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
