-- Pins (map.md): the renderer for every registered map layer. Layers are queried only when the view
-- settles (Map.onSettle), pins are projected and drawn on every view change (Map.onView) from pools;
-- grid clustering at low zoom, label priority with collision, areas with a radius, path lines, hover
-- tooltip from the entity, left click = primary action, right click = entity menu, a cluster click
-- zooms in. The layers panel toggles every registered layer, grouped by owner.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Widgets = B.UI.Widgets
local Map = ns.Map

local Pins = {}
ns.Pins = Pins

Pins.CLUSTER_LEVEL = 5 -- below this level pins that share a grid cell merge into a cluster
Pins.CLUSTER_CELL = 36 -- pixels
Pins.LABEL_LEVEL = 4 -- labels from this level on
Pins.LABEL_PRIORITY = 55 -- pins with a lower priority get no label
Pins.MAX_PINS = 400 -- live pin frames
Pins.AREA_ALPHA = 0.18
-- A soft disc for areas with a radius: Blizzard's round portrait mask (white, soft edge; both
-- clients ship it). When the client refuses the path the plain white square of before stays.
Pins.AREA_TEXTURE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
Pins.DASH, Pins.GAP = 10, 7 -- pixels of a dashed path segment (approximate route legs)
Pins.MAX_DASHES = 60 -- per segment; longer segments get longer dashes

local parent, mod
local layerPins = {} -- layerID -> array of pins (world coordinates) from the last query
local pinPool, areaPool, linePool, labelPool = {}, {}, {}, {} -- exposed below for the tests
Pins.pinPool, Pins.areaPool, Pins.linePool, Pins.labelPool = pinPool, areaPool, linePool, labelPool
local arrow
Pins.stats = { pins = 0, clusters = 0, labels = 0, areas = 0, lines = 0 }

local function db()
  return mod.db.profile
end

-- ---------------------------------------------------------------------------------------------
-- Layer state and queries
-- ---------------------------------------------------------------------------------------------

function Pins.IsLayerOn(def)
  local saved = db().layers[def.id]
  if saved == nil then
    return def.defaultOn ~= false
  end
  return saved
end

function Pins.SetLayerOn(id, on)
  db().layers[id] = on and true or false
  Pins.Requery()
end

-- Ask every enabled layer for the pins of the current view, then draw.
function Pins.Query(cam, view)
  layerPins = {}
  for _, def in ipairs(B:GetMapLayers()) do
    if Pins.IsLayerOn(def) then
      layerPins[def.id] = B:QueryLayer(def.id, view)
    end
  end
  Pins.Render(cam)
end

function Pins.Requery()
  local cam = Map.Camera()
  if cam and Map.IsShown() then
    Pins.Query(cam, cam:View(Map.PlayerWorld()))
  end
end

-- ---------------------------------------------------------------------------------------------
-- Pools
-- ---------------------------------------------------------------------------------------------

-- The subject a pin stands for: the one quest behind a giver pin, else the pin's own ref.
local function pinSubject(pin)
  local quests = pin.quests
  if quests and #quests == 1 then
    return "quest:" .. quests[1]
  end
  return pin.ref
end

Pins.CARD_REWARDS = 3 -- reward rows a quest's mini-card lists at most (R8)

-- The mini-card of a pin as data (C7, ADR 0014): the name, the status words (or the summary), the
-- worth line, the distance, what the layer wants said (the giver's quests) and the hint. From
-- Bastians.UI.Card, so the words are the band's words.
function Pins.MiniCardData(pin)
  local ref = pinSubject(pin)
  if not ref then
    return nil
  end
  local card = B.UI.Card(ref, { source = "map" })
  local lines = {}
  for _, line in ipairs(pin.lines or {}) do
    lines[#lines + 1] = line
  end
  -- a quest's rewards: up to three rows of the quest's Rewards
  -- section (money, xp, reputation or renown, the items), as the page lists them
  if B.Entity.Parse(ref) == "quest" then
    for _, s in ipairs(B:GetDetailSections(ref)) do
      if s.id == "quests.rewards" then
        local n = 0
        for _, row in ipairs(s.rows) do
          if n >= Pins.CARD_REWARDS then
            break
          end
          if row.kind ~= "para" and row.text then
            n = n + 1
            local value = row.value ~= nil and B.UI.FormatValue(row.value, row.valueKind) or nil
            lines[#lines + 1] = L["Reward"] .. ": " .. row.text .. (value and ("  " .. value) or "")
          end
        end
        break
      end
    end
  end
  local yards = card.distance
  if not yards and pin.wx and pin.wy then -- a quest behind a giver: the pin's own place
    local continent, wx, wy = B.Coords.Player()
    local cam = Map.Camera and Map.Camera() or nil
    if continent and cam and cam.continent == continent then
      yards = math.sqrt((pin.wx - wx) ^ 2 + (pin.wy - wy) ^ 2)
    end
  end
  return {
    ref = ref,
    name = pin.label or card.name,
    words = card.status or card.summary,
    worth = card.worth and card.worth.text or nil,
    distance = B.UI.Distance(yards),
    lines = lines,
    layer = pin.layer,
    hint = L["Click to open"],
  }
end

local miniCard -- one frame, made on the first hover (the map is shown then)
Pins.CARD_W = 260 -- the mini-card's width; its lines wrap to three at most

-- The lines a text takes on the card: the client's measure when it has one, else an estimate.
function Pins.CardLines(fs, text)
  local h = fs.GetStringHeight and fs:GetStringHeight() or 0
  if h and h > 0 then
    return math.min(3, math.max(1, math.floor(h / 12 + 0.5)))
  end
  local plain = string.gsub(string.gsub(text or "", "|c%x%x%x%x%x%x%x%x", ""), "|r", "")
  local chars = math.floor((Pins.CARD_W - 16) / 5.5)
  return math.min(3, math.max(1, math.ceil(#plain / chars)))
end

local function miniCardFrame()
  if miniCard then
    return miniCard
  end
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetFrameStrata("TOOLTIP")
  f:SetWidth(Pins.CARD_W)
  S.panel(f, S.C.panel)
  f.name = S.text(f, 13, S.C.accent)
  f.name:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -6)
  f.name:SetPoint("RIGHT", f, "RIGHT", -8, 0)
  f.name:SetJustifyH("LEFT")
  f.rows = {}
  for i = 1, 8 do
    local fs = S.text(f, 11, S.C.dim)
    fs:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(true) -- a long reward or worth line wraps
    fs:SetMaxLines(3)
    fs:Hide()
    f.rows[i] = fs
  end
  f:Hide()
  miniCard = f
  Pins.miniCard = f
  return f
end

-- Shows the mini-card beside the pin: name, words, worth (gold), distance, the layer's lines, hint.
local function showMiniCard(frame, data)
  local f = miniCardFrame()
  f.name:SetText(data.name or "?")
  local y = 6 + 17
  local n = 0
  local function line(text, color)
    if not text or text == "" then
      return
    end
    n = n + 1
    local fs = f.rows[n]
    if not fs then
      return
    end
    fs:SetText(text)
    fs:SetTextColor(color[1], color[2], color[3], 1)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -y)
    fs:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    fs:Show()
    y = y + 2 + 12 * Pins.CardLines(fs, text)
  end
  line(data.words, S.C.text)
  line(data.worth and (L["worth"] .. " " .. data.worth) or nil, S.C.gold)
  line(data.distance, S.C.dim)
  for _, text in ipairs(data.lines) do
    line(text, S.C.text)
  end
  line(data.hint, S.C.dim)
  for i = n + 1, #f.rows do
    f.rows[i]:Hide()
  end
  f.lineCount = n
  f:SetHeight(y + 4)
  f:ClearAllPoints()
  f:SetPoint("BOTTOMLEFT", frame, "TOPRIGHT", 4, 0)
  f.ref = data.ref
  f:Show()
end

function Pins.HideMiniCard()
  if miniCard then
    miniCard:Hide()
  end
end

-- Hover: a cluster says how many pins it holds (the game tooltip), an entity pin shows its
-- mini-card (C7); the map's own entity tooltip is gone.
local function showHover(frame)
  local pin = frame.pin
  if not pin then
    return
  end
  if pin.isCluster then
    if GameTooltip then
      GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
      GameTooltip:AddLine(string.format(L["%d pins"], pin.count), 1, 1, 1)
      S.TipLine(GameTooltip, L["Click to zoom in"], "tipDim")
      GameTooltip:Show()
    end
    return
  end
  local data = Pins.MiniCardData(pin)
  if data then
    showMiniCard(frame, data)
  end
end

local function onPinClick(frame, button)
  local pin = frame.pin
  if not pin then
    return
  end
  if pin.isCluster then -- a cluster frame, not a pin that may be clustered
    Map.ZoomAt(frame.sx, frame.sy, 2)
    return
  end
  if pin.onClick then
    pin.onClick(pin, button)
    return
  end
  if not pin.ref then
    return
  end
  local ctx = { source = "map", button = button }
  if button == "RightButton" then
    B.UI.EntityMenu(pin.ref, frame, ctx)
  else
    -- a left click focuses the entity (ADR 0013 D: the ring, the strip, the Browser's page when
    -- it is open); one quest behind the pin is the subject instead of the giver (owner,
    -- 22.10.2026: the quest sign must give the quest, with its rewards, text, chain, Route and Play)
    local ref = pinSubject(pin)
    B:Focus(ref, ctx)
    local action = B:GetPrimaryAction(pin.ref, ctx)
    if action and action.id ~= "map.show" then
      B:RunAction(action.id, pin.ref, ctx)
    elseif B:GetAction("browser.open") then
      B:RunAction("browser.open", ref, ctx) -- the entity is in view already: open its page
    end
  end
end

-- The pin scripts, shared with the minimap overlay (Minimap.lua): the same hover card, the
-- same click, the same leave.
Pins.HoverPin = showHover
Pins.ClickPin = onPinClick
function Pins.LeavePin()
  if GameTooltip then
    GameTooltip:Hide()
  end
  Pins.HideMiniCard()
end

-- Whether a pin stands for the ref: its own ref, or the one quest behind a giver pin.
function Pins.PinHas(pin, ref)
  if pin.ref == ref then
    return true
  end
  local quests = pin.quests
  return quests ~= nil and #quests == 1 and ("quest:" .. quests[1]) == ref
end

local function pinFrame(i)
  local f = pinPool[i]
  if not f then
    f = CreateFrame("Button", nil, parent)
    f:SetSize(16, 16)
    f.ring = f:CreateTexture(nil, "BACKGROUND") -- the focus ring (ADR 0013 D)
    f.ring:SetTexture(S.WHITE)
    S.tint(f.ring, S.C.accent, 0.45)
    f.ring:SetPoint("CENTER")
    f.ring:Hide()
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.count = S.text(f, 10, S.C.text)
    f.count:SetPoint("CENTER")
    f.count:SetJustifyH("CENTER")
    f.count:Hide()
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:SetScript("OnClick", onPinClick)
    f:SetScript("OnEnter", showHover)
    f:SetScript("OnLeave", Pins.LeavePin)
    pinPool[i] = f
  end
  return f
end

local areaFile -- what the client accepted for the disc: Pins.AREA_TEXTURE or S.WHITE

local function areaTexture(i)
  local t = areaPool[i]
  if not t then
    t = parent:CreateTexture(nil, "BORDER")
    if areaFile == nil then
      areaFile = t:SetTexture(Pins.AREA_TEXTURE) and Pins.AREA_TEXTURE or S.WHITE
    end
    t:SetTexture(areaFile)
    t:SetBlendMode("BLEND")
    areaPool[i] = t
  end
  return t
end

-- The soft disc's radius in pixels for a pin at the camera's scale, nil when it would be too small.
function Pins.AreaRadius(pin, cam)
  if not (pin.radius and pin.radius > 0) then
    return nil
  end
  local r = pin.radius * cam:Scale()
  return r >= 4 and r or nil
end

local function placeArea(a, sx, sy, r)
  a:ClearAllPoints()
  a:SetPoint("CENTER", parent, "TOPLEFT", sx, -sy)
  a:SetSize(r * 2, r * 2)
  a:Show()
end

local function lineTexture(i)
  local t = linePool[i]
  if not t then
    t = parent:CreateTexture(nil, "ARTWORK")
    t:SetTexture(S.WHITE)
    linePool[i] = t
  end
  return t
end

local function labelText(i)
  local fs = labelPool[i]
  if not fs then
    fs = S.text(parent, 11, S.C.text)
    fs:SetJustifyH("CENTER")
    labelPool[i] = fs
  end
  return fs
end

local function hideFrom(pool, n)
  for i = n + 1, #pool do
    pool[i]:Hide()
  end
end

-- ---------------------------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------------------------

-- One straight piece between two screen points as a rotated texture; `w1`, `w2` are the piece's
-- world end points kept on the texture for Pins.Reposition.
local function placePiece(t, x1, y1, x2, y2, width, w1, w2)
  local dx, dy = x2 - x1, y2 - y1
  local len = math.sqrt(dx * dx + dy * dy)
  t.w1, t.w2, t.width = w1, w2, width
  if len < 1 then
    t:Hide()
    return
  end
  t:ClearAllPoints()
  t:SetPoint("CENTER", parent, "TOPLEFT", (x1 + x2) / 2, -(y1 + y2) / 2)
  t:SetSize(len, width or 2)
  t:SetRotation(math.atan2(-dy, dx))
  t:Show()
end

-- A segment between two world points (projected to `x1, y1`..`x2, y2`): solid, or dashed for
-- `style` "dashed" or "dotted" (approximate route legs, core-contracts §6). Returns the number of
-- line textures used from index `i` on.
local function drawSegment(i, x1, y1, x2, y2, color, width, style, w1, w2)
  local dx, dy = x2 - x1, y2 - y1
  local len = math.sqrt(dx * dx + dy * dy)
  local r, g, b, a = color[1], color[2], color[3], color[4] or 0.9
  if not (style == "dashed" or style == "dotted") or len <= Pins.DASH * 2 then
    local t = lineTexture(i)
    t:SetVertexColor(r, g, b, a)
    placePiece(t, x1, y1, x2, y2, width, w1, w2)
    return 1
  end
  local dash, gap = Pins.DASH, Pins.GAP
  local n = math.floor(len / (dash + gap))
  if n > Pins.MAX_DASHES then
    n = Pins.MAX_DASHES
    dash = len / n - gap
  end
  local step = n > 1 and (len - dash) / (n - 1) or 0 -- the first dash starts, the last one ends the segment
  local used = 0
  for k = 0, n - 1 do
    local f1, f2 = (k * step) / len, (k * step + dash) / len
    local t = lineTexture(i + used)
    t:SetVertexColor(r, g, b, a)
    placePiece(
      t,
      x1 + dx * f1,
      y1 + dy * f1,
      x1 + dx * f2,
      y1 + dy * f2,
      width,
      w1 and { w1[1] + (w2[1] - w1[1]) * f1, w1[2] + (w2[2] - w1[2]) * f1 } or nil,
      w1 and { w1[1] + (w2[1] - w1[1]) * f2, w1[2] + (w2[2] - w1[2]) * f2 } or nil
    )
    used = used + 1
  end
  return used
end

-- Projects the queried pins: clusters at low zoom, then draws areas, lines, pins and labels.
function Pins.Render(cam)
  if not parent then
    return
  end
  local level = cam.level
  local clustering = level < Pins.CLUSTER_LEVEL
  local cells, drawn = {}, {}
  local lines = 0
  for layerID, pins in pairs(layerPins) do
    local def = B:GetMapLayer(layerID)
    for _, pin in ipairs(pins) do
      if pin.kind == "path" then
        local prev, prevWorld
        for _, pt in ipairs(pin.points or {}) do
          local sx, sy = cam:ToScreen(pt[1], pt[2])
          if prev then
            lines = lines
              + drawSegment(
                lines + 1,
                prev[1],
                prev[2],
                sx,
                sy,
                pin.color or S.C.accent,
                pin.width,
                pin.style,
                prevWorld,
                pt
              )
          end
          prev, prevWorld = { sx, sy }, pt
        end
      elseif pin.wx and pin.wy then
        local sx, sy = cam:ToScreen(pin.wx, pin.wy)
        if sx >= -32 and sy >= -32 and sx <= cam.width + 32 and sy <= cam.height + 32 then
          local entry = { pin = pin, sx = sx, sy = sy, layer = def and def.label or layerID }
          if clustering and pin.cluster ~= false then
            local key = math.floor(sx / Pins.CLUSTER_CELL) .. ":" .. math.floor(sy / Pins.CLUSTER_CELL)
            local cell = cells[key]
            if cell then
              cell.count = cell.count + 1
              cell.sx = (cell.sx * (cell.count - 1) + sx) / cell.count
              cell.sy = (cell.sy * (cell.count - 1) + sy) / cell.count
              if (pin.priority or 50) > (cell.pin.priority or 50) then
                cell.pin = pin
              end
            else
              cell = { pin = pin, sx = sx, sy = sy, count = 1, layer = entry.layer }
              cells[key] = cell
              drawn[#drawn + 1] = cell
            end
          else
            entry.count = 1
            drawn[#drawn + 1] = entry
          end
        end
      end
    end
  end
  hideFrom(linePool, lines)
  table.sort(drawn, function(a, b)
    return (a.pin.priority or 50) > (b.pin.priority or 50)
  end)

  local pinsDrawn, clusters, areas, labels = 0, 0, 0, 0
  local labelRects = {}
  local focused = B:Focused()
  for _, d in ipairs(drawn) do
    if pinsDrawn >= Pins.MAX_PINS then
      break
    end
    local pin = d.pin
    pinsDrawn = pinsDrawn + 1
    local f = pinFrame(pinsDrawn)
    f.sx, f.sy = d.sx, d.sy
    local size = pin.size or 16
    if d.count > 1 then
      clusters = clusters + 1
      f.pin = { isCluster = true, count = d.count, layer = d.layer }
      size = 22
      f.icon:SetTexture(S.WHITE)
      S.tint(f.icon, S.C.accent, 0.8)
      f.count:SetText(tostring(d.count))
      f.count:Show()
    else
      f.pin = pin
      pin.layer = d.layer
      B.UI.PaintIcon(f.icon, pin.icon or B.UI.IconTexture("other"))
      if pin.color then
        S.tint(f.icon, pin.color) -- a layer's state colour wins (quest states)
      end
      f.count:Hide()
      local r = Pins.AreaRadius(pin, cam)
      if r then
        areas = areas + 1
        local a = areaTexture(areas)
        a.pin = pin
        S.tint(a, pin.color or S.C.accent, Pins.AREA_ALPHA)
        placeArea(a, d.sx, d.sy, r)
      end
      if pin.label and level >= Pins.LABEL_LEVEL and (pin.priority or 50) >= Pins.LABEL_PRIORITY then
        local w = #pin.label * 6 + 8
        local lx1, ly1 = d.sx - w / 2, d.sy + size / 2
        local free = true
        for _, rect in ipairs(labelRects) do
          if lx1 < rect[3] and lx1 + w > rect[1] and ly1 < rect[4] and ly1 + 14 > rect[2] then
            free = false
            break
          end
        end
        if free then
          labels = labels + 1
          labelRects[#labelRects + 1] = { lx1, ly1, lx1 + w, ly1 + 14 }
          local fs = labelText(labels)
          fs:SetText(pin.label)
          fs.pin, fs.below = pin, size / 2 + 1
          fs:ClearAllPoints()
          fs:SetPoint("TOP", parent, "TOPLEFT", d.sx, -(d.sy + fs.below))
          fs:Show()
        end
      end
    end
    f.wx, f.wy = cam:ToWorld(d.sx, d.sy) -- a cluster's centre has no pin to ask later
    f:SetSize(size, size)
    f:ClearAllPoints()
    f:SetPoint("CENTER", parent, "TOPLEFT", d.sx, -d.sy)
    if focused and d.count == 1 and Pins.PinHas(pin, focused) then
      f.ring:SetSize(size + 10, size + 10)
      f.ring:Show()
    else
      f.ring:Hide()
    end
    f:Show()
  end
  hideFrom(pinPool, pinsDrawn)
  hideFrom(areaPool, areas)
  hideFrom(labelPool, labels)
  Pins.UpdateArrow(cam)
  Pins.stats.pins, Pins.stats.clusters, Pins.stats.areas, Pins.stats.labels, Pins.stats.lines =
    pinsDrawn, clusters, areas, labels, lines
end

-- Moves every shown pin, area, label and path piece to where it lies for the camera, from the
-- world positions kept at the last render: what a resize in progress needs, no query, no sort,
-- no clustering (those follow once after the last event).
function Pins.Reposition(cam)
  if not parent then
    return
  end
  for i = 1, Pins.stats.pins do
    local f = pinPool[i]
    if f and f.wx and f:IsShown() then
      f.sx, f.sy = cam:ToScreen(f.wx, f.wy)
      f:ClearAllPoints()
      f:SetPoint("CENTER", parent, "TOPLEFT", f.sx, -f.sy)
    end
  end
  for i = 1, Pins.stats.areas do
    local a = areaPool[i]
    local r = a and a.pin and Pins.AreaRadius(a.pin, cam)
    if r then
      local sx, sy = cam:ToScreen(a.pin.wx, a.pin.wy)
      placeArea(a, sx, sy, r)
    elseif a then
      a:Hide()
    end
  end
  for i = 1, Pins.stats.labels do
    local fs = labelPool[i]
    if fs and fs.pin and fs:IsShown() then
      local sx, sy = cam:ToScreen(fs.pin.wx, fs.pin.wy)
      fs:ClearAllPoints()
      fs:SetPoint("TOP", parent, "TOPLEFT", sx, -(sy + (fs.below or 9)))
    end
  end
  for i = 1, Pins.stats.lines do
    local t = linePool[i]
    if t and t.w1 and t.w2 then
      local x1, y1 = cam:ToScreen(t.w1[1], t.w1[2])
      local x2, y2 = cam:ToScreen(t.w2[1], t.w2[2])
      placePiece(t, x1, y1, x2, y2, t.width, t.w1, t.w2)
    end
  end
  Pins.UpdateArrow(cam)
end

-- The player arrow: position from Coords.Player, rotation from the facing.
function Pins.UpdateArrow(cam)
  if not parent then
    return
  end
  if not arrow then
    arrow = parent:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
    arrow:SetSize(28, 28)
  end
  cam = cam or Map.Camera()
  local continent, wx, wy = B.Coords.Player()
  if not (cam and continent == cam.continent and cam:Contains(wx, wy, 14)) then
    arrow:Hide()
    return
  end
  local sx, sy = cam:ToScreen(wx, wy)
  arrow:ClearAllPoints()
  arrow:SetPoint("CENTER", parent, "TOPLEFT", sx, -sy)
  arrow:SetRotation(B.Compat.GetPlayerFacing() or 0)
  arrow:Show()
end

function Pins.Arrow()
  return arrow
end

-- ---------------------------------------------------------------------------------------------
-- Layers panel
-- ---------------------------------------------------------------------------------------------

local panel

function Pins.TogglePanel()
  if panel and panel:IsShown() then
    panel:Hide()
    return
  end
  if not panel then
    panel = CreateFrame("Frame", nil, Map.win.frame)
    panel:SetFrameStrata("DIALOG")
    panel:SetPoint("TOPRIGHT", Map.clip, "TOPRIGHT", -4, -4)
    panel:SetWidth(220)
    S.panel(panel, S.C.panel)
    panel.rows = {}
    panel.title = S.text(panel, 13, S.C.accent)
    panel.title:SetPoint("TOPLEFT", 8, -6)
    panel.title:SetText(L["Layers"])
  end
  Pins.RefreshPanel()
  panel:Show()
end

function Pins.RefreshPanel()
  if not panel then
    return
  end
  local y = -26
  local n = 0
  local lastOwner
  for _, def in ipairs(B:GetMapLayers()) do
    local owner = def.owner.title or def.owner.name
    if owner ~= lastOwner then
      n = n + 1
      local row = panel.rows[n]
      if not row or row.kind ~= "header" then
        row = Widgets.Header(panel, owner)
        row.kind = "header"
        panel.rows[n] = row
      end
      row:SetText(owner)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", 8, y)
      row:SetPoint("RIGHT", -8, 0)
      row:Show()
      y = y - 22
      lastOwner = owner
    end
    n = n + 1
    local row = panel.rows[n]
    if not row or row.kind ~= "toggle" then
      row = Widgets.Checkbox(panel, "", nil)
      row.kind = "toggle"
      panel.rows[n] = row
    end
    row.layerID = def.id
    row.label:SetText(def.label or def.id)
    row:SetChecked(Pins.IsLayerOn(def))
    row:SetScript("OnClick", function(self)
      self:SetChecked(not self.checked)
      Pins.SetLayerOn(self.layerID, self.checked)
    end)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 12, y)
    row:SetPoint("RIGHT", -8, 0)
    row:Show()
    y = y - 22
  end
  for i = n + 1, #panel.rows do
    panel.rows[i]:Hide()
  end
  panel:SetHeight(-y + 8)
  panel.count = n
end

function Pins.Panel()
  return panel
end

-- ---------------------------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------------------------

table.insert(Map.onBuild, function(clip)
  parent = clip
  local button = S.button(Map.toolbar, L["Layers"], 60, 22)
  button.tip = L["Which layers the map shows: quests, NPCs, nodes, routes and more."]
  button:SetPoint("RIGHT", Map.toolbar.zoomOut, "LEFT", -8, 0)
  button:SetScript("OnClick", Pins.TogglePanel)
  Map.toolbar.layers = button
end)
table.insert(Map.onView, Pins.Render)
table.insert(Map.onResize, Pins.Reposition)
table.insert(Map.onSettle, Pins.Query)
table.insert(Map.onTick, function()
  Pins.UpdateArrow()
end)
table.insert(Map.onEnable, function(self)
  mod = self
  self:On("BASTIANS_THEME_CHANGED", function(me) -- the pins take the theme's colours (ST3)
    me:Coalesce("requery", 0.1, Pins.Requery)
    for _, fn in ipairs(Map.onLayerChanged) do
      fn()
    end
  end)
  self:On("BASTIANS_LAYER_CHANGED", function(me)
    me:Coalesce("requery", 0.1, Pins.Requery)
    for _, fn in ipairs(Map.onLayerChanged) do
      fn() -- the minimap overlay (one bus handler per message and module)
    end
  end)
  table.insert(Map.onFocus, function()
    local cam = Map.Camera()
    if cam and Map.IsShown() then
      Pins.Render(cam) -- the ring moves to the focused pin
    end
  end)
  self:On("BASTIANS_REGISTRY_CHANGED", function(me, _, kind)
    if kind == "layer" then
      me:Coalesce("requery", 0.1, Pins.Requery)
      for _, fn in ipairs(Map.onLayerChanged) do
        fn()
      end
      if panel and panel:IsShown() then
        Pins.RefreshPanel()
      end
    end
  end)
end)
ns.mod.Pins = Pins
