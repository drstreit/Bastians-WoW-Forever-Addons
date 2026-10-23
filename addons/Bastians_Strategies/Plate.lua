-- Bastian's Strategies: the plates (strategies-design.md section 6): the place from above or the steps
-- of a trade, drawn from the suite's glyphs and discs on a card in the theme's colours.
local _, ns = ...
local B = Bastians
local S = B.UI.Style
local L = ns.L

local Plate = {}
ns.Plate = Plate

local ASPECT = 1.62 -- width over height, as the pipeline scaled the dots (book.py PLATE_ASPECT)
local DOT, RIM = 8, 11 -- a spawn: a disc on a darker disc
local STEP = 7 -- px between the loop's dots
local LOOP_DOT = 3
local LEGEND_H = 18
local EDGE = 0.05 -- the flight point's arrow keeps this much of the plate free at the border

local Obj = {}
Obj.__index = Obj

function Plate.New(parent)
  local self = setmetatable({ tex = {}, fs = {}, nt = 0, nf = 0 }, Obj)
  local frame = CreateFrame("Frame", nil, parent)
  S.panel(frame, S.C.header, "radiusSmall")
  self.frame = frame
  return self
end

local function texture(self, path, size, color, alpha)
  self.nt = self.nt + 1
  local t = self.tex[self.nt]
  if not t then
    t = self.frame:CreateTexture(nil, "ARTWORK")
    self.tex[self.nt] = t
  end
  t:SetTexture(path)
  t:SetSize(size, size)
  t:SetRotation(0)
  if color then
    S.tint(t, color, alpha)
  else
    S.untint(t)
  end
  t:SetDrawLayer("ARTWORK", 0)
  t:Show()
  return t
end

local function text(self, value, size, color)
  self.nf = self.nf + 1
  local fs = self.fs[self.nf]
  if not fs then
    fs = S.text(self.frame, size, color)
    self.fs[self.nf] = fs
  end
  S.setSize(fs, size)
  S.ink(fs, color or S.C.text)
  fs:SetText(value)
  fs:SetWordWrap(false)
  fs:ClearAllPoints()
  fs:Show()
  return fs
end

local function glyph(self, kind, size, color)
  local t = texture(self, B.UI.IconTexture(kind) or B.UI.IconTexture("other"), size, nil)
  local tint = color or B.UI.IconTint(kind)
  if tint then
    S.tint(t, tint)
  end
  t:SetDrawLayer("ARTWORK", 3)
  return t
end

-- Places a texture's centre at plate coordinates (0..1 across, 0..1 down) of a w x h box.
local function at(t, frame, x, y, w, h)
  t:ClearAllPoints()
  t:SetPoint("CENTER", frame, "TOPLEFT", x * w, -y * h)
end

local function dot(self, x, y, w, h, color, alpha)
  local rim = texture(self, S.DISC, RIM, S.C.text, alpha)
  at(rim, self.frame, x, y, w, h)
  local body = texture(self, S.DISC, DOT, color, alpha)
  body:SetDrawLayer("ARTWORK", 1)
  at(body, self.frame, x, y, w, h)
end

-- The closed loop as dots every STEP px.
local function loop(self, points, w, h)
  local n = #points
  if n < 2 then
    return
  end
  for i = 1, n do
    local a, b = points[i], points[i % n + 1]
    if n == 2 and i == 2 then
      break -- two points: one line, not there and back
    end
    local dx, dy = (b[1] - a[1]) * w, (b[2] - a[2]) * h
    local len = math.sqrt(dx * dx + dy * dy)
    local steps = math.max(1, math.floor(len / STEP))
    for k = 0, steps - 1 do
      local f = k / steps
      local t = texture(self, S.DISC, LOOP_DOT, S.C.accent)
      t:SetDrawLayer("ARTWORK", 2)
      at(t, self.frame, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, w, h)
    end
  end
end

-- Where a ray from (cx, cy) (plate units) in direction `angle` (radians in pixels, 0 east, positive
-- down) leaves the box that keeps EDGE free, for a w x h px plate; returns plate units.
function Plate.Edge(cx, cy, angle, w, h)
  local px, py = cx * w, cy * h
  local dx, dy = math.cos(angle), math.sin(angle)
  local best = math.huge
  if dx > 0 then
    best = math.min(best, ((1 - EDGE) * w - px) / dx)
  elseif dx < 0 then
    best = math.min(best, (EDGE * w - px) / dx)
  end
  if dy > 0 then
    best = math.min(best, ((1 - EDGE) * h - py) / dy)
  elseif dy < 0 then
    best = math.min(best, (EDGE * h - py) / dy)
  end
  if best == math.huge then
    return cx, cy
  end
  return (px + dx * best) / w, (py + dy * best) / h
end

-- The flight points the reader can use: the player's faction, both when it is unknown.
local function flightPoints(fp, faction)
  local out = {}
  for _, f in ipairs(fp or {}) do
    if not faction or f.faction == faction then
      out[#out + 1] = f
    end
  end
  return out
end

function Obj:DrawSpot(spec, w, h, ctx)
  local frame = self.frame
  for _, p in ipairs(spec.avoid or {}) do
    dot(self, p[1], p[2], w, h, S.C.bad, 0.75)
  end
  for _, p in ipairs(spec.farm or {}) do
    dot(self, p[1], p[2], w, h, S.C.good)
  end
  loop(self, spec.loop or {}, w, h)
  if spec.start then
    local flag = glyph(self, "waypoint", 18, S.C.accent)
    flag:ClearAllPoints()
    flag:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", spec.start[1] * w - 3, -spec.start[2] * h + 2)
  end
  local mark = spec.landmark
  if mark and mark.at then
    local g = glyph(self, mark.glyph or "spot", 26, S.C.bad)
    at(g, frame, mark.at[1], mark.at[2], w, h)
    if mark.label then
      local fs = text(self, mark.label, 10, S.C.text)
      fs:SetPoint("TOP", g, "BOTTOM", 0, -1)
    end
  end
  if spec.label and spec.labelAt then
    local fs = text(self, spec.label, 10, S.C.text)
    fs:SetPoint("TOP", frame, "TOPLEFT", spec.labelAt[1] * w, -spec.labelAt[2] * h - 8)
  end
  -- the way in: the nearest flight point of the reader's faction, at the plate's edge
  local fps = flightPoints(spec.fp, ctx and ctx.faction)
  local farm = spec.farm or {}
  if #fps > 0 and #farm > 0 then
    local cx, cy = 0, 0
    for _, p in ipairs(farm) do
      cx, cy = cx + p[1], cy + p[2]
    end
    cx, cy = cx / #farm, cy / #farm
    for _, f in ipairs(fps) do
      if f.angle then
        local x, y = Plate.Edge(cx, cy, f.angle, w, h)
        local arrow = texture(self, S.ARROW, 16, S.C.accent)
        arrow:SetRotation(-f.angle) -- the arrow points east; map y runs down, the screen's up
        at(arrow, frame, x, y, w, h)
        local fs = text(self, string.format(L["%s, %d yd"], tostring(f.name), f.yards or 0), 10, S.C.dim)
        if x > 0.5 then
          fs:SetPoint("RIGHT", arrow, "LEFT", -2, 0)
        else
          fs:SetPoint("LEFT", arrow, "RIGHT", 2, 0)
        end
      end
    end
  end
  -- north is up; the scale when the build knew the map's size
  local north = text(self, "N", 10, S.C.dim)
  north:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -4)
  if spec.across then
    local fs = text(self, string.format(L["about %d yards across"], spec.across), 10, S.C.dim)
    fs:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, LEGEND_H + 2)
  end
  -- the legend under the drawing
  local g1 = glyph(self, "mob", 14, S.C.good)
  g1:ClearAllPoints()
  g1:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 6, 3)
  local t1 = text(self, L["your farm"], 10, S.C.dim)
  t1:SetPoint("LEFT", g1, "RIGHT", 3, 0)
  if #(spec.avoid or {}) > 0 then
    local g2 = glyph(self, "mob", 14, S.C.bad)
    g2:ClearAllPoints()
    g2:SetPoint("LEFT", t1, "RIGHT", 12, 0)
    local t2 = text(self, L["stay clear"], 10, S.C.dim)
    t2:SetPoint("LEFT", g2, "RIGHT", 3, 0)
  end
end

local FLOW_GLYPH = 40

function Obj:DrawFlow(spec, w, h)
  local frame = self.frame
  local nodes = spec.nodes or {}
  local n = #nodes
  if n == 0 then
    return
  end
  local cy = (h - (spec.foot and 22 or 0)) * 0.38
  local slot = w / n
  for i, node in ipairs(nodes) do
    local cx = slot * (i - 0.5)
    local back = texture(self, S.DISC, FLOW_GLYPH + 16, S.C.panel, 0.9)
    back:ClearAllPoints()
    back:SetPoint("CENTER", frame, "TOPLEFT", cx, -cy)
    local tint = node.tint and S.C[node.tint] or nil
    local g = glyph(self, node.glyph, FLOW_GLYPH, tint)
    g:ClearAllPoints()
    g:SetPoint("CENTER", frame, "TOPLEFT", cx, -cy)
    local title = text(self, node.title or "", 11, S.C.text)
    title:SetPoint("TOP", frame, "TOPLEFT", cx, -(cy + FLOW_GLYPH / 2 + 10))
    if node.note then
      local note = text(self, node.note, 10, S.C.dim)
      note:SetPoint("TOP", title, "BOTTOM", 0, -2)
    end
    if i < n then
      local arrow = glyph(self, "arrow", 22, S.C.dim)
      arrow:ClearAllPoints()
      arrow:SetPoint("CENTER", frame, "TOPLEFT", slot * i, -cy)
    end
  end
  local foot = spec.foot
  if foot then
    local g = glyph(self, foot.glyph or "never", 14, foot.tint and S.C[foot.tint] or S.C.bad)
    g:ClearAllPoints()
    g:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 6)
    local fs = text(self, foot.text or "", 10, S.C.dim)
    fs:SetPoint("LEFT", g, "RIGHT", 4, 0)
    fs:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
  end
end

-- Draws `spec` (a page's precomputed plate) `width` px wide; returns the height used.
-- ctx = { faction = "A" | "H" | nil }.
function Obj:Draw(spec, width, ctx)
  self.nt, self.nf = 0, 0
  local frame = self.frame
  local h
  if spec.kind == "flow" then
    h = 150 + (spec.foot and 20 or 0)
    frame:SetSize(width, h)
    self:DrawFlow(spec, width, h)
  else
    local drawn = math.floor(width / ASPECT)
    h = drawn + LEGEND_H
    frame:SetSize(width, h)
    self:DrawSpot(spec, width, drawn, ctx)
  end
  for i = self.nt + 1, #self.tex do
    self.tex[i]:Hide()
  end
  for i = self.nf + 1, #self.fs do
    self.fs[i]:Hide()
  end
  frame:Show()
  return h
end

function Obj:Hide()
  self.frame:Hide()
end
