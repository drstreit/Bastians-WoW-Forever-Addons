-- UI kit: Bastians.UI.Dossier(parent, opts): one entity as a sheet (ADR 0054; the dossier of ADR
-- 0014 before it). On two pages when the host is wide: the figure and the facts left, the reading
-- right; in one column when narrow. The reading is the head (the type, the name, the lead, the
-- status words with the distance, the worth, the main buttons with More), a contents line, then the
-- registered detail sections as chapters in the type's reading order (each a titled list of rows,
-- capped with a "+N more" row that expands in place), and the sections marked `link` as relation
-- rows with chips. The Here column (`opts.here`) keeps the band and the block grid of ADR 0014.
-- Pooled frames, nothing built while hidden. The rows inside a block are a Tree in flat mode.
local _, ns = ...
local B = ns.B
local S = ns.Style
local L = ns.L

local GAP = 14 -- between grid cells and regions
local PAD = 6 -- inside the band and the blocks
local TITLE_H = 24 -- a block's title line (room for the block controls, row actions of 22 px)
local LINE_H = 15 -- a band text line
local BUTTON_H = 22
local CHIP_GAP = 4 -- between link chips; a chip is the kit's pill (ADR 0046), S.G.pill high
local TRAIL_H = 18 -- a trail entry
local LABEL_W = 70 -- the relation label of a link row
local ICON = 40
local PORTRAIT = 132 -- the 3D portrait of a creature or a wearable item (opts.portrait)
local DEFAULT_LIMIT = 5
local LINK_LIMIT = 8
local SHEET_MIN = 700 -- two pages from this width (ADR 0054)
local FIGURE_MIN, FIGURE_MAX = 220, 320 -- the figure's height on the left page
local READ_MAX = 680 -- the reading column is no wider: a line stays readable
local NAME_H = 28 -- the name's line on a sheet
local KIND_H = 20 -- the type line above it
local CHAPTER_H = 30 -- a chapter's heading
local CONTENTS_H = 22 -- a line of the contents
local CONTENTS_MIN = 3 -- chapters before a sheet gets a contents line
-- the main buttons a sheet shows: a type marks three, the chain and the voice line join them
-- where there is one
local MAIN_MAX = 5
-- a sheet of cards (ADR 0056)
local CARD_MIN = 280 -- a card's least width: two stand side by side from 2 * CARD_MIN + GAP
local CARD_ALL = 6 -- a part with this many things or fewer shows them all
local CARD_BEST = 4 -- a larger one shows its first few, and "All N"
local CARD_HEAD = 32 -- a card's title line
local CARD_FOOT = 28 -- the line of "All N"
local CARD_PAD = 8
local STATS_PER_LINE = 4 -- stat tiles to a line (ADR 0058)
local STAT_GAP = 6

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

-- The sheet's pages by the host's width (ADR 0054): two from SHEET_MIN (the figure a third of the
-- width, within its limits; the reading column beside it, no wider than READ_MAX), else one column
-- with the small portrait. -> two, the figure's height, the reading column's x and its width.
function Util.pages(width)
  if width < SHEET_MIN then
    return false, PORTRAIT, 0, width
  end
  local figure = math.max(FIGURE_MIN, math.min(FIGURE_MAX, math.floor(width * 0.34)))
  local x = figure + 2 * PAD + GAP
  return true, figure, x, math.min(READ_MAX, width - x)
end

-- The chapter a section sits in on a sheet of `entityType` (ADR 0054): `def.chapter` is a chapter
-- id, or a table of ids by entity type for a section that serves several; nil: a chapter of its own.
function Util.chapterOf(def, entityType)
  local chapter = def and def.chapter
  if type(chapter) == "table" then
    return chapter[entityType]
  end
  return chapter
end

-- The reading order of a type that declares none: its sections in their order, then the book's
-- pages and the player's notes, as on every other sheet.
Util.CHAPTERS = { { id = "book", tail = true }, { id = "notes", tail = true } }

-- The sheet's chapters (ADR 0054), pure. `catalogue` is the type's reading order ({ { id, title,
-- tail } }, Bastians:GetChapters; Util.CHAPTERS without one); a block carries `chapter` and
-- `order`. -> the chapters { id, title, blocks, count, own } that have a block: the catalogue's in
-- its order, then every block without a chapter (or with one the type does not know) as a chapter
-- of its own, then the catalogue's `tail` chapters (the book, the notes); and the blocks of the
-- reserved chapter "facts", which the sheet draws under the figure. Blocks keep their order
-- inside a chapter.
function Util.chapters(blocks, catalogue)
  local byId, listed, own, facts = {}, {}, {}, {}
  for i, entry in ipairs(catalogue or Util.CHAPTERS) do
    local chapter = {
      id = entry.id,
      title = entry.title,
      tail = entry.tail,
      tab = entry.tab, -- a tab of a tabbed sheet (ADR 0058)
      always = entry.always, -- there with nothing to show, saying `empty`
      empty = entry.empty,
      blocks = {},
      count = 0,
    }
    byId[entry.id] = chapter
    listed[i] = chapter
  end
  for _, block in ipairs(blocks) do
    if block.chapter == "facts" then
      facts[#facts + 1] = block
    else
      local chapter = block.chapter and byId[block.chapter]
      if not chapter then
        chapter = { id = block.id, title = block.title, blocks = {}, count = 0, own = true }
        own[#own + 1] = chapter
      end
      chapter.blocks[#chapter.blocks + 1] = block
      chapter.count = chapter.count + (block.count or 0)
    end
  end
  local out = {}
  local function listedChapters(tail)
    for _, chapter in ipairs(listed) do
      if (#chapter.blocks > 0 or chapter.always) and (chapter.tail or false) == tail then
        chapter.title = chapter.title or (chapter.blocks[1] and chapter.blocks[1].title)
        out[#out + 1] = chapter
      end
    end
  end
  listedChapters(false)
  for _, chapter in ipairs(own) do
    out[#out + 1] = chapter
  end
  listedChapters(true)
  return out, facts
end

-- Tabs (ADR 0058, PH5): a type whose reading order marks chapters `tab` reads one chapter at a
-- time: Overview (every chapter without the mark, and the facts) first, then a tab per marked
-- chapter in the order's order; an `always` chapter is there with nothing to show. -> the list
-- { { id, title, chapters } }, or nil for a sheet without tabs.
function Util.tabs(chapters)
  local any = false
  for _, ch in ipairs(chapters) do
    if ch.tab then
      any = true
    end
  end
  if not any then
    return nil
  end
  local overview = { id = "overview", title = L["Overview"], chapters = {} }
  local out = { overview }
  for _, ch in ipairs(chapters) do
    if ch.tab then
      out[#out + 1] = { id = ch.id, title = ch.title, chapters = { ch }, count = ch.count }
    else
      overview.chapters[#overview.chapters + 1] = ch
    end
  end
  return out
end

-- The rows of a block of facts as tiles (ADR 0058, `block.stats`): a row with a value is a tile
-- (its text the label, the value the figure, the note under it), and so is a row that says
-- `stat = true` with no value (the tile reads unknown); the rest stay rows.
function Util.statRows(block)
  local tiles, rest = {}, {}
  for _, row in ipairs(block.rows or {}) do
    if row.value ~= nil or row.stat then
      local value = row.value
      if value == nil then
        value = nil -- unknown
      elseif row.valueKind == "money" then
        value = B.UI.Money(value)
      else
        value = tostring(value)
      end
      tiles[#tiles + 1] = { label = row.text, value = value, note = row.note, row = row }
    else
      rest[#rest + 1] = row
    end
  end
  return tiles, rest
end

-- The sheet's lead (ADR 0054): the type's own sentence, else the summary, then the status words;
-- every part ends as a sentence. nil when there is nothing to say.
function Util.lead(card, own)
  local parts = {}
  for _, text in ipairs({ own or card.summary or false, card.status or false }) do
    if type(text) == "string" then
      text = string.gsub(text, "^%s*(.-)%s*$", "%1")
      if text ~= "" then
        local plain = string.gsub(text, "|r$", "")
        if not string.find(plain, "[%.%!%?]$") then
          text = text .. "."
        end
        parts[#parts + 1] = text
      end
    end
  end
  return #parts > 0 and table.concat(parts, " ") or nil
end

-- The sheet's buttons (ADR 0054): the actions marked `main`, at most `max` (three), in their order;
-- with none marked, the first ones. -> main, more (every other action, for the More menu).
function Util.mainActions(actions, max)
  max = max or 3
  local marked = false
  for _, a in ipairs(actions) do
    if a.main then
      marked = true
      break
    end
  end
  local main, more = {}, {}
  for _, a in ipairs(actions) do
    if #main < max and (a.main or not marked) then
      main[#main + 1] = a
    else
      more[#more + 1] = a
    end
  end
  return main, more
end

-- The dossier of an entity as data: the card (Bastians.UI.Card), the blocks and the links from the
-- registered sections (core-contracts §7). A section marked `link` lands in the links; the section
-- marked `card` with a single row is the band's status line and no block; every other section is a
-- block with its `block` options (`columns` cells wide, `wide` = the whole row, `limit` rows shown).
-- For the sheet (ADR 0054) the same blocks are also grouped: `chapters` and `facts` (Util.chapters),
-- with `lead`, and the card's actions split into `main` and `more`.
function B.UI.DossierData(ref, sections, ctx, opts)
  sections = sections or B:GetDetailSections(ref)
  local card = B.UI.Card(ref, ctx, sections)
  local blocks, links = {}, {}
  local entityType, entityId = B.Entity.Parse(ref)
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
        stats = b.stats or false, -- the rows with a value as stat tiles (ADR 0058)
        limit = b.limit or DEFAULT_LIMIT,
        count = #s.rows,
        folded = def.collapsed or false, -- a group that opens on a click (the sheet, ADR 0054)
        chapter = Util.chapterOf(def, entityType),
        order = def.order or 50,
      }
    end
  end
  local chapters, facts = Util.chapters(blocks, B:GetChapters(entityType, entityId))
  local main, more = Util.mainActions(card.actions, MAIN_MAX)
  return {
    ref = ref,
    card = card,
    blocks = blocks,
    links = links,
    chapters = chapters,
    facts = facts,
    lead = Util.lead(card, entityType and B:Entity(ref):Lead() or nil),
    main = main,
    more = more,
  }
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

-- A section title: in capitals, in its own case over an ornament (ADR 0034, ADR 0038).
function Util.titleText(text)
  if S.Ornaments() then
    return tostring(text or "")
  end
  return Util.caps(text)
end

-- The rule under a section title: the 1 px line, or the gold ornament (`ornaments`), no wider
-- than its texture.
function Util.rule(line, orn, width)
  if S.Ornaments() then
    line:Hide()
    orn:SetWidth(math.min(width, 256))
    orn:Show()
  else
    orn:Hide()
    line:Show()
  end
end

-- Whether a row or one of its descendants matches the query (a text or a compiled query, ADR
-- 0045).
local function matches(row, query)
  if B.Query.Of(query):MatchLower(B.UI.TreeUtil.searchText(row), row) then
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
  if query and query ~= "" and not B.Query.Of(query).empty then
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

-- The band's status line: the status words, the travel time (or distance), or both.
function Util.statusLine(card)
  local dist = card.away
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
--         cards = true (ADR 0056: the chapters as cards with tiles, nothing folds; a card with
--         more than six things shows four and "All N", which calls onChapter(chapter, dossier),
--         else opens the rest in place),
--         here = true (C4: the Here column, the `here` sections only, a band without buttons;
--         every other dossier is a sheet, ADR 0054),
--         host (handed to a section's own `onRender(rows, host)` and `onHide(host)`, C4) }
Dossier.MARGIN = 8

local function create(parent, opts, palette)
  local self = setmetatable({
    palette = palette,
    folds = {},
    parent = parent,
    opts = opts,
    ctx = opts.ctx or { source = "dossier" },
    expanded = {},
    blockPool = {},
    cardPool = {},
    chapterPool = {},
    contentsPool = {},
    chipPool = {},
    labelPool = {},
    buttons = {},
    data = nil,
    dirty = false,
  }, Dossier)

  local frame = CreateFrame("Frame", nil, parent)
  -- a margin from the host's left edge (the Browser's page text touched
  -- the separator)
  frame:SetPoint("TOPLEFT", Dossier.MARGIN, 0)
  frame:SetPoint("BOTTOMRIGHT", -14, 0)
  self.frame = frame
  self:LayPaper()
  local scroll = CreateFrame("ScrollFrame", nil, frame)
  scroll:SetAllPoints(frame)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)
  self.scroll, self.content = scroll, content
  self.bar = S.scrollbar(scroll, frame, function()
    self:PlaceLeft() -- the figure and the facts stay while the reading scrolls
  end)
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
  if opts.here then
    S.panel(band, S.C.panel) -- the Here column's band; a sheet's head stands on the page itself
  end
  band.icon = band:CreateTexture(nil, "ARTWORK")
  band.icon:SetSize(ICON, ICON)
  band.icon:SetPoint("TOPLEFT", band, "TOPLEFT", PAD, -PAD)
  -- the heading font (ADR 0038), larger on a sheet
  band.name = S.heading(band, opts.here and 16 or 21, opts.here and 19 or 25, S.C.accent)
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
  -- the summary in the Here column; a sheet's lead
  band.meta = S.text(band, opts.here and 12 or 13, opts.here and S.C.dim or S.C.text)
  band.meta:SetJustifyH("LEFT")
  band.meta:SetJustifyV("TOP")
  band.status = S.text(band, 12, S.C.text)
  band.status:SetJustifyH("LEFT")
  band.worth = S.text(band, 12, S.C.gold)
  band.worth:SetJustifyH("LEFT")
  -- round 4 (ADR 0038): a 2 px line on top in the subject's colour (the Here column), a glow
  -- behind the plate
  band.top = S.fill(band, S.C.accent, "OVERLAY")
  band.top:ClearAllPoints()
  band.top:SetPoint("TOPLEFT", band, "TOPLEFT", 0, 0)
  band.top:SetPoint("TOPRIGHT", band, "TOPRIGHT", 0, 0)
  band.top:SetHeight(2)
  band.glow = band:CreateTexture(nil, "BACKGROUND", nil, 1)
  band.glow:SetTexture(S.GLOW)
  band.glow:Hide()
  band.top:SetShown(opts.here and true or false)
  band:Hide()
  self.band = band
  if opts.portrait then
    self:BuildPortrait()
  end

  -- the links region
  local links = CreateFrame("Frame", nil, content)
  links.title = S.heading(links, 11, 13, S.C.dim)
  links.title:SetPoint("TOPLEFT", links, "TOPLEFT", 0, -3)
  links.line = S.fill(links, S.C.line, "BORDER")
  links.line:ClearAllPoints()
  links.line:SetPoint("TOPLEFT", links, "TOPLEFT", 0, -TITLE_H + 3)
  links.line:SetPoint("TOPRIGHT", links, "TOPRIGHT", 0, -TITLE_H + 3)
  links.line:SetHeight(1)
  links.orn = S.ornament(links)
  links.orn:SetPoint("LEFT", links.line, "LEFT", 0, 0)
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

-- The palette a sheet draws in (ADR 0054): the Parchment theme's on paper (the skin's
-- `sheetParchment`, on by default), nil for the look's own colours and for the Here column. The
-- fonts are the ones the player chose in the options, on paper too.
local function sheetPalette(opts)
  if not opts.here and S.Skin("sheetParchment") ~= false then
    return S.Palette("parchment")
  end
  return nil
end

function B.UI.Dossier(parent, opts)
  opts = opts or {}
  local palette = sheetPalette(opts)
  return S.WithPalette(palette, create, parent, opts, palette)
end

-- The page of a sheet on parchment (ADR 0054): the paper to the host's edges and every widget
-- below in the paper's palette; in the look's colours no paper and the theme.
function Dossier:LayPaper()
  local frame = self.frame
  frame.palette = self.palette
  if self.palette and not self.paper then
    local paper = frame:CreateTexture(nil, "BACKGROUND")
    paper:SetTexture(S.PARCHMENT, "REPEAT", "REPEAT")
    paper:SetHorizTile(true)
    paper:SetVertTile(true)
    paper:SetPoint("TOPLEFT", frame, "TOPLEFT", -Dossier.MARGIN, 0)
    paper:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 14, 0)
    self.paper = paper
  end
  if self.paper then
    self.paper:SetShown(self.palette ~= nil)
  end
end

-- The skin's choice changed (`sheetParchment`): the page takes the other palette at its next
-- subject or layout, without a reload. True when it changed.
function Dossier:SyncPaper()
  local want = sheetPalette(self.opts)
  if want == self.palette then
    return false
  end
  local from = self.palette
  self.palette = want
  self:LayPaper()
  for _, bf in ipairs(self.blockPool) do
    bf.tree.palette = want
  end
  S.Repalette(self.frame, from, want)
  return true
end

-- The sections of `ref` built in the page's palette: a section writes colour codes into its
-- texts (S.H), and on paper they must be the paper's. A host that fetches the sections itself
-- asks here, not the registry.
function Dossier:Sections(ref)
  self:SyncPaper()
  return S.WithPalette(self.palette, B.GetDetailSections, B, ref)
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
    self.folds = {}
    self.tab = nil -- a tabbed sheet opens on its overview (ADR 0058)
    -- a page opened in the Browser sounds like one (ADR 0034); a hovered row's preview does not
    if ref and self.opts.portrait and not (opts and opts.preview) and self.frame:IsVisible() then
      B.UI.Scenery.PageSound(ref)
    end
  end
  self.ref = ref
  self.previewing = opts and opts.preview or false
  self:SyncPaper()
  -- in the page's palette: the card's words and a section built here carry colour codes
  self.data =
    S.WithPalette(self.palette, B.UI.DossierData, ref, sections, ctx or self.ctx, { here = self.opts.here })
  if self.frame:IsVisible() then
    self:Layout()
  else
    self.dirty = true
  end
end

function Dossier:Clear()
  self.ref, self.data, self.dirty = nil, nil, false
  self:LeaveSheet()
  self.band:Hide()
  self.links:Hide()
  self.trail:Hide()
  for _, bf in ipairs(self.blockPool) do
    bf:Hide()
  end
  for _, head in ipairs(self.chapterPool) do
    head:Hide()
  end
  for _, card in ipairs(self.cardPool) do
    card:Hide()
  end
  for _, b in ipairs(self.contentsPool) do
    b:Hide()
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

-- Whether a query narrows the page (the host's filter, R2): then a page of cards shows only the
-- things that match, of every tab, without its head, its pictures and an app's sheet.
function Dossier:Searching()
  local q = self.query
  return q ~= nil and q ~= "" and not B.Query.Of(q).empty
end

-- The search box of the host: blocks keep only the rows that match (highlighted), empty blocks
-- and the links go while a query is set.
function Dossier:SetQuery(query)
  self.query = string.gsub(tostring(query or ""), "^%s*(.-)%s*$", "%1")
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
    -- a declared action (ADR 0046): the registered action's icon and label, drawn by the look
    b = S.action(self.band, {
      label = "",
      row = true,
      boxed = true,
      onClick = function(btn)
        if btn.onClick then
          btn.onClick()
        end
      end,
    })
    self.buttons[n] = b
  end
  return b
end

-- ---------------------------------------------------------------------------------------------
-- The stage: one subject on
-- a dark plate. A creature (an NPC, a quest's giver), an item's own model (weapons, shields, helms,
-- ...) or its icon large, a zone's painting with the explored areas. Dragging turns a model, a
-- click opens the showcase; while a model loads three dots pulse. The band's portrait and the
-- showcase window are each a stage.
-- ---------------------------------------------------------------------------------------------

local Stage = {}
Stage.__index = Stage
Stage.LOAD_TIMEOUT = 2.5 -- seconds the dots pulse at most (a model that never reports)
Stage.CLICK_PX = 4 -- a press that moves less is a click

-- The quest's giver: the first creature of the quest's starters in Data (a quest an object or an
-- item starts has none).
local function questGiver(id)
  local d = B:GetService("data")
  local r = d and d:Get("quest", tonumber(id))
  for _, ref in ipairs(r and r.starts or {}) do
    local kind, npc = B.Entity.Parse(ref)
    if kind == "npc" then
      return npc
    end
  end
  return nil
end
Stage.QuestGiver = questGiver

local function pulse(stage, elapsed)
  stage.t = (stage.t or 0) + elapsed
  for i, dot in ipairs(stage.dots) do
    dot:SetAlpha(0.25 + 0.75 * math.max(0, math.sin(stage.t * 5 - i * 0.9)))
  end
  if stage.t > Stage.LOAD_TIMEOUT then
    stage:Loaded()
  end
end

function B.UI.Stage(parent)
  local stage = setmetatable({ art = {}, scene = {} }, Stage)
  local plate = CreateFrame("Frame", nil, parent)
  plate.bg = S.roundFill(plate, S.C.header, "radiusSmall")
  plate.edges = S.roundEdges(plate, S.C.line, "radiusSmall")
  plate:EnableMouse(true) -- a painting or an icon opens the showcase too
  plate:SetScript("OnMouseUp", function()
    if stage.onClick then
      stage.onClick(stage.ref)
    end
  end)
  stage.frame = plate
  stage.icon = plate:CreateTexture(nil, "ARTWORK")
  stage.icon:SetPoint("CENTER")
  stage.icon:Hide()
  stage.dots = {}
  for i = 1, 3 do
    local dot = plate:CreateTexture(nil, "OVERLAY")
    dot:SetTexture(S.DISC)
    dot:SetSize(8, 8)
    S.tint(dot, S.C.accent)
    dot:SetPoint("CENTER", plate, "CENTER", (i - 2) * 14, 0)
    dot:Hide()
    stage.dots[i] = dot
  end
  local model = B.Compat.NewModel(plate) -- none on a client without model frames: the rest still shows
  if model then
    model:SetPoint("TOPLEFT", 2, -2)
    model:SetPoint("BOTTOMRIGHT", -2, 2)
    model:EnableMouse(true)
    model:SetScript("OnMouseDown", function(m)
      local x = GetCursorPosition()
      m.turnFrom, m.pressedAt = x, x
      m:SetScript("OnUpdate", function(me)
        local cx = GetCursorPosition()
        me.facing = (me.facing or 0) + (cx - me.turnFrom) / 80
        me.turnFrom = cx
        me:SetFacing(me.facing)
      end)
    end)
    model:SetScript("OnMouseUp", function(m)
      m:SetScript("OnUpdate", nil) -- turns only while the button is held
      local x = GetCursorPosition()
      if m.pressedAt and math.abs(x - m.pressedAt) < Stage.CLICK_PX and stage.onClick then
        stage.onClick(stage.ref)
      end
      m.pressedAt = nil
    end)
    model:SetScript("OnModelLoaded", function(m)
      stage:Loaded()
      B.UI.Scenery.Greet(m) -- the creature greets once it is there (ADR 0034)
    end)
    B.UI.Scenery.Animate(model)
    model:Hide()
    stage.model = model
  end
  plate:Hide()
  return stage
end

function Stage:Loading()
  self.t = 0
  for _, dot in ipairs(self.dots) do
    dot:Show()
  end
  -- pulses only while a model loads (CLAUDE.md golden rule 7)
  self.frame:SetScript("OnUpdate", function(_, elapsed)
    pulse(self, elapsed)
  end)
end

-- The model reports it loaded (or the dots waited long enough): the dots go. ~~The first report
-- put the subject once more~~ (28.10.2026: with the plate sized first the newest subject stays,
-- and the second put left some models empty, owner retail).
function Stage:Loaded()
  for _, dot in ipairs(self.dots) do
    dot:Hide()
  end
  self.frame:SetScript("OnUpdate", nil)
end

-- Puts a model subject on a plate of `size`: the plate gets its size before the model its
-- subject, a model set on a frame of no size stays empty (the showcase
-- showed no model, the small plate sometimes none).
function Stage:PutModel(apply, facing, size)
  local model = self.model
  self.frame:SetSize(size, size)
  model:Show()
  if not apply(model) then
    model:Hide()
    return false
  end
  model.facing = facing
  model:SetFacing(facing)
  self:Loading()
  return true
end

-- The zone's painting at `height`, as wide as its aspect asks but no wider than `maxWidth` (then
-- lower: the showcase showed only part of it, ): the art layer's tiles and the
-- areas the character explored over them (Coords.MapArt), as the game's map draws the zone.
-- Returns the width and the height it takes.
function Stage:PutPainting(uiMapID, height, maxWidth)
  local art = B.Coords.MapArt(tonumber(uiMapID))
  if not art then
    return nil
  end
  if maxWidth and height * art.width / art.height > maxWidth then
    height = math.floor(maxWidth * art.height / art.width + 0.5)
  end
  local width = math.floor(height * art.width / art.height + 0.5)
  -- in the chosen map style where there is one (ADR 0056, PA6)
  local styled = B.UI.Scenery.DrawInset(self.frame, self.art, tonumber(uiMapID), width - 4, height - 4, 2, 2)
  B.UI.Scenery.MarkPlayer(self.frame, tonumber(uiMapID), width - 4, height - 4, 2, 2)
  if styled then
    return width, height
  end
  local k = (height - 4) / art.height
  local n = 0
  local function draw(t, sublevel)
    n = n + 1
    local tex = self.art[n]
    if not tex then
      tex = self.frame:CreateTexture(nil, "ARTWORK")
      self.art[n] = tex
    end
    tex:SetTexture(t.file)
    tex:SetTexCoord(0, t.tcRight, 0, t.tcBottom)
    tex:SetDrawLayer("ARTWORK", sublevel)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 2 + t.px1 * k, -(2 + t.py1 * k))
    tex:SetSize(math.max(1, (t.px2 - t.px1) * k), math.max(1, (t.py2 - t.py1) * k))
    tex:Show()
  end
  for _, t in ipairs(art.tiles) do
    draw(t, 0)
  end
  for _, t in ipairs(art.explored) do
    draw(t, t.top and 2 or 1)
  end
  for i = n + 1, #self.art do
    self.art[i]:Hide()
  end
  return width, height
end

-- An area on its zone's painting: a cut
-- around its place, wide enough for its radius, and a soft disc over the area; nil without art.
Stage.AREA_MIN_SPAN, Stage.AREA_MAX_SPAN = 0.12, 0.5
function Stage:PutArea(id, size)
  local place = B.UI.Scenery.FirstPlace("area:" .. id)
  self.areaArt = self.areaArt or {}
  local d = B:GetService("data")
  local r = d and d:Get("area", tonumber(id))
  if not place then
    return nil
  end
  local c1, x1, y1 = B.Coords.ToWorld(place.map, 0, 0.5)
  local c2, x2, y2 = B.Coords.ToWorld(place.map, 1, 0.5)
  local mapYards = (c1 and c1 == c2) and math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2) or nil
  local radius = r and r.r
  local span = B.UI.Scenery.CUT_SPAN
  if mapYards and mapYards > 0 and radius then
    span = math.max(Stage.AREA_MIN_SPAN, math.min(Stage.AREA_MAX_SPAN, 2.6 * radius / mapYards))
  end
  local px, py =
    B.UI.Scenery.DrawCut(self.frame, self.areaArt, place.map, place.x, place.y, size, size, span, 1, true)
  if not px then
    return nil
  end
  if not self.areaDisc then
    self.areaDisc = self.frame:CreateTexture(nil, "ARTWORK")
    self.areaDisc:SetTexture(S.DISC)
  end
  local discPx = (mapYards and radius) and (radius / (mapYards * span) * size * 2) or size * 0.3
  S.tint(self.areaDisc, S.C.accent, 0.3)
  self.areaDisc:SetSize(discPx, discPx)
  self.areaDisc:ClearAllPoints()
  self.areaDisc:SetPoint("CENTER", self.frame, "TOPLEFT", px, -py)
  self.areaDisc:Show()
  return size
end

-- The zone's painting behind a creature (the skin's `diorama`, ADR 0034): a cut around its first
-- place, dimmed; nil or the switch off clears it.
function Stage:PutScene(npcID, size)
  local place = npcID and B.UI.Scenery.FirstPlace("npc:" .. npcID)
  if place and S.Skin("diorama") then
    local Scenery = B.UI.Scenery
    Scenery.DrawCut(
      self.frame,
      self.scene,
      place.map,
      place.x,
      place.y,
      size,
      size,
      Scenery.DIORAMA_SPAN,
      Scenery.DIORAMA_ALPHA
    )
    return
  end
  for _, tex in ipairs(self.scene) do
    tex:Hide()
  end
end

-- A creature on the stage, with its scenery and its greeting waiting for the model to load.
function Stage:PutCreature(npcID, size)
  if not self:PutModel(function(m)
    return B.Compat.ShowCreature(m, npcID)
  end, -0.3, size) then
    self:PutScene(nil, size)
    return nil
  end
  self.model.isCreature = true
  self.model.pendingGreeting = B.UI.Scenery.GreetingFor(npcID)
  self:PutScene(npcID, size)
  return size
end

-- Shows the subject at `height` (a painting no wider than `maxWidth`); `icon` is the entity's icon
-- for an item without a model. Returns the width it takes, or nil when there is nothing to show
-- (the caller keeps its small icon).
function Stage:Show(ref, height, icon, maxWidth)
  local kind, id = B.Entity.Parse(ref)
  self.ref = ref
  self:Loaded()
  if self.model then
    self.model:Hide()
  end
  self.icon:Hide()
  B.UI.Scenery.UnmarkPlayer(self.frame)
  for _, tex in ipairs(self.art) do
    tex:Hide()
  end
  for _, tex in ipairs(self.areaArt or {}) do
    tex:Hide()
  end
  if self.areaDisc then
    self.areaDisc:Hide()
  end
  if self.model then
    self.model.isCreature = nil
    B.UI.Scenery.StopMotion(self.model) -- the old subject's emotes end here
  end
  if kind == "recipe" then
    -- a recipe shows what it makes
    local d = B:GetService("data")
    local r = d and d:Get("recipe", id)
    if r and r.item then
      kind, id = "item", r.item
      icon = B:Entity("item:" .. r.item):Icon() or icon
    end
  end
  local width, creature
  if kind == "zone" then
    width, height = self:PutPainting(id, height, maxWidth)
  elseif kind == "area" then
    width = self:PutArea(id, height)
  elseif self.model and kind == "npc" then
    creature = id
  elseif self.model and kind == "quest" then
    creature = questGiver(id)
  elseif kind == "item" then
    if
      self.model
      and self:PutModel(function(m)
        return B.Compat.ShowItem(m, id)
      end, 0.6, height)
    then
      width = height
    elseif icon then
      -- an item without a model of its own: its icon, large
      B.UI.PaintIcon(self.icon, icon)
      self.icon:SetSize(height * 0.6, height * 0.6)
      self.icon:Show()
      width = height
    end
  end
  if creature then
    width = self:PutCreature(creature, height)
  else
    self:PutScene(nil, height)
  end
  if width then
    self.frame:SetSize(width, height)
    self.frame:Show()
  else
    self.frame:Hide()
  end
  return width
end

-- ---------------------------------------------------------------------------------------------
-- The showcase: the subject large in a window of its own ("a click on the
-- 3D model should open a larger window, hard to see currently"); the wheel zooms a model.
-- ---------------------------------------------------------------------------------------------

-- Several showcases: the newest follows the page the Browser shows;
-- Ctrl+click on the portrait opens another one, and the older ones stay as they are.
local showcases = {} -- in the order they were made; the last is the one that follows
local Showcase = { OFFSET = 30 } -- a new window's step down and right from the newest

local function showcaseDB(n)
  local p = ns.core and ns.core.db and ns.core.db.profile
  if not p then
    return {}
  end
  p.showcase = type(p.showcase) == "table" and p.showcase or {}
  if n == 1 then
    return p.showcase -- the first keeps its place and size
  end
  return {}
end

local function fill(win)
  -- the window's height less its title bar and a margin (the content's own height resolves late)
  local h = math.max(100, (win.frame:GetHeight() or 600) - 30 - 12)
  local maxW = math.max(100, (win.frame:GetWidth() or 560) - 12)
  local w = win.stage:Show(win.ref, math.min(h, maxW), win.icon, maxW)
  if w then
    win.stage.frame:ClearAllPoints()
    win.stage.frame:SetPoint("TOP", win.content, "TOP", 0, -6)
  end
end

local function newShowcase()
  local n = #showcases + 1
  local win
  win = B.UI.Window(n == 1 and "BastiansShowcase" or ("BastiansShowcase" .. n), {
    title = "",
    width = 560,
    height = 600,
    minWidth = 260,
    minHeight = 260,
    maxWidth = B.UI.NO_LIMIT,
    maxHeight = B.UI.NO_LIMIT,
    db = showcaseDB(n),
    onResize = function(_, sizing)
      if not sizing and win.ref then
        fill(win)
      end
    end,
  })
  win.stage = B.UI.Stage(win.content)
  win.zoom = 1
  win.content:EnableMouseWheel(true)
  win.content:SetScript("OnMouseWheel", function(_, delta)
    win.zoom = math.max(0.3, math.min(2, win.zoom - delta * 0.1))
    B.Compat.ZoomModel(win.stage.model, win.zoom)
  end)
  local last = showcases[#showcases]
  if last and last.frame:IsShown() then
    win.frame:ClearAllPoints()
    win.frame:SetPoint("TOPLEFT", last.frame, "TOPLEFT", Showcase.OFFSET, -Showcase.OFFSET)
  end
  showcases[n] = win
  return win
end

local function put(win, ref, name, icon)
  win.ref, win.icon = ref, icon
  win:SetTitle(name or ref)
  win:Show()
  win.zoom = 1
  fill(win)
  B.Compat.ZoomModel(win.stage.model, 1)
end

-- Shows the subject large: in the newest showcase, or with `new` (Ctrl+click) in another one
-- (reusing a closed one) that becomes the newest.
function B.UI.Showcase(ref, name, icon, new)
  if not ref then
    return nil
  end
  local win = showcases[#showcases]
  if new and win and win.frame:IsShown() then
    win = nil
    for i, w in ipairs(showcases) do
      if not w.frame:IsShown() then
        win = table.remove(showcases, i) -- a closed one comes back as the newest
        showcases[#showcases + 1] = win
        break
      end
    end
  end
  win = win or newShowcase()
  put(win, ref, name, icon)
  return win
end

-- The page changed: the newest showcase follows when it shows (the older ones stay).
function B.UI.ShowcaseFollow(ref, name, icon)
  local win = showcases[#showcases]
  if win and win.frame:IsShown() and ref and win.ref ~= ref then
    put(win, ref, name, icon)
  end
end

-- The newest showcase, and all of them (for the tests).
function B.UI.ShowcaseWindow()
  return showcases[#showcases]
end

function B.UI.Showcases()
  return showcases
end

-- The band's stage: built once when the host asks for portraits.
function Dossier:BuildPortrait()
  local stage = B.UI.Stage(self.band)
  stage.frame:SetPoint("TOPLEFT", self.band, "TOPLEFT", PAD, -PAD)
  stage.onClick = function(ref)
    -- a zone's painting opens the zone on the map; the rest the showcase
    if B.Entity.Parse(ref) == "zone" and B:GetAction("map.zone") then
      B:RunAction("map.zone", ref, { source = "dossier" })
      return
    end
    if B.Entity.Parse(ref) == "area" and B:GetAction("map.show") then
      B:RunAction("map.show", ref, { source = "dossier" }) -- an area's cut: its place on the map
      return
    end
    local card = self.data and self.data.card
    B.UI.Showcase(ref, card and card.name, card and card.icon, IsControlKeyDown and IsControlKeyDown())
  end
  self.band.portrait = stage.frame
  self.band.stage = stage
end

-- Shows the subject on the portrait at `size` (a painting no wider than `maxWidth`); the plate's
-- width, or nil (the head keeps its small icon).
function Dossier:ShowPortrait(ref, icon, size, maxWidth)
  local stage = self.band.stage
  if not (stage and ref) then
    return nil
  end
  return stage:Show(ref, size or PORTRAIT, icon, maxWidth)
end

-- Lays the head out for the card and returns its height and the page's geometry { two, x, w (the
-- reading column), figure, left (where the left page goes on under the figure) }. In the Here
-- column it is the band of ADR 0014: a panel, the small icon, the name with its badge, no buttons.
-- On a sheet (ADR 0054) the figure stands large at the left and the head is the top of the reading
-- column: the type, the name, the lead (the type's own sentence, else the summary), the status
-- words, the worth, then the main buttons, More with every other action, and the host's own.
function Dossier:LayoutBand(card, width, data)
  local band = self.band
  local here = self.opts.here
  band:SetWidth(width)
  local two, figure, readX, readW = false, PORTRAIT, 0, width
  if not here then
    two, figure, readX, readW = Util.pages(width)
  end
  local plateW = self.opts.portrait
      and not here
      and self:ShowPortrait(card.ref, card.icon, figure, two and figure or nil)
    or nil
  if two and not plateW then -- nothing to show large: one column with the small icon
    two, figure, readX, readW = false, PORTRAIT, 0, math.min(width, READ_MAX)
  end
  if self.opts.portrait and not here and not self.previewing then
    B.UI.ShowcaseFollow(card.ref, card.name, card.icon) -- the newest showcase follows the page
  end
  local side = plateW or ICON
  -- the subject's colour (ADR 0038): the line on top, the plate's edge and the glow behind it
  local token = S.KindToken(B.UI.IconKind(card.icon))
  local roleCol = token and S.C[token] or S.C.accent
  S.tint(band.top, roleCol)
  local stage = band.stage
  if stage then
    S.setEdges(stage.frame.edges, roleCol, plateW and 0.7 or nil)
  end
  if plateW and stage then
    local spread = two and 1.3 or 1.9 -- a large figure needs less of it
    band.glow:ClearAllPoints()
    band.glow:SetPoint("CENTER", stage.frame, "CENTER", 0, 0)
    band.glow:SetSize(plateW * spread, plateW * spread)
    S.tint(band.glow, roleCol, 0.45)
    band.glow:Show()
  else
    band.glow:Hide()
  end
  band.icon:SetShown(plateW == nil)
  B.UI.PaintIcon(band.icon, card.icon)
  local x = two and readX or (side + 2 * PAD)
  local right = two and (readX + readW) or (width - PAD)
  band.name:SetText(card.name or "")
  band.badge.label:SetText(card.typeLabel or "")
  band.badge:SetWidth(labelWidth(band.badge.label, card.typeLabel) + 10)
  band.name:ClearAllPoints()
  band.badge:ClearAllPoints()
  local y
  if here then
    band.name:SetPoint("TOPLEFT", band, "TOPLEFT", x, -PAD)
    band.badge:SetPoint("LEFT", band.name, "LEFT", labelWidth(band.name, card.name) + 8, 0)
    y = PAD + 19
  else -- the type above the name
    band.badge:SetPoint("TOPLEFT", band, "TOPLEFT", x, -PAD)
    band.name:SetPoint("TOPLEFT", band, "TOPLEFT", x, -(PAD + KIND_H))
    y = PAD + KIND_H + NAME_H
  end
  if self.previewing then
    band.preview:ClearAllPoints()
    band.preview:SetPoint("LEFT", band.badge, "RIGHT", 8, 0)
    band.preview:Show()
  else
    band.preview:Hide()
  end
  local function line(fs, text, wrap)
    if text and text ~= "" then
      fs:SetText(text)
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", band, "TOPLEFT", x, -y)
      fs:SetWidth(math.max(40, right - x))
      local h = LINE_H
      if wrap then -- the lead may take more than one line
        fs:SetWordWrap(true)
        h = math.max(LINE_H, math.ceil(fs:GetStringHeight() or 0)) + 2
      end
      fs:Show()
      y = y + h
    else
      fs:Hide()
    end
  end
  local lead = card.summary
  if not here and card.ref and B.Entity.Parse(card.ref) then
    lead = B:Entity(card.ref):Lead() or lead
  end
  line(band.meta, lead, not here)
  line(band.status, Util.statusLine(card))
  line(band.worth, card.worth and card.worth.text and (L["worth"] .. " " .. card.worth.text))
  -- the buttons, wrapped by width (none in the Here column): the main actions, More, the host's
  local list = {}
  if not here then
    -- where a mini map shows, it is the Map button (ADR 0056); the action stays in More
    local mapped = self.opts.cards and data and self:ShowsMiniMap(data)
    for _, a in ipairs(data and data.main or card.actions) do
      if not (mapped and Util.MAP_ACTIONS[a.id]) then
        list[#list + 1] = {
          label = a.label,
          icon = a.icon,
          accent = a.active,
          enabled = a.enabled,
          tip = a.tip,
          onClick = function()
            if a.enabled ~= false then
              B:RunAction(a.id, card.ref, { source = self.ctx.source, button = "LeftButton" })
            end
          end,
        }
      end
    end
    if data and #data.more > 0 then
      list[#list + 1] =
        { label = L["More"], icon = "more", menu = true, tip = L["Every action for this subject"] }
    end
    if self.opts.buttons then
      for _, extra in ipairs(self.opts.buttons(card.ref) or {}) do
        list[#list + 1] = extra
      end
    end
  end
  local bx = x
  y = y + 3
  for i, a in ipairs(list) do
    local b = bandButton(self, i)
    if a.menu then -- every action that is not a main button (and the main ones too): the entity menu
      b.onClick = function()
        B.UI.EntityMenu(card.ref, b, self.ctx)
      end
    else
      b.onClick = a.onClick
    end
    b.tip = a.tip or a.desc -- the button's explanation after the hover delay (Style.TipEnter)
    b.spec.icon = a.icon
    b.spec.label = a.label or ""
    b.spec.on = a.accent or nil
    b:Fit()
    b:SetEnabledFlat(a.enabled ~= false)
    local w = b:GetWidth() or 80
    if bx > x and bx + w > right then
      bx = x
      y = y + BUTTON_H + 4
    end
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
  -- on two pages the head ends under its buttons and the figure may reach lower beside it
  local h = two and (y + PAD) or math.max(y + PAD, (plateW and figure or ICON) + 2 * PAD)
  band:SetHeight(h)
  band:Show()
  local stageH = plateW and stage and stage.frame:GetHeight() or 0
  return h,
    {
      two = two,
      x = two and readX or 0,
      w = two and readW or (here and width or math.min(width, READ_MAX)),
      figure = figure,
      left = two and (PAD + stageH + GAP) or nil,
    }
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
  bf.title = S.heading(bf, 11, 13, S.C.dim)
  bf.title:SetPoint("TOPLEFT", bf, "TOPLEFT", 0, -6)
  bf.title:SetJustifyH("LEFT")
  bf.count = S.text(bf, 11, S.C.dim)
  bf.count:SetPoint("TOPRIGHT", bf, "TOPRIGHT", 0, -6)
  bf.count:SetJustifyH("RIGHT")
  bf.controls = {} -- the section's toggles on the title line (layoutControls)
  -- on a sheet a titled block folds on a click on its title line; the mark says which way
  bf.mark = S.text(bf, 12, S.C.dim)
  bf.mark:SetPoint("TOPRIGHT", bf, "TOPRIGHT", 0, -6)
  bf.fold = CreateFrame("Button", nil, bf)
  bf.fold:SetPoint("TOPLEFT", bf, "TOPLEFT", 0, 0)
  bf.fold:SetPoint("TOPRIGHT", bf, "TOPRIGHT", 0, 0)
  bf.fold:SetHeight(TITLE_H)
  bf.fold:SetScript("OnClick", function()
    if bf.block then
      self:ToggleFold(bf.block)
    end
  end)
  bf.line = S.fill(bf, S.C.line, "BORDER")
  bf.line:ClearAllPoints()
  bf.line:SetPoint("TOPLEFT", bf, "TOPLEFT", 0, -TITLE_H + 2)
  bf.line:SetPoint("TOPRIGHT", bf, "TOPRIGHT", 0, -TITLE_H + 2)
  bf.line:SetHeight(1)
  bf.orn = S.ornament(bf) -- the WoW look's gilt rule (ornaments, Util.rule)
  bf.orn:SetPoint("LEFT", bf.line, "LEFT", 0, 0)
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
-- row actions (ADR 0046) on the title line, right of the title, `on` while on.
local function controlButton(bf, n)
  local b = bf.controls[n]
  if b then
    return b
  end
  b = S.action(bf, {
    label = "",
    row = true,
    boxed = true,
    onClick = function(btn)
      if btn.control and btn.control.onClick then
        btn.control.onClick()
      end
    end,
  })
  S.setSize(b.label, 10)
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
    b.spec.label = control.label or ""
    b.spec.on = control.on or nil
    S.Draw(b)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", bf, "TOPLEFT", x, 0)
    b:Show()
    x = x + b:GetWidth() + 4
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

Util.MAP_ACTIONS = { ["map.show"] = true, ["map.zone"] = true }

-- Whether a page shows a mini map: a block of them, or the thing is a zone or an area, whose
-- figure is its map and opens it on a click.
function Dossier:ShowsMiniMap(data)
  local typ = data.ref and B.Entity.Parse(data.ref)
  if typ == "zone" or typ == "area" then
    return true
  end
  for _, chapter in ipairs(data.chapters or {}) do
    for _, block in ipairs(chapter.blocks) do
      if self:CellBlock(block) == "maps" then
        return true
      end
    end
  end
  return false
end

-- The block as its cells show it (ADR 0034): the mode ("places" or nil for rows) and the block.
function Dossier:CellBlock(block)
  local Scenery = B.UI.Scenery
  return Scenery and Scenery.BlockMode(block) or nil, block
end

-- Whether a block is folded to its title line: the player's click on this page, else the
-- section's own word (`collapsed`). Never in the Here column, and never under a query.
function Dossier:Folded(block)
  if self.opts.here or (self.query and self.query ~= "") then
    return false
  end
  local own = self.folds[block.id]
  if own ~= nil then
    return own
  end
  return block.folded or false
end

function Dossier:ToggleFold(block)
  self.folds[block.id] = not self:Folded(block)
  self:Layout()
end

-- Whether the rows of a block with `meta` take two lines: always on a sheet, where a row says one
-- thing per line as in My quests (not in a small table); in the Here column as the host asks.
function Dossier:TwoLine(block)
  if self.opts.twoLine or block.twoLine then
    return true
  end
  return not self.opts.here and not block.table
end

-- The height a block needs at `width`: the title line (none on a `bare` block, whose chapter's
-- heading names it), its shown rows, the padding; a folded block is its title line.
function Dossier:BlockHeight(block, width, bare)
  local head = bare and 0 or TITLE_H
  if not bare and self:Folded(block) then
    return TITLE_H
  end
  if block.stats then
    -- the facts as tiles (ADR 0058): four to a line, the rows without a value under them
    local tiles, rest = Util.statRows(block)
    local lines = math.ceil(#tiles / STATS_PER_LINE)
    local h = head + 2 + lines * (S.STAT_H + STAT_GAP)
    local Tree = B.UI.TreeUtil
    for _, row in ipairs(rest) do
      h = h + Tree.rowHeight(row, width, self:TwoLine(block), self:WorthOn())
    end
    return h + PAD
  end
  local mode, shown = self:CellBlock(block)
  if mode == "floors" then
    local rows = Util.shownRows(shown, self.expanded[block.id], nil, self.query)
    return head + 4 + B.UI.Scenery.FloorsHeight(rows, width) + PAD
  elseif mode == "maps" then
    return head + 4 + B.UI.Scenery.MapsHeight(Util.mapRows(block, self.query), width) + PAD
  elseif mode then
    local rows = Util.shownRows(shown, self.expanded[block.id], nil, self.query)
    return head + 4 + B.UI.Scenery.CellsHeight(mode, #rows, width) + PAD
  end
  local rows = Util.shownRows(block, self.expanded[block.id], nil, self.query)
  local h = 0
  local Tree = B.UI.TreeUtil
  for _, row in ipairs(rows) do
    h = h + Tree.rowHeight(row, width, self:TwoLine(block), self:WorthOn())
  end
  return head + 2 + h + PAD
end

-- Draws `block` in the i-th block frame at x, y of the content, w by h px.
function Dossier:PutBlock(i, block, x, y, w, h, bare)
  local query = self.query
  local bf = blockFrame(self, i)
  local head = bare and 0 or TITLE_H
  bf.block = block
  bf.bare = bare or false
  bf.title:SetText(Util.titleText(block.title))
  bf.title:SetShown(not bare)
  if bare then
    bf.line:Hide()
    bf.orn:Hide()
  else
    Util.rule(bf.line, bf.orn, w)
  end
  local id = block.id
  local mode, shown = self:CellBlock(block)
  local rows, capped = Util.shownRows(shown, self.expanded[id], function()
    self:Expand(id)
  end, query)
  bf.tree.query = query or ""
  local foldable = not bare and not self.opts.here
  local folded = foldable and self:Folded(block)
  bf.fold:SetShown(foldable)
  bf.mark:SetShown(foldable)
  bf.mark:SetText(folded and "+" or "-")
  bf.count:ClearAllPoints()
  bf.count:SetPoint("TOPRIGHT", bf, "TOPRIGHT", foldable and -14 or 0, -6)
  if folded then
    rows, capped, mode = {}, true, nil -- the title line alone, with the count of what it holds
  end
  -- the count: on every Here block (the title carries none since 22.10.2026, it showed twice)
  -- and on a capped block elsewhere; a bare block's count is in its chapter's heading
  if not bare and (capped or (self.opts.here and block.count)) then
    bf.count:SetText(tostring(block.count))
    bf.count:Show()
  else
    bf.count:Hide()
  end
  if bare then
    for _, control in ipairs(bf.controls) do
      control:Hide()
    end
  else
    layoutControls(self, bf, block)
  end
  bf:ClearAllPoints()
  bf:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, -y)
  bf:SetSize(w, h)
  local statH = 0
  if block.stats and not folded then
    local tiles, rest = Util.statRows(block)
    statH = self:PutStats(bf, tiles, w, head + 2)
    rows = rest
  elseif bf.statPool then
    for _, t in ipairs(bf.statPool) do
      t:Hide()
    end
  end
  bf.tree.scroll:ClearAllPoints()
  bf.tree.scroll:SetPoint("TOPLEFT", bf, "TOPLEFT", 0, -head - 2 - statH)
  bf.tree.scroll:SetSize(w, math.max(1, h - head - 2 - statH - PAD))
  bf.tree.opts.twoLine = self:TwoLine(block) -- per block since S7 (pooled frame)
  bf.tree.opts.table = block.table or nil -- per block too (ADR 0018 D)
  bf.tree.opts.tiles, bf.tree.opts.entityNames = nil, nil -- a card's tiles drew here before
  if mode == "maps" then
    rows = Util.mapRows(block, self.query) -- a mini map shows every place, not the first few
  end
  if mode then
    -- place cuts instead of rows (ADR 0034)
    bf.tree:SetRows({})
    bf.tree.scroll:Hide()
    B.UI.Scenery.RenderCells(bf, mode, rows, w, head + 4, self)
  else
    if bf.cells then
      B.UI.Scenery.HideCells(bf)
    end
    bf.tree.scroll:Show()
    bf.tree:SetRows(rows)
  end
  bf.mode = mode
  bf:Show()
  local def = block.def
  if def and def.onRender then -- the owner's own frames beside the rows (Quests' item bar, C4)
    ns.safecall(def.owner or ns.coreOwner, def.onRender, rows, self.opts.host)
  end
end

-- The tiles of a block of facts (ADR 0058): up to four to a line at the block's width; a tile
-- with a thing behind its row opens it. Returns the height they take.
function Dossier:PutStats(bf, tiles, w, top)
  bf.statPool = bf.statPool or {}
  local n = #tiles
  local per = math.min(STATS_PER_LINE, math.max(1, n))
  local tileW = math.floor((w - STAT_GAP * (per - 1)) / per)
  for i, it in ipairs(tiles) do
    local t = bf.statPool[i]
    if not t then
      t = S.stat(bf, {})
      bf.statPool[i] = t
    end
    local row = it.row
    t:SetStat({
      label = it.label,
      value = it.value,
      note = it.note,
      unknown = L["unknown"],
      onClick = row.ref and function()
        self:RowClick(row, "LeftButton")
      end or nil,
    })
    local line, col = math.floor((i - 1) / per), (i - 1) % per
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", bf, "TOPLEFT", col * (tileW + STAT_GAP), -(top + line * (S.STAT_H + STAT_GAP)))
    t:SetWidth(math.max(60, tileW))
    t:Show()
  end
  for i = n + 1, #bf.statPool do
    bf.statPool[i]:Hide()
  end
  return math.ceil(n / per) * (S.STAT_H + STAT_GAP)
end

local function hideBlocksFrom(self, n)
  for i = n, #self.blockPool do
    self.blockPool[i]:Hide()
    self.blockPool[i].block = nil
  end
end

-- Whether a block has a row to show under the host's query (every block without one).
local function blockMatches(block, query)
  return not (query and query ~= "") or #Util.shownRows(block, true, nil, query) > 0
end

-- The Here column's blocks in a grid (ADR 0014); the height they take.
function Dossier:LayoutBlocks(blocks, width, top)
  local cols = Util.columns(width)
  local cellW = (width - (cols - 1) * GAP) / cols
  local kept = {}
  for _, block in ipairs(blocks) do
    if blockMatches(block, self.query) then -- only the blocks with a match
      kept[#kept + 1] = block
    end
  end
  local placements, total = Util.grid(kept, cols, cellW, GAP, function(block, w)
    return self:BlockHeight(block, w)
  end)
  for i, p in ipairs(placements) do
    self:PutBlock(i, p.block, p.x, top + p.y, p.w, p.h)
  end
  hideBlocksFrom(self, #placements + 1)
  self.blockCount = #placements
  self.columns = cols
  return total
end

-- ---------------------------------------------------------------------------------------------
-- The sheet's reading column (ADR 0054): the contents line, the chapters
-- ---------------------------------------------------------------------------------------------

local function chapterHead(self, n)
  local head = self.chapterPool[n]
  if head then
    return head
  end
  head = CreateFrame("Frame", nil, self.content)
  head:SetHeight(CHAPTER_H)
  head.title = S.heading(head, 15, 18, S.C.bright)
  head.title:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 0, 7)
  head.title:SetJustifyH("LEFT")
  head.count = S.text(head, 11, S.C.dim)
  head.count:SetJustifyH("LEFT")
  head.line = S.fill(head, S.C.line, "BORDER")
  head.line:ClearAllPoints()
  head.line:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 0, 2)
  head.line:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", 0, 2)
  head.line:SetHeight(1)
  head.orn = S.ornament(head) -- the WoW look's gilt rule (ornaments, Util.rule)
  head.orn:SetPoint("LEFT", head.line, "LEFT", 0, 0)
  self.chapterPool[n] = head
  return head
end

local function contentsButton(self, n)
  local b = self.contentsPool[n]
  if b then
    return b
  end
  b = S.action(self.content, {
    label = "",
    row = true,
    onClick = function(btn)
      self:ScrollToChapter(btn.chapter)
    end,
  })
  S.setSize(b.label, 11)
  self.contentsPool[n] = b
  return b
end

-- The count a chapter's heading shows: its rows where there is more than one; nil for a chapter
-- of its own whose section writes the count into its title already ("To do here  3").
function Util.chapterCount(chapter)
  if (chapter.count or 0) <= 1 then
    return nil
  end
  local def = chapter.own and chapter.blocks[1] and chapter.blocks[1].def
  if def and type(def.title) == "function" then
    return nil
  end
  return chapter.count
end

-- A chapter's words on the contents line: its title and its count.
function Util.contentsText(chapter)
  local title = string.gsub(tostring(chapter.title or ""), "%s+$", "")
  local count = Util.chapterCount(chapter)
  if count then
    return title .. "  " .. S.H.dim .. count .. "|r"
  end
  return title
end

-- The contents line: one quiet button per chapter, wrapped by width; a click scrolls there. A
-- sheet with fewer than CONTENTS_MIN chapters has none. Returns its height.
function Dossier:LayoutContents(chapters, x, width, top)
  local n = #chapters >= CONTENTS_MIN and #chapters or 0
  local bx, y = 0, 0
  for i = 1, n do
    local b = contentsButton(self, i)
    b.chapter = i
    b.spec.label = Util.contentsText(chapters[i])
    b:Fit()
    local w = b:GetWidth() or 60
    if bx > 0 and bx + w > width then
      bx = 0
      y = y + CONTENTS_H
    end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", self.content, "TOPLEFT", x + bx, -(top + y))
    b:Show()
    bx = bx + w + 6
  end
  for i = n + 1, #self.contentsPool do
    self.contentsPool[i]:Hide()
  end
  return n > 0 and (y + CONTENTS_H) or 0
end

-- Scrolls the sheet to its i-th shown chapter.
function Dossier:ScrollToChapter(i)
  local y = self.chapterY and self.chapterY[i]
  if y then
    self.bar.ScrollTo(math.max(0, y - PAD))
  end
end

-- The sheet under its head: the facts under the figure on two pages, the contents line, then
-- every chapter with its heading and its blocks one under the other; in one column the facts
-- follow the chapters. A chapter of one block shows no block title; the heading names it and
-- carries its count. Under a query only the blocks with a match stay. Returns where the sheet ends.
function Dossier:LayoutSheet(data, geo, head)
  local query = self.query
  local x, w = geo.x, geo.w
  local n = 0 -- block frames in use
  local y = head
  local left = geo.left
  self.leftBlocks = {}
  if geo.two then
    for _, block in ipairs(data.facts) do
      if blockMatches(block, query) then
        n = n + 1
        local h = self:BlockHeight(block, geo.figure, true)
        self:PutBlock(n, block, PAD, left, geo.figure, h, true)
        self.leftBlocks[#self.leftBlocks + 1] = { frame = self.blockPool[n], y = left }
        left = left + h
      end
    end
  end
  self.leftHeight = geo.two and left or nil
  local chapters = {}
  for _, chapter in ipairs(data.chapters) do
    local kept = {}
    for _, block in ipairs(chapter.blocks) do
      if blockMatches(block, query) then
        kept[#kept + 1] = block
      end
    end
    if #kept > 0 then
      chapters[#chapters + 1] = { chapter = chapter, blocks = kept }
    end
  end
  local shown = {}
  for i, entry in ipairs(chapters) do
    shown[i] = entry.chapter
  end
  local contents = self:LayoutContents(shown, x, w, y + 2)
  if contents > 0 then
    y = y + 2 + contents
  end
  self.chapterY = {}
  for i, entry in ipairs(chapters) do
    local chapter = entry.chapter
    local ch = chapterHead(self, i)
    y = y + (i == 1 and 2 or PAD)
    self.chapterY[i] = y
    ch:ClearAllPoints()
    ch:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, -y)
    ch:SetWidth(w)
    ch.title:SetText(tostring(chapter.title or ""))
    Util.rule(ch.line, ch.orn, w)
    local count = Util.chapterCount(chapter)
    if count then
      ch.count:ClearAllPoints()
      ch.count:SetPoint("BOTTOMLEFT", ch, "BOTTOMLEFT", labelWidth(ch.title, chapter.title) + 8, 8)
      ch.count:SetText(tostring(count))
      ch.count:Show()
    else
      ch.count:Hide()
    end
    ch.chapter = chapter
    ch:Show()
    y = y + CHAPTER_H
    local first = entry.blocks[1]
    local bare = #entry.blocks == 1 and not (first.def and first.def.controls)
    for _, block in ipairs(entry.blocks) do
      n = n + 1
      local h = self:BlockHeight(block, w, bare)
      self:PutBlock(n, block, x, y, w, h, bare)
      y = y + h
    end
  end
  for i = #chapters + 1, #self.chapterPool do
    self.chapterPool[i]:Hide()
    self.chapterPool[i].chapter = nil
  end
  if not geo.two then
    -- one column: the facts end the reading under their own titles, so the first chapter stays the
    -- first thing read (ADR 0052: a quest says what to do first)
    for _, block in ipairs(data.facts) do
      if blockMatches(block, query) then
        n = n + 1
        local h = self:BlockHeight(block, w)
        self:PutBlock(n, block, x, y + PAD, w, h)
        y = y + PAD + h
      end
    end
  end
  hideBlocksFrom(self, n + 1)
  self.blockCount = n
  self.chapterCount = #chapters
  self.columns = nil
  self.pages = geo.two and 2 or 1
  local links = self:LayoutLinks(data.links, w, y + GAP, x)
  if links > 0 then
    y = y + GAP + links
  end
  local trail = self:LayoutTrail(w, y + PAD, x)
  if trail > 0 then
    y = y + PAD + trail
  end
  return math.max(y, left or 0)
end

-- ---------------------------------------------------------------------------------------------
-- The sheet as cards (ADR 0056, `opts.cards`): every chapter a card, its things as tiles
-- ---------------------------------------------------------------------------------------------

-- The rows of a block without their groups (ADR 0056: nothing folds on a sheet): a row with
-- children gives its children, in order.
function Util.leaves(rows, out)
  out = out or {}
  for _, row in ipairs(rows or {}) do
    if row.children and #row.children > 0 then
      Util.leaves(row.children, out)
    else
      out[#out + 1] = row
    end
  end
  return out
end

-- The leaves of a block as rows of their own: a card's tree writes its depth and ids into them,
-- and the section's rows may stand nested in another tree at the same time (the Here column).
local cardLeaves

-- The same for a host that lists a chapter's things itself (the Browser stepping inside).
function Util.things(block)
  return cardLeaves(block)
end

function cardLeaves(block)
  local leaves = block.leaves
  if not leaves then
    leaves = {}
    for _, row in ipairs(Util.leaves(block.rows)) do
      leaves[#leaves + 1] = setmetatable({}, { __index = row })
    end
    block.leaves = leaves
  end
  return leaves
end

-- A chapter as a card, pure. `special(block)` says which blocks keep their own drawing (a small
-- table, places and floors as pictures); every other block is a part of rows, its things (the
-- rows with a ref) drawn as tiles. With more than CARD_ALL things in all, the card shows the
-- first CARD_BEST and is `capped`: "All N" opens the rest. `expanded` and a query show everything
-- (the query: what matches). A chapter of several blocks labels its parts.
-- -> { parts = { { block, rows | nil, special, label } }, things, capped, wide }
function Util.card(chapter, special, expanded, query)
  local searching = query and query ~= "" and not B.Query.Of(query).empty
  local parts, things, wide = {}, 0, false
  local labelled = #chapter.blocks > 1
  for _, block in ipairs(chapter.blocks) do
    if special and special(block) then
      if not searching or #Util.shownRows(block, true, nil, query) > 0 then
        parts[#parts + 1] = { block = block, special = true, label = labelled }
        wide = true
      end
    else
      local rows = {}
      for _, row in ipairs(cardLeaves(block)) do
        if not searching or matches(row, query) then
          rows[#rows + 1] = row
          if row.ref then
            things = things + 1
          elseif row.kind == "para" then
            wide = true -- running text reads at the page's width
          end
        end
      end
      if #rows > 0 then
        parts[#parts + 1] = { block = block, rows = rows, label = labelled }
      end
    end
  end
  local capped = things > CARD_ALL and not expanded and not searching
  if capped then
    local left, kept = CARD_BEST, {}
    for _, part in ipairs(parts) do
      if part.special then
        kept[#kept + 1] = part
      elseif left > 0 then
        local rows = {}
        for _, row in ipairs(part.rows) do
          if left == 0 then
            break
          end
          rows[#rows + 1] = row
          if row.ref then
            left = left - 1
          end
        end
        kept[#kept + 1] = { block = part.block, rows = rows, label = part.label }
      end
    end
    parts = kept
  end
  return { parts = parts, things = things, capped = capped, wide = wide }
end

-- The rows a block of mini maps draws: every place, or what a query keeps.
function Util.mapRows(block, query)
  if query and query ~= "" then
    return Util.shownRows(block, true, nil, query)
  end
  return block.rows
end

-- Whether a block keeps its own drawing on a card: a small table, or places and floors.
function Dossier:SpecialBlock(block)
  return block.table == true or block.stats == true or self:CellBlock(block) ~= nil
end

-- The tab row of a tabbed sheet (ADR 0058): one button per tab, the chosen one filled, flowing
-- into more lines at the page's width. Returns the height it takes.
local function tabButton(self, n)
  local b = self.tabPool[n]
  if b then
    return b
  end
  b = S.action(self.content, { label = "", boxed = true, row = true })
  b:SetScript("OnClick", function(btn)
    if btn.tabId then
      self:SetTab(btn.tabId)
    end
  end)
  self.tabPool[n] = b
  return b
end

function Dossier:LayoutTabs(tabs, x, w, top)
  self.tabPool = self.tabPool or {}
  local cx, cy, rowH = 0, 0, S.G.actionRow
  for i, tab in ipairs(tabs) do
    local b = tabButton(self, i)
    b.tabId = tab.id
    local count = tab.count and tab.count > 0 and tab.count or nil
    b.spec.label = count and (tostring(tab.title) .. "  " .. count) or tostring(tab.title)
    b.spec.primary = (tab.id == self.tabId) or nil
    b:Fit()
    local bw = b:GetWidth() or 60
    if cx > 0 and cx + bw > w then
      cx, cy = 0, cy + rowH + 4
    end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", self.content, "TOPLEFT", x + cx, -(top + cy))
    b:Show()
    cx = cx + bw + 4
  end
  for i = #tabs + 1, #self.tabPool do
    self.tabPool[i]:Hide()
    self.tabPool[i].tabId = nil
  end
  self.tabCount = #tabs
  return cy + rowH
end

-- Opens a tab of a tabbed sheet.
function Dossier:SetTab(id)
  self.tab = id
  self:Layout()
end

-- The tabs the sheet reads with, or nil (Util.tabs over the chapters).
function Dossier:Tabs()
  return self.data and Util.tabs(self.data.chapters) or nil
end

local function cardFrame(self, n)
  local card = self.cardPool[n]
  if card then
    return card
  end
  card = CreateFrame("Frame", nil, self.content)
  card.plate = S.roundFill(card, S.C.card, "radius")
  card.edge = S.roundEdges(card, S.C.cardEdge, "radius")
  card.title = S.heading(card, 14, 16, S.C.bright)
  card.title:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -8)
  card.title:SetJustifyH("LEFT")
  card.count = S.text(card, 11, S.C.dim)
  card.count:SetJustifyH("LEFT")
  card.all = S.action(card, {
    label = "",
    row = true,
    boxed = true,
    onClick = function()
      local chapter = card.chapter
      if not chapter then
        return
      end
      if self.opts.onChapter then
        self.opts.onChapter(chapter, self) -- the host steps inside (ADR 0056)
      else
        self:Expand("card:" .. tostring(chapter.id))
      end
    end,
  })
  card.all:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", CARD_PAD, CARD_PAD - 2)
  self.cardPool[n] = card
  return card
end

-- Draws a card's part of rows in the i-th block frame: its things as tiles, a label above them
-- where the chapter has several parts. Returns the height it takes.
function Dossier:PutTiles(i, part, x, y, w)
  local block = part.block
  local bf = blockFrame(self, i)
  local controls = block.def and block.def.controls
  local head = (part.label or controls) and TITLE_H or 0
  bf.block = block
  bf.bare = head == 0
  bf.title:SetText(Util.titleText(block.title))
  bf.title:SetShown(head > 0)
  bf.line:Hide()
  bf.orn:Hide()
  bf.fold:Hide()
  bf.mark:Hide()
  bf.count:Hide()
  if head > 0 and controls then
    layoutControls(self, bf, block)
  else
    for _, control in ipairs(bf.controls) do
      control:Hide()
    end
  end
  if bf.cells then
    B.UI.Scenery.HideCells(bf)
  end
  local opts = bf.tree.opts
  opts.tiles, opts.entityNames, opts.twoLine, opts.table = true, true, true, nil
  local Tree = B.UI.TreeUtil
  local h = 0
  for _, row in ipairs(part.rows) do
    h = h + Tree.rowHeight(row, w, true, self:WorthOn(), true)
  end
  bf:ClearAllPoints()
  bf:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, -y)
  bf:SetSize(w, head + h)
  bf.tree.query = self.query or ""
  bf.tree.scroll:ClearAllPoints()
  bf.tree.scroll:SetPoint("TOPLEFT", bf, "TOPLEFT", 0, -head)
  bf.tree.scroll:SetSize(w, math.max(1, h))
  bf.tree.scroll:Show()
  bf.tree:SetRows(part.rows)
  bf.mode = "tiles"
  bf:Show()
  local def = block.def
  if def and def.onRender then -- the owner's own frames beside the rows (Quests' item bar, C4)
    ns.safecall(def.owner or ns.coreOwner, def.onRender, part.rows, self.opts.host)
  end
  return head + h
end

-- The sheet under its head as cards: the facts under the figure on two pages, then every chapter
-- a card in the page's width, two side by side where they fit (a card goes where the page is
-- shorter; one with running text, a table or pictures takes the whole width); in one column the
-- facts follow the cards. Nothing folds. Returns where the sheet ends.
function Dossier:LayoutCards(data, geo, head, covered)
  local query = self.query
  local x = geo.x
  local w = math.max(120, self:Width() - x - PAD) -- the cards take the page, not a reading column
  local n = 0 -- block frames in use
  local left = geo.left
  self.leftBlocks = {}
  if geo.two then
    for _, block in ipairs(data.facts) do
      if blockMatches(block, query) then
        n = n + 1
        local h = self:BlockHeight(block, geo.figure, true)
        self:PutBlock(n, block, PAD, left, geo.figure, h, true)
        self.leftBlocks[#self.leftBlocks + 1] = { frame = self.blockPool[n], y = left }
        left = left + h
      end
    end
  end
  self.leftHeight = geo.two and left or nil
  local cols = w >= 2 * CARD_MIN + GAP and 2 or 1
  local colW = math.floor((w - (cols - 1) * GAP) / cols)
  -- a tabbed sheet (ADR 0058): the tab row, then the chosen tab's chapters alone
  local chapterList = data.chapters
  local top0 = head + 2
  local searching = self:Searching()
  local tabs = not searching and Util.tabs(data.chapters) or nil -- the filter looks in every tab
  if tabs then
    local chosen = tabs[1]
    for _, tab in ipairs(tabs) do
      if tab.id == self.tab then
        chosen = tab
      end
    end
    self.tabId = chosen.id
    top0 = top0 + self:LayoutTabs(tabs, x, w, top0) + 6
    chapterList = chosen.chapters
  elseif self.tabPool then
    for _, b in ipairs(self.tabPool) do
      b:Hide()
    end
    self.tabId, self.tabCount = nil, 0
  end
  local colY = {}
  for c = 1, cols do
    colY[c] = top0
  end
  local cards = 0
  self.cards = {}
  for _, whole in ipairs(chapterList) do
    local chapter = whole
    if whole.always and #whole.blocks == 0 then
      -- a tab with nothing to show says so (ADR 0058: "No attunement needed")
      chapter = {
        id = whole.id,
        title = whole.title,
        count = 0,
        blocks = {
          {
            id = "empty:" .. tostring(whole.id),
            title = whole.title,
            rows = { { id = "empty", kind = "para", text = whole.empty or "" } },
            span = 1,
            wide = true,
            limit = 1,
            count = 0,
          },
        },
      }
    end
    if covered then
      -- a hosted sheet says some sections itself: the chapter keeps the others
      local kept = {}
      for _, block in ipairs(whole.blocks) do
        if not covered[block.id] then
          kept[#kept + 1] = block
        end
      end
      if #kept < #whole.blocks then
        chapter =
          { id = whole.id, title = #kept > 0 and kept[1].title or whole.title, blocks = kept, count = 0 }
        if whole.title and not whole.own and kept[1] and whole.blocks[1] == kept[1] then
          chapter.title = whole.title
        end
        for _, block in ipairs(kept) do
          chapter.count = chapter.count + (block.count or 0)
        end
      end
    end
    if searching then
      -- the things alone: a card's maps and floors (its pictures) stand back while filtering
      local kept = {}
      for _, block in ipairs(chapter.blocks) do
        if not self:CellBlock(block) then
          kept[#kept + 1] = block
        end
      end
      if #kept < #chapter.blocks then
        chapter = { id = chapter.id, title = chapter.title, blocks = kept, count = chapter.count }
      end
    end
    local model = Util.card(chapter, function(block)
      return self:SpecialBlock(block)
    end, self.expanded["card:" .. tostring(chapter.id)], query)
    if #model.parts > 0 then
      cards = cards + 1
      local card = cardFrame(self, cards)
      local col, cw = 1, colW
      local top = colY[1]
      if cols > 1 and model.wide then
        cw = w
        top = math.max(colY[1], colY[2])
      elseif cols > 1 and colY[2] < colY[1] then
        col, top = 2, colY[2]
      end
      local cx = x + (col - 1) * (colW + GAP)
      local inner = cw - 2 * CARD_PAD
      local y = top + CARD_HEAD
      for _, part in ipairs(model.parts) do
        n = n + 1
        if part.special then
          local h = self:BlockHeight(part.block, inner, not part.label)
          self:PutBlock(n, part.block, cx + CARD_PAD, y, inner, h, not part.label)
          y = y + h
        else
          y = y + self:PutTiles(n, part, cx + CARD_PAD, y, inner)
        end
        self.blockPool[n]:SetFrameLevel(card:GetFrameLevel() + 1) -- on the card's plate
      end
      card.chapter = chapter
      card.title:SetText(tostring(chapter.title or ""))
      local count = model.things > 1 and model.things or Util.chapterCount(chapter)
      if count then
        card.count:ClearAllPoints()
        card.count:SetPoint(
          "TOPLEFT",
          card,
          "TOPLEFT",
          CARD_PAD + labelWidth(card.title, chapter.title) + 8,
          -11
        )
        card.count:SetText(tostring(count))
        card.count:Show()
      else
        card.count:Hide()
      end
      if model.capped then
        card.all.spec.label = string.format(L["All %d"], model.things)
        card.all:Fit()
        card.all:Show()
        y = y + CARD_FOOT
      else
        card.all:Hide()
      end
      y = y + CARD_PAD
      card:ClearAllPoints()
      card:SetPoint("TOPLEFT", self.content, "TOPLEFT", cx, -top)
      card:SetSize(cw, y - top)
      card.plate:Show() -- lays the corners out for the new size
      card.edge:Show()
      card:Show()
      self.cards[cards] =
        { chapter = chapter, things = model.things, capped = model.capped, col = col, wide = cw == w }
      if cw == w then
        for c = 1, cols do
          colY[c] = y + GAP
        end
      else
        colY[col] = y + GAP
      end
    end
  end
  for i = cards + 1, #self.cardPool do
    self.cardPool[i]:Hide()
    self.cardPool[i].chapter = nil
  end
  for _, ch in ipairs(self.chapterPool) do
    ch:Hide()
    ch.chapter = nil
  end
  for _, b in ipairs(self.contentsPool) do
    b:Hide()
  end
  local y = colY[1]
  for c = 2, cols do
    y = math.max(y, colY[c])
  end
  y = cards > 0 and (y - GAP) or (head + 2)
  if not geo.two then
    -- one column: the facts end the page under their own titles (ADR 0052: the first answer first)
    for _, block in ipairs(data.facts) do
      if blockMatches(block, query) then
        n = n + 1
        local h = self:BlockHeight(block, w)
        self:PutBlock(n, block, x, y + PAD, w, h)
        y = y + PAD + h
      end
    end
  end
  hideBlocksFrom(self, n + 1)
  self.blockCount = n
  self.chapterCount = cards
  self.columns = cols
  self.pages = geo.two and 2 or 1
  local links = self:LayoutLinks(data.links, w, y + GAP, x)
  if links > 0 then
    y = y + GAP + links
  end
  local trail = self:LayoutTrail(w, y + PAD, x)
  if trail > 0 then
    y = y + PAD + trail
  end
  return math.max(y, left or 0)
end

-- Draws a registered sheet (Bastians:RegisterSheet) at the top of the page, in place of the
-- head: its app's own drawing of the type. The host's buttons (Bookmark) and More ride on it.
-- Returns where it ends.
function Dossier:HostSheet(sheet, data, width)
  local ref = data.ref
  self.band:Hide()
  local host = self.sheetHost
  if not host then
    host = {
      frame = self.content,
      refresh = function()
        if self.data then
          self:Layout()
        end
      end,
      -- the drawing opens another thing (a chain's step): as a click on a row of the page
      open = function(target)
        self:RowClick({ ref = target }, "LeftButton")
      end,
    }
    self.sheetHost = host
  end
  host.width, host.ctx = width, self.ctx
  local buttons = {}
  for i, spec in ipairs(self.opts.buttons and self.opts.buttons(ref) or {}) do
    buttons[#buttons + 1] = { key = "host" .. i, label = spec.label, icon = spec.icon, run = spec.onClick }
  end
  buttons[#buttons + 1] = {
    key = "host.more",
    label = L["More"],
    tip = L["Every action for this subject"],
    run = function(button)
      if B.UI.EntityMenu then
        B.UI.EntityMenu(ref, button, self.ctx)
      end
    end,
  }
  host.buttons = buttons
  self.sheet = sheet
  self.covered = {}
  for _, id in ipairs(sheet.covers or {}) do
    self.covered[id] = true
  end
  local ok, height = ns.safecall(sheet.owner or ns.coreOwner, sheet.draw, ref, host)
  return ok and type(height) == "number" and height or 0
end

-- The page shows a type without a sheet again, or nothing: the hosted drawing goes.
function Dossier:LeaveSheet()
  local sheet = self.sheet
  self.sheet, self.covered = nil, nil
  if sheet and sheet.hide and self.sheetHost then
    ns.safecall(sheet.owner or ns.coreOwner, sheet.hide, self.sheetHost)
  end
end

-- How far the left page (the figure and the facts under it) moves down with the reading: it
-- stays in view while the reading scrolls. A left page taller than the view scrolls until its
-- end shows and stays from there; it never leaves the sheet's end. Pure.
function Util.leftShift(scroll, view, leftHeight, total)
  local shift = scroll - math.max(0, leftHeight - view)
  return math.max(0, math.min(shift, total - leftHeight))
end

-- Puts the left page where the scroll position asks (two pages only; the scrollbar calls it).
function Dossier:PlaceLeft()
  local stage = self.band.stage
  if not (stage and self.opts.portrait) or self.opts.here then
    return
  end
  local shift = 0
  if self.leftHeight then
    shift = Util.leftShift(
      self.scroll:GetVerticalScroll() or 0,
      self.scroll:GetHeight() or 0,
      self.leftHeight,
      self.height or 0
    )
  end
  self.leftShift = shift
  stage.frame:ClearAllPoints()
  stage.frame:SetPoint("TOPLEFT", self.band, "TOPLEFT", PAD, -PAD - shift)
  for _, entry in ipairs(self.leftBlocks or {}) do
    entry.frame:ClearAllPoints()
    entry.frame:SetPoint("TOPLEFT", self.content, "TOPLEFT", PAD, -(entry.y + shift))
  end
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
    S.EntityTip(GameTooltip, row.ref, row.text)
  else
    return
  end
  GameTooltip:Show()
end

-- The tile of a link chip: the row's own suite icon, else its entity's type (ADR 0046); none on
-- the "+N more" chip.
local function chipKind(row)
  if row.kind == "more" then
    return nil
  end
  local kind = row.icon and B.UI.IconKind(row.icon)
  if kind then
    return kind
  end
  local typ = row.ref and B.Entity.Parse(row.ref)
  if typ == "npc" then
    return "service"
  end
  return typ
end

local function chip(self, n)
  local c = self.chipPool[n]
  if c then
    return c
  end
  c = S.pill(self.links, {
    onClick = function(btn, button)
      if btn.row then
        self:RowClick(btn.row, button)
      end
    end,
  })
  c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
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

function Dossier:LayoutLinks(links, width, top, left)
  local region = self.links
  if #links == 0 or (self.query and self.query ~= "") then
    region:Hide()
    for _, c in ipairs(self.chipPool) do
      c:Hide()
    end
    return 0
  end
  region:ClearAllPoints()
  region:SetPoint("TOPLEFT", self.content, "TOPLEFT", left or 0, -top)
  region:SetWidth(width)
  region.title:SetText(Util.titleText(L["Links"]))
  Util.rule(region.line, region.orn, width)
  local y = TITLE_H + 2
  local chipH = S.G.pill or 26
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
      c.spec.kind = chipKind(row)
      c.spec.label = Util.chipText(row)
      c.spec.on = row.kind == "more" or nil
      S.Draw(c)
      local w = c:GetWidth()
      if x > LABEL_W + 4 and x + w > width then
        x = LABEL_W + 4
        y = y + chipH + CHIP_GAP
      end
      c:ClearAllPoints()
      c:SetPoint("TOPLEFT", region, "TOPLEFT", x, -y)
      c:Show()
      x = x + w + CHIP_GAP
    end
    link.capped = capped
    y = y + chipH + CHIP_GAP
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
  b:SetHeight(TRAIL_H)
  b.label = S.text(b, 12)
  b.label:SetPoint("LEFT", 0, 0)
  b.label:SetJustifyH("LEFT")
  b:SetScript("OnClick", function(btn)
    if btn.item and self.onTrail then
      self.onTrail(btn.item)
    end
  end)
  b:SetScript("OnEnter", function(btn) -- S.Tok: on paper the paper's accent, also under the mouse
    local c = S.Tok(btn, "accent")
    btn.label:SetTextColor(c[1], c[2], c[3])
  end)
  b:SetScript("OnLeave", function(btn)
    local c = S.Tok(btn, btn.last and "accent" or "text")
    btn.label:SetTextColor(c[1], c[2], c[3])
  end)
  self.trailPool[n] = b
  return b
end

function Dossier:LayoutTrail(width, top, left)
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
  region:SetPoint("TOPLEFT", self.content, "TOPLEFT", left or 0, -top)
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
      x, y = x0, y + TRAIL_H
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
  region:SetHeight(y + TRAIL_H)
  region:Show()
  return y + TRAIL_H
end

-- ---------------------------------------------------------------------------------------------
-- Layout: a sheet (the head, the facts, the contents, the chapters, the links, the trail), or
-- the Here column (the band and its grid)
-- ---------------------------------------------------------------------------------------------

function Dossier:Layout()
  self:SyncPaper()
  return S.WithPalette(self.palette, self.LayoutNow, self)
end

function Dossier:LayoutNow()
  local data = self.data
  if not data then
    return
  end
  self.dirty = false
  local width = self:Width()
  local y
  if self.opts.here then
    y = self:LayoutBand(data.card, width)
    local grid = self:LayoutBlocks(data.blocks, width, y + GAP)
    if grid > 0 then
      y = y + GAP + grid
    end
  else
    -- the page filter ("if I am in a dungeon and start typing in that
    -- filter, I expect that all node lists are reduced accordingly. pictures disappear when I
    -- type, only nodes are shown"): no head, no app's sheet, the cards of every tab
    local searching = self.opts.cards and self:Searching()
    local sheet = not searching and self.opts.cards and B:GetSheet((B.Entity.Parse(data.ref))) or nil
    if self.sheet and self.sheet ~= sheet then
      self:LeaveSheet() -- the page before was another app's drawing
    end
    if searching then
      self.band:Hide()
      y = self:LayoutCards(data, { two = false, x = 0, figure = 0 }, PAD)
    elseif sheet then
      -- one sheet per type (ADR 0056): its app draws the head and what it knows best, the
      -- cards of the other parts follow at the page's width
      y = self:LayoutCards(
        data,
        { two = false, x = 0, figure = 0 },
        self:HostSheet(sheet, data, width),
        self.covered
      )
    else
      local head, geo = self:LayoutBand(data.card, width, data)
      if self.opts.cards then
        y = self:LayoutCards(data, geo, head)
      else
        y = self:LayoutSheet(data, geo, head)
      end
    end
  end
  y = y + PAD
  self.height = y
  self.content:SetSize(math.max(1, width), math.max(1, y))
  self.bar.SetTotal(y)
  self:PlaceLeft()
  if self.opts.onRender then
    self.opts.onRender(self)
  end
end
