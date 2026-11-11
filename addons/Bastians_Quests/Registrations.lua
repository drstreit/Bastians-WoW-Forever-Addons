-- Registrations (quests.md "What Quests registers in Core"): map layers, actions, detail sections and
-- the quest-text search provider. Everything here answers from memory; no pack is loaded on a hot path.
local _, ns = ...
local B = Bastians
local S = B.UI.Style
local L = ns.L
local Logic, State, R = ns.Logic, ns.State, ns.Rows

local Reg = {}
ns.Registrations = Reg

local OBJECTIVE_RADIUS = 60 -- world yards, drawn as a soft area around an objective spot
local HAND_IN_SIZE = 26 -- a done quest's "?" stands out from the map's 16 px pins (ADR 0053)
local COLOR = {
  available = S.C.gold,
  low = S.C.diffGrey, -- only low-level quests here: the game shows no mark (ADR 0051)
  soon = S.C.dim,
  blocked = S.C.muted,
  complete = S.C.gold,
  incomplete = S.C.dim,
}
-- A spot's icon by its kind: the pack's spot kinds (`slay`, `loot`, `object`, `area`) and the
-- steps' (`slay`, `use`, `get`, `reach`, `cast`). An item is got where who has it stands: the
-- monster glyph. (The table named `kill`, `item` and `event`, kinds the data never had: S1.)
local SPOT_ICON = {
  slay = "mob",
  loot = "mob",
  get = "mob",
  cast = "mob",
  object = "treasure",
  use = "treasure",
  area = "zone",
  reach = "zone",
}
Reg.SPOT_ICON = SPOT_ICON
local LAYERS = { "quests.available", "quests.soon", "quests.turnin", "quests.objectives" }

local function data()
  return B:GetService("data")
end

local function questID(ref)
  local typ, id = B.Entity.Parse(ref)
  return typ == "quest" and id or nil
end

-- ---------------------------------------------------------------------------------------------
-- Layers
-- ---------------------------------------------------------------------------------------------

-- giver ref -> "available" | "low" | "soon" | "blocked" | false, cached until the quests change
local giverStatus = {}
local giverQuests = {} -- giver ref -> { qid, ... } of the quests behind its status, for the pin

function Reg.ResetCaches()
  giverStatus = {}
  giverQuests = {}
end

local function inBags(itemID)
  return B.Compat.GetItemCount(itemID, true)
end

local function statusOfGiver(ref)
  local cached = giverStatus[ref]
  if cached ~= nil then
    return cached or nil, giverQuests[ref]
  end
  local d = data()
  local ids = d and d:Index("quest.byGiver", ref)
  local s = State.ForLogic()
  local best = false
  local byStatus = { available = {}, low = {}, soon = {}, blocked = {} }
  for _, qid in ipairs(ids or {}) do
    local st = Logic.status(qid, s)
    if st == "available" and Logic.AlreadyTaken(Logic.quest(qid), ref, inBags) then
      st = "taken" -- the book is in the bags: its place offers nothing, the NPC's pin stays
    end
    if st == "available" then
      if Logic.isTrivial(Logic.quest(qid), s) then
        table.insert(byStatus.low, qid)
        if best ~= "available" then
          best = "low"
        end
      else
        best = "available"
        table.insert(byStatus.available, qid)
      end
    elseif st == "level" then
      local q = Logic.quest(qid)
      if (q.minLevel or 0) - s.level <= Logic.SOON then
        table.insert(byStatus.soon, qid)
        if best ~= "available" and best ~= "low" then
          best = "soon"
        end
      end
    elseif st == "prereq" then
      table.insert(byStatus.blocked, qid)
      if not best then
        best = "blocked"
      end
    end
  end
  if best == "available" then
    for _, qid in ipairs(byStatus.low) do
      table.insert(byStatus.available, qid) -- the giver's yellow pin names them too
    end
  end
  giverStatus[ref] = best
  giverQuests[ref] = best and byStatus[best] or nil
  return best or nil, giverQuests[ref]
end

-- The first known location of an entity inside the view, in world yards.
local function inView(ref, view)
  for _, loc in ipairs(B:Entity(ref):Locations()) do
    local continent, wx, wy = B.Coords.ToWorld(loc.map, loc.x, loc.y)
    if
      continent == view.continent
      and wx >= view.x1
      and wx <= view.x2
      and wy >= view.y1
      and wy <= view.y2
    then
      return wx, wy
    end
  end
  return nil
end

-- Giver positions in spatial buckets (core-contracts §6: precompute on enable, in a job; B11.1):
-- continent -> { [cell] = { ref, wx, wy, ref, wx, wy, ... } }, built once per data load. Before it,
-- every query decoded all 1,814 Forever givers: 110 ms cold on the mock (measured 22.10.2026,
-- nfr.md); with the index a query touches only the cells under the view.
local giverCells -- nil while the job runs or without data
local giverJob
Reg.CELL_YARDS = 4 * 1600 / 3 -- 2133.33 yards, four ADT tiles: a continent is 16 x 16 cells
Reg.INDEX_STEP = 100 -- givers decoded per job slice before yielding
Reg.indexed = 0 -- givers in the index (for the tests and the perf report)

local function cellKey(cx, cy)
  return (cx + 64) * 256 + cy + 64
end

function Reg.GiverIndex()
  return giverCells
end

-- Rebuilds the index in a job; the layers re-query when it is ready (BASTIANS_LAYER_CHANGED).
function Reg.BuildGiverIndex(mod)
  if giverJob then
    giverJob:Cancel()
    giverJob = nil
  end
  giverCells = nil
  local d = data()
  local byGiver = d and d:Index("quest.byGiver")
  if not byGiver then
    return
  end
  local refs = {}
  for ref in pairs(byGiver) do
    refs[#refs + 1] = ref
  end
  table.sort(refs)
  local cells = {}
  local c = Reg.CELL_YARDS
  giverJob = B.Jobs:Run(mod, "giver-index", function(yield)
    for i, ref in ipairs(refs) do
      for _, loc in ipairs(B:Entity(ref):Locations()) do
        local continent, wx, wy = B.Coords.ToWorld(loc.map, loc.x, loc.y)
        if continent then
          local byCell = cells[continent]
          if not byCell then
            byCell = {}
            cells[continent] = byCell
          end
          local key = cellKey(math.floor(wx / c), math.floor(wy / c))
          local list = byCell[key]
          if not list then
            list = {}
            byCell[key] = list
          end
          list[#list + 1], list[#list + 2], list[#list + 3] = ref, wx, wy
        end
      end
      if i % Reg.INDEX_STEP == 0 then
        yield()
      end
    end
  end, {
    onDone = function(job)
      if job.cancelled then
        return
      end
      giverJob = nil
      giverCells = cells
      Reg.indexed = #refs
      mod:Fire("BASTIANS_LAYER_CHANGED", "quests.available")
      mod:Fire("BASTIANS_LAYER_CHANGED", "quests.soon")
    end,
  })
end

-- Calls fn(ref, wx, wy) for every indexed giver location inside the view.
local function giversInView(view, fn)
  local byCell = giverCells and giverCells[view.continent]
  if not byCell then
    return
  end
  local c = Reg.CELL_YARDS
  for cx = math.floor(view.x1 / c), math.floor(view.x2 / c) do
    for cy = math.floor(view.y1 / c), math.floor(view.y2 / c) do
      local list = byCell[cellKey(cx, cy)]
      if list then
        for i = 1, #list, 3 do
          local wx, wy = list[i + 1], list[i + 2]
          if wx >= view.x1 and wx <= view.x2 and wy >= view.y1 and wy <= view.y2 then
            fn(list[i], wx, wy)
          end
        end
      end
    end
  end
end

local function giverPins(view, wanted, priority)
  local pins, seen = {}, {}
  local s = State.ForLogic()
  local shortStatus = Reg.ShortStatus -- defined with the detail sections below
  giversInView(view, function(ref, wx, wy)
    if seen[ref] then
      return -- one pin per giver: its first location in the view
    end
    local st, qids = statusOfGiver(ref)
    if st and wanted[st] then
      seen[ref] = true
      -- the quests behind the pin, for its tooltip
      local lines = {}
      for i, qid in ipairs(qids or {}) do
        if i > 4 then
          lines[#lines + 1] = string.format(L["... and %d more"], #qids - 4)
          break
        end
        lines[#lines + 1] = R.questName(qid) .. "  " .. R.COLOR.grey .. (shortStatus(qid, s)) .. "|r"
      end
      pins[#pins + 1] = {
        ref = ref,
        wx = wx,
        wy = wy,
        icon = B.UI.IconTexture("quest"),
        color = COLOR[st],
        label = B:Entity(ref):Name(),
        priority = priority,
        cluster = true,
        status = st,
        quests = qids,
        lines = lines,
        card = Reg.SignCard, -- the map's hover card (R25.30), made when hovered
      }
    end
  end)
  return pins
end

-- The quest the map shows (ADR 0053): the focused one, else the open log quest with the nearest
-- spot on the player's map; nil without one.
function Reg.FocusQuest()
  local typ, id = B.Entity.Parse(B:Focused() or "")
  if typ == "quest" and State.log[id] then
    return id
  end
  local map, px, py = ns.Window.PlayerPlace()
  local best, nearest
  for _, qid in ipairs(State.order) do
    local e = State.log[qid]
    if not e.isComplete then
      local place = ns.Views.PlaceOf(e, map, px, py)
      local here = place.map == map and place.target == "objective"
      if here and (nearest == nil or place.d < nearest) then
        best, nearest = qid, place.d
      end
    end
  end
  return best
end

-- Hand-ins: every done quest's, large; an open quest's only while it has the map.
local function turnInPins(view)
  local pins, seen = {}, {}
  local focus = Reg.FocusQuest()
  for _, qid in ipairs(State.order) do
    local e = State.log[qid]
    local q = Logic.quest(qid)
    for _, ref in ipairs((e.isComplete or qid == focus) and q and q.ends or {}) do
      local pin = seen[ref]
      if pin then
        pin.quests[#pin.quests + 1] = qid
        if e.isComplete and not pin.complete then
          pin.complete, pin.color, pin.priority, pin.size = true, nil, 70, HAND_IN_SIZE
        end
      else
        local wx, wy = inView(ref, view)
        if wx then
          pin = {
            ref = ref,
            wx = wx,
            wy = wy,
            icon = B.UI.IconTexture("questActive"),
            color = not e.isComplete and COLOR.incomplete or nil,
            size = e.isComplete and HAND_IN_SIZE or nil,
            label = B:Entity(ref):Name(),
            priority = e.isComplete and 70 or 55,
            cluster = true,
            complete = e.isComplete or false,
            -- the quests handed in here: one opens that quest, several the NPC's page with its
            -- "Ends quests"
            quests = { qid },
            card = Reg.SignCard,
          }
          seen[ref] = pin
          pins[#pins + 1] = pin
        end
      end
    end
  end
  return pins
end

-- What a spot asks for, in the client's words with the count: "Hippogryph Youth slain 0/8".
local function objectiveWords(o)
  local text = R.objectiveLabel(o)
  if o.required and o.required > 0 then
    return string.format("%s %d/%d", text, o.fulfilled or 0, o.required)
  end
  return text
end

-- The hover card of a spot: what to do here first, then the quest it is for.
local function spotCard(pin)
  local card = Reg.SignCard(pin) or { lines = {} }
  local lines = { { text = card.title or pin.quest, color = "dim" } }
  for i = 2, #pin.open do
    table.insert(lines, i - 1, { text = objectiveWords(pin.open[i]), color = "good" })
  end
  for _, line in ipairs(card.lines) do
    lines[#lines + 1] = line
  end
  return { title = objectiveWords(pin.open[1]), titleColor = "good", lines = lines }
end

local function objectivePins(view)
  local pins = {}
  local function add(qid, e, map, x, y, kind, open)
    local continent, wx, wy = B.Coords.ToWorld(map, x, y)
    if
      continent == view.continent
      and wx >= view.x1
      and wx <= view.x2
      and wy >= view.y1
      and wy <= view.y2
    then
      pins[#pins + 1] = {
        ref = "quest:" .. qid,
        wx = wx,
        wy = wy,
        icon = B.UI.IconTexture(SPOT_ICON[kind] or "questActive"),
        label = open and objectiveWords(open[1]) or e.title, -- what to do here, when known
        priority = 65,
        cluster = false,
        radius = OBJECTIVE_RADIUS,
        quests = open and { qid } or nil,
        quest = e.title,
        open = open,
        card = open and spotCard or nil,
      }
    end
  end
  local withoutSpots = {} -- log quests the pack has no spots for (retail, Forever's own, D2)
  local focus = Reg.FocusQuest() -- one quest has the map (ADR 0053)
  for _, qid in ipairs(State.order) do
    local e = State.log[qid]
    local q = Logic.quest(qid)
    if not e.isComplete and qid == focus then
      local spots = q and q.spots and Logic.OpenSpots(e, q)
      if spots and next(spots) then
        for map, list in pairs(spots) do
          for _, s in ipairs(list) do
            add(qid, e, map, s[1], s[2], s[3], s.open)
          end
        end
      else
        withoutSpots[qid] = e
      end
    end
  end
  if next(withoutSpots) then
    -- the client's quest POIs of the player's map stand in for the missing spots (D2)
    local map = B.Coords.PlayerMap()
    if not map then
      map = select(4, B.Coords.Player())
    end
    if map then
      for _, poi in ipairs(B.Compat.GetQuestsOnMap(map)) do
        local e = withoutSpots[poi.questID]
        if e then
          add(poi.questID, e, map, poi.x, poi.y, nil)
        end
      end
    end
  end
  return pins
end

local function registerLayers(mod)
  B:RegisterMapLayer(mod, {
    id = "quests.available",
    icon = "quest", -- the layer bar shows its icon (R27.8)
    label = L["Quests to take"],
    defaultOn = true,
    minLevel = 2,
    query = function(view)
      return giverPins(view, { available = true, low = true }, 60)
    end,
  })
  B:RegisterMapLayer(mod, {
    id = "quests.soon",
    icon = "waiting", -- the layer bar shows its icon (R27.8)
    label = L["Quests soon (level, prerequisite)"],
    defaultOn = false,
    minLevel = 3,
    query = function(view)
      return giverPins(view, { soon = true, blocked = true }, 40)
    end,
  })
  B:RegisterMapLayer(mod, {
    id = "quests.turnin",
    icon = "done", -- the layer bar shows its icon (R27.8)
    label = L["Quest hand-ins"],
    defaultOn = true,
    minLevel = 1,
    query = turnInPins,
  })
  B:RegisterMapLayer(mod, {
    id = "quests.objectives",
    icon = "mob", -- the layer bar shows its icon (R27.8)
    label = L["Quest objectives"],
    defaultOn = true,
    minLevel = 2,
    query = objectivePins,
  })
end

-- ---------------------------------------------------------------------------------------------
-- Actions: track and untrack (the objective tracker); quests.open lives with the window
-- ---------------------------------------------------------------------------------------------

function Reg.SyncTracked(mod)
  local changes = State.RefreshTracked()
  for _, c in ipairs(changes or {}) do
    mod:Fire("BASTIANS_TRACKED_CHANGED", "quest:" .. c[1], c[2])
  end
end

-- ---------------------------------------------------------------------------------------------
-- Where a quest sends you (ADR 0069, quests.md): the facet `steps` and its readers
-- ---------------------------------------------------------------------------------------------

-- What the client says of a running quest's place (D2), asked for the player's map and the
-- quest's zone: its next waypoint, else its quest POI there. `kind` is the place's kind.
local function clientWaypoint(id, kind)
  local q = Logic.quest(id)
  local player, zone = B.Coords.PlayerMap(), q and q.zone
  local maps = { player }
  if zone and zone ~= player then
    maps[#maps + 1] = zone
  end
  for _, map in ipairs(maps) do
    local x, y = B.Compat.GetQuestWaypoint(id, map)
    if x and y then
      return { map = map, x = x, y = y, kind = kind, src = "client" }
    end
  end
  for _, map in ipairs(maps) do
    for _, poi in ipairs(B.Compat.GetQuestsOnMap(map)) do
      if poi.questID == id then
        return { map = map, x = poi.x, y = poi.y, kind = kind, src = "client" }
      end
    end
  end
  return nil
end

-- The quests whose facet asked the client, and what it said ("map:x:y", false for nothing).
local asked = {}

local function placeKey(p)
  return p and (p.map .. ":" .. p.x .. ":" .. p.y) or false
end

-- The facet `steps` of a quest: Data's steps with the log's state (Logic.QuestSteps). Core makes
-- a quest's Locations() from it: the places of the open steps, and nothing when none of them has
-- a place. The client is asked only then, and only for a quest of the log.
local function questSteps(ref)
  local id = questID(ref)
  if not id then
    return nil
  end
  local steps = Logic.QuestSteps(id, State.log[id], State.ForLogic())
  asked[id] = nil
  if steps and (steps.state == "active" or steps.state == "complete") then
    local placed = false
    for _, step in ipairs(steps) do
      placed = placed or (step.open and step.places and #step.places > 0) or false
    end
    if not placed then
      steps.waypoint = clientWaypoint(id, steps.state == "complete" and "turnin" or "objective")
      asked[id] = placeKey(steps.waypoint)
    end
  end
  return steps
end
Reg.QuestSteps = questSteps

-- Asks the client again for the quests that wait for its place, once per burst of quest events
-- without a change of the log (Quests.lua): the client learns its places after the log (at
-- login, after a step), and no message of ours says so. An answer that differs drops the facet
-- (BASTIANS_QUESTS_CHANGED with { places = true }); the zone change does it by `invalidateOn`.
function Reg.CheckWaypoints(mod)
  local changed = false
  for id, was in pairs(asked) do
    local entry = State.log[id]
    if not entry then
      asked[id] = nil
    else
      local ready = entry.isComplete or entry.readyForTurnIn
      local now = placeKey(clientWaypoint(id, ready and "turnin" or "objective"))
      asked[id] = now -- said once: nobody may read the facet before the next burst
      changed = changed or now ~= was
    end
  end
  if changed then
    mod:Fire("BASTIANS_QUESTS_CHANGED", nil, { places = true })
  end
  return changed
end

-- The facet as every reader of Quests asks for it: Core's cached answer (the same one Route, the
-- Map and the public API see), nil for a quest nobody knows.
local function stepsOf(id)
  return id and B:Entity("quest:" .. id):Facet("steps") or nil
end
Reg.StepsOf = stepsOf

-- The band's Giver, Targets and Hand-in buttons: the places of
-- one kind of step, whatever the quest's status: `giver` where it is taken, `turnin` where it is
-- handed in, `objective` the things to do that are not finished (the client's place fills in
-- for a quest of the log none of them places). Each { map, x, y, kind, ref, step, src }.
local STEP_KIND = { take = "giver", handin = "turnin" }

local function questPlaces(ref, kind)
  local id = questID(ref)
  local steps = stepsOf(id)
  local out, seen = {}, {}
  for i, step in ipairs(steps or {}) do
    if (STEP_KIND[step.step] or "objective") == kind and not (kind == "objective" and step.done) then
      for _, p in ipairs(step.places or {}) do
        local key = p.map .. ":" .. p.x .. ":" .. p.y
        if not seen[key] then
          seen[key] = true
          out[#out + 1] = {
            map = p.map,
            x = p.x,
            y = p.y,
            kind = kind,
            ref = p.ref or step.ref,
            step = i,
            src = p.src or step.src,
          }
        end
      end
    end
  end
  if #out == 0 and kind == "objective" and State.log[id] then
    out[1] = clientWaypoint(id, "objective")
  end
  return out
end

local function registerPlaces(mod)
  B:RegisterFacet(mod, {
    facet = "steps",
    types = { "quest" },
    priority = 150,
    -- the zone: the client's place is asked for the player's map
    invalidateOn = { "BASTIANS_QUESTS_CHANGED", "BASTIANS_DATA_LOADED", "BASTIANS_PLAYER_MOVED_ZONE" },
    rule = questSteps,
  })
  for i, def in ipairs({
    { "quests.giver", "giver", "Giver", "Show the quest giver on the map" },
    { "quests.targets", "objective", "Targets", "Show the quest's targets on the map" },
    { "quests.turnin", "turnin", "Hand-in", "Show the hand-in on the map" },
  }) do
    local id, kind, short, label = def[1], def[2], def[3], def[4]
    B:RegisterAction(mod, {
      id = id,
      label = L[label],
      short = L[short],
      icon = B.UI.IconTexture("zone"),
      types = { "quest" },
      order = 11 + i,
      when = function()
        return B:GetAction("map.show") ~= nil -- the Map draws; without it nothing to press
      end,
      enabled = function(ref)
        return #questPlaces(ref, kind) > 0 -- greyed with "unknown" when no source has the place
      end,
      run = function(ref, ctx)
        local places = questPlaces(ref, kind)
        if #places == 0 then
          return false
        end
        return B:RunAction("map.show", ref, { source = ctx and ctx.source or "quests", points = places })
      end,
    })
  end
end
Reg.QuestPlaces = questPlaces

local function registerActions(mod)
  registerPlaces(mod)
  -- Hide a quest from Do here and the ranking; the same
  -- icon unhides (orange while hidden). The row tag greys the quest wherever a list shows it.
  B:RegisterAction(mod, {
    id = "quests.hide",
    label = L["Hide from Do here (click again to unhide)"],
    icon = B.UI.IconTexture("hide"),
    types = { "quest" },
    order = 45,
    when = function(ref)
      local id = questID(ref)
      return id ~= nil and Logic.quest(id) ~= nil and not State.IsInLog(id)
    end,
    active = function(ref)
      return State.IsHidden(questID(ref))
    end,
    run = function(ref)
      local id = questID(ref)
      State.SetHidden(id, not State.IsHidden(id))
      mod:Fire("BASTIANS_QUESTS_CHANGED", { id }, { hidden = true })
    end,
  })
  -- Gestures' "Toggle the tracker" (plan-second-wave.md S6), offered to the ring only
  B:RegisterAction(mod, {
    id = "quests.tracker",
    label = L["Toggle the tracker"],
    icon = B.UI.IconTexture("track"),
    types = "*",
    order = 90,
    when = function(_, ctx)
      return ctx ~= nil and ctx.source == "gestures"
    end,
    active = function()
      return ns.Tracker.IsShown()
    end,
    run = function()
      ns.Tracker.Toggle()
    end,
  })
  B:RegisterRowTag(mod, {
    id = "quests.hidden",
    types = { "quest" },
    tag = function(ref)
      local id = questID(ref)
      return id and State.IsHidden(id) and L["hidden"] or nil
    end,
  })
  B:RegisterAction(mod, {
    id = "quests.track",
    main = true, -- a button of the sheet (ADR 0054)
    label = L["Track: show it on the objective tracker"],
    short = L["Track"],
    icon = B.UI.IconTexture("questActive"),
    types = { "quest" },
    order = 30,
    when = function(ref)
      local id = questID(ref)
      return id ~= nil and State.IsInLog(id) and not State.IsTracked(id)
    end,
    run = function(ref)
      if B.Compat.SetQuestWatched(questID(ref), true) then
        Reg.SyncTracked(mod)
      end
    end,
  })
  B:RegisterAction(mod, {
    id = "quests.untrack",
    main = true, -- a button of the sheet (ADR 0054)
    label = L["Tracked: click to untrack"],
    short = L["Untrack"],
    icon = B.UI.IconTexture("questActive"),
    types = { "quest" },
    order = 30,
    -- the same icon as Track, green while the quest is tracked (it was
    -- unclear how to track and untrack)
    active = function()
      return true
    end,
    when = function(ref)
      local id = questID(ref)
      return id ~= nil and State.IsTracked(id)
    end,
    run = function(ref)
      if B.Compat.SetQuestWatched(questID(ref), false) then
        Reg.SyncTracked(mod)
      end
    end,
  })
  -- Abandon a log quest (owner, Forever launch night 05.11.2026: the window had no way to cancel
  -- one). The game's own confirmation asks; QUEST_REMOVED then refreshes the window.
  B:RegisterAction(mod, {
    id = "quests.abandon",
    label = L["Abandon the quest (the game asks first)"],
    short = L["Abandon"],
    icon = B.UI.IconTexture("remove"),
    types = { "quest" },
    order = 80,
    when = function(ref)
      local id = questID(ref)
      return id ~= nil and State.IsInLog(id)
    end,
    run = function(ref)
      return B.Compat.AbandonQuest(questID(ref)) ~= false
    end,
  })
end

-- ---------------------------------------------------------------------------------------------
-- Detail sections
-- ---------------------------------------------------------------------------------------------

-- Rows "quest name" for the quests an index lists for an entity.
-- The status of a quest in a few words for a row on an NPC, object or item page (owner,
-- 22.10.2026: the pin's NPC page must say which quest it is and where the player stands with it).
-- Returns the words, their colour and a sort rank (what the player can act on first).
local SHORT_STATUS = {
  available = { "Available", "yellow", 1 },
  low = { "Available, low level", "grey", 2 },
  log = { "In your log", "white", 3 },
  complete = { "Ready to turn in", "green", 0 },
  done = { "Done", "grey", 6 },
  level = { "Needs level %d", "grey", 4 },
  prereq = { "Needs another quest first", "grey", 5 },
  skill = { "Needs a profession skill", "grey", 5 },
  rep = { "Needs reputation", "grey", 5 },
  superseded = { "Replaced by another quest", "grey", 7 },
  never = { "Not for this character", "grey", 7 },
  inactive = { "Not offered now", "grey", 8 },
}

-- Why the game does not offer the quest now, in a few words.
local function inactiveWords(q)
  if q and q.holiday then
    return string.format(L["Only during %s"], L[q.holiday])
  end
  return L["Not offered now"]
end

local function shortStatus(id, s)
  local st = Logic.status(id, s)
  local e = st == "log" and State.log[id] or nil
  if e and e.isComplete then
    st = "complete"
  end
  local q = Logic.quest(id)
  local key = (st == "available" and q and Logic.isTrivial(q, s)) and "low" or st
  local def = SHORT_STATUS[key] or SHORT_STATUS.never
  local text = L[def[1]]
  if st == "level" then
    text = string.format(text, q and q.minLevel or 0)
  elseif st == "inactive" then
    text = inactiveWords(q)
  elseif st == "log" and e then
    local progress = R.progressText(e)
    if progress ~= "" then
      text = text .. " " .. progress
    end
  end
  return text, R.COLOR[def[2]], def[3], st
end
Reg.ShortStatus = shortStatus

-- The category a quest row sits under on a page:
-- rank -> header text; the status words of the "Later" and "Not for you" ranks stay on the row.
local CATEGORY = {
  [0] = "Ready to turn in",
  [1] = "Available",
  [2] = "Available",
  [3] = "In your log",
  [4] = "Later",
  [5] = "Later",
  [6] = "Done",
  [7] = "Not for this character",
  [8] = "Not offered now",
}

-- A Play button on a quest row when Spoken has a line for it (Bastian's Voice registers voice.play
-- with `has`, voice.md; ADR 0013: no play symbol where no line exists).
local function voiceButton(ref)
  local voice = B:GetAction("voice.play")
  if not voice or (voice.has and not voice.has(ref)) then
    return nil
  end
  return {
    label = ">",
    onClick = function(row)
      B:RunAction("voice.play", row.ref or ref, { source = "browser" })
    end,
  }
end

-- Quest rows of a list of quest ids, sorted by what the player can act on first. `grouped` puts
-- them under category rows (the page); flat rows carry the status words (tooltips, the old
-- shape). `key` names the header rows. nil for no ids.
local function questRowsFor(ids, grouped, key)
  if not ids or #ids == 0 then
    return nil
  end
  local rows = {}
  local s = State.ForLogic()
  for _, id in ipairs(ids) do
    local q = Logic.quest(id)
    local words, color, rank, st = shortStatus(id, s)
    local name = q and q.name or (L["Quest"] .. " " .. id)
    -- under a header only "low level", the log progress and "needs" stay
    local keepWords = not grouped or rank >= 2
    rows[#rows + 1] = {
      text = keepWords and (name .. "  " .. color .. words .. "|r") or name,
      ref = "quest:" .. id,
      value = q and q.level or nil,
      valueKind = "number",
      status = st,
      rank = rank,
      icon = B.UI.IconTexture(
        ({ available = "quest", log = "questActive", complete = "questActive", done = "done" })[st] or "quest"
      ),
      button = voiceButton("quest:" .. id),
    }
  end
  table.sort(rows, function(a, b)
    if a.rank ~= b.rank then
      return a.rank < b.rank -- what the player can act on first: turn-ins, then available
    end
    return (a.value or 0) < (b.value or 0)
  end)
  if not grouped then
    return rows
  end
  local out, header = {}, nil
  for _, row in ipairs(rows) do
    local title = L[CATEGORY[row.rank] or CATEGORY[7]]
    if not header or header.text ~= title then
      header = {
        id = tostring(key) .. ":" .. title,
        text = title,
        kind = "section",
        children = {},
      }
      out[#out + 1] = header
    end
    header.children[#header.children + 1] = row
  end
  return out
end

Reg.QuestRowsFor = questRowsFor -- the class quests view builds its rows here (Window.lua)

-- Quest rows of an index entry (the pages' sections).
local function questRows(indexName, key, grouped)
  local d = data()
  local ids = d and d:Index(indexName, key)
  return questRowsFor(ids, grouped, indexName .. ":" .. tostring(key))
end

local function statusText(id)
  local s = State.ForLogic()
  local st, missing = Logic.status(id, s)
  local q = Logic.quest(id)
  local text
  if st == "log" then
    local e = State.log[id]
    local progress = e and R.progressText(e) or ""
    text = (e and e.isComplete) and L["In the log, complete"] or L["In the log"]
    if progress ~= "" then
      text = text .. " " .. progress
    end
  elseif st == "done" then
    text = L["Done"]
  elseif st == "available" then
    text = (q and Logic.isTrivial(q, s)) and L["Available, low level"] or L["Available"]
  elseif st == "inactive" then
    text = inactiveWords(q)
  elseif st == "level" then
    text = L["Needs level"] .. " " .. tostring(q and q.minLevel or "?")
  elseif st == "prereq" then
    local names = {}
    for _, m in ipairs(missing or {}) do
      names[#names + 1] = R.questName(m)
    end
    text = L["Needs"] .. ": " .. table.concat(names, ", ")
  elseif st == "skill" then
    text = L["Needs a profession skill"]
  elseif st == "rep" then
    text = L["Needs reputation"]
  elseif st == "superseded" then
    text = L["Superseded by another quest"]
  else
    text = L["Not for this character"]
  end
  if State.IsTracked(id) then
    text = text .. "  " .. R.COLOR.grey .. L["tracked"] .. "|r"
  end
  return { { text = R.statusIcon(st) .. text, status = st } }
end

-- The attunement of a dungeon (data.md "Dungeons", DG2b): the list whose `instance` is the
-- dungeon, as a progress chain with the bags and the reputation of this character.
local function dungeonAttunementRows(ref)
  local _, id = B.Entity.Parse(ref)
  local s = State.ForLogic()
  for _, a in ipairs(Logic.attunements(State.facts.faction)) do
    if a.instance == id then
      local steps = {}
      for _, step in ipairs(a.steps or {}) do
        steps[#steps + 1] = { kind = step[1], id = step[2], label = step[3], standing = step[4] }
      end
      local rows = R.progress(steps, s, {
        hasItem = function(itemID)
          return B.Compat.GetItemCount(itemID) > 0
        end,
        rep = B.Compat.GetReputation,
      }, { key = "datt:" .. id })
      if not a.verified then
        rows[1].text = rows[1].text .. "  " .. R.COLOR.orange .. L["unverified"] .. "|r"
      end
      return rows
    end
  end
  return nil
end

-- The quest's givers or hand-in NPCs and objects, each with its zone ("NPC
-- issuing the quest" on the quest page); a click opens the giver's page.
local function npcRows(refs)
  if not refs or #refs == 0 then
    return nil
  end
  local rows = {}
  for _, ref in ipairs(refs) do
    local e = B:Entity(ref)
    local summary = e:Summary()
    rows[#rows + 1] = {
      text = (e:Name() or ref) .. (summary and ("  " .. R.COLOR.grey .. summary .. "|r") or ""),
      ref = ref,
    }
  end
  return rows
end

-- The "after" link (C2): what must be done first; the plain prerequisites unlabelled, the other
-- kinds (one of, while in the log, excludes) with their word in front.
local function afterRows(id)
  local q = Logic.quest(id)
  if not q then
    return nil
  end
  local s = State.ForLogic()
  local rows = {}
  local function add(label, ids)
    for _, p in ipairs(ids or {}) do
      local row = R.quest(p, s, { zone = true, map = Logic.startMap(q), where = label or "after" })
      if label then
        row.text = R.COLOR.grey .. label .. ":|r " .. row.text
      end
      rows[#rows + 1] = row
    end
  end
  add(nil, q.pre)
  add(L["one of"], q.preAny)
  if q.parent then
    add(L["while in the log"], { q.parent })
  end
  add(L["excludes"], q.excl)
  return #rows > 0 and rows or nil
end

-- The "unlocks" link (C2): the quests this one leads to (Logic.next: prerequisites and chains).
local function unlocksRows(id)
  local q = Logic.quest(id)
  local s = State.ForLogic()
  local rows, seen = {}, {}
  local function add(f)
    if f and not seen[f] then
      seen[f] = true
      rows[#rows + 1] = R.quest(f, s, { zone = true, map = q and Logic.startMap(q), where = "unlocks" })
    end
  end
  for _, f in ipairs(Logic.next(id)) do
    add(f)
  end
  if q then
    add(q.chain)
  end
  return #rows > 0 and rows or nil
end

-- The "needs" link (C2): the items a quest asks for (its `get` steps), each with who has it and
-- how long the way there is now (so the rows are not cached: the time moves with the player).
-- (It matched the kind `item`, which the data never had: plan-quest-links.md S2.)
local function needsRows(id)
  local rows = {}
  for i, step in ipairs(stepsOf(id) or {}) do
    local ref = step.step == "get" and step.ref or nil
    if ref then
      local text = B:Entity(ref):Name() or ref
      if type(step.count) == "number" and step.count > 1 then
        text = text .. " x" .. step.count
      end
      local source = step.via and step.via[1]
      local from = source and B:Entity(source):Name()
      if from then
        local dist = B.UI.Away(source)
        text = text
          .. "  "
          .. R.COLOR.grey
          .. L["from"]
          .. " "
          .. from
          .. (dist and (", " .. dist) or "")
          .. "|r"
      end
      rows[#rows + 1] =
        { id = "needs:" .. id .. ":" .. i, text = text, ref = ref, icon = B:Entity(ref):Icon() }
    end
  end
  return #rows > 0 and rows or nil
end

-- The quest's task in its own words: the text pack's, else the client's for a log quest.
local function taskText(id)
  local d = data()
  local t = d and d:PackLoaded("text") and d:Get("questText", id) or nil
  if t and t.objectives and t.objectives ~= "" then
    return t.objectives
  end
  local _, objectives = B.Compat.GetQuestText(id)
  return objectives
end

-- What to do (ADR 0052): the task, then the live objectives of a log quest or the data's.
local function objectiveRows(id)
  local rows = {}
  rows[1] = R.taskRow(id, taskText(id))
  local e = State.log[id]
  if e and #(e.objectives or {}) > 0 then
    for _, row in ipairs(R.objectives(e)) do
      rows[#rows + 1] = row
    end
    return rows
  end
  local q = Logic.quest(id)
  for i, o in ipairs(q and q.objectives or {}) do
    local kind, ref, source = o[1], o[2], o[4]
    local name = ref and B:Entity(ref):Name() or nil
    local text = R.COLOR.grey .. L[kind] .. ":|r " .. (name or ref or "?")
    if source then -- a loot objective: the item, and where it comes from (data.md, 23.10.2026)
      local from = B:Entity(source):Name()
      if from then
        text = text .. "  " .. R.COLOR.grey .. "(" .. L["from"] .. " " .. from .. ")|r"
      end
    end
    rows[#rows + 1] = { id = "obj:" .. id .. ":" .. i, text = text, ref = ref }
  end
  return #rows > 0 and rows or nil
end

local function itemRow(entry, label)
  local itemID, count = entry[1], entry[2] or 1
  local name = B:Entity("item:" .. itemID):Name() or (L["Item"] .. " " .. itemID)
  local prices = B:GetService("prices")
  local price = prices and prices:Price(itemID) or nil
  local value = price and price.median and price.median * count or nil
  return {
    text = (label and (R.COLOR.grey .. label .. ":|r ") or "")
      .. name
      .. (count > 1 and (" x" .. count) or ""),
    ref = "item:" .. itemID,
    icon = B:Entity("item:" .. itemID):Icon(), -- the item's own icon
    value = value,
    valueKind = value and "money" or nil,
  }
end

-- The name of a faction: the client knows every faction id (Compat.GetReputation), else the id.
local function factionName(factionID)
  return R.factionName(factionID) or (L["Faction"] .. " " .. factionID)
end

-- What a quest earns: money, XP (classic: from
-- the money it pays at level 60), reputation, items, choices and a spell. The section always shows
-- when the quest is known: "No reward known" says so instead of hiding the section.
local function rewardRows(id)
  local q = Logic.quest(id)
  if not q then
    return nil
  end
  local rw = Logic.rewards(id) or {}
  local rows = {}
  if rw.money and rw.money > 0 then
    rows[#rows + 1] = { text = L["Money"], value = rw.money, valueKind = "money" }
  end
  if rw.xp and rw.xp > 0 then
    rows[#rows + 1] = {
      text = rw.src == "client" and L["Experience"]
        or (L["Experience"] .. "  " .. R.COLOR.grey .. L["about, less for a lower quest"] .. "|r"),
      value = rw.xp,
      valueKind = "number",
    }
  end
  for _, rep in ipairs(rw.rep or {}) do
    local value = rep[2] or 0
    rows[#rows + 1] = {
      text = L["Reputation"] .. ": " .. factionName(rep[1]),
      value = (value > 0 and "+" or "") .. value,
      color = value < 0 and S.C.bad or nil,
    }
  end
  for _, it in ipairs(rw.items or {}) do
    rows[#rows + 1] = itemRow(it, nil)
  end
  for _, it in ipairs(rw.choices or {}) do
    rows[#rows + 1] = itemRow(it, L["Choice"])
  end
  if rw.spell then
    rows[#rows + 1] = {
      text = R.COLOR.grey
        .. L["On completion"]
        .. ":|r "
        .. (rw.spellName or (L["Spell"] .. " " .. rw.spell)),
    }
  end
  if #rows == 0 then
    rows[1] = {
      kind = "para",
      text = R.COLOR.grey .. L["The giver tells you the rewards when you speak to them."] .. "|r",
    }
  end
  return rows
end

-- "Quest chain 'X' 2/5": a quest's step on its chain's main line, as the strip of its sheet
-- counts it (ADR 0055); a side quest names the chain alone. Nil outside a chain.
local function chainWords(qid, state)
  local place = Logic.chainPlace(qid, state)
  if not place or place.why then
    return nil
  end
  local name = Logic.chainName(place.root, state) or "?"
  if place.step then
    return string.format(L["Quest chain '%s' %d/%d"], name, place.step, place.steps)
  end
  return string.format(L["Quest chain '%s'"], name)
end

-- The rows under a quest's tooltip (owner, Forever launch night 05.11.2026: the Orbiter's quest
-- marks showed no reward): the chain position, then the rewards (money, reputation, items, choices,
-- a spell) without the experience row. Rendered by B.UI.TipRows wherever a host shows a quest.
local function rewardTipRows(id)
  local q = Logic.quest(id)
  if not q then
    return nil
  end
  local rows = {}
  local chain = chainWords(id, State.ForLogic())
  if chain then
    rows[1] = { text = chain }
  end
  for _, row in ipairs(rewardRows(id) or {}) do
    if row.valueKind ~= "number" then
      rows[#rows + 1] = row
    end
  end
  return rows
end

Reg.CARD_QUESTS = 3 -- quests a sign's card names; the rest as "... and n more"

-- A quest's rewards as card lines: the money, the reputation, then every item (the choices
-- marked); no experience.
local function rewardLines(qid)
  local rw = Logic.rewards(qid) or {}
  local lines = {}
  if rw.money and rw.money > 0 then
    lines[#lines + 1] = { text = B.UI.Money(rw.money), color = "gold" }
  end
  for _, rep in ipairs(rw.rep or {}) do
    local value = rep[2] or 0
    lines[#lines + 1] = {
      text = (value > 0 and "+" or "") .. value .. " " .. factionName(rep[1]),
      color = value < 0 and "bad" or "text",
    }
  end
  local function item(it, prefix)
    local name = B:Entity("item:" .. it[1]):Name() or (L["Item"] .. " " .. it[1])
    local count = (it[2] or 1) > 1 and (" x" .. it[2]) or ""
    lines[#lines + 1] = { text = (prefix and (R.COLOR.grey .. prefix .. "|r ") or "") .. name .. count }
  end
  for _, it in ipairs(rw.items or {}) do
    item(it)
  end
  for _, it in ipairs(rw.choices or {}) do
    item(it, L["Choice:"])
  end
  return lines
end

-- The map's card of a quest sign: per quest its name (green,
-- larger), its chain in grey ("Quest chain 'X' 2/5"), its rewards. One quest: the card is that
-- quest's; several: the giver's name over up to CARD_QUESTS quests. Not "Available", the worth or
-- the minutes: the sign says the status, the rest did not help.
function Reg.SignCard(pin)
  local qids = pin.quests or {}
  if #qids == 0 then
    return nil
  end
  local s = State.ForLogic()
  local single = #qids == 1
  local lines = {}
  if pin.status == "low" then
    lines[1] = { text = L["Low level"], color = "dim" }
  end
  for i, qid in ipairs(qids) do
    if i > Reg.CARD_QUESTS then
      lines[#lines + 1] =
        { text = string.format(L["... and %d more"], #qids - Reg.CARD_QUESTS), color = "dim" }
      break
    end
    if not single then
      lines[#lines + 1] = { text = R.questName(qid), color = "good", size = 13 }
    end
    local chain = chainWords(qid, s)
    if chain then
      lines[#lines + 1] = { text = chain, color = "dim" }
    end
    for _, l in ipairs(rewardLines(qid)) do
      lines[#lines + 1] = l
    end
  end
  return {
    title = single and R.questName(qids[1]) or (pin.ref and B:Entity(pin.ref):Name()) or pin.label,
    titleColor = single and "good" or nil,
    lines = lines,
  }
end

-- Which reward to take (S7, browser.md "Item comparison of quest reward choices"): the choices
-- compared by what the client knows of each item (kind, item level, stats), the value (the AH
-- median through the prices service, else the vendor sell price) and what the player wears where
-- the item would go. Two choices at least; an item the client has not cached is requested once
-- and the block says so until ITEM_DATA_LOAD_RESULT re-renders it (Quests.lua).
local requestedItems = {} -- itemID -> true while a load is asked for
Reg.requestedItems = requestedItems

local function statName(key)
  local s = rawget(_G, key)
  return type(s) == "string" and s or nil
end

local function choiceRows(id)
  local rw = Logic.rewards(id)
  local choices = rw and rw.choices or nil
  if not choices or #choices < 2 then
    return nil
  end
  local prices = B:GetService("prices")
  local d = data()
  local list = ns.Worth.choices(choices, {
    name = function(itemID)
      return B:Entity("item:" .. itemID):Name()
    end,
    info = B.Compat.GetItemInfo,
    stats = B.Compat.GetItemStats,
    equipped = B.Compat.GetEquippedItem,
    statName = statName,
    price = function(itemID)
      local p = prices and prices:Price(itemID) or nil
      return p and p.median or nil
    end,
    sell = function(itemID)
      local info = B.Compat.GetItemInfo(itemID) -- the client's sell price first, the pack's else
      if info and info.sellPrice and info.sellPrice > 0 then
        return info.sellPrice
      end
      local r = d and d:Get("item", itemID) or nil
      return r and r.sell or nil
    end,
  })
  local rows = {}
  for _, c in ipairs(list) do
    if not c.loaded and not requestedItems[c.itemID] and B.Compat.RequestItemData(c.itemID) then
      requestedItems[c.itemID] = true
    end
    local title = c.title
    if c.tag then
      title = title .. "  " .. (c.tagGood and R.COLOR.green or R.COLOR.grey) .. c.tag .. "|r"
    end
    rows[#rows + 1] = {
      title = title,
      meta = c.meta,
      text = title .. "  " .. R.COLOR.grey .. c.meta .. "|r", -- the one-line hosts (cards)
      ref = "item:" .. c.itemID,
      icon = c.icon or B:Entity("item:" .. c.itemID):Icon(),
      value = c.value and c.value.copper or nil,
      valueKind = c.value and "money" or nil,
    }
  end
  return rows
end

local function textRows(id)
  local d = data()
  if not d then
    return nil
  end
  local loaded = d:PackLoaded("text")
  local t = loaded and d:Get("questText", id) or nil
  local rows = {}
  local function add(text)
    for _, p in ipairs(R.paragraphs(text)) do
      rows[#rows + 1] = { kind = "para", text = p }
    end
  end
  if t then
    add(t.details) -- the story only: the task stands in What to do (ADR 0052)
    add(t.offer)
  else
    -- not in the pack (retail has no quest texts, data.md): the client's own text of a log quest,
    -- else a note; on Forever the Text pack carries it and Spoken reads it aloud
    local details, objectives = B.Compat.GetQuestText(id)
    add(details)
    if #rows == 0 and not loaded then
      rows[1] = {
        text = R.COLOR.grey .. L["Quest texts are not loaded. Click to load them."] .. "|r",
        onClick = function()
          d:LoadPack("text")
        end,
      }
    elseif #rows == 0 and #R.paragraphs(objectives) == 0 then
      rows[1] = {
        kind = "para",
        text = R.COLOR.grey
          .. L["No quest text in the data for this client; the client shows it once the quest is in the log."]
          .. "|r",
      }
    end
  end
  return #rows > 0 and rows or nil
end

-- "Target of" (guide gaps, 23.10.2026: AHSyncGuide's monster tooltip, so it can be uninstalled):
-- the log quests with a thing to do that needs this NPC: the step's subject, one of several that
-- count, who has its item (the step's way, a place's own ref, the item's loot record). Pure:
-- log = { [questID] = entry }, steps(questID) -> the quest's `steps` facet, item(id) -> record.
-- Rows by quest title, each with that step's own progress or "done"; a step the client's list
-- does not show has no progress (it read another objective's count: plan-quest-links.md S3).
local function stepNeeds(step, npcRef, item)
  if step.ref == npcRef then
    return true
  end
  for _, list in ipairs({ step.refs or {}, step.via or {} }) do
    for _, ref in ipairs(list) do
      if ref == npcRef then
        return true
      end
    end
  end
  for _, p in ipairs(step.places or {}) do
    if p.ref == npcRef then
      return true
    end
  end
  local itemID = type(step.ref) == "string" and tonumber(string.match(step.ref, "^item:(%d+)$"))
  local rec = itemID and item(itemID)
  for _, d in ipairs(rec and rec.drops or {}) do
    if d[1] == npcRef then
      return true
    end
  end
  return false
end

function Reg.TargetOf(npcRef, log, steps, item)
  local rows = {}
  for qid, entry in pairs(log) do
    local hit
    for _, step in ipairs(steps(qid) or {}) do
      local todo = step.step ~= "take" and step.step ~= "handin"
      if todo and (not hit or hit.done) and stepNeeds(step, npcRef, item) then
        hit = step -- the first that is still to do, else one that is done
      end
    end
    if hit then
      local progress
      if entry.isComplete or hit.done then
        progress = L["done"]
      elseif hit.have and hit.count and hit.count > 0 then
        progress = hit.have .. "/" .. hit.count
      end
      rows[#rows + 1] = {
        text = entry.title or B:Entity("quest:" .. qid):Name() or ("quest " .. qid),
        ref = "quest:" .. qid,
        icon = B.UI.IconTexture("questActive"),
        value = progress,
        valueKind = "text",
      }
    end
  end
  table.sort(rows, function(a, b)
    return a.text < b.text
  end)
  return rows
end

local function targetOfRows(ref)
  local d = data()
  if not d then
    return nil
  end
  local rows = Reg.TargetOf(ref, State.log, stepsOf, function(id)
    return id and d:Get("item", id) or nil
  end)
  return #rows > 0 and rows or nil
end

local function registerSections(mod)
  local INVALIDATE = { "BASTIANS_QUESTS_CHANGED", "BASTIANS_TRACKED_CHANGED" }
  B:RegisterDetailSection(mod, {
    id = "quests.target",
    chapter = "quests", -- on the sheet (ADR 0054)
    title = L["Target of"],
    types = { "npc" },
    order = 15,
    invalidateOn = INVALIDATE,
    build = targetOfRows,
    tooltip = {
      max = 3,
      build = function(ref)
        local rows = targetOfRows(ref)
        for _, row in ipairs(rows or {}) do
          row.text = L["Target of"] .. ": " .. row.text -- the tooltip has no block title
        end
        return rows
      end,
    },
  })
  B:RegisterDetailSection(mod, {
    id = "quests.starts",
    chapter = { npc = "quests", object = "quests", item = "use" }, -- on the sheet (ADR 0054)
    title = L["Starts quests"],
    types = { "npc", "object", "item" },
    order = 20,
    invalidateOn = INVALIDATE,
    build = function(ref)
      return questRows("quest.byGiver", ref, true)
    end,
    tooltip = {
      max = 2,
      build = function(ref)
        return questRows("quest.byGiver", ref)
      end,
    },
  })
  B:RegisterDetailSection(mod, {
    id = "quests.ends",
    chapter = "quests", -- on the sheet (ADR 0054)
    title = L["Ends quests"],
    types = { "npc", "object" },
    order = 21,
    invalidateOn = INVALIDATE,
    build = function(ref)
      return questRows("quest.byEnder", ref, true)
    end,
  })
  -- a dungeon's quests (data.md "Dungeons"): the ones ForeverDB confirmed in Forever, under
  -- the status headers, so the page says which to pick up before the run
  B:RegisterDetailSection(mod, {
    id = "quests.dungeon",
    chapter = "quests", -- on the sheet (ADR 0054)
    title = L["Dungeon quests"],
    types = { "dungeon" },
    order = 25,
    invalidateOn = INVALIDATE,
    build = function(ref)
      local _, id = B.Entity.Parse(ref)
      return questRows("quest.byDungeon", id, true)
    end,
    tooltip = {
      max = 3,
      build = function(ref)
        local _, id = B.Entity.Parse(ref)
        return questRows("quest.byDungeon", id)
      end,
    },
  })
  B:RegisterDetailSection(mod, {
    id = "quests.attunement",
    chapter = "attunement", -- on the sheet (ADR 0054)
    title = L["Attunement"],
    types = { "dungeon" },
    order = 23,
    block = { wide = true, limit = 20 },
    invalidateOn = INVALIDATE,
    cache = false, -- the bags and the reputation change without a quest event
    build = dungeonAttunementRows,
  })
  B:RegisterDetailSection(mod, {
    id = "quests.needed",
    chapter = "use", -- on the sheet (ADR 0054)
    title = L["Needed for quests"],
    types = { "item" },
    order = 22,
    invalidateOn = INVALIDATE,
    build = function(ref)
      local _, id = B.Entity.Parse(ref)
      return questRows("quest.byItem", id, true)
    end,
    tooltip = {
      max = 2,
      build = function(ref)
        local _, id = B.Entity.Parse(ref)
        return questRows("quest.byItem", id)
      end,
    },
  })
  B:RegisterDetailSection(mod, {
    id = "quests.status",
    title = L["Status"],
    types = { "quest" },
    order = 5,
    card = true, -- its first row is the card's status line (ADR 0013 B)
    noStats = true, -- the band says level and distance, the blocks the rest (ADR 0052)
    invalidateOn = INVALIDATE,
    build = function(ref)
      return statusText(questID(ref))
    end,
    tooltip = { max = 1 },
  })
  -- the quest dossier (C2, ADR 0014; ADR 0052): What to do first, across the row; Given by, Hand
  -- in and Rewards as one-cell blocks, Quest text across the row; needs, after and
  -- unlocks as links
  B:RegisterDetailSection(mod, {
    id = "quests.objectives",
    chapter = "todo", -- on the sheet (ADR 0054)
    title = L["What to do"],
    types = { "quest" },
    order = 5.5,
    block = { wide = true, limit = 8 },
    invalidateOn = { "BASTIANS_QUESTS_CHANGED", "BASTIANS_TRACKED_CHANGED", "BASTIANS_DATA_LOADED" },
    build = function(ref)
      return objectiveRows(questID(ref))
    end,
  })
  B:RegisterDetailSection(mod, {
    id = "quests.givers",
    chapter = "people", -- on the sheet (ADR 0054)
    title = L["Given by"],
    types = { "quest" },
    order = 6,
    block = { columns = 1 },
    build = function(ref)
      local q = Logic.quest(questID(ref))
      return q and npcRows(q.starts) or nil
    end,
  })
  B:RegisterDetailSection(mod, {
    id = "quests.enders",
    chapter = "people", -- on the sheet (ADR 0054)
    title = L["Hand in"],
    types = { "quest" },
    order = 7,
    block = { columns = 1 },
    build = function(ref)
      local q = Logic.quest(questID(ref))
      return q and npcRows(q.ends) or nil
    end,
  })
  B:RegisterDetailSection(mod, {
    id = "quests.rewards",
    chapter = "rewards", -- on the sheet (ADR 0054)
    title = L["Rewards"],
    types = { "quest" },
    order = 8,
    block = { columns = 1, limit = 8, table = true }, -- a small table (ADR 0018 D)
    invalidateOn = { "BASTIANS_PRICES_UPDATED", "BASTIANS_QUESTS_CHANGED", "BASTIANS_REWARD_INFO_CHANGED" },
    build = function(ref)
      return rewardRows(questID(ref))
    end,
    tooltip = { -- the chain and the rewards under every host's quest tooltip (the Orbiter's marks)
      max = 8,
      build = function(ref)
        return rewardTipRows(questID(ref))
      end,
    },
  })
  B:RegisterDetailSection(mod, {
    id = "quests.choice",
    chapter = "rewards", -- on the sheet (ADR 0054)
    title = L["Which reward"],
    types = { "quest" },
    order = 8.5, -- right under Rewards, before Objectives
    block = { wide = true, twoLine = true, limit = 6 },
    invalidateOn = { "BASTIANS_PRICES_UPDATED", "BASTIANS_REWARD_INFO_CHANGED" },
    build = function(ref)
      return choiceRows(questID(ref))
    end,
  })
  B:RegisterDetailSection(mod, {
    id = "quests.text",
    chapter = "text", -- on the sheet (ADR 0054)
    title = L["Quest text"],
    types = { "quest" },
    order = 40,
    block = { wide = true, limit = 20 },
    build = function(ref)
      return textRows(questID(ref))
    end,
  })
  B:RegisterDetailSection(mod, {
    id = "quests.needs",
    title = L["Needs"],
    types = { "quest" },
    order = 50,
    link = L["needs"],
    cache = false,
    build = function(ref)
      return needsRows(questID(ref))
    end,
  })
  B:RegisterDetailSection(mod, {
    id = "quests.after",
    title = L["After"],
    types = { "quest" },
    order = 51,
    link = L["after"],
    invalidateOn = INVALIDATE,
    build = function(ref)
      return afterRows(questID(ref))
    end,
  })
  B:RegisterDetailSection(mod, {
    id = "quests.unlocks",
    title = L["Unlocks"],
    types = { "quest" },
    order = 52,
    link = L["unlocks"],
    invalidateOn = INVALIDATE,
    build = function(ref)
      return unlocksRows(questID(ref))
    end,
  })
end

-- ---------------------------------------------------------------------------------------------
-- Search provider: quest texts when the pack is loaded, else the offer to load it
-- ---------------------------------------------------------------------------------------------

local function registerSearch(mod)
  B:RegisterSearchProvider(mod, {
    id = "quests.text",
    label = L["Quest texts"],
    priority = 40,
    search = function(query, limit, yield, q)
      local d = data()
      if not d or #query < 3 then
        return {}
      end
      q = q or B.Query.Compile(query) -- the suite's search syntax (ADR 0045)
      if not d:PackLoaded("text") then
        return {
          {
            ref = nil,
            label = L["Load quest texts to search them"],
            score = 0.3,
            action = function()
              d:LoadPack("text")
            end,
          },
        }
      end
      local out, n = {}, 0
      for _, qid in ipairs(Logic.allQuestIDs()) do
        n = n + 1
        if n % 200 == 0 then
          yield()
        end
        local t = d:Get("questText", qid)
        if t then
          local hay = string.lower((t.details or "") .. " " .. (t.objectives or ""))
          if q:MatchLower(hay) then
            out[#out + 1] =
              { ref = "quest:" .. qid, label = R.questName(qid), score = 0.5, note = L["quest text"] }
            if #out >= (limit or 50) then
              break
            end
          end
        end
      end
      return out
    end,
  })
end

-- ---------------------------------------------------------------------------------------------
-- The zone page (ADR 0013 A): "To do here" (the ranking), the log's quests of the zone by status
-- (Hand in, In progress, To take, Later, Onward, Prerequisite elsewhere, Done folded) and the
-- neighbouring zones, as detail sections of `zone:<map>`. One V.zone and one V.here per map,
-- remembered until the next quest, zone or data change (Window.Schedule bumps the generation).
-- ---------------------------------------------------------------------------------------------

local V = ns.Views
local TODO_SHOWN = 5 -- the ranking's top rows on the page; the rest fold under "More"
local zoneGen = 0
-- colour set -> map -> { gen, byKey, counts, here }. The rows carry colour codes and colours, so a
-- page on paper and the dark panes each keep their own (a zone's quests
-- stood in the theme's yellow, teal and grey on parchment; the first host to ask had built them).
local zoneCache = setmetatable({}, { __mode = "k" })

function Reg.InvalidateZone()
  zoneGen = zoneGen + 1
end

-- The zone of a zone page, or of an area page the zone the area lies in (owner, retail
-- 31.10.2026: "the subzone ... I would expect the same information as in the main zone").
local function zoneMap(ref)
  local typ, id = B.Entity.Parse(ref)
  if typ == "area" then
    local d = data()
    return d and d.AreaScope and d:AreaScope(id) or nil
  end
  return typ == "zone" and tonumber(id) or nil
end

-- An area page's test of map points (Data's AreaScope), nil on a zone page.
local function areaTest(ref)
  local typ, id = B.Entity.Parse(ref)
  local d = typ == "area" and data()
  if not (d and d.AreaScope) then
    return nil
  end
  local _, inside = d:AreaScope(id)
  return inside
end

-- The zone's rows that lie in the area: a giver's row by its point, a quest by its givers' or
-- takers' places, a row without either by the rows under it.
local function questIn(qid, inside)
  local q = Logic.quest(qid)
  if not q then
    return false
  end
  for _, places in ipairs({ q.startPlaces or {}, q.endPlaces or {} }) do
    for _, p in ipairs(places) do
      if inside(p[1], p[2], p[3]) then
        return true
      end
    end
  end
  local d = data() -- a record without places: where its givers and takers stand
  for _, refs in ipairs({ q.starts or {}, q.ends or {} }) do
    for _, ref in ipairs(refs) do
      for _, s in ipairs(d and type(ref) == "string" and d:Spawns(ref) or {}) do
        if inside(s.map, s.x, s.y) then
          return true
        end
      end
    end
  end
  return false
end
Reg.ZoneMap, Reg.AreaTest, Reg.QuestIn = zoneMap, areaTest, questIn -- Chains.lua: "Chains here"
local function inArea(rows, inside)
  local out = {}
  for _, row in ipairs(rows) do
    if row.map and row.x and row.y then
      if inside(row.map, row.x, row.y) then
        out[#out + 1] = row
      end
    elseif row.qid then
      if questIn(row.qid, inside) then
        out[#out + 1] = row
      end
    elseif row.children then
      local kids = inArea(row.children, inside)
      if #kids > 0 then
        local copy = {}
        for k, v in pairs(row) do
          copy[k] = v
        end
        copy.children = kids
        out[#out + 1] = copy
      end
    end
  end
  return out
end
Reg.InArea = inArea

local function zoneData(map)
  local tone = B.UI.Style.H -- the colour set in force
  local byMap = zoneCache[tone]
  if not byMap then
    byMap = {}
    zoneCache[tone] = byMap
  end
  local c = byMap[map]
  if c and c.gen == zoneGen then
    return c
  end
  local W = ns.Window
  local state = State.ForLogic()
  local px, py = W.PlayerOn(map)
  local roots, counts = V.zone(map, state, px, py, {
    showDone = true,
    progressOf = function(qid)
      local e = State.log[qid]
      return e and R.progressText(e) or nil
    end,
  })
  local byKey = {}
  for _, root in ipairs(roots) do
    if root.key then
      byKey[root.key] = root
    end
  end
  c = { gen = zoneGen, byKey = byKey, counts = counts or {}, state = state }
  if Logic.knows(map) then
    local rows = V.here(map, state, W.RecommendContext(map), State.facts.faction, nil)
    for _, root in ipairs(rows) do
      if root.key == "recs" then
        c.here = root.children
      elseif root.key == "hidden" then
        c.hidden = root.children -- the quests the player hid (R3)
      end
    end
  end
  byMap[map] = c
  return c
end

local ZONE_SECTIONS = {
  { "turnin", "Hand in", 3 },
  { "active", "In progress", 4 },
  -- folded on the sheet until clicked (ADR 0054): what cannot be acted on now
  { "available", "To take", 5, true },
  { "soon", "Later", 6, true },
  { "onward", "Onward", 7, true },
  { "blocked", "Prerequisite elsewhere", 8, true },
  { "done", "Done", 9, true },
}
local ZONE_INVALIDATE = {
  "BASTIANS_QUESTS_CHANGED",
  "BASTIANS_TRACKED_CHANGED",
  "BASTIANS_PLAYER_MOVED_ZONE",
  "BASTIANS_DATA_LOADED",
  "BASTIANS_QUESTS_VIEWS",
}

Reg.ZONE_INVALIDATE = ZONE_INVALIDATE

-- A title with the row count, for the zone page's blocks (the Here blocks leave the count to the
-- dossier, which prints it for them).
local function countTitle(title)
  return function(_, rows)
    local n = rows.count or #rows
    return L[title] .. "  " .. R.COLOR.grey .. tostring(n) .. "|r"
  end
end

local function neighbourRows(ref)
  local map = zoneMap(ref)
  if not (map and Logic.knows(map)) then
    return nil
  end
  local faction = State.facts.faction
  local rows = {}
  local function add(m, mark)
    if not m or m == map then
      return
    end
    local band = R.band(Logic.zoneInfo(m))
    local text = R.COLOR.grey .. mark .. " |r" .. R.COLOR.white .. R.zoneName(m) .. "|r"
    if band ~= "" then
      text = text .. "  " .. R.COLOR.grey .. band .. "|r"
    end
    rows[#rows + 1] = R.zone(m, text)
  end
  local prev = Logic.neighbor(map, faction, -1)
  if prev ~= map then
    add(Logic.neighbor(prev, faction, -1), "<<")
    add(prev, "<")
  end
  local nxt = Logic.neighbor(map, faction, 1)
  if nxt ~= map then
    add(nxt, ">")
    add(Logic.neighbor(nxt, faction, 1), ">>")
  end
  return #rows > 0 and rows or nil
end

local function registerZoneSections(mod)
  B:RegisterDetailSection(mod, {
    id = "quests.zone.todo",
    chapter = "quests", -- on the sheet (ADR 0054)
    title = countTitle("To do here"),
    types = { "zone", "area" },
    order = 2,
    invalidateOn = ZONE_INVALIDATE,
    build = function(ref)
      local map = zoneMap(ref)
      local here = map and zoneData(map).here
      local inside = areaTest(ref)
      if here and inside then
        here = inArea(here, inside)
      end
      if not (here and #here > 0) then
        return nil
      end
      local rows = {}
      for i = 1, math.min(TODO_SHOWN, #here) do
        rows[i] = here[i]
      end
      if #here > TODO_SHOWN then
        local more = {}
        for i = TODO_SHOWN + 1, #here do
          more[#more + 1] = here[i]
        end
        rows[#rows + 1] = {
          id = "todo:more",
          text = R.COLOR.grey .. L["More"] .. "  " .. #more .. "|r",
          children = more,
          collapsed = true,
        }
      end
      rows.count = #here
      return rows
    end,
  })
  for _, s in ipairs(ZONE_SECTIONS) do
    local key, title, order, folded = s[1], s[2], s[3], s[4]
    B:RegisterDetailSection(mod, {
      id = "quests.zone." .. key,
      chapter = "quests", -- on the sheet (ADR 0054)
      title = countTitle(title),
      types = { "zone", "area" },
      order = order,
      collapsed = folded or nil,
      invalidateOn = ZONE_INVALIDATE,
      build = function(ref)
        local map = zoneMap(ref)
        if not map then
          return nil
        end
        local c = zoneData(map)
        local root = c.byKey[key]
        if not (root and root.children and #root.children > 0) then
          return nil
        end
        local inside = areaTest(ref)
        if inside then
          local rows = inArea(root.children, inside)
          if #rows == 0 then
            return nil
          end
          return rows
        end
        local rows = {}
        for i, row in ipairs(root.children) do
          rows[i] = row
        end
        rows.count = c.counts[key] or root.count
        return rows
      end,
    })
  end
  B:RegisterDetailSection(mod, {
    id = "quests.zone.neighbours",
    chapter = "roads", -- on the sheet (ADR 0054)
    title = L["Neighbours"],
    types = { "zone" },
    order = 13,
    invalidateOn = { "BASTIANS_DATA_LOADED" },
    build = neighbourRows,
  })
end

-- ---------------------------------------------------------------------------------------------
-- The Here column (C4): "Do here" and "My quests here" on the player's zone
-- ---------------------------------------------------------------------------------------------

-- How far a map point is from the player (Bastians.UI.Away): the travel time's text and a
-- number to sort by; nil when unknown.
local function awayTo(map, x, y)
  if not (map and x and y) then
    return nil
  end
  local c, wx, wy = B.Coords.ToWorld(map, x, y)
  if not c then
    return nil
  end
  return B.UI.Away({ map = c, wx = wx, wy = wy })
end

-- "Do here": the ranking, best first; the rows lose their "/min" value so the worth shows (C3).
local function hereTodoRows(ref)
  local map = zoneMap(ref)
  local here = map and zoneData(map).here
  if not (here and #here > 0) then
    return nil
  end
  local rows = {}
  for i, src in ipairs(here) do
    local row = {}
    for k, v in pairs(src) do
      row[k] = v
    end
    row.id = "here:todo:" .. tostring(src.qid or i)
    row.value, row.valueKind, row.children = nil, nil, nil
    rows[i] = row
  end
  return rows
end

-- "My quests here": the log entries with a step on this map (a hand-in or an objective spot),
-- nearest step first, the distance after the words; the quest item beside the row through the
-- secure bar (`onRender`, below), as the log view does.
local function hereLogRows(ref)
  local map = zoneMap(ref)
  if not map then
    return nil
  end
  local W = ns.Window
  local px, py = W.PlayerOn(map)
  local opts = W.LogFilters() -- the tracker's filters apply here too
  opts.questItem, opts.onOpen = W.QuestItemOf, ns.Sheet.Toggle
  local roots = V.active(map, px, py, opts)
  local rows = {}
  for _, root in ipairs(roots) do
    if root.key == "a_turnin" or root.key == "a_goals" then
      for _, src in ipairs(root.children or {}) do
        local row = {}
        for k, v in pairs(src) do
          row[k] = v
        end
        row.id = "here:log:" .. tostring(src.qid or row.id)
        row.children = nil
        local dist, d = awayTo(row.map, row.x, row.y)
        row.d = d
        row.text = (row.text or "") .. "  " .. R.COLOR.grey .. (dist or L["distance unknown"]) .. "|r"
        rows[#rows + 1] = row
      end
    end
  end
  table.sort(rows, function(a, b)
    if (a.d or math.huge) ~= (b.d or math.huge) then
      return (a.d or math.huge) < (b.d or math.huge)
    end
    return (a.text or "") < (b.text or "")
  end)
  return #rows > 0 and rows or nil
end

-- "Hidden": the quests the player hid from Do here on this map, greyed,
-- folded to a "+N more" row until clicked; the Hide icon on a row unhides it.
local function hereHiddenRows(ref)
  local map = zoneMap(ref)
  local hidden = map and zoneData(map).hidden
  if not (hidden and #hidden > 0) then
    return nil
  end
  local rows = {}
  for i, src in ipairs(hidden) do
    local row = {}
    for k, v in pairs(src) do
      row[k] = v
    end
    row.id = "here:hidden:" .. tostring(src.qid or i)
    row.value, row.valueKind, row.children = nil, nil, nil
    rows[i] = row
  end
  return rows
end

local function registerHereSections(mod)
  B:RegisterDetailSection(mod, {
    id = "quests.here.hidden",
    title = L["Hidden"],
    types = { "zone" },
    order = 97,
    here = { order = 1.5, limit = 0, only = true },
    invalidateOn = ZONE_INVALIDATE,
    build = hereHiddenRows,
  })
  -- the stat tiles of Here (ADR 0058, PH4): what to do here, what is ready to hand in
  B:RegisterStat(mod, {
    id = "quests.stat.todo",
    rail = "here",
    order = 10,
    title = L["To do here"],
    invalidateOn = ZONE_INVALIDATE,
    build = function()
      local map = B.Coords.PlayerMap()
      if not map then
        return nil -- no zone known: unknown, not 0
      end
      local here = zoneData(map).here
      return { value = here and #here or 0 }
    end,
  })
  B:RegisterStat(mod, {
    id = "quests.stat.handin",
    rail = "here",
    order = 20,
    title = L["Hand in"],
    invalidateOn = { "BASTIANS_QUESTS_CHANGED" },
    build = function()
      local n = 0
      for _, id in ipairs(State.order) do
        if State.IsReady(id) then
          n = n + 1
        end
      end
      return { value = n, nav = { kind = "view", id = "quests.log" } }
    end,
  })
  B:RegisterDetailSection(mod, {
    id = "quests.here.todo",
    title = L["Do here"], -- the dossier prints the count
    types = { "zone" },
    order = 95,
    here = { order = 1, limit = 5, only = true },
    invalidateOn = ZONE_INVALIDATE,
    build = hereTodoRows,
  })
  B:RegisterDetailSection(mod, {
    id = "quests.here.log",
    title = L["My quests here"],
    -- the log toggles on the block's title line, the same flags as the log view and the hub
    --
    controls = function()
      local p = mod.db.profile
      local function toggle(key, label, tip)
        return {
          label = label,
          on = p[key] == true,
          tooltip = tip,
          onClick = function()
            p[key] = p[key] ~= true
            B:Fire("BASTIANS_TRACKED_CHANGED")
          end,
        }
      end
      local hideDone = "While on, quests you completed and only need to hand in are left out."
        .. " Click to switch."
      local tracked = "While on, only tracked quests are listed. A quest is tracked when its ? icon"
        .. " is green; click the icon on its row to track or untrack it. Tracked quests are the"
        .. " ones the objective tracker shows."
      return {
        toggle("logHideDone", L["Hide done"], L[hideDone]),
        toggle("logTrackedOnly", L["Tracked"], L[tracked]),
      }
    end,
    types = { "zone" },
    order = 96,
    here = { order = 2, limit = 6, only = true },
    invalidateOn = ZONE_INVALIDATE,
    build = hereLogRows,
    onRender = function(rows, host) -- the usable quest items of these rows, beside the host
      ns.Window.SetItemBar(ns.Window.ItemsOf(rows), host)
    end,
    onHide = function()
      ns.Window.SetItemBar(nil)
    end,
  })
end

-- ---------------------------------------------------------------------------------------------
-- Wiring, once per enable
-- ---------------------------------------------------------------------------------------------

local function layersChanged(mod)
  Reg.ResetCaches()
  for _, id in ipairs(LAYERS) do
    mod:Fire("BASTIANS_LAYER_CHANGED", id)
  end
end

-- The Browser's "Quest chains" list ("an easier way to find quest
-- chains, a list of its own"): one row per chain this character can take, faceted by its first
-- step's level band. Since ADR 0055 (PA5.2) a row is the chain itself (`chain:<root>`, Chains.lua):
-- its tile says the steps, the zones, the levels and how far the character is; ~~a row opens the
-- first quest, whose page shows the chain~~.
local function levelBand(level)
  if not level then
    return "no level"
  end
  local lo = math.floor((level - 1) / 10) * 10 + 1
  return lo .. "-" .. (lo + 9)
end

-- How a chain's progress reads, as a group's heading and a filter's choice (quests.md "The list").
local PROGRESS_WORDS = {
  on = "On your way",
  start = "Can start now",
  later = "Later",
  finished = "Finished",
}
local CHAIN_INVALIDATE = { "BASTIANS_QUESTS_CHANGED", "BASTIANS_DATA_LOADED" }

local function registerLists(mod)
  -- the names that more than one chain carries: such a row says where its way starts (C1).
  -- Counted when the list asks for its ids, so a build reads one count
  local shared = {}
  B:RegisterList(mod, {
    type = "chain",
    label = "Chains", -- the model's word (ADR 0056); "Quest chains" until 06.11.2026
    glyph = "chain", -- not the quest's "!"
    facet = "level",
    chips = true, -- several level bands at once
    groupBy = "quests.chain.progress", -- opens grouped by how far the character is (ADR 0055)
    ids = function()
      local roots = Logic.chainRoots()
      local state, count = State.ForLogic(), {}
      for _, root in ipairs(roots) do
        local name = Logic.chainName(root, state)
        if name then
          count[name] = (count[name] or 0) + 1
        end
      end
      shared = count
      return roots
    end,
    record = function(root)
      local c = ns.Chains.Sheet(root)
      if not c then
        return nil
      end
      local first = Logic.quest(c.main[1])
      local name = ns.Chains.Name(c)
      return {
        name = name,
        level = first and first.level or nil,
        zone = c.zones[1], -- where the way starts: the list's Where and its zone groups
        steps = #c.main,
        first = c.main[1],
        state = c.state,
        apart = (shared[name] or 0) > 1 and c.zones[1] and R.zoneName(c.zones[1]) or nil,
      }
    end,
    value = function(r)
      return levelBand(r.level)
    end,
    suffix = function(r)
      return r.apart
    end,
    ref = function(root)
      return "chain:" .. root
    end,
  })
  local function chainOf(ref)
    local typ, id = B.Entity.Parse(ref)
    return typ == "chain" and tonumber(id) or nil
  end
  -- the list's own dimensions (quests.md "The list"): how far the character is (also the
  -- default groups), what kind of chain, pairs apart from the longer ones
  B:RegisterFilter(mod, {
    id = "quests.chain.progress",
    kind = "facet",
    types = { "chain" },
    label = L["Progress"],
    chips = true,
    group = true,
    value = function(_, r)
      return r and r.state or nil
    end,
    labels = function(key)
      return PROGRESS_WORDS[key] and L[PROGRESS_WORDS[key]] or L[key]
    end,
    order = function(key)
      return Logic.PROGRESS_ORDER[key] or 9
    end,
    invalidateOn = CHAIN_INVALIDATE,
  })
  B:RegisterFilter(mod, {
    id = "quests.chain.kind",
    kind = "facet",
    types = { "chain" },
    label = L["Kind"],
    chips = true,
    value = function(ref)
      local root = chainOf(ref)
      return root and Logic.chainKinds(root, State.ForLogic()) or nil
    end,
    labels = function(key)
      return key == "Other" and L["Ordinary"] or L[key]
    end,
    invalidateOn = { "BASTIANS_DATA_LOADED" },
  })
  B:RegisterFilter(mod, {
    id = "quests.chain.length",
    kind = "facet",
    types = { "chain" },
    label = L["Steps"],
    value = function(_, r)
      return r and (r.steps <= 2 and "pair" or "longer") or nil
    end,
    labels = function(key)
      return key == "pair" and L["Pairs"] or L["Three steps or more"]
    end,
    order = function(key)
      return key == "pair" and 2 or 1
    end,
    invalidateOn = { "BASTIANS_DATA_LOADED" },
  })
  -- The Quests list's Status and Type ("All quests does not load ...
  -- whats the difference to the normal quest list"): the All quests view's two filters on the
  -- Browser's one quest list, which then covers the view (`coveredBy`, Window.lua).
  local statusState, statusGen
  local function stateNow()
    local gen = B:FilterGeneration("quests.status")
    if statusGen ~= gen then
      statusState, statusGen = State.ForLogic(), gen
    end
    return statusState
  end
  local statusOrder = {}
  for i, key in ipairs(V.STATUS) do
    statusOrder[key] = i
  end
  B:RegisterFilter(mod, {
    id = "quests.status",
    kind = "facet",
    types = { "quest" },
    label = L["Status"],
    chips = true,
    value = function(ref)
      local qid = questID(ref)
      local q = qid and Logic.quest(qid)
      if not q then
        return nil
      end
      local state = stateNow()
      return V.statusKey(Logic.status(qid, state), q, state)
    end,
    labels = function(key)
      return L[V.STATUS_LABEL[key] or key]
    end,
    order = function(key)
      return statusOrder[key] or 100
    end,
    invalidateOn = { "BASTIANS_QUESTS_CHANGED" }, -- a hand-in, an accepted quest, a level
  })
  B:RegisterFilter(mod, {
    id = "quests.kind",
    kind = "facet",
    types = { "quest" },
    label = L["Type"],
    value = function(ref)
      local qid = questID(ref)
      local q = qid and Logic.quest(qid)
      return q and V.KindsOf(q) or nil
    end,
    labels = function(key)
      return L[key]
    end,
  })
end
Reg.LevelBand = levelBand

-- ---------------------------------------------------------------------------------------------
-- Activity (R26.11, route.md "Explore"): the quest as something to do now, timed by Recommend's
-- estimate, above Data's rule (priority 100); and the quests worth asking about
-- ---------------------------------------------------------------------------------------------

Reg.EXPLORE_BELOW, Reg.EXPLORE_ABOVE = 2, 2 -- the zones whose level band meets the character's

-- The quests in the log and those the character can take now in its zone and the zones of its level.
function Reg.ExploreQuests()
  local state = State.ForLogic()
  local out = {}
  for qid in pairs(State.log or {}) do
    out[#out + 1] = "quest:" .. qid
  end
  local here = ns.Window.PlayerPlace()
  local maps = { here }
  local level = state.level
  if level then
    for _, z in ipairs(Logic.zones(state.faction)) do
      local fits = z.lo and z.hi and z.lo <= level + Reg.EXPLORE_ABOVE and z.hi >= level - Reg.EXPLORE_BELOW
      if fits and z.map ~= here then
        maps[#maps + 1] = z.map
      end
    end
  end
  for _, map in ipairs(maps) do
    for _, g in ipairs(Logic.zoneView(map, state).available) do
      for _, qid in ipairs(g.quests) do
        if not State.IsHidden(qid) then
          out[#out + 1] = "quest:" .. qid
        end
      end
    end
  end
  return out
end

-- { kind = "quest", takes, gives, status, src = "estimate" }: XP by the character's level, the
-- money and the reward items (the choices as one), the time from the next place on.
function Reg.QuestActivity(ref)
  local qid = questID(ref)
  local q = qid and Logic.quest(qid)
  if not q then
    return nil
  end
  local Rec = ns.Recommend
  local state = State.ForLogic()
  local entry = State.log[qid]
  local ctx = ns.Window.RecommendContext(nil)
  local hard = q.level and state.level and q.level - state.level >= 3
  local map, px, py = ns.Window.PlayerPlace()
  ctx.px, ctx.py = px, py
  local minutes = Rec.workMinutes(qid, entry, map, ctx, ctx.objectiveTime, hard and 1.5 or 1)
  local gives = { { kind = "xp", amount = (Rec.questXP(qid, q, state.level)) } }
  local rw = Logic.rewards(qid) or {}
  if rw.money and rw.money > 0 then
    gives[#gives + 1] = { kind = "copper", amount = rw.money }
  end
  for _, it in ipairs(rw.items or {}) do
    gives[#gives + 1] = { kind = "item", id = it[1], amount = it[2] or 1 }
  end
  for _, it in ipairs(rw.choices or {}) do
    gives[#gives + 1] = { kind = "item", id = it[1], amount = it[2] or 1, choice = true }
  end
  return {
    kind = "quest",
    places = B:Entity(ref):Places(), -- where it is done now: the open steps' (S7: it had none)
    takes = minutes * 60,
    gives = gives,
    status = entry and "log" or Logic.status(qid, state),
    src = "estimate",
  }
end

-- What a quest's tile says to this character (ADR 0056; the facet "tile", core-contracts §4):
-- its state as the picture, the giver under the name with the quest's first mark (Dungeon,
-- Repeatable, a festival), its place in its chain as a mark. Data adds the level as the badge.
function Reg.QuestTile(ref)
  local qid = questID(ref)
  local q = qid and Logic.quest(qid)
  if not q then
    return nil
  end
  local s = State.ForLogic()
  local status = Logic.status(qid, s)
  if status == "log" and s.isComplete(qid) then
    status = "complete"
  end
  local giver = q.starts and q.starts[1] and B:Entity(q.starts[1]):Name() or nil
  local mark = Logic.marks(q)[1]
  mark = mark and L[mark] or nil
  local place = Logic.chainPlace(qid, s)
  return {
    icon = R.statusTexture(status),
    line = giver and mark and (giver .. ", " .. mark) or giver or mark,
    mark = place and place.step and { text = place.step .. "/" .. place.steps } or nil,
  }
end

-- A giver's tile: how many quests it has for the character now, as a mark. Counted here, not from
-- the layers' cache: that one is reset a moment after the quests change.
function Reg.GiverTile(ref)
  local d = data()
  local ids = d and d:Index("quest.byGiver", ref)
  if type(ids) ~= "table" then
    return nil
  end
  local s = State.ForLogic()
  local n = 0
  for _, qid in ipairs(ids) do
    if Logic.status(qid, s) == "available" then
      n = n + 1
    end
  end
  return n > 0 and { mark = { text = "!" .. n, token = "svcQuest" } } or nil
end

local function registerTiles(mod)
  local on = { "BASTIANS_QUESTS_CHANGED", "BASTIANS_DATA_LOADED" }
  B:RegisterFacet(mod, {
    facet = "tile",
    types = { "quest" },
    priority = 150,
    invalidateOn = on,
    rule = Reg.QuestTile,
  })
  B:RegisterFacet(mod, {
    facet = "tile",
    types = { "npc", "object" },
    priority = 150,
    invalidateOn = on,
    rule = Reg.GiverTile,
  })
end

local function registerActivity(mod)
  B:RegisterFacet(mod, {
    facet = "activity",
    types = { "quest" },
    priority = 150,
    invalidateOn = { "BASTIANS_QUESTS_CHANGED", "BASTIANS_DATA_LOADED", "BASTIANS_PLAYER_MOVED_ZONE" },
    rule = Reg.QuestActivity,
    list = Reg.ExploreQuests,
  })
end

function Reg.Register(mod)
  mod.Registrations = Reg -- for the tests and the perf scripts
  registerLayers(mod)
  Reg.BuildGiverIndex(mod) -- the data may be there already (packs load at startup, ADR 0011)
  registerActions(mod)
  registerSections(mod)
  registerZoneSections(mod)
  registerHereSections(mod)
  registerSearch(mod)
  registerLists(mod) -- the Browser's Quest chains list
  ns.Worth.Register(mod) -- the worth of a quest (C3)
  registerActivity(mod) -- the quest as an activity for Explore (R26.11)
  registerTiles(mod) -- what a quest's and a giver's tile say (ADR 0056)
  Reg.ResetCaches()
  Reg.InvalidateZone()
  mod:On("BASTIANS_ENTITY_FOCUSED", function(me) -- the focused quest takes the map
    me:Fire("BASTIANS_LAYER_CHANGED", "quests.objectives")
    me:Fire("BASTIANS_LAYER_CHANGED", "quests.turnin")
  end)
  mod:RegisterEvent("QUEST_WATCH_LIST_CHANGED", function(me)
    Reg.SyncTracked(me)
  end)
end

-- Called by the module on BASTIANS_QUESTS_CHANGED (coalesced there): the statuses may differ.
function Reg.OnChanged(mod)
  Reg.InvalidateZone()
  layersChanged(mod)
end

-- Called by the module on BASTIANS_DATA_LOADED and when the data service changes: new records and
-- transforms, so the giver index is rebuilt (the layers re-query when it is ready) and the statuses
-- are dropped.
function Reg.OnDataLoaded(mod)
  Reg.BuildGiverIndex(mod)
  layersChanged(mod)
end
