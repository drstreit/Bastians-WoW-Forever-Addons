-- The window My lines of Bastian's Courtesy (courtesy.md "Your own lines", ADR 0063's amendment of
-- 15.11.2026, owner: "I have the feeling its confusing to have Bastians_MyLines and hard coded?"):
-- three views (your lines, the lines offered lately, the lines never offered) above a form that
-- adds or saves a line, checked as you go, and says it in your own chat with Try.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local W = B.UI.Widgets
local Voice, Mine = ns.Voice, ns.Mine

local Editor = {}
ns.Editor = Editor

Editor.ROW = 32 -- pixels of one line in the list
Editor.ROWS = 8 -- lines the list shows; the mouse wheel moves through the rest
Editor.MOODS = { "polite", "roleplay", "snarky", "philosophic", "cheerful", "weary" }
-- the stand-ins of Try for the facts nobody gives outside a moment
Editor.STAND_IN = {
  target = "Alda",
  race = "Dwarf",
  raceKey = "Dwarf",
  class = "Mage",
  classKey = "MAGE",
  sex = "f",
  spell = "Arcane Intellect",
}

local win, view, offset, editing = nil, "mine", 0, nil
local rows, tabs, form = {}, {}, {}

local function moodWord(mood)
  return L[mood:sub(1, 1):upper() .. mood:sub(2)]
end

-- A line's words as the list shows them: the action dim in front, then what is said.
local function words(line)
  local text = type(line[3]) == "string" and line[3] or ""
  if line.act then
    return S.H.muted .. line.act .. "|r" .. (text ~= "" and (" " .. text) or "")
  end
  return text
end

local function conditionWords(when)
  if type(when) ~= "table" then
    return nil
  end
  local out = {}
  for key, value in pairs(when) do
    local v = type(value) == "table" and table.concat(value, "/") or tostring(value)
    out[#out + 1] = key .. " " .. v
  end
  table.sort(out)
  return #out > 0 and table.concat(out, ", ") or nil
end

local function head(line, mine)
  local parts = { tostring(line[1]), moodWord(tostring(line[2])) }
  local only = conditionWords(line.when)
  if only then
    parts[#parts + 1] = string.format(L["only: %s"], only)
  end
  if mine then
    parts[#parts + 1] = L["yours"]
  end
  return table.concat(parts, " - ")
end

-- What a view lists: { head, text, line, index (yours), key (never), action = "remove" | "never" |
-- "allow" } each (pure but for the saved lines and the memory of what was offered).
function Editor.Items(which)
  local out = {}
  if which == "offered" then
    for _, line in ipairs(ns.Courtesy.RecentLines()) do
      out[#out + 1] = {
        head = head(line, Mine.Owns(line)),
        text = words(line),
        line = line,
        action = not Mine.IsNever(line) and "never" or nil,
      }
    end
  elseif which == "never" then
    local keys = {}
    for key in pairs(Mine.NeverSet()) do
      keys[#keys + 1] = key
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
      local act = key:match("^act:(.*)$")
      out[#out + 1] = {
        head = L["Never offered"],
        text = act and (S.H.muted .. act .. "|r") or key,
        key = key,
        action = "allow",
      }
    end
  else
    for i, line in ipairs(Mine.List()) do
      out[#out + 1] = { head = head(line), text = words(line), line = line, index = i, action = "remove" }
    end
  end
  return out
end

local function setProblem(text)
  form.problem:SetText(text or "")
end

-- The line the form holds now (its conditions and emote kept from the line being changed).
function Editor.FormLine()
  local text = form.text:GetText() or ""
  local act = form.act:GetText() or ""
  local before = editing and Mine.List()[editing] or {}
  return {
    form.situation:GetValue(),
    form.mood:GetValue(),
    text ~= "" and text or false,
    act = act ~= "" and act or nil,
    when = before.when,
    emote = before.emote,
  }
end

function Editor.Clear()
  editing = nil
  form.text:SetText("")
  form.act:SetText("")
  form.add:SetLabel(L["Add"])
  setProblem(nil)
end

-- A line of yours into the form, to change it.
function Editor.Load(index)
  local line = Mine.List()[index]
  if not line then
    return
  end
  editing = index
  form.situation:SetValue(line[1])
  form.mood:SetValue(line[2])
  form.text:SetText(type(line[3]) == "string" and line[3] or "")
  form.act:SetText(line.act or "")
  form.add:SetLabel(L["Save"])
  setProblem(Mine.Problem(line))
end

-- Add, or Save while a line of the list is in the form. -> true, or false and why.
function Editor.Commit()
  local ok, why = Mine.Put(Editor.FormLine(), editing)
  if not ok then
    setProblem(why)
    return false, why
  end
  Editor.Clear()
  view = "mine"
  Editor.Refresh()
  return true
end

-- The form's line in your own chat, filled with the moment's facts and stand-ins for the rest.
function Editor.Try()
  local line = Editor.FormLine()
  local why = Mine.Problem(line)
  setProblem(why)
  if why then
    return nil
  end
  local facts = ns.Facts.Surroundings(ns.Facts.Speaker())
  for key, value in pairs(Editor.STAND_IN) do
    if facts[key] == nil then
      facts[key] = value
    end
  end
  facts.situation = line[1]
  facts.company = facts.company or Voice.Company({ "Alda", "Brann" })
  facts = Voice.Complete(facts)
  local said = (facts.myName and (facts.myName .. " ") or "") .. Voice.Words(line, facts, "emote")
  B:Say("%s", said)
  return said
end

local function act(item)
  if item.action == "remove" then
    if editing == item.index then
      Editor.Clear()
    end
    Mine.Remove(item.index)
  elseif item.action == "never" then
    Mine.Never(item.line)
  elseif item.action == "allow" then
    Mine.Allow(item.key)
  end
  Editor.Refresh()
end

local ACTION_WORDS = { never = "Never offer", allow = "Allow again" }

local function row(i)
  local r = rows[i]
  if r then
    return r
  end
  r = CreateFrame("Button", nil, win.list)
  r:SetHeight(Editor.ROW)
  r.head = S.text(r, 11, S.C.muted)
  r.head:SetPoint("TOPLEFT", 6, -3)
  r.head:SetPoint("RIGHT", -110, 0)
  r.head:SetJustifyH("LEFT")
  r.head:SetWordWrap(false)
  r.text = S.text(r, 12, S.C.text)
  r.text:SetPoint("TOPLEFT", r.head, "BOTTOMLEFT", 0, -2)
  r.text:SetPoint("RIGHT", -110, 0)
  r.text:SetJustifyH("LEFT")
  r.text:SetWordWrap(false)
  r.hl = S.fill(r, S.C.hover, "BACKGROUND")
  r.hl:Hide()
  r.button = S.action(r, { label = L["Never offer"] })
  r.button:SetPoint("RIGHT", -4, 0)
  r.remove = S.action(r, { icon = "close", only = true, label = L["Remove"] })
  r.remove:SetPoint("RIGHT", -4, 0)
  r:SetScript("OnEnter", function(self)
    if self.item and self.item.index then
      self.hl:Show()
    end
  end)
  r:SetScript("OnLeave", function(self)
    self.hl:Hide()
  end)
  r:SetScript("OnClick", function(self)
    if self.item and self.item.index then
      Editor.Load(self.item.index)
    end
  end)
  r:EnableMouseWheel(true)
  r:SetScript("OnMouseWheel", function(_, delta)
    Editor.Scroll(-delta)
  end)
  rows[i] = r
  return r
end

function Editor.Scroll(by)
  local n = #Editor.Items(view)
  offset = math.max(0, math.min(math.max(0, n - Editor.ROWS), offset + by))
  Editor.Refresh()
end

local NOTES = {
  mine = "Click a line to change it; the cross removes it. Yours take part beside the lines that come with Courtesy.", -- luacheck: ignore 631 (a locale key stays one literal)
  offered = "The lines the rings and the chat offered lately. Never offer switches one off for good.",
  never = "These lines are never offered. Allow again brings one back.",
}

-- Draws the view and the tabs' counts.
function Editor.Refresh()
  if not win then
    return
  end
  local items = Editor.Items(view)
  offset = math.max(0, math.min(offset, math.max(0, #items - Editor.ROWS)))
  tabs.mine:SetLabel(string.format(L["Mine (%d)"], #Mine.List()))
  local neverCount = 0
  for _ in pairs(Mine.NeverSet()) do
    neverCount = neverCount + 1
  end
  tabs.never:SetLabel(string.format(L["Never (%d)"], neverCount))
  for key, b in pairs(tabs) do
    b:SetOn(key == view)
  end
  win.note:SetText(L[NOTES[view]])
  for i = 1, Editor.ROWS do
    local item = items[offset + i]
    local r = row(i)
    r.item = item
    if item then
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", win.list, "TOPLEFT", 0, -(i - 1) * Editor.ROW)
      r:SetPoint("RIGHT", win.list, "RIGHT", 0, 0)
      r.head:SetText(item.head)
      r.text:SetText(item.text)
      r.remove:SetShown(item.action == "remove")
      r.button:SetShown(item.action == "never" or item.action == "allow")
      if ACTION_WORDS[item.action] then
        r.button:SetLabel(L[ACTION_WORDS[item.action]])
      end
      r.button:SetScript("OnClick", function()
        act(item)
      end)
      r.remove:SetScript("OnClick", function()
        act(item)
      end)
      r:Show()
    else
      r:Hide()
    end
  end
  win.empty:SetShown(#items == 0)
end

function Editor.SetView(which)
  view, offset = which, 0
  Editor.Refresh()
end

function Editor.View()
  return view
end

local function build()
  local mod = ns.Main.mod
  mod.db.profile.linesWindow = mod.db.profile.linesWindow or {}
  win = B.UI.Window("BastiansCourtesyLines", {
    title = L["My lines"],
    width = 600,
    height = 560,
    minWidth = 520,
    minHeight = 560,
    db = mod.db.profile.linesWindow,
  })
  local c = win.content
  local x = 10
  for _, spec in ipairs({
    { "mine", L["Mine (%d)"]:format(0) },
    { "offered", L["Offered lately"] },
    { "never", L["Never (%d)"]:format(0) },
  }) do
    local b = S.action(c, { label = spec[2], toggle = true })
    b:SetPoint("TOPLEFT", x, -8)
    b:SetScript("OnClick", function()
      Editor.SetView(spec[1])
    end)
    tabs[spec[1]] = b
    x = x + 150
  end
  win.note = S.text(c, 11, S.C.muted)
  win.note:SetPoint("TOPLEFT", 10, -38)
  win.note:SetPoint("TOPRIGHT", -10, -38)
  win.note:SetJustifyH("LEFT")
  win.list = CreateFrame("Frame", nil, c)
  win.list:SetPoint("TOPLEFT", 6, -58)
  win.list:SetPoint("TOPRIGHT", -6, -58)
  win.list:SetHeight(Editor.ROW * Editor.ROWS)
  win.list:EnableMouseWheel(true)
  win.list:SetScript("OnMouseWheel", function(_, delta)
    Editor.Scroll(-delta)
  end)
  win.empty = S.text(win.list, 12, S.C.muted)
  win.empty:SetPoint("TOP", 0, -20)
  win.empty:SetText(L["Nothing here yet."])
  -- the form
  local top = -(58 + Editor.ROW * Editor.ROWS + 12)
  local situations = {}
  for situation in pairs(Voice.Situations(ns.CourtesyLines)) do
    situations[situation] = situation
  end
  form.situation = W.Select(c, L["Situation"], situations)
  form.situation:SetPoint("TOPLEFT", 10, top)
  form.situation:SetWidth(280)
  form.situation:SetValue("buff")
  local moods = {}
  for _, mood in ipairs(Editor.MOODS) do
    moods[mood] = moodWord(mood)
  end
  form.mood = W.Select(c, L["Mood"], moods)
  form.mood:SetPoint("TOPLEFT", 300, top)
  form.mood:SetWidth(270)
  form.mood:SetValue("polite")
  local function check()
    setProblem(Mine.Problem(Editor.FormLine()))
  end
  form.text = W.Edit(c, L["What you say: %t their name, %h the time of day, %k the people at a fire"], check)
  form.text:SetPoint("TOPLEFT", 10, top - 30)
  form.text:SetPoint("TOPRIGHT", -10, top - 30)
  form.act = W.Edit(c, L["Optional: what you do, such as waves at %t."], check)
  form.act:SetPoint("TOPLEFT", 10, top - 58)
  form.act:SetPoint("TOPRIGHT", -10, top - 58)
  form.problem = S.text(c, 11, S.C.bad)
  form.problem:SetPoint("TOPLEFT", 10, top - 86)
  form.problem:SetPoint("TOPRIGHT", -10, top - 86)
  form.problem:SetJustifyH("LEFT")
  form.add = S.action(c, { icon = "plus", label = L["Add"], primary = true })
  form.add:SetPoint("TOPLEFT", 10, top - 104)
  form.add:SetScript("OnClick", Editor.Commit)
  form.try = S.action(c, { icon = "play", label = L["Try"] })
  form.try:SetPoint("LEFT", form.add, "RIGHT", 8, 0)
  form.try:SetScript("OnClick", Editor.Try)
  form.clear = S.action(c, { icon = "clear", label = L["Clear"] })
  form.clear:SetPoint("LEFT", form.try, "RIGHT", 8, 0)
  form.clear:SetScript("OnClick", Editor.Clear)
  Editor.form, Editor.rows, Editor.tabs, Editor.win = form, rows, tabs, win
end

function Editor.Open()
  if not ns.Main.mod then
    return nil
  end
  if not win then
    build()
  end
  win:Show()
  Editor.Refresh()
  return win
end

function Editor.Window()
  return win
end
