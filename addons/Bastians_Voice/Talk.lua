-- Bastian's Voice, the conversation (voice.md §4, off by default): when the player talks to an NPC
-- the game's gossip and quest windows stay shut and the Lore Orbit shows the NPC's quests and what
-- to say; accept, decline, continue and hand in go through the Compat wrappers Helpers uses. The
-- player starts the conversation (a click, the interact key); no addon can.
local _, ns = ...
local B = Bastians
local L = ns.L
local Voice = ns.Voice
local Model = Voice.Model
local Orbit = ns.Orbit

local Talk = {}
ns.Talk = Talk
Voice.Talk = Talk

Talk.state = nil -- { step, npc, quests, options, current, hidden, gameWindow }

local function profile()
  local mod = B:GetModule("Voice.Talk")
  return mod and mod.db and mod.db.profile or {}
end

local function npc()
  local guid = UnitGUID("npc")
  return { name = UnitName("npc"), creature = Model.CreatureID(guid) }
end

-- Whether this visit keeps the game's windows: the pause key (Shift, Helpers' default) held.
local function paused()
  return B.Compat.ModifierDown(profile().pauseKey or "shift")
end

local function questItem(title, status, questID, select)
  return {
    kind = "quest",
    size = "here",
    title = title,
    status = status,
    questID = questID,
    ref = questID and ("quest:" .. questID) or nil,
    line = questID and Voice.Line("quest:" .. questID) or nil,
    heard = questID and Voice.IsHeard(Model.Key("quest", questID, "accept")) or false,
    hint = L["Click: the giver tells you about it"],
    onClick = select,
  }
end

-- `glyph` draws the answer as a symbol with the words in its tooltip.
local function sayItem(label, run, hint, glyph)
  return {
    kind = "say",
    title = label,
    label = label,
    glyph = glyph,
    hint = hint or L["Click to say it"],
    onClick = run,
  }
end

local function actItem(label, run, hint, glyph)
  return {
    kind = "act",
    size = "here",
    title = label,
    label = label,
    glyph = glyph,
    hint = hint or L["Click to answer"],
    onClick = run,
  }
end

-- The gossip or greeting list: the NPC's quests and its options.
local function listStep(frame)
  local state = { step = frame, npc = npc(), quests = {}, options = {} }
  local active, available
  if frame == "gossip" then
    active, available = B.Compat.GossipQuests()
    for _, q in ipairs(active) do
      state.quests[#state.quests + 1] = questItem(
        q.title,
        q.complete and "ready" or "log",
        q.questID,
        function()
          B.Compat.NpcSelect("gossip", "active", q.questID)
        end
      )
    end
    for _, q in ipairs(available) do
      state.quests[#state.quests + 1] = questItem(q.title, "available", q.questID, function()
        B.Compat.NpcSelect("gossip", "available", q.questID)
      end)
    end
    for _, o in ipairs(B.Compat.GossipOptions()) do
      state.options[#state.options + 1] = sayItem(o.name, function()
        B.Compat.NpcSelect("gossip", "option", o.id)
      end)
    end
  else
    active, available = B.Compat.GreetingQuests()
    for _, q in ipairs(active) do
      state.quests[#state.quests + 1] = questItem(q.title, q.complete and "ready" or "log", nil, function()
        B.Compat.NpcSelect("greeting", "active", q.index)
      end)
    end
    for _, q in ipairs(available) do
      state.quests[#state.quests + 1] = questItem(q.title, "available", nil, function()
        B.Compat.NpcSelect("greeting", "available", q.index)
      end)
    end
  end
  state.options[#state.options + 1] = sayItem(L["Farewell"], Talk.Bye, L["Ends the conversation"])
  return state
end

-- One quest's detail, progress or hand-in step.
local function questStep(step)
  local detail = B.Compat.QuestDetail() or {}
  local questID = B.Compat.QuestID()
  local state = {
    step = step,
    npc = npc(),
    quests = {},
    options = {},
    current = {
      questID = questID,
      title = detail.title,
      text = detail.text,
      objectives = detail.objectives,
      actions = {},
      choices = {},
    },
  }
  local current = state.current
  local q = questItem(
    detail.title or "?",
    step == "complete" and "ready" or step == "progress" and "log" or "available",
    questID
  )
  q.onClick = nil
  q.hint = L["The giver speaks about it"]
  q.detail = { text = detail.text, objectives = detail.objectives } -- for the quest sheet
  state.quests[1] = q
  if step == "detail" then
    current.actions[1] = actItem(L["Accept"], Talk.Accept, L["Takes the quest; the tracker shows it"], "done")
    current.actions[2] =
      sayItem(L["Not now"], Talk.Decline, L["Declines; the giver keeps offering it"], "never")
  elseif step == "progress" then
    local completable, cost = B.Compat.QuestProgress()
    current.completable, current.cost = completable, cost
    if completable then
      current.actions[1] = actItem(L["Continue"], Talk.Continue, L["On to the hand-in"], "arrow")
    end
    current.actions[#current.actions + 1] =
      sayItem(L["Not now"], Talk.Bye, L["Ends the conversation"], "never")
  elseif step == "complete" then
    for _, choice in ipairs(B.Compat.QuestChoices()) do
      local ref = choice.itemID and ("item:" .. choice.itemID) or nil
      current.choices[#current.choices + 1] = {
        kind = "object",
        size = "giver",
        ref = ref,
        title = ref and B:Entity(ref):Name() or L["Reward"],
        index = choice.index,
        count = choice.count,
        itemID = choice.itemID,
        hint = L["Click chooses this reward"],
        onClick = function()
          current.choice = choice.index
          Orbit.Render()
        end,
      }
    end
    current.actions[1] =
      actItem(L["Hand in"], Talk.HandIn, #current.choices > 1 and L["Choose a reward first"] or nil, "done")
    current.actions[2] = sayItem(L["Not now"], Talk.Bye, L["Ends the conversation"], "never")
  end
  return state
end

-- The orbit's items of a conversation: the quests on the inner orbit, the answers and the options
-- on the outer one (the answers below, the options above).
function Talk.OrbitItems(state)
  local places, outer = {}, {}
  for _, q in ipairs(state.quests) do
    places[#places + 1] = q
  end
  local current = state.current
  if current then
    for _, c in ipairs(current.choices) do
      c.chosen = current.choice == c.index
      places[#places + 1] = c
    end
    local n = #current.actions
    for i, a in ipairs(current.actions) do
      a.bearing = 180 + (i - (n + 1) / 2) * 50
      if a.kind == "act" and state.step == "complete" and #current.choices > 1 and not current.choice then
        a.disabled = true
      end
      outer[#outer + 1] = a
    end
  end
  -- the options spread over an arc centred on top, at most 240 degrees and at least 60 apart,
  -- so their words do not meet; the name sits at the bottom
  local m = #state.options
  local span = math.min(240, 60 * (m - 1))
  for i, o in ipairs(state.options) do
    o.bearing = (-(span / 2) + (m > 1 and (i - 1) * span / (m - 1) or 0)) % 360
    outer[#outer + 1] = o
  end
  return places, outer, {}
end

-- ---------------------------------------------------------------------------------------------
-- The steps
-- ---------------------------------------------------------------------------------------------

local function begin(state)
  state.hidden = Talk.state and Talk.state.hidden
  if state.hidden == nil then
    state.hidden = not paused()
  end
  if Talk.state and Talk.state.gameWindow then
    state.hidden, state.gameWindow = false, true
  end
  Talk.state = state
  B.Compat.NpcFramesHidden(state.hidden)
  if state.hidden then
    Orbit.SetTalk(state)
  end
  B:Fire("BASTIANS_VOICE_TALK", state.step)
end

function Talk.Gossip()
  begin(listStep("gossip"))
end

function Talk.Greeting()
  begin(listStep("greeting"))
end

function Talk.Detail()
  begin(questStep("detail"))
end

function Talk.Progress()
  begin(questStep("progress"))
end

function Talk.Complete()
  begin(questStep("complete"))
end

-- The conversation ended (the NPC's window closed, the player walked away).
function Talk.End()
  if not Talk.state then
    return
  end
  Talk.state = nil
  B.Compat.NpcFramesHidden(false)
  Orbit.SetTalk(nil)
  B:Fire("BASTIANS_VOICE_TALK", nil)
end

-- The hub's button: the game's own window for this visit.
function Talk.ShowGameWindow()
  if not Talk.state then
    return false
  end
  Talk.state.hidden, Talk.state.gameWindow = false, true
  B.Compat.NpcFramesHidden(false)
  Orbit.SetTalk(nil)
  return true
end

-- ---------------------------------------------------------------------------------------------
-- The answers (the Compat wrappers Helpers uses; the game answers with the next event)
-- ---------------------------------------------------------------------------------------------

function Talk.Accept()
  return B.Compat.QuestAccept()
end

function Talk.Decline()
  return B.Compat.QuestDecline()
end

function Talk.Continue()
  return B.Compat.QuestContinue()
end

function Talk.HandIn()
  local current = Talk.state and Talk.state.current
  if not current then
    return false
  end
  if #current.choices > 1 and not current.choice then
    B:Say(L["Choose a reward first"])
    return false
  end
  local choice = current.choice or (current.choices[1] and current.choices[1].index) or nil
  return B.Compat.QuestTakeReward(choice)
end

function Talk.Bye()
  return B.Compat.NpcClose()
end

function Talk.Attach(mod)
  mod:RegisterEvent("GOSSIP_SHOW", Talk.Gossip)
  mod:RegisterEvent("QUEST_GREETING", Talk.Greeting)
  mod:RegisterEvent("QUEST_DETAIL", Talk.Detail)
  mod:RegisterEvent("QUEST_PROGRESS", Talk.Progress)
  mod:RegisterEvent("QUEST_COMPLETE", Talk.Complete)
  mod:RegisterEvent("GOSSIP_CLOSED", Talk.End)
  mod:RegisterEvent("QUEST_FINISHED", Talk.End)
end

function Talk.Detach()
  Talk.End()
end
