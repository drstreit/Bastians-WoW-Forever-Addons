-- Bastian's Chat, right click everywhere and copying (plan-chat-one-window.md §5, §6, ADR 0076;
-- "utilize the right click more - for copy/paste etc", "we lost ways to
-- copy/paste the text"): the menus of a line, a name (a Battle.net friend's too, never the game's
-- menu, R16), a place of the rail, a person, the input line; a line's plain text for the copy box,
-- every line shown, and Shift+click on a line's time that puts the line into the input line. The
-- game gives addons no clipboard: copying always ends in a text box where the player presses Ctrl+C.
local _, ns = ...
local B = Bastians
local L = ns.L
local Model, Compat = ns.Model, ns.Compat

local Menus = {}
ns.Menus = Menus

Menus.ITEMS = 2 -- item links of a line offered in its menu
Menus.HISTORY = 10 -- sent lines in the input line's menu
Menus.TIME_LINK = "addon:Bastians_Chat:time:" -- a line's time as a link (Shift+click quotes it)

local function mod()
  return ns.mod
end

local function profile()
  return ns.mod.db.profile
end

local function short(name)
  return name and Model.ShortName(name) or nil
end

-- ---------------------------------------------------------------------------------------------
-- A line's plain text
-- ---------------------------------------------------------------------------------------------

-- The plain text of a shown item: its time and the line as the game wrote it (a ledger row, a run
-- of a conversation, a card's words too); nil for a secret line.
function Menus.LineText(item)
  if type(item) ~= "table" then
    return nil
  end
  if item.kind == "ledger" then
    return Model.Strip(ns.Rows.LedgerText(item))
  elseif item.kind == "run" then
    local out = {}
    for _, text in ipairs(item.lines or {}) do
      out[#out + 1] = (Model.Stamp("hm", item.at) or "")
        .. (item.name or "")
        .. ": "
        .. (Model.Strip(text) or "")
    end
    return table.concat(out, "\n")
  elseif item.kind == "dungeon" then
    local out = { item.dungeon or "" }
    for _, rec in ipairs(item.posts or {}) do
      out[#out + 1] = Menus.LineText({ kind = "rec", rec = rec })
    end
    return table.concat(out, "\n")
  elseif item.kind == "person" then
    local c = ns.People.Convo(item.key)
    local last = c and c.lines[#c.lines]
    return c and (short(c.name) .. (last and (": " .. (Model.Strip(last.text) or "")) or "")) or nil
  elseif item.kind == "day" or item.kind == "newdiv" or item.kind == "section" then
    return item.label
  end
  local rec = item.rec
  if not rec or rec.secret or type(rec.text or rec.body) ~= "string" then
    return nil
  end
  local stamp = Model.Stamp(profile().stamps ~= "off" and profile().stamps or "hm", rec.t)
  return (stamp or "") .. (Model.Strip(rec.text or rec.body) or "")
end

-- Every line shown in the window's stream, as plain text.
function Menus.ShownText()
  local box = ns.Front.Frame()
  local out = {}
  for _, item in ipairs(box and box.list.items or {}) do
    if not item.hidden then
      local text = Menus.LineText(item)
      if text and text ~= "" then
        out[#out + 1] = text
      end
    end
  end
  return table.concat(out, "\n")
end

-- Every line of a stream, as plain text (a place's "Copy all lines").
function Menus.StreamText(stream)
  local out = {}
  for _, rec in ipairs(ns.Chat.Store().lines[stream] or {}) do
    local text = Menus.LineText({ kind = "rec", rec = rec })
    if text then
      out[#out + 1] = text
    end
  end
  return table.concat(out, "\n")
end

-- ---------------------------------------------------------------------------------------------
-- Shift+click on a line's time (Prat's and Better Forever Chat's convention): the line into the
-- input line, to quote or pass on. Nothing is sent.
-- ---------------------------------------------------------------------------------------------

function Menus.TimeLink(id, stamp)
  return "|H" .. Menus.TIME_LINK .. tostring(id) .. "|h" .. stamp .. "|h"
end

function Menus.IsTimeLink(link)
  return type(link) == "string" and link:sub(1, #Menus.TIME_LINK) == Menus.TIME_LINK
end

-- The line of a record into the input line (an open bar takes it where the cursor is). Returns the
-- text it put in.
function Menus.Quote(rec)
  if not rec or rec.secret then
    return nil
  end
  local text = Model.Strip(rec.text or rec.body or "")
  if not text or text == "" then
    return nil
  end
  if not Compat.InsertLink(text) then
    Compat.OpenChat(text)
  end
  return text
end

function Menus.QuoteId(id)
  local rec = ns.Chat.Store():Get(tonumber(id))
  return Menus.Quote(rec)
end

-- ---------------------------------------------------------------------------------------------
-- The menus
-- ---------------------------------------------------------------------------------------------

local function add(items, label, fn)
  items[#items + 1] = { label = label, onClick = fn }
  return items[#items]
end

-- The channel a line answers in: "/g ", "/2 " with its name ("Trade"), nil for none.
local function answerIn(rec)
  if rec.chatType == "CHANNEL" and rec.channelNumber then
    local name = rec.channel and (rec.channel:match("^(.-)%s+%-%s+.+$") or rec.channel)
      or tostring(rec.channelNumber)
    return "/" .. rec.channelNumber .. " ", name
  end
  local slash = ns.Rows.REPLY[rec.chatType]
  if slash then
    return slash, ns.Find.ClientTypeName(rec.chatType) or rec.chatType:lower()
  end
  return nil
end

-- What a mute is kept by: the sender and the channel ("trade", "say").
function Menus.MuteKey(name, rec)
  local where = rec.channelKind or (rec.channel and rec.channel:lower()) or (rec.chatType or ""):lower()
  return string.lower(short(name) or "") .. "|" .. where
end

-- A line's menu (plan §5): copy it, all shown, select the text; answer; show only or leave out its
-- sender; mute them in this channel, block them; its items on the watch list or into the input line;
-- in Junk, Not junk.
function Menus.Line(item, anchor)
  local items = {}
  local rec = item and item.rec
  local text = Menus.LineText(item)
  if text then
    add(items, L["Copy line"], function()
      ns.View.Copy(text)
    end)
  end
  add(items, L["Copy all lines shown"], function()
    ns.View.Copy(Menus.ShownText())
  end)
  add(items, L["Select text"], function()
    ns.Front.SelectText()
  end)
  local title = text and text:sub(1, 30) or L["Line"]
  if rec and not rec.secret then
    local name = rec.who and rec.who.name
    local who = short(name)
    title = (Model.Stamp("hm", rec.t) or "") .. (who or "")
    if name and not rec.own then
      add(items, L["Whisper %s"]:format(who), function()
        Compat.OpenChat("/w " .. name .. " ")
      end)
    end
    local slash, channel = answerIn(rec)
    if slash then
      add(items, L["Answer in %s"]:format(channel), function()
        Compat.OpenChat(slash)
      end)
    end
    if who and not rec.own then
      add(items, L["Show only %s"]:format(who), function()
        ns.Front.SetFilter(who)
      end)
      add(items, L["Leave out %s"]:format(who), function()
        local q = ns.Front.Query()
        ns.Front.SetFilter(((q and (q .. " ")) or "") .. "-" .. who)
      end)
      local public = rec.chatType == "CHANNEL" or rec.chatType == "SAY" or rec.chatType == "YELL"
      if public then
        local where = rec.channel and (rec.channel:match("^(.-)%s+%-%s+.+$") or rec.channel)
          or ns.Find.ClientTypeName(rec.chatType)
          or ""
        add(items, L["Mute %s in %s"]:format(who, where), function()
          ns.Chat.Mute(name, rec)
        end)
      end
      add(items, L["Block in Bastian's Chat"], function()
        ns.Chat.BlockSender(name)
      end)
    end
    local n = 0
    for _, link in ipairs(rec.links or {}) do
      if link.kind == "item" and link.id and n < Menus.ITEMS then
        n = n + 1
        local full = ns.Rows.ItemLink(rec.body, link.id) or ("[" .. tostring(link.text) .. "]")
        local watched = profile().watch and profile().watch.items and profile().watch.items[link.id]
        add(
          items,
          (watched and L["Stop watching %s"] or L["Watch %s"]):format("[" .. tostring(link.text) .. "]"),
          function()
            ns.Chat.ToggleWatch("item", link.id, full)
          end
        )
        add(items, L["Put %s into the input line"]:format("[" .. tostring(link.text) .. "]"), function()
          if not Compat.InsertLink(full) then
            Compat.OpenChat(full)
          end
        end)
      end
    end
    if rec.stream == "junk" then
      add(items, L["Not junk"], function()
        Menus.NotJunk(rec)
      end)
    end
  end
  B.UI.Menu(anchor, title, items, mod())
  return items
end

-- A junk record back where it belonged: its line in Junk's ring, by its text and time.
function Menus.NotJunk(rec)
  local ring = ns.Junk.Lines()
  for i = #ring, 1, -1 do
    local line = ring[i].line
    if line and line.text == rec.text and (line.at or 0) == (rec.t or 0) then
      ns.Junk.NotJunk(i)
      return true
    end
  end
  return false
end

-- A stream's notification (Parley's per-place choice): every line, only the player's name,
-- nothing; nil keeps the sound of the chat's page.
Menus.NOTIFY =
  { { "all", "Notify: every line" }, { "name", "Notify: only my name" }, { "none", "Notify: nothing" } }

-- A place's menu on the rail (plan §5): show it alone, in or out of All, its notification and
-- sound, copy its lines, clear it.
function Menus.Place(id, anchor)
  local s = ns.Inbox.Settings()
  local items = {}
  add(items, L["Show alone"], function()
    ns.Front.Solo(id)
  end)
  add(items, s.off[id] and L["Put back into All"] or L["Take out of All"], function()
    ns.Front.ToggleInMix(id)
  end)
  if ns.Front.Detach then
    add(items, L["Window of its own"], function()
      ns.Front.Detach(id)
    end)
  end
  s.notify = type(s.notify) == "table" and s.notify or {}
  for _, pair in ipairs(Menus.NOTIFY) do
    add(items, L[pair[2]] .. (s.notify[id] == pair[1] and "  *" or ""), function()
      s.notify[id] = pair[1]
    end)
  end
  local p = profile()
  local choices = Compat.SoundChoices()
  local current = p.sounds and p.sounds.streams and p.sounds.streams[id] or "none"
  for _, sid in ipairs({ "none", "whisper", "bell", "chime" }) do
    if choices[sid] then
      add(items, L["Sound: %s"]:format(choices[sid]) .. (current == sid and "  *" or ""), function()
        p.sounds = type(p.sounds) == "table" and p.sounds or {}
        p.sounds.streams = type(p.sounds.streams) == "table" and p.sounds.streams or {}
        p.sounds.streams[id] = sid
        Compat.PlaySound(sid)
      end)
    end
  end
  add(items, L["Copy all lines"], function()
    ns.View.Copy(Menus.StreamText(id))
  end)
  add(items, L["Clear"], function()
    ns.Chat.Store():Clear(id)
    ns.Front.Rebuild()
  end)
  B.UI.Menu(anchor, L[ns.Find.STREAM_LABELS[id] or id], items, mod())
  return items
end

-- The menu of a Battle.net friend's name in a line (R16): Chat's, never the game's (whose "Move
-- to New Window" opened a game window Chat keeps hidden).
function Menus.BNetName(name, bnID, anchor)
  local items = {}
  local key = bnID and ("bn:" .. tostring(bnID)) or nil
  if key and ns.People.Convo(key) then
    add(items, L["Open the conversation"], function()
      ns.Front.ShowPerson(key, true)
    end)
  end
  add(items, L["Whisper"], function()
    Compat.OpenBNetChat(name)
  end)
  add(items, L["Copy name"], function()
    ns.View.Copy(name)
  end)
  B.UI.Menu(anchor, name or L["Battle.net friend"], items, mod())
  return items
end

-- The input line's menu (plan §5): the last ten lines sent (a click puts one in, also in a fight,
-- where Up may belong to the game; never a secure command), the player's place and item level,
-- Clear.
function Menus.Input(bar)
  local items = {}
  local walk = ns.Keys.Walkable(mod().db.char.history or {}, Compat.SecureCmdCheck()) or {}
  for i = #walk, math.max(1, #walk - Menus.HISTORY + 1), -1 do
    local line = walk[i]
    add(items, line, function()
      bar:SetText(line)
      bar:SetFocus()
    end)
  end
  local zone, sub, x, y = Compat.Where()
  if zone then
    local where = zone .. (sub and (", " .. sub) or "") .. (x and string.format(" (%d, %d)", x, y) or "")
    add(items, L["Insert my location"], function()
      bar:Insert(where)
    end)
  end
  local ilvl = Compat.ItemLevel()
  if ilvl then
    add(items, L["Insert my item level"], function()
      bar:Insert(L["item level %d"]:format(math.floor(ilvl + 0.5)))
    end)
  end
  add(items, L["Clear"], function()
    bar:SetText("")
  end)
  B.UI.Menu(bar, L["Input line"], items, mod())
  return items
end
