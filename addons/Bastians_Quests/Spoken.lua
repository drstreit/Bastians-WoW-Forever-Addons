-- Spoken bridge (quests.md "Spoken bridge"), sub-module Quests.Spoken: the voice action on quests.
-- Spoken's public API (3.5, API_VERSION 1) gives compatibility, the queue, the quests source and the
-- AUDIO_CHANGED callback; building the clip of a quest's accept line is not public, so that one
-- thing goes through Spoken Quests' VoiceOver environment (DataModules:PrepareSound, Player:PlayNow),
-- version checked here and nowhere else. When a check fails the action is simply not registered.
local _, ns = ...
local B = Bastians
local L = ns.L
local R = ns.Rows

local Bridge = {}
ns.SpokenBridge = Bridge
ns.mod.SpokenBridge = Bridge -- reachable for tests (Quests.lua loads before this file)

local REQUIRED_API = 1

-- Returns Spoken and VoiceOver when everything the bridge needs exists, else nil and the reason.
function Bridge.Detect()
  local Spoken = _G.Spoken
  if type(Spoken) ~= "table" or type(Spoken.IsCompatible) ~= "function" then
    return nil, L["Spoken is not installed: no voice button"]
  end
  if not Spoken:IsCompatible(REQUIRED_API) then
    return nil, L["Spoken is too old for the voice button"]
  end
  local VO = _G.VoiceOver
  local DM = type(VO) == "table" and rawget(VO, "DataModules") or nil
  local P = type(VO) == "table" and rawget(VO, "Player") or nil
  local E = type(VO) == "table" and rawget(VO, "Enums") or nil
  if
    type(DM) ~= "table"
    or type(DM.PrepareSound) ~= "function"
    or type(P) ~= "table"
    or type(P.PlayNow) ~= "function"
    or type(E) ~= "table"
    or type(E.SoundEvent) ~= "table"
  then
    return nil, L["Spoken Quests is not installed or changed: no voice button"]
  end
  return Spoken, VO
end

-- The accept-line clip of a quest that is queued or playing, or nil.
function Bridge.Playing(questID)
  local Spoken, VO = Bridge.Detect()
  if not Spoken then
    return nil
  end
  local accept = VO.Enums.SoundEvent.QuestAccept
  local key = "q:" .. tostring(questID) .. ":accept"
  for _, clip in ipairs(Spoken:GetQueue() or {}) do
    if (clip.questID == questID and clip.event == accept) or clip.key == key then
      return clip
    end
  end
  return nil
end

-- The sound table of a quest's accept line, prepared by Spoken Quests (the clip's path is filled
-- in); nil when no installed pack has a line for it.
local function prepare(VO, questID, title)
  local DM, E = VO.DataModules, VO.Enums
  local kind, id
  if DM.GetQuestLogQuestGiverTypeAndID then
    kind, id = DM:GetQuestLogQuestGiverTypeAndID(questID)
  end
  local U, G = rawget(VO, "Utils"), E.GUID
  local canGUID = id and G and G.CanHaveID and G:CanHaveID(kind) and U and U.MakeGUID
  local sound = {
    event = E.SoundEvent.QuestAccept,
    questID = questID,
    title = title,
    name = (id and DM.GetObjectName and DM:GetObjectName(kind, id)) or title or "Unknown Name",
    unitGUID = canGUID and U:MakeGUID(kind, id) or nil,
    unitIsObjectOrItem = id ~= nil and not (G and G.IsCreature and G:IsCreature(kind)),
    origin = "Bastians_Quests",
  }
  if not DM:PrepareSound(sound) then
    return nil
  end
  return sound
end

local lines = {} -- questID -> true | false, asked once per session (the packs do not change)

-- Whether an installed pack has the accept line of a quest, without playing it (ADR 0013: the play
-- symbol only where a line exists). Cached per quest id; nil without Spoken.
function Bridge.HasLine(questID)
  if questID == nil then
    return nil
  end
  local known = lines[questID]
  if known ~= nil then
    return known
  end
  local Spoken, VO = Bridge.Detect()
  if not Spoken then
    return nil
  end
  local has = prepare(VO, questID, R.questName(questID)) ~= nil
  lines[questID] = has
  return has
end

function Bridge.ResetLines()
  lines = {}
end

-- Play the accept line of a quest, or stop it when it is queued already. Returns true and
-- "playing" | "stopped", or false and "missing" | "noline".
function Bridge.Toggle(questID, title)
  local Spoken, VO = Bridge.Detect()
  if not Spoken then
    return false, "missing"
  end
  local playing = Bridge.Playing(questID)
  if playing then
    local source = Spoken:GetSource("quests")
    if source and source.Remove then
      source:Remove(playing)
    else
      Spoken:StopAll()
    end
    return true, "stopped"
  end
  local sound = prepare(VO, questID, title)
  if not sound then
    lines[questID] = false
    return false, "noline"
  end
  lines[questID] = true
  VO.Player:PlayNow(sound)
  return true, "playing"
end

local callback

B:NewModule("Quests.Spoken", {
  title = L["Spoken voice"],
  optional = { "Spoken", "Spoken_Quests" },
  options = {
    {
      type = "note",
      text = function()
        local ok, why = Bridge.Detect()
        return ok and L["Spoken: quest lines play from every quest row"] or why
      end,
    },
  },
  OnEnable = function(self)
    local Spoken = Bridge.Detect()
    if not Spoken then
      return
    end
    B:RegisterAction(self, {
      id = "quests.voice",
      label = L["Play the voice line"],
      short = L["Play"],
      activeShort = L["Stop"],
      icon = B.UI.IconTexture("service"),
      types = { "quest" },
      order = 80,
      -- only where a line exists (ADR 0013 C): `has` is the row renderers' question, `when` the
      -- menu's and the card's; both answer from the per-id cache after the first ask
      has = function(ref)
        local _, id = B.Entity.Parse(ref)
        return Bridge.HasLine(id) == true
      end,
      when = function(ref)
        local _, id = B.Entity.Parse(ref)
        return Bridge.HasLine(id) == true
      end,
      -- playing right now: the Browser shows a stop button then (core-contracts §5, optional)
      active = function(ref)
        local _, id = B.Entity.Parse(ref)
        return Bridge.Playing(id) ~= nil
      end,
      run = function(ref)
        local _, id = B.Entity.Parse(ref)
        local entry = ns.State.log[id]
        local ok, why = Bridge.Toggle(id, entry and entry.title or R.questName(id))
        if not ok and why == "noline" then
          B:Say(L["No voice line for this quest in the installed packs"])
        end
      end,
    })
    callback = Spoken:RegisterCallback("AUDIO_CHANGED", function()
      ns.Window.Schedule()
      self:Fire("BASTIANS_ACTION_STATE", "quests.voice") -- play and stop buttons elsewhere follow
    end)
  end,
  OnDisable = function()
    local Spoken = Bridge.Detect()
    if Spoken and callback and Spoken.UnregisterCallback then
      Spoken:UnregisterCallback(callback)
    end
    callback = nil
    Bridge.ResetLines()
  end,
})
