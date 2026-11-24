-- The /bastians hub (core-contracts §17): a window with the modules on the left and the selected
-- module's settings page on the right, drawn by the same renderer as the Blizzard panel.
local _, ns = ...
local B = ns.B
local L = ns.L
local S = ns.Style
local Settings_ = B.UI.Settings

local Hub = {}
B.UI.Hub = Hub

local NAV_W = 200 -- the rail: the app's icon, its name and its sentence (ADR 0058, PH7)
local ROW_H, ROW_TALL = 24, 40 -- a plain row; a row with a sentence under its name
local NAV_MARGIN = 8 -- a row's words end here, left of the rail's scroll bar
local NAV_PAD = 6 -- over the first row and under the last
local win, rail, nav, navScroll, navBar, canvas, scroll, bar
local navButtons = {}

-- The hub wears the suite's one look, the tall head and the theme (ADR 0084, W5; ~~always the
-- WoW look: the game's frame and insets and the gold scheme as a fixed palette~~ from
-- 31.10.2026 to 23.11.2026, when the looks it had to stay readable against were gone).

-- The menu's entries: the Suite page, General, the apps by name (each with its icon and its own
-- pages indented under it: Map > Minimap, General > Hidden by the key; plan-launch-review O3,
-- 01.11.2026), the load-on-demand apps, Help, What's new, About.
local function entries()
  -- the Suite page first: every app with its switch, then General
  -- every row carries a pictogram ("some option sections do not have an
  -- icon but should have"): the apps their own, the others a kind of the icon table
  local list = {
    { suite = true, title = L["Bastian's Suite"], icon = B.UI.IconTexture(B.UI.SUITE_ICON) },
    { mod = ns.core, title = ns.core.title },
  }
  for _, mod in B:IterateModules() do
    if not mod.parent and mod ~= ns.core then
      list[#list + 1] = { mod = mod, title = mod.title }
    end
  end
  for addon, title in pairs(Settings_.LodApps()) do
    if not ns.byAddon[addon] then
      list[#list + 1] = { lod = addon, title = title }
    end
  end
  local function rank(e)
    return e.suite and 0 or (e.mod == ns.core) and 1 or 2
  end
  table.sort(list, function(a, b)
    if rank(a) ~= rank(b) then
      return rank(a) < rank(b)
    end
    return a.title < b.title
  end)
  -- a module's own pages (core-contracts §8 `pages`) under their owner, indented
  local out = {}
  for _, entry in ipairs(list) do
    out[#out + 1] = entry
    if entry.mod then
      local app = Settings_.AppByModule(entry.mod.name)
      entry.icon = B.UI.AppIcon(entry.mod.name) or B.UI.IconTexture(entry.mod.def.icon or "settings")
      entry.tip = app and app.about or nil
      for _, page in ipairs(entry.mod.def.pages or {}) do
        out[#out + 1] = {
          mod = entry.mod,
          page = page,
          title = page.title,
          indent = true,
          icon = page.icon and B.UI.IconTexture(page.icon) or nil, -- a page's own kind (core-contracts §8)
        }
      end
    end
  end
  out[#out + 1] = {
    help = true,
    title = L["Help"],
    icon = B.UI.IconTexture("help"),
    tip = L["The story, the two ways to play, every command and key."],
  }
  local unseen = B.UI.News and B.UI.News.Unseen() or 0
  local news = L["What's new"] .. (unseen > 0 and (" (" .. unseen .. ")") or "")
  out[#out + 1] = { news = true, title = news, icon = B.UI.IconTexture("note") } -- before About (ADR 0021)
  -- always last (core.md "About page")
  out[#out + 1] = { about = true, title = L["About"], icon = B.UI.IconTexture(B.UI.SUITE_ICON) }
  return out
end

local function renderLod(entry)
  for _, w in ipairs(canvas.widgets or {}) do
    w:Hide()
  end
  local switch = B.UI.Widgets.Checkbox(
    canvas,
    L["Load this addon"] .. " (" .. entry.title .. ")",
    function(on)
      Settings_.SetLod(entry.lod, on)
      Hub.Refresh()
    end
  )
  switch:SetChecked(Settings_.IsLodOn(entry.lod))
  switch:SetPoint("TOPLEFT", canvas, "TOPLEFT", 12, -10)
  switch:SetWidth((canvas:GetWidth() or 400) - 24)
  local note = B.UI.Widgets.Note(
    canvas,
    L["Load-on-demand addons load at login when switched on; turning one off applies at the next /reload."]
  )
  note:SetPoint("TOPLEFT", switch, "BOTTOMLEFT", 0, -6)
  note:SetWidth((canvas:GetWidth() or 400) - 24)
  canvas.widgets = { switch, note }
  canvas.mod = nil
  canvas.contentHeight = 80
  bar.SetTotal(80)
end

local function selectEntry(entry)
  Hub.current = entry
  for _, b in ipairs(navButtons) do
    local on = b.entry
      and (
        (entry.mod and b.entry.mod == entry.mod and b.entry.page == entry.page)
        or (entry.lod and b.entry.lod == entry.lod)
        or (entry.about and b.entry.about)
        or (entry.news and b.entry.news)
        or (entry.help and b.entry.help)
        or (entry.suite and b.entry.suite)
      )
    S.ink(b.label, on and S.C.accent or S.C.text)
    b.line:SetShown(on and true or false)
    b.on:SetShown(on and true or false)
  end
  if entry.mod then
    Settings_.Render(canvas, entry.mod, entry.page)
  elseif entry.suite then
    Settings_.RenderSuite(canvas)
  elseif entry.about then
    B.UI.About.Render(canvas)
  elseif entry.news then
    B.UI.News.Render(canvas)
  elseif entry.help then
    Settings_.RenderHelp(canvas)
  else
    renderLod(entry)
  end
end

local function select(entry)
  selectEntry(entry)
end

local function build()
  win = B.UI.Window("BastiansHubFrame", {
    title = L["Bastian's"] .. " " .. B.VERSION,
    head = "tall",
    width = 620,
    height = 520,
    db = ns.core.db.profile.hub,
    onResize = function()
      Hub.Refresh()
    end,
  })
  -- the rail on the band's ground, a rule between it and the page (the suite's board)
  rail = CreateFrame("Frame", nil, win.content)
  rail:SetPoint("TOPLEFT", 0, 0)
  rail:SetPoint("BOTTOMLEFT", 0, 0)
  rail:SetWidth(NAV_W)
  rail.bg = S.fill(rail, S.C.panel)
  rail.rule = S.fill(rail, S.C.line, "BORDER")
  rail.rule:ClearAllPoints()
  rail.rule:SetPoint("TOPRIGHT", rail, "TOPRIGHT", 0, 0)
  rail.rule:SetPoint("BOTTOMRIGHT", rail, "BOTTOMRIGHT", 0, 0)
  rail.rule:SetWidth(1)
  -- the rows scroll where the window is lower than the list: 22 rows are 790 units, and in a
  -- window 728 high the last four stood under its foot (the windows probe, Forever 23.11.2026)
  navScroll = CreateFrame("ScrollFrame", nil, rail)
  navScroll:SetPoint("TOPLEFT", 0, 0)
  navScroll:SetPoint("BOTTOMRIGHT", -1, 0)
  nav = CreateFrame("Frame", nil, navScroll)
  nav:SetSize(NAV_W - 1, 1)
  navScroll:SetScrollChild(nav)
  navBar = S.scrollbar(navScroll, rail)
  navBar:ClearAllPoints() -- inside the rail's right edge, over the rows' margin
  navBar:SetPoint("TOPRIGHT", rail, "TOPRIGHT", -2, -2)
  navBar:SetPoint("BOTTOMRIGHT", rail, "BOTTOMRIGHT", -2, 2)
  local page = CreateFrame("Frame", nil, win.content)
  page:SetPoint("TOPLEFT", rail, "TOPRIGHT", 4, 0)
  page:SetPoint("BOTTOMRIGHT", 0, 0)
  Hub.page = page
  scroll = CreateFrame("ScrollFrame", nil, win.content)
  scroll:SetPoint("TOPLEFT", rail, "TOPRIGHT", 4, -2)
  scroll:SetPoint("BOTTOMRIGHT", -14, 2)
  canvas = CreateFrame("Frame", nil, scroll)
  canvas:SetSize(440, 1)
  scroll:SetScrollChild(canvas)
  bar = S.scrollbar(scroll, win.content)
  canvas.onRendered = function(height)
    canvas:SetHeight(math.max(1, height))
    bar.SetTotal(height)
  end
  Hub.win, Hub.nav, Hub.canvas, Hub.navButtons = win, nav, canvas, navButtons
  Hub.rail, Hub.navScroll, Hub.navBar = rail, navScroll, navBar
end

-- A row of the rail (ADR 0058, PH7): the icon, the name, and under it the app's one sentence
-- (`entry.tip`) where there is one; a page of an app sits indented under it on a plain row.
-- `y` is where the row starts; the row's height comes back.
local function navButton(i, entry, y)
  local b = navButtons[i]
  if not b then
    b = CreateFrame("Button", nil, nav)
    b:SetHeight(ROW_H)
    b:SetPoint("LEFT", 0, 0)
    b:SetPoint("RIGHT", 0, 0)
    b.hl = S.fill(b, S.C.hover, "ARTWORK")
    b.hl:Hide()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(14, 14)
    b.icon:SetPoint("LEFT", 8, 0)
    b.label = S.text(b, 12)
    b.label:SetPoint("LEFT", 10, 0)
    b.label:SetPoint("RIGHT", -NAV_MARGIN, 0)
    b.label:SetWordWrap(false)
    b.sub = S.text(b, 10, S.C.dim)
    b.sub:SetWordWrap(false)
    b.sub:Hide()
    b.on = S.fill(b, S.C.accent, "BORDER") -- the chosen row's faint plate (the board: 10 %)
    b.on:SetAlpha(0.1)
    b.on:Hide()
    b.line = S.fill(b, S.C.accent, "OVERLAY")
    b.line:ClearAllPoints()
    b.line:SetPoint("TOPLEFT", 0, 0)
    b.line:SetPoint("BOTTOMLEFT", 0, 0)
    b.line:SetWidth(2)
    b.line:Hide()
    b:SetScript("OnEnter", function(self)
      self.hl:Show()
      S.TipEnter(self)
    end)
    b:SetScript("OnLeave", function(self)
      self.hl:Hide()
      S.TipLeave(self)
    end)
    b:SetScript("OnClick", function(self)
      select(self.entry)
    end)
    navButtons[i] = b
  end
  b.entry = entry
  b.tip = entry.tip
  -- the app's one icon before its name (B.UI.AppIcon); a page sits indented under its owner
  if entry.icon then
    B.UI.PaintIcon(b.icon, entry.icon)
    b.icon:Show()
  else
    b.icon:Hide()
  end
  local tall = entry.tip ~= nil and not entry.indent
  local height = tall and ROW_TALL or ROW_H
  local left = entry.icon and (tall and 34 or 26) or (entry.indent and 26 or 10)
  b.icon:SetSize(tall and 20 or 14, tall and 20 or 14)
  b.label:ClearAllPoints()
  b.sub:ClearAllPoints()
  if tall then
    b.label:SetPoint("TOPLEFT", left, -6)
    b.label:SetPoint("RIGHT", -NAV_MARGIN, 0)
    b.sub:SetPoint("TOPLEFT", left, -21)
    b.sub:SetPoint("RIGHT", -NAV_MARGIN, 0)
    b.sub:SetText(entry.tip)
    b.sub:Show()
  else
    b.label:SetPoint("LEFT", left, 0)
    b.label:SetPoint("RIGHT", -NAV_MARGIN, 0)
    b.sub:Hide()
  end
  local off = entry.mod and entry.mod.state ~= "enabled" and not entry.mod.def.noSwitch
  b.label:SetText(entry.title .. (off and (" " .. S.H.muted .. "(" .. L["off"] .. ")|r") or ""))
  b:SetHeight(height)
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", 0, -y)
  b:SetPoint("RIGHT", 0, 0)
  b.top = y -- where the row starts in the list (Hub.ShowChosenRow)
  b:Show()
  return height
end

function Hub.Refresh()
  if not win then
    return
  end
  canvas:SetWidth(math.max(100, (scroll:GetWidth() or 440)))
  local list = entries()
  local y = NAV_PAD
  for i, entry in ipairs(list) do
    y = y + navButton(i, entry, y)
  end
  for i = #list + 1, #navButtons do
    navButtons[i]:Hide()
  end
  nav:SetHeight(y + NAV_PAD)
  navBar.SetTotal(y + NAV_PAD)
  navBar:SetAlpha(navBar.thumb:IsShown() and 1 or 0) -- no track beside a list that fits
  local current = Hub.current or list[1]
  selectEntry(current)
  Hub.ShowChosenRow()
end

-- The chosen row inside the rail's view (the hub opened on an app far down the list).
function Hub.ShowChosenRow()
  local view = navScroll:GetHeight() or 0
  local off = navScroll:GetVerticalScroll() or 0
  for _, b in ipairs(navButtons) do
    if b:IsShown() and b.line:IsShown() then
      local top = b.top or 0
      local bottom = top + (b:GetHeight() or 0)
      if top - NAV_PAD < off then
        navBar.ScrollTo(top - NAV_PAD)
      elseif view > 0 and bottom + NAV_PAD > off + view then
        navBar.ScrollTo(bottom + NAV_PAD - view)
      end
      return
    end
  end
end

-- Hub.Open([moduleName[, pageID]]): the module's page, or one of its own pages.
function Hub.Open(moduleName, pageID)
  if not win then
    build()
  end
  if moduleName == "about" then
    Hub.current = { about = true, title = L["About"] }
  elseif moduleName == "suite" then
    Hub.current = { suite = true, title = L["Bastian's Suite"] }
  elseif moduleName == "news" then
    Hub.current = { news = true, title = L["What's new"] }
  elseif moduleName == "help" then
    Hub.current = { help = true, title = L["Help"] }
  elseif moduleName then
    local mod = ns.modules[moduleName]
    local page = Settings_.Page(mod, pageID)
    if page then
      Hub.current = { mod = mod, page = page, title = page.title }
    elseif mod then
      Hub.current = { mod = mod, title = mod.title }
    end
  end
  win:Show()
  Hub.Refresh()
end

function Hub.Toggle()
  if win and win:IsShown() then
    win:Hide()
  else
    Hub.Open()
  end
end

-- Whether the hub shows the module's page now.
function Hub.Shows(moduleName)
  local mod = ns.modules[moduleName]
  return mod ~= nil and win ~= nil and win:IsShown() and Hub.current ~= nil and Hub.current.mod == mod
end

-- The module's page, or the hub closed when it shows that page already (an app's minimap button
-- whose window is its page: a second click closes it, ); true when shown.
function Hub.TogglePage(moduleName)
  if Hub.Shows(moduleName) then
    win:Hide()
    return false
  end
  Hub.Open(moduleName)
  return true
end

-- /bastians [hub | suite | help | news | about | addons | welcome | log [n] | debug | profile <name> | perf]
Hub.USAGE =
  L["/bastians: hub | suite | help | news | about | addons | welcome | log [n] | debug | profile [name] | perf"] -- luacheck: ignore 631 (a locale key stays one literal)
SLASH_BASTIANS1 = "/bastians"
SlashCmdList.BASTIANS = function(msg)
  local cmd, arg = string.match(msg or "", "^%s*(%S*)%s*(.-)%s*$")
  cmd = string.lower(cmd or "")
  if cmd == "" or cmd == "hub" then
    Hub.Toggle()
  elseif cmd == "help" then
    Hub.Open("help") -- the Help page (plan-launch-review O5)
  elseif cmd == "about" then
    Hub.Open("about")
  elseif cmd == "suite" then
    Hub.Open("suite") -- the Suite page
  elseif cmd == "welcome" then
    if B.UI.Welcome then
      B.UI.Welcome.Show() -- the first-start window, any time
    end
  elseif cmd == "news" then
    Hub.Open("news") -- What's new (ADR 0021)
  elseif cmd == "log" then
    B:PrintLog(tonumber(arg) or 20)
  elseif cmd == "debug" then
    B.debug = not B.debug
    ns.core.db.global.debug = B.debug
    B:Say(B.debug and L["Verbose logging on."] or L["Verbose logging off."])
  elseif cmd == "profile" then
    if arg == "" then
      B:Say(L["Profile: %s. Profiles: %s"], B:GetProfile(), table.concat(B:GetProfiles(), ", "))
    else
      B:SetProfile(arg)
      B:Say(L["Profile: %s"], B:GetProfile())
    end
  elseif cmd == "perf" and B.Perf then
    B.Perf.Print()
  elseif cmd == "addons" then
    B.UI.Settings.PrintAddons() -- what this client needs and the optional addons (ADR 0015)
  else
    B:Say(Hub.USAGE)
  end
end
