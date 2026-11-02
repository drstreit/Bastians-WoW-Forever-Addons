-- Bastian's Chat, the Messenger (chat.md "The Messenger"): whispers as conversations in a window of
-- the WhatsApp kind, the people on the left (their class, the last line, unread), the whole
-- conversation with that one person on the right as bubbles under a header that says what the
-- client knows about them, its own input line with Send; the history account-wide, Battle.net
-- conversations for the session only.
local _, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
local L = ns.L
local S = B.UI.Style
local Model, Compat = ns.Model, ns.Compat

local Messenger = {}
ns.Messenger = Messenger

Messenger.LIST_W = 230
Messenger.ROW_H = 46
Messenger.HEAD_H = 50
Messenger.ICON = 32
Messenger.RENDER = 150 -- bubbles drawn per conversation; the older lines are in Copy
Messenger.SHARE = 0.72 -- a bubble's widest share of the view
Messenger.PAD = 8
Messenger.INFO_AGE = 60 -- seconds a partner's info is kept before the client is asked again
Messenger.CLASS_CIRCLES = "Interface\\TargetingFrame\\UI-Classes-Circles"
Messenger.NO_PORTRAIT = "Interface\\CharacterFrame\\TempPortrait"

local win, list, listSearch, newButton, nameBox, rowsArea
local header, view, child, input, hint, note, moreButton, sendButton, inviteButton, searchButton
local convoSearch, searchRow, emptyTitle, emptyText, moreNote
local rows, bubbles, dividers = {}, {}, {}
local selected
local session = {} -- the Battle.net conversations of this session (never stored)
local parts -- { list, next, key } of a long text being sent
local offset = 0 -- the list's first row
local listQ, convoQ -- the list's search and the conversation's filter (ADR 0045)
local hay = setmetatable({}, { __mode = "k" }) -- [convo] = { n, text }: the list's search text

local function mod()
  return ns.mod
end

local function settings()
  return mod().db.profile.messenger
end

local function stored()
  return mod().db.global.convos
end

local function isBNet(key)
  return type(key) == "string" and key:sub(1, 3) == "bn:"
end

function Messenger.Convo(key)
  if isBNet(key) then
    return session[key]
  end
  return key and stored()[key] or nil
end

local function all()
  local t = {}
  for k, v in pairs(stored()) do
    t[k] = v
  end
  for k, v in pairs(session) do
    t[k] = v
  end
  return t
end

function Messenger.Selected()
  return selected
end

function Messenger.Unread()
  local n = 0
  for _, c in pairs(all()) do
    n = n + (c.unread or 0)
  end
  return n
end

-- The conversations with unread lines, newest first (the feed's tooltip).
function Messenger.UnreadConvos()
  local convos, out = all(), {}
  for _, key in ipairs(Model.ConvoOrder(convos)) do
    if (convos[key].unread or 0) > 0 then
      out[#out + 1] = convos[key]
    end
  end
  return out
end

-- Every conversation read (the feed's right click).
function Messenger.MarkAllRead()
  for _, c in pairs(all()) do
    c.unread = 0
  end
  Messenger.Refresh()
end

local function shown()
  return win ~= nil and win:IsShown()
end

-- ---------------------------------------------------------------------------------------------
-- The partner: what the client knows (Compat.PartnerInfo), kept with the conversation so an
-- offline partner keeps the class of their last visit
-- ---------------------------------------------------------------------------------------------

function Messenger.Info(key, fresh)
  local c = Messenger.Convo(key)
  if not c then
    return nil
  end
  local info = c.info
  if fresh or not info or (time() - (info.at or 0)) > Messenger.INFO_AGE then
    local got = Compat.PartnerInfo(c.name, isBNet(key) and c.bnID or nil)
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
function Messenger.InfoLine(info)
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

local function paintClass(tex, class)
  local coords = class and rawget(_G, "CLASS_ICON_TCOORDS")
  coords = coords and coords[class]
  if coords then
    tex:SetTexture(Messenger.CLASS_CIRCLES)
    tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
  else
    tex:SetTexture(Messenger.NO_PORTRAIT)
    tex:SetTexCoord(0, 1, 0, 1)
  end
end

local function paintOnline(dot, info)
  if not info or info.online == nil then
    dot:Hide()
    return
  end
  S.tint(dot.tex, info.online and S.C.accent or S.C.muted)
  dot:Show()
end

-- ---------------------------------------------------------------------------------------------
-- Lines in
-- ---------------------------------------------------------------------------------------------

local OUT = { WHISPER_INFORM = true, BN_WHISPER_INFORM = true }
local AWAY = { AFK = "away", DND = "busy" }

-- A whisper line (chat.md): into its conversation; an incoming one counts as unread unless the
-- conversation is open in front of the player.
function Messenger.Add(line)
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
  end
  if out or (shown() and selected == key) then
    c.unread = 0
  end
  if not out then
    if settings().open and not shown() and not InCombatLockdown() then -- in combat: only counted
      Messenger.Show(key)
    elseif not selected then
      selected = key
    end
    if settings().sound and settings().sound ~= "none" then
      Compat.PlaySound(settings().sound)
    end
  elseif not selected then
    selected = key
  end
  Messenger.Refresh()
  return c
end

-- A conversation opened by the player (the list's "+", a name): empty until somebody writes.
function Messenger.Open(name)
  name = strtrim(name or "")
  if name == "" then
    return nil
  end
  Model.ConvoOpen(stored(), name, name, time())
  Messenger.Show(name)
  if input then
    input:SetFocus()
  end
  return name
end

-- ---------------------------------------------------------------------------------------------
-- Sending
-- ---------------------------------------------------------------------------------------------

local function sendOne(key, text)
  local c = Messenger.Convo(key)
  if not c then
    return false
  end
  if isBNet(key) then
    return Compat.SendBNet(c.bnID, text)
  end
  return Compat.SendChat(text, "WHISPER", c.name)
end

local function noteParts()
  if parts then
    note:SetText(
      string.format(L["Long text: Enter sends part %d of %d, Escape stops"], parts.next, #parts.list)
    )
    note:Show()
  else
    note:Hide()
  end
end

-- Enter in the input line (or Send): the text to the partner; a text over 255 bytes in parts, one
-- per Enter (the line shows the next part). Battle.net whispers are not split.
function Messenger.Send()
  if not (selected and Messenger.Convo(selected)) then
    input:ClearFocus()
    return
  end
  if parts and parts.key == selected then
    sendOne(selected, parts.list[parts.next])
    parts.next = parts.next + 1
    if parts.next > #parts.list then
      parts = nil
      input:SetText("")
    else
      input:SetText(parts.list[parts.next])
    end
    noteParts()
    return
  end
  parts = nil
  local text = input:GetText() or ""
  if not text:find("%S") then
    input:ClearFocus()
    return
  end
  if #text > Model.PART_BYTES and not isBNet(selected) then
    local pieces = Model.Split(text)
    sendOne(selected, pieces[1])
    parts = { list = pieces, next = 2, key = selected }
    input:SetText(pieces[2])
    noteParts()
    return
  end
  sendOne(selected, text)
  input:SetText("")
end

-- ---------------------------------------------------------------------------------------------
-- Menus and actions
-- ---------------------------------------------------------------------------------------------

local function stamp(t)
  if not t then
    return ""
  end
  if date("%Y-%m-%d", t) == date("%Y-%m-%d") then
    return date("%H:%M", t)
  end
  return date("%d.%m.", t)
end

function Messenger.ConvoMenu(key, anchor)
  local c = Messenger.Convo(key)
  if not c then
    return nil
  end
  local items = {}
  if not isBNet(key) then
    items[#items + 1] = {
      label = L["Whisper in the chat bar"],
      onClick = function()
        Compat.OpenChat("/w " .. c.name .. " ")
      end,
    }
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
      Messenger.CopyConvo(key)
    end,
  }
  items[#items + 1] = {
    label = L["Delete conversation"],
    onClick = function()
      Messenger.Delete(key)
    end,
  }
  B.UI.Menu(anchor, Model.ShortName(c.name), items, mod())
  return items
end

-- The "+" of the list: a name to type, and the friends online to pick.
function Messenger.NewMenu(anchor)
  local items = {
    {
      label = L["Type a name..."],
      onClick = function()
        Messenger.ShowNameBox(true)
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
          Messenger.Open(f.name)
        end,
      }
    end
  end
  B.UI.Menu(anchor, L["New conversation"], items, mod())
  return items
end

function Messenger.ShowNameBox(on)
  if not nameBox then
    return
  end
  nameBox:SetShown(on)
  rowsArea:ClearAllPoints()
  rowsArea:SetPoint("TOPLEFT", on and nameBox or listSearch, "BOTTOMLEFT", 0, -4)
  rowsArea:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -2, 2)
  if on then
    nameBox:SetText("")
    nameBox:SetFocus()
  end
  Messenger.RefreshList()
end

function Messenger.Delete(key)
  if isBNet(key) then
    session[key] = nil
  else
    stored()[key] = nil
  end
  if selected == key then
    selected = Model.ConvoOrder(all())[1]
  end
  Messenger.Refresh()
end

-- The conversation as plain text into the copy box.
function Messenger.CopyConvo(key)
  local c = Messenger.Convo(key or selected)
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
  return ns.View.Copy(table.concat(out, "\n"))
end

-- ---------------------------------------------------------------------------------------------
-- The list of people
-- ---------------------------------------------------------------------------------------------

-- The text the list's search reads: the partner's name and every line of the conversation.
local function hayOf(c)
  local h = hay[c]
  if not h or h.n ~= #c.lines then
    local out = { string.lower(Model.ShortName(c.name)), string.lower(c.name or "") }
    for _, l in ipairs(c.lines) do
      out[#out + 1] = string.lower(Model.Strip(l.text) or "")
    end
    h = { n = #c.lines, text = table.concat(out, "\n") }
    hay[c] = h
  end
  return h.text
end

-- The search box over the list: the conversations whose partner or lines hold the text.
function Messenger.SetSearch(text)
  local q = B.Query.Compile(text or "")
  listQ = not q.empty and q or nil
  offset = 0
  Messenger.RefreshList()
end

-- The keys the list shows, the newest first, narrowed by the search.
function Messenger.Keys()
  local t = all()
  local keys = Model.ConvoOrder(t)
  if listQ then
    local kept = {}
    for _, key in ipairs(keys) do
      if listQ:MatchLower(hayOf(t[key]), t[key]) then
        kept[#kept + 1] = key
      end
    end
    keys = kept
  end
  return keys, t
end

local function row(i)
  local r = rows[i]
  if r then
    return r
  end
  r = CreateFrame("Button", nil, rowsArea)
  r:SetHeight(Messenger.ROW_H)
  r.sel = S.fill(r, S.C.accent, "BACKGROUND")
  S.tint(r.sel, S.C.accent, 0.25)
  r.sel:Hide()
  r.hl = S.fill(r, S.C.hover, "ARTWORK")
  r.hl:Hide()
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(Messenger.ICON, Messenger.ICON)
  r.icon:SetPoint("LEFT", 6, 0)
  r.dot = CreateFrame("Frame", nil, r)
  r.dot:SetSize(8, 8)
  r.dot:SetPoint("BOTTOMRIGHT", r.icon, "BOTTOMRIGHT", 1, -1)
  r.dot.tex = S.fill(r.dot, S.C.accent, "OVERLAY")
  r.dot:Hide()
  r.name = S.text(r, 12, S.C.text)
  r.name:SetPoint("TOPLEFT", 6 + Messenger.ICON + 8, -7)
  r.name:SetPoint("RIGHT", -44, 0)
  r.name:SetWordWrap(false)
  r.time = S.text(r, 10, S.C.dim)
  r.time:SetPoint("TOPRIGHT", -6, -8)
  r.last = S.text(r, 11, S.C.dim)
  r.last:SetPoint("BOTTOMLEFT", 6 + Messenger.ICON + 8, 8)
  r.last:SetPoint("RIGHT", -30, 0)
  r.last:SetWordWrap(false)
  r.badge = CreateFrame("Frame", nil, r)
  r.badge:SetSize(22, 14)
  r.badge:SetPoint("BOTTOMRIGHT", -6, 7)
  r.badge.bg = S.fill(r.badge, S.C.accent)
  r.badge.text = S.text(r.badge, 10, S.C.headerText)
  r.badge.text:SetPoint("CENTER")
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
      Messenger.ConvoMenu(self.key)
    else
      Messenger.Select(self.key)
    end
  end)
  r:SetScript("OnEnter", function(self)
    self.hl:Show()
    local info = self.key and Messenger.Convo(self.key) and Messenger.Convo(self.key).info
    local line = Messenger.InfoLine(info)
    if line ~= "" and GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      S.TipLine(GameTooltip, self.name:GetText() or "", "tipText")
      S.TipLine(GameTooltip, line, "tipDim", true)
      GameTooltip:Show()
    end
  end)
  r:SetScript("OnLeave", function(self)
    self.hl:Hide()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  rows[i] = r
  return r
end

-- the unread count or the people behind it changed (the feed of the broker displays reads it)
B:DeclareMessage("BASTIANS_CHAT_UNREAD")
local unreadSig = ""

function Messenger.RefreshList()
  ns.View.MessengerCount(Messenger.Unread())
  local sig = ""
  for _, c in ipairs(Messenger.UnreadConvos()) do
    sig = sig .. (c.name or "") .. "=" .. c.unread .. ";"
  end
  if sig ~= unreadSig then
    unreadSig = sig
    B:Fire("BASTIANS_CHAT_UNREAD", Messenger.Unread())
  end
  if not win then
    return
  end
  local keys, t = Messenger.Keys()
  local fit = math.max(1, math.floor(((rowsArea:GetHeight() or 300) - 4) / Messenger.ROW_H))
  offset = math.max(0, math.min(offset, #keys - fit))
  for i = 1, fit do
    local key = keys[i + offset]
    local r = row(i)
    if key then
      local c = t[key]
      r.key = key
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", rowsArea, "TOPLEFT", 2, -2 - (i - 1) * Messenger.ROW_H)
      r:SetPoint("RIGHT", rowsArea, "RIGHT", -2, 0)
      r.name:SetText(Model.ShortName(c.name))
      local last = c.lines[#c.lines]
      r.last:SetText(
        last and ((last.out and (L["You"] .. ": ") or "") .. Model.Strip(last.text)) or L["No line yet"]
      )
      r.time:SetText(last and stamp(c.last) or "")
      r.badge:SetShown((c.unread or 0) > 0)
      r.badge.text:SetText(tostring(c.unread or 0))
      r.sel:SetShown(key == selected)
      local info = Messenger.Info(key)
      paintClass(r.icon, info and info.class)
      paintOnline(r.dot, info)
      r:Show()
    else
      r.key = nil
      r:Hide()
    end
  end
  for i = fit + 1, #rows do
    rows[i]:Hide()
  end
  if listSearch and listSearch.count then
    listSearch.count:SetText(listQ and tostring(#keys) or "")
  end
end

-- ---------------------------------------------------------------------------------------------
-- The conversation
-- ---------------------------------------------------------------------------------------------

local function bubble(i)
  local b = bubbles[i]
  if b then
    return b
  end
  b = CreateFrame("Frame", nil, child)
  b.bg = S.roundFill(b, S.C.panel, "radiusSmall")
  b.text = S.text(b, 12, S.C.text)
  b.text:SetPoint("TOPLEFT", Messenger.PAD, -Messenger.PAD + 2)
  b.text:SetJustifyH("LEFT")
  b.text:SetWordWrap(true)
  b.time = S.text(b, 9, S.C.dim)
  b.time:SetPoint("BOTTOMRIGHT", -6, 3)
  if Compat.EnableLinks(b) then
    b:SetScript("OnHyperlinkClick", function(self, link, text, button)
      ns.View.OnLink(self, link, text, button)
    end)
  end
  bubbles[i] = b
  return b
end

local function atBottom()
  local range = view:GetVerticalScrollRange() or 0
  return (view:GetVerticalScroll() or 0) >= range - 4
end

local function toBottom()
  view:SetVerticalScroll(view:GetVerticalScrollRange() or 0)
  moreNote:Hide()
  C_Timer.After(0, function()
    view:SetVerticalScroll(view:GetVerticalScrollRange() or 0) -- the range follows a frame later
  end)
end

-- The filter over the shown conversation (the header's Search): only the lines that match.
function Messenger.SetFilter(text)
  local q = B.Query.Compile(text or "")
  convoQ = not q.empty and q or nil
  Messenger.RefreshView(true)
end

function Messenger.ToggleSearch(on)
  if not searchRow then
    return
  end
  if on == nil then
    on = not searchRow:IsShown()
  end
  searchRow:SetShown(on)
  view:ClearAllPoints()
  view:SetPoint("TOPLEFT", on and searchRow or header, "BOTTOMLEFT", 0, -4)
  view:SetPoint("BOTTOMRIGHT", input, "TOPRIGHT", 0, 6)
  if on then
    convoSearch:SetFocus()
  else
    convoSearch:SetText("")
    Messenger.SetFilter("")
  end
end

-- The lines to draw: those that pass the filter, the last RENDER of them.
function Messenger.Lines(c)
  local out = {}
  for _, l in ipairs(c and c.lines or {}) do
    if not convoQ or convoQ:Match(Model.Strip(l.text) or "") then
      out[#out + 1] = l
    end
  end
  while #out > Messenger.RENDER do
    table.remove(out, 1)
  end
  return out
end

function Messenger.RefreshView(forceBottom)
  if not win then
    return
  end
  local c = selected and Messenger.Convo(selected)
  local info = c and Messenger.Info(selected) or nil
  header.name:SetText(c and Model.ShortName(c.name) or L["No conversation yet"])
  header.sub:SetText(c and Messenger.InfoLine(info) or L["Press + for a new one, or whisper someone."])
  paintClass(header.icon, info and info.class)
  paintOnline(header.dot, info)
  inviteButton:SetShown(c ~= nil and not isBNet(selected))
  searchButton:SetShown(c ~= nil)
  moreButton:SetShown(c ~= nil)
  sendButton:SetEnabledFlat(c ~= nil)
  hint:SetText(c and string.format(L["Write to %s"], Model.ShortName(c.name)) or "")
  local width = math.max(200, (view:GetWidth() or 400) - 4)
  child:SetWidth(width)
  local maxText = math.floor(width * Messenger.SHARE) - 2 * Messenger.PAD
  local wasBottom = forceBottom or atBottom()
  local y, nb, nd, lastDay = -6, 0, 0, nil
  local lines = Messenger.Lines(c)
  for _, l in ipairs(lines) do
    local day = date("%Y-%m-%d", l.at)
    if day ~= lastDay then
      lastDay = day
      nd = nd + 1
      local d = dividers[nd]
      if not d then
        d = S.text(child, 10, S.C.dim)
        dividers[nd] = d
      end
      d:ClearAllPoints()
      d:SetPoint("TOP", child, "TOP", 0, y)
      d:SetText(date("%d.%m.%Y", l.at))
      d:Show()
      y = y - 18
    end
    nb = nb + 1
    local b = bubble(nb)
    ns.View.ApplyFont(b.text)
    b.text:SetWidth(maxText)
    b.text:SetText(l.text)
    local ok, wide = pcall(function()
      return b.text:GetUnboundedStringWidth() -- the retail family; older clients: the bound width
    end)
    if not ok then
      wide = b.text:GetStringWidth()
    end
    local textW = math.max(40, math.min(maxText, math.ceil(tonumber(wide) or maxText)))
    b.text:SetWidth(textW)
    local h = math.ceil(b.text:GetStringHeight() or 14) + 2 * Messenger.PAD + 8
    b:SetSize(textW + 2 * Messenger.PAD, h)
    b:ClearAllPoints()
    if l.out then
      b:SetPoint("TOPRIGHT", child, "TOPRIGHT", -6, y)
      S.tint(b.bg, S.C.accent, 0.35)
    else
      b:SetPoint("TOPLEFT", child, "TOPLEFT", 6, y)
      S.tint(b.bg, S.C.panel, 0.95)
    end
    b.time:SetText(date("%H:%M", l.at))
    b:Show()
    y = y - h - 6
  end
  for i = nb + 1, #bubbles do
    bubbles[i]:Hide()
  end
  for i = nd + 1, #dividers do
    dividers[i]:Hide()
  end
  child:SetHeight(math.max(10, -y))
  -- nothing to show: the WhatsApp-like invitation in the middle
  local empty = nb == 0
  emptyTitle:SetShown(empty)
  emptyText:SetShown(empty)
  if empty then
    if convoQ then
      emptyTitle:SetText(L["No line matches"])
      emptyText:SetText("")
    elseif c then
      emptyTitle:SetText(L["Start the conversation"])
      emptyText:SetText(string.format(L["Say hi to %s."], Model.ShortName(c.name)))
    else
      emptyTitle:SetText(L["No conversation yet"])
      emptyText:SetText(L["Press + for a new one, or whisper someone."])
    end
  end
  if convoSearch and convoSearch.count then
    convoSearch.count:SetText(convoQ and tostring(#lines) or "")
  end
  if wasBottom then
    toBottom()
  else
    moreNote:Show()
  end
end

function Messenger.Refresh(forceBottom)
  Messenger.RefreshList()
  Messenger.RefreshView(forceBottom)
end

-- ---------------------------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------------------------

local function build()
  local p = settings()
  win = B.UI.Window("BastiansChatMessenger", {
    module = "Chat",
    title = L["Messenger"],
    width = 720,
    height = 460,
    minWidth = 560,
    minHeight = 320,
    lockable = true,
    db = p.window,
    onShow = function(w)
      w.frame:SetFrameStrata("MEDIUM") -- a chat window: under the game's panels and the suite's
    end,
    onResize = function()
      Messenger.Refresh()
    end,
  })
  local c = win.content

  -- the people, left: the search, "+", the rows
  list = CreateFrame("Frame", nil, c)
  list:SetPoint("TOPLEFT", 4, -4)
  list:SetPoint("BOTTOMLEFT", 4, 4)
  list:SetWidth(Messenger.LIST_W)
  list.bg = S.fill(list, S.C.panel)
  newButton = S.action(list, { icon = "plus", label = L["New"], primary = true, row = true })
  newButton:SetPoint("TOPRIGHT", -4, -4)
  newButton.tip = L["New conversation: a name, or a friend online"]
  newButton:SetScript("OnClick", function(self)
    Messenger.NewMenu(self)
  end)
  listSearch = S.search(list, L["Search conversations"])
  listSearch:SetPoint("TOPLEFT", 4, -4)
  listSearch:SetPoint("RIGHT", newButton, "LEFT", -4, 0)
  listSearch.count = S.text(listSearch, 10, S.C.muted)
  listSearch.count:SetPoint("RIGHT", listSearch.clear, "LEFT", -2, 0)
  listSearch:SetScript("OnTextChanged", function(self)
    local text = self:GetText() or ""
    self.hint:SetShown(text == "")
    self.clear:SetShown(text ~= "")
    Messenger.SetSearch(text)
  end)
  nameBox = S.search(list, L["A name, then Enter"], true)
  nameBox:SetPoint("TOPLEFT", listSearch, "BOTTOMLEFT", 0, -4)
  nameBox:SetPoint("TOPRIGHT", newButton, "BOTTOMRIGHT", 0, -4)
  nameBox:SetScript("OnTextChanged", function(self)
    local text = self:GetText() or ""
    self.hint:SetShown(text == "")
    self.clear:SetShown(text ~= "")
  end)
  nameBox:SetScript("OnEnterPressed", function(self)
    local name = self:GetText() or ""
    Messenger.ShowNameBox(false)
    Messenger.Open(name)
  end)
  nameBox:SetScript("OnEscapePressed", function()
    Messenger.ShowNameBox(false)
  end)
  nameBox:Hide()
  rowsArea = CreateFrame("Frame", nil, list)
  rowsArea:SetPoint("TOPLEFT", listSearch, "BOTTOMLEFT", 0, -4)
  rowsArea:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -2, 2)
  rowsArea:EnableMouseWheel(true)
  rowsArea:SetScript("OnMouseWheel", function(_, delta)
    offset = math.max(0, offset - delta)
    Messenger.RefreshList()
  end)

  -- the header, right: who it is and what the client knows, the actions
  header = CreateFrame("Frame", nil, c)
  header:SetPoint("TOPLEFT", list, "TOPRIGHT", 6, -4)
  header:SetPoint("TOPRIGHT", c, "TOPRIGHT", -4, -4)
  header:SetHeight(Messenger.HEAD_H)
  header.bg = S.fill(header, S.C.panel)
  header.icon = header:CreateTexture(nil, "ARTWORK")
  header.icon:SetSize(Messenger.ICON + 4, Messenger.ICON + 4)
  header.icon:SetPoint("LEFT", 8, 0)
  header.dot = CreateFrame("Frame", nil, header)
  header.dot:SetSize(9, 9)
  header.dot:SetPoint("BOTTOMRIGHT", header.icon, "BOTTOMRIGHT", 1, -1)
  header.dot.tex = S.fill(header.dot, S.C.accent, "OVERLAY")
  header.dot:Hide()
  moreButton = S.action(header, { icon = "more", label = L["More"], only = true, row = true })
  moreButton:SetPoint("RIGHT", -6, 0)
  moreButton.tip = L["More: whisper in the chat bar, add friend, copy, delete"]
  moreButton:SetScript("OnClick", function(self)
    Messenger.ConvoMenu(selected, self)
  end)
  searchButton = S.action(header, { icon = "search", label = L["Search"], boxed = true, row = true })
  searchButton:SetPoint("RIGHT", moreButton, "LEFT", -4, 0)
  searchButton.tip = L["Only the lines of this conversation that match a search"]
  searchButton:SetScript("OnClick", function()
    Messenger.ToggleSearch()
  end)
  inviteButton = S.action(header, { icon = "invite", label = L["Invite"], boxed = true, row = true })
  inviteButton:SetPoint("RIGHT", searchButton, "LEFT", -4, 0)
  inviteButton:SetScript("OnClick", function()
    local conv = Messenger.Convo(selected)
    if conv then
      Compat.Invite(conv.name)
    end
  end)
  header.name = S.heading(header, 14, 16, S.C.headerText)
  header.name:SetPoint("TOPLEFT", 8 + Messenger.ICON + 12, -9)
  header.name:SetPoint("RIGHT", inviteButton, "LEFT", -8, 0)
  header.name:SetWordWrap(false)
  header.sub = S.text(header, 11, S.C.dim)
  header.sub:SetPoint("BOTTOMLEFT", 8 + Messenger.ICON + 12, 9)
  header.sub:SetPoint("RIGHT", inviteButton, "LEFT", -8, 0)
  header.sub:SetWordWrap(false)

  -- the search over the conversation, under the header when wanted
  searchRow = CreateFrame("Frame", nil, c)
  searchRow:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
  searchRow:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -4)
  searchRow:SetHeight(24)
  searchRow:Hide()
  convoSearch = S.search(searchRow, L["Search in the conversation"])
  convoSearch:SetPoint("LEFT", 0, 0)
  convoSearch:SetPoint("RIGHT", 0, 0)
  convoSearch.count = S.text(convoSearch, 10, S.C.muted)
  convoSearch.count:SetPoint("RIGHT", convoSearch.clear, "LEFT", -2, 0)
  convoSearch:SetScript("OnTextChanged", function(self)
    local text = self:GetText() or ""
    self.hint:SetShown(text == "")
    self.clear:SetShown(text ~= "")
    Messenger.SetFilter(text)
  end)
  convoSearch:SetScript("OnEscapePressed", function()
    Messenger.ToggleSearch(false)
  end)

  -- the input line with Send, bottom right
  sendButton = S.action(c, { icon = "send", label = L["Send"], primary = true })
  sendButton:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -6, 4)
  sendButton:SetScript("OnClick", function()
    Messenger.Send()
  end)
  input = CreateFrame("EditBox", nil, c)
  input:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 6, 4)
  input:SetPoint("BOTTOMRIGHT", sendButton, "BOTTOMLEFT", -4, 0)
  input:SetHeight(24)
  input:SetFontObject(Compat.ChatFont())
  input:SetAutoFocus(false)
  input:SetMaxLetters(0)
  pcall(function()
    input:SetTextInsets(6, 6, 0, 0)
  end)
  S.ink(input, S.C.text)
  local ig = input:CreateTexture(nil, "BACKGROUND")
  ig:SetTexture(ns.View.GROUND, true, true)
  ig:SetAllPoints()
  hint = S.text(input, 12, S.C.dim)
  hint:SetPoint("LEFT", 8, 0)
  input:SetScript("OnEnterPressed", Messenger.Send)
  input:SetScript("OnEscapePressed", function(self)
    parts = nil
    noteParts()
    self:ClearFocus()
  end)
  input:SetScript("OnTextChanged", function(self)
    hint:SetShown((self:GetText() or "") == "")
  end)
  -- the text keys (ADR 0045): the Windows keys, the readline set with the chat's setting
  S.EditKeys(input, ns.Chat.keyOpts)
  note = S.text(c, 11, S.C.tipDim)
  note:SetPoint("BOTTOMLEFT", input, "TOPLEFT", 2, 4)
  note:Hide()

  -- the conversation between the header and the input
  view = CreateFrame("ScrollFrame", nil, c)
  view:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
  view:SetPoint("BOTTOMRIGHT", input, "TOPRIGHT", 0, 6)
  local ground = view:CreateTexture(nil, "BACKGROUND")
  ground:SetTexture(ns.View.GROUND, true, true)
  ground:SetAllPoints()
  ground:SetAlpha(0.6)
  child = CreateFrame("Frame", nil, view)
  child:SetSize(300, 10)
  view:SetScrollChild(child)
  view:EnableMouseWheel(true)
  view:SetScript("OnMouseWheel", function(self, delta)
    local v = (self:GetVerticalScroll() or 0) - delta * 40
    self:SetVerticalScroll(math.max(0, math.min(v, self:GetVerticalScrollRange() or 0)))
    if atBottom() then
      moreNote:Hide()
    end
  end)
  emptyTitle = S.heading(c, 15, 17, S.C.text)
  emptyTitle:SetPoint("CENTER", view, "CENTER", 0, 12)
  emptyText = S.text(c, 12, S.C.dim)
  emptyText:SetPoint("TOP", emptyTitle, "BOTTOM", 0, -6)
  emptyTitle:Hide()
  emptyText:Hide()
  moreNote = S.button(c, L["New lines below"], 130, 18, true)
  moreNote:SetPoint("BOTTOM", view, "BOTTOM", 0, 6)
  moreNote:SetScript("OnClick", toBottom)
  moreNote:Hide()
  return win
end

function Messenger.Select(key)
  selected = key
  local c = Messenger.Convo(key)
  if c then
    c.unread = 0
  end
  parts = nil
  if win then
    noteParts()
    if convoQ then
      Messenger.ToggleSearch(false) -- the filter belonged to the other conversation
    end
  end
  Messenger.Refresh(true)
end

function Messenger.Show(key)
  if not win then
    build()
  end
  win:Show()
  if key then
    Messenger.Select(key)
  else
    selected = selected or Model.ConvoOrder(all())[1]
    Messenger.Select(selected)
  end
  return win
end

function Messenger.Hide()
  if win then
    win:Hide()
  end
end

function Messenger.Toggle()
  if shown() then
    Messenger.Hide()
  else
    Messenger.Show()
  end
end

function Messenger.Input()
  return input
end

function Messenger.Window()
  return win
end

function Messenger.Rows()
  return rows
end

-- At the start: the history trimmed (30 days, 500 lines a partner) and the unread count shown.
function Messenger.Start()
  local p = settings()
  Model.TrimConvos(stored(), time(), p.days, p.lines)
  ns.View.MessengerCount(Messenger.Unread())
end
