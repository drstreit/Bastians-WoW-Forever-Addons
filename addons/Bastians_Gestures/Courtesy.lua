-- Courtesy (gestures.md): what others do to the player, and a ready answer. A stranger's buff, a
-- resurrection, an emote aimed at you: with "Ask" a small bubble for eight seconds (the thank
-- emote at them, one of your thank-you lines, Not now); with "Automatic" one of them at once.
-- Once per person in ten minutes, never in combat, never in an instance unless the setting says
-- so. Nothing about another player is kept beyond that memory in RAM (CLAUDE.md §8).
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Model = ns.Model
local Compat = ns.Compat

local Courtesy = {}
ns.Courtesy = Courtesy

local mod
local state = { seen = {} }
local bubble -- the Ask frame
local pending -- the event the bubble shows

local function now()
  return (GetTime and GetTime()) or 0
end

local function settings()
  local p = mod.db.profile
  local inInstance = false
  if type(IsInInstance) == "function" then
    inInstance = IsInInstance() and true or false
  end
  return {
    mode = p.courtesy or "ask",
    instances = p.courtesyInstances and true or false,
    inInstance = inInstance,
    inCombat = (InCombatLockdown and InCombatLockdown()) and true or false,
  }
end

-- The sentence of an event, for the bubble.
function Courtesy.Words(event)
  if event.kind == "buff" then
    if event.what then
      return string.format(L["%s cast %s on you"], event.who, event.what)
    end
    return string.format(L["%s buffed you"], event.who)
  elseif event.kind == "rez" then
    return string.format(L["%s resurrected you"], event.who)
  elseif event.kind == "duel" then
    return string.format(L["%s challenges you to a duel"], event.who)
  elseif event.kind == "trade" then
    return string.format(L["%s wants to trade"], event.who)
  elseif event.kind == "invite" then
    return string.format(L["%s invites you to a group"], event.who)
  elseif event.kind == "camp" then
    return string.format(L["%s's camp warmed you"], event.who)
  end
  return event.text or string.format(L["%s greets you"], event.who)
end

-- A duel, a trade or a group invite (plan-second-wave.md S7): a bow or a wave, or a polite
-- decline; never answered automatically (a decline is a decision).
function Courtesy.IsRequest(event)
  return event.kind == "duel" or event.kind == "trade" or event.kind == "invite"
end

-- The thank emote of an event: a wave back for an emote, a bow for a request, thanks otherwise.
function Courtesy.EmoteFor(event)
  if event.kind == "emote" then
    return "WAVE"
  elseif Courtesy.IsRequest(event) then
    return "BOW"
  end
  return "THANK"
end

-- The polite decline of a request: a whisper to them (the first decline line, %t filled) and the
-- game's own decline. -> the whisper, or false.
function Courtesy.Decline(event)
  local text = Model.Fill(Model.Pick(mod.db.profile.declines or Model.DefaultDeclines(), function()
    return 1
  end) or "", { target = event.who })
  local sent = text ~= "" and Compat.SendChat(text, "WHISPER", nil, event.who) or false
  Compat.Decline(event.kind)
  return sent and text or false
end

-- Answers `event`: `choice` "emote" (the emote at them) or "line" (a random thank-you line), or
-- nil for either at random. -> what was sent, or false.
function Courtesy.Answer(event, choice, rand)
  rand = rand or math.random
  local lines = mod.db.profile.thanks or {}
  if Courtesy.IsRequest(event) then
    if choice == "line" then
      return Courtesy.Decline(event)
    elseif choice ~= "wave" then
      choice = "emote" -- never a random line for a request
    end
  end
  if choice == nil then
    choice = (#lines > 0 and rand(2) == 1) and "line" or "emote"
  end
  if choice == "line" then
    local text = Model.Pick(lines, rand)
    if not text then
      return false
    end
    local filled = Model.Fill(text, { target = event.who })
    Compat.SendChat(filled, "SAY", nil)
    return filled
  end
  local token = choice == "wave" and "WAVE" or Courtesy.EmoteFor(event)
  local unit = event.unit
  if unit and not UnitExists(unit) then
    unit = nil
  end
  B.Compat.Emote(token, unit)
  return token
end

-- ---------------------------------------------------------------------------------------------
-- The bubble
-- ---------------------------------------------------------------------------------------------

local function build()
  local f = CreateFrame("Frame", "BastiansGesturesCourtesy", UIParent)
  f:SetSize(340, 76)
  f:SetPoint("TOP", UIParent, "TOP", 0, -140)
  f:SetFrameStrata("DIALOG")
  S.panel(f, S.C.panel)
  f.who = S.text(f, 11, S.C.dim)
  f.who:SetPoint("TOPLEFT", 12, -10)
  f.who:SetPoint("RIGHT", -12, 0)
  f.who:SetJustifyH("LEFT")
  f.ask = S.text(f, 12, S.C.text)
  f.ask:SetPoint("TOPLEFT", 12, -26)
  f.ask:SetText(L["Thank them?"])
  f.emote = S.action(f, { icon = "invite", label = L["Thank"], primary = true })
  f.emote:SetPoint("BOTTOMLEFT", 12, 10)
  f.emote:SetScript("OnClick", function()
    Courtesy.Click("emote")
  end)
  f.wave = S.action(f, { icon = "invite", label = L["Wave"], boxed = true })
  f.wave:SetPoint("LEFT", f.emote, "RIGHT", 6, 0)
  f.wave:SetScript("OnClick", function()
    Courtesy.Click("wave")
  end)
  f.wave:Hide() -- a request's second answer only
  f.line = S.action(f, { icon = "service", label = L["Say thanks"], boxed = true })
  f.line:SetPoint("LEFT", f.emote, "RIGHT", 6, 0)
  f.line:SetScript("OnClick", function()
    Courtesy.Click("line")
  end)
  f.no = S.action(f, { icon = "close", label = L["Not now"] })
  f.no:SetPoint("LEFT", f.line, "RIGHT", 6, 0)
  f.no:SetScript("OnClick", function()
    Courtesy.Click(nil)
  end)
  f.until_ = 0
  f:SetScript("OnUpdate", function(self)
    if now() >= self.until_ then
      Courtesy.Click(nil)
    end
  end)
  f:Hide()
  return f
end

function Courtesy.Show(event)
  bubble = bubble or build()
  pending = event
  local request = Courtesy.IsRequest(event)
  bubble.who:SetText(Courtesy.Words(event))
  bubble.ask:SetText(request and L["Answer?"] or L["Thank them?"])
  bubble.emote.tip = "/" .. string.lower(Courtesy.EmoteFor(event)) .. " " .. (event.who or "")
  bubble.emote:SetLabel(request and L["Bow"] or L["Thank"])
  bubble.line:SetLabel(request and L["Decline politely"] or L["Say thanks"])
  bubble.wave:SetShown(request)
  bubble.line:ClearAllPoints()
  bubble.line:SetPoint("LEFT", request and bubble.wave or bubble.emote, "RIGHT", 6, 0)
  bubble.line:SetShown(request or #(mod.db.profile.thanks or {}) > 0)
  bubble:SetWidth(request and 440 or 340)
  bubble.until_ = now() + Model.BUBBLE_SECONDS
  bubble:Show()
end

function Courtesy.Hide()
  pending = nil
  if bubble then
    bubble:Hide()
  end
end

function Courtesy.IsShown()
  return bubble ~= nil and bubble:IsShown()
end

function Courtesy.Pending()
  return pending
end

-- A button of the bubble: the answer, then the bubble goes.
function Courtesy.Click(choice)
  local event = pending
  Courtesy.Hide()
  if event and choice then
    return Courtesy.Answer(event, choice)
  end
  return false
end

-- An event arrived: the model decides, the bubble asks or the answer goes out.
function Courtesy.Offer(event)
  if not mod or not mod:IsEnabled() then
    return nil
  end
  local t = now()
  Model.Forget(state, t)
  local s = settings()
  if Courtesy.IsRequest(event) and s.mode == "auto" then
    s.mode = "ask" -- a request is never answered for the player
  end
  local decision = Model.Courtesy(event, state, t, s)
  if decision == "ask" then
    Courtesy.Show(event)
  elseif decision == "auto" then
    Courtesy.Answer(event, nil)
  end
  return decision
end

-- ---------------------------------------------------------------------------------------------
-- The events
-- ---------------------------------------------------------------------------------------------

-- UNIT_AURA on the player with the retail family's payload: `updateInfo.addedAuras`, each with
-- `sourceUnit`, `isHelpful`, `name` (assumed on Forever, forever-api.md).
function Courtesy.OnAura(_, _, unit, info)
  if unit ~= "player" or type(info) ~= "table" or type(info.addedAuras) ~= "table" then
    return
  end
  for _, aura in ipairs(info.addedAuras) do
    local source = type(aura) == "table" and aura.sourceUnit or nil
    if aura.isHelpful and source and not Compat.IsMineOrGroup(source) then
      local who = Compat.UnitPlayerName(source)
      if who then
        Courtesy.Offer({ kind = "buff", who = who, unit = source, what = aura.name })
      end
    end
  end
end

function Courtesy.OnResurrect(_, _, who)
  if type(who) == "string" and who ~= "" then
    Courtesy.Offer({ kind = "rez", who = who })
  end
end

-- CHAT_MSG_TEXT_EMOTE: the line ("Grimtok waves at you.") and the sender.
function Courtesy.OnEmote(_, _, text, sender)
  if type(sender) ~= "string" or sender == "" or not Model.AimedAtMe(text) then
    return
  end
  local who = sender:match("^([^%-]+)") or sender
  if who == Compat.UnitPlayerName("player") then
    return
  end
  Courtesy.Offer({ kind = "emote", who = who, text = text })
end

-- DUEL_REQUESTED (the challenger's name), TRADE_SHOW (the partner is the unit "NPC"),
-- PARTY_INVITE_REQUEST (the inviter's name); the retail family's events, assumed on Forever.
function Courtesy.OnDuel(_, _, who)
  if type(who) == "string" and who ~= "" then
    Courtesy.Offer({ kind = "duel", who = who })
  end
end

function Courtesy.OnTrade()
  local who = Compat.UnitPlayerName("NPC")
  if who and not Compat.IsMineOrGroup("NPC") then
    Courtesy.Offer({ kind = "trade", who = who, unit = "NPC" })
  end
end

function Courtesy.OnInvite(_, _, who)
  if type(who) == "string" and who ~= "" then
    Courtesy.Offer({ kind = "invite", who = who })
  end
end

-- BASTIANS_CAMP_WARMED (Bastian's Campfire, the bus): the host's name when the client gives it.
-- Campfire reads UNIT_AURA first (it loads first), so the host is remembered and the same aura's
-- buff courtesy below is not asked twice.
function Courtesy.OnCampWarmed(_, _, who)
  if type(who) == "string" and who ~= "" and who ~= Compat.UnitPlayerName("player") then
    Courtesy.Offer({ kind = "camp", who = who })
  end
end

function Courtesy.Attach(m)
  mod = m
  state = { seen = {} }
  m:On("BASTIANS_CAMP_WARMED", Courtesy.OnCampWarmed)
  m:RegisterEvent("UNIT_AURA", Courtesy.OnAura)
  m:RegisterEvent("RESURRECT_REQUEST", Courtesy.OnResurrect)
  m:RegisterEvent("CHAT_MSG_TEXT_EMOTE", Courtesy.OnEmote)
  m:RegisterEvent("DUEL_REQUESTED", Courtesy.OnDuel)
  m:RegisterEvent("TRADE_SHOW", Courtesy.OnTrade)
  m:RegisterEvent("PARTY_INVITE_REQUEST", Courtesy.OnInvite)
end

function Courtesy.Detach()
  Courtesy.Hide()
  state = { seen = {} }
end

-- The courtesy memory (tests): how many people were answered lately.
function Courtesy.Remembered()
  local n = 0
  for _ in pairs(state.seen or {}) do
    n = n + 1
  end
  return n
end
