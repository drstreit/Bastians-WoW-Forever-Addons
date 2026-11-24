-- UI kit: the band (ADR 0084 decision 2; book-look.md section 5): filters and view choices in a
-- band of their own under the head, on the panel's ground with a rule under it. Its parts flow in
-- groups: a label in small capitals, then chips, a thin line between two groups on one row.
local _, ns = ...
local B = ns.B
local S = ns.Style

local Band = {}
Band.__index = Band
B.UI.BandClass = Band

Band.TOP, Band.SIDE, Band.FOOT = 10, 15, 9 -- the band's padding
Band.ROW_GAP = 8 -- between two rows
Band.GAP = 5 -- between two parts on a row
Band.LABEL_W = 41 -- the label column at a row's start
Band.LABEL_GAP = 8 -- after a label that is wider than its column, and after one inside a row
Band.SEP_H, Band.SEP_PAD = 20, 10 -- the line between two groups, the room each side of it
Band.ROW = 22 -- a row is as high as a chip (S.G.chip)

local floor, max = math.floor, math.max

local function rowHeight()
  return S.G.chip or Band.ROW
end

-- How far under a row's top a part of height `h` sits to stand on the row's middle, in whole
-- units. Rounded, not cut: the game answers a chip's 22 as 22.00002, and cutting put every chip
-- one unit too high (the band's padding 9 for 10, measured in Forever 17.11.2026; R4.14).
function Band.Centre(rowH, h)
  return floor((rowH - h) / 2 + 0.5)
end

-- band = Bastians.UI.Band(parent, opts): `band.frame` (anchor its top corners; the band sets its
-- height), on the panel's ground with a rule under it. opts = { labels = false (no label column:
-- the parts start at the side padding), ground = false (no ground or rule: the host draws its
-- own), frame (the host's own frame as the band's) }.
-- A layout: band:Begin(width); then band:Group(title), band:Place(frame, w, h), band:Separator()
-- as the content needs; band:End() -> the band's height. A part is a child of `band.frame`.
function B.UI.Band(parent, opts)
  opts = opts or {}
  local band = setmetatable({ opts = opts, labels = {}, seps = {}, n = 0, s = 0 }, Band)
  local f = opts.frame
  if not f then
    f = CreateFrame("Frame", nil, parent)
    f:SetHeight(1)
  end
  band.frame = f
  if opts.ground ~= false then
    band.ground = S.fill(f, S.C.panel, "BACKGROUND")
    band.rule = S.fill(f, S.C.line, "BORDER")
    band.rule:ClearAllPoints()
    band.rule:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    band.rule:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    band.rule:SetHeight(1)
  end
  return band
end

-- The column a row's parts start in.
function Band:Left()
  return Band.SIDE + (self.opts.labels == false and 0 or Band.LABEL_W)
end

-- Starts a layout `width` wide. The ground and the rule take the tokens of the palette the frame
-- stands in (a host may give `band.frame.palette` one of its own first: the book's dark table).
function Band:Begin(width)
  if not width or width <= 0 then
    width = self.frame:GetWidth() or 0
  end
  if width <= 0 then
    width = 400
  end
  self.x, self.y = self:Left(), Band.TOP
  self.rowH = rowHeight()
  self.right = width - Band.SIDE
  self.started = nil
  self.n, self.s = 0, 0
  if self.ground then
    S.tint(self.ground, S.Tok(self.frame, "panel"))
    S.tint(self.rule, S.Tok(self.frame, "line"))
  end
  return self
end

-- Ends the layout: hides what the last one used and this one did not -> the band's height.
function Band:End()
  for i = self.n + 1, #self.labels do
    self.labels[i]:Hide()
  end
  for i = self.s + 1, #self.seps do
    self.seps[i]:Hide()
  end
  self.height = (self.started and (self.y + self.rowH) or Band.TOP) + Band.FOOT
  self.frame:SetHeight(self.height)
  return self.height
end

function Band:Height()
  return self.height or 1
end

-- A new row, `h` high (a chip's height by default).
function Band:NewRow(h)
  if self.started then
    self.y = self.y + self.rowH + Band.ROW_GAP
  end
  self.rowH = h or rowHeight()
  self.x = self:Left()
  self.started = true
end

-- A label in small capitals at x on the row's middle -> its width.
function Band:Label(text, x)
  self.n = self.n + 1
  local fs = self.labels[self.n]
  if not fs then
    fs = S.SetRole(S.text(self.frame, 11, S.C.dim), "bookCaps")
    fs:SetWordWrap(false)
    self.labels[self.n] = fs
  end
  S.ink(fs, S.Tok(self.frame, "dim"))
  fs:ClearAllPoints()
  fs:SetPoint("LEFT", self.frame, "TOPLEFT", x, -(self.y + self.rowH / 2))
  fs:SetText(S.SmallCaps(text))
  fs:Show()
  local w = fs:GetStringWidth()
  return (w and w > 0) and w or (#text * 6)
end

-- A thin line between two groups on one row.
function Band:Separator()
  self.s = self.s + 1
  local line = self.seps[self.s]
  if not line then
    line = S.fill(self.frame, S.C.line, "ARTWORK")
    self.seps[self.s] = line
  end
  S.tint(line, S.Tok(self.frame, "line"))
  local x = self.x - Band.GAP + Band.SEP_PAD
  line:ClearAllPoints()
  line:SetSize(1, Band.SEP_H)
  line:SetPoint("LEFT", self.frame, "TOPLEFT", x, -(self.y + self.rowH / 2))
  line:Show()
  self.x = x + 1 + Band.SEP_PAD
end

-- Whether `need` units still fit on the row after a separator.
function Band:Fits(need)
  return self.started and self.x + 2 * Band.SEP_PAD + need <= self.right
end

-- Opens a group: its label in the left column of a new row, or after a thin line on the row of
-- the group before when it fits there. `need` the room its first parts take, so a group never
-- begins at a row's end; `own`: on a row of its own, `h` high.
function Band:Group(text, own, need, h)
  if not self.started and not own and not text then
    self:NewRow(h)
    return
  end
  text = text or ""
  if own or not self:Fits(#text * 6 + Band.LABEL_GAP + (need or 80)) then
    self:NewRow(h)
    if text ~= "" then
      local w = self:Label(text, Band.SIDE)
      -- a long label pushes its parts; without a label column the label stands before them
      self.x = max(self.x, Band.SIDE + w + Band.LABEL_GAP)
    end
    return
  end
  self:Separator()
  if text ~= "" then
    self.x = self.x + self:Label(text, self.x) + Band.LABEL_GAP
  end
end

-- Puts `frame` (w x h) on the row, on a new one when it does not fit.
function Band:Place(frame, w, h)
  if not self.started then
    self:NewRow()
  end
  if self.x + w > self.right and self.x > self:Left() then
    self:NewRow()
  end
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", self.x, -(self.y + Band.Centre(self.rowH, h)))
  self.x = self.x + w + Band.GAP
end

-- Moves the pen so that parts `total` wide end at the row's right end (a view's own controls
-- after its label): on the row while they fit after what stands there, else on a new one; a
-- group wider than a row starts at the row's left and wraps with Place.
function Band:AlignRight(total)
  if not self.started then
    self:NewRow()
  end
  if self.x + total > self.right and self.x > self:Left() then
    self:NewRow()
  end
  self.x = max(self.x, self.right - total)
end

-- A block on a row of its own: `frame`, `h` high, takes the row's width after its label (a
-- list's filter chips in the band of the view's controls); the label stands on the first line
-- -> the block's width.
function Band:Block(frame, h, text)
  self:NewRow()
  local x = self:Left()
  if text and text ~= "" then
    x = max(x, Band.SIDE + self:Label(text, Band.SIDE) + Band.LABEL_GAP)
  end
  local w = max(1, self.right - x)
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -self.y)
  frame:SetWidth(w)
  self.rowH = max(self.rowH, h or 0)
  self.x = self.right
  return w
end

-- Puts `frame` (w x h) at the row's right end (a switch, a view choice); the row's other parts
-- end before it.
function Band:PlaceRight(frame, w, h)
  if not self.started then
    self:NewRow()
  end
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", self.right - w, -(self.y + Band.Centre(self.rowH, h)))
  self.right = self.right - w - Band.GAP
end
