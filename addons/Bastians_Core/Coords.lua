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

function Coords.SetTransforms(tbl, names)
  transforms = tbl or {}
  continents = type(names) == "table" and names or {}
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

-- The continent maps of the two Azeroth continents (uiMapID; the same on Forever and retail).
Coords.CONTINENT_MAPS = { [0] = 1415, [1] = 1414 }

-- Without a transform table: the deepest map under the continent map whose rectangle holds the point,
-- through the client (C_Map.GetMapChildrenInfo, documented on both clients; assumed on Forever).
local function clientBestMap(continent, wx, wy)
  local root = Coords.CONTINENT_MAPS[continent]
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
  local uiMapID = C_Map.GetBestMapForUnit("player")
  if not uiMapID then
    return nil
  end
  local pos = C_Map.GetPlayerMapPosition(uiMapID, "player")
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
