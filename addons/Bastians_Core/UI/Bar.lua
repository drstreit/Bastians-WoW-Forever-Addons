-- UI kit: the one bar of a window's head (ADR 0084 decisions 2 and 3; core.md "The frame"): an
-- app's views as tabs, a search field and tools as words in an outline, laid out by Core.
local _, ns = ...
local B = ns.B
local S = ns.Style

local Window = B.UI.WindowClass
local Bar = {}
Bar.__index = Bar
B.UI.BarClass = Bar

Bar.SEARCH_MIN = 150 -- the search field's least width in the head (book-look.md section 4)
Bar.SEARCH_MAX = 230
Bar.TOOL_GAP = 8 -- between two tools
Bar.TAB_PAD = 10 -- beside a tab's word
Bar.TAB_GAP = 4 -- between two tabs
Bar.ROW_PAD = 6 -- around the tabs on a row of their own
Bar.PRIMARY_PAD = 2 -- the filled plate's words stand this much further in
Bar.TOOL_GLYPH = 16 -- a tool's pictogram

local function width(frame)
  return frame and frame:IsShown() and (frame:GetWidth() or 0) or 0
end

-- A tool of the bar from its spec (S.action in the head's numbers).
local function makeTool(bar, t)
  local H = bar.win.headSpec
  return S.action(bar.win.head, {
    icon = t.icon,
    label = t.label,
    tip = t.tip,
    menu = t.menu or nil,
    primary = t.primary or nil,
    boxed = not t.primary or nil,
    caps = (t.caps or t.primary) and true or nil,
    role = (t.caps or t.primary) and "bookCaps" or "bookSans",
    size = H.toolText,
    height = H.tool,
    glyph = Bar.TOOL_GLYPH,
    pad = H.toolPad + (t.primary and Bar.PRIMARY_PAD or 0),
    onClick = t.onClick,
  })
end

-- win:Bar(spec) -> the bar. spec = {
--   tabs = { items = { { id, label, icon, tip, disabled } }, value, onChange(id), again (a
--     click on the shown tab calls onChange too) },
--   search = { hint, plain } or { frame = an edit box of the app's own },
--   tools = { { id, label, icon, tip, primary, caps, menu, onClick(tool, button) } }, left to right,
--   wrapTools (the tools may leave a head too narrow for them), onLayout(bar) }
-- The parts: `bar.tabs` (S.segmented: SetValue, Part), `bar.search` (S.search: the app sets its
-- own scripts), `bar.tools[id]` (S.action: SetOn, SetLabel, tip; `menu` a small arrow after the
-- words, a select). `bar:AddTool(t, before)` adds one later (a part another module of the app
-- brings), before the tool `before` or last; `bar:SetTab(id, t)` changes a tab.
-- `bar:Layout()` places them: the tabs after the
-- name, the search after them, the tools before the window's own pictograms; a hidden tool
-- takes no room. A head too narrow for all gives the tabs a row of their own under it
-- (`bar.row` true), and a row too narrow for the words shows the tabs' pictograms with the
-- words in the tips; with `wrapTools` a head still too narrow for the search at its least width
-- and the tools gives the tools rows of their own under it too (`bar.toolRows`, W9: the Map at
-- its least width; without it the search narrows, as before). `bar:Room()` is
-- the height those rows take at the content's top.
function Window:Bar(spec)
  if self.headBar then
    return self.headBar
  end
  spec = spec or {}
  local H = self.headSpec
  local head = self.head
  local bar = setmetatable({ win = self, spec = spec, tools = {}, order = {} }, Bar)
  if spec.tabs then
    for _, item in ipairs(spec.tabs.items or {}) do
      item.word = item.word or item.label or ""
      item.glyph = item.glyph or item.icon
      item.label, item.icon = S.SmallCaps(item.word), nil
    end
    -- the row the tabs stand on when the head has no room for them: on the window, over the
    -- content's top, so it never scales or scrolls with it
    bar.rowFrame = CreateFrame("Frame", nil, self.frame)
    bar.rowFrame:SetHeight(H.tool)
    bar.rowFrame:Hide()
    bar.tabs = S.segmented(head, {
      items = spec.tabs.items,
      value = spec.tabs.value,
      again = spec.tabs.again,
      flat = true,
      height = H.tool,
      pad = Bar.TAB_PAD,
      gap = Bar.TAB_GAP,
      corners = "top", -- the shown tab stands on the head's rule
      onChange = function(_, id)
        if spec.tabs.onChange then
          spec.tabs.onChange(id)
        end
      end,
    })
    for _, part in ipairs(bar.tabs.parts) do
      S.SetRole(part.label, "bookCaps")
      S.setSize(part.label, H.toolText)
    end
    S.Draw(bar.tabs)
  end
  -- the rows the tools stand on when the head has no room for them (as the tabs' row)
  bar.toolFrame = CreateFrame("Frame", nil, self.frame)
  bar.toolFrame:Hide()
  bar.toolRows = 0
  for _, t in ipairs(spec.tools or {}) do
    local tool = makeTool(bar, t)
    bar.tools[t.id] = tool
    bar.order[#bar.order + 1] = tool
  end
  if spec.search then
    if spec.search.frame then
      bar.search = spec.search.frame -- the app's own box with its own scripts (the Map's)
      bar.search:SetParent(head)
    else
      bar.search = S.search(head, spec.search.hint or "", spec.search.plain)
    end
    bar.search:SetHeight(H.tool)
  end
  self.headBar = bar
  bar:Layout()
  return bar
end

-- Adds a tool after the bar was made: before the tool with the id `before`, else last.
function Bar:AddTool(t, before)
  local tool = makeTool(self, t)
  self.tools[t.id] = tool
  local at = #self.order + 1
  for i, other in ipairs(self.order) do
    if before and other == self.tools[before] then
      at = i
      break
    end
  end
  table.insert(self.order, at, tool)
  self:Layout()
  return tool
end

-- Changes a tab after the bar was made (W9: the Browser's sections follow the apps that are
-- on): t = { label, icon, tip, disabled }. `label` and `icon` stay when not named; `tip` and
-- `disabled` are set as given (nil: none). A disabled tab is dim and takes no click, its tip
-- says why. `bar:Layout()` after the last change draws them. -> false when no tab has the id.
function Bar:SetTab(id, t)
  local part = self.tabs and self.tabs:Part(id)
  if not part then
    return false
  end
  local item = part.item
  item.word = t.label or item.word
  item.glyph = t.icon or item.glyph
  item.tip = t.tip
  item.disabled = t.disabled and true or nil
  self.words = nil -- the next layout writes the tabs again
  return true
end

-- The tabs as words, or as their pictograms with the words in the tips.
function Bar:TabWords(words)
  if not self.tabs or self.words == words then
    return
  end
  self.words = words
  for _, part in ipairs(self.tabs.parts) do
    local item = part.item
    item.label = words and S.SmallCaps(item.word) or nil
    item.icon = (not words) and item.glyph or nil
    part.tip = item.tip or ((not words) and item.word or nil)
    part.tipNow = (not words) or nil -- a tab as its pictogram: its name at once
  end
  S.Draw(self.tabs)
end

-- The height the bar takes at the content's top: none while everything stands in the head;
-- else its rows (the tabs', the tools'), each a tool high with ROW_PAD around them.
function Bar:Room()
  local n = (self.row and 1 or 0) + (self.toolRows or 0)
  if n == 0 then
    return 0
  end
  return n * self.win.headSpec.tool + (n + 1) * Bar.ROW_PAD - 2
end

function Bar:Layout()
  local win, spec = self.win, self.spec
  local H, head = win.headSpec, win.head
  local headW = head:GetWidth() or 0
  local start = win:HeadStart()
  local edge, rightW = win:HeadEnd()
  local toolsW = 0
  for _, tool in ipairs(self.order) do
    if tool:IsShown() then
      toolsW = toolsW + width(tool) + (toolsW > 0 and Bar.TOOL_GAP or 0)
    end
  end
  self:TabWords(true)
  local tabsW = self.tabs and (self.tabs:GetWidth() or 0) or 0
  local searchMin = self.search and (Bar.SEARCH_MIN + H.gap) or 0
  local rest = searchMin + toolsW + (toolsW > 0 and H.gap or 0) + rightW
  local need = start + tabsW + (tabsW > 0 and H.gap or 0) + rest
  -- a head not yet measured (the first layout) counts as wide enough
  self.row = self.tabs ~= nil and headW > 0 and need > headW
  -- still too narrow with the tabs on their row: the tools on rows of their own under it
  local below = spec.wrapTools == true and toolsW > 0 and headW > 0 and (start + rest) > headW
  local firstTool
  if below then
    local frame = self.toolFrame
    local room = math.max(1, (win.content:GetWidth() or headW) - 2 * H.pad)
    local x, rows = 0, 1
    for _, tool in ipairs(self.order) do
      tool:ClearAllPoints()
      if tool:IsShown() then
        local w = width(tool)
        if x > 0 and x + w > room then
          x, rows = 0, rows + 1
        end
        tool:SetParent(frame)
        tool:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -(rows - 1) * (H.tool + Bar.ROW_PAD))
        x = x + w + Bar.TOOL_GAP
      end
    end
    self.toolRows = rows
    local top = Bar.ROW_PAD + (self.row and (H.tool + Bar.ROW_PAD) or 0)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", win.content, "TOPLEFT", H.pad, -top)
    frame:SetPoint("TOPRIGHT", win.content, "TOPRIGHT", -H.pad, -top)
    frame:SetHeight(rows * H.tool + (rows - 1) * Bar.ROW_PAD)
    frame:SetFrameLevel((win.content:GetFrameLevel() or 0) + 5)
    frame:Show()
    toolsW = 0 -- none of them in the head
  else
    self.toolRows = 0
    self.toolFrame:Hide()
    -- the tools from the right, the last one nearest the window's own pictograms
    local anchor, point, x = edge or head, edge and "LEFT" or "RIGHT", edge and -H.gap or -H.pad
    for i = #self.order, 1, -1 do
      local tool = self.order[i]
      tool:ClearAllPoints()
      if tool:IsShown() then
        tool:SetParent(head)
        tool:SetPoint("RIGHT", anchor, point, x, 0)
        anchor, point, x = tool, "LEFT", -Bar.TOOL_GAP
      end
    end
    firstTool = toolsW > 0 and anchor or nil
  end
  local left = start
  if self.tabs then
    self.tabs:ClearAllPoints()
    if self.row then
      local row = self.rowFrame
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", win.content, "TOPLEFT", H.pad, -Bar.ROW_PAD)
      row:SetPoint("TOPRIGHT", win.content, "TOPRIGHT", -H.pad, -Bar.ROW_PAD)
      row:SetFrameLevel((win.content:GetFrameLevel() or 0) + 5)
      row:Show()
      self.tabs:SetParent(row)
      self.tabs:SetPoint("LEFT", row, "LEFT", 0, 0)
      local room = (win.content:GetWidth() or 0) - 2 * H.pad
      if room > 0 and tabsW > room then
        self:TabWords(false) -- too narrow even for a row of words: the pictograms
      end
    else
      self.rowFrame:Hide()
      self.tabs:SetParent(head)
      self.tabs:SetFrameLevel((head:GetFrameLevel() or 0) + 5)
      self.tabs:SetPoint("LEFT", head, "LEFT", start, 0)
      left = start + tabsW + H.gap
    end
  end
  if self.search then
    local right = firstTool and (toolsW + H.gap) or 0
    local room = headW > 0 and (headW - left - right - rightW) or Bar.SEARCH_MAX
    self.search:ClearAllPoints()
    self.search:SetPoint("LEFT", head, "LEFT", left, 0)
    self.search:SetWidth(math.max(60, math.min(Bar.SEARCH_MAX, room)))
  end
  if spec.onLayout then
    spec.onLayout(self)
  end
end
