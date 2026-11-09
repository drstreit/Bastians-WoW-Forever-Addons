-- The flight bar (route.md "The flight bar", catalog review A4.1, 07.11.2026): while the character
-- flies a taxi, a small bar under the top of the screen names the flight and counts the time left
-- from the flight time Route measured on an earlier flight of the same pair (graph:Learned, the
-- direction flown only). Without a measured time it counts the time flown and fills nothing
-- (unknown is not zero). It ticks four times a second only while shown; the landing hides it.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style

local Flight = {}
ns.Flight = Flight

Flight.TICK = 0.25
Flight.WIDTH, Flight.HEIGHT = 240, 20

local mod, frame
local flight -- { from, to, startedAt, expected, label }
local byKey = false -- hidden by the clear-screen key
local sinceTick = 0

local function db()
  return mod.db.profile
end

-- "Stormwind" of "Stormwind, Elwynn": the master's place; the zone the flight map adds is noise here.
local function shortName(id)
  local d = B:GetService("data")
  local r = d and id and d:Get("flightpath", id)
  local name = r and r.name
  if not name then
    return nil
  end
  return name:match("^([^,]+)") or name
end

local function build()
  frame = CreateFrame("Frame", "BastiansRouteFlight", UIParent)
  frame:SetSize(Flight.WIDTH, Flight.HEIGHT)
  frame:SetFrameStrata("MEDIUM")
  frame:SetPoint("TOP", UIParent, "TOP", 0, -100) -- above the arrow's place (-140)
  S.panel(frame)
  frame.fill = S.fill(frame, S.C.accent, "BORDER")
  frame.fill:ClearAllPoints()
  frame.fill:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
  frame.fill:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
  frame.fill:SetWidth(1)
  frame.text = S.text(frame, 12, S.C.text, "OVERLAY")
  frame.text:SetPoint("CENTER")
  frame.text:SetJustifyH("CENTER")
  frame:Hide()
  Flight.frame = frame
end

local function refresh()
  if not (frame and flight) then
    return
  end
  local flown = GetTime() - flight.startedAt
  local words
  if flight.expected then
    local left = math.max(0, flight.expected - flown)
    words = string.format(L["%s left"], ns.Graph.FormatSeconds(left))
    local share = math.min(1, flown / flight.expected)
    frame.fill:SetWidth(math.max(1, (Flight.WIDTH - 2) * share))
    frame.fill:Show()
  else
    words = ns.Graph.FormatSeconds(flown) -- the time flown: no measured time, no bar to fill
    frame.fill:Hide()
  end
  frame.text:SetText(flight.label .. "   " .. words)
end

local function onUpdate(_, dt)
  sinceTick = sinceTick + dt
  if sinceTick >= Flight.TICK then
    sinceTick = 0
    refresh()
  end
end

local function update()
  local show = flight ~= nil and mod ~= nil and db().flightBar ~= false and mod:IsEnabled() and not byKey
  if show then
    if not frame then
      build()
    end
    refresh()
    sinceTick = 0
    frame:SetScript("OnUpdate", onUpdate)
    frame:Show()
  elseif frame then
    frame:SetScript("OnUpdate", nil)
    frame:Hide()
  end
end

-- Route's taxi hook: a flight begins. `f` = { from, to, startedAt } with flight master ids; a flight
-- whose ends Data does not know shows nothing.
function Flight.Begin(f)
  if not (f and f.from and f.to) then
    flight = nil
    update()
    return
  end
  local times = ns.Route.FlightTimes()
  flight = {
    from = f.from,
    to = f.to,
    startedAt = f.startedAt or GetTime(),
    expected = times[ns.Graph.FlightKey(f.from, f.to)],
    label = string.format(L["%s to %s"], shortName(f.from) or "?", shortName(f.to) or "?"),
  }
  update()
end

-- The real landing (a stop on a multi-hop flight keeps the bar).
function Flight.End()
  flight = nil
  update()
end

function Flight.Current()
  return flight
end

function Flight.IsShown()
  return frame ~= nil and frame:IsShown()
end

function Flight.HideByKey(hidden)
  byKey = hidden
  update()
end

function Flight.Register(self)
  mod = self
end

function Flight.Unregister()
  flight = nil
  update()
end
