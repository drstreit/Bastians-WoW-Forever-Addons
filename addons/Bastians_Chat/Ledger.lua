-- Bastian's Chat, the session's ledger (plan-chat-v3.md V16, V22; plan-chat-one-window.md §1.2, V31):
-- what the player looted and its worth, the items most looted, money, the quests done, experience
-- and reputation, at the head of the Mine place (the Switchboard's Needs-you column held it until
-- V31). The store sums it (Store:Gain). The worth counts what Gold prices; "at least" when some
-- item has no price, nothing when none has (golden rule 2). Every text is bounded by the panel:
-- the gains wrap on a line of their own (R5).
local _, ns = ...
local B = Bastians
local S = B.UI.Style
local L = ns.L

local Ledger = {}
ns.Ledger = Ledger

Ledger.TOP = 24 -- the first row under the title
Ledger.ROW = 18
Ledger.H = 84 -- a title and three rows
Ledger.PAD = 8

local function store()
  return ns.Chat.Store()
end

-- The ledger's frame on `parent`: a panel with its title, three rows and the gains' line.
function Ledger.Build(parent)
  local led = CreateFrame("Frame", nil, parent)
  led:SetHeight(Ledger.H)
  ns.Inbox.Panel(led)
  led.title = S.SetRole(S.text(led, 11, S.C.muted), "label")
  led.title:SetPoint("TOPLEFT", led, "TOPLEFT", Ledger.PAD, -7)
  led.title:SetText(L["This session, yours"])
  led.rows = {}
  for i = 1, 3 do
    local y = -(Ledger.TOP + (i - 1) * Ledger.ROW)
    local row = {
      left = S.text(led, 12, S.C.text),
      right = S.SetRole(S.text(led, 11, S.C.muted), "number"), -- the artifact's mono column
    }
    row.right:SetPoint("TOPRIGHT", led, "TOPRIGHT", -Ledger.PAD, y - 1)
    row.right:SetJustifyH("RIGHT")
    row.left:SetPoint("TOPLEFT", led, "TOPLEFT", Ledger.PAD, y)
    row.left:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
    row.left:SetJustifyH("LEFT")
    row.left:SetWordWrap(false)
    led.rows[i] = row
  end
  -- the quests, experience and reputation on a line of their own under the money, wrapping
  -- inside the panel
  led.gains = S.SetRole(S.text(led, 11, S.C.muted), "number")
  led.gains:SetPoint("TOPLEFT", led, "TOPLEFT", Ledger.PAD, -(Ledger.TOP + 3 * Ledger.ROW))
  led.gains:SetPoint("RIGHT", led, "RIGHT", -Ledger.PAD, 0)
  led.gains:SetJustifyH("LEFT")
  led.gains:SetWordWrap(true)
  led:Hide()
  return led
end

-- An item's link as the game wrote it, from the first of the player's lines that looted it.
local links = {}
local function itemLink(id)
  if links[id] == nil then
    links[id] = false
    for _, rec in ipairs(store():Query({ streams = { mine = true } })) do
      local g = rec.gain
      if g and g.kind == "item" and g.item == id then
        links[id] = ns.Rows.ItemLink(rec.body, id) or false
        break
      end
    end
  end
  return links[id] or nil
end

-- The ledger drawn from the store's sums: "5 items looted ... worth 1s 20c", the three most
-- looted, money, then the quests, experience and reputation. Its height follows its lines.
function Ledger.Draw(led)
  if not led then
    return
  end
  local sum = store().ledger
  local ids, count, worth, priced = {}, 0, 0, 0
  for id, n in pairs(sum.items) do
    ids[#ids + 1] = id
    count = count + n
  end
  table.sort(ids, function(a, b)
    if sum.items[a] ~= sum.items[b] then
      return sum.items[a] > sum.items[b]
    end
    return a < b
  end)
  for _, id in ipairs(ids) do
    local m = ns.Rows.MarketPrice(id)
    if m then
      worth, priced = worth + m * sum.items[id], priced + 1
    end
  end
  local rows = led.rows
  for _, row in ipairs(rows) do
    row.left:SetText("")
    row.right:SetText("")
  end
  led.gains:SetText("")
  led:SetHeight(Ledger.H)
  local quests = sum.quests or {}
  if count == 0 and sum.copper == 0 and sum.xp == 0 and not next(sum.rep) and #quests == 0 then
    rows[1].left:SetText(S.H.dim .. L["Nothing yet: your loot, money and experience add up here."] .. "|r")
    return
  end
  if count > 0 then
    rows[1].left:SetText(L["%d items looted"]:format(count))
    if priced > 0 then
      local money = B.UI.Money(math.floor(worth + 0.5))
      rows[1].right:SetText((priced == #ids and L["worth %s"] or L["worth at least %s"]):format(money))
    end
    local top = {}
    for i = 1, math.min(3, #ids) do
      top[i] = (itemLink(ids[i]) or ("#" .. ids[i])) .. " x" .. sum.items[ids[i]]
    end
    rows[2].left:SetText(S.ReadableText(table.concat(top, ", "), led)) -- links readable (V25)
  end
  if sum.copper > 0 then
    rows[3].left:SetText(L["Money %s"]:format(B.UI.Money(sum.copper)))
  end
  local gains = {}
  local look = ns.Rows.LookColors() -- experience and reputation in their colours (V25)
  local xp = look and ns.Rows.Code(led, "chanXp") or ""
  local rep = look and ns.Rows.Code(led, "chanRep") or ""
  if #quests > 0 then -- the quests done this session (V22)
    gains[#gains + 1] = L["%d quests done"]:format(#quests)
  end
  if sum.xp > 0 then
    gains[#gains + 1] = xp .. L["%d experience"]:format(sum.xp) .. (xp ~= "" and "|r" or "")
  end
  local factions = {}
  for faction in pairs(sum.rep) do
    factions[#factions + 1] = faction
  end
  table.sort(factions)
  for _, faction in ipairs(factions) do
    local n = sum.rep[faction]
    gains[#gains + 1] = rep
      .. ("%s %s%d"):format(faction, n >= 0 and "+" or "", n)
      .. (rep ~= "" and "|r" or "")
  end
  if #gains > 0 then
    led.gains:SetText(table.concat(gains, ", "))
    local h = math.ceil(led.gains:GetStringHeight() or Ledger.ROW)
    led:SetHeight(Ledger.TOP + 3 * Ledger.ROW + h + 6)
  end
end
