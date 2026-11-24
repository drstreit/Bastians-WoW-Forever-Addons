-- Bastian's Chat, the people (plan-chat-one-window.md §3, ADR 0076): whispers are places of the one
-- window. Every partner's conversation (account-wide, 30 days and 500 lines; Battle.net ones for
-- the session), what the client knows about them and their face, the order of the rail's People,
-- and how a conversation and the People list draw in the window's stream: runs of one speaker
-- under one name and time on two sides, a divider per day, "N new" before what was unread; the
-- People place as a phone's chat list. Version 2's Messenger window is gone (V30); its history is
-- the same `global.convos`.
local _, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
local L = ns.L
local S = B.UI.Style
local Model, Compat = ns.Model, ns.Compat

local People = {}
ns.People = People

People.RUN_SECS = 300 -- one speaker's lines within five minutes form one run
People.RAIL_MAX = 5 -- people on the rail, then "N more"
People.INFO_AGE = 60 -- seconds a partner's info is kept before the client is asked again
People.RUN_SHARE = 0.78 -- a run's widest share of the view
People.FACE = 32 -- a face in the People list
People.ROW_H = 50 -- a person in the People list
People.CLASS_CIRCLES = "Interface\\TargetingFrame\\UI-Classes-Circles"
-- who writes, for the order (D6): Game Master, friend, guild, stranger
People.REL_RANK = { gm = 4, friend = 3, bnet = 3, guild = 2, group = 2, stranger = 1 }
People.REL_WORDS = {
  gm = "Game Master",
  friend = "Friend",
  bnet = "Friend",
  guild = "Guild",
  group = "Group",
  stranger = "Stranger",
}

local session = {} -- the Battle.net conversations of this session (never stored)

local function mod()
  return ns.mod
end

local function settings()
  local p = mod().db.profile
  p.messenger = type(p.messenger) == "table" and p.messenger or {}
  return p.messenger
end

local function stored()
  return mod().db.global.convos
end

local function isBNet(key)
  return type(key) == "string" and key:sub(1, 3) == "bn:"
end
People.IsBNet = isBNet

function People.Convo(key)
  if isBNet(key) then
    return session[key]
  end
  return key and stored()[key] or nil
end

-- Every conversation: the stored ones and this session's Battle.net ones.
function People.All()
  local t = {}
  for k, v in pairs(stored()) do
    t[k] = v
  end
  for k, v in pairs(session) do
    t[k] = v
  end
  return t
end

function People.Unread()
  local n = 0
  for _, c in pairs(People.All()) do
    n = n + (c.unread or 0)
  end
  return n
end

-- The conversations with unread lines, newest first (the feed's tooltip).
function People.UnreadConvos()
  local convos, out = People.All(), {}
  for _, key in ipairs(Model.ConvoOrder(convos)) do
    if (convos[key].unread or 0) > 0 then
      out[#out + 1] = convos[key]
    end
  end
  return out
end

function People.MarkRead(key)
  local c = People.Convo(key)
  if c and (c.unread or 0) > 0 then
    c.unread = 0
    People.Changed()
  end
end

-- Every conversation read (the feed's right click).
function People.MarkAllRead()
  for _, c in pairs(People.All()) do
    c.unread = 0
  end
  People.Changed()
end

-- ---------------------------------------------------------------------------------------------
-- Who they are: what the client knows (Compat.PartnerInfo), kept with the conversation so an
-- offline partner keeps the class of their last visit
-- ---------------------------------------------------------------------------------------------

function People.Info(key, fresh)
  local c = People.Convo(key)
  if not c then
    return nil
  end
  local info = c.info
  if fresh or not info or (time() - (info.at or 0)) > People.INFO_AGE then
    local got = Compat.PartnerInfo(c.name, isBNet(key) and c.bnID or nil, c.guid)
    info = info or {}
    for k, v in pairs(got) do
      info[k] = v
    end
    info.at = time()
    c.info = info
  end
  return info
end

-- The line under the name: level, class, guild, zone, realm, the parts known.
function People.InfoLine(info)
  if not info then
    return ""
  end
  local bits = {}
  if info.level then
    bits[#bits + 1] = string.format(L["Level %d"], info.level)
  end
  if info.className then
    bits[#bits + 1] = info.className
  end
  if info.guild then
    bits[#bits + 1] = "<" .. info.guild .. ">"
  end
  if info.zone then
    bits[#bits + 1] = info.zone
  end
  if info.realm then
    bits[#bits + 1] = info.realm
  end
  return table.concat(bits, ", ")
end

-- How the player knows them: "gm", "bnet", "friend", "guild", "group", "stranger" (nil unknown).
function People.Rel(key)
  local c = People.Convo(key)
  if not c then
    return nil
  end
  if c.gm then
    return "gm"
  end
  if isBNet(key) then
    return "bnet"
  end
  return ns.Chat.Relation(c.name)
end

-- A partner's face (plan-chat-v3.md V26): their portrait while the game can draw one (a unit now),
-- else their class's symbol of ours in the class's colour on a round plate, else a person.
-- Returns "portrait", "class" or "person".
People.FACE_GLYPH = 0.72 -- a glyph's share of the face
function People.PaintFace(face, key, c, info)
  local tex = face.icon
  tex:SetTexCoord(0, 1, 0, 1)
  local unit = c and not isBNet(key) and Compat.UnitOf(c.name)
  if unit and Compat.Portrait(tex, unit) then
    S.untint(tex)
    tex:ClearAllPoints()
    tex:SetAllPoints(face)
    face.plate:Hide()
    return "portrait"
  end
  local size = math.floor((face:GetWidth() or People.FACE) * People.FACE_GLYPH + 0.5)
  tex:ClearAllPoints()
  tex:SetPoint("CENTER", face, "CENTER", 0, 0)
  tex:SetSize(size, size)
  face.plate:Show()
  local class = info and info.class
  local glyph = type(class) == "string" and B.UI.GLYPH_PATHS["class_" .. class:lower()]
  if glyph then
    tex:SetTexture(glyph)
    local r, g, b = Compat.ClassColor(class)
    if r then
      S.untint(tex)
      tex:SetVertexColor(r, g, b) -- the client's class colour, a value
    else
      S.tint(tex, S.Tok(face, "text"))
    end
    return "class"
  end
  tex:SetTexture(B.UI.GLYPH_PATHS.person)
  S.tint(tex, S.Tok(face, "dim"))
  return "person"
end

-- A face: a round plate of the look, the texture on it, the online dot at its foot.
function People.NewFace(parent, size)
  local face = CreateFrame("Frame", nil, parent)
  face:SetSize(size, size)
  face.plate = S.roundFill(face, S.C.inset, "pill")
  face.icon = face:CreateTexture(nil, "ARTWORK")
  face.icon:SetAllPoints(face)
  face.dot = CreateFrame("Frame", nil, face)
  local d = math.max(6, math.floor(size / 4))
  face.dot:SetSize(d, d)
  face.dot:SetPoint("BOTTOMRIGHT", face, "BOTTOMRIGHT", 1, -1)
  face.dot:SetFrameLevel((face:GetFrameLevel() or 1) + 2)
  face.dot.fill = S.roundFill(face.dot, S.C.accent, "pill")
  face.dot:Hide()
  return face
end

-- The face of a conversation with its online dot (none when the client cannot tell).
function People.Face(face, key)
  local c = People.Convo(key)
  local info = c and People.Info(key) or nil
  local how = People.PaintFace(face, key, c, info)
  if face.dot then
    if not info or info.online == nil then
      face.dot:Hide()
    else
      S.tint(face.dot.fill, info.online and S.C.good or S.C.muted)
      face.dot:Show()
    end
  end
  return how
end

-- ---------------------------------------------------------------------------------------------
-- Lines in
-- ---------------------------------------------------------------------------------------------

local OUT = { WHISPER_INFORM = true, BN_WHISPER_INFORM = true }
local AWAY = { AFK = "away", DND = "busy" }

-- A whisper line (chat.md): into its conversation; an incoming one counts as unread unless the
-- person's place is shown. Returns the conversation.
function People.Add(line)
  if line.secret or type(line.msg) ~= "string" or not line.partner then
    return nil
  end
  local bn = line.cat == "bnet"
  local key = bn and ("bn:" .. tostring(line.bnID or line.partner)) or line.partner
  local out = OUT[line.chatType] or nil
  local text = line.msg
  if AWAY[line.chatType] then
    text = "(" .. L[AWAY[line.chatType]] .. ") " .. text
  end
  local c = Model.ConvoPush(bn and session or stored(), key, line.partner, {
    at = line.at or time(),
    out = out,
    text = text,
  }, settings().lines)
  if bn then
    c.bnID = line.bnID
  elseif type(line.guid) == "string" and line.guid ~= "" then
    c.guid = line.guid -- the class of a stranger too (V26)
  end
  if line.flags == "GM" or line.flags == "DEV" then
    c.gm = true -- a Game Master's conversation says so (plan-chat-v3.md §3.2, probe X2)
  end
  local W = ns.Places.Window("p:" .. key)
  if out or (ns.Front.ShowsPerson(key) and ns.Front.Frame():IsVisible()) or (W and W.win.frame:IsShown()) then
    c.unread = 0 -- answered, or read where it shows
  end
  People.Changed(key)
  return c
end

-- A conversation opened by the player (the People section's "+", a name): empty until somebody
-- writes, its place shown with the input line on them.
function People.Open(name)
  name = strtrim(name or "")
  if name == "" then
    return nil
  end
  Model.ConvoOpen(stored(), name, name, time())
  ns.Front.ShowPerson(name, true)
  return name
end

-- A line to the partner (a plate, a person's window): a whisper or a Battle.net whisper.
function People.SendOne(key, text)
  local c = People.Convo(key)
  if not c or type(text) ~= "string" or text == "" then
    return false
  end
  if isBNet(key) then
    return Compat.SendBNet(c.bnID, text)
  end
  return Compat.SendChat(text, "WHISPER", c.name)
end

function People.Delete(key)
  if isBNet(key) then
    session[key] = nil
  else
    stored()[key] = nil
  end
  People.Changed()
end

-- The conversation as plain text into the copy box.
function People.CopyText(key)
  local c = People.Convo(key)
  if not c then
    return nil
  end
  local out = {}
  for _, l in ipairs(c.lines) do
    out[#out + 1] = string.format(
      "%s %s: %s",
      date("%d.%m. %H:%M", l.at),
      l.out and L["You"] or Model.ShortName(c.name),
      Model.Strip(l.text)
    )
  end
  return table.concat(out, "\n")
end

function People.CopyConvo(key)
  local text = People.CopyText(key)
  return text and ns.View.Copy(text) or nil
end

-- ---------------------------------------------------------------------------------------------
-- The order (D6) and who waits
-- ---------------------------------------------------------------------------------------------

-- Does the person wait for an answer (an open whisper request: the request bar's chip)?
function People.Waits(key)
  local c = People.Convo(key)
  local store = ns.Chat.Store()
  if not c or not store then
    return false
  end
  local bn = isBNet(key) and c.bnID or nil
  for _, a in ipairs(store.asks) do
    if a.kind == "whisper" and a.state == "open" then
      if (bn and a.bn == bn) or (not bn and a.who and Model.ShortName(a.who) == Model.ShortName(c.name)) then
        return true
      end
    end
  end
  return false
end

-- The keys in the rail's order (plan §3.1, D6): those who wait first, Game Master, friend, guild,
-- stranger, then the newest; then the others, a Game Master first, then the newest. Pure but for
-- `waits(key)` and `rel(key)`.
function People.Ordered(convos, waits, rel)
  local keys = Model.ConvoOrder(convos)
  local pos = {}
  for i, key in ipairs(keys) do
    pos[key] = i
  end
  local w, r, pin = {}, {}, {}
  for _, key in ipairs(keys) do
    w[key] = waits(key) and 1 or 0
    r[key] = People.REL_RANK[rel(key) or "stranger"] or 1
    pin[key] = convos[key].pinned and 1 or 0
  end
  table.sort(keys, function(a, b)
    if pin[a] ~= pin[b] then
      return pin[a] > pin[b] -- pinned on top by the player (V33)
    end
    if w[a] ~= w[b] then
      return w[a] > w[b]
    end
    local ra, rb = r[a], r[b]
    if w[a] == 0 then -- the others by the newest, only a Game Master above them
      ra, rb = (ra == 4) and 1 or 0, (rb == 4) and 1 or 0
    end
    if ra ~= rb then
      return ra > rb
    end
    return pos[a] < pos[b]
  end)
  return keys
end

function People.Order()
  return People.Ordered(People.All(), People.Waits, People.Rel)
end

-- ---------------------------------------------------------------------------------------------
-- A conversation as items of the stream (pure but for `date`): runs, days, "N new"
-- ---------------------------------------------------------------------------------------------

local function dayOf(t)
  return date("%Y-%m-%d", t)
end

-- "Today", "Yesterday" or the date.
function People.DayLabel(t, now)
  now = now or time()
  local day = dayOf(t)
  if day == dayOf(now) then
    return L["Today"]
  elseif day == dayOf(now - 86400) then
    return L["Yesterday"]
  end
  return date("%d.%m.%Y", t)
end

-- The first of the `n` unread lines of a conversation: the n-th line from the end that came in.
function People.FirstNew(c, n)
  local seen = 0
  for i = #(c and c.lines or {}), 1, -1 do
    local l = c.lines[i]
    if not l.out then
      seen = seen + 1
      if seen == n then
        return l
      end
    end
  end
  return nil
end

-- The items of a conversation: { kind = "day", label }, { kind = "newdiv", n }, { kind = "run",
-- out, at, name, lines = { texts }, bn }. `mark` = { line, n }: "N new" stands before that line
-- (the first that was unread when the place was opened). `query` (optional) keeps only the lines
-- it takes.
function People.Items(c, mark, now, query)
  local items = {}
  if not c then
    return items
  end
  local lines = {}
  for _, l in ipairs(c.lines or {}) do
    if not query or query(l) then
      lines[#lines + 1] = l
    end
  end
  local run, lastDay
  local name = Model.ShortName(c.name or "?")
  for _, l in ipairs(lines) do
    local day = dayOf(l.at or 0)
    if day ~= lastDay then
      lastDay = day
      items[#items + 1] = { kind = "day", label = People.DayLabel(l.at or 0, now) }
      run = nil
    end
    if mark and mark.line == l and not query then
      items[#items + 1] = { kind = "newdiv", n = mark.n }
      run = nil
    end
    local out = l.out and true or false
    if run and run.out == out and (l.at or 0) - (run.lastAt or 0) <= People.RUN_SECS then
      run.lines[#run.lines + 1] = l.text
      run.lastAt = l.at
      run.src[#run.src + 1] = l
    else
      run = {
        kind = "run",
        out = out,
        at = l.at,
        lastAt = l.at,
        name = out and L["You"] or name,
        lines = { l.text },
        src = { l },
        bn = c.bnID ~= nil or nil,
      }
      items[#items + 1] = run
    end
  end
  return items
end

-- The People place: every conversation as one list, "Waiting for you" first, then "Earlier".
-- Items { kind = "section", label } and { kind = "person", key }.
function People.ListItems(keys, waits)
  local items, waiting, earlier = {}, {}, {}
  for _, key in ipairs(keys) do
    if waits(key) then
      waiting[#waiting + 1] = key
    else
      earlier[#earlier + 1] = key
    end
  end
  if #waiting > 0 then
    items[#items + 1] = { kind = "section", label = L["Waiting for you"] .. "  " .. #waiting }
    for _, key in ipairs(waiting) do
      items[#items + 1] = { kind = "person", key = key, waits = true }
    end
  end
  if #earlier > 0 then
    items[#items + 1] = { kind = "section", label = L["Earlier"] }
    for _, key in ipairs(earlier) do
      items[#items + 1] = { kind = "person", key = key }
    end
  end
  return items
end

-- ---------------------------------------------------------------------------------------------
-- Changes: the rail, the feed (BASTIANS_CHAT_UNREAD), the chat's minimap badge
-- ---------------------------------------------------------------------------------------------

-- the unread count or the people behind it changed (the feed of the broker displays reads it)
B:DeclareMessage("BASTIANS_CHAT_UNREAD")
local unreadSig = ""

function People.Changed(key)
  local n = People.Unread()
  local sig = ""
  for _, c in ipairs(People.UnreadConvos()) do
    sig = sig .. (c.name or "") .. "=" .. c.unread .. ";"
  end
  if sig ~= unreadSig then
    unreadSig = sig
    B:Fire("BASTIANS_CHAT_UNREAD", n)
  end
  -- the badge: the people, and with the decks the group's unread lines (plan-chat-two-decks §2)
  ns.View.UnreadCount(n + (ns.Front.GroupUnread and ns.Front.GroupUnread() or 0))
  ns.Front.OnPeople(key)
  ns.Places.OnPeople(key) -- a person out in a window of their own (V32)
end

-- At the start: the history trimmed (30 days, 500 lines a partner) and the unread count shown.
function People.Start()
  local p = settings()
  Model.TrimConvos(stored(), time(), p.days, p.lines)
  People.Changed()
end

-- ---------------------------------------------------------------------------------------------
-- Menus
-- ---------------------------------------------------------------------------------------------

-- A person's menu (the rail, the People list, a conversation's head).
function People.Menu(key, anchor)
  local c = People.Convo(key)
  if not c then
    return nil
  end
  local items = {
    {
      label = L["Open the conversation"],
      onClick = function()
        ns.Front.ShowPerson(key, true)
      end,
    },
  }
  if not isBNet(key) then
    items[#items + 1] = {
      label = L["Invite"],
      onClick = function()
        Compat.Invite(c.name)
      end,
    }
    items[#items + 1] = {
      label = L["Add friend"],
      onClick = function()
        Compat.AddFriend(c.name)
      end,
    }
    items[#items + 1] = {
      label = L["Copy name"],
      onClick = function()
        ns.View.Copy(c.name)
      end,
    }
  end
  items[#items + 1] = {
    label = L["Copy conversation"],
    onClick = function()
      People.CopyConvo(key)
    end,
  }
  items[#items + 1] = {
    label = c.pinned and L["Unpin"] or L["Pin on top"],
    onClick = function()
      c.pinned = (not c.pinned) or nil
      People.Changed()
    end,
  }
  if ns.Front.Detach then
    items[#items + 1] = {
      label = L["Window of its own"],
      onClick = function()
        ns.Front.Detach("p:" .. key)
      end,
    }
  end
  items[#items + 1] = {
    label = L["Delete conversation"],
    onClick = function()
      if ns.Front.ShowsPerson(key) then
        ns.Front.ShowPeople()
      end
      ns.Places.Dock("p:" .. key)
      People.Delete(key)
    end,
  }
  B.UI.Menu(anchor, Model.ShortName(c.name), items, mod())
  return items
end

-- The "+" of the People section: a name to type (the game's bar opens on "/w "), the friends
-- online to pick.
function People.NewMenu(anchor)
  local items = {
    {
      label = L["Type a name..."],
      onClick = function()
        Compat.OpenChat("/w ")
      end,
    },
  }
  local friends = B.Compat.Friends and B.Compat.Friends() or {}
  table.sort(friends, function(a, b)
    return a.name < b.name
  end)
  for _, f in ipairs(friends) do
    if f.online then
      items[#items + 1] = {
        label = f.area and (f.name .. "  " .. f.area) or f.name,
        onClick = function()
          People.Open(f.name)
        end,
      }
    end
  end
  B.UI.Menu(anchor, L["New conversation"], items, mod())
  return items
end

-- A run's menu: copy it, every line shown, select the text (V33); the player's own lines kept as
-- answers, or forgotten (V12's bubble menu).
function People.RunMenu(run, anchor)
  if not run then
    return nil
  end
  local items = {
    {
      label = L["Copy line"],
      onClick = function()
        ns.View.Copy(ns.Menus.LineText(run))
      end,
    },
    {
      label = L["Copy all lines shown"],
      onClick = function()
        ns.View.Copy(ns.Menus.ShownText())
      end,
    },
    {
      label = L["Select text"],
      onClick = function()
        ns.Front.SelectText()
      end,
    },
  }
  if not run.out then
    B.UI.Menu(anchor, run.name or "", items, mod())
    return items
  end
  for i = #run.lines, math.max(1, #run.lines - 4), -1 do
    local text = run.lines[i]
    if type(text) == "string" then
      local short = Model.Strip(text) or text
      if #short > 40 then
        short = short:sub(1, 38) .. "..."
      end
      if ns.Answers.IsKept(text) then
        items[#items + 1] = {
          label = L["Forget this answer"] .. ": " .. short,
          onClick = function()
            ns.Answers.Forget(text)
            People.DrawPlates()
          end,
        }
      else
        items[#items + 1] = {
          label = L["Keep as an answer"] .. ": " .. short,
          onClick = function()
            if not ns.Answers.Keep(text) then
              B:Say(L["Twelve lines are kept as answers already; forget one first."])
            end
            People.DrawPlates()
          end,
        }
      end
    end
  end
  B.UI.Menu(anchor, L["Your line"], items, mod())
  return items
end

-- ---------------------------------------------------------------------------------------------
-- The proposed answers (plan-chat-v3.md §5, V12) over the input line, for the person shown: one
-- click sends a plate, Shift+click puts it into the line to change first; nothing is ever sent
-- without the click
-- ---------------------------------------------------------------------------------------------

local platesAsk -- the question the plates answer, for the counts

-- The plates for the shown person on `holder` (the window's plates row); returns how many show.
function People.DrawPlates()
  local holder = ns.Front.PlatesFrame and ns.Front.PlatesFrame()
  if not holder then
    return 0
  end
  local key = ns.Front.ShownPerson()
  local c = key and People.Convo(key)
  local answers = c and ns.Answers.For(c) or {}
  platesAsk = answers.ask
  holder.buttons = holder.buttons or {}
  -- the row's room: the plates that fit, in their order; the first one cut with "..." when even
  -- it is wider than the row (plan-chat-one-window.md §8: no text past its panel)
  local room = holder:GetWidth()
  if not room or room <= 0 then
    room = (holder:GetParent() and holder:GetParent():GetWidth() or 0) - ns.Front.RAIL_W - 30
  end
  local x = (holder.label:GetStringWidth() or 50) + 4 + 6
  local prev, full = holder.label, false
  for i = 1, math.max(#answers, #holder.buttons) do
    local plate = answers[i]
    local b = holder.buttons[i]
    if plate and not full then
      if not b then
        b = S.action(holder, { label = "", row = true, boxed = true })
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(self, button)
          if button == "RightButton" then
            People.PlateMenu(self)
          else
            People.UsePlate(self.plate)
          end
        end)
        holder.buttons[i] = b
      end
      b.plate = plate
      local own =
        L["Click: send it. Shift+click: put it into the line to change it first. Right click: forget it."]
      b.tip = plate.own and own or L["Click: send it. Shift+click: put it into the line to change it first."]
      b.spec.primary = (i == 1) or nil
      b.spec.width = nil
      b:SetLabel(plate.text)
      local w = b:GetWidth() or 60
      if room > 0 and x + w > room then
        if i == 1 then
          b.spec.width = math.max(40, math.floor(room - x)) -- cut, the whole text its tooltip
          b:Fit()
          w = b:GetWidth() or w
        else
          full = true
        end
      end
      if full then
        b.plate = nil
        b:Hide()
      else
        b:ClearAllPoints()
        b:SetPoint("LEFT", prev, "RIGHT", 6, 0)
        b:Show()
        prev = b
        x = x + w + 6
      end
    elseif b then
      b.plate = nil
      b:Hide()
    end
  end
  ns.Front.ShowPlates(#answers > 0)
  return #answers
end

-- The plate shown with this text, or a plate of it.
local function plateOf(textOrPlate)
  if type(textOrPlate) == "table" then
    return textOrPlate
  end
  local holder = ns.Front.PlatesFrame and ns.Front.PlatesFrame()
  for _, b in ipairs(holder and holder.buttons or {}) do
    if b:IsShown() and b.plate and b.plate.text == textOrPlate then
      return b.plate
    end
  end
  return type(textOrPlate) == "string" and { text = textOrPlate } or nil
end

-- A plate clicked: sent to the partner (an invite's plate also invites); with Shift into the line.
-- Either way it counts as used for the question it answered.
function People.UsePlate(textOrPlate)
  local key = ns.Front.ShownPerson()
  local c = key and People.Convo(key)
  local plate = plateOf(textOrPlate)
  if not c or not plate or type(plate.text) ~= "string" then
    return
  end
  ns.Answers.Used(plate, platesAsk)
  if IsShiftKeyDown() then
    if isBNet(key) then
      Compat.OpenChat(plate.text)
    else
      Compat.OpenChat("/w " .. c.name .. " " .. plate.text)
    end
    return
  end
  People.SendOne(key, plate.text)
  if plate.invites and not isBNet(key) then
    Compat.Invite(c.name)
  end
end

-- A plate's menu: the player's own line can be forgotten.
function People.PlateMenu(b)
  local plate = b.plate
  if not (plate and plate.own) then
    return nil
  end
  local items = {
    {
      label = L["Forget this answer"],
      onClick = function()
        ns.Answers.Forget(plate.text)
        People.DrawPlates()
      end,
    },
  }
  B.UI.Menu(b, L["Your line"], items, mod())
  return items
end

-- The plates shown, for tests: their texts in order.
function People.Plates()
  local out = {}
  local holder = ns.Front.PlatesFrame and ns.Front.PlatesFrame()
  for _, b in ipairs(holder and holder.buttons or {}) do
    if b:IsShown() and b.plate then
      out[#out + 1] = b.plate.text
    end
  end
  return out
end

-- ---------------------------------------------------------------------------------------------
-- How they draw (Bastians.UI.VirtualList kinds of the window's stream)
-- ---------------------------------------------------------------------------------------------

local function profile()
  return mod().db.profile
end

-- A day between two runs: the date in a pill in the middle.
local function makeDay(parent)
  local f = CreateFrame("Frame", nil, parent)
  f.pill = CreateFrame("Frame", nil, f)
  f.pill.ground = S.roundFill(f.pill, S.C.inset, "pill")
  f.pill.edges = S.roundEdges(f.pill, S.C.line, "pill")
  f.text = S.SetRole(S.text(f.pill, 10, S.C.dim), "number")
  f.text:SetPoint("CENTER", f.pill, "CENTER", 0, 0)
  return f
end

-- "2 new": a line in the colour of what needs you on both sides of the words.
local function makeNew(parent)
  local f = CreateFrame("Frame", nil, parent)
  f.text = S.SetRole(S.text(f, 10, S.C.tier0), "number")
  f.text:SetPoint("CENTER", f, "CENTER", 0, 0)
  f.left = S.fill(f, S.C.tier0, "ARTWORK")
  f.left:ClearAllPoints()
  f.left:SetPoint("LEFT", f, "LEFT", 4, 0)
  f.left:SetPoint("RIGHT", f.text, "LEFT", -8, 0)
  f.left:SetHeight(1)
  f.right = S.fill(f, S.C.tier0, "ARTWORK")
  f.right:ClearAllPoints()
  f.right:SetPoint("LEFT", f.text, "RIGHT", 8, 0)
  f.right:SetPoint("RIGHT", f, "RIGHT", -4, 0)
  f.right:SetHeight(1)
  return f
end

-- A run: a bar at its side (the whisper's colour for theirs, the accent for the player's), the
-- name and the time, the lines under it; the player's on the right unless the choice says left.
local function makeRun(parent)
  local f = CreateFrame("Button", nil, parent)
  f.tint = S.fill(f, S.C.chanWhisper, "BACKGROUND")
  f.bar = S.fill(f, S.C.chanWhisper, "BORDER")
  f.name = S.text(f, 12, S.C.text)
  f.name:SetWordWrap(false)
  f.when = S.SetRole(S.text(f, 10, S.C.dim), "number")
  f.text = f:CreateFontString(nil, "ARTWORK")
  f.text:SetWordWrap(true)
  f:RegisterForClicks("RightButtonUp")
  f:SetScript("OnClick", function(self, button)
    if button == "RightButton" and self.item then
      People.RunMenu(self.item, self)
    end
  end)
  if Compat.EnableLinks(f) then
    f:SetScript("OnHyperlinkClick", function(self, link, text, button)
      ns.View.OnLink(self, link, text, button)
    end)
    f:SetScript("OnHyperlinkEnter", function(self, link)
      if type(link) == "string" and not link:find("^player") and not link:find("^addon") then
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        pcall(GameTooltip.SetHyperlink, GameTooltip, link)
        GameTooltip:Show()
      end
    end)
    f:SetScript("OnHyperlinkLeave", function()
      GameTooltip:Hide()
    end)
  end
  return f
end

local PAD = 4
local BAR = 2

-- Lays a run out at `width`; returns its height.
local function layRun(f, item, width)
  local p = profile()
  local right = item.out and p.convoSide ~= "left"
  local token = item.out and "accent" or (item.bn and "chanBnet" or "chanWhisper")
  local maxW = math.max(60, math.floor(width * People.RUN_SHARE))
  S.tint(f.bar, S.Tok(f, token), 1)
  S.tint(f.tint, S.Tok(f, token), p.convoTint and 0.09 or 0)
  f.bar:ClearAllPoints()
  f.tint:ClearAllPoints()
  local x0 = right and (width - maxW) or 0 -- the run's left edge
  if right then
    f.bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -PAD)
    f.bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, PAD)
  else
    f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -PAD)
    f.bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 2, PAD)
  end
  f.bar:SetWidth(BAR)
  f.tint:SetPoint("TOPLEFT", f, "TOPLEFT", x0, -2)
  f.tint:SetPoint("BOTTOMRIGHT", f, "TOPLEFT", x0 + maxW, 0) -- the height follows below
  local inner = maxW - BAR - 12
  f.name:SetText(item.name or "")
  S.ink(f.name, S.Tok(f, item.out and "accent" or token))
  f.when:SetText(((Model.Stamp("hm", item.at) or ""):gsub("%s+$", "")))
  f.name:ClearAllPoints()
  f.when:ClearAllPoints()
  f.text:ClearAllPoints()
  ns.View.ApplyFont(f.text)
  f.text:SetWidth(inner)
  f.text:SetJustifyH(right and "RIGHT" or "LEFT")
  if right then
    f.when:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(BAR + 10), -PAD)
    f.name:SetPoint("RIGHT", f.when, "LEFT", -6, 0)
    f.text:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(BAR + 10), -(PAD + 16))
  else
    f.name:SetPoint("TOPLEFT", f, "TOPLEFT", BAR + 10, -PAD)
    f.when:SetPoint("LEFT", f.name, "RIGHT", 6, 0)
    f.text:SetPoint("TOPLEFT", f, "TOPLEFT", BAR + 10, -(PAD + 16))
  end
  local body = {}
  for i, text in ipairs(item.lines) do
    body[i] = ns.View.Decorate({ text = text, noStamp = true })
  end
  f.text:SetText(S.ReadableText(table.concat(body, "\n"), f)) -- readable on a light look (V25)
  -- the partner's words in the whisper's colour, the player's own in the text's (V25)
  if not item.out and ns.Rows.LookColors() then
    S.ink(f.text, S.Tok(f, token))
  else
    S.ink(f.text, S.Tok(f, "text"))
  end
  local h = math.floor(PAD + 16 + (f.text:GetStringHeight() or 14) + PAD + 2 + 0.5)
  f.tint:SetPoint("BOTTOMRIGHT", f, "TOPLEFT", x0 + maxW, -(h - 2))
  return h
end

-- A person in the People list: the face, the name and who they are, the last line, its time, the
-- unread count.
local function makePerson(parent)
  local f = CreateFrame("Button", nil, parent)
  f.hl = S.fill(f, S.C.hover, "HIGHLIGHT")
  f.rule = S.fill(f, S.C.divider, "BORDER")
  f.rule:ClearAllPoints()
  f.rule:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
  f.rule:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  f.rule:SetHeight(1)
  f.face = People.NewFace(f, People.FACE)
  f.face:SetPoint("LEFT", f, "LEFT", 6, 0)
  f.name = S.text(f, 13, S.C.text)
  f.name:SetPoint("TOPLEFT", f, "TOPLEFT", 6 + People.FACE + 10, -8)
  f.name:SetWordWrap(false)
  f.rel = S.SetRole(S.text(f, 9, S.C.dim), "number")
  f.rel:SetPoint("LEFT", f.name, "RIGHT", 6, 0)
  f.when = S.SetRole(S.text(f, 10, S.C.dim), "number")
  f.when:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -9)
  f.name:SetPoint("RIGHT", f.when, "LEFT", -60, 0)
  f.badge = CreateFrame("Frame", nil, f)
  f.badge:SetSize(22, 14)
  f.badge:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 9)
  f.badge.fill = S.roundFill(f.badge, S.C.tier0, "pill")
  f.badge.text = S.SetRole(S.text(f.badge, 10, S.C.bg), "number")
  f.badge.text:SetPoint("CENTER", 0, 0)
  f.last = S.text(f, 12, S.C.dim)
  f.last:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 6 + People.FACE + 10, 9)
  f.last:SetPoint("RIGHT", f.badge, "LEFT", -8, 0)
  f.last:SetWordWrap(false)
  f.last:SetJustifyH("LEFT")
  f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  f:SetScript("OnClick", function(self, button)
    if not self.key then
      return
    end
    if button == "RightButton" then
      People.Menu(self.key, self)
    else
      ns.Front.ShowPerson(self.key, true)
    end
  end)
  return f
end

local function stamp(t)
  if not t then
    return ""
  end
  if dayOf(t) == dayOf(time()) then
    return date("%H:%M", t)
  end
  return People.DayLabel(t)
end

local function layPerson(f, item)
  local key = item.key
  local c = People.Convo(key)
  f.key = key
  if not c then
    return 0
  end
  People.Face(f.face, key)
  f.name:SetText(Model.ShortName(c.name))
  local rel = People.Rel(key)
  f.rel:SetText(rel and string.upper(L[People.REL_WORDS[rel] or "Stranger"]) or "")
  S.ink(f.rel, rel == "gm" and S.C.tier3 or S.C.dim)
  local last = c.lines[#c.lines]
  f.last:SetText(
    last and ((last.out and (L["You"] .. ": ") or "") .. (Model.Strip(last.text) or "")) or L["No line yet"]
  )
  S.ink(f.last, item.waits and S.C.text or S.C.dim)
  f.when:SetText(last and stamp(c.last) or "")
  local n = c.unread or 0
  f.badge:SetShown(n > 0)
  f.badge.text:SetText(tostring(n))
  S.tint(f.badge.fill, rel == "gm" and S.C.tier3 or S.C.tier0)
  return People.ROW_H
end

local function makeSection(parent)
  local f = CreateFrame("Frame", nil, parent)
  f.text = S.SetRole(S.text(f, 11, S.C.muted), "label")
  f.text:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 6, 3)
  return f
end

People.KINDS = {
  day = {
    make = makeDay,
    fill = function(f, item)
      f.text:SetText(item.label or "")
      f.pill:SetSize(math.max(60, (f.text:GetStringWidth() or 40) + 20), 16)
      f.pill:ClearAllPoints()
      f.pill:SetPoint("CENTER", f, "CENTER", 0, 0)
      return 24
    end,
  },
  newdiv = {
    make = makeNew,
    fill = function(f, item)
      f.text:SetText(string.upper(L["%d new"]:format(item.n or 0)))
      return 18
    end,
  },
  run = {
    make = makeRun,
    fill = function(f, item, width)
      f.item = item
      return layRun(f, item, width)
    end,
  },
  person = {
    make = makePerson,
    fill = function(f, item)
      return layPerson(f, item)
    end,
  },
  section = {
    make = makeSection,
    fill = function(f, item)
      f.text:SetText(string.upper(item.label or ""))
      return 24
    end,
  },
}
-- one list draws every place: the stream's kinds and these
for id, kind in pairs(People.KINDS) do
  ns.Rows.KINDS[id] = kind
end
