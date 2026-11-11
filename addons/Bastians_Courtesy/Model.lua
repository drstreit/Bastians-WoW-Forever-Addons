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

Model.HEAVY = 0.5 -- weather of this intensity or more is heavy (the threshold is ours, assumed)
Model.LEVEL_GAP = 5 -- levels above or below the player that make someone "higher" or "lower"
Model.HURT = 0.5 -- below this share of health the player is hurt

-- The spells that have lines of their own, and where they sit in the tree of situations
-- ("buff." .. the value): the base ranks, read as the client's own names, so that every rank and
-- every language matches. The ids are those of the Forever client's SpellName table (clientdump,
-- 1.60.1.70790, read 11.11.2026; forever-api.md). That table has no Blessing of Salvation or
-- Sanctuary and no Greater Blessing of Light: their ids were dropped.
Model.BUFFS = {
  [1459] = "mind", -- Arcane Intellect
  [23028] = "mind", -- Arcane Brilliance
  [14752] = "mind", -- Divine Spirit
  [27681] = "mind", -- Prayer of Spirit
  [1243] = "stamina", -- Power Word: Fortitude
  [21562] = "stamina", -- Prayer of Fortitude
  [1126] = "nature", -- Mark of the Wild
  [21849] = "nature", -- Gift of the Wild
  [467] = "nature.thorns", -- Thorns
  [19740] = "blessing.might", -- Blessing of Might
  [25782] = "blessing.might", -- Greater Blessing of Might
  [19742] = "blessing.wisdom", -- Blessing of Wisdom
  [25894] = "blessing.wisdom", -- Greater Blessing of Wisdom
  [20217] = "blessing.kings", -- Blessing of Kings
  [25898] = "blessing.kings", -- Greater Blessing of Kings
  [26650] = "blessing", -- Blessing of Light
  [17] = "shield", -- Power Word: Shield
  [139] = "heal", -- Renew
  [774] = "heal", -- Rejuvenation
  [8936] = "heal", -- Regrowth
}

-- The kind of country of a zone, by its map (the client's UiMap table, clientdump 1.60.1.70862; the
-- kinds are ours). A zone we do not know has none: Riverglades, Mount Hyjal, Shen'dralas, Zephras
-- Isle and Azshara are left out on purpose, as is every map of the retail client.
Model.LANDS = {
  [1429] = "forest", -- Elwynn Forest
  [1431] = "forest", -- Duskwood
  [1421] = "forest", -- Silverpine Forest
  [1420] = "forest", -- Tirisfal Glades
  [1425] = "forest", -- The Hinterlands
  [1440] = "forest", -- Ashenvale
  [1439] = "forest", -- Darkshore
  [1448] = "forest", -- Felwood
  [1450] = "forest", -- Moonglade
  [1438] = "forest", -- Teldrassil
  [1434] = "jungle", -- Stranglethorn Vale
  [1444] = "jungle", -- Feralas
  [1449] = "jungle", -- Un'Goro Crater
  [1435] = "swamp", -- Swamp of Sorrows
  [1437] = "swamp", -- Wetlands
  [1445] = "swamp", -- Dustwallow Marsh
  [1417] = "plains", -- Arathi Highlands
  [1424] = "plains", -- Hillsbrad Foothills
  [1436] = "plains", -- Westfall
  [1412] = "plains", -- Mulgore
  [1413] = "plains", -- The Barrens
  [1418] = "desert", -- Badlands
  [1411] = "desert", -- Durotar
  [1451] = "desert", -- Silithus
  [1446] = "desert", -- Tanaris
  [1441] = "desert", -- Thousand Needles
  [1432] = "mountains", -- Loch Modan
  [1433] = "mountains", -- Redridge Mountains
  [1442] = "mountains", -- Stonetalon Mountains
  [1416] = "frost", -- Alterac Mountains
  [1426] = "frost", -- Dun Morogh
  [1452] = "frost", -- Winterspring
  [1419] = "waste", -- Blasted Lands
  [1428] = "waste", -- Burning Steppes
  [1430] = "waste", -- Deadwind Pass
  [1423] = "waste", -- Eastern Plaguelands
  [1422] = "waste", -- Western Plaguelands
  [1427] = "waste", -- Searing Gorge
  [1443] = "waste", -- Desolace
  [1455] = "city", -- Ironforge
  [1453] = "city", -- Stormwind City
  [1458] = "city", -- Undercity
  [1457] = "city", -- Darnassus
  [1454] = "city", -- Orgrimmar
  [1456] = "city", -- Thunder Bluff
}

-- Words of the game's English emote lines that are not friendly.
Model.RUDE = { "rude", "spit", "insult", "taunt", "threaten", "chicken", "laughs at", "mock", "growl" }

-- What a friendly emote was, by words of the game's English lines (their wording assumed on Forever):
-- the first kind with a word in the line; none is a plain "emote.friendly" (a wave, a smile, a dance).
Model.FRIENDLY = {
  { "thank", { "thanks you" } },
  { "love", { "hugs you", "a kiss", "kisses you", "loves you", "cuddles", "flirts with you" } },
  { "bow", { "bows", "salutes you", "curtsies", "curtseys", "kneels" } },
  { "cheer", { "cheers at you", "applauds", "claps", "congratulates you", "commends you" } },
}

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

-- What a friendly emote line was: "thank", "love", "bow", "cheer", or nil for any other.
function Model.FriendlyKind(text)
  local lower = string.lower(text or "")
  for _, kind in ipairs(Model.FRIENDLY) do
    for _, word in ipairs(kind[2]) do
      if string.find(lower, word, 1, true) then
        return kind[1]
      end
    end
  end
  return nil
end

-- Whether the weather is heavy: nil when there is none to speak of or the client gives no intensity.
function Model.Heavy(weather, intensity)
  if weather == nil or weather == "clear" or type(intensity) ~= "number" then
    return nil
  end
  return intensity >= Model.HEAVY
end

-- "higher", "lower" or "peer" for the other person's level against the player's; nil when either is
-- unknown (the client says 0 or less for a level it does not give).
function Model.LevelGap(theirs, mine)
  if type(theirs) ~= "number" or type(mine) ~= "number" or theirs <= 0 or mine <= 0 then
    return nil
  elseif theirs - mine >= Model.LEVEL_GAP then
    return "higher"
  elseif mine - theirs >= Model.LEVEL_GAP then
    return "lower"
  end
  return "peer"
end

-- Whether the player is hurt; nil when the client hides the health or the player is dead.
function Model.Hurt(health, max)
  if type(health) ~= "number" or type(max) ~= "number" or max <= 0 or health <= 0 then
    return nil
  end
  return health / max < Model.HURT
end

-- The situation of the lines for `event`, nil when no line can have it (a declined trade).
-- `kindOf(spell name)` -> the spell's place under "buff" ("mind", "blessing.might", ...) or nil.
function Model.Situation(event, kindOf)
  local kind = event.kind
  if kind == "buff" then
    local of = kindOf and kindOf(event.what) or nil
    return of and ("buff." .. of) or "buff"
  elseif kind == "rez" or kind == "camp" then
    return kind
  elseif kind == "emote" then
    if Model.IsRude(event.text) then
      return "emote.rude"
    end
    local of = Model.FriendlyKind(event.text)
    return of and ("emote.friendly." .. of) or "emote.friendly"
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
