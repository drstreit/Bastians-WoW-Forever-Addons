-- Performance meter (core-contracts §15): CPU per module in its callbacks, memory per addon, snapshots.
local _, ns = ...
local B = ns.B
local L = ns.L

local Perf = { enabled = true, modules = {}, loadedAt = GetTime() }
B.Perf = Perf

local MAX_SNAPSHOTS = 20

-- Wrap ns.safecall so every callback into a module is timed (debugprofilestop is cheap).
-- Adds one timed call to a module and to the handler's label (Core's ns.label; "other" without).
function Perf.Record(owner, text, elapsed)
  local name = type(owner) == "table" and owner.name or "?"
  local stat = Perf.modules[name]
  if not stat then
    stat = { calls = 0, ms = 0, maxMs = 0, top = {} }
    Perf.modules[name] = stat
  end
  stat.calls = stat.calls + 1
  stat.ms = stat.ms + elapsed
  if elapsed > stat.maxMs then
    stat.maxMs = elapsed
  end
  local key = text or "other"
  local t = stat.top[key]
  if not t then
    t = { calls = 0, ms = 0, maxMs = 0 }
    stat.top[key] = t
  end
  t.calls = t.calls + 1
  t.ms = t.ms + elapsed
  if elapsed > t.maxMs then
    t.maxMs = elapsed
  end
end

local safecall = ns.safecall
function ns.safecall(owner, fn, ...)
  if not Perf.enabled or type(owner) ~= "table" then
    return safecall(owner, fn, ...)
  end
  local start = debugprofilestop()
  local ok, a, b, c, d = safecall(owner, fn, ...)
  Perf.Record(owner, ns.perfLabels[fn], debugprofilestop() - start)
  return ok, a, b, c, d
end

-- The costliest handlers of a module stat: up to `n` { label, calls, ms, maxMs }, by time.
function Perf.Top(stat, n)
  local list = {}
  for text, t in pairs(stat.top or {}) do
    list[#list + 1] = { label = text, calls = t.calls, ms = t.ms, maxMs = t.maxMs }
  end
  table.sort(list, function(a, b)
    return a.ms > b.ms
  end)
  for i = #list, (n or 3) + 1, -1 do
    list[i] = nil
  end
  return list
end

function Perf.Reset()
  for k in pairs(Perf.modules) do
    Perf.modules[k] = nil
  end
end

-- Memory of every Bastians_* addon in KB (UpdateAddOnMemoryUsage is documented on both clients).
function Perf.Memory()
  -- the client counts garbage not yet collected as an addon's memory: after 33 minutes of play
  -- the owner's snapshot showed 80 MB without packs (R10, 22.10.2026); a full collect first makes
  -- the figure the live memory, which is what the budgets mean
  collectgarbage("collect")
  UpdateAddOnMemoryUsage()
  local out = {}
  for i = 1, C_AddOns.GetNumAddOns() do
    local name = C_AddOns.GetAddOnInfo(i)
    if name and string.find(name, "^Bastians_") and (C_AddOns.IsAddOnLoaded(name)) then
      out[name] = GetAddOnMemoryUsage(i)
    end
  end
  return out
end

-- A snapshot: { time, build, client, modules = { name = { calls, ms, maxMs } }, memoryKB = { addon = KB } }
function Perf.Snapshot()
  local modules = {}
  for name, s in pairs(Perf.modules) do
    modules[name] = { calls = s.calls, ms = s.ms, maxMs = s.maxMs, top = Perf.Top(s, 3) }
  end
  local snap = {
    time = GetServerTime(),
    build = B.Build,
    client = B.Client,
    uptime = GetTime() - Perf.loadedAt, -- GetTime() alone is the system uptime (seen 20.10.2026: 225222 s)
    modules = modules,
    memoryKB = Perf.Memory(),
  }
  if ns.core and ns.core.db then
    local list = ns.core.db.global.perf
    if type(list) ~= "table" then
      list = {}
      ns.core.db.global.perf = list
    end
    list[#list + 1] = snap
    while #list > MAX_SNAPSHOTS do
      table.remove(list, 1)
    end
  end
  return snap
end

-- /bastians perf: the table to chat, and a snapshot into Core's saved variables for tools/perf_report.py.
function Perf.Print()
  local snap = Perf.Snapshot()
  local names = {}
  for name in pairs(snap.modules) do
    names[#names + 1] = name
  end
  table.sort(names, function(a, b)
    return snap.modules[a].ms > snap.modules[b].ms
  end)
  B:Say(L["Performance since login (%.0f s), snapshot saved"], snap.uptime)
  for _, name in ipairs(names) do
    local s = snap.modules[name]
    DEFAULT_CHAT_FRAME:AddMessage(
      ("  %-16s %6d calls %8.1f ms  max %.2f ms"):format(name, s.calls, s.ms, s.maxMs)
    )
    for _, t in ipairs(s.top or {}) do -- what the time went into (23.10.2026)
      DEFAULT_CHAT_FRAME:AddMessage(
        ("      %-30s %6d calls %8.1f ms  max %.2f ms"):format(t.label, t.calls, t.ms, t.maxMs)
      )
    end
  end
  local addons = {}
  for name in pairs(snap.memoryKB) do
    addons[#addons + 1] = name
  end
  table.sort(addons)
  for _, name in ipairs(addons) do
    DEFAULT_CHAT_FRAME:AddMessage(("  %-28s %8.0f KB"):format(name, snap.memoryKB[name]))
  end
end
