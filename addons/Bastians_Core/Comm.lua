-- Core: the suite's transport between players (core-contracts §11a, notes.md N3): plain values
-- serialized without code (length-prefixed strings, nothing is ever loaded as Lua), cut into
-- addon messages, throttled, put together again on the other side and handed to the app that
-- registered the kind. Also the text form of a value (a copyable string) for forums and friends.
local _, ns = ...
local B = ns.B

local Comm = {}
B.Comm = Comm

Comm.PREFIX = "Bastians" -- the addon message prefix (at most 16 characters)
Comm.VERSION = "1"
Comm.CHUNK = 200 -- characters of payload per message (the game allows 255 with the header)
Comm.RATE = 0.25 -- seconds between two messages of the send queue
Comm.STALE = 60 -- seconds after which an incomplete message is dropped
Comm.MAX_DEPTH, Comm.MAX_ITEMS = 8, 5000 -- what a received value may hold at most
-- CHANNEL (04.11.2026, #20): a custom chat channel by its number; only a kind registered as
-- `public` takes values from there (strangers reach it), every other kind drops them.
Comm.CHANNELS = { PARTY = true, RAID = true, GUILD = true, WHISPER = true, CHANNEL = true }
Comm.TEXT_TAG = "!BN1!" -- the start of the text form

local handlers = {} -- kind -> { owner, fn }
local queue = {} -- { prefix, text, channel, target }
local partial = {} -- sender .. id -> { n, parts, got, at, kind, channel }
local ticker, frame, nextId = nil, nil, 0

-- ---------------------------------------------------------------------------------------------
-- Serialization: s<len>:<text> | n<number>; | T | F | t <key value>... e
-- ---------------------------------------------------------------------------------------------

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do
    keys[#keys + 1] = k
  end
  table.sort(keys, function(a, b)
    if type(a) ~= type(b) then
      return type(a) < type(b)
    end
    return a < b
  end)
  return keys
end

local function write(v, out, depth)
  local t = type(v)
  if t == "string" then
    out[#out + 1] = "s" .. #v .. ":" .. v
  elseif t == "number" then
    out[#out + 1] = "n" .. string.format("%.17g", v) .. ";"
  elseif t == "boolean" then
    out[#out + 1] = v and "T" or "F"
  elseif t == "table" then
    if depth > Comm.MAX_DEPTH then
      error("Comm.Serialize: too deep", 0)
    end
    out[#out + 1] = "t"
    for _, k in ipairs(sortedKeys(v)) do
      local kt = type(k)
      if kt == "string" or kt == "number" then
        write(k, out, depth + 1)
        write(v[k], out, depth + 1)
      end
    end
    out[#out + 1] = "e"
  else
    error("Comm.Serialize: cannot send a " .. t, 0)
  end
end

-- A plain value (strings, numbers, booleans, tables of them) as a string; deterministic.
function Comm.Serialize(v)
  local out = {}
  write(v, out, 0)
  return table.concat(out)
end

-- The value back, or nil and why; never runs anything, stops at MAX_DEPTH and MAX_ITEMS.
function Comm.Deserialize(text)
  if type(text) ~= "string" then
    return nil, "not a string"
  end
  local pos, items = 1, 0
  local read
  local function fail(why)
    error({ why = why }, 0)
  end
  read = function(depth)
    items = items + 1
    if items > Comm.MAX_ITEMS then
      fail("too many items")
    end
    local c = text:sub(pos, pos)
    if c == "" then
      fail("unexpected end")
    elseif c == "s" then
      local colon = text:find(":", pos + 1, true)
      local len = colon and tonumber(text:sub(pos + 1, colon - 1))
      if not len or len < 0 or colon + len > #text then
        fail("bad string")
      end
      local v = text:sub(colon + 1, colon + len)
      pos = colon + len + 1
      return v
    elseif c == "n" then
      local semi = text:find(";", pos + 1, true)
      local v = semi and tonumber(text:sub(pos + 1, semi - 1))
      if not v then
        fail("bad number")
      end
      pos = semi + 1
      return v
    elseif c == "T" or c == "F" then
      pos = pos + 1
      return c == "T"
    elseif c == "t" then
      if depth >= Comm.MAX_DEPTH then
        fail("too deep")
      end
      pos = pos + 1
      local t = {}
      while text:sub(pos, pos) ~= "e" do
        if pos > #text then
          fail("unterminated table")
        end
        local k = read(depth + 1)
        if type(k) ~= "string" and type(k) ~= "number" then
          fail("bad key")
        end
        t[k] = read(depth + 1)
      end
      pos = pos + 1
      return t
    end
    fail("unknown tag")
  end
  local ok, result = pcall(read, 0)
  if not ok then
    return nil, type(result) == "table" and result.why or tostring(result)
  end
  if pos ~= #text + 1 then
    return nil, "trailing data"
  end
  return result
end

-- ---------------------------------------------------------------------------------------------
-- The text form: TEXT_TAG .. base64 of the serialized value
-- ---------------------------------------------------------------------------------------------

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_INDEX = {}
for i = 1, #B64 do
  B64_INDEX[B64:sub(i, i)] = i - 1
end

local function base64(data)
  local out = {}
  for i = 1, #data, 3 do
    local a, b, c = data:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local q = {
      math.floor(n / 262144) % 64,
      math.floor(n / 4096) % 64,
      math.floor(n / 64) % 64,
      n % 64,
    }
    out[#out + 1] = B64:sub(q[1] + 1, q[1] + 1) .. B64:sub(q[2] + 1, q[2] + 1)
    out[#out + 1] = b and B64:sub(q[3] + 1, q[3] + 1) or "="
    out[#out + 1] = c and B64:sub(q[4] + 1, q[4] + 1) or "="
  end
  return table.concat(out)
end

local function unbase64(text)
  text = text:gsub("%s", "")
  if #text % 4 ~= 0 then
    return nil
  end
  local out = {}
  for i = 1, #text, 4 do
    local chunk = text:sub(i, i + 3)
    local n, pad = 0, 0
    for j = 1, 4 do
      local ch = chunk:sub(j, j)
      local v = B64_INDEX[ch]
      if ch == "=" then
        pad, v = pad + 1, 0
      elseif not v then
        return nil
      end
      n = n * 64 + v
    end
    local bytes = { math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256 }
    for j = 1, 3 - pad do
      out[#out + 1] = string.char(bytes[j])
    end
  end
  return table.concat(out)
end

-- A value as a string to copy (forums, Discord, another account).
function Comm.Encode(v)
  return Comm.TEXT_TAG .. base64(Comm.Serialize(v))
end

-- The value of a copied string, or nil and why.
function Comm.Decode(text)
  text = strtrim(text or "")
  if text:sub(1, #Comm.TEXT_TAG) ~= Comm.TEXT_TAG then
    return nil, "not a Bastian's text"
  end
  local data = unbase64(text:sub(#Comm.TEXT_TAG + 1))
  if not data then
    return nil, "damaged text"
  end
  return Comm.Deserialize(data)
end

-- ---------------------------------------------------------------------------------------------
-- Sending: kind and value to a channel, cut into messages, sent from a queue
-- ---------------------------------------------------------------------------------------------

local function pump()
  local m = table.remove(queue, 1)
  if m then
    B.Compat.SendAddonMessage(m.prefix, m.text, m.channel, m.target)
  end
  if #queue == 0 and ticker then
    ticker:Cancel()
    ticker = nil
  end
end
Comm.Pump = pump

-- Cuts a message into its parts: "<version>|<id>|<i>/<n>|<kind>|<chunk>".
function Comm.Parts(kind, value, id)
  local data = Comm.Serialize(value)
  local n = math.max(1, math.ceil(#data / Comm.CHUNK))
  local parts = {}
  for i = 1, n do
    local chunk = data:sub((i - 1) * Comm.CHUNK + 1, i * Comm.CHUNK)
    parts[i] = table.concat({ Comm.VERSION, id, i .. "/" .. n, kind, chunk }, "|")
  end
  return parts
end

-- Sends a value of `kind` to PARTY, RAID, GUILD, WHISPER (target: the name) or CHANNEL (target:
-- the channel's number); -> the number of messages queued, or nil and why.
function Comm.Send(kind, value, channel, target)
  if not Comm.CHANNELS[channel] then
    return nil, "channel"
  end
  if channel == "WHISPER" and (type(target) ~= "string" or target == "") then
    return nil, "target"
  end
  if channel == "CHANNEL" and not (tonumber(target) and tonumber(target) > 0) then
    return nil, "target"
  end
  if not B.Compat.RegisterAddonPrefix(Comm.PREFIX) then
    return nil, "no addon messages on this client"
  end
  nextId = nextId + 1
  local parts = Comm.Parts(kind, value, tostring(nextId))
  for _, text in ipairs(parts) do
    queue[#queue + 1] = { prefix = Comm.PREFIX, text = text, channel = channel, target = target }
  end
  if not ticker then
    pump()
    if #queue > 0 then
      ticker = C_Timer.NewTicker(Comm.RATE, pump)
    end
  end
  return #parts
end

-- ---------------------------------------------------------------------------------------------
-- Receiving: parts by sender and id, the whole value to the kind's handler
-- ---------------------------------------------------------------------------------------------

local function selfName()
  return type(UnitName) == "function" and UnitName("player") or nil
end

-- One received addon message; -> the kind delivered when a value was completed.
function Comm.Receive(prefix, text, channel, sender)
  if prefix ~= Comm.PREFIX or type(text) ~= "string" or type(sender) ~= "string" then
    return nil
  end
  if sender:match("^([^%-]+)") == selfName() then
    return nil -- our own message, echoed to the group
  end
  local version, id, i, n, kind, chunk = text:match("^([^|]+)|([^|]+)|(%d+)/(%d+)|([^|]+)|(.*)$")
  i, n = tonumber(i), tonumber(n)
  if version ~= Comm.VERSION or not (i and n) or i < 1 or i > n or n > 1000 then
    return nil
  end
  local now = GetTime()
  for key, p in pairs(partial) do
    if now - p.at > Comm.STALE then
      partial[key] = nil
    end
  end
  local key = sender .. "\0" .. id
  local p = partial[key]
  if not p then
    p = { n = n, parts = {}, got = 0, kind = kind, channel = channel }
    partial[key] = p
  end
  p.at = now
  if not p.parts[i] then
    p.parts[i], p.got = chunk, p.got + 1
  end
  if p.got < p.n then
    return nil
  end
  partial[key] = nil
  local value = Comm.Deserialize(table.concat(p.parts, "", 1, p.n))
  local h = handlers[p.kind]
  if value == nil or not h or not h.owner:IsEnabled() or (p.channel == "CHANNEL" and not h.public) then
    return nil
  end
  ns.safecall(h.owner, h.fn, value, sender, p.channel)
  return p.kind
end

-- An app takes the values of a kind: fn(value, sender, channel). One handler per kind. `opts.public`
-- also takes them from a custom channel (CHANNEL), where anyone may send.
function Comm.Register(owner, kind, fn, opts)
  handlers[kind] = { owner = owner, fn = fn, public = opts and opts.public == true or false }
  if not frame then
    frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function(_, _, ...)
      Comm.Receive(...)
    end)
    pcall(frame.RegisterEvent, frame, "CHAT_MSG_ADDON") -- a client without it loses the feature only
    B.Compat.RegisterAddonPrefix(Comm.PREFIX)
  end
end

-- For the tests: the queue and the partial messages.
function Comm.State()
  return queue, partial
end
