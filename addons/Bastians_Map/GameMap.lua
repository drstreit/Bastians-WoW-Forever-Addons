-- The game's world map and ours (map.md, Should rows built 22.10.2026, owner question "can we
-- replace the world map"): two settings, both off until checked in game.
-- "Open with M": a hook on the game's map frame hides it when it shows and opens ours at the map
-- it wanted (a quest link, the M key); an instance or a cave without a transform of ours stays
-- on the game's map. "Draw Bastian's art over the game's map": a data provider on the game's map
-- canvas (MapCanvasDataProviderMixin, the retail family; GetCanvas and SetMapID verified on
-- Forever) lays our overview cells over the map it shows, placed through the same transforms the
-- addon uses, so the owner's styled art appears inside the normal map too. The cells sit above
-- the game's art and below its pins. No secure frame is touched, nothing in combat is retargeted.
local _, ns = ...
local B = Bastians
local Map = ns.Map
local Overview = ns.Overview

local GameMap = {}
ns.GameMap = GameMap
if ns.mod then
  ns.mod.GameMap = GameMap -- reachable through the module, for the tests
end

GameMap.MAX_CELLS = 64 -- textures a map draws at most (a continent is 20 to 40 cells)
local mod, provider
local hooked = false
local suppress = false -- true while we hide the game's map ourselves

local function db()
  return mod.db.profile
end

-- ---------------------------------------------------------------------------------------------
-- Open with M
-- ---------------------------------------------------------------------------------------------

-- The game's map showed: with the setting on and a map we can draw, it goes and ours opens there.
local function onGameMapShown()
  if suppress or not (mod and mod:IsEnabled() and db().openWithM) then
    return
  end
  local uiMapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID() or nil
  if not (uiMapID and B.Coords.ToWorld(uiMapID, 0.5, 0.5)) then
    return -- an instance, a cave, a map we cannot place in the world: the game's map stays
  end
  suppress = true
  WorldMapFrame:Hide()
  suppress = false
  if Map.IsShown() then
    Map.Hide() -- M is a toggle: ours closes too
  else
    Map.ShowUiMap(uiMapID)
  end
end

local function hookGameMap()
  if hooked or type(WorldMapFrame) ~= "table" or not WorldMapFrame.HookScript then
    return
  end
  hooked = true
  WorldMapFrame:HookScript("OnShow", onGameMapShown)
end

-- ---------------------------------------------------------------------------------------------
-- Our art over the game's map
-- ---------------------------------------------------------------------------------------------

local function newProvider()
  local p = CreateFromMixins(MapCanvasDataProviderMixin)
  p.textures = {}
  p.shown = 0

  function p:RemoveAllData()
    for i = 1, self.shown do
      self.textures[i]:Hide()
    end
    self.shown = 0
  end

  -- The cells of the shown map, placed by the map's transform; nothing for a map without one.
  function p:RefreshAllData()
    self:RemoveAllData()
    if not (mod and mod:IsEnabled() and db().overlayGameMap and Overview.Enabled()) then
      return
    end
    local map = self:GetMap()
    local uiMapID = map and map:GetMapID()
    if not uiMapID then
      return
    end
    local continent, ax, ay = B.Coords.ToWorld(uiMapID, 0, 0)
    local c2, bx, by = B.Coords.ToWorld(uiMapID, 1, 1)
    if not continent or c2 ~= continent then
      return
    end
    local wx1, wx2 = math.min(ax, bx), math.max(ax, bx)
    local wy1, wy2 = math.min(ay, by), math.max(ay, by)
    local canvas = map:GetCanvas()
    local width, height = canvas:GetWidth() or 0, canvas:GetHeight() or 0
    if width <= 0 or height <= 0 then
      return
    end
    local n = 0
    for _, cell in ipairs(Overview.Visible(continent, wx1, wy1, wx2, wy2, 0)) do
      if n >= GameMap.MAX_CELLS then
        break
      end
      -- the cell's corners on the map: north-west (wx2, wy2) is the top-left
      local fx1, fy1 = B.Coords.ToMap(continent, cell.x2, cell.y2, uiMapID)
      local fx2, fy2 = B.Coords.ToMap(continent, cell.x1, cell.y1, uiMapID)
      if fx1 and fx2 then
        n = n + 1
        local tex = self.textures[n]
        if not tex then
          tex = canvas:CreateTexture(nil, "BORDER")
          self.textures[n] = tex
        end
        tex:SetTexture(cell.file)
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", canvas, "TOPLEFT", fx1 * width, -fy1 * height)
        tex:SetSize(math.max(1, (fx2 - fx1) * width), math.max(1, (fy2 - fy1) * height))
        tex:Show()
      end
    end
    self.shown = n
  end
  return p
end

function GameMap.Provider()
  return provider
end

-- The settings decide: the hook is installed once (a hook cannot go), the provider is added and
-- removed with its setting.
function GameMap.Apply()
  if not mod then
    return
  end
  if db().openWithM then
    hookGameMap()
  end
  local want = db().overlayGameMap == true
    and type(WorldMapFrame) == "table"
    and WorldMapFrame.AddDataProvider ~= nil
  if want and not provider then
    provider = newProvider()
    WorldMapFrame:AddDataProvider(provider)
  elseif provider and not want then
    provider:RemoveAllData()
    WorldMapFrame:RemoveDataProvider(provider)
    provider = nil
  elseif provider then
    provider:RefreshAllData()
  end
end

table.insert(Map.onEnable, function(self)
  mod = self
  GameMap.Apply()
end)
table.insert(Map.onSetting, function(key)
  if key == "openWithM" or key == "overlayGameMap" or key == "overviewArt" then
    GameMap.Apply()
  end
end)
