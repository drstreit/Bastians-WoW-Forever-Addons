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
  complete = "questActive",
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

-- The first sentence of a text, at most `max` characters, for a folded text row.
function R.firstSentence(text, max)
  max = max or 90
  local s = string.gsub(tostring(text or ""), "%$[Bb]", " ")
  s = string.gsub(s, "%s+", " ")
  s = string.match(s, "^%s*(.-)%s*$")
  if s == "" then
    return nil
  end
  local stop = string.find(s, "[%.!%?]%s")
  if stop and stop < max then
    s = string.sub(s, 1, stop)
  end
  if #s > max then
    s = string.gsub(string.sub(s, 1, max - 1), "%s+%S*$", "") .. "..."
  end
  return s
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

-- Finished and total objectives of a log entry (0, 0 without objectives).
function R.progressOf(entry)
  local total = #(entry.objectives or {})
  local done = 0
  for _, o in ipairs(entry.objectives or {}) do
    if o.finished then
      done = done + 1
    end
  end
  return done, total
end

-- "done/total" of a log entry's objectives, or "" without objectives.
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
  local ch = Logic.chain(qid, state)
  if ch then
    add(accent(), L["Chain"] .. " " .. ch.pos[qid] .. "/" .. #ch.quests)
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
  local money = q.rewards and q.rewards.money
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
    local money = q.rewards and q.rewards.money
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
      text = (o.finished and B.UI.Icon("done") or "") .. col .. tostring(o.text or "") .. "|r" .. progress,
    }
  end
  return out
end

-- ---------------------------------------------------------------------------------------------
-- Structure rows
-- ---------------------------------------------------------------------------------------------

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
