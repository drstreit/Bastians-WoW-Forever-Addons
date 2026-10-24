-- Bastian's Map (map.md): the window with one camera per continent in world yards; mouse wheel zooms
-- to the cursor, dragging pans, double-click zooms in, arrow keys pan and +/- zoom; the footer shows
-- the zone and map percent under the cursor. Imagery and pins hang off `Map.layers` (Imagery.lua,
-- Pins.lua): they draw on `Map.OnView` (every change) and query on `Map.OnSettle` (100 ms after the
-- last change). Nothing runs while the window is hidden.
local ADDON, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
local L = ns.L
local S = B.UI.Style
local Widgets = B.UI.Widgets
local Camera = ns.Camera

local Map = {}
ns.Map = Map

local SETTLE_DELAY = 0.1 -- seconds after the last pan or zoom before the layers are queried
local WHEEL_STEP = 0.5 -- levels per wheel notch
local KEY_PAN = 120 -- pixels per arrow key
local FOOTER_H = 18
-- Continent names come from Core (the transform table lists every world map with a zone; the two
-- Azeroth continents without one). Map.CONTINENTS reads the same table.
local function continentName(continent)
  return B.Coords.ContinentName(continent)
end
Map.ContinentName = continentName
Map.CONTINENTS = setmetatable({}, {
  __index = function(_, continent)
    return continentName(continent)
  end,
})

local mod, win, clip, footer, toolbar
local cameras = {} -- continent -> Camera
local camera -- the current one
local dragging -- { x, y } last cursor position while the mouse button is down
local settleTimer
Map.onView = {} -- fn(camera) after every view change
Map.onResize = {} -- fn(camera) per size change while the grip is held: reposition only, no loads
Map.onSettle = {} -- fn(camera, view) when the view has settled
Map.onBuild = {} -- fn(clip) once the window exists
Map.onSetting = {} -- fn(key, value) when one of the Map's settings changes (one bus handler for all)
Map.onTick = {} -- fn() ten times a second while the window is shown
Map.onEnable = {} -- fn(module) at every enable
Map.onDisable = {} -- fn() at every disable
Map.onLayerChanged = {} -- fn() when a layer changed or was registered (Pins holds the bus handler)
Map.onFocus = {} -- fn(ref, ctx) on BASTIANS_ENTITY_FOCUSED (one bus handler for all; ref nil: cleared)

local function db()
  return mod.db.profile
end

-- ---------------------------------------------------------------------------------------------
-- Camera and view
-- ---------------------------------------------------------------------------------------------

function Map.Camera()
  return camera
end

local function viewSize()
  local w, h = clip and clip:GetWidth() or 0, clip and clip:GetHeight() or 0
  if not w or w <= 0 then
    w = 600
  end
  if not h or h <= 0 then
    h = 400
  end
  return w, h
end

local function cameraFor(continent)
  local cam = cameras[continent]
  if not cam then
    cam = Camera.new(continent, viewSize())
    local saved = db().cameras and db().cameras[continent]
    if saved then
      cam.wx, cam.wy, cam.level = saved.wx or 0, saved.wy or 0, saved.level or 0
    end
    cameras[continent] = cam
  end
  return cam
end

local function remember()
  if not camera then
    return
  end
  db().cameras = db().cameras or {}
  db().cameras[camera.continent] = { wx = camera.wx, wy = camera.wy, level = camera.level }
  db().continent = camera.continent
end

local function settle()
  settleTimer = nil
  if not (win and win:IsShown() and camera) then
    return
  end
  remember()
  local view = camera:View(Map.PlayerWorld())
  for _, fn in ipairs(Map.onSettle) do
    fn(camera, view)
  end
end

-- After every pan or zoom: redraw now, query the layers when the view settles. While the window
-- is being resized (`sizing`, many events per second) only the resize handlers run: they move
-- what is live and draw the overview; the full draw and one layer query follow the last event
--.
function Map.ViewChanged(sizing)
  if not (win and win:IsShown() and camera) then
    return
  end
  camera:SetView(viewSize())
  if settleTimer then
    settleTimer:Cancel()
    settleTimer = nil
  end
  if sizing then
    for _, fn in ipairs(Map.onResize) do
      fn(camera)
    end
    Map.UpdateFooter()
    return
  end
  for _, fn in ipairs(Map.onView) do
    fn(camera)
  end
  Map.UpdateFooter()
  settleTimer = C_Timer.NewTimer(SETTLE_DELAY, settle)
end

-- The player's world position as { continent, wx, wy } or nil (instances).
function Map.PlayerWorld()
  local continent, wx, wy = B.Coords.Player()
  if not continent then
    return nil
  end
  return { continent, wx, wy }
end

-- Switch to a continent (keeps that continent's camera).
function Map.SetContinent(continent)
  camera = cameraFor(continent)
  if toolbar and toolbar.continent then
    toolbar.continent:SetValue(continent)
  end
  Map.ViewChanged()
end

-- Centre the camera on a world point, optionally at a level, switching continents when needed.
function Map.Fly(continent, wx, wy, level)
  if not win then
    Map.Open()
  end
  if not camera or camera.continent ~= continent then
    camera = cameraFor(continent)
    if toolbar and toolbar.continent then
      toolbar.continent:SetValue(continent)
    end
  end
  camera:Center(wx, wy)
  if level then
    camera:SetLevel(level)
  end
  Map.ViewChanged()
end

-- Centre on the player; false when the player has no world position.
-- Fits several world points into the view (an NPC with several spawn areas,
-- a quest with its giver and its targets): the camera centres on their box at the level that
-- holds it with a margin; one point flies as Map.Fly does at `level`.
-- Centre the view on the points at `level`. The view never zooms out below `level` (owner,
-- 22.10.2026: three wolf spawns fitted at a far zoom became one icon; the player's zoom stays,
-- zoomed in to the zone level at least). With `fit`, the level drops until the box fits: for a
-- whole zone, where seeing all of it is the point.
function Map.FitWorld(continent, points, level, fit)
  if not points or #points == 0 then
    return
  end
  local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
  for _, p in ipairs(points) do
    x1, y1 = math.min(x1, p.wx), math.min(y1, p.wy)
    x2, y2 = math.max(x2, p.wx), math.max(y2, p.wy)
  end
  local cx, cy = (x1 + x2) / 2, (y1 + y2) / 2
  local extent = math.max(x2 - x1, y2 - y1)
  if not fit or #points == 1 or extent < 50 then
    Map.Fly(continent, cx, cy, level)
    return
  end
  if not win then
    Map.Open()
  end
  local view = math.min(clip:GetWidth() or 600, clip:GetHeight() or 400)
  -- pixels per yard at level L is 2^L / 32: the level where the box with its margin fits
  local fitLevel = math.floor(math.log((view * 32) / (extent * 1.4)) / math.log(2))
  Map.Fly(continent, cx, cy, math.max(Camera.MIN_LEVEL, math.min(Camera.MAX_LEVEL, fitLevel)))
end

function Map.CenterOnPlayer()
  local p = Map.PlayerWorld()
  if not p then
    return false
  end
  Map.Fly(p[1], p[2], p[3])
  return true
end

-- ---------------------------------------------------------------------------------------------
-- Input
-- ---------------------------------------------------------------------------------------------

-- The cursor in pixels from the clip's top-left corner.
function Map.CursorPos()
  local x, y = GetCursorPosition()
  local scale = clip:GetEffectiveScale()
  if not scale or scale == 0 then
    scale = 1
  end
  return x / scale - (clip:GetLeft() or 0), (clip:GetTop() or 0) - y / scale
end

function Map.ZoomAt(sx, sy, delta)
  if camera and camera:ZoomAt(sx, sy, delta) then
    Map.ViewChanged()
  end
end

function Map.Pan(dx, dy)
  if camera then
    camera:Pan(dx, dy)
    Map.ViewChanged()
  end
end

local function onWheel(_, delta)
  local sx, sy = Map.CursorPos()
  Map.ZoomAt(sx, sy, (delta > 0 and 1 or -1) * WHEEL_STEP)
end

local function onMouseDown(_, button)
  if button == "LeftButton" then
    local x, y = GetCursorPosition()
    dragging = { x = x, y = y }
  end
end

local DOUBLE_CLICK = 0.4 -- seconds between two left clicks that count as one double-click
local lastClick = { at = -1, x = 0, y = 0 }

-- A plain Frame has no OnDoubleClick script (only Buttons do; the client refused it on 20.10.2026),
-- so a second left click within DOUBLE_CLICK seconds and 6 px of the first zooms in one level.
local function onMouseUp(_, button)
  if button == "LeftButton" then
    local moved = dragging and dragging.moved
    dragging = nil
    if moved then
      lastClick.at = -1 -- the end of a drag is not a click
      return
    end
    local sx, sy = Map.CursorPos()
    local now = GetTime()
    if
      now - lastClick.at <= DOUBLE_CLICK
      and math.abs(sx - lastClick.x) <= 6
      and math.abs(sy - lastClick.y) <= 6
    then
      lastClick.at = -1
      Map.ZoomAt(sx, sy, 1)
    else
      lastClick.at, lastClick.x, lastClick.y = now, sx, sy
    end
  elseif button == "RightButton" and Map.OnRightClick then
    Map.OnRightClick(Map.CursorPos())
  end
end

local lastFooter = 0

-- Only while the window is shown: follow a drag, refresh the footer ten times a second.
local function onUpdate(_, elapsed)
  if dragging then
    local x, y = GetCursorPosition()
    local scale = clip:GetEffectiveScale()
    if not scale or scale == 0 then
      scale = 1
    end
    local dx, dy = (x - dragging.x) / scale, (dragging.y - y) / scale
    if dx ~= 0 or dy ~= 0 then
      dragging.x, dragging.y, dragging.moved = x, y, true
      Map.Pan(dx, dy)
    end
  end
  lastFooter = lastFooter + (elapsed or 0)
  if lastFooter >= 0.1 then
    lastFooter = 0
    Map.UpdateFooter()
    for _, fn in ipairs(Map.onTick) do
      fn()
    end
  end
end

local KEYS = {
  LEFT = function()
    Map.Pan(KEY_PAN, 0)
  end,
  RIGHT = function()
    Map.Pan(-KEY_PAN, 0)
  end,
  UP = function()
    Map.Pan(0, KEY_PAN)
  end,
  DOWN = function()
    Map.Pan(0, -KEY_PAN)
  end,
  HOME = function()
    Map.CenterOnPlayer()
  end,
}
local ZOOM_KEYS = { ["+"] = 1, ["="] = 1, NUMPADPLUS = 1, ["-"] = -1, NUMPADMINUS = -1 }

local function onKeyDown(frame, key)
  local handler = KEYS[key]
  if handler then
    handler()
    frame:SetPropagateKeyboardInput(false)
  elseif key == "ESCAPE" and ns.Focus and ns.Focus.Escape() then
    frame:SetPropagateKeyboardInput(false) -- the focus went; a second Esc closes the window
  elseif ZOOM_KEYS[key] then
    Map.ZoomAt(camera.width / 2, camera.height / 2, ZOOM_KEYS[key])
    frame:SetPropagateKeyboardInput(false)
  else
    frame:SetPropagateKeyboardInput(true) -- anything else keeps working as usual
  end
end

-- ---------------------------------------------------------------------------------------------
-- Footer: the zone and map percent under the cursor
-- ---------------------------------------------------------------------------------------------

-- "Elwynn Forest 42.0, 65.0" for a world point, or the continent name when no zone contains it.
function Map.Describe(continent, wx, wy)
  local uiMapID = B.Coords.BestMap(continent, wx, wy)
  if uiMapID then
    local x, y = B.Coords.ToMap(continent, wx, wy, uiMapID)
    local name = B:Entity("zone:" .. uiMapID):Name()
    if not name then
      local info = C_Map.GetMapInfo(uiMapID)
      name = info and info.name or ("map " .. uiMapID)
    end
    if x and y then
      return string.format("%s %.1f, %.1f", name, x * 100, y * 100), uiMapID, x, y
    end
    return name, uiMapID
  end
  return L[continentName(continent) or ("continent " .. tostring(continent))], nil
end

function Map.UpdateFooter()
  if not (footer and camera) then
    return
  end
  local sx, sy = Map.CursorPos()
  local text
  if sx >= 0 and sy >= 0 and sx <= camera.width and sy <= camera.height then
    local wx, wy = camera:ToWorld(sx, sy)
    text = Map.Describe(camera.continent, wx, wy)
  else
    text = L[continentName(camera.continent) or "?"]
  end
  footer:SetText(string.format("%s   " .. S.H.muted .. "%s %.1f|r", text, L["zoom"], camera.level))
end

-- ---------------------------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------------------------

local function build()
  win = B.UI.Window("BastiansMapFrame", {
    title = L["Map"],
    width = 760,
    height = 560,
    minWidth = 400,
    minHeight = 300,
    db = db().window,
    onShow = function()
      clip:SetScript("OnUpdate", onUpdate)
      Map.ViewChanged()
    end,
    onHide = function()
      clip:SetScript("OnUpdate", nil) -- no work while hidden (CLAUDE.md golden rule 7)
      dragging = nil
      if settleTimer then
        settleTimer:Cancel()
        settleTimer = nil
      end
      remember()
    end,
    onResize = function(_, sizing)
      Map.ViewChanged(sizing)
    end,
  })
  local content = win.content

  toolbar = CreateFrame("Frame", nil, content)
  toolbar:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -6)
  toolbar:SetPoint("TOPRIGHT", content, "TOPRIGHT", -6, -6)
  toolbar:SetHeight(22)
  local continents = {}
  for id, name in pairs(B.Coords.Continents()) do
    continents[id] = L[name]
  end
  toolbar.continent = Widgets.Select(toolbar, "", continents, function(key)
    Map.SetContinent(key)
  end)
  toolbar.continent:SetPoint("LEFT", 0, 0)
  toolbar.continent:SetWidth(170)
  toolbar.player = S.button(toolbar, L["Player"], 60, 22)
  toolbar.player.tip = L["Centre the map on you."]
  toolbar.player:SetPoint("LEFT", toolbar.continent, "RIGHT", 6, 0)
  ns.Search.Attach(toolbar) -- the search bar (Search.lua, map.md B8.6)
  toolbar.player:SetScript("OnClick", function()
    if not Map.CenterOnPlayer() then
      B:Say(L["No map position here (instance?)"])
    end
  end)
  toolbar.full = S.button(toolbar, L["Full"], 40, 22) -- full screen and back
  toolbar.full.tip = L["Full screen, and back."]
  toolbar.full:SetPoint("RIGHT", 0, 0)
  toolbar.full:SetScript("OnClick", function()
    win:ToggleFullScreen()
    toolbar.full.label:SetText(win:IsFullScreen() and L["Back"] or L["Full"])
  end)
  toolbar.full.label:SetText(win:IsFullScreen() and L["Back"] or L["Full"])
  toolbar.zoomIn = S.button(toolbar, "+", 22, 22)
  toolbar.zoomIn.tip = L["Zoom in (or the mouse wheel)."]
  toolbar.zoomIn:SetPoint("RIGHT", toolbar.full, "LEFT", -6, 0)
  toolbar.zoomIn:SetScript("OnClick", function()
    Map.ZoomAt(camera.width / 2, camera.height / 2, 1)
  end)
  toolbar.zoomOut = S.button(toolbar, "-", 22, 22)
  toolbar.zoomOut.tip = L["Zoom out (or the mouse wheel)."]
  toolbar.zoomOut:SetPoint("RIGHT", toolbar.zoomIn, "LEFT", -2, 0)
  toolbar.zoomOut:SetScript("OnClick", function()
    Map.ZoomAt(camera.width / 2, camera.height / 2, -1)
  end)

  clip = CreateFrame("Frame", nil, content)
  clip:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -32)
  clip:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -6, FOOTER_H + 4)
  clip:SetClipsChildren(true)
  -- parchment, not black: the sea is transparent in the overview cells and the zone art under it
  -- arrives late on a streaming client
  S.fill(clip, S.C.sea) -- the clip's background: parchment like Blizzard's sea
  clip:EnableMouse(true)
  clip:EnableMouseWheel(true)
  clip:SetScript("OnMouseWheel", onWheel)
  clip:SetScript("OnMouseDown", onMouseDown)
  clip:SetScript("OnMouseUp", onMouseUp)
  clip:EnableKeyboard(true)
  clip:SetScript("OnKeyDown", onKeyDown)
  clip:SetPropagateKeyboardInput(true)

  footer = S.text(content, 11, S.C.dim)
  footer:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 8, 4)
  footer:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -8, 4)
  footer:SetHeight(FOOTER_H - 4)

  Map.win, Map.clip, Map.footer, Map.toolbar = win, clip, footer, toolbar
  for _, fn in ipairs(Map.onBuild) do
    fn(clip)
  end
  Map.LayoutToolbar()
end

-- The search box spans from Player to the leftmost button of the right group, whichever modules
-- added them (a fixed right margin of 190 let the box cover Dock and half
-- of Follow, which together with Layers, the zoom buttons and Full take 272 units).
function Map.LayoutToolbar()
  local bar = Map.toolbar
  if not (bar and bar.search) then
    return
  end
  local right
  for _, name in ipairs({ "dock", "follow", "layers", "zoomOut", "zoomIn", "full" }) do
    if bar[name] then
      right = bar[name]
      break
    end
  end
  bar.search:ClearAllPoints()
  bar.search:SetPoint("LEFT", bar.player, "RIGHT", 8, 0)
  if right then
    bar.search:SetPoint("RIGHT", right, "LEFT", -8, 0)
  else
    bar.search:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
  end
end

-- Open on the player's continent (or the last one) centred on the player the first time.
function Map.Open()
  if not (mod and mod:IsEnabled()) then
    return false
  end
  local first = win == nil
  if not win then
    build()
  end
  if not camera then
    local p = Map.PlayerWorld()
    camera = cameraFor(p and p[1] or db().continent or 0)
    if p and first and not (db().cameras and db().cameras[camera.continent]) then
      camera:Center(p[2], p[3])
      camera:SetLevel(3)
    end
    toolbar.continent:SetValue(camera.continent)
  end
  if win:IsShown() then
    Map.ViewChanged()
  else
    win:Show()
  end
  return true
end

function Map.Toggle()
  if win and win:IsShown() then
    win:Hide()
  else
    Map.Open()
  end
end

function Map.Hide()
  if win then
    win:Hide()
  end
end

-- Opens the map on a uiMap: the view fitted to its corners from `level` (the zone level by
-- default). The zone page's "Show on map" and the M key use it; nil for a map without transform.
function Map.ShowUiMap(uiMapID, level)
  local continent, cx, cy = B.Coords.ToWorld(uiMapID, 0.5, 0.5)
  if not continent then
    return false
  end
  Map.Open()
  local points = { { wx = cx, wy = cy } }
  for _, corner in ipairs({ { 0, 0 }, { 1, 1 } }) do
    local c, wx, wy = B.Coords.ToWorld(uiMapID, corner[1], corner[2])
    if c == continent then
      points[#points + 1] = { wx = wx, wy = wy }
    end
  end
  Map.FitWorld(continent, points, level or ns.Waypoints.ZONE_LEVEL, true)
  return true
end

function Map.IsShown()
  return win ~= nil and win:IsShown()
end

-- ---------------------------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------------------------

mod = B:NewModule("Map", {
  news = ns.NEWS, -- What's new (ADR 0021)
  addon = ADDON,
  open = function()
    Map.Toggle()
  end,
  title = L["Map"],
  apiVersion = 1,
  data = { "world" },
  optional = { "Bastians_Map_Art", "TomTom" },
  defaults = {
    profile = {
      window = {},
      cameras = {},
      layers = {},
      continent = 0,
      nativeTiles = true,
      overviewArt = true,
      follow = false, -- the map follows the Browser's page (ADR 0013 D; off by default)
      minimapPins = true, -- the layers on the game's minimap (S5)
      minimapMax = 20,
    },
  },
  options = {
    { type = "header", label = L["Imagery"] },
    { type = "toggle", key = "nativeTiles", label = L["Native minimap tiles at close zoom"] },
    {
      type = "note",
      text = function()
        return ns.Tiles.Note()
      end,
    },
    { type = "toggle", key = "overviewArt", label = L["Overview textures from Bastian's Map Art"] },
    { type = "header", label = L["The minimap"] },
    {
      type = "toggle",
      key = "minimapPins",
      label = L["Show the map's layers on the minimap (the nearest pins, arrows at the rim)"],
      default = true,
    },
    {
      type = "range",
      key = "minimapMax",
      label = L["Pins on the minimap at most"],
      min = 5,
      max = 40,
      step = 5,
    },
    { type = "header", label = L["The game's map"] },
    {
      type = "toggle",
      key = "openWithM",
      label = L["Open Bastian's map instead of the game's (instances and caves stay on the game's map)"],
      default = false, -- off until checked in game (map.md, Should row; GameMap.lua)
    },
    {
      type = "toggle",
      key = "overlayGameMap",
      label = L["Draw Bastian's map art over the game's map"],
      default = false,
    },
    {
      type = "note",
      text = function()
        return ns.Overview.Note()
      end,
    },
  },
  OnEnable = function(self)
    for _, fn in ipairs(Map.onEnable) do
      fn(self)
    end
    self:On("BASTIANS_SETTING_CHANGED", function(_, _, name, key, value)
      if name == self.name then
        for _, fn in ipairs(Map.onSetting) do
          fn(key, value)
        end
      end
    end)
    self:On("BASTIANS_ENTITY_FOCUSED", function(_, _, ref, ctx)
      for _, fn in ipairs(Map.onFocus) do
        fn(ref, ctx)
      end
    end)
  end,
  OnDisable = function()
    Map.Hide()
    for _, fn in ipairs(Map.onDisable) do
      fn()
    end
  end,
})
ns.mod = mod
mod.Map = Map
mod.Camera = Camera

BINDING_NAME_BASTIANS_MAP = L["Open Bastian's Map"]

SLASH_BASTIANSMAP1 = "/bmap"
SlashCmdList.BASTIANSMAP = function(msg)
  msg = string.lower(strtrim(msg or ""))
  if msg == "" then
    Map.Toggle()
  elseif msg == "player" or msg == "me" then
    Map.Open()
    Map.CenterOnPlayer()
  elseif msg == "ek" or msg == "0" then
    Map.Open()
    Map.SetContinent(0)
  elseif msg == "kalimdor" or msg == "1" then
    Map.Open()
    Map.SetContinent(1)
  elseif msg == "stats" then
    for _, line in ipairs(Map.Stats()) do
      B:Say(line)
    end
  else
    B:Say(L["Usage: /bmap [player | ek | kalimdor | stats]"])
  end
end

-- What the imagery layers hold right now, one line each, plus the first live textures of the native
-- and the overview layer as the client describes them (the diagnosis the owner pastes, map.md).
function Map.Stats()
  local Tiles, Overview, Imagery, Pins = ns.Tiles, ns.Overview, ns.Imagery, ns.Pins
  local lines = {}
  if not camera then
    lines[1] = L["The map has not been opened yet."]
    return lines
  end
  lines[#lines + 1] = string.format(
    "%s %s, %s %.1f, %dx%d px, %s",
    L["Map"],
    tostring(continentName(camera.continent) or camera.continent),
    L["zoom"],
    camera.level,
    camera.width,
    camera.height,
    B.Client or "?"
  )
  local function layer(name, obj)
    lines[#lines + 1] = string.format(
      "%s: shown %d, wanted %d, skipped %d, pooled %d",
      name,
      obj.stats.shown,
      obj.stats.wanted,
      obj.stats.skipped,
      #obj.free
    )
    for _, line in ipairs(Tiles.Describe(obj, 3)) do
      lines[#lines + 1] = "  " .. line
    end
  end
  layer(L["Minimap tiles"] .. " (" .. (Tiles.Note() or "") .. ")", Tiles)
  layer(L["Overview cells"] .. " (" .. (Overview.Note() or "") .. ")", Overview)
  lines[#lines + 1] = string.format(
    "%s: %d %s, %d %s, %d %s",
    L["Zone art"],
    Imagery.stats.textures,
    L["textures"],
    Imagery.stats.zones,
    L["zones"],
    Imagery.stats.labels,
    L["labels"]
  )
  local first = Imagery.pool[1]
  if first then
    local w, h = first:GetSize()
    lines[#lines + 1] = string.format(
      "  %s %s shown=%s %dx%d",
      L["first"],
      tostring(first:GetTexture()),
      tostring(first:IsShown()),
      math.floor((w or 0) + 0.5),
      math.floor((h or 0) + 0.5)
    )
  end
  for _, z in ipairs(Imagery.Drawn(camera)) do
    lines[#lines + 1] = string.format(
      "  map %d %s depth %d, %d %s, %dx%d px",
      z.map,
      tostring(z.name),
      z.depth,
      z.tiles,
      L["art tiles"],
      z.w,
      z.h
    )
  end
  lines[#lines + 1] = string.format(
    "%s: %d %s, %d %s, %d %s, %d %s, %d %s",
    L["Pins"],
    Pins.stats.pins,
    L["pins"],
    Pins.stats.clusters,
    L["clusters"],
    Pins.stats.areas,
    L["areas"],
    Pins.stats.lines,
    L["lines"],
    Pins.stats.labels,
    L["labels"]
  )
  return lines
end
