-- Bastian's Route: the departures of boats and zeppelins (route.md "Departure times", R26.6). A
-- vessel's loop and the moments it leaves each stop come with the data (NauticusClassic's
-- measurements); when it leaves is learned the first time the character rides it (the start of the
-- loop in server time), shared with the group and the guild, and then every departure is known.
local _, ns = ...
local B = Bastians
local L = ns.L
local Graph = ns.Graph

local Ferries = {}
ns.Ferries = Ferries

Ferries.DOCK_YARDS = 40 -- the character waits at the stop this close
Ferries.CARRIED_YARDS = 3 -- moved this much in a tick while standing: on a moving vessel
Ferries.KIND = "route.ferry" -- the Comm kind of a learned loop
Ferries.RIDES = { boat = true, zeppelin = true }

local mod
local atDock -- { transport, stop, since } while the character waits at a stop of its ride

local function db()
  return mod.db.global
end

local function data()
  return B:GetService("data")
end

local function graph()
  return B:GetService("graph")
end

function Ferries.Now()
  return B.Compat.ServerTime()
end

-- The transport record when it has a loop and departures, else nil.
function Ferries.Record(id)
  local d = data()
  local t = d and id and d:Get("transport", tonumber(id) or id)
  return t and t.cycle and t.departs and t or nil
end

-- The learned start of a transport's loop (server seconds) and when it was learned, or nil.
function Ferries.Phase(id)
  local f = db().ferries and db().ferries[id]
  return f and f.cycle0, f and f.at
end

-- Seconds from `at` (server seconds, default now) until the transport leaves its stop `stop`; nil
-- while its loop is not known.
function Ferries.NextDeparture(id, stop, at)
  local t = Ferries.Record(id)
  local cycle0 = Ferries.Phase(id)
  if not (t and cycle0 and t.departs[stop]) then
    return nil
  end
  at = at or Ferries.Now()
  return (cycle0 + t.departs[stop] - at) % t.cycle
end

-- Keeps a loop's start when it is newer than the one known; -> true when kept.
function Ferries.Learn(id, cycle0, at)
  if not (Ferries.Record(id) and type(cycle0) == "number" and type(at) == "number") then
    return false
  end
  db().ferries = db().ferries or {}
  local known = db().ferries[id]
  if known and known.at >= at then
    return false
  end
  db().ferries[id] = { cycle0 = cycle0, at = at }
  return true
end

-- Tells the group and the guild what was learned (nothing to send alone and guildless).
function Ferries.Share(id)
  local cycle0, at = Ferries.Phase(id)
  if not cycle0 then
    return 0
  end
  local value = { v = 1, id = tostring(id), cycle0 = cycle0, at = at }
  local sent = 0
  local group = B.Compat.GroupChannel()
  if group and B.Comm.Send(Ferries.KIND, value, group) then
    sent = sent + 1
  end
  if B.Compat.InGuild() and B.Comm.Send(Ferries.KIND, value, "GUILD") then
    sent = sent + 1
  end
  return sent
end

-- A shared loop: checked, kept when newer and not from the future.
function Ferries.Receive(value)
  if type(value) ~= "table" or value.v ~= 1 or type(value.id) ~= "string" then
    return false
  end
  local now = Ferries.Now()
  if type(value.at) ~= "number" or value.at > now + 60 or value.at < now - 14 * 86400 then
    return false
  end
  return Ferries.Learn(value.id, value.cycle0, value.at)
end

-- The route's 1-second tick while its step is a boat or a zeppelin. Waiting at its stop, then
-- carried: standing (no speed of its own, not mounted) while the position moves more than
-- CARRIED_YARDS in a tick; that moment is the departure. Assumed 26.10.2026 (as NauticusClassic
-- does): the client answers no speed while the character stands on a moving vessel; to verify in
-- game (forever-api.md). The wait from reaching the dock to the departure is learned into the
-- graph (W11: it rides along in the captures, where the build checks it against the loop).
local last -- the position at the last tick { continent, wx, wy }
function Ferries.Observe(step, pos)
  local from = step.from
  local id, stop = from and from.transport, from and from.stop
  local moved = last and last.continent == pos.continent and Graph.Distance(pos.wx, pos.wy, last.wx, last.wy)
    or 0
  last = { continent = pos.continent, wx = pos.wx, wy = pos.wy }
  if not (Ferries.RIDES[step.mode] and id and stop and Ferries.Record(id)) then
    atDock = nil
    return nil
  end
  local speed, mounted = B.Compat.GetMoveSpeed()
  local carried = speed == 0 and not mounted and moved > Ferries.CARRIED_YARDS
  local near = from.continent == pos.continent
    and Graph.Distance(pos.wx, pos.wy, from.wx, from.wy) <= Ferries.DOCK_YARDS
  if near and not carried then
    if not (atDock and atDock.transport == id and atDock.stop == stop) then
      atDock = { transport = id, stop = stop, since = Ferries.Now() }
    end
    return nil
  end
  if not (carried and atDock and atDock.transport == id) then
    return nil
  end
  local t = Ferries.Record(id)
  local now = Ferries.Now()
  local waited, g = now - (atDock.since or now), graph()
  atDock = nil
  if g and waited > 0 and waited <= t.cycle then
    g:Learn({ kind = "ride", ref = "transport:" .. id, wait = waited })
  end
  if Ferries.Learn(id, now - t.departs[stop], now) then
    B:Say(L["Learned when %s leaves; shared with your group and guild."], t.name or tostring(id))
    Ferries.Share(id)
  end
  return id
end

-- After planning: a boat or zeppelin step whose loop is known waits exactly until its departure
-- from the moment the character reaches the stop (the steps before it); the route's time follows.
function Ferries.Adjust(route)
  if not (route and route.steps) then
    return route
  end
  local clock = Ferries.Now()
  local total = 0
  for _, step in ipairs(route.steps) do
    local from = step.from or {}
    local wait = Ferries.RIDES[step.mode] and Ferries.NextDeparture(from.transport, from.stop, clock)
    if wait then
      local ride = (step.seconds or 0) - (step.wait or 0)
      step.wait, step.seconds, step.exactWait = wait, ride + wait, true
    end
    clock = clock + (step.seconds or 0)
    total = total + (step.seconds or 0)
  end
  route.seconds = total
  return route
end

-- /broute ferries: every transport with departures, the next one from each stop.
function Ferries.Report()
  local d = data()
  local shown = 0
  for _, id in ipairs(d and d:Each("transport") or {}) do
    local t = Ferries.Record(id)
    if t then
      shown = shown + 1
      local parts = {}
      for stop, s in ipairs(t.stops) do
        local next = Ferries.NextDeparture(id, stop)
        parts[#parts + 1] = string.format("%s %s", s[4], next and Graph.FormatSeconds(next) or L["unknown"])
      end
      B:Say("%s: %s", t.name or tostring(id), table.concat(parts, ", "))
    end
  end
  if shown == 0 then
    B:Say(L["No boat or zeppelin with departures in the data."])
  end
end

function Ferries.Register(module)
  mod = module
  B.Comm.Register(module, Ferries.KIND, function(value)
    Ferries.Receive(value)
  end)
end

ns.mod.Ferries = Ferries -- for the tests and /bastians debug
