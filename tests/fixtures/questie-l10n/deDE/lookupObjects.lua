if GetLocale() ~= "deDE" then
    return
end

---@type l10n
local l10n = QuestieLoader:ImportModule("l10n")

l10n.objectLookup["deDE"] = loadstring([[return {
[1734] = "Steckbrief",
}]])
