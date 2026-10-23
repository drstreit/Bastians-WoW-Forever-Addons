-- Saved variables and profiles (core-contracts §9): defaults by metatable, never copied into the file.
local _, ns = ...
local B = ns.B

local DB = {}
ns.DB = DB

local SCHEMA_KEY = "__schema"
local DEFAULT_PROFILE = "Default"
local SCOPES = { "profile", "char", "global" }

local function charKey()
  return (UnitName("player") or "?") .. " - " .. (GetRealmName() or "?")
end

-- Defaults are reached through __index; sub-tables of the defaults exist as real tables so that
-- `db.profile.colors.accent = x` works, and empty ones disappear again when the file is pruned.
local function applyDefaults(target, defaults)
  for key, value in pairs(defaults) do
    if type(value) == "table" then
      if type(rawget(target, key)) ~= "table" then
        rawset(target, key, {})
      end
      applyDefaults(rawget(target, key), value)
    end
  end
  setmetatable(target, {
    __index = function(_, key)
      local d = defaults[key]
      if type(d) ~= "table" then
        return d
      end
    end,
  })
end

-- Remove values equal to their default and empty tables, so the saved file holds only real changes.
local function prune(target, defaults)
  for key, value in pairs(target) do
    local d = defaults and defaults[key]
    if type(value) == "table" then
      prune(value, type(d) == "table" and d or nil)
      if next(value) == nil then
        rawset(target, key, nil)
      end
    elseif d ~= nil and value == d then
      rawset(target, key, nil)
    end
  end
end

local function mergedDefaults(mod)
  local given = mod.defaults or {}
  local out = { profile = {}, char = {}, global = {} }
  for _, scope in ipairs(SCOPES) do
    for k, v in pairs(given[scope] or {}) do
      out[scope][k] = v
    end
  end
  out.profile.enabled = true -- the module switch (core-contracts §2)
  return out
end

-- ---------------------------------------------------------------------------------------------
-- Core's own saved variables: the suite-wide profile selection per character
-- ---------------------------------------------------------------------------------------------

function DB.InitCore()
  BastiansCoreDB = type(BastiansCoreDB) == "table" and BastiansCoreDB or {}
  BastiansCoreDB.profileKeys = BastiansCoreDB.profileKeys or {} -- suite-wide, not per profile
  DB.ready = true -- Core's own settings live in its module ("Core", Settings.lua) like any other
end

function DB.CurrentProfile()
  if not DB.ready then
    DB.InitCore()
  end
  local keys = rawget(BastiansCoreDB, "profileKeys") -- may have been pruned at logout or SetProfile
  return keys and keys[charKey()] or DEFAULT_PROFILE
end

-- ---------------------------------------------------------------------------------------------
-- Attaching a module to its saved variables
-- ---------------------------------------------------------------------------------------------

local function ensure(tbl, key)
  local v = rawget(tbl, key)
  if type(v) ~= "table" then
    v = {}
    rawset(tbl, key, v)
  end
  return v
end

local function runMigrations(mod, sv, db)
  local migrations = mod.migrations
  local latest = 0
  if migrations then
    for n in pairs(migrations) do
      latest = math.max(latest, n)
    end
  end
  if latest == 0 then
    return -- no migrations declared: nothing to track yet
  end
  local stored = sv[SCHEMA_KEY]
  if stored == nil then
    local fresh = next(sv.global) == nil and next(sv.profiles[DB.CurrentProfile()]) == nil
    stored = fresh and latest or 1
  end
  for n = stored + 1, latest do
    if migrations[n] then
      local ok = ns.safecall(mod, migrations[n], db, n)
      if not ok then
        B:Log(mod, "error", "migration %d failed; stopping at schema %d", n, n - 1)
        sv[SCHEMA_KEY] = n - 1
        return
      end
    end
  end
  sv[SCHEMA_KEY] = latest
end

local function attachProfile(mod)
  local db = mod.db
  local defaults = mod.mergedDefaults
  if mod.parent then
    local parentDB = mod.parent.db
    db.profile = ensure(ensure(parentDB.profile, "modules"), mod.shortName)
  else
    local profile = DB.CurrentProfile()
    db.profileName = profile
    db.profile = ensure(ensure(db.sv, "profiles"), profile)
  end
  applyDefaults(db.profile, defaults.profile)
  for _, child in ipairs(mod.children) do
    if child.db then
      attachProfile(child)
    end
  end
end

function DB.Attach(mod)
  mod.mergedDefaults = mergedDefaults(mod)
  local db = {}
  mod.db = db
  if mod.parent then
    local parentDB = mod.parent.db
    db.char = ensure(ensure(parentDB.char, "modules"), mod.shortName)
    db.global = ensure(ensure(parentDB.global, "modules"), mod.shortName)
  else
    local svName = mod.def.db or ("Bastians" .. mod.shortName .. "DB")
    local charName = mod.def.charDb or ("Bastians" .. mod.shortName .. "CharDB")
    local sv = _G[svName]
    if type(sv) ~= "table" then
      sv = {}
      _G[svName] = sv
    end
    sv.profiles = sv.profiles or {}
    sv.global = sv.global or {}
    local charSv = _G[charName]
    if type(charSv) ~= "table" then
      charSv = {}
      _G[charName] = charSv
    end
    ensure(sv.profiles, DB.CurrentProfile())
    db.sv, db.svName, db.charName = sv, svName, charName
    db.char, db.global = charSv, sv.global
    runMigrations(mod, sv, { profile = sv.profiles[DB.CurrentProfile()], char = charSv, global = sv.global })
  end
  applyDefaults(db.char, mod.mergedDefaults.char)
  applyDefaults(db.global, mod.mergedDefaults.global)
  attachProfile(mod)
  if not mod.parent then
    function db:GetCurrentProfile()
      return self.profileName
    end
    function db:GetProfiles()
      return B:GetProfiles()
    end
  end
end

function DB.Prune(mod)
  local db = mod.db
  if not db then
    return
  end
  local d = mod.mergedDefaults
  prune(db.profile, d.profile)
  prune(db.char, d.char)
  prune(db.global, d.global)
  if db.sv then
    -- empty containers leave the file too; Attach and Reattach recreate them
    prune(db.sv.profiles, nil)
    if next(db.sv.profiles) == nil then
      rawset(db.sv, "profiles", nil)
    end
    if next(db.global) == nil then
      rawset(db.sv, "global", nil)
    end
  end
end

-- Re-point a top-level module at its (possibly pruned) scope tables, then its children.
function DB.Reattach(mod)
  local db = mod.db
  db.global = ensure(db.sv, "global")
  applyDefaults(db.global, mod.mergedDefaults.global)
  attachProfile(mod)
  for _, child in ipairs(mod.children) do
    if child.db then
      child.db.global = ensure(ensure(db.global, "modules"), child.shortName)
      applyDefaults(child.db.global, child.mergedDefaults.global)
    end
  end
end

-- Children were registered after their parents, so the reverse order prunes them first.
function DB.PruneAll()
  for i = #ns.moduleList, 1, -1 do
    DB.Prune(ns.moduleList[i])
  end
  -- Core's settings are the "Core" module's scopes and were pruned above; an empty profileKeys goes too.
  local keys = type(BastiansCoreDB) == "table" and rawget(BastiansCoreDB, "profileKeys")
  if type(keys) == "table" and next(keys) == nil then
    rawset(BastiansCoreDB, "profileKeys", nil)
  end
end

-- ---------------------------------------------------------------------------------------------
-- Profiles: one selection for the whole suite, per character (core-contracts §9)
-- ---------------------------------------------------------------------------------------------

function B:GetProfiles()
  local seen = { [DEFAULT_PROFILE] = true, [charKey()] = true }
  for _, mod in ipairs(ns.moduleList) do
    if mod.db and mod.db.sv then
      for name in pairs(mod.db.sv.profiles) do
        seen[name] = true
      end
    end
  end
  local names = {}
  for name in pairs(seen) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

function B:GetProfile()
  return DB.CurrentProfile()
end

-- Switches every module to the profile: enabled modules are disabled, re-pointed and enabled again.
function B:SetProfile(name)
  if type(name) ~= "string" or name == "" then
    error("SetProfile: a profile name is required", 2)
  end
  if name == DB.CurrentProfile() then
    return
  end
  local wasEnabled = {}
  for _, mod in ipairs(ns.moduleList) do
    if not mod.parent and mod.state == "enabled" then
      wasEnabled[#wasEnabled + 1] = mod
      mod:Disable("profile")
    end
  end
  DB.PruneAll()
  ensure(BastiansCoreDB, "profileKeys")[charKey()] = name
  for _, mod in ipairs(ns.moduleList) do
    if mod.db and not mod.parent then
      DB.Reattach(mod)
    end
  end
  for _, mod in ipairs(wasEnabled) do
    ns.autoEnable(mod)
  end
  B:Fire("BASTIANS_PROFILE_CHANGED", name)
end
