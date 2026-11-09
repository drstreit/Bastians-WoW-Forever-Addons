-- Bastian's Helpers, the module (helpers.md): the switches, the lists as item actions and an item
-- page section, the record of this character for the mail's Send to, `/bhelp`.
local ADDON, ns = ...
local B = Bastians
local L = ns.L
local Helpers = ns.Helpers

local mod

-- The saved tables the helpers write into (defaults come by metatable: a table of the defaults
-- would be written into and never saved).
local function ensure(db)
  local tables = {
    { db.global, "characters" },
    { db.global, "neverSell" },
    { db.global, "mailRules" },
    { db.char, "restock" },
    { db.char, "recent" },
    { db.profile, "window" },
  }
  for _, at in ipairs(tables) do
    if type(rawget(at[1], at[2])) ~= "table" then
      rawset(at[1], at[2], {})
    end
  end
end

-- `level`: PLAYER_LEVEL_UP's own, the client may still answer the old one. A zone the client does
-- not know yet (right after the loading screen) keeps the last one.
function Helpers.RecordMe(_, _, level)
  local facts = B.Compat.GetPlayerFacts()
  local characters, key = Helpers.Global().characters, Helpers.Key()
  local zone = B.Compat.Plain(GetZoneText())
  local before = characters[key]
  characters[key] = {
    name = (UnitName("player")),
    full = B.Compat.FullName("player"), -- what a mail needs (Forever: with the surname)
    realm = GetRealmName(),
    faction = facts.faction,
    class = facts.class,
    className = B.Compat.Plain(facts.className),
    level = tonumber(level) or B.Compat.Plain(facts.level),
    zone = zone ~= "" and zone or (before and before.zone) or nil,
  }
end

local function itemOf(ref)
  local typ, id = B.Entity.Parse(ref)
  return typ == "item" and type(id) == "number" and id or nil
end

local function sectionRows(ref)
  local id = itemOf(ref)
  if not (id and mod) then
    return nil
  end
  local rows = {}
  if Helpers.IsNeverSell(id) then
    rows[#rows + 1] = { text = L["Never sold to a vendor"] }
  end
  local amount = Helpers.Restock(id)
  if amount then
    rows[#rows + 1] = { text = L["Restocked at vendors to"], value = amount, valueKind = "number" }
  end
  return #rows > 0 and rows or nil
end

local function changed()
  B:Fire("BASTIANS_HELPERS_CHANGED")
end

local function register(self)
  local function action(def)
    def.types = { "item" }
    B:RegisterAction(self, def)
  end
  action({
    id = "helpers.neversell",
    label = L["Never sell to a vendor"],
    order = 60,
    when = function(ref)
      local id = itemOf(ref)
      return id ~= nil and not Helpers.IsNeverSell(id)
    end,
    run = function(ref)
      Helpers.NeverSell(itemOf(ref), true)
      changed()
    end,
  })
  action({
    id = "helpers.allowsell",
    label = L["Allow selling again"],
    order = 60,
    when = function(ref)
      local id = itemOf(ref)
      return id ~= nil and Helpers.IsNeverSell(id)
    end,
    run = function(ref)
      Helpers.NeverSell(itemOf(ref), false)
      changed()
    end,
  })
  action({
    id = "helpers.restock",
    label = L["Restock at vendors"],
    order = 61,
    when = function(ref)
      local id = itemOf(ref)
      return id ~= nil and Helpers.Restock(id) == nil
    end,
    run = function(ref)
      local id = itemOf(ref)
      local amount = Helpers.SetRestock(id)
      Helpers.Notice(string.format(L["%s: restocked to %d at vendors"], Helpers.ItemName(id), amount))
      changed()
    end,
  })
  action({
    id = "helpers.unrestock",
    label = L["Stop restocking"],
    order = 61,
    when = function(ref)
      local id = itemOf(ref)
      return id ~= nil and Helpers.Restock(id) ~= nil
    end,
    run = function(ref)
      Helpers.SetRestock(itemOf(ref), 0)
      changed()
    end,
  })
  B:RegisterDetailSection(self, {
    id = "helpers.item",
    chapter = "yours", -- on the sheet (ADR 0054)
    title = L["Helpers"],
    types = { "item" },
    order = 90,
    cache = false, -- a click on the actions changes it at once
    build = sectionRows,
  })
end

-- one edit row per mail rule kind (#18), set on Enter, an empty name removes the rule
local function mailRuleRows()
  local rows = {}
  for _, kind in ipairs(Helpers.MAIL_KINDS) do
    rows[#rows + 1] = {
      type = "edit",
      label = string.format(L["%s go to (a name, Enter; empty removes the rule)"], L[kind.label]),
      set = function(text)
        local to = Helpers.SetMailRule(kind.id, text)
        Helpers.Notice(
          to and string.format(L["%s go to %s"], L[kind.label], to)
            or string.format(L["%s: no mail rule"], L[kind.label])
        )
        changed()
      end,
    }
  end
  return rows
end

local OPTIONS = {
  { type = "header", label = L["Merchant"] },
  { type = "toggle", key = "sellJunk", label = L["Sell grey items (Undo in the notice)"] },
  { type = "toggle", key = "repair", label = L["Repair everything"] },
  { type = "toggle", key = "guildRepair", label = L["Repair from the guild bank when it may pay"] },
  { type = "toggle", key = "restock", label = L["Restock the items on your restock list"] },
  { type = "toggle", key = "altStack", label = L["Alt-click on a merchant item buys a full stack"] },
  { type = "header", label = L["Mail"] },
  { type = "toggle", key = "takeAll", label = L["Take all button on the mailbox"] },
  { type = "toggle", key = "sendTo", label = L["Your characters and recent recipients beside the mail"] },
  { type = "toggle", key = "lastRecipient", label = L["Start the send tab with the last recipient"] },
  { type = "header", label = L["Mail rules"] },
  {
    type = "note",
    text = function()
      return Helpers.MailRulesText()
        or L["No rules yet: name a character below, for example your alchemist for herbs."]
    end,
  },
  { type = "header", label = L["Quests"] },
  { type = "toggle", key = "autoQuest", label = L["Accept and hand in quests automatically"] },
  { type = "toggle", key = "skipGossip", label = L["Skip the gossip of NPCs with one option"] },
  { type = "toggle", key = "shareQuests", label = L["Share accepted quests with your group"] },
  { type = "header", label = L["Tooltips"] },
  { type = "toggle", key = "tooltipIDs", label = L["Item and NPC IDs"] },
  { type = "toggle", key = "tooltipItemLevel", label = L["Item level"] },
  { type = "header", label = L["Warnings"] },
  { type = "toggle", key = "warnDurability", label = L["Warn when your gear is almost broken"] },
  { type = "toggle", key = "warnBags", label = L["Warn when your bags are almost full"] },
  {
    type = "toggle",
    key = "warnRares",
    label = L["Warn when a rare creature is targeted or under the mouse"],
  },
  {
    type = "select",
    key = "pauseKey",
    label = L["Hold to pause the helpers"],
    values = { shift = L["Shift"], ctrl = L["Ctrl"], alt = L["Alt"] },
  },
}
do -- the rule rows go right after the rules' note
  local at
  for i, option in ipairs(OPTIONS) do
    if option.type == "header" and option.label == L["Mail rules"] then
      at = i + 2
    end
  end
  for n, row in ipairs(mailRuleRows()) do
    table.insert(OPTIONS, at + n - 1, row)
  end
end

mod = B:NewModule("Helpers", {
  news = ns.NEWS, -- What's new (ADR 0021)
  addon = ADDON,
  open = function()
    ns.Info.Open()
  end,
  title = L["Helpers"],
  data = { "world" }, -- the rare alert reads the creature's record (A3.3); optional like Data itself
  apiVersion = 1,
  optional = { "Bastians_Data", "Bastians_Browser" },
  defaults = {
    profile = {
      sellJunk = true,
      repair = true,
      guildRepair = false,
      restock = true,
      altStack = true,
      takeAll = true,
      sendTo = true,
      lastRecipient = true,
      autoQuest = false, -- off by default
      skipGossip = false, -- off by default
      shareQuests = true,
      tooltipIDs = true,
      tooltipItemLevel = true,
      warnDurability = true,
      warnBags = true,
      warnRares = true, -- catalog review A3.3 (07.11.2026)
      pauseKey = "shift",
    },
    char = {},
    global = {},
  },
  options = OPTIONS,
  OnEnable = function(self)
    ensure(self.db)
    register(self)
    -- the never-sell service (core-contracts section 11, ADR 0058 PH6): Gold's Bags keep what is on the list
    B:ProvideService(self, "neversell", {
      Is = function(_, itemID)
        return Helpers.IsNeverSell(itemID)
      end,
    }, { priority = 100 })
    ns.Feed.Register(self)
    ns.Merchant.Attach(self)
    ns.Mail.Attach(self)
    ns.Quests.Attach(self)
    ns.Tooltips.Attach(self)
    ns.Info.Attach(self)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", Helpers.RecordMe)
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", Helpers.RecordMe)
    self:On("BASTIANS_CHARACTER_FORGOTTEN", function(_, _, key) -- Alts: deleted in the game
      Helpers.Global().characters[key] = nil
    end)
    self:RegisterEvent("PLAYER_LEVEL_UP", Helpers.RecordMe)
    if IsLoggedIn and IsLoggedIn() then
      Helpers.RecordMe()
    end
  end,
})
Helpers.mod = mod
mod.Helpers = Helpers

-- a list of the helpers changed (an item's page shows it)
B:DeclareMessage("BASTIANS_HELPERS_CHANGED")

-- `/bhelp` the session panel; `/bhelp restock <itemID> <amount>` sets an amount (0 removes it).
function Helpers.Slash(text)
  local cmd, id, amount = string.match(text or "", "^%s*(%S*)%s*(%d*)%s*(%-?%d*)")
  if cmd == "restock" and tonumber(id) then
    local n = Helpers.SetRestock(tonumber(id), tonumber(amount) or nil)
    local name = Helpers.ItemName(tonumber(id))
    Helpers.Notice(
      n and string.format(L["%s: restocked to %d at vendors"], name, n)
        or string.format(L["%s: no longer restocked"], name)
    )
    changed()
    return n
  end
  return ns.Info.Open()
end

SLASH_BASTIANSHELPERS1 = "/bhelp"
SlashCmdList.BASTIANSHELPERS = function(text)
  Helpers.Slash(text)
end
