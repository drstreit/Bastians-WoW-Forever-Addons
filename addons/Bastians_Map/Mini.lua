-- Bastian's minimap:
-- the game's minimap taken into a frame of ours with a search bar on top, the zone and coordinates
-- and a row of tools below. The style "game" (the default) shows the game's live minimap with our
-- pins; the map's styles are drawn by our renderer (the tile layers of Tiles.lua on a camera of
-- its own) and lose what only the client can draw, which a warning says once. Mouse wheel zooms,
-- dragging pans, Recentre comes back, Alt+drag moves the frame, Alt+wheel sizes it. The game's
-- indicators (mail, tracking, calendar, clock, ...) move into the tools row. Nothing is moved in
-- combat (CLAUDE.md golden rule 6); everything goes back when the setting is off.
-- The search on top finds only what the minimap shows and marks the place it jumps to (map.md
-- "The minimap search", L4, ): a quest's mark is its giver.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Map = ns.Map
local Camera = ns.Camera
local Tiles = ns.Tiles

local Mini = {}
ns.Mini = Mini

Mini.SIZE_MIN, Mini.SIZE_MAX, Mini.SIZE_STEP = 120, 400, 10
Mini.LEVEL_MIN, Mini.LEVEL_MAX, Mini.LEVEL_STEP = 2, 7, 0.5
Mini.BAR_H, Mini.FOOT_H, Mini.TOOLS_H, Mini.GAP = 22, 14, 22, 2
Mini.TICK = 0.25 -- seconds between full redraws while the player moves (positions follow per frame)
Mini.WATCH = 1 -- seconds between the looks where the player is, while shown (ADR 0066)
Mini.MOVED = 1 -- yards that count as having moved
Mini.DRAG_PX = 3
Mini.BORDER = 5 -- pixels of the frame around the view -- a press that moves less is a click
Mini.MASKS = {
  ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask",
  SQUARE = "Interface\\Buttons\\WHITE8X8",
}
-- The game's indicators taken into the tools row, by the names both clients may use (retail
-- family; Forever's names assumed until checked in game, map.md checklist).
Mini.INDICATORS = {
  { "MinimapCluster", "IndicatorFrame" }, -- mail and crafting orders (retail)
  { "MiniMapMailFrame" },
  { "GameTimeFrame" }, -- the calendar
  { "TimeManagerClockButton" },
  { "MinimapCluster", "InstanceDifficulty" },
  { "MiniMapInstanceDifficulty" },
  { "ExpansionLandingPageMinimapButton" },
  { "MiniMapBattlefieldFrame" },
  { "MiniMapLFGFrame" },
  -- the game's tracking menu (, undoing R28.15: Find Herbs and Find Minerals are
  -- switched on there, and only the game's minimap shows what they find; Tracked.lua reads it back)
  { "MinimapCluster", "Tracking" },
  { "MiniMapTracking" },
}
-- The game's minimap art and buttons that would float without the cluster: parked while ours shows.
Mini.HIDE = {
  { "Minimap", "ZoomIn" },
  { "Minimap", "ZoomOut" },
  { "MinimapZoomIn" },
  { "MinimapZoomOut" },
  { "MinimapBorder" },
  { "MinimapBorderTop" },
  { "MinimapCompassTexture" },
  { "MiniMapWorldMapButton" },
  -- the number of addons in the compartment: no value
  { "AddonCompartmentFrame" },
  -- the suite's own button: the badge on the frame stands in for it
  { "BastiansMinimapButton" },
  { "LibDBIcon10_Bastians" }, -- the same, made by LibDBIcon when another addon loaded it (ADR 0043)
}
Mini.BADGE = 34 -- the Bastian's badge on the frame (the one button on the minimap)
Mini.OPENER = 26 -- the button of the minimap buttons' box on the rim, bottom left
Mini.ICON = "Interface\\AddOns\\Bastians_Core\\Icon"
-- The entity types the minimap's search offers (map.md "The minimap search"); notes on a spot and
-- the bookmarks come without an entity and are kept by their place.
Mini.SEARCH_SCOPE = { npc = true, quest = true, zone = true, area = true }
Mini.SPOT_LAYER = "notes.spots" -- the layer whose pins are the player's notes on a spot (Notes)
Mini.MARK_SECONDS = 120 -- the search's mark goes after this long
Mini.FAR = 1e9 -- yards: a view that holds a whole continent

local mod
local frame, bar, view, clip, catcher, arrow, foot, tools, recentre, warn
local cam
local following = true -- the view keeps the player in the middle until dragged
local moving, drag = false, nil
local drifting = false -- the player is moved without a movement event (a boat, a knockback; ADR 0066)
local watch -- the timer of the looks
local watched, ticked = {}, {} -- where the player was at the last look, at the last tick
local elapsed = 0
local taken -- what was moved: { minimap = state, cluster = state, indicators = { ... }, hidden = { ... } }
local hider -- a hidden frame that holds the game's cluster while ours shows
local pending -- a take or give back waiting for the end of combat
local markTimer -- the mark's timeout
local hookMinimap -- defined with the takeover below
Mini.stats = { drawn = 0, indicators = 0 }

local function layer(sublevel)
  return { live = {}, free = {}, stats = { shown = 0, wanted = 0, skipped = 0 }, sublevel = sublevel }
end
Mini.layers = {
  overview = layer(1), -- Map Art's cells (physical)
  native = layer(2), -- the native minimap tiles (physical)
  far = layer(1), -- Bastian's styles
  near = layer(2),
}

local function db()
  return mod.db.profile
end

function Mini.Enabled()
  return mod ~= nil and mod:IsEnabled() and db().miniMap ~= false
end

function Mini.Frame()
  return frame
end

function Mini.View()
  return view
end

function Mini.Camera()
  return cam
end

function Mini.Following()
  return following
end

-- ---------------------------------------------------------------------------------------------
-- Styles
-- ---------------------------------------------------------------------------------------------

-- "game" first, then the big map's styles that exist here, Blizzard's paintings left out: at a
-- minimap's zoom they show no detail, and "Game minimap" beside "Blizzard" confused (owner, retail
-- 28.10.2026).
function Mini.StyleList()
  local out = { "game" }
  for _, style in ipairs(Map.StyleList()) do
    if style ~= "blizzard" then
      out[#out + 1] = style
    end
  end
  return out
end

function Mini.StyleTitle(style)
  if style == "game" then
    return L["Game minimap"]
  end
  return Map.StyleTitle(style)
end

-- The style chosen, or "game" when it is unknown here (its addon gone).
function Mini.Style()
  local style = mod and db().miniStyle or "game"
  for _, known in ipairs(Mini.StyleList()) do
    if known == style then
      return style
    end
  end
  return "game"
end

-- Switches the style; the first switch away from the game's minimap asks once, since only the
-- game's minimap shows tracked herbs and ore, group members and quest areas.
function Mini.SetStyle(style)
  if not mod then
    return
  end
  if style ~= "game" and not db().miniWarned then
    Mini.Warn(style)
    return
  end
  db().miniStyle = style
  B:Fire("BASTIANS_SETTING_CHANGED", mod.name, "miniStyle", style)
end

-- The one-time warning: what the player loses with one of our styles.
function Mini.Warn(style)
  if not warn then
    warn = B.UI.Window("BastiansMiniWarning", {
      title = L["Bastian's minimap"],
      width = 380,
      height = 190,
      minWidth = 380,
      minHeight = 190,
      db = {},
    })
    warn.text = S.text(warn.content, 12, S.C.text)
    warn.text:SetPoint("TOPLEFT", 12, -10)
    warn.text:SetPoint("TOPRIGHT", -12, -10)
    warn.text:SetJustifyH("LEFT")
    local text = "Bastian's styles show the herbs, ore and creatures you track and the map's layers (quests,"
      .. " NPCs, your route). Only the game's own minimap shows your group, quest areas and server pings."
    warn.text:SetText(L[text])
    warn.ok = S.action(warn.content, { icon = "check", label = L["Switch"], primary = true })
    warn.ok:SetPoint("BOTTOMRIGHT", -12, 12)
    warn.cancel = S.action(warn.content, { icon = "close", label = L["Keep the game's"], boxed = true })
    warn.cancel:SetPoint("RIGHT", warn.ok, "LEFT", -8, 0)
    warn.cancel:SetScript("OnClick", function()
      warn:Hide()
    end)
  end
  warn.ok:SetScript("OnClick", function()
    db().miniWarned = true
    warn:Hide()
    Mini.SetStyle(warn.style)
  end)
  warn.style = style
  warn:Show()
  return warn
end

function Mini.Warning()
  return warn
end

-- ---------------------------------------------------------------------------------------------
-- The game's frames: taken into ours, given back
-- ---------------------------------------------------------------------------------------------

-- A frame by its global name and its parent keys; nil when this client has none (a parent key is a
-- plain field of the frame's table: rawget reads it without the frame's methods).
local function resolve(path)
  local f = rawget(_G, path[1])
  for i = 2, #path do
    f = type(f) == "table" and rawget(f, path[i]) or nil
  end
  if type(f) == "table" and f.GetParent then
    return f
  end
  return nil
end

local function stateOf(f)
  local points = {}
  for i = 1, f:GetNumPoints() do
    points[i] = { f:GetPoint(i) }
  end
  return {
    frame = f,
    parent = f:GetParent(),
    points = points,
    scale = f.GetScale and f:GetScale() or 1,
    w = f:GetWidth(),
    h = f:GetHeight(),
    shown = f:IsShown(),
  }
end

local function restore(st)
  local f = st.frame
  f:SetParent(st.parent)
  f:ClearAllPoints()
  for _, p in ipairs(st.points) do
    f:SetPoint(unpack(p))
  end
  if f.SetScale then
    f:SetScale(st.scale or 1)
  end
  if st.w and st.h and st.sized then
    f:SetSize(st.w, st.h)
  end
  if st.shown then
    f:Show()
  end
end

local function deferred(fn)
  if InCombatLockdown() then
    pending = fn -- the last wish wins
    return false
  end
  fn()
  return true
end

local placing = false

-- The game's minimap at the view's centre and size. Its own size, not two anchors: the game draws
-- its terrain for the size it is given (Alt+wheel in the game style only
-- shifted the map, and an old larger minimap showed beside the view in our styles).
function Mini.PlaceMinimap()
  if not (taken and view) then
    return
  end
  placing = true
  local size = Mini.Size()
  Minimap:ClearAllPoints()
  Minimap:SetPoint("CENTER", view, "CENTER", 0, 0)
  if (Minimap:GetWidth() or 0) ~= size or (Minimap:GetHeight() or 0) ~= size then
    Minimap:SetSize(size, size)
    -- the terrain follows a new size with the next zoom: one step there and back
    local zoom = Minimap:GetZoom() or 0
    Minimap:SetZoom(zoom > 0 and zoom - 1 or zoom + 1)
    Minimap:SetZoom(zoom)
  end
  placing = false
end

-- Once: the game moving its minimap back (a layout of the cluster) is undone on the next frame;
-- Alt+drag on the game's minimap moves our frame, as on our styles.
local hooked = false
hookMinimap = function()
  if hooked then
    return
  end
  hooked = true
  hooksecurefunc(Minimap, "SetPoint", function()
    if taken and not placing then
      C_Timer.After(0, Mini.PlaceMinimap)
    end
  end)
  Minimap:HookScript("OnMouseDown", function(_, button)
    if taken and button == "LeftButton" and IsAltKeyDown and IsAltKeyDown() then
      frame:StartMoving()
      frame.moving = true
    end
  end)
  Minimap:HookScript("OnMouseUp", function(_, button)
    if frame and frame.moving then
      Mini.StopMoving()
    elseif taken and button == "RightButton" then
      Mini.PointMenu()
    end
  end)
end

-- The game's minimap goes into our view; its cluster waits on a hidden frame; the indicators go
-- into the tools row; the floating art is hidden.
local function take()
  if taken or not (Minimap and frame) then
    return
  end
  taken = { indicators = {}, hidden = {} }
  local st = stateOf(Minimap)
  st.sized = true
  taken.minimap = st
  Minimap:SetParent(view)
  Minimap:SetFrameLevel((view:GetFrameLevel() or 1) + 1)
  if Minimap.SetScale then
    Minimap:SetScale(1) -- the size is ours now, not the game cluster's
  end
  Mini.PlaceMinimap()
  hookMinimap()
  for _, path in ipairs(Mini.INDICATORS) do
    local f = resolve(path)
    if f and f ~= Minimap then
      taken.indicators[#taken.indicators + 1] = stateOf(f)
    end
  end
  hider = hider or CreateFrame("Frame")
  hider:Hide()
  -- parked on the hidden frame, not hidden: the game shows its zoom buttons again on hover
  for _, path in ipairs(Mini.HIDE) do
    local f = resolve(path)
    if f then
      taken.hidden[#taken.hidden + 1] = { frame = f, parent = f:GetParent() }
      f:SetParent(hider)
    end
  end
  local cluster = rawget(_G, "MinimapCluster")
  if cluster and cluster ~= Minimap then
    taken.cluster = stateOf(cluster)
    cluster:SetParent(hider)
  end
  Mini.LayoutTools()
  Mini.ApplyShape()
end

local function giveBack()
  if not taken then
    return
  end
  for _, st in ipairs(taken.indicators) do
    restore(st)
  end
  for _, h in ipairs(taken.hidden) do
    h.frame:SetParent(h.parent)
  end
  if taken.cluster then
    restore(taken.cluster)
  end
  if Minimap.SetMaskTexture then
    Minimap:SetMaskTexture(Mini.MASKS.ROUND)
  end
  restore(taken.minimap)
  taken = nil
  Mini.stats.indicators = 0
end

function Mini.Taken()
  return taken ~= nil
end

-- The tools row centred under the view: our buttons, then
-- the game's indicators, each scaled to the row's height.
function Mini.LayoutTools()
  if not tools then
    return
  end
  local own = { tools.style, tools.layers, tools.map, tools.options, tools.timers, tools.info }
  local width, count = 0, 0
  for _, b in ipairs(own) do
    if b:IsShown() then
      width, count = width + (b:GetWidth() or 20), count + 1
    end
  end
  for _, st in ipairs(taken and taken.indicators or {}) do
    local h = math.max(1, st.h or Mini.TOOLS_H)
    width, count = width + (st.w or Mini.TOOLS_H) * math.min(1, Mini.TOOLS_H / h), count + 1
  end
  width = width + 2 * math.max(0, count - 1)
  local first = true
  local prevOwn
  for _, b in ipairs(own) do
    if b:IsShown() then
      b:ClearAllPoints()
      if first then
        b:SetPoint("LEFT", tools, "CENTER", -width / 2, 0)
        first = false
      else
        b:SetPoint("LEFT", prevOwn, "RIGHT", 2, 0)
      end
      prevOwn = b
    end
  end
  tools.last = prevOwn
  if not taken then
    return
  end
  local prev = tools.last
  local n = 0
  for _, st in ipairs(taken.indicators) do
    local f = st.frame
    f:SetParent(tools)
    f:ClearAllPoints()
    local h = math.max(1, st.h or Mini.TOOLS_H)
    if f.SetScale then
      f:SetScale(math.min(1, Mini.TOOLS_H / h))
    end
    if prev then
      f:SetPoint("LEFT", prev, "RIGHT", 2, 0)
    else
      f:SetPoint("LEFT", tools, "LEFT", 0, 0)
    end
    f:Show()
    prev = f
    n = n + 1
  end
  Mini.stats.indicators = n
end

-- ---------------------------------------------------------------------------------------------
-- Shape and size
-- ---------------------------------------------------------------------------------------------

function Mini.Shape()
  return mod and db().miniShape == "SQUARE" and "SQUARE" or "ROUND"
end

function Mini.Size()
  local size = tonumber(mod and db().miniSize) or 200
  return math.max(Mini.SIZE_MIN, math.min(Mini.SIZE_MAX, size))
end

-- The frame around the view: a band
-- in the header colour with an accent rim, round or square as the view; a setting switches it off.
function Mini.ApplyBorder()
  local ring = view and view.ring
  if not ring then
    return
  end
  Mini.PlaceBadge()
  local on = db().miniBorder ~= false
  ring:SetShown(on)
  if not on then
    return
  end
  -- round: two discs cut by the round mask, smooth at any size (the
  -- corner pieces scaled to a whole circle looked like pixel art); square: the theme's corners
  local round = Mini.Shape() == "ROUND"
  ring.rim:SetShown(round)
  ring.band:SetShown(round)
  for _, shape in ipairs({ ring.bg, ring.edges }) do
    if round then
      shape:Hide()
    else
      shape.radius = "radiusSmall"
      shape:Show()
    end
  end
end

-- The badge sits on the frame's rim, top right: on the circle at 45 degrees, or the square's corner.
function Mini.PlaceBadge()
  local badge = frame and frame.badge
  if not badge then
    return
  end
  local r = Mini.Size() / 2 + Mini.BORDER
  local d = Mini.Shape() == "ROUND" and r * math.sqrt(0.5) or r - 4
  badge:ClearAllPoints()
  badge:SetPoint("CENTER", view, "CENTER", d, d)
  local opener = frame.boxButton
  if opener then
    opener:ClearAllPoints()
    opener:SetPoint("CENTER", view, "CENTER", -d, -d)
  end
  if ns.MiniButtons and ns.MiniButtons.Window() and not InCombatLockdown() then
    ns.MiniButtons.Layout() -- the buttons on the rim follow its size and shape
  end
end

function Mini.ApplyShape()
  if not view then
    return
  end
  Mini.ApplyBorder()
  local shape = Mini.Shape()
  if taken and Minimap.SetMaskTexture then
    Minimap:SetMaskTexture(Mini.MASKS[shape])
  end
  local mask = shape == "ROUND" and clip.mask or nil
  for _, l in pairs(Mini.layers) do
    Tiles.SetLayerMask(l, mask)
  end
  if clip.sea.AddMaskTexture then
    if clip.seaMasked then
      clip.sea:RemoveMaskTexture(clip.mask)
      clip.seaMasked = nil
    end
    if mask then
      clip.sea:AddMaskTexture(mask)
      clip.seaMasked = true
    end
  end
end

function Mini.ApplySize()
  if not frame then
    return
  end
  local size = Mini.Size()
  view:SetSize(size, size)
  frame:SetSize(
    size + 2 * Mini.BORDER,
    Mini.BAR_H + Mini.GAP + size + 2 * Mini.BORDER + Mini.GAP + Mini.FOOT_H + Mini.TOOLS_H
  )
  if cam then
    cam:SetView(size, size)
  end
  Mini.PlaceMinimap()
  Mini.ApplyBorder()
  Mini.Render()
end

-- Alt+wheel: the frame grows or shrinks by a step.
function Mini.Resize(delta)
  db().miniSize = math.max(Mini.SIZE_MIN, math.min(Mini.SIZE_MAX, Mini.Size() + delta * Mini.SIZE_STEP))
  Mini.ApplySize()
end

-- ---------------------------------------------------------------------------------------------
-- Drawing our styles
-- ---------------------------------------------------------------------------------------------

local function clearLayers(except)
  for name, l in pairs(Mini.layers) do
    if not (except and except[name]) then
      Tiles.Clear(l)
    end
  end
end

local function drawStyle(style)
  local x1, y1, x2, y2 = cam:Bounds()
  local L_ = Mini.layers
  local used = {}
  if style == "physical" then
    if ns.Overview.Enabled() then
      Tiles.Draw(L_.overview, cam, ns.Overview.Visible(cam.continent, x1, y1, x2, y2, 1), 16)
      used.overview = true
    end
    if ns.Tiles.Enabled() and cam.level >= Tiles.MIN_LEVEL then
      Tiles.Draw(L_.native, cam, Tiles.Visible(cam.continent, x1, y1, x2, y2, 1), 36)
      used.native = true
    end
  else
    local st = ns.Styles.Get(style)
    if st then
      Tiles.Draw(L_.far, cam, ns.Styles.Visible(st.far, cam.continent, x1, y1, x2, y2, 1), 16)
      used.far = true
      if st.near and cam.level >= ns.Styles.NEAR_LEVEL then
        Tiles.Draw(L_.near, cam, ns.Styles.Visible(st.near, cam.continent, x1, y1, x2, y2, 1), 16)
        used.near = true
      end
    end
  end
  clearLayers(used)
  local n = 0
  for name in pairs(used) do
    n = n + L_[name].stats.shown
  end
  Mini.stats.drawn = n
end

-- The player's arrow where the player stands in the view, turned to the facing; hidden when the
-- view was dragged so far that the player is outside it.
local function placeArrow()
  local c, px, py = B.Coords.Player()
  if not (c and c == cam.continent) then
    arrow:Hide()
    return
  end
  local sx, sy = cam:ToScreen(px, py)
  local size = Mini.Size()
  if sx < 0 or sy < 0 or sx > size or sy > size then
    arrow:Hide()
    return
  end
  arrow:ClearAllPoints()
  arrow:SetPoint("CENTER", clip, "TOPLEFT", sx, -sy)
  arrow:SetRotation(B.Compat.GetPlayerFacing() or 0)
  arrow:Show()
end

-- The overlay host for our styles (Minimap.lua MM.SetHost): our camera's centre and scale.
local host = {
  Center = function()
    return cam.continent, cam.wx, cam.wy
  end,
  Scale = function()
    return cam:Scale()
  end,
  Half = function()
    return Mini.Size() / 2
  end,
  Shape = function()
    return Mini.Shape()
  end,
}
Mini.host = host

-- The zone and the coordinates under the view.
function Mini.UpdateFoot()
  if not foot then
    return
  end
  local zone = rawget(_G, "GetMinimapZoneText")
  local text = zone and zone() or ""
  local _, _, _, _, x, y = B.Coords.Player()
  if x and y then
    text = string.format("%s  %s%.1f, %.1f|r", text, S.H.muted, x * 100, y * 100)
  end
  foot:SetText(text)
end

-- Draws what the style needs: the game's minimap, or our renderer with the overlay on it.
function Mini.Render()
  if not (frame and frame:IsShown() and cam) then
    return
  end
  local style = Mini.Style()
  Mini.SyncWatch()
  Mini.UpdateFoot()
  if style == "game" then
    clip:Hide()
    catcher:Show()
    clearLayers()
    Mini.stats.drawn = 0
    if ns.Minimap.Host() then
      ns.Minimap.SetHost(nil)
    end
    ns.Tracked.Sync() -- stops: the game's minimap shows its own dots
    return
  end
  catcher:Hide()
  clip:Show()
  ns.Tracked.Sync() -- our tiles cover the game's dots: read them back (Tracked.lua)
  if following then
    local c, px, py = B.Coords.Player()
    if c then
      cam.continent = c
      cam:Center(px, py)
    end
  end
  style = ns.Styles.On(style, cam.continent) -- a baked style without cells here: the physical map
  if style == "physical" then
    ns.Overview.Load()
  end
  drawStyle(style)
  placeArrow()
  if ns.Minimap.Host() ~= host then
    ns.Minimap.SetHost(host)
  else
    ns.Minimap.Schedule()
  end
end

-- Positions only (no textures set): a frame of movement or of a drag.
local function follow()
  if following then
    local c, px, py = B.Coords.Player()
    if c and c == cam.continent then
      cam:Center(px, py)
    end
  end
  for _, l in pairs(Mini.layers) do
    Tiles.Reposition(l, cam)
  end
  placeArrow()
  ns.Minimap.Reposition()
end

-- ---------------------------------------------------------------------------------------------
-- Moving: wheel, drag, Recentre, and the player's own movement
-- ---------------------------------------------------------------------------------------------

-- Recentre is lit while the view looks elsewhere.
local function markRecentre()
  if recentre then
    recentre:SetAlpha(following and 0.5 or 1)
  end
end

-- The cursor in the view: pixels from its top left, or nil.
function Mini.CursorInView()
  local left, top = clip:GetLeft(), clip:GetTop()
  if not (left and top) then
    return nil
  end
  local x, y = GetCursorPosition()
  local s = clip:GetEffectiveScale() or 1
  return x / s - left, top - y / s
end

-- Zooms by `delta` notches: at the cursor ("zoom exactly where my cursor
-- is"), at the centre with `atCentre` (Shift + wheel). The game's minimap always centres on the
-- player: there the zoom has no point to keep.
function Mini.Zoom(delta, atCentre)
  if Mini.Style() == "game" then
    local zoom = Minimap:GetZoom() or 0
    local levels = Minimap.GetZoomLevels and Minimap:GetZoomLevels() or 6
    Minimap:SetZoom(math.max(0, math.min(levels - 1, zoom + delta)))
    return
  end
  local level = math.max(Mini.LEVEL_MIN, math.min(Mini.LEVEL_MAX, cam.level + delta * Mini.LEVEL_STEP))
  local step = level - cam.level
  if step == 0 then
    return
  end
  local sx, sy
  if not atCentre then
    sx, sy = Mini.CursorInView()
  end
  local half = Mini.Size() / 2
  if sx and (math.abs(sx - half) > 1 or math.abs(sy - half) > 1) then
    cam:ZoomAt(sx, sy, step)
    following = false -- the view looks where the cursor was; Recentre comes back
    markRecentre()
  else
    cam.level = level
  end
  db().miniLevel = cam.level
  Mini.Render()
end

local function onWheel(_, delta)
  if IsAltKeyDown and IsAltKeyDown() then
    Mini.Resize(delta)
  else
    Mini.Zoom(delta, IsShiftKeyDown and IsShiftKeyDown())
  end
end

function Mini.Recentre()
  following = true
  markRecentre()
  Mini.Render()
end

local onUpdate

local function running()
  local onTaxi = rawget(_G, "UnitOnTaxi")
  return moving or drifting or drag ~= nil or (onTaxi ~= nil and onTaxi("player") == true)
end

-- Whether the player is a yard or more from `seen` (which this updates). No position, nothing to follow.
local function movedSince(seen)
  local c, x, y = B.Coords.Player()
  if not c then
    return false
  end
  local moved = seen.c ~= nil and (c ~= seen.c or math.abs(x - seen.x) + math.abs(y - seen.y) >= Mini.MOVED)
  seen.c, seen.x, seen.y = c, x, y
  return moved
end

-- The look (ADR 0066): the game moves a player without a movement event; the ticks start all the same.
function Mini.Watch()
  if movedSince(watched) and not frame.ticking then
    drifting = true
    ticked.c, ticked.x, ticked.y = watched.c, watched.x, watched.y
    Mini.StartTicks()
    ns.Tracked.Wake() -- new ground comes into the tracking's reach
  end
end

-- The look runs only while one of our styles shows: the game's own minimap follows by itself.
function Mini.SyncWatch()
  local wanted = frame and frame:IsShown() and Mini.Style() ~= "game"
  if wanted and not watch then
    watched = {}
    watch = C_Timer.NewTicker(Mini.WATCH, Mini.Watch)
  elseif watch and not wanted then
    watch:Cancel()
    watch = nil
  end
end

function Mini.StartTicks()
  if frame and frame:IsShown() and not frame.ticking then
    frame.ticking = true
    elapsed = 0
    frame:SetScript("OnUpdate", onUpdate)
  end
end

onUpdate = function(_, dt)
  if moving and not drag and not following then
    following = true -- a zoom at the cursor or a drag during a walk: walking brings the view back
    markRecentre()
  end
  if drag then
    local x, y = GetCursorPosition()
    local s = frame:GetEffectiveScale() or 1
    local dx, dy = (x - drag.x) / s, (y - drag.y) / s
    if drag.moved or math.abs(dx) + math.abs(dy) >= Mini.DRAG_PX then
      if not drag.moved then
        drag.moved = true
        following = false
        markRecentre() -- Recentre now has something to do
      end
      cam:Pan(dx, -dy)
      drag.x, drag.y = x, y
    end
  end
  elapsed = elapsed + dt
  if elapsed >= Mini.TICK then
    elapsed = 0
    if drifting and not movedSince(ticked) then
      drifting = false
    end
    Mini.Render()
  elseif Mini.Style() ~= "game" then
    follow()
  end
  if not running() then
    frame.ticking = nil
    frame:SetScript("OnUpdate", nil) -- no work while nothing moves (CLAUDE.md golden rule 7)
    Mini.Render()
  end
end

local function onMouseDown(_, button)
  if button ~= "LeftButton" then
    return
  end
  if IsAltKeyDown and IsAltKeyDown() then
    frame:StartMoving()
    frame.moving = true
    return
  end
  local x, y = GetCursorPosition()
  drag = { x = x, y = y }
  Mini.StartTicks()
end

-- The end of an Alt+drag: the place is kept as an offset from the screen's top right.
function Mini.StopMoving()
  frame:StopMovingOrSizing()
  frame.moving = nil
  local right, top = frame:GetRight(), frame:GetTop()
  if right and top then
    db().miniPos = { right - UIParent:GetWidth(), top - UIParent:GetHeight() }
  end
end

-- The world point under the cursor: our camera's, or on the game's minimap the player's place plus
-- the cursor's offset from the minimap's centre at its scale (turned back with a rotating minimap).
function Mini.CursorPoint()
  if Mini.Style() ~= "game" then
    local sx, sy = Mini.CursorInView()
    if not sx then
      return nil
    end
    local wx, wy = cam:ToWorld(sx, sy)
    return cam.continent, wx, wy
  end
  local c, px, py = B.Coords.Player()
  local mx, my = Minimap:GetCenter()
  if not (c and mx) then
    return nil
  end
  local x, y = GetCursorPosition()
  local s = Minimap:GetEffectiveScale() or 1
  local scale = ns.Minimap.Scale()
  local east, north = (x / s - mx) / scale, (y / s - my) / scale
  local cvar = rawget(_G, "C_CVar")
  if cvar and cvar.GetCVar and cvar.GetCVar("rotateMinimap") == "1" then
    local f = B.Compat.GetPlayerFacing() or 0
    local cs, sn = math.cos(f), math.sin(f)
    east, north = east * cs - north * sn, east * sn + north * cs
  end
  return c, px + north, py - east
end

-- A right click on the minimap's ground: the place's menu (Route here, Note here, ...), as on the
-- big map.
function Mini.PointMenu()
  local c, wx, wy = Mini.CursorPoint()
  if c and ns.Waypoints then
    return ns.Waypoints.PointMenu(c, wx, wy, "minimap")
  end
  return false
end

local function onMouseUp(_, button)
  if frame.moving then
    Mini.StopMoving()
    return
  end
  local dragged = drag and drag.moved
  drag = nil
  if button == "RightButton" and not dragged then
    Mini.PointMenu()
  end
end

-- ---------------------------------------------------------------------------------------------
-- The frame
-- ---------------------------------------------------------------------------------------------

local function iconButton(parent, kind, tip, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(20, 20)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  B.UI.PaintIcon(b.icon, B.UI.IconTexture(kind))
  b.tip = tip -- a text, or a function returning title and text (S.TipEnter)
  b:SetScript("OnEnter", S.TipEnter)
  b:SetScript("OnLeave", S.TipLeave)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", onClick)
  return b
end

-- The style menu and the layer menu of the tools row.
function Mini.StyleMenu(anchor)
  local entries = {}
  for _, style in ipairs(Mini.StyleList()) do
    entries[#entries + 1] = {
      label = Mini.StyleTitle(style),
      icon = B.UI.IconTexture(style == "game" and "waypoint" or "zone"),
      on = style == Mini.Style(),
      onClick = function()
        Mini.SetStyle(style)
      end,
    }
  end
  return B.UI.Menu(anchor, L["Minimap style"], entries, mod)
end

function Mini.LayerMenu(anchor)
  local entries = {}
  for _, def in ipairs(B:GetMapLayers()) do
    local id = def.id
    entries[#entries + 1] = {
      label = tostring(def.label or id),
      icon = B.UI.IconTexture(def.icon or "other"),
      on = ns.Pins.IsLayerOn(def),
      onClick = function()
        ns.Pins.SetLayerOn(id, not ns.Pins.IsLayerOn(B:GetMapLayer(id)))
      end,
    }
  end
  return B.UI.Menu(anchor, L["Layers"], entries, mod)
end

-- ---------------------------------------------------------------------------------------------
-- The search: what it offers, where it jumps, the mark
-- ---------------------------------------------------------------------------------------------

-- The mark of the search's jump (drawn by the overlay, Minimap.lua MM.SetMark); nil clears it.
-- It goes on its own after MARK_SECONDS: one timer, nothing ticks.
function Mini.SetMark(m)
  if markTimer then
    markTimer:Cancel()
    markTimer = nil
  end
  ns.Minimap.SetMark(m)
  if m then
    markTimer = C_Timer.NewTimer(Mini.MARK_SECONDS, function()
      markTimer = nil
      ns.Minimap.SetMark(nil)
    end)
  end
end

function Mini.ClearMark()
  if markTimer or ns.Minimap.Mark() then
    Mini.SetMark(nil)
  end
end

function Mini.Mark()
  return ns.Minimap.Mark()
end

-- The point the search measures from: the view's centre on our styles, the player on the game's.
local function searchCentre()
  if Mini.Style() ~= "game" and cam then
    return cam.continent, cam.wx, cam.wy
  end
  local c, px, py = B.Coords.Player()
  if c then
    return c, px, py
  end
  if cam then
    return cam.continent, cam.wx, cam.wy
  end
  return nil
end

-- The place of a note on a spot: the pin of Notes' spot layer with the note's title, the
-- continent the search measures from first. -> { continent, wx, wy, title }, pin; or nil.
function Mini.SpotPlace(title)
  if type(title) ~= "string" or title == "" then
    return nil
  end
  local first = searchCentre()
  local order = {}
  for c in pairs(B.Coords.Continents()) do
    if c ~= first then
      order[#order + 1] = c
    end
  end
  table.sort(order)
  if first then
    table.insert(order, 1, first)
  end
  local far = Mini.FAR
  for _, c in ipairs(order) do
    local whole = { continent = c, x1 = -far, y1 = -far, x2 = far, y2 = far, level = 6, minimap = true }
    for _, pin in ipairs(B:QueryLayer(Mini.SPOT_LAYER, whole)) do
      if pin.label == title and pin.wx and pin.wy then
        return { c, pin.wx, pin.wy, title }, pin
      end
    end
  end
  return nil
end

-- The minimap's box keeps what the minimap can show: the types of SEARCH_SCOPE, and a result
-- without an entity when it is a note on a spot (it gets the spot as its point).
function Mini.KeepResult(res)
  local kind = B.Entity.Parse(res.ref)
  if kind then
    return Mini.SEARCH_SCOPE[kind] and res or nil
  end
  if res.point then
    return res
  end
  local point, pin = Mini.SpotPlace(res.label)
  if not point then
    return nil -- a row without a place (Quests' "Load quest texts")
  end
  return {
    label = res.label,
    point = point,
    icon = pin.icon,
    color = pin.color,
    card = pin.card,
    kindLabel = L["Note"],
    score = res.score,
    rank = res.rank,
  }
end

-- The map's bookmarks whose name matches (the layer bar's, from Notes or the Map's own list); none
-- when a type word asks for entities.
function Mini.SearchBookmarks(query, types)
  if types or not ns.LayerBar then
    return {}
  end
  local q = B.Query.Compile(query)
  local out = {}
  for _, b in ipairs(ns.LayerBar.Bookmarks() or {}) do
    local score = b.continent and b.wx and b.wy and q:Score(b.name)
    if score then
      out[#out + 1] = {
        label = b.name,
        point = { b.continent, b.wx, b.wy, b.name },
        icon = B.UI.IconTexture("spot"),
        kindLabel = L["Bookmark"],
        score = score,
      }
    end
  end
  table.sort(out, function(a, b)
    if a.score ~= b.score then
      return a.score > b.score
    end
    return a.label < b.label
  end)
  return out
end

-- A type word the minimap cannot show ("item linen"): one line instead of a search.
function Mini.SearchBlocked(types)
  if not types then
    return nil
  end
  for kind in pairs(types) do
    if Mini.SEARCH_SCOPE[kind] then
      return nil
    end
  end
  return L["The minimap finds NPCs, quests, zones and your notes."]
end

-- The places a jump to the entity may go: a quest's giver (the giver
-- must be marked), else the places that matter now.
local function jumpPlaces(ref, kind)
  local e = B:Entity(ref)
  if kind ~= "quest" then
    return e:Places()
  end
  local out = {}
  for _, p in ipairs(e:AllPlaces()) do
    if p.kind == "giver" then
      out[#out + 1] = p
    end
  end
  return out
end

-- The nearest of the places with a world position, the continent the search measures from first.
local function nearest(places)
  local fc, fx, fy = searchCentre()
  local best
  for _, p in ipairs(places) do
    if p.map and p.wx and p.wy then
      local d = (fx and p.map == fc) and ((p.wx - fx) ^ 2 + (p.wy - fy) ^ 2) or math.huge
      if not best or d < best.d then
        best = { d = d, c = p.map, wx = p.wx, wy = p.wy }
      end
    end
  end
  return best
end

-- Jumps the view to a result of the search and marks the place: the point the result carries (a
-- note, a bookmark), a zone's middle (no mark), a quest's giver, else the entity's nearest place.
-- In the game's style the big map shows the place, marked there too. -> true, or false when there
-- is no place (one line in the chat says why).
function Mini.JumpTo(ref, res)
  local kind, id = B.Entity.Parse(ref)
  local point = res and res.point
  local c, wx, wy, mark
  if point then
    c, wx, wy = point[1], point[2], point[3]
    mark = { ref = ref, icon = res.icon, color = res.color, label = res.label, card = res.card }
  elseif kind == "zone" then
    c, wx, wy = B.Coords.ToWorld(tonumber(id), 0.5, 0.5)
  elseif kind then
    local best = nearest(jumpPlaces(ref, kind))
    if not best and kind == "quest" then
      B:Say(L["No known place of the quest giver for %s."], B:Entity(ref):Name() or ref)
      return false
    end
    if best then
      c, wx, wy = best.c, best.wx, best.wy
      local e = B:Entity(ref)
      mark = {
        ref = ref,
        icon = e:Icon() or B.UI.IconTexture(kind) or B.UI.IconTexture("other"),
        label = e:Name(),
      }
    end
  end
  if not c then
    B:Say(L["No map position here (instance?)"])
    return false
  end
  if mark then
    mark.continent, mark.wx, mark.wy = c, wx, wy
    Mini.SetMark(mark)
  else
    Mini.ClearMark()
  end
  if Mini.Style() == "game" then
    -- the game's minimap cannot look elsewhere: the big map shows the place, marked as well
    if mark then
      B:RunAction("map.show", ref, { source = "minimap.search", point = { c, wx, wy, mark.label } })
    else
      Map.Fly(c, wx, wy, ns.Waypoints and ns.Waypoints.ZONE_LEVEL or 4)
    end
    return true
  end
  following = false
  markRecentre()
  cam.continent = c
  cam:Center(wx, wy)
  Mini.Render()
  return true
end

-- The info sign's text: the two ways to use the minimap, with their pros and
-- cons, as { text, token } lines; the token is a tooltip-safe colour (S.TipLine).
function Mini.InfoLines()
  local on = Mini.Style() == "game" and L["Game minimap"] or Mini.StyleTitle(Mini.Style())
  return {
    { L["Two ways to use the minimap"], "tipText" },
    { L["Now:"] .. " " .. on, "tipDim" },
    { " ", "tipDim" },
    { L["Game minimap (the default)"], "tipGold" },
    { "+ " .. L["Live: the herbs, ore and creatures you track, your group, quest areas, pings"], "tipText" },
    { "+ " .. L["Other addons that draw on the minimap keep working"], "tipText" },
    { "+ " .. L["The map's pins on top: quests, NPCs, your route"], "tipText" },
    { "- " .. L["Only the game's look; it always stays on you"], "tipDim" },
    { " ", "tipDim" },
    { L["Bastian's styles (Physical, Modern, Pencil, Parchment)"], "tipGold" },
    { "+ " .. L["The look of Bastian's Map, round or square"], "tipText" },
    { "+ " .. L["Drag to look around; the search jumps there; Recentre comes back"], "tipText" },
    { "+ " .. L["Known herb and ore places, quests, NPCs and your route from the map's layers"], "tipText" },
    { "- " .. L["Nothing live: no tracked herbs or ore, no group, no quest areas, no pings"], "tipDim" },
    { " ", "tipDim" },
    { L["Switch with the style button in this row."], "tipDim" },
    { L["Mouse wheel zooms, Alt + wheel sizes, Alt + drag moves the minimap."], "tipDim" },
  }
end

-- Shows the info at once (an info sign, not a button: no tooltip delay).
function Mini.ShowInfo(owner)
  if not GameTooltip then
    return
  end
  GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
  for _, line in ipairs(Mini.InfoLines()) do
    S.TipLine(GameTooltip, line[1], line[2], true)
  end
  GameTooltip:Show()
end

local function build()
  frame = CreateFrame("Frame", "BastiansMiniMap", UIParent)
  frame:SetFrameStrata("LOW")
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  local pos = db().miniPos
  frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", pos and pos[1] or -16, pos and pos[2] or -16)
  frame:Hide()

  -- the search bar on top, Recentre at its end
  bar = CreateFrame("Frame", nil, frame)
  bar:SetPoint("TOPLEFT", 0, 0)
  bar:SetPoint("TOPRIGHT", 0, 0)
  bar:SetHeight(Mini.BAR_H)
  recentre = iconButton(bar, "waypoint", L["Recentre on you"], function()
    Mini.Recentre()
  end)
  recentre:SetPoint("RIGHT", 0, 0)
  markRecentre()
  -- what the minimap shows, and its mark (map.md "The minimap search")
  Mini.search = ns.Search.New({
    keep = Mini.KeepResult,
    extra = Mini.SearchBookmarks,
    blocked = Mini.SearchBlocked,
    onRun = Mini.ClearMark,
    onEscape = Mini.ClearMark,
  }, bar, L["Search ..."], Mini.JumpTo)
  Mini.search.box:SetPoint("LEFT", bar, "LEFT", 0, 0)
  Mini.search.box:SetPoint("RIGHT", recentre, "LEFT", -4, 0)

  -- the view: the game's minimap lives in it; our renderer's clip lies above it
  view = CreateFrame("Frame", nil, frame)
  view:SetPoint("TOP", bar, "BOTTOM", 0, -(Mini.GAP + Mini.BORDER))
  view.ring = CreateFrame("Frame", nil, frame)
  view.ring:SetPoint("TOPLEFT", view, "TOPLEFT", -Mini.BORDER, Mini.BORDER)
  view.ring:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", Mini.BORDER, -Mini.BORDER)
  view.ring:SetFrameLevel(math.max(0, (view:GetFrameLevel() or 1) - 1))
  view.ring.bg = S.roundFill(view.ring, S.C.header, "radiusSmall")
  view.ring.edges = S.roundEdges(view.ring, S.C.accent, "radiusSmall")
  S.setEdges(view.ring.edges, S.C.accent, 0.8)
  -- the round frame: an accent disc and the band's disc inside it, both cut by the round mask
  local ring = view.ring
  ring.rim = S.fill(ring, S.C.accent, "BACKGROUND")
  ring.rim:SetAlpha(0.9)
  ring.rimMask = ring:CreateMaskTexture()
  ring.rimMask:SetTexture(Mini.MASKS.ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  ring.rimMask:SetAllPoints(ring)
  ring.rim:AddMaskTexture(ring.rimMask)
  ring.band = S.fill(ring, S.C.header, "BORDER")
  ring.band:ClearAllPoints()
  ring.band:SetPoint("TOPLEFT", 2, -2)
  ring.band:SetPoint("BOTTOMRIGHT", -2, 2)
  ring.bandMask = ring:CreateMaskTexture()
  ring.bandMask:SetTexture(Mini.MASKS.ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  ring.bandMask:SetAllPoints(ring.band)
  ring.band:AddMaskTexture(ring.bandMask)

  -- the Bastian's badge: the suite's one button on the minimap, the
  -- suite's icon in a round accent rim; click and menu as the suite's minimap button
  local badge = CreateFrame("Button", nil, frame)
  badge:SetSize(Mini.BADGE, Mini.BADGE)
  badge:SetFrameLevel((view:GetFrameLevel() or 1) + 30)
  badge:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  badge.rim = S.fill(badge, S.C.accent, "BACKGROUND")
  badge.face = S.fill(badge, S.C.header, "BORDER")
  badge.face:ClearAllPoints()
  badge.face:SetPoint("TOPLEFT", 2, -2)
  badge.face:SetPoint("BOTTOMRIGHT", -2, 2)
  badge.icon = badge:CreateTexture(nil, "ARTWORK")
  badge.icon:SetTexture(Mini.ICON)
  badge.icon:SetPoint("TOPLEFT", 5, -5)
  badge.icon:SetPoint("BOTTOMRIGHT", -5, 5)
  for _, t in ipairs({ badge.rim, badge.face, badge.icon }) do
    local m = badge:CreateMaskTexture()
    m:SetTexture(Mini.MASKS.ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetAllPoints(t)
    t:AddMaskTexture(m)
  end
  badge:SetScript("OnEnter", function(self)
    S.tint(self.rim, S.C.text)
    local launcher = B.UI.Launcher
    if GameTooltip and launcher and launcher.Tooltip then
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      launcher.Tooltip(GameTooltip)
      GameTooltip:Show()
    end
  end)
  badge:SetScript("OnLeave", function(self)
    S.tint(self.rim, S.C.accent)
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  badge:SetScript("OnClick", function(self, button)
    local launcher = B.UI.Launcher
    if launcher and launcher.OnClick then
      launcher.OnClick(self, button)
    end
  end)
  frame.badge = badge

  -- the box of the addons' minimap buttons, on the rim bottom left; the mouse on it opens the box
  --
  local opener = CreateFrame("Button", nil, frame)
  opener:SetSize(Mini.OPENER, Mini.OPENER)
  opener:SetFrameLevel((view:GetFrameLevel() or 1) + 30)
  opener.rim = S.fill(opener, S.C.accent, "BACKGROUND")
  opener.face = S.fill(opener, S.C.header, "BORDER")
  opener.face:ClearAllPoints()
  opener.face:SetPoint("TOPLEFT", 2, -2)
  opener.face:SetPoint("BOTTOMRIGHT", -2, 2)
  opener.icon = opener:CreateTexture(nil, "ARTWORK")
  opener.icon:SetPoint("TOPLEFT", 4, -4)
  opener.icon:SetPoint("BOTTOMRIGHT", -4, 4)
  B.UI.PaintIcon(opener.icon, B.UI.IconTexture("buttons"))
  for _, t in ipairs({ opener.rim, opener.face, opener.icon }) do
    local m = opener:CreateMaskTexture()
    m:SetTexture(Mini.MASKS.ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetAllPoints(t)
    t:AddMaskTexture(m)
  end
  opener:SetScript("OnEnter", function(self)
    S.tint(self.rim, S.C.text)
    if ns.MiniButtons then
      ns.MiniButtons.Open(self)
    end
  end)
  opener:SetScript("OnLeave", function(self)
    S.tint(self.rim, S.C.accent)
  end)
  frame.boxButton = opener
  clip = CreateFrame("Frame", nil, view)
  clip:SetAllPoints(view)
  clip:SetClipsChildren(true)
  clip:SetFrameLevel((view:GetFrameLevel() or 1) + 10)
  clip.sea = S.fill(clip, S.C.sea)
  clip.sea:SetDrawLayer("BACKGROUND", -8)
  clip.mask = clip:CreateMaskTexture()
  clip.mask:SetTexture(Mini.MASKS.ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  clip.mask:SetAllPoints(clip)
  clip:EnableMouse(true)
  clip:EnableMouseWheel(true)
  clip:SetScript("OnMouseWheel", onWheel)
  clip:SetScript("OnMouseDown", onMouseDown)
  clip:SetScript("OnMouseUp", onMouseUp)
  for _, l in pairs(Mini.layers) do
    l.parent = clip
  end
  host.frame = clip -- the overlay's pins over our renderer
  -- the arrow on a frame of its own above the overlay's pins (in Goldshire
  -- the innkeeper's and the quest givers' pins covered it, the player was nowhere to see)
  local arrowLayer = CreateFrame("Frame", nil, clip)
  arrowLayer:SetAllPoints(clip)
  arrowLayer:SetFrameLevel((clip:GetFrameLevel() or 1) + 20)
  Mini.arrowLayer = arrowLayer
  arrow = arrowLayer:CreateTexture(nil, "OVERLAY")
  arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
  arrow:SetSize(24, 24)
  -- the game's minimap keeps its clicks (pings, tracked blips); only the wheel is ours
  catcher = CreateFrame("Frame", nil, view)
  catcher:SetAllPoints(view)
  catcher:SetFrameLevel((view:GetFrameLevel() or 1) + 20)
  catcher:EnableMouse(false)
  catcher:EnableMouseWheel(true)
  catcher:SetScript("OnMouseWheel", onWheel)

  -- the zone and the coordinates; Alt+drag here moves the frame too
  foot = S.text(frame, 11, S.C.text)
  foot:SetPoint("TOPLEFT", view, "BOTTOMLEFT", -Mini.BORDER, -(Mini.GAP + Mini.BORDER))
  foot:SetPoint("TOPRIGHT", view, "BOTTOMRIGHT", Mini.BORDER, -(Mini.GAP + Mini.BORDER))
  foot:SetJustifyH("CENTER")
  foot:SetWordWrap(false)
  foot:SetHeight(Mini.FOOT_H)

  -- the tools: style, layers, the button box, the big map, then the game's indicators
  tools = CreateFrame("Frame", nil, frame)
  tools:SetPoint("BOTTOMLEFT", 0, 0)
  tools:SetPoint("BOTTOMRIGHT", 0, 0)
  tools:SetHeight(Mini.TOOLS_H)
  tools.style = iconButton(tools, "zone", L["Minimap style"], function(self)
    Mini.StyleMenu(self)
  end)
  tools.style:SetPoint("LEFT", 0, 0)
  tools.layers = iconButton(tools, "spot", L["Layers"], function(self)
    Mini.LayerMenu(self)
  end)
  tools.layers:SetPoint("LEFT", tools.style, "RIGHT", 2, 0)
  tools.map = iconButton(tools, "open", L["Open Bastian's Map"], function()
    Map.Toggle()
  end)
  tools.map:SetPoint("LEFT", tools.layers, "RIGHT", 2, 0)
  -- the minimap's options, one click away
  tools.options = iconButton(tools, "settings", L["Options of this window"], function()
    if B.UI.Hub then
      B.UI.Hub.Open("Map", "minimap")
    end
  end)
  tools.options:SetPoint("LEFT", tools.map, "RIGHT", 2, 0)
  -- the timers: stopwatches and countdowns
  tools.timers = ns.Timers.Button(tools, iconButton)
  tools.timers:SetPoint("LEFT", tools.options, "RIGHT", 2, 0)
  -- the info sign: the two ways to use the minimap and what each gives and takes
  tools.info = S.action(tools, { icon = "help", only = true, boxed = true })
  tools.info:SetPoint("LEFT", tools.timers, "RIGHT", 2, 0)
  tools.info:SetScript("OnEnter", function(self)
    S.tint(self.face, S.C.faceHover)
    Mini.ShowInfo(self)
  end)
  tools.info:SetScript("OnLeave", function(self)
    S.tint(self.face, S.C.panel)
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  tools.info:SetScript("OnClick", function(self)
    Mini.ShowInfo(self)
  end)
  tools.last = tools.info
  Mini.LayoutTools()

  frame:SetScript("OnShow", function()
    Mini.Render()
    if running() then
      Mini.StartTicks() -- it came back during a walk: no new start event will tell
    end
  end)
  frame:SetScript("OnHide", function(self)
    self.ticking = nil
    self:SetScript("OnUpdate", nil)
    drag = nil
    drifting = false
    Mini.SyncWatch()
    ns.Tracked.Stop()
    -- what hung off the minimap goes with it
    ns.Pins.HideMiniCard()
    if GameTooltip then
      GameTooltip:Hide()
    end
    if ns.MiniButtons then
      ns.MiniButtons.Close()
    end
  end)
  -- the player's own movement drives the ticks; the frame listens itself (the module's handlers for
  -- these events belong to the overlay, Minimap.lua: one handler per event per module)
  frame:RegisterEvent("PLAYER_STARTED_MOVING")
  frame:RegisterEvent("PLAYER_STOPPED_MOVING")
  frame:RegisterEvent("PLAYER_CONTROL_LOST")
  frame:RegisterEvent("ZONE_CHANGED")
  frame:RegisterEvent("ZONE_CHANGED_INDOORS")
  frame:RegisterEvent("PLAYER_REGEN_ENABLED")
  frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_STARTED_MOVING" or event == "PLAYER_CONTROL_LOST" then
      moving = event == "PLAYER_STARTED_MOVING" or moving
      -- walking brings the view back to the player ("the minimap does
      -- not center around my position" after a zoom at the cursor); standing still keeps the look
      if not following and not drag then
        following = true
        markRecentre()
      end
      Mini.StartTicks()
      ns.Tracked.Wake() -- new ground comes into the tracking's reach
    elseif event == "PLAYER_STOPPED_MOVING" then
      moving = false
    elseif event == "PLAYER_REGEN_ENABLED" then
      local fn = pending
      pending = nil
      if fn then
        fn()
      end
    else
      Mini.Render()
    end
  end)

  cam = Camera.new(0, Mini.Size(), Mini.Size())
  cam.level = tonumber(db().miniLevel) or 4
  Mini.view, Mini.clip, Mini.bar, Mini.foot, Mini.tools, Mini.catcher, Mini.arrow =
    view, clip, bar, foot, tools, catcher, arrow
end

-- The setting decides: on takes the game's minimap into ours, off gives it back.
function Mini.Apply()
  if not mod then
    return
  end
  if Mini.Enabled() then
    deferred(function()
      if not frame then
        build()
      end
      Mini.ApplySize()
      frame:Show()
      take()
      Mini.Render()
      if ns.MiniButtons then
        ns.MiniButtons.Apply()
      end
    end)
  elseif frame then
    Mini.ClearMark()
    deferred(function()
      if ns.MiniButtons then
        ns.MiniButtons.Release()
      end
      ns.Minimap.SetHost(nil)
      clearLayers()
      giveBack()
      frame:Hide()
    end)
  end
end

ns.mod.Mini = Mini
table.insert(Map.onEnable, function(self)
  mod = self
end)
table.insert(Map.onWorld, function()
  Mini.Apply()
end)
table.insert(Map.onZone, function()
  Mini.Render()
end)
table.insert(Map.onLayerChanged, function()
  if frame and frame:IsShown() then
    ns.Minimap.Schedule()
  end
end)
table.insert(Map.onSetting, function(key, value)
  if key == "miniMap" then
    Mini.Apply()
  elseif key == "miniStyle" then
    if value ~= "game" and not db().miniWarned then
      db().miniStyle = "game" -- the settings page chose it: ask first, as the menu does
      Mini.Warn(value)
    end
    Mini.Render()
  elseif key == "miniShape" then
    Mini.ApplyShape()
    Mini.Render()
  elseif key == "miniSize" then
    Mini.ApplySize()
  elseif key == "miniBorder" then
    Mini.ApplyBorder()
  elseif key == "miniButtonBox" and ns.MiniButtons then
    ns.MiniButtons.Apply()
  end
end)
table.insert(Map.onDisable, function()
  if markTimer then
    markTimer:Cancel()
    markTimer = nil
  end
  if frame then
    deferred(function()
      if ns.MiniButtons then
        ns.MiniButtons.Release()
      end
      ns.Minimap.SetHost(nil)
      clearLayers()
      giveBack()
      frame:Hide()
    end)
  end
end)
