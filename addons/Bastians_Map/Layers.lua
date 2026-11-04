-- The map's own layers: the map as a view
-- on the world graph. Zone information (the name with its level band; hovered: the creatures'
-- levels, the typical resource nodes, a lore link when Spoken's places are installed), and the
-- points of interest by the `poi` facet's role groups (travel, services, vendors, trainers,
-- crafting, resource nodes), queried for the view's rectangle from the zones that overlap it.
-- The dungeons and raids at their doors, switched on when one of them is focused or shown.
-- An NPC with several places in view (one who walks about) is one pin and a faint line through
-- its places, not a pin per place.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Map = ns.Map

local Layers = {}
ns.Layers = Layers

Layers.MAX_PINS = 300 -- per layer and view; the nearest the view's centre stay
Layers.WALKER_YARDS = 400 -- places of one NPC this close together are its walk, one pin
Layers.TYPICAL_NODES = 4 -- resource nodes named in a zone's information

local rects = {} -- continent -> { { ui, x1, y1, x2, y2 } } of its zones (world yards), built once
local infos = {} -- uiMapID -> the zone information lines, built once per data load

local function data()
  return B:GetService("data")
end

-- The zones of a continent with their world rectangles (Data's zone records, the transforms).
function Layers.ZoneRects(continent)
  if rects[continent] then
    return rects[continent]
  end
  local d = data()
  local out = {}
  for _, id in ipairs(d and d:Each("zone") or {}) do
    local z = d:Get("zone", id)
    if z and z.continent == continent and z.mapType == 3 then
      local c1, ax, ay = B.Coords.ToWorld(id, 0, 0)
      local c2, bx, by = B.Coords.ToWorld(id, 1, 1)
      if c1 == continent and c2 == continent then
        out[#out + 1] = {
          ui = id,
          x1 = math.min(ax, bx),
          x2 = math.max(ax, bx),
          y1 = math.min(ay, by),
          y2 = math.max(ay, by),
        }
      end
    end
  end
  table.sort(out, function(a, b)
    return a.ui < b.ui
  end)
  rects[continent] = out
  return out
end

local function overlaps(r, view)
  return r.x1 <= view.x2 and r.x2 >= view.x1 and r.y1 <= view.y2 and r.y2 >= view.y1
end

local function inside(p, view)
  return p.wx >= view.x1 and p.wx <= view.x2 and p.wy >= view.y1 and p.wy <= view.y2
end

-- --- zone information ---------------------------------------------------------------------------

-- The lore of a zone in Spoken's places is Bastian's Voice's `voice.play` since 01.11.2026
-- (voice.md); the old `SpokenZones:ShowLoreFor` belonged to Spoken before 3.0 and is gone.

-- Whether LoreForever is loaded (it has no public calls; its /lore command opens it).
function Layers.LoreForever()
  local info = B.Compat.GetAddOnInfo("LoreForever")
  return info ~= nil and info.loaded == true
end

-- The lines under a zone's name in its card: the creatures' levels (the middle 80 % of its NPCs
-- without a service), the typical resource nodes (by spawns in the zone), where its lore is.
function Layers.ZoneInfo(ui)
  if infos[ui] then
    return infos[ui]
  end
  local d = data()
  local lines = {}
  if d then
    local levels = {}
    for id in d:ByZone("npc", ui) do
      local r = d:Get("npc", id)
      if r and type(r.level) == "number" and not B:Entity("npc:" .. id):Facet("poi") then
        levels[#levels + 1] = r.level
        if type(r.levelMax) == "number" and r.levelMax ~= r.level then
          levels[#levels + 1] = r.levelMax
        end
      end
    end
    if #levels > 0 then
      table.sort(levels)
      local lo = levels[math.max(1, math.floor(#levels * 0.1 + 0.5))]
      local hi = levels[math.max(1, math.floor(#levels * 0.9 + 0.5))]
      lines[#lines + 1] = string.format(L["Creatures: level %s"], lo == hi and lo or (lo .. "-" .. hi))
    end
    local nodes = {}
    for id in d:ByZone("node", ui) do
      local r = d:Get("node", id)
      if r and r.name then
        local n = 0
        for _, s in ipairs(r.spawns or {}) do
          if s[1] == ui then
            n = n + 1
          end
        end
        nodes[#nodes + 1] = { name = r.name, n = n }
      end
    end
    table.sort(nodes, function(a, b)
      if a.n ~= b.n then
        return a.n > b.n
      end
      return a.name < b.name
    end)
    local names = {}
    for i = 1, math.min(#nodes, Layers.TYPICAL_NODES) do
      names[i] = nodes[i].name
    end
    if #names > 0 then
      lines[#lines + 1] = L["Resources:"] .. " " .. table.concat(names, ", ")
    end
  end
  -- the zone's lore in Spoken: Voice's Play button on the card (voice.md), no line needed here
  if Layers.LoreForever() then
    lines[#lines + 1] = L["Lore: type /lore (LoreForever)"]
  end
  infos[ui] = lines
  return lines
end

local function zonePins(view)
  if view.minimap then
    return {} -- words on the minimap would cover it
  end
  local d = data()
  local pins = {}
  for _, r in ipairs(Layers.ZoneRects(view.continent)) do
    if overlaps(r, view) then
      local z = d:Get("zone", r.ui)
      local c, wx, wy = B.Coords.ToWorld(r.ui, 0.5, 0.5)
      if z and z.name and c == view.continent then
        local band = (z.levelLo and z.levelHi) and (z.levelLo .. "-" .. z.levelHi) or nil
        local ui = r.ui
        pins[#pins + 1] = {
          kind = "text",
          ref = "zone:" .. ui,
          wx = wx,
          wy = wy,
          label = z.name,
          sub = band,
          priority = 40,
          info = function()
            return Layers.ZoneInfo(ui)
          end,
        }
      end
    end
  end
  return pins
end

-- --- points of interest by role ---------------------------------------------------------------

-- role (the poi facet's word) -> the glyph kind of its pin
local ROLE_ICON = {
  ["travel.flightmaster"] = "flight",
  ["travel.dock"] = "route",
  ["travel.portal"] = "open",
  ["travel.meetingstone"] = "other",
  ["rest.inn"] = "innkeeper",
  ["rest.stable"] = "service",
  ["money.bank"] = "banker",
  ["money.auction"] = "auctioneer",
  ["money.mailbox"] = "service",
  ["money.repair"] = "repair",
  ["gather.herb"] = "herb",
  ["gather.ore"] = "mine",
  ["gather.fish"] = "fish",
  ["gather.treasure"] = "treasure",
}

-- The first role of the entity that a prefix of the layer matches, or nil.
local function matchRole(ref, prefixes)
  local poi = B:Entity(ref):Facet("poi")
  for _, role in ipairs(poi and poi.roles or {}) do
    for _, prefix in ipairs(prefixes) do
      if role == prefix or string.sub(role, 1, #prefix + 1) == prefix .. "." then
        return role
      end
    end
  end
  return nil
end

-- The places of one walker in walking order: from the first, always the nearest next (the data
-- keeps spawns, not paths).
local function walkOrder(places)
  local left, out = {}, { places[1] }
  for i = 2, #places do
    left[#left + 1] = places[i]
  end
  while #left > 0 do
    local last, bi, bd = out[#out], 1, nil
    for i, p in ipairs(left) do
      local d = (p.wx - last.wx) ^ 2 + (p.wy - last.wy) ^ 2
      if not bd or d < bd then
        bi, bd = i, d
      end
    end
    out[#out + 1] = table.remove(left, bi)
  end
  return out
end

-- Whether the places lie together (one NPC walking about), not spread over the world.
local function together(places)
  local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
  for _, p in ipairs(places) do
    x1, x2 = math.min(x1, p.wx), math.max(x2, p.wx)
    y1, y2 = math.min(y1, p.wy), math.max(y2, p.wy)
  end
  return x2 - x1 <= Layers.WALKER_YARDS and y2 - y1 <= Layers.WALKER_YARDS
end

-- A layer's query over the zones in view: matching entities inside the view.
Layers.AREA_MIN_YARDS = 15 -- a creature roaming at least this far gets a soft area (W5)

local function poiQuery(types, prefixes, fallbackIcon, priority)
  return function(view)
    local d = data()
    -- on the minimap too ("better use ours on all"; the game's tracking
    -- shows them only on its own minimap and only one kind at a time)
    if not d then
      return {}
    end
    local seen, pins, paths = {}, {}, {}
    local cx, cy = (view.x1 + view.x2) / 2, (view.y1 + view.y2) / 2
    local function consider(typ, id)
      local ref = typ .. ":" .. id
      if seen[ref] then
        return
      end
      seen[ref] = true
      local role = matchRole(ref, prefixes)
      if not role then
        return
      end
      local here = {}
      for _, p in ipairs(B:Entity(ref):Places()) do
        if p.map == view.continent and p.wx and inside(p, view) then
          here[#here + 1] = p
        end
      end
      if #here == 0 then
        return
      end
      local walker = typ == "npc" and #here > 1 and together(here)
      local list = walker and { walkOrder(here)[1] } or here
      if walker then
        local points = {}
        for _, p in ipairs(walkOrder(here)) do
          points[#points + 1] = { p.wx, p.wy }
        end
        paths[#paths + 1] = { kind = "path", points = points, color = S.C.dim, width = 1, style = "dashed" }
      end
      local name = B:Entity(ref):Name()
      if role and string.sub(role, 1, 7) == "trainer" then
        -- what the trainer trains, from its subname ("Alchemy Trainer";
        -- "I see the trainer names - but not what they train")
        local rec = d:Get("npc", id)
        local words = type(rec) == "table"
          and type(rec.subname) == "string"
          and rec.subname:match("^(.-)%s+[Tt]rainer$")
        if words and words ~= "" and name then
          name = name .. " (" .. words .. ")"
        end
      end
      for _, p in ipairs(list) do
        pins[#pins + 1] = {
          radius = p.r and p.r >= Layers.AREA_MIN_YARDS and p.r or nil, -- where it roams (W5)
          ref = ref,
          wx = p.wx,
          wy = p.wy,
          icon = B.UI.IconTexture(ROLE_ICON[role] or fallbackIcon),
          label = name,
          priority = priority,
          d = (p.wx - cx) ^ 2 + (p.wy - cy) ^ 2,
        }
      end
    end
    for _, typ in ipairs(types) do
      if d:Index(typ .. ".byZone") then
        for _, r in ipairs(Layers.ZoneRects(view.continent)) do
          if overlaps(r, view) then
            for id in d:ByZone(typ, r.ui) do
              consider(typ, id)
            end
          end
        end
      else
        for _, id in ipairs(d:Each(typ) or {}) do -- a small type without a zone index (taxi nodes)
          consider(typ, id)
        end
      end
    end
    if #pins > Layers.MAX_PINS then
      table.sort(pins, function(a, b)
        if a.d ~= b.d then
          return a.d < b.d
        end
        return a.ref < b.ref
      end)
      for i = #pins, Layers.MAX_PINS + 1, -1 do
        pins[i] = nil
      end
    end
    for _, path in ipairs(paths) do
      pins[#pins + 1] = path
    end
    return pins
  end
end

-- --- monsters ---------------------------------------------------------------------------------

-- Monsters ("I dont have a mob filter in the map - can we do that as
-- regions for all mobs? clickable to open the browser for that mob"): every monster of the zones
-- in view as soft regions where it stands, tinted by its level against the character's; one region
-- per group of its places that lie together (each within MOB_LINK yards of another), as wide as
-- the group and where it roams. The pin in a region's middle opens the monster's page (the pins'
-- left click: the Browser when it is there), its card names it.
Layers.MOB_LINK = 60 -- yards
Layers.MOB_MIN_RADIUS = 20 -- yards: a lone place's region

-- Groups of places that lie together (single link); each { wx, wy, r }. Pure.
function Layers.MobRegions(places, link)
  link = link or Layers.MOB_LINK
  local regions, taken = {}, {}
  for i = 1, #places do
    if not taken[i] then
      taken[i] = true
      local group = { places[i] }
      local k = 1
      while k <= #group do
        local a = group[k]
        for j = 1, #places do
          local b = places[j]
          if not taken[j] and (a.wx - b.wx) ^ 2 + (a.wy - b.wy) ^ 2 <= link * link then
            taken[j] = true
            group[#group + 1] = b
          end
        end
        k = k + 1
      end
      local cx, cy = 0, 0
      for _, p in ipairs(group) do
        cx, cy = cx + p.wx, cy + p.wy
      end
      cx, cy = cx / #group, cy / #group
      local r = Layers.MOB_MIN_RADIUS
      for _, p in ipairs(group) do
        r = math.max(r, math.sqrt((p.wx - cx) ^ 2 + (p.wy - cy) ^ 2) + (p.r or 0))
      end
      regions[#regions + 1] = { wx = cx, wy = cy, r = r, n = #group }
    end
  end
  return regions
end

local function monsterPins(view)
  local d = data()
  if view.minimap or not (d and d.IsMonster and d:Index("npc.byZone")) then
    return {} -- regions would cover the minimap
  end
  local _, _, playerLevel = B.Compat.GetPlayerXP()
  local pins, seen = {}, {}
  local cx, cy = (view.x1 + view.x2) / 2, (view.y1 + view.y2) / 2
  for _, rect in ipairs(Layers.ZoneRects(view.continent)) do
    if overlaps(rect, view) then
      for id in d:ByZone("npc", rect.ui) do
        local r = not seen[id] and d:Get("npc", id)
        seen[id] = true
        if r and d:IsMonster(r) then
          local ref = "npc:" .. id
          local here = {}
          for _, p in ipairs(B:Entity(ref):Places()) do
            if p.map == view.continent and p.wx and inside(p, view) then
              here[#here + 1] = p
            end
          end
          local token = S.LevelToken(r.level, playerLevel)
          local level = r.level
            and (r.levelMax and r.levelMax ~= r.level and (r.level .. "-" .. r.levelMax) or r.level)
          local label = (r.name or ref) .. (level and ("  " .. level) or "")
          for _, region in ipairs(Layers.MobRegions(here)) do
            pins[#pins + 1] = {
              ref = ref,
              wx = region.wx,
              wy = region.wy,
              radius = region.r,
              icon = B.UI.IconTexture("mob"),
              color = token and S.C[token] or nil,
              label = label,
              priority = 30,
              d = (region.wx - cx) ^ 2 + (region.wy - cy) ^ 2,
            }
          end
        end
      end
    end
  end
  if #pins > Layers.MAX_PINS then
    table.sort(pins, function(a, b)
      if a.d ~= b.d then
        return a.d < b.d
      end
      return a.ref < b.ref
    end)
    for i = #pins, Layers.MAX_PINS + 1, -1 do
      pins[i] = nil
    end
  end
  return pins
end
Layers.MonsterPins = monsterPins

-- --- dungeons ---------------------------------------------------------------------------------

-- Dungeons and raids ("when I click in the browser on a dungeon, I expect
-- to see it - so switch on the dungeon layer automatically"): a pin at every door of the zones in
-- view, named after its dungeon and opening the dungeon's page (and ringed when the dungeon is
-- focused); a door of an instance without a dungeon record keeps its own name and page.
local function dungeonPins(view)
  local d = data()
  if not d or not d:Index("entrance.byZone") then
    return {}
  end
  local seen, pins = {}, {}
  for _, r in ipairs(Layers.ZoneRects(view.continent)) do
    if overlaps(r, view) then
      for id in d:ByZone("entrance", r.ui) do
        local door = "entrance:" .. id
        if not seen[door] then
          seen[door] = true
          local rec = d:Get("entrance", id)
          local instance = rec and rec.instance
          local ref = instance and d:Get("dungeon", instance) and ("dungeon:" .. instance) or door
          for _, p in ipairs(B:Entity(door):Places()) do
            if p.map == view.continent and p.wx and inside(p, view) then
              pins[#pins + 1] = {
                ref = ref,
                wx = p.wx,
                wy = p.wy,
                icon = B.UI.IconTexture("keep"),
                label = B:Entity(ref):Name(),
                priority = 55,
              }
            end
          end
        end
      end
    end
  end
  return pins
end

-- The entity types a layer of ours draws when that layer is switched off would hide them: a
-- focused dungeon (a click in the Browser) or "Show on map" switches the layer on.
Layers.SHOWS = { dungeon = "map.dungeons", entrance = "map.dungeons" }

function Layers.Reveal(ref)
  local typ = type(ref) == "string" and B.Entity.Parse(ref)
  local id = typ and Layers.SHOWS[typ]
  if id then
    B:Fire("BASTIANS_LAYER_CHANGED", id, "show") -- Pins.lua switches it on and queries again
  end
end

-- The layers, in the order of the bar (map.md's table). a layer that
-- vanishes when zooming out confuses, so they start low and cluster there.
Layers.DEFS = {
  {
    id = "map.zones",
    icon = "zone",
    label = "Zone information",
    on = true,
    min = 0, -- at every zoom: the only zone names
    query = zonePins,
  },
  {
    id = "map.travel",
    icon = "flight",
    label = "Travel",
    on = true,
    min = 1,
    query = poiQuery({ "npc", "object", "flightpath", "transport" }, { "travel" }, "flight", 60),
  },
  {
    id = "map.dungeons", -- the doors left Travel for a layer of their own (31.10.2026)
    icon = "keep",
    label = "Dungeons and raids",
    on = true,
    min = 1,
    query = dungeonPins,
  },
  {
    id = "map.services",
    icon = "service",
    label = "Services",
    on = true,
    min = 2,
    query = poiQuery({ "npc", "object" }, { "rest", "money" }, "service", 50),
  },
  {
    id = "map.vendors",
    icon = "vendor",
    label = "Vendors",
    on = false,
    min = 2,
    query = poiQuery({ "npc" }, { "vendor" }, "vendor", 45),
  },
  {
    id = "map.trainers",
    icon = "trainer",
    label = "Trainers",
    on = false,
    min = 2,
    query = poiQuery({ "npc" }, { "trainer" }, "trainer", 45),
  },
  {
    id = "map.crafting",
    icon = "leather",
    label = "Crafting",
    on = false,
    min = 2,
    query = poiQuery({ "object" }, { "craft" }, "service", 40),
  },
  {
    id = "map.nodes",
    icon = "herb",
    label = "Resource nodes",
    on = false,
    min = 2,
    query = poiQuery({ "node", "object" }, { "gather" }, "herb", 35),
  },
  {
    id = "map.monsters",
    icon = "mob",
    label = "Monsters",
    on = false,
    min = 2,
    query = monsterPins,
  },
}

table.insert(Map.onEnable, function(self)
  for _, def in ipairs(Layers.DEFS) do
    B:RegisterMapLayer(self, {
      id = def.id,
      icon = def.icon, -- the layer bar shows it (R27.8)
      label = L[def.label],
      defaultOn = def.on,
      minLevel = def.min,
      maxLevel = def.max,
      query = def.query,
    })
  end
  -- a focused dungeon or door switches its layer on ("when I click in the
  -- browser on a dungeon, I expect to see it"); the zone lore moved to Bastian's Voice (B7.10)
  table.insert(Map.onFocus, Layers.Reveal)
end)

-- New zones or transforms (Imagery.lua's BASTIANS_DATA_LOADED handler calls this: one bus handler
-- per message and module; the view is queried again there).
function Layers.Reset()
  rects, infos = {}, {}
end

ns.mod.Layers = Layers
