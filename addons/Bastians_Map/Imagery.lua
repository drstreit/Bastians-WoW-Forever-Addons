-- Imagery stage 1 (map.md, ADR 0007 fallback path): Blizzard's zone art tiles placed in world
-- coordinates through the map transforms, so Elwynn, Westfall and Duskwood join without seams; no
-- zone rectangles (29.10.2026; the zone names are the layer map.zones, Layers.lua). Pooled
-- textures with a cap; only zones in view are drawn; drawing happens on Map.onView, never per frame.
-- Stage 2 (native minimap tiles, Map_Art) is B8.4.
local _, ns = ...
local B = Bastians
local Map = ns.Map

local Imagery = {}
ns.Imagery = Imagery

Imagery.MAX_TEXTURES = 300 -- live art textures (map.md budget)
local MAX_DEPTH = 2 -- continent, zones, cities
local UI_MAP_ZONE = 3 -- Enum.UIMapType.Zone: retail lists caves (5), dungeons (4) and orphans (6) too

local parent -- the clip frame
local pool = {} -- exposed below for the tests
Imagery.pool = pool
local zonesByContinent = {} -- continent -> array of { map, name, depth, x1, y1, x2, y2, tiles }

-- ---------------------------------------------------------------------------------------------
-- Geometry: which maps exist on a continent, where they lie in world yards, and their art tiles
-- ---------------------------------------------------------------------------------------------

local function worldRect(map)
  local c1, ax, ay = B.Coords.ToWorld(map, 0, 0)
  local c2, bx, by = B.Coords.ToWorld(map, 1, 1)
  if not (c1 and c2) or c1 ~= c2 then
    return nil
  end
  return c1, math.min(ax, bx), math.min(ay, by), math.max(ax, bx), math.max(ay, by)
end

-- The art tiles of a map: file id and the map-fraction rectangle each one covers, with the texture
-- coordinates of partly used edge tiles; then the art layer (its size and largest scale).
local function tilesFor(map)
  local tiles = {}
  if type(C_Map.GetMapArtLayers) ~= "function" or type(C_Map.GetMapArtLayerTextures) ~= "function" then
    return tiles
  end
  local layers = C_Map.GetMapArtLayers(map)
  local info = layers and layers[1]
  if not (info and info.layerWidth and info.tileWidth and info.layerWidth > 0 and info.tileWidth > 0) then
    return tiles
  end
  local textures = C_Map.GetMapArtLayerTextures(map, 1) or {}
  local cols = math.ceil(info.layerWidth / info.tileWidth)
  for i, fileID in ipairs(textures) do
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    local px1, py1 = col * info.tileWidth, row * info.tileHeight
    local px2, py2 =
      math.min(px1 + info.tileWidth, info.layerWidth), math.min(py1 + info.tileHeight, info.layerHeight)
    if px2 > px1 and py2 > py1 then
      tiles[#tiles + 1] = {
        file = fileID,
        fx1 = px1 / info.layerWidth,
        fy1 = py1 / info.layerHeight,
        fx2 = px2 / info.layerWidth,
        fy2 = py2 / info.layerHeight,
        tcRight = (px2 - px1) / info.tileWidth,
        tcBottom = (py2 - py1) / info.tileHeight,
      }
    end
  end
  return tiles, info
end

local function mapName(map)
  local name = B:Entity("zone:" .. map):Name()
  if name then
    return name
  end
  local info = C_Map.GetMapInfo(map)
  return info and info.name or ("map " .. map)
end

-- Every map with art under the continent map, continent first, then zones, then cities; `mapType`
-- from the client (nil when it gives none).
function Imagery.Zones(continent)
  local cached = zonesByContinent[continent]
  if cached then
    return cached
  end
  local list = {}
  local root = B.Coords.ContinentMap(continent) -- 13 on retail, 1415 on Forever (R28.4)
  local function add(map, depth, mapType)
    local c, x1, y1, x2, y2 = worldRect(map)
    if c ~= continent then
      return false
    end
    local tiles, layer = tilesFor(map)
    list[#list + 1] = {
      map = map,
      depth = depth,
      mapType = mapType,
      name = mapName(map),
      x1 = x1,
      y1 = y1,
      x2 = x2,
      y2 = y2,
      tiles = tiles,
      layer = layer,
    }
    return true
  end
  if root then
    add(root, 0)
    local function walk(parentMap, depth)
      if depth > MAX_DEPTH or type(C_Map.GetMapChildrenInfo) ~= "function" then
        return
      end
      for _, child in ipairs(C_Map.GetMapChildrenInfo(parentMap) or {}) do
        if add(child.mapID, depth, child.mapType) then
          walk(child.mapID, depth + 1)
        end
      end
    end
    walk(root, 1)
  end
  table.sort(list, function(a, b)
    if a.depth ~= b.depth then
      return a.depth < b.depth
    end
    return a.map < b.map
  end)
  if #list > 0 then
    zonesByContinent[continent] = list -- none found is asked again: the transforms may come later
  end
  return list
end

function Imagery.Reset()
  zonesByContinent = {}
end

-- ---------------------------------------------------------------------------------------------
-- Pools
-- ---------------------------------------------------------------------------------------------

local function texture(i)
  local t = pool[i]
  if not t then
    t = parent:CreateTexture(nil, "BACKGROUND")
    pool[i] = t
  end
  return t
end

local function place(region, sx1, sy1, sx2, sy2)
  region:ClearAllPoints()
  region:SetPoint("TOPLEFT", parent, "TOPLEFT", sx1, -sy1)
  region:SetSize(math.max(1, sx2 - sx1), math.max(1, sy2 - sy1))
  region:Show()
end

-- ---------------------------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------------------------

-- A zone or a city of the continent: its art. Caves, dungeons and the orphan maps
-- retail lists under a zone are not (Fargodeep Mine drawn over Elwynn,
-- their rectangles everywhere, a dungeon's parchment in the continent painting).
function Imagery.IsZone(z)
  return z.depth >= 1 and (z.mapType == nil or z.mapType == UI_MAP_ZONE)
end

local function intersects(cam, z)
  local x1, y1, x2, y2 = cam:Bounds()
  return z.x2 >= x1 and z.x1 <= x2 and z.y2 >= y1 and z.y1 <= y2
end

-- Screen rectangle of a world rectangle (wx1 < wx2 south to north, wy1 < wy2 east to west).
local function screenRect(cam, wx1, wy1, wx2, wy2)
  local ax, ay = cam:ToScreen(wx2, wy2) -- north-west corner: top-left on the screen
  local bx, by = cam:ToScreen(wx1, wy1)
  return ax, ay, bx, by
end

Imagery.stats = { textures = 0, zones = 0 }

-- The maps whose art intersects the view: { map, name, depth, tiles, w, h } in screen pixels, for
-- `/bmap stats`.
function Imagery.Drawn(cam)
  local out = {}
  for _, z in ipairs(Imagery.Zones(cam.continent)) do
    if intersects(cam, z) then
      local sx1, sy1, sx2, sy2 = screenRect(cam, z.x1, z.y1, z.x2, z.y2)
      out[#out + 1] = {
        map = z.map,
        name = z.name,
        depth = z.depth,
        tiles = #z.tiles,
        w = math.floor(sx2 - sx1 + 0.5),
        h = math.floor(sy2 - sy1 + 0.5),
      }
    end
  end
  return out
end

-- The draw sublevel of a map's art: the continent lowest, then the zones, then the cities; the zone
-- and the city under the view's centre above their neighbours, whose rectangles overlap theirs. All
-- below Map Art's overview (1) and the native tiles (2).
function Imagery.Sublevel(z, cam)
  if z.depth == 0 then
    return -4
  end
  local inside = cam.wx >= z.x1 and cam.wx <= z.x2 and cam.wy >= z.y1 and cam.wy <= z.y2
  return (z.depth == 1 and -3 or -1) + (inside and 1 or 0)
end

-- One art tile of map `z` (its map-fraction rectangle fx1..fy2) as pool texture `used + 1` when it
-- lies in view; returns the new count. Map fractions to world yards through the map's transform
-- (affine: two corners suffice).
local function drawArt(used, cam, z, fx1, fy1, fx2, fy2, file, tcRight, tcBottom, sub)
  if used >= Imagery.MAX_TEXTURES then
    return used
  end
  local _, ax, ay = B.Coords.ToWorld(z.map, fx1, fy1)
  local _, bx, by = B.Coords.ToWorld(z.map, fx2, fy2)
  if not (ax and bx) then
    return used
  end
  local sx1, sy1, sx2, sy2 =
    screenRect(cam, math.min(ax, bx), math.min(ay, by), math.max(ax, bx), math.max(ay, by))
  if sx2 < 0 or sy2 < 0 or sx1 > cam.width or sy1 > cam.height then
    return used
  end
  used = used + 1
  local t = texture(used)
  if t.file ~= file or t.tcRight ~= tcRight or t.tcBottom ~= tcBottom then
    t:SetTexture(file)
    t:SetTexCoord(0, tcRight, 0, tcBottom)
    t.file, t.tcRight, t.tcBottom = file, tcRight, tcBottom
  end
  if t.sub ~= sub then
    t:SetDrawLayer("BACKGROUND", sub)
    t.sub = sub
  end
  t.rect = { math.min(ax, bx), math.min(ay, by), math.max(ax, bx), math.max(ay, by) }
  place(t, sx1, sy1, sx2, sy2)
  return used
end

local function hideFrom(used)
  for i = used + 1, #pool do
    pool[i]:Hide()
  end
end

function Imagery.Render(cam)
  if not parent then
    return
  end
  local style = Map.Style()
  local used, zonesDrawn = 0, 0
  -- the physical map: every zone's art under the ground tiles; the baked styles (ADR 0027, the
  -- Blizzard one of ADR 0036) draw no painting here. No zone rectangles in any style (owner, retail
  -- 29.10.2026: "remove them"; they were the paintings' frames, not the zones' borders)
  local ours = style ~= "physical"
  for _, z in ipairs(Imagery.Zones(cam.continent)) do
    if (z.depth == 0 or Imagery.IsZone(z)) and intersects(cam, z) then
      zonesDrawn = zonesDrawn + 1
      local sub = Imagery.Sublevel(z, cam)
      if not ours then
        for _, tile in ipairs(z.tiles) do
          used = drawArt(
            used,
            cam,
            z,
            tile.fx1,
            tile.fy1,
            tile.fx2,
            tile.fy2,
            tile.file,
            tile.tcRight,
            tile.tcBottom,
            sub
          )
        end
      end
    end
  end
  hideFrom(used)
  Imagery.stats.textures, Imagery.stats.zones = used, zonesDrawn
  Imagery.stats.pool = #pool
end

-- Moves what is shown to where it lies for the camera, no texture is set or loaded (a resize in
-- progress): art tiles from their world rectangle.
function Imagery.Reposition(cam)
  for i = 1, Imagery.stats.textures do
    local t = pool[i]
    if t and t.rect and t:IsShown() then
      place(t, screenRect(cam, t.rect[1], t.rect[2], t.rect[3], t.rect[4]))
    end
  end
end

function Imagery.Attach(clip)
  parent = clip
end

ns.mod.Imagery = Imagery
table.insert(Map.onBuild, Imagery.Attach)
table.insert(Map.onView, Imagery.Render)
table.insert(Map.onResize, Imagery.Reposition)
table.insert(Map.onEnable, function(self)
  self:On("BASTIANS_DATA_LOADED", function()
    Imagery.Reset() -- new transforms or zone names
    if ns.Layers then
      ns.Layers.Reset() -- the zones of the map's own layers (Layers.lua)
    end
    Map.ViewChanged()
  end)
end)
