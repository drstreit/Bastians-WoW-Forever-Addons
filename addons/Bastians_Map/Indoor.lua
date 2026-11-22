-- The cities inside the ground on the world map (map.md "Cities inside the ground"; owner, Forever
-- 20.11.2026): Ironforge and the Undercity lie under the terrain the map paints from, so there the
-- place's sheet of the City & dungeon map (Bastians_Map_Art) is drawn over the terrain as the
-- ground. Only the picture: the pins and the layers stay the world map's own.
local _, ns = ...
local B = Bastians
local Map = ns.Map
local Tiles = ns.Tiles
local City = ns.City

local Indoor = {
  live = {},
  free = {},
  stats = { shown = 0, wanted = 0, skipped = 0 },
  sublevel = 3, -- above the styles' paintings and the native tiles (2), below the pins
}
ns.Indoor = Indoor

-- The places whose terrain is what lies over them (the UiMap of the sheet). None since 21.11.2026
-- (owner, Forever: the Undercity's sheet "covers the map - that doesn't work"): the sheet is the
-- whole parchment with its frame, scroll and crest, an opaque rectangle over the land around the
-- city. ~~Ironforge and the Undercity, { [1455] = true, [1458] = true }~~ (20.11. to 21.11.2026).
-- The machinery stays for a sheet cut out to the city's plan (map.md "Cities inside the ground").
Indoor.CITIES = {}
Indoor.MIN_LEVEL = 3 -- where the native tiles start; nearer out the overview shows the land
Indoor.MAX_TEXTURES = 24 -- two places of 12 tiles

local function inView(city, x1, y1, x2, y2)
  return city.wx[2] >= x1 and city.wx[1] <= x2 and city.wy[2] >= y1 and city.wy[1] <= y2
end

-- The sheet tiles to draw for the camera: { key, path, x1, y1, x2, y2, tc } in world yards (x south
-- to north, y east to west), for Tiles.Draw.
function Indoor.Wanted(cam)
  local out = {}
  if not (City.Available() and cam.level and cam.level >= Indoor.MIN_LEVEL) then
    return out
  end
  local x1, y1, x2, y2 = cam:Bounds()
  for _, city in ipairs(B.Map.cities) do
    if Indoor.CITIES[city.ui] and city.continent == cam.continent and inView(city, x1, y1, x2, y2) then
      for row = 0, (city.rows or 0) - 1 do
        for col = 0, (city.cols or 0) - 1 do
          local north, west, south, east, u, v = City.TileRect(city, row, col)
          out[#out + 1] = {
            key = city.ui * 100 + row * 10 + col,
            path = city.path .. row .. "_" .. col,
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
    return
  end
  Tiles.Draw(Indoor, cam, wanted, Indoor.MAX_TEXTURES)
end

ns.mod.Indoor = Indoor
table.insert(Map.onView, Indoor.Render)
table.insert(Map.onResize, function(cam)
  Tiles.Reposition(Indoor, cam)
end)
