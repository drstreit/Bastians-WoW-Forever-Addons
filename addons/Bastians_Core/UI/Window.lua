-- UI kit: Bastians.UI.Window(name, opts): movable, resizable, flat window with a header, close button,
-- resize grip, saved position and size, placed above the world map; ESC closes it (core-contracts §13).
local _, ns = ...
local B = ns.B
local S = ns.Style
local L = ns.L

local HEADER_H = 30
local DEFAULTS =
  { width = 420, height = 520, minWidth = 300, minHeight = 240, maxWidth = 1200, maxHeight = 1200 }
-- `maxWidth` or `maxHeight` = B.UI.NO_LIMIT: as large as the player drags it (owner, retail
-- 28.10.2026: the map stopped at half the screen); the window stays clamped to the screen.
B.UI.NO_LIMIT = 100000

-- The resize bounds of a window, at least `w` x `h` (full screen lifts them to the screen).
local function resizeBounds(frame, opts, w, h)
  frame:SetResizeBounds(
    opts.minWidth or DEFAULTS.minWidth,
    opts.minHeight or DEFAULTS.minHeight,
    math.max(w or 0, opts.maxWidth or DEFAULTS.maxWidth),
    math.max(h or 0, opts.maxHeight or DEFAULTS.maxHeight)
  )
end

local Window = {}
Window.__index = Window

-- Every window by frame name (ADR 0013 E: the dock needs to find its partner), and the dock pair:
-- the map left, the Browser right. `B.UI.DOCK_MODULES` names the module that opens each window.
B.UI.Windows = {}
B.UI.DOCK = { left = "BastiansMapFrame", right = "BastiansBrowserFrame" }
B.UI.DOCK_MODULES = { BastiansMapFrame = "Map", BastiansBrowserFrame = "Browser" }
local DOCK_GAP = 2
local RESIZE_COALESCE = 0.1 -- seconds between content refreshes while the grip is held
local GRIP_LEVEL = 100 -- frame levels above the window: no content frame reaches it
local GESTURE_PX = 40 -- a right-button drag this far goes back or forward
local GESTURE_FLASH = 0.4 -- seconds the arrow shows
local GESTURE_RECENT = 0.5 -- a right click this soon after a gesture opens no menu

-- The right-button drag: while a window
-- with `opts.gestures = { back = fn, forward = fn }` shows, an unnamed child watches the right
-- mouse button over it; a drag of GESTURE_PX to the left goes back, to the right forward, an
-- arrow flashes at the cursor side, and the row's own right click is swallowed
-- (B.UI.GestureRecent, read by the entity menu). The watcher runs only while the window shows.
local gestureAt

function B.UI.GestureRecent()
  return gestureAt ~= nil and (GetTime() - gestureAt) < GESTURE_RECENT
end

local function flashArrow(win, dir)
  local frame = win.frame
  local arrow = win.gestureArrow
  if not arrow then
    -- a real arrow with a shaft, big and in the accent colour (the
    -- chevron "<" was too small and thin)
    arrow = CreateFrame("Frame", nil, frame)
    arrow:SetSize(96, 96)
    arrow:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
    arrow.face = S.fill(arrow, S.C.panel)
    arrow.face:SetAlpha(0.85)
    arrow.tex = arrow:CreateTexture(nil, "OVERLAY")
    arrow.tex:SetTexture(S.ARROW)
    arrow.tex:SetSize(80, 80)
    arrow.tex:SetPoint("CENTER")
    local c = S.C.accent
    arrow.tex:SetVertexColor(c[1], c[2], c[3], 1)
    win.gestureArrow = arrow
  end
  arrow.dir = dir
  if dir == "back" then
    arrow.tex:SetTexCoord(1, 0, 0, 1) -- mirrored: pointing west
  else
    arrow.tex:SetTexCoord(0, 1, 0, 1)
  end
  arrow:ClearAllPoints()
  arrow:SetPoint(dir == "back" and "LEFT" or "RIGHT", frame, dir == "back" and "LEFT" or "RIGHT", 0, 0)
  arrow:Show()
  C_Timer.After(GESTURE_FLASH, function()
    arrow:Hide()
  end)
end

local function watchGestures(win, gestures)
  local frame = win.frame
  local watcher = CreateFrame("Frame", nil, frame)
  watcher:SetSize(1, 1)
  win.gestureWatcher = watcher
  local function tick()
    local down = IsMouseButtonDown("RightButton")
    local g = win.gesture
    if down and not g then
      if frame:IsMouseOver() then
        win.gesture = { x0 = GetCursorPosition(), fired = nil }
      end
    elseif down and g and not g.fired then
      local dx = (GetCursorPosition() - g.x0) / (frame:GetEffectiveScale() or 1)
      if math.abs(dx) >= GESTURE_PX then
        g.fired = dx < 0 and "back" or "forward"
        gestureAt = GetTime()
        flashArrow(win, g.fired)
      end
    elseif not down and g then
      win.gesture = nil
      if g.fired and gestures[g.fired] then
        gestureAt = GetTime()
        gestures[g.fired](win)
      end
    end
  end
  frame:HookScript("OnShow", function()
    watcher:SetScript("OnUpdate", tick)
  end)
  frame:HookScript("OnHide", function()
    watcher:SetScript("OnUpdate", nil)
    win.gesture = nil
  end)
  if frame:IsShown() then
    watcher:SetScript("OnUpdate", tick)
  end
end

local function draggable(region, win)
  region:EnableMouse(true)
  region:RegisterForDrag("LeftButton")
  region:SetScript("OnDragStart", function()
    if win.db.locked then
      return -- locked in place
    end
    if win.dock then
      win:Undock(true) -- dragging a docked window away undocks it, where it stands
    end
    -- The move starts from where the window is seen, anchored there, and stays on the screen
    -- ("when I click in the top bar to move it, it jumps out of the top
    -- border of the screen and my mouse is in the middle"). The clamp used to be lifted for the
    -- move: a window whose anchor lay beyond the screen edge, shown clamped, then jumped to it.
    win:AnchorAtSight()
    win.frame:StartMoving()
  end)
  region:SetScript("OnDragStop", function()
    win.frame:StopMovingOrSizing()
    win.dodged = nil -- moved by hand: this is its place now, nothing to restore
    win:SavePlace()
  end)
end

-- opts: { title, width, height, minWidth, minHeight, maxWidth, maxHeight, db (table for pos and size),
--         onShow(win), onHide(win), onResize(win), escape (default true), onTop (above every
--         other window, Window.TOP_STRATA) }
function B.UI.Window(name, opts)
  opts = opts or {}
  local db = opts.db or {}
  local frame = CreateFrame("Frame", name, UIParent)
  local win = setmetatable({ frame = frame, name = name, db = db, opts = opts }, Window)
  -- a window of its own palette (the settings, always the WoW look): its widgets ask it (S.Tok)
  frame.palette = opts.palette

  local size = db.size or { opts.width or DEFAULTS.width, opts.height or DEFAULTS.height }
  frame:SetSize(size[1], size[2])
  frame:SetFrameStrata(opts.strata or Window.STRATA)
  frame:SetToplevel(not opts.onTop) -- a window on top never climbs over the tooltips and menus
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:SetResizable(true)
  resizeBounds(frame, opts)
  S.panel(frame)
  frame:EnableMouse(true)
  draggable(frame, win)
  win:RestorePlace()
  frame:Hide()

  frame:SetScript("OnShow", function()
    win:PlaceStrata()
    if opts.onShow then
      opts.onShow(win)
    end
  end)
  frame:SetScript("OnHide", function()
    if opts.onHide then
      opts.onHide(win)
    end
  end)
  frame:SetScript("OnMouseDown", function(self)
    if not opts.onTop then
      self:Raise()
    end
  end)
  -- onResize(win, sizing): `sizing` is true while the grip is held and false for the final call
  -- after the mouse is up. The client fires OnSizeChanged per frame while sizing; the content
  -- follows at most ten times a second (a full refresh per frame made
  -- the resize crawl at one update a second), the followers at once.
  -- A docked follower resized by its leader's grip counts as sizing too (`followSizing`): before,
  -- each of the leader's size events gave the follower two full refreshes, the map with the
  -- Browser docked crawled.
  frame:SetScript("OnSizeChanged", function()
    if not win.placing then -- PlaceDocked refreshes the content itself
      win:ResizeContent(win.sizing or win.followSizing)
    end
    win:SizeFollowers(win.sizing)
  end)

  -- header: title, close
  local head = CreateFrame("Frame", nil, frame)
  head:SetPoint("TOPLEFT", 1, -1)
  head:SetPoint("TOPRIGHT", -1, -1)
  head:SetHeight(HEADER_H)
  head.bg = S.roundFill(head, S.C.header, "radius", nil, "top") -- the window's top corners
  draggable(head, win)
  win.head = head

  win.title = S.heading(head, 15, 17, S.C.headerText) -- the heading font; gold on the Azeroth bar
  win.title:SetPoint("LEFT", 10, 0)
  win.title:SetPoint("RIGHT", -34, 0)
  win.title:SetWordWrap(false) -- a title never breaks into two lines
  win.title:SetText(opts.title or name)

  -- the header's actions (ADR 0046: declared, the look draws the pictogram and the text)
  win.close = S.action(head, {
    icon = "close",
    label = L["Close"],
    tip = L["Close (Escape)"],
    row = true,
    onClick = function()
      frame:Hide()
    end,
  })
  win.close:SetPoint("RIGHT", -6, 0)

  -- the window's options, straight to its app's page of the settings (,
  -- R27.1): `opts.module` names the app, `opts.page` one of its own pages (core-contracts §8)
  if opts.module then
    local b = S.action(head, {
      icon = "settings",
      label = L["Options"],
      tip = L["Options of this window"],
      row = true,
      onClick = function()
        if B.UI.Hub then
          B.UI.Hub.Open(opts.module, opts.page)
        end
      end,
    })
    b:SetPoint("RIGHT", win.close, "LEFT", -4, 0)
    win.options = b
  end

  -- the lock ("an option to lock the chat window in place", per
  -- window): `opts.lockable` shows it left of the options; locked, the window neither moves
  -- nor sizes, and `db.locked` keeps it so
  if opts.lockable then
    local b = S.action(head, {
      icon = "lock",
      label = L["Lock"],
      row = true,
      onClick = function()
        win:SetLocked(not win.db.locked)
      end,
    })
    b:SetPoint("RIGHT", win.options or win.close, "LEFT", -4, 0)
    win.lock = b
  end
  win.title:SetPoint("RIGHT", win.lock or win.options or win.close, "LEFT", -8, 0)

  -- content area: apps anchor their widgets here
  local content = CreateFrame("Frame", nil, frame)
  content:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, 0)
  content:SetPoint("BOTTOMRIGHT", -1, 1)
  win.content = content

  -- resize grip, bottom right
  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -1, 1)
  -- above everything the content builds (the book's "turn the page"
  -- button sat over the grip at the same level, so the grip took the mouse only now and then)
  grip:SetFrameLevel((frame:GetFrameLevel() or 1) + GRIP_LEVEL)
  local gripTex = S.fill(grip, S.C.accent, "OVERLAY")
  gripTex:SetAlpha(0.5)
  grip:SetScript("OnMouseDown", function()
    win.sizing = true
    -- a docked window keeps its partner's height: the grip changes its width only, and the
    -- pair stays docked
    local d = win.dock
    -- a window still at the screen's centre (never moved) is anchored at its top left first: the
    -- client sizes a centre-anchored frame from both sides and it jumped (owner, retail
    -- 02.11.2026: "the window jumps to a large size, then can be scaled")
    local left, top = frame:GetLeft(), frame:GetTop()
    if not d and not win.full and left and top and frame:GetPoint(1) ~= "TOPLEFT" then
      frame:ClearAllPoints()
      frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end
    frame:StartSizing(d and (d.side == "left" and "LEFT" or "RIGHT") or "BOTTOMRIGHT")
  end)
  grip:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    win.sizing = nil
    win:SavePlace()
    if opts.onResize then
      opts.onResize(win, false)
    end
    win:SizeFollowers(false) -- the followers' final full refresh
  end)
  win.grip = grip
  if opts.lockable then
    win:SetLocked(db.locked == true)
  end
  if opts.gestures then
    watchGestures(win, opts.gestures)
  end
  if db.full then
    win:SetFullScreen(true)
  end

  -- ESC closes: the client hides every frame named in UISpecialFrames (FrameXML; both clients)
  if opts.escape ~= false and name then
    table.insert(UISpecialFrames, name)
  end
  win:ApplyLook()
  if name then
    B.UI.Windows[name] = win
    -- a dock remembered in the profile comes back once both windows exist (both build lazily)
    if db.dock and B.UI.Windows[db.dock.with] then
      win:DockWith(B.UI.Windows[db.dock.with], db.dock.side)
    end
    for _, other in pairs(B.UI.Windows) do
      if other ~= win and other.db.dock and other.db.dock.with == name and not other.dock then
        other:DockWith(win, other.db.dock.side)
      end
    end
  end
  return win
end

-- ---------------------------------------------------------------------------------------------
-- Dock (ADR 0013 E): two windows side by side at one height, remembered in the profile
-- ---------------------------------------------------------------------------------------------

-- Docks this window beside `other` ("right": its left edge on the other's right edge, "left": the
-- mirror), at the other's height; the other window leads, this one follows its moves and its
-- height. `db.dock` remembers it; the windowed place stays in the db for the undock.
function Window:DockWith(other, side)
  if not other or other == self then
    return false
  end
  side = side == "left" and "left" or "right"
  if self.full then
    self:SetFullScreen(false)
  end
  if other.full then
    other:SetFullScreen(false)
  end
  if other.dock then
    other:Undock() -- no chains: a window either leads or follows
  end
  self.dock = { with = other, side = side }
  self.db.dock = { with = other.name, side = side }
  other.followers = other.followers or {}
  other.followers[self] = true
  self:PlaceDocked()
  self:FitDocked()
  return true
end

-- The docked pair fits the screen (a map as wide as the screen left no
-- room for the Browser): the leader narrows down to its minimum width, then the follower; then the
-- leader moves so that both lie on the screen. The leader keeps its new place and size.
function Window:FitDocked()
  local d = self.dock
  if not d then
    return
  end
  local lead, f = d.with.frame, self.frame
  local screen = UIParent:GetWidth()
  local lw, fw = lead:GetWidth() or 0, f:GetWidth() or 0
  if not (screen and screen > 0 and lw > 0 and fw > 0) then
    return
  end
  local excess = lw + DOCK_GAP + fw - screen
  if excess > 0 then
    local leadMin = d.with.opts.minWidth or DEFAULTS.minWidth
    local cut = math.min(excess, math.max(0, lw - leadMin))
    lw, excess = lw - cut, excess - cut
    if cut > 0 then
      lead:SetWidth(lw)
    end
    if excess > 0 then
      fw = math.max(self.opts.minWidth or DEFAULTS.minWidth, fw - excess)
      f:SetWidth(fw)
    end
  end
  local left, top = lead:GetLeft(), lead:GetTop()
  if not (left and top) then
    return
  end
  -- the pair's left edge, and where the leader must stand for the pair to fit
  local pairLeft = d.side == "left" and left - DOCK_GAP - fw or left
  local fitLeft = math.max(0, math.min(pairLeft, screen - (lw + DOCK_GAP + fw)))
  if fitLeft ~= pairLeft then
    lead:ClearAllPoints()
    lead:SetPoint("TOPLEFT", UIParent, "TOPLEFT", left + fitLeft - pairLeft, top - UIParent:GetHeight())
  end
  d.with:SavePlace()
end

-- Locked: the header does not drag, the grip hides, the pin shows it (`opts.lockable` windows).
function Window:SetLocked(on)
  self.db.locked = on and true or nil
  if self.grip then
    self.grip:SetShown(not on)
  end
  if self.lock then
    self.lock.spec.on = on and true or nil
    self.lock:SetLabel(on and L["Locked"] or L["Lock"])
    self.lock.tip = on and L["Locked in place: click to free the window"]
      or L["Lock the window in place (no move, no resize)"]
  end
  return on
end

-- The content refresh after a size change: at once when `sizing` is false, else at most once per
-- RESIZE_COALESCE while the grip (this window's or the leader's) is held.
function Window:ResizeContent(sizing)
  local frame, onResize = self.frame, self.opts.onResize
  if not (frame:IsShown() and onResize) then
    return
  end
  if not sizing then
    onResize(self, false)
    return
  end
  if self.resizePending then
    return
  end
  self.resizePending = true
  C_Timer.After(RESIZE_COALESCE, function()
    self.resizePending = nil
    if (self.sizing or self.followSizing) and frame:IsShown() then
      onResize(self, true)
    end
  end)
end

-- Places a docked window beside its leader at the leader's height. `sizing`: the leader's grip is
-- held, so the content follows coalesced; false or nil: one full refresh now.
function Window:PlaceDocked(sizing)
  local d = self.dock
  if not d then
    return
  end
  local f, lead = self.frame, d.with.frame
  self.followSizing = sizing or nil
  self.placing = true
  f:ClearAllPoints()
  if d.side == "left" then
    f:SetPoint("TOPRIGHT", lead, "TOPLEFT", -DOCK_GAP, 0)
  else
    f:SetPoint("TOPLEFT", lead, "TOPRIGHT", DOCK_GAP, 0)
  end
  f:SetHeight(lead:GetHeight())
  self.placing = nil
  self:ResizeContent(sizing)
end

-- The followers take this window's height after every size change.
function Window:SizeFollowers(sizing)
  for follower in pairs(self.followers or {}) do
    if follower.dock and follower.dock.with == self then
      follower:PlaceDocked(sizing)
    end
  end
end

function Window:IsDocked()
  return self.dock ~= nil
end

-- Pins the window at the place it is seen: one TOPLEFT point on UIParent, so a move or a size
-- starts from there whatever its anchors were (a partner, the centre, a clamped place).
function Window:AnchorAtSight()
  local f = self.frame
  local left, top = f:GetLeft(), f:GetTop()
  if left and top then
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
  end
end

-- Back to the windowed place; followers of this window are released too. `inPlace` (the Dock
-- button, a drag): the window stays where it stands at its docked size, fitted onto the screen
-- (undocking from the button "scales large and strangely from top to
-- bottom": it jumped to an old place and size, or to the screen's centre at the default size).
function Window:Undock(inPlace)
  for follower in pairs(self.followers or {}) do
    if follower.dock and follower.dock.with == self then
      follower:Undock(inPlace)
    end
  end
  local d = self.dock
  if not d then
    return
  end
  self.dock = nil
  self.db.dock = nil
  if d.with.followers then
    d.with.followers[self] = nil
  end
  if inPlace then
    self:AnchorAtSight()
    self:SavePlace()
    self:FitScreen()
  else
    self:RestorePlace()
  end
  if not self.db.size then
    self.frame:SetSize(self.opts.width or DEFAULTS.width, self.opts.height or DEFAULTS.height)
  end
  if self.frame:IsShown() and self.opts.onResize then
    self.opts.onResize(self, false)
  end
end

-- The Dock button of the pair (the map and the Browser): docks the right window to the left one,
-- opening what is missing through its module; a second press undocks. Returns the new state.
-- A pair still docked but with one window closed by hand docks again with both shown (owner,
-- Forever 07.11.2026: "I close it by hand, the next Dock does nothing - it still thinks it's open").
function B.UI.ToggleDock()
  local rightWin = B.UI.Windows[B.UI.DOCK.right]
  local leftWin = B.UI.Windows[B.UI.DOCK.left]
  if rightWin and rightWin.dock and rightWin:IsShown() and leftWin and leftWin:IsShown() then
    rightWin:Undock(true)
    return false
  end
  for _, name in ipairs({ B.UI.DOCK.left, B.UI.DOCK.right }) do
    local win = B.UI.Windows[name]
    if not (win and win:IsShown()) then
      local mod = B:GetModule(B.UI.DOCK_MODULES[name])
      if not (mod and mod:IsEnabled() and type(mod.def.open) == "function") then
        B:Say(L["Dock needs both the map and the Browser."])
        return false
      end
      if not win then
        mod.def.open() -- builds the window (it opens on its home or the player's map)
      else
        win:Show()
      end
    end
  end
  leftWin = B.UI.Windows[B.UI.DOCK.left]
  rightWin = B.UI.Windows[B.UI.DOCK.right]
  if not (leftWin and rightWin) then
    return false
  end
  return rightWin:DockWith(leftWin, "right")
end

function B.UI.IsDocked()
  local rightWin = B.UI.Windows[B.UI.DOCK.right]
  return rightWin ~= nil and rightWin.dock ~= nil
end

-- Position as TOPLEFT offset from UIParent's TOPLEFT and the size, into the window's db.
function Window:SavePlace()
  if self.full or self.dock then
    return -- the windowed place stays what it was
  end
  local f = self.frame
  local left, top = f:GetLeft(), f:GetTop()
  if left and top then
    local scale = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    self.db.pos = { left * scale, (top - UIParent:GetHeight() / scale) * scale }
  end
  self.db.size = { f:GetWidth(), f:GetHeight() }
end

-- True while the resize grip is held: a size change then is one of many per second.
function Window:IsSizing()
  return self.sizing == true
end

function Window:IsFullScreen()
  return self.full ~= nil
end

-- Full screen: the frame covers UIParent (the resize bounds are lifted for it), the windowed
-- place and size stay in the db and come back on the way out; `db.full` remembers the mode.
function Window:SetFullScreen(on)
  local f, opts = self.frame, self.opts
  if on and (self.dock or next(self.followers or {})) then
    self:Undock() -- full screen undocks (ADR 0013 E)
  end
  if on and not self.full then
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    self.full = { w, h }
    self.db.full = true
    resizeBounds(f, opts, w, h)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    f:SetSize(w, h)
    self.grip:Hide()
  elseif not on and self.full then
    self.full = nil
    self.db.full = nil
    resizeBounds(f, opts)
    self.grip:Show()
    self:RestorePlace()
    if not self.db.size then
      f:SetSize(opts.width or DEFAULTS.width, opts.height or DEFAULTS.height)
    end
  end
  if f:IsShown() and opts.onResize then
    opts.onResize(self, false)
  end
end

function Window:ToggleFullScreen()
  self:SetFullScreen(not self.full)
end

-- A saved size never exceeds the screen and a saved place stays on it (
-- the book taller than the screen after a UI scale change, the grip out of reach).
Window.SCREEN_MARGIN = 20
function Window:FitScreen()
  local f = self.frame
  local sw, sh = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
  if sw <= 0 or sh <= 0 then
    return
  end
  local w, h = f:GetWidth() or 0, f:GetHeight() or 0
  local maxW, maxH = sw - 2 * Window.SCREEN_MARGIN, sh - 2 * Window.SCREEN_MARGIN
  if w > maxW or h > maxH then
    w, h = math.min(w, maxW), math.min(h, maxH)
    f:SetSize(w, h)
    if self.db.size then
      self.db.size = { w, h }
    end
  end
  local pos = self.db.pos
  if pos then
    -- pos: the left edge, and the top edge as a negative offset from the screen's top
    local left = math.max(0, math.min(pos[1] or 0, sw - w))
    local top = math.min(0, math.max(pos[2] or 0, -(sh - h)))
    if left ~= pos[1] or top ~= pos[2] then
      self.db.pos = { left, top }
      f:ClearAllPoints()
      f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", left, top)
    end
  end
end

function Window:RestorePlace()
  local f = self.frame
  f:ClearAllPoints()
  local pos = self.db.pos
  if pos then
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", pos[1], pos[2])
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
  if self.db.size then
    f:SetSize(self.db.size[1], self.db.size[2])
  end
  self:FitScreen()
end

-- Above other addons' windows, which sit on DIALOG or below (some covered the
-- map), and above the world map when it is drawn full screen; tooltips and menus stay above us.
Window.STRATA = "FULLSCREEN_DIALOG"
B.UI.WINDOW_STRATA = Window.STRATA -- for the few windows the factory does not build
-- `opts.onTop` ("the route window should be a high layer on top of all
-- others"): the strata of the tooltips and menus, at its lowest level and never raised, so they
-- still come over it (the menus raise themselves; the kit's tooltip too, S.TipEnter), while every
-- other window, the game's dialogs and the full-screen map stay under it.
Window.TOP_STRATA = "TOOLTIP"

function Window:PlaceStrata()
  if self.opts.onTop then
    self.frame:SetFrameStrata(Window.TOP_STRATA)
    self.frame:SetFrameLevel(1)
    return
  end
  self.frame:SetFrameStrata(self.opts.strata or Window.STRATA)
  self.frame:Raise()
end

-- The background colour and opacity of Core's settings (R27.2), the same for every window, unless
-- the window's app set its own (`windowColor` and `windowAlpha` in the app's
-- profile, nil means the General setting); the header stays opaque, a title over the world reads
-- badly.
function Window:ApplyLook()
  local core = ns.core and ns.core.db and ns.core.db.profile
  local app = self.opts.module and ns.modules[self.opts.module]
  local own = app and app.db and app.db.profile or nil
  local c = own and own.windowColor or (core and core.windowColor)
  local color = S.Tok(self.frame, "bg")
  if type(c) == "table" and tonumber(c[1]) and tonumber(c[2]) and tonumber(c[3]) then
    color = c
  end
  local alpha = own and tonumber(own.windowAlpha) or (core and tonumber(core.windowAlpha)) or 100
  local a = math.max(0.2, math.min(1, alpha / 100))
  local cap = S.LookGroundAlpha and S.LookGroundAlpha() or nil -- Glass: 75 % at most (ADR 0046)
  if cap then
    a = math.min(a, cap / 100)
  end
  if self.frame.bg then
    S.tint(self.frame.bg, color, a)
  end
  -- the game's grounds follow the opacity too: the rock of its window, the marble or parchment
  -- of its insets
  S.insetAlpha = a
  self:ApplyFrame()
  if self.chrome and self.chrome.Bg then
    self.chrome.Bg:SetAlpha(a)
  end
end

-- The game's own window behind ours (, "a clearly skinned style according
-- to Blizzard examples"): the client's PortraitFrameTemplate with its metal frame, rock ground,
-- the title in its bar, its red close button and the app's icon as the round portrait; our header
-- moves into the band beside the portrait, the content below it.
Window.CHROME_TOP = 56 -- the title bar and the band beside the portrait
Window.CHROME_SIDE = 6
Window.PORTRAIT_X = 58 -- the band starts right of the portrait
function Window:PortraitIcon()
  if self.opts.portrait then
    return self.opts.portrait
  end
  local app = self.opts.module and ns.modules[self.opts.module]
  local addon = app and app.addon or "Bastians_Core"
  return "Interface\\AddOns\\" .. addon .. "\\Icon"
end

function Window:Chrome()
  if self.chrome == nil then
    local chrome = B.Compat.NewGameWindow(self.frame)
    self.chrome = chrome or false
    if chrome then
      chrome:SetAllPoints(self.frame)
      chrome:SetFrameLevel(self.frame:GetFrameLevel() or 1)
      chrome.CloseButton:SetScript("OnClick", function()
        -- the app's own close where it set one (Bastian's Chat: the tabs go back to the main
        -- window; the red button only hid the window)
        local own = self.close:GetScript("OnClick")
        if own then
          own(self.close)
        else
          self:Hide()
        end
      end)
      chrome:SetPortraitToAsset(self:PortraitIcon())
      chrome:SetTitle(self.title:GetText() or "")
    end
  end
  return self.chrome or nil
end

-- The insets around the content, for windows that size themselves to it: top (header included),
-- side, bottom in px.
function Window:Insets()
  if self.gameFramed then
    return Window.CHROME_TOP, Window.CHROME_SIDE, Window.CHROME_SIDE
  end
  local inset = self.framed and Window.FRAME_INSET or 1
  return HEADER_H + inset, inset, inset
end

function Window:ApplyChrome()
  local on = (self.opts.gameFrames or S.GameFrames()) and self:Chrome() ~= nil
  if self.chrome then
    self.chrome:SetShown(on)
  end
  if self.gameFramed == on then
    return on
  end
  self.gameFramed = on
  local head, frame = self.head, self.frame
  head:ClearAllPoints()
  self.content:ClearAllPoints()
  if on then
    head:SetPoint("TOPLEFT", frame, "TOPLEFT", Window.PORTRAIT_X, -22)
    head:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -Window.CHROME_SIDE, -22)
    self.content:SetPoint("TOPLEFT", frame, "TOPLEFT", Window.CHROME_SIDE, -Window.CHROME_TOP)
    self.content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -Window.CHROME_SIDE, Window.CHROME_SIDE)
  else
    head:SetPoint("TOPLEFT", 1, -1)
    head:SetPoint("TOPRIGHT", -1, -1)
    self.content:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, 0)
    self.content:SetPoint("BOTTOMRIGHT", -1, 1)
    self.framed = nil -- ApplyFrame places them again
  end
  head:SetHeight(on and 32 or HEADER_H)
  for _, part in ipairs({ frame.bg, frame.edges, head.bg, self.title, self.close }) do
    S.showPart(part, not on)
  end
  return on
end

-- The game's window frame (the skin's `skinFrames`, ADR 0034): the dialog border over the window's
-- edge, the header, content and grip moved in by FRAME_INSET, the round outline hidden. Without
-- the client's backdrop the window keeps its flat look.
Window.FRAME_INSET = 9
function Window:ApplyFrame()
  if self:ApplyChrome() then
    if self.border then
      self.border:Hide()
    end
    return
  end
  local on = S.Skin("skinFrames") == true
  local border = self.border
  if on and not border then
    border = B.Compat.NewBackdrop(self.frame)
    if border then
      border:SetAllPoints(self.frame)
      border:SetFrameLevel((self.frame:GetFrameLevel() or 1) + 40) -- over the content's edge
      self.border = border
    end
  end
  on = on and border ~= nil
  if border then
    -- the flat ground (the theme's colour and opacity) stays inside the border under every preset
    -- (ADR 0038: the Azeroth scheme's ground is the quest frame's parchment)
    if not border.dressed then
      border.dressed = true
      border:SetBackdrop({ edgeFile = S.FRAME_BORDER, edgeSize = 32 })
    end
    border:SetShown(on)
  end
  if self.framed == on then
    return
  end
  self.framed = on
  local inset = on and Window.FRAME_INSET or 1
  self.head:ClearAllPoints()
  self.head:SetPoint("TOPLEFT", inset, -inset)
  self.head:SetPoint("TOPRIGHT", -inset, -inset)
  self.content:SetPoint("BOTTOMRIGHT", -inset, inset)
  self.grip:ClearAllPoints()
  self.grip:SetPoint("BOTTOMRIGHT", -inset, inset)
  if self.frame.edges then
    if on then
      self.frame.edges:Hide()
    else
      self.frame.edges:Show()
    end
  end
end

function B.UI.ApplyWindowLook()
  for _, win in pairs(B.UI.Windows) do
    win:ApplyLook()
  end
end

function Window:SetTitle(text)
  self.title:SetText(text)
  if self.chrome then
    self.chrome:SetTitle(text or "")
  end
end
-- Opens the window, and brings one already open to the front ("every
-- window that is newly opened should always be on top of all others").
function Window:Show()
  if self.frame:IsShown() then
    self:PlaceStrata()
  else
    self.frame:Show()
  end
end
function Window:Hide()
  self.frame:Hide()
end
function Window:Toggle()
  if self.frame:IsShown() then
    self.frame:Hide()
  else
    self.frame:Show()
  end
end
function Window:IsShown()
  return self.frame:IsShown()
end

B.UI.L_CLOSE = L["Close"]

-- ---------------------------------------------------------------------------------------------
-- The game's interaction panels come first (, severe: with the Gold
-- window open, the vendor's "I want to browse your goods" could not be clicked; our windows sit
-- above every game panel). While a gossip, merchant, quest, trainer, mail, bank, auction or taxi
-- panel shows, a window of ours that overlaps it steps to the panel's right; it goes back when
-- the panel closes, unless the player moved it meanwhile. Docked followers go with their leader,
-- a full-screen window stays.
-- ---------------------------------------------------------------------------------------------

Window.PANELS = {
  "GossipFrame",
  "MerchantFrame",
  "QuestFrame",
  "ClassTrainerFrame",
  "MailFrame",
  "BankFrame",
  "AuctionHouseFrame",
  "TaxiFrame",
  "FlightMapFrame", -- the retail family's flight map
}
local PANEL_SHOW = {
  "GOSSIP_SHOW",
  "MERCHANT_SHOW",
  "QUEST_DETAIL",
  "QUEST_GREETING",
  "QUEST_PROGRESS",
  "QUEST_COMPLETE",
  "TRAINER_SHOW",
  "MAIL_SHOW",
  "BANKFRAME_OPENED",
  "AUCTION_HOUSE_SHOW",
  "TAXIMAP_OPENED",
}
local PANEL_HIDE = {
  "GOSSIP_CLOSED",
  "MERCHANT_CLOSED",
  "QUEST_FINISHED",
  "TRAINER_CLOSED",
  "MAIL_CLOSED",
  "BANKFRAME_CLOSED",
  "AUCTION_HOUSE_CLOSED",
  "TAXIMAP_CLOSED",
}

-- The game panels shown now.
function Window.ShownPanels()
  local out = {}
  for _, name in ipairs(Window.PANELS) do
    local f = rawget(_G, name)
    if type(f) == "table" and f.IsShown and f:IsShown() then
      out[#out + 1] = f
    end
  end
  return out
end

-- Do two frames overlap on the screen (their own scales taken into account)?
local function overlaps(a, b)
  local al, ar, at, ab = a:GetLeft(), a:GetRight(), a:GetTop(), a:GetBottom()
  local bl, br, bt, bb = b:GetLeft(), b:GetRight(), b:GetTop(), b:GetBottom()
  if not (al and ar and at and ab and bl and br and bt and bb) then
    return false
  end
  local sa, sb = a:GetEffectiveScale() or 1, b:GetEffectiveScale() or 1
  return al * sa < br * sb and ar * sa > bl * sb and ab * sa < bt * sb and at * sa > bb * sb
end

-- Steps every overlapping window of ours aside (`win.dodged` keeps its points for the way back).
function Window.Dodge()
  local panels = Window.ShownPanels()
  if #panels == 0 then
    return
  end
  for _, win in pairs(B.UI.Windows) do
    local f = win.frame
    if f:IsShown() and not win.dock and not win.full and not win.dodged then
      for _, panel in ipairs(panels) do
        if overlaps(f, panel) then
          local points = {}
          for i = 1, f:GetNumPoints() do
            points[i] = { f:GetPoint(i) }
          end
          win.dodged = points
          f:ClearAllPoints()
          f:SetPoint("TOPLEFT", panel, "TOPRIGHT", 8, 0)
          break
        end
      end
    end
  end
end

-- Puts the windows back once no game panel shows.
function Window.Return()
  if #Window.ShownPanels() > 0 then
    return
  end
  for _, win in pairs(B.UI.Windows) do
    local points = win.dodged
    if points then
      win.dodged = nil
      local f = win.frame
      f:ClearAllPoints()
      for _, p in ipairs(points) do
        f:SetPoint(unpack(p))
      end
    end
  end
end

local panelWatch = CreateFrame("Frame")
for _, event in ipairs(PANEL_SHOW) do
  panelWatch:RegisterEvent(event)
end
for _, event in ipairs(PANEL_HIDE) do
  panelWatch:RegisterEvent(event)
end
local hideEvent = {}
for _, event in ipairs(PANEL_HIDE) do
  hideEvent[event] = true
end
panelWatch:SetScript("OnEvent", function(_, event)
  -- the game shows or hides its panel in the same event: look one frame later
  C_Timer.After(0, hideEvent[event] and Window.Return or Window.Dodge)
end)
