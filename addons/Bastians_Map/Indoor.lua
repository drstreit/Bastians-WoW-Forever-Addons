-- The cities inside the ground on the world map (map.md "Cities inside the ground"; owner, Forever
-- 20.11.2026): Ironforge and the Undercity lie under the terrain the map paints from, so there the
-- place's sheet of the City & dungeon map (Bastians_Map_Art) is drawn over the terrain as the
-- ground, cut out to the city's plan. Only the picture: the pins and the layers stay the world map's.
local _, ns = ...
local B = Bastians
local Map = ns.Map
local Tiles = ns.Tiles
local City = ns.City

local Indoor = {
  live = {},
  free = {},
  stats = { shown = 0, wanted = 0, skipped = 0, unmasked = 0 },
  sublevel = 3, -- above the styles' paintings and the native tiles (2), below the pins
}
ns.Indoor = Indoor

-- Which places and tiles: the manifest's `ground` per place (tools/city_ground.py, the places
-- tools/cities.toml marks), the tiles that hold some of the city's plan, each with its mask.
-- ~~`Indoor.CITIES`, the whole sheet of Ironforge and the Undercity~~ (20.11.2026; the parchment
-- with its frame, scroll and crest lay as an opaque rectangle over the land around the city, owner,
-- Forever 21.11.2026: "covers the map - that doesn't work").
Indoor.MIN_LEVEL = 3 -- where the native tiles start; nearer out the overview shows the land
Indoor.MAX_TEXTURES = 24 -- two places of 12 tiles
Indoor.MASK_SUFFIX = "_ground.tga"

local function inView(city, x1, y1, x2, y2)
  return city.wx[2] >= x1 and city.wx[1] <= x2 and city.wy[2] >= y1 and city.wy[1] <= y2
end

-- The sheet tiles to draw for the camera: { key, path, mask, x1, y1, x2, y2, tc } in world yards
-- (x south to north, y east to west), for Tiles.Draw.
function Indoor.Wanted(cam)
  local out = {}
  if not (City.Available() and cam.level and cam.level >= Indoor.MIN_LEVEL) then
    return out
  end
  local x1, y1, x2, y2 = cam:Bounds()
  for _, city in ipairs(B.Map.cities) do
    if city.ground and city.continent == cam.continent and inView(city, x1, y1, x2, y2) then
      for _, cell in ipairs(city.ground) do
        local row, col = string.match(cell, "^(%d+)_(%d+)$")
        row, col = tonumber(row), tonumber(col)
        if row and col then
          local north, west, south, east, u, v = City.TileRect(city, row, col)
          local name = city.path .. row .. "_" .. col
          out[#out + 1] = {
            key = city.ui * 100 + row * 10 + col,
            path = name,
            mask = name .. Indoor.MASK_SUFFIX,
            x1 = south,
            y1 = east,
            x2 = north,
            y2 = west,
            tc = { u, v },
          }
        end
      end
    end
  end
  return out
end

function Indoor.Render(cam)
  local wanted = Indoor.Wanted(cam)
  if #wanted == 0 then
    Tiles.Clear(Indoor)
    Indoor.stats.unmasked = 0
    return
  end
  Tiles.Draw(Indoor, cam, wanted, Indoor.MAX_TEXTURES)
  -- a tile whose mask did not load (a client without mask textures, or new mask files before a
  -- full restart, CLAUDE.md section 12) would show the whole parchment again: it stays hidden, the
  -- terrain shows there
  local unmasked = 0
  for _, t in pairs(Indoor.live) do
    if not t.maskPath then
      t:Hide()
      unmasked = unmasked + 1
    end
  end
  Indoor.stats.unmasked = unmasked
  Indoor.stats.shown = Indoor.stats.shown - unmasked
end

ns.mod.Indoor = Indoor
table.insert(Map.onView, Indoor.Render)
table.insert(Map.onResize, function(cam)
  Tiles.Reposition(Indoor, cam)
end)
