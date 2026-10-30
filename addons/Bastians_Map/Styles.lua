-- Bastian's own map styles (ADR 0027, map.md "Bastian's styles"): each style addon
-- (Bastians_Map_Modern, Bastians_Map_Pencil, Bastians_Map_Parchment) registers its cells through
-- Bastians.deferred; the Map draws the far cells (8 x 8 ADT tiles in one texture) at every level and
-- the near cells (4 x 4 tiles, four times the pixels per tile) above them from NEAR_LEVEL on, in
-- place of the overview, the native tiles and the zone art. Labels, borders, pins and routes stay.
local _, ns = ...
local B = Bastians
local Map = ns.Map
local Tiles = ns.Tiles

local Styles = {}
ns.Styles = Styles

Styles.NEAR_LEVEL = 3 -- near cells from this level on (a 1024 px cell of 4 tiles: 256 px per tile)
Styles.MAX_TEXTURES = 48
Styles.MARGIN = 1

local registered = {} -- key -> { key, title, order, client, build, near = set, far = set }

local function layer(sublevel)
  return { live = {}, free = {}, stats = { shown = 0, wanted = 0, skipped = 0 }, sublevel = sublevel }
end
Styles.far = layer(1)
Styles.near = layer(2)

local function setOf(continents)
  local out = {}
  for continent, keys in pairs(continents or {}) do
    local set = {}
    for _, key in ipairs(keys) do
      set[key] = true
    end
    out[continent] = set
  end
  return out
end

local function part(info)
  if type(info) ~= "table" or type(info.path) ~= "string" then
    return nil
  end
  local span = info.span or 8
  return {
    path = info.path,
    span = span,
    grid = math.floor(Tiles.GRID / span),
    cells = setOf(info.continents),
  }
end

-- A style addon's Generated/Style.lua calls this once: { key, title, order, client, build,
-- near = { path, span, continents = { [continent] = { cx * grid + cy, ... } } }, far = { ... } }.
-- A table built for the other client is kept out.
function B.Map.RegisterStyle(info)
  if type(info) ~= "table" or type(info.key) ~= "string" or info.key == "physical" then
    return
  end
  if info.client and B.Client and info.client ~= B.Client then
    return
  end
  registered[info.key] = {
    key = info.key,
    title = info.title or info.key,
    order = info.order or 50,
    client = info.client,
    build = info.build,
    near = part(info.near),
    far = part(info.far),
    font = type(info.font) == "string" and info.font or nil,
    -- the style's own place names (the Blizzard style, ADR 0036): continent -> { { text, wx, wy,
    -- height in yards, kind, area id or false, level }, ... }; Names.lua draws them for the style
    labels = type(info.labels) == "table" and info.labels or nil,
  }
  if Map.bar then
    Map.bar.Refresh()
  end
  if Map.IsShown() then
    Map.ViewChanged()
  end
end

function Styles.Get(key)
  return registered[key]
end

-- The registered styles by order, then key.
function Styles.List()
  local out = {}
  for _, st in pairs(registered) do
    out[#out + 1] = st
  end
  table.sort(out, function(a, b)
    if a.order ~= b.order then
      return a.order < b.order
    end
    return a.key < b.key
  end)
  return out
end

-- How many cells a style's part holds on a continent.
function Styles.Count(key, which, continent)
  local st = registered[key]
  local set = st and st[which] and st[which].cells[continent]
  local n = 0
  for _ in pairs(set or {}) do
    n = n + 1
  end
  return n
end

-- World rectangle of cell (cx, cy) of `span` tiles: wx1 < wx2, wy1 < wy2.
function Styles.WorldRect(cx, cy, span)
  local x1, y1 = Tiles.WorldRect(cx * span + span - 1, cy * span + span - 1)
  local _, _, x2, y2 = Tiles.WorldRect(cx * span, cy * span)
  return x1, y1, x2, y2
end

-- The part's cells in the world rectangle plus `margin` cells, nearest the centre first.
function Styles.Visible(p, continent, wx1, wy1, wx2, wy2, margin)
  local out = {}
  local set = p and p.cells[continent]
  if not set then
    return out
  end
  local span, grid, half, t = p.span, p.grid, Tiles.GRID / 2, Tiles.TILE_YARDS
  local function clamp(v)
    return math.max(0, math.min(grid - 1, v))
  end
  margin = margin or 0
  local cx1 = clamp(math.floor((half - wy2 / t) / span) - margin)
  local cx2 = clamp(math.floor((half - wy1 / t) / span) + margin)
  local cy1 = clamp(math.floor((half - wx2 / t) / span) - margin)
  local cy2 = clamp(math.floor((half - wx1 / t) / span) + margin)
  local mx, my = (wx1 + wx2) / 2, (wy1 + wy2) / 2
  for cx = cx1, cx2 do
    for cy = cy1, cy2 do
      local key = cx * grid + cy
      if set[key] then
        local x1, y1, x2, y2 = Styles.WorldRect(cx, cy, span)
        local dx, dy = (x1 + x2) / 2 - mx, (y1 + y2) / 2 - my
        out[#out + 1] = {
          key = key,
          path = p.path .. continent .. "_" .. cx .. "_" .. cy,
          x1 = x1,
          y1 = y1,
          x2 = x2,
          y2 = y2,
          dist = dx * dx + dy * dy,
        }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.dist ~= b.dist then
      return a.dist < b.dist
    end
    return a.key < b.key
  end)
  return out
end

-- The far cells always (they stay under the near ones while those load), the near cells from
-- NEAR_LEVEL on; nothing when the style is not one of ours.
function Styles.Render(cam)
  local st = registered[Map.Style()]
  if not st then
    Tiles.Clear(Styles.far)
    Tiles.Clear(Styles.near)
    return
  end
  local x1, y1, x2, y2 = cam:Bounds()
  Tiles.Draw(
    Styles.far,
    cam,
    Styles.Visible(st.far, cam.continent, x1, y1, x2, y2, Styles.MARGIN),
    Styles.MAX_TEXTURES
  )
  if cam.level >= Styles.NEAR_LEVEL and st.near then
    Tiles.Draw(
      Styles.near,
      cam,
      Styles.Visible(st.near, cam.continent, x1, y1, x2, y2, Styles.MARGIN),
      Styles.MAX_TEXTURES
    )
  else
    Tiles.Clear(Styles.near)
  end
end

ns.mod.Styles = Styles
table.insert(Map.onView, Styles.Render)
table.insert(Map.onResize, function(cam)
  Tiles.Reposition(Styles.far, cam)
  Tiles.Reposition(Styles.near, cam)
end)
