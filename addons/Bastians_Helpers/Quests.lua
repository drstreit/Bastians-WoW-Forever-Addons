-- Bastian's Helpers, quest givers (helpers.md "Quests"): accept and hand in (off by default),
-- skip a lone gossip option (off by default), share an accepted quest with the group.
local _, ns = ...
local B = Bastians
local L = ns.L
local Helpers = ns.Helpers
local Model = Helpers.Model

local Quests = {}
ns.Quests = Quests
Helpers.Quests = Quests

local function auto()
  return Helpers.On("autoQuest") and not Helpers.Paused()
end

function Quests.OnDetail()
  if auto() then
    B.Compat.QuestAccept()
  end
end

function Quests.OnConfirm()
  if auto() then
    B.Compat.QuestAccept("confirm")
  end
end

function Quests.OnProgress()
  local completable, cost = B.Compat.QuestProgress()
  if auto() and completable and (cost or 0) == 0 then -- a hand-in that takes money stays the player's
    B.Compat.QuestContinue()
  end
end

-- The reward: taken when there is no choice; with a choice the strip names the best one at a
-- vendor and its button takes it.
function Quests.OnComplete()
  if not auto() then
    return
  end
  local choices = B.Compat.QuestChoices()
  if #choices <= 1 then
    B.Compat.QuestTakeReward(#choices == 1 and 1 or nil)
    return
  end
  local best, value = Model.BestChoice(choices, Helpers.SellPrice)
  if not best then
    Helpers.Notice(L["Choose your reward"])
    return
  end
  local itemID
  for _, c in ipairs(choices) do
    if c.index == best then
      itemID = c.itemID
    end
  end
  Helpers.Notice(
    string.format(
      L["Choose your reward: %s pays the most at a vendor (%s)"],
      Helpers.ItemName(itemID),
      B.UI.Money(value)
    ),
    {
      label = L["Take"],
      run = function()
        B.Compat.QuestTakeReward(best)
      end,
    }
  )
end

function Quests.OnGreeting()
  if not auto() then
    return
  end
  local active, available = B.Compat.GreetingQuests()
  local kind, id = Model.QuestPick(active, available, "index")
  if kind then
    B.Compat.NpcSelect("greeting", kind, id)
  end
end

function Quests.OnGossip()
  local active, available = B.Compat.GossipQuests()
  if auto() then
    local kind, id = Model.QuestPick(active, available, "questID")
    if kind then
      B.Compat.NpcSelect("gossip", kind, id)
      return
    end
  end
  if Helpers.On("skipGossip") and not Helpers.Paused() and #active == 0 and #available == 0 then
    local options = B.Compat.GossipOptions()
    if #options == 1 then
      B.Compat.NpcSelect("gossip", "option", options[1].id)
    end
  end
end

-- QUEST_ACCEPTED carries the quest id (retail) or the log index and the id (the older shape).
function Quests.OnAccepted(_, _, a, b)
  local questID = b or a
  if Helpers.On("shareQuests") and questID and B.Compat.IsInGroup() then
    B.Compat.PushQuest(questID)
  end
end

function Quests.Attach(mod)
  mod:RegisterEvent("QUEST_DETAIL", Quests.OnDetail)
  mod:RegisterEvent("QUEST_ACCEPT_CONFIRM", Quests.OnConfirm)
  mod:RegisterEvent("QUEST_PROGRESS", Quests.OnProgress)
  mod:RegisterEvent("QUEST_COMPLETE", Quests.OnComplete)
  mod:RegisterEvent("QUEST_GREETING", Quests.OnGreeting)
  mod:RegisterEvent("GOSSIP_SHOW", Quests.OnGossip)
  mod:RegisterEvent("QUEST_ACCEPTED", Quests.OnAccepted)
end
