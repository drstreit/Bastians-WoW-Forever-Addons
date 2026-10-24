-- Bastian's Quests: the module (quests.md). Quest state and the `progress` service (B5.2) are in
-- State.lua, the window (B5.3) in Window.lua, Views.lua and Rows.lua, the layers, actions, detail
-- sections and the search provider (B5.4) in Registrations.lua.
local ADDON, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
local L = ns.L

local REFRESH_DELAY = 0.05 -- seconds; the client fires QUEST_LOG_UPDATE in bursts, one refresh per burst

local function data()
  return B:GetService("data")
end

local pendingAccepts = {} -- [questID] = expiry: the quests QUEST_ACCEPTED named, tracked once in the log
local acceptedBurst = false -- a QUEST_ACCEPTED without a usable id: the burst's added quests get tracked
local ACCEPT_TTL = 10 -- seconds a named quest may take to show up in the log

-- Auto-track on accept: an accepted quest goes on
-- the objective tracker, so the tracker (slim mode, "Tracked") shows it at once. The event names
-- the quest (retail: questID; the Classic shape questLogIndex, questID is taken too), and the
-- quest is tracked at the first refresh that finds it in the log, whichever of QUEST_ACCEPTED and
-- QUEST_LOG_UPDATE came first. Only accepted quests: the log that arrives late at login
-- (PLAYER_ENTERING_WORLD on retail) is never tracked wholesale. Setting `autoTrack`, default on.
local function autoTrack(self, diff)
  local ids = {}
  local now = GetTime()
  for id, expiry in pairs(pendingAccepts) do
    if ns.State.IsInLog(id) then
      ids[#ids + 1] = id
      pendingAccepts[id] = nil
    elseif expiry < now then
      pendingAccepts[id] = nil
    end
  end
  if acceptedBurst then
    for _, id in ipairs(diff and diff.added or {}) do
      ids[#ids + 1] = id
    end
  end
  acceptedBurst = false
  local n = 0
  for _, id in ipairs(ids) do
    if not ns.State.IsTracked(id) and B.Compat.SetQuestWatched(id, true) then
      n = n + 1
    end
  end
  if n > 0 then
    ns.Registrations.SyncTracked(self)
  end
end

-- One refresh per burst of quest events: diff the log, tell the suite which quests changed.
local function refresh(self)
  local diff = ns.State.Refresh()
  if self.db.profile.autoTrack ~= false then
    autoTrack(self, diff)
  else
    acceptedBurst = false
  end
  if diff then
    self:Fire("BASTIANS_QUESTS_CHANGED", diff.ids, diff)
  end
end

local function scheduleRefresh(self)
  self:Coalesce("refresh", REFRESH_DELAY, refresh)
end

local mod = B:NewModule("Quests", {
  news = ns.NEWS, -- What's new (ADR 0021)
  addon = ADDON,
  open = function()
    ns.Window.Toggle()
  end,
  title = L["Quests"],
  apiVersion = 1,
  data = { "quests", "world", "items" }, -- items: reward and quest item names
  optional = { "QuestieDB", "Spoken_Quests" },
  defaults = {
    profile = {
      window = {},
      tree = {},
      showDone = false,
      autoTrack = true, -- the tracker
      logTrackedOnly = false,
      logHideDone = false,
      journey = true, -- XP, gold, kills and quests per zone and session (S3)
      allKind = "any",
      allBand = "any",
      weightGold = 2, -- XP per silver of reward
      weightUnlock = 0.5, -- share of an unlocked quest's XP
      weightNext = 300, -- XP for leading into a planned next area
      timeSlay = 0.75, -- minutes per kill
      timeLoot = 1, -- minutes per looted item
      timeObject = 0.5, -- minutes per object
      timeEvent = 2, -- minutes per event or exploration
      timeDelivery = 1, -- minutes for a quest without objectives
    },
    char = { flightPaths = {}, hidden = {} }, -- hidden: the quests hidden from Do here (R3)
  },
  options = {
    { type = "header", label = L["The tracker (My quests)"] },
    {
      type = "toggle",
      key = "trackerFrame",
      label = L["Show My quests as its own frame (in place of the game's tracker)"],
      default = true,
    },
    {
      type = "toggle",
      key = "trackerHidesGame",
      label = L["Hide the game's objective tracker while the frame shows"],
      default = true,
    },
    { type = "toggle", key = "trackerLocked", label = L["Lock the frame in place"], default = false },
    {
      type = "toggle",
      key = "autoTrack",
      label = L["Track a new quest when it is accepted"],
      default = true,
    },
    { type = "toggle", key = "logTrackedOnly", label = L["Show only tracked quests"], default = false },
    {
      type = "toggle",
      key = "journey",
      label = L["Record the journey (XP, gold, kills and quests per zone and session)"],
      default = true,
    },
    {
      type = "toggle",
      key = "logHideDone",
      label = L["Hide complete quests (ready to hand in)"],
      default = false,
    },
    { type = "header", label = L["Recommendations"] },
    {
      type = "range",
      key = "weightGold",
      label = L["XP per silver of reward"],
      min = 0,
      max = 10,
      step = 0.5,
    },
    {
      type = "range",
      key = "weightUnlock",
      label = L["Share of an unlocked quest's XP"],
      min = 0,
      max = 1,
      step = 0.1,
    },
    {
      type = "range",
      key = "weightNext",
      label = L["XP for leading to the next area"],
      min = 0,
      max = 1000,
      step = 50,
    },
    { type = "range", key = "timeSlay", label = L["Minutes per kill"], min = 0.25, max = 3, step = 0.25 },
    {
      type = "range",
      key = "timeLoot",
      label = L["Minutes per looted item"],
      min = 0.25,
      max = 3,
      step = 0.25,
    },
    { type = "range", key = "timeObject", label = L["Minutes per object"], min = 0.25, max = 3, step = 0.25 },
    { type = "range", key = "timeEvent", label = L["Minutes per event"], min = 0.5, max = 10, step = 0.5 },
    {
      type = "range",
      key = "timeDelivery",
      label = L["Minutes for a delivery"],
      min = 0.5,
      max = 5,
      step = 0.5,
    },
  },
  OnEnable = function(self)
    ns.Logic.SetData(data())
    ns.State.Attach(self) -- facts, completed set, first snapshot; then the service, so consumers see state
    B:ProvideService(self, "progress", ns.Progress, { priority = 100 })
    ns.Window.Register(self)
    ns.Tracker.Register(self) -- the log view in its own frame (R6)
    ns.Registrations.Register(self)
    ns.Journey.Register(self) -- the journey per zone and session (S3)
    self:RegisterEvent("QUEST_LOG_UPDATE", scheduleRefresh)
    self:RegisterEvent("QUEST_ACCEPTED", function(mod, _, a, b)
      local id = tonumber(b) or tonumber(a) -- retail: questID; Classic shape: questLogIndex, questID
      if id then
        pendingAccepts[id] = GetTime() + ACCEPT_TTL
      else
        acceptedBurst = true -- no id: the refresh of this burst tracks what it added
      end
      scheduleRefresh(mod)
    end)
    self:RegisterEvent("QUEST_REMOVED", scheduleRefresh)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function(mod) -- retail delivers the completed list late
      ns.Journey.OnEnteringWorld()
      scheduleRefresh(mod)
    end)
    self:RegisterEvent("QUEST_TURNED_IN", function(mod, _, questID)
      ns.State.MarkDone(questID)
      ns.Journey.OnQuest(questID)
      scheduleRefresh(mod)
    end)
    self:RegisterEvent("PLAYER_LEVEL_UP", function(mod, _, level)
      ns.State.SetLevel(tonumber(level) or ns.State.facts.level)
      mod:Fire("BASTIANS_QUESTS_CHANGED", nil, { level = ns.State.facts.level }) -- every status may change
    end)
    self:RegisterEvent("TAXIMAP_OPENED", function(mod)
      local learned = ns.State.LearnFlightPaths()
      if learned > 0 then
        mod:Log("debug", "learned %d flight paths", learned)
      end
    end)
    -- the reward comparison (S7): a requested reward item arrived, or the gear changed
    local function rewardInfoChanged(mod)
      mod:Coalesce("rewardInfo", REFRESH_DELAY, function()
        mod:Fire("BASTIANS_REWARD_INFO_CHANGED")
      end)
    end
    self:RegisterEvent("ITEM_DATA_LOAD_RESULT", function(mod, _, itemID)
      local requested = ns.Registrations.requestedItems
      if requested[itemID] then
        requested[itemID] = nil
        rewardInfoChanged(mod)
      end
    end)
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", rewardInfoChanged)
    self:On("BASTIANS_DATA_LOADED", function(me)
      ns.Logic.SetData(data()) -- new records: rebuild the indexes lazily
      ns.Window.Schedule()
      me:Coalesce("layers", REFRESH_DELAY, ns.Registrations.OnDataLoaded)
    end)
    self:On("BASTIANS_QUESTS_CHANGED", function(me) -- one handler per message and module (Core)
      B:InvalidateEntities("quest") -- a quest's places follow its status (R7, the location filter)
      ns.Window.Schedule()
      me:Coalesce("layers", REFRESH_DELAY, ns.Registrations.OnChanged)
    end)
    self:On("BASTIANS_SERVICE_CHANGED", function(me, _, name)
      if name == "data" then
        ns.Logic.SetData(data())
        ns.Window.Schedule()
        me:Coalesce("layers", REFRESH_DELAY, ns.Registrations.OnDataLoaded)
      end
    end)
  end,
  OnDisable = function()
    ns.Window.HideOwn() -- the shared window (the Browser) stays; its Quests view says "not available"
    ns.Tracker.Hide() -- the frame goes, the game's tracker comes back
    ns.Journey.Close() -- the open journey entry is finished
  end,
})
ns.mod = mod
mod.Logic = ns.Logic -- the pure logic, reachable for tests and other views of this addon
mod.State = ns.State -- the cached quest state (State.lua)
mod.Tracker = ns.Tracker -- the tracker frame (Tracker.lua, R6)
mod.Journey = ns.Journey -- the journey per zone and session (Journey.lua, S3)
mod.Rows = ns.Rows -- the row builders (Rows.lua)
mod.Views = ns.Views -- the view builders (Views.lua)
mod.Recommend = ns.Recommend -- scoring and the next-area planner (Recommend.lua)
mod.Window = ns.Window -- the window (Window.lua)
