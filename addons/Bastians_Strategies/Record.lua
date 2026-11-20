-- Bastian's Book: the record (book.md "The record"): what this character and the other characters
-- of the account did, marked by hand or found in the game (quest history, bags and bank, known
-- spells, titles), and the envelopes opened. The check of a rule is pure; the scan asks Compat.
local _, ns = ...
local B = Bastians

local Record = {}
ns.Record = Record

local pairs, ipairs, type = pairs, ipairs, type

Record.PER_FRAME = 200 -- wonders checked per frame after login (book.md)
Record.BAG_DELAY = 2 -- seconds: bag updates coalesced

local global, key -- the account's saved table and this character's key

-- The account's table (BastiansStrategiesDB.global) and this character: key "Name-Realm",
-- me = { name, class, faction, level }. Keeps only the account's own characters (CLAUDE.md §8).
function Record.Bind(g, k, me)
  global, key = g, k
  g.record = g.record or {}
  g.opened = g.opened or {}
  local r = g.record[k] or {}
  r.done = r.done or {}
  if me then
    r.name, r.class, r.faction, r.level = me.name, me.class, me.faction, me.level
  end
  g.record[k] = r
  return r
end

function Record.Key()
  return key
end

function Record.Mine()
  return global and key and global.record[key] or nil
end

function Record.IsDone(id)
  local me = Record.Mine()
  return me ~= nil and me.done[id] ~= nil
end

-- What this character did with the wonder: { how = "mark" | "found", at, name } or nil.
function Record.Entry(id)
  local me = Record.Mine()
  return me and me.done[id] or nil
end

-- `name`: the wonder's title, kept with the mark, so a wonder that later leaves the pack (what
-- is not obtainable is removed, book.md "What is obtainable") still has a name in the record.
function Record.Mark(id, how, at, name)
  local me = Record.Mine()
  if not me or not id then
    return false
  end
  if not me.done[id] then
    me.done[id] = { how = how or "mark", at = at or time(), name = name }
  end
  return true
end

-- The marks made before a name was kept take it from the shelf, while the pack still holds
-- their wonder. `entries`: the shelf's.
function Record.KeepNames(entries)
  local me = Record.Mine()
  if not me then
    return
  end
  for _, e in ipairs(entries) do
    local d = me.done[e.id]
    if d and not d.name then
      d.name = e.title
    end
  end
end

-- Undoes a mark ("Not done yet"); the game may find it again on the next scan.
function Record.Unmark(id)
  local me = Record.Mine()
  if me then
    me.done[id] = nil
  end
end

-- The other characters that did it and this one did not: their names, sorted; {} for none.
function Record.Alts(id)
  local out = {}
  if not global or Record.IsDone(id) then
    return out
  end
  for k, r in pairs(global.record) do
    if k ~= key and r.done and r.done[id] then
      out[#out + 1] = r.name or k
    end
  end
  table.sort(out)
  return out
end

function Record.IsOpened(id)
  return global ~= nil and global.opened[id] == true
end

function Record.Open(id)
  if global then
    global.opened[id] = true
  end
end

-- Your record's lists: mine = { { id, how, at } } newest first; alts = { { id, names } } by id.
function Record.Lists()
  local mine, alts = {}, {}
  local me = Record.Mine()
  for id, d in pairs(me and me.done or {}) do
    mine[#mine + 1] = { id = id, how = d.how, at = d.at or 0 }
  end
  table.sort(mine, function(a, b)
    if a.at ~= b.at then
      return a.at > b.at
    end
    return a.id < b.id
  end)
  local seen = {}
  for k, r in pairs(global and global.record or {}) do
    if k ~= key then
      for id in pairs(r.done or {}) do
        if not seen[id] and not (me and me.done[id]) then
          seen[id] = true
          alts[#alts + 1] = { id = id, names = Record.Alts(id) }
        end
      end
    end
  end
  table.sort(alts, function(a, b)
    return a.id < b.id
  end)
  return { mine = mine, alts = alts }
end

-- ---------------------------------------------------------------------------------------------
-- The check (pure): rule = the wonder's `done` (book.md "The data"); ask = { quest(id) -> bool|nil,
-- item(id) -> count|nil, spell(id) -> bool|nil, title(id) -> bool|nil }; side "A" | "H".
-- -> true (the game shows it done), false (it does not), nil (it cannot tell, or no rule).
-- ---------------------------------------------------------------------------------------------

function Record.Check(rule, ask, side)
  if type(rule) ~= "table" then
    return nil
  end
  local unsure = false
  local function take(answer)
    if answer == nil then
      unsure = true
    end
    return answer
  end
  if rule.item and ask.item then
    local n = take(ask.item(rule.item))
    if n and n > 0 then
      return true
    end
  end
  if rule.spell and ask.spell and take(ask.spell(rule.spell)) then
    return true
  end
  if rule.title and ask.title and take(ask.title(rule.title)) then
    return true
  end
  if rule.quests and ask.quest then
    local ids = side and rule.quests[side]
    if not ids and not side then
      unsure = true
    end
    for _, q in ipairs(ids or {}) do
      if take(ask.quest(q)) then
        return true
      end
    end
  end
  if unsure then
    return nil
  end
  if rule.item or rule.spell or rule.title or rule.quests then
    return false
  end
  return nil
end

-- ---------------------------------------------------------------------------------------------
-- The scan: the game's answers through Compat, a little each frame
-- ---------------------------------------------------------------------------------------------

function Record.Ask()
  local C = B.Compat
  return {
    quest = function(id)
      if C.IsQuestCompleted then
        return C.IsQuestCompleted(id) == true
      end
      return nil
    end,
    item = function(id)
      if C.GetItemCount then
        return C.GetItemCount(id, true)
      end
      return nil
    end,
    spell = function(id)
      if C.IsSpellKnown then
        return C.IsSpellKnown(id)
      end
      return nil
    end,
    title = function(id)
      if C.IsTitleKnown then
        return C.IsTitleKnown(id)
      end
      return nil
    end,
  }
end

function Record.Side()
  local faction = UnitFactionGroup and UnitFactionGroup("player")
  return faction == "Alliance" and "A" or faction == "Horde" and "H" or nil
end

-- Checks `entries` (the shelf's) that have a rule and are not done yet: found ones are marked.
-- `onFound(n)` after the end when any was found. Through Core's jobs when there are many.
function Record.Scan(owner, entries, onFound)
  if not Record.Mine() then
    return
  end
  Record.KeepNames(entries)
  local todo = {}
  for _, e in ipairs(entries) do
    if e.done and not Record.IsDone(e.id) then
      todo[#todo + 1] = e
    end
  end
  if #todo == 0 then
    return
  end
  local ask, side = Record.Ask(), Record.Side()
  local found = 0
  local function step(i)
    local e = todo[i]
    if Record.Check(e.done, ask, side) then
      Record.Mark(e.id, "found", nil, e.title)
      found = found + 1
    end
  end
  local function finish()
    if found > 0 and onFound then
      onFound(found)
    end
  end
  if B.Jobs and #todo > Record.PER_FRAME then
    B.Jobs:Run(owner, "book.record", function(yield)
      for i = 1, #todo do
        step(i)
        if i % Record.PER_FRAME == 0 then
          yield()
        end
      end
    end, { onDone = finish })
  else
    for i = 1, #todo do
      step(i)
    end
    finish()
  end
end
