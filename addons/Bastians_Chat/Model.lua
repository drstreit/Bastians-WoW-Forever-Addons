-- Bastian's Chat, the model (chat.md): plain tables in and out, no WoW API. Which category a chat
-- type is, which tab takes a line, the line's plain text, long texts cut into parts, web addresses
-- turned into links, and the capped scrollback.
local _, ns = ...

local Model = {}
ns.Model = Model

Model.PART_BYTES = 255 -- one chat message of the client, in bytes
Model.MARK_BYTES = 8 -- room for " (12/15)"
Model.URL_LINK = "addon:Bastians_Chat:url:" -- our own link type for web addresses

-- chat type (the event name without CHAT_MSG_) -> category
local CATEGORY = {
  WHISPER = "whisper",
  WHISPER_INFORM = "whisper",
  AFK = "whisper",
  DND = "whisper",
  BN_WHISPER = "bnet",
  BN_WHISPER_INFORM = "bnet",
  GUILD = "guild",
  OFFICER = "officer",
  GUILD_ACHIEVEMENT = "guild",
  PARTY = "group",
  PARTY_LEADER = "group",
  RAID = "group",
  RAID_LEADER = "group",
  RAID_WARNING = "group",
  INSTANCE_CHAT = "group",
  INSTANCE_CHAT_LEADER = "group",
  CHANNEL = "channel",
  COMMUNITIES_CHANNEL = "channel",
  SAY = "say",
  YELL = "say",
  EMOTE = "say",
  TEXT_EMOTE = "say",
  MONSTER_SAY = "npc",
  MONSTER_YELL = "npc",
  MONSTER_EMOTE = "npc",
  MONSTER_WHISPER = "npc",
  RAID_BOSS_EMOTE = "npc",
  RAID_BOSS_WHISPER = "npc",
  LOOT = "loot",
  MONEY = "loot",
  CURRENCY = "loot",
  SKILL = "progress",
  COMBAT_XP_GAIN = "progress",
  COMBAT_FACTION_CHANGE = "progress",
  COMBAT_HONOR_GAIN = "progress",
  ACHIEVEMENT = "progress",
}

-- The kinds of line a tab can take, in the tab editor's order (chat.md "Windows and tabs").
Model.CATS = {
  "say",
  "whisper",
  "guild",
  "officer",
  "group",
  "channel",
  "npc",
  "loot",
  "progress",
  "system",
  "addon",
  "bnet",
}
Model.CAT_LABELS = {
  say = "Say, yell, emotes",
  whisper = "Whispers",
  guild = "Guild",
  officer = "Officers",
  group = "Group and raid",
  channel = "Every channel",
  npc = "NPCs",
  loot = "Loot and money",
  progress = "Experience, skills, achievements",
  system = "System",
  addon = "Addons",
  bnet = "Battle.net",
}

-- The chat events the app listens to (each also a key of CATEGORY or "system").
Model.EVENTS = {
  "CHAT_MSG_SAY",
  "CHAT_MSG_YELL",
  "CHAT_MSG_EMOTE",
  "CHAT_MSG_TEXT_EMOTE",
  "CHAT_MSG_WHISPER",
  "CHAT_MSG_WHISPER_INFORM",
  "CHAT_MSG_BN_WHISPER",
  "CHAT_MSG_BN_WHISPER_INFORM",
  "CHAT_MSG_PARTY",
  "CHAT_MSG_PARTY_LEADER",
  "CHAT_MSG_RAID",
  "CHAT_MSG_RAID_LEADER",
  "CHAT_MSG_RAID_WARNING",
  "CHAT_MSG_INSTANCE_CHAT",
  "CHAT_MSG_INSTANCE_CHAT_LEADER",
  "CHAT_MSG_GUILD",
  "CHAT_MSG_OFFICER",
  "CHAT_MSG_CHANNEL",
  "CHAT_MSG_SYSTEM",
  "CHAT_MSG_LOOT",
  "CHAT_MSG_MONEY",
  "CHAT_MSG_CURRENCY",
  "CHAT_MSG_MONSTER_SAY",
  "CHAT_MSG_MONSTER_YELL",
  "CHAT_MSG_MONSTER_EMOTE",
  "CHAT_MSG_MONSTER_WHISPER",
  "CHAT_MSG_RAID_BOSS_EMOTE",
  "CHAT_MSG_RAID_BOSS_WHISPER",
  "CHAT_MSG_ACHIEVEMENT",
  "CHAT_MSG_GUILD_ACHIEVEMENT",
  "CHAT_MSG_COMMUNITIES_CHANNEL",
  "CHAT_MSG_SKILL",
  "CHAT_MSG_COMBAT_XP_GAIN",
  "CHAT_MSG_COMBAT_FACTION_CHANGE",
  "CHAT_MSG_COMBAT_HONOR_GAIN",
  "CHAT_MSG_AFK",
  "CHAT_MSG_DND",
  "CHAT_MSG_IGNORED",
  "CHAT_MSG_CHANNEL_NOTICE",
  "CHAT_MSG_CHANNEL_NOTICE_USER",
  "CHAT_MSG_CHANNEL_JOIN",
  "CHAT_MSG_CHANNEL_LEAVE",
}

function Model.ChatType(event)
  return type(event) == "string" and event:match("^CHAT_MSG_(.+)$") or nil
end

function Model.Category(chatType)
  if not chatType then
    return "addon" -- a line without an event: an addon's or the game's own print
  end
  return CATEGORY[chatType] or "system"
end

-- The tabs of a new profile, in order; whisper tabs follow them (Model.WhisperTab). `fixed`: the
-- tab cannot be deleted. Their titles are English keys of the locale (a renamed tab has `named`).
Model.TABS = {
  {
    id = "general",
    title = "General",
    fixed = true,
    cats = {
      say = true,
      channel = true,
      guild = true,
      officer = true,
      group = true,
      npc = true,
      loot = true,
      progress = true,
      system = true,
      addon = true,
    },
  },
  { id = "guild", title = "Guild", cats = { guild = true, officer = true } },
  { id = "group", title = "Group", cats = { group = true } },
  { id = "bnet", title = "Battle.net", cats = { bnet = true }, hidden = true },
}

-- The presets of the `+` menu (plan-chat.md §3.1 "Preset groups").
Model.PRESETS = {
  { title = "Loot", cats = { loot = true } },
  { title = "System", cats = { system = true, progress = true } },
  { title = "NPC", cats = { npc = true } },
  { title = "Addons", cats = { addon = true } },
  { title = "Whispers", cats = { whisper = true, bnet = true } },
  -- roleplay (plan-second-wave.md S9): what is said around you and to you, the NPCs, no channels
  { title = "Roleplay", cats = { say = true, whisper = true, npc = true } },
}

-- A copy of a tab definition (the defaults and presets stay as they are).
function Model.CopyDef(def)
  local out = {}
  for k, v in pairs(def) do
    if type(v) == "table" then
      local t = {}
      for k2, v2 in pairs(v) do
        t[k2] = v2
      end
      out[k] = t
    else
      out[k] = v
    end
  end
  return out
end

-- A free id for a new tab: "t1", "t2", ...
function Model.NewTabId(defs)
  local i = 1
  while defs["t" .. i] do
    i = i + 1
  end
  return "t" .. i
end

function Model.WhisperTab(partner)
  return { id = "w:" .. partner, title = Model.ShortName(partner), partner = partner, whisper = true }
end

-- "Name-Realm" -> "Name"
function Model.ShortName(name)
  return type(name) == "string" and (name:match("^([^%-]+)") or name) or "?"
end

-- ---------------------------------------------------------------------------------------------
-- Words: "a, b*, ~pattern" -> matchers on the line's plain text, lower case (plan A2: no regex)
-- ---------------------------------------------------------------------------------------------

-- The fields a chat filter may name (ADR 0045), the line being the record: `from` (the
-- sender), `in` (the kind and the channel's name), `has` (link, item, quest, achievement, url).
local HAS = { item = "|Hitem:", quest = "|Hquest:", achievement = "|Hachievement:", link = "|H" }
Model.FIELDS = {
  from = {
    get = function(line)
      return line.sender
    end,
  },
  ["in"] = {
    get = function(line)
      local out = {}
      out[#out + 1] = line.cat
      out[#out + 1] = line.channel
      return out
    end,
  },
  has = {
    kind = "flag",
    get = function(line, value)
      local raw = line.text or line.msg or ""
      if HAS[value] then
        return raw:find(HAS[value], 1, true) ~= nil
      elseif value == "url" or value == "web" then
        local plain = line.plain or ""
        return plain:find("://", 1, true) ~= nil or plain:find("www.", 1, true) ~= nil
      end
      return nil
    end,
  },
}

-- The fields for a box's tooltip.
Model.FIELD_NAMES = "from, in, has (link, item, quest, achievement, url)"

-- A box whose text is a list of chat filters: the syntax on its tooltip (ADR 0045).
function Model.FilterBox(box)
  box.plainText = nil
  box.queryOpts = { fields = Model.FIELDS }
  box.queryFields = Model.FIELD_NAMES
  return box
end

-- One entry as a matcher: { word, q = a Bastians.Query } or, written as before ADR 0045,
-- { word, pattern = a Lua pattern } for "~pattern".
local function compileWord(word)
  word = word:gsub("^%s+", ""):gsub("%s+$", "")
  if word == "" then
    return nil
  end
  if word:sub(1, 1) == "~" then
    local pattern = word:sub(2)
    if pattern == "" or not pcall(string.find, "", pattern) then
      return nil -- a broken pattern matches nothing rather than raising on every line
    end
    return { word = word, pattern = pattern }
  end
  local q = Bastians.Query.Compile(word, { fields = Model.FIELDS })
  if q.empty then
    return nil
  end
  return { word = word, q = q }
end

-- "a, b, c" (commas or new lines) -> a list of matchers, each in the suite's search syntax
-- (ADR 0045: "wts gold, from:name, /pattern/"); nil or "" -> an empty list.
function Model.Words(text)
  local out = {}
  if type(text) ~= "string" then
    return out
  end
  for word in text:gmatch("[^,\n]+") do
    local m = compileWord(word)
    if m then
      out[#out + 1] = m
    end
  end
  return out
end

-- The first matcher that matches `plain` (already lower case) and the line its fields read, or
-- nil.
function Model.MatchWords(words, plain, line)
  if type(plain) ~= "string" then
    return nil
  end
  for _, m in ipairs(words) do
    if m.q then
      if m.q:MatchLower(plain, line or {}) then
        return m
      end
    else
      local ok, found = pcall(string.find, plain, m.pattern)
      if ok and found then
        return m
      end
    end
  end
  return nil
end

-- A channel's name without its zone: "Trade - City" and "General - Elwynn Forest" are "Trade"
-- and "General".
function Model.ChannelBase(name)
  if type(name) ~= "string" then
    return name
  end
  return name:match("^(.-)%s+%-%s+.+$") or name
end

-- line = { cat, partner, channel, plain }: does the tab take it? `words` the tab's compiled
-- keywords (Model.Words(def.words)), nil for none.
function Model.Takes(tab, line, words)
  if tab.whisper then
    return line.cat == "whisper" and line.partner == tab.partner
  end
  local kind = tab.cats ~= nil and tab.cats[line.cat] == true
  if not kind and line.cat == "channel" and tab.channels and line.channel then
    kind = tab.channels[line.channel] == true or tab.channels[Model.ChannelBase(line.channel)] == true
  end
  if not kind then
    return false
  end
  if words and #words > 0 then
    if line.secret then
      return false -- a secret text is never matched
    end
    return Model.MatchWords(words, line.plain, line) ~= nil
  end
  return true
end

-- A channel of the game's own (General, Trade, LocalDefense, ...) has a zone channel number above
-- 0; a channel the player made or joined by name has 0 (the event's seventh argument).
function Model.IsPublic(line)
  return line.cat == "channel" and type(line.zoneChannel) == "number" and line.zoneChannel > 0
end

-- The line as plain text: colour codes, textures and atlases gone, a link reduced to its words.
-- A line with the speaker's roleplay name (plan-launch-version L3): the shown text of the
-- speaker's player link becomes `rpName` (the link and its target stay, so a click still opens the
-- player's menu); a text emote that starts with the short name ("Grimtok waves.") starts with the
-- roleplay name. Anything else is left as it is. Pure.
function Model.WithRoleplayName(text, sender, rpName)
  if type(text) ~= "string" or type(sender) ~= "string" or type(rpName) ~= "string" or rpName == "" then
    return text
  end
  local short = sender:match("^([^%-]+)") or sender
  local safe = rpName:gsub("%%", "%%%%")
  local escaped = sender:gsub("(%W)", "%%%1")
  local out, n = text:gsub("(|Hplayer:" .. escaped .. "[^|]*|h)%[[^%]]*%](|h)", "%1[" .. safe .. "]%2", 1)
  if n == 0 and short ~= sender then
    escaped = short:gsub("(%W)", "%%%1")
    out, n = text:gsub("(|Hplayer:" .. escaped .. "[^|]*|h)%[[^%]]*%](|h)", "%1[" .. safe .. "]%2", 1)
  end
  if n == 0 then
    local plainShort = short:gsub("(%W)", "%%%1")
    out = text:gsub("^" .. plainShort .. "(%s)", safe .. "%1", 1)
  end
  return out
end

function Model.Strip(text)
  if type(text) ~= "string" then
    return ""
  end
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", ""):gsub("|r", "")
  text = text:gsub("|H.-|h(.-)|h", "%1")
  text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
  return text
end

-- Web addresses outside a link become our links; `code` is the colour code to show them in.
function Model.Linkify(text, code)
  if type(text) ~= "string" or not (text:find("://", 1, true) or text:find("www.", 1, true)) then
    return text
  end
  local out, pos = {}, 1
  while pos <= #text do
    local ls, le = text:find("|H.-|h.-|h", pos)
    local chunk = text:sub(pos, (ls or #text + 1) - 1)
    chunk = chunk:gsub("(%f[%S]%a[%w+.-]*://[^%s|]+)", function(url)
      return string.format("%s|H%s%s|h[%s]|h|r", code or "", Model.URL_LINK, url, url)
    end)
    chunk = chunk:gsub("(%f[%S]www%.[^%s|]+)", function(url)
      return string.format("%s|H%s%s|h[%s]|h|r", code or "", Model.URL_LINK, url, url)
    end)
    out[#out + 1] = chunk
    if not ls then
      break
    end
    out[#out + 1] = text:sub(ls, le)
    pos = le + 1
  end
  return table.concat(out)
end

-- The start of a link that covers byte `cut`, or nil.
local function insideLink(text, cut)
  local start = 1
  while true do
    local s, e = text:find("|H.-|h.-|h", start)
    if not s or s > cut then
      return nil
    end
    local open = s
    if s > 10 and text:sub(s - 10, s - 9) == "|c" then
      open = s - 10
    end
    local close = e
    if text:sub(e + 1, e + 2) == "|r" then
      close = e + 2
    end
    if cut >= open and cut < close then
      return open
    end
    start = e + 1
  end
end

-- Parts of at most `limit` bytes, never inside a UTF-8 character or a link, at a space where one
-- is near, each marked " (i/n)" when there are several.
function Model.Split(text, limit)
  limit = limit or Model.PART_BYTES
  if #text <= limit then
    return { text }
  end
  local room = limit - Model.MARK_BYTES
  local parts = {}
  while #text > room do
    local cut = room
    while cut > 1 and (text:byte(cut + 1) or 0) >= 128 and (text:byte(cut + 1) or 0) < 192 do
      cut = cut - 1
    end
    local open = insideLink(text, cut)
    if open and open > 1 then
      cut = open - 1
    end
    local space = text:sub(1, cut):match(".*() ")
    if space and space > room / 2 and not insideLink(text, space - 1) then
      cut = space - 1
    end
    parts[#parts + 1] = text:sub(1, cut)
    text = text:sub(cut + 1):gsub("^ +", "")
  end
  if #text > 0 then
    parts[#parts + 1] = text
  end
  for i = 1, #parts do
    parts[i] = string.format("%s (%d/%d)", parts[i], i, #parts)
  end
  return parts
end

-- Append to a capped list, dropping the oldest.
function Model.Push(list, entry, cap)
  list[#list + 1] = entry
  local over = #list - cap
  if over > 0 then
    for i = 1, #list - over do
      list[i] = list[i + over]
    end
    for i = #list, #list - over + 1, -1 do
      list[i] = nil
    end
  end
  return list
end

-- At logout (not at /reload): the lines of the game's public channels are dropped, and every line
-- of a tab whose definition says not to keep it (`defs[id].keep == false`).
function Model.DropPublic(scrollback, defs)
  for id, lines in pairs(scrollback) do
    local def = defs and defs[id]
    local kept = {}
    if not (def and def.keep == false) then
      for _, l in ipairs(lines) do
        if not l.public then
          kept[#kept + 1] = l
        end
      end
    end
    scrollback[id] = kept
  end
  return scrollback
end

-- ---------------------------------------------------------------------------------------------
-- The Messenger's conversations: { [key] = { name, lines = { { at, out, text, me } }, last, unread } }
-- ---------------------------------------------------------------------------------------------

Model.CONVO_DAYS = 30
Model.CONVO_LINES = 500

function Model.ConvoPush(convos, key, name, entry, cap)
  local c = convos[key]
  if not c then
    c = { name = name, lines = {}, unread = 0 }
    convos[key] = c
  end
  c.name = name or c.name
  Model.Push(c.lines, entry, cap or Model.CONVO_LINES)
  c.last = entry.at
  if not entry.out then
    c.unread = (c.unread or 0) + 1
  end
  return c
end

-- A conversation opened by the player before any line (the Messenger's "New"): made when missing,
-- at the top of the list; it goes at the next login if nobody wrote in it (TrimConvos).
function Model.ConvoOpen(convos, key, name, now)
  local c = convos[key]
  if not c then
    c = { name = name or key, lines = {}, unread = 0, last = now or time() }
    convos[key] = c
  end
  return c
end

-- Lines older than `days` go; a conversation without lines goes.
function Model.TrimConvos(convos, now, days, cap)
  local oldest = now - (days or Model.CONVO_DAYS) * 86400
  for key, c in pairs(convos) do
    local kept = {}
    for _, l in ipairs(c.lines or {}) do
      if type(l.at) == "number" and l.at >= oldest then
        kept[#kept + 1] = l
      end
    end
    while #kept > (cap or Model.CONVO_LINES) do
      table.remove(kept, 1)
    end
    if #kept == 0 then
      convos[key] = nil
    else
      c.lines = kept
      c.last = kept[#kept].at
    end
  end
  return convos
end

-- The keys of the conversations, the newest first.
function Model.ConvoOrder(convos)
  local keys = {}
  for key in pairs(convos) do
    keys[#keys + 1] = key
  end
  table.sort(keys, function(a, b)
    local la, lb = convos[a].last or 0, convos[b].last or 0
    if la ~= lb then
      return la > lb
    end
    return a < b
  end)
  return keys
end

-- Did the player ever write in it (S2: a contact)?
function Model.HasOwnLine(convo)
  for _, l in ipairs(convo and convo.lines or {}) do
    if l.out then
      return true
    end
  end
  return false
end

-- "[2. Trade - City]" in a channel link -> "[2]" (`how` "number") or "[Trade]" ("name").
function Model.ShortChannels(text, how)
  if type(text) ~= "string" or (how ~= "number" and how ~= "name") then
    return text
  end
  return (
    text:gsub("(|Hchannel:[^|]*|h)%[([^%]]*)%](|h)", function(open, inner, close)
      local num, name = inner:match("^(%d+)%.%s*(.*)$")
      if not num then
        return open .. "[" .. inner .. "]" .. close
      end
      if how == "number" then
        return open .. "[" .. num .. "]" .. close
      end
      name = name:gsub("%s+%-%s+.*$", "")
      return open .. "[" .. (name ~= "" and name or num) .. "]" .. close
    end)
  )
end

-- An icon before every item link; `iconOf(itemID)` -> texture or nil (unknown: no icon). The
-- icon goes right before `|H`, inside the link's colour (retail's `|cnIQ4:` codes included).
function Model.ItemIcons(text, iconOf)
  if type(text) ~= "string" or not text:find("|Hitem:", 1, true) then
    return text
  end
  return (
    text:gsub("(|Hitem:(%d+))", function(link, id)
      local icon = iconOf(tonumber(id))
      if icon then
        return "|T" .. tostring(icon) .. ":0|t" .. link
      end
      return link
    end)
  )
end

-- "HH:MM" or "HH:MM:SS" before a line; nil for none.
function Model.Stamp(fmt, t)
  if fmt == "hm" then
    return date("%H:%M", t) .. " "
  elseif fmt == "hms" then
    return date("%H:%M:%S", t) .. " "
  end
  return nil
end
