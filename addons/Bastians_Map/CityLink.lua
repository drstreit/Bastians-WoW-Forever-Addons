-- The ways into the City & dungeon map (map.md "The ways in", the map was "quite
-- hard to find"): a pulsing city button on the minimap while the player is in a place with a sheet,
-- and a "City map" button on the game's world map while it shows such a place. Without the art there
-- is neither. Nothing secure is touched; the game's map is closed only out of a fight.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Map = ns.Map
local City = ns.City

local CityLink = {}
ns.CityLink = CityLink

CityLink.SIZE = 28 -- the minimap button
CityLink.PULSE = 12 -- seconds the button pulses after entering a place
CityLink.ICON = "zone"
CityLink.HALO = 7 -- pixels the pulsing halo reaches past the rim
CityLink.HALO_ALPHA = { 0.85, 0.1 } -- the halo's pulse, from and to
CityLink.BEAT = 1.4 -- seconds of one pulse, there and back

local mod, nudge, provider
local here -- the place the player stands in, or nil

local function db()
  return mod.db.profile
end

-- The place's name in the player's language (the zone's own), the manifest's as the fallback.
local function placeName(city)
  return B:Entity("zone:" .. city.ui):Name() or city.name
end

-- The place whose sheet is the given UiMap, or nil.
function CityLink.CityOfMap(uiMapID)
  if not (uiMapID and City.Available()) then
    return nil
  end
  return (City.Of("zone:" .. tostring(uiMapID)))
end

function CityLink.Here()
  return here
end

function CityLink.Enabled()
  return mod ~= nil and mod:IsEnabled() and db().cityNudge ~= false
end

-- --- the minimap button ------------------------------------------------------------------------

-- On Bastian's minimap the rim's top left, as the badge sits top right; else the game's minimap's
-- rim at 45 degrees.
function CityLink.Place()
  if not nudge then
    return
  end
  local Mini = ns.Mini
  local view = Mini and Mini.Enabled() and Mini.Frame() and Mini.View()
  nudge:ClearAllPoints()
  if view then
    nudge:SetParent(Mini.Frame())
    nudge:SetFrameLevel((view:GetFrameLevel() or 1) + 30)
    local r = Mini.Size() / 2 + Mini.BORDER
    local d = Mini.Shape() == "ROUND" and r * math.sqrt(0.5) or r - 4
    nudge:SetPoint("CENTER", view, "CENTER", -d, d)
    nudge.host = "bastian"
  elseif Minimap then
    nudge:SetParent(Minimap)
    nudge:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
    local d = (Minimap:GetWidth() or 140) / 2 * math.sqrt(0.5)
    nudge:SetPoint("CENTER", Minimap, "CENTER", -d, d)
    nudge.host = "game"
  end
end

-- The halo's alpha after `t` seconds of pulsing: from the bright end to the faint one and back.
function CityLink.HaloAlpha(t)
  local hi, lo = CityLink.HALO_ALPHA[1], CityLink.HALO_ALPHA[2]
  return lo + (hi - lo) * (0.5 + 0.5 * math.cos(2 * math.pi * t / CityLink.BEAT))
end

local function stopPulse()
  if nudge then
    nudge:SetScript("OnUpdate", nil) -- the button ticks only while it pulses
    nudge.glow:SetAlpha(0)
    nudge.pulsing = false
  end
end

local function onPulse(self, elapsed)
  self.pulsed = self.pulsed + elapsed
  if self.pulsed >= CityLink.PULSE then
    stopPulse()
  else
    self.glow:SetAlpha(CityLink.HaloAlpha(self.pulsed))
  end
end

local function startPulse()
  nudge.pulsing = true
  nudge.pulsed = 0
  nudge.glow:SetAlpha(CityLink.HALO_ALPHA[1])
  nudge:SetScript("OnUpdate", onPulse)
end

local function buildNudge()
  local b = CreateFrame("Button", nil, Minimap or UIParent)
  b:SetSize(CityLink.SIZE, CityLink.SIZE)
  b:RegisterForClicks("LeftButtonUp")
  -- a soft halo behind the rim: what pulses
  b.glow = S.fill(b, S.C.accent, "BACKGROUND")
  b.glow:SetDrawLayer("BACKGROUND", -1)
  b.glow:ClearAllPoints()
  b.glow:SetPoint("TOPLEFT", -CityLink.HALO, CityLink.HALO)
  b.glow:SetPoint("BOTTOMRIGHT", CityLink.HALO, -CityLink.HALO)
  b.glow:SetAlpha(0)
  b.rim = S.fill(b, S.C.accent, "BACKGROUND")
  b.face = S.fill(b, S.C.header, "BORDER")
  b.face:ClearAllPoints()
  b.face:SetPoint("TOPLEFT", 2, -2)
  b.face:SetPoint("BOTTOMRIGHT", -2, 2)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetTexture(B.UI.IconTexture(CityLink.ICON))
  b.icon:SetPoint("TOPLEFT", 5, -5)
  b.icon:SetPoint("BOTTOMRIGHT", -5, 5)
  local round = ns.Mini and ns.Mini.MASKS and ns.Mini.MASKS.ROUND
  if round then
    for _, t in ipairs({ b.glow, b.rim, b.face, b.icon }) do
      local m = b:CreateMaskTexture()
      m:SetTexture(round, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      m:SetAllPoints(t)
      t:AddMaskTexture(m)
    end
  end
  b.tip = function()
    return L["City map"], here and (L["Open the painted map of %s."]):format(placeName(here)) or ""
  end
  b:SetScript("OnEnter", function(self)
    stopPulse()
    S.tint(self.rim, S.C.text)
    S.TipEnter(self)
  end)
  b:SetScript("OnLeave", function(self)
    S.tint(self.rim, S.C.accent)
    S.TipLeave(self)
  end)
  b:SetScript("OnClick", function()
    stopPulse()
    local win = City.win
    if win and win:IsShown() and City.Current() == here then
      win:Hide()
    else
      City.Open(here)
    end
  end)
  b:Hide()
  return b
end

-- The player's zone changed: in a place with a sheet the button shows (and pulses on arriving).
function CityLink.Update(uiMapID)
  local city = CityLink.Enabled() and CityLink.CityOfMap(uiMapID) or nil
  local arrived = city ~= nil and city ~= here
  here = city
  if not city then
    if nudge then
      stopPulse()
      nudge:Hide()
    end
    return
  end
  nudge = nudge or buildNudge()
  CityLink.Place()
  nudge:Show()
  if arrived then
    startPulse()
  end
end

function CityLink.Nudge()
  return nudge
end

-- --- the game's world map ----------------------------------------------------------------------

local function mapButton(parent)
  local b = S.tileButton(parent, L["City map"], CityLink.ICON, "accent", nil, 26)
  b:SetFrameLevel((parent:GetFrameLevel() or 1) + 20)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -12)
  b:SetScript("OnClick", function(self)
    local city = self.city
    if not city then
      return
    end
    if not InCombatLockdown() and WorldMapFrame and WorldMapFrame:IsShown() then
      WorldMapFrame:Hide() -- in a fight the window opens over it instead
    end
    City.Open(city)
  end)
  b.tip = function(self)
    return L["City & dungeon map"],
      self.city and (L["Open the painted map of %s."]):format(placeName(self.city)) or ""
  end
  b:Hide()
  return b
end

local function newProvider()
  local p = CreateFromMixins(MapCanvasDataProviderMixin)

  function p:RemoveAllData()
    if self.button then
      self.button:Hide()
    end
  end

  -- The shown map is a place with a sheet: its button. Any other map: none.
  function p:RefreshAllData()
    local map = self:GetMap()
    local city = map and mod and mod:IsEnabled() and CityLink.CityOfMap(map:GetMapID()) or nil
    if not city then
      self:RemoveAllData()
      return
    end
    if not self.button then
      self.button = mapButton(map.ScrollContainer or map)
    end
    self.button.city = city
    self.button:Show()
  end
  return p
end

function CityLink.Provider()
  return provider
end

-- The provider is added once there is art to open; it stays (a removed provider would only hide).
function CityLink.Apply()
  if provider or not City.Available() then
    return
  end
  if type(WorldMapFrame) ~= "table" or not WorldMapFrame.AddDataProvider then
    return
  end
  provider = newProvider()
  WorldMapFrame:AddDataProvider(provider)
end

-- --- the wiring --------------------------------------------------------------------------------

table.insert(Map.onEnable, function(self)
  mod = self
  CityLink.Apply()
  CityLink.Update(B.Coords.PlayerMap and B.Coords.PlayerMap() or nil)
end)
table.insert(Map.onZone, function(uiMapID)
  CityLink.Apply() -- the art may have come after the Map's start
  CityLink.Update(uiMapID)
end)
table.insert(Map.onSetting, function(key)
  if key == "cityNudge" then
    here = nil -- a fresh look: back on, it pulses again
    CityLink.Update(B.Coords.PlayerMap and B.Coords.PlayerMap() or nil)
  elseif key == "miniMap" or key == "miniSize" or key == "miniShape" or key == "miniBorder" then
    CityLink.Place()
  end
end)
table.insert(Map.onDisable, function()
  here = nil
  if nudge then
    stopPulse()
    nudge:Hide()
  end
  if provider then
    provider:RemoveAllData()
  end
end)

if ns.mod then
  ns.mod.CityLink = CityLink -- reachable through the module, for the tests
end
