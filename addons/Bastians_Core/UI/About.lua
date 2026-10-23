-- The About page of the hub (core.md "About page"): suite and API version, client and build, the
-- installed Bastians addons with their versions, the loaded data packs with build and client, and the
-- credits CLAUDE.md §8 asks for: every bundled source with its licence, plus the build-time libraries.
-- About.Lines() is pure (a list of { kind, text }); About.Render draws it with the kit's widgets.
-- The lists mirror docs/data/sources.md; a test checks that every name here appears there.
local _, ns = ...
local B = ns.B
local L = ns.L
local W = B.UI.Widgets

local About = {}
B.UI.About = About

About.URL = "github.com/drstreit/Bastians-WoW-Forever-Addons"
About.LICENCE = "GPL-3.0"

-- { name, licence, what it gives }: the bundled sources, in the order of sources.md
About.SOURCES = {
  { "Everything Quests", "MIT", "quests, their places and objective points (Forever)" },
  { "AllTheThings", "MIT", "quests, NPCs, objects and flight paths (retail)" },
  {
    "ItemDB / LibItemDB",
    "MIT",
    "item names and where to get them (retail); its places are re-expressed from the TrinityCore "
      .. "world database (GPL-2.0)",
  },
  { "QuestieDB", "GPL-3.0", "zone table and spawns (Forever)" },
  { "ForeverDB", "GPL-3.0", "vendors, trainers, recipes and gather nodes (Forever)" },
  { "CMaNGOS classic-db", "GPL-3.0", "quest rewards and texts, loot and trainers, labelled classic" },
  { "AHledger", "Prices from AHledger", "market prices through the AHSync export" },
  { "Spoken", "MIT", "the voice bridge of Bastian's Quests" },
  {
    "Blizzard client files",
    "Blizzard Entertainment",
    "minimap tiles, map transforms, taxi nodes and the overview textures of Bastian's Map Art, "
      .. "read from your own installed client",
  },
}

-- { name, licence }: what the build tools and Core link, never shipped as data
About.LIBRARIES = {
  { "TACTSharp, DBCD, BLPSharp (wowdev, Marlamin)", "MIT, build time only" },
  { "WoWDBDefs definitions (wowdev)", "CC BY-SA 4.0, build time only" },
  { "LibStub", "public domain" },
  { "CallbackHandler-1.0, LibDataBroker-1.1, LibDeflate", "see their files in Bastians_Core/Libs" },
}

local function addonVersion(addon)
  local version = C_AddOns.GetAddOnMetadata(addon, "Version")
  return version and tostring(version) or "?"
end

local function moduleState(mod)
  if mod.state == "enabled" then
    return L["on"]
  end
  return L["off"]
end

-- The page as a list of { kind = "header" | "note", text }.
function About.Lines()
  local lines = {}
  local function header(text)
    lines[#lines + 1] = { kind = "header", text = text }
  end
  local function note(text)
    lines[#lines + 1] = { kind = "note", text = text }
  end

  header(L["Bastian's WoW Forever addons"] .. " " .. B.VERSION)
  note(
    string.format(
      L["Core API %d. Client: %s, game build %s (interface %s)."],
      B.API_VERSION,
      tostring(B.Client),
      tostring(B.Build),
      tostring(B.Interface)
    )
  )
  note(L["Licence: "] .. About.LICENCE .. ". " .. L["Source and issues: "] .. About.URL)

  header(L["Addons"])
  local addons = {}
  for addon in pairs(ns.byAddon) do
    addons[#addons + 1] = addon
  end
  for addon in pairs(B.UI.Settings.LodApps()) do
    if not ns.byAddon[addon] then
      addons[#addons + 1] = addon
    end
  end
  table.sort(addons)
  for _, addon in ipairs(addons) do
    local mods = ns.byAddon[addon]
    local info = B.Compat.GetAddOnInfo(addon)
    local title = info and info.title or addon
    local state
    if mods then
      local parts = {}
      for _, mod in ipairs(mods) do
        if not mod.parent then
          parts[#parts + 1] = moduleState(mod)
        end
      end
      state = table.concat(parts, ", ")
    else
      state = B.UI.Settings.IsLodOn(addon) and L["loads at login"] or L["not loaded"]
    end
    note(string.format("%s %s (%s)", title, addonVersion(addon), state))
  end

  header(L["Data packs"])
  local data = B:GetService("data")
  local meta = data and data.Meta and data:Meta()
  if not meta or not next(meta.packs) then
    note(L["No data packs are loaded."])
  else
    local names = {}
    for name in pairs(meta.packs) do
      names[#names + 1] = name
    end
    table.sort(names)
    for _, name in ipairs(names) do
      local pack = meta.packs[name]
      local text = string.format("%s: %s %s", name, L["build"], tostring(pack.build or "?"))
      if meta.foreign[name] then
        text = text .. " " .. string.format(L["(built for %s, not this client)"], meta.foreign[name])
      end
      note(text)
    end
  end

  header(L["Credits"])
  note(L["Data and ideas from these sources; every value keeps its source label in the addons."])
  for _, source in ipairs(About.SOURCES) do
    note(string.format("%s (%s): %s", source[1], source[2], source[3]))
  end
  header(L["Libraries and build tools"])
  for _, lib in ipairs(About.LIBRARIES) do
    note(string.format("%s: %s", lib[1], lib[2]))
  end
  return lines
end

-- Draws the page into the hub canvas (the same widget list protocol as the settings renderer).
function About.Render(canvas)
  for _, w in ipairs(canvas.widgets or {}) do
    w:Hide()
  end
  local width = (canvas:GetWidth() or 400) - 24
  local widgets = {}
  local y = -10
  for _, line in ipairs(About.Lines()) do
    local w
    if line.kind == "header" then
      w = W.Header(canvas, line.text)
      if #widgets > 0 then
        y = y - 8
      end
    else
      w = W.Note(canvas, line.text)
    end
    w:SetPoint("TOPLEFT", canvas, "TOPLEFT", 12, y)
    w:SetWidth(width)
    w.text = line.text
    widgets[#widgets + 1] = w
    y = y - (w:GetHeight() or 16) - 2
  end
  canvas.widgets = widgets
  canvas.mod = nil
  canvas.contentHeight = -y + 10
  if canvas.onRendered then
    canvas.onRendered(canvas.contentHeight)
  end
end
