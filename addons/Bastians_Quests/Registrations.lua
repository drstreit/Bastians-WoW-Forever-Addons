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
local COLOR = {
  available = S.C.gold,
  soon = S.C.dim,
  blocked = S.C.muted,
  complete = S.C.gold,
  incomplete = S.C.dim,
}
local SPOT_ICON = { loot = "mob", kill = "mob", object = "treasure", item = "item", event = "zone" }
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

-- giver ref -> "available" | "soon" | "blocked" | false, cached until the quests change
local giverStatus = {}
local giverQuests = {} -- giver ref -> { qid, ... } of the quests behind its status, for the pin

function Reg.ResetCaches()
  giverStatus = {}
  giverQuests = {}
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
  local byStatus = { available = {}, soon = {}, blocked = {} }
  for _, qid in ipairs(ids or {}) do
    local st = Logic.status(qid, s)
    if st == "available" then
      best = "available"
      table.insert(byStatus.available, qid)
    elseif st == "level" then
      local q = Logic.quest(qid)
      if (q.minLevel or 0) - s.level <= Logic.SOON then
        table.insert(byStatus.soon, qid)
        if best ~= "available" then
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
      }
    end
  end)
  return pins
end

local function turnInPins(view)
  local pins, seen = {}, {}
  for _, qid in ipairs(State.order) do
    local e = State.log[qid]
    local q = Logic.quest(qid)
    for _, ref in ipairs(q and q.ends or {}) do
      local pin = seen[ref]
      if pin then
        if e.isComplete and not pin.complete then
          pin.complete, pin.color, pin.priority = true, COLOR.complete, 70
        end
      else
        local wx, wy = inView(ref, view)
        if wx then
          pin = {
            ref = ref,
            wx = wx,
            wy = wy,
            icon = B.UI.IconTexture("questActive"),
            color = e.isComplete and COLOR.complete or COLOR.incomplete,
            label = B:Entity(ref):Name(),
            priority = e.isComplete and 70 or 55,
            cluster = true,
            complete = e.isComplete or false,
          }
          seen[ref] = pin
          pins[#pins + 1] = pin
        end
      end
    end
  end
  return pins
end

local function objectivePins(view)
  local pins = {}
  local function add(qid, e, map, x, y, kind)
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
        label = e.title,
        priority = 65,
        cluster = false,
        radius = OBJECTIVE_RADIUS,
      }
    end
  end
  local withoutSpots = {} -- log quests the pack has no spots for (retail, D2)
  for _, qid in ipairs(State.order) do
    local e = State.log[qid]
    local q = Logic.quest(qid)
    if not e.isComplete then
      if q and q.spots then
        for map, list in pairs(q.spots) do
          for _, s in ipairs(list) do
            add(qid, e, map, s[1], s[2], s[3])
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
    label = L["Quests to take"],
    defaultOn = true,
    minLevel = 2,
    query = function(view)
      return giverPins(view, { available = true }, 60)
    end,
  })
  B:RegisterMapLayer(mod, {
    id = "quests.soon",
    label = L["Quests soon (level, prerequisite)"],
    defaultOn = false,
    minLevel = 3,
    query = function(view)
      return giverPins(view, { soon = true, blocked = true }, 40)
    end,
  })
  B:RegisterMapLayer(mod, {
    id = "quests.turnin",
    label = L["Quest hand-ins"],
    defaultOn = true,
    minLevel = 1,
    query = turnInPins,
  })
  B:RegisterMapLayer(mod, {
    id = "quests.objectives",
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

-- Quest places by status: the places of a quest that matter now.
-- Not in the log: the giver. In the log and open: the targets (the pack's objective spots, else
-- the client's waypoint on the player's map, D2). Complete: the hand-in. Without a place of that
-- kind every place stays, so "Show on map" never goes blind.
local function clientStep(id)
  local map = B.Coords.PlayerMap()
  if not map then
    return nil
  end
  local x, y = B.Compat.GetQuestWaypoint(id, map)
  if x and y then
    return { map = map, x = x, y = y, kind = "objective", src = "client" }
  end
  return nil
end

local function placesOfKind(points, kind)
  local out = {}
  for _, p in ipairs(points) do
    if p.kind == kind then
      out[#out + 1] = p
    end
  end
  return out
end

-- The kind the quest's status asks for: "giver", "objective" or "turnin".
local function nextKind(id)
  local entry = State.log[id]
  if not entry then
    return "giver"
  elseif entry.isComplete or entry.readyForTurnIn then
    return "turnin"
  end
  return "objective"
end

-- The places of a kind for the quest, the client's step filling in for missing targets.
local function questPlaces(ref, kind)
  local id = questID(ref)
  if not id then
    return {}
  end
  local out = placesOfKind(B:Entity(ref):AllLocations(), kind)
  if #out == 0 and kind == "objective" and State.log[id] then
    local step = clientStep(id)
    if step then
      out[1] = step
    end
  end
  return out
end

local function registerPlaces(mod)
  B:RegisterLocationFilter(mod, {
    id = "quests.next",
    types = { "quest" },
    filter = function(ref, points)
      local id = questID(ref)
      if not id then
        return points
      end
      local wanted = placesOfKind(points, nextKind(id))
      local entry = State.log[id]
      if #wanted == 0 and entry and not (entry.isComplete or entry.readyForTurnIn) then
        local step = clientStep(id)
        if step then
          return { step }
        end
      end
      return #wanted > 0 and wanted or points
    end,
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
Reg.NextKind = nextKind

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
  log = { "In your log", "white", 3 },
  complete = { "Ready to turn in", "green", 0 },
  done = { "Done", "grey", 6 },
  level = { "Needs level %d", "grey", 4 },
  prereq = { "Needs another quest first", "grey", 5 },
  skill = { "Needs a profession skill", "grey", 5 },
  rep = { "Needs reputation", "grey", 5 },
  superseded = { "Replaced by another quest", "grey", 7 },
  never = { "Not for this character", "grey", 7 },
}

local function shortStatus(id, s)
  local st = Logic.status(id, s)
  local e = st == "log" and State.log[id] or nil
  if e and e.isComplete then
    st = "complete"
  end
  local def = SHORT_STATUS[st] or SHORT_STATUS.never
  local text = L[def[1]]
  if st == "level" then
    local q = Logic.quest(id)
    text = string.format(text, q and q.minLevel or 0)
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
  [3] = "In your log",
  [4] = "Later",
  [5] = "Later",
  [6] = "Done",
  [7] = "Not for this character",
}

-- A Play button on a quest row when Spoken has a line for it (Quests.Spoken registers quests.voice
-- with `has`; ADR 0013: no play symbol where no line exists).
local function voiceButton(ref)
  local voice = B:GetAction("quests.voice")
  if not voice or (voice.has and not voice.has(ref)) then
    return nil
  end
  return {
    label = ">",
    onClick = function(row)
      B:RunAction("quests.voice", row.ref or ref, { source = "browser" })
    end,
  }
end

-- Quest rows of an index entry, sorted by what the player can act on first. `grouped` puts them
-- under category rows (the page); flat rows carry the status words (tooltips, the old shape).
local function questRows(indexName, key, grouped)
  local d = data()
  local ids = d and d:Index(indexName, key)
  if not ids or #ids == 0 then
    return nil
  end
  local rows = {}
  local s = State.ForLogic()
  for _, id in ipairs(ids) do
    local q = Logic.quest(id)
    local words, color, rank, st = shortStatus(id, s)
    local name = q and q.name or (L["Quest"] .. " " .. id)
    local keepWords = not grouped or rank >= 3 -- under a header only the log progress and "needs" stay
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
        id = indexName .. ":" .. tostring(key) .. ":" .. title,
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
    text = L["Available"]
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

local function chainRows(id)
  local s = State.ForLogic()
  local ch = Logic.chain(id, s)
  if not ch then
    return nil
  end
  local rows = {}
  -- where to start: the first quest of the
  -- chain the player can act on now, else the first one not done
  local start
  for _, qid in ipairs(ch.quests) do
    local st = Logic.status(qid, s)
    if st == "available" or st == "log" then
      start = qid
      break
    end
  end
  if not start then
    for _, qid in ipairs(ch.quests) do
      if Logic.status(qid, s) ~= "done" then
        start = qid
        break
      end
    end
  end
  if start then
    local row = R.quest(start, s, { zone = true, where = "start-here" })
    row.text = R.COLOR.grey .. L["Continue the chain with"] .. ":|r " .. row.text
    rows[#rows + 1] = row
  else
    rows[#rows + 1] = { kind = "para", text = R.COLOR.grey .. L["The whole chain is done."] .. "|r" }
  end
  for _, qid in ipairs(ch.quests) do
    local row = R.quest(qid, s, { zone = true, map = Logic.startMap(Logic.quest(id)) })
    if qid == id then
      row.color = B.UI.Style.C.accent
    end
    rows[#rows + 1] = row
  end
  return rows
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

-- The "needs" link (C2): the items a quest asks for, each with where it comes from and how far
-- that is now (so the rows are not cached: the distance moves with the player).
local function needsRows(id)
  local q = Logic.quest(id)
  if not (q and q.objectives) then
    return nil
  end
  local rows = {}
  for i, o in ipairs(q.objectives) do
    local kind, ref, count, source = o[1], o[2], o[3], o[4]
    if kind == "item" and ref then
      local text = B:Entity(ref):Name() or ref
      if type(count) == "number" and count > 1 then
        text = text .. " x" .. count
      end
      if source then
        local from = B:Entity(source):Name()
        if from then
          local dist = B.UI.Distance(B.Coords.DistanceTo(source))
          text = text
            .. "  "
            .. R.COLOR.grey
            .. L["from"]
            .. " "
            .. from
            .. (dist and (", " .. dist) or "")
            .. "|r"
        end
      end
      rows[#rows + 1] =
        { id = "needs:" .. id .. ":" .. i, text = text, ref = ref, icon = B:Entity(ref):Icon() }
    end
  end
  return #rows > 0 and rows or nil
end

local function objectiveRows(id)
  local e = State.log[id]
  if e and #(e.objectives or {}) > 0 then
    return R.objectives(e)
  end
  local q = Logic.quest(id)
  if not (q and q.objectives) then
    return nil
  end
  local rows = {}
  for i, o in ipairs(q.objectives) do
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
  return rows
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
  local rw = q.rewards or {}
  local rows = {}
  if rw.money and rw.money > 0 then
    rows[#rows + 1] = { text = L["Money"], value = rw.money, valueKind = "money" }
  end
  if rw.xp and rw.xp > 0 then
    rows[#rows + 1] = {
      text = L["Experience"] .. "  " .. R.COLOR.grey .. L["about, less for a lower quest"] .. "|r",
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
      text = R.COLOR.grey
        .. L["No reward known: no money, items, reputation or experience in our sources."]
        .. "|r",
    }
  end
  return rows
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
  local q = Logic.quest(id)
  local choices = q and q.rewards and q.rewards.choices or nil
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
    add(t.details)
    if t.objectives and t.objectives ~= "" then
      rows[#rows + 1] = {
        kind = "para",
        text = R.COLOR.white .. t.objectives .. "|r",
      }
    end
    add(t.offer)
  else
    -- not in the pack (retail has no quest texts, data.md): the client's own text of a log quest,
    -- else a note; on Forever the Text pack carries it and Spoken reads it aloud
    local details, objectives = B.Compat.GetQuestText(id)
    add(details)
    if objectives and objectives ~= "" then
      rows[#rows + 1] = { kind = "para", text = R.COLOR.white .. objectives .. "|r" }
    end
    if #rows == 0 and not loaded then
      rows[1] = {
        text = R.COLOR.grey .. L["Quest texts are not loaded. Click to load them."] .. "|r",
        onClick = function()
          d:LoadPack("text")
        end,
      }
    elseif #rows == 0 then
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
-- the log quests whose objectives need this NPC: a slay target, the source of a loot objective,
-- or a dropper of a required item. Pure: log = { [questID] = entry }, quest(id) -> record,
-- item(id) -> record. Rows by quest title, each with the objective's progress or "done".
function Reg.TargetOf(npcRef, log, quest, item)
  local rows = {}
  for qid, entry in pairs(log) do
    local q = quest(qid)
    local hit
    for _, o in ipairs(q and q.objectives or {}) do
      local target, source = o[2], o[4]
      local match = target == npcRef or source == npcRef
      if not match and type(target) == "string" and string.sub(target, 1, 5) == "item:" then
        local rec = item(tonumber(string.sub(target, 6)))
        for _, d in ipairs(rec and rec.drops or {}) do
          if d[1] == npcRef then
            match = true
            break
          end
        end
      end
      if match then
        hit = o
        break
      end
    end
    if hit then
      local objectives = entry.objectives or {}
      local o = objectives[(tonumber(hit[3]) or 0) + 1]
      if not o then
        for _, x in ipairs(objectives) do
          if not x.finished then
            o = x
            break
          end
        end
      end
      local done = entry.isComplete or (o and o.finished)
      local progress
      if done then
        progress = L["done"]
      elseif o and o.required and o.required > 0 then
        progress = (o.fulfilled or 0) .. "/" .. o.required
      end
      rows[#rows + 1] = {
        text = entry.title or (q and q.name) or ("quest " .. qid),
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
  local rows = Reg.TargetOf(ref, State.log, Logic.quest, function(id)
    return id and d:Get("item", id) or nil
  end)
  return #rows > 0 and rows or nil
end

local function registerSections(mod)
  local INVALIDATE = { "BASTIANS_QUESTS_CHANGED", "BASTIANS_TRACKED_CHANGED" }
  B:RegisterDetailSection(mod, {
    id = "quests.target",
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
    title = L["Ends quests"],
    types = { "npc", "object" },
    order = 21,
    invalidateOn = INVALIDATE,
    build = function(ref)
      return questRows("quest.byEnder", ref, true)
    end,
  })
  B:RegisterDetailSection(mod, {
    id = "quests.needed",
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
    invalidateOn = INVALIDATE,
    build = function(ref)
      return statusText(questID(ref))
    end,
    tooltip = { max = 1 },
  })
  -- the quest dossier (C2, ADR 0014): Given by, Hand in, Rewards and Objectives as one-cell
  -- blocks, Chain and Quest text across the row; needs, after and unlocks as links
  B:RegisterDetailSection(mod, {
    id = "quests.givers",
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
    title = L["Rewards"],
    types = { "quest" },
    order = 8,
    block = { columns = 1, limit = 8, table = true }, -- a small table (ADR 0018 D)
    invalidateOn = { "BASTIANS_PRICES_UPDATED" },
    build = function(ref)
      return rewardRows(questID(ref))
    end,
  })
  B:RegisterDetailSection(mod, {
    id = "quests.choice",
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
    id = "quests.objectives",
    title = L["Objectives"],
    types = { "quest" },
    order = 9,
    block = { columns = 1, limit = 8 },
    invalidateOn = INVALIDATE,
    build = function(ref)
      return objectiveRows(questID(ref))
    end,
  })
  B:RegisterDetailSection(mod, {
    id = "quests.chain",
    title = L["Chain"],
    types = { "quest" },
    order = 30,
    block = { wide = true, limit = 8 },
    invalidateOn = INVALIDATE,
    build = function(ref)
      return chainRows(questID(ref))
    end,
  })
  B:RegisterDetailSection(mod, {
    id = "quests.text",
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
    search = function(query, limit, yield)
      local d = data()
      if not d or #query < 3 then
        return {}
      end
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
          if string.find(hay, query, 1, true) then
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
local zoneCache = {} -- map -> { gen, byKey, counts, here }

function Reg.InvalidateZone()
  zoneGen = zoneGen + 1
end

local function zoneMap(ref)
  local typ, id = B.Entity.Parse(ref)
  return typ == "zone" and tonumber(id) or nil
end

local function zoneData(map)
  local c = zoneCache[map]
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
  zoneCache[map] = c
  return c
end

local ZONE_SECTIONS = {
  { "turnin", "Hand in", 3 },
  { "active", "In progress", 4 },
  { "available", "To take", 5 },
  { "soon", "Later", 6 },
  { "onward", "Onward", 7 },
  { "blocked", "Prerequisite elsewhere", 8 },
  { "done", "Done", 9, true },
}
local ZONE_INVALIDATE = {
  "BASTIANS_QUESTS_CHANGED",
  "BASTIANS_TRACKED_CHANGED",
  "BASTIANS_PLAYER_MOVED_ZONE",
  "BASTIANS_DATA_LOADED",
  "BASTIANS_QUESTS_VIEWS",
}

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
    title = countTitle("To do here"),
    types = { "zone" },
    order = 2,
    invalidateOn = ZONE_INVALIDATE,
    build = function(ref)
      local map = zoneMap(ref)
      local here = map and zoneData(map).here
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
      title = countTitle(title),
      types = { "zone" },
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

-- Yards from the player to a map point, nil when either side is unknown.
local function yardsTo(map, x, y)
  if not (map and x and y) then
    return nil
  end
  local continent, wx, wy = B.Coords.Player()
  local c, px, py = B.Coords.ToWorld(map, x, y)
  if not (continent and c == continent) then
    return nil
  end
  return math.sqrt((px - wx) ^ 2 + (py - wy) ^ 2)
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
  opts.questItem = W.QuestItemOf
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
        local dist = B.UI.Distance(yardsTo(row.map, row.x, row.y))
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
-- chains, a list of its own"): one row per chain this character can take, named after its first
-- quest, the steps in grey, faceted by the first quest's level band; a row opens the first quest,
-- whose page shows the chain.
local function levelBand(level)
  if not level then
    return "no level"
  end
  local lo = math.floor((level - 1) / 10) * 10 + 1
  return lo .. "-" .. (lo + 9)
end

local function registerLists(mod)
  B:RegisterList(mod, {
    type = "chain",
    label = "Quest chains",
    facet = "level",
    ids = Logic.chainRoots,
    record = function(root)
      local c = Logic.chain(root, State.ForLogic())
      if not c then
        return nil
      end
      local first = Logic.quest(c.quests[1])
      return {
        name = c.name or (first and first.name),
        level = first and first.level or nil,
        zone = first and first.zone or nil,
        steps = #c.quests,
        first = c.quests[1],
      }
    end,
    value = function(r)
      return levelBand(r.level)
    end,
    suffix = function(r)
      return string.format(L["%d steps"], r.steps)
    end,
    ref = function(_, r)
      return "quest:" .. r.first
    end,
  })
end
Reg.LevelBand = levelBand

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
  Reg.ResetCaches()
  Reg.InvalidateZone()
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
