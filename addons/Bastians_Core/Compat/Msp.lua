-- Compat: roleplay names through the msp protocol (Total RP 3, MyRolePlay; LibMSP's global `msp`),
-- read only (plan-second-wave.md S8, plan-launch-version L3): the suite never publishes a profile
-- of its own. LibMSP read 01.11.2026 (github.com/wow-rp-addons/LibMSP): another player's fields in
-- msp.char["Name-Realm"].field (NA name, NT title, NI nickname), `msp:Request(name, fields)` asks
-- (the library throttles one request per field per 5 s), the answer comes through
-- msp.callback.received. A shape check guards every read; without msp everything answers nil.
local _, ns = ...
local B = ns.B
local define, note = ns.Compat.define, ns.Compat.note

local FIELDS = { "NA", "NT", "NI" }
local ASK_SECONDS = 30 -- our own pause between two requests for one player
local asked = {} -- name -> GetTime of our last request (RAM only, no names kept)
local hooked = false

B:DeclareMessage("BASTIANS_RP_NAME") -- a roleplay profile arrived: the player's "Name-Realm"

local function lib()
  local m = rawget(_G, "msp")
  if type(m) == "table" and type(m.char) == "table" then
    return m
  end
  return nil
end

-- The callback list LibMSP calls with a name when fields arrived; joined once, on first use (Total
-- RP 3 and MyRolePlay load after Core).
local function hook(m)
  if hooked then
    return
  end
  local cb = type(m.callback) == "table" and m.callback.received or nil
  if type(cb) == "table" then
    hooked = true
    cb[#cb + 1] = function(name)
      if type(name) == "string" then
        B:Fire("BASTIANS_RP_NAME", name)
      end
    end
  end
end

-- "Name-Realm" of a unit (a player only) or of a name without a realm (this realm's).
local function fullName(who)
  if type(who) ~= "string" or who == "" then
    return nil
  end
  if UnitExists(who) then
    if not UnitIsPlayer(who) then
      return nil
    end
    local name, realm = UnitName(who)
    if type(name) ~= "string" then
      return nil
    end
    if not realm or realm == "" then
      realm = GetNormalizedRealmName and GetNormalizedRealmName() or nil
    end
    return realm and (name .. "-" .. realm:gsub("%s", "")) or name
  end
  if who:find("-", 1, true) then
    return who
  end
  local realm = GetNormalizedRealmName and GetNormalizedRealmName() or nil
  return realm and (who .. "-" .. realm) or who
end

-- A profile's text made plain: colour codes and links out, trimmed, at most 64 letters.
local function plainText(v)
  if type(v) ~= "string" then
    return nil
  end
  v = v:gsub("|c%x%x%x%x%x%x%x%x", "")
    :gsub("|r", "")
    :gsub("|H.-|h(.-)|h", "%1")
    :gsub("^%s+", "")
    :gsub("%s+$", "")
  if v == "" then
    return nil
  end
  return v:sub(1, 64)
end

define("shared", "HasMsp", function()
  return lib() ~= nil
end)

-- The roleplay name of a unit or player name: { name, title, nick } or nil (no msp, no profile).
define("shared", "MspName", function(who)
  local m = lib()
  if not m then
    return nil
  end
  hook(m)
  local key = fullName(who)
  local char = key and m.char[key]
  local field = type(char) == "table" and type(char.field) == "table" and char.field or nil
  if not field then
    return nil
  end
  local name = plainText(field.NA)
  if not name then
    return nil
  end
  note("MspName", "msp")
  return { name = name, title = plainText(field.NT), nick = plainText(field.NI) }
end)

-- Asks for a player's name fields (at most once per ASK_SECONDS per player). -> asked (bool).
define("shared", "MspRequest", function(who)
  local m = lib()
  if not m or type(m.Request) ~= "function" then
    return false
  end
  hook(m)
  local key = fullName(who)
  if not key then
    return false
  end
  local now = GetTime()
  if asked[key] and now - asked[key] < ASK_SECONDS then
    return false
  end
  asked[key] = now
  return pcall(m.Request, m, key, FIELDS) and true or false
end)
