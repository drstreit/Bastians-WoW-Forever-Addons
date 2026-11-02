-- Timers on Bastian's minimap (map.md "Timers", "you can start a
-- timer/stopwatch from the minimap - we need to add that to ours, maybe improving it, maybe
-- multiple"): stopwatches and countdowns, as many as wanted, each with a name, kept in the
-- profile so a reload loses none. A countdown that ends says so in the chat, plays the raid
-- warning and lights the tools button until the window is opened. The model is pure (server time
-- in, plain tables out); the window ticks only while it shows, and a running countdown rings
-- through one C_Timer, nothing polls.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Map = ns.Map

local Timers = {}
ns.Timers = Timers

Timers.ALARM = 8959 -- the raid warning (SOUNDKIT.RAID_WARNING on retail; the number is Forever's too)
Timers.TICK = 0.2 -- seconds between the window's time texts following the clock
Timers.ROW_H = 30
Timers.NAME_W = 120
Timers.MAX_NAME = 24

local mod, win, button
local handles = {} -- { [id] = the C_Timer of a running countdown }
local rows = {}

local function db()
  return mod.db.profile
end

-- The kept list: { list = { timer }, nextID }.
function Timers.State()
  local p = db()
  if type(p.timers) ~= "table" then
    p.timers = { list = {}, nextID = 1 }
  end
  p.timers.list = p.timers.list or {}
  p.timers.nextID = p.timers.nextID or 1
  return p.timers
end

local function now()
  return B.Compat.ServerTime and B.Compat.ServerTime() or time()
end

-- ---------------------------------------------------------------------------------------------
-- The model: a timer is { id, kind = "watch" | "down", name, total (seconds of a countdown),
-- base (seconds run before the last start), startedAt (server time of the last start, nil while
-- paused), rang (a countdown that ended) }
-- ---------------------------------------------------------------------------------------------

local Model = {}
Timers.Model = Model

-- "5m", "1:30", "90", "90s", "2h", "1h 20m", "1:02:03" -> seconds, nil for anything else.
function Model.Parse(text)
  if type(text) ~= "string" then
    return nil
  end
  text = string.lower(string.gsub(text, "^%s*(.-)%s*$", "%1"))
  if text == "" then
    return nil
  end
  if string.find(text, ":", 1, true) then
    local parts = {}
    for part in string.gmatch(text, "[^:]+") do
      local n = tonumber(part)
      if not n or #parts >= 3 then
        return nil
      end
      parts[#parts + 1] = n
    end
    if #parts < 2 then
      return nil
    end
    local seconds = 0
    for _, n in ipairs(parts) do
      seconds = seconds * 60 + n
    end
    return seconds > 0 and math.floor(seconds) or nil
  end
  local seconds, rest = 0, text
  while rest ~= "" do
    local n, unit, after = string.match(rest, "^%s*(%d+%.?%d*)%s*([hms]?)%s*(.*)$")
    if not n then
      return nil
    end
    n = tonumber(n)
    if unit == "h" then
      seconds = seconds + n * 3600
    elseif unit == "m" then
      seconds = seconds + n * 60
    else
      seconds = seconds + n
    end
    rest = after
  end
  return seconds > 0 and math.floor(seconds) or nil
end

-- "1:02:03", "12:34", "0:07".
function Model.Format(seconds)
  seconds = math.max(0, math.floor((seconds or 0) + 0.5))
  local h = math.floor(seconds / 3600)
  local m = math.floor((seconds % 3600) / 60)
  local s = seconds % 60
  if h > 0 then
    return string.format("%d:%02d:%02d", h, m, s)
  end
  return string.format("%d:%02d", m, s)
end

function Model.Running(t)
  return t.startedAt ~= nil
end

function Model.Elapsed(t, at)
  return (t.base or 0) + (t.startedAt and math.max(0, at - t.startedAt) or 0)
end

-- A countdown's seconds left (0 at the end), nil for a stopwatch.
function Model.Left(t, at)
  if t.kind ~= "down" then
    return nil
  end
  return math.max(0, (t.total or 0) - Model.Elapsed(t, at))
end

-- Whether a countdown reached its end.
function Model.Due(t, at)
  return t.kind == "down" and Model.Left(t, at) <= 0
end

function Model.Start(t, at)
  if t.startedAt then
    return false
  end
  if Model.Due(t, at) then
    t.base, t.rang = 0, nil -- a countdown that ended runs again from the top
  end
  t.startedAt = at
  return true
end

function Model.Pause(t, at)
  if not t.startedAt then
    return false
  end
  t.base = Model.Elapsed(t, at)
  t.startedAt = nil
  return true
end

function Model.Reset(t)
  t.base, t.startedAt, t.rang = 0, nil, nil
end

-- The timer that ended: stopped at its total, marked.
function Model.Ring(t)
  t.base, t.startedAt, t.rang = t.total or 0, nil, true
end

function Model.Add(state, kind, name, total)
  local t = { id = state.nextID, kind = kind, name = name, base = 0 }
  if kind == "down" then
    t.total = total
  end
  state.nextID = state.nextID + 1
  state.list[#state.list + 1] = t
  return t
end

function Model.Remove(state, id)
  for i, t in ipairs(state.list) do
    if t.id == id then
      table.remove(state.list, i)
      return true
    end
  end
  return false
end

function Model.Find(state, id)
  for _, t in ipairs(state.list) do
    if t.id == id then
      return t
    end
  end
  return nil
end

-- The default name of a new timer: "Stopwatch 2", "Countdown 1".
function Model.DefaultName(state, kind)
  local word = kind == "down" and L["Countdown"] or L["Stopwatch"]
  local n = 0
  for _, t in ipairs(state.list) do
    if t.kind == kind then
      n = n + 1
    end
  end
  return word .. " " .. (n + 1)
end

-- ---------------------------------------------------------------------------------------------
-- Ringing: one C_Timer per running countdown
-- ---------------------------------------------------------------------------------------------

local function disarm(id)
  local h = handles[id]
  if h then
    if h.Cancel then
      h:Cancel()
    end
    handles[id] = nil
  end
end

local function ring(t)
  disarm(t.id)
  if Model.Find(Timers.State(), t.id) ~= t then
    return -- removed meanwhile
  end
  Model.Ring(t)
  B:Say(L["%s is up."], t.name or L["Countdown"])
  if B.Compat.PlayKit then
    B.Compat.PlayKit(Timers.ALARM)
  end
  Timers.Light()
  Timers.Render()
end
Timers.ring = ring

-- Arms the timer that rings when a running countdown ends; a countdown already past its end rings
-- at once (a reload while it ran).
local function arm(t)
  disarm(t.id)
  if t.kind ~= "down" or not Model.Running(t) then
    return
  end
  local left = Model.Left(t, now())
  if left <= 0 then
    ring(t)
    return
  end
  handles[t.id] = C_Timer.NewTimer(left, function()
    handles[t.id] = nil
    ring(t)
  end)
end

function Timers.Arm()
  if not mod then
    return
  end
  for _, t in ipairs(Timers.State().list) do
    arm(t)
  end
end

function Timers.Disarm()
  for id in pairs(handles) do
    disarm(id)
  end
end

-- ---------------------------------------------------------------------------------------------
-- What the player does
-- ---------------------------------------------------------------------------------------------

function Timers.Add(kind, name, text)
  local state = Timers.State()
  local total
  if kind == "down" then
    total = Model.Parse(text)
    if not total then
      B:Say(L["I could not read that time. Try 5m, 1:30, 90s or 2h."])
      return nil
    end
  end
  name = string.gsub(name or "", "^%s*(.-)%s*$", "%1")
  if name == "" then
    name = Model.DefaultName(state, kind)
  end
  local t = Model.Add(state, kind, string.sub(name, 1, Timers.MAX_NAME), total)
  Model.Start(t, now())
  arm(t)
  Timers.Render()
  return t
end

function Timers.Toggle(id)
  local t = Model.Find(Timers.State(), id)
  if not t then
    return
  end
  local at = now()
  if Model.Running(t) then
    Model.Pause(t, at)
  else
    Model.Start(t, at)
  end
  arm(t)
  Timers.Render()
end

function Timers.Reset(id)
  local t = Model.Find(Timers.State(), id)
  if not t then
    return
  end
  local running = Model.Running(t)
  Model.Reset(t)
  if running then
    Model.Start(t, now())
  end
  arm(t)
  Timers.Render()
end

function Timers.Remove(id)
  disarm(id)
  Model.Remove(Timers.State(), id)
  Timers.Render()
end

function Timers.Rename(id, name)
  local t = Model.Find(Timers.State(), id)
  if t then
    t.name = string.sub(name or "", 1, Timers.MAX_NAME)
  end
end

-- The running ones, soonest countdown first, then the stopwatches: for the tools button's tip.
function Timers.Lines()
  local at = now()
  local out = {}
  for _, t in ipairs(Timers.State().list) do
    if t.kind == "down" then
      local left = Model.Left(t, at)
      if Model.Running(t) then
        out[#out + 1] = string.format(L["%s: %s left"], t.name or "?", Model.Format(left))
      elseif t.rang then
        out[#out + 1] = (t.name or "?") .. ": " .. L["Done"]
      end
    elseif Model.Running(t) then
      out[#out + 1] = (t.name or "?") .. ": " .. Model.Format(Model.Elapsed(t, at))
    end
  end
  return out
end

-- ---------------------------------------------------------------------------------------------
-- The tools button: lit while a countdown ended and the window was not looked at since
-- ---------------------------------------------------------------------------------------------

function Timers.Lit()
  for _, t in ipairs(Timers.State().list) do
    if t.rang and not t.seen then
      return true
    end
  end
  return false
end

function Timers.Light()
  if button and button.glow then
    button.glow:SetShown(Timers.Lit())
  end
end

local function seen()
  for _, t in ipairs(Timers.State().list) do
    if t.rang then
      t.seen = true
    end
  end
  Timers.Light()
end

-- The button's tip: the running timers, or what the window does.
local function buttonTip()
  local lines = Timers.Lines()
  if #lines == 0 then
    return L["Timers"], L["Stopwatches and countdowns, as many as you like. A lit button: a countdown ended."]
  end
  return L["Timers"] .. "  " .. string.format(L["%d running"], #lines), table.concat(lines, "\n")
end

-- Made by Mini.lua for its tools row: the glyph, a glow behind it while a countdown ended.
function Timers.Button(parent, make)
  button = make(parent, "waiting", buttonTip, function()
    Timers.ToggleWindow()
  end)
  button.glow = S.fill(button, S.C.accent, "BACKGROUND")
  button.glow:SetAlpha(0.6)
  button.glow:Hide()
  return button
end

-- ---------------------------------------------------------------------------------------------
-- The window: a row per timer, the adding line at the bottom
-- ---------------------------------------------------------------------------------------------

local function timeText(t, at)
  if t.kind == "down" then
    if t.rang and not Model.Running(t) then
      return L["Done"], "accent"
    end
    return Model.Format(Model.Left(t, at)), Model.Running(t) and "text" or "dim"
  end
  return Model.Format(Model.Elapsed(t, at)), Model.Running(t) and "text" or "dim"
end

local function rowFrame(i)
  local r = rows[i]
  if r then
    return r
  end
  local content = win.content
  r = CreateFrame("Frame", nil, content)
  r:SetHeight(Timers.ROW_H)
  r.kind = S.tile(r, "waiting")
  r.kind:SetPoint("LEFT", 6, 0)
  -- the name, editable in place
  r.name = S.search(r, L["Name"], true)
  r.name:SetWidth(Timers.NAME_W)
  r.name:SetPoint("LEFT", r.kind, "RIGHT", 6, 0)
  r.name:SetScript("OnTextChanged", function(self, user)
    if user and r.id then
      Timers.Rename(r.id, self:GetText())
    end
    self.hint:SetShown((self:GetText() or "") == "")
  end)
  r.time = S.text(r, 16, S.C.text)
  r.time:SetPoint("LEFT", r.name, "RIGHT", 8, 0)
  r.time:SetWidth(80)
  r.time:SetJustifyH("LEFT")
  r.remove = S.action(r, { icon = "remove", label = L["Remove"], only = true, row = true })
  r.remove:SetPoint("RIGHT", -6, 0)
  r.remove:SetScript("OnClick", function()
    Timers.Remove(r.id)
  end)
  r.reset = S.action(r, { icon = "replay", label = L["Reset"], only = true, row = true })
  r.reset:SetPoint("RIGHT", r.remove, "LEFT", -2, 0)
  r.reset:SetScript("OnClick", function()
    Timers.Reset(r.id)
  end)
  r.toggle = S.action(r, { icon = "play", label = L["Start"], only = true, row = true })
  r.toggle:SetPoint("RIGHT", r.reset, "LEFT", -2, 0)
  r.toggle:SetScript("OnClick", function()
    Timers.Toggle(r.id)
  end)
  r.rule = S.fill(r, S.C.line, "ARTWORK")
  r.rule:ClearAllPoints()
  r.rule:SetPoint("BOTTOMLEFT", 6, 0)
  r.rule:SetPoint("BOTTOMRIGHT", -6, 0)
  r.rule:SetHeight(1)
  rows[i] = r
  return r
end

-- The time texts follow the clock; the rows stay.
function Timers.Tick()
  if not (win and win:IsShown()) then
    return
  end
  local at = now()
  for i, t in ipairs(Timers.State().list) do
    local r = rows[i]
    if r and r:IsShown() then
      local text, tok = timeText(t, at)
      r.time:SetText(text)
      S.ink(r.time, S.C[tok])
    end
  end
end

function Timers.Render()
  Timers.Light()
  if not (win and win:IsShown()) then
    return
  end
  local list = Timers.State().list
  local at = now()
  for i, t in ipairs(list) do
    local r = rowFrame(i)
    r.id = t.id
    r.kind:SetKind(t.kind == "down" and "waiting" or "play")
    if not r.name:HasFocus() then
      r.name:SetText(t.name or "")
      r.name.hint:SetShown((t.name or "") == "")
    end
    local text, tok = timeText(t, at)
    r.time:SetText(text)
    S.ink(r.time, S.C[tok])
    r.toggle.spec.icon = Model.Running(t) and "pause" or "play"
    r.toggle.spec.label = Model.Running(t) and L["Pause"] or L["Start"]
    r.toggle.tip = r.toggle.spec.label
    S.Draw(r.toggle)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", win.content, "TOPLEFT", 0, -(4 + (i - 1) * Timers.ROW_H))
    r:SetPoint("TOPRIGHT", win.content, "TOPRIGHT", 0, -(4 + (i - 1) * Timers.ROW_H))
    r:Show()
  end
  for i = #list + 1, #rows do
    rows[i]:Hide()
  end
  win.empty:SetShown(#list == 0)
  -- the window grows with its rows, the adding line stays at the bottom
  local top, _, bottom = win:Insets()
  win.frame:SetHeight(top + bottom + 4 + math.max(1, #list) * Timers.ROW_H + 8 + win.adder:GetHeight())
end

local function build()
  win = B.UI.Window("BastiansTimers", {
    module = "Map",
    page = "minimap",
    title = L["Timers"],
    width = 360,
    height = 140,
    minWidth = 320,
    minHeight = 120,
    db = db().timersWindow,
    onShow = function()
      seen()
      Timers.Render()
      local elapsed = 0
      win.frame:SetScript("OnUpdate", function(_, dt) -- only while the window shows (golden rule 7)
        elapsed = elapsed + dt
        if elapsed >= Timers.TICK then
          elapsed = 0
          Timers.Tick()
        end
      end)
    end,
    onHide = function()
      win.frame:SetScript("OnUpdate", nil)
    end,
  })
  local content = win.content
  win.empty = S.text(content, 11, S.C.dim)
  win.empty:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -10)
  win.empty:SetPoint("TOPRIGHT", content, "TOPRIGHT", -10, -10)
  win.empty:SetJustifyH("LEFT")
  win.empty:SetText(L["No timers yet. Add a stopwatch or a countdown below."])
  -- the adding line: a name, a duration, the two buttons
  local adder = CreateFrame("Frame", nil, content)
  adder:SetHeight(26)
  adder:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 6, 4)
  adder:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -6, 4)
  adder.name = S.search(adder, L["Name"], true)
  adder.name:SetWidth(Timers.NAME_W)
  adder.name:SetPoint("LEFT", 0, 0)
  adder.name:SetScript("OnTextChanged", function(self)
    self.hint:SetShown((self:GetText() or "") == "")
  end)
  adder.how = S.search(adder, L["How long: 5m, 1:30, 90s, 2h"], true)
  adder.how:SetWidth(110)
  adder.how:SetPoint("LEFT", adder.name, "RIGHT", 4, 0)
  adder.how:SetScript("OnTextChanged", function(self)
    self.hint:SetShown((self:GetText() or "") == "")
  end)
  adder.how:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    adder.down:Click()
  end)
  adder.watch =
    S.action(adder, { icon = "play", label = L["Stopwatch"], tip = L["Add a stopwatch"], boxed = true })
  adder.watch:SetPoint("LEFT", adder.how, "RIGHT", 6, 0)
  adder.watch:SetScript("OnClick", function()
    if Timers.Add("watch", adder.name:GetText()) then
      adder.name:SetText("")
    end
  end)
  adder.down =
    S.action(adder, { icon = "waiting", label = L["Countdown"], tip = L["Add a countdown"], boxed = true })
  adder.down:SetPoint("LEFT", adder.watch, "RIGHT", 4, 0)
  adder.down:SetScript("OnClick", function()
    if Timers.Add("down", adder.name:GetText(), adder.how:GetText()) then
      adder.name:SetText("")
      adder.how:SetText("")
    end
  end)
  win.adder = adder
  Timers.win = win
  Timers.rows = rows
end

function Timers.Open()
  if not mod then
    return false
  end
  if not win then
    build()
  end
  if win:IsShown() then
    Timers.Render()
  else
    win:Show()
  end
  return true
end

function Timers.ToggleWindow()
  if win and win:IsShown() then
    win:Hide()
    return false
  end
  return Timers.Open()
end

function Timers.Window()
  return win
end

ns.mod.Timers = Timers
table.insert(Map.onEnable, function(self)
  mod = self
end)
table.insert(Map.onWorld, function()
  Timers.Arm() -- a reload or a login: the running countdowns ring on time, a past one at once
  Timers.Light()
end)
table.insert(Map.onDisable, function()
  Timers.Disarm()
  if win then
    win:Hide()
  end
end)
