-- The arrow to the next step (route.md "The arrow", S6, 22.10.2026): our own small movable arrow
-- that turns with the player's facing and names the step's end with the distance (TomTom's crazy
-- arrow is no longer used: , "we drop tomtom as we have it ourselves"). The arrow
-- moves ten times a second only while the player moves or turns (the movement events) and once a
-- second from the route's own ticker; nothing ticks while the player stands without a route. The
-- minimap shows the next step through the route.path layer (a pin the minimap overlay draws, Map
-- S5).
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style

local Arrow = {}
ns.Arrow = Arrow

Arrow.TICK = 0.1
Arrow.BEND_YARDS = 30 -- on a walk network path the arrow turns to the next bend this close to the current one
Arrow.SIZE = 72 -- the arrow texture
Arrow.WIDTH, Arrow.HEIGHT = 150, 112
-- Core's arrow texture points east; the rotation below is counted from north (up)
Arrow.TEXTURE_OFFSET = math.pi / 2
-- the arrow's colour by how far the target lies from straight ahead (radians): green ahead,
-- gold to the side, red behind, as TomTom's crazy arrow does
Arrow.AHEAD, Arrow.SIDE = math.rad(25), math.rad(100)
Arrow.COLORS = { ahead = S.C.good, side = S.C.gold, behind = S.C.bad } -- the theme's (ST3)

local mod, frame
local moving, turning, ticking = false, false, false
local elapsed = 0

local function db()
  return mod.db.profile
end

-- The next step's end: { continent, wx, wy, name, mode } or nil without a route.
function Arrow.Target()
  local active = ns.Route.Active()
  if not active then
    return nil
  end
  local step = active.steps[active.index or 1]
  if not (step and step.to) then
    return nil
  end
  local to = step.to
  local name = to.name
  if not name and step == active.steps[#active.steps] and active.goal then
    name = active.goal.name
  end
  local wx, wy = to.wx, to.wy
  if step.legs then
    -- a walk on the walk network: the next bend of its path, not the end behind the mountain
    local c, px, py = B.Coords.Player()
    if c == to.continent and px then
      local _, p = ns.Graph.PathProgress(step, px, py, Arrow.BEND_YARDS)
      if p then
        wx, wy = p[1], p[2]
      end
    end
  end
  return { continent = to.continent, wx = wx, wy = wy, name = name, mode = step.mode }
end

-- The direction from the player to a point, counter-clockwise from north like the facing (world
-- wx grows north, wy west), and the arrow's rotation given the facing.
function Arrow.Bearing(px, py, tx, ty)
  return math.atan2(ty - py, tx - px)
end

function Arrow.Rotation(bearing, facing)
  return bearing - (facing or 0)
end

-- "ahead", "side" or "behind" for a rotation (0 = straight ahead).
function Arrow.Heading(rotation)
  local r = math.abs(math.atan2(math.sin(rotation), math.cos(rotation))) -- folded into 0..pi
  if r <= Arrow.AHEAD then
    return "ahead"
  elseif r <= Arrow.SIDE then
    return "side"
  end
  return "behind"
end

-- ---------------------------------------------------------------------------------------------
-- The own arrow frame
-- ---------------------------------------------------------------------------------------------

local function savePlace()
  local x, y = frame:GetCenter()
  local cx, cy = UIParent:GetCenter()
  if x and cx then
    db().arrow = { x - cx, y - cy }
  end
end

local function place()
  frame:ClearAllPoints()
  local saved = db().arrow
  if saved and saved[1] and saved[2] then
    frame:SetPoint("CENTER", UIParent, "CENTER", saved[1], saved[2])
  else
    frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
  end
end

local function build()
  frame = CreateFrame("Button", "BastiansRouteArrow", UIParent)
  frame:SetSize(Arrow.WIDTH, Arrow.HEIGHT)
  frame:SetFrameStrata("MEDIUM")
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  frame:SetScript("OnDragStart", function()
    frame:StartMoving()
  end)
  frame:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    savePlace()
  end)
  frame:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      ns.Route.Clear() -- the route goes, the arrow with it
    else
      ns.Window.Toggle() -- the step list
    end
  end)
  frame.tex = frame:CreateTexture(nil, "ARTWORK")
  frame.tex:SetTexture(S.ARROW) -- Core's arrow with a shaft, tinted by the heading
  frame.tex:SetSize(Arrow.SIZE, Arrow.SIZE)
  frame.tex:SetPoint("TOP", frame, "TOP", 0, -2)
  frame.name = S.text(frame, 13, S.C.text)
  frame.name:SetPoint("TOP", frame.tex, "BOTTOM", 0, -2)
  frame.name:SetPoint("LEFT", frame, "LEFT", 2, 0)
  frame.name:SetPoint("RIGHT", frame, "RIGHT", -2, 0)
  frame.name:SetJustifyH("CENTER")
  frame.dist = S.text(frame, 12, S.C.dim)
  frame.dist:SetPoint("TOP", frame.name, "BOTTOM", 0, -1)
  frame.dist:SetPoint("LEFT", frame, "LEFT", 2, 0)
  frame.dist:SetPoint("RIGHT", frame, "RIGHT", -2, 0)
  frame.dist:SetJustifyH("CENTER")
  frame:Hide()
  place()
  Arrow.frame = frame
end

local function stopTicks()
  if ticking and frame then
    frame:SetScript("OnUpdate", nil)
    ticking = false
  end
end

local function inMotion()
  return moving or turning
end

local onUpdate

function Arrow.StartTicks()
  if frame and frame:IsShown() and not ticking then
    frame:SetScript("OnUpdate", onUpdate)
    ticking = true
    elapsed = Arrow.TICK
  end
end

function Arrow.Ticking()
  return ticking
end

-- Turns the texture to `rotation` (from north) and colours it by the heading.
local function turn(rotation, alpha)
  frame.angle = rotation
  frame.tex:SetRotation(rotation + Arrow.TEXTURE_OFFSET)
  local c = Arrow.COLORS[Arrow.Heading(rotation)]
  frame.tex:SetVertexColor(c[1], c[2], c[3], alpha or 1)
end

-- Turn the arrow and write the distance; called by the ticks, the route's own ticker and every
-- route change.
function Arrow.Refresh()
  if not (frame and frame:IsShown()) then
    return
  end
  local t = Arrow.Target()
  if not t then
    return
  end
  local continent, px, py = B.Coords.Player()
  frame.name:SetText(t.name or L["Next step"])
  if not continent then
    turn(0, 0.4)
    frame.dist:SetText(L["position unknown"])
    return
  end
  if continent ~= t.continent then
    turn(0, 0.4)
    frame.dist:SetText(L["another continent"])
    return
  end
  local facing = B.Compat.GetPlayerFacing() or 0
  turn(Arrow.Rotation(Arrow.Bearing(px, py, t.wx, t.wy), facing), 1)
  local dx, dy = t.wx - px, t.wy - py
  frame.dist:SetText(B.UI.Distance(math.sqrt(dx * dx + dy * dy)))
end

onUpdate = function(_, dt)
  elapsed = elapsed + dt
  if elapsed < Arrow.TICK then
    return
  end
  elapsed = 0
  Arrow.Refresh()
  if not inMotion() then
    stopTicks() -- one last turn after the stop; the route's ticker refreshes once a second
  end
end

-- ---------------------------------------------------------------------------------------------
-- The route changed (also every step): the arrow follows
-- ---------------------------------------------------------------------------------------------

function Arrow.Update()
  if not mod then
    return
  end
  local t = db().arrow ~= false and mod:IsEnabled() and Arrow.Target() or nil
  if not t then
    if frame then
      stopTicks()
      frame:Hide()
    end
    return
  end
  if not frame then
    build()
  end
  frame:Show()
  Arrow.Refresh()
  if inMotion() then
    Arrow.StartTicks()
  end
end

function Arrow.IsShown()
  return frame ~= nil and frame:IsShown()
end

function Arrow.Register(self)
  mod = self
  moving, turning = false, false
  -- movement (retail family events, assumed on Forever until seen: forever-api.md)
  self:RegisterEvent("PLAYER_STARTED_MOVING", function()
    moving = true
    Arrow.StartTicks()
  end)
  self:RegisterEvent("PLAYER_STOPPED_MOVING", function()
    moving = false
  end)
  self:RegisterEvent("PLAYER_STARTED_TURNING", function()
    turning = true
    Arrow.StartTicks()
  end)
  self:RegisterEvent("PLAYER_STOPPED_TURNING", function()
    turning = false
  end)
  Arrow.Update()
end

function Arrow.Unregister()
  if frame then
    stopTicks()
    frame:Hide()
  end
end
