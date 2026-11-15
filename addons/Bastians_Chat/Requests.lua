-- Bastian's Chat version 3, what the game asks of the player (plan-chat-v3.md §3.1, §3.3, V6): an
-- invite, a duel, a trade, a ready check, a summon, a resurrection as requests in the store, whose
-- cards stay until they are answered (on the card, in the game's window, or in Courtesy's ring)
-- or the game ends them; Courtesy's kind deeds (a buff, an emote at the player, a camp) as cards
-- of their own; and the lines Courtesy and Gestures send, tagged with the app (§3.3, D9). Courtesy
-- speaks by the bus only: BASTIANS_MOMENT when its ring opens, BASTIANS_MOMENT_DONE with the
-- answer; a card's Courtesy button asks it to open the ring again (BASTIANS_MOMENT_REOPEN).
local _, ns = ...
local B = Bastians
local Model, Compat = ns.Model, ns.Compat

local Requests = {}
ns.Requests = Requests

-- seconds a request stays open by itself; a trade stays until its window closes
Requests.LIFE = { invite = 60, duel = 60, ready = 40, summon = 120, resurrect = 60, deed = 60 }
Requests.TAG_SECS = 3 -- an app's line arrives this soon after it said it sends one
Requests.MOMENT_SECS = 5 -- Courtesy's moment and the game's request of one person, this close
-- Courtesy's moments and the request each one answers; every other moment is a kind deed
Requests.MOMENT_OF = { invite = "invite", duel = "duel", trade = "trade", rez = "resurrect" }
Requests.KINDS = { invite = true, duel = true, trade = true, ready = true, summon = true, resurrect = true }
local EMOTES = { EMOTE = true, TEXT_EMOTE = true, SAY = true }

local tags = {} -- { app, text, any, untilT }: lines an app said it sends
local moments = {} -- { id, kind, who, t }: Courtesy's moments not yet joined to a request

local function store()
  return ns.Chat.Store()
end

local function same(a, b)
  return a ~= nil and b ~= nil and Model.ShortName(a) == Model.ShortName(b)
end

-- Opens the request of a kind from a person (one at a time), joined to Courtesy's moment for it.
function Requests.Open(kind, who, life, extra)
  local t = time()
  for _, a in ipairs(store().asks) do
    if a.kind == kind and a.state == "open" and (a.who == who or same(a.who, who)) then
      return a
    end
  end
  local a = { kind = kind, who = who, t = t, expires = life and (t + life) or nil }
  for k, v in pairs(extra or {}) do
    a[k] = v
  end
  for i = #moments, 1, -1 do
    local m = moments[i]
    if t - m.t > Requests.MOMENT_SECS then
      table.remove(moments, i)
    elseif Requests.MOMENT_OF[m.kind] == kind and same(m.who, who) then
      a.moment = m.id
      table.remove(moments, i)
    end
  end
  return store():Ask(a)
end

-- The game ended a kind of request (the window closed, the check finished): its card goes.
function Requests.Close(kind, who)
  for _, a in ipairs(store().asks) do
    if a.kind == kind and a.state == "open" and (not who or same(a.who, who)) then
      store():Answer(a.id, "game")
    end
  end
end

-- The player's answer on a card: the game's call, then the card goes. False when the client
-- refused or lacks the call (probe X3): the card stays and says to answer in the game's window.
function Requests.Answer(ask, yes)
  local ok = Compat.AnswerRequest(ask.kind, yes)
  if ok then
    store():Answer(ask.id, "chat")
  else
    ask.refused = true
    store():Notify("ask", ask)
  end
  return ok
end

-- ---------------------------------------------------------------------------------------------
-- The game's events
-- ---------------------------------------------------------------------------------------------

local function plainName(v)
  v = Compat.Plain(v)
  return type(v) == "string" and v ~= "" and v or nil
end

function Requests.OnInvite(_, _, who)
  Requests.Open("invite", plainName(who), Requests.LIFE.invite)
end

function Requests.OnDuel(_, _, who)
  Requests.Open("duel", plainName(who), Requests.LIFE.duel)
end

function Requests.OnTrade()
  Requests.Open("trade", Compat.UnitPlayerName("NPC"))
end

function Requests.OnReady(_, _, who, seconds)
  Requests.Open("ready", plainName(who), tonumber(Compat.Plain(seconds)) or Requests.LIFE.ready)
end

function Requests.OnSummon()
  Requests.Open("summon", Compat.Summoner(), Requests.LIFE.summon)
end

function Requests.OnResurrect(_, _, who)
  Requests.Open("resurrect", plainName(who), Requests.LIFE.resurrect)
end

-- the events that end a request: the request kind each one closes
Requests.ENDS = {
  PARTY_INVITE_CANCEL = "invite",
  GROUP_JOINED = "invite",
  DUEL_FINISHED = "duel", -- also when the challenger takes the request back
  TRADE_CLOSED = "trade",
  READY_CHECK_FINISHED = "ready",
  CANCEL_SUMMON = "summon",
  PLAYER_ALIVE = "resurrect",
  PLAYER_UNGHOST = "resurrect",
}

-- ---------------------------------------------------------------------------------------------
-- Courtesy and Gestures (the bus)
-- ---------------------------------------------------------------------------------------------

-- BASTIANS_MOMENT(id, kind, who): Courtesy's ring opened. A request's moment joins its card (or
-- waits a few seconds for the game's event); any other is a kind deed with a card of its own.
function Requests.OnMoment(_, _, id, kind, who)
  local req = Requests.MOMENT_OF[kind]
  if not req then
    Requests.Open("deed", who, Requests.LIFE.deed, { moment = id, deed = kind })
    return
  end
  for _, a in ipairs(store().asks) do
    if a.kind == req and a.state == "open" and same(a.who, who) then
      a.moment = id
      store():Notify("ask", a)
      return
    end
  end
  moments[#moments + 1] = { id = id, kind = kind, who = who, t = time() }
end

-- BASTIANS_MOMENT_DONE(id, how, text): answered or declined in the ring, the card goes with the
-- answer; a deed's card also goes when its ring closes unanswered (a request stays: the game ends it).
function Requests.OnMomentDone(_, _, id, how, text)
  for _, a in ipairs(store().asks) do
    if a.moment == id and a.state == "open" then
      if how == "answered" or how == "declined" then
        store():Answer(a.id, "courtesy", text)
      elseif a.kind == "deed" then
        store():Dismiss(a.id)
      end
    end
  end
end

-- A card's Courtesy button: the ring of its moment again.
function Requests.Reopen(ask)
  if ask.moment then
    B:Fire("BASTIANS_MOMENT_REOPEN", ask.moment)
  end
end

-- BASTIANS_SAYING(app, chatType, target, text): an app sends a line right now.
function Requests.OnSaying(_, _, app, _, _, text)
  tags[#tags + 1] =
    { app = app, text = type(text) == "string" and text or nil, untilT = GetTime() + Requests.TAG_SECS }
end

-- BASTIANS_GESTURE_FIRED: the next own emote or saying is the gesture's.
function Requests.OnGesture()
  tags[#tags + 1] = { app = "gestures", any = true, untilT = GetTime() + Requests.TAG_SECS }
end

-- The app that sent an own line (Chat.Record), or nil.
function Requests.Via(rec)
  if not rec.own then
    return nil
  end
  local t = GetTime()
  for i = #tags, 1, -1 do
    local tag = tags[i]
    if tag.untilT < t then
      table.remove(tags, i)
    elseif
      (tag.text and type(rec.body) == "string" and rec.body:find(tag.text, 1, true))
      or (tag.any and EMOTES[rec.chatType])
    then
      table.remove(tags, i)
      return tag.app
    end
  end
  return nil
end

function Requests.Attach(m)
  tags, moments = {}, {}
  m:RegisterEvent("PARTY_INVITE_REQUEST", Requests.OnInvite)
  m:RegisterEvent("DUEL_REQUESTED", Requests.OnDuel)
  m:RegisterEvent("TRADE_SHOW", Requests.OnTrade)
  m:RegisterEvent("READY_CHECK", Requests.OnReady)
  m:RegisterEvent("CONFIRM_SUMMON", Requests.OnSummon)
  m:RegisterEvent("RESURRECT_REQUEST", Requests.OnResurrect)
  for event, kind in pairs(Requests.ENDS) do
    -- an event a client lacks is refused by it and must not stop the others (12.11.2026: an
    -- unknown event stopped the chat's whole start in game)
    local ok, err = pcall(m.RegisterEvent, m, event, function()
      Requests.Close(kind)
    end)
    if not ok then
      ns.Chat.Note("requests " .. event, err)
    end
  end
  m:On("BASTIANS_MOMENT", Requests.OnMoment)
  m:On("BASTIANS_MOMENT_DONE", Requests.OnMomentDone)
  m:On("BASTIANS_SAYING", Requests.OnSaying)
  m:On("BASTIANS_GESTURE_FIRED", Requests.OnGesture)
end
