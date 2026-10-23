-- Imagery stage 1 (map.md, ADR 0007 fallback path): Blizzard's zone art tiles placed in world
-- coordinates through the map transforms, so Elwynn, Westfall and Duskwood join without seams, plus
-- zone borders and names as vector overlays. Pooled textures with a cap; only zones in view are drawn;
-- drawing happens on Map.onView, never per frame. Stage 2 (native minimap tiles, Map_Art) is B8.4.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Map = ns.Map

local Imagery = {}
ns.Imagery = Imagery

Imagery.MAX_TEXTURES = 300 -- live art textures (map.md budget)
Imagery.LABEL_MIN_LEVEL = 1 -- zone names from this level on
Imagery.BORDER_MIN_LEVEL = 0.5
local MAX_DEPTH = 2 -- continent, zones, cities

local parent -- the clip frame
local pool, linePool, labelPool = {}, {}, {} -- exposed below for the tests
Imagery.pool, Imagery.linePool, Imagery.labelPool = pool, linePool, labelPool
local zonesByContinent = {} -- continent -> array of { map, name, depth, x1, y1, x2, y2, tiles }
local zoneInfo = {} -- map -> { lo, hi } from Data when it has the zone

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
-- coordinates of partly used edge tiles.
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
  return tiles
end

local function mapName(map)
  local name = B:Entity("zone:" .. map):Name()
  if name then
    return name
  end
  local info = C_Map.GetMapInfo(map)
  return info and info.name or ("map " .. map)
end

-- Every map with art under the continent map, continent first, then zones, then cities.
function Imagery.Zones(continent)
  local cached = zonesByContinent[continent]
  if cached then
    return cached
  end
  local list = {}
  local root = B.Coords.CONTINENT_MAPS[continent]
  local function add(map, depth)
    local c, x1, y1, x2, y2 = worldRect(map)
    if c ~= continent then
      return false
    end
    list[#list + 1] = {
      map = map,
      depth = depth,
      name = mapName(map),
      x1 = x1,
      y1 = y1,
      x2 = x2,
      y2 = y2,
      tiles = tilesFor(map),
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
        if add(child.mapID, depth) then
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
  zonesByContinent[continent] = list
  return list
end

function Imagery.Reset()
  zonesByContinent = {}
  zoneInfo = {}
end

local function levelRange(map)
  local cached = zoneInfo[map]
  if cached ~= nil then
    return cached or nil
  end
  local d = B:GetService("data")
  local z = d and d:Get("zone", map)
  local range = z and z.levelLo and z.levelHi and { lo = z.levelLo, hi = z.levelHi } or false
  zoneInfo[map] = range
  return range or nil
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

local function line(i)
  local t = linePool[i]
  if not t then
    t = parent:CreateTexture(nil, "BORDER")
    t:SetTexture(S.WHITE)
    S.tint(t, S.C.grid)
    linePool[i] = t
  end
  return t
end

local function label(i)
  local f = labelPool[i]
  if not f then
    f = CreateFrame("Frame", nil, parent)
    f:SetSize(120, 16)
    f.text = S.text(f, 12, S.C.text)
    f.text:SetPoint("CENTER")
    f.text:SetJustifyH("CENTER")
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
      if not (GameTooltip and self.map) then
        return
      end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(self.name or "", 1, 1, 1)
      local range = levelRange(self.map)
      if range then
        S.TipLine(GameTooltip, L["Level"] .. " " .. range.lo .. "-" .. range.hi, "tipDim")
      end
      GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function()
      if GameTooltip then
        GameTooltip:Hide()
      end
    end)
    labelPool[i] = f
  end
  return f
end

local function place(region, sx1, sy1, sx2, sy2)
  region:ClearAllPoints()
  region:SetPoint("TOPLEFT", parent, "TOPLEFT", sx1, -sy1)
  region:SetSize(math.max(1, sx2 - sx1), math.max(1, sy2 - sy1))
  region:Show()
end

-- One edge of a zone's screen rectangle as a 1 px line: 1 top, 2 bottom, 3 left, 4 right.
local function placeEdge(t, sx1, sy1, sx2, sy2)
  local edge = t.edge
  if edge == 1 then
    place(t, sx1, sy1, sx2, sy1 + 1)
  elseif edge == 2 then
    place(t, sx1, sy2 - 1, sx2, sy2)
  elseif edge == 3 then
    place(t, sx1, sy1, sx1 + 1, sy2)
  else
    place(t, sx2 - 1, sy1, sx2, sy2)
  end
end

local function placeLabel(f, sx1, sy1, sx2, sy2)
  f:ClearAllPoints()
  f:SetPoint("CENTER", parent, "TOPLEFT", (sx1 + sx2) / 2, -(sy1 + sy2) / 2)
  f:Show()
end

-- ---------------------------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------------------------

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

Imagery.stats = { textures = 0, zones = 0, labels = 0 }

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

function Imagery.Render(cam)
  if not parent then
    return
  end
  local used, lines, labels, zonesDrawn = 0, 0, 0, 0
  local level = cam.level
  for _, z in ipairs(Imagery.Zones(cam.continent)) do
    if intersects(cam, z) then
      zonesDrawn = zonesDrawn + 1
      for _, tile in ipairs(z.tiles) do
        if used >= Imagery.MAX_TEXTURES then
          break
        end
        -- the tile's map-fraction rectangle in world yards (affine: corners suffice)
        local _, ax, ay = B.Coords.ToWorld(z.map, tile.fx1, tile.fy1)
        local _, bx, by = B.Coords.ToWorld(z.map, tile.fx2, tile.fy2)
        if ax and bx then
          local sx1, sy1, sx2, sy2 =
            screenRect(cam, math.min(ax, bx), math.min(ay, by), math.max(ax, bx), math.max(ay, by))
          if sx2 >= 0 and sy2 >= 0 and sx1 <= cam.width and sy1 <= cam.height then
            used = used + 1
            local t = texture(used)
            if t.file ~= tile.file then
              t:SetTexture(tile.file)
              t:SetTexCoord(0, tile.tcRight, 0, tile.tcBottom)
              t.file = tile.file
            end
            t.rect = { math.min(ax, bx), math.min(ay, by), math.max(ax, bx), math.max(ay, by) }
            place(t, sx1, sy1, sx2, sy2)
          end
        end
      end
      if z.depth >= 1 then
        local sx1, sy1, sx2, sy2 = screenRect(cam, z.x1, z.y1, z.x2, z.y2)
        if level >= Imagery.BORDER_MIN_LEVEL then
          for edge = 1, 4 do
            local t = line(lines + edge)
            t.zone, t.edge = z, edge
            placeEdge(t, sx1, sy1, sx2, sy2)
          end
          lines = lines + 4
        end
        if level >= Imagery.LABEL_MIN_LEVEL and z.depth == 1 then
          labels = labels + 1
          local f = label(labels)
          f.map, f.name, f.zone = z.map, z.name, z
          f.text:SetText(z.name)
          placeLabel(f, sx1, sy1, sx2, sy2)
        end
      end
    end
  end
  for i = used + 1, #pool do
    pool[i]:Hide()
  end
  for i = lines + 1, #linePool do
    linePool[i]:Hide()
  end
  for i = labels + 1, #labelPool do
    labelPool[i]:Hide()
  end
  Imagery.stats.textures, Imagery.stats.zones, Imagery.stats.labels = used, zonesDrawn, labels
  Imagery.stats.pool = #pool
end

-- Moves what is shown to where it lies for the camera, no texture is set or loaded (a resize in
-- progress): art tiles from their world rectangle, borders and names from their zone.
function Imagery.Reposition(cam)
  for i = 1, Imagery.stats.textures do
    local t = pool[i]
    if t and t.rect and t:IsShown() then
      place(t, screenRect(cam, t.rect[1], t.rect[2], t.rect[3], t.rect[4]))
    end
  end
  for _, t in ipairs(linePool) do
    if t.zone and t:IsShown() then
      local z = t.zone
      placeEdge(t, screenRect(cam, z.x1, z.y1, z.x2, z.y2))
    end
  end
  for _, f in ipairs(labelPool) do
    if f.zone and f:IsShown() then
      local z = f.zone
      placeLabel(f, screenRect(cam, z.x1, z.y1, z.x2, z.y2))
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
    Map.ViewChanged()
  end)
end)
