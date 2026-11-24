-- The Atlas's window part (book.md "The Atlas with filters", R4.12): band, tokens, card, boards, layers.
local _, ns = ...
local B = Bastians
local S = B.UI.Style
local L = ns.L
local Atlas, Book, Front, Record, Picture = ns.Atlas, ns.Book, ns.Front, ns.Record, ns.Picture

local Map = {}
ns.AtlasMap = Map

local floor, max, min = math.floor, math.max, math.min

-- book-look.md 10.10, in UI units
Map.ASPECT = Book.WORLD.width / Book.WORLD.height -- the world picture's 2 to 1
Map.COLUMN = 0.25 -- a zone's column: this share of the picture
Map.COL_PAD_X, Map.COL_PAD_Y, Map.COL_GAP = 15, 14, 12
Map.CARD_W, Map.CARD_PAD_X, Map.CARD_PAD_Y, Map.CARD_GAP, Map.CARD_OFF = 232, 13, 11, 5, 12
Map.HOVER = 2 -- the ring under the mouse: this much wider
Map.DOT = 7 -- the true spot of a pushed token
Map.STAMP, Map.STAMP_OUT = 12, 4 -- the done stamp's disc at the lower right
Map.NO, Map.NO_OUT = 14, 6 -- a round's stop: its number's plate at the upper left
Map.STEP = 16 -- a trail's step
Map.TRAIL_DOT, Map.TRAIL_PITCH = 3, 9
Map.PIN = 20 -- a hosted pin without a size of its own
Map.LEVEL = 11 -- a gold page's level under its token
Map.UNCONFIRMED = 0.62
Map.SOMEWHERE = 6 -- names listed under "somewhere in the zone"
Map.BOARD_COLS, Map.BOARD_PITCH = 4, 45
Map.SCREEN_MARGIN = 20 -- a window fitted to the map stays this far from the screen's bottom
Map.LEGEND = 12 -- a token's small copy on a chip and before a row
Map.DASHES, Map.DASH, Map.DASH_OUT = 18, 2, 4 -- an unconfirmed token's dotted ring
Map.CARD_MODEL = 104 -- a rare's model on its card
Map.YOU, Map.YOU_TICK = 18, 1 -- the character's arrow, and how often it follows him
Map.FOOT_ROWS = 3 -- the menu's rows a card's foot names
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- as Bastian's minimap's

local view -- the Atlas's frame (Window.atlas)
local filter = Atlas.NewFilter()
local state = { zone = nil, picked = {}, planned = nil }

function Map.Filter()
  return filter
end

function Map.State()
  return state
end

-- A new session of the book: the world, nothing picked (tests; a reader's filter stays).
function Map.Reset()
  filter = Atlas.NewFilter()
  state = { zone = nil, picked = {}, planned = nil }
end

local function context()
  local ctx = Front.Ctx()
  ctx.isOpened = ctx.isOpened or Record.IsOpened
  ctx.mapOf = ctx.mapOf or B.Coords.ToMap
  return ctx
end
Map.Ctx = context

local function rerender()
  ns.Window.Render()
end

local function text(parent, size, token, role, wrap)
  return Front.BookText(parent, size, S.C[token], role, wrap)
end

local function disc(parent, layer, sub)
  local t = parent:CreateTexture(nil, layer, nil, sub)
  t:SetTexture(S.DISC)
  return t
end

-- `tex` around `b`, `out` units wider on every side (negative: inside).
local function around(tex, b, out)
  tex:ClearAllPoints()
  tex:SetPoint("TOPLEFT", b, "TOPLEFT", -out, out)
  tex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", out, -out)
end

-- A token's small copy (the mockup's legend): on a chapter's chip and before a chapter's row.
local function newLegend(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(Map.LEGEND, Map.LEGEND)
  f.outer = disc(f, "ARTWORK", 1)
  f.outer:SetAllPoints(f)
  f.inner = disc(f, "ARTWORK", 2)
  around(f.inner, f, -2)
  f.line = S.fill(f, S.C.folioPaperEdge, "ARTWORK")
  f.border = S.fill(f, S.C.folioSealText, "ARTWORK")
  f.border:SetDrawLayer("ARTWORK", 1)
  around(f.border, f, -1)
  f.mat = S.fill(f, S.C.folioAlbum, "ARTWORK")
  f.mat:SetDrawLayer("ARTWORK", 2)
  around(f.mat, f, -3)
  f.glyph = f:CreateTexture(nil, "ARTWORK", nil, 3)
  f.glyph:SetAllPoints(f)
  return f
end

-- `on`: on a chosen chip's gold the rings are the dark ink.
local function drawLegend(f, chapter, on)
  for _, part in ipairs({ f.outer, f.inner, f.line, f.border, f.mat, f.glyph }) do
    part:Hide()
  end
  local dark = on and S.C.folioGoldInk or nil
  if chapter == "gold" then -- a drawing in a gold ring
    S.tint(f.outer, dark or S.C.folioGold)
    S.tint(f.inner, S.C.folioMatFoot)
    f.outer:Show()
    f.inner:Show()
  elseif chapter == "secrets" then -- the wax seal
    S.tint(f.outer, S.C.folioSeal)
    f.outer:Show()
  elseif chapter == "collections" then -- the album's frame
    S.tint(f.line, S.C.folioPaperEdge)
    S.tint(f.border, S.C.folioSealText)
    S.tint(f.mat, S.C.folioAlbum)
    f.line:Show()
    f.border:Show()
    f.mat:Show()
  elseif chapter == "camp" then -- the flame
    f.glyph:SetTexture(B.UI.IconTexture("flame") or B.UI.IconTexture("campfire"))
    S.tint(f.glyph, S.C.folioSeal, 1)
    f.glyph:Show()
  else -- a rare: a dark face in a bone ring
    S.tint(f.outer, dark or S.C.folioText)
    S.tint(f.inner, S.C.folioBarTop)
    f.outer:Show()
    f.inner:Show()
  end
end

-- An unconfirmed token's ring of dots, `radius` from its middle; nil: none.
local function dashes(b, radius)
  if not radius then
    for _, d in ipairs(b.dashes or {}) do
      d:Hide()
    end
    return
  end
  b.dashes = b.dashes or {}
  for i = 1, Map.DASHES do
    local d = b.dashes[i]
    if not d then
      d = disc(b, "OVERLAY", 1)
      d:SetSize(Map.DASH, Map.DASH)
      b.dashes[i] = d
    end
    local a = (i - 1) / Map.DASHES * 2 * math.pi
    S.tint(d, S.C.folioText)
    d:ClearAllPoints()
    d:SetPoint("CENTER", b, "CENTER", math.cos(a) * radius, math.sin(a) * radius)
    d:Show()
  end
end

local function heightOf(fs, fallback)
  local h = fs:GetStringHeight()
  return (h and h > 0) and h or fallback
end

local function widthOf(fs, words)
  local w = fs:GetStringWidth()
  return (w and w > 0) and w or (#(words or "") * 6)
end

-- ---------------------------------------------------------------------------------------------
-- What other addons lay on the Atlas: map layers through Core (core-contracts 6). The book calls
-- no addon: a layer nobody registered is not there.
-- ---------------------------------------------------------------------------------------------

-- Whether the Atlas draws the layer `id` (a change of it is a reason to ask again).
function Map.Hosts(id)
  for _, own in ipairs(Atlas.LAYERS) do
    if own == id then
      return true
    end
  end
  return false
end

-- The registered layers the Atlas hosts, by id.
function Map.Layers()
  local out = {}
  local want = {}
  for _, id in ipairs(Atlas.LAYERS) do
    want[id] = true
  end
  for _, def in ipairs(B:GetMapLayers()) do
    if want[def.id] then
      out[def.id] = def
    end
  end
  return out
end

-- Asks the hosted layers for the views -> notes = { { pin, fx, fy } } (Notes' pins on the
-- picture), paths = { { { fx, fy }, ... } } (Route's line). A layer that fails is left out.
function Map.Hosted(views, zone, ctx)
  local notes, paths = {}, {}
  local layers = Map.Layers()
  for _, id in ipairs(Atlas.LAYERS) do
    local def = layers[id]
    for _, v in ipairs(def and views or {}) do
      local ok, pins = pcall(def.query, v) -- another addon's code: the one boundary here
      for _, pin in ipairs(ok and type(pins) == "table" and pins or {}) do
        if pin.kind == "path" then
          local line = {}
          for _, pt in ipairs(pin.points or {}) do
            local fx, fy = Atlas.PinSpot({ wx = pt[1], wy = pt[2] }, v, zone, ctx)
            if fx then
              line[#line + 1] = { fx, fy }
            elseif #line > 1 then
              paths[#paths + 1] = line
              line = {}
            else
              line = {}
            end
          end
          if #line > 1 then
            paths[#paths + 1] = line
          end
        elseif Atlas.NOTE_LAYERS[id] then
          local fx, fy = Atlas.PinSpot(pin, v, zone, ctx)
          if fx then
            notes[#notes + 1] = { pin = pin, fx = fx, fy = fy }
          end
        end
      end
    end
  end
  return notes, paths
end

-- ---------------------------------------------------------------------------------------------
-- The card under the mouse, in the tooltip's place
-- ---------------------------------------------------------------------------------------------

-- What a right click offers, in the words of the menu's first rows; "" without a menu.
local function menuWords(ref, ctx)
  local names = {}
  for _, def in ipairs(ref and B:GetActions(ref, ctx) or {}) do
    if type(def.label) == "string" and #names < Map.FOOT_ROWS then
      names[#names + 1] = def.label
    end
  end
  if #names == 0 then
    return ""
  end
  return " " .. string.format(L["Right click: %s."], table.concat(names, ", "))
end

-- The suite's menu for a wonder: its creature; else its own spot as the menu's point (Show on
-- map, Route here, a note here); else its thing. -> ref, ctx
function Map.MenuTarget(e)
  local ctx = { source = "strategies" }
  if e.npc or not e.place then
    return Atlas.RefOf(e), ctx
  end
  local p = e.place
  local c, wx, wy = (view and view.ctx or context()).worldOf(p[1], p[2], p[3])
  if c then
    return "zone:" .. tostring(p[1]), { source = "strategies", point = { c, wx, wy, e.title } }
  end
  return Atlas.RefOf(e), ctx
end

-- What the card of a mark says -> { kind, title, line, foot }.
function Map.CardOf(b)
  if b.pin then -- a hosted pin: the layer's own card
    local own = type(b.pin.card) == "function" and b.pin.card() or nil
    local line = own and own.lines and own.lines[1] and own.lines[1].text or nil
    return {
      kind = b.layerLabel or "",
      title = (own and own.title) or b.pin.label or "",
      line = line,
      foot = own and own.hint or nil,
    }
  end
  if b.disc then
    local d = b.disc
    local by, order = {}, {}
    for _, e in ipairs(d.entries) do
      if not by[e.kind] then
        by[e.kind] = 0
        order[#order + 1] = e.kind
      end
      by[e.kind] = by[e.kind] + 1
    end
    table.sort(order, function(x, y)
      if by[x] ~= by[y] then
        return by[x] > by[y]
      end
      return x < y
    end)
    local parts = {}
    for i, k in ipairs(order) do
      parts[i] = by[k] .. " " .. Front.ValueLabel("kind", k)
    end
    local foot = L["Click: the zone."] .. menuWords("zone:" .. d.zone, { source = "strategies" })
    return {
      kind = L["a zone"] .. "  -  " .. string.format(L["%d wonders"], d.count),
      title = d.name or "",
      line = table.concat(parts, ", "),
      plain = true,
      foot = foot,
    }
  end
  local e = b.entry
  local line = e.hook
  if Atlas.Sealed(e, view.ctx) then
    line = L["Sealed until you open its page."] -- no step of a sealed secret
  end
  if b.form and b.form.done then
    line = (line and (line .. " ") or "") .. L["Done, in Your diary."]
  end
  local foot = L["Click: open the page."] .. menuWords(Map.MenuTarget(e))
  return { kind = ns.Cabinet.Eyebrow(e), title = e.title or "", line = line, foot = foot }
end

local function newCard()
  local c = CreateFrame("Frame", nil, view.picture)
  c:SetFrameLevel((view.picture:GetFrameLevel() or 0) + 30)
  c.edge = S.fill(c, S.C.folioPaperEdge, "BACKGROUND")
  c.paper = S.fill(c, S.C.folioPaper, "BORDER")
  around(c.paper, c, -1)
  c.kind = text(c, 11, "folioInkSoft", "bookCaps", true)
  c.title = text(c, 18, "folioInk", "bookDisplay", true)
  c.line = text(c, 13, "folioInk", "bookItalic", true)
  c.rule = S.fill(c, S.C.folioPaperEdge, "ARTWORK")
  c.mat = S.fill(c, S.C.folioAlbum, "ARTWORK") -- under a rare's model
  S.shadow(c)
  c.foot = text(c, 11, "folioInkSoft", "bookSans", true)
  for _, fs in ipairs({ c.kind, c.title, c.line, c.foot }) do
    fs:SetJustifyH("LEFT")
    fs:SetWidth(Map.CARD_W - 2 * Map.CARD_PAD_X)
  end
  c:EnableMouse(false)
  c:Hide()
  return c
end

-- A rare's model at the card's top (the mockup: without a round portrait on the token "its
-- portrait stands on the card") -> the height it takes, 0 without a model.
local function cardModel(c, b)
  local e = b.entry
  local m = c.model
  c.mat:Hide()
  -- a rare whose token is its portrait needs no model here: the card is the mockup's
  if not (e and e.npc and b.form and b.form.form == "rare") or b.portrait then
    if m then
      m:Hide()
    end
    return 0
  end
  if not m then
    m = B.Compat.NewModel(c)
    if not m then
      return 0
    end
    m:EnableMouse(false)
    c.model = m
  end
  -- its place first, then its creature: a model set on a frame with no size stays empty
  local w = Map.CARD_W - 2 * Map.CARD_PAD_X
  m:ClearAllPoints()
  m:SetPoint("TOPLEFT", c, "TOPLEFT", Map.CARD_PAD_X, -Map.CARD_PAD_Y)
  m:SetSize(w, Map.CARD_MODEL)
  m:Show()
  if m.shownNpc ~= e.npc then
    if not B.Compat.ShowCreature(m, e.npc) then
      m:Hide()
      m.shownNpc = nil
      return 0
    end
    m.shownNpc = e.npc
  end
  if m.SetFacing then
    m:SetFacing(Picture.FACING)
  end
  S.tint(c.mat, S.C.folioAlbum)
  c.mat:ClearAllPoints()
  c.mat:SetPoint("TOPLEFT", c, "TOPLEFT", Map.CARD_PAD_X, -Map.CARD_PAD_Y)
  c.mat:SetSize(w, Map.CARD_MODEL)
  c.mat:Show()
  return Map.CARD_MODEL + Map.CARD_GAP + 2
end

local function showCard(b)
  view.card = view.card or newCard()
  local c = view.card
  S.tint(c.edge, S.C.folioPaperEdge)
  S.tint(c.paper, S.C.folioPaper)
  S.tint(c.rule, S.C.folioPaperEdge)
  S.ink(c.kind, S.C.folioInkSoft)
  S.ink(c.title, S.C.folioInk)
  S.ink(c.line, S.C.folioInk)
  S.ink(c.foot, S.C.folioInkSoft)
  local say = Map.CardOf(b)
  c.said = say
  local y = Map.CARD_PAD_Y
  y = y + cardModel(c, b)
  local function put(fs, words, size, role)
    fs:SetShown(words ~= nil and words ~= "")
    if not fs:IsShown() then
      return
    end
    if role then
      S.SetRole(fs, role)
    end
    fs:SetText(words)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", c, "TOPLEFT", Map.CARD_PAD_X, -y)
    y = y + heightOf(fs, size * 1.3) + Map.CARD_GAP
  end
  put(c.kind, say.kind ~= "" and S.SmallCaps(say.kind) or nil, 11)
  put(c.title, say.title, 18)
  put(c.line, say.line, 13, say.plain and "bookSans" or "bookItalic")
  c.rule:SetShown(say.foot ~= nil)
  if say.foot then
    c.rule:ClearAllPoints()
    c.rule:SetPoint("TOPLEFT", c, "TOPLEFT", Map.CARD_PAD_X, -(y + 2))
    c.rule:SetSize(Map.CARD_W - 2 * Map.CARD_PAD_X, 1)
    y = y + 2 + 6
  end
  put(c.foot, say.foot, 11)
  local h = y - Map.CARD_GAP + Map.CARD_PAD_Y
  c:SetSize(Map.CARD_W, h)
  local reach = b.size / 2 + Map.CARD_OFF
  local x = b.x + reach
  if x + Map.CARD_W > view.pw - Atlas.EDGE then
    x = b.x - reach - Map.CARD_W
  end
  local top = max(Atlas.EDGE, min(view.ph - h - Atlas.EDGE, b.y - h / 2))
  c:ClearAllPoints()
  c:SetPoint("TOPLEFT", view.picture, "TOPLEFT", x, -top)
  c:Show()
end

local function hideCard()
  if view.card then
    view.card:Hide()
  end
end

-- ---------------------------------------------------------------------------------------------
-- Dots: a trail, the route's line
-- ---------------------------------------------------------------------------------------------

local function hideFrom(pool, n)
  for i = n + 1, #pool do
    pool[i]:Hide()
  end
end

-- Dots from x1, y1 to x2, y2 (the picture's units), a pitch apart -> the pool's new count.
local function dotLine(pool, n, x1, y1, x2, y2, color)
  local dx, dy = x2 - x1, y2 - y1
  local len = math.sqrt(dx * dx + dy * dy)
  local steps = floor(len / Map.TRAIL_PITCH)
  for i = 1, steps do
    n = n + 1
    local t = pool[n]
    if not t then
      t = disc(view.picture, "ARTWORK", 3)
      t:SetSize(Map.TRAIL_DOT, Map.TRAIL_DOT)
      pool[n] = t
    end
    S.tint(t, color)
    local k = i / (steps + 1)
    t:ClearAllPoints()
    t:SetPoint("CENTER", view.picture, "TOPLEFT", x1 + dx * k, -(y1 + dy * k))
    t:Show()
  end
  return n
end

-- A chain's trail on the world, while the mouse is on its token.
local function showTrail(b)
  local n = 0
  if b.entry and not state.zone then
    local pts = Atlas.TrailWorld(b.entry, context())
    for i = 2, #pts do
      n = dotLine(
        view.hoverDots,
        n,
        pts[i - 1].fx * view.pw,
        pts[i - 1].fy * view.ph,
        pts[i].fx * view.pw,
        pts[i].fy * view.ph,
        S.C.folioSeal
      )
    end
  end
  hideFrom(view.hoverDots, n)
end

-- ---------------------------------------------------------------------------------------------
-- A mark: a wonder's token, a zone's disc, a hosted pin. One pooled button draws them all.
-- ---------------------------------------------------------------------------------------------

local function paint(b, lit)
  local f = b.form
  local ring = f.ring + (lit and Map.HOVER or 0)
  local color = lit and S.C.bright or b.ringColor
  if f.form == "frame" then -- the album's frame is square: its line lights up
    S.tint(b.line, color)
    around(b.line, b, lit and Map.HOVER or 0)
    return
  end
  S.tint(b.ring, color)
  around(b.ring, b, ring)
  if f.elite then -- a second ring: a dark line, then gold again
    S.tint(b.dark, S.C.folioGoldInk)
    around(b.dark, b, ring + 1.5)
    S.tint(b.outer, color)
    around(b.outer, b, ring + 3)
  end
end

local function onEnter(b)
  paint(b, true)
  showCard(b)
  showTrail(b)
end

local function onLeave(b)
  paint(b, false)
  hideCard()
  hideFrom(view.hoverDots, 0)
end

local function onClick(b, button)
  hideCard()
  if b.pin then -- the layer's own pin: its own click
    if button == "RightButton" then
      if b.pin.ref then
        B.UI.EntityMenu(b.pin.ref, b, { source = "strategies" })
      end
    elseif type(b.pin.onClick) == "function" then
      b.pin.onClick()
    elseif b.pin.ref then
      ns.Window.OpenRef(b.pin.ref)
    end
    return
  end
  if b.disc then
    if button == "RightButton" then
      B.UI.EntityMenu("zone:" .. b.disc.zone, b, { source = "strategies" })
    else
      Map.OpenZone(b.disc.zone)
    end
    return
  end
  local e = b.entry
  if button == "RightButton" then
    local ref, ctx = Map.MenuTarget(e)
    if ref then
      B.UI.EntityMenu(ref, b, ctx)
    end
    return
  end
  if state.zone and not b.onBoard and IsShiftKeyDown and IsShiftKeyDown() and B:GetService("route") then
    state.picked[e.id] = not state.picked[e.id] or nil -- a stop of the round
    state.planned = nil
    rerender()
    return
  end
  ns.Window.Show({ kind = e.page and "page" or "wonder", id = e.id })
end

local function newMark()
  local b = CreateFrame("Button", nil, view.picture)
  b.outer = disc(b, "BACKGROUND", 1)
  b.dark = disc(b, "BACKGROUND", 2)
  b.ring = disc(b, "BACKGROUND", 3)
  b.face = disc(b, "BORDER", 1)
  b.face:SetAllPoints(b)
  b.line = S.fill(b, S.C.folioPaperEdge, "BACKGROUND") -- the album's frame: line, border, mat
  b.border = S.fill(b, S.C.folioSealText, "BORDER")
  around(b.border, b, -1)
  b.mat = S.fill(b, S.C.folioAlbum, "ARTWORK")
  around(b.mat, b, -4)
  b.pic = b:CreateTexture(nil, "ARTWORK", nil, 1)
  b.pic:SetAllPoints(b)
  if b.CreateMaskTexture then
    b.mask = b:CreateMaskTexture()
    b.mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    b.mask:SetAllPoints(b.pic)
    b.pic:AddMaskTexture(b.mask)
  end
  b.glyph = b:CreateTexture(nil, "ARTWORK", nil, 2)
  b.glyph:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.count = text(b, 15, "folioInk", "bookDisplay")
  b.count:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.countBig = text(b, 18, "folioInk", "bookDisplay") -- a zone of twenty and more
  b.countBig:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.plate = S.fill(b, S.C.folioBand, "OVERLAY")
  b.lvl = text(b, Map.LEVEL, "folioText", "bookSans")
  b.lvl:SetDrawLayer("OVERLAY", 2)
  b.stampRim = disc(b, "OVERLAY", 3)
  b.stamp = disc(b, "OVERLAY", 4)
  b.no = CreateFrame("Frame", nil, b)
  b.no.face = S.roundFill(b.no, S.C.folioGold, "pill")
  b.no.text = text(b.no, 11, "folioGoldInk", "bookSans")
  b.no.text:SetPoint("CENTER", b.no, "CENTER", 0, 0)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnEnter", onEnter)
  b:SetScript("OnLeave", onLeave)
  b:SetScript("OnClick", onClick)
  return b
end

local function glyph(b, kind, token, share)
  b.glyph:SetTexture(B.UI.IconTexture(kind) or B.UI.IconTexture("other"))
  local side = floor(b.size * share)
  b.glyph:SetSize(side, side)
  S.tint(b.glyph, S.C[token], 1)
  b.glyph:Show()
end

-- Bastian's crest on a seal (the mockup's; the bar's logo).
local function crest(b, token)
  b.glyph:SetTexture(S.CREST)
  local side = floor(b.size * 0.7)
  b.glyph:SetSize(side, side)
  S.tint(b.glyph, S.C[token], 1)
  b.glyph:Show()
end

-- The entry's drawing cut round; without it (or before a full restart) the glyph on paper.
local function drawing(b, e, fallback)
  b.pic:SetTexture(e.art and Picture.ArtOf(e.id) or nil)
  if b.pic:GetTexture() then
    b.pic:SetTexCoord(0.25, 0.75, 0, 1) -- the middle square of the 2 to 1 drawing
    b.pic:Show()
    return
  end
  S.tint(b.face, S.C.folioPaper)
  glyph(b, fallback, "folioInkSoft", 0.6)
end

-- Draws mark `i` at x, y (the picture's units) as `spec` = { entry, form } | { disc } | { pin }.
local function mark(spec, x, y)
  view.nmarks = view.nmarks + 1
  local b = view.marks[view.nmarks]
  if not b then
    b = newMark()
    view.marks[view.nmarks] = b
  end
  local f = spec.form
  b.entry, b.disc, b.pin, b.form, b.onBoard = spec.entry, spec.disc, spec.pin, f, spec.onBoard
  b.layerLabel = spec.layerLabel
  b.portrait = nil
  b.x, b.y, b.size = x, y, f.size
  b:SetSize(f.size, f.size)
  b:ClearAllPoints()
  b:SetPoint("CENTER", view.picture, "TOPLEFT", x, -y)
  b:SetFrameLevel((view.picture:GetFrameLevel() or 0) + (spec.level or 4))
  b:SetAlpha(f.unconfirmed and Map.UNCONFIRMED or 1)
  dashes(b, f.unconfirmed and (f.size / 2 + Map.DASH_OUT) or nil)
  S.tint(b.border, S.C.folioSealText)
  S.tint(b.mat, S.C.folioAlbum)
  S.tint(b.plate, S.C.folioBand)
  S.ink(b.lvl, S.C.folioText)
  S.ink(b.count, S.C.folioInk)
  S.ink(b.countBig, S.C.folioInk)
  S.tint(b.no.face, S.C.folioGold)
  S.ink(b.no.text, S.C.folioGoldInk)
  local square = f.form == "frame"
  for _, part in ipairs({
    b.outer,
    b.dark,
    b.pic,
    b.glyph,
    b.count,
    b.countBig,
    b.plate,
    b.lvl,
    b.stamp,
    b.stampRim,
  }) do
    part:Hide()
  end
  b.no:Hide()
  b.ring:SetShown(not square)
  b.face:SetShown(not square)
  b.line:SetShown(square)
  b.border:SetShown(square)
  b.mat:SetShown(square)
  b.outer:SetShown(f.elite == true)
  b.dark:SetShown(f.elite == true)
  local e = spec.entry
  if f.form == "story" then
    b.ringColor = f.exact and S.C.folioGold or S.C.folioMuted
    S.tint(b.face, S.C.folioBand)
    drawing(b, e, "ledger")
    local lo, hi = e.levelMin, e.levelMax
    if lo and not spec.onBoard then
      b.lvl:SetText((hi and hi ~= lo) and (lo .. "-" .. hi) or tostring(lo))
      b.lvl:ClearAllPoints()
      b.lvl:SetPoint("TOP", b, "BOTTOM", 0, -(f.ring + 2))
      b.plate:ClearAllPoints()
      b.plate:SetPoint("TOPLEFT", b.lvl, "TOPLEFT", -4, 2)
      b.plate:SetPoint("BOTTOMRIGHT", b.lvl, "BOTTOMRIGHT", 4, -2)
      b.lvl:Show()
      b.plate:Show()
    end
  elseif f.form == "seal" then
    b.ringColor = S.C.folioInk
    S.tint(b.face, S.C.folioSeal)
    crest(b, "folioSealText")
  elseif f.form == "broken" then
    b.ringColor = S.C.folioSeal
    S.tint(b.face, S.C.folioPaper)
    crest(b, "folioSeal")
  elseif f.form == "opened" then
    b.ringColor = S.C.folioSeal
    S.tint(b.face, S.C.folioBand)
    drawing(b, e, "treasure")
  elseif f.form == "camp" then
    b.ringColor = S.C.folioPaperEdge
    S.tint(b.face, S.C.folioPaper)
    glyph(b, B.UI.IconTexture("flame") and "flame" or "campfire", "folioSeal", 0.62)
  elseif f.form == "rare" then
    b.ringColor = f.elite and S.C.folioGold or S.C.folioText
    S.tint(b.face, S.C.folioBand)
    -- its round portrait once the client has answered its display (ADR 0090); until then,
    -- and where the client draws none, the suite's rare pictogram
    -- (ns.Portrait is nil until the full restart after its file came: a new file)
    if e.npc and ns.Portrait and ns.Portrait.Set(b.pic, e.npc) then
      b.portrait = true
      b.pic:SetTexCoord(0, 1, 0, 1)
      b.pic:Show()
    else
      glyph(b, "rare", "folioText", 0.6)
    end
  elseif square then
    b.ringColor = S.C.folioPaperEdge
    glyph(b, Picture.GlyphOf(e), "folioInkSoft", 0.6)
  elseif f.form == "disc" then
    b.ringColor = spec.disc.here and S.C.folioGold or S.C.folioPaperEdge
    S.tint(b.face, S.C.folioPaper)
    local count = spec.disc.big and b.countBig or b.count
    count:SetText(tostring(spec.disc.count))
    count:Show()
  else -- a hosted pin: the layer's own icon on a disc in the pin's colour
    b.ringColor = S.C.folioGoldInk
    S.tint(b.face, spec.pin.color or S.C.folioGold)
    B.UI.PaintIcon(b.glyph, spec.pin.icon or B.UI.IconTexture("note"))
    local side = floor(f.size * 0.62)
    b.glyph:SetSize(side, side)
    b.glyph:Show()
  end
  if f.done then
    b.stampRim:ClearAllPoints()
    b.stampRim:SetSize(Map.STAMP + 2, Map.STAMP + 2)
    b.stampRim:SetPoint(
      "CENTER",
      b,
      "BOTTOMRIGHT",
      Map.STAMP_OUT - Map.STAMP / 2,
      -(Map.STAMP_OUT - Map.STAMP / 2)
    )
    S.tint(b.stampRim, S.C.folioGoldInk)
    b.stamp:ClearAllPoints()
    b.stamp:SetSize(Map.STAMP, Map.STAMP)
    b.stamp:SetPoint("CENTER", b.stampRim, "CENTER", 0, 0)
    S.tint(b.stamp, S.C.folioGold)
    b.stampRim:Show()
    b.stamp:Show()
  end
  if spec.no then
    b.no.text:SetText(tostring(spec.no))
    b.no:SetSize(max(Map.NO, widthOf(b.no.text, tostring(spec.no)) + 6), Map.NO)
    b.no:ClearAllPoints()
    b.no:SetPoint("TOPLEFT", b, "TOPLEFT", -Map.NO_OUT, Map.NO_OUT)
    b.no:SetFrameLevel(b:GetFrameLevel() + 1)
    b.no:Show()
  end
  paint(b, b:IsMouseOver())
  b:Show()
  return b
end

local function spotDot(x, y, color)
  view.ndots = view.ndots + 1
  local dot = view.dots[view.ndots]
  if not dot then
    dot = disc(view.picture, "OVERLAY")
    dot:SetSize(Map.DOT, Map.DOT)
    view.dots[view.ndots] = dot
  end
  S.tint(dot, color)
  dot:ClearAllPoints()
  dot:SetPoint("CENTER", view.picture, "TOPLEFT", x, -y)
  dot:Show()
end

-- A trail's step: a red disc with its number.
local function stepMark(x, y, n)
  view.nsteps = view.nsteps + 1
  local s = view.steps[view.nsteps]
  if not s then
    s = CreateFrame("Frame", nil, view.picture)
    s:SetSize(Map.STEP, Map.STEP)
    s.face = disc(s, "ARTWORK")
    s.face:SetAllPoints(s)
    s.text = text(s, 11, "folioSealText", "bookSans")
    s.text:SetPoint("CENTER", s, "CENTER", 0, 0)
    view.steps[view.nsteps] = s
  end
  S.tint(s.face, S.C.folioSeal)
  s.text:SetText(tostring(n))
  s:SetFrameLevel((view.picture:GetFrameLevel() or 0) + 3)
  s:ClearAllPoints()
  s:SetPoint("CENTER", view.picture, "TOPLEFT", x, -y)
  s:Show()
end

-- ---------------------------------------------------------------------------------------------
-- Words and links on the picture: the boards, a zone's column
-- ---------------------------------------------------------------------------------------------

-- Pools by size: a font string keeps the size it was made with.
local function pooled(pools, size)
  local pool = pools[size]
  if not pool then
    pool = { n = 0 }
    pools[size] = pool
  end
  pool.n = pool.n + 1
  return pool, pool.n
end

local function word(_, size, token, role, wrap)
  local pool, n = pooled(view.words, size)
  local fs = pool[n]
  if not fs then
    fs = text(view.over, size, token, role, wrap)
    pool[n] = fs
  end
  S.SetRole(fs, role)
  S.ink(fs, S.C[token])
  fs:SetWordWrap(wrap == true)
  fs:SetJustifyH("LEFT")
  fs:ClearAllPoints()
  fs:Show()
  return fs
end

-- A link: words with a line under them. `onClick(self, button)`.
local function link(_, words, size, token, click, ref)
  local pool, n = pooled(view.links, size)
  local b = pool[n]
  if not b then
    b = CreateFrame("Button", nil, view.picture)
    b:SetFrameLevel((view.picture:GetFrameLevel() or 0) + 5)
    b.text = text(b, size, token, "bookSans")
    b.text:SetPoint("LEFT", b, "LEFT", 0, 0)
    b.under = S.fill(b, S.C.folioMuted, "ARTWORK")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnEnter", function(self)
      S.ink(self.text, S.C.folioGold)
    end)
    b:SetScript("OnLeave", function(self)
      S.ink(self.text, S.C[self.token])
    end)
    b:SetScript("OnClick", function(self, button)
      if button == "RightButton" then
        if self.ref then
          B.UI.EntityMenu(self.ref, self, { source = "strategies" })
        end
      elseif self.onClick then
        self.onClick(self)
      end
    end)
    pool[n] = b
  end
  b.token, b.onClick, b.ref, b.words = token, click, ref, words
  S.ink(b.text, S.C[token])
  S.tint(b.under, S.C.folioMuted)
  b.text:SetText(words)
  local w = widthOf(b.text, words)
  b:SetSize(w, size + 5)
  b.under:ClearAllPoints()
  b.under:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
  b.under:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  b.under:SetHeight(1)
  b:ClearAllPoints()
  b:Show()
  return b
end

-- A chapter's mark before a row, at x, y of `anchor`.
local function legendAt(anchor, chapter, x, y)
  view.nlegends = view.nlegends + 1
  local f = view.legends[view.nlegends]
  if not f then
    f = newLegend(view.picture)
    f:SetFrameLevel((view.picture:GetFrameLevel() or 0) + 5)
    view.legends[view.nlegends] = f
  end
  drawLegend(f, chapter, false)
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, -y)
  f:Show()
end

local function board(key)
  local f = view.boards[key]
  if not f then
    f = CreateFrame("Frame", nil, view.picture)
    f.ground = S.fill(f, S.C.folioBand, "BACKGROUND")
    f.edges = S.roundEdges(f, S.C.folioRule, "radiusSmall")
    view.boards[key] = f
  end
  S.tint(f.ground, S.C.folioBand)
  S.setEdges(f.edges, S.C.folioRule)
  f:SetFrameLevel((view.picture:GetFrameLevel() or 0) + 2)
  f:ClearAllPoints()
  return f
end

-- The gold pages without a place, left: under the market's head and the trades' head.
local function leftBoard(boards)
  local f = board("left")
  local w = floor(view.pw * Atlas.BOARD_W)
  local x0, y = Atlas.BOARD_PAD, 8
  local shown = false
  local cols = max(1, min(Map.BOARD_COLS, floor((w - 20 + 12) / Map.BOARD_PITCH)))
  for _, part in ipairs({ { "market", L["The market"] }, { "trades", L["Making and gathering"] } }) do
    local list = boards[part[1]]
    if #list > 0 then
      shown = true
      local head = word(f, 11, "folioMuted", "bookCaps")
      head:SetText(S.SmallCaps(part[2]))
      head:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -y)
      y = y + 11 + 8
      local size = Atlas.SIZE.board
      for i, e in ipairs(list) do
        local col, row = (i - 1) % cols, floor((i - 1) / cols)
        local form = { form = "story", size = size, ring = Atlas.RING_DEFAULT, exact = false }
        mark(
          { entry = e, form = form, onBoard = true, level = 6 },
          x0 + 10 + size / 2 + col * Map.BOARD_PITCH,
          Atlas.BOARD_PAD + y + size / 2 + row * Map.BOARD_PITCH
        )
      end
      y = y + (floor((#list - 1) / cols) + 1) * Map.BOARD_PITCH
    end
  end
  f:SetShown(shown)
  f:SetPoint("TOPLEFT", view.picture, "TOPLEFT", x0, -Atlas.BOARD_PAD)
  f:SetSize(w, y + 2)
end

-- What has no place, right: a row per chapter with its count; a row opens the shelf.
local function rightBoard(off)
  local f = board("right")
  local w = floor(view.pw * Atlas.BOARD_W)
  local y, rows = 8, 0
  local head = word(f, 11, "folioMuted", "bookCaps")
  head:SetText(S.SmallCaps(L["Without a place"]))
  head:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -y)
  y = y + 11 + 8
  for _, id in ipairs(Atlas.CHAPTERS) do
    local n = off[id]
    if n then
      rows = rows + 1
      local row = link(f, Front.ChapterName(id), 13, "folioText", function()
        ns.Window.Show({ kind = "shelf", id = id })
      end)
      legendAt(f, id, 10, y + 2)
      row:SetPoint("TOPLEFT", f, "TOPLEFT", 10 + Map.LEGEND + 7, -y)
      local count = word(f, 13, "folioMuted", "bookSans")
      count:SetText(tostring(n))
      count:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -y)
      y = y + 13 + 8
    end
  end
  local note = word(f, 11, "folioMuted", "bookItalic", true)
  note:SetWidth(w - 20)
  note:SetText(L["They have no spot. A row opens its shelf."])
  note:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -y)
  y = y + heightOf(note, 28) + 8
  f:SetShown(rows > 0)
  if rows == 0 then
    head:Hide()
    note:Hide()
  end
  f:SetPoint("TOPRIGHT", view.picture, "TOPRIGHT", -Atlas.BOARD_PAD, -Atlas.BOARD_PAD)
  f:SetSize(w, y)
end

-- ---------------------------------------------------------------------------------------------
-- The band: the chapters (the legend too), a chapter's kinds, level, unconfirmed, the notes'
-- layer; right Near me and Hide done
-- ---------------------------------------------------------------------------------------------

local function pill(spec)
  view.npills = view.npills + 1
  local p = view.pills[view.npills]
  if not p then
    p = S.pill(view.band.frame, { small = true })
    S.SetRole(p.label, "bookSans")
    view.pills[view.npills] = p
  end
  p.spec = spec
  p.tip = spec.tip
  S.Draw(p)
  if spec.mark then -- the pill kept its tile's room: the token's small copy stands in it
    p.mark = p.mark or newLegend(p)
    p.tile:Hide()
    drawLegend(p.mark, spec.mark, spec.on)
    p.mark:ClearAllPoints()
    p.mark:SetPoint("CENTER", p.tile, "CENTER", 0, 0)
    p.mark:Show()
  elseif p.mark then
    p.mark:Hide()
  end
  p:Show()
  return p
end

local function placed(spec)
  local p = pill(spec)
  view.band:Place(p, p:GetWidth(), p:GetHeight())
  return p
end

local function renderBand(width, ctx, entries, notes)
  local band = view.band
  local counts = Atlas.Counts(entries, filter, ctx)
  view.counts = counts
  view.npills = 0
  band:Begin(width)
  -- right first, so the row's other parts end before it
  local hide = view.hide
  if not hide then
    hide = Front.NewSwitch(band.frame)
    view.hide = hide
  end
  hide.tip = L["What you did leaves the map. Your diary keeps it."]
  hide:SetScript("OnClick", function()
    filter.showDone = not filter.showDone
    rerender()
  end)
  band:Group(L["show"], true)
  local done = view.done
  if counts.done > 0 then
    if not done then
      done = Front.NewLink(band.frame)
      view.done = done
    end
    done:SetScript("OnClick", function()
      ns.Window.Show({ kind = "record" })
    end)
    local w = done:Set(string.format(L["%d done, in Your diary"], counts.done))
    band:PlaceRight(done, w, done:GetHeight())
    done:Show()
  elseif done then
    done:Hide()
  end
  local hw = hide:Set(not filter.showDone, L["Hide done"])
  band:PlaceRight(hide, hw, hide:GetHeight())
  local here = ctx.here and ctx.here.map
  if here then
    local near = pill({
      label = L["Near me"],
      gold = true,
      on = state.zone == here,
      tip = L["The zone you stand in, on its own map."],
      onClick = function()
        if state.zone == here then
          Map.OpenWorld()
        else
          Map.OpenZone(here)
        end
      end,
    })
    band:PlaceRight(near, near:GetWidth(), near:GetHeight())
  end
  for _, id in ipairs(Atlas.CHAPTERS) do
    placed({
      kind = Picture.CHAPTER_GLYPH[id],
      mark = id,
      label = Front.ChapterName(id),
      count = counts.chapters[id] or 0,
      on = filter.chapters[id] == true,
      onClick = function()
        filter.chapters[id] = not filter.chapters[id] or nil
        filter.kinds = {}
        rerender()
      end,
    })
  end
  local one = Atlas.OneChapter(filter)
  local kinds = {}
  for k in pairs(counts.kinds) do
    kinds[#kinds + 1] = k
  end
  table.sort(kinds)
  if one and #kinds > 1 then
    band:Group(L["kind"])
    for _, k in ipairs(kinds) do
      placed({
        label = Front.ValueLabel("kind", k),
        count = counts.kinds[k],
        on = filter.kinds[k] == true,
        onClick = function()
          filter.kinds[k] = not filter.kinds[k] or nil
          rerender()
        end,
      })
    end
  end
  band:Group(L["level"])
  placed({
    label = L["any"],
    on = not filter.mine,
    onClick = function()
      filter.mine = false
      rerender()
    end,
  })
  local lo, hi = ns.Shelf.MyLevel(ctx.level)
  if lo then
    placed({
      label = string.format(L["my level (%s)"], string.format(L["%d to %d"], lo, hi)),
      gold = true,
      on = filter.mine,
      onClick = function()
        filter.mine = not filter.mine
        rerender()
      end,
    })
  end
  if counts.unconfirmed > 0 or filter.unconfirmed then
    band:Separator()
    placed({
      label = L["unconfirmed"],
      count = counts.unconfirmed,
      on = filter.unconfirmed or nil,
      dashed = not filter.unconfirmed or nil,
      tip = L["In the game's files, and nobody has reported it in Forever yet. It may not be there."],
      onClick = function()
        filter.unconfirmed = not filter.unconfirmed
        rerender()
      end,
    })
  end
  -- another addon's layer: only while the view holds one of its pins
  if #notes > 0 then
    band:Separator()
    placed({
      kind = "note",
      label = L["My notes"],
      count = #notes,
      on = filter.layers.notes ~= false,
      tip = L["Your notes on spots, and the places others sent you."],
      onClick = function()
        filter.layers.notes = filter.layers.notes == false
        rerender()
      end,
    })
  end
  hideFrom(view.pills, view.npills)
  return band:End()
end

-- ---------------------------------------------------------------------------------------------
-- The world
-- ---------------------------------------------------------------------------------------------

local function drawNotes(notes, w, h, ox, label)
  if filter.layers.notes == false then
    return
  end
  for _, n in ipairs(notes) do
    local size = n.pin.size or Map.PIN
    mark({
      pin = n.pin,
      layerLabel = label,
      level = 7,
      form = { form = "pin", size = size, ring = Atlas.RING_DEFAULT },
    }, ox + n.fx * w, n.fy * h)
  end
end

local function drawPaths(paths, w, h, ox)
  local n = view.nline
  for _, line in ipairs(paths) do
    for i = 2, #line do
      n = dotLine(
        view.lineDots,
        n,
        ox + line[i - 1][1] * w,
        line[i - 1][2] * h,
        ox + line[i][1] * w,
        line[i][2] * h,
        S.C.folioGold
      )
    end
  end
  view.nline = n
end

local function notesLabel()
  local def = Map.Layers()["notes.spots"]
  return def and def.label or L["My notes"]
end

local function renderWorld(ctx, entries, notes, paths)
  local pw, ph = view.pw, view.ph
  view.column:Hide()
  view.paint:Hide()
  view.world:SetTexture(Picture.ArtOf("world"))
  local drawn = view.world:GetTexture() ~= nil
  view.world:SetShown(drawn)
  view.note:SetText(L["The map appears after a full restart of the game."])
  view.note:SetShown(not drawn) -- a new file: the client sees it after a full restart
  local w = Atlas.World(entries, filter, ctx, pw, ph)
  view.worldShown = w
  for _, t in ipairs(w.tokens) do
    if t.moved then
      spotDot(t.tx * pw, t.ty * ph, t.entry.chapter == "gold" and S.C.folioGold or S.C.folioText)
    end
    mark({ entry = t.entry, form = t.form }, t.x, t.y)
  end
  for _, d in ipairs(w.discs) do
    local big = d.big and Atlas.SIZE.discBig or Atlas.SIZE.disc
    mark({ disc = d, form = { form = "disc", size = big, ring = Atlas.RING_DEFAULT } }, d.x, d.y)
  end
  leftBoard(w.boards)
  rightBoard(w.off)
  drawNotes(notes, pw, ph, 0, notesLabel())
  drawPaths(paths, pw, ph, 0)
  Map.PlaceYou(ctx.here, ctx)
  view.count:SetText(string.format(L["%d on the map, %d without a place"], w.shown, w.offTotal))
  -- the mill from the map: the first chapter with rumours
  view.mill.chapter = nil
  for _, entry in ipairs(ns.Window.Order()) do
    if entry.kind == "mill" and not view.mill.chapter then
      view.mill.chapter = entry.id
    end
  end
  view.mill:SetShown(view.mill.chapter ~= nil)
end

-- ---------------------------------------------------------------------------------------------
-- A zone: a column of a quarter, the painting on three
-- ---------------------------------------------------------------------------------------------

-- The character's arrow at his place on the picture shown, turned the way he faces; hidden
-- where he is not on it.
function Map.PlaceYou(here, ctx)
  local x, y
  if here and here.continent and here.wx and view.pw then
    if state.zone then
      local zx, zy = ctx.mapOf(here.continent, here.wx, here.wy, state.zone)
      if zx and zx >= 0 and zx <= 1 and zy >= 0 and zy <= 1 then
        local colW = floor(view.pw * Map.COLUMN)
        x, y = colW + zx * (view.pw - colW), zy * view.ph
      end
    else
      local fx, fy = Book.WorldSpot(here.continent, here.wx, here.wy)
      if fx then
        x, y = fx * view.pw, fy * view.ph
      end
    end
  end
  view.you:SetShown(x ~= nil)
  if not x then
    return
  end
  S.tint(view.you.rim, S.C.folioGoldInk)
  S.tint(view.you.face, S.C.folioGold)
  -- the arrow's picture points east; north is a quarter turn, then the way he faces
  local turn = math.pi / 2 + (GetPlayerFacing and GetPlayerFacing() or 0)
  view.you.rim:SetRotation(turn)
  view.you.face:SetRotation(turn)
  view.you.x, view.you.y = x, y
  view.you:ClearAllPoints()
  view.you:SetPoint("CENTER", view.picture, "TOPLEFT", x, -y)
end

-- The client answered a creature's display: its tokens on the picture turn into the portrait,
-- without a new layout.
function Map.PortraitKnown(npcID)
  for _, b in ipairs(view and view.marks or {}) do
    if b:IsShown() and b.entry and b.entry.npc == npcID and b.form and b.form.form == "rare" then
      if not b.portrait and ns.Portrait and ns.Portrait.Set(b.pic, npcID) then
        b.portrait = true
        b.glyph:Hide()
        b.pic:SetTexCoord(0, 1, 0, 1)
        b.pic:Show()
      end
    end
  end
end

if ns.Portrait then
  ns.Portrait.OnKnown = Map.PortraitKnown
end

function Map.OpenZone(zone)
  state.zone = tonumber(zone)
  state.picked, state.planned = {}, nil
  rerender()
end

function Map.OpenWorld()
  state.zone = nil
  state.picked, state.planned = {}, nil
  rerender()
end

-- The shelf of everything, as a list, with the zone chosen.
function Map.OpenList(zone, ctx)
  local f = Front.Filter("all")
  local info = ctx.zoneOf and ctx.zoneOf(zone)
  f.continent, f.zone = info and info.continent or nil, zone
  Front.SetView("all", "list")
  ns.Window.Show({ kind = "shelf", id = "all" })
end

-- Hands the round to the route service (route.md "Several stops"). -> true when asked.
function Map.PlanRound()
  local route = B:GetService("route")
  local z = view and view.zoneShown
  if not (route and route.Tour and z and state.zone) then
    return false
  end
  local ctx = context()
  local stops = Atlas.Stops(view.round or {}, state.zone, ctx)
  if #stops == 0 then
    return false
  end
  local info = ctx.zoneOf and ctx.zoneOf(state.zone)
  local ok = route:Tour(stops, string.format(L["%s: a round"], info and info.name or L["a zone"])) ~= false
  if ok then
    state.planned = state.zone
    rerender()
  end
  return ok
end

local function renderColumn(ctx, z, round, colW)
  local col = view.column
  col:Show()
  col:ClearAllPoints()
  col:SetPoint("TOPLEFT", view.picture, "TOPLEFT", 0, 0)
  col:SetSize(colW, view.ph)
  S.tint(col.ground, S.C.folioBand)
  S.tint(col.rule, S.C.folioRule)
  local zone = state.zone
  local info = ctx.zoneOf and ctx.zoneOf(zone)
  local name = info and info.name or tostring(zone)
  local x, y = Map.COL_PAD_X, Map.COL_PAD_Y
  local room = colW - 2 * Map.COL_PAD_X
  local function down(frame, h, gap)
    frame:SetPoint("TOPLEFT", col, "TOPLEFT", x, -y)
    y = y + h + (gap or Map.COL_GAP)
  end
  down(link(col, "< " .. L["The world"], 13, "folioGold", Map.OpenWorld), 18)
  local over = {}
  if ctx.here and ctx.here.map == zone then
    over[1] = L["you are here"]
  end
  local continent = info and info.continent and B.Coords.ContinentName(info.continent)
  if continent then
    over[#over + 1] = continent
  end
  if #over > 0 then
    local hereLine = word(col, 11, "folioMuted", "bookCaps")
    hereLine:SetText(S.SmallCaps(table.concat(over, "  -  ")))
    down(hereLine, 11, 4)
  end
  -- the zone's name: the book's link (the Browser's zone page where the Browser is)
  local title = link(col, name, 27, "folioText", function()
    ns.Window.OpenRef("zone:" .. zone)
  end, "zone:" .. zone)
  S.SetRole(title.text, "bookDisplay")
  title:SetSize(min(room, widthOf(title.text, name)), 32)
  down(title, 32)
  local total = word(col, 11, "folioMuted", "bookCaps")
  total:SetText(S.SmallCaps(string.format(L["%d wonders with this filter"], z.total)))
  down(total, 11, 8)
  for _, id in ipairs(Atlas.CHAPTERS) do
    if z.counts[id] then
      local row = word(col, 13, "folioText", "bookSans")
      row:SetText(Front.ChapterName(id))
      legendAt(col, id, x, y + 1)
      row:SetPoint("TOPLEFT", col, "TOPLEFT", x + Map.LEGEND + 7, -y)
      local n = word(col, 13, "folioMuted", "bookSans")
      n:SetText(tostring(z.counts[id]))
      n:SetPoint("TOPRIGHT", col, "TOPRIGHT", -Map.COL_PAD_X, -y)
      y = y + 13 + 7
    end
  end
  y = y + Map.COL_GAP - 7
  if z.total > 0 then
    down(
      link(col, L["Open them as a list"], 13, "folioText", function()
        Map.OpenList(zone, ctx)
      end),
      18
    )
  end
  if #z.somewhere > 0 then
    local head = word(col, 11, "folioMuted", "bookCaps")
    head:SetText(S.SmallCaps(L["somewhere in the zone"]))
    down(head, 11, 6)
    for i = 1, min(#z.somewhere, Map.SOMEWHERE) do
      local e = z.somewhere[i]
      down(
        link(col, e.title or tostring(e.id), 13, "folioText", function()
          ns.Window.Show({ kind = e.page and "page" or "wonder", id = e.id })
        end, Atlas.RefOf(e)),
        18,
        3
      )
    end
    if #z.somewhere > Map.SOMEWHERE then
      local more = word(col, 13, "folioMuted", "bookSans")
      more:SetText(string.format(L["and %d more"], #z.somewhere - Map.SOMEWHERE))
      down(more, 13, 3)
    end
    local why = word(col, 13, "folioMuted", "bookItalic", true)
    why:SetWidth(room)
    why:SetText(L["They name the zone and no spot, so they get none."])
    down(why, heightOf(why, 34))
  end
  -- a round, only with the route service
  local plan, forget = view.plan, view.forget
  plan:Hide()
  forget:Hide()
  if B:GetService("route") and #round > 0 then
    local head = word(col, 11, "folioMuted", "bookCaps")
    head:SetText(S.SmallCaps(L["a round"]))
    down(head, 11, 8)
    local picked = next(state.picked) ~= nil
    local say
    if state.planned == zone then
      say = string.format(L["Route has the round: %d stops."], #round)
    else
      plan:ClearAllPoints()
      down(plan, plan:GetHeight(), 8)
      plan:Show()
      if picked then
        say = string.format(L["Through your %d stops, the nearest first."], #round)
      elseif #z.tokens > Atlas.ROUND_MAX then
        say = string.format(
          L["Through the %d nearest of the %d shown: a round holds no more."],
          #round,
          #z.tokens
        )
      else
        say = string.format(L["Through the %d shown, the nearest first."], #round)
      end
      say = say .. " " .. L["Shift and a click picks single stops."]
    end
    local line = word(col, 13, "folioMuted", "bookItalic", true)
    line:SetWidth(room)
    line:SetText(say)
    down(line, heightOf(line, 34), 8)
    if picked and state.planned ~= zone then
      forget:ClearAllPoints()
      down(forget, forget:GetHeight())
      forget:Show()
    end
  end
end

local function renderZone(ctx, entries, notes, paths)
  local pw, ph = view.pw, view.ph
  local zone = state.zone
  local colW = floor(pw * Map.COLUMN)
  local zw, zh = pw - colW, ph
  view.world:Hide()
  view.mill:Hide()
  for _, f in pairs(view.boards) do
    f:Hide()
  end
  view.paint:Show()
  view.paint:ClearAllPoints()
  view.paint:SetPoint("TOPLEFT", view.picture, "TOPLEFT", colW, 0)
  view.paint:SetSize(zw, zh)
  local drawn = B.UI.Scenery.DrawBox(view.paint, view.paintPool, zone, 0, 0, 1, 1, zw, zh, 1, true)
  view.note:SetText(L["This zone has no painting in the client."])
  view.note:SetShown(not drawn)
  Map.PlaceYou(ctx.here, ctx)
  local z = Atlas.Zone(entries, zone, filter, ctx, zw, zh)
  view.zoneShown = z
  -- a round's stops: numbered once stops are picked or the round is planned
  local from
  local here = ctx.here
  if here and here.continent and here.wx then
    local hx, hy = ctx.mapOf(here.continent, here.wx, here.wy, zone)
    if hx and hx >= 0 and hx <= 1 and hy >= 0 and hy <= 1 then
      from = { x = hx, y = hy }
    end
  end
  local round = B:GetService("route") and Atlas.Round(z.tokens, state.picked, from) or {}
  view.round = round
  local number = {}
  if next(state.picked) ~= nil or state.planned == zone then
    for i, t in ipairs(round) do
      number[t.entry.id] = i
    end
  end
  local before = {}
  for _, s in ipairs(z.steps) do
    local last = before[s.entry]
    if last then
      view.nline = dotLine(view.lineDots, view.nline, colW + last.x, last.y, colW + s.x, s.y, S.C.folioSeal)
    end
    before[s.entry] = s
    stepMark(colW + s.x, s.y, s.n)
  end
  for _, t in ipairs(z.tokens) do
    if t.moved then
      spotDot(colW + t.tx * zw, t.ty * zh, t.entry.chapter == "gold" and S.C.folioGold or S.C.folioText)
    end
    mark({ entry = t.entry, form = t.form, no = number[t.entry.id] }, colW + t.x, t.y)
  end
  drawNotes(notes, zw, zh, colW, notesLabel())
  drawPaths(paths, zw, zh, colW)
  view.count:SetText(string.format(L["%d wonders with this filter"], z.total))
  renderColumn(ctx, z, round, colW)
end

-- ---------------------------------------------------------------------------------------------
-- The view
-- ---------------------------------------------------------------------------------------------

-- The picture into the room: while the grip is held it scales as one piece (one SetScale a size
-- event); when the size settles, Render lays it out anew with the tokens at their own size.
local function fit()
  if not (view and view.pw) then
    return
  end
  local w, h = view:GetWidth() or 0, (view:GetHeight() or 0) - (view.bandH or 0)
  if w < 1 or h < 1 then
    return
  end
  local k = min(w, h * Map.ASPECT) / view.pw
  if math.abs((view.picture:GetScale() or 1) - k) > 0.0005 then
    view.picture:SetScale(k)
  end
end

function Map.Build(content)
  view = CreateFrame("Frame", nil, content)
  view.ground = S.fill(view, S.C.panel, "BACKGROUND")
  view.band = B.UI.Band(view, { ground = false })
  view.band.frame:SetPoint("TOPLEFT", view, "TOPLEFT", 0, 0)
  view.band.frame:SetPoint("TOPRIGHT", view, "TOPRIGHT", 0, 0)
  view.bandGround = S.fill(view.band.frame, S.C.panel, "BACKGROUND")
  view.bandRule = S.fill(view.band.frame, S.C.line, "BORDER")
  view.bandRule:ClearAllPoints()
  view.bandRule:SetPoint("BOTTOMLEFT", view.band.frame, "BOTTOMLEFT", 0, 0)
  view.bandRule:SetPoint("BOTTOMRIGHT", view.band.frame, "BOTTOMRIGHT", 0, 0)
  view.bandRule:SetHeight(1)
  view.room = CreateFrame("Frame", nil, view)
  view.room:SetPoint("BOTTOMLEFT", view, "BOTTOMLEFT", 0, 0)
  view.room:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", 0, 0)
  view.picture = CreateFrame("Frame", nil, view.room)
  view.picture:SetPoint("CENTER", view.room, "CENTER", 0, 0)
  if view.picture.SetClipsChildren then
    view.picture:SetClipsChildren(true)
  end
  view.world = view.picture:CreateTexture(nil, "BORDER")
  view.world:SetAllPoints(view.picture)
  view.paint = CreateFrame("Frame", nil, view.picture)
  view.paintPool = {}
  view.column = CreateFrame("Frame", nil, view.picture)
  view.column.ground = S.fill(view.column, S.C.folioBand, "BACKGROUND")
  view.column.rule = S.fill(view.column, S.C.folioRule, "BORDER")
  view.column.rule:ClearAllPoints()
  view.column.rule:SetPoint("TOPRIGHT", view.column, "TOPRIGHT", 0, 0)
  view.column.rule:SetPoint("BOTTOMRIGHT", view.column, "BOTTOMRIGHT", 0, 0)
  view.column.rule:SetWidth(1)
  view.column:SetFrameLevel((view.picture:GetFrameLevel() or 0) + 2)
  view.note = S.text(view.picture, 12, S.C.dim)
  view.note:SetPoint("BOTTOM", view.picture, "BOTTOM", 0, 8)
  view.you = CreateFrame("Frame", nil, view.picture) -- the character: the mockup's arrow
  view.you:SetSize(Map.YOU, Map.YOU)
  view.you:SetFrameLevel((view.picture:GetFrameLevel() or 0) + 8)
  view.you.rim = view.you:CreateTexture(nil, "OVERLAY", nil, 1)
  view.you.rim:SetTexture(S.ARROW)
  view.you.rim:SetAllPoints(view.you)
  view.you.face = view.you:CreateTexture(nil, "OVERLAY", nil, 2)
  view.you.face:SetTexture(S.ARROW)
  around(view.you.face, view.you, -3)
  view.over = CreateFrame("Frame", nil, view.picture) -- the words on the boards and the column
  view.over:SetAllPoints(view.picture)
  view.over:SetFrameLevel((view.picture:GetFrameLevel() or 0) + 5)
  view.marks, view.dots, view.steps, view.words, view.links = {}, {}, {}, {}, {}
  view.pills, view.boards, view.lineDots, view.hoverDots, view.legends = {}, {}, {}, {}, {}
  view.nmarks, view.ndots, view.nsteps, view.nline, view.nlegends = 0, 0, 0, 0, 0
  -- the count and the mill's button are no part of the land: on the room, never scaled
  view.countPlate = CreateFrame("Frame", nil, view.room)
  view.countPlate:SetFrameLevel((view.picture:GetFrameLevel() or 0) + 12)
  view.countPlate.ground = S.roundFill(view.countPlate, S.C.folioBand, "radiusSmall")
  view.count = text(view.countPlate, 13, "folioText", "bookSans")
  view.count:SetPoint("CENTER", view.countPlate, "CENTER", 0, 0)
  view.mill = S.action(view.room, { icon = "note", label = L["The rumour mill"], boxed = true })
  view.mill:SetFrameLevel((view.picture:GetFrameLevel() or 0) + 12)
  view.mill.tip = L["This is what they're saying on the road. Make of it what you will."]
  view.mill:SetScript("OnClick", function(self)
    ns.Window.Show({ kind = "mill", id = self.chapter })
  end)
  view.plan =
    S.action(view.column, { icon = "route", label = L["Plan a round"], boxed = true, primary = true })
  view.plan:SetScript("OnClick", function()
    Map.PlanRound()
  end)
  view.forget = S.action(view.column, { label = L["Forget my stops"], boxed = true })
  view.forget:SetScript("OnClick", function()
    state.picked, state.planned = {}, nil
    rerender()
  end)
  view:SetScript("OnSizeChanged", fit) -- every size event of the grip, nothing coalesced
  -- the arrow follows the character while the Atlas is shown, and only then
  view:SetScript("OnHide", function()
    if view.ticker then
      view.ticker:Cancel()
      view.ticker = nil
    end
  end)
  view:Hide()
  return view
end

-- The window takes the map's proportions (the window's size "bound to the
-- map"): after the grip is let go and on the way onto the map, the height follows the width so
-- that the picture fills the room under the band, within the screen and the window's smallest
-- height. The place is saved as after a drag.
function Map.FitWindow(win)
  if not (win and view and view:IsShown()) or win.full or win.dock then
    return
  end
  local frame = win.frame
  local fw, fh = frame:GetWidth() or 0, frame:GetHeight() or 0
  local aw, ah = view:GetWidth() or 0, view:GetHeight() or 0
  if fw < 1 or fh < 1 or aw < 1 or ah < 1 then
    return
  end
  local band = view.bandH or 0
  local edgeW, edgeH = fw - aw, fh - ah + band -- what the window and the band add around the map
  local minH = win.opts.minHeight or 0
  local maxH = (UIParent:GetHeight() or 0) - Map.SCREEN_MARGIN
  local h = aw / Map.ASPECT + edgeH
  local w = fw
  if h < minH then
    h = minH
    w = (h - edgeH) * Map.ASPECT + edgeW
  elseif maxH > minH and h > maxH then
    h = maxH
    w = (h - edgeH) * Map.ASPECT + edgeW
  end
  if math.abs(w - fw) > 0.5 or math.abs(h - fh) > 0.5 then
    frame:SetSize(w, h)
    win:SavePlace()
  end
end

-- Lays the Atlas out for its size now -> the page's title.
function Map.Render()
  local vw, vh = view:GetWidth() or 0, view:GetHeight() or 0
  if vw < 1 or vh < 1 then
    return L["Map"]
  end
  local ctx = context()
  view.ctx = ctx -- a card and a menu ask what this render knew
  local entries = Front.Entries()
  -- the book's dark table in a dark look, the theme's own in a light one (as the shelves)
  local dark = S.DarkTable(view)
  local own = dark and S.FolioPalette() or nil
  view.band.frame.palette = own
  S.tint(view.bandGround, dark and S.C.folioBand or S.C.panel)
  S.tint(view.bandRule, dark and S.C.folioRule or S.C.line)
  S.tint(view.ground, dark and S.C.folioTable or S.C.panel)
  if state.zone and not ctx.worldOf(state.zone, 0.5, 0.5) then
    state.zone = nil -- a zone the client does not know (an older pack): back to the world
  end
  -- what the other addons lay on this view (asked now that the view has settled)
  local views = state.zone and { Atlas.ZoneView(state.zone, ctx) } or Atlas.WorldViews()
  local notes, paths = Map.Hosted(views, state.zone, ctx)
  view.notes = notes
  view.bandH = renderBand(vw, ctx, entries, notes)
  view.band.frame:SetHeight(view.bandH)
  local rw, rh = vw, max(1, vh - view.bandH)
  view.room:SetSize(rw, rh)
  local pw = floor(min(rw, rh * Map.ASPECT))
  local ph = floor(pw / Map.ASPECT)
  view.pw, view.ph = pw, ph
  view.picture:SetScale(1)
  view.picture:SetSize(pw, ph)
  view.nmarks, view.ndots, view.nsteps, view.nline, view.nlegends = 0, 0, 0, 0, 0
  for _, pools in ipairs({ view.words, view.links }) do
    for _, pool in pairs(pools) do
      pool.n = 0
    end
  end
  hideCard()
  hideFrom(view.hoverDots, 0)
  if state.zone then
    renderZone(ctx, entries, notes, paths)
  else
    view.zoneShown, view.round = nil, nil
    renderWorld(ctx, entries, notes, paths)
  end
  for i = view.nmarks + 1, #view.marks do
    local b = view.marks[i]
    b:Hide()
    b.entry, b.disc, b.pin = nil, nil, nil
  end
  hideFrom(view.dots, view.ndots)
  hideFrom(view.legends, view.nlegends)
  hideFrom(view.steps, view.nsteps)
  for _, pools in ipairs({ view.words, view.links }) do
    for _, pool in pairs(pools) do
      hideFrom(pool, pool.n)
    end
  end
  hideFrom(view.lineDots, view.nline)
  if not view.ticker and view:IsShown() then
    view.ticker = C_Timer.NewTicker(Map.YOU_TICK, function()
      if view:IsShown() and view.pw then
        local now = context()
        Map.PlaceYou(now.here, now)
      end
    end)
  end
  -- the count at the picture's lower right, the mill at its lower left
  S.tint(view.countPlate.ground, S.C.folioBand)
  S.ink(view.count, S.C.folioText)
  local cw = widthOf(view.count, view.count:GetText()) + 20
  view.countPlate:SetSize(cw, 26)
  view.countPlate:ClearAllPoints()
  view.countPlate:SetPoint("BOTTOMRIGHT", view.picture, "BOTTOMRIGHT", -Atlas.BOARD_PAD, Atlas.BOARD_PAD)
  view.mill:ClearAllPoints()
  view.mill:SetPoint("BOTTOMLEFT", view.picture, "BOTTOMLEFT", Atlas.BOARD_PAD, Atlas.BOARD_PAD)
  return L["Map"]
end

-- What a test and the probe read: the marks shown, { id | zone | pin, x, y, size, form }.
function Map.Marks()
  local out = {}
  for _, b in ipairs(view and view.marks or {}) do
    if b:IsShown() then
      out[#out + 1] = {
        id = b.entry and b.entry.id or nil,
        zone = b.disc and b.disc.zone or nil,
        count = b.disc and b.disc.count or nil,
        pin = b.pin and (b.pin.label or true) or nil,
        x = b.x,
        y = b.y,
        size = b.size,
        form = b.form.form,
        onBoard = b.onBoard,
      }
    end
  end
  return out
end
