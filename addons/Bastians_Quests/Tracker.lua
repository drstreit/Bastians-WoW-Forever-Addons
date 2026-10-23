-- The tracker frame: the log view ("My quests") in its own window,
-- fixed on screen (under the minimap until moved), replacing the game's objective tracker while it
-- shows; the Companion keeps the same view and its slim mode. A third host of the log view beside
-- the Browser and the fallback window: the view renders into it, two-line rows, the two toggles
-- on its bar, the secure quest-item bar beside it; the rows re-render through Window.Schedule.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Widgets = B.UI.Widgets

local Tracker = {}
ns.Tracker = Tracker

local VIEW = "quests.log"
local CLAIM = "quests-tracker" -- the game tracker claim (core-contracts §13)
local RENDER_DELAY = 0.05
local DEFAULT_W, DEFAULT_H = 300, 420

local mod, win, bar, tree, summary
local rows -- the rows shown now, for the item bar

local function db()
  return mod.db.profile
end

function Tracker.Enabled()
  return mod ~= nil and mod:IsEnabled() and db().trackerFrame ~= false
end

-- The host the log view renders into (core-contracts §7b).
local function host()
  local h = { frame = win and win.frame, id = VIEW, args = {} }
  function h.SetRows(_, list)
    rows = list or {}
    tree:SetRows(rows)
  end
  function h.SetSummary(_, text)
    summary:SetText(text or "")
  end
  function h.SetChips(_, chips, active, onChip, title)
    tree:SetChips(chips or {}, active, onChip, nil, title)
  end
  function h.SetControls(_, controls)
    bar:SetControls(controls)
  end
  function h.Job(_, name, fn, onDone)
    return B.Jobs:Run(mod, name, fn, { onDone = onDone })
  end
  function h.Render()
    Tracker.Render()
  end
  function h.IsShown()
    return win ~= nil and win:IsShown()
  end
  return h
end

local function applyLock()
  if not win then
    return
  end
  local locked = db().trackerLocked == true
  if locked then
    win.head:RegisterForDrag() -- no button starts a drag
    win.grip:Hide()
  else
    win.head:RegisterForDrag("LeftButton")
    win.grip:Show()
  end
  if win.lock then
    win.lock.label:SetText(locked and L["Locked"] or L["Lock"])
    local c = locked and S.C.accent or S.C.text
    win.lock.label:SetTextColor(c[1], c[2], c[3])
  end
end

-- The lock on the frame itself: the same
-- setting as the hub's "Lock the frame in place".
function Tracker.ToggleLock()
  local p = db()
  p.trackerLocked = p.trackerLocked ~= true
  applyLock()
  B:Fire("BASTIANS_SETTING_CHANGED", mod.name, "trackerLocked", p.trackerLocked)
end

local function build()
  local p = db()
  p.tracker = p.tracker or {}
  local fresh = p.tracker.pos == nil
  win = B.UI.Window("BastiansTrackerFrame", {
    title = L["My quests"],
    width = DEFAULT_W,
    height = DEFAULT_H,
    minWidth = 220,
    minHeight = 120,
    db = p.tracker,
    escape = false, -- ESC leaves the tracker where it is
    onShow = function()
      Tracker.Render()
      Tracker.UpdateClaim()
    end,
    onHide = function()
      ns.Window.SetItemBar(nil, { frame = win.frame })
      Tracker.UpdateClaim()
    end,
    onResize = function()
      if tree then
        tree:Refresh()
      end
    end,
  })
  -- below the Companion and the map, above the world: the windows open over it
  win.frame:SetFrameStrata("MEDIUM")
  win.PlaceStrata = function() end
  if fresh then
    -- under the minimap, where the game's tracker sits
    win.frame:ClearAllPoints()
    if Minimap then
      win.frame:SetPoint("TOPRIGHT", Minimap, "BOTTOMRIGHT", 0, -24)
    else
      win.frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -220)
    end
  end
  win.lock = S.button(win.head, L["Lock"], 54, 20)
  win.lock:SetPoint("RIGHT", win.close, "LEFT", -4, 0)
  win.lock:SetScript("OnClick", Tracker.ToggleLock)
  win.lock.tip = function()
    local text = "Locked: the frame cannot be moved or resized. Click to switch;"
      .. ' the same as "Lock the frame in place" in the settings.'
    return L["Lock the frame in place"], L[text]
  end
  local content = win.content
  bar = Widgets.ControlBar(content)
  bar:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -4)
  bar:SetPoint("TOPRIGHT", content, "TOPRIGHT", -6, -4)
  tree = B.UI.Tree(content, {
    db = p.tracker, -- the folds of the groups, apart from the fallback window's
    ctx = { source = "tracker" },
    twoLine = true, -- the owner's two-line quest rows (R2)
    iconsAlways = true,
    onClick = function(row, button)
      if row.onClick and button ~= "RightButton" then
        row.onClick(row, button)
      elseif row.ref and button == "RightButton" then
        B.UI.EntityMenu(row.ref, nil, { source = "tracker" })
      elseif row.group and row.hasChildren then
        tree:ToggleFold(row)
      elseif row.ref then
        B:ShowPage(row.ref) -- the quest page in the Companion (or the fallback window)
      elseif row.hasChildren then
        tree:ToggleFold(row)
      end
    end,
  })
  tree.chips:ClearAllPoints()
  tree.chips:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -28)
  tree.chips:SetPoint("TOPRIGHT", content, "TOPRIGHT", -20, -28)
  tree.scroll:ClearAllPoints()
  tree.scroll:SetPoint("TOPLEFT", tree.chips, "BOTTOMLEFT", 0, -2)
  tree.scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -20, 18)
  summary = S.text(content, 11, S.C.dim)
  summary:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 8, 4)
  summary:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -8, 4)
  applyLock()
  Tracker.win, Tracker.tree, Tracker.bar, Tracker.summary = win, tree, bar, summary
end

-- The game's tracker goes while the frame shows and the setting says so.
function Tracker.UpdateClaim()
  local hide = win ~= nil and win:IsShown() and db().trackerHidesGame ~= false
  B.UI.ClaimGameTracker(CLAIM, hide)
end

function Tracker.Render()
  if not (win and win:IsShown() and mod and mod:IsEnabled()) then
    return
  end
  local h = host()
  tree:SetChips({}, nil, nil)
  B:RenderView(VIEW, h)
  -- the quest items of the shown rows sit beside this frame (secure bar, out of combat)
  ns.Window.SetItemBar(ns.Window.ItemsOf(rows or {}), { frame = win.frame })
end

-- Called with every Window.Schedule: the rows follow the log, the zone and the settings.
function Tracker.Schedule()
  if mod and win and win:IsShown() then
    mod:Coalesce("tracker", RENDER_DELAY, Tracker.Render)
  end
end

-- The settings decide: the frame shows while `trackerFrame` is on, the lock and the claim follow.
function Tracker.Apply()
  if not mod then
    return
  end
  if Tracker.Enabled() then
    if not win then
      build()
    end
    applyLock()
    if not win:IsShown() then
      win:Show() -- onShow renders and claims
    else
      Tracker.UpdateClaim()
      Tracker.Schedule()
    end
  elseif win and win:IsShown() then
    win:Hide() -- onHide releases the claim and the item bar
  end
end

function Tracker.Toggle()
  if not mod then
    return false
  end
  db().trackerFrame = not Tracker.Enabled()
  Tracker.Apply()
  return db().trackerFrame
end

function Tracker.IsShown()
  return win ~= nil and win:IsShown()
end

function Tracker.Hide()
  if win and win:IsShown() then
    win:Hide()
  end
end

-- Wiring once per enable: the frame comes up after login (the log arrives then).
function Tracker.Register(self)
  mod = self
  self:RegisterEvent("PLAYER_LOGIN", function()
    Tracker.Apply()
  end)
  Tracker.Apply() -- enabled after login (the usual case): now; the log's arrival re-renders
end
