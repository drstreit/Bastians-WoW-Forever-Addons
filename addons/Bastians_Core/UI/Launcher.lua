-- Launcher (core.md): the suite's minimap button and LibDataBroker launcher (left click the zone page
-- or the omnibox, right click a menu of the apps and the hub; ported from AHSyncGuide Core.lua), and
-- since 23.10.2026 one minimap button and launcher per app that has a window (owner, Forever: "all
-- main functions need separate minimap buttons").
local _, ns = ...
local B = ns.B
local L = ns.L
local S = ns.Style

local Launcher = { entries = {} }
B.UI.Launcher = Launcher

local button, menu

local function settings()
  return ns.core.db.profile.minimap
end

-- Apps add themselves: Bastians.UI.Launcher.Add(owner, { label, icon, onClick, order })
function Launcher.Add(owner, entry)
  entry.owner = owner
  entry.order = entry.order or 50
  Launcher.entries[#Launcher.entries + 1] = entry
  ns.track(owner, function()
    for i = #Launcher.entries, 1, -1 do
      if Launcher.entries[i] == entry then
        table.remove(Launcher.entries, i)
      end
    end
  end)
end

-- The apps with a window (a top-level module whose definition has `open`), by title.
local function windowApps()
  local out = {}
  for _, mod in B:IterateModules() do
    if not mod.parent and type(mod.def.open) == "function" then
      out[#out + 1] = mod
    end
  end
  table.sort(out, function(a, b)
    return tostring(a.title) < tostring(b.title)
  end)
  return out
end
Launcher.WindowApps = windowApps

local function openApp(mod)
  if mod:IsEnabled() then
    mod.def.open()
  else
    B:Say(L["%s is switched off."], mod.title)
  end
end

local function sortedEntries()
  local list = {}
  for _, e in ipairs(Launcher.entries) do
    list[#list + 1] = e
  end
  for _, mod in ipairs(windowApps()) do
    list[#list + 1] = {
      label = mod.title,
      order = 40,
      owner = mod,
      onClick = function()
        openApp(mod)
      end,
    }
  end
  list[#list + 1] = { label = L["Settings"], order = 90, onClick = B.UI.Hub.Toggle }
  table.sort(list, function(a, b)
    if a.order ~= b.order then
      return a.order < b.order
    end
    return a.label < b.label
  end)
  return list
end

local function showMenu(anchor)
  if not menu then
    menu = CreateFrame("Frame", "BastiansLauncherMenu", UIParent)
    menu:SetFrameStrata("TOOLTIP")
    menu:SetWidth(160)
    S.panel(menu, S.C.panel)
    menu.items = {}
    menu:SetScript("OnLeave", function(self)
      if not self:IsMouseOver() then
        self:Hide()
      end
    end)
  end
  local list = sortedEntries()
  for i, e in ipairs(list) do
    local b = menu.items[i]
    if not b then
      b = CreateFrame("Button", nil, menu)
      b:SetHeight(20)
      b.hl = S.fill(b, S.C.hover, "ARTWORK")
      b.hl:Hide()
      b.label = S.text(b, 12)
      b.label:SetPoint("LEFT", 8, 0)
      b.label:SetPoint("RIGHT", -8, 0)
      b:SetScript("OnEnter", function(self)
        self.hl:Show()
      end)
      b:SetScript("OnLeave", function(self)
        self.hl:Hide()
      end)
      b:SetScript("OnClick", function(self)
        menu:Hide()
        if self.entry.onClick then
          ns.safecall(self.entry.owner or ns.coreOwner, self.entry.onClick)
        end
      end)
      menu.items[i] = b
    end
    b.entry = e
    b.label:SetText((e.icon and B.UI.InlineTexture(e.icon, 12) or "") .. e.label)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 1, -(4 + (i - 1) * 20))
    b:SetPoint("RIGHT", -1, 0)
    b:Show()
  end
  for i = #list + 1, #menu.items do
    menu.items[i]:Hide()
  end
  menu:SetHeight(8 + #list * 20)
  menu:ClearAllPoints()
  menu:SetPoint("TOPRIGHT", anchor, "BOTTOMLEFT", 0, 0)
  menu:Show()
end
Launcher.ShowMenu = showMenu

-- Left click: the player's zone page (ADR 0013: "what can I do here" is one click away) when a
-- host shows pages and the zone is known, else the omnibox; right click: the menu.
local function onClick(_, mouse)
  if mouse == "RightButton" then
    showMenu(button or UIParent)
    return
  end
  local _, _, _, map = B.Coords.Player()
  if map and B:ShowPage("zone:" .. map) then
    return
  end
  B.UI.Omnibox.Toggle()
end

local function tooltip(tt)
  tt:AddLine("Bastian's " .. B.VERSION)
  local apps = 0
  for _, mod in B:IterateModules() do
    if not mod.parent and mod ~= ns.core and mod:IsEnabled() then
      apps = apps + 1
    end
  end
  S.TipLine(tt, string.format("%d %s", apps, L["apps enabled"]), "tipText")
  if B.UI.News then
    B.UI.News.TipLine(tt) -- "3 new things: /bastians news" (ADR 0021)
  end
  S.TipLine(tt, L["Click: search. Right click: menu. Drag: move the button."], "tipDim")
end

-- `cfg` holds the button's `angle` (degrees around the minimap) and `hide`.
local function place(btn, cfg)
  local angle = math.rad(cfg.angle or 200)
  local r = (Minimap:GetWidth() or 140) / 2 + 6
  btn:ClearAllPoints()
  btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

-- A round minimap button: icon, border, click, drag around the minimap (the angle kept in cfg).
local function makeButton(name, iconPath, click, tip, cfg)
  local b = CreateFrame("Button", name, Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  b.icon = b:CreateTexture(nil, "BACKGROUND")
  b.icon:SetSize(20, 20)
  B.UI.PaintIcon(b.icon, iconPath)
  b.icon:SetPoint("TOPLEFT", 7, -5)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetPoint("TOPLEFT")
  b:SetScript("OnClick", click)
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function(me)
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local s = Minimap:GetEffectiveScale()
      cfg().angle = math.deg(math.atan2(cy / s - my, cx / s - mx))
      place(me, cfg())
    end)
  end)
  b:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    tip(GameTooltip)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  place(b, cfg())
  return b
end

function Launcher.MinimapButton()
  if button then
    return button
  end
  button =
    makeButton("BastiansMinimapButton", "Interface\\Icons\\INV_Misc_Map_01", onClick, tooltip, settings)
  Launcher.UpdateVisibility()
  if B.UI.News then
    B.UI.News.UpdateDot() -- the dot of What's new (ADR 0021)
  end
  return button
end

-- The suite's button once it exists, never created by asking (What's new's dot).
function Launcher.Current()
  return button
end

-- ---------------------------------------------------------------------------------------------
-- One button per app with a window. An app may set `icon` in its
-- module definition; the defaults below are Blizzard icons both clients ship.
-- ---------------------------------------------------------------------------------------------

-- the suite's glyphs
Launcher.ICONS = {
  Browser = B.UI.IconTexture("trainer"), -- the book of everything
  Gold = B.UI.IconTexture("gold"),
  Map = B.UI.IconTexture("zone"),
  Quests = B.UI.IconTexture("quest"),
  Route = B.UI.IconTexture("route"),
}
Launcher.apps = {} -- module name -> its minimap button

-- The button settings of an app: { angle, hide }, in Core's profile.
function Launcher.AppSettings(name, slot)
  local p = ns.core.db.profile
  if type(p.minimapApps) ~= "table" then
    p.minimapApps = {}
  end
  local cfg = p.minimapApps[name]
  if type(cfg) ~= "table" then
    cfg = { angle = 230 + 24 * (slot or 0) } -- spread beside the suite's button (200 degrees)
    p.minimapApps[name] = cfg
  end
  return cfg
end

local function appTooltip(mod)
  return function(tt)
    tt:AddLine("Bastian's " .. tostring(mod.title))
    S.TipLine(tt, L["Click: open. Drag: move the button."], "tipDim")
    S.TipLine(tt, L["Its settings page hides the button."], "tipDim")
  end
end

-- Creates the missing app buttons and shows each by its setting and its app's state.
function Launcher.UpdateAppButtons()
  if not (ns.core and ns.core.db) then
    return
  end
  for slot, mod in ipairs(windowApps()) do
    local name = mod.name
    local cfg = Launcher.AppSettings(name, slot)
    local b = Launcher.apps[name]
    if not b and not cfg.hide then
      b = makeButton(
        "BastiansMinimapButton" .. name,
        mod.def.icon or Launcher.ICONS[name] or B.UI.IconTexture("other"),
        function()
          openApp(mod)
        end,
        appTooltip(mod),
        function()
          return Launcher.AppSettings(name, slot)
        end
      )
      Launcher.apps[name] = b
    end
    if b then
      if cfg.hide or not mod:IsEnabled() then
        b:Hide()
      else
        b:Show()
      end
    end
  end
end

-- Turns an app's button on or off (its settings page).
function Launcher.SetAppButton(name, on)
  Launcher.AppSettings(name).hide = not on or nil
  Launcher.UpdateAppButtons()
end

function Launcher.UpdateVisibility()
  if not button then
    return
  end
  if settings().hide then
    button:Hide()
  else
    button:Show()
  end
end

-- LibDataBroker launcher for broker displays (Titan, Bazooka, ElvUI data texts).
function Launcher.Broker()
  if Launcher.ldb then
    return Launcher.ldb
  end
  local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
  if not ldb then
    return nil
  end
  Launcher.ldb = ldb:NewDataObject("Bastians", {
    type = "launcher",
    icon = B.UI.IconTexture("open"), -- the suite's search
    label = "Bastian's",
    OnClick = onClick,
    OnTooltipShow = tooltip,
  })
  return Launcher.ldb
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_LOGIN")
  Launcher.MinimapButton()
  Launcher.Broker()
  Launcher.UpdateAppButtons()
end)
ns.on("BASTIANS_MODULE_STATE", function()
  Launcher.UpdateAppButtons() -- an app switched on or off, a load-on-demand app loaded
end)
ns.on("BASTIANS_SETTING_CHANGED", function(_, _, moduleName, key)
  if moduleName == "Core" and key == "minimapHide" then
    Launcher.UpdateVisibility()
  end
end)
