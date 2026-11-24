-- Bastian's Book: one page, one wonder (book.md "The wonder's page", R4.4; book-look.md 10.5): a
-- spread of two paper pages. Left: the plate on its mat, its caption, the tale. Right: the kind,
-- the title, then how to get it (a row per source: a link, where and at which level, the odds or
-- the price, Show on map, Route there), what it gives, the steps in Nixie's envelope, the acts.
local _, ns = ...
local B = Bastians
local S = B.UI.Style
local L = ns.L
local Record, Picture, Sources = ns.Record, ns.Picture, ns.Sources

local Wonder = {}
ns.Wonder = Wonder

local floor, max = math.floor, math.max

Wonder.PLATE = 0.5 -- the plate's height over its width: the drawings' own 2 : 1
Wonder.MAT = 5 -- the mat around the plate
Wonder.TITLE = 27 -- the display size (D3): the page's title
Wonder.TITLE_LINE = 30
Wonder.BLOCK_GAP = 14 -- between two blocks of the right page
Wonder.SOURCE_H = 40 -- a source's row
Wonder.SOURCE_GLYPH = 20
Wonder.ACT_H, Wonder.TOOL_H = 22, 28 -- a source's small acts; the page's acts at its foot

-- A heading in the book's small capitals (ADR 0081; plain capitals where the client keeps its font).
local function caps(text)
  return S.SmallCaps(text)
end

local function zoneName(z)
  local info = z and ns.Front.ZoneOf(z)
  return info and info.name or nil
end

local function placeLine(place)
  local name = zoneName(place[1])
  if not name then
    return nil
  end
  return string.format("%s, %d, %d", name, floor(place[2] * 100 + 0.5), floor(place[3] * 100 + 0.5))
end

local function sideWord(side)
  return side == "A" and L["Alliance"] or side == "H" and L["Horde"] or nil
end

local function metaLine(e)
  local parts = {}
  if e.levelMin then
    parts[#parts + 1] = e.levelMax
        and e.levelMax ~= e.levelMin
        and string.format(L["level %d to %d"], e.levelMin, e.levelMax)
      or string.format(e.levelMax and L["level %d"] or L["level %d+"], e.levelMin)
  end
  local names = {}
  for i, z in ipairs(e.zones or {}) do
    if i > 3 then
      break
    end
    names[#names + 1] = zoneName(z)
  end
  if names[1] then
    parts[#parts + 1] = table.concat(names, ", ")
  end
  parts[#parts + 1] = sideWord(e.side)
  if ns.Shelf.Unconfirmed(e) then
    parts[#parts + 1] = L["nobody has reported it in Forever yet"] -- E2, "unknown"
  end
  return table.concat(parts, "  /  ")
end

-- ---------------------------------------------------------------------------------------------
-- The paper: a wonder's two pages lie on the table as paper, whatever the theme (ADR 0081)
-- ---------------------------------------------------------------------------------------------

local function paper(page)
  if not page.shadow then
    S.shadow(page)
  end
  for _, tex in ipairs(page.shadow) do
    tex:Show()
  end
  S.tint(page.bg, S.C.folioPaper, 1)
  S.setEdges(page.edges, S.C.folioPaperEdge, 1)
  page.onPaper = true
end

-- The page shows something else again: the theme's panel, no shadow, the wonder's own parts gone.
function Wonder.Hide(page)
  if page.wonderPic then
    Picture.Clear(page.wonderPic)
    page.wonderPic:Hide()
  end
  if page.wonderMat then
    page.wonderMat:Hide()
  end
  for _, pool in ipairs({ page.sources or {}, page.links or {}, page.rules or {}, page.tools or {} }) do
    for _, f in ipairs(pool) do
      f:Hide()
    end
  end
  if page.onPaper then
    page.onPaper = nil
    for _, tex in ipairs(page.shadow or {}) do
      tex:Hide()
    end
    S.tint(page.bg, S.Tok(page, "panel"))
    S.setEdges(page.edges, S.Tok(page, "line"))
  end
end

local function start(page)
  page.nsources, page.nlinks, page.nrules, page.ntools = 0, 0, 0, 0
  page.sources, page.links = page.sources or {}, page.links or {}
  page.rules, page.tools = page.rules or {}, page.tools or {}
end

local function done(page)
  for i = page.nsources + 1, #page.sources do
    page.sources[i]:Hide()
  end
  for i = page.nlinks + 1, #page.links do
    page.links[i]:Hide()
  end
  for i = page.nrules + 1, #page.rules do
    page.rules[i]:Hide()
  end
  for i = page.ntools + 1, #page.tools do
    page.tools[i]:Hide()
  end
end

-- A rule of 1 in the paper's edge across the page.
local function rule(page, gap)
  page.nrules = page.nrules + 1
  local line = page.rules[page.nrules]
  if not line then
    line = S.fill(page.content, S.C.folioPaperEdge, "ARTWORK")
    page.rules[page.nrules] = line
  end
  line:ClearAllPoints()
  line:SetPoint("TOPLEFT", page.content, "TOPLEFT", 0, -page.y)
  line:SetSize(page.width, 1)
  line:Show()
  page.y = page.y + 1 + (gap or 0)
  return line
end

-- ---------------------------------------------------------------------------------------------
-- A link on paper (book-look.md 10.5): the paper's ink with a line of 1 under it in the paper's
-- edge; under the mouse both in the seal's red. A left click opens the thing's page (the Browser
-- through Core), a right click its entity menu ("Link everything with
-- everything").
-- ---------------------------------------------------------------------------------------------

local function linkInk(b, hot)
  S.ink(b.text, hot and S.C.folioSeal or S.C.folioInk)
  S.tint(b.line, hot and S.C.folioSeal or S.C.folioPaperEdge, 1)
end

local function newLink(parent)
  local b = CreateFrame("Button", nil, parent)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b.text = ns.Front.BookText(b, 13, S.C.folioInk, "bookSans")
  b.text:SetPoint("LEFT", b, "LEFT", 0, 0)
  b.line = S.fill(b, S.C.folioPaperEdge, "ARTWORK")
  b.line:ClearAllPoints()
  b.line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
  b.line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  b.line:SetHeight(1)
  b:SetScript("OnEnter", function(self)
    linkInk(self, true)
    if self.ref and GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
      S.EntityTip(GameTooltip, self.ref)
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function(self)
    linkInk(self, false)
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  b.open = function(self, button)
    if not self.ref then
      return
    end
    if button == "RightButton" then
      B.UI.EntityMenu(self.ref, nil, { source = "strategies" })
    else
      ns.Window.OpenRef(self.ref)
    end
  end
  b:SetScript("OnClick", b.open)
  return b
end

-- Sets a link's words, size and reference -> its width. `role`: the face (the book's sans; the
-- diary writes its lines in Bastian's italic). A link is pooled: its click is the reference's
-- again, whatever its last use set (until 24.11.2026 "N more sources" left its own click on the
-- button, and the next page's first link opened the sources instead of its thing).
local function setLink(b, text, ref, size, width, role)
  b.ref = ref
  b:SetScript("OnClick", b.open)
  S.SetRole(b.text, role or "bookSans")
  S.setSize(b.text, size or 13)
  b.text:SetText(text or "")
  linkInk(b, false)
  local w = b.text:GetStringWidth()
  w = (w and w > 0) and w or (#(text or "") * 6)
  if width and w > width then
    w = width
    b.text:SetWidth(width)
  else
    b.text:SetWidth(0)
  end
  b.text:SetWordWrap(false)
  b:SetSize(w, (size or 13) + 4)
  b:Show()
  return w
end

-- A link of the page's own pool, placed by the caller.
local function pageLink(page)
  page.nlinks = page.nlinks + 1
  local b = page.links[page.nlinks]
  if not b then
    b = newLink(page.content)
    page.links[page.nlinks] = b
  end
  return b
end

-- The paper's kit, shared with the diary's spread (Diary.lua): the page as paper, its pools'
-- start and end, a rule, a link.
Wonder.Paper = { lay = paper, start = start, finish = done, rule = rule, link = pageLink, set = setLink }

-- ---------------------------------------------------------------------------------------------
-- A source's row (book-look.md 10.5): 40 high. The kind's pictogram, the name as a link, under
-- it where it is and its level (the zone a link); at the right the odds or a vendor's price,
-- then two small acts: Show on map, Route there (the second only with Route).
-- ---------------------------------------------------------------------------------------------

local function smallAct(parent)
  local b = S.action(parent, {
    boxed = true,
    role = "bookSans",
    size = 11,
    height = Wonder.ACT_H,
    pad = 8,
  })
  return b
end

local function newSource(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(Wonder.SOURCE_H)
  f.palette = S.Palette("parchment") -- the kit's parts on paper draw in the Paper theme's inks
  f.glyph = f:CreateTexture(nil, "ARTWORK")
  f.glyph:SetSize(Wonder.SOURCE_GLYPH, Wonder.SOURCE_GLYPH)
  f.glyph:SetPoint("LEFT", f, "LEFT", 0, 0)
  f.name = newLink(f)
  f.zone = newLink(f)
  f.where = ns.Front.BookText(f, 11, S.C.folioInkSoft, "bookSans")
  f.odds = ns.Front.BookText(f, 13, S.C.folioInk, "bookSans")
  f.map = smallAct(f)
  f.route = smallAct(f)
  f.rule = S.fill(f, S.C.folioPaperEdge, "ARTWORK")
  f.rule:ClearAllPoints()
  f.rule:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
  f.rule:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  f.rule:SetHeight(1)
  return f
end

local function fillSource(f, row, width)
  f.row = row
  f:SetWidth(width)
  f.glyph:SetTexture(B.UI.IconTexture(row.glyph) or B.UI.IconTexture("other"))
  S.tint(f.glyph, S.C.folioInkSoft, 1)
  -- the acts from the right: Route there (only with Route), Show on map
  local right = 0
  local place = row.place
  local canRoute = place and B:GetService("route") ~= nil
  f.route:SetShown(canRoute and true or false)
  if canRoute then
    f.route:SetLabel(L["Route there"])
    f.route:ClearAllPoints()
    f.route:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    f.route:SetScript("OnClick", function()
      ns.Plate.RouteTo(place, row.name)
    end)
    right = right + f.route:GetWidth() + 5
  end
  local canShow = place and ns.Plate.CanShow(place, row.name)
  f.map:SetShown(canShow and true or false)
  if canShow then
    f.map:SetLabel(L["Show on map"])
    f.map:ClearAllPoints()
    f.map:SetPoint("RIGHT", f, "RIGHT", -right, 0)
    f.map:SetScript("OnClick", function()
      ns.Plate.ShowOnMap(place, row.name)
    end)
    right = right + f.map:GetWidth() + 5
  end
  -- the odds, or a vendor's price in coins; nothing when unknown (golden rule 2)
  local value = row.odds
  if row.price then
    value = B.UI.Money(row.price) .. (row.stack and row.stack > 1 and (" x" .. row.stack) or "")
  end
  f.odds:SetShown(value ~= nil)
  if value then
    f.odds:SetText(value)
    f.odds:ClearAllPoints()
    f.odds:SetPoint("RIGHT", f, "RIGHT", -(right + 5), 0)
    local w = f.odds:GetStringWidth()
    right = right + 5 + ((w and w > 0) and w or (#value * 6)) + 8
  end
  local x = Wonder.SOURCE_GLYPH + 10
  local room = max(40, width - x - right)
  setLink(f.name, row.name, row.ref, 13, room)
  f.name:ClearAllPoints()
  f.name:SetPoint("TOPLEFT", f, "TOPLEFT", x, -4)
  -- under it: the zone as a link, then the level
  local where = x
  f.zone:Hide()
  if row.zone and row.zoneName then
    where = where + setLink(f.zone, row.zoneName, "zone:" .. row.zone, 11, room) + 6
    f.zone:ClearAllPoints()
    f.zone:SetPoint("TOPLEFT", f, "TOPLEFT", x, -22)
  end
  local level = Sources.Where({ levelMin = row.levelMin, levelMax = row.levelMax })
  f.where:SetShown(level ~= "")
  if level ~= "" then
    f.where:SetText((row.zoneName and "-  " or "") .. level)
    f.where:ClearAllPoints()
    f.where:SetPoint("TOPLEFT", f, "TOPLEFT", where, -23)
  end
  f:Show()
end

-- The block "How to get it": a row per source, at most Sources.SHOWN, then "N more sources" as
-- a link that opens them; without a source the pack knows, the wonder's own sentence.
local expanded = {} -- [wonder id] = true: every source shown (this session)

local function howToGet(K, page, e)
  local rows = Sources.Of(e)
  if not rows[1] and not e.start then
    return
  end
  K.text(page, caps(L["How to get it"]), 11, S.C.folioInkSoft, 0, 6, "bookCaps")
  if not rows[1] then
    K.text(page, e.start, 13, S.C.folioInk)
    page.y = page.y + Wonder.BLOCK_GAP
    return
  end
  local shown = expanded[e.id] and #rows or math.min(#rows, Sources.SHOWN)
  for i = 1, shown do
    page.nsources = page.nsources + 1
    local f = page.sources[page.nsources]
    if not f then
      f = newSource(page.content)
      page.sources[page.nsources] = f
    end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", page.content, "TOPLEFT", 0, -page.y)
    fillSource(f, rows[i], page.width)
    page.y = page.y + Wonder.SOURCE_H
  end
  if shown < #rows then
    local more = pageLink(page)
    setLink(more, string.format(L["%d more sources"], #rows - shown), nil, 13)
    more:ClearAllPoints()
    more:SetPoint("TOPLEFT", page.content, "TOPLEFT", 0, -(page.y + 6))
    more:SetScript("OnClick", function()
      expanded[e.id] = true
      ns.Window.Render()
    end)
    page.y = page.y + 6 + 17
  end
  if e.start then
    page.y = page.y + 6
    K.text(page, e.start, 11, S.C.folioInkSoft)
  end
  page.y = page.y + Wonder.BLOCK_GAP
end

-- "What it gives": every item a link with its icon before it.
local function gives(K, page, e)
  if not e.gives then
    return
  end
  local head = e.chapter == "rares" and L["It drops"] or L["It gives"]
  K.text(page, caps(head), 11, S.C.folioInkSoft, 0, 6, "bookCaps")
  for _, item in ipairs(e.gives) do
    local ref = "item:" .. item
    local ent = B:Entity(ref)
    local link = pageLink(page)
    setLink(link, ent:Name() or string.format(L["item %d"], item), ref, 13, page.width)
    link:ClearAllPoints()
    link:SetPoint("TOPLEFT", page.content, "TOPLEFT", 0, -page.y)
    page.y = page.y + 20
  end
  page.y = page.y + Wonder.BLOCK_GAP
end

-- A tool of the page's foot: words in an outline, the main act the one filled plate; 28 high.
local function tool(page, label, onClick, opts)
  opts = opts or {}
  page.ntools = page.ntools + 1
  local b = page.tools[page.ntools]
  if not b then
    b = S.action(page.content, { role = "bookSans", size = 13, height = Wonder.TOOL_H, pad = 12 })
    page.tools[page.ntools] = b
  end
  -- on paper: an outline in the Paper theme's inks, the filled plate in the book's gold
  b.palette = opts.primary and S.FolioPalette() or S.Palette("parchment")
  b.spec.label, b.spec.icon = label, nil
  b.spec.primary = opts.primary and true or nil
  b.spec.boxed = not opts.primary and true or nil
  b.spec.caps = opts.primary and true or nil
  S.SetRole(b.label, opts.primary and "bookCaps" or "bookSans")
  b.tip = opts.tip
  b:SetScript("OnClick", onClick)
  S.Draw(b)
  b:Show()
  return b
end

-- The acts at the right page's foot, in a row that wraps: Mark done the filled plate, Bookmark
-- and Show on map words in an outline.
local function acts(K, page, e)
  local row = {}
  local mine = Record.Entry(e.id)
  if mine then
    local when = date and date("%d.%m.%Y", mine.at or 0) or ""
    local how = mine.how == "found" and L["Found done in the game on %s."] or L["Marked done on %s."]
    K.text(page, string.format(how, when), 13, S.C.folioInk)
    row[#row + 1] = tool(page, L["Not done yet"], function()
      Record.Unmark(e.id)
      ns.Front.Invalidate()
      ns.Window.Render()
    end)
  else
    row[#row + 1] = tool(page, L["Mark done"], function()
      Record.Mark(e.id, "mark", nil, e.title, Record.Here()) -- where and at which level: the diary's line
      ns.Window.Render()
    end, { primary = true, tip = L["It leaves the shelves and stands in Your diary."] })
  end
  row[#row + 1] = tool(page, L["Bookmark"], function()
    ns.Window.ToggleBookmark()
  end, { tip = L["Keeps this page in Your diary, also when it moves to the back shelf."] })
  local p = e.place
  if p and ns.Plate.CanShow(p, e.title) then
    row[#row + 1] = tool(page, L["Show on map"], function()
      ns.Plate.ShowOnMap(p, e.title)
    end)
  end
  if p and B:GetService("route") then
    row[#row + 1] = tool(page, L["Route there"], function()
      ns.Plate.RouteTo(p, e.title)
    end)
  end
  local x = 0
  for _, b in ipairs(row) do
    local w = b:GetWidth()
    if x > 0 and x + w > page.width then
      x = 0
      page.y = page.y + Wonder.TOOL_H + 6
    end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", page.content, "TOPLEFT", x, -page.y)
    x = x + w + 8
  end
  page.y = page.y + Wonder.TOOL_H + 8
  local alts = Record.Alts(e.id)
  if alts[1] then
    K.text(page, string.format(L["Done by %s"], table.concat(alts, ", ")), 13, S.C.folioInkSoft)
  end
end

-- Nixie's envelope: the steps, sealed until opened (per account).
local function envelope(K, page, e)
  if not e.steps then
    return
  end
  K.text(page, caps(L["Nixie's envelope"]), 11, S.C.folioInkSoft, 0, 6, "bookCaps")
  if not Record.IsOpened(e.id) then
    K.text(
      page,
      string.format(
        L["%d steps, sealed. Nixie charges two silver for a rumour; this one is on the house."],
        #e.steps
      ),
      13,
      S.C.folioInkSoft
    )
    local b = tool(page, L["Break the seal"], function()
      Record.Open(e.id)
      ns.Window.Render()
    end)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", page.content, "TOPLEFT", 0, -page.y)
    page.y = page.y + Wonder.TOOL_H + Wonder.BLOCK_GAP
    return
  end
  for i, step in ipairs(e.steps) do
    local head = step.title and (step.title .. ": ") or ""
    local side = sideWord(step.side)
    K.text(
      page,
      string.format("%d. %s%s%s", i, head, step.text or "", side and ("  (" .. side .. ")") or ""),
      13,
      S.C.folioInk
    )
    if step.tip then
      K.text(page, step.tip, 11, S.C.folioInkSoft, 14)
    end
    if step.place and ns.Plate.CanShow(step.place, step.title or e.title) then
      local where = placeLine(step.place) or L["Show on map"]
      local link = pageLink(page)
      setLink(link, where, nil, 11, page.width - 14)
      link:ClearAllPoints()
      link:SetPoint("TOPLEFT", page.content, "TOPLEFT", 14, -page.y)
      link:SetScript("OnClick", function()
        ns.Plate.ShowOnMap(step.place, step.title or e.title)
      end)
      page.y = page.y + 19
    end
  end
  page.y = page.y + Wonder.BLOCK_GAP
end

-- The plate on the left page: the picture on a mat of 5, its caption centred under it.
local function plate(K, page, e)
  local pic, mat = page.wonderPic, page.wonderMat
  if not pic then
    mat = CreateFrame("Frame", nil, page.content)
    mat.fill = S.fill(mat, S.C.folioSealText, "BACKGROUND")
    mat.edge = S.border(mat, S.C.folioPaperEdge)
    pic = Picture.New(mat, true) -- framed: a model needs its border (16.11.2026)
    page.wonderPic, page.wonderMat = pic, mat
  end
  local w = page.width - 2 * Wonder.MAT
  local h = floor(w * Wonder.PLATE)
  mat:ClearAllPoints()
  mat:SetPoint("TOPLEFT", page.content, "TOPLEFT", 0, -page.y)
  mat:SetSize(page.width, h + 2 * Wonder.MAT)
  mat:Show()
  pic:ClearAllPoints()
  pic:SetPoint("TOPLEFT", mat, "TOPLEFT", Wonder.MAT, -Wonder.MAT)
  local drew = Picture.Draw(pic, e, w, h)
  pic:Show()
  -- a done wonder wears the stamp and its date on its plate (R4.11), above the picture's rim
  Picture.Stamp(mat, pic, Record.Entry(e.id), 12)
  page.y = page.y + h + 2 * Wonder.MAT + 6
  local caption
  if drew == "art" then
    caption = L["Drawn by Bastian, in the evenings, at whatever inn would have him."]
  elseif drew == "model" then
    caption = e.place and placeLine(e.place) or nil
  elseif drew == "painting" then
    caption = e.place and placeLine(e.place) or zoneName(e.zones and e.zones[1])
  end
  if caption then
    local fs = K.text(page, caption, 13, S.C.folioInkSoft, nil, nil, "bookItalic")
    fs:SetJustifyH("CENTER")
  end
  return drew
end

-- Renders the wonder `id` on the two pages -> its title. K: the window's page kit.
function Wonder.Render(K, left, right, id)
  local e = ns.Front.Find(id)
  if not e then
    K.text(left, L["This wonder is not in the book any more."], 13, S.C.dim)
    return id
  end
  paper(left)
  paper(right)
  start(left)
  start(right)
  -- the left page: the plate, then the tale in Bastian's hand and what the travellers say
  plate(K, left, e)
  if e.hook then
    K.space(left, 4)
    K.text(left, e.hook, 13, S.C.folioInk, nil, nil, "bookItalic")
  end
  if e.tale then
    K.space(left, 4)
    if e.hook then
      K.text(left, caps(L["What the travellers say"]), 11, S.C.folioInkSoft, 0, 3, "bookCaps")
    end
    K.text(left, e.tale, 13, S.C.folioInk, nil, nil, "bookItalic")
  end
  if e.note then
    K.text(left, e.note, 11, S.C.folioInkSoft)
  end
  -- the right page: the kind, the title at the display size, a rule, then the blocks
  K.text(right, caps(ns.Front.KindLabel(e)), 11, S.C.folioInkSoft, 0, 4, "bookCaps")
  local title = K.text(right, e.title, 18, S.C.folioInk, 0, 0, "bookDisplay")
  local before = ns.Window.HeightOf(e.title, 18, right.width)
  S.setSize(title, Wonder.TITLE)
  local lines = max(1, floor(before / 18 + 0.5))
  right.y = right.y - before + lines * Wonder.TITLE_LINE + 6
  local meta = metaLine(e)
  if meta ~= "" then
    K.text(right, meta, 11, S.C.folioInkSoft)
  end
  rule(right, Wonder.BLOCK_GAP)
  howToGet(K, right, e)
  gives(K, right, e)
  envelope(K, right, e)
  acts(K, right, e)
  done(left)
  done(right)
  return e.title
end
