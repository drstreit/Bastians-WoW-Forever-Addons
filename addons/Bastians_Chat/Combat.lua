-- Bastian's Chat version 3, the fight (plan-chat-v3.md §6.2, V11; "they pop up
-- middle of screen and slide to counter collector window"): while the player fights, a request that
-- matters (a raid warning, a ready check, a Game Master, a friend's whisper) pops up as a card in
-- the middle of the upper screen for a few seconds, then slides into the collector, a small window
-- that counts what waits; the layouts draw only the group's lines and hold the rest until the fight
-- is over. Our own frames only, never a protected one (golden rule 6).
local _, ns = ...
local B = Bastians
local S = B.UI.Style
local L = ns.L

local Combat = {}
ns.Combat = Combat

Combat.TOAST_SECS = 3 -- a popped card stays this long
Combat.SLIDE_SECS = 0.35 -- then slides into the collector
Combat.TOAST_Y = -140 -- from the screen's top
Combat.POP = { warning = true, ready = true } -- the kinds that pop; and Game Masters, friends' whispers
Combat.PASS = { group = true } -- the streams the layouts keep drawing in a fight
Combat.CATCHUP_SECS = 60 -- a fight this long brings a catch-up card (V20)

local fighting = false
local hidden = false -- the clear-screen key hides the chat: the toasts are the chat (V20)
local held = {} -- [ask id] = ask: what waits in the collector
local heldLines = 0
local toast, collector
local began, fromSeq -- the fight's start and the store's last record then (V20)

local function store()
  return ns.Chat.Store()
end

function Combat.Fighting()
  return fighting
end

-- Does a request pop up in a fight? While the chat is hidden, every one that needs the player
-- (V20; not a watch match or a kind deed).
function Combat.Pops(ask)
  if Combat.POP[ask.kind] or ask.rel == "gm" then
    return true
  end
  if hidden and not fighting then
    return ns.Store.Rank(ask) >= 1
  end
  return ask.kind == "whisper" and (ask.rel == "friend" or ask.rel == "bnet")
end

-- Does a layout draw this record in a fight (the group's lines only)?
function Combat.Draws(rec)
  return not fighting or Combat.PASS[rec.stream] == true
end

local function settings()
  return ns.mod.db.profile
end

-- Can the player drag the collector (V20)?
function Combat.CanDrag()
  return settings().collectorLocked ~= true
end

-- The collector where the player put it (UIParent's coordinates of its centre), kept.
function Combat.MoveCollector(x, y)
  settings().collector = { x = math.floor(x + 0.5), y = math.floor(y + 0.5) }
  if collector then
    collector:ClearAllPoints()
    collector:SetPoint("CENTER", UIParent, "BOTTOMLEFT", settings().collector.x, settings().collector.y)
  end
end

-- `/bchat collector`: back on the chat window's edge.
function Combat.ResetCollector()
  settings().collector = nil
  if collector and collector:IsShown() then
    Combat.DrawCollector()
  end
end

local function buildCollector()
  collector = CreateFrame("Button", nil, UIParent)
  collector:SetFrameStrata("HIGH")
  collector:SetMovable(true)
  collector:RegisterForDrag("LeftButton")
  collector:SetScript("OnDragStart", function(self)
    if Combat.CanDrag() then
      self:StartMoving()
    end
  end)
  collector:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local x, y = self:GetCenter()
    if x and y then
      Combat.MoveCollector(x, y)
    end
  end)
  collector:SetSize(220, 26)
  collector.face = S.fill(collector, S.C.panel, "BACKGROUND")
  collector.text = S.text(collector, 11, S.C.text)
  collector.text:SetPoint("LEFT", collector, "LEFT", 8, 0)
  collector.text:SetPoint("RIGHT", collector, "RIGHT", -6, 0)
  collector.text:SetJustifyH("LEFT")
  collector.stripe = S.fill(collector, S.C.tier0, "BORDER")
  collector.stripe:ClearAllPoints()
  collector.stripe:SetPoint("TOPLEFT", 0, 0)
  collector.stripe:SetPoint("BOTTOMLEFT", 0, 0)
  collector.stripe:SetWidth(3)
  S.SetFramePreset(collector, ns.View.LookValues("toastLook")) -- the pop-ups' look (V13)
  collector:Hide()
end

-- The collector's place: on the top edge of the chat window when it shows, else at the screen's top.
local function placeCollector()
  collector:ClearAllPoints()
  local at = settings().collector -- where the player dragged it (V20)
  if type(at) == "table" and type(at.x) == "number" and type(at.y) == "number" then
    collector:SetPoint("CENTER", UIParent, "BOTTOMLEFT", at.x, at.y)
    return
  end
  local W = ns.View.Window(ns.View.MAIN)
  local frame = W and W.win and W.win.frame
  if frame and frame:IsShown() then
    collector:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 4)
  else
    collector:SetPoint("TOP", UIParent, "TOP", 0, -40)
  end
end

function Combat.DrawCollector()
  if not collector then
    buildCollector()
  end
  local n = 0
  for _, ask in pairs(held) do
    if ask.state == "open" then
      n = n + 1
    end
  end
  if not (fighting or hidden) or (n == 0 and heldLines == 0) then
    collector:Hide()
    return
  end
  placeCollector()
  if fighting then
    collector.text:SetText(L["In a fight: %d requests and %d lines wait"]:format(n, heldLines))
  else
    collector.text:SetText(L["While hidden: %d requests wait"]:format(n))
  end
  collector:Show()
end

local function buildToast()
  toast = ns.Cards.Make(UIParent)
  toast:SetFrameStrata("HIGH")
  S.SetFramePreset(toast, ns.View.LookValues("toastLook")) -- Glass by default (plan §9, V13)
  toast:Hide()
end

-- The pop-ups' look changed (V13): the toast and the collector take it.
function Combat.ApplyLook()
  local values = ns.View.LookValues("toastLook")
  for _, f in ipairs({ toast or false, collector or false }) do
    if f then
      S.SetFramePreset(f, values)
    end
  end
end

function Combat.ToastFrame()
  return toast
end

-- The card slides from the middle of the screen to the collector and goes.
local function slide()
  if not toast or not toast:IsShown() then
    return
  end
  local fx, fy = toast:GetCenter()
  local tx, ty
  if collector and collector:IsShown() then
    tx, ty = collector:GetCenter()
  end
  if not (fx and fy and tx and ty) then
    toast:Hide()
    return
  end
  local start = GetTime()
  toast:SetScript("OnUpdate", function(self)
    local k = math.min(1, (GetTime() - start) / Combat.SLIDE_SECS)
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", fx + (tx - fx) * k, fy + (ty - fy) * k)
    self:SetAlpha(1 - 0.7 * k)
    if k >= 1 then
      self:SetScript("OnUpdate", nil)
      self:Hide()
      self:SetAlpha(1)
    end
  end)
end

function Combat.Toast(ask)
  if not toast then
    buildToast()
  end
  toast:SetScript("OnUpdate", nil)
  toast:SetAlpha(1)
  toast:ClearAllPoints()
  toast:SetPoint("TOP", UIParent, "TOP", 0, Combat.TOAST_Y)
  ns.Cards.Fill(toast, ask, time())
  toast:Show()
  toast.ask = ask
  C_Timer.After(Combat.TOAST_SECS, function()
    if toast.ask == ask then
      slide()
    end
  end)
end

function Combat.Toasting()
  return toast ~= nil and toast:IsShown() and toast.ask or nil
end

-- The store's news in a fight: a new request into the collector (and up as a toast when it
-- matters), a held line counted.
function Combat.OnStore(what, value)
  if not (fighting or hidden) then
    return
  end
  if what == "ask" and value.state == "open" and not held[value.id] then
    held[value.id] = value
    if Combat.Pops(value) then
      Combat.Toast(value)
    end
    Combat.DrawCollector()
  elseif what == "add" and fighting and not Combat.Draws(value) and not value.ask then -- an ask counts once
    heldLines = heldLines + 1
    Combat.DrawCollector()
  end
end

function Combat.Start()
  if ns.View.LayoutKind() == "decks" then
    return -- the decks hold nothing in a fight (plan-chat-two-decks.md §7, I2)
  end
  fighting = true
  held, heldLines = {}, 0
  began, fromSeq = time(), store().seq
end

-- The clear-screen key hid the chat (true) or showed it again (false): while hidden the toasts
-- are the chat (V20).
function Combat.SetHidden(on)
  hidden = on == true
  if not hidden and not fighting then
    held = {}
    if collector then
      collector:Hide()
    end
  end
end

-- The fight is over: the collector goes and the layout draws what waited.
function Combat.Stop()
  fighting = false
  held, heldLines = {}, 0
  if collector then
    collector:Hide()
  end
  if toast then
    toast:SetScript("OnUpdate", nil)
    toast:Hide()
  end
  ns.View.AfterFight()
  -- a long fight: what came, as a card (V20)
  if began and time() - began >= Combat.CATCHUP_SECS then
    ns.Away.CatchUp("fight", fromSeq, began)
  end
  began, fromSeq = nil, nil
end

function Combat.Collector()
  return collector
end

-- The store's listener, once (Chat's own fight handlers call Start and Stop: a module's second
-- registration of an event would replace its first).
local attached = false
function Combat.Attach()
  if not attached then
    attached = true
    store():On(Combat.OnStore)
  end
end
