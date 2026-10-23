-- Imagery stage 3 (map.md "Imagery pipeline", ADR 0007): the overview textures of the load-on-demand
-- addon Bastians_Map_Art. Its Generated/Overview.lua (pipeline command `mapart --overview`) registers
-- one texture per `span` x `span` block of ADT tiles (a cell) per continent; the Map draws a cell at
-- the world rectangle of its block through the same layer machinery as the native tiles
-- (Tiles.Draw), below them (sublevel 1) and above the zone art (0). The texture's mip chain gives the
-- low zoom levels, so a whole continent at level 0 is at most 64 cells. The Map loads Map_Art when
-- the window is first built and the setting is on; without it the zone art stays.
local _, ns = ...
local B = Bastians
local L = ns.L
local Map = ns.Map
local Tiles = ns.Tiles

-- ALPHAKEY: the cells carry 1-bit alpha for the sea; blending would mix the land's edge texels with
-- the black of the transparent ones (a dark coast outline, seen 21.10.2026), the alpha test does not.
local Overview = {
  live = {},
  free = {},
  stats = { shown = 0, wanted = 0, skipped = 0 },
  sublevel = 1,
  blend = "ALPHAKEY",
}
ns.Overview = Overview

Overview.ADDON = "Bastians_Map_Art"
Overview.MAX_TEXTURES = 96 -- a continent is at most 64 cells; the margin and a pan add a few
Overview.MARGIN = 1 -- cells beyond the view that are drawn so they are loaded before they scroll in

local tables = {} -- continent -> { [cx * grid + cy] = true }
local masks = {} -- continent -> { [x * 64 + y] = true }: coast tiles with a sea mask
local registered -- what the generated file handed over: { client, span, grid, pixels, path, continents }
local span, grid = 8, 8
local mod
local loadState -- 'loaded' | 'deferred' | 'missing' | 'failed' from the last load attempt

-- ---------------------------------------------------------------------------------------------
-- The table
-- ---------------------------------------------------------------------------------------------

-- Bastians_Map_Art/Generated/Overview.lua calls this once; a table of another client is kept out.
function B.Map.RegisterOverview(info)
  registered = info
  tables, masks = {}, {}
  if type(info) ~= "table" or type(info.continents) ~= "table" then
    return
  end
  if info.client and B.Client and info.client ~= B.Client then
    return
  end
  span = info.span or 8
  grid = info.grid or math.floor(Tiles.GRID / span)
  for continent, keys in pairs(info.continents) do
    local set = {}
    for _, key in ipairs(keys) do
      set[key] = true
    end
    tables[continent] = set
  end
  for continent, keys in pairs(info.masks or {}) do
    local set = {}
    for _, key in ipairs(keys) do
      set[key] = true
    end
    masks[continent] = set
  end
  Tiles.Clear(Tiles) -- live native tiles take their masks when they are drawn again
  if Map.IsShown() then
    Map.ViewChanged()
  end
end

function Overview.Count(continent)
  local tbl = tables[continent]
  if not tbl then
    return 0
  end
  local n = 0
  for _ in pairs(tbl) do
    n = n + 1
  end
  return n
end

function Overview.Key(cx, cy)
  return cx * grid + cy
end

-- The texture path of cell (cx, cy), or nil when the continent has no such cell. No extension: the
-- client finds the .blp (or .tga) itself.
function Overview.File(continent, cx, cy)
  local tbl = tables[continent]
  if not tbl or not tbl[cx * grid + cy] then
    return nil
  end
  return registered.path .. continent .. "_" .. cx .. "_" .. cy
end

-- The sea mask of native tile (x, y), or nil: the native layer masks the coast tile's sea out so
-- the parchment cell underneath shows. Only while the cells are drawn.
function Overview.Mask(continent, x, y)
  local set = masks[continent]
  if not (set and set[x * Tiles.GRID + y] and registered.maskPath and Overview.Enabled()) then
    return nil
  end
  return registered.maskPath .. continent .. "_" .. x .. "_" .. y
end

function Overview.MaskCount(continent)
  local n = 0
  for _ in pairs(masks[continent] or {}) do
    n = n + 1
  end
  return n
end

-- One line for the settings hub.
function Overview.Note()
  if registered and registered.client and B.Client and registered.client ~= B.Client then
    return string.format(
      L["The overview textures were built for %s; zone art is shown at low zoom instead."],
      registered.client
    )
  end
  if not registered then
    if loadState == "missing" then
      return L["Bastian's Map Art is not installed: zone art is shown at low zoom."]
    elseif B.Map.artLoaded then
      return L["Bastian's Map Art has no overview textures: run the pipeline command mapart --overview."]
    elseif loadState == "failed" then
      return L["Bastian's Map Art could not be loaded; zone art is shown at low zoom."]
    end
    return L["Bastian's Map Art loads when the map opens."]
  end
  local ids = {}
  for continent in pairs(tables) do
    ids[#ids + 1] = continent
  end
  table.sort(ids)
  local parts = {}
  for _, continent in ipairs(ids) do
    local n = Overview.Count(continent)
    if n > 0 then
      parts[#parts + 1] = string.format("%s %d", Map.ContinentName(continent) or continent, n)
    end
  end
  return string.format(L["Overview cells: %s"], table.concat(parts, ", "))
end

-- ---------------------------------------------------------------------------------------------
-- Cell math: a cell is `span` x `span` ADT tiles; (cx, cy) = (x / span, y / span) of its tiles.
-- ---------------------------------------------------------------------------------------------

function Overview.CellAt(wx, wy)
  local x, y = Tiles.TileAt(wx, wy)
  return math.floor(x / span), math.floor(y / span)
end

-- World rectangle of cell (cx, cy): wx1 < wx2 (south to north), wy1 < wy2 (east to west).
function Overview.WorldRect(cx, cy)
  local x1, y1 = Tiles.WorldRect(cx * span + span - 1, cy * span + span - 1)
  local _, _, x2, y2 = Tiles.WorldRect(cx * span, cy * span)
  return x1, y1, x2, y2
end

local function clampIndex(v)
  if v < 0 then
    return 0
  elseif v > grid - 1 then
    return grid - 1
  end
  return v
end

-- The continent's cells inside the world rectangle plus `margin` cells around it, nearest the
-- rectangle's centre first: { x, y, key, file, x1, y1, x2, y2, dist }.
function Overview.Visible(continent, wx1, wy1, wx2, wy2, margin)
  local tbl = tables[continent]
  local out = {}
  if not tbl then
    return out
  end
  margin = margin or 0
  local half, t = Tiles.GRID / 2, Tiles.TILE_YARDS * span
  local cx1 = clampIndex(math.floor((half - wy2 / Tiles.TILE_YARDS) / span) - margin)
  local cx2 = clampIndex(math.floor((half - wy1 / Tiles.TILE_YARDS) / span) + margin)
  local cy1 = clampIndex(math.floor((half - wx2 / Tiles.TILE_YARDS) / span) - margin)
  local cy2 = clampIndex(math.floor((half - wx1 / Tiles.TILE_YARDS) / span) + margin)
  local mx, my = (wx1 + wx2) / 2, (wy1 + wy2) / 2
  for cx = cx1, cx2 do
    for cy = cy1, cy2 do
      local key = cx * grid + cy
      if tbl[key] then
        local x1, y1, x2, y2 = Overview.WorldRect(cx, cy)
        local dx, dy = x1 + t / 2 - mx, y1 + t / 2 - my
        out[#out + 1] = {
          x = cx,
          y = cy,
          key = key,
          file = registered.path .. continent .. "_" .. cx .. "_" .. cy,
          x1 = x1,
          y1 = y1,
          x2 = x2,
          y2 = y2,
          dist = dx * dx + dy * dy,
        }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.dist ~= b.dist then
      return a.dist < b.dist
    end
    return a.key < b.key
  end)
  return out
end

-- ---------------------------------------------------------------------------------------------
-- Renderer and loading
-- ---------------------------------------------------------------------------------------------

function Overview.Enabled()
  return mod ~= nil and mod.db.profile.overviewArt ~= false and next(tables) ~= nil
end

function Overview.Render(cam)
  if not Overview.Enabled() then
    Tiles.Clear(Overview)
    return
  end
  local x1, y1, x2, y2 = cam:Bounds()
  Tiles.Draw(
    Overview,
    cam,
    Overview.Visible(cam.continent, x1, y1, x2, y2, Overview.MARGIN),
    Overview.MAX_TEXTURES
  )
end

-- Loads Bastians_Map_Art (load on demand) when the setting is on and it is not registered yet.
-- Compat.LoadAddOn defers the load in combat and calls back afterwards.
function Overview.Load()
  if registered or not mod or mod.db.profile.overviewArt == false then
    return loadState
  end
  local state = B.Compat.LoadAddOn(Overview.ADDON, function()
    loadState = "loaded"
    if Map.IsShown() then
      Map.ViewChanged()
    end
  end)
  loadState = state
  return state
end

ns.mod.Overview = Overview
table.insert(Map.onBuild, function()
  Overview.Load()
end)
table.insert(Map.onView, Overview.Render)
table.insert(Map.onResize, Overview.Render) -- the one layer drawn in full during a resize: few cells, kept
table.insert(Map.onEnable, function(self)
  mod = self
end)
table.insert(Map.onSetting, function(key)
  if key == "overviewArt" then
    Overview.Load()
    Map.ViewChanged()
  end
end)
