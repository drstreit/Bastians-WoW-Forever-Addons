-- Feeds (core-contracts §7f, ADR 0043): one LibDataBroker data source per app for the community's
-- displays (Titan Panel, Bazooka, EllesmereUI, ElvUI).
local _, ns = ...
local B = ns.B
local L = ns.L
local S = ns.Style

local Feeds = { defs = {}, objects = {}, pending = {}, ticks = {} }
B.Feeds = Feeds

Feeds.DELAY = 0.3 -- seconds after the last trigger before a text is read again
local PREFIX = "LibDataBroker_AttributeChanged_"

local function broker()
  return LibStub and LibStub("LibDataBroker-1.1", true)
end

-- "Bastian's Quests": the module's English name, so a display keeps its choice in every language;
-- an app whose identity names a `feed` (the Orbiter, module "Voice") is listed under that.
function Feeds.Name(mod)
  local settings = B.UI.Settings
  local app = settings and settings.AppByModule and settings.AppByModule(mod.name)
  return "Bastian's " .. (app and app.feed or mod.name)
end

-- Whether any display listens to the object's text (Titan and Bazooka per attribute, EllesmereUI
-- per object, some displays to every object): a feed's own timer runs only then.
function Feeds.Listened(name)
  local lib = broker()
  local events = lib and lib.callbacks and lib.callbacks.events
  if type(events) ~= "table" then
    return false
  end
  for _, key in ipairs({ PREFIX .. name .. "_text", PREFIX .. name, PREFIX .. "_text", PREFIX:sub(1, -2) }) do
    local list = rawget(events, key)
    if list and next(list) then
      return true
    end
  end
  return false
end

-- The feed's icon is the app's one icon (B.UI.AppIcon, the same as its minimap button); a feed
-- of a module that is no app of the suite may name its own.
local function iconOf(mod, def)
  return B.UI.AppIcon(mod.name) or (def and def.icon) or mod.def.icon or B.UI.IconTexture("other")
end

local refresh -- defined below

local function tip(mod)
  return function(tt)
    tt:AddLine("Bastian's " .. tostring(mod.title))
    local def = Feeds.defs[mod.name]
    if not mod:IsEnabled() or not def then
      S.TipLine(tt, string.format(L["%s is switched off."], mod.title), "tipDim")
      S.TipLine(tt, L["Click: its page, to switch it on."], "tipDim")
      return
    end
    if def.tooltip then
      ns.safecall(mod, def.tooltip, tt)
    end
    S.TipLine(tt, def.hint or L["Click: open. Right click: its settings."], "tipDim")
  end
end

local function click(mod)
  return function(_, button)
    local def = Feeds.defs[mod.name]
    if not mod:IsEnabled() or not def then
      B.UI.Launcher.OpenSwitchedOff(mod)
      return
    end
    if def.click then
      local ok, handled = ns.safecall(mod, def.click, button)
      if ok and handled then
        return
      end
    end
    if button == "RightButton" then
      B.UI.Hub.Open(mod.name)
    elseif type(mod.def.open) == "function" then
      mod.def.open()
    end
  end
end

-- The module's LDB object, made once (LibDataBroker cannot remove one) with every attribute set,
-- because Titan watches only the attributes an object had when it first saw it.
local function objectFor(mod, def)
  local obj = Feeds.objects[mod.name]
  if obj then
    return obj
  end
  local lib = broker()
  if not lib then
    return nil
  end
  local name = Feeds.Name(mod)
  obj = lib:GetDataObjectByName(name)
    or lib:NewDataObject(name, {
      type = "data source",
      text = "",
      label = tostring(mod.title),
      icon = iconOf(mod, def),
      tocname = mod.addon,
      OnClick = click(mod),
      OnTooltipShow = tip(mod),
    })
  Feeds.objects[mod.name] = obj
  return obj
end

Feeds.ObjectFor = objectFor -- the Launcher's LibDBIcon buttons, made before or after the feed

function B:FeedObject(name)
  return Feeds.objects[name]
end

-- Reads the feed's text now; with `every`, reads it again after that many seconds while a
-- display listens (the route's minutes count down without a message).
refresh = function(mod)
  Feeds.pending[mod.name] = nil
  local obj = Feeds.objects[mod.name]
  if not obj then
    return
  end
  local def = Feeds.defs[mod.name]
  if not mod:IsEnabled() then
    obj.text = L["off"]
    return
  elseif not def then
    obj.text = ""
    return
  end
  local ok, text = ns.safecall(mod, def.text)
  obj.text = ok and type(text) == "string" and text or "" -- unknown stays empty, never 0
  if def.every and not Feeds.ticks[mod.name] then
    local okEvery, seconds = ns.safecall(mod, def.every)
    if okEvery and type(seconds) == "number" and seconds > 0 and Feeds.Listened(Feeds.Name(mod)) then
      Feeds.ticks[mod.name] = C_Timer.NewTimer(seconds, function()
        Feeds.ticks[mod.name] = nil
        refresh(mod)
      end)
    end
  end
end

-- Coalesced: a burst of messages reads the text once, DELAY after the last.
local function schedule(mod)
  local timer = Feeds.pending[mod.name]
  if timer then
    timer:Cancel()
  end
  Feeds.pending[mod.name] = C_Timer.NewTimer(Feeds.DELAY, function()
    ns.safecall(mod, refresh, mod)
  end)
end

-- One Core subscription per message or event, shared by every feed that names it.
local byMessage, byEvent = {}, {}
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event)
  for name in pairs(byEvent[event] or {}) do
    local mod = ns.modules[name]
    if mod and Feeds.defs[name] then
      schedule(mod)
    end
  end
end)

local function watch(mod, def)
  for _, msg in ipairs(def.on or {}) do
    if not byMessage[msg] then
      byMessage[msg] = {}
      ns.on(msg, function()
        for name in pairs(byMessage[msg]) do
          local m = ns.modules[name]
          if m and Feeds.defs[name] then
            schedule(m)
          end
        end
      end)
    end
    byMessage[msg][mod.name] = true
  end
  for _, event in ipairs(def.events or {}) do
    if not byEvent[event] then
      byEvent[event] = {}
      eventFrame:RegisterEvent(event)
    end
    byEvent[event][mod.name] = true
  end
end

local function unwatch(mod)
  for _, list in pairs(byMessage) do
    list[mod.name] = nil
  end
  for _, list in pairs(byEvent) do
    list[mod.name] = nil
  end
end

function B:RegisterFeed(owner, def)
  if type(def) ~= "table" or type(def.text) ~= "function" then
    error("RegisterFeed: `text` (a function) is required", 2)
  end
  local mod = owner.parent and ns.modules[owner.name:match("^[^%.]+")] or owner -- one per app
  unwatch(mod)
  Feeds.defs[mod.name] = def
  watch(mod, def)
  local obj = objectFor(mod, def)
  if obj and def.icon then
    obj.icon = def.icon
  end
  refresh(mod)
  ns.track(owner, function()
    if Feeds.defs[mod.name] == def then
      Feeds.defs[mod.name] = nil
      unwatch(mod)
      local tick = Feeds.ticks[mod.name]
      if tick then
        tick:Cancel()
        Feeds.ticks[mod.name] = nil
      end
    end
  end)
  return obj
end

-- A switched-off app's object stays (LibDataBroker cannot remove one) and says "off".
ns.on("BASTIANS_MODULE_STATE", function(_, _, name, enabled)
  local mod = ns.modules[name]
  if mod and not mod.parent and Feeds.objects[name] and not (enabled and Feeds.defs[name]) then
    refresh(mod)
  end
end)

function B:UpdateFeed(owner)
  local mod = owner.parent and ns.modules[owner.name:match("^[^%.]+")] or owner
  if Feeds.objects[mod.name] then
    schedule(mod)
  end
end

-- The events for WeakAuras and ForeverAuras (ADR 0043 decision 5) are the public API's
-- (API.lua, ADR 0044): one list for both.
