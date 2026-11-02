-- Bastian's Chat, the windows (chat.md): the main window and the windows tabs were dragged into,
-- their tab bars, one message area per tab on the game's dark chat ground, tab menus and the tab
-- editor, link clicks and our own name menu, the copy box, and the bar for long texts that sits
-- where the game's input bar sits.
local _, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
local L = ns.L
local S = B.UI.Style
local Model, Compat = ns.Model, ns.Compat

local View = {}
ns.View = View

View.TAB_H = 20
View.INPUT_H = 26
View.GROUND = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark" -- the game's dark ground
View.GROUND_ALPHA = 0.85
View.MAX_LINES = 1000 -- per message area
View.MAIN = "main"
View.SOUND_GAP = 2 -- seconds between two sounds of one tab
View.COMBAT_ALPHA = 0.35
View.QUIET = { [1] = 15, [2] = 30, [3] = 60 } -- minutes (keyed: three bare numbers read as a colour)
View.FONT_DIR = "Interface\\AddOns\\Bastians_Chat\\Fonts\\"
View.MESSENGER_ICON = "Interface\\AddOns\\Bastians_Chat\\Icon" -- the app's icon, until E4's pictograms
-- the condensed fonts shipped with the app (SIL OFL, sources.md)
View.FONTS = {
  { "BarlowCondensed", "Barlow Condensed" },
  { "FiraSansCondensed", "Fira Sans Condensed" },
  { "IBMPlexSansCondensed", "IBM Plex Sans Condensed" },
  { "PTSansNarrow", "PT Sans Narrow" },
  { "SairaCondensed", "Saira Condensed" },
}

local redraw -- a tab's frame from its kept lines (below; View.Refilter needs it first)
local wins = {} -- [window id] = { id, win, bar, area, tabs = { tab, ... }, current, empty }
local byId = {} -- [tab id] = { def, words, button, frame, wid, unread, quiet, folds }
local longBox, longNote, copyWin, copyEdit, ghost, editor
local long -- { parts, next, chatType, target } while a long text is being sent
local lastSound = {}
local before -- the tab of the main window before an instance brought Group forward
local ready = false

local function db()
  return ns.Chat.DB()
end

local function profile()
  return db().profile
end

-- A method the frame may lack (the mock, an older client), called without raising.
local function call(obj, method, ...)
  local ok, f = pcall(function()
    return obj[method]
  end)
  if ok and type(f) == "function" then
    return pcall(f, obj, ...)
  end
  return false
end

local function tabTitle(def)
  if def.whisper or def.named then
    return def.title
  end
  return L[def.title]
end

-- ---------------------------------------------------------------------------------------------
-- Fonts
-- ---------------------------------------------------------------------------------------------

-- Every font to choose: "" is the game's chat font; on Korean and Chinese clients only that one.
function View.FontChoices()
  local out = { [""] = L["The game's chat font"] }
  if S.CJK then
    return out
  end
  local core = B.UI.Settings and B.UI.Settings.FontChoices
  if type(core) == "function" then
    for path, name in pairs(core()) do
      out[path] = name
    end
  end
  for _, f in ipairs(View.FONTS) do
    out[View.FONT_DIR .. f[1] .. ".ttf"] = f[2]
  end
  return out
end

local function applyFont(f)
  local p = profile()
  local gamePath, _, gameFlags = Compat.ChatFont():GetFont()
  local flags = (p.outline and p.outline ~= "") and p.outline or gameFlags or ""
  local path = (p.font and p.font ~= "") and p.font or gamePath
  local ok, set = call(f, "SetFont", path, p.fontSize, flags)
  if (not ok or set == false) and gamePath then
    call(f, "SetFont", gamePath, p.fontSize, flags) -- a file the client does not see yet (restart)
  end
  call(f, "SetSpacing", p.spacing or 0)
end
View.ApplyFont = applyFont -- the Messenger's bubbles too

-- ---------------------------------------------------------------------------------------------
-- Tabs
-- ---------------------------------------------------------------------------------------------

-- The kind tile of a tab (ADR 0046): by the preset's id, a speech bubble for the rest.
local TAB_KINDS = {
  system = "settings",
  general = "service",
  loot = "item",
  trade = "gold",
  group = "invite",
  guild = "keep",
  bnet = "voice",
}
local function tabKind(def)
  if def.whisper then
    return "invite"
  end
  return TAB_KINDS[def.id] or "service"
end

local function paintTab(tab)
  local b = tab.button
  local W = wins[tab.wid]
  if not (b and W) then
    return
  end
  local on = tab == W.current
  b.spec.on = on or nil
  b.spec.unread = (tab.unread and not on) or nil
  S.Draw(b)
  if tab.quiet then
    S.ink(b.label, S.Tok(b, "muted"))
  end
end

local function firstShown(W)
  for _, tab in ipairs(W.tabs) do
    if not (tab.def.hidden and not tab.used) then
      return tab
    end
  end
  return W.tabs[1]
end

View.MIN_W = 220 -- a window's width at least, before its tabs ask for more

-- The window at least as wide as its tabs and the bar's buttons (, round 3: "the
-- tabs and the buttons are overlapping on scaling and the tabs are scaling out of the window box
-- if too small"): the bar's needed width is the window's minimum; a narrower window widens.
local function fitWidth(W, tabsEnd)
  if not (W.copy and W.plus and W.filterButton) then
    return
  end
  local right = (W.copy:GetWidth() or 50) + 4 + (W.filterButton:GetWidth() or 50) + 4
  if W.junk then
    right = right + (W.junk:GetWidth() or 70) + 4
  end
  local frame, content = W.win.frame, W.win.content
  local fw, cw = frame:GetWidth() or 0, content:GetWidth() or 0
  local chrome = (cw > 0 and fw > cw) and (fw - cw) or 2 -- the game's frame around the content
  local need = math.max(View.MIN_W, math.ceil(tabsEnd + 2 + (W.plus:GetWidth() or 22) + 8 + right + chrome))
  if W.minWidth ~= need then
    W.minWidth = need
    W.win.opts.minWidth = need
    call(frame, "SetResizeBounds", need, W.win.opts.minHeight or 120)
  end
  if fw > 0 and fw < need then
    frame:SetWidth(need)
    W.win:SavePlace()
  end
end

local function layoutTabs(W)
  local x = 4
  for _, tab in ipairs(W.tabs) do
    local b = tab.button
    if tab.def.hidden and not tab.used then
      b:Hide()
    else
      b:ClearAllPoints()
      b:SetPoint("BOTTOMLEFT", W.bar, "BOTTOMLEFT", x, 0)
      b.spec.label = tabTitle(tab.def) .. (tab.quiet and (" " .. L["(quiet)"]) or "")
      b.spec.kind = tabKind(tab.def)
      b:Show()
      x = x + b:GetWidth() + 2
    end
    paintTab(tab)
  end
  W.plus:ClearAllPoints()
  W.plus:SetPoint("BOTTOMLEFT", W.bar, "BOTTOMLEFT", x + 2, 1)
  fitWidth(W, x)
end

function View.Select(id)
  local tab = byId[id]
  if not tab then
    return
  end
  local W = wins[tab.wid]
  if W.current and W.current ~= tab and W.current.frame then
    W.current.frame:Hide()
  end
  W.current = tab
  tab.unread = nil
  if W.filterQ or tab.filteredBy then
    View.ApplyFilter(W)
  end
  tab.frame:Show()
  if not tab.def.whisper then
    profile().selected[W.id] = id
  end
  for _, t in ipairs(W.tabs) do
    paintTab(t)
  end
end

-- The selected tab of the main window (or of window `wid`).
function View.Current(wid)
  local W = wins[wid or View.MAIN]
  return W and W.current and W.current.def.id or nil
end

function View.Tabs(wid)
  local W = wins[wid or View.MAIN]
  return W and W.tabs or {}
end

function View.Tab(id)
  return byId[id]
end

function View.Window(wid)
  return wins[wid or View.MAIN]
end

-- The ids of the windows that show, the main window first.
function View.Windows()
  local out = {}
  if wins[View.MAIN] then
    out[1] = View.MAIN
  end
  for wid, W in pairs(wins) do
    if wid ~= View.MAIN and not W.empty then
      out[#out + 1] = wid
    end
  end
  return out
end

local function onLink(frame, link, text, button)
  View.OnLink(frame, link, text, button)
end

local function newArea(W)
  local f = CreateFrame("ScrollingMessageFrame", nil, W.area)
  f:SetPoint("TOPLEFT", 6, -4)
  f:SetPoint("BOTTOMRIGHT", -6, 4)
  f:SetFontObject(Compat.ChatFont())
  applyFont(f)
  f:SetJustifyH("LEFT")
  f:SetMaxLines(View.MAX_LINES)
  f:SetFading(profile().fade)
  f:SetTimeVisible(120)
  f:SetHyperlinksEnabled(true)
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(self, delta)
    if IsShiftKeyDown() then
      if delta > 0 then
        self:ScrollToTop()
      else
        self:ScrollToBottom()
      end
    elseif delta > 0 then
      self:ScrollUp()
    else
      self:ScrollDown()
    end
  end)
  f:SetScript("OnHyperlinkClick", onLink)
  f:Hide()
  return f
end

-- The tab dragged right now, and the ghost that follows the cursor while it is (no OnUpdate else).
local dragging

local function cursor()
  local x, y = GetCursorPosition()
  local s = UIParent:GetEffectiveScale()
  return x / s, y / s
end

local function followCursor(self)
  local x, y = cursor()
  self:ClearAllPoints()
  self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
end

local function ghostFrame()
  if not ghost then
    ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetSize(90, View.TAB_H)
    ghost:SetFrameStrata("TOOLTIP")
    ghost.bg = S.fill(ghost, S.C.header)
    ghost.bg:SetAlpha(0.9)
    ghost.label = S.text(ghost, 12, S.C.headerText)
    ghost.label:SetPoint("CENTER")
    ghost:Hide()
  end
  return ghost
end

local function newButton(tab)
  local b = S.tab(UIParent, { kind = tabKind(tab.def), label = tabTitle(tab.def) })
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      View.TabMenu(tab.def.id)
    else
      View.Select(tab.def.id)
    end
  end)
  b:SetScript("OnDragStart", function()
    View.BeginDrag(tab.def.id)
  end)
  b:SetScript("OnDragStop", function()
    View.EndDrag()
  end)
  b.tip = L["Drag to move the tab; right click for more"]
  b:SetScript("OnEnter", S.TipEnter)
  b:SetScript("OnLeave", S.TipLeave)
  return b
end

local function attach(tab, W, index)
  tab.wid = W.id
  tab.frame:SetParent(W.area)
  tab.frame:ClearAllPoints()
  tab.frame:SetPoint("TOPLEFT", 6, -4)
  tab.frame:SetPoint("BOTTOMRIGHT", -6, 4)
  tab.frame:Hide()
  tab.button:SetParent(W.bar)
  index = math.max(1, math.min(index or (#W.tabs + 1), #W.tabs + 1))
  table.insert(W.tabs, index, tab)
end

local function detach(tab)
  local W = wins[tab.wid]
  for i, t in ipairs(W.tabs) do
    if t == tab then
      table.remove(W.tabs, i)
      break
    end
  end
  if W.current == tab then
    W.current = nil
  end
  tab.frame:Hide()
  return W
end

local function buildTab(def, W, index)
  local tab = byId[def.id]
  if tab then
    return tab
  end
  tab = { def = def, words = Model.Words(def.words), folds = {} }
  byId[def.id] = tab
  tab.frame = newArea(W)
  tab.button = newButton(tab)
  attach(tab, W, index)
  return tab
end

-- Which tab sits in which window, kept in the profile (whisper tabs are the character's own).
local function saveLayout()
  local p = profile()
  local layout = {}
  for wid, W in pairs(wins) do
    if not W.empty then
      local ids = {}
      for _, tab in ipairs(W.tabs) do
        if not tab.def.whisper then
          ids[#ids + 1] = tab.def.id
        end
      end
      if #ids > 0 or wid == View.MAIN then
        layout[wid] = ids
      end
    end
  end
  p.layout = layout
end

-- A tab of the model's shape ({ id, title, cats } or a whisper tab) into window `wid` (default the
-- main window); returns the live tab.
function View.AddTab(def, wid)
  if byId[def.id] then
    return byId[def.id]
  end
  local W = wins[wid or View.MAIN]
  local tab = buildTab(def, W)
  layoutTabs(W)
  if not W.current then
    View.Select(def.id)
  end
  return tab
end

-- A new tab (a preset or the editor's) into the profile and window `wid`; selected.
function View.CreateTab(def, wid)
  local p = profile()
  def.id = Model.NewTabId(p.tabs)
  p.tabs[def.id] = def
  local W = wins[wid] and not wins[wid].empty and wins[wid] or wins[View.MAIN]
  buildTab(def, W)
  layoutTabs(W)
  View.Select(def.id)
  saveLayout()
  return def.id
end

local function closeWindow(W)
  if W.id == View.MAIN then
    return
  end
  if W.filterRow and W.filterRow:IsShown() then
    View.ToggleFilter(W.id, false)
  end
  W.win:Hide()
  W.empty = true
  W.current = nil
  profile().places[W.id] = nil
end

-- A free window id: an emptied window is used again (frames are never thrown away).
local function freeWindowId()
  for wid, W in pairs(wins) do
    if W.empty then
      return wid
    end
  end
  local i = 2
  while wins["w" .. i] do
    i = i + 1
  end
  return "w" .. i
end

local newWindow -- below

-- Tab `id` into window `toWid` at `index` (default: the end). The main window keeps one tab at
-- least; a window that loses its last tab closes. Returns true when moved.
function View.MoveTab(id, toWid, index)
  local tab = byId[id]
  if not tab then
    return false
  end
  local from = wins[tab.wid]
  if from.id == View.MAIN and toWid ~= View.MAIN and #from.tabs <= 1 then
    B:Say(L["The main window keeps at least one tab."])
    return false
  end
  local to = newWindow(toWid)
  local wasCurrent = from.current == tab
  if from == to then
    local old
    for i, t in ipairs(to.tabs) do
      if t == tab then
        old = i
      end
    end
    if old and index and index > old then
      index = index - 1 -- the list is one shorter once the tab is out
    end
  end
  detach(tab)
  attach(tab, to, index)
  if from ~= to then
    if #from.tabs == 0 then
      closeWindow(from)
    else
      if wasCurrent or not from.current then
        View.Select(firstShown(from).def.id)
      end
      layoutTabs(from)
    end
    to.win:Show()
  end
  layoutTabs(to)
  View.Select(id)
  saveLayout()
  return true
end

-- Tab `id` into a window of its own; `pos` the window's TOPLEFT offset { x, y } from UIParent's.
function View.OwnWindow(id, pos)
  local tab = byId[id]
  if not tab then
    return nil
  end
  local wid = freeWindowId()
  local place = profile().places[wid] or (wins[wid] and wins[wid].win.db) or {}
  profile().places[wid] = place
  if pos then
    place.pos = pos
  elseif not place.pos then
    local main = wins[View.MAIN].win.frame
    local left, top = main:GetLeft(), main:GetTop()
    if left and top then
      place.pos = { left + 40, top + 40 - UIParent:GetHeight() }
    end
  end
  if wins[wid] then
    wins[wid].empty = nil
    wins[wid].win.db = place
    wins[wid].win:RestorePlace()
  end
  if not View.MoveTab(id, wid, 1) then
    if wins[wid] and #wins[wid].tabs == 0 then
      closeWindow(wins[wid])
    end
    return nil
  end
  return wid
end

-- A window's tabs back into the main window, in their order; the window closes (owner, retail
-- 31.10.2026: dragging a tab window onto the main window docks it, its close button too).
function View.Dock(wid)
  local W = wins[wid]
  if not W or wid == View.MAIN or W.empty then
    return false
  end
  local ids = {}
  for _, tab in ipairs(W.tabs) do
    ids[#ids + 1] = tab.def.id
  end
  for _, id in ipairs(ids) do
    View.MoveTab(id, View.MAIN)
  end
  if not W.empty then
    closeWindow(W)
  end
  saveLayout()
  return true
end

-- The close button of a tab window: the tabs go back to the main window; with Ctrl they are
-- deleted (the fixed ones and whisper tabs still go back, a whisper tab closes).
function View.CloseWindow(wid, delete)
  local W = wins[wid]
  if not W or wid == View.MAIN then
    return false
  end
  if delete then
    local ids = {}
    for _, tab in ipairs(W.tabs) do
      ids[#ids + 1] = tab.def.id
    end
    for _, id in ipairs(ids) do
      local tab = byId[id]
      if tab.def.whisper then
        View.CloseTab(id)
      elseif not tab.def.fixed then
        View.DeleteTab(id)
      end
    end
  end
  if not W.empty then
    View.Dock(wid)
  end
  return true
end

function View.BeginDrag(id)
  local tab = byId[id]
  if not tab then
    return
  end
  dragging = tab
  local g = ghostFrame()
  g.label:SetText(tabTitle(tab.def))
  g:SetScript("OnUpdate", followCursor)
  followCursor(g)
  g:Show()
end

-- Where the cursor is: a window's tab bar ("bar"), a window ("window"), or nothing.
local function dropTarget()
  for _, wid in ipairs(View.Windows()) do
    local W = wins[wid]
    if W.win.frame:IsShown() and W.bar:IsMouseOver() then
      return W, "bar"
    end
  end
  for _, wid in ipairs(View.Windows()) do
    local W = wins[wid]
    if W.win.frame:IsShown() and W.win.frame:IsMouseOver() then
      return W, "window"
    end
  end
  return nil
end

-- The place in W.tabs for a drop at the cursor: after every shown tab whose middle lies left of it.
local function dropIndex(W, tab)
  local x = GetCursorPosition() / (W.bar:GetEffectiveScale() or 1) -- in the bar's own scale
  local index = 1
  for i, t in ipairs(W.tabs) do
    if t ~= tab and t.button:IsShown() then
      local left, width = t.button:GetLeft(), t.button:GetWidth()
      if left and width and x > left + width / 2 then
        index = i + 1
      end
    end
  end
  return index
end

function View.EndDrag()
  local tab = dragging
  dragging = nil
  if ghost then
    ghost:SetScript("OnUpdate", nil)
    ghost:Hide()
  end
  if not tab then
    return
  end
  local W, where = dropTarget()
  if W and where == "bar" then
    View.MoveTab(tab.def.id, W.id, dropIndex(W, tab))
  elseif W then
    if W.id ~= tab.wid then
      View.MoveTab(tab.def.id, W.id)
    end
  else
    local from = wins[tab.wid]
    if from.id ~= View.MAIN and #from.tabs == 1 then
      return -- the only tab of its window: the window stays where it is
    end
    local x, y = cursor()
    View.OwnWindow(tab.def.id, { x - 40, y + 10 - UIParent:GetHeight() })
  end
end

function View.CloseTab(id)
  local tab = byId[id]
  if not tab or not tab.def.whisper then
    return
  end
  local W = detach(tab)
  byId[id] = nil
  tab.button:Hide()
  ns.Chat.ForgetWhisper(tab.def.partner)
  if #W.tabs == 0 then
    closeWindow(W)
  else
    if not W.current then
      View.Select(firstShown(W).def.id)
    end
    layoutTabs(W)
  end
end

function View.DeleteTab(id)
  local tab = byId[id]
  if not tab or tab.def.fixed or tab.def.whisper then
    return false
  end
  if tab.wid == View.MAIN and #wins[View.MAIN].tabs <= 1 then
    B:Say(L["The main window keeps at least one tab."])
    return false
  end
  local W = detach(tab)
  byId[id] = nil
  tab.button:Hide()
  profile().tabs[id] = nil
  db().char.scrollback[id] = nil
  if #W.tabs == 0 then
    closeWindow(W)
  else
    if not W.current then
      View.Select(firstShown(W).def.id)
    end
    layoutTabs(W)
  end
  saveLayout()
  return true
end

function View.ClearTab(id)
  local tab = byId[id]
  if tab then
    call(tab.frame, "Clear")
    tab.folds = {}
    db().char.scrollback[id] = nil
  end
end

-- Quiet: no lines, no light, no sound until `minutes` pass, or ("instance") until an instance is
-- left (Chat.OnZone ends it); nil ends it now.
function View.SetQuiet(id, minutes)
  local tab = byId[id]
  if not tab then
    return
  end
  if minutes == "instance" then
    tab.quiet = { instance = true, inside = Compat.InstanceKind() ~= nil }
  elseif minutes then
    tab.quiet = { untilAt = GetTime() + minutes * 60 }
  else
    tab.quiet = nil
  end
  layoutTabs(wins[tab.wid])
end

-- An instance was entered or left: "until the instance is left" ends on the way out.
function View.OnZone(inside)
  for id, tab in pairs(byId) do
    local q = tab.quiet
    if q and q.instance then
      if inside then
        q.inside = true
      elseif q.inside then
        View.SetQuiet(id, nil)
      end
    end
  end
end

local function isQuiet(tab)
  local q = tab.quiet
  if not q then
    return false
  end
  if q.untilAt and GetTime() >= q.untilAt then
    tab.quiet = nil
    layoutTabs(wins[tab.wid])
    return false
  end
  return true
end

function View.TabMenu(id)
  local tab = byId[id]
  if not tab then
    return nil
  end
  local def = tab.def
  local items = {}
  local function add(label, onClick)
    items[#items + 1] = { label = label, onClick = onClick }
  end
  if not def.whisper then
    add(L["Edit tab"], function()
      View.EditTab(id)
    end)
  end
  add(L["Copy lines"], function()
    View.CopyTab(id)
  end)
  add(L["Clear lines"], function()
    View.ClearTab(id)
  end)
  if tab.quiet then
    add(L["End the quiet"], function()
      View.SetQuiet(id, nil)
    end)
  else
    for _, m in ipairs(View.QUIET) do
      add(string.format(L["Quiet for %d minutes"], m), function()
        View.SetQuiet(id, m)
      end)
    end
    add(L["Quiet until the instance is left"], function()
      View.SetQuiet(id, "instance")
    end)
  end
  if tab.wid == View.MAIN then
    add(L["Own window"], function()
      View.OwnWindow(id)
    end)
  else
    add(L["Back to the main window"], function()
      View.MoveTab(id, View.MAIN)
    end)
  end
  if def.whisper then
    add(L["Close tab"], function()
      View.CloseTab(id)
    end)
  elseif not def.fixed then
    add(L["Delete tab"], function()
      View.DeleteTab(id)
    end)
  end
  B.UI.Menu(nil, tabTitle(def), items, ns.mod)
  return items
end

-- The `+` of a tab bar: the presets and the editor.
function View.PlusMenu(anchor, wid)
  local items = {
    {
      label = L["New tab..."],
      onClick = function()
        View.EditTab(nil, wid)
      end,
    },
  }
  for _, preset in ipairs(Model.PRESETS) do
    items[#items + 1] = {
      label = L[preset.title],
      onClick = function()
        View.CreateTab(Model.CopyDef(preset), wid)
      end,
    }
  end
  B.UI.Menu(anchor, L["A new tab"], items, ns.mod)
  return items
end

-- ---------------------------------------------------------------------------------------------
-- The tab editor
-- ---------------------------------------------------------------------------------------------

local CHANNEL_ROWS = 5

local function buildEditor()
  local Wd = B.UI.Widgets
  local w = B.UI.Window("BastiansChatTabEditor", {
    module = "Chat",
    title = L["Tab"],
    width = 440,
    height = 620,
    minWidth = 420,
    minHeight = 600,
    db = profile().editor,
  })
  local c = w.content
  local y = -10
  -- what a tab is
  w.intro = S.text(c, 11, S.C.dim)
  w.intro:SetPoint("TOPLEFT", c, "TOPLEFT", 12, y)
  w.intro:SetPoint("RIGHT", c, "RIGHT", -12, 0)
  w.intro:SetJustifyH("LEFT")
  w.intro:SetText(
    L["A tab shows the kinds of lines and channels you tick; filters narrow them. Save makes it."]
  )
  y = y - 34
  local function row(widget, h)
    widget:SetPoint("TOPLEFT", c, "TOPLEFT", 12, y)
    widget:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    y = y - (h or 24)
  end
  w.name = Wd.Edit(c, L["Name of the tab"])
  w.name:SetHeight(20)
  row(w.name, 30)
  row(Wd.Header(c, L["Takes these lines"]), 26)
  w.cats = {}
  for i, cat in ipairs(Model.CATS) do
    local cb = Wd.Checkbox(c, L[Model.CAT_LABELS[cat]])
    cb:SetPoint("TOPLEFT", c, "TOPLEFT", 12 + ((i - 1) % 2) * 205, y - math.floor((i - 1) / 2) * 22)
    cb:SetWidth(200)
    w.cats[cat] = cb
  end
  y = y - math.ceil(#Model.CATS / 2) * 22 - 6
  row(Wd.Header(c, L["Channels"]), 26)
  w.chanTop = y
  w.chans = {}
  w.chanNote = S.text(c, 11, S.C.dim)
  w.chanNote:SetPoint("TOPLEFT", c, "TOPLEFT", 12, y)
  w.chanNote:SetText(L["No channel joined."]) -- never shown now: the game's own are offered
  y = y - CHANNEL_ROWS * 22 - 4
  row(Wd.Header(c, L["Filters"]), 26)
  w.words = Wd.Edit(c, L["Searches, comma separated (hover for the syntax)"])
  w.words:SetHeight(20)
  Model.FilterBox(w.words)
  row(w.words, 28)
  w.only = Wd.Checkbox(c, L["Only here: the lines leave the other tabs"])
  row(w.only, 22)
  w.keep = Wd.Checkbox(c, L["Keep the lines after logout (never the game's public channels)"])
  row(w.keep, 22)
  local sounds = {}
  for _, s in ipairs(Compat.SOUND_NAMES) do
    sounds[s] = L["sound: " .. s]
  end
  w.sound = Wd.Select(c, L["Sound on a new line"], sounds)
  row(w.sound, 30)
  -- Save and Cancel on their own line under everything (they overlapped
  -- the sound's choice)
  w.save = S.button(c, L["Save"], 90, 22, true)
  w.save:SetPoint("TOPRIGHT", c, "TOPRIGHT", -12, y - 10)
  w.save:SetScript("OnClick", function()
    View.SaveEditor()
  end)
  w.cancel = S.button(c, L["Cancel"], 90, 22)
  w.cancel:SetPoint("RIGHT", w.save, "LEFT", -8, 0)
  w.cancel:SetScript("OnClick", function()
    w:Hide()
  end)
  return w
end

-- Opens the editor on tab `id`, or (nil) on a new tab for window `wid`.
function View.EditTab(id, wid)
  editor = editor or buildEditor()
  local Wd = B.UI.Widgets
  local def = id and byId[id] and byId[id].def or { cats = {}, channels = {} }
  editor.editing = id
  editor.wid = wid
  editor.name:SetText(id and tabTitle(def) or "")
  for cat, cb in pairs(editor.cats) do
    cb:SetChecked(def.cats and def.cats[cat])
  end
  for _, cb in ipairs(editor.chans) do
    cb:Hide()
  end
  local channels = Compat.ChannelChoices()
  for i, ch in ipairs(channels) do
    if i > CHANNEL_ROWS * 2 then
      break
    end
    local cb = editor.chans[i]
    if not cb then
      cb = Wd.Checkbox(editor.content, "")
      cb:SetWidth(200)
      cb:SetPoint(
        "TOPLEFT",
        editor.content,
        "TOPLEFT",
        12 + ((i - 1) % 2) * 205,
        editor.chanTop - math.floor((i - 1) / 2) * 22
      )
      editor.chans[i] = cb
    end
    -- a game channel not joined goes by its name in the client's language (the locale's)
    cb.channel = ch.id and ch.name or L[ch.name]
    cb.label:SetText(ch.id and (ch.id .. ". " .. ch.name) or cb.channel)
    cb:SetChecked(def.channels and def.channels[ch.name])
    cb:Show()
  end
  editor.chanNote:SetShown(#channels == 0)
  editor.words:SetText(def.words or "")
  editor.only:SetChecked(def.only)
  editor.keep:SetChecked(def.keep ~= false)
  editor.sound:SetValue(def.sound or "none")
  editor:Show()
  return editor
end

function View.SaveEditor()
  if not editor then
    return nil
  end
  local name = strtrim(editor.name:GetText() or "")
  local cats, channels = {}, {}
  for cat, cb in pairs(editor.cats) do
    cats[cat] = cb:GetChecked() or nil
  end
  for _, cb in ipairs(editor.chans) do
    if cb:IsShown() and cb:GetChecked() then
      channels[cb.channel] = true
    end
  end
  local tab = editor.editing and byId[editor.editing]
  local def = tab and tab.def or {}
  if name ~= "" and name ~= tabTitle(def) then
    def.title, def.named = name, true
  elseif not def.title then
    def.title, def.named = L["New tab"], true
  end
  def.cats, def.channels = cats, channels
  local words = strtrim(editor.words:GetText() or "")
  def.words = words ~= "" and words or nil
  def.only = editor.only:GetChecked() or nil
  def.keep = editor.keep:GetChecked() and nil or false
  local sound = editor.sound:GetValue()
  def.sound = sound ~= "none" and sound or nil
  editor:Hide()
  if tab then
    tab.words = Model.Words(def.words)
    layoutTabs(wins[tab.wid])
    return def.id
  end
  return View.CreateTab(def, editor.wid)
end

-- ---------------------------------------------------------------------------------------------
-- Lines
-- ---------------------------------------------------------------------------------------------

-- The text a line shows: short channel names, item icons, web addresses as links, the time stamp;
-- a dimmed line (spam, ADR 0042 §7) as plain grey text. A secret text is shown as it came.
function View.Decorate(line)
  local text = line.text
  if line.secret or type(text) ~= "string" then
    return text
  end
  local p = profile()
  if line.dim then
    text = S.H.muted .. Model.Strip(text) .. "|r"
  else
    text = Model.ShortChannels(text, p.shortChannels)
    if p.itemIcons then
      text = Model.ItemIcons(text, Compat.ItemIcon)
    end
    text = Model.Linkify(text, S.H.chat)
  end
  local stamp = Model.Stamp(p.stamps, line.at)
  if stamp then
    text = S.H.tipDim .. stamp .. "|r" .. text
  end
  return text
end

-- A tab's lines as shown, for the window's filter: { text, r, g, b, line }, at most MAX_LINES.
local function remember(tab, text, line)
  local lines = tab.lines or {}
  tab.lines = lines
  lines[#lines + 1] = { text = text, r = line.r, g = line.g, b = line.b, line = line }
  if #lines > View.MAX_LINES then
    table.remove(lines, 1)
  end
end

-- Does a line pass its window's filter (the current tab only)?
local function passes(tab, line)
  local W = wins[tab.wid]
  local q = W and W.filterQ
  if not q or tab ~= W.current then
    return true
  end
  local plain = line.plain or string.lower(Model.Strip(line.text or "") or "")
  return not line.secret and q:MatchLower(plain, line)
end

local function show(tab, line)
  if not tab.frame or isQuiet(tab) then
    return false
  end
  local text = View.Decorate(line)
  remember(tab, text, line)
  if passes(tab, line) then
    local ok = pcall(tab.frame.AddMessage, tab.frame, text, line.r, line.g, line.b, line.foldKey)
    if not ok then
      ns.Chat.Note("show")
    end
  end
  if line.foldKey then
    tab.folds[line.foldKey] = text
  end
  local W = wins[tab.wid]
  if W and tab ~= W.current then
    tab.unread = true
    paintTab(tab)
  end
  local sound = tab.def.sound
  if sound and not line.own and (GetTime() - (lastSound[tab.def.id] or -100)) >= View.SOUND_GAP then
    lastSound[tab.def.id] = GetTime()
    Compat.PlaySound(sound)
  end
  return true
end

-- A captured line into every tab that takes it. A tab marked "only here" takes it from the others;
-- whisper tabs open on the first whisper when whispers go to tabs.
function View.Add(line)
  local p = profile()
  local toTabs = p.whisperTo ~= "messenger"
  if toTabs and line.cat == "whisper" and line.partner and not byId["w:" .. line.partner] then
    View.AddTab(Model.WhisperTab(line.partner))
    ns.Chat.RememberWhisper(line.partner)
  end
  if line.cat == "bnet" and byId.bnet and not byId.bnet.used then
    byId.bnet.used = true
    layoutTabs(wins[byId.bnet.wid])
  end
  local takers, only = {}, false
  for _, W in pairs(wins) do
    if not W.empty then
      for _, tab in ipairs(W.tabs) do
        if (toTabs or not tab.def.whisper) and Model.Takes(tab.def, line, tab.words) then
          takers[#takers + 1] = tab
          only = only or tab.def.only == true
        end
      end
    end
  end
  for _, tab in ipairs(takers) do
    if (not only or tab.def.only or tab.def.whisper) and show(tab, line) then
      ns.Chat.Keep(tab.def.id, line)
    end
  end
  local main = wins[View.MAIN]
  if toTabs and line.cat == "whisper" and main and not main.win:IsShown() and p.showOnWhisper then
    main.win:Show()
  end
end

-- S3: a repeat folds into the line it repeats, which now says " x3" (where the client's message
-- frame can rewrite a shown line: TransformMessages, retail family).
function View.Fold(key, count)
  for _, tab in pairs(byId) do
    local base = tab.folds[key]
    if base and tab.frame then
      local mark = base .. S.H.tipDim .. " x" .. tostring(count) .. "|r"
      call(tab.frame, "TransformMessages", function(_, _, _, _, k)
        return k == key
      end, function(_, r, g, b, k)
        return mark, r, g, b, k
      end)
    end
  end
end

-- The rules again over every tab's kept lines (Chat.Refilter): `judge(line)` answers the verdict
-- or nil. A line taken (junk, hide) leaves the tab and the saved scrollback, a dimmed one is
-- drawn dim; a tab with a change is drawn again. Returns the lines taken, each once.
function View.Refilter(judge)
  local taken, seen = {}, {}
  for _, tab in pairs(byId) do
    local changed = false
    local lines = tab.lines or {}
    for i = #lines, 1, -1 do
      local l = lines[i]
      local line = l.line
      local verdict = line and not line.dim and judge(line) or nil
      if verdict and verdict.action == "dim" then
        line.dim = true
        l.text = View.Decorate(line)
        changed = true
      elseif verdict and verdict.action ~= "fold" then
        table.remove(lines, i)
        ns.Chat.Unkeep(tab.def.id, line)
        changed = true
        if not seen[line] then
          seen[line] = true
          taken[#taken + 1] = line
        end
      end
    end
    if changed then
      redraw(tab, tab.filteredBy)
    end
  end
  return taken
end

-- The kept lines of every tab, shown again after a /reload or a login.
function View.Replay(scrollback)
  for id, tab in pairs(byId) do
    for _, l in ipairs(scrollback[id] or {}) do
      local text = View.Decorate(l)
      remember(tab, text, l)
      pcall(tab.frame.AddMessage, tab.frame, text, l.r, l.g, l.b)
    end
  end
end

-- ---------------------------------------------------------------------------------------------
-- The filter of a window's current tab ("a real time filter on the
-- current tab - only leaves messages with the filter"; ADR 0045's syntax with from:, in:, has:)
-- ---------------------------------------------------------------------------------------------

-- The tab's frame again from its lines: those that match `q`, or all (q nil).
redraw = function(tab, q)
  if not tab.frame then
    return
  end
  call(tab.frame, "Clear")
  for _, l in ipairs(tab.lines or {}) do
    local line = l.line
    local plain = line.plain or string.lower(Model.Strip(line.text or "") or "")
    if not q or (not line.secret and q:MatchLower(plain, line)) then
      pcall(tab.frame.AddMessage, tab.frame, l.text, l.r, l.g, l.b, line.foldKey)
    end
  end
  tab.filteredBy = q
end

-- The window's filter onto its tabs: the current one filtered, the others whole again.
function View.ApplyFilter(W)
  for _, tab in ipairs(W.tabs) do
    local want = tab == W.current and W.filterQ or nil
    if tab.filteredBy ~= want then
      redraw(tab, want)
    end
  end
end

-- The filter text of window `wid` ("" or nil ends it); the count of shown lines in the box.
function View.SetFilter(wid, text)
  local W = wins[wid or View.MAIN]
  if not W then
    return nil
  end
  local q = B.Query.Compile(text or "", { fields = Model.FIELDS })
  W.filterQ = not q.empty and q or nil
  View.ApplyFilter(W)
  local n
  if W.filterQ and W.current then
    n = 0
    for _, l in ipairs(W.current.lines or {}) do
      local line = l.line
      local plain = line.plain or string.lower(Model.Strip(line.text or "") or "")
      if not line.secret and W.filterQ:MatchLower(plain, line) then
        n = n + 1
      end
    end
  end
  if W.filterBox and W.filterBox.count then
    W.filterBox.count:SetText(n and tostring(n) or "")
  end
  return n
end

-- The filter row under the tab bar, shown and hidden with the bar's Filter button.
function View.ToggleFilter(wid, on)
  local W = wins[wid or View.MAIN]
  if not W then
    return
  end
  if on == nil then
    on = not W.filterRow:IsShown()
  end
  W.filterRow:SetShown(on)
  W.area:ClearAllPoints()
  W.area:SetPoint("TOPLEFT", on and W.filterRow or W.bar, "BOTTOMLEFT", on and 0 or 2, 0)
  W.area:SetPoint(
    "BOTTOMRIGHT",
    W.win.content,
    "BOTTOMRIGHT",
    -2,
    W.id == View.MAIN and (View.INPUT_H + 2) or 2
  )
  if on then
    W.filterBox:SetFocus()
  else
    W.filterBox:SetText("")
    View.SetFilter(W.id, "")
  end
end

-- ---------------------------------------------------------------------------------------------
-- Links and the name menu
-- ---------------------------------------------------------------------------------------------

function View.NameMenu(name)
  local items = {
    {
      label = L["Whisper"],
      onClick = function()
        Compat.OpenChat("/w " .. name .. " ")
      end,
    },
    {
      label = L["Invite"],
      onClick = function()
        Compat.Invite(name)
      end,
    },
    {
      label = L["Add friend"],
      onClick = function()
        Compat.AddFriend(name)
      end,
    },
    {
      label = L["Ignore"],
      onClick = function()
        Compat.Ignore(name)
      end,
    },
    {
      label = L["Who is this?"],
      onClick = function()
        Compat.Who(name)
      end,
    },
    {
      label = L["Copy name"],
      onClick = function()
        View.Copy(name)
      end,
    },
    {
      label = L["Block in Bastian's Chat"],
      onClick = function()
        ns.Chat.BlockSender(name)
      end,
    },
  }
  B.UI.Menu(nil, Model.ShortName(name), items, ns.mod)
  return items
end

function View.OnLink(frame, link, text, button)
  local kind = type(link) == "string" and link:match("^(%a+):") or nil
  if kind == "player" then
    local name = link:match("^player:([^:]+)")
    if not name then
      return
    end
    if button == "RightButton" then
      View.NameMenu(name)
    elseif IsShiftKeyDown() then
      Compat.InsertLink(name)
    elseif IsAltKeyDown() and profile().altInvite then
      Compat.Invite(name)
    else
      Compat.OpenChat("/w " .. name .. " ")
    end
  elseif kind == "addon" and link:sub(1, #Model.URL_LINK) == Model.URL_LINK then
    View.Copy(link:sub(#Model.URL_LINK + 1))
  elseif Compat.IsLinkClick() and Compat.InsertLink(text) then
    return
  else
    Compat.ItemRef(link, text, button, frame)
  end
end

-- ---------------------------------------------------------------------------------------------
-- The copy box: the text selected, Ctrl+C copies (the game gives addons no clipboard)
-- ---------------------------------------------------------------------------------------------

function View.Copy(text)
  if not copyWin then
    copyWin = B.UI.Window("BastiansChatCopy", {
      module = "Chat",
      title = L["Copy: Ctrl+C, then Escape"],
      width = 520,
      height = 300,
      db = profile().copy,
    })
    local scroll = CreateFrame("ScrollFrame", nil, copyWin.content)
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -8, 8)
    copyEdit = CreateFrame("EditBox", nil, scroll)
    copyEdit:SetMultiLine(true)
    copyEdit:SetAutoFocus(false)
    copyEdit:SetFontObject(Compat.ChatFont())
    copyEdit:SetWidth(500)
    S.ink(copyEdit, S.C.text)
    copyEdit:SetScript("OnEscapePressed", function()
      copyWin:Hide()
    end)
    scroll:SetScrollChild(copyEdit)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
      local v = (self:GetVerticalScroll() or 0) - delta * 40
      self:SetVerticalScroll(math.max(0, math.min(v, self:GetVerticalScrollRange() or 0)))
    end)
    copyWin.scroll = scroll
  end
  copyEdit:SetWidth(math.max(200, (copyWin.content:GetWidth() or 520) - 20))
  copyEdit:SetText(text or "")
  copyWin:Show()
  copyEdit:SetFocus()
  copyEdit:HighlightText()
  return copyEdit
end

-- The lines of tab `id` (default: the main window's selected tab) as plain text.
function View.CopyTab(id)
  local tab = byId[id or View.Current() or ""]
  if not tab then
    return nil
  end
  local out = {}
  for i = 1, tab.frame:GetNumMessages() do
    local text = tab.frame:GetMessageInfo(i)
    if type(text) == "string" and not Compat.IsSecret(text) then
      out[#out + 1] = Model.Strip(text)
    end
  end
  return View.Copy(table.concat(out, "\n"))
end

-- ---------------------------------------------------------------------------------------------
-- The bar for long texts: one part per Enter (a part sent by a timer is blocked, CH0)
-- ---------------------------------------------------------------------------------------------

local SPLITTABLE = {
  SAY = true,
  YELL = true,
  EMOTE = true,
  PARTY = true,
  RAID = true,
  RAID_WARNING = true,
  INSTANCE_CHAT = true,
  GUILD = true,
  OFFICER = true,
  WHISPER = true,
  CHANNEL = true,
}

local function noteLong()
  if long then
    longNote:SetText(
      string.format(L["Long text: Enter sends part %d of %d, Escape stops"], long.next, #long.parts)
    )
  end
end

-- A one-line hint above the input bar (the history search), gone after a few seconds.
function View.Hint(text)
  if not longNote then
    return
  end
  longNote:SetText(text or "")
  longNote:Show()
  local shown = text
  C_Timer.After(4, function()
    if longNote:GetText() == shown and not long then
      longNote:Hide()
    end
  end)
end

function View.TakeLong(text, chatType, target)
  if not SPLITTABLE[chatType] then
    B:Say(L["Long texts cannot be sent in this chat; shorten it to 255 characters."])
    return false
  end
  long = { parts = Model.Split(text), next = 1, chatType = chatType, target = target }
  longBox:SetText(long.parts[1])
  longBox:Show()
  longNote:Show()
  noteLong()
  wins[View.MAIN].win:Show()
  longBox:SetFocus()
  return true
end

function View.SendLongPart()
  if not long then
    longBox:ClearFocus()
    longBox:Hide()
    longNote:Hide()
    return
  end
  local part = long.parts[long.next]
  Compat.SendChat(part, long.chatType, long.target)
  long.next = long.next + 1
  if long.next > #long.parts then
    long = nil
    longBox:SetText("")
    longBox:ClearFocus()
    longBox:Hide()
    longNote:Hide()
  else
    longBox:SetText(long.parts[long.next])
    noteLong()
  end
end

function View.Long()
  return long
end

-- ---------------------------------------------------------------------------------------------
-- The windows
-- ---------------------------------------------------------------------------------------------

-- On the first start the main window takes the place of the game's chat.
local function firstPlace(wdb)
  local game = Compat.MainChatFrame()
  if wdb.pos or not game then
    return
  end
  local left, top = game:GetLeft(), game:GetTop()
  local w, h = game:GetWidth(), game:GetHeight()
  if left and top and w and h then
    wdb.pos = { left, top + View.TAB_H + 24 - UIParent:GetHeight() }
    wdb.size = { math.max(320, w + 12), math.max(160, h + View.TAB_H + View.INPUT_H + 36) }
  end
end

local function buildLongBar(W)
  local content = W.win.content
  longBox = CreateFrame("EditBox", nil, content)
  longBox:SetPoint("BOTTOMLEFT", 4, 2)
  longBox:SetPoint("BOTTOMRIGHT", -20, 2)
  longBox:SetHeight(View.INPUT_H - 4)
  longBox:SetFontObject(Compat.ChatFont())
  longBox:SetAutoFocus(false)
  longBox:SetMaxLetters(0)
  longBox:SetFrameLevel((content:GetFrameLevel() or 1) + 20) -- above the game's bar
  S.ink(longBox, S.C.tipText)
  local lg = longBox:CreateTexture(nil, "BACKGROUND")
  lg:SetTexture(View.GROUND, true, true)
  lg:SetAllPoints()
  longBox:SetScript("OnEnterPressed", View.SendLongPart)
  longBox:SetScript("OnEscapePressed", function()
    long = nil
    View.SendLongPart()
  end)
  longBox:Hide()
  longNote = S.text(content, 11, S.C.tipDim)
  longNote:SetPoint("BOTTOMLEFT", longBox, "TOPLEFT", 2, 4)
  longNote:Hide()
end

-- The Messenger button in the main window's header, with the unread count.
function View.MessengerCount(n)
  n = n or 0
  local W = wins[View.MAIN]
  if W and W.msgButton then
    W.msgButton:SetBadge(n)
    W.msgButton.tip = n > 0 and string.format(L["Messenger (%d)"], n) or L["Your whispers as conversations"]
  end
  if B.UI.Launcher and B.UI.Launcher.SetBadge then
    B.UI.Launcher.SetBadge("ChatMessenger", n) -- the Messenger's minimap button
  end
end

-- The Junk button of the main window's tab bar, with the count of filtered lines.
function View.JunkCount(n)
  local W = wins[View.MAIN]
  if W and W.junk then
    W.junk:SetBadge(n or 0)
    W.junk.tip = n and n > 0 and string.format(L["Junk (%d)"], n)
      or L["The lines the spam filter took, with the reason"]
  end
end

newWindow = function(wid)
  local W = wins[wid]
  if W then
    if W.empty then
      W.empty = nil
      profile().places[wid] = W.win.db
    end
    return W
  end
  local function wireExtra(Wx)
    -- close: the tabs back into the main window; Ctrl+close deletes them
    Wx.win.close.tip = L["Close: the tabs go back to the main window. Ctrl+click: delete them."]
    Wx.win.close:SetScript("OnClick", function()
      View.CloseWindow(Wx.id, IsControlKeyDown())
    end)
    -- dragged onto the main window and let go: it docks
    local function dock()
      local main = wins[View.MAIN]
      if not Wx.empty and main and main.win.frame:IsShown() and main.win.frame:IsMouseOver() then
        View.Dock(Wx.id)
      end
    end
    Wx.win.head:HookScript("OnDragStop", dock)
    Wx.win.frame:HookScript("OnDragStop", dock)
    Wx.win.head.tip = L["Drag onto the main chat window to put the tabs back"]
    Wx.win.head:HookScript("OnEnter", S.TipEnter)
    Wx.win.head:HookScript("OnLeave", S.TipLeave)
  end
  local p = profile()
  local main = wid == View.MAIN
  if main then
    firstPlace(p.window)
  end
  W = { id = wid, tabs = {} }
  W.win = B.UI.Window(main and "BastiansChatWindow" or ("BastiansChatWindow_" .. wid), {
    module = "Chat",
    title = L["Chat"],
    width = main and 520 or 380,
    height = main and 260 or 220,
    minWidth = 220,
    minHeight = 120,
    lockable = true, -- the pin in the header
    db = main and p.window or (function()
      p.places[wid] = p.places[wid] or {}
      return p.places[wid]
    end)(),
    escape = false, -- Escape must not close the chat
    onShow = function(w)
      w.frame:SetFrameStrata("LOW") -- under every other window, as the game's chat
    end,
  })
  local head = W.win.head
  if main then
    -- the Messenger as a pictogram with the unread count as a badge (
    -- "replace the Messenger button with an icon button")
    local m = S.action(head, {
      icon = "messenger",
      label = L["Messenger"],
      tip = L["Your whispers as conversations"],
      row = true,
      onClick = function()
        ns.Messenger.Toggle()
      end,
    })
    m:SetPoint("RIGHT", W.win.lock or W.win.options or W.win.close, "LEFT", -6, 0)
    m:SetBadge(0)
    W.win.title:SetPoint("RIGHT", m, "LEFT", -6, 0)
    W.msgButton = m
  end

  local bar = CreateFrame("Frame", nil, W.win.content)
  bar:SetPoint("TOPLEFT", 0, 0)
  bar:SetPoint("TOPRIGHT", 0, 0)
  bar:SetHeight(View.TAB_H + 2)
  -- a thin rule in the accent under the tabs: the bar apart from the lines (owner, retail
  -- 01.11.2026: "a small bar separates tab bar from chat text")
  bar.rule = S.fill(bar, S.C.accent, "ARTWORK")
  bar.rule:ClearAllPoints()
  bar.rule:SetPoint("BOTTOMLEFT", 0, 0)
  bar.rule:SetPoint("BOTTOMRIGHT", 0, 0)
  bar.rule:SetHeight(1)
  S.tint(bar.rule, S.C.accent, 0.6)
  W.bar = bar
  -- the bar's actions (ADR 0046): pictogram and text, the look draws them
  local copy = S.action(bar, {
    icon = "copy",
    boxed = true, -- a recognisable button
    label = L["Copy"],
    tip = L["The tab's lines as text to copy"],
    row = true,
    onClick = function()
      View.CopyTab(W.current and W.current.def.id)
    end,
  })
  copy:SetPoint("RIGHT", -4, 0)
  W.copy = copy
  if main then
    local junk = S.action(bar, {
      icon = "junk",
      boxed = true,
      label = L["Junk"],
      tip = L["The lines the spam filter took, with the reason"],
      row = true,
      onClick = function()
        ns.Junk.Toggle()
      end,
    })
    junk:SetPoint("RIGHT", copy, "LEFT", -4, 0)
    junk:SetBadge(0)
    W.junk = junk
  end
  -- the filter of the current tab
  local filterButton = S.action(bar, {
    icon = "filter",
    boxed = true,
    label = L["Filter"],
    tip = L["Show only the lines of this tab that match a search"],
    row = true,
    onClick = function()
      View.ToggleFilter(wid)
    end,
  })
  filterButton:SetPoint("RIGHT", W.junk or copy, "LEFT", -4, 0)
  W.filterButton = filterButton
  local filterRow = CreateFrame("Frame", nil, W.win.content)
  filterRow:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 2, -2)
  filterRow:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", -2, -2)
  filterRow:SetHeight(24)
  filterRow:Hide()
  W.filterRow = filterRow
  local help = S.button(filterRow, "?", 22, 20)
  help:SetPoint("RIGHT", 0, 0)
  local filterBox = S.search(filterRow, L["Filter this tab: words, -not, OR, from:name, in:trade, has:item"])
  filterBox:SetPoint("LEFT", 0, 0)
  filterBox:SetPoint("RIGHT", help, "LEFT", -4, 0)
  Model.FilterBox(filterBox)
  filterBox.count = S.text(filterBox, 10, S.C.muted)
  filterBox.count:SetPoint("RIGHT", filterBox.clear, "LEFT", -2, 0)
  filterBox:SetScript("OnTextChanged", function(self)
    local text = self:GetText() or ""
    self.hint:SetShown(text == "")
    self.clear:SetShown(text ~= "")
    View.SetFilter(wid, text)
  end)
  filterBox:SetScript("OnEscapePressed", function()
    View.ToggleFilter(wid, false)
  end)
  W.filterBox = filterBox
  -- the info box: the syntax at once on hover or click
  local function helpTip(self)
    local title, text = S.SearchTip(filterBox)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    S.TipLine(GameTooltip, title, "tipText")
    S.TipLine(
      GameTooltip,
      L["Only the lines of the current tab that match stay; Escape or Filter ends it."],
      "tipDim",
      true
    )
    S.TipLine(GameTooltip, text, "tipDim", true)
    GameTooltip:Show()
  end
  help:SetScript("OnEnter", helpTip)
  help:SetScript("OnClick", helpTip)
  help:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  W.help = help
  local plus = S.action(bar, {
    icon = "plus",
    boxed = true,
    label = L["A new tab"],
    only = true,
    row = true,
    onClick = function(self)
      View.PlusMenu(self, wid)
    end,
  })
  W.plus = plus

  local area = CreateFrame("Frame", nil, W.win.content)
  area:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 2, 0)
  area:SetPoint("BOTTOMRIGHT", W.win.content, "BOTTOMRIGHT", -2, main and (View.INPUT_H + 2) or 2)
  local ground = area:CreateTexture(nil, "BACKGROUND")
  ground:SetTexture(View.GROUND, true, true)
  ground:SetAllPoints()
  ground:SetAlpha(View.GROUND_ALPHA)
  area.ground = ground
  W.area = area
  if main then
    buildLongBar(W)
  else
    wireExtra(W)
  end
  wins[wid] = W
  return W
end

-- Builds the windows and tabs from the profile once: the default tabs on the first start, every
-- defined tab in exactly one window, the main window with one tab at least.
function View.Setup()
  if ready then
    return wins[View.MAIN]
  end
  ready = true
  local p = profile()
  if not next(p.tabs) then
    for _, d in ipairs(Model.TABS) do
      p.tabs[d.id] = Model.CopyDef(d)
    end
  end
  local layout, placed = p.layout, {}
  layout[View.MAIN] = layout[View.MAIN] or {}
  for wid, ids in pairs(layout) do
    local kept = {}
    for _, id in ipairs(ids) do
      if p.tabs[id] and not placed[id] then
        placed[id] = true
        kept[#kept + 1] = id
      end
    end
    layout[wid] = kept
  end
  local rest = {}
  for id in pairs(p.tabs) do
    if not placed[id] then
      rest[#rest + 1] = id
    end
  end
  local order = {}
  for i, d in ipairs(Model.TABS) do
    order[d.id] = i
  end
  table.sort(rest, function(a, b)
    return (order[a] or 100) < (order[b] or 100) or (order[a] or 100) == (order[b] or 100) and a < b
  end)
  for _, id in ipairs(rest) do
    table.insert(layout[View.MAIN], id)
  end
  for wid, ids in pairs(layout) do
    if wid ~= View.MAIN and #ids == 0 then
      layout[wid] = nil
      p.places[wid] = nil
    end
  end
  if #layout[View.MAIN] == 0 then
    for wid, ids in pairs(layout) do
      if wid ~= View.MAIN then
        table.insert(layout[View.MAIN], table.remove(ids, 1))
        if #ids == 0 then
          layout[wid] = nil
        end
        break
      end
    end
  end
  newWindow(View.MAIN)
  for wid in pairs(layout) do
    newWindow(wid)
  end
  for wid, ids in pairs(layout) do
    for _, id in ipairs(ids) do
      buildTab(p.tabs[id], wins[wid])
    end
  end
  for wid, W in pairs(wins) do
    layoutTabs(W)
    local sel = byId[p.selected[wid] or ""]
    View.Select(sel and sel.wid == wid and sel.def.id or (firstShown(W) and firstShown(W).def.id))
  end
  return wins[View.MAIN]
end

function View.Build()
  return View.Setup()
end

-- The game's input bar in the bottom of the main window, where the long bar sits.
function View.PlaceBox(box)
  local W = wins[View.MAIN]
  if not W then
    return
  end
  View.placing = true
  box:SetParent(W.win.frame)
  box:ClearAllPoints()
  box:SetPoint("BOTTOMLEFT", W.win.content, "BOTTOMLEFT", 0, -2)
  box:SetPoint("BOTTOMRIGHT", W.win.content, "BOTTOMRIGHT", -16, -2)
  View.placing = false
end

-- Is the bar where PlaceBox put it (anchored to the main window)?
function View.HoldsBox(box)
  local W = wins[View.MAIN]
  if not W or box:GetNumPoints() == 0 then
    return false
  end
  local _, rel = box:GetPoint(1)
  return rel == W.win.content
end

-- The settings that change the message areas and the tab bars.
function View.Apply()
  local p = profile()
  for _, tab in pairs(byId) do
    if tab.frame then
      applyFont(tab.frame)
      tab.frame:SetFading(p.fade)
    end
  end
  for _, W in pairs(wins) do
    layoutTabs(W)
  end
end

-- In combat the windows fade (a setting), back after.
function View.SetCombat(on)
  local alpha = (on and profile().combatFade) and View.COMBAT_ALPHA or 1
  for _, W in pairs(wins) do
    W.win.frame:SetAlpha(alpha)
  end
end

-- An instance brings the Group tab forward (a setting); leaving it brings the last tab back.
function View.SelectGroup(inside)
  if not profile().groupInInstance then
    return
  end
  local group = byId.group
  if inside and group and group.wid == View.MAIN then
    if View.Current() ~= "group" then
      before = View.Current()
      View.Select("group")
    end
  elseif not inside and before then
    View.Select(before)
    before = nil
  end
end

function View.Show()
  View.Setup()
  for _, wid in ipairs(View.Windows()) do
    wins[wid].win:Show()
  end
end

function View.Hide()
  for _, W in pairs(wins) do
    W.win:Hide()
  end
  if copyWin then
    copyWin:Hide()
  end
  if editor then
    editor:Hide()
  end
end

function View.Toggle()
  View.Setup()
  local main = wins[View.MAIN].win
  if main:IsShown() then
    View.Hide()
  else
    View.Show()
  end
end
