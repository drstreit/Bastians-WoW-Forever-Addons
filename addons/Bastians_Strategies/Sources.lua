-- Bastian's Book: how to get a wonder (book.md "The wonder's page", R4.4; book-look.md 10.5):
-- its sources as rows. A source is a reference in the pack (`from = { { how, ref } }`, R4.3);
-- its name, place, level, odds and price are read here from the entity and the data service,
-- so nothing is copied. Without the World or Items pack a source has only its reference's name,
-- or nothing: the wonder's sentence stays (every app works alone).
local _, ns = ...
local B = Bastians
local L = ns.L

local Sources = {}
ns.Sources = Sources

local floor = math.floor

Sources.SHOWN = 5 -- rows before "N more sources"
Sources.LIKELY = 25 -- from this chance up the odds read as a percentage

-- The pictogram of a way to get something (Core's glyphs).
Sources.GLYPH = {
  drop = "mob",
  vendor = "vendor",
  quest = "quest",
  craft = "item",
  make = "item",
  container = "treasure",
  skin = "leather",
  pick = "herb",
  fish = "fish",
  object = "object",
}

-- The odds of a chance in percent, as a reader says them: 2 is "1 in 50", 0.4 "1 in 250"; from
-- 25 up "about 40 %". Unknown (nil, zero or less) is nothing: never "0" (golden rule 2).
function Sources.Odds(chance)
  chance = tonumber(chance)
  if not chance or chance <= 0 then
    return nil
  end
  if chance >= Sources.LIKELY then
    return string.format(L["about %d %%"], floor(chance + 0.5))
  end
  return string.format(L["1 in %d"], floor(100 / chance + 0.5))
end

local function data()
  return B:GetService("data")
end

local function record(typ, id)
  local d = data()
  return d and d.Get and d:Get(typ, id) or nil
end

-- The chance (percent) that `ref` gives one of the wonder's items, nil when no list says.
local function chanceOf(ref, items)
  for _, item in ipairs(items or {}) do
    local r = record("item", item)
    for _, d in ipairs(r and r.drops or {}) do
      if d[1] == ref and tonumber(d[2]) then
        return tonumber(d[2])
      end
    end
  end
  local typ, id = B.Entity.Parse(ref)
  local r = (typ == "npc" or typ == "object") and record(typ, id) or nil
  for _, l in ipairs(r and r.loot or {}) do
    for _, item in ipairs(items or {}) do
      if l[1] == item and tonumber(l[2]) then
        return tonumber(l[2])
      end
    end
  end
  return nil
end

-- A vendor's price for one of the wonder's items -> copper, the stack it buys (nil: one).
local function priceOf(ref, items)
  local typ, id = B.Entity.Parse(ref)
  local r = typ == "npc" and record("npc", id) or nil
  for _, v in ipairs(r and r.vendor or {}) do
    for _, item in ipairs(items or {}) do
      if v[1] == item and tonumber(v[2]) then
        return tonumber(v[2]), tonumber(v[3])
      end
    end
  end
  return nil
end

-- The first known place of a thing: { map, x, y } in map fractions, or nil.
local function placeOf(ref)
  local ent = B:Entity(ref)
  local points = ent and ent.Locations and ent:Locations() or nil
  local p = type(points) == "table" and points[1] or nil
  if p and p.map and p.x and p.y then
    return { p.map, p.x, p.y } -- a uiMap and its fractions
  end
  local s = B.UI.Scenery and B.UI.Scenery.FirstPlace(ref)
  if s then
    return { s.map, s.x, s.y }
  end
  return nil
end

-- One source of the wonder `e` as a row: { how, ref, name, glyph, place = { map, x, y }, zone =
-- uiMapID, zoneName, levelMin, levelMax, chance, odds, price, stack }. Every fact is nil where
-- the packs know nothing (unknown is not zero).
function Sources.Row(e, how, ref)
  local typ, id = B.Entity.Parse(ref)
  if not typ then
    return nil
  end
  local ent = B:Entity(ref)
  local row = {
    how = how,
    ref = ref,
    name = ent and ent:Name() or nil,
    glyph = Sources.GLYPH[how] or (typ == "object" and "object") or "other",
  }
  local r = record(typ, id)
  row.place = placeOf(ref)
  row.zone = (row.place and row.place[1]) or (r and r.zone) or nil
  local zone = row.zone and ns.Front.ZoneOf(row.zone)
  row.zoneName = zone and zone.name or nil
  if r then
    if typ == "npc" then
      row.levelMin, row.levelMax = r.levelLo or r.level, r.levelHi or r.level
    elseif typ == "quest" then
      row.levelMin, row.levelMax = r.level, r.level
    end
  end
  if how == "vendor" then
    row.price, row.stack = priceOf(ref, e.gives)
  elseif how ~= "quest" and how ~= "craft" and how ~= "make" then
    row.chance = chanceOf(ref, e.gives)
    row.odds = Sources.Odds(row.chance)
  end
  return row
end

-- The rows of a wonder's sources, in the pack's order (the one the tale tells first); a source
-- without a name (no pack knows it) is left out. -> rows (may be empty)
function Sources.Of(e)
  local out = {}
  for _, s in ipairs(e.from or {}) do
    local row = Sources.Row(e, s[1], s[2])
    if row and row.name then
      out[#out + 1] = row
    end
  end
  return out
end

-- The line under a source's name: where it is and its level.
function Sources.Where(row)
  local parts = {}
  parts[#parts + 1] = row.zoneName
  if row.levelMin then
    if row.levelMax and row.levelMax ~= row.levelMin then
      parts[#parts + 1] = string.format(L["level %d to %d"], row.levelMin, row.levelMax)
    else
      parts[#parts + 1] = string.format(L["level %d"], row.levelMin)
    end
  end
  return table.concat(parts, "  -  ")
end
