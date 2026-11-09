-- What a quest earns, as the game says it (ADR 0053): the client's answers for the log and for what a
-- giver offers, kept for the account so a quest once seen keeps its rewards. Logic.rewards reads them.
local _, ns = ...
local B = Bastians
local Logic, State = ns.Logic, ns.State

local Rewards = {}
ns.Rewards = Rewards

local mod
local read = {} -- questID -> true: asked this session and level (a read moves the log's selection)

local function count(list)
  return #(list or {})
end

-- Keeps what the client said; true when it differs from what was kept.
function Rewards.Learn(qid, said)
  if not (mod and qid and said) then
    return false
  end
  local store = mod.db.global.rewards
  local old = store[qid]
  if
    old
    and old.money == said.money
    and old.xp == said.xp
    and count(old.items) == count(said.items)
    and count(old.choices) == count(said.choices)
  then
    return false
  end
  store[qid] = said
  Logic.SetLearnedRewards(store)
  return true
end

local function told()
  mod:Fire("BASTIANS_REWARD_INFO_CHANGED") -- the page's rewards, the sheet, the rows
end

-- Asks the client once for each log quest not asked yet; never in combat, the selection moves.
function Rewards.ReadLog()
  if not mod or InCombatLockdown() then
    return
  end
  local changed = false
  for _, qid in ipairs(State.order) do
    if not read[qid] then
      read[qid] = true
      changed = Rewards.Learn(qid, B.Compat.GetQuestLogRewards(qid)) or changed
    end
  end
  if changed then
    told()
  end
end

-- The giver shows a quest: its rewards, before the quest is in the log.
function Rewards.ReadOffer()
  if Rewards.Learn(B.Compat.QuestID(), B.Compat.GetOfferRewards()) then
    told()
  end
end

-- Experience follows the level: the next read asks again.
function Rewards.Forget()
  read = {}
end

function Rewards.Register(self)
  mod = self
  self.db.global.rewards = self.db.global.rewards or {}
  Logic.SetLearnedRewards(self.db.global.rewards)
  self:RegisterEvent("QUEST_DETAIL", Rewards.ReadOffer)
  self:RegisterEvent("QUEST_COMPLETE", Rewards.ReadOffer)
end
