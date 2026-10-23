-- Test double of Spoken Quests 3.5: the VoiceOver environment internals the Quests bridge reaches
-- for (DataModules:PrepareSound, Player:PlayNow, Enums.SoundEvent). Quest 999 has no voice line.
VoiceOver = {
  DataModules = {
    PrepareSound = function(_, sound)
      VoiceOver.prepared = (VoiceOver.prepared or 0) + 1
      if sound.questID == 999 then
        return false
      end
      sound.path = "Interface\\AddOns\\SpokenQuestsAudio\\q" .. sound.questID .. ".ogg"
      return true
    end,
    GetQuestLogQuestGiverTypeAndID = function()
      return "creature", 240
    end,
    GetObjectName = function()
      return "Marshal Dughan"
    end,
  },
  Player = {
    PlayNow = function(_, sound)
      Spoken.queue[#Spoken.queue + 1] = sound
      Spoken:Fire("AUDIO_CHANGED")
    end,
  },
  Enums = {
    SoundEvent = { QuestAccept = 1, QuestProgress = 2, QuestComplete = 3 },
    GUID = {
      CanHaveID = function()
        return true
      end,
      IsCreature = function(_, kind)
        return kind == "creature"
      end,
    },
  },
  Utils = {
    MakeGUID = function(_, kind, id)
      return kind .. "-" .. id
    end,
  },
}
