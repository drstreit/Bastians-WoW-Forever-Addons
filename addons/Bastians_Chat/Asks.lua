-- Bastian's Chat, the request bar (plan-chat-one-window.md §3.3, ADR 0076): one row over the input
-- line while a request is open, gone when none is. A chip per open request, the most important
-- first: an unanswered whisper ("Elowen waits (2)", a click shows her place), an invite, a duel, a
-- trade, a ready check, a summon, a resurrection, a raid warning, a mention (ten minutes), a
-- watch-list match, a kind deed of Courtesy, Away and the catch-up after a fight; each with its
-- buttons (Accept, Decline, Ready, Courtesy, Got it). What does not fit: "+3", a click lists them.
-- A right click: the chip's actions, Dismiss, Dismiss all. The store keeps the state.
local _, ns = ...
local B = Bastians
local S = B.UI.Style
local L = ns.L

local Asks = {}
ns.Asks = Asks

Asks.CHIP_H = 22
Asks.GAP = 6
Asks.MAX_CHIPS = 8 -- chip frames kept; the rest is behind "+N"
Asks.LABEL_MAX = 220 -- a chip's words at most this wide (one line, cut with "...")

local bar -- the bar's frame (the Inbox's box.asks)

local function store()
  return ns.Chat.Store()
end

-- The open requests the bar shows. With the decks a whisper is no chip: its person's chip on
-- Talk's strip carries the count (plan-chat-two-decks.md §11); a Game Master's stays.
local function openAsks(now)
  local all = store():OpenAsks(now)
  if ns.View.LayoutKind() ~= "decks" then
    return all
  end
  local out = {}
  for _, a in ipairs(all) do
    if a.kind ~= "whisper" or a.rel == "gm" then
      out[#out + 1] = a
    end
  end
  return out
end

-- What a chip says (pure but for the locale): "Elowen waits (2)", "Haskel invites you",
-- "Raid warning: Stack on me", "During the fight, 3 min".
function Asks.Text(ask, rec)
  local title, kind, text = ns.Cards.Words(ask, rec)
  if ask.refused then -- the client refused the call (probe X3): the game's window answers
    return title .. " " .. kind .. ". " .. text
  elseif ask.kind == "whisper" then
    local name = ask.rel == "gm" and (title .. " <" .. L["GM"] .. ">") or title
    local n = ask.unread or 0
    return n > 1 and L["%s waits (%d)"]:format(name, n) or L["%s waits"]:format(name)
  elseif ask.kind == "warning" then
    return title .. ": " .. ((text ~= "" and text) or kind or "")
  elseif ask.kind == "away" then
    return title
  elseif ask.kind == "digest" then
    return title .. ", " .. kind
  elseif ask.kind == "watch" then
    return title .. ": " .. kind
  end
  return title .. " " .. kind
end

-- The buttons a chip carries: the card's, without its Reply (the chip's own click) and its Dismiss
-- (the right click's); "Got it" stays.
function Asks.Buttons(ask, rec)
  local out = {}
  for _, b in ipairs(ns.Cards.Buttons(ask, rec)) do
    local reply = ask.kind == "whisper" and b.label == L["Reply"]
    local dismiss = b.label == L["Dismiss"]
    if not reply and not dismiss then
      out[#out + 1] = b
    end
  end
  return out
end

-- A chip's own click: a whisper shows its person; any other runs its first button.
function Asks.Open(ask, rec)
  if ask.kind == "whisper" then
    local key = ask.bn and ("bn:" .. tostring(ask.bn)) or ask.who
    if key and ns.People.Convo(key) then
      return ns.Front.ShowPerson(key, true)
    end
    return false
  end
  local first = Asks.Buttons(ask, rec)[1]
  if first and ask.kind == "mention" then
    first.run(ask)
    return true
  end
  return false
end

-- The right click on a chip: its actions, Dismiss, Dismiss all.
function Asks.Menu(ask, anchor)
  local rec = ask.last and store():Get(ask.last) or nil
  local items = {}
  if ask.kind == "whisper" then
    items[#items + 1] = {
      label = L["Open the conversation"],
      onClick = function()
        Asks.Open(ask, rec)
      end,
    }
  end
  for _, b in ipairs(Asks.Buttons(ask, rec)) do
    items[#items + 1] = {
      label = b.label,
      onClick = function()
        b.run(ask)
      end,
    }
  end
  items[#items + 1] = {
    label = L["Dismiss"],
    onClick = function()
      store():Dismiss(ask.id)
    end,
  }
  items[#items + 1] = {
    label = L["Dismiss all"],
    onClick = function()
      Asks.DismissAll()
    end,
  }
  B.UI.Menu(anchor, Asks.Text(ask, rec), items, ns.mod)
  return items
end

-- Every open request put away; the game's own requests (an invite, a ready check) stay: the game
-- ends them.
function Asks.DismissAll()
  for _, a in ipairs(openAsks(time())) do
    if not ns.Requests.KINDS[a.kind] then
      store():Dismiss(a.id)
    end
  end
end

local function chip(i)
  local c = bar.chips[i]
  if c then
    return c
  end
  c = CreateFrame("Button", nil, bar)
  c:SetHeight(Asks.CHIP_H)
  c.ground = S.roundFill(c, S.C.inset, "pill")
  c.edges = S.roundEdges(c, S.C.tier0, "pill")
  c.dot = CreateFrame("Frame", nil, c)
  c.dot:SetSize(7, 7)
  c.dot:SetPoint("LEFT", c, "LEFT", 9, 0)
  c.dot.fill = S.roundFill(c.dot, S.C.tier0, "pill")
  c.label = S.text(c, 12, S.C.text)
  c.label:SetPoint("LEFT", c.dot, "RIGHT", 6, 0)
  c.label:SetJustifyH("LEFT")
  c.label:SetWordWrap(false)
  c.buttons = {}
  c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  c:SetScript("OnClick", function(self, button)
    if not self.ask then
      return
    end
    if button == "RightButton" then
      Asks.Menu(self.ask, self)
    else
      Asks.Open(self.ask, self.rec)
    end
  end)
  c:SetScript("OnEnter", S.TipEnter)
  c:SetScript("OnLeave", S.TipLeave)
  bar.chips[i] = c
  return c
end

local function chipButton(c, i)
  local b = c.buttons[i]
  if b then
    return b
  end
  b = S.action(c, { label = "", row = true, boxed = true })
  b:SetScript("OnClick", function(self)
    if self.run and c.ask then
      self.run(c.ask)
    end
  end)
  c.buttons[i] = b
  return b
end

-- A chip shows a request: the dot and edge in the colour of needs you (a Game Master's in the
-- watch list's gold), its words, its buttons. Returns its width.
local function fill(c, ask, now)
  local rec = ask.last and store():Get(ask.last) or nil
  c.ask, c.rec = ask, rec
  local token = ask.rel == "gm" and S.C.tier3 or S.C.tier0
  S.tint(c.dot.fill, token)
  S.setEdges(c.edges, token)
  local text = Asks.Text(ask, rec)
  c.label:SetWidth(0)
  c.label:SetText(text)
  local w = c.label:GetStringWidth() or 0
  if w <= 0 then
    w = #text * 6
  end
  if w > Asks.LABEL_MAX then
    c.label:SetWidth(Asks.LABEL_MAX)
    w = Asks.LABEL_MAX
  end
  c.tip = text
  local x = 9 + 7 + 6 + w + 8
  local buttons = Asks.Buttons(ask, rec)
  for i, spec in ipairs(buttons) do
    local b = chipButton(c, i)
    b.spec.label, b.spec.icon = spec.label, nil
    b.spec.primary = (i == 1 and spec.icon ~= "close") or nil
    b.run = spec.run
    b:Fit()
    b:ClearAllPoints()
    b:SetPoint("LEFT", c, "LEFT", x, 0)
    b:Show()
    x = x + (b:GetWidth() or 50) + 3
  end
  for i = #buttons + 1, #c.buttons do
    c.buttons[i].run = nil
    c.buttons[i]:Hide()
  end
  local width = math.floor(x + 4)
  c:SetWidth(width)
  -- lit while fresh, as the card was
  c:SetAlpha((now - (ask.t or 0)) < ns.Cards.FRESH_SECS and 1 or 0.92)
  return width
end

-- The bar in the Inbox's box (built once).
function Asks.Build(box)
  if bar then
    return Asks.Adopt(box) -- the one bar, in the box of the layout in force
  end
  bar = CreateFrame("Frame", nil, box)
  bar:SetHeight(ns.Inbox.ASKS_H)
  bar.chips = {}
  bar.label = S.SetRole(S.text(bar, 11, S.C.tier0), "label")
  bar.label:SetPoint("LEFT", bar, "LEFT", 4, 0)
  bar.label:SetText(string.upper(L["Waiting"]))
  bar.more = S.action(bar, {
    label = "",
    row = true,
    boxed = true,
    onClick = function(self)
      Asks.MoreMenu(self)
    end,
  })
  bar.more:Hide()
  bar:Hide()
  box.asks = bar
  return bar
end

-- The bar into the box of the layout that shows (the decks, or the Inbox until V35).
function Asks.Adopt(box)
  if bar and box and bar:GetParent() ~= box then
    bar:SetParent(box)
  end
  if box then
    box.asks = bar
  end
  return bar
end

-- The requests behind "+N": each with its actions.
function Asks.MoreMenu(anchor)
  local items = {}
  for _, ask in ipairs(bar.rest or {}) do
    local rec = ask.last and store():Get(ask.last) or nil
    local text = Asks.Text(ask, rec)
    if ask.kind == "whisper" then
      items[#items + 1] = {
        label = text,
        onClick = function()
          Asks.Open(ask, rec)
        end,
      }
    else
      local buttons = Asks.Buttons(ask, rec)
      if #buttons == 0 then
        items[#items + 1] = {
          label = text .. ": " .. L["Dismiss"],
          onClick = function()
            store():Dismiss(ask.id)
          end,
        }
      end
      for _, b in ipairs(buttons) do
        items[#items + 1] = {
          label = text .. ": " .. b.label,
          onClick = function()
            b.run(ask)
          end,
        }
      end
    end
  end
  B.UI.Menu(anchor, L["Waiting"], items, ns.mod)
  return items
end

-- The bar drawn from the open requests: shown while one is, the chips that fit, "+N" for the rest.
local draw
function Asks.Draw()
  if not bar then
    return
  end
  return S.WithPalette(S.PaletteOf(bar), draw)
end

function draw()
  local now = time()
  local asks = openAsks(now)
  local was = bar:IsShown()
  bar:SetShown(#asks > 0)
  if was ~= (#asks > 0) then
    ns.Front.Layout()
  end
  local width = bar:GetWidth()
  if not width or width <= 0 then
    width = (bar:GetParent():GetWidth() or 0) - ns.Front.RAIL_W - 12
  end
  local x = 4 + (bar.label:GetStringWidth() or 50) + Asks.GAP
  local moreW = 40
  local shownN = 0
  bar.rest = {}
  local full = false -- once a chip does not fit, the rest is behind "+N" in their order
  for i, ask in ipairs(asks) do
    if not full and i <= Asks.MAX_CHIPS then
      local c = chip(i)
      local w = fill(c, ask, now)
      local last = i == #asks
      if shownN > 0 and x + w + (last and 0 or moreW) > width then
        full = true
      else
        c:ClearAllPoints()
        c:SetPoint("LEFT", bar, "LEFT", x, 0)
        c:Show()
        x = x + w + Asks.GAP
        shownN = shownN + 1
      end
    else
      full = true
    end
    if full then
      bar.rest[#bar.rest + 1] = ask
    end
  end
  for i = shownN + 1, #bar.chips do
    bar.chips[i]:Hide()
    bar.chips[i].ask = nil
  end
  if #bar.rest > 0 then
    bar.more:SetLabel("+" .. #bar.rest)
    bar.more:ClearAllPoints()
    bar.more:SetPoint("LEFT", bar, "LEFT", x, 0)
    bar.more:Show()
  else
    bar.more:Hide()
  end
  return shownN
end

-- The chips shown, for tests: their words in order.
function Asks.Shown()
  local out = {}
  for _, c in ipairs(bar and bar.chips or {}) do
    if c:IsShown() and c.ask then
      out[#out + 1] = c.label:GetText()
    end
  end
  return out
end

function Asks.Frame()
  return bar
end
