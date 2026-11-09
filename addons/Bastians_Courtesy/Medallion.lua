-- The ring of four answers (courtesy.md "The ring"): Core's ring kit with the symbol in the centre,
-- petals that fly out, a breathing symbol and a fade at the end. Works only while it is shown.
local _, ns = ...
local B = Bastians
local S = B.UI.Style

local Medallion = {}
ns.Medallion = Medallion

Medallion.SECONDS = 12 -- how long it waits for a click
Medallion.OPEN = 0.25 -- seconds the petals take to fly out
Medallion.FADE = 2 -- the last seconds it fades
Medallion.FROM_TOP = 240 -- the ring's centre, below the top of the screen
Medallion.WIDTH = 420 -- the caption above it
Medallion.BREATH = 2.5 -- how fast the symbol breathes

local WEDGES = 4
local RADIUS = 70

local ring, symbol, caption
local born, closes -- the time it opened and the time it closes
local settled -- the petals have arrived
local onFire, onClose, onSecured -- the caller's, for this opening

local function now()
  return (GetTime and GetTime()) or 0
end

local function place(share)
  for i, wedge in ipairs(ring.wedges) do
    local dx, dy = B.UI.Ring.Slot(i, WEDGES, RADIUS * share)
    wedge:ClearAllPoints()
    wedge:SetPoint("CENTER", ring.frame, "CENTER", dx, dy)
  end
end

local function tick()
  local t = now()
  if not settled then
    local share = math.min(1, (t - born) / Medallion.OPEN)
    settled = share >= 1
    place(1 - (1 - share) ^ 3)
  end
  symbol:SetAlpha(0.72 + 0.28 * math.sin(t * Medallion.BREATH))
  local left = closes - t
  if left <= 0 then
    ring:Close()
  else
    ring.frame:SetAlpha(math.min(1, left / Medallion.FADE))
  end
end

local function build()
  ring = B.UI.Ring.New("BastiansCourtesyRing", {
    wedges = WEDGES,
    radius = RADIUS,
    inner = 30,
    bubble = 32,
    onFire = function(index, item)
      local fn = onFire
      if fn then
        fn(index, item)
      end
    end,
    onSecure = function(index, item)
      local fn = onSecured
      if fn then
        fn(index, item)
      end
    end,
    onHub = function()
      ring:Close()
    end,
    onHide = function()
      local fn = onClose
      onClose, onFire = nil, nil
      if fn then
        fn()
      end
    end,
  })
  ring.frame:EnableMouse(false) -- only the petals and the centre take clicks
  ring.frame:EnableMouseWheel(false)
  ring.frame:HookScript("OnUpdate", tick)
  symbol = ring.hub:CreateTexture(nil, "OVERLAY")
  symbol:SetTexture(B.UI.GLYPH_PATHS.app_courtesy)
  symbol:SetSize(38, 38)
  symbol:SetPoint("CENTER")
  S.tint(symbol, S.C.accent)
  caption = S.text(ring.frame, 13, S.C.bright)
  caption:SetPoint("BOTTOM", ring.frame, "TOP", 0, 6)
  caption:SetWidth(Medallion.WIDTH)
  caption:SetJustifyH("CENTER")
end

-- Opens the ring: `items` the kit's four, `text` above it. `fire(index, item)` on a petal,
-- `close()` when it goes, however it goes, `secured(index, item)` after a petal's secure click.
function Medallion.Open(items, text, fire, close, secured)
  if not ring then
    build()
  end
  if ring:IsShown() then
    onClose = nil -- replaced, not dismissed
    ring:Close()
  end
  onFire, onClose, onSecured = fire, close, secured
  ring:SetItems(items, "", 0, 0)
  caption:SetText(text or "")
  born, closes, settled = now(), now() + Medallion.SECONDS, false
  place(0)
  ring.frame:SetAlpha(1)
  local parent = UIParent
  ring:OpenAt((parent:GetWidth() or 1920) / 2, (parent:GetHeight() or 1080) - Medallion.FROM_TOP)
  place(0) -- SetItems and OpenAt lay the petals out in full; they start at the centre
end

function Medallion.Close()
  if ring and ring:IsShown() then
    ring:Close()
  end
end

function Medallion.IsShown()
  return ring ~= nil and ring:IsShown()
end

-- For the tests: what petal `i` holds, its secure button, the caption, the symbol's texture.
function Medallion.Item(i)
  return ring and ring.items[i] or nil
end

function Medallion.Secure(i)
  return ring and ring:Secure(i) or nil
end

function Medallion.Caption()
  return caption and caption:GetText() or nil
end

function Medallion.Symbol()
  return symbol and symbol:GetTexture() or nil
end

function Medallion.Petal(i)
  return ring and ring.wedges[i] or nil
end
