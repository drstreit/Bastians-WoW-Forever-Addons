-- Item sets (core-contracts §7f, ADR 0043 decision 7): the apps' item lists for the bag addons
-- that are loaded: BetterBags categories, Baganator's junk coin and corner mark, AdiBags filters.
local _, ns = ...
local B = ns.B

local Bags = { defs = {}, order = {}, items = {}, pending = {}, bridges = {}, connected = {} }
B.Bags = Bags

Bags.DELAY = 1 -- seconds after the last trigger before a set is asked again
local KINDS = { category = true, junk = true, mark = true }

-- The last answer of a set: { [itemID] = true }, never nil (a bag addon's callback reads it).
function Bags.Items(id)
  return Bags.items[id] or {}
end

local function any(t)
  return next(t) ~= nil
end

local function push(def)
  for name, bridge in pairs(Bags.bridges) do
    if Bags.connected[name] then
      local ok, err = pcall(bridge.push, def, Bags.Items(def.id))
      if not ok then
        B:Log(def.owner, "warn", "item set %s to %s: %s", def.id, name, tostring(err))
      end
    end
  end
end

-- Asks the set's owner for its items, but only while a bag addon takes them (no work without a
-- reason, golden rule 7).
local function compute(def)
  Bags.pending[def.id] = nil
  if Bags.defs[def.id] ~= def or not any(Bags.connected) then
    return
  end
  local ok, set = ns.safecall(def.owner, def.items)
  Bags.items[def.id] = ok and type(set) == "table" and set or {}
  push(def)
end

local function schedule(def)
  local timer = Bags.pending[def.id]
  if timer then
    timer:Cancel()
  end
  Bags.pending[def.id] = C_Timer.NewTimer(Bags.DELAY, function()
    compute(def)
  end)
end

local byMessage, byEvent = {}, {}
local eventFrame = CreateFrame("Frame")

local function watch(def)
  for _, msg in ipairs(def.on or {}) do
    if not byMessage[msg] then
      byMessage[msg] = {}
      ns.on(msg, function()
        for id in pairs(byMessage[msg]) do
          local d = Bags.defs[id]
          if d then
            schedule(d)
          end
        end
      end)
    end
    byMessage[msg][def.id] = true
  end
  for _, event in ipairs(def.events or {}) do
    if not byEvent[event] then
      byEvent[event] = {}
      eventFrame:RegisterEvent(event)
    end
    byEvent[event][def.id] = true
  end
end

function B:RegisterItemSet(owner, def)
  if type(def) ~= "table" or type(def.id) ~= "string" or type(def.items) ~= "function" then
    error("RegisterItemSet: `id` and `items` (a function) are required", 2)
  end
  def.owner = owner
  def.kind = KINDS[def.kind] and def.kind or "category"
  def.label = tostring(def.label or def.id)
  if not Bags.defs[def.id] then
    Bags.order[#Bags.order + 1] = def.id
  end
  Bags.defs[def.id] = def
  watch(def)
  for name, bridge in pairs(Bags.bridges) do
    if Bags.connected[name] and bridge.add then
      pcall(bridge.add, def)
    end
  end
  schedule(def)
  ns.track(owner, function()
    if Bags.defs[def.id] == def then
      Bags.defs[def.id] = nil
      Bags.items[def.id] = {}
      push(def) -- the bag addon empties it
    end
  end)
end

function B:UpdateItemSet(_, id)
  local def = Bags.defs[id]
  if def then
    schedule(def)
  end
end

-- ---------------------------------------------------------------------------------------------
-- The bridges: `ready()` says whether the bag addon is there, `connect()` runs once, `add(def)`
-- once per set, `push(def, items)` after every answer. Each is one runtime contract we do not
-- control, so each runs in pcall and fails alone (golden rule 4).
-- ---------------------------------------------------------------------------------------------

local function ace(name)
  local lib = LibStub and LibStub("AceAddon-3.0", true)
  return lib and lib:GetAddon(name, true) or nil
end

local function itemExists(id)
  return C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(id) ~= nil
end

-- BetterBags (MIT, Forever's Camelot TOC): an ephemeral category per set from its item list.
Bags.bridges.BetterBags = {
  ready = function()
    local addon = ace("BetterBags")
    return addon ~= nil
      and addon:GetModule("Categories", true) ~= nil
      and addon:GetModule("Context", true) ~= nil
  end,
  connect = function(self)
    local addon = ace("BetterBags")
    self.categories, self.context, self.made = addon:GetModule("Categories"), addon:GetModule("Context"), {}
  end,
  add = function(def)
    local self = Bags.bridges.BetterBags
    if not self.made[def.label] then
      self.categories:CreateCategory(
        self.context:New("Bastians"),
        { name = def.label, itemList = {}, save = false }
      )
      self.made[def.label] = true
    end
  end,
  push = function(def, items)
    local self = Bags.bridges.BetterBags
    self.add(def)
    local ctx = self.context:New("Bastians")
    self.categories:WipeCategory(ctx, def.label)
    for id in pairs(items) do
      if itemExists(id) then -- BetterBags asserts on an item the client does not know
        self.categories:AddItemToCategory(ctx, id, def.label)
      end
    end
  end,
}

-- Baganator (no category API): a junk plugin for `junk` sets, a corner mark for the others.
Bags.MARK = "Interface\\AddOns\\Bastians_Core\\Icon"
Bags.bridges.Baganator = {
  ready = function()
    local api = rawget(_G, "Baganator") and rawget(_G, "Baganator").API
    return type(api) == "table" and type(api.RegisterJunkPlugin) == "function"
  end,
  connect = function(self)
    self.made = {}
  end,
  add = function(def)
    local self = Bags.bridges.Baganator
    if self.made[def.id] then
      return
    end
    self.made[def.id] = true
    local api = rawget(_G, "Baganator").API
    if def.kind == "junk" then
      api.RegisterJunkPlugin(def.label, "bastians_" .. def.id, function(_, _, itemID)
        return Bags.Items(def.id)[itemID] == true
      end)
    elseif type(api.RegisterCornerWidget) == "function" then
      api.RegisterCornerWidget(def.label, "bastians_" .. def.id, function(_, details)
        local id = details
          and (details.itemID or tonumber(string.match(details.itemLink or "", "item:(%d+)")))
        if not id then
          return nil -- not known yet
        end
        return Bags.Items(def.id)[id] == true
      end, function(button)
        local t = button:CreateTexture(nil, "OVERLAY")
        t:SetSize(12, 12)
        t:SetTexture(def.icon or Bags.MARK)
        return t
      end)
    end
  end,
  push = function(def)
    Bags.bridges.Baganator.add(def)
    local api = rawget(_G, "Baganator").API
    if type(api.RequestItemButtonsRefresh) == "function" then
      api.RequestItemButtonsRefresh()
    end
  end,
}

-- AdiBags (GPL-3.0; no TOC for our clients, it may run out of date): a filter per set.
Bags.bridges.AdiBags = {
  ready = function()
    local addon = ace("AdiBags")
    return addon ~= nil and type(addon.RegisterFilter) == "function"
  end,
  connect = function(self)
    self.addon, self.filters = ace("AdiBags"), {}
  end,
  add = function(def)
    local self = Bags.bridges.AdiBags
    if self.filters[def.id] then
      return
    end
    local filter = self.addon:RegisterFilter("Bastians_" .. def.id, 98, "ABEvent-1.0")
    filter.uiName, filter.uiDesc = def.label, def.label
    filter.Filter = function(_, slot)
      if slot and Bags.Items(def.id)[slot.itemId] then
        return def.label
      end
    end
    self.filters[def.id] = filter
  end,
  push = function(def)
    local self = Bags.bridges.AdiBags
    self.add(def)
    local filter = self.filters[def.id]
    if filter and filter.SendMessage then
      filter:SendMessage("AdiBags_FiltersChanged")
    end
  end,
}

-- Connects the bag addons loaded by now; again whenever an addon loads (one may come later).
function Bags.Connect()
  local new = false
  for name, bridge in pairs(Bags.bridges) do
    if not Bags.connected[name] then
      local ok, ready = pcall(bridge.ready)
      if ok and ready and pcall(bridge.connect, bridge) then
        Bags.connected[name] = true
        new = true
        for _, id in ipairs(Bags.order) do
          local def = Bags.defs[id]
          if def and bridge.add then
            pcall(bridge.add, def)
          end
        end
      end
    end
  end
  if new then
    for _, id in ipairs(Bags.order) do
      local def = Bags.defs[id]
      if def then
        schedule(def)
      end
    end
  end
end

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" or (event == "ADDON_LOADED" and ns.loggedIn) then
    Bags.Connect()
    return
  end
  for id in pairs(byEvent[event] or {}) do
    local def = Bags.defs[id]
    if def then
      schedule(def)
    end
  end
end)
