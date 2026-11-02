-- Settings (core-contracts §8): Core's own module ("General"), the schema renderer, the Blizzard panel
-- categories, load-on-demand switches (§2) and the profiles page (§9).
local _, ns = ...
local B = ns.B
local L = ns.L
local S = ns.Style
local Wd = B.UI.Widgets

local Settings_ = {}
B.UI.Settings = Settings_

local FONTS = {
  ["Fonts\\ARIALN.TTF"] = "Arial Narrow",
  ["Fonts\\FRIZQT__.TTF"] = "Friz Quadrata",
  ["Fonts\\MORPHEUS.TTF"] = "Morpheus",
  ["Fonts\\SKURRI.TTF"] = "Skurri",
}
local GAP = 6

-- Readable names of the client's fonts by file name; anything else shows its file name.
local FONT_NAMES = {
  FRIZQT__ = "Friz Quadrata",
  FRIZQT___CYR = "Friz Quadrata (Cyrillic)",
  ARIALN = "Arial Narrow",
  MORPHEUS = "Morpheus",
  MORPHEUS_CYR = "Morpheus (Cyrillic)",
  SKURRI = "Skurri",
  SKURRI_CYR = "Skurri (Cyrillic)",
  ["2002"] = "2002",
  ["2002B"] = "2002 Bold",
  NIM_____ = "Nimrod",
  K_PAGETEXT = "Pagetext",
  K_DAMAGE = "Damage",
}

local function fontLabel(path)
  local file = string.match(path, "([^\\/]+)%.[%a%d]+$") or path
  return FONT_NAMES[string.upper(file)] or file
end

-- Every font to choose from: the
-- four above, every file the client's font objects use, and the fonts other addons register with
-- LibSharedMedia when it is loaded. { [path] = name }.
function Settings_.FontChoices()
  local out = {}
  for path, name in pairs(FONTS) do
    out[path] = name
  end
  for _, f in ipairs(S.ADDON_FONTS) do -- the suite's own five (ADR 0038)
    out[f[1]] = f[2]
  end
  for path in pairs(B.Compat.GetFontFiles()) do
    if not out[path] then
      out[path] = fontLabel(path)
    end
  end
  local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
  if lsm and type(lsm.HashTable) == "function" then
    for name, path in pairs(lsm:HashTable("font") or {}) do
      if type(path) == "string" and not out[path] then
        out[path] = name
      end
    end
  end
  return out
end

-- ---------------------------------------------------------------------------------------------
-- Companions and suite parts (core.md "What a client needs", ADR 0015): which of Bastian's addons
-- the installed apps need on this client, and the optional third-party addons the apps bridge to,
-- what each one adds and where to get it. Every app works without them (CLAUDE.md golden rule 4);
-- the hub lists both, the login says what is missing.
-- ---------------------------------------------------------------------------------------------

local CLIENT_NAMES = { forever = "WoW Forever", retail = "retail" }

-- The client's name for players ("WoW Forever", "retail").
function Settings_.ClientName(client)
  client = client or B.Client
  return CLIENT_NAMES[client] or tostring(client)
end

-- `clients` lists where the companion exists (its TOC's interfaces, checked 23.10.2026: QuestieDB
-- and Spoken ship for the Classic flavours and 16001 only, TomTom for both). `slug` is its
-- CurseForge project (tools/curseforge.toml relates to it).
-- TomTom is not one since 29.10.2026 (owner: "we drop tomtom as we have it ourselves": Route's
-- arrow, the map's own waypoint); a player who has it still gets its arrow and waypoints.
B.COMPANIONS = {
  {
    addon = "QuestieDB",
    what = L["a second source of NPC and object spawns where our data has none"],
    url = "https://www.curseforge.com/wow/addons/questie",
    clients = { "forever" },
  },
  {
    addon = "Spoken",
    what = L["voiced quest texts, zone lore, books and boss stories: the Orbiter plays them (3.7.0 or newer)"], -- luacheck: ignore 631 (a locale key stays one literal)
    url = "https://www.curseforge.com/wow/addons/spoken", -- Spoken; Spoken Quests is retired
    clients = { "forever" },
    min = "3.7.0", -- B.TESTED_WITH
  },
}

-- The companion versions the suite was tested with (plan-second-wave.md S2, 
-- "an addon we depend 100% on"): the Orbiter's note says when Spoken is newer or older than this,
-- and tools/companion_watch.py checks the launch client's copy against the same number every day.
B.TESTED_WITH = { Spoken = "3.7.0" }

-- The data packs by the pack name the apps declare in `data` (core-contracts §11; Data loads them).
-- Market and Nav are optional: built only when their source exists, no app fails without them.
B.PACK_ADDONS = {
  quests = "Bastians_Data_Quests",
  world = "Bastians_Data_World",
  items = "Bastians_Data_Items",
  text = "Bastians_Data_Text_enUS",
  -- the game data in other languages (data.md, ADR 0033): Data loads the client's
  text_deDE = "Bastians_Data_Text_deDE",
  text_frFR = "Bastians_Data_Text_frFR",
  text_esES = "Bastians_Data_Text_esES",
  text_koKR = "Bastians_Data_Text_koKR",
  text_zhCN = "Bastians_Data_Text_zhCN",
  text_zhTW = "Bastians_Data_Text_zhTW",
  market = "Bastians_Data_Market",
  nav = "Bastians_Data_Nav",
  book = "Bastians_Data_Strategies", -- the Strategies book (strategies-design.md section 6)
}
B.OPTIONAL_PACKS = {
  market = true,
  nav = true,
  book = true,
  text_deDE = true,
  text_frFR = true,
  text_esES = true,
  text_koKR = true,
  text_zhCN = true,
  text_zhTW = true,
}

-- Every released folder of the suite (the probe is never released): the fingerprint of an update.
B.SUITE_ADDONS = {
  "Bastians_Core",
  "Bastians_Data",
  "Bastians_Data_Quests",
  "Bastians_Data_World",
  "Bastians_Data_Items",
  "Bastians_Data_Text_enUS",
  "Bastians_Data_Text_deDE",
  "Bastians_Data_Text_frFR",
  "Bastians_Data_Text_esES",
  "Bastians_Data_Text_koKR",
  "Bastians_Data_Text_zhCN",
  "Bastians_Data_Text_zhTW",
  "Bastians_Data_Market",
  "Bastians_Data_Strategies",
  "Bastians_Map",
  "Bastians_Map_Art",
  "Bastians_Map_Blizzard",
  "Bastians_Map_Modern",
  "Bastians_Map_Pencil",
  "Bastians_Map_Parchment",
  "Bastians_Quests",
  "Bastians_Browser",
  "Bastians_Gold",
  "Bastians_Route",
  "Bastians_Strategies",
  "Bastians_Notes",
  "Bastians_Alts",
  "Bastians_Helpers",
  "Bastians_Voice",
  "Bastians_Chat",
  "Bastians_Gestures",
  "Bastians_Campfire",
}

-- The apps of the suite in the Suite page's order ("a first page where you can
-- toggle all addons", "a short explanation page for each"): the folder, the module name, the
-- slash command, the clients it ships for and what it does in one sentence a newcomer
-- understands. Core holds the words, so the page can describe an app that is not installed.
-- Since 01.11.2026 (plan-launch-review.md I1) it is the app's identity: `icon` (a glyph kind) is
-- the one icon of its minimap button, its feed and the hub (`B.UI.AppIcon`); `later` marks an app
-- that ships after the launch and is listed only where its folder is installed; `does` (three to
-- five lines a player understands), `keys` (its key bindings' actions) and `links` (module ->
-- what of this app needs that app) draw the app's page and the Help page (O3 to O5, 01.11.2026).
B.APPS = {
  {
    addon = "Bastians_Quests",
    icon = "app_quests", -- the app marks (plan-second-wave.md S1, 01.11.2026)
    module = "Quests",
    slash = "/bq",
    about = L["Every quest: what to do next here and at your level, chains and attunements, your log as a tracker, the quest text read aloud with Spoken."], -- luacheck: ignore 631 (a locale key stays one literal)
    does = {
      L["What to do next, here and at your level, with the reason"],
      L["Your log as a tracker: slim or wide, hide the done ones, tracked first"],
      L["Quest chains and attunements, and where you stand in them"],
      L["Every quest's text, read aloud with Spoken or the game's voice"],
      L["Your journey: experience, gold and kills per zone and session"],
    },
    keys = { "BASTIANS_QUESTS" },
    links = {
      Map = L["Show on map"],
      Route = L["Route there"],
      Browser = L["Open in Browser"],
      Voice = L["Play the quest's voice"],
    },
  },
  {
    addon = "Bastians_Map",
    icon = "app_map",
    module = "Map",
    slash = "/bmap",
    about = L["One seamless map of the world with every app's layers: quests, NPCs, nodes, notes and routes; the minimap in a frame of its own."], -- luacheck: ignore 631 (a locale key stays one literal)
    does = {
      L["One seamless map of both continents: zoom, drag, every app's pins as layers"],
      L["Bastian's minimap: the game's minimap in a frame of ours, with styles and a search"],
      L["Your own waypoints and bookmarks, the route's dotted line"],
      L["Pins on the game's minimap with arrows at the rim"],
    },
    keys = { "BASTIANS_MAP" },
    links = {
      Route = L["Route there"],
      Browser = L["Open a pin's page"],
      Quests = L["The quest pins"],
      Notes = L["Notes on the map"],
    },
  },
  {
    addon = "Bastians_Browser",
    icon = "app_browser",
    module = "Browser",
    slash = "/bb",
    about = L["Every NPC, item, quest, object, zone and dungeon on a page of its own, and a search that finds anything by name."], -- luacheck: ignore 631 (a locale key stays one literal)
    does = {
      L["A page for every NPC, item, quest, object, zone and dungeon"],
      L["One search that finds anything by name, with the types as its filter"],
      L["Lists by type with filters: where, level, rank, services"],
      L["The way there and its time on every row; the portrait and the dungeon's floors"],
    },
    links = {
      Map = L["Show on map"],
      Route = L["Route there"],
      Notes = L["Add a note"],
      Alts = L["Which of your characters has it"],
      Voice = L["Play its voice"],
    },
  },
  {
    addon = "Bastians_Gold",
    icon = "app_gold",
    module = "Gold",
    slash = "/bgold",
    clients = { forever = true },
    about = L["Auction house prices, your income, what things are worth, and how to earn gold with the time you have."], -- luacheck: ignore 631 (a locale key stays one literal)
    does = {
      L["Prices from your own auction house scans and the daily market export"],
      L["What an item is worth to you, on tooltips and rows"],
      L["Farm spots and strategies with their gold per hour"],
      L["Your income per day; what to post, vendor or keep when the bags fill"],
    },
    links = {
      Map = L["Farm spots on the map"],
      Route = L["Route to a spot"],
      Strategies = L["Live prices in the book"],
      Browser = L["An item's price on its page"],
    },
  },
  {
    addon = "Bastians_Route",
    icon = "app_route",
    module = "Route",
    slash = "/broute",
    about = L["A route to any place: a step list with times, a dotted line on the map and the minimap, flights and boats included."], -- luacheck: ignore 631 (a locale key stays one literal)
    does = {
      L["A route to any place: flights, boats, zeppelins, the tram, portals and the hearthstone"],
      L["A step list with times, a dotted line on the map and the minimap, an arrow to the next step"], -- luacheck: ignore 631 (a locale key stays one literal)
      L["Fastest, safest or without flight costs; home and every way back"],
      L["A round of several quest stops; what is worth doing nearby"],
    },
    keys = { "BASTIANS_ROUTE" },
    links = {
      Map = L["The route's line"],
      Quests = L["A quest's places as stops"],
      Notes = L["A note's spot as the goal"],
    },
  },
  {
    addon = "Bastians_Strategies",
    icon = "ledger",
    module = "Strategies",
    slash = "/bbook",
    clients = { forever = true },
    about = L["Bastian's book of gold rumours: strategies from the travellers, checked against live prices, read in game."], -- luacheck: ignore 631 (a locale key stays one literal)
    does = {
      L["Bastian's Gold Rumours: a book of gold strategies, told in game"],
      L["Live prices on every page from your scans"],
      L["The place of every farm on the map, and a route there"],
      L["Sealed pages open as you level and travel; bookmarks and notes"],
    },
    links = {
      Gold = L["Live prices"],
      Map = L["The farm on the map"],
      Route = L["Route there"],
      Browser = L["What a page names"],
    },
  },
  {
    addon = "Bastians_Notes",
    icon = "app_notes",
    module = "Notes",
    slash = "/bnotes",
    about = L["Your own notes and lists with places on the map, reminders, and sharing with your party."],
    does = {
      L["Notes on any NPC, quest, item or spot: on tooltips, pages and the map"],
      L["Lists you can hide, share with your group or guild, or paste as text"],
      L["Reminders when you come near or target what you noted"],
      L["Send your spot, or any place, to your group"],
    },
    links = {
      Map = L["Notes and shared spots on the map"],
      Browser = L["A note on a page"],
      Route = L["Route to a shared spot"],
    },
  },
  {
    addon = "Bastians_Alts",
    icon = "app_alts",
    module = "Alts",
    slash = "/balts",
    about = L["Your characters' bags, bank, mail and equipment, searchable from any of them; ask one for an item by mail."], -- luacheck: ignore 631 (a locale key stays one literal)
    does = {
      L["Every character's bags, bank, mail and equipment, read from any of them"],
      L["Which of your characters has an item, on its page and its tooltip"],
      L["Who knows a recipe or a trainer's lesson"],
      L["Ask another character for an item; its next mailbox visit fills the mail"],
    },
    links = {
      Browser = L["The characters and their pages"],
      Helpers = L["Send to at the mailbox"],
    },
  },
  {
    addon = "Bastians_Helpers",
    icon = "app_helpers",
    module = "Helpers",
    slash = "/bhelp",
    about = L["The small helpers: sell junk, repair, restock, take all mail, quest givers, IDs on tooltips and warnings."], -- luacheck: ignore 631 (a locale key stays one literal)
    does = {
      L["At the merchant: sell junk with Undo, repair, restock; Alt-click buys a stack"],
      L["At the mailbox: Take all, Send to your characters, the last recipient"],
      L["At quest givers: accept and hand in, skip gossip (off until you turn them on)"],
      L["IDs and item level on tooltips; a word when gear breaks or the bags fill"],
      L["A session panel: gold and experience per hour"],
    },
    links = {
      Browser = L["The never-sell and restock lists on an item's page"],
      Voice = L["The conversation without windows uses its quest helpers"],
    },
  },
  {
    addon = "Bastians_Voice",
    icon = "orbit",
    feed = "Orbiter",
    module = "Voice",
    slash = "/bv",
    about = L["The Orbiter: Spoken's narration on every quest, zone, boss and book around you, and quest conversations without windows."], -- luacheck: ignore 631 (a locale key stays one literal)
    does = {
      L["A round panel of what can be heard around you: the zone, the dungeon, quest givers and their quests, bosses, books"], -- luacheck: ignore 631 (a locale key stays one literal)
      L["Play on every such thing, in the Orbiter and on every row of the suite"],
      L["Quest conversations without the game's windows (off until you switch it on)"],
      L["Spoken's voice where it has a line, the game's voice for quest texts otherwise"],
    },
    keys = { "BASTIANS_VOICE_ORBIT", "BASTIANS_VOICE_PLAY", "BASTIANS_VOICE_STOP", "BASTIANS_VOICE_HEARD" },
    links = {
      Quests = L["The quests it lists"],
      Browser = L["Open in Browser"],
      Map = L["Show on map"],
      Route = L["Go there"],
      Helpers = L["Accept and hand in"],
    },
  },
  {
    addon = "Bastians_Chat",
    module = "Chat",
    slash = "/bchat",
    icon = "app_chat",
    about = L["The whole chat in windows of your own: tabs you define, a Messenger for whispers, a spam filter, long texts and copying. New: off until you try it."], -- luacheck: ignore 631 (a locale key stays one literal)
    does = {
      L["The whole chat in windows of your own, with tabs you define"],
      L["A Messenger for whispers: the people on the left, the conversation on the right"],
      L["A spam filter, long texts sent in parts, copying, web addresses as links"],
      L["Everything kept over /reload and logout"],
      L["Works with Spoken Players: it reads the chat aloud in race voices, Chat shows the words and never reads them twice"], -- luacheck: ignore 631 (a locale key stays one literal)
    },
  },
  {
    addon = "Bastians_Gestures",
    module = "Gestures",
    slash = "/bgest",
    icon = "app_gestures",
    keys = { "BASTIANS_GESTURES_RING", "BASTIANS_GESTURES_NEXT" }, -- its Bindings.xml (R5.1)
    about = L["Bastian's Gestures: a ring of emotes, your own lines and the suite's actions on one key; a ready thank-you when someone buffs you."], -- luacheck: ignore 631 (a locale key stays one literal)
    does = {
      L["A ring of the game's emotes on one key"],
      L["Your own lines with placeholders: the target's name, race, class, the zone; in your character's languages"], -- luacheck: ignore 631 (a locale key stays one literal)
      L["The suite's actions on a third ring: play the lore here, clear the screen, a note here"],
      L["A ready thank-you when someone buffs or resurrects you, or emotes at you"],
    },
    links = {
      Voice = L["Play the lore here"],
      Notes = L["A note here"],
      Map = L["Send my spot"],
    },
  },
  {
    addon = "Bastians_Campfire",
    module = "Campfire",
    slash = "/bcamp",
    icon = "app_campfire",
    clients = { forever = true }, -- camping is Forever's (plan-second-wave.md S5)
    about = L["Bastian's Campfire: a card while a fire is near, a ring for the camp, share the fire with your group and guild, and a planner of every camp feature."], -- luacheck: ignore 631 (a locale key stays one literal)
    does = {
      L["A card while a fire burns near: what the camp gives, what you could add, the time until you are warm"], -- luacheck: ignore 631 (a locale key stays one literal)
      L["A camp ring in Gestures: sit, offer a feature, thank the host, the place's story, share the fire"], -- luacheck: ignore 631 (a locale key stays one literal)
      L["Share the fire with your group and guild: a pin on their map for an hour"],
      L["The planner: every camp feature, its buff at your level, who of your characters can place it"], -- luacheck: ignore 631 (a locale key stays one literal)
    },
    links = {
      Gestures = L["The camp ring"],
      Map = L["Shared fires on the map"],
      Voice = L["The place's story at the fire"],
      Browser = L["The planner page"],
      Alts = L["Which of your characters can place a feature"],
      Route = L["Route to a shared fire"],
    },
  },
  {
    addon = "Bastians_Library",
    module = "Library",
    slash = "/btale",
    icon = "tale",
    later = true,
    about = L["The Library of Untold Tales: stories of the common folk, read in a book, opened by what you do in the world. After the launch."], -- luacheck: ignore 631 (a locale key stays one literal)
    does = {
      L["Stories of the common folk, read in a book"],
      L["Opened by what you do in the world: where you stand, what you say, whom you meet"],
      L["Read aloud with the tale's voice or the game's"],
    },
    links = {
      Quests = L["Leads in the tracker"],
      Browser = L["Open in Browser"],
    },
  },
  {
    addon = "Bastians_Data",
    icon = "app_data",
    module = "Data",
    about = L["The game data behind every app: quests, NPCs, items, places and prices, updated daily. Required."], -- luacheck: ignore 631 (a locale key stays one literal)
    does = {
      L["The game data behind every app: quests, NPCs, items, objects, zones, spawns"],
      L["Built per client from the client's own files and the licensed sources, updated daily"],
      L["Loaded only when an app asks for it"],
    },
  },
}

-- The apps of this client (an app that ships for another client only is not listed here).
function Settings_.Apps()
  local out = {}
  for _, app in ipairs(B.APPS) do
    if
      (not app.clients or app.clients[B.Client]) and (not app.later or C_AddOns.DoesAddOnExist(app.addon))
    then
      out[#out + 1] = app
    end
  end
  return out
end

-- The suite's words about an app, by its module name; nil for a module that is no app of the suite.
function Settings_.AppByModule(name)
  for _, app in ipairs(B.APPS) do
    if app.module == name then
      return app
    end
  end
  return nil
end

-- The suite's words about an app, by its folder; nil for a module that is no app of the suite.
function Settings_.AppOf(addon)
  for _, app in ipairs(B.APPS) do
    if app.addon == addon then
      return app
    end
  end
  return nil
end

local function exists(addon)
  return C_AddOns.DoesAddOnExist(addon) and true or false
end

local function onClient(c, client)
  for _, name in ipairs(c.clients or {}) do
    if name == client then
      return true
    end
  end
  return false
end

-- What a companion adds, by addon name (an app's other optional addon is one of ours).
local function companionWhat(addon)
  for _, c in ipairs(B.COMPANIONS) do
    if c.addon == addon then
      return c.what, c.url
    end
  end
  return nil
end

-- The companions of a client (default: this one): { addon, what, url, installed }, installed first.
-- A companion that does not exist for the client is left out: retail is never told about QuestieDB.
function Settings_.Companions(client)
  client = client or B.Client
  local list = {}
  for _, c in ipairs(B.COMPANIONS) do
    if onClient(c, client) then
      list[#list + 1] = { addon = c.addon, what = c.what, url = c.url, installed = exists(c.addon) }
    end
  end
  table.sort(list, function(a, b)
    if a.installed ~= b.installed then
      return a.installed
    end
    return a.addon < b.addon
  end)
  return list
end

-- Whether an app's optional addon applies to this client: a companion of another client is no
-- missing feature here (Quests on retail does not miss QuestieDB).
function Settings_.AppliesHere(addon)
  for _, c in ipairs(B.COMPANIONS) do
    if c.addon == addon or addon:find("^" .. c.addon .. "_") then
      return onClient(c, B.Client)
    end
  end
  return true
end

-- The parts of the suite the installed apps need: { addon, installed, required, neededBy = { app
-- titles } }, in B.SUITE_ADDONS order. Required: Bastian's Data and every non-optional pack an app
-- declares in `data`; optional: the Bastian's addons an app lists in `optional` (Map Art).
function Settings_.Parts()
  local need = {} -- addon -> { required, neededBy }
  local function add(addon, required, title)
    local n = need[addon] or { required = false, neededBy = {} }
    n.required = n.required or required
    for _, t in ipairs(n.neededBy) do
      if t == title then
        title = nil
      end
    end
    if title then
      n.neededBy[#n.neededBy + 1] = title
    end
    need[addon] = n
  end
  add("Bastians_Core", true, nil)
  for _, mod in ipairs(ns.moduleList) do
    if not mod.parent and mod.name ~= "Data" and mod.name ~= "Core" then
      if mod.data and #mod.data > 0 then
        add("Bastians_Data", true, mod.title)
        for _, pack in ipairs(mod.data) do
          if B.PACK_ADDONS[pack] and not B.OPTIONAL_PACKS[pack] then
            add(B.PACK_ADDONS[pack], true, mod.title)
          end
        end
      end
      for _, addon in ipairs(mod.optional or {}) do
        if addon:find("^Bastians_") and addon ~= "Bastians_Data" then
          add(addon, false, mod.title)
        end
      end
    end
  end
  local out = {}
  for _, addon in ipairs(B.SUITE_ADDONS) do
    local n = need[addon]
    if n then
      local installed = exists(addon)
      out[#out + 1] = {
        addon = addon,
        required = n.required,
        neededBy = n.neededBy,
        installed = installed,
        disabled = installed and not B.Compat.IsAddOnEnabled(addon), -- off in the AddOns list
      }
    end
  end
  return out
end

-- The required parts that are not installed, as words, or nil.
function Settings_.MissingParts()
  local missing = {}
  for _, p in ipairs(Settings_.Parts()) do
    if p.required and (not p.installed or p.disabled) then
      local words = {}
      if p.disabled then
        words[#words + 1] = L["switched off in the AddOns list"]
      end
      if #p.neededBy > 0 then
        words[#words + 1] = L["needed by"] .. " " .. table.concat(p.neededBy, ", ")
      end
      missing[#missing + 1] = #words > 0 and ("%s (%s)"):format(p.addon, table.concat(words, ", ")) or p.addon
    end
  end
  return #missing > 0 and missing or nil
end

-- Every login while a required part is missing: the install is broken, say so each time.
function Settings_.NoteParts()
  local missing = Settings_.MissingParts()
  if not missing then
    return false
  end
  local text = "Missing parts for %s: %s. Install the %s files (the bundle or the -%s zips);"
    .. " /bastians addons lists every part."
  B:Say(L[text], Settings_.ClientName(), table.concat(missing, "; "), Settings_.ClientName(), B.Client)
  return true
end

-- The installed suite as one string: the client and every folder's version. It changes with any
-- update of any of Bastian's addons, not only Core's. Without `full` a Data edition's
-- "+data.<date>.<n>" is left out (the optional addons are not listed again every day); What's new
-- compares the full one (ADR 0021).
function Settings_.Fingerprint(full)
  local parts = { B.Client }
  for _, addon in ipairs(B.SUITE_ADDONS) do
    if exists(addon) then
      local version = tostring(C_AddOns.GetAddOnMetadata(addon, "Version") or "?")
      if not full then
        version = string.gsub(version, "%+.*$", "")
      end
      parts[#parts + 1] = addon .. "=" .. version
    end
  end
  return table.concat(parts, ";")
end

-- The optional addons of this client in one line (installed or not, with what they add).
function Settings_.CompanionLine()
  local items = {}
  for _, c in ipairs(Settings_.Companions()) do
    items[#items + 1] = c.installed and ("%s (%s)"):format(c.addon, L["installed"])
      or ("%s (%s: %s)"):format(c.addon, L["not installed"], c.what)
  end
  if #items == 0 then
    return nil
  end
  return string.format(
    L["Optional addons for %s: %s. Everything works without them; /bastians addons lists them."],
    Settings_.ClientName(),
    table.concat(items, "; ")
  )
end

-- The optional addons, once at the first start and after every update of any part of the suite
--, per account: one chat line, installed ones included.
function Settings_.NoteCompanions()
  local db = ns.core.db and ns.core.db.global
  if not db then
    return false
  end
  local fingerprint = Settings_.Fingerprint()
  if db.companionsNoted == fingerprint then
    return false
  end
  db.companionsNoted = fingerprint
  local line = Settings_.CompanionLine()
  if not line then
    return false
  end
  B:Say(line)
  return true
end

-- /bastians addons: both lists, always.
function Settings_.PrintAddons()
  for _, p in ipairs(Settings_.Parts()) do
    local state = p.disabled and L["switched off"]
      or p.installed and L["installed"]
      or (p.required and L["MISSING"] or L["not installed"])
    local who = #p.neededBy > 0 and (" - " .. L["needed by"] .. " " .. table.concat(p.neededBy, ", ")) or ""
    B:Say("%s: %s%s%s", p.addon, state, p.required and "" or (" (" .. L["optional"] .. ")"), who)
  end
  local line = Settings_.CompanionLine()
  if line then
    B:Say(line)
  end
end

-- ---------------------------------------------------------------------------------------------
-- Core's module: profiles, tooltip lines, font, debug, load-on-demand switches
-- ---------------------------------------------------------------------------------------------

-- Looks as presets (ADR 0038, "we deliver all 3, with the option to change
-- everything per option menu and save as new preset"; ADR 0046: the Azeroth preset went on
-- 01.11.2026, its profiles moved to WoW by migration 3). A preset is every look setting at once;
-- a player's own are kept account-wide (db.global.presets); any change after shows "custom". The
-- game's frames stay on in every preset.
Settings_.LOOK_KEYS = {
  "look", -- the renderer (ADR 0046): modern | wow | parchment | glass
  "gameFrames",
  "skinFrames",
  "theme",
  "font",
  "headingFont",
  "fontScale",
  "windowColor",
  "windowAlpha",
  "gameButtons",
  "ornaments",
  "rowPortraits",
  "placeCuts",
  "diorama",
  "modelMotion",
  "pageSounds",
}
local LOOK = {}
for _, key in ipairs(Settings_.LOOK_KEYS) do
  LOOK[key] = true
end
local function modern(theme)
  return {
    look = "modern",
    gameFrames = false,
    skinFrames = true,
    theme = theme,
    font = S.DEFAULT_FONT,
    headingFont = nil,
    fontScale = 100,
    windowColor = nil,
    windowAlpha = 100,
    gameButtons = false,
    ornaments = false,
    rowPortraits = true,
    placeCuts = true,
    diorama = true,
    modelMotion = true,
    pageSounds = true,
  }
end
-- the built-ins, in the order of the choice; `font` and `headingFont` are the client's on a CJK
-- client (Friz Quadrata and Morpheus carry no Hangul or Han)
-- The game's look on a scheme (, "a clearly skinned style according to
-- Blizzard examples"): the game's own windows and insets, its buttons, Friz Quadrata and Morpheus.
local function game(theme)
  local v = modern(theme)
  v.look = "wow"
  v.gameFrames = true
  v.font = S.CJK and S.DEFAULT_FONT or S.BLIZZARD_FONT
  v.headingFont = (not S.CJK) and S.HEADING_FONT or nil
  v.gameButtons = true
  v.ornaments = true
  return v
end
-- A look of its own on a scheme (plan-round4 H4): the Modern settings with the renderer named,
-- and a heading font where the look asks for one (Parchment: a serif).
local function styled(theme, lookId, headingFont)
  local v = modern(theme)
  v.look = lookId
  v.headingFont = (not S.CJK) and headingFont or nil
  return v
end
-- The seven (plan-round4 H5, 01.11.2026): the Modern renderer on four schemes, Glass, Parchment, WoW.
Settings_.PRESETS = {
  { id = "modern-dark", name = "Modern dark", values = modern("teal") },
  { id = "modern-light", name = "Modern light", values = modern("parchment") },
  { id = "modern-graphite", name = "Modern graphite", values = modern("graphite") },
  { id = "night", name = "Night", values = modern("night") },
  -- translucent plates under every text; dark glass on Dark teal (a light scheme gives light glass)
  { id = "glass", name = "Glass", values = styled("teal", "glass") },
  -- paper panels, brown ink, serif headings, square tiles with a sepia edge, no gold text
  { id = "parchment", name = "Parchment", values = styled("parchment", "parchment", S.SERIF_FONT) },
  -- the Character, Dungeon Finder and Guild windows: gold and white on the dark marble insets
  { id = "wow", name = "WoW (the game's windows)", values = game("blizzard") },
}

-- Writes every look setting of the built-in preset `id` into the profile table `p` (migrations).
local function writePreset(p, id)
  for _, preset in ipairs(Settings_.PRESETS) do
    if preset.id == id then
      for _, key in ipairs(Settings_.LOOK_KEYS) do
        p[key] = preset.values[key]
      end
    end
  end
  p.preset = id
end

local function presetValues(mod, id)
  for _, preset in ipairs(Settings_.PRESETS) do
    if preset.id == id then
      return preset.values
    end
  end
  local name = string.match(id or "", "^user:(.+)$")
  local saved = name and mod.db.global.presets and mod.db.global.presets[name]
  return saved
end

-- Writes every look setting of the preset `id` (a built-in or "user:<name>") and applies them;
-- `fromSelect` when the select wrote `preset` already. An unknown id does nothing.
function Settings_.ApplyPreset(mod, id, fromSelect)
  local values = presetValues(mod, id)
  if not values then
    return false
  end
  local p = mod.db.profile
  Settings_.applying = true
  for _, key in ipairs(Settings_.LOOK_KEYS) do
    p[key] = values[key]
  end
  p.preset = id
  S.ApplyTheme(p.theme)
  S.applyFont()
  S.ApplySkin()
  Settings_.applying = false
  if not fromSelect then
    B:Fire("BASTIANS_SETTING_CHANGED", mod.name, "preset", id)
  end
  if B.UI.Hub then
    B.UI.Hub.Refresh() -- the choice and the rows show the new values
  end
  return true
end

-- Keeps the current look under `name` for every character and profile, and selects it.
function Settings_.SavePreset(mod, name)
  name = string.match(tostring(name or ""), "^%s*(.-)%s*$")
  if name == "" then
    return false
  end
  local p = mod.db.profile
  local values = {}
  for _, key in ipairs(Settings_.LOOK_KEYS) do
    values[key] = p[key]
  end
  mod.db.global.presets = mod.db.global.presets or {}
  mod.db.global.presets[name] = values
  p.preset = "user:" .. name
  B:Fire("BASTIANS_SETTING_CHANGED", mod.name, "preset", p.preset)
  if B.UI.Hub then
    B.UI.Hub.Refresh()
  end
  return true
end

-- Removes the saved preset that is chosen; the settings stay as they are ("custom").
function Settings_.DeletePreset(mod)
  local p = mod.db.profile
  local name = string.match(p.preset or "", "^user:(.+)$")
  if not name or not (mod.db.global.presets and mod.db.global.presets[name]) then
    return false
  end
  mod.db.global.presets[name] = nil
  p.preset = "custom"
  B:Fire("BASTIANS_SETTING_CHANGED", mod.name, "preset", p.preset)
  if B.UI.Hub then
    B.UI.Hub.Refresh()
  end
  return true
end

-- The choice: the built-ins, the saved ones ("user:<name>"), and Custom.
function Settings_.PresetChoices(mod)
  local values = {}
  for _, preset in ipairs(Settings_.PRESETS) do
    values[preset.id] = L[preset.name]
  end
  for name in pairs(mod.db.global.presets or {}) do
    values["user:" .. name] = name
  end
  values.custom = L["Custom"]
  return values
end

-- A look setting changed by hand: the preset shows as Custom (not while a preset is applied).
function Settings_.NoteLookChange(mod, key)
  if Settings_.applying or not LOOK[key] then
    return
  end
  local p = mod.db.profile
  if p.preset ~= "custom" then
    p.preset = "custom"
    if B.UI.Hub then
      B.UI.Hub.Refresh()
    end
  end
end

local function profileValues()
  local values = {}
  for _, name in ipairs(B:GetProfiles()) do
    values[name] = name
  end
  return values
end

ns.core = B:NewModule("Core", {
  news = ns.NEWS, -- What's new (ADR 0021)
  addon = ns.ADDON,
  title = L["General"],
  apiVersion = 1,
  -- one key clears the screen (plan-round4 F1): the page lists what hides, built when shown
  pages = {
    {
      id = "screen",
      title = L["Hidden by the key"],
      icon = "hide", -- the hub's pictogram (02.11.2026)
      build = function()
        return B.UI.Screen.Options()
      end,
    },
  },
  noSwitch = true, -- Core cannot be disabled
  db = "BastiansCoreDB",
  charDb = "BastiansCoreCharDB",
  defaults = {
    profile = {
      tooltipLines = 6, -- 3 before the guide gaps (23.10.2026): target of, drops, givers
      noticeTab = "Addons", -- the chat tab of the apps' notices
      tips = true, -- a tip on every button after the hover delay
      fontScale = 100, -- the text size in percent
      tipDelay = 1, -- seconds
      font = S.DEFAULT_FONT,
      theme = "teal", -- the colour scheme (ST3, ADR 0017)
      windowAlpha = 100, -- the windows' opacity in percent (R27.2); windowColor nil: the theme's
      -- the look (ADR 0034, ADR 0038): the preset, the game's window frames, the content switches
      preset = "modern-dark",
      gameButtons = false,
      ornaments = false,
      skinFrames = true, -- the game's frames are the standard
      rowPortraits = true,
      placeCuts = true,
      diorama = true,
      modelMotion = true,
      pageSounds = true,
      lod = {},
      minimap = { hide = false, angle = 200 },
      wordsNotice = "text", -- Words (plan-launch-review R5.3): text | voice | both per kind
      wordsReminder = "text",
      wordsStep = "text",
      wordsArrival = "text",
      hub = {},
      welcome = {}, -- the welcome window
      floorWindow = {}, -- the enlarged dungeon floor (DG2c)
      omnibox = {},
      omniboxTree = {},
    },
    global = { debug = false, perf = {}, newsMode = "always", presets = {}, welcomeAtLogin = true },
  },
  -- 2 (ADR 0038): the skin of ADR 0034 becomes a preset; every profile of the account
  migrations = {
    [2] = function(db)
      local sv = rawget(db, "sv")
      local profiles = sv and sv.profiles or { db.profile }
      for _, p in pairs(profiles) do
        local skin = type(p) == "table" and rawget(p, "skin")
        if skin ~= nil then
          p.skin = nil
        end
        if type(p) == "table" and rawget(p, "preset") == nil then
          if skin == "azeroth" or skin == "blizzard" then
            -- the game's look of old becomes the game's look of now (31.10.2026): both the WoW
            -- preset since Azeroth went (ADR 0046), every look setting written
            writePreset(p, "wow")
          elseif rawget(p, "theme") == "parchment" then
            p.preset = "modern-light"
          elseif skin ~= nil or rawget(p, "theme") ~= nil then
            p.preset = "custom"
          end
        end
      end
    end,
    -- 3: the Azeroth preset and its scheme
    -- are gone. A profile on the preset moves to WoW once (every look setting written, a line in
    -- the log); a custom look or a saved preset on the Azeroth scheme takes Parchment, the light
    -- scheme that stays.
    [3] = function(db)
      local sv = rawget(db, "sv")
      local profiles = sv and sv.profiles or { db.profile }
      local moved = 0
      for _, p in pairs(profiles) do
        if type(p) == "table" then
          if rawget(p, "preset") == "azeroth" then
            writePreset(p, "wow")
            moved = moved + 1
          elseif rawget(p, "theme") == "azeroth" then
            p.theme = "parchment"
          end
        end
      end
      local saved = sv and sv.global and sv.global.presets
      for _, values in pairs(type(saved) == "table" and saved or {}) do
        if type(values) == "table" and values.theme == "azeroth" then
          values.theme = "parchment"
        end
      end
      if moved > 0 then
        B:Log(nil, "info", "the Azeroth look is gone: %d profile(s) now wear the WoW look", moved)
      end
    end,
  },
  options = {
    { type = "header", label = L["Profiles"] },
    {
      type = "select",
      key = "profile",
      desc = L["The settings of this character: every look and every app's switch. Several characters may share one."], -- luacheck: ignore 631 (a locale key stays one literal)
      label = L["Profile for this character"],
      values = profileValues,
      get = function()
        return B:GetProfile()
      end,
      set = function(name)
        B:SetProfile(name)
      end,
    },
    {
      type = "edit",
      key = "newProfile",
      desc = L["Starts a new profile as a copy of this one, or switches to one of that name."],
      label = L["New profile (press Enter)"],
      -- a new profile starts as a copy of this one ("you enter a name,
      -- press return, then the skin resets to our modern default"); an existing name is switched to
      set = function(name)
        if name ~= "" then
          B:SetProfile(name, true)
        end
      end,
    },
    -- every look setting of the suite in one section; every addon
    -- follows it. Looks as presets: two buttons on top, the Preset
    -- choice, save and delete, then every setting free.
    { type = "header", label = L["Skin (every Bastian's addon)"] },
    {
      type = "execute",
      icon = "keep",
      label = L["Use the WoW look"],
      desc = L["The game's own windows on every window: its frame, title bar, close button and insets, gold and white on dark."], -- luacheck: ignore 631 (a locale key stays one literal)
      func = function(mod)
        Settings_.ApplyPreset(mod, "wow")
      end,
    },
    {
      type = "execute",
      icon = "layers",
      label = L["Use the Modern look"],
      desc = L["The flat look on the dark teal scheme; Modern light is the same on parchment."],
      -- the other presets (Modern graphite, Night, Glass, Parchment) are in the Preset choice below
      func = function(mod)
        Settings_.ApplyPreset(mod, "modern-dark")
      end,
    },
    {
      type = "select",
      key = "preset",
      desc = L["Every look setting at once: the renderer, the colours, the fonts. Change anything after and save your own."], -- luacheck: ignore 631 (a locale key stays one literal)
      label = L["Preset"],
      values = function(mod)
        return Settings_.PresetChoices(mod)
      end,
      set = function(id, mod)
        if id ~= "custom" then
          Settings_.ApplyPreset(mod, id, true)
        end
      end,
    },
    {
      type = "edit",
      key = "newPreset",
      label = L["Save as new preset (press Enter)"],
      set = function(name, mod)
        Settings_.SavePreset(mod, name)
      end,
    },
    {
      type = "execute",
      icon = "remove",
      label = L["Delete this preset"],
      desc = L["Removes the saved preset that is chosen; the settings stay as they are."],
      func = function(mod)
        Settings_.DeletePreset(mod)
      end,
    },
    {
      type = "toggle",
      key = "gameFrames",
      label = L["The game's own windows and insets"],
      set = S.ApplySkin,
    },
    { type = "toggle", key = "skinFrames", label = L["The game's window frames"], set = S.ApplySkin },
    {
      type = "select",
      key = "theme",
      desc = L["The colour scheme: every token the suite draws with, from the window ground to the tiles."], -- luacheck: ignore 631 (a locale key stays one literal)
      label = L["Colour scheme"],
      values = function()
        local values = {}
        for _, theme in ipairs(S.Themes()) do
          values[theme.id] = L[theme.name]
        end
        return values
      end,
      set = function(id)
        S.ApplyTheme(id)
      end,
    },
    {
      type = "select",
      key = "font",
      desc = L["The font of every text of the suite; a CJK client keeps its own."],
      label = L["Font"],
      values = function()
        return Settings_.FontChoices()
      end,
      set = function()
        S.applyFont()
      end,
    },
    {
      -- the heading font (ADR 0038): window titles, page names and section titles; "" is the text font
      type = "select",
      key = "headingFont",
      desc = L["The font of window titles, page names and section titles."],
      label = L["Heading font"],
      values = function()
        local values = Settings_.FontChoices()
        values[""] = L["Same as the text"]
        return values
      end,
      get = function(mod)
        return mod.db.profile.headingFont or ""
      end,
      set = function(path, mod)
        mod.db.profile.headingFont = path ~= "" and path or nil
        S.applyFont()
      end,
    },
    {
      type = "range",
      key = "fontScale",
      desc = L["Every text of the suite larger or smaller, in percent."],
      label = L["Text size (percent)"],
      min = 80,
      max = 130,
      step = 5,
      set = function()
        S.applyFont()
      end,
    },
    {
      type = "color",
      key = "windowColor",
      desc = L["The ground of every window; an app may set its own on its page."],
      label = L["Window background"],
      theme = S.C.bg,
    },
    {
      type = "range",
      key = "windowAlpha",
      desc = L["How much of the world shows through the windows' ground."],
      label = L["Window opacity (%)"],
      min = 20,
      max = 100,
      step = 5,
    },
    {
      type = "toggle",
      key = "gameButtons",
      desc = L["The game's red button textures on every button of the suite."],
      label = L["The game's buttons"],
      set = S.ApplySkin,
    },
    {
      type = "toggle",
      key = "ornaments",
      desc = L["The gold rule under section titles, as the game's quest frame draws it."],
      label = L["Ornaments under section titles"],
      set = S.ApplySkin,
    },
    {
      type = "toggle",
      key = "rowPortraits",
      desc = L["Rows of NPCs show the creature's face instead of the kind tile."],
      label = L["Faces in the rows of NPCs"],
      set = S.ApplySkin,
    },
    {
      type = "toggle",
      key = "placeCuts",
      desc = L["Places as small cuts of the zone's painting with a pin."],
      label = L["Places as cuts of the map"],
      set = S.ApplySkin,
    },
    {
      type = "toggle",
      key = "diorama",
      desc = L["The zone's painting, dimmed, behind a creature's portrait."],
      label = L["The zone's painting behind a creature"],
      set = S.ApplySkin,
    },
    {
      type = "toggle",
      key = "modelMotion",
      desc = L["A creature greets when it shows and plays an emote now and then."],
      label = L["Creatures greet and talk"],
      set = S.ApplySkin,
    },
    {
      type = "toggle",
      key = "pageSounds",
      desc = L["The page turn when a page opens, the quest log's sound for a quest."],
      label = L["Sounds when a page opens"],
    },
    { type = "header", label = L["Display"] },
    {
      type = "toggle",
      key = "minimapHide",
      desc = L["The suite's own button at the minimap: the search on a click, every app on a right click."], -- luacheck: ignore 631 (a locale key stays one literal)
      label = L["Hide the minimap button"],
      get = function(mod)
        return mod.db.profile.minimap.hide
      end,
      set = function(on, mod)
        mod.db.profile.minimap.hide = on and true or false
      end,
    },
    {
      -- the options window as a minimap button of its own, on by default
      type = "toggle",
      key = "minimapHub",
      desc = L["A second button at the minimap that opens these settings."],
      label = L["Its own minimap button for the options"],
      get = function()
        return not B.UI.Launcher.AppSettings("Options").hide
      end,
      set = function(on)
        B.UI.Launcher.SetAppButton("Options", on)
      end,
    },
    {
      type = "toggle",
      key = "minimapWelcome",
      desc = L["A button at the minimap that shows the welcome with the Wanderer and the Scholar again."],
      label = L["Its own minimap button for the welcome"],
      get = function()
        return not B.UI.Launcher.AppSettings("Welcome").hide
      end,
      set = function(on)
        B.UI.Launcher.SetAppButton("Welcome", on)
      end,
    },
    {
      type = "range",
      key = "tooltipLines",
      desc = L["How many lines of the suite a tooltip may add: prices, notes, who has it."],
      label = L["Extra tooltip lines"],
      min = 0,
      max = 10,
      step = 1,
    },
    {
      type = "select",
      key = "newsMode",
      desc = L["After an update: a dot on the minimap button and one chat line (Always), the line at most weekly, or nothing (Never). /bastians news lists everything."], -- luacheck: ignore 631 (a locale key stays one literal)
      scope = "global",
      label = L["Tell me about updates"],
      values = function()
        return { always = L["Always"], weekly = L["Weekly"], never = L["Never"] }
      end,
      set = function()
        B.UI.News.UpdateDot() -- What's new (ADR 0021): the dot follows the choice at once
      end,
    },
    {
      type = "toggle",
      key = "welcomeAtLogin",
      desc = L["The welcome window at every login, until Don't show again in its corner (plan-launch-version D)."], -- luacheck: ignore 631 (a locale key stays one literal)
      scope = "global",
      label = L["Show the welcome at every login"],
    },
    {
      type = "toggle",
      key = "tips",
      desc = L["A small explanation under the mouse on every button and setting."],
      label = L["Explain buttons when the mouse rests on them"],
    },
    {
      type = "range",
      key = "tipDelay",
      desc = L["How long the mouse rests before the explanation shows."],
      label = L["Seconds before a button's explanation shows"],
      min = 0,
      max = 3,
      step = 0.5,
    },
    -- Words (plan-launch-review R5.3): how the suite talks to the player, per kind
    { type = "header", label = L["Words (how the suite talks to me)"] },
    {
      type = "select",
      key = "wordsNotice",
      label = L["Notices (what a helper did)"],
      desc = L["Text is the notice strip and the Addons chat tab; Voice is the game's voice through the Orbiter."], -- luacheck: ignore 631 (a locale key stays one literal)
      values = { text = L["Text"], voice = L["Voice"], both = L["Both"] },
    },
    {
      type = "select",
      key = "wordsReminder",
      label = L["Reminders (a note near you or on your target)"],
      desc = L["Text is a chat line; Voice reads the note aloud."],
      values = { text = L["Text"], voice = L["Voice"], both = L["Both"] },
    },
    {
      type = "select",
      key = "wordsStep",
      label = L["Route steps (the next step of your route)"],
      desc = L["Voice says the next step when you reach one; Text leaves it to the step list and the arrow."], -- luacheck: ignore 631 (a locale key stays one literal)
      values = { text = L["Text"], voice = L["Voice"], both = L["Both"] },
    },
    {
      type = "select",
      key = "wordsArrival",
      label = L["Arrivals (you are there)"],
      desc = L["Text is a chat line; Voice says it."],
      values = { text = L["Text"], voice = L["Voice"], both = L["Both"] },
    },
    { type = "header", label = L["Diagnostics"] },
    {
      type = "toggle",
      key = "debug",
      desc = L["Every step of the suite in the chat, for a bug report; /bastians log shows the last lines."], -- luacheck: ignore 631 (a locale key stays one literal)
      scope = "global",
      label = L["Verbose logging to chat"],
      set = function(on)
        B.debug = on and true or false
      end,
    },
    {
      type = "execute",
      icon = "page",
      label = L["Show the log"],
      func = function()
        B:PrintLog(20)
      end,
    },
  },
  OnEnable = function(self)
    B.debug = self.db.global.debug and true or false
    S.applyFont()
    S.ApplyTheme(self.db.profile.theme)
    S.ApplySkin() -- the profile's skin over what was built before it was read (ADR 0034)
    self:On("BASTIANS_THEME_CHANGED", function() -- the hub shows the new scheme at once (ST3)
      if B.UI.Hub then
        B.UI.Hub.Refresh()
      end
    end)
    self:On("BASTIANS_PROFILE_CHANGED", function(me)
      S.ApplyTheme(me.db.profile.theme) -- each profile keeps its own scheme
      S.applyFont()
      S.ApplySkin() -- and its own skin (ADR 0034); redraws the windows too
    end)
    self:On("BASTIANS_SETTING_CHANGED", function(me, _, modName, key)
      if modName == me.name and (key == "windowColor" or key == "windowAlpha") then
        B.UI.ApplyWindowLook()
      end
      if modName == me.name then
        Settings_.NoteLookChange(me, key) -- a look changed by hand: the preset reads Custom (ADR 0038)
      end
    end)
  end,
})

-- Newest n log lines to chat (the ring buffer never spams on its own).
function B:PrintLog(n)
  local lines = B:GetLog(n or 20)
  if #lines == 0 then
    B:Say(L["The log is empty."])
    return
  end
  for _, line in ipairs(lines) do
    DEFAULT_CHAT_FRAME:AddMessage((S.H.chat .. "[%s]|r %s: %s"):format(line.level, line.owner, line.text))
  end
end

-- ---------------------------------------------------------------------------------------------
-- Load-on-demand apps: a switch per addon with "## X-Bastians-LoD: 1", loaded at login when on
-- ---------------------------------------------------------------------------------------------

local lodApps = {} -- addon name -> title

local function scanLodApps()
  for i = 1, C_AddOns.GetNumAddOns() do
    local name, title = C_AddOns.GetAddOnInfo(i)
    if name and C_AddOns.GetAddOnMetadata(name, "X-Bastians-LoD") then
      lodApps[name] = title or name
    end
  end
end

function Settings_.LodApps()
  return lodApps
end

function Settings_.IsLodOn(addon)
  return ns.core.db.profile.lod[addon] == true
end

function Settings_.SetLod(addon, on)
  ns.core.db.profile.lod[addon] = on and true or nil
  if on then
    B.Compat.LoadAddOn(addon)
  else
    B:Say(L["%s turns off at the next /reload."], lodApps[addon] or addon)
  end
end

local function loadLodApps()
  for addon in pairs(lodApps) do
    if Settings_.IsLodOn(addon) then
      B.Compat.LoadAddOn(addon)
    end
  end
end

-- ---------------------------------------------------------------------------------------------
-- Values: an option reads and writes mod.db[scope][key], or its own get/set
-- ---------------------------------------------------------------------------------------------

local function scopeTable(mod, option)
  return mod.db[option.scope or "profile"]
end

local function getValue(mod, option)
  if option.get then
    return option.get(mod)
  end
  local value = scopeTable(mod, option)[option.key]
  if value == nil then
    return option.default
  end
  return value
end

local function setValue(mod, option, value)
  if option.key and not option.get then
    scopeTable(mod, option)[option.key] = value
  end
  if option.set then
    ns.safecall(mod, option.set, value, mod)
  end
  B:Fire("BASTIANS_SETTING_CHANGED", mod.name, option.key, value)
end

-- ---------------------------------------------------------------------------------------------
-- Renderer: draws a module's switch, notes, options and sub-modules into a canvas frame
-- ---------------------------------------------------------------------------------------------

local function missingOptional(mod)
  local out = {}
  for _, addon in ipairs(mod.optional or {}) do
    if not C_AddOns.DoesAddOnExist(addon) and Settings_.AppliesHere(addon) then
      out[#out + 1] = addon
    end
  end
  return out
end

-- An option's `desc` is its tooltip, whatever its type (O4, 01.11.2026; before only `execute`
-- had one): the widget carries `tip`, the kit's TipEnter shows it after the delay.
local function describe(w, desc)
  if desc and w then
    w.tip = desc
    if w.EnableMouse then
      w:EnableMouse(true)
    end
    w:HookScript("OnEnter", S.TipEnter)
    w:HookScript("OnLeave", S.TipLeave)
  end
  return w
end

local function widgetFor(canvas, option, mod)
  local kind = option.type
  if kind == "header" then
    return Wd.Header(canvas, option.label)
  elseif kind == "toggle" then
    local w = Wd.Checkbox(canvas, option.label, function(on)
      setValue(mod, option, on)
    end)
    w:SetChecked(getValue(mod, option) and true or false)
    return describe(w, option.desc)
  elseif kind == "range" then
    local w = Wd.Slider(
      canvas,
      option.label,
      option.min or 0,
      option.max or 100,
      option.step or 1,
      function(v)
        setValue(mod, option, v)
      end
    )
    w:SetValue(tonumber(getValue(mod, option)) or option.min or 0, true)
    return describe(w, option.desc)
  elseif kind == "select" or kind == "font" then
    local values = option.values or FONTS
    if type(values) == "function" then
      values = values(mod)
    end
    local w = Wd.Select(canvas, option.label, values, function(key)
      setValue(mod, option, key)
    end)
    w:SetValue(getValue(mod, option))
    return describe(w, option.desc)
  elseif kind == "execute" then
    -- a column of equal buttons: the width stays the hub's; `icon` names the pictogram (ADR 0046)
    local w = S.action(canvas, { icon = option.icon, label = option.label, boxed = true, width = 160 })
    w.tip = option.desc
    w:SetScript("OnClick", function()
      ns.safecall(mod, option.func, mod)
    end)
    return w
  elseif kind == "note" then
    local text = option.text
    if type(text) == "function" then
      local ok, result = ns.safecall(mod, text, mod)
      text = ok and result or ""
    end
    return Wd.Note(canvas, text)
  elseif kind == "edit" then
    local w = Wd.Edit(canvas, option.label, function(text)
      setValue(mod, option, text)
    end)
    return describe(w, option.desc)
  elseif kind == "color" then
    local w = Wd.Color(canvas, option.label, function()
      return getValue(mod, option)
    end, function(value)
      setValue(mod, option, value)
    end, option.theme)
    return describe(w, option.desc)
  end
  return Wd.Note(canvas, ("unknown option type %s"):format(tostring(kind)), S.C.warn)
end

-- "Open <app>": the app's window from the hub, so nobody needs its slash command
local function openRow(canvas, mod)
  local row = CreateFrame("Frame", nil, canvas)
  row:SetHeight(24)
  row.button =
    S.action(row, { icon = "open", label = L["Open %s"]:format(mod.title), boxed = true, width = 160 })
  row.button.tip = L["Opens the window of this app."]
  row.button:SetPoint("LEFT", 0, 0)
  row.button:SetScript("OnClick", function()
    if mod:IsEnabled() then
      mod.def.open()
    else
      B:Say(L["%s is switched off."], mod.title)
    end
  end)
  return row
end

-- "Its own minimap button", on by default
local function minimapRow(canvas, mod)
  local mm = Wd.Checkbox(canvas, L["Its own minimap button"], function(on)
    B.UI.Launcher.SetAppButton(mod.name, on)
  end)
  mm:SetChecked(not B.UI.Launcher.AppSettings(mod.name).hide)
  return mm
end

-- The app's switch: on or off at runtime, the others keep working (CLAUDE.md golden rule 4)
local function switchRow(canvas, mod, label, rerender)
  local switch = Wd.Checkbox(canvas, label, function(on)
    if on then
      mod:Enable()
    else
      mod:Disable()
    end
    Settings_.PlayCustom()
    rerender()
  end)
  switch:SetChecked(mod:IsSwitchOn())
  return switch
end

-- An app's own window colour and opacity ("an option to colour/transparency
-- each window"): written to the app's profile, nil means the General setting for every window.
local function windowLookRows(canvas, mod)
  local p = mod.db and mod.db.profile
  if not p then
    return {}
  end
  local color = Wd.Color(canvas, L["Window background"], function()
    return p.windowColor
  end, function(value)
    p.windowColor = value
    B.UI.ApplyWindowLook()
  end, S.C.bg)
  local core = ns.core.db.profile
  local alpha = Wd.Slider(canvas, L["Window opacity (%)"], 20, 100, 5, function(v)
    p.windowAlpha = v
    B.UI.ApplyWindowLook()
  end)
  alpha:SetValue(tonumber(p.windowAlpha) or tonumber(core.windowAlpha) or 100, true)
  return { color, alpha }
end

-- ---------------------------------------------------------------------------------------------
-- The page skeleton of every app (plan-launch-review.md O4, 01.11.2026): the sentence and the
-- slash command, What it does, the switch and its buttons, Keys, its options, Works with.
-- ---------------------------------------------------------------------------------------------

Settings_.CORE_KEYS = { "BASTIANS_OMNIBOX", "BASTIANS_HUB", "BASTIANS_CLEAR_SCREEN" }

-- A key binding's words and its key: the name the Bindings.xml global gives, the key the game has
-- (nil when none is set, or the client cannot tell).
function Settings_.KeyRow(action)
  local name = rawget(_G, "BINDING_NAME_" .. action) or action
  return name, B.Compat.BindingKey(action)
end

-- The key bindings of every installed addon of the suite, Core's first: { action, ... }.
function Settings_.AllKeys()
  local out = {}
  for _, action in ipairs(Settings_.CORE_KEYS) do
    out[#out + 1] = action
  end
  for _, app in ipairs(Settings_.Apps()) do
    if app.keys and C_AddOns.DoesAddOnExist(app.addon) then
      for _, action in ipairs(app.keys) do
        out[#out + 1] = action
      end
    end
  end
  return out
end

local function keyRows(canvas, keys)
  local widgets = {}
  if not keys or #keys == 0 then
    return widgets
  end
  widgets[#widgets + 1] = Wd.Header(canvas, L["Keys"])
  for _, action in ipairs(keys) do
    local name, key = Settings_.KeyRow(action)
    widgets[#widgets + 1] =
      Wd.Note(canvas, ("%s: %s"):format(name, key or L["not set"]), key and S.C.text or nil)
  end
  local set = S.action(canvas, { icon = "settings", label = L["Set the keys"], boxed = true, width = 160 })
  set.tip = L["Opens the game's Key Bindings, where every key of Bastian's is set."]
  set:SetScript("OnClick", function()
    B.Compat.OpenKeyBindings()
  end)
  widgets[#widgets + 1] = set
  return widgets
end

-- The state of an app another app links to: on, off, not installed.
local function linkState(module)
  local mod = ns.modules[module]
  if mod then
    return mod:IsEnabled() and L["on"] or L["off"], mod:IsEnabled()
  end
  local app = Settings_.AppByModule(module)
  if app and C_AddOns.DoesAddOnExist(app.addon) then
    return L["off"], false
  end
  return L["not installed"], false
end

local function linkTitle(module)
  local mod = ns.modules[module]
  return "Bastian's " .. (mod and mod.title or module)
end

-- "Works with": the optional addons that are missing, and the suite's apps this app links to,
-- each with its state ("Show on map needs Bastian's Map (on).").
local function worksWithRows(canvas, mod, app)
  local widgets = {}
  local missing = missingOptional(mod)
  local links = app and app.links
  if #missing == 0 and not (links and next(links)) then
    return widgets
  end
  widgets[#widgets + 1] = Wd.Header(canvas, L["Works with"])
  for _, addon in ipairs(missing) do
    local what = companionWhat(addon)
    widgets[#widgets + 1] = Wd.Note(
      canvas,
      what and ("%s %s %s."):format(addon, L["is not installed: it would add"], what)
        or ("%s %s"):format(addon, L["is not installed: the features that need it are off."])
    )
  end
  if links then
    for _, other in ipairs(B.APPS) do
      local what = links[other.module]
      if what then
        local state, on = linkState(other.module)
        widgets[#widgets + 1] = Wd.Note(
          canvas,
          ("%s %s %s (%s)."):format(what, L["needs"], linkTitle(other.module), state),
          on and S.C.text or nil
        )
      end
    end
  end
  return widgets
end

local function moduleRows(canvas, mod, depth)
  local widgets = {}
  local app = depth == 0 and Settings_.AppOf(mod.def.addon)
  if app then
    -- what the app does, in one sentence
    widgets[#widgets + 1] = Wd.Note(canvas, app.about .. (app.slash and ("  " .. app.slash) or ""), S.C.text)
    if app.does then
      widgets[#widgets + 1] = Wd.Header(canvas, L["What it does"])
      for _, line in ipairs(app.does) do
        widgets[#widgets + 1] = Wd.Note(canvas, "- " .. line, S.C.text)
      end
    end
  end
  if not mod.def.noSwitch then
    local switch = Wd.Checkbox(
      canvas,
      depth == 0 and L["Enabled"] or (mod.title .. ": " .. L["enabled"]),
      function(on)
        if on then
          mod:Enable()
        else
          mod:Disable()
        end
        Settings_.Render(canvas, canvas.mod)
      end
    )
    switch:SetChecked(mod:IsSwitchOn())
    widgets[#widgets + 1] = switch
    if mod.disabledByErrors then
      widgets[#widgets + 1] =
        Wd.Note(canvas, L["Disabled for this session after repeated errors. See /bastians log."], S.C.warn)
    end
  end
  if depth == 0 and type(mod.def.open) == "function" then
    widgets[#widgets + 1] = openRow(canvas, mod)
    widgets[#widgets + 1] = minimapRow(canvas, mod)
    for _, w in ipairs(windowLookRows(canvas, mod)) do
      widgets[#widgets + 1] = w
    end
  end
  if app and app.keys then
    for _, w in ipairs(keyRows(canvas, app.keys)) do
      widgets[#widgets + 1] = w
    end
  end
  for _, option in ipairs(mod.options or {}) do
    widgets[#widgets + 1] = widgetFor(canvas, option, mod)
  end
  if depth == 0 and mod == ns.core then
    -- General: the suite's own keys after its options (Profiles stays the first section)
    for _, w in ipairs(keyRows(canvas, Settings_.CORE_KEYS)) do
      widgets[#widgets + 1] = w
    end
  end
  for _, child in ipairs(mod.children) do
    widgets[#widgets + 1] = Wd.Header(canvas, child.title)
    for _, w in ipairs(moduleRows(canvas, child, depth + 1)) do
      widgets[#widgets + 1] = w
    end
  end
  if depth == 0 then
    for _, w in ipairs(worksWithRows(canvas, mod, app)) do
      widgets[#widgets + 1] = w
    end
  else
    for _, addon in ipairs(missingOptional(mod)) do
      local what = companionWhat(addon)
      widgets[#widgets + 1] = Wd.Note(
        canvas,
        what and ("%s %s %s."):format(addon, L["is not installed: it would add"], what)
          or ("%s %s"):format(addon, L["is not installed: the features that need it are off."])
      )
    end
  end
  return widgets
end

-- What this client needs: every part
-- the installed apps need, installed or missing, and who needs it; then the companions of this
-- client with their state. On the Suite page since
-- 30.10.2026 (before: the General page).
local function partsRows(canvas)
  local widgets = {}
  do
    widgets[#widgets + 1] =
      Wd.Header(canvas, string.format(L["Bastian's addons for %s"], Settings_.ClientName()))
    for _, p in ipairs(Settings_.Parts()) do
      local state
      if p.disabled then
        state = L["Switched off in the AddOns list at character select."]
      elseif p.installed then
        state = L["Installed."]
      elseif p.required then
        state = string.format(L["MISSING: install the %s files."], Settings_.ClientName())
      else
        state = L["Not installed (optional)."]
      end
      local who = #p.neededBy > 0 and (" " .. L["Needed by"] .. " " .. table.concat(p.neededBy, ", ") .. ".")
        or ""
      widgets[#widgets + 1] =
        Wd.Note(canvas, ("%s:%s %s"):format(p.addon, who, state), p.installed and S.C.text or nil)
    end
    -- retail has no companions since TomTom left the list (29.10.2026)
    local companions = Settings_.Companions()
    if #companions > 0 then
      widgets[#widgets + 1] =
        Wd.Header(canvas, string.format(L["Optional addons for %s"], Settings_.ClientName()))
    end
    for _, c in ipairs(companions) do
      widgets[#widgets + 1] = Wd.Note(
        canvas,
        ("%s: %s. %s"):format(
          c.addon,
          c.what,
          c.installed and L["Installed."] or (L["Not installed:"] .. " " .. c.url)
        ),
        c.installed and S.C.text or nil
      )
    end
  end
  return widgets
end

-- The Suite page, the first page of the hub and the Blizzard panel's root:
-- what the suite is, the welcome window, every app of this client with its words, its switch,
-- its minimap button and its Open button (or why it is not there), then the parts and companions.
-- ---------------------------------------------------------------------------------------------
-- Play presets: "Bastian's Suite is Azeroth, told in
-- your own way." A play preset says which apps are on, which minimap buttons show, a handful of
-- app settings and what the clear-screen key hides; it is written once (the first-start window,
-- the Suite page), a later change of any switch shows Custom. Nothing is uninstalled: an app
-- switched off keeps its data and comes back with one tick.
-- ---------------------------------------------------------------------------------------------

local SCREEN_GAME = {
  "screenMinimap",
  "screenChat",
  "screenBars",
  "screenUnits",
  "screenBuffs",
  "screenTracker",
  "screenMicro",
  "screenAlerts",
}

local function screenAll(on, except)
  local out = {}
  for _, key in ipairs(SCREEN_GAME) do
    out[key] = on and key ~= except
  end
  return out
end

local function appsOn(off)
  local out = {}
  for _, app in ipairs(B.APPS) do
    if app.module ~= "Data" then
      out[app.module] = not off[app.module]
    end
  end
  return out
end

Settings_.PLAY_PRESETS = {
  {
    id = "wanderer",
    name = L["The Wanderer"],
    about = L["Explore this new world on your own, guided only by the voices of the land: the Orbiter, the chat, the map with a quiet minimap, your gestures. No quest log, no browser, no routes; one key clears the screen."], -- luacheck: ignore 631 (a locale key stays one literal)
    -- "orbiter, chat, maps, minimap with a preset that does not show
    -- anything, especially no quests ... hide everything else, outside the spell bars"
    apps = appsOn({
      Quests = true,
      Browser = true,
      Gold = true,
      Route = true,
      Strategies = true,
      Notes = true,
      Alts = true,
      Helpers = true,
      Library = true,
    }),
    buttons = { Map = true, Voice = true, Chat = true, Gestures = true },
    settings = {
      Map = { minimapPins = false },
      ["Voice.Talk"] = { enabled = true },
      -- the campfire's warmth, its ring and the beacon; the planner is the Scholar's (S5 presets)
      Campfire = { card = true, ring = true, beacon = true, planner = false },
      Core = { wordsReminder = "voice", wordsStep = "voice", wordsArrival = "voice", wordsNotice = "text" },
    },
    screen = screenAll(true, "screenBars"),
  },
  {
    id = "scholar",
    name = L["The Scholar"],
    about = L["Every quest, creature, item and place one click from its page, its spot on the map and the way there: every app on, every minimap button, the tracker wide."], -- luacheck: ignore 631 (a locale key stays one literal)
    apps = appsOn({ Chat = true, Gestures = true, Library = true }),
    buttons = appsOn({ Chat = true, Gestures = true, Library = true }),
    settings = {
      Map = { minimapPins = true },
      ["Voice.Talk"] = { enabled = false },
      Core = { wordsReminder = "text", wordsStep = "text", wordsArrival = "text", wordsNotice = "text" },
      Campfire = { card = true, ring = false, beacon = true, planner = true }, -- a Scholar sits too
    },
    screen = screenAll(false),
  },
  {
    id = "everything",
    name = L["Everything"],
    about = L["Every app on, the Orbiter too; decide later on the Suite page."],
    apps = appsOn({ Library = true }),
    buttons = appsOn({ Library = true }),
    settings = {
      Map = { minimapPins = true },
      ["Voice.Talk"] = { enabled = false },
      Campfire = { card = true, ring = true, beacon = true, planner = true },
    },
    screen = screenAll(false),
  },
}

function Settings_.PlayPreset(id)
  for _, preset in ipairs(Settings_.PLAY_PRESETS) do
    if preset.id == id then
      return preset
    end
  end
  return nil
end

-- The chosen play preset's id, "custom" after a switch was changed by hand, nil before any choice.
function Settings_.PlayId()
  return ns.core.db.profile.play
end

-- Any switch changed by hand after a preset: the Suite page says Custom.
function Settings_.PlayCustom()
  local p = ns.core.db.profile
  if p.play and p.play ~= "custom" then
    p.play = "custom"
  end
end

-- Writes the play preset `id`: the apps' switches (a load-on-demand app through its load switch),
-- the minimap buttons, the settings and the clear-screen ticks; fires BASTIANS_PLAY_CHANGED so
-- the apps draw again. -> true, or false for an unknown id.
function Settings_.ApplyPlay(id)
  local preset = Settings_.PlayPreset(id)
  if not preset then
    return false
  end
  local p = ns.core.db.profile
  local Launcher = B.UI.Launcher
  for _, app in ipairs(Settings_.Apps()) do
    local on = preset.apps[app.module]
    if on ~= nil then
      local mod = ns.modules[app.module]
      if mod then
        if on then
          mod:Enable()
        else
          mod:Disable()
        end
      elseif Settings_.LodApps()[app.addon] then
        Settings_.SetLod(app.addon, on)
      end
      if Launcher and Launcher.SetAppButton then
        Launcher.SetAppButton(app.module, preset.buttons[app.module] and true or false)
      end
    end
  end
  for name, values in pairs(preset.settings) do
    local mod = name == "Core" and ns.core or ns.modules[name]
    if mod and mod.db then
      for key, value in pairs(values) do
        if key == "enabled" then
          if value then
            mod:Enable()
          else
            mod:Disable()
          end
        else
          mod.db.profile[key] = value
        end
      end
    end
  end
  for key, value in pairs(preset.screen) do
    p[key] = value
  end
  p.play = id
  B:Fire("BASTIANS_PLAY_CHANGED", id)
  return true
end

-- The choices of the "Play as" select: the presets and Custom.
function Settings_.PlayChoices()
  local out = { custom = L["Custom"] }
  for _, preset in ipairs(Settings_.PLAY_PRESETS) do
    out[preset.id] = preset.name
  end
  return out
end

-- The story, in the owner's words (01.11.2026): the Suite page, the welcome and the website tell it.
Settings_.STORY =
  L["Bastian's Suite is Azeroth, told in your own way. You might be the Wanderer, who explores this new world on their own, guided only by the voices of the land. Or you might be the Scholar, with every quest, creature, item and place one click from its page, its spot on the map and the way there."] -- luacheck: ignore 631 (a locale key stays one literal)

-- The "Play as" choice with the chosen preset's words (the Suite page, the Help page).
function Settings_.PlayRows(canvas, rerender)
  local widgets = {}
  local play = Wd.Select(canvas, L["Play as"], Settings_.PlayChoices(), function(id)
    if id ~= "custom" then
      Settings_.ApplyPlay(id)
      rerender()
    end
  end)
  play:SetValue(Settings_.PlayId() or "custom")
  play.tip =
    L["The Wanderer: the world, a voice, no windows. The Scholar: every fact at hand. A switch changed by hand shows Custom."] -- luacheck: ignore 631 (a locale key stays one literal)
  widgets[#widgets + 1] = play
  local chosen = Settings_.PlayPreset(Settings_.PlayId())
  if chosen then
    widgets[#widgets + 1] = Wd.Note(canvas, chosen.about)
  end
  return widgets
end

-- The Help page (plan-launch-review.md O5, 01.11.2026; `/bastians help`): the story, the two ways
-- to play, every slash command, every key, how the apps link, where to ask.
function Settings_.HelpRows(canvas)
  local widgets = {}
  local function rerender()
    if B.UI.Hub and B.UI.Hub.win and canvas == B.UI.Hub.canvas then
      B.UI.Hub.Refresh()
    else
      Settings_.RenderHelp(canvas)
    end
  end
  widgets[#widgets + 1] = Wd.Note(canvas, Settings_.STORY, S.C.text)
  widgets[#widgets + 1] = Wd.Header(canvas, L["Two ways to play"])
  for _, preset in ipairs(Settings_.PLAY_PRESETS) do
    widgets[#widgets + 1] = Wd.Note(canvas, preset.name .. ": " .. preset.about, S.C.text)
  end
  for _, w in ipairs(Settings_.PlayRows(canvas, rerender)) do
    widgets[#widgets + 1] = w
  end
  widgets[#widgets + 1] = Wd.Header(canvas, L["Slash commands"])
  widgets[#widgets + 1] =
    Wd.Note(canvas, L["Bastian's: /bastians (the settings), /bs (the search)"], S.C.text)
  for _, app in ipairs(Settings_.Apps()) do
    if app.slash and C_AddOns.DoesAddOnExist(app.addon) then
      local mod = ns.modules[app.module]
      widgets[#widgets + 1] =
        Wd.Note(canvas, (mod and mod.title or app.module) .. ": " .. app.slash, S.C.text)
    end
  end
  for _, w in ipairs(keyRows(canvas, Settings_.AllKeys())) do
    widgets[#widgets + 1] = w
  end
  widgets[#widgets + 1] = Wd.Header(canvas, L["How the apps link"])
  widgets[#widgets + 1] = Wd.Note(
    canvas,
    L["A name on any page opens its page, its place on the map, the way there and its voice in the Orbiter. The apps talk through Core only, so one that is missing or switched off takes away its button and nothing else; every app can be switched off on the Suite page."], -- luacheck: ignore 631 (a locale key stays one literal)
    S.C.text
  )
  widgets[#widgets + 1] = Wd.Header(canvas, L["Where to ask"])
  widgets[#widgets + 1] = Wd.Note(
    canvas,
    L["bastians.dev/wow, the comments on CurseForge, or an issue on GitHub (the link is on the About page). /bastians log shows the last lines for a bug report."], -- luacheck: ignore 631 (a locale key stays one literal)
    S.C.text
  )
  return widgets
end

function Settings_.SuiteRows(canvas)
  local widgets = {}
  local function rerender()
    if B.UI.Hub and B.UI.Hub.win and canvas == B.UI.Hub.canvas then
      B.UI.Hub.Refresh() -- the navigation says (off) too
    else
      Settings_.RenderSuite(canvas)
    end
  end
  widgets[#widgets + 1] = Wd.Note(canvas, Settings_.STORY, S.C.text)
  for _, w in ipairs(Settings_.PlayRows(canvas, rerender)) do
    widgets[#widgets + 1] = w
  end
  local welcome =
    S.action(canvas, { icon = "help", label = L["Show the welcome window"], boxed = true, width = 200 })
  welcome.tip = L["The first-start window with the apps and the guidelines, any time."]
  welcome:SetScript("OnClick", function()
    if B.UI.Welcome then
      B.UI.Welcome.Show()
    end
  end)
  widgets[#widgets + 1] = welcome
  for _, app in ipairs(Settings_.Apps()) do
    local mod = ns.modules[app.module]
    local installed = exists(app.addon)
    local lodTitle = Settings_.LodApps()[app.addon]
    widgets[#widgets + 1] = Wd.Header(canvas, mod and mod.title or app.module)
    widgets[#widgets + 1] = Wd.Note(canvas, app.about .. (app.slash and ("  " .. app.slash) or ""))
    if mod then
      if not mod.def.noSwitch then
        widgets[#widgets + 1] = switchRow(canvas, mod, L["Enabled"], rerender)
      end
      if type(mod.def.open) == "function" then
        widgets[#widgets + 1] = openRow(canvas, mod)
        widgets[#widgets + 1] = minimapRow(canvas, mod)
      end
      if mod.disabledByErrors then
        widgets[#widgets + 1] =
          Wd.Note(canvas, L["Disabled for this session after repeated errors. See /bastians log."], S.C.warn)
      end
    elseif installed and lodTitle then
      -- a load-on-demand app that is not loaded: its load switch (core-contracts §2)
      local switch = Wd.Checkbox(canvas, L["Load this addon"], function(on)
        Settings_.SetLod(app.addon, on)
        rerender()
      end)
      switch:SetChecked(Settings_.IsLodOn(app.addon))
      widgets[#widgets + 1] = switch
    elseif installed then
      widgets[#widgets + 1] =
        Wd.Note(canvas, L["Switched off in the AddOns list at character select."], S.C.warn)
    else
      widgets[#widgets + 1] = Wd.Note(
        canvas,
        string.format(L["Not installed. Install the %s files to add it."], Settings_.ClientName())
      )
    end
  end
  for _, w in ipairs(partsRows(canvas)) do
    widgets[#widgets + 1] = w
  end
  return widgets
end

-- A module's own page of settings (core-contracts §8 `pages`, the
-- minimap on a page of its own): its options only, read and written on the module like its others.
local function pageRows(canvas, mod, page)
  local widgets = {}
  -- a page may build its rows when it shows (`build()`: the screen page lists what is shown now)
  for _, option in ipairs(page.build and page.build() or page.options or {}) do
    widgets[#widgets + 1] = widgetFor(canvas, option, mod)
  end
  return widgets
end

-- The page `id` of a module, or nil.
function Settings_.Page(mod, id)
  for _, page in ipairs(mod and mod.def.pages or {}) do
    if page.id == id then
      return page
    end
  end
  return nil
end

-- Bastians.UI.Settings.Render(canvas, mod[, page]): (re)draws the module's page, or one of its own
-- pages, into canvas.
local function layout(canvas, widgets)
  canvas.widgets = widgets
  local width = (canvas:GetWidth() or 0) - 24
  if width <= 100 then
    width = 400
  end
  local y = 10
  for _, w in ipairs(widgets) do
    w:ClearAllPoints()
    w:SetPoint("TOPLEFT", canvas, "TOPLEFT", 12, -y)
    w:SetWidth(width)
    w:Show()
    y = y + (w:GetHeight() or 22) + GAP
  end
  canvas.contentHeight = y
  if canvas.onRendered then
    canvas.onRendered(y)
  end
  return y
end

function Settings_.Render(canvas, mod, page)
  for _, w in ipairs(canvas.widgets or {}) do
    w:Hide()
  end
  canvas.mod = mod
  canvas.page = page
  canvas.suite = nil
  canvas.help = nil
  return layout(canvas, page and pageRows(canvas, mod, page) or moduleRows(canvas, mod, 0))
end

-- Bastians.UI.Settings.RenderSuite(canvas): the Suite page.
function Settings_.RenderSuite(canvas)
  for _, w in ipairs(canvas.widgets or {}) do
    w:Hide()
  end
  canvas.mod = nil
  canvas.page = nil
  canvas.suite = true
  canvas.help = nil
  return layout(canvas, Settings_.SuiteRows(canvas))
end

-- Bastians.UI.Settings.RenderHelp(canvas): the Help page (O5).
function Settings_.RenderHelp(canvas)
  for _, w in ipairs(canvas.widgets or {}) do
    w:Hide()
  end
  canvas.mod = nil
  canvas.page = nil
  canvas.suite = nil
  canvas.help = true
  return layout(canvas, Settings_.HelpRows(canvas))
end

-- ---------------------------------------------------------------------------------------------
-- Blizzard panel: the parent "Bastians" shows the Suite page; one child per top-level module
-- (General for Core, sub-modules as sections) and one per page a module declares (`pages`)
-- ---------------------------------------------------------------------------------------------

local panels = {} -- "Suite", a module name, or "name:page" for a page -> { canvas, category }
local parentCategory

-- A panel of the game's settings window that scrolls (a long page ran
-- off the bottom and its last switch could not be clicked): the frame the game gets holds a
-- scroll frame, the canvas the renderer draws on is its child and grows with the rows.
local function scrollingCanvas(render)
  local outer = CreateFrame("Frame", nil, UIParent)
  outer:SetSize(600, 500)
  outer:Hide()
  local scroll = CreateFrame("ScrollFrame", nil, outer)
  scroll:SetPoint("TOPLEFT", 0, 0)
  scroll:SetPoint("BOTTOMRIGHT", -14, 0)
  local canvas = CreateFrame("Frame", nil, scroll)
  canvas:SetSize(560, 1)
  scroll:SetScrollChild(canvas)
  local bar = S.scrollbar(scroll, outer)
  canvas.onRendered = function(height)
    canvas:SetHeight(math.max(1, height))
    bar.SetTotal(height)
  end
  canvas:Hide()
  canvas:SetScript("OnShow", function(self) -- shown with its panel (and on its own, in the tests)
    render(self)
  end)
  outer:SetScript("OnShow", function()
    canvas:Show()
  end)
  outer:SetScript("OnHide", function()
    canvas:Hide()
  end)
  outer:SetScript("OnSizeChanged", function(self, w)
    canvas:SetWidth(math.max(100, (w or 600) - 14))
    if self:IsShown() then
      render(canvas)
    end
  end)
  return canvas, outer
end

local function suitePanel()
  if parentCategory then
    return
  end
  local canvas, outer = scrollingCanvas(function(self)
    Settings_.RenderSuite(self)
  end)
  parentCategory = B.Compat.RegisterSettingsCategory(outer, "Bastians")
  panels.Suite = { canvas = canvas, category = parentCategory }
end

local function panelFor(mod)
  if panels[mod.name] or mod.parent then
    return
  end
  suitePanel()
  local canvas, outer = scrollingCanvas(function(self)
    Settings_.Render(self, mod)
  end)
  local category = B.Compat.RegisterSettingsCategory(outer, mod.title, parentCategory)
  panels[mod.name] = { canvas = canvas, category = category }
  for _, page in ipairs(mod.def.pages or {}) do
    local pageCanvas, pageOuter = scrollingCanvas(function(self)
      Settings_.Render(self, mod, page)
    end)
    panels[mod.name .. ":" .. page.id] = {
      canvas = pageCanvas,
      category = B.Compat.RegisterSettingsCategory(pageOuter, page.title, parentCategory),
    }
  end
end

function Settings_.Panels()
  return panels
end

function Settings_.Open(mod, pageID)
  local p = mod and (pageID and panels[mod.name .. ":" .. pageID] or panels[mod.name]) or panels.Suite
  if p then
    B.Compat.OpenSettings(p.category)
  end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_LOGIN")
  scanLodApps()
  loadLodApps()
  -- the game's options list keeps the order of registration: by title (
  -- "sorted alphabetically"), General among the apps
  local mods = { ns.core }
  for _, mod in B:IterateModules() do
    if mod ~= ns.core then
      mods[#mods + 1] = mod
    end
  end
  table.sort(mods, function(a, b)
    return string.lower(tostring(a.title)) < string.lower(tostring(b.title))
  end)
  for _, mod in ipairs(mods) do
    panelFor(mod)
  end
end)
ns.on("BASTIANS_MODULE_STATE", function(_, _, name, enabled)
  local mod = enabled and ns.modules[name]
  if mod and ns.loggedIn then
    panelFor(mod)
  end
end)
