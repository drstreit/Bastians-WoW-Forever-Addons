-- Bastian's Book: a shelf as a list (book.md "The views", E4, R4.10; book-look.md 10.4): a head
-- row with the columns' names, which sort, and a row per wonder: its picture small, its name
-- with Bastian's line, how to get it (the first source, its name a link) and whether the reader
-- has it. Core's virtual list draws the rows, so 2,000 wonders cost a screenful of them.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Front, Shelf, Picture, Sources, Record = ns.Front, ns.Shelf, ns.Picture, ns.Sources, ns.Record

local List = {}
ns.List = List

local floor, max = math.floor, math.max

List.ROW = 36 -- a row: the name 13 and Bastian's line 11
List.HEAD = 24 -- the head row
List.SIDE = 15 -- the table's padding: the spec counts from the window's edge, a row lies inside
List.PIC = 28 -- the picture, a square with corners of 4
List.GAP = 11 -- after the picture and between two columns
List.NAME_MIN = 320 -- the name's column ends at 40 % of the window, never before 320
List.NAME_SHARE = 0.4
List.HOW_MIN = 120 -- how to get it keeps this much in a narrow window
List.HAVE = 170 -- the last column
List.GLYPH = 14 -- the source's pictogram
List.STAMP = 16 -- the stamp's disc
List.SWITCH = 20 -- a pictogram of the view's switch
List.ARROW = 8 -- the sorted column's arrow
-- a column that sorts -> the shelf's sort (Shelf.Sort)
List.SORTS = { name = "az", how = "how", have = "have" }
List.COLUMNS = { "name", "how", "have" }
-- the views' pictograms (Core's glyphs: a box of four, a written sheet)
List.VIEW_GLYPH = { tiles = "buttons", list = "note" }

-- ---------------------------------------------------------------------------------------------
-- Pure: the columns' places, a source in words
-- ---------------------------------------------------------------------------------------------

-- The columns of a row `width` wide (the table's width inside its padding) -> { name, how, have }
-- each { x, w } from the row's left edge. The picture stands at 0.
function List.Columns(width)
  local window = width + 2 * List.SIDE
  local nameX = List.PIC + List.GAP
  local howX = max(List.NAME_MIN, floor(window * List.NAME_SHARE)) - List.SIDE
  local haveX = max(howX + List.HOW_MIN, width - List.HAVE)
  return {
    name = { x = nameX, w = max(40, howX - nameX - List.GAP) },
    how = { x = howX, w = max(40, haveX - howX - List.GAP) },
    have = { x = haveX, w = max(0, width - haveX) },
  }
end

-- The pack's ways to get something that the shelf's filter has a word for ("a drop").
local SOURCE_WORD = { drop = "drop", vendor = "vendor", quest = "quest", craft = "crafted", make = "crafted" }
SOURCE_WORD.object = "object"

-- The first of a wonder's sources in words (`rows` of Sources.Of) -> { glyph, word, name, ref,
-- rest, more }: "a drop:" then the name (a link), then ", Silverpine Forest, level 12, 1 in 50";
-- `more` further sources. The level that holds `level` is written in gold. nil without a source.
function List.How(rows, level, words)
  local r = rows and rows[1]
  if not r then
    return nil
  end
  local parts = {}
  if r.zoneName then
    parts[#parts + 1] = r.zoneName
  end
  local lv = Sources.Where({ levelMin = r.levelMin, levelMax = r.levelMax })
  if lv ~= "" then
    local fits = Shelf.Fits({ levelMin = r.levelMin, levelMax = r.levelMax }, level)
    local gold = fits and S.H.folioGold or nil
    parts[#parts + 1] = gold and (gold .. lv .. "|r") or lv
  end
  local value = r.odds -- unknown odds say nothing (golden rule 2)
  if r.price then
    value = B.UI.Money(r.price) .. (r.stack and r.stack > 1 and (" x" .. r.stack) or "")
  end
  if value then
    parts[#parts + 1] = value
  end
  local word = words and SOURCE_WORD[r.how] and words[SOURCE_WORD[r.how]] or nil
  return {
    glyph = r.glyph,
    word = word,
    name = r.name,
    ref = r.ref,
    rest = #parts > 0 and (", " .. table.concat(parts, ", ")) or "",
    more = #rows - 1,
  }
end

-- Whether the reader has it -> { at } (this character's mark), { by } (the first other
-- character's name and how many more), or nil. A gold page is read, not owned: nothing.
function List.Have(e)
  if e.page then
    return nil
  end
  local mine = Record.Entry(e.id)
  if mine then
    return { at = mine.at }
  end
  local alts = Record.Alts(e.id)
  if alts[1] then
    return { by = alts[1], others = #alts - 1 }
  end
  return nil
end

-- ---------------------------------------------------------------------------------------------
-- The frames: a link on the dark table, the head row, a row
-- ---------------------------------------------------------------------------------------------

local function width(fs, text)
  local w = fs:GetStringWidth()
  return (w and w > 0) and w or (#(text or "") * 6)
end

-- A source's name: the table's ink with a line under it, gold under the mouse. A left click
-- opens the thing's page, a right click its menu (as a link on the wonder's page does).
local function newLink(parent)
  local b = CreateFrame("Button", nil, parent)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b.text = Front.BookText(b, 13, S.C.folioText, "bookSans")
  b.text:SetPoint("LEFT", b, "LEFT", 0, 0)
  b.text:SetWordWrap(false)
  b.line = S.fill(b, S.C.folioRule, "ARTWORK")
  b.line:ClearAllPoints()
  b.line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
  b.line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  b.line:SetHeight(1)
  b:SetScript("OnEnter", function(self)
    S.ink(self.text, S.C.folioGold)
    if self.ref and GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
      S.EntityTip(GameTooltip, self.ref)
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function(self)
    S.ink(self.text, S.C.folioText)
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  b:SetScript("OnClick", function(self, button)
    if not self.ref then
      return
    end
    if button == "RightButton" then
      B.UI.EntityMenu(self.ref, nil, { source = "strategies" })
    else
      ns.Window.OpenRef(self.ref)
    end
  end)
  return b
end

local HEADS -- the columns' names, made at the first head row (the locale is there by then)
local function heads()
  HEADS = HEADS or { name = L["Name"], how = L["How to get it"], have = L["Done"] }
  return HEADS
end

local KINDS = Front.KINDS

-- The head row: the columns' names in small capitals; a click sorts by the column, the sorted
-- one stands in gold with a small arrow.
KINDS.listhead = {
  make = function(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.bg = S.fill(f, S.C.folioBand, "BACKGROUND")
    f.rule = S.fill(f, S.C.folioRule, "BORDER")
    f.rule:ClearAllPoints()
    f.rule:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    f.rule:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    f.rule:SetHeight(1)
    f.cols = {}
    for _, id in ipairs(List.COLUMNS) do
      local b = CreateFrame("Button", nil, f)
      b:SetHeight(List.HEAD)
      b.text = Front.BookText(b, 11, S.C.folioMuted, "bookCaps")
      b.text:SetPoint("LEFT", b, "LEFT", 0, 0)
      b.arrow = b:CreateTexture(nil, "ARTWORK")
      b.arrow:SetSize(List.ARROW, List.ARROW)
      b.arrow:SetPoint("LEFT", b.text, "RIGHT", 4, 0)
      b.arrow:SetTexture(B.UI.Pictogram("arrow"))
      b.arrow:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0) -- the pictogram points right: turned to point down
      f.cols[id] = b
    end
    return f
  end,
  fill = function(f, item, w)
    if not f.vlKind then
      return List.HEAD
    end
    local cols = List.Columns(w)
    for _, id in ipairs(List.COLUMNS) do
      local b, c = f.cols[id], cols[id]
      local sorted = item.sort == List.SORTS[id]
      local text = S.SmallCaps(heads()[id])
      b.text:SetText(text)
      S.ink(b.text, sorted and S.C.folioGold or S.C.folioMuted)
      S.tint(b.arrow, S.C.folioGold, 1)
      b.arrow:SetShown(sorted)
      b.sorted = sorted
      b:SetWidth(math.min(c.w, width(b.text, text) + 4 + List.ARROW))
      b:ClearAllPoints()
      b:SetPoint("LEFT", f, "LEFT", c.x, 0)
      b:SetShown(c.w > 0)
      b:SetScript("OnClick", function()
        if item.onSort then
          item.onSort(List.SORTS[id])
        end
      end)
    end
    return List.HEAD
  end,
}

local function newRow(parent)
  local f = CreateFrame("Button", nil, parent)
  f.hover = S.fill(f, S.C.folioBand, "BACKGROUND")
  f.hover:Hide()
  f.rule = S.fill(f, S.C.folioRule, "BORDER")
  f.rule:ClearAllPoints()
  f.rule:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
  f.rule:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  f.rule:SetHeight(1)
  f.rule:SetAlpha(0.5)
  f.pic = Picture.New(f)
  f.pic:SetPoint("LEFT", f, "LEFT", 0, 0)
  f.pic:EnableMouse(false)
  f.name = Front.BookText(f, 13, S.C.folioText, "bookSans")
  f.name:SetJustifyH("LEFT")
  f.name:SetWordWrap(false)
  f.line = Front.BookText(f, 11, S.C.folioMuted, "bookItalic")
  f.line:SetJustifyH("LEFT")
  f.line:SetWordWrap(false)
  f.glyph = f:CreateTexture(nil, "ARTWORK")
  f.glyph:SetSize(List.GLYPH, List.GLYPH)
  f.word = Front.BookText(f, 13, S.C.folioMuted, "bookSans")
  f.link = newLink(f)
  f.rest = Front.BookText(f, 13, S.C.folioText, "bookSans")
  f.rest:SetJustifyH("LEFT")
  f.rest:SetWordWrap(false)
  f.stamp = f:CreateTexture(nil, "ARTWORK")
  f.stamp:SetTexture(Picture.DISC)
  f.stamp:SetSize(List.STAMP, List.STAMP)
  f.have = Front.BookText(f, 11, S.C.folioText, "bookSans")
  f.have:SetJustifyH("LEFT")
  f.have:SetWordWrap(false)
  f:SetScript("OnEnter", function(self)
    self.hover:Show()
  end)
  f:SetScript("OnLeave", function(self)
    self.hover:Hide()
  end)
  f:SetScript("OnClick", function(self)
    if self.entry then
      Front.OpenEntry(self.entry)
    end
  end)
  return f
end

-- Fills the row for `e` -> what its picture drew.
local function fillRow(f, e, w, ctx)
  local cols = List.Columns(w)
  f.entry = e
  f.drew = Picture.Draw(f.pic, e, List.PIC, List.PIC)
  -- the name and Bastian's line under it
  S.ink(f.name, S.C.folioText)
  f.name:ClearAllPoints()
  f.name:SetPoint("TOPLEFT", f, "TOPLEFT", cols.name.x, -4)
  f.name:SetWidth(cols.name.w)
  f.name:SetText(e.title or "")
  local line = e.hook or e.tale or ""
  f.line:ClearAllPoints()
  f.line:SetPoint("TOPLEFT", f, "TOPLEFT", cols.name.x, -20)
  f.line:SetWidth(cols.name.w)
  f.line:SetText(line)
  f.line:SetShown(line ~= "")
  -- how to get it: the first source
  local how = List.How(Sources.Of(e), ctx and ctx.level, Front.SourceWords())
  f.how = how
  local shown = how ~= nil and cols.how.w > 0
  f.glyph:SetShown(shown)
  f.word:SetShown(shown and how.word ~= nil)
  f.link:SetShown(shown)
  f.rest:SetShown(shown)
  if shown then
    local x = cols.how.x
    f.glyph:SetTexture(B.UI.Pictogram(how.glyph) or B.UI.Pictogram("other"))
    S.tint(f.glyph, S.C.folioMuted, 1)
    f.glyph:ClearAllPoints()
    f.glyph:SetPoint("LEFT", f, "LEFT", x, 0)
    x = x + List.GLYPH + 6
    if how.word then
      local text = how.word .. ":"
      f.word:SetText(text)
      f.word:ClearAllPoints()
      f.word:SetPoint("LEFT", f, "LEFT", x, 0)
      x = x + width(f.word, text) + 5
    end
    local room = max(30, cols.how.x + cols.how.w - x)
    f.link.ref = how.ref
    f.link.text:SetText(how.name or "")
    local lw = math.min(room, width(f.link.text, how.name))
    f.link.text:SetWidth(lw)
    f.link:SetSize(lw, 17)
    f.link:ClearAllPoints()
    f.link:SetPoint("LEFT", f, "LEFT", x, 0)
    x = x + lw
    local rest = how.rest
    if how.more > 0 then
      rest = rest .. "  " .. S.H.folioMuted .. string.format(L["%d more"], how.more) .. "|r"
    end
    f.rest:SetText(rest)
    f.rest:ClearAllPoints()
    f.rest:SetPoint("LEFT", f, "LEFT", x, 0)
    f.rest:SetWidth(max(1, cols.how.x + cols.how.w - x))
    f.rest:SetShown(rest ~= "" and cols.how.x + cols.how.w - x > 20)
  end
  -- have it: the stamp and its date, or the character that has it
  local have = cols.have.w > 0 and List.Have(e) or nil
  f.has = have
  f.stamp:SetShown(have ~= nil and have.at ~= nil)
  f.have:SetShown(have ~= nil)
  if have then
    local x = cols.have.x
    if have.at then
      S.tint(f.stamp, S.C.folioGold, 1)
      f.stamp:ClearAllPoints()
      f.stamp:SetPoint("LEFT", f, "LEFT", x, 0)
      x = x + List.STAMP + 6
      S.ink(f.have, S.C.folioText)
      f.have:SetText(date and date("%d.%m.%Y", have.at) or "")
    else
      S.ink(f.have, S.C.folioMuted)
      local by = string.format(L["Done by %s"], have.by)
      f.have:SetText(have.others > 0 and (by .. " +" .. have.others) or by)
    end
    f.have:ClearAllPoints()
    f.have:SetPoint("LEFT", f, "LEFT", x, 0)
    f.have:SetWidth(max(1, cols.have.x + cols.have.w - x))
  end
  f:Show()
  return f.drew
end

KINDS.row = {
  make = function(parent)
    return newRow(parent)
  end,
  fill = function(f, item, w)
    if not f.vlKind then
      return List.ROW
    end
    fillRow(f, item.entry, w, item.ctx)
    return List.ROW
  end,
}

-- ---------------------------------------------------------------------------------------------
-- The switch on the filter band: two pictograms, the chosen one in gold
-- ---------------------------------------------------------------------------------------------

-- -> a frame with `Set(view, onPick)` and the two buttons `tiles` and `list`; its width is two
-- pictograms and a gap of 6.
function List.NewSwitch(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(2 * List.SWITCH + 6, List.SWITCH)
  for i, id in ipairs({ "tiles", "list" }) do
    local b = CreateFrame("Button", nil, f)
    b:SetSize(List.SWITCH, List.SWITCH)
    b:SetPoint("LEFT", f, "LEFT", (i - 1) * (List.SWITCH + 6), 0)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    b.icon:SetTexture(B.UI.Pictogram(List.VIEW_GLYPH[id]))
    b.tip = id == "tiles" and L["As tiles"] or L["As a list"]
    b:SetScript("OnEnter", S.TipEnter)
    b:SetScript("OnLeave", S.TipLeave)
    f[id] = b
  end
  function f.Set(self, view, onPick)
    self.view = view
    for _, id in ipairs({ "tiles", "list" }) do
      local b = self[id]
      S.tint(b.icon, id == view and S.C.folioGold or S.C.folioMuted, 1)
      b:SetScript("OnClick", function()
        if onPick and self.view ~= id then
          onPick(id)
        end
      end)
    end
  end
  return f
end
