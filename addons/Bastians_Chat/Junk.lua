-- Bastian's Chat, the Junk window (chat.md "Spam", S10): the session's last filtered lines, each
-- with its reason and "Not junk"; above them the strength, what a blocked word does, the word lists
-- and the blocked senders.
local _, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
local L = ns.L
local S = B.UI.Style
local Model = ns.Model

local Junk = {}
ns.Junk = Junk

Junk.CAP = 500 -- lines kept for the session, never saved
Junk.ROW_H = 20

local ring = {} -- { line, at }, the oldest first
local win, rows, offset = nil, {}, 0
local block, allow, level, action, senders

local function profile()
  return ns.mod.db.profile
end

-- The reason of a filtered line, for the player (S10).
function Junk.Reason(line)
  if line.reason == "blocked word" then
    return string.format(L["blocked word: %s"], tostring(line.word or ""))
  end
  return L[line.reason or "filtered"]
end

function Junk.Add(line)
  Model.Push(ring, { line = line, at = line.at or time() }, Junk.CAP)
  ns.View.JunkCount(#ring)
  if win and win:IsShown() then
    Junk.Refresh()
  end
end

function Junk.Lines()
  return ring
end

-- "Not junk": the sender is allowed for the session and the line goes where it belonged.
function Junk.NotJunk(index)
  local entry = table.remove(ring, index)
  if not entry then
    return nil
  end
  local line = entry.line
  ns.Chat.Allow(line.sender)
  line.reason, line.word, line.dim = nil, nil, nil
  ns.Chat.Route(line)
  ns.View.JunkCount(#ring)
  Junk.Refresh()
  return line
end

local function row(i)
  local r = rows[i]
  if r then
    return r
  end
  r = CreateFrame("Frame", nil, win.list)
  r:SetHeight(Junk.ROW_H)
  r:EnableMouse(true)
  r.text = S.text(r, 11, S.C.text)
  r.text:SetPoint("LEFT", 4, 0)
  r.text:SetPoint("RIGHT", -84, 0)
  r.text:SetWordWrap(false)
  r.back = S.action(r, { icon = "check", label = L["Not junk"], boxed = true, row = true })
  r.back:SetPoint("RIGHT", -2, 0)
  r.back:SetScript("OnClick", function()
    Junk.NotJunk(r.index)
  end)
  r:SetScript("OnEnter", function(self)
    if GameTooltip and self.full then
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      S.TipLine(GameTooltip, self.full, "tipText", true)
      GameTooltip:Show()
    end
  end)
  r:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  rows[i] = r
  return r
end

function Junk.Refresh()
  if not win then
    return
  end
  -- our own label
  senders:SetLabel(string.format(L["Blocked senders: %d"], Junk.CountSenders()))
  local fit = math.max(1, math.floor(((win.list:GetHeight() or 200) - 4) / Junk.ROW_H))
  offset = math.max(0, math.min(offset, #ring - fit))
  for i = 1, fit do
    local index = #ring - offset - i + 1 -- the newest first
    local entry = ring[index]
    local r = row(i)
    if entry then
      local plain = Model.Strip(entry.line.text)
      r.index = index
      r.full = plain
      r.text:SetText(
        S.H.tipDim .. date("%H:%M", entry.at) .. "  " .. Junk.Reason(entry.line) .. "|r  " .. plain
      )
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", win.list, "TOPLEFT", 2, -2 - (i - 1) * Junk.ROW_H)
      r:SetPoint("RIGHT", win.list, "RIGHT", -2, 0)
      r:Show()
    else
      r:Hide()
    end
  end
  for i = fit + 1, #rows do
    rows[i]:Hide()
  end
end

function Junk.CountSenders()
  local n = 0
  for _ in pairs(profile().spam.senders) do
    n = n + 1
  end
  return n
end

-- The blocked senders as a menu: a click unblocks.
function Junk.SendersMenu(anchor)
  local items = {}
  local names = {}
  for name in pairs(profile().spam.senders) do
    names[#names + 1] = name
  end
  table.sort(names)
  for _, name in ipairs(names) do
    items[#items + 1] = {
      label = string.format(L["Unblock %s"], name),
      onClick = function()
        ns.Chat.UnblockSender(name)
        Junk.Refresh()
      end,
    }
  end
  if #items == 0 then
    items[1] = { label = L["Nobody is blocked."], disabled = true }
  end
  B.UI.Menu(anchor, L["Blocked senders"], items, ns.mod)
  return items
end

local function build()
  local Wd = B.UI.Widgets
  local p = profile()
  win = B.UI.Window("BastiansChatJunk", {
    module = "Chat",
    title = L["Junk"],
    width = 600,
    height = 420,
    minWidth = 460,
    minHeight = 300,
    db = p.junkWindow,
    onResize = function()
      Junk.Refresh()
    end,
  })
  local c = win.content
  local levels = {}
  for i, id in ipairs(ns.Rules.LEVEL_ORDER) do
    levels[id] = i .. ". " .. L["strength: " .. id]
  end
  level = Wd.Select(c, L["Spam filter"], levels, function(key)
    p.spam.level = key
    ns.Chat.RulesChanged()
  end)
  level:SetPoint("TOPLEFT", 10, -8)
  level:SetPoint("RIGHT", c, "RIGHT", -10, 0)
  action = Wd.Select(c, L["A blocked word"], {
    junk = L["goes to Junk"],
    dim = L["is shown dimmed"],
    hide = L["is hidden (still listed here)"],
  }, function(key)
    p.spam.action = key
    ns.Chat.RulesChanged()
  end)
  action:SetPoint("TOPLEFT", level, "BOTTOMLEFT", 0, -6)
  action:SetPoint("RIGHT", c, "RIGHT", -10, 0)
  block = Wd.Edit(
    c,
    L["Blocked (Enter saves; comma separated searches: wts gold, from:name, /pattern/)"],
    function(text)
      p.spam.block = text
      ns.Chat.RulesChanged()
    end
  )
  block:SetHeight(20)
  ns.Model.FilterBox(block)
  block:SetPoint("TOPLEFT", action, "BOTTOMLEFT", 0, -8)
  block:SetPoint("RIGHT", c, "RIGHT", -10, 0)
  allow = Wd.Edit(c, L["Allowed, they win (Enter saves; comma separated searches)"], function(text)
    p.spam.allow = text
    ns.Chat.RulesChanged()
  end)
  allow:SetHeight(20)
  ns.Model.FilterBox(allow)
  allow:SetPoint("TOPLEFT", block, "BOTTOMLEFT", 0, -6)
  allow:SetPoint("RIGHT", c, "RIGHT", -10, 0)
  senders = S.button(c, "", 160, 20)
  senders:SetPoint("TOPLEFT", allow, "BOTTOMLEFT", 0, -6)
  senders:SetScript("OnClick", function(self)
    Junk.SendersMenu(self)
  end)
  local clear = S.action(c, { icon = "junk", label = L["Empty the list"], boxed = true, row = true })
  clear:SetPoint("LEFT", senders, "RIGHT", 8, 0)
  clear:SetScript("OnClick", function()
    for i = #ring, 1, -1 do
      ring[i] = nil
    end
    ns.View.JunkCount(0)
    Junk.Refresh()
  end)
  -- a changed rule reaches the lines already shown ("apply to older
  -- messages ... immediately filter the whole chat, not only new ones")
  win.applyOld = Wd.Checkbox(c, L["Apply the filter to older lines too"], function(on)
    p.spam.applyOld = on and true or false
    if on then
      ns.Chat.Refilter()
    end
  end)
  win.applyOld:SetPoint("LEFT", clear, "RIGHT", 12, 0)
  win.applyOld:SetChecked(p.spam.applyOld ~= false)
  win.list = CreateFrame("Frame", nil, c)
  win.list:SetPoint("TOPLEFT", senders, "BOTTOMLEFT", 0, -8)
  win.list:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -10, 8)
  win.list.bg = S.fill(win.list, S.C.panel)
  win.list:EnableMouseWheel(true)
  win.list:SetScript("OnMouseWheel", function(_, delta)
    offset = math.max(0, offset - delta * 3)
    Junk.Refresh()
  end)
  Junk.win = win -- tests reach the window's controls
  return win
end

function Junk.Show()
  if not win then
    build()
  end
  local p = profile()
  level:SetValue(p.spam.level)
  action:SetValue(p.spam.action)
  block:SetText(p.spam.block or "")
  allow:SetText(p.spam.allow or "")
  win:Show()
  Junk.Refresh()
  return win
end

function Junk.Hide()
  if win then
    win:Hide()
  end
end

function Junk.Toggle()
  if win and win:IsShown() then
    Junk.Hide()
  else
    Junk.Show()
  end
end
