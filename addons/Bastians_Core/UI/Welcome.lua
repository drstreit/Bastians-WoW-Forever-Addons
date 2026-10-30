-- Welcome (core.md "The Suite page and the welcome"): the window of the first start with the apps,
-- how to open things and the guidelines; the Suite page and `/bastians welcome` show it any time.
local _, ns = ...
local B = ns.B
local L = ns.L
local S = ns.Style
local W = B.UI.Widgets

local Welcome = {}
B.UI.Welcome = Welcome

local win, canvas, scroll, bar, footer

-- The page as rows { kind = "header" | "note" | "app", text }, pure: the suite in two sentences,
-- every app of this client with its state and slash command, how to open things, good to know.
function Welcome.Lines()
  local lines = {}
  local function header(text)
    lines[#lines + 1] = { kind = "header", text = text }
  end
  local function note(text)
    lines[#lines + 1] = { kind = "note", text = text }
  end
  note(
    L["Bastian's Suite puts everything you look up while you play into one window and one map. Every app works on its own; together they link: a name on any page opens its page, its place on the map and the way there."] -- luacheck: ignore 631 (a locale key stays one literal)
  )
  header(L["Your apps"])
  for _, app in ipairs(B.UI.Settings.Apps()) do
    local mod = ns.modules[app.module]
    local installed = C_AddOns.DoesAddOnExist(app.addon)
    local state = ""
    if mod and not mod:IsSwitchOn() then
      state = " (" .. L["off"] .. ")"
    elseif not mod and not installed then
      state = " (" .. L["not installed"] .. ")"
    end
    local title = mod and mod.title or app.module
    local slash = app.slash and ("  " .. app.slash) or ""
    lines[#lines + 1] = { kind = "app", text = title .. state .. slash .. ": " .. app.about }
  end
  header(L["How to open things"])
  note(
    L["Every app has its own minimap button, and a right click on the suite's button lists them all. /bastians opens the settings, /bs the search."] -- luacheck: ignore 631 (a locale key stays one literal)
  )
  note(
    L["Escape closes a window. Drag a window by its title and resize it at its corner; the gear left of the close button opens the app's settings."] -- luacheck: ignore 631 (a locale key stays one literal)
  )
  header(L["Good to know"])
  note(L["Bastian's Data is required and updated daily; let the CurseForge app update it with the suite."])
  note(
    L["After installing another Bastian's addon, restart the game fully: /reload does not load new folders."]
  )
  note(L["Every app can be switched off on the Suite page of the settings; the others keep working."])
  note(L["Pick a look under Skin in the General settings: Modern, Azeroth or Blizzard, and a colour scheme."])
  note(L["Missing or outdated parts are said in chat at login; /bastians addons lists every part."])
  note(L["Questions and feedback: bastians.dev/wow, or the comments on CurseForge."])
  return lines
end

local function render()
  if not canvas then
    return
  end
  for _, w in ipairs(canvas.widgets or {}) do
    w:Hide()
  end
  canvas:SetWidth(math.max(100, (scroll:GetWidth() or 500)))
  local width = (canvas:GetWidth() or 500) - 24
  local widgets = {}
  local y = -10
  for _, line in ipairs(Welcome.Lines()) do
    local w
    if line.kind == "header" then
      w = W.Header(canvas, line.text)
      y = y - 4
    else
      w = W.Note(canvas, line.text, S.C.text)
    end
    w:SetPoint("TOPLEFT", canvas, "TOPLEFT", 12, y)
    w:SetWidth(width)
    w.text = line.text
    w.kind = line.kind
    widgets[#widgets + 1] = w
    y = y - (w:GetHeight() or 16) - 4
  end
  canvas.widgets = widgets
  canvas.contentHeight = -y + 10
  canvas:SetHeight(canvas.contentHeight)
  bar.SetTotal(canvas.contentHeight)
end

local function build()
  win = B.UI.Window("BastiansWelcomeFrame", {
    title = L["Welcome to Bastian's Suite"],
    width = 560,
    height = 540,
    db = ns.core.db.profile.welcome,
    onResize = render,
  })
  footer = CreateFrame("Frame", nil, win.content)
  footer:SetPoint("BOTTOMLEFT", 0, 0)
  footer:SetPoint("BOTTOMRIGHT", 0, 0)
  footer:SetHeight(32)
  footer.settings = S.button(footer, L["Open the settings"], 160, 22)
  footer.settings:SetPoint("LEFT", 12, 0)
  footer.settings.tip = L["The Suite page: every app with its switch and its words."]
  footer.settings:SetScript("OnClick", function()
    B.UI.Hub.Open("suite")
  end)
  footer.close = S.button(footer, L["Close"], 100, 22)
  footer.close:SetPoint("RIGHT", -12, 0)
  footer.close:SetScript("OnClick", function()
    win:Hide()
  end)
  scroll = CreateFrame("ScrollFrame", nil, win.content)
  scroll:SetPoint("TOPLEFT", 0, 0)
  scroll:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -14, 0)
  canvas = CreateFrame("Frame", nil, scroll)
  canvas:SetSize(500, 1)
  scroll:SetScrollChild(canvas)
  bar = S.scrollbar(scroll, win.content)
  Welcome.win, Welcome.canvas = win, canvas
end

function Welcome.Show()
  if not win then
    build()
  end
  win:Show()
  render()
end

function Welcome.Hide()
  if win then
    win:Hide()
  end
end

function Welcome.IsShown()
  return win ~= nil and win:IsShown()
end

-- The first start of the suite on this account (News.Check, ADR 0021): the window once, never in
-- combat (then at the next login). -> whether it was shown.
function Welcome.FirstStart()
  local g = ns.core and ns.core.db and ns.core.db.global
  if not g or g.welcomed then
    return false
  end
  if InCombatLockdown and InCombatLockdown() then
    return false
  end
  g.welcomed = true
  Welcome.Show()
  return true
end
