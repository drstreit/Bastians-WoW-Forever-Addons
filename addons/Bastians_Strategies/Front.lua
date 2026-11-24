-- Bastian's Book: the front table and the category pages (book.md "The pages"; Your record
-- was a list here until 24.11.2026, it is the diary's spread now, Diary.lua):
-- large picture tiles in Core's virtual list (only the rows in sight have frames) under the
-- chapter's filter, every chip a click.
local _, ns = ...
local B = Bastians
local S = B.UI.Style
local L = ns.L
local Shelf, Record, Picture = ns.Shelf, ns.Record, ns.Picture

local Front = {}
ns.Front = Front

local ipairs, pairs, tostring, type = ipairs, pairs, tostring, type
local floor, max, min = math.floor, math.max, math.min

-- three plates across a spread, not five stamps
Front.TILE_MIN = 320 -- a tile's least width: the columns follow the window
Front.COLS_MAX = 4
Front.GAP = 11 -- between two tiles (book-look.md section 6; ~~18~~ until 17.11.2026)
Front.PIC = 0.5 -- a tile's picture, the card's whole width: the drawings' own 2:1
Front.BODY = 130 -- a tile's words and chips under its picture
Front.ZONES_SHOWN = 10 -- a continent's zone chips before "more"
-- the filter band in the concept board's numbers (docs/addons/book-look.md section 5)
Front.LABEL_W = 41 -- the filter rows' label column
Front.CHIP = 22 -- a filter chip (Core's S.G.chip)
Front.ROW_GAP = 8 -- between two rows
Front.BAND_TOP, Front.BAND_SIDE, Front.BAND_FOOT = 10, 15, 9 -- the band's padding
Front.SEP_H, Front.SEP_PAD = 20, 10 -- the line between two groups on a row, the room each side
Front.SLIDER_W, Front.SLIDER_H = 204, 34 -- the level's range slider
Front.TABLE_TOP = 8 -- between the band and the result line
Front.BANDS = { { 1, 10 }, { 10, 20 }, { 20, 30 }, { 30, 40 }, { 40, 50 }, { 50, 60 } }

-- The chapters, named by what the reader does (book.md "The chapters", E1)
local CHAPTER_NAMES = {
  all = "Everything",
  gold = "Gold",
  secrets = "Secrets",
  collections = "Collections",
  camp = "Camp",
  rares = "Rares",
}

function Front.ChapterName(id)
  return L[CHAPTER_NAMES[id] or tostring(id)]
end

-- The words of the filter: a facet's name, and each value's ("I
-- selected pet and object ... the object is also a pet": the facet is where a thing comes from,
-- so it says so). Built at the first use: the locale is loaded by then.
local words
local function wordsOf()
  if not words then
    words = {
      facet = {
        chapter = L["chapter"],
        kind = L["kind"],
        side = L["faction"],
        source = L["comes from"],
        type = L["type"],
        profession = L["profession"],
        skill = L["skill"],
      },
      value = {
        A = L["Alliance"],
        H = L["Horde"],
        both = L["both"],
      },
      -- Bastian's sentence of each chapter: at the head of its shelf and as its tab's tip
      -- (book.md "The chapters", approved 17.11.2026)
      line = {
        gold = L["How I earn my keep, page by page."],
        secrets = L["What the world hides, and what nobody has solved yet."],
        collections = L["What you can own: mounts, companions, titles, and the library's books."],
        camp = L["What you can build at your own fire."],
        rares = L["What is worth a hunt."],
      },
      source = {
        drop = L["a drop"],
        vendor = L["a vendor"],
        quest = L["a quest"],
        object = L["an object in the world"],
        boss = L["a boss"],
        crafted = L["crafting"],
        achievement = L["an achievement"],
        event = L["an event"],
      },
      kind = {
        chain = L["chain"],
        unsolved = L["unsolved"],
        camping = L["camping"],
        library = L["library"],
        ["library book"] = L["library book"],
        ["camp kit"] = L["camp kit"],
        ["camp item"] = L["camp item"],
        mount = L["mount"],
        pet = L["pet"],
        title = L["title"],
        rare = L["rare"],
        ["rare elite"] = L["rare elite"],
      },
    }
  end
  return words
end

-- A gold page's kind is its chapter of the old book: its name from the pack.
local function goldChapter(id)
  local d = B:GetService("data")
  local c = d and d:Get("chapter", id)
  return c and c.name or nil
end

local function kindName(v)
  return goldChapter(v) or wordsOf().kind[v] or tostring(v)
end

local function sourceName(v)
  return wordsOf().source[v] or tostring(v)
end

-- The words for a way to get something ("a drop"), by the filter's value (the list's rows).
function Front.SourceWords()
  return wordsOf().source
end

local function valueLabel(key, v)
  if key == "chapter" then
    return Front.ChapterName(v)
  elseif key == "kind" then
    return kindName(v)
  elseif key == "source" then
    return sourceName(v)
  end
  return wordsOf().value[v] or tostring(v)
end

Front.ValueLabel = valueLabel -- a kind's or a chapter's word, for the Atlas's band and cards

local function facetLabel(key)
  return wordsOf().facet[key] or key
end

-- A chapter's sentence, nil for Everything and the front table.
function Front.ChapterLine(id)
  return wordsOf().line[id]
end

-- A tile's first line: the kind, and where it comes from ("PET - FROM A DROP"), a gold page's
-- chapter of the old book.
function Front.KindLabel(e)
  if e.page then
    return goldChapter(e.kind) or ""
  end
  local kind = e.kind and kindName(e.kind) or ""
  local src = e.facets and e.facets.source
  if src then
    return kind .. "  -  " .. string.format(L["from %s"], sourceName(src))
  end
  return kind
end

-- ---------------------------------------------------------------------------------------------
-- The shelf's entries and the context the filters ask
-- ---------------------------------------------------------------------------------------------

local entries, byId
local simulated = {}
local filters = {} -- [chapter] = the filter (this session)

local function data()
  return B:GetService("data")
end

function Front.Entries()
  if entries then
    return entries
  end
  local out, d = {}, data()
  if d then
    local place = {}
    for i, turn in ipairs(ns.Book.Order(d:Index("book.toc"))) do
      place[turn.id] = i
    end
    for _, id in ipairs(d:Each("wonder") or {}) do
      local rec = d:Get("wonder", id)
      if rec then
        out[#out + 1] = Shelf.FromWonder(id, rec)
      end
    end
    for _, id in ipairs(d:Each("page") or {}) do
      local p = d:Get("page", id)
      if p and (p.shelf == "active" or p.shelf == "back") and p.chapter ~= "front" then
        local e = Shelf.FromPage(id, p, ns.Book.Lead(p, 160))
        e.body = ns.Window.TextOf and ns.Window.TextOf(id, p) or nil
        e.order = place[id] -- the page's place in the book: the Gold shelf's order of the undated
        out[#out + 1] = e
      end
    end
  end
  for _, e in ipairs(simulated) do
    out[#out + 1] = e
  end
  entries, byId = out, {}
  for _, e in ipairs(out) do
    byId[e.id] = e
  end
  return out
end

function Front.Find(id)
  Front.Entries()
  return byId[id]
end

-- New data or a new simulation: the shelf is built again at the next look.
function Front.Invalidate()
  entries, byId = nil, nil
end

-- /bbook simulate <n>: n simulated wonders on the shelf for this session (0 takes them away).
function Front.Simulate(n)
  simulated = (n and n > 0) and Shelf.Simulate(n, 7) or {}
  Front.Invalidate()
  return #simulated
end

local zoneCache = {}
local function zoneOf(z)
  local c = zoneCache[z]
  if c == nil then
    c = Shelf.SimZone(z) or false
    if not c then
      local d = data()
      local rec = d and d:Get("zone", z)
      c = rec and { name = rec.name, continent = rec.continent } or false
    end
    zoneCache[z] = c
  end
  return c or nil
end
Front.ZoneOf = zoneOf

local function itemName(id)
  local d = data()
  local rec = d and d:Get("item", id)
  return rec and rec.name or nil
end

function Front.Ctx()
  local continent, wx, wy, map = B.Coords.Player()
  return {
    isDone = Record.IsDone,
    doneAt = function(id) -- the time of this character's mark (the list's sort by "have")
      local mine = Record.Entry(id)
      return mine and mine.at or nil
    end,
    zoneOf = zoneOf,
    itemName = itemName,
    level = UnitLevel and UnitLevel("player") or nil,
    today = date("%Y-%m-%d"),
    here = map and { map = map, continent = continent or (zoneOf(map) or {}).continent, wx = wx, wy = wy }
      or nil,
    worldOf = B.Coords.ToWorld,
  }
end

function Front.Filter(chapter)
  chapter = chapter or "all"
  filters[chapter] = filters[chapter] or Shelf.NewFilter(chapter)
  return filters[chapter]
end

function Front.ResetFilters()
  filters = {}
end

-- A shelf's view (book.md "The views", E4): tiles or a list, the reader's choice kept per chapter
-- and character (`char.views`); Collections opens as a list.
local function views()
  local char = ns.mod and ns.mod.db and ns.mod.db.char or nil
  if not char then
    return nil
  end
  char.views = char.views or {} -- a character saved before round 4's list has none
  return char.views
end

function Front.View(chapter)
  return Shelf.ViewOf(views(), chapter or "all")
end

function Front.SetView(chapter, v)
  local saved = views()
  if saved and Shelf.VIEWS[v] then
    saved[chapter or "all"] = v
  end
end

-- ---------------------------------------------------------------------------------------------
-- The view: the filter on top (category pages), the list under it
-- ---------------------------------------------------------------------------------------------

local view, list, current

local function show(entry)
  ns.Window.Show(entry)
end

local function rerender()
  ns.Window.Render()
end

-- A pooled pill on `parent`'s pool `pool`; `spec` as S.pill's.
local function pill(parent, pool, i, spec)
  local p = pool[i]
  if not p then
    p = S.pill(parent, { small = true }) -- a chip: 22 high, the small text (book-look.md)
    S.SetRole(p.label, "bookSans") -- the book's controls in its own sans (ADR 0081)
    pool[i] = p
  end
  p.spec = spec
  p.tip = spec.tip
  S.Draw(p)
  p:Show()
  return p
end

local function hideFrom(pool, n)
  for i = n + 1, #pool do
    pool[i]:Hide()
  end
end

-- ---------------------------------------------------------------------------------------------
-- A tile: the picture on top, the kind, the title, the first line, the chips
-- ---------------------------------------------------------------------------------------------

local function chipsOf(e, ctx)
  local out = {}
  local z = e.zones and e.zones[1]
  local zone = z and zoneOf(z)
  if zone and zone.name then
    out[#out + 1] = { label = zone.name, zone = z }
  end
  if e.levelMin or e.levelMax then
    local lo, hi = e.levelMin or 1, e.levelMax
    local label = hi and hi ~= lo and string.format(L["level %d to %d"], lo, hi)
      or (hi and string.format(L["level %d"], lo) or string.format(L["level %d+"], lo))
    out[#out + 1] = { label = label, lo = lo, hi = hi or Shelf.LEVEL_CAP, gold = Shelf.Fits(e, ctx.level) }
  end
  if e.side then
    out[#out + 1] = { label = valueLabel("side", e.side), side = e.side }
  end
  return out
end

local function openEntry(e)
  if e.page then
    show({ kind = "page", id = e.id })
  else
    show({ kind = "wonder", id = e.id })
  end
end
Front.OpenEntry, Front.Show = openEntry, show

-- A chip of a tile filters its chapter's page (book.md "The category page").
local function chipClick(e, chip)
  local chapter = (current and current.kind == "shelf" and current.id) or e.chapter
  local f = Front.Filter(chapter)
  if chip.zone then
    f.zone = chip.zone
    f.continent = (zoneOf(chip.zone) or {}).continent
  elseif chip.lo then
    f.lo, f.hi = chip.lo, chip.hi
  elseif chip.side then
    f.facets.side = { [chip.side] = true }
  end
  show({ kind = "shelf", id = chapter })
end

-- ---------------------------------------------------------------------------------------------
-- The paper: every card of the book is paper in
-- every look, its words the paper's ink in the book's own faces; only the frame around follows the
-- look. A soft shadow lays it on the table. ~~A plate in the theme's card colour~~ (until
-- 16.11.2026; at full opacity it painted a leaving tile solid gold in the WoW look, the "hover
-- that does not go away").
-- ---------------------------------------------------------------------------------------------

-- The look's paper parts are Core's kit since W4 (ADR 0084 decision 8: S.shadow, S.deckle,
-- S.fade); ~~the book drew Core's textures itself~~ (until 20.11.2026, a crossing of ADR 0082).
Front.SHADOW_SPREAD = 12 -- px the shadow reaches beyond a card
Front.SHADOW_DROP = 4 -- px it falls lower than the card
Front.DECKLE_H = 12 -- the torn edge at a picture's foot
Front.CHIP_H = 18 -- a chip on a card

-- A card's paper, at rest. Drawn plain again on every fill: the list hands a card on under a
-- resting mouse. ~~Under the mouse its edge in the book's gold~~ (until 23.11.2026): a tile is an
-- object now (R4.6, Core's S.object): it rises, its shadow grows, its edge is lit 2 wide.
local function plate(t)
  S.tint(t.face, S.C.folioPaper)
  t:SetObjectState("rest")
end
Front.Plate = plate

Front.RADIUS = 5 -- a tile's corners (book-look.md section 6)

local function paperFrame(parent)
  local t = CreateFrame("Button", nil, parent)
  t.face = S.roundFill(t, S.C.folioPaper, Front.RADIUS)
  S.object(t, { radius = Front.RADIUS })
  t:SetScript("OnClick", function(self)
    if self.entry then
      openEntry(self.entry)
    end
  end)
  return t
end

-- A text in one of the book's faces (Core's S.BOOK_FONTS: bookDisplay, bookItalic, bookCaps,
-- bookSans), kept across a theme change.
local function bookText(parent, size, color, role, wrap)
  local fs = S.SetRole(S.text(parent, size, color), role)
  fs:SetWordWrap(wrap == true)
  return fs
end
Front.BookText = bookText

-- A chip on a card: a thin outline in the paper's edge; a level that fits you filled in the book's
-- gold (the concept board's chips). A click filters the shelf.
local function chipPlate(c, hot)
  local fit = c.fit
  if fit then
    S.tint(c.face, S.C.folioFit) -- the gold at the token's own 40 %
  else
    S.tint(c.face, S.C.folioFit, 0)
  end
  S.setEdges(c.edges, (hot and S.C.folioInk) or (fit and S.C.folioFitEdge) or S.C.folioPaperEdge)
  S.ink(c.label, (fit or hot) and S.C.folioInk or S.C.folioInkSoft)
end

local function paperChip(parent)
  local c = CreateFrame("Button", nil, parent)
  c.face = S.roundFill(c, S.C.folioFit, "pill")
  c.edges = S.roundEdges(c, S.C.folioPaperEdge, "pill")
  c.label = bookText(c, 11, S.C.folioInkSoft, "bookSans")
  c.label:SetPoint("CENTER", c, "CENTER", 0, 0)
  c:SetScript("OnEnter", function(self)
    chipPlate(self, true)
  end)
  c:SetScript("OnLeave", function(self)
    chipPlate(self, false)
  end)
  c:SetScript("OnClick", function(self)
    if self.onClick then
      self.onClick()
    end
  end)
  return c
end

local function newTile(parent)
  local t = paperFrame(parent)
  t.pic = Picture.New(t)
  t.pic:SetPoint("TOPLEFT", t, "TOPLEFT", 0, 0)
  -- the torn foot of the picture, in the paper's colour, over the picture and its model
  t.tear = S.deckle(t, 8, "folioPaper")
  t.tear:SetHeight(Front.DECKLE_H)
  t.ribbon = CreateFrame("Frame", nil, t)
  t.ribbon:SetFrameLevel(t:GetFrameLevel() + 9)
  t.ribbon.fill = S.fill(t.ribbon, S.C.folioSeal, "BACKGROUND")
  t.ribbon.text = bookText(t.ribbon, 11, S.C.folioSealText, "bookCaps")
  t.ribbon.text:SetPoint("CENTER")
  t.alt = CreateFrame("Frame", nil, t)
  t.alt:SetFrameLevel(t:GetFrameLevel() + 9)
  t.alt.fill = S.fill(t.alt, S.C.folioGold, "BACKGROUND")
  t.alt.text = bookText(t.alt, 11, S.C.folioInk, "bookSans")
  t.alt.text:SetPoint("CENTER")
  t.badge = CreateFrame("Frame", nil, t)
  t.badge:SetFrameLevel(t:GetFrameLevel() + 9)
  t.seal = t.badge:CreateTexture(nil, "OVERLAY", nil, 7)
  t.seal:SetTexture(B.UI.IconTexture("lock"))
  t.seal:SetSize(22, 22)
  t.kind = bookText(t, 11, S.C.folioInkSoft, "bookCaps")
  t.title = bookText(t, 18, S.C.folioInk, "bookDisplay")
  t.hook = bookText(t, 13, S.C.folioInk, "bookItalic", true)
  t.hook:SetJustifyV("TOP")
  t.chips = {}
  return t
end

-- A label in small capitals: the small-capitals face makes them of lower case letters; a client
-- that keeps its own font (S.CLIENT_FONT) gets plain capitals instead.
local function lower(text)
  text = text or ""
  return S.CLIENT_FONT and string.upper(text) or string.lower(text)
end
Front.SmallCaps = lower

local function fillTile(t, e, w, h, ctx, extra)
  t.entry = e
  t:SetSize(w, h)
  plate(t)
  local picH = floor(w * Front.PIC)
  Picture.Draw(t.pic, e, w, picH)
  t.tear:ClearAllPoints()
  t.tear:SetPoint("BOTTOMLEFT", t, "TOPLEFT", 0, -picH - 1)
  t.tear:SetPoint("BOTTOMRIGHT", t, "TOPRIGHT", 0, -picH - 1)
  -- the ribbons: new, done by another character, sealed
  local new = Shelf.IsNew(e, ctx.today)
  t.ribbon:SetShown(new)
  if new then
    t.ribbon.text:SetText(lower(L["new"]))
    t.ribbon:SetSize(t.ribbon.text:GetStringWidth() + 16, 19)
    t.ribbon:ClearAllPoints()
    t.ribbon:SetPoint("TOPLEFT", t, "TOPLEFT", 10, -10)
  end
  local alts = Record.Alts(e.id)
  t.alt:SetShown(alts[1] ~= nil)
  if alts[1] then
    t.alt.text:SetText(string.format(L["Done by %s"], table.concat(alts, ", ")))
    t.alt:SetSize(min(w - 20, t.alt.text:GetStringWidth() + 16), 19)
    t.alt:ClearAllPoints()
    t.alt:SetPoint("BOTTOMLEFT", t, "TOPLEFT", 10, -picH + Front.DECKLE_H + 4)
  end
  -- a done wonder wears the stamp and its date at the picture's top right (R4.11); it takes the
  -- seal's corner: what is done needs no seal
  local mine = not e.page and Record.Entry(e.id) or nil
  Picture.Stamp(t, t, mine)
  local sealed = (e.kind == "chain" or e.kind == "unsolved") and not Record.IsOpened(e.id) and not mine
  t.seal:SetShown(sealed)
  if sealed then
    S.tint(t.seal, S.C.folioGold)
    t.seal:ClearAllPoints()
    t.seal:SetPoint("TOPRIGHT", t, "TOPRIGHT", -10, -10)
  end
  -- the words: the kind in small capitals, the name in the old-print face, Bastian's line in italic
  local x, y = 13, -(picH + 10)
  t.kind:ClearAllPoints()
  t.kind:SetPoint("TOPLEFT", t, "TOPLEFT", x, y)
  t.kind:SetWidth(w - 2 * x)
  t.kind:SetText(lower(Front.KindLabel(e)))
  t.title:ClearAllPoints()
  t.title:SetPoint("TOPLEFT", t, "TOPLEFT", x, y - 17)
  t.title:SetWidth(w - 2 * x)
  t.title:SetText(e.title)
  t.hook:ClearAllPoints()
  t.hook:SetPoint("TOPLEFT", t, "TOPLEFT", x, y - 43)
  t.hook:SetSize(w - 2 * x, 34)
  t.hook:SetText(e.hook or e.tale or "")
  -- the chips, at the foot; extra = the Your record chip ("Not done yet")
  local chips = chipsOf(e, ctx)
  if extra then
    table.insert(chips, 1, extra) -- Your record's own chip first: it must never be cut off
  end
  local cx, n = x, 0
  for _, chip in ipairs(chips) do
    n = n + 1
    local c = t.chips[n]
    if not c then
      c = paperChip(t)
      t.chips[n] = c
    end
    c.fit = chip.gold or nil
    c.label:SetText(chip.label)
    c:SetSize((c.label:GetStringWidth() or 40) + 16, Front.CHIP_H)
    c.spec = { label = chip.label } -- what the tests and the tips read
    c.onClick = function()
      if chip.onClick then
        chip.onClick()
      else
        chipClick(e, chip)
      end
    end
    chipPlate(c, false)
    c:ClearAllPoints()
    if cx + c:GetWidth() > w - x then
      c:Hide()
      n = n - 1
      break
    end
    c:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", cx, 12)
    c:Show()
    cx = cx + c:GetWidth() + 5
  end
  hideFrom(t.chips, n)
  t:SetAlpha(Record.IsDone(e.id) and not extra and 0.55 or 1)
  t:Show()
end

-- ---------------------------------------------------------------------------------------------
-- The list's kinds: a heading, the hero, a row of tiles, a note
-- ---------------------------------------------------------------------------------------------

local function columns(width)
  local cols = floor((width + Front.GAP) / (Front.TILE_MIN + Front.GAP))
  return max(1, min(Front.COLS_MAX, cols))
end

local function tileSize(width)
  local cols = columns(width)
  local w = floor((width - (cols - 1) * Front.GAP) / cols)
  return cols, w, floor(w * Front.PIC) + Front.BODY
end

local KINDS = {}
Front.KINDS = KINDS -- the front table's kinds join it (Cabinet.lua)

KINDS.head = {
  make = function(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.title = bookText(f, 18, S.C.gold, "bookDisplay")
    f.title:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 2, 7)
    f.note = bookText(f, 13, S.C.muted, "bookSans")
    f.note:SetPoint("BOTTOMLEFT", f.title, "BOTTOMRIGHT", 12, 1)
    f.rule = S.fill(f, S.C.line, "ARTWORK")
    f.rule:ClearAllPoints()
    f.rule:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    f.rule:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    f.rule:SetHeight(1)
    f.acts = {}
    return f
  end,
  fill = function(f, item)
    if not f.vlKind then
      return 40
    end
    f.title:SetText(item.title or "")
    f.note:SetText(item.note or "")
    local right = 0
    for i, a in ipairs(item.acts or {}) do
      local b = f.acts[i]
      if not b then
        b = S.action(f, {})
        f.acts[i] = b
      end
      -- quiet words, as the concept board's "Clear all"; the pictograms stay (ADR 0046)
      b.spec = { icon = a.icon, label = a.label, primary = a.primary }
      b.tip = a.tip
      S.Draw(b)
      b:SetScript("OnClick", a.onClick)
      b:ClearAllPoints()
      b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -right, 5)
      right = right + b:GetWidth() + 8
      b:Show()
    end
    hideFrom(f.acts, #(item.acts or {}))
    return 40
  end,
}

-- A word to click, in the accent's ink (the concept board's "Clear all").
local function wordButton(parent)
  local b = CreateFrame("Button", nil, parent)
  b.text = bookText(b, 13, S.C.accent, "bookSans")
  b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
  b:SetScript("OnEnter", function(self)
    S.ink(self.text, S.Tok(self, "text"))
    S.TipEnter(self)
  end)
  b:SetScript("OnLeave", function(self)
    S.ink(self.text, S.Tok(self, "accent"))
    S.TipLeave(self)
  end)
  return b
end

-- The line over a shelf's tiles (book-look.md section 6): the count in the text's ink, what the
-- filter keeps in words after it, quiet; the acts as words at the right. ~~The count in the
-- title's face~~ (until 17.11.2026).
KINDS.result = {
  make = function(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.count = bookText(f, 13, S.C.text, "bookSans")
    f.count:SetPoint("LEFT", f, "LEFT", 0, 0)
    f.words = bookText(f, 13, S.C.muted, "bookSans")
    f.words:SetJustifyH("LEFT")
    f.acts = {}
    return f
  end,
  fill = function(f, item)
    if not f.vlKind then
      return 16
    end
    S.ink(f.count, S.Tok(f, "text"))
    S.ink(f.words, S.Tok(f, "muted"))
    f.count:SetText(item.title or "")
    f.words:SetText(item.note or "")
    local right = 0
    for i, a in ipairs(item.acts or {}) do
      local b = f.acts[i]
      if not b then
        b = wordButton(f)
        f.acts[i] = b
      end
      b.text:SetText(a.label or "")
      S.ink(b.text, S.Tok(b, "accent"))
      b.tip = a.tip
      local w = b.text:GetStringWidth()
      b:SetSize(((w and w > 0) and w or (#(a.label or "") * 7)) + 4, 16)
      b:SetScript("OnClick", a.onClick)
      b:ClearAllPoints()
      b:SetPoint("RIGHT", f, "RIGHT", -right, 0)
      right = right + b:GetWidth() + 14
      b:Show()
    end
    hideFrom(f.acts, #(item.acts or {}))
    f.words:ClearAllPoints()
    f.words:SetPoint("LEFT", f.count, "RIGHT", 8, 0)
    f.words:SetPoint("RIGHT", f, "RIGHT", -right, 0)
    return 16
  end,
}

KINDS.tiles = {
  make = function(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.tiles = {}
    return f
  end,
  fill = function(f, item, width)
    local _, w, h = tileSize(width)
    if not f.vlKind then
      return h
    end
    for i, e in ipairs(item.entries) do
      local t = f.tiles[i]
      if not t then
        t = newTile(f)
        f.tiles[i] = t
      end
      t:Rest("TOPLEFT", f, "TOPLEFT", (i - 1) * (w + Front.GAP), 0)
      fillTile(t, e, w, h, item.ctx, item.extra and item.extra(e) or nil)
    end
    for i = #item.entries + 1, #f.tiles do
      Picture.Clear(f.tiles[i].pic)
      f.tiles[i]:Hide()
    end
    return h
  end,
}

KINDS.note = {
  make = function(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.text = S.text(f, 13, S.C.muted)
    f.text:SetWordWrap(true)
    f.text:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -8)
    return f
  end,
  fill = function(f, item, width)
    f.text:SetWidth(width - 4)
    f.text:SetText(item.text or "")
    return 40
  end,
}

-- ---------------------------------------------------------------------------------------------
-- The filter (category pages): a band of its own, rows of chips that wrap with the width
-- (docs/addons/book-look.md section 5: the concept board's numbers;
-- "more space between filters", "the buttons are rounder")
-- ---------------------------------------------------------------------------------------------

local CHIP_GAP = 5 -- between two chips

local function chipHeight()
  return S.G.chip or Front.CHIP
end

-- The book's ground (book-look.md section 3; "background color in wow schema
-- should be same as artifact", D2): the dark table on a dark theme, the theme's own on a light one
-- (~~where the look is the game's~~ until 20.11.2026, ADR 0084). The band's and the shelf's widgets
-- ask the palette set here (S.Tok).
local function ground(shelf)
  local dark = S.DarkTable(view)
  local own = dark and S.FolioPalette() or nil
  view.filters.palette, view.body.palette = own, own
  S.tint(view.band, dark and S.C.folioBand or S.C.panel)
  S.tint(view.rule, dark and S.C.folioRule or S.C.line)
  S.tint(view.table, S.C.folioTable, dark and 1 or 0)
  view.band:SetShown(shelf)
  view.rule:SetShown(shelf)
  return dark
end

-- The filter flows in groups: a group is
-- its label and its chips; it starts a row with its label in the left column, or follows the
-- group before on the same row after a thin line when it fits there. A row is as high as a chip,
-- the level's as high as its slider; everything in it sits on its middle. Core's band lays it
-- out (B.UI.Band, W5 of plan-suite-waves.md; the book drew it itself until 23.11.2026).
local function newRow(state, h)
  state:NewRow(h)
end

local function separator(state)
  state:Separator()
end

local function fits(state, need)
  return state:Fits(need)
end

local function group(state, text, own, need, h)
  state:Group(text, own, need, h)
end

-- How far under a row's top a part of height `h` sits to stand on the row's middle (Core's).
Front.Centre = B.UI.BandClass.Centre

local function place(state, frame, w, h)
  state:Place(frame, w, h)
end

local function filterPill(state, spec)
  state.p = state.p + 1
  local p = pill(view.filters, view.pills, state.p, spec)
  place(state, p, p:GetWidth(), p:GetHeight())
  return p
end

-- The level's range slider: two knobs on a
-- track from 1 to the level cap, the character's level marked over it. Pure: the level a place on
-- the track means.
function Front.LevelAt(x, width)
  local cap = Shelf.LEVEL_CAP
  if not width or width <= 0 then
    return 1
  end
  return max(1, min(cap, floor(1 + x / width * (cap - 1) + 0.5)))
end

local function levelX(level)
  return (level - 1) / (Shelf.LEVEL_CAP - 1) * Front.SLIDER_W
end

local SLIDER_TICKS = { 1, 10, 20, 30, 40, 50, 60 }
local SLIDER_MID = 17 -- the track's middle from the slider's top: the words over and under it

local function rangeLabel(lo, hi)
  return string.format(L["%d to %d"], lo, hi)
end

local function newSlider(parent)
  local s = CreateFrame("Frame", nil, parent)
  s:SetSize(Front.SLIDER_W, Front.SLIDER_H)
  local level = s:GetFrameLevel() or 1
  local function bar(lift)
    local f = CreateFrame("Frame", nil, s)
    f:SetHeight(4)
    f:SetFrameLevel(level + lift)
    f.face = S.roundFill(f, S.C.line, "pill", "ARTWORK")
    return f
  end
  s.track = bar(1)
  s.track:SetWidth(Front.SLIDER_W)
  s.track:SetPoint("LEFT", s, "TOPLEFT", 0, -SLIDER_MID)
  s.sel = bar(2)
  s.knobs = {}
  for i = 1, 2 do
    local k = CreateFrame("Button", nil, s)
    k:SetSize(16, 16) -- a knob of 12 in a ring of 2
    k:SetFrameLevel(level + 3)
    k.ring = S.roundFill(k, S.C.accent, "pill", "ARTWORK")
    k.core = CreateFrame("Frame", nil, k)
    k.core:SetSize(12, 12)
    k.core:SetPoint("CENTER", k, "CENTER", 0, 0)
    k.core:SetFrameLevel(level + 4)
    k.core.face = S.roundFill(k.core, S.C.folioSealText, "pill", "ARTWORK")
    k:SetScript("OnMouseDown", function()
      s:Grab(i)
    end)
    k:SetScript("OnMouseUp", function()
      s:Release()
    end)
    s.knobs[i] = k
  end
  s.you = bookText(s, 11, S.C.accent, "bookCaps")
  s.read = bookText(s, 11, S.C.text, "bookSans")
  s.ticks = {}
  for i, tick in ipairs(SLIDER_TICKS) do
    local fs = bookText(s, 11, S.C.dim, "bookSans")
    fs:SetText(tostring(tick))
    fs:SetPoint("TOP", s, "TOPLEFT", levelX(tick), -(SLIDER_MID + 6))
    s.ticks[i] = fs
  end

  -- Draws the range lo..hi (nil: every level) and the character's level `you` (nil: unknown).
  function s.Set(self, lo, hi, you)
    self.lo, self.hi, self.youLevel = lo or 1, hi or Shelf.LEVEL_CAP, you
    local a, b = levelX(self.lo), levelX(self.hi)
    local hot = S.Tok(self, "accent")
    S.tint(self.track.face, S.Tok(self, "line"))
    S.tint(self.sel.face, hot)
    self.sel:ClearAllPoints()
    self.sel:SetPoint("LEFT", self, "TOPLEFT", a, -SLIDER_MID)
    self.sel:SetWidth(max(1, b - a))
    for i, x in ipairs({ a, b }) do
      local k = self.knobs[i]
      S.tint(k.ring, hot)
      k:ClearAllPoints()
      k:SetPoint("CENTER", self, "TOPLEFT", x, -SLIDER_MID)
    end
    for _, fs in ipairs(self.ticks) do
      S.ink(fs, S.Tok(self, "dim"))
    end
    -- over the track: the range while a knob is held, else where the character stands
    local held = self.grabbed ~= nil
    self.read:SetShown(held)
    self.you:SetShown(you ~= nil and not held)
    if held then
      S.ink(self.read, S.Tok(self, "text"))
      self.read:SetText(rangeLabel(self.lo, self.hi))
      self.read:ClearAllPoints()
      self.read:SetPoint("TOP", self, "TOPLEFT", (a + b) / 2, 0)
    elseif you then
      S.ink(self.you, hot)
      self.you:SetText(Front.SmallCaps(string.format(L["you %d"], you)))
      self.you:ClearAllPoints()
      self.you:SetPoint("TOP", self, "TOPLEFT", levelX(max(1, min(Shelf.LEVEL_CAP, you))), 0)
    end
  end

  -- The held end to `level`, never past the other end.
  function s.Drag(self, to)
    local lo, hi = self.lo, self.hi
    if self.grabbed == 1 then
      lo = min(to, hi)
    elseif self.grabbed == 2 then
      hi = max(to, lo)
    else
      return
    end
    if lo ~= self.lo or hi ~= self.hi then
      self:Set(lo, hi, self.youLevel)
    end
  end

  -- The mouse takes a knob: it follows the cursor until the button is up (no OnUpdate otherwise).
  function s.Grab(self, i)
    self.grabbed = i
    self:Set(self.lo, self.hi, self.youLevel)
    self:SetScript("OnUpdate", function()
      local x = (GetCursorPosition() or 0) / (self:GetEffectiveScale() or 1) - (self:GetLeft() or 0)
      self:Drag(Front.LevelAt(x, Front.SLIDER_W))
    end)
  end

  function s.Release(self)
    if not self.grabbed then
      return
    end
    self.grabbed = nil
    self:SetScript("OnUpdate", nil)
    self:Commit(self.lo, self.hi)
  end

  -- The range is chosen: the filter takes it (the whole track is every level).
  function s.Commit(self, lo, hi)
    if self.onCommit then
      self.onCommit(lo, hi)
    end
  end
  return s
end

-- Hide done as a switch (the concept board's): Core's switch (the book's own until W4, ADR 0084:
-- it moved into the kit) with its words beside it; the whole row is the button.
local function newSwitch(parent)
  local b = CreateFrame("Button", nil, parent)
  b.bar = S.toggle(b, {})
  b.bar:SetPoint("LEFT", b, "LEFT", 0, 0)
  b.bar:EnableMouse(false) -- the row's click, not the switch's own
  b.words = bookText(b, 11, S.C.text, "bookSans")
  b.words:SetPoint("LEFT", b.bar, "RIGHT", 6, 0)
  b:SetScript("OnEnter", S.TipEnter)
  b:SetScript("OnLeave", S.TipLeave)
  -- -> its width
  function b.Set(self, on, text)
    self.on = on and true or false
    self.bar:SetOn(self.on)
    S.ink(self.words, S.Tok(self, "text"))
    self.words:SetText(text)
    local w = self.words:GetStringWidth()
    self:SetSize(S.SWITCH_W + 6 + ((w and w > 0) and w or (#text * 6)), chipHeight())
    return self:GetWidth()
  end
  return b
end

Front.NewSwitch = newSwitch -- the Atlas's band has the same switch (R4.12)

-- Quiet words with a line under them: a link.
local function newLink(parent)
  local b = CreateFrame("Button", nil, parent)
  b.text = bookText(b, 11, S.C.muted, "bookSans")
  b.text:SetPoint("LEFT", b, "LEFT", 0, 0)
  b.line = S.fill(b, S.C.muted, "ARTWORK")
  b.line:ClearAllPoints()
  b.line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 2)
  b.line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 2)
  b.line:SetHeight(1)
  b:SetScript("OnEnter", function(self)
    S.ink(self.text, S.Tok(self, "text"))
  end)
  b:SetScript("OnLeave", function(self)
    S.ink(self.text, S.Tok(self, "muted"))
  end)
  -- -> its width
  function b.Set(self, text)
    S.ink(self.text, S.Tok(self, "muted"))
    S.tint(self.line, S.Tok(self, "muted"))
    self.text:SetText(text)
    local w = self.text:GetStringWidth()
    self:SetSize((w and w > 0) and w or (#text * 6), chipHeight())
    return self:GetWidth()
  end
  return b
end

Front.NewLink = newLink

local function toggleFacet(f, key, value)
  local chosen = f.facets[key] or {}
  chosen[value] = not chosen[value] or nil
  f.facets[key] = chosen
  rerender()
end

local function continentName(c)
  return B.Coords.ContinentName(c) or (c == 2991 and L["Islands"]) or tostring(c)
end

-- Lays the filter out for chapter `chapter` -> its height. `hidden`: the done wonders the filter
-- leaves out.
local function layFilters(chapter, all, ctx, width, hidden)
  local f = Front.Filter(chapter)
  local state = view.flow:Begin(width)
  state.p = 0
  -- where: the continents; after a line the chosen continent's zones while they fit on the row
  -- (else on a row of their own: every continent's zones at once were too many chips); after a
  -- line the zone you stand in
  group(state, L["where"], true)
  filterPill(state, {
    label = L["Everywhere"],
    on = not f.continent and not f.zone or nil,
    onClick = function()
      f.continent, f.zone, f.allZones = nil, nil, nil
      rerender()
    end,
  })
  for _, c in ipairs(Shelf.Counts(all, f, ctx, "continent")) do
    filterPill(state, {
      label = continentName(c.value),
      count = c.n,
      on = f.continent == c.value and not f.zone or nil,
      onClick = function()
        f.continent = (f.continent ~= c.value or f.zone) and c.value or nil
        f.zone, f.allZones = nil, nil
        rerender()
      end,
    })
  end
  local inline = false
  if f.continent then
    local zones = {}
    for _, z in ipairs(Shelf.Counts(all, f, ctx, "zone")) do
      local info = zoneOf(z.value)
      -- an island that is a continent of its own has no zone chip of the same name
      if not (info and info.name == continentName(f.continent)) then
        zones[#zones + 1] = z
      end
    end
    if zones[1] then
      local shown = f.allZones and #zones or min(#zones, Front.ZONES_SHOWN)
      local need = 0
      for i = 1, shown do
        local info = zoneOf(zones[i].value)
        need = need + 2 * 9 + 6 * #(info and info.name or "0000") + 14 + CHIP_GAP
      end
      inline = fits(state, need + 90)
      if inline then
        separator(state)
      else
        group(state, L["zone"], true)
      end
      for i = 1, shown do
        local z = zones[i]
        local info = zoneOf(z.value)
        filterPill(state, {
          label = info and info.name or tostring(z.value),
          count = z.n,
          on = f.zone == z.value or nil,
          onClick = function()
            f.zone = (f.zone ~= z.value) and z.value or nil
            rerender()
          end,
        })
      end
      if #zones > shown then
        filterPill(state, {
          label = string.format(L["%d more"], #zones - shown),
          onClick = function()
            f.allZones = true
            rerender()
          end,
        })
      end
    end
  end
  if ctx.here and ctx.here.map then
    if inline and fits(state, 80) then
      separator(state)
    end
    filterPill(state, {
      label = L["Near me"],
      on = f.zone == ctx.here.map or nil,
      tip = L["The zone you stand in."],
      onClick = function()
        f.zone = (f.zone ~= ctx.here.map) and ctx.here.map or nil
        f.continent = f.zone and ctx.here.continent or nil
        rerender()
      end,
    })
  end
  -- level: the range slider with your level marked; any, the chosen range, yours as chips
  group(state, L["level"], true, nil, Front.SLIDER_H)
  local slider = view.slider
  if not slider then
    slider = newSlider(view.filters)
    view.slider = slider
  end
  slider.onCommit = function(lo, hi)
    if lo <= 1 and hi >= Shelf.LEVEL_CAP then
      f.lo, f.hi = nil, nil
    else
      f.lo, f.hi = lo, hi
    end
    rerender()
  end
  if not slider.grabbed then -- a knob in the hand keeps its place through a render
    slider:Set(f.lo, f.lo and (f.hi or Shelf.LEVEL_CAP) or nil, ctx.level)
  end
  state.x = state.x + 4
  place(state, slider, Front.SLIDER_W + 8, Front.SLIDER_H)
  slider:Show()
  filterPill(state, {
    label = L["any"],
    on = not f.lo and not f.hi or nil,
    onClick = function()
      f.lo, f.hi = nil, nil
      rerender()
    end,
  })
  local mlo, mhi = Shelf.MyLevel(ctx.level)
  if f.lo and not (f.lo == mlo and f.hi == mhi) then
    filterPill(state, { label = rangeLabel(f.lo, f.hi or Shelf.LEVEL_CAP), on = true })
  end
  if mlo then
    filterPill(state, {
      label = string.format(L["my level (%s)"], rangeLabel(mlo, mhi)),
      gold = true,
      on = (f.lo == mlo and f.hi == mhi) or nil,
      onClick = function()
        f.lo, f.hi = mlo, mhi
        rerender()
      end,
    })
  end
  -- what nobody reported in Forever yet (E2): one chip on the level's row, off by default, with
  -- the count it would add (the board's shelf), in the kit's dashed outline while off (W4)
  local unconfirmed = Shelf.UnconfirmedCount(all, f, ctx)
  if unconfirmed > 0 or f.unconfirmed then
    if fits(state, 120) then
      separator(state)
    end
    filterPill(state, {
      label = L["unconfirmed"],
      count = unconfirmed,
      on = f.unconfirmed or nil,
      dashed = not f.unconfirmed or nil,
      tip = L["In the game's files, and nobody has reported it in Forever yet. It may not be there."],
      onClick = function()
        f.unconfirmed = not f.unconfirmed or nil
        rerender()
      end,
    })
  end
  -- the chapter's own facets, the largest first, side by side where they fit
  for _, key in ipairs(Shelf.FACETS[chapter] or Shelf.FACETS.all) do
    local counts = Shelf.Counts(all, f, ctx, key)
    if #counts > 1 or (f.facets[key] and next(f.facets[key])) then
      table.sort(counts, function(a, b)
        if type(a.value) == "number" and type(b.value) == "number" then
          return a.value < b.value -- a skill: the lowest first, not the most wonders
        end
        if a.n ~= b.n then
          return a.n > b.n
        end
        return tostring(a.value) < tostring(b.value)
      end)
      group(state, facetLabel(key), false, 90)
      for _, c in ipairs(counts) do
        filterPill(state, {
          label = valueLabel(key, c.value),
          count = c.n,
          on = f.facets[key] and f.facets[key][c.value] or nil,
          onClick = function()
            toggleFacet(f, key, c.value)
          end,
        })
      end
    end
  end
  -- sort; a shelf that is always in one order has no sort group (Gold: newest first, R4.8)
  if not Shelf.FIXED_SORT[chapter] then
    group(state, L["sort"], false, 90)
    for _, s in ipairs({
      { "newest", L["newest"] },
      { "level", L["level"] },
      { "nearest", L["nearest"] },
      { "az", L["A to Z"] },
    }) do
      filterPill(state, {
        label = s[2],
        on = f.sort == s[1] or nil,
        onClick = function()
          f.sort = s[1]
          rerender()
        end,
      })
    end
  end
  -- hide done: a switch at the row's right end; the count of the hidden ones leads to Your diary
  local hide = view.hide
  if not hide then
    hide = newSwitch(view.filters)
    view.hide = hide
  end
  hide.tip = L["What you did, or the game shows done, leaves the shelf. Your diary keeps it."]
  hide:SetScript("OnClick", function()
    f.showDone = not f.showDone
    rerender()
  end)
  local total = hide:Set(not f.showDone, L["Hide done"])
  -- the view's switch (R4.10): two pictograms left of Hide done, the chosen one in gold
  local switch = view.viewSwitch
  if not switch then
    switch = ns.List.NewSwitch(view.filters)
    view.viewSwitch = switch
  end
  switch:Set(Front.View(chapter), function(v)
    Front.SetView(chapter, v)
    rerender()
  end)
  local lead = switch:GetWidth() + Front.SEP_PAD
  total = total + lead
  local done = view.done
  if (hidden or 0) > 0 then
    if not done then
      done = newLink(view.filters)
      view.done = done
    end
    done:SetScript("OnClick", function()
      show({ kind = "record" })
    end)
    total = total + 8 + done:Set(string.format(L["%d done, in Your diary"], hidden))
    done:Show()
  elseif done then
    done:Hide()
  end
  if state.x + Front.SEP_PAD + total > state.right then
    newRow(state)
  end
  local mid = -(state.y + state.rowH / 2)
  switch:ClearAllPoints()
  switch:SetPoint("LEFT", view.filters, "TOPLEFT", state.right - total, mid)
  switch:Show()
  hide:ClearAllPoints()
  hide:SetPoint("LEFT", view.filters, "TOPLEFT", state.right - total + lead, mid)
  hide:Show()
  if done and done:IsShown() then
    done:ClearAllPoints()
    done:SetPoint("RIGHT", view.filters, "TOPLEFT", state.right, mid)
  end
  hideFrom(view.pills, state.p)
  return state:End()
end

-- ---------------------------------------------------------------------------------------------
-- The pages as list items
-- ---------------------------------------------------------------------------------------------

local function rows(out, found, width, ctx, extra)
  local cols = columns(width)
  for i = 1, #found, cols do
    local chunk = {}
    for j = i, min(#found, i + cols - 1) do
      chunk[#chunk + 1] = found[j]
    end
    out[#out + 1] = { kind = "tiles", entries = chunk, ctx = ctx, extra = extra }
  end
end

-- The front table (book.md "The front table", E3): the cabinet of seven tiles, Bastian's note,
-- one entrance per chapter. ~~The hero, New on the table and a strip of tiles per chapter~~
-- (until 23.11.2026, W6).
local function frontItems(all, ctx)
  local front = Shelf.Front(all, ctx)
  local out = {}
  if not front.main and not front.six[1] then
    out[1] = { kind = "note", text = L["The book has no pages yet: the data pack is not loaded."] }
    return out
  end
  out[#out + 1] = { kind = "cabinet", front = front, ctx = ctx }
  out[#out + 1] = {
    kind = "bnote",
    text = ns.Cabinet.Note(ctx),
    act = {
      label = L["Surprise me"],
      tip = L["A wonder you have not done yet, at random."],
      onClick = function()
        local e = Shelf.Surprise(all, ctx, GetTime and GetTime() * 1000 or 0)
        if e then
          openEntry(e)
        end
      end,
    },
  }
  out[#out + 1] = { kind = "entrances", front = front, ctx = ctx }
  return out
end

-- What the filter keeps, in words: every chosen facet with its name ("kind: pet, comes from: a
-- drop / an object"), so two chips of two facets read as both.
local function describe(f, chapter)
  local parts = {}
  if f.zone then
    parts[#parts + 1] = (zoneOf(f.zone) or {}).name
  elseif f.continent then
    parts[#parts + 1] = continentName(f.continent)
  end
  if f.lo then
    parts[#parts + 1] = string.format(L["level %d to %d"], f.lo, f.hi or Shelf.LEVEL_CAP)
  end
  for _, key in ipairs(Shelf.FACETS[chapter] or Shelf.FACETS.all) do
    local vs = {}
    for v in pairs(f.facets[key] or {}) do
      vs[#vs + 1] = valueLabel(key, v)
    end
    table.sort(vs)
    if vs[1] then
      parts[#parts + 1] = facetLabel(key) .. ": " .. table.concat(vs, " / ")
    end
  end
  if f.query and f.query ~= "" then
    parts[#parts + 1] = '"' .. f.query .. '"'
  end
  return table.concat(parts, ", ")
end

-- `found`: what the chapter's filter `f` keeps.
local function shelfItems(chapter, f, found, ctx, width)
  local acts = {
    {
      label = L["Clear all"],
      onClick = function()
        filters[chapter] = Shelf.NewFilter(chapter)
        local box = ns.Window.bar and ns.Window.bar.search
        if box then
          box:SetText("") -- the search is part of the filter
        end
        rerender()
      end,
    },
  }
  if chapter == "gold" then
    table.insert(acts, {
      label = L["The rumour mill"],
      tip = L["This is what they're saying on the road. Make of it what you will."],
      onClick = function()
        show({ kind = "mill" })
      end,
    })
  end
  -- what the filter keeps, in words; an unfiltered shelf says what the chapter is: its sentence
  local said = describe(f, chapter)
  if said == "" then
    said = Front.ChapterLine(chapter) or ""
  end
  local out = {
    -- the done ones stand in the band, beside their switch (until 17.11.2026 in this line)
    {
      kind = "result",
      title = string.format(L["%d wonders"], #found),
      note = said,
      acts = acts,
    },
  }
  if #found == 0 then
    out[#out + 1] =
      { kind = "note", text = L["Nothing here with this filter. Clear a chip, or all of them."] }
  end
  if Front.View(chapter) == "list" and #found > 0 then
    -- the list (R4.10): the columns' heads sort, but a shelf in one fixed order (Gold)
    local fixed = Shelf.FIXED_SORT[chapter]
    out[#out + 1] = {
      kind = "listhead",
      sort = not fixed and f.sort or nil,
      onSort = not fixed and function(sort)
        f.sort = sort
        rerender()
      end or nil,
    }
    for _, e in ipairs(found) do
      out[#out + 1] = { kind = "row", entry = e, ctx = ctx }
    end
  else
    rows(out, found, width, ctx)
  end
  return out
end

-- ---------------------------------------------------------------------------------------------
-- Building and rendering
-- ---------------------------------------------------------------------------------------------

-- The order of the last shelf shown: a details page turns within it (browsing, book.md).
local order, orderIndex = {}, {}

local function remember(items)
  order, orderIndex = {}, {}
  local function add(e)
    if e and not orderIndex[e.id] then
      order[#order + 1] = e
      orderIndex[e.id] = #order
    end
  end
  for _, item in ipairs(items) do
    if item.kind == "hero" then
      add(item.entry)
    elseif item.kind == "tiles" then
      for _, e in ipairs(item.entries) do
        add(e)
      end
    elseif item.kind == "row" then
      add(item.entry) -- the list's rows: the wonder's page turns to its neighbours as on tiles
    end
  end
end

-- -> the place of `id` in the last shelf and the shelf's length; nil when it is not on it.
function Front.Place(id)
  local i = id and orderIndex[id]
  if i then
    return i, #order
  end
  return nil
end

function Front.Neighbour(id, step)
  local i = id and orderIndex[id]
  return i and order[i + step] or nil
end

-- The view under the bar: `top` the room the bar takes (the window's, Window.BarRoom).
function Front.SetTop(top)
  if not view or view.top == top then
    return
  end
  view.top = top
  view:ClearAllPoints()
  -- the content's whole width: the band and the table reach its edges, their padding is inside
  view:SetPoint("TOPLEFT", view.host, "TOPLEFT", 0, -top)
  view:SetPoint("BOTTOMRIGHT", view.host, "BOTTOMRIGHT", 0, 0)
end

-- `host` the window's content, `top` the room the bar takes. -> the view frame.
function Front.Build(host, top)
  view = CreateFrame("Frame", nil, host)
  view.host = host
  Front.SetTop(top)
  view.filters = CreateFrame("Frame", nil, view)
  view.filters:SetPoint("TOPLEFT", view, "TOPLEFT", 0, 0)
  view.filters:SetPoint("TOPRIGHT", view, "TOPRIGHT", 0, 0)
  view.filters:SetHeight(1)
  view.band = S.fill(view.filters, S.C.panel, "BACKGROUND") -- the band's own ground
  view.rule = S.fill(view.filters, S.C.line, "BORDER") -- and the rule under it
  view.rule:ClearAllPoints()
  view.rule:SetPoint("BOTTOMLEFT", view.filters, "BOTTOMLEFT", 0, 0)
  view.rule:SetPoint("BOTTOMRIGHT", view.filters, "BOTTOMRIGHT", 0, 0)
  view.rule:SetHeight(1)
  view.pills = {}
  -- Core's band lays the groups out; its ground and rule are the book's own two textures above
  -- (the dark table on a dark theme)
  view.flow = B.UI.Band(view, { frame = view.filters, ground = false })
  view.labels, view.seps = view.flow.labels, view.flow.seps
  view.body = CreateFrame("Frame", nil, view)
  view.body:SetPoint("TOPLEFT", view.filters, "BOTTOMLEFT", 0, 0)
  view.body:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", 0, 0)
  view.table = S.fill(view.body, S.C.folioTable, "BACKGROUND") -- the dark table (the WoW look)
  -- the shelf: the table's padding around the list (the list keeps room for its scroll bar)
  view.shelf = CreateFrame("Frame", nil, view.body)
  view.shelf:SetPoint("TOPLEFT", view.body, "TOPLEFT", Front.BAND_SIDE, -Front.TABLE_TOP)
  view.shelf:SetPoint(
    "BOTTOMRIGHT",
    view.body,
    "BOTTOMRIGHT",
    -(Front.BAND_SIDE - B.UI.VirtualList.BAR_ROOM),
    0
  )
  list = B.UI.VirtualList.New(view.shelf, { kinds = KINDS, gap = Front.GAP })
  local lastW
  view.body:SetScript("OnSizeChanged", function(self)
    local w = floor(self:GetWidth() or 0)
    if w > 0 and w ~= lastW then
      lastW = w
      if ns.mod and view:IsShown() then
        ns.mod:Coalesce("book.front", 0.05, rerender)
      end
    end
  end)
  view:Hide()
  Front.view, Front.list = view, list
  return view
end

-- Renders `entry` ({ kind = "front" | "shelf", id }) -> the page's title.
function Front.Render(entry)
  current = entry
  local all = Front.Entries()
  local ctx = Front.Ctx()
  local width = (view:GetWidth() or 0) > 0 and view:GetWidth() or 900
  local listW = width - 2 * Front.BAND_SIDE
  local title, items
  ground(entry.kind == "shelf")
  if entry.kind == "shelf" then
    local chapter = entry.id or "all"
    local f = Front.Filter(chapter)
    local found, hidden = Shelf.Filter(all, f, ctx)
    view.filters:SetHeight(layFilters(chapter, all, ctx, width, hidden))
    view.filters:Show()
    items = shelfItems(chapter, f, found, ctx, listW)
    title = Front.ChapterName(chapter)
  else
    hideFrom(view.labels, 0)
    hideFrom(view.pills, 0)
    hideFrom(view.seps, 0)
    if view.slider then
      view.slider:Hide()
    end
    if view.hide then
      view.hide:Hide()
    end
    if view.viewSwitch then
      view.viewSwitch:Hide()
    end
    if view.done then
      view.done:Hide()
    end
    view.filters:SetHeight(1)
    items = frontItems(all, ctx)
    title = L["The front table"]
  end
  remember(items)
  list:SetItems(items)
  return title
end

-- The tiles in view (for the tests and the scan's count): the entries' ids, top first.
function Front.TilesInView()
  local out = {}
  for _, row in ipairs(list and list:Rows() or {}) do
    for _, t in ipairs(row.tiles or {}) do
      if t:IsShown() and t.entry then
        out[#out + 1] = t.entry.id
      end
    end
    if row.entry and row:IsShown() then
      out[#out + 1] = row.entry.id
    end
  end
  return out
end

-- How many tile frames exist (only the rows in view have frames).
function Front.TileFrames()
  local n = 0
  for _, pool in pairs(list and list.pools or {}) do
    for _, row in ipairs(pool) do
      n = n + #(row.tiles or {})
    end
  end
  for _, row in ipairs(list and list.used or {}) do
    n = n + #(row.tiles or {})
  end
  return n
end

function Front.Search(text)
  local chapter = (current and current.kind == "shelf" and current.id) or "all"
  local f = Front.Filter(chapter)
  f.query = text or ""
  show({ kind = "shelf", id = chapter })
end
