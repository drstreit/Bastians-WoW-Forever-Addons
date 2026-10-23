-- Creates the one global `Bastians`, its versions and the client identity (core-contracts §1, ADR 0010).
local ADDON, ns = ...

Bastians = Bastians or {}
local B = Bastians
ns.B = B

B.API_VERSION = 1
B.VERSION = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "dev"

-- Bastians.Client is read only by Compat and the Data loader; apps never branch on it (ADR 0010).
local _, build, _, interface = GetBuildInfo()
B.Build = tostring(build)
B.Interface = interface
if interface == 16001 then
  B.Client = "forever"
elseif type(interface) == "number" and interface >= 100000 then
  B.Client = "retail"
else
  B.Client = "unknown"
end

-- Private helpers shared by Core's own files.
ns.ADDON = ADDON
ns.modules = {} -- name -> module
ns.moduleList = {} -- modules in registration order
ns.byAddon = {} -- addon folder name -> list of modules

-- Deferred registrations (core-contracts "Generated files"): a generated file never calls into a
-- module directly, because the client may run it before its consumer exists (Forever beta
-- 1.60.1.70450, 20.10.2026: remembered load-on-demand addons ran at startup before their
-- dependencies, and a runtime LoadAddOn ran nothing until the next reload). The file appends
-- { "Data.RegisterPack", arg, ... } to Bastians.deferred; Deliver() calls every entry whose target
-- function exists now and keeps the rest. Core runs it on every ADDON_LOADED and after LoadAddOn.
B.deferred = B.deferred or {}

local function resolve(path)
  local target = B
  for part in string.gmatch(path, "[^%.]+") do
    target = target[part]
    if target == nil then
      return nil
    end
  end
  return type(target) == "function" and target or nil
end

function B.Deliver()
  local queue = B.deferred
  if #queue == 0 then
    return 0
  end
  local kept, delivered = {}, 0
  B.deferred = kept
  for _, entry in ipairs(queue) do
    local fn = type(entry) == "table" and type(entry[1]) == "string" and resolve(entry[1])
    if fn then
      fn(unpack(entry, 2))
      delivered = delivered + 1
    elseif type(entry) == "table" then
      kept[#kept + 1] = entry
    end
  end
  return delivered
end
