-- Bastian's Chat, where a line belongs and how much it matters (plan-chat-v3.md §2): its stream
-- (direct, group, guild, world, market, lfg, mine, addons, junk), its tier on the ladder of six
-- (0 needs you ... 5 noise), how the player knows the writer, and the request it makes of the
-- player (a whisper, a raid warning, the player's name, a watch-list match). System lines are
-- sorted by the client's own format strings, so this works in every client language. Pure: the
-- facts (relations, the player's names, the patterns, the words) are handed in.
local _, ns = ...
local Record, Words, Intent = ns.Record, ns.Words, ns.Intent

local Relevance = {}
ns.Relevance = Relevance

Relevance.STREAMS =
  { "direct", "group", "guild", "world", "market", "lfg", "mine", "addons", "junk", "fight" }
Relevance.TIER_NAMES = { [0] = "needs you", "your people", "yours", "signals", "ambient", "noise" }

-- the stream of a chat type before the line's words and the client's strings are read
Relevance.STREAM_OF = {
  WHISPER = "direct",
  WHISPER_INFORM = "direct",
  BN_WHISPER = "direct",
  BN_WHISPER_INFORM = "direct",
  AFK = "direct",
  DND = "direct",
  PARTY = "group",
  PARTY_LEADER = "group",
  RAID = "group",
  RAID_LEADER = "group",
  RAID_WARNING = "group",
  INSTANCE_CHAT = "group",
  INSTANCE_CHAT_LEADER = "group",
  GUILD = "guild",
  OFFICER = "guild",
  GUILD_ACHIEVEMENT = "guild",
  SAY = "world",
  YELL = "world",
  EMOTE = "world",
  TEXT_EMOTE = "world",
  CHANNEL = "world",
  COMMUNITIES_CHANNEL = "world",
  MONSTER_SAY = "world",
  MONSTER_YELL = "world",
  MONSTER_EMOTE = "world",
  RAID_BOSS_EMOTE = "world",
  ACHIEVEMENT = "world",
  MONSTER_WHISPER = "mine",
  RAID_BOSS_WHISPER = "mine",
  LOOT = "group", -- the player's own loot is recognised by the client's strings (LOOT_ITEM_SELF)
  MONEY = "mine",
  CURRENCY = "mine",
  SKILL = "mine",
  COMBAT_XP_GAIN = "mine",
  COMBAT_FACTION_CHANGE = "mine",
  COMBAT_HONOR_GAIN = "mine",
  SYSTEM = "addons",
  IGNORED = "addons",
  CHANNEL_NOTICE = "addons",
  CHANNEL_NOTICE_USER = "addons",
  CHANNEL_JOIN = "addons",
  CHANNEL_LEAVE = "addons",
}
Relevance.TIER_OF = {
  direct = 0,
  group = 1,
  guild = 1,
  world = 4,
  market = 3,
  lfg = 3,
  mine = 2,
  addons = 4,
  junk = 5,
  fight = 2,
}
local SOCIAL = { direct = true, group = true, guild = true }
local SPEECH = { SAY = true, YELL = true, EMOTE = true, TEXT_EMOTE = true }
local INCOMING = { WHISPER = true, BN_WHISPER = true }
local FRIENDLY = { friend = true, bnet = true }

-- The client's format strings that sort a line (by its chat type, in this order: a "_MULTIPLE"
-- string before its shorter form). `gain`: what the ledger counts, from the capture at `qty`,
-- `num`, `money`, `name`; `kind = "online"`: a person came or went (the capture at `name`).
Relevance.SYSTEM = {
  { key = "LOOT_ITEM_SELF_MULTIPLE", ct = "LOOT", stream = "mine", gain = "item", qty = 2 },
  { key = "LOOT_ITEM_SELF", ct = "LOOT", stream = "mine", gain = "item" },
  { key = "LOOT_ITEM_PUSHED_SELF_MULTIPLE", ct = "LOOT", stream = "mine", gain = "item", qty = 2 },
  { key = "LOOT_ITEM_PUSHED_SELF", ct = "LOOT", stream = "mine", gain = "item" },
  { key = "LOOT_ITEM_CREATED_SELF_MULTIPLE", ct = "LOOT", stream = "mine", gain = "item", qty = 2 },
  { key = "LOOT_ITEM_CREATED_SELF", ct = "LOOT", stream = "mine", gain = "item" },
  { key = "LOOT_ROLL_YOU_WON", ct = "LOOT", stream = "mine", gain = "item" },
  { key = "LOOT_ITEM_MULTIPLE", ct = "LOOT", stream = "group" },
  { key = "LOOT_ITEM", ct = "LOOT", stream = "group" },
  { key = "LOOT_ROLL_WON", ct = "LOOT", stream = "group" },
  { key = "YOU_LOOT_MONEY_GUILD", ct = "MONEY", stream = "mine", gain = "money", money = 1 },
  { key = "YOU_LOOT_MONEY", ct = "MONEY", stream = "mine", gain = "money", money = 1 },
  { key = "LOOT_MONEY_SPLIT", ct = "MONEY", stream = "mine", gain = "money", money = 1 },
  { key = "COMBATLOG_XPGAIN_EXHAUSTION1", ct = "COMBAT_XP_GAIN", stream = "mine", gain = "xp", num = 2 },
  { key = "COMBATLOG_XPGAIN_EXHAUSTION2", ct = "COMBAT_XP_GAIN", stream = "mine", gain = "xp", num = 2 },
  { key = "COMBATLOG_XPGAIN_EXHAUSTION4", ct = "COMBAT_XP_GAIN", stream = "mine", gain = "xp", num = 2 },
  { key = "COMBATLOG_XPGAIN_EXHAUSTION5", ct = "COMBAT_XP_GAIN", stream = "mine", gain = "xp", num = 2 },
  { key = "COMBATLOG_XPGAIN_FIRSTPERSON", ct = "COMBAT_XP_GAIN", stream = "mine", gain = "xp", num = 2 },
  {
    key = "COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED",
    ct = "COMBAT_XP_GAIN",
    stream = "mine",
    gain = "xp",
    num = 1,
  },
  {
    key = "FACTION_STANDING_INCREASED",
    ct = "COMBAT_FACTION_CHANGE",
    stream = "mine",
    gain = "rep",
    name = 1,
    num = 2,
  },
  {
    key = "FACTION_STANDING_DECREASED",
    ct = "COMBAT_FACTION_CHANGE",
    stream = "mine",
    gain = "rep",
    name = 1,
    num = 2,
    sign = -1,
  },
  { key = "ERR_QUEST_REWARD_EXP_I", ct = "SYSTEM", stream = "mine", gain = "xp", num = 1 },
  { key = "ERR_QUEST_REWARD_MONEY_S", ct = "SYSTEM", stream = "mine", gain = "money", money = 1 },
  { key = "ERR_QUEST_REWARD_ITEM_S", ct = "SYSTEM", stream = "mine", gain = "item" },
  { key = "ERR_ZONE_EXPLORED_XP", ct = "SYSTEM", stream = "mine", gain = "xp", num = 2 },
  { key = "ERR_ZONE_EXPLORED", ct = "SYSTEM", stream = "mine" },
  { key = "ERR_QUEST_ACCEPTED_S", ct = "SYSTEM", stream = "mine" },
  { key = "ERR_QUEST_COMPLETE_S", ct = "SYSTEM", stream = "mine", gain = "quest" }, -- V22
  { key = "ERR_LEARN_RECIPE_S", ct = "SYSTEM", stream = "mine" },
  { key = "ERR_LEARN_SPELL_S", ct = "SYSTEM", stream = "mine" },
  { key = "ERR_LEARN_ABILITY_S", ct = "SYSTEM", stream = "mine" },
  { key = "ERR_TRADE_COMPLETE", ct = "SYSTEM", stream = "mine" },
  { key = "INSTANCE_SAVED", ct = "SYSTEM", stream = "mine" },
  { key = "MARKED_AFK_MESSAGE", ct = "SYSTEM", stream = "mine" },
  { key = "MARKED_AFK", ct = "SYSTEM", stream = "mine" },
  { key = "CLEARED_AFK", ct = "SYSTEM", stream = "mine" },
  { key = "MARKED_DND", ct = "SYSTEM", stream = "mine" },
  { key = "CLEARED_DND", ct = "SYSTEM", stream = "mine" },
  { key = "ERR_JOINED_GROUP_S", ct = "SYSTEM", stream = "group" },
  { key = "ERR_LEFT_GROUP_S", ct = "SYSTEM", stream = "group" },
  { key = "ERR_RAID_MEMBER_ADDED_S", ct = "SYSTEM", stream = "group" },
  { key = "ERR_RAID_MEMBER_REMOVED_S", ct = "SYSTEM", stream = "group" },
  { key = "ERR_NEW_LEADER_S", ct = "SYSTEM", stream = "group" },
  { key = "RANDOM_ROLL_RESULT", ct = "SYSTEM", stream = "group" },
  { key = "ERR_FRIEND_ONLINE_SS", ct = "SYSTEM", stream = "addons", kind = "online", name = 1 },
  { key = "ERR_FRIEND_OFFLINE_S", ct = "SYSTEM", stream = "addons", kind = "online", name = 1 },
  { key = "ERR_GUILD_JOIN_S", ct = "SYSTEM", stream = "guild" },
  { key = "ERR_GUILD_LEAVE_S", ct = "SYSTEM", stream = "guild" },
  { key = "GUILD_MOTD_TEMPLATE", ct = "SYSTEM", stream = "guild" },
}

-- English forms of those strings for a client that lacks one (the clients have them all; the
-- mock and the tests have these)
Relevance.SYSTEM_EN = {
  LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d.",
  LOOT_ITEM_SELF = "You receive loot: %s.",
  LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d.",
  LOOT_ITEM_PUSHED_SELF = "You receive item: %s.",
  LOOT_ITEM_CREATED_SELF_MULTIPLE = "You create: %sx%d.",
  LOOT_ITEM_CREATED_SELF = "You create: %s.",
  LOOT_ROLL_YOU_WON = "You won: %s",
  LOOT_ITEM_MULTIPLE = "%s receives loot: %sx%d.",
  LOOT_ITEM = "%s receives loot: %s.",
  LOOT_ROLL_WON = "%s won: %s",
  YOU_LOOT_MONEY = "You loot %s",
  LOOT_MONEY_SPLIT = "Your share of the loot is %s.",
  COMBATLOG_XPGAIN_EXHAUSTION1 = "%s dies, you gain %d experience. (%s exp %s bonus)",
  COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience.",
  COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED = "You gain %d experience.",
  FACTION_STANDING_INCREASED = "Reputation with %s increased by %d.",
  FACTION_STANDING_DECREASED = "Reputation with %s decreased by %d.",
  ERR_QUEST_REWARD_EXP_I = "Experience gained: %d.",
  ERR_QUEST_REWARD_MONEY_S = "Received %s.",
  ERR_QUEST_REWARD_ITEM_S = "Received item: %s.",
  ERR_ZONE_EXPLORED_XP = "Discovered %s: %d experience gained",
  ERR_ZONE_EXPLORED = "Discovered: %s",
  ERR_QUEST_ACCEPTED_S = "Quest accepted: %s",
  ERR_QUEST_COMPLETE_S = "%s completed.",
  ERR_LEARN_RECIPE_S = "You have learned how to create a new item: %s.",
  ERR_LEARN_SPELL_S = "You have learned a new spell: %s.",
  ERR_TRADE_COMPLETE = "Trade complete.",
  MARKED_AFK_MESSAGE = "You are now AFK: %s",
  MARKED_AFK = "You are now AFK.",
  CLEARED_AFK = "You are no longer AFK.",
  ERR_JOINED_GROUP_S = "%s joins the party.",
  ERR_LEFT_GROUP_S = "%s leaves the party.",
  RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)",
  ERR_FRIEND_ONLINE_SS = "|Hplayer:%s|h[%s]|h has come online.",
  ERR_FRIEND_OFFLINE_S = "%s has gone offline.",
  ERR_GUILD_JOIN_S = "%s has joined the guild.",
  ERR_GUILD_LEAVE_S = "%s has left the guild.",
}

-- The entries with their patterns, grouped by chat type; `lookup(key)` answers the client's
-- string (a missing one leaves its entry out).
function Relevance.CompileSystem(lookup)
  local out = {}
  for _, entry in ipairs(Relevance.SYSTEM) do
    local fmt = lookup(entry.key)
    local pattern = Record.Pattern(fmt)
    if pattern then
      local e = {}
      for k, v in pairs(entry) do
        e[k] = v
      end
      e.pattern = pattern
      out[entry.ct] = out[entry.ct] or {}
      table.insert(out[entry.ct], e)
    end
  end
  return out
end

-- A Game Master or a Blizzard developer (the whisper's sixth argument, probe X2).
function Relevance.IsGM(flags)
  return flags == "GM" or flags == "DEV"
end

-- Why an offer or a group is on the watch list (plan-chat-v3.md V19), or nil. watch = { items =
-- { [id] = true }, dungeons = { [name] = true } (the player's own), quests = { [id] = { need,
-- have, quest, title } } (progress:NeededItems), range = fn(dungeon) -> bool or nil }. Answers
-- { why = "own" | "quest" | "range", title, need }: an item of the player's list sold or bought,
-- an item a quest needs sold, a group for a dungeon of the list or (with range) for the level.
function Relevance.Watch(it, watch)
  if type(it) ~= "table" or type(watch) ~= "table" then
    return nil
  end
  if it.item and (it.kind == "wts" or it.kind == "wtb") then
    if watch.items and watch.items[it.item] then
      return { why = "own" }
    end
    local q = it.kind == "wts" and watch.quests and watch.quests[it.item]
    if type(q) == "table" then
      return { why = "quest", title = q.title, need = q.need }
    end
  end
  if it.dungeon and it.kind == "lfm" then
    if watch.dungeons and watch.dungeons[it.dungeon] then
      return { why = "own" }
    end
    if watch.range and watch.range(it.dungeon) then
      return { why = "range" }
    end
  end
  return nil
end

-- The ask a record makes, or nil.
local function ask(rec, stream, facts)
  local ct, who = rec.chatType, rec.who
  local name = who and who.name
  if rec.secret or rec.junk or rec.own then
    return nil
  end
  if stream == "direct" and INCOMING[ct] and (name or (who and who.bn)) then
    return { kind = "whisper", who = name, rel = who.rel, bn = who.bn }
  end
  if ct == "RAID_WARNING" then
    return { kind = "warning", who = name }
  end
  local it = rec.intent
  local found = it and facts.watch and Relevance.Watch(it, facts.watch)
  if found then
    rec.watch = found.why
    return {
      kind = "watch",
      who = name,
      item = it.item,
      dungeon = it.dungeon,
      why = found.why,
      title = found.title,
      need = found.need,
    }
  end
  if
    Intent.PEOPLE[ct]
    and rec.plain
    and facts.mentions
    and #facts.mentions > 0
    and Words.Has(rec.plain, facts.mentions)
  then
    return { kind = "mention", who = name, rel = who and who.rel, chatType = ct, channel = rec.channel }
  end
  return nil
end

-- Fills rec.stream, rec.tier, rec.who.rel, rec.ask (and rec.sys, rec.caps for a line the
-- client's strings sorted). facts = { rel = fn(name) -> relation, system = CompileSystem(...),
-- mentions = { lowercase words }, words = Words.For(locale), watch = { items, dungeons },
-- grouped = fn(name) -> is in the player's group }.
function Relevance.Rank(rec, facts)
  local ct, who = rec.chatType, rec.who
  -- the player's own whisper: the client names the partner as its sender
  local inform = ct == "WHISPER_INFORM" or ct == "BN_WHISPER_INFORM"
  if inform then
    rec.own = true
  end
  if who then
    if ct == "BN_WHISPER" or ct == "BN_WHISPER_INFORM" then
      who.rel = "bnet"
    elseif rec.own and not inform then
      who.rel = "self"
    elseif who.name and facts.rel and not who.rel then
      who.rel = facts.rel(who.name)
    end
    -- say, yell and emotes follow the speaker (plan-chat-two-decks.md §1): a group member's
    -- are the group's, whatever else the player knows them as
    if SPEECH[ct] and who.name and facts.grouped and not rec.own then
      who.grouped = facts.grouped(who.name) or nil
    end
    if Relevance.IsGM(who.flags) then
      who.rel = "gm"
    end
  end
  local stream
  if rec.junk then
    stream = "junk"
  elseif not ct then
    stream = "addons"
  else
    stream = Relevance.STREAM_OF[ct] or "addons"
    if not rec.secret and facts.system and facts.system[ct] then
      local entry, caps = Record.Match(rec.body, facts.system[ct])
      if entry then
        rec.sys, rec.caps = entry, caps
        stream = entry.stream
        if entry.kind == "online" then
          local rel = facts.rel and caps[entry.name] and facts.rel(caps[entry.name])
          stream = rel == "guild" and "guild" or FRIENDLY[rel] and "direct" or "addons"
          rec.online = true
        end
      end
    end
    if ct == "ACHIEVEMENT" and rec.own then
      stream = "mine"
    end
    -- say, yell and the channels are sorted by what the line wants (V45: said and yelled lines
    -- too, and services); a group member's say and yell stay the group's
    if ns.Intent.PUBLIC[ct] and not rec.secret and not (who and who.grouped) then
      local kind
      if ct == "CHANNEL" or ct == "COMMUNITIES_CHANNEL" then
        kind = facts.words and Words.ChannelKind(facts.words, rec.channel)
        rec.channelKind = kind
      end
      local it = rec.intent
      if it and (it.kind == "wts" or it.kind == "wtb" or it.kind == "service") then
        stream = "market"
      elseif kind == "lfg" or (it and (it.kind == "lfm" or it.kind == "lfg")) then
        stream = "lfg"
      end
    end
  end
  local tier = Relevance.TIER_OF[stream] or 4
  if rec.secret then
    -- shown as it came, never read: the tier of its chat type, never "needs you" by its words
    tier = SOCIAL[stream] and 1 or (stream == "mine" and 2 or 4)
  elseif stream == "direct" then
    tier = (INCOMING[ct] and not rec.own) and 0 or (rec.online and 4 or 1)
    rec.auto = (ct == "AFK" or ct == "DND") or nil
  elseif stream == "group" and ct == "LOOT" then
    local link = Record.Link(rec, "item")
    tier = (link and link.quality and link.quality >= 3) and 1 or 4
  elseif stream == "group" and ct == "SYSTEM" then
    tier = 4
  elseif stream == "world" and (rec.own or (who and FRIENDLY[who.rel])) then
    tier = 1
  end
  if stream ~= "junk" and stream ~= "addons" and rec.own and tier > 1 and stream ~= "mine" then
    tier = 1
  end
  if rec.online then
    tier = 4 -- someone came or went: worth a glance, in the stream of who they are
  end
  rec.stream = stream
  rec.ask = not rec.secret and ask(rec, stream, facts) or nil
  if rec.ask then
    tier = 0
  end
  rec.tier = tier
  return rec
end
