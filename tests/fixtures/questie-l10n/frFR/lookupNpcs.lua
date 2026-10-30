if GetLocale() ~= "frFR" then
    return
end

---@type l10n
local l10n = QuestieLoader:ImportModule("l10n")

l10n.npcNameLookup["frFR"] = loadstring([[return {
[240] = {"Maréchal Dughan","Maréchal"},
}]])
