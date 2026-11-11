-- The City & dungeon map (map.md "City plans", ADR 0065): a window of its own over a place's painted
-- sheet, with the player, the layers the player picks and a Dock for the Browser. The world map is
-- not touched: without the art (Bastians.Map.cities, from Bastians_Map_Art) there is no button.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Map = ns.Map

local City = {}
ns.City = City

City.TILE = 1024 -- pixels of a stored tile
City.MAX_LEVEL = 7 -- a little past the picture's own pixels (level 6.2)
City.QUERY_LEVEL = 6 -- the layers are asked as at close zoom: every level of detail, at every zoom
City.MAX_PINS = 300 -- as the world map (map.md "Budgets")
City.PIN = 16
City.ROW = 22
City.GAP = 4
City.ARROW_EVERY = 0.05 -- seconds between the arrow's updates
City.DRAG = 4 -- pixels a press may move and still be a click
-- not for a sheet: the route, the zone names (the sheet has its own), a world waypoint
City.LEFT_OUT = { ["route.path"] = true, ["map.zones"] = true, ["map.waypoint"] = true }
City.HOUSES = { -- this window's own filter: houses are no layer of the world map
  id = "city.houses",
  label = L["Houses"],
  tip = L["The buildings with their people. Hover to see one, click to open it."],
  icon = "service",
  defaultOn = true,
}
City.OUTLINE_W = 2

local win, clip, bar, filterRow
local camera, current
local tiles, placeButtons, filters, pool = {}, {}, {}, {}
local pins = {}
local arrow, ring, arrowAt = nil, nil, 0
local press -- { x, y, moved, button } while a mouse button is down on the sheet
local hovered, overPin -- the house under the mouse; true while the mouse is on a pin
local lines = {} -- the hovered house's outline

local function db()
  return ns.mod.db.profile.city
end

-- The place's name in the player's language (the zone's own), the manifest's as the fallback.
local function placeName(city)
  return B:Entity("zone:" .. city.ui):Name() or city.name
end

local function inside(city, wx, wy)
  return wx >= city.wx[1] and wx <= city.wx[2] and wy >= city.wy[1] and wy <= city.wy[2]
end

-- --- the places ------------------------------------------------------------------------------

local function cities()
  return B.Map and B.Map.cities or {}
end

function City.Available()
  return #cities() > 0
end

-- The city a world point lies on, or nil.
function City.At(continent, wx, wy)
  for _, city in ipairs(cities()) do
    if city.continent == continent and inside(city, wx, wy) then
      return city
    end
  end
  return nil
end

-- The city an entity belongs to, and where on it: a zone that is a city, or the first place of
-- anything else that lies on a sheet. Nothing known, nothing claimed.
function City.Of(ref)
  if type(ref) ~= "string" then
    return nil
  end
  local kind, id = B.Entity.Parse(ref)
  if not kind then
    return nil
  end
  if kind == "zone" then
    for _, city in ipairs(cities()) do
      if tostring(city.ui) == tostring(id) then
        return city
      end
    end
    return nil
  end
  if kind == "house" then -- its own place: no map transform in between
    local house = ns.Houses.Get(id)
    for _, city in ipairs(cities()) do
      if house and city.ui == house.ui then
        return city, house.wx, house.wy
      end
    end
    return nil
  end
  local continent, wx, wy = ns.Waypoints.FirstLocation(ref)
  local city = continent and City.At(continent, wx, wy)
  if city then
    return city, wx, wy
  end
  return nil
end

-- --- the view: pure math over the Camera -----------------------------------------------------

-- The level that shows the whole sheet in a view of the given size.
function City.FitLevel(city, width, height)
  local spanX, spanY = city.wx[2] - city.wx[1], city.wy[2] - city.wy[1]
  local scale = math.min(height / spanX, width / spanY)
  return math.log(scale / ns.Camera.PX_PER_YARD_L0) / math.log(2)
end

-- Never further out than the whole sheet, never past its edge; a sheet smaller than the view stands
-- in its middle.
function City.Clamp(cam, city)
  local fit = City.FitLevel(city, cam.width, cam.height)
  cam.level = math.max(fit, math.min(cam.level, math.max(fit, City.MAX_LEVEL)))
  local s = cam:Scale()
  local function axis(v, lo, hi, half)
    if hi - lo <= 2 * half then
      return (lo + hi) / 2
    end
    return math.max(lo + half, math.min(v, hi - half))
  end
  cam.wx = axis(cam.wx, city.wx[1], city.wx[2], cam.height / 2 / s)
  cam.wy = axis(cam.wy, city.wy[1], city.wy[2], cam.width / 2 / s)
end

-- A stored tile in world yards and its visible share: { north, west, south, east, u, v }. The picture
-- is padded to whole tiles, the padding is not shown.
function City.TileRect(city, row, col)
  local ypp = (city.wy[2] - city.wy[1]) / city.w -- yards a pixel
  local x0, y0 = col * City.TILE, row * City.TILE
  local w, h = math.min(City.TILE, city.w - x0), math.min(City.TILE, city.h - y0)
  local north, west = city.wx[2] - y0 * ypp, city.wy[2] - x0 * ypp
  return north, west, north - h * ypp, west - w * ypp, w / City.TILE, h / City.TILE
end

-- --- drawing -----------------------------------------------------------------------------------

local function layoutSheet()
  if not (camera and current) then
    return
  end
  local n = 0
  for row = 0, current.rows - 1 do
    for col = 0, current.cols - 1 do
      n = n + 1
      local north, west, south, east = City.TileRect(current, row, col)
      local x1, y1 = camera:ToScreen(north, west)
      local x2, y2 = camera:ToScreen(south, east)
      local t = tiles[n]
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", clip, "TOPLEFT", x1, -y1)
      t:SetSize(x2 - x1, y2 - y1)
    end
  end
end

local function layoutPins()
  for _, f in ipairs(pool) do
    if f:IsShown() and f.pin then
      local sx, sy = camera:ToScreen(f.pin.wx, f.pin.wy)
      f.sx, f.sy = sx, sy
      f:ClearAllPoints()
      f:SetPoint("CENTER", clip, "TOPLEFT", sx, -sy)
    end
  end
  if ring and ring.wx then
    local sx, sy = camera:ToScreen(ring.wx, ring.wy)
    ring:ClearAllPoints()
    ring:SetPoint("CENTER", clip, "TOPLEFT", sx, -sy)
  end
end

local function updateArrow()
  if not (arrow and camera and current) then
    return
  end
  local continent, wx, wy = B.Coords.Player()
  if continent ~= current.continent or not inside(current, wx, wy) then
    arrow:Hide()
    return
  end
  local sx, sy = camera:ToScreen(wx, wy)
  arrow:ClearAllPoints()
  arrow:SetPoint("CENTER", clip, "TOPLEFT", sx, -sy)
  arrow:SetRotation(B.Compat.GetPlayerFacing() or 0)
  arrow:Show()
end

-- The hovered house's real outline, one straight piece per edge.
local function drawOutline()
  local n = 0
  for _, poly in ipairs(hovered and hovered.outlines or {}) do
    local count = #poly / 2
    for i = 1, count do
      local j = i % count + 1
      local x1, y1 = camera:ToScreen(poly[2 * i - 1], poly[2 * i])
      local x2, y2 = camera:ToScreen(poly[2 * j - 1], poly[2 * j])
      local dx, dy = x2 - x1, y2 - y1
      local len = math.sqrt(dx * dx + dy * dy)
      if len >= 1 then
        n = n + 1
        local t = lines[n]
        if not t then
          t = clip:CreateTexture(nil, "ARTWORK")
          t:SetTexture(S.WHITE)
          S.tint(t, S.C.accent, 0.95)
          lines[n] = t
        end
        t:ClearAllPoints()
        t:SetPoint("CENTER", clip, "TOPLEFT", (x1 + x2) / 2, -(y1 + y2) / 2)
        t:SetSize(len + City.OUTLINE_W, City.OUTLINE_W)
        t:SetRotation(math.atan2(-dy, dx))
        t:Show()
      end
    end
  end
  for i = n + 1, #lines do
    lines[i]:Hide()
  end
  return n
end

local function viewChanged()
  City.Clamp(camera, current)
  layoutSheet()
  layoutPins()
  drawOutline()
  updateArrow()
end

local function setHovered(house)
  if house ~= hovered then
    hovered = house
    drawOutline()
  end
end

function City.Hovered()
  return hovered
end

function City.OutlinePieces()
  return drawOutline()
end

-- The pin frame of a house, while it shows.
local function frameOf(house)
  for _, f in ipairs(pool) do
    if f:IsShown() and f.pin and f.pin.house == house then
      return f
    end
  end
  return nil
end

local function pinFrame(i)
  local f = pool[i]
  if not f then
    f = CreateFrame("Button", nil, clip)
    f:SetFrameLevel((clip:GetFrameLevel() or 1) + 5)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:SetScript("OnClick", ns.Pins.ClickPin) -- the map's own: the focus, the Browser's page, the menu
    f:SetScript("OnEnter", function(self)
      overPin = true
      ns.Pins.HoverPin(self)
      setHovered(self.pin and self.pin.house or nil)
    end)
    f:SetScript("OnLeave", function()
      overPin = false
      ns.Pins.LeavePin()
      setHovered(nil)
    end)
    pool[i] = f
  end
  return f
end

-- --- the layers: this window's own filters -------------------------------------------------------

function City.ShowsLayer(def)
  return not City.LEFT_OUT[def.id]
end

-- What the filter row offers: the houses, then the map's layers.
function City.Layers()
  local out = { City.HOUSES }
  for _, def in ipairs(B:GetMapLayers()) do
    if City.ShowsLayer(def) then
      out[#out + 1] = def
    end
  end
  return out
end

function City.IsLayerOn(def)
  local saved = db().layers[def.id]
  if saved == nil then
    return def.defaultOn ~= false
  end
  return saved
end

-- The pins of the switched-on layers on the sheet, the most important first. Asked for the whole
-- sheet, so that a pan or a zoom only moves them.
function City.Query(city)
  local view = {
    continent = city.continent,
    x1 = city.wx[1],
    y1 = city.wy[1],
    x2 = city.wx[2],
    y2 = city.wy[2],
    level = City.QUERY_LEVEL,
    player = Map.PlayerWorld(),
  }
  local out = {}
  for _, def in ipairs(B:GetMapLayers()) do
    if City.ShowsLayer(def) and City.IsLayerOn(def) then
      for _, pin in ipairs(B:QueryLayer(def.id, view)) do
        if
          pin.kind ~= "path"
          and pin.kind ~= "text"
          and pin.wx
          and pin.wy
          and inside(city, pin.wx, pin.wy)
        then
          pin.layer = def.label or def.id
          out[#out + 1] = pin
        end
      end
    end
  end
  if City.IsLayerOn(City.HOUSES) then
    for _, pin in ipairs(ns.Houses.Pins(city.ui)) do
      pin.layer = City.HOUSES.label
      out[#out + 1] = pin
    end
  end
  table.sort(out, function(a, b)
    return (a.priority or 50) > (b.priority or 50)
  end)
  return out
end

local function drawPins()
  if not (win and win:IsShown() and current) then
    return
  end
  pins = City.Query(current)
  local n = math.min(#pins, City.MAX_PINS)
  for i = 1, n do
    local pin, f = pins[i], pinFrame(i)
    f.pin = pin
    local size = pin.size or City.PIN
    f:SetSize(size, size)
    B.UI.PaintIcon(f.icon, pin.icon or B.UI.IconTexture("other"))
    if pin.color then
      S.tint(f.icon, pin.color)
    end
    f:Show()
  end
  for i = n + 1, #pool do
    pool[i]:Hide()
    pool[i].pin = nil
  end
  layoutPins()
end

-- The focused entity's ring, wherever it stands on this sheet; the sheet does not move for it.
local function drawRing()
  if not ring then
    return
  end
  local city, wx, wy = City.Of(B:Focused())
  if city ~= nil and city == current and wx then
    ring.wx, ring.wy = wx, wy
    ring:Show()
    layoutPins()
  else
    ring.wx, ring.wy = nil, nil
    ring:Hide()
  end
end

local function paintFilter(b, def)
  local on = City.IsLayerOn(def)
  b.token = on and "accent" or "dim"
  S.tint(b.face, S.C[b.token], S.TILE_FACE_ALPHA)
  S.setEdges(b.edges, S.C[b.token], on and 0.9 or 0.4)
  b.icon:SetAlpha(on and 1 or 0.35)
end

-- One icon per layer, wrapping at the window's width; returns the row's height.
local function layoutFilters()
  local width = (win.frame:GetWidth() or 0) - 14
  local x, y, n = 0, 0, 0
  for _, def in ipairs(City.Layers()) do
    n = n + 1
    local b = filters[n]
    if not b then
      b = S.tileButton(filterRow, "", "other", "accent", City.ROW)
      b.tipNow = true
      b:SetScript("OnClick", function(self)
        db().layers[self.def.id] = not City.IsLayerOn(self.def)
        paintFilter(self, self.def)
        drawPins()
        if not City.IsLayerOn(City.HOUSES) then
          setHovered(nil)
        end
      end)
      filters[n] = b
    end
    b.def = def
    local label, tip = tostring(def.label or def.id), def.tip
    b.tip = function()
      return label, tip
    end
    B.UI.PaintIcon(b.icon, B.UI.IconTexture(def.icon or "other") or B.UI.IconTexture("other"))
    paintFilter(b, def)
    if x > 0 and x + City.ROW > width then
      x, y = 0, y + City.ROW + City.GAP
    end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", filterRow, "TOPLEFT", x, -y)
    b:Show()
    x = x + City.ROW + City.GAP
  end
  for i = n + 1, #filters do
    filters[i]:Hide()
  end
  local height = y + City.ROW
  filterRow:SetHeight(height)
  return height
end

local function updateDock()
  local dock = bar and bar.dock
  if dock then
    local on = B.UI.IsDocked(B.UI.DOCK.city)
    S.tint(dock.face, S.C[dock.token] or S.C.accent, on and 0.75 or S.TILE_FACE_ALPHA)
  end
end

-- --- the mouse -----------------------------------------------------------------------------------

local function cursor()
  local x, y = GetCursorPosition()
  local s = clip:GetEffectiveScale()
  return x / s - (clip:GetLeft() or 0), (clip:GetTop() or 0) - y / s
end

-- The building under the mouse: its outline and its card. Not while a pin has the mouse or the
-- houses are switched off.
function City.HoverAt(wx, wy)
  local house = wx and City.IsLayerOn(City.HOUSES) and ns.Houses.At(current.ui, wx, wy) or nil
  if house == hovered then
    return house
  end
  setHovered(house)
  local f = house and frameOf(house)
  if f then
    ns.Pins.HoverPin(f)
  else
    ns.Pins.LeavePin()
  end
  return house
end

local function onUpdate(_, elapsed)
  if press and press.button == "LeftButton" then
    local x, y = cursor()
    local dx, dy = x - press.x, y - press.y
    if press.moved or math.abs(dx) + math.abs(dy) > City.DRAG then
      press.moved = true
      camera:Pan(dx, dy)
      press.x, press.y = x, y
      viewChanged()
    end
  end
  arrowAt = arrowAt + elapsed
  if arrowAt >= City.ARROW_EVERY then
    arrowAt = 0
    updateArrow()
    if current and not press and not overPin then
      if clip:IsMouseOver() then
        local x, y = cursor()
        City.HoverAt(camera:ToWorld(x, y))
      else
        City.HoverAt(nil)
      end
    end
  end
end

local function onMouseDown(_, button)
  local x, y = cursor()
  press = { x = x, y = y, button = button }
end

local function onMouseUp(_, button)
  local p = press
  press = nil
  if not (p and not p.moved and current) then
    return
  end
  local f = hovered and frameOf(hovered)
  if f then -- a click on the building is a click on its pin
    ns.Pins.ClickPin(f, button)
  elseif button == "RightButton" then
    local x, y = cursor()
    local wx, wy = camera:ToWorld(x, y)
    -- the place's menu with the point: "Add note here" and what else the apps offer there
    B.UI.EntityMenu(
      "zone:" .. current.ui,
      nil,
      { source = "city", point = { current.continent, wx, wy, placeName(current) } }
    )
  end
end

local function onWheel(_, delta)
  local x, y = cursor()
  camera:ZoomAt(x, y, delta * 0.5)
  viewChanged()
end

local function zoom(delta)
  camera:Zoom(delta)
  viewChanged()
end

-- --- the window ----------------------------------------------------------------------------------

local function layoutBody()
  local height = layoutFilters()
  clip:ClearAllPoints()
  clip:SetPoint("TOPLEFT", win.content, "TOPLEFT", 6, -(6 + City.ROW + City.GAP + height + City.GAP))
  clip:SetPoint("BOTTOMRIGHT", win.content, "BOTTOMRIGHT", -6, 6)
  camera:SetView(clip:GetWidth(), clip:GetHeight())
end

local function paintPlaces()
  for _, b in ipairs(placeButtons) do
    local on = b.city == current
    b.token = on and "accent" or "dim"
    S.tint(b.face, S.C[b.token], on and 0.75 or S.TILE_FACE_ALPHA)
  end
end

-- Shows a place: its tiles (the only moment its pictures load), the whole sheet in view.
function City.Show(city)
  current = city
  local n = 0
  for row = 0, city.rows - 1 do
    for col = 0, city.cols - 1 do
      n = n + 1
      local t = tiles[n]
      if not t then
        t = clip:CreateTexture(nil, "BACKGROUND")
        tiles[n] = t
      end
      t:SetTexture(city.path .. row .. "_" .. col)
      local _, _, _, _, u, v = City.TileRect(city, row, col)
      t:SetTexCoord(0, u, 0, v)
      t:Show()
    end
  end
  for i = n + 1, #tiles do
    tiles[i]:Hide()
  end
  camera.continent = city.continent
  camera.level = 0
  camera.wx, camera.wy = (city.wx[1] + city.wx[2]) / 2, (city.wy[1] + city.wy[2]) / 2
  paintPlaces()
  viewChanged()
  drawPins()
  drawRing()
end

local function build()
  win = B.UI.Window(B.UI.DOCK.city, {
    module = "Map",
    title = L["City & dungeon map"],
    width = 900,
    height = 680,
    minWidth = 480,
    minHeight = 360,
    maxWidth = B.UI.NO_LIMIT,
    maxHeight = B.UI.NO_LIMIT,
    db = db().window,
    onShow = function()
      clip:SetScript("OnUpdate", onUpdate)
      updateDock()
      if current then
        layoutBody()
        viewChanged()
        drawPins()
        drawRing()
      end
    end,
    onHide = function()
      clip:SetScript("OnUpdate", nil) -- no work while hidden (CLAUDE.md golden rule 7)
      press, hovered, overPin = nil, nil, nil
      ns.Pins.LeavePin()
    end,
    onResize = function()
      if current then
        layoutBody()
        viewChanged()
      end
    end,
  })
  local content = win.content

  bar = CreateFrame("Frame", nil, content)
  bar:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -6)
  bar:SetPoint("TOPRIGHT", content, "TOPRIGHT", -6, -6)
  bar:SetHeight(City.ROW)
  local prev
  for _, city in ipairs(cities()) do
    local b = S.tileButton(bar, placeName(city), "zone", "dim")
    b.city = city
    b:SetScript("OnClick", function(self)
      City.Show(self.city)
    end)
    if prev then
      b:SetPoint("LEFT", prev, "RIGHT", City.GAP, 0)
    else
      b:SetPoint("LEFT", bar, "LEFT", 0, 0)
    end
    placeButtons[#placeButtons + 1] = b
    prev = b
  end
  bar.full = S.tileButton(bar, L["Full"], "zone", "accent", 76)
  bar.full.tip = L["Full screen, and back."]
  bar.full:SetPoint("RIGHT", 0, 0)
  bar.full:SetScript("OnClick", function()
    win:ToggleFullScreen()
    bar.full.label:SetText(win:IsFullScreen() and L["Window"] or L["Full"])
  end)
  bar.zoomIn = S.tileButton(bar, "+", nil, "dim", 22)
  bar.zoomIn.tip = L["Zoom in (or the mouse wheel)."]
  bar.zoomIn:SetPoint("RIGHT", bar.full, "LEFT", -6, 0)
  bar.zoomIn:SetScript("OnClick", function()
    zoom(1)
  end)
  bar.zoomOut = S.tileButton(bar, "-", nil, "dim", 22)
  bar.zoomOut.tip = L["Zoom out (or the mouse wheel)."]
  bar.zoomOut:SetPoint("RIGHT", bar.zoomIn, "LEFT", -2, 0)
  bar.zoomOut:SetScript("OnClick", function()
    zoom(-1)
  end)
  bar.dock = S.tileButton(bar, L["Dock"], "open", "rare")
  bar.dock.tip = function()
    return L["Dock the Browser"], L["Opens the Browser beside this map at its height. Click again to undock."]
  end
  bar.dock:SetPoint("RIGHT", bar.zoomOut, "LEFT", -8, 0)
  bar.dock:SetScript("OnClick", function()
    B.UI.ToggleDock(B.UI.DOCK.city)
    updateDock()
  end)

  filterRow = CreateFrame("Frame", nil, content)
  filterRow:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -City.GAP)
  filterRow:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -City.GAP)

  clip = CreateFrame("Frame", nil, content)
  clip:SetClipsChildren(true)
  local back = S.fill(clip, S.C.sea)
  back:SetDrawLayer("BACKGROUND", -8)
  clip:EnableMouse(true)
  clip:EnableMouseWheel(true)
  clip:SetScript("OnMouseWheel", onWheel)
  clip:SetScript("OnMouseDown", onMouseDown)
  clip:SetScript("OnMouseUp", onMouseUp)

  ring = clip:CreateTexture(nil, "BORDER")
  ring:SetTexture(S.DISC)
  S.tint(ring, S.C.accent, 0.45)
  ring:SetSize(City.PIN + 12, City.PIN + 12)
  ring:Hide()
  arrow = clip:CreateTexture(nil, "OVERLAY")
  arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
  arrow:SetSize(28, 28)
  arrow:Hide()

  camera = ns.Camera.new(0, 600, 400)
  City.win, City.clip, City.bar = win, clip, bar
end

-- Opens the window on a place (the first one, or the last one shown); wx and wy centre it on a point.
function City.Open(city, wx, wy)
  if not City.Available() then
    return false
  end
  if not win then
    build()
  end
  win:Show()
  layoutBody()
  city = city or current or cities()[1]
  if city ~= current then
    City.Show(city)
  end
  if wx then
    camera:Center(wx, wy)
    viewChanged()
    drawRing()
  end
  return true
end

function City.Toggle()
  if win and win:IsShown() then
    win:Hide()
  else
    City.Open()
  end
end

function City.Camera()
  return camera
end

function City.Current()
  return current
end

function City.PinCount()
  return math.min(#pins, City.MAX_PINS)
end

-- --- the wiring ----------------------------------------------------------------------------------

table.insert(Map.onBuild, function()
  local button = S.tileButton(Map.toolbar, L["City map"], "zone", "accent")
  button.tip = function()
    return L["City & dungeon map"], L["The painted map of a city in its own window."]
  end
  button:SetScript("OnClick", City.Toggle)
  Map.toolbar.city = button
end)

table.insert(Map.onEnable, function(self)
  B:RegisterAction(self, {
    id = "map.city",
    main = { "zone", "npc", "object", "house" }, -- a button of the sheet (ADR 0054)
    label = L["Open city map"],
    short = L["City map"],
    icon = B.UI.IconTexture("zone"),
    types = "*",
    order = 11,
    when = function(ref)
      return City.Available() and City.Of(ref) ~= nil
    end,
    run = function(ref, ctx)
      local city, wx, wy = City.Of(ref)
      if not city then
        return false
      end
      if wx then
        B:Focus(ref, { source = ctx and ctx.source or "map.city" })
      end
      return City.Open(city, wx, wy)
    end,
  })
  -- the map's own lists: a module has one handler per bus message, and Pins and Layers hold those
  table.insert(Map.onFocus, function()
    if win and win:IsShown() then
      drawRing()
    end
  end)
  table.insert(Map.onLayerChanged, function()
    if win and win:IsShown() and current then
      self:Coalesce("cityPins", 0.1, function()
        layoutBody()
        viewChanged()
        drawPins()
      end)
    end
  end)
end)

ns.mod.City = City
