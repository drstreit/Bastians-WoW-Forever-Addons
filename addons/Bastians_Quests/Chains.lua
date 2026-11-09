-- The chain as a subject (ADR 0055; ADR 0056, PA5.2): the entity type `chain`, what its tile says,
-- the sections of its page and the row of the Browser's list. The model is Logic.chainSheet.
local _, ns = ...
local B = Bastians
local L = ns.L
local Logic, State, R = ns.Logic, ns.State, ns.Rows

local Chains = {}
ns.Chains = Chains

local INVALIDATE = { "BASTIANS_QUESTS_CHANGED", "BASTIANS_DATA_LOADED" }
local owner -- the module, from Chains.Register

local function rootOf(ref)
  local typ, id = B.Entity.Parse(ref)
  return typ == "chain" and type(id) == "number" and id or nil
end

-- The chain of a root for this character (Logic.chainSheet), or nil.
function Chains.Sheet(root)
  return type(root) == "number" and Logic.chainSheet(root, State.ForLogic()) or nil
end

-- A chain's name: the model's, else its first step's as the client names it.
function Chains.Name(c)
  return c.name or R.questName(c.main[1])
end

-- "3-10" for the levels of its steps, nil when the pack knows none.
function Chains.Levels(c)
  if not (c.lo and c.hi) then
    return nil
  end
  return c.lo == c.hi and tostring(c.lo) or (c.lo .. "-" .. c.hi)
end

-- "3 steps, Level 7-10"
function Chains.Summary(c)
  local words = string.format(L["%d steps"], #c.main)
  local levels = Chains.Levels(c)
  return levels and (words .. ", " .. L["Level"] .. " " .. levels) or words
end

-- What the chain's tile says (the facet "tile", core-contracts §4): its steps and where it
-- goes, the levels as the badge, how far the character is as the mark, the next step.
function Chains.Tile(ref)
  local c = Chains.Sheet(rootOf(ref))
  if not c then
    return nil
  end
  local where
  if #c.zones == 1 then
    where = R.zoneName(c.zones[1])
  elseif #c.zones > 1 then
    where = string.format(L["%d zones"], #c.zones)
  end
  local line = string.format(L["%d steps"], #c.main)
  local note
  if c.state == "finished" then
    note = L["Finished"]
  elseif c.now then
    note = string.format(L["Next: %s"], R.questName(c.main[c.now]))
  end
  local levels = Chains.Levels(c)
  local steps = c.done .. "/" .. #c.main
  local follows = Chains.IsFollowed(rootOf(ref))
  return {
    line = where and (line .. ", " .. where) or line,
    badge = levels and { text = levels, level = c.lo, levelHi = c.hi ~= c.lo and c.hi or nil } or nil,
    mark = {
      text = follows and (L["Following"] .. " " .. steps) or steps, -- PA5: which chains you follow
      token = (follows or c.state == "on") and "typeChain" or nil,
    },
    note = note,
  }
end

-- The rows of a chain's page: each a quest, so a host draws them as quest tiles and a click
-- opens the quest.
local function questRow(id, text)
  return { id = "chain:q:" .. id, ref = "quest:" .. id, text = text or R.questName(id) }
end

function Chains.StepRows(ref)
  local c = Chains.Sheet(rootOf(ref))
  if not c then
    return nil
  end
  local rows = {}
  for i, id in ipairs(c.main) do
    rows[i] = questRow(id, i .. ". " .. R.questName(id))
    rows[i].step = i
  end
  return rows
end

function Chains.SideRows(ref)
  local c = Chains.Sheet(rootOf(ref))
  if not c or #c.side == 0 then
    return nil
  end
  local rows = {}
  for _, side in ipairs(c.side) do
    rows[#rows + 1] = questRow(side.id)
  end
  return rows
end

local WHY = { race = "for another race", class = "for another class" }

function Chains.OtherRows(ref)
  local c = Chains.Sheet(rootOf(ref))
  if not c or #c.others == 0 then
    return nil
  end
  local rows = {}
  for _, other in ipairs(c.others) do
    local why = WHY[other.why]
    rows[#rows + 1] = questRow(other.id, R.questName(other.id) .. (why and (" (" .. L[why] .. ")") or ""))
  end
  return rows
end

-- What the way pays in things: the main steps' items and choices in the order of the way, one
-- row per thing (ADR 0056, PA5).
function Chains.RewardRows(ref)
  local c = Chains.Sheet(rootOf(ref))
  if not c then
    return nil
  end
  local rows, seen = {}, {}
  local function add(step, id)
    if id and not seen[id] then
      seen[id] = true
      local item = "item:" .. id
      rows[#rows + 1] = { id = "chain:r:" .. step .. ":" .. id, ref = item, text = B:Entity(item):Name() }
    end
  end
  for _, step in ipairs(c.main) do
    local rw = Logic.rewards(step)
    for _, it in ipairs(rw and rw.items or {}) do
      add(step, it[1])
    end
    for _, it in ipairs(rw and rw.choices or {}) do
      add(step, it[1])
    end
  end
  return #rows > 0 and rows or nil
end

function Chains.ZoneRows(ref)
  local c = Chains.Sheet(rootOf(ref))
  if not c or #c.zones == 0 then
    return nil
  end
  local rows = {}
  for _, map in ipairs(c.zones) do
    rows[#rows + 1] = { id = "chain:z:" .. map, ref = "zone:" .. map, text = R.zoneName(map) }
  end
  return rows
end

-- The names of several chains shown together: two of the same name get the zone their way
-- starts in (quests.md, C1). chains = { Logic.chainSheet answers }; returns { [root] = name }.
function Chains.Names(chains)
  local names, count = {}, {}
  for _, c in ipairs(chains) do
    local name = Chains.Name(c)
    names[c.id] = name
    count[name] = (count[name] or 0) + 1
  end
  for _, c in ipairs(chains) do
    local zone = c.zones[1]
    if count[names[c.id]] > 1 and zone then
      names[c.id] = names[c.id] .. " - " .. R.zoneName(zone)
    end
  end
  return names
end

-- What a zone means for a chain, in one line (quests.md "A zone's sheet"): the step the
-- character is on when it is there, where the way starts, else which of its steps are there.
-- entry = one of Logic.chainsAmong.
function Chains.HereWords(entry)
  local c, steps = entry.chain, entry.steps
  local n = #c.main
  local function has(step)
    for _, s in ipairs(steps) do
      if s == step then
        return true
      end
    end
    return false
  end
  if c.state == "on" and c.now and has(c.now) then
    return string.format(L["Step %d of %d"], c.now, n) .. ": " .. R.questName(c.main[c.now])
  end
  if (c.state == "start" or c.state == "later") and has(1) then
    local q = Logic.quest(c.main[1])
    local giver = q and q.starts and q.starts[1] and B:Entity(q.starts[1]):Name() or nil
    return giver and string.format(L["Starts here with %s"], giver) or L["Starts here"]
  end
  if #steps == 1 then
    return string.format(L["Step %d of %d is here"], steps[1], n)
  elseif #steps > 1 and steps[#steps] - steps[1] == #steps - 1 then
    return string.format(L["Steps %d to %d of %d are here"], steps[1], steps[#steps], n)
  elseif #steps > 1 then
    return string.format(L["%d of its %d steps are here"], #steps, n)
  end
  return string.format(L["Side quests here: %d"], entry.side)
end

-- "Chains here" on a zone's page, and on an area's with the steps that lie in the area: one row
-- per chain, by how far the character is. A row is the chain (a host with tiles draws the
-- chain's own tile); its second line says what the zone means for it.
function Chains.HereRows(ref)
  local Reg = ns.Registrations
  local map = Reg.ZoneMap(ref)
  if not map then
    return nil
  end
  local qids = Logic.questsOfZone(map)
  local inside = Reg.AreaTest(ref)
  if inside then
    local there = {}
    for _, qid in ipairs(qids) do
      if Reg.QuestIn(qid, inside) then
        there[#there + 1] = qid
      end
    end
    qids = there
  end
  local found = Logic.chainsAmong(qids, State.ForLogic())
  if #found == 0 then
    return nil
  end
  local chains = {}
  for i, entry in ipairs(found) do
    chains[i] = entry.chain
  end
  local names = Chains.Names(chains)
  local rows = {}
  for i, entry in ipairs(found) do
    local c = entry.chain
    rows[i] = {
      id = "chain:here:" .. c.id,
      ref = "chain:" .. c.id,
      text = names[c.id],
      meta = Chains.HereWords(entry),
      progress = c.state,
    }
  end
  return rows
end

-- ---------------------------------------------------------------------------------------------
-- Follow (ADR 0055, C7): a followed chain tracks the step the character is on; when that step
-- is handed in, the next one is tracked as soon as it is in the log. Kept per character:
-- followed[root] = the quest tracked for the chain last, or true before any.
-- ---------------------------------------------------------------------------------------------

local function followed()
  local char = owner:GetDB().char
  if type(char.followed) ~= "table" then
    char.followed = {}
  end
  return char.followed
end

function Chains.IsFollowed(root)
  return owner ~= nil and root ~= nil and followed()[root] ~= nil
end

-- What following asks for now; pure. store = { [root] = last tracked quest or true }, sheetOf =
-- function(root) -> Logic.chainSheet's answer or nil, inLog = function(qid) -> boolean. Returns
-- track = { { root, qid } } (a step in the log that was not tracked for its chain yet) and drop =
-- { root } (finished chains). A chain without an answer (no data yet) is left alone.
function Chains.FollowPlan(store, sheetOf, inLog)
  local track, drop = {}, {}
  for root, last in pairs(store) do
    local c = sheetOf(root)
    if c and c.state == "finished" then
      drop[#drop + 1] = root
    elseif c then
      local step = c.now and c.main[c.now]
      if step and step ~= last and inLog(step) then
        track[#track + 1] = { root = root, qid = step }
      end
    end
  end
  table.sort(drop)
  table.sort(track, function(a, b)
    return a.root < b.root
  end)
  return track, drop
end

-- The quests changed, or a chain was just followed: track what the followed chains ask for.
-- A step is tracked once for its chain, so a player who untracks it keeps it untracked.
function Chains.FollowTick()
  if not owner then
    return
  end
  local store = followed()
  if next(store) == nil then
    return
  end
  local track, drop = Chains.FollowPlan(store, Chains.Sheet, State.IsInLog)
  for _, root in ipairs(drop) do
    store[root] = nil
  end
  local watched = 0
  for _, t in ipairs(track) do
    store[t.root] = t.qid
    if not State.IsTracked(t.qid) and B.Compat.SetQuestWatched(t.qid, true) then
      watched = watched + 1
    end
  end
  if watched > 0 then
    ns.Registrations.SyncTracked(owner)
  end
  if #drop > 0 then
    owner:Fire("BASTIANS_ACTION_STATE", "quests.chain.follow")
  end
end

function Chains.SetFollowed(root, on)
  local store = followed()
  if on then
    store[root] = store[root] or true
    Chains.FollowTick()
  else
    store[root] = nil
  end
  owner:Fire("BASTIANS_ACTION_STATE", "quests.chain.follow")
end

function Chains.Register(mod)
  owner = mod
  mod.Chains = Chains -- for the tests
  B:RegisterEntityType(mod, {
    type = "chain",
    priority = 100,
    -- the reading order of a chain's page: the way first (ADR 0052)
    chapters = {
      { id = "steps", title = L["The way"] },
      { id = "side", title = L["Also open"] },
      { id = "others", title = L["Not for this character"] },
      { id = "rewards", title = L["Rewards"] },
      { id = "zones", title = L["Where it goes"] },
      { id = "book", tail = true },
      { id = "notes", tail = true },
    },
    name = function(root)
      local c = Chains.Sheet(root)
      return c and Chains.Name(c) or nil
    end,
    icon = function()
      return B.UI.IconTexture("chain")
    end,
    summary = function(root)
      local c = Chains.Sheet(root)
      return c and Chains.Summary(c) or nil
    end,
    -- where the chain is now: the place of the step the player is on, else of the first step
    locations = function(root)
      local c = Chains.Sheet(root)
      local step = c and c.main[c.now or 1]
      return step and B:Entity("quest:" .. step):Locations() or nil
    end,
  })
  B:RegisterFacet(mod, {
    facet = "tile",
    types = { "chain" },
    priority = 150,
    -- the action's state too: Follow changes the mark
    invalidateOn = { "BASTIANS_ACTION_STATE", "BASTIANS_QUESTS_CHANGED", "BASTIANS_DATA_LOADED" },
    rule = Chains.Tile,
  })
  B:RegisterAction(mod, {
    id = "quests.chain.follow",
    main = true, -- the first button of a chain's page (ADR 0055, C7)
    label = L["Follow: track the step you are on, and the next one when it is handed in"],
    short = L["Follow"],
    activeShort = L["Following"],
    icon = B.UI.IconTexture("questActive"),
    types = { "chain" },
    order = 10,
    active = function(ref)
      return Chains.IsFollowed(rootOf(ref))
    end,
    when = function(ref)
      local c = Chains.Sheet(rootOf(ref))
      return c ~= nil and c.state ~= "finished"
    end,
    run = function(ref)
      local root = rootOf(ref)
      Chains.SetFollowed(root, not Chains.IsFollowed(root))
    end,
  })
  local function section(id, chapter, title, order, build)
    B:RegisterDetailSection(mod, {
      id = id,
      chapter = chapter,
      title = title,
      types = { "chain" },
      order = order,
      block = { wide = true, limit = 100 }, -- a chain shows its whole way
      invalidateOn = INVALIDATE,
      build = build,
    })
  end
  section("quests.chain.steps", "steps", L["The way"], 10, Chains.StepRows)
  section("quests.chain.side", "side", L["Also open"], 20, Chains.SideRows)
  section("quests.chain.others", "others", L["Not for this character"], 30, Chains.OtherRows)
  section("quests.chain.rewards", "rewards", L["Rewards"], 35, Chains.RewardRows)
  section("quests.chain.zones", "zones", L["Where it goes"], 40, Chains.ZoneRows)
  -- a zone's chains, in a chapter of their own after its quests (Data's chapter list of a zone)
  B:RegisterDetailSection(mod, {
    id = "quests.zone.chains",
    chapter = "chains",
    title = L["Chains here"],
    types = { "zone", "area" },
    order = 9.5, -- after the zone's quest sections, before Data's people
    block = { wide = true, twoLine = true, limit = 8 },
    invalidateOn = ns.Registrations.ZONE_INVALIDATE,
    build = Chains.HereRows,
  })
end
