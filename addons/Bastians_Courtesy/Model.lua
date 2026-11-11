-- Courtesy's pure logic (courtesy.md): whether a moment is answered, which situation it is. Plain
-- tables in, plain tables out.
local _, ns = ...

local Model = {}
ns.Model = Model

Model.COURTESY_SECONDS = 600 -- one answer per person in ten minutes
Model.ACCEPT_SECONDS = 120 -- how long after an invite a joined group still counts as that invite
Model.REFRESH_SECONDS = 5 -- an aura whose end moves this much later was cast again
Model.SETTLE_SECONDS = 5 -- after a login or a loading screen every aura only arrives
Model.AFTER_FIGHT_SECONDS = 60 -- unread for longer (a fight): a buff must say when it landed
Model.LATE_SECONDS = 300 -- then it still gets its ring when it landed this lately

-- The spells that have lines of their own: the base ranks, read as the client's own names, so that
-- every rank and every language matches (ids assumed on Forever, forever-api.md).
Model.BUFFS = {
  [1459] = "mind", -- Arcane Intellect
  [23028] = "mind", -- Arcane Brilliance
  [14752] = "mind", -- Divine Spirit
  [27681] = "mind", -- Prayer of Spirit
  [1243] = "stamina", -- Power Word: Fortitude
  [21562] = "stamina", -- Prayer of Fortitude
  [1126] = "nature", -- Mark of the Wild
  [21849] = "nature", -- Gift of the Wild
  [467] = "nature", -- Thorns
  [19740] = "blessing", -- Might
  [19742] = "blessing", -- Wisdom
  [20217] = "blessing", -- Kings
  [1038] = "blessing", -- Salvation
  [19977] = "blessing", -- Light
  [20911] = "blessing", -- Sanctuary
  [25782] = "blessing", -- Greater Might
  [25894] = "blessing", -- Greater Wisdom
  [25898] = "blessing", -- Greater Kings
  [25890] = "blessing", -- Greater Light
  [25899] = "blessing", -- Greater Sanctuary
}

-- Words of the game's English emote lines that are not friendly.
Model.RUDE = { "rude", "spit", "insult", "taunt", "threaten", "chicken", "laughs at", "mock", "growl" }

-- The time of day's key from the game clock's hour; nil when the hour is unknown.
function Model.DayKey(hour)
  hour = tonumber(hour)
  if not hour then
    return nil
  end
  if hour >= 5 and hour < 12 then
    return "morning"
  elseif hour >= 12 and hour < 17 then
    return "afternoon"
  elseif hour >= 17 and hour < 21 then
    return "evening"
  end
  return "night"
end

function Model.IsRude(text)
  local lower = string.lower(text or "")
  for _, word in ipairs(Model.RUDE) do
    if string.find(lower, word, 1, true) then
      return true
    end
  end
  return false
end

-- The situation of the lines for `event`, nil when no line can have it (a declined trade).
-- `kindOf(spell name)` -> "mind", "stamina", "nature", "blessing" or nil.
function Model.Situation(event, kindOf)
  local kind = event.kind
  if kind == "buff" then
    local of = kindOf and kindOf(event.what) or nil
    return of and ("buff." .. of) or "buff"
  elseif kind == "rez" or kind == "camp" then
    return kind
  elseif kind == "emote" then
    return Model.IsRude(event.text) and "emote.rude" or "emote.friendly"
  elseif kind == "accepted" then
    return "invite.accepted"
  elseif kind == "duel" or kind == "invite" then
    return kind .. ".declined"
  end
  return nil
end

-- Why `event` is not answered, nil when it is: "off", "combat", "instance", "answered lately".
function Model.Refusal(event, state, now, settings)
  settings = settings or {}
  local key = event and (event.key or event.who)
  if not key or settings.mode == "off" or settings.mode == nil then
    return "off"
  elseif settings.inCombat then
    return "combat"
  elseif settings.inInstance and not settings.instances then
    return "instance"
  end
  local last = state.seen and state.seen[key]
  if last and not event.again and now - last < Model.COURTESY_SECONDS then
    return "answered lately"
  end
  return nil
end

-- The decision for `event` ({ kind, who, key, again }) with `state` ({ seen = { [key or who] = time } })
-- at `now` under `settings` ({ mode = "ask" | "auto" | "off", instances, inInstance, inCombat }): "ask",
-- "auto" or nil; an answer is noted in `state.seen`. `key`: what counts as the same person when the
-- name is unknown. `again`: the follow-up of a moment already counted.
function Model.Courtesy(event, state, now, settings)
  if Model.Refusal(event, state, now, settings) then
    return nil
  end
  state.seen = state.seen or {}
  state.seen[event.key or event.who] = now
  return settings.mode == "auto" and "auto" or "ask"
end

-- Forgets the people answered more than COURTESY_SECONDS ago (nothing of them is kept).
function Model.Forget(state, now)
  for who, t in pairs(state.seen or {}) do
    if now - t >= Model.COURTESY_SECONDS then
      state.seen[who] = nil
    end
  end
end

-- Whether an emote line is aimed at the player: the game writes "X waves at you." for those. The
-- player's own begin with "You" ("You wave at X."; the ring opened on the
-- player's own gestures).
function Model.AimedAtMe(text)
  text = " " .. string.lower(text or "") .. " "
  if string.find(text, "^ you[r ]") then
    return false
  end
  return string.find(text, " you[ .,!]", 1) ~= nil or string.find(text, " your ", 1, true) ~= nil
end

-- Whether a buff just read still gets its ring. The auras were unread for `blind` seconds before
-- (a fight, hidden auras; nil: read all along). After up to AFTER_FIGHT_SECONDS every new one is
-- that fresh; after longer only one the aura dates (`landed`, on the clock of `now`) to
-- LATE_SECONDS ago at most. Unknown is not "just now".
function Model.Timely(landed, now, blind)
  if type(blind) ~= "number" or blind <= Model.AFTER_FIGHT_SECONDS then
    return true
  end
  return type(landed) == "number" and now - landed <= Model.LATE_SECONDS
end

-- A reading of the auras as `{ [key] = end or true }` for the next comparison.
function Model.Reading(list)
  local out = {}
  for _, a in ipairs(list or {}) do
    out[a.key] = a.ends
  end
  return out
end

-- The auras of `list` that someone has just cast: not in the last reading `before`, or with an end
-- that moved later. Nothing without a last reading.
function Model.NewAuras(before, list)
  local out = {}
  if not before then
    return out
  end
  for _, a in ipairs(list or {}) do
    local was = before[a.key]
    local later = type(was) == "number" and type(a.ends) == "number" and a.ends > was + Model.REFRESH_SECONDS
    if was == nil or later then
      out[#out + 1] = a
    end
  end
  return out
end
