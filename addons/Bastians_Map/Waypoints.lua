-- Waypoints and actions (map.md): the own waypoint pin (loud for three seconds, then a faint dot) on
-- the layer map.waypoint, the actions map.show (fly to the entity and highlight it), tomtom.waypoint
-- (when TomTom is loaded) and chat.way (the /way line into the chat box), the right click on empty
-- ground ("what's here": the zone's menu and a waypoint at the point), and BASTIANS_ENTITY_FOCUSED.
-- Blizzard's user waypoints are never used (CLAUDE.md golden rule 6).
local _, ns = ...
local B = Bastians
local S = B.UI.Style
local L = ns.L
local Map = ns.Map

local Waypoints = {}
ns.Waypoints = Waypoints

Waypoints.LOUD_SECONDS = 3
Waypoints.SHOW_LEVEL = 5
Waypoints.ZONE_LEVEL = 3 -- "Show on map" of a zone starts here and fits the zone from there
Waypoints.FIT_MAX = 12 -- places "Show on map" fits into the view at most

local mod
local waypoint -- { continent, wx, wy, label, setAt, map, x, y }
local loudTimer

-- The entity's first location in world yards and map fractions, or nil.
local function firstLocation(ref)
  for _, loc in ipairs(B:Entity(ref):Locations()) do
    local continent, wx, wy = B.Coords.ToWorld(loc.map, loc.x, loc.y)
    if continent then
      return continent, wx, wy, loc.map, loc.x, loc.y
    end
  end
  return nil
end
Waypoints.FirstLocation = firstLocation

function Waypoints.Get()
  return waypoint
end

function Waypoints.Set(continent, wx, wy, label, map, x, y)
  if not (map and x) then
    map = B.Coords.BestMap(continent, wx, wy)
    if map then
      x, y = B.Coords.ToMap(continent, wx, wy, map)
    end
  end
  waypoint =
    { continent = continent, wx = wx, wy = wy, label = label, setAt = GetTime(), map = map, x = x, y = y }
  if loudTimer then
    loudTimer:Cancel()
  end
  loudTimer = C_Timer.NewTimer(Waypoints.LOUD_SECONDS, function()
    loudTimer = nil
    B:Fire("BASTIANS_LAYER_CHANGED", "map.waypoint") -- the pin turns into the faint dot
  end)
  B:Fire("BASTIANS_LAYER_CHANGED", "map.waypoint")
end

function Waypoints.Clear()
  waypoint = nil
  if loudTimer then
    loudTimer:Cancel()
    loudTimer = nil
  end
  B:Fire("BASTIANS_LAYER_CHANGED", "map.waypoint")
end

-- Loud: big and bright for the first seconds; then a faint dot.
local function waypointPins(view)
  if not (waypoint and waypoint.continent == view.continent) then
    return {}
  end
  local loud = GetTime() - waypoint.setAt < Waypoints.LOUD_SECONDS
  return {
    {
      ref = waypoint.map and ("zone:" .. waypoint.map) or nil,
      wx = waypoint.wx,
      wy = waypoint.wy,
      icon = B.UI.IconTexture(loud and "spot" or "other"),
      color = loud and S.C.waypointLoud or S.C.waypoint,
      size = loud and 32 or 8,
      label = loud and (waypoint.label or L["Waypoint"]) or nil,
      priority = 90,
      cluster = false,
      onClick = function(_, button)
        if button == "RightButton" then
          Waypoints.Clear()
        end
      end,
    },
  }
end

-- "/way Elwynn Forest 42.0 65.0" for a point, through the zone the point lies in.
function Waypoints.WayLine(continent, wx, wy, label)
  local text, map, x, y = Map.Describe(continent, wx, wy)
  if not (map and x) then
    return nil
  end
  local name = string.match(text, "^(.-) %d") or text
  local line = string.format("/way %s %.1f %.1f", name, x * 100, y * 100)
  if label then
    line = line .. " " .. label
  end
  return line
end

local function tomtom()
  local tt = _G.TomTom
  if type(tt) == "table" and type(tt.AddWaypoint) == "function" then
    return tt
  end
  return nil
end

function Waypoints.HasTomTom()
  return tomtom() ~= nil
end

-- Right click on empty ground: a waypoint at the point and the zone's menu.
local function onRightClick(sx, sy)
  local cam = Map.Camera()
  if not cam then
    return
  end
  local wx, wy = cam:ToWorld(sx, sy)
  local text, map = Map.Describe(cam.continent, wx, wy)
  Waypoints.Set(cam.continent, wx, wy, text, map)
  B:Say("%s", text)
  if map then
    -- the point travels in the context, so Route can offer "Route here" without the Map knowing it
    B.UI.EntityMenu("zone:" .. map, nil, { source = "map", point = { cam.continent, wx, wy, text } })
  end
end

function Waypoints.Register(self)
  mod = self
  Map.OnRightClick = onRightClick
  B:RegisterMapLayer(self, {
    id = "map.waypoint",
    label = L["Waypoint"],
    defaultOn = true,
    minLevel = 0,
    query = waypointPins,
  })
  B:RegisterAction(self, {
    id = "map.show",
    label = L["Show on map"],
    icon = B.UI.IconTexture("zone"),
    types = "*",
    order = 10,
    when = function(ref)
      return firstLocation(ref) ~= nil
    end,
    run = function(ref, ctx)
      local point = ctx and ctx.point
      local places = ctx and ctx.points -- { { map, x, y } or { continent, wx, wy }, ... } (R7)
      local continent, wx, wy, map, x, y = firstLocation(ref)
      if places and #places > 0 then
        -- the caller names the places (a quest's giver, targets or hand-in): those, not the
        -- entity's own; the first one gets the waypoint
        local pts = {}
        continent, wx, wy, map, x, y = nil, nil, nil, nil, nil, nil
        for i, p in ipairs(places) do
          local c, px, py
          if p.map then
            c, px, py = B.Coords.ToWorld(p.map, p.x, p.y)
          else
            c, px, py = p[1], p[2], p[3]
          end
          if c and (continent == nil or c == continent) and i <= Waypoints.FIT_MAX then
            continent = continent or c
            pts[#pts + 1] = { wx = px, wy = py }
            if not wx then
              wx, wy, map, x, y = px, py, p.map, p.x, p.y
            end
          end
        end
        if not continent then
          return
        end
        Map.Open()
        Map.FitWorld(continent, pts, math.max(Map.Camera().level, Waypoints.SHOW_LEVEL))
        Waypoints.Set(continent, wx, wy, B:Entity(ref):Name(), map, x, y)
        return
      end
      if not (point or continent) then
        return
      end
      Map.Open() -- before the camera is read: the map builds on its first open
      local level = math.max(Map.Camera().level, Waypoints.SHOW_LEVEL)
      if point then
        -- the caller names the place (a route step's end): that point, not the entity's places
        Map.Fly(point[1], point[2], point[3], level)
        Waypoints.Set(point[1], point[2], point[3], point[4] or B:Entity(ref):Name())
        return
      end
      -- every place on that continent (a quest's giver and targets, an NPC's spawn areas,
      -- ): the view centres on them at the player's zoom, zoomed in to
      -- SHOW_LEVEL at least and never out (Map.FitWorld); the waypoint marks the first
      local points = {}
      for i, loc in ipairs(B:Entity(ref):Locations()) do
        if i > Waypoints.FIT_MAX then
          break
        end
        local c, px, py = B.Coords.ToWorld(loc.map, loc.x, loc.y)
        if c == continent then
          points[#points + 1] = { wx = px, wy = py }
        end
      end
      Map.FitWorld(continent, points, level)
      Waypoints.Set(continent, wx, wy, B:Entity(ref):Name(), map, x, y)
    end,
  })
  -- a zone has no place of its own: "Show on map" opens the map on the whole zone (owner,
  -- 22.10.2026: zone pages had no way to the map), the view fitted to its corners
  B:RegisterAction(self, {
    id = "map.zone",
    label = L["Show on map"],
    icon = B.UI.IconTexture("zone"),
    types = { "zone" },
    order = 10,
    when = function(ref)
      local map = tonumber(string.match(ref, "^zone:(%d+)$"))
      return map ~= nil and B.Coords.ToWorld(map, 0.5, 0.5) ~= nil
    end,
    run = function(ref)
      local map = tonumber(string.match(ref, "^zone:(%d+)$"))
      Map.ShowUiMap(map, Waypoints.ZONE_LEVEL)
    end,
  })
  B:RegisterAction(self, {
    id = "tomtom.waypoint",
    label = L["TomTom waypoint"],
    icon = B.UI.IconTexture("route"),
    types = "*",
    order = 80,
    when = function(ref)
      return Waypoints.HasTomTom() and firstLocation(ref) ~= nil
    end,
    run = function(ref)
      local _, _, _, map, x, y = firstLocation(ref)
      local tt = tomtom()
      if tt and map then
        local uid = tt:AddWaypoint(map, x, y, { title = B:Entity(ref):Name() or ref, persistent = false })
        mod.lastTomTom = uid
      end
    end,
  })
  B:RegisterAction(self, {
    id = "chat.way",
    label = L["Copy /way"],
    icon = B.UI.IconTexture("other"),
    types = "*",
    order = 85,
    when = function(ref)
      return firstLocation(ref) ~= nil
    end,
    run = function(ref)
      local continent, wx, wy = firstLocation(ref)
      local line = continent and Waypoints.WayLine(continent, wx, wy, B:Entity(ref):Name()) or nil
      if line then
        B.Compat.OpenChat(line)
      end
    end,
  })
  table.insert(Map.onFocus, function(ref, ctx)
    if not ref or not Map.IsShown() or (ctx and ctx.source == "map") then
      return
    end
    local continent, wx, wy, map, x, y = firstLocation(ref)
    local cam = Map.Camera()
    if continent and cam and cam.continent == continent and cam:Contains(wx, wy, 0) then
      Waypoints.Set(continent, wx, wy, B:Entity(ref):Name(), map, x, y) -- highlight if visible
    end
  end)
end

table.insert(Map.onEnable, Waypoints.Register)
ns.mod.Waypoints = Waypoints
