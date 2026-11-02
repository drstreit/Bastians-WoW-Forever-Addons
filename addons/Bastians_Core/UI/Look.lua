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

local function look()
  return LOOKS[S.LookId()] or LOOKS.modern
end

-- The look's own corner radii over the theme's (Style.applyShape reads them with every theme
-- load): Glass rounds more, Parchment squares the kind tiles (`tile`). nil: the theme's.
function S.LookShape()
  return look().shape
end

-- The look's cap on the window ground's opacity in percent (Glass: 75), nil for none.
function S.LookGroundAlpha()
  return look().groundAlpha
end

-- Draws one widget by the look in force (a changed spec, a changed look).
function S.Draw(frame)
  local kind = S.widgets[frame]
  local draw = kind and look()[kind]
  if draw then
    draw(frame)
  end
  return frame
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
-- text"). spec = { icon, label, tip, primary, on, boxed, only, row, onClick, badge }: `only`
-- draws the pictogram alone (the one case is "More"), `row` the smaller button inside a row,
-- `boxed` a face and edges in Modern (a quiet button has none). It sizes itself (Fit).
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
  b.tip = spec.tip or (spec.only and spec.label) or nil
  b:SetScript("OnEnter", function(self)
    local hover = look().hover
    if hover and self.enabledFlat ~= false then
      hover(self, true)
    end
    S.TipEnter(self)
  end)
  b:SetScript("OnLeave", function(self)
    local hover = look().hover
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
      self.badge.text = S.text(self.badge, 10, S.C.headerText)
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
  b.label:SetText(text)
  b.label:ClearAllPoints()
  if spec.width and not icon then
    b.label:SetPoint("CENTER") -- a fixed width without a pictogram: the word in the middle
  else
    b.label:SetPoint("LEFT", pad + iconW + (icon and text ~= "" and gap or 0), 0)
  end
  local w = pad + iconW + (icon and text ~= "" and gap or 0) + textWidth(b.label, text) + pad
  if spec.width then
    w = spec.width -- a column of equal buttons (the hub's rows): the app's choice
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
    S.tint(b.icon, S.Tok(b, spec.primary and "bg" or "accent"), 1)
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
    S.tint(b.icon, gold, 1)
    layoutAction(b, h, spec.icon and B.UI.Pictogram(spec.icon) or nil, G.gap, spec.only and 6 or 9)
    S.fitGameArt(b) -- the caps follow the size the layout gave
  end,
  tile = function(t)
    layoutTile(t, t.spec.big and S.G.tileBig or S.G.tile, S.Palette("blizzard").C.gold, 0.8)
  end,
}

-- ---------------------------------------------------------------------------------------------
-- The pill: a filter's choice or a view's chip, its kind tile, the label and a count; `on` the
-- chosen one, `gold` a choice of value, `menu` a dropdown's arrow after the label, `clear` a small
-- x after it (a button of its own: onClear, its tip clearTip, so a click on it never reaches the
-- pill's own click). spec = { kind, label, count, on, gold, menu, clear, clearTip, onClick, onClear }
-- ---------------------------------------------------------------------------------------------

function S.pill(parent, spec)
  spec = spec or {}
  local p = CreateFrame("Button", nil, parent)
  p.spec = spec
  p.face = S.roundFill(p, S.C.panel, "radius")
  p.edges = S.roundEdges(p, S.C.line, "radius")
  p.tile = S.tile(p, spec.kind)
  p.tile:SetPoint("LEFT", 4, 0)
  p.label = S.text(p, 12, S.C.text)
  p.label:SetJustifyH("LEFT")
  p.label:SetWordWrap(false)
  p.count = S.text(p, 11, S.C.dim)
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
    local hover = look().pillHover
    if hover then
      hover(self, true)
    end
    S.TipEnter(self)
  end)
  p:SetScript("OnLeave", function(self)
    local hover = look().pillHover
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

local function layoutPill(p, h, inkTok, edgeTok, edgeAlpha)
  local spec = p.spec
  p.tile:SetKind(spec.kind)
  p.tile:SetShown(spec.kind ~= nil)
  local x = spec.kind and (4 + S.G.tile + S.G.gap) or 10
  p.label:SetText(spec.label or "")
  p.label:ClearAllPoints()
  p.label:SetPoint("LEFT", x, 0)
  S.ink(p.label, S.Tok(p, inkTok))
  local w = x + textWidth(p.label, spec.label or "")
  if spec.count ~= nil then
    p.count:SetText(tostring(spec.count))
    p.count:ClearAllPoints()
    p.count:SetPoint("LEFT", w + 5, 0)
    S.ink(p.count, S.Tok(p, "dim"))
    p.count:Show()
    w = w + 5 + textWidth(p.count, tostring(spec.count))
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
  S.setEdges(p.edges, S.Tok(p, edgeTok), edgeAlpha)
  p:SetSize(w + (spec.clear and 4 or 10), h)
end

LOOKS.modern.pill = function(p)
  local spec = p.spec
  local ink = spec.on and "accent" or (spec.gold and "gold" or "text")
  hideSheen(p)
  S.tint(p.face, S.Tok(p, "panel"), 1)
  layoutPill(p, S.G.pill, ink, spec.on and "accent" or (spec.gold and "gold" or "line"), 1)
end

LOOKS.modern.pillHover = function(p, over)
  S.tint(p.face, S.Tok(p, over and "faceHover" or "panel"), 1)
end

LOOKS.wow.pill = function(p)
  local spec = p.spec
  local ink = (spec.on or spec.gold) and "gold" or "text"
  hideSheen(p)
  S.tint(p.face, S.Tok(p, "panel"), 1)
  layoutPill(p, S.G.pill, ink, (spec.on or spec.gold) and "gold" or "line", 1)
end

LOOKS.wow.pillHover = LOOKS.modern.pillHover

-- ---------------------------------------------------------------------------------------------
-- The tab: a kind tile, the label, a badge; `on` the shown one, `unread` lit.
-- spec = { kind, label, badge, on, unread, onClick, onDrag... (the app's own scripts stay) }
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
  t.label = S.text(t, 12, S.C.dim)
  t.label:SetJustifyH("LEFT")
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
  function t.SetBadge(self, n)
    n = tonumber(n) or 0
    if not self.badge then
      self.badge = CreateFrame("Frame", nil, self)
      self.badge:SetSize(16, 13)
      self.badge.bg = S.roundFill(self.badge, S.C.accent, "radiusSmall")
      self.badge.text = S.text(self.badge, 10, S.C.headerText)
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

local function layoutTab(t, h, inkTok, faceAlpha)
  local spec = t.spec
  t.tile:SetKind(spec.kind)
  t.tile:SetShown(spec.kind ~= nil)
  local x = spec.kind and (6 + S.G.tile + S.G.gap) or 10
  t.label:SetText(spec.label or "")
  t.label:ClearAllPoints()
  t.label:SetPoint("LEFT", x, 0)
  S.ink(t.label, S.Tok(t, inkTok))
  local w = x + textWidth(t.label, spec.label or "")
  if t.badge and (spec.badge or 0) > 0 then
    t.badge:ClearAllPoints()
    t.badge:SetPoint("LEFT", w + 5, 0)
    w = w + 5 + 16
  end
  S.tint(t.face, S.Tok(t, "panel"), faceAlpha)
  t:SetSize(w + 10, h)
end

-- The chosen tab reads in the accent inside an accent frame ("hard to
-- see what is menu tabs, what is text and what is active tab"); the others in dim.
LOOKS.modern.tab = function(t)
  local spec = t.spec
  layoutTab(t, S.G.tab, (spec.on or spec.unread) and "accent" or "dim", spec.on and 1 or 0)
  t.under:SetShown(spec.on == true)
  S.tint(t.under, S.Tok(t, "accent"), 1)
  S.setEdges(t.edges, S.Tok(t, "accent"), spec.on and 0.9 or 0)
end

LOOKS.wow.tab = function(t)
  local spec = t.spec
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
  s.title = S.text(s, 11, S.C.dim)
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
    S.tint(b.icon, S.Tok(b, spec.primary and "bg" or "accent"), 1)
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
  pill = function(p)
    local spec = p.spec
    hideSheen(p)
    S.tint(p.face, S.Tok(p, "panel"), 1)
    local ink = (spec.on or spec.gold) and "accent" or "text" -- no gold text on paper
    layoutPill(p, S.G.pill, ink, spec.on and "accent" or "muted", spec.on and 1 or 0.7)
  end,
  pillHover = LOOKS.modern.pillHover,
  tab = function(t)
    local spec = t.spec
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
    S.tint(b.icon, S.Tok(b, spec.primary and "bg" or "accent"), 1)
    layoutAction(b, h, spec.icon and B.UI.Pictogram(spec.icon) or nil, G.gap, spec.only and 6 or 8)
  end,
  hover = function(b, over)
    glassRim(b, over)
  end,
  tile = function(t)
    layoutTile(t, t.spec.big and S.G.tileBig or S.G.tile, S.Tok(t, "line"), 0)
  end,
  pill = function(p)
    local spec = p.spec
    glassPlate(p, "panel", GLASS_PLATE)
    local ink = spec.on and "accent" or (spec.gold and "gold" or "text")
    layoutPill(p, S.G.pill, ink, "bright", 0)
  end,
  pillHover = function(p, over)
    glassRim(p, over)
  end,
  tab = function(t)
    local spec = t.spec
    layoutTab(t, S.G.tab, (spec.on or spec.unread) and "accent" or "dim", spec.on and GLASS_PLATE or 0)
    t.under:SetShown(spec.on == true)
    S.tint(t.under, S.Tok(t, "accent"), 1)
    S.setEdges(t.edges, S.Tok(t, "accent"), spec.on and 0.9 or 0)
  end,
  section = LOOKS.modern.section,
  toggle = LOOKS.modern.toggle,
}
