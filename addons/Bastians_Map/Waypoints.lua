-- Waypoints and actions (map.md): the own waypoint pin (loud for three seconds, then a faint dot) on
-- the layer map.waypoint, the actions map.show (fly to the entity and highlight it) and chat.way
-- (the /way line into the chat box; no TomTom waypoints since 29.10.2026), the right click on empty
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

local waypoint -- { continent, wx, wy, label, setAt, map, x, y }
local loudTimer
-- What "Show on map" showed last (the map opened on an NPC and nothing
-- of the NPC was on it): { ref, label, icon, continent, points = { { wx, wy } } }, drawn with the
-- entity's own icon and name at every place it fitted, whatever layers are on; gone with the next
-- show, a cleared focus (Esc on the map) or Waypoints.Clear.
local shown

-- The entity's first location in world yards and map fractions, or nil.
local function firstLocation(ref)
  if type(ref) ~= "string" or not B.Entity.Parse(ref) then
    return nil -- a point without an entity (a route step to a spot on the map)
  end
  for _, loc in ipairs(B:Entity(ref):Locations()) do
    local continent, wx, wy = B.Coords.ToWorld(loc.map, loc.x, loc.y)
    if continent then
      return continent, wx, wy, loc.map, loc.x, loc.y
    end
  end
  return nil
end
Waypoints.FirstLocation = firstLocation

-- The entity's name, or nil for a point without an entity.
local function nameOf(ref)
  if type(ref) == "string" and B.Entity.Parse(ref) then
    return B:Entity(ref):Name()
  end
  return nil
end

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
  B:Fire("BASTIANS_WAYPOINT_CHANGED", map, x, y)
end

function Waypoints.Clear()
  local had = waypoint ~= nil
  waypoint = nil
  shown = nil
  if loudTimer then
    loudTimer:Cancel()
    loudTimer = nil
  end
  B:Fire("BASTIANS_LAYER_CHANGED", "map.waypoint")
  if had then
    B:Fire("BASTIANS_WAYPOINT_CHANGED") -- no arguments: there is none now
  end
end

function Waypoints.Shown()
  return shown
end

-- The shown entity: its places on the continent, its icon (the entity's own, else its type's), its
-- name; `label` wins for a point without an entity (a route step's end).
local function setShown(ref, continent, points, label)
  if not continent or #points == 0 then
    shown = nil
    return
  end
  local e = ref and B.Entity.Parse(ref) and B:Entity(ref) or nil
  shown = {
    ref = e and ref or nil,
    label = label or (e and e:Name()) or nil,
    icon = (e and e:Icon()) or B.UI.IconTexture(e and e:Type() or "spot") or B.UI.IconTexture("other"),
    continent = continent,
    points = points,
  }
  -- "show": the layer that draws it switches on when the player had it off (owner, retail
  -- 01.11.2026: "the map I open per right click still has nothing to show on"; Pins' handler)
  B:Fire("BASTIANS_LAYER_CHANGED", "map.waypoint", "show")
end

local function clearShown()
  if shown then
    shown = nil
    B:Fire("BASTIANS_LAYER_CHANGED", "map.waypoint")
  end
end

-- The waypoint, loud (big and bright) for the first seconds, then a faint dot; and the shown entity
-- at every place "Show on map" fitted, above everything else and never clustered.
local function waypointPins(view)
  local pins = {}
  if shown and shown.continent == view.continent then
    for _, p in ipairs(shown.points) do
      pins[#pins + 1] = {
        ref = shown.ref,
        wx = p.wx,
        wy = p.wy,
        icon = shown.icon,
        size = 24,
        label = shown.label,
        priority = 95,
        cluster = false,
      }
    end
  end
  if waypoint and waypoint.continent == view.continent then
    local loud = GetTime() - waypoint.setAt < Waypoints.LOUD_SECONDS
    pins[#pins + 1] = {
      ref = waypoint.map and ("zone:" .. waypoint.map) or nil,
      wx = waypoint.wx,
      wy = waypoint.wy,
      icon = B.UI.IconTexture(loud and "spot" or "other"),
      color = loud and S.C.waypointLoud or S.C.waypoint,
      size = loud and 32 or 8,
      label = loud and not shown and (waypoint.label or L["Waypoint"]) or nil,
      priority = shown and 60 or 90, -- under the shown entity's pin on the same spot
      cluster = false,
      onClick = function(_, button)
        if button == "RightButton" then
          Waypoints.Clear()
        end
      end,
    }
  end
  return pins
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

-- Right click on empty ground: a waypoint at the point and the zone's menu.
-- A right click on empty ground, on the map or the minimap: the waypoint there and the menu of the
-- place (Route here, Note here, ... from the apps that read `ctx.point`).
function Waypoints.PointMenu(continent, wx, wy, source)
  local text, map = Map.Describe(continent, wx, wy)
  Waypoints.Set(continent, wx, wy, text, map)
  B:Say("%s", text)
  if map then
    -- the point travels in the context, so Route can offer "Route here" without the Map knowing it
    B.UI.EntityMenu("zone:" .. map, nil, { source = source or "map", point = { continent, wx, wy, text } })
  end
  return map ~= nil
end

local function onRightClick(sx, sy)
  local cam = Map.Camera()
  if not cam then
    return
  end
  local wx, wy = cam:ToWorld(sx, sy)
  Waypoints.PointMenu(cam.continent, wx, wy)
end

-- The `waypoint` service (core-contracts section 11, #14): the public API reads and sets the
-- player's own waypoint through it.
local service = {
  Get = function()
    return waypoint
  end,
  Set = function(_, continent, wx, wy, label, map, x, y)
    Waypoints.Set(continent, wx, wy, label, map, x, y)
    return true
  end,
  Clear = function()
    Waypoints.Clear()
    return true
  end,
}

function Waypoints.Register(self)
  Map.OnRightClick = onRightClick
  B:ProvideService(self, "waypoint", service, { priority = 100 })
  B:RegisterMapLayer(self, {
    id = "map.waypoint",
    icon = "waypoint", -- the layer bar shows its icon (R27.8)
    label = L["My waypoint"], -- was "Waypoint": it looked like a filter
    tip = L["Your own waypoint: a right click on empty map ground sets it, so does Show on map."],
    defaultOn = true,
    minLevel = 0,
    query = waypointPins,
  })
  B:RegisterAction(self, {
    id = "map.show",
    main = {
      "npc",
      "object",
      "node",
      "quest",
      "chain", -- where the chain is now (its `locations`)
      "dungeon",
      "spot",
      "area",
      "entrance",
      "flightpath",
      "transport",
    }, -- a button of the sheet (ADR 0054)
    label = L["Show on map"],
    short = L["Map"], -- the band's button
    icon = B.UI.IconTexture("zone"),
    types = "*",
    order = 10,
    when = function(ref, ctx)
      -- a point in the context needs no entity (a route step to a
      -- spot raised "Entity: nil"); places named by the caller need no place of its own (an item
      -- a quest asks for: where its droppers are, Forever 09.11.2026)
      return (ctx ~= nil and (ctx.point ~= nil or ctx.points ~= nil)) or firstLocation(ref) ~= nil
    end,
    run = function(ref, ctx)
      local point = ctx and ctx.point
      local places = ctx and ctx.points -- { { map, x, y } or { continent, wx, wy }, ... } (R7)
      local continent, wx, wy, map, x, y = firstLocation(ref)
      -- the entity is the focus (ADR 0013 D: the ring, the strip, the Browser's page when it is
      -- open); the caller's source stays in the context so the Browser does not reopen its own page
      local function focus()
        if type(ref) == "string" and B.Entity.Parse(ref) then
          B:Focus(ref, { source = ctx and ctx.source or "map.show" })
        end
      end
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
        local went = Map.FitWorld(continent, pts, math.max(Map.Camera().level, Waypoints.SHOW_LEVEL))
        setShown(ref, continent, pts)
        if went then
          Waypoints.Set(continent, went.wx, went.wy, nameOf(ref))
        else
          Waypoints.Set(continent, wx, wy, nameOf(ref), map, x, y)
        end
        focus()
        return
      end
      if not (point or continent) then
        return
      end
      ns.Layers.Reveal(ref) -- a dungeon's layer comes on with it
      Map.Open() -- before the camera is read: the map builds on its first open
      local level = math.max(Map.Camera().level, Waypoints.SHOW_LEVEL)
      if point then
        -- the caller names the place (a route step's end): that point, not the entity's places
        Map.Fly(point[1], point[2], point[3], level)
        setShown(ref, point[1], { { wx = point[2], wy = point[3] } }, point[4])
        Waypoints.Set(point[1], point[2], point[3], point[4] or nameOf(ref))
        focus()
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
      local went = Map.FitWorld(continent, points, level)
      setShown(ref, continent, points)
      if went then -- the waypoint where the view went, not on the far group
        Waypoints.Set(continent, went.wx, went.wy, B:Entity(ref):Name())
      else
        Waypoints.Set(continent, wx, wy, B:Entity(ref):Name(), map, x, y)
      end
      focus()
    end,
  })
  -- a zone has no place of its own: "Show on map" opens the map on the whole zone (owner,
  -- 22.10.2026: zone pages had no way to the map), the view fitted to its corners
  B:RegisterAction(self, {
    id = "map.zone",
    main = true, -- a button of the sheet (ADR 0054)
    label = L["Show on map"],
    short = L["Map"],
    icon = B.UI.IconTexture("zone"),
    types = { "zone" },
    order = 10,
    when = function(ref, ctx)
      if ctx and ctx.point then
        -- a point on the ground: map.show flies to that very point, one "Show on map" (owner,
        -- Forever 07.11.2026: the ground's menu said it twice)
        return false
      end
      local map = tonumber(string.match(ref, "^zone:(%d+)$"))
      return map ~= nil and B.Coords.ToWorld(map, 0.5, 0.5) ~= nil
    end,
    run = function(ref)
      local map = tonumber(string.match(ref, "^zone:(%d+)$"))
      Map.ShowUiMap(map, Waypoints.ZONE_LEVEL)
    end,
  })
  B:RegisterAction(self, {
    id = "chat.way",
    main = { "object", "node" }, -- a button of the sheet (ADR 0054)
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
    if not ref then
      clearShown() -- Esc on the map: the shown entity goes with the focus
      return
    end
    if not Map.IsShown() or (ctx and ctx.source == "map") then
      return
    end
    if shown and shown.ref == ref then
      return -- map.show placed the waypoint (a step's end, a quest's targets) and focused: keep it
    end
    clearShown() -- another entity took the focus (a pin, the Browser): the old one is done
    local continent, wx, wy, map, x, y = firstLocation(ref)
    local cam = Map.Camera()
    if continent and cam and cam.continent == continent and cam:Contains(wx, wy, 0) then
      Waypoints.Set(continent, wx, wy, B:Entity(ref):Name(), map, x, y) -- highlight if visible
    end
  end)
end

table.insert(Map.onEnable, Waypoints.Register)

-- the player's waypoint was set (uiMapID, x, y; x and y nil off every map) or cleared (no
-- arguments); public (Bastians.API.EVENTS)
B:DeclareMessage("BASTIANS_WAYPOINT_CHANGED")
ns.mod.Waypoints = Waypoints
