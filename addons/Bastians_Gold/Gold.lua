-- Bastian's Gold: the module (gold.md). Capture (B6.1) lives in Capture.lua, the prices service and
-- market detection (B6.2) in Prices.lua, the Price and Sells sections with the tooltip lines (B6.3) in
-- Sections.lua, the Today list in Today.lua, farm spots and strategies in Spots.lua, the bag advisor
-- in Advisor.lua (S4) and the window in Window.lua (B6.4).
local ADDON, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
local L = ns.L

local mod = B:NewModule("Gold", {
  addon = ADDON,
  open = function()
    ns.Window.Toggle()
  end,
  title = L["Gold"],
  apiVersion = 1,
  data = { "items", "market" }, -- the Market pack loads with Gold (core-contracts §11)
  defaults = {
    profile = { scanMaxAgeHours = 24, minutes = 30, window = {}, tree = {}, view = "today" },
    global = {
      capture = { scans = {}, merchants = {}, trainers = {}, sellPrices = {}, log = {} },
      income = {}, -- per day: ah, loot, spent, chars (Income.lua, R9)
    },
  },
  options = {
    { type = "header", label = L["Today"] },
    {
      type = "range",
      key = "minutes",
      label = L["Play time available (minutes)"],
      min = 5,
      max = 240,
      step = 5,
    },
    {
      type = "toggle",
      key = "advisorAuto",
      label = L["Open the bag advisor at the auction house and at vendors"],
      default = true,
    },
    { type = "header", label = L["Prices"] },
    {
      type = "toggle",
      key = "tooltipSell",
      label = L["Vendor sell price in item tooltips"],
      default = true, -- a line the client knows, also without AH data
    },
    {
      type = "range",
      key = "scanMaxAgeHours",
      label = L["Hours an own scan counts as fresh"],
      min = 1,
      max = 72,
      step = 1,
    },
    {
      type = "note",
      text = function()
        return ns.Prices.Note()
      end,
    },
    { type = "header", label = L["Capture"] },
    {
      type = "note",
      text = function()
        local c = ns.Capture.Counts()
        return string.format(
          L["%d merchants (%d offers), %d trainers (%d services), sell prices for %d items."]
            .. " "
            .. L["/bgold for scans."],
          c.merchants,
          c.offers,
          c.trainers,
          c.services,
          c.sellPrices
        )
      end,
    },
  },
  OnEnable = function(self)
    ns.Capture.Register(self)
    ns.Income.Register(self) -- gold per day, AH apart from loot (R9)
    ns.Advisor.Register(self) -- the bag advisor (S4)
    ns.Prices.Register(self)
    ns.Sections.Register(self)
    ns.Spots.Register(self)
    ns.Window.Register(self)
  end,
  OnDisable = function()
    ns.Window.Hide()
  end,
})
ns.mod = mod
mod.Capture = ns.Capture
mod.Prices = ns.Prices
mod.Sections = ns.Sections
mod.Today = ns.Today
mod.Spots = ns.Spots
mod.Income = ns.Income -- gold per day (Income.lua, R9)
mod.Advisor = ns.Advisor -- the bag advisor (Advisor.lua, S4)
mod.Window = ns.Window

SLASH_BASTIANSGOLD1 = "/bgold"
SlashCmdList.BASTIANSGOLD = function(msg)
  if not mod:IsEnabled() then
    B:Say(L["Gold is disabled"])
    return
  end
  local cmd = string.lower(string.match(msg or "", "^%s*(%S*)") or "")
  if cmd == "" or cmd == "today" then
    ns.Window.Open("today")
  elseif cmd == "spots" then
    ns.Window.Open("spots", nil)
  elseif cmd == "bags" then
    ns.Window.Open("bags")
  elseif cmd == "item" then
    ns.Window.Open("price", tonumber(string.match(msg, "%d+")))
  else
    ns.Capture.Slash(msg)
  end
end
