-- Bastian's Notes: the sharing dialogs (notes.md N3): send a list to the party, the raid, the guild
-- or one player, or copy it as text (G, H); a received or pasted list asks Accept or Decline (I).
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Widgets = B.UI.Widgets
local Notes = ns.Notes

local Share = {}
ns.Share = Share

local sendWin, sendInfo, whisperBox, textBox, sendList
local askWin, askText, asked -- asked = { offer, from }
local importWin, importBox

-- --- send -------------------------------------------------------------------------------------

local function send(channel)
  local target = channel == "WHISPER" and strtrim(whisperBox:GetText() or "") or nil
  local ok, why = Notes.Share(sendList, channel, target)
  if not ok then
    B:Say(why == "target" and L["Type the name of the player to whisper to."] or L["Not sent (%s)."], why)
    return false
  end
  sendWin:Hide()
  return true
end
Share.Send = send

local function buildSend()
  sendWin =
    B.UI.Window("BastiansNotesShare", { module = "Notes", title = L["Share"], width = 380, height = 250 })
  local c = sendWin.content
  sendInfo = S.text(c, 11, S.C.text)
  sendInfo:SetPoint("TOPLEFT", c, "TOPLEFT", 8, -8)
  sendInfo:SetPoint("TOPRIGHT", c, "TOPRIGHT", -8, -8)
  sendInfo:SetJustifyH("LEFT")
  local x = 8
  for _, ch in ipairs({ { "PARTY", "Party" }, { "RAID", "Raid" }, { "GUILD", "Guild" } }) do
    local b = S.button(c, L[ch[2]], 80, 22)
    b:SetPoint("TOPLEFT", c, "TOPLEFT", x, -44)
    b:SetScript("OnClick", function()
      send(ch[1])
    end)
    x = x + 86
  end
  whisperBox = Widgets.Edit(c, L["Player name"], function()
    send("WHISPER")
  end)
  whisperBox:SetPoint("TOPLEFT", c, "TOPLEFT", 8, -74)
  whisperBox:SetWidth(250)
  local whisper = S.button(c, L["Whisper"], 90, 22)
  whisper:SetPoint("LEFT", whisperBox, "RIGHT", 6, 0)
  whisper:SetScript("OnClick", function()
    send("WHISPER")
  end)
  local copyHint = S.text(c, 11, S.C.dim)
  copyHint:SetPoint("TOPLEFT", c, "TOPLEFT", 8, -106)
  copyHint:SetText(L["Or copy this text (Ctrl+C) for a forum, Discord or another account:"])
  textBox = CreateFrame("EditBox", nil, c)
  textBox:SetPoint("TOPLEFT", c, "TOPLEFT", 8, -124)
  textBox:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -8, 10)
  textBox:SetMultiLine(true)
  textBox:SetAutoFocus(false)
  textBox:SetFont(S.font(), S.size(11), "")
  S.ink(textBox, S.C.dim)
  textBox:SetScript("OnEscapePressed", function()
    sendWin:Hide()
  end)
  -- the text stays what it is: a change by the player is undone
  textBox:SetScript("OnTextChanged", function(self, byUser)
    if byUser and self.text then
      self:SetText(self.text)
      self:HighlightText()
    end
  end)
  Share.sendWin, Share.textBox, Share.whisperBox, Share.sendInfo = sendWin, textBox, whisperBox, sendInfo
end

-- Opens the send dialog for a list.
function Share.Open(listId)
  local offer, private = Notes.Payload(listId)
  if not offer then
    return false
  end
  if #offer.notes == 0 and #offer.bookmarks == 0 then
    B:Say(L["Nothing to share: every note of this list is private."])
    return false
  end
  if not sendWin then
    buildSend()
  end
  sendList = listId
  local words =
    string.format(L["%s: %d notes, %d bookmarks go along."], offer.name, #offer.notes, #offer.bookmarks)
  if private > 0 then
    words = words .. " " .. string.format(L["%d private notes stay here."], private)
  end
  sendInfo:SetText(words)
  textBox.text = Notes.ExportText(listId)
  textBox:SetText(textBox.text)
  sendWin:Show()
  textBox:HighlightText()
  return true
end

-- --- ask: Accept or Decline -----------------------------------------------------------------------

local function buildAsk()
  askWin = B.UI.Window(
    "BastiansNotesOffer",
    { module = "Notes", title = L["A list for you"], width = 360, height = 150 }
  )
  local c = askWin.content
  askText = S.text(c, 12, S.C.text)
  askText:SetPoint("TOPLEFT", c, "TOPLEFT", 8, -8)
  askText:SetPoint("TOPRIGHT", c, "TOPRIGHT", -8, -8)
  askText:SetJustifyH("LEFT")
  local accept = S.button(c, L["Accept"], 90, 22, true)
  accept:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -8, 8)
  accept:SetScript("OnClick", function()
    Share.Answer(true)
  end)
  local decline = S.button(c, L["Decline"], 90, 22)
  decline:SetPoint("RIGHT", accept, "LEFT", -6, 0)
  decline:SetScript("OnClick", function()
    Share.Answer(false)
  end)
  Share.askWin, Share.askText = askWin, askText
end

-- A checked offer: one dialog at a time; a second offer while one is open waits its turn.
local waiting = {}
function Share.Ask(offer, from)
  if asked then
    waiting[#waiting + 1] = { offer = offer, from = from }
    return
  end
  if not askWin then
    buildAsk()
  end
  asked = { offer = offer, from = from }
  askText:SetText(
    string.format(
      L['%s shares the list "%s" with %d notes and %d bookmarks. Nothing is kept without your click.'],
      from or "?",
      offer.name,
      #offer.notes,
      #offer.bookmarks
    )
  )
  askWin:Show()
end

function Share.Answer(yes)
  local a = asked
  asked = nil
  if askWin then
    askWin:Hide()
  end
  if a and yes then
    Notes.Accept(a.offer, a.from)
  end
  local nextOne = table.remove(waiting, 1)
  if nextOne then
    Share.Ask(nextOne.offer, nextOne.from)
  end
end

-- --- import a pasted text -----------------------------------------------------------------------

local function buildImport()
  importWin = B.UI.Window(
    "BastiansNotesImport",
    { module = "Notes", title = L["Import a list"], width = 380, height = 220 }
  )
  local c = importWin.content
  local hint = S.text(c, 11, S.C.dim)
  hint:SetPoint("TOPLEFT", c, "TOPLEFT", 8, -8)
  hint:SetText(L["Paste the text (Ctrl+V), then Read."])
  local box = CreateFrame("Frame", nil, c)
  box:SetPoint("TOPLEFT", c, "TOPLEFT", 8, -28)
  box:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -8, 38)
  S.panel(box, S.C.panel)
  importBox = CreateFrame("EditBox", nil, box)
  importBox:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -6)
  importBox:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -6, 6)
  importBox:SetMultiLine(true)
  importBox:SetAutoFocus(false)
  importBox:SetFont(S.font(), S.size(11), "")
  S.ink(importBox, S.C.text)
  local read = S.button(c, L["Read"], 90, 22, true)
  read:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -8, 8)
  read:SetScript("OnClick", function()
    Share.Read()
  end)
  Share.importWin, Share.importBox = importWin, importBox
end

function Share.OpenImport()
  if not importWin then
    buildImport()
  end
  importBox:SetText("")
  importWin:Show()
  importBox:SetFocus()
end

function Share.Read()
  local offer, why = Notes.ImportText(importBox:GetText() or "")
  if not offer then
    B:Say(L["This text holds no list (%s)."], why or "?")
    return false
  end
  importWin:Hide()
  return true
end

function Share.Hide()
  for _, w in ipairs({ sendWin, askWin, importWin }) do
    if w then
      w:Hide()
    end
  end
end

ns.mod.Share = Share -- for the tests and /bastians debug
