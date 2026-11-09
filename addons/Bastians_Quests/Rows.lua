-- Quest rows (quests.md): builders that turn Logic and State results into rows of the shared tree
-- renderer (core-contracts §7). They read the data service and the state table only; no frames here.
local _, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
local L = ns.L
local Logic = ns.Logic

local R = {}
ns.Rows = R

-- The quest colours by name, as the theme's text codes (ST3): read at use, so a theme change shows
-- at the next draw. red to grey is the game's difficulty scale; white the strongest text.
local COLOR_TOKEN = {
  red = "diffRed",
  orange = "diffOrange",
  yellow = "diffYellow",
  green = "diffGreen",
  grey = "muted",
  white = "bright",
  blue = "typeItem", -- the Forever-only tag (missing until launch night 05.11.2026: nil colour, Rows.lua:222)
}
R.COLOR = setmetatable({}, {
  __index = function(_, name)
    local token = COLOR_TOKEN[name]
    return token and B.UI.Style.H[token] or nil
  end,
})
local C = R.COLOR

local function accent()
  return B.UI.Style.accent()
end
R.accent = accent

-- ---------------------------------------------------------------------------------------------
-- Pure helpers
-- ---------------------------------------------------------------------------------------------

-- Levels below the player that still give experience (the Classic rule).
function R.greenRange(playerLevel)
  if playerLevel <= 5 then
    return 5
  end
  if playerLevel <= 39 then
    return math.floor(playerLevel / 10) + 5
  end
  return math.floor(playerLevel / 5) + 1
end

-- Quest level colour: red from +5, orange from +3, yellow around the player, green in the range
-- that still gives experience, grey below. White when a level is unknown.
function R.levelColor(level, playerLevel)
  if not level or not playerLevel then
    return C.white
  end
  local diff = level - playerLevel
  if diff >= 5 then
    return C.red
  elseif diff >= 3 then
    return C.orange
  elseif diff >= -2 then
    return C.yellow
  elseif -diff <= R.greenRange(playerLevel) then
    return C.green
  end
  return C.grey
end

local ICON = {
  done = "done",
  log = "questActive",
  complete = "done", -- done looks done, not like the open quests (ADR 0053)
  available = "quest",
  soon = "waiting",
  level = "waiting",
  prereq = "waiting",
  skill = "waiting",
  rep = "waiting",
  never = "never",
  superseded = "never",
}

function R.statusIcon(status)
  return B.UI.Icon(ICON[status] or "quest")
end

-- The same picture as a texture, for a tile (ADR 0056: a quest's state is its picture).
function R.statusTexture(status)
  return B.UI.IconTexture(ICON[status] or "quest")
end

-- Paragraphs of a quest text ($B is the client's line break).
function R.paragraphs(text)
  local out = {}
  local s = string.gsub(tostring(text or ""), "%$[Bb]", "\n")
  for part in string.gmatch(s, "[^\n]+") do
    local p = string.match(part, "^%s*(.-)%s*$")
    if p ~= "" then
      out[#out + 1] = p
    end
  end
  return out
end

-- How far a log entry is: the count of a single counted objective ("0/6", not "0/1"), else its
-- finished and total objectives (0, 0 without objectives).
function R.progressOf(entry)
  local total = #(entry.objectives or {})
  local only = total == 1 and entry.objectives[1]
  if only and only.required and only.required > 0 then
    return only.fulfilled or 0, only.required
  end
  local done = 0
  for _, o in ipairs(entry.objectives or {}) do
    if o.finished then
      done = done + 1
    end
  end
  return done, total
end

-- R.progressOf as "done/total", or "" without objectives.
function R.progressText(entry)
  local done, total = R.progressOf(entry)
  if total == 0 then
    return ""
  end
  return done .. "/" .. total
end

-- Objective progress in colour: red at
-- nothing, through orange and yellow, green when done. Takes `fulfilled, required` or a fraction
-- alone; white when the progress is unknown (no required count).
-- On a light ground (a page on paper, the Parchment theme) the bright scale cannot be read (owner,
-- Forever 05.11.2026: yellow counts on parchment): there it runs between the colour set's own
-- difficulty colours, which are made for that ground.
local function lightGround()
  local t = B.UI.Style.C.text
  return t ~= nil and (0.2126 * t[1] + 0.7152 * t[2] + 0.0722 * t[3]) < 0.5
end

local function mixed(a, b, t)
  local function part(i)
    return math.floor((a[i] + (b[i] - a[i]) * t) * 255 + 0.5)
  end
  return string.format("|cff%02x%02x%02x", part(1), part(2), part(3))
end

function R.progressColor(fulfilled, required)
  local p
  if required == nil then
    p = fulfilled
  elseif required > 0 then
    p = (fulfilled or 0) / required
  end
  if p == nil then
    return C.white
  end
  if p >= 1 then
    return C.green
  end
  if p < 0 then
    p = 0
  end
  if lightGround() then
    local c = B.UI.Style.C
    if p < 0.5 then
      return mixed(c.diffRed, c.diffYellow, p * 2)
    end
    return mixed(c.diffYellow, c.diffGreen, (p - 0.5) * 2)
  end
  local r, g, b
  if p < 0.5 then -- red (255, 64, 64) to yellow (255, 224, 0)
    local t = p * 2
    r, g, b = 255, math.floor(64 + 160 * t), math.floor(64 * (1 - t))
  else -- yellow to a light green (128, 208, 0) just before done
    local t = (p - 0.5) * 2
    r, g, b = math.floor(255 - 127 * t), math.floor(224 - 16 * t), 0
  end
  return string.format("|cff%02x%02x%02x", r, g, b)
end

-- ---------------------------------------------------------------------------------------------
-- Names
-- ---------------------------------------------------------------------------------------------

-- The pack's name, else the client's through the entity (Data.Names: retail packs carry no quest
-- titles; the rows re-render when a title arrives, ), else a label.
function R.questName(qid, fallback)
  local q = Logic.quest(qid)
  local name = q and q.name
  if not name and q then
    name = B:Entity("quest:" .. tostring(qid)):Name()
  end
  return name or fallback or (L["Quest"] .. " " .. tostring(qid))
end

-- The side factions answer no faction data to a character (Forever 23.10.2026: "Reputation:
-- Faction 67" on a quest page); their names are fixed.
R.SIDE_FACTIONS = { [67] = "Horde", [469] = "Alliance" }

-- A faction's name: the client's, a side faction's, or nil.
function R.factionName(factionID)
  local rep = B.Compat.GetReputation(factionID)
  if rep and rep.name then
    return rep.name
  end
  local side = R.SIDE_FACTIONS[factionID]
  return side and L[side] or nil
end

function R.zoneName(map)
  if not map then
    return nil
  end
  return B:Entity("zone:" .. map):Name() or (L["Zone"] .. " " .. tostring(map))
end

-- "12-20" for a zone record from Logic.zoneInfo, "" when unknown.
function R.band(z)
  if z and z.lo and z.hi then
    return z.lo .. "-" .. z.hi
  end
  return ""
end

-- ---------------------------------------------------------------------------------------------
-- Quest rows
-- ---------------------------------------------------------------------------------------------

-- Marks after the title: chain position, group marks, where it leads, decision, class, ...
function R.tags(qid, q, state, map)
  local tags = {}
  local function add(color, text)
    tags[#tags + 1] = color .. text .. "|r"
  end
  -- its step on the chain's main line, as the strip of its sheet says it (ADR 0055); a side
  -- quest carries the word alone
  local place = Logic.chainPlace(qid, state)
  if place and place.step then
    add(accent(), L["Chain"] .. " " .. place.step .. "/" .. place.steps)
  elseif place and not place.why then
    add(accent(), L["Chain"])
  end
  for _, m in ipairs(Logic.marks(q)) do
    add(C.orange, L[m])
  end
  if map then
    local leads = Logic.leadsTo(qid, map)
    if #leads > 0 then
      local names = {}
      for i = 1, math.min(2, #leads) do
        names[#names + 1] = R.zoneName(leads[i])
      end
      add(C.orange, "> " .. table.concat(names, ", "))
    end
  end
  if q.excl then
    add(C.red, L["Decision"])
  end
  if q.classes and q.classes > 0 then
    add(C.grey, L["Class"])
  end
  if q.skill then
    add(C.grey, L["Profession"])
  end
  if q.minRep then
    add(C.grey, L["Reputation"])
  end
  if q.foreverOnly then
    add(C.blue, L["Forever"])
  end
  if #tags == 0 then
    return ""
  end
  return "  " .. table.concat(tags, C.grey .. " - |r")
end

-- A quest row. opts: { status, where ("start" | "turnin", part of the id), map (the viewed map),
-- title (client title when the data has none), extra (appended text), zone (name the start map when
-- it is not the viewed one) }. Left click runs the primary action of `quest:<id>`.
function R.quest(qid, state, opts)
  opts = opts or {}
  local q = Logic.quest(qid)
  local st = opts.status or (q and Logic.status(qid, state)) or "log"
  local title = opts.title or R.questName(qid)
  local row = {
    id = "q:" .. qid .. ":" .. (opts.where or "start"),
    ref = "quest:" .. qid,
    qid = qid,
    status = st,
  }
  if not q then
    row.text = R.statusIcon(st) .. C.white .. title .. "|r" .. (opts.extra or "")
    return row
  end
  local head = R.statusIcon(st)
    .. R.levelColor(q.level, state.level)
    .. "["
    .. tostring(q.level or "?")
    .. "] "
    .. title
    .. "|r"
  local meta = R.tags(qid, q, state, opts.map)
  if opts.zone then
    local sm = Logic.startMap(q)
    if sm and sm ~= opts.map then
      meta = meta .. C.grey .. "  (" .. R.zoneName(sm) .. ")|r"
    end
  end
  if opts.extra then
    meta = meta .. opts.extra
  end
  row.text = head .. meta
  -- a two-line host (the Here column, R2) draws the name and, under it, the meta line
  row.title = head
  meta = string.gsub(meta, "^%s+", "")
  if meta ~= "" then
    row.meta = meta
  end
  local rw = Logic.rewards(qid)
  local money = rw and rw.money
  if money and money > 0 then
    row.value, row.valueKind = money, "money"
  end
  return row
end

-- Rows for Logic.group results: one row per giver or taker (its entity ref) with the quests below.
function R.groups(groups, state, map, prefix, which)
  local out = {}
  for _, g in ipairs(groups) do
    local name = g.ref and B:Entity(g.ref):Name() or nil
    local label = name or g.ref or L["Unknown place"]
    local coords = g.x and string.format("%.1f, %.1f", g.x * 100, g.y * 100) or ""
    local row = {
      id = "g:" .. prefix .. ":" .. tostring(g.ref) .. "@" .. coords,
      ref = g.ref,
      map = map,
      x = g.x,
      y = g.y,
      text = C.white .. label .. "|r" .. (coords ~= "" and ("  " .. C.grey .. coords .. "|r") or ""),
      children = {},
      group = true, -- a click folds the group; the zone page is one of its icons
    }
    for _, qid in ipairs(g.quests) do
      row.children[#row.children + 1] = R.quest(qid, state, { where = which, map = map })
    end
    out[#out + 1] = row
  end
  return out
end

-- A chain row with its steps below: "name  done/total  next: ..." and the summed reward money.
function R.chain(ch, state, map)
  local done, nextQ, nextSt = 0, nil, nil
  local steps, marks, seen = {}, {}, {}
  local total
  for _, qid in ipairs(ch.quests) do
    local q = Logic.quest(qid)
    for _, m in ipairs(Logic.marks(q)) do
      if not seen[m] then
        seen[m] = true
        marks[#marks + 1] = L[m]
      end
    end
    local st = Logic.status(qid, state)
    if st == "done" then
      done = done + 1
    end
    if not nextQ and (st == "available" or st == "log") then
      nextQ, nextSt = qid, st
    end
    local rw = Logic.rewards(qid)
    local money = rw and rw.money
    if money and money > 0 then
      total = (total or 0) + money
    end
    steps[#steps + 1] = R.quest(qid, state, {
      status = st,
      zone = true,
      map = map,
      where = st == "log" and "turnin" or "start",
    })
  end
  local name = R.questName(ch.quests[1])
  local text = accent() .. name .. "|r  " .. C.grey .. done .. "/" .. #ch.quests
  if nextQ then
    text = text .. "  " .. L["next"] .. ": " .. R.questName(nextQ)
  end
  text = text .. "|r"
  if #marks > 0 then
    text = text .. "  " .. C.orange .. table.concat(marks, ", ") .. "|r"
  end
  return {
    id = "k:" .. ch.id,
    chain = ch.id,
    block = true,
    nextQuest = nextQ,
    nextStatus = nextSt,
    text = text,
    children = steps,
    value = total,
    valueKind = total and "money" or nil,
    tooltip = function(tt)
      B.UI.Style.TipLine(tt, name, "tipGold")
      tt:AddLine(string.format(L["Chain of %d steps, %d done"], #ch.quests, done), 0.6, 0.6, 0.6)
      if nextQ then
        tt:AddDoubleLine(L["next"], R.questName(nextQ), 0.6, 0.6, 0.6, 1, 1, 1)
      end
    end,
  }
end

-- An objective's words without the count the client's text may carry ("0/6 Shiny Junk", "Shiny
-- Junk: 0/6"): the row prints the count itself.
function R.objectiveLabel(o)
  local text = tostring(o.text or "")
  if not (o.required and o.required > 0) then
    return text -- no count of ours: the client's stays
  end
  text = string.gsub(text, "^%d+/%d+%s+", "")
  return (string.gsub(text, ":?%s+%d+/%d+$", ""))
end

-- The task row of a quest (ADR 0052): what to do in the quest's own words, or nil without them.
function R.taskRow(qid, text)
  local parts = R.paragraphs(text)
  if #parts == 0 then
    return nil
  end
  return { id = "task:" .. qid, kind = "para", text = table.concat(parts, " ") }
end

-- Who takes a done quest, in words, or nil when nobody is known: "Hand in to Morgan Pestle,
-- Stormwind"; the zone only when it is not the one the player is on (`map`).
function R.handInWords(q, map)
  local ref = q and q.ends and q.ends[1]
  local name = ref and B:Entity(ref):Name() or nil
  if not name then
    return nil
  end
  local there = Logic.turnInMap(q)
  if there and there ~= map then
    return string.format(L["Hand in to %s, %s"], name, R.zoneName(there))
  end
  return string.format(L["Hand in to %s"], name)
end

-- The lines under a quest's name in My quests (ADR 0053): who takes a done quest, else the first
-- objective, and the others as a list for the lines below it.
function R.nextStep(entry, q, map)
  if entry.isComplete then
    local words = R.handInWords(q, map)
    return C.green .. L["Done."] .. (words and (" " .. words) or "") .. "|r"
  end
  local lines = R.objectiveLines(entry)
  if #lines == 0 then
    return C.grey .. L["In progress"] .. "|r"
  end
  return table.remove(lines, 1), lines
end

-- Every objective of a log entry, one line each with its count first (
-- "I cannot see multiple objectives in a quest, but that is necessary").
function R.objectiveLines(entry)
  local lines = {}
  for _, o in ipairs(entry.objectives or {}) do
    local count = ""
    if o.required and o.required > 0 then
      local col = o.finished and C.green or R.progressColor(o.fulfilled or 0, o.required)
      count = col .. (o.fulfilled or 0) .. "/" .. o.required .. "|r "
    end
    lines[#lines + 1] = count .. (o.finished and C.green or C.white) .. R.objectiveLabel(o) .. "|r"
  end
  return lines
end

-- Objective rows of a log entry: finished ones grey with a check, open ones with their count.
function R.objectives(entry)
  local out = {}
  for i, o in ipairs(entry.objectives or {}) do
    -- the colour follows the progress: green when finished, red to yellow on the way, white
    -- when the objective has no count
    local col = C.white
    if o.finished then
      col = C.green
    elseif o.required and o.required > 0 then
      col = R.progressColor(o.fulfilled or 0, o.required)
    end
    local progress = ""
    if o.required and o.required > 0 then
      progress = "  " .. col .. tostring(o.fulfilled or 0) .. "/" .. o.required .. "|r"
    end
    out[#out + 1] = {
      id = "ob:" .. entry.questID .. ":" .. i,
      text = (o.finished and B.UI.Icon("done") or "") .. col .. R.objectiveLabel(o) .. "|r" .. progress,
    }
  end
  return out
end

-- ---------------------------------------------------------------------------------------------
-- Structure rows
-- ---------------------------------------------------------------------------------------------

-- ---------------------------------------------------------------------------------------------
-- A progress chain ("hard to figure out where you are in the chain,
-- what chain quest is available"): the steps numbered with their state in a few words, the step
-- to act on next marked "you are here", a head line with the count and the next step. One
-- renderer for quest chains, attunements (quest, reputation and item steps) and dungeon pages.
-- ---------------------------------------------------------------------------------------------

R.STANDINGS = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }

local STATE_WORDS = {
  available = { "available now", "yellow" },
  log = { "in your log", "white" },
  done = { "done", "grey" },
  level = { "needs level %d", "grey" },
  skill = { "needs a profession skill", "grey" },
  rep = { "needs reputation", "grey" },
  superseded = { "replaced by another quest", "grey" },
  never = { "not for this character", "grey" },
  inactive = { "not offered now", "grey" },
}

-- The words of a quest's state on a step; a prerequisite inside the chain reads "after step k".
local function stateWords(st, qid, missing, pos)
  if st == "prereq" then
    local inside = {}
    for _, m in ipairs(missing or {}) do
      if pos[m] then
        inside[#inside + 1] = pos[m]
      end
    end
    if #inside > 0 then
      table.sort(inside)
      return string.format(L["after step %d"], inside[1]), C.grey
    end
    local m = missing and missing[1]
    return string.format(L["needs %s"], m and R.questName(m) or "?"), C.grey
  end
  local def = STATE_WORDS[st] or STATE_WORDS.never
  local text = L[def[1]]
  if st == "level" then
    local q = Logic.quest(qid)
    text = string.format(text, q and q.minLevel or 0)
  end
  return text, C[def[2]]
end

local function stepName(step)
  if step.kind == "quest" then
    return R.questName(step.id, step.label)
  end
  return step.label or "?"
end

-- steps = { { kind = "quest" | "rep" | "item", id, label, standing } }; ctx = { hasItem(itemID),
-- rep(factionID) -> { standing } } for the item and reputation steps; opts = { map, key }.
-- -> the rows (a head line, then one per step) and { total, done, current }.
function R.progress(steps, state, ctx, opts)
  ctx, opts = ctx or {}, opts or {}
  local key = opts.key or "progress"
  local pos = {}
  for i, step in ipairs(steps) do
    if step.kind == "quest" then
      pos[step.id] = i
    end
  end
  local states, missing, oks = {}, {}, {}
  local done, current = 0, nil
  for i, step in ipairs(steps) do
    local st, ok, miss
    if step.kind == "quest" then
      if Logic.quest(step.id) then
        st, miss = Logic.status(step.id, state)
      else
        st = state.done(step.id) and "done" or "available"
      end
      ok = st == "done"
    elseif step.kind == "item" then
      ok = ctx.hasItem and ctx.hasItem(step.id) or false
      st = ok and "done" or "available"
    else
      local rep = ctx.rep and ctx.rep(step.id) or nil
      ok = rep ~= nil and (rep.standing or 0) >= (step.standing or 6)
      st = ok and "done" or "available"
    end
    states[i], missing[i], oks[i] = st, miss, ok
    if ok then
      done = done + 1
    end
    if not current and not ok and (st == "available" or st == "log") then
      current = i
    end
  end
  if not current then
    for i, ok in ipairs(oks) do
      if not ok and states[i] ~= "never" then
        current = i
        break
      end
    end
  end
  local head
  if #steps > 0 and done == #steps then
    head = L["The whole chain is done."]
  elseif current then
    head = string.format(L["Step %d of %d. Next: %s"], current, #steps, stepName(steps[current]))
  else
    head = L["Nothing of it is for this character."]
  end
  local rows = { { id = key .. ":head", kind = "para", text = C.grey .. head .. "|r" } }
  for i, step in ipairs(steps) do
    local st = states[i]
    local words, color = stateWords(st, step.id, missing[i], pos)
    local row
    if step.kind == "quest" then
      row = R.quest(step.id, state, {
        status = st,
        zone = true,
        map = opts.map,
        where = key .. i,
        title = Logic.quest(step.id) and nil or step.label,
      })
    elseif step.kind == "item" then
      row = {
        ref = "item:" .. step.id,
        text = B.UI.Icon(oks[i] and "done" or "waiting") .. C.white .. (step.label or "") .. "|r",
      }
      words = oks[i] and L["in your bags"] or L["not in your bags"]
    else
      local rep = ctx.rep and ctx.rep(step.id) or nil
      local now = rep and L[R.STANDINGS[rep.standing] or "?"] or L["unknown"]
      row = {
        text = B.UI.Icon(oks[i] and "done" or "waiting")
          .. C.white
          .. (step.label or "")
          .. ": "
          .. L[R.STANDINGS[step.standing or 6] or "?"]
          .. "|r",
      }
      words = L["now"] .. " " .. now
    end
    row.id = key .. ":" .. i
    -- the number after the state glyph, which stays first on the row (the tree reads it there)
    local glyph, rest = string.match(row.text, "^(|T[^|]*|t ?)(.*)$")
    row.text = (glyph or "")
      .. C.grey
      .. i
      .. ".|r "
      .. (glyph and rest or row.text)
      .. "  "
      .. color
      .. words
      .. "|r"
    if i == current then
      row.text = row.text .. "  " .. accent() .. L["<- you are here"] .. "|r"
      row.color = B.UI.Style.C.accent
    end
    rows[#rows + 1] = row
  end
  return rows, { total = #steps, done = done, current = current }
end

function R.section(key, title, n, children, suffix)
  return {
    id = "s:" .. key,
    kind = "section",
    key = key,
    count = n,
    title = title,
    text = accent() .. string.upper(title) .. "|r  " .. C.grey .. tostring(n or "") .. (suffix or "") .. "|r",
    children = children,
  }
end

function R.note(id, text)
  return { id = id, kind = "para", text = C.grey .. text .. "|r" }
end

-- A zone row: `onClick(map)` when given, else the zone entity's primary action.
function R.zone(map, text, onClick)
  local row = { id = "z:" .. map, ref = "zone:" .. map, map = map, text = text }
  if onClick then
    row.onClick = function()
      onClick(map)
    end
  end
  return row
end
