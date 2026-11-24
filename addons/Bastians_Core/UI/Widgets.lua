-- UI kit: flat form widgets for the settings renderer: checkbox, slider, select, header, note.
local _, ns = ...
local B = ns.B
local S = ns.Style
local L = ns.L

local W = {}
B.UI.Widgets = W

local ROW = 22

-- Checkbox: the book's switch (S.toggle, 28 x 15; ADR 0084 decision 2: it replaces the
-- checkboxes of every settings page; a box with an "x" until 23.11.2026) and a label. A click
-- anywhere on the row switches it. onChange(checked) after a click.
function W.Checkbox(parent, label, onChange)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(ROW)
  b.box = S.toggle(b, {})
  b.box:SetPoint("LEFT", 0, 0)
  b.box:EnableMouse(false) -- the row takes the click
  b.label = S.text(b, 12)
  b.label:SetPoint("LEFT", b.box, "RIGHT", 6, 0)
  b.label:SetPoint("RIGHT", 0, 0)
  b.label:SetText(label or "")
  b.checked = false
  function b.SetChecked(self, on)
    self.checked = on and true or false
    self.box:SetOn(self.checked)
  end
  function b.GetChecked(self)
    return self.checked
  end
  -- the switch at the right of the label, as on a card of the settings hub (ADR 0058, PH7)
  function b.SetControlRight(self)
    self.box:ClearAllPoints()
    self.box:SetPoint("RIGHT", 0, 0)
    self.label:ClearAllPoints()
    self.label:SetPoint("LEFT", 0, 0)
    self.label:SetPoint("RIGHT", self.box, "LEFT", -6, 0)
    self.controlRight = true
  end
  b:SetScript("OnClick", function(self)
    self:SetChecked(not self.checked)
    if onChange then
      onChange(self.checked)
    end
  end)
  return b
end

-- Slider: label left, value right, a flat track. onChange(value) when the player moves it.
-- Slider: a thin call of the look engine's (S.slider, plan-chat-one-window.md V34): the label as
-- written, the value at the right; `label`, `value` and `slider` are its parts for the renderer.
function W.Slider(parent, label, min, max, step, onChange)
  local f = S.slider(parent, {
    title = label or "",
    plain = true,
    min = min,
    max = max,
    step = step or 1,
    onChange = onChange and function(_, v)
      onChange(v)
    end or nil,
  })
  f:SetHeight(ROW + 14)
  f.label, f.value, f.step = f.title, f.number, step or 1
  return f
end

-- Select: a button showing the current label; click opens a flat list below. values = { key = label }.
-- onChange(key) when the player picks one. SetValues(values) replaces the choices. Since
-- 24.11.2026 (ADR 0084 decision 2) it is a tool with a small arrow at its end: the chosen word
-- from the left, the arrow says that it opens.
W.SELECT_MIN, W.SELECT_MAX = 160, 320
function W.Select(parent, label, values, onChange)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(ROW)
  f.label = S.text(f, 12)
  f.label:SetPoint("LEFT", 0, 0)
  f.label:SetText(label or "")
  f.button = S.button(f, "", 160, 20)
  f.button.spec.menu = true
  f.button:SetPoint("RIGHT", 0, 0)
  f.list = CreateFrame("Frame", nil, f)
  f.list:SetFrameStrata("TOOLTIP")
  f.list:SetPoint("TOPRIGHT", f.button, "BOTTOMRIGHT", 0, -1)
  f.list:SetWidth(160)
  S.panel(f.list, S.C.panel)
  f.list.items = {}
  f.list:Hide()
  f.values = values or {}

  local function keys()
    local out = {}
    for k in pairs(f.values) do
      out[#out + 1] = k
    end
    table.sort(out, function(a, b)
      return tostring(f.values[a]) < tostring(f.values[b])
    end)
    return out
  end

  -- As wide as the longest choice ("the Skin button in options needs to
  -- be wider, it's overflown"), between W.SELECT_MIN and W.SELECT_MAX; the list as wide.
  function f.Fit(self)
    local widest = 0
    for _, text in pairs(self.values) do
      self.button.label:SetText(tostring(text))
      widest = math.max(widest, self.button.label:GetStringWidth() or 0)
    end
    -- the words, the room beside them and the arrow with its gap
    local w =
      math.max(W.SELECT_MIN, math.min(W.SELECT_MAX, math.ceil(widest) + 28 + S.MENU_GAP + S.MENU_ARROW))
    -- the button's own width, so the next SetLabel (which draws the button again) keeps it: it
    -- drew the button at its first 160 and a long choice ran out
    self.button.spec.width = w
    self.button:SetWidth(w)
    self.list:SetWidth(w)
    self.button.label:SetText(
      self.current ~= nil and tostring(self.values[self.current] or self.current) or ""
    )
  end

  function f.SetValues(self, v)
    self.values = v or {}
    self:Fit()
    self:SetValue(self.current)
  end

  function f.SetValue(self, key)
    self.current = key
    self.button:SetLabel(key ~= nil and tostring(self.values[key] or key) or "")
  end

  function f.GetValue(self)
    return self.current
  end

  function f.Open(self)
    local ordered = keys()
    for i, key in ipairs(ordered) do
      local item = self.list.items[i]
      if not item then
        item = CreateFrame("Button", nil, self.list)
        item:SetHeight(ROW - 2)
        item:SetPoint("LEFT", 1, 0)
        item:SetPoint("RIGHT", -1, 0)
        item.hl = S.fill(item, S.C.hover, "ARTWORK")
        item.hl:Hide()
        item.label = S.text(item, 12)
        item.label:SetPoint("LEFT", 8, 0)
        item.label:SetPoint("RIGHT", -8, 0)
        item:SetScript("OnEnter", function(me)
          me.hl:Show()
        end)
        item:SetScript("OnLeave", function(me)
          me.hl:Hide()
        end)
        item:SetScript("OnClick", function(me)
          f.list:Hide()
          f:SetValue(me.key)
          if onChange then
            onChange(me.key)
          end
        end)
        self.list.items[i] = item
      end
      item.key = key
      item.label:SetText(tostring(self.values[key]))
      local c = key == self.current and S.Tok(self, "accent") or S.Tok(self, "text")
      item.label:SetTextColor(c[1], c[2], c[3])
      item:ClearAllPoints()
      item:SetPoint("TOPLEFT", 1, -(1 + (i - 1) * (ROW - 2)))
      item:SetPoint("RIGHT", -1, 0)
      item:Show()
    end
    for i = #ordered + 1, #self.list.items do
      self.list.items[i]:Hide()
    end
    self.list:SetHeight(2 + #ordered * (ROW - 2))
    self.list:Show()
  end

  -- a click anywhere else closes the list
  f:Fit()

  f.list:SetScript("OnShow", function(list)
    list:RegisterEvent("GLOBAL_MOUSE_DOWN")
  end)
  f.list:SetScript("OnHide", function(list)
    list:UnregisterEvent("GLOBAL_MOUSE_DOWN")
  end)
  f.list:SetScript("OnEvent", function(list)
    if not (list:IsMouseOver() or f.button:IsMouseOver()) then
      list:Hide()
    end
  end)

  f.button:SetScript("OnClick", function()
    if f.list:IsShown() then
      f.list:Hide()
    else
      S.WithPalette(S.PaletteOf(f), f.Open, f) -- the list in its window's palette (the settings)
    end
  end)
  return f
end

-- Section header: the heading face 18 in the accent with a rule under it (ADR 0084: the
-- suite's board, the hub's page).
W.HEADER_H = 30
function W.Header(parent, text)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(W.HEADER_H)
  f.label = S.heading(f, 18, 18, S.C.accent)
  f.label:SetPoint("BOTTOMLEFT", 0, 6)
  f.label:SetText(text or "")
  local line = S.fill(f, S.C.line, "BORDER")
  line:ClearAllPoints()
  line:SetPoint("BOTTOMLEFT", 0, 0)
  line:SetPoint("BOTTOMRIGHT", 0, 0)
  line:SetHeight(1)
  function f.SetText(self, t)
    self.label:SetText(t)
  end
  return f
end

-- Note: dim wrapped text, e.g. "QuestieDB not installed: NPC spawns from our data only".
function W.Note(parent, text, color)
  local f = CreateFrame("Frame", nil, parent)
  f.label = S.text(f, 11, color or S.C.dim)
  f.label:SetPoint("TOPLEFT", 0, 0)
  f.label:SetPoint("RIGHT", 0, 0)
  f.label:SetWordWrap(true)
  f.label:SetText(text or "")
  function f.SetText(self, t)
    self.label:SetText(t or "")
    local lines = math.max(1, math.ceil(#(t or "") / 80))
    self:SetHeight(lines * 13 + 4)
  end
  f:SetText(text)
  return f
end

-- A colour row (R27.2): the label, a swatch that opens the game's colour picker, and a button
-- back to the theme's colour. get() -> { r, g, b } or nil (the theme's), set(colour or nil).
function W.Color(parent, label, get, set, themeColor)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(ROW)
  f.label = S.text(f, 12)
  f.label:SetPoint("LEFT", 0, 0)
  f.label:SetText(label or "")
  f.reset = S.button(f, L["Reset"], 70, 20) -- "Theme" said nothing
  f.reset:SetPoint("RIGHT", 0, 0)
  f.reset.tip = L["Back to the theme's colour."]
  f.swatch = CreateFrame("Button", nil, f)
  f.swatch:SetSize(40, 16)
  f.swatch:SetPoint("RIGHT", f.reset, "LEFT", -8, 0)
  f.swatch.edges = S.roundEdges(f.swatch, S.C.line, "radiusSmall")
  f.swatch.fill = S.fill(f.swatch, themeColor or S.C.bg)
  f.swatch.tip = L["Click to pick a colour."]
  function f.Refresh()
    local c = get()
    S.tint(f.swatch.fill, type(c) == "table" and c or themeColor or S.C.bg)
  end
  f.swatch:SetScript("OnClick", function()
    local c = get() or themeColor or S.C.bg
    local shown = B.Compat.PickColor(c[1], c[2], c[3], function(r, g, b)
      set({ r, g, b })
      f.Refresh()
    end)
    if not shown then
      B:Say(L["The game's colour picker is not available here."])
    end
  end)
  f.reset:SetScript("OnClick", function()
    set(nil)
    f.Refresh()
  end)
  for _, w in ipairs({ f.swatch, f.reset }) do
    w:HookScript("OnEnter", S.TipEnter)
    w:HookScript("OnLeave", S.TipLeave)
  end
  f.Refresh()
  return f
end

-- Text field with a hint (the kit's search box without the clear button semantics).
function W.Edit(parent, hint, onEnter)
  local box = S.search(parent, hint, true)
  box:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    if onEnter then
      onEnter(self:GetText() or "")
    end
  end)
  box:SetScript("OnTextChanged", function(self)
    local text = self:GetText() or ""
    if text == "" then
      self.hint:Show()
      self.clear:Hide()
    else
      self.hint:Hide()
      self.clear:Show()
    end
  end)
  return box
end

-- ControlBar: the toolbar line of a view (core-contracts §7b, ADR 0012). SetControls(controls) lays
-- out { kind = "button", label, onClick, tooltip, width } | { kind = "label", text, width } |
-- { kind = "select", value, options = { { key, label } }, onChange, width } from left to right;
-- widgets are pooled and reused, the ones not used stay hidden. Buttons with `align = "right"` go
-- to the right end.
function W.ControlBar(parent)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetHeight(ROW)
  bar.pools = { button = {}, label = {}, select = {} }

  local function take(kind, i)
    local pool = bar.pools[kind]
    local w = pool[i]
    if w then
      return w
    end
    if kind == "button" then
      w = S.button(bar, "", 40, ROW - 2)
      w:SetScript("OnClick", function(me)
        if me.control and me.control.onClick then
          me.control.onClick()
        end
      end)
      w:HookScript("OnEnter", function(me)
        if me.control and me.control.tooltip and GameTooltip then
          GameTooltip:SetOwner(me, "ANCHOR_BOTTOM")
          GameTooltip:AddLine(me.control.tooltip, 1, 1, 1, true)
          GameTooltip:Show()
        end
      end)
      w:HookScript("OnLeave", function()
        if GameTooltip then
          GameTooltip:Hide()
        end
      end)
    elseif kind == "label" then
      w = S.text(bar, 13)
      w:SetJustifyH("LEFT")
      w:SetWordWrap(false)
    else
      w = W.Select(bar, "", {}, function(key)
        if w.control and w.control.onChange then
          w.control.onChange(key)
        end
      end)
    end
    pool[i] = w
    return w
  end

  function bar.SetControls(self, controls)
    local used = { button = 0, label = 0, select = 0 }
    local left, right = 0, 0
    self.byId = {} -- the widget of every control with an `id`
    for _, c in ipairs(controls or {}) do
      local kind = c.kind == "select" and "select" or (c.kind == "label" and "label" or "button")
      used[kind] = used[kind] + 1
      local w = take(kind, used[kind])
      w.control = c
      if c.id then
        self.byId[c.id] = w
      end
      local width
      if kind == "button" then
        local label = c.label or ""
        if c.kind == "toggle" then -- a switch on a plain bar: its word lit while on
          label = (c.on and S.H.accent or S.H.dim) .. label .. "|r"
        end
        w.label:SetText(label)
        width = c.width or math.max(22, math.floor((w.label:GetStringWidth() or 0) + 14))
        if width <= 14 then
          width = math.max(22, #(c.label or "") * 7 + 12)
        end
        w:SetWidth(width)
      elseif kind == "label" then
        w:SetText(c.text or "")
        width = c.width or math.floor(w:GetStringWidth() or 0)
        if width <= 0 then
          width = #(c.text or "") * 7
        end
        w:SetWidth(width)
      else
        local values = {}
        for _, o in ipairs(c.options or {}) do
          values[o.key] = o.label
        end
        w:SetValues(values)
        w:SetValue(c.value)
        width = c.width or 140
        w:SetWidth(width)
        w.button:SetWidth(width)
        w.list:SetWidth(width)
      end
      w:ClearAllPoints()
      if c.align == "right" then
        w:SetPoint("RIGHT", self, "RIGHT", -right, 0)
        right = right + width + 4
      else
        w:SetPoint("LEFT", self, "LEFT", left, 0)
        left = left + width + 4
      end
      w:Show()
    end
    for kind, pool in pairs(self.pools) do
      for i = used[kind] + 1, #pool do
        pool[i]:Hide()
        pool[i].control = nil
      end
    end
    self.count = used.button + used.label + used.select
  end

  return bar
end

-- ControlBand (ADR 0084 decision 2, W9): a view's controls in a band under the head, the same
-- SetControls(controls) as the ControlBar. A label stands in small capitals at its row's start,
-- a toggle ({ kind = "toggle", on }) is a chip, filled while on, a button a tool in an outline
-- (`shape = "chip"`: a quiet chip, beside toggles) and a select a tool with a small arrow (its
-- choices in the order given); the controls with
-- `align = "right"` end at the row's right end, in their order. What does not fit starts a new
-- row. A tool may name `icon` (a pictogram before its word) and `enabled = false` (dim, no
-- click), a chip `count` (a number after its word), any of them `tipTitle` (its `tooltip` under
-- that line). opts = { search = hint (a search field first, taking the room the controls leave) }.
-- `bar.frame` (anchor its top corners; the band sets its height, 1 with nothing to show),
-- `bar.search`, `bar.byId[id]`, `bar:Layout(width)`, `bar:Height()`, `bar:SetBlock(frame, label)`
-- with `bar:SetBlockHeight(h)` (an owner's part on a row of its own under the controls: a list's
-- filter chips) and `bar.onBlockWidth(w)`.
W.BAND_TOOL = { height = 22, size = 11, pad = 8, glyph = 14 } -- a tool on a band: the low head's numbers
W.BAND_SEARCH_MIN = 150

function W.ControlBand(parent, opts)
  opts = opts or {}
  local T = W.BAND_TOOL
  local band = B.UI.Band(parent, { labels = false })
  local bar = {
    frame = band.frame,
    band = band,
    pools = { chip = {}, tool = {}, select = {} },
    byId = {},
    controls = {},
    parts = {},
    count = 0,
    height = 1,
  }
  if opts.search then
    bar.search = S.search(band.frame, opts.search)
    bar.search:SetHeight(T.height)
  end

  -- a control's `tooltip`, under its `tipTitle` when it names one
  local function tip(me)
    local c = me.control
    if not c then
      return nil
    end
    if c.tipTitle then
      return c.tipTitle, c.tooltip
    end
    return c.tooltip
  end

  local function click(me)
    local c = me.control
    if c and c.onClick and c.enabled ~= false then
      c.onClick()
    end
  end

  local function take(kind, i)
    local pool = bar.pools[kind]
    local w = pool[i]
    if w then
      return w
    end
    if kind == "chip" then
      w = S.pill(band.frame, { small = true, onClick = click })
    elseif kind == "tool" then
      w = S.action(band.frame, {
        boxed = true,
        role = "bookSans",
        height = T.height,
        size = T.size,
        pad = T.pad,
        glyph = T.glyph,
        onClick = click,
      })
    else
      w = S.action(band.frame, {
        boxed = true,
        menu = true,
        role = "bookSans",
        height = T.height,
        size = T.size,
        pad = T.pad,
        onClick = function(me)
          local c = me.control
          local m = B.UI.FilterMenuFrame()
          if m and m:IsShown() and m.anchor == me then
            m:Hide()
            return
          end
          if c then
            B.UI.FilterMenu({
              choices = c.options or {},
              active = c.value,
              all = false,
              onSelect = function(key)
                if c.onChange then
                  c.onChange(key)
                end
              end,
            }, me)
          end
        end,
      })
    end
    w.tip = tip
    pool[i] = w
    return w
  end

  local function kindOf(c)
    if c.kind == "label" then
      return "label"
    elseif c.kind == "toggle" or c.shape == "chip" then
      return "chip"
    elseif c.kind == "select" then
      return "select"
    end
    return "tool"
  end

  local function selectLabel(c)
    for _, o in ipairs(c.options or {}) do
      if o.key == c.value then
        return tostring(o.label)
      end
    end
    return tostring(c.value or "")
  end

  function bar.SetControls(self, controls)
    local used = { chip = 0, tool = 0, select = 0 }
    self.controls, self.byId, self.parts = controls or {}, {}, {}
    for i, c in ipairs(self.controls) do
      local kind = kindOf(c)
      if kind ~= "label" then
        used[kind] = used[kind] + 1
        local w = take(kind, used[kind])
        w.control = c
        local spec = w.spec
        spec.label = kind == "select" and selectLabel(c) or (c.label or "")
        spec.on = c.kind == "toggle" and c.on and true or nil
        if kind == "chip" then
          spec.count = c.count -- a number after the word (a search's hits in a list)
        elseif kind == "tool" then
          spec.icon = c.icon -- a pictogram before the word (Back, Forward)
          w:SetEnabledFlat(c.enabled ~= false) -- `enabled = false`: dim, no click
        end
        S.Draw(w)
        w:Show()
        self.parts[i] = w
        if c.id then
          self.byId[c.id] = w
        end
      elseif c.id then
        -- a label is the band's own text: its words answer for it
        self.byId[c.id] = {
          GetText = function()
            return c.text
          end,
        }
      end
    end
    for kind, pool in pairs(self.pools) do
      for i = used[kind] + 1, #pool do
        pool[i]:Hide()
        pool[i].control = nil
      end
    end
    self.count = #self.controls
    self:Layout()
  end

  -- An owner's part on a row of its own under the controls; nil takes it away.
  function bar.SetBlock(self, frame, label)
    self.block, self.blockLabel = frame, label
    if frame then
      frame:SetParent(band.frame)
    end
    self:Layout()
  end

  function bar.SetBlockHeight(self, h)
    h = h or 0
    if self.blockH ~= h then
      self.blockH = h
      self:Layout()
    end
  end

  function bar.Layout(self, width)
    if width and width > 0 then
      self.width = width
    end
    local Band = B.UI.BandClass
    band:Begin(self.width)
    local gap = Band.GAP
    -- what stands at the row's left, and what ends at its right
    local leftW, rightW, nRight = 0, 0, 0
    for i, c in ipairs(self.controls) do
      local w = self.parts[i]
      if w then
        if c.align == "right" then
          rightW = rightW + (w:GetWidth() or 0) + (nRight > 0 and gap or 0)
          nRight = nRight + 1
        else
          leftW = leftW + (w:GetWidth() or 0) + gap
        end
      elseif c.kind == "label" and (c.text or "") ~= "" then
        -- a label after the search: its words (the band's own estimate) behind a thin line
        leftW = leftW + #c.text * 6 + Band.LABEL_GAP + 2 * Band.SEP_PAD + 1 + gap
      end
    end
    local any = false
    if self.search then
      band:NewRow()
      local room = band.right - band.x - leftW - (nRight > 0 and (rightW + gap) or 0)
      local w = math.max(W.BAND_SEARCH_MIN, math.min(room, band.right - band.x))
      band:Place(self.search, w, T.height)
      self.search:SetWidth(w)
      any = true
    end
    for i, c in ipairs(self.controls) do
      local w = self.parts[i]
      if c.kind == "label" and (c.text or "") ~= "" then
        band:Group(c.text, not any)
        any = true
      elseif w and c.align ~= "right" then
        band:Place(w, w:GetWidth() or 0, T.height)
        any = true
      end
    end
    if nRight > 0 then
      band:AlignRight(rightW)
      for i, c in ipairs(self.controls) do
        local w = self.parts[i]
        if w and c.align == "right" then
          band:Place(w, w:GetWidth() or 0, T.height)
        end
      end
      any = true
    end
    if self.block and (self.blockH or 0) > 1 then
      local w = band:Block(self.block, self.blockH, self.blockLabel)
      self.block:Show()
      any = true
      if self.onBlockWidth and self.blockW ~= w then
        self.blockW = w
        self.onBlockWidth(w)
      end
    elseif self.block then
      self.block:Hide()
    end
    local h = band:End()
    if not any then
      h = 1
      band.frame:SetHeight(1)
    end
    band.ground:SetShown(any)
    band.rule:SetShown(any)
    local changed = self.height ~= h
    self.height = h
    if changed and self.onHeight then
      self.onHeight(h)
    end
    return h
  end

  function bar.Height(self)
    return self.height
  end

  band.frame:SetScript("OnSizeChanged", function(_, width)
    if width and width > 0 and width ~= bar.width then
      bar:Layout(width)
    end
  end)
  bar:Layout()
  return bar
end

-- Foot (ADR 0084, the suite's board): a window's last line on the band's ground with a rule over
-- it, 34 high: a view's summary in the small text, two lines when the window is narrow. Anchored
-- to its parent's bottom corners; `foot:SetText(text)`, `foot:GetText()`, `foot.text`. `height`:
-- a lower foot of one line (the Map's 20: the place under the mouse). `foot:Tool(spec)` adds a
-- tool at its end (words in an outline, 22 high; spec = { label, tip, onClick }), left to right
-- in the order added; `foot:Layout()` after one was shown or hidden: the shown tools end 18
-- before the foot's right edge (the window's grip), 5 apart, and the text ends before them.
W.FOOT_H, W.FOOT_PAD, W.FOOT_GRIP, W.FOOT_TOOL_GAP = 34, 12, 18, 5

function W.Foot(parent, height)
  height = height or W.FOOT_H
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(height)
  f:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
  f:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
  f.ground = S.fill(f, S.C.panel, "BACKGROUND")
  f.rule = S.fill(f, S.C.line, "BORDER")
  f.rule:ClearAllPoints()
  f.rule:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  f.rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  f.rule:SetHeight(1)
  f.text = S.text(f, 11, S.C.dim)
  f.text:SetPoint("LEFT", f, "LEFT", W.FOOT_PAD, 0)
  f.text:SetPoint("RIGHT", f, "RIGHT", -W.FOOT_GRIP, 0) -- the window's grip stands in the corner
  f.text:SetJustifyH("LEFT")
  f.text:SetWordWrap(height >= W.FOOT_H) -- a low foot is one line
  f.text:SetHeight(math.max(12, height - 8)) -- two lines of the small text; a third is cut
  function f.SetText(self, text)
    self.text:SetText(text or "")
  end
  function f.GetText(self)
    return self.text:GetText()
  end
  f.tools = {}
  function f.Layout(self)
    local anchor, point, x = self, "RIGHT", -W.FOOT_GRIP
    for i = #self.tools, 1, -1 do -- the last one added stands at the end
      local b = self.tools[i]
      b:ClearAllPoints()
      if b:IsShown() then
        b:SetPoint("RIGHT", anchor, point, x, 0)
        anchor, point, x = b, "LEFT", -W.FOOT_TOOL_GAP
      end
    end
    self.text:ClearAllPoints()
    self.text:SetPoint("LEFT", self, "LEFT", W.FOOT_PAD, 0)
    self.text:SetPoint("RIGHT", anchor, point, anchor == self and -W.FOOT_GRIP or -8, 0)
  end
  function f.Tool(self, spec)
    local T = W.BAND_TOOL
    local b = S.action(self, {
      label = spec.label,
      tip = spec.tip,
      boxed = true,
      role = "bookSans",
      height = T.height,
      size = T.size,
      pad = T.pad,
      onClick = spec.onClick,
    })
    self.tools[#self.tools + 1] = b
    self:Layout()
    return b
  end
  return f
end

-- ---------------------------------------------------------------------------------------------
-- The game's objective tracker (R6, 22.10.2026): one arbiter for every window that replaces it
-- (Quests' tracker frame; the Browser's slim mode until ADR 0056). Bastians.UI.ClaimGameTracker(key, hide)
-- records a claim per key; the game's tracker is hidden while any claim stands and shown again
-- when the last one goes. Out of combat the change applies at once (Compat.SetObjectiveTracker-
-- Shown), in combat the wish waits for PLAYER_REGEN_ENABLED (golden rule 6).
-- ---------------------------------------------------------------------------------------------

local claims = {} -- key -> true
local trackerHidden = false -- what we did last
local trackerPending = nil -- the wish kept during combat

-- The game shows its tracker again on its own (at login, on a layout change): while a claim stands
-- it goes again at once (the option was on and the tracker showed until
-- the option was switched off and on). Hooked once, when the frame exists.
local guarded = false
local function guardTracker()
  local f = rawget(_G, "ObjectiveTrackerFrame")
  if guarded or not (f and f.HookScript) then
    return
  end
  guarded = true
  f:HookScript("OnShow", function(self)
    if next(claims) == nil then
      return
    end
    if InCombatLockdown() then
      trackerHidden, trackerPending = false, true -- shown in combat: hidden after it
    else
      self:Hide()
      trackerHidden = true
    end
  end)
end

local function applyTracker()
  guardTracker()
  local hide = next(claims) ~= nil
  if hide == trackerHidden then
    trackerPending = nil
    return
  end
  if B.Compat.SetObjectiveTrackerShown(not hide) then
    trackerHidden = hide
    trackerPending = nil
  else
    trackerPending = hide
  end
end

function B.UI.ClaimGameTracker(key, hide)
  claims[key] = hide and true or nil
  applyTracker()
end

function B.UI.GameTrackerHidden()
  return trackerHidden
end

local regen = CreateFrame("Frame")
regen:RegisterEvent("PLAYER_REGEN_ENABLED")
regen:SetScript("OnEvent", function()
  if trackerPending ~= nil then
    applyTracker()
  end
end)
