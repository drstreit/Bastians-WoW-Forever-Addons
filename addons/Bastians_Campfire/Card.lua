-- The fire card of Bastian's Campfire (campfire.md "The fire card"): a small card while a fire is
-- near, while the player rests by it, and a minute after; what the camp gives, what the player
-- could add from the bags, the time until warm or left. Sit and Share the fire on it. It ticks once
-- a second only while shown (CLAUDE.md §4.7).
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Camp = ns.Camp
local Model = ns.Model

local Card = {}
ns.Card = Card

local mod, frame

-- The benefit's word.
function Card.Label(key)
  local b = Camp.BENEFITS[key]
  return b and L[b.label] or key
end

local function list(keys, word)
  local out = {}
  for _, key in ipairs(keys) do
    out[#out + 1] = word(key)
  end
  return table.concat(out, ", ")
end

local function featureName(feature)
  return L[feature.name]
end

-- The card's two lines for a state of Model.Card: the heading and the sentence.
function Card.Words(card)
  local could = #card.could > 0 and string.format(L["You could add: %s."], list(card.could, featureName))
    or nil
  local have = #card.have > 0 and list(card.have, Card.Label) or nil
  local parts = {}
  local heading
  if card.state == "warming" then
    heading = L["Getting warm"]
    parts[#parts + 1] = have and string.format(L["A fire burns: %s."], have) or L["A fire burns."]
    parts[#parts + 1] = could
    if card.warmIn then
      parts[#parts + 1] = string.format(L["%s until you are warm."], Model.Clock(card.warmIn))
    else
      parts[#parts + 1] = L["Rest a minute to get warm."]
    end
  elseif card.state == "warm" or card.state == "fading" then
    heading = card.state == "fading" and L["The warmth is fading"] or L["You are warm"]
    parts[#parts + 1] = string.format(L["Warm: %s."], have)
    parts[#parts + 1] = could
    parts[#parts + 1] = card.left and string.format(L["%s left."], Model.Clock(card.left))
      or L["Time left: unknown."]
  elseif card.state == "near" then
    heading = L["A fire nearby"]
    parts[#parts + 1] = L["A fire burns."]
    parts[#parts + 1] = could
    parts[#parts + 1] = L["Sit by it for a minute to get warm."]
  else
    heading = L["The fire is behind you"]
    parts[#parts + 1] = have and string.format(L["Warm: %s."], have) or L["No fire nearby."]
  end
  local text = {}
  for _, p in ipairs(parts) do
    if p then
      text[#text + 1] = p
    end
  end
  return heading, table.concat(text, " ")
end

local function build()
  local f = CreateFrame("Frame", "BastiansCampfireCard", UIParent)
  f:SetSize(320, 92)
  f:SetPoint("TOP", UIParent, "TOP", 0, -230)
  f:SetFrameStrata("MEDIUM")
  S.panel(f, S.C.panel)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(18, 18)
  f.icon:SetPoint("TOPLEFT", 10, -9)
  f.icon:SetTexture(B.UI.IconTexture("campfire"))
  f.heading = S.text(f, 11, S.C.dim)
  f.heading:SetPoint("LEFT", f.icon, "RIGHT", 6, 0)
  f.heading:SetPoint("RIGHT", -28, 0)
  f.heading:SetJustifyH("LEFT")
  f.text = S.text(f, 12, S.C.text)
  f.text:SetPoint("TOPLEFT", 12, -32)
  f.text:SetPoint("RIGHT", -12, 0)
  f.text:SetJustifyH("LEFT")
  f.text:SetWordWrap(true)
  f.sit = S.action(f, { icon = "invite", label = L["Sit"], primary = true })
  f.sit:SetPoint("BOTTOMLEFT", 10, 8)
  f.sit:SetScript("OnClick", function()
    B.Compat.Emote("SIT")
  end)
  f.share = S.action(f, { icon = "spot", label = L["Share the fire"], boxed = true })
  f.share:SetPoint("LEFT", f.sit, "RIGHT", 6, 0)
  f.share:SetScript("OnClick", function()
    ns.Beacon.Share()
  end)
  f.close = S.action(f, { icon = "close", label = L["Close"], only = true })
  f.close:SetPoint("TOPRIGHT", -6, -6)
  f.close:SetScript("OnClick", function()
    Card.Dismiss()
  end)
  f.elapsed = 0
  f:SetScript("OnUpdate", function(self, dt)
    self.elapsed = self.elapsed + (dt or 0)
    if self.elapsed >= 1 then
      self.elapsed = 0
      Card.Refresh()
    end
  end)
  f:Hide()
  return f
end

-- Draws the card from the watch, or hides it.
function Card.Refresh()
  if not mod or not mod:IsEnabled() or not mod.db.profile.card then
    if frame then
      frame:Hide()
    end
    return
  end
  local card = ns.Watch.Card()
  if not card.show or Card.dismissed == card.state then
    if frame then
      frame:Hide()
    end
    if not card.show then
      Card.dismissed = nil
    end
    return
  end
  frame = frame or build()
  local heading, text = Card.Words(card)
  frame.heading:SetText(heading)
  frame.text:SetText(text)
  frame.share:SetShown(mod.db.profile.beacon and (card.state ~= "away"))
  frame:SetHeight(math.max(92, 52 + (frame.text:GetStringHeight() or 14)))
  frame:Show()
end

-- The close button: the card stays away until the state changes.
function Card.Dismiss()
  local card = ns.Watch.Card()
  Card.dismissed = card.state
  if frame then
    frame:Hide()
  end
end

function Card.IsShown()
  return frame ~= nil and frame:IsShown()
end

function Card.Frame()
  return frame
end

function Card.Attach(m)
  mod = m
  Card.dismissed = nil
  Card.Refresh()
end

function Card.Detach()
  if frame then
    frame:Hide()
  end
end
