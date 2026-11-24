-- Bastian's Book: a wonder's picture (book.md "Pictures"): Bastian's drawing, else the creature's
-- model on the painting of its place, else the painting with the spot marked, else the chapter's
-- plate (the paper, a glyph and, for a title, the title set large). One holder per tile, reused.
local _, ns = ...
local B = Bastians
local S = B.UI.Style
local L = ns.L

local Picture = {}
ns.Picture = Picture

-- The texture of a drawing by its id ("world": the atlas's map): the book's pack names its own
-- art folder, the data service answers it (ADR 0082's crossing, gone with W6; ~~a path into the
-- pack's folder written here~~ until 23.11.2026). nil without the Data addon.
-- A wonder's or a chapter's id names its file with a dash for the colon (`camp:279938` is
-- `camp-279938.blp`, tools/book_art.py), a page's id is its file's name already.
function Picture.ArtOf(id)
  local data = B:GetService("data")
  local folder = data and data.PackArt and data:PackArt("book")
  return folder and (folder .. (string.gsub(tostring(id), ":", "-"))) or nil
end
Picture.DISC = "Interface\\AddOns\\Bastians_Core\\Media\\Disc"
Picture.ART_ASPECT = 2 -- Bastian's drawings ship at 2:1 (tools/book_art.py)
Picture.FOCUS_Y = 0.4 -- a cut drawing keeps a little more of its top: the faces are there
Picture.SPAN = 0.32 -- a painting's cut: this share of the zone's width around the spot
Picture.ZONE_SPAN = 0.7 -- a wonder with only a zone: most of the zone's painting
Picture.PAINT_ALPHA = 0.85
Picture.FACING = 0.6 -- a creature turned three quarters towards the reader

-- The glyph of a plate, by kind, else by chapter (Core's glyph atlas).
Picture.KIND_GLYPH = {
  chain = "treasure",
  unsolved = "treasure",
  camping = "campfire",
  library = "tale",
  ["library book"] = "tale",
  ["camp kit"] = "campfire",
  ["camp item"] = "campfire",
  mount = "route",
  pet = "mob",
  title = "ledger",
  rare = "rare",
  ["rare elite"] = "rare",
}
Picture.CHAPTER_GLYPH = {
  gold = "gold",
  secrets = "treasure",
  collections = "keep",
  camp = "campfire",
  rares = "rare",
}

function Picture.GlyphOf(e)
  return Picture.KIND_GLYPH[e.kind] or Picture.CHAPTER_GLYPH[e.chapter] or "ledger"
end

-- The part of a drawing of `aspect` (width over height) that fills w x h without stretching it:
-- the picture covers the frame and what does not fit is cut, the sides evenly, the height at
-- FOCUS_Y ("stretched to a width it does not support ... show/hide it
-- with resizing"). -> left, right, top, bottom as texture coordinates.
function Picture.Cover(w, h, aspect, focusY)
  aspect = aspect or Picture.ART_ASPECT
  if not (w and h and w > 0 and h > 0) then
    return 0, 1, 0, 1
  end
  local frame = w / h
  if frame > aspect then
    local share = aspect / frame -- a wide frame: the drawing's height is cut
    local top = (1 - share) * (focusY or Picture.FOCUS_Y)
    return 0, 1, top, top + share
  end
  local share = frame / aspect -- a tall frame: its sides are cut
  local left = (1 - share) / 2
  return left, left + share, 0, 1
end

-- `framed`: a thin frame drawn over everything, the model too ("3D
-- image needs a border"); the details page's plate has one, a tile its card's edge.
function Picture.New(parent, framed)
  local f = CreateFrame("Frame", nil, parent)
  if f.SetClipsChildren then
    f:SetClipsChildren(true) -- the painting's tiles and the model stay inside the picture
  end
  if framed then
    f.rim = CreateFrame("Frame", nil, f)
    f.rim:SetAllPoints(f)
    f.rim:SetFrameLevel((f:GetFrameLevel() or 0) + 8) -- above the model
    f.rim.edges = S.roundEdges(f.rim, S.C.cardEdge, "radius")
  end
  f.ground = S.fill(f, S.C.panel, "BACKGROUND")
  f.art = f:CreateTexture(nil, "ARTWORK")
  f.art:SetAllPoints(f)
  f.paint = {} -- the painting's tiles (Scenery's pool)
  f.glyph = f:CreateTexture(nil, "ARTWORK")
  f.glyph:SetPoint("CENTER", f, "CENTER", 0, 0)
  f.label = S.SetRole(S.text(f, 18, S.C.folioGold, "OVERLAY"), "bookDisplay") -- the book's face (ADR 0081)
  f.label:SetPoint("CENTER", f, "CENTER", 0, -4)
  f.label:SetJustifyH("CENTER")
  f.dot = f:CreateTexture(nil, "OVERLAY")
  f.dot:SetTexture(Picture.DISC)
  f.dot:SetSize(10, 10)
  S.tint(f.dot, S.C.gold, 1)
  return f
end

local function hidePaint(f)
  for _, tex in ipairs(f.paint) do
    tex:Hide()
  end
end

local function showModel(f, e, w, h)
  local m = f.model
  if not m then
    m = B.Compat.NewModel(f)
    if not m then
      return false
    end
    m:EnableMouse(false) -- the tile takes the clicks
    f.model = m
  end
  -- its place first, then its creature: a model set on a frame with no size stays empty (the
  -- FacePool's lesson, )
  m:ClearAllPoints()
  m:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  m:SetSize(w, h)
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
  return true
end

-- Draws `e` into the holder at w x h px -> "art" | "model" | "painting" | "plate".
function Picture.Draw(f, e, w, h)
  f:SetSize(w, h)
  f.art:Hide()
  f.glyph:Hide()
  f.label:Hide()
  f.dot:Hide()
  if f.model and not e.npc then
    f.model:Hide()
  end
  if e.art and not e.sim then
    f.art:SetTexture(Picture.ArtOf(e.id))
    if f.art:GetTexture() then
      hidePaint(f)
      if f.model then
        f.model:Hide()
      end
      f.art:SetTexCoord(Picture.Cover(w, h))
      f.art:Show()
      return "art"
    end
  end
  local drew
  local p = e.place
  local span = Picture.SPAN
  if not p and e.zones and e.zones[1] then
    -- only a zone (a vendor's mount, a pet): the zone's painting around its middle, no spot
    p, span = { e.zones[1], 0.5, 0.5 }, Picture.ZONE_SPAN
  end
  if p and p[1] then
    -- the zone whole (R4.5): every area's overlay from the pack, not only what the reader's
    -- character uncovered; the Map keeps what the character explored
    local px, py =
      B.UI.Scenery.DrawCut(f, f.paint, p[1], p[2], p[3], w, h, span, Picture.PAINT_ALPHA, nil, true)
    if px then
      drew = "painting"
      if not e.npc and e.place then
        f.dot:ClearAllPoints()
        f.dot:SetPoint("CENTER", f, "TOPLEFT", px, -py)
        f.dot:Show()
      end
    end
  else
    hidePaint(f)
  end
  if e.npc and showModel(f, e, w, h) then
    drew = "model"
  elseif f.model then
    f.model:Hide()
  end
  if drew then
    return drew
  end
  -- the chapter's plate
  local size = math.floor(math.min(w, h) * 0.42)
  f.glyph:SetTexture(B.UI.IconTexture(Picture.GlyphOf(e)))
  f.glyph:SetSize(size, size)
  S.tint(f.glyph, S.C.gold, e.kind == "title" and 0.25 or 0.7)
  f.glyph:Show()
  if e.kind == "title" then
    f.label:SetWidth(w - 16)
    f.label:SetText(e.title)
    f.label:Show()
  end
  return "plate"
end

-- Lets go of what a hidden tile holds: its model stops drawing.
function Picture.Clear(f)
  if f.model then
    f.model:Hide()
  end
  hidePaint(f)
end

-- ---------------------------------------------------------------------------------------------
-- The stamp on a plate (book.md "Your record becomes the diary", R4.11; book-look.md 10.9): a
-- done wonder wears "found - 17.11" in the seal's red, in a border of 2, padded 4 and 8, on the
-- paper at 70 %, turned 12 degrees, at the plate's top right (16 in, 14 down). The game turns a
-- texture and a text about their middle (forever-api.md, verified 17.11.2026), so the border
-- is four bars, each turned and set on the turned box's edge.
-- ---------------------------------------------------------------------------------------------

Picture.STAMP_IN, Picture.STAMP_DOWN = 16, 14 -- from the plate's top right corner
Picture.STAMP_PAD_X, Picture.STAMP_PAD_Y = 8, 4
Picture.STAMP_EDGE = 2
Picture.STAMP_SIZE = 11
Picture.STAMP_TURN = -math.rad(12) -- clockwise, as the board draws it
Picture.STAMP_PAPER = 0.7

-- `lift`: how far above `parent` the stamp lies (a tile's ribbons lie 9 above it).
function Picture.NewStamp(parent, lift)
  local f = CreateFrame("Frame", nil, parent)
  f:SetFrameLevel((parent:GetFrameLevel() or 0) + (lift or 9))
  f.ground = S.fill(f, S.C.folioPaper, "BACKGROUND")
  f.sides = {}
  for i = 1, 4 do
    f.sides[i] = S.fill(f, S.C.folioSeal, "BORDER")
  end
  f.text = S.SetRole(S.text(f, Picture.STAMP_SIZE, S.C.folioSeal, "OVERLAY"), "bookCaps")
  f.text:SetPoint("CENTER", f, "CENTER", 0, 0)
  f.text:SetWordWrap(false)
  return f
end

-- The stamp's words for a mark { how, at }: what the game found is "found", a mark by hand
-- "done", then the day and the month.
function Picture.StampText(mark)
  local word = mark.how == "found" and L["found"] or L["done"]
  return S.SmallCaps(word) .. " - " .. (date and date("%d.%m", mark.at or 0) or "")
end

-- Writes the stamp for `mark` and lays its parts out -> its width and height before the turn.
function Picture.SetStamp(f, mark)
  local text = Picture.StampText(mark)
  f.text:SetText(text)
  S.ink(f.text, S.C.folioSeal)
  local tw = f.text:GetStringWidth()
  tw = (tw and tw > 0) and tw or (#text * 6)
  local w = math.floor(tw + 2 * Picture.STAMP_PAD_X + 0.5)
  local h = Picture.STAMP_SIZE + 2 * Picture.STAMP_PAD_Y
  f:SetSize(w, h)
  local turn, edge = Picture.STAMP_TURN, Picture.STAMP_EDGE
  local cos, sin = math.cos(turn), math.sin(turn)
  local function lay(tex, x, y, tw2, th2)
    tex:ClearAllPoints()
    tex:SetSize(tw2, th2)
    tex:SetPoint("CENTER", f, "CENTER", x * cos - y * sin, x * sin + y * cos)
    if tex.SetRotation then
      tex:SetRotation(turn)
    end
  end
  S.tint(f.ground, S.C.folioPaper, Picture.STAMP_PAPER)
  lay(f.ground, 0, 0, w, h)
  for _, side in ipairs(f.sides) do
    S.tint(side, S.C.folioSeal, 1)
  end
  lay(f.sides[1], 0, (h - edge) / 2, w, edge)
  lay(f.sides[2], 0, -(h - edge) / 2, w, edge)
  lay(f.sides[3], -(w - edge) / 2, 0, edge, h)
  lay(f.sides[4], (w - edge) / 2, 0, edge, h)
  if f.text.SetRotation then
    f.text:SetRotation(turn)
  end
  f.mark = mark
  return w, h
end

-- A plate's stamp: made at the first done wonder, set at the plate's top right, hidden for a
-- wonder that is not done -> the stamp or nil. `holder` keeps it as `holder.stamp`.
function Picture.Stamp(holder, plate, mark, lift)
  local st = holder.stamp
  if not mark then
    if st then
      st:Hide()
    end
    return nil
  end
  if not st then
    st = Picture.NewStamp(holder, lift)
    holder.stamp = st
  end
  Picture.SetStamp(st, mark)
  st:ClearAllPoints()
  st:SetPoint("TOPRIGHT", plate, "TOPRIGHT", -Picture.STAMP_IN, -Picture.STAMP_DOWN)
  st:Show()
  return st
end
