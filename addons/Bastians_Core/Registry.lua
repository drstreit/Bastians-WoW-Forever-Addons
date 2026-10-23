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

-- "npc:448" -> "npc", 448 ; "node:herb-2" -> "node", "herb-2" ; anything else -> nil
function Entity.Parse(ref)
  if type(ref) ~= "string" then
    return nil
  end
  local entityType, id = string.match(ref, "^([%l%d_]+):(.+)$")
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
      if p.locations then
        local ok, points =
          safecall(p.owner, label(p.locations, "entity " .. self.type .. " locations"), self.id)
        if ok and type(points) == "table" then
          for _, point in ipairs(points) do
            merged[#merged + 1] = point
          end
        end
      end
    end
  end
  self.values.allLocations = merged
  return merged
end

-- The places that matter now: every place, through the registered filters of the type.
function Entity:Locations()
  local all = self:AllLocations()
  local cached = self.values.locations
  if cached then
    return cached
  end
  local points = all
  for _, def in pairs(locationFilters) do
    if hasType(def, self.type) then
      local ok, filtered =
        safecall(def.owner, label(def.filter, "filter " .. tostring(def.id)), self.ref, points)
      if ok and type(filtered) == "table" then
        points = filtered
      end
    end
  end
  self.values.locations = points
  return points
end

-- ---------------------------------------------------------------------------------------------
-- Worth (§4, C3): what an entity is worth, in words and numbers, from the app that knows
-- ---------------------------------------------------------------------------------------------

local worthDefs = {} -- array of defs, highest priority first
local worthGeneration = 0 -- bumped by the defs' invalidateOn messages
local worthInvalidators = {} -- message -> true once subscribed

-- Bastians:RegisterWorth(owner, { types = { "quest" } | "*", priority = 50,
--   worth = function(ref) -> { text, copper, xp } | nil, invalidateOn = { messages } })
-- The first provider (by priority) with a table answer wins; nil means "no worth line". Answers
-- are cached per entity generation and per worth generation (the invalidateOn messages bump it).
function B:RegisterWorth(owner, def)
  require_(def, "types", "RegisterWorth")
  require_(def, "worth", "RegisterWorth")
  def.owner = owner
  def.priority = def.priority or 50
  worthDefs[#worthDefs + 1] = def
  table.sort(worthDefs, function(a, b)
    return a.priority > b.priority
  end)
  worthGeneration = worthGeneration + 1
  for _, msg in ipairs(def.invalidateOn or {}) do
    if not worthInvalidators[msg] then
      worthInvalidators[msg] = true
      ns.on(msg, function()
        worthGeneration = worthGeneration + 1
      end)
    end
  end
  track(owner, function()
    for i = #worthDefs, 1, -1 do
      if worthDefs[i] == def then
        table.remove(worthDefs, i)
      end
    end
    worthGeneration = worthGeneration + 1
  end)
end

function B:HasWorth(entityType)
  for _, def in ipairs(worthDefs) do
    if hasType(def, entityType) then
      return true
    end
  end
  return false
end

-- Drops every cached worth (a price source changed outside the registered messages).
function B:InvalidateWorth()
  worthGeneration = worthGeneration + 1
end

-- { text, copper, xp } or nil; cached until the entity or the worth generation moves.
function Entity:Worth()
  if self.worthGen ~= worthGeneration or self.worthEntityGen ~= generation then
    self.worthValue = nil
    self.worthGen, self.worthEntityGen = worthGeneration, generation
  end
  local cached = self.worthValue
  if cached ~= nil then
    return cached or nil
  end
  local result
  for _, def in ipairs(worthDefs) do
    if hasType(def, self.type) then
      local ok, answer = safecall(def.owner, label(def.worth, "worth"), self.ref)
      if ok and type(answer) == "table" then
        result = answer
        break
      end
    end
  end
  self.worthValue = result or false
  return result
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
local sectionCache = {} -- id -> { [ref] = rows | false, order = { refs } }
B.SECTION_CACHE_MAX = 64 -- refs kept per section (R10): a session visits hundreds of pages
local tooltipCache = {} -- ref -> rows
local invalidators = {} -- message -> set of section ids (subscribed once per message)

local function dropSection(id)
  sectionCache[id] = nil
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
  local cache = sectionCache[def.id]
  if not cache then
    cache = { order = {} } -- order: the refs in the order they came, for the cap
    sectionCache[def.id] = cache
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

-- ---------------------------------------------------------------------------------------------
-- Search providers (§7a): one Job per search, progressive callbacks, cross-provider ranking
-- ---------------------------------------------------------------------------------------------

local searchProviders = {} -- id -> def
local currentSearch

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
  spot = "spot",
  spots = "spot",
}

-- Bastians.ParseSearch("npc wel") -> "wel", { npc = true }; the type word may come first or last
-- ("wel npc" is the same, ADR 0013 F); a plain query gives (query, nil).
function B.ParseSearch(text)
  text = string.gsub(tostring(text or ""), "^%s*(.-)%s*$", "%1")
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
-- with :Cancel(). `types` keeps only results of those entity types.
function B:Search(query, opts, callback)
  if currentSearch then
    currentSearch:Cancel()
    currentSearch = nil
  end
  opts = opts or {}
  query = string.lower(string.gsub(tostring(query or ""), "^%s*(.-)%s*$", "%1"))
  local handle = { cancelled = false }
  function handle:Cancel()
    self.cancelled = true
    if self.job then
      self.job:Cancel()
    end
  end
  if query == "" then
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
  handle.job = B.Jobs:Run(ns.coreOwner, "search", function(yield)
    for _, def in ipairs(ordered) do
      local results = def.search(query, limit, yield) or {}
      for _, r in ipairs(results) do
        r.provider = def.id
        r.rank = (r.score or 0) * (1 + def.priority / 1000)
        collected[#collected + 1] = r
      end
      if not handle.cancelled then
        callback(keepType(rank(collected), opts.types), false)
      end
      yield()
    end
  end, {
    onDone = function()
      if not handle.cancelled then
        callback(keepType(rank(collected), opts.types), true)
      end
      if currentSearch == handle then
        currentSearch = nil
      end
    end,
  })
  currentSearch = handle
  return handle
end

-- ---------------------------------------------------------------------------------------------
-- Services (§11): one active provider per name, the enabled one with the highest priority
-- ---------------------------------------------------------------------------------------------

B.SERVICES = { data = true, prices = true, travel = true, progress = true, views = true } -- §11
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
