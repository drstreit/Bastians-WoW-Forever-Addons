-- The moments (courtesy.md): what others do to the player, the four answers on the ring, what a click
-- sends. Once per person in ten minutes, never in combat, in an instance only by choice. Nothing
-- about another player is kept beyond that memory in RAM (CLAUDE.md §8).
local _, ns = ...
local B = Bastians
local L = ns.L
local Model, Compat, Voice, Mine, Facts, Medallion =
  ns.Model, ns.Compat, ns.Voice, ns.Mine, ns.Facts, ns.Medallion

local Courtesy = {}
ns.Courtesy = Courtesy

Courtesy.DECLINE = "Thank you, but not today, %t." -- what a request without a line of its own gets
Courtesy.MACRO_MAX = 255 -- characters of one macro line (assumed as for a typed line)

local MOOD_WORD = {
  polite = L["Polite"],
  roleplay = L["Roleplay"],
  snarky = L["Snarky"],
  philosophic = L["Philosophic"],
  cheerful = L["Cheerful"],
  weary = L["Weary"],
}

local plain = B.Compat.Plain
local mod
local state = { seen = {} }
local recent = {} -- the lines of this session (Voice.Remember)
local pending, pendingFacts -- the moment the ring shows
local invite -- the last group invite: { who, guid, at }
local trace = {} -- the last buffs and what became of them, newest first (saved: spells, never names)
local refusal -- why the last Offer was not answered
local known -- the last reading of the auras (Model.Reading), nil before the first
local settleUntil = 0 -- readings before this only note what is there (a login, a loading screen)
local blindSince -- since when the auras went unread (a fight, hidden auras); nil while they are read
Courtesy.TRACE = 30 -- kept; `/bcourtesy why` prints the newest ten

local function now()
  return (GetTime and GetTime()) or 0
end

local function settings()
  local p = mod.db.profile
  local inInstance = false
  if type(IsInInstance) == "function" then
    inInstance = IsInInstance() and true or false
  end
  return {
    mode = p.courtesy or "ask",
    instances = p.courtesyInstances and true or false,
    inInstance = inInstance,
    inCombat = (InCombatLockdown and InCombatLockdown()) and true or false,
  }
end

-- The moods switched on, as Voice's weights.
function Courtesy.Moods()
  local out = {}
  for _, mood in ipairs(Voice.MOODS) do
    if mod.db.profile["mood_" .. mood] then
      out[mood] = 1
    end
  end
  return out
end

-- The sentence above the ring.
function Courtesy.Words(event)
  if event.kind == "buff" then
    if not event.who then -- a caster the client has no handle on
      return event.what and string.format(L["Someone cast %s on you"], event.what) or L["Someone buffed you"]
    elseif event.what then
      return string.format(L["%s cast %s on you"], event.who, event.what)
    end
    return string.format(L["%s buffed you"], event.who)
  elseif event.kind == "rez" then
    return string.format(L["%s resurrected you"], event.who)
  elseif event.kind == "duel" then
    return string.format(L["%s challenges you to a duel"], event.who)
  elseif event.kind == "trade" then
    return string.format(L["%s wants to trade"], event.who)
  elseif event.kind == "invite" then
    return string.format(L["%s invites you to a group"], event.who)
  elseif event.kind == "camp" then
    return string.format(L["%s's camp warmed you"], event.who)
  elseif event.kind == "accepted" then
    return string.format(L["You joined %s's group"], event.who)
  elseif event.kind == "try" then
    return string.format(L["A moment to try: %s"], event.situation or "")
  end
  return event.text or string.format(L["%s greets you"], event.who)
end

function Courtesy.IsRequest(event)
  return event.kind == "duel" or event.kind == "trade" or event.kind == "invite"
end

-- The game emote of a moment: a wave back for an emote, a bow for a request, thanks otherwise.
function Courtesy.EmoteFor(event)
  if event.kind == "emote" then
    return "WAVE"
  elseif Courtesy.IsRequest(event) then
    return "BOW"
  end
  return "THANK"
end

local function unitOf(event)
  return event.unit and UnitExists(event.unit) and event.unit or nil
end

local function emoteAt(event, token)
  B.Compat.Emote(token, unitOf(event))
  return token
end

-- Up to `count` lines for a moment: different moods where it can, never one line twice; lines said
-- lately only when nothing else is left.
function Courtesy.Lines(facts, count, onlyMood, via)
  local weights = onlyMood and { [onlyMood] = 1 } or Courtesy.Moods()
  local left, out, offered = {}, {}, {}
  for mood, weight in pairs(weights) do
    left[mood] = weight
  end
  local avoid = setmetatable({}, { __index = recent })
  for _ = 1, count do
    local line = Mine.Choose(facts, { moods = left, recent = avoid, fresh = true, via = via })
      or Mine.Choose(facts, { moods = weights, recent = avoid, fresh = true, via = via })
      or Mine.Choose(facts, { moods = weights, recent = offered, fresh = true, via = via })
    if not line then
      break
    end
    out[#out + 1] = line
    avoid[line], offered[line] = true, true
    left[line[2]] = nil
  end
  return out
end

local function preview(line, facts)
  return (facts.myName and (facts.myName .. " ") or "") .. Voice.Words(line, facts, "emote")
end

-- What the petal's secure button runs: the line as the player would type it. The client refuses
-- SendChatMessage from addon code even on a real click (BugGrabber, Forever 08.11.2026, twice); a macro
-- line of a secure button is the player's own (the kit's overlay: out of combat only, as the ring).
function Courtesy.Macro(line, facts)
  local spoken = Voice.Channel(line) == "SAY"
  local words = Voice.Words(line, facts, spoken and "say" or "emote")
  local text = words and ((spoken and "/s " or "/e ") .. words) or nil
  return text and #text <= Courtesy.MACRO_MAX and { type = "macro", macrotext = text } or nil
end

-- The whole name a whisper to this person needs, nil when the client does not give it.
local function wholeName(event)
  if event.full then
    return event.full
  elseif unitOf(event) then
    return B.Compat.FullName(event.unit)
  end
  return event.guid and Compat.WholeNameOfGUID(event.guid) or nil
end

local function kindItems(event, facts, onlyMood)
  local items = {}
  local whisper = event.full ~= nil -- to the person; else aloud, through the secure button
  for i, line in ipairs(Courtesy.Lines(facts, 3, onlyMood, whisper and "say" or nil)) do
    items[i] = {
      icon = (line.act and not whisper) and "app_gestures" or "app_chat",
      label = MOOD_WORD[line[2]],
      tip = whisper and ("/w " .. (event.who or "") .. " " .. Voice.Words(line, facts, "say"))
        or preview(line, facts),
      line = line,
      secure = not whisper and Courtesy.Macro(line, facts) or nil,
    }
  end
  for i = #items + 1, 3 do
    items[i] = false
  end
  local token = Courtesy.EmoteFor(event)
  items[4] = {
    icon = "app_gestures",
    label = L["Gesture"],
    tip = "/" .. string.lower(token) .. " " .. (event.who or ""),
    emote = token,
  }
  return items
end

local function requestItems(event)
  local who = event.who or ""
  return {
    { icon = "app_gestures", label = L["Bow"], tip = "/bow " .. who, emote = "BOW" },
    { icon = "app_gestures", label = L["Wave"], tip = "/wave " .. who, emote = "WAVE" },
    { icon = "close", label = L["Decline"], tip = L["Decline politely"], decline = true },
    { icon = "other", label = L["Not now"] },
  }
end

-- Sends a line, as the line asks. Only ever from a click (courtesy.md "What the client allows").
function Courtesy.Say(line, facts, event)
  Voice.Remember(recent, line)
  if event.full then -- to the person: no target needed, the player's own stays, nothing public
    local spoken = Voice.Words(line, facts, "say")
    Compat.SendChat(spoken, "WHISPER", event.full)
    return spoken
  end
  local channel = Voice.Channel(line)
  local words = Voice.Words(line, facts, channel == "SAY" and "say" or "emote")
  Compat.SendChat(words, channel)
  if line.emote then
    emoteAt(event, line.emote)
  end
  return words
end

-- Whispers the polite no and calls the game's decline. -> the whisper, or false.
function Courtesy.Decline(event, facts)
  local line = Mine.Choose(facts, { moods = Courtesy.Moods(), via = "say", recent = recent })
  local text = line and Voice.Words(line, facts, "say")
    or string.gsub(L[Courtesy.DECLINE], "%%t", function()
      return event.who
    end)
  local sent = Compat.SendChat(text, "WHISPER", event.full or event.who)
  Compat.Decline(event.kind)
  return sent and text or false
end

-- A petal was clicked. -> what went out, or false.
function Courtesy.Fire(_, item)
  local event, facts = pending, pendingFacts
  Courtesy.Hide()
  if not (event and item) then
    return false
  elseif item.decline then
    return Courtesy.Decline(event, facts)
  elseif item.line then
    return Courtesy.Say(item.line, facts, event)
  elseif item.emote then
    return emoteAt(event, item.emote)
  end
  return false
end

-- A petal's secure button has run its line: what is left to do after the game sent it.
function Courtesy.Fired(_, item)
  local event = pending
  if event and item and item.line then
    Voice.Remember(recent, item.line)
    if item.line.emote then
      emoteAt(event, item.line.emote)
    end
  end
  Courtesy.Hide()
end

-- Opens the ring for a moment. `facts` and `onlyMood` from `/bcourtesy try ring`.
function Courtesy.Show(event, facts, onlyMood)
  facts = facts or Facts.Moment(event)
  event.full = event.who and wholeName(event) or nil
  pending, pendingFacts = event, facts
  local items = Courtesy.IsRequest(event) and requestItems(event) or kindItems(event, facts, onlyMood)
  Medallion.Open(items, Courtesy.Words(event), Courtesy.Fire, function()
    pending, pendingFacts = nil, nil
  end, Courtesy.Fired)
end

function Courtesy.Hide()
  pending, pendingFacts = nil, nil
  Medallion.Close()
end

function Courtesy.IsShown()
  return Medallion.IsShown()
end

function Courtesy.Pending()
  return pending
end

-- A moment arrived: the model decides, the ring asks or the gesture plays.
function Courtesy.Offer(event)
  if not mod or not mod:IsEnabled() then
    return nil
  end
  local t = now()
  Model.Forget(state, t)
  local s = settings()
  if Courtesy.IsRequest(event) and s.mode == "auto" then
    s.mode = "ask" -- a request is never answered for the player
  end
  refusal = Model.Refusal(event, state, t, s)
  local decision = Model.Courtesy(event, state, t, s)
  if decision == "ask" then
    Courtesy.Show(event)
  elseif decision == "auto" then
    emoteAt(event, Courtesy.EmoteFor(event))
  end
  return decision
end

-- -------------------------------------------------------------------------------------------------
-- The events
-- -------------------------------------------------------------------------------------------------

local function name(who)
  who = plain(who)
  return type(who) == "string" and who ~= "" and who or nil
end

-- One line of the trace: what became of a buff, `how` the caster was known. No names (CLAUDE.md §8).
local function note(word, spell, how)
  if trace[1] and trace[1].word == word and trace[1].spell == spell and word == "auras hidden" then
    return
  end
  table.insert(trace, 1, { at = time(), word = word, spell = spell, how = how })
  trace[Courtesy.TRACE + 1] = nil
end

local function offerBuff(event, how)
  note(Courtesy.Offer(event) or refusal or "module off", event.what, how)
end

-- An aura someone has just cast on the player. Who: the unit, else the caster's GUID (the client has
-- no unit for a stranger who is neither target nor nameplate), else only that a player cast it.
local function onFresh(a)
  local spell, source = a.name, a.source
  if source then
    if Compat.IsMe(source) then
      return -- my own cast: no line of the trace (they pushed every stranger's buff out of it)
    elseif Compat.IsMineOrGroup(source) then
      return note("own or group", spell, "unit")
    end
    local who = Compat.UnitPlayerName(source)
    if not who or plain(UnitIsPlayer(source)) == false then
      return note("not a player", spell, "unit")
    end
    return offerBuff({ kind = "buff", who = who, unit = source, what = spell }, "unit")
  end
  local guid = Compat.CasterGUID(a.instance)
  if guid and guid == plain(UnitGUID("player")) then
    return -- my own cast
  elseif guid and not string.find(guid, "^Player%-") then
    return note("not a player", spell, "guid")
  end
  local who = guid and Compat.NameOfGUID(guid)
  if who then
    if Compat.IsMineOrGroup(who) then
      return note("own or group", spell, "guid")
    end
    return offerBuff({ kind = "buff", who = who, guid = guid, what = spell }, "guid")
  end
  local how = guid and "guid without a name" or "none"
  if a.fromPlayer == true or (a.fromPlayer == nil and Facts.BuffKind(spell)) then
    return offerBuff({ kind = "buff", key = "unseen:" .. (spell or "?"), what = spell }, how)
  end
  return note("not from a player", spell, how)
end

-- Reads the auras and compares (courtesy.md "The moments"): UNIT_AURA says only that something changed,
-- its own list can be secret, empty on a full update and says nothing of a buff cast again.
function Courtesy.ReadAuras()
  if not mod or not mod:IsEnabled() then
    return
  elseif InCombatLockdown and InCombatLockdown() then
    blindSince = blindSince or now()
    return -- in a fight: PLAYER_REGEN_ENABLED reads
  end
  local list = Compat.HelpfulAuras()
  if not list then
    blindSince = blindSince or now()
    return note("auras hidden")
  end
  local t = now()
  local blind = blindSince and (t - blindSince) or nil
  blindSince = nil
  local fresh = t >= settleUntil and Model.NewAuras(known, list) or {}
  known = Model.Reading(list)
  for _, a in ipairs(fresh) do
    if Model.Timely(a.landed, t, blind) then
      onFresh(a)
    else
      note("long fight", a.name) -- unread too long, and the aura does not say it landed lately
    end
  end
end

function Courtesy.OnAura(_, _, unit)
  if plain(unit) == "player" then
    mod:Coalesce("courtesy-auras", 0.2, Courtesy.ReadAuras)
  end
end

-- A fight: the ring closes. After it the auras are read: a buff of a short fight still gets its
-- ring, one of a longer fight when the aura says it landed lately (Model.Timely).
function Courtesy.OnFight()
  blindSince = blindSince or now()
  Courtesy.Hide()
end

function Courtesy.OnFightOver()
  Courtesy.ReadAuras()
end

-- A login or a loading screen: what is there now is no one's kindness.
function Courtesy.Settle()
  settleUntil = now() + Model.SETTLE_SECONDS
  C_Timer.After(Model.SETTLE_SECONDS + 0.1, Courtesy.ReadAuras)
end

-- `/bcourtesy why`: the last buffs and what became of each, newest first.
function Courtesy.Why()
  if #trace == 0 then
    B:Say(L["No buff seen yet."])
    return false
  end
  B:Say(L["The last buffs Courtesy saw:"])
  for i = 1, math.min(#trace, 10) do
    local entry = trace[i]
    B:Say(
      "%ds: %s%s%s",
      time() - entry.at,
      entry.word,
      entry.spell and (", " .. entry.spell) or "",
      entry.how and (" (" .. entry.how .. ")") or ""
    )
  end
  return true
end

function Courtesy.OnResurrect(_, _, who)
  who = name(who)
  if who then
    Courtesy.Offer({ kind = "rez", who = who })
  end
end

-- CHAT_MSG_TEXT_EMOTE: the line, the sender, ... and the sender's GUID, ten arguments later.
function Courtesy.OnEmote(_, _, text, sender, ...)
  text, sender = plain(text), name(sender)
  local guid = plain((select(10, ...)))
  if
    not sender
    or type(text) ~= "string"
    or not Model.AimedAtMe(text)
    or guid == plain(UnitGUID("player"))
  then
    return
  end
  -- the first name: Forever's sender can carry a surname, with a space or a hyphen
  local who = sender:match("^([^%-%s]+)") or sender
  if who ~= Compat.UnitPlayerName("player") then
    Courtesy.Offer({ kind = "emote", who = who, text = text, guid = guid })
  end
end

function Courtesy.OnDuel(_, _, who)
  who = name(who)
  if who then
    Courtesy.Offer({ kind = "duel", who = who })
  end
end

function Courtesy.OnTrade()
  local who = Compat.UnitPlayerName("NPC")
  if who and not Compat.IsMineOrGroup("NPC") then
    Courtesy.Offer({ kind = "trade", who = who, unit = "NPC", full = B.Compat.FullName("NPC") })
  end
end

-- PARTY_INVITE_REQUEST: the inviter, four flags, ... and the inviter's GUID.
function Courtesy.OnInvite(_, _, who, ...)
  who = name(who)
  if who then
    local guid = select(6, ...)
    invite = { who = who, guid = guid, at = now() }
    Courtesy.Offer({ kind = "invite", who = who, guid = guid })
  end
end

-- GROUP_JOINED soon after an invite: the player said yes in the game's own popup.
function Courtesy.OnGroupJoined()
  local last = invite
  invite = nil
  if last and now() - last.at <= Model.ACCEPT_SECONDS then
    Courtesy.Offer({ kind = "accepted", who = last.who, guid = last.guid, again = true })
  end
end

-- BASTIANS_CAMP_WARMED (Bastian's Campfire, the bus): the host's name when the client gives it.
function Courtesy.OnCampWarmed(_, _, who)
  who = name(who)
  if who and who ~= Compat.UnitPlayerName("player") then
    Courtesy.Offer({ kind = "camp", who = who })
  end
end

function Courtesy.Attach(m)
  mod = m
  state, invite, known, blindSince = { seen = {} }, nil, nil, nil
  m.db.global.trace = type(m.db.global.trace) == "table" and m.db.global.trace or {}
  trace = m.db.global.trace
  Courtesy.Settle()
  m:RegisterEvent("PLAYER_ENTERING_WORLD", Courtesy.Settle)
  m:On("BASTIANS_CAMP_WARMED", Courtesy.OnCampWarmed)
  m:RegisterEvent("UNIT_AURA", Courtesy.OnAura)
  m:RegisterEvent("RESURRECT_REQUEST", Courtesy.OnResurrect)
  m:RegisterEvent("CHAT_MSG_TEXT_EMOTE", Courtesy.OnEmote)
  m:RegisterEvent("DUEL_REQUESTED", Courtesy.OnDuel)
  m:RegisterEvent("TRADE_SHOW", Courtesy.OnTrade)
  m:RegisterEvent("PARTY_INVITE_REQUEST", Courtesy.OnInvite)
  m:RegisterEvent("GROUP_JOINED", Courtesy.OnGroupJoined)
  m:RegisterEvent("PLAYER_REGEN_DISABLED", Courtesy.OnFight)
  m:RegisterEvent("PLAYER_REGEN_ENABLED", Courtesy.OnFightOver)
end

function Courtesy.Detach()
  Courtesy.Hide()
  state, invite = { seen = {} }, nil
end

-- The courtesy memory (tests): how many people were answered lately.
function Courtesy.Remembered()
  local n = 0
  for _ in pairs(state.seen or {}) do
    n = n + 1
  end
  return n
end
