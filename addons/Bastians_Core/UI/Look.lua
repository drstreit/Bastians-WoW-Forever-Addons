-- UI kit, the look engine (ADR 0046) in the one look (ADR 0084, W4 of plan-suite-waves.md): apps
-- declare widgets (S.action, S.tile, ...) and never draw them; every widget keeps its declaration
-- (`frame.spec`) and registers in S.widgets, so a theme change redraws all of them at once
-- (S.ApplyLook, from S.ApplySkin). One renderer, the book's shape language (book-look.md): words
-- in an outline, the primary as the one filled plate, round chips, the chosen one filled, tabs as
-- words with the shown one filled, quiet pictograms, the book's switch and slider. A theme gives
-- the colours (S.C), the geometry tokens the sizes (S.G); a theme never changes a shape.
-- ~~Four looks: modern, wow, parchment, glass~~ (until 20.11.2026; a saved look is mapped once to
-- a theme, Settings.lua migration 4).
local _, ns = ...
local B = ns.B
local S = ns.Style

S.widgets = setmetatable({}, { __mode = "k" }) -- [frame] = the widget kind
local LOOKS = {}
S.LOOKS = LOOKS

-- The look in force: there is one (ADR 0084 decision 1). Kept as functions, so a caller that asks
-- reads the same answer everywhere.
S.LOOK = "book"
function S.LookId()
  return S.LOOK
end

function S.LookOf()
  return S.LOOK
end

local function look()
  return LOOKS.book
end

-- Whether a frame draws on a dark theme: Bastian's Book lays its dark table there (book-look.md
-- section 3; ~~in the WoW look only, D2~~ until 20.11.2026, when the WoW look went).
function S.DarkTable(frame)
  return not S.Light(frame)
end

-- Draws one widget in the look, with the tokens where it stands (a changed spec, a theme).
function S.Draw(frame)
  local kind = S.widgets[frame]
  local draw = kind and look()[kind]
  if draw then
    draw(frame)
  end
  if kind == "action" and frame.spec.hue then
    S.DrawHue(frame)
  end
  return frame
end

-- A coloured symbol with its text ("remove them all with coloured
-- symbols with text", of the Browser's green-on-green buttons): `spec.hue`, a tile token, paints
-- the pictogram on a small square of that colour, as the kind tiles are; no plate, no edge.
-- `spec.primary` is the lit one: its word bright and a line of its colour under it.
function S.DrawHue(b)
  local spec = b.spec
  local token = S.Tok(b, spec.hue) or S.Tok(b, "accent")
  b:SetNormalTexture("")
  b:SetPushedTexture("")
  b:SetHighlightTexture("")
  S.tint(b.face, S.Tok(b, "panel"), 0)
  S.setEdges(b.edges, S.Tok(b, "line"), 0)
  if not b.hueSquare then
    b.hueSquare = S.fill(b, token, "BORDER")
    b.hueLine = S.fill(b, token, "OVERLAY")
  end
  local shown = spec.icon ~= nil and b.icon:IsShown()
  local size = (b.icon:GetWidth() or 0) + 6
  b.hueSquare:ClearAllPoints()
  b.hueSquare:SetPoint("CENTER", b.icon, "CENTER", 0, 0)
  b.hueSquare:SetSize(size, size)
  S.tint(b.hueSquare, token, 1)
  b.hueSquare:SetShown(shown)
  S.untint(b.icon) -- the white pictogram on its colour, as on a kind tile
  S.ink(b.label, S.Tok(b, spec.primary and "bright" or "text"))
  b.hueLine:ClearAllPoints()
  b.hueLine:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 2, 0)
  b.hueLine:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 0)
  b.hueLine:SetHeight(2)
  S.tint(b.hueLine, token, 1)
  b.hueLine:SetShown(spec.primary == true)
end

-- Every live widget again: a theme change. The radii first, so the shapes the widgets own lay out
-- with the theme's corners.
function S.ApplyLook()
  S.applyShape()
  for shape in pairs(S.shapes or {}) do
    shape:Layout()
  end
  for frame in pairs(S.widgets) do
    S.Draw(frame)
  end
end

-- The one look's numbers (book-look.md section 4: a tool's side padding 10; a quiet word's 7, a
-- pictogram alone 5).
S.PAD_TOOL, S.PAD_QUIET, S.PAD_ONLY = 10, 7, 5

local function textWidth(fs, text)
  local w = fs:GetStringWidth() or 0
  if w == 0 and text ~= "" then
    w = #text * 6 -- before the first frame the client has not measured the text
  end
  return w
end

-- ---------------------------------------------------------------------------------------------
-- The action button: a pictogram and its text ("always an optical clue plus
-- text"). spec = { icon, label, tip, primary, on, boxed, only, toggle, row, onClick, badge }:
-- `only` draws the pictogram alone ("More", a window's head with `headIcons`), `row` the smaller
-- button inside a row, `boxed` a face and edges in Modern (a quiet button has none), `toggle` a
-- switch whose pictogram is lit while `on` and dim while off (the window's lock, plan-chat-v3.md
-- V27). It sizes itself (Fit). A head's part (ADR 0084, Window.HEADS) names its own numbers:
-- `height`, `glyph` (the pictogram's size), `size` (the text's), `pad` (beside the words), `role`
-- (the text's face) and `caps` (small capitals, S.SmallCaps). `menu`: a small arrow after the
-- words (a select as a tool, W9).
-- ---------------------------------------------------------------------------------------------

function S.action(parent, spec)
  spec = spec or {}
  local b = CreateFrame("Button", nil, parent)
  b.spec = spec
  b.face = S.roundFill(b, S.C.panel, "radiusSmall")
  b.edges = S.roundEdges(b, S.C.line, "radiusSmall")
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.label = S.text(b, 12, S.C.text)
  b.label:SetJustifyH("LEFT")
  b.label:SetWordWrap(false) -- one line; a fixed width cuts it (layoutAction)
  if spec.role then
    S.SetRole(b.label, spec.role)
  end
  if spec.size then
    S.setSize(b.label, spec.size)
  end
  b.tip = spec.tip or (spec.only and spec.label) or nil
  b.tipNow = spec.only and true or nil -- a pictogram alone: its name at once (S.TipEnter)
  b:SetScript("OnEnter", function(self)
    local hover = look(self).hover
    if hover and self.enabledFlat ~= false then
      hover(self, true)
    end
    S.TipEnter(self)
  end)
  b:SetScript("OnLeave", function(self)
    local hover = look(self).hover
    if hover then
      hover(self, false)
    end
    S.TipLeave(self)
  end)
  if spec.onClick then
    b:SetScript("OnClick", function(self, button)
      spec.onClick(self, button)
    end)
  end
  function b.Fit(self)
    return S.Draw(self)
  end
  function b.SetLabel(self, text)
    self.spec.label = text
    S.Draw(self)
  end
  function b.SetOn(self, on)
    self.spec.on = on and true or nil
    S.Draw(self)
  end
  function b.SetEnabledFlat(self, on)
    self.enabledFlat = on and true or false
    self:SetAlpha(on and 1 or 0.4)
  end
  -- a count at the top right corner (unread whispers, junk lines); 0 hides it
  function b.SetBadge(self, n)
    n = tonumber(n) or 0
    if not self.badge then
      self.badge = CreateFrame("Frame", nil, self)
      self.badge:SetSize(16, 13)
      self.badge:SetPoint("TOPRIGHT", 4, 4)
      self.badge:SetFrameLevel((self:GetFrameLevel() or 1) + 2)
      self.badge.bg = S.roundFill(self.badge, S.C.accent, "radiusSmall")
      self.badge.text = S.SetRole(S.text(self.badge, 10, S.C.bg), "number")
      self.badge.text:SetPoint("CENTER")
    end
    self.badge:SetShown(n > 0)
    self.badge.text:SetText(n > 99 and "99+" or tostring(n))
    self.spec.badge = n
  end
  S.widgets[b] = "action"
  S.buttons[b] = true -- the skin loop of ApplySkin knows it too (tests list the buttons there)
  S.Draw(b)
  return b
end

-- The pictogram's ink: the ground's on a primary's plate, dim for a switch that is off, else
-- `lit` (the accent; WoW's gold).
local function iconInk(b, lit)
  local spec = b.spec
  if spec.primary then
    return S.Tok(b, "bg")
  elseif spec.toggle and not spec.on then
    return S.Tok(b, "dim")
  end
  return lit or S.Tok(b, "accent")
end

S.MENU_ARROW, S.MENU_GAP = 8, 7 -- a select's arrow and the room before it (the suite's board)

-- The shared layout of an action: the icon left, the text after it, the size from both.
local function layoutAction(b, h, icon, gap, pad)
  local spec = b.spec
  local iconW = icon and (spec.glyph or (h - 8)) or 0
  b.icon:ClearAllPoints()
  b.icon:SetSize(math.max(iconW, 1), math.max(iconW, 1))
  b.icon:SetPoint("LEFT", pad, 0)
  if icon then
    b.icon:SetTexture(icon)
    b.icon:Show()
  else
    b.icon:SetTexture(nil)
    b.icon:Hide()
  end
  local text = spec.only and "" or (spec.label or "")
  if spec.caps then
    text = S.SmallCaps(text)
  end
  local lead = pad + iconW + (icon and text ~= "" and gap or 0)
  b.label:SetText(text)
  b.label:ClearAllPoints()
  if spec.width and not icon and not spec.menu then
    b.label:SetPoint("CENTER") -- a fixed width without a pictogram: the word in the middle
  else
    b.label:SetPoint("LEFT", lead, 0)
  end
  local textW = textWidth(b.label, text)
  local w = lead + textW + pad
  -- a select is a tool with a small arrow after its words (ADR 0084 decision 2; `spec.menu`)
  if spec.menu then
    if not b.arrow then
      b.arrow = b:CreateTexture(nil, "ARTWORK")
      b.arrow:SetTexture(S.ARROW)
      b.arrow:SetSize(S.MENU_ARROW, S.MENU_ARROW)
      b.arrow:SetRotation(-math.pi / 2) -- the arrow points east; a select's points down
    end
    b.arrow:ClearAllPoints()
    if spec.width then
      b.arrow:SetPoint("RIGHT", -pad, 0) -- a select of a fixed width: the arrow at its end
    else
      b.arrow:SetPoint("LEFT", lead + textW + S.MENU_GAP, 0)
    end
    S.tint(b.arrow, S.Tok(b, "dim"), 1)
    b.arrow:Show()
    w = w + S.MENU_GAP + S.MENU_ARROW
  elseif b.arrow then
    b.arrow:Hide()
  end
  -- a fixed width never draws its label past the edge (, screens 5 and
  -- 8: the settings' choices ran out of their buttons): the label is cut to the room (the client
  -- ends it with "...") and the whole label is the tooltip, unless the button has a tip of its own
  if b.tipFromCut ~= nil and b.tip == b.tipFromCut then
    b.tip = nil -- the cut's own tip; one the app set since stays
  end
  b.tipFromCut, b.cutTip = nil, nil
  b.label:SetWidth(0) -- as wide as its text
  if spec.width then
    w = spec.width -- a column of equal buttons (the hub's rows): the app's choice
    local room = math.max(1, w - lead - pad - (spec.menu and (S.MENU_GAP + S.MENU_ARROW) or 0))
    if textW > room then
      b.label:SetWidth(room)
      b.cutTip = text
      if not b.tip then
        b.tip, b.tipFromCut = text, text
      end
    end
  end
  b:SetSize(math.max(w, h), h)
end

-- ---------------------------------------------------------------------------------------------
-- The kind tile: a coloured square with the kind's glyph (the suite's tiles, on every row and
-- pill). spec = { kind, big }; SetKind changes it.
-- ---------------------------------------------------------------------------------------------

function S.tile(parent, kind, big)
  local t = CreateFrame("Frame", nil, parent)
  t.spec = { kind = kind, big = big or nil }
  t.face = S.roundFill(t, S.C.tileGrey, "tile") -- the kind tiles' radius (a look may square it)
  t.edges = S.roundEdges(t, S.C.line, "tile")
  t.glyph = t:CreateTexture(nil, "ARTWORK")
  t.glyph:SetPoint("CENTER")
  function t.SetKind(self, k)
    self.spec.kind = k
    S.Draw(self)
  end
  S.widgets[t] = "tile"
  S.Draw(t)
  return t
end

local function layoutTile(t, size, edgeColor, edgeAlpha)
  local kind = t.spec.kind
  t:SetSize(size, size)
  S.tint(t.face, S.Tok(t, B.UI.TileGroup(kind)), 1)
  S.setEdges(t.edges, edgeColor, edgeAlpha)
  local glyph = kind and B.UI.GLYPH_PATHS[kind == "mob" and B.UI.MobKind() or kind]
  if glyph then
    t.glyph:SetTexture(glyph)
    S.untint(t.glyph)
    t.glyph:Show()
  else
    t.glyph:Hide()
  end
  t.glyph:SetSize(math.floor(size * 0.72), math.floor(size * 0.72))
end

-- ---------------------------------------------------------------------------------------------
-- The stat tile (ADR 0058): a small label, a large figure and a note under it; a figure nobody
-- knows reads the host's word for unknown in dim ink. spec = { label, value, note, unknown,
-- onClick, tip }; SetStat replaces it. The look draws the plate and the edges.
-- ---------------------------------------------------------------------------------------------

S.STAT_H = 56
S.STAT_FIGURE = 17 -- the figure's size

function S.stat(parent, spec)
  spec = spec or {}
  local f = CreateFrame("Button", nil, parent)
  f.spec = spec
  f.face = S.roundFill(f, S.C.card, "radiusSmall")
  f.edges = S.roundEdges(f, S.C.line, "radiusSmall")
  f.label = S.text(f, 10, S.C.dim)
  f.label:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -6)
  f.label:SetPoint("RIGHT", f, "RIGHT", -6, 0)
  f.label:SetWordWrap(false)
  -- the figure in the reader's text font (ADR 0084 decision 7: numbers stay the text font):
  -- the heading face's old-style digits read "17" as "I7" (the windows probe, 23.11.2026)
  f.value = S.SetRole(S.text(f, S.STAT_FIGURE, S.C.text), "number")
  f.value:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -19)
  f.value:SetPoint("RIGHT", f, "RIGHT", -6, 0)
  f.value:SetWordWrap(false)
  f.note = S.text(f, 10, S.C.dim)
  f.note:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 5)
  f.note:SetPoint("RIGHT", f, "RIGHT", -6, 0)
  f.note:SetWordWrap(false)
  f:SetHeight(S.STAT_H)
  f:SetScript("OnClick", function(self, button)
    if self.spec.onClick then
      self.spec.onClick(self, button)
    end
  end)
  f:SetScript("OnEnter", S.TipEnter)
  f:SetScript("OnLeave", S.TipLeave)
  function f.SetStat(self, s)
    self.spec = s or {}
    S.Draw(self)
  end
  S.widgets[f] = "stat"
  S.Draw(f)
  return f
end

local function layoutStat(f, face, edge, edgeAlpha)
  local spec = f.spec
  S.tint(f.face, face, 1)
  S.setEdges(f.edges, edge, edgeAlpha)
  f.label:SetText(spec.label or "")
  S.ink(f.label, S.Tok(f, "dim"))
  if spec.value == nil then
    f.value:SetText(spec.unknown or "?")
    S.ink(f.value, S.Tok(f, "dim"))
  else
    f.value:SetText(tostring(spec.value))
    S.ink(f.value, S.Tok(f, "text"))
  end
  f.note:SetText(spec.note or "")
  S.ink(f.note, S.Tok(f, "dim"))
  f.tip = spec.tip
  f:EnableMouse(spec.onClick ~= nil or spec.tip ~= nil)
end

-- ---------------------------------------------------------------------------------------------
-- The one look (ADR 0084 decision 2): the action is the book's tool. `primary` the filled plate in
-- the accent with the ground's ink (at most one per window); `boxed` the words in an outline of
-- the line token, the accent's edge under the mouse and while `on`; a quiet one the pictogram and
-- the word alone, a faint plate under the mouse; `only` a quiet pictogram in the muted ink,
-- brighter under the mouse. The tiles and the stat keep their plate and a thin edge.
-- ---------------------------------------------------------------------------------------------

LOOKS.book = {
  action = function(b)
    local spec, G = b.spec, S.G
    local h = spec.height or (spec.row and G.actionRow or G.action)
    b:SetNormalTexture("")
    b:SetPushedTexture("")
    b:SetHighlightTexture("")
    b.face:Show()
    b.edges:Show()
    S.tint(b.face, S.Tok(b, spec.primary and "accent" or "panel"), spec.primary and 1 or 0)
    local outline = spec.boxed and not spec.primary
    if spec.primary then
      -- the filled plate while `on` (the book's Atlas while it shows): an edge in the text's ink
      S.setEdges(b.edges, S.Tok(b, "text"), spec.on and 1 or 0)
    else
      S.setEdges(b.edges, S.Tok(b, spec.on and "accent" or "line"), outline and 1 or 0)
    end
    local ink = spec.primary and "bg" or (spec.on and "accent" or "text")
    S.ink(b.label, S.Tok(b, ink))
    S.tint(b.icon, iconInk(b, spec.only and not spec.on and S.Tok(b, "muted") or nil), 1)
    local pad = spec.only and S.PAD_ONLY
      or spec.pad
      or ((spec.boxed or spec.primary) and S.PAD_TOOL or S.PAD_QUIET)
    layoutAction(b, h, spec.icon and B.UI.Pictogram(spec.icon) or nil, G.gap, pad)
  end,
  hover = function(b, over)
    local spec = b.spec
    if spec.primary then
      return
    end
    if spec.boxed then
      S.setEdges(b.edges, S.Tok(b, (over or spec.on) and "accent" or "line"), 1)
    else
      S.tint(b.face, S.Tok(b, "faceHover"), over and 1 or 0)
    end
    if spec.only and not spec.on then
      S.tint(b.icon, over and S.Tok(b, "text") or iconInk(b, S.Tok(b, "muted")), 1)
    end
  end,
  tile = function(t)
    layoutTile(t, t.spec.big and S.G.tileBig or S.G.tile, S.Tok(t, "line"), 0.6)
  end,
  stat = function(f)
    layoutStat(f, S.Tok(f, "card"), S.Tok(f, "line"), 0.6)
  end,
}

-- ---------------------------------------------------------------------------------------------
-- The pill: a filter's choice or a view's chip, its kind tile, the label and a count; `on` the
-- chosen one, `gold` a choice of value, `menu` a dropdown's arrow after the label, `clear` a small
-- x after it (a button of its own: onClear, its tip clearTip, so a click on it never reaches the
-- pill's own click). spec = { kind, label, count, on, gold, menu, clear, clearTip, onClick, onClear }
-- A pill is round at both ends in every look (core.md "Round corners"; ~~the theme's corner
-- radius~~ until 17.11.2026, when the owner held the book against its concept board: "the buttons
-- are rounder"). `small` at its making: a chip, S.G.chip high with the small text (the book's
-- filter, book-look.md section 5); a pill keeps the size it was made with.
-- ---------------------------------------------------------------------------------------------

function S.pill(parent, spec)
  spec = spec or {}
  local p = CreateFrame("Button", nil, parent)
  p.spec = spec
  p.small = spec.small and true or nil
  p.face = S.roundFill(p, S.C.panel, "pill")
  p.edges = S.roundEdges(p, S.C.line, "pill")
  p.tile = S.tile(p, spec.kind)
  p.tile:SetPoint("LEFT", 4, 0)
  p.label = S.text(p, p.small and 11 or 12, S.C.text)
  p.label:SetJustifyH("LEFT")
  p.label:SetWordWrap(false)
  p.count = S.SetRole(S.text(p, 11, S.C.dim), "number") -- a count in the numbers' face (V17)
  p.arrow = p:CreateTexture(nil, "ARTWORK")
  p.arrow:SetTexture(S.ARROW)
  p.arrow:SetSize(9, 9)
  p.arrow:SetRotation(-math.pi / 2) -- the arrow points east; a dropdown's points down
  p.clear = CreateFrame("Button", nil, p)
  p.clear:SetSize(16, 16)
  p.clear.label = S.text(p.clear, 12, S.C.dim)
  p.clear.label:SetPoint("CENTER")
  p.clear.label:SetText("x") -- ASCII, the game fonts lack the symbols (CLAUDE.md section 12)
  p.clear.tip = function(self)
    return self:GetParent().spec.clearTip
  end
  p.clear:SetScript("OnEnter", function(self)
    S.ink(self.label, S.Tok(self, "text"))
    S.TipEnter(self)
  end)
  p.clear:SetScript("OnLeave", function(self)
    S.ink(self.label, S.Tok(self, "dim"))
    S.TipLeave(self)
  end)
  p.clear:SetScript("OnClick", function(self)
    local pill = self:GetParent()
    if pill.spec.onClear then
      pill.spec.onClear(pill)
    end
  end)
  p.tip = spec.tip
  p:SetScript("OnEnter", function(self)
    local hover = look(self).pillHover
    if hover then
      hover(self, true)
    end
    S.TipEnter(self)
  end)
  p:SetScript("OnLeave", function(self)
    local hover = look(self).pillHover
    if hover then
      hover(self, false)
    end
    S.TipLeave(self)
  end)
  p:SetScript("OnClick", function(self, button)
    if self.spec.onClick then
      self.spec.onClick(self, button)
    end
  end)
  function p.SetOn(self, on)
    self.spec.on = on and true or nil
    S.Draw(self)
  end
  function p.SetCount(self, n)
    self.spec.count = n
    S.Draw(self)
  end
  function p.SetLabel(self, text)
    self.spec.label = text
    S.Draw(self)
  end
  S.widgets[p] = "pill"
  S.Draw(p)
  return p
end

-- A pill's height: the look's, a chip's for one made small.
local function pillHeight(p)
  return p.small and (S.G.chip or 22) or S.G.pill
end

local PILL_PAD, CHIP_PAD = 10, 9 -- beside the words

-- `countTok` the count's ink (dim; the ground's on a chosen pill's fill).
local function layoutPill(p, h, inkTok, edgeTok, edgeAlpha, countTok)
  local spec = p.spec
  local pad = p.small and CHIP_PAD or PILL_PAD
  p.tile:SetKind(spec.kind)
  p.tile:SetShown(spec.kind ~= nil)
  local x = spec.kind and (4 + S.G.tile + S.G.gap) or pad
  p.label:SetText(spec.label or "")
  p.label:ClearAllPoints()
  p.label:SetPoint("LEFT", x, 0)
  S.ink(p.label, S.Tok(p, inkTok))
  local w = x + textWidth(p.label, spec.label or "")
  if spec.count ~= nil then
    p.count:SetText(tostring(spec.count))
    p.count:ClearAllPoints()
    local gap = p.small and 4 or 5
    p.count:SetPoint("LEFT", w + gap, 0)
    S.ink(p.count, S.Tok(p, countTok or "dim"))
    p.count:Show()
    w = w + gap + textWidth(p.count, tostring(spec.count))
  else
    p.count:Hide()
  end
  if spec.menu then
    p.arrow:ClearAllPoints()
    p.arrow:SetPoint("LEFT", w + 4, 0)
    S.tint(p.arrow, S.Tok(p, "dim"), 1)
    p.arrow:Show()
    w = w + 4 + 9
  else
    p.arrow:Hide()
  end
  if spec.clear then
    p.clear:ClearAllPoints()
    p.clear:SetPoint("LEFT", w + 2, 0)
    S.ink(p.clear.label, S.Tok(p, "dim"))
    p.clear:Show()
    w = w + 2 + 16
  else
    p.clear:Hide()
  end
  S.setEdges(p.edges, type(edgeTok) == "table" and edgeTok or S.Tok(p, edgeTok), edgeAlpha)
  p:SetSize(w + (spec.clear and 4 or pad), h)
  -- round at both ends: the radius is half the height, known only now
  if p.face.r ~= math.floor(h / 2) then
    p.face:Layout()
    p.edges:Layout()
  end
  S.dashEdges(p)
end

-- A dashed outline (`spec.dashed`; the book's chip "unconfirmed", the board's dashed outline,
-- book-look.md section 11; W4): the round ends stay, the straight top and bottom become dashes of
-- DASH with DASH_GAP between, in the edge's colour. A pooled pill without it gets its lines back.
S.DASH, S.DASH_GAP = 4, 3
function S.dashEdges(p)
  local dashed = p.spec.dashed == true
  local e = p.edges
  e:Piece(5):SetShown(not dashed)
  e:Piece(6):SetShown(not dashed)
  p.dashes = p.dashes or {}
  local n = 0
  if dashed then
    local paint = S.painted[e] or { S.Tok(p, "line") }
    local w, h = p:GetWidth() or 0, p:GetHeight() or 0
    local r = e.r or math.floor(h / 2)
    local count = math.max(0, math.floor((w - 2 * r + S.DASH_GAP) / (S.DASH + S.DASH_GAP)))
    for _, side in ipairs({ "TOPLEFT", "BOTTOMLEFT" }) do
      for i = 1, count do
        n = n + 1
        local d = p.dashes[n]
        if not d then
          d = p:CreateTexture(nil, "BORDER")
          d:SetTexture(S.WHITE)
          p.dashes[n] = d
        end
        d:ClearAllPoints()
        d:SetSize(S.DASH, 1)
        d:SetPoint(side, p, side, r + (i - 1) * (S.DASH + S.DASH_GAP), 0)
        S.tint(d, paint[1], paint[2])
        d:Show()
      end
    end
  end
  for i = n + 1, #p.dashes do
    p.dashes[i]:Hide()
  end
end

-- The chosen pill is filled, its words in the ground's ink ("selected
-- filter need to be dramatically different from unselected"), as the segmented switch's chosen
-- part; ~~the chosen one in the accent's ink inside an accent edge~~ (until 16.11.2026).
local function chosenPill(p, fill)
  S.tint(p.face, fill, 1)
  layoutPill(p, pillHeight(p), "bg", fill, 1, "bg")
end

-- An unchosen pill is quiet: no plate, its
-- edge the line token at the token's own faint opacity (a choice of value: gold at QUIET_GOLD), so
-- the chosen one is the only filled thing in a row; the plate comes back under the mouse.
-- ~~A plate and the edge at full strength~~ (until 16.11.2026).
S.QUIET_GOLD = 0.6

local function quietPill(p, inkTok)
  local spec = p.spec
  S.tint(p.face, S.Tok(p, "panel"), 0)
  if spec.gold then
    layoutPill(p, pillHeight(p), inkTok or "gold", "gold", S.QUIET_GOLD)
  else
    layoutPill(p, pillHeight(p), "text", "line", nil)
  end
end

-- A chip: quiet, the chosen one filled in the accent (book-look.md section 5).
LOOKS.book.pill = function(p)
  if p.spec.on then
    return chosenPill(p, S.Tok(p, "accent"))
  end
  quietPill(p)
end

-- A chosen pill keeps its fill under the mouse; a quiet one shows its plate while the mouse is on it.
LOOKS.book.pillHover = function(p, over)
  if not p.spec.on then
    S.tint(p.face, S.Tok(p, over and "faceHover" or "panel"), over and 1 or 0)
  end
end

-- ---------------------------------------------------------------------------------------------
-- The tab: a kind tile, the label, a count, a badge; `on` the shown one, `unread` lit. `line`, a
-- colour token, makes it a flat tab (the chat artifact's world tabs, plan-chat-v3.md V27): no
-- plate, no frame, the label in capitals where the look's sections are, the shown one in the
-- text's ink over a line of that colour. spec = { kind, label, count, badge, on, unread, line,
-- onClick, onDrag... (the app's own scripts stay) }
-- ---------------------------------------------------------------------------------------------

function S.tab(parent, spec)
  spec = spec or {}
  local t = CreateFrame("Button", nil, parent)
  t.spec = spec
  t.face = S.roundFill(t, S.C.panel, "radiusSmall", nil, "top")
  t.edges = S.roundEdges(t, S.C.accent, "radiusSmall", "top") -- the chosen tab's frame (01.11.2026)
  t.under = S.fill(t, S.C.accent, "ARTWORK")
  t.under:ClearAllPoints()
  t.under:SetPoint("BOTTOMLEFT", 0, 0)
  t.under:SetPoint("BOTTOMRIGHT", 0, 0)
  t.under:SetHeight(2)
  t.tile = S.tile(t, spec.kind)
  t.tile:SetPoint("LEFT", 6, 0)
  t.label = S.SetRole(S.text(t, 12, S.C.dim), "label") -- the labels' face (V17)
  t.label:SetJustifyH("LEFT")
  t.count = S.SetRole(S.text(t, 11, S.C.dim), "number") -- a count in the numbers' face (V27)
  t.count:Hide()
  t.tip = spec.tip
  t:SetScript("OnEnter", S.TipEnter)
  t:SetScript("OnLeave", S.TipLeave)
  if spec.onClick then
    t:SetScript("OnClick", function(self, button)
      self.spec.onClick(self, button)
    end)
  end
  function t.SetOn(self, on)
    self.spec.on = on and true or nil
    S.Draw(self)
  end
  function t.SetUnread(self, on)
    self.spec.unread = on and true or nil
    S.Draw(self)
  end
  function t.SetLabel(self, text)
    self.spec.label = text
    S.Draw(self)
  end
  function t.SetCount(self, n)
    self.spec.count = n
    S.Draw(self)
  end
  function t.SetBadge(self, n)
    n = tonumber(n) or 0
    if not self.badge then
      self.badge = CreateFrame("Frame", nil, self)
      self.badge:SetSize(16, 13)
      self.badge.bg = S.roundFill(self.badge, S.C.accent, "radiusSmall")
      self.badge.text = S.SetRole(S.text(self.badge, 10, S.C.bg), "number")
      self.badge.text:SetPoint("CENTER")
    end
    self.badge:SetShown(n > 0)
    self.badge.text:SetText(n > 99 and "99+" or tostring(n))
    self.spec.badge = n
    S.Draw(self)
  end
  S.widgets[t] = "tab"
  S.Draw(t)
  return t
end

local function layoutTab(t, h, inkTok, faceAlpha, upper)
  local spec = t.spec
  t.tile:SetKind(spec.kind)
  t.tile:SetShown(spec.kind ~= nil)
  local x = spec.kind and (6 + S.G.tile + S.G.gap) or 10
  local label = spec.label or ""
  if upper then
    label = S.LabelCaps(t.label, label)
  end
  t.label:SetText(label)
  t.label:ClearAllPoints()
  t.label:SetPoint("LEFT", x, 0)
  S.ink(t.label, S.Tok(t, inkTok))
  local w = x + textWidth(t.label, label)
  if spec.count ~= nil then
    local n = tostring(spec.count)
    t.count:SetText(n)
    t.count:ClearAllPoints()
    t.count:SetPoint("LEFT", w + 5, 0)
    S.ink(t.count, S.Tok(t, "dim"))
    t.count:Show()
    w = w + 5 + textWidth(t.count, n)
  else
    t.count:Hide()
  end
  if t.badge and (spec.badge or 0) > 0 then
    t.badge:ClearAllPoints()
    t.badge:SetPoint("LEFT", w + 5, 0)
    w = w + 5 + 16
  end
  S.tint(t.face, S.Tok(t, "panel"), faceAlpha)
  t:SetSize(w + 10, h)
end

-- The flat tab (`spec.line`): no plate, no frame; the shown one in `onInk` over a 2 px line of
-- the spec's colour, the others dim; capitals where the look's sections have them (`upper`).
local function flatTab(t, onInk, upper)
  local spec = t.spec
  layoutTab(t, S.G.tab, (spec.on or spec.unread) and onInk or "dim", 0, upper)
  t.under:SetShown(spec.on == true)
  S.tint(t.under, S.Tok(t, spec.line) or S.Tok(t, "accent"), 1)
  S.setEdges(t.edges, S.Tok(t, "accent"), 0)
end

-- A tab is a word (book-look.md section 4): no plate, the shown one filled in the accent with the
-- ground's ink and its top corners round; the others in the dim ink, an unread one in the accent.
-- ~~The chosen tab in the accent inside an accent frame~~ (until 20.11.2026, the Modern look).
LOOKS.book.tab = function(t)
  local spec = t.spec
  if spec.line then
    return flatTab(t, "text", true)
  end
  local ink = spec.on and "bg" or (spec.unread and "accent" or "dim")
  layoutTab(t, S.G.tab, ink, 0)
  S.tint(t.face, S.Tok(t, "accent"), spec.on and 1 or 0)
  S.tint(t.under, S.Tok(t, "accent"), 1) -- hidden, but in its window's colours (a flat tab shows it)
  t.under:Hide()
  S.setEdges(t.edges, S.Tok(t, "accent"), 0)
  if t.count:IsShown() then
    S.ink(t.count, S.Tok(t, spec.on and "bg" or "dim"))
  end
end

-- ---------------------------------------------------------------------------------------------
-- The section title: a small pictogram and the title; Modern small capitals in dim, WoW the
-- heading face in gold over a gilt rule. spec = { icon, title }
-- ---------------------------------------------------------------------------------------------

function S.section(parent, spec)
  spec = spec or {}
  local s = CreateFrame("Frame", nil, parent)
  s.spec = spec
  s:SetHeight(18)
  s.icon = s:CreateTexture(nil, "ARTWORK")
  s.icon:SetSize(14, 14)
  s.icon:SetPoint("LEFT", 0, 0)
  s.title = S.SetRole(S.text(s, 11, S.C.dim), "label") -- the labels' face (V17)
  s.title:SetJustifyH("LEFT")
  s.rule = S.fill(s, S.C.line, "ARTWORK")
  s.rule:ClearAllPoints()
  s.rule:SetPoint("BOTTOMLEFT", 0, 0)
  s.rule:SetPoint("BOTTOMRIGHT", 0, 0)
  s.rule:SetHeight(1)
  function s.SetTitle(self, text)
    self.spec.title = text
    S.Draw(self)
  end
  S.widgets[s] = "section"
  S.Draw(s)
  return s
end

local function layoutSection(s, inkTok, upper)
  local spec = s.spec
  local icon = spec.icon and B.UI.Pictogram(spec.icon) or nil
  if icon then
    s.icon:SetTexture(icon)
    S.tint(s.icon, S.Tok(s, inkTok), 1)
    s.icon:Show()
  else
    s.icon:SetTexture(nil)
    s.icon:Hide()
  end
  local title = spec.title or ""
  s.title:SetText(upper and S.LabelCaps(s.title, title) or title)
  s.title:ClearAllPoints()
  s.title:SetPoint("LEFT", icon and 20 or 0, 0)
  S.ink(s.title, S.Tok(s, inkTok))
end

-- A section's title: small capitals in the dim ink, no rule.
LOOKS.book.section = function(s)
  layoutSection(s, "dim", true)
  s.rule:Hide()
end

-- ---------------------------------------------------------------------------------------------
-- The toggle: Modern a switch (a track with its knob), WoW the game's box with a cross.
-- spec = { on, onChange(self, on) }; the label is the row's, not the widget's.
-- ---------------------------------------------------------------------------------------------

function S.toggle(parent, spec)
  spec = spec or {}
  local t = CreateFrame("Button", nil, parent)
  t.spec = spec
  t.track = S.roundFill(t, S.C.line, "pill")
  t.edges = S.roundEdges(t, S.C.line, "radius")
  t.knob = CreateFrame("Frame", nil, t)
  t.knob.fill = S.roundFill(t.knob, S.C.bg, "pill")
  t.mark = S.text(t, 12, S.C.gold)
  t.mark:SetPoint("CENTER")
  t.mark:SetText("x")
  t:SetScript("OnClick", function(self)
    self:SetOn(not self.spec.on)
    if self.spec.onChange then
      self.spec.onChange(self, self.spec.on == true)
    end
  end)
  function t.SetOn(self, on)
    self.spec.on = on and true or nil
    S.Draw(self)
  end
  S.widgets[t] = "toggle"
  S.Draw(t)
  return t
end

-- The book's switch (book-look.md section 5, Hide done): a bar of 28 x 15 round at both ends,
-- filled in the accent while on and in the muted ink while off, its knob of 11 in the ground's
-- colour at the side it stands for. ~~Modern's 34 x 18 track, WoW's box with a cross~~ (until
-- 20.11.2026; the book's own switch moved here, W4).
S.SWITCH_W, S.SWITCH_H, S.SWITCH_KNOB = 28, 15, 11
LOOKS.book.toggle = function(t)
  local on = t.spec.on == true
  t:SetSize(S.SWITCH_W, S.SWITCH_H)
  t.track:Show()
  S.tint(t.track, S.Tok(t, on and "accent" or "muted"), 1)
  S.setEdges(t.edges, S.Tok(t, "line"), 0)
  t.knob:SetSize(S.SWITCH_KNOB, S.SWITCH_KNOB)
  t.knob:ClearAllPoints()
  t.knob:SetPoint(on and "RIGHT" or "LEFT", t, on and "RIGHT" or "LEFT", on and -2 or 2, 0)
  S.tint(t.knob.fill, S.Tok(t, "bg"), 1)
  t.knob:Show()
  t.mark:Hide()
end

-- ---------------------------------------------------------------------------------------------
-- The card (plan-chat-v3.md §3, §9; ADR 0075): the block a request, an offer or a group stands
-- on, with a stripe of its colour along the left edge and a lit edge while it is fresh. What it
-- says is its owner's: texts and buttons go into `card.body`, which the look leaves alone; the
-- owner sets the card's height. spec = { stripe (a colour token, nil for none), hot, flat (no
-- plate, no edge: a quiet card), onClick, tip }.
-- ---------------------------------------------------------------------------------------------

S.CARD_PAD = 8 -- between the card's edge and its body
S.CARD_STRIPE = 3 -- the stripe's width

function S.card(parent, spec)
  spec = spec or {}
  local c = CreateFrame("Button", nil, parent)
  c.spec = spec
  c.face = S.roundFill(c, S.C.card, "radius")
  c.edges = S.roundEdges(c, S.C.cardEdge, "radius")
  c.stripe = S.fill(c, S.C.accent, "BORDER")
  c.stripe:ClearAllPoints()
  c.stripe:SetPoint("TOPLEFT", c, "TOPLEFT", 1, -3)
  c.stripe:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 1, 3)
  c.stripe:SetWidth(S.CARD_STRIPE)
  c.body = CreateFrame("Frame", nil, c)
  c.body:SetPoint("TOPLEFT", c, "TOPLEFT", S.CARD_PAD + S.CARD_STRIPE, -S.CARD_PAD)
  c.body:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -S.CARD_PAD, S.CARD_PAD)
  c:SetScript("OnClick", function(self, button)
    if self.spec.onClick then
      self.spec.onClick(self, button)
    end
  end)
  c:SetScript("OnEnter", function(self)
    local hover = look(self).cardHover
    if hover and self.spec.onClick then
      hover(self, true)
    end
    S.TipEnter(self)
  end)
  c:SetScript("OnLeave", function(self)
    local hover = look(self).cardHover
    if hover then
      hover(self, false)
    end
    S.TipLeave(self)
  end)
  function c.SetCard(self, s)
    self.spec = s or {}
    S.Draw(self)
  end
  S.widgets[c] = "card"
  S.Draw(c)
  return c
end

-- The shared part of every look: the stripe, the tip, the mouse; the plate and the edge by the look.
local function layoutCard(c, faceTok, faceAlpha, edgeTok, edgeAlpha)
  local spec = c.spec
  local stripe = spec.stripe and S.Tok(c, spec.stripe)
  if stripe then
    S.tint(c.stripe, stripe, 1)
  end
  c.stripe:SetShown(stripe ~= nil)
  if spec.flat then
    c.face:Hide()
  else
    c.face:Show()
    S.tint(c.face, type(faceTok) == "table" and faceTok or S.Tok(c, faceTok), faceAlpha)
  end
  local edge = type(edgeTok) == "table" and edgeTok or S.Tok(c, edgeTok)
  S.setEdges(c.edges, edge, spec.flat and not spec.hot and 0 or edgeAlpha)
  c.tip = spec.tip
  c:EnableMouse(spec.onClick ~= nil or spec.tip ~= nil)
end

LOOKS.book.card = function(c)
  local hot = c.spec.hot
  layoutCard(c, "card", 1, hot and "cardHot" or "cardEdge", 1)
end

LOOKS.book.cardHover = function(c, over)
  S.tint(c.face, S.Tok(c, over and "hover" or "card"), 1)
end

-- ---------------------------------------------------------------------------------------------
-- The segmented switch (plan-chat-v3.md V27, the chat artifact's layout switch; owner, Forever
-- 13.11.2026: "the button look all the same color"): two or more choices side by side on one
-- plate, the chosen one filled, so the switch says which is shown. spec = { items = { { id,
-- label, icon, tip } }, value (the chosen id; nil: none), onChange(self, id) }. A click on another
-- part chooses it and calls onChange; SetValue chooses without the call; Part(id) is its button.
-- An item with `disabled` is drawn dim and takes no click; its tip still shows (W9: the Browser's
-- section whose app is missing says what it needs). `spec.again`: a click on the chosen part
-- calls onChange too (the Browser's lit section leads back to its first list).
-- ---------------------------------------------------------------------------------------------

S.SEGMENT_HOVER = 0.25 -- the fill's opacity under the mouse on a part not chosen
S.SEGMENT_OFF = 0.4 -- a part that is `disabled` (S.action's SetEnabledFlat draws the same)

function S.segmented(parent, spec)
  spec = spec or {}
  spec.items = spec.items or {}
  local f = CreateFrame("Frame", nil, parent)
  f.spec = spec
  f.face = S.roundFill(f, S.C.panel, "radiusSmall")
  f.edges = S.roundEdges(f, S.C.line, "radiusSmall")
  f.parts = {}
  for i, item in ipairs(spec.items) do
    local b = CreateFrame("Button", nil, f)
    b.item = item
    -- `spec.corners` ("top"): the chosen part's fill rounds only those (a tab's)
    b.fill = S.roundFill(b, S.C.accent, "radiusSmall", "BORDER", spec.corners)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.label = S.text(b, 12, S.C.text)
    b.label:SetJustifyH("LEFT")
    b.tip = item.tip
    b:SetScript("OnEnter", function(self)
      if f.spec.value ~= self.item.id and f.fillTok and not self.item.disabled then
        S.tint(self.fill, f.fillTok, S.SEGMENT_HOVER)
        self.fill:Show()
      end
      S.TipEnter(self)
    end)
    b:SetScript("OnLeave", function(self)
      S.Draw(f)
      S.TipLeave(self)
    end)
    b:SetScript("OnClick", function(self)
      local id = self.item.id
      if self.item.disabled or (f.spec.value == id and not f.spec.again) then
        return
      end
      f:SetValue(id)
      if f.spec.onChange then
        f.spec.onChange(f, id)
      end
    end)
    f.parts[i] = b
  end
  function f.SetValue(self, id)
    self.spec.value = id
    S.Draw(self)
  end
  function f.Part(self, id)
    for _, b in ipairs(self.parts) do
      if b.item.id == id then
        return b
      end
    end
    return nil
  end
  S.widgets[f] = "segmented"
  S.Draw(f)
  return f
end

-- The shared layout: the parts side by side, each its pictogram and its word; the chosen part's
-- fill in `c.fill` with its ink `c.on`, the others' words in `c.off` and pictograms in `c.icon`.
-- c = { fill, on, off, icon } (colours: a look's own or the frame's tokens).
local function layoutSegmented(f, c)
  local G = S.G
  local h = f.spec.height or G.actionRow -- `spec.height`, `spec.pad`: a bar's taller, wider parts
  local pad = f.spec.pad or 9
  local x = 0
  f.fillTok = c.fill
  -- `spec.flat`: no plate, no edge, the chosen part alone filled (Bastian's Book's tabs, the
  -- concept board's row of words; )
  if f.spec.flat then
    f.face:Hide()
    f.edges:Hide()
  else
    f.face:Show()
    f.edges:Show()
  end
  for _, b in ipairs(f.parts) do
    local item = b.item
    local on = item.id ~= nil and item.id == f.spec.value
    local icon = item.icon and B.UI.Pictogram(item.icon) or nil
    local iconW = icon and (h - 8) or 0
    b.icon:ClearAllPoints()
    b.icon:SetSize(math.max(iconW, 1), math.max(iconW, 1))
    b.icon:SetPoint("LEFT", pad, 0)
    if icon then
      b.icon:SetTexture(icon)
      S.tint(b.icon, on and c.on or c.icon, 1)
      b.icon:Show()
    else
      b.icon:SetTexture(nil)
      b.icon:Hide()
    end
    local text = item.label or ""
    local gap = (icon and text ~= "") and G.gap or 0
    b.label:SetText(text)
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT", pad + iconW + gap, 0)
    S.ink(b.label, on and c.on or c.off)
    local w = pad + iconW + gap + textWidth(b.label, text) + pad
    b:SetSize(w, h)
    b:ClearAllPoints()
    b:SetPoint("LEFT", f, "LEFT", x, 0)
    S.tint(b.fill, c.fill, 1)
    if on then
      b.fill:Show()
    else
      b.fill:Hide()
    end
    b:SetAlpha(item.disabled and S.SEGMENT_OFF or 1) -- as an action that is not enabled
    x = x + w + (f.spec.gap or 0) -- `spec.gap`: room between the parts (words in a row)
  end
  f:SetSize(math.max(x, h), h)
end

-- The segmented switch: its parts on one plate, the chosen one filled. A flat one is a row of
-- words (the book's tabs, book-look.md section 4): the parts not chosen in the quiet dim ink.
LOOKS.book.segmented = function(f)
  S.tint(f.face, S.Tok(f, "panel"), 1)
  S.setEdges(f.edges, S.Tok(f, "line"), 1)
  layoutSegmented(f, {
    fill = S.Tok(f, "accent"),
    on = S.Tok(f, "bg"),
    off = S.Tok(f, f.spec.flat and "dim" or "text"),
    icon = S.Tok(f, "accent"),
  })
end

-- ---------------------------------------------------------------------------------------------
-- The slider (plan-chat-one-window.md §8, R1, V34; , screens 1 and 2:
-- the flat track with a square knob, the artifact's slider): a title in the labels' face, the
-- track filled up to the knob in the accent, a round knob, the value at the right and a line of
-- words under it ("2 . and what is yours"). ~~The WoW look draws the game's own slider~~ (until
-- 20.11.2026). spec = { title, plain (the title as written, not in capitals), min, max, step,
-- value, words = function(v) -> the line under, number = function(v) -> the value's text (default
-- the number), onChange(self, v) }. SetValue(v, silent) moves it without the call.
-- ---------------------------------------------------------------------------------------------

S.SLIDER_KNOB = 12 -- the round knob (book-look.md section 5)
S.SLIDER_TRACK = 4 -- the track's height
S.SLIDER_TOP = 16 -- the track's row under the title

function S.slider(parent, spec)
  spec = spec or {}
  local f = CreateFrame("Frame", nil, parent)
  f.spec = spec
  f:SetHeight(spec.words and (S.SLIDER_TOP + 30) or (S.SLIDER_TOP + 18))
  f.title = S.SetRole(S.text(f, 11, S.C.muted), "label")
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  f.title:SetJustifyH("LEFT")
  f.title:SetWordWrap(false)
  f.number = S.SetRole(S.text(f, 11, S.C.dim), "number")
  f.number:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  f.number:SetJustifyH("RIGHT")
  f.title:SetPoint("RIGHT", f.number, "LEFT", -6, 0)
  local slider = CreateFrame("Slider", nil, f)
  slider:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -S.SLIDER_TOP)
  slider:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -S.SLIDER_TOP)
  slider:SetHeight(14)
  slider:SetOrientation("HORIZONTAL")
  slider:SetMinMaxValues(spec.min or 0, spec.max or 1)
  slider:SetValueStep(spec.step or 1)
  slider:SetObeyStepOnDrag(true)
  f.slider = slider
  -- the track and its filled part, under the knob
  f.rail = CreateFrame("Frame", nil, slider)
  f.rail:SetPoint("LEFT", slider, "LEFT", 0, 0)
  f.rail:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
  f.rail:SetHeight(S.SLIDER_TRACK)
  f.track = S.roundFill(f.rail, S.C.track, "pill")
  f.filled = CreateFrame("Frame", nil, f.rail)
  f.filled:SetPoint("TOPLEFT", f.rail, "TOPLEFT", 0, 0)
  f.filled:SetPoint("BOTTOMLEFT", f.rail, "BOTTOMLEFT", 0, 0)
  f.fill = S.roundFill(f.filled, S.C.accent, "pill", "BORDER")
  slider:SetThumbTexture(S.DISC)
  f.knob = slider:GetThumbTexture()
  f.words = S.text(f, 11, S.C.text)
  f.words:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -3)
  f.words:SetPoint("RIGHT", f, "RIGHT", 0, 0)
  f.words:SetJustifyH("LEFT")
  f.words:SetWordWrap(false)
  if spec.value then
    slider:SetValue(spec.value)
  end
  function f.SetValue(self, v, silent)
    self.silent = silent
    slider:SetValue(v)
    self.silent = nil
    S.Draw(self)
  end
  function f.GetValue()
    return slider:GetValue()
  end
  slider:SetScript("OnValueChanged", function(_, v, user)
    S.Draw(f) -- the fill, the value and its words follow the knob
    if spec.onChange and not f.silent and user ~= false then
      spec.onChange(f, v)
    end
  end)
  f:SetScript("OnSizeChanged", function()
    S.Draw(f)
  end)
  S.widgets[f] = "slider"
  S.Draw(f)
  return f
end

-- The texts and the filled part (every look); returns the value's share of the track, 0..1.
local function layoutSlider(f, titleTok, numberTok, wordsTok)
  local spec = f.spec
  local v = f.slider:GetValue() or spec.min or 0
  local lo, hi = f.slider:GetMinMaxValues()
  local frac = (hi and lo and hi > lo) and math.max(0, math.min(1, (v - lo) / (hi - lo))) or 0
  local title = spec.title or ""
  f.title:SetText(spec.plain and title or S.LabelCaps(f.title, title))
  S.ink(f.title, titleTok)
  local number
  if spec.number then
    number = spec.number(v)
  elseif (spec.step or 1) >= 1 then
    number = tostring(math.floor(v + 0.5))
  else
    number = string.format("%.2f", v)
  end
  f.number:SetText(number or "")
  S.ink(f.number, numberTok)
  f.words:SetText(spec.words and spec.words(v) or "")
  f.words:SetShown(spec.words ~= nil)
  S.ink(f.words, wordsTok)
  local w = f.rail:GetWidth()
  if not w or w <= 0 then
    w = f:GetWidth() or 0
  end
  f.filled:SetWidth(math.max(1, math.floor(w * frac + 0.5)))
  return frac
end

-- a thin track, filled up to a round knob
local function flatSlider(f, trackTok, fillTok, knobTok)
  f.rail:Show()
  S.tint(f.track, trackTok, 1)
  S.tint(f.fill, fillTok, 1)
  f.knob:SetTexture(S.DISC)
  f.knob:SetTexCoord(0, 1, 0, 1)
  f.knob:SetSize(S.SLIDER_KNOB, S.SLIDER_KNOB)
  S.tint(f.knob, knobTok, 1)
end

-- The book's slider (book-look.md section 5): a track of 4 in the line's colour, filled in the
-- accent up to a round knob of 12 in the accent.
LOOKS.book.slider = function(f)
  flatSlider(f, S.Tok(f, "line"), S.Tok(f, "accent"), S.Tok(f, "accent"))
  layoutSlider(f, S.Tok(f, "muted"), S.Tok(f, "dim"), S.Tok(f, "text"))
end

-- ---------------------------------------------------------------------------------------------
-- The look's paper (ADR 0084 decisions 2 and 8, ADR 0082 decision 5; W4, 20.11.2026): what is
-- read lies on paper as an object with a soft shadow; a picture's foot is torn; a picture's words
-- fade into the dark. The textures are the look's (tools/make_media.py), drawn by the kit; until
-- 20.11.2026 the book drew them from Core's folder itself (a crossing of ADR 0082). Each path
-- whole, so the texture check finds its file.
-- ---------------------------------------------------------------------------------------------

S.SHADOW = "Interface\\AddOns\\Bastians_Core\\Media\\FolioShadow"
S.DECKLE = "Interface\\AddOns\\Bastians_Core\\Media\\Deckle"
S.FADE = "Interface\\AddOns\\Bastians_Core\\Media\\Fade"
S.SHADOW_SPREAD = 12 -- how far the shadow reaches beyond the paper
S.SHADOW_DROP = 4 -- how much lower it falls than the paper
S.DECKLE_H = 12 -- the torn edge's height

-- The soft shadow under `frame`: eight pieces of the soft square around it (its quarters the
-- corners, its middle row and column the sides), in the `folioShadow` token. -> the pieces, also
-- kept as frame.shadow.
function S.shadow(frame, spread, drop)
  local pieces = frame.shadow
  if not pieces then
    local function piece(l, r, top, bottom)
      local tex = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
      tex:SetTexture(S.SHADOW)
      tex:SetTexCoord(l, r, top, bottom)
      S.tint(tex, S.C.folioShadow)
      return tex
    end
    local tl, tr = piece(0, 0.5, 0, 0.5), piece(0.5, 1, 0, 0.5)
    local bl, br = piece(0, 0.5, 0.5, 1), piece(0.5, 1, 0.5, 1)
    local top, bottom = piece(0.49, 0.51, 0, 0.5), piece(0.49, 0.51, 0.5, 1)
    local left, right = piece(0, 0.5, 0.49, 0.51), piece(0.5, 1, 0.49, 0.51)
    top:SetPoint("TOPLEFT", tl, "TOPRIGHT")
    top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
    bottom:SetPoint("TOPLEFT", bl, "TOPRIGHT")
    bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
    left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT")
    left:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
    right:SetPoint("TOPLEFT", tr, "BOTTOMLEFT")
    right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
    pieces = { tl, tr, bl, br, top, bottom, left, right }
    frame.shadow = pieces
  end
  -- the corners carry the spread and the drop; a second call lays the same shadow out again
  -- (a tile under the mouse casts a longer one, book-look.md 10.3)
  local s, d = spread or S.SHADOW_SPREAD, drop or S.SHADOW_DROP
  local tl, tr, bl, br = pieces[1], pieces[2], pieces[3], pieces[4]
  for _, corner in ipairs({ tl, tr, bl, br }) do
    corner:SetSize(2 * s, 2 * s)
    corner:ClearAllPoints()
  end
  tl:SetPoint("TOPLEFT", frame, "TOPLEFT", -s, s - d)
  tr:SetPoint("TOPRIGHT", frame, "TOPRIGHT", s, s - d)
  bl:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -s, -s - d)
  br:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", s, -s - d)
  frame.shadowSpread, frame.shadowDrop = s, d
  return pieces
end

-- ---------------------------------------------------------------------------------------------
-- A tile as an object (ADR 0084 decision 2; book-look.md 10.3; the
-- hover should be seen "without looking for it"): it lies on the table with a shadow, a light
-- line at its top and a dark one at its foot; under the mouse it rises 2, its shadow grows and
-- its edge is lit 2 wide in the book's gold; pressed it sinks 1. No tween: the game moves the
-- anchor in the frame the mouse arrives.
-- S.object(frame, { radius = 5, edge = "folioGold" }) makes `frame` (a Button, or a frame with
-- the mouse) one; call it after the frame's own OnEnter, OnLeave and mouse scripts are set (it
-- hooks them, and a script set later would replace the hooks). The owner places it with
-- frame:Rest(point, relativeTo, relativePoint, x, y)
-- (the tile's place at rest; the states move it from there) and may call
-- frame:SetObjectState("rest" | "hover" | "press") itself (a list that hands a tile on).
-- ---------------------------------------------------------------------------------------------

S.OBJECT = {
  radius = 5,
  rest = { lift = 0, drop = 4, spread = 12 },
  hover = { lift = 2, drop = 8, spread = 20 },
  press = { lift = -1, drop = 2, spread = 6 },
}

function S.object(frame, spec)
  spec = spec or {}
  local radius = spec.radius or S.OBJECT.radius
  frame.objectSpec = spec
  S.shadow(frame, S.OBJECT.rest.spread, S.OBJECT.rest.drop)
  -- the lit edge, 2 wide: one outline at the tile's edge and one a unit inside it, over
  -- everything the tile holds
  local lit = CreateFrame("Frame", nil, frame)
  lit:SetAllPoints(frame)
  lit:SetFrameLevel((frame:GetFrameLevel() or 0) + 12)
  lit.outer = S.roundEdges(lit, S.C[spec.edge or "folioGold"], radius)
  lit.innerFrame = CreateFrame("Frame", nil, lit)
  lit.innerFrame:SetPoint("TOPLEFT", lit, "TOPLEFT", 1, -1)
  lit.innerFrame:SetPoint("BOTTOMRIGHT", lit, "BOTTOMRIGHT", -1, 1)
  lit.inner = S.roundEdges(lit.innerFrame, S.C[spec.edge or "folioGold"], math.max(1, radius - 1))
  -- a light line at the top edge, a dark one at the foot (inside the round corners)
  lit.top = S.fill(lit, S.C.folioLight, "OVERLAY")
  lit.top:ClearAllPoints()
  lit.top:SetPoint("TOPLEFT", lit, "TOPLEFT", radius, 0)
  lit.top:SetPoint("TOPRIGHT", lit, "TOPRIGHT", -radius, 0)
  lit.top:SetHeight(1)
  lit.foot = S.fill(lit, S.C.folioDark, "OVERLAY")
  lit.foot:ClearAllPoints()
  lit.foot:SetPoint("BOTTOMLEFT", lit, "BOTTOMLEFT", radius, 0)
  lit.foot:SetPoint("BOTTOMRIGHT", lit, "BOTTOMRIGHT", -radius, 0)
  lit.foot:SetHeight(1)
  frame.lit = lit
  function frame.Rest(self, point, rel, relPoint, x, y)
    self.rest = { point, rel, relPoint, x or 0, y or 0 }
    self:SetObjectState(self.objectState or "rest")
  end
  function frame.SetObjectState(self, state)
    local st = S.OBJECT[state] or S.OBJECT.rest
    self.objectState = S.OBJECT[state] and state or "rest"
    local on = self.objectState ~= "rest"
    S.setEdges(self.lit.outer, S.Tok(self, spec.edge or "folioGold"), on and 1 or 0)
    S.setEdges(self.lit.inner, S.Tok(self, spec.edge or "folioGold"), on and 1 or 0)
    S.shadow(self, st.spread, st.drop)
    local r = self.rest
    if r then
      self:ClearAllPoints()
      self:SetPoint(r[1], r[2], r[3], r[4], r[5] + st.lift)
    end
  end
  frame:HookScript("OnEnter", function(self)
    self:SetObjectState("hover")
  end)
  frame:HookScript("OnLeave", function(self)
    self:SetObjectState("rest")
  end)
  frame:HookScript("OnMouseDown", function(self)
    self:SetObjectState("press")
  end)
  frame:HookScript("OnMouseUp", function(self)
    self:SetObjectState(self:IsMouseOver() and "hover" or "rest")
  end)
  frame:HookScript("OnHide", function(self)
    self:SetObjectState("rest") -- a tile that goes while lifted comes back at rest
  end)
  frame:SetObjectState("rest")
  return frame
end

-- A torn paper edge over `parent`'s picture, `level` frame levels above it, in the paper's colour
-- (`token`, default folioPaper). -> its frame (`.tex` the texture), DECKLE_H high; the caller
-- places it.
function S.deckle(parent, level, token)
  local f = CreateFrame("Frame", nil, parent)
  f:SetFrameLevel(parent:GetFrameLevel() + (level or 1))
  f:SetHeight(S.DECKLE_H)
  f.tex = f:CreateTexture(nil, "ARTWORK")
  f.tex:SetTexture(S.DECKLE)
  f.tex:SetAllPoints(f)
  S.tint(f.tex, S.C[token or "folioPaper"])
  return f
end

-- The fade from clear at the top to `token` at the foot (words on a picture), on a frame of its
-- own `level` levels over `parent`. -> its frame (`.tex` the texture); the caller places it.
function S.fade(parent, level, token)
  local f = CreateFrame("Frame", nil, parent)
  f:SetFrameLevel(parent:GetFrameLevel() + (level or 1))
  f.tex = f:CreateTexture(nil, "ARTWORK")
  f.tex:SetTexture(S.FADE)
  f.tex:SetAllPoints(f)
  S.tint(f.tex, S.C[token or "folioShade"])
  return f
end
