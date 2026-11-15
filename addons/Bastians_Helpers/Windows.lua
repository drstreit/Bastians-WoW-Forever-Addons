-- Bastian's Helpers, the game's windows (helpers.md "The game's windows",
-- "make all blizzard windows movable"): every window the game's panel manager places, and a few it
-- does not, moves by a drag; the place is kept per window and laid again when it shows. Protected
-- windows are left alone in a fight (CLAUDE.md golden rule 6); no field is written on a Blizzard
-- frame (taint): the places live in the profile, the frames taken in a weak table.
local _, ns = ...
local L = ns.L
local Helpers = ns.Helpers

local Windows = {}
ns.Windows = Windows
Helpers.Windows = Windows

-- Windows outside the panel manager (the game shows them itself).
Windows.EXTRA = { "LootFrame" }

local taken = setmetatable({}, { __mode = "k" }) -- frame -> its global name
local moving = setmetatable({}, { __mode = "k" }) -- frames picked up now
local waiting = {} -- name -> true: a protected window met in a fight, taken at its end
local events

local function on()
  return Helpers.On("moveWindows")
end

local function places()
  local p = Helpers.Profile()
  p.windows = type(p.windows) == "table" and p.windows or {}
  return p.windows
end

local function locked(f)
  return InCombatLockdown() and f.IsProtected ~= nil and f:IsProtected() == true
end

-- The kept place laid on the window, when there is one and nothing forbids it.
function Windows.Place(f)
  local name = taken[f]
  local at = name and places()[name]
  if not (at and on()) or locked(f) then
    return false
  end
  f:ClearAllPoints()
  f:SetPoint(at[1], UIParent, at[2], at[3], at[4])
  return true
end

local function dragStart(f, button)
  if button ~= nil and button ~= "LeftButton" then
    return
  end
  if not on() or locked(f) then
    return
  end
  moving[f] = true
  f:StartMoving()
end

local function dragStop(f)
  if not moving[f] then
    return
  end
  moving[f] = nil
  f:StopMovingOrSizing()
  if f.SetUserPlaced then
    f:SetUserPlaced(false) -- our profile keeps the place, not the client's layout cache
  end
  local point, _, relativePoint, x, y = f:GetPoint(1)
  local name = taken[f]
  if name and point and x and y then
    places()[name] = { point, relativePoint or point, x, y }
  end
end

-- Takes a window by its global name: movable by a drag, its kept place laid when it shows. A
-- protected window in a fight waits. -> true when taken (now or before).
function Windows.Take(name)
  local f = type(name) == "string" and rawget(_G, name) or nil
  if type(f) ~= "table" or type(f.SetMovable) ~= "function" or type(f.HookScript) ~= "function" then
    return false
  end
  if taken[f] then
    return true
  end
  if locked(f) then
    waiting[name] = true
    return false
  end
  taken[f] = name
  f:SetMovable(true)
  if f.SetClampedToScreen then
    f:SetClampedToScreen(true)
  end
  f:RegisterForDrag("LeftButton")
  f:HookScript("OnDragStart", dragStart)
  f:HookScript("OnDragStop", dragStop)
  f:HookScript("OnShow", Windows.Place)
  return true
end

-- Every window the panel manager knows now, and the extra ones.
function Windows.TakeAll()
  local panels = rawget(_G, "UIPanelWindows")
  if type(panels) == "table" then
    for name in pairs(panels) do
      Windows.Take(name)
    end
  end
  for _, name in ipairs(Windows.EXTRA) do
    Windows.Take(name)
  end
end

-- Forgets every kept place; open windows keep their spot until they close.
function Windows.Reset()
  local p = Helpers.Profile()
  p.windows = {}
  Helpers.Notice(L["The game's windows are back in their places."])
end

function Windows.Taken(f)
  return taken[f]
end

function Windows.Attach()
  if Windows.attached then
    Windows.TakeAll()
    return
  end
  Windows.attached = true
  Windows.TakeAll()
  -- a window shown through the panel manager later (a new name, a window loaded on demand), and
  -- the manager's own placing, after which the kept place goes on again
  if type(rawget(_G, "ShowUIPanel")) == "function" then
    hooksecurefunc("ShowUIPanel", function(frame)
      if type(frame) == "table" and not taken[frame] then
        local name = frame.GetName and frame:GetName()
        if name and rawget(_G, name) == frame and Windows.Take(name) then
          Windows.Place(frame)
        end
      end
    end)
  end
  if type(rawget(_G, "UpdateUIPanelPositions")) == "function" then
    hooksecurefunc("UpdateUIPanelPositions", function()
      for f in pairs(taken) do
        if f:IsShown() then
          Windows.Place(f)
        end
      end
    end)
  end
  -- the module's handlers belong to the other helpers: this frame listens itself
  events = CreateFrame("Frame")
  events:RegisterEvent("ADDON_LOADED")
  events:RegisterEvent("PLAYER_REGEN_ENABLED")
  events:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" then
      if type(addon) == "string" and addon:find("^Blizzard_") then
        Windows.TakeAll() -- its windows are in the panel manager's table now
      end
    else
      local names = waiting
      waiting = {}
      for name in pairs(names) do
        if Windows.Take(name) then
          Windows.Place(rawget(_G, name))
        end
      end
    end
  end)
end
