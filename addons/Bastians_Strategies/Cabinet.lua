-- Bastian's Book: the front table (book.md "The front table", E3; book-look.md 10.2 and 10.3;
-- R4.6 and R4.7): the cabinet of seven tiles, Bastian's note and one entrance per chapter.
local _, ns = ...
local B = Bastians
local S = B.UI.Style
local L = ns.L
local Front, Shelf, Picture, Record = ns.Front, ns.Shelf, ns.Picture, ns.Record

local Cabinet = {}
ns.Cabinet = Cabinet

local floor, max, min = math.floor, math.max, math.min

Cabinet.GAP = 11 -- between two cells (the gap between tiles, book-look.md section 6)
Cabinet.SIDE = 15 -- the table's side padding: the widths below are the window's
Cabinet.THREE, Cabinet.TWO = 900, 600 -- three columns from this width of the window, two from this
Cabinet.RADIUS = 5
Cabinet.PAD, Cabinet.PAD_MAIN = 11, 16 -- a tile's words from its edge; the main tile's
Cabinet.SHADE = 0.45 -- the fade into the dark covers this much of a picture, from its foot
Cabinet.TITLE, Cabinet.TITLE_MAIN = 18, 27 -- the display size is the main tile's alone (D3)
Cabinet.LINE_MAIN = 30 -- the main title's line: at most two
Cabinet.HOOK_H = 34 -- Bastian's line: two lines of 13
Cabinet.SEAL = 41 -- a sealed letter's seal
Cabinet.SLOT, Cabinet.SLOT_GAP = 22, 4 -- a collection's slots
Cabinet.ICON = 64 -- a camp item's icon on its mat
Cabinet.CAMP_BODY = 44 -- a camp tile's words under the mat
Cabinet.NOTE_H = 58 -- Bastian's note
Cabinet.PORTRAIT, Cabinet.RING = 39, 2 -- his portrait in its ring
Cabinet.ENTRANCE_H = 92 -- a chapter's entrance
Cabinet.ENTRANCE_NARROW, Cabinet.ENTRANCE_LINE = 250, 15 -- under this width a card's sentence takes
-- a third line of 15 (the card grows by it)
Cabinet.ENTRANCES_WIDE, Cabinet.ENTRANCES_ROWS = 5, 3 -- five in a row; three and two under THREE

-- ---------------------------------------------------------------------------------------------
-- The cells (pure)
-- ---------------------------------------------------------------------------------------------

-- The cabinet in a table `width` wide (the list's width: the window's less its side padding).
-- -> { cols, c, h (a cell), height, rects = { { x, y, w, h, slot, role } } }: slot 0 is the main
-- tile, 1 the tall one, 5 the wide one, 2, 3, 4 and 6 the single cells; y grows downwards.
function Cabinet.Layout(width)
  local window = width + 2 * Cabinet.SIDE
  local cols = window >= Cabinet.THREE and 3 or (window >= Cabinet.TWO and 2 or 1)
  local g = Cabinet.GAP
  local c = floor((width - (cols - 1) * g) / cols)
  local h = floor((c - g) / 2)
  local rects = {}
  local function cell(col, row, wide, tall, slot, role)
    rects[#rects + 1] = {
      x = col * (c + g),
      y = row * (h + g),
      w = wide * c + (wide - 1) * g,
      h = tall * h + (tall - 1) * g,
      slot = slot,
      role = role,
    }
  end
  local rows
  if cols == 3 then
    cell(0, 0, 2, 2, 0, "main")
    cell(2, 0, 1, 2, 1, "tall")
    cell(0, 2, 1, 1, 2, "single")
    cell(1, 2, 1, 1, 3, "single")
    cell(2, 2, 1, 1, 4, "single")
    cell(0, 3, 2, 1, 5, "wide")
    cell(2, 3, 1, 1, 6, "single")
    rows = 4
  elseif cols == 2 then
    cell(0, 0, 2, 2, 0, "main")
    cell(0, 2, 1, 2, 1, "tall")
    cell(1, 2, 1, 1, 2, "single")
    cell(1, 3, 1, 1, 3, "single")
    cell(0, 4, 1, 1, 4, "single")
    cell(1, 4, 1, 1, 6, "single")
    cell(0, 5, 2, 1, 5, "wide")
    rows = 6
  else
    cell(0, 0, 1, 2, 0, "main")
    cell(0, 2, 1, 2, 1, "tall")
    for i = 2, 6 do
      cell(0, 2 + i, 1, 1, i, i == 5 and "wide" or "single")
    end
    rows = 9
  end
  return { cols = cols, c = c, h = h, rects = rects, height = rows * h + (rows - 1) * g }
end

-- The entrances' cells in a table `width` wide -> { rects = { { x, y, w, h } } (one per
-- chapter), height }: five in a row, three and two under THREE, one column under TWO.
function Cabinet.Entrances(width, n)
  n = n or #Shelf.CHAPTERS
  local window = width + 2 * Cabinet.SIDE
  local per = window >= Cabinet.THREE and Cabinet.ENTRANCES_WIDE
    or (window >= Cabinet.TWO and Cabinet.ENTRANCES_ROWS or 1)
  per = min(per, max(1, n))
  local g, h = Cabinet.GAP, Cabinet.ENTRANCE_H
  local w = floor((width - (per - 1) * g) / per)
  -- a narrow card gives its sentence a third line (the windows probe, 24.11.2026: at 1,100 the
  -- five cards are 205 wide and Collections' sentence needed three lines of the card's two)
  local lines = w < Cabinet.ENTRANCE_NARROW and 3 or 2
  if lines == 3 then
    h = h + Cabinet.ENTRANCE_LINE
  end
  local rects = {}
  for i = 1, n do
    local col, row = (i - 1) % per, floor((i - 1) / per)
    rects[i] = { x = col * (w + g), y = row * (h + g), w = w, h = h }
  end
  local rows = floor((n - 1) / per) + 1
  return { rects = rects, per = per, height = rows * h + (rows - 1) * g, lines = lines }
end

-- ---------------------------------------------------------------------------------------------
-- What a tile holds
-- ---------------------------------------------------------------------------------------------

-- The six in their slots: the collection (when the table has one) on the wide tile, the best
-- of the others on the tall one, the rest in the table's order. -> { [1..6] = entry }
function Cabinet.Slots(front)
  local six = {}
  for i, e in ipairs(front.six or {}) do
    six[i] = e
  end
  local coll = front.collection and front.collection.entry
  if coll then
    for i, e in ipairs(six) do
      if e == coll and i ~= 5 and six[5] then
        six[i], six[5] = six[5], e
        break
      end
    end
  end
  return six
end

-- The kind of tile an entry is drawn as: "collection" (the wide tile's, when the table has
-- one), "letter" (a secret not yet opened), "camp" (a camp item or kit), else "picture" (a
-- drawing with its words on it, or a creature on its zone: Picture.Draw decides).
function Cabinet.KindOf(e, front, slot)
  local coll = front and front.collection
  if slot == 5 and coll and coll.entry == e then
    return "collection"
  end
  if e.chapter == "secrets" and (e.kind == "chain" or e.kind == "unsolved") and not Record.IsOpened(e.id) then
    return "letter"
  end
  if e.chapter == "camp" and (e.kind == "camp item" or e.kind == "camp kit") then
    return "camp"
  end
  return "picture"
end

local function levelWords(e)
  if not (e.levelMin or e.levelMax) then
    return nil
  end
  local lo, hi = e.levelMin or 1, e.levelMax
  if hi and hi ~= lo then
    return string.format(L["level %d to %d"], lo, hi)
  end
  return string.format(hi and L["level %d"] or L["level %d+"], lo)
end

local function zoneName(e)
  local z = e.zones and e.zones[1]
  local zone = z and Front.ZoneOf(z)
  return zone and zone.name or nil
end

-- The line over a tile's title: what it is, where, for which level; the main tile's says that
-- it is the newest gold story and of which day.
function Cabinet.Eyebrow(e, main)
  local parts = {}
  if main then
    parts[1] = L["the newest gold story"]
    local m, d = string.match(e.added or "", "^%d+%-(%d+)%-(%d+)")
    if m then
      parts[#parts + 1] = d .. "." .. m
    end
  else
    local kind = Front.KindLabel(e)
    if kind and kind ~= "" then
      parts[1] = kind
    end
    parts[#parts + 1] = zoneName(e)
  end
  parts[#parts + 1] = levelWords(e)
  return table.concat(parts, "  -  ")
end

-- A camp item's line: its chapter, the profession and the skill it needs.
function Cabinet.CampLine(e)
  local parts = { Front.ChapterName("camp") }
  local f = e.facets or {}
  if f.profession then
    parts[#parts + 1] = tostring(f.profession) .. (f.skill and (" " .. tostring(f.skill)) or "")
  end
  return table.concat(parts, "  -  ")
end

-- A collection's name on its tile.
local COLLECTIONS = {
  mount = "Mounts",
  pet = "Companions",
  title = "Titles",
  ["library book"] = "The library's books",
}
function Cabinet.CollectionName(kind)
  return L[COLLECTIONS[kind] or "Collections"]
end

-- An entrance's count: "29 open, 3 near you", "41 open".
function Cabinet.Count(c)
  if (c.near or 0) > 0 then
    return string.format(L["%d open, %d near you"], c.open or 0, c.near)
  end
  return string.format(L["%d open"], c.open or 0)
end

-- Bastian's note under the cabinet: where you are and what that does to the table.
function Cabinet.Note(ctx)
  local here = ctx and ctx.here
  local zone = here and here.map and Front.ZoneOf(here.map)
  if zone and zone.name and ctx.level then
    return string.format(
      L["You are in %s and you are level %d, so today the table holds what is near you and what fits you. It changes when you move on."], -- luacheck: ignore 631 (a locale key stays one literal)
      zone.name,
      ctx.level
    )
  end
  return L["Today the table holds what the day turned up. It changes when you move on."]
end

-- ---------------------------------------------------------------------------------------------
-- A tile of the cabinet
-- ---------------------------------------------------------------------------------------------

local function text(parent, size, token, role, wrap)
  return Front.BookText(parent, size, S.C[token], role, wrap)
end

local function newTile(parent)
  local t = CreateFrame("Button", nil, parent)
  t.ground = S.roundFill(t, S.C.folioBarTop, Cabinet.RADIUS)
  t.paper = S.roundFill(t, S.C.folioPaper, Cabinet.RADIUS, "BORDER")
  t.pic = Picture.New(t)
  t.pic:SetPoint("TOPLEFT", t, "TOPLEFT", 0, 0)
  t.shade = S.fade(t, 7, "folioShade")
  t.shade:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 0, 0)
  t.shade:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 0, 0)
  -- the camp item's mat and what lies on it
  t.mat = S.fill(t, S.C.folioMat, "ARTWORK")
  t.icon = t:CreateTexture(nil, "OVERLAY")
  t.icon:SetSize(Cabinet.ICON, Cabinet.ICON)
  -- the words, over the picture and its model
  t.cap = CreateFrame("Frame", nil, t)
  t.cap:SetAllPoints(t)
  t.cap:SetFrameLevel(t:GetFrameLevel() + 8)
  t.eb = text(t.cap, 11, "folioGold", "bookCaps")
  t.ti = text(t.cap, Cabinet.TITLE, "folioShadeText", "bookDisplay", true)
  t.ho = text(t.cap, 13, "folioShadeText", "bookItalic", true)
  t.ho:SetJustifyV("BOTTOM")
  t.ct = text(t.cap, 13, "folioInkSoft", "bookSans")
  -- a sealed letter's seal: wax with the lock on it
  t.seal = t.cap:CreateTexture(nil, "ARTWORK")
  t.seal:SetTexture(S.DISC)
  t.seal:SetSize(Cabinet.SEAL, Cabinet.SEAL)
  t.lock = t.cap:CreateTexture(nil, "OVERLAY")
  t.lock:SetTexture(B.UI.IconTexture("lock"))
  t.lock:SetSize(floor(Cabinet.SEAL * 0.6), floor(Cabinet.SEAL * 0.6))
  t.lock:SetPoint("CENTER", t.seal, "CENTER", 0, 0)
  t.slots = {}
  t.more = text(t.cap, 11, "folioInkSoft", "bookSans")
  t.ribbon = CreateFrame("Frame", nil, t.cap)
  t.ribbon.fill = S.roundFill(t.ribbon, S.C.folioSeal, 3)
  t.ribbon.text = text(t.ribbon, 11, "folioSealText", "bookCaps")
  t.ribbon.text:SetPoint("CENTER")
  t:SetScript("OnClick", function(self)
    if self.onClick then
      self.onClick()
    elseif self.entry then
      Front.OpenEntry(self.entry)
    end
  end)
  t:SetScript("OnEnter", S.TipEnter)
  t:SetScript("OnLeave", S.TipLeave)
  -- an object of the table (R4.6); after the tile's own scripts: the object hooks them
  S.object(t, { radius = Cabinet.RADIUS })
  return t
end
Cabinet.NewTile = newTile

local function hideAll(t)
  local parts = { t.shade, t.mat, t.icon, t.eb, t.ti, t.ho, t.ct, t.seal, t.lock, t.more, t.ribbon }
  for _, part in ipairs(parts) do
    part:Hide()
  end
  for _, slot in ipairs(t.slots) do
    slot:Hide()
  end
  t.pic:Hide()
  Picture.Clear(t.pic)
  t.paper:Hide()
  t.onClick, t.tip = nil, nil
end

-- A title of `size` in a box `w` wide and at most `lines` lines high.
local function setTitle(t, title, size, token, w, lines)
  S.setSize(t.ti, size)
  S.ink(t.ti, S.C[token])
  t.ti:SetWidth(w)
  if t.ti.SetMaxLines then
    t.ti:SetMaxLines(lines)
  end
  t.ti:SetText(title or "")
  t.ti:Show()
end

local function ribbon(t, e, ctx, pad)
  if not Shelf.IsNew(e, ctx.today) then
    return
  end
  t.ribbon.text:SetText(S.SmallCaps(L["new"]))
  t.ribbon:SetSize((t.ribbon.text:GetStringWidth() or 20) + 14, 19)
  t.ribbon:ClearAllPoints()
  t.ribbon:SetPoint("TOPLEFT", t, "TOPLEFT", pad - 2, -(pad - 2))
  t.ribbon:Show()
end

-- A drawing with its words on it, or a creature on its zone: the picture fills the tile (cut,
-- never stretched), its lower part fades into the dark, the words stand on the fade.
local function fillPicture(t, e, w, h, role, ctx)
  local main = role == "main"
  local pad = main and Cabinet.PAD_MAIN or Cabinet.PAD
  t.pic:Show()
  t.drew = Picture.Draw(t.pic, e, w, h)
  t.shade:SetHeight(max(60, floor(h * Cabinet.SHADE)))
  t.shade:Show()
  local y = pad
  if main or role == "tall" then
    t.ho:ClearAllPoints()
    t.ho:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", pad, y)
    t.ho:SetSize(w - 2 * pad, Cabinet.HOOK_H)
    t.ho:SetText(e.hook or e.tale or "")
    t.ho:Show()
    y = y + Cabinet.HOOK_H + 5
  end
  setTitle(
    t,
    e.title,
    main and Cabinet.TITLE_MAIN or Cabinet.TITLE,
    "folioShadeText",
    w - 2 * pad,
    main and 2 or 1
  )
  t.ti:SetJustifyH("LEFT")
  t.ti:ClearAllPoints()
  t.ti:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", pad, y)
  t.eb:ClearAllPoints()
  t.eb:SetPoint("BOTTOMLEFT", t.ti, "TOPLEFT", 0, 5)
  t.eb:SetWidth(w - 2 * pad)
  t.eb:SetJustifyH("LEFT")
  S.ink(t.eb, S.C.folioGold)
  t.eb:SetText(S.SmallCaps(Cabinet.Eyebrow(e, main)))
  t.eb:Show()
  ribbon(t, e, ctx, pad)
end

-- A sealed letter: paper, the seal in the middle of the upper half, the title and what it is.
local function fillLetter(t, e, w, h)
  t.paper:Show()
  S.tint(t.seal, S.C.folioSeal, 1)
  S.tint(t.lock, S.C.folioSealText, 1)
  t.seal:ClearAllPoints()
  t.seal:SetPoint("CENTER", t, "TOP", 0, -floor(h * 0.36))
  t.seal:Show()
  t.lock:Show()
  setTitle(t, e.title, Cabinet.TITLE, "folioInk", w - 2 * Cabinet.PAD, 1)
  t.ti:SetJustifyH("CENTER")
  t.ti:ClearAllPoints()
  t.ti:SetPoint("TOP", t.seal, "BOTTOM", 0, -8)
  t.eb:ClearAllPoints()
  t.eb:SetPoint("TOP", t.ti, "BOTTOM", 0, -6)
  t.eb:SetWidth(w - 2 * Cabinet.PAD)
  t.eb:SetJustifyH("CENTER")
  S.ink(t.eb, S.C.folioInkSoft)
  t.eb:SetText(S.SmallCaps(L["a secret"] .. "  -  " .. L["sealed until you open it"]))
  t.eb:Show()
end

-- A collection: paper, its name, how much of it the character has, a row of slots.
local function fillCollection(t, coll, w, h)
  t.paper:Show()
  local pad = Cabinet.PAD_MAIN
  local block = Cabinet.TITLE + 8 + 13 + 8 + Cabinet.SLOT
  local top = max(pad, floor((h - block) / 2))
  setTitle(t, Cabinet.CollectionName(coll.kind), Cabinet.TITLE, "folioInk", w - 2 * pad, 1)
  t.ti:SetJustifyH("LEFT")
  t.ti:ClearAllPoints()
  t.ti:SetPoint("TOPLEFT", t, "TOPLEFT", pad, -top)
  t.ct:ClearAllPoints()
  t.ct:SetPoint("TOPLEFT", t.ti, "BOTTOMLEFT", 0, -8)
  t.ct:SetText(string.format(L["%d of %d"], coll.have, coll.total))
  t.ct:Show()
  -- as many slots as fit on one row, the owned ones first in the book's gold, then "+ N"
  local step = Cabinet.SLOT + Cabinet.SLOT_GAP
  local room = w - 2 * pad
  local fit = max(0, floor((room + Cabinet.SLOT_GAP) / step))
  local shown = min(coll.total, fit)
  if shown < coll.total then
    shown = max(0, min(coll.total, floor((room - 44 + Cabinet.SLOT_GAP) / step))) -- room for "+ N"
  end
  for i = 1, shown do
    local slot = t.slots[i]
    if not slot then
      slot = CreateFrame("Frame", nil, t.cap)
      slot:SetSize(Cabinet.SLOT, Cabinet.SLOT)
      slot.fill = S.roundFill(slot, S.C.folioGold, "pill")
      slot.edge = S.roundEdges(slot, S.C.folioPaperEdge, "pill")
      t.slots[i] = slot
    end
    local on = i <= coll.have
    S.tint(slot.fill, S.C.folioGold, on and 1 or 0)
    S.setEdges(slot.edge, on and S.C.folioFitEdge or S.C.folioPaperEdge, 1)
    slot:ClearAllPoints()
    slot:SetPoint("TOPLEFT", t.ct, "BOTTOMLEFT", (i - 1) * step, -8)
    slot:Show()
  end
  if shown < coll.total then
    t.more:ClearAllPoints()
    t.more:SetPoint("LEFT", t.ct, "BOTTOMLEFT", shown * step, -8 - Cabinet.SLOT / 2)
    t.more:SetText("+ " .. (coll.total - shown))
    t.more:Show()
  end
  t.shownSlots = shown
  t.tip = L["Opens the collection on its shelf."]
  t.onClick = function()
    local f = Front.Filter("collections")
    f.facets.kind = { [coll.kind] = true }
    Front.Show({ kind = "shelf", id = "collections" })
  end
end

-- A camp item: its icon on a mat, its name, the profession and the skill it needs.
local function fillCamp(t, e, w, h)
  t.paper:Show()
  local matH = max(20, h - Cabinet.CAMP_BODY)
  t.mat:ClearAllPoints()
  t.mat:SetPoint("TOPLEFT", t, "TOPLEFT", 0, 0)
  t.mat:SetPoint("TOPRIGHT", t, "TOPRIGHT", 0, 0)
  t.mat:SetHeight(matH)
  S.tint(t.mat, S.C.folioMat, 1)
  S.gradient(t.mat, S.C.folioMatFoot, S.C.folioMat)
  t.mat:Show()
  -- Bastian's drawing of it over the mat (R4.9: the 36 camp items that place an object are
  -- drawn); until its drawing is in, its item's icon; without one the chapter's glyph in the
  -- paper's colour
  local drawn = e.art and not e.sim and Picture.ArtOf(e.id) or nil
  if drawn then
    t.icon:ClearAllPoints()
    t.icon:SetAllPoints(t.mat)
    t.icon:SetTexture(drawn)
    drawn = t.icon:GetTexture() and drawn or nil -- a file the client does not have: the icon
  end
  if drawn then
    S.untint(t.icon)
    t.icon:SetTexCoord(Picture.Cover(w, matH))
    t.drew = "art"
  else
    local item = e.gives and e.gives[1]
    local icon = item and B.Compat.ItemIcon(item) or nil
    local size = min(Cabinet.ICON, matH - 12)
    t.icon:ClearAllPoints()
    t.icon:SetSize(size, size)
    t.icon:SetPoint("CENTER", t.mat, "CENTER", 0, 0)
    t.icon:SetTexCoord(0, 1, 0, 1)
    if icon then
      t.icon:SetTexture(icon)
      S.untint(t.icon)
    else
      t.icon:SetTexture(B.UI.IconTexture(Picture.GlyphOf(e)))
      S.tint(t.icon, S.C.folioPaper, 0.85)
    end
    t.drew = icon and "icon" or "plate"
  end
  t.icon:Show()
  t.eb:ClearAllPoints()
  t.eb:SetPoint("TOPLEFT", t.mat, "BOTTOMLEFT", Cabinet.PAD, -8)
  t.eb:SetWidth(w - 2 * Cabinet.PAD)
  t.eb:SetJustifyH("LEFT")
  S.ink(t.eb, S.C.folioInkSoft)
  t.eb:SetText(S.SmallCaps(Cabinet.CampLine(e)))
  t.eb:Show()
  setTitle(t, e.title, Cabinet.TITLE, "folioInk", w - 2 * Cabinet.PAD, 1)
  t.ti:SetJustifyH("LEFT")
  t.ti:ClearAllPoints()
  t.ti:SetPoint("TOPLEFT", t.eb, "BOTTOMLEFT", 0, -4)
end

-- Fills a tile for `e` in the cell `rect` -> the kind it drew.
function Cabinet.Fill(t, e, rect, front, ctx)
  hideAll(t)
  t.entry = e
  t:SetSize(rect.w, rect.h)
  local kind = Cabinet.KindOf(e, front, rect.slot)
  t.kind = kind
  if kind == "collection" then
    fillCollection(t, front.collection, rect.w, rect.h)
  elseif kind == "letter" then
    fillLetter(t, e, rect.w, rect.h)
  elseif kind == "camp" then
    fillCamp(t, e, rect.w, rect.h)
  else
    fillPicture(t, e, rect.w, rect.h, rect.role, ctx)
  end
  t:Show()
  return kind
end

-- ---------------------------------------------------------------------------------------------
-- The list's kinds: the cabinet, Bastian's note, the entrances
-- ---------------------------------------------------------------------------------------------

local KINDS = Front.KINDS

KINDS.cabinet = {
  make = function(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.tiles = {}
    return f
  end,
  fill = function(f, item, width)
    local lay = Cabinet.Layout(width)
    if not f.vlKind then
      return lay.height
    end
    local front, ctx = item.front, item.ctx
    local six = Cabinet.Slots(front)
    f.layout = lay
    local used = {}
    for _, rect in ipairs(lay.rects) do
      local e = rect.slot == 0 and front.main or six[rect.slot]
      -- the tiles as a list (the slot's number and one), so the list's helpers walk them
      local t = f.tiles[rect.slot + 1]
      if e then
        if not t then
          for i = #f.tiles + 1, rect.slot + 1 do
            f.tiles[i] = newTile(f)
            f.tiles[i]:Hide()
          end
          t = f.tiles[rect.slot + 1]
        end
        t:Rest("TOPLEFT", f, "TOPLEFT", rect.x, -rect.y)
        Cabinet.Fill(t, e, rect, front, ctx)
        used[rect.slot + 1] = true
      end
    end
    for slot, t in ipairs(f.tiles) do
      if not used[slot] then
        hideAll(t)
        t:Hide()
      end
    end
    return lay.height
  end,
}

-- Bastian's note: a band with his portrait in a gold ring and his line; at its right end a
-- wonder at random as a quiet word.
KINDS.bnote = {
  make = function(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.band = S.roundFill(f, S.C.panel, Cabinet.RADIUS)
    local size = Cabinet.PORTRAIT + 2 * Cabinet.RING
    f.ring = f:CreateTexture(nil, "BORDER")
    f.ring:SetTexture(S.DISC)
    f.ring:SetSize(size, size)
    f.ring:SetPoint("LEFT", f, "LEFT", Cabinet.SIDE, 0)
    f.disc = f:CreateTexture(nil, "ARTWORK")
    f.disc:SetTexture(S.DISC)
    f.disc:SetSize(Cabinet.PORTRAIT, Cabinet.PORTRAIT)
    f.disc:SetPoint("CENTER", f.ring, "CENTER", 0, 0)
    f.crest = f:CreateTexture(nil, "OVERLAY")
    f.crest:SetTexture(S.CREST)
    f.crest:SetSize(26, 26)
    f.crest:SetPoint("CENTER", f.ring, "CENTER", 0, 0)
    f.text = Front.BookText(f, 13, S.C.text, "bookItalic", true)
    f.text:SetJustifyV("MIDDLE")
    f.text:SetJustifyH("LEFT")
    f.act = CreateFrame("Button", nil, f)
    f.act.text = Front.BookText(f.act, 13, S.C.accent, "bookSans")
    f.act.text:SetPoint("CENTER")
    f.act:SetScript("OnEnter", function(self)
      S.ink(self.text, S.Tok(self, "text"))
      S.TipEnter(self)
    end)
    f.act:SetScript("OnLeave", function(self)
      S.ink(self.text, S.Tok(self, "accent"))
      S.TipLeave(self)
    end)
    return f
  end,
  fill = function(f, item, width)
    if not f.vlKind then
      return Cabinet.NOTE_H
    end
    S.tint(f.band, S.Tok(f, "panel"), 1)
    S.tint(f.ring, S.Tok(f, "accent"), 1)
    S.tint(f.disc, S.Tok(f, "panel"), 1)
    S.tint(f.crest, S.Tok(f, "accent"), 1)
    S.ink(f.text, S.Tok(f, "text"))
    local right = Cabinet.SIDE
    f.act:SetShown(item.act ~= nil)
    if item.act then
      f.act.text:SetText(item.act.label or "")
      S.ink(f.act.text, S.Tok(f, "accent"))
      f.act.tip = item.act.tip
      local w = f.act.text:GetStringWidth()
      f.act:SetSize(((w and w > 0) and w or (#(item.act.label or "") * 7)) + 4, 20)
      f.act:ClearAllPoints()
      f.act:SetPoint("RIGHT", f, "RIGHT", -Cabinet.SIDE, 0)
      f.act:SetScript("OnClick", item.act.onClick)
      right = right + f.act:GetWidth() + 12
    end
    f.text:ClearAllPoints()
    f.text:SetPoint("LEFT", f.ring, "RIGHT", 12, 0)
    f.text:SetSize(
      max(40, width - Cabinet.SIDE - Cabinet.PORTRAIT - 2 * Cabinet.RING - 12 - right),
      Cabinet.NOTE_H - 8
    )
    f.text:SetText(item.text or "")
    return Cabinet.NOTE_H
  end,
}

-- One entrance per chapter: a paper card with the chapter's name, its sentence and how much of
-- it is open and near; a click opens its shelf.
local function newEntrance(parent)
  local t = CreateFrame("Button", nil, parent)
  t.paper = S.roundFill(t, S.C.folioPaper, Cabinet.RADIUS)
  t.ti = text(t, Cabinet.TITLE, "folioInk", "bookDisplay")
  t.ti:SetPoint("TOPLEFT", t, "TOPLEFT", Cabinet.PAD, -10)
  t.line = text(t, 13, "folioInk", "bookItalic", true)
  t.line:SetJustifyV("TOP")
  t.line:SetJustifyH("LEFT")
  t.line:SetPoint("TOPLEFT", t.ti, "BOTTOMLEFT", 0, -4)
  t.kd = text(t, 11, "folioInkSoft", "bookCaps")
  t.kd:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", Cabinet.PAD, 10)
  t:SetScript("OnClick", function(self)
    if self.chapter then
      Front.Show({ kind = "shelf", id = self.chapter })
    end
  end)
  S.object(t, { radius = Cabinet.RADIUS })
  return t
end

KINDS.entrances = {
  make = function(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.cards = {}
    return f
  end,
  fill = function(f, item, width)
    local lay = Cabinet.Entrances(width, #Shelf.CHAPTERS)
    if not f.vlKind then
      return lay.height
    end
    f.layout = lay
    for i, chapter in ipairs(Shelf.CHAPTERS) do
      local t = f.cards[i]
      if not t then
        t = newEntrance(f)
        f.cards[i] = t
      end
      local rect = lay.rects[i]
      t.chapter = chapter
      t:SetSize(rect.w, rect.h)
      t:Rest("TOPLEFT", f, "TOPLEFT", rect.x, -rect.y)
      t.ti:SetText(Front.ChapterName(chapter))
      t.line:SetSize(rect.w - 2 * Cabinet.PAD, Cabinet.HOOK_H + (lay.lines - 2) * Cabinet.ENTRANCE_LINE)
      t.line:SetText(Front.ChapterLine(chapter) or "")
      t.kd:SetText(S.SmallCaps(Cabinet.Count(item.front.chapters[chapter] or {})))
      t:Show()
    end
    return lay.height
  end,
}
