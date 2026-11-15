-- Bastian's Chat version 3, Away (plan-chat-v3.md §6.1, V10; "auto whisper back to
-- whispers with a configurable text that you can edit when starting the away"): the player starts
-- Away with a text of their own (an editor, or `/bchat away <text>`); while away, a whisper from
-- the people the player chose gets that text once per person every ten minutes (friends and the
-- guild by default, strangers only when switched on, a Game Master never, never an automatic reply
-- to an automatic reply); a card in the requests says Away is on, with "I am back". Back, a digest
-- card says what came. Away's own reply is the one line that goes out by itself (Q4, Q7 asks).
local _, ns = ...
local B = Bastians
local S = B.UI.Style
local L = ns.L
local Compat = ns.Compat

local Away = {}
ns.Away = Away

Away.REPLY_SECS = 600 -- one answer per person in this long
Away.GRACE = 5 -- seconds after the start in which moving does not end Away (V20)
Away.CATCHUP_SECS = 20 -- a cutscene or a loading screen this long brings a catch-up card (V20)
Away.CLOSE = { friend = "friends", bnet = "friends", guild = "guild", group = "guild" }

local on = false
local since, fromSeq
local replied = {} -- [name or Battle.net id] = when answered
local card -- the open "You are away" request
local editor
local sawAFK = false -- the game marked the player AFK while away (V20)
local pause -- { kind, since, fromSeq } while a cutscene or a loading screen runs (V20)

local function store()
  return ns.Chat.Store()
end

function Away.Settings()
  local p = ns.mod.db.profile
  p.away = type(p.away) == "table" and p.away or {}
  local s = p.away
  if type(s.text) ~= "string" or s.text == "" then
    s.text = L["Away for a moment, back soon."]
  end
  if type(s.marker) ~= "string" then
    s.marker = L["[away]"]
  end
  if s.friends == nil then
    s.friends = true
  end
  if s.guild == nil then
    s.guild = true
  end
  if s.strangers == nil then
    s.strangers = false -- Q2: off by default
  end
  if s.endOnMove == nil then
    s.endOnMove = true -- V20: moving is being back
  end
  return s
end

function Away.On()
  return on
end

-- Who gets an answer (pure but for the settings): a relation, a Game Master never.
function Away.Answers(rel, s)
  if rel == "gm" then
    return false
  end
  local group = Away.CLOSE[rel]
  if group then
    return s[group] == true
  end
  return s.strangers == true
end

function Away.Start(text)
  local s = Away.Settings()
  if type(text) == "string" and text:find("%S") then
    s.text = strtrim(text)
  end
  if on then
    return
  end
  on, since, fromSeq, replied = true, time(), store().seq, {}
  sawAFK = Compat.IsAFK() == true
  card = store():Ask({ kind = "away", t = since })
end

-- Back: the Away card goes, the digest of what came takes its place.
function Away.Stop()
  if not on then
    return
  end
  on = false
  if card then
    store():Answer(card.id, "chat")
    card = nil
  end
  local recs = {}
  for _, rec in ipairs(store():Query()) do
    if rec.id > (fromSeq or 0) then
      recs[#recs + 1] = rec
    end
  end
  local sum = Away.Summary(recs)
  store():Ask({
    kind = "digest",
    t = time(),
    minutes = math.max(1, math.floor((time() - since) / 60 + 0.5)),
    summary = sum,
  })
end

-- ---------------------------------------------------------------------------------------------
-- Away ends by itself, and the catch-up cards (V20)
-- ---------------------------------------------------------------------------------------------

-- The player moved (PLAYER_STARTED_MOVING): back, unless switched off or just started.
function Away.OnMove()
  if on and Away.Settings().endOnMove and time() - (since or 0) >= Away.GRACE then
    Away.Stop()
  end
end

-- The player's flags changed (PLAYER_FLAGS_CHANGED): the game's AFK seen while away, and its end
-- is being back.
function Away.OnFlags(unit)
  if not on or (unit ~= nil and unit ~= "player") then
    return
  end
  local afk = Compat.IsAFK()
  if afk then
    sawAFK = true
  elseif afk == false and sawAFK then
    Away.Stop()
  end
end

-- Does a summary hold news (a whisper, a mention, the guild's or the group's lines)? Trade alone
-- is none.
function Away.HasNews(s)
  return s.whispers + s.mentions + s.guild + s.group > 0
end

-- What came after the record `fromSeq`, as a summary.
local function summarySince(fromSeqOf)
  local recs = {}
  for _, rec in ipairs(store():Query()) do
    if rec.id > (fromSeqOf or 0) then
      recs[#recs + 1] = rec
    end
  end
  return Away.Summary(recs)
end

-- A catch-up card after a fight, a cutscene or a loading screen (`after`): what came since the
-- record `fromSeqOf`, when it holds news and the player is not away (Away's own digest says it).
function Away.CatchUp(after, fromSeqOf, began)
  if on then
    return nil
  end
  local sum = summarySince(fromSeqOf)
  if not Away.HasNews(sum) then
    return nil
  end
  return store():Ask({
    kind = "digest",
    after = after,
    t = time(),
    minutes = math.max(1, math.floor((time() - (began or time())) / 60 + 0.5)),
    summary = sum,
  })
end

-- A cutscene or a loading screen began (`kind`: "cutscene", "loading") or ended (nil).
function Away.Pause(kind)
  if kind then
    pause = pause or { kind = kind, since = time(), fromSeq = store().seq }
    return
  end
  local p = pause
  pause = nil
  if p and time() - p.since >= Away.CATCHUP_SECS then
    Away.CatchUp(p.kind, p.fromSeq, p.since)
  end
end

-- What came while away (pure): { whispers, people, mentions, guild, group, offers, junk }.
function Away.Summary(recs)
  local s = { whispers = 0, people = 0, mentions = 0, guild = 0, group = 0, offers = 0, junk = 0 }
  local seen = {}
  for _, rec in ipairs(recs) do
    if rec.stream == "direct" and not rec.own and rec.ask then
      s.whispers = s.whispers + 1
      local who = rec.who and (rec.who.name or rec.who.bn)
      if who and not seen[who] then
        seen[who] = true
        s.people = s.people + 1
      end
    elseif rec.ask and rec.ask.kind == "mention" then
      s.mentions = s.mentions + 1
    elseif rec.stream == "guild" then
      s.guild = s.guild + 1
    elseif rec.stream == "group" then
      s.group = s.group + 1
    elseif rec.stream == "market" then
      s.offers = s.offers + 1
    elseif rec.stream == "junk" then
      s.junk = s.junk + 1
    end
  end
  return s
end

-- The digest's words: "3 whispers from 2 people, 1 mention, 14 guild lines" (nothing: "Nothing came.").
function Away.SummaryText(s)
  local parts = {}
  if s.whispers > 0 then
    parts[#parts + 1] = L["%d whispers from %d people"]:format(s.whispers, s.people)
  end
  if s.mentions > 0 then
    parts[#parts + 1] = L["%d mentions"]:format(s.mentions)
  end
  if s.guild > 0 then
    parts[#parts + 1] = L["%d guild lines"]:format(s.guild)
  end
  if s.group > 0 then
    parts[#parts + 1] = L["%d group lines"]:format(s.group)
  end
  if s.offers > 0 then
    parts[#parts + 1] = L["%d offers in Trade"]:format(s.offers)
  end
  return #parts > 0 and table.concat(parts, ", ") or L["Nothing came."]
end

-- A record in the store while away (Chat.Record): a whisper that gets the answer.
function Away.OnRecord(rec)
  if not on or rec.stream ~= "direct" or rec.own or rec.auto or rec.secret or not rec.ask then
    return nil
  end
  local s = Away.Settings()
  local who = rec.who or {}
  if not Away.Answers(who.rel, s) then
    return nil
  end
  if type(rec.body) == "string" and s.marker ~= "" and rec.body:find(s.marker, 1, true) then
    return nil -- another player's automatic answer: never answered
  end
  local key = who.name or who.bn
  local t = time()
  if not key or (replied[key] and t - replied[key] < Away.REPLY_SECS) then
    return nil
  end
  replied[key] = t
  local text = (s.marker ~= "" and (s.marker .. " ") or "") .. s.text
  B:Fire("BASTIANS_SAYING", "away", "WHISPER", who.name, text)
  if who.bn and not who.name then
    Compat.SendBNet(who.bn, text) -- from a timer: probe X6
  else
    Compat.SendChat(text, "WHISPER", who.name)
  end
  return text
end

-- ---------------------------------------------------------------------------------------------
-- The editor: the text, who gets it, Start (owner: "a configurable text that you can edit when
-- starting the away")
-- ---------------------------------------------------------------------------------------------

local function buildEditor()
  local s = Away.Settings()
  editor = B.UI.Window("BastiansChatAway", {
    module = "Chat",
    title = L["Away"],
    width = 360,
    height = 214,
    db = s,
    strata = "DIALOG",
  })
  local c = editor.content
  local label = S.text(c, 11, S.C.dim)
  label:SetPoint("TOPLEFT", c, "TOPLEFT", 6, -6)
  label:SetText(L["Your answer while you are away"])
  local box = S.search(c, L["Away for a moment, back soon."], true)
  box:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
  box:SetPoint("RIGHT", c, "RIGHT", -6, 0)
  box:SetScript("OnTextChanged", function(self)
    local text = self:GetText() or ""
    self.hint:SetShown(text == "")
    self.clear:SetShown(text ~= "")
  end)
  box:SetScript("OnEnterPressed", function(self)
    Away.Start(self:GetText())
    editor:Hide()
  end)
  editor.box = box
  local prev = box
  editor.checks = {}
  for _, row in ipairs({
    { "friends", "Answer friends" },
    { "guild", "Answer the guild and the group" },
    { "strangers", "Answer strangers" },
    { "endOnMove", "End when I move" },
  }) do
    local cb = B.UI.Widgets.Checkbox(c, L[row[2]], function(checked)
      Away.Settings()[row[1]] = checked
    end)
    cb:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -6)
    cb:SetPoint("RIGHT", c, "RIGHT", -6, 0)
    editor.checks[row[1]] = cb
    prev = cb
  end
  local start = S.action(c, {
    icon = "send",
    label = L["Start"],
    primary = true,
    onClick = function()
      Away.Start(editor.box:GetText())
      editor:Hide()
    end,
  })
  start:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -6, 6)
  editor.start = start
  ns.View.Dress(editor) -- Chat's look (V13), once its parts are built
end

-- The editor, filled with the last text and the choices.
function Away.Edit()
  if not editor then
    buildEditor()
  end
  local s = Away.Settings()
  editor.box:SetText(s.text)
  for key, cb in pairs(editor.checks) do
    cb:SetChecked(s[key] == true)
  end
  editor:Show()
  return editor
end

function Away.Editor()
  return editor
end

-- `/bchat away [text]`: with a text, Away starts at once; without, the editor opens.
function Away.Command(rest)
  if type(rest) == "string" and rest:find("%S") then
    Away.Start(rest)
  else
    Away.Edit()
  end
end
