-- Bastian's Helpers, the mailbox (helpers.md "Mail"): Take all, the Send to column with the
-- account's characters and the recent recipients, the last recipient in the send tab.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Helpers = ns.Helpers
local Model = Helpers.Model

local Mail = {}
ns.Mail = Mail
Helpers.Mail = Mail

Mail.STEP_WAIT = 0.5 -- seconds Take all waits for MAIL_INBOX_UPDATE before the next step

local open = false
local take -- { money, items, mails, seq, waiting } while Take all runs
local button, column

-- ---------------------------------------------------------------------------------------------
-- Take all
-- ---------------------------------------------------------------------------------------------

local function finish(why)
  local t = take
  take = nil
  if not t then
    return
  end
  local words = string.format(L["Took %s and %d items from %d mails"], B.UI.Money(t.money), t.items, t.mails)
  local cod = Model.CodLeft(B.Compat.GetInboxMail())
  if why == "full" then
    words = words .. "; " .. L["the bags are full"]
  end
  if cod > 0 then
    words = words .. "; " .. string.format(L["%d cash-on-delivery mails left"], cod)
  end
  Helpers.Notice(words)
end

function Mail.Step()
  if not take then
    return
  end
  if not open then
    return finish("closed")
  end
  local mails = B.Compat.GetInboxMail()
  local pick, why = Model.NextMail(mails, (B.Compat.BagSpace()))
  if not pick then
    return finish(why)
  end
  local m = mails[pick.index]
  local ok
  if pick.what == "money" then
    ok = B.Compat.TakeInboxMoney(pick.index)
    take.money = take.money + (ok and m.money or 0)
  else
    ok = B.Compat.TakeInboxItems(pick.index)
    take.items = take.items + (ok and m.items or 0)
  end
  if not ok then
    return finish("failed")
  end
  if pick.what == "items" or (m.items or 0) == 0 then -- a mail counts at its last step
    take.mails = take.mails + 1
  end
  take.seq = take.seq + 1
  take.waiting = take.seq
  local seq = take.seq
  C_Timer.After(Mail.STEP_WAIT, function() -- the client may stay silent: go on anyway
    if take and take.waiting == seq then
      take.waiting = nil
      Mail.Step()
    end
  end)
end

function Mail.TakeAll()
  if take or not open then
    return false
  end
  take = { money = 0, items = 0, mails = 0, seq = 0 }
  Mail.Step()
  return true
end

local function onInbox()
  if take and take.waiting then
    take.waiting = nil
    C_Timer.After(0.05, Mail.Step) -- after the client has settled its list
  end
end

-- ---------------------------------------------------------------------------------------------
-- Send to and the last recipient
-- ---------------------------------------------------------------------------------------------

function Mail.Names()
  return Model.Recipients(
    Helpers.Global().characters,
    Helpers.Key(),
    Helpers.Char().recent,
    Helpers.SEND_TO_MAX
  )
end

local function buildColumn(parent)
  column = CreateFrame("Frame", "BastiansHelpersSendTo", parent)
  column:SetSize(120, 30)
  if parent == UIParent then
    column:SetPoint("TOP", UIParent, "TOP", 240, -120)
  else
    column:SetPoint("TOPLEFT", parent, "TOPRIGHT", 4, 0)
  end
  S.panel(column, S.C.panel)
  column.title = S.text(column, 11, S.C.muted)
  column.title:SetPoint("TOPLEFT", column, "TOPLEFT", 8, -6)
  column.title:SetText(L["Send to"])
  column.buttons = {}
end

function Mail.UpdateColumn()
  local names = open and Helpers.On("sendTo") and Mail.Names() or {}
  if #names == 0 then
    if column then
      column:Hide()
    end
    return
  end
  if not column then
    buildColumn(rawget(_G, "MailFrame") or UIParent)
  end
  for i, name in ipairs(names) do
    local b = column.buttons[i]
    if not b then
      b = S.button(column, "", 104, 20)
      b:SetPoint("TOPLEFT", column, "TOPLEFT", 8, -22 - (i - 1) * 22)
      b:SetScript("OnClick", function(self)
        B.Compat.MailRecipient(self.name)
      end)
      column.buttons[i] = b
    end
    b.name = name
    b:SetLabel(name)
    b:Show()
  end
  for i = #names + 1, #column.buttons do
    column.buttons[i]:Hide()
  end
  column:SetHeight(28 + #names * 22)
  column:Show()
end

-- The last recipient into the empty send tab (a moment later: the client resets the tab itself).
function Mail.FillLast()
  C_Timer.After(0.1, function()
    local last = Helpers.Char().recent[1]
    if open and Helpers.On("lastRecipient") and last and (B.Compat.MailRecipientText() or "") == "" then
      B.Compat.MailRecipient(last)
    end
  end)
end

function Mail.OnSend(recipient)
  if type(recipient) == "string" and recipient ~= "" and Helpers.mod and Helpers.mod:IsEnabled() then
    Helpers.Char().recent = Model.Remember(Helpers.Char().recent, recipient, Helpers.RECENT_MAX)
  end
end

-- ---------------------------------------------------------------------------------------------
-- The mailbox
-- ---------------------------------------------------------------------------------------------

local function buildButton()
  local parent = rawget(_G, "InboxFrame") or rawget(_G, "MailFrame") or UIParent
  button = S.button(parent, L["Take all"], 90, 22, true)
  button:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", 0, 4)
  button:SetScript("OnClick", Mail.TakeAll)
  Mail.button = button
end

function Mail.OnShow()
  open = true
  if Helpers.On("takeAll") then
    if not button then
      buildButton()
    end
    button:Show()
  elseif button then
    button:Hide()
  end
  Mail.UpdateColumn()
  Mail.FillLast()
end

function Mail.OnClose()
  open = false
  if button then
    button:Hide()
  end
  Mail.UpdateColumn()
  if take then
    finish("closed")
  end
end

function Mail.Attach(mod)
  mod:RegisterEvent("MAIL_SHOW", Mail.OnShow)
  mod:RegisterEvent("MAIL_CLOSED", Mail.OnClose)
  mod:RegisterEvent("MAIL_INBOX_UPDATE", onInbox)
  mod:RegisterEvent("MAIL_SEND_SUCCESS", Mail.FillLast)
  if not Mail.hooked and type(rawget(_G, "SendMail")) == "function" then
    Mail.hooked = true
    hooksecurefunc("SendMail", function(recipient)
      Mail.OnSend(recipient)
    end)
  end
end
