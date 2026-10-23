-- Quest views (quests.md): Zone, Active, All quests and Chains as row trees. Pure over Logic, State
-- and Rows: every builder takes plain values and returns rows plus counts, so the tests run them
-- without the window. Ported from AHSyncGuide Tab_Zone.lua and Tab_Active.lua.
local _, ns = ...
local B = Bastians
local S = B.UI.Style
local L = ns.L
local Logic, State, R, Rec = ns.Logic, ns.State, ns.Rows, ns.Recommend
local C = R.COLOR -- the theme's text codes, read at use (ST3)

local V = {}
ns.Views = V

V.TITLES = {
  turnin = "Hand in",
  active = "In progress",
  available = "Take",
  soon = "Soon",
  onward = "Onward",
  blocked = "Prerequisite elsewhere",
  done = "Done",
}
V.ORDER = { "turnin", "active", "available", "soon", "onward", "blocked", "done" }

local CATEGORIES = {
  { "chain", "Chains" },
  { "group", "Group and dungeon" },
  { "class", "Class" },
  { "profession", "Profession" },
  { "single", "Single quests" },
}

local function dist2(px, py, x, y)
  if not (px and x) then
    return math.huge
  end
  return (px - x) ^ 2 + (py - y) ^ 2
end

-- ---------------------------------------------------------------------------------------------
-- Zone view
-- ---------------------------------------------------------------------------------------------

-- "Take" split into chains, group, class, profession and single quests, each a folded category.
local function availableRows(view, state, map, px, py)
  local avail = {}
  for _, g in ipairs(view.available) do
    for _, qid in ipairs(g.quests) do
      avail[#avail + 1] = qid
    end
  end
  local by = { chain = {}, group = {}, class = {}, profession = {}, single = {} }
  local chains, chainOrder = {}, {}
  for _, qid in ipairs(avail) do
    local cat = Logic.category(qid, state)
    if cat == "single" and Logic.isGroup(Logic.quest(qid)) then
      cat = "group"
    end
    if cat == "chain" then
      local ch = Logic.chain(qid, state)
      if not chains[ch.id] then
        chains[ch.id] = ch
        chainOrder[#chainOrder + 1] = ch
      end
    else
      table.insert(by[cat], qid)
    end
  end
  table.sort(chainOrder, function(a, b)
    local la = Logic.quest(a.quests[1]).level or 0
    local lb = Logic.quest(b.quests[1]).level or 0
    if la ~= lb then
      return la < lb
    end
    return a.id < b.id
  end)
  local cats = {}
  for _, c in ipairs(CATEGORIES) do
    local key, title = c[1], c[2]
    local children, n
    if key == "chain" then
      children = {}
      for _, ch in ipairs(chainOrder) do
        children[#children + 1] = R.chain(ch, state, map)
      end
      n = #chainOrder
    else
      children = R.groups(Logic.group(by[key], map, "start", px, py), state, map, key, "start")
      n = #by[key]
    end
    if n > 0 then
      cats[#cats + 1] = {
        id = "c:" .. key,
        text = C.grey .. L[title] .. "  " .. n .. "|r",
        children = children,
      }
    end
  end
  return cats, #avail
end

local function blockedRows(blocked, state, map)
  local out = {}
  for _, b in ipairs(blocked) do
    local first = b.missing[1]
    local fq = Logic.quest(first)
    local fm = fq and Logic.startMap(fq)
    local extra = "  " .. C.grey .. L["first"] .. ":|r " .. R.questName(first)
    if fm then
      extra = extra .. C.grey .. " (" .. R.zoneName(fm) .. ")|r"
    end
    local row = R.quest(b.qid, state, { status = "prereq", map = map, extra = extra })
    row.missing = b.missing
    out[#out + 1] = row
  end
  return out
end

local function onwardRows(onward, onZone)
  local out = {}
  for _, o in ipairs(onward) do
    local lead = o.n == 1 and L["quest leads there"] or L["quests lead there"]
    local text = C.orange .. "> |r" .. C.white .. (o.name or R.zoneName(o.map)) .. "|r  " .. C.grey
    local band = R.band(o)
    if band ~= "" then
      text = text .. band .. " - "
    end
    text = text .. o.n .. " " .. lead .. "|r"
    out[#out + 1] = R.zone(o.map, text, onZone)
  end
  return out
end

-- The zone view for `map`: sections in V.ORDER, each with a count; px, py are the player's map
-- fractions when the player is on that map. opts: { showDone, onZone(map), progressOf(qid) }.
-- Returns rows, counts (section key -> number), view (the Logic result).
function V.zone(map, state, px, py, opts)
  opts = opts or {}
  if not map then
    return { R.note("note:nomap", L["No zone: the map position is unknown here."]) }, {}
  end
  if not Logic.knows(map) then
    return { R.note("note:unknown", L["No quest data for this zone."]) }, {}
  end
  local view = Logic.zoneView(map, state, px, py)
  local onward = Logic.onward(map, state)
  local roots, counts = {}, {}
  local T = V.TITLES

  counts.turnin = view.counts.turnin
  if counts.turnin > 0 then
    local rows = R.groups(view.turnin, state, map, "turnin", "turnin")
    roots[#roots + 1] = R.section("turnin", L[T.turnin], counts.turnin, rows)
  end
  counts.active = view.counts.active
  if counts.active > 0 then
    local rows = R.groups(view.active, state, map, "active", "turnin")
    for _, g in ipairs(rows) do
      for _, row in ipairs(g.children or {}) do
        local progress = opts.progressOf and opts.progressOf(row.qid)
        if progress and progress ~= "" then
          row.text = row.text .. "  " .. C.grey .. progress .. " " .. L["objectives"] .. "|r"
        end
      end
    end
    roots[#roots + 1] = R.section("active", L[T.active], counts.active, rows)
  end
  local cats, nAvail = availableRows(view, state, map, px, py)
  counts.available = nAvail
  if nAvail > 0 then
    roots[#roots + 1] = R.section("available", L[T.available], nAvail, cats)
  end
  counts.soon = view.counts.soon
  if counts.soon > 0 then
    local rows = R.groups(view.soon, state, map, "soon", "start")
    local suffix = " (" .. L["up to level"] .. " " .. (state.level + Logic.SOON) .. ")"
    roots[#roots + 1] = R.section("soon", L[T.soon], counts.soon, rows, suffix)
  end
  counts.onward = #onward
  if #onward > 0 then
    roots[#roots + 1] = R.section("onward", L[T.onward], #onward, onwardRows(onward, opts.onZone))
  end
  counts.blocked = view.counts.blocked
  if counts.blocked > 0 then
    local rows = blockedRows(view.blocked, state, map)
    roots[#roots + 1] = R.section("blocked", L[T.blocked], counts.blocked, rows)
  end
  counts.done = view.counts.done or 0
  if opts.showDone and counts.done > 0 then
    local rows = R.groups(view.done, state, map, "done", "start")
    roots[#roots + 1] = R.section("done", L[T.done], counts.done, rows)
  end
  if counts.turnin + counts.active + counts.available + counts.soon == 0 then
    table.insert(roots, 1, R.note("note:none", L["No quests (left) here for this character."]))
  end
  return roots, counts, view
end

-- The summary line under the zone toolbar.
function V.zoneSummary(counts)
  local parts = { (counts.available or 0) .. " " .. L["to take"] }
  if (counts.turnin or 0) > 0 then
    parts[#parts + 1] = counts.turnin .. " " .. L["to hand in"]
  end
  if (counts.active or 0) > 0 then
    parts[#parts + 1] = counts.active .. " " .. L["in progress"]
  end
  if (counts.soon or 0) > 0 then
    parts[#parts + 1] = counts.soon .. " " .. L["soon"]
  end
  return table.concat(parts, " - ")
end

-- ---------------------------------------------------------------------------------------------
-- Active view: the quest log, sorted by what to do on the viewed map
-- ---------------------------------------------------------------------------------------------

-- Where a log entry sends the player: the hand-in when complete, else the nearest objective spot
-- on the viewed map, else the first map with spots, else the hand-in. Sets map, x, y, target, d.
local function placeEntry(row, e, q, map, px, py)
  local function turnIn()
    local p = q and q.endPlaces and q.endPlaces[1]
    row.map = q and Logic.turnInMap(q) or nil
    row.x, row.y = p and p[2] or nil, p and p[3] or nil
    row.target = "turnin"
  end
  if e.isComplete then
    turnIn()
  else
    local spots = q and q.spots
    local list = spots and spots[map]
    local cx, cy
    if not (list and #list > 0) then
      -- no spot in the pack (retail, D2): the client's next step on this map
      cx, cy = B.Compat.GetQuestWaypoint(e.questID, map)
    end
    if cx then
      row.map, row.x, row.y, row.target = map, cx, cy, "objective"
      row.src = "client"
    elseif list and #list > 0 then
      local best, bd
      for _, s in ipairs(list) do
        local d = dist2(px, py, s[1], s[2])
        if not bd or d < bd then
          best, bd = s, d
        end
      end
      row.map, row.x, row.y, row.target = map, best[1], best[2], "objective"
    elseif spots and next(spots) then
      local first
      for m in pairs(spots) do
        if not first or m < first then
          first = m
        end
      end
      local s = spots[first][1]
      row.map, row.x, row.y, row.target = first, s[1], s[2], "objective"
    elseif q then
      turnIn()
    else
      row.map, row.x, row.y, row.target = nil, nil, nil, "objective" -- not in the pack: unknown
    end
  end
  row.d = (row.map == map) and dist2(px, py, row.x, row.y) or math.huge
end

-- One quest of the log with objectives, the folded quest text and the quest item row below.
-- opts: { questText(qid) -> details, objectives ; questItem(entry) -> { itemID, icon, link } or nil }
function V.activeRow(e, state, map, px, py, opts)
  opts = opts or {}
  local q = Logic.quest(e.questID)
  local status = e.isComplete and "complete" or "log"
  local progress = R.progressText(e)
  local pdone, ptotal = R.progressOf(e)
  local pcol = e.isComplete and R.COLOR.green or R.progressColor(pdone, ptotal > 0 and ptotal or nil)
  local row = R.quest(e.questID, state, {
    status = status,
    title = e.title,
    map = map,
    where = e.isComplete and "turnin" or "start",
    extra = progress ~= "" and ("  " .. pcol .. progress .. "|r") or nil,
  })
  row.id = "a:" .. e.questID
  row.entry = e
  placeEntry(row, e, q, map, px, py)

  local children = R.objectives(e)
  local details, objText
  if opts.questText then
    details, objText = opts.questText(e.questID)
  end
  local first = R.firstSentence(details)
  local more = {
    id = "more:" .. e.questID,
    text = C.grey .. (first or L["Quest text"]) .. "|r",
    collapsed = true,
    children = {},
  }
  for i, p in ipairs(R.paragraphs(details)) do
    more.children[#more.children + 1] =
      { id = "pa:" .. e.questID .. ":" .. i, kind = "para", text = C.grey .. p .. "|r" }
  end
  if objText and objText ~= "" then
    more.children[#more.children + 1] =
      { id = "pa:" .. e.questID .. ":o", kind = "para", text = C.white .. objText .. "|r" }
  end
  if #more.children == 0 then
    more.children[1] =
      { id = "pa:" .. e.questID .. ":0", kind = "para", text = C.grey .. L["(no quest text)"] .. "|r" }
  end
  children[#children + 1] = more
  local item = opts.questItem and opts.questItem(e)
  if item then
    row.useItem, row.itemIcon, row.rightPad = item.itemID, item.icon, 24
    children[#children + 1] = {
      id = "use:" .. e.questID,
      kind = "useitem",
      useItem = item.itemID,
      itemIcon = item.icon,
      rightPad = 30,
      height = 26,
      text = "  " .. L["Use quest item"] .. ": " .. (item.link or ("item:" .. item.itemID)),
    }
  end
  row.children = children
  return row
end

-- The active view for the viewed map. Returns rows and a summary table { log, here, goals, hidden }.
-- opts (besides activeRow's): hideDone = true leaves out the complete quests (ready to hand in),
-- trackedOnly = true only keeps the quests on the objective tracker (isTracked(qid), State's by
-- default); the tracker's filters. The hidden count goes to the summary.
function V.active(map, px, py, opts)
  opts = opts or {}
  local state = State.ForLogic()
  local isTracked = opts.isTracked or State.IsTracked
  local here, goals, doneElsewhere, doneUnknown = {}, {}, {}, {}
  local byZone, zoneOrder = {}, {}
  local hidden = 0
  for _, qid in ipairs(State.order) do
    local e = State.log[qid]
    if (opts.hideDone and e.isComplete) or (opts.trackedOnly and not isTracked(qid)) then
      hidden = hidden + 1
    else
      local row = V.activeRow(e, state, map, px, py, opts)
      if e.isComplete and row.map == map then
        here[#here + 1] = row
      elseif e.isComplete and row.map == nil then
        doneUnknown[#doneUnknown + 1] = row -- no data for the hand-in: say so, never "elsewhere"
      elseif e.isComplete then
        doneElsewhere[#doneElsewhere + 1] = row
      elseif row.map == map then
        goals[#goals + 1] = row -- objective spots here, or the hand-in here when no spot is known
      else
        local m = row.map or 0
        local z = byZone[m]
        if not z then
          local name = m ~= 0 and R.zoneName(m) or L["Unknown place"]
          z = {
            id = "az:" .. m,
            ref = m ~= 0 and ("zone:" .. m) or nil,
            text = C.grey .. name .. "|r",
            children = {},
            group = true, -- a click folds the group
          }
          byZone[m] = z
          zoneOrder[#zoneOrder + 1] = z
        end
        z.children[#z.children + 1] = row
      end
    end
  end
  local function byDistance(list)
    table.sort(list, function(a, b)
      if a.d ~= b.d then
        return a.d < b.d
      end
      return (a.entry.title or "") < (b.entry.title or "")
    end)
  end
  byDistance(here)
  byDistance(goals)
  local roots = {}
  if #here > 0 then
    roots[#roots + 1] = R.section("a_turnin", L["Hand in here"], #here, here)
  end
  if #goals > 0 then
    roots[#roots + 1] = R.section("a_goals", L["Objectives here"], #goals, goals)
  end
  if #zoneOrder > 0 then
    local n = 0
    for _, z in ipairs(zoneOrder) do
      n = n + #z.children
      z.text = z.text .. "  " .. C.grey .. #z.children .. "|r"
    end
    roots[#roots + 1] = R.section("a_elsewhere", L["Elsewhere"], n, zoneOrder)
  end
  if #doneElsewhere > 0 then
    roots[#roots + 1] = R.section("a_done", L["Complete, hand in elsewhere"], #doneElsewhere, doneElsewhere)
  end
  if #doneUnknown > 0 then
    roots[#roots + 1] = R.section("a_unknown", L["Complete, place unknown"], #doneUnknown, doneUnknown)
  end
  if State.count == 0 then
    roots[#roots + 1] = R.note("a_note", L["The quest log is empty."])
  elseif hidden == State.count then
    local why = opts.trackedOnly and L["No tracked quest: track one from its row, or switch Tracked off."]
      or L["Every quest in the log is complete and hidden: switch Hide done off."]
    roots[#roots + 1] = R.note("a_note", why)
  end
  return roots, { log = State.count, here = #here, goals = #goals, hidden = hidden }
end

function V.activeSummary(s)
  local text = s.log
    .. " "
    .. L["in the log"]
    .. " - "
    .. s.here
    .. " "
    .. L["to hand in"]
    .. " - "
    .. s.goals
    .. " "
    .. L["objectives here"]
  if s.hidden and s.hidden > 0 then
    text = text .. " - " .. s.hidden .. " " .. L["hidden"]
  end
  return text
end

-- ---------------------------------------------------------------------------------------------
-- All quests: every quest the data knows, by zone, with status, type and level filters
-- ---------------------------------------------------------------------------------------------

V.STATUS = { "available", "log", "done", "soon", "later", "blocked", "never" }
V.STATUS_LABEL = {
  available = "Available",
  log = "In log",
  done = "Done",
  soon = "Soon",
  later = "Later",
  blocked = "Blocked",
  never = "Not for this character",
}
V.KINDS = {
  "any",
  "Group",
  "Dungeon",
  "Raid",
  "Class",
  "Profession",
  "Forever",
  "Holiday",
  "Repeatable",
  "PvP",
  "Escort",
}
V.BANDS = { "any", "1-10", "11-20", "21-30", "31-40", "41-50", "51-60" }

-- Logic status -> chip key.
function V.statusKey(st, q, state)
  if st == "available" or st == "log" or st == "done" then
    return st
  elseif st == "level" then
    if (q.minLevel or 0) - state.level <= Logic.SOON then
      return "soon"
    end
    return "later"
  elseif st == "prereq" or st == "skill" or st == "rep" then
    return "blocked"
  end
  return "never"
end

local function hasKind(q, kind)
  if kind == "any" or kind == nil then
    return true
  elseif kind == "Group" then
    return q.qtype == 1
  elseif kind == "Dungeon" then
    return q.qtype == 81 or Logic.hasFlag(q, "instance")
  elseif kind == "Raid" then
    return q.qtype == 62
  elseif kind == "PvP" then
    return q.qtype == 41
  elseif kind == "Escort" then
    return q.qtype == 84
  elseif kind == "Class" then
    return (q.classes and q.classes > 0) or Logic.hasFlag(q, "class")
  elseif kind == "Profession" then
    return q.skill ~= nil or Logic.hasFlag(q, "profession")
  elseif kind == "Forever" then
    return q.foreverOnly == true
  elseif kind == "Holiday" then
    return q.holiday ~= nil
  elseif kind == "Repeatable" then
    return Logic.hasFlag(q, "repeatable")
  end
  return true
end

local function inBand(q, band)
  if band == "any" or band == nil then
    return true
  end
  local lo, hi = string.match(band, "^(%d+)%-(%d+)$")
  lo, hi = tonumber(lo), tonumber(hi)
  local level = q.level
  return level ~= nil and level >= lo and level <= hi
end

-- filter = { status (chip key or nil), kind (V.KINDS entry), band (V.BANDS entry) }. `yield` is
-- called every 100 quests (Jobs), `textOf(qid)` adds quest text to the search string when given.
-- Returns rows (zone sections in level order, folded), counts per status key, total shown.
function V.all(state, filter, yield, textOf)
  filter = filter or {}
  local byZone, order = {}, {}
  local counts, shown, n = {}, 0, 0
  for _, qid in ipairs(Logic.allQuestIDs()) do
    n = n + 1
    if yield and n % 100 == 0 then
      yield()
    end
    local q = Logic.quest(qid)
    local st = Logic.status(qid, state)
    local key = V.statusKey(st, q, state)
    counts[key] = (counts[key] or 0) + 1
    if
      (filter.status == nil or filter.status == key)
      and hasKind(q, filter.kind)
      and inBand(q, filter.band)
    then
      shown = shown + 1
      local m = Logic.startMap(q) or 0
      local z = byZone[m]
      if not z then
        z = { map = m, children = {} }
        byZone[m] = z
        order[#order + 1] = z
      end
      local row = R.quest(qid, state, { status = st, map = m })
      if textOf then
        local text = textOf(qid)
        if text then
          row.search = string.lower(R.questName(qid) .. " " .. text)
        end
      end
      z.children[#z.children + 1] = row
    end
  end
  for _, z in ipairs(order) do
    local info = z.map ~= 0 and Logic.zoneInfo(z.map) or nil
    z.med = info and info.med or 999
    z.name = z.map ~= 0 and R.zoneName(z.map) or L["Unknown zone"]
    z.band = R.band(info)
  end
  table.sort(order, function(a, b)
    if a.med ~= b.med then
      return a.med < b.med
    end
    return a.map < b.map
  end)
  local roots = {}
  for _, z in ipairs(order) do
    local suffix = z.band ~= "" and ("  " .. z.band) or ""
    local section = R.section("all:" .. z.map, z.name, #z.children, z.children, suffix)
    section.collapsed = true
    section.ref = z.map ~= 0 and ("zone:" .. z.map) or nil
    roots[#roots + 1] = section
  end
  if #roots == 0 then
    roots[1] = R.note("note:none", L["No quests match the filter."])
  end
  return roots, counts, shown
end

-- Chips for the status facet with counts.
function V.statusChips(counts)
  local chips = {}
  for _, key in ipairs(V.STATUS) do
    if (counts[key] or 0) > 0 then
      chips[#chips + 1] = { key = key, label = L[V.STATUS_LABEL[key]], count = counts[key] }
    end
  end
  return chips
end

-- ---------------------------------------------------------------------------------------------
-- Here: the ranked recommendations for the viewed map and the next areas
-- ---------------------------------------------------------------------------------------------

-- ctx as Recommend.rank takes it (log, px, py, distance, travel, price, grouped, weights, times);
-- `faction` for the planner, `onZone(map)` for the zone rows. Returns rows and a summary table.
function V.here(map, state, ctx, faction, onZone)
  if not map then
    return { R.note("note:nomap", L["No zone: the map position is unknown here."]) }, { recs = 0, areas = 0 }
  end
  if not Logic.knows(map) then
    return { R.note("note:unknown", L["No quest data for this zone."]) }, { recs = 0, areas = 0 }
  end
  local areas = Rec.nextAreas(map, state, faction)
  ctx.nextZones = ctx.nextZones or Rec.nextZoneSet(areas)
  local recs = Rec.rank(map, state, ctx)
  local roots = {}
  local rows, hiddenRows = {}, {}
  local hidden = ctx.hidden or {}
  for _, rec in ipairs(recs) do
    local entry = rec.inLog and ctx.log and ctx.log[rec.qid] or nil
    local row = R.quest(rec.qid, state, {
      map = map,
      where = rec.inLog and "turnin" or "start",
      title = entry and entry.title or nil, -- the client's title wins, as in the Active view
      extra = "  " .. C.grey .. rec.reason .. "|r",
    })
    row.score = rec.score
    row.value = string.format("%.0f/%s", rec.score, L["min"])
    row.valueKind = "text"
    if hidden[rec.qid] then
      -- hidden by the player: out of the ranking, listed apart, greyed
      row.id = "hidden:" .. rec.qid
      row.color = S.C.muted
      hiddenRows[#hiddenRows + 1] = row
    else
      row.id = "rec:" .. rec.qid
      row.rank = #rows + 1
      if rec.score == 0 then
        row.color = S.C.dim
      end
      rows[#rows + 1] = row
    end
  end
  if #rows > 0 then
    roots[#roots + 1] = R.section("recs", L["Do now"], #rows, rows)
  else
    roots[#roots + 1] = R.note("note:norecs", L["Nothing to do here for this character."])
  end
  if #hiddenRows > 0 then
    local section = R.section("hidden", L["Hidden"], #hiddenRows, hiddenRows)
    section.collapsed = true -- folded until the player looks
    roots[#roots + 1] = section
  end
  local areaRows = {}
  for _, z in ipairs(areas) do
    local text = C.orange
      .. "> |r"
      .. C.white
      .. (z.name or R.zoneName(z.map))
      .. "|r  "
      .. C.grey
      .. R.band(z)
    if #z.leads > 0 then
      local lead = #z.leads == 1 and L["quest leads there"] or L["quests lead there"]
      text = text .. " - " .. #z.leads .. " " .. lead
    end
    text = text .. "|r"
    local row = R.zone(z.map, text, onZone)
    row.children = {}
    for _, qid in ipairs(z.leads) do
      row.children[#row.children + 1] = R.quest(qid, state, { map = map, where = "lead" })
    end
    areaRows[#areaRows + 1] = row
  end
  if #areaRows > 0 then
    local suffix = " (" .. L["level"] .. " " .. (state.level + 1) .. "-" .. (state.level + 3) .. ")"
    roots[#roots + 1] = R.section("areas", L["Next areas"], #areaRows, areaRows, suffix)
  end
  return roots, { recs = #recs, areas = #areas }
end

function V.hereSummary(s)
  return s.recs .. " " .. L["recommendations"] .. " - " .. s.areas .. " " .. L["next areas"]
end

-- ---------------------------------------------------------------------------------------------
-- Attunements: the lists of the character's faction with one row per step
-- ---------------------------------------------------------------------------------------------

V.STANDINGS = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }

-- ctx = { hasItem(itemID) -> bool, rep(factionID) -> { name, standing } or nil }.
-- Returns rows and a summary table { total, complete }.
function V.attunements(state, faction, ctx)
  ctx = ctx or {}
  local list = Logic.attunements(faction)
  if #list == 0 then
    return { R.note("note:none", L["No attunements known for this faction and client."]) }, {
      total = 0,
      complete = 0,
    }
  end
  local roots, complete = {}, 0
  for _, a in ipairs(list) do
    local steps, done = {}, 0
    for i, step in ipairs(a.steps or {}) do
      local kind, id, label = step[1], step[2], step[3]
      local row, ok
      if kind == "quest" then
        ok = state.done(id)
        row = R.quest(id, state, { title = Logic.quest(id) and nil or label, where = "att" })
        row.id = "att:" .. a.id .. ":" .. i
      elseif kind == "item" then
        ok = ctx.hasItem and ctx.hasItem(id) or false
        row = {
          id = "att:" .. a.id .. ":" .. i,
          ref = "item:" .. id,
          text = (ok and B.UI.Icon("done") or B.UI.Icon("waiting")) .. C.white .. label .. "|r",
        }
      else -- rep
        local want = step[4] or 6
        local rep = ctx.rep and ctx.rep(id) or nil
        ok = rep ~= nil and (rep.standing or 0) >= want
        local current = rep and L[V.STANDINGS[rep.standing] or "?"] or L["unknown"]
        row = {
          id = "att:" .. a.id .. ":" .. i,
          text = (ok and B.UI.Icon("done") or B.UI.Icon("waiting"))
            .. C.white
            .. label
            .. ": "
            .. L[V.STANDINGS[want] or "?"]
            .. "|r  "
            .. C.grey
            .. "("
            .. L["now"]
            .. " "
            .. current
            .. ")|r",
        }
      end
      if ok then
        done = done + 1
      end
      steps[#steps + 1] = row
    end
    local n = #(a.steps or {})
    if n > 0 and done == n then
      complete = complete + 1
    end
    local suffix = ""
    if not a.verified then
      suffix = suffix .. "  " .. C.orange .. L["unverified"] .. "|r"
    end
    if a.note then
      suffix = suffix .. "  " .. C.grey .. a.note .. "|r"
    end
    local section = R.section("att:" .. a.id, a.name, done .. "/" .. n, steps)
    section.text = section.text .. suffix
    section.collapsed = n > 0 and done == n
    roots[#roots + 1] = section
  end
  return roots, { total = #list, complete = complete }
end

function V.attunementSummary(s)
  return s.complete .. " " .. L["of"] .. " " .. s.total .. " " .. L["attunements complete"]
end

-- ---------------------------------------------------------------------------------------------
-- Chains: one quest's chain, or every chain with a quest of the viewed zone
-- ---------------------------------------------------------------------------------------------

function V.chains(map, state, qid)
  if qid then
    local ch = Logic.chain(qid, state)
    if not ch then
      return {
        R.quest(qid, state, { map = map, zone = true }),
        R.note("note:single", L["This quest is not part of a chain."]),
      }
    end
    local row = R.chain(ch, state, map)
    row.collapsed = false
    return { row }
  end
  local seen, chains = {}, {}
  for _, id in ipairs(Logic.questsOfZone(map)) do
    local ch = Logic.chain(id, state)
    if ch and not seen[ch.id] then
      seen[ch.id] = true
      chains[#chains + 1] = ch
    end
  end
  table.sort(chains, function(a, b)
    local la = Logic.quest(a.quests[1]).level or 0
    local lb = Logic.quest(b.quests[1]).level or 0
    if la ~= lb then
      return la < lb
    end
    return a.id < b.id
  end)
  local rows = {}
  for _, ch in ipairs(chains) do
    local row = R.chain(ch, state, map)
    row.collapsed = true
    rows[#rows + 1] = row
  end
  if #rows == 0 then
    rows[1] = R.note("note:nochains", L["No quest chains in this zone."])
  end
  return rows
end
