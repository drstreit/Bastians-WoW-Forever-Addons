-- Bastian's Book: the front table, the category pages and Your record (book.md "The pages"):
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
Front.HERO_RATIO = 2.6 -- the hero: its width over its height, the drawing cut to it (Picture.Cover)
Front.HERO_MIN, Front.HERO_MAX = 220, 480
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

-- Core's textures (tools/make_media.py), each path whole so the texture check can find its file
Front.SHADOW = "Interface\\AddOns\\Bastians_Core\\Media\\FolioShadow"
Front.DECKLE = "Interface\\AddOns\\Bastians_Core\\Media\\Deckle"
Front.FADE = "Interface\\AddOns\\Bastians_Core\\Media\\Fade"
Front.SHADOW_SPREAD = 12 -- px the shadow reaches beyond a card
Front.SHADOW_DROP = 4 -- px it falls lower than the card
Front.DECKLE_H = 12 -- the torn edge at a picture's foot
Front.CHIP_H = 18 -- a chip on a card

-- The shadow: eight pieces of the soft square around the card (its quarters the corners, its
-- middle row and column the sides), under the card's paper.
local function shadow(t)
  local s, drop = Front.SHADOW_SPREAD, Front.SHADOW_DROP
  local c = 2 * s
  local function piece(l, r, top, bottom)
    local tex = t:CreateTexture(nil, "BACKGROUND", nil, -8)
    tex:SetTexture(Front.SHADOW)
    tex:SetTexCoord(l, r, top, bottom)
    S.tint(tex, S.C.folioShadow)
    return tex
  end
  local tl, tr = piece(0, 0.5, 0, 0.5), piece(0.5, 1, 0, 0.5)
  local bl, br = piece(0, 0.5, 0.5, 1), piece(0.5, 1, 0.5, 1)
  for _, corner in ipairs({ tl, tr, bl, br }) do
    corner:SetSize(c, c)
  end
  tl:SetPoint("TOPLEFT", t, "TOPLEFT", -s, s - drop)
  tr:SetPoint("TOPRIGHT", t, "TOPRIGHT", s, s - drop)
  bl:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", -s, -s - drop)
  br:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", s, -s - drop)
  local top, bottom = piece(0.49, 0.51, 0, 0.5), piece(0.49, 0.51, 0.5, 1)
  local left, right = piece(0, 0.5, 0.49, 0.51), piece(0.5, 1, 0.49, 0.51)
  top:SetPoint("TOPLEFT", tl, "TOPRIGHT")
  top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
  bottom:SetPoint("TOPLEFT", bl, "TOPRIGHT")
  bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
  left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT")
  left:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
  right:SetPoint("TOPLEFT", tr, "BOTTOMLEFT")
  right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
  t.shadow = { tl, tr, bl, br, top, bottom, left, right }
end

-- A card's paper; under the mouse its edge in the book's gold. Drawn plain again on every fill:
-- the list hands a card on under a resting mouse.
local function plate(t, hot)
  S.tint(t.face, S.C.folioPaper)
  S.setEdges(t.edges, S.C.folioGold, hot and 1 or 0)
end
Front.Plate = plate

local function paperFrame(parent)
  local t = CreateFrame("Button", nil, parent)
  shadow(t)
  t.face = S.roundFill(t, S.C.folioPaper, "radiusSmall")
  t.edges = S.roundEdges(t, S.C.folioGold, "radiusSmall")
  t:SetScript("OnClick", function(self)
    if self.entry then
      openEntry(self.entry)
    end
  end)
  t:SetScript("OnEnter", function(self)
    plate(self, true)
  end)
  t:SetScript("OnLeave", function(self)
    plate(self, false)
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
  t.tear = CreateFrame("Frame", nil, t)
  t.tear:SetFrameLevel(t:GetFrameLevel() + 8)
  t.tear:SetHeight(Front.DECKLE_H)
  t.tear.tex = t.tear:CreateTexture(nil, "ARTWORK")
  t.tear.tex:SetTexture(Front.DECKLE)
  t.tear.tex:SetAllPoints(t.tear)
  S.tint(t.tear.tex, S.C.folioPaper)
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
  plate(t, false)
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
  local sealed = (e.kind == "chain" or e.kind == "unsolved") and not Record.IsOpened(e.id)
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

-- The hero's height: the window's width over HERO_RATIO, within its bounds; the drawing is cut to
-- it, never stretched (Picture.Cover).
function Front.HeroHeight(width)
  return max(Front.HERO_MIN, min(Front.HERO_MAX, floor(width / Front.HERO_RATIO)))
end

-- The hero: the picture the whole width, its words on a fade into the dark at its foot (the
-- concept board's front table), ~~in a dark box~~.
KINDS.hero = {
  make = function(parent)
    local f = paperFrame(parent)
    f.pic = Picture.New(f)
    f.pic:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.shade = CreateFrame("Frame", nil, f)
    f.shade:SetFrameLevel(f:GetFrameLevel() + 7)
    f.shade:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    f.shade:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    f.shade.tex = f.shade:CreateTexture(nil, "ARTWORK")
    f.shade.tex:SetTexture(Front.FADE)
    f.shade.tex:SetAllPoints(f.shade)
    S.tint(f.shade.tex, S.C.folioShade)
    f.cap = CreateFrame("Frame", nil, f)
    f.cap:SetFrameLevel(f:GetFrameLevel() + 8)
    f.hook = bookText(f.cap, 13, S.C.folioShadeText, "bookItalic", true)
    f.hook:SetJustifyV("BOTTOM")
    f.hook:SetPoint("BOTTOMLEFT", f.cap, "BOTTOMLEFT", 0, 0)
    f.title = bookText(f.cap, 18, S.C.folioShadeText, "bookDisplay")
    f.title:SetPoint("BOTTOMLEFT", f.hook, "TOPLEFT", 0, 6)
    f.kind = bookText(f.cap, 11, S.C.folioGold, "bookCaps")
    f.kind:SetPoint("BOTTOMLEFT", f.title, "TOPLEFT", 0, 5)
    f.ribbon = CreateFrame("Frame", nil, f)
    f.ribbon:SetFrameLevel(f:GetFrameLevel() + 9)
    f.ribbon.fill = S.fill(f.ribbon, S.C.folioSeal, "BACKGROUND")
    f.ribbon.text = bookText(f.ribbon, 11, S.C.folioSealText, "bookCaps")
    f.ribbon.text:SetPoint("CENTER")
    return f
  end,
  fill = function(f, item, width)
    local h = Front.HeroHeight(width)
    if not f.vlKind then
      return h
    end
    local e, ctx = item.entry, item.ctx
    f.entry = e
    plate(f, false)
    Picture.Draw(f.pic, e, width, h)
    f.shade:SetHeight(min(h, max(140, floor(h * 0.62))))
    local capW = min(width - 48, max(300, floor(width * 0.55)))
    f.cap:ClearAllPoints()
    f.cap:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 24, 20)
    f.cap:SetSize(capW, 120)
    f.kind:SetWidth(capW)
    f.kind:SetText(lower(Front.KindLabel(e)))
    f.title:SetWidth(capW)
    f.title:SetText(e.title)
    f.hook:SetSize(capW, 34)
    f.hook:SetText(e.hook or e.tale or "")
    local new = Shelf.IsNew(e, ctx.today)
    f.ribbon:SetShown(new)
    if new then
      f.ribbon.text:SetText(lower(string.format(L["new, %s"], e.added or "")))
      f.ribbon:SetSize(f.ribbon.text:GetStringWidth() + 16, 19)
      f.ribbon:ClearAllPoints()
      f.ribbon:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -14)
    end
    return h
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
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", f, "TOPLEFT", (i - 1) * (w + Front.GAP), 0)
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
-- should be same as artifact", D2 "WoW look only"): the dark table where the look is the game's,
-- the theme's own elsewhere. The band's and the shelf's widgets ask the palette set here (S.Tok).
local function ground(shelf)
  local dark = S.LookOf(view) == "wow"
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
-- the level's as high as its slider; everything in it sits on its middle.
local function label(state, text, x)
  state.n = state.n + 1
  local fs = view.labels[state.n]
  if not fs then
    fs = Front.BookText(view.filters, 11, S.C.dim, "bookCaps")
    view.labels[state.n] = fs
  end
  S.ink(fs, S.Tok(view.filters, "dim"))
  fs:ClearAllPoints()
  fs:SetPoint("LEFT", view.filters, "TOPLEFT", x, -(state.y + state.rowH / 2))
  fs:SetText(Front.SmallCaps(text)) -- small capitals: the face sets them
  fs:Show()
  local w = fs:GetStringWidth()
  return (w and w > 0) and w or (#text * 6)
end

local function newRow(state, h)
  if state.started then
    state.y = state.y + state.rowH + Front.ROW_GAP
  end
  state.rowH = h or chipHeight()
  state.x = Front.BAND_SIDE + Front.LABEL_W
  state.started = true
end

-- A thin line between two groups on one row.
local function separator(state)
  state.s = state.s + 1
  local line = view.seps[state.s]
  if not line then
    line = S.fill(view.filters, S.C.line, "ARTWORK")
    view.seps[state.s] = line
  end
  S.tint(line, S.Tok(view.filters, "line"))
  local x = state.x - CHIP_GAP + Front.SEP_PAD
  line:ClearAllPoints()
  line:SetSize(1, Front.SEP_H)
  line:SetPoint("LEFT", view.filters, "TOPLEFT", x, -(state.y + state.rowH / 2))
  line:Show()
  state.x = x + 1 + Front.SEP_PAD
end

-- Whether `need` px still fit on the row after a separator.
local function fits(state, need)
  return state.started and state.x + 2 * Front.SEP_PAD + need <= state.right
end

-- Opens a group; `need` the room its first chips take, so a group never begins at a row's end.
-- `own`: on a row of its own, `h` high.
local function group(state, text, own, need, h)
  if own or not fits(state, #text * 6 + 8 + (need or 80)) then
    newRow(state, h)
    local w = label(state, text, Front.BAND_SIDE)
    state.x = max(state.x, Front.BAND_SIDE + w + 8) -- a long label pushes its chips
    return
  end
  separator(state)
  state.x = state.x + label(state, text, state.x) + 8
end

-- How far under a row's top a part of height `h` sits to stand on the row's middle, in whole
-- units. Rounded, not cut: the game answers a chip's 22 as 22.00002, and cutting put every chip
-- one unit too high (the band's padding 9 for 10, measured in Forever 17.11.2026; R4.14).
function Front.Centre(rowH, h)
  return floor((rowH - h) / 2 + 0.5)
end

-- Puts `frame` (w x h) on the row, on a new one when it does not fit.
local function place(state, frame, w, h)
  if state.x + w > state.right and state.x > Front.BAND_SIDE + Front.LABEL_W then
    newRow(state)
  end
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", view.filters, "TOPLEFT", state.x, -(state.y + Front.Centre(state.rowH, h)))
  state.x = state.x + w + CHIP_GAP
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

-- Hide done as a switch (the concept board's): the bar filled while done wonders are hidden.
local function newSwitch(parent)
  local b = CreateFrame("Button", nil, parent)
  b.bar = CreateFrame("Frame", nil, b)
  b.bar:SetSize(28, 15)
  b.bar:SetPoint("LEFT", b, "LEFT", 0, 0)
  b.bar.face = S.roundFill(b.bar, S.C.accent, "pill", "ARTWORK")
  b.knob = CreateFrame("Frame", nil, b.bar)
  b.knob:SetSize(11, 11)
  b.knob.face = S.roundFill(b.knob, S.C.bg, "pill", "OVERLAY")
  b.words = bookText(b, 11, S.C.text, "bookSans")
  b.words:SetPoint("LEFT", b.bar, "RIGHT", 6, 0)
  b:SetScript("OnEnter", S.TipEnter)
  b:SetScript("OnLeave", S.TipLeave)
  -- -> its width
  function b.Set(self, on, text)
    self.on = on and true or false
    S.tint(self.bar.face, S.Tok(self, on and "accent" or "muted"))
    S.tint(self.knob.face, S.Tok(self, "bg"))
    self.knob:ClearAllPoints()
    self.knob:SetPoint(on and "RIGHT" or "LEFT", self.bar, on and "RIGHT" or "LEFT", on and -2 or 2, 0)
    S.ink(self.words, S.Tok(self, "text"))
    self.words:SetText(text)
    local w = self.words:GetStringWidth()
    self:SetSize(28 + 6 + ((w and w > 0) and w or (#text * 6)), chipHeight())
    return self:GetWidth()
  end
  return b
end

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
  local state = {
    x = Front.BAND_SIDE + Front.LABEL_W,
    y = Front.BAND_TOP,
    rowH = chipHeight(),
    right = width - Front.BAND_SIDE,
    n = 0,
    p = 0,
    s = 0,
  }
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
  -- the count it would add (the board's shelf; its dashed outline comes with the kit, W4)
  local unconfirmed = Shelf.UnconfirmedCount(all, f, ctx)
  if unconfirmed > 0 or f.unconfirmed then
    if fits(state, 120) then
      separator(state)
    end
    filterPill(state, {
      label = L["unconfirmed"],
      count = unconfirmed,
      on = f.unconfirmed or nil,
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
  -- hide done: a switch at the row's right end; the count of the hidden ones leads to Your record
  local hide = view.hide
  if not hide then
    hide = newSwitch(view.filters)
    view.hide = hide
  end
  hide.tip = L["What you did, or the game shows done, leaves the shelf. Your record keeps it."]
  hide:SetScript("OnClick", function()
    f.showDone = not f.showDone
    rerender()
  end)
  local total = hide:Set(not f.showDone, L["Hide done"])
  local done = view.done
  if (hidden or 0) > 0 then
    if not done then
      done = newLink(view.filters)
      view.done = done
    end
    done:SetScript("OnClick", function()
      show({ kind = "record" })
    end)
    total = total + 8 + done:Set(string.format(L["%d done, in Your record"], hidden))
    done:Show()
  elseif done then
    done:Hide()
  end
  if state.x + Front.SEP_PAD + total > state.right then
    newRow(state)
  end
  local mid = -(state.y + state.rowH / 2)
  hide:ClearAllPoints()
  hide:SetPoint("LEFT", view.filters, "TOPLEFT", state.right - total, mid)
  hide:Show()
  if done and done:IsShown() then
    done:ClearAllPoints()
    done:SetPoint("RIGHT", view.filters, "TOPLEFT", state.right, mid)
  end
  hideFrom(view.labels, state.n)
  hideFrom(view.pills, state.p)
  hideFrom(view.seps, state.s)
  return state.y + state.rowH + Front.BAND_FOOT
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

local function frontItems(all, ctx, width)
  local front = Shelf.Front(all, ctx)
  local out = {}
  if not front.hero then
    out[1] = { kind = "note", text = L["The book has no pages yet: the data pack is not loaded."] }
    return out
  end
  out[#out + 1] = { kind = "hero", entry = front.hero, ctx = ctx }
  out[#out + 1] = {
    kind = "head",
    title = L["New on the table"],
    note = L["what came in last, and what the day turned up"],
    acts = {
      {
        icon = "rare",
        label = L["Surprise me"],
        tip = L["A wonder you have not done yet, at random."],
        onClick = function()
          local e = Shelf.Surprise(all, ctx, GetTime and GetTime() * 1000 or 0)
          if e then
            openEntry(e)
          end
        end,
      },
    },
  }
  rows(out, front.new, width, ctx)
  for _, strip in ipairs(front.strips) do
    local chapter = strip.chapter
    out[#out + 1] = {
      kind = "head",
      title = Front.ChapterName(chapter),
      note = string.format(L["%d to find"], strip.total),
      acts = {
        {
          label = L["all of them"],
          onClick = function()
            show({ kind = "shelf", id = chapter })
          end,
        },
      },
    }
    local cols = columns(width)
    local some = {}
    for i = 1, min(cols, #strip.entries) do
      some[i] = strip.entries[i]
    end
    rows(out, some, width, ctx)
  end
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
  rows(out, found, width, ctx)
  return out
end

local NOTHING_DONE = "Nothing done yet on this character. Mark a wonder done, or the book finds it"
  .. " in your quest history, bags and titles."

local function recordItems(ctx, width)
  local out = {}
  local marks = ns.mod and ns.mod.db and ns.mod.db.char.bookmarks or {}
  local kept = {}
  for _, id in ipairs(marks) do
    local e = Front.Find(id)
    if e then
      kept[#kept + 1] = e
    end
  end
  out[#out + 1] =
    { kind = "head", title = L["Kept for later"], note = string.format(L["%d bookmarks"], #kept) }
  if #kept == 0 then
    out[#out + 1] = { kind = "note", text = L["Bookmark a page to keep it here."] }
  end
  rows(out, kept, width, ctx)
  local lists = Record.Lists()
  local byChapter = {}
  for _, d in ipairs(lists.mine) do
    local e = Front.Find(d.id)
    if e then
      byChapter[e.chapter] = byChapter[e.chapter] or {}
      table.insert(byChapter[e.chapter], e)
    end
  end
  local any = false
  for _, chapter in ipairs(Shelf.CHAPTERS) do
    local done = byChapter[chapter]
    if done then
      any = true
      out[#out + 1] = {
        kind = "head",
        title = string.format(L["Done: %s"], Front.ChapterName(chapter)),
        note = string.format(L["%d by %s"], #done, (Record.Mine() or {}).name or UnitName("player") or ""),
      }
      rows(out, done, width, ctx, function(e)
        local d = Record.Entry(e.id) or {}
        return {
          label = (d.how == "found" and L["found, not done yet?"]) or L["Not done yet"],
          onClick = function()
            Record.Unmark(e.id)
            rerender()
          end,
        }
      end)
    end
  end
  if not any then
    out[#out + 1] = { kind = "head", title = L["Done"] }
    out[#out + 1] = {
      kind = "note",
      text = L[NOTHING_DONE],
    }
  end
  local alts = {}
  for _, a in ipairs(lists.alts) do
    local e = Front.Find(a.id)
    if e then
      alts[#alts + 1] = e
    end
  end
  if alts[1] then
    out[#out + 1] = {
      kind = "head",
      title = L["Your other characters"],
      note = string.format(L["%d done by them, not by you"], #alts),
    }
    rows(out, alts, width, ctx)
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
  view.labels, view.pills, view.seps = {}, {}, {}
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

-- Renders `entry` ({ kind = "front" | "shelf" | "record", id }) -> the page's title.
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
    if view.done then
      view.done:Hide()
    end
    view.filters:SetHeight(1)
    if entry.kind == "record" then
      items = recordItems(ctx, listW)
      title = L["Your record"]
    else
      items = frontItems(all, ctx, listW)
      title = L["The front table"]
    end
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
