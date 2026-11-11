-- The five registries and the services (core-contracts §4-§7a, §11): entity types, actions, map layers,
-- detail sections, search providers. Every registration is owner-tracked and announced on the bus.
local _, ns = ...
local B = ns.B
local track = ns.track
-- Looked up at call time: Perf (loaded later) wraps ns.safecall, and the registries' callbacks
-- (layer queries, sections, actions, providers) were never timed before (23.10.2026).
local function safecall(...)
  return ns.safecall(...)
end
local label = ns.label

local function changed(kind, id, added)
  B:Fire("BASTIANS_REGISTRY_CHANGED", kind, id, added)
end

local function require_(def, field, kind)
  if def[field] == nil then
    error(("%s: `%s` is required"):format(kind, field), 3)
  end
end

local function hasType(def, entityType)
  if def.types == "*" then
    return true
  end
  for _, t in ipairs(def.types) do
    if t == entityType then
      return true
    end
  end
  return false
end

local function byOrder(a, b)
  if a.order ~= b.order then
    return a.order < b.order
  end
  return a.id < b.id
end

-- ---------------------------------------------------------------------------------------------
-- Entities (§4)
-- ---------------------------------------------------------------------------------------------

local Entity = {}
Entity.__index = Entity
B.Entity = Entity

local providers = {} -- type -> array of defs, highest priority first
local generation = 0
local facades = setmetatable({}, { __mode = "v" }) -- ref -> facade (weak, cheap to rebuild)

function Entity.Make(entityType, id)
  return entityType .. ":" .. tostring(id)
end

-- "npc:448" -> "npc", 448 ; "node:herb-2" -> "node", "herb-2" ; an extension's type carries its
-- namespace (ADR 0026): "gatherplus.route:7" -> "gatherplus.route", 7 ; anything else -> nil
function Entity.Parse(ref)
  if type(ref) ~= "string" then
    return nil
  end
  local entityType, id = string.match(ref, "^([%l%d_]+):(.+)$")
  if not entityType then
    entityType, id = string.match(ref, "^([%l%d_]+%.[%l%d_]+):(.+)$")
  end
  if not entityType then
    return nil
  end
  return entityType, tonumber(id) or id
end

function B:RegisterEntityType(owner, def)
  require_(def, "type", "RegisterEntityType")
  def.owner = owner
  def.priority = def.priority or 50
  local list = providers[def.type] or {}
  providers[def.type] = list
  list[#list + 1] = def
  table.sort(list, function(a, b)
    return a.priority > b.priority
  end)
  B:InvalidateEntities(def.type)
  changed("entity", def.type, true)
  track(owner, function()
    for i = #list, 1, -1 do
      if list[i] == def then
        table.remove(list, i)
      end
    end
    if #list == 0 then
      providers[def.type] = nil
    end
    B:InvalidateEntities(def.type)
    changed("entity", def.type, false)
  end)
end

function B:HasEntityType(entityType)
  return providers[entityType] ~= nil
end

-- The reading order of a type's sheet (ADR 0054): the `chapters` of the first provider that has
-- them, { { id, title }, ... }; a function there is asked with the entity's id (a monster reads in
-- another order than a vendor). nil for a type without chapters.
function B:GetChapters(entityType, id)
  for _, p in ipairs(providers[entityType] or {}) do
    local chapters = p.chapters
    if type(chapters) == "function" then
      local ok, list = safecall(p.owner, label(chapters, "entity " .. entityType .. " chapters"), id)
      chapters = ok and list or nil
    end
    if type(chapters) == "table" then
      return chapters
    end
  end
  return nil
end

-- Bumps the cache generation so every facade asks its providers again (§4).
function B:InvalidateEntities(entityType)
  generation = generation + 1
  B:Fire("BASTIANS_ENTITY_CHANGED", entityType)
end

local function ask(e, fn)
  if e.gen ~= generation then
    e.values = {}
    e.gen = generation
  end
  local cached = e.values[fn]
  if cached ~= nil then
    return cached or nil
  end
  local result
  local list = providers[e.type]
  if list then
    for _, p in ipairs(list) do
      if p[fn] then
        local ok, answer = safecall(p.owner, label(p[fn], "entity " .. e.type .. " " .. fn), e.id)
        if ok and answer ~= nil then
          result = answer
          break
        end
      end
    end
  end
  if result == nil then
    e.values[fn] = false -- a nil answer is cached too, until the next generation
  else
    e.values[fn] = result
  end
  return result
end

function Entity:Type()
  return self.type
end
function Entity:ID()
  return self.id
end
function Entity:Ref()
  return self.ref
end
function Entity:Name()
  return ask(self, "name")
end
function Entity:Icon()
  return ask(self, "icon")
end
-- The sheet's lead sentence (ADR 0054), from the provider that has one; nil: the host builds it.
function Entity:Lead()
  return ask(self, "lead")
end
function Entity:Summary()
  return ask(self, "summary")
end
function Entity:Fields()
  return ask(self, "fields")
end

-- Locations merge every provider's points and keep `src` on each (§4).
-- Location filters (R7, 22.10.2026): an app that knows which of an entity's places matter now
-- (Quests: the next place of a quest by its status) registers
-- `Bastians:RegisterLocationFilter(owner, { id, types, filter = function(ref, points) -> points })`;
-- `Entity:Locations()` returns the filtered list, `Entity:AllLocations()` every place.
local locationFilters = {} -- id -> def

function B:RegisterLocationFilter(owner, def)
  require_(def, "id", "RegisterLocationFilter")
  require_(def, "filter", "RegisterLocationFilter")
  require_(def, "types", "RegisterLocationFilter")
  def.owner = owner
  locationFilters[def.id] = def
  B:InvalidateEntities(nil)
  changed("locationfilter", def.id, true)
  track(owner, function()
    if locationFilters[def.id] == def then
      locationFilters[def.id] = nil
      B:InvalidateEntities(nil)
      changed("locationfilter", def.id, false)
    end
  end)
end

-- Map places for drawing from a provider's world places (ADR 0026: an extension answers `places`):
-- the map that holds the point best, its fractions; a place no map holds is left out.
local function toLocations(places)
  local out, coords = {}, B.Coords
  for _, p in ipairs(places) do
    if coords and p.map and p.wx and p.wy then
      local ui = p.ui or coords.BestMap(p.map, p.wx, p.wy)
      local x, y
      if ui then
        x, y = coords.ToMap(p.map, p.wx, p.wy, ui)
      end
      if x and y then
        out[#out + 1] = { map = ui, x = x, y = y, wz = p.wz, r = p.r, kind = p.kind, src = p.src }
      end
    end
  end
  return out
end

-- Every place of the entity, merged from the providers in priority order, unfiltered.
function Entity:AllLocations()
  if self.gen ~= generation then
    self.values = {}
    self.gen = generation
  end
  local cached = self.values.allLocations
  if cached then
    return cached
  end
  local merged = {}
  local list = providers[self.type]
  if list then
    for _, p in ipairs(list) do
      local ok, points
      if p.locations then
        ok, points = safecall(p.owner, label(p.locations, "entity " .. self.type .. " locations"), self.id)
      elseif p.places then
        ok, points = safecall(p.owner, label(p.places, "entity " .. self.type .. " places"), self.id)
        points = ok and type(points) == "table" and toLocations(points) or nil
      end
      if ok and type(points) == "table" then
        for _, point in ipairs(points) do
          merged[#merged + 1] = point
        end
      end
    end
  end
  self.values.allLocations = merged
  return merged
end

-- Facets (below) are declared here: the places of a thing with steps come from the facet `steps`.
local facetDefs = {} -- facet -> array of defs, highest priority first
local facetGeneration = {} -- facet -> generation, bumped by registrations and invalidateOn messages

-- Steps (ADR 0069, core-contracts §4 "Steps"): the places of the steps to do now, each
-- { map, x, y, kind, src, ref, step, label }. A facet without a `state` marks no step open: there
-- every step counts. A state and no open step: where the first step is (a done quest shows where
-- it began). Open steps and no place among them: the facet's waypoint, else nothing; no other
-- place is added, unknown stays unknown.
local STEP_KIND = { take = "giver", handin = "turnin" }

local function stepLocations(steps)
  local out, seen = {}, {}
  local function add(i, step)
    for _, p in ipairs(type(step.places) == "table" and step.places or {}) do
      local key = p.map and p.x and p.y and (p.map .. ":" .. p.x .. ":" .. p.y)
      if key and not seen[key] then
        seen[key] = true
        out[#out + 1] = {
          map = p.map,
          x = p.x,
          y = p.y,
          wz = p.wz,
          r = p.r,
          kind = STEP_KIND[step.step] or "objective",
          src = p.src or step.src,
          ref = p.ref or step.ref,
          step = i,
          label = p.label,
        }
      end
    end
  end
  local stated, anyOpen = steps.state ~= nil, false
  for i, step in ipairs(steps) do
    if type(step) == "table" and (not stated or step.open) then
      anyOpen = true
      add(i, step)
    end
  end
  if not anyOpen then
    if type(steps[1]) == "table" then
      add(1, steps[1])
    end
  elseif #out == 0 and type(steps.waypoint) == "table" then
    local w = steps.waypoint
    if w.map and w.x and w.y then
      out[1] = { map = w.map, x = w.x, y = w.y, kind = w.kind or "objective", src = w.src }
    end
  end
  return out
end

-- The places that matter now: of a thing with steps the open steps' places, of any other every
-- place; then through the registered filters of the type.
function Entity:Locations()
  local all = self:AllLocations()
  local stepsGen = facetGeneration.steps or 0
  local cached = self.values.locations
  if cached and self.values.locationsGen == stepsGen then
    return cached
  end
  local points = all
  local steps = facetDefs.steps and self:Facet("steps") or nil
  if steps then
    points = stepLocations(steps)
  end
  for _, def in pairs(locationFilters) do
    if hasType(def, self.type) then
      local ok, filtered =
        safecall(def.owner, label(def.filter, "filter " .. tostring(def.id)), self.ref, points)
      if ok and type(filtered) == "table" then
        points = filtered
      end
    end
  end
  self.values.locations, self.values.locationsGen = points, stepsGen
  self.values.places = nil -- Places() follows
  return points
end

-- Places (ADR 0026, core-contracts §4): world positions
-- { map, wx, wy, wz, r, ui, x, y, kind, src }, `map` the Map.db2 id. W5 builds the interface over
-- today's storage: a place is a location converted through Coords.ToWorld; `ui, x, y` stay for
-- drawing. A location whose map has no transform (an instance floor) keeps `ui, x, y` with
-- `map, wx, wy` nil. The packs move to world positions in W8.
local function toPlaces(points)
  local out = {}
  local coords = B.Coords
  for _, p in ipairs(points) do
    local map, wx, wy
    if coords and p.map and p.x and p.y then
      map, wx, wy = coords.ToWorld(p.map, p.x, p.y)
    end
    out[#out + 1] = {
      map = map,
      wx = wx,
      wy = wy,
      wz = p.wz,
      r = p.r,
      ui = p.map,
      x = p.x,
      y = p.y,
      kind = p.kind,
      src = p.src,
      ref = p.ref,
      step = p.step,
      label = p.label,
    }
  end
  return out
end

-- Every place of the entity, unfiltered.
function Entity:AllPlaces()
  local all = self:AllLocations()
  local cached = self.values.allPlaces
  if cached then
    return cached
  end
  cached = toPlaces(all)
  self.values.allPlaces = cached
  return cached
end

-- The places that matter now: Locations() (through the location filters) as places.
function Entity:Places()
  local points = self:Locations()
  local cached = self.values.places
  if cached then
    return cached
  end
  cached = toPlaces(points)
  self.values.places = cached
  return cached
end

-- ---------------------------------------------------------------------------------------------
-- Facets (§4, ADR 0026): computed views on any entity: poi, activity, worth, an extension's own
-- ---------------------------------------------------------------------------------------------

-- facetDefs and facetGeneration are declared above Entity:Locations(), which reads them.
local facetInvalidators = {} -- message -> { [facet] = true }, subscribed once per message
-- Facets put together from every rule of the type, field by field, the higher priority first
-- (ADR 0056: a tile's facts come from the app that knows each); the others take the first answer.
local ASSEMBLED = { tile = true }

local function bumpFacet(facet)
  facetGeneration[facet] = (facetGeneration[facet] or 0) + 1
end

-- Bastians:RegisterFacet(owner, { facet = "poi", types = { "npc" } | "*", priority = 50,
--   rule = function(ref) -> table | nil, invalidateOn = { messages },
--   list = function(ctx) -> { refs } (optional, R26.11: the things worth asking about now) })
-- The first rule (by priority) with a table answer wins; nil means the entity has no such facet.
-- The facet "tile" is assembled instead: every rule of the type answers, a field of a higher rule
-- stays. Answers are cached per entity generation and per facet generation.
function B:RegisterFacet(owner, def)
  require_(def, "facet", "RegisterFacet")
  require_(def, "types", "RegisterFacet")
  require_(def, "rule", "RegisterFacet")
  def.owner = owner
  def.priority = def.priority or 50
  local facet = def.facet
  local list = facetDefs[facet] or {}
  facetDefs[facet] = list
  list[#list + 1] = def
  table.sort(list, function(a, b)
    return a.priority > b.priority
  end)
  bumpFacet(facet)
  for _, msg in ipairs(def.invalidateOn or {}) do
    local facets = facetInvalidators[msg]
    if not facets then
      facets = {}
      facetInvalidators[msg] = facets
      ns.on(msg, function()
        for f in pairs(facets) do
          bumpFacet(f)
        end
      end)
    end
    facets[facet] = true
  end
  changed("facet", facet, true)
  track(owner, function()
    for i = #list, 1, -1 do
      if list[i] == def then
        table.remove(list, i)
      end
    end
    bumpFacet(facet)
    changed("facet", facet, false)
  end)
end

-- The refs the facet's rules offer through their `list` (R26.11), each once, in rule order; a
-- failing list is logged and left out.
function B:FacetCandidates(facet, ctx)
  local out, seen = {}, {}
  for _, def in ipairs(facetDefs[facet] or {}) do
    if def.list then
      local ok, refs = safecall(def.owner, label(def.list, facet .. " list"), ctx)
      if ok and type(refs) == "table" then
        for _, ref in ipairs(refs) do
          if type(ref) == "string" and not seen[ref] then
            seen[ref] = true
            out[#out + 1] = ref
          end
        end
      end
    end
  end
  return out
end

-- Whether a rule for the facet covers the type.
function B:HasFacet(facet, entityType)
  for _, def in ipairs(facetDefs[facet] or {}) do
    if hasType(def, entityType) then
      return true
    end
  end
  return false
end

-- Drops the cached answers of one facet, or of every facet with nil.
function B:InvalidateFacet(facet)
  if facet then
    bumpFacet(facet)
    return
  end
  for f in pairs(facetDefs) do
    bumpFacet(f)
  end
end

-- The facet's table or nil; cached until the entity or the facet generation moves.
-- An answer may carry colour codes (the worth's text with its coins), so it is kept per colour
-- set in force: the theme's, and the palette of a page on paper (the
-- first host to ask had fixed the colours for every other).
function Entity:Facet(facet)
  if self.facetEntityGen ~= generation then
    self.facetTones = {}
    self.facetEntityGen = generation
  end
  local tone = B.UI and B.UI.Style and B.UI.Style.H or self
  local slot = self.facetTones[tone]
  if not slot then
    slot = { values = {}, gens = {} }
    self.facetTones[tone] = slot
  end
  local gen = facetGeneration[facet] or 0
  if slot.gens[facet] == gen then
    return slot.values[facet] or nil
  end
  local result
  local assembled = ASSEMBLED[facet]
  for _, def in ipairs(facetDefs[facet] or {}) do
    if hasType(def, self.type) then
      local ok, answer = safecall(def.owner, label(def.rule, facet), self.ref)
      if ok and type(answer) == "table" then
        if not assembled then
          result = answer
          break
        end
        -- every rule adds what the rules above it left open (Quests the state of a quest and
        -- its chain, Data its level)
        result = result or {}
        for key, value in pairs(answer) do
          if result[key] == nil then
            result[key] = value
          end
        end
      end
    end
  end
  slot.values[facet] = result or false
  slot.gens[facet] = gen
  return result
end

-- Worth (§4, C3) is the facet "worth": { text, copper, xp }. The calls of C3 stay as its names.
-- Bastians:RegisterWorth(owner, { types, priority, worth = function(ref) -> table | nil,
--   invalidateOn }) is RegisterFacet with facet = "worth" and rule = worth.
function B:RegisterWorth(owner, def)
  require_(def, "types", "RegisterWorth")
  require_(def, "worth", "RegisterWorth")
  def.facet, def.rule = "worth", def.worth
  B:RegisterFacet(owner, def)
end

function B:HasWorth(entityType)
  return B:HasFacet("worth", entityType)
end

-- Drops every cached worth (a price source changed outside the registered messages).
function B:InvalidateWorth()
  B:InvalidateFacet("worth")
end

-- { text, copper, xp } or nil.
function Entity:Worth()
  return self:Facet("worth")
end

-- ---------------------------------------------------------------------------------------------
-- Sheets (§7, ADR 0056: one quest sheet): an app that draws the page of a type itself, the same
-- wherever a host shows such a page
-- ---------------------------------------------------------------------------------------------

local sheets = {} -- entity type -> def

-- Bastians:RegisterSheet(owner, { types = { "quest" },
--   draw = function(ref, host) -> height (host = { frame, width, ctx, buttons, refresh }),
--   hide = function(host) (optional: the host shows something else),
--   covers = { section ids the drawing says itself: the host leaves them out },
--   inside = true (optional: the thing can still be stepped into, ADR 0056; a chain) })
-- One sheet per type: the last registration stands.
function B:RegisterSheet(owner, def)
  require_(def, "types", "RegisterSheet")
  require_(def, "draw", "RegisterSheet")
  def.owner = owner
  for _, entityType in ipairs(def.types) do
    sheets[entityType] = def
    changed("sheet", entityType, true)
  end
  track(owner, function()
    for _, entityType in ipairs(def.types) do
      if sheets[entityType] == def then
        sheets[entityType] = nil
        changed("sheet", entityType, false)
      end
    end
  end)
end

-- The sheet registered for a type, or nil.
function B:GetSheet(entityType)
  return sheets[entityType]
end

-- ---------------------------------------------------------------------------------------------
-- Graph extensions (§4, ADR 0026): another addon's node types, edge types, facet rules, cost
-- profiles and annotations under one namespace. Data's graph reads them through GraphExtensions().
-- ---------------------------------------------------------------------------------------------

local extensions = {} -- ns -> def
local OUR_FACETS = { poi = true, activity = true, worth = true, tile = true }

-- Bastians:RegisterGraphExtension(owner, { ns, version, types = { [name] = { name, icon, summary,
--   places, locations, fields, priority } }, edges = { [name] = { from, to, props } },
--   facets = { { facet, types, rule, priority, invalidateOn } }, profiles = { [name] = fn },
--   annotate = fn }) -> true, or false when the namespace is taken (a log line says so).
function B:RegisterGraphExtension(owner, def)
  require_(def, "ns", "RegisterGraphExtension")
  local name = def.ns
  if type(name) ~= "string" or not name:match("^[a-z][a-z0-9]*$") then
    error(("RegisterGraphExtension: ns %q must be lowercase letters and digits"):format(tostring(name)), 2)
  end
  if extensions[name] then
    B:Log(owner, "warn", "graph extension namespace %s is taken; not registered", name)
    return false
  end
  for _, f in ipairs(def.facets or {}) do
    local facet = f.facet
    if type(facet) ~= "string" or not (OUR_FACETS[facet] or facet:sub(1, #name + 1) == name .. ".") then
      error(
        ("RegisterGraphExtension: facet %q is neither ours nor under %s."):format(tostring(facet), name),
        2
      )
    end
  end
  def.owner = owner
  def.version = def.version or 1
  extensions[name] = def
  local typeNames = {}
  for typ in pairs(def.types or {}) do
    typeNames[#typeNames + 1] = typ
  end
  table.sort(typeNames)
  for _, typ in ipairs(typeNames) do
    local t = def.types[typ]
    B:RegisterEntityType(owner, {
      type = name .. "." .. typ,
      priority = t.priority or 50,
      name = t.name,
      icon = t.icon,
      summary = t.summary,
      locations = t.locations,
      places = t.places,
      fields = t.fields,
    })
  end
  for _, f in ipairs(def.facets or {}) do
    B:RegisterFacet(owner, {
      facet = f.facet,
      types = f.types or "*",
      priority = f.priority or 20, -- below ours (Data's poi rule is 100)
      rule = f.rule,
      invalidateOn = f.invalidateOn,
    })
  end
  changed("graph", name, true)
  track(owner, function()
    if extensions[name] == def then
      extensions[name] = nil
      changed("graph", name, false)
    end
  end)
  return true
end

-- ns -> def of every registered extension; read only (Data's graph).
function B:GraphExtensions()
  return extensions
end

local function facade(ref)
  local e = facades[ref]
  if e then
    return e
  end
  local entityType, id = Entity.Parse(ref)
  if not entityType then
    error(("Entity: %q is not an entity reference"):format(tostring(ref)), 3)
  end
  e = setmetatable({ ref = ref, type = entityType, id = id, gen = -1, values = {} }, Entity)
  facades[ref] = e
  return e
end

-- Bastians:Entity("npc:448") (and Bastians.Entity("npc:448")) return the cached facade;
-- Bastians.Entity.Make / .Parse live on the same table.
setmetatable(Entity, {
  __call = function(_, a, b)
    return facade(type(a) == "string" and a or b)
  end,
})

ns.on("BASTIANS_DATA_LOADED", function()
  B:InvalidateEntities(nil)
end)

-- ---------------------------------------------------------------------------------------------
-- Actions (§5): `when` is evaluated when GetActions is called (click time), never while rendering
-- ---------------------------------------------------------------------------------------------

local actions = {} -- id -> def

function B:RegisterAction(owner, def)
  require_(def, "id", "RegisterAction")
  require_(def, "label", "RegisterAction")
  require_(def, "run", "RegisterAction")
  require_(def, "types", "RegisterAction")
  def.owner = owner
  def.order = def.order or 50
  actions[def.id] = def
  changed("action", def.id, true)
  track(owner, function()
    if actions[def.id] == def then
      actions[def.id] = nil
      changed("action", def.id, false)
    end
  end)
end

function B:GetAction(id)
  return actions[id]
end

-- Row tags (R3, 22.10.2026): a short word a host appends to a row of that entity, greyed, such as
-- "hidden" on a quest the player hid. `tag(ref)` returns the word or nil; evaluated per visible
-- row, so it must be a lookup, never a search.
local rowTags = {} -- id -> def

function B:RegisterRowTag(owner, def)
  require_(def, "id", "RegisterRowTag")
  require_(def, "tag", "RegisterRowTag")
  require_(def, "types", "RegisterRowTag")
  def.owner = owner
  rowTags[def.id] = def
  changed("rowtag", def.id, true)
  track(owner, function()
    if rowTags[def.id] == def then
      rowTags[def.id] = nil
      changed("rowtag", def.id, false)
    end
  end)
end

-- The first tag that applies to ref, or nil.
function B:RowTag(ref)
  if not next(rowTags) then
    return nil
  end
  local entityType = Entity.Parse(ref)
  if not entityType then
    return nil
  end
  for _, def in pairs(rowTags) do
    if hasType(def, entityType) then
      local ok, tag = safecall(def.owner, label(def.tag, "row tag"), ref)
      if ok and tag then
        return tag
      end
    end
  end
  return nil
end

-- Sorted list of the actions that apply to ref now. `ctx` is passed to `when`.
function B:GetActions(ref, ctx)
  local entityType = Entity.Parse(ref)
  local out = {}
  for _, def in pairs(actions) do
    if entityType and hasType(def, entityType) then
      local applies = true
      if def.when then
        local ok, result = safecall(def.owner, label(def.when, "action " .. def.id .. " when"), ref, ctx)
        applies = ok and result and true or false
      end
      if applies then
        out[#out + 1] = def
      end
    end
  end
  table.sort(out, byOrder)
  return out
end

function B:GetPrimaryAction(ref, ctx)
  return B:GetActions(ref, ctx)[1]
end

-- Whether an action (def or id) can run for ref now: `enabled(ref, ctx)` when the action has it,
-- else true. A disabled action is still listed (`when`), so hosts draw it greyed (owner,
-- 21.10.2026: "Open in Browser" greyed while the Browser is open, not hidden).
function B:ActionEnabled(def, ref, ctx)
  if type(def) ~= "table" then
    def = actions[def]
  end
  if not def then
    return false
  end
  if not def.enabled then
    return true
  end
  local ok, result = safecall(def.owner, label(def.enabled, "action " .. def.id .. " enabled"), ref, ctx)
  return ok and result and true or false
end

function B:RunAction(id, ref, ctx)
  local def = actions[id]
  if not def or not B:ActionEnabled(def, ref, ctx) then
    return false
  end
  return (safecall(def.owner, label(def.run, "action " .. def.id), ref, ctx))
end

-- ---------------------------------------------------------------------------------------------
-- Map layers (§6)
-- ---------------------------------------------------------------------------------------------

local layers = {} -- id -> def

function B:RegisterMapLayer(owner, def)
  require_(def, "id", "RegisterMapLayer")
  require_(def, "label", "RegisterMapLayer")
  require_(def, "query", "RegisterMapLayer")
  def.owner = owner
  def.minLevel = def.minLevel or 0
  def.maxLevel = def.maxLevel or math.huge
  if def.defaultOn == nil then
    def.defaultOn = true
  end
  layers[def.id] = def
  changed("layer", def.id, true)
  track(owner, function()
    if layers[def.id] == def then
      layers[def.id] = nil
      changed("layer", def.id, false)
    end
  end)
end

function B:GetMapLayer(id)
  return layers[id]
end

-- All layers sorted by owner then id, so the layers panel can group them.
function B:GetMapLayers()
  local out = {}
  for _, def in pairs(layers) do
    out[#out + 1] = def
  end
  table.sort(out, function(a, b)
    if a.owner ~= b.owner then
      return (a.owner.title or a.owner.name) < (b.owner.title or b.owner.name)
    end
    return a.id < b.id
  end)
  return out
end

-- ---------------------------------------------------------------------------------------------
-- Views (§7b, ADR 0012): what an app shows in the one window. A view renders into the host it is
-- given; the host is the service `views` (the Browser, else an app's own fallback window).
-- ---------------------------------------------------------------------------------------------

local views = {} -- id -> def

-- def.pinned (21.10.2026): the host keeps a toolbar button for the view ("My quests" one click
-- away, owner), besides listing it on the home.
function B:RegisterView(owner, def)
  require_(def, "id", "RegisterView")
  require_(def, "title", "RegisterView")
  require_(def, "render", "RegisterView")
  def.owner = owner
  def.order = def.order or 50
  def.group = def.group or owner.title or owner.name
  views[def.id] = def
  changed("view", def.id, true)
  track(owner, function()
    if views[def.id] == def then
      views[def.id] = nil
      changed("view", def.id, false)
    end
  end)
end

function B:GetView(id)
  return views[id]
end

-- Takes a view back before its owner is disabled (an option switched it off, 04.11.2026); true
-- when it was registered.
function B:UnregisterView(id)
  if views[id] == nil then
    return false
  end
  views[id] = nil
  changed("view", id, false)
  return true
end

-- ---------------------------------------------------------------------------------------------
-- Lists: an app
-- adds a list to the Browser's type bar beside the data types. def = { type, label, ids = fn() ->
-- array, record = fn(id) -> { name, level, zone, ... } or nil (left out), value = fn(record) ->
-- facet, facet (its name), ref = fn(id, record) -> the entity a row opens, suffix = fn(record) ->
-- grey words after the name or nil }.
-- ---------------------------------------------------------------------------------------------

local lists = {}

function B:RegisterList(owner, def)
  require_(def, "type", "RegisterList")
  require_(def, "label", "RegisterList")
  require_(def, "ids", "RegisterList")
  require_(def, "record", "RegisterList")
  def.owner = owner
  lists[def.type] = def
  changed("list", def.type, true)
  track(owner, function()
    if lists[def.type] == def then
      lists[def.type] = nil
      changed("list", def.type, false)
    end
  end)
end

-- The registered lists by label.
function B:GetLists()
  local out = {}
  for _, def in pairs(lists) do
    out[#out + 1] = def
  end
  table.sort(out, function(a, b)
    return tostring(a.label) < tostring(b.label)
  end)
  return out
end

-- ---------------------------------------------------------------------------------------------
-- Filters and sorts (core-contracts §7d, ADR 0016): an app adds a sort ("Loot per kill") or a
-- facet (a pill of its own) to the lists of the types it names. def = { id, kind = "sort" |
-- "facet", types = { "npc" } | "*", label, value = fn(ref, record) -> number (sort) or key
-- (facet) or nil, ascending = bool (sort: smallest first), text = fn(value) -> grey words on
-- the row while sorted, labels = fn(key) -> words (facet), invalidateOn = { messages } }.
-- ---------------------------------------------------------------------------------------------

local filters = {}
local filterGen = {} -- id -> generation, bumped by the def's invalidateOn messages
local filterInvalidators = {} -- message -> true once subscribed

local function bumpFilters(msg)
  for id, def in pairs(filters) do
    for _, m in ipairs(def.invalidateOn or {}) do
      if m == msg then
        filterGen[id] = (filterGen[id] or 0) + 1
      end
    end
  end
end

function B:RegisterFilter(owner, def)
  require_(def, "id", "RegisterFilter")
  require_(def, "types", "RegisterFilter")
  require_(def, "label", "RegisterFilter")
  require_(def, "value", "RegisterFilter")
  if def.kind ~= "sort" and def.kind ~= "facet" then
    error('RegisterFilter: `kind` must be "sort" or "facet"', 2)
  end
  def.owner = owner
  filters[def.id] = def
  filterGen[def.id] = (filterGen[def.id] or 0) + 1
  for _, msg in ipairs(def.invalidateOn or {}) do
    if not filterInvalidators[msg] then
      filterInvalidators[msg] = true
      ns.on(msg, function()
        bumpFilters(msg)
      end)
    end
  end
  changed("filter", def.id, true)
  track(owner, function()
    if filters[def.id] == def then
      filters[def.id] = nil
      changed("filter", def.id, false)
    end
  end)
end

function B:GetFilter(id)
  return filters[id]
end

-- Moves when the filter's values may have changed (its invalidateOn messages, a new registration):
-- a host keeps computed values with the generation they were computed at.
function B:FilterGeneration(id)
  return filterGen[id] or 0
end

-- The filters of a list type, of one kind ("sort", "facet") or both, by label.
function B:GetFilters(listType, kind)
  local out = {}
  for _, def in pairs(filters) do
    if (kind == nil or def.kind == kind) and hasType(def, listType) then
      out[#out + 1] = def
    end
  end
  table.sort(out, function(a, b)
    return tostring(a.label) < tostring(b.label)
  end)
  return out
end

-- A filter's value for one record; a provider that fails gives nil (logged), never a broken list.
function B:FilterValue(def, ref, record)
  local ok, value = safecall(def.owner, label(def.value, "filter"), ref, record)
  if ok then
    return value
  end
  return nil
end

-- All views sorted by group, then order, then id: the host's menu.
function B:GetViews()
  local out = {}
  for _, def in pairs(views) do
    out[#out + 1] = def
  end
  table.sort(out, function(a, b)
    if a.group ~= b.group then
      return tostring(a.group) < tostring(b.group)
    end
    return byOrder(a, b)
  end)
  return out
end

-- ---------------------------------------------------------------------------------------------
-- Stat tiles (ADR 0058, 07.11.2026): an app registers a figure for a rail entry of the Atlas; the
-- host draws up to four as tiles on Here and on a section's first tab. def = { id, rail, title,
-- order, build = function() -> { value, note, ref | nav, tip } or nil, invalidateOn }. A figure
-- nobody knows is nil: the tile says unknown, never 0; a build that answers nil draws no tile.
-- ---------------------------------------------------------------------------------------------

local stats = {} -- id -> def

function B:RegisterStat(owner, def)
  require_(def, "id", "RegisterStat")
  require_(def, "rail", "RegisterStat")
  require_(def, "title", "RegisterStat")
  require_(def, "build", "RegisterStat")
  def.owner = owner
  def.order = def.order or 50
  stats[def.id] = def
  changed("stat", def.id, true)
  track(owner, function()
    if stats[def.id] == def then
      stats[def.id] = nil
      changed("stat", def.id, false)
    end
  end)
end

function B:UnregisterStat(id)
  if stats[id] == nil then
    return false
  end
  stats[id] = nil
  changed("stat", id, false)
  return true
end

-- The stats of a rail entry (every one for nil), by order then id.
function B:GetStats(rail)
  local out = {}
  for _, def in pairs(stats) do
    if rail == nil or def.rail == rail then
      out[#out + 1] = def
    end
  end
  table.sort(out, byOrder)
  return out
end

-- The tile's figures through the owner's error guard: the build's table, or nil (no tile).
function B:BuildStat(def)
  local ok, got = safecall(def.owner, label(def.build, "stat " .. tostring(def.id)))
  if ok and type(got) == "table" then
    return got
  end
  return nil
end

-- Renders a view into a host with the owner's error guard; false when the view is missing or failed.
function B:RenderView(id, host)
  local def = views[id]
  if not def then
    return false
  end
  local ok = safecall(def.owner, label(def.render, "view " .. def.id), host, host.args or {})
  return ok and true or false
end

-- For hosts: a view became visible ("show", with its host) or stopped being visible ("hide");
-- runs the view's onShow / onHide with the owner's error guard.
function B:ViewEvent(id, what, host)
  local def = views[id]
  local fn = def and (what == "show" and def.onShow or what == "hide" and def.onHide)
  if fn then
    safecall(def.owner, fn, host)
  end
end

-- Opens a view in the active host (the `views` service); false when there is no host or no view.
function B:ShowView(id, args)
  local host = B:GetService("views")
  if not (host and views[id]) then
    return false
  end
  host:Show(id, args or {})
  return true
end

-- Opens an entity page in the active host (ADR 0013: the zone page is the way in); false when no
-- host shows pages (the Browser does, an app's fallback window may).
function B:ShowPage(ref)
  local host = B:GetService("views")
  if not (host and host.ShowPage and Entity.Parse(ref)) then
    return false
  end
  return host:ShowPage(ref) == true
end

-- Pins of one layer for a view; an empty table when the layer is missing, errors or is out of range.
function B:QueryLayer(id, view)
  local def = layers[id]
  if not def or view.level < def.minLevel or view.level > def.maxLevel then
    return {}
  end
  local ok, pins = safecall(def.owner, label(def.query, "layer " .. def.id), view)
  if ok and type(pins) == "table" then
    return pins
  end
  return {}
end

-- ---------------------------------------------------------------------------------------------
-- Detail sections (§7): rows cached per ref, invalidated by the section's own messages and by Core
-- ---------------------------------------------------------------------------------------------

local sections = {} -- id -> def
-- id -> { [tone] = { [ref] = rows | false, order = { refs } } }: rows carry colour codes (S.H), so
-- they are kept per colour set, the theme's and the palette of a page on paper (ADR 0054)
local sectionCache = {}
B.SECTION_CACHE_MAX = 64 -- refs kept per section (R10): a session visits hundreds of pages
local tooltipCache = {} -- ref -> rows
local invalidators = {} -- message -> set of section ids (subscribed once per message)

local function dropSection(id)
  sectionCache[id] = nil
  for ref in pairs(tooltipCache) do
    tooltipCache[ref] = nil
  end
end

-- Forgets the tooltip rows: what they say has changed (the Browser's key was bound).
function B:ForgetTooltipRows()
  for ref in pairs(tooltipCache) do
    tooltipCache[ref] = nil
  end
end

local function dropForType(entityType)
  for id, def in pairs(sections) do
    if entityType == nil or hasType(def, entityType) then
      dropSection(id)
    end
  end
end

function B:RegisterDetailSection(owner, def)
  require_(def, "id", "RegisterDetailSection")
  require_(def, "title", "RegisterDetailSection")
  require_(def, "types", "RegisterDetailSection")
  require_(def, "build", "RegisterDetailSection")
  def.owner = owner
  def.order = def.order or 50
  sections[def.id] = def
  dropSection(def.id) -- a fresh row cache, and tooltips of every entity see the new section
  for _, msg in ipairs(def.invalidateOn or {}) do
    if not invalidators[msg] then
      invalidators[msg] = {}
      ns.on(msg, function()
        for id in pairs(invalidators[msg]) do
          dropSection(id)
        end
      end)
    end
    invalidators[msg][def.id] = true
  end
  changed("section", def.id, true)
  track(owner, function()
    if sections[def.id] == def then
      sections[def.id] = nil
      dropSection(def.id)
      for _, set in pairs(invalidators) do
        set[def.id] = nil
      end
      changed("section", def.id, false)
    end
  end)
end

local function rowsFor(def, ref)
  if def.cache == false then -- rows that change with time (prices with their age): built every call
    local ok, built = safecall(def.owner, label(def.build, "section " .. def.id), ref)
    return ok and type(built) == "table" and #built > 0 and built or nil
  end
  local tones = sectionCache[def.id]
  if not tones then
    tones = {}
    sectionCache[def.id] = tones
  end
  local tone = B.UI and B.UI.Style and B.UI.Style.H or tones -- the colour set in force
  local cache = tones[tone]
  if not cache then
    cache = { order = {} } -- order: the refs in the order they came, for the cap
    tones[tone] = cache
  end
  local rows = cache[ref]
  if rows == nil then
    local ok, built = safecall(def.owner, label(def.build, "section " .. def.id), ref)
    rows = ok and type(built) == "table" and #built > 0 and built or false
    cache[ref] = rows
    -- the cap (R10, 22.10.2026: a session visits hundreds of pages): past SECTION_CACHE_MAX refs
    -- the oldest go; the pages at hand stay cached
    local order = cache.order
    order[#order + 1] = ref
    if #order > B.SECTION_CACHE_MAX then
      local drop = #order - B.SECTION_CACHE_MAX
      for i = 1, drop do
        cache[order[i]] = nil
      end
      local kept = {}
      for i = drop + 1, #order do
        kept[#kept + 1] = order[i]
      end
      cache.order = kept
    end
  end
  return rows or nil
end

-- Array of { id, title, order, rows, def } for the sections that have rows for ref, by order.
function B:GetDetailSections(ref)
  local entityType = Entity.Parse(ref)
  local out = {}
  for _, def in pairs(sections) do
    if entityType and hasType(def, entityType) then
      local rows = rowsFor(def, ref)
      if rows then
        local title = def.title
        if type(title) == "function" then -- a title with a count ("Hand in  3", ADR 0013)
          local ok, text = safecall(def.owner, label(title, "section " .. def.id .. " title"), ref, rows)
          title = ok and text or def.id
        end
        out[#out + 1] = { id = def.id, title = title, order = def.order, rows = rows, def = def }
      end
    end
  end
  table.sort(out, byOrder)
  return out
end

-- The section definitions for an entity type (by order, no rows built): hosts that draw sections
-- of their own accord (the Browser's Here column) subscribe to their `invalidateOn` messages.
function B:GetDetailSectionDefs(ref)
  local entityType = Entity.Parse(ref)
  local out = {}
  for _, def in pairs(sections) do
    if entityType and hasType(def, entityType) then
      out[#out + 1] = def
    end
  end
  table.sort(out, byOrder)
  return out
end

-- Tooltip rows from every section with a `tooltip` entry for this type, each capped at tooltip.max.
function B:GetTooltipRows(ref)
  local cached = tooltipCache[ref]
  if cached then
    return cached
  end
  local entityType = Entity.Parse(ref)
  local ordered = {}
  for _, def in pairs(sections) do
    local tip = def.tooltip
    if
      tip
      and tip.enabled ~= false
      and entityType
      and hasType({ types = tip.types or def.types }, entityType)
    then
      ordered[#ordered + 1] = def
    end
  end
  table.sort(ordered, byOrder)
  local out = {}
  local cacheable = true
  for _, def in ipairs(ordered) do
    local tip = def.tooltip
    if def.cache == false then
      cacheable = false
    end
    local ok, rows = safecall(def.owner, label(tip.build or def.build, "tooltip " .. def.id), ref)
    if ok and type(rows) == "table" then
      for i = 1, math.min(#rows, tip.max or 2) do
        out[#out + 1] = rows[i]
      end
    end
  end
  if cacheable then
    tooltipCache[ref] = out
  end
  return out
end

ns.on("BASTIANS_ENTITY_CHANGED", function(_, _, entityType)
  dropForType(entityType)
end)
ns.on("BASTIANS_DATA_LOADED", function()
  dropForType(nil)
end)
ns.on("BASTIANS_THEME_CHANGED", function() -- the codes in the cached rows are the old theme's
  dropForType(nil)
end)

-- ---------------------------------------------------------------------------------------------
-- Search providers (§7a): one Job per search, progressive callbacks, cross-provider ranking
-- ---------------------------------------------------------------------------------------------

local searchProviders = {} -- id -> def
B.SEARCH_PATIENCE = 10 -- seconds a provider may take; it is given up after them

function B:RegisterSearchProvider(owner, def)
  require_(def, "id", "RegisterSearchProvider")
  require_(def, "label", "RegisterSearchProvider")
  require_(def, "search", "RegisterSearchProvider")
  def.owner = owner
  def.priority = def.priority or 50
  searchProviders[def.id] = def
  changed("search", def.id, true)
  track(owner, function()
    if searchProviders[def.id] == def then
      searchProviders[def.id] = nil
      changed("search", def.id, false)
    end
  end)
end

local function rank(results)
  local best = {}
  local out = {}
  for _, r in ipairs(results) do
    local key = r.ref or ("label:" .. tostring(r.label))
    local prev = best[key]
    if not prev then
      best[key] = r
      out[#out + 1] = r
    elseif r.rank > prev.rank then
      for i, existing in ipairs(out) do
        if existing == prev then
          out[i] = r
        end
      end
      best[key] = r
    end
  end
  table.sort(out, function(a, b)
    if a.rank ~= b.rank then
      return a.rank > b.rank
    end
    return tostring(a.label) < tostring(b.label)
  end)
  return out
end

-- A leading type word narrows a search: "npc wel" finds NPCs whose name matches "wel" (owner,
-- 21.10.2026). Plurals and a few short forms are accepted; the word must be followed by a space.
B.SEARCH_TYPES = {
  npc = "npc",
  npcs = "npc",
  quest = "quest",
  quests = "quest",
  item = "item",
  items = "item",
  object = "object",
  objects = "object",
  zone = "zone",
  zones = "zone",
  -- not "area": "Area 52" is a place's name
  subzone = "area",
  subzones = "area",
  node = "node",
  nodes = "node",
  herb = "node",
  ore = "node",
  fp = "flightpath",
  flight = "flightpath",
  flightpath = "flightpath",
  recipe = "recipe",
  recipes = "recipe",
  transport = "transport",
  transports = "transport",
  dungeon = "dungeon",
  dungeons = "dungeon",
  raid = "dungeon",
  raids = "dungeon",
  spot = "spot",
  spots = "spot",
}

-- The `type:npc` (or `t:npc`) words of a search text (ADR 0045): the text without them, the
-- entity types, and the other `type:` words as kinds (`type:vendor`, an
-- NPC's service, an object's kind), lower case; nil for none. ParseSearch leaves the kinds in the
-- text, Bastians:Search reads them.
local function typeFields(text, takeKinds)
  local types, kinds
  local rest = string.gsub(text, "(%S+)", function(word)
    local field, value = string.match(word, "^(%a+):(%a+)$")
    field = field and string.lower(field)
    if field ~= "type" and field ~= "t" then
      return nil
    end
    local entityType = B.SEARCH_TYPES[string.lower(value)]
    if entityType then
      types = types or {}
      types[entityType] = true
      return ""
    elseif takeKinds then
      kinds = kinds or {}
      kinds[#kinds + 1] = string.lower(value)
      return ""
    end
  end)
  return (string.gsub(rest, "^%s*(.-)%s*$", "%1")), types, kinds
end

-- The results whose entity has every kind word asked for (`type:vendor`): Data's kind words of the
-- record (KindWords), so a result without a known kind leaves.
local function keepKinds(results, kinds)
  if not kinds then
    return results
  end
  local d = B:GetService("data")
  local out = {}
  for _, r in ipairs(results) do
    local entityType, id = Entity.Parse(r.ref or "")
    local words = d and d.KindWords and entityType and d:KindWords(entityType, id) or nil
    local all = words ~= nil
    for _, kind in ipairs(words and kinds or {}) do
      local found = false
      for _, w in ipairs(words) do
        if string.find(w, kind, 1, true) then
          found = true
          break
        end
      end
      all = all and found
    end
    if all then
      out[#out + 1] = r
    end
  end
  return out
end

-- Bastians.ParseSearch("npc wel") -> "wel", { npc = true }; the type word may come first or last
-- ("wel npc" is the same, ADR 0013 F), `type:npc` anywhere (ADR 0045); a plain query gives
-- (query, nil).
function B.ParseSearch(text)
  text = string.gsub(tostring(text or ""), "^%s*(.-)%s*$", "%1")
  local fieldTypes
  text, fieldTypes = typeFields(text)
  if fieldTypes then
    return text, fieldTypes
  end
  local word, rest = string.match(text, "^(%a+)%s+(.+)$")
  local entityType = word and B.SEARCH_TYPES[string.lower(word)]
  if entityType then
    return rest, { [entityType] = true }
  end
  rest, word = string.match(text, "^(.-)%s+(%a+)$")
  entityType = word and B.SEARCH_TYPES[string.lower(word)]
  if entityType then
    return rest, { [entityType] = true }
  end
  return text, nil
end

local function keepType(results, types)
  if not types then
    return results
  end
  local out = {}
  for _, r in ipairs(results) do
    local entityType = Entity.Parse(r.ref)
    if entityType and types[entityType] then
      out[#out + 1] = r
    end
  end
  return out
end

-- Bastians:Search(query, { limit = 50, types = { npc = true } }, callback(results, done)) -> handle
-- with :Cancel(). `types` keeps only results of those entity types; `type:npc` words in the query
-- do the same. Providers get the query lower-cased and compiled (ADR 0045):
-- search(text, limit, yield, q), q a Bastians.Query.
-- A search belongs to its caller, who cancels it; another caller's search leaves it alone (owner,
-- Forever 06.11.2026: "Searching ..." for good). `opts.onError()` hears of a callback that failed.
function B:Search(query, opts, callback)
  opts = opts or {}
  local typed, kinds
  query, typed, kinds = typeFields(string.gsub(tostring(query or ""), "^%s*(.-)%s*$", "%1"), true)
  opts = typed and not opts.types and setmetatable({ types = typed }, { __index = opts }) or opts
  -- `type:vendor` alone searches every name of that kind; providers read q.kinds (Data's Find)
  local q = B.Query.Compile((query == "" and kinds) and "*" or query)
  if kinds then
    q = setmetatable({ kinds = kinds }, { __index = q })
  end
  query = string.lower(query)
  local handle = { cancelled = false }
  function handle:Cancel()
    self.cancelled = true
    if self.job then
      self.job:Cancel()
    end
  end
  if q.empty then
    callback({}, true)
    return handle
  end
  local ordered = {}
  for _, def in pairs(searchProviders) do
    ordered[#ordered + 1] = def
  end
  table.sort(ordered, function(a, b)
    return a.priority > b.priority
  end)
  local limit = opts.limit or 50
  local collected = {}
  -- the caller hears of the results through the error guard, and a provider runs in a coroutine
  -- of its own: one that fails costs its own results, never the search (owner, Forever
  -- 06.11.2026: an error left every search on "Searching..." for good, the job died unfinished)
  local function tell(done)
    local shown = keepKinds(keepType(rank(collected), opts.types), kinds)
    if not ns.safecall(ns.coreOwner, callback, shown, done) and opts.onError then
      ns.safecall(ns.coreOwner, opts.onError)
    end
  end
  local function failed(def, why)
    ns.noteError(def.owner or ns.coreOwner, ("search %s: %s"):format(tostring(def.id), tostring(why)))
    return {}
  end
  local function run(def, yield)
    local co = coroutine.create(def.search)
    local started = GetTime()
    local ok, results = coroutine.resume(co, query, limit, coroutine.yield, q)
    while ok and coroutine.status(co) ~= "dead" do
      if GetTime() - started > B.SEARCH_PATIENCE then
        return failed(def, "gave up, it did not end")
      end
      yield()
      ok, results = coroutine.resume(co)
    end
    if not ok then
      return failed(def, results)
    end
    if results ~= nil and type(results) ~= "table" then
      return failed(def, "answered no list")
    end
    local out = {}
    for _, r in ipairs(results or {}) do
      if type(r) == "table" then
        out[#out + 1] = r
      end
    end
    return out
  end
  local function finished()
    if not handle.cancelled then
      tell(true)
    end
  end
  handle.job = B.Jobs:Run(ns.coreOwner, "search", function(yield)
    for _, def in ipairs(ordered) do
      for _, r in ipairs(run(def, yield)) do
        r.provider = def.id
        r.rank = (r.score or 0) * (1 + def.priority / 1000)
        collected[#collected + 1] = r
      end
      if not handle.cancelled then
        tell(false)
      end
      yield()
    end
  end, {
    onDone = finished,
    onFail = finished, -- a job that died has still ended: the caller is told what came
  })
  return handle
end

-- ---------------------------------------------------------------------------------------------
-- Services (§11): one active provider per name, the enabled one with the highest priority
-- ---------------------------------------------------------------------------------------------

-- the service table of §11
B.SERVICES = {
  data = true,
  prices = true,
  travel = true,
  progress = true,
  views = true,
  questSheet = true, -- the quest sheet: the Orbiter shows it on hover (Quests, ADR 0053)
  graph = true,
  route = true,
  notes = true,
  facts = true,
  library = true,
  knowledge = true, -- who knows a spell or recipe (Alts, 01.11.2026)
  requests = true, -- what the other characters asked this one for, by item (Alts, ADR 0058 PH6, 07.11.2026)
  neversell = true, -- the player's never-sell list (Helpers, ADR 0058 PH6, 07.11.2026)
  voice = true, -- speaks the suite's own words (the Orbiter, plan-launch-review R5.3, 01.11.2026)
  camps = true, -- the player's fire, camp buffs and shared fires (Bastian's Campfire, 02.11.2026)
  income = true, -- gold per day, AH apart from loot (Gold's Income.lua, 04.11.2026)
  waypoint = true, -- the player's own waypoint on Bastian's Map (#14, 04.11.2026)
  mapPicture = true, -- the chosen map style's cells for a picture (the Map, ADR 0056, PA6)
  account = true, -- the account's gold over its characters (Alts, #14, 04.11.2026)
}
local services = {} -- name -> array of { owner, impl, priority }
local active = {} -- name -> impl

local function recompute(name)
  local list = services[name]
  local best
  if list then
    for _, entry in ipairs(list) do
      if not best or entry.priority > best.priority then
        best = entry
      end
    end
  end
  local impl = best and best.impl or nil
  if active[name] ~= impl then
    active[name] = impl
    B:Fire("BASTIANS_SERVICE_CHANGED", name)
  end
end

function B:ProvideService(owner, name, impl, opts)
  if not B.SERVICES[name] then
    error(("ProvideService: %q is not in the service table (core-contracts §11)"):format(tostring(name)), 2)
  end
  local entry = { owner = owner, impl = impl, priority = opts and opts.priority or 50 }
  local list = services[name] or {}
  services[name] = list
  list[#list + 1] = entry
  recompute(name)
  track(owner, function()
    for i = #list, 1, -1 do
      if list[i] == entry then
        table.remove(list, i)
      end
    end
    recompute(name)
  end)
end

function B:GetService(name)
  return active[name]
end

-- ---------------------------------------------------------------------------------------------
-- Courtesy lines: a player's own, from the file they write (core-contracts 13, ADR 0063). Core only
-- keeps the list; Bastian's Courtesy checks the lines.
-- ---------------------------------------------------------------------------------------------

local courtesyLines = {}

function B:AddCourtesyLines(lines)
  if type(lines) ~= "table" then
    error("AddCourtesyLines: a table of lines is required", 2)
  end
  for _, line in ipairs(lines) do
    courtesyLines[#courtesyLines + 1] = line
  end
end

function B:GetCourtesyLines()
  return courtesyLines
end
