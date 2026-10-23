-- Compat layer "forever": where Forever deviates from the retail family (forever-api.md, verified facts).
local _, ns = ...
local B = ns.B
local define, note = ns.Compat.define, ns.Compat.note

if B.Client ~= "forever" then
  return
end

-- Verified 17.10.2026 (AHSync): a number throws "Missing on/off parameter"; the filter wants a boolean.
define("forever", "SetTrainerFilter", function(kind, on)
  note("SetTrainerFilter", "boolean")
  SetTrainerServiceTypeFilter(kind, on and true or false)
end)

-- Verified AHSyncCapture 0.5.2: GetTrainerServiceInfo returns name, type, icon (Classic: name, rank, type).
define("forever", "GetTrainerService", function(index)
  local name, kind, icon = GetTrainerServiceInfo(index)
  if not name then
    return nil
  end
  return ns.Compat.trainerCommon(index, { index = index, name = name, kind = kind, icon = icon })
end)
