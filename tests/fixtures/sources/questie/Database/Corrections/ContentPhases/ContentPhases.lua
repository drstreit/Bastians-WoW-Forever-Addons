-- Trimmed from Questie 12.6.0.
---@class ContentPhases
local ContentPhases = QuestieLoader:CreateModule("ContentPhases")

ContentPhases.activePhases = {
    SoM = 5,
    SoD = 7,
    Anniversary = 6,
    MoP = 5,
    TBC = 4,
}

ContentPhases.IsInvasionActive = {
    [1] = Questie.IsSoD and true or false, -- Era
    [2] = false, -- TBC
    [3] = false, -- Wotlk
}
