-- The place names: the names of the map as a layer of words, not
-- pixels in the cells (baked names did not scale and could not be hidden). Since 29.10.2026 (owner:
-- "I like a lot that a wider zoom only shows me the main cities, but zooming in gives me details on
-- the blizzard seamless - I want the same for all") every style names the map as the Blizzard style
-- does (ADR 0036): Blizzard's own labels where its paintings set them, as tall against the map as
-- Blizzard's letters, each from its own zoom level; the subzones they leave out come closer in,
-- sized by their patch. The tables come from tools/mapstyle (Generated/Names.lua).
local _, ns = ...
local B = Bastians
local L = ns.L
local Map = ns.Map

local Names = {}
ns.Names = Names

Names.LAYER = "map.names"

local byContinent = {} -- continent -> array of { text, wx, wy, chunks }: the subzones
local named = {} -- continent -> Blizzard's labels { text, wx, wy, height, kind, area, level }
local covered = {} -- continent -> { [plain text] = true }: the subzones Blizzard's labels name

-- Generated/Names.lua calls this once per client: { client, build, continents = { [continent] =
-- { { text, wx, wy, chunks }, ... } }, labels = { [continent] = { Blizzard's labels } } (Forever,
-- from the Blizzard map's build) }; a table built for the other client is kept out.
function B.Map.RegisterNames(info)
  if type(info) ~= "table" or type(info.continents) ~= "table" then
    return
  end
  if info.client and B.Client and info.client ~= B.Client then
    return
  end
  for continent, list in pairs(info.continents) do
    if type(list) == "table" then
      byContinent[continent] = list
    end
  end
  for continent, list in pairs(type(info.labels) == "table" and info.labels or {}) do
    if type(list) == "table" then
      named[continent] = list
      covered[continent] = nil
    end
  end
  if ns.Pins and ns.Pins.Requery then
    ns.Pins.Requery()
  end
end

-- How many subzone names a continent has.
function Names.Count(continent)
  return #(byContinent[continent] or {})
end

-- How many of Blizzard's labels a continent has.
function Names.LabelCount(continent)
  return #(named[continent] or {})
end

-- Blizzard's labels (ADR 0036): where and as tall as the paintings set them, so they keep their size
-- against the map as it zooms (within LABEL_MIN..LABEL_MAX).
Names.LABEL_MIN, Names.LABEL_MAX = 9, 24
Names.LABEL_SCALE = 0.9 -- a font's size against the height of Blizzard's letters
local INK = { place = "text", city = "text", sea = "dim" }

-- The subzones Blizzard's labels leave out (or every subzone without them): as tall as a share of
-- their patch's side, from the level where that reads, with Blizzard's labels not before its
-- districts' level.
Names.CHUNK_YARDS = 100 / 3 -- an ADT chunk's side
Names.DETAIL_SCALE = 0.12 -- a subzone's letters against the side of its patch (100 chunks: 40 yd)
Names.DETAIL_MIN, Names.DETAIL_MAX = 15, 250 -- yards
Names.DETAIL_LEVEL = 3 -- with Blizzard's labels: the other subzones from this level on
Names.DETAIL_TEXT = 50 -- yards: a taller subzone name in the text ink, a smaller one in the dim

-- The words in the client's font where it writes Hangul, Han or Cyrillic (S.CLIENT_FONT), else the style's
-- face.
local function face(st)
  if B.UI.Style.CLIENT_FONT then
    return nil
  end
  return st and st.font or nil
end

-- A label's words: the client's own name for the area in its language, else Blizzard's English
-- with its line breaks.
local english = { enUS = true, enGB = true }
local function labelText(entry)
  local area = entry[6]
  if area and not english[GetLocale and GetLocale() or "enUS"] then
    local name = B.Compat.AreaName(area)
    if name and name ~= "" then
      return name
    end
  end
  return entry[1]
end

function Names.LabelSize(height, level)
  local px = height * ns.Camera.PX_PER_YARD_L0 * 2 ^ (level or 0) * Names.LABEL_SCALE
  return math.floor(math.max(Names.LABEL_MIN, math.min(Names.LABEL_MAX, px)) + 0.5)
end

-- The letters' height in yards of a subzone of `chunks` ADT chunks.
function Names.DetailHeight(chunks)
  local side = math.sqrt(math.max(chunks or 1, 1)) * Names.CHUNK_YARDS
  return math.max(Names.DETAIL_MIN, math.min(Names.DETAIL_MAX, side * Names.DETAIL_SCALE))
end

-- The first zoom level at which letters `height` yards tall read (LABEL_MIN points or more).
function Names.ReadsFrom(height)
  local px = height * ns.Camera.PX_PER_YARD_L0 * Names.LABEL_SCALE
  return math.max(0, math.ceil(math.log(Names.LABEL_MIN / px) / math.log(2) - 1e-9))
end

function Names.StyleQuery(view, list, font)
  local pins = {}
  for _, e in ipairs(list or {}) do
    local wx, wy, kind, level = e[2], e[3], e[5], e[7] or 0
    if view.level >= level and wx >= view.x1 and wx <= view.x2 and wy >= view.y1 and wy <= view.y2 then
      pins[#pins + 1] = {
        kind = "text",
        wx = wx,
        wy = wy,
        label = labelText(e),
        size = Names.LabelSize(e[4], view.level),
        font = font,
        ink = INK[kind] or "text", -- the map's dark twin of it (Pins, 29.10.2026): no outline
        priority = kind == "city" and 38 or 20 + math.min(15, math.floor(e[4] / 4)),
      }
    end
  end
  return pins
end

local function plain(text)
  return (string.gsub(string.lower(text), "%s+", " "))
end

local function coveredOf(continent)
  local set = covered[continent]
  if not set then
    set = {}
    for _, e in ipairs(named[continent] or {}) do
      set[plain(e[1])] = true
    end
    covered[continent] = set
  end
  return set
end

-- The subzones in view as text pins into `pins`: those Blizzard's labels name are left out (with
-- `withLabels`); below Blizzard's labels in priority, the bigger patch above the smaller.
function Names.AddDetails(pins, view, withLabels, font)
  local skip = withLabels and coveredOf(view.continent) or nil
  for _, n in ipairs(byContinent[view.continent] or {}) do
    local wx, wy = n[2], n[3]
    if wx >= view.x1 and wx <= view.x2 and wy >= view.y1 and wy <= view.y2 then
      local height = Names.DetailHeight(n[4])
      local from = Names.ReadsFrom(height)
      if withLabels then
        from = math.max(from, Names.DETAIL_LEVEL)
      end
      if view.level >= from and not (skip and skip[plain(n[1])]) then
        pins[#pins + 1] = {
          kind = "text",
          wx = wx,
          wy = wy,
          label = n[1],
          size = Names.LabelSize(height, view.level),
          font = font,
          ink = height >= Names.DETAIL_TEXT and "text" or "dim",
          priority = 10 + math.min(9, math.floor((n[4] or 0) / 50)),
        }
      end
    end
  end
  return pins
end

-- The layer's query: the names inside the view as text pins. The Blizzard style shows its own
-- labels; every other style Blizzard's labels from Names.lua (where the build has them) and the
-- subzones they leave out, or the subzones alone. Where two would overlap the higher priority
-- stays (Pins); the zone names (40) above all.
function Names.Query(view)
  if view.minimap then
    return {}
  end
  local st = ns.Styles and ns.Styles.Get(Map.StyleOn(view.continent))
  if st and st.labels then
    return Names.StyleQuery(view, st.labels[view.continent], face(st))
  end
  local labels = named[view.continent]
  local pins = labels and Names.StyleQuery(view, labels, face(st)) or {}
  return Names.AddDetails(pins, view, labels ~= nil, face(st))
end

table.insert(Map.onEnable, function(self)
  B:RegisterMapLayer(self, {
    id = Names.LAYER,
    icon = "copy", -- the layer bar shows its icon (R27.8)
    label = L["Place names"],
    tip = L["The names of villages, camps and places, larger as you zoom in."],
    defaultOn = true,
    minLevel = 0, -- each name from its own level (Query)
    query = Names.Query,
  })
end)
ns.mod.Names = Names
