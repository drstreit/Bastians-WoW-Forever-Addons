-- Bastian's Chat, the message record (plan-chat-v3.md §1, ADR 0075): every captured line as one
-- plain table the views read; its links with their kind, id and quality; map coordinates and web
-- addresses in its words; the client's own format strings turned into patterns, so its system
-- lines are recognised in every client language. Pure: plain tables in and out, no WoW API.
local _, ns = ...

local Record = {}
ns.Record = Record

-- an item link's colour code and the item quality it stands for (the retail family's ITEM_QUALITY)
Record.QUALITY = {
  ff9d9d9d = 0,
  ffffffff = 1,
  ff1eff00 = 2,
  ff0070dd = 3,
  ffa335ee = 4,
  ffff8000 = 5,
  ffe6cc80 = 6,
}

-- The links of a text: { kind, id, text, quality, name, payload }. `id` is the number after the
-- kind (item, quest, spell, achievement, enchant, ...), `name` a player link's name, `quality` an
-- item's from the colour code before it (nil when none).
function Record.Links(text)
  local out = {}
  if type(text) ~= "string" or not text:find("|H", 1, true) then
    return out
  end
  for pos, payload, shown in text:gmatch("()|H(.-)|h(.-)|h") do
    local kind = payload:match("^([^:]+)")
    local link = {
      kind = kind,
      id = tonumber(payload:match("^[^:]+:(%-?%d+)")),
      text = shown:match("^%[(.*)%]$") or shown,
      payload = payload,
    }
    if kind == "player" or kind == "BNplayer" then
      link.name = payload:match("^[^:]+:([^:]+)")
      link.id = nil
    end
    if pos > 10 then
      local hex = text:sub(pos - 10, pos - 1):match("^|c(%x%x%x%x%x%x%x%x)$")
      link.quality = hex and Record.QUALITY[hex:lower()]
    end
    out[#out + 1] = link
  end
  return out
end

local function percent(v)
  local n = tonumber(v)
  return n and n >= 0 and n <= 100 and n or nil
end

-- Map coordinates (map percent, 0..100) and web addresses in a line's plain text, added to its
-- links as { kind = "coords", x, y } and { kind = "url", text }. Coordinates count when written
-- after /way, or as two numbers with decimals ("45.2, 67.8"): plain numbers are counts and prices.
function Record.AddPlaces(links, plain)
  if type(plain) ~= "string" then
    return links
  end
  local x, y = plain:match("/way%s+[^%d]-(%d+%.?%d*)[%s,]+(%d+%.?%d*)")
  if not x then
    x, y = plain:match("(%d%d?%.%d+)%s*,?%s+(%d%d?%.%d+)")
  end
  if not x then
    x, y = plain:match("(%d%d?%.%d+),(%d%d?%.%d+)")
  end
  if percent(x) and percent(y) then
    links[#links + 1] = { kind = "coords", x = percent(x), y = percent(y) }
  end
  for url in plain:gmatch("https?://[^%s]+") do
    links[#links + 1] = { kind = "url", text = url }
  end
  for url in plain:gmatch("www%.[^%s]+") do
    links[#links + 1] = { kind = "url", text = url }
  end
  return links
end

-- The first link of a kind, or nil.
function Record.Link(rec, kind)
  for _, link in ipairs(rec.links or {}) do
    if link.kind == kind then
      return link
    end
  end
  return nil
end

local MAGIC = {
  ["^"] = true,
  ["$"] = true,
  ["("] = true,
  [")"] = true,
  ["."] = true,
  ["["] = true,
  ["]"] = true,
  ["*"] = true,
  ["+"] = true,
  ["-"] = true,
  ["?"] = true,
}

-- A client format string ("%s receives loot: %s.", "|Hplayer:%s|h[%s]|h has come online.", with
-- or without positions like "%1$s") as an anchored Lua pattern with one capture per placeholder:
-- "%s" any text, "%d" a number. Nil for a format without text.
function Record.Pattern(fmt)
  if type(fmt) ~= "string" or fmt == "" then
    return nil
  end
  local out, i, n = { "^" }, 1, #fmt
  while i <= n do
    local c = fmt:sub(i, i)
    if c == "%" then
      local s, e = fmt:find("^%%%d*%$?[sdi%%]", i)
      if s then
        local spec = fmt:sub(e, e)
        if spec == "s" then
          out[#out + 1] = "(.+)"
        elseif spec == "%" then
          out[#out + 1] = "%%"
        else
          out[#out + 1] = "(%-?%d+)"
        end
        i = e + 1
      else
        out[#out + 1] = "%%"
        i = i + 1
      end
    else
      out[#out + 1] = MAGIC[c] and ("%" .. c) or c
      i = i + 1
    end
  end
  out[#out + 1] = "$"
  return table.concat(out)
end

-- The first entry whose pattern the text fits, with the captures; entries = { { pattern, ... } }.
function Record.Match(text, entries)
  if type(text) ~= "string" or not entries then
    return nil
  end
  for _, entry in ipairs(entries) do
    local caps = { text:match(entry.pattern) }
    if caps[1] ~= nil then
      return entry, caps
    end
  end
  return nil
end

-- A record from the line version 2 captures (Chat.Line): { text, msg, plain, secret, chatType,
-- cat, sender, guid, flags, bnID, rpName, channel, channelNumber, zoneChannel, public, own, r, g, b, at,
-- reason, dim }. Stream, tier, intent and ask are filled by Intent and Relevance.
function Record.Build(line)
  local secret = line.secret and true or false
  local rec = {
    t = line.at,
    chatType = line.chatType,
    event = line.chatType and ("CHAT_MSG_" .. line.chatType) or nil,
    text = line.text,
    body = line.msg or line.text,
    plain = not secret and line.plain or nil,
    secret = secret,
    own = line.own and true or false,
    channel = line.channel,
    channelNumber = line.channelNumber,
    zoneChannel = line.zoneChannel,
    public = line.public and true or false,
    r = line.r,
    g = line.g,
    b = line.b,
    reason = line.reason,
    dim = line.dim,
  }
  -- the client sends 0 as the Battle.net id of every line that is not a Battle.net one
  local bn = type(line.bnID) == "number" and line.bnID > 0 and line.bnID or nil
  if line.sender or bn then
    rec.who = { name = line.sender, guid = line.guid, flags = line.flags, bn = bn, rp = line.rpName }
  end
  if secret then
    rec.links = {}
  else
    rec.links = Record.AddPlaces(Record.Links(rec.body), rec.plain)
  end
  rec.keep = not secret and line.cat ~= "bnet" and not rec.public
  return rec
end
