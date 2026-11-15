-- Bastian's Chat, the fight's recap (plan-chat-two-decks.md §3, V42; the owner's Q2: "a as
-- summary"): when a fight ends, one line in the stream "fight" with what the client's own meter
-- knows of it (C_DamageMeter: the current session's duration and the player's own row per type).
-- A value that is missing or secret is left out, never shown as 0; without the meter the line
-- holds the duration alone, by our own clock. What the meter answers is assumed (probe X18).
local _, ns = ...
local L = ns.L
local Compat = ns.Compat

local Fights = {}
ns.Fights = Fights

Fights.SETTLE = 2 -- seconds after the fight before the meter is read (its numbers may still be secret)
Fights.MIN_SECS = 3 -- a shorter fight leaves no line
-- the meter's types read, and the recap's part each one fills
Fights.TYPES = { DamageDone = "done", DamageTaken = "taken", HealingDone = "healing", Deaths = "deaths" }

local began -- GetTime() at the fight's start
local count = 0 -- the session's fights with a line

-- 12400 -> "12,400".
function Fights.Number(n)
  local s = tostring(math.floor(n + 0.5))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end

-- 102 -> "1:42".
function Fights.Clock(secs)
  secs = math.floor(secs + 0.5)
  return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end

-- Pure: the recap's words. facts = { secs, done, taken, healing, deaths }, each a number or nil.
function Fights.Text(facts)
  local parts = {}
  if type(facts.done) == "number" and facts.done > 0 then
    parts[#parts + 1] = L["%s damage done"]:format(Fights.Number(facts.done))
  end
  if type(facts.taken) == "number" and facts.taken > 0 then
    parts[#parts + 1] = L["%s taken"]:format(Fights.Number(facts.taken))
  end
  if type(facts.healing) == "number" and facts.healing > 0 then
    parts[#parts + 1] = L["%s healing"]:format(Fights.Number(facts.healing))
  end
  if type(facts.deaths) == "number" and facts.deaths > 0 then
    parts[#parts + 1] = facts.deaths == 1 and L["1 death"] or L["%d deaths"]:format(facts.deaths)
  end
  local head = facts.secs and L["Fight, %s"]:format(Fights.Clock(facts.secs)) or L["Fight"]
  if #parts == 0 then
    return head
  end
  return head .. ": " .. table.concat(parts, ", ")
end

-- A plain number of the client's, nil for a secret or anything else.
local function number(v)
  v = Compat.Plain(v)
  return type(v) == "number" and v or nil
end

-- What the client's meter knows of the current session: { secs, done, taken, healing, deaths },
-- each nil when it is not there or not readable. Never raises.
function Fights.Read()
  local facts = {}
  local api = rawget(_G, "C_DamageMeter")
  local enum = rawget(_G, "Enum")
  if type(api) ~= "table" or type(enum) ~= "table" then
    return facts
  end
  local sessions, kinds = enum.DamageMeterSessionType, enum.DamageMeterType
  local current = type(sessions) == "table" and sessions.Current or nil
  if current == nil or type(kinds) ~= "table" then
    return facts
  end
  if type(api.IsDamageMeterAvailable) == "function" then
    local ok, on = pcall(api.IsDamageMeterAvailable)
    if not ok or Compat.Plain(on) == false then
      return facts
    end
  end
  if type(api.GetSessionDurationSeconds) == "function" then
    local ok, secs = pcall(api.GetSessionDurationSeconds, current)
    facts.secs = ok and number(secs) or nil
  end
  if type(api.GetCombatSessionFromType) ~= "function" then
    return facts
  end
  for name, part in pairs(Fights.TYPES) do
    local id = kinds[name]
    if id ~= nil then
      -- the whole read inside the pcall: a secret among the fields raises when it is touched
      local ok, amount = pcall(function()
        local session = api.GetCombatSessionFromType(current, id)
        for _, source in ipairs(session.combatSources) do
          if source.isLocalPlayer == true then
            return number(source.totalAmount)
          end
        end
        return nil
      end)
      facts[part] = ok and amount or nil
    end
  end
  return facts
end

-- The recap's record into the store; returns it.
function Fights.Add(facts, now)
  local text = Fights.Text(facts)
  count = count + 1
  return ns.Chat.Store():Add({
    t = now or time(),
    chatType = "SYSTEM",
    stream = "fight",
    tier = 2,
    text = text,
    body = text,
    plain = text:lower(),
    links = {},
    fight = facts,
    keep = false,
  })
end

function Fights.Count()
  return count
end

function Fights.Start()
  began = GetTime()
end

-- The fight is over: its line once the meter had its moment.
function Fights.Stop()
  local started = began
  began = nil
  if not started then
    return
  end
  local ours = GetTime() - started
  if ours < Fights.MIN_SECS then
    return
  end
  C_Timer.After(Fights.SETTLE, function()
    local facts = Fights.Read()
    facts.secs = facts.secs and facts.secs > 0 and facts.secs or ours
    Fights.Add(facts)
  end)
end
