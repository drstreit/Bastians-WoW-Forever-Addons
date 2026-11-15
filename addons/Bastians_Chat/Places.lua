-- Bastian's Chat, a place in a window of its own (plan-chat-one-window.md §4, ADR 0076; owner,
-- 13.11.2026: "you can pull categories out of the inbox left list into a new window that you can
-- place anywhere. And again drop back."): a stream, a person or a saved search dragged from the
-- rail and let go outside the chat window (or its right click "Window of its own") stands in a
-- window there, in its form, with its own filter line; dragged back onto the chat window, or
-- closed, it is in the rail again. A person's window has its own input line (Q3, as WIM's
-- windows; whispers are sent from addon code, verified on Forever 08.11.2026); every other window
-- answers through the chat window's line (a click on a line opens it on the line's channel). Which
-- places are out, their windows' places, sizes, locks and text size are kept in the profile. The
-- Switchboard's column windows (Q6) were the model; they went with it in V31.
local _, ns = ...
local B = Bastians
local S = B.UI.Style
local L = ns.L
local Model, Compat = ns.Model, ns.Compat

local Places = {}
ns.Places = Places

Places.W, Places.H = 340, 300 -- a window when it first opens
Places.FILTER_H = 24
Places.INPUT_H = 24
-- "Text size larger, smaller": the window's scale (keyed: bare numbers in a row read as a colour)
Places.SCALES = { [1] = 0.85, [2] = 1, [3] = 1.15, [4] = 1.3 }

local wins = {} -- [place id] = { id, win, filter, list, feed, input, ... }
local serial = 0 -- the windows' global names
local parts = {} -- [person] = { list, next } of a long text being sent from their window

local function settings()
  local s = ns.Inbox.Settings()
  s.out = type(s.out) == "table" and s.out or {}
  s.windows = type(s.windows) == "table" and s.windows or {}
  return s
end

local function store()
  return ns.Chat.Store()
end

-- What a place id names: "guild" a stream, "p:<key>" a person, "s:<name>" a saved search.
function Places.Kind(id)
  if type(id) ~= "string" then
    return nil
  end
  if id:sub(1, 2) == "p:" then
    return "person", id:sub(3)
  elseif id:sub(1, 2) == "s:" then
    return "saved", id:sub(3)
  elseif ns.Inbox.STREAM_TIER[id] and id ~= "direct" then
    return "stream", id
  end
  return nil
end

-- Does the place exist (a stream of the rail, a conversation, a saved search)? All never leaves.
function Places.Valid(id)
  local kind, key = Places.Kind(id)
  if kind == "person" then
    return ns.People.Convo(key) ~= nil
  elseif kind == "saved" then
    return ns.Views.Find(key) ~= nil
  end
  return kind == "stream"
end

function Places.Title(id)
  local kind, key = Places.Kind(id)
  if kind == "person" then
    local c = ns.People.Convo(key)
    return c and Model.ShortName(c.name) or key
  elseif kind == "saved" then
    return key
  end
  return L[ns.Find.STREAM_LABELS[key] or key]
end

function Places.IsOut(id)
  return settings().out[id] == true
end

function Places.Window(id)
  return wins[id]
end

-- The streams a window's feed shows and their form.
local function streamsOf(id)
  local kind, key = Places.Kind(id)
  if kind == "stream" then
    return { [key] = true }, ns.Inbox.FORMS[key]
  elseif kind == "saved" then
    local v = ns.Views.Find(key)
    local streams = v and v.streams
    local form
    for s in pairs(streams or {}) do
      local f = ns.Inbox.FORMS[s]
      form = (form == nil or form == f) and f or false
    end
    return streams, form or nil
  end
  return nil
end

-- ---------------------------------------------------------------------------------------------
-- Drawing a window's place
-- ---------------------------------------------------------------------------------------------

local function query(W)
  local kind, key = Places.Kind(W.id)
  local words = W.filter:GetText()
  if kind == "saved" then
    local v = ns.Views.Find(key)
    words = ((v and v.query) or "") .. " " .. (words or "")
  end
  return ns.Find.Query(words)
end

-- A window's place drawn again from the store or the conversation.
function Places.Fill(id)
  local W = wins[id]
  if not W or not W.win.frame:IsShown() then
    return
  end
  local kind, key = Places.Kind(id)
  local q = query(W)
  if kind == "person" then
    local c = ns.People.Convo(key)
    local items = ns.People.Items(c, nil, time(), q and function(l)
      return q:Match(ns.Find.LineRec(c, l))
    end or nil)
    W.feed = nil
    W.list.gap = 0
    W.list:SetItems(items)
    W.win.title:SetText(Places.Title(id))
    return
  end
  local streams, form = streamsOf(id)
  form = form or {}
  local off
  if streams and next(streams) then
    off = {}
    for _, sid in ipairs(ns.Store.STREAMS) do
      if not streams[sid] then
        off[sid] = true
      end
    end
  end
  local now = time()
  W.feed = ns.Rows.NewFeed({
    off = off,
    maxTier = 5,
    query = q,
    board = form.board,
    blocks = form.blocks,
    byDungeon = form.byDungeon,
    since = form.board and now - ns.Rows.BOARD_AGE or nil,
  })
  W.feed.filled = now
  for _, rec in ipairs(store():Query()) do
    W.feed:Add(rec)
  end
  if form.byDungeon then
    ns.Rows.OrderBoard(W.feed.items, Compat.PlayerLevel())
  end
  W.list.gap = form.board and ns.Rows.BOARD_GAP or 0
  W.list:SetItems(W.feed.items)
  W.filter.count:SetText(q and tostring(W.feed.matched) or "")
end

-- The store's news: a new record into every window whose streams take it.
function Places.OnStore(what, rec)
  if what ~= "add" then
    return
  end
  for id, W in pairs(wins) do
    if W.feed and W.win.frame:IsShown() and W.feed:Shows(rec) and ns.Combat.Draws(rec) then
      if W.feed.opts.board and time() - (W.feed.filled or 0) >= ns.Inbox.BOARD_REFRESH then
        Places.Fill(id)
      else
        local added, changed = W.feed:Add(rec)
        if changed then
          W.list:Invalidate(changed)
        end
        if added then
          W.list:Append(added)
        end
      end
    end
  end
end

-- A conversation changed: its person's window, if it is out.
function Places.OnPeople(key)
  for id, W in pairs(wins) do
    local kind, k = Places.Kind(id)
    if kind == "person" and (key == nil or k == key) and W.win.frame:IsShown() then
      local c = ns.People.Convo(k)
      if c then
        c.unread = 0 -- read while its window shows
      end
      Places.Fill(id)
    end
  end
end

-- ---------------------------------------------------------------------------------------------
-- A person's own input line (Q3): Enter whispers them, a long text in parts, one per Enter
-- ---------------------------------------------------------------------------------------------

function Places.Send(id)
  local W = wins[id]
  local kind, key = Places.Kind(id)
  if not W or kind ~= "person" or not W.input then
    return false
  end
  local input = W.input
  local pending = parts[key]
  if pending then
    ns.People.SendOne(key, pending.list[pending.next])
    pending.next = pending.next + 1
    if pending.next > #pending.list then
      parts[key] = nil
      input:SetText("")
    else
      input:SetText(pending.list[pending.next])
    end
    return true
  end
  local text = input:GetText() or ""
  if not text:find("%S") then
    input:ClearFocus()
    return false
  end
  if #text > Model.PART_BYTES and not ns.People.IsBNet(key) then
    local pieces = Model.Split(text)
    ns.People.SendOne(key, pieces[1])
    parts[key] = { list = pieces, next = 2 }
    input:SetText(pieces[2])
    return true
  end
  ns.People.SendOne(key, text)
  input:SetText("")
  return true
end

-- ---------------------------------------------------------------------------------------------
-- The windows
-- ---------------------------------------------------------------------------------------------

-- The window's head menu (plan §5): back into the chat window, lock, text size, close.
function Places.HeadMenu(id, anchor)
  local W = wins[id]
  if not W then
    return nil
  end
  local db = W.win.db
  local items = {
    {
      label = L["Back into the chat window"],
      onClick = function()
        Places.Dock(id)
      end,
    },
    {
      label = db.locked and L["Unlock"] or L["Lock"],
      onClick = function()
        W.win:SetLocked(not db.locked)
      end,
    },
    {
      label = L["Text size larger"],
      onClick = function()
        Places.Scale(id, 1)
      end,
    },
    {
      label = L["Text size smaller"],
      onClick = function()
        Places.Scale(id, -1)
      end,
    },
    {
      label = L["Close"],
      onClick = function()
        Places.Dock(id)
      end,
    },
  }
  B.UI.Menu(anchor, Places.Title(id), items, ns.mod)
  return items
end

-- The window's text one step larger (1) or smaller (-1), kept with it.
function Places.Scale(id, dir)
  local W = wins[id]
  if not W then
    return nil
  end
  local db = W.win.db
  local at = 2
  for i, v in ipairs(Places.SCALES) do
    if v == (db.scale or 1) then
      at = i
    end
  end
  at = math.max(1, math.min(#Places.SCALES, at + dir))
  db.scale = Places.SCALES[at]
  W.win.frame:SetScale(db.scale)
  return db.scale
end

local function build(id)
  local s = settings()
  s.windows[id] = type(s.windows[id]) == "table" and s.windows[id] or {}
  serial = serial + 1
  local W = { id = id }
  local win = B.UI.Window("BastiansChatPlace" .. serial, {
    module = "Chat",
    title = Places.Title(id),
    width = Places.W,
    height = Places.H,
    minWidth = 240,
    minHeight = 180,
    lockable = true,
    headIcons = true, -- the chat's windows: Lock, Options, Close as pictograms (V27)
    db = s.windows[id],
    escape = false, -- Escape must not close the chat
    strata = "LOW", -- with the chat window, under every other
    onResize = function()
      Places.Fill(id)
    end,
  })
  W.win = win
  -- its close puts the place back into the rail; dragged onto the chat window it goes back too
  win.close:SetScript("OnClick", function()
    Places.Dock(id)
  end)
  win.close.tip = L["Back into the chat window"]
  local function dock()
    local main = ns.View.Window(ns.View.MAIN)
    if main and main.win.frame:IsShown() and main.win.frame:IsMouseOver() then
      Places.Dock(id)
    end
  end
  win.head:HookScript("OnDragStop", dock)
  win.frame:HookScript("OnDragStop", dock)
  win.head:HookScript("OnMouseUp", function(self, button)
    if button == "RightButton" then
      Places.HeadMenu(id, self)
    end
  end)
  win.head.tip = L["Drag onto the chat window to put it back into the rail"]
  win.head:HookScript("OnEnter", S.TipEnter)
  win.head:HookScript("OnLeave", S.TipLeave)
  local content = win.content
  local kind = Places.Kind(id)
  -- its own filter line (plan §4)
  W.filter = S.search(content, L["Words; -word leaves out"], true)
  W.filter:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -4)
  W.filter:SetPoint("RIGHT", content, "RIGHT", -4, 0)
  W.filter.count = S.SetRole(S.text(W.filter, 10, S.C.muted), "number")
  W.filter.count:SetPoint("RIGHT", W.filter.clear, "LEFT", -2, 0)
  W.filter:SetScript("OnTextChanged", function(self)
    local text = self:GetText() or ""
    self.hint:SetShown(text == "")
    self.clear:SetShown(text ~= "")
    Places.Fill(id)
  end)
  W.filter:SetScript("OnEscapePressed", function(self)
    self:SetText("")
    self:ClearFocus()
  end)
  local bottom = 4
  if kind == "person" then
    W.input = CreateFrame("EditBox", nil, content)
    W.input:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 4, 4)
    W.input:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -4, 4)
    W.input:SetHeight(Places.INPUT_H)
    W.input:SetFontObject(Compat.ChatFont())
    W.input:SetAutoFocus(false)
    W.input:SetMaxLetters(0)
    pcall(W.input.SetTextInsets, W.input, 6, 6, 0, 0)
    S.ink(W.input, S.C.text)
    W.input.ground = S.roundFill(W.input, S.C.inset, "radiusSmall")
    W.input.edges = S.roundEdges(W.input, S.C.accent, "radiusSmall")
    W.input.hint = S.text(W.input, 12, S.C.dim)
    W.input.hint:SetPoint("LEFT", W.input, "LEFT", 8, 0)
    W.input.hint:SetText(L["To %s: Enter whispers"]:format(Places.Title(id)))
    W.input:SetScript("OnTextChanged", function(self)
      self.hint:SetShown((self:GetText() or "") == "")
    end)
    W.input:SetScript("OnEnterPressed", function()
      Places.Send(id)
    end)
    W.input:SetScript("OnEscapePressed", function(self)
      parts[select(2, Places.Kind(id))] = nil
      self:ClearFocus()
    end)
    S.EditKeys(W.input, ns.Chat.keyOpts) -- the text keys (ADR 0045)
    bottom = bottom + Places.INPUT_H + 4
  end
  W.area = CreateFrame("Frame", nil, content)
  W.area:SetPoint("TOPLEFT", W.filter, "BOTTOMLEFT", 0, -4)
  W.area:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -4, bottom)
  ns.Inbox.Panel(W.area, "stream")
  W.area.inner = CreateFrame("Frame", nil, W.area)
  W.area.inner:SetPoint("TOPLEFT", W.area, "TOPLEFT", 4, -4)
  W.area.inner:SetPoint("BOTTOMRIGHT", W.area, "BOTTOMRIGHT", -2, 4)
  W.list =
    B.UI.VirtualList.New(W.area.inner, { kinds = ns.Rows.KINDS, stick = true, bottomUp = true, max = 1000 })
  if s.windows[id].scale then
    win.frame:SetScale(s.windows[id].scale)
  end
  ns.View.Dress(win) -- Chat's look (V13)
  wins[id] = W
  return W
end

-- The place into a window of its own, its top left at (x, y) in UIParent's units when given.
-- All never leaves the rail; a place that is out already is brought to the front.
function Places.Detach(id, x, y)
  if not Places.Valid(id) then
    if id == "all" then
      B:Say(L["All stays in the chat window."])
    end
    return false
  end
  local s = settings()
  s.out[id] = true
  local W = wins[id] or build(id)
  if x and y then
    W.win.frame:ClearAllPoints()
    W.win.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x - 20, y + 10)
    W.win:SavePlace()
  end
  W.win:Show()
  W.win.frame:Raise()
  -- the main window shows something else while the place is out
  local kind, key = ns.Front.Place()
  local pk, pkey = Places.Kind(id)
  if
    (pk == "stream" and kind == "stream" and key == pkey)
    or (pk == "person" and kind == "person" and key == pkey)
    or (pk == "saved" and kind == "saved" and key == pkey)
  then
    ns.Front.ShowMix()
  end
  if pk == "person" then
    local c = ns.People.Convo(pkey)
    if c then
      c.unread = 0
      ns.People.Changed(pkey)
    end
  end
  Places.Fill(id)
  ns.Front.DrawRail()
  return true
end

-- The place back into the rail: its window hides.
function Places.Dock(id)
  local s = settings()
  if not s.out[id] then
    return false
  end
  s.out[id] = nil
  if wins[id] then
    wins[id].win:Hide()
  end
  ns.Front.DrawRail()
  return true
end

-- The windows of the places that are out, shown with the chat window, hidden with it; one whose
-- place is gone (a conversation deleted) goes back.
function Places.ShowWindows(on)
  local s = settings()
  for id in pairs(s.out) do
    if not Places.Valid(id) then
      s.out[id] = nil
    elseif on then
      local W = wins[id] or build(id)
      W.win:Show()
      Places.Fill(id)
    end
  end
  for id, W in pairs(wins) do
    if not on or not s.out[id] then
      W.win:Hide()
    end
  end
end

-- ---------------------------------------------------------------------------------------------
-- Dragging a place off the rail: a label follows the cursor (OnUpdate only while it does); let go
-- outside the chat window, the place gets its window there.
-- ---------------------------------------------------------------------------------------------

local dragging, ghost

local function cursor()
  local x, y = GetCursorPosition()
  local scale = UIParent:GetEffectiveScale() or 1
  return x / scale, y / scale
end

local function follow(self)
  local x, y = cursor()
  self:ClearAllPoints()
  self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
end

function Places.BeginDrag(id)
  if not Places.Valid(id) then
    return
  end
  dragging = id
  if not ghost then
    ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetSize(140, 22)
    ghost:SetFrameStrata("TOOLTIP")
    ghost.bg = S.roundFill(ghost, S.C.panel, "radiusSmall")
    ghost.edges = S.roundEdges(ghost, S.C.accent, "radiusSmall")
    ghost.label = S.text(ghost, 12, S.C.text)
    ghost.label:SetPoint("CENTER")
  end
  ghost.label:SetText(Places.Title(id))
  ghost:SetScript("OnUpdate", follow)
  follow(ghost)
  ghost:Show()
end

function Places.EndDrag()
  local id = dragging
  dragging = nil
  if ghost then
    ghost:SetScript("OnUpdate", nil)
    ghost:Hide()
  end
  if not id then
    return nil
  end
  local main = ns.View.Window(ns.View.MAIN)
  local over = main ~= nil and main.win.frame:IsShown() and main.win.frame:IsMouseOver()
  if over then
    return nil -- let go on the chat window: it stays in the rail
  end
  local x, y = cursor()
  return Places.Detach(id, x, y) and "detached" or nil
end

-- A rail row draggable as its place (`placeOf(row)` names it when the drag starts).
function Places.Draggable(row, placeOf)
  row:RegisterForDrag("LeftButton")
  row:SetScript("OnDragStart", function(self)
    local id = placeOf(self)
    if id then
      Places.BeginDrag(id)
    end
  end)
  row:SetScript("OnDragStop", function()
    Places.EndDrag()
  end)
end

function Places.Attach()
  if not Places.attached then
    Places.attached = true
    store():On(Places.OnStore)
  end
end
