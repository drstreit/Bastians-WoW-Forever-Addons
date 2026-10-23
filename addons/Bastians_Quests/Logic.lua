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
local indexSource -- "pack" (the shipped quest graph) or "decoded" (built from every record)

function Logic.Reset()
  byStart, byTurnIn, followers = nil, nil, nil
  compOf, members, chainFrom, chainCache = nil, nil, nil, nil
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

-- Status of one quest for the character, with the reason:
-- never, done, log, superseded, prereq (second value: missing quests the character can take),
-- skill, rep, level, available.
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
-- Marks and categories
-- ---------------------------------------------------------------------------------------------

local function hasFlag(q, flag)
  for _, f in ipairs(q.flags or {}) do
    if f == flag then
      return true
    end
  end
  return false
end
Logic.hasFlag = hasFlag

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

-- Where an available quest goes in the tree: class, profession, chain or single.
function Logic.category(qid, state)
  local q = quest(qid)
  if (q.classes and q.classes > 0) or hasFlag(q, "class") then
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
