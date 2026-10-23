-- Locale tables: English text is the key and the fallback (CLAUDE.md §5).
local _, ns = ...
local B = ns.B

-- A key may carry a context after "##" where one English word needs two translations ("Rare" the
-- item quality, "Rare##rank" the NPC: "Selten" and "Rar" in German); untranslated, the text before
-- the marker shows.
local function missing(_, key)
  if type(key) == "string" then
    local at = string.find(key, "##", 1, true)
    if at then
      return string.sub(key, 1, at - 1)
    end
  end
  return key
end

-- Bastians.NewLocale() returns a table L where L["Text"] is the translation or the English key itself.
-- L:Register("deDE", { ["Text"] = "Übersetzung" }) adds a translation that is used when the client runs
-- that locale. Core and every app call this once and share nothing else.
function B.NewLocale()
  local L = {}
  local current = GetLocale()
  local function register(_, locale, strings)
    if locale == current then
      for key, value in pairs(strings) do
        rawset(L, key, value)
      end
    end
  end
  rawset(L, "Register", register)
  return setmetatable(L, { __index = missing })
end

B.L = B.NewLocale()
ns.L = B.L
