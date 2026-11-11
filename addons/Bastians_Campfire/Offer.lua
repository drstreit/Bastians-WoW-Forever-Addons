-- The two secure buttons of Bastian's Campfire (campfire.md "The flame", "Lighting a fire"): the foot
-- icon at the flame, which places what the camp lacks or throws the Violet Dust, and the minimap
-- button that lights a kit away from a fire. Using an item needs a secure button the player clicks:
-- both are created, set and moved only out of combat (CLAUDE.md golden rule 6), and the foot is placed
-- by screen coordinates, never anchored to the flame, so the flame stays free in combat.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Camp = ns.Camp
local Model = ns.Model

local Offer = {}
ns.Offer = Offer

local FOOT_SIZE = 26
local LIGHT_ANGLE = 160 -- degrees around the minimap, until the player drags it

local mod, foot, lighter, readyTimer
local footAt, lightAt = 1, 1 -- how far the right click has gone through the offers

local function locked()
  return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

local function stateDriver(b, on)
  local register, unregister = rawget(_G, "RegisterStateDriver"), rawget(_G, "UnregisterStateDriver")
  if on and not b.driven and type(register) == "function" then
    register(b, "visibility", "[combat] hide; show")
    b.driven = true
  elseif not on and b.driven and type(unregister) == "function" then
    unregister(b, "visibility")
    b.driven = nil
  end
end

local function hideButton(b)
  if b and not locked() then
    stateDriver(b, false)
    b:Hide()
  end
end

local function reveal(b)
  b:Show()
  stateDriver(b, true)
end

-- Only the left button acts (`type1`): the right click goes to the next offer.
local function setEntry(b, entry)
  b.entry = entry
  local key = entry.toy or entry.item
  if b.key == key then
    return
  end
  b.key = key
  b:SetAttribute("type1", entry.toy and "toy" or "item")
  b:SetAttribute("toy", entry.toy)
  b:SetAttribute("item", entry.item and ("item:" .. entry.item) or nil)
  local icon = B.Compat.ItemIcon(entry.toy or entry.item)
  if icon then
    b.icon:SetTexture(icon)
  else
    B.UI.PaintIcon(b.icon, B.UI.IconTexture("campfire"))
  end
end

local function secureButton(name, parent)
  local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
  -- acts on the release, whatever ActionButtonUseKeyDown says (Core's Ring.lua)
  b:RegisterForClicks("AnyUp")
  b:SetAttribute("useOnKeyDown", false)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  return b
end

-- -------------------------------------------------------------------------------------------------
-- What is offered
-- -------------------------------------------------------------------------------------------------

-- Whether the Violet Dust can be thrown now: owned, off cooldown, no violet flames yet, and the client
-- does not call the toy unusable (the Launch Celebration's end). Unknown answers do not hide it.
function Offer.VioletReady()
  if ns.Watch.State().violet then
    return false
  end
  local owned, ready = B.Compat.GetTeleportState("toy", Camp.VIOLET.toy)
  return owned == true and ready ~= false and B.Compat.ToyUsable(Camp.VIOLET.toy) ~= false
end

-- The foot icon's offers, best first: the features the camp lacks, then the dust.
function Offer.FootEntries(card)
  local out = {}
  for _, feature in ipairs(card.could) do
    out[#out + 1] = { item = feature.item, name = L[feature.name], feature = feature }
  end
  if Offer.VioletReady() then
    out[#out + 1] = { toy = Camp.VIOLET.toy, name = L["Violet dust for the fire"] }
  end
  return out
end

-- The class buff on the player that `benefit` does not stack with: its name, or nil.
local function clash(benefit)
  local word = benefit and benefit.exclusive and L[benefit.exclusive]
  if not word then
    return nil
  end
  for _, name in pairs(B.Compat.PlayerAuras()) do
    if type(name) == "string" and string.find(name, word, 1, true) then
      return name
    end
  end
  return nil
end

local function footTip(self)
  local entry = self.entry
  if not entry then
    return
  end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  S.TipLine(GameTooltip, entry.name, "tipText")
  local feature = entry.feature
  if feature then
    local benefit = feature.benefit and Camp.BENEFITS[feature.benefit] or nil
    if benefit then
      local level = UnitLevel("player")
      S.TipLine(GameTooltip, ns.Planner.ValueText(benefit, Model.Values(benefit, level)), "tipDim")
      local other = clash(benefit)
      if other then
        S.TipLine(GameTooltip, string.format(L["Does not stack with your %s."], other), "tipDim")
      end
    elseif feature.service then
      S.TipLine(GameTooltip, L[feature.service], "tipDim")
    end
    S.TipLine(GameTooltip, L["Sit again for a minute afterwards to get its buff."], "tipDim", true)
  else
    S.TipLine(GameTooltip, L["Colours the fire violet."], "tipDim")
  end
  S.TipLine(GameTooltip, L["Click: use it. Right click: the next one."], "tipDim")
  GameTooltip:Show()
end

-- -------------------------------------------------------------------------------------------------
-- The foot icon
-- -------------------------------------------------------------------------------------------------

local function buildFoot()
  local b = secureButton("BastiansCampfireFoot", UIParent)
  b:SetSize(FOOT_SIZE, FOOT_SIZE)
  b.icon:SetAllPoints(b)
  if b.icon.SetMask then
    b.icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")
  end
  b.rim = b:CreateTexture(nil, "OVERLAY")
  b.rim:SetTexture(B.UI.GLYPH_PATHS.flame_ring)
  b.rim:SetPoint("CENTER")
  b.rim:SetSize(FOOT_SIZE + 6, FOOT_SIZE + 6)
  S.tint(b.rim, S.C.warn)
  b:SetScript("OnEnter", function(self)
    self.hovered = true
    footTip(self)
  end)
  b:SetScript("OnLeave", function(self)
    self.hovered = false
    GameTooltip:Hide()
  end)
  b:HookScript("PostClick", function(self, button)
    if button == "RightButton" then
      footAt = footAt + 1
      Offer.Refresh()
      if self.hovered then
        footTip(self)
      end
    else
      B:Fire("BASTIANS_CAMP_CHANGED")
    end
  end)
  return b
end

function Offer.HideFoot()
  hideButton(foot)
end

local function refreshFoot()
  local flame = ns.Card.Frame()
  local st = ns.Watch.State()
  local entries = (flame and flame:IsShown() and st.nearby) and Offer.FootEntries(ns.Watch.Card()) or {}
  local cx, cy
  if #entries > 0 then
    cx, cy = flame:GetCenter()
  end
  if not cx then
    return hideButton(foot)
  end
  foot = foot or buildFoot()
  footAt = ((footAt - 1) % #entries) + 1
  setEntry(foot, entries[footAt])
  foot:SetFrameStrata(flame:GetFrameStrata())
  foot:SetFrameLevel(flame:GetFrameLevel() + 10)
  foot:ClearAllPoints()
  foot:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx + 22, cy - 24)
  reveal(foot)
end

-- -------------------------------------------------------------------------------------------------
-- The minimap button
-- -------------------------------------------------------------------------------------------------

local function placeLight(b)
  local angle = math.rad(mod.db.profile.lightAngle or LIGHT_ANGLE)
  local r = (Minimap:GetWidth() or 140) / 2 + 6
  b:ClearAllPoints()
  b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function lightTip(self)
  local entry = self.entry
  if not entry then
    return
  end
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  S.TipLine(GameTooltip, entry.name, "tipText")
  local left = B.Compat.ItemCooldown(entry.item)
  if left and left > 1.5 then
    S.TipLine(GameTooltip, string.format(L["Ready in %s."], Model.Clock(left)), "tipDim")
  end
  S.TipLine(GameTooltip, L["Click: light a fire. Right click: the next kit. Drag: move."], "tipDim", true)
  GameTooltip:Show()
end

local function stopDrag(b)
  if b then
    b:SetScript("OnUpdate", nil)
  end
end

local function buildLight()
  local b = secureButton("BastiansCampfireLight", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  b.icon:SetDrawLayer("BACKGROUND")
  b.icon:SetSize(20, 20)
  b.icon:SetPoint("TOPLEFT", 7, -5)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetPoint("TOPLEFT")
  b:SetScript("OnDragStart", function(self)
    if locked() then
      return
    end
    self:SetScript("OnUpdate", function(me)
      if locked() then
        return stopDrag(me)
      end
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local s = Minimap:GetEffectiveScale()
      mod.db.profile.lightAngle = math.deg(math.atan2(cy / s - my, cx / s - mx))
      placeLight(me)
    end)
  end)
  b:SetScript("OnDragStop", stopDrag)
  b:SetScript("OnEnter", function(self)
    self.hovered = true
    lightTip(self)
  end)
  b:SetScript("OnLeave", function(self)
    self.hovered = false
    GameTooltip:Hide()
  end)
  b:HookScript("PostClick", function(self, button)
    if button == "RightButton" then
      lightAt = lightAt + 1
      Offer.Refresh()
      if self.hovered then
        lightTip(self)
      end
    end
  end)
  placeLight(b)
  return b
end

local function cancelReady()
  if readyTimer then
    readyTimer:Cancel()
    readyTimer = nil
  end
end

-- The button is dimmed while the kit cools down; a one-shot timer lights it again.
local function dimWhileCooling(b, entry)
  cancelReady()
  local left = B.Compat.ItemCooldown(entry.item)
  local cooling = left ~= nil and left > 1.5
  b:SetAlpha(cooling and 0.45 or 1)
  if cooling then
    readyTimer = C_Timer.NewTimer(left + 0.5, Offer.Refresh)
  end
end

local function refreshLight()
  local st = ns.Watch.State()
  local kits = {}
  if mod:IsEnabled() and mod.db.profile.lightButton and not st.nearby and not st.resting then
    kits = Model.Kits(st.carried, st.professions)
  end
  if #kits == 0 then
    cancelReady()
    return hideButton(lighter)
  end
  lighter = lighter or buildLight()
  lightAt = ((lightAt - 1) % #kits) + 1
  local kit = kits[lightAt]
  local entry = { item = kit.item, name = L[kit.name] }
  setEntry(lighter, entry)
  dimWhileCooling(lighter, entry)
  reveal(lighter)
end

-- -------------------------------------------------------------------------------------------------

-- Both buttons from the watch. Nothing in combat: they are hidden then, PLAYER_REGEN_ENABLED comes back.
function Offer.Refresh()
  if not mod or locked() then
    return
  end
  refreshFoot()
  refreshLight()
end

-- PLAYER_REGEN_DISABLED comes just before the lockdown: the last moment to hide them by hand.
function Offer.OnCombat()
  stopDrag(lighter)
  hideButton(foot)
  hideButton(lighter)
end

function Offer.Foot()
  return foot
end

function Offer.Light()
  return lighter
end

function Offer.Attach(m)
  mod = m
  footAt, lightAt = 1, 1
  m:RegisterEvent("PLAYER_REGEN_DISABLED", Offer.OnCombat)
  m:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    ns.Watch.Read() -- what changed while auras were hidden
    Offer.Refresh()
  end)
  Offer.Refresh()
end

function Offer.Detach()
  cancelReady()
  hideButton(foot)
  hideButton(lighter)
end
