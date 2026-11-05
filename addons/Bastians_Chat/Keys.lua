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

-- Up (dir -1) and Down (dir 1) over `history` (oldest first) as a shell walks it. `state` is the
-- walk so far ({ index, draft, shown }) or nil before the first Up; `current` the bar's text now.
-- Returns the text to show (nil: nothing to do) and the new state (nil once the walk is left on
-- the draft). A text edited since the last step starts a new walk from the newest line, with the
-- edited text as the draft that Down past the newest brings back.
function Keys.Walk(history, state, dir, current)
  if #history == 0 then
    return nil, nil
  end
  current = current or ""
  if state and state.shown ~= current then
    state = nil
  end
  if not state then
    if dir > 0 then
      return nil, nil
    end
    state = { index = #history + 1, draft = current }
  end
  local i = state.index + dir
  if i < 1 then
    return nil, state -- the oldest line is shown already
  end
  if i > #history then
    return state.draft, nil
  end
  state.index, state.shown = i, history[i]
  return history[i], state
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
