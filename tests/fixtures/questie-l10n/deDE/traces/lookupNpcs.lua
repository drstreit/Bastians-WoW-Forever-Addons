if GetLocale() ~= "deDE" then
    return
end

---@type l10n
local l10n = QuestieLoader:ImportModule("l10n")

-- captured on the Forever client: wins over the base set; a stray Chinese name is dropped
l10n.npcNameLookup["deDE"] = loadstring([[return {
[240] = {"Marschall Dughan",nil},
[448] = {"佐阿斯伊塔",nil},
}]])
