-- Bastian's Book: the shelf (book.md "Filters and search"): every wonder and gold page as one
-- entry; the filters and their counts, the search, the sorts, the day's order, the front table
-- and the simulation. Pure: plain tables in, plain tables out.
local _, ns = ...

local Shelf = {}
ns.Shelf = Shelf

local ipairs, pairs, type, tostring = ipairs, pairs, type, tostring
local lower, find, gsub, byte, char = string.lower, string.find, string.gsub, string.byte, string.char
local floor, max, sqrt = math.floor, math.max, math.sqrt

-- The chapters, named by what the reader does (book.md "The chapters", E1; ~~treasures,
-- curiosities~~ until 17.11.2026). The order is the tabs'.
Shelf.CHAPTERS = { "gold", "secrets", "collections", "camp", "rares" }
Shelf.LEVEL_CAP = 60
Shelf.NEW_DAYS = 7 -- a wonder this new wears the ribbon
Shelf.MY_LEVEL = 3 -- "my level": yours, three below to three above

-- The facets of each chapter, in the order the filter shows them (book.md "The chapters").
-- `all`: the facets every chapter shares, for the Everything tab.
Shelf.FACETS = {
  all = { "chapter", "side" },
  gold = { "kind" },
  secrets = { "kind", "side" },
  collections = { "kind", "source", "side" },
  camp = { "profession", "skill", "kind" },
  rares = { "kind", "type" },
}
-- A shelf that is always in one order has no sort group (R4.8): Gold, newest first.
Shelf.FIXED_SORT = { gold = "dated" }

-- A pack of before round 4 (an older Data edition under a newer suite): its two chapters by the
-- kind, so every wonder still stands on a shelf. { old kind = { chapter, kind } }
local OLD_KINDS = {
  secret = { "secrets", "chain" },
  ["secret pet"] = { "secrets", "pet" },
  camping = { "camp", "camping" },
  library = { "collections", "library" },
  ["library book"] = { "collections", "library book" },
  ["camp kit"] = { "camp", "camp kit" },
  ["camp item"] = { "camp", "camp item" },
}

-- ---------------------------------------------------------------------------------------------
-- Entries
-- ---------------------------------------------------------------------------------------------

-- A wonder record of the book's pack (book.md "The data") as an entry.
function Shelf.FromWonder(id, rec)
  local chapter, kind = rec.chapter, rec.kind
  if chapter == "treasures" or chapter == "curiosities" then
    local now = OLD_KINDS[kind]
    chapter, kind = now and now[1] or "secrets", now and now[2] or kind
    if kind == "chain" and rec.facets and rec.facets.unsolved then
      kind = "unsolved"
    end
  end
  return {
    id = id,
    chapter = chapter,
    kind = kind,
    title = rec.name or id,
    hook = rec.hook,
    tale = rec.tale,
    start = rec.start,
    note = rec.note,
    levelMin = rec.levelMin,
    levelMax = rec.levelMax,
    zones = rec.zones,
    place = rec.place,
    side = rec.side,
    facets = rec.facets or {},
    gives = rec.gives,
    steps = rec.steps,
    done = rec.done,
    npc = rec.npc,
    added = rec.added,
    art = rec.art,
    -- what is obtainable (E2): "in" or "unknown"; a pack without it (before round 4) is shown
    state = rec.state,
    from = rec.from, -- the sources as references, { { how, ref } } (R4.3)
  }
end

-- In the client, and nobody reported it in Forever yet: off the front table, on a shelf only
-- behind the chip "unconfirmed" (book.md "What is obtainable").
function Shelf.Unconfirmed(e)
  return e.state == "unknown"
end

-- A gold page (strategies.md) as an entry: its chapter is the kind, `lead` its first line.
function Shelf.FromPage(id, p, lead)
  local place = p.plate and p.plate.place
  return {
    id = id,
    chapter = "gold",
    kind = p.chapter,
    title = p.name or id,
    hook = lead,
    levelMin = p.levelMin,
    levelMax = p.levelMax,
    zones = p.zones,
    place = place and place[1] and { place[1], place[2], place[3] } or nil,
    facets = {},
    added = p.updated or p.added,
    art = p.art,
    page = true,
    back = p.shelf == "back" or nil, -- the back shelf: found by a search only
  }
end

-- The value of facet `key` for an entry; nil: the entry has none (it passes no chip of it).
function Shelf.FacetOf(e, key)
  if key == "chapter" then
    return e.chapter
  elseif key == "kind" then
    return e.kind
  elseif key == "side" then
    return e.side or "both"
  end
  return e.facets and e.facets[key] or nil
end

-- ---------------------------------------------------------------------------------------------
-- The text a search looks in, and the query
-- ---------------------------------------------------------------------------------------------

local FOLD = {
  ["\195\160"] = "a",
  ["\195\161"] = "a",
  ["\195\162"] = "a",
  ["\195\164"] = "a",
  ["\195\168"] = "e",
  ["\195\169"] = "e",
  ["\195\170"] = "e",
  ["\195\171"] = "e",
  ["\195\172"] = "i",
  ["\195\173"] = "i",
  ["\195\174"] = "i",
  ["\195\175"] = "i",
  ["\195\178"] = "o",
  ["\195\179"] = "o",
  ["\195\180"] = "o",
  ["\195\182"] = "o",
  ["\195\185"] = "u",
  ["\195\186"] = "u",
  ["\195\187"] = "u",
  ["\195\188"] = "u",
  ["\195\177"] = "n",
  ["\195\167"] = "c",
  ["\195\159"] = "ss",
}

-- Lower case, accents folded, every run of other characters one space. The accents first: a
-- client's lower() may read the bytes as Latin-1 and change a UTF-8 lead byte (the mock does).
function Shelf.Fold(text)
  text = gsub(text or "", "\195([\128-\191])", function(c)
    local b = byte(c)
    if b < 159 and b ~= 151 then
      b = b + 32 -- a capital to its small letter (the multiplication sign stays)
    end
    local ch = "\195" .. char(b)
    return FOLD[ch] or ch
  end)
  text = gsub(lower(text), "[^%w]+", " ")
  return text
end

-- The words of a query, folded; empty words left out.
function Shelf.Words(query)
  local out = {}
  for w in string.gmatch(Shelf.Fold(query), "%S+") do
    out[#out + 1] = w
  end
  return out
end

-- The folded text of an entry a search looks in (cached on the entry): title, hook, tale,
-- start, kind, the zones' names, the gifts' names.
function Shelf.TextOf(e, ctx)
  if e.text then
    return e.text
  end
  local list = {}
  local function add(s)
    if type(s) == "string" and s ~= "" then
      list[#list + 1] = s
    end
  end
  add(e.title)
  add(e.hook)
  add(e.tale)
  add(e.start)
  add(e.kind)
  add(e.chapter)
  add(e.body) -- a gold page's whole text (its blocks, its rumours)
  for _, z in ipairs(e.zones or {}) do
    local info = ctx and ctx.zoneOf and ctx.zoneOf(z)
    add(info and info.name)
  end
  if ctx and ctx.itemName then
    for _, item in ipairs(e.gives or {}) do
      add(ctx.itemName(item))
    end
  end
  e.text = " " .. Shelf.Fold(table.concat(list, " ")) .. " "
  return e.text
end

-- Every word of `words` is in the entry's text (a word matches the start of a word there).
function Shelf.Matches(e, words, ctx)
  if #words == 0 then
    return true
  end
  local text = Shelf.TextOf(e, ctx)
  for i = 1, #words do
    if not find(text, " " .. words[i], 1, true) then
      return false
    end
  end
  return true
end

-- ---------------------------------------------------------------------------------------------
-- The filter: f = { chapter, continent, zone, lo, hi, facets = { [key] = { [value] = true } },
-- query, sort, showDone, unconfirmed }; ctx = { isDone(id), zoneOf(uiMapID) -> { name, continent }, level,
-- here = { map, continent, wx, wy }, worldOf(map, x, y) -> continent, wx, wy, today, itemName }
-- ---------------------------------------------------------------------------------------------

function Shelf.NewFilter(chapter)
  return { chapter = chapter or "all", facets = {}, query = "", sort = "newest", showDone = false }
end

local function continentOf(z, ctx)
  local info = ctx and ctx.zoneOf and ctx.zoneOf(z)
  return info and info.continent
end

local function passWhere(e, f, ctx)
  if not f.continent and not f.zone then
    return true
  end
  local zones = e.zones
  if not zones then
    return false
  end
  for i = 1, #zones do
    local z = zones[i]
    if (not f.zone or z == f.zone) and (not f.continent or continentOf(z, ctx) == f.continent) then
      return true
    end
  end
  return false
end

-- The band overlaps lo..hi; a wonder without a band always passes (unknown is not zero).
function Shelf.InBand(e, lo, hi)
  if not e.levelMin and not e.levelMax then
    return true
  end
  local a, b = e.levelMin or 1, e.levelMax or Shelf.LEVEL_CAP
  return a <= (hi or Shelf.LEVEL_CAP) and b >= (lo or 1)
end

-- The band holds `level`: the tile's level chip turns gold.
function Shelf.Fits(e, level)
  if not level or (not e.levelMin and not e.levelMax) then
    return false
  end
  return (e.levelMin or 1) <= level and level <= (e.levelMax or Shelf.LEVEL_CAP)
end

local function passFacets(e, f, skip)
  for key, chosen in pairs(f.facets or {}) do
    if key ~= skip and next(chosen) then
      local v = Shelf.FacetOf(e, key)
      if v == nil or not chosen[v] then
        return false
      end
    end
  end
  return true
end

-- Does the entry pass the filter, leaving out dimension `skip` ("where", "zone", "level",
-- "done", "chapter", "state" or a facet's key)? `words`: the query's words.
function Shelf.Passes(e, f, ctx, words, skip)
  if skip ~= "chapter" and f.chapter and f.chapter ~= "all" and e.chapter ~= f.chapter then
    return false
  end
  if skip ~= "state" and not f.unconfirmed and e.state == "unknown" then
    return false
  end
  if skip ~= "done" and not f.showDone and ctx and ctx.isDone and ctx.isDone(e.id) then
    return false
  end
  if skip ~= "where" then
    if skip == "zone" then
      if f.continent and not passWhere(e, { continent = f.continent }, ctx) then
        return false
      end
    elseif not passWhere(e, f, ctx) then
      return false
    end
  end
  if skip ~= "level" and (f.lo or f.hi) and not Shelf.InBand(e, f.lo, f.hi) then
    return false
  end
  if not passFacets(e, f, skip) then
    return false
  end
  words = words or Shelf.Words(f.query)
  if e.back and #words == 0 then
    return false -- a page of the back shelf stands on no shelf; a search finds it
  end
  return Shelf.Matches(e, words, ctx)
end

-- ---------------------------------------------------------------------------------------------
-- Sorting and the day's order
-- ---------------------------------------------------------------------------------------------

-- A number from a string (djb2), the same on every client and every run.
function Shelf.Hash(s)
  local h = 5381
  for i = 1, #s do
    h = (h * 33 + byte(s, i)) % 2147483647
  end
  return h
end

local function dayKey(e, today)
  e.dayKey = e.dayKey or {}
  local k = e.dayKey[today or ""]
  if not k then
    k = Shelf.Hash((today or "") .. ":" .. e.id)
    e.dayKey = { [today or ""] = k }
  end
  return k
end

local function distance(e, ctx)
  local here = ctx and ctx.here
  if not (here and e.zones) then
    return 3, 0
  end
  for i = 1, #e.zones do
    if e.zones[i] == here.map then
      return 0, 0
    end
  end
  local p = e.place
  if p and here.wx and ctx.worldOf then
    local c, wx, wy = ctx.worldOf(p[1], p[2], p[3])
    if c and c == here.continent and wx then
      local dx, dy = wx - here.wx, wy - here.wy
      return 1, dx * dx + dy * dy
    end
  end
  for i = 1, #e.zones do
    if here.continent and continentOf(e.zones[i], ctx) == here.continent then
      return 2, 0
    end
  end
  return 3, 0
end

-- The views of a shelf (book.md "The views", E4): tiles or a list. Collections opens as a list,
-- the others as tiles; `saved` is the character's own choice by chapter.
Shelf.VIEWS = { tiles = true, list = true }

function Shelf.DefaultView(chapter)
  return chapter == "collections" and "list" or "tiles"
end

function Shelf.ViewOf(saved, chapter)
  local v = saved and saved[chapter or "all"]
  return Shelf.VIEWS[v] and v or Shelf.DefaultView(chapter)
end

-- Sorts a list of entries in place by `how` ("newest", "level", "nearest", "az", "dated", and
-- the list's columns: "how" by the way to get it, "have" the reader's own first, newest first;
-- `ctx.doneAt(id)` the time of this character's mark).
function Shelf.Sort(list, how, ctx)
  local today = ctx and ctx.today
  if how == "how" then
    -- by the first source's way, then the name; a wonder without a source last
    table.sort(list, function(a, b)
      local ha, hb = a.from and a.from[1] and a.from[1][1], b.from and b.from[1] and b.from[1][1]
      if ha ~= hb then
        if ha and hb then
          return ha < hb
        end
        return ha ~= nil
      end
      if a.title ~= b.title then
        return lower(a.title) < lower(b.title)
      end
      return a.id < b.id
    end)
    return list
  elseif how == "have" then
    local at = {}
    for _, e in ipairs(list) do
      at[e] = ctx and ctx.doneAt and ctx.doneAt(e.id) or nil
    end
    table.sort(list, function(a, b)
      local ta, tb = at[a], at[b]
      if ta ~= tb then
        if ta and tb then
          return ta > tb
        end
        return ta ~= nil
      end
      if a.title ~= b.title then
        return lower(a.title) < lower(b.title)
      end
      return a.id < b.id
    end)
    return list
  end
  if how == "dated" then
    -- the Gold shelf (R4.8): by the page's date, newest first; the undated last, in the book's
    -- own order (`order`, the page's place in the contents), never the day's shuffle
    table.sort(list, function(a, b)
      local da, db = a.added, b.added
      if da and db and da ~= db then
        return da > db
      elseif da and not db then
        return true
      elseif db and not da then
        return false
      end
      local oa, ob = a.order or 1e9, b.order or 1e9
      if oa ~= ob then
        return oa < ob
      end
      return a.id < b.id
    end)
  elseif how == "level" then
    table.sort(list, function(a, b)
      local la, lb = a.levelMin or 999, b.levelMin or 999
      if la ~= lb then
        return la < lb
      end
      return a.title < b.title
    end)
  elseif how == "az" then
    table.sort(list, function(a, b)
      if a.title ~= b.title then
        return lower(a.title) < lower(b.title)
      end
      return a.id < b.id
    end)
  elseif how == "nearest" then
    local rank, dist = {}, {}
    for _, e in ipairs(list) do
      rank[e], dist[e] = distance(e, ctx)
    end
    table.sort(list, function(a, b)
      if rank[a] ~= rank[b] then
        return rank[a] < rank[b]
      end
      if dist[a] ~= dist[b] then
        return dist[a] < dist[b]
      end
      return dayKey(a, today) < dayKey(b, today)
    end)
  else -- newest: dated first, newest first; then the day's order
    table.sort(list, function(a, b)
      local da, db = a.added, b.added
      if da and db and da ~= db then
        return da > db
      elseif da and not db then
        return true
      elseif db and not da then
        return false
      end
      local ka, kb = dayKey(a, today), dayKey(b, today)
      if ka ~= kb then
        return ka < kb
      end
      return a.id < b.id
    end)
  end
  return list
end

-- ---------------------------------------------------------------------------------------------
-- The shelf: the filtered list, the chips' counts
-- ---------------------------------------------------------------------------------------------

-- -> the entries the filter leaves, sorted; and how many it hid because they are done.
function Shelf.Filter(entries, f, ctx)
  local words = Shelf.Words(f.query)
  local out, hidden = {}, 0
  for i = 1, #entries do
    local e = entries[i]
    if Shelf.Passes(e, f, ctx, words) then
      out[#out + 1] = e
    elseif
      not f.showDone
      and ctx
      and ctx.isDone
      and ctx.isDone(e.id)
      and Shelf.Passes(e, f, ctx, words, "done")
    then
      hidden = hidden + 1
    end
  end
  Shelf.Sort(out, Shelf.FIXED_SORT[f.chapter or "all"] or f.sort, ctx)
  return out, hidden
end

-- How many wonders the chip "unconfirmed" would add: what the rest of the filter leaves of the
-- ones nobody reported yet.
function Shelf.UnconfirmedCount(entries, f, ctx)
  local words = Shelf.Words(f.query)
  local n = 0
  for i = 1, #entries do
    local e = entries[i]
    if e.state == "unknown" and Shelf.Passes(e, f, ctx, words, "state") then
      n = n + 1
    end
  end
  return n
end

-- The chips of a dimension with their counts: what the rest of the filter leaves, by value.
-- dim: "chapter", "continent", "zone" or a facet's key. -> { { value, n }, ... }, most first.
function Shelf.Counts(entries, f, ctx, dim)
  local words = Shelf.Words(f.query)
  local skip = (dim == "continent") and "where" or dim
  local n = {}
  for i = 1, #entries do
    local e = entries[i]
    if Shelf.Passes(e, f, ctx, words, skip) then
      if dim == "zone" or dim == "continent" then
        local seen = {}
        for _, z in ipairs(e.zones or {}) do
          local v = dim == "zone" and z or continentOf(z, ctx)
          if dim == "zone" and f.continent and continentOf(z, ctx) ~= f.continent then
            v = nil -- a wonder on two continents: only its zones on the chosen one
          end
          if v ~= nil and not seen[v] then
            seen[v] = true
            n[v] = (n[v] or 0) + 1
          end
        end
      else
        local v = Shelf.FacetOf(e, dim)
        if v ~= nil then
          n[v] = (n[v] or 0) + 1
        end
      end
    end
  end
  local out = {}
  for v, c in pairs(n) do
    out[#out + 1] = { value = v, n = c }
  end
  table.sort(out, function(a, b)
    if a.n ~= b.n then
      return a.n > b.n
    end
    return tostring(a.value) < tostring(b.value)
  end)
  return out
end

-- "my level": yours, three below to three above, within 1 and the cap.
function Shelf.MyLevel(level)
  if not level then
    return nil, nil
  end
  local lo = level - Shelf.MY_LEVEL
  local hi = level + Shelf.MY_LEVEL
  return lo < 1 and 1 or lo, hi > Shelf.LEVEL_CAP and Shelf.LEVEL_CAP or hi
end

-- A date "YYYY-MM-DD" as a day number (days since 2000-01-01), for the ribbon.
function Shelf.DayNumber(date)
  local y, m, d = string.match(date or "", "^(%d+)%-(%d+)%-(%d+)")
  if not y then
    return nil
  end
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  if m <= 2 then
    y, m = y - 1, m + 12
  end
  return 365 * y
    + floor(y / 4)
    - floor(y / 100)
    + floor(y / 400)
    + floor((153 * (m - 3) + 2) / 5)
    + d
    - 730426
end

function Shelf.IsNew(e, today)
  local a, t = Shelf.DayNumber(e.added), Shelf.DayNumber(today)
  return a ~= nil and t ~= nil and t - a >= 0 and t - a < Shelf.NEW_DAYS
end

-- ---------------------------------------------------------------------------------------------
-- The front table (book.md "The front table", E3; R4.7 of plan-book-round4.md): the newest gold
-- story as the main tile, six more chosen for the character, the chapters' counts for their
-- entrances. Pure: the same answer for the same day, zone and level, so a /reload changes
-- nothing and a new zone or level does.
-- ---------------------------------------------------------------------------------------------

Shelf.FRONT_SIX = 6 -- the tiles beside and under the main one
Shelf.FRONT_PER_CHAPTER = 2 -- at most this many of one chapter
Shelf.NEAR_YARDS = 4000 -- a place this far from your zone's middle counts as nothing nearer
-- the points: place (your zone, then by distance on your continent, then your continent), level
-- (yours in the band, then within 3, then within 6), a point for new
Shelf.POINTS = { zone = 6, near = 4, continent = 2, band = 3, within3 = 2, within6 = 1, new = 1 }
-- what stands as a collection on the wide tile: the kinds a character collects
Shelf.COLLECTION_KINDS = { mount = true, pet = true, title = true, ["library book"] = true }

-- Where the character is, as the table sees it: the zone's middle, not the spot the character
-- stands on, so the table holds still while walking through a zone.
local function anchor(ctx)
  local here = ctx and ctx.here
  if not (here and here.map and ctx.worldOf) then
    return nil
  end
  local c, wx, wy = ctx.worldOf(here.map, 0.5, 0.5)
  if c and wx then
    return { continent = c, wx = wx, wy = wy }
  end
  return nil
end

-- 0 in your zone, 1 on your continent with the yards from your zone's middle, 2 on your
-- continent, 3 elsewhere or without a place.
local function placeOf(e, ctx, from)
  local here = ctx and ctx.here
  if not (here and e.zones) then
    return 3
  end
  for i = 1, #e.zones do
    if e.zones[i] == here.map then
      return 0
    end
  end
  local p = e.place
  if from and p and ctx.worldOf then
    local c, wx, wy = ctx.worldOf(p[1], p[2], p[3])
    if c and c == from.continent and wx then
      local dx, dy = wx - from.wx, wy - from.wy
      return 1, sqrt(dx * dx + dy * dy)
    end
  end
  for i = 1, #e.zones do
    if here.continent and continentOf(e.zones[i], ctx) == here.continent then
      return 2
    end
  end
  return 3
end

-- A wonder's points for this character -> the score, and whether it is in the character's zone.
function Shelf.Score(e, ctx, from)
  local P = Shelf.POINTS
  local score = 0
  local rank, yards = placeOf(e, ctx, from)
  if rank == 0 then
    score = score + P.zone
  elseif rank == 1 then
    score = score + P.continent + P.near * max(0, 1 - yards / Shelf.NEAR_YARDS)
  elseif rank == 2 then
    score = score + P.continent
  end
  local level = ctx and ctx.level
  if level and (e.levelMin or e.levelMax) then
    local lo, hi = e.levelMin or 1, e.levelMax or Shelf.LEVEL_CAP
    local gap = (level < lo and lo - level) or (level > hi and level - hi) or 0
    if gap == 0 then
      score = score + P.band
    elseif gap <= 3 then
      score = score + P.within3
    elseif gap <= 6 then
      score = score + P.within6
    end
  end
  if Shelf.IsNew(e, ctx and ctx.today) then
    score = score + P.new
  end
  return score, rank == 0
end

-- -> { main = the newest gold story (nil without one), six = { up to six entries, the best
-- first }, collection = { kind, have, total, entry } or nil (what the wide tile stands for: the
-- collection of the best Collections wonder among the six), chapters = { [chapter] = { open,
-- near } } }. On the table: open (not done), obtainable (E2: never what nobody reported in
-- Forever yet), on no back shelf, of the character's side. At most FRONT_PER_CHAPTER of a
-- chapter while other chapters have something; ties by the day's order.
function Shelf.Front(entries, ctx)
  local today = ctx and ctx.today
  local side = ctx and ctx.side
  local from = anchor(ctx)
  local front = { six = {}, chapters = {} }
  for _, chapter in ipairs(Shelf.CHAPTERS) do
    front.chapters[chapter] = { open = 0, near = 0 }
  end
  local gold, open, score = {}, {}, {}
  for i = 1, #entries do
    local e = entries[i]
    if e.chapter == "gold" and not e.back then
      gold[#gold + 1] = e
    end
    local done = ctx and ctx.isDone and ctx.isDone(e.id)
    if e.state ~= "unknown" and not e.back and not done and not (side and e.side and e.side ~= side) then
      local s, here = Shelf.Score(e, ctx, from)
      score[e] = s
      open[#open + 1] = e
      local c = front.chapters[e.chapter]
      if c then
        c.open = c.open + 1
        if here then
          c.near = c.near + 1
        end
      end
    end
  end
  -- the main tile: the newest gold story, whatever its level, done or not
  Shelf.Sort(gold, "dated", ctx)
  front.main = gold[1]
  table.sort(open, function(a, b)
    if score[a] ~= score[b] then
      return score[a] > score[b]
    end
    local ka, kb = dayKey(a, today), dayKey(b, today)
    if ka ~= kb then
      return ka < kb
    end
    return a.id < b.id
  end)
  -- the best first, at most two of a chapter; what is left fills the table when fewer than
  -- three chapters have something
  local per, taken = {}, {}
  for pass = 1, 2 do
    for i = 1, #open do
      local e = open[i]
      if #front.six >= Shelf.FRONT_SIX then
        break
      end
      if e ~= front.main and not taken[e] then
        local n = per[e.chapter] or 0
        if pass == 2 or n < Shelf.FRONT_PER_CHAPTER then
          per[e.chapter] = n + 1
          taken[e] = true
          front.six[#front.six + 1] = e
        end
      end
    end
  end
  front.score = score
  -- the wide tile's collection: of the best collectable among the six
  for i = 1, #front.six do
    local e = front.six[i]
    if e.chapter == "collections" and Shelf.COLLECTION_KINDS[e.kind] then
      local have, total = 0, 0
      for j = 1, #entries do
        local o = entries[j]
        if o.chapter == "collections" and o.kind == e.kind then
          local counts, done = Shelf.Counted(o, ctx)
          if counts then
            total = total + 1
            if done then
              have = have + 1
            end
          end
        end
      end
      front.collection = { kind = e.kind, have = have, total = total, entry = e }
      break
    end
  end
  return front
end

-- ---------------------------------------------------------------------------------------------
-- Progress and the album (book.md "Your record becomes the diary", R4.11)
-- ---------------------------------------------------------------------------------------------

-- Whether a wonder counts in a total -> counts, done. It counts when it can be had (E2: "in";
-- never what nobody reported in Forever yet) or when the reader has it, which is the proof. A
-- gold page is read, not owned; the other side's wonders do not count unless the reader has one.
function Shelf.Counted(e, ctx)
  if e.page or e.back then
    return false, false
  end
  local done = (ctx and ctx.isDone and ctx.isDone(e.id)) and true or false
  if done then
    return true, true
  end
  if e.state == "unknown" then
    return false, false
  end
  local side = ctx and ctx.side
  if side and e.side and e.side ~= side then
    return false, false
  end
  return true, false
end

-- The diary's collections, in its order: what a character collects by kind (the cabinet's wide
-- tile counts the same), then the chapters that are no collection of one kind.
Shelf.PROGRESS = {
  { id = "mount", chapter = "collections", kind = "mount" },
  { id = "pet", chapter = "collections", kind = "pet" },
  { id = "title", chapter = "collections", kind = "title" },
  { id = "library book", chapter = "collections", kind = "library book" },
  { id = "secrets", chapter = "secrets" },
  { id = "camp", chapter = "camp" },
  { id = "rares", chapter = "rares" },
}
Shelf.PROGRESS_ZONES = 6 -- the zones' rows: where the reader is, then where the most is done

-- -> { rows = { { id, chapter, kind, have, total } }, zones = { { zone, name, have, total } } }.
-- A row without anything to have is left out. The zones: the one the reader stands in (when it
-- holds a wonder), then the zones with something done, the most first, then by name.
function Shelf.Progress(entries, ctx)
  local rows, byId = {}, {}
  for _, p in ipairs(Shelf.PROGRESS) do
    local row = { id = p.id, chapter = p.chapter, kind = p.kind, have = 0, total = 0 }
    rows[#rows + 1] = row
    byId[p.id] = row
  end
  local zoneRows, zoneOf = {}, {}
  for i = 1, #entries do
    local e = entries[i]
    local counts, done = Shelf.Counted(e, ctx)
    if counts then
      local row = byId[e.chapter == "collections" and e.kind or e.chapter]
      if row then
        row.total = row.total + 1
        row.have = row.have + (done and 1 or 0)
      end
      for _, z in ipairs(e.zones or {}) do
        local zr = zoneOf[z]
        if not zr then
          local info = ctx and ctx.zoneOf and ctx.zoneOf(z)
          zr = { zone = z, name = info and info.name or nil, have = 0, total = 0 }
          zoneOf[z] = zr
          zoneRows[#zoneRows + 1] = zr
        end
        zr.total = zr.total + 1
        zr.have = zr.have + (done and 1 or 0)
      end
    end
  end
  local out = { rows = {}, zones = {} }
  for _, row in ipairs(rows) do
    if row.total > 0 then
      out.rows[#out.rows + 1] = row
    end
  end
  local here = ctx and ctx.here and ctx.here.map
  table.sort(zoneRows, function(a, b)
    if (a.zone == here) ~= (b.zone == here) then
      return a.zone == here
    end
    if a.have ~= b.have then
      return a.have > b.have
    end
    local na, nb = a.name or "", b.name or ""
    if na ~= nb then
      return na < nb
    end
    return a.zone < b.zone
  end)
  for _, zr in ipairs(zoneRows) do
    -- a zone without a name cannot be written (a pack without the World pack's zones)
    if #out.zones < Shelf.PROGRESS_ZONES and zr.name and (zr.zone == here or zr.have > 0) then
      out.zones[#out.zones + 1] = zr
    end
  end
  return out
end

-- A collection as an album: the wonders of `kind` that count and have a model (`npc`), the ones
-- the reader has first, then by name -> { { entry, have } }.
function Shelf.Album(entries, kind, ctx)
  local out = {}
  for i = 1, #entries do
    local e = entries[i]
    if e.chapter == "collections" and e.kind == kind and e.npc then
      local counts, done = Shelf.Counted(e, ctx)
      if counts then
        out[#out + 1] = { entry = e, have = done }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.have ~= b.have then
      return a.have
    end
    local ta, tb = lower(a.entry.title or ""), lower(b.entry.title or "")
    if ta ~= tb then
      return ta < tb
    end
    return a.entry.id < b.entry.id
  end)
  return out
end

-- A wonder this character has not done, by `seed` (any number): nil when all are done. Never
-- one nobody reported in Forever yet.
function Shelf.Surprise(entries, ctx, seed)
  local open = {}
  for i = 1, #entries do
    if entries[i].state ~= "unknown" and not (ctx and ctx.isDone and ctx.isDone(entries[i].id)) then
      open[#open + 1] = entries[i]
    end
  end
  if #open == 0 then
    return nil
  end
  return open[(floor(seed or 0) % #open) + 1]
end

-- ---------------------------------------------------------------------------------------------
-- The simulation (book.md "Simulation"): n wonders over every chapter, zone, band, facet and
-- date, the same for the same seed.
-- ---------------------------------------------------------------------------------------------

Shelf.SIM_ZONES = {
  [1429] = { name = "Elwynn Forest", continent = 0 },
  [1436] = { name = "Westfall", continent = 0 },
  [1431] = { name = "Duskwood", continent = 0 },
  [1437] = { name = "Wetlands", continent = 0 },
  [1432] = { name = "Loch Modan", continent = 0 },
  [1416] = { name = "Alterac Mountains", continent = 0 },
  [1434] = { name = "Stranglethorn Vale", continent = 0 },
  [1418] = { name = "Badlands", continent = 0 },
  [1420] = { name = "Tirisfal Glades", continent = 0 },
  [1426] = { name = "Dun Morogh", continent = 0 },
  [1413] = { name = "The Barrens", continent = 1 },
  [1411] = { name = "Durotar", continent = 1 },
  [1412] = { name = "Mulgore", continent = 1 },
  [1438] = { name = "Teldrassil", continent = 1 },
  [1439] = { name = "Darkshore", continent = 1 },
  [1442] = { name = "Stonetalon Mountains", continent = 1 },
  [1445] = { name = "Dustwallow Marsh", continent = 1 },
  [1441] = { name = "Thousand Needles", continent = 1 },
  [1446] = { name = "Tanaris", continent = 1 },
  [2521] = { name = "Zephras Isle", continent = 2991 },
}

local SIM_KINDS = {
  gold = { "farming", "fishing", "crafting", "flips", "auction", "trades" },
  secrets = { "chain", "pet", "unsolved" },
  collections = { "mount", "pet", "title", "library book" },
  camp = { "camp kit", "camp item", "camping" },
  rares = { "rare", "rare elite" },
}
local SIM_PROFESSIONS = { "Cooking", "Alchemy", "Engineering", "Tailoring", "Mining" }
local SIM_SKILLS = { 1, 20, 90, 140, 300 } -- the skill a camp item needs
local SIM_WORDS = {
  "Silver",
  "Wolf",
  "Bag",
  "Lantern",
  "Map",
  "Raptor",
  "Pearl",
  "Frog",
  "Tome",
  "Key",
  "Ghost",
  "Banner",
  "Saber",
  "Kodo",
  "Murloc",
  "Harpy",
  "Ram",
  "Owl",
  "Crab",
  "Candle",
}
local SIM_TYPES = { "Beast", "Humanoid", "Undead", "Elemental", "Dragonkin" }
local SIM_SOURCES = { "vendor", "drop", "quest", "crafted", "boss", "object" }

function Shelf.Simulate(n, seed)
  local state = (seed or 1) % 2147483647
  if state <= 0 then
    state = 1
  end
  local function rnd(k) -- 1..k
    state = (state * 16807) % 2147483647
    return state % k + 1
  end
  local zones = {}
  for z in pairs(Shelf.SIM_ZONES) do
    zones[#zones + 1] = z
  end
  table.sort(zones)
  local out = {}
  for i = 1, n or 0 do
    local chapter = Shelf.CHAPTERS[rnd(#Shelf.CHAPTERS)]
    local kinds = SIM_KINDS[chapter]
    local kind = kinds[rnd(#kinds)]
    local w1, w2 = SIM_WORDS[rnd(#SIM_WORDS)], SIM_WORDS[rnd(#SIM_WORDS)]
    local e = {
      id = "sim:" .. i,
      chapter = chapter,
      kind = kind,
      title = w1 .. " of the " .. w2 .. " " .. i,
      hook = "A simulated wonder: the " .. lower(w2) .. " and the " .. lower(w1) .. ".",
      facets = {},
      sim = true,
    }
    if rnd(10) > 1 then -- one in ten has no place
      local z = zones[rnd(#zones)]
      e.zones = { z }
      e.place = { z, rnd(90) / 100, rnd(90) / 100 }
      if rnd(6) == 1 then
        local z2 = zones[rnd(#zones)]
        if z2 ~= z then
          e.zones[2] = z2
        end
      end
    end
    if rnd(8) > 1 then -- one in eight has no band
      local lo = rnd(55)
      e.levelMin = lo
      e.levelMax = lo + rnd(6) - 1
    end
    local side = rnd(4)
    e.side = side == 1 and "A" or side == 2 and "H" or nil
    if chapter == "collections" then
      e.facets.source = SIM_SOURCES[rnd(#SIM_SOURCES)]
    elseif chapter == "rares" then
      e.facets.type = SIM_TYPES[rnd(#SIM_TYPES)]
    elseif chapter == "camp" and kind ~= "camping" then
      e.facets.profession = SIM_PROFESSIONS[rnd(#SIM_PROFESSIONS)]
      e.facets.skill = SIM_SKILLS[rnd(#SIM_SKILLS)]
    end
    if chapter == "collections" or chapter == "rares" then
      e.state = rnd(3) ~= 1 and "in" or "unknown" -- one in three nobody reported yet
    elseif chapter ~= "gold" then
      e.state = "in"
    end
    if rnd(5) == 1 then
      e.added = string.format("2026-%02d-%02d", 9 + rnd(3), rnd(28))
    end
    out[i] = e
  end
  return out
end

-- The zone of a simulated wonder (the simulation's zones are named without the data pack).
function Shelf.SimZone(uiMapID)
  return Shelf.SIM_ZONES[uiMapID]
end
