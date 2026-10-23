-- Imagery stage 2 (map.md, ADR 0007 primary path): the client's native minimap tiles drawn from the
-- generated table Generated/MinimapTiles.lua (pipeline command `mapart`), one 533.33 yard ADT tile
-- per texture, from Tiles.MIN_LEVEL on. A tile is loaded by the path World\Minimaps\<dir>\map<x>_<y>
-- (the form P5 proved on Forever) and by its FileDataID when the path is refused. The tile math
-- (TileAt, WorldRect, Visible) is pure. The tile layer machinery (Tiles.Draw, Tiles.Clear,
-- Tiles.Reposition) keys textures by tile so a tile in view keeps its texture across pans, pools
-- them with a cap and draws above the zone art, which stays as the fallback underneath;
-- Overview.lua reuses it for the Map_Art cells.
local _, ns = ...
local B = Bastians
local L = ns.L
local Map = ns.Map

local Tiles = {}
ns.Tiles = Tiles
B.Map = B.Map or {} -- the hook the generated file calls (data.md does the same for packs)

Tiles.TILE_YARDS = 1600 / 3 -- one ADT tile is 533.33 yards; the 64 x 64 grid is centred on the origin
Tiles.GRID = 64
Tiles.MIN_LEVEL = 3 -- native tiles from this level on (a 512 px tile is 133 px at level 3, 1:1 at level 5)
Tiles.MAX_TEXTURES = 300 -- live tile textures (map.md budget: about 300 for all imagery)
Tiles.MARGIN = 1 -- tiles beyond the view that are drawn so they are loaded before they scroll in

local tables = {} -- continent -> { [x * 64 + y] = fileDataID }
local directories = {} -- continent -> map directory ("Azeroth"), the folder under World\Minimaps
local registered -- what the generated file handed over: { client, continents }
Tiles.PATH_PREFIX = "World\\Minimaps\\"
local parent, mod
local live = {} -- tile key -> texture showing that tile
local free = {} -- textures not in use
Tiles.live, Tiles.free = live, free
Tiles.stats = { shown = 0, wanted = 0, skipped = 0 }

-- ---------------------------------------------------------------------------------------------
-- The table
-- ---------------------------------------------------------------------------------------------

-- Generated/MinimapTiles.lua calls this once; the table of another client is kept out.
function B.Map.RegisterTiles(info)
  registered = info
  tables, directories = {}, {}
  if type(info) ~= "table" or type(info.continents) ~= "table" then
    return
  end
  if info.client and B.Client and info.client ~= B.Client then
    return
  end
  for continent, entry in pairs(info.continents) do
    if type(entry.tiles) == "table" then
      tables[continent] = entry.tiles
      directories[continent] = entry.directory
    else
      tables[continent] = entry -- the table form before 22.10.2026: ids only, no path
    end
  end
  if Map.IsShown() then
    Map.ViewChanged()
  end
end

function Tiles.Count(continent)
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

function Tiles.File(continent, x, y)
  local tbl = tables[continent]
  return tbl and tbl[x * Tiles.GRID + y] or nil
end

function Tiles.Directory(continent)
  return directories[continent]
end

-- The texture path of tile (x, y) without extension (the client finds the .blp), or nil when the
-- continent's map directory is unknown.
function Tiles.Path(continent, x, y)
  local dir = directories[continent]
  if not dir then
    return nil
  end
  return Tiles.PATH_PREFIX .. dir .. "\\map" .. x .. "_" .. y
end

-- One line for the settings hub: what the table holds, or why there is none.
function Tiles.Note()
  if not registered then
    return L["No minimap tile table: run the pipeline command mapart (map.md). Zone art is shown instead."]
  end
  if registered.client and B.Client and registered.client ~= B.Client then
    return string.format(
      L["The minimap tile table was built for %s; zone art is shown instead."],
      registered.client
    )
  end
  local ids = {}
  for continent in pairs(tables) do
    ids[#ids + 1] = continent
  end
  table.sort(ids)
  local parts = {}
  for _, continent in ipairs(ids) do
    local n = Tiles.Count(continent)
    if n > 0 then
      parts[#parts + 1] = string.format("%s %d", Map.ContinentName(continent) or continent, n)
    end
  end
  return string.format(L["Minimap tiles: %s"], table.concat(parts, ", "))
end

-- ---------------------------------------------------------------------------------------------
-- Tile math (coordinates.md): column x grows east (falling wy), row y grows south (falling wx);
-- the corner of tile (32, 32) is the world origin.
-- ---------------------------------------------------------------------------------------------

function Tiles.Key(x, y)
  return x * Tiles.GRID + y
end

-- The tile a world point lies in.
function Tiles.TileAt(wx, wy)
  local half, t = Tiles.GRID / 2, Tiles.TILE_YARDS
  return math.floor(half - wy / t), math.floor(half - wx / t)
end

-- World rectangle of tile (x, y): wx1 < wx2 (south to north), wy1 < wy2 (east to west).
function Tiles.WorldRect(x, y)
  local half, t = Tiles.GRID / 2, Tiles.TILE_YARDS
  local wx2, wy2 = (half - y) * t, (half - x) * t
  return wx2 - t, wy2 - t, wx2, wy2
end

local function clampIndex(v)
  if v < 0 then
    return 0
  elseif v > Tiles.GRID - 1 then
    return Tiles.GRID - 1
  end
  return v
end

-- The continent's tiles inside the world rectangle plus `margin` tiles around it, nearest the
-- rectangle's centre first: { x, y, key, file, x1, y1, x2, y2, dist } (world rectangle included).
function Tiles.Visible(continent, wx1, wy1, wx2, wy2, margin)
  local tbl = tables[continent]
  local out = {}
  if not tbl then
    return out
  end
  margin = margin or 0
  local half, t = Tiles.GRID / 2, Tiles.TILE_YARDS
  local cx1 = clampIndex(math.floor(half - wy2 / t) - margin)
  local cx2 = clampIndex(math.floor(half - wy1 / t) + margin)
  local ry1 = clampIndex(math.floor(half - wx2 / t) - margin)
  local ry2 = clampIndex(math.floor(half - wx1 / t) + margin)
  local mx, my = (wx1 + wx2) / 2, (wy1 + wy2) / 2
  for x = cx1, cx2 do
    for y = ry1, ry2 do
      local key = x * Tiles.GRID + y
      local file = tbl[key]
      if file then
        local tx1, ty1, tx2, ty2 = Tiles.WorldRect(x, y)
        local dx, dy = (tx1 + tx2) / 2 - mx, (ty1 + ty2) / 2 - my
        out[#out + 1] = {
          x = x,
          y = y,
          key = key,
          file = file,
          path = Tiles.Path(continent, x, y),
          mask = ns.Overview and ns.Overview.Mask(continent, x, y) or nil, -- the coast's sea mask
          x1 = tx1,
          y1 = ty1,
          x2 = tx2,
          y2 = ty2,
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
-- Tile layers: a layer is { live = { key -> texture }, free = { textures }, stats, sublevel, blend }.
-- Tiles itself is the native layer; Overview.lua (Bastians_Map_Art cells) is another one.
-- ---------------------------------------------------------------------------------------------

local function release(layer, key)
  local t = layer.live[key]
  if t then
    t:Hide()
    layer.free[#layer.free + 1] = t
    layer.live[key] = nil
  end
end

-- Hides every texture of the layer (back to the pool) and zeroes its stats.
function Tiles.Clear(layer)
  for key in pairs(layer.live) do
    release(layer, key)
  end
  layer.stats.shown, layer.stats.wanted, layer.stats.skipped = 0, 0, 0
end

-- Gives the texture its file: the FileDataID first (`tile.file`; it drew every tile on Forever
-- 20.10.2026), the path (`tile.path`, nil for a layer without one) when the id leaves the texture
-- empty. "Empty" is `GetTexture()` returning nil: on Forever `SetTexture` says true for a path it
-- cannot load and the texture stays blank (seen 22.10.2026 with the path form, `/bmap stats`),
-- while a loaded file answers with a number (negative for a path, the id for an id). Returns what
-- was set and whether it was the id.
function Tiles.SetFile(t, tile)
  if tile.file then
    t:SetTexture(tile.file)
    if t:GetTexture() ~= nil or not tile.path then
      t.source = tile.path and "id" or "file"
      return tile.file, true
    end
  end
  t:SetTexture(tile.path)
  t.source = "path"
  return tile.path, false
end

-- Each texture reaches this many UI units past its east and south edges: neighbours start at
-- fractional screen positions and the client rounds each edge on its own, so without the overlap
-- a one-pixel gap opened between cells (since the painted sea nothing
-- is drawn under the level-0 cells and the gap shows the dark background).
Tiles.OVERLAP = 1

-- Puts a live texture where its tile lies on the screen for the camera.
local function placeTile(t, cam, tile)
  local sx1, sy1 = cam:ToScreen(tile.x2, tile.y2) -- north-west corner: top-left on the screen
  local sx2, sy2 = cam:ToScreen(tile.x1, tile.y1)
  t:ClearAllPoints()
  t:SetPoint("TOPLEFT", parent, "TOPLEFT", sx1, -sy1)
  t:SetSize(math.max(1, sx2 - sx1) + Tiles.OVERLAP, math.max(1, sy2 - sy1) + Tiles.OVERLAP)
end

-- Draws the first `cap` entries of `wanted` ({ key, file, path, x1, y1, x2, y2 } in world yards,
-- nearest first): a tile in view keeps its texture across pans, the rest go back to the pool.
function Tiles.Draw(layer, cam, wanted, cap)
  if not parent then
    return
  end
  if layer.continent ~= cam.continent then
    -- keys are positions, the same on every continent: a texture kept across a continent switch
    -- showed Kalimdor's cells over Eastern Kingdoms
    Tiles.Clear(layer)
    layer.continent = cam.continent
  end
  local n = math.min(#wanted, cap)
  local keep = {}
  for i = 1, n do
    keep[wanted[i].key] = true
  end
  for key in pairs(layer.live) do
    if not keep[key] then
      release(layer, key)
    end
  end
  local shown = 0
  for i = 1, n do
    local tile = wanted[i]
    local t = layer.live[tile.key]
    if not t then
      t = table.remove(layer.free)
      if not t then
        t = parent:CreateTexture(nil, "BACKGROUND", nil, layer.sublevel) -- above the zone art (sublevel 0)
        if layer.blend then
          t:SetBlendMode(layer.blend)
        end
      end
      Tiles.SetFile(t, tile)
      t:SetTexCoord(0, 1, 0, 1)
      t.tile = tile.key
      layer.live[tile.key] = t
      if tile.mask or t.maskPath then
        -- the sea of a coast tile masked out, the parchment cell shows through (Compat: nil when
        -- the client has no mask textures, then the water stays as Blizzard drew it)
        t.maskPath = B.Compat.AddMask(t, tile.mask) and tile.mask or nil
      end
    end
    t.rect = tile -- the world rectangle, for Tiles.Reposition
    placeTile(t, cam, tile)
    t:Show()
    shown = shown + 1
  end
  layer.stats.shown, layer.stats.wanted = shown, #wanted
  layer.stats.skipped = #wanted - shown
end

-- Moves the live textures of the layer to where their tiles lie for the camera, nothing else: what
-- a resize needs while the mouse is still down. Tiles that scroll in
-- wait for the full draw at the end of the resize.
function Tiles.Reposition(layer, cam)
  for _, t in pairs(layer.live) do
    if t.rect then
      placeTile(t, cam, t.rect)
    end
  end
end

-- One line per live texture of a layer for the chat: what the client says about it (the owner's
-- diagnosis line of 21.10.2026 evening: GetTexture, IsShown, GetSize, which form loaded it).
function Tiles.Describe(layer, limit)
  local lines = {}
  local keys = {}
  for key in pairs(layer.live) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  for i = 1, math.min(limit or 5, #keys) do
    local t = layer.live[keys[i]]
    local w, h = t:GetSize()
    lines[#lines + 1] = string.format(
      "%d (%d/%d): %s %s shown=%s %dx%d%s",
      keys[i],
      math.floor(keys[i] / Tiles.GRID),
      keys[i] % Tiles.GRID,
      t.source or "?",
      tostring(t:GetTexture()),
      tostring(t:IsShown()),
      math.floor((w or 0) + 0.5),
      math.floor((h or 0) + 0.5),
      t.maskPath and " masked" or ""
    )
  end
  return lines
end

-- ---------------------------------------------------------------------------------------------
-- The native layer
-- ---------------------------------------------------------------------------------------------

Tiles.sublevel = 2 -- above the overview cells (1) and the zone art (0)

function Tiles.Enabled()
  return mod ~= nil and mod.db.profile.nativeTiles ~= false and next(tables) ~= nil
end

-- Tiles the view needs including the margin: when more than the cap, the native layer stays off
-- and the overview shows (a sharp block in the middle of a blurry view looked wrong on a 2137 px
-- window at level 3.5, Forever 20.10.2026); the levels where the tiles show depend on the window.
function Tiles.Needed(cam)
  local x1, y1, x2, y2 = cam:Bounds()
  local t = Tiles.TILE_YARDS
  local cols = math.ceil((y2 - y1) / t) + 1 + 2 * Tiles.MARGIN
  local rows = math.ceil((x2 - x1) / t) + 1 + 2 * Tiles.MARGIN
  return cols * rows
end

function Tiles.Render(cam)
  if not parent then
    return
  end
  if not Tiles.Enabled() or cam.level < Tiles.MIN_LEVEL or Tiles.Needed(cam) > Tiles.MAX_TEXTURES then
    Tiles.Clear(Tiles)
    return
  end
  local x1, y1, x2, y2 = cam:Bounds()
  Tiles.Draw(Tiles, cam, Tiles.Visible(cam.continent, x1, y1, x2, y2, Tiles.MARGIN), Tiles.MAX_TEXTURES)
end

function Tiles.Attach(clip)
  parent = clip
end

ns.mod.Tiles = Tiles
table.insert(Map.onBuild, Tiles.Attach)
table.insert(Map.onView, Tiles.Render)
table.insert(Map.onResize, function(cam)
  Tiles.Reposition(Tiles, cam)
end)
table.insert(Map.onEnable, function(self)
  mod = self
end)
table.insert(Map.onSetting, function(key)
  if key == "nativeTiles" then
    Map.ViewChanged()
  elseif key == "overviewArt" then
    Tiles.Clear(Tiles) -- the coast masks follow the cells: reload the live tiles with or without them
  end
end)
