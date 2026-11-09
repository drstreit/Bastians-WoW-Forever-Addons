-- Bastian's Courtesy, the module (courtesy.md): the settings, the slash command, what comes over from
-- Bastian's Gestures once. `/bcourtesy` opens the settings page.
local ADDON, ns = ...
local B = Bastians
local L = ns.L

local Main = {}
ns.Main = Main

local MOODS = {
  { "polite", L["Polite"] },
  { "roleplay", L["Roleplay"] },
  { "snarky", L["Snarky"] },
  { "philosophic", L["Philosophic"] },
  { "cheerful", L["Cheerful"] },
  { "weary", L["Weary"] },
}

local OPTIONS = {
  { type = "header", label = L["Courtesy"] },
  {
    type = "select",
    key = "courtesy",
    label = L["When someone does something for you or to you"],
    values = {
      ask = L["Ask (the ring)"],
      auto = L["Automatic (a gesture at once; words need your click)"],
      off = L["Off"],
    },
  },
  { type = "toggle", key = "courtesyInstances", label = L["Also in dungeons and battlegrounds"] },
  { type = "header", label = L["The moods it may speak in"] },
}
for _, mood in ipairs(MOODS) do
  OPTIONS[#OPTIONS + 1] = { type = "toggle", key = "mood_" .. mood[1], label = mood[2] }
end
OPTIONS[#OPTIONS + 1] = { type = "header", label = L["My own lines"] }
OPTIONS[#OPTIONS + 1] = {
  type = "toggle",
  key = "myLines",
  label = L["Use my own lines (the addon Bastians_MyLines)"],
  desc = L["On: yours first, and ours where none of yours fits. Off: only the lines that come with the addon."], -- luacheck: ignore 631 (a locale key stays one literal)
}
OPTIONS[#OPTIONS + 1] = {
  type = "execute",
  key = "checkMyLines",
  label = L["Check my lines"],
  icon = "search",
  desc = L["Says in the chat how many of your lines can be used, and what is wrong with the others."],
  func = function()
    ns.Mine.Report()
  end,
}

local defaults = { courtesy = "ask", courtesyInstances = false, myLines = true }
for _, mood in ipairs(MOODS) do
  defaults["mood_" .. mood[1]] = true
end

local function shipped(list)
  local set = {}
  for _, key in ipairs(list) do
    set[L[key]] = true
  end
  return set
end

local SHIPPED_THANKS = { "Thank you, %t!", "Much obliged, %t.", "May the road be kind to you, %t." }

local function keep(kept, texts, skip, situations)
  for _, text in ipairs(type(texts) == "table" and texts or {}) do
    if type(text) == "string" and not skip[text] then
      for _, situation in ipairs(situations) do
        kept[#kept + 1] = { situation, "polite", text }
      end
    end
  end
end

-- Once per profile: the Courtesy settings of Bastian's Gestures, and the lines the player wrote there
-- (ADR 0064, the only place one addon reads another's saved variables).
function Main.Adopt(db)
  if db.profile.adopted then
    return
  end
  db.profile.adopted = true
  local old = rawget(_G, "BastiansGesturesDB")
  local profiles = type(old) == "table" and old.profiles
  local profile = type(profiles) == "table" and profiles[B:GetProfile()]
  if type(profile) ~= "table" then
    return
  end
  if profile.courtesy ~= nil then
    db.profile.courtesy = profile.courtesy
  end
  if profile.courtesyInstances ~= nil then
    db.profile.courtesyInstances = profile.courtesyInstances
  end
  local kept = {}
  keep(kept, profile.thanks, shipped(SHIPPED_THANKS), { "buff", "rez" })
  keep(kept, profile.declines, shipped({ ns.Courtesy.DECLINE }), { "duel.declined", "invite.declined" })
  if #kept > 0 then
    db.profile.keptLines = kept
  end
end

local handedOver = false -- the kept lines reach Core once a session

local mod = B:NewModule("Courtesy", {
  news = ns.NEWS, -- What's new (ADR 0021)
  addon = ADDON,
  icon = B.UI.IconTexture("app_courtesy"),
  open = function()
    B.UI.Hub.TogglePage("Courtesy")
  end,
  title = L["Courtesy"],
  apiVersion = 1,
  optional = { "Bastians_Gestures", "Bastians_Campfire", "Bastians_MyLines" },
  defaults = { profile = defaults, char = {}, global = {} },
  options = OPTIONS,
  OnEnable = function(self)
    Main.Adopt(self.db)
    if not handedOver and self.db.profile.keptLines then
      handedOver = true
      B:AddCourtesyLines(self.db.profile.keptLines)
    end
    ns.Courtesy.Attach(self)
  end,
  OnDisable = function()
    ns.Courtesy.Detach()
  end,
})
Main.mod = mod
mod.Courtesy = ns.Courtesy
mod.Model = ns.Model
mod.Voice = ns.Voice
mod.Mine = ns.Mine
mod.Try = ns.Try
mod.Facts = ns.Facts
mod.Medallion = ns.Medallion
mod.CourtesyLines = ns.CourtesyLines
mod.Compat = ns.Compat
mod.Main = Main

-- `/bcourtesy` opens the page; `/bcourtesy try ...`; `/bcourtesy mine`.
function Main.Slash(text)
  local cmd = string.match(text or "", "^%s*(%S*)")
  if cmd == "try" then
    return ns.Try.Run(string.match(text, "^%s*%S+%s*(.*)$"))
  elseif cmd == "mine" then
    return ns.Mine.Report()
  elseif cmd == "why" then
    return ns.Courtesy.Why()
  end
  B.UI.Hub.TogglePage("Courtesy")
  return true
end

SLASH_BASTIANSCOURTESY1 = "/bcourtesy"
SlashCmdList.BASTIANSCOURTESY = function(text)
  Main.Slash(text)
end
