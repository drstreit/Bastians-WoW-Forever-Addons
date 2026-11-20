-- UI kit, the look engine (ADR 0046): a look is a table of draw functions, one per widget kind;
-- apps declare widgets (S.action, S.tile) and never draw them. Every widget keeps its declaration
-- (`frame.spec`) and registers in S.widgets, so a preset change redraws all of them at once
-- (S.ApplyLook, from S.ApplySkin). Four looks: `modern` (the dark and the light schemes), `wow`
-- (the game's red buttons with gold text, the tiles with a gilt edge), `parchment` (paper panels
-- with a sepia edge, square tiles, no gold text; plan-round4 H4) and `glass` (translucent plates
-- under every text, no edges, a light rim on hover, rounder corners). The sizes are the theme's
-- geometry tokens (S.G), the colours its colour tokens (S.C), never a number in an app; a look may
-- carry corner radii of its own (`shape`) and a cap on the window ground's opacity (`groundAlpha`).
local _, ns = ...
local B = ns.B
local S = ns.Style

S.widgets = setmetatable({}, { __mode = "k" }) -- [frame] = the widget kind
local LOOKS = {}
S.LOOKS = LOOKS

-- The look in force: the preset's `look` (Settings.LOOK_KEYS, since 01.11.2026); a profile saved
-- before it has none and reads it from the game's buttons switch of ADR 0038 (on: WoW).
function S.LookId()
  local id = S.Skin("look")
  if id and LOOKS[id] then
    return id
  end
  return S.GameButtons() and "wow" or "modern"
end

-- The look a frame draws in (ADR 0046's look per window, plan-chat-v3.md V13): its own or an
-- ancestor's (`frame.look`, set by S.SetFramePreset), else the suite's. Nothing is walked until a
-- frame took a look of its own (S.anyLook).
function S.LookOf(frame)
  if S.anyLook then
    local f = frame
    for _ = 1, 40 do
      if not f then
        break
      end
      local id = f.look
      if id and LOOKS[id] then
        return id
      end
      f = f.GetParent and f:GetParent() or nil
    end
  end
  return S.LookId()
end

local function look(frame)
  return LOOKS[frame and S.LookOf(frame) or S.LookId()] or LOOKS.modern
end

-- The look's own corner radii over the theme's (Style.applyShape reads them with every theme
-- load): Glass rounds more, Parchment squares the kind tiles (`tile`). nil: the theme's.
function S.LookShape(frame)
  return look(frame).shape
end

-- The look's cap on the window ground's opacity in percent (Glass: 75), nil for none.
function S.LookGroundAlpha(frame)
  return look(frame).groundAlpha
end

-- Draws one widget by the look in force where it stands (a changed spec, a changed look).
function S.Draw(frame)
  local kind = S.widgets[frame]
  local draw = kind and look(frame)[kind]
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
-- the pictogram on a small square of that colour, as the kind tiles are; no plate, no edge in
-- any look. `spec.primary` is the lit one: its word bright and a line of its colour under it.
function S.DrawHue(b)
  local spec = b.spec
  local token = S.Tok(b, spec.hue) or S.Tok(b, "accent")
  if S.hideGameArt then
    S.hideGameArt(b)
  end
  b:SetNormalTexture("")
  b:SetPushedTexture("")
  b:SetHighlightTexture("")
  S.tint(b.face, S.Tok(b, "panel"), 0)
  S.setEdges(b.edges, S.Tok(b, "line"), 0)
  if b.sheen then
    b.sheen:Hide()
  end
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

-- Every live widget again: a preset or theme change. The radii first (a look may bring its own),
-- so the shapes the widgets own lay out with the right corners.
function S.ApplyLook()
  S.applyShape()
  for shape in pairs(S.shapes or {}) do
    shape:Layout()
  end
  for frame in pairs(S.widgets) do
    S.Draw(frame)
  end
end

-- The second, lighter fill the Glass look stacks on a plate for depth; made when first drawn,
-- hidden by every other look.
local function sheen(f)
  if not f.sheen then
    f.sheen = S.roundFill(f, S.C.bright, f.face.radius, "BORDER")
  end
  return f.sheen
end

local function hideSheen(f)
  if f.sheen then
    f.sheen:Hide()
  end
end

local MODERN_PLATE, MODERN_PLATE_HOVER, MODERN_EDGE = 0.16, 0.3, 0.6 -- the accent plate of a boxed button
local GLASS_PLATE = 0.72 -- the plate under every text: 70 % and more (plan-round4 H4)
S.GLASS_QUIET = 0.5 -- an unchosen pill's plate: half the glass's (quiet chips, 16.11.2026)
local GLASS_SHEEN = 0.05
local GLASS_RIM = 0.35 -- the light rim, on hover only

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
-- V27). It sizes itself (Fit).
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
  b.tip = spec.tip or (spec.only and spec.label) or nil
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
      self.badge.text = S.SetRole(S.text(self.badge, 10, S.C.headerText), "number")
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

-- The shared layout of an action: the icon left, the text after it, the size from both.
local function layoutAction(b, h, icon, gap, pad)
  local spec = b.spec
  local iconW = icon and (h - 8) or 0
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
  local lead = pad + iconW + (icon and text ~= "" and gap or 0)
  b.label:SetText(text)
  b.label:ClearAllPoints()
  if spec.width and not icon then
    b.label:SetPoint("CENTER") -- a fixed width without a pictogram: the word in the middle
  else
    b.label:SetPoint("LEFT", lead, 0)
  end
  local textW = textWidth(b.label, text)
  local w = lead + textW + pad
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
    local room = math.max(1, w - lead - pad)
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
  f.value = S.heading(f, 16, 18, S.C.text)
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
-- Modern: quiet rounded buttons (a face only when boxed or primary), the text colour on the
-- icon, the accent for a button that is on; tiles with the theme's radius and a thin edge.
-- ---------------------------------------------------------------------------------------------

LOOKS.modern = {
  action = function(b)
    local spec, G = b.spec, S.G
    local h = spec.row and G.actionRow or G.action
    b:SetNormalTexture("")
    b:SetPushedTexture("")
    b:SetHighlightTexture("")
    S.hideGameArt(b)
    hideSheen(b)
    b.face:Show()
    b.edges:Show()
    -- a boxed button is a tinted plate with the accent's edge, its pictogram in the accent (owner,
    -- retail 01.11.2026: "coloured icons with text", as the map's tile buttons); a quiet one shows
    -- the coloured pictogram and the word alone
    local faceAlpha = spec.primary and 1 or (spec.boxed and MODERN_PLATE or 0)
    S.tint(b.face, S.Tok(b, spec.primary and "accent" or (spec.boxed and "accent" or "panel")), faceAlpha)
    local edge = spec.on and 1 or MODERN_EDGE
    S.setEdges(b.edges, S.Tok(b, "accent"), spec.boxed and not spec.primary and edge or 0)
    local ink = spec.primary and "bg" or (spec.on and "accent" or "text")
    S.ink(b.label, S.Tok(b, ink))
    S.tint(b.icon, iconInk(b), 1)
    layoutAction(b, h, spec.icon and B.UI.Pictogram(spec.icon) or nil, G.gap, spec.only and 5 or 7)
  end,
  hover = function(b, over)
    local spec = b.spec
    if spec.primary then
      return
    end
    if spec.boxed then
      S.tint(b.face, S.Tok(b, "accent"), over and MODERN_PLATE_HOVER or MODERN_PLATE)
    else
      S.tint(b.face, S.Tok(b, "faceHover"), over and 1 or 0)
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
-- WoW: the game's red button textures with the pictogram and the text in the game's gold; the
-- tiles with a gilt edge. Hover is the game's highlight.
-- ---------------------------------------------------------------------------------------------

LOOKS.wow = {
  action = function(b)
    local spec, G = b.spec, S.G
    local h = spec.row and G.actionRow or G.action
    hideSheen(b)
    S.applyButton(b) -- the textures, the face and edges hidden, the gold label
    local gold = S.Palette("blizzard").C.gold
    S.tint(b.icon, spec.toggle and not spec.on and S.Tok(b, "dim") or gold, 1)
    layoutAction(b, h, spec.icon and B.UI.Pictogram(spec.icon) or nil, G.gap, spec.only and 6 or 9)
    S.fitGameArt(b) -- the caps follow the size the layout gave
  end,
  tile = function(t)
    layoutTile(t, t.spec.big and S.G.tileBig or S.G.tile, S.Palette("blizzard").C.gold, 0.8)
  end,
  stat = function(f)
    layoutStat(f, S.Tok(f, "card"), S.Palette("blizzard").C.gold, 0.8)
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

LOOKS.modern.pill = function(p)
  hideSheen(p)
  if p.spec.on then
    return chosenPill(p, S.Tok(p, "accent"))
  end
  quietPill(p)
end

-- A chosen pill keeps its fill under the mouse; a quiet one shows its plate while the mouse is on it.
LOOKS.modern.pillHover = function(p, over)
  if not p.spec.on then
    S.tint(p.face, S.Tok(p, over and "faceHover" or "panel"), over and 1 or 0)
  end
end

-- The chosen one in the game's gold; inside a palette of its own (the book's dark table,
-- S.FolioPalette) in that palette's gold.
LOOKS.wow.pill = function(p)
  hideSheen(p)
  if p.spec.on then
    local own = S.PaletteOf(p)
    return chosenPill(p, own and own.C.gold or S.Palette("blizzard").C.gold)
  end
  quietPill(p)
end

LOOKS.wow.pillHover = LOOKS.modern.pillHover

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
      self.badge.text = S.SetRole(S.text(self.badge, 10, S.C.headerText), "number")
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
    label = string.upper(label)
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

-- The chosen tab reads in the accent inside an accent frame ("hard to
-- see what is menu tabs, what is text and what is active tab"); the others in dim.
LOOKS.modern.tab = function(t)
  local spec = t.spec
  if spec.line then
    return flatTab(t, "text", true)
  end
  layoutTab(t, S.G.tab, (spec.on or spec.unread) and "accent" or "dim", spec.on and 1 or 0)
  t.under:SetShown(spec.on == true)
  S.tint(t.under, S.Tok(t, "accent"), 1)
  S.setEdges(t.edges, S.Tok(t, "accent"), spec.on and 0.9 or 0)
end

LOOKS.wow.tab = function(t)
  local spec = t.spec
  if spec.line then
    return flatTab(t, "gold", false)
  end
  layoutTab(t, S.G.tab, (spec.on or spec.unread) and "gold" or "dim", spec.on and 1 or 0.6)
  t.under:SetShown(spec.on == true)
  S.tint(t.under, S.Palette("blizzard").C.gold, 1)
  S.setEdges(t.edges, S.Palette("blizzard").C.gold, spec.on and 0.9 or 0)
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
  s.title:SetText(upper and string.upper(title) or title)
  s.title:ClearAllPoints()
  s.title:SetPoint("LEFT", icon and 20 or 0, 0)
  S.ink(s.title, S.Tok(s, inkTok))
end

LOOKS.modern.section = function(s)
  layoutSection(s, "dim", true)
  s.rule:Hide()
end

LOOKS.wow.section = function(s)
  layoutSection(s, "gold", false)
  S.tint(s.rule, S.Palette("blizzard").C.gold, 0.6)
  s.rule:Show()
end

-- ---------------------------------------------------------------------------------------------
-- The toggle: Modern a switch (a track with its knob), WoW the game's box with a cross.
-- spec = { on, onChange(self, on) }; the label is the row's, not the widget's.
-- ---------------------------------------------------------------------------------------------

function S.toggle(parent, spec)
  spec = spec or {}
  local t = CreateFrame("Button", nil, parent)
  t.spec = spec
  t.track = S.roundFill(t, S.C.line, "radius")
  t.edges = S.roundEdges(t, S.C.line, "radius")
  t.knob = CreateFrame("Frame", nil, t)
  t.knob.fill = S.roundFill(t.knob, S.C.bright, "radius")
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

LOOKS.modern.toggle = function(t)
  local on = t.spec.on == true
  t:SetSize(34, 18)
  t.track:Show()
  S.tint(t.track, S.Tok(t, on and "accent" or "line"), 1)
  S.setEdges(t.edges, S.Tok(t, "line"), 0)
  t.knob:SetSize(14, 14)
  t.knob:ClearAllPoints()
  t.knob:SetPoint("LEFT", on and 18 or 2, 0)
  t.knob:Show()
  t.mark:Hide()
end

LOOKS.wow.toggle = function(t)
  t:SetSize(18, 18)
  t.track:Show()
  S.tint(t.track, S.Tok(t, "panel"), 1)
  S.setEdges(t.edges, S.Palette("blizzard").C.gold, 0.9)
  t.knob:Hide()
  S.ink(t.mark, S.Palette("blizzard").C.gold)
  t.mark:SetShown(t.spec.on == true)
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

LOOKS.modern.card = function(c)
  hideSheen(c)
  local hot = c.spec.hot
  layoutCard(c, "card", 1, hot and "cardHot" or "cardEdge", 1)
end

LOOKS.modern.cardHover = function(c, over)
  S.tint(c.face, S.Tok(c, over and "hover" or "card"), 1)
end

LOOKS.wow.card = function(c)
  hideSheen(c)
  local hot = c.spec.hot
  layoutCard(c, "card", 1, hot and "cardHot" or S.Palette("blizzard").C.gold, hot and 1 or 0.5)
end

LOOKS.wow.cardHover = LOOKS.modern.cardHover

-- ---------------------------------------------------------------------------------------------
-- Parchment: paper panels with a sepia
-- edge on every boxed button, square kind tiles with the same edge, no gold text (a choice of
-- value reads in the accent), section titles in their own case over a sepia rule. The paper
-- itself and the brown ink are the Parchment scheme's; the serif headings the preset's font.
-- Never on the rock ground: the preset keeps the game's frames off.
-- ---------------------------------------------------------------------------------------------

LOOKS.parchment = {
  shape = { tile = 0 },
  action = function(b)
    local spec, G = b.spec, S.G
    local h = spec.row and G.actionRow or G.action
    b:SetNormalTexture("")
    b:SetPushedTexture("")
    b:SetHighlightTexture("")
    S.hideGameArt(b)
    hideSheen(b)
    b.face:Show()
    b.edges:Show()
    local faceAlpha = (spec.primary or spec.boxed) and 1 or 0
    S.tint(b.face, S.Tok(b, spec.primary and "accent" or "panel"), faceAlpha)
    local edge = spec.on and "accent" or "muted"
    S.setEdges(b.edges, S.Tok(b, edge), spec.boxed and not spec.primary and 0.7 or 0)
    local ink = spec.primary and "bg" or (spec.on and "accent" or "text")
    S.ink(b.label, S.Tok(b, ink))
    S.tint(b.icon, iconInk(b), 1)
    layoutAction(b, h, spec.icon and B.UI.Pictogram(spec.icon) or nil, G.gap, spec.only and 5 or 7)
  end,
  hover = function(b, over)
    if not b.spec.primary then
      S.tint(b.face, S.Tok(b, over and "faceHover" or "panel"), (over or b.spec.boxed) and 1 or 0)
    end
  end,
  tile = function(t)
    layoutTile(t, t.spec.big and S.G.tileBig or S.G.tile, S.Tok(t, "muted"), 0.9)
  end,
  stat = function(f)
    layoutStat(f, S.Tok(f, "card"), S.Tok(f, "muted"), 0.9)
  end,
  pill = function(p)
    local spec = p.spec
    hideSheen(p)
    if spec.on then
      return chosenPill(p, S.Tok(p, "accent"))
    end
    S.tint(p.face, S.Tok(p, "panel"), 0) -- quiet: no plate, a faint sepia edge (16.11.2026)
    local ink = spec.gold and "accent" or "text" -- no gold text on paper
    layoutPill(p, pillHeight(p), ink, "muted", 0.35)
  end,
  pillHover = LOOKS.modern.pillHover,
  tab = function(t)
    local spec = t.spec
    if spec.line then
      return flatTab(t, "text", false)
    end
    layoutTab(t, S.G.tab, (spec.on or spec.unread) and "accent" or "dim", spec.on and 1 or 0)
    t.under:SetShown(spec.on == true)
    S.tint(t.under, S.Tok(t, "accent"), 1)
    S.setEdges(t.edges, S.Tok(t, "accent"), spec.on and 0.9 or 0)
  end,
  section = function(s)
    layoutSection(s, "dim", false)
    S.tint(s.rule, S.Tok(s, "muted"), 0.5)
    s.rule:Show()
  end,
  toggle = LOOKS.modern.toggle,
}

-- ---------------------------------------------------------------------------------------------
-- Glass: two stacked translucent fills under
-- every text (the plate at 72 %, a light sheen over it), no edges, a light rim on hover only, 10 px
-- corners on windows and 8 px on buttons, the window ground capped at 75 %. Dark glass on a dark
-- scheme, light glass on a light one: the scheme decides.
-- ---------------------------------------------------------------------------------------------

local function glassPlate(f, tok, alpha)
  f.face:Show()
  S.tint(f.face, S.Tok(f, tok), alpha)
  local veil = sheen(f)
  veil:Show()
  S.tint(veil, S.Tok(f, "bright"), GLASS_SHEEN)
end

local function glassRim(f, over)
  S.setEdges(f.edges, S.Tok(f, "bright"), over and GLASS_RIM or 0)
end

LOOKS.glass = {
  shape = { radius = 10, radiusSmall = 8 },
  groundAlpha = 75,
  action = function(b)
    local spec, G = b.spec, S.G
    local h = spec.row and G.actionRow or G.action
    b:SetNormalTexture("")
    b:SetPushedTexture("")
    b:SetHighlightTexture("")
    S.hideGameArt(b)
    b.edges:Show()
    glassPlate(b, spec.primary and "accent" or "panel", spec.primary and 0.9 or GLASS_PLATE)
    glassRim(b, false)
    local ink = spec.primary and "bg" or (spec.on and "accent" or "text")
    S.ink(b.label, S.Tok(b, ink))
    S.tint(b.icon, iconInk(b), 1)
    layoutAction(b, h, spec.icon and B.UI.Pictogram(spec.icon) or nil, G.gap, spec.only and 6 or 8)
  end,
  hover = function(b, over)
    glassRim(b, over)
  end,
  tile = function(t)
    layoutTile(t, t.spec.big and S.G.tileBig or S.G.tile, S.Tok(t, "line"), 0)
  end,
  stat = function(f)
    layoutStat(f, S.Tok(f, "card"), S.Tok(f, "line"), 0)
  end,
  pill = function(p)
    local spec = p.spec
    if spec.on then
      glassPlate(p, "accent", 0.9) -- the chosen one filled, as a primary action's plate
      return layoutPill(p, pillHeight(p), "bg", "bright", 0, "bg")
    end
    -- quiet (16.11.2026): the plate at half the glass's strength, the chosen one stands out
    glassPlate(p, "panel", GLASS_PLATE * S.GLASS_QUIET)
    layoutPill(p, pillHeight(p), spec.gold and "gold" or "text", "bright", 0)
  end,
  pillHover = function(p, over)
    glassRim(p, over)
  end,
  tab = function(t)
    local spec = t.spec
    if spec.line then
      return flatTab(t, "text", true)
    end
    layoutTab(t, S.G.tab, (spec.on or spec.unread) and "accent" or "dim", spec.on and GLASS_PLATE or 0)
    t.under:SetShown(spec.on == true)
    S.tint(t.under, S.Tok(t, "accent"), 1)
    S.setEdges(t.edges, S.Tok(t, "accent"), spec.on and 0.9 or 0)
  end,
  section = LOOKS.modern.section,
  toggle = LOOKS.modern.toggle,
}

-- The card in Parchment and Glass (plan-chat-v3.md §9): paper with its sepia edge; glass with its
-- plate and no edge, the rim in the fresh card's colour while it is fresh and on hover.
LOOKS.parchment.card = function(c)
  hideSheen(c)
  local hot = c.spec.hot
  layoutCard(c, "card", 1, hot and "cardHot" or "muted", hot and 1 or 0.5)
end
LOOKS.parchment.cardHover = function(c, over)
  S.tint(c.face, S.Tok(c, over and "faceHover" or "card"), 1)
end

LOOKS.glass.card = function(c)
  local hot = c.spec.hot
  layoutCard(c, "panel", GLASS_PLATE, hot and "cardHot" or "bright", hot and 1 or 0)
  if c.spec.flat then
    hideSheen(c)
  else
    local veil = sheen(c)
    veil:Show()
    S.tint(veil, S.Tok(c, "bright"), GLASS_SHEEN)
  end
end
LOOKS.glass.cardHover = function(c, over)
  if not c.spec.hot then
    glassRim(c, over)
  end
end

-- ---------------------------------------------------------------------------------------------
-- The segmented switch (plan-chat-v3.md V27, the chat artifact's layout switch; owner, Forever
-- 13.11.2026: "the button look all the same color"): two or more choices side by side on one
-- plate, the chosen one filled, so the switch says which is shown. spec = { items = { { id,
-- label, icon, tip } }, value (the chosen id; nil: none), onChange(self, id) }. A click on another
-- part chooses it and calls onChange; SetValue chooses without the call; Part(id) is its button.
-- ---------------------------------------------------------------------------------------------

S.SEGMENT_HOVER = 0.25 -- the fill's opacity under the mouse on a part not chosen

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
      if f.spec.value ~= self.item.id and f.fillTok then
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
      if f.spec.value == id then
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
    hideSheen(f)
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
    x = x + w + (f.spec.gap or 0) -- `spec.gap`: room between the parts (words in a row)
  end
  f:SetSize(math.max(x, h), h)
end

LOOKS.modern.segmented = function(f)
  hideSheen(f)
  S.tint(f.face, S.Tok(f, "panel"), 1)
  S.setEdges(f.edges, S.Tok(f, "line"), 1)
  layoutSegmented(f, {
    fill = S.Tok(f, "accent"),
    on = S.Tok(f, "bg"),
    off = S.Tok(f, "text"),
    icon = S.Tok(f, "accent"),
  })
end

LOOKS.parchment.segmented = function(f)
  hideSheen(f)
  S.tint(f.face, S.Tok(f, "panel"), 1)
  S.setEdges(f.edges, S.Tok(f, "muted"), 0.7)
  layoutSegmented(f, {
    fill = S.Tok(f, "accent"),
    on = S.Tok(f, "bg"),
    off = S.Tok(f, "text"),
    icon = S.Tok(f, "accent"),
  })
end

LOOKS.glass.segmented = function(f)
  glassPlate(f, "panel", GLASS_PLATE)
  glassRim(f, false)
  layoutSegmented(f, {
    fill = S.Tok(f, "accent"),
    on = S.Tok(f, "bg"),
    off = S.Tok(f, "text"),
    icon = S.Tok(f, "accent"),
  })
end

-- WoW: a dark plate with a gilt edge, the chosen part in the game's gold with dark words.
-- Inside a palette of its own (the book's dark table, S.FolioPalette): that palette's gold, the
-- parts not chosen in its quiet ink.
LOOKS.wow.segmented = function(f)
  hideSheen(f)
  local own = S.PaletteOf(f)
  local gold = own and own.C.gold or S.Palette("blizzard").C.gold
  S.tint(f.face, S.Tok(f, "panel"), 1)
  S.setEdges(f.edges, gold, 0.8)
  layoutSegmented(f, { fill = gold, on = S.Tok(f, "bg"), off = own and own.C.dim or gold, icon = gold })
end

-- ---------------------------------------------------------------------------------------------
-- The slider (plan-chat-one-window.md §8, R1, V34; , screens 1 and 2:
-- the flat track with a square knob, the artifact's slider): a title in the labels' face, the
-- track filled up to the knob in the accent, a round knob, the value at the right and a line of
-- words under it ("2 . and what is yours"). The WoW look draws the game's own slider: its bar and
-- its knob. spec = { title, plain (the title as written, not in capitals), min, max, step, value,
-- words = function(v) -> the line under, number = function(v) -> the value's text (default the
-- number), onChange(self, v) }. SetValue(v, silent) moves it without the call.
-- ---------------------------------------------------------------------------------------------

S.SLIDER_KNOB = 12 -- the round knob of the flat looks
S.SLIDER_TRACK = 4 -- the track's height in the flat looks
S.SLIDER_TOP = 16 -- the track's row under the title
S.GAME_SLIDER_BAR = "Interface\\Buttons\\UI-SliderBar-Background"
S.GAME_SLIDER_KNOB = "Interface\\Buttons\\UI-SliderBar-Button-Horizontal"

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
  -- the flat looks' track and its filled part, under the knob
  f.rail = CreateFrame("Frame", nil, slider)
  f.rail:SetPoint("LEFT", slider, "LEFT", 0, 0)
  f.rail:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
  f.rail:SetHeight(S.SLIDER_TRACK)
  f.track = S.roundFill(f.rail, S.C.track, "pill")
  f.filled = CreateFrame("Frame", nil, f.rail)
  f.filled:SetPoint("TOPLEFT", f.rail, "TOPLEFT", 0, 0)
  f.filled:SetPoint("BOTTOMLEFT", f.rail, "BOTTOMLEFT", 0, 0)
  f.fill = S.roundFill(f.filled, S.C.accent, "pill", "BORDER")
  -- the game's bar (the WoW look)
  f.bar = slider:CreateTexture(nil, "BACKGROUND")
  f.bar:SetPoint("TOPLEFT", slider, "TOPLEFT", 0, 2)
  f.bar:SetPoint("BOTTOMRIGHT", slider, "BOTTOMRIGHT", 0, -2)
  f.bar:Hide()
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
  f.title:SetText(spec.plain and title or string.upper(title))
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

-- the flat looks: a thin track, filled up to a round knob in the accent
local function flatSlider(f, trackTok, fillTok, knobTok)
  f.bar:Hide()
  f.rail:Show()
  S.tint(f.track, trackTok, 1)
  S.tint(f.fill, fillTok, 1)
  f.knob:SetTexture(S.DISC)
  f.knob:SetTexCoord(0, 1, 0, 1)
  f.knob:SetSize(S.SLIDER_KNOB, S.SLIDER_KNOB)
  S.tint(f.knob, knobTok, 1)
end

LOOKS.modern.slider = function(f)
  flatSlider(f, S.Tok(f, "line"), S.Tok(f, "accent"), S.Tok(f, "bright"))
  layoutSlider(f, S.Tok(f, "muted"), S.Tok(f, "dim"), S.Tok(f, "text"))
end

LOOKS.parchment.slider = function(f)
  flatSlider(f, S.Tok(f, "line"), S.Tok(f, "accent"), S.Tok(f, "accent"))
  layoutSlider(f, S.Tok(f, "muted"), S.Tok(f, "dim"), S.Tok(f, "text"))
end

LOOKS.glass.slider = function(f)
  flatSlider(f, S.Tok(f, "line"), S.Tok(f, "accent"), S.Tok(f, "bright"))
  layoutSlider(f, S.Tok(f, "muted"), S.Tok(f, "dim"), S.Tok(f, "text"))
end

-- WoW: the game's own slider bar and knob, the title in the game's gold
LOOKS.wow.slider = function(f)
  local gold = S.Palette("blizzard").C.gold
  f.rail:Hide()
  f.bar:SetTexture(S.GAME_SLIDER_BAR)
  S.untint(f.bar)
  f.bar:Show()
  f.knob:SetTexture(S.GAME_SLIDER_KNOB)
  f.knob:SetTexCoord(0, 1, 0, 1)
  f.knob:SetSize(32, 32)
  S.untint(f.knob)
  layoutSlider(f, gold, S.Tok(f, "dim"), S.Tok(f, "text"))
end
