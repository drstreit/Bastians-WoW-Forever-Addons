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

-- A switched-off app's button (Chat's "just says switched off, never on,
-- unclear what it even does"): its page in the hub, where its Enabled switch is.
function Launcher.OpenSwitchedOff(mod)
  B:Say(L["%s is switched off. Its page has the switch to turn it on."], mod.title)
  B.UI.Hub.Open(mod.name)
end

local function openApp(mod)
  if mod:IsEnabled() then
    mod.def.open()
  else
    Launcher.OpenSwitchedOff(mod)
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
local function onClick(self, mouse)
  if mouse == "RightButton" then
    showMenu(self or button or UIParent)
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
      cfg(true).angle = math.deg(math.atan2(cy / s - my, cx / s - mx)) -- a drag is written
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

-- The suite button's click and tooltip, for a button of an app that stands in for it (the badge
-- on Bastian's minimap, Map's Mini.lua).
Launcher.OnClick = onClick
Launcher.Tooltip = tooltip

-- ---------------------------------------------------------------------------------------------
-- LibDBIcon at runtime (ADR 0043 decision 4): when another addon loaded it (it is All Rights
-- Reserved, never bundled), the minimap buttons are LibDBIcon's, made from our LDB objects, so
-- collectors and Bazooka know them. Their place and switch stay in our settings: `cfg(create)`
-- returns { angle, hide } and LibDBIcon's `minimapPos` is our `angle` (degrees, the same circle).
-- ---------------------------------------------------------------------------------------------

function Launcher.DBIcon()
  return LibStub and LibStub("LibDBIcon-1.0", true) or nil
end

function Launcher.IconDB(cfg, default)
  return setmetatable({}, {
    __index = function(_, key)
      if key == "minimapPos" then
        return cfg().angle or default
      elseif key == "hide" then
        return cfg().hide
      end
      return nil
    end,
    __newindex = function(_, key, value)
      if key == "minimapPos" then
        cfg(true).angle = value -- a drag is written
      end
    end,
  })
end

local function dbiconButton(name, object, cfg, default)
  local lib = Launcher.DBIcon()
  if not (lib and object) then
    return nil
  end
  if not lib:IsRegistered(name) then
    lib:Register(name, object, Launcher.IconDB(cfg, default))
  end
  return lib:GetMinimapButton(name)
end

function Launcher.MinimapButton()
  if button then
    return button
  end
  button = dbiconButton("Bastians", Launcher.Broker(), settings, 200)
    or makeButton("BastiansMinimapButton", B.UI.IconTexture(B.UI.SUITE_ICON), onClick, tooltip, settings)
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
-- One button per app with a window, wearing the app's one icon: the
-- `icon` of its identity record in B.APPS (`B.UI.AppIcon`, plan-launch-review.md I1; before
-- 01.11.2026 a table here, the module's `icon` and a Blizzard default picked by three rules). A
-- module that is no app of the suite may still name `icon` in its definition.
-- ---------------------------------------------------------------------------------------------

Launcher.apps = {} -- module name -> its minimap button

-- The icon of an app's button: the identity's, else the module's own, else the grey "other".
function Launcher.IconOf(mod)
  return B.UI.AppIcon(mod.name) or mod.def.icon or B.UI.IconTexture("other")
end

-- The button settings of an app: { angle, hide }, in Core's profile.
-- Nothing is written until the player drags or hides a button (`create`): the saved file stays
-- as it was for a player who never touched them (30.10.2026, the round-trip test).
function Launcher.AppSettings(name, slot, create)
  local p = ns.core.db.profile
  local cfg = type(p.minimapApps) == "table" and p.minimapApps[name] or nil
  if type(cfg) ~= "table" then
    slot = slot or Launcher.SlotOf(name) or 0
    cfg = { angle = 230 + 24 * slot } -- spread beside the suite's button (200 degrees)
    if create then
      if type(p.minimapApps) ~= "table" then
        p.minimapApps = {}
      end
      p.minimapApps[name] = cfg
    end
  end
  return cfg
end

-- The slot of a button entry by name (its default place around the minimap).
function Launcher.SlotOf(name)
  for slot, entry in ipairs(Launcher.ButtonEntries()) do
    if entry.name == name then
      return slot
    end
  end
  return nil
end

local function appTooltip(title)
  return function(tt)
    tt:AddLine("Bastian's " .. tostring(title))
    S.TipLine(tt, L["Click: open. Drag: move the button."], "tipDim")
    S.TipLine(tt, L["Its settings page hides the button."], "tipDim")
  end
end

-- The buttons beside the suite's: one per app with a window, and the options window ("Options",
-- "add bastians option window as minimap button").
local function buttonEntries()
  local out = {}
  for _, mod in ipairs(windowApps()) do
    out[#out + 1] = {
      name = mod.name,
      mod = mod,
      title = mod.title,
      icon = Launcher.IconOf(mod),
      open = function()
        openApp(mod)
      end,
      shown = function()
        return mod:IsEnabled()
      end,
    }
    -- an app's further buttons (`def.minimapButtons = { { id, title, icon, open } }`; Bastian's
    -- Chat's Messenger, ), named after the app: "ChatMessenger"
    for _, extra in ipairs(mod.def.minimapButtons or {}) do
      out[#out + 1] = {
        name = mod.name .. extra.id,
        title = extra.title or extra.id,
        icon = extra.icon or mod.def.icon or B.UI.IconTexture("other"),
        open = function()
          if mod:IsEnabled() then
            extra.open()
          else
            Launcher.OpenSwitchedOff(mod)
          end
        end,
        shown = function()
          return mod:IsEnabled()
        end,
      }
    end
  end
  out[#out + 1] = {
    name = "Options",
    title = L["Options"],
    icon = B.UI.IconTexture("settings"),
    open = function()
      B.UI.Hub.Toggle()
    end,
    shown = function()
      return true
    end,
  }
  -- the welcome with the Wanderer and the Scholar, any time ("I miss the
  -- intro page with wanderer and scholar - add a minimap button to bring that on")
  out[#out + 1] = {
    name = "Welcome",
    title = L["Welcome"],
    icon = B.UI.IconTexture("tale"),
    open = function()
      local welcome = B.UI.Welcome
      if welcome.IsShown() then
        welcome.Hide()
      else
        welcome.Show()
      end
    end,
    shown = function()
      return B.UI.Welcome ~= nil
    end,
  }
  return out
end
Launcher.ButtonEntries = buttonEntries

-- The LDB object a LibDBIcon button is made from: the app's feed (ADR 0043), or a launcher of
-- its own for the options window.
function Launcher.EntryObject(entry)
  if entry.mod then
    return B.Feeds.ObjectFor(entry.mod)
  end
  local lib = LibStub and LibStub("LibDataBroker-1.1", true)
  if not lib then
    return nil
  end
  local name = "Bastian's " .. entry.name
  return lib:GetDataObjectByName(name)
    or lib:NewDataObject(name, {
      type = "launcher",
      label = tostring(entry.title),
      icon = entry.icon,
      OnClick = function()
        entry.open()
      end,
      OnTooltipShow = appTooltip(entry.title),
    })
end

-- Creates the missing app buttons and shows each by its setting and its app's state.
function Launcher.UpdateAppButtons()
  if not (ns.core and ns.core.db) then
    return
  end
  for slot, entry in ipairs(buttonEntries()) do
    local name = entry.name
    local cfg = Launcher.AppSettings(name, slot)
    local b = Launcher.apps[name]
    if not b and not cfg.hide then
      local function appCfg(create)
        return Launcher.AppSettings(name, slot, create)
      end
      b = dbiconButton("Bastian's " .. name, Launcher.EntryObject(entry), appCfg)
        or makeButton(
          "BastiansMinimapButton" .. name,
          entry.icon,
          entry.open,
          appTooltip(entry.title),
          appCfg
        )
      Launcher.apps[name] = b
    end
    if b then
      if cfg.hide or not entry.shown() then
        b:Hide()
      else
        b:Show()
      end
    end
  end
end

-- A count on an app's button (the Messenger's unread whispers): hidden at 0, "99+" above 99.
function Launcher.SetBadge(name, n)
  local b = Launcher.apps[name]
  if not b then
    return false
  end
  if not b.badge then
    b.badge = CreateFrame("Frame", nil, b)
    b.badge:SetSize(18, 13)
    b.badge:SetFrameLevel((b:GetFrameLevel() or 8) + 2)
    b.badge:SetPoint("TOPRIGHT", 2, 2)
    b.badge.bg = S.fill(b.badge, S.C.accent)
    b.badge.text = S.text(b.badge, 10, S.C.headerText)
    b.badge.text:SetPoint("CENTER")
  end
  n = tonumber(n) or 0
  b.badge:SetShown(n > 0)
  b.badge.text:SetText(n > 99 and "99+" or tostring(n))
  return true
end

-- Is an app's button shown by its setting?
function Launcher.AppButtonShown(name)
  return not Launcher.AppSettings(name).hide
end

-- Turns an app's button on or off (its settings page).
function Launcher.SetAppButton(name, on)
  Launcher.AppSettings(name, nil, true).hide = not on or nil
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
    icon = B.UI.IconTexture(B.UI.SUITE_ICON), -- the suite's one face
    label = "Bastian's",
    OnClick = onClick,
    OnTooltipShow = tooltip,
  })
  return Launcher.ldb
end

-- The suite's entry in the Addon Compartment (ADR 0043 decision 3), click and tooltip as its button.
function Launcher.Compartment()
  if Launcher.inCompartment ~= nil then
    return Launcher.inCompartment
  end
  Launcher.inCompartment = B.Compat.RegisterCompartment({
    text = "Bastian's",
    icon = B.UI.IconTexture(B.UI.SUITE_ICON),
    func = function(mouse)
      onClick(nil, mouse)
    end,
    onEnter = function(owner)
      GameTooltip:SetOwner(owner or UIParent, "ANCHOR_LEFT")
      tooltip(GameTooltip)
      GameTooltip:Show()
    end,
    onLeave = function()
      GameTooltip:Hide()
    end,
  }) and true or false
  return Launcher.inCompartment
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_LOGIN")
  Launcher.Broker()
  Launcher.MinimapButton()
  Launcher.UpdateAppButtons()
  Launcher.Compartment()
end)
ns.on("BASTIANS_MODULE_STATE", function()
  Launcher.UpdateAppButtons() -- an app switched on or off, a load-on-demand app loaded
end)
ns.on("BASTIANS_SETTING_CHANGED", function(_, _, moduleName, key)
  if moduleName == "Core" and key == "minimapHide" then
    Launcher.UpdateVisibility()
  end
end)
