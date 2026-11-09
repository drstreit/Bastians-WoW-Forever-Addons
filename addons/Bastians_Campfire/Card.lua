-- The flame of Bastian's Campfire (campfire.md "The flame"): a flame without a box while a fire is
-- near, while the player rests by it, and a minute after. Its size, colour and flicker are the camp's
-- state, the tooltip says what the camp gives. Left click sits, right click shares the fire,
-- Shift-click hides it. It flickers and refreshes only while shown (CLAUDE.md §4.7).
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Camp = ns.Camp
local Model = ns.Model

local Card = {}
ns.Card = Card

Card.SIZE = 64 -- the flame's frame; the flame itself is at most FLAME
local FLAME = 60
local FLICKER_EVERY = 0.05 -- 20 steps a second are enough for a fire

-- The theme's colours of a state: the flame, its heart (a new colour is a theme token, ADR 0017).
local INK = {
  near = { "warn", "gold" },
  warming = { "warn", "gold" },
  warm = { "warn", "gold" },
  fading = { "bad", "warn" },
  away = { "dim", "dim" },
}

local mod, frame

-- The benefit's word.
function Card.Label(key)
  local b = Camp.BENEFITS[key]
  return b and L[b.label] or key
end

local function list(keys, word)
  local out = {}
  for _, key in ipairs(keys) do
    out[#out + 1] = word(key)
  end
  return table.concat(out, ", ")
end

local function featureName(feature)
  return L[feature.name]
end

-- The flame's two lines for a state of Model.Card: the heading and the sentence.
function Card.Words(card)
  local could = #card.could > 0 and string.format(L["You could add: %s."], list(card.could, featureName))
    or nil
  local have = #card.have > 0 and list(card.have, Card.Label) or nil
  local parts = {}
  local heading
  if card.state == "warming" then
    heading = L["Getting warm"]
    parts[#parts + 1] = have and string.format(L["A fire burns: %s."], have) or L["A fire burns."]
    parts[#parts + 1] = could
    if card.warmIn then
      parts[#parts + 1] = string.format(L["%s until you are warm."], Model.Clock(card.warmIn))
    else
      parts[#parts + 1] = L["Rest a minute to get warm."]
    end
  elseif card.state == "warm" or card.state == "fading" then
    heading = card.state == "fading" and L["The warmth is fading"] or L["You are warm"]
    parts[#parts + 1] = string.format(L["Warm: %s."], have)
    parts[#parts + 1] = could
    parts[#parts + 1] = card.left and string.format(L["%s left."], Model.Clock(card.left))
      or L["Time left: unknown."]
  elseif card.state == "near" then
    heading = L["A fire nearby"]
    parts[#parts + 1] = L["A fire burns."]
    parts[#parts + 1] = could
    parts[#parts + 1] = L["Sit by it for a minute to get warm."]
  else
    heading = L["The fire is behind you"]
    parts[#parts + 1] = have and string.format(L["Warm: %s."], have) or L["No fire nearby."]
  end
  local text = {}
  for _, p in ipairs(parts) do
    if p then
      text[#text + 1] = p
    end
  end
  return heading, table.concat(text, " ")
end

-- Whether the right click may share the fire now.
local function canShare(state)
  return mod.db.profile.beacon and state ~= "away"
end

local function showTip(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  S.TipLine(GameTooltip, self.headingText or "", "tipText")
  S.TipLine(GameTooltip, self.sentence or "", "tipDim", true)
  S.TipLine(GameTooltip, L["Left click: sit"], "tipDim")
  if canShare(self.state) then
    S.TipLine(GameTooltip, L["Right click: share the fire"], "tipDim")
  end
  S.TipLine(GameTooltip, L["Shift-click: hide until something changes"], "tipDim")
  S.TipLine(GameTooltip, L["Drag: move"], "tipDim")
  GameTooltip:Show()
end

-- One step of the flicker: the size, the brightness and how much of the heart is lit.
local function flicker(self, t)
  local size, outer, heart = Model.Flame(self.state, t)
  local px = FLAME * size
  self.flame:SetSize(px, px)
  self.flame:SetAlpha(outer)
  local fill = self.fill or 1
  self.heart:SetSize(px, px * fill)
  self.heart:SetTexCoord(0, 1, 1 - fill, 1)
  self.heart:SetAlpha(heart)
end

local function build()
  local f = CreateFrame("Button", "BastiansCampfireCard", UIParent)
  f:SetSize(Card.SIZE, Card.SIZE)
  local at = mod.db.profile.cardPos -- where the player dragged it
  if at then
    f:SetPoint(at[1], UIParent, at[2], at[3], at[4])
  else
    f:SetPoint("TOP", UIParent, "TOP", 0, -230)
  end
  f:SetFrameStrata(B.UI.WINDOW_STRATA)
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetHitRectInsets(8, 8, 4, 4) -- the flame's corners are empty
  f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnMouseDown", function(self)
    self.moved = false
  end)
  f:SetScript("OnDragStart", function(self)
    self.moved = true -- the release of a drag is no click
    self:StartMoving()
    ns.Offer.HideFoot()
  end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relative, x, y = self:GetPoint(1)
    mod.db.profile.cardPos = { point, relative, x, y }
    ns.Offer.Refresh()
  end)
  f:SetScript("OnClick", function(_, button)
    Card.Click(button)
  end)
  f:SetScript("OnEnter", function(self)
    self.hovered = true
    showTip(self)
  end)
  f:SetScript("OnLeave", function(self)
    self.hovered = false
    GameTooltip:Hide()
  end)
  f.flame = f:CreateTexture(nil, "ARTWORK")
  f.flame:SetTexture(B.UI.GLYPH_PATHS.flame)
  f.flame:SetPoint("BOTTOM", 0, 2)
  f.heart = f:CreateTexture(nil, "OVERLAY")
  f.heart:SetTexture(B.UI.GLYPH_PATHS.flame_heart)
  f.heart:SetPoint("BOTTOM", f.flame, "BOTTOM")
  -- the camp buffs' time left: the game runs the ring down, no Lua per frame (assumed on Forever)
  f.sweep = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
  f.sweep:SetAllPoints(f)
  f.sweep:EnableMouse(false)
  f.sweep.noCooldownCount = true
  if f.sweep.SetSwipeTexture then
    f.sweep:SetSwipeTexture(B.UI.GLYPH_PATHS.flame_ring)
  end
  if f.sweep.SetDrawEdge then
    f.sweep:SetDrawEdge(false)
  end
  if f.sweep.SetDrawBling then
    f.sweep:SetDrawBling(false)
  end
  if f.sweep.SetHideCountdownNumbers then
    f.sweep:SetHideCountdownNumbers(true)
  end
  if f.sweep.SetReverse then
    f.sweep:SetReverse(true)
  end
  if f.sweep.SetSwipeColor then
    local c = S.C.warn
    f.sweep:SetSwipeColor(c[1], c[2], c[3], 0.8)
  end
  f.sweep:Hide()
  f.time = S.text(f, 11, S.C.text)
  f.time:SetPoint("TOP", f, "BOTTOM", 0, 0)
  f.elapsed, f.step, f.clock = 0, 0, 0
  f:SetScript("OnUpdate", function(self, dt)
    dt = dt or 0
    self.clock = self.clock + dt
    self.step = self.step + dt
    if self.step >= FLICKER_EVERY then
      self.step = 0
      flicker(self, self.clock)
    end
    self.elapsed = self.elapsed + dt
    if self.elapsed >= 1 then
      self.elapsed = 0
      Card.Refresh()
    end
  end)
  f:Hide()
  return f
end

-- A click on the flame. -> what it did: "sit", "share", "hide", or nil.
function Card.Click(button)
  if not frame or frame.moved then
    return nil
  end
  if type(IsShiftKeyDown) == "function" and IsShiftKeyDown() then
    Card.Dismiss()
    return "hide"
  elseif button == "RightButton" then
    if canShare(frame.state) then
      ns.Beacon.Share()
      return "share"
    end
    return nil
  end
  B.Compat.Emote("SIT")
  return "sit"
end

-- The ring around the flame: the camp buffs' time left, set again only when their end has moved.
local function runSweep(f, card)
  if not (card.left and (card.state == "warm" or card.state == "fading")) then
    f.sweepEnd = nil
    f.sweep:Hide()
    return
  end
  local ends = GetTime() + card.left
  if f.sweepEnd and math.abs(f.sweepEnd - ends) < 1.5 then
    return
  end
  f.sweepEnd = ends
  local whole = math.max(Camp.BUFF_SECONDS, card.left)
  f.sweep:Show()
  f.sweep:SetCooldown(ends - whole, whole)
end

local function paint(f, card)
  if f.state ~= card.state then
    f.state = card.state
    local ink = INK[card.state] or INK.near
    S.tint(f.flame, S.C[ink[1]])
    S.tint(f.heart, S.C[ink[2]])
  end
  f.fill = Model.Fill(card.state, card.warmIn)
  f.time:SetText(Model.Clock(card.warmIn or card.left) or "")
  runSweep(f, card)
  flicker(f, f.clock)
end

local function hide()
  if frame then
    frame:Hide()
  end
end

-- Draws the flame from the watch, or hides it; then the foot icon and the minimap button follow.
function Card.Refresh()
  local card = (mod and mod:IsEnabled() and mod.db.profile.card) and ns.Watch.Card() or nil
  if not card then
    hide()
  elseif not card.show or Card.dismissed == card.state then
    hide()
    if not card.show then
      Card.dismissed = nil
    end
  else
    frame = frame or build()
    frame.headingText, frame.sentence = Card.Words(card)
    paint(frame, card)
    if not frame:IsShown() then
      frame:Show()
      frame:Raise() -- newly opened: over the windows, later refreshes leave the order alone
    end
    if frame.hovered then
      showTip(frame)
    end
  end
  if mod then
    ns.Offer.Refresh()
  end
end

-- Shift-click: the flame stays away until the state changes.
function Card.Dismiss()
  local card = ns.Watch.Card()
  Card.dismissed = card.state
  hide()
  ns.Offer.Refresh()
end

function Card.IsShown()
  return frame ~= nil and frame:IsShown()
end

function Card.Frame()
  return frame
end

function Card.Attach(m)
  mod = m
  Card.dismissed = nil
  Card.Refresh()
end

function Card.Detach()
  hide()
end
