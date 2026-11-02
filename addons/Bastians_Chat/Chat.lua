-- Bastian's Chat (chat.md, ADR 0042): the module. Takes every finished line from the game's chat
-- frames, which stay alive under a hidden parent, runs it through the spam rules, hands it to the
-- tabs and the Messenger, moves the game's input bars into our window (with their history and the
-- shell keys), keeps the scrollback, and puts the game's chat back when switched off.
local ADDON, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
local L = ns.L
local S = B.UI.Style
local Model, Compat, Rules, Keys = ns.Model, ns.Compat, ns.Rules, ns.Keys

local Chat = {}
ns.Chat = Chat

Chat.SEEN_MAX = 400 -- remembered line ids: a line two of the game's frames show is taken once
Chat.BOX_LETTERS = 255 -- the game's bar holds this many letters, we lift it for long texts
Chat.TRUST_SECS = 60 -- how long a trust answer (friend, guild, group) is kept per sender
-- the lines that show a roleplay name (plan-launch-version L3): what is said where people stand
Chat.RP_TYPES = { SAY = true, YELL = true, EMOTE = true, TEXT_EMOTE = true }
-- the players' emotes (/e and /wave), drawn in the scheme's chatEmote (chat.md "Emotes for roleplay")
Chat.EMOTES = { EMOTE = true, TEXT_EMOTE = true }

local mod
local active = false -- the game's chat is replaced right now
local wanted = false -- switched on, waiting for the end of combat
local reloading = false
local hooked, boxHooked = {}, {} -- frames and bars hooked once per session (a hook stays)
local lastEvent = {} -- [frame] = the event the frame's next AddMessage shows
local seen, seenOrder = {}, {}
local moved = {} -- { frame, parent }: the game's chat parts under our hidden parent
local boxes = {} -- [bar] = its home: { parent, points, letters, bytes, alt }
local typed = {} -- [bar] = { cur, cleared, clearedAt, search }: what the bar held, for the history
local fed = {} -- [bar] = true once the kept history is in it
local spam = Rules.NewState()
local compiled
local trust = {} -- [sender] = { yes, at }
local insideInstance = false
-- the clear-screen key (plan-launch-review R5.6): true while it hides the chat; peek = { box, shown }
-- while Enter brought the main window up for one line
local suiteHidden, peek = false, nil
local hidden = CreateFrame("Frame")
hidden:Hide()

function Chat.DB()
  return mod.db
end

function Chat.Active()
  return active
end

-- A failure inside a hook (the hooks are the module's boundary, CLAUDE.md §5).
function Chat.Note(where, err)
  mod.noted = mod.noted or {} -- not `errors`: Core counts a module's errors there
  mod.noted[where] = (mod.noted[where] or 0) + 1
  if err then
    mod:Log("error", "%s: %s", where, tostring(err))
  end
end

-- A method the client may lack, called without raising: the value, or nil.
local function try(obj, method, ...)
  local args = { ... }
  local ok, value = pcall(function()
    return obj[method](obj, unpack(args))
  end)
  return ok and value or nil
end

local function guard(where, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    Chat.Note(where, err)
  end
end

-- ---------------------------------------------------------------------------------------------
-- Spam (ADR 0042 §7)
-- ---------------------------------------------------------------------------------------------

function Chat.Rules()
  if not compiled then
    compiled = Rules.Compile(mod.db.profile.spam)
  end
  return compiled
end

function Chat.RulesChanged()
  compiled = nil
  if mod.db.profile.spam.applyOld ~= false then
    Chat.Refilter()
  end
end

-- The rules onto the lines already shown ("immediately filter the whole
-- chat, not only new ones"): every kept line of every tab is judged again (the timeless part of
-- the rules: senders, words, web addresses); a line the rules take now leaves its tabs and the
-- saved scrollback and lands in Junk, a dimmed one is redrawn dim. Returns the lines taken.
function Chat.Refilter()
  if not active then
    return {}
  end
  local rules = Chat.Rules()
  local taken = ns.View.Refilter(function(line)
    local verdict = Rules.Judge(spam, rules, line, Chat.Trusted)
    if verdict then
      line.reason, line.word = verdict.reason, verdict.word
    end
    return verdict
  end)
  for _, line in ipairs(taken) do
    ns.Junk.Add(line)
  end
  return taken
end

-- Drops a kept line from a tab's saved scrollback (the text and the time name it).
function Chat.Unkeep(tabId, line)
  local sb = mod.db.char.scrollback[tabId]
  if not sb then
    return
  end
  for i = #sb, 1, -1 do
    local l = sb[i]
    if l.text == line.text and l.at == line.at then
      table.remove(sb, i)
    end
  end
end

-- S2: the player, friends, guild, group (asked once a minute per sender), and every contact.
function Chat.Trusted(sender)
  local convo = mod.db.global.convos[sender]
  if convo and Model.HasOwnLine(convo) then
    return true
  end
  local t = trust[sender]
  local now = GetTime()
  if not t or now - t.at > Chat.TRUST_SECS then
    t = { yes = Compat.IsTrusted(sender), at = now }
    trust[sender] = t
  end
  return t.yes
end

function Chat.Allow(sender)
  Rules.Allow(spam, sender)
end

function Chat.BlockSender(name)
  if type(name) == "string" and name ~= "" then
    mod.db.profile.spam.senders[name] = true
    Chat.RulesChanged()
    B:Say(L["%s is blocked in Bastian's Chat (the Junk window lifts it)."], Model.ShortName(name))
  end
end

function Chat.UnblockSender(name)
  mod.db.profile.spam.senders[name] = nil
  Chat.RulesChanged()
end

-- A captured line: the spam verdict, then the Messenger and the tabs.
function Chat.Route(line)
  local verdict, foldKey
  if not line.secret then
    verdict, foldKey = Rules.Check(spam, Chat.Rules(), line, GetTime(), Chat.Trusted)
  end
  if verdict then
    line.reason, line.word = verdict.reason, verdict.word
    if verdict.action == "fold" then
      ns.View.Fold(verdict.foldKey, verdict.count)
      return "fold"
    elseif verdict.action == "dim" then
      line.dim = true
    else
      ns.Junk.Add(line)
      return verdict.action
    end
  end
  line.foldKey = foldKey
  local mode = mod.db.profile.whisperTo
  if mode ~= "tabs" and (line.cat == "whisper" or line.cat == "bnet") then
    ns.Messenger.Add(line)
  end
  ns.View.Add(line)
  return verdict and verdict.action or "show"
end

-- ---------------------------------------------------------------------------------------------
-- Capture: the event a frame is about to show, then the finished line
-- ---------------------------------------------------------------------------------------------

local function onFilter(frame, event, ...)
  if active and frame ~= Compat.CombatLogFrame() then
    local text, sender, _, channelString, _, _, zoneChannel, _, channelName, _, lineID, _, bnID = ...
    local secret = Compat.IsSecret(text)
    local base = Compat.Plain(channelName)
    if type(base) ~= "string" or base == "" then
      base = type(Compat.Plain(channelString)) == "string" and channelString:match("^%d+%.%s*(.-)$") or nil
    end
    lastEvent[frame] = {
      event = event,
      sender = Compat.Plain(sender),
      zoneChannel = Compat.Plain(zoneChannel),
      lineID = Compat.Plain(lineID),
      channel = base,
      bnID = Compat.Plain(bnID),
      msg = not secret and Compat.Plain(text) or nil,
      secret = secret,
      at = GetTime(),
    }
  end
  return false
end

local function remember(key)
  if seen[key] then
    return true
  end
  seen[key] = true
  seenOrder[#seenOrder + 1] = key
  if #seenOrder > Chat.SEEN_MAX then
    seen[table.remove(seenOrder, 1)] = nil
  end
  return false
end

local me -- the player's "Name-Realm", read at the start

-- The line a frame shows, as the model's line, or nil when it is not ours to take.
function Chat.Line(frame, text, r, g, b)
  if frame == Compat.CombatLogFrame() then
    return nil
  end
  local ev = lastEvent[frame]
  lastEvent[frame] = nil
  if ev and ev.at ~= GetTime() then
    ev = nil -- a filter whose line never came (another addon dropped it)
  end
  if not ev and frame ~= DEFAULT_CHAT_FRAME then
    return nil -- prints without an event: from the default frame only
  end
  if ev then
    -- the same line in two frames: by its id, or (system lines carry id 0) by its text this frame
    local key
    if type(ev.lineID) == "number" and ev.lineID > 0 then
      key = ev.event .. ":" .. ev.lineID
    elseif not ev.secret and type(text) == "string" then
      key = ev.event .. ":" .. ev.at .. ":" .. text
    end
    if key and remember(key) then
      return nil
    end
  end
  local chatType = ev and Model.ChatType(ev.event)
  local line = {
    text = text,
    r = r,
    g = g,
    b = b,
    at = time(),
    chatType = chatType,
    cat = Model.Category(chatType),
    zoneChannel = ev and ev.zoneChannel,
    channel = ev and ev.channel,
    sender = ev and ev.sender,
    bnID = ev and ev.bnID,
    msg = ev and ev.msg,
    secret = (ev and ev.secret) or Compat.IsSecret(text),
  }
  if not line.secret then
    local source = line.msg or (type(text) == "string" and text) or ""
    line.plain = Model.Strip(source):lower()
  end
  if Chat.EMOTES[chatType] then
    -- roleplay (S9, L5): the scheme's emote colour instead of the game's, kept with the line
    local c = S.C.chatEmote
    line.r, line.g, line.b = c[1], c[2], c[3]
  end
  line.own = line.sender ~= nil and (line.sender == me or line.sender == UnitName("player"))
  if line.cat == "whisper" or line.cat == "bnet" then
    line.partner = line.sender
    if not line.partner then
      line.cat = "system" -- a secret sender: the line goes to General, without a conversation
    end
  end
  line.public = Model.IsPublic(line)
  if Chat.RP_TYPES[chatType] and line.sender and not line.secret and mod.db.profile.rpNames then
    -- the speaker's roleplay name (msp, read only), else ask for it once in a while
    local rp = B.Compat.MspName(line.sender)
    if rp then
      line.text = Model.WithRoleplayName(line.text, line.sender, rp.name)
      line.rpName = rp.name
    else
      B.Compat.MspRequest(line.sender)
    end
  end
  return line
end

local function onAddMessage(frame, text, r, g, b)
  if not active then
    return
  end
  local line = Chat.Line(frame, text, r, g, b)
  if line then
    Chat.Route(line)
  end
end

-- Never the combat log: its lines are not ours, and a hook on its AddMessage broke the game's
-- handler there (CHAT_MSG_TRADESKILLS, "attempt to call a nil value", retail 31.10.2026).
function Chat.HookFrames()
  local log = Compat.CombatLogFrame()
  for _, name in ipairs(Compat.ChatFrameNames()) do
    local f = _G[name]
    if f and f ~= log and not hooked[f] and type(f.AddMessage) == "function" then
      hooked[f] = true
      hooksecurefunc(f, "AddMessage", function(...)
        guard("capture", onAddMessage, ...)
      end)
    end
  end
end

-- ---------------------------------------------------------------------------------------------
-- The game's chat under our hidden parent, and back
-- ---------------------------------------------------------------------------------------------

local function stash(f)
  if type(f) ~= "table" or type(f.SetParent) ~= "function" then
    return
  end
  local parent = f:GetParent()
  if parent == hidden or boxes[f] then
    return
  end
  for _, wid in ipairs(ns.View.Windows()) do
    local W = ns.View.Window(wid)
    if W and parent == W.win.frame then
      return
    end
  end
  moved[#moved + 1] = { frame = f, parent = parent }
  f:SetParent(hidden)
end

function Chat.HideGame()
  for _, name in ipairs(Compat.ChatFrameNames()) do
    stash(_G[name])
    stash(_G[name .. "Tab"])
    stash(_G[name .. "ButtonFrame"])
  end
  for _, name in ipairs(Compat.CHAT_PARTS) do
    stash(_G[name])
  end
end

function Chat.ShowGame()
  for i = #moved, 1, -1 do
    local m = moved[i]
    m.frame:SetParent(m.parent)
    moved[i] = nil
  end
end

-- ---------------------------------------------------------------------------------------------
-- The game's input bars in our window: long texts, the history, the shell keys
-- ---------------------------------------------------------------------------------------------

local function onBoxText(box)
  if not active or not boxes[box] then
    return
  end
  local text = box:GetText()
  if type(text) ~= "string" or #text <= Chat.BOX_LETTERS or text:sub(1, 1) == "/" then
    return
  end
  local chatType = box:GetAttribute("chatType")
  local target = chatType == "WHISPER" and box:GetAttribute("tellTarget")
    or chatType == "CHANNEL" and box:GetAttribute("channelTarget")
    or nil
  if ns.View.TakeLong(text, chatType, target) then
    box:SetText("")
    Compat.DeactivateChat(box)
  end
end

-- What the game puts into the bar's history (every sent line and slash command) is kept too; the
-- lines we hand the bar at the start are not counted again.
local feeding = false
local function onBoxHistory(_, text)
  if active and not feeding then
    Keys.Remember(mod.db.char.history, text)
  end
end

-- Ctrl+R: the newest older history line that holds the text typed before the first Ctrl+R.
function Chat.SearchHistory(box)
  local t = typed[box]
  local history = mod.db.char.history
  local s = t.search
  local text = box:GetText() or ""
  if not s or s.shown ~= text then
    s = { query = text }
    t.search = s
  end
  local i = Keys.Search(history, s.query, s.index)
  if i then
    s.index, s.shown = i, history[i]
    box:SetText(history[i])
    box:SetCursorPosition(#history[i])
    ns.View.Hint(string.format(L["History search: %s (Ctrl+R: older)"], s.query))
  else
    ns.View.Hint(string.format(L["No older line holds: %s"], s.query))
  end
  return i
end

-- Ctrl+G: the search left, the text typed before it back.
function Chat.CancelSearch(box)
  local t = typed[box]
  local s = t and t.search
  if not s then
    return nil
  end
  t.search = nil
  box:SetText(s.query)
  box:SetCursorPosition(#s.query)
  ns.View.Hint(nil)
  return s.query
end

-- The text keys of the bar (ADR 0045, Bastians.TextKeys): the Windows keys always, the readline
-- set with the setting (chat.md "The input bar"); only while the bar has the keyboard, so no
-- binding of the game is touched. Ctrl+C, X, V stay the client's.
local killed = {} -- the text the last Ctrl+U, K, W or Alt+D took, for Ctrl+Y (every bar)
local keyOpts = {
  shell = function()
    return mod.db.profile.bashKeys
  end,
  onOp = function(box, op)
    if op == "search" then
      Chat.SearchHistory(box)
      return true
    elseif op == "cancel" then
      Chat.CancelSearch(box)
      return true
    end
  end,
}
Chat.keyOpts, Chat.killed = keyOpts, killed

function Chat.OnBoxKey(box, key)
  if not (active and boxes[box]) then
    return nil
  end
  keyOpts.extra = mod.db.profile.bashKeys and Keys.EXTRA or nil
  return S.TextKey(box, key, keyOpts, killed)
end

-- The bar is put back in our window whenever something else anchors it (the game, Edit Mode).
local function onBoxPoint(box)
  if active and boxes[box] and not ns.View.placing then
    C_Timer.After(0, function()
      if active and boxes[box] and not ns.View.HoldsBox(box) then
        ns.View.PlaceBox(box)
      end
    end)
  end
end

function Chat.AdoptBox(box)
  if not active or type(box) ~= "table" then
    return
  end
  if not boxes[box] then
    local home = { parent = box:GetParent(), points = {} }
    for i = 1, box:GetNumPoints() do
      home.points[i] = { box:GetPoint(i) }
    end
    home.letters = try(box, "GetMaxLetters") or Chat.BOX_LETTERS
    home.bytes = try(box, "GetMaxBytes")
    home.alt = try(box, "GetAltArrowKeyMode")
    boxes[box] = home
    typed[box] = typed[box] or {}
    try(box, "SetMaxLetters", 0)
    try(box, "SetMaxBytes", 0)
    try(box, "SetAltArrowKeyMode", false) -- Up and Down walk the history without Alt
    if not fed[box] then
      fed[box] = true
      feeding = true
      for _, l in ipairs(mod.db.char.history) do
        try(box, "AddHistoryLine", l)
      end
      feeding = false
    end
    if not boxHooked[box] then
      boxHooked[box] = true
      box:HookScript("OnTextChanged", function(self)
        guard("long", onBoxText, self)
      end)
      local ok, add = pcall(function()
        return box.AddHistoryLine
      end)
      if ok and type(add) == "function" then
        hooksecurefunc(box, "AddHistoryLine", function(self, text)
          guard("history", onBoxHistory, self, text)
        end)
      end
      box:HookScript("OnKeyDown", function(self, key)
        guard("keys", Chat.OnBoxKey, self, key)
      end)
      -- sent or Escape (the bar hides; with the "IM" chat style it only loses the focus): a peek
      -- under the clear-screen key ends
      box:HookScript("OnHide", function(self)
        guard("peek", Chat.BoxClosed, self)
      end)
      box:HookScript("OnEditFocusLost", function(self)
        guard("peek", Chat.BoxClosed, self)
      end)
      hooksecurefunc(box, "SetPoint", function(self)
        guard("place", onBoxPoint, self)
      end)
    end
  end
  ns.View.PlaceBox(box)
end

function Chat.ReleaseBoxes()
  for box, home in pairs(boxes) do
    box:SetParent(home.parent)
    box:ClearAllPoints()
    for _, p in ipairs(home.points) do
      box:SetPoint(unpack(p))
    end
    try(box, "SetMaxLetters", home.letters)
    if home.bytes then
      try(box, "SetMaxBytes", home.bytes)
    end
    if home.alt ~= nil then
      try(box, "SetAltArrowKeyMode", home.alt)
    end
    boxes[box] = nil
  end
end

-- The game showed, focused or activated a bar: into our window it goes (any callback argument
-- that is an edit box counts; the registry passes its owner first).
local function onBoxShown(...)
  if not active then
    return
  end
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if type(v) == "table" and type(v.GetObjectType) == "function" then
      local ok, kind = pcall(v.GetObjectType, v)
      if ok and kind == "EditBox" then
        Chat.AdoptBox(v)
        if suiteHidden then
          Chat.Peek(v) -- the key hides the chat: the main window for this one line
        else
          ns.View.Show()
        end
        -- the window was hidden (the clear-screen key): the box lost the focus the game gave it
        -- a moment ago; back on the next frame ("I have to press
        -- enter the second time")
        C_Timer.After(0, function()
          local hasFocus = v.HasFocus and v:HasFocus()
          if active and v:IsShown() and not hasFocus then
            v:SetFocus()
          end
        end)
        return
      end
    end
  end
end

-- ---------------------------------------------------------------------------------------------
-- The clear-screen key (plan-round4 F1, BASTIANS_SUITE_HIDDEN; plan-launch-review R5.6,
-- 01.11.2026): Core hides the chat's windows; Enter while hidden brings the main window with the
-- bar focused, and when the bar closes (sent or Escape) the window goes again while the key still
-- hides the suite. The chat's windows are not protected: nothing waits for the end of combat.
-- ---------------------------------------------------------------------------------------------

function Chat.SetSuiteHidden(on)
  suiteHidden = on == true
  peek = nil -- hidden: Core took the window; back: Core shows what it took
end

function Chat.SuiteHidden()
  return suiteHidden
end

function Chat.Peeking()
  return peek ~= nil
end

function Chat.Peek(box)
  local W = ns.View.Window() or ns.View.Setup()
  if not W then
    return
  end
  if not peek then
    peek = { shown = W.win.frame:IsShown() }
  end
  peek.box = box
  W.win:Show()
end

-- The bar hid or lost the focus: on the next frame (the game may hand the focus back, our own
-- refocus above runs then too) the peek ends unless the bar holds the focus again.
function Chat.BoxClosed(box)
  if not (peek and peek.box == box) then
    return
  end
  C_Timer.After(0, function()
    if not (peek and peek.box == box) then
      return
    end
    local hasFocus = box.HasFocus and box:HasFocus()
    if box:IsShown() and hasFocus then
      return
    end
    local was = peek
    peek = nil
    local W = ns.View.Window()
    if suiteHidden and W and not was.shown then
      W.win:Hide()
    end
  end)
end

-- ---------------------------------------------------------------------------------------------
-- What is kept: the scrollback per tab, the open whisper tabs
-- ---------------------------------------------------------------------------------------------

function Chat.Keep(tabId, line)
  if line.secret or line.cat == "bnet" or type(line.text) ~= "string" then
    return
  end
  local sb = mod.db.char.scrollback
  sb[tabId] = sb[tabId] or {}
  Model.Push(sb[tabId], {
    text = line.text,
    r = line.r,
    g = line.g,
    b = line.b,
    at = line.at,
    public = line.public or nil,
  }, mod.db.profile.keep)
end

function Chat.RememberWhisper(partner)
  local list = mod.db.char.whispers
  for _, p in ipairs(list) do
    if p == partner then
      return
    end
  end
  list[#list + 1] = partner
end

function Chat.ForgetWhisper(partner)
  local list = mod.db.char.whispers
  for i = #list, 1, -1 do
    if list[i] == partner then
      table.remove(list, i)
    end
  end
  mod.db.char.scrollback["w:" .. tostring(partner)] = nil
end

-- ---------------------------------------------------------------------------------------------
-- On and off
-- ---------------------------------------------------------------------------------------------

function Chat.Start()
  wanted = true
  if active then
    return
  end
  if InCombatLockdown() then
    return -- PLAYER_REGEN_ENABLED starts it
  end
  active = true
  me = Compat.PlayerName()
  local first = not ns.View.Window()
  ns.View.Setup()
  if first then
    if mod.db.profile.whisperTo ~= "messenger" then
      for _, partner in ipairs(mod.db.char.whispers) do
        ns.View.AddTab(Model.WhisperTab(partner))
      end
    end
    ns.View.Replay(mod.db.char.scrollback)
  end
  Chat.HookFrames()
  Chat.HideGame()
  for _, box in ipairs(Compat.EditBoxes()) do
    Chat.AdoptBox(box)
  end
  ns.View.Show()
  ns.Messenger.Start()
end

function Chat.Stop()
  wanted = false
  if not active then
    return
  end
  active = false
  Chat.ReleaseBoxes()
  Chat.ShowGame()
  ns.View.Hide()
  ns.Messenger.Hide()
  ns.Junk.Hide()
end

local function setupHooks()
  for _, event in ipairs(Model.EVENTS) do
    Compat.AddFilter(event, onFilter)
  end
  -- every bar the game shows or activates comes into our window (retail 12.x: ChatFrameUtil and
  -- the EventRegistry callbacks; the old global where a client still calls it)
  for _, name in ipairs({ "ChatEdit_ActivateChat", "ChatFrameUtil.ActivateChat" }) do
    Compat.HookGlobal(name, function(box)
      guard("activate", onBoxShown, box)
    end)
  end
  for _, event in ipairs({ "ChatFrame.OnEditBoxShow", "ChatFrame.OnEditBoxFocusGained" }) do
    Compat.OnRegistryEvent(event, function(...)
      guard("activate", onBoxShown, ...)
    end, Chat)
  end
  -- a whisper window the game opens later is hidden and captured too
  Compat.HookGlobal("FCF_OpenTemporaryWindow", function()
    if active then
      guard("whisper window", function()
        Chat.HookFrames()
        Chat.HideGame()
      end)
    end
  end)
  -- a /reload is not a logout: the public lines stay
  Compat.HookGlobal("ReloadUI", function()
    reloading = true
  end)
  if type(C_UI) == "table" and type(C_UI.Reload) == "function" then
    hooksecurefunc(C_UI, "Reload", function()
      reloading = true
    end)
  end
end

local function onZone()
  local inside = Compat.InstanceKind() ~= nil
  if inside ~= insideInstance then
    insideInstance = inside
    ns.View.SelectGroup(inside)
  end
  ns.View.OnZone(inside)
end

local function strengths()
  local out = {}
  for i, id in ipairs(Rules.LEVEL_ORDER) do
    out[id] = i .. ". " .. L["strength: " .. id]
  end
  return out
end

mod = B:NewModule("Chat", {
  news = ns.NEWS, -- What's new (ADR 0021)
  addon = ADDON,
  title = L["Chat"],
  icon = "Interface\\AddOns\\Bastians_Chat\\Icon",
  open = function()
    ns.View.Toggle()
  end,
  -- the Messenger's own minimap button beside the chat's
  minimapButtons = {
    {
      id = "Messenger",
      title = L["Messenger"],
      icon = B.UI.IconTexture("invite"), -- a person: apart from the chat's bubble
      open = function()
        ns.Messenger.Toggle()
      end,
    },
  },
  apiVersion = 1,
  defaults = {
    profile = {
      enabled = false, -- ships off by default
      window = {},
      places = {},
      layout = {},
      tabs = {},
      selected = {},
      copy = {},
      editor = {},
      junkWindow = {},
      stamps = "off",
      font = "",
      fontSize = 14,
      outline = "",
      spacing = 0,
      fade = false,
      keep = 200,
      showOnWhisper = true,
      whisperTo = "messenger",
      bashKeys = true,
      shortChannels = "off",
      itemIcons = true,
      altInvite = true,
      rpNames = true, -- roleplay names in say and emote lines (plan-launch-version L3)
      combatFade = false,
      groupInInstance = true,
      spam = { level = "normal", action = "junk", block = "", allow = "", senders = {}, applyOld = true },
      messenger = { window = {}, open = true, sound = "none", days = 30, lines = 500 },
    },
    char = { scrollback = {}, whispers = {}, history = {} },
    global = { convos = {} },
  },
  options = {
    { type = "header", label = L["Chat"] },
    { type = "toggle", key = "showOnWhisper", label = L["Open the window on a whisper"] },
    {
      type = "toggle",
      key = "rpNames",
      label = L["Roleplay names in say, yell and emote lines (Total RP 3, MyRolePlay)"],
    },
    {
      type = "note",
      text = function()
        return B.Compat.HasMsp() and "" or L["Roleplay names: Total RP 3 or MyRolePlay is not installed."]
      end,
    },
    {
      type = "execute",
      label = L["Messenger minimap button: show or hide"],
      desc = L["The Messenger has a minimap button of its own beside the chat's."],
      func = function()
        local launcher = B.UI.Launcher
        launcher.SetAppButton("ChatMessenger", not launcher.AppButtonShown("ChatMessenger"))
      end,
    },
    {
      type = "select",
      key = "whisperTo",
      label = L["Whispers go to"],
      values = {
        messenger = L["the Messenger"],
        tabs = L["a tab per partner"],
        both = L["both"],
      },
    },
    {
      type = "select",
      key = "stamps",
      label = L["Time before each line"],
      values = { off = L["None"], hm = "14:32", hms = "14:32:07" },
    },
    {
      type = "select",
      key = "shortChannels",
      label = L["Channel names"],
      values = { off = L["as the game writes them"], number = "[2]", name = "[Trade]" },
    },
    { type = "toggle", key = "itemIcons", label = L["An icon before item links"] },
    { type = "toggle", key = "altInvite", label = L["Alt+click on a name invites"] },
    {
      type = "execute",
      label = L["Names in class colours"],
      desc = L["Every channel colours names by class (the game's own setting)."],
      func = function()
        if Compat.ClassColorsEverywhere() then
          B:Say(L["Names are now in class colours in every channel."])
        end
      end,
    },
    { type = "header", label = L["Text"] },
    {
      type = "font",
      key = "font",
      label = L["Font"],
      values = function()
        return ns.View.FontChoices()
      end,
    },
    { type = "range", key = "fontSize", label = L["Text size"], min = 10, max = 22, step = 1 },
    {
      type = "select",
      key = "outline",
      label = L["Outline"],
      values = { [""] = L["None"], OUTLINE = L["thin"], THICKOUTLINE = L["thick"] },
    },
    { type = "range", key = "spacing", label = L["Line spacing"], min = 0, max = 6, step = 1 },
    { type = "toggle", key = "fade", label = L["Fade old lines"] },
    { type = "range", key = "keep", label = L["Lines kept per tab"], min = 50, max = 500, step = 50 },
    { type = "header", label = L["Input bar"] },
    {
      type = "toggle",
      key = "bashKeys",
      label = L["Shell keys: Ctrl+A, E, U, K, W, R (only while you type)"],
    },
    { type = "header", label = L["Context"] },
    { type = "toggle", key = "combatFade", label = L["Fade the windows in combat"] },
    { type = "toggle", key = "groupInInstance", label = L["Group tab in dungeons and raids"] },
    { type = "header", label = L["Spam"] },
    {
      type = "select",
      key = "level",
      label = L["Spam filter"],
      get = function(m)
        return m.db.profile.spam.level
      end,
      set = function(v, m)
        m.db.profile.spam.level = v
        Chat.RulesChanged()
      end,
      values = strengths,
    },
    {
      -- a changed rule reaches what is already on screen
      type = "toggle",
      key = "spamApplyOld",
      label = L["Apply the filter to older lines too"],
      get = function(m)
        return m.db.profile.spam.applyOld ~= false
      end,
      set = function(v, m)
        m.db.profile.spam.applyOld = v and true or false
        if v then
          Chat.Refilter()
        end
      end,
    },
    {
      type = "execute",
      label = L["Junk and word lists"],
      desc = L["The filtered lines with their reason, the blocked and allowed words."],
      func = function()
        ns.Junk.Show()
      end,
    },
    { type = "header", label = L["Messenger"] },
    {
      type = "toggle",
      key = "msgOpen",
      label = L["Open the Messenger on a whisper"],
      get = function(m)
        return m.db.profile.messenger.open
      end,
      set = function(v, m)
        m.db.profile.messenger.open = v
      end,
    },
    {
      type = "range",
      key = "msgDays",
      label = L["Days of history"],
      min = 1,
      max = 90,
      step = 1,
      get = function(m)
        return m.db.profile.messenger.days
      end,
      set = function(v, m)
        m.db.profile.messenger.days = v
      end,
    },
  },
  OnInitialize = function()
    setupHooks()
  end,
  OnEnable = function(self)
    ns.Feed.Register(self)
    for _, key in ipairs({ "scrollback", "history" }) do
      self.db.char[key] = type(self.db.char[key]) == "table" and self.db.char[key] or {}
    end
    self.db.char.whispers = type(self.db.char.whispers) == "table" and self.db.char.whispers or {}
    self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
      if wanted and not active then
        Chat.Start()
      end
      ns.View.SetCombat(false)
    end)
    self:RegisterEvent("PLAYER_REGEN_DISABLED", function()
      if active then
        ns.View.SetCombat(true)
      end
    end)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
      if active then
        onZone()
      end
    end)
    self:RegisterEvent("PLAYER_LOGOUT", function()
      if not reloading then
        -- the game's public channels end with the session, and tabs marked not to keep
        Model.DropPublic(self.db.char.scrollback, self.db.profile.tabs)
      end
    end)
    self:On("BASTIANS_SETTING_CHANGED", function(_, _, name)
      if name == self.name and active then
        ns.View.Apply()
      end
    end)
    -- the clear-screen key, only while the page "Hidden by the key" ticks the chat; the key's
    -- return always passes (as the Orbiter, Voice/Module.lua)
    self:On("BASTIANS_SUITE_HIDDEN", function(_, _, on)
      local Screen = B.UI.Screen
      if on and Screen and Screen.Hides and not Screen.Hides("Chat") then
        return
      end
      Chat.SetSuiteHidden(on == true)
    end)
    local Screen = B.UI.Screen
    Chat.SetSuiteHidden(Screen ~= nil and Screen.Hidden ~= nil and Screen.Hidden() and Screen.Hides("Chat"))
    Chat.Start()
  end,
  OnDisable = function()
    Chat.Stop()
  end,
})
ns.mod = mod
mod.Chat, mod.Model, mod.View = Chat, Model, ns.View
mod.Messenger, mod.Junk, mod.Rules, mod.Keys = ns.Messenger, ns.Junk, Rules, Keys

SLASH_BASTIANSCHAT1 = "/bchat"
SlashCmdList.BASTIANSCHAT = function(msg)
  local cmd = string.lower(strtrim(msg or ""))
  if cmd == "copy" then
    ns.View.CopyTab()
  elseif cmd == "msg" or cmd == "messenger" then
    ns.Messenger.Toggle()
  elseif cmd == "junk" then
    ns.Junk.Toggle()
  else
    ns.View.Toggle()
  end
end
