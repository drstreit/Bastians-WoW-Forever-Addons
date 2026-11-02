-- EllesmereUI (ADR 0043 decision 6): a "Bastian's" section in its options when it is loaded, with
-- the minimap-button switches, where the feeds are, and the way to the suite's own settings.
local _, ns = ...
local B = ns.B
local L = ns.L

local Ellesmere = {}
B.UI.Ellesmere = Ellesmere

local function launcher()
  return B.UI.Launcher
end

-- The suite's button and one per app with a window, as the settings hub has them.
local function buildButtons(parent, y)
  local W = rawget(_G, "EllesmereUI").Widgets
  local _, h = W:SectionHeader(parent, string.upper(L["Minimap buttons"]), y)
  y = y - h
  _, h = W:Toggle(parent, "Bastian's", y, function()
    return not ns.core.db.profile.minimap.hide
  end, function(on)
    ns.core.db.profile.minimap.hide = not on
    launcher().UpdateVisibility()
  end)
  y = y - h
  for _, entry in ipairs(launcher().ButtonEntries()) do
    _, h = W:Toggle(parent, tostring(entry.title), y, function()
      return not launcher().AppSettings(entry.name).hide
    end, function(on)
      launcher().SetAppButton(entry.name, on)
    end)
    y = y - h
  end
  return y
end

function Ellesmere.Spec()
  return {
    label = "Bastian's",
    modules = {
      {
        key = "Suite",
        title = L["Bastian's Suite"],
        description = L["Add a Broker Plugin block to a data bar and pick a Bastian's feed."],
        pages = { L["Buttons"] },
        buildPage = function(_, parent, yOffset)
          local y = buildButtons(parent, yOffset)
          local W = rawget(_G, "EllesmereUI").Widgets
          local _, h = W:SectionHeader(parent, string.upper(L["Settings"]), y)
          y = y - h
          _, h = W:WideButton(parent, L["Open Bastian's settings"], y, function()
            B.UI.Hub.Open()
          end)
          y = y - h
          return math.abs(y)
        end,
      },
    },
  }
end

-- Registers once, when EllesmereUI is there (a plugin id is taken once per session).
function Ellesmere.Register()
  local eui = rawget(_G, "EllesmereUI")
  if Ellesmere.registered or type(eui) ~= "table" or type(eui.RegisterPlugin) ~= "function" then
    return Ellesmere.registered or false
  end
  local ok, done = pcall(eui.RegisterPlugin, "Bastians_Core", Ellesmere.Spec())
  Ellesmere.registered = ok and done == true
  return Ellesmere.registered
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_LOGIN")
  Ellesmere.Register()
end)
