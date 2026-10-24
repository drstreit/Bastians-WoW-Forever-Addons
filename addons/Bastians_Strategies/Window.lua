-- Bastian's Strategies: the book window (strategies-design.md section 6): two pages; the title page with
-- What's new, the front matter, the contents, the index, the bookmarks, and the strategy pages with
-- their plate, live box, table, rumours, the places they name and the reader's note.
local _, ns = ...
local B = Bastians
local S = B.UI.Style
local L = ns.L
local Book = ns.Book

local Window = {}
ns.Window = Window

local PAD = 16 -- inside a page
local GAP = 6 -- between blocks
local SPINE = 8 -- between the two pages
local FRONT = "front" -- the chapter of the front matter (preface, before you start): not in the contents
local NEWS_SHOWN = 12

local win, bar, left, right, folio, measure
local current = { kind = "title" }
Window.PLATE_CTX = {}

-- ---------------------------------------------------------------------------------------------
-- Data (through the data service; nil and empty without the pack)
-- ---------------------------------------------------------------------------------------------

local function data()
  return B:GetService("data")
end

local function get(typ, id)
  local d = data()
  return d and d:Get(typ, id) or nil
end

function Window.Toc()
  local d = data()
  return d and d:Index("book.toc") or nil
end

function Window.Pages()
  local d, out = data(), {}
  if d then
    for _, id in ipairs(d:Each("page")) do
      out[id] = d:Get("page", id)
    end
  end
  return out
end

function Window.News()
  local d, out = data(), {}
  if d then
    for _, id in ipairs(d:Each("news")) do
      out[#out + 1] = d:Get("news", id)
    end
  end
  return out
end

-- The Rumour mill of a chapter (strategies-design.md section 7): the strongest rumours no page
-- tells yet, by rank. -> { { id = claim id, mill, rumour } }, empty without them.
function Window.Mill(chapter)
  local d, out = data(), {}
  local idx = d and d:Index("book.mill")
  for _, cid in ipairs(idx and idx[chapter] or {}) do
    local m, r = get("mill", cid), get("rumour", cid)
    if m and r then
      out[#out + 1] = { id = cid, mill = m, rumour = r }
    end
  end
  return out
end

local function db()
  return ns.mod.db
end

local function facts()
  return B.Compat.GetPlayerFacts and B.Compat.GetPlayerFacts() or {}
end

-- The reading order: the title page, the front matter, the contents, every chapter's active pages
-- and its Rumour mill.
function Window.Order()
  local out = { { kind = "title" } }
  local toc = Window.Toc()
  for _, id in ipairs(toc and toc.pages and toc.pages[FRONT] or {}) do
    out[#out + 1] = { kind = "page", id = id }
  end
  out[#out + 1] = { kind = "contents" }
  local rest = { chapters = {}, pages = toc and toc.pages or {} }
  for _, c in ipairs(toc and toc.chapters or {}) do
    if c ~= FRONT then
      rest.chapters[#rest.chapters + 1] = c
    end
  end
  for _, entry in
    ipairs(Book.Order(rest, function(chapter)
      return #Window.Mill(chapter) > 0
    end))
  do
    out[#out + 1] = entry
  end
  return out
end

local function same(a, b)
  return a and b and a.kind == b.kind and a.id == b.id
end

-- ---------------------------------------------------------------------------------------------
-- A page of the book: a scroll frame; widgets are laid out top-down and pooled per page
-- ---------------------------------------------------------------------------------------------

local function newPage(parent)
  local p = CreateFrame("Frame", nil, parent)
  S.panel(p, S.C.panel)
  local scroll = CreateFrame("ScrollFrame", nil, p)
  scroll:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -PAD)
  scroll:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -PAD - 8, PAD)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)
  p.scroll, p.content = scroll, content
  p.bar = S.scrollbar(scroll, p, nil)
  p.fs, p.rows, p.plates, p.boxes, p.edits, p.pics = {}, {}, {}, {}, {}, {}
  return p
end

local function begin(page)
  page.y = 0
  page.nfs, page.nrows, page.nplates, page.nboxes, page.nedits, page.npics = 0, 0, 0, 0, 0, 0
  page.width = math.max(120, (page.scroll:GetWidth() or 0) > 0 and page.scroll:GetWidth() or 360)
  page.scroll:SetVerticalScroll(0)
end

local function finish(page)
  for i = page.nfs + 1, #page.fs do
    page.fs[i]:Hide()
  end
  for i = page.nrows + 1, #page.rows do
    page.rows[i]:Hide()
  end
  for i = page.nplates + 1, #page.plates do
    page.plates[i]:Hide()
  end
  for i = page.nboxes + 1, #page.boxes do
    page.boxes[i]:Hide()
  end
  for i = page.nedits + 1, #page.edits do
    page.edits[i]:Hide()
  end
  for i = page.npics + 1, #page.pics do
    page.pics[i]:Hide()
  end
  page.content:SetSize(page.width, math.max(1, page.y))
  page.bar.SetTotal(page.y)
end

-- The height a wrapped text takes at `width` (the client's measure; an estimate where it has none).
local function heightOf(text, size, width)
  measure:SetWidth(width)
  S.setSize(measure, size)
  measure:SetText(text)
  local h = measure:GetStringHeight() or 0
  if h <= 0 then
    local plain = string.gsub(string.gsub(text or "", "|c%x%x%x%x%x%x%x%x", ""), "|r", "")
    local chars = math.max(10, math.floor(width / (size * 0.5)))
    h = math.max(1, math.ceil(#plain / chars)) * (size + 3)
  end
  return h
end
Window.HeightOf = function(text, size, width)
  return heightOf(text, size, width)
end

local function addText(page, text, size, color, indent, gap)
  indent = indent or 0
  page.nfs = page.nfs + 1
  local fs = page.fs[page.nfs]
  if not fs then
    fs = S.text(page.content, size, color)
    fs:SetWordWrap(true)
    fs:SetJustifyV("TOP")
    page.fs[page.nfs] = fs
  end
  S.setSize(fs, size)
  S.ink(fs, color or S.C.text)
  fs:SetWidth(page.width - indent)
  fs:SetText(text)
  fs:ClearAllPoints()
  fs:SetPoint("TOPLEFT", page.content, "TOPLEFT", indent, -page.y)
  fs:Show()
  page.y = page.y + heightOf(text, size, page.width - indent) + (gap or GAP)
  return fs
end

-- A clickable line (contents, index, bookmarks, the places on a page, a source's copy link).
local function addRow(page, text, onClick, opts)
  opts = opts or {}
  page.nrows = page.nrows + 1
  local row = page.rows[page.nrows]
  if not row then
    row = CreateFrame("Button", nil, page.content)
    row.hl = S.fill(row, S.C.hover, "BACKGROUND")
    row.hl:Hide()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(12, 12)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.label = S.text(row, 12, S.C.text)
    row.label:SetWordWrap(false)
    row:SetScript("OnEnter", function(self)
      self.hl:Show()
      if self.tip then
        S.TipEnter(self)
      end
    end)
    row:SetScript("OnLeave", function(self)
      self.hl:Hide()
      S.TipLeave(self)
    end)
    row:SetScript("OnClick", function(self, button)
      if self.onClick then
        self.onClick(self, button)
      end
    end)
    page.rows[page.nrows] = row
  end
  local indent = opts.indent or 0
  local size = opts.size or 12
  row.onClick = onClick
  row.tip = opts.tip
  row.ref = opts.ref
  row.entry = opts.entry
  if opts.icon then
    B.UI.PaintIcon(row.icon, opts.icon)
    row.icon:Show()
  else
    row.icon:Hide()
  end
  S.setSize(row.label, size)
  S.ink(row.label, opts.color or S.C.text)
  row.label:SetText(text)
  row.label:ClearAllPoints()
  row.label:SetPoint("LEFT", row, "LEFT", opts.icon and 17 or 2, 0)
  row.label:SetPoint("RIGHT", row, "RIGHT", -2, 0)
  row:SetSize(page.width - indent, size + 6)
  row:ClearAllPoints()
  row:SetPoint("TOPLEFT", page.content, "TOPLEFT", indent, -page.y)
  row:Show()
  page.y = page.y + size + 6 + (opts.gap or 1)
  return row
end

local function addSpace(page, px)
  page.y = page.y + (px or GAP)
end

local function caps(text)
  return string.upper(text or "")
end

-- ---------------------------------------------------------------------------------------------
-- The text of a page: tokens, money, the reader's market
-- ---------------------------------------------------------------------------------------------

local function priceOf(item)
  local prices = B:GetService("prices")
  local p = prices and prices:Price(item)
  return p and (p.median or p.minBuyout) or nil -- unknown stays nil (golden rule 2)
end
Window.PriceOf = priceOf

local function vendorOf(item)
  local r = get("item", item)
  return r and r.sell or nil
end

local function money(copper)
  if copper == nil then
    return L["price unknown"]
  end
  return B.UI.Money(copper)
end

local function nameOf(kind, id)
  local ref = kind .. ":" .. tostring(id)
  return B:Entity(ref):Name() or ref
end

-- The tokens drawn: names in the accent colour, prices as money, unknown said so.
function Window.Expand(text)
  return Book.Expand(text, {
    name = function(kind, id)
      return S.H.accent .. nameOf(kind, id) .. "|r"
    end,
    price = function(id)
      return S.H.gold .. money(priceOf(id)) .. "|r"
    end,
    vendor = function(id)
      return S.H.gold .. money(vendorOf(id)) .. "|r"
    end,
  })
end

-- ---------------------------------------------------------------------------------------------
-- Blocks
-- ---------------------------------------------------------------------------------------------

-- the export's status as a stamp, where our own check did not set one (the Rumour mill)
local STATUS_STAMP = { verified = "true", refuted = "lies", unverified = "open" }

local STAMPS = {
  ["true"] = { "Checked", "good" },
  half = { "Half right", "warn" },
  lies = { "Did not hold", "bad" },
  open = { "Heard, not checked", "muted" },
}
Window.STAMPS = STAMPS

function Window.StampText(stamp)
  local s = STAMPS[stamp] or STAMPS.open
  return S.H[s[2]] .. "[" .. L[s[1]] .. "]|r"
end

local function liveLines(spec)
  local lines = {}
  if not B:GetService("prices") then
    lines[1] = L["No auction prices here: Bastian's Gold brings them."]
    return lines
  end
  if spec.kind == "farm" then
    local box = Book.Farm(spec.npcs, function(id)
      local r = get("npc", id) or get("object", id)
      return r and r.loot or nil
    end, priceOf)
    if not box then
      lines[1] = L["No loot known for these creatures."]
      return lines
    end
    if box.perKill then
      lines[#lines + 1] =
        string.format(L["%s a kill in loot, %s per 100 kills."], money(box.perKill), money(box.perKill * 100))
    else
      lines[#lines + 1] = L["No auction price for their loot yet."]
    end
    for i = 1, math.min(spec.top or 3, #box.items) do
      local it = box.items[i]
      lines[#lines + 1] = string.format(
        L["%s: %s of the kills, %s each"],
        nameOf("item", it.item),
        B.UI.FormatValue(it.chance, "percent"),
        money(it.price)
      )
    end
    lines[#lines + 1] = L["After the auction house's cut. Coin and rare drops are not counted."]
  elseif spec.kind == "flip" then
    local buy, sell = nameOf("item", spec.buy), nameOf("item", spec.sell)
    local box = Book.Flip(priceOf(spec.buy), vendorOf(spec.sell), spec.per)
    if not box then
      lines[1] = L["No vendor price known."]
      return lines
    end
    lines[#lines + 1] = string.format(
      L["%s on the auction house: %s. %s at a vendor: %s."],
      buy,
      money(priceOf(spec.buy)),
      sell,
      money(box.sale)
    )
    if box.margin == nil then
      lines[#lines + 1] = L["No auction price yet: the box opens with the first scan."]
    elseif box.open then
      lines[#lines + 1] = S.H.good
        .. string.format(
          L["The bargain is open: %s a piece, %s a stack of 20."],
          money(box.margin),
          money(box.margin * 20)
        )
        .. "|r"
    elseif box.ownAH and box.ownAH > box.sale then
      lines[#lines + 1] = string.format(
        L["Closed. Sell your %s on the auction house: %s each after the cut."],
        buy,
        money(box.ownAH)
      )
    else
      lines[#lines + 1] = string.format(L["Closed. Wait for cheaper %s."], buy)
    end
  elseif spec.kind == "craft" then
    local box = Book.Craft(priceOf(spec.item), spec.count, spec.reagents, function(item)
      local r = get("item", item)
      return priceOf(item) or (r and r.buy) or nil
    end)
    for _, r in ipairs(spec.reagents or {}) do
      local cost = priceOf(r[1]) or (get("item", r[1]) or {}).buy
      lines[#lines + 1] = string.format(L["%d x %s at %s"], r[2], nameOf("item", r[1]), money(cost))
    end
    if box.margin then
      local col = box.margin > 0 and S.H.good or S.H.bad
      lines[#lines + 1] = col
        .. string.format(
          L["%s sells for %s after the cut: %s a craft."],
          nameOf("item", spec.item),
          money(box.sale),
          money(box.margin)
        )
        .. "|r"
    elseif box.sale then
      lines[#lines + 1] = L["A reagent has no price yet: no margin today."]
    else
      lines[#lines + 1] = string.format(L["%s: no auction price yet."], nameOf("item", spec.item))
    end
  elseif spec.kind == "prices" then
    for _, item in ipairs(spec.items or {}) do
      lines[#lines + 1] = string.format(L["%s: %s"], nameOf("item", item), money(priceOf(item)))
    end
  end
  return lines
end
Window.LiveLines = liveLines

local function addBox(page, title, lines)
  page.nboxes = page.nboxes + 1
  local box = page.boxes[page.nboxes]
  if not box then
    box = CreateFrame("Frame", nil, page.content)
    S.panel(box, S.C.header, "radiusSmall")
    box.fs = {}
    page.boxes[page.nboxes] = box
  end
  local width = page.width
  local y = 6
  local all = { S.H.muted .. caps(title) .. "|r" }
  for _, line in ipairs(lines) do
    all[#all + 1] = line
  end
  for i, line in ipairs(all) do
    local fs = box.fs[i]
    if not fs then
      fs = S.text(box, 12, S.C.text)
      fs:SetWordWrap(true)
      fs:SetJustifyV("TOP")
      box.fs[i] = fs
    end
    fs:SetWidth(width - 16)
    fs:SetText(line)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -y)
    fs:Show()
    y = y + heightOf(line, 12, width - 16) + 2
  end
  for i = #all + 1, #box.fs do
    box.fs[i]:Hide()
  end
  box:SetSize(width, y + 6)
  box:ClearAllPoints()
  box:SetPoint("TOPLEFT", page.content, "TOPLEFT", 0, -page.y)
  box:Show()
  page.y = page.y + y + 6 + GAP
  return box
end

local function tableLines(spec)
  local rows = Book.Pairs(spec.rows, vendorOf)
  local out = {}
  for _, r in ipairs(rows) do
    local gain = ""
    if r.gain then
      local pct = math.floor(r.gain * 100 + (r.gain >= 0 and 0.5 or -0.5))
      gain = (pct >= 0 and S.H.good .. "+" or S.H.bad) .. pct .. "|r"
    end
    out[#out + 1] = string.format(
      L["%s (%s) as %s (%s): %s"],
      nameOf("item", r.from) .. (r.per > 1 and (" x" .. r.per) or ""),
      money(r.fromSell and r.fromSell * r.per or nil),
      nameOf("item", r.made),
      money(r.madeSell),
      gain ~= "" and gain .. " " .. L["percent at the vendor"] or L["price unknown"]
    )
  end
  return out
end
Window.TableLines = tableLines

local function addPlate(page, spec)
  page.nplates = page.nplates + 1
  local plate = page.plates[page.nplates]
  if not plate then
    plate = ns.Plate.New(page.content)
    page.plates[page.nplates] = plate
  end
  local f = facts()
  local h = plate:Draw(
    spec,
    page.width,
    { faction = f.faction == "Horde" and "H" or f.faction == "Alliance" and "A" or nil }
  )
  plate.frame:ClearAllPoints()
  plate.frame:SetPoint("TOPLEFT", page.content, "TOPLEFT", 0, -page.y)
  page.y = page.y + h + GAP
  return plate
end

-- Opens an entity named on a page: in the Browser when it is there, else the primary action, else
-- the map's ring (golden rule 3: through Core's actions, never a direct call).
function Window.OpenRef(ref)
  local ctx = { source = "strategies" }
  if B:RunAction("browser.open", ref, ctx) ~= false then
    return "browser"
  end
  local action = B:GetPrimaryAction(ref, ctx)
  if action and B:RunAction(action.id, ref, ctx) ~= false then
    return action.id
  end
  B:Focus(ref, ctx)
  return "focus"
end

local function addNote(page, id)
  page.nedits = page.nedits + 1
  local box = page.edits[page.nedits]
  if not box then
    box = S.search(page.content, L["Your note on this page (kept for every character)"])
    box:SetMultiLine(true)
    box:SetHeight(64)
    box:SetScript("OnTextChanged", function(self, userInput)
      local text = self:GetText() or ""
      if text == "" then
        self.hint:Show()
        self.clear:Hide()
      else
        self.hint:Hide()
        self.clear:Show()
      end
      if self.pageID and userInput ~= false then
        ns.mod.db.global.notes[self.pageID] = text ~= "" and text or nil
      end
    end)
    page.edits[page.nedits] = box
  end
  box.pageID = nil -- no saving while the text is set below
  box:SetWidth(page.width)
  box:SetText(db().global.notes[id] or "")
  box.pageID = id
  box:ClearAllPoints()
  box:SetPoint("TOPLEFT", page.content, "TOPLEFT", 0, -page.y)
  box:Show()
  page.y = page.y + 64 + GAP
  return box
end

-- ---------------------------------------------------------------------------------------------
-- The spreads
-- ---------------------------------------------------------------------------------------------

-- Lays a page's blocks over the two pages: the left fills first, a block that does not fit moves
-- to the right one, which scrolls when it overflows.
local function flowBlocks(page, blocks)
  local target = left
  local leftMax = (left.scroll:GetHeight() or 0) > 0 and left.scroll:GetHeight() or 480
  local function room(h)
    if target == left and left.y > 0 and left.y + h > leftMax then
      target = right
    end
    return target
  end
  for _, b in ipairs(blocks or {}) do
    local kind = b[1]
    if kind == "opening" or kind == "p" then
      local text = Window.Expand(b[2])
      room(heightOf(text, 13, target.width))
      addText(target, text, 13, kind == "opening" and S.C.dim or S.C.text)
    elseif kind == "h" then
      room(40)
      addSpace(target, 4)
      addText(target, caps(b[2]), 11, S.C.accent, 0, 3)
    elseif kind == "steps" then
      for i, step in ipairs(b[2]) do
        local text = i .. ". " .. Window.Expand(step)
        room(heightOf(text, 13, target.width - 10))
        addText(target, text, 13, S.C.text, 10, 3)
      end
      addSpace(target, 3)
    elseif kind == "verdict" then
      local text = S.H.muted .. caps(L["Bastian's verdict"]) .. "|r  " .. Window.Expand(b[2])
      room(heightOf(text, 13, target.width))
      addSpace(target, 4)
      addText(target, text, 13, S.C.text)
    elseif kind == "plate" and page.plate then
      room((target.width / 1.62) + 20)
      addPlate(target, page.plate)
    elseif kind == "live" and page.live then
      room(90)
      addBox(
        target,
        page.live.kind == "farm" and L["What it pays on your market"] or L["Today on your market"],
        liveLines(page.live)
      )
    elseif kind == "table" and page.table then
      room(80)
      addBox(target, L["At the vendor"], tableLines(page.table))
    end
  end
  return target
end

local function shelfWord(p)
  if p.shelf == "back" then
    return L["From the back shelf"]
  end
  local c = p.chapter and get("chapter", p.chapter)
  return c and c.name or ""
end

local function sealedText(p)
  local zones = {}
  for _, z in ipairs(p.zones or {}) do
    zones[#zones + 1] = nameOf("zone", z)
  end
  if #zones > 0 then
    return string.format(
      L["This page is sealed. It opens at level %d, or the first time you set foot in %s."],
      math.max(1, p.levelMin - Book.UNSEAL_EARLY),
      table.concat(zones, ", ")
    )
  end
  return string.format(
    L["This page is sealed. It opens at level %d."],
    math.max(1, p.levelMin - Book.UNSEAL_EARLY)
  )
end

-- The page's picture (content/strategies/art), the page's width at 2:1. A picture that came with a
-- new Data edition is a new file: the client takes it without an error but shows it only after
-- a full restart (GetTexture stays nil, Forever 22.10.2026), so until then the page has none.
local ART = "Interface\\AddOns\\Bastians_Data_Strategies\\Generated\\Art\\"
local function addPicture(page, id)
  local tex = page.pics[page.npics + 1]
  if not tex then
    tex = page.content:CreateTexture(nil, "ARTWORK")
    page.pics[page.npics + 1] = tex
  end
  tex:SetTexture(ART .. id)
  if not tex:GetTexture() then
    tex:Hide()
    return nil
  end
  page.npics = page.npics + 1
  local h = math.floor(page.width / 2)
  tex:SetSize(page.width, h)
  tex:ClearAllPoints()
  tex:SetPoint("TOPLEFT", page.content, "TOPLEFT", 0, -page.y)
  tex:Show()
  page.y = page.y + h + GAP
  return tex
end
Window.ART = ART

local function header(page, p)
  addText(left, caps(shelfWord(p)), 10, S.C.dim, 0, 2)
  addText(left, p.name or page, 18, S.C.bright, 0, 4)
  if p.meta then
    addText(left, table.concat(p.meta, "  /  "), 11, S.C.dim)
  end
end

-- The travellers of a rumour: channel, date, the moment in the video, the link to copy.
local function sourceRows(target, sources)
  for _, src in ipairs(sources or {}) do
    local channel, date, link = src[1], src[2], src[3]
    local moment = Book.Moment(link)
    local line = tostring(channel)
      .. (date and (", " .. date) or "")
      .. (moment and (", " .. string.format(L["at %s"], moment)) or "")
    addRow(target, line .. "  " .. S.H.accent .. L["copy the link"] .. "|r", function()
      B.Compat.OpenChat(link) -- the game opens no browser: the link goes into the chat box to copy
    end, {
      size = 11,
      indent = 10,
      color = S.C.dim,
      tip = L["Puts the link into the chat input: copy it with Ctrl+C."],
    })
  end
end

local function rumourLines(target, p)
  if not p.rumours then
    return
  end
  addSpace(target, 4)
  addText(target, caps(L["The rumours on this page"]), 11, S.C.accent, 0, 3)
  for _, r in ipairs(p.rumours) do
    local claimID, stamp, why = r[1], r[2], r[3]
    local rumour = get("rumour", claimID)
    if rumour then
      addText(
        target,
        Window.StampText(stamp) .. " " .. (rumour.claim or rumour.subject or ""),
        12,
        S.C.text,
        0,
        2
      )
      if why then
        addText(target, why, 11, S.C.dim, 10, 2)
      end
      sourceRows(target, rumour.sources)
    end
  end
end

local function refRows(target, p)
  if not p.refs then
    return
  end
  addSpace(target, 4)
  addText(target, caps(L["On this page"]), 11, S.C.accent, 0, 3)
  for _, ref in ipairs(p.refs) do
    local e = B:Entity(ref)
    addRow(target, e:Name() or ref, function()
      Window.OpenRef(ref)
    end, {
      icon = e:Icon(),
      ref = ref,
      tip = L["Opens it in Bastian's Browser, or on the map without it."],
    })
  end
end

local function renderPage(id)
  local p = get("page", id)
  if not p then
    addText(left, L["This page is not in the book any more."], 13, S.C.dim)
    return id
  end
  header(id, p)
  if p.shelf == "retired" then
    addText(
      left,
      string.format(L["Retired on %s: %s"], tostring(p.retired), tostring(p.reason)),
      13,
      S.C.text
    )
    local next = p.successor and get("page", p.successor)
    if next then
      addRow(left, string.format(L["Read on: %s"], next.name), function()
        Window.Show({ kind = "page", id = p.successor })
      end, { color = S.C.accent })
    end
    return p.name
  end
  local level = facts().level
  if not Book.IsOpen(p, level, db().char.entered) and p.chapter ~= FRONT then
    addText(left, sealedText(p), 13, S.C.text)
    return p.name
  end
  if p.art then
    addPicture(left, id)
  end
  local last = flowBlocks(p, p.blocks)
  rumourLines(last, p)
  refRows(last, p)
  if p.chapter ~= FRONT then
    addSpace(last, 6)
    addText(last, caps(L["Your note"]), 11, S.C.accent, 0, 3)
    addNote(last, id)
  end
  return p.name
end

-- The Rumour mill of a chapter: one rumour after the other, flowing onto the right page.
local function renderMill(chapter)
  local c = get("chapter", chapter)
  local name = c and c.name or chapter
  addText(left, caps(L["The rumour mill"]), 10, S.C.dim, 0, 2)
  addText(left, name, 18, S.C.bright, 0, 4)
  addText(
    left,
    L["What the travellers say and I have not tried yet, with the stamp and where to hear it."]
      .. " "
      .. L["When one of them holds up, it gets a page."],
    12,
    S.C.dim,
    0,
    8
  )
  local entries = Window.Mill(chapter)
  if #entries == 0 then
    addText(left, L["Nothing in the mill for this chapter today."], 12, S.C.dim)
  end
  local leftMax = (left.scroll:GetHeight() or 0) > 0 and left.scroll:GetHeight() or 480
  local target = left
  for _, e in ipairs(entries) do
    if target == left and left.y + 60 > leftMax then
      target = right
    end
    local stamp = STATUS_STAMP[e.rumour.status or ""] or "open"
    addText(
      target,
      Window.StampText(stamp) .. " " .. (e.rumour.claim or e.rumour.subject or ""),
      12,
      S.C.text,
      0,
      2
    )
    local place = e.mill.zone and nameOf("zone", e.mill.zone) or e.mill.where
    local told = string.format(L["told by %d channels"], e.mill.channels or 0)
    addText(target, (place and (place .. "  /  ") or "") .. told, 11, S.C.dim, 10, 2)
    sourceRows(target, e.rumour.sources)
    addSpace(target, 4)
  end
  return string.format(L["Rumour mill: %s"], name)
end

local function renderTitle()
  addSpace(left, 40)
  addText(left, caps(L["Bastian's Strategies"]), 11, S.C.dim, 0, 8)
  addText(left, L["Bastian's Gold Rumours"], 24, S.C.bright, 0, 12)
  addText(
    left,
    L["Every way to get rich I was ever told about, written down by a man who is still not rich"],
    13,
    S.C.text,
    0,
    16
  )
  addText(left, L["Printed in Booty Bay, on credit."], 11, S.C.dim)
  addText(right, caps(L["What's new"]), 11, S.C.accent, 0, 6)
  local news = Window.News()
  if #news == 0 then
    addText(
      right,
      L["The book's pages are not installed: Bastian's Data: Strategies brings them."],
      12,
      S.C.dim
    )
  end
  local seen = db().global.seen
  for i = 1, math.min(NEWS_SHOWN, #news) do
    local n = news[i]
    local new = Book.IsNew(n, seen, db().global.seenToday)
    local line = (new and (S.H.good .. L["new"] .. "|r  ") or "") .. S.H.muted .. n.date .. "|r  " .. n.text
    if n.page and get("page", n.page) then
      addRow(right, line, function()
        Window.Show({ kind = "page", id = n.page })
      end, { size = 12 })
    elseif n.mill and get("chapter", n.mill) then
      -- an entry the build wrote about a chapter's Rumour mill opens that mill
      addRow(right, line, function()
        Window.Show({ kind = "mill", id = n.mill })
      end, { size = 12 })
    else
      addText(right, line, 12, S.C.text, 0, 3)
    end
  end
  if news[1] then
    -- read once the page was shown: the newest date and its texts
    local today = {}
    for _, n in ipairs(news) do
      if n.date == news[1].date then
        today[n.text] = true
      end
    end
    db().global.seen, db().global.seenToday = news[1].date, today
    if B.MarkNewsSeen then
      B:MarkNewsSeen(ns.mod) -- the suite's What's new: the book's lines were read here (ADR 0021)
    end
  end
  return L["Bastian's Gold Rumours"]
end

local function pageLine(id, p, level, entered)
  local band = p.levelMin and string.format(L["level %d-%d"], p.levelMin, p.levelMax) or ""
  local open = Book.IsOpen(p, level, entered)
  return (open and "" or S.H.muted)
    .. (p.name or id)
    .. "  "
    .. S.H.muted
    .. band
    .. (open and "" or ("  " .. L["sealed"]))
    .. "|r",
    open
end

local function renderContents()
  addText(left, caps(L["Contents"]), 11, S.C.accent, 0, 6)
  local toc = Window.Toc()
  local level, entered = facts().level, db().char.entered
  for _, cid in ipairs(toc and toc.chapters or {}) do
    if cid ~= FRONT then
      local c = get("chapter", cid)
      addText(left, c and c.name or cid, 14, S.C.bright, 0, 2)
      local ids = toc.pages[cid] or {}
      if #ids == 0 then
        addText(left, L["(no pages yet)"], 11, S.C.dim, 10, 4)
      end
      for _, id in ipairs(ids) do
        local p = get("page", id)
        if p then
          local text = pageLine(id, p, level, entered)
          addRow(left, text, function()
            Window.Show({ kind = "page", id = id })
          end, { indent = 10, entry = { kind = "page", id = id } })
        end
      end
      local mill = #Window.Mill(cid)
      if mill > 0 then
        addRow(left, string.format(L["Rumour mill: %d rumours I have not tried yet"], mill), function()
          Window.Show({ kind = "mill", id = cid })
        end, { indent = 10, color = S.C.dim, entry = { kind = "mill", id = cid } })
      end
      addSpace(left, 4)
    end
  end
  local back = 0
  for _, p in pairs(Window.Pages()) do
    if p.shelf == "back" then
      back = back + 1
    end
  end
  if back > 0 then
    addRow(left, string.format(L["The back shelf: %d older pages, in the index"], back), function()
      Window.Show({ kind = "index" })
    end, { color = S.C.dim })
  end
  -- the legend of the stamps, the right page
  addText(right, caps(L["The stamps"]), 11, S.C.accent, 0, 4)
  for _, key in ipairs({ "true", "half", "lies", "open" }) do
    local what = {
      ["true"] = L["I held the rumour against the prices and the loot tables, and it stood."],
      half = L["True for part of it. The page says which part."],
      lies = L["It failed the check. The page stays as a warning."],
      open = L["Nobody has managed to check it yet."],
    }
    addText(right, Window.StampText(key) .. " " .. what[key], 12, S.C.text, 0, 3)
  end
  addSpace(right, 6)
  addText(right, caps(L["Your bookmarks and notes"]), 11, S.C.accent, 0, 4)
  addText(
    right,
    L["A page keeps its place in your bookmarks and its note when it moves to the back shelf or is retired."],
    12,
    S.C.text
  )
  return L["Contents"]
end

local function renderIndex()
  addText(left, caps(L["Index"]), 11, S.C.accent, 0, 6)
  local pages = Window.Pages()
  local entries = Book.Index(pages, function(ref)
    return B:Entity(ref):Name()
  end)
  local leftMax = (left.scroll:GetHeight() or 0) > 0 and left.scroll:GetHeight() or 480
  local target = left
  for _, e in ipairs(entries) do
    if target == left and left.y + 20 > leftMax then
      target = right
    end
    if e.kind == "page" then
      local p = pages[e.page]
      local note = p.shelf == "back" and ("  " .. S.H.muted .. L["back shelf"] .. "|r")
        or p.shelf == "retired" and ("  " .. S.H.muted .. L["retired"] .. "|r")
        or ""
      addRow(target, e.text .. note, function()
        Window.Show({ kind = "page", id = e.page })
      end, { icon = B.UI.IconTexture("ledger") })
    else
      local titles = {}
      for _, id in ipairs(e.pages) do
        titles[#titles + 1] = pages[id] and pages[id].name or id
      end
      addRow(target, e.text .. "  " .. S.H.muted .. table.concat(titles, ", ") .. "|r", function()
        Window.Show({ kind = "page", id = e.pages[1] })
      end, { icon = B:Entity(e.ref):Icon(), ref = e.ref })
    end
  end
  if #entries == 0 then
    addText(left, L["The index is empty: the book's pages are not installed."], 12, S.C.dim)
  end
  return L["Index"]
end

-- A page's text as the reader sees it, for the search: the meta line, the blocks with names for
-- the tokens (no prices: they change), the rumours. Kept per page id: a Data edition needs a
-- restart anyway.
local searchText = {}
local PLAIN = {
  name = nameOf,
  price = function()
    return ""
  end,
  vendor = function()
    return ""
  end,
}
local function textOf(id, p)
  if searchText[id] then
    return searchText[id]
  end
  local parts = { table.concat(p.meta or {}, " ") }
  for _, b in ipairs(p.blocks or {}) do
    if b[1] == "steps" then
      for _, step in ipairs(b[2]) do
        parts[#parts + 1] = Book.Expand(step, PLAIN)
      end
    elseif type(b[2]) == "string" then
      parts[#parts + 1] = Book.Expand(b[2], PLAIN)
    end
  end
  for _, r in ipairs(p.rumours or {}) do
    local rumour = get("rumour", r[1])
    parts[#parts + 1] = rumour and (rumour.claim or rumour.subject) or nil
  end
  searchText[id] = table.concat(parts, " ")
  return searchText[id]
end
Window.TextOf = textOf

local function renderSearch(query)
  addText(left, caps(L["Search the book"]), 11, S.C.accent, 0, 6)
  local pages = Window.Pages()
  local hits = Book.Search(pages, query, textOf)
  if #hits == 0 then
    addText(left, L["Nothing in the book about that."], 12, S.C.dim)
    return L["Search the book"]
  end
  addText(left, string.format(L['%d pages with "%s"'], #hits, query), 12, S.C.dim, 0, 6)
  local leftMax = (left.scroll:GetHeight() or 0) > 0 and left.scroll:GetHeight() or 480
  local target = left
  for _, hit in ipairs(hits) do
    if target == left and left.y + 60 > leftMax then
      target = right
    end
    local p = pages[hit.page]
    local note = p.shelf == "back" and ("  " .. S.H.muted .. L["back shelf"] .. "|r") or ""
    addRow(target, hit.name .. note, function()
      Window.Show({ kind = "page", id = hit.page })
    end, { icon = B.UI.IconTexture("ledger") })
    addText(target, Book.Snippet(textOf(hit.page, p), query, 140), 11, S.C.dim, 18, 6)
  end
  return L["Search the book"]
end

-- Searches the book's text and shows the hits; an empty query goes back to the contents.
function Window.Search(query)
  query = strtrim(query or "")
  if query == "" then
    return Window.Show({ kind = "contents" })
  end
  return Window.Show({ kind = "search", id = query })
end

local function renderBookmarks()
  addText(left, caps(L["Bookmarks"]), 11, S.C.accent, 0, 6)
  local marks = db().char.bookmarks
  if #marks == 0 then
    addText(left, L["No bookmarks yet. Bookmark a page with the button at the top."], 12, S.C.dim)
  end
  for _, id in ipairs(marks) do
    local p = get("page", id)
    local text = p and p.name or id
    if p and p.shelf == "back" then
      text = text .. "  " .. S.H.muted .. L["back shelf"] .. "|r"
    elseif p and p.shelf == "retired" then
      text = text .. "  " .. S.H.muted .. L["retired"] .. "|r"
    elseif not p then
      text = text .. "  " .. S.H.muted .. L["not in this book"] .. "|r"
    end
    addRow(left, text, function()
      Window.Show({ kind = "page", id = id })
    end, { icon = B.UI.IconTexture("ledger") })
  end
  addText(right, caps(L["Your notes"]), 11, S.C.accent, 0, 6)
  local any = false
  local ids = {}
  for id in pairs(db().global.notes) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    any = true
    local p = get("page", id)
    local first = string.match(db().global.notes[id], "^[^\n]*") or ""
    addRow(right, (p and p.name or id) .. "  " .. S.H.muted .. first .. "|r", function()
      Window.Show({ kind = "page", id = id })
    end)
  end
  if not any then
    addText(right, L["No notes yet. Every page has a field for your own."], 12, S.C.dim)
  end
  return L["Bookmarks"]
end

-- ---------------------------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------------------------

local function updateBar()
  if not bar then
    return
  end
  local unread = Book.Unread(Window.News(), db().global.seen, db().global.seenToday)
  bar.news.label:SetText(unread > 0 and string.format(L["What's new (%d)"], unread) or L["What's new"])
  local isPage = current.kind == "page" and get("page", current.id) ~= nil
  local on = isPage and Book.IsBookmarked(db().char.bookmarks, current.id)
  bar.mark.label:SetText(on and L["Bookmarked"] or L["Bookmark"])
  local c = on and S.C.accent or S.C.text
  bar.mark.label:SetTextColor(c[1], c[2], c[3])
  bar.mark:SetEnabledFlat(isPage)
  local order = Window.Order()
  local at
  for i, e in ipairs(order) do
    if same(e, current) then
      at = i
    end
  end
  folio.back:SetEnabledFlat(at ~= nil and at > 1 or current.kind ~= "title")
  folio.next:SetEnabledFlat(at == nil or at < #order)
  folio.label:SetText(at and string.format(L["- %d of %d -"], at, #order) or "")
end

function Window.Render()
  if not (win and win:IsShown()) then
    return
  end
  begin(left)
  begin(right)
  local title
  if current.kind == "title" then
    title = renderTitle()
  elseif current.kind == "contents" then
    title = renderContents()
  elseif current.kind == "index" then
    title = renderIndex()
  elseif current.kind == "bookmarks" then
    title = renderBookmarks()
  elseif current.kind == "mill" then
    title = renderMill(current.id)
  elseif current.kind == "search" then
    title = renderSearch(current.id)
  else
    title = renderPage(current.id)
  end
  finish(left)
  finish(right)
  win:SetTitle(
    L["Bastian's Gold Rumours"]
      .. (title and title ~= L["Bastian's Gold Rumours"] and ("  " .. S.H.muted .. title .. "|r") or "")
  )
  updateBar()
end

function Window.Schedule()
  if ns.mod and win and win:IsShown() then
    ns.mod:Coalesce("render", 0.05, Window.Render)
  end
end

-- Shows an entry ({ kind = "title" | "contents" | "index" | "bookmarks" | "page" | "mill" |
-- "search", id }; a mill's id is its chapter, a search's its query) and keeps
-- it as the character's last place (strategies-design.md section 7: by the page's permanent id).
function Window.Show(entry)
  if not win then
    Window.Build()
  end
  current = entry or { kind = "title" }
  db().char.last = { kind = current.kind, id = current.id }
  if win:IsShown() then
    Window.Render()
  else
    win:Show()
  end
  return true
end

function Window.Current()
  return current
end

-- Turns a page: the reading order; from the index or the bookmarks back to the contents.
function Window.Turn(step)
  local order = Window.Order()
  for i, e in ipairs(order) do
    if same(e, current) then
      local next = order[i + step]
      if next then
        Window.Show(next)
      end
      return
    end
  end
  Window.Show({ kind = "contents" })
end

-- Opens the book where the character left it, else on the title page.
function Window.Open()
  local last = db().char.last
  if type(last) == "table" and last.kind then
    return Window.Show({ kind = last.kind, id = last.id })
  end
  return Window.Show({ kind = "title" })
end

function Window.Toggle()
  if win and win:IsShown() then
    win:Hide()
  else
    Window.Open()
  end
end

function Window.Hide()
  if win then
    win:Hide()
  end
end

function Window.IsShown()
  return win ~= nil and win:IsShown()
end

function Window.ToggleBookmark()
  if current.kind == "page" and get("page", current.id) then
    Book.ToggleBookmark(db().char.bookmarks, current.id)
    Window.Render()
  end
end

local function layoutPages()
  local content = win.content
  local top = -(30 + 6)
  left:ClearAllPoints()
  right:ClearAllPoints()
  local w = (content:GetWidth() or 0) > 0 and content:GetWidth() - 12 or 900
  local half = math.floor((w - SPINE) / 2)
  left:SetPoint("TOPLEFT", content, "TOPLEFT", 6, top)
  left:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 6, 34)
  left:SetWidth(half)
  right:SetPoint("TOPLEFT", left, "TOPRIGHT", SPINE, 0)
  right:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -6, 34)
end

function Window.Build()
  win = B.UI.Window("BastiansStrategiesFrame", {
    title = L["Bastian's Gold Rumours"],
    width = 940,
    height = 640,
    minWidth = 660,
    minHeight = 420,
    db = ns.mod.db.profile.window,
    onShow = function()
      layoutPages()
      Window.Render()
    end,
    onResize = function(_, sizing)
      layoutPages()
      if not sizing then
        Window.Render()
      end
    end,
  })
  local content = win.content
  measure = S.text(content, 12)
  measure:SetWordWrap(true)
  measure:Hide()
  bar = CreateFrame("Frame", nil, content)
  bar:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -6)
  bar:SetPoint("TOPRIGHT", content, "TOPRIGHT", -6, -6)
  bar:SetHeight(26)
  local x = 0
  local function tab(label, tip, onClick, width)
    local b = S.button(bar, label, width, 24)
    b.tip = tip
    b:SetPoint("LEFT", bar, "LEFT", x, 0)
    b:SetScript("OnClick", onClick)
    x = x + width + 4
    return b
  end
  bar.title = tab(L["Title page"], L["The title page and What's new."], function()
    Window.Show({ kind = "title" })
  end, 80)
  bar.contents = tab(
    L["Contents"],
    L["Every chapter and its pages; sealed pages say when they open."],
    function()
      Window.Show({ kind = "contents" })
    end,
    80
  )
  bar.index = tab(L["Index"], L["Every page, place, item and creature in the book, A to Z."], function()
    Window.Show({ kind = "index" })
  end, 64)
  bar.marks = tab(
    L["Bookmarks"],
    L["Your bookmarks (this character) and your notes (every character)."],
    function()
      Window.Show({ kind = "bookmarks" })
    end,
    84
  )
  bar.news = tab(L["What's new"], L["The book is updated often: what changed, newest first."], function()
    Window.Show({ kind = "title" })
  end, 110)
  bar.mark = S.button(bar, L["Bookmark"], 96, 24)
  bar.mark.tip = L["Keeps this page in your bookmarks, also when it moves to the back shelf."]
  bar.mark:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
  bar.mark:SetScript("OnClick", function()
    Window.ToggleBookmark()
  end)
  -- the full-text search: between the tabs and the bookmark button, as wide as the window allows
  bar.search = S.search(bar, L["Search the book"])
  bar.search:SetPoint("LEFT", bar, "LEFT", x + 8, 0)
  bar.search:SetPoint("RIGHT", bar.mark, "LEFT", -8, 0)
  bar.search:SetScript("OnTextChanged", function(self, userInput)
    local text = self:GetText() or ""
    if text == "" then
      self.hint:Show()
      self.clear:Hide()
    else
      self.hint:Hide()
      self.clear:Show()
    end
    if userInput then
      ns.mod:Coalesce("search", 0.3, function()
        Window.Search(self:GetText())
      end)
    end
  end)
  bar.search:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    Window.Search(self:GetText())
  end)
  left = newPage(content)
  right = newPage(content)
  folio = CreateFrame("Frame", nil, content)
  folio:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 6, 6)
  folio:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -6, 6)
  folio:SetHeight(24)
  folio.back = S.button(folio, L["< turn back"], 110, 22)
  folio.back:SetPoint("LEFT", folio, "LEFT", 0, 0)
  folio.back:SetScript("OnClick", function()
    Window.Turn(-1)
  end)
  folio.next = S.button(folio, L["turn the page >"], 120, 22)
  folio.next:SetPoint("RIGHT", folio, "RIGHT", 0, 0)
  folio.next:SetScript("OnClick", function()
    Window.Turn(1)
  end)
  folio.label = S.text(folio, 11, S.C.dim)
  folio.label:SetPoint("CENTER", folio, "CENTER", 0, 0)
  Window.win, Window.bar, Window.left, Window.right, Window.folio = win, bar, left, right, folio
  layoutPages()
end
