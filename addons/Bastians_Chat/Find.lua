-- Bastian's Chat, finding (plan-chat-one-window.md §2, ADR 0076; "Just replace by
-- text filters across the whole entry plus a '-' filter for words ruled out"): plain words over the
-- whole entry. A record's words are more than its text: the sender's name, its channel's name in
-- the client's language and in English, its stream's name on the rail, the sender's relation, the
-- offer and group words of every language of V9's tables (`wts` finds "verkaufe"), the names of
-- the items in its links, a dungeon's full name and its short forms (`dm` finds "Deadmines").
-- The suite's syntax (ADR 0045) still parses for those who know it; nothing on screen teaches it.
-- Also: the hits per place while a filter is typed, the suggestions under the filter line, the
-- recent searches. Pure but for the client's own words for its chat types.
local _, ns = ...
local B = Bastians
local L = ns.L
local Model, Words = ns.Model, ns.Words

local Find = {}
ns.Find = Find

Find.RECENT = 10 -- searches remembered
Find.SUGGEST = 5 -- suggestions at most
Find.SUGGEST_MIN = 2 -- letters typed before suggestions show

-- the English words of a chat type (and the client's own, from its CHAT_MSG_<TYPE> strings)
Find.TYPE_WORDS = {
  SAY = "say",
  YELL = "yell",
  EMOTE = "emote",
  TEXT_EMOTE = "emote",
  GUILD = "guild",
  OFFICER = "officer guild",
  GUILD_ACHIEVEMENT = "guild achievement",
  PARTY = "party group",
  PARTY_LEADER = "party group",
  RAID = "raid group",
  RAID_LEADER = "raid group",
  RAID_WARNING = "raid warning group",
  INSTANCE_CHAT = "instance group",
  INSTANCE_CHAT_LEADER = "instance group",
  WHISPER = "whisper",
  WHISPER_INFORM = "whisper",
  AFK = "whisper away",
  DND = "whisper busy",
  BN_WHISPER = "whisper battle.net",
  BN_WHISPER_INFORM = "whisper battle.net",
  LOOT = "loot",
  MONEY = "loot money",
  CURRENCY = "loot currency",
  COMBAT_XP_GAIN = "experience xp",
  COMBAT_FACTION_CHANGE = "reputation rep",
  SYSTEM = "system",
  SKILL = "skill",
  ACHIEVEMENT = "achievement",
  TRADESKILLS = "profession",
  MONSTER_SAY = "npc",
  MONSTER_YELL = "npc",
  MONSTER_EMOTE = "npc",
  MONSTER_WHISPER = "npc",
  MONSTER_PARTY = "npc",
  RAID_BOSS_EMOTE = "npc boss",
  RAID_BOSS_WHISPER = "npc boss",
  CHANNEL = "channel",
}
-- a public channel's kind (Words.ChannelKind) in English
Find.CHANNEL_WORDS = {
  trade = "trade",
  lfg = "lookingforgroup lfg",
  general = "general",
  defense = "localdefense defense",
  services = "services",
}
-- a stream's names: its id, its English rail name (and the client's, from the rail's labels)
Find.STREAM_WORDS = {
  direct = "whispers whisper",
  group = "group",
  guild = "guild",
  mine = "mine",
  market = "market",
  lfg = "groups",
  world = "world",
  addons = "addons",
  junk = "junk",
  fight = "fight",
}
Find.STREAM_LABELS = {
  direct = "Whispers",
  group = "Group",
  guild = "Guild",
  mine = "Mine",
  market = "Market",
  lfg = "Groups",
  world = "World",
  addons = "Addons",
  junk = "Junk",
  fight = "Fight",
}
-- how the player knows the sender
Find.REL_WORDS = {
  friend = "friend",
  bnet = "friend battle.net",
  guild = "guild",
  group = "group",
  stranger = "stranger",
  gm = "gm game master",
  self = "you",
}
Find.REL_LABELS = { friend = "Friend", bnet = "Friend", stranger = "Stranger", gm = "Game Master" }

local lower, concat = string.lower, table.concat

local function words()
  return ns.Chat.Facts and ns.Chat.Facts().words or Words.For("enUS")
end

-- The client's own name of a chat type ("Gilde" for GUILD on a German client), lowercase, or nil.
function Find.ClientTypeName(chatType)
  local v = chatType and rawget(_G, "CHAT_MSG_" .. chatType)
  v = ns.Compat.Plain(v)
  return type(v) == "string" and v ~= "" and lower(v) or nil
end

-- Every name a dungeon goes by, from the words of every language the client merges: { [English
-- name] = "the deadmines deadmines vc dm" }. Built once per word list.
local aliasCache = setmetatable({}, { __mode = "k" })
function Find.Aliases(w)
  local out = aliasCache[w]
  if out then
    return out
  end
  local lists = {}
  for _, pair in ipairs(w.dungeons or {}) do
    local name = pair[2]
    lists[name] = lists[name] or { lower(name) }
    lists[name][#lists[name] + 1] = pair[1]
  end
  out = {}
  for name, list in pairs(lists) do
    out[name] = concat(list, " ")
  end
  aliasCache[w] = out
  return out
end

-- A record's words, lowercase, kept with the record: nil for a secret line (never matched).
function Find.Hay(rec, w)
  if type(rec) ~= "table" or rec.secret then
    return nil
  end
  if rec.hay then
    return rec.hay
  end
  w = w or words()
  local parts = { rec.plain or lower(Model.Strip(rec.body or rec.text or "") or "") }
  local function add(v)
    if type(v) == "string" and v ~= "" then
      parts[#parts + 1] = lower(v)
    end
  end
  local who = rec.who
  if who then
    add(who.name and Model.ShortName(who.name))
    add(who.name)
    add(who.rp)
    add(Find.REL_WORDS[who.rel])
    add(Find.REL_LABELS[who.rel] and L[Find.REL_LABELS[who.rel]])
  end
  local ct = rec.chatType
  add(Find.TYPE_WORDS[ct])
  add(Find.ClientTypeName(ct))
  add(rec.channel)
  add(Find.CHANNEL_WORDS[rec.channelKind])
  add(Find.STREAM_WORDS[rec.stream])
  add(Find.STREAM_LABELS[rec.stream] and L[Find.STREAM_LABELS[rec.stream]])
  local it = rec.intent
  if it and (it.kind == "wts" or it.kind == "wtb" or it.kind == "lfm" or it.kind == "lfg") then
    add(it.kind)
    add(concat(w[it.kind] or {}, " ")) -- `wts` finds "verkaufe", "verkaufe" finds "WTS"
    if it.need then
      add("lf" .. it.need .. "m")
    end
    for _, role in ipairs(it.roles or {}) do
      add(role)
    end
  elseif it and it.kind == "service" then
    add("service") -- V45: `service` finds the crafts and services of Trade
  end
  for _, link in ipairs(rec.links or {}) do
    if link.kind == "item" then
      add(link.text)
    end
  end
  local dungeon = (it and it.dungeon) or Words.Dungeon(w, parts[1])
  if dungeon then
    add(Find.Aliases(w)[dungeon] or lower(dungeon))
  end
  rec.hay = concat(parts, "\n")
  return rec.hay
end

-- A filter's text compiled (nil for none): plain words over the whole entry, the suite's fields.
function Find.Query(text)
  if type(text) ~= "string" or not text:find("%S") then
    return nil
  end
  return B.Query.Compile(text, { fields = ns.Rows.FIELDS, text = Find.Hay })
end

-- A conversation's line as a record of words: its text, the partner's name and "whisper".
function Find.LineRec(c, l)
  local name = c and c.name or ""
  return {
    plain = lower(Model.Strip(l.text) or ""),
    who = { name = name },
    chatType = l.out and "WHISPER_INFORM" or "WHISPER",
    stream = "direct",
  }
end

-- ---------------------------------------------------------------------------------------------
-- Hits per place (plan §2.3): how many lines of each stream and each person a query takes
-- ---------------------------------------------------------------------------------------------

-- { streams = { [id] = n }, people = { [key] = n } } for a compiled query.
function Find.Counts(q, recs, convos)
  local out = { streams = {}, people = {} }
  for _, rec in ipairs(recs or {}) do
    if q:Match(rec) then
      out.streams[rec.stream] = (out.streams[rec.stream] or 0) + 1
    end
  end
  for key, c in pairs(convos or {}) do
    local n = 0
    for _, l in ipairs(c.lines or {}) do
      if q:Match(Find.LineRec(c, l)) then
        n = n + 1
      end
    end
    out.people[key] = n
  end
  return out
end

-- ---------------------------------------------------------------------------------------------
-- Suggestions (plan §2.3): what the session has seen that starts with the word being typed
-- ---------------------------------------------------------------------------------------------

-- The word being typed: the text after the last space (a minus kept apart), lowercase.
function Find.LastWord(text)
  local word = (text or ""):match("(%S+)$")
  if not word then
    return nil
  end
  word = word:gsub("^%-", "")
  return lower(word)
end

local function starts(s, prefix)
  return type(s) == "string" and s:sub(1, #prefix) == prefix
end

-- Up to SUGGEST of { kind = "person"|"place"|"item"|"dungeon", label, value, n, place }: people
-- with their lines, the rail's places, the items in the session's links, the dungeons with their
-- posts. `places` = { { id, label } }; pure but for the locale.
function Find.Suggest(prefix, recs, convos, places, w)
  if type(prefix) ~= "string" or #prefix < Find.SUGGEST_MIN then
    return {}
  end
  prefix = lower(prefix)
  w = w or words()
  local out, seen = {}, {}
  local function push(kind, label, value, n, place)
    local key = kind .. ":" .. lower(value)
    if not seen[key] then
      seen[key] = true
      out[#out + 1] = { kind = kind, label = label, value = value, n = n, place = place }
    end
  end
  -- people: by their lines this session and their conversations
  local lines = {}
  for _, rec in ipairs(recs or {}) do
    local name = rec.who and rec.who.name and Model.ShortName(rec.who.name)
    if name and not rec.own and starts(lower(name), prefix) then
      lines[name] = (lines[name] or 0) + 1
    end
  end
  for _, c in pairs(convos or {}) do
    local name = Model.ShortName(c.name or "")
    if starts(lower(name), prefix) then
      lines[name] = (lines[name] or 0) + #(c.lines or {})
    end
  end
  local names = {}
  for name in pairs(lines) do
    names[#names + 1] = name
  end
  table.sort(names, function(a, b)
    return lines[a] > lines[b] or (lines[a] == lines[b] and a < b)
  end)
  for _, name in ipairs(names) do
    push("person", name, name, lines[name])
  end
  for _, p in ipairs(places or {}) do
    if starts(lower(p.label or ""), prefix) or starts(p.id, prefix) then
      push("place", p.label, p.label, nil, p.id)
    end
  end
  local items = {}
  for _, rec in ipairs(recs or {}) do
    for _, link in ipairs(rec.links or {}) do
      if link.kind == "item" and type(link.text) == "string" and starts(lower(link.text), prefix) then
        items[link.text] = (items[link.text] or 0) + 1
      end
    end
  end
  for text, n in pairs(items) do
    push("item", text, text, n)
  end
  local posts = {}
  for _, rec in ipairs(recs or {}) do
    local d = rec.intent and rec.intent.dungeon
    if d then
      posts[d] = (posts[d] or 0) + 1
    end
  end
  for _, pair in ipairs(w.dungeons or {}) do
    if starts(pair[1], prefix) or starts(lower(pair[2]), prefix) then
      push("dungeon", pair[2], pair[2], posts[pair[2]] or 0)
    end
  end
  while #out > Find.SUGGEST do
    table.remove(out)
  end
  return out
end

-- A suggestion's words on its row: "Haskel, 12 lines", "Guild", "Linen Cloth", "The Deadmines, 4
-- posts".
function Find.SuggestText(s)
  if s.kind == "person" then
    return L["%s, %d lines"]:format(s.label, s.n or 0)
  elseif s.kind == "dungeon" then
    return L["%s, %d posts"]:format(s.label, s.n or 0)
  end
  return s.label
end

-- The filter's text with the word being typed replaced by a suggestion's value (quoted when it
-- holds a space).
function Find.Take(text, value)
  local word = type(value) == "string" and value:find("%s") and ('"' .. value .. '"') or value
  local head = (text or ""):gsub("(%-?)%S*$", "%1")
  return head .. word .. " "
end

-- ---------------------------------------------------------------------------------------------
-- Recent searches (plan §2.3: a right click on the filter line lists the last ten)
-- ---------------------------------------------------------------------------------------------

function Find.Remember(list, text)
  text = type(text) == "string" and strtrim(text) or ""
  if text == "" then
    return list
  end
  for i = #list, 1, -1 do
    if list[i] == text then
      table.remove(list, i)
    end
  end
  table.insert(list, 1, text)
  while #list > Find.RECENT do
    table.remove(list)
  end
  return list
end
