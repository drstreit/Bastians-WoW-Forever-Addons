if GetLocale() ~= "deDE" then
    return
end

---@type l10n
local l10n = QuestieLoader:ImportModule("l10n")

l10n.itemLookup["deDE"] = loadstring([[return {
[2589] = "Leinenstoff",
[1185] = "Blutsäbel",
}]])
