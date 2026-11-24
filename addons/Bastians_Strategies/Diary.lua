-- Bastian's Book: Your diary (book.md "Your record becomes the diary", R4.11; book-look.md 10.9):
-- a spread of two paper pages. Left: the journal, a day per date and a line per find, newest
-- first; what is kept for later; what the other characters did. Right: the progress of every
-- collection and zone as a row of slots; the album, every companion and mount as its model, the
-- ones the reader lacks as dark shapes.
local _, ns = ...
local B = Bastians
local S = B.UI.Style
local L = ns.L
local Record, Shelf, Picture = ns.Record, ns.Shelf, ns.Picture
local P = ns.Wonder.Paper -- the paper's kit: the page as paper, its rules and links

local Diary = {}
ns.Diary = Diary

local floor, max, min = math.floor, math.max, math.min

Diary.BLOCK_GAP = 14 -- between two blocks of a page
Diary.LABEL_GAP = 6 -- under a block's label
Diary.DAY_GAP = 5 -- under a day's date and between its lines
Diary.LINE = 18 -- a line: the italic at 13
Diary.DISC, Diary.DISC_GAP = 16, 8 -- the stamp's disc before a line
Diary.SPACE = 4 -- a blank between two parts of a line
Diary.NAME_W, Diary.COUNT_W = 120, 70 -- a progress row: the name, "3 of 18"
Diary.COL_GAP, Diary.ROW_GAP = 10, 9
Diary.SLOT, Diary.SLOT_GAP = 22, 4
Diary.MORE_W = 44 -- the room "+ 17" takes at a row's end
Diary.ALBUM_COLS, Diary.ALBUM_GAP = 6, 8
Diary.ALBUM_EDGE, Diary.ALBUM_BORDER = 1, 3 -- a frame: a line, then the border in the paper's light
Diary.ALBUM_MODEL, Diary.ALBUM_FOOT = 0.74, 0.08 -- the model's width and its foot, of the frame
Diary.ALBUM_ROWS = 3 -- an album's rows before "N more"
Diary.ALBUMS = { "pet", "mount" } -- the collections with a model each
Diary.DAYS = 30 -- the journal's days before "N earlier days"
Diary.ALTS = 12 -- the other characters' lines before "N more"
Diary.MONTHS = {
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
}

local NOTHING_YET = "Nothing done yet on this character. Mark a wonder done, or the book finds it"
  .. " in your quest history, bags and titles."

-- what the reader opened on the page (this session): every day, every frame of an album
local opened = {}

-- ---------------------------------------------------------------------------------------------
-- Pure: a day's title, a find's line, the slots of a row
-- ---------------------------------------------------------------------------------------------

-- "17 November": the day without a leading zero and the month's name, in the locale's order.
function Diary.DayTitle(at)
  local day = tostring(tonumber(date("%d", at)) or 0)
  local month = L[Diary.MONTHS[tonumber(date("%m", at)) or 1]]
  local text = string.gsub(L["{day} {month}"], "{day}", function()
    return day
  end)
  return (string.gsub(text, "{month}", function()
    return month
  end))
end

-- A find's line as its parts, in Bastian's hand: "The Black Tabby, Silverpine Forest. Level 24."
-- mark = { id, how, name, zone, level } (Record.Journal), `entry` the wonder on the shelf (nil
-- when it left the pack: its saved name then, else its id), zoneName(uiMapID) -> name or nil.
-- The zone is where the mark was made, else the wonder's own first zone; the level only what
-- the mark kept. -> { { text } | { link, ref } | { link, wonder, page } }
function Diary.Line(mark, entry, zoneName)
  local name = (entry and entry.title) or mark.name or mark.id
  local zone = mark.zone or (entry and entry.zones and entry.zones[1]) or nil
  local zname = zone and zoneName and zoneName(zone) or nil
  local template = zname and L["{name}, {zone}."] or L["{name}."]
  local parts, pos = {}, 1
  while true do
    local a, b, key = string.find(template, "{(%a+)}", pos)
    if not a then
      break
    end
    if a > pos then
      parts[#parts + 1] = { text = string.sub(template, pos, a - 1) }
    end
    if key == "name" then
      parts[#parts + 1] = entry and { link = name, wonder = entry.id, page = entry.page } or { text = name }
    elseif key == "zone" then
      parts[#parts + 1] = { link = zname, ref = "zone:" .. zone }
    end
    pos = b + 1
  end
  local tail = string.sub(template, pos)
  if mark.level then
    tail = tail .. " " .. string.format(L["Level %d."], mark.level)
  end
  if mark.how ~= "found" then
    tail = tail .. " " .. L["Marked by hand."]
  end
  if tail ~= "" then
    parts[#parts + 1] = { text = tail }
  end
  return parts
end

-- The slots of a row with `room` for them -> how many are drawn, and how many stand behind
-- "+ N" (discs of 22, 4 apart; when not all fit, the row keeps room for the count).
function Diary.Slots(room, total)
  local step = Diary.SLOT + Diary.SLOT_GAP
  local fit = max(0, floor((room + Diary.SLOT_GAP) / step))
  if total <= fit then
    return total, 0
  end
  local shown = max(0, min(total, floor((room - Diary.MORE_W + Diary.SLOT_GAP) / step)))
  return shown, total - shown
end

-- A model as a dark shape (book-look.md 10.6; verified 17.11.2026, build 1.60.1.70938): lit
-- black, the retail family's table form of SetLight -> false where the client cannot.
local NO_LIGHT = 0 -- a light's strength and colour, not a colour of the look
function Diary.Darken(model)
  local vector, colour = rawget(_G, "CreateVector3D"), rawget(_G, "CreateColor")
  if not (model and vector and colour and type(model.SetLight) == "function") then
    return false
  end
  model:SetLight(true, {
    omnidirectional = false,
    point = vector(NO_LIGHT, NO_LIGHT, NO_LIGHT),
    ambientIntensity = NO_LIGHT,
    ambientColor = colour(NO_LIGHT, NO_LIGHT, NO_LIGHT),
    diffuseIntensity = NO_LIGHT,
    diffuseColor = colour(NO_LIGHT, NO_LIGHT, NO_LIGHT),
  })
  return true
end

-- ---------------------------------------------------------------------------------------------
-- The page's own parts: words, discs, slots and the album's frames, pooled per page
-- ---------------------------------------------------------------------------------------------

local function pools(page)
  local d = page.diary
  if not d then
    d = { words = {}, discs = {}, slots = {}, frames = {} }
    page.diary = d
  end
  d.nwords, d.ndiscs, d.nslots, d.nframes = 0, 0, 0, 0
  return d
end

local function clearFrame(f)
  for _, key in ipairs({ "lit", "dark" }) do
    if f[key] then
      f[key]:Hide()
    end
  end
  f:Hide()
end

local function finish(page)
  local d = page.diary
  for i = d.nwords + 1, #d.words do
    d.words[i]:Hide()
  end
  for i = d.ndiscs + 1, #d.discs do
    d.discs[i]:Hide()
  end
  for i = d.nslots + 1, #d.slots do
    d.slots[i]:Hide()
  end
  for i = d.nframes + 1, #d.frames do
    clearFrame(d.frames[i])
  end
end

-- The page shows something else again: the diary's parts go, its models stop drawing.
function Diary.Hide(page)
  if page.diary then
    pools(page)
    finish(page)
  end
end

local function widthOf(fs, text)
  local w = fs:GetStringWidth()
  return (w and w > 0) and w or (#(text or "") * 6)
end

-- A word on one line, placed by the caller -> the font string and its width.
local function word(page, text, size, color, role)
  local d = page.diary
  d.nwords = d.nwords + 1
  local fs = d.words[d.nwords]
  if not fs then
    fs = ns.Front.BookText(page.content, size, color, role)
    d.words[d.nwords] = fs
  end
  S.SetRole(fs, role)
  S.setSize(fs, size)
  S.ink(fs, color)
  fs:SetText(text)
  fs:ClearAllPoints()
  fs:Show()
  return fs, widthOf(fs, text)
end

local function at(region, page, x, y)
  region:ClearAllPoints()
  region:SetPoint("TOPLEFT", page.content, "TOPLEFT", x, -y)
end

local function label(K, page, text)
  K.text(page, S.SmallCaps(text), 11, S.C.folioInkSoft, 0, Diary.LABEL_GAP, "bookCaps")
end

local function note(K, page, text)
  K.text(page, text, 13, S.C.folioInkSoft, 0, 0, "bookItalic")
end

-- A rule between two blocks, 14 over and under it.
local function rule(page)
  page.y = page.y + Diary.BLOCK_GAP
  P.rule(page, Diary.BLOCK_GAP)
end

local function openWonder(part)
  return function()
    ns.Window.Show({ kind = part.page and "page" or "wonder", id = part.wonder })
  end
end

-- Lays `parts` (Diary.Line's) as running words from `x0`, on as many lines as they need; a part
-- that does not fit the line starts the next one. A blank at a text's end is a gap of 4, so the
-- client's measure of a trailing blank does not matter. -> the y under the last line.
local function flow(page, parts, x0, y, size, role, color)
  local x = x0
  for _, part in ipairs(parts) do
    if part.link then
      local b = P.link(page)
      local w = P.set(b, part.link, part.ref, size, page.width - x0, role)
      if part.wonder then
        b:SetScript("OnClick", openWonder(part))
      end
      if x > x0 and x + w > page.width then
        x, y = x0, y + Diary.LINE
      end
      at(b, page, x, y)
      x = x + w
    else
      local text = part.text
      local lead = string.find(text, "^%s") and Diary.SPACE or 0
      local trail = string.find(text, "%s$") and Diary.SPACE or 0
      text = strtrim(text)
      if text ~= "" then
        local fs, w = word(page, text, size, color, role)
        if x > x0 and x + lead + w > page.width then
          x, y, lead = x0, y + Diary.LINE, 0
        end
        at(fs, page, x + lead, y + 1)
        x = x + lead + w
      end
      x = x + trail
    end
  end
  return y + Diary.LINE
end

-- ---------------------------------------------------------------------------------------------
-- The left page: the journal, kept for later, the other characters
-- ---------------------------------------------------------------------------------------------

local function zoneName(z)
  local info = z and ns.Front.ZoneOf(z)
  return info and info.name or nil
end

local function disc(page, y)
  local d = page.diary
  d.ndiscs = d.ndiscs + 1
  local tex = d.discs[d.ndiscs]
  if not tex then
    tex = page.content:CreateTexture(nil, "ARTWORK")
    tex:SetTexture(Picture.DISC)
    tex:SetSize(Diary.DISC, Diary.DISC)
    d.discs[d.ndiscs] = tex
  end
  S.tint(tex, S.C.folioGold, 1)
  at(tex, page, 0, y + (Diary.LINE - Diary.DISC) / 2)
  tex:Show()
end

local function journal(K, page)
  label(K, page, L["The journal - newest first"])
  local days = Record.Journal()
  if not days[1] then
    note(K, page, L[NOTHING_YET])
    return
  end
  local shown = opened.days and #days or min(#days, Diary.DAYS)
  local x0 = Diary.DISC + Diary.DISC_GAP
  for i = 1, shown do
    local day = days[i]
    if i > 1 then
      page.y = page.y + Diary.BLOCK_GAP - Diary.DAY_GAP
    end
    K.text(page, Diary.DayTitle(day.at), 18, S.C.folioInk, 0, Diary.DAY_GAP, "bookDisplay")
    for _, mark in ipairs(day.marks) do
      disc(page, page.y)
      local parts = Diary.Line(mark, ns.Front.Find(mark.id), zoneName)
      page.y = flow(page, parts, x0, page.y, 13, "bookItalic", S.C.folioInk) + Diary.DAY_GAP
    end
  end
  page.y = page.y - Diary.DAY_GAP
  if shown < #days then
    local more = P.link(page)
    P.set(more, string.format(L["%d earlier days"], #days - shown), nil, 13)
    more:SetScript("OnClick", function()
      opened.days = true
      ns.Window.Render()
    end)
    at(more, page, 0, page.y + Diary.DAY_GAP)
    page.y = page.y + Diary.DAY_GAP + Diary.LINE
  end
end

-- Kept for later: the bookmarks as links in one running line.
local function kept(K, page)
  label(K, page, L["Kept for later"])
  local marks = ns.mod and ns.mod.db and ns.mod.db.char.bookmarks or {}
  local parts = {}
  for _, id in ipairs(marks) do
    local e = ns.Front.Find(id)
    if e then
      if parts[1] then
        parts[#parts + 1] = { text = " - " }
      end
      parts[#parts + 1] = { link = e.title, wonder = e.id, page = e.page }
    end
  end
  if not parts[1] then
    note(K, page, L["Bookmark a page to keep it here."])
    return
  end
  page.y = flow(page, parts, 0, page.y, 13, "bookSans", S.C.folioInkSoft)
end

-- Your other characters: what one of them did and this one did not, a line each.
local function others(K, page)
  local alts = {}
  for _, a in ipairs(Record.Lists().alts) do
    local e = ns.Front.Find(a.id)
    if e then
      alts[#alts + 1] = { entry = e, names = a.names }
    end
  end
  if not alts[1] then
    return
  end
  rule(page)
  label(K, page, L["Your other characters"])
  local shown = opened.alts and #alts or min(#alts, Diary.ALTS)
  for i = 1, shown do
    local a = alts[i]
    local parts = {
      { link = a.entry.title, wonder = a.entry.id, page = a.entry.page },
      { text = " - " .. string.format(L["Done by %s"], table.concat(a.names, ", ")) },
    }
    page.y = flow(page, parts, 0, page.y, 13, "bookSans", S.C.folioInkSoft)
  end
  if shown < #alts then
    local more = P.link(page)
    P.set(more, string.format(L["%d more"], #alts - shown), nil, 13)
    more:SetScript("OnClick", function()
      opened.alts = true
      ns.Window.Render()
    end)
    at(more, page, 0, page.y)
    page.y = page.y + Diary.LINE
  end
end

-- ---------------------------------------------------------------------------------------------
-- The right page: progress, the album
-- ---------------------------------------------------------------------------------------------

local function slot(page, x, y, on)
  local d = page.diary
  d.nslots = d.nslots + 1
  local f = d.slots[d.nslots]
  if not f then
    f = CreateFrame("Frame", nil, page.content)
    f:SetSize(Diary.SLOT, Diary.SLOT)
    f.fill = S.roundFill(f, S.C.folioGold, "pill")
    f.edge = S.roundEdges(f, S.C.folioPaperEdge, "pill")
    d.slots[d.nslots] = f
  end
  f.on = on
  S.tint(f.fill, S.C.folioGold, on and 1 or 0)
  S.setEdges(f.edge, on and S.C.folioFitEdge or S.C.folioPaperEdge, 1)
  at(f, page, x, y)
  f:Show()
end

-- A row: the name (a link: a collection opens its shelf, a zone its page), "3 of 18", the slots
-- with the owned ones first in the book's gold, then "+ N" for the ones that do not fit.
local function progressRow(page, name, ref, onClick, have, total)
  local y = page.y
  local link = P.link(page)
  P.set(link, name, ref, 15, Diary.NAME_W, "bookDisplay")
  if onClick then
    link:SetScript("OnClick", onClick)
  end
  at(link, page, 0, y + 1)
  local count = word(page, string.format(L["%d of %d"], have, total), 13, S.C.folioInkSoft, "bookSans")
  at(count, page, Diary.NAME_W + Diary.COL_GAP, y + 4)
  local x0 = Diary.NAME_W + Diary.COUNT_W + 2 * Diary.COL_GAP
  local shown, more = Diary.Slots(page.width - x0, total)
  local step = Diary.SLOT + Diary.SLOT_GAP
  for i = 1, shown do
    slot(page, x0 + (i - 1) * step, y, i <= have)
  end
  if more > 0 then
    local fs = word(page, "+ " .. more, 11, S.C.folioInkSoft, "bookSans")
    at(fs, page, x0 + shown * step, y + 5)
  end
  page.y = y + Diary.SLOT + Diary.ROW_GAP
end

-- A collection's name: the cabinet's for a kind, the chapter's for a chapter. The library's
-- books are "The library" here, as on the board: the cabinet's name is too long for the column.
function Diary.RowName(row)
  if row.kind == "library book" then
    return L["The library"]
  elseif row.kind then
    return ns.Cabinet.CollectionName(row.kind)
  end
  return ns.Front.ChapterName(row.chapter)
end

local function openShelf(row)
  return function()
    if row.kind then
      ns.Front.Filter(row.chapter).facets.kind = { [row.kind] = true } -- as the cabinet's wide tile
    end
    ns.Window.Show({ kind = "shelf", id = row.chapter })
  end
end

local function progress(K, page, entries, ctx)
  label(K, page, L["Progress"])
  local p = Shelf.Progress(entries, ctx)
  if not p.rows[1] then
    note(K, page, L["The book holds nothing to collect yet."])
    return
  end
  for _, row in ipairs(p.rows) do
    progressRow(page, Diary.RowName(row), nil, openShelf(row), row.have, row.total)
  end
  for _, zone in ipairs(p.zones) do
    progressRow(page, zone.name, "zone:" .. zone.zone, nil, zone.have, zone.total)
  end
  page.y = page.y - Diary.ROW_GAP
end

local function newFrame(parent)
  local f = CreateFrame("Button", nil, parent)
  local function inset(tex, by)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", f, "TOPLEFT", by, -by)
    tex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -by, by)
  end
  f.line = S.fill(f, S.C.folioPaperEdge, "BACKGROUND")
  f.border = S.fill(f, S.C.folioSealText, "BORDER")
  inset(f.border, Diary.ALBUM_EDGE)
  f.mat = S.fill(f, S.C.folioAlbum, "ARTWORK")
  inset(f.mat, Diary.ALBUM_EDGE + Diary.ALBUM_BORDER)
  -- without a model (the client cannot draw it, or cannot darken it): the name on the mat
  f.name = ns.Front.BookText(f, 11, S.C.folioInkSoft, "bookCaps", true)
  f.name:SetPoint("CENTER", f, "CENTER", 0, 0)
  f.name:SetJustifyH("CENTER")
  f:SetScript("OnEnter", S.TipEnter)
  f:SetScript("OnLeave", S.TipLeave)
  f:SetScript("OnClick", function(self)
    if self.entry then
      ns.Window.Show({ kind = "wonder", id = self.entry.id })
    end
  end)
  return f
end

-- The model in a frame: 74 % of it wide, its foot 8 % over the frame's. A frame keeps one model
-- lit and one dark, so a model once lit black never has to be lit again. -> whether it draws.
local function showModel(f, e, side, dark)
  local key, other = dark and "dark" or "lit", dark and "lit" or "dark"
  if f[other] then
    f[other]:Hide()
  end
  local m = f[key]
  if not m then
    m = B.Compat.NewModel(f)
    if not m then
      return false
    end
    m:EnableMouse(false) -- the frame takes the clicks
    f[key] = m
  end
  local size = floor(side * Diary.ALBUM_MODEL)
  -- its place first, then its creature (Picture.lua: a model set on a frame without a size
  -- stays empty)
  m:ClearAllPoints()
  m:SetPoint("BOTTOM", f, "BOTTOM", 0, floor(side * Diary.ALBUM_FOOT))
  m:SetSize(size, size)
  m:Show()
  if m.shownNpc ~= e.npc then
    if not B.Compat.ShowCreature(m, e.npc) then
      m:Hide()
      m.shownNpc = nil
      return false
    end
    m.shownNpc = e.npc
  end
  if m.SetFacing then
    m:SetFacing(Picture.FACING)
  end
  if dark and not Diary.Darken(m) then
    m:Hide() -- never the lit model of something the reader lacks
    return false
  end
  return true
end

local function fillFrame(f, slotOf, side)
  local e = slotOf.entry
  f.entry, f.have = e, slotOf.have
  f:SetSize(side, side)
  S.tint(f.line, S.C.folioPaperEdge, 1)
  S.tint(f.border, S.C.folioSealText, 1)
  S.tint(f.mat, S.C.folioAlbum, 1)
  f.drew = showModel(f, e, side, not slotOf.have)
  f.name:SetShown(not f.drew)
  if not f.drew then
    f.name:SetWidth(side - 2 * (Diary.ALBUM_EDGE + Diary.ALBUM_BORDER) - 6)
    f.name:SetText(S.SmallCaps(e.title or ""))
  end
  f.tip = e.title
  f:Show()
end

-- An album: six frames in a row, the reader's own first; three rows, then "N more" opens it.
local function album(K, page, kind, list)
  label(K, page, string.format(L["The album - %s"], ns.Cabinet.CollectionName(kind)))
  local d = page.diary
  local cols, gap = Diary.ALBUM_COLS, Diary.ALBUM_GAP
  local side = floor((page.width - (cols - 1) * gap) / cols)
  local shown = opened[kind] and #list or min(#list, cols * Diary.ALBUM_ROWS)
  for i = 1, shown do
    d.nframes = d.nframes + 1
    local f = d.frames[d.nframes]
    if not f then
      f = newFrame(page.content)
      d.frames[d.nframes] = f
    end
    local col, row = (i - 1) % cols, floor((i - 1) / cols)
    at(f, page, col * (side + gap), page.y + row * (side + gap))
    fillFrame(f, list[i], side)
  end
  local rows = floor((shown + cols - 1) / cols)
  page.y = page.y + rows * (side + gap) - gap
  if shown < #list then
    local more = P.link(page)
    P.set(more, string.format(L["%d more"], #list - shown), nil, 13)
    more:SetScript("OnClick", function()
      opened[kind] = true
      ns.Window.Render()
    end)
    at(more, page, 0, page.y + Diary.DAY_GAP)
    page.y = page.y + Diary.DAY_GAP + Diary.LINE
  end
end

-- ---------------------------------------------------------------------------------------------
-- The spread
-- ---------------------------------------------------------------------------------------------

-- Renders the diary on the two pages -> its title. K: the window's page kit.
function Diary.Render(K, left, right)
  local entries, ctx = ns.Front.Entries(), ns.Front.Ctx()
  for _, page in ipairs({ left, right }) do
    P.lay(page)
    P.start(page)
    pools(page)
  end
  journal(K, left)
  rule(left)
  kept(K, left)
  others(K, left)
  progress(K, right, entries, ctx)
  for _, kind in ipairs(Diary.ALBUMS) do
    local list = Shelf.Album(entries, kind, ctx)
    if list[1] then
      rule(right)
      album(K, right, kind, list)
    end
  end
  for _, page in ipairs({ left, right }) do
    P.finish(page)
    finish(page)
  end
  return L["Your diary"]
end
