-- The minimap overlay (map.md "The minimap overlay", S5, 22.10.2026): the map's layers on the
-- game's minimap, the nearest N pins around the player, pins beyond the minimap's rim drawn at
-- the rim with a small arrow pointing their way, and the path pins (the route's legs, S6) as line
-- pieces inside the rim. The layers are queried once per place (a view of
-- QUERY_RANGE yards around the player, re-queried when the player moved half of it, when a layer
-- changes or the zone changes); the pins are moved ten times a second while the player moves,
-- turns (with a rotating minimap) or flies, told by the movement events: nothing ticks while the
-- player stands (nfr.md: no OnUpdate while idle).
-- The yards a minimap shows per zoom step are the client's own figures (HereBeDragons measures
-- them the same way); indoors is told from the two zoom cvars as HereBeDragons does.
-- A host other than the game's minimap (MM.SetHost: Bastian's minimap drawing one of our styles,
-- Mini.lua) gives its own centre, scale, size and shape; north stays up there.
-- The minimap search's mark (MM.SetMark, map.md "The minimap search", L4) is one more pin above
-- the layers' pins, drawn at any distance (on the rim when far) and also with the layers off.
-- The live pins (MM.SetLive: the game's tracked dots read back on our styles, Tracked.lua) are no
-- layer's either: drawn with the layers off, beside the nearest N and above them.
local _, ns = ...
local B = Bastians
local S = B.UI.Style
local Map = ns.Map

local MM = {}
ns.Minimap = MM

MM.QUERY_RANGE = 600 -- yards around the player a query covers (edge arrows reach this far)
MM.QUERY_LEVEL = 6 -- the view level the layers are asked at: the finest, so every layer answers
MM.TICK = 0.1 -- seconds between two pin moves
MM.PIN_SIZE = 14
MM.EDGE_SIZE = 10
MM.EDGE_INSET = 7 -- pixels the rim pins keep from the minimap's edge
MM.MARK_SIZE = 20 -- the search's mark, on a disc MARK_RING pixels wider
MM.MARK_RING = 8
MM.MARK_SAME = 2 -- yards: a layer pin of the marked entity this close is the mark's double
MM.PIECE = 10 -- pixels of one line piece of a path; a piece is drawn when its middle is inside the rim
MM.MAX_PIECES = 80
-- Yards across the minimap per zoom step (0 = farthest), outdoors and indoors.
MM.DIAMETER = {
  outdoor = { [0] = 466.67, 400, 333.33, 266.67, 200, 133.33 },
  indoor = { [0] = 300, 240, 180, 120, 80, 50 },
}

local mod, frame
local pool = {} -- the pin buttons, pooled
MM.pool = pool
local pieces = {} -- the line textures of the paths, pooled
MM.pieces = pieces
local pins = {} -- the nearest pins of the last query, with their world coordinates
local paths = {} -- the path pins of the last query (points in world yards)
local center -- { continent, wx, wy } of the last query
local mark -- the search's mark: { ref, continent, wx, wy, icon, color, label, card } or nil
local live = {} -- the live pins: { ref, continent, wx, wy, icon, color, label, card } each
local host -- nil: the game's minimap; else { frame, Center(), Scale(), Half(), Shape() }
local indoors = false
local elapsed = 0
local moving, turning, ticking = false, false, false
local byKey = false -- hidden by the clear-screen key (MM.HideByKey)
MM.stats = { shown = 0, edge = 0, queried = 0, pieces = 0 }

local function db()
  return mod.db.profile
end

-- Cvars: C_CVar on the retail family (both clients), the legacy globals as the fallback.
local function cvar(name)
  local api = rawget(_G, "C_CVar")
  if api and api.GetCVar then
    return api.GetCVar(name)
  end
  local f = rawget(_G, "GetCVar")
  return f and f(name) or nil
end

local function cvarBool(name)
  local v = cvar(name)
  return v == "1" or v == true
end

local function enabled()
  return mod ~= nil and db().minimapPins == true
end

-- ---------------------------------------------------------------------------------------------
-- The minimap's scale and shape
-- ---------------------------------------------------------------------------------------------

-- Indoors or outdoors, told from the zoom: the client keeps one zoom cvar for each; the one the
-- minimap's zoom equals is where the player is (HereBeDragons' way). Called on MINIMAP_UPDATE_ZOOM.
-- Probes only on the zone and indoor events, never on MINIMAP_UPDATE_ZOOM: the client answers every
-- zoom change with that event, and the probe below changes the zoom twice, so a probe from the
-- event fed itself every frame for a whole session (Map: 33 calls and 82 ms a second, owner
-- Forever 23.10.2026). When the outdoor and indoor cvars differ the minimap's zoom answers alone.
MM.probes = 0
function MM.UpdateZoom(probe)
  if not (Minimap and Minimap.GetZoom) then
    return
  end
  local zoom = Minimap:GetZoom()
  if cvar("minimapZoom") ~= cvar("minimapInsideZoom") then
    indoors = tonumber(cvar("minimapZoom")) ~= zoom -- no zoom change: safe from any event
    return
  end
  if probe == false then
    return -- equal cvars: only a zone or indoor event may probe
  end
  MM.probes = MM.probes + 1
  Minimap:SetZoom(zoom < 2 and zoom + 1 or zoom - 1)
  indoors = tonumber(cvar("minimapZoom")) ~= Minimap:GetZoom()
  Minimap:SetZoom(zoom)
end

function MM.Indoors()
  return indoors
end

-- Pixels per yard at the current zoom.
function MM.Scale()
  local zoom = (Minimap and Minimap.GetZoom and Minimap:GetZoom()) or 0
  local table_ = indoors and MM.DIAMETER.indoor or MM.DIAMETER.outdoor
  local yards = table_[zoom] or table_[0]
  return (Minimap:GetWidth() or 140) / yards
end

local function shape()
  local f = rawget(_G, "GetMinimapShape")
  local s = f and f() or "ROUND"
  return s == "ROUND" and "ROUND" or "SQUARE"
end

-- A world point as dx right, dy up in pixels from the minimap's centre.
function MM.Project(wx, wy, px, py, scale, facing)
  local east, north = -(wy - py), wx - px
  if facing then
    local c, s = math.cos(facing), math.sin(facing)
    east, north = east * c + north * s, -east * s + north * c
  end
  return east * scale, north * scale
end

-- Where a pin lands on the minimap: dx right, dy up in pixels from the centre, and whether it
-- had to be pulled to the rim. World wx grows north and wy west; the minimap may rotate with the
-- player's facing (cvar rotateMinimap), a clockwise turn by the facing puts "ahead" up.
function MM.Place(pin, px, py, scale, facing, half, shapeName)
  local east, north = -(pin.wy - py), pin.wx - px
  if facing then
    local c, s = math.cos(facing), math.sin(facing)
    east, north = east * c + north * s, -east * s + north * c
  end
  local dx, dy = east * scale, north * scale
  local limit = half - MM.EDGE_INSET
  if shapeName == "ROUND" then
    local d = math.sqrt(dx * dx + dy * dy)
    if d > limit then
      return dx * limit / d, dy * limit / d, true, math.atan2(dy, dx)
    end
    return dx, dy, false, nil
  end
  local m = math.max(math.abs(dx), math.abs(dy))
  if m > limit then
    local k = limit / m
    return dx * k, dy * k, true, math.atan2(dy, dx)
  end
  return dx, dy, false, nil
end

local function onTaxi()
  local f = rawget(_G, "UnitOnTaxi")
  return f ~= nil and f("player") == true
end

-- Whether the pins have to follow the player right now.
local function inMotion()
  return moving or (turning and cvarBool("rotateMinimap")) or onTaxi()
end

-- ---------------------------------------------------------------------------------------------
-- Pins
-- ---------------------------------------------------------------------------------------------

local function pinButton(i)
  local f = pool[i]
  if not f then
    f = CreateFrame("Button", nil, frame)
    f:SetSize(MM.PIN_SIZE, MM.PIN_SIZE)
    f.arrow = f:CreateTexture(nil, "BACKGROUND")
    f.arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
    f.arrow:SetSize(MM.EDGE_SIZE + 4, MM.EDGE_SIZE + 4)
    f.arrow:SetPoint("CENTER")
    f.arrow:Hide()
    f.ring = f:CreateTexture(nil, "BORDER") -- the mark's disc (S.DISC in the accent)
    f.ring:SetTexture(S.DISC)
    S.tint(f.ring, S.C.accent, 0.55)
    f.ring:SetPoint("CENTER")
    f.ring:Hide()
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:SetScript("OnClick", ns.Pins.ClickPin)
    f:SetScript("OnEnter", ns.Pins.HoverPin)
    f:SetScript("OnLeave", ns.Pins.LeavePin)
    pool[i] = f
  end
  return f
end

local function hideFrom(n)
  for i = n + 1, #pool do
    local f = pool[i]
    if f then
      f.pin = nil
      f:Hide()
    end
  end
end

local function pieceTexture(i)
  local t = pieces[i]
  if not t then
    t = frame:CreateTexture(nil, "BORDER")
    t:SetTexture(S.WHITE)
    pieces[i] = t
  end
  return t
end

local function hidePiecesFrom(n)
  for i = n + 1, #pieces do
    pieces[i]:Hide()
  end
end

-- The paths as line pieces: every leg cut into PIECE pixel pieces, a piece drawn when its middle
-- is inside the rim (a dashed path draws every other piece). Returns how many were drawn.
local function drawPaths(px, py, scale, facing, half, shapeName)
  local n = 0
  local limit = half - MM.EDGE_INSET
  for _, path in ipairs(paths) do
    local color = path.color or S.C.accent
    local width = math.max(1, math.min(3, path.width or 2))
    local points = path.points
    for i = 2, #points do
      local x1, y1 = MM.Project(points[i - 1][1], points[i - 1][2], px, py, scale, facing)
      local x2, y2 = MM.Project(points[i][1], points[i][2], px, py, scale, facing)
      local dx, dy = x2 - x1, y2 - y1
      local length = math.sqrt(dx * dx + dy * dy)
      local count = math.max(1, math.ceil(length / MM.PIECE))
      local angle = math.atan2(dy, dx)
      for k = 0, count - 1 do
        if n >= MM.MAX_PIECES then
          return n
        end
        if not (path.style == "dashed" and k % 2 == 1) then
          local t0, t1 = k / count, (k + 1) / count
          local mx, my = x1 + dx * (t0 + t1) / 2, y1 + dy * (t0 + t1) / 2
          local inside
          if shapeName == "ROUND" then
            inside = mx * mx + my * my <= limit * limit
          else
            inside = math.abs(mx) <= limit and math.abs(my) <= limit
          end
          if inside then
            n = n + 1
            local t = pieceTexture(n)
            t:SetSize(length * (t1 - t0), width)
            S.tint(t, color, color[4] or 0.85)
            t:SetRotation(angle)
            t:ClearAllPoints()
            t:SetPoint("CENTER", frame, "CENTER", mx, my)
            t:Show()
          end
        end
      end
    end
  end
  return n
end

-- The point the overlay is centred on: the player on the game's minimap, the view's centre on a
-- host (it may be dragged away from the player).
local function viewCenter()
  if host then
    return host.Center()
  end
  return B.Coords.Player()
end

-- Move every pin to its place around the player; rim pins shrink and show the arrow.
function MM.Reposition()
  if not (frame and frame:IsShown()) then
    return
  end
  local continent, px, py = viewCenter()
  if not continent or (center and continent ~= center[1]) then
    hideFrom(0)
    hidePiecesFrom(0)
    MM.stats.shown, MM.stats.edge, MM.stats.pieces = 0, 0, 0
    return
  end
  local scale, half, facing, shapeName
  if host then
    scale, half, shapeName = host.Scale(), host.Half(), host.Shape()
  else
    scale = MM.Scale()
    half = (Minimap:GetWidth() or 140) / 2
    facing = cvarBool("rotateMinimap") and (B.Compat.GetPlayerFacing() or 0) or nil
    shapeName = shape()
  end
  local edge = 0
  for i, pin in ipairs(pins) do
    local f = pinButton(i)
    local dx, dy, onEdge, angle = MM.Place(pin, px, py, scale, facing, half, shapeName)
    f.pin = pin
    B.UI.PaintIcon(f.icon, pin.icon or B.UI.IconTexture("other"))
    if pin.color then
      S.tint(f.icon, pin.color, 1)
    end
    -- the mark on top, a live pin above the layers' (a tracked herb on its known place)
    f:SetFrameLevel((frame:GetFrameLevel() or 0) + (pin.isMark and 3 or pin.isLive and 2 or 1))
    f.ring:SetShown(pin.isMark == true and not onEdge)
    if onEdge then
      edge = edge + 1
      f:SetSize(MM.EDGE_SIZE, MM.EDGE_SIZE)
      f:SetAlpha(0.8)
      -- the game's arrow texture points up at rotation 0; turn it outward
      f.arrow:SetRotation(angle - math.pi / 2)
      local c = pin.color or S.C.accent
      S.tint(f.arrow, c, 0.9)
      f.arrow:Show()
    else
      local size = pin.isMark and MM.MARK_SIZE or MM.PIN_SIZE
      f:SetSize(size, size)
      f.ring:SetSize(size + MM.MARK_RING, size + MM.MARK_RING)
      f:SetAlpha(1)
      f.arrow:Hide()
    end
    f:ClearAllPoints()
    f:SetPoint("CENTER", frame, "CENTER", dx, dy)
    f:Show()
  end
  hideFrom(#pins)
  local drawn = drawPaths(px, py, scale, facing, half, shapeName)
  hidePiecesFrom(drawn)
  MM.stats.shown, MM.stats.edge, MM.stats.pieces = #pins, edge, drawn
end

-- The mark as a pin of the overlay.
local function markPin(px, py)
  local dx, dy = mark.wx - px, mark.wy - py
  return {
    ref = mark.ref,
    wx = mark.wx,
    wy = mark.wy,
    icon = mark.icon,
    color = mark.color,
    label = mark.label,
    card = mark.card,
    isMark = true,
    distance = math.sqrt(dx * dx + dy * dy),
  }
end

-- Whether a layer's pin is the mark's double (the same entity on the same spot).
local function isMarked(pin)
  if not (mark and pin.ref and pin.ref == mark.ref) then
    return false
  end
  local dx, dy = pin.wx - mark.wx, pin.wy - mark.wy
  return dx * dx + dy * dy <= MM.MARK_SAME * MM.MARK_SAME
end

-- Ask every enabled layer for the pins around the player, keep the nearest N; the mark first,
-- then the live pins, all of them.
function MM.Query()
  pins = {}
  paths = {}
  center = nil
  if not frame or byKey then
    return -- hidden by the key: nothing drawn until the key brings it back
  end
  local on = enabled()
  if not (on or mark or #live > 0) then
    hideFrom(0)
    hidePiecesFrom(0)
    frame:Hide()
    return
  end
  local continent, px, py = viewCenter()
  if not continent then
    frame:Hide() -- an instance: nothing to show, no ticks until the next zone or world event
    MM.stats.shown, MM.stats.edge, MM.stats.queried, MM.stats.pieces = 0, 0, 0, 0
    return
  end
  center = { continent, px, py }
  local r = MM.QUERY_RANGE
  local view = {
    continent = continent,
    x1 = px - r,
    y1 = py - r,
    x2 = px + r,
    y2 = py + r,
    level = MM.QUERY_LEVEL,
    player = center,
    minimap = true,
  }
  local found = {}
  for _, def in ipairs(on and B:GetMapLayers() or {}) do
    if ns.Pins.IsLayerOn(def) then
      for _, pin in ipairs(B:QueryLayer(def.id, view)) do
        if pin.kind == "path" and pin.points and #pin.points >= 2 then
          paths[#paths + 1] = pin
        elseif pin.wx and pin.wy and pin.kind ~= "path" and pin.ref then
          local dx, dy = pin.wx - px, pin.wy - py
          pin.distance = math.sqrt(dx * dx + dy * dy)
          if pin.distance <= r and not isMarked(pin) then
            found[#found + 1] = pin
          end
        end
      end
    end
  end
  table.sort(found, function(a, b)
    if a.distance ~= b.distance then
      return a.distance < b.distance
    end
    return tostring(a.ref) < tostring(b.ref)
  end)
  if mark and mark.continent == continent then
    pins[1] = markPin(px, py)
  end
  for _, pin in ipairs(live) do
    if pin.continent == continent then
      local dx, dy = pin.wx - px, pin.wy - py
      pin.distance = math.sqrt(dx * dx + dy * dy)
      pin.isLive = true
      pins[#pins + 1] = pin
    end
  end
  local max = db().minimapMax or 20
  for i = 1, math.min(max, #found) do
    pins[#pins + 1] = found[i]
  end
  MM.stats.queried = #found
  frame:Show()
  MM.Reposition()
  if inMotion() then
    MM.StartTicks() -- the player is on the move already; a standing player starts nothing
  end
end

function MM.Pins()
  return pins
end

-- A layer changed, the zone changed, the settings changed: one query, coalesced.
function MM.Schedule()
  if mod and (enabled() or #live > 0) then
    mod:Coalesce("minimap", 0.1, MM.Query)
  end
end

local function stopTicks()
  if ticking and frame then
    frame:SetScript("OnUpdate", nil)
    ticking = false
  end
end

local onUpdate

-- Ticks run only while the player is in motion and the overlay shows; they stop themselves.
function MM.StartTicks()
  if frame and frame:IsShown() and not ticking then
    frame:SetScript("OnUpdate", onUpdate)
    ticking = true
    elapsed = MM.TICK
  end
end

function MM.Ticking()
  return ticking
end

onUpdate = function(_, dt)
  elapsed = elapsed + dt
  if elapsed < MM.TICK then
    return
  end
  elapsed = 0
  if not center then
    stopTicks()
    return
  end
  local continent, px, py = viewCenter()
  if continent ~= center[1] then
    MM.Schedule()
    return
  end
  if continent then
    local dx, dy = px - center[2], py - center[3]
    if dx * dx + dy * dy > (MM.QUERY_RANGE / 2) ^ 2 then
      MM.Schedule()
      return
    end
  end
  MM.Reposition()
  if not inMotion() then
    stopTicks() -- one last move after the stop, then nothing until the next movement event
  end
end

local function build()
  local over = host and host.frame or Minimap
  frame = CreateFrame("Frame", "BastiansMinimapOverlay", over)
  frame:SetAllPoints(over)
  frame:SetFrameLevel((over:GetFrameLevel() or 0) + 5)
  frame:Hide()
  MM.frame = frame
end

-- The minimap search's mark (Mini.lua): { ref, continent, wx, wy, icon, color, label, card }, or
-- nil to clear it. Drawn at once, with or without the layers on the minimap.
function MM.SetMark(m)
  if not (mod and mod:IsEnabled()) then
    mark = nil
    return
  end
  mark = m
  if m and not frame then
    build()
  end
  if frame then
    MM.Query()
  end
end

function MM.Mark()
  return mark
end

-- The live pins (Tracked.lua): a list of { ref, continent, wx, wy, icon, color, label, card },
-- empty to clear them. Drawn with or without the layers on the minimap, never counted against the
-- nearest N; one query, coalesced (a sweep changes several at once).
function MM.SetLive(list)
  local had = #live > 0
  live = mod and mod:IsEnabled() and list or {}
  if not mod or not (had or #live > 0) then
    return
  end
  if not frame then
    build()
  end
  mod:Coalesce("minimap", 0.1, MM.Query)
end

function MM.Live()
  return live
end

-- Puts the overlay on a host (nil: back on the game's minimap) and asks the layers again.
function MM.SetHost(newHost)
  host = newHost
  if frame then
    local over = host and host.frame or Minimap
    frame:SetParent(over)
    frame:ClearAllPoints()
    frame:SetAllPoints(over)
    frame:SetFrameLevel((over:GetFrameLevel() or 0) + 5)
  end
  MM.Schedule()
end

function MM.Host()
  return host
end

-- The clear-screen key (plan-round4 F1, BASTIANS_SUITE_HIDDEN; plan-launch-review R5.6,
-- 01.11.2026): the pins, their rim arrows and the path pieces go with the suite, on the game's
-- minimap and on Bastian's (the host); no ticks, no queries while hidden. The key's return asks the
-- layers again; the setting switched off stays off.
function MM.HideByKey(hidden)
  if hidden then
    byKey = true
    hideFrom(0)
    hidePiecesFrom(0)
    stopTicks()
    pins, paths, center = {}, {}, nil
    MM.stats.shown, MM.stats.edge, MM.stats.pieces = 0, 0, 0
    if frame then
      frame:Hide()
    end
  elseif byKey then
    byKey = false
    MM.Query()
  end
end

function MM.HiddenByKey()
  return byKey
end

-- The setting decides: on builds the frame once and queries, off hides everything.
function MM.Apply()
  if not mod then
    return
  end
  if enabled() then
    if not frame then
      build()
    end
    MM.UpdateZoom()
    MM.Query()
  elseif frame then
    hideFrom(0)
    hidePiecesFrom(0)
    pins, paths, center = {}, {}, nil
    MM.stats.shown, MM.stats.edge, MM.stats.queried, MM.stats.pieces = 0, 0, 0, 0
    stopTicks()
    frame:Hide()
    if mark or #live > 0 then
      MM.Query() -- the search's mark and the live pins stay without the layers
    end
  end
end

table.insert(Map.onEnable, function(self)
  mod = self
  self:RegisterEvent("MINIMAP_UPDATE_ZOOM", function()
    MM.UpdateZoom(false) -- never a probe here: it would answer with this event again
    MM.Reposition()
  end)
  self:RegisterEvent("ZONE_CHANGED_NEW_AREA", MM.Schedule)
  -- movement (retail family events, assumed on Forever until seen: forever-api.md); the subzone
  -- events move the pins once as the fallback when the movement events never come
  self:RegisterEvent("PLAYER_STARTED_MOVING", function()
    moving = true
    MM.StartTicks()
  end)
  self:RegisterEvent("PLAYER_STOPPED_MOVING", function()
    moving = false
  end)
  self:RegisterEvent("PLAYER_STARTED_TURNING", function()
    turning = true
    if cvarBool("rotateMinimap") then
      MM.StartTicks()
    end
  end)
  self:RegisterEvent("PLAYER_STOPPED_TURNING", function()
    turning = false
  end)
  self:RegisterEvent("PLAYER_CONTROL_LOST", MM.StartTicks) -- a flight: UnitOnTaxi keeps the ticks
  self:RegisterEvent("ZONE_CHANGED", function()
    MM.Reposition()
    MM.StartTicks()
  end)
  self:RegisterEvent("ZONE_CHANGED_INDOORS", function()
    MM.UpdateZoom() -- in or out of a building: the zoom table changes
    MM.Reposition()
    MM.StartTicks()
  end)
  -- enabled while the key hides the suite: hidden until the key comes back
  local Screen = B.UI.Screen
  byKey = Screen ~= nil and Screen.Hidden ~= nil and Screen.Hidden() and Screen.Hides("Map") or false
  MM.Apply()
end)
-- once at load, not per enable (the Map runs these lists from its one handler per event)
table.insert(Map.onWorld, function()
  MM.UpdateZoom()
  MM.Schedule()
end)
table.insert(Map.onZone, MM.Schedule)
table.insert(Map.onSetting, function(key)
  if key == "minimapPins" or key == "minimapMax" then
    MM.Apply()
  end
end)
table.insert(Map.onLayerChanged, MM.Schedule)
table.insert(Map.onSuiteHidden, MM.HideByKey)
table.insert(Map.onDisable, function()
  mark = nil
  live = {}
  if frame then
    hideFrom(0)
    hidePiecesFrom(0)
    stopTicks()
    frame:Hide()
  end
  pins, paths, center = {}, {}, nil
end)

ns.mod.Minimap = MM -- reachable through the module, for the tests
