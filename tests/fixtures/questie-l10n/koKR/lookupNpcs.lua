if GetLocale() ~= "koKR" then
    return
end

---@type l10n
local l10n = QuestieLoader:ImportModule("l10n")

l10n.npcNameLookup["koKR"] = loadstring([[return {
[240] = {"보안관 듀간","보안관"},
}]])
