-- Bastian's Chat, the store of records (plan-chat-v3.md §1, ADR 0075): every record in the ring of
-- its stream, the repost keys (the newest line of a seller's offer or a group stands for the older
-- ones), the open requests ranked as the player should see them (§3.2: a Game Master, a friend,
-- the guild, a stranger), and the session's ledger of what the player gained. The views read
-- only this. Pure: the time is handed in, no WoW API.
local _, ns = ...

local Store = {}
Store.__index = Store
ns.Store = Store

Store.STREAMS = { "direct", "group", "guild", "world", "market", "lfg", "mine", "addons", "junk", "fight" }
-- records kept per stream for the session
Store.CAPS = {
  direct = 300,
  group = 500,
  guild = 500,
  world = 300,
  market = 300,
  lfg = 300,
  mine = 300,
  addons = 200,
  junk = 500,
  fight = 100, -- one recap line per fight (Fights.lua)
}
-- seconds a request stays open by itself (whispers stay until answered or dismissed)
Store.ASK_LIFE = { mention = 600, warning = 60, watch = 300 }
Store.ASKS_KEPT = 200 -- answered and gone requests remembered, for the digest

-- how the writer ranks a whisper (§3.2, "stranger->guild->friend->blizzard tech
-- support/Game master"); a request with a timer sits above the guild and strangers while it runs
local REL_RANK = { gm = 4, friend = 3, bnet = 3, guild = 2, group = 2, stranger = 1 }
local TIMED =
  { invite = true, duel = true, trade = true, ready = true, summon = true, resurrect = true, warning = true }

function Store.Rank(a)
  if a.rel == "gm" then
    return 4
  end
  if a.kind == "away" then
    return 3.5 -- the player's own state stays in view while it lasts (V10)
  elseif a.kind == "digest" then
    return 3
  end
  if a.kind == "whisper" then
    return REL_RANK[a.rel] or 1
  end
  if TIMED[a.kind] then
    return 2.5
  end
  if a.kind == "mention" then
    return 1
  end
  return 0.5 -- a watch-list match, a kind deed
end

function Store.New(caps)
  local s = setmetatable({
    caps = caps or Store.CAPS,
    seq = 0,
    lines = {},
    byId = {},
    latest = {}, -- [key] = the newest record id with that key
    posts = {}, -- [key] = how often it was posted this session
    asks = {},
    askSeq = 0,
    listeners = {},
    totals = { stream = {}, tier = {} },
  }, Store)
  for _, id in ipairs(Store.STREAMS) do
    s.lines[id] = {}
  end
  s:ResetLedger()
  return s
end

function Store:ResetLedger()
  self.ledger = { items = {}, copper = 0, xp = 0, rep = {}, quests = {} }
end

function Store:On(fn)
  self.listeners[#self.listeners + 1] = fn
end

function Store:Notify(what, value)
  for _, fn in ipairs(self.listeners) do
    fn(what, value)
  end
end

function Store:Gain(g)
  local L = self.ledger
  if g.kind == "item" and g.item then
    L.items[g.item] = (L.items[g.item] or 0) + (g.qty or 1)
  elseif g.kind == "money" and g.copper then
    L.copper = L.copper + g.copper
  elseif g.kind == "xp" and g.xp then
    L.xp = L.xp + g.xp
  elseif g.kind == "rep" and g.rep and g.faction then
    L.rep[g.faction] = (L.rep[g.faction] or 0) + g.rep
  elseif g.kind == "quest" and g.name then -- V22
    L.quests = L.quests or {}
    L.quests[#L.quests + 1] = g.name
  end
end

-- An own whisper to `name` answers that person's open whisper request.
function Store:Replied(name, t)
  for _, a in ipairs(self.asks) do
    if a.kind == "whisper" and a.who == name and a.state == "open" then
      a.state, a.how, a.unread, a.answeredAt = "answered", "chat", 0, t
      self:Notify("ask", a)
    end
  end
end

-- Opens a request, or for a whisper adds to the person's open one. Returns it.
function Store:Ask(a, rec)
  a.t = a.t or (rec and rec.t) or 0
  if a.kind == "whisper" then
    for _, open in ipairs(self.asks) do
      local same = (a.who and open.who == a.who) or (a.bn and open.bn == a.bn)
      if open.kind == "whisper" and same and (open.state == "open" or open.state == "answered") then
        open.state, open.how = "open", nil
        open.unread = (open.unread or 0) + 1
        open.t, open.last = a.t, rec and rec.id
        if a.rel then
          open.rel = a.rel
        end
        self:Notify("ask", open)
        return open
      end
    end
    a.unread = 1
  end
  if a.kind == "watch" then
    -- a seller's repost is the same match (V19): it refreshes the open card, and one put away
    -- stays away; only one that ran out by itself comes again
    for _, open in ipairs(self.asks) do
      if open.kind == "watch" and open.who == a.who and open.item == a.item and open.dungeon == a.dungeon then
        if open.state == "open" then
          open.t, open.last = a.t, rec and rec.id
          self:Notify("ask", open)
          return open
        elseif open.how == "dismissed" then
          return open
        end
      end
    end
  end
  self.askSeq = self.askSeq + 1
  a.id = self.askSeq
  a.state = a.state or "open"
  a.last = rec and rec.id
  self.asks[#self.asks + 1] = a
  self:Prune()
  self:Notify("ask", a)
  return a
end

function Store:AskById(id)
  for _, a in ipairs(self.asks) do
    if a.id == id then
      return a
    end
  end
  return nil
end

-- A request answered (how: "chat", "courtesy", "gestures", "game"), its text when one was sent.
function Store:Answer(id, how, text)
  local a = self:AskById(id)
  if a then
    a.state, a.how, a.answer, a.unread = "answered", how, text, 0
    self:Notify("ask", a)
  end
  return a
end

function Store:Dismiss(id)
  local a = self:AskById(id)
  if a then
    a.state, a.how = "gone", "dismissed"
    self:Notify("ask", a)
  end
  return a
end

-- Forgets the oldest requests no longer open beyond ASKS_KEPT.
function Store:Prune()
  local closed = 0
  for _, a in ipairs(self.asks) do
    if a.state ~= "open" then
      closed = closed + 1
    end
  end
  local i = 1
  while closed > Store.ASKS_KEPT and i <= #self.asks do
    if self.asks[i].state ~= "open" then
      table.remove(self.asks, i)
      closed = closed - 1
    else
      i = i + 1
    end
  end
end

-- The open requests at `now`, the most important first: rank, then the newest.
function Store:OpenAsks(now)
  local out = {}
  for _, a in ipairs(self.asks) do
    local life = a.expires or (Store.ASK_LIFE[a.kind] and a.t + Store.ASK_LIFE[a.kind])
    if a.state == "open" and life and now and now > life then
      a.state, a.how = "gone", "expired"
    end
    if a.state == "open" then
      out[#out + 1] = a
    end
  end
  table.sort(out, function(x, y)
    local rx, ry = Store.Rank(x), Store.Rank(y)
    if rx ~= ry then
      return rx > ry
    end
    if x.t ~= y.t then
      return x.t > y.t
    end
    return x.id > y.id
  end)
  return out
end

-- Adds a record (Relevance filled its stream and tier); returns it with its id.
function Store:Add(rec)
  self.seq = self.seq + 1
  rec.id = self.seq
  local stream = self.lines[rec.stream] and rec.stream or "addons"
  rec.stream = stream
  local list = self.lines[stream]
  list[#list + 1] = rec
  self.byId[rec.id] = rec
  local cap = self.caps[stream] or 200
  while #list > cap do
    local old = table.remove(list, 1)
    self.byId[old.id] = nil
  end
  local t = self.totals
  t.stream[stream] = (t.stream[stream] or 0) + 1
  t.tier[rec.tier or 4] = (t.tier[rec.tier or 4] or 0) + 1
  if rec.key then
    self.posts[rec.key] = (self.posts[rec.key] or 0) + 1
    rec.posts = self.posts[rec.key]
    self.latest[rec.key] = rec.id
  end
  if rec.gain then
    self:Gain(rec.gain)
  end
  if stream == "direct" and rec.own and rec.who and rec.who.name then
    self:Replied(rec.who.name, rec.t)
  end
  if rec.ask then
    self:Ask(rec.ask, rec)
  end
  self:Notify("add", rec)
  return rec
end

function Store:Get(id)
  return self.byId[id]
end

-- Is this the newest line of its offer or group (or a line without a key)?
function Store:IsLatest(rec)
  return not rec.key or self.latest[rec.key] == rec.id
end

-- The records of some streams, oldest first. opts = { streams = { [id] = true } or nil for all,
-- maxTier, latest (a repost hides the older line), match = fn(rec) -> bool, limit (the newest n) }.
function Store:Query(opts)
  opts = opts or {}
  local out = {}
  for _, id in ipairs(Store.STREAMS) do
    if not opts.streams or opts.streams[id] then
      for _, rec in ipairs(self.lines[id]) do
        if
          (not opts.maxTier or (rec.tier or 4) <= opts.maxTier)
          and (not opts.latest or self:IsLatest(rec))
          and (not opts.match or opts.match(rec))
        then
          out[#out + 1] = rec
        end
      end
    end
  end
  table.sort(out, function(a, b)
    return a.id < b.id
  end)
  if opts.limit and #out > opts.limit then
    local newest = {}
    for i = #out - opts.limit + 1, #out do
      newest[#newest + 1] = out[i]
    end
    out = newest
  end
  return out
end

-- What the store holds: records per stream now, records per tier since the start, open requests.
function Store:Counts(now)
  local streams = {}
  for _, id in ipairs(Store.STREAMS) do
    streams[id] = #self.lines[id]
  end
  local tiers = {}
  for tier = 0, 5 do
    tiers[tier] = self.totals.tier[tier] or 0
  end
  return { streams = streams, tiers = tiers, asks = #self:OpenAsks(now), total = self.seq }
end

-- How many lines a stream took since the start (the world column's summary, V16).
function Store:Total(stream)
  return self.totals.stream[stream] or 0
end

-- Drops a stream's records (at logout the public ones: they are never kept, ADR 0042 §5).
function Store:Clear(stream)
  for _, rec in ipairs(self.lines[stream] or {}) do
    self.byId[rec.id] = nil
  end
  self.lines[stream] = {}
end
