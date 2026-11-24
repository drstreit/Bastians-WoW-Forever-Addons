-- Bastian's Chat (chat.md, ADR 0042): the module. Takes every finished line from the game's chat
-- frames, which stay alive under a hidden parent, runs it through the spam rules, hands it to the
-- store, the people's conversations and the tabs, moves the game's input bars into our window
-- (with their history and the shell keys), keeps the scrollback, and puts the game's chat back
-- when switched off.
local ADDON, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
local L = ns.L
local S = B.UI.Style
local Model, Compat, Rules, Keys = ns.Model, ns.Compat, ns.Rules, ns.Keys
local Words, Record, Intent, Relevance, Store = ns.Words, ns.Record, ns.Intent, ns.Relevance, ns.Store

local Chat = {}
ns.Chat = Chat

Chat.SEEN_MAX = 400 -- remembered line ids: a line two of the game's frames show is taken once
Chat.BOX_LETTERS = 255 -- the game's bar holds this many letters, we lift it for long texts
Chat.TRUST_SECS = 60 -- how long a trust answer (friend, guild, group) is kept per sender
-- the lines that show a roleplay name (plan-launch-version L3): what is said where people stand
Chat.RP_TYPES = { SAY = true, YELL = true, EMOTE = true, TEXT_EMOTE = true }
-- the players' emotes (/e and /wave), drawn in the scheme's chatEmote (chat.md "Emotes for roleplay")
Chat.EMOTES = { EMOTE = true, TEXT_EMOTE = true }

local mod
local active = false -- the game's chat is replaced right now
local wanted = false -- switched on, waiting for the end of combat
local reloading = false
local hooked, boxHooked = {}, {} -- frames and bars hooked once per session (a hook stays)
local lastEvent = {} -- [frame] = the event the frame's next AddMessage shows
local seen, seenOrder = {}, {}
local moved = {} -- { frame, parent }: the game's chat parts under our hidden parent
local boxes = {} -- [bar] = its home: { parent, points, letters, bytes, alt }
local typed = {} -- [bar] = { cur, cleared, clearedAt, search }: what the bar held, for the history
local fed = {} -- [bar] = true once the kept history is in it
local spam = Rules.NewState()
local compiled
local trust = {} -- [sender] = { yes, at }
local insideInstance = false
-- the clear-screen key (plan-launch-review R5.6): true while it hides the chat; peek = { box, shown }
-- while Enter brought the main window up for one line
local suiteHidden, peek = false, nil
local hidden = CreateFrame("Frame")
hidden:Hide()

function Chat.DB()
  return mod.db
end

function Chat.Active()
  return active
end

-- A failure inside a hook (the hooks are the module's boundary, CLAUDE.md §5): counted, logged,
-- and the last ones kept in the saved variables (`global.lastErrors`), so a round in game leaves
-- them readable without BugSack; `/bchat errors` prints them, the Inbox's foot counts them.
Chat.ERRORS_KEPT = 12
function Chat.Note(where, err)
  mod.noted = mod.noted or {} -- not `errors`: Core counts a module's errors there
  mod.noted[where] = (mod.noted[where] or 0) + 1
  if err then
    mod:Log("error", "%s: %s", where, tostring(err))
    local g = mod.db and mod.db.global
    if g then
      g.lastErrors = type(g.lastErrors) == "table" and g.lastErrors or {}
      table.insert(g.lastErrors, { at = time(), where = where, text = tostring(err):sub(1, 400) })
      while #g.lastErrors > Chat.ERRORS_KEPT do
        table.remove(g.lastErrors, 1)
      end
    end
  end
end

-- How many failures this session (the Inbox's foot).
function Chat.ErrorCount()
  local n = 0
  for _, c in pairs(mod.noted or {}) do
    n = n + c
  end
  return n
end

-- /bchat errors: the kept failures, the newest last.
function Chat.SayErrors()
  local list = mod.db.global.lastErrors
  if type(list) ~= "table" or #list == 0 then
    B:Say(L["Bastian's Chat has no errors noted."])
    return
  end
  for _, e in ipairs(list) do
    B:Say("%s %s: %s", date("%d.%m. %H:%M", e.at or 0), tostring(e.where), tostring(e.text))
  end
end

-- A method the client may lack, called without raising: the value, or nil.
local function try(obj, method, ...)
  local args = { ... }
  local ok, value = pcall(function()
    return obj[method](obj, unpack(args))
  end)
  return ok and value or nil
end

local function guard(where, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    Chat.Note(where, err)
  end
end

-- ---------------------------------------------------------------------------------------------
-- Spam (ADR 0042 §7)
-- ---------------------------------------------------------------------------------------------

function Chat.Rules()
  if not compiled then
    compiled = Rules.Compile(mod.db.profile.spam)
  end
  return compiled
end

function Chat.RulesChanged()
  compiled = nil
  if mod.db.profile.spam.applyOld ~= false then
    Chat.Refilter()
  end
end

-- The rules onto the lines already shown ("immediately filter the whole
-- chat, not only new ones"): every kept line of every tab is judged again (the timeless part of
-- the rules: senders, words, web addresses); a line the rules take now leaves its tabs and the
-- saved scrollback and lands in Junk, a dimmed one is redrawn dim. Returns the lines taken.
function Chat.Refilter()
  if not active then
    return {}
  end
  local rules = Chat.Rules()
  local taken = ns.View.Refilter(function(line)
    local verdict = Rules.Judge(spam, rules, line, Chat.Trusted)
    if verdict then
      line.reason, line.word = verdict.reason, verdict.word
    end
    return verdict
  end)
  for _, line in ipairs(taken) do
    ns.Junk.Add(line)
  end
  return taken
end

-- Drops a kept line from a tab's saved scrollback (the text and the time name it).
function Chat.Unkeep(tabId, line)
  local sb = mod.db.char.scrollback[tabId]
  if not sb then
    return
  end
  for i = #sb, 1, -1 do
    local l = sb[i]
    if l.text == line.text and l.at == line.at then
      table.remove(sb, i)
    end
  end
end

-- S2: the player, friends, guild, group (asked once a minute per sender), and every contact.
function Chat.Trusted(sender)
  local convo = mod.db.global.convos[sender]
  if convo and Model.HasOwnLine(convo) then
    return true
  end
  local t = trust[sender]
  local now = GetTime()
  if not t or now - t.at > Chat.TRUST_SECS then
    t = { yes = Compat.IsTrusted(sender), at = now }
    trust[sender] = t
  end
  return t.yes
end

function Chat.Allow(sender)
  Rules.Allow(spam, sender)
end

function Chat.BlockSender(name)
  if type(name) == "string" and name ~= "" then
    mod.db.profile.spam.senders[name] = true
    Chat.RulesChanged()
    B:Say(L["%s is blocked in Bastian's Chat (the Junk window lifts it)."], Model.ShortName(name))
  end
end

-- "Mute <name> in <channel>" (plan-chat-one-window.md §5, Better Forever Chat's): that sender's
-- lines in that channel go to Junk with the reason "muted"; the Junk window's Not junk lifts it for
-- the session, the profile keeps it (`spam.muted`).
function Chat.Mute(name, rec)
  if type(name) ~= "string" or name == "" or type(rec) ~= "table" then
    return nil
  end
  local rules = mod.db.profile.spam
  rules.muted = type(rules.muted) == "table" and rules.muted or {}
  local key = ns.Menus.MuteKey(name, rec)
  rules.muted[key] = true
  B:Say(L["%s is muted in this channel (the Junk window shows the lines)."], Model.ShortName(name))
  return key
end

-- Is a captured line muted (its sender in its channel)?
function Chat.IsMuted(line)
  local muted = mod.db.profile.spam.muted
  if type(muted) ~= "table" or not next(muted) or not line.sender or line.own then
    return false
  end
  local kind = line.channel and Words.ChannelKind(Chat.Facts().words, line.channel) or nil
  return muted[ns.Menus.MuteKey(
    line.sender,
    { channelKind = kind, channel = line.channel, chatType = line.chatType }
  )] == true
end

function Chat.UnblockSender(name)
  mod.db.profile.spam.senders[name] = nil
  Chat.RulesChanged()
end

-- ---------------------------------------------------------------------------------------------
-- The store of version 3 (plan-chat-v3.md §1, ADR 0075): every line also becomes a record, fed
-- beside the version 2 view until the new views read it (package V1)
-- ---------------------------------------------------------------------------------------------

Chat.MENTIONS_SECS = 60 -- the player's names and the guild's are read again after this long
local store = Store.New()
local facts
local soundsAttached = false -- the store's listener for the sounds (V24), once
local relations = {} -- [name] = { rel, at }

function Chat.Store()
  return store
end

-- How the player knows a writer (friend, guild, group, stranger), asked once a minute per name.
function Chat.Relation(name)
  local r = relations[name]
  local now = GetTime()
  if not r or now - r.at > Chat.TRUST_SECS then
    r = { rel = Compat.Relation(name), at = now }
    relations[name] = r
  end
  return r.rel
end

-- The words that make a line the player's (plan §2.2): the character's name, the guild's name,
-- the player's own words (the profile's `mentions`, separated by commas). Lowercase.
function Chat.MentionWords()
  local out = {}
  local function add(word)
    if type(word) == "string" and word ~= "" then
      out[#out + 1] = word:lower()
    end
  end
  local me = Compat.PlayerName()
  add(me and (me:match("^([^%-]+)") or me))
  add(Compat.GuildName())
  for word in string.gmatch(mod.db.profile.mentions or "", "[^,]+") do
    add(strtrim(word))
  end
  return out
end

-- What the pure modules need to sort a line, built once (the mentions renewed once a minute).
function Chat.Facts()
  local now = GetTime()
  if not facts then
    local words = Words.For(GetLocale())
    facts = {
      words = words,
      system = Relevance.CompileSystem(function(key)
        local v = _G[key]
        return type(v) == "string" and v or Relevance.SYSTEM_EN[key]
      end),
      rel = Chat.Relation,
      grouped = Compat.Grouped,
    }
  end
  if not facts.mentionsAt or now - facts.mentionsAt > Chat.MENTIONS_SECS then
    facts.mentions, facts.mentionsAt = Chat.MentionWords(), now
    facts.watch = Chat.WatchFacts() -- the watch list with them (V19)
  end
  return facts
end

-- ---------------------------------------------------------------------------------------------
-- The watch list (plan-chat-v3.md §10.3, V19): the items the quests still need (the `progress`
-- service), the player's own items and dungeons, the dungeons in range when switched on.
-- ---------------------------------------------------------------------------------------------

-- The watch list's facts for Relevance.Watch.
function Chat.WatchFacts()
  local p = mod.db.profile
  local own = type(p.watch) == "table" and p.watch or {}
  local quests = {}
  local progress = B:GetService("progress")
  if progress and type(progress.NeededItems) == "function" then
    local ok, items = pcall(progress.NeededItems, progress)
    if ok and type(items) == "table" then
      quests = items
    end
  end
  return {
    items = type(own.items) == "table" and own.items or {},
    dungeons = type(own.dungeons) == "table" and own.dungeons or {},
    quests = quests,
    range = p.watchRange and Chat.InRange or nil,
  }
end

-- Whether a dungeon's levels (Data's record) hold the player's level; false when unknown.
function Chat.InRange(name)
  local band = ns.Rows.Band(name)
  local level = Compat.PlayerLevel()
  return band ~= nil and type(level) == "number" and level >= band[1] and level <= band[2]
end

-- The list or the quests changed: the facts are built again for the next line.
function Chat.WatchChanged()
  if facts then
    facts.mentionsAt = nil
  end
end

-- ---------------------------------------------------------------------------------------------
-- Sounds (plan-chat-v3.md §9, V24): one per kind of request and per stream, "none" by default
-- ---------------------------------------------------------------------------------------------

Chat.SOUND_ASKS = { "whisper", "gm", "mention", "request", "ready", "warning", "watch" }
Chat.SOUND_STREAMS = { "group", "guild", "market", "lfg" }
Chat.SOUND_GAP = 2 -- seconds between two sounds of one stream
local REQUEST_KINDS = { invite = true, duel = true, trade = true, summon = true, resurrect = true }
local askState = {} -- [ask id] = its state when last seen: a request rings when it opens
local streamRung = {} -- [stream] = GetTime() of its last sound

-- The sound kind of a request, or nil for one that never rings (Away's own cards, a kind deed).
function Chat.SoundKind(ask)
  if ask.rel == "gm" then
    return "gm"
  end
  if REQUEST_KINDS[ask.kind] then
    return "request"
  end
  for _, kind in ipairs(Chat.SOUND_ASKS) do
    if kind == ask.kind then
      return kind
    end
  end
  return nil
end

local function soundsOn()
  return active and ns.View.LayoutKind() ~= "tabs" and not ns.Away.On()
end

local function play(name)
  if type(name) == "string" and name ~= "none" then
    Compat.PlaySound(name)
  end
end

-- The store's news: a request that opens, a line of a stream with a sound.
function Chat.OnStoreSound(what, value)
  local s = mod.db.profile.sounds or {}
  if what == "ask" then
    local was = askState[value.id]
    askState[value.id] = value.state
    if value.state ~= "open" or was == "open" or not soundsOn() then
      return
    end
    if ns.Combat.Fighting() and not ns.Combat.Pops(value) then
      return -- in a fight only what pops up rings (V11)
    end
    local kind = Chat.SoundKind(value)
    local notify = mod.db.profile.inbox and mod.db.profile.inbox.notify
    local rec = value.last and store:Get(value.last)
    if type(notify) == "table" and rec and notify[rec.stream] == "none" and kind == "mention" then
      return -- a place set to "nothing" stays quiet, its mentions too (V33)
    end
    play(kind and s.asks and s.asks[kind])
  elseif what == "add" then
    local name = s.streams and s.streams[value.stream]
    -- a place's notification (V33, the place's right click): every line rings (its sound, or a
    -- chime), only the player's name or nothing leaves the stream quiet
    local notify = mod.db.profile.inbox and mod.db.profile.inbox.notify
    notify = type(notify) == "table" and notify[value.stream] or nil
    if notify == nil and ns.View.LayoutKind() == "decks" then
      -- the decks' level of the place (plan-chat-two-decks.md §6): its default keeps a stream
      -- quiet (Guild, Know's places), "everything" leaves it its sound
      local level = ns.Decks.Level(value.stream)
      notify = level ~= "all" and level or nil
    end
    if notify == "all" and (not name or name == "none") then
      name = "chime"
    elseif notify == "name" or notify == "none" then
      name = nil
    end
    if not name or name == "none" or value.own or value.ask or not soundsOn() then
      return -- a request rings as one (above)
    end
    if not ns.Combat.Draws(value) then
      return
    end
    local now = GetTime()
    if now - (streamRung[value.stream] or -100) >= Chat.SOUND_GAP then
      streamRung[value.stream] = now
      play(name)
    end
  end
end

-- An item's name for the chat's own lines.
local function itemLabel(id)
  local e = B:Entity("item:" .. id)
  local name = e and e:Name()
  return name and ("[" .. name .. "]") or ("item " .. id)
end

-- Puts an item (its id) or a dungeon (its English name) on the player's list, or takes it off;
-- says which and draws the boards again. Returns true when it is on the list now.
function Chat.ToggleWatch(kind, value, label)
  local p = mod.db.profile
  p.watch = type(p.watch) == "table" and p.watch or {}
  local key = kind == "item" and "items" or "dungeons"
  p.watch[key] = type(p.watch[key]) == "table" and p.watch[key] or {}
  local on = not p.watch[key][value]
  p.watch[key][value] = on or nil
  Chat.WatchChanged()
  label = label or (kind == "item" and itemLabel(value) or value)
  B:Say(on and L["Watching %s."] or L["No longer watching %s."], label)
  if active and ns.Front.Frame() then
    ns.Front.Rebuild() -- the boards' gold edges (V19)
  end
  return on
end

-- /bchat watch [item link or dungeon], /bchat unwatch [the same]; without one: the list.
function Chat.WatchCommand(verb, text)
  local p = mod.db.profile
  local own = type(p.watch) == "table" and p.watch or {}
  if text == "" then
    local names = {}
    for id in pairs(own.items or {}) do
      names[#names + 1] = itemLabel(id)
    end
    for name in pairs(own.dungeons or {}) do
      names[#names + 1] = name
    end
    table.sort(names)
    if #names == 0 then
      B:Say(L["Your watch list is empty."])
    else
      B:Say(L["Your watch list: %s"], table.concat(names, ", "))
    end
    return
  end
  local kind, value, label
  local id = tonumber(text:match("|Hitem:(%d+)") or text:match("^item:(%d+)$") or "")
  if id then
    kind, value, label = "item", id, text:match("(|c%x+|Hitem:.-|h.-|h|r)") or itemLabel(id)
  else
    local dungeon = Words.Dungeon(Chat.Facts().words, string.lower(text))
    if dungeon then
      kind, value, label = "dungeon", dungeon, dungeon
    end
  end
  if not kind then
    B:Say(L["Name an item (Shift+click its link) or a dungeon: /bchat watch Deadmines"])
    return
  end
  local list = own[kind == "item" and "items" or "dungeons"]
  local isOn = type(list) == "table" and list[value] == true
  if (verb == "watch") ~= isOn then
    Chat.ToggleWatch(kind, value, label)
  else
    B:Say(isOn and L["Watching %s."] or L["No longer watching %s."], label)
  end
end

-- A captured line as a record in the store; `junk` when the spam rules took it. A repeat the
-- rules folded counts only when it is an offer or a group: its repost moves the board's card
-- ("posted 3x", plan §1); any other repeat stays out.
function Chat.Record(line, junk, repeated)
  local f = Chat.Facts()
  local rec = Record.Build(line)
  rec.junk = junk or nil
  Intent.Apply(rec, f.words)
  if repeated and not rec.key then
    return nil
  end
  Relevance.Rank(rec, f)
  Intent.Gain(rec, f.words)
  rec.via = ns.Requests.Via(rec) -- a line Courtesy or Gestures sent (V6)
  store:Add(rec)
  ns.Away.OnRecord(rec) -- while away, the whisper's answer (V10)
  return rec
end

-- /bchat store: what the store holds, as counts (never a name or a word).
function Chat.SayStore()
  local c = store:Counts(time())
  local parts = {}
  for _, id in ipairs(Store.STREAMS) do
    parts[#parts + 1] = id .. " " .. c.streams[id]
  end
  B:Say(L["Chat's records by stream: %s"], table.concat(parts, ", "))
  local tiers = {}
  for tier = 0, 5 do
    tiers[#tiers + 1] = tier .. ": " .. c.tiers[tier]
  end
  B:Say(L["By tier since the start: %s; open requests: %d"], table.concat(tiers, ", "), c.asks)
end

-- A captured line: the spam verdict, then the conversations (a whisper) and the tabs.
function Chat.Route(line)
  local verdict, foldKey
  if not line.secret and Chat.IsMuted(line) and not spam.allowed[line.sender] then
    verdict = { action = "junk", reason = "muted" } -- muted in this channel (V33)
  elseif not line.secret then
    verdict, foldKey = Rules.Check(spam, Chat.Rules(), line, GetTime(), Chat.Trusted)
  end
  if verdict then
    line.reason, line.word = verdict.reason, verdict.word
    if verdict.action == "fold" then
      ns.View.Fold(verdict.foldKey, verdict.count)
      guard("store", Chat.Record, line, false, true)
      return "fold"
    elseif verdict.action == "dim" then
      line.dim = true
    else
      ns.Junk.Add(line)
      guard("store", Chat.Record, line, true)
      return verdict.action
    end
  end
  guard("store", Chat.Record, line)
  line.foldKey = foldKey
  if line.cat == "whisper" or line.cat == "bnet" then
    ns.People.Add(line) -- its person's place (plan-chat-one-window.md §3)
  end
  ns.View.Add(line)
  return verdict and verdict.action or "show"
end

-- ---------------------------------------------------------------------------------------------
-- Capture: the event a frame is about to show, then the finished line
-- ---------------------------------------------------------------------------------------------

-- A channel line's number (the event's eighth argument, else the "2. Trade" of its channel
-- string), so a click on it can answer there (plan-chat-v3.md §4, V5); nil when there is none.
function Chat.ChannelNumber(index, channelString)
  if type(index) == "number" and index > 0 then
    return index
  end
  local n = type(channelString) == "string" and tonumber(channelString:match("^(%d+)%.")) or nil
  return n and n > 0 and n or nil
end

local function onFilter(frame, event, ...)
  if active and frame ~= Compat.CombatLogFrame() then
    local text, sender, _, channelString, _, flags, zoneChannel, chanIndex, channelName = ...
    local lineID, guid, bnID = select(11, ...)
    local secret = Compat.IsSecret(text)
    local base = Compat.Plain(channelName)
    if type(base) ~= "string" or base == "" then
      base = type(Compat.Plain(channelString)) == "string" and channelString:match("^%d+%.%s*(.-)$") or nil
    end
    lastEvent[frame] = {
      event = event,
      sender = Compat.Plain(sender),
      zoneChannel = Compat.Plain(zoneChannel),
      lineID = Compat.Plain(lineID),
      channel = base,
      channelNumber = Chat.ChannelNumber(Compat.Plain(chanIndex), Compat.Plain(channelString)),
      bnID = Compat.Plain(bnID),
      guid = Compat.Plain(guid),
      flags = Compat.Plain(flags), -- "GM", "DEV", "AFK", ... (plan-chat-v3.md §3.2, probe X2)
      msg = not secret and Compat.Plain(text) or nil,
      secret = secret,
      at = GetTime(),
    }
  end
  return false
end

local function remember(key)
  if seen[key] then
    return true
  end
  seen[key] = true
  seenOrder[#seenOrder + 1] = key
  if #seenOrder > Chat.SEEN_MAX then
    seen[table.remove(seenOrder, 1)] = nil
  end
  return false
end

local me -- the player's "Name-Realm", read at the start

-- The line a frame shows, as the model's line, or nil when it is not ours to take.
function Chat.Line(frame, text, r, g, b)
  if frame == Compat.CombatLogFrame() then
    return nil
  end
  local ev = lastEvent[frame]
  lastEvent[frame] = nil
  if ev and ev.at ~= GetTime() then
    ev = nil -- a filter whose line never came (another addon dropped it)
  end
  if not ev and frame ~= DEFAULT_CHAT_FRAME then
    return nil -- prints without an event: from the default frame only
  end
  if ev then
    -- the same line in two frames: by its id, or (system lines carry id 0) by its text this frame
    local key
    if type(ev.lineID) == "number" and ev.lineID > 0 then
      key = ev.event .. ":" .. ev.lineID
    elseif not ev.secret and type(text) == "string" then
      key = ev.event .. ":" .. ev.at .. ":" .. text
    end
    if key and remember(key) then
      return nil
    end
  end
  local chatType = ev and Model.ChatType(ev.event)
  local line = {
    text = text,
    r = r,
    g = g,
    b = b,
    at = time(),
    chatType = chatType,
    cat = Model.Category(chatType),
    zoneChannel = ev and ev.zoneChannel,
    channel = ev and ev.channel,
    channelNumber = ev and ev.channelNumber,
    sender = ev and ev.sender,
    bnID = ev and ev.bnID,
    guid = ev and ev.guid,
    flags = ev and ev.flags,
    msg = ev and ev.msg,
    secret = (ev and ev.secret) or Compat.IsSecret(text),
  }
  if not line.secret then
    local source = line.msg or (type(text) == "string" and text) or ""
    line.plain = Model.Strip(source):lower()
  end
  if Chat.EMOTES[chatType] then
    -- roleplay (S9, L5): the scheme's emote colour instead of the game's, kept with the line
    local c = S.C.chatEmote
    line.r, line.g, line.b = c[1], c[2], c[3]
  end
  line.own = line.sender ~= nil and (line.sender == me or line.sender == UnitName("player"))
  if line.cat == "whisper" or line.cat == "bnet" then
    line.partner = line.sender
    if not line.partner then
      line.cat = "system" -- a secret sender: the line goes to General, without a conversation
    end
  end
  line.public = Model.IsPublic(line)
  if Chat.RP_TYPES[chatType] and line.sender and not line.secret and mod.db.profile.rpNames then
    -- the speaker's roleplay name (msp, read only), else ask for it once in a while
    local rp = B.Compat.MspName(line.sender)
    if rp then
      line.text = Model.WithRoleplayName(line.text, line.sender, rp.name)
      line.rpName = rp.name
    else
      B.Compat.MspRequest(line.sender)
    end
  end
  return line
end

local function onAddMessage(frame, text, r, g, b)
  if not active then
    return
  end
  local line = Chat.Line(frame, text, r, g, b)
  if line then
    Chat.Route(line)
  end
end

-- Never the combat log: its lines are not ours, and a hook on its AddMessage broke the game's
-- handler there (CHAT_MSG_TRADESKILLS, "attempt to call a nil value", retail 31.10.2026).
function Chat.HookFrames()
  local log = Compat.CombatLogFrame()
  for _, name in ipairs(Compat.ChatFrameNames()) do
    local f = _G[name]
    if f and f ~= log and not hooked[f] and type(f.AddMessage) == "function" then
      hooked[f] = true
      hooksecurefunc(f, "AddMessage", function(...)
        guard("capture", onAddMessage, ...)
      end)
    end
  end
end

-- ---------------------------------------------------------------------------------------------
-- The game's chat under our hidden parent, and back
-- ---------------------------------------------------------------------------------------------

local logOut = {} -- [frame] = true: the combat log out as a window, HideGame leaves it alone

local function stash(f)
  if type(f) ~= "table" or type(f.SetParent) ~= "function" then
    return
  end
  local parent = f:GetParent()
  if parent == hidden or boxes[f] or logOut[f] then
    return
  end
  for _, wid in ipairs(ns.View.Windows()) do
    local W = ns.View.Window(wid)
    if W and parent == W.win.frame then
      return
    end
  end
  moved[#moved + 1] = { frame = f, parent = parent }
  f:SetParent(hidden)
end

function Chat.HideGame()
  for _, name in ipairs(Compat.ChatFrameNames()) do
    stash(_G[name])
    stash(_G[name .. "Tab"])
    stash(_G[name .. "ButtonFrame"])
  end
  for _, name in ipairs(Compat.CHAT_PARTS) do
    stash(_G[name])
  end
end

-- The game's combat log in a window of ours (plan-chat-two-decks.md §7, I1; chat.md "Combat
-- log", V45). Seen on Forever 15.11.2026: the frame alone, given back to UIParent, stood in the
-- middle of the screen without a title and could not be dragged. So a Core window holds it: the
-- log's frame and its tab become children of the window's content the first time it opens (not
-- in a fight) and stay there for the session; showing and hiding is our window's from then on.
-- Assumed: that the frame draws there and keeps the anchors we set.
Chat.LOG_BAND = 26 -- above the log's lines: its tab and its own filter buttons

local logWin
local logHome = {} -- [frame] = { parent, points }: where the game had it

local function logParts()
  local log = Compat.CombatLogFrame()
  if type(log) ~= "table" or type(log.SetParent) ~= "function" then
    return nil
  end
  local name = type(log.GetName) == "function" and log:GetName() or nil
  local tab = name and rawget(_G, name .. "Tab") or nil
  return log, type(tab) == "table" and tab or nil
end

local function redrawLogSwitch()
  if ns.Decks and ns.Decks.DrawHeads then
    ns.Decks.DrawHeads()
  end
end

local function logWindow()
  if logWin then
    return logWin
  end
  local s = ns.Decks.Settings()
  s.logWin = type(s.logWin) == "table" and s.logWin or {}
  local fresh = s.logWin.pos == nil
  logWin = B.UI.Window("BastiansChatLog", {
    module = "Chat",
    title = L["Combat log"],
    width = 460,
    height = 240,
    minWidth = 280,
    minHeight = 120,
    db = s.logWin,
    escape = false, -- Escape must not close it, as the chat's other windows
    strata = "LOW",
    onShow = redrawLogSwitch,
    onHide = redrawLogSwitch,
  })
  ns.View.Dress(logWin)
  -- the first time: above the chat window, not in the middle of the screen
  local main = ns.View.Window(ns.View.MAIN)
  if fresh and main and main.win and main.win.frame then
    logWin.frame:ClearAllPoints()
    logWin.frame:SetPoint("BOTTOMLEFT", main.win.frame, "TOPLEFT", 0, 8)
  end
  return logWin
end

local function pointsOf(f)
  local points = {}
  if type(f.GetNumPoints) == "function" and type(f.GetPoint) == "function" then
    for i = 1, f:GetNumPoints() or 0 do
      points[i] = { f:GetPoint(i) }
    end
  end
  return points
end

-- The log's frame and its tab into our window, where the frame fills the content under the band.
local function adoptLog(log, tab)
  local W = logWindow()
  for _, f in ipairs({ log, tab }) do
    if not logHome[f] then
      local home = f:GetParent()
      for _, m in ipairs(moved) do
        if m.frame == f then
          home = m.parent -- under our hidden parent now: the parent the game gave it
        end
      end
      logHome[f] = { parent = home, points = pointsOf(f) }
    end
    logOut[f] = true
    f:SetParent(W.content)
  end
end

local function placeLog(log, tab)
  local content = logWin.content
  log:ClearAllPoints()
  log:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -Chat.LOG_BAND)
  log:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -6, 6)
  log:Show()
  if tab then
    tab:ClearAllPoints()
    tab:SetPoint("BOTTOMLEFT", log, "TOPLEFT", 0, 2)
    tab:Show()
  end
end

-- The log is in our window (shown or not): showing and hiding moves no frame of the game's.
function Chat.LogHeld()
  local log = logParts()
  return log ~= nil and logOut[log] == true
end

function Chat.LogShown()
  return Chat.LogHeld() and logWin ~= nil and logWin.frame:IsShown()
end

-- Shows or hides the combat log's window; returns whether it shows. The first showing re-parents
-- the game's frame, which waits for the fight's end (false then).
function Chat.ShowLog(on)
  local log, tab = logParts()
  if not log or not active then
    return false
  end
  if not on then
    if logWin then
      logWin:Hide()
    end
    return false
  end
  if not logOut[log] then
    if InCombatLockdown() then
      return false
    end
    adoptLog(log, tab)
  end
  placeLog(log, tab) -- again each time: the game's dock may have set its own anchors meanwhile
  logWin:Show()
  return true
end

-- The log back where the game had it (the chat is switched off).
local function releaseLog()
  if logWin then
    logWin:Hide()
  end
  for f, home in pairs(logHome) do
    f:SetParent(home.parent)
    if #home.points > 0 then
      f:ClearAllPoints()
      for _, p in ipairs(home.points) do
        f:SetPoint(p[1], p[2], p[3], p[4], p[5])
      end
    end
  end
  logHome = {}
  logOut = {}
end

function Chat.ShowGame()
  releaseLog()
  for i = #moved, 1, -1 do
    local m = moved[i]
    m.frame:SetParent(m.parent)
    moved[i] = nil
  end
end

-- ---------------------------------------------------------------------------------------------
-- The game's input bars in our window: long texts, the history, the shell keys
-- ---------------------------------------------------------------------------------------------

local function onBoxText(box)
  if not active or not boxes[box] then
    return
  end
  local text = box:GetText()
  if type(text) ~= "string" or #text <= Chat.BOX_LETTERS or text:sub(1, 1) == "/" then
    return
  end
  local chatType = box:GetAttribute("chatType")
  local target = chatType == "WHISPER" and box:GetAttribute("tellTarget")
    or chatType == "CHANNEL" and box:GetAttribute("channelTarget")
    or nil
  if ns.View.TakeLong(text, chatType, target) then
    box:SetText("")
    Compat.DeactivateChat(box)
  end
end

-- What the game puts into the bar's history (every sent line and slash command) is kept too; the
-- lines we hand the bar at the start are not counted again.
local feeding = false
local function onBoxHistory(box, text)
  if active and not feeding and not Compat.IsSecret(text) then
    -- with its channel ("/p pulling"), so Up repeats where the line went (plan-chat-one-window.md
    -- §7, as Chattynator keeps it); a line the game wrote with its command stays as it is
    Keys.Remember(mod.db.char.history, Keys.WithChannel(text, Compat.ChatHead(box)))
    if typed[box] then
      typed[box].walk = nil -- sent: the next Up starts from the newest line
    end
  end
end

-- The lines our walk and search go over: the kept history without the secure commands (/cast,
-- /use: text an addon puts into the bar may not run them, assumed, probe X14; Chattynator leaves
-- them out too). The game's own walk (Alt+Up) is handed every line at the start.
local function walkable()
  return Keys.Walkable(mod.db.char.history, Compat.SecureCmdCheck())
end

-- Plain Up and Down over the kept history (chat.md "The input bar"), the bar's own walk with Alt
-- left to the game. Returns "history" when a step was taken. In the client's chat lockdown (an
-- encounter's secret chat) the bar is left alone, as Chattynator does.
function Chat.WalkHistory(box, dir)
  local t = typed[box]
  if not t or Compat.ChatLockdown() then
    return nil
  end
  local before = t.walk
  local head = Compat.ChatHead(box)
  local text, state = Keys.Walk(walkable(), before, dir, box:GetText() or "")
  t.walk = state
  if text == nil then
    return nil
  end
  if state and state ~= before then
    state.head = head -- a new walk: the channel the draft was typed for
  elseif not state and before then
    -- past the newest: the draft back on its own channel (a line of the walk moved the bar's)
    text = Keys.WithChannel(text, before.head)
  end
  Chat.ShowInBox(box, text, state)
  return "history"
end

-- A text into the bar. The game's bar reads a channel command at once (its OnTextSet runs
-- ParseText: "/p pulling" becomes the chat type PARTY and the text "pulling"), so what the bar
-- holds afterwards is what `state` (a walk or a search) remembers as shown: comparing with the
-- text put in took every such line for an edit by the player and dropped the walk, so Down did
-- nothing and a second Up showed the newest line again.
function Chat.ShowInBox(box, text, state)
  box:SetText(text)
  local shown = box:GetText()
  if type(shown) ~= "string" or Compat.IsSecret(shown) then
    shown = text
  end
  if state then
    state.shown = shown
  end
  box:SetCursorPosition(#shown)
  return shown
end

-- Ctrl+R: the newest older history line that holds the text typed before the first Ctrl+R.
function Chat.SearchHistory(box)
  local t = typed[box]
  if Compat.ChatLockdown() then
    return nil
  end
  local history = walkable()
  local s = t.search
  local text = box:GetText() or ""
  if not s or s.shown ~= text then
    s = { query = text, head = Compat.ChatHead(box) }
    t.search = s
  end
  local i = Keys.Search(history, s.query, s.index)
  if i then
    s.index = i
    Chat.ShowInBox(box, history[i], s)
    ns.View.Hint(string.format(L["History search: %s (Ctrl+R: older)"], s.query))
  else
    ns.View.Hint(string.format(L["No older line holds: %s"], s.query))
  end
  return i
end

-- Ctrl+G: the search left, the text typed before it back.
function Chat.CancelSearch(box)
  local t = typed[box]
  local s = t and t.search
  if not s then
    return nil
  end
  t.search = nil
  -- on the channel it was typed for, when a found line moved the bar's
  Chat.ShowInBox(box, s.index and Keys.WithChannel(s.query, s.head) or s.query)
  ns.View.Hint(nil)
  return s.query
end

-- The text keys of the bar (ADR 0045, Bastians.TextKeys): the Windows keys always, the readline
-- set with the setting (chat.md "The input bar"); only while the bar has the keyboard, so no
-- binding of the game is touched. Ctrl+C, X, V stay the client's.
local killed = {} -- the text the last Ctrl+U, K, W or Alt+D took, for Ctrl+Y (every bar)
local keyOpts = {
  shell = function()
    return mod.db.profile.bashKeys
  end,
  onOp = function(box, op)
    if op == "search" then
      Chat.SearchHistory(box)
      return true
    elseif op == "cancel" then
      Chat.CancelSearch(box)
      return true
    end
  end,
}
Chat.keyOpts, Chat.killed = keyOpts, killed

function Chat.OnBoxKey(box, key)
  if not (active and boxes[box]) then
    return nil
  end
  if key == "UP" or key == "DOWN" then
    local modified = (IsControlKeyDown and IsControlKeyDown())
      or (IsAltKeyDown and IsAltKeyDown())
      or (IsShiftKeyDown and IsShiftKeyDown())
    if not modified then
      return Chat.WalkHistory(box, key == "UP" and -1 or 1)
    end
  end
  keyOpts.extra = mod.db.profile.bashKeys and Keys.EXTRA or nil
  return S.TextKey(box, key, keyOpts, killed)
end

-- The bar is put back in our window whenever something else anchors it (the game, Edit Mode).
local function onBoxPoint(box)
  if active and boxes[box] and not ns.View.placing then
    C_Timer.After(0, function()
      if active and boxes[box] and not ns.View.HoldsBox(box) then
        ns.View.PlaceBox(box)
      end
    end)
  end
end

function Chat.AdoptBox(box)
  if not active or type(box) ~= "table" then
    return
  end
  if not boxes[box] then
    local home = { parent = box:GetParent(), points = {} }
    for i = 1, box:GetNumPoints() do
      home.points[i] = { box:GetPoint(i) }
    end
    home.letters = try(box, "GetMaxLetters") or Chat.BOX_LETTERS
    home.bytes = try(box, "GetMaxBytes")
    home.alt = try(box, "GetAltArrowKeyMode")
    boxes[box] = home
    typed[box] = typed[box] or {}
    -- the input line's right click (plan-chat-one-window.md §5, V33): the last lines, the place,
    -- the item level, Clear
    if not home.menu then
      home.menu = true
      pcall(box.HookScript, box, "OnMouseUp", function(self, button)
        if button == "RightButton" and active then
          ns.Menus.Input(self)
        end
      end)
    end
    try(box, "SetMaxLetters", 0)
    try(box, "SetMaxBytes", 0)
    -- the arrow keys belong to the bar, not to the game's key bindings: with the game's Alt mode
    -- on, plain Up moved the character. The measurement of 05.11.2026
    -- (build 70790: the bar's own walk needs Alt, OnKeyDown sees UP) was taken with the mode off;
    -- a4ca655f then left it on. Plain Up and Down are our walk (Chat.WalkHistory), Alt+Up the
    -- game's; Chattynator, which supports Forever, does the same.
    try(box, "SetAltArrowKeyMode", false)
    if not fed[box] then
      fed[box] = true
      feeding = true
      for _, l in ipairs(mod.db.char.history) do
        try(box, "AddHistoryLine", l)
      end
      feeding = false
    end
    if not boxHooked[box] then
      boxHooked[box] = true
      box:HookScript("OnTextChanged", function(self)
        guard("long", onBoxText, self)
      end)
      local ok, add = pcall(function()
        return box.AddHistoryLine
      end)
      if ok and type(add) == "function" then
        hooksecurefunc(box, "AddHistoryLine", function(self, text)
          guard("history", onBoxHistory, self, text)
        end)
      end
      box:HookScript("OnKeyDown", function(self, key)
        guard("keys", Chat.OnBoxKey, self, key)
      end)
      -- sent or Escape (the bar hides; with the "IM" chat style it only loses the focus): a peek
      -- under the clear-screen key ends
      box:HookScript("OnHide", function(self)
        guard("peek", Chat.BoxClosed, self)
        -- the decks name the input line's target while the bar is closed (I5)
        guard("target", function(b)
          if active and ns.Front.OnBarClose then
            ns.Front.OnBarClose(b)
          end
        end, self)
      end)
      box:HookScript("OnEditFocusLost", function(self)
        guard("peek", Chat.BoxClosed, self)
      end)
      hooksecurefunc(box, "SetPoint", function(self)
        guard("place", onBoxPoint, self)
      end)
    end
  end
  ns.View.PlaceBox(box)
end

function Chat.ReleaseBoxes()
  for box, home in pairs(boxes) do
    box:SetParent(home.parent)
    box:ClearAllPoints()
    for _, p in ipairs(home.points) do
      box:SetPoint(unpack(p))
    end
    try(box, "SetMaxLetters", home.letters)
    if home.bytes then
      try(box, "SetMaxBytes", home.bytes)
    end
    if home.alt ~= nil then
      try(box, "SetAltArrowKeyMode", home.alt)
    end
    boxes[box] = nil
  end
end

-- The game showed, focused or activated a bar: into our window it goes (any callback argument
-- that is an edit box counts; the registry passes its owner first). `activated`: the player asked
-- for the bar; a bar that merely appears (adopted on a /reload) never takes the keyboard.
local function onBoxShown(activated, ...)
  if not active then
    return
  end
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if type(v) == "table" and type(v.GetObjectType) == "function" then
      local ok, kind = pcall(v.GetObjectType, v)
      if ok and kind == "EditBox" then
        Chat.AdoptBox(v)
        if suiteHidden then
          Chat.Peek(v) -- the key hides the chat: the main window for this one line
        else
          ns.View.Show()
        end
        if activated then
          ns.Front.OnBarOpen(v) -- the place's channel in an empty bar (plan-chat-one-window §3.1)
        end
        -- the window was hidden (the clear-screen key): the box lost the focus the game gave it
        -- a moment ago; back on the next frame ("I have to press
        -- enter the second time")
        if activated then
          C_Timer.After(0, function()
            local hasFocus = v.HasFocus and v:HasFocus()
            if active and v:IsShown() and not hasFocus then
              v:SetFocus()
            end
          end)
        end
        return
      end
    end
  end
end

-- ---------------------------------------------------------------------------------------------
-- The clear-screen key (plan-round4 F1, BASTIANS_SUITE_HIDDEN; plan-launch-review R5.6,
-- 01.11.2026): Core hides the chat's windows; Enter while hidden brings the main window with the
-- bar focused, and when the bar closes (sent or Escape) the window goes again while the key still
-- hides the suite. The chat's windows are not protected: nothing waits for the end of combat.
-- ---------------------------------------------------------------------------------------------

function Chat.SetSuiteHidden(on)
  suiteHidden = on == true
  peek = nil -- hidden: Core took the window; back: Core shows what it took
  ns.Combat.SetHidden(suiteHidden) -- the toasts are the chat while hidden (V20)
end

function Chat.SuiteHidden()
  return suiteHidden
end

function Chat.Peeking()
  return peek ~= nil
end

function Chat.Peek(box)
  local W = ns.View.Window() or ns.View.Setup()
  if not W then
    return
  end
  if not peek then
    peek = { shown = W.win.frame:IsShown() }
  end
  peek.box = box
  W.win:Show()
end

-- The bar hid or lost the focus: on the next frame (the game may hand the focus back, our own
-- refocus above runs then too) the peek ends unless the bar holds the focus again.
function Chat.BoxClosed(box)
  if not (peek and peek.box == box) then
    return
  end
  C_Timer.After(0, function()
    if not (peek and peek.box == box) then
      return
    end
    local hasFocus = box.HasFocus and box:HasFocus()
    if box:IsShown() and hasFocus then
      return
    end
    local was = peek
    peek = nil
    local W = ns.View.Window()
    if suiteHidden and W and not was.shown then
      W.win:Hide()
    end
  end)
end

-- ---------------------------------------------------------------------------------------------
-- What is kept: the scrollback per tab, the open whisper tabs
-- ---------------------------------------------------------------------------------------------

function Chat.Keep(tabId, line)
  if line.secret or line.cat == "bnet" or type(line.text) ~= "string" then
    return
  end
  local sb = mod.db.char.scrollback
  sb[tabId] = sb[tabId] or {}
  Model.Push(sb[tabId], {
    text = line.text,
    r = line.r,
    g = line.g,
    b = line.b,
    at = line.at,
    public = line.public or nil,
  }, mod.db.profile.keep)
end

function Chat.RememberWhisper(partner)
  local list = mod.db.char.whispers
  for _, p in ipairs(list) do
    if p == partner then
      return
    end
  end
  list[#list + 1] = partner
end

function Chat.ForgetWhisper(partner)
  local list = mod.db.char.whispers
  for i = #list, 1, -1 do
    if list[i] == partner then
      table.remove(list, i)
    end
  end
  mod.db.char.scrollback["w:" .. tostring(partner)] = nil
end

-- ---------------------------------------------------------------------------------------------
-- On and off
-- ---------------------------------------------------------------------------------------------

function Chat.Start()
  wanted = true
  if active then
    return
  end
  if InCombatLockdown() then
    return -- PLAYER_REGEN_ENABLED starts it
  end
  active = true
  me = Compat.PlayerName()
  local first = not ns.View.Window()
  ns.View.Setup()
  if first then
    if ns.View.LayoutKind() == "tabs" then -- the tabs of version 2 keep their whisper tabs
      for _, partner in ipairs(mod.db.char.whispers) do
        ns.View.AddTab(Model.WhisperTab(partner))
      end
    end
    ns.View.Replay(mod.db.char.scrollback)
  end
  Chat.HookFrames()
  Chat.HideGame()
  for _, box in ipairs(Compat.EditBoxes()) do
    Chat.AdoptBox(box)
  end
  ns.View.Show()
  ns.People.Start()
end

function Chat.Stop()
  wanted = false
  if not active then
    return
  end
  active = false
  Chat.ReleaseBoxes()
  Chat.ShowGame()
  ns.View.Hide()
  ns.Junk.Hide()
end

local function setupHooks()
  for _, event in ipairs(Model.EVENTS) do
    Compat.AddFilter(event, onFilter)
  end
  -- every bar the game shows or activates comes into our window (retail 12.x: ChatFrameUtil and
  -- the EventRegistry callbacks; the old global where a client still calls it)
  for _, name in ipairs({ "ChatEdit_ActivateChat", "ChatFrameUtil.ActivateChat" }) do
    Compat.HookGlobal(name, function(box)
      guard("activate", onBoxShown, true, box)
    end)
  end
  for event, activated in pairs({
    ["ChatFrame.OnEditBoxShow"] = false,
    ["ChatFrame.OnEditBoxFocusGained"] = true,
  }) do
    Compat.OnRegistryEvent(event, function(...)
      guard("activate", onBoxShown, activated, ...)
    end, Chat)
  end
  -- a whisper window the game opens later is hidden and captured too
  Compat.HookGlobal("FCF_OpenTemporaryWindow", function()
    if active then
      guard("whisper window", function()
        Chat.HookFrames()
        Chat.HideGame()
      end)
    end
  end)
  -- a /reload is not a logout: the public lines stay
  Compat.HookGlobal("ReloadUI", function()
    reloading = true
  end)
  if type(C_UI) == "table" and type(C_UI.Reload) == "function" then
    hooksecurefunc(C_UI, "Reload", function()
      reloading = true
    end)
  end
end

local function onZone()
  local inside = Compat.InstanceKind() ~= nil
  if inside ~= insideInstance then
    insideInstance = inside
    ns.View.SelectGroup(inside)
  end
  ns.View.OnZone(inside)
end

-- The settings page's rows with the parts' own rows after them (V12's answers).
local function withParts(rows)
  for _, row in ipairs(ns.Answers.Options()) do
    rows[#rows + 1] = row
  end
  return rows
end

-- The migration's word to the player (V8), said after the start (`Chat.TELL_DELAY` seconds).
local tellViews = false
Chat.TELL_DELAY = 3

local function strengths()
  local out = {}
  for i, id in ipairs(Rules.LEVEL_ORDER) do
    out[id] = i .. ". " .. L["strength: " .. id]
  end
  return out
end

-- A sound's choice on the chat's page (V24): `part` "asks" or "streams", its key, its label.
local function soundOption(part, key, label)
  return {
    type = "select",
    key = (part == "asks" and "soundAsk_" or "soundStream_") .. key,
    label = L[label],
    values = function()
      return Compat.SoundChoices()
    end,
    get = function(m)
      local s = m.db.profile.sounds
      return s and s[part] and s[part][key] or "none"
    end,
    set = function(v, m)
      local p = m.db.profile
      p.sounds = type(p.sounds) == "table" and p.sounds or {}
      p.sounds[part] = type(p.sounds[part]) == "table" and p.sounds[part] or {}
      p.sounds[part][key] = v
      play(v) -- a choice rings once, so the player hears it
    end,
  }
end

mod = B:NewModule("Chat", {
  news = ns.NEWS, -- What's new (ADR 0021)
  addon = ADDON,
  title = L["Chat"],
  icon = "Interface\\AddOns\\Bastians_Chat\\Icon",
  open = function()
    ns.View.Toggle()
  end,
  apiVersion = 1,
  defaults = {
    profile = {
      enabled = false, -- ships off by default
      window = {},
      places = {},
      layout = {},
      tabs = {},
      selected = {},
      copy = {},
      editor = {},
      junkWindow = {},
      stamps = "hm", -- the artifact puts a dim time before every line
      font = "",
      fontSize = 14,
      outline = "",
      spacing = 0,
      fade = false,
      keep = 200,
      showOnWhisper = true,
      whisperTo = "messenger",
      bashKeys = true,
      shortChannels = "off",
      itemIcons = true,
      altInvite = true,
      rpNames = true, -- roleplay names in say and emote lines (plan-launch-version L3)
      mentions = "", -- the player's own words that make a line theirs (plan-chat-v3.md §2.2)
      watch = { items = {}, dungeons = {} }, -- the player's own watch list (§10.3, V19)
      watchRange = false, -- a group for the player's level pings too (V19; a city would ping a lot)
      -- the main window: the two decks (plan-chat-two-decks.md), the Inbox of version 3 or the
      -- tabs of version 2 (both until V35)
      layoutKind = "decks",
      combatFade = false,
      collectorLocked = false, -- the fight's collector can be dragged (V20)
      -- a sound per kind of request and per stream (V24): none by default, the game rings itself
      sounds = {
        asks = {
          whisper = "none",
          gm = "none",
          mention = "none",
          request = "none",
          ready = "none",
          warning = "none",
          watch = "none",
        },
        streams = { group = "none", guild = "none", market = "none", lfg = "none" },
      },
      -- Chat's look (plan-chat-v3.md §9, V13): a theme of the suite's ("" follows the suite's), the
      -- fight's pop-ups, the rows' density, the cards' style. ~~A preset (modern-dark, glass)~~
      -- until 20.11.2026: one look (ADR 0084), migration 2 maps a saved one to its theme
      look = "folio", -- the artifact's dark plate
      toastLook = "folio",
      -- the faces of the chat's windows (plan-chat-v3.md V17): the artifact's (one look, ADR 0084)
      uiFont = "auto",
      labelFont = "auto",
      numberFont = "auto",
      channelColors = "look", -- the channels' colours of the look (V25), or "game"
      chatBorder = "", -- LibSharedMedia's border for the chat's windows (V25): "" the suite's
      chatTexture = "",
      density = "comfortable",
      cardStyle = "framed",
      tierStripe = true,
      groupInInstance = true,
      spam = { level = "normal", action = "junk", block = "", allow = "", senders = {}, applyOld = true },
      messenger = { days = 30, lines = 500 }, -- the conversations' history (the Messenger's key)
      convoSide = "right", -- the player's runs in a conversation: right or left (plan-chat-one-window §3.1)
      convoTint = false, -- a faint ground under each run
      inputFollows = true, -- the input line follows the place shown (a person, the guild, the group)
    },
    char = { scrollback = {}, whispers = {}, history = {}, drafts = {} },
    global = { convos = {} },
  },
  -- 2 (ADR 0084, 20.11.2026): one look; the windows' presets become the themes they map to
  migrations = {
    [2] = function(db)
      local sv = rawget(db, "sv")
      local profiles = sv and sv.profiles or { db.profile }
      local values = B.UI.Settings and B.UI.Settings.PresetValues
      for _, p in pairs(profiles) do
        for _, key in ipairs({ "look", "toastLook" }) do
          local id = type(p) == "table" and rawget(p, key)
          local v = type(id) == "string" and id ~= "" and values and values(id)
          if v and v.theme then
            p[key] = v.theme
          end
        end
      end
    end,
  },
  options = withParts({
    { type = "header", label = L["Chat"] },
    { type = "toggle", key = "showOnWhisper", label = L["Open the window on a whisper"] },
    {
      type = "toggle",
      key = "watchRange",
      label = L["Ping for groups in my level range"],
      desc = L["The watch list: items your quests need and what /bchat watch adds always ping; groups for your level only with this."], -- luacheck: ignore 631 (a locale key stays one literal)
    },
    {
      type = "toggle",
      key = "rpNames",
      label = L["Roleplay names in say, yell and emote lines (Total RP 3, MyRolePlay)"],
    },
    {
      type = "note",
      text = function()
        return B.Compat.HasMsp() and "" or L["Roleplay names: Total RP 3 or MyRolePlay is not installed."]
      end,
    },
    {
      type = "select",
      key = "stamps",
      label = L["Time before each line"],
      values = { off = L["None"], hm = "14:32", hms = "14:32:07" },
    },
    {
      type = "select",
      key = "shortChannels",
      label = L["Channel names"],
      values = { off = L["as the game writes them"], number = "[2]", name = "[Trade]" },
    },
    { type = "toggle", key = "itemIcons", label = L["An icon before item links"] },
    { type = "toggle", key = "altInvite", label = L["Alt+click on a name invites"] },
    {
      -- a box like its neighbours ("unclear what that large button is
      -- supposed to do"): the game's own setting per kind of chat, all of them at once
      type = "toggle",
      key = "classColors",
      label = L["Names in class colours in every channel"],
      desc = L["The game keeps this per kind of chat; the box sets all of them at once."],
      get = function()
        return Compat.ClassColors() == true
      end,
      set = function(v)
        Compat.SetClassColors(v and true or false)
      end,
    },
    { type = "header", label = L["Look"] },
    {
      type = "select",
      key = "look",
      label = L["Chat's look"],
      desc = L["Every window of the chat in this look, whatever the suite's; the suite's follows it."],
      values = function()
        return ns.View.LookChoices()
      end,
    },
    {
      type = "select",
      key = "toastLook",
      label = L["The fight's pop-ups"],
      values = function()
        return ns.View.LookChoices()
      end,
    },
    {
      type = "select",
      key = "uiFont",
      label = L["Window text"],
      desc = L["By the look, the chat's windows take IBM Plex Sans, Barlow Condensed and IBM Plex Mono; the chat's lines keep the Font under Text."], -- luacheck: ignore 631 (a locale key stays one literal)
      values = function()
        return ns.View.FaceChoices("uiFont")
      end,
    },
    {
      type = "select",
      key = "labelFont",
      label = L["Heads and tabs"],
      desc = L["By the look: the heads and tabs take Barlow Condensed SemiBold, the numbers and times IBM Plex Mono."], -- luacheck: ignore 631 (a locale key stays one literal)
      values = function()
        return ns.View.FaceChoices("labelFont")
      end,
    },
    {
      type = "select",
      key = "numberFont",
      label = L["Numbers and times"],
      desc = L["By the look: the heads and tabs take Barlow Condensed SemiBold, the numbers and times IBM Plex Mono."], -- luacheck: ignore 631 (a locale key stays one literal)
      values = function()
        return ns.View.FaceChoices("numberFont")
      end,
    },
    {
      type = "range",
      key = "windowAlpha",
      label = L["Window opacity"],
      min = 20,
      max = 100,
      step = 5,
      get = function(m)
        return m.db.profile.windowAlpha or 100
      end,
      set = function(v, m)
        m.db.profile.windowAlpha = v
      end,
    },
    {
      type = "select",
      key = "channelColors",
      label = L["Channel colours"],
      desc = L["The look's: each channel in a colour readable on this look, light ones too; the game's: as set in the game's chat settings."], -- luacheck: ignore 631 (a locale key stays one literal)
      values = { look = L["the look's"], game = L["the game's"] },
    },
    {
      type = "note",
      text = function()
        return B.UI.Style.HasMedia() and ""
          or L["Borders and window textures: LibSharedMedia is not loaded (another addon brings it)."]
      end,
    },
    {
      type = "select",
      key = "chatBorder",
      label = L["Window border"],
      values = function()
        return ns.View.MediaChoices("border", L["None"])
      end,
    },
    {
      type = "color",
      key = "chatBorderColor",
      label = L["Border colour"],
      theme = B.UI.Style.C.line,
    },
    {
      type = "select",
      key = "chatTexture",
      label = L["Window texture"],
      values = function()
        return ns.View.MediaChoices("background", L["The look's flat ground"])
      end,
    },
    {
      type = "select",
      key = "density",
      label = L["Lines"],
      values = { compact = L["compact"], comfortable = L["comfortable"] },
    },
    {
      type = "select",
      key = "cardStyle",
      label = L["Cards"],
      values = { framed = L["framed"], flat = L["flat"] },
    },
    { type = "toggle", key = "tierStripe", label = L["A stripe in the colour of how much a line matters"] },
    { type = "header", label = L["Text"] },
    {
      type = "font",
      key = "font",
      label = L["Font"],
      values = function()
        return ns.View.FontChoices()
      end,
    },
    { type = "range", key = "fontSize", label = L["Text size"], min = 10, max = 22, step = 1 },
    {
      type = "select",
      key = "outline",
      label = L["Outline"],
      values = { [""] = L["None"], OUTLINE = L["thin"], THICKOUTLINE = L["thick"] },
    },
    { type = "range", key = "spacing", label = L["Line spacing"], min = 0, max = 6, step = 1 },
    { type = "toggle", key = "fade", label = L["Fade old lines"] },
    { type = "range", key = "keep", label = L["Lines kept per tab"], min = 50, max = 500, step = 50 },
    { type = "header", label = L["Sounds"] },
    soundOption("asks", "whisper", "A whisper"),
    soundOption("asks", "gm", "A Game Master"),
    soundOption("asks", "mention", "A mention"),
    soundOption("asks", "request", "An invite, a duel, a trade, a summon"),
    soundOption("asks", "ready", "A ready check"),
    soundOption("asks", "warning", "A raid warning"),
    soundOption("asks", "watch", "A watch-list match"),
    soundOption("streams", "group", "A line of the group"),
    soundOption("streams", "guild", "A line of the guild"),
    soundOption("streams", "market", "An offer in Trade"),
    soundOption("streams", "lfg", "A group post"),
    { type = "header", label = L["Input bar"] },
    {
      type = "toggle",
      key = "bashKeys",
      label = L["Shell keys: Ctrl+A, E, U, K, W, R (only while you type)"],
    },
    { type = "header", label = L["Context"] },
    { type = "toggle", key = "combatFade", label = L["Fade the windows in combat"] },
    { type = "toggle", key = "collectorLocked", label = L["Lock the fight's collector"] },
    { type = "toggle", key = "groupInInstance", label = L["Group tab in dungeons and raids"] },
    { type = "header", label = L["Spam"] },
    {
      type = "select",
      key = "level",
      label = L["Spam filter"],
      get = function(m)
        return m.db.profile.spam.level
      end,
      set = function(v, m)
        m.db.profile.spam.level = v
        Chat.RulesChanged()
      end,
      values = strengths,
    },
    {
      -- a changed rule reaches what is already on screen
      type = "toggle",
      key = "spamApplyOld",
      label = L["Apply the filter to older lines too"],
      get = function(m)
        return m.db.profile.spam.applyOld ~= false
      end,
      set = function(v, m)
        m.db.profile.spam.applyOld = v and true or false
        if v then
          Chat.Refilter()
        end
      end,
    },
    {
      type = "execute",
      label = L["Junk and word lists"],
      desc = L["The filtered lines with their reason, the blocked and allowed words."],
      func = function()
        ns.Junk.Show()
      end,
    },
    { type = "header", label = L["Whispers"] },
    {
      type = "toggle",
      key = "inputFollows",
      label = L["The input line follows the place shown"],
      desc = L["A person shown: Enter whispers them; Guild: the guild; Group: the party or the raid."],
    },
    {
      type = "select",
      key = "convoSide",
      label = L["Your lines in a conversation"],
      values = { right = L["on the right"], left = L["on the left"] },
    },
    { type = "toggle", key = "convoTint", label = L["A faint ground under each run of lines"] },
    {
      type = "range",
      key = "msgDays",
      label = L["Days of history"],
      min = 1,
      max = 90,
      step = 1,
      get = function(m)
        return m.db.profile.messenger.days
      end,
      set = function(v, m)
        m.db.profile.messenger.days = v
      end,
    },
  }),
  OnInitialize = function()
    setupHooks()
  end,
  OnEnable = function(self)
    -- each part on its own: a part that fails is noted (/bchat errors) and the chat still starts
    -- (12.11.2026: one event the client refused stopped the whole start, and nothing was captured)
    -- once per profile: whispers have one place, the conversations (
    -- "whisper has one window in the future"; plan-chat-one-window.md R12). The setting left the
    -- page; a profile that sent them to tabs would never reach them again.
    guard("whispers", function()
      local p = self.db.profile
      if not p.whispersOnePlace then
        p.whispersOnePlace = true
        if p.whisperTo ~= "messenger" then
          p.whisperTo = "messenger"
          B:Log(self, "info", "whispers go to the conversations again (plan-chat-one-window.md R12)")
        end
      end
    end)
    -- once per profile: the Switchboard's settings go with it (plan-chat-one-window.md V31); a
    -- profile that showed it shows the one window
    guard("switchboard", function()
      local p = self.db.profile
      if not p.switchboardGone then
        p.switchboardGone = true
        local had = p.switchboard ~= nil or p.layoutKind == "switchboard"
        p.switchboard = nil
        if p.layoutKind == "switchboard" then
          p.layoutKind = "inbox"
        end
        if had then
          B:Log(
            self,
            "info",
            "the Switchboard's settings dropped; the one window shows (plan-chat-one-window.md V31)"
          )
        end
      end
    end)
    guard("feed", ns.Feed.Register, self)
    guard("places", ns.Places.Attach) -- the places in windows of their own (V32)
    guard("requests", ns.Requests.Attach, self) -- the game's requests and Courtesy's moments (V6)
    guard("combat", ns.Combat.Attach) -- the fight's toasts and collector (V11)
    guard("sounds", function() -- the requests' and the streams' sounds (V24)
      if not soundsAttached then
        soundsAttached = true
        store:On(Chat.OnStoreSound)
      end
    end)
    -- once per profile the tabs become views and the window shows the Inbox (plan-chat-v3.md §11)
    guard("views", function()
      local p = self.db.profile
      local hadTabs = type(p.tabs) == "table" and next(p.tabs) ~= nil
      local made = ns.Views.Migrate(p)
      if made then
        B:Log(
          self,
          "info",
          "the tabs became %d views; the main window shows the Inbox (plan-chat-v3.md 11)",
          made
        )
      end
      -- the player is told in our own window, after the start and the login's lines
      tellViews = made ~= nil and hadTabs
      ns.Views.Attach()
    end)
    -- once per profile: the two decks take the Inbox's place (plan-chat-two-decks.md V38); the
    -- Inbox and the tabs stay behind /bchat inbox and /bchat tabs until V35
    guard("decks", function()
      local p = self.db.profile
      if not p.decksOffered then
        p.decksOffered = true
        if p.layoutKind == "inbox" then
          p.layoutKind = "decks"
        end
      end
      ns.Decks.Migrate(p)
      ns.Decks.Attach()
    end)
    for _, key in ipairs({ "scrollback", "history", "drafts" }) do
      self.db.char[key] = type(self.db.char[key]) == "table" and self.db.char[key] or {}
    end
    self.db.char.whispers = type(self.db.char.whispers) == "table" and self.db.char.whispers or {}
    self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
      if wanted and not active then
        Chat.Start()
      end
      ns.View.SetCombat(false)
      ns.Combat.Stop()
      if active then
        ns.Fights.Stop() -- the fight's recap (V42)
        ns.Basics.AfterFight() -- the combat log asked for in the fight (V37)
      end
    end)
    self:RegisterEvent("PLAYER_REGEN_DISABLED", function()
      if active then
        ns.View.SetCombat(true)
        ns.Combat.Start()
        ns.Fights.Start()
      end
    end)
    -- Away ends by itself, the catch-up cards (V20; probe X12)
    self:RegisterEvent("PLAYER_STARTED_MOVING", function()
      ns.Away.OnMove()
    end)
    self:RegisterEvent("PLAYER_FLAGS_CHANGED", function(_, _, unit)
      ns.Away.OnFlags(unit)
    end)
    for event, kind in pairs({
      CINEMATIC_START = "cutscene",
      PLAY_MOVIE = "cutscene",
      LOADING_SCREEN_ENABLED = "loading",
    }) do
      self:RegisterEvent(event, function()
        ns.Away.Pause(kind)
      end)
    end
    for _, event in ipairs({ "CINEMATIC_STOP", "STOP_MOVIE", "LOADING_SCREEN_DISABLED" }) do
      self:RegisterEvent(event, function()
        ns.Away.Pause(nil)
      end)
    end
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
      if active then
        onZone()
      end
    end)
    -- the group's life: a finished group is an entry of the people list (plan-chat-two-decks §5)
    guard("group", function()
      self:RegisterEvent("GROUP_ROSTER_UPDATE", function()
        if active then
          ns.Decks.OnGroup()
        end
      end)
    end)
    self:RegisterEvent("PLAYER_LOGOUT", function()
      if active and ns.View.LayoutKind() == "decks" then
        ns.Decks.KeepDraft() -- a half-typed whisper stays with its person (plan §4)
      end
      if not reloading then
        -- the game's public channels end with the session, and tabs marked not to keep
        Model.DropPublic(self.db.char.scrollback, self.db.profile.tabs)
      end
    end)
    self:On("BASTIANS_QUESTS_CHANGED", function()
      Chat.WatchChanged() -- what the quests still need (V19)
    end)
    self:On("BASTIANS_SETTING_CHANGED", function(_, _, name, key)
      if name == self.name and active then
        if key == "watchRange" then
          Chat.WatchChanged() -- V19
        end
        if ns.View.LOOK_OPTIONS[key] then
          ns.View.ApplyLookChange() -- Chat's look (V13)
        else
          ns.View.Apply()
        end
      end
    end)
    -- the clear-screen key, only while the page "Hidden by the key" ticks the chat; the key's
    -- return always passes (as the Orbiter, Voice/Module.lua)
    self:On("BASTIANS_SUITE_HIDDEN", function(_, _, on)
      local Screen = B.UI.Screen
      if on and Screen and Screen.Hides and not Screen.Hides("Chat") then
        return
      end
      Chat.SetSuiteHidden(on == true)
    end)
    local Screen = B.UI.Screen
    Chat.SetSuiteHidden(Screen ~= nil and Screen.Hidden ~= nil and Screen.Hidden() and Screen.Hides("Chat"))
    Chat.Start()
    if tellViews then
      tellViews = false
      C_Timer.After(Chat.TELL_DELAY, function()
        B:Say(
          L["Bastian's Chat shows its two decks; your tabs are watches on the upper strip now. /bchat tabs brings the tabs back."] -- luacheck: ignore 631 (a locale key stays one literal)
        )
      end)
    end
  end,
  OnDisable = function()
    Chat.Stop()
  end,
})
ns.mod = mod
mod.Chat, mod.Model, mod.View = Chat, Model, ns.View
mod.People, mod.Junk, mod.Rules, mod.Keys = ns.People, ns.Junk, Rules, Keys
mod.Words, mod.Record, mod.Intent, mod.Relevance, mod.Store = Words, Record, Intent, Relevance, Store
mod.Compat = Compat -- the client's calls the chat makes (the tests read the sound choices, V25)
mod.Rows, mod.Cards, mod.Inbox, mod.Requests = ns.Rows, ns.Cards, ns.Inbox, ns.Requests
mod.Ledger, mod.Answers, mod.Combat, mod.Away = ns.Ledger, ns.Answers, ns.Combat, ns.Away
mod.Views, mod.Asks, mod.Find, mod.Menus, mod.Places = ns.Views, ns.Asks, ns.Find, ns.Menus, ns.Places
mod.Decks, mod.Basics, mod.Fights, mod.Front = ns.Decks, ns.Basics, ns.Fights, ns.Front

B:DeclareMessage("BASTIANS_MOMENT_REOPEN") -- a card asks Courtesy for its ring again (V6, §16)

SLASH_BASTIANSCHAT1 = "/bchat"
SlashCmdList.BASTIANSCHAT = function(msg)
  local word, rest = string.match(msg or "", "^%s*(%S*)%s*(.-)%s*$")
  if string.lower(word or "") == "away" then
    ns.Away.Command(rest) -- the text keeps its case (V10)
    return
  end
  local verb = string.lower(word or "")
  if verb == "watch" or verb == "unwatch" then
    Chat.WatchCommand(verb, rest) -- the link keeps its case (V19)
    return
  end
  local cmd = string.lower(strtrim(msg or ""))
  if cmd == "copy" then
    ns.View.CopyTab()
  elseif cmd == "msg" or cmd == "messenger" or cmd == "people" then
    ns.Front.ShowPeople() -- the conversations are places of the one window (V30)
  elseif cmd == "junk" then
    ns.Junk.Toggle()
  elseif cmd == "store" then
    Chat.SayStore()
  elseif cmd == "errors" then
    Chat.SayErrors()
  elseif cmd == "back" then
    ns.Away.Stop()
  elseif cmd == "collector" then
    ns.Combat.ResetCollector() -- back on the chat window's edge (V20)
  elseif cmd == "inbox" or cmd == "tabs" or cmd == "decks" then
    ns.View.SetLayout(cmd)
  elseif cmd == "log" then
    ns.Basics.ToggleLog() -- the game's combat log window (I1)
  elseif cmd == "switchboard" then
    ns.View.SetLayout("inbox") -- the Switchboard went in V31; its places are the window's
  else
    ns.View.Toggle()
  end
end
