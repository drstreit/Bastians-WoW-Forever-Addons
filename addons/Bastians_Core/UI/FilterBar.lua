-- UI kit: Bastians.UI.FilterBar(parent): one line of dropdown pills, one per dimension (ADR 0016);
-- a dimension marked `chips` shows every choice as a chip with its icon and count (ADR 0038). The
-- pills are the kit's S.pill (ADR 0046): the dimension's `kind` is their tile, the look draws them.
local _, ns = ...
local B = ns.B
local S = ns.Style
local L = ns.L

-- PILL_H: the chips' height (book-look.md section 5: 22, round at both ends, 9 beside the
-- words, 5 between two); a pill's is S.G.pill
local PILL_H, PILL_GAP, LINE_GAP = 22, 6, 4
local CHIP_GAP, CHIP_ICON = 5, 11
local PAD = 9
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

-- A pill (ADR 0046): the kit's S.pill with a dropdown arrow and the clearing x; its kind is the
-- dimension's `kind` (the Browser: Where = spot, Rank = rare).
local function makePill(bar)
  local p = S.pill(bar.frame, {
    menu = true,
    clearTip = L["Clear this filter"],
    onClick = function(self)
      local m = B.UI.FilterMenuFrame()
      if m and m:IsShown() and m.anchor == self then
        m:Hide()
        return
      end
      B.UI.FilterMenu(self.dim, self)
    end,
    onClear = function(self)
      local dim = self.dim
      B.UI.HideFilterMenu()
      if dim and dim.onSelect then
        dim.onSelect(dim.default)
      end
    end,
  })
  p.tip = function(self)
    local dim = self.dim
    return dim and dim.tip or L["Click to choose; the x clears the choice."]
  end
  return p
end

-- A chip (ADR 0038): one choice of a `chips` dimension; on when its key is in `dim.active` (a
-- set of keys), the All chip when the set is empty. Its icon is the choice's `icon` (a texture
-- path), its colour the theme token `token` of the choice.
local function chipOn(dim, key)
  local active = dim.active
  if key == nil then
    return active == nil or next(active) == nil
  end
  return type(active) == "table" and active[key] == true
end

local function makeChip(bar)
  local c = CreateFrame("Button", nil, bar.frame)
  c:SetHeight(PILL_H)
  c.face = S.roundFill(c, S.C.panel, "pill")
  c.edges = S.roundEdges(c, S.C.line, "pill")
  c.icon = c:CreateTexture(nil, "ARTWORK")
  c.icon:SetSize(CHIP_ICON, CHIP_ICON)
  c.icon:SetPoint("LEFT", PAD - 2, 0)
  c.label = S.text(c, 12)
  c.label:SetWordWrap(false)
  c.count = S.text(c, 11, S.C.muted)
  c.count:SetPoint("LEFT", c.label, "RIGHT", 4, 0)
  c:SetScript("OnEnter", function(self)
    if not self.on then
      S.tint(self.face, S.Tok(self, "faceHover"), 1)
    end
    S.TipEnter(self)
  end)
  c:SetScript("OnLeave", function(self)
    if not self.on then
      S.tint(self.face, S.Tok(self, "panel"), 0)
    end
    S.TipLeave(self)
  end)
  c:SetScript("OnClick", function(self)
    B.UI.HideFilterMenu()
    local dim = self.dim
    if dim and dim.onSelect then
      dim.onSelect(self.key)
    end
  end)
  c.tip = function(self)
    return self.dim and self.dim.tip or L["Click to switch this choice on or off; All clears them."]
  end
  return c
end

-- Lays the chips of `dim` out from (x, y); returns x, y and the height of the line it ends on.
-- A chip is quiet (no plate, the line's edge, the text's ink); the chosen one is filled in its
-- colour with the ground's ink (ADR 0084 decision 2: the chosen one filled).
local function layoutChips(bar, dim, x, y, width)
  local x0, lineGap = bar.x0, bar.lineGap
  for _, c in ipairs(menuChoices(dim)) do
    bar.chipCount = bar.chipCount + 1
    local chip = bar.chips[bar.chipCount] or makeChip(bar)
    bar.chips[bar.chipCount] = chip
    chip.dim, chip.key = dim, c.key
    local on = chipOn(dim, c.key)
    chip.on = on
    local col = (c.token and S.Tok(chip, c.token)) or S.Tok(chip, "accent")
    chip.label:SetText(tostring(c.label))
    chip.count:SetText(c.count and tostring(c.count) or "")
    S.ink(chip.label, S.Tok(chip, on and "bg" or "text"))
    S.ink(chip.count, S.Tok(chip, on and "bg" or "muted"))
    S.tint(chip.face, on and col or S.Tok(chip, "panel"), on and 1 or 0)
    S.setEdges(chip.edges, on and col or S.Tok(chip, "line"), 1)
    local w = PAD
    if c.icon then
      B.UI.PaintIcon(chip.icon, c.icon)
      chip.icon:Show()
      w = w + CHIP_ICON + 3
    else
      chip.icon:Hide()
    end
    chip.label:ClearAllPoints()
    chip.label:SetPoint("LEFT", w, 0)
    w = w + textWidth(chip.label) + (c.count and (4 + textWidth(chip.count)) or 0) + PAD
    if x > 0 and x + w > width then
      x, y = 0, y + PILL_H + lineGap
    end
    chip:SetSize(w, PILL_H)
    chip.face:Layout()
    chip.edges:Layout()
    chip:ClearAllPoints()
    chip:SetPoint("TOPLEFT", bar.frame, "TOPLEFT", x0 + x, -y)
    chip:Show()
    x = x + w + CHIP_GAP
  end
  return x, y, PILL_H
end

-- bar = Bastians.UI.FilterBar(parent): bar.frame (anchor it), bar:SetDims(dims), bar:Height().
-- dims[k] = { id, title, choices = { { key, label, count } } (in the order shown), active = key or
-- nil, default = the key the "x" restores (nil: All), all = { label, count } or false (no All
-- choice: a sort), onSelect = fn(key), tip = words }. A dimension with nothing to choose (fewer
-- than two entries in its dropdown) is left out. The pills flow left to right and wrap to a new
-- line when the width is used up. `opts.band` (ADR 0084 decision 2, W5): the bar is a band of its
-- own, on the panel's ground with a rule under it, in the band's padding and row gap
-- (B.UI.BandClass); without it the pills stand bare in the owner's frame.
function B.UI.FilterBar(parent, opts)
  local bar = setmetatable({ pills = {}, chips = {}, chipCount = 0, dims = {}, height = 1 }, Bar)
  bar.frame = CreateFrame("Frame", nil, parent)
  bar.frame:SetHeight(1)
  local Band = B.UI.BandClass
  bar.band = opts and opts.band == true
  bar.x0 = bar.band and Band.SIDE or 0
  bar.y0 = bar.band and Band.TOP or 0
  bar.foot = bar.band and Band.FOOT or LINE_GAP
  bar.lineGap = bar.band and Band.ROW_GAP or LINE_GAP
  if bar.band then
    bar.ground = S.fill(bar.frame, S.C.panel, "BACKGROUND")
    bar.rule = S.fill(bar.frame, S.C.line, "BORDER")
    bar.rule:ClearAllPoints()
    bar.rule:SetPoint("BOTTOMLEFT", bar.frame, "BOTTOMLEFT", 0, 0)
    bar.rule:SetPoint("BOTTOMRIGHT", bar.frame, "BOTTOMRIGHT", 0, 0)
    bar.rule:SetHeight(1)
    bar.ground:Hide()
    bar.rule:Hide()
  end
  -- the pills wrap at the bar's width: laid out again when it changes (the first layout often
  -- runs before the frame has one, and a resized window gives it another; owner, retail
  -- 31.10.2026: "the filter buttons should use the full width ... should readjust when scaling")
  bar.frame:SetScript("OnSizeChanged", function(_, width)
    if #bar.dims > 0 and width and width > 0 and width ~= bar.laidOutAt and not bar.relayout then
      bar.relayout = true
      C_Timer.After(0, function()
        bar.relayout = nil
        if (bar.frame:GetWidth() or 0) ~= bar.laidOutAt then
          bar:Layout()
        end
      end)
    end
  end)
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
  local x0, lineGap = self.x0, self.lineGap
  local full = width
  width = math.max(1, width - 2 * x0) -- the room between the band's side padding
  local pillH = S.G.pill or PILL_H
  local x, y, lineH = 0, self.y0, 0 -- lineH: the height of the line being filled, 0 while empty
  local bottom = self.y0 -- the foot of the last line that holds something
  local function newLine()
    if lineH > 0 then
      bottom = y + lineH
      y = bottom + lineGap
    end
    x, lineH = 0, 0
  end
  self.chipCount = 0
  local pillCount = 0
  for _, dim in ipairs(self.dims) do
    if dim.chips then
      -- a chips dimension takes its own line (ADR 0038)
      newLine()
      x, y, lineH = layoutChips(self, dim, x, y, width)
      newLine()
    end
  end
  for _, dim in ipairs(self.dims) do
    if not dim.chips then
      pillCount = pillCount + 1
      local p = self.pills[pillCount] or makePill(self)
      self.pills[pillCount] = p
      p.dim = dim
      local set = isSet(dim)
      local spec = p.spec
      spec.kind = dim.kind
      spec.label = S.hex(S.C.dim) .. tostring(dim.title) .. ":|r " .. choiceLabel(dim)
      spec.on = set or nil
      spec.clear = set or nil
      S.Draw(p)
      local w = p:GetWidth()
      if x > 0 and x + w > width then
        newLine()
      end
      p:ClearAllPoints()
      p:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x0 + x, -y)
      p:Show()
      lineH = math.max(lineH, pillH)
      x = x + w + PILL_GAP
    end
  end
  for i = pillCount + 1, #self.pills do
    self.pills[i]:Hide()
  end
  for i = self.chipCount + 1, #self.chips do
    self.chips[i]:Hide()
  end
  local total = y + lineH
  local any = total > self.y0
  if lineH > 0 then
    bottom = total
  end
  -- a band ends its padding under the last line; a bare bar keeps the air it always had
  self.height = any and ((self.band and bottom or total) + self.foot) or 1
  self.bottom = any and bottom or 0 -- the foot of the last line, without the air under it
  if self.ground then
    self.ground:SetShown(any)
    self.rule:SetShown(any)
    S.tint(self.ground, S.Tok(self.frame, "panel"))
    S.tint(self.rule, S.Tok(self.frame, "line"))
  end
  self.laidOutAt = full
  self.frame:SetHeight(self.height)
  if self.onHeight then
    self.onHeight(self.height) -- the owner moves its rows under the bar (Tree:SetFilters)
  end
end

function Bar:Height()
  return self.height
end

-- The shown pills' words, for tests and the settings hub: { "Kind: Mailbox", ... } without colours.
function Bar:Labels()
  local out = {}
  for _, p in ipairs(self.pills) do
    if p:IsShown() then
      local text = p.label:GetText() or ""
      out[#out + 1] = (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
    end
  end
  return out
end

-- The shown chips (ADR 0038): { { label, count, on, key } } in their order.
function Bar:Chips()
  local out = {}
  for i = 1, self.chipCount do
    local c = self.chips[i]
    out[#out + 1] = { label = c.label:GetText(), count = tonumber(c.count:GetText()), on = c.on, key = c.key }
  end
  return out
end

-- The pill of a dimension by id, or nil.
function Bar:Pill(id)
  for _, p in ipairs(self.pills) do -- by the pill's dimension: chips dimensions have no pill
    if p:IsShown() and p.dim and p.dim.id == id then
      return p
    end
  end
  return nil
end

B.UI.FILTER_PILL_H = PILL_H
