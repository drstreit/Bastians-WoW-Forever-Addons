-- Houses (map.md "City plans", ADR 0065): the buildings of a city sheet as an entity type, with the
-- people in them. The records come with the sheet (Bastians.Map.houses, from Bastians_Map_Art), so
-- without the art there are none. What a house's people sell, teach or offer comes from those
-- people's own sections through Core: no other app is called.
local _, ns = ...
local B = Bastians
local L = ns.L
local Map = ns.Map

local Houses = {}
ns.Houses = Houses

Houses.PIN = 18
Houses.CARD_PEOPLE = 6 -- people named on the hover card
Houses.ICONS = {
  bank = "banker",
  auction = "auctioneer",
  inn = "innkeeper",
  flight = "flight",
  stable = "service",
  trainer = "trainer",
  vendor = "vendor",
  quest = "quest",
}
Houses.ROLES = {
  bank = "Bank",
  auction = "Auction House",
  inn = "Inn",
  flight = "Flight master",
  stable = "Stable",
  trainer = "Trainers",
  vendor = "Vendors",
  quest = "Quests",
}

local indexed, byID, byNpc = nil, {}, {}

local function index()
  local source = B.Map and B.Map.houses or nil
  if source == indexed then
    return
  end
  indexed, byID, byNpc = source, {}, {}
  for ui, list in pairs(source or {}) do
    for _, house in ipairs(list) do
      house.ui = ui
      byID[house.id] = house
      for _, npc in ipairs(house.people or {}) do
        byNpc[npc] = house
      end
    end
  end
end

function Houses.Get(id)
  index()
  return byID[tostring(id)]
end

function Houses.OfNpc(npc)
  index()
  return byNpc[npc]
end

function Houses.Name(house)
  return L[house.name]
end

local function iconOf(house)
  local kind = Houses.ICONS[house.roles and house.roles[1] or ""]
  return kind and B.UI.IconTexture(kind) or B.UI.IconTexture("other")
end

function Houses.Summary(house)
  local words = {}
  for _, role in ipairs(house.roles or {}) do
    words[#words + 1] = L[Houses.ROLES[role] or role]
  end
  if house.district then
    words[#words + 1] = L[house.district]
  end
  return #words > 0 and table.concat(words, ", ") or nil
end

-- Whether a world point lies in a flat { wx, wy, ... } polygon (even-odd).
function Houses.Inside(poly, wx, wy)
  local inside = false
  local n = #poly / 2
  local jx, jy = poly[2 * n - 1], poly[2 * n]
  for i = 1, n do
    local ix, iy = poly[2 * i - 1], poly[2 * i]
    if (iy > wy) ~= (jy > wy) and wx < (jx - ix) * (wy - iy) / (jy - iy) + ix then
      inside = not inside
    end
    jx, jy = ix, iy
  end
  return inside
end

-- The house a point of a sheet lies in, the smallest when rooms overlap, or nil.
function Houses.At(ui, wx, wy)
  local found
  for _, house in ipairs(B.Map and B.Map.houses and B.Map.houses[ui] or {}) do
    if not found or house.area < found.area then
      for _, poly in ipairs(house.outlines or {}) do
        if Houses.Inside(poly, wx, wy) then
          found = house
          break
        end
      end
    end
  end
  return found
end

local function cardLines(house)
  local lines = {}
  for i, npc in ipairs(house.people or {}) do
    if i > Houses.CARD_PEOPLE then
      lines[#lines + 1] = string.format(L["and %d more"], #house.people - Houses.CARD_PEOPLE)
      break
    end
    local e = B:Entity("npc:" .. npc)
    local sub = e:Summary()
    local name = e:Name()
    if name then
      lines[#lines + 1] = sub and (name .. " - " .. sub) or name
    end
  end
  return lines
end

-- The pins of a sheet (fresh tables: they belong to the renderer).
function Houses.Pins(ui)
  local pins = {}
  for _, house in ipairs(B.Map and B.Map.houses and B.Map.houses[ui] or {}) do
    pins[#pins + 1] = {
      ref = "house:" .. house.id,
      wx = house.wx,
      wy = house.wy,
      icon = iconOf(house),
      label = Houses.Name(house),
      size = Houses.PIN,
      priority = 80,
      house = house,
      info = function()
        return cardLines(house)
      end,
    }
  end
  return pins
end

-- --- the page ------------------------------------------------------------------------------------

local function peopleRows(ref)
  local _, id = B.Entity.Parse(ref)
  local house = Houses.Get(id)
  if not house then
    return nil
  end
  local rows = {}
  for _, npc in ipairs(house.people or {}) do
    local r = "npc:" .. npc
    local e = B:Entity(r)
    rows[#rows + 1] = { ref = r, text = e:Name() or r, meta = e:Summary(), icon = e:Icon() }
  end
  return rows
end

-- One section of every person in the house, each thing once.
local function gathered(sectionID)
  return function(ref)
    local _, id = B.Entity.Parse(ref)
    local house = Houses.Get(id)
    if not house then
      return nil
    end
    local rows, seen = {}, {}
    for _, npc in ipairs(house.people or {}) do
      for _, section in ipairs(B:GetDetailSections("npc:" .. npc)) do
        if section.id == sectionID then
          for _, row in ipairs(section.rows or {}) do
            local key = row.ref or row.text
            if key == nil or not seen[key] then
              if key ~= nil then
                seen[key] = true
              end
              rows[#rows + 1] = row
            end
          end
        end
      end
    end
    return #rows > 0 and rows or nil
  end
end

function Houses.Register(mod)
  B:RegisterEntityType(mod, {
    type = "house",
    name = function(id)
      local house = Houses.Get(id)
      return house and Houses.Name(house) or nil
    end,
    icon = function(id)
      local house = Houses.Get(id)
      return house and iconOf(house) or nil
    end,
    summary = function(id)
      local house = Houses.Get(id)
      return house and Houses.Summary(house) or nil
    end,
    places = function(id)
      local house = Houses.Get(id)
      if not house then
        return nil
      end
      return { { map = house.continent, wx = house.wx, wy = house.wy, kind = "house", src = "client" } }
    end,
  })
  B:RegisterDetailSection(mod, {
    id = "map.house.people",
    title = L["People"],
    types = { "house" },
    order = 10,
    twoLine = true,
    build = peopleRows,
  })
  B:RegisterDetailSection(mod, {
    id = "map.house.quests",
    title = L["Quests"],
    types = { "house" },
    order = 20,
    invalidateOn = { "BASTIANS_QUESTS_CHANGED" },
    build = gathered("quests.starts"),
  })
  B:RegisterDetailSection(mod, {
    id = "map.house.sells",
    title = L["Sells"],
    types = { "house" },
    order = 30,
    build = gathered("data.vendor"),
  })
  B:RegisterDetailSection(mod, {
    id = "map.house.teaches",
    title = L["Teaches"],
    types = { "house" },
    order = 40,
    build = gathered("data.trainer"),
  })
  -- the way back: a row on the page of each person
  B:RegisterDetailSection(mod, {
    id = "map.house.of",
    title = L["House"],
    types = { "npc" },
    order = 89,
    link = L["house"],
    build = function(ref)
      local _, id = B.Entity.Parse(ref)
      local house = Houses.OfNpc(id)
      if not house then
        return nil
      end
      return { { ref = "house:" .. house.id, text = Houses.Name(house), icon = iconOf(house) } }
    end,
  })
end

table.insert(Map.onEnable, function(self)
  Houses.Register(self)
end)

ns.mod.Houses = Houses
