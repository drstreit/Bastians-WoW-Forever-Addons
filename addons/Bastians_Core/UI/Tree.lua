-- UI kit: Bastians.UI.Tree(parent, opts): the shared tree renderer of the row format (core-contracts §7).
-- Virtual rows: only the visible ones have frames, pooled and re-used while scrolling. Folding, the
-- filter bar, search with highlight that keeps colour escapes, a value column and a selection mark.
-- Ported from AHSyncGuide Core.lua (flatten, highlight, rows, chips) and made data-driven.
local _, ns = ...
local B = ns.B
local S = ns.Style
local L = ns.L

local ROW_H, INDENT, VALUE_W, OVERSCAN = 18, 14, 70, 2
local FOLD_W = 18 -- the fold marker's width
local DOUBLE_H = 34 -- a two-line row (opts.twoLine, rows with `meta`): name, then the meta line
local FLAT_INDENT = 8 -- children inside a dossier block (flat mode): a step, no marker
local WORTH_W = 170 -- the value column may grow to this for a worth line (C3)
local WORTH_LINE_H = 12 -- a line of the worth under a two-line row
local WORTH_LINES = 2 -- at most this many
local RULE_H = 9 -- a "rule" row: one pixel line with air around it
local ICON_W, ICON_GAP = 14, 2 -- the row action icons
local NOTE_W = 48 -- the note column of a table (ADR 0018 D: the chance, the stack)

local Tree = {}
Tree.__index = Tree

-- ---------------------------------------------------------------------------------------------
-- Pure helpers (exported for tests through Bastians.UI.TreeUtil)
-- ---------------------------------------------------------------------------------------------

local Util = {}
B.UI.TreeUtil = Util

-- Text with the search term in the accent colour. Escape sequences (|c, |r, |T..|t, |H..|h..|h) pass
-- through untouched; after a highlight the colour that was active comes back.
function Util.highlight(text, query)
  if not (text and query and query ~= "") then
    return text
  end
  local out, pos, n, color = {}, 1, #text, nil
  local acc = S.accent()
  local lowQuery = string.lower(query)
  local function plain(s)
    if s == "" then
      return
    end
    local low, i, res = string.lower(s), 1, {}
    while true do
      local a, b = string.find(low, lowQuery, i, true)
      if not a then
        res[#res + 1] = string.sub(s, i)
        break
      end
      res[#res + 1] = string.sub(s, i, a - 1)
      res[#res + 1] = acc .. string.sub(s, a, b) .. "|r" .. (color or "")
      i = b + 1
    end
    out[#out + 1] = table.concat(res)
  end
  while pos <= n do
    local s = string.find(text, "|", pos, true)
    if not s then
      plain(string.sub(text, pos))
      break
    end
    plain(string.sub(text, pos, s - 1))
    local c = string.sub(text, s + 1, s + 1)
    local e
    if c == "c" then
      e = s + 9
      color = string.sub(text, s, e)
    elseif c == "r" then
      e = s + 1
      color = nil
    elseif c == "T" then
      e = string.find(text, "|t", s + 2, true)
      e = e and e + 1 or n
    elseif c == "H" then
      local h1 = string.find(text, "|h", s + 2, true)
      local h2 = h1 and string.find(text, "|h", h1 + 2, true)
      e = h2 and h2 + 1 or n
    else
      e = s + 1
    end
    out[#out + 1] = string.sub(text, s, e)
    pos = e + 1
  end
  return table.concat(out)
end

-- Lower-cased plain text of a row for searching: escapes removed.
function Util.searchText(row)
  if row.search then
    return row.search
  end
  local text = tostring(row.text or "")
  text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
  text = string.gsub(text, "|r", "")
  text = string.gsub(text, "|T[^|]*|t", "")
  text = string.gsub(text, "|H[^|]*|h", "")
  text = string.gsub(text, "|h", "")
  row.search = string.lower(text)
  return row.search
end

-- Rows to draw. While searching, folds are ignored: a row that matches brings its whole branch,
-- otherwise only the matching descendants and the way to them. `expanded(row)` decides folds.
function Util.flatten(rows, query, expanded)
  local out = {}
  local function all(list, depth)
    for _, r in ipairs(list or {}) do
      r.depth = depth
      r.hasChildren = r.children ~= nil and #r.children > 0
      out[#out + 1] = r
      all(r.children, depth + 1)
    end
  end
  local function walk(list, depth, parentID)
    for i, r in ipairs(list or {}) do
      r.id = r.id or ((parentID or "") .. "/" .. tostring(r.ref or r.text or i))
      r.hasChildren = r.children ~= nil and #r.children > 0
      if query and query ~= "" then
        if string.find(Util.searchText(r), query, 1, true) then
          r.depth = depth
          out[#out + 1] = r
          all(r.children, depth + 1)
        elseif r.hasChildren then
          local mark = #out
          r.depth = depth
          out[#out + 1] = r
          walk(r.children, depth + 1, r.id)
          if #out == mark + 1 then
            out[#out] = nil -- nothing below matched
          end
        end
      else
        r.depth = depth
        out[#out + 1] = r
        if r.hasChildren and expanded(r) then
          walk(r.children, depth + 1, r.id)
        end
      end
    end
  end
  walk(rows, 0, nil)
  return out
end

-- Row action icons (ADR 0013 C): up to four small icons at the right of a row with a ref, shown on
-- hover and always on the focused row, drawn from the registered actions in this order: locate
-- (map.show), route (route.to), play or stop (quests.voice, only where it has a line), open
-- (browser.open). An app that is not installed simply contributes no icon.
Tree.ROW_ACTIONS = { "map.show", "route.to", "quests.voice", "browser.open", "quests.hide" }

-- How many row actions are registered now: the space kept free at the right of every ref row.
function Util.actionSlots()
  local n = 0
  for _, id in ipairs(Tree.ROW_ACTIONS) do
    if B:GetAction(id) then
      n = n + 1
    end
  end
  return n
end

-- The row actions that apply to ref now, in slot order. `when` is evaluated here, on hover or for
-- the one focused row, never for every row drawn (core-contracts §5).
function Util.rowActions(ref, ctx)
  local out = {}
  local all = B:GetActions(ref, ctx)
  for _, id in ipairs(Tree.ROW_ACTIONS) do
    for _, def in ipairs(all) do
      if def.id == id then
        out[#out + 1] = def
        break
      end
    end
  end
  return out
end

-- The card of an entity as data (ADR 0013 B), for every host that shows one (the Browser's page
-- header, the map's context strip): icon, name, the type badge, the summary (zone, level), the
-- status words (the first row of the section marked `card`) and the actions that apply now with
-- their short labels (`short`; `activeShort` while a toggle such as the voice line is on).
function B.UI.Card(ref, ctx, sections)
  local e = B:Entity(ref)
  local typ = B.Entity.Parse(ref)
  local card = {
    ref = ref,
    name = e:Name() or ref,
    icon = e:Icon() or B.UI.IconTexture(typ) or B.UI.IconTexture("other"),
    typeLabel = L[typ or "entity"],
    summary = e:Summary(),
    distance = B.Coords.DistanceTo(ref), -- yards to the nearest known place, nil when unknown (C1)
    worth = e:Worth(), -- { text, copper, xp } from the app that knows, nil without one (C3)
    actions = {},
  }
  sections = sections or B:GetDetailSections(ref)
  if e:Name() == nil and #sections == 0 then -- an id the packs do not know: say so on the band
    card.summary = L["No data for this entity. Is Bastian's Data installed and loaded?"]
  end
  for _, s in ipairs(sections) do
    if s.def.card and s.rows[1] then
      card.status = s.rows[1].text
      break
    end
  end
  ctx = ctx or { source = "card" }
  for _, def in ipairs(B:GetActions(ref, ctx)) do
    local active = def.active and def.active(ref) or false
    card.actions[#card.actions + 1] = {
      id = def.id,
      label = (active and def.activeShort) or def.short or def.label,
      tip = (def.short or def.activeShort) and def.label or nil, -- the full words after the delay
      icon = def.icon,
      active = active,
      enabled = B:ActionEnabled(def, ref, ctx), -- false: the host draws the button greyed
    }
  end
  return card
end

-- The worth line of a row (C3): the entity's worth where the row has no value of its own, or nil.
-- `worthOn` false (the host's setting) shows none.
function Util.worthText(row, worthOn)
  if worthOn == false or row.value ~= nil or not row.ref or row.worth == false then
    return nil
  end
  local worth = B:Entity(row.ref):Worth()
  return worth and worth.text or nil
end

-- How many lines (1 or 2) a worth text takes under a two-line row of `width` px.
function Util.worthLines(text, width)
  local plain = string.gsub(string.gsub(text or "", "|c%x%x%x%x%x%x%x%x", ""), "|r", "")
  local chars = math.max(20, math.floor((width - 30) / 5.5))
  return math.min(WORTH_LINES, math.max(1, math.ceil(#plain / chars)))
end

-- Height of a row: paragraphs ("para") wrap, a rule (a horizontal divider, "rule") is thin,
-- everything else is one line. A two-line row with a worth gets one or two more lines for it
--.
function Util.rowHeight(row, width, twoLine, worthOn)
  if row.height then
    return row.height
  end
  if row.kind == "rule" then
    return RULE_H
  end
  if twoLine and row.meta then
    local worth = Util.worthText(row, worthOn)
    if worth then
      return DOUBLE_H + Util.worthLines(worth, width) * WORTH_LINE_H + 2
    end
    return DOUBLE_H
  end
  if row.kind == "para" then
    local chars = math.max(20, math.floor((width - 60) / 6))
    local lines = math.max(1, math.ceil(#(row.text or "") / chars))
    return lines * 13 + 6
  end
  return ROW_H
end

-- ---------------------------------------------------------------------------------------------
-- The tree widget
-- ---------------------------------------------------------------------------------------------

-- opts: { db (table; collapsed[id] is stored here), onClick(row, button, tree), tooltip(tt, row),
--         onSelect(row), ctx (action context, default { source = "tree" }), chips = true,
--         onRender(tree) (after every layout; `tree.pool[1..tree.visibleCount]` are the row frames),
--         flat = true (C1, the rows inside a dossier block: no fold markers, every branch open, a
--         small indent for children, no scroll bar and no mouse wheel of its own, so the wheel
--         reaches the dossier's scroll),
--         twoLine = true (R2, 22.10.2026: a row with `meta` takes two lines, the name and its icons
--         on the first, the meta text and the value on the second, a thin divider below; the
--         row's worth on one or two more lines under them, 23.10.2026),
--         worth = false | function() -> bool (no worth on the rows),
--         onHover(row, entering) (ADR 0018: the mouse entered or left a row; the host's preview),
--         table = true (ADR 0018 D, a dossier block's small table: icon, name, the note as a column
--         left of the value, no action icons; set per block by the Dossier) }
-- Rows may carry `rightPad` (px kept free on the right, for an owner's own widget placed in onRender).
function B.UI.Tree(parent, opts)
  opts = opts or {}
  local tree = setmetatable({
    parent = parent,
    opts = opts,
    db = opts.db or {},
    rows = {},
    flat = {},
    heights = {},
    offsets = {},
    pool = {},
    query = "",
    selectedID = nil,
    ctx = opts.ctx or { source = "tree" },
  }, Tree)
  tree.db.collapsed = tree.db.collapsed or {}

  local chips = CreateFrame("Frame", nil, parent)
  chips:SetPoint("TOPLEFT", 0, 0)
  chips:SetPoint("TOPRIGHT", -14, 0)
  chips:SetHeight(1)
  tree.chips = chips -- the filter bar's place (SetFilters)

  local scroll = CreateFrame("ScrollFrame", nil, parent)
  scroll:SetPoint("TOPLEFT", chips, "BOTTOMLEFT", 0, -2)
  scroll:SetPoint("BOTTOMRIGHT", -14, 0)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)
  tree.scroll, tree.content = scroll, content
  tree.bar = S.scrollbar(scroll, parent, function()
    tree:Render()
  end)
  scroll:SetScript("OnSizeChanged", function()
    tree:Render()
  end)
  if opts.flat then
    tree.bar:Hide()
    scroll:EnableMouseWheel(false)
    scroll:SetScript("OnMouseWheel", nil)
    chips:Hide()
  end
  return tree
end

function Tree:Expanded(row)
  if self.opts.flat then
    return true
  end
  local c = self.db.collapsed[row.id]
  if c ~= nil then
    return not c
  end
  if row.collapsed ~= nil then
    return not row.collapsed
  end
  return true
end

function Tree:ToggleFold(row)
  self.db.collapsed[row.id] = self:Expanded(row) or nil
  if self.db.collapsed[row.id] == nil and row.collapsed then
    self.db.collapsed[row.id] = false -- the row folds by default, so "open" must be stored
  end
  self:Refresh()
end

function Tree:SetRows(rows)
  self.rows = rows or {}
  self:Refresh()
end

function Tree:SetQuery(query)
  self.query = string.lower(string.gsub(tostring(query or ""), "^%s*(.-)%s*$", "%1"))
  self:Refresh()
end

function Tree:Select(row)
  self.selectedID = row and row.id or nil
  self.selected = row
  if self.opts.onSelect then
    self.opts.onSelect(row)
  end
  self:Render()
end

function Tree:GetSelected()
  return self.selected
end

-- Re-flatten and lay out: called when rows, folds or the query change.
function Tree:Refresh()
  local width = self:Width()
  self.flat = Util.flatten(self.rows, self.query, function(r)
    return self:Expanded(r)
  end)
  local total = 0
  local indent = self.opts.flat and FLAT_INDENT or INDENT
  for i, row in ipairs(self.flat) do
    self.offsets[i] = total
    local h = Util.rowHeight(row, width - (row.depth or 0) * indent, self.opts.twoLine, self:WorthOn())
    self.heights[i] = h
    total = total + h
  end
  for i = #self.flat + 1, #self.heights do
    self.heights[i], self.offsets[i] = nil, nil
  end
  self.total = total
  self.content:SetSize(math.max(1, width), math.max(1, total))
  self.bar.SetTotal(total)
  self:Render()
end

-- Whether rows show the worth of their entity (C3): `opts.worth` false or a function returning
-- false hides it.
function Tree:WorthOn()
  local w = self.opts.worth
  if type(w) == "function" then
    w = w()
  end
  return w ~= false
end

function Tree:Width()
  local w = self.scroll:GetWidth()
  if not w or w <= 0 then
    w = (self.parent:GetWidth() or 400) - 14
  end
  return w
end

-- First flat index whose bottom edge is below `offset` (binary search over the prefix sums).
function Tree:FirstVisible(offset)
  local lo, hi = 1, #self.flat
  while lo < hi do
    local mid = math.floor((lo + hi) / 2)
    if self.offsets[mid] + self.heights[mid] <= offset then
      lo = mid + 1
    else
      hi = mid
    end
  end
  return lo
end

local function showTooltip(tree, frame)
  local row = frame.row
  if not row or not GameTooltip then
    return
  end
  GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
  if row.tooltip then
    row.tooltip(GameTooltip, row)
  elseif tree.opts.tooltip then
    tree.opts.tooltip(GameTooltip, row)
  elseif row.ref then
    local e = B:Entity(row.ref)
    GameTooltip:AddLine(e:Name() or row.text or row.ref, 1, 1, 1)
    local summary = e:Summary()
    if summary then
      S.TipLine(GameTooltip, summary, "tipDim")
    end
  elseif row.hasChildren then
    S.TipLine(GameTooltip, L["Click: fold or unfold"], "tipDim")
  else
    return
  end
  GameTooltip:Show()
end

-- Default click: a custom handler, else the primary action for a ref (right click: the entity menu),
-- else fold. `when` is evaluated here, at click time (core-contracts §5).
local function rowClick(tree, frame, button)
  local row = frame.row
  if not row then
    return
  end
  tree:Select(row)
  if tree.opts.onClick then
    tree.opts.onClick(row, button, tree)
    return
  end
  if row.onClick then
    row.onClick(row, button)
  elseif row.ref and button == "RightButton" and B.UI.EntityMenu then
    B.UI.EntityMenu(row.ref, frame, tree.ctx)
  elseif row.group and row.hasChildren then
    tree:ToggleFold(row) -- a group header folds on click, whatever its ref offers
  elseif row.ref and B:GetPrimaryAction(row.ref, tree.ctx) then
    B:RunAction(B:GetPrimaryAction(row.ref, tree.ctx).id, row.ref, tree.ctx)
  elseif row.hasChildren then
    tree:ToggleFold(row)
  end
end

local function hideIcons(frame)
  for _, b in ipairs(frame.icons) do
    b:Hide()
  end
  frame.iconCount = 0
end

-- The icons of the row's ref, placed from `frame.iconRight` leftwards; the one that is active (a
-- line playing) is tinted green. Returns how many are shown.
local function showIcons(tree, frame)
  local row = frame.row
  if not (row and row.ref) or tree.opts.table then -- a table row carries no action icons (ADR 0018 D)
    hideIcons(frame)
    return 0
  end
  local actions = Util.rowActions(row.ref, tree.ctx)
  local x = frame.iconRight or 6
  for i, def in ipairs(actions) do
    local b = frame.icons[i]
    if not b then
      b = CreateFrame("Button", nil, frame)
      b:SetSize(ICON_W, ICON_W)
      b.tex = b:CreateTexture(nil, "OVERLAY")
      b.tex:SetAllPoints()
      b:SetScript("OnClick", function(self)
        local r = frame.row
        if r and r.ref and self.action and not self.disabled then
          B:RunAction(self.action.id, r.ref, tree.ctx)
        end
      end)
      b.tip = function(self) -- the action's label after the hover delay
        return self.action and self.action.label or nil
      end
      b:SetScript("OnEnter", function(self)
        frame.hl:Show()
        S.TipEnter(self)
      end)
      b:SetScript("OnLeave", function(self)
        S.TipLeave(self)
        if not frame:IsMouseOver() then
          frame.hl:Hide()
          local r = frame.row
          if not (tree.opts.iconsAlways or (r and r.ref and r.ref == B:Focused())) then
            hideIcons(frame)
          end
        end
      end)
      frame.icons[i] = b
    end
    b.action = def
    b.tex:SetTexture(def.icon or B.UI.IconTexture("other"))
    b.disabled = not B:ActionEnabled(def, row.ref, tree.ctx)
    if b.disabled then
      S.tint(b.tex, S.C.dim, 0.4) -- greyed: listed, not runnable now
    elseif def.active and def.active(row.ref) then
      -- the same icon in green while its state is on: a hidden quest, a tracked quest, a line
      -- playing
      S.tint(b.tex, S.C.on)
    else
      S.untint(b.tex)
    end
    b:ClearAllPoints()
    -- on a two-line row the icons sit on the first line
    b:SetPoint("RIGHT", frame, "RIGHT", -x, frame.twoLine and (DOUBLE_H - ROW_H) / 2 or 0)
    b:Show()
    x = x + ICON_W + ICON_GAP
  end
  for i = #actions + 1, #frame.icons do
    frame.icons[i]:Hide()
  end
  frame.iconCount = #actions
  return #actions
end
Tree.ShowIcons = showIcons

local function makeRow(tree)
  local content = tree.content
  local frame = CreateFrame("Button", nil, content)
  frame:SetHeight(ROW_H)
  frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  frame.icons = {}
  frame.iconCount = 0
  frame.sec = S.fill(frame, S.C.header, "BACKGROUND")
  frame.sec:Hide()
  frame.rule = frame:CreateTexture(nil, "ARTWORK")
  frame.rule:SetTexture(S.WHITE)
  S.tint(frame.rule, S.C.rule)
  frame.rule:SetPoint("LEFT", 12, 0)
  frame.rule:SetPoint("RIGHT", -12, 0)
  frame.rule:SetHeight(1)
  frame.rule:Hide()
  frame.sel = S.fill(frame, S.C.accent, "BACKGROUND")
  frame.sel:SetAlpha(0.14)
  frame.sel:Hide()
  frame.hl = S.fill(frame, S.C.hover, "ARTWORK")
  frame.hl:Hide()
  frame.bar = S.fill(frame, S.C.accent, "ARTWORK")
  frame.bar:ClearAllPoints()
  frame.bar:SetPoint("TOPLEFT", 0, 0)
  frame.bar:SetPoint("BOTTOMLEFT", 0, 0)
  frame.bar:SetWidth(2)
  frame.bar:Hide()
  -- the fold marker: 18 px wide and 15 pt, so a group header reads as foldable
  frame.fold = CreateFrame("Button", nil, frame)
  frame.fold:SetSize(FOLD_W, ROW_H)
  frame.fold:SetPoint("TOPLEFT", 0, 0)
  frame.fold.label = S.text(frame.fold, 15, S.C.dim)
  frame.fold.label:SetPoint("CENTER")
  frame.fold:SetScript("OnClick", function(self)
    local row = self:GetParent().row
    if row and row.hasChildren and tree.query == "" then
      tree:ToggleFold(row)
    end
  end)
  frame.icon = frame:CreateTexture(nil, "ARTWORK")
  frame.icon:SetSize(12, 12)
  frame.icon:SetPoint("LEFT", 15, 0)
  frame.icon:Hide()
  frame.text = S.text(frame, 12)
  frame.text:SetPoint("TOPLEFT", 15, -3)
  frame.text:SetPoint("BOTTOMRIGHT", -38, 2)
  frame.text:SetWordWrap(false)
  frame.text:SetJustifyV("MIDDLE")
  frame.value = S.text(frame, 12)
  frame.value:SetWidth(VALUE_W)
  frame.value:SetJustifyH("RIGHT")
  frame.value:SetWordWrap(false) -- cut with an ellipsis, never over the rows above and below
  frame.value:Hide()
  frame.worth = S.text(frame, 11) -- the worth under a two-line row, one or two lines
  frame.worth:SetJustifyH("LEFT")
  frame.worth:SetJustifyV("TOP")
  frame.worth:SetWordWrap(true)
  frame.worth:Hide()
  frame.note = S.text(frame, 10, S.C.dim)
  frame.note:SetPoint("RIGHT", -6, 0)
  frame.note:Hide()
  frame.meta = S.text(frame, 11, S.C.dim) -- the second line of a two-line row
  frame.meta:SetWordWrap(false)
  frame.meta:Hide()
  frame.div = frame:CreateTexture(nil, "ARTWORK") -- the thin divider under a two-line row
  frame.div:SetTexture(S.WHITE)
  S.tint(frame.div, S.C.divider)
  frame.div:SetPoint("BOTTOMLEFT", 0, 0)
  frame.div:SetPoint("BOTTOMRIGHT", 0, 0)
  frame.div:SetHeight(1)
  frame.div:Hide()
  frame.action = S.button(frame, "", 22, ROW_H - 2)
  frame.action:SetPoint("RIGHT", -3, 0)
  frame.action.label:SetTextColor(S.C.accent[1], S.C.accent[2], S.C.accent[3])
  frame.action:Hide()
  frame.action:SetScript("OnClick", function(self)
    local row = self:GetParent().row
    if row and row.button and row.button.onClick then
      row.button.onClick(row)
    end
  end)
  frame:SetScript("OnClick", function(self, button)
    rowClick(tree, self, button)
  end)
  frame:SetScript("OnEnter", function(self)
    self.hl:Show()
    self.bar:Show()
    showIcons(tree, self)
    showTooltip(tree, self)
    if tree.opts.onHover then
      tree.opts.onHover(self.row, true) -- the host's preview (ADR 0018 C)
    end
  end)
  frame:SetScript("OnLeave", function(self)
    if GameTooltip then
      GameTooltip:Hide()
    end
    if self:IsMouseOver() then
      return -- the mouse went onto one of the row's icons
    end
    if tree.opts.onHover then
      tree.opts.onHover(self.row, false)
    end
    self.hl:Hide()
    if not (self.row and self.row.id == tree.selectedID) then
      self.bar:Hide()
    end
    -- the icons stay on a tree that shows them always (the Chain rows lost
    -- theirs after one hover) and on the focused row
    if not (tree.opts.iconsAlways or (self.row and self.row.ref and self.row.ref == B:Focused())) then
      hideIcons(self)
    end
  end)
  return frame
end

-- Lay the visible rows out on pooled frames (the hot path: no tables are created here).
function Tree:Render()
  local width = self:Width()
  local view = self.scroll:GetHeight() or 0
  local offset = self.scroll:GetVerticalScroll() or 0
  local flat, pool = self.flat, self.pool
  local n = #flat
  local used = 0
  if n > 0 and view > 0 then
    local first = math.max(1, self:FirstVisible(offset) - OVERSCAN)
    local searching = self.query ~= ""
    local tableMode = self.opts.table == true
    local slots = tableMode and 0 or Util.actionSlots() * (ICON_W + ICON_GAP)
    local focused = B:Focused()
    local flatMode = self.opts.flat
    local indentStep = flatMode and FLAT_INDENT or INDENT
    local left = flatMode and 3 or FOLD_W + 1 -- flat rows need no room for the fold marker
    local i = first
    while i <= n and self.offsets[i] < offset + view + OVERSCAN * ROW_H do
      local row = flat[i]
      used = used + 1
      local frame = pool[used]
      if not frame then
        frame = makeRow(self)
        pool[used] = frame
      end
      local indent = (row.depth or 0) * indentStep
      frame.row = row
      frame:ClearAllPoints()
      frame:SetPoint("TOPLEFT", self.content, "TOPLEFT", indent, -self.offsets[i])
      frame:SetWidth(width - indent)
      frame:SetHeight(self.heights[i])
      local two = self.opts.twoLine == true and row.meta ~= nil
      frame.twoLine = two
      frame.text:SetWordWrap(row.kind == "para")
      frame.text:SetJustifyV(row.kind == "para" and "TOP" or "MIDDLE")
      -- any text that is not a string is shown as one: a table as text stopped the whole tree at
      -- that row in game (a quest's flags list, 22.10.2026)
      local text = row.text
      if text ~= nil and type(text) ~= "string" then
        text = tostring(text)
      end
      -- a row tag (R3, core-contracts §5): "(hidden)" after the name, the row dimmed
      local tag = row.ref and B:RowTag(row.ref) or nil
      local tagText = tag and (S.H.muted .. "  (" .. tag .. ")|r") or ""
      frame.text:SetAlpha(tag and 0.55 or 1)
      text = (text or "") .. tagText
      frame.text:SetText(searching and Util.highlight(text, self.query) or text)
      if row.color then
        frame.text:SetTextColor(row.color[1], row.color[2], row.color[3], row.color[4] or 1)
      else
        frame.text:SetTextColor(S.C.text[1], S.C.text[2], S.C.text[3], 1)
      end
      local textLeft = left
      if row.icon then
        B.UI.PaintIcon(frame.icon, row.icon)
        frame.icon:ClearAllPoints()
        frame.icon:SetPoint("LEFT", left, 0)
        frame.icon:Show()
        textLeft = left + 15
      else
        frame.icon:Hide()
      end
      local noteW = (row.note and not tableMode) and 44 or 0 -- a table's note is a column, below
      local right = 6 + (row.button and 28 or 0) + noteW + (row.rightPad or 0)
      if row.ref and slots > 0 then
        frame.iconRight = right -- the icons sit here, right of the value; shown on hover
        right = right + slots
      end
      local valueText = B.UI.FormatValue(row.value, row.valueKind)
      local valueW = VALUE_W
      local worthLine -- a two-line row's worth goes on its own lines under the meta
      if valueText then
        frame.value:SetTextColor(S.C.text[1], S.C.text[2], S.C.text[3], 1)
      else
        -- the worth of the row's entity in gold (C3), where the row has no value of its own;
        -- cached on the facade, so this costs a lookup per visible row
        local worth = Util.worthText(row, self:WorthOn())
        if worth and two then
          worthLine = worth
        elseif worth then
          valueText = worth
          S.ink(frame.value, S.C.gold)
          frame.value:SetText(valueText)
          -- never more than a third of the row, cut with an ellipsis (
          -- and Forever 23.10.2026: a long worth wrapped over the icons and the next row)
          local cap = math.max(VALUE_W, math.floor(width / 3))
          valueW = math.min(WORTH_W, cap, math.max(VALUE_W, (frame.value:GetStringWidth() or 0) + 4))
        end
      end
      if worthLine then
        frame.worth:SetText(worthLine)
        S.ink(frame.worth, S.C.gold)
        frame.worth:ClearAllPoints()
        frame.worth:SetPoint("TOPLEFT", frame, "TOPLEFT", textLeft, -(2 * ROW_H - 3))
        frame.worth:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 3)
        frame.worth:Show()
      else
        frame.worth:Hide()
      end
      local metaRight = 6
      if valueText then
        frame.value:SetText(valueText)
        frame.value:SetWidth(valueW)
        frame.value:ClearAllPoints()
        if two then
          -- the value sits on the second line, right; the first line keeps the whole width
          frame.value:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 3)
          metaRight = valueW + 12
        else
          frame.value:SetPoint("RIGHT", frame, "RIGHT", -right, 0)
          right = right + valueW + 6
        end
        frame.value:Show()
      else
        frame.value:Hide()
      end
      if row.note then
        frame.note:SetText(L[row.note])
        frame.note:ClearAllPoints()
        if tableMode and not two then
          -- the table's middle column: right-aligned against the value (ADR 0018 D)
          frame.note:SetWidth(NOTE_W)
          frame.note:SetJustifyH("RIGHT")
          frame.note:SetPoint("RIGHT", frame, "RIGHT", -right, 0)
          right = right + NOTE_W + 6
        else
          frame.note:SetWidth(0)
          frame.note:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
        end
        frame.note:Show()
      else
        frame.note:Hide()
      end
      frame.text:ClearAllPoints()
      if two then
        -- line one: the name (row.title when the one-line text carries the meta too); line two:
        -- the meta text in dim, the value right of it; a divider below
        local title = (row.title and (row.title .. tagText)) or text
        frame.text:SetText(searching and Util.highlight(title or "", self.query) or (title or ""))
        frame.text:SetPoint("TOPLEFT", textLeft, -2)
        frame.text:SetPoint("TOPRIGHT", -right, -2)
        frame.text:SetHeight(ROW_H - 2)
        local meta = row.meta
        if type(meta) ~= "string" then
          meta = tostring(meta)
        end
        frame.meta:SetText(searching and Util.highlight(meta, self.query) or meta)
        frame.meta:ClearAllPoints()
        frame.meta:SetPoint("TOPLEFT", textLeft, -(ROW_H - 1))
        frame.meta:SetPoint("TOPRIGHT", -metaRight, -(ROW_H - 1))
        frame.meta:SetHeight(ROW_H - 4)
        frame.meta:Show()
        frame.div:Show()
      else
        frame.text:SetPoint("TOPLEFT", textLeft, -3)
        frame.text:SetPoint("BOTTOMRIGHT", -right, 2)
        frame.meta:Hide()
        frame.div:Hide()
      end
      if row.id == self.selectedID then
        frame.sel:Show()
        frame.bar:Show()
      else
        frame.sel:Hide()
        frame.bar:Hide()
      end
      if row.kind == "section" then
        frame.sec:Show()
      else
        frame.sec:Hide()
      end
      if row.kind == "rule" then
        frame.rule:Show()
      else
        frame.rule:Hide()
      end
      if row.hasChildren and not flatMode then
        frame.fold.label:SetText((searching or self:Expanded(row)) and "-" or "+")
        frame.fold:Show()
      else
        frame.fold:Hide()
      end
      if row.button then
        frame.action.label:SetText(row.button.label or "*")
        frame.action:Show()
      else
        frame.action:Hide()
      end
      if row.ref and not tableMode and (self.opts.iconsAlways or (focused ~= nil and row.ref == focused)) then
        -- the focused row always shows its icons (ADR 0013 C); a dossier's rows all of them
        --
        showIcons(self, frame)
      elseif frame.iconCount > 0 then
        hideIcons(frame)
      end
      frame:Show()
      i = i + 1
    end
  end
  for j = used + 1, #pool do
    pool[j]:Hide()
    pool[j].row = nil
  end
  self.visibleCount = used
  self.bar.Update()
  if self.opts.onRender then
    self.opts.onRender(self)
  end
end

function Tree:ScrollTo(offset)
  self.bar.ScrollTo(offset)
end

-- The filter bar above the rows (ADR 0016): one dropdown pill per dimension, see
-- Bastians.UI.FilterBar for the shape of `dims`.
function Tree:SetFilters(dims)
  local bar = self.filterBar
  if not bar then
    bar = B.UI.FilterBar(self.chips)
    bar.frame:SetPoint("TOPLEFT", 0, 0)
    bar.frame:SetPoint("TOPRIGHT", 0, 0)
    self.filterBar = bar
  end
  bar:SetDims(dims)
  self.chips:SetHeight(bar:Height())
end

-- Chips in the old shape, shown as the filter bar: `list` = { { key, label, count }, ... },
-- `active` key or nil for "All", onSelect(key); `more` = one more group { list, active, onSelect,
-- noAll, title } or an array of them. Each group is one pill; `title` names it ("Show" for the
-- first group unless given). Kept for the views of other apps (Quests' status chips).
function Tree:SetChips(list, active, onSelect, more, title)
  local dims = {}
  local function add(items, on, fn, noAll, name, id)
    if items and #items > 1 then -- one choice is nothing to choose
      dims[#dims + 1] = {
        id = id,
        title = name or L["Show"],
        choices = items,
        active = on,
        default = noAll and items[1].key or nil,
        all = not noAll and {} or false,
        onSelect = fn,
      }
    end
  end
  add(list, active, onSelect, false, title, "chips1")
  if more then
    local groups = more.list and { more } or more
    for i, g in ipairs(groups) do
      add(g.list, g.active, g.onSelect, g.noAll, g.title, "chips" .. (i + 1))
    end
  end
  self:SetFilters(dims)
end

Tree.ROW_H = ROW_H
