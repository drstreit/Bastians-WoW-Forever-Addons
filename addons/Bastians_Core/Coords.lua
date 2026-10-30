-- Coordinate facade (coordinates.md): map fractions in, world yards per continent out, and back.
-- The transform table comes from Data (generated); the client API is tried first where it exists.
local _, ns = ...
local B = ns.B
local Compat = ns.Compat

local Coords = {}
B.Coords = Coords

-- [uiMapID] = { continent, wx0, wxDx, wxDy, wy0, wyDx, wyDy }: world = origin + fractions * matrix
local transforms = {}
-- A continent is the Map.db2 id the client's world positions report. Names come with the
-- transform table (every open-world map with a zone: Outland, Northrend, ... on retail); without
-- one, the two Azeroth continents.
Coords.DEFAULT_CONTINENTS = { [0] = "Eastern Kingdoms", [1] = "Kalimdor" }
local continents = {}
local continentMaps = {} -- continent -> its uiMap (Coords.ContinentMap), or false when it has none

function Coords.SetTransforms(tbl, names)
  transforms = tbl or {}
  continents = type(names) == "table" and names or {}
  continentMaps = {} -- found again from the new table
  Compat.SetTransformTable(transforms)
end

-- { [continent] = name } for the Map's continent list and footer.
function Coords.Continents()
  if next(continents) then
    return continents
  end
  return Coords.DEFAULT_CONTINENTS
end

function Coords.ContinentName(continent)
  return Coords.Continents()[continent]
end

function Coords.HasTransform(uiMapID)
  return transforms[uiMapID] ~= nil
end

-- (uiMapID, x, y) -> continent, wx, wy ; nil when unknown
function Coords.ToWorld(uiMapID, x, y)
  return Compat.MapPosToWorld(uiMapID, x, y)
end

local scratch = Compat.Has.WorldPosFromMapPos and CreateVector2D(0, 0) or nil

-- ---------------------------------------------------------------------------------------------
-- A uiMap's painting (the Blizzard map style, the Browser's zone banner): the art layer's tiles in
-- layer pixels and the explored areas the character has uncovered on it, as Blizzard draws them.
-- ---------------------------------------------------------------------------------------------

Coords.OVERLAY_TILE = 256

-- Blizzard's explored areas of a map as tiles in the map's layer pixels, cut as
-- MapExplorationPinMixin cuts them: 256 px tiles, the last row and column from the smallest
-- power-of-two file (16 px up) that holds them; areas shown only on mouse-over are left out.
-- { file, px1, py1, px2, py2, tcRight, tcBottom, top }.
function Coords.OverlayTiles(infos)
  local size = Coords.OVERLAY_TILE
  local out = {}
  local function cut(total, i, n)
    if i < n then
      return size, size
    end
    local px = total % size
    if px == 0 then
      px = size
    end
    local file = 16
    while file < px do
      file = file * 2
    end
    return px, file
  end
  for _, info in ipairs(infos or {}) do
    local ids = info.fileDataIDs
    local w, h = tonumber(info.textureWidth) or 0, tonumber(info.textureHeight) or 0
    if type(ids) == "table" and not info.isShownByMouseOver and w > 0 and h > 0 then
      local wide, tall = math.ceil(w / size), math.ceil(h / size)
      for j = 1, tall do
        local ph, fh = cut(h, j, tall)
        for k = 1, wide do
          local pw, fw = cut(w, k, wide)
          local file = ids[(j - 1) * wide + k]
          if file then
            local px1 = (info.offsetX or 0) + size * (k - 1)
            local py1 = (info.offsetY or 0) + size * (j - 1)
            out[#out + 1] = {
              file = file,
              px1 = px1,
              py1 = py1,
              px2 = px1 + pw,
              py2 = py1 + ph,
              tcRight = pw / fw,
              tcBottom = ph / fh,
              top = info.isDrawOnTopLayer and true or false,
            }
          end
        end
      end
    end
  end
  return out
end

-- The painting of a uiMap: { width, height, maxScale, tiles, explored } in layer pixels, each tile
-- { file, px1, py1, px2, py2, tcRight, tcBottom } (edge tiles partly used), the explored areas cut
-- by Coords.OverlayTiles; nil when the map has no art or the client lacks the calls.
function Coords.MapArt(uiMapID)
  local cmap = rawget(_G, "C_Map")
  if
    not (
      cmap
      and type(cmap.GetMapArtLayers) == "function"
      and type(cmap.GetMapArtLayerTextures) == "function"
    )
  then
    return nil
  end
  local layers = uiMapID and cmap.GetMapArtLayers(uiMapID)
  local info = layers and layers[1]
  if not (info and info.layerWidth and info.tileWidth and info.layerWidth > 0 and info.tileWidth > 0) then
    return nil
  end
  local lw, lh, tw, th = info.layerWidth, info.layerHeight, info.tileWidth, info.tileHeight
  local cols = math.ceil(lw / tw)
  local tiles = {}
  for i, file in ipairs(cmap.GetMapArtLayerTextures(uiMapID, 1) or {}) do
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    local px1, py1 = col * tw, row * th
    local px2, py2 = math.min(px1 + tw, lw), math.min(py1 + th, lh)
    if px2 > px1 and py2 > py1 then
      tiles[#tiles + 1] = {
        file = file,
        px1 = px1,
        py1 = py1,
        px2 = px2,
        py2 = py2,
        tcRight = (px2 - px1) / tw,
        tcBottom = (py2 - py1) / th,
      }
    end
  end
  if #tiles == 0 then
    return nil
  end
  local api = rawget(_G, "C_MapExplorationInfo")
  local infos = api and type(api.GetExploredMapTextures) == "function" and api.GetExploredMapTextures(uiMapID)
    or nil
  return {
    width = lw,
    height = lh,
    maxScale = info.maxScale,
    tiles = tiles,
    explored = Coords.OverlayTiles(infos),
  }
end

-- (continent, wx, wy, uiMapID) -> x, y as fractions (may lie outside 0..1) ; nil when unknown
function Coords.ToMap(continent, wx, wy, uiMapID)
  local t = transforms[uiMapID]
  if t and t[1] == continent then
    local a, b, c, d = t[3], t[4], t[6], t[7]
    local det = a * d - b * c
    if det ~= 0 then
      local dx, dy = wx - t[2], wy - t[5]
      return (dx * d - dy * b) / det, (dy * a - dx * c) / det
    end
  end
  if scratch and type(C_Map.GetMapPosFromWorldPos) == "function" then
    scratch:SetXY(wx, wy)
    local _, pos = C_Map.GetMapPosFromWorldPos(continent, scratch, uiMapID)
    if pos then
      return pos:GetXY()
    end
  end
  return nil
end

local function area(t)
  return math.abs(t[3] * t[7] - t[4] * t[6])
end

-- The continent maps of the two Azeroth continents as Forever numbers them (Classic's uiMapIDs).
-- ~~The same on Forever and retail.~~ Retail has no 1414 and 1415: its Kalimdor is 12, its Eastern
-- Kingdoms 13 (retail probe P3, 12.1.5.70575, 28.10.2026), so Coords.ContinentMap asks the client.
Coords.CONTINENT_MAPS = { [0] = 1415, [1] = 1414 }
Coords.CONTINENT_MAPS_RETAIL = { [0] = 13, [1] = 12 }
local UI_MAP_CONTINENT = 2 -- Enum.UIMapType.Continent

local function isContinentMap(uiMapID, continent)
  local info = uiMapID and C_Map.GetMapInfo(uiMapID)
  if not (info and info.mapType == UI_MAP_CONTINENT) then
    return false
  end
  local c = Compat.MapPosToWorld(uiMapID, 0.5, 0.5)
  return c == nil or c == continent
end

-- The continent's own uiMap (the painted continent, the root of its zones), or nil: a known id
-- (Forever's, then retail's) when this client has it as a continent map, else the continent map
-- above any map of the transform table on the continent (Outland, Northrend, ... on retail).
function Coords.ContinentMap(continent)
  local known = continentMaps[continent]
  if known ~= nil then
    return known or nil
  end
  local found
  if type(C_Map.GetMapInfo) == "function" then
    for _, ids in ipairs({ Coords.CONTINENT_MAPS, Coords.CONTINENT_MAPS_RETAIL }) do
      if not found and isContinentMap(ids[continent], continent) then
        found = ids[continent]
      end
    end
    if not found then
      local ids = {}
      for uiMapID, t in pairs(transforms) do
        if t[1] == continent then
          ids[#ids + 1] = uiMapID
        end
      end
      table.sort(ids) -- the same answer every time
      for _, uiMapID in ipairs(ids) do
        local id, steps = uiMapID, 0
        while id and steps < 6 and not found do
          local info = C_Map.GetMapInfo(id)
          if info and info.mapType == UI_MAP_CONTINENT then
            found = isContinentMap(id, continent) and id or nil
            break
          end
          id, steps = info and info.parentMapID, steps + 1
        end
        if found then
          break
        end
      end
    end
  end
  -- an empty transform table may still fill: only an answer is kept
  if found or next(transforms) ~= nil then
    continentMaps[continent] = found or false
  end
  return found
end

-- Without a transform table: the deepest map under the continent map whose rectangle holds the point,
-- through the client (C_Map.GetMapChildrenInfo, documented on both clients; assumed on Forever).
local function clientBestMap(continent, wx, wy)
  local root = Coords.ContinentMap(continent)
  if not (root and type(C_Map.GetMapChildrenInfo) == "function") then
    return nil
  end
  local best
  local function walk(parent, depth)
    for _, child in ipairs(C_Map.GetMapChildrenInfo(parent) or {}) do
      local x, y = Coords.ToMap(continent, wx, wy, child.mapID)
      if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
        if not best or depth > best.depth then
          best = { map = child.mapID, depth = depth }
        end
        if depth < 4 then
          walk(child.mapID, depth + 1)
        end
      end
    end
  end
  walk(root, 1)
  return best and best.map or nil
end

-- The containing map of the transform table in which the point lies most centrally (zone
-- rectangles overlap their neighbours, so "smallest" picks the neighbour for a point near a border;
-- coordinates.md, measured 20.10.2026); centrality rounded to a tenth, the smaller area, then the
-- lower id break ties. The client's map tree when the table is empty.
Coords.PARENT_RATIO = 8 -- a containing map this many times larger than the smallest is a parent map
function Coords.BestMap(continent, wx, wy)
  local candidates, smallest = {}, nil
  for uiMapID, t in pairs(transforms) do
    if t[1] == continent then
      local x, y = Coords.ToMap(continent, wx, wy, uiMapID)
      if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
        local a = area(t)
        candidates[#candidates + 1] = { map = uiMapID, area = a, x = x, y = y }
        if not smallest or a < smallest then
          smallest = a
        end
      end
    end
  end
  local best, bestCentral, bestArea
  for _, c in ipairs(candidates) do
    if c.area <= smallest * Coords.PARENT_RATIO then
      local central = math.floor(math.max(math.abs(c.x - 0.5), math.abs(c.y - 0.5)) * 10 + 0.5)
      if
        not best
        or central < bestCentral
        or (central == bestCentral and (c.area < bestArea or (c.area == bestArea and c.map < best)))
      then
        best, bestCentral, bestArea = c.map, central, c.area
      end
    end
  end
  if best or next(transforms) ~= nil then
    return best
  end
  return clientBestMap(continent, wx, wy)
end

-- -> continent, wx, wy, uiMapID, x, y ; nil when the player's map position is unknown (instances)
function Coords.Player()
  return Coords.Unit("player")
end

-- The same for a unit of the group ("party1", "raid3"; R26.9): nil where the client gives no map
-- position (another instance, out of range of the game's own rules)
function Coords.Unit(unit)
  local uiMapID = C_Map.GetBestMapForUnit(unit)
  if not uiMapID then
    return nil
  end
  local pos = C_Map.GetPlayerMapPosition(uiMapID, unit)
  if not pos then
    return nil
  end
  local x, y = pos:GetXY()
  local continent, wx, wy = Coords.ToWorld(uiMapID, x, y)
  if not continent then
    return nil, nil, nil, uiMapID, x, y
  end
  return continent, wx, wy, uiMapID, x, y
end

-- BASTIANS_PLAYER_MOVED_ZONE(uiMapID, continent): coalesced zone changes (core-contracts §16). The
-- client fires ZONE_CHANGED* in bursts; one timer after the last one compares the map with the last
-- one announced. Instances without a map position announce nil once.
local lastMap
local zoneTimer
local zoneFrame = CreateFrame("Frame")
for _, event in ipairs({
  "ZONE_CHANGED_NEW_AREA",
  "ZONE_CHANGED",
  "ZONE_CHANGED_INDOORS",
  "PLAYER_ENTERING_WORLD",
}) do
  zoneFrame:RegisterEvent(event)
end
local function announceZone()
  zoneTimer = nil
  local uiMapID = C_Map.GetBestMapForUnit("player")
  if uiMapID == lastMap then
    return
  end
  lastMap = uiMapID
  local continent = uiMapID and Coords.ToWorld(uiMapID, 0.5, 0.5) or nil
  B:Fire("BASTIANS_PLAYER_MOVED_ZONE", uiMapID, continent)
end
zoneFrame:SetScript("OnEvent", function()
  if zoneTimer then
    zoneTimer:Cancel()
  end
  zoneTimer = C_Timer.NewTimer(0.2, announceZone)
end)

-- The map the player is on, as last announced (nil before the first announcement).
function Coords.PlayerMap()
  return lastMap
end

-- Yards between two { continent, wx, wy } points; nil across continents.
function Coords.Distance(a, b)
  if a[1] ~= b[1] then
    return nil
  end
  local dx, dy = a[2] - b[2], a[3] - b[3]
  return math.sqrt(dx * dx + dy * dy)
end

-- How far a ref or a place { map, wx, wy } is from the player, for rows, cards and tooltips
-- (world-graph.md principle 7): the world graph's travel time from its cache, never a search ->
-- seconds, approx. Without the graph's network on the player's continent (no nav pack, data.md)
-- the straight line stands in -> nil, nil, yards. nil when neither is known; a time not cached
-- yet is nil too, and BASTIANS_GRAPH_TIMES says when to ask again.
function Coords.Away(target)
  local graph = B:GetService("graph")
  if graph and graph:Ready() then
    return graph:Time(target)
  end
  if type(target) == "string" then
    return nil, nil, (Coords.DistanceTo(target))
  end
  local continent, wx, wy = Coords.Player()
  if continent and type(target) == "table" and target.map == continent and target.wx then
    local dx, dy = target.wx - wx, target.wy - wy
    return nil, nil, math.sqrt(dx * dx + dy * dy)
  end
  return nil
end

-- Yards from the player to the nearest known place of an entity (C1): the entity's locations
-- (every provider, core-contracts §4) on the player's continent, through the transform table.
-- -> yards, point ; nil when the player's position, the entity's places or the transform are unknown.
function Coords.DistanceTo(ref)
  local continent, wx, wy = Coords.Player()
  if not continent then
    return nil
  end
  local best, bestPoint
  for _, p in ipairs(B:Entity(ref):Locations()) do
    if p.map and p.x and p.y then
      local c, px, py = Coords.ToWorld(p.map, p.x, p.y)
      if c == continent then
        local dx, dy = px - wx, py - wy
        local d = dx * dx + dy * dy
        if not best or d < best then
          best, bestPoint = d, p
        end
      end
    end
  end
  if not best then
    return nil
  end
  return math.sqrt(best), bestPoint
end
