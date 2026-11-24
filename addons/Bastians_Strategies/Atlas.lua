-- The Atlas with filters (book.md, R4.12): what stands on the world and in a zone, and where. Pure.
local _, ns = ...
local Book, Shelf = ns.Book, ns.Shelf

local Atlas = {}
ns.Atlas = Atlas

-- The numbers of book-look.md 10.10, in UI units.
Atlas.CHAPTERS = { "gold", "secrets", "collections", "camp", "rares" }
Atlas.SIZE = {
  story = 46, -- a gold page's drawing
  board = 33, -- a gold page on a board in the ocean
  seal = 26,
  broken = 26,
  opened = 33,
  camp = 26,
  rare = 33,
  rareWorld = 26,
  frame = 24,
  disc = 30,
  discBig = 36,
}
Atlas.RING = { story = 3 } -- a token's ring; every other form: RING_DEFAULT
Atlas.RING_DEFAULT = 2
Atlas.DISC_BIG = 20 -- a zone's disc is the large one from this many wonders
Atlas.GAP = 6 -- no two tokens closer than their radii and this
Atlas.PLATE = 7 -- a gold page's level plate: its circle lies this much lower and is as much wider
Atlas.DOT_FROM = 8 -- a pushed token further than this from its spot leaves a dot there
Atlas.ALONE_MAX = 4 -- wonders standing alone per zone; the rest join the zone's disc
Atlas.BOARD_W, Atlas.BOARD_PAD = 0.17, 10 -- a board's share of the picture's width, its way from the edge
Atlas.EDGE = 6 -- a token keeps this far from the picture's edge
Atlas.ROUND_MAX = 12 -- a round's stops: the tour's limit (route.md "Several stops")
Atlas.ZONE_ASPECT = 1.5 -- a zone's painting is 3 wide to 2 high
Atlas.SPREAD_ROUNDS = 200
-- The map layers of other addons the Atlas draws (core-contracts 6): Notes' spots and the places
-- others sent, Route's line. A layer nobody registered is never asked.
Atlas.LAYERS = { "notes.spots", "notes.shared", "route.path" }
Atlas.NOTE_LAYERS = { ["notes.spots"] = true, ["notes.shared"] = true }

-- ---------------------------------------------------------------------------------------------
-- The filter: f = { chapters = { [id] = true }, kinds = { [kind] = true }, mine, unconfirmed,
-- showDone, layers = { [id] = false } (a layer switched off) }
-- ---------------------------------------------------------------------------------------------

function Atlas.NewFilter()
  return { chapters = {}, kinds = {}, mine = false, unconfirmed = false, showDone = false, layers = {} }
end

local function chosen(set)
  local out, n = {}, 0
  for k, on in pairs(set or {}) do
    if on then
      out[k] = true
      n = n + 1
    end
  end
  return out, n
end

-- The one chapter chosen, whose kinds the band then offers; nil with none or several.
function Atlas.OneChapter(f)
  local set, n = chosen(f.chapters)
  if n ~= 1 then
    return nil
  end
  return (next(set))
end

-- The Atlas's filter as a shelf's (Shelf.Passes decides), leaving out `skip` ("chapter", "kind").
function Atlas.ShelfFilter(f, ctx, skip)
  local s = Shelf.NewFilter("all")
  s.showDone, s.unconfirmed = f.showDone and true or false, f.unconfirmed and true or false
  if f.mine then
    s.lo, s.hi = Shelf.MyLevel(ctx and ctx.level)
  end
  local chapters, n = chosen(f.chapters)
  if skip ~= "chapter" and n > 0 then
    s.facets.chapter = chapters
  end
  local kinds, k = chosen(f.kinds)
  if skip ~= "kind" and n == 1 and k > 0 then
    s.facets.kind = kinds
  end
  return s
end

-- ---------------------------------------------------------------------------------------------
-- Places
-- ---------------------------------------------------------------------------------------------

-- An entry's place on the world picture -> fx, fy (fractions), exact (false: its zone's middle);
-- nil without a place on it (unknown is not zero: such a wonder gets no spot).
function Atlas.Spot(e, toWorld)
  local p = e.place
  if p and p[1] then
    local c, wx, wy = toWorld(p[1], p[2], p[3])
    if c then
      local fx, fy = Book.WorldSpot(c, wx, wy)
      if fx then
        return fx, fy, true
      end
    end
  end
  local z = e.zones and tonumber(e.zones[1])
  if z then
    local c, wx, wy = toWorld(z, 0.5, 0.5)
    if c then
      local fx, fy = Book.WorldSpot(c, wx, wy)
      if fx then
        return fx, fy, false
      end
    end
  end
  return nil
end

-- The zone an entry is counted in: its first zone, else its place's map.
function Atlas.ZoneOf(e)
  return (e.zones and tonumber(e.zones[1])) or (e.place and e.place[1]) or nil
end

-- An entry's spot on its zone's painting -> x, y (map fractions); nil when it names no spot
-- there. A place given on a sub map goes through world yards (ctx.worldOf, ctx.mapOf).
function Atlas.InZone(e, zone, ctx)
  local p = e.place
  if not (p and p[1]) then
    return nil
  end
  if p[1] == zone then
    return p[2], p[3]
  end
  if not (ctx and ctx.worldOf and ctx.mapOf) then
    return nil
  end
  local c, wx, wy = ctx.worldOf(p[1], p[2], p[3])
  if not c then
    return nil
  end
  local x, y = ctx.mapOf(c, wx, wy, zone)
  if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
    return x, y
  end
  return nil
end

-- ---------------------------------------------------------------------------------------------
-- Forms: one per chapter
-- ---------------------------------------------------------------------------------------------

-- Stands as itself on the world: a gold page, a secret, a camp (the chains of kind "camping").
function Atlas.Alone(e)
  return e.chapter == "gold" or e.chapter == "secrets" or (e.chapter == "camp" and e.kind == "camping")
end

-- Whether a secret still wears its seal: the shelves' rule (Cabinet.KindOf), a chain not opened.
function Atlas.Sealed(e, ctx)
  return e.chapter == "secrets" and e.kind == "chain" and not (ctx and ctx.isOpened and ctx.isOpened(e.id))
end

-- -> { form = "story" | "seal" | "broken" | "opened" | "camp" | "rare" | "frame", size, ring,
-- elite, exact, unconfirmed, done }
function Atlas.Form(e, ctx, inZone)
  local form, size
  if e.chapter == "gold" then
    form, size = "story", Atlas.SIZE.story
  elseif e.chapter == "secrets" then
    if e.kind == "unsolved" then
      form, size = "broken", Atlas.SIZE.broken
    elseif Atlas.Sealed(e, ctx) then
      form, size = "seal", Atlas.SIZE.seal
    else
      form, size = "opened", Atlas.SIZE.opened
    end
  elseif e.chapter == "camp" then
    form, size = "camp", Atlas.SIZE.camp
  elseif e.chapter == "rares" then
    form, size = "rare", inZone and Atlas.SIZE.rare or Atlas.SIZE.rareWorld
  else
    form, size = "frame", Atlas.SIZE.frame
  end
  return {
    form = form,
    size = size,
    ring = Atlas.RING[form] or Atlas.RING_DEFAULT,
    elite = e.kind == "rare elite" or nil,
    exact = e.place ~= nil,
    unconfirmed = Shelf.Unconfirmed(e) or nil,
    done = (ctx and ctx.isDone and ctx.isDone(e.id)) and true or nil,
  }
end

-- The thing a wonder is, for the suite's menu and links: its page, its creature, its item, else
-- its zone. nil when it names none.
function Atlas.RefOf(e)
  if e.page then
    return "page:" .. tostring(e.id)
  end
  if e.npc then
    return "npc:" .. tostring(e.npc)
  end
  local item = e.gives and e.gives[1]
  if type(item) == "number" then
    return "item:" .. item
  end
  local z = Atlas.ZoneOf(e)
  return z and ("zone:" .. z) or nil
end

-- ---------------------------------------------------------------------------------------------
-- Apart: Book.Spread with each point's own radius
-- ---------------------------------------------------------------------------------------------

-- Pushes points { x, y, r } apart until no two are closer than their radii and the gap, inside
-- the box. In place; deterministic.
function Atlas.Spread(points, x1, y1, x2, y2)
  local n = #points
  for _ = 1, Atlas.SPREAD_ROUNDS do
    local moved = false
    for i = 1, n do
      for j = i + 1, n do
        local a, b = points[i], points[j]
        local dx, dy = b.x - a.x, b.y - a.y
        local d = math.sqrt(dx * dx + dy * dy)
        local gap = a.r + b.r + Atlas.GAP
        if d < gap then
          moved = true
          local push = (gap - d) / 2 + 0.25
          if d < 0.001 then
            local angle = (i * 7 + j * 3) * 0.7
            dx, dy, d = math.cos(angle), math.sin(angle), 1
          end
          a.x, a.y = a.x - dx / d * push, a.y - dy / d * push
          b.x, b.y = b.x + dx / d * push, b.y + dy / d * push
        end
      end
    end
    for _, p in ipairs(points) do
      p.x = math.max(x1 + p.r, math.min(x2 - p.r, p.x))
      p.y = math.max(y1 + p.r, math.min(y2 - p.r, p.y))
    end
    if not moved then
      break
    end
  end
  return points
end

local function byId(a, b)
  return tostring(a.id) < tostring(b.id)
end

-- The entries that pass, in the order of their ids (so the picture is the same every time).
local function passing(entries, f, ctx)
  local s = Atlas.ShelfFilter(f, ctx)
  local words = Shelf.Words(s.query)
  local out = {}
  for _, e in ipairs(entries or {}) do
    if Shelf.Passes(e, s, ctx, words) then
      out[#out + 1] = e
    end
  end
  table.sort(out, byId)
  return out
end

-- A token's point for the spread: its circle, a gold page's holding its level plate.
local function pointOf(e, form, x, y)
  local plate = form.form == "story" and Atlas.PLATE or 0
  return { x = x, y = y + plate, r = form.size / 2 + form.ring + plate, up = plate, entry = e, form = form }
end

local function settle(points, w, h)
  for _, p in ipairs(points) do
    p.y = p.y - (p.up or 0) -- the token's own middle
    local dx, dy = p.x - p.tx * w, p.y - p.ty * h
    p.moved = (math.abs(dx) + math.abs(dy)) > Atlas.DOT_FROM or nil
    p.r, p.up = nil, nil
  end
end

-- ---------------------------------------------------------------------------------------------
-- The world
-- ---------------------------------------------------------------------------------------------

-- What the world picture of pw x ph units shows. -> { tokens = { { entry, form, x, y, tx, ty,
-- moved } }, discs = { { zone, name, count, entries, big, here, x, y, tx, ty } }, boards = {
-- market = { entries }, trades = { entries } } (the gold pages without a place), off = {
-- [chapter] = n } (the wonders without one), offTotal, shown }. x, y: units from the picture's
-- top left; tx, ty: the true place as fractions.
function Atlas.World(entries, f, ctx, pw, ph)
  local out = {
    tokens = {},
    discs = {},
    boards = { market = {}, trades = {} },
    off = {},
    offTotal = 0,
    shown = 0,
  }
  local alone, groups, zones, seen = {}, {}, {}, {}
  for _, e in ipairs(passing(entries, f, ctx)) do
    local fx, fy = Atlas.Spot(e, ctx.worldOf)
    if not fx then
      out.offTotal = out.offTotal + 1
      if e.page then
        local board = out.boards[Book.BOARD[e.kind] or "trades"]
        board[#board + 1] = e
      else
        out.off[e.chapter] = (out.off[e.chapter] or 0) + 1
      end
    else
      out.shown = out.shown + 1
      local z = Atlas.ZoneOf(e) or 0
      if not seen[z] then
        seen[z] = true
        zones[#zones + 1] = z
      end
      local list = Atlas.Alone(e) and alone or groups
      list[z] = list[z] or {}
      list[z][#list[z] + 1] = { entry = e, fx = fx, fy = fy }
    end
  end
  table.sort(zones)
  local points = {}
  for _, z in ipairs(zones) do
    local own = alone[z] or {}
    if #own > Atlas.ALONE_MAX then -- the best stand alone, the rest join the zone's count
      for _, it in ipairs(own) do
        it.score = Shelf.Score(it.entry, ctx) or 0
      end
      table.sort(own, function(a, b)
        if a.score ~= b.score then
          return a.score > b.score
        end
        return byId(a.entry, b.entry)
      end)
      groups[z] = groups[z] or {}
      for i = #own, Atlas.ALONE_MAX + 1, -1 do
        table.insert(groups[z], table.remove(own, i))
      end
    end
    for _, it in ipairs(own) do
      local p = pointOf(it.entry, Atlas.Form(it.entry, ctx, false), it.fx * pw, it.fy * ph)
      p.tx, p.ty = it.fx, it.fy
      points[#points + 1] = p
      out.tokens[#out.tokens + 1] = p
    end
    local group = groups[z]
    if group and #group == 1 then -- one wonder is itself, not a disc of one
      local it = group[1]
      local p = pointOf(it.entry, Atlas.Form(it.entry, ctx, false), it.fx * pw, it.fy * ph)
      p.tx, p.ty = it.fx, it.fy
      points[#points + 1] = p
      out.tokens[#out.tokens + 1] = p
    elseif group then
      local sx, sy, list = 0, 0, {}
      for _, it in ipairs(group) do
        sx, sy = sx + it.fx, sy + it.fy
        list[#list + 1] = it.entry
      end
      table.sort(list, byId)
      local n = #group
      local big = n >= Atlas.DISC_BIG
      local info = ctx.zoneOf and ctx.zoneOf(z)
      local disc = {
        zone = z,
        name = info and info.name or nil,
        count = n,
        entries = list,
        big = big or nil,
        here = (ctx.here and ctx.here.map == z) or nil,
        x = sx / n * pw,
        y = sy / n * ph,
        tx = sx / n,
        ty = sy / n,
        r = (big and Atlas.SIZE.discBig or Atlas.SIZE.disc) / 2 + Atlas.RING_DEFAULT,
      }
      points[#points + 1] = disc
      out.discs[#out.discs + 1] = disc
    end
  end
  local side = pw * Atlas.BOARD_W + Atlas.BOARD_PAD
  Atlas.Spread(points, side, Atlas.EDGE, pw - side, ph - Atlas.EDGE)
  settle(points, pw, ph)
  return out
end

-- ---------------------------------------------------------------------------------------------
-- A zone
-- ---------------------------------------------------------------------------------------------

-- Whether a chain's trail may be drawn: a camp's, and a secret's once its page was opened.
function Atlas.HasTrail(e, ctx)
  if not (e.steps and #e.steps > 1) then
    return false
  end
  if e.chapter == "camp" then
    return true
  end
  return e.chapter == "secrets" and e.kind ~= "unsolved" and not Atlas.Sealed(e, ctx)
end

-- A chain's steps on the world picture -> { { n, fx, fy } }.
function Atlas.TrailWorld(e, ctx)
  local out = {}
  if not Atlas.HasTrail(e, ctx) then
    return out
  end
  for i, step in ipairs(e.steps) do
    local p = type(step) == "table" and step.place
    if p and p[1] then
      local c, wx, wy = ctx.worldOf(p[1], p[2], p[3])
      local fx, fy = Book.WorldSpot(c, wx, wy)
      if fx then
        out[#out + 1] = { n = i, fx = fx, fy = fy }
      end
    end
  end
  return out
end

-- What a zone's painting of zw x zh units shows. -> { tokens = { { entry, form, x, y, tx, ty,
-- moved } } (the wonders with a spot there), somewhere = { entries } (they name the zone and no
-- spot), counts = { [chapter] = n }, total, steps = { { entry, n, x, y } } (the trails' steps
-- that lie in the zone, of this zone's chains and of others') }.
function Atlas.Zone(entries, zone, f, ctx, zw, zh)
  local out = { tokens = {}, somewhere = {}, counts = {}, total = 0, steps = {} }
  for _, e in ipairs(passing(entries, f, ctx)) do
    if Atlas.HasTrail(e, ctx) then
      for i, step in ipairs(e.steps) do
        local p = type(step) == "table" and step.place
        if p and p[1] then
          local x, y = Atlas.InZone({ place = p }, zone, ctx)
          if x then
            out.steps[#out.steps + 1] = { entry = e, n = i, x = x * zw, y = y * zh }
          end
        end
      end
    end
    if Atlas.ZoneOf(e) == zone then
      out.total = out.total + 1
      out.counts[e.chapter] = (out.counts[e.chapter] or 0) + 1
      local x, y = Atlas.InZone(e, zone, ctx)
      if x then
        local p = pointOf(e, Atlas.Form(e, ctx, true), x * zw, y * zh)
        p.tx, p.ty = x, y
        out.tokens[#out.tokens + 1] = p
      else
        out.somewhere[#out.somewhere + 1] = e
      end
    end
  end
  Atlas.Spread(out.tokens, Atlas.EDGE, Atlas.EDGE, zw - Atlas.EDGE, zh - Atlas.EDGE)
  settle(out.tokens, zw, zh)
  return out
end

-- ---------------------------------------------------------------------------------------------
-- The band's counts
-- ---------------------------------------------------------------------------------------------

-- -> { chapters = { [id] = n } (placed wonders passing everything but the chapter chips), kinds =
-- { [kind] = n } (of the one chosen chapter, passing everything but the kind chips), unconfirmed
-- (placed ones nobody saw in Forever yet, whether shown or not), done (placed and done) }
function Atlas.Counts(entries, f, ctx)
  local out = { chapters = {}, kinds = {}, unconfirmed = 0, done = 0 }
  local one = Atlas.OneChapter(f)
  local noChapter, noKind = Atlas.ShelfFilter(f, ctx, "chapter"), Atlas.ShelfFilter(f, ctx, "kind")
  local all = Atlas.ShelfFilter(f, ctx)
  all.unconfirmed, all.showDone = true, true
  local words = {}
  for _, e in ipairs(entries or {}) do
    if Atlas.Spot(e, ctx.worldOf) then
      if Shelf.Passes(e, noChapter, ctx, words) then
        out.chapters[e.chapter] = (out.chapters[e.chapter] or 0) + 1
      end
      if one and e.chapter == one and Shelf.Passes(e, noKind, ctx, words) then
        out.kinds[e.kind] = (out.kinds[e.kind] or 0) + 1
      end
      if Shelf.Passes(e, all, ctx, words) then
        if Shelf.Unconfirmed(e) then
          out.unconfirmed = out.unconfirmed + 1
        end
        if ctx.isDone and ctx.isDone(e.id) then
          out.done = out.done + 1
        end
      end
    end
  end
  return out
end

-- ---------------------------------------------------------------------------------------------
-- A round through a zone (with the route service)
-- ---------------------------------------------------------------------------------------------

-- The stops of a round: the picked tokens ({ [id] = true }), else all shown; from `from` ({ x, y }
-- map fractions, the character; else the first token) always to the nearest next; at most
-- ROUND_MAX. -> the tokens in the round's order.
function Atlas.Round(tokens, picked, from)
  local pool = {}
  for _, t in ipairs(tokens or {}) do
    if picked and picked[t.entry.id] then
      pool[#pool + 1] = t
    end
  end
  if #pool == 0 then
    for _, t in ipairs(tokens or {}) do
      pool[#pool + 1] = t
    end
  end
  local out = {}
  if #pool == 0 then
    return out
  end
  local ax, ay = pool[1].tx, pool[1].ty
  if from then
    ax, ay = from.x, from.y
  end
  while #pool > 0 and #out < Atlas.ROUND_MAX do
    local best, bestD
    for i, t in ipairs(pool) do
      local dx, dy = (t.tx - ax) * Atlas.ZONE_ASPECT, t.ty - ay
      local d = dx * dx + dy * dy
      if not bestD or d < bestD then
        best, bestD = i, d
      end
    end
    local t = table.remove(pool, best)
    ax, ay = t.tx, t.ty
    out[#out + 1] = t
  end
  return out
end

-- The round as the route service's stops (route.md "Several stops"): { { id, name, ref, place =
-- { map, wx, wy } } }; a stop whose place has no world position is left out.
function Atlas.Stops(round, zone, ctx)
  local out = {}
  for _, t in ipairs(round or {}) do
    local c, wx, wy = ctx.worldOf(zone, t.tx, t.ty)
    if c then
      out[#out + 1] = {
        id = t.entry.id,
        name = t.entry.title,
        ref = Atlas.RefOf(t.entry),
        place = { map = c, wx = wx, wy = wy },
      }
    end
  end
  return out
end

-- ---------------------------------------------------------------------------------------------
-- The views a hosted map layer is asked with (core-contracts 6)
-- ---------------------------------------------------------------------------------------------

-- The world picture: one view per continent on it.
function Atlas.WorldViews()
  local out = {}
  for _, c in ipairs(Book.WorldContinents()) do
    local x1, y1, x2, y2 = Book.WorldBox(c)
    out[#out + 1] = { continent = c, x1 = x1, y1 = y1, x2 = x2, y2 = y2, level = 0 }
  end
  return out
end

-- A zone's painting; nil when the zone has no world position.
function Atlas.ZoneView(zone, ctx)
  local c, ax, ay = ctx.worldOf(zone, 0, 0)
  local c2, bx, by = ctx.worldOf(zone, 1, 1)
  if not (c and c2) then
    return nil
  end
  return {
    continent = c,
    x1 = math.min(ax, bx),
    y1 = math.min(ay, by),
    x2 = math.max(ax, bx),
    y2 = math.max(ay, by),
    level = 3,
  }
end

-- A pin's place on the picture -> fractions; nil outside it.
function Atlas.PinSpot(pin, view, zone, ctx)
  if not (pin and pin.wx and pin.wy) then
    return nil
  end
  if zone then
    local x, y = ctx.mapOf(view.continent, pin.wx, pin.wy, zone)
    if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
      return x, y
    end
    return nil
  end
  return Book.WorldSpot(view.continent, pin.wx, pin.wy)
end
