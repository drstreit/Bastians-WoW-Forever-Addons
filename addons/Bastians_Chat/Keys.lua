-- Bastian's Chat, the history of the input bar (chat.md "The input bar"): the search and the
-- kept lines. Pure: no WoW API. The text keys themselves are Core's (Bastians.TextKeys, ADR 0045).
local _, ns = ...

local Keys = {}
ns.Keys = Keys

Keys.HISTORY = 100 -- lines kept per character

-- The bar's own Ctrl keys beside Core's readline set: Ctrl+R searches the history, Ctrl+G leaves
-- the search with the text typed before it.
Keys.EXTRA = { R = "search", G = "cancel" }

-- The newest line of `history` (oldest first) before index `before` that holds `query` (any
-- case), as its index, or nil. `before` nil: from the newest.
function Keys.Search(history, query, before)
  query = (query or ""):lower()
  local i = math.min((before or (#history + 1)) - 1, #history)
  while i >= 1 do
    local line = history[i]
    if type(line) == "string" and (query == "" or line:lower():find(query, 1, true)) then
      return i
    end
    i = i - 1
  end
  return nil
end

-- A sent line into the history: no empty line, no repeat of the newest, at most Keys.HISTORY.
function Keys.Remember(history, line)
  if type(line) ~= "string" or not line:find("%S") or history[#history] == line then
    return history
  end
  history[#history + 1] = line
  while #history > Keys.HISTORY do
    table.remove(history, 1)
  end
  return history
end
