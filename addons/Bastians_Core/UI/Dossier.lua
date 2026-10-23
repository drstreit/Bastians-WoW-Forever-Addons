-- UI kit: Bastians.UI.Dossier(parent, opts): the dossier of one entity (ADR 0014, companion-design
-- §4): a header band (icon, name, type badge, summary, the status words with the distance, the worth
-- line, the actions as labelled buttons), the registered detail sections as blocks flowed into a grid
-- of one to three columns by width (each a titled list of rows, capped with a "+N more" row that
-- expands in place), and the sections marked `link` as relation rows with chips below the blocks.
-- Pooled frames, nothing built while hidden. The rows inside a block are a Tree in flat mode.
local _, ns = ...
local B = ns.B
local S = ns.Style
local L = ns.L

local GAP = 14 -- between grid cells and regions
local PAD = 6 -- inside the band and the blocks
local TITLE_H = 18 -- a block's title line
local LINE_H = 15 -- a band text line
local BUTTON_H = 22
local CHIP_H, CHIP_GAP = 18, 4
local LABEL_W = 70 -- the relation label of a link row
local ICON = 40
local DEFAULT_LIMIT = 5
local LINK_LIMIT = 8

local Dossier = {}
Dossier.__index = Dossier

-- ---------------------------------------------------------------------------------------------
-- Pure helpers (exported for tests through Bastians.UI.DossierUtil)
-- ---------------------------------------------------------------------------------------------

local Util = {}
B.UI.DossierUtil = Util

-- Grid columns by width: one under 420 px, two under 680 px, three above.
function Util.columns(width)
  if width < 420 then
    return 1
  elseif width < 680 then
    return 2
  end
  return 3
end

-- The dossier of an entity as data: the card (Bastians.UI.Card), the blocks and the links from the
-- registered sections (core-contracts §7). A section marked `link` lands in the links; the section
-- marked `card` with a single row is the band's status line and no block; every other section is a
-- block with its `block` options (`columns` cells wide, `wide` = the whole row, `limit` rows shown).
function B.UI.DossierData(ref, sections, ctx, opts)
  sections = sections or B:GetDetailSections(ref)
  local card = B.UI.Card(ref, ctx, sections)
  local blocks, links = {}, {}
  if opts and opts.here then
    -- the Here column (C4): the sections marked `here = { order, limit }` only, every one a wide
    -- block in that order, no links
    for _, s in ipairs(sections) do
      local h = s.def.here
      if h then
        blocks[#blocks + 1] = {
          id = s.id,
          title = s.title,
          rows = s.rows,
          def = s.def,
          span = 1,
          wide = true,
          limit = h.limit or DEFAULT_LIMIT,
          order = h.order or s.def.order or 50,
          count = #s.rows,
        }
      end
    end
    table.sort(blocks, function(a, b)
      if a.order ~= b.order then
        return a.order < b.order
      end
      return a.id < b.id
    end)
    return { ref = ref, card = card, blocks = blocks, links = links }
  end
  for _, s in ipairs(sections) do
    local def = s.def
    if def.here and def.here.only then
      -- a Here-column section (C4): not on the page, the zone page has its own blocks
      local _ = nil
    elseif def.link then
      links[#links + 1] = {
        id = s.id,
        relation = def.link,
        title = s.title,
        rows = s.rows,
        limit = def.limit or LINK_LIMIT,
      }
    elseif not (def.card and #s.rows == 1) then
      local b = def.block or {}
      blocks[#blocks + 1] = {
        id = s.id,
        title = s.title,
        rows = s.rows,
        def = def,
        span = b.columns or 1,
        wide = b.wide or false,
        twoLine = b.twoLine or false, -- rows with `meta` on two lines in this block (S7)
        table = b.table or false, -- a small table: icon, name, note, value (ADR 0018 D)
        limit = b.limit or DEFAULT_LIMIT,
        count = #s.rows,
      }
    end
  end
  return { ref = ref, card = card, blocks = blocks, links = links }
end

-- Places blocks into a grid of `cols` cells of `cellW` px: left to right, a block that does not fit
-- the rest of its row starts the next one; a row is as tall as its tallest block. `heightOf(block,
-- width)` measures a block at the width it gets. -> placements { x, y, w, h, block }, total height.
function Util.grid(blocks, cols, cellW, gap, heightOf)
  local out = {}
  local y, x, rowH, rowStart = 0, 0, 0, 1
  local function flush()
    for i = rowStart, #out do
      out[i].y = y
    end
    y = y + rowH + (rowH > 0 and gap or 0)
    x, rowH, rowStart = 0, 0, #out + 1
  end
  for _, block in ipairs(blocks) do
    local span = block.wide and cols or math.min(cols, block.span or 1)
    if x + span > cols then
      flush()
    end
    local w = span * cellW + (span - 1) * gap
    local h = heightOf(block, w)
    out[#out + 1] = { x = x * (cellW + gap), w = w, h = h, block = block }
    rowH = math.max(rowH, h)
    x = x + span
  end
  flush()
  return out, math.max(0, y - gap)
end

-- A title in capitals: the text outside escape sequences only (|c..|r, |T..|t, |H..|h..|h stay
-- as they are; an upper-cased "|R" would no longer end a colour).
function Util.caps(text)
  text = tostring(text or "")
  local out, pos, n = {}, 1, #text
  while pos <= n do
    local s = string.find(text, "|", pos, true)
    if not s then
      out[#out + 1] = string.upper(string.sub(text, pos))
      break
    end
    out[#out + 1] = string.upper(string.sub(text, pos, s - 1))
    local c = string.sub(text, s + 1, s + 1)
    local e
    if c == "c" then
      e = s + 9
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

-- Whether a row or one of its descendants carries the (lower-cased) query in its text.
local function matches(row, query)
  if string.find(B.UI.TreeUtil.searchText(row), query, 1, true) then
    return true
  end
  for _, child in ipairs(row.children or {}) do
    if matches(child, query) then
      return true
    end
  end
  return false
end

-- The rows a block shows: all of them when expanded or within the limit, else the first `limit`
-- and a "+N more" row (`kind = "more"`, `onClick` expands). With a query only the matching rows,
-- uncapped (the search box filters a page, browser.md).
function Util.shownRows(block, expanded, onMore, query)
  if query and query ~= "" then
    local out = {}
    for _, row in ipairs(block.rows) do
      if matches(row, query) then
        out[#out + 1] = row
      end
    end
    return out, false
  end
  if expanded or #block.rows <= block.limit then
    return block.rows, false
  end
  local out = {}
  for i = 1, block.limit do
    out[i] = block.rows[i]
  end
  out[#out + 1] = {
    id = "more:" .. block.id,
    kind = "more",
    text = string.format(L["+%d more"], #block.rows - block.limit),
    color = S.C.accent,
    search = "",
    onClick = onMore,
  }
  return out, true
end

-- The band's status line: the status words, the distance, or both.
function Util.statusLine(card)
  local dist = B.UI.Distance(card.distance)
  if card.status and dist then
    return card.status .. "  " .. S.H.dim .. dist .. "|r"
  end
  return card.status or dist
end

-- ---------------------------------------------------------------------------------------------
-- The widget
-- ---------------------------------------------------------------------------------------------

-- opts: { ctx (action context, default { source = "dossier" }), onClick(row, button, dossier) (a row
--         or a link chip; default: the primary action, right click the entity menu), tooltip(tt, row),
--         buttons(ref) -> { { label, icon, onClick, accent, enabled } } (the host's own band buttons,
--         e.g. the Browser's bookmark), onRender(dossier) (after every layout),
--         here = true (C4: the Here column, the `here` sections only, a band without buttons),
--         host (handed to a section's own `onRender(rows, host)` and `onHide(host)`, C4) }
function B.UI.Dossier(parent, opts)
  opts = opts or {}
  local self = setmetatable({
    parent = parent,
    opts = opts,
    ctx = opts.ctx or { source = "dossier" },
    expanded = {},
    blockPool = {},
    chipPool = {},
    labelPool = {},
    buttons = {},
    data = nil,
    dirty = false,
  }, Dossier)

  local frame = CreateFrame("Frame", nil, parent)
  frame:SetPoint("TOPLEFT", 0, 0)
  frame:SetPoint("BOTTOMRIGHT", -14, 0)
  self.frame = frame
  local scroll = CreateFrame("ScrollFrame", nil, frame)
  scroll:SetAllPoints(frame)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)
  self.scroll, self.content = scroll, content
  self.bar = S.scrollbar(scroll, frame, nil)
  scroll:SetScript("OnSizeChanged", function()
    if self.data then
      self:Layout()
    end
  end)
  frame:SetScript("OnShow", function()
    if self.dirty then
      self:Layout()
    end
  end)

  -- the band
  local band = CreateFrame("Frame", nil, content)
  band:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
  S.panel(band, S.C.panel)
  band.icon = band:CreateTexture(nil, "ARTWORK")
  band.icon:SetSize(ICON, ICON)
  band.icon:SetPoint("TOPLEFT", band, "TOPLEFT", PAD, -PAD)
  band.name = S.text(band, 16, S.C.accent)
  band.name:SetPoint("TOPLEFT", band, "TOPLEFT", ICON + 2 * PAD, -PAD)
  band.name:SetJustifyH("LEFT")
  band.badge = CreateFrame("Frame", nil, band)
  band.badge:SetHeight(16)
  band.badge.edges = S.border(band.badge)
  band.badge.label = S.text(band.badge, 11, S.C.text)
  band.badge.label:SetPoint("CENTER")
  band.badge.label:SetJustifyH("CENTER")
  band.preview = S.text(band, 11, S.C.accent) -- a hovered row shown for a moment (ADR 0018 C)
  band.preview:SetText(L["preview: click the row to keep it"])
  band.preview:Hide()
  band.meta = S.text(band, 12, S.C.dim)
  band.meta:SetJustifyH("LEFT")
  band.status = S.text(band, 12, S.C.text)
  band.status:SetJustifyH("LEFT")
  band.worth = S.text(band, 12, S.C.gold)
  band.worth:SetJustifyH("LEFT")
  band:Hide()
  self.band = band

  -- the links region
  local links = CreateFrame("Frame", nil, content)
  links.title = S.text(links, 11, S.C.dim)
  links.title:SetPoint("TOPLEFT", links, "TOPLEFT", 0, 0)
  links.title:SetText(Util.caps(L["Links"]))
  links.line = S.fill(links, S.C.line, "BORDER")
  links.line:ClearAllPoints()
  links.line:SetPoint("TOPLEFT", links, "TOPLEFT", 0, -TITLE_H + 3)
  links.line:SetPoint("TOPRIGHT", links, "TOPRIGHT", 0, -TITLE_H + 3)
  links.line:SetHeight(1)
  links:Hide()
  self.links = links

  -- the trail (C5): the way here as breadcrumbs under the links, a click goes back to that point
  local trail = CreateFrame("Frame", nil, content)
  trail.label = S.text(trail, 11, S.C.dim)
  trail.label:SetPoint("LEFT", trail, "LEFT", 0, 0)
  trail.label:SetText(Util.caps(L["trail"]))
  trail:Hide()
  self.trail = trail
  self.trailPool = {}
  self.trailList = {}
  return self
end

-- The trail: list = { { ref, name, index }, ... } oldest first; onClick(item) when one is clicked.
-- An empty list hides it.
function Dossier:SetTrail(list, onClick)
  self.trailList = list or {}
  self.onTrail = onClick
  if self.data and self.frame:IsVisible() then
    self:Layout()
  end
end

function Dossier:Width()
  local w = self.scroll:GetWidth()
  if not w or w <= 0 then
    w = (self.parent:GetWidth() or 400) - 14
  end
  return w
end

function Dossier:Show()
  self.frame:Show()
end

function Dossier:Hide()
  self.frame:Hide()
end

function Dossier:IsShown()
  return self.frame:IsShown()
end

-- The subject. `sections` may be passed when the host fetched them already; `ctx` overrides the
-- widget's action context for this subject; `opts.preview` marks a subject shown for a hovered
-- row (ADR 0018 C). Nothing is laid out while the widget is hidden.
function Dossier:SetSubject(ref, sections, ctx, opts)
  if ref ~= self.ref then
    self.expanded = {}
  end
  self.ref = ref
  self.previewing = opts and opts.preview or false
  self.data = B.UI.DossierData(ref, sections, ctx or self.ctx, { here = self.opts.here })
  if self.frame:IsVisible() then
    self:Layout()
  else
    self.dirty = true
  end
end

function Dossier:Clear()
  self.ref, self.data, self.dirty = nil, nil, false
  self.band:Hide()
  self.links:Hide()
  self.trail:Hide()
  for _, bf in ipairs(self.blockPool) do
    bf:Hide()
  end
  self.content:SetSize(1, 1)
  self.bar.SetTotal(0)
end

function Dossier:Refresh()
  if self.data then
    self:Layout()
  end
end

-- The host hides: every shown section with an `onHide` takes its own frames away (C4).
function Dossier:NotifyHide()
  if not self.data then
    return
  end
  for _, block in ipairs(self.data.blocks) do
    local def = block.def
    if def and def.onHide then
      ns.safecall(def.owner or ns.coreOwner, def.onHide, self.opts.host)
    end
  end
end

function Dossier:Expand(id)
  self.expanded[id] = true
  self:Layout()
end

-- The search box of the host: blocks keep only the rows that match (highlighted), empty blocks
-- and the links go while a query is set.
function Dossier:SetQuery(query)
  self.query = string.lower(string.gsub(tostring(query or ""), "^%s*(.-)%s*$", "%1"))
  if self.data then
    self:Layout()
  end
end

-- A row of a block or a link chip was clicked.
function Dossier:RowClick(row, button)
  if row.kind == "more" and row.onClick then
    row.onClick(row)
    return
  end
  if self.opts.onClick then
    self.opts.onClick(row, button, self)
    return
  end
  if row.onClick then
    row.onClick(row, button)
  elseif row.ref and button == "RightButton" and B.UI.EntityMenu then
    B.UI.EntityMenu(row.ref, nil, self.ctx)
  elseif row.ref then
    local action = B:GetPrimaryAction(row.ref, self.ctx)
    if action then
      B:RunAction(action.id, row.ref, self.ctx)
    end
  end
end

-- ---------------------------------------------------------------------------------------------
-- The band
-- ---------------------------------------------------------------------------------------------

local function labelWidth(fs, text)
  local w = fs:GetStringWidth() or 0
  if w == 0 then
    w = #(text or "") * 6
  end
  return w
end

local function bandButton(self, n)
  local b = self.buttons[n]
  if not b then
    b = S.button(self.band, "", 80, BUTTON_H)
    b:SetScript("OnClick", function(btn)
      if btn.onClick then
        btn.onClick()
      end
    end)
    self.buttons[n] = b
  end
  return b
end

-- Lays the band out for the card and returns its height.
function Dossier:LayoutBand(card, width)
  local band = self.band
  band:SetWidth(width)
  B.UI.PaintIcon(band.icon, card.icon)
  band.name:SetText(card.name or "")
  band.badge.label:SetText(card.typeLabel or "")
  local nameW = labelWidth(band.name, card.name)
  band.badge:SetWidth(labelWidth(band.badge.label, card.typeLabel) + 10)
  band.badge:ClearAllPoints()
  band.badge:SetPoint("LEFT", band.name, "LEFT", nameW + 8, 0)
  if self.previewing then
    band.preview:ClearAllPoints()
    band.preview:SetPoint("LEFT", band.badge, "RIGHT", 8, 0)
    band.preview:Show()
  else
    band.preview:Hide()
  end
  local x = ICON + 2 * PAD
  local y = PAD + 19
  local function line(fs, text)
    if text and text ~= "" then
      fs:SetText(text)
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", band, "TOPLEFT", x, -y)
      fs:SetPoint("RIGHT", band, "RIGHT", -PAD, 0)
      fs:Show()
      y = y + LINE_H
    else
      fs:Hide()
    end
  end
  line(band.meta, card.summary)
  line(band.status, Util.statusLine(card))
  line(band.worth, card.worth and card.worth.text and (L["worth"] .. " " .. card.worth.text))
  -- the actions as labelled buttons, wrapped by width (none in the Here column)
  local list = {}
  for _, a in ipairs(self.opts.here and {} or card.actions) do
    list[#list + 1] = {
      label = a.label,
      icon = a.icon,
      accent = a.active,
      enabled = a.enabled,
      onClick = function()
        if a.enabled ~= false then
          B:RunAction(a.id, card.ref, { source = self.ctx.source, button = "LeftButton" })
        end
      end,
    }
  end
  if self.opts.buttons and not self.opts.here then
    for _, extra in ipairs(self.opts.buttons(card.ref) or {}) do
      list[#list + 1] = extra
    end
  end
  local bx = x
  y = y + 3
  local maxX = width - PAD
  for i, a in ipairs(list) do
    local b = bandButton(self, i)
    b.onClick = a.onClick
    b.tip = a.tip or a.desc -- the button's explanation after the hover delay (Style.TipEnter)
    b.label:SetText((a.icon and B.UI.InlineTexture(a.icon, 12) or "") .. (a.label or ""))
    local col = a.accent and S.C.accent or S.C.text
    b.label:SetTextColor(col[1], col[2], col[3])
    b:SetEnabledFlat(a.enabled ~= false)
    local w = labelWidth(b.label, a.label) + 14
    if bx > x and bx + w > maxX then
      bx = x
      y = y + BUTTON_H + 4
    end
    b:SetWidth(w)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", band, "TOPLEFT", bx, -y)
    b:Show()
    bx = bx + w + 4
  end
  for i = #list + 1, #self.buttons do
    self.buttons[i]:Hide()
  end
  self.buttonCount = #list
  if #list > 0 then
    y = y + BUTTON_H
  end
  local h = math.max(y + PAD, ICON + 2 * PAD)
  band:SetHeight(h)
  band:Show()
  return h
end

-- ---------------------------------------------------------------------------------------------
-- The blocks
-- ---------------------------------------------------------------------------------------------

local function blockFrame(self, n)
  local bf = self.blockPool[n]
  if bf then
    return bf
  end
  bf = CreateFrame("Frame", nil, self.content)
  bf.title = S.text(bf, 11, S.C.dim)
  bf.title:SetPoint("TOPLEFT", bf, "TOPLEFT", 0, -3)
  bf.title:SetJustifyH("LEFT")
  bf.count = S.text(bf, 11, S.C.dim)
  bf.count:SetPoint("TOPRIGHT", bf, "TOPRIGHT", 0, -3)
  bf.count:SetJustifyH("RIGHT")
  bf.controls = {} -- the section's toggles on the title line (layoutControls)
  bf.line = S.fill(bf, S.C.line, "BORDER")
  bf.line:ClearAllPoints()
  bf.line:SetPoint("TOPLEFT", bf, "TOPLEFT", 0, -TITLE_H + 2)
  bf.line:SetPoint("TOPRIGHT", bf, "TOPRIGHT", 0, -TITLE_H + 2)
  bf.line:SetHeight(1)
  bf.tree = B.UI.Tree(bf, {
    flat = true,
    ctx = self.ctx,
    tooltip = self.opts.tooltip,
    iconsAlways = self.opts.iconsAlways, -- the row action icons on every row, not only on hover
    twoLine = self.opts.twoLine, -- rows with meta take two lines (the Here column, R2)
    worth = self.opts.worth, -- the host's worth switch (Browser setting, 23.10.2026)
    onHover = self.opts.onHover, -- the host's preview (ADR 0018 C)
    onClick = function(row, button)
      self:RowClick(row, button)
    end,
  })
  bf.tree.scroll:ClearAllPoints()
  bf.tree.scroll:SetPoint("TOPLEFT", bf, "TOPLEFT", 0, -TITLE_H - 2)
  self.blockPool[n] = bf
  return bf
end

-- Block controls: a section def
-- may carry `controls = function(host) -> { { label, on, tooltip, onClick }, ... }`; they draw as
-- small buttons on the title line, right of the title, accented while `on`.
local CONTROL_H = TITLE_H - 4

local function controlButton(bf, n)
  local b = bf.controls[n]
  if b then
    return b
  end
  b = S.button(bf, "", 40, CONTROL_H)
  S.setSize(b.label, 10)
  b:SetScript("OnClick", function(btn)
    if btn.control and btn.control.onClick then
      btn.control.onClick()
    end
  end)
  b.tip = function(btn) -- the control's explanation after the hover delay (Style.TipEnter)
    local c = btn.control
    return c and (c.tipTitle or c.label), c and c.tooltip
  end
  bf.controls[n] = b
  return b
end

local function layoutControls(self, bf, block)
  local def = block.def
  local controls = {}
  if def and def.controls then
    local ok, list = ns.safecall(def.owner or ns.coreOwner, def.controls, self.opts.host)
    if ok and type(list) == "table" then
      controls = list
    end
  end
  local x = labelWidth(bf.title, bf.title:GetText()) + 10
  for i, control in ipairs(controls) do
    local b = controlButton(bf, i)
    b.control = control
    b.label:SetText(control.label or "")
    local w = labelWidth(b.label, control.label) + 10
    b:SetWidth(w)
    local c = control.on and S.C.accent or S.C.dim
    b.label:SetTextColor(c[1], c[2], c[3])
    S.setEdges(b.edges, control.on and S.C.accent or S.C.line, control.on and 0.8 or nil)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", bf, "TOPLEFT", x, -1)
    b:Show()
    x = x + w + 4
  end
  for i = #controls + 1, #bf.controls do
    bf.controls[i]:Hide()
  end
end

-- Whether the rows show their worth (the host's `opts.worth`, as the Tree reads it).
function Dossier:WorthOn()
  local w = self.opts.worth
  if type(w) == "function" then
    w = w()
  end
  return w ~= false
end

-- The height a block needs at `width`: the title line, its shown rows, the padding.
function Dossier:BlockHeight(block, width)
  local rows = Util.shownRows(block, self.expanded[block.id], nil, self.query)
  local h = 0
  local Tree = B.UI.TreeUtil
  for _, row in ipairs(rows) do
    h = h + Tree.rowHeight(row, width, self.opts.twoLine or block.twoLine, self:WorthOn())
  end
  return TITLE_H + 2 + h + PAD
end

function Dossier:LayoutBlocks(blocks, width, top)
  local cols = Util.columns(width)
  local cellW = (width - (cols - 1) * GAP) / cols
  local query = self.query
  if query and query ~= "" then -- only the blocks with a match
    local kept = {}
    for _, block in ipairs(blocks) do
      if #Util.shownRows(block, true, nil, query) > 0 then
        kept[#kept + 1] = block
      end
    end
    blocks = kept
  end
  local placements, total = Util.grid(blocks, cols, cellW, GAP, function(block, w)
    return self:BlockHeight(block, w)
  end)
  for i, p in ipairs(placements) do
    local block = p.block
    local bf = blockFrame(self, i)
    bf.block = block
    bf.title:SetText(Util.caps(block.title))
    local id = block.id
    local rows, capped = Util.shownRows(block, self.expanded[id], function()
      self:Expand(id)
    end, query)
    bf.tree.query = query or ""
    -- the count: on every Here block (the title carries none since 22.10.2026, it showed twice)
    -- and on a capped block elsewhere
    if capped or (self.opts.here and block.count) then
      bf.count:SetText(tostring(block.count))
      bf.count:Show()
    else
      bf.count:Hide()
    end
    layoutControls(self, bf, block)
    bf:ClearAllPoints()
    bf:SetPoint("TOPLEFT", self.content, "TOPLEFT", p.x, -(top + p.y))
    bf:SetSize(p.w, p.h)
    bf.tree.scroll:SetSize(p.w, p.h - TITLE_H - 2 - PAD)
    bf.tree.opts.twoLine = self.opts.twoLine or block.twoLine -- per block since S7 (pooled frame)
    bf.tree.opts.table = block.table or nil -- per block too (ADR 0018 D)
    bf.tree:SetRows(rows)
    bf:Show()
    local def = block.def
    if def and def.onRender then -- the owner's own frames beside the rows (Quests' item bar, C4)
      ns.safecall(def.owner or ns.coreOwner, def.onRender, rows, self.opts.host)
    end
  end
  for i = #placements + 1, #self.blockPool do
    self.blockPool[i]:Hide()
    self.blockPool[i].block = nil
  end
  self.blockCount = #placements
  self.columns = cols
  return total
end

-- ---------------------------------------------------------------------------------------------
-- The links: one line per relation, the label left, chips flowing right
-- ---------------------------------------------------------------------------------------------

local function chipTooltip(chip)
  local row = chip.row
  if not (row and GameTooltip) then
    return
  end
  GameTooltip:SetOwner(chip, "ANCHOR_RIGHT")
  if row.tooltip then
    row.tooltip(GameTooltip, row)
  elseif row.ref then
    local e = B:Entity(row.ref)
    GameTooltip:AddLine(e:Name() or row.text or row.ref, 1, 1, 1)
    local summary = e:Summary()
    if summary then
      S.TipLine(GameTooltip, summary, "tipDim")
    end
  else
    return
  end
  GameTooltip:Show()
end

local function chip(self, n)
  local c = self.chipPool[n]
  if c then
    return c
  end
  c = S.button(self.links, "", 40, CHIP_H)
  c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  c:SetScript("OnClick", function(btn, button)
    if btn.row then
      self:RowClick(btn.row, button)
    end
  end)
  c:HookScript("OnEnter", chipTooltip)
  c:HookScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  self.chipPool[n] = c
  return c
end

local function relationLabel(self, n)
  local fs = self.labelPool[n]
  if fs then
    return fs
  end
  fs = S.text(self.links, 11, S.C.dim)
  fs:SetJustifyH("LEFT")
  fs:SetWidth(LABEL_W)
  self.labelPool[n] = fs
  return fs
end

-- The text of a link chip: the row's text, then its value in gold (the worth, C3).
function Util.chipText(row)
  local value = B.UI.FormatValue(row.value, row.valueKind)
  if value then
    return (row.text or "") .. "  " .. S.H.gold .. value .. "|r"
  end
  return row.text or ""
end

function Dossier:LayoutLinks(links, width, top)
  local region = self.links
  if #links == 0 or (self.query and self.query ~= "") then
    region:Hide()
    for _, c in ipairs(self.chipPool) do
      c:Hide()
    end
    return 0
  end
  region:ClearAllPoints()
  region:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -top)
  region:SetWidth(width)
  local y = TITLE_H + 2
  local chips, labels = 0, 0
  for _, link in ipairs(links) do
    labels = labels + 1
    local fs = relationLabel(self, labels)
    fs:SetText(Util.caps(link.relation or link.title))
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", region, "TOPLEFT", 0, -y - 2)
    fs:Show()
    local x = LABEL_W + 4
    local rows, capped = Util.shownRows(
      { id = link.id, rows = link.rows, limit = link.limit },
      self.expanded[link.id],
      function()
        self:Expand(link.id)
      end
    )
    for _, row in ipairs(rows) do
      chips = chips + 1
      local c = chip(self, chips)
      c.row = row
      c.label:SetText(Util.chipText(row))
      local col = row.kind == "more" and S.C.accent or S.C.text
      c.label:SetTextColor(col[1], col[2], col[3])
      local w = labelWidth(c.label, row.text) + 14
      if x > LABEL_W + 4 and x + w > width then
        x = LABEL_W + 4
        y = y + CHIP_H + CHIP_GAP
      end
      c:SetWidth(w)
      c:ClearAllPoints()
      c:SetPoint("TOPLEFT", region, "TOPLEFT", x, -y)
      c:Show()
      x = x + w + CHIP_GAP
    end
    link.capped = capped
    y = y + CHIP_H + CHIP_GAP
  end
  for i = chips + 1, #self.chipPool do
    self.chipPool[i]:Hide()
    self.chipPool[i].row = nil
  end
  for i = labels + 1, #self.labelPool do
    self.labelPool[i]:Hide()
  end
  self.chipCount = chips
  region:SetHeight(y)
  region:Show()
  return y
end

-- ---------------------------------------------------------------------------------------------
-- The trail: "TRAIL  Elwynn > Marshal Dughan > The Fargodeep Mine", the last one accented
-- ---------------------------------------------------------------------------------------------

local function trailButton(self, n)
  local b = self.trailPool[n]
  if b then
    return b
  end
  b = CreateFrame("Button", nil, self.trail)
  b:SetHeight(CHIP_H)
  b.label = S.text(b, 12)
  b.label:SetPoint("LEFT", 0, 0)
  b.label:SetJustifyH("LEFT")
  b:SetScript("OnClick", function(btn)
    if btn.item and self.onTrail then
      self.onTrail(btn.item)
    end
  end)
  b:SetScript("OnEnter", function(btn)
    btn.label:SetTextColor(S.C.accent[1], S.C.accent[2], S.C.accent[3])
  end)
  b:SetScript("OnLeave", function(btn)
    local c = btn.last and S.C.accent or S.C.text
    btn.label:SetTextColor(c[1], c[2], c[3])
  end)
  self.trailPool[n] = b
  return b
end

function Dossier:LayoutTrail(width, top)
  local list = self.trailList
  local region = self.trail
  if #list == 0 or (self.query and self.query ~= "") then
    region:Hide()
    for _, b in ipairs(self.trailPool) do
      b:Hide()
    end
    return 0
  end
  region:ClearAllPoints()
  region:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -top)
  region:SetWidth(width)
  -- the label keeps its own column on the left; every crumb line starts right of it (owner,
  -- 22.10.2026: label and crumbs fought for the first line)
  local x0 = labelWidth(region.label, L["trail"]) + 8
  local x, y = x0, 0
  for i, item in ipairs(list) do
    local b = trailButton(self, i)
    b.item = item
    b.last = i == #list
    b.label:SetText((i > 1 and "> " or "") .. (item.name or item.ref or "?"))
    local c = b.last and S.C.accent or S.C.text
    b.label:SetTextColor(c[1], c[2], c[3])
    local w = labelWidth(b.label, item.name) + 6
    if x > x0 and x + w > width then
      x, y = x0, y + CHIP_H
    end
    b:SetWidth(w)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", region, "TOPLEFT", x, -y)
    b:Show()
    x = x + w
  end
  for i = #list + 1, #self.trailPool do
    self.trailPool[i]:Hide()
  end
  self.trailCount = #list
  region:SetHeight(y + CHIP_H)
  region:Show()
  return y + CHIP_H
end

-- ---------------------------------------------------------------------------------------------
-- Layout: the band, the grid, the links, the trail, top to bottom
-- ---------------------------------------------------------------------------------------------

function Dossier:Layout()
  local data = self.data
  if not data then
    return
  end
  self.dirty = false
  local width = self:Width()
  local y = self:LayoutBand(data.card, width)
  local grid = self:LayoutBlocks(data.blocks, width, y + GAP)
  if grid > 0 then
    y = y + GAP + grid
  end
  local links = self:LayoutLinks(data.links, width, y + GAP)
  if links > 0 then
    y = y + GAP + links
  end
  local trail = self:LayoutTrail(width, y + PAD)
  if trail > 0 then
    y = y + PAD + trail
  end
  y = y + PAD
  self.height = y
  self.content:SetSize(math.max(1, width), math.max(1, y))
  self.bar.SetTotal(y)
  if self.opts.onRender then
    self.opts.onRender(self)
  end
end
