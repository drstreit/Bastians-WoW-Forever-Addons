-- Bastian's Helpers, the warnings and the session panel (helpers.md "Warnings and the session
-- panel"): durability and bag space in the notice strip once per drop; `/bhelp` shows the money
-- and experience of this session per hour, the time to the next level, durability, free bag
-- slots and the hearthstone.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Helpers = ns.Helpers
local Model = Helpers.Model

local Info = {}
ns.Info = Info
Helpers.Info = Info

local session -- { start, money, xp = { xp, max, level }, gained }
local lastDurability, lastFree
local win

-- ---------------------------------------------------------------------------------------------
-- The session
-- ---------------------------------------------------------------------------------------------

local function xpNow()
  local xp, max, level = B.Compat.GetPlayerXP()
  return { xp = xp, max = max, level = level }
end

function Info.Start()
  session = { start = GetTime(), money = B.Compat.GetMoney(), xp = xpNow(), gained = 0 }
  Info.session = session
end

function Info.OnXP()
  if not session then
    return
  end
  local now = xpNow()
  session.gained = session.gained + Model.XPGain(session.xp, now)
  session.xp = now
end

-- { seconds, money, moneyPerHour, xpPerHour, toLevel } of this session.
function Info.Stats()
  if not session then
    return nil
  end
  local seconds = GetTime() - session.start
  local money = B.Compat.GetMoney() - session.money
  local xpPerHour = Model.PerHour(session.gained, seconds)
  local left = session.xp.max and session.xp.xp and (session.xp.max - session.xp.xp) or nil
  return {
    seconds = seconds,
    money = money,
    moneyPerHour = Model.PerHour(money, seconds),
    xp = session.gained,
    xpPerHour = xpPerHour,
    toLevel = Model.ToLevel(left, xpPerHour),
  }
end

-- ---------------------------------------------------------------------------------------------
-- The warnings
-- ---------------------------------------------------------------------------------------------

function Info.CheckDurability()
  local lowest = B.Compat.GetDurability()
  if Helpers.On("warnDurability") and Model.Crossed(lastDurability, lowest, Helpers.DURABILITY_WARN) then
    Helpers.Notice(string.format(L["Your gear is at %d%%: time for a repair"], math.floor(lowest * 100)))
  end
  lastDurability = lowest
end

function Info.CheckBags()
  local free = B.Compat.BagSpace()
  if Helpers.On("warnBags") and Model.Crossed(lastFree, free, Helpers.BAGS_WARN) then
    Helpers.Notice(free == 0 and L["Your bags are full"] or string.format(L["Only %d bag slots free"], free))
  end
  lastFree = free
end

-- ---------------------------------------------------------------------------------------------
-- The panel
-- ---------------------------------------------------------------------------------------------

-- The panel's lines: { label, value } (a value nil reads "unknown").
function Info.Lines()
  local s = Info.Stats() or {}
  local lines = {}
  local function add(label, value)
    lines[#lines + 1] = { label = label, value = value }
  end
  add(L["This session"], Helpers.Duration(s.seconds))
  local money = s.money and B.UI.Money(s.money)
  if money and s.moneyPerHour then
    money = money .. "  " .. string.format(L["(%s per hour)"], B.UI.Money(s.moneyPerHour))
  end
  add(L["Money"], money)
  local _, max = B.Compat.GetPlayerXP()
  if max then
    add(L["Experience per hour"], s.xpPerHour and tostring(math.floor(s.xpPerHour)) or nil)
    add(L["Next level in"], Helpers.Duration(s.toLevel))
  end
  local lowest = B.Compat.GetDurability()
  add(L["Durability"], lowest and (math.floor(lowest * 100) .. "%") or nil)
  local free, total = B.Compat.BagSpace()
  add(L["Free bag slots"], free and string.format("%d / %d", free, total) or nil)
  local hearth = B.Compat.GetHearthstone()
  if hearth and hearth.bindName then
    local when = hearth.ready and L["ready"] or Helpers.Duration(hearth.remaining)
    add(L["Hearthstone"], hearth.bindName .. (when and ("  " .. S.H.muted .. when .. "|r") or ""))
  end
  return lines
end

local ROW_H = 20

local function build()
  local db = Helpers.Profile().window
  win = B.UI.Window("BastiansHelpersPanel", {
    module = "Helpers",
    title = L["Helpers"],
    width = 320,
    height = 190,
    minWidth = 260,
    minHeight = 150,
    db = db,
  })
  win.rows = {}
  local elapsed = 0
  win.frame:HookScript("OnUpdate", function(_, dt) -- runs only while the panel is shown
    elapsed = elapsed + (dt or 0)
    if elapsed >= 1 then
      elapsed = 0
      Info.Refresh()
    end
  end)
  Info.win = win
end

function Info.Refresh()
  if not (win and win:IsShown()) then
    return
  end
  for i, line in ipairs(Info.Lines()) do
    local row = win.rows[i]
    if not row then
      row = {
        label = S.text(win.content, 12, S.C.muted),
        value = S.text(win.content, 12, S.C.text),
      }
      row.label:SetPoint("TOPLEFT", win.content, "TOPLEFT", 10, -8 - (i - 1) * ROW_H)
      row.value:SetPoint("TOPRIGHT", win.content, "TOPRIGHT", -10, -8 - (i - 1) * ROW_H)
      row.value:SetJustifyH("RIGHT")
      win.rows[i] = row
    end
    row.label:SetText(line.label)
    row.value:SetText(line.value or (S.H.muted .. L["unknown"] .. "|r"))
    row.label:Show()
    row.value:Show()
  end
end

function Info.Open()
  if not win then
    build()
  end
  win:Toggle()
  Info.Refresh()
  return win:IsShown()
end

function Info.Attach(mod)
  if not session then
    Info.Start()
  end
  mod:RegisterEvent("PLAYER_XP_UPDATE", Info.OnXP)
  mod:RegisterEvent("PLAYER_LEVEL_UP", function()
    C_Timer.After(0, Info.OnXP) -- the new level's numbers come a moment later
  end)
  mod:RegisterEvent("UPDATE_INVENTORY_DURABILITY", Info.CheckDurability)
  mod:RegisterEvent("BAG_UPDATE_DELAYED", function()
    Info.CheckBags()
    ns.Mail.OnBags() -- the mail rules' buttons (#18)
  end)
  mod:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    Info.CheckDurability()
    Info.CheckBags()
  end)
end
