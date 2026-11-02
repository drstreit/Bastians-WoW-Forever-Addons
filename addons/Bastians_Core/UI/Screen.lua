-- Core: one key clears the screen (plan-round4 F1; , "for role player
-- support"): what the player ticked on the hub page "Hidden by the key" hides, the same key
-- brings it back as it was. Three groups: the suite's windows and minimap buttons (hidden with
-- Hide), the game's own frames and other addons' windows (faded to alpha 0, the mouse taken from
-- the unprotected ones: a protected frame is never hidden or changed in combat, CLAUDE.md §4.6).
-- The bus message BASTIANS_SUITE_HIDDEN tells apps without a kit window (the Map's pins, Route's
-- arrow). The state does not survive /reload.
local _, ns = ...
local B = ns.B
local L = ns.L

local Screen = {}
B.UI.Screen = Screen

BINDING_NAME_BASTIANS_CLEAR_SCREEN = L["Clear the screen (hide and show what is ticked)"]
B:DeclareMessage("BASTIANS_SUITE_HIDDEN")

-- The game's own, by group (the retail family's names; assumed on Forever, measured per client
-- before release). A name the client lacks is skipped.
Screen.GAME = {
  { key = "screenMinimap", label = "Minimap", frames = { "MinimapCluster" } },
  {
    key = "screenChat",
    label = "Chat",
    chat = true, -- the chat frames and their tabs join by number
    frames = {
      "GeneralDockManager",
      "ChatFrameMenuButton",
      "ChatFrameChannelButton",
      "QuickJoinToastButton",
      "ChatFrame1EditBox",
    },
  },
  {
    key = "screenBars",
    label = "Action bars",
    frames = {
      "MainMenuBar",
      "MultiBarBottomLeft",
      "MultiBarBottomRight",
      "MultiBarRight",
      "MultiBarLeft",
      "MultiBar5",
      "MultiBar6",
      "MultiBar7",
      "StanceBar",
      "PetActionBar",
      "PossessActionBar",
      "StatusTrackingBarManager",
      "MainMenuBarVehicleLeaveButton",
    },
  },
  {
    key = "screenUnits",
    label = "Unit frames",
    frames = {
      "PlayerFrame",
      "TargetFrame",
      "FocusFrame",
      "PetFrame",
      "PartyFrame",
      "CompactRaidFrameManager",
      "CompactRaidFrameContainer",
      "BossTargetFrameContainer",
    },
  },
  { key = "screenBuffs", label = "Buffs", frames = { "BuffFrame", "DebuffFrame" } },
  { key = "screenTracker", label = "Objective tracker", frames = { "ObjectiveTrackerFrame" } },
  {
    key = "screenMicro",
    label = "Micro menu and bags",
    frames = { "MicroMenuContainer", "MicroButtonAndBagsBar", "MicroMenu", "BagsBar" },
  },
  {
    key = "screenAlerts",
    label = "Alerts",
    frames = {
      "AlertFrame",
      "UIErrorsFrame",
      "ZoneTextFrame",
      "SubZoneTextFrame",
      "RaidWarningFrame",
    },
  },
}

-- while hidden: { wins = { win, ... }, buttons = { frame, ... }, alphas = { [frame] = alpha },
-- mouse = { [frame] = true }, extra = { frame, ... } }; nil when everything shows
local hidden

-- An app's frames beyond its kit windows, hidden with the app ("only
-- our own minimap stays visible"): Bastian's minimap of the Map. Apps add theirs with
-- Screen.Register(module, frameName).
Screen.EXTRA = { Map = { "BastiansMiniMap" } }
function Screen.Register(module, frameName)
  Screen.EXTRA[module] = Screen.EXTRA[module] or {}
  table.insert(Screen.EXTRA[module], frameName)
end

local function profile()
  return ns.core.db.profile
end

local function ticked(key, default)
  local v = profile()[key]
  if v == nil then
    return default
  end
  return v and true or false
end

-- Whether the key hides the app's frames (its tick on the page; on unless unticked): apps without
-- a kit window ask before they follow BASTIANS_SUITE_HIDDEN (the Orbiter, 01.11.2026).
function Screen.Hides(module)
  return ticked("screen_" .. tostring(module), true)
end

function Screen.Hidden()
  return hidden ~= nil
end

-- The frame names of a game group, the chat's by number.
local function groupFrames(group)
  local names = {}
  for _, n in ipairs(group.frames) do
    names[#names + 1] = n
  end
  if group.chat then
    for i = 1, tonumber(rawget(_G, "NUM_CHAT_WINDOWS")) or 10 do
      names[#names + 1] = "ChatFrame" .. i
      names[#names + 1] = "ChatFrame" .. i .. "Tab"
    end
  end
  return names
end

local gameNames -- every name of the game's groups, for telling other addons' frames apart
local function isGameName(name)
  if not gameNames then
    gameNames = {}
    for _, group in ipairs(Screen.GAME) do
      for _, n in ipairs(groupFrames(group)) do
        gameNames[n] = true
      end
    end
  end
  return gameNames[name] == true
end

-- The named windows of other addons shown right now: every shown, named frame on UIParent that
-- is neither the suite's nor one of the game's groups. Sorted; empty where the client cannot
-- enumerate frames.
function Screen.OtherFrames()
  local out = {}
  local enumerate = rawget(_G, "EnumerateFrames")
  if type(enumerate) ~= "function" then
    return out
  end
  local f = enumerate()
  while f do
    local ok, name = pcall(f.GetName, f)
    if
      ok
      and type(name) == "string"
      and name ~= ""
      and not name:find("^Bastians")
      and not isGameName(name)
    then
      local okP, parent = pcall(f.GetParent, f)
      if okP and parent == UIParent and f:IsShown() then
        out[#out + 1] = name
      end
    end
    f = enumerate(f)
  end
  table.sort(out)
  return out
end

-- Fades a frame of the game or of another addon: alpha 0, remembered; the mouse taken only from
-- an unprotected frame (a click on an invisible bar would still act), never in combat.
local function fade(frame)
  if not (frame and frame.SetAlpha and frame.GetAlpha) or hidden.alphas[frame] then
    return
  end
  hidden.alphas[frame] = frame:GetAlpha() or 1
  frame:SetAlpha(0)
  local protected = frame.IsProtected == nil or frame:IsProtected()
  if not protected and frame.EnableMouse and frame.IsMouseEnabled and frame:IsMouseEnabled() then
    hidden.mouse[frame] = true
    frame:EnableMouse(false)
  end
end

local function fadeNamed(name)
  local frame = rawget(_G, name)
  if type(frame) == "table" then
    fade(frame)
  end
end

-- Hides what is ticked.
function Screen.Hide()
  if hidden then
    return false
  end
  hidden = { wins = {}, buttons = {}, alphas = {}, mouse = {}, extra = {} }
  -- the suite: every kit window of a ticked app, its other frames, the minimap buttons
  for _, win in pairs(B.UI.Windows) do
    local module = win.opts and win.opts.module or "Core"
    if win.frame:IsShown() and ticked("screen_" .. module, true) then
      win.frame:Hide()
      hidden.wins[#hidden.wins + 1] = win
    end
  end
  for module, names in pairs(Screen.EXTRA) do
    if ticked("screen_" .. module, true) then
      for _, name in ipairs(names) do
        local frame = rawget(_G, name)
        if type(frame) == "table" and frame.IsShown and frame:IsShown() then
          frame:Hide()
          hidden.extra[#hidden.extra + 1] = frame
        end
      end
    end
  end
  if ticked("screenMinimapButtons", true) and B.UI.Launcher then
    local buttons = {}
    for _, b in pairs(B.UI.Launcher.apps or {}) do
      buttons[#buttons + 1] = b
    end
    local suite = rawget(_G, "BastiansMinimapButton")
    if suite then
      buttons[#buttons + 1] = suite
    end
    for _, b in ipairs(buttons) do
      if b:IsShown() then
        b:Hide()
        hidden.buttons[#hidden.buttons + 1] = b
      end
    end
  end
  -- the game's own
  for _, group in ipairs(Screen.GAME) do
    if ticked(group.key, false) then
      for _, name in ipairs(groupFrames(group)) do
        fadeNamed(name)
      end
    end
  end
  -- other addons: every ticked name, or everything shown
  local p = profile()
  if ticked("screenOthersAll", false) then
    for _, name in ipairs(Screen.OtherFrames()) do
      fadeNamed(name)
    end
  end
  for key, on in pairs(p) do
    local name = type(key) == "string" and on and key:match("^screenOther_(.+)$")
    if name then
      fadeNamed(name)
    end
  end
  p.screenHidden = true -- kept over /reload: hidden again after the login
  B:Fire("BASTIANS_SUITE_HIDDEN", true)
  return true
end

-- Brings everything back as it was.
function Screen.Show()
  if not hidden then
    return false
  end
  local was = hidden
  hidden = nil
  profile().screenHidden = nil
  for _, win in ipairs(was.wins) do
    win.frame:Show()
  end
  for _, frame in ipairs(was.extra) do
    frame:Show()
  end
  for _, b in ipairs(was.buttons) do
    b:Show()
  end
  for frame, alpha in pairs(was.alphas) do
    frame:SetAlpha(alpha)
  end
  for frame in pairs(was.mouse) do
    frame:EnableMouse(true)
  end
  B:Fire("BASTIANS_SUITE_HIDDEN", false)
  return true
end

function Screen.Toggle()
  if hidden then
    return Screen.Show()
  end
  return Screen.Hide()
end

-- After a /reload or login with the state kept: hidden again once the windows are up.
local waiter = CreateFrame("Frame")
waiter:RegisterEvent("PLAYER_ENTERING_WORLD")
waiter:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_ENTERING_WORLD")
  if ns.core and ns.core.db and profile().screenHidden then
    C_Timer.After(1.5, function()
      if profile().screenHidden and not hidden then
        Screen.Hide()
      end
    end)
  end
end)

-- Ticks every row of a group on or off.
function Screen.TickAll(keys, on)
  local p = profile()
  for _, key in ipairs(keys) do
    p[key] = on and true or false
  end
  if B.UI.Hub then
    B.UI.Hub.Refresh()
  end
end

local function tickRows(out, keys)
  out[#out + 1] = {
    type = "execute",
    icon = "check",
    label = L["Tick all"],
    func = function()
      Screen.TickAll(keys, true)
    end,
  }
  out[#out + 1] = {
    type = "execute",
    icon = "clear",
    label = L["Untick all"],
    func = function()
      Screen.TickAll(keys, false)
    end,
  }
end

-- The hub page "Hidden by the key" (core-contracts §8: a page may build its rows when shown).
function Screen.Options()
  local out = { { type = "header", label = L["The suite"] } }
  local apps = B.UI.Launcher and B.UI.Launcher.WindowApps and B.UI.Launcher.WindowApps() or {}
  local suiteKeys = {}
  for _, mod in ipairs(apps) do
    out[#out + 1] =
      { type = "toggle", key = "screen_" .. mod.name, label = tostring(mod.title), default = true }
    suiteKeys[#suiteKeys + 1] = "screen_" .. mod.name
  end
  out[#out + 1] = {
    type = "toggle",
    key = "screenMinimapButtons",
    label = L["The suite's minimap buttons"],
    default = true,
  }
  suiteKeys[#suiteKeys + 1] = "screenMinimapButtons"
  tickRows(out, suiteKeys)
  out[#out + 1] = { type = "header", label = L["The game's own"] }
  local gameKeys = {}
  for _, group in ipairs(Screen.GAME) do
    out[#out + 1] = { type = "toggle", key = group.key, label = L[group.label], default = false }
    gameKeys[#gameKeys + 1] = group.key
  end
  tickRows(out, gameKeys)
  out[#out + 1] = { type = "header", label = L["Other addons"] }
  out[#out + 1] = {
    type = "toggle",
    key = "screenOthersAll",
    label = L["Everything else that is shown"],
    desc = L["Every named window of another addon that shows when the key is pressed, whatever is ticked below."], -- luacheck: ignore 631 (a locale key stays one literal)
    default = false,
  }
  local names, seen = Screen.OtherFrames(), {}
  for _, name in ipairs(names) do
    seen[name] = true
  end
  for key, on in pairs(profile()) do
    local name = type(key) == "string" and on and key:match("^screenOther_(.+)$")
    if name and not seen[name] then
      seen[name] = true
      names[#names + 1] = name -- ticked earlier, not shown now (or not loaded): kept
    end
  end
  table.sort(names)
  local otherKeys = {}
  for _, name in ipairs(names) do
    out[#out + 1] = { type = "toggle", key = "screenOther_" .. name, label = name, default = false }
    otherKeys[#otherKeys + 1] = "screenOther_" .. name
  end
  if #otherKeys > 0 then
    tickRows(out, otherKeys)
  end
  return out
end
