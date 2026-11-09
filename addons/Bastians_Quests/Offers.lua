-- What the givers really offer (quests.md "What the game offers", ADR 0051): the first page of a
-- gossip or greeting against the data. A quest the data expected and the page lacks is `inactive`
-- for this character until it gains a level; a quest the game offers beats the data.
local _, ns = ...
local B = Bastians
local Logic, State = ns.Logic, ns.State

local Offers = {}
ns.Offers = Offers

Offers.AGAIN = 60 -- seconds a giver's page counts as the same visit: an option's sub-page lists no quests

local mod
local lastRef, lastAt
local open = false -- the page of the last visit is still up

local function fire()
  mod:Fire("BASTIANS_QUESTS_CHANGED", nil, { offers = true })
end

-- The page's quests as sets by id and by lower-cased title, and how many titles; nil when one of
-- them cannot be read.
local function readPage(kind)
  local _, available
  if kind == "gossip" then
    _, available = B.Compat.GossipQuests()
  else
    _, available = B.Compat.GreetingQuests()
  end
  local byID, byTitle, titles = {}, {}, 0
  for _, q in ipairs(available) do
    if q.questID then
      byID[q.questID] = true
    elseif q.title then
      byTitle[string.lower(q.title)] = true
      titles = titles + 1
    else
      return nil
    end
  end
  return byID, byTitle, titles
end

-- Whether the page lists the quest; the second value says it did so by title.
local function listed(qid, q, byID, byTitle)
  if byID[qid] then
    return true, false
  end
  for _, name in ipairs({ q.name or "", ns.Rows.questName(qid) }) do
    if byTitle[string.lower(name)] then
      return true, true
    end
  end
  return false, false
end

-- The game offers the quest: no mark stands against it, and it beats the data. True when that
-- changes what the quest's status says.
function Offers.Note(qid, s)
  local changed = State.missed[qid] ~= nil
  State.missed[qid] = nil
  local q = Logic.quest(qid)
  if q and Logic.gatedByData(q, s) then
    changed = changed or not s.offered(qid)
    State.offered[qid] = time()
  end
  return changed
end

-- One visit: the giver's page against the quests the data gives it.
function Offers.Visit(kind)
  if InCombatLockdown() then
    return -- the page's texts may be secret
  end
  local ref = B.Compat.NpcEntity()
  if not ref then
    return
  end
  local now = GetTime()
  if ref == lastRef and (open or now - lastAt < Offers.AGAIN) then
    return
  end
  lastRef, lastAt, open = ref, now, true
  local d = B:GetService("data")
  local ids = d and d:Index("quest.byGiver", ref)
  local byID, byTitle, titles = readPage(kind)
  if not (ids and byID) then
    return
  end
  local s = State.ForLogic()
  local changed = false
  local missing = {}
  for _, qid in ipairs(ids) do
    local q = Logic.quest(qid)
    if q then
      local here, byName = listed(qid, q, byID, byTitle)
      if here then
        titles = titles - (byName and 1 or 0)
        changed = Offers.Note(qid, s) or changed
      elseif Logic.status(qid, s) == "available" and not Logic.isTrivial(q, s) then
        missing[#missing + 1] = qid -- the client may leave a low-level quest out
      end
    end
  end
  if titles > 0 then
    missing = {} -- a title we could not match may be one of them
  end
  for _, qid in ipairs(missing) do
    State.missed[qid] = s.level
    changed = true
  end
  mod:Log("debug", "offers at %s: %d in the data, %d not offered", ref, #ids, #missing)
  if changed then
    fire()
  end
end

-- A quest's detail window: the game offers it, whoever or whatever opened it. Says nothing about
-- the giver's other quests (it also follows a hand-in).
function Offers.Detail()
  local qid = B.Compat.QuestID()
  if qid and not InCombatLockdown() and Offers.Note(qid, State.ForLogic()) then
    fire()
  end
end

function Offers.Closed()
  open = false
end

function Offers.Register(self)
  mod = self
  lastRef, lastAt, open = nil, nil, false
  self:RegisterEvent("GOSSIP_SHOW", function()
    Offers.Visit("gossip")
  end)
  self:RegisterEvent("QUEST_GREETING", function()
    Offers.Visit("greeting")
  end)
  self:RegisterEvent("QUEST_DETAIL", function(...)
    ns.Rewards.ReadOffer(...) -- a module has one handler per event, and this one replaces Rewards'
    Offers.Detail(...)
  end)
  self:RegisterEvent("GOSSIP_CLOSED", Offers.Closed)
  self:RegisterEvent("QUEST_FINISHED", Offers.Closed)
end
