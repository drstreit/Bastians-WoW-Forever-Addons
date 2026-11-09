-- Quest logic (quests.md "Logic layer"): what a character can do, from the data alone. Pure: no WoW
-- API, everything comes through the `data` service and a `state` table the caller builds, so the
-- rules run in tests. Ported from AHSyncGuide Logic.lua onto the canonical quest records.
--
-- state = { level, raceID, classID, faction ("Alliance"/"Horde"),
--           done(questID) -> bool, inLog(questID) -> bool, isComplete(questID) -> bool (optional),
--           skills = { [skillLineID] = rank }, rep(factionID) -> value or nil }
--
-- Quest rules follow Everything Quests' data: preAny = any one done, pre = all done, excl = any taken
-- or done rules it out, chain = that quest active or done rules this one out, parent = must be in the log.
local _, ns = ...

local Logic = {}
ns.Logic = Logic

Logic.SOON = 3 -- levels ahead that still count as "soon"

-- A spot's kind and the client's objective type it counts among (Everything Quests' numbering:
-- bit i of a spot is the i-th objective of its kind).
local SPOT_KIND_TYPE = { slay = "monster", object = "object", loot = "item" }

-- The log objectives a spot { x, y, kind, mask } serves, or nil when that is not known: no mask,
-- a kind without a numbering, or a bit past the objectives the client lists. An "area" spot is
-- the client's own quest area: its bit counts all objectives. Pure.
function Logic.SpotObjectives(objectives, spot)
  local mask = spot[4]
  if type(objectives) ~= "table" or type(mask) ~= "number" or mask <= 0 then
    return nil
  end
  local pool = objectives
  if spot[3] ~= "area" then
    local wanted = SPOT_KIND_TYPE[spot[3]]
    if not wanted then
      return nil
    end
    pool = {}
    for _, o in ipairs(objectives) do
      if o.kind == wanted then
        pool[#pool + 1] = o
      end
    end
  end
  local served, i = {}, 1
  while mask > 0 do
    if mask % 2 == 1 then
      if not pool[i] then
        return nil
      end
      served[#served + 1] = pool[i]
    end
    mask, i = math.floor(mask / 2), i + 1
  end
  return served
end

-- A log quest's spots still worth going to (two of three targets done,
-- the map still drew all three): { [map] = { { x, y, kind, mask, open = { objectives } } } }. A
-- spot whose objectives are all finished is left out; one nobody can tell stays, without `open`
-- (unknown is not done). Empty when none is left. Pure.
function Logic.OpenSpots(entry, q)
  local out = {}
  for map, list in pairs(q and q.spots or {}) do
    for _, s in ipairs(list) do
      local served = Logic.SpotObjectives(entry and entry.objectives, s)
      local open
      if served then
        open = {}
        for _, o in ipairs(served) do
          if not o.finished then
            open[#open + 1] = o
          end
        end
      end
      if not open or #open > 0 then
        out[map] = out[map] or {}
        table.insert(out[map], { s[1], s[2], s[3], s[4], open = open })
      end
    end
  end
  return out
end
-- A chain component larger than this shows the line through the quest instead of every member:
-- retail storylines join hundreds of quests through their prerequisites (K'aresh: 219 in one
-- component, 1,346 in the largest; ), Classic chains stay small.
Logic.CHAIN_MAX = 24
Logic.OWN_SHARE = 0.25 -- a zone counts for a faction when its quests reach a quarter of the other side's

local data -- the `data` service, set by Logic.SetData

function Logic.SetData(service)
  data = service
  Logic.Reset()
end

local byStart, byTurnIn, followers
local compOf, members, chainFrom, chainCache
local shapes -- a chain's shape per root, race and class (chainShape)
local indexSource -- "pack" (the shipped quest graph) or "decoded" (built from every record)

-- Counts the data's changes: a view that keeps what it built from every quest knows when to build
-- again (the class quests).
Logic.generation = 0

function Logic.Reset()
  Logic.generation = Logic.generation + 1
  byStart, byTurnIn, followers = nil, nil, nil
  compOf, members, chainFrom, chainCache = nil, nil, nil, nil
  shapes = nil
  indexSource = nil
end

-- Where the quest graph came from: "pack" or "decoded" (nil before the first query). For the tests
-- and the perf notes: decoding every quest cost 0.5 s on the retail pack (nfr.md, B11.1).
function Logic.IndexSource()
  return indexSource
end

local function quest(id)
  return data and data:Get("quest", id) or nil
end
Logic.quest = quest

-- Whether the thing lying at `ref` is already in the player's hands, so the place has nothing to
-- offer: `ref` is an object, the quest also starts at an
-- NPC (the pin there stays, nothing is lost), and `countOf(itemID)` finds an item of its objectives.
-- A quest that starts only at the object keeps its pin: the item may be a common one. Pure.
function Logic.AlreadyTaken(q, ref, countOf)
  if not (q and type(ref) == "string" and string.find(ref, "^object:")) then
    return false
  end
  local atNpc = false
  for _, start in ipairs(q.starts or {}) do
    atNpc = atNpc or string.find(start, "^npc:") ~= nil
  end
  if not atNpc then
    return false
  end
  for _, objective in ipairs(q.objectives or {}) do
    local id = type(objective[2]) == "string" and tonumber(string.match(objective[2], "^item:(%d+)"))
    if id and countOf(id) > 0 then
      return true
    end
  end
  return false
end

-- What a quest earns (ADR 0053): the pack's record with what the client said laid over it. The
-- client's words win for what it answers; reputation and spells stay the pack's. Nil when nothing
-- is known, which is not "no reward". `learned` is Rewards.lua's saved table.
local learned, merged = {}, {}

function Logic.SetLearnedRewards(store)
  learned, merged = store or {}, {}
end

function Logic.rewards(id)
  local said = learned[id]
  local q = quest(id)
  if not said then
    return q and q.rewards or nil
  end
  local out = merged[id]
  if out then
    return out
  end
  out = {}
  for key, value in pairs(q and q.rewards or {}) do
    out[key] = value
  end
  for key, value in pairs(said) do
    out[key] = value
  end
  out.src = "client"
  merged[id] = out
  return out
end

-- All quest ids known to the data (the quests pack must be loaded).
local function allQuestIDs()
  local out = {}
  local idx = data and data:Index("quest.byZone")
  if not idx then
    return out
  end
  local seen = {}
  for _, list in pairs(idx) do
    for _, id in ipairs(list) do
      if not seen[id] then
        seen[id] = true
        out[#out + 1] = id
      end
    end
  end
  table.sort(out)
  return out
end
Logic.allQuestIDs = allQuestIDs

local function startMap(q)
  if q.zone then
    return q.zone
  end
  local p = q.startPlaces and q.startPlaces[1]
  return p and p[1] or nil
end

local function turnInMap(q)
  local p = q.endPlaces and q.endPlaces[1]
  return p and p[1] or startMap(q)
end
Logic.startMap, Logic.turnInMap = startMap, turnInMap

-- Quest ids whose zone is this map (the quests pack must be loaded).
function Logic.questsOfZone(map)
  local idx = data and map and data:Index("quest.byZone", map)
  return idx or {}
end

-- The attunement records for a faction ("Alliance" | "Horde"), in id order; empty without the pack.
function Logic.attunements(faction)
  local ids = data and faction and data:Index("attunement.byFaction", faction) or nil
  local out = {}
  for _, id in ipairs(ids or {}) do
    local a = data:Get("attunement", id)
    if a then
      out[#out + 1] = a
    end
  end
  return out
end

-- Indexes: quests by start map, by turn-in map, and the followers of each quest. The pack ships
-- them since 21.10.2026 (`quest.byStart`, `quest.byTurnIn`, `quest.followers`, read-only here); a
-- pack without them gets the same tables built from every record, which decodes the whole pack.
local function index()
  if byStart then
    return
  end
  local shipped = data and data:Index("quest.byStart")
  if shipped then
    byStart = shipped
    local turnIn = data:Index("quest.byTurnIn")
    byTurnIn = turnIn and next(turnIn) and turnIn or byStart -- empty: every quest ends where it starts
    followers = data:Index("quest.followers") or {}
    indexSource = "pack"
    return
  end
  indexSource = "decoded"
  byStart, byTurnIn, followers = {}, {}, {}
  local function add(t, k, v)
    if not k then
      return
    end
    local list = t[k]
    if not list then
      list = {}
      t[k] = list
    end
    list[#list + 1] = v
  end
  for _, qid in ipairs(allQuestIDs()) do
    local q = quest(qid)
    if q then
      -- the zone and, when different, the map the giver stands on (derive.py quest_start_maps)
      local sm, place = startMap(q), q.startPlaces and q.startPlaces[1]
      local gm = place and place[1] ~= sm and place[1] or nil
      add(byStart, sm, qid)
      add(byStart, gm, qid)
      if q.endPlaces and q.endPlaces[1] then
        add(byTurnIn, turnInMap(q), qid)
      else
        add(byTurnIn, sm, qid)
        add(byTurnIn, gm, qid)
      end
      for _, key in ipairs({ "pre", "preAny" }) do
        for _, p in ipairs(q[key] or {}) do
          add(followers, p, qid)
        end
      end
      add(followers, q.parent, qid)
      if q.chain then
        add(followers, qid, q.chain)
      end
    end
  end
end

local function hasBit(mask, bitIndex)
  return math.floor(mask / 2 ^ bitIndex) % 2 == 1
end
Logic.hasBit = hasBit

local function hasFlag(q, flag)
  for _, f in ipairs(q.flags or {}) do
    if f == flag then
      return true
    end
  end
  return false
end
Logic.hasFlag = hasFlag

-- Can this character ever take the quest (race, class)?
function Logic.canEverTake(q, state)
  local races, classes = q.races, q.classes
  if races and races > 0 and not hasBit(races, state.raceID - 1) then
    return false
  end
  if classes and classes > 0 and not hasBit(classes, state.classID - 1) then
    return false
  end
  return true
end

local function anyOf(list, test)
  for i = 1, #(list or {}) do
    if test(list[i]) then
      return true
    end
  end
  return false
end

-- Whether the data says the game does not offer the quest now (ADR 0051): Questie's lists, or a
-- world event that does not run. `state.holidayOn` absent: the event counts as running.
function Logic.gatedByData(q, state)
  if hasFlag(q, "absent") or hasFlag(q, "dormant") then
    return true
  end
  return q.holiday ~= nil and state.holidayOn ~= nil and not state.holidayOn(q.holiday)
end

-- Below the level where the client calls a quest trivial: the
-- client's range decides, without it nothing is low level.
function Logic.isTrivial(q, state)
  local range, level = state.trivialRange, q.level
  return range ~= nil and level ~= nil and level > 0 and state.level - level > range
end

-- Status of one quest for the character, with the reason:
-- never, done, log, superseded, inactive (the game does not offer it now: the data says so or the
-- giver did not list it), prereq (second value: missing quests the character can take), skill,
-- rep, level, available.
function Logic.status(qid, state)
  local q = quest(qid)
  if not q or not Logic.canEverTake(q, state) then
    return "never"
  end
  if state.done(qid) then
    return "done"
  end
  if state.inLog(qid) then
    return "log"
  end
  local function taken(o)
    return state.done(o) or state.inLog(o)
  end
  if anyOf(q.excl, taken) or (q.chain and taken(q.chain)) then
    return "superseded"
  end
  local offered = state.offered ~= nil and state.offered(qid)
  if not offered and Logic.gatedByData(q, state) then
    return "inactive"
  end
  local missing = {}
  local function takeable(o)
    local oq = quest(o)
    return not oq or Logic.canEverTake(oq, state)
  end
  if q.preAny and not anyOf(q.preAny, state.done) then
    for _, p in ipairs(q.preAny) do
      if takeable(p) then
        missing[#missing + 1] = p
      end
    end
    if #missing == 0 then
      return "never" -- only other races' variants unlock it
    end
  end
  for _, p in ipairs(q.pre or {}) do
    if not state.done(p) then
      missing[#missing + 1] = p
    end
  end
  if q.parent and not state.inLog(q.parent) then
    missing[#missing + 1] = q.parent
  end
  if #missing > 0 then
    return "prereq", missing
  end
  if q.skill then
    local rank = state.skills and state.skills[q.skill[1]]
    if not rank or rank < (q.skill[2] or 0) then
      return "skill"
    end
  end
  if q.minRep and state.rep then
    local v = state.rep(q.minRep[1])
    if v and v < q.minRep[2] then
      return "rep"
    end
  end
  if state.level < (q.minLevel or 0) then
    return "level"
  end
  if state.notOffered and state.notOffered(qid) then
    return "inactive"
  end
  return "available"
end

-- ---------------------------------------------------------------------------------------------
-- Chains: connected parts of the graph of pre, preAny, parent and chain links, kept to what the
-- character can ever take, in depth order. The chain's name is its first quest's.
-- ---------------------------------------------------------------------------------------------

-- Chain components: every quest joined by pre, preAny, parent or chain edges, keyed by the smallest
-- id. The pack ships them as `quest.chainMembers` and `quest.chainFrom` (same rules, derive.py);
-- without them the union-find below decodes every record.
local function chainIndex()
  if compOf then
    return
  end
  local shipped = data and data:Index("quest.chainMembers")
  if shipped then
    compOf, members, chainCache = {}, shipped, {}
    for root, list in pairs(shipped) do
      for _, m in ipairs(list) do
        compOf[m] = root
      end
    end
    chainFrom = data:Index("quest.chainFrom") or {}
    return
  end
  local up = {}
  local function find(x)
    local r = x
    while up[r] ~= r do
      r = up[r]
    end
    while up[x] ~= r do
      local n = up[x]
      up[x] = r
      x = n
    end
    return r
  end
  local function union(a, b)
    if not (quest(a) and quest(b)) then
      return
    end
    up[a] = up[a] or a
    up[b] = up[b] or b
    local ra, rb = find(a), find(b)
    if ra ~= rb then
      if ra < rb then
        up[rb] = ra
      else
        up[ra] = rb
      end
    end
  end
  chainFrom = {}
  for _, qid in ipairs(allQuestIDs()) do
    local q = quest(qid)
    for _, key in ipairs({ "pre", "preAny" }) do
      for _, p in ipairs(q[key] or {}) do
        union(qid, p)
      end
    end
    if q.parent then
      union(qid, q.parent)
    end
    if q.chain then
      union(qid, q.chain)
      local t = chainFrom[q.chain] or {}
      t[#t + 1] = qid
      chainFrom[q.chain] = t
    end
  end
  compOf, members, chainCache = {}, {}, {}
  for qid in pairs(up) do
    local r = find(qid)
    compOf[qid] = r
    local list = members[r] or {}
    list[#list + 1] = qid
    members[r] = list
  end
end

local function preds(qid)
  local q = quest(qid)
  local out = {}
  for _, key in ipairs({ "pre", "preAny" }) do
    for _, p in ipairs(q[key] or {}) do
      out[#out + 1] = p
    end
  end
  if q.parent then
    out[#out + 1] = q.parent
  end
  for _, p in ipairs(chainFrom[qid] or {}) do
    out[#out + 1] = p
  end
  return out
end

-- The longest path of predecessors to q inside the set (memoized in `depth`; a cycle in the data
-- must not hang the client).
local function depthIn(inSet, depth, busy, q)
  if depth[q] then
    return depth[q]
  end
  if busy[q] then
    return 0
  end
  busy[q] = true
  local best = 0
  for _, p in ipairs(preds(q)) do
    if inSet[p] then
      local v = depthIn(inSet, depth, busy, p)
      if v > best then
        best = v
      end
    end
  end
  busy[q] = nil
  depth[q] = best + 1
  return depth[q]
end

-- The line through qid in a huge component: back along the deepest predecessor each step, forward
-- along the follower with the longest continuation, at most CHAIN_MAX each way.
local function lineThrough(qid, inSet)
  index()
  local depth, busy, seen = {}, {}, { [qid] = true }
  local function d(q)
    return depthIn(inSet, depth, busy, q)
  end
  local height, hBusy = {}, {}
  local function h(q)
    if height[q] then
      return height[q]
    end
    if hBusy[q] then
      return 0
    end
    hBusy[q] = true
    local best = 0
    for _, f in ipairs(followers[q] or {}) do
      if inSet[f] then
        local v = h(f)
        if v > best then
          best = v
        end
      end
    end
    hBusy[q] = nil
    height[q] = best + 1
    return height[q]
  end
  local function pick(candidates, score)
    local best
    for _, x in ipairs(candidates) do
      if
        inSet[x]
        and not seen[x]
        and (not best or score(x) > score(best) or (score(x) == score(best) and x < best))
      then
        best = x
      end
    end
    if best then
      seen[best] = true
    end
    return best
  end
  local back, cur = {}, qid
  while #back < Logic.CHAIN_MAX do
    cur = pick(preds(cur), d)
    if not cur then
      break
    end
    table.insert(back, 1, cur)
  end
  local list = back
  list[#list + 1] = qid
  cur = qid
  local n = 0
  while n < Logic.CHAIN_MAX do
    cur = pick(followers[cur] or {}, h)
    if not cur then
      break
    end
    n = n + 1
    list[#list + 1] = cur
  end
  return list
end

-- Every chain's root (the components of two quests or more), sorted: the Browser's "Quest chains"
-- list.
function Logic.chainRoots()
  chainIndex()
  local out = {}
  for root, list in pairs(members) do
    if #list >= 2 then
      out[#out + 1] = root
    end
  end
  table.sort(out)
  return out
end

-- The chain a quest belongs to for this character: { id, name, quests (in order), pos[qid], line },
-- or nil. In a component larger than CHAIN_MAX the quests are the line through qid (`line` = true).
-- The quest after `qid` in its chain's order, or nil (the last step, or no chain): the "next in
-- chain" line of the log.
function Logic.nextInChain(qid, state)
  local ch = Logic.chain(qid, state)
  local i = ch and ch.pos and ch.pos[qid]
  return i and ch.quests[i + 1] or nil
end

function Logic.chain(qid, state)
  chainIndex()
  local root = compOf[qid]
  if not root then
    return nil
  end
  local all = members[root]
  local line = #all > Logic.CHAIN_MAX
  local key = root
    .. ":"
    .. (line and qid or "")
    .. ":"
    .. tostring(state.raceID)
    .. ":"
    .. tostring(state.classID)
  local c = chainCache[key]
  if c == nil then
    local list, inSet = {}, {}
    for _, m in ipairs(all) do
      if Logic.canEverTake(quest(m), state) then
        list[#list + 1] = m
        inSet[m] = true
      end
    end
    if line then
      list = lineThrough(qid, inSet) -- already in order
    end
    if #list < 2 then
      c = false
    else
      if not line then
        local depth, busy = {}, {}
        for _, m in ipairs(list) do
          depthIn(inSet, depth, busy, m)
        end
        table.sort(list, function(a, b)
          if depth[a] ~= depth[b] then
            return depth[a] < depth[b]
          end
          return a < b
        end)
      end
      local pos = {}
      for i, m in ipairs(list) do
        pos[m] = i
      end
      c = { id = root, name = quest(list[1]).name, quests = list, pos = pos, line = line or nil }
    end
    chainCache[key] = c
  end
  return c or nil
end

-- ---------------------------------------------------------------------------------------------
-- The chain as a subject (ADR 0055, quests.md "Chains, first class"): one main line through the
-- quests the character can take, every other quest hanging from it. Pure, as the rest.
-- ---------------------------------------------------------------------------------------------

-- Why a character can never take a quest: "race" or "class"; nil when it can.
function Logic.whyNot(q, state)
  local races, classes = q.races, q.classes
  if races and races > 0 and not hasBit(races, state.raceID - 1) then
    return "race"
  end
  if classes and classes > 0 and not hasBit(classes, state.classID - 1) then
    return "class"
  end
  return nil
end

-- A chain's shape for a race and class: what does not move with the character's progress.
-- { id, main = { qid }, index = { [qid] = i }, side = { { id, after } }, others = { { id, after,
-- why } } }, or nil when fewer than two of its quests are open to the character.
local function chainShape(root, state)
  chainIndex()
  local all = members[root]
  if not all then
    return nil
  end
  shapes = shapes or {}
  local key = root .. ":" .. tostring(state.raceID) .. ":" .. tostring(state.classID)
  local shape = shapes[key]
  if shape ~= nil then
    return shape or nil
  end
  local open, inSet, closed = {}, {}, {}
  for _, m in ipairs(all) do
    local q = quest(m)
    if q then
      if Logic.canEverTake(q, state) then
        open[#open + 1] = m
        inSet[m] = true
      else
        closed[#closed + 1] = m
      end
    end
  end
  if #open < 2 then
    shapes[key] = false
    return nil
  end
  table.sort(open)
  table.sort(closed)
  local depth, busy = {}, {}
  for _, m in ipairs(open) do
    depthIn(inSet, depth, busy, m)
  end
  -- the main line: from the deepest quest (ties: the smaller id) back along the deepest
  -- predecessor each step (ties: the smaller id)
  local last
  for _, m in ipairs(open) do
    if not last or depth[m] > depth[last] then
      last = m
    end
  end
  local main, stepOf = {}, {}
  local cur = last
  while cur do
    table.insert(main, 1, cur)
    stepOf[cur] = true
    local best
    for _, p in ipairs(preds(cur)) do
      if
        inSet[p]
        and not stepOf[p]
        and depth[p] < depth[cur] -- a cycle in the data must not hang the client
        and (not best or depth[p] > depth[best] or (depth[p] == depth[best] and p < best))
      then
        best = p
      end
    end
    cur = best
  end
  for i, m in ipairs(main) do
    stepOf[m] = i
  end
  -- where another quest hangs: the deepest main step among what must be done before it, through
  -- quests off the line too; 0 for another way into the chain
  local function after(m)
    local best, seen, stack = 0, { [m] = true }, { m }
    while #stack > 0 do
      local x = table.remove(stack)
      for _, p in ipairs(preds(x)) do
        if not seen[p] then
          seen[p] = true
          if stepOf[p] then
            if stepOf[p] > best then
              best = stepOf[p]
            end
          elseif quest(p) then
            stack[#stack + 1] = p
          end
        end
      end
    end
    return best
  end
  local function hanging(list, why)
    local out = {}
    for _, m in ipairs(list) do
      if not stepOf[m] then
        out[#out + 1] = { id = m, after = after(m), why = why and Logic.whyNot(quest(m), state) or nil }
      end
    end
    table.sort(out, function(a, b)
      if a.after ~= b.after then
        return a.after < b.after
      end
      return a.id < b.id
    end)
    return out
  end
  shape = { id = root, main = main, index = stepOf, side = hanging(open), others = hanging(closed, true) }
  -- every quest's place in the chain (Logic.chainPlace)
  local place = {}
  for i, m in ipairs(main) do
    place[m] = { root = root, step = i, steps = #main }
  end
  for _, s in ipairs(shape.side) do
    place[s.id] = { root = root, after = s.after, steps = #main }
  end
  for _, o in ipairs(shape.others) do
    place[o.id] = { root = root, after = o.after, steps = #main, why = o.why }
  end
  shape.place = place
  shapes[key] = shape
  return shape
end

-- The name most steps share; with no shared name (every name once) the first main step's. nil
-- when the pack names none of them (the client's names are the caller's to ask).
local function shapeName(shape)
  local count, best = {}, nil
  local function note(id)
    local q = quest(id)
    local name = q and q.name
    if name then
      count[name] = (count[name] or 0) + 1
      if count[name] >= 2 and (not best or count[name] > count[best]) then
        best = name
      end
    end
  end
  for _, id in ipairs(shape.main) do
    note(id)
  end
  for _, s in ipairs(shape.side) do
    note(s.id)
  end
  if best then
    return best
  end
  local first = quest(shape.main[1])
  return first and first.name or nil
end

function Logic.chainName(root, state)
  local shape = chainShape(root, state)
  return shape and shapeName(shape) or nil
end

-- The root of the chain a quest belongs to, or nil (a quest alone).
function Logic.chainRoot(qid)
  chainIndex()
  local root = compOf[qid]
  return root and members[root] and #members[root] >= 2 and root or nil
end

-- The root of a quest's chain when the chain is a subject for this character (two of its quests
-- or more are open to the race and class), else nil. The shape is kept, so this is cheap.
function Logic.chainFor(qid, state)
  local root = Logic.chainRoot(qid)
  return root and chainShape(root, state) and root or nil
end

-- A quest's place in its chain for a character, or nil (a quest alone, a chain that is no
-- subject for the character): { root, steps (the main line's length), step (its number on the
-- main line) } for a main step; { root, steps, after (the main step it hangs under, 0 for another
-- way in), why ("race" | "class" for a quest the character cannot take) } off the line. The
-- table is the shape's: read it, do not change it.
function Logic.chainPlace(qid, state)
  local root = Logic.chainRoot(qid)
  local shape = root and chainShape(root, state)
  return shape and shape.place[qid] or nil
end

-- The chain for a character (quests.md "The model"): the shape with where the character is.
-- { id, name, main, index, side, others, done, now, state ("on" | "start" | "later" |
-- "finished"), zones, lo, hi, ahead = { xp, money, rep = { { faction, value } } } }; nil when
-- fewer than two of its quests are open to the character's race and class.
function Logic.chainSheet(root, state)
  local shape = chainShape(root, state)
  if not shape then
    return nil
  end
  local main = shape.main
  local done, inLog, canTake = 0, nil, nil
  local zones, seenZone = {}, {}
  local lo, hi
  local ahead, byFaction = { xp = 0, money = 0, rep = {} }, {}
  for i, id in ipairs(main) do
    local q = quest(id)
    local status = Logic.status(id, state)
    if status == "done" then
      done = done + 1
    else
      if status == "log" then
        inLog = inLog or i
      elseif status == "available" then
        canTake = canTake or i
      end
      local rw = Logic.rewards(id)
      if rw then
        ahead.xp = ahead.xp + (rw.xp or 0)
        ahead.money = ahead.money + (rw.money or 0)
        for _, rep in ipairs(rw.rep or {}) do
          byFaction[rep[1]] = (byFaction[rep[1]] or 0) + (rep[2] or 0)
        end
      end
    end
    local zone = startMap(q)
    if zone and not seenZone[zone] then
      seenZone[zone] = true
      zones[#zones + 1] = zone
    end
    if q.level and q.level > 0 then
      lo = (not lo or q.level < lo) and q.level or lo
      hi = (not hi or q.level > hi) and q.level or hi
    end
  end
  for faction, value in pairs(byFaction) do
    ahead.rep[#ahead.rep + 1] = { faction, value }
  end
  table.sort(ahead.rep, function(a, b)
    return a[1] < b[1]
  end)
  local progress
  if done == #main then
    progress = "finished"
  elseif done > 0 or inLog then
    progress = "on"
  else
    local first = quest(main[1])
    local status = Logic.status(main[1], state)
    local soon = status == "level" and ((first.minLevel or 0) - state.level) <= Logic.SOON
    progress = (status == "available" or soon) and "start" or "later"
  end
  return {
    id = shape.id,
    name = shapeName(shape),
    main = main,
    index = shape.index,
    side = shape.side,
    others = shape.others,
    done = done,
    now = progress ~= "finished" and (inLog or canTake) or nil,
    state = progress,
    zones = zones,
    lo = lo,
    hi = hi,
    ahead = ahead,
  }
end

-- What kind of chain it is, from its main steps: "Class", "Profession", "Raid", "Dungeon",
-- "Festival", each once, in that order; empty for a chain of none of them. Kept with the shape.
function Logic.chainKinds(root, state)
  local shape = chainShape(root, state)
  if not shape then
    return nil
  end
  if not shape.kinds then
    local has = {}
    for _, id in ipairs(shape.main) do
      local q = quest(id)
      if (q.classes and q.classes > 0) or hasFlag(q, "class") then
        has.Class = true
      end
      if q.skill or hasFlag(q, "profession") then
        has.Profession = true
      end
      if q.qtype == 62 then
        has.Raid = true
      elseif q.qtype == 81 or hasFlag(q, "instance") then
        has.Dungeon = true
      end
      if q.holiday then
        has.Festival = true
      end
    end
    local kinds = {}
    for _, key in ipairs({ "Class", "Profession", "Raid", "Dungeon", "Festival" }) do
      if has[key] then
        kinds[#kinds + 1] = key
      end
    end
    shape.kinds = kinds
  end
  return shape.kinds
end

local PROGRESS_ORDER = { on = 1, start = 2, later = 3, finished = 4 }
Logic.PROGRESS_ORDER = PROGRESS_ORDER

-- The chains that have a main step or a side quest among `qids` (a zone's quests, an area's),
-- for a character: { { chain = Logic.chainSheet's answer, steps = { the numbers of its main
-- steps there, ascending }, side = how many of its side quests are there } }. Ordered by how
-- far the character is (on the way, can start, later, finished), then by the lowest level, then
-- by the root. A quest the character cannot take counts for nothing.
function Logic.chainsAmong(qids, state)
  local byRoot, out = {}, {}
  for _, qid in ipairs(qids or {}) do
    local place = Logic.chainPlace(qid, state)
    if place and not place.why then
      local entry = byRoot[place.root]
      if not entry then
        local c = Logic.chainSheet(place.root, state)
        entry = c and { chain = c, steps = {}, side = 0 } or false
        byRoot[place.root] = entry
        if entry then
          out[#out + 1] = entry
        end
      end
      if entry then
        if place.step then
          entry.steps[#entry.steps + 1] = place.step
        else
          entry.side = entry.side + 1
        end
      end
    end
  end
  for _, entry in ipairs(out) do
    table.sort(entry.steps)
  end
  table.sort(out, function(a, b)
    local pa, pb = PROGRESS_ORDER[a.chain.state], PROGRESS_ORDER[b.chain.state]
    if pa ~= pb then
      return pa < pb
    end
    local la, lb = a.chain.lo or 999, b.chain.lo or 999
    if la ~= lb then
      return la < lb
    end
    return a.chain.id < b.chain.id
  end)
  return out
end

-- ---------------------------------------------------------------------------------------------
-- Marks and categories
-- ---------------------------------------------------------------------------------------------

function Logic.isGroup(q)
  local t = q.qtype
  return t == 1 or t == 62 or t == 81 or hasFlag(q, "instance")
end

-- Short marks, English keys (the UI translates them), most important first.
function Logic.marks(q)
  local out = {}
  local t = q.qtype
  if t == 62 then
    out[#out + 1] = "Raid"
  elseif t == 81 or hasFlag(q, "instance") then
    out[#out + 1] = "Dungeon"
  end
  if t == 1 then
    out[#out + 1] = "Group"
  end
  if t == 41 then
    out[#out + 1] = "PvP"
  end
  if t == 84 then
    out[#out + 1] = "Escort"
  end
  if hasFlag(q, "repeatable") then
    out[#out + 1] = "Repeatable"
  end
  if q.holiday then
    out[#out + 1] = q.holiday
  end
  return out
end

-- A class quest: the data restricts it to classes (quests.md "Class quests").
function Logic.isClassQuest(q)
  return ((q.classes and q.classes > 0) or hasFlag(q, "class")) and true or false
end

-- Where an available quest goes in the tree: class, profession, chain or single.
function Logic.category(qid, state)
  local q = quest(qid)
  if Logic.isClassQuest(q) then
    return "class"
  end
  if q.skill or hasFlag(q, "profession") then
    return "profession"
  end
  if Logic.chain(qid, state) then
    return "chain"
  end
  return "single"
end

-- Quests that a quest unlocks or leads to.
function Logic.next(qid)
  index()
  return followers[qid] or {}
end

-- Other maps this quest leads to (its followers start there).
function Logic.leadsTo(qid, map)
  local out, seen = {}, {}
  for _, f in ipairs(Logic.next(qid)) do
    local fq = quest(f)
    local m = fq and startMap(fq)
    if m and m ~= map and not seen[m] then
      seen[m] = true
      out[#out + 1] = m
    end
  end
  table.sort(out)
  return out
end

-- ---------------------------------------------------------------------------------------------
-- Zone view: everything for one map and one character, grouped by the place of giver or taker
-- ---------------------------------------------------------------------------------------------

local function dist2(px, py, x, y)
  if not (px and x) then
    return math.huge
  end
  return (px - x) ^ 2 + (py - y) ^ 2
end

local function placeOf(q, which)
  local refs = which == "turnin" and q.ends or q.starts
  local places = which == "turnin" and q.endPlaces or q.startPlaces
  local ref = refs and refs[1]
  local p = places and places[1]
  return ref, p and p[2] or nil, p and p[3] or nil
end

-- Group quests by the giver or taker (one pin per entity), nearest first.
local function group(list, map, which, px, py)
  local groups, byKey = {}, {}
  for _, qid in ipairs(list) do
    local q = quest(qid)
    local ref, x, y = placeOf(q, which)
    local key = (ref or "?") .. "@" .. tostring(x) .. "," .. tostring(y)
    local g = byKey[key]
    if not g then
      g = { ref = ref, map = map, x = x, y = y, quests = {} }
      byKey[key] = g
      groups[#groups + 1] = g
    end
    g.quests[#g.quests + 1] = qid
  end
  for _, g in ipairs(groups) do
    table.sort(g.quests, function(a, b)
      local la, lb = quest(a).level or 0, quest(b).level or 0
      if la ~= lb then
        return la < lb
      end
      return a < b
    end)
    g.d = dist2(px, py, g.x, g.y)
    g.minLevel = quest(g.quests[1]).level or 0
  end
  table.sort(groups, function(a, b)
    if a.d ~= b.d then
      return a.d < b.d
    end
    if a.minLevel ~= b.minLevel then
      return a.minLevel < b.minLevel
    end
    return (a.ref or "") < (b.ref or "")
  end)
  return groups
end
Logic.group = group

-- Missing earlier quests that start on another map: what to bring along before coming here.
local function elsewhere(missing, map)
  local out = {}
  for _, m in ipairs(missing or {}) do
    local mq = quest(m)
    local sm = mq and startMap(mq)
    if sm and sm ~= map then
      out[#out + 1] = m
    end
  end
  return out
end
Logic.elsewhere = elsewhere

-- { map, turnin, active, available, soon, blocked, done, counts }; px, py are map fractions.
function Logic.zoneView(map, state, px, py)
  index()
  local view = { map = map, blocked = {} }
  local turnin, active, avail, soon, done = {}, {}, {}, {}, {}
  local complete = state.isComplete or state.inLog
  for _, qid in ipairs(byTurnIn[map] or {}) do
    if state.inLog(qid) then
      if complete(qid) then
        turnin[#turnin + 1] = qid
      else
        active[#active + 1] = qid
      end
    end
  end
  for _, qid in ipairs(byStart[map] or {}) do
    local st, missing = Logic.status(qid, state)
    if st == "available" then
      avail[#avail + 1] = qid
    elseif st == "level" and (quest(qid).minLevel or 0) - state.level <= Logic.SOON then
      soon[#soon + 1] = qid
    elseif st == "prereq" then
      local away = elsewhere(missing, map)
      if #away > 0 then
        view.blocked[#view.blocked + 1] = { qid = qid, missing = away }
      end
    elseif st == "done" then
      done[#done + 1] = qid
    end
  end
  table.sort(view.blocked, function(a, b)
    return (quest(a.qid).level or 0) < (quest(b.qid).level or 0)
  end)
  view.turnin = group(turnin, map, "turnin", px, py)
  view.active = group(active, map, "turnin", px, py)
  view.available = group(avail, map, "start", px, py)
  view.soon = group(soon, map, "start", px, py)
  view.done = group(done, map, "start", px, py)
  view.counts = {
    turnin = #turnin,
    active = #active,
    available = #avail,
    soon = #soon,
    blocked = #view.blocked,
    done = #done,
  }
  return view
end

-- ---------------------------------------------------------------------------------------------
-- Zones: the zone list for a faction in level order, and where a zone's quests lead
-- ---------------------------------------------------------------------------------------------

local function zoneRecords()
  local out = {}
  local idx = data and data:Index("quest.byZone")
  for map in pairs(idx or {}) do
    local z = data:Get("zone", map)
    -- outdoor zones only: a dungeon (UiMap type 4 and up) or a map without a name is no
    -- neighbour or next area
    if z and z.name and (z.mapType == nil or z.mapType <= 3) then
      out[#out + 1] = {
        map = map,
        name = z.name,
        lo = z.levelLo,
        hi = z.levelHi,
        med = z.levelMed,
        a = z.questsA or 0,
        h = z.questsH or 0,
      }
    end
  end
  table.sort(out, function(x, y)
    if (x.med or 99) ~= (y.med or 99) then
      return (x.med or 99) < (y.med or 99)
    end
    return x.map < y.map
  end)
  return out
end

-- Zones for this faction, in level order. A zone counts when its own quests reach a quarter of the
-- other side's (contested zones stay, Silverpine with 4 Alliance quests against 51 does not).
function Logic.zones(faction)
  local out = {}
  for _, z in ipairs(zoneRecords()) do
    local mine, theirs = z.a, z.h
    if faction == "Horde" then
      mine, theirs = z.h, z.a
    end
    if (mine > 0 and mine >= Logic.OWN_SHARE * theirs) or (theirs == 0 and (z.a + z.h) > 0) then
      out[#out + 1] = z
    end
  end
  return out
end

function Logic.zoneInfo(map)
  for _, z in ipairs(zoneRecords()) do
    if z.map == map then
      return z
    end
  end
end

-- Where the quests of this zone lead: maps whose quests follow from quests that start here and that
-- this character can take, with how many quests point there; nearest level band first.
function Logic.onward(map, state)
  index()
  local count = {}
  for _, qid in ipairs(byStart[map] or {}) do
    local q = quest(qid)
    if Logic.canEverTake(q, state) then
      for _, f in ipairs(Logic.next(qid)) do
        local fq = quest(f)
        local m = fq and startMap(fq)
        if m and m ~= map and Logic.canEverTake(fq, state) then
          count[m] = (count[m] or 0) + 1
        end
      end
    end
  end
  local out = {}
  for m, n in pairs(count) do
    local z = Logic.zoneInfo(m)
    out[#out + 1] =
      { map = m, n = n, lo = z and z.lo, hi = z and z.hi, med = z and z.med or 99, name = z and z.name }
  end
  table.sort(out, function(a, b)
    if a.med ~= b.med then
      return a.med < b.med
    end
    return a.map < b.map
  end)
  return out
end

-- The zone before or after `map` in level order (step -1 or 1); nil at the ends.
function Logic.neighbor(map, faction, step)
  local list = Logic.zones(faction)
  for i, z in ipairs(list) do
    if z.map == map then
      local n = list[i + step]
      return n and n.map
    end
  end
  return list[1] and list[1].map
end

-- Does the data know this map at all?
function Logic.knows(map)
  index()
  return map and (byStart[map] ~= nil or byTurnIn[map] ~= nil) or false
end
