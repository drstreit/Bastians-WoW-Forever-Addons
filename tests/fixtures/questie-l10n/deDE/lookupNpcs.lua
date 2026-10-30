if GetLocale() ~= "deDE" then
    return
end

---@type l10n
local l10n = QuestieLoader:ImportModule("l10n")

l10n.npcNameLookup["deDE"] = loadstring([[return {
[448] = {"Hogger",nil},
[240] = {"Marshal Dughan","Marschall"},
}]])
