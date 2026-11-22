-- The symbol that stays (courtesy.md "The symbol, the shuffle and the languages", ADR 0088): a small
-- disc with the Courtesy glyph. Under the pointer it grows into Core's ring of four answers (the
-- petals fly out), with a die and the language on the rim; off it for a moment it shrinks back. A
-- moment makes it call (it pulses, the caption says who did what) until it is answered, set aside
-- or over. At rest it runs nothing: its ticker is shown only while it grows, is open, or calls.
local _, ns = ...
local B = Bastians
local S = B.UI.Style
local L = ns.L

local Medallion = {}
ns.Medallion = Medallion

Medallion.SIZE = 28 -- the symbol, px
Medallion.OPEN = 0.25 -- seconds the petals take to fly out
Medallion.HOVER = 0.2 -- seconds on the symbol before it grows (a press in between drags it)
Medallion.LEAVE = 0.4 -- seconds off the ring before it shrinks
Medallion.MARGIN = 12 -- px beyond the petals that still count as on the ring
Medallion.CALL = 60 -- seconds a moment waits by default (the setting `callSeconds`)
Medallion.FROM_TOP = 240 -- the symbol's first place: its centre below the top of the screen
Medallion.WIDTH = 420 -- the caption
Medallion.BREATH = 4 -- how fast it pulses while it calls
Medallion.DIM = 0.45 -- its alpha in a fight

local WEDGES = 4
local RADIUS = 70
local BUBBLE = 32
local RIM = 24 -- the die and the language on the rim
local RIM_AT = 64 -- their offset from the centre, down left and down right

local symbol, glyph, halo -- the small one
local ring, hubGlyph, shuffle, language -- the grown one
local ticker, caption
local opts = {} -- the caller's: Medallion.Attach
local held -- the moment it calls for: { items, text, fire, close, secured, ends }
local current -- what the open ring's petals answer to: { fire, secured }
local born, settled, entered, leftAt -- the grown ring's clock
local hoverAt, pressed -- the pointer on the small symbol
local moving, dragged -- a drag under way; a drag just ended (its release is no click)
local fighting, hiddenByKey = false, false

local function now()
  return (GetTime and GetTime()) or 0
end

local function inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

local function grown()
  return ring ~= nil and ring:IsShown()
end

-- The symbol's centre in UIParent's units: where the player put it, else the top centre.
local function where()
  local x, y
  if opts.place then
    x, y = opts.place()
  end
  if not (tonumber(x) and tonumber(y)) then
    x = (UIParent:GetWidth() or 1920) / 2
    y = (UIParent:GetHeight() or 1080) - Medallion.FROM_TOP
  end
  return x, y
end

local function wake()
  if ticker and not ticker:IsShown() then
    ticker:Show()
  end
end

local function place(share)
  for i, wedge in ipairs(ring.wedges) do
    local dx, dy = B.UI.Ring.Slot(i, WEDGES, RADIUS * share)
    wedge:ClearAllPoints()
    wedge:SetPoint("CENTER", ring.frame, "CENTER", dx, dy)
  end
end

-- Whether the symbol shows now: the setting, or a moment calling; never with the screen cleared.
local function wanted()
  if hiddenByKey or not opts.enabled then
    return false
  end
  return held ~= nil or not opts.shown or opts.shown()
end

-- The caption sits above what shows: the ring when grown, else the symbol.
local function anchorCaption()
  caption:ClearAllPoints()
  if grown() then
    caption:SetPoint("BOTTOM", ring.frame, "TOP", 0, 6)
  else
    caption:SetPoint("BOTTOM", symbol, "TOP", 0, 6)
  end
  local shown = held ~= nil and held.text ~= nil and held.text ~= ""
  caption:SetShown(shown)
  caption.plate:SetShown(shown)
end

-- The symbol as the book's seal: at rest a quiet glyph on the hairline; calling, the gold edge
-- and the gold glyph (the halo pulses in the ticker).
local function look()
  local calling = held ~= nil
  S.tint(glyph, calling and S.C.accent or S.C.dim)
  S.tint(halo, S.C.accent, 0)
  symbol.seal.edge:SetTexture(calling and S.RINGS.L or B.UI.Ring.HAIRLINE)
  S.tint(symbol.seal.edge, S.C.accent, calling and 1 or B.UI.Ring.EDGE)
  symbol:SetAlpha(fighting and Medallion.DIM or 1)
end

-- Shows or hides the symbol as it should be, in its place.
function Medallion.Refresh()
  if not symbol then
    return
  end
  local x, y = where()
  symbol:ClearAllPoints()
  symbol:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
  local show = wanted() and not grown()
  symbol:SetShown(show)
  if not wanted() and grown() then
    ring:Close()
  end
  look()
  anchorCaption()
  if held or grown() then
    wake()
  end
end

local function paintRim()
  if opts.language then
    language:SetValue(opts.language())
  end
  shuffle:SetShown(opts.shuffle ~= nil)
  language:SetShown(opts.switch ~= nil)
end

local function lay(items, answer)
  current = answer
  ring:SetItems(items, "", 0, 0)
  if settled then
    place(1)
  else
    place(0) -- SetItems lays the petals out in full; while flying they start at the centre
  end
  paintRim()
  anchorCaption()
end

-- Grows into the ring: the moment's petals while it calls, else the general lines. Never in a
-- fight (the secure buttons cannot be laid). -> whether it grew.
function Medallion.Grow()
  if not ring or grown() or inCombat() or fighting or not wanted() then
    return false
  end
  local items, answer
  if held then
    items, answer = held.items, { fire = held.fire, secured = held.secured }
  elseif opts.ambient then
    local fire, secured
    items, fire, secured = opts.ambient()
    answer = { fire = fire, secured = secured }
  end
  if not items then
    return false
  end
  hoverAt, leftAt = nil, nil
  born, settled, entered = now(), false, symbol:IsMouseOver() and true or false
  local x, y = where()
  lay(items, answer)
  ring.frame:SetAlpha(1)
  ring:OpenAt(x, y)
  place(0) -- OpenAt lays the petals out in full once more
  symbol:Hide()
  anchorCaption()
  wake()
  return true
end

-- Shrinks back to the symbol; a moment it calls for goes on calling.
function Medallion.Shrink()
  if grown() then
    ring:Close()
  end
end

-- The open ring's petals again: new lines (the die, the language). `items` and `answer` as Grow's.
function Medallion.Relay(items, answer)
  if held and answer == nil then
    held.items = items
    answer = { fire = held.fire, secured = held.secured }
  end
  if grown() and items then
    lay(items, answer)
  end
end

-- Ends the moment it calls for (answered, set aside, over): `close()` of that moment, then the
-- general lines again.
local function endCall()
  local was = held
  held = nil
  if grown() and current and was and current.fire == was.fire then
    ring:Close()
  end
  Medallion.Refresh()
  if was and was.close then
    was.close()
  end
end

local function seconds()
  local s = opts.seconds and tonumber(opts.seconds()) or nil
  return s and s > 0 and s or Medallion.CALL
end

local function cursorDistance()
  local x, y = GetCursorPosition()
  local scale = UIParent:GetEffectiveScale() or 1
  local fs = ring.frame:GetScale() or 1
  local dx, dy = (x / scale - (ring.cx or 0)) / fs, (y / scale - (ring.cy or 0)) / fs
  return math.sqrt(dx * dx + dy * dy)
end

local function tick(self)
  local t = now()
  if held then
    if t >= held.ends then
      endCall()
      return
    end
    local pulse = 0.5 + 0.5 * math.sin(t * Medallion.BREATH)
    if grown() then
      hubGlyph:SetAlpha(0.7 + 0.3 * pulse)
    else
      S.tint(halo, S.C.accent, 0.25 + 0.5 * pulse)
    end
  end
  if grown() then
    if not settled then
      local share = math.min(1, (t - born) / Medallion.OPEN)
      settled = share >= 1
      place(1 - (1 - share) ^ 3)
    end
    local on = moving or cursorDistance() <= RADIUS + BUBBLE + Medallion.MARGIN
    if on then
      entered, leftAt = true, nil
    elseif entered then
      leftAt = leftAt or t
      if t - leftAt >= Medallion.LEAVE then
        ring:Close()
      end
    end
  elseif hoverAt and not pressed and not moving then
    if not symbol:IsMouseOver() then
      hoverAt = nil
    elseif t - hoverAt >= Medallion.HOVER then
      Medallion.Grow()
    end
  end
  if not (held or grown() or hoverAt) then
    self:Hide()
  end
end

local function rimButton(size, x, y)
  local b = CreateFrame("Button", nil, ring.frame)
  b:SetSize(size, size)
  b:SetPoint("CENTER", ring.frame, "CENTER", x, y)
  b.seal = B.UI.Ring.Seal(b, size)
  b.rim = b.seal.edge
  b:SetScript("OnLeave", function(self)
    S.tint(self.rim, S.C.accent, B.UI.Ring.EDGE)
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  return b
end

local function tip(b, text)
  b:SetScript("OnEnter", function(self)
    S.tint(self.rim, S.C.accent, 1)
    if GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      S.TipLine(GameTooltip, type(text) == "function" and text() or text, "tipText")
      GameTooltip:Show()
    end
  end)
end

local function buildRing()
  ring = B.UI.Ring.New("BastiansCourtesyRing", {
    wedges = WEDGES,
    radius = RADIUS,
    inner = 30,
    bubble = BUBBLE,
    escape = false, -- it shrinks when the pointer goes; Escape is the game's
    onFire = function(index, item)
      local fn = current and current.fire
      if fn then
        fn(index, item)
      end
    end,
    onSecure = function(index, item)
      local fn = current and current.secured
      if fn then
        fn(index, item)
      end
    end,
    onHub = function()
      if dragged then
        dragged = false
        return
      end
      -- the centre: a moment is set aside (Not now), the general lines just go
      if held and current and current.fire == held.fire then
        endCall()
      else
        Medallion.Shrink()
      end
    end,
    onHide = function()
      current, entered, leftAt = nil, false, nil
      Medallion.Refresh()
    end,
  })
  ring.frame:EnableMouse(false) -- only the petals, the centre and the rim take clicks
  ring.frame:EnableMouseWheel(false)
  hubGlyph = ring.hub:CreateTexture(nil, "OVERLAY")
  hubGlyph:SetTexture(B.UI.GLYPH_PATHS.app_courtesy)
  hubGlyph:SetSize(38, 38)
  hubGlyph:SetPoint("CENTER")
  S.tint(hubGlyph, S.C.accent)
  -- the open ring moves by its centre
  ring.frame:SetMovable(true)
  ring.frame:SetClampedToScreen(true)
  ring.hub:RegisterForDrag("LeftButton")
  ring.hub:SetScript("OnDragStart", function()
    if inCombat() then
      return
    end
    moving, dragged = true, true
    ring:HideSecure() -- laid by screen place: they come back where the ring stops
    ring.frame:StartMoving()
  end)
  ring.hub:SetScript("OnDragStop", function()
    ring.frame:StopMovingOrSizing()
    moving = false
    local x, y = ring.frame:GetCenter()
    if x and y then
      ring.cx, ring.cy = x, y
      if opts.save then
        opts.save(x, y)
      end
      ring:PlaceSecure()
    end
    Medallion.Refresh()
  end)
  -- the die: three new lines; the language: English or German
  shuffle = rimButton(RIM, -RIM_AT, -RIM_AT)
  local die = shuffle:CreateTexture(nil, "ARTWORK")
  die:SetTexture(B.UI.GLYPH_PATHS.replay)
  die:SetSize(14, 14)
  die:SetPoint("CENTER")
  S.tint(die, S.C.accent)
  tip(shuffle, L["Other lines"])
  shuffle:SetScript("OnClick", function()
    if opts.shuffle and not inCombat() then
      opts.shuffle()
    end
  end)
  -- the language: the book's two-part chip, the chosen one filled
  language = S.segmented(ring.frame, {
    items = opts.languages and opts.languages() or {},
    value = opts.language and opts.language() or nil,
    height = 22,
    pad = 7,
    onChange = function(_, id)
      if opts.switch and not inCombat() then
        opts.switch(id)
      end
      paintRim()
    end,
  })
  language:SetPoint("CENTER", ring.frame, "CENTER", RIM_AT + 6, -RIM_AT)
end

local function build()
  ticker = CreateFrame("Frame", nil, UIParent)
  ticker:SetSize(1, 1)
  ticker:SetPoint("CENTER")
  ticker:Hide()
  ticker:SetScript("OnUpdate", tick)
  -- the caption: the book's italic on the shade, as a picture's words are
  local plate = CreateFrame("Frame", nil, ticker)
  plate.face = S.roundFill(plate, S.C.folioShade, "radiusSmall")
  caption = S.SetRole(S.text(plate, 13, S.C.folioShadeText), "bookItalic")
  caption:SetWordWrap(false)
  caption:SetJustifyH("CENTER")
  plate:SetPoint("TOPLEFT", caption, "TOPLEFT", -10, 4)
  plate:SetPoint("BOTTOMRIGHT", caption, "BOTTOMRIGHT", 10, -4)
  caption.plate = plate
  symbol = CreateFrame("Button", "BastiansCourtesySymbol", UIParent)
  symbol:SetSize(Medallion.SIZE, Medallion.SIZE)
  symbol:SetFrameStrata("MEDIUM")
  symbol:SetMovable(true)
  symbol:SetClampedToScreen(true)
  symbol:RegisterForDrag("LeftButton", "RightButton")
  symbol:RegisterForClicks("LeftButtonUp")
  halo = symbol:CreateTexture(nil, "BACKGROUND", nil, -7) -- over the shadow, under the disc
  halo:SetTexture(S.GLOW)
  halo:SetPoint("CENTER")
  halo:SetSize(Medallion.SIZE * 2, Medallion.SIZE * 2)
  symbol.seal = B.UI.Ring.Seal(symbol, Medallion.SIZE)
  glyph = symbol:CreateTexture(nil, "OVERLAY")
  glyph:SetTexture(B.UI.GLYPH_PATHS.app_courtesy)
  glyph:SetSize(Medallion.SIZE - 8, Medallion.SIZE - 8)
  glyph:SetPoint("CENTER")
  symbol:SetScript("OnEnter", function(self)
    hoverAt = now()
    wake()
    if GameTooltip and not held then
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      S.TipLine(GameTooltip, L["Courtesy"], "tipText")
      S.TipLine(GameTooltip, L["Point at it for a few kind words. Drag it to move it."], "tipDim", true)
      S.TipLine(GameTooltip, L["Open, the ring moves by its centre."], "tipDim", true)
      GameTooltip:Show()
    end
  end)
  symbol:SetScript("OnLeave", function()
    hoverAt = nil
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  symbol:SetScript("OnMouseDown", function()
    pressed = true
  end)
  symbol:SetScript("OnMouseUp", function()
    pressed = false
    hoverAt = now()
    wake()
  end)
  symbol:SetScript("OnClick", function()
    if dragged then
      dragged = false
      return
    end
    Medallion.Grow()
  end)
  symbol:SetScript("OnDragStart", function(self)
    hoverAt, moving, dragged = nil, true, true
    if GameTooltip then
      GameTooltip:Hide()
    end
    self:StartMoving()
  end)
  symbol:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    pressed, moving = false, false
    local x, y = self:GetCenter()
    if opts.save and x and y then
      opts.save(x, y)
    end
    Medallion.Refresh()
  end)
  buildRing()
end

-- Takes the caller's: { enabled, shown() (the setting), place() -> x, y, save(x, y),
-- seconds() (how long a moment waits), ambient() -> items, fire, secured, shuffle(), switch(),
-- language() -> "EN" }.
function Medallion.Attach(o)
  opts = o or {}
  opts.enabled = true
  if not symbol then
    build()
  end
  Medallion.Refresh()
end

function Medallion.Detach()
  if held then
    endCall()
  end
  Medallion.Shrink()
  opts.enabled = false
  Medallion.Refresh()
end

-- A fight: it shrinks and dims; a moment goes on calling and can be answered after it.
function Medallion.Fight(on)
  fighting = on and true or false
  if fighting then
    Medallion.Shrink()
  end
  Medallion.Refresh()
end

-- The clear-screen key: gone with the screen, back with it.
function Medallion.HideByKey(hidden)
  hiddenByKey = hidden and true or false
  Medallion.Refresh()
end

-- Calls for a moment: `items` the kit's four, `text` the caption. `fire(index, item)` on a petal,
-- `close()` when the moment goes, however it goes, `secured(index, item)` after a petal's secure
-- click. A moment that called before is replaced, not dismissed.
function Medallion.Open(items, text, fire, close, secured)
  if not symbol then
    build()
  end
  held = { items = items, text = text, fire = fire, close = close, secured = secured }
  held.ends = now() + seconds()
  caption:SetText(text or "")
  if grown() then
    lay(items, { fire = fire, secured = secured })
  end
  Medallion.Refresh()
end

-- The moment is over (answered or set aside).
function Medallion.Close()
  if held then
    endCall()
  else
    Medallion.Shrink()
  end
end

-- Whether it calls for a moment.
function Medallion.IsShown()
  return held ~= nil
end

function Medallion.IsGrown()
  return grown()
end

-- Whether the open ring holds the moment's petals (not the general lines).
function Medallion.ShowsMoment()
  return grown() and held ~= nil and current ~= nil and current.fire == held.fire
end

function Medallion.IsSymbolShown()
  return symbol ~= nil and symbol:IsShown()
end

-- For the tests: what petal `i` holds (the open ring's, else the moment's), its secure button, the
-- caption, the centre's glyph, a petal, the rim's buttons, the ticker.
function Medallion.Item(i)
  if grown() then
    return ring.items[i]
  end
  return held and held.items[i] or nil
end

function Medallion.Secure(i)
  return ring and ring:Secure(i) or nil
end

function Medallion.Caption()
  return caption and caption:GetText() or nil
end

function Medallion.Symbol()
  return hubGlyph and hubGlyph:GetTexture() or nil
end

function Medallion.Petal(i)
  return ring and ring.wedges[i] or nil
end

function Medallion.Frames()
  return { symbol = symbol, ring = ring, shuffle = shuffle, language = language, ticker = ticker }
end
