-- Ring (plan-launch-review.md R5.1, 01.11.2026): the suite's ring kit, a round menu of wedges
-- around a hub, drawn like the Orbiter's orbits (the disc and ring textures, kind tiles, labels).
-- Bastian's Gestures opens one at the cursor; the Orbiter moves onto it after the launch.
local _, ns = ...
local B = ns.B
local S = ns.Style

local Ring = {}
B.UI.Ring = Ring

Ring.DEFAULTS = { wedges = 8, radius = 96, inner = 38, bubble = 30 }

-- ---------------------------------------------------------------------------------------------
-- Pure geometry (tested alone). Angles start at the top and go clockwise; y grows upwards, as
-- frame offsets do.
-- ---------------------------------------------------------------------------------------------

-- The centre of wedge `i` of `n` on a circle of `radius`: dx, dy from the hub.
function Ring.Slot(i, n, radius)
  local a = (i - 1) * 2 * math.pi / n
  return radius * math.sin(a), radius * math.cos(a)
end

-- The wedge under the point (dx, dy) from the hub, or nil inside the hub (`r0`) or beyond the rim
-- (`r1`).
function Ring.Hovered(dx, dy, n, r0, r1)
  if not n or n < 1 then
    return nil
  end
  local d = math.sqrt(dx * dx + dy * dy)
  if d < r0 or d > r1 then
    return nil
  end
  local a = math.atan2(dx, dy)
  if a < 0 then
    a = a + 2 * math.pi
  end
  local step = 2 * math.pi / n
  return math.floor((a + step / 2) / step) % n + 1
end

-- A centre kept inside the screen: the ring's half size against the parent's width and height.
function Ring.Clamp(x, y, half, width, height)
  x = math.max(half, math.min(width - half, x))
  y = math.max(half, math.min(height - half, y))
  return x, y
end

-- ---------------------------------------------------------------------------------------------
-- The frame
-- ---------------------------------------------------------------------------------------------

local function disc(parent, color, alpha, layer)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetTexture(S.DISC)
  t:SetAllPoints()
  S.tint(t, color, alpha)
  return t
end

local function rim(parent, color, alpha, layer, texture)
  local t = parent:CreateTexture(nil, layer or "BORDER")
  t:SetTexture(texture or S.RINGS.M)
  t:SetAllPoints()
  S.tint(t, color, alpha)
  return t
end

local RingMT = {}
RingMT.__index = RingMT

local function newWedge(ring, i)
  local b = CreateFrame("Button", nil, ring.frame)
  b.index = i
  b.disc = disc(b, S.C.panel, 0.92)
  b.fill = disc(b, S.C.accent, 0, "BORDER")
  b.ring = rim(b, S.C.line, 1, "ARTWORK")
  b.tile = b:CreateTexture(nil, "ARTWORK")
  b.tile:SetPoint("CENTER", 0, 7)
  b.glyph = b:CreateTexture(nil, "OVERLAY")
  b.glyph:SetPoint("CENTER", b.tile, "CENTER")
  b.label = S.text(b, 10, S.C.text)
  b.label:SetPoint("CENTER", 0, -10)
  b.label:SetJustifyH("CENTER")
  b.sub = b:CreateTexture(nil, "OVERLAY")
  b.sub:SetSize(9, 9)
  b.sub:SetPoint("BOTTOMRIGHT", -3, 3)
  b.sub:SetTexture(B.UI.GLYPH_PATHS.more)
  S.tint(b.sub, S.C.dim)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function(self, button)
    if self.item and not self.item.disabled and ring.opts.onFire then
      ring.opts.onFire(self.index, self.item, button)
    end
  end)
  b:SetScript("OnEnter", function(self)
    ring:Highlight(self.index)
    if self.item and GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      S.TipLine(GameTooltip, self.item.label or "", "tipText")
      if self.item.tip then
        S.TipLine(GameTooltip, self.item.tip, "tipDim", true)
      end
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  return b
end

-- Paints a wedge with its item: the kind tile and glyph, the label, dimmed when disabled.
local function paint(ring, b, item)
  b.item = item
  if not item then
    b:Hide()
    return
  end
  local size = ring.opts.bubble * 2
  b:SetSize(size, size)
  local tile = item.kind and B.UI.IconTexture(item.kind) or nil
  if tile then
    b.tile:SetTexture(tile)
    b.tile:SetSize(18, 18)
    b.tile:Show()
    b.glyph:Hide()
  else
    b.tile:Hide()
    local path = item.icon and (B.UI.GLYPH_PATHS[item.icon] or item.icon) or B.UI.GLYPH_PATHS.other
    b.glyph:SetTexture(path)
    b.glyph:SetSize(16, 16)
    S.tint(b.glyph, S.C.text)
    b.glyph:Show()
  end
  b.label:SetText(item.label or "")
  b.sub:SetShown(item.sub and true or false)
  b:SetAlpha(item.disabled and 0.45 or 1)
  b:Show()
end

-- ---------------------------------------------------------------------------------------------
-- The secure overlay: the client runs a macro
-- only from a secure action button the player clicks. An item with `secure = { type = "macro",
-- macro = name }` (any attributes of SecureActionButtonTemplate) gets a pooled secure button
-- laid over its wedge, out of combat only (CLAUDE.md golden rule 6): created, set and moved only
-- while InCombatLockdown() is false. It is placed by screen coordinates on the ring's parent,
-- never parented or anchored to the ring, so the ring stays free to open and close in combat (the
-- Quests item bar's rule). It hides when the ring closes, when the item changes, and on entering
-- combat (PLAYER_REGEN_DISABLED comes before the lockdown; where the client offers
-- RegisterStateDriver a "[combat] hide" driver keeps it hidden too); PLAYER_REGEN_ENABLED puts
-- the overlays right again. The player's real click runs it; a key release cannot (no click).
-- ---------------------------------------------------------------------------------------------

local function locked()
  return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

local function stateDriver(o, on)
  local register, unregister = rawget(_G, "RegisterStateDriver"), rawget(_G, "UnregisterStateDriver")
  if on and type(register) == "function" then
    register(o, "visibility", "[combat] hide; show")
  elseif not on and o.driven and type(unregister) == "function" then
    unregister(o, "visibility")
  end
  o.driven = on and type(register) == "function" or nil
end

local function hideOverlay(o)
  if o and not locked() then
    stateDriver(o, false)
    o:Hide()
  end
end

-- Hides every overlay of the ring (out of combat; in combat they are hidden already).
function RingMT.HideSecure(self)
  for _, o in pairs(self.secure or {}) do
    hideOverlay(o)
  end
end

local function newOverlay(ring, i)
  local parent = ring.frame:GetParent() or UIParent
  local o = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
  o.index = i
  -- a real mouse press acts on its release whatever ActionButtonUseKeyDown says
  -- (SecureActionButton_OnClick, Forever FrameXML: `isSecureMousePress`), so the up it is
  o:RegisterForClicks("AnyUp")
  o:SetFrameStrata("FULLSCREEN") -- above the ring's DIALOG strata, so the click lands here
  o:EnableMouseWheel(true)
  -- the wedge's tooltip and light, the wheel's cycling: forwarded (none of them is secure)
  o:SetScript("OnEnter", function(self)
    local w = ring.wedges[self.index]
    local fn = w and w:GetScript("OnEnter")
    if fn then
      fn(w)
    end
  end)
  o:SetScript("OnLeave", function(self)
    local w = ring.wedges[self.index]
    local fn = w and w:GetScript("OnLeave")
    if fn then
      fn(w)
    end
  end)
  o:SetScript("OnMouseWheel", function(_, delta)
    if ring.opts.onCycle then
      ring.opts.onCycle(delta)
    end
  end)
  -- after the client ran the action: the caller's word (Gestures closes the ring)
  o:HookScript("PostClick", function(self, button)
    if ring.opts.onSecure then
      ring.opts.onSecure(self.index, ring.items[self.index], button)
    end
  end)
  if not ring.watching then
    ring.watching = true
    ring.frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    ring.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
  end
  return o
end

-- Lays the overlays over the wedges whose item carries `secure` (and is not disabled), hides the
-- others. Nothing in combat; nothing while the ring is closed.
function RingMT.PlaceSecure(self)
  if locked() then
    return
  end
  local open = self.frame:IsShown() and self.cx ~= nil
  local fs = self.frame:GetScale() or 1
  local parent = self.frame:GetParent() or UIParent
  for i = 1, self.opts.wedges do
    local item = self.items[i]
    local o = self.secure and self.secure[i]
    if open and item and item.secure and not item.disabled then
      self.secure = self.secure or {}
      o = o or newOverlay(self, i)
      self.secure[i] = o
      for key in pairs(o.attrs or {}) do
        if item.secure[key] == nil then
          o:SetAttribute(key, nil)
        end
      end
      for key, value in pairs(item.secure) do
        o:SetAttribute(key, value)
      end
      o.attrs = item.secure
      local dx, dy = Ring.Slot(i, self.opts.wedges, self.opts.radius)
      local size = self.opts.bubble * 2 * fs
      o:SetSize(size, size)
      o:ClearAllPoints()
      o:SetPoint("CENTER", parent, "BOTTOMLEFT", self.cx + dx * fs, self.cy + dy * fs)
      o:Show()
      if not o.driven then
        stateDriver(o, true)
      end
    else
      hideOverlay(o)
    end
  end
end

-- The overlay of wedge `i` (tests), or nil.
function RingMT.Secure(self, i)
  return self.secure and self.secure[i] or nil
end

-- Shows items (an array of up to `wedges`; nil for an empty slot) with the hub's title and the
-- page dots (`page` of `pages`).
function RingMT.SetItems(self, items, title, page, pages)
  self.items = items or {}
  for i = 1, self.opts.wedges do
    local b = self.wedges[i]
    if not b then
      b = newWedge(self, i)
      self.wedges[i] = b
    end
    local dx, dy = Ring.Slot(i, self.opts.wedges, self.opts.radius)
    b:ClearAllPoints()
    b:SetPoint("CENTER", self.frame, "CENTER", dx, dy)
    local item = self.items[i]
    if item == false then
      item = nil
    end
    paint(self, b, item)
    if not item then
      -- an empty slot shows a faint place
      b.item = nil
      b:SetSize(self.opts.bubble * 2, self.opts.bubble * 2)
      b.tile:Hide()
      b.glyph:Hide()
      b.label:SetText("")
      b.sub:Hide()
      b:SetAlpha(0.25)
      b:Show()
    end
  end
  self.title:SetText(title or "")
  self:PlaceSecure()
  pages = pages or 0
  for i = 1, math.max(pages, #self.dots) do
    local d = self.dots[i]
    if not d then
      d = self.hub:CreateTexture(nil, "OVERLAY")
      d:SetTexture(S.DISC)
      d:SetSize(6, 6)
      self.dots[i] = d
    end
    if i <= pages then
      d:ClearAllPoints()
      d:SetPoint("CENTER", self.hub, "CENTER", (i - (pages + 1) / 2) * 10, -12)
      S.tint(d, i == page and S.C.accent or S.C.dim, i == page and 1 or 0.6)
      d:Show()
    else
      d:Hide()
    end
  end
  self:Highlight(nil)
end

-- Lights wedge `i` (nil: none).
function RingMT.Highlight(self, i)
  if self.lit == i then
    return
  end
  self.lit = i
  for n, b in ipairs(self.wedges) do
    local on = n == i and b.item ~= nil
    S.tint(b.fill, S.C.accent, on and 0.9 or 0)
    S.tint(b.ring, on and S.C.bright or S.C.line, 1)
    S.ink(b.label, on and S.C.bg or S.C.text)
  end
end

-- The wedge under the cursor right now, or nil.
function RingMT.HoveredIndex(self)
  if not self.frame:IsShown() then
    return nil
  end
  local x, y = GetCursorPosition()
  local parent = self.frame:GetParent() or UIParent
  local cx, cy = self.cx, self.cy -- where OpenAt put the centre, in the parent's units
  if not (cx and cy) then
    return nil
  end
  local ps = parent:GetEffectiveScale()
  local fs = self.frame:GetScale() or 1
  local dx, dy = (x / ps - cx) / fs, (y / ps - cy) / fs
  return Ring.Hovered(dx, dy, self.opts.wedges, self.opts.inner, self.opts.radius + self.opts.bubble)
end

-- Opens the ring with its centre at (x, y) in the parent's units, kept inside the screen.
function RingMT.OpenAt(self, x, y)
  local parent = self.frame:GetParent() or UIParent
  local half = (self.opts.radius + self.opts.bubble) * (self.frame:GetScale() or 1)
  x, y = Ring.Clamp(x, y, half, parent:GetWidth() or 1920, parent:GetHeight() or 1080)
  self.cx, self.cy = x, y
  self.frame:ClearAllPoints()
  self.frame:SetPoint("CENTER", parent, "BOTTOMLEFT", x, y)
  self.frame:Show()
  self.frame:Raise()
  self:Highlight(nil)
  self:PlaceSecure()
end

-- Opens the ring under the cursor.
function RingMT.OpenAtCursor(self)
  local x, y = GetCursorPosition()
  local scale = (self.frame:GetParent() or UIParent):GetEffectiveScale()
  self:OpenAt(x / scale, y / scale)
end

function RingMT.Close(self)
  self.frame:Hide()
end

function RingMT.IsShown(self)
  return self.frame:IsShown()
end

-- Scale in percent (50 to 200), the frame's own SetScale so text and textures scale together.
function RingMT.SetScale(self, percent)
  local s = math.max(50, math.min(200, tonumber(percent) or 100)) / 100
  self.frame:SetScale(s)
end

-- Follows the cursor while shown (the lit wedge); nothing while hidden (CLAUDE.md golden rule 7).
local function onUpdate(frame)
  local ring = frame.ring
  ring:Highlight(ring:HoveredIndex())
end

-- opts: { wedges, radius, inner, bubble, onFire(index, item, button), onCycle(delta),
--         onHub(button), onHide(), onSecure(index, item, button) (after a secure overlay's click),
--         parent, escape (default true) }
function Ring.New(name, opts)
  opts = setmetatable(opts or {}, { __index = Ring.DEFAULTS })
  local frame = CreateFrame("Frame", name, opts.parent or UIParent)
  local size = (opts.radius + opts.bubble) * 2
  frame:SetSize(size, size)
  frame:SetFrameStrata("DIALOG")
  frame:SetToplevel(true)
  frame:EnableMouse(true)
  frame:EnableMouseWheel(true)
  frame:Hide()
  local self = setmetatable({ frame = frame, opts = opts, wedges = {}, dots = {}, items = {} }, RingMT)
  frame.ring = self
  -- the hub: a disc with the title and the page dots; a click on it is the caller's (back, close)
  local hub = CreateFrame("Button", nil, frame)
  hub:SetSize(opts.inner * 2, opts.inner * 2)
  hub:SetPoint("CENTER")
  hub.disc = disc(hub, S.C.bg, 0.96)
  hub.ring = rim(hub, S.C.line, 1, "ARTWORK")
  hub:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  hub:SetScript("OnClick", function(_, button)
    if opts.onHub then
      opts.onHub(button)
    end
  end)
  self.hub = hub
  self.title = S.heading(hub, 12)
  self.title:SetPoint("CENTER", 0, 4)
  self.title:SetJustifyH("CENTER")
  frame:SetScript("OnMouseWheel", function(_, delta)
    if opts.onCycle then
      opts.onCycle(delta)
    end
  end)
  frame:SetScript("OnUpdate", onUpdate)
  frame:SetScript("OnHide", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
    self:HideSecure()
    if opts.onHide then
      opts.onHide()
    end
  end)
  -- registered with the first secure overlay only: entering combat hides the overlays, leaving
  -- it puts them right
  frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
      self:HideSecure()
    elseif frame:IsShown() then
      self:PlaceSecure()
    else
      self:HideSecure()
    end
  end)
  if name and opts.escape ~= false then
    table.insert(UISpecialFrames, name) -- Escape closes it, as every window of the suite
  end
  return self
end

-- ---------------------------------------------------------------------------------------------
-- The ring registry (core-contracts §13 "Rings", plan-second-wave.md decision F, 02.11.2026): an
-- app offers a ring of its own while it is enabled; the ring host (Bastian's Gestures) shows every
-- registered ring after its own three. Apps never call each other: the host reads the registry,
-- the owner answers through its spec.
--   B:RegisterRing(owner, { id, name, order, items = fn() -> the ring kit's items (up to eight;
--                  false for an empty slot), fire = fn(index, item, button) -> bool,
--                  secure = fn(index, item, button) (after a secure wedge's click) })
-- Removed with B:UnregisterRing(owner, id) or when the owner is disabled; both announce
-- BASTIANS_REGISTRY_CHANGED("ring", id, added).
-- ---------------------------------------------------------------------------------------------

local rings = {} -- id -> spec

function B:RegisterRing(owner, spec)
  if type(spec) ~= "table" or type(spec.id) ~= "string" then
    error("RegisterRing: `id` is required", 2)
  end
  if type(spec.items) ~= "function" or type(spec.fire) ~= "function" then
    error("RegisterRing: `items` and `fire` (functions) are required", 2)
  end
  spec.owner = owner
  spec.order = spec.order or 50
  rings[spec.id] = spec
  B:Fire("BASTIANS_REGISTRY_CHANGED", "ring", spec.id, true)
  ns.track(owner, function()
    if rings[spec.id] == spec then
      rings[spec.id] = nil
      B:Fire("BASTIANS_REGISTRY_CHANGED", "ring", spec.id, false)
    end
  end)
end

function B:UnregisterRing(owner, id)
  local spec = rings[id]
  if spec and spec.owner == owner then
    rings[id] = nil
    B:Fire("BASTIANS_REGISTRY_CHANGED", "ring", id, false)
  end
end

-- The registered rings of enabled owners, by order and id.
function B:GetRings()
  local out = {}
  for _, spec in pairs(rings) do
    if not spec.owner.IsEnabled or spec.owner:IsEnabled() then
      out[#out + 1] = spec
    end
  end
  table.sort(out, function(a, b)
    if a.order ~= b.order then
      return a.order < b.order
    end
    return a.id < b.id
  end)
  return out
end
