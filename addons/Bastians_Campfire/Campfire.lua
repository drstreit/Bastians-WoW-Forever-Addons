-- Bastian's Campfire, the module (campfire.md, plan-second-wave.md S5): the fire card, the camp
-- ring, the beacon for the group and the guild, the planner. `/bcamp` opens the planner.
local ADDON, ns = ...
local B = Bastians
local L = ns.L

local Campfire = {}
ns.Campfire = Campfire

local OPTIONS = {
  { type = "header", label = L["At the fire"] },
  { type = "toggle", key = "card", label = L["The flame: what the camp gives, the time until warm"] },
  {
    type = "toggle",
    key = "lightButton",
    label = L["A minimap button to light a fire when you carry a kit"],
  },
  {
    type = "toggle",
    key = "words",
    label = L["Words when you are warm, when it fades, when your features are ready"],
  },
  {
    type = "toggle",
    key = "ring",
    label = L["The camp ring in Bastian's Gestures (sit, offer a feature, thank the host, share the fire)"],
  },
  { type = "header", label = L["Sharing"] },
  {
    type = "toggle",
    key = "beacon",
    label = L["Share the fire with your group and guild; see theirs on the map"],
  },
  {
    type = "toggle",
    key = "public",
    label = L["Also on a public channel: share with everyone of the suite and see their fires"],
    desc = L["Off by default. Joins a hidden chat channel; fires from it come at most one per player in five minutes, twenty at once."], -- luacheck: ignore 631 (a locale key stays one literal)
  },
  {
    type = "edit",
    label = L["Block a name on the public channel (Enter; the same name again unblocks it)"],
    set = function(name)
      local blocked = ns.Public.Blocked(name)
      local now = ns.Public.Block(name, not blocked)
      if now ~= nil then
        B:Say(now and L["%s is blocked on the public channel."] or L["%s is no longer blocked."], name)
      end
    end,
  },
  {
    type = "note",
    text = function()
      local names = ns.Public.BlockedText()
      return names and string.format(L["Blocked: %s"], names) or L["Nobody is blocked."]
    end,
  },
  {
    type = "toggle",
    key = "chatPickup",
    label = L["A camp posted in chat with a map pin becomes a faded pin"],
  },
  { type = "header", label = L["The planner"] },
  {
    type = "toggle",
    key = "planner",
    label = L["The planner page: every feature, its buff at your level, who can place it"],
  },
  {
    type = "execute",
    key = "open",
    label = L["Open the planner"],
    icon = "open",
    func = function()
      Campfire.Open()
    end,
  },
  {
    type = "note",
    text = function()
      return L["Camp numbers come from Campfire Tooltips (GPLv3), read from client build 1.60.1.70009; what is not measured on the launch client shows as unknown."] -- luacheck: ignore 631 (a locale key stays one literal)
    end,
  },
}

-- The `camps` service (core-contracts §11): what other addons may read through Bastians.API.
local function camps()
  local svc = {}
  -- Nearby() -> { nearby, state, warmIn, left } of the player's fire now
  function svc.Nearby()
    local card = ns.Watch.Card()
    return { nearby = ns.Watch.State().nearby, state = card.state, warmIn = card.warmIn, left = card.left }
  end
  -- Buffs() -> { benefit key, ... } the camp buffs on the player
  function svc.Buffs()
    return ns.Watch.Card().have
  end
  -- Mine() -> { readyIn } the player's own features: seconds until they can be placed again, nil unknown
  function svc.Mine()
    return { readyIn = ns.Watch.ReadyIn() }
  end
  -- Fires() -> the number of shared fires on the map
  function svc.Fires()
    return #ns.Beacon.Fires()
  end
  return svc
end

local function apply()
  ns.Public.Apply()
  ns.CampRing.Apply()
  ns.Card.Refresh() -- the buttons follow
end

local mod = B:NewModule("Campfire", {
  news = ns.NEWS,
  addon = ADDON,
  icon = B.UI.IconTexture("app_campfire"),
  open = function()
    Campfire.Toggle()
  end,
  title = L["Campfire"],
  apiVersion = 1,
  optional = { "Bastians_Data", "Bastians_Map", "Bastians_Voice", "Bastians_Gestures", "Bastians_Alts" },
  defaults = {
    profile = {
      card = true,
      lightButton = true,
      words = true,
      ring = true,
      beacon = true,
      public = false, -- the public channel (decision B: off by default)
      chatPickup = true,
      planner = true,
    },
    char = { log = {} },
    global = { fires = {} }, -- `blocked` is made by Public.Attach (a default table would never save)
  },
  options = OPTIONS,
  OnEnable = function(self)
    ns.Watch.Attach(self)
    ns.Beacon.Attach(self)
    ns.Public.Attach(self)
    ns.Planner.Attach(self)
    ns.CampRing.Attach(self)
    ns.Offer.Attach(self)
    ns.Card.Attach(self)
    ns.Feed.Register(self)
    B:ProvideService(self, "camps", camps(), { priority = 100 })
    self:On("BASTIANS_CAMP_CHANGED", function()
      ns.Card.Refresh()
    end)
    self:On("BASTIANS_SETTING_CHANGED", function(_, _, module)
      if module == "Campfire" then
        apply()
      end
    end)
    self:On("BASTIANS_PLAY_CHANGED", apply)
  end,
  OnDisable = function()
    ns.Watch.Detach()
    ns.Beacon.Detach()
    ns.Public.Detach()
    ns.Offer.Detach()
    ns.Card.Detach()
  end,
})
Campfire.mod = mod
mod.Campfire = Campfire
mod.Camp = ns.Camp
mod.Model = ns.Model
mod.Watch = ns.Watch
mod.Card = ns.Card
mod.Offer = ns.Offer
mod.Beacon = ns.Beacon
mod.Public = ns.Public
mod.CampRing = ns.CampRing
mod.Planner = ns.Planner

-- the fire's state, the bags or the shared fires changed (the card, the feed, the planner)
B:DeclareMessage("BASTIANS_CAMP_CHANGED")
-- someone shared a fire: uiMapID, x, y (public, Bastians.API.EVENTS)
B:DeclareMessage("BASTIANS_CAMP_SHARED")
-- the camp's buffs landed: the host's name when the client gives it (public)
B:DeclareMessage("BASTIANS_CAMP_WARMED")
-- the warmth ends soon: seconds left (public)
B:DeclareMessage("BASTIANS_CAMP_FADING")

-- The planner in the suite's window, else the app's page in the hub.
function Campfire.Open()
  if not (mod.db.profile.planner and ns.Planner.Open()) then
    B.UI.Hub.Open("Campfire")
  end
  return true
end

-- The minimap button: the planner (or the page), or closed when it shows already (owner, retail
-- 02.11.2026: "opens but does not close").
function Campfire.Toggle()
  local views = B:GetService("views")
  if mod.db.profile.planner and views and views:IsShown(ns.Planner.VIEW) then
    views:Hide()
    return true
  end
  if B.UI.Hub.Shows("Campfire") then
    B.UI.Hub.TogglePage("Campfire")
    return true
  end
  return Campfire.Open()
end

-- `/bcamp` the planner; `/bcamp share` shares the fire; `/bcamp card` shows the card again;
-- `/bcamp block <name>` and `/bcamp unblock <name>` the public channel's block list.
function Campfire.Slash(text)
  local cmd, rest = string.match(text or "", "^%s*(%S*)%s*(.-)%s*$")
  if (cmd == "block" or cmd == "unblock") and rest ~= "" then
    local now = ns.Public.Block(rest, cmd == "block")
    B:Say(now and L["%s is blocked on the public channel."] or L["%s is no longer blocked."], rest)
    return now
  elseif cmd == "share" then
    return ns.Beacon.Share()
  elseif cmd == "card" then
    ns.Card.dismissed = nil
    ns.Card.Refresh()
    return true
  end
  return Campfire.Open()
end

SLASH_BASTIANSCAMPFIRE1 = "/bcamp"
SlashCmdList.BASTIANSCAMPFIRE = function(text)
  Campfire.Slash(text)
end
