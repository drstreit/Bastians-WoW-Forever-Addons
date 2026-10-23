-- UI kit: Bastians.UI.Window(name, opts): movable, resizable, flat window with a header, close button,
-- resize grip, saved position and size, placed above the world map; ESC closes it (core-contracts §13).
local _, ns = ...
local B = ns.B
local S = ns.Style
local L = ns.L

local HEADER_H = 30
local DEFAULTS =
  { width = 420, height = 520, minWidth = 300, minHeight = 240, maxWidth = 1200, maxHeight = 1200 }

local Window = {}
Window.__index = Window

-- Every window by frame name (ADR 0013 E: the dock needs to find its partner), and the dock pair:
-- the map left, the Browser right. `B.UI.DOCK_MODULES` names the module that opens each window.
B.UI.Windows = {}
B.UI.DOCK = { left = "BastiansMapFrame", right = "BastiansBrowserFrame" }
B.UI.DOCK_MODULES = { BastiansMapFrame = "Map", BastiansBrowserFrame = "Browser" }
local DOCK_GAP = 2
local RESIZE_COALESCE = 0.1 -- seconds between content refreshes while the grip is held
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
    if win.dock then
      win:Undock() -- dragging a docked window away undocks it
    end
    win.frame:SetClampedToScreen(false)
    win.frame:StartMoving()
  end)
  region:SetScript("OnDragStop", function()
    win.frame:StopMovingOrSizing()
    win.frame:SetClampedToScreen(true)
    win.dodged = nil -- moved by hand: this is its place now, nothing to restore
    win:SavePlace()
  end)
end

-- opts: { title, width, height, minWidth, minHeight, maxWidth, maxHeight, db (table for pos and size),
--         onShow(win), onHide(win), onResize(win), escape (default true) }
function B.UI.Window(name, opts)
  opts = opts or {}
  local db = opts.db or {}
  local frame = CreateFrame("Frame", name, UIParent)
  local win = setmetatable({ frame = frame, name = name, db = db, opts = opts }, Window)

  local size = db.size or { opts.width or DEFAULTS.width, opts.height or DEFAULTS.height }
  frame:SetSize(size[1], size[2])
  frame:SetFrameStrata(Window.STRATA)
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:SetResizable(true)
  frame:SetResizeBounds(
    opts.minWidth or DEFAULTS.minWidth,
    opts.minHeight or DEFAULTS.minHeight,
    opts.maxWidth or DEFAULTS.maxWidth,
    opts.maxHeight or DEFAULTS.maxHeight
  )
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
    self:Raise()
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

  win.title = S.text(head, 15, S.C.text)
  win.title:SetPoint("LEFT", 10, 0)
  win.title:SetPoint("RIGHT", -34, 0)
  win.title:SetText(opts.title or name)

  win.close = S.button(head, "x", 22, 20)
  win.close.tip = L["Close (Escape)"]
  win.close:SetPoint("RIGHT", -6, 0)
  win.close:SetScript("OnClick", function()
    frame:Hide()
  end)

  -- content area: apps anchor their widgets here
  local content = CreateFrame("Frame", nil, frame)
  content:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, 0)
  content:SetPoint("BOTTOMRIGHT", -1, 1)
  win.content = content

  -- resize grip, bottom right
  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(12, 12)
  grip:SetPoint("BOTTOMRIGHT", -1, 1)
  grip:SetFrameLevel((content:GetFrameLevel() or 1) + 2)
  local gripTex = S.fill(grip, S.C.accent, "OVERLAY")
  gripTex:SetAlpha(0.5)
  grip:SetScript("OnMouseDown", function()
    win.sizing = true
    -- a docked window keeps its partner's height: the grip changes its width only, and the
    -- pair stays docked
    local d = win.dock
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
  return true
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

-- Back to the windowed place; followers of this window are released too.
function Window:Undock()
  for follower in pairs(self.followers or {}) do
    if follower.dock and follower.dock.with == self then
      follower:Undock()
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
  self:RestorePlace()
  if not self.db.size then
    self.frame:SetSize(self.opts.width or DEFAULTS.width, self.opts.height or DEFAULTS.height)
  end
  if self.frame:IsShown() and self.opts.onResize then
    self.opts.onResize(self, false)
  end
end

-- The Dock button of the pair (the map and the Browser): docks the right window to the left one,
-- opening what is missing through its module; a second press undocks. Returns the new state.
function B.UI.ToggleDock()
  local rightWin = B.UI.Windows[B.UI.DOCK.right]
  if rightWin and rightWin.dock then
    rightWin:Undock()
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
  local leftWin = B.UI.Windows[B.UI.DOCK.left]
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
    f:SetResizeBounds(
      opts.minWidth or DEFAULTS.minWidth,
      opts.minHeight or DEFAULTS.minHeight,
      math.max(w, opts.maxWidth or DEFAULTS.maxWidth),
      math.max(h, opts.maxHeight or DEFAULTS.maxHeight)
    )
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    f:SetSize(w, h)
    self.grip:Hide()
  elseif not on and self.full then
    self.full = nil
    self.db.full = nil
    f:SetResizeBounds(
      opts.minWidth or DEFAULTS.minWidth,
      opts.minHeight or DEFAULTS.minHeight,
      opts.maxWidth or DEFAULTS.maxWidth,
      opts.maxHeight or DEFAULTS.maxHeight
    )
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
end

-- Above other addons' windows, which sit on DIALOG or below (some covered the
-- map), and above the world map when it is drawn full screen; tooltips and menus stay above us.
Window.STRATA = "FULLSCREEN_DIALOG"

function Window:PlaceStrata()
  self.frame:SetFrameStrata(Window.STRATA)
  self.frame:Raise()
end

function Window:SetTitle(text)
  self.title:SetText(text)
end
function Window:Show()
  self.frame:Show()
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
