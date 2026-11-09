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
local META_LINE_H = 14 -- each further line of `row.metaMore` under the meta line
local FLAT_INDENT = 8 -- children inside a dossier block (flat mode): a step, no marker
local WORTH_W = 170 -- the value column may grow to this for a worth line (C3)
local WORTH_LINE_H = 12 -- a line of the worth under a two-line row
local WORTH_LINES = 2 -- at most this many
local RULE_H = 9 -- a "rule" row: one pixel line with air around it
-- A tile (opts.tiles, ADR 0056): a row with a ref as a plate of its own, a picture, the name and
-- one line under it, what it is worth at the right
local TILE_H = 56 -- with the gap under it
local TILE_GAP = 4
local TILE_ICON = 36
local TILE_MAP_W, TILE_MAP_H = 54, 36 -- a zone's tile: the zone as a mini map (ADR 0056)
local TILE_PAD = 8
local TILE_LINE1, TILE_LINE2 = 8, 28 -- where a tile's two lines start, from its top
local BADGE_H, BADGE_PAD, BADGE_GAP, BADGE_MIN = 18, 7, 4, 26 -- a tile's badge: a pill of words
local EDGE_W = 22 -- a tile's edge: the step inside (ADR 0056)
local ICON_W, ICON_GAP = 14, 2 -- the row action icons
local NOTE_W = 48 -- the note column of a table (ADR 0018 D: the chance, the stack)

local Tree = {}
Tree.__index = Tree

-- ---------------------------------------------------------------------------------------------
-- Pure helpers (exported for tests through Bastians.UI.TreeUtil)
-- ---------------------------------------------------------------------------------------------

local Util = {}
B.UI.TreeUtil = Util

-- Text with the query's words in the accent colour (ADR 0045: the plain words the query looks
-- for; `query` a text or a compiled query). Escape sequences (|c, |r, |T..|t, |H..|h..|h) pass
-- through untouched; after a highlight the colour that was active comes back.
function Util.highlight(text, query)
  if not (text and query and query ~= "") then
    return text
  end
  local words = B.Query.Of(query).words
  if #words == 0 then
    return text
  end
  local out, pos, n, color = {}, 1, #text, nil
  local acc = S.accent()
  -- the earliest of the words from `i` on
  local function nextHit(low, i)
    local bestA, bestB
    for _, w in ipairs(words) do
      local a, b = string.find(low, w, i, true)
      if a and (not bestA or a < bestA or (a == bestA and b > bestB)) then
        bestA, bestB = a, b
      end
    end
    return bestA, bestB
  end
  local function plain(s)
    if s == "" then
      return
    end
    local low, i, res = string.lower(s), 1, {}
    while true do
      local a, b = nextHit(low, i)
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
-- `query` is a text or a compiled query (ADR 0045), matched against each row's text.
function Util.flatten(rows, query, expanded)
  local out = {}
  local q = query and query ~= "" and B.Query.Of(query) or nil
  if q and q.empty then
    q = nil
  end
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
      if q then
        if q:MatchLower(Util.searchText(r), r) then
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

-- The block around flat[index]: the nearest row at or above it that carries
-- `block`, and the last row under that one. Returns first, last; nil outside a block.
function Util.blockOf(flat, index)
  local depth = math.huge
  for first = index, 1, -1 do
    local row = flat[first]
    if row.depth < depth then
      depth = row.depth
      if row.block then
        local last = first
        while flat[last + 1] and flat[last + 1].depth > depth do
          last = last + 1
        end
        return first, last
      end
      if depth == 0 then
        return nil
      end
    end
  end
  return nil
end

-- Row action icons (ADR 0013 C): small icons at the right of a row with a ref, shown on hover and
-- always on the focused row, drawn from the registered actions in this order: locate (map.show),
-- route (route.to), play or stop (voice.play, only where it has a line; Bastian's Voice since
-- 01.11.2026, Quests.Spoken before), open (browser.open), copy the Wowhead link (browser.wowhead,
-- ), hide (quests.hide). An app that is not installed simply contributes no icon.
Tree.ROW_ACTIONS = { "map.show", "route.to", "voice.play", "browser.open", "browser.wowhead", "quests.hide" }

-- How many row actions are registered now: the space kept free at the right of every ref row.
-- `ids`: a tree's own list (opts.rowActions, opts.hoverActions).
function Util.actionSlots(ids)
  local n = 0
  for _, id in ipairs(ids or Tree.ROW_ACTIONS) do
    if B:GetAction(id) then
      n = n + 1
    end
  end
  return n
end

-- The row actions that apply to ref now, in slot order. `when` is evaluated here, on hover or for
-- the one focused row, never for every row drawn (core-contracts §5).
function Util.rowActions(ref, ctx, ids)
  local out = {}
  local all = B:GetActions(ref, ctx)
  for _, id in ipairs(ids or Tree.ROW_ACTIONS) do
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
-- their short labels (`short`; `activeShort` while a toggle such as the voice line is on). An
-- action is `main` where its definition says so for this type (`main = true` or a list of types):
-- the sheet's buttons (ADR 0054), the rest are in More.
local function isMain(def, typ)
  local main = def.main
  if type(main) ~= "table" then
    return main == true
  end
  for _, t in ipairs(main) do
    if t == typ then
      return true
    end
  end
  return false
end

function B.UI.Card(ref, ctx, sections)
  local e = B:Entity(ref)
  local typ = B.Entity.Parse(ref)
  local card = {
    ref = ref,
    name = e:Name() or ref,
    icon = e:Icon() or B.UI.IconTexture(typ) or B.UI.IconTexture("other"),
    typeLabel = L[typ or "entity"],
    summary = e:Summary(),
    away = B.UI.Away(ref), -- the travel time there (C1; W8: the graph's, else the yards), or nil
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
      card.noStats = s.def.noStats -- the page goes without the stats strip (ADR 0052)
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
      main = isMain(def, typ),
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

-- Whether a row of a tree of tiles is drawn as a tile: it stands for one thing (a ref) and is
-- neither a heading nor a group nor running text; `tile = false` keeps a row plain.
function Util.isTile(row)
  return row.ref ~= nil
    and row.tile ~= false
    and row.kind ~= "para"
    and row.kind ~= "rule"
    and row.kind ~= "section"
    and row.children == nil
    and not row.hasChildren
end

-- The token of a tile's badge (ADR 0056: difficulty is a badge, never the colour of a name): its
-- own, else the game's difficulty colour of its level for the character; of a range (`level` to
-- `levelHi`, a zone) the level in it nearest the character's. nil: a quiet badge.
function Util.badgeToken(badge, playerLevel)
  if badge.token then
    return badge.token
  end
  return S.BandToken(badge.level, badge.levelHi, playerLevel)
end

-- Height of a row: paragraphs ("para") wrap, a rule (a horizontal divider, "rule") is thin,
-- everything else is one line. A two-line row with a worth gets one or two more lines for it
--.
-- The lines of `row.metaMore` under a two-line row's meta line; none hides the frame's old ones.
function Util.metaMore(frame, lines, left, right, y)
  frame.metaLines = frame.metaLines or {}
  for i = 1, math.max(#frame.metaLines, lines and #lines or 0) do
    local line = frame.metaLines[i]
    local text = lines and lines[i]
    if text and not line then
      line = S.text(frame, 11, S.C.dim)
      line:SetWordWrap(false)
      line:SetJustifyH("LEFT")
      frame.metaLines[i] = line
    end
    if text then
      line:ClearAllPoints()
      line:SetPoint("TOPLEFT", left, -(y + i * META_LINE_H))
      line:SetPoint("TOPRIGHT", -right, -(y + i * META_LINE_H))
      line:SetHeight(ROW_H - 4)
      line:SetText(text)
      line:Show()
    elseif line then
      line:Hide()
    end
  end
end

function Util.rowHeight(row, width, twoLine, worthOn, tiles)
  if row.height then
    return row.height
  end
  if tiles and Util.isTile(row) then
    return TILE_H
  end
  if row.kind == "rule" then
    return RULE_H
  end
  if twoLine and row.meta then
    local worth = Util.worthText(row, worthOn)
    if worth then
      return DOUBLE_H + Util.worthLines(worth, width) * WORTH_LINE_H + 2
    end
    return DOUBLE_H + (row.metaMore and #row.metaMore * META_LINE_H or 0)
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
--         left of the value, no action icons; set per block by the Dossier),
--         filterHost = frame, onFilterHeight(h) (ADR 0056: the filter bar stands in the owner's
--         frame, not above the rows; the owner sets its width with tree:SetFilterWidth),
--         entityNames = true (with tiles: a tile shows its entity's own name and line, not the
--         row's text and meta: one tile per type on a sheet's cards; one row asks with
--         `row.entityName`),
--         inside(row) -> bool and onInside(row) (ADR 0056: a tile of a thing with parts has an
--         edge at its right; a click there calls onInside, and so does a double click on the tile),
--         tiles = true (ADR 0056: a row with a ref is a tile: a plate, a large picture, the name,
--         under it `meta` or the entity's summary, the value or the worth at the right),
--         pages = true (ADR 0058: the rows in pages of what fits the view, no scroll bar; the
--         wheel, tree:TurnPage and tree:SetPage turn them, tree:Page says where you are; a new
--         first row goes back to the first page) }
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
    -- the palette of the window it stands in (a sheet on paper, the hub), nil for the theme: what
    -- the tree draws later (a render after a scroll, the icons under the mouse) draws in it
    palette = S.PaletteOf(parent),
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
  scroll:HookScript("OnHide", function() -- closed under the mouse: no block is left lit on reopening
    tree.hoverFrame = nil
    tree:PlaceBlock()
  end)
  if opts.flat then
    tree.bar:Hide()
    scroll:EnableMouseWheel(false)
    scroll:SetScript("OnMouseWheel", nil)
    chips:Hide()
  elseif opts.pages then
    tree.bar:Hide() -- pages, not a scroll (ADR 0058): the wheel turns them
    scroll:SetScript("OnMouseWheel", function(_, delta)
      tree:TurnPage(delta > 0 and -1 or 1)
    end)
    scroll:SetScript("OnSizeChanged", function()
      tree:Refresh() -- the pages are cut by the view's height
    end)
  end
  return tree
end

-- The stored folds. A profile switch prunes an empty table out of the old profile while a tree
-- built before still holds that profile's table (retail 31.10.2026: Quests stopped on
-- "attempt to index field 'collapsed'"), so the table is made again when it is gone.
function Tree:Folds()
  local folds = self.db.collapsed
  if type(folds) ~= "table" then
    folds = {}
    self.db.collapsed = folds
  end
  return folds
end

function Tree:Expanded(row)
  if self.opts.flat then
    return true
  end
  local c = self:Folds()[row.id]
  if c ~= nil then
    return not c
  end
  if row.collapsed ~= nil then
    return not row.collapsed
  end
  return true
end

function Tree:ToggleFold(row)
  self:Folds()[row.id] = self:Expanded(row) or nil
  if self:Folds()[row.id] == nil and row.collapsed then
    self:Folds()[row.id] = false -- the row folds by default, so "open" must be stored
  end
  self:Refresh()
end

function Tree:SetRows(rows)
  self.rows = rows or {}
  if self.opts.pages then
    -- another list, a filter, a search: the first page; the same rows growing (a staged
    -- fill) keep the page that is open
    local first = self.rows[1] and self.rows[1].id
    if first ~= self.firstRowID then
      self.pageWanted = 1
    end
    self.firstRowID = first
  end
  self:Refresh()
end

-- The search box's text (ADR 0045: the suite's search syntax, so its case stays for OR/AND/NOT).
function Tree:SetQuery(query)
  self.query = string.gsub(tostring(query or ""), "^%s*(.-)%s*$", "%1")
  self:Refresh()
end

-- The row the keyboard points at (ADR 0038: the arrows in a host's search box); nil clears it.
-- The row is lit like a hovered one and scrolled into view.
function Tree:SetKeyRow(row)
  self.keyRowID = row and row.id or nil
  if row then
    for i, r in ipairs(self.flat) do
      if r == row then
        local top, h = self.offsets[i] or 0, self.heights[i] or ROW_H
        local view = self.scroll:GetHeight() or 0
        local offset = self.scroll:GetVerticalScroll() or 0
        if self.opts.pages then
          self:SetPage(self:PageOf(i)) -- the page the row is on (ADR 0058)
        elseif top < offset then
          self:ScrollTo(top)
        elseif view > 0 and top + h > offset + view then
          self:ScrollTo(top + h - view)
        end
        break
      end
    end
  end
  self:Render()
end

-- The flat index of the key row, or nil.
function Tree:KeyIndex()
  if not self.keyRowID then
    return nil
  end
  for i, r in ipairs(self.flat) do
    if r.id == self.keyRowID then
      return i
    end
  end
  return nil
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
    local h = Util.rowHeight(
      row,
      width - (row.depth or 0) * indent,
      self.opts.twoLine,
      self:WorthOn(),
      self.opts.tiles
    )
    self.heights[i] = h
    total = total + h
  end
  for i = #self.flat + 1, #self.heights do
    self.heights[i], self.offsets[i] = nil, nil
  end
  if self.opts.pages then
    total = self:cutPages(total)
  end
  self.total = total
  self.content:SetSize(math.max(1, width), math.max(1, total))
  self.bar.SetTotal(total)
  if self.pageWanted then
    local page = self.pageWanted
    self.pageWanted = nil
    self:SetPage(page)
  elseif self.opts.pages then
    self:SetPage(self:Page()) -- a shorter list: back onto its last page
  end
  self:Render()
end

-- Pages (ADR 0058): the flat rows cut into pages of what fits the view's height, as the
-- starts of the pages (flat indices); the content is padded so the last page starts at its
-- top like every other. -> the padded total.
function Tree:cutPages(total)
  local view = self.scroll:GetHeight() or 0
  local starts = { 1 }
  if view > 0 then
    local used = 0
    for i, h in ipairs(self.heights) do
      if used > 0 and used + h > view then
        starts[#starts + 1] = i
        used = 0
      end
      used = used + h
    end
  end
  self.pageStarts = starts
  local last = starts[#starts]
  if #self.flat > 0 and view > 0 then
    total = math.max(total, (self.offsets[last] or 0) + view)
  end
  return total
end

-- The page the view is on: index, count, the first and the last flat index on it, the number
-- of rows. One page of nothing for an empty list.
function Tree:Page()
  local starts = self.pageStarts or { 1 }
  local offset = self.scroll:GetVerticalScroll() or 0
  local index = 1
  for i, start in ipairs(starts) do
    if (self.offsets[start] or 0) <= offset + 0.5 then
      index = i
    end
  end
  local first = starts[index]
  local last = (starts[index + 1] or (#self.flat + 1)) - 1
  return index, #starts, first, math.max(first - 1, last), #self.flat
end

-- The page a flat index is on.
function Tree:PageOf(i)
  local page = 1
  for p, start in ipairs(self.pageStarts or { 1 }) do
    if start <= i then
      page = p
    end
  end
  return page
end

-- Opens page `index` (clamped); the view scrolls to its first row.
function Tree:SetPage(index)
  local starts = self.pageStarts or { 1 }
  index = math.max(1, math.min(#starts, index or 1))
  self:ScrollTo(self.offsets[starts[index]] or 0)
  return index
end

function Tree:TurnPage(step)
  return self:SetPage(self:Page() + (step or 1))
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
    S.EntityTip(GameTooltip, row.ref, row.text)
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

-- A tile's second line: the line under the name, and right of it the value unless the action
-- icons stand there (`iconsRight`: where they end, from the tile's right edge).
local function placeSecondLine(frame, iconsRight)
  frame.meta:ClearAllPoints()
  frame.meta:SetPoint("TOPLEFT", frame.metaLeft or 0, -TILE_LINE2)
  frame.meta:SetPoint("TOPRIGHT", -(iconsRight or frame.metaRight or 6), -TILE_LINE2)
  frame.value:SetShown(frame.valueOn == true and not iconsRight)
end

local function hideIcons(frame)
  for _, b in ipairs(frame.icons) do
    b:Hide()
  end
  frame.iconCount = 0
  if frame.iconsOver then -- they stood on the tile's second line: its value comes back
    frame.iconsOver = nil
    placeSecondLine(frame)
  end
end

-- A tile's badge or mark (ADR 0056): a pill with a few words at the top right, in a token's
-- colour with the ink chosen against it (4.5 to 1), quiet without a token. Returns where the next
-- thing to its left ends, from the tile's right edge.
local function putBadge(frame, key, spec, token, right)
  local b = frame[key]
  if not spec or spec.text == nil or spec.text == "" then
    if b then
      b:Hide()
    end
    return right
  end
  if not b then
    b = CreateFrame("Frame", nil, frame)
    b:SetHeight(BADGE_H)
    b.fill = S.roundFill(b, S.C.press, "pill", "BACKGROUND")
    b.label = S.text(b, 12)
    b.label:SetPoint("CENTER")
    b.label:SetWordWrap(false)
    frame[key] = b
  end
  b.label:SetText(tostring(spec.text))
  local ground = token and S.C[token] or nil
  if ground then
    S.tint(b.fill, ground)
    S.ink(b.label, S.InkOn(ground))
  else
    S.tint(b.fill, S.C.press)
    S.ink(b.label, S.C.text)
  end
  b.token = ground and token or nil
  b:SetWidth(math.max(BADGE_MIN, math.floor((b.label:GetStringWidth() or 0) + 2 * BADGE_PAD + 0.5)))
  b:ClearAllPoints()
  b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -right, -(TILE_LINE1 - 1))
  b.fill:Show() -- lays the pill out for its new width
  b:Show()
  return right + b:GetWidth() + BADGE_GAP
end

-- The mouse is on the row: its own colour, and the block's behind it.
local function lightRow(tree, frame)
  frame.hl:Show()
  tree.hoverFrame = frame
  tree:PlaceBlock()
end

-- The mouse left the row and the widgets on it.
local function leaveRow(tree, frame)
  if tree.opts.onHover then
    tree.opts.onHover(frame.row, false)
  end
  if not (frame.row and frame.row.id == tree.keyRowID) then
    frame.hl:Hide() -- the key row stays lit (ADR 0038)
  end
  if not (frame.row and frame.row.id == tree.selectedID) then
    frame.bar:Hide()
  end
  -- the icons stay on a tree that shows them always (the Chain rows lost
  -- theirs after one hover) and on the focused row; the hover's own ones go (ADR 0053)
  if tree.opts.hoverActions and frame.row then
    Tree.ShowIcons(tree, frame)
  elseif not (tree.opts.iconsAlways or (frame.row and frame.row.ref and frame.row.ref == B:Focused())) then
    hideIcons(frame)
  end
  if tree.hoverFrame == frame then
    tree.hoverFrame = nil
    tree:PlaceBlock()
  end
end

-- A widget on a row takes the mouse from it: it counts as the row, also when the mouse leaves
-- through it (the row's own OnLeave saw the mouse still over the row and did nothing).
local function widgetLeft(tree, frame)
  if not frame:IsMouseOver() then
    leaveRow(tree, frame)
  end
end

-- The icons of the row's ref, placed from `frame.iconRight` leftwards; the one that is active (a
-- line playing) is tinted green. Returns how many are shown.
local function showIconsNow(tree, frame, hovering)
  local row = frame.row
  if not (row and row.ref) or tree.opts.table then -- a table row carries no action icons (ADR 0018 D)
    hideIcons(frame)
    return 0
  end
  local opts = tree.opts
  local actions = Util.rowActions(row.ref, tree.ctx, opts.rowActions)
  if hovering and opts.hoverActions then -- a tree's quieter buttons, only under the mouse
    for _, def in ipairs(Util.rowActions(row.ref, tree.ctx, opts.hoverActions)) do
      actions[#actions + 1] = def
    end
  end
  local size = opts.iconSize or ICON_W
  local x = frame.iconRight or 6
  for i, def in ipairs(actions) do
    local b = frame.icons[i]
    if not b then
      b = CreateFrame("Button", nil, frame)
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
        lightRow(tree, frame)
        S.TipEnter(self)
      end)
      b:SetScript("OnLeave", function(self)
        S.TipLeave(self)
        widgetLeft(tree, frame)
      end)
      frame.icons[i] = b
    end
    b:SetSize(size, size)
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
    -- on a two-line row the icons sit on the first line, on a tile on the second (the first
    -- belongs to the name and the badges)
    local y = frame.tile and ((TILE_H - TILE_GAP) / 2 - TILE_LINE2 - 7)
      or (frame.twoLine and (DOUBLE_H - ROW_H) / 2 or 0)
    b:SetPoint("RIGHT", frame, "RIGHT", -x, y)
    b:Show()
    x = x + size + ICON_GAP
  end
  for i = #actions + 1, #frame.icons do
    frame.icons[i]:Hide()
  end
  frame.iconCount = #actions
  if frame.tile and frame.twoLine and #actions > 0 then
    frame.iconsOver = true -- in the place of the value, while they show
    placeSecondLine(frame, x + 2)
  end
  return #actions
end

local function showIcons(tree, frame, hovering)
  return S.WithPalette(tree.palette, showIconsNow, tree, frame, hovering)
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
  frame.fold:SetScript("OnEnter", function()
    lightRow(tree, frame)
  end)
  frame.fold:SetScript("OnLeave", function()
    widgetLeft(tree, frame)
  end)
  frame.icon = frame:CreateTexture(nil, "ARTWORK")
  frame.icon:SetSize(12, 12)
  frame.icon:SetPoint("LEFT", 15, 0)
  frame.icon:Hide()
  frame.textSize = tree.opts.tiles and 14 or 12 -- a tile's name is larger (ADR 0056)
  frame.text = S.text(frame, frame.textSize)
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
  frame.action:HookScript("OnEnter", function()
    lightRow(tree, frame)
  end)
  frame.action:HookScript("OnLeave", function()
    widgetLeft(tree, frame)
  end)
  frame:SetScript("OnClick", function(self, button)
    rowClick(tree, self, button)
  end)
  -- a double click on a tile of a thing with parts steps inside, as its edge does (ADR 0056:
  -- the first click showed its sheet). Only where the host steps inside: a button with this
  -- script gets it in place of the second click of a fast pair, so every other row answers it
  -- as the click it is (a group folds and unfolds, a quest's sheet opens and closes)
  if tree.opts.onInside then
    frame:SetScript("OnDoubleClick", function(self, button)
      local row = self.row
      if self.tile and row and tree.opts.inside and tree.opts.inside(row) then
        tree.opts.onInside(row)
      else
        rowClick(tree, self, button)
      end
    end)
  end
  frame:SetScript("OnEnter", function(self)
    lightRow(tree, self)
    self.bar:Show()
    showIcons(tree, self, true)
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
      return -- the mouse went onto one of the row's widgets
    end
    leaveRow(tree, self)
  end)
  return frame
end

-- The block colour behind the hovered row's block, else the key row's. One
-- texture on the content, under the row frames: it spans the indents and the rows scrolled away.
-- A block of one row has nothing to tell apart, so only the row's own colour shows.
function Tree:PlaceBlock()
  return S.WithPalette(self.palette, self.PlaceBlockNow, self)
end

function Tree:PlaceBlockNow()
  local hover = self.hoverFrame
  local index = hover and hover.row and hover.index or self:KeyIndex()
  local first, last
  if index then
    first, last = Util.blockOf(self.flat, index)
  end
  local fill = self.blockFill
  if not first or first == last then
    if fill then
      fill:Hide()
    end
    return
  end
  if not fill then
    fill = S.fill(self.content, S.C.hoverBlock, "BACKGROUND")
    self.blockFill = fill
  end
  local indent = self.flat[first].depth * (self.opts.flat and FLAT_INDENT or INDENT)
  fill:ClearAllPoints()
  fill:SetPoint("TOPLEFT", self.content, "TOPLEFT", indent, -self.offsets[first])
  fill:SetPoint("BOTTOMRIGHT", self.content, "TOPRIGHT", 0, -(self.offsets[last] + self.heights[last]))
  fill:Show()
end

-- Lay the visible rows out on pooled frames (the hot path: no tables are created here; a tree
-- in a palette of its own pays one for the switch).
function Tree:Render()
  return S.WithPalette(self.palette, self.RenderNow, self)
end

function Tree:RenderNow()
  local width = self:Width()
  local view = self.scroll:GetHeight() or 0
  local offset = self.scroll:GetVerticalScroll() or 0
  local flat, pool = self.flat, self.pool
  local n = #flat
  local used = 0
  local faces -- the NPC faces of this render (ADR 0034), nil while the switch is off
  if n > 0 and view > 0 then
    local over = self.opts.pages and 0 or OVERSCAN -- a page draws its own rows alone
    local first = math.max(1, self:FirstVisible(offset) - over)
    local pageLast -- a page's last row: nothing of the next page shows cut at the bottom
    if self.opts.pages then
      pageLast = select(4, self:Page())
    end
    local searching = self.query ~= ""
    local tableMode = self.opts.table == true
    local slots = 0
    if not tableMode then
      local count = Util.actionSlots(self.opts.rowActions)
      if self.opts.hoverActions then
        count = count + Util.actionSlots(self.opts.hoverActions)
      end
      slots = count * ((self.opts.iconSize or ICON_W) + ICON_GAP)
    end
    local focused = B:Focused()
    if S.Skin("rowPortraits") and B.UI.Scenery then
      self.faces = self.faces or B.UI.Scenery.FacePool(self.content)
      faces = self.faces
      faces:Begin()
    end
    local flatMode = self.opts.flat
    local tiles = self.opts.tiles == true
    local playerLevel -- asked once, for the first badge that carries a level
    local indentStep = flatMode and FLAT_INDENT or INDENT
    local rowLeft = flatMode and 3 or FOLD_W + 1 -- flat rows need no room for the fold marker
    local i = first
    while
      i <= n
      and (pageLast and i <= pageLast or (not pageLast and self.offsets[i] < offset + view + over * ROW_H))
    do
      local row = flat[i]
      used = used + 1
      local frame = pool[used]
      if not frame then
        frame = makeRow(self)
        pool[used] = frame
      end
      local indent = (row.depth or 0) * indentStep
      frame.row, frame.index = row, i
      frame:ClearAllPoints()
      frame:SetPoint("TOPLEFT", self.content, "TOPLEFT", indent, -self.offsets[i])
      frame:SetWidth(width - indent)
      frame:SetHeight(self.heights[i])
      -- a tile: its own plate with a gap under it, the picture large, two lines
      local tile = tiles and Util.isTile(row)
      local left = tile and TILE_PAD or rowLeft
      local meta = row.meta
      -- what the tile says of its thing (the facet "tile", core-contracts §4): asked for the
      -- rows in view, cached on the facade
      local facts = tile and B:Entity(row.ref):Facet("tile") or nil
      if tile then
        frame:SetHeight(self.heights[i] - TILE_GAP)
        if not frame.plate then
          frame.plate = S.roundFill(frame, S.C.card, "radiusSmall", "BACKGROUND")
          frame.plateEdge = S.roundEdges(frame, S.C.accent, "radiusSmall")
        end
        local chosen = row.id == self.selectedID
        S.tint(frame.plate, chosen and S.C.accent or S.C.card, chosen and 0.2 or nil)
        frame.plate:Show()
        if chosen then
          S.tint(frame.plateEdge, S.C.accent, 0.9)
          frame.plateEdge:Show()
        else
          frame.plateEdge:Hide()
        end
        if meta == nil or self.opts.entityNames or row.entityName then
          -- the tile's own line, else what the entity is in one line; on a sheet's card always
          -- the thing's own (one tile per type, ADR 0056), the row's words only without one
          meta = facts and facts.line or B:Entity(row.ref):Summary() or row.meta or ""
        end
      elseif frame.plate then
        frame.plate:Hide()
        frame.plateEdge:Hide()
      end
      frame.tile = tile or false
      frame.iconsOver = nil -- this render lays the second line out again
      local textSize = tile and 14 or 12 -- a pooled row may have been the other kind
      if frame.textSize ~= textSize then
        frame.textSize = textSize
        S.setSize(frame.text, textSize)
      end
      -- a tile always has its two lines: the name stays in its place beside the badges
      local two = (self.opts.twoLine == true and row.meta ~= nil) or tile == true
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
      -- an NPC's face in place of its glyph (the skin's `rowPortraits`, ADR 0034)
      local npc = faces and row.ref and row.npcFace
      if faces and row.ref and npc == nil then
        local kind, id = B.Entity.Parse(row.ref)
        npc = kind == "npc" and tonumber(id) or false
        row.npcFace = npc
      end
      -- a zone's tile carries the zone, in the chosen map style (ADR 0056)
      local mapped = false
      if facts and facts.map then
        local mini = frame.mini
        if not mini then
          mini = CreateFrame("Frame", nil, frame)
          mini.art = {}
          frame.mini = mini
        end
        mini:ClearAllPoints()
        mini:SetPoint("LEFT", frame, "LEFT", left, 0)
        mini:SetSize(TILE_MAP_W, TILE_MAP_H)
        mapped = B.UI.Scenery.DrawPicture(mini, mini.art, facts.map, 0, 0, 1, 1, TILE_MAP_W, TILE_MAP_H)
        mini:SetShown(mapped)
      elseif frame.mini then
        frame.mini:Hide()
      end
      -- a tile's picture in the same slot (`facts.picture = { path, coords }`: a gold story's
      -- picture of Bastian, ); a file the client cannot show leaves the icon
      local pictured = false
      if not mapped and facts and facts.picture then
        local pic = frame.pic
        if not pic then
          pic = frame:CreateTexture(nil, "ARTWORK")
          frame.pic = pic
        end
        pic:ClearAllPoints()
        pic:SetPoint("LEFT", frame, "LEFT", left, 0)
        pic:SetSize(TILE_MAP_W, TILE_MAP_H)
        pic:SetTexture(facts.picture.path)
        local c = facts.picture.coords or {} -- { left, right, top, bottom }, the whole by default
        pic:SetTexCoord(c.left or 0, c.right or 1, c.top or 0, c.bottom or 1)
        pictured = pic:GetTexture() ~= nil
        pic:SetShown(pictured)
      elseif frame.pic then
        frame.pic:Hide()
      end
      local faceSize = tile and TILE_ICON or math.min(30, self.heights[i] - 2)
      -- a row that links an entity shows its picture when it brings none (owner, retail
      -- 29.10.2026: "always use the picture or 3d model"); `icon = false` keeps a row bare
      local icon = row.icon
      if facts and facts.icon then
        icon = facts.icon -- a quest's state, in place of the list's glyph
      end
      if icon == nil and row.ref and row.kind ~= "para" then
        icon = B:Entity(row.ref):Icon()
      end
      if mapped or pictured then
        frame.icon:Hide()
        textLeft = left + TILE_MAP_W + TILE_PAD
      elseif npc and faces:Place(npc, frame, faceSize, left) then
        frame.icon:Hide()
        textLeft = left + faceSize + (tile and TILE_PAD or 3)
      elseif icon then
        B.UI.PaintIcon(frame.icon, icon)
        if row.tint and S.C[row.tint] then
          S.tint(frame.icon, S.C[row.tint]) -- a glyph in the row's own token (Teaches: known by whom)
        end
        frame.icon:ClearAllPoints()
        frame.icon:SetPoint("LEFT", left, 0)
        local iconSize = tile and (TILE_ICON - 4) or 12 -- a pooled row may have been a tile
        frame.icon:SetSize(iconSize, iconSize)
        frame.icon:Show()
        textLeft = left + iconSize + (tile and (TILE_PAD + 4) or 3)
      else
        frame.icon:Hide()
      end
      local noteW = (row.note and not tableMode) and 44 or 0 -- a table's note is a column, below
      local right = 6 + (row.button and 28 or 0) + noteW + (row.rightPad or 0)
      -- a tile of a thing with parts has an edge at its right: a click there steps inside (ADR
      -- 0056, P2: the tile shows the sheet, its edge the inside); the host says which and what
      local edgeW = 0
      if tile and self.opts.onInside and self.opts.inside and self.opts.inside(row) then
        edgeW = EDGE_W
        local edge = frame.edge
        if not edge then
          edge = CreateFrame("Button", nil, frame)
          edge:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
          edge:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
          edge:SetWidth(EDGE_W)
          edge.line = S.fill(edge, S.C.divider, "ARTWORK")
          edge.line:ClearAllPoints()
          edge.line:SetPoint("TOPLEFT", edge, "TOPLEFT", 0, -6)
          edge.line:SetPoint("BOTTOMLEFT", edge, "BOTTOMLEFT", 0, 6)
          edge.line:SetWidth(1)
          edge.label = S.text(edge, 16, S.C.dim)
          edge.label:SetPoint("CENTER", 1, 0)
          edge.label:SetText(">")
          edge.tip = L["Step inside"]
          edge:SetScript("OnClick", function()
            if frame.row and self.opts.onInside then
              self.opts.onInside(frame.row)
            end
          end)
          edge:SetScript("OnEnter", function(btn)
            lightRow(self, frame)
            S.ink(btn.label, S.Tok(frame, "accent"))
            S.TipEnter(btn)
          end)
          edge:SetScript("OnLeave", function(btn)
            S.ink(btn.label, S.Tok(frame, "dim"))
            S.TipLeave(btn)
            widgetLeft(self, frame)
          end)
          frame.edge = edge
        end
        S.ink(edge.label, S.C.dim)
        edge:Show()
      elseif frame.edge then
        frame.edge:Hide()
      end
      local levelsAhead -- a countdown badge's levels still to go (a dungeon's band)
      if tile then
        -- the name's line ends at the badges; the icons under the mouse take the value's place
        frame.iconRight = TILE_PAD + edgeW
        right = TILE_PAD + edgeW + (row.button and 28 or 0) + (row.rightPad or 0)
        -- the entity's badge; without one the row's own words (a list's level); `false`
        -- from the entity: none at all
        local badge = facts and facts.badge
        if badge == nil and row.badge ~= nil then
          badge = { text = row.badge }
        end
        badge = badge or nil
        local token
        if badge and badge.token == nil and badge.level then
          if playerLevel == nil then
            playerLevel = B.Compat.GetPlayerFacts().level or false
          end
          token = Util.badgeToken(badge, playerLevel or nil)
          if badge.countdown and playerLevel and badge.level > playerLevel then
            levelsAhead = badge.level - playerLevel
          end
        elseif badge then
          token = badge.token
        end
        right = putBadge(frame, "badge", badge, token, right)
        local mark = facts and facts.mark or nil
        right = putBadge(frame, "mark", mark, mark and mark.token, right)
      else
        if frame.badge then
          frame.badge:Hide()
        end
        if frame.mark then
          frame.mark:Hide()
        end
        if row.ref and slots > 0 then
          frame.iconRight = right -- the icons sit here, right of the value; shown on hover
          right = right + slots
        end
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
        if worth and two and not tile then
          worthLine = worth
        elseif worth then
          valueText = worth
          S.ink(frame.value, S.C.gold)
        elseif levelsAhead then
          -- "in 4 levels": how far the character is from the band (catalog review A2.2)
          valueText = levelsAhead == 1 and L["in 1 level"] or string.format(L["in %d levels"], levelsAhead)
          S.ink(frame.value, S.C.dim)
        elseif facts and facts.note then
          valueText = tostring(facts.note) -- a tile without a worth: its note ("3 places")
          S.ink(frame.value, S.C.dim)
        end
      end
      if valueText and (tile or row.value == nil) then
        frame.value:SetText(valueText)
        -- never more than a third of the row, cut with an ellipsis (
        -- and Forever 23.10.2026: a long worth wrapped over the icons and the next row)
        local cap = math.max(VALUE_W, math.floor(width / (tile and 2 or 3))) -- a tile has the line to share
        valueW = math.min(WORTH_W, cap, math.max(VALUE_W, (frame.value:GetStringWidth() or 0) + 4))
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
          frame.value:SetPoint(
            "BOTTOMRIGHT",
            frame,
            "BOTTOMRIGHT",
            tile and -(TILE_PAD + edgeW) or -6,
            tile and 9 or 3
          )
          metaRight = valueW + 12 + edgeW
        else
          frame.value:SetPoint("RIGHT", frame, "RIGHT", -right, 0)
          right = right + valueW + 6
        end
        frame.value:Show()
      else
        frame.value:Hide()
      end
      frame.valueOn = valueText ~= nil
      if row.note then
        -- as with the text: a table here stopped the whole tree at that row (Notes, 28.10.2026)
        local note = L[row.note]
        frame.note:SetText(type(note) == "string" and note or tostring(note))
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
        if tile and (self.opts.entityNames or row.entityName) then
          -- a tile of a sheet's card says the thing's own name: what the row's text adds (a
          -- level in brackets, a state's icon) is the tile's badge and picture
          local name = B:Entity(row.ref):Name()
          if name then
            title = name .. tagText
          end
        end
        frame.text:SetText(searching and Util.highlight(title or "", self.query) or (title or ""))
        local y1, y2 = tile and TILE_LINE1 or 2, tile and TILE_LINE2 or (ROW_H - 1)
        frame.metaLeft, frame.metaRight = textLeft, metaRight
        frame.text:SetPoint("TOPLEFT", textLeft, -y1)
        frame.text:SetPoint("TOPRIGHT", -right, -y1)
        frame.text:SetHeight(ROW_H - 2)
        if type(meta) ~= "string" then
          meta = tostring(meta)
        end
        frame.meta:SetText(searching and Util.highlight(meta, self.query) or meta)
        frame.meta:ClearAllPoints()
        frame.meta:SetPoint("TOPLEFT", textLeft, -y2)
        frame.meta:SetPoint("TOPRIGHT", -metaRight, -y2)
        frame.meta:SetHeight(ROW_H - 4)
        frame.meta:Show()
        Util.metaMore(frame, row.metaMore, textLeft, metaRight, y2)
        frame.div:SetShown(not tile) -- a tile's edge is its plate
      else
        frame.text:SetPoint("TOPLEFT", textLeft, -3)
        frame.text:SetPoint("BOTTOMRIGHT", -right, 2)
        frame.meta:Hide()
        Util.metaMore(frame)
        frame.div:Hide()
      end
      if row.id == self.selectedID and tile then
        frame.sel:Hide() -- the chosen tile is its plate in the accent
        frame.bar:Hide()
      elseif row.id == self.selectedID then
        frame.sel:Show()
        frame.bar:Show()
      else
        frame.sel:Hide()
        frame.bar:Hide()
      end
      if self.keyRowID ~= nil and row.id == self.keyRowID then
        frame.hl:Show() -- the keyboard's row (ADR 0038)
      elseif self.keyRowID ~= nil and not frame:IsMouseOver() then
        frame.hl:Hide()
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
  if faces then
    faces:End()
  elseif self.faces then
    self.faces:HideAll() -- the switch went off, or nothing to show
  end
  self.visibleCount = used
  self.bar.Update()
  self:PlaceBlock()
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
  -- a host of the owner's (opts.filterHost, ADR 0056: the Browser's chips stand beside its
  -- search) takes the bar out of the tree; the owner gives it its width (SetFilterWidth) and
  -- hears of its height (opts.onFilterHeight)
  local host = self.opts.filterHost
  if not bar then
    bar = B.UI.FilterBar(host or self.chips)
    bar.frame:SetPoint("TOPLEFT", 0, 0)
    if host then
      if self.filterWidth then
        bar.frame:SetWidth(self.filterWidth)
      end
    else
      bar.frame:SetPoint("TOPRIGHT", 0, 0)
    end
    -- the rows start under the bar's real height, also after a relayout at another width
    --
    bar.onHeight = function(h)
      if host then
        host:SetHeight(h)
        if self.opts.onFilterHeight then
          self.opts.onFilterHeight(h)
        end
      else
        self.chips:SetHeight(h)
      end
    end
    self.filterBar = bar
  end
  bar:SetDims(dims)
  local holder = host or self.chips
  holder:SetHeight(bar:Height())
end

-- The width a hosted filter bar flows in (opts.filterHost): its pills wrap there.
function Tree:SetFilterWidth(width)
  if not (width and width > 0) then
    return
  end
  self.filterWidth = width
  local bar = self.filterBar
  if bar and bar.laidOutAt ~= width then
    bar.frame:SetWidth(width)
    bar:Layout()
  end
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
Tree.TILE_H = TILE_H
