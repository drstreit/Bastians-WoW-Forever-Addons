-- Bastian's Chat, the two decks (plan-chat-two-decks.md, ADR 0077; the owner's answers of
-- 14.11.2026): Know above (All, Loot, Fight, Trade, LFG, World, Addons and a chip per watch; summed
-- up, never counted), Talk and Team below (the group, Guild, the active people, "People N"; counted
-- per person and for the group). Know's strip lies in the window's head in place of the title; a
-- splitter moves the border; Know folds to one line of sums. No rail, no "Down to", no timeline.
-- The lists draw with the rows of version 3 (Rows, People); the store is the same. The other parts
-- reach this window through ns.Front.
local _, ns = ...
local B = Bastians
local S = B.UI.Style
local L = ns.L
local Model, Compat = ns.Model, ns.Compat

local Decks = {}
ns.Decks = Decks

Decks.MIN_W, Decks.MIN_H = 440, 280
Decks.FIRST_H = 340 -- the first time the decks show, the window has at least this height
Decks.RAIL_W = 0 -- no rail: the request bar and the plates have the window's width
Decks.STRIP_H = 20
Decks.SPLIT_H = 4 -- the splitter over Talk's strip
-- a low window: the strip and the splitter give their room to the lines (the rule, plan §2)
Decks.TIGHT_H, Decks.STRIP_TIGHT, Decks.SPLIT_TIGHT = 320, 15, 2
Decks.SPLIT, Decks.SPLIT_MIN, Decks.SPLIT_MAX = 0.45, 0.2, 0.8 -- Know's share of the lists' height
Decks.LINE_H = 16 -- a deck never gets less than one line
Decks.HEAD_H = 20 -- a view's head line (Loot's sums, Fight's button, the people's filter)
Decks.FOOT_H = 14 -- "N hidden"
Decks.FIND_H = 24
Decks.ASKS_H = 26
Decks.PLATES_H = 24
Decks.INSET = 0 -- a list inside its panel
Decks.CHIP_PAD = 5
Decks.CHIP_GAP = 2
Decks.CHIP_MIN = 40 -- a person's chip at least: the name cut, the count whole
Decks.MORE_W = 30 -- "+N" at Know's end
Decks.HEAD_ROOM = 122 -- the head's own buttons beside Know's strip (find, lock, options, close)
Decks.LATELY = 600 -- seconds: "spoken to lately" keeps a person on the strip
Decks.STALE_DAYS = 7 -- a stranger without a line this long leaves the list (the filter finds them)
Decks.ROOM_DAYS = 7 -- a finished group's entry is kept this long
Decks.ROOMS_MAX = 20
Decks.SIDE_W = 900 -- "auto": side by side from this width
Decks.WHO_H = 20 -- a row of the people list
Decks.MAX = 1000 -- rows a list keeps
Decks.BOARD_REFRESH = 30
-- Know's chips: the place's id (a stream's, or "all") and its name
Decks.KNOW = {
  { "all", "All" },
  { "mine", "Loot" },
  { "fight", "Fight" },
  { "market", "Trade" },
  { "lfg", "LFG" },
  { "world", "World" },
  { "addons", "Addons" },
}
Decks.MIX = { mine = true, fight = true, market = true, lfg = true, world = true, addons = true }
Decks.FORMS = { market = { board = true }, lfg = { board = true, byDungeon = true } }
Decks.HIDES = { all = true, world = true } -- the places whose foot says "N hidden"
Decks.WORLDLY = { SAY = true, YELL = true, EMOTE = true, TEXT_EMOTE = true, CHANNEL = true }
Decks.TALK_NAMES = { guild = "Guild", officer = "Officer", people = "People" }
Decks.LEVELS = { { "all", "Everything" }, { "name", "My name and watches" }, { "none", "Nothing" } }
Decks.DEFAULT_LEVEL = { group = "all", guild = "name", officer = "name" }
Decks.SIDES = { { "stacked", "Stacked" }, { "side", "Side by side" }, { "auto", "By the width" } }
Decks.WHERE = { { "both", "Both decks" }, { "know", "Know" }, { "talk", "Talk and Team" } }
Decks.WHEN = { { "all", "Everything kept" }, { "today", "Today" }, { "week", "This week" } }
-- the input line's targets: the bar's chat type and the command that sets it
Decks.SLASH = {
  SAY = "/s ",
  YELL = "/y ",
  PARTY = "/p ",
  RAID = "/ra ",
  INSTANCE_CHAT = "/i ",
  GUILD = "/g ",
  OFFICER = "/o ",
}
Decks.TARGET_WORDS =
  { s = "Say", y = "Yell", p = "Party", ra = "Raid", i = "Instance", g = "Guild", o = "Officer" }

local box -- the decks' frame in the main window
local win -- the main window's record (View's W)
local panes = {} -- know, talk: { id, strip, chips, frame, head, area, inner, list, feed, foot, ... }
local dirty = true -- the store changed while the decks were hidden
local attached = false
local groupUnread = 0 -- the group's lines that came while another place showed
local hit = {} -- [place] = true: a watch or the player's name hit it while another place showed
local officerSeen, watchedSeen, guildSeen = false, false, false
local mark -- the conversation shown: { key, line, n }: "N new" stands before `line`
local find = { where = "both", when = "all" } -- the find line's state (its frame in find.frame)
local deckWins = {} -- [deck] = the window a deck stands in while it is out
local sel -- the people list's row the keys walk to (a person's key)

local function store()
  return ns.Chat.Store()
end

local function tight()
  return win ~= nil and (win.win.frame:GetHeight() or 0) <= Decks.TIGHT_H
end

-- The height of Talk's strip and of the splitter over it: less in a low window.
function Decks.StripHeight()
  return tight() and Decks.STRIP_TIGHT or Decks.STRIP_H
end

function Decks.SplitHeight()
  return tight() and Decks.SPLIT_TIGHT or Decks.SPLIT_H
end

local function P()
  return ns.People
end

local function copy(t)
  local out = {}
  for k, v in pairs(t or {}) do
    out[k] = v
  end
  return out
end

local function personKey(id)
  return type(id) == "string" and id:sub(1, 2) == "p:" and id:sub(3) or nil
end

local function savedName(id)
  return type(id) == "string" and id:sub(1, 2) == "s:" and id:sub(3) or nil
end

-- ---------------------------------------------------------------------------------------------
-- Settings, levels, the migration
-- ---------------------------------------------------------------------------------------------

function Decks.Settings()
  local p = ns.mod.db.profile
  if type(p.decks) ~= "table" then
    p.decks = {}
  end
  local s = p.decks
  if type(s.know) ~= "string" then
    s.know = "all"
  end
  if type(s.talk) ~= "string" then
    s.talk = "people"
  end
  s.split = math.max(Decks.SPLIT_MIN, math.min(Decks.SPLIT_MAX, tonumber(s.split) or Decks.SPLIT))
  for _, key in ipairs({ "out", "windows", "rooms", "lines" }) do
    if type(s[key]) ~= "table" then
      s[key] = {}
    end
  end
  return s
end

local function notify()
  local inbox = ns.Inbox.Settings()
  inbox.notify = type(inbox.notify) == "table" and inbox.notify or {}
  return inbox.notify
end

-- A place's level: "all" (everything: the count and a sound), "name" (my name and watches),
-- "none". People are always everything.
function Decks.Level(place)
  if place == "people" or place == "direct" or personKey(place) then
    return "all"
  end
  return notify()[place] or Decks.DEFAULT_LEVEL[place] or "none"
end

function Decks.SetLevel(place, level)
  notify()[place] = level
end

-- Once per profile: a stream whose sound was on gets "everything" (plan §6); nothing is deleted.
function Decks.Migrate(p)
  if p.levelsFromSounds then
    return nil
  end
  p.levelsFromSounds = true
  local n = 0
  local streams = type(p.sounds) == "table" and type(p.sounds.streams) == "table" and p.sounds.streams or {}
  p.inbox = type(p.inbox) == "table" and p.inbox or {}
  p.inbox.notify = type(p.inbox.notify) == "table" and p.inbox.notify or {}
  for stream, sound in pairs(streams) do
    if sound ~= "none" and p.inbox.notify[stream] == nil then
      p.inbox.notify[stream] = "all"
      n = n + 1
    end
  end
  return n
end

-- ---------------------------------------------------------------------------------------------
-- What the window answers the other parts (ns.Front)
-- ---------------------------------------------------------------------------------------------

local function shown()
  return box ~= nil and box:IsVisible() and ns.View.LayoutKind() == "decks"
end

function Decks.Frame()
  if box and panes.know then
    -- the list the menus copy from: the deck under the mouse, else Talk's
    local over = panes.know.frame:IsVisible() and panes.know.frame:IsMouseOver()
    box.list = over and panes.know.list or panes.talk.list
  end
  return box
end

function Decks.Pane(deck)
  return panes[deck]
end

-- The place Places' windows compare against: never one of theirs (DrawRail moves a deck off a
-- place that left).
function Decks.Place()
  return "all"
end

function Decks.ShownPerson()
  local s = Decks.Settings()
  local key = personKey(s.talk)
  if key and P().Convo(key) then
    return key
  end
  return nil
end

function Decks.ShowsPerson(key)
  return box ~= nil and key ~= nil and Decks.ShownPerson() == key
end

function Decks.GroupUnread()
  return groupUnread
end

local function badge()
  ns.View.UnreadCount(P().Unread() + groupUnread)
end

-- ---------------------------------------------------------------------------------------------
-- Chips
-- ---------------------------------------------------------------------------------------------

local function newChip(pane)
  local b = CreateFrame("Button", nil, pane.strip)
  b:SetHeight(Decks.STRIP_H)
  b.hl = S.fill(b, S.C.hover, "HIGHLIGHT")
  b.line = S.fill(b, S.C.accent, "ARTWORK")
  b.line:ClearAllPoints()
  b.line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 2, 0)
  b.line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 0)
  b.line:SetHeight(2)
  b.label = S.SetRole(S.text(b, 12, S.C.dim), "label")
  b.label:SetPoint("LEFT", b, "LEFT", Decks.CHIP_PAD, 0)
  b.label:SetJustifyH("LEFT")
  b.label:SetWordWrap(false)
  b.count = S.SetRole(S.text(b, 10, S.C.tier0), "number")
  b.count:SetPoint("RIGHT", b, "RIGHT", -Decks.CHIP_PAD, 0)
  b.mark = CreateFrame("Frame", nil, b)
  b.mark:SetSize(5, 5)
  b.mark:SetPoint("TOPRIGHT", b, "TOPRIGHT", -1, -3)
  b.mark.fill = S.roundFill(b.mark, S.C.tier3, "pill")
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function(self, button)
    Decks.ChipClick(self, button)
  end)
  b:SetScript("OnEnter", S.TipEnter)
  b:SetScript("OnLeave", S.TipLeave)
  -- dragged out of the window: a window of its own (V32's windows)
  ns.Places.Draggable(b, function(self)
    return self.id ~= "more" and ns.Places.Valid(self.id) and self.id or nil
  end)
  return b
end

-- A chip filled from its spec { id, text, count, mark, tip, selected, out }; returns its natural
-- width.
local function fillChip(b, spec, deck)
  b.id, b.deck, b.spec = spec.id, deck, spec
  b.tip = spec.tip
  b.label:SetWidth(0)
  b.label:SetText(spec.text or "")
  local n = spec.count
  b.count:SetText(n and n > 0 and tostring(n) or "")
  b.count:SetShown(n ~= nil and n > 0)
  b.mark:SetShown(spec.mark == true and not spec.selected)
  b.selected = spec.selected == true
  S.showPart(b.line, b.selected)
  S.tint(b.line, S.Tok(b, "accent"), 1)
  S.ink(b.label, S.Tok(b, (b.selected and "text") or (spec.out and "muted") or "dim"))
  b.label:SetAlpha(spec.out and 0.6 or 1)
  local w = (b.label:GetStringWidth() or 0) + 2 * Decks.CHIP_PAD
  if b.count:IsShown() then
    w = w + (b.count:GetStringWidth() or 6) + 4
  end
  return math.ceil(w)
end

-- A chip at `x` with the width `w` (its name cut when `w` is under its natural width).
local function placeChip(b, x, w, natural)
  b:ClearAllPoints()
  b:SetPoint("LEFT", b:GetParent(), "LEFT", x, 0)
  b:SetSize(w, b.deck == "talk" and Decks.StripHeight() or Decks.STRIP_H)
  if w < natural then
    local room = w - 2 * Decks.CHIP_PAD
    if b.count:IsShown() then
      room = room - (b.count:GetStringWidth() or 6) - 4
    end
    b.label:SetWidth(math.max(8, room))
  end
  b.cut = w < natural
  b:Show()
end

local function stripWidth(pane)
  local w = pane.strip:GetWidth() or 0
  if w > 0 then
    return w
  end
  local host = deckWins[pane.id] and Decks.Settings().out[pane.id] and deckWins[pane.id].frame
    or (win and win.win.frame)
  local fw = host and host:GetWidth() or Decks.MIN_W
  if pane.id == "know" or (deckWins[pane.id] and Decks.Settings().out[pane.id]) then
    return fw - Decks.HEAD_ROOM
  end
  return fw - 2
end

-- Know's chips: the fixed places, "Watched" once the watch list hit, one per watch (saved search).
function Decks.KnowChips()
  local s = Decks.Settings()
  local out = {}
  for _, pair in ipairs(Decks.KNOW) do
    out[#out + 1] = { id = pair[1], text = L[pair[2]] }
  end
  if watchedSeen or s.know == "watched" then
    out[#out + 1] = { id = "watched", text = L["Watched"], tip = L["What your watch list found"] }
  end
  for _, view in ipairs(ns.Views.List()) do
    out[#out + 1] =
      { id = "s:" .. view.name, text = view.name, tip = L["A watch: %s"]:format(view.query or "") }
  end
  for _, spec in ipairs(out) do
    spec.selected = spec.id == s.know
    spec.mark = hit[spec.id] == true
    spec.out = ns.Places.IsOut(spec.id)
  end
  return out
end

local function groupName()
  return Compat.InRaid() and L["Raid"] or L["Party"]
end

-- The people on the strip, in order: who waits, who is pinned, who was spoken to lately, and the
-- one shown.
function Decks.ActivePeople(now)
  local s = Decks.Settings()
  local People = P()
  local all = People.All()
  local waiting, pinned, lately = {}, {}, {}
  local shownKey = personKey(s.talk)
  for _, key in ipairs(People.Order()) do
    local c = all[key]
    if c and not ns.Places.IsOut("p:" .. key) then
      if (c.unread or 0) > 0 or People.Waits(key) then
        waiting[#waiting + 1] = key
      elseif c.pinned then
        pinned[#pinned + 1] = key
      elseif key == shownKey or (now - (c.last or 0)) <= Decks.LATELY then
        lately[#lately + 1] = key
      end
    end
  end
  local out = {}
  for _, list in ipairs({ waiting, pinned, lately }) do
    for _, key in ipairs(list) do
      out[#out + 1] = key
    end
  end
  return out
end

-- Talk and Team's chips: the group, Guild, Officer, the active people, "People N".
function Decks.TalkChips(now)
  local s = Decks.Settings()
  local People = P()
  local out = {}
  if Compat.GroupSize() or groupUnread > 0 or s.talk == "group" then
    out[#out + 1] = { id = "group", text = groupName(), count = groupUnread, fixed = true }
  end
  if Compat.GuildName() or guildSeen or s.talk == "guild" then
    out[#out + 1] = { id = "guild", text = L["Guild"], fixed = true, mark = hit.guild == true }
  end
  if officerSeen or s.talk == "officer" then
    out[#out + 1] = { id = "officer", text = L["Officer"], fixed = true, mark = hit.officer == true }
  end
  local all = People.All()
  for _, key in ipairs(Decks.ActivePeople(now or time())) do
    local c = all[key]
    local info = People.InfoLine(People.Info(key))
    local rel = People.Rel(key)
    local who = rel and L[People.REL_WORDS[rel] or "Stranger"] or nil
    out[#out + 1] = {
      id = "p:" .. key,
      text = Model.ShortName(c.name),
      count = c.unread or 0,
      person = true,
      tip = Model.ShortName(c.name) .. (who and (": " .. who) or "") .. (info ~= "" and (", " .. info) or ""),
    }
  end
  local n = 0
  for _ in pairs(all) do
    n = n + 1
  end
  out[#out + 1] = { id = "people", text = L["People"] .. " " .. n, fixed = true }
  for _, spec in ipairs(out) do
    spec.selected = spec.id == s.talk
    spec.out = ns.Places.IsOut(spec.id)
  end
  return out
end

-- Know's strip: the chips that fit, the rest behind "+N" (the chip shown always fits).
local function layKnow(pane, specs, width)
  local chips, widths = pane.chips, {}
  for i, spec in ipairs(specs) do
    chips[i] = chips[i] or newChip(pane)
    widths[i] = fillChip(chips[i], spec, "know")
  end
  local x0 = pane.fold and (pane.fold:GetWidth() + 4) or 0
  local total = x0
  for i = 1, #specs do
    total = total + widths[i] + Decks.CHIP_GAP
  end
  local order = {}
  if total <= width then
    for i = 1, #specs do
      order[i] = i
    end
  else
    local x, selected = x0, nil
    for i = 1, #specs do
      if specs[i].selected then
        selected = i
      end
    end
    local room = width - Decks.MORE_W
    for i = 1, #specs do
      if x + widths[i] <= room then
        order[#order + 1] = i
        x = x + widths[i] + Decks.CHIP_GAP
      else
        break
      end
    end
    local last = order[#order] or 0
    if selected and selected > last and #order > 0 then
      order[#order] = selected -- the chip shown takes the last place
    end
  end
  local placed = {}
  local x = x0
  for _, i in ipairs(order) do
    placeChip(chips[i], x, widths[i], widths[i])
    placed[i] = true
    x = x + widths[i] + Decks.CHIP_GAP
  end
  pane.rest = {}
  for i = 1, #specs do
    if not placed[i] then
      chips[i]:Hide()
      pane.rest[#pane.rest + 1] = specs[i]
    end
  end
  for i = #specs + 1, #chips do
    chips[i]:Hide()
  end
  local more = pane.more
  if #pane.rest > 0 then
    local marked = false
    for _, spec in ipairs(pane.rest) do
      marked = marked or spec.mark == true
    end
    fillChip(more, { id = "more", text = "+" .. #pane.rest, mark = marked }, "know")
    placeChip(more, x, Decks.MORE_W, Decks.MORE_W)
  else
    more:Hide()
  end
  pane.shownChips = #order
end

-- Talk's strip: the fixed chips whole, the people in the room that is left, their names cut so
-- that as many as possible show (five at 440 px); who does not fit is in the list.
local function layTalk(pane, specs, width)
  local chips, widths = pane.chips, {}
  local fixed, people = 0, {}
  for i, spec in ipairs(specs) do
    chips[i] = chips[i] or newChip(pane)
    widths[i] = fillChip(chips[i], spec, "talk")
    if spec.person then
      people[#people + 1] = i
    else
      fixed = fixed + widths[i] + Decks.CHIP_GAP
    end
  end
  local room = width - fixed - (pane.menu and (pane.menu:GetWidth() + 4) or 0)
  local natural = 0
  for _, i in ipairs(people) do
    natural = natural + widths[i] + Decks.CHIP_GAP
  end
  local showN, each = #people, nil
  if natural > room then
    showN = math.max(0, math.min(#people, math.floor(room / (Decks.CHIP_MIN + Decks.CHIP_GAP))))
    each = showN > 0 and math.floor(room / showN) - Decks.CHIP_GAP or 0
    -- the chip shown is among them
    local selectedAt
    for n, i in ipairs(people) do
      if specs[i].selected then
        selectedAt = n
      end
    end
    if selectedAt and selectedAt > showN and showN > 0 then
      people[showN], people[selectedAt] = people[selectedAt], people[showN]
    end
  end
  local visible = {}
  for n, i in ipairs(people) do
    visible[i] = n <= showN
  end
  local x, count = 0, 0
  for i, spec in ipairs(specs) do
    if not spec.person then
      placeChip(chips[i], x, widths[i], widths[i])
      x = x + widths[i] + Decks.CHIP_GAP
    elseif visible[i] then
      local w = each and math.min(widths[i], each) or widths[i]
      placeChip(chips[i], x, w, widths[i])
      x = x + w + Decks.CHIP_GAP
      count = count + 1
    else
      chips[i]:Hide()
    end
  end
  for i = #specs + 1, #chips do
    chips[i]:Hide()
  end
  pane.shownPeople = count
end

-- ---------------------------------------------------------------------------------------------
-- The sums (Know folded, Loot's head line)
-- ---------------------------------------------------------------------------------------------

-- "7 items, 1g 12s, 2,140 experience; 3 fights": what the session brought, from the store's
-- ledger and the fights' count. A part that is nothing is left out.
function Decks.SumsText()
  local sum = store().ledger
  local parts = {}
  local items = 0
  for _, n in pairs(sum.items or {}) do
    items = items + n
  end
  if items > 0 then
    parts[#parts + 1] = items == 1 and L["1 item"] or L["%d items"]:format(items)
  end
  if (sum.copper or 0) > 0 then
    parts[#parts + 1] = B.UI.Money(sum.copper)
  end
  if (sum.xp or 0) > 0 then
    parts[#parts + 1] = L["%s experience"]:format(ns.Fights.Number(sum.xp))
  end
  local quests = #(sum.quests or {})
  if quests > 0 then
    parts[#parts + 1] = quests == 1 and L["1 quest done"] or L["%d quests done"]:format(quests)
  end
  local text = table.concat(parts, ", ")
  local fights = ns.Fights.Count()
  if fights > 0 then
    local f = fights == 1 and L["1 fight"] or L["%d fights"]:format(fights)
    text = text ~= "" and (text .. "; " .. f) or f
  end
  return text ~= "" and text or L["Nothing yet this session"]
end

-- ---------------------------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------------------------

local function buildPane(id)
  local pane = { id = id, chips = {} }
  pane.strip = CreateFrame("Frame", nil, box)
  pane.strip:SetHeight(Decks.STRIP_H)
  pane.frame = CreateFrame("Frame", nil, box)
  pane.head = CreateFrame("Frame", nil, pane.frame)
  pane.head:SetHeight(Decks.HEAD_H)
  pane.head.text = S.text(pane.head, 11, S.C.muted)
  pane.head.text:SetPoint("LEFT", pane.head, "LEFT", 6, 0)
  pane.head.text:SetWordWrap(false)
  pane.head:Hide()
  pane.area = CreateFrame("Frame", nil, pane.frame)
  ns.Inbox.Panel(pane.area, "stream")
  pane.inner = CreateFrame("Frame", nil, pane.area)
  pane.inner:SetPoint("TOPLEFT", pane.area, "TOPLEFT", Decks.INSET, -Decks.INSET)
  pane.inner:SetPoint("BOTTOMRIGHT", pane.area, "BOTTOMRIGHT", -Decks.INSET, Decks.INSET)
  pane.list = B.UI.VirtualList.New(pane.inner, {
    kinds = ns.Rows.KINDS,
    stick = true,
    bottomUp = true,
    max = Decks.MAX,
    onBelow = function(n)
      Decks.DrawBelow(pane, n)
    end,
  })
  pane.newer = S.action(pane.area, {
    icon = "plus",
    label = "",
    row = true,
    boxed = true,
    onClick = function()
      pane.list:ScrollToEnd()
    end,
  })
  pane.newer:SetPoint("BOTTOM", pane.area, "BOTTOM", 0, 3)
  pane.newer:Hide()
  pane.empty = S.text(pane.area, 12, S.C.dim)
  pane.empty:SetPoint("CENTER", pane.area, "CENTER", 0, 0)
  pane.empty:SetWidth(260)
  pane.empty:SetWordWrap(true)
  pane.empty:Hide()
  -- "N hidden": a note in the list's lower right corner, so it costs the lines no row
  pane.foot = CreateFrame("Button", nil, pane.area)
  pane.foot:SetHeight(Decks.FOOT_H)
  pane.foot:SetPoint("BOTTOMRIGHT", pane.area, "BOTTOMRIGHT", -(B.UI.VirtualList.BAR_ROOM + 4), 2)
  pane.foot:SetFrameLevel((pane.area:GetFrameLevel() or 1) + 8)
  pane.foot.ground = S.roundFill(pane.foot, S.C.panel, "radiusSmall")
  pane.foot.text = S.text(pane.foot, 10, S.C.dim)
  pane.foot.text:SetPoint("CENTER", pane.foot, "CENTER", 0, 0)
  pane.foot:SetScript("OnClick", function()
    pane.hidden = (not pane.hidden) or nil
    Decks.Fill(pane.id)
    Decks.DrawFoot(pane)
  end)
  pane.foot.tip = L["What the spam filter took, with the reason. A second click hides it again."]
  pane.foot:SetScript("OnEnter", S.TipEnter)
  pane.foot:SetScript("OnLeave", S.TipLeave)
  pane.foot:Hide()
  return pane
end

local function buildKnow()
  local pane = buildPane("know")
  panes.know = pane
  -- the fold at the strip's start, the sums in the chips' place while folded
  pane.fold = S.action(pane.strip, {
    icon = "hide",
    label = L["Fold Know to one line"],
    only = true,
    row = true,
    onClick = function()
      Decks.Fold(not Decks.Settings().folded)
    end,
  })
  pane.fold:SetPoint("LEFT", pane.strip, "LEFT", 0, 0)
  pane.sums = CreateFrame("Button", nil, pane.strip)
  pane.sums:SetPoint("LEFT", pane.fold, "RIGHT", 4, 0)
  pane.sums:SetPoint("RIGHT", pane.strip, "RIGHT", 0, 0)
  pane.sums:SetHeight(Decks.STRIP_H)
  pane.sums.text = S.text(pane.sums, 12, S.C.text)
  pane.sums.text:SetPoint("LEFT", pane.sums, "LEFT", 2, 0)
  pane.sums.text:SetPoint("RIGHT", pane.sums, "RIGHT", -2, 0)
  pane.sums.text:SetJustifyH("LEFT")
  pane.sums.text:SetWordWrap(false)
  pane.sums.tip = L["Know, folded: what this session brought. Click to unfold."]
  pane.sums:SetScript("OnClick", function()
    Decks.Fold(false)
  end)
  pane.sums:SetScript("OnEnter", S.TipEnter)
  pane.sums:SetScript("OnLeave", S.TipLeave)
  -- folded, the sums fill the head: the window is still dragged there
  pane.sums:RegisterForDrag("LeftButton")
  pane.sums:SetScript("OnDragStart", function()
    if not win.win.db.locked then
      win.win.frame:StartMoving()
    end
  end)
  pane.sums:SetScript("OnDragStop", function()
    win.win.frame:StopMovingOrSizing()
    win.win:SavePlace()
  end)
  pane.sums:Hide()
  pane.more = newChip(pane)
  pane.more:Hide()
  -- the view's head: Loot's sums; Fight's count and "Combat log"; a board's "Lines"
  pane.head.log = S.action(pane.head, {
    icon = "open",
    label = L["Combat log"],
    tip = L["The game's own combat log as a window, with its filters. The same button puts it back."],
    row = true,
    boxed = true,
    toggle = true,
    onClick = function()
      ns.Basics.ToggleLog()
      Decks.DrawHeads()
    end,
  })
  pane.head.log:SetPoint("RIGHT", pane.head, "RIGHT", -2, 0)
  pane.head.lines = S.action(pane.head, {
    icon = "page",
    label = L["Lines"],
    tip = L["The posts as lines, or as cards again"],
    row = true,
    boxed = true,
    toggle = true,
    onClick = function()
      local s = Decks.Settings()
      s.lines[s.know] = (not s.lines[s.know]) or nil
      Decks.Rebuild()
    end,
  })
  pane.head.lines:SetPoint("RIGHT", pane.head, "RIGHT", -2, 0)
  return pane
end

local function peopleKey(_, key)
  if key == "DOWN" or key == "UP" then
    Decks.WalkPeople(key == "DOWN" and 1 or -1)
  end
end

local function buildTalk()
  local pane = buildPane("talk")
  panes.talk = pane
  pane.strip:EnableMouse(true)
  pane.strip:RegisterForDrag("LeftButton")
  pane.strip:SetScript("OnDragStart", function()
    local host = Decks.Settings().out.talk and deckWins.talk or win.win
    if not host.db.locked then
      host.frame:StartMoving()
    end
  end)
  pane.strip:SetScript("OnDragStop", function()
    local host = Decks.Settings().out.talk and deckWins.talk or win.win
    host.frame:StopMovingOrSizing()
    host:SavePlace()
  end)
  pane.strip:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" then
      Decks.StripMenu("talk", self)
    end
  end)
  pane.menu = S.action(pane.strip, {
    icon = "settings",
    label = L["Talk and Team: new whisper, emotes, channels, the game's chat settings"],
    only = true,
    row = true,
    onClick = function(self)
      Decks.StripMenu("talk", self)
    end,
  })
  pane.menu:SetPoint("RIGHT", pane.strip, "RIGHT", -2, 0)
  -- the people list's filter line (plan §4)
  local filter = S.search(pane.head, L["Find a person: a name, or a word they wrote"], true)
  filter:SetPoint("LEFT", pane.head, "LEFT", 2, 0)
  filter:SetPoint("RIGHT", pane.head, "RIGHT", -2, 0)
  filter.count = S.SetRole(S.text(filter, 10, S.C.muted), "number")
  filter.count:SetPoint("RIGHT", filter.clear, "LEFT", -2, 0)
  filter:SetScript("OnTextChanged", function(self)
    local text = self:GetText() or ""
    self.hint:SetShown(text == "")
    self.clear:SetShown(text ~= "")
    sel = nil
    if Decks.Settings().talk == "people" then
      Decks.Fill("talk")
    end
  end)
  filter:SetScript("OnEscapePressed", function(self)
    self:SetText("")
    self:ClearFocus()
  end)
  filter:SetScript("OnEnterPressed", function(self)
    if Decks.OpenWalked() then
      self:SetText("")
      self:ClearFocus()
    end
  end)
  filter:HookScript("OnKeyDown", peopleKey)
  if filter.SetAltArrowKeyMode then
    pcall(filter.SetAltArrowKeyMode, filter, false) -- plain Up and Down reach the line
  end
  filter:Hide()
  pane.filter = filter
  return pane
end

local function buildSplitter()
  local sp = CreateFrame("Button", nil, box)
  sp:SetHeight(Decks.SPLIT_H)
  sp.fill = S.fill(sp, S.C.line, "ARTWORK")
  sp.hl = S.fill(sp, S.C.accent, "HIGHLIGHT")
  sp.tip = L["Drag to give Know or Talk more room"]
  sp:SetScript("OnEnter", S.TipEnter)
  sp:SetScript("OnLeave", S.TipLeave)
  sp:SetScript("OnMouseDown", function(self)
    self.dragging = true
    self:SetScript("OnUpdate", function()
      local _, y = GetCursorPosition()
      local scale = box:GetEffectiveScale() or 1
      local top, h = box:GetTop() or 0, Decks.ListsHeight()
      if h > 0 then
        Decks.Split((top - y / scale - Decks.TopRows()) / h)
      end
    end)
  end)
  sp:SetScript("OnMouseUp", function(self)
    self.dragging = nil
    self:SetScript("OnUpdate", nil)
  end)
  sp:SetScript("OnHide", function(self)
    self.dragging = nil
    self:SetScript("OnUpdate", nil)
  end)
  box.splitter = sp
end

local function buildPlates()
  local plates = CreateFrame("Frame", nil, box)
  plates:SetHeight(Decks.PLATES_H)
  plates.label = S.SetRole(S.text(plates, 11, S.C.muted), "label")
  plates.label:SetPoint("LEFT", plates, "LEFT", 4, 0)
  plates.label:SetText(string.upper(L["Answer"]))
  plates.buttons = {}
  plates:Hide()
  box.plates = plates
end

-- The input line's target, named while the game's bar is closed (plan §7, I5).
local function buildTarget()
  local content = win.win.content
  local t = CreateFrame("Button", nil, content)
  t:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 2, 0)
  t:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -18, 0)
  t:SetHeight(ns.View.INPUT_H)
  t.text = S.text(t, 12, S.C.muted)
  t.text:SetPoint("LEFT", t, "LEFT", 6, 0)
  t.hint = S.text(t, 11, S.C.dim)
  t.hint:SetPoint("LEFT", t.text, "RIGHT", 8, 0)
  t.hint:SetText(L["Enter to write"])
  t:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  t:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
      Decks.TargetMenu(self)
    else
      Compat.OpenChat(Decks.Settings().target or "")
    end
  end)
  t.tip = L["Where Enter writes. Click to write; right click for another target, emotes and channels."]
  t:SetScript("OnEnter", S.TipEnter)
  t:SetScript("OnLeave", S.TipLeave)
  t:Hide()
  box.target = t
end

local function findMenu(list, key, anchor, title)
  local items = {}
  for _, pair in ipairs(list) do
    items[#items + 1] = {
      label = L[pair[2]],
      on = find[key] == pair[1],
      onClick = function()
        find[key] = pair[1]
        Decks.DrawFind()
        Decks.Rebuild()
      end,
    }
  end
  B.UI.Menu(anchor, title, items, ns.mod)
  return items
end

local function buildFind()
  local f = CreateFrame("Frame", nil, box)
  f:SetHeight(Decks.FIND_H)
  f.star = S.action(f, {
    icon = "keep",
    label = L["Keep these words as a watch"],
    only = true,
    row = true,
    onClick = function()
      Decks.KeepWatch()
    end,
  })
  f.star:SetPoint("RIGHT", f, "RIGHT", -2, 0)
  f.when = S.action(f, {
    label = "",
    row = true,
    boxed = true,
    onClick = function(self)
      findMenu(Decks.WHEN, "when", self, L["When"])
    end,
  })
  f.when:SetPoint("RIGHT", f.star, "LEFT", -4, 0)
  f.who = S.action(f, {
    label = L["Who"],
    row = true,
    boxed = true,
    onClick = function(self)
      Decks.WhoMenu(self)
    end,
  })
  f.who:SetPoint("RIGHT", f.when, "LEFT", -4, 0)
  f.where = S.action(f, {
    label = "",
    row = true,
    boxed = true,
    onClick = function(self)
      findMenu(Decks.WHERE, "where", self, L["Where"])
    end,
  })
  f.where:SetPoint("RIGHT", f.who, "LEFT", -4, 0)
  f.box = S.search(f, L["Find: words; -word leaves out"], true)
  f.box:SetPoint("LEFT", f, "LEFT", 2, 0)
  f.box:SetPoint("RIGHT", f.where, "LEFT", -4, 0)
  f.box:SetScript("OnTextChanged", function(self)
    local text = self:GetText() or ""
    self.hint:SetShown(text == "")
    self.clear:SetShown(text ~= "")
    if find.applying then
      return
    end
    find.words = text ~= "" and text or nil
    Decks.Rebuild()
  end)
  f.box:SetScript("OnEscapePressed", function()
    Decks.CloseFind()
  end)
  f:Hide()
  find.frame = f
end

-- The find button in the window's head, left of its own buttons.
local function buildHeadParts()
  local head = win.win.head
  local b = S.action(head, {
    icon = "search",
    label = L["Find in the chat"],
    only = true,
    row = true,
    onClick = function()
      Decks.ToggleFind()
    end,
  })
  b:SetPoint("RIGHT", win.win.lock or win.win.options or win.win.close, "LEFT", -4, 0)
  b:Hide()
  box.findButton = b
  head:HookScript("OnMouseUp", function(self, button)
    if button == "RightButton" and ns.View.LayoutKind() == "decks" and not Decks.Settings().out.know then
      Decks.StripMenu("know", self)
    end
  end)
end

-- The decks in the main window W (built once).
function Decks.Build(W)
  if box then
    return box
  end
  win = W
  local content = W.win.content
  box = CreateFrame("Frame", nil, content)
  box:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
  box:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, ns.View.INPUT_H + 2)
  buildKnow()
  buildTalk()
  buildSplitter()
  buildPlates()
  ns.Asks.Build(box)
  buildTarget()
  buildFind()
  buildHeadParts()
  box:SetScript("OnShow", function()
    if dirty then
      Decks.Rebuild()
    end
  end)
  box:SetScript("OnSizeChanged", function()
    if shown() then
      Decks.Layout()
      Decks.DrawStrips()
    end
  end)
  box:Hide()
  return box
end

-- The window's head: Know's strip in place of the title while the decks show; the title back
-- for another layout.
function Decks.TakeHead(W, on)
  if not on then
    W.win.title:Show()
    if panes.know then
      panes.know.strip:Hide()
      panes.talk.strip:Hide()
      box.findButton:Hide()
      box.target:Hide()
    end
    Decks.ShowWindows(false)
  end
end

-- ---------------------------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------------------------

local function sideBySide(s, width)
  if s.side == "side" then
    return true
  end
  return s.side == "auto" and width >= Decks.SIDE_W
end

-- The rows over the lists inside the box (the find line).
function Decks.TopRows()
  return find.frame and find.frame:IsShown() and (Decks.FIND_H + 2) or 0
end

local function bottomRows()
  local n = 0
  if box.asks and box.asks:IsShown() then
    n = n + Decks.ASKS_H + 2
  end
  if box.plates:IsShown() then
    n = n + Decks.PLATES_H + 2
  end
  return n
end

-- The height both lists share (stacked): the box without its other rows.
function Decks.ListsHeight()
  local h = box:GetHeight() or 0
  return math.max(0, h - Decks.TopRows() - bottomRows() - Decks.SplitHeight() - Decks.StripHeight())
end

-- A pane's frame at (x, y) from the box's top left, w by h, and its parts inside.
local function layPane(pane, parent, x, y, w, h)
  local f = pane.frame
  if f:GetParent() ~= parent then
    f:SetParent(parent)
  end
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  f:SetSize(math.max(1, w), math.max(1, h))
  f:Show()
  local top, bottom = 0, 0
  if pane.head:IsShown() then
    pane.head:ClearAllPoints()
    pane.head:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    pane.head:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    top = Decks.HEAD_H
  end
  pane.area:ClearAllPoints()
  pane.area:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top)
  pane.area:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, bottom)
  local ah = math.max(1, h - top - bottom)
  pane.area:SetSize(math.max(1, w), ah)
  local iw, ih = math.max(1, w - 2 * Decks.INSET), math.max(1, ah - 2 * Decks.INSET)
  pane.inner:SetSize(iw, ih)
  pane.list.scroll:SetSize(math.max(1, iw - B.UI.VirtualList.BAR_ROOM), ih)
  pane.height = ih
end

local function layStripAt(pane, parent, x, y, w)
  local strip = pane.strip
  if strip:GetParent() ~= parent then
    strip:SetParent(parent)
  end
  strip:ClearAllPoints()
  strip:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  strip:SetSize(math.max(1, w), Decks.StripHeight())
  strip:Show()
end

-- A strip in a window's head, in place of the title.
local function layStripInHead(pane, host, rightOf)
  local head, strip = host.head, pane.strip
  if strip:GetParent() ~= head then
    strip:SetParent(head)
  end
  strip:SetFrameLevel((head:GetFrameLevel() or 1) + 2)
  strip:ClearAllPoints()
  strip:SetPoint("LEFT", head, "LEFT", 4, 0)
  strip:SetPoint("RIGHT", rightOf, "LEFT", -4, 0)
  strip:SetHeight(Decks.STRIP_H)
  local w = (host.frame:GetWidth() or Decks.MIN_W) - Decks.HEAD_ROOM
  strip:SetWidth(math.max(1, w))
  strip:Show()
  host.title:Hide()
end

-- A deck in the window it left to.
local function layOut(deck)
  local W = Decks.DeckWindow(deck)
  local pane = panes[deck]
  layStripInHead(pane, W, W.lock or W.options or W.close)
  local cw, ch = W.content:GetWidth() or 0, W.content:GetHeight() or 0
  if cw <= 0 or ch <= 0 then
    cw = (W.frame:GetWidth() or 300) - 2
    ch = (W.frame:GetHeight() or 200) - 32
  end
  layPane(pane, W.content, 0, 0, cw, ch)
end

-- Everything in its place: the find line, Know, the splitter, Talk's strip, Talk, and over the
-- input line the request bar and the proposed answers (each only while it shows).
function Decks.Layout()
  if not box then
    return
  end
  local s = Decks.Settings()
  local w, h = box:GetWidth() or 0, box:GetHeight() or 0
  if w <= 0 or h <= 0 then
    local frame = win.win.frame
    w = (frame:GetWidth() or Decks.MIN_W) - 2
    h = (frame:GetHeight() or Decks.MIN_H) - 32 - ns.View.INPUT_H - 2
  end
  local know, talk = panes.know, panes.talk
  local head = win.win.head
  box.findButton:Show()
  -- the rows over the input line
  local bottom = 0
  local asks = box.asks
  if asks then
    asks:ClearAllPoints()
    asks:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 2, bottom)
    asks:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, bottom)
    if asks:IsShown() then
      bottom = bottom + Decks.ASKS_H + 2
    end
  end
  local plates = box.plates
  plates:ClearAllPoints()
  plates:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 2, bottom)
  plates:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, bottom)
  if plates:IsShown() then
    bottom = bottom + Decks.PLATES_H + 2
  end
  local top = 0
  if find.frame:IsShown() then
    find.frame:ClearAllPoints()
    find.frame:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    find.frame:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)
    top = Decks.FIND_H + 2
  end
  local knowIn, talkIn = not s.out.know, not s.out.talk
  -- Know's strip: in the head while Know is in this window
  if knowIn then
    layStripInHead(know, win.win, box.findButton)
    know.fold:Show()
  else
    win.win.title:Show()
    layOut("know")
  end
  if not talkIn then
    layOut("talk")
  end
  local folded = s.folded == true
  know.sums:SetShown(knowIn and folded)
  local rest = math.max(0, h - top - bottom)
  local sp = box.splitter
  sp:Hide()
  if knowIn and folded then
    know.frame:Hide()
  end
  local knowShown = knowIn and not folded
  local stripH, splitH = Decks.StripHeight(), Decks.SplitHeight()
  if knowShown and talkIn and sideBySide(s, w) then
    local kw = math.floor((w - splitH) * s.split)
    layPane(know, box, 0, top, kw, rest)
    layStripAt(talk, box, kw + splitH, top, w - kw - splitH)
    layPane(talk, box, kw + splitH, top + stripH, w - kw - splitH, rest - stripH)
  elseif knowShown and talkIn then
    local lists = math.max(0, rest - splitH - stripH)
    local kh = math.floor(lists * s.split)
    kh = math.max(Decks.LINE_H, math.min(lists - Decks.LINE_H, kh))
    layPane(know, box, 0, top, w, kh)
    sp:ClearAllPoints()
    sp:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -(top + kh))
    sp:SetSize(w, splitH)
    sp:Show()
    layStripAt(talk, box, 0, top + kh + splitH, w)
    layPane(talk, box, 0, top + kh + splitH + stripH, w, lists - kh)
  elseif talkIn then
    layStripAt(talk, box, 0, top, w)
    layPane(talk, box, 0, top + stripH, w, rest - stripH)
  elseif knowShown then
    layPane(know, box, 0, top, w, rest)
  end
  if head and not knowIn and talkIn then
    win.win.title:Show()
  end
  Decks.DrawTarget()
end

-- ---------------------------------------------------------------------------------------------
-- Filling the lists
-- ---------------------------------------------------------------------------------------------

-- The find line's words and oldest time for a deck: nil each when the line is closed or looks
-- elsewhere.
local function findFor(deck)
  if not (find.frame and find.frame:IsShown()) then
    return nil, nil
  end
  if find.where ~= "both" and find.where ~= deck then
    return nil, nil
  end
  local since
  if find.when == "today" then
    local d = date("*t", time())
    since = time({ year = d.year, month = d.month, day = d.day, hour = 0 })
  elseif find.when == "week" then
    since = time() - 7 * 86400
  end
  return find.words, since
end

-- A query that also asks `fn(rec)`; `q` may be nil.
local function both(q, fn)
  if not fn then
    return q
  end
  return {
    Match = function(_, rec)
      return fn(rec) and (not q or q:Match(rec))
    end,
  }
end

local function offOf(streams)
  local off = {}
  for _, id in ipairs(ns.Store.STREAMS) do
    if not streams[id] then
      off[id] = true
    end
  end
  return off
end

local function hasOfficer()
  for _, rec in ipairs(store():Query({ streams = { guild = true } })) do
    if rec.chatType == "OFFICER" then
      return true
    end
  end
  return false
end

-- A group member's say, yell or emote: Team's, not the world's (plan §1).
local function teamSpeech(rec)
  return rec.stream == "world" and rec.who ~= nil and rec.who.grouped == true
end

-- What a place's feed takes: the options of Rows.NewFeed.
function Decks.FeedOpts(deck, id)
  local s = Decks.Settings()
  local pane = panes[deck]
  local words, since = findFor(deck)
  local streams, fn, form
  local name = savedName(id)
  if id == "all" then
    -- the mix of Know: its streams, and who came online (a friend's notice lands in the
    -- whispers' stream); a group member's say and emote lines are the group's
    streams = copy(Decks.MIX)
    streams.direct = true
    fn = function(rec)
      return (rec.stream ~= "direct" or rec.online == true) and not teamSpeech(rec)
    end
  elseif id == "world" then
    streams = { world = true, direct = true, addons = true }
    fn = function(rec)
      if rec.stream == "world" then
        return not teamSpeech(rec)
      end
      return rec.online == true -- "friend online" is the world's, not an addon's (plan §1)
    end
  elseif id == "addons" then
    streams = { addons = true }
    fn = function(rec)
      return not rec.online
    end
  elseif id == "group" then
    streams = { group = true, world = true }
    fn = function(rec)
      return rec.stream == "group" or teamSpeech(rec)
    end
  elseif id == "watched" then
    streams = copy(Decks.MIX)
    streams.group, streams.guild = true, true
    fn = function(rec)
      return rec.watch ~= nil
    end
  elseif name then
    local view = ns.Views.Find(name)
    if view and type(view.streams) == "table" and next(view.streams) then
      streams = copy(view.streams)
    else
      streams = copy(Decks.MIX)
      streams.group, streams.guild, streams.direct = true, true, true
    end
    words = ((view and view.query) or "") .. " " .. (words or "")
  elseif id == "officer" then
    streams = { guild = true }
    fn = function(rec)
      return rec.chatType == "OFFICER"
    end
  elseif id == "guild" then
    streams = { guild = true }
    if officerSeen then
      fn = function(rec)
        return rec.chatType ~= "OFFICER"
      end
    end
  else
    streams = { [id] = true }
    form = (not s.lines[id]) and Decks.FORMS[id] or nil
  end
  if pane and pane.hidden and Decks.HIDES[id] then
    streams.junk = true
    local inner = fn
    fn = function(rec)
      if rec.stream == "junk" then
        return id == "all" or Decks.WORLDLY[rec.chatType] == true
      end
      return not inner or inner(rec)
    end
  end
  form = form or {}
  local now = time()
  local oldest = form.board and (now - ns.Rows.BOARD_AGE) or nil
  if since and (not oldest or since > oldest) then
    oldest = since
  end
  return {
    off = offOf(streams),
    maxTier = 5,
    query = both(ns.Find.Query(words), fn),
    board = form.board,
    byDungeon = form.byDungeon,
    since = oldest,
    plain = deck == "talk", -- Team: every line whole, nothing folded under a speaker
    reasons = pane ~= nil and pane.hidden == true, -- what the spam rules took says why
  }
end

local function fillFeed(pane, opts)
  pane.feed = ns.Rows.NewFeed(opts)
  pane.feed.filled = time()
  for _, rec in ipairs(store():Query()) do
    pane.feed:Add(rec)
  end
  if opts.byDungeon then
    ns.Rows.OrderBoard(pane.feed.items, Compat.PlayerLevel())
  end
  pane.list.gap = opts.board and ns.Rows.BOARD_GAP or 0
  pane.list.stuck = true
  pane.list:SetItems(pane.feed.items)
  pane.empty:SetShown(#pane.feed.items == 0)
end

local EMPTY = {
  all = "Loot, fights, Trade, groups, the world and addon prints show here.",
  mine = "Nothing yet: your loot, money and experience show here.",
  fight = "No fight yet. After each fight one line says how it went.",
  market = "No offer in the last five minutes.",
  lfg = "No group post in the last five minutes.",
  world = "Nothing from the world yet.",
  addons = "No addon print yet.",
  watched = "Your watch list found nothing yet.",
  group = "No line in the group yet.",
  guild = "No line in the guild yet.",
  officer = "No officer line yet.",
}

local function fillPerson(pane, key)
  local People = P()
  local c = People.Convo(key)
  local words, since = findFor("talk")
  local q = ns.Find.Query(words)
  local match
  if q or since then
    match = function(l)
      return (not since or (l.at or 0) >= since) and (not q or q:Match(ns.Find.LineRec(c, l)))
    end
  end
  local items = People.Items(c, mark and mark.key == key and mark or nil, time(), match)
  pane.feed = nil
  pane.list.gap = 0
  pane.list.stuck = true
  pane.list:SetItems(items)
  pane.empty:SetShown(#items == 0)
  pane.empty:SetText(
    match and L["No line matches"]
      or string.format(L["Start the conversation: say hi to %s."], Model.ShortName(c.name))
  )
  People.DrawPlates()
end

-- The group's history entries still kept (plan §5), the newest first.
function Decks.Rooms(now)
  local s = Decks.Settings()
  local kept = {}
  for _, room in ipairs(s.rooms) do
    if
      type(room) == "table"
      and (now - (room.to or 0)) <= Decks.ROOM_DAYS * 86400
      and #kept < Decks.ROOMS_MAX
    then
      kept[#kept + 1] = room
    end
  end
  s.rooms = kept
  return kept
end

-- "Party, 14.11., 21:10 to 22:40, 5 people".
function Decks.RoomText(room)
  local kind = room.kind == "raid" and L["Raid"] or L["Party"]
  local text = ("%s, %s, %s"):format(
    kind,
    date("%d.%m.", room.from),
    L["%s to %s"]:format(date("%H:%M", room.from), date("%H:%M", room.to or room.from))
  )
  if room.people then
    text = text .. ", " .. L["%d people"]:format(room.people)
  end
  return text
end

-- The people list's rows (plan §4): who waits, who is pinned, the others by the newest, and
-- while a filter is typed the strangers gone quiet for a week. The filter's words match a name or
-- a kept line; a row found by a line shows that line. Pure but for People and the time.
function Decks.PeopleItems(words, now)
  local People = P()
  local all = People.All()
  local q = ns.Find.Query(words)
  local drafts = ns.mod.db.char.drafts or {}
  local waiting, pinned, earlier, older = {}, {}, {}, {}
  local n = 0
  for _, key in ipairs(People.Order()) do
    local c = all[key]
    local rel = People.Rel(key)
    local waits = (c.unread or 0) > 0 or People.Waits(key)
    local stale = (rel == nil or rel == "stranger")
      and not waits
      and not c.pinned
      and (now - (c.last or 0)) > Decks.STALE_DAYS * 86400
    local item = { kind = "who", key = key, waits = waits, draft = drafts[key] }
    local keep = true
    if q then
      local short = string.lower(Model.ShortName(c.name or ""))
      keep = q:Match({ plain = short, who = { name = c.name }, stream = "direct" })
      if not keep then
        for i = #(c.lines or {}), 1, -1 do
          local l = c.lines[i]
          if q:Match(ns.Find.LineRec(c, l)) then
            item.preview = (l.out and (L["You"] .. ": ") or "") .. (Model.Strip(l.text) or "")
            keep = true
            break
          end
        end
      end
    elseif stale then
      keep = false
    end
    if keep then
      n = n + 1
      local list = (waits and waiting) or (c.pinned and pinned) or (stale and older) or earlier
      list[#list + 1] = item
    end
  end
  local items = {}
  local function section(label, list)
    if #list > 0 then
      items[#items + 1] = { kind = "section", label = label }
      for _, item in ipairs(list) do
        items[#items + 1] = item
      end
    end
  end
  section(L["Waiting for you"] .. "  " .. #waiting, waiting)
  section(L["Pinned"], pinned)
  section(L["Earlier"], earlier)
  section(L["Older"], older)
  local rooms = {}
  for _, room in ipairs(Decks.Rooms(now)) do
    local text = Decks.RoomText(room)
    if not q or q:Match({ plain = string.lower(text), stream = "group" }) then
      rooms[#rooms + 1] = { kind = "room", text = text }
    end
  end
  section(L["Groups you were in"], rooms)
  return items, n
end

local function fillPeople(pane)
  local words = pane.filter:GetText()
  words = words ~= "" and words or nil
  local items, n = Decks.PeopleItems(words, time())
  for _, item in ipairs(items) do
    item.sel = item.key ~= nil and item.key == sel
  end
  pane.feed = nil
  pane.list.gap = 0
  pane.list.stuck = false
  pane.list:SetItems(items)
  pane.list.bar.ScrollTo(0)
  pane.empty:SetShown(#items == 0)
  pane.empty:SetText(
    words and L["No conversation matches"]
      or L["No conversation yet: whisper someone, or right click the strip."]
  )
  pane.filter.count:SetText(words and tostring(n) or "")
  Decks.ShowPlates(false)
end

-- A deck's list again from the store or the conversations.
function Decks.Fill(deck)
  local pane = panes[deck]
  if not pane then
    return
  end
  local s = Decks.Settings()
  local id = s[deck]
  if deck == "talk" then
    local key = personKey(id)
    if key then
      fillPerson(pane, key)
      return
    elseif id == "people" then
      fillPeople(pane)
      return
    end
    Decks.ShowPlates(false)
  end
  fillFeed(pane, Decks.FeedOpts(deck, id))
  local words = findFor(deck)
  pane.empty:SetText(words and L["No line matches"] or L[EMPTY[id] or "Nothing here yet."])
end

-- ---------------------------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------------------------

function Decks.DrawStrips()
  if not box then
    return
  end
  local s = Decks.Settings()
  local know, talk = panes.know, panes.talk
  S.WithPalette(S.PaletteOf(know.strip), function()
    if s.folded and not s.out.know then
      for _, chip in ipairs(know.chips) do
        chip:Hide()
      end
      know.more:Hide()
      know.sums.text:SetText(Decks.SumsText())
    else
      layKnow(know, Decks.KnowChips(), stripWidth(know))
    end
  end)
  S.WithPalette(S.PaletteOf(talk.strip), function()
    layTalk(talk, Decks.TalkChips(time()), stripWidth(talk))
  end)
end

-- The heads over the lists: Loot's sums, Fight's count and button, a board's "Lines", the people's
-- filter. Returns whether a head's presence changed (the layout must follow).
function Decks.DrawHeads()
  if not box then
    return false
  end
  local s = Decks.Settings()
  local know, talk = panes.know, panes.talk
  local head = know.head
  local id = s.know
  local was = head:IsShown()
  local board = Decks.FORMS[id] ~= nil
  head.log:SetShown(id == "fight" and ns.Basics.HasLog())
  head.lines:SetShown(board)
  if id == "mine" then
    head.text:SetText(Decks.SumsText())
  elseif id == "fight" then
    local n = ns.Fights.Count()
    head.text:SetText(n == 1 and L["1 fight"] or L["%d fights"]:format(n))
    if head.log.SetOn then
      head.log:SetOn(ns.Basics.LogShown())
    end
  elseif board then
    head.text:SetText(s.lines[id] and L["Every post as a line"] or L["The posts of the last five minutes"])
    if head.lines.SetOn then
      head.lines:SetOn(s.lines[id] == true)
    end
  end
  head:SetShown(id == "mine" or id == "fight" or board)
  local talkWas = talk.head:IsShown()
  talk.filter:SetShown(s.talk == "people")
  talk.head.text:SetShown(false)
  talk.head:SetShown(s.talk == "people")
  return was ~= head:IsShown() or talkWas ~= talk.head:IsShown()
end

-- "N hidden" under All and World: what the spam rules took.
function Decks.DrawFoot(pane)
  if not pane or pane.id ~= "know" then
    return false
  end
  local id = Decks.Settings().know
  local n = 0
  if Decks.HIDES[id] then
    for _, rec in ipairs(store().lines.junk or {}) do
      if id == "all" or Decks.WORLDLY[rec.chatType] then
        n = n + 1
      end
    end
  end
  pane.foot:SetShown(n > 0)
  if n > 0 then
    pane.foot.text:SetText(
      (n == 1 and L["1 hidden"] or L["%d hidden"]:format(n)) .. (pane.hidden and ("  " .. L["(shown)"]) or "")
    )
  end
  if n > 0 then
    pane.foot:SetWidth((pane.foot.text:GetStringWidth() or 40) + 12)
  end
  return false -- the note lies over the list: the layout stays
end

function Decks.DrawBelow(pane, n)
  if n > 0 then
    pane.newer:SetLabel(n == 1 and L["1 new line"] or L["%d new lines"]:format(n))
    pane.newer:Show()
  else
    pane.newer:Hide()
  end
end

-- Everything again (a place switched, the window shown, the find line changed).
function Decks.Rebuild()
  if not box then
    return
  end
  if not shown() then
    dirty = true
    return
  end
  dirty = false
  ns.Asks.Adopt(box) -- the one request bar (the Inbox may have had it)
  local s = Decks.Settings()
  if not s.sized then
    -- once per profile: two decks need more room than the one stream had (the window of version
    -- 1 opened 260 high)
    s.sized = true
    local frame = win.win.frame
    if (frame:GetHeight() or 0) < Decks.FIRST_H then
      frame:SetHeight(Decks.FIRST_H)
      win.win:SavePlace()
    end
  end
  if s.folded == nil then
    -- a window at its smallest height starts with Know folded (plan §2)
    s.folded = (win.win.frame:GetHeight() or 0) <= Decks.MIN_H + 1
  end
  -- a place that is gone, or out in a window of its own, is not shown here
  local key = personKey(s.talk)
  if (key and not P().Convo(key)) or ns.Places.IsOut(s.talk) then
    s.talk = "people"
  end
  local name = savedName(s.know)
  if (name and not ns.Views.Find(name)) or ns.Places.IsOut(s.know) then
    s.know = "all"
  end
  if s.talk == "group" and not Compat.GroupSize() and groupUnread == 0 then
    local any = #store():Query({ streams = { group = true } }) > 0
    if not any then
      s.talk = "people"
    end
  end
  officerSeen = officerSeen or hasOfficer()
  hit[s.know], hit[s.talk] = nil, nil
  if s.talk == "group" then
    groupUnread = 0
  end
  S.WithPalette(S.PaletteOf(box), function()
    Decks.DrawHeads()
    Decks.DrawFoot(panes.know)
    ns.Asks.Draw()
    Decks.Layout()
    Decks.Fill("know")
    Decks.Fill("talk")
    Decks.Layout() -- the plates may have come or gone with the person shown
    Decks.DrawStrips()
    Decks.DrawFind()
    ns.Inbox.PaintPanels(box)
  end)
  badge()
end

-- ---------------------------------------------------------------------------------------------
-- The store's and the people's news
-- ---------------------------------------------------------------------------------------------

-- What a new line marks and counts, also while the window is hidden. Returns whether the strips
-- changed.
local function note(rec)
  if rec.own then
    return false
  end
  local s = Decks.Settings()
  local changed = false
  local visible = shown()
  local team = rec.stream == "group" or (rec.stream == "world" and rec.who and rec.who.grouped)
  if team and not (visible and s.talk == "group" and not s.out.talk) then
    local level = Decks.Level("group")
    if level == "all" or (level == "name" and rec.ask ~= nil) then
      groupUnread = groupUnread + 1
      changed = true
      badge()
    end
  end
  if rec.stream == "guild" and not guildSeen then
    guildSeen, changed = true, true -- a guild line: its chip, whatever the client says of the guild
  end
  if rec.chatType == "OFFICER" and not officerSeen then
    officerSeen, changed = true, true
  end
  if rec.stream == "guild" and rec.ask and Decks.Level("guild") ~= "none" then
    local place = rec.chatType == "OFFICER" and "officer" or "guild"
    if not (visible and s.talk == place) and not hit[place] then
      hit[place], changed = true, true
    end
  end
  if rec.watch then
    if not watchedSeen then
      watchedSeen, changed = true, true
    end
    if not (visible and s.know == "watched") and not hit.watched then
      hit.watched, changed = true, true
    end
  end
  for _, view in ipairs(ns.Views.List()) do
    local id = "s:" .. view.name
    if not hit[id] and not (visible and s.know == id) and ns.Views.Matches(view, rec) then
      hit[id], changed = true, true
    end
  end
  return changed
end

local function addTo(pane, rec)
  if not (pane.feed and pane.frame:IsVisible() and pane.feed:Shows(rec)) then
    return
  end
  if pane.feed.opts.board and time() - (pane.feed.filled or 0) >= Decks.BOARD_REFRESH then
    Decks.Fill(pane.id) -- the old posts leave, the ages are new
    return
  end
  local added, changed = pane.feed:Add(rec)
  if changed then
    pane.list:Invalidate(changed)
  end
  if added then
    pane.list:Append(added)
    pane.empty:Hide()
  end
end

function Decks.OnStore(what, value)
  if ns.View.LayoutKind() ~= "decks" then
    return
  end
  if what == "ask" then
    if box and shown() then
      ns.Asks.Draw()
      Decks.DrawStrips()
      if Decks.Settings().talk == "people" then
        Decks.Fill("talk") -- who waits moved
      end
    end
    return
  end
  if what ~= "add" then
    return
  end
  local officerWas = officerSeen
  local changed = note(value)
  if not box or not shown() then
    dirty = true
    return
  end
  addTo(panes.know, value)
  if officerSeen and not officerWas and Decks.Settings().talk == "guild" then
    Decks.Fill("talk") -- the first officer line: Guild's room is without them from now on
  else
    addTo(panes.talk, value)
  end
  local relaid = false
  if value.stream == "mine" or value.stream == "fight" then
    relaid = Decks.DrawHeads()
    changed = changed or Decks.Settings().folded == true
  end
  if value.stream == "junk" then
    relaid = Decks.DrawFoot(panes.know) or relaid
  end
  if relaid then
    Decks.Layout()
  end
  if changed then
    Decks.DrawStrips()
  end
end

-- A conversation changed (People.Changed): the strip, and the place if it shows them.
function Decks.OnPeople(key)
  if not box then
    return
  end
  if not shown() then
    dirty = true
    return
  end
  local s = Decks.Settings()
  local shownKey = personKey(s.talk)
  if shownKey and not P().Convo(shownKey) then
    s.talk = "people"
    Decks.Rebuild()
    return
  end
  if shownKey and (key == nil or key == shownKey) and not s.out.talk then
    local c = P().Convo(shownKey)
    if c and (c.unread or 0) > 0 then
      c.unread = 0 -- read where it shows
    end
    Decks.Fill("talk")
    Decks.Layout()
  elseif s.talk == "people" then
    Decks.Fill("talk")
  end
  Decks.DrawStrips()
  badge()
end

function Decks.Attach()
  if not attached then
    attached = true
    store():On(Decks.OnStore)
  end
end

-- ---------------------------------------------------------------------------------------------
-- Places
-- ---------------------------------------------------------------------------------------------

-- The half-typed whisper to the person shown, kept for them (plan §4; per character, so a
-- reload keeps it).
function Decks.KeepDraft()
  local key = Decks.ShownPerson()
  local c = key and P().Convo(key)
  if not c then
    return nil
  end
  local drafts = ns.mod.db.char.drafts
  for _, b in ipairs(Compat.EditBoxes()) do
    if b:IsShown() then
      local text = b:GetText() or ""
      local chatType, target = Compat.BarTarget(b)
      if
        text ~= ""
        and chatType == "WHISPER"
        and target
        and Model.ShortName(target):lower() == Model.ShortName(c.name):lower()
      then
        drafts[key] = text
        b:SetText("")
        return text
      end
    end
  end
  return nil
end

-- The command that sets the input line on a place of Talk or Team, nil for one that has none.
function Decks.TargetOf(id)
  local key = personKey(id)
  if key then
    local c = P().Convo(key)
    if c and not P().IsBNet(key) then
      return "/w " .. c.name .. " "
    end
    return nil
  elseif id == "guild" then
    return "/g "
  elseif id == "officer" then
    return "/o "
  elseif id == "group" then
    return Compat.InRaid() and "/ra " or "/p "
  end
  return nil
end

function Decks.SetTarget(slash)
  if slash then
    Decks.Settings().target = slash
    Decks.DrawTarget()
  end
end

-- "Party:", "To Ann:", "Say:": where Enter writes.
function Decks.TargetText()
  local target = Decks.Settings().target
  local cmd, rest = (target or "/s "):match("^/(%S+)%s*(.-)%s*$")
  if cmd == "w" and rest ~= "" then
    return L["To %s:"]:format(Model.ShortName(rest))
  elseif cmd and tonumber(cmd) then
    return L["Channel %s:"]:format(cmd)
  end
  return L[Decks.TARGET_WORDS[cmd or "s"] or "Say"] .. ":"
end

local function barOpen()
  for _, b in ipairs(Compat.EditBoxes()) do
    if b:IsShown() then
      return true
    end
  end
  return false
end

function Decks.DrawTarget()
  if not box then
    return
  end
  local t = box.target
  local on = ns.View.LayoutKind() == "decks" and not barOpen()
  t:SetShown(on)
  if on then
    t.text:SetText(Decks.TargetText())
  end
end

-- The player opened the game's bar (Enter): an empty bar takes the target (never in a fight,
-- never over a typed text). Returns the text it put in, or nil.
function Decks.OnBarOpen(bar)
  if box then
    box.target:Hide()
  end
  if not shown() or InCombatLockdown() then
    return nil
  end
  local s = Decks.Settings()
  if not s.target or not bar or (bar:GetText() or "") ~= "" then
    return nil
  end
  local key = Decks.ShownPerson()
  local drafts = ns.mod.db.char.drafts
  local draft = ""
  if key and s.target == Decks.TargetOf("p:" .. key) and drafts[key] then
    draft = drafts[key]
    drafts[key] = nil
  end
  bar:SetText(s.target .. draft)
  return s.target
end

-- The bar closed (sent, or Escape): what it was set on is the target from now on.
function Decks.OnBarClose(bar)
  if not box or ns.View.LayoutKind() ~= "decks" then
    return
  end
  local chatType, tell = Compat.BarTarget(bar)
  local s = Decks.Settings()
  if chatType == "WHISPER" and tell then
    s.target = "/w " .. tell .. " "
  elseif chatType and Decks.SLASH[chatType] then
    s.target = Decks.SLASH[chatType]
  elseif chatType == "CHANNEL" then
    local ok, ch = pcall(bar.GetAttribute, bar, "channelTarget")
    ch = ok and Compat.Plain(ch) or nil
    if ch ~= nil and tonumber(ch) then
      s.target = "/" .. tostring(ch) .. " "
    end
  end
  Decks.DrawTarget()
end

-- A place of a deck shown. `byClick`: the player chose it, so Talk's input line follows.
function Decks.Show(deck, id, byClick)
  local s = Decks.Settings()
  if deck == "talk" then
    Decks.KeepDraft()
    if id ~= s.talk then
      mark = nil
    end
  else
    panes.know.hidden = nil
    if s.folded then
      s.folded = false
    end
  end
  s[deck] = id
  hit[id] = nil
  if id == "group" then
    groupUnread = 0
  end
  if deck == "talk" and byClick then
    Decks.SetTarget(Decks.TargetOf(id))
  end
  Decks.Rebuild()
  badge()
end

function Decks.ShowMix()
  Decks.Show("know", "all")
end

-- A stream shown alone (the menus' "Show alone"): its chip, in its deck.
function Decks.Solo(id)
  if id == "group" or id == "guild" then
    Decks.Show("talk", id, true)
  elseif Decks.MIX[id] then
    Decks.Show("know", id)
  end
end

function Decks.ToggleInMix() end -- All is Know's mix, always whole

function Decks.ShowPeople()
  ns.View.ShowInbox()
  Decks.Show("talk", "people")
end

-- A person's place: their conversation, "N new" before what was unread, the input line on them
-- when the player asked for it.
function Decks.ShowPerson(key, byClick)
  local People = P()
  local c = People.Convo(key)
  if not c then
    return false
  end
  ns.View.ShowInbox()
  local s = Decks.Settings()
  if ns.Places.IsOut("p:" .. key) then
    return ns.Places.Detach("p:" .. key) -- their own window comes to the front
  end
  Decks.KeepDraft()
  if Decks.ShownPerson() ~= key then
    local n = c.unread or 0
    mark = { key = key, n = n, line = n > 0 and People.FirstNew(c, n) or nil }
  end
  s.talk = "p:" .. key
  c.unread = 0
  -- read: the chip says no count any more; the request stays until the answer
  local bn = People.IsBNet(key) and c.bnID or nil
  for _, a in ipairs(store().asks) do
    local same = (bn and a.bn == bn)
      or (not bn and a.who and Model.ShortName(a.who) == Model.ShortName(c.name))
    if a.kind == "whisper" and a.state == "open" and same and (a.unread or 0) > 0 then
      a.unread = 0
      store():Notify("ask", a)
    end
  end
  People.Changed(key)
  Decks.Rebuild()
  if byClick and not People.IsBNet(key) then
    local drafts = ns.mod.db.char.drafts
    local draft = drafts[key] or ""
    drafts[key] = nil
    Decks.SetTarget("/w " .. c.name .. " ")
    Compat.OpenChat("/w " .. c.name .. " " .. draft)
  end
  return true
end

-- A click on a chip: its place; "+N": the chips that did not fit.
function Decks.ChipClick(chip, button)
  local id, deck = chip.id, chip.deck
  if id == "more" then
    return Decks.MoreMenu(chip)
  end
  if button == "RightButton" then
    return Decks.ChipMenu(deck, id, chip)
  end
  if ns.Places.IsOut(id) then
    return ns.Places.Detach(id) -- its window comes to the front
  end
  local key = personKey(id)
  if key then
    return Decks.ShowPerson(key, true)
  elseif id == "people" then
    Decks.ShowPeople()
    panes.talk.filter:SetFocus() -- typing a name goes to the line (plan §4)
    return true
  end
  Decks.Show(deck, id, true)
  return true
end

function Decks.MoreMenu(anchor)
  local items = {}
  for _, spec in ipairs(panes.know.rest or {}) do
    items[#items + 1] = {
      label = spec.text .. (spec.mark and "  *" or ""),
      onClick = function()
        Decks.Show("know", spec.id)
      end,
    }
  end
  B.UI.Menu(anchor, L["More places"], items, ns.mod)
  return items
end

-- Know folded to one line of sums, or open again.
function Decks.Fold(on)
  Decks.Settings().folded = on and true or false
  Decks.Rebuild()
end

-- Know's share of the lists' height (the splitter).
function Decks.Split(frac)
  local s = Decks.Settings()
  s.split = math.max(Decks.SPLIT_MIN, math.min(Decks.SPLIT_MAX, tonumber(frac) or Decks.SPLIT))
  if shown() then
    Decks.Layout()
  end
  return s.split
end

-- Places' windows changed (one left the window, one came back): a deck never shows a place
-- that stands in a window of its own.
function Decks.DrawRail()
  if box and shown() then
    Decks.Rebuild()
  end
end

function Decks.Detach(id)
  return ns.Places.Detach(id)
end

-- ---------------------------------------------------------------------------------------------
-- The plates (the proposed answers) and the request bar's rows
-- ---------------------------------------------------------------------------------------------

function Decks.PlatesFrame()
  return box and box.plates or nil
end

function Decks.ShowPlates(on)
  if not box then
    return
  end
  on = on and Decks.ShownPerson() ~= nil
  if box.plates:IsShown() ~= (on and true or false) then
    box.plates:SetShown(on)
    Decks.Layout()
  end
end

-- ---------------------------------------------------------------------------------------------
-- The people list's keys
-- ---------------------------------------------------------------------------------------------

local function whoKeys()
  local keys = {}
  for _, item in ipairs(panes.talk.list.items or {}) do
    if item.kind == "who" then
      keys[#keys + 1] = item.key
    end
  end
  return keys
end

-- Down and Up in the filter line walk the rows.
function Decks.WalkPeople(dir)
  local keys = whoKeys()
  if #keys == 0 then
    sel = nil
    return nil
  end
  local at = 0
  for i, key in ipairs(keys) do
    if key == sel then
      at = i
    end
  end
  at = math.max(1, math.min(#keys, at + dir))
  sel = keys[at]
  for _, item in ipairs(panes.talk.list.items) do
    local on = item.key ~= nil and item.key == sel
    if item.sel ~= on then
      item.sel = on
      panes.talk.list:Invalidate(item)
    end
  end
  return sel
end

-- Enter in the filter line: the row walked to, else the first.
function Decks.OpenWalked()
  local keys = whoKeys()
  local key = sel or keys[1]
  sel = nil
  if not key then
    return false
  end
  return Decks.ShowPerson(key, true)
end

-- ---------------------------------------------------------------------------------------------
-- Find (plan §8)
-- ---------------------------------------------------------------------------------------------

function Decks.Query()
  return find.frame and find.frame:IsShown() and find.words or nil
end

function Decks.DrawFind()
  local f = find.frame
  if not f then
    return
  end
  for _, pair in ipairs(Decks.WHERE) do
    if pair[1] == find.where then
      f.where:SetLabel(L[pair[2]])
    end
  end
  for _, pair in ipairs(Decks.WHEN) do
    if pair[1] == find.when then
      f.when:SetLabel(L[pair[2]])
    end
  end
end

function Decks.OpenFind(text)
  if not box then
    return
  end
  find.frame:Show()
  if text then
    find.applying = true
    find.frame.box:SetText(text)
    find.applying = false
    find.words = text ~= "" and text or nil
  end
  Decks.Rebuild()
  find.frame.box:SetFocus()
end

function Decks.CloseFind()
  if not box then
    return
  end
  find.applying = true
  find.frame.box:SetText("")
  find.applying = false
  find.frame.box:ClearFocus()
  find.words = nil
  find.frame:Hide()
  Decks.Rebuild()
end

function Decks.ToggleFind()
  if find.frame:IsShown() then
    Decks.CloseFind()
  else
    Decks.OpenFind()
  end
end

-- The menus' "Show only ...": the find line holds the words.
function Decks.SetFilter(text)
  if text and text ~= "" then
    Decks.OpenFind(text)
  else
    Decks.CloseFind()
  end
end

-- "Who": a person's name as a word of the find line.
function Decks.WhoMenu(anchor)
  local items = {}
  local all = P().All()
  for i, key in ipairs(P().Order()) do
    if i > 15 then
      break
    end
    local name = Model.ShortName(all[key].name)
    items[#items + 1] = {
      label = name,
      onClick = function()
        local text = find.frame.box:GetText() or ""
        find.frame.box:SetText((text ~= "" and (text .. " ") or "") .. name)
      end,
    }
  end
  B.UI.Menu(anchor, L["Who"], items, ns.mod)
  return items
end

-- The find line's words kept as a watch: a chip in Know that marks its hits (plan §6).
function Decks.KeepWatch()
  local words = find.words
  if not words then
    return false
  end
  local view = ns.Views.Keep({ query = words })
  if not view then
    B:Say(L["The watch list is full."])
    return false
  end
  Decks.CloseFind()
  Decks.Show("know", "s:" .. view.name)
  return view
end

-- The lines shown, to select and copy: the copy box (the game gives addons no clipboard).
function Decks.SelectText()
  ns.View.Copy(ns.Menus.ShownText())
end

-- ---------------------------------------------------------------------------------------------
-- Menus
-- ---------------------------------------------------------------------------------------------

local function levelEntries(items, place)
  items[#items + 1] = { label = L["How loud"], header = true }
  local current = Decks.Level(place)
  for _, pair in ipairs(Decks.LEVELS) do
    items[#items + 1] = {
      label = L[pair[2]],
      on = current == pair[1],
      onClick = function()
        Decks.SetLevel(place, pair[1])
      end,
    }
  end
end

local function ownWindow(items, id)
  if ns.Places.Valid(id) then
    items[#items + 1] = {
      label = L["Window of its own"],
      onClick = function()
        ns.Places.Detach(id)
      end,
    }
  end
end

-- A chip's menu: its level, a window of its own, its lines to copy, and what its kind adds.
function Decks.ChipMenu(deck, id, anchor)
  local key = personKey(id)
  if key then
    return P().Menu(key, anchor)
  end
  local items = {}
  local title
  local name = savedName(id)
  if id == "people" then
    title = L["People"]
    items[#items + 1] = {
      label = L["New whisper"],
      onClick = function()
        P().NewMenu(anchor)
      end,
    }
    items[#items + 1] = {
      label = L["Mark every conversation read"],
      onClick = function()
        P().MarkAllRead()
      end,
    }
  elseif name then
    title = name
    local view = ns.Views.Find(name)
    local rings = view and view.sound and view.sound ~= "none"
    items[#items + 1] = {
      label = L["Ring on a hit"],
      on = rings and true or false,
      onClick = function()
        if view then
          view.sound = (not rings) and "chime" or nil
        end
      end,
    }
    items[#items + 1] = {
      label = L["Change the words"],
      onClick = function()
        ns.Views.Delete(name)
        Decks.OpenFind(view and view.query or "")
      end,
    }
    ownWindow(items, id)
    items[#items + 1] = {
      label = L["Delete this watch"],
      onClick = function()
        ns.Places.Dock(id)
        ns.Views.Delete(name)
        Decks.Rebuild()
      end,
    }
  elseif id == "all" or id == "watched" then
    title = id == "all" and L["All"] or L["Watched"]
    items[#items + 1] = {
      label = L["Copy all lines shown"],
      onClick = function()
        ns.View.Copy(ns.Menus.ShownText())
      end,
    }
  else
    local stream = id == "officer" and "guild" or id
    title = (deck == "talk" and id == "group") and groupName() or nil
    for _, pair in ipairs(Decks.KNOW) do
      if pair[1] == id then
        title = L[pair[2]]
      end
    end
    title = title or L[Decks.TALK_NAMES[id] or id]
    levelEntries(items, id)
    items[#items + 1] = { label = title, header = true }
    ownWindow(items, id)
    items[#items + 1] = {
      label = L["Copy all lines"],
      onClick = function()
        ns.View.Copy(ns.Menus.StreamText(stream))
      end,
    }
    if id ~= "officer" then
      items[#items + 1] = {
        label = L["Clear"],
        onClick = function()
          store():Clear(stream)
          Decks.Rebuild()
        end,
      }
    end
  end
  B.UI.Menu(anchor, title, items, ns.mod)
  return items
end

-- A strip's menu: the deck's own entries, then what the game's chat offered (plan §7).
function Decks.StripMenu(deck, anchor)
  local s = Decks.Settings()
  local items = {}
  if deck == "know" then
    items[#items + 1] = {
      label = s.folded and L["Unfold Know"] or L["Fold Know to one line"],
      onClick = function()
        Decks.Fold(not s.folded)
      end,
    }
    items[#items + 1] = {
      label = L["Watch words ..."],
      onClick = function()
        Decks.OpenFind()
      end,
    }
    items[#items + 1] = { label = L["The decks"], header = true }
    for _, pair in ipairs(Decks.SIDES) do
      items[#items + 1] = {
        label = L[pair[2]],
        on = (s.side or "stacked") == pair[1],
        onClick = function()
          s.side = pair[1]
          Decks.Rebuild()
        end,
      }
    end
  else
    items[#items + 1] = {
      label = L["New whisper"],
      onClick = function()
        P().NewMenu(anchor)
      end,
    }
    items[#items + 1] = {
      label = L["Mark every conversation read"],
      onClick = function()
        P().MarkAllRead()
      end,
    }
  end
  items[#items + 1] = {
    label = s.out[deck] and L["Dock this deck"] or L["Deck as a window of its own"],
    onClick = function()
      if s.out[deck] then
        Decks.DeckDock(deck)
      else
        Decks.DeckOut(deck)
      end
    end,
  }
  ns.Basics.Entries(items, anchor)
  B.UI.Menu(anchor, deck == "know" and L["Know"] or L["Talk and Team"], items, ns.mod)
  return items
end

-- The input label's menu: the targets, then the game's chat entries.
function Decks.TargetMenu(anchor)
  local items = { { label = L["Enter writes to"], header = true } }
  local s = Decks.Settings()
  local list = { { "/s ", "Say" }, { "/y ", "Yell" } }
  if Compat.GroupSize() then
    list[#list + 1] = Compat.InRaid() and { "/ra ", "Raid" } or { "/p ", "Party" }
  end
  if Compat.GuildName() then
    list[#list + 1] = { "/g ", "Guild" }
  end
  for _, pair in ipairs(list) do
    items[#items + 1] = {
      label = L[pair[2]],
      on = (s.target or "/s ") == pair[1],
      onClick = function()
        Decks.SetTarget(pair[1])
      end,
    }
  end
  ns.Basics.Entries(items, anchor)
  B.UI.Menu(anchor, L["Input line"], items, ns.mod)
  return items
end

-- ---------------------------------------------------------------------------------------------
-- A deck in a window of its own (plan §9)
-- ---------------------------------------------------------------------------------------------

function Decks.DeckWindow(deck)
  if deckWins[deck] then
    return deckWins[deck]
  end
  local s = Decks.Settings()
  s.windows[deck] = type(s.windows[deck]) == "table" and s.windows[deck] or {}
  local W = B.UI.Window("BastiansChatDeck_" .. deck, {
    module = "Chat",
    title = deck == "know" and L["Know"] or L["Talk and Team"],
    width = 420,
    height = 240,
    minWidth = 300,
    minHeight = 120,
    lockable = true,
    headIcons = true,
    db = s.windows[deck],
    escape = false,
    strata = "LOW",
    onResize = function()
      if Decks.Settings().out[deck] and shown() then
        Decks.Layout()
        Decks.DrawStrips()
      end
    end,
  })
  W.close:SetScript("OnClick", function()
    Decks.DeckDock(deck)
  end)
  W.close.tip = L["Back into the chat window"]
  local function dock()
    if win.win.frame:IsShown() and win.win.frame:IsMouseOver() then
      Decks.DeckDock(deck)
    end
  end
  W.head:HookScript("OnDragStop", dock)
  W.head:HookScript("OnMouseUp", function(self, button)
    if button == "RightButton" then
      Decks.StripMenu(deck, self)
    end
  end)
  ns.View.Dress(W)
  deckWins[deck] = W
  return W
end

function Decks.DeckOut(deck)
  if not box or not panes[deck] then
    return false
  end
  local s = Decks.Settings()
  s.out[deck] = true
  if deck == "know" then
    s.folded = false
  end
  Decks.DeckWindow(deck):Show()
  Decks.Rebuild()
  return true
end

function Decks.DeckDock(deck)
  local s = Decks.Settings()
  if not s.out[deck] then
    return false
  end
  s.out[deck] = nil
  local W = deckWins[deck]
  if W then
    W.title:Show()
    W:Hide()
  end
  if box then
    Decks.Rebuild()
  end
  return true
end

-- The decks' own windows shown with the chat window, hidden with it.
function Decks.ShowWindows(on)
  local s = Decks.Settings()
  for _, deck in ipairs({ "know", "talk" }) do
    if on and s.out[deck] and box then
      Decks.DeckWindow(deck):Show()
    elseif deckWins[deck] then
      deckWins[deck]:Hide()
    end
  end
end

-- ---------------------------------------------------------------------------------------------
-- The group's life (plan §5): a finished group becomes an entry of the people list
-- ---------------------------------------------------------------------------------------------

function Decks.OnGroup(now)
  local s = Decks.Settings()
  now = now or time()
  local n = Compat.GroupSize()
  if n then
    local room = type(s.room) == "table" and s.room or { from = now, people = n }
    room.kind = Compat.InRaid() and "raid" or "party"
    room.people = math.max(room.people or 0, n)
    s.room = room
  elseif type(s.room) == "table" then
    local room = s.room
    s.room = nil
    room.to = now
    table.insert(s.rooms, 1, room)
    Decks.Rooms(now)
  end
  if box and shown() then
    Decks.DrawStrips()
    if s.talk == "people" then
      Decks.Fill("talk")
    end
  end
end

-- ---------------------------------------------------------------------------------------------
-- The people list's rows
-- ---------------------------------------------------------------------------------------------

local function makeWho(parent)
  local f = CreateFrame("Button", nil, parent)
  f.hl = S.fill(f, S.C.hover, "HIGHLIGHT")
  f.selFill = S.fill(f, S.C.accent, "BACKGROUND")
  f.name = S.text(f, 12, S.C.text)
  f.name:SetPoint("LEFT", f, "LEFT", 6, 0)
  f.name:SetWordWrap(false)
  f.name:SetJustifyH("LEFT")
  f.count = S.SetRole(S.text(f, 10, S.C.tier0), "number")
  f.count:SetPoint("RIGHT", f, "RIGHT", -6, 0)
  f.count:SetJustifyH("RIGHT")
  f.count:SetWidth(18)
  f.when = S.SetRole(S.text(f, 10, S.C.dim), "number")
  f.when:SetPoint("RIGHT", f.count, "LEFT", -4, 0)
  f.rel = S.SetRole(S.text(f, 9, S.C.dim), "number")
  f.rel:SetPoint("LEFT", f.name, "RIGHT", 6, 0)
  f.last = S.text(f, 12, S.C.dim)
  f.last:SetPoint("LEFT", f.rel, "RIGHT", 8, 0)
  f.last:SetPoint("RIGHT", f.when, "LEFT", -8, 0)
  f.last:SetWordWrap(false)
  f.last:SetJustifyH("LEFT")
  f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  f:SetScript("OnClick", function(self, button)
    if not self.key then
      return
    end
    if button == "RightButton" then
      P().Menu(self.key, self)
    else
      Decks.ShowPerson(self.key, true)
    end
  end)
  return f
end

local function whoWhen(t)
  if not t then
    return ""
  end
  if date("%d.%m.%Y", t) == date("%d.%m.%Y", time()) then
    return date("%H:%M", t)
  end
  return date("%d.%m.", t)
end

local function layWho(f, item)
  local People = P()
  local c = People.Convo(item.key)
  f.key = item.key
  if not c then
    return 0
  end
  f.name:SetWidth(0)
  f.name:SetText(Model.ShortName(c.name))
  if (f.name:GetStringWidth() or 0) > 120 then
    f.name:SetWidth(120)
  end
  local rel = People.Rel(item.key)
  f.rel:SetText(rel and string.upper(L[People.REL_WORDS[rel] or "Stranger"]) or "")
  local last = c.lines[#c.lines]
  local text
  if item.preview then
    text = item.preview
  elseif item.draft then
    text = L["Draft: %s"]:format(item.draft)
  elseif last then
    text = (last.out and (L["You"] .. ": ") or "") .. (Model.Strip(last.text) or "")
  else
    text = L["No line yet"]
  end
  f.last:SetText(text)
  S.ink(f.last, S.Tok(f, (item.waits or item.preview) and "text" or "dim"))
  f.when:SetText(last and whoWhen(c.last) or "")
  local n = c.unread or 0
  f.count:SetText(n > 0 and tostring(n) or "")
  S.tint(f.selFill, S.Tok(f, "accent"), item.sel and 0.16 or 0)
  return Decks.WHO_H
end

local function makeRoom(parent)
  local f = CreateFrame("Frame", nil, parent)
  f.text = S.text(f, 12, S.C.dim)
  f.text:SetPoint("LEFT", f, "LEFT", 6, 0)
  f.text:SetWordWrap(false)
  return f
end

ns.Rows.KINDS.who = {
  make = makeWho,
  fill = function(f, item)
    return layWho(f, item)
  end,
}
ns.Rows.KINDS.room = {
  make = makeRoom,
  fill = function(f, item)
    f.text:SetText(item.text or "")
    return Decks.WHO_H
  end,
}
