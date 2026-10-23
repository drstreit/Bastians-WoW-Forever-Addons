-- UI kit: Bastians.UI.FilterBar(parent): one line of dropdown pills, one per dimension (ADR 0016).
local _, ns = ...
local B = ns.B
local S = ns.Style
local L = ns.L

local PILL_H, PILL_GAP, LINE_GAP = 20, 6, 4
local PAD, ARROW_W, CLEAR_W = 8, 9, 16
local ITEM_H, MENU_MIN, MENU_MAX = 20, 140, 320

local Bar = {}
Bar.__index = Bar

-- ---------------------------------------------------------------------------------------------
-- The dropdown: one shared frame, opaque, one line per choice with its count on the right
-- ---------------------------------------------------------------------------------------------

local menu

local function menuItem(i)
  local b = menu.items[i]
  if b then
    return b
  end
  b = CreateFrame("Button", nil, menu)
  b:SetHeight(ITEM_H)
  b.hl = S.fill(b, S.C.hover, "ARTWORK")
  b.hl:Hide()
  b.label = S.text(b, 12)
  b.label:SetPoint("LEFT", PAD, 0)
  b.label:SetWordWrap(false)
  b.count = S.text(b, 11, S.C.dim)
  b.count:SetPoint("RIGHT", -PAD, 0)
  b.count:SetJustifyH("RIGHT")
  b:SetScript("OnEnter", function(self)
    self.hl:Show()
  end)
  b:SetScript("OnLeave", function(self)
    self.hl:Hide()
  end)
  b:SetScript("OnClick", function(self)
    local fn = menu.onSelect
    menu:Hide()
    if fn then
      fn(self.key)
    end
  end)
  menu.items[i] = b
  return b
end

local function buildMenu()
  menu = CreateFrame("Frame", "BastiansFilterMenu", UIParent)
  menu:SetFrameStrata("TOOLTIP")
  menu:SetClampedToScreen(true)
  menu:EnableMouse(true)
  S.panel(menu, S.C.panel)
  S.tint(menu.bg, S.C.panel, 1) -- opaque, as the entity menu
  menu.items = {}
  -- a click anywhere else closes it
  menu:SetScript("OnShow", function(self)
    self:RegisterEvent("GLOBAL_MOUSE_DOWN")
  end)
  menu:SetScript("OnHide", function(self)
    self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
  end)
  menu:SetScript("OnEvent", function(self)
    if not (self:IsMouseOver() or (self.anchor and self.anchor:IsMouseOver())) then
      self:Hide()
    end
  end)
  menu:Hide()
  return menu
end

local function textWidth(fs)
  local w = fs:GetStringWidth() or 0
  if w == 0 then -- no font metrics (the mock, a font not loaded yet): an estimate
    w = #(fs:GetText() or "") * 6
  end
  return w
end

-- The choices of a dimension as the dropdown lists them: All first (when the dimension has one).
local function menuChoices(dim)
  local out = {}
  if dim.all ~= false then
    local all = dim.all or {}
    out[1] = { key = nil, label = all.label or L["All"], count = all.count }
  end
  for _, c in ipairs(dim.choices or {}) do
    out[#out + 1] = c
  end
  return out
end

-- Opens the dropdown of `dim` under `anchor`. Returns the menu frame (tests read its items).
function B.UI.FilterMenu(dim, anchor)
  menu = menu or buildMenu()
  local choices = menuChoices(dim)
  local width = MENU_MIN
  for i, c in ipairs(choices) do
    local b = menuItem(i)
    b.key = c.key
    b.label:SetText(tostring(c.label))
    b.count:SetText(c.count and tostring(c.count) or "")
    local on = c.key == dim.active
    local col = on and S.C.accent or S.C.text
    b.label:SetTextColor(col[1], col[2], col[3])
    width = math.max(width, textWidth(b.label) + textWidth(b.count) + 3 * PAD + 8)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 1, -(1 + (i - 1) * ITEM_H))
    b:SetPoint("RIGHT", -1, 0)
    b:Show()
  end
  for i = #choices + 1, #menu.items do
    menu.items[i]:Hide()
  end
  menu.onSelect, menu.anchor, menu.dim = dim.onSelect, anchor, dim
  menu:SetWidth(math.min(MENU_MAX, width))
  menu:SetHeight(2 + #choices * ITEM_H)
  menu:ClearAllPoints()
  if anchor then
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  end
  menu:Show()
  menu:Raise()
  return menu
end

function B.UI.HideFilterMenu()
  if menu then
    menu:Hide()
  end
end

function B.UI.FilterMenuFrame()
  return menu
end

-- ---------------------------------------------------------------------------------------------
-- The pills
-- ---------------------------------------------------------------------------------------------

-- The words of a dimension's current choice.
local function choiceLabel(dim)
  if dim.active == nil then
    return dim.all and dim.all.label or L["All"]
  end
  for _, c in ipairs(dim.choices or {}) do
    if c.key == dim.active then
      return tostring(c.label)
    end
  end
  return tostring(dim.active)
end

-- Whether the pill shows a choice of the player's (accent and the "x").
local function isSet(dim)
  return dim.active ~= dim.default
end

local function makePill(bar)
  local p = CreateFrame("Button", nil, bar.frame)
  p:SetHeight(PILL_H)
  p.face = S.roundFill(p, S.C.panel, "pill") -- the pills are round at both ends (ST3)
  p.edges = S.roundEdges(p, S.C.line, "pill")
  p.label = S.text(p, 12)
  p.label:SetPoint("LEFT", PAD, 0)
  p.label:SetWordWrap(false)
  p.arrow = p:CreateTexture(nil, "ARTWORK")
  p.arrow:SetTexture(S.ARROW)
  p.arrow:SetSize(ARROW_W, ARROW_W)
  p.arrow:SetRotation(-math.pi / 2) -- the arrow points east; a dropdown's points down
  p.clear = CreateFrame("Button", nil, p)
  p.clear:SetSize(CLEAR_W, PILL_H)
  p.clear:SetPoint("RIGHT", -2, 0)
  p.clear.label = S.text(p.clear, 12, S.C.dim)
  p.clear.label:SetPoint("CENTER")
  p.clear.label:SetText("x") -- ASCII, the game fonts lack the symbols (CLAUDE.md §12)
  p.clear.tip = L["Clear this filter"]
  p.clear:SetScript("OnEnter", function(self)
    self.label:SetTextColor(S.C.text[1], S.C.text[2], S.C.text[3])
    S.TipEnter(self)
  end)
  p.clear:SetScript("OnLeave", function(self)
    self.label:SetTextColor(S.C.dim[1], S.C.dim[2], S.C.dim[3])
    S.TipLeave(self)
  end)
  p.clear:SetScript("OnClick", function(self)
    local dim = self:GetParent().dim
    B.UI.HideFilterMenu()
    if dim and dim.onSelect then
      dim.onSelect(dim.default)
    end
  end)
  p:SetScript("OnEnter", function(self)
    S.tint(self.face, S.C.faceHover)
    S.TipEnter(self)
  end)
  p:SetScript("OnLeave", function(self)
    S.tint(self.face, S.C.panel)
    S.TipLeave(self)
  end)
  p:SetScript("OnClick", function(self)
    local m = B.UI.FilterMenuFrame()
    if m and m:IsShown() and m.anchor == self then
      m:Hide()
      return
    end
    B.UI.FilterMenu(self.dim, self)
  end)
  p.tip = function(self)
    local dim = self.dim
    return dim and dim.tip or L["Click to choose; the x clears the choice."]
  end
  return p
end

-- bar = Bastians.UI.FilterBar(parent): bar.frame (anchor it), bar:SetDims(dims), bar:Height().
-- dims[k] = { id, title, choices = { { key, label, count } } (in the order shown), active = key or
-- nil, default = the key the "x" restores (nil: All), all = { label, count } or false (no All
-- choice: a sort), onSelect = fn(key), tip = words }. A dimension with nothing to choose (fewer
-- than two entries in its dropdown) is left out. The pills flow left to right and wrap to a new
-- line when the width is used up.
function B.UI.FilterBar(parent)
  local bar = setmetatable({ pills = {}, dims = {}, height = 1 }, Bar)
  bar.frame = CreateFrame("Frame", nil, parent)
  bar.frame:SetHeight(1)
  return bar
end

function Bar:SetDims(dims)
  self.dims = {}
  for _, dim in ipairs(dims or {}) do
    if #menuChoices(dim) >= 2 then
      self.dims[#self.dims + 1] = dim
    end
  end
  self:Layout()
end

function Bar:Layout()
  local width = self.frame:GetWidth()
  if not width or width <= 0 then
    width = 400
  end
  local x, y, lines = 0, 0, (#self.dims > 0) and 1 or 0
  for i, dim in ipairs(self.dims) do
    local p = self.pills[i] or makePill(self)
    self.pills[i] = p
    p.dim = dim
    local set = isSet(dim)
    local title = S.hex(S.C.dim) .. tostring(dim.title) .. ":|r "
    p.label:SetText(title .. choiceLabel(dim))
    local col = set and S.C.accent or S.C.text
    p.label:SetTextColor(col[1], col[2], col[3])
    S.setEdges(p.edges, set and S.C.accent or S.C.line, set and 0.8 or nil)
    p.arrow:SetVertexColor(S.C.dim[1], S.C.dim[2], S.C.dim[3], 1)
    p.arrow:ClearAllPoints()
    p.arrow:SetPoint("LEFT", p.label, "RIGHT", 4, 0)
    if set then
      p.clear:Show()
    else
      p.clear:Hide()
    end
    local w = PAD + textWidth(p.label) + 4 + ARROW_W + (set and CLEAR_W or 0) + PAD
    if x > 0 and x + w > width then
      x, y = 0, y + PILL_H + LINE_GAP
      lines = lines + 1
    end
    p:SetSize(w, PILL_H)
    p.face:Layout()
    p.edges:Layout()
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -y)
    p:Show()
    x = x + w + PILL_GAP
  end
  for i = #self.dims + 1, #self.pills do
    self.pills[i]:Hide()
  end
  self.height = lines > 0 and (lines * PILL_H + (lines - 1) * LINE_GAP + LINE_GAP) or 1
  self.frame:SetHeight(self.height)
end

function Bar:Height()
  return self.height
end

-- The shown pills' words, for tests and the settings hub: { "Kind: Mailbox", ... } without colours.
function Bar:Labels()
  local out = {}
  for i = 1, #self.dims do
    local text = self.pills[i].label:GetText() or ""
    out[#out + 1] = (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
  end
  return out
end

-- The pill of a dimension by id, or nil.
function Bar:Pill(id)
  for i, dim in ipairs(self.dims) do
    if dim.id == id then
      return self.pills[i]
    end
  end
  return nil
end

B.UI.FILTER_PILL_H = PILL_H
