-- Bastian's Chat version 3, the rows of a list of records (plan-chat-v3.md §7.2, §8): the feed
-- that turns records into the items a list shows (the player's own gains folded into one ledger
-- row per half minute, a repost shown once, the newest; a speaker's following lines without the
-- name again; the lines under the tier counted, not shown) and how each kind of row is drawn in
-- the virtual list. The feed is pure; the drawing reads the theme.
local _, ns = ...
local B = Bastians
local S = B.UI.Style
local L = ns.L
local Model = ns.Model

local Rows = {}
ns.Rows = Rows

Rows.LEDGER_SECS = 30 -- one ledger row per half minute of the player's gains
Rows.SPEAKER_SECS = 60 -- a speaker's next line within this joins their block
Rows.PAD = 2 -- above and below a row's text
Rows.STRIPE = 2 -- the tier's stripe at a row's left edge
Rows.INDENT = 12 -- a speaker's following line
Rows.STRIPED = { [0] = true, [3] = true } -- the tiers whose rows carry their stripe
Rows.VIA_WORDS = { courtesy = "by Courtesy", gestures = "by Gestures", away = "by Away" } -- §3.3

-- ---------------------------------------------------------------------------------------------
-- The live filters (plan §7.3, V8): the suite's search syntax (ADR 0045) over records
-- ---------------------------------------------------------------------------------------------

local LINK_HAS = { link = true, item = true, quest = true, spell = true, achievement = true, url = true }

-- The fields a panel's filter line knows: from:, in:, has:, tier:, rel:, item:, price, role:,
-- dungeon:, via:. Plain words search the record's words (never a secret line's).
Rows.FIELDS = {
  from = {
    get = function(rec)
      return rec.who and rec.who.name
    end,
  },
  ["in"] = {
    get = function(rec)
      local out = {} -- no holes: a missing part is left out, not nil
      for _, v in ipairs({ rec.stream or false, rec.chatType and rec.chatType:lower() or false }) do
        if v then
          out[#out + 1] = v
        end
      end
      out[#out + 1] = rec.channel
      out[#out + 1] = rec.channelKind
      return out
    end,
  },
  has = {
    kind = "flag",
    get = function(rec, value)
      if not LINK_HAS[value] then
        return nil
      end
      for _, link in ipairs(rec.links or {}) do
        if value == "link" or link.kind == value then
          return true
        end
      end
      return false
    end,
  },
  tier = {
    kind = "number",
    get = function(rec)
      return rec.tier
    end,
  },
  rel = {
    get = function(rec)
      return rec.who and rec.who.rel
    end,
  },
  item = {
    get = function(rec)
      local out = {}
      for _, link in ipairs(rec.links or {}) do
        if link.kind == "item" then
          out[#out + 1] = link.text
        end
      end
      return out
    end,
  },
  price = {
    kind = "money",
    get = function(rec)
      return rec.intent and rec.intent.price
    end,
  },
  role = {
    get = function(rec)
      return rec.intent and rec.intent.roles
    end,
  },
  dungeon = {
    get = function(rec)
      return rec.intent and rec.intent.dungeon
    end,
  },
  via = {
    get = function(rec)
      return rec.via
    end,
  },
  -- the kind of line as version 2's tabs named it (say, whisper, guild, officer, group, channel,
  -- npc, loot, progress, system, addon, bnet): none is a part of another, so a match is exact;
  -- the views made from the tabs read it (Views.FromTab)
  cat = {
    get = function(rec)
      return Model.Category(rec.chatType)
    end,
  },
}
Rows.FIELD_NAMES = "from, in, has, tier, rel, item, price, role, dungeon, via, cat"

-- A panel's filter text compiled (nil for none): a query that matches records, plain words over
-- the record's whole entry since V29 (Find.Hay: its text, sender, channel, stream, relation, offer
-- and group words, items, dungeons).
function Rows.Query(text)
  return ns.Find.Query(text)
end

-- ---------------------------------------------------------------------------------------------
-- The feed (pure)
-- ---------------------------------------------------------------------------------------------

local Feed = {}
Feed.__index = Feed

-- What a board shows an intent as (V14): an offer card, a group card.
local BOARD_KIND = { wts = "offer", wtb = "offer", lfm = "group", lfg = "group" }

-- opts = { off = { [stream] = true } (streams not shown), maxTier (0..5), query (Rows.Query),
-- board (offers and groups as cards), since (the oldest time shown: a board's posts age out),
-- blocks (a person's lines as speaker blocks: the name once, the lines under it, V15), byDungeon
-- (a group post goes into its dungeon's card, V18), plain (every line whole, a speaker's next
-- line with the name again: the decks' Team), reasons (a junk line says why it was taken) }
function Rows.NewFeed(opts)
  return setmetatable({
    opts = opts or {},
    matched = 0, -- records the filter let through
    items = {},
    buckets = {}, -- [half minute] = its ledger item
    byKey = {}, -- [repost key] = the item that shows it
    dungeons = {}, -- [dungeon] = its card (byDungeon, V18)
    last = nil, -- the last line item, for the speaker blocks
    shown = 0, -- the items shown (a repost hides its older one): a tab's count (V16)
    folded = 0, -- lines under the tier
    junk = 0,
  }, Feed)
end

-- Does the feed show this stream at all?
function Feed:Shows(rec)
  return not (self.opts.off and self.opts.off[rec.stream])
end

-- A record into the feed. Returns the item added at the end (nil for none) and an item that
-- changed (a ledger row that grew, an older post a repost hides), which must be measured again.
function Feed:Add(rec)
  if not self:Shows(rec) then
    return nil
  end
  if self.opts.since and (rec.t or 0) < self.opts.since then
    return nil -- an old post: gone from the board, not counted
  end
  local q = self.opts.query
  if q then
    if not q:Match(rec) then
      return nil -- the live filter: neither shown nor counted as folded
    end
    self.matched = self.matched + 1
  end
  if (rec.tier or 4) > (self.opts.maxTier or 5) then
    if rec.stream == "junk" then
      self.junk = self.junk + 1
    else
      self.folded = self.folded + 1
    end
    return nil
  end
  if rec.stream == "mine" and rec.gain then
    local bucket = math.floor((rec.t or 0) / Rows.LEDGER_SECS)
    local item = self.buckets[bucket]
    self.last = nil
    if item then
      item.recs[#item.recs + 1] = rec
      return nil, item
    end
    item = { kind = "ledger", t = rec.t, recs = { rec } }
    self.buckets[bucket] = item
    self.items[#self.items + 1] = item
    self.shown = self.shown + 1
    return item
  end
  local board = self.opts.board and rec.intent and BOARD_KIND[rec.intent.kind]
  if board == "group" and self.opts.byDungeon and rec.intent.dungeon then
    return self:AddToDungeon(rec)
  end
  local item = { kind = board or "rec", rec = rec }
  if self.opts.reasons and rec.stream == "junk" then
    item.why = rec.reason or "filtered" -- shown after the line (the decks' "N hidden")
  end
  local changed
  if rec.key then
    local older = self.byKey[rec.key]
    if older then
      older.hidden = true
      changed = older
      self.shown = self.shown - 1
    end
    self.byKey[rec.key] = item
  end
  local prev = self.last and self.last.rec
  if
    prev
    and rec.who
    and prev.who
    and rec.who.name ~= nil
    and prev.who.name == rec.who.name
    and prev.chatType == rec.chatType
    and not rec.intent
    and not prev.intent
    and not self.opts.plain
    and (rec.t or 0) - (prev.t or 0) < Rows.SPEAKER_SECS
  then
    item.cont = true
  end
  if self.opts.blocks and not board and rec.who and rec.who.name and not rec.secret then
    item.block = true -- drawn under the block's head, not indented
    if not item.cont then
      item.kind = "speaker"
    end
  end
  self.last = item
  self.items[#self.items + 1] = item
  self.shown = self.shown + 1
  return item, changed
end

-- A group post into its dungeon's card (V18): the card is made with the dungeon's first post;
-- a poster's newer post replaces their older one. Returns as Add does.
function Feed:AddToDungeon(rec)
  self.last = nil
  local key = rec.intent.dungeon
  local card = self.dungeons[key]
  if not card then
    card = { kind = "dungeon", dungeon = key, posts = { rec }, t = rec.t }
    self.dungeons[key] = card
    self.items[#self.items + 1] = card
    self.shown = self.shown + 1
    return card
  end
  local name = rec.who and rec.who.name
  for i = #card.posts, 1, -1 do
    local old = card.posts[i]
    if name and old.who and old.who.name == name then
      table.remove(card.posts, i)
    end
  end
  card.posts[#card.posts + 1] = rec
  card.t = rec.t
  return nil, card
end

-- The player's gains of a ledger row, summed: { items = { { id, qty, link } }, copper, xp,
-- rep = { { faction, n } } }, in the order they came.
function Rows.Sum(item)
  local out = { items = {}, copper = 0, xp = 0, rep = {}, quests = {} }
  local itemAt, repAt = {}, {}
  for _, rec in ipairs(item.recs) do
    local g = rec.gain
    if g.kind == "item" and g.item then
      local e = itemAt[g.item]
      if not e then
        local link = Rows.ItemLink(rec.body, g.item)
        e = { id = g.item, qty = 0, link = link }
        itemAt[g.item] = e
        out.items[#out.items + 1] = e
      end
      e.qty = e.qty + (g.qty or 1)
    elseif g.kind == "money" then
      out.copper = out.copper + (g.copper or 0)
    elseif g.kind == "xp" then
      out.xp = out.xp + (g.xp or 0)
    elseif g.kind == "rep" then
      local e = repAt[g.faction]
      if not e then
        e = { faction = g.faction, n = 0 }
        repAt[g.faction] = e
        out.rep[#out.rep + 1] = e
      end
      e.n = e.n + g.rep
    elseif g.kind == "quest" then
      out.quests[#out.quests + 1] = g.name
    end
  end
  return out
end

-- The whole link of an item in a line, its colour code with it, as the game wrote it.
function Rows.ItemLink(text, id)
  if type(text) ~= "string" then
    return nil
  end
  local s = text:find("|Hitem:" .. id .. "[:|]")
  if not s then
    return nil
  end
  local from = (s > 10 and text:sub(s - 10, s - 1):match("^|c%x%x%x%x%x%x%x%x$")) and s - 10 or s
  local _, e = text:find("|h.-|h", s + 2)
  if not e then
    return nil
  end
  local close = text:sub(e + 1, e + 2) == "|r" and e + 2 or e
  return text:sub(from, close)
end

-- ---------------------------------------------------------------------------------------------
-- The boards (plan §7.1, §7.3, V14; the artifact's Market and Groups), pure: the price of one
-- item of an offer, the offer against the market price, how long ago a post came
-- ---------------------------------------------------------------------------------------------

Rows.BOARD_AGE = 300 -- an offer or a group older than five minutes leaves the board
Rows.AT_MARKET = 5 -- within this many percent of the market price: "at market"

-- The price of one item of an offer in copper, or nil: a price "each", the price of a single
-- item, a stack's price shared by its count; "x20 5g" without "each" or "stack" stays unknown.
function Rows.UnitPrice(it)
  if type(it) ~= "table" or type(it.price) ~= "number" then
    return nil
  end
  if it.each == true or not it.qty or it.qty <= 1 then
    return it.price
  end
  if it.each == false then
    return math.floor(it.price / it.qty + 0.5)
  end
  return nil
end

-- An offer against the market's price for one: the difference in whole percent and "good" (a
-- seller under the market, a buyer over it), "bad", or "at" (within AT_MARKET); nil when either
-- price is unknown (golden rule 2).
function Rows.Versus(it, median)
  local unit = Rows.UnitPrice(it)
  if not unit or type(median) ~= "number" or median <= 0 then
    return nil
  end
  local d = math.floor((unit / median - 1) * 100 + 0.5)
  if math.abs(d) < Rows.AT_MARKET then
    return d, "at"
  end
  return d, ((it.kind == "wts") == (d < 0)) and "good" or "bad"
end

-- "45s ago", "3m ago".
function Rows.Ago(t, now)
  local d = math.max(0, (now or 0) - (t or now or 0))
  if d < 60 then
    return L["%ds ago"]:format(math.floor(d))
  end
  return L["%dm ago"]:format(math.floor(d / 60))
end

-- ---------------------------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------------------------

local function profile()
  return ns.mod.db.profile
end

-- A record as the line version 2 decorates (the time, short channels, item icons, web links); its
-- id makes the time a link (Shift+click quotes the line, V33).
local function asLine(rec)
  return { text = rec.text, secret = rec.secret, dim = rec.dim, at = rec.t, id = rec.id }
end

local function short(name)
  return Model.ShortName(name)
end

-- An offer or a group as one structured line (plan §7.2): the kind, the item or the dungeon, the
-- price, who, how often it was posted.
function Rows.IntentText(rec)
  local it, who = rec.intent, rec.who and short(rec.who.name) or "?"
  local posts = (rec.posts or 1) > 1 and (" " .. S.H.dim .. L["posted %dx"]:format(rec.posts) .. "|r") or ""
  if it.kind == "wts" or it.kind == "wtb" then
    local tag = it.kind == "wts" and (S.H.offerSell .. "WTS|r") or (S.H.offerBuy .. "WTB|r")
    local link = Rows.ItemLink(rec.body, it.item) or ("[" .. tostring(it.item) .. "]")
    local qty = it.qty and (" x" .. it.qty) or ""
    local price = it.price and B.UI.Money(it.price) or (S.H.dim .. L["price: ask"] .. "|r")
    local each = it.each == true and (" " .. L["each"]) or ""
    return ("%s %s%s  %s%s  %s%s"):format(tag, link, qty, price, each, who, posts)
  end
  local tag = it.kind == "lfm" and "LFM" or "LFG"
  local roles = {}
  for _, role in ipairs(it.roles or {}) do
    local token = role == "tank" and "roleTank" or role == "heal" and "roleHeal" or "roleDps"
    roles[#roles + 1] = S.H[token] .. role .. "|r"
  end
  local need = it.need and (" " .. it.need) or ""
  local dungeon = it.dungeon or L["a dungeon"]
  return ("%s%s %s  %s  %s%s"):format(tag, need, dungeon, table.concat(roles, " "), who, posts)
end

-- The ledger row's words: "You: [Linen Cloth] x5, 1s 20c, 230 experience, Stormwind +25".
function Rows.LedgerText(item, frame)
  local sum = Rows.Sum(item)
  local parts = {}
  for _, e in ipairs(sum.items) do
    parts[#parts + 1] = (e.link or ("#" .. e.id)) .. (e.qty > 1 and (" x" .. e.qty) or "")
  end
  if sum.copper > 0 then
    parts[#parts + 1] = B.UI.Money(sum.copper)
  end
  -- experience and reputation in their own colours, as the artifact's ledger (V25)
  local xp = Rows.LookColors() and frame and Rows.Code(frame, "chanXp") or ""
  local rep = Rows.LookColors() and frame and Rows.Code(frame, "chanRep") or ""
  local close = xp ~= "" and "|r" or ""
  if sum.xp > 0 then
    parts[#parts + 1] = xp .. L["%d experience"]:format(sum.xp) .. close
  end
  for _, e in ipairs(sum.rep) do
    parts[#parts + 1] = rep .. ("%s %s%d"):format(e.faction, e.n >= 0 and "+" or "", e.n) .. close
  end
  for _, name in ipairs(sum.quests) do
    parts[#parts + 1] = L["%s done"]:format(name) -- V22
  end
  local stamp = Model.Stamp(profile().stamps, item.t) or ""
  return S.H.dim .. stamp .. "|r" .. L["You: %s"]:format(table.concat(parts, ", "))
end

-- ---------------------------------------------------------------------------------------------
-- A person's day (V22; the artifact's "Hover a name: everything that person said today"): the
-- tooltip over a player link lists what that person said this session, every stream.
-- ---------------------------------------------------------------------------------------------

Rows.DAY_LINES = 12

local function sameName(a, b)
  if a == b then
    return true
  end
  return type(a) == "string"
    and type(b) == "string"
    and short(a) == short(b)
    and not (a:find("-") and b:find("-"))
end

-- A person's lines (pure): { lines = { { t, tag, body } } the newest last, more = how many older
-- ones were left out }. A secret line is left out (it cannot be read).
function Rows.PersonLines(recs, name, limit)
  limit = limit or Rows.DAY_LINES
  local all = {}
  for _, rec in ipairs(recs or {}) do
    local who = rec.who and rec.who.name
    if who and sameName(who, name) and not rec.secret and not rec.own and type(rec.body) == "string" then
      local tag = Rows.TAG[rec.chatType]
        or (rec.channelNumber and tostring(rec.channelNumber))
        or (rec.chatType == "WHISPER" and "W")
        or (rec.chatType and rec.chatType:sub(1, 1))
        or "?"
      all[#all + 1] = { t = rec.t, tag = tag, body = rec.body }
    end
  end
  local from = math.max(1, #all - limit + 1)
  local out = {}
  for i = from, #all do
    out[#out + 1] = all[i]
  end
  return { lines = out, more = from - 1 }
end

-- The tooltip of a person's day over `owner`; nothing for the player or a person with no line.
function Rows.ShowPerson(owner, name)
  local me = ns.Compat.PlayerName()
  if not name or (me and sameName(me, name)) then
    return false
  end
  local day = Rows.PersonLines(ns.Chat.Store():Query(), name)
  if #day.lines == 0 then
    return false
  end
  GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
  S.TipLine(GameTooltip, short(name), "tipText")
  if day.more > 0 then
    S.TipLine(GameTooltip, L["and %d more"]:format(day.more), "tipDim")
  end
  for _, line in ipairs(day.lines) do
    local stamp = Model.Stamp("hm", line.t) or ""
    S.TipLine(GameTooltip, stamp .. "[" .. line.tag .. "] " .. line.body, "tipDim", true)
  end
  GameTooltip:Show()
  return true
end

-- ---------------------------------------------------------------------------------------------
-- A click on a person's line (plan-chat-v3.md §4, V5): the game's bar opens on that line's
-- channel, with the slash command typed as the player would type it ("/g ", "/2 ", "/w Name "),
-- the way a card's Reply opens it; a whisper opens its conversation. Nothing is sent.
-- ---------------------------------------------------------------------------------------------

Rows.REPLY = {
  GUILD = "/g ",
  OFFICER = "/o ",
  PARTY = "/p ",
  PARTY_LEADER = "/p ",
  RAID = "/ra ",
  RAID_LEADER = "/ra ",
  RAID_WARNING = "/ra ",
  INSTANCE_CHAT = "/i ",
  INSTANCE_CHAT_LEADER = "/i ",
  SAY = "/s ",
  YELL = "/y ",
  EMOTE = "/s ",
  TEXT_EMOTE = "/s ",
}
local WHISPERS = { WHISPER = true, WHISPER_INFORM = true, BN_WHISPER = true, BN_WHISPER_INFORM = true }

-- The slash command a record's line answers in (pure), or nil: a post on the boards whispers its
-- poster, a channel line answers in its channel by number, a whisper whispers back.
function Rows.SlashFor(rec)
  if type(rec) ~= "table" then
    return nil
  end
  local name = rec.who and rec.who.name
  if (rec.stream == "market" or rec.stream == "lfg") and name and not rec.own then
    return "/w " .. name .. " "
  end
  if rec.chatType == "WHISPER" or rec.chatType == "WHISPER_INFORM" then
    return name and ("/w " .. name .. " ") or nil
  end
  if rec.chatType == "CHANNEL" then
    return rec.channelNumber and ("/" .. rec.channelNumber .. " ") or nil
  end
  return Rows.REPLY[rec.chatType]
end

-- A row clicked: a whisper opens its person's place, any other person's line the game's bar on
-- its channel. Returns what it did ("convo", the slash, or nil).
function Rows.Click(item)
  local rec = item and not item.hidden and item.rec
  if not rec then
    return nil
  end
  local who = rec.who
  if
    WHISPERS[rec.chatType]
    and who
    and (who.name or who.bn)
    and ns.Cards.Open({ who = who.name, bn = who.bn })
  then
    return "convo"
  end
  local slash = Rows.SlashFor(rec)
  if slash then
    ns.Compat.OpenChat(slash)
  end
  return slash
end

-- A right click on a board's card (V19): its item or dungeon on the player's watch list, or off
-- it again. Returns what it toggled ("item", "dungeon") or nil.
function Rows.RightClick(item)
  if not item or item.hidden then
    return nil
  end
  local it = item.rec and item.rec.intent
  if item.kind == "offer" and it and it.item then
    ns.Chat.ToggleWatch("item", it.item, Rows.ItemLink(item.rec.body, it.item))
    return "item"
  end
  local dungeon = item.kind == "dungeon" and item.dungeon or (item.kind == "group" and it and it.dungeon)
  if dungeon then
    ns.Chat.ToggleWatch("dungeon", dungeon)
    return "dungeon"
  end
  return nil
end

-- Why an offer or a dungeon is on the watch list now (V19), for the boards: the player's own
-- entries and the quests' items; a dungeon only in range is "your level" already, so not here.
function Rows.WatchWhy(it)
  local facts = ns.Chat.Facts and ns.Chat.Facts()
  local found = facts and facts.watch and ns.Relevance.Watch(it, facts.watch)
  return (found and found.why ~= "range") and found or nil
end

-- The words of why: "Kill Defias Bandits needs 5", "on your watch list", "a group for your level".
function Rows.WhyText(w)
  if type(w) ~= "table" then
    return nil
  end
  if w.why == "quest" then
    local title = w.title or L["a quest"]
    return type(w.need) == "number" and L["%s needs %d"]:format(title, w.need)
      or L["%s needs it"]:format(title)
  elseif w.why == "own" then
    return L["on your watch list"]
  elseif w.why == "range" then
    return L["a group for your level"]
  end
  return nil
end

-- Does a click on the row do something? (its highlight on hover)
local function clickable(item)
  local rec = item and item.rec
  return rec ~= nil and (Rows.SlashFor(rec) ~= nil or (WHISPERS[rec.chatType] and rec.who ~= nil))
end

-- A row's frame: a stripe, one text, the links clickable (the version 2 handlers), and a plain
-- click on the row's text outside a link answers in its channel (V5).
local function makeRow(parent)
  local f = CreateFrame("Button", nil, parent)
  f.wash = S.fill(f, S.C.tier0, "BACKGROUND")
  S.tint(f.wash, S.C.tier0, 0)
  f.hl = S.fill(f, S.C.hover, "HIGHLIGHT")
  f.hl:SetAllPoints()
  f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  f:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
      -- a board's card: its item or dungeon on the watch list (V19); any other row its menu (V33)
      if not Rows.RightClick(self.item) then
        ns.Menus.Line(self.item or self.ledger, self)
      end
      return
    end
    if button == "LeftButton" and IsShiftKeyDown() and self.when and self.item and self.item.rec then
      local ok, over = pcall(self.when.IsMouseOver, self.when)
      if ok and over then
        ns.Menus.Quote(self.item.rec) -- Shift+click on a speaker block's time (V33)
        return
      end
    end
    if button ~= "LeftButton" or IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown() then
      return
    end
    -- a link's own click may come before or after this one in the same frame: the row waits a
    -- frame and steps aside when a link took the click
    local at = GetTime()
    local item = self.item
    C_Timer.After(0, function()
      if self.linkAt ~= at and self.item == item then
        Rows.Click(item)
      end
    end)
  end)
  f.stripe = S.fill(f, S.C.tier0, "BORDER")
  f.stripe:ClearAllPoints()
  f.stripe:SetPoint("TOPLEFT", 0, 0)
  f.stripe:SetPoint("BOTTOMLEFT", 0, 0)
  f.stripe:SetWidth(Rows.STRIPE)
  f.text = f:CreateFontString(nil, "ARTWORK")
  f.text:SetJustifyH("LEFT")
  f.text:SetWordWrap(true)
  if f.SetHyperlinksEnabled then
    f:SetHyperlinksEnabled(true)
  end
  f:SetScript("OnHyperlinkClick", function(self, link, text, button)
    if ns.Menus.IsTimeLink(link) then
      -- a line's time: Shift+click puts the line into the input line (V33); a plain click is the
      -- row's (it answers in the line's channel)
      if button == "LeftButton" and IsShiftKeyDown() then
        self.linkAt = GetTime()
        ns.Menus.QuoteId(link:sub(#ns.Menus.TIME_LINK + 1))
      end
      return
    end
    self.linkAt = GetTime()
    ns.View.OnLink(self, link, text, button)
  end)
  f:SetScript("OnHyperlinkEnter", function(self, link)
    if type(link) == "string" and link:find("^player:") then
      Rows.ShowPerson(self, link:match("^player:([^:]+)")) -- a person's day (V22)
      return
    end
    if type(link) == "string" and not link:find("^player") and not link:find("^addon") then
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
      pcall(GameTooltip.SetHyperlink, GameTooltip, link)
      GameTooltip:Show()
    end
  end)
  f:SetScript("OnHyperlinkLeave", function()
    GameTooltip:Hide()
  end)
  return f
end

-- The space above and below a row's text: the density of Chat's look (V13).
function Rows.Pad()
  return profile().density == "compact" and 0 or Rows.PAD
end

local function setText(f, text, width, indent)
  local pad = Rows.Pad()
  ns.View.ApplyFont(f.text)
  f.text:ClearAllPoints()
  f.text:SetPoint("TOPLEFT", f, "TOPLEFT", Rows.STRIPE + 4 + (indent or 0), -pad)
  f.text:SetWidth(math.max(10, width - Rows.STRIPE - 6 - (indent or 0)))
  f.text:SetText(S.ReadableText(text or "", f)) -- the game's codes readable on a light look (V25)
  return math.floor((f.text:GetStringHeight() or 12) + 2 * pad + 0.5)
end

-- ---------------------------------------------------------------------------------------------
-- The channels' colours (plan-chat-v3.md V25; the artifact's --c-whisper ... --c-npc): a line in
-- its chat type's token of the look, or in the game's own colour when the player chose it.
-- ---------------------------------------------------------------------------------------------

Rows.CHANNEL_TOKENS = {
  WHISPER = "chanWhisper",
  WHISPER_INFORM = "chanWhisper",
  AFK = "chanWhisper",
  DND = "chanWhisper",
  BN_WHISPER = "chanBnet",
  BN_WHISPER_INFORM = "chanBnet",
  BN_INLINE_TOAST_ALERT = "chanBnet",
  PARTY = "chanParty",
  PARTY_LEADER = "chanParty",
  INSTANCE_CHAT = "chanParty",
  INSTANCE_CHAT_LEADER = "chanParty",
  RAID = "chanRaid",
  RAID_LEADER = "chanRaid",
  RAID_WARNING = "chanWarning",
  GUILD = "chanGuild",
  GUILD_ACHIEVEMENT = "chanGuild",
  OFFICER = "chanOfficer",
  SAY = "chanSay",
  YELL = "chanYell",
  EMOTE = "chanEmote",
  TEXT_EMOTE = "chanEmote",
  CHANNEL = "chanChannel",
  COMMUNITIES_CHANNEL = "chanChannel",
  LOOT = "chanLoot",
  MONEY = "chanLoot",
  CURRENCY = "chanLoot",
  COMBAT_XP_GAIN = "chanXp",
  COMBAT_FACTION_CHANGE = "chanRep",
  SYSTEM = "chanSystem",
  SKILL = "chanSystem",
  ACHIEVEMENT = "chanSystem",
  TRADESKILLS = "chanSystem",
  MONSTER_SAY = "chanNpc",
  MONSTER_YELL = "chanNpc",
  MONSTER_EMOTE = "chanNpc",
  MONSTER_WHISPER = "chanNpc",
  MONSTER_PARTY = "chanNpc",
  RAID_BOSS_EMOTE = "chanNpc",
  RAID_BOSS_WHISPER = "chanNpc",
}

-- The token of a record's chat type, nil for one without.
function Rows.ChannelToken(rec)
  return type(rec) == "table" and Rows.CHANNEL_TOKENS[rec.chatType] or nil
end

-- Does the chat draw the look's channel colours (the default), or the game's own?
function Rows.LookColors()
  return profile().channelColors ~= "game"
end

-- A text in a record's colour (V25): the look's token for its chat type where it shows (`frame`'s
-- palette, so a light look gets its dark twins), else the game's colour the line came with;
-- `fallback` a token for a record without either. Returns whether it coloured.
function Rows.InkLine(fs, frame, rec, fallback)
  local token = Rows.LookColors() and Rows.ChannelToken(rec) or nil
  if token and S.Tok(frame, token) then
    S.ink(fs, S.Tok(frame, token))
    return true
  end
  if type(rec) == "table" and type(rec.r) == "number" then
    S.inked[fs] = nil -- the game's colour, a value: no theme change repaints it
    local r, g, b = rec.r, rec.g, rec.b
    if S.Light(frame) then -- the game's colour is made for its dark frames (V25)
      r, g, b = S.ReadableColor(r, g, b, S.Tok(frame, "panel"))
    end
    fs:SetTextColor(r, g, b)
    return true
  end
  if fallback then
    S.ink(fs, S.Tok(frame, fallback))
  end
  return false
end

-- A token's colour code as `frame`'s palette has it (its window's look), for words in a line.
function Rows.Code(frame, token)
  local p = S.PaletteOf(frame)
  return (p and p.H[token]) or S.H[token] or ""
end

-- the wash behind a row of these tiers: only what needs the player (a whisper, a mention); every
-- other tier its stripe alone (plan-chat-one-window.md §8, V34; , screen 9:
-- the gains' green wash turned a stream of Mine olive)
Rows.WASH = { [0] = 0.08 }

local function stripe(f, tier)
  local on = profile().tierStripe ~= false
  local token = on and Rows.STRIPED[tier] and S.C["tier" .. tier]
  if token then
    S.tint(f.stripe, token, tier == 3 and 0.5 or 1)
  end
  f.stripe:SetShown(token ~= nil and token ~= false)
  local wash = on and tier and Rows.WASH[tier] -- a record without a tier (Relevance failed): none
  S.tint(f.wash, wash and S.C["tier" .. tier] or S.C.tier0, wash or 0)
end

-- The kinds of row a record list draws (Bastians.UI.VirtualList kinds).
Rows.KINDS = {
  rec = {
    make = makeRow,
    fill = function(f, item, width)
      local rec = item.rec
      f.item = item
      if item.hidden then
        f.text:SetText("")
        f.stripe:Hide()
        S.tint(f.wash, S.C.tier0, 0)
        return 0
      end
      S.tint(f.hl, S.C.hover, clickable(item) and 0.25 or 0)
      stripe(f, rec.tier)
      local text, indent
      -- an offer or a group as its structured line; a service (V45) is read as it was written
      local it = rec.intent
      if it and it.kind ~= "service" and (rec.stream == "market" or rec.stream == "lfg") then
        text = (Model.Stamp(profile().stamps, rec.t) or "") .. Rows.IntentText(rec)
      elseif item.cont and type(rec.body) == "string" then
        text, indent = rec.body, (not item.block) and Rows.INDENT or nil
      else
        text = ns.View.Decorate(asLine(rec))
      end
      if item.why and type(text) == "string" then
        text = text .. " " .. S.H.dim .. "(" .. L[item.why] .. ")|r"
      end
      if rec.via and Rows.VIA_WORDS[rec.via] and type(text) == "string" then
        text = text .. " " .. S.H.dim .. L[Rows.VIA_WORDS[rec.via]] .. "|r"
      end
      local h = setText(f, text, width, indent)
      Rows.InkLine(f.text, f, rec) -- the channel's colour (V25)
      return h
    end,
  },
  ledger = {
    make = makeRow,
    fill = function(f, item, width)
      f.item = nil -- the player's own gains: nowhere to answer
      f.ledger = item -- its menu copies it (V33)
      S.tint(f.hl, S.C.hover, 0)
      stripe(f, 2)
      local h = setText(f, Rows.LedgerText(item, f), width)
      S.ink(f.text, S.Tok(f, Rows.LookColors() and "chanLoot" or "tier2"))
      return h
    end,
  },
}

-- ---------------------------------------------------------------------------------------------
-- The boards' cards (V14): an offer, a group. The row's frame (its links, its click that
-- whispers the poster) on a card's plate: a tag (WTS, WTB, LFM, LFG), the title in the row's
-- text, the price or "your level" at the right, a second line (who, how long ago, "posted 3x",
-- the market or the roles) and a button that whispers.
-- ---------------------------------------------------------------------------------------------

Rows.CARD_PAD = 7
Rows.BOARD_GAP = 5 -- between two cards of a board

-- Gold's market price for one, or nil (no `prices` provider, or none known).
function Rows.MarketPrice(id)
  local prices = id and B:GetService("prices")
  if not prices then
    return nil
  end
  local ok, p = pcall(prices.Price, prices, id)
  return ok and type(p) == "table" and type(p.median) == "number" and p.median or nil
end

-- A dungeon's levels { lo, hi } by its English name (the words' value), from Data's dungeon
-- records; nil without Data or a record. Found once per name.
local bands = {}
local function findBand(data, name)
  local ok, hits = pcall(data.Find, data, "dungeon", name, 5)
  if not ok or type(hits) ~= "table" or not hits[1] then
    return nil
  end
  local pick = hits[1]
  for _, h in ipairs(hits) do
    if type(h.name) == "string" and h.name:lower() == name:lower() then
      pick = h
      break
    end
  end
  local okRec, rec = pcall(data.Get, data, "dungeon", pick.id)
  if okRec and type(rec) == "table" and rec.levelLo and rec.levelHi then
    return { rec.levelLo, rec.levelHi }
  end
  return nil
end

function Rows.Band(name)
  if type(name) ~= "string" then
    return nil
  end
  if bands[name] == nil then
    local data = B:GetService("data")
    if not data then
      return nil
    end
    -- "The Deadmines" may be "Deadmines" in the data: the name without its article second
    local band = findBand(data, name) or (name:find("^The ") and findBand(data, name:sub(5)))
    if not band then
      return nil -- asked again next time: the pack may load later
    end
    bands[name] = band
  end
  return bands[name]
end

local function makeBoard(parent)
  local f = makeRow(parent)
  f.stripe:Hide()
  f.plate = S.roundFill(f, S.C.card, "radiusSmall")
  f.edges = S.roundEdges(f, S.C.cardEdge, "radiusSmall")
  f.tag = CreateFrame("Frame", nil, f)
  f.tag:SetSize(30, 14)
  f.tag.fill = S.roundFill(f.tag, S.C.offerSell, "radiusSmall")
  f.tag.text = S.SetRole(S.text(f.tag, 10, S.C.offerSell), "number") -- WTS, LFM: the numbers' face (V17)
  f.tag.text:SetPoint("CENTER", 0, 0)
  f.side = S.SetRole(S.text(f, 12, S.C.text), "number") -- the price, or "your level"
  f.side:SetJustifyH("RIGHT")
  f.meta = S.text(f, 11, S.C.muted)
  f.meta:SetJustifyH("LEFT")
  f.meta:SetWordWrap(true)
  f.act = S.action(f, {
    icon = "invite",
    label = L["Whisper"],
    row = true,
    boxed = true,
    onClick = function()
      Rows.Click(f.item)
    end,
  })
  -- every word of the card, for the copy box and the tests
  function f.Words(self)
    return table.concat({
      self.tag.text:GetText() or "",
      self.text:GetText() or "",
      self.side:GetText() or "",
      self.meta:GetText() or "",
    }, "  ")
  end
  return f
end

-- The card's parts in place; returns its height. tag = { text, token }, title, side, meta, act.
local function layCard(f, width, spec)
  local pad = Rows.CARD_PAD
  S.tint(f.tag.fill, spec.token, 0.18)
  S.ink(f.tag.text, spec.token)
  f.tag.text:SetText(spec.tag)
  f.tag:SetWidth(math.max(26, (f.tag.text:GetStringWidth() or 0) + 8))
  f.tag:ClearAllPoints()
  f.tag:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -pad)
  f.tag:Show()
  f.side:SetText(spec.side or "")
  f.side:ClearAllPoints()
  f.side:SetPoint("TOPRIGHT", f, "TOPRIGHT", -pad, -pad)
  local sideW = spec.side and math.max(30, f.side:GetStringWidth() or 0) or 0
  ns.View.ApplyFont(f.text)
  f.text:ClearAllPoints()
  f.text:SetPoint("TOPLEFT", f.tag, "TOPRIGHT", 5, 1)
  f.text:SetWidth(math.max(20, width - 2 * pad - f.tag:GetWidth() - 5 - sideW - 6))
  f.text:SetText(S.ReadableText(spec.title or "", f))
  local h1 = math.max(14, f.text:GetStringHeight() or 14)
  f.act:SetLabel(spec.act)
  f.act:ClearAllPoints()
  f.act:SetPoint("TOPRIGHT", f, "TOPRIGHT", -pad + 2, -(pad + h1 + 3))
  f.act:Show()
  local actH, actW = f.act:GetHeight() or 18, f.act:GetWidth() or 60
  f.meta:ClearAllPoints()
  f.meta:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -(pad + h1 + 6))
  f.meta:SetWidth(math.max(20, width - 2 * pad - actW - 6))
  f.meta:SetText(S.ReadableText(spec.meta or "", f))
  -- on the watch list (V19): the artifact's gold edge
  S.setEdges(f.edges, spec.why and S.C.tier3 or S.C.cardEdge)
  local h2 = math.max(actH, (f.meta:GetStringHeight() or 12) + 3)
  return math.floor(pad + h1 + 3 + h2 + pad + 0.5)
end

local function hideCard(f)
  f.text:SetText("")
  f.side:SetText("")
  f.meta:SetText("")
  f.tag:Hide()
  f.act:Hide()
  return 0
end

local function who(rec)
  return rec.who and rec.who.name and short(rec.who.name) or "?"
end

-- An offer's card: [WTS] [Linen Cloth] x20 .... 19c each / Pellwyn, 2m ago, posted 3x, -12% vs
-- market [Whisper].
function Rows.OfferSpec(rec, now, median, have, why)
  local it = rec.intent
  local sell = it.kind == "wts"
  local unit = Rows.UnitPrice(it)
  local side
  if unit then
    side = B.UI.Money(unit) .. ((it.qty or 1) > 1 and (" " .. S.H.dim .. L["each"] .. "|r") or "")
  elseif it.price then
    side = B.UI.Money(it.price) -- the price as written: for one or for all, it does not say
  else
    side = S.H.dim .. L["price: ask"] .. "|r"
  end
  local link = Rows.ItemLink(rec.body, it.item) or ("[" .. tostring(it.item) .. "]")
  local qty = (it.qty and it.qty > 1) and (" " .. S.H.dim .. "x" .. it.qty .. "|r") or ""
  local meta = { who(rec), Rows.Ago(rec.t, now) }
  if (rec.posts or 1) > 1 then
    meta[#meta + 1] = L["posted %dx"]:format(rec.posts)
  end
  local d, verdict = Rows.Versus(it, median)
  if d then
    local code = verdict == "good" and S.H.good or verdict == "bad" and S.H.bad or S.H.dim
    local word = verdict == "at" and L["at market"] or L["%+d%% vs market"]:format(d)
    meta[#meta + 1] = code .. word .. "|r"
  end
  if type(have) == "number" and have > 0 then -- the bags' count (V18); none or unknown: nothing
    meta[#meta + 1] = L["you have %d"]:format(have)
  end
  local text = table.concat(meta, ", ")
  if why then -- on the watch list (V19): why, on a line of its own
    text = text .. "\n" .. S.H.tier3 .. why .. "|r"
  end
  return {
    tag = sell and "WTS" or "WTB",
    token = sell and S.C.offerSell or S.C.offerBuy,
    title = link .. qty,
    side = side,
    meta = text,
    act = L["Whisper"],
    why = why,
  }
end

local ROLE_TOKEN = { tank = "roleTank", heal = "roleHeal", dps = "roleDps" }

-- A dungeon's head: "The Deadmines  lvl 17-26" and "your level" when the player's level lies
-- within them (nil side otherwise, and no levels without Data or a record).
function Rows.DungeonHead(name, level)
  local title = name or L["a dungeon"]
  local band = Rows.Band(name)
  local side
  if band then
    title = title .. "  " .. S.H.dim .. L["lvl %d-%d"]:format(band[1], band[2]) .. "|r"
    if type(level) == "number" and level >= band[1] and level <= band[2] then
      side = S.H.tier3 .. L["your level"] .. "|r"
    end
  end
  return { title = title, side = side }
end

-- One post: its tag (LFM, LF2M, LFG) and token, "Haskel needs TANK HEAL, 2m ago, posted 2x", and
-- the button's word.
function Rows.PostSpec(rec, now)
  local it = rec.intent
  local lfm = it.kind == "lfm"
  local roles = {}
  for _, role in ipairs(it.roles or {}) do
    roles[#roles + 1] = S.H[ROLE_TOKEN[role] or "roleDps"] .. role:upper() .. "|r"
  end
  local first = who(rec)
  if #roles > 0 then
    first = lfm and L["%s needs %s"]:format(first, table.concat(roles, " "))
      or (first .. " " .. table.concat(roles, " "))
  end
  local parts = { first, Rows.Ago(rec.t, now) }
  if (rec.posts or 1) > 1 then
    parts[#parts + 1] = L["posted %dx"]:format(rec.posts)
  end
  return {
    tag = lfm and (it.need and ("LF" .. it.need .. "M") or "LFM") or "LFG",
    token = lfm and S.C.tier1 or S.C.accent,
    text = table.concat(parts, ", "),
    act = lfm and L["Ask to join"] or L["Whisper"],
  }
end

-- A group's card: [LF2M] The Deadmines  lvl 17-26 .... your level / Haskel needs TANK HEAL, 2m
-- ago [Ask to join]. Since V18 for a post whose dungeon was not recognised (the others share
-- their dungeon's card).
function Rows.GroupSpec(rec, now, level)
  local head = Rows.DungeonHead(rec.intent.dungeon, level)
  local post = Rows.PostSpec(rec, now)
  return {
    tag = post.tag,
    token = post.token,
    title = head.title,
    side = head.side,
    meta = post.text,
    act = post.act,
  }
end

-- The board's order when it is filled (V18): the dungeons in the player's level range last,
-- nearest the input line (a board is drawn from the bottom up), the others above them; within
-- each by the newest post. Sorts `items` in place and returns it.
function Rows.OrderBoard(items, level)
  local keyed = {}
  for i, item in ipairs(items) do
    local name = item.dungeon or (item.rec and item.rec.intent and item.rec.intent.dungeon)
    local band = name and Rows.Band(name)
    local fit = band ~= nil and type(level) == "number" and level >= band[1] and level <= band[2]
    keyed[i] = { item = item, fit = fit and 1 or 0, t = item.t or (item.rec and item.rec.t) or 0, i = i }
  end
  table.sort(keyed, function(a, b)
    if a.fit ~= b.fit then
      return a.fit < b.fit
    end
    if a.t ~= b.t then
      return a.t < b.t
    end
    return a.i < b.i
  end)
  for i, k in ipairs(keyed) do
    items[i] = k.item
  end
  return items
end

local function boardKind(spec)
  return {
    make = makeBoard,
    fill = function(f, item, width)
      f.item = item
      if item.hidden then
        return hideCard(f)
      end
      S.tint(f.hl, S.C.hover, 0.25)
      return layCard(f, width, spec(item.rec))
    end,
  }
end

Rows.KINDS.offer = boardKind(function(rec)
  local id = rec.intent.item
  local why = Rows.WhyText(Rows.WatchWhy(rec.intent))
  return Rows.OfferSpec(rec, time(), Rows.MarketPrice(id), id and ns.Compat.ItemCount(id), why)
end)
Rows.KINDS.group = boardKind(function(rec)
  return Rows.GroupSpec(rec, time(), ns.Compat.PlayerLevel())
end)

-- A dungeon's card (V18; the artifact's `groupsHTML`): the dungeon, its levels and "your level"
-- on top, then up to four posts, the newest first, each a line with its tag, who needs what and
-- how long ago, and a button that whispers its poster; "and N more" under them.
Rows.DUNGEON_POSTS = 4
Rows.POST_H = 20 -- a post's line, at least

local function postLine(f, i)
  local line = f.lines[i]
  if line then
    return line
  end
  line = CreateFrame("Frame", nil, f)
  line.tag = CreateFrame("Frame", nil, line)
  line.tag:SetSize(30, 14)
  line.tag.fill = S.roundFill(line.tag, S.C.tier1, "radiusSmall")
  line.tag.text = S.SetRole(S.text(line.tag, 10, S.C.tier1), "number")
  line.tag.text:SetPoint("CENTER", 0, 0)
  line.text = S.text(line, 11, S.C.text)
  line.text:SetJustifyH("LEFT")
  line.text:SetWordWrap(false)
  line.act = S.action(line, {
    icon = "invite",
    label = L["Whisper"],
    row = true,
    boxed = true,
    onClick = function()
      Rows.Click({ rec = line.rec })
    end,
  })
  f.lines[i] = line
  return line
end

local function makeDungeon(parent)
  local f = makeBoard(parent)
  f.tag:Hide()
  f.act:Hide()
  f.lines = {}
  -- every word of the card: the head, then each shown post's tag and line
  function f.Words(self)
    local out = { self.text:GetText() or "", self.side:GetText() or "" }
    for _, line in ipairs(self.lines) do
      if line:IsShown() then
        out[#out + 1] = (line.tag.text:GetText() or "") .. " " .. (line.text:GetText() or "")
      end
    end
    out[#out + 1] = self.meta:GetText() or ""
    return table.concat(out, "  ")
  end
  return f
end

local function layDungeon(f, width, item, now, level)
  local pad = Rows.CARD_PAD
  local head = Rows.DungeonHead(item.dungeon, level)
  f.side:SetText(head.side or "")
  f.side:ClearAllPoints()
  f.side:SetPoint("TOPRIGHT", f, "TOPRIGHT", -pad, -pad)
  local sideW = head.side and math.max(30, f.side:GetStringWidth() or 0) or 0
  ns.View.ApplyFont(f.text)
  f.text:ClearAllPoints()
  f.text:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -pad)
  f.text:SetWidth(math.max(20, width - 2 * pad - sideW - 6))
  f.text:SetText(S.ReadableText(head.title, f))
  local y = pad + math.max(14, f.text:GetStringHeight() or 14) + 4
  local n = math.min(#item.posts, Rows.DUNGEON_POSTS)
  for i = 1, n do
    local rec = item.posts[#item.posts - i + 1] -- the newest first
    local spec = Rows.PostSpec(rec, now)
    local line = postLine(f, i)
    line.rec = rec
    S.tint(line.tag.fill, spec.token, 0.18)
    S.ink(line.tag.text, spec.token)
    line.tag.text:SetText(spec.tag)
    line.tag:SetWidth(math.max(26, (line.tag.text:GetStringWidth() or 0) + 8))
    line.tag:ClearAllPoints()
    line.tag:SetPoint("LEFT", line, "LEFT", 0, 0)
    line.act:SetLabel(spec.act)
    line.act:ClearAllPoints()
    line.act:SetPoint("RIGHT", line, "RIGHT", 0, 0)
    line.text:ClearAllPoints()
    line.text:SetPoint("LEFT", line.tag, "RIGHT", 5, 0)
    line.text:SetPoint("RIGHT", line.act, "LEFT", -6, 0)
    line.text:SetText(S.ReadableText(spec.text, f))
    local h = math.max(Rows.POST_H, (line.act:GetHeight() or 18) + 2)
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -y)
    line:SetPoint("RIGHT", f, "RIGHT", -pad + 2, 0)
    line:SetHeight(h)
    line:Show()
    y = y + h + 2
  end
  for i = n + 1, #f.lines do
    f.lines[i].rec = nil
    f.lines[i]:Hide()
  end
  f.meta:ClearAllPoints()
  local foot = {}
  if #item.posts > n then
    foot[#foot + 1] = L["and %d more"]:format(#item.posts - n)
  end
  local why = Rows.WhyText(Rows.WatchWhy({ kind = "lfm", dungeon = item.dungeon }))
  if why then -- on the watch list (V19)
    foot[#foot + 1] = S.H.tier3 .. why .. "|r"
  end
  S.setEdges(f.edges, why and S.C.tier3 or S.C.cardEdge)
  if #foot > 0 then
    f.meta:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -y)
    f.meta:SetWidth(math.max(20, width - 2 * pad))
    f.meta:SetText(table.concat(foot, "\n"))
    y = y + (f.meta:GetStringHeight() or 12) + 2
  else
    f.meta:SetText("")
  end
  return math.floor(y + pad + 0.5)
end

Rows.KINDS.dungeon = {
  make = makeDungeon,
  fill = function(f, item, width)
    f.item = item -- a click on the card itself answers nobody: its posts' buttons do
    S.tint(f.hl, S.C.hover, 0)
    return layDungeon(f, width, item, time(), ns.Compat.PlayerLevel())
  end,
}

-- ---------------------------------------------------------------------------------------------
-- Speaker blocks (plan §7.1, V15; the artifact's "Your people"): a person's lines under their
-- name once. The block's head: the channel's letter in the channel's colour, the name as the
-- game wrote it (its class colour, a link), the time at the right; the line under it; the
-- person's next lines within a minute follow as rows of their own, not indented.
-- ---------------------------------------------------------------------------------------------

Rows.TAG = {
  GUILD = "G",
  OFFICER = "O",
  PARTY = "P",
  PARTY_LEADER = "P",
  RAID = "R",
  RAID_LEADER = "R",
  RAID_WARNING = "R",
  INSTANCE_CHAT = "I",
  INSTANCE_CHAT_LEADER = "I",
}

-- The player link of a line as the game wrote it (its colour codes with it), the brackets off;
-- nil when the line has none.
function Rows.PlayerLink(text)
  if type(text) ~= "string" then
    return nil
  end
  local s = text:find("|Hplayer:", 1, true)
  if not s then
    return nil
  end
  local from = (s > 10 and text:sub(s - 10, s - 1):match("^|c%x%x%x%x%x%x%x%x$")) and s - 10 or s
  local _, e = text:find("|h.-|h", s + 2)
  if not e then
    return nil
  end
  local close = text:sub(e + 1, e + 2) == "|r" and e + 2 or e
  return (text:sub(from, close):gsub("|h%[(.-)%]|h", "|h%1|h", 1))
end

local function makeSpeaker(parent)
  local f = makeRow(parent)
  f.rule = S.fill(f, S.C.divider, "BORDER") -- between two blocks
  f.rule:ClearAllPoints()
  f.rule:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  f.rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  f.rule:SetHeight(1)
  f.tag = CreateFrame("Frame", nil, f)
  f.tag:SetSize(14, 12)
  f.tag.edges = S.roundEdges(f.tag, S.C.line, "radiusSmall")
  f.tag.text = S.SetRole(S.text(f.tag, 9, S.C.text), "number")
  f.tag.text:SetPoint("CENTER", 0, 0)
  f.head = f:CreateFontString(nil, "ARTWORK") -- the name: a link, so on the row's frame
  f.head:SetJustifyH("LEFT")
  f.when = S.SetRole(S.text(f, 10, S.C.dim), "number")
  f.when:SetJustifyH("RIGHT")
  return f
end

Rows.KINDS.speaker = {
  make = makeSpeaker,
  fill = function(f, item, width)
    local rec = item.rec
    f.item = item
    if item.hidden then
      f.text:SetText("")
      f.head:SetText("")
      f.when:SetText("")
      f.tag:Hide()
      f.stripe:Hide()
      S.tint(f.wash, S.C.tier0, 0)
      return 0
    end
    S.tint(f.hl, S.C.hover, clickable(item) and 0.25 or 0)
    stripe(f, rec.tier)
    local pad, x = Rows.Pad() + 2, Rows.STRIPE + 4
    local letter = Rows.TAG[rec.chatType]
    f.tag:ClearAllPoints()
    if letter then
      f.tag.text:SetText(letter)
      if Rows.InkLine(f.tag.text, f, rec) then -- the channel's colour (V25), the edge with it
        local r, g, b = f.tag.text:GetTextColor()
        if r then
          f.tag.edges:SetVertexColor(r, g, b)
        end
      end
      f.tag:SetPoint("TOPLEFT", f, "TOPLEFT", x, -(pad + 1))
      f.tag:Show()
    else
      f.tag:Hide()
    end
    f.when:SetText(((Model.Stamp(profile().stamps, rec.t) or ""):gsub("%s+$", "")))
    f.when:ClearAllPoints()
    f.when:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -(pad + 1))
    ns.View.ApplyFont(f.head)
    S.ink(f.head, S.C.text)
    f.head:ClearAllPoints()
    f.head:SetPoint("TOPLEFT", f, "TOPLEFT", x + (letter and 18 or 0), -pad)
    f.head:SetWidth(math.max(20, width - x - (letter and 18 or 0) - 44))
    f.head:SetText(S.ReadableText(Rows.PlayerLink(rec.text) or short(rec.who.name), f))
    local headH = math.max(13, f.head:GetStringHeight() or 13)
    local body = ns.View.Decorate({ text = rec.body, secret = rec.secret, dim = rec.dim, noStamp = true })
    ns.View.ApplyFont(f.text)
    f.text:ClearAllPoints()
    f.text:SetPoint("TOPLEFT", f, "TOPLEFT", x, -(pad + headH + 2))
    f.text:SetWidth(math.max(10, width - x - 2))
    f.text:SetText(S.ReadableText(body or "", f))
    Rows.InkLine(f.text, f, rec) -- the channel's colour (V25)
    return math.floor(pad + headH + 2 + (f.text:GetStringHeight() or 12) + Rows.Pad() + 0.5)
  end,
}

-- The record a row shows (the first of a ledger row), or nil.
function Rows.RecOf(item)
  return item and (item.rec or (item.recs and item.recs[1])) or nil
end

-- Does any shown item hold this record? (the timeline's jump)
function Rows.Find(items, rec)
  for _, item in ipairs(items) do
    if item.rec == rec then
      return item
    end
    for _, r in ipairs(item.recs or {}) do
      if r == rec then
        return item
      end
    end
  end
  return nil
end

-- The first shown item at or after a record id.
function Rows.FindFrom(items, id)
  for _, item in ipairs(items) do
    local rec = Rows.RecOf(item)
    if rec and rec.id and rec.id >= id and not item.hidden then
      return item
    end
  end
  return nil
end
