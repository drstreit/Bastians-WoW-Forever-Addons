if GetLocale() ~= "deDE" then
    return
end

---@type l10n
local l10n = QuestieLoader:ImportModule("l10n")

l10n.questLookup["deDE"] = loadstring([[return {
[176] = {"Gesucht: \"Hogger\"", {"Bringt die riesige Gnollklaue zu Marschall Dughan in Goldhain."}},
[62] = {"Die Mine von Tiefenhain", nil},
[99999] = {"Eine Quest, die unsere Packs nicht kennen", {"Nichts."}},
}]])
