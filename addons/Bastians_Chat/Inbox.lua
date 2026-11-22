-- Bastian's Chat, the one window (plan-chat-one-window.md §1, ADR 0076; layout B of ADR 0075): a
-- rail of places on the left (All, the mix; People, one per whisper partner; the streams, each
-- alone with every line of it, Ctrl+click for more than one; Saved, the player's saved searches;
-- "Down to", the tier the mix goes down to), the filter line over the place shown (plain words
-- over the whole entry, the hits per place on the rail, suggestions, a star that saves), the
-- place in the stream under it, each in its form (All, World, Addons and Junk as lines with the
-- player's gains folded into ledger rows and reposts shown once; Market as offer cards, Groups as a
-- card per dungeon, Guild and Group as speaker blocks, Mine under the session's ledger; a person as
-- their conversation; People as every conversation in one list), the proposed answers and the
-- bar of the open requests over the input line, and a timeline strip at the right with a tick per
-- line in its tier's colour. The game's input bar stays in the window's bottom line and follows the
-- place shown.
local _, ns = ...
local B = Bastians
local S = B.UI.Style
local L = ns.L
local Model, Compat = ns.Model, ns.Compat

local Inbox = {}
ns.Inbox = Inbox

Inbox.RAIL_W = 160
Inbox.MIN_W = 440 -- the one window at least: the rail, the filter line, a stream to read (V34)
Inbox.MIN_H = 280
Inbox.PAD = 8 -- inside a panel
Inbox.FACET_H = 22
Inbox.SECTION_H = 20
Inbox.FILTER_H = 26 -- the filter line over the stream (plan §2.1)
Inbox.SUGGEST_H = 20 -- a suggestion's row
Inbox.HEAD_H = 44 -- a person's head over their conversation
Inbox.ASKS_H = 26 -- the request bar while something is open (plan §3.3)
Inbox.PLATES_H = 24 -- the proposed answers over the input line
Inbox.SAVED_MAX = 5 -- saved searches on the rail, then "N more"
-- what a suggestion is, at its row's left
Inbox.SUGGEST_KINDS = { person = "Person", place = "Place", item = "Item", dungeon = "Dungeon" }
-- the colour of a stream's dot on the rail: the tier its lines usually have (the artifact's facets)
Inbox.STREAM_TIER = {
  direct = 0,
  group = 1,
  guild = 1,
  mine = 2,
  market = 3,
  lfg = 3,
  world = 4,
  addons = 4,
  junk = 5,
  fight = 2,
}
Inbox.TIMELINE_W = 8
Inbox.TICKS = 240 -- the newest lines on the timeline
Inbox.FOOT_H = 16
Inbox.GAP = 6
Inbox.MAX = 1000 -- rows the stream keeps (the store keeps more)
Inbox.TIMELINE_DELAY = 0.5 -- seconds: the timeline is drawn again at most this often
Inbox.BOARD_REFRESH = 30 -- a board is filled again (ages, counts) this often while lines come
-- each stream shown alone in its form (plan §1.2, V31; the Switchboard's columns until then): the
-- boards of V14 and V18, the speaker blocks of V15, the ledger of V16 at Mine's head
Inbox.FORMS = {
  market = { board = true },
  lfg = { board = true, byDungeon = true },
  group = { blocks = true },
  guild = { blocks = true },
  mine = { ledger = true },
}
-- the rail's streams, in the order of the ladder (plan §2.1); the whispers are People (V30)
Inbox.STREAMS = {
  { "group", "Group" },
  { "guild", "Guild" },
  { "mine", "Mine" },
  { "market", "Market" },
  { "lfg", "Groups" },
  { "world", "World" },
  { "addons", "Addons" },
  { "junk", "Junk" },
}
Inbox.TIER_WORDS = {
  [0] = "Only what needs you",
  "And your people",
  "And what is yours",
  "And Trade and groups",
  "And everything around",
  "Everything, junk too",
}

local box -- the Inbox's frame in the main window
local feed -- Rows' feed of what the stream shows
local dirty = true -- the store changed while the Inbox was hidden
local timelinePending = false
local applying = false -- the window writes the filter line itself (a saved search, a place)
local mark -- the conversation shown: { key, line, n }: "N new" stands before `line`
local drafts = {} -- [person] = a half-typed line to them (plan §3.1)
local hits -- the hits per place of the filter in force (Find.Counts), nil without one

local function store()
  return ns.Chat.Store()
end

local function People()
  return ns.People
end

local function copy(t)
  if type(t) ~= "table" then
    return nil
  end
  local out = {}
  for k, v in pairs(t) do
    out[k] = v
  end
  return out
end

function Inbox.Settings()
  local p = ns.mod.db.profile
  p.inbox = p.inbox or {}
  local s = p.inbox
  if type(s.off) ~= "table" then
    s.off = { junk = true }
  end
  if type(s.maxTier) ~= "number" then
    s.maxTier = 3
  end
  if s.only ~= nil and (not Inbox.STREAM_TIER[s.only] or s.only == "direct") then
    s.only = nil -- the stream shown alone (V27): a name no stream of the rail has any more
  end
  if type(s.also) ~= "table" or not s.only then
    s.also = nil -- the streams Ctrl+click added to the one shown (V29)
  end
  s.recent = type(s.recent) == "table" and s.recent or {}
  -- once: a view shown (V8) is a saved search shown (V29)
  if s.view ~= nil then
    s.saved, s.view, s.before = s.view, nil, nil
  end
  if s.saved ~= nil and not ns.Views.Find(s.saved) then
    s.saved, s.savedStreams = nil, nil
  end
  return s
end

-- The place shown: "all", "stream" (and its id), "person" (and its key), "people", "saved" (and
-- its name).
function Inbox.Place()
  local s = Inbox.Settings()
  if s.person and People().Convo(s.person) then
    return "person", s.person
  elseif s.people then
    return "people"
  elseif s.saved then
    return "saved", s.saved
  elseif s.only then
    return "stream", s.only
  end
  return "all"
end

-- What the stream shows: the streams shown alone (one, or more by Ctrl+click) with every line of
-- them (V27), a saved search's streams, else the mix, its streams down to "Down to". Returns the
-- streams left out and the lowest tier shown.
function Inbox.Shown(s)
  s = s or Inbox.Settings()
  local only = s.saved and s.savedStreams
  if not only and s.only then
    only = copy(s.also) or {}
    only[s.only] = true
  end
  if only and next(only) then
    local off = {}
    for _, id in ipairs(ns.Store.STREAMS) do
      if not only[id] then
        off[id] = true
      end
    end
    return off, 5
  end
  return s.off, s.maxTier
end

-- The form of what shows (plan §1.2): a stream shown alone, or streams that share their form
-- (Guild and Group are both speaker blocks); nil for lines.
function Inbox.Form(s)
  s = s or Inbox.Settings()
  local kind = Inbox.Place()
  if kind ~= "stream" and kind ~= "saved" then
    return nil
  end
  local only = kind == "saved" and s.savedStreams or nil
  if kind == "stream" then
    only = copy(s.also) or {}
    only[s.only] = true
  end
  local form
  for id in pairs(only or {}) do
    local f = Inbox.FORMS[id]
    if not f or (form and form ~= f and not (form.blocks and f.blocks)) then
      return nil
    end
    form = f
  end
  return form
end

-- The filter's words in force (the menus' "Leave out").
function Inbox.Query()
  return Inbox.Settings().query
end

function Inbox.Frame()
  return box
end

function Inbox.Feed()
  return feed
end

function Inbox.ShownPerson()
  local kind, key = Inbox.Place()
  return kind == "person" and key or nil
end

function Inbox.ShowsPerson(key)
  return box ~= nil and key ~= nil and Inbox.ShownPerson() == key
end

-- ---------------------------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------------------------

-- A panel of the artifact: the plate's ground and a 1 px edge, rounded. `role` "stream" is the
-- place's lines, which the WoW look draws on the game's chat ground (Inbox.PaintPanels).
local panels = setmetatable({}, { __mode = "k" })
function Inbox.Panel(f, role)
  f.ground = S.roundFill(f, S.C.panel, "radius")
  f.edges = S.roundEdges(f, S.C.line, "radius")
  panels[f] = role or "panel"
  return f
end

-- The panels in the window's look (plan §8, R14): each its plate and its line.
function Inbox.PaintPanels(of)
  of = of or box -- the decks paint theirs by their own frame
  if not of then
    return
  end
  -- ~~the WoW look's black stream in a gold-edged inset~~ (until 20.11.2026, ADR 0084: one look)
  for f in pairs(panels) do
    S.tint(f.ground, S.Tok(f, "panel"), 1)
    S.setEdges(f.edges, S.Tok(f, "line"), 1)
  end
end

-- A row of the rail (the artifact's facet): a dot in its colour (or a face), its name, its
-- count. The row shown is marked with the accent's wash and a bar at its left edge.
local function facet(parent, id, label, dot, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(Inbox.FACET_H)
  b.stream = id
  b.sel = S.fill(b, S.C.accent, "BACKGROUND")
  b.bar = S.fill(b, S.C.accent, "BORDER")
  b.bar:ClearAllPoints()
  b.bar:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  b.bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
  b.bar:SetWidth(2)
  b.hl = S.fill(b, S.C.hover, "HIGHLIGHT")
  if dot then
    b.dot = CreateFrame("Frame", nil, b)
    b.dot:SetSize(8, 8)
    b.dot:SetPoint("LEFT", b, "LEFT", 6, 0)
    b.dot.fill = S.roundFill(b.dot, dot, "pill")
  else
    b.face = ns.People.NewFace(b, 16) -- a person (V30)
    b.face:SetPoint("LEFT", b, "LEFT", 4, 0)
    b.dot = b.face
  end
  b.count = S.SetRole(S.text(b, 11, S.C.muted), "number")
  b.count:SetPoint("RIGHT", b, "RIGHT", -6, 0)
  b.count:SetJustifyH("RIGHT")
  -- in a window of its own (V32): the place's row dimmed with the "open" pictogram
  b.outIcon = b:CreateTexture(nil, "ARTWORK")
  b.outIcon:SetSize(10, 10)
  b.outIcon:SetPoint("RIGHT", b, "RIGHT", -6, 0)
  b.outIcon:SetTexture(B.UI.Pictogram("open"))
  b.outIcon:Hide()
  b.label = S.text(b, 12, S.C.text)
  b.label:SetPoint("LEFT", b.dot, "RIGHT", 7, 0)
  b.label:SetPoint("RIGHT", b.count, "LEFT", -4, 0)
  b.label:SetJustifyH("LEFT")
  b.label:SetWordWrap(false) -- one line, cut with "..." (plan §8)
  b.label:SetText(label)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", S.TipEnter)
  b:SetScript("OnLeave", S.TipLeave)
  function b.SetOn(self, on)
    self.on = on and true or false
    S.ink(self.label, on and S.C.text or S.C.dim)
    self.dot:SetAlpha(on and 1 or 0.3)
  end
  -- out in its own window: dim, the pictogram instead of the count
  function b.SetOut(self, out)
    self.out = out and true or false
    S.tint(self.outIcon, S.Tok(self, "dim"), 1)
    self.outIcon:SetShown(self.out)
    self.count:SetShown(not self.out)
    if self.out then
      S.ink(self.label, S.Tok(self, "dim"))
    end
  end
  function b.SetSelected(self, on)
    self.selected = on and true or false
    S.tint(self.sel, S.Tok(self, "accent"), on and 0.16 or 0)
    S.showPart(self.bar, on)
    S.tint(self.bar, S.Tok(self, "accent"), 1)
  end
  -- the count of its lines, or while a filter is typed its hits (a dim 0 where none, plan §2.3)
  function b.SetCount(self, n, hit)
    self.count:SetText(n and tostring(n) or "")
    S.ink(self.count, (hit and n == 0) and S.C.dim or S.C.muted)
    self.count:SetAlpha((hit and n == 0) and 0.6 or 1)
  end
  b:SetSelected(false)
  return b
end

-- A section's head on the rail: "PEOPLE 3 [+]", "STREAMS", "SAVED".
local function section(parent, label)
  local f = CreateFrame("Button", nil, parent)
  f:SetHeight(Inbox.SECTION_H)
  f.sel = S.fill(f, S.C.accent, "BACKGROUND")
  S.tint(f.sel, S.C.accent, 0)
  f.text = S.SetRole(S.text(f, 11, S.C.muted), "label")
  f.text:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 3)
  f.text:SetText(string.upper(label))
  f.count = S.SetRole(S.text(f, 10, S.C.dim), "number")
  f.count:SetPoint("LEFT", f.text, "RIGHT", 6, 0)
  f:SetScript("OnEnter", S.TipEnter)
  f:SetScript("OnLeave", S.TipLeave)
  return f
end

local function buildRail()
  local rail = CreateFrame("Frame", nil, box)
  rail:SetPoint("TOPLEFT", box, "TOPLEFT", 2, -2)
  rail:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 2, 2)
  rail:SetWidth(Inbox.RAIL_W)
  Inbox.Panel(rail)
  local s = Inbox.Settings()
  -- "All": the mix (every stream not left out, down to "Down to")
  rail.all = facet(rail, "all", L["All"], S.C.accent, function(self, button)
    if button == "RightButton" then
      Inbox.AllMenu(self)
    else
      Inbox.ShowMix()
    end
  end)
  rail.all.tip = L["All the streams not left out, down to the slider below."]
  rail.all:SetPoint("TOPLEFT", rail, "TOPLEFT", 2, -Inbox.PAD)
  rail.all:SetPoint("RIGHT", rail, "RIGHT", -2, 0)
  rail.all:SetCount(0)
  -- People (plan §3.1, V30): the head with "+", five people, "N more"
  rail.peopleHead = section(rail, L["People"])
  rail.peopleHead.tip = L["Every conversation, one list: click. A new whisper: +"]
  rail.peopleHead:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  rail.peopleHead:SetScript("OnClick", function()
    Inbox.ShowPeople()
  end)
  rail.newPerson = S.action(rail.peopleHead, {
    icon = "plus",
    label = L["New conversation: a name, or a friend online"],
    only = true,
    row = true,
    onClick = function(self)
      ns.People.NewMenu(self)
    end,
  })
  rail.newPerson:SetPoint("RIGHT", rail.peopleHead, "RIGHT", -4, 0)
  rail.people = {}
  for i = 1, ns.People.RAIL_MAX do
    local row = facet(rail, nil, "", nil, function(self, button)
      if not self.key then
        return
      end
      if button == "RightButton" then
        ns.People.Menu(self.key, self)
      elseif ns.Places.IsOut("p:" .. self.key) then
        ns.Places.Detach("p:" .. self.key) -- out in its window (V32)
      else
        Inbox.ShowPerson(self.key, true)
      end
    end)
    row.wait = CreateFrame("Frame", nil, row) -- waits for an answer: a ring in the colour of needs you
    row.wait:SetSize(8, 8)
    row.wait:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.wait.edges = S.roundEdges(row.wait, S.C.tier0, "pill")
    row.wait:Hide()
    row:Hide()
    ns.Places.Draggable(row, function(self)
      return self.key and ("p:" .. self.key) or nil
    end)
    rail.people[i] = row
  end
  rail.more = facet(rail, "more", "", S.C.dim, function(self)
    Inbox.MoreMenu(self)
  end)
  rail.more.dot:SetAlpha(0)
  rail.more:Hide()
  rail.streamsHead = section(rail, L["Streams"])
  rail.pills = {}
  for _, pair in ipairs(Inbox.STREAMS) do
    local id = pair[1]
    local row = facet(rail, id, L[pair[2]], S.C["tier" .. (Inbox.STREAM_TIER[id] or 4)], function(_, button)
      if button == "RightButton" then
        ns.Menus.Place(id, rail.pills[id]) -- alone, in or out of All, notify, sound, copy (V33)
      elseif ns.Places.IsOut(id) then
        ns.Places.Detach(id) -- out in its window (V32): the window to the front
      else
        Inbox.Solo(id, IsControlKeyDown())
      end
    end)
    row.tip =
      L["Click: this stream alone, every line; again: All. Ctrl+click: add it to what shows. Right click: its menu."] -- luacheck: ignore 631 (a locale key stays one literal)
    row:SetOn(not s.off[id])
    row:SetCount(0)
    ns.Places.Draggable(row, function()
      return id
    end)
    rail.pills[id] = row
  end
  -- Saved (plan §2.4, V29): the player's saved searches, named by their words
  rail.savedHead = section(rail, L["Saved"])
  rail.savedHead.tip = L["Your saved searches: the star on the filter line saves what shows."]
  rail.saved = {}
  for i = 1, Inbox.SAVED_MAX do
    local row = facet(rail, nil, "", S.C.tier3, function(self, button)
      if not self.saved then
        return
      end
      if button == "RightButton" then
        Inbox.SavedMenu(self.saved, self)
      elseif ns.Places.IsOut("s:" .. self.saved) then
        ns.Places.Detach("s:" .. self.saved) -- out in its window (V32)
      else
        Inbox.ShowSaved(self.saved)
      end
    end)
    row:Hide()
    ns.Places.Draggable(row, function(self)
      return self.saved and ("s:" .. self.saved) or nil
    end)
    rail.saved[i] = row
  end
  rail.savedMore = facet(rail, "savedMore", "", S.C.dim, function(self)
    Inbox.SavedMoreMenu(self)
  end)
  rail.savedMore.dot:SetAlpha(0)
  rail.savedMore:Hide()
  -- the saved search renamed in place (plan §2.4: "a right click renames it in place")
  rail.rename = S.search(rail, L["A name, then Enter"], true)
  rail.rename:SetHeight(Inbox.FACET_H - 2)
  rail.rename:SetScript("OnEnterPressed", function(self)
    local old = self.saved
    local st = Inbox.Settings() -- before the rename: Settings lets go of a name no search has
    self:Hide()
    if old and ns.Views.Rename(old, self:GetText()) and st.saved == old then
      st.saved = strtrim(self:GetText())
    end
    Inbox.DrawRail()
  end)
  rail.rename:SetScript("OnEscapePressed", function(self)
    self:Hide()
  end)
  rail.rename:Hide()
  -- "Down to" at the rail's foot shapes the mix: moving it shows the mix (V27); the artifact's
  -- slider of the look engine (V34, R1): its title, the track filled to a round knob, the words
  rail.tier = S.slider(rail, {
    title = L["Down to"],
    min = 0,
    max = 5,
    step = 1,
    value = s.maxTier,
    words = function(v)
      return L[Inbox.TIER_WORDS[math.floor(v + 0.5)] or ""]
    end,
    onChange = function(_, v)
      local st = Inbox.Settings()
      st.maxTier = math.floor(v + 0.5)
      st.only, st.also, st.person, st.people, st.saved, st.savedStreams = nil, nil, nil, nil, nil, nil
      Inbox.Rebuild()
    end,
  })
  rail.tier:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", Inbox.PAD, Inbox.PAD)
  rail.tier:SetPoint("RIGHT", rail, "RIGHT", -Inbox.PAD, 0)
  rail.tierWords = rail.tier.words -- the tier's words, under the track
  box.rail = rail
end

-- The filter line over the stream (plan §2.1, V29): plain words, the count of matches, the star
-- that saves (plan §2.4), the x that clears; Escape clears too; a right click lists the recent
-- searches and the saved ones; suggestions under it while a word is typed (plan §2.3).
local function buildFilter()
  local row = CreateFrame("Frame", nil, box)
  row:SetPoint("TOPLEFT", box.rail, "TOPRIGHT", Inbox.GAP, 0)
  row:SetPoint("RIGHT", box, "RIGHT", -2, 0)
  row:SetHeight(Inbox.FILTER_H)
  row.star = S.action(row, {
    icon = "bookmark",
    label = L["Save this search"],
    only = true,
    row = true,
    onClick = function()
      Inbox.SaveSearch()
    end,
  })
  row.star:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  local f = S.search(row, L["Words; -word leaves out"], true)
  f:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
  f:SetPoint("RIGHT", row.star, "LEFT", -4, 0)
  f.tip =
    L["Words over the whole line: its text, who wrote it, the channel, the place, friend or guild, the items, the dungeons (dm finds the Deadmines). -word leaves out."] -- luacheck: ignore 631 (a locale key stays one literal)
  f.count = S.SetRole(S.text(f, 10, S.C.muted), "number")
  f.count:SetPoint("RIGHT", f.clear, "LEFT", -2, 0)
  f:SetText(Inbox.Settings().query or "")
  f:SetScript("OnTextChanged", function(self)
    local text = self:GetText() or ""
    self.hint:SetShown(text == "")
    self.clear:SetShown(text ~= "")
    if applying then
      return
    end
    local s = Inbox.Settings()
    if text ~= (s.query or "") then
      if s.saved then -- the player changes a saved search's words: it is not that search any more
        local v = ns.Views.Find(s.saved)
        if not v or v.query ~= text then
          Inbox.Unsave(s)
        end
      end
      s.query = text ~= "" and text or nil
      Inbox.Rebuild()
    end
    Inbox.Suggest()
  end)
  f:SetScript("OnEscapePressed", function(self)
    Inbox.SetFilter("")
    self:ClearFocus()
  end)
  f:SetScript("OnEnterPressed", function(self)
    Inbox.Remember()
    self:ClearFocus()
  end)
  f:SetScript("OnTabPressed", function()
    Inbox.TakeSuggestion(1)
  end)
  f:HookScript("OnEditFocusLost", function()
    Inbox.Remember()
    C_Timer.After(0.2, function()
      if box and not box.filter.box:HasFocus() then
        box.suggest:Hide() -- after a click on a suggestion had its turn
      end
    end)
  end)
  f:HookScript("OnMouseUp", function(self, button)
    if button == "RightButton" then
      Inbox.FilterMenu(self)
    end
  end)
  row.box = f
  row.count = f.count
  box.filter = row
  -- the suggestions: up to five rows under the line, over the stream
  local sg = CreateFrame("Frame", nil, box)
  sg:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -2)
  sg:SetPoint("RIGHT", f, "RIGHT", 0, 0)
  sg:SetFrameLevel((box:GetFrameLevel() or 1) + 20)
  sg.ground = S.roundFill(sg, S.C.panel, "radiusSmall")
  sg.edges = S.roundEdges(sg, S.C.line, "radiusSmall")
  sg.rows = {}
  for i = 1, ns.Find.SUGGEST do
    local b = CreateFrame("Button", nil, sg)
    b:SetHeight(Inbox.SUGGEST_H)
    b:SetPoint("TOPLEFT", sg, "TOPLEFT", 4, -2 - (i - 1) * Inbox.SUGGEST_H)
    b:SetPoint("RIGHT", sg, "RIGHT", -4, 0)
    b.hl = S.fill(b, S.C.hover, "HIGHLIGHT")
    b.kind = S.SetRole(S.text(b, 10, S.C.dim), "number")
    b.kind:SetPoint("LEFT", b, "LEFT", 4, 0)
    b.kind:SetWidth(64)
    b.kind:SetJustifyH("LEFT")
    b.text = S.text(b, 12, S.C.text)
    b.text:SetPoint("LEFT", b.kind, "RIGHT", 6, 0)
    b.text:SetPoint("RIGHT", b, "RIGHT", -4, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    b:SetScript("OnClick", function()
      Inbox.TakeSuggestion(i)
    end)
    sg.rows[i] = b
  end
  sg:Hide()
  box.suggest = sg
end

-- The head over a place that is not lines: a person (their face, name, who they are, Invite and
-- Add friend), or People (the count, "+ New whisper").
local function buildHead()
  local head = CreateFrame("Frame", nil, box)
  head:SetPoint("TOPLEFT", box.filter, "BOTTOMLEFT", 0, -2)
  head:SetPoint("RIGHT", box, "RIGHT", -(Inbox.TIMELINE_W + Inbox.GAP), 0)
  head:SetHeight(Inbox.HEAD_H)
  Inbox.Panel(head)
  head.face = ns.People.NewFace(head, 30)
  head.face:SetPoint("LEFT", head, "LEFT", 8, 0)
  head.more = S.action(head, {
    icon = "more",
    label = L["More"],
    only = true,
    row = true,
    onClick = function(self)
      local key = Inbox.ShownPerson()
      if key then
        ns.People.Menu(key, self)
      end
    end,
  })
  head.more:SetPoint("RIGHT", head, "RIGHT", -6, 0)
  head.friend = S.action(head, {
    icon = "plus",
    label = L["Add friend"],
    only = true,
    row = true,
    onClick = function()
      local c = ns.People.Convo(Inbox.ShownPerson())
      if c then
        Compat.AddFriend(c.name)
      end
    end,
  })
  head.friend:SetPoint("RIGHT", head.more, "LEFT", -4, 0)
  head.invite = S.action(head, {
    icon = "invite",
    label = L["Invite"],
    only = true,
    row = true,
    onClick = function()
      local c = ns.People.Convo(Inbox.ShownPerson())
      if c then
        Compat.Invite(c.name)
      end
    end,
  })
  head.invite:SetPoint("RIGHT", head.friend, "LEFT", -4, 0)
  head.new = S.action(head, {
    icon = "plus",
    label = L["New whisper"],
    row = true,
    boxed = true,
    onClick = function(self)
      ns.People.NewMenu(self)
    end,
  })
  head.new:SetPoint("RIGHT", head, "RIGHT", -6, 0)
  head.name = S.heading(head, 14, 16, S.C.headerText)
  head.name:SetPoint("TOPLEFT", head, "TOPLEFT", 8 + 30 + 10, -7)
  head.name:SetPoint("RIGHT", head.invite, "LEFT", -8, 0)
  head.name:SetJustifyH("LEFT")
  head.name:SetWordWrap(false)
  head.sub = S.text(head, 11, S.C.dim)
  head.sub:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 8 + 30 + 10, 7)
  head.sub:SetPoint("RIGHT", head.invite, "LEFT", -8, 0)
  head.sub:SetJustifyH("LEFT")
  head.sub:SetWordWrap(false)
  head:Hide()
  box.head = head
end

local function buildStream()
  local area = CreateFrame("Frame", nil, box)
  -- the stream's panel in the chat's look, light ones too ("chat needs to
  -- follow a full skinning approach"; V25: the forced dark plate is gone); the WoW look's chat
  -- ground (V34)
  Inbox.Panel(area, "stream")
  box.area = area
  area.inner = CreateFrame("Frame", nil, area)
  area.inner:SetPoint("TOPLEFT", area, "TOPLEFT", 4, -4)
  area.inner:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -2, 4)
  box.list = B.UI.VirtualList.New(area.inner, {
    kinds = ns.Rows.KINDS,
    stick = true,
    bottomUp = true,
    max = Inbox.MAX,
    onBelow = function(n)
      Inbox.DrawBelow(n)
    end,
  })
  local newer = S.action(area, {
    icon = "plus",
    label = "",
    row = true,
    boxed = true,
    onClick = function()
      box.list:ScrollToEnd()
    end,
  })
  newer:SetPoint("BOTTOM", area, "BOTTOM", 0, 4)
  newer:Hide()
  box.newer = newer
  local empty = S.text(area, 12, S.C.dim)
  empty:SetPoint("CENTER", area, "CENTER", 0, 0)
  empty:SetWidth(260)
  empty:SetWordWrap(true)
  empty:Hide()
  box.empty = empty
  local foot = CreateFrame("Button", nil, box)
  foot:SetPoint("TOPLEFT", area, "BOTTOMLEFT", 0, -1)
  foot:SetPoint("TOPRIGHT", area, "BOTTOMRIGHT", 0, -1)
  foot:SetHeight(Inbox.FOOT_H)
  foot.text = S.text(foot, 10, S.C.dim)
  foot.text:SetPoint("LEFT", foot, "LEFT", 4, 0)
  foot:SetScript("OnClick", function()
    Inbox.ShowEverything()
  end)
  foot.tip = L["Show every line: every stream, down to the junk"]
  foot:SetScript("OnEnter", S.TipEnter)
  foot:SetScript("OnLeave", S.TipLeave)
  box.foot = foot
end

-- The proposed answers (V12) over the input line, while the person shown waits for one.
local function buildPlates()
  local plates = CreateFrame("Frame", nil, box)
  plates:SetHeight(Inbox.PLATES_H)
  plates.label = S.SetRole(S.text(plates, 11, S.C.muted), "label")
  plates.label:SetPoint("LEFT", plates, "LEFT", 4, 0)
  plates.label:SetText(string.upper(L["Answer"]))
  plates.buttons = {}
  plates:Hide()
  box.plates = plates
end

local function buildTimeline()
  local t = CreateFrame("Button", nil, box)
  t:SetWidth(Inbox.TIMELINE_W)
  Inbox.Panel(t) -- in the chat's look (V25)
  t.ticks = {}
  t.recs = {}
  t.tip =
    L["Every line, newest at the bottom: a tick in the colour of how much it matters. Click to go there."]
  t:SetScript("OnEnter", S.TipEnter)
  t:SetScript("OnLeave", S.TipLeave)
  t:SetScript("OnMouseUp", function(self)
    local _, y = GetCursorPosition()
    local scale = self:GetEffectiveScale() or 1
    local top, h = self:GetTop() or 0, self:GetHeight() or 0
    if h > 0 then
      Inbox.JumpTo((top - y / scale) / h)
    end
  end)
  box.timeline = t
end

-- The Inbox in the main window W (built once).
function Inbox.Build(W)
  if box then
    return box
  end
  local content = W.win.content
  box = CreateFrame("Frame", nil, content)
  box:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
  box:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, ns.View.INPUT_H + 2)
  buildRail()
  buildFilter()
  buildHead()
  buildStream()
  buildPlates()
  box.ledger = ns.Ledger.Build(box) -- the session's ledger, at Mine's head (V31)
  box.ledger:SetPoint("TOPLEFT", box.filter, "BOTTOMLEFT", 0, -2)
  box.ledger:SetPoint("RIGHT", box, "RIGHT", -(Inbox.TIMELINE_W + Inbox.GAP), 0)
  ns.Asks.Build(box)
  buildTimeline()
  Inbox.Layout()
  box:SetScript("OnShow", function()
    if dirty then
      Inbox.Rebuild()
    end
  end)
  box:SetScript("OnSizeChanged", function()
    Inbox.DrawRail()
  end)
  store():On(Inbox.OnStore)
  Inbox.DrawTierWords()
  box:Hide()
  return box
end

-- The bottom of the stream: the request bar and the plates take their rows over the input line
-- while they show (plan §3.3: none open, the bar has no height).
function Inbox.Layout()
  if not box then
    return
  end
  local bottom = 2
  local asks = box.asks
  asks:ClearAllPoints()
  asks:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", Inbox.RAIL_W + 2 + Inbox.GAP, bottom)
  asks:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, bottom)
  if asks:IsShown() then
    bottom = bottom + Inbox.ASKS_H + 2
  end
  local plates = box.plates
  plates:ClearAllPoints()
  plates:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", Inbox.RAIL_W + 2 + Inbox.GAP, bottom)
  plates:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -(Inbox.TIMELINE_W + Inbox.GAP), bottom)
  if plates:IsShown() then
    bottom = bottom + Inbox.PLATES_H + 2
  end
  local area = box.area
  area:ClearAllPoints()
  local top = (box.head:IsShown() and box.head) or (box.ledger:IsShown() and box.ledger) or box.filter
  area:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -2)
  area:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -(Inbox.TIMELINE_W + Inbox.GAP), bottom + Inbox.FOOT_H)
  box.timeline:ClearAllPoints()
  box.timeline:SetPoint("TOPRIGHT", box.filter, "BOTTOMRIGHT", 0, -2)
  box.timeline:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, bottom + Inbox.FOOT_H)
  box.timeline:SetWidth(Inbox.TIMELINE_W)
end

-- ---------------------------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------------------------

local function shown()
  return box ~= nil and box:IsVisible()
end

-- The conversation shown, its head and its plates.
local function drawPerson(key)
  local P = People()
  local c = P.Convo(key)
  local q = ns.Find.Query(Inbox.Settings().query)
  local items = P.Items(c, mark and mark.key == key and mark or nil, time(), q and function(l)
    return q:Match(ns.Find.LineRec(c, l))
  end or nil)
  box.list:SetItems(items)
  local head = box.head
  head.new:Hide()
  head.more:Show()
  head.face:Show()
  local bn = P.IsBNet(key)
  head.invite:SetShown(not bn)
  head.friend:SetShown(not bn)
  P.Face(head.face, key)
  head.name:SetText(Model.ShortName(c.name))
  local rel = P.Rel(key)
  local bits = {}
  if rel then
    bits[#bits + 1] = L[P.REL_WORDS[rel] or "Stranger"]
  end
  local info = P.InfoLine(P.Info(key))
  if info ~= "" then
    bits[#bits + 1] = info
  end
  head.sub:SetText(table.concat(bits, "  .  "))
  head.name:ClearAllPoints()
  head.name:SetPoint("TOPLEFT", head, "TOPLEFT", 8 + 30 + 10, -7)
  head.name:SetPoint("RIGHT", bn and head.more or head.invite, "LEFT", -8, 0)
  head.sub:ClearAllPoints()
  head.sub:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 8 + 30 + 10, 7)
  head.sub:SetPoint("RIGHT", bn and head.more or head.invite, "LEFT", -8, 0)
  box.empty:SetShown(#items == 0)
  box.empty:SetText(
    q and L["No line matches"]
      or string.format(L["Start the conversation: say hi to %s."], Model.ShortName(c.name))
  )
  local n = 0
  for _, item in ipairs(items) do
    n = n + (item.kind == "run" and #item.lines or 0)
  end
  box.filter.count:SetText(q and tostring(n) or "")
  P.DrawPlates()
end

-- Every conversation as one list (the People place).
local function drawPeople()
  local P = People()
  local keys = P.Order()
  local q = ns.Find.Query(Inbox.Settings().query)
  if q then
    local all, kept = P.All(), {}
    for _, key in ipairs(keys) do
      local c = all[key]
      local hay = { string.lower(Model.ShortName(c.name or "")) }
      for _, l in ipairs(c.lines or {}) do
        hay[#hay + 1] = string.lower(Model.Strip(l.text) or "")
      end
      if q:Match({ plain = table.concat(hay, "\n"), who = { name = c.name }, stream = "direct" }) then
        kept[#kept + 1] = key
      end
    end
    keys = kept
  end
  local items = P.ListItems(keys, P.Waits)
  box.list.stuck = false
  box.list:SetItems(items)
  box.list.bar.ScrollTo(0)
  local head = box.head
  head.face:Hide()
  head.invite:Hide()
  head.friend:Hide()
  head.more:Hide()
  head.new:Show()
  head.name:SetText(L["People"])
  head.name:ClearAllPoints()
  head.name:SetPoint("TOPLEFT", head, "TOPLEFT", 10, -7)
  head.name:SetPoint("RIGHT", head.new, "LEFT", -8, 0)
  local n = #keys
  head.sub:SetText(n == 1 and L["1 conversation"] or L["%d conversations"]:format(n))
  head.sub:ClearAllPoints()
  head.sub:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 10, 7)
  head.sub:SetPoint("RIGHT", head.new, "LEFT", -8, 0)
  box.empty:SetShown(n == 0)
  box.empty:SetText(
    q and L["No conversation matches"] or L["No conversation yet: + for a new one, or whisper someone."]
  )
  box.filter.count:SetText(q and tostring(n) or "")
  Inbox.ShowPlates(false)
end

-- The hits per place of the filter in force (plan §2.3), nil without a filter.
local function countHits(s)
  local q = ns.Find.Query(s.query)
  if not q then
    return nil
  end
  return ns.Find.Counts(q, store():Query(), People().All())
end

-- Everything again from the store (a place switched, the tier moved, the Inbox shown).
function Inbox.Rebuild()
  if not box then
    return
  end
  ns.Asks.Adopt(box) -- the one request bar (the decks may have had it)
  if not shown() then
    dirty = true
    return
  end
  dirty = false
  local s = Inbox.Settings()
  if s.person and not People().Convo(s.person) then
    s.person = nil -- a conversation deleted or trimmed
  end
  local kind, key = Inbox.Place()
  box.list.stuck = kind ~= "people"
  box.head:SetShown(kind == "person" or kind == "people")
  if kind == "person" or kind == "people" then
    feed = nil -- the stream of records is not shown
    if kind == "person" then
      drawPerson(key)
    else
      drawPeople()
    end
  else
    Inbox.Fill(s)
    box.empty:Hide()
    Inbox.ShowPlates(false)
  end
  local form = feed and Inbox.Form(s)
  box.ledger:SetShown(form ~= nil and form.ledger == true)
  if box.ledger:IsShown() then
    ns.Ledger.Draw(box.ledger)
  end
  hits = countHits(s)
  ns.Asks.Draw()
  Inbox.DrawRail()
  Inbox.DrawFoot()
  Inbox.DrawTimeline()
  Inbox.DrawStar()
  Inbox.PaintPanels()
  Inbox.Layout()
end

-- The stream filled from the store in the form of what shows: a board's posts younger than five
-- minutes as cards (the dungeons in the player's range nearest the input line), speaker blocks,
-- or lines.
function Inbox.Fill(s)
  s = s or Inbox.Settings()
  local off, maxTier = Inbox.Shown(s)
  local form = Inbox.Form(s) or {}
  local now = time()
  feed = ns.Rows.NewFeed({
    off = off,
    maxTier = maxTier,
    query = ns.Find.Query(s.query),
    board = form.board,
    blocks = form.blocks,
    byDungeon = form.byDungeon,
    since = form.board and now - ns.Rows.BOARD_AGE or nil,
  })
  feed.filled = now
  for _, rec in ipairs(store():Query()) do
    feed:Add(rec)
  end
  if form.byDungeon then
    ns.Rows.OrderBoard(feed.items, Compat.PlayerLevel())
  end
  box.list.gap = form.board and ns.Rows.BOARD_GAP or 0
  box.list:SetItems(feed.items)
  box.filter.count:SetText(feed.opts.query and tostring(feed.matched) or "")
end

-- The store's news (Store:On): a new record goes on the stream's end, a request into the bar.
function Inbox.OnStore(what, value)
  if what == "ask" then
    if box then
      ns.Asks.Draw()
      Inbox.DrawRail()
      if Inbox.Place() == "people" and shown() then
        Inbox.Rebuild() -- who waits moved
      end
    end
    return
  end
  if what ~= "add" then
    return
  end
  if box and hits and Inbox.Settings().query then
    local q = ns.Find.Query(Inbox.Settings().query)
    if q and q:Match(value) then
      hits.streams[value.stream] = (hits.streams[value.stream] or 0) + 1
    end
  end
  if not shown() or not feed then
    dirty = dirty or not shown()
    if shown() and box.rail.pills[value.stream] then
      Inbox.DrawCounts()
    end
    return
  end
  if not ns.Combat.Draws(value) then
    dirty = true -- held until the fight is over (V11)
    return
  end
  if value.stream == "mine" and box.ledger:IsShown() then
    ns.Ledger.Draw(box.ledger)
    Inbox.Layout()
  end
  if feed.opts.board and feed:Shows(value) and time() - (feed.filled or 0) >= Inbox.BOARD_REFRESH then
    Inbox.Fill() -- the old posts leave, the ages and the counts are new
    Inbox.DrawCounts()
    return
  end
  local added, changed = feed:Add(value)
  if changed then
    box.list:Invalidate(changed)
  end
  if added then
    box.list:Append(added)
  end
  box.filter.count:SetText(feed.opts.query and tostring(feed.matched) or "")
  Inbox.DrawCounts()
  Inbox.DrawFoot()
  Inbox.TimelineLater()
end

-- A conversation changed (People.Changed): the rail's People, and the place if it shows them.
function Inbox.OnPeople(key)
  if not box then
    return
  end
  if hits then
    hits = countHits(Inbox.Settings())
  end
  Inbox.DrawRail()
  if not shown() then
    dirty = true
    return
  end
  local kind, shownKey = Inbox.Place()
  if (kind == "person" and (key == nil or key == shownKey)) or kind == "people" then
    Inbox.Rebuild()
  end
end

-- "+N" on the rail: the people beyond the ones shown.
function Inbox.MoreMenu(anchor)
  local items = {}
  local keys = People().Order()
  for i = (box and box.rail.peopleFit or ns.People.RAIL_MAX) + 1, #keys do
    local key = keys[i]
    local c = People().Convo(key)
    local n = c and c.unread or 0
    items[#items + 1] = {
      label = Model.ShortName(c and c.name or key) .. (n > 0 and ("  (" .. n .. ")") or ""),
      onClick = function()
        Inbox.ShowPerson(key, true)
      end,
    }
  end
  B.UI.Menu(anchor, L["People"], items, ns.mod)
  return items
end

-- The rail drawn again: its rows placed from the top, People and Saved among them (as many as fit
-- over the streams and "Down to"), each stream's count (or its hits while a filter is typed) and
-- whether it is in the mix, the place shown marked, "Down to" dimmed while it does not shape what
-- shows (V27).
function Inbox.DrawRail()
  if not box then
    return
  end
  local s, rail = Inbox.Settings(), box.rail
  local kind, key = Inbox.Place()
  local P = People()
  local keys = P.Order()
  local saved = ns.Views.List()
  local railH = rail:GetHeight()
  if not railH or railH <= 0 then
    railH = (box:GetHeight() or 0) - 4
  end
  -- the rows' heights: All, the streams' head and rows, the slider; People and Saved share the rest
  local fixed = Inbox.PAD + Inbox.FACET_H + Inbox.SECTION_H + #Inbox.STREAMS * Inbox.FACET_H
  local sliderH = (rail.tier:GetHeight() or 46) + Inbox.PAD + Inbox.GAP
  local room = railH > 0 and (railH - fixed - sliderH) or (2 * ns.People.RAIL_MAX * Inbox.FACET_H)
  local function rows(n, max)
    -- a section's head and its rows, "N more" when they do not all fit; returns the rows shown
    if n == 0 then
      return 0
    end
    local fit = math.max(1, math.min(max, n, math.floor((room - Inbox.SECTION_H) / Inbox.FACET_H)))
    if n > fit and fit > 1 and room - Inbox.SECTION_H < (fit + 1) * Inbox.FACET_H then
      fit = fit - 1 -- "N more" takes a row too
    end
    room = room - Inbox.SECTION_H - (fit + (n > fit and 1 or 0)) * Inbox.FACET_H
    return fit
  end
  local fit = rows(#keys, ns.People.RAIL_MAX)
  rail.peopleFit = fit
  local above = rail.all
  local function place(f)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, 0)
    f:SetPoint("RIGHT", rail, "RIGHT", -2, 0)
    above = f
  end
  local hasPeople = #keys > 0
  rail.peopleHead:SetShown(hasPeople)
  if hasPeople then
    place(rail.peopleHead)
    rail.peopleHead.count:SetText(tostring(#keys))
  end
  for i, row in ipairs(rail.people) do
    local k = hasPeople and i <= fit and keys[i] or nil
    if k then
      local c = P.Convo(k)
      row.key = k
      row.label:SetText(Model.ShortName(c.name))
      P.Face(row.face, k)
      local waits = P.Waits(k)
      local n = c.unread or 0
      if hits then
        row:SetCount(hits.people[k] or 0, true)
        row.wait:Hide()
      else
        row:SetCount(n > 0 and n or nil)
        row.wait:SetShown(waits and n == 0)
      end
      row:SetOn(true)
      row:SetOut(ns.Places.IsOut("p:" .. k))
      row:SetSelected(kind == "person" and key == k)
      row.tip = P.InfoLine(P.Info(k))
      if row.tip == "" then
        row.tip = nil
      end
      place(row)
      row:Show()
    else
      row.key = nil
      row:Hide()
    end
  end
  S.tint(rail.peopleHead.sel, S.Tok(rail.peopleHead, "accent"), kind == "people" and 0.16 or 0)
  if hasPeople and #keys > fit then
    rail.more.label:SetText(L["%d more"]:format(#keys - fit))
    place(rail.more)
    rail.more:Show()
  else
    rail.more:Hide()
  end
  place(rail.streamsHead)
  for _, pair in ipairs(Inbox.STREAMS) do
    local id = pair[1]
    local pill = rail.pills[id]
    pill:SetOn(not s.off[id])
    pill:SetOut(ns.Places.IsOut(id))
    local alone = kind == "stream" and (s.only == id or (s.also and s.also[id]))
    pill:SetSelected(alone and true or false)
    place(pill)
  end
  -- Saved: the searches that fit, "N more"
  local savedFit = rows(#saved, Inbox.SAVED_MAX)
  rail.savedFit = savedFit
  rail.savedHead:SetShown(#saved > 0)
  if #saved > 0 then
    place(rail.savedHead)
    rail.savedHead.count:SetText(tostring(#saved))
  end
  for i, row in ipairs(rail.saved) do
    local v = i <= savedFit and saved[i] or nil
    if v then
      row.saved = v.name
      row.label:SetText(v.name)
      row.tip = v.query
      row:SetOn(true)
      row:SetOut(ns.Places.IsOut("s:" .. v.name))
      row:SetSelected(kind == "saved" and key == v.name)
      row:SetCount(nil)
      place(row)
      row:Show()
    else
      row.saved = nil
      row:Hide()
    end
  end
  if #saved > savedFit then
    rail.savedMore.label:SetText(L["%d more"]:format(#saved - savedFit))
    place(rail.savedMore)
    rail.savedMore:Show()
  else
    rail.savedMore:Hide()
  end
  rail.all:SetSelected(kind == "all")
  Inbox.DrawCounts()
  rail.tier:SetValue(s.maxTier, true)
  rail.tier:SetAlpha(kind == "all" and 1 or 0.45) -- it shapes the mix only
end

-- The streams' and All's counts: their lines, or while a filter is typed its hits in them.
function Inbox.DrawCounts()
  if not box then
    return
  end
  local s, rail = Inbox.Settings(), box.rail
  local n = 0
  for _, pair in ipairs(Inbox.STREAMS) do
    local id = pair[1]
    local v = hits and (hits.streams[id] or 0) or #store().lines[id]
    rail.pills[id]:SetCount(v, hits ~= nil)
  end
  for _, id in ipairs(ns.Store.STREAMS) do
    if not s.off[id] then
      n = n + (hits and (hits.streams[id] or 0) or #store().lines[id])
    end
  end
  rail.all:SetCount(n, hits ~= nil)
end

-- "All"'s count (kept for the callers of V27).
function Inbox.DrawAllCount()
  Inbox.DrawCounts()
end

function Inbox.DrawTierWords()
  if box then
    box.rail.tier:SetValue(Inbox.Settings().maxTier, true) -- its words follow the value
  end
end

function Inbox.DrawFoot()
  local parts = {}
  if feed and feed.folded > 0 then
    parts[#parts + 1] = L["%d quieter lines folded"]:format(feed.folded)
  end
  if feed and feed.junk > 0 then
    parts[#parts + 1] = L["%d junk"]:format(feed.junk)
  end
  local errors = ns.Chat.ErrorCount()
  if errors > 0 then
    parts[#parts + 1] = S.H.warn .. L["%d errors (/bchat errors)"]:format(errors) .. "|r"
  end
  if #parts == 0 then
    box.foot.text:SetText("")
    box.foot:EnableMouse(false)
    return
  end
  box.foot.text:SetText(table.concat(parts, ", ") .. ". " .. L["Show everything"])
  box.foot:EnableMouse(true)
end

function Inbox.DrawBelow(n)
  if not box then
    return
  end
  if n > 0 then
    box.newer:SetLabel(L["%d new below"]:format(n))
    box.newer:Show()
  else
    box.newer:Hide()
  end
end

-- The plates' row (People.DrawPlates draws into it).
function Inbox.PlatesFrame()
  return box and box.plates or nil
end

function Inbox.ShowPlates(on)
  if not box then
    return
  end
  on = on and Inbox.ShownPerson() ~= nil
  if box.plates:IsShown() ~= (on and true or false) then
    box.plates:SetShown(on)
    Inbox.Layout()
  end
end

-- ---------------------------------------------------------------------------------------------
-- The filter line: its text, suggestions, recent searches (plan §2.1 to §2.3)
-- ---------------------------------------------------------------------------------------------

-- The filter line shows `text` (and the stream follows), without the line's own change.
function Inbox.SetFilter(text)
  local s = Inbox.Settings()
  text = (type(text) == "string" and text ~= "") and text or nil
  if s.saved then
    local v = ns.Views.Find(s.saved)
    if not v or v.query ~= text then
      Inbox.Unsave(s)
    end
  end
  s.query = text
  if box then
    applying = true
    box.filter.box:SetText(text or "")
    applying = false
    box.suggest:Hide()
  end
  Inbox.Rebuild()
end

-- The filter's text kept among the recent searches (Enter, or the line leaving the keyboard).
function Inbox.Remember()
  local s = Inbox.Settings()
  if s.query then
    ns.Find.Remember(s.recent, s.query)
  end
end

-- The places the suggestions offer: All, People, the streams, the saved searches.
local function places()
  local out = { { id = "all", label = L["All"] }, { id = "people", label = L["People"] } }
  for _, pair in ipairs(Inbox.STREAMS) do
    out[#out + 1] = { id = pair[1], label = L[pair[2]] }
  end
  for _, v in ipairs(ns.Views.List()) do
    out[#out + 1] = { id = "saved:" .. v.name, label = v.name }
  end
  return out
end

-- The suggestions for the word being typed (plan §2.3), drawn under the line while it has the
-- keyboard. Returns them.
function Inbox.Suggest()
  if not box then
    return {}
  end
  local f = box.filter.box
  local word = ns.Find.LastWord(f:GetText())
  local list = word and ns.Find.Suggest(word, store():Query(), People().All(), places()) or {}
  box.suggest.list = list
  for i, row in ipairs(box.suggest.rows) do
    local sgt = list[i]
    if sgt then
      row.kind:SetText(string.upper(L[Inbox.SUGGEST_KINDS[sgt.kind] or "Item"]))
      row.text:SetText(ns.Find.SuggestText(sgt))
      row:Show()
    else
      row:Hide()
    end
  end
  box.suggest:SetHeight(#list * Inbox.SUGGEST_H + 4)
  box.suggest:SetShown(#list > 0 and (f:HasFocus() or false))
  return list
end

-- A suggestion taken (Tab, a click): a person, an item or a dungeon becomes the word, a place is
-- shown.
function Inbox.TakeSuggestion(i)
  local list = box and box.suggest.list or {}
  local sgt = list[i or 1]
  if not sgt then
    return nil
  end
  local f = box.filter.box
  if sgt.kind == "place" then
    local head = (f:GetText() or ""):gsub("%-?%S*$", "")
    Inbox.SetFilter(strtrim(head))
    local id = sgt.place
    if id == "all" then
      Inbox.ShowMix()
    elseif id == "people" then
      Inbox.ShowPeople()
    elseif id:sub(1, 6) == "saved:" then
      Inbox.ShowSaved(id:sub(7))
    else
      Inbox.Solo(id)
    end
  else
    f:SetText(ns.Find.Take(f:GetText(), sgt.value))
    f:SetCursorPosition(#(f:GetText() or ""))
  end
  box.suggest:Hide()
  return sgt
end

-- The filter line's right click: the last ten searches, the saved searches, Clear.
function Inbox.FilterMenu(anchor)
  local s = Inbox.Settings()
  local items = {}
  for _, text in ipairs(s.recent) do
    items[#items + 1] = {
      label = text,
      onClick = function()
        Inbox.SetFilter(text)
      end,
    }
  end
  for _, v in ipairs(ns.Views.List()) do
    items[#items + 1] = {
      label = L["Saved: %s"]:format(v.name),
      onClick = function()
        Inbox.ShowSaved(v.name)
      end,
    }
  end
  items[#items + 1] = {
    label = L["Clear"],
    onClick = function()
      Inbox.SetFilter("")
    end,
  }
  B.UI.Menu(anchor, L["Recent searches"], items, ns.mod)
  return items
end

-- ---------------------------------------------------------------------------------------------
-- Saved searches (plan §2.4, V29; the views of V8 are their store)
-- ---------------------------------------------------------------------------------------------

-- The streams a search of what shows keeps: the streams shown alone, nil for the mix.
local function shownStreams(s)
  local kind = Inbox.Place()
  if kind ~= "stream" then
    return nil
  end
  local out = copy(s.also) or {}
  out[s.only] = true
  return out
end

-- The star: the words and the places shown kept as a saved search, named by its words; it shows
-- under Saved at once. False when there are no words.
function Inbox.SaveSearch()
  local s = Inbox.Settings()
  if not s.query then
    B:Say(L["Type words into the filter line first; the star keeps them."])
    return false
  end
  if s.saved then
    return ns.Views.Find(s.saved) -- this search is saved already
  end
  local v = ns.Views.Keep({ query = s.query, streams = shownStreams(s) })
  if not v then
    B:Say(L["Thirty searches are saved already; delete one first."])
    return false
  end
  s.saved, s.savedStreams = v.name, copy(v.streams)
  s.only, s.also, s.person, s.people = nil, nil, nil, nil
  Inbox.Rebuild()
  return v
end

-- The star filled while a saved search shows.
function Inbox.DrawStar()
  if box then
    local star = box.filter.star
    star.spec.toggle = true
    star:SetOn(Inbox.Settings().saved ~= nil)
    star.tip = Inbox.Settings().saved and L["Saved"] or L["Save this search"]
  end
end

-- A saved search left without a change of what shows: its streams stay as the streams shown.
function Inbox.Unsave(s)
  if s.savedStreams and next(s.savedStreams) then
    local first
    s.also = {}
    for _, id in ipairs(ns.Store.STREAMS) do
      if s.savedStreams[id] and id ~= "direct" then
        if first then
          s.also[id] = true
        else
          first = id
        end
      end
    end
    s.only = first
    if not next(s.also) then
      s.also = nil
    end
  end
  s.saved, s.savedStreams = nil, nil
end

-- A saved search shown: its words over its streams (every line of them), or over the mix.
function Inbox.ShowSaved(name)
  local v = ns.Views.Find(name)
  if not v then
    return false
  end
  ns.View.ShowInbox()
  local s = Inbox.Settings()
  Inbox.LeavePlace(s)
  s.only, s.also = nil, nil
  s.saved, s.savedStreams = v.name, copy(v.streams)
  s.query = v.query
  if box then
    applying = true
    box.filter.box:SetText(v.query or "")
    applying = false
  end
  Inbox.Rebuild()
  return true
end

-- A saved search's menu (plan §5): Rename, Change the words, Sound, Delete.
function Inbox.SavedMenu(name, anchor)
  local v = ns.Views.Find(name)
  if not v then
    return nil
  end
  local items = {
    {
      label = L["Rename"],
      onClick = function()
        Inbox.StartRename(name, anchor)
      end,
    },
    {
      label = L["Change the words"],
      onClick = function()
        Inbox.ShowSaved(name)
        local s = Inbox.Settings()
        Inbox.Unsave(s) -- the words go into the filter line, to change and save again
        if box then
          box.filter.box:SetFocus()
        end
        Inbox.Rebuild()
      end,
    },
  }
  -- a sound with each new line of it (the tabs' sounds, chat.md "Sounds"), the chosen one marked
  local choices = Compat.SoundChoices()
  local ids = {}
  for id in pairs(choices) do
    ids[#ids + 1] = id
  end
  table.sort(ids, function(a, b)
    return (a == "none") or (b ~= "none" and a < b)
  end)
  for _, id in ipairs(ids) do
    items[#items + 1] = {
      label = L["Sound: %s"]:format(choices[id]) .. ((v.sound or "none") == id and "  *" or ""),
      onClick = function()
        v.sound = id ~= "none" and id or nil
        if v.sound then
          Compat.PlaySound(v.sound)
        end
      end,
    }
  end
  items[#items + 1] = {
    label = L["Window of its own"],
    onClick = function()
      ns.Places.Detach("s:" .. name)
    end,
  }
  items[#items + 1] = {
    label = L["Delete"],
    onClick = function()
      local s = Inbox.Settings()
      ns.Places.Dock("s:" .. name)
      if s.saved == name then
        Inbox.Unsave(s)
      end
      ns.Views.Delete(name)
      Inbox.Rebuild()
    end,
  }
  B.UI.Menu(anchor, name, items, ns.mod)
  return items
end

-- A place into a window of its own (the menus' "Window of its own", V32).
function Inbox.Detach(id)
  return ns.Places.Detach(id)
end

-- The saved searches beyond the rail's rows.
function Inbox.SavedMoreMenu(anchor)
  local items = {}
  local list = ns.Views.List()
  for i = (box and box.rail.savedFit or Inbox.SAVED_MAX) + 1, #list do
    local name = list[i].name
    items[#items + 1] = {
      label = name,
      onClick = function()
        Inbox.ShowSaved(name)
      end,
    }
  end
  B.UI.Menu(anchor, L["Saved"], items, ns.mod)
  return items
end

-- The name edited in place over its rail row.
function Inbox.StartRename(name, row)
  if not box then
    return
  end
  local edit = box.rail.rename
  edit.saved = name
  edit:ClearAllPoints()
  if row and row.GetPoint then
    edit:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -1)
    edit:SetPoint("RIGHT", row, "RIGHT", -4, 0)
  end
  edit:SetText(name)
  edit:Show()
  edit:SetFocus()
end

-- ---------------------------------------------------------------------------------------------
-- Select text (plan §6, V33): the lines shown become one read-only text box in the same place, the
-- same font; the player drags over what they want and presses Ctrl+C. Escape or a click outside
-- returns to the lines.
-- ---------------------------------------------------------------------------------------------

local function buildSelect()
  local f = CreateFrame("Frame", nil, box.area)
  f:SetPoint("TOPLEFT", box.area, "TOPLEFT", 2, -2)
  f:SetPoint("BOTTOMRIGHT", box.area, "BOTTOMRIGHT", -2, 2)
  f:SetFrameLevel((box.area:GetFrameLevel() or 1) + 15)
  f.ground = S.fill(f, S.C.panel, "BACKGROUND")
  f.hint = S.SetRole(S.text(f, 10, S.C.dim), "number")
  f.hint:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, 3)
  f.hint:SetPoint("RIGHT", f, "RIGHT", -4, 0)
  f.hint:SetJustifyH("LEFT")
  f.hint:SetWordWrap(false)
  f.hint:SetText(L["Drag over the lines, Ctrl+C copies, Escape goes back"])
  local scroll = CreateFrame("ScrollFrame", nil, f)
  scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
  scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 18)
  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject(Compat.ChatFont())
  S.ink(edit, S.C.text)
  scroll:SetScrollChild(edit)
  f.bar = S.scrollbar(scroll, f)
  edit:SetScript("OnSizeChanged", function(self)
    f.bar.SetTotal(self:GetHeight() or 0)
  end)
  -- read only: a typed change is taken back
  edit:SetScript("OnTextChanged", function(self, user)
    if user and self:GetText() ~= f.text then
      self:SetText(f.text or "")
    end
  end)
  edit:SetScript("OnEscapePressed", function()
    Inbox.EndSelect()
  end)
  edit:SetScript("OnEditFocusLost", function()
    Inbox.EndSelect()
  end)
  f.edit, f.scroll = edit, scroll
  f:Hide()
  box.select = f
end

-- The lines shown as one text box to select in; returns its text.
function Inbox.SelectText()
  if not box then
    return nil
  end
  if not box.select then
    buildSelect()
  end
  local f = box.select
  f.text = ns.Menus.ShownText()
  local w = box.area:GetWidth()
  f.edit:SetWidth(math.max(100, ((w and w > 0) and w or 400) - 20))
  f.edit:SetText(f.text)
  f:Show()
  f.scroll:SetVerticalScroll(math.max(0, (f.edit:GetHeight() or 0) - (f.scroll:GetHeight() or 0)))
  f.edit:SetFocus()
  return f.text
end

function Inbox.EndSelect()
  if box and box.select then
    box.select:Hide()
  end
end

function Inbox.Selecting()
  return box ~= nil and box.select ~= nil and box.select:IsShown()
end

-- All's right click: copy every line shown, select them, show everything.
function Inbox.AllMenu(anchor)
  local items = {
    {
      label = L["Copy all lines shown"],
      onClick = function()
        ns.View.Copy(ns.Menus.ShownText())
      end,
    },
    {
      label = L["Select text"],
      onClick = function()
        Inbox.SelectText()
      end,
    },
    {
      label = L["Show everything"],
      onClick = function()
        Inbox.ShowEverything()
      end,
    },
  }
  B.UI.Menu(anchor, L["All"], items, ns.mod)
  return items
end

-- ---------------------------------------------------------------------------------------------
-- Places
-- ---------------------------------------------------------------------------------------------

-- A place leaves the person shown: their half-typed line is kept for them (plan §3.1).
local function keepDraft()
  local key = Inbox.ShownPerson()
  local c = key and People().Convo(key)
  if not c then
    return
  end
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
      end
    end
  end
end

-- What shows is left for another place: the person's draft kept, a saved search let go (its
-- words stay in the filter line, the new place shows under them).
function Inbox.LeavePlace(s)
  Inbox.EndSelect()
  keepDraft()
  if s.saved then
    s.saved, s.savedStreams = nil, nil
  end
  s.person, s.people = nil, nil
end

-- A click on a stream of the rail (V27, "I click left on addons, but
-- the window is empty"): that stream alone, every line of it; on the stream shown alone, the mix
-- again. Ctrl+click (V29) adds it to what shows, or takes it away again.
function Inbox.Solo(id, add)
  local s = Inbox.Settings()
  local kind = Inbox.Place()
  if add and kind == "stream" then
    if s.only == id then
      local nxt = s.also and next(s.also)
      if nxt then
        s.only = nxt
        s.also[nxt] = nil
      end
    else
      s.also = s.also or {}
      s.also[id] = (not s.also[id]) or nil
    end
    if s.also and not next(s.also) then
      s.also = nil
    end
    Inbox.Rebuild()
    return
  end
  local was = kind == "stream" and s.only == id and not s.also
  Inbox.LeavePlace(s)
  s.only, s.also = (not was) and id or nil, nil
  Inbox.Rebuild()
end

-- "All": the mix, every stream not left out, down to "Down to".
function Inbox.ShowMix()
  local s = Inbox.Settings()
  Inbox.LeavePlace(s)
  s.only, s.also = nil, nil
  Inbox.Rebuild()
end

-- The People place: every conversation as one list.
function Inbox.ShowPeople()
  ns.View.ShowInbox()
  local s = Inbox.Settings()
  Inbox.LeavePlace(s)
  s.only, s.also, s.people = nil, nil, true
  Inbox.Rebuild()
end

-- A person's place: their conversation, "N new" before what was unread, the input line on them
-- when the player asked for it (`byClick`; a setting, on by default).
function Inbox.ShowPerson(key, byClick)
  local P = People()
  local c = P.Convo(key)
  if not c then
    return false
  end
  ns.View.ShowInbox()
  local s = Inbox.Settings()
  if Inbox.ShownPerson() ~= key then
    Inbox.LeavePlace(s)
    local n = c.unread or 0
    mark = { key = key, n = n, line = n > 0 and P.FirstNew(c, n) or nil }
  end
  s.only, s.also, s.people, s.person = nil, nil, nil, key
  c.unread = 0
  -- read: the chip says no count any more; it stays until the answer (plan §3.3)
  local bn = P.IsBNet(key) and c.bnID or nil
  for _, a in ipairs(store().asks) do
    local same = (bn and a.bn == bn)
      or (not bn and a.who and Model.ShortName(a.who) == Model.ShortName(c.name))
    if a.kind == "whisper" and a.state == "open" and same and (a.unread or 0) > 0 then
      a.unread = 0
      store():Notify("ask", a)
    end
  end
  P.Changed(key)
  Inbox.Rebuild()
  if byClick then
    Inbox.TalkTo(key)
  end
  return true
end

-- The game's bar on the person shown, their draft back in it (nothing is sent).
function Inbox.TalkTo(key)
  local c = People().Convo(key)
  if not c or ns.mod.db.profile.inputFollows == false then
    return
  end
  local draft = drafts[key] or ""
  drafts[key] = nil
  if People().IsBNet(key) then
    return -- a Battle.net friend has no name the bar takes; a plate or the game's own window
  end
  Compat.OpenChat("/w " .. c.name .. " " .. draft)
end

-- Where Enter writes while this place shows (plan §3.1): a person, the guild, the group; nil for
-- the others (the last channel stays).
function Inbox.Target()
  local kind, key = Inbox.Place()
  local s = Inbox.Settings()
  if kind == "person" then
    local c = People().Convo(key)
    if c and not People().IsBNet(key) then
      return "/w " .. c.name .. " "
    end
  elseif kind == "stream" and key == "guild" and not s.also then
    return "/g "
  elseif kind == "stream" and key == "group" and not s.also then
    return Compat.InRaid() and "/ra " or "/p "
  end
  return nil
end

-- The player opened the game's bar (Enter) while the Inbox shows: an empty bar takes the place's
-- channel (never in a fight, never over a typed text, and only with "The input line follows the
-- place"). Returns the text it put in, or nil.
function Inbox.OnBarOpen(bar)
  if not shown() or ns.mod.db.profile.inputFollows == false or InCombatLockdown() then
    return nil
  end
  local target = Inbox.Target()
  if not target or not bar or (bar:GetText() or "") ~= "" then
    return nil
  end
  local key = Inbox.ShownPerson()
  local draft = key and drafts[key] or ""
  if key then
    drafts[key] = nil
  end
  bar:SetText(target .. draft)
  return target
end

-- A right click on a stream of the rail: out of the mix, or back in.
function Inbox.ToggleInMix(id)
  local s = Inbox.Settings()
  s.off[id] = (not s.off[id]) or nil
  Inbox.Rebuild()
end

-- Every stream on, down to the junk (the foot's click), the mix shown.
function Inbox.ShowEverything()
  local s = Inbox.Settings()
  Inbox.LeavePlace(s)
  s.off, s.maxTier, s.only, s.also = {}, 5, nil, nil
  Inbox.Rebuild()
end

function Inbox.TimelineLater()
  if timelinePending then
    return
  end
  timelinePending = true
  C_Timer.After(Inbox.TIMELINE_DELAY, function()
    timelinePending = false
    if shown() then
      Inbox.DrawTimeline()
    end
  end)
end

-- A tick per line of the newest TICKS, top the oldest; "needs you" thicker, the quiet tiers faint;
-- in the palette of the window (Chat's look, V13).
local drawTimeline
function Inbox.DrawTimeline()
  return S.WithPalette(S.PaletteOf(box), drawTimeline)
end

function drawTimeline()
  local t = box.timeline
  local recs = store():Query({ limit = Inbox.TICKS })
  t.recs = recs
  local h = t:GetHeight()
  if not h or h <= 0 then
    h = box.area:GetHeight() or 0
  end
  local n = #recs
  for i, rec in ipairs(recs) do
    local tick = t.ticks[i]
    if not tick then
      tick = S.fill(t, S.C.tier4, "ARTWORK")
      t.ticks[i] = tick
    end
    local tier = rec.tier or 4
    tick:ClearAllPoints()
    tick:SetPoint("TOPLEFT", t, "TOPLEFT", 0, -math.floor((i - 1) / math.max(1, n) * h))
    tick:SetPoint("RIGHT", t, "RIGHT", 0, 0)
    tick:SetHeight(tier == 0 and 3 or 1)
    S.tint(tick, S.C["tier" .. tier] or S.C.tier4, tier >= 4 and 0.4 or 1)
    tick:Show()
  end
  for i = n + 1, #t.ticks do
    t.ticks[i]:Hide()
  end
end

-- A click on the timeline at `frac` (0 the top, 1 the bottom): the stream shows that line; a line
-- the stream hides (its stream off, under the tier, another place shown) shows every line first.
function Inbox.JumpTo(frac)
  local recs = box.timeline.recs
  if #recs == 0 then
    return nil
  end
  local i = math.min(#recs, math.max(1, math.floor(frac * #recs) + 1))
  local rec = recs[i]
  if not feed then
    Inbox.ShowMix()
  end
  local item = ns.Rows.Find(feed.items, rec)
  if not item or item.hidden then
    if not feed:Shows(rec) or (rec.tier or 4) > (feed.opts.maxTier or 5) then
      Inbox.ShowEverything()
    end
    item = ns.Rows.FindFrom(feed.items, rec.id)
  end
  if item then
    box.list:ScrollToItem(item)
  end
  return item
end
