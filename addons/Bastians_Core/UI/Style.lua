-- UI kit: flat style (core-contracts §13). The theme's surfaces, 1 px lines, one accent colour, no
-- Blizzard templates. Ported from AHSyncGuide Style.lua; the font comes from Core's profile, the
-- colours from the theme (ST3, ADR 0017), EllesmereUI is optional.
local _, ns = ...
local B = ns.B

B.UI = B.UI or {}
local S = {}
B.UI.Style = S
ns.Style = S

local WHITE = "Interface\\Buttons\\WHITE8X8"
S.WHITE = WHITE
S.DEFAULT_FONT = "Fonts\\ARIALN.TTF"
-- The suite's own textures (tools/make_media.py): a 64x64 white arrow with a dark rim pointing
-- east, tinted with SetVertexColor and turned with SetRotation.
S.ARROW = "Interface\\AddOns\\Bastians_Core\\Media\\Arrow"

-- The colour tokens of the active theme (ST3, ADR 0017; the themes are UI/Themes.lua, compiled from
-- pipeline/config/themes/*.toml). S.C holds one table { r, g, b, a } per token. A theme change
-- writes the new values into the same tables, so a widget that kept `S.C.accent` sees the new
-- colour at its next draw; the kit re-colours what it drew itself (fills, edges, texts) and
-- BASTIANS_THEME_CHANGED asks the apps to draw again. S.H holds the tokens as "|cffRRGGBB" for
-- text (strings cannot change in place: read S.H at use, never keep it in a local). S.SHAPE
-- holds the corner radii.
S.C = {}
S.H = {}
S.SHAPE = { radius = 0, radiusSmall = 0 }
S.THEMES = ns.THEMES or {}

-- What the kit drew with a token: texture -> { token table, alpha }, font string -> token table.
S.painted = setmetatable({}, { __mode = "k" })
S.inked = setmetatable({}, { __mode = "k" })

local function hexOf(c)
  return string.format("|cff%02x%02x%02x", c[1] * 255 + 0.5, c[2] * 255 + 0.5, c[3] * 255 + 0.5)
end

local function themeById(id)
  for _, theme in ipairs(S.THEMES) do
    if theme.id == id then
      return theme
    end
  end
  return S.THEMES[1]
end

-- The themes to choose from: { { id, name } } in their order.
function S.Themes()
  local out = {}
  for _, theme in ipairs(S.THEMES) do
    out[#out + 1] = { id = theme.id, name = theme.name }
  end
  return out
end

-- The id of the theme in use.
function S.ThemeId()
  return S.themeId
end

-- Writes a theme's values into the token tables (an unknown id falls back to the first theme).
local function loadTheme(id)
  local theme = themeById(id)
  if not theme then
    return
  end
  S.themeId = theme.id
  for token, value in pairs(theme.colors) do
    local c = S.C[token]
    if not c then
      c = {}
      S.C[token] = c
    end
    c[1], c[2], c[3], c[4] = value[1], value[2], value[3], value[4] or 1
    S.H[token] = hexOf(c)
  end
  for key, value in pairs(theme.shape or {}) do
    S.SHAPE[key] = value
  end
end
loadTheme(S.THEMES[1] and S.THEMES[1].id)

local function eui()
  return _G.EllesmereUI
end

-- Take EllesmereUI's accent colour when it is loaded (optional bridge, never required).
function S.adopt()
  local E = eui()
  if E and E.GetAccentColor then
    local ok, r, g, b = pcall(E.GetAccentColor)
    if ok and r then
      local c = S.C.accent
      c[1], c[2], c[3] = r, g, b
      S.H.accent = hexOf(c)
    end
  end
end

-- Switches the theme: the tokens, then what the kit drew, then the apps (BASTIANS_THEME_CHANGED).
function S.ApplyTheme(id)
  loadTheme(id)
  S.adopt()
  for tex, paint in pairs(S.painted) do
    local c = paint[1]
    tex:SetVertexColor(c[1], c[2], c[3], paint[2] or c[4] or 1)
  end
  for fs, c in pairs(S.inked) do
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
  end
  for shape in pairs(S.shapes or {}) do
    shape:Layout() -- the theme's radius
  end
  B:Fire("BASTIANS_THEME_CHANGED", S.themeId)
end

-- Colours a texture with a token (and an alpha of its own), kept for the next theme change.
function S.tint(tex, color, alpha)
  S.painted[tex] = { color, alpha }
  tex:SetVertexColor(color[1], color[2], color[3], alpha or color[4] or 1)
end

-- Colours a text with a token, kept for the next theme change.
function S.ink(fs, color)
  S.inked[fs] = color
  fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

-- A tooltip line in a tooltip-safe token (tipText, tipDim, tipGold): the game's tooltip stays dark
-- in every theme, so its words never take the window's text colours.
function S.TipLine(tooltip, text, token, wrap)
  local c = S.C[token or "tipText"] or S.C.tipText
  tooltip:AddLine(text, c[1], c[2], c[3], wrap)
end

-- A texture back to its own colours (the game's icons): no token, nothing kept.
function S.untint(tex)
  S.painted[tex] = nil
  tex:SetVertexColor(1, 1, 1, 1)
end

-- Every font string the kit made, with its size, so a font change applies at once (weak keys).
S.fonts = setmetatable({}, { __mode = "k" })

function S.font()
  local core = ns.core -- Core's module, once Settings.lua has created and initialized it
  local font = core and core.db and core.db.profile.font
  if font then
    return font
  end
  local E = eui()
  if E and E.GetFontPath then
    local ok, path = pcall(E.GetFontPath)
    if ok and path then
      return path
    end
  end
  return S.DEFAULT_FONT
end

-- The text size in percent of the kit's sizes (General page, "and a
-- size, naturally"); rows keep their height, so the range stays 80 to 130.
function S.scale()
  local core = ns.core
  local pct = core and core.db and tonumber(core.db.profile.fontScale) or 100
  return math.max(80, math.min(130, pct)) / 100
end

-- A base size scaled to the setting.
function S.size(base)
  return math.floor((base or 12) * S.scale() + 0.5)
end

-- Sets a kit text's base size (scaled), kept for the next font or size change.
function S.setSize(fs, base)
  S.fonts[fs] = base
  fs:SetFont(S.font(), S.size(base), "")
end

function S.applyFont()
  local path = S.font()
  for fs, size in pairs(S.fonts) do
    fs:SetFont(path, S.size(size), "")
  end
end

function S.hex(c)
  return hexOf(c)
end

function S.accent()
  return S.H.accent
end

function S.text(parent, size, color, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  fs:SetFont(S.font(), S.size(size or 12), "")
  S.fonts[fs] = size or 12
  S.ink(fs, color or S.C.text)
  fs:SetJustifyH("LEFT")
  fs:SetShadowOffset(1, -1)
  return fs
end

function S.fill(frame, color, layer)
  local t = frame:CreateTexture(nil, layer or "BACKGROUND")
  t:SetTexture(WHITE)
  t:SetAllPoints()
  S.tint(t, color)
  return t
end

-- 1 px outline from four textures (no backdrop template needed on any client).
function S.border(frame, color)
  local c = color or S.C.line
  local edges = {}
  for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    local t = frame:CreateTexture(nil, "BORDER")
    t:SetTexture(WHITE)
    S.tint(t, c)
    if side == "TOP" or side == "BOTTOM" then
      t:SetPoint(side .. "LEFT")
      t:SetPoint(side .. "RIGHT")
      t:SetHeight(1)
    else
      t:SetPoint("TOP" .. side)
      t:SetPoint("BOTTOM" .. side)
      t:SetWidth(1)
    end
    edges[side] = t
  end
  return edges
end

-- ---------------------------------------------------------------------------------------------
-- Round corners. A shape is
-- a fill or a 1 px outline made of pieces: four corners cut from Media/Disc (a disc's quarters) or
-- Media/Ring* (its outline), and WHITE8X8 bands between them. The radius is a theme token
-- ("radius", "radiusSmall"), a number, or "pill" (half the frame's height); a theme switch lays the
-- shapes out again. `corners` = "all" (default), "top" or "bottom": the others stay square. A
-- shape answers SetVertexColor, GetVertexColor, SetAlpha, Show, Hide like the texture it replaces,
-- so S.tint, S.setEdges and `frame.bg` work on it.
-- ---------------------------------------------------------------------------------------------

S.DISC = "Interface\\AddOns\\Bastians_Core\\Media\\Disc"
S.RINGS = {
  S = "Interface\\AddOns\\Bastians_Core\\Media\\RingS",
  M = "Interface\\AddOns\\Bastians_Core\\Media\\RingM",
  L = "Interface\\AddOns\\Bastians_Core\\Media\\RingL",
}
local CORNERS = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
local QUARTER = {
  TOPLEFT = { 0, 0.5, 0, 0.5 },
  TOPRIGHT = { 0.5, 1, 0, 0.5 },
  BOTTOMLEFT = { 0, 0.5, 0.5, 1 },
  BOTTOMRIGHT = { 0.5, 1, 0.5, 1 },
}
local Shape = {}
Shape.__index = Shape
S.Shape = Shape
S.shapes = setmetatable({}, { __mode = "k" }) -- every shape, laid out again on a theme switch

-- The ring whose line stays about one pixel wide at a corner of r pixels (tools/make_media.py).
function S.RingFor(r)
  if r <= 4 then
    return S.RINGS.S
  elseif r <= 7 then
    return S.RINGS.M
  end
  return S.RINGS.L
end

function Shape:Radius()
  local r = self.radius
  if r == "pill" then
    r = math.floor((self.frame:GetHeight() or 0) / 2)
  elseif type(r) == "string" then
    r = S.SHAPE[r] or 0
  end
  r = r or 0
  local w, h = self.frame:GetWidth() or 0, self.frame:GetHeight() or 0
  if w > 0 and h > 0 then
    r = math.min(r, math.floor(math.min(w, h) / 2)) -- a small frame never folds over itself
  end
  return math.max(0, r)
end

function Shape:Rounded(corner)
  local c = self.corners
  if c == "top" then
    return corner == "TOPLEFT" or corner == "TOPRIGHT"
  elseif c == "bottom" then
    return corner == "BOTTOMLEFT" or corner == "BOTTOMRIGHT"
  end
  return true
end

function Shape:Piece(i)
  local t = self.pieces[i]
  if not t then
    t = self.frame:CreateTexture(nil, self.layer)
    self.pieces[i] = t
    local c = self.color
    if c then
      t:SetVertexColor(c[1], c[2], c[3], c[4])
    end
  end
  return t
end

local function band(t, f, p1, x1, y1, p2, x2, y2)
  t:SetTexture(S.WHITE)
  t:SetTexCoord(0, 1, 0, 1)
  t:ClearAllPoints()
  t:SetPoint(p1, f, p1, x1, y1)
  t:SetPoint(p2, f, p2, x2, y2)
end

-- Lays the pieces out for the current radius (after a theme switch, a pill's new height).
function Shape:Layout()
  local f, r = self.frame, self:Radius()
  self.r = r
  for i, corner in ipairs(CORNERS) do
    local t = self:Piece(i)
    t:ClearAllPoints()
    if r > 0 and self:Rounded(corner) then
      t:SetTexture(self.outline and S.RingFor(r) or S.DISC)
      local q = QUARTER[corner]
      t:SetTexCoord(q[1], q[2], q[3], q[4])
      t:SetSize(r, r)
      t:SetPoint(corner, f, corner, 0, 0)
      t:Show()
    elseif r > 0 and not self.outline then -- a square corner of a fill
      t:SetTexture(S.WHITE)
      t:SetTexCoord(0, 1, 0, 1)
      t:SetSize(r, r)
      t:SetPoint(corner, f, corner, 0, 0)
      t:Show()
    else
      t:Hide()
    end
  end
  if self.outline then
    -- the straight lines stop where a rounded corner starts
    local tl = (r > 0 and self:Rounded("TOPLEFT")) and r or 0
    local tr = (r > 0 and self:Rounded("TOPRIGHT")) and r or 0
    local bl = (r > 0 and self:Rounded("BOTTOMLEFT")) and r or 0
    local br = (r > 0 and self:Rounded("BOTTOMRIGHT")) and r or 0
    local top, bottom, left, right = self:Piece(5), self:Piece(6), self:Piece(7), self:Piece(8)
    band(top, f, "TOPLEFT", tl, 0, "TOPRIGHT", -tr, 0)
    top:SetHeight(1)
    band(bottom, f, "BOTTOMLEFT", bl, 0, "BOTTOMRIGHT", -br, 0)
    bottom:SetHeight(1)
    band(left, f, "TOPLEFT", 0, -tl, "BOTTOMLEFT", 0, bl)
    left:SetWidth(1)
    band(right, f, "TOPRIGHT", 0, -tr, "BOTTOMRIGHT", 0, br)
    right:SetWidth(1)
    for i = 5, 8 do
      self.pieces[i]:Show()
    end
  else
    -- the middle band runs the full height; the side bands fill between the corners
    band(self:Piece(5), f, "TOPLEFT", r, 0, "BOTTOMRIGHT", -r, 0)
    local left, right = self:Piece(6), self:Piece(7)
    band(left, f, "TOPLEFT", 0, -r, "BOTTOMLEFT", 0, r)
    left:SetWidth(r)
    band(right, f, "TOPRIGHT", 0, -r, "BOTTOMRIGHT", 0, r)
    right:SetWidth(r)
    self.pieces[5]:Show()
    if r > 0 then
      left:Show()
      right:Show()
    else
      left:Hide()
      right:Hide()
    end
  end
  if self.hidden then
    self:Hide()
  end
end

function Shape:SetVertexColor(r, g, b, a)
  local c = self.color or {}
  c[1], c[2], c[3], c[4] = r, g, b, a or 1
  self.color = c
  for _, t in ipairs(self.pieces) do
    t:SetVertexColor(r, g, b, a or 1)
  end
end

function Shape:GetVertexColor()
  local c = self.color or { 1, 1, 1, 1 }
  return c[1], c[2], c[3], c[4]
end

function Shape:SetAlpha(a)
  for _, t in ipairs(self.pieces) do
    t:SetAlpha(a)
  end
end

function Shape:Show()
  self.hidden = nil
  self:Layout()
end

function Shape:Hide()
  self.hidden = true
  for _, t in ipairs(self.pieces) do
    t:Hide()
  end
end

function Shape:IsShown()
  return not self.hidden
end

local function newShape(frame, color, radius, layer, corners, outline)
  local shape = setmetatable({
    frame = frame,
    radius = radius or "radius",
    layer = layer,
    corners = corners or "all",
    outline = outline,
    pieces = {},
  }, Shape)
  S.shapes[shape] = true
  shape:Layout()
  S.tint(shape, color)
  return shape
end

-- A rounded fill of the frame in a token colour.
function S.roundFill(frame, color, radius, layer, corners)
  return newShape(frame, color or S.C.bg, radius, layer or "BACKGROUND", corners, false)
end

-- A rounded 1 px outline of the frame in a token colour.
function S.roundEdges(frame, color, radius, corners)
  return newShape(frame, color or S.C.line, radius, "BORDER", corners, true)
end

function S.setEdges(edges, c, alpha)
  if getmetatable(edges) == Shape then
    S.tint(edges, c, alpha)
    return
  end
  for _, e in pairs(edges) do
    S.tint(e, c, alpha)
  end
end

-- A window, menu or panel: a rounded fill with a rounded outline (the theme's radius).
function S.panel(frame, color, radius)
  frame.bg = S.roundFill(frame, color or S.C.bg, radius or "radius")
  frame.edges = S.roundEdges(frame, S.C.line, radius or "radius")
  return frame
end

-- Button tips ("an information text on every button of every addon,
-- shown after one second of hovering, the time set globally"). A widget carries `tip`: a string,
-- or a function(widget) returning the title and an optional second line. S.TipEnter starts the
-- wait, S.TipLeave cancels it; the kit's buttons call both. The delay comes from Core's General
-- page (`tipDelay`, seconds, default 1; `tips` off shows none).
local tipToken = 0

function S.TipDelay()
  local core = ns.core
  local profile = core and core.db and core.db.profile
  if profile and profile.tips == false then
    return nil
  end
  return profile and tonumber(profile.tipDelay) or 1
end

local function showTip(widget)
  local tip = widget.tip
  if not tip or not GameTooltip then
    return
  end
  local title, text
  if type(tip) == "function" then
    title, text = tip(widget)
  else
    title = tip
  end
  if not title or title == "" then
    return
  end
  GameTooltip:SetOwner(widget, "ANCHOR_TOP")
  local c = S.C.tipText
  GameTooltip:AddLine(title, c[1], c[2], c[3], true)
  if text and text ~= "" then
    c = S.C.tipDim
    GameTooltip:AddLine(text, c[1], c[2], c[3], true)
  end
  GameTooltip:Show()
  widget.tipShown = true
end

function S.TipEnter(widget)
  tipToken = tipToken + 1
  if not widget.tip then
    return
  end
  local delay = S.TipDelay()
  if not delay then
    return
  end
  if delay <= 0 then
    showTip(widget)
    return
  end
  local token = tipToken
  C_Timer.After(delay, function()
    if token == tipToken then -- still on the same widget: no leave, no other enter
      showTip(widget)
    end
  end)
end

function S.TipLeave(widget)
  tipToken = tipToken + 1
  if widget.tipShown then
    widget.tipShown = nil
    if GameTooltip then
      GameTooltip:Hide()
    end
  end
end

-- Flat button with a label. `accent` colours the label; hover lightens the face. `b.tip` (see
-- S.TipEnter) explains the button after the hover delay.
function S.button(parent, label, width, height, accent)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width or 80, height or 20)
  b.face = S.roundFill(b, S.C.panel, "radiusSmall")
  b.edges = S.roundEdges(b, S.C.line, "radiusSmall")
  b.label = S.text(b, 12, accent and S.C.accent or S.C.text)
  b.label:SetPoint("CENTER")
  b.label:SetJustifyH("CENTER")
  b.label:SetText(label or "")
  b:SetScript("OnEnter", function(self)
    if self.enabledFlat ~= false then
      S.tint(self.face, S.C.faceHover)
    end
    S.TipEnter(self)
  end)
  b:SetScript("OnLeave", function(self)
    S.tint(self.face, S.C.panel)
    S.TipLeave(self)
  end)
  function b.SetLabel(self, text)
    self.label:SetText(text)
  end
  function b.SetEnabledFlat(self, on)
    self.enabledFlat = on and true or false
    self:SetAlpha(on and 1 or 0.4)
  end
  return b
end

-- Search box: flat field with a hint text while empty and a clear button (ASCII "x", see CLAUDE.md §12).
function S.search(parent, hint)
  local box = CreateFrame("EditBox", nil, parent)
  box:SetHeight(22)
  box:SetAutoFocus(false)
  box:SetFont(S.font(), S.size(12), "")
  S.fonts[box] = 12
  S.ink(box, S.C.text)
  box:SetTextInsets(8, 22, 0, 0)
  box.face = S.roundFill(box, S.C.panel, "radiusSmall")
  box.edges = S.roundEdges(box, S.C.line, "radiusSmall")
  box.hint = S.text(box, 12, S.C.dim)
  box.hint:SetPoint("LEFT", 8, 0)
  box.hint:SetText(hint or "")
  box.clear = CreateFrame("Button", nil, box)
  box.clear:SetSize(18, 18)
  box.clear:SetPoint("RIGHT", -2, 0)
  box.clear.label = S.text(box.clear, 14, S.C.dim)
  box.clear.label:SetPoint("CENTER")
  box.clear.label:SetText("x")
  box.clear:SetScript("OnClick", function()
    box:SetText("")
    box:ClearFocus()
  end)
  box.clear:Hide()
  box:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)
  box:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
  end)
  box:SetScript("OnEditFocusGained", function(self)
    S.setEdges(self.edges, S.C.accent, 0.8)
  end)
  box:SetScript("OnEditFocusLost", function(self)
    S.setEdges(self.edges, S.C.line)
  end)
  return box
end

-- A slim scroll bar that follows a ScrollFrame; mouse wheel on the frame, the thumb can be dragged.
-- `onScroll` is called after every change so a virtual list can re-render.
function S.scrollbar(scroll, parent, onScroll)
  local track = CreateFrame("Frame", nil, parent)
  track:SetWidth(4)
  track:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, 0)
  track:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 0)
  S.fill(track, S.C.track)
  local thumb = CreateFrame("Frame", nil, track)
  thumb:SetWidth(4)
  thumb.tex = S.fill(thumb, S.C.accent)
  thumb.tex:SetAlpha(0.6)
  thumb:EnableMouse(true)
  track.thumb = thumb
  track.total = 0 -- content height, set by the owner (virtual lists do not size a scroll child)

  local function range()
    local view = scroll:GetHeight() or 0
    return math.max(0, track.total - view), view
  end

  function track.SetTotal(total)
    track.total = total or 0
    track.Update()
  end

  function track.Update()
    local rng, view = range()
    if rng <= 0 or view <= 0 then
      thumb:Hide()
      if (scroll:GetVerticalScroll() or 0) ~= 0 then
        scroll:SetVerticalScroll(0)
      end
      return
    end
    thumb:Show()
    local h = math.max(20, view * view / track.total)
    local off = scroll:GetVerticalScroll() or 0
    if off > rng then
      off = rng
      scroll:SetVerticalScroll(off)
    end
    thumb:SetHeight(h)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPLEFT", track, "TOPLEFT", 0, -(view - h) * off / rng)
  end

  function track.ScrollTo(off)
    local rng = range()
    off = math.min(rng, math.max(0, off))
    scroll:SetVerticalScroll(off)
    track.Update()
    if onScroll then
      onScroll(off)
    end
  end

  function track.ScrollBy(delta)
    track.ScrollTo((scroll:GetVerticalScroll() or 0) + delta)
  end

  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(_, delta)
    track.ScrollBy(-delta * 54)
  end)

  thumb:SetScript("OnMouseDown", function(self)
    local _, cy = GetCursorPosition()
    self.startY = cy / (self:GetEffectiveScale() or 1)
    self.startOff = scroll:GetVerticalScroll() or 0
    self:SetScript("OnUpdate", function(me)
      local _, y = GetCursorPosition()
      y = y / (me:GetEffectiveScale() or 1)
      local rng, view = range()
      local free = math.max(1, view - (me:GetHeight() or 20))
      track.ScrollTo(me.startOff + (me.startY - y) * rng / free)
    end)
  end)
  thumb:SetScript("OnMouseUp", function(self)
    self:SetScript("OnUpdate", nil)
  end)
  return track
end
