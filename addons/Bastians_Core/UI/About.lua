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

About.URL = "bastians.dev/wow" -- the suite's address (ADR 0023)
About.SOURCE_URL = "github.com/drstreit/Bastians-WoW-Forever-Addons"
About.LICENCE = "GPL-3.0"

-- { name, licence, what it gives }: the bundled sources. The client first since ADR 0035 (owner,
-- 29.10.2026: "do a max ourselves"): what it holds comes from it; the others give what the server
-- holds (spawns, loot, vendors, trainers, quests) and the names the client does not carry.
About.SOURCES = {
  {
    "Blizzard client files",
    "Blizzard Entertainment",
    "items, their prices and levels, recipes with reagents and products, quest chains and quest "
      .. "areas, item names in every language, zones, taxi nodes, minimap tiles, map transforms and "
      .. "the overview textures of Bastian's Map Art, read from your own installed client",
  },
  { "Everything Quests", "MIT", "quests, their places and objective points (Forever)" },
  { "AllTheThings", "MIT", "quests, NPCs, objects, flight paths and the recipe list (retail)" },
  {
    "ItemDB / LibItemDB",
    "MIT",
    "where to get an item (retail); its places are re-expressed from the TrinityCore world "
      .. "database (GPL-2.0)",
  },
  {
    "QuestieDB",
    "GPL-3.0",
    "zone table and spawns; NPC names, quest titles and objectives in other languages (Forever)",
  },
  {
    "ForeverDB",
    "GPL-3.0, credit: Data from ForeverDB.net (https://foreverdb.net)",
    "vendors, trainers, gather nodes, the skill a recipe is taught at, the dungeons and raids with "
      .. "their bosses, loot and quests (Forever)",
  },
  {
    "CMaNGOS classic-db",
    "GPL-3.0",
    "quest rewards and texts (German and Chinese too), loot and trainers, labelled classic",
  },
  { "NauticusClassic", "MIT", "the loops and departures of the boats and zeppelins (Forever)" },
  {
    "TrinityCore TDB",
    "GPL-2.0 or later",
    "NPC services, levels and places, mailboxes and forges, the danger of the routes, and NPC, "
      .. "object and quest names in every language (retail)",
  },
  { "AHledger", "Prices from AHledger", "market prices through the AHSync export" },
  { "Spoken", "MIT", "the voice bridge of Bastian's Quests" },
  -- the Library's fonts (EB Garamond, IM FELL Types, Atkinson Hyperlegible, OpenDyslexic; SIL Open
  -- Font License 1.1) come back with the Library: it is private until it ships
  {
    "Google Gemini image model",
    "Gemini API terms",
    "the drawings of Bastian's book, made from our own scene descriptions (Bastian draws them in the story)",
  },
}

-- { name, licence }: what the build tools and Core link, never shipped as data
About.LIBRARIES = {
  { "TACTSharp, DBCD, BLPSharp (wowdev, Marlamin)", "MIT, build time only" },
  { "WoWDBDefs definitions (wowdev)", "CC BY-SA 4.0, build time only" },
  { "EasyOCR, LaMa, Real-ESRGAN, spandrel", "Apache-2.0, Apache-2.0, BSD-3-Clause, MIT; build time only" },
  { "LibStub", "public domain" },
  { "CallbackHandler-1.0, LibDataBroker-1.1", "see their files in Bastians_Core/Libs" },
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
  note(L["Licence: "] .. About.LICENCE .. ". " .. L["Website: "] .. About.URL)
  note(L["Source and issues: "] .. About.SOURCE_URL)
  local data = B:GetService("data")
  local meta = data and data.Meta and data:Meta()
  local downloads = meta and meta.downloads
  if downloads then -- the daily edition's counts; unknown says nothing
    note(
      string.format(
        L["Downloaded on CurseForge: the suite %d times, its data %d times (%s)."],
        downloads.suite,
        downloads.data,
        tostring(downloads.at or "?")
      )
    )
  end

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
  -- the client first (ADR 0035); the key is one sentence, the locale files carry it whole
  local sources = "Most of the data comes from your own game client; what only the game's servers "
    .. "know comes from these sources. Every value keeps its source label in the addons."
  note(L[sources])
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
