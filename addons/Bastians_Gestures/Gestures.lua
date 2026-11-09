-- Bastian's Gestures, the module (gestures.md): a ring of emotes, your own lines and the suite's
-- actions on one key. `/bgest` opens the editor.
local ADDON, ns = ...
local B = Bastians
local L = ns.L

local Gestures = {}
ns.Gestures = Gestures

local function ensure(db)
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
      myLines = true,
    },
    char = {},
    global = {},
  },
  options = OPTIONS,
  OnEnable = function(self)
    ensure(self.db)
    ns.Ring.Attach(self)
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
    ns.Editor.Close()
  end,
})
Gestures.mod = mod
mod.Gestures = Gestures
mod.Model = ns.Model
mod.Ring = ns.Ring
mod.Editor = ns.Editor
mod.Compat = ns.Compat

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
