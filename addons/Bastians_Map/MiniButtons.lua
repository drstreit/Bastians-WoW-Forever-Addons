-- The button box of Bastian's minimap: the minimap
-- buttons of other addons (LibDBIcon's, and every named button on the game's minimap) packed into
-- one window that opens from the minimap's tools row. Hovering a button shows its name in the
-- window's title bar, large and readable (owner: "hard to read otherwise"). Clicks are the
-- button's own. Off, every button goes back where it was.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style

local MB = {}
ns.MiniButtons = MB

MB.SIZE = 28 -- one cell of the grid
MB.GAP = 4
MB.COLS = 9 -- the columns of a new box; the window's width decides from then on (30.10.2026)
MB.MAX_ROWS = 6 -- rows the window grows to; more scroll
-- Named frames on the minimap that are the game's own (they stay where Mini.lua puts them).
MB.SKIP = {
  "^Minimap",
  "^MiniMap",
  "^GameTimeFrame",
  "^TimeManager",
  "^QueueStatus",
  "^ExpansionLandingPage",
  "^AddonCompartment",
  "^BastiansMinimapOverlay",
  "^BastiansMiniMap",
  "^BastiansMinimapButton$", -- the suite's button: the minimap's badge stands in for it
  "^HandyNotes", -- map pins, not buttons
  "^GatherMatePin",
  "^QuestieFrame",
  "^TTMinimapButton", -- TomTom's crazy arrow pins
}

local mod, win
local collected = {} -- { frame, name, state, ldb } in grid order
MB.collected = collected

local function db()
  return mod.db.profile
end

function MB.Enabled()
  return mod ~= nil and db().miniButtonBox ~= false and ns.Mini.Enabled()
end

-- "LibDBIcon10_BugSack" -> "Bug Sack", "BastiansMinimapButtonQuests" -> "Bastian's Quests".
function MB.Pretty(name)
  name = tostring(name or "?")
  name = name:gsub("^LibDBIcon10_", ""):gsub("MinimapButton", " "):gsub("_Minimap", ""):gsub("_", " ")
  name = name:gsub("(%l)(%u)", "%1 %2")
  name = name:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""):gsub("^Bastians", "Bastian's")
  return name ~= "" and name or "?"
end

local function skipped(name)
  for _, pattern in ipairs(MB.SKIP) do
    if name:find(pattern) then
      return true
    end
  end
  return false
end

-- Every minimap button there is now: { frame, name, ldb } (LibDBIcon's first, by name).
function MB.Scan()
  local out, seen = {}, {}
  local lib = LibStub and LibStub("LibDBIcon-1.0", true)
  if lib and type(lib.objects) == "table" then
    local names = {}
    for name in pairs(lib.objects) do
      names[#names + 1] = name
    end
    table.sort(names)
    for _, name in ipairs(names) do
      local b = lib.objects[name]
      if type(b) == "table" and not seen[b] then
        seen[b] = true
        local label = b.dataObject and (b.dataObject.label or b.dataObject.text) or nil
        out[#out + 1] = { frame = b, name = label or name, ldb = true }
      end
    end
  end
  local others = {}
  -- the game's minimap, its backdrop and its cluster (some addons put their button there, and
  -- the cluster waits hidden while Bastian's minimap shows: , no other addon's
  -- button was in the box)
  local parents = {}
  for _, name in ipairs({ "Minimap", "MinimapBackdrop", "MinimapCluster" }) do
    local f = rawget(_G, name) -- a missing one is skipped (a nil in a list stops ipairs)
    if f then
      parents[#parents + 1] = f
    end
  end
  for _, parent in ipairs(parents) do
    if parent.GetChildren then
      for _, child in ipairs({ parent:GetChildren() }) do
        local name = child.GetName and child:GetName()
        if
          name
          and not seen[child]
          and child.IsObjectType
          and child:IsObjectType("Button")
          and not skipped(name)
        then
          seen[child] = true
          others[#others + 1] = { frame = child, name = MB.Pretty(name) }
        end
      end
    end
  end
  table.sort(others, function(a, b)
    return a.name < b.name
  end)
  for _, o in ipairs(others) do
    out[#out + 1] = o
  end
  return out
end

-- The name in the title bar while the mouse is on a button.
local function hook(entry)
  local f = entry.frame
  if f.bastiansBoxHooked then
    f.bastiansBoxName = entry.name
    return
  end
  f.bastiansBoxHooked = true
  f.bastiansBoxName = entry.name
  f:HookScript("OnEnter", function(self)
    if win and self:GetParent() == win.grid then
      win:SetTitle(self.bastiansBoxName or "?")
    end
  end)
  f:HookScript("OnLeave", function(self)
    if win and self:GetParent() == win.grid then
      win:SetTitle(L["Minimap buttons"])
    end
  end)
end

MB.HOVER_GRACE = 0.4 -- seconds the box stays after the mouse left it and its button
MB.HINT_H = 16

local function build()
  win = B.UI.Window("BastiansMiniButtons", {
    module = "Map",
    page = "minimap", -- the box's options live on the minimap's page
    title = L["Minimap buttons"],
    width = MB.COLS * (MB.SIZE + MB.GAP) + MB.GAP + 16 + 2,
    height = 120,
    minWidth = 3 * (MB.SIZE + MB.GAP) + MB.GAP + 16 + 2,
    minHeight = 80,
    db = db().buttonBox,
    onResize = function()
      MB.Layout() -- the columns follow the width
    end,
  })
  -- how a button moves between the box and the map ("how to move them
  -- back in?")
  win.hint = S.text(win.content, 10, S.C.dim)
  win.hint:SetPoint("BOTTOMLEFT", win.content, "BOTTOMLEFT", MB.GAP, 3)
  win.hint:SetPoint("BOTTOMRIGHT", win.content, "BOTTOMRIGHT", -MB.GAP, 3)
  win.hint:SetJustifyH("LEFT")
  win.hint:SetText(L["Ctrl+click: put a button on the map, or back into the box."])
  -- the grid in a scroll frame: the window grows to MAX_ROWS, more rows scroll
  win.scroll = CreateFrame("ScrollFrame", nil, win.content)
  win.scroll:SetPoint("TOPLEFT", win.content, "TOPLEFT", 0, 0)
  win.scroll:SetPoint("BOTTOMRIGHT", win.content, "BOTTOMRIGHT", -16, MB.HINT_H + 4)
  win.grid = CreateFrame("Frame", nil, win.scroll)
  win.grid:SetSize(100, 1)
  win.scroll:SetScrollChild(win.grid)
  win.bar = S.scrollbar(win.scroll, win.content)
  MB.win = win
end

-- The columns the box's width holds, two at least.
function MB.Columns()
  local width = (win and win.scroll and win.scroll:GetWidth() or 0)
  if width <= 0 then
    width = (win and win.frame:GetWidth() or 0) - 16 - 2
  end
  return math.max(2, math.floor((width - MB.GAP) / (MB.SIZE + MB.GAP)))
end

-- Where a button lives: "box" (the default) or "map" (on the rim of Bastian's minimap), kept by
-- the button's frame name.
function MB.Home(entry)
  local homes = db().buttonHomes
  return type(homes) == "table" and homes[entry.key] == "map" and "map" or "box"
end

local function homed(home)
  local out = {}
  for _, entry in ipairs(collected) do
    if MB.Home(entry) == home then
      out[#out + 1] = entry
    end
  end
  return out
end

-- "On the map" is the rim of Bastian's minimap (a button Ctrl+clicked out
-- of the box was gone, also after a reload: its old place was the game's minimap cluster, which
-- waits hidden while ours shows). The buttons take these places in turn, degrees counter-clockwise
-- from east, clear of the badge (45) and the box's button (225).
MB.RIM_ANGLES = { 135, 160, 110, 185, 85, 250, 275, 300, 325, 350, 15, 205 }

-- The frame a button sits on and the frame its point is relative to, for its home.
local function hostOf(home)
  if home == "box" then
    return win and win.grid, win and win.grid
  end
  return ns.Mini.Frame(), ns.Mini.View()
end

local laying = false

-- An addon putting its boxed button back on the minimap (LibDBIcon does on many occasions): the
-- box takes it back on the next frame.
local function guard(entry)
  local f = entry.frame
  if f.bastiansBoxGuarded then
    return
  end
  f.bastiansBoxGuarded = true
  hooksecurefunc(f, "SetPoint", function(self)
    if laying or not win then
      return
    end
    local host, anchor = hostOf(MB.Home(entry))
    if not host or self:GetParent() ~= host then
      return
    end
    local _, rel = self:GetPoint(1)
    if rel ~= anchor then
      C_Timer.After(0, MB.Layout)
    end
  end)
end

-- A button's layer: LibDBIcon fixes its buttons to MEDIUM and level 8 (SetFixedFrameStrata), so in
-- the box they stayed under the window, two empty cells (no button but
-- ours). In the box a button takes the window's strata; back on the map its own again.
local function layerOf(f)
  return {
    strata = f.GetFrameStrata and f:GetFrameStrata() or nil,
    level = f.GetFrameLevel and f:GetFrameLevel() or nil,
    fixedStrata = f.HasFixedFrameStrata and f:HasFixedFrameStrata() or false,
    fixedLevel = f.HasFixedFrameLevel and f:HasFixedFrameLevel() or false,
  }
end

local function setLayer(f, strata, level, fixedStrata, fixedLevel)
  if f.SetFixedFrameStrata then
    f:SetFixedFrameStrata(false)
  end
  if f.SetFixedFrameLevel then
    f:SetFixedFrameLevel(false)
  end
  if strata then
    f:SetFrameStrata(strata)
  end
  if level then
    f:SetFrameLevel(level)
  end
  if fixedStrata and f.SetFixedFrameStrata then
    f:SetFixedFrameStrata(true)
  end
  if fixedLevel and f.SetFixedFrameLevel then
    f:SetFixedFrameLevel(true)
  end
end

local function restore(entry)
  local f, st = entry.frame, entry.state
  f:SetParent(st.parent)
  local layer = st.layer or {}
  setLayer(f, layer.strata, layer.level, layer.fixedStrata, layer.fixedLevel)
  f:ClearAllPoints()
  for _, p in ipairs(st.points) do
    f:SetPoint(unpack(p))
  end
  if f.SetScale then
    f:SetScale(st.scale or 1)
  end
  if entry.ldb and f.RegisterForDrag then
    f:RegisterForDrag("LeftButton") -- LibDBIcon's drag around the minimap again
  end
end

-- A button in the box's grid or on the rim: the layer given, its size, no LibDBIcon drag (that one
-- moves it around the game's minimap).
local function lay(entry, host, strata, level, anchor, x, y, point)
  local f = entry.frame
  f:SetParent(host)
  setLayer(f, strata, level)
  local scale = 1
  if f.SetScale then
    local h = entry.state.h or MB.SIZE
    scale = math.min(1.2, MB.SIZE / math.max(1, h))
    f:SetScale(scale)
  end
  -- a point's offsets count in the button's own scale (the rim's buttons
  -- sat inside the ring, not on it)
  f:ClearAllPoints()
  f:SetPoint(point, anchor, point, x / scale, y / scale)
  if entry.ldb and f.RegisterForDrag then
    f:RegisterForDrag()
  end
  f:Show()
end

-- The rim's buttons around the view, on the circle or the square's edge, at the badge's height:
-- the view's layers (the styles' clip, the mouse catcher) cover its whole square, and a place on
-- the circle lies inside it (the buttons were still gone; the mock does
-- not draw by level).
MB.RIM_LEVEL = 28 -- above the view's own level; the badge is at 30

-- The middle of the frame's accent rim (its outer 2 px), where the buttons' centres sit (owner,
-- retail 28.10.2026: "the outer green ring exactly in the middle of the buttons").
function MB.RimRadius()
  return ns.Mini.Size() / 2 + ns.Mini.BORDER - 1
end

local function layRim()
  local host, view = hostOf("map")
  local r = MB.RimRadius()
  for i, entry in ipairs(homed("map")) do
    if host and view then
      local a = math.rad(MB.RIM_ANGLES[(i - 1) % #MB.RIM_ANGLES + 1])
      local c, s = math.cos(a), math.sin(a)
      if ns.Mini.Shape() ~= "ROUND" then
        local m = math.max(math.abs(c), math.abs(s))
        c, s = c / m, s / m
      end
      local level = (view:GetFrameLevel() or 1) + MB.RIM_LEVEL
      lay(entry, host, host:GetFrameStrata(), level, view, r * c, r * s, "CENTER")
    else
      restore(entry)
    end
  end
end

-- The grid: the boxed buttons in as many columns as the width holds (MB.Columns), the window as
-- tall as the rows need up to MAX_ROWS, more rows scroll; the others on the rim of Bastian's
-- minimap. Called again when the player resizes the window.
function MB.Layout()
  if not win then
    return
  end
  local list = homed("box")
  local cols = MB.Columns()
  laying = true
  for i, entry in ipairs(list) do
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    local x, y = MB.GAP + col * (MB.SIZE + MB.GAP), -(MB.GAP + row * (MB.SIZE + MB.GAP))
    local level = (win.grid:GetFrameLevel() or 1) + 2
    lay(entry, win.grid, win.frame:GetFrameStrata(), level, win.grid, x, y, "TOPLEFT")
  end
  layRim()
  laying = false
  local rows = math.max(1, math.ceil(#list / cols))
  local gridHeight = MB.GAP + rows * (MB.SIZE + MB.GAP)
  local shown = MB.GAP + math.min(rows, MB.MAX_ROWS) * (MB.SIZE + MB.GAP)
  win.grid:SetSize(math.max(1, win.scroll:GetWidth() or 100), gridHeight)
  -- the chrome: the header and the frame's inset top and bottom (the game's frames, ADR 0034)
  local inset = win.framed and win.FRAME_INSET or 1
  win.frame:SetHeight(30 + 2 * inset + shown + MB.HINT_H + 4)
  win.bar.SetTotal(gridHeight)
  MB.cols, MB.rows = cols, rows
end

-- Ctrl+click moves a button between the box and the map; any other click is the button's own.
local function wrapClick(entry)
  local f = entry.frame
  if f.bastiansBoxWrapped or not f.GetScript then
    return
  end
  local own = f:GetScript("OnClick")
  f.bastiansBoxWrapped, f.bastiansBoxOwnClick = true, own
  f:SetScript("OnClick", function(self, button, ...)
    if IsControlKeyDown and IsControlKeyDown() and self.bastiansBoxEntry then
      MB.Move(self.bastiansBoxEntry)
      return
    end
    if own then
      return own(self, button, ...)
    end
  end)
  f.bastiansBoxEntry = entry
end

local function unwrapClick(entry)
  local f = entry.frame
  if f.bastiansBoxWrapped then
    f:SetScript("OnClick", f.bastiansBoxOwnClick)
    f.bastiansBoxWrapped, f.bastiansBoxOwnClick, f.bastiansBoxEntry = nil, nil, nil
  end
end

-- A button to the other home, remembered.
function MB.Move(entry)
  if InCombatLockdown() then
    return false
  end
  local homes = db().buttonHomes
  if type(homes) ~= "table" then
    homes = {}
    db().buttonHomes = homes
  end
  homes[entry.key] = MB.Home(entry) == "box" and "map" or nil
  MB.Layout()
  return true
end

-- Every button back into the box.
function MB.AllIntoBox()
  if InCombatLockdown() then
    return false
  end
  db().buttonHomes = nil
  MB.Layout()
  return true
end

local function stateOf(f)
  local points = {}
  for i = 1, f:GetNumPoints() do
    points[i] = { f:GetPoint(i) }
  end
  return {
    parent = f:GetParent(),
    points = points,
    scale = f.GetScale and f:GetScale() or 1,
    h = f:GetHeight(),
    layer = layerOf(f),
  }
end

-- Takes every button there is (new ones too: a scan each time): into the box, or left on the map
-- when its home is the map.
function MB.Collect()
  if InCombatLockdown() then
    return false
  end
  if not win then
    build()
  end
  local have = {}
  for _, entry in ipairs(collected) do
    have[entry.frame] = true
  end
  for _, entry in ipairs(MB.Scan()) do
    if not have[entry.frame] then
      entry.key = entry.frame:GetName() or entry.name
      entry.state = stateOf(entry.frame)
      hook(entry)
      wrapClick(entry)
      guard(entry)
      collected[#collected + 1] = entry
    end
  end
  MB.Layout()
  return true
end

-- Every button back where it was, its own click again, the box closed.
function MB.Release()
  if InCombatLockdown() then
    return false
  end
  for i = #collected, 1, -1 do
    local entry = collected[i]
    restore(entry)
    unwrapClick(entry)
    collected[i] = nil
  end
  if win then
    win:Hide()
  end
  return true
end

-- The setting decides: on collects (the box opens when the mouse is on its button), off gives them
-- back.
function MB.Apply()
  if not mod then
    return
  end
  if MB.Enabled() then
    MB.Collect()
  else
    MB.Release()
  end
  local opener = ns.Mini.Frame() and ns.Mini.Frame().boxButton
  if opener then
    opener:SetShown(MB.Enabled())
  end
end

-- The box beside its button on the minimap's rim, open while the mouse is on either (owner, retail
-- 28.10.2026: "a hover will open it, no clicking"); it goes HOVER_GRACE after the mouse left both.
local watcher
function MB.Open(anchor)
  if not MB.Enabled() then
    return
  end
  MB.Collect()
  if anchor and not db().buttonBox.pos then
    win.frame:ClearAllPoints()
    win.frame:SetPoint("TOPRIGHT", anchor, "BOTTOMLEFT", 4, 4)
  end
  win:Show()
  watcher = watcher or CreateFrame("Frame", nil, win.frame)
  local away = 0
  watcher:SetScript("OnUpdate", function(me, elapsed)
    if win.frame:IsMouseOver() or (anchor and anchor:IsMouseOver()) then
      away = 0
      return
    end
    away = away + elapsed
    if away >= MB.HOVER_GRACE then
      me:SetScript("OnUpdate", nil) -- watches only while the box shows (CLAUDE.md golden rule 7)
      win:Hide()
    end
  end)
end

function MB.Window()
  return win
end

ns.mod.MiniButtons = MB
table.insert(ns.Map.onEnable, function(self)
  mod = self
  local profile = self.db.profile
  profile.buttonBox = profile.buttonBox or {}
end)
