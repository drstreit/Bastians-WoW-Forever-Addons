-- The /bastians hub (core-contracts §17): a window with the modules on the left and the selected
-- module's settings page on the right, drawn by the same renderer as the Blizzard panel.
local _, ns = ...
local B = ns.B
local L = ns.L
local S = ns.Style
local Settings_ = B.UI.Settings

local Hub = {}
B.UI.Hub = Hub

local NAV_W = 150
local win, nav, canvas, scroll, bar
local navButtons = {}

local function entries()
  local list = { { mod = ns.core, title = ns.core.title } }
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
  table.sort(list, function(a, b)
    if a.mod == ns.core then
      return true
    elseif b.mod == ns.core then
      return false
    end
    return a.title < b.title
  end)
  local unseen = B.UI.News and B.UI.News.Unseen() or 0
  local news = L["What's new"] .. (unseen > 0 and (" (" .. unseen .. ")") or "")
  list[#list + 1] = { news = true, title = news } -- before About (ADR 0021)
  list[#list + 1] = { about = true, title = L["About"] } -- always last (core.md "About page")
  return list
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

local function select(entry)
  Hub.current = entry
  for _, b in ipairs(navButtons) do
    local on = b.entry
      and (
        (entry.mod and b.entry.mod == entry.mod)
        or (entry.lod and b.entry.lod == entry.lod)
        or (entry.about and b.entry.about)
        or (entry.news and b.entry.news)
      )
    local c = on and S.C.accent or S.C.text
    b.label:SetTextColor(c[1], c[2], c[3])
    if on then
      b.line:Show()
    else
      b.line:Hide()
    end
  end
  if entry.mod then
    Settings_.Render(canvas, entry.mod)
  elseif entry.about then
    B.UI.About.Render(canvas)
  elseif entry.news then
    B.UI.News.Render(canvas)
  else
    renderLod(entry)
  end
end

local function build()
  win = B.UI.Window("BastiansHubFrame", {
    title = L["Bastian's"] .. " " .. B.VERSION,
    width = 620,
    height = 520,
    db = ns.core.db.profile.hub,
    onResize = function()
      Hub.Refresh()
    end,
  })
  nav = CreateFrame("Frame", nil, win.content)
  nav:SetPoint("TOPLEFT", 0, 0)
  nav:SetPoint("BOTTOMLEFT", 0, 0)
  nav:SetWidth(NAV_W)
  S.fill(nav, S.C.header)
  scroll = CreateFrame("ScrollFrame", nil, win.content)
  scroll:SetPoint("TOPLEFT", nav, "TOPRIGHT", 0, 0)
  scroll:SetPoint("BOTTOMRIGHT", -14, 0)
  canvas = CreateFrame("Frame", nil, scroll)
  canvas:SetSize(440, 1)
  scroll:SetScrollChild(canvas)
  bar = S.scrollbar(scroll, win.content)
  canvas.onRendered = function(height)
    canvas:SetHeight(math.max(1, height))
    bar.SetTotal(height)
  end
  Hub.win, Hub.nav, Hub.canvas = win, nav, canvas
end

local function navButton(i, entry)
  local b = navButtons[i]
  if not b then
    b = CreateFrame("Button", nil, nav)
    b:SetHeight(24)
    b:SetPoint("LEFT", 0, 0)
    b:SetPoint("RIGHT", 0, 0)
    b.hl = S.fill(b, S.C.hover, "ARTWORK")
    b.hl:Hide()
    b.label = S.text(b, 12)
    b.label:SetPoint("LEFT", 10, 0)
    b.label:SetPoint("RIGHT", -4, 0)
    b.line = S.fill(b, S.C.accent, "OVERLAY")
    b.line:ClearAllPoints()
    b.line:SetPoint("TOPLEFT", 0, 0)
    b.line:SetPoint("BOTTOMLEFT", 0, 0)
    b.line:SetWidth(2)
    b.line:Hide()
    b:SetScript("OnEnter", function(self)
      self.hl:Show()
    end)
    b:SetScript("OnLeave", function(self)
      self.hl:Hide()
    end)
    b:SetScript("OnClick", function(self)
      select(self.entry)
    end)
    navButtons[i] = b
  end
  b.entry = entry
  local off = entry.mod and entry.mod.state ~= "enabled" and not entry.mod.def.noSwitch
  b.label:SetText(entry.title .. (off and (" " .. S.H.muted .. "(" .. L["off"] .. ")|r") or ""))
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", 0, -(6 + (i - 1) * 24))
  b:SetPoint("RIGHT", 0, 0)
  b:Show()
  return b
end

function Hub.Refresh()
  if not win then
    return
  end
  canvas:SetWidth(math.max(100, (scroll:GetWidth() or 440)))
  local list = entries()
  for i, entry in ipairs(list) do
    navButton(i, entry)
  end
  for i = #list + 1, #navButtons do
    navButtons[i]:Hide()
  end
  local current = Hub.current or list[1]
  select(current)
end

function Hub.Open(moduleName)
  if not win then
    build()
  end
  if moduleName == "about" then
    Hub.current = { about = true, title = L["About"] }
  elseif moduleName == "news" then
    Hub.current = { news = true, title = L["What's new"] }
  elseif moduleName then
    local mod = ns.modules[moduleName]
    if mod then
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

-- /bastians [about | news | addons | log [n] | debug | profile <name> | perf]
SLASH_BASTIANS1 = "/bastians"
SlashCmdList.BASTIANS = function(msg)
  local cmd, arg = string.match(msg or "", "^%s*(%S*)%s*(.-)%s*$")
  cmd = string.lower(cmd or "")
  if cmd == "" then
    Hub.Toggle()
  elseif cmd == "about" then
    Hub.Open("about")
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
    B:Say(L["/bastians: hub | news | about | addons | log [n] | debug | profile [name] | perf"])
  end
end
