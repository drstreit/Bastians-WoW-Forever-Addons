-- Bastian's Alts, the mailbox (alts.md "Asking for items by mail"): a strip on the mail frame
-- names who asks this character for what; "Fill mail" writes that mail (the recipient, the
-- subject, the requested stacks from the bags) for the player to send. A sent mail answers the
-- requests it carried and lands in the recipient's recorded mailbox.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Alts = ns.Alts
local Model = Alts.Model

local Mail = {}
ns.Mail = Mail
Alts.MailStrip = Mail

Mail.WIDTH = 340
local mod, strip
local open = false
local lastSend -- { recipient, items } of the mail the player is sending, kept for MAIL_SEND_SUCCESS
local attached = {} -- the attachments as the last MAIL_SEND_INFO_UPDATE saw them: SendMail's
-- post-hook may come after the client cleared the send tab

local function global()
  return mod.db.global
end

-- The asker the strip shows: the first of this character's request groups.
function Mail.Current()
  return Model.RequestsFor(global(), Alts.Key())[1]
end

-- "Linen Cloth x40 (20 in the bank)" for a group's items, from what this character holds.
function Mail.Words(group)
  local places = Model.Places(Alts.Me())
  local parts = {}
  for _, it in ipairs(group.items) do
    local name = B:Entity("item:" .. it[1]):Name() or ("item " .. it[1])
    local text = name .. " x" .. it[2]
    local e = places[it[1]]
    if e and e.bank > 0 then
      text = text .. " " .. string.format(L["(%d in the bank)"], e.bank)
    end
    parts[#parts + 1] = text
  end
  return table.concat(parts, ", ")
end

local function build()
  local parent = rawget(_G, "MailFrame") or UIParent
  strip = CreateFrame("Frame", "BastiansAltsMailStrip", parent)
  strip:SetSize(Mail.WIDTH, 58)
  if parent == UIParent then
    strip:SetPoint("TOP", UIParent, "TOP", 0, -120)
  else
    strip:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, -4)
  end
  S.panel(strip, S.C.panel)
  strip.text = S.text(strip, 11, S.C.text)
  strip.text:SetPoint("TOPLEFT", strip, "TOPLEFT", 8, -6)
  strip.text:SetPoint("RIGHT", strip, "RIGHT", -96, 0)
  strip.text:SetJustifyH("LEFT")
  strip.text:SetWordWrap(true)
  strip.fill = S.action(strip, { icon = "send", label = L["Fill mail"], primary = true })
  strip.fill:SetPoint("RIGHT", strip, "RIGHT", -8, 0)
  strip.fill:SetScript("OnClick", function()
    Mail.Fill()
  end)
  strip:Hide()
  Mail.strip = strip
end

-- Shows the strip while the mailbox is open and someone asks this character for something.
function Mail.Update()
  if not mod then
    return
  end
  local group = open and Mail.Current()
  if not group then
    if strip then
      strip:Hide()
    end
    return
  end
  if not strip then
    build()
  end
  local asker = global().characters[group.asker]
  strip.text:SetText(
    string.format(L["%s asks for: %s"], asker and asker.name or group.asker, Mail.Words(group))
  )
  strip:Show()
end

-- Writes the mail for the strip's asker: recipient, subject and the requested stacks from the
-- bags (whole stacks, never soulbound, up to the free attachment slots). Returns the stacks put in.
function Mail.Fill()
  local group = Mail.Current()
  local asker = group and global().characters[group.asker]
  if not (asker and B.Compat.MailPrepare(asker.full or asker.name, L["Bastian's Alts: your request"])) then
    return 0
  end
  local want = {}
  for _, it in ipairs(group.items) do
    want[it[1]] = (want[it[1]] or 0) + it[2]
  end
  local put = 0
  for _, slot in ipairs(B.Compat.GetBagItems()) do
    local need = want[slot.itemID]
    if need and need > 0 and not slot.bound then
      if B.Compat.MailFreeSlots() == 0 or not B.Compat.MailAttach(slot.bag, slot.slot) then
        break
      end
      want[slot.itemID] = need - (slot.count or 1)
      put = put + 1
    end
  end
  return put
end

-- The mail being sent: its recipient and attachments, read before the client clears them.
function Mail.OnSend(recipient)
  local now = B.Compat.GetSendMailItems()
  lastSend = { recipient = recipient, items = next(now) and now or attached }
end

function Mail.OnAttachments()
  attached = B.Compat.GetSendMailItems()
end

function Mail.OnSent()
  if not lastSend then
    return
  end
  local send = lastSend
  lastSend, attached = nil, {}
  if next(send.items) then
    Model.Sent(global(), Alts.Key(), send.recipient, send.items, time())
    B:InvalidateEntities("character")
    B:Fire("BASTIANS_ALTS_CHANGED")
  end
  Mail.Update()
end

function Mail.Attach(module)
  mod = module
  module:RegisterEvent("MAIL_SHOW", function()
    open = true
    Mail.Update()
  end)
  module:RegisterEvent("MAIL_CLOSED", function()
    open = false
    Mail.Update()
  end)
  module:RegisterEvent("MAIL_SEND_SUCCESS", Mail.OnSent)
  module:RegisterEvent("MAIL_FAILED", function()
    lastSend = nil
  end)
  module:RegisterEvent("MAIL_SEND_INFO_UPDATE", Mail.OnAttachments)
  -- BASTIANS_ALTS_CHANGED reaches Mail.Update through the module's one handler (Alts.lua)
  local send = rawget(_G, "SendMail")
  if type(send) == "function" and not Mail.hooked then
    Mail.hooked = true
    hooksecurefunc("SendMail", function(recipient)
      Mail.OnSend(recipient)
    end)
  end
end
