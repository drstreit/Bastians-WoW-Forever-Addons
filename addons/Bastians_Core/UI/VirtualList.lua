-- UI kit, the virtual list (plan-chat-v3.md §8, ADR 0075): a long list of rows of several kinds
-- where only the rows in view have frames, pooled per kind. A kind says how its row is made and
-- filled; the fill answers the row's height, kept per item and width, so a row is measured once.
-- A list that sticks to its end (a chat) keeps the newest row in view while the player has not
-- scrolled up, and counts the rows that arrived below the view while they have.
--
--   local list = Bastians.UI.VirtualList.New(parent, {
--     kinds = { line = { make = function(parent) return frame end,
--                        fill = function(frame, item, width) return height end } },
--     gap = 2, stick = true, bottomUp = true, max = 500, onBelow = function(n) end })
--   list:SetItems({ { kind = "line", ... }, ... }); list:Append(item)
local _, ns = ...
local B = ns.B
local S = ns.Style

local VL = {}
VL.__index = VL
B.UI.VirtualList = VL

VL.OVERSCAN = 2 -- rows drawn beyond each edge of the view
VL.END_SLACK = 2 -- pixels from the end that still count as "at the end"
VL.TRIM = 50 -- a list over its `max` drops this many of its oldest rows at once
VL.BAR_ROOM = 10 -- the slim scroll bar's room at the right

-- Pure: the first and the last row a view shows; tops[i] is row i's top (0 the list's top),
-- heights[i] its height. Nil when the view shows none.
function VL.Span(tops, heights, offset, view)
  local n = #tops
  if n == 0 or not view or view <= 0 then
    return nil
  end
  local lo, hi = 1, n
  while lo < hi do -- the first row whose bottom lies below the offset
    local mid = math.floor((lo + hi) / 2)
    if tops[mid] + heights[mid] <= offset then
      lo = mid + 1
    else
      hi = mid
    end
  end
  local last = lo
  while last < n and tops[last + 1] < offset + view do
    last = last + 1
  end
  return lo, last
end

function VL.New(parent, opts)
  opts = opts or {}
  local list = setmetatable({
    opts = opts,
    kinds = opts.kinds or {},
    gap = opts.gap or 0,
    items = {},
    tops = {},
    heights = {},
    total = 0,
    pools = {}, -- [kind] = free rows
    used = {}, -- the rows in view
    measure = {}, -- [kind] = a hidden row the heights are measured on
    cache = setmetatable({}, { __mode = "k" }), -- [item] = { w, h }
    stuck = opts.stick == true,
    parent = parent,
    below = 0,
  }, VL)
  local scroll = CreateFrame("ScrollFrame", nil, parent)
  scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
  scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -VL.BAR_ROOM, 0)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)
  list.scroll, list.content = scroll, content
  list.bar = S.scrollbar(scroll, parent, function(offset)
    list:Scrolled(offset)
  end)
  scroll:SetScript("OnSizeChanged", function()
    list:Layout()
  end)
  return list
end

-- The scroll frame's size; before the client has laid it out, its parent's (as Tree does).
-- The palette the list draws in: its parent's, read each time it draws, so a window that takes a
-- preset of its own (S.SetFramePreset) is followed.
function VL:Palette()
  return S.PaletteOf(self.parent)
end

function VL:Width()
  local w = self.scroll:GetWidth()
  if not w or w <= 0 then
    w = (self.parent:GetWidth() or 0) - VL.BAR_ROOM
  end
  return math.max(0, w)
end

function VL:View()
  local h = self.scroll:GetHeight()
  if not h or h <= 0 then
    h = self.parent:GetHeight() or 0
  end
  return h
end

function VL:Offset()
  return self.scroll:GetVerticalScroll() or 0
end

-- The height of an item's row at a width: measured on the kind's hidden row once, then kept.
function VL:HeightOf(item, width)
  local c = self.cache[item]
  if c and c.w == width then
    return c.h
  end
  local kind = self.kinds[item.kind]
  if not kind then
    return 0
  end
  local m = self.measure[item.kind]
  if not m then
    m = kind.make(self.content)
    m:Hide()
    self.measure[item.kind] = m
  end
  m:SetWidth(width)
  local h = S.WithPalette(self:Palette(), kind.fill, m, item, width) or kind.height or 0
  self.cache[item] = { w = width, h = h }
  return h
end

local function sizeContent(self)
  self.content:SetSize(math.max(1, self:Width()), math.max(1, self.total))
  self.bar.SetTotal(self.total)
end

-- Every row's place again (new items, a new width), then the view.
function VL:Layout()
  local width = self:Width()
  local y, gap, n = 0, self.gap, #self.items
  if width > 0 then
    for i, item in ipairs(self.items) do
      local h = self:HeightOf(item, width)
      self.tops[i], self.heights[i] = y, h
      y = y + h + gap
    end
  end
  for i = #self.tops, n + 1, -1 do
    self.tops[i], self.heights[i] = nil, nil
  end
  self.total = (n > 0 and width > 0) and (y - gap) or 0
  sizeContent(self)
  if self.stuck then
    self:ScrollToEnd()
  else
    self:Render()
  end
end

-- The first row in view and how far the view's top lies inside it (to keep a reader's place).
function VL:TopItem()
  local first = VL.Span(self.tops, self.heights, self:Offset(), self:View())
  if not first then
    return nil
  end
  return self.items[first], self:Offset() - self.tops[first]
end

-- Replaces the items (the list keeps its own copy of the array, so the owner's array and Append
-- never add twice). A stuck list shows the end; otherwise the row at the top stays where it was.
function VL:SetItems(items)
  local anchor, delta
  if not self.stuck then
    anchor, delta = self:TopItem()
  end
  local own = {}
  for i, item in ipairs(items or {}) do
    own[i] = item
  end
  self.items = own
  self.below = 0
  self:Layout()
  if anchor then
    for i, item in ipairs(self.items) do
      if item == anchor then
        self.bar.ScrollTo(self.tops[i] + delta)
        break
      end
    end
  end
end

-- One item more at the end (a chat line): measured alone, the others keep their places.
function VL:Append(item)
  local items = self.items
  items[#items + 1] = item
  if self.opts.max and #items > self.opts.max + VL.TRIM then
    local keep = {}
    for i = VL.TRIM + 1, #items do
      keep[#keep + 1] = items[i]
    end
    self.items = keep
    self:Layout()
    return
  end
  local width, n = self:Width(), #items
  if width <= 0 then
    return
  end
  local h = self:HeightOf(item, width)
  local y = n > 1 and (self.tops[n - 1] + self.heights[n - 1] + self.gap) or 0
  self.tops[n], self.heights[n] = y, h
  self.total = y + h
  sizeContent(self)
  if self.stuck then
    self:ScrollToEnd()
  else
    self.below = self.below + 1
    if self.opts.onBelow then
      self.opts.onBelow(self.below)
    end
    self:Render()
  end
end

-- An item changed its height (a card answered, a line folded): measured again.
function VL:Invalidate(item)
  self.cache[item] = nil
  self:Layout()
end

-- The rows in view filled again (their words changed, not their heights).
function VL:Refresh()
  self:Render()
end

function VL:AtEnd()
  return self:Offset() >= self.total - self:View() - VL.END_SLACK
end

-- The player scrolled (the wheel, the thumb) or the list did: a list that sticks sticks again at
-- the end, and the count of rows below goes back to 0 there.
function VL:Scrolled()
  if self.opts.stick then
    local was = self.stuck
    self.stuck = self:AtEnd()
    if self.stuck and (not was or self.below > 0) then
      self.below = 0
      if self.opts.onBelow then
        self.opts.onBelow(0)
      end
    end
  end
  self:Render()
end

function VL:ScrollToEnd()
  self.bar.ScrollTo(math.max(0, self.total - self:View()))
end

function VL:ScrollToItem(item)
  for i, it in ipairs(self.items) do
    if it == item then
      self.bar.ScrollTo(self.tops[i])
      return true
    end
  end
  return false
end

local function release(self)
  for i = #self.used, 1, -1 do
    local row = self.used[i]
    row:Hide()
    row.item, row.index = nil, nil
    local pool = self.pools[row.vlKind] or {}
    self.pools[row.vlKind] = pool
    pool[#pool + 1] = row
    self.used[i] = nil
  end
end

local function acquire(self, kindId)
  local pool = self.pools[kindId]
  local row = pool and table.remove(pool)
  if not row then
    row = self.kinds[kindId].make(self.content)
    row.vlKind = kindId -- not `kind`: a row is its owner's frame (a card has a `kind` text)
  end
  return row
end

function VL:RenderNow()
  release(self)
  local view, offset, width = self:View(), self:Offset(), self:Width()
  local first, last = VL.Span(self.tops, self.heights, offset, view)
  if not first or width <= 0 then
    return
  end
  -- a short list that grows from the bottom (a chat) lies at the view's foot
  local base = (self.opts.bottomUp and self.total < view) and (view - self.total) or 0
  first = math.max(1, first - VL.OVERSCAN)
  last = math.min(#self.items, last + VL.OVERSCAN)
  for i = first, last do
    local item = self.items[i]
    local kind = self.kinds[item.kind]
    if kind and self.heights[i] > 0 then -- a row of no height (a hidden one) takes no frame
      local row = acquire(self, item.kind)
      row.item, row.index = item, i
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -(self.tops[i] + base))
      row:SetWidth(width)
      row:SetHeight(self.heights[i])
      kind.fill(row, item, width)
      row:Show()
      self.used[#self.used + 1] = row
    end
  end
end

function VL:Render()
  return S.WithPalette(self:Palette(), self.RenderNow, self)
end

-- The rows in view, top first (for the owner's hit tests and for tests).
function VL:Rows()
  local out = {}
  for i, row in ipairs(self.used) do
    out[i] = row
  end
  table.sort(out, function(a, b)
    return a.index < b.index
  end)
  return out
end
