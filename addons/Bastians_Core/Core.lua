-- Module system, event dispatch, message bus, Coalesce and error isolation (core-contracts §2, §3, §14).
local _, ns = ...
local B = ns.B
local L = ns.L

local ERROR_LIMIT, ERROR_WINDOW = 10, 60 -- more than 10 errors in 60 s disables a module for the session

local Module = {}
Module.__index = Module
ns.Module = Module

ns.loadedAddons = {}
ns.loggedIn = false

-- ---------------------------------------------------------------------------------------------
-- Error isolation: every callback into a module runs through ns.safecall
-- ---------------------------------------------------------------------------------------------

local function traceback(err)
  return tostring(err) .. "\n" .. (debugstack and debugstack(3, 5, 0) or "")
end

function ns.noteError(owner, err)
  B:Log(owner, "error", "%s", tostring(err))
  if type(owner) ~= "table" or not owner.errors then
    return
  end
  local now = GetTime()
  local list = owner.errors
  list[#list + 1] = now
  while list[1] and now - list[1] > ERROR_WINDOW do
    table.remove(list, 1)
  end
  if #list > ERROR_LIMIT and owner.state == "enabled" then
    owner.disabledByErrors = true
    owner:Disable("errors")
    B:Say(
      L["%s was disabled after %d errors in %d seconds, see /bastians log"],
      owner.title,
      ERROR_LIMIT,
      ERROR_WINDOW
    )
  end
end

local function pack(...)
  return { n = select("#", ...), ... }
end

-- ns.safecall(owner, fn, ...) -> ok, results... ; logs and counts the error against owner on failure.
function ns.safecall(owner, fn, ...)
  local args = pack(...)
  local ok, a, b, c, d = xpcall(function()
    return fn(unpack(args, 1, args.n))
  end, traceback)
  if not ok then
    ns.noteError(owner, a)
    return false
  end
  return true, a, b, c, d
end

-- Perf labels (core-contracts §15, Map spent 82 ms a second and nobody
-- could say on what): what a timed callback is ("event X", "bus X", "timer key", "layer id", ...),
-- so /bastians perf names the costliest handlers of each module. Weak keys: closures go.
ns.perfLabels = setmetatable({}, { __mode = "k" })
function ns.label(fn, text)
  if type(fn) == "function" and ns.perfLabels[fn] == nil then
    ns.perfLabels[fn] = text
  end
  return fn
end

-- ---------------------------------------------------------------------------------------------
-- Owner tracking: anything a module registers hands Core an undo function
-- ---------------------------------------------------------------------------------------------

function ns.track(owner, undo)
  owner.undo[#owner.undo + 1] = undo
  return undo
end

-- ---------------------------------------------------------------------------------------------
-- Events: one frame for the suite; handlers in registration order, safe (un)register while dispatching
-- ---------------------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {} -- event -> array of { owner, fn, active }
local dispatching = 0
local dirty = {}

local function compact(event)
  local list = handlers[event]
  if not list then
    return
  end
  if dispatching > 0 then
    dirty[event] = true
    return
  end
  local kept = {}
  for _, h in ipairs(list) do
    if h.active then
      kept[#kept + 1] = h
    end
  end
  if #kept == 0 then
    handlers[event] = nil
    eventFrame:UnregisterEvent(event)
  else
    handlers[event] = kept
  end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if not list then
    return
  end
  dispatching = dispatching + 1
  for i = 1, #list do
    local h = list[i]
    if h.active then
      ns.safecall(h.owner, h.fn, h.owner, event, ...)
    end
  end
  dispatching = dispatching - 1
  if dispatching == 0 and next(dirty) then
    for ev in pairs(dirty) do
      dirty[ev] = nil
      compact(ev)
    end
  end
end)

function Module:RegisterEvent(event, fn)
  fn = fn or self[event]
  if type(fn) ~= "function" then
    error(("RegisterEvent(%s): handler missing"):format(tostring(event)), 2)
  end
  if self.eventHandlers[event] then
    self:UnregisterEvent(event)
  end
  local list = handlers[event]
  if not list then
    list = {}
    handlers[event] = list
    eventFrame:RegisterEvent(event)
  end
  ns.label(fn, "event " .. event)
  local h = { owner = self, fn = fn, active = true }
  list[#list + 1] = h
  self.eventHandlers[event] = h
end

function Module:UnregisterEvent(event)
  local h = self.eventHandlers[event]
  if not h then
    return
  end
  h.active = false
  self.eventHandlers[event] = nil
  compact(event)
end

function Module:IsEventRegistered(event)
  return self.eventHandlers[event] ~= nil
end

-- ---------------------------------------------------------------------------------------------
-- Message bus: synchronous, subscription order; unknown message names are logged once (typo guard)
-- ---------------------------------------------------------------------------------------------

B.Messages = {} -- set of known bus messages, filled from the catalogue (core-contracts §16) below
local subscribers = {} -- msg -> array of { owner, fn, active }
local warned = {}

-- Core's own identity for callbacks it runs itself (registries, search job). It is never disabled.
ns.coreOwner = { name = "Core", title = "Core", errors = {}, undo = {}, jobs = {} }

-- Internal subscription for Core files (apps use mod:On). Not removable; Core lives as long as the UI.
function ns.on(msg, fn)
  local list = subscribers[msg]
  if not list then
    list = {}
    subscribers[msg] = list
  end
  list[#list + 1] = { owner = ns.coreOwner, fn = fn, active = true }
end

function B:DeclareMessage(name)
  B.Messages[name] = true
end

for _, name in ipairs({
  "BASTIANS_ENTITY_FOCUSED",
  "BASTIANS_PAGE_SHOWN",
  "BASTIANS_LAYER_CHANGED",
  "BASTIANS_SETTING_CHANGED",
  "BASTIANS_MODULE_STATE",
  "BASTIANS_PLAYER_MOVED_ZONE",
  "BASTIANS_QUESTS_CHANGED",
  "BASTIANS_TRACKED_CHANGED",
  "BASTIANS_ROUTE_CHANGED",
  "BASTIANS_PRICES_UPDATED",
  "BASTIANS_DATA_LOADED",
  "BASTIANS_REGISTRY_CHANGED",
  "BASTIANS_SERVICE_CHANGED",
  "BASTIANS_ENTITY_CHANGED",
  "BASTIANS_PROFILE_CHANGED",
  "BASTIANS_THEME_CHANGED",
}) do
  B:DeclareMessage(name)
end

-- The focus (ADR 0013 D): the one entity map and Browser select together. Bastians:Focus(ref, ctx)
-- stores it and fires BASTIANS_ENTITY_FOCUSED(ref, ctx) every time (a pin click on the focused
-- entity opens its page again); nil clears it, with the message carrying nil.
local focused

function B:Focus(ref, ctx)
  focused = ref
  B:Fire("BASTIANS_ENTITY_FOCUSED", ref, ctx)
end

function B:Focused()
  return focused
end

function B:Fire(msg, ...)
  if not B.Messages[msg] and not warned[msg] then
    warned[msg] = true
    B:Log(nil, "warn", "bus message %s is not in the catalogue (core-contracts §16)", tostring(msg))
  end
  local list = subscribers[msg]
  if not list then
    return
  end
  local snapshot = {}
  for i, s in ipairs(list) do
    snapshot[i] = s
  end
  for _, s in ipairs(snapshot) do
    if s.active then
      ns.safecall(s.owner, s.fn, s.owner, msg, ...)
    end
  end
end

function Module:Fire(msg, ...)
  B:Fire(msg, ...)
end

function Module:On(msg, fn)
  if type(fn) ~= "function" then
    error(("On(%s): handler missing"):format(tostring(msg)), 2)
  end
  if self.busHandlers[msg] then
    self:Off(msg)
  end
  local list = subscribers[msg]
  if not list then
    list = {}
    subscribers[msg] = list
  end
  ns.label(fn, "bus " .. msg)
  local s = { owner = self, fn = fn, active = true }
  list[#list + 1] = s
  self.busHandlers[msg] = s
end

function Module:Off(msg)
  local s = self.busHandlers[msg]
  if not s then
    return
  end
  s.active = false
  self.busHandlers[msg] = nil
  local list = subscribers[msg]
  for i = #list, 1, -1 do
    if list[i] == s then
      table.remove(list, i)
    end
  end
  if #list == 0 then
    subscribers[msg] = nil
  end
end

-- ---------------------------------------------------------------------------------------------
-- Coalesce: run fn once, delay seconds after the last call with the same key (debounce)
-- ---------------------------------------------------------------------------------------------

function Module:Coalesce(key, delay, fn)
  local pending = self.coalesce
  if pending[key] then
    pending[key]:Cancel()
  end
  local mod = self
  ns.label(fn, "timer " .. tostring(key))
  pending[key] = C_Timer.NewTimer(delay, function()
    pending[key] = nil
    ns.safecall(mod, fn, mod)
  end)
end

-- ---------------------------------------------------------------------------------------------
-- Modules
-- ---------------------------------------------------------------------------------------------

function Module:Log(level, fmt, ...)
  B:Log(self, level, fmt, ...)
end

function Module:GetDB()
  return self.db
end

function Module:IsEnabled()
  return self.state == "enabled"
end

-- The enable switch lives in the module's profile (reserved key `enabled`, default true).
function Module:IsSwitchOn()
  return self.db ~= nil and self.db.profile.enabled ~= false
end

function Module:Enable()
  if self.state == "enabled" then
    return true
  end
  if self.state == "registered" then
    return false -- saved variables not available yet; auto-enabled after initialization
  end
  if self.parent and self.parent.state ~= "enabled" then
    return false
  end
  self.db.profile.enabled = true
  self.disabledByErrors = nil
  self.state = "enabled"
  if self.OnEnable then
    ns.safecall(self, self.OnEnable, self)
  end
  B:Fire("BASTIANS_MODULE_STATE", self.name, true)
  for _, child in ipairs(self.children) do
    ns.autoEnable(child)
  end
  return true
end

-- reason: nil = the player switched it off (persisted); "errors", "parent", "profile" = session only.
function Module:Disable(reason)
  if self.state ~= "enabled" then
    return false
  end
  for _, child in ipairs(self.children) do
    child:Disable("parent")
  end
  for i = #self.undo, 1, -1 do
    local undo = self.undo[i]
    self.undo[i] = nil
    pcall(undo)
  end
  for event in pairs(self.eventHandlers) do
    self:UnregisterEvent(event)
  end
  for msg in pairs(self.busHandlers) do
    self:Off(msg)
  end
  for key, timer in pairs(self.coalesce) do
    timer:Cancel()
    self.coalesce[key] = nil
  end
  B.Jobs:CancelAll(self)
  self.state = "disabled"
  if reason == nil then
    self.db.profile.enabled = false
  end
  if self.OnDisable then
    ns.safecall(self, self.OnDisable, self)
  end
  B:Fire("BASTIANS_MODULE_STATE", self.name, false)
  return true
end

function ns.initializeModule(mod)
  if mod.state ~= "registered" then
    return
  end
  ns.DB.Attach(mod)
  mod.state = "initialized"
  if mod.OnInitialize then
    ns.safecall(mod, mod.OnInitialize, mod)
  end
  for _, child in ipairs(mod.children) do
    ns.initializeModule(child)
  end
end

function ns.autoEnable(mod)
  if (mod.state == "initialized" or mod.state == "disabled") and mod:IsSwitchOn() then
    if mod.disabledByErrors then
      return
    end
    mod:Enable()
  end
end

local RESERVED = { name = true, state = true, db = true, parent = true, children = true }

-- Bastians:NewModule(name, def) ; see core-contracts §2. Returns nil (and logs) if Core is too old.
function B:NewModule(name, def)
  if
    type(name) ~= "string"
    or not name:match("^[%w_]+[%w_%.]*$")
    or name:match("%.%.")
    or name:match("%.$")
  then
    error(("NewModule: bad module name %q"):format(tostring(name)), 2)
  end
  if ns.modules[name] then
    error(("NewModule: module %s already exists"):format(name), 2)
  end
  def = def or {}
  if (def.apiVersion or 1) > B.API_VERSION then
    B:Log(
      nil,
      "error",
      "module %s needs Core API %d, this Core has %d; not loaded",
      name,
      def.apiVersion,
      B.API_VERSION
    )
    return nil
  end
  local parentName = name:match("^(.*)%.[^%.]+$")
  local parent = parentName and ns.modules[parentName] or nil
  if parentName and not parent then
    error(("NewModule: parent module %s of %s does not exist"):format(parentName, name), 2)
  end
  local addon = def.addon or (parent and parent.addon)
  if type(addon) ~= "string" then
    error(("NewModule(%s): def.addon (the addon folder name) is required"):format(name), 2)
  end
  local mod = setmetatable({
    name = name,
    shortName = name:match("[^%.]+$"),
    title = def.title or (parent and name:match("[^%.]+$")) or name,
    addon = addon,
    def = def,
    parent = parent,
    children = {},
    state = "registered",
    eventHandlers = {},
    busHandlers = {},
    coalesce = {},
    undo = {},
    errors = {},
    defaults = def.defaults,
    options = def.options,
    migrations = def.migrations,
    data = def.data,
    optional = def.optional,
    OnInitialize = def.OnInitialize,
    OnEnable = def.OnEnable,
    OnDisable = def.OnDisable,
  }, Module)
  for k, v in pairs(def) do
    if type(v) == "function" and mod[k] == nil and not RESERVED[k] then
      mod[k] = v -- extra methods declared in the definition
    end
  end
  ns.modules[name] = mod
  ns.moduleList[#ns.moduleList + 1] = mod
  ns.byAddon[addon] = ns.byAddon[addon] or {}
  table.insert(ns.byAddon[addon], mod)
  if parent then
    parent.children[#parent.children + 1] = mod
  end
  if ns.loadedAddons[addon] then -- created after its addon loaded: catch up with the lifecycle
    ns.initializeModule(mod)
    if ns.loggedIn then
      ns.autoEnable(mod)
    end
  end
  return mod
end

function B:GetModule(name)
  return ns.modules[name]
end

function B:IterateModules()
  return ipairs(ns.moduleList)
end

-- ---------------------------------------------------------------------------------------------
-- Lifecycle events
-- ---------------------------------------------------------------------------------------------

local lifecycle = CreateFrame("Frame")
lifecycle:RegisterEvent("ADDON_LOADED")
lifecycle:RegisterEvent("PLAYER_LOGIN")
lifecycle:RegisterEvent("PLAYER_LOGOUT")
lifecycle:SetScript("OnEvent", function(_, event, addonName)
  if event == "ADDON_LOADED" then
    ns.loadedAddons[addonName] = true
    B.Deliver() -- generated files that ran before their consumer (Init.lua)
    if addonName == ns.ADDON then
      ns.DB.InitCore()
      ns.Compat.verify()
    end
    for _, mod in ipairs(ns.byAddon[addonName] or {}) do
      if not mod.parent then
        ns.initializeModule(mod)
        if ns.loggedIn then
          ns.autoEnable(mod)
        end
      end
    end
  elseif event == "PLAYER_LOGIN" then
    ns.loggedIn = true
    for _, mod in ipairs(ns.moduleList) do
      if not mod.parent then
        ns.autoEnable(mod)
      end
    end
    if B.UI.News then
      B.UI.News.Login() -- before the companions note: did the suite run here before (ADR 0021)
    end
    if B.UI.Settings and B.UI.Settings.NoteCompanions then
      B.UI.Settings.NoteParts() -- every login while a required part is missing (ADR 0015)
      B.UI.Settings.NoteCompanions() -- once at the first start and after every update
    end
  elseif event == "PLAYER_LOGOUT" then
    ns.DB.PruneAll()
  end
end)
