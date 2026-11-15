-- Bastian's Chat version 3, the cards of the open requests (plan-chat-v3.md §3, ADR 0075): what a
-- whisper, a raid warning, a mention or a watch-list match says on its card, and the buttons that
-- answer it on the card. One card frame (S.card) per request in view; the store keeps the state.
local _, ns = ...
local B = Bastians
local S = B.UI.Style
local L = ns.L
local Model, Compat = ns.Model, ns.Compat

local Cards = {}
ns.Cards = Cards

Cards.W = 230 -- a card in the strip
Cards.H = 70
Cards.FRESH_SECS = 8 -- a card is lit this long after its request came
Cards.BUTTONS = 3

local KIND_WORDS = {
  whisper = "whisper",
  warning = "raid warning",
  mention = "mentioned you",
  watch = "on your watch list",
  invite = "invites you",
  duel = "challenges you to a duel",
  trade = "opened a trade",
  ready = "ready check",
  summon = "summons you",
  resurrect = "offers to resurrect you",
}
-- Courtesy's kind deeds (V6): what the person did
local DEED_WORDS = {
  buff = "buffed you",
  emote = "greeted you",
  camp = "warmed you at their fire",
  accepted = "you joined their group",
}
-- the catch-up card's title by what the player missed it in (V20)
local DIGEST_TITLES = {
  fight = "During the fight",
  cutscene = "During the cutscene",
  loading = "During the loading screen",
}
-- a request's two answers on its card (V6); a trade can only be closed
local ANSWER_WORDS = {
  invite = { "Accept", "Decline" },
  duel = { "Accept", "Decline" },
  trade = { nil, "Cancel trade" },
  ready = { "Ready", "Not ready" },
  summon = { "Accept", "Decline" },
  resurrect = { "Accept", "Decline" },
}

local function store()
  return ns.Chat.Store()
end

-- The words of a request's card: title, the kind line, the text. Pure but for the store's record.
function Cards.Words(ask, rec)
  local who = ask.who and Model.ShortName(ask.who) or (ask.bn and L["Battle.net friend"]) or "?"
  local kind = L[KIND_WORDS[ask.kind] or ask.kind]
  if ask.kind == "deed" then
    kind = L[DEED_WORDS[ask.deed] or "was kind to you"]
  end
  if ask.rel == "gm" then
    kind = L["Game Master"]
  end
  if ask.kind == "watch" then
    kind = ns.Rows.WhyText(ask) or kind -- why it is on the list (V19)
  end
  if ask.kind == "whisper" and (ask.unread or 0) > 1 then
    kind = kind .. " (" .. ask.unread .. ")"
  end
  local title = who
  if ask.kind == "warning" then
    title = L["Raid warning"]
    kind = who
  elseif ask.kind == "away" then
    return L["You are away"], "", ns.Away.Settings().text -- V10
  elseif ask.kind == "digest" then
    local heading = DIGEST_TITLES[ask.after] or "While you were away" -- V20: the catch-up cards
    return L[heading], L["%d min"]:format(ask.minutes or 0), ns.Away.SummaryText(ask.summary)
  end
  local text = rec and rec.body
  if type(text) ~= "string" then
    text = ""
  end
  if ask.refused then
    text = L["Answer in the game's window."] -- the client refused the call (probe X3)
  end
  return title, kind, text
end

-- The buttons of a request: { label, icon, run = fn(ask) }.
function Cards.Buttons(ask, rec)
  local out = {}
  local function add(label, icon, run)
    out[#out + 1] = { label = label, icon = icon, run = run }
  end
  if ask.kind == "whisper" then
    if ask.who or ask.bn then
      add(L["Reply"], "messenger", function(a)
        if not Cards.Open(a) and a.who then
          Compat.OpenChat("/w " .. a.who .. " ")
        end
      end)
    end
  elseif ask.kind == "mention" then
    local slash = ns.Rows.SlashFor(rec)
    if slash then
      add(L["Reply"], "messenger", function()
        Compat.OpenChat(slash)
      end)
    end
    if ask.who then
      add(L["Whisper"], "invite", function(a)
        Compat.OpenChat("/w " .. a.who .. " ")
      end)
    end
  elseif ask.kind == "watch" and ask.who then
    add(L["Whisper"], "invite", function(a)
      Compat.OpenChat("/w " .. a.who .. " ")
    end)
  elseif ask.kind == "away" then
    add(L["I am back"], "close", function()
      ns.Away.Stop()
    end)
    return out
  elseif ANSWER_WORDS[ask.kind] and not ask.refused then
    local words = ANSWER_WORDS[ask.kind]
    if words[1] then
      add(L[words[1]], nil, function(a)
        ns.Requests.Answer(a, true)
      end)
    end
    add(L[words[2]], "close", function(a)
      ns.Requests.Answer(a, false)
    end)
  end
  if ask.moment then
    add(L["Courtesy"], "app_courtesy", function(a)
      ns.Requests.Reopen(a)
    end)
  end
  -- a request the game asks is answered or ended by the game; anything else can be put away
  if not ANSWER_WORDS[ask.kind] or ask.refused then
    add(ask.kind == "warning" and L["Got it"] or L["Dismiss"], "close", function(a)
      store():Dismiss(a.id)
    end)
  end
  return out
end

-- A whisper's conversation, opened from its card or chip: the person's place in the one window,
-- the input line on them (plan-chat-one-window.md §3.1). False when there is no conversation.
function Cards.Open(ask)
  local key = ask.bn and ("bn:" .. tostring(ask.bn)) or ask.who
  if not key or not ns.People.Convo(key) then
    return false
  end
  ask.unread = 0
  return ns.Front.ShowPerson(key, true)
end

local make

-- A card frame, drawn in the palette of where it stands (Chat's look, V13).
function Cards.Make(parent)
  return S.WithPalette(S.PaletteOf(parent), make, parent)
end

function make(parent)
  local c = S.card(parent, {})
  c:SetSize(Cards.W, Cards.H)
  c.title = S.text(c.body, 12, S.C.text)
  c.title:SetPoint("TOPLEFT", c.body, "TOPLEFT", 0, 0)
  c.title:SetJustifyH("LEFT")
  c.title:SetWordWrap(false)
  c.kind = S.SetRole(S.text(c.body, 10, S.C.dim), "number")
  c.kind:SetPoint("TOPRIGHT", c.body, "TOPRIGHT", 0, 0)
  c.kind:SetJustifyH("RIGHT")
  c.title:SetPoint("RIGHT", c.kind, "LEFT", -6, 0)
  c.text = S.text(c.body, 11, S.C.text)
  c.text:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -3)
  c.text:SetPoint("RIGHT", c.body, "RIGHT", 0, 0)
  c.text:SetJustifyH("LEFT")
  c.text:SetWordWrap(false)
  c.buttons = {}
  for i = 1, Cards.BUTTONS do
    local b = S.action(c.body, { label = "", row = true, boxed = true })
    if i == 1 then
      b:SetPoint("BOTTOMLEFT", c.body, "BOTTOMLEFT", 0, 0)
    else
      b:SetPoint("LEFT", c.buttons[i - 1], "RIGHT", 4, 0)
    end
    b:SetScript("OnClick", function(self)
      if self.run and c.ask then
        self.run(c.ask)
      end
    end)
    b:Hide()
    c.buttons[i] = b
  end
  return c
end

-- A card shows a request: its words, its stripe (a Game Master's in the gold of the WoW palette
-- is not a token: the tier's, needs you), lit while fresh.
function Cards.Fill(c, ask, now)
  local rec = ask.last and store():Get(ask.last) or nil
  local title, kind, text = Cards.Words(ask, rec)
  c.ask = ask
  local p = ns.mod.db.profile
  c:SetCard({
    stripe = p.tierStripe ~= false and "tier0" or nil,
    flat = p.cardStyle == "flat" or nil,
    hot = now ~= nil and (now - (ask.t or 0)) < Cards.FRESH_SECS,
    onClick = ask.kind == "whisper" and function()
      Cards.Open(ask)
    end or nil,
    tip = ask.kind == "whisper" and L["Open the conversation"] or nil,
  })
  c.title:SetText(title)
  -- the name in its channel's colour (V25): a whisper's, a mention's channel, a raid warning's;
  -- a request of the game has no line and keeps the text's
  ns.Rows.InkLine(c.title, c, ask.kind ~= "away" and ask.kind ~= "digest" and rec or nil, "text")
  c.kind:SetText(kind)
  c.text:SetText(S.ReadableText(text, c)) -- readable on a light look (V25)
  local buttons = Cards.Buttons(ask, rec)
  for i, b in ipairs(c.buttons) do
    local spec = buttons[i]
    if spec then
      b.spec.label, b.spec.icon = spec.label, spec.icon
      -- the card's answer in the accent, the others as quiet chips (the artifact's cards)
      b.spec.primary = (i == 1 and spec.icon ~= "close") or nil
      b.run = spec.run
      b:Fit()
      b:Show()
    else
      b.run = nil
      b:Hide()
    end
  end
  return c
end
