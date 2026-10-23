-- Quest state (quests.md "Quest-log refresh"): the cached quest log, the completed set, the character
-- facts and the learned flight paths. Reads the client only through Bastians.Compat; diffs on every
-- refresh so that consumers re-evaluate only the quests that changed (acceptance 3: 20 quests under 2 ms).
local _, ns = ...
local B = Bastians

local State = {}
ns.State = State

State.log = {} -- [questID] = { index, questID, title, level, header, isComplete, readyForTurnIn, objectives }
State.order = {} -- questIDs in quest log order
State.count = 0
State.done = {} -- [questID] = true, from the completed list at login plus every QUEST_TURNED_IN
State.doneLoaded = false -- false until the client answered the completed list with at least one entry
State.facts = { level = nil, raceID = nil, classID = nil, faction = nil }
State.flightPaths = {} -- [nodeID or name] = { name, map, x, y }, persisted per character (db.char)
State.tracked = {} -- [questID] = true for quests on the objective tracker
State.hidden = {} -- [questID] = true for quests the player hid from Do here (R3, per character)

function State.IsHidden(questID)
  return State.hidden[questID] == true
end

function State.SetHidden(questID, on)
  State.hidden[questID] = on and true or nil
end

local DONE_RETRIES = 3 -- how often an empty completed list is asked again (retail answers it late)
local doneAttempts = 0

-- ---------------------------------------------------------------------------------------------
-- Character facts and the completed set
-- ---------------------------------------------------------------------------------------------

function State.ReadFacts()
  local f = B.Compat.GetPlayerFacts()
  local facts = State.facts
  facts.level, facts.raceID, facts.classID, facts.faction = f.level, f.raceID, f.classID, f.faction
  return facts
end

function State.SetLevel(level)
  State.facts.level = level
end

-- Reads the completed list; returns how many quests it holds. An empty answer is retried on later
-- refreshes because retail delivers the list after PLAYER_LOGIN.
function State.LoadDone()
  local ids = B.Compat.GetCompletedQuestIDs()
  doneAttempts = doneAttempts + 1
  for _, id in ipairs(ids) do
    State.done[id] = true
  end
  if #ids > 0 then
    State.doneLoaded = true
  end
  return #ids
end

function State.MarkDone(questID)
  if questID then
    State.done[questID] = true
  end
end

-- ---------------------------------------------------------------------------------------------
-- Quest log snapshot and diff
-- ---------------------------------------------------------------------------------------------

local function sameObjectives(a, b)
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    local x, y = a[i], b[i]
    if
      x.text ~= y.text
      or x.finished ~= y.finished
      or x.fulfilled ~= y.fulfilled
      or x.required ~= y.required
    then
      return false
    end
  end
  return true
end

local function sameEntry(a, b)
  return a.title == b.title
    and a.level == b.level
    and a.header == b.header
    and a.isComplete == b.isComplete
    and a.readyForTurnIn == b.readyForTurnIn
    and sameObjectives(a.objectives, b.objectives)
end

-- Re-reads the quest log through Compat and diffs it against the cache. Returns nil when nothing
-- changed, else { added, removed, changed, ids } (arrays of questIDs; ids = all three together).
-- Unchanged quests keep their cached entry table (only `index` is refreshed), so consumers may hold
-- on to entries and compare them by identity.
function State.Refresh()
  if not State.doneLoaded and doneAttempts < DONE_RETRIES then
    State.LoadDone()
  end
  local entries = B.Compat.GetQuestLogEntries()
  local log, order = State.log, State.order
  local added, removed, changed = {}, {}, {}
  local seen = {}
  local newOrder = {}
  for i, entry in ipairs(entries) do
    local id = entry.questID
    seen[id] = true
    newOrder[i] = id
    local old = log[id]
    if not old then
      log[id] = entry
      added[#added + 1] = id
    elseif sameEntry(old, entry) then
      old.index = entry.index
    else
      log[id] = entry
      changed[#changed + 1] = id
    end
  end
  for _, id in ipairs(order) do
    if not seen[id] then
      log[id] = nil
      removed[#removed + 1] = id
    end
  end
  State.order = newOrder
  State.count = #newOrder
  if #added == 0 and #removed == 0 and #changed == 0 then
    return nil
  end
  local ids = {}
  for _, list in ipairs({ added, removed, changed }) do
    for _, id in ipairs(list) do
      ids[#ids + 1] = id
    end
  end
  return { added = added, removed = removed, changed = changed, ids = ids }
end

function State.Entry(questID)
  return State.log[questID]
end

-- Re-reads the tracked set; returns the diff as { { questID, tracked }, ... } or nil when unchanged.
function State.RefreshTracked()
  local now = {}
  for _, id in ipairs(B.Compat.GetWatchedQuestIDs()) do
    now[id] = true
  end
  local changes = {}
  for id in pairs(State.tracked) do
    if not now[id] then
      changes[#changes + 1] = { id, false }
    end
  end
  for id in pairs(now) do
    if not State.tracked[id] then
      changes[#changes + 1] = { id, true }
    end
  end
  State.tracked = now
  if #changes == 0 then
    return nil
  end
  table.sort(changes, function(a, b)
    return a[1] < b[1]
  end)
  return changes
end

function State.IsTracked(questID)
  return State.tracked[questID] == true
end

function State.IsInLog(questID)
  return State.log[questID] ~= nil
end

function State.IsQuestDone(questID)
  return State.done[questID] == true
end

-- The `state` table the pure Logic layer takes (Logic.lua header). One table, kept current, so views
-- build it once; `skills` and `rep` stay unknown until the profession reader exists (B5.3+).
local logicState
function State.ForLogic()
  if not logicState then
    logicState = {
      done = State.IsQuestDone,
      inLog = State.IsInLog,
      isComplete = function(id)
        local e = State.log[id]
        return e ~= nil and e.isComplete == true
      end,
      skills = {},
      rep = function()
        return nil
      end,
    }
  end
  local f = State.facts
  logicState.level, logicState.raceID, logicState.classID, logicState.faction =
    f.level, f.raceID, f.classID, f.faction
  return logicState
end

-- ---------------------------------------------------------------------------------------------
-- Flight paths: learned whenever a taxi map opens, kept per character
-- ---------------------------------------------------------------------------------------------

-- Records the current and reachable nodes of the open taxi map; returns how many were new.
function State.LearnFlightPaths()
  local known = State.flightPaths
  local new = 0
  for _, n in ipairs(B.Compat.GetTaxiNodes()) do
    if (n.state == "current" or n.state == "reachable") and (n.id or n.name) then
      local key = n.id or n.name
      if not known[key] then
        new = new + 1
      end
      known[key] = { name = n.name, map = n.map, x = n.x, y = n.y }
    end
  end
  return new
end

-- ---------------------------------------------------------------------------------------------
-- Attach to the module: saved variables, facts, first snapshot (no message: nothing to diff against)
-- ---------------------------------------------------------------------------------------------

function State.Attach(mod)
  local char = mod:GetDB().char
  if type(char.flightPaths) ~= "table" then
    char.flightPaths = {}
  end
  State.flightPaths = char.flightPaths
  if type(char.hidden) ~= "table" then
    char.hidden = {}
  end
  State.hidden = char.hidden
  State.ReadFacts()
  doneAttempts = 0
  State.LoadDone()
  State.Refresh()
  State.RefreshTracked()
end

-- The `progress` service (core-contracts §11), provided by the Quests module while it is enabled.
ns.Progress = {
  IsQuestDone = function(_, questID)
    return State.IsQuestDone(questID)
  end,
  IsInLog = function(_, questID)
    return State.IsInLog(questID)
  end,
  -- The live table; consumers read it and never modify it.
  KnownFlightPaths = function()
    return State.flightPaths
  end,
}
