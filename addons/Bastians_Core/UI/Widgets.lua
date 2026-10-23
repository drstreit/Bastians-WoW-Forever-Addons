-- UI kit: flat form widgets for the settings renderer: checkbox, slider, select, header, note.
local _, ns = ...
local B = ns.B
local S = ns.Style

local W = {}
B.UI.Widgets = W

local ROW = 22

-- Checkbox: a 14 px box with an accent "x" and a label. onChange(checked) after a click.
function W.Checkbox(parent, label, onChange)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(ROW)
  b.box = CreateFrame("Frame", nil, b)
  b.box:SetSize(14, 14)
  b.box:SetPoint("LEFT", 0, 0)
  S.fill(b.box, S.C.panel)
  b.box.edges = S.border(b.box)
  b.mark = S.text(b.box, 13, S.C.accent)
  b.mark:SetPoint("CENTER", 0, 0)
  b.mark:SetJustifyH("CENTER")
  b.label = S.text(b, 12)
  b.label:SetPoint("LEFT", b.box, "RIGHT", 6, 0)
  b.label:SetPoint("RIGHT", 0, 0)
  b.label:SetText(label or "")
  b.checked = false
  function b.SetChecked(self, on)
    self.checked = on and true or false
    self.mark:SetText(self.checked and "x" or "")
  end
  function b.GetChecked(self)
    return self.checked
  end
  b:SetScript("OnClick", function(self)
    self:SetChecked(not self.checked)
    if onChange then
      onChange(self.checked)
    end
  end)
  b:SetScript("OnEnter", function(self)
    S.setEdges(self.box.edges, S.C.accent, 0.8)
  end)
  b:SetScript("OnLeave", function(self)
    S.setEdges(self.box.edges, S.C.line)
  end)
  return b
end

-- Slider: label left, value right, a flat track. onChange(value) when the player moves it.
function W.Slider(parent, label, min, max, step, onChange)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(ROW + 14)
  f.label = S.text(f, 12)
  f.label:SetPoint("TOPLEFT", 0, 0)
  f.label:SetText(label or "")
  f.value = S.text(f, 12, S.C.dim)
  f.value:SetPoint("TOPRIGHT", 0, 0)
  f.value:SetJustifyH("RIGHT")
  local slider = CreateFrame("Slider", nil, f)
  slider:SetPoint("BOTTOMLEFT", 0, 2)
  slider:SetPoint("BOTTOMRIGHT", 0, 2)
  slider:SetHeight(10)
  slider:SetOrientation("HORIZONTAL")
  slider:SetMinMaxValues(min, max)
  slider:SetValueStep(step or 1)
  slider:SetObeyStepOnDrag(true)
  S.fill(slider, S.C.track)
  slider:SetThumbTexture(S.WHITE)
  local thumb = slider:GetThumbTexture()
  if thumb then
    thumb:SetSize(8, 10)
    thumb:SetVertexColor(S.C.accent[1], S.C.accent[2], S.C.accent[3], 1)
  end
  f.slider = slider
  f.step = step or 1
  local function fmt(v)
    if f.step >= 1 then
      return tostring(math.floor(v + 0.5))
    end
    return string.format("%.2f", v)
  end
  function f.SetValue(self, v, silent)
    self.silent = silent
    slider:SetValue(v)
    self.value:SetText(fmt(v))
    self.silent = nil
  end
  function f.GetValue()
    return slider:GetValue()
  end
  slider:SetScript("OnValueChanged", function(_, v, user)
    f.value:SetText(fmt(v))
    if onChange and not f.silent and user ~= false then
      onChange(v)
    end
  end)
  return f
end

-- Select: a button showing the current label; click opens a flat list below. values = { key = label }.
-- onChange(key) when the player picks one. SetValues(values) replaces the choices.
function W.Select(parent, label, values, onChange)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(ROW)
  f.label = S.text(f, 12)
  f.label:SetPoint("LEFT", 0, 0)
  f.label:SetText(label or "")
  f.button = S.button(f, "", 160, 20)
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

  function f.SetValues(self, v)
    self.values = v or {}
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
      local c = key == self.current and S.C.accent or S.C.text
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
      f:Open()
    end
  end)
  return f
end

-- Section header: accent text with a line under it.
function W.Header(parent, text)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(ROW)
  f.label = S.text(f, 13, S.C.accent)
  f.label:SetPoint("BOTTOMLEFT", 0, 4)
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

-- Text field with a hint (the kit's search box without the clear button semantics).
function W.Edit(parent, hint, onEnter)
  local box = S.search(parent, hint)
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
        w.label:SetText(c.label or "")
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

-- ---------------------------------------------------------------------------------------------
-- The game's objective tracker (R6, 22.10.2026): one arbiter for every window that replaces it
-- (the Companion in slim mode, Quests' tracker frame). Bastians.UI.ClaimGameTracker(key, hide)
-- records a claim per key; the game's tracker is hidden while any claim stands and shown again
-- when the last one goes. Out of combat the change applies at once (Compat.SetObjectiveTracker-
-- Shown), in combat the wish waits for PLAYER_REGEN_ENABLED (golden rule 6).
-- ---------------------------------------------------------------------------------------------

local claims = {} -- key -> true
local trackerHidden = false -- what we did last
local trackerPending = nil -- the wish kept during combat

local function applyTracker()
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
