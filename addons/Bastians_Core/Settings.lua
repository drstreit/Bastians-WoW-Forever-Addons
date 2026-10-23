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
B.COMPANIONS = {
  {
    addon = "TomTom",
    what = L["a waypoint arrow: pins and places can be sent to it"],
    url = "https://www.curseforge.com/wow/addons/tomtom",
    clients = { "forever", "retail" },
  },
  {
    addon = "QuestieDB",
    what = L["a second source of NPC and object spawns where our data has none"],
    url = "https://www.curseforge.com/wow/addons/questie",
    clients = { "forever" },
  },
  {
    addon = "Spoken",
    what = L["voiced quest texts: Quests hands it the quest you look at"],
    url = "https://www.curseforge.com/wow/addons/spoken-quests",
    clients = { "forever" },
  },
}

-- The data packs by the pack name the apps declare in `data` (core-contracts §11; Data loads them).
-- Market and Nav are optional: built only when their source exists, no app fails without them.
B.PACK_ADDONS = {
  quests = "Bastians_Data_Quests",
  world = "Bastians_Data_World",
  items = "Bastians_Data_Items",
  text = "Bastians_Data_Text_enUS",
  market = "Bastians_Data_Market",
  nav = "Bastians_Data_Nav",
  book = "Bastians_Data_Strategies", -- the Strategies book (strategies-design.md section 6)
}
B.OPTIONAL_PACKS = { market = true, nav = true, book = true }

-- Every released folder of the suite (the probe is never released): the fingerprint of an update.
B.SUITE_ADDONS = {
  "Bastians_Core",
  "Bastians_Data",
  "Bastians_Data_Quests",
  "Bastians_Data_World",
  "Bastians_Data_Items",
  "Bastians_Data_Text_enUS",
  "Bastians_Data_Market",
  "Bastians_Data_Strategies",
  "Bastians_Map",
  "Bastians_Map_Art",
  "Bastians_Quests",
  "Bastians_Browser",
  "Bastians_Gold",
  "Bastians_Route",
  "Bastians_Strategies",
}

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
-- update of any of Bastian's addons, not only Core's.
function Settings_.Fingerprint()
  local parts = { B.Client }
  for _, addon in ipairs(B.SUITE_ADDONS) do
    if exists(addon) then
      parts[#parts + 1] = addon .. "=" .. tostring(C_AddOns.GetAddOnMetadata(addon, "Version") or "?")
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

local function profileValues()
  local values = {}
  for _, name in ipairs(B:GetProfiles()) do
    values[name] = name
  end
  return values
end

ns.core = B:NewModule("Core", {
  addon = ns.ADDON,
  title = L["General"],
  apiVersion = 1,
  noSwitch = true, -- Core cannot be disabled
  db = "BastiansCoreDB",
  charDb = "BastiansCoreCharDB",
  defaults = {
    profile = {
      tooltipLines = 6, -- 3 before the guide gaps (23.10.2026): target of, drops, givers
      tips = true, -- a tip on every button after the hover delay
      fontScale = 100, -- the text size in percent
      tipDelay = 1, -- seconds
      font = S.DEFAULT_FONT,
      theme = "teal", -- the colour scheme (ST3, ADR 0017)
      lod = {},
      minimap = { hide = false, angle = 200 },
      hub = {},
      omnibox = {},
      omniboxTree = {},
    },
    global = { debug = false, perf = {} },
  },
  options = {
    { type = "header", label = L["Profiles"] },
    {
      type = "select",
      key = "profile",
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
      label = L["New profile (press Enter)"],
      set = function(name)
        if name ~= "" then
          B:SetProfile(name)
        end
      end,
    },
    { type = "header", label = L["Display"] },
    {
      type = "select",
      key = "theme",
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
      type = "toggle",
      key = "minimapHide",
      label = L["Hide the minimap button"],
      get = function(mod)
        return mod.db.profile.minimap.hide
      end,
      set = function(on, mod)
        mod.db.profile.minimap.hide = on and true or false
      end,
    },
    { type = "range", key = "tooltipLines", label = L["Extra tooltip lines"], min = 0, max = 10, step = 1 },
    { type = "toggle", key = "tips", label = L["Explain buttons when the mouse rests on them"] },
    {
      type = "range",
      key = "tipDelay",
      label = L["Seconds before a button's explanation shows"],
      min = 0,
      max = 3,
      step = 0.5,
    },
    {
      type = "select",
      key = "font",
      label = L["Font"],
      values = function()
        return Settings_.FontChoices()
      end,
      set = function()
        S.applyFont()
      end,
    },
    {
      type = "range",
      key = "fontScale",
      label = L["Text size (percent)"],
      min = 80,
      max = 130,
      step = 5,
      set = function()
        S.applyFont()
      end,
    },
    { type = "header", label = L["Diagnostics"] },
    {
      type = "toggle",
      key = "debug",
      scope = "global",
      label = L["Verbose logging to chat"],
      set = function(on)
        B.debug = on and true or false
      end,
    },
    {
      type = "execute",
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
    self:On("BASTIANS_THEME_CHANGED", function() -- the hub shows the new scheme at once (ST3)
      if B.UI.Hub then
        B.UI.Hub.Refresh()
      end
    end)
    self:On("BASTIANS_PROFILE_CHANGED", function(me)
      S.ApplyTheme(me.db.profile.theme) -- each profile keeps its own scheme
      S.applyFont()
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

local function widgetFor(canvas, option, mod)
  local kind = option.type
  if kind == "header" then
    return Wd.Header(canvas, option.label)
  elseif kind == "toggle" then
    local w = Wd.Checkbox(canvas, option.label, function(on)
      setValue(mod, option, on)
    end)
    w:SetChecked(getValue(mod, option) and true or false)
    return w
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
    return w
  elseif kind == "select" or kind == "font" then
    local values = option.values or FONTS
    if type(values) == "function" then
      values = values(mod)
    end
    local w = Wd.Select(canvas, option.label, values, function(key)
      setValue(mod, option, key)
    end)
    w:SetValue(getValue(mod, option))
    return w
  elseif kind == "execute" then
    local w = S.button(canvas, option.label, 160, 20)
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
    return w
  elseif kind == "color" then
    return Wd.Note(canvas, option.label .. ": " .. L["colour picker comes later"])
  end
  return Wd.Note(canvas, ("unknown option type %s"):format(tostring(kind)), S.C.warn)
end

local function moduleRows(canvas, mod, depth)
  local widgets = {}
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
    -- the app's window from the hub, so nobody needs its slash command
    local row = CreateFrame("Frame", nil, canvas)
    row:SetHeight(24)
    row.button = S.button(row, L["Open %s"]:format(mod.title), 160, 22)
    row.button.tip = L["Opens the window of this app."]
    row.button:SetPoint("LEFT", 0, 0)
    row.button:SetScript("OnClick", function()
      if mod:IsEnabled() then
        mod.def.open()
      else
        B:Say(L["%s is switched off."], mod.title)
      end
    end)
    widgets[#widgets + 1] = row
    -- its own minimap button, on by default
    local mm = Wd.Checkbox(canvas, L["Its own minimap button"], function(on)
      B.UI.Launcher.SetAppButton(mod.name, on)
    end)
    mm:SetChecked(not B.UI.Launcher.AppSettings(mod.name).hide)
    widgets[#widgets + 1] = mm
  end
  for _, addon in ipairs(missingOptional(mod)) do
    local what = companionWhat(addon)
    widgets[#widgets + 1] = Wd.Note(
      canvas,
      what and ("%s %s %s."):format(addon, L["is not installed: it would add"], what)
        or ("%s %s"):format(addon, L["is not installed: the features that need it are off."])
    )
  end
  for _, option in ipairs(mod.options or {}) do
    widgets[#widgets + 1] = widgetFor(canvas, option, mod)
  end
  for _, child in ipairs(mod.children) do
    widgets[#widgets + 1] = Wd.Header(canvas, child.title)
    for _, w in ipairs(moduleRows(canvas, child, depth + 1)) do
      widgets[#widgets + 1] = w
    end
  end
  if mod == ns.core and depth == 0 then
    -- what this client needs: every part
    -- the installed apps need, installed or missing, and who needs it
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
    -- the companions of this client with their state
    widgets[#widgets + 1] =
      Wd.Header(canvas, string.format(L["Optional addons for %s"], Settings_.ClientName()))
    for _, c in ipairs(Settings_.Companions()) do
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

-- Bastians.UI.Settings.Render(canvas, mod): (re)draws the module's page into canvas.
function Settings_.Render(canvas, mod)
  for _, w in ipairs(canvas.widgets or {}) do
    w:Hide()
  end
  canvas.mod = mod
  local widgets = moduleRows(canvas, mod, 0)
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

-- ---------------------------------------------------------------------------------------------
-- Blizzard panel: one parent "Bastians", one child per top-level module (sub-modules as sections)
-- ---------------------------------------------------------------------------------------------

local panels = {} -- module name -> { canvas, category }
local parentCategory

local function panelFor(mod)
  if panels[mod.name] or mod.parent then
    return
  end
  local canvas = CreateFrame("Frame", nil, UIParent)
  canvas:SetSize(600, 500)
  canvas:Hide()
  canvas:SetScript("OnShow", function(self)
    Settings_.Render(self, mod)
  end)
  local category
  if not parentCategory then
    parentCategory = B.Compat.RegisterSettingsCategory(canvas, "Bastians")
    category = parentCategory
    mod.isRootPanel = true
  else
    category = B.Compat.RegisterSettingsCategory(canvas, mod.title, parentCategory)
  end
  panels[mod.name] = { canvas = canvas, category = category }
end

function Settings_.Panels()
  return panels
end

function Settings_.Open(mod)
  local p = mod and panels[mod.name] or panels["Core"]
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
  panelFor(ns.core)
  for _, mod in B:IterateModules() do
    panelFor(mod)
  end
end)
ns.on("BASTIANS_MODULE_STATE", function(_, _, name, enabled)
  local mod = enabled and ns.modules[name]
  if mod and ns.loggedIn then
    panelFor(mod)
  end
end)
