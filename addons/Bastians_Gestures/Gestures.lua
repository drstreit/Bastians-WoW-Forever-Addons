-- Bastian's Gestures, the module (gestures.md): a ring of emotes, your own lines and the suite's
-- actions on one key; a ready thank-you when someone buffs you. `/bgest` opens the editor.
local ADDON, ns = ...
local B = Bastians
local L = ns.L

local Gestures = {}
ns.Gestures = Gestures

local function ensure(db)
  if type(rawget(db.profile, "thanks")) ~= "table" then
    rawset(db.profile, "thanks", ns.Model.DefaultThanks())
  end
  if type(rawget(db.profile, "declines")) ~= "table" then
    rawset(db.profile, "declines", ns.Model.DefaultDeclines())
  end
  if type(rawget(db.profile, "editor")) ~= "table" then
    rawset(db.profile, "editor", {})
  end
  ns.Model.Ensure(db.global)
end

local OPTIONS = {
  { type = "header", label = L["The ring"] },
  {
    type = "toggle",
    key = "toggle",
    label = L["The key opens and closes the ring (else: hold it, release on a wedge)"],
  },
  { type = "range", key = "scale", label = L["Size (%)"], min = 50, max = 200, step = 5 },
  {
    type = "execute",
    key = "edit",
    label = L["Edit the rings"],
    icon = "rename",
    desc = L["The three rings and their slots: gestures, your lines, the suite's actions."],
    func = function()
      ns.Editor.Open()
    end,
  },
  { type = "header", label = L["Courtesy"] },
  {
    type = "select",
    key = "courtesy",
    label = L["When someone buffs you, resurrects you or greets you"],
    values = { ask = L["Ask (a bubble)"], auto = L["Automatic (a random thank-you)"], off = L["Off"] },
  },
  { type = "toggle", key = "courtesyInstances", label = L["Also in dungeons and battlegrounds"] },
  {
    type = "edit",
    key = "newThanks",
    label = L["Add a thank-you line (press Enter; %t is who to thank)"],
    set = function(text, mod)
      text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
      if text ~= "" then
        local list = mod.db.profile.thanks
        list[#list + 1] = text
      end
    end,
  },
  {
    type = "edit",
    key = "newDecline",
    label = L["The polite decline of a duel, a trade or an invite (press Enter; %t is who asked)"],
    set = function(text, mod)
      text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
      if text ~= "" then
        mod.db.profile.declines = { text }
      end
    end,
  },
  {
    type = "execute",
    key = "clearThanks",
    label = L["Back to the three thank-you lines as shipped"],
    icon = "replay",
    func = function(mod)
      mod.db.profile.thanks = ns.Model.DefaultThanks()
    end,
  },
}

local mod = B:NewModule("Gestures", {
  news = ns.NEWS, -- What's new (ADR 0021)
  addon = ADDON,
  icon = B.UI.IconTexture("other"),
  open = function()
    B.UI.Hub.TogglePage("Gestures")
  end,
  title = L["Gestures"],
  apiVersion = 1,
  optional = {
    "Bastians_Data",
    "Bastians_Voice",
    "Bastians_Map",
    "Bastians_Route",
    "Bastians_Notes",
    "Bastians_Quests",
  },
  defaults = {
    profile = {
      toggle = false,
      scale = 100,
      courtesy = "ask",
      courtesyInstances = false,
    },
    char = {},
    global = {},
  },
  options = OPTIONS,
  OnEnable = function(self)
    ensure(self.db)
    ns.Ring.Attach(self)
    ns.Courtesy.Attach(self)
    ns.Feed.Register(self)
    self:On("BASTIANS_SUITE_HIDDEN", function(_, _, hidden)
      -- the clear-screen key, only while the page "Hidden by the key" ticks Gestures
      local Screen = B.UI.Screen
      if hidden and Screen and Screen.Hides and not Screen.Hides("Gestures") then
        return
      end
      ns.Ring.HideByKey(hidden == true)
    end)
  end,
  OnDisable = function()
    ns.Ring.Detach()
    ns.Courtesy.Detach()
    ns.Editor.Close()
  end,
})
Gestures.mod = mod
mod.Gestures = Gestures
mod.Model = ns.Model
mod.Ring = ns.Ring
mod.Courtesy = ns.Courtesy
mod.Editor = ns.Editor

-- the ring in front, or its slots, changed (the feed)
B:DeclareMessage("BASTIANS_GESTURES_CHANGED")
-- an emote, a line or a command of the ring went out: its kind (the welcome's first five minutes)
B:DeclareMessage("BASTIANS_GESTURE_FIRED")

-- `/bgest` opens the editor; `/bgest ring` opens the ring at the cursor; `/bgest next` cycles.
function Gestures.Slash(text)
  local cmd = string.match(text or "", "^%s*(%S*)")
  if cmd == "ring" then
    return ns.Ring.Open()
  elseif cmd == "next" then
    ns.Ring.Cycle(1)
    return true
  elseif cmd == "thanks" then
    for i, line in ipairs(mod.db.profile.thanks or {}) do
      B:Say("%d. %s", i, line)
    end
    return true
  end
  return ns.Editor.Open()
end

SLASH_BASTIANSGESTURES1 = "/bgest"
SlashCmdList.BASTIANSGESTURES = function(text)
  Gestures.Slash(text)
end

-- Key bindings (Bindings.xml reads these globals); the header is the addon's own.
BINDING_HEADER_BASTIANS_GESTURES = "Bastian's Gestures"
BINDING_NAME_BASTIANS_GESTURES_RING = L["Gestures: the ring (hold, release on a wedge)"]
BINDING_NAME_BASTIANS_GESTURES_NEXT = L["Gestures: the next ring"]
