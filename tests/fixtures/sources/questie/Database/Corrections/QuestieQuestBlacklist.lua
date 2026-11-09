-- Trimmed from Questie 12.6.0: the shape of the real file, its expressions and its three lists.
---@class QuestieQuestBlacklist
local QuestieQuestBlacklist = QuestieLoader:CreateModule("QuestieQuestBlacklist")
---@type ContentPhases
local ContentPhases = QuestieLoader:ImportModule("ContentPhases")
---@type Expansions
local Expansions = QuestieLoader:ImportModule("Expansions")

local HIDE_ON_MAP = "HIDE_ON_MAP"

QuestieQuestBlacklist.HIDE_ON_MAP = HIDE_ON_MAP

function QuestieQuestBlacklist:Load()
    local questsToBlacklist = {
        [787] = true, -- The New Horde is not in the game. See #830
        [172] = true, -- Children's Week: hidden until the event runs
        [2358] = Expansions.Current == Expansions.Era or Expansions.Current >= Expansions.Wotlk,
        [236] = Expansions.Current < Expansions.Wotlk,
        [9260] = Expansions.Current >= Expansions.Cata, -- Investigate the Scourge of Stormwind
        [63866] = Expansions.Current >= Expansions.Wotlk or (Expansions.Current == Expansions.Tbc and ContentPhases.activePhases.TBC < 5),
        [78124] = HIDE_ON_MAP, -- Nar'thalas Almanac
    }

    if Questie.IsSoD then
        questsToBlacklist = ContentPhases.BlacklistSoDQuestsByPhase(questsToBlacklist, ContentPhases.activePhases.SoD)
    elseif Questie.IsAnniversaryEra or Questie.IsAnniversaryHardcore then
        questsToBlacklist = ContentPhases.BlacklistAnniversaryQuestsByPhase(questsToBlacklist, ContentPhases.activePhases.Anniversary)
    end

    return questsToBlacklist
end

QuestieQuestBlacklist.AQWarEffortQuests = {
    [8492] = true,
    [8493] = true,
}

QuestieQuestBlacklist.InvasionQuests = {
    [9260] = true, -- Investigate the Scourge of Stormwind
    [9292] = true, -- Cracked Necrotic Crystal
}
