-- Camera (map.md "Rendering model"): the view onto one continent in world yards. Pure math: a centre
-- (wx, wy), a fractional zoom level and the view size in pixels; world <-> screen conversions, pan,
-- zoom to a point, bounds for the layer queries. World axes (coordinates.md): wx grows north (up on
-- the screen), wy grows west (left on the screen).
local _, ns = ...

local Camera = {}
Camera.__index = Camera
ns.Camera = Camera

Camera.PX_PER_YARD_L0 = 1 / 32 -- level 0: 32 yards per pixel, a continent of ~17,000 yards in ~530 px
Camera.MIN_LEVEL, Camera.MAX_LEVEL = 0, 8 -- each level doubles (map.md); 8 = 1/8 yard per pixel

local function clamp(v, lo, hi)
  if v < lo then
    return lo
  elseif v > hi then
    return hi
  end
  return v
end

function Camera.new(continent, width, height)
  return setmetatable({
    continent = continent or 0,
    wx = 0,
    wy = 0,
    level = 0,
    width = width or 600,
    height = height or 400,
  }, Camera)
end

-- Pixels per yard at the current level.
function Camera:Scale()
  return Camera.PX_PER_YARD_L0 * 2 ^ self.level
end

function Camera:SetView(width, height)
  self.width, self.height = math.max(1, width or self.width), math.max(1, height or self.height)
end

function Camera:Center(wx, wy)
  self.wx, self.wy = wx, wy
end

function Camera:SetLevel(level)
  self.level = clamp(level, Camera.MIN_LEVEL, Camera.MAX_LEVEL)
end

-- World yards -> pixels from the view's top-left corner (x right, y down).
function Camera:ToScreen(wx, wy)
  local s = self:Scale()
  return self.width / 2 - (wy - self.wy) * s, self.height / 2 - (wx - self.wx) * s
end

-- Pixels from the view's top-left corner -> world yards.
function Camera:ToWorld(sx, sy)
  local s = self:Scale()
  return self.wx - (sy - self.height / 2) / s, self.wy - (sx - self.width / 2) / s
end

-- Drag by pixels: the content follows the cursor, so the centre moves the other way in world terms.
function Camera:Pan(dx, dy)
  local s = self:Scale()
  self.wy = self.wy + dx / s
  self.wx = self.wx + dy / s
end

-- Change the level by `delta` keeping the world point under the pixel (sx, sy) where it is.
function Camera:ZoomAt(sx, sy, delta)
  local wx, wy = self:ToWorld(sx, sy)
  local before = self.level
  self:SetLevel(self.level + delta)
  if self.level == before then
    return false
  end
  local nwx, nwy = self:ToWorld(sx, sy)
  self.wx = self.wx + (wx - nwx)
  self.wy = self.wy + (wy - nwy)
  return true
end

function Camera:Zoom(delta)
  return self:ZoomAt(self.width / 2, self.height / 2, delta)
end

-- The world rectangle the view shows: wx1 < wx2 (south to north), wy1 < wy2 (east to west).
function Camera:Bounds()
  local s = self:Scale()
  local hx, hy = self.height / 2 / s, self.width / 2 / s
  return self.wx - hx, self.wy - hy, self.wx + hx, self.wy + hy
end

-- The view table the map layers take (core-contracts §6): continent, bounds, integer level.
function Camera:View(player)
  local x1, y1, x2, y2 = self:Bounds()
  return {
    continent = self.continent,
    x1 = x1,
    y1 = y1,
    x2 = x2,
    y2 = y2,
    level = math.floor(self.level + 0.5),
    player = player,
  }
end

-- Centre on a world rectangle and pick the largest level that shows all of it (with a margin).
function Camera:FitBounds(x1, y1, x2, y2, margin)
  margin = margin or 1.1
  self.wx, self.wy = (x1 + x2) / 2, (y1 + y2) / 2
  local spanX, spanY = math.max(1, math.abs(x2 - x1)) * margin, math.max(1, math.abs(y2 - y1)) * margin
  local scale = math.min(self.height / spanX, self.width / spanY) -- px per yard that fits both axes
  local level = math.log(scale / Camera.PX_PER_YARD_L0) / math.log(2)
  self:SetLevel(level)
end

-- Is the world point inside the view (with `margin` pixels around it)?
function Camera:Contains(wx, wy, margin)
  local sx, sy = self:ToScreen(wx, wy)
  margin = margin or 0
  return sx >= -margin and sx <= self.width + margin and sy >= -margin and sy <= self.height + margin
end
