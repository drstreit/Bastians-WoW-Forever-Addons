-- Bastian's Orbiter, the round panel (voice.md §3 and §5): the hub's controls in the middle, around
-- it what can be heard and done here: the zone, the dungeon, the areas on the inner orbit; quest
-- givers with their quests as moons, bosses and readables on the outer one. Compact at rest, wide
-- while the pointer is over it, growing around its own centre; sized from the screen, moved by
-- dragging its rim, the place kept as the nearest screen corner. In a conversation (Talk.lua) the
-- same panel shows the NPC's quests and what to say. Bubbles keep their identity between renders
-- (a face is never torn down for the same creature), and a render with nothing new is skipped.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Voice = ns.Voice
local Model = Voice.Model
local SD = ns.SpokenData

local Orbit = {}
ns.Orbit = Orbit
Voice.Orbit = Orbit

local BASE, COMPACT = Voice.BASE, Voice.COMPACT
local SETTLE = 0.6 -- seconds after the pointer leaves before it shrinks
local GROW = 0.22 -- seconds of the grow and shrink
local NOTE_SECONDS = 4 -- how long a note under the hub stays
-- the cloud follows the player twice a second from 3 yards or 6 degrees on, and every bubble
-- glides to its new slot ("sliding around instead of jumping once per
-- second"; before: once a second from 10 yards or 20 degrees, placed at once)
local TICK, GLIDE = 0.5, 0.45
local MOVED_YARDS, TURNED = 3, math.rad(6)
local RING_XL = "Interface\\AddOns\\Bastians_Core\\Media\\RingXL" -- a 256 px ring with a 2 px line

-- The theme token of each kind (ADR 0017: no raw colours; the suite's type tokens).
local TOKEN = {
  zone = "typeZone",
  area = "typeZone",
  dungeon = "typeChain",
  npc = "typeNpc",
  object = "typeObject",
  quest = "typeQuest",
  boss = "bad",
  read = "typeObject",
  plus = "dim",
  act = "accent",
  say = "typeNpc",
}
-- The glyph in a bubble (B.UI.IconTexture kinds; a giver shows its face instead).
local GLYPH = {
  zone = "zone",
  area = "zone",
  dungeon = "keep",
  read = "ledger",
  object = "object",
  say = "other",
}
local STATUS_GLYPH = { available = "quest", log = "questActive", ready = "done" }
local MAX_FACES = 7

local frame, hub, progress
local byKey, free = {}, {} -- the bubbles: by the key of the item they show, and the spare ones
local shown = {} -- the bubbles drawn by the last render, in layout order
local gliding = {} -- the bubbles on their way to a new slot: [bubble] = true (Orbit.OnUpdate)
local faceCount = 0
local state = {
  k = COMPACT,
  target = COMPACT,
  wide = false,
  settle = nil,
  moving = false,
  talk = nil,
  hovering = 0,
  center = nil, -- { x, y } in UI units from the screen's bottom left
  note = nil,
  noteLeft = 0,
  signature = nil,
}
local lastPos -- { wx, wy, facing } of the last layout, for the movement check
local tick = 0

local function profile()
  local mod = Voice.mod
  return mod and mod.db and mod.db.profile or {}
end

local function data()
  return B:GetService("data")
end

local function orbitDB()
  local p = profile()
  if type(rawget(p, "orbit")) ~= "table" then
    rawset(p, "orbit", {})
  end
  return p.orbit
end

local function menuOpen()
  local m = B.UI.EntityMenuFrame and B.UI.EntityMenuFrame()
  if m and m:IsShown() then
    return true
  end
  m = B.UI.MenuFrame and B.UI.MenuFrame()
  return m ~= nil and m:IsShown()
end

-- ---------------------------------------------------------------------------------------------
-- Collecting what is around the player
-- ---------------------------------------------------------------------------------------------

local function withHeard(item)
  item.heard = item.line ~= nil and Voice.IsHeard(item.line.key) or false
  return item
end

-- The bearing and distance of an entity's first place from the player.
local function whereIs(ref, continent, wx, wy, facing)
  if not (ref and continent) then
    return nil, nil
  end
  local place = B:Entity(ref):Locations()[1]
  if not (place and place.map and place.x and place.y) then
    return nil, nil
  end
  local c, tx, ty = B.Coords.ToWorld(place.map, place.x, place.y)
  if c ~= continent then
    return nil, nil
  end
  local dx, dy = tx - wx, ty - wy
  return Model.Bearing(wx, wy, facing, tx, ty), math.sqrt(dx * dx + dy * dy)
end

-- The places: the dungeon, the zone, the area the player stands in, the zone's other areas with a
-- line (unheard first).
local function collectPlaces(uiMapID, instanceMap, instanceName)
  local places = {}
  local d = data()
  if instanceMap then
    local r = d and d:Get("dungeon", instanceMap)
    local title = r and r.name or instanceName or tostring(instanceMap)
    places[#places + 1] = withHeard({
      kind = "dungeon",
      size = "place",
      ref = r and ("dungeon:" .. instanceMap) or nil,
      title = title,
      line = Voice.DungeonLine(instanceMap, title),
      here = true,
    })
  end
  if not uiMapID then
    return places
  end
  local zoneRef = "zone:" .. uiMapID
  local zone = withHeard({
    kind = "zone",
    size = "place",
    ref = zoneRef,
    title = Voice.ZoneName(uiMapID),
    line = Voice.Line(zoneRef),
  })
  places[#places + 1] = zone
  local sub = GetSubZoneText()
  if sub == "" then
    sub = nil
  end
  local hereFound = false
  local others = {}
  if d then
    for id in d:ByZone("area", uiMapID) do
      local r = d:Get("area", id)
      local ref = "area:" .. id
      if r and r.name then
        local line = Voice.Line(ref)
        if sub and r.name == sub then
          hereFound = true
          places[#places + 1] =
            withHeard({ kind = "area", size = "here", ref = ref, title = r.name, line = line, here = true })
        elseif line then
          others[#others + 1] =
            withHeard({ kind = "area", size = "area", ref = ref, title = r.name, line = line })
        end
      end
    end
  end
  if sub and not hereFound and not instanceMap then
    -- the area the client names, with no record of ours: Spoken's key of the name finds its lore
    local key = Model.AreaKey(sub)
    local clip = SD.AreaClip(uiMapID, key)
    places[#places + 1] = withHeard({
      kind = "area",
      size = "here",
      title = sub,
      line = clip and {
        kind = "area",
        key = Model.Key("area", uiMapID, key),
        title = sub,
        clip = clip,
        mapID = uiMapID,
      } or nil,
      here = true,
    })
  end
  zone.here = not instanceMap and not sub -- no area named: the zone is where the player stands
  Model.Order(others)
  for _, o in ipairs(others) do
    places[#places + 1] = o
  end
  return places
end

-- The zone a quest's hand-in NPC stands in, or nil.
local function enderZone(d, q)
  local ref = q.ends and q.ends[1]
  if type(ref) ~= "string" then
    return nil
  end
  local typ, id = B.Entity.Parse(ref)
  local r = typ == "npc" and d:Get("npc", id)
  return r and r.zone or nil
end

-- The quest givers of the zone with their quests (in the log, ready to hand in, to take), each
-- giver at its bearing from the player.
local function collectGivers(uiMapID, continent, wx, wy, facing)
  local d = data()
  if not (d and uiMapID) then
    return {}
  end
  local level = UnitLevel("player")
  local log = {}
  for _, e in ipairs(B.Compat.GetQuestLogEntries() or {}) do
    if e.questID then
      log[e.questID] = e
    end
  end
  local givers, order = {}, {}
  local function add(questID, status)
    local q = d:Get("quest", questID)
    if not q then
      return
    end
    local giverRef = status == "ready" and q.ends and q.ends[1] or q.starts and q.starts[1]
    if type(giverRef) ~= "string" then
      return
    end
    local typ, id = B.Entity.Parse(giverRef)
    if typ ~= "npc" and typ ~= "object" then
      return
    end
    local giver = givers[giverRef]
    if not giver then
      local bearing, distance = whereIs(giverRef, continent, wx, wy, facing)
      giver = {
        kind = typ,
        size = "giver",
        ref = giverRef,
        title = B:Entity(giverRef):Name() or giverRef,
        creature = typ == "npc" and id or nil,
        bearing = bearing,
        distance = distance,
        quests = {},
      }
      givers[giverRef] = giver
      order[#order + 1] = giver
    end
    local ref = "quest:" .. questID
    giver.quests[#giver.quests + 1] = withHeard({
      kind = "quest",
      ref = ref,
      title = q.name or B:Entity(ref):Name() or ref,
      status = status,
      line = Voice.Line(ref),
      questID = questID,
    })
  end
  local seen = {}
  for id, e in pairs(log) do
    local q = d:Get("quest", id)
    if q and (q.zone == uiMapID or enderZone(d, q) == uiMapID) then
      seen[id] = true
      add(id, Model.QuestStatus(q, e, false, level))
    end
  end
  for _, id in ipairs(d:Index("quest.byZone", uiMapID) or {}) do
    if not seen[id] and not log[id] then
      local q = d:Get("quest", id)
      local status = Model.QuestStatus(q, nil, B.Compat.IsQuestCompleted(id), level)
      if status then
        add(id, status)
      end
    end
  end
  for _, giver in ipairs(order) do
    Model.Order(giver.quests)
    giver.status = giver.quests[1] and giver.quests[1].status or nil
  end
  return order
end

-- The bosses of the instance (their stories) and the readables Spoken lists for the zone.
local function collectOthers(uiMapID, instanceMap)
  local out = {}
  if instanceMap then
    for _, boss in ipairs(SD.BossesOf(instanceMap)) do
      local ref = boss.creature and ("npc:" .. boss.creature) or nil
      local line = ref and Voice.Line(ref)
      if not line then
        line = {
          kind = "boss",
          key = Model.Key("boss", boss.map, boss.key),
          title = SD.BossName(boss),
          textOnly = true,
          story = boss.story,
          creature = boss.creature,
          display = boss.display,
          map = boss.map,
        }
      end
      out[#out + 1] =
        withHeard({ kind = "boss", ref = ref, title = line.title, line = line, creature = boss.creature })
    end
  end
  if uiMapID then
    for _, book in ipairs(SD.ReadablesIn(uiMapID)) do
      local line = Voice.BookLine(book.bookId, book.title)
      if line then
        out[#out + 1] = withHeard({ kind = "read", title = book.title, line = line })
      end
    end
  end
  return out
end

-- Everything the orbit shows now: places, outer. Pure data for the renderer and the tests.
function Orbit.Collect()
  local continent, wx, wy, uiMapID = B.Coords.Player()
  local facing = B.Compat.GetPlayerFacing()
  local instanceMap, instanceName = B.Compat.InstanceMap()
  local places = collectPlaces(uiMapID, instanceMap, instanceName)
  local outer = collectGivers(uiMapID, continent, wx, wy, facing)
  for _, o in ipairs(collectOthers(uiMapID, instanceMap)) do
    outer[#outer + 1] = o
  end
  Model.Order(outer)
  lastPos = { wx = wx, wy = wy, facing = facing }
  return places, outer
end

-- ---------------------------------------------------------------------------------------------
-- The frame
-- ---------------------------------------------------------------------------------------------

local function token(name)
  return S.C[name] or S.C.text
end

local function disc(parent, color, alpha, layer)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetTexture(S.DISC)
  t:SetAllPoints()
  S.tint(t, color, alpha)
  return t
end

local function ring(parent, color, alpha, layer, texture)
  local t = parent:CreateTexture(nil, layer or "BORDER")
  t:SetTexture(texture or S.RINGS.M)
  t:SetAllPoints()
  S.tint(t, color, alpha)
  return t
end

-- A glyph of the suite's set, white, tinted by a token.
local function glyph(parent, kind, size, color, layer)
  local t = parent:CreateTexture(nil, layer or "OVERLAY")
  t:SetTexture(B.UI.GLYPH_PATHS[kind] or B.UI.IconTexture(kind))
  t:SetSize(size, size)
  S.tint(t, color or S.C.text)
  t.kind = kind
  return t
end

local KIND_WORDS = {
  zone = "Zone lore",
  area = "Area lore",
  dungeon = "Dungeon story",
  npc = "Quest giver",
  object = "Quest giver",
  quest = "Quest",
  boss = "Boss story",
  read = "Readable",
  act = "Answer",
  say = "Say",
}

local TIP_ROWS = 8 -- tooltip rows of a quest (the chain, money, reputation, items) at most
local TIP_QUESTS = 3 -- quests a giver's tooltip details; the rest as "... and n more"

local function tip(bubble)
  local item = bubble.item
  -- a quest mark shows the quest sheet beside the ring (ADR 0053), the tooltip stays without it
  local sheet = item and item.kind == "quest" and item.ref and B:GetService("questSheet")
  if sheet then
    state.sheetShown = sheet
    -- on the side with room: the ring can stand anywhere
    local side = state.center and state.center.x > UIParent:GetWidth() / 2 and "LEFT" or "RIGHT"
    sheet:Preview(item.ref, { anchor = frame, side = side, title = item.title, detail = item.detail })
    return
  end
  if not (item and GameTooltip) then
    return
  end
  GameTooltip:SetOwner(bubble, "ANCHOR_RIGHT")
  -- a reward says what it is: the game's whole item tooltip
  if item.itemID and GameTooltip.SetItemByID then
    GameTooltip:SetItemByID(item.itemID)
    if item.hint then
      S.TipLine(GameTooltip, item.hint, "tipDim")
    end
    GameTooltip:Show()
    return
  end
  S.TipLine(GameTooltip, item.title or "?", "tipText")
  local words = KIND_WORDS[item.kind] and L[KIND_WORDS[item.kind]] or nil
  if item.kind == "quest" then
    local status = { available = L["To take"], log = L["In your log"], ready = L["Ready to hand in"] }
    words = status[item.status] or words
    if item.giver then
      words = words .. ", " .. item.giver
    end
  end
  if words then
    S.TipLine(GameTooltip, words, "tipGold")
  end
  -- what the quest earns and where it sits in its chain (the marks
  -- showed no reward): Quests' tooltip rows through Core, on a moon and under a giver's quests
  if item.kind == "quest" and item.ref and B.UI.TipRows then
    B.UI.TipRows(GameTooltip, item.ref, TIP_ROWS)
  end
  if item.quests then
    local lines = 0
    for _, q in ipairs(item.quests) do
      if q.line then
        lines = lines + 1
      end
    end
    S.TipLine(GameTooltip, string.format(L["%d quests, %d with a voice line"], #item.quests, lines), "tipDim")
    if lines > 0 then
      S.TipLine(GameTooltip, L["Click plays the first unheard line"], "tipDim")
    end
    local status = { available = L["To take"], log = L["In your log"], ready = L["Ready to hand in"] }
    for i, q in ipairs(item.quests) do
      if i > TIP_QUESTS then
        S.TipLine(GameTooltip, string.format(L["... and %d more"], #item.quests - TIP_QUESTS), "tipDim")
        break
      end
      GameTooltip:AddLine(" ")
      S.TipLine(
        GameTooltip,
        (q.title or "?") .. (status[q.status] and (", " .. status[q.status]) or ""),
        "tipText"
      )
      if q.ref and B.UI.TipRows then
        B.UI.TipRows(GameTooltip, q.ref, TIP_ROWS)
      end
    end
  end
  if item.distance then
    S.TipLine(GameTooltip, B.UI.Distance(item.distance), "tipDim")
  end
  if item.line then
    local clip = item.line.clip or (item.line.pages and item.line.pages[1])
    if item.line.tts then
      S.TipLine(GameTooltip, L["Read by the game's voice (no Spoken line)"], "tipDim")
    elseif item.line.textOnly then
      S.TipLine(GameTooltip, L["Text in Spoken's narrator"], "tipDim")
    elseif clip and clip.length then
      S.TipLine(GameTooltip, string.format(L["Voice line, %s"], B.UI.Duration(clip.length)), "tipDim")
    else
      S.TipLine(GameTooltip, L["Voice line"], "tipDim")
    end
    S.TipLine(GameTooltip, item.heard and L["Heard"] or L["Not heard yet"], "tipDim")
  elseif item.kind == "quest" or item.kind == "zone" or item.kind == "area" or item.kind == "boss" then
    S.TipLine(
      GameTooltip,
      SD.Spoken() and L["No voice line in the installed packs"] or L["Spoken is not installed"],
      "tipDim"
    )
  end
  if item.hint then
    S.TipLine(GameTooltip, item.hint, "tipDim")
  elseif item.line then
    S.TipLine(GameTooltip, L["Click plays, Shift-click queues, right click for more"], "tipDim")
  elseif item.ref then
    S.TipLine(GameTooltip, L["Right click for more"], "tipDim")
  end
  GameTooltip:Show()
end

local function hideTip()
  if state.sheetShown then
    state.sheetShown:EndPreview()
    state.sheetShown = nil
  end
  if GameTooltip then
    GameTooltip:Hide()
  end
end

-- The lock on the hub: whether the ring can be dragged. The same switch as "Lock the position"
-- in the options.
function Orbit.ToggleLock()
  local p = profile()
  p.lock = not p.lock
  Orbit.Note(p.lock and L["Locked in place"] or L["Moves freely"])
end

-- A note under the hub for a few seconds (what a click did, why nothing plays).
function Orbit.Note(text)
  state.note, state.noteLeft = text, NOTE_SECONDS
  Orbit.RefreshHub()
end

-- A face: Spoken's round speaker face where the player has it, else our own model under a ring.
-- The same creature on the same bubble keeps its face (no flicker on a render).
local function face(bubble, creature)
  local f = bubble.face
  if not f then
    local Spoken = SD.Spoken()
    if Spoken and Spoken.CreateSpeakerFace then
      f = Spoken:CreateSpeakerFace(bubble, bubble:GetWidth())
      f.spoken = true
    else
      f = CreateFrame("PlayerModel", nil, bubble)
      f.ringOver = ring(f, token("typeNpc"), 1, "OVERLAY")
    end
    f:SetPoint("CENTER")
    bubble.face = f
  end
  f:SetSize(bubble:GetWidth(), bubble:GetHeight())
  if f.shownCreature ~= creature then
    if f.spoken then
      f:SetSpeaker({ creatureID = creature })
    else
      f:SetCreature(creature)
    end
    f.shownCreature = creature
  end
  if not f:IsShown() then
    f:Show()
  end
  faceCount = faceCount + 1
end

local function onBubbleClick(bubble, button)
  local item = bubble.item
  if not item then
    return
  end
  if button == "RightButton" then
    if item.ref then
      B.UI.EntityMenu(item.ref, bubble, { source = "voice" })
    end
    return
  end
  hideTip()
  if item.onClick then
    item.onClick(item)
    return
  end
  local queue = B.Compat.ModifierDown("shift")
  local target = item
  if item.quests then
    target = nil
    for _, q in ipairs(item.quests) do
      if q.line and not q.heard then
        target = q
        break
      end
    end
    if not target then
      for _, q in ipairs(item.quests) do
        if q.line then
          target = q
          break
        end
      end
    end
    if not target then
      Orbit.Note(string.format(L["%s: no voice line for these quests"], item.title or "?"))
      return
    end
  end
  if not target.line then
    if not SD.Spoken() and not Voice.TtsOn() then
      Orbit.Note(L["Spoken is not installed: nothing to play"])
    else
      Orbit.Note(string.format(L["%s: no voice line in the installed packs"], target.title or "?"))
    end
    return
  end
  if Voice.Playing(target.line) then
    Voice.Stop(target.line)
    Orbit.Note(string.format(L["Stopped: %s"], target.title or "?"))
  else
    local ok, why = Voice.Play(target.line, queue)
    if ok then
      Orbit.Note(string.format(queue and L["Queued: %s"] or L["Playing: %s"], target.title or "?"))
    elseif why == "refused" then
      Orbit.Note(L["Spoken did not take the line"])
    else
      Orbit.Note(string.format(L["%s: no voice line in the installed packs"], target.title or "?"))
    end
  end
  Orbit.Refresh()
end

local function newBubble()
  local b = CreateFrame("Button", nil, frame)
  b.disc = disc(b, S.C.panel, 0.9)
  b.fill = disc(b, S.C.text, 0.22, "BORDER")
  b.ring = ring(b, S.C.line, 1, "ARTWORK")
  b.glyph = b:CreateTexture(nil, "OVERLAY")
  b.glyph:SetPoint("CENTER")
  b.label = S.text(b, 11, S.C.text)
  b.label:SetPoint("CENTER")
  b.label:SetJustifyH("CENTER")
  b.badge = S.text(b, 10, S.C.text)
  b.badge:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
  b.mark = glyph(b, "voice", 10, S.C.accent, "OVERLAY") -- "has a voice line"
  b.mark:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", -2, -2)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", onBubbleClick)
  b:SetScript("OnEnter", function(self)
    Orbit.Hover(true)
    tip(self)
  end)
  b:SetScript("OnLeave", function()
    Orbit.Hover(false)
    hideTip()
  end)
  return b
end

-- The key a bubble is kept under between renders.
local function itemKey(item)
  return item.ref or (item.line and item.line.key) or (tostring(item.kind) .. ":" .. tostring(item.title))
end

local function paint(b, item, playing)
  local kind = item.kind == "quest" and "quest" or item.kind
  local color = token(TOKEN[kind] or "text")
  local hasLine = item.line ~= nil
  -- what plays or was chosen is unmistakable ("it needs to be very
  -- clear what is active - coloured"): the bubble filled with the accent, a bright ring, its
  -- mark and words in the ground colour
  local active = (playing or item.chosen) and true or false
  b.active = active
  if active then
    S.tint(b.fill, S.C.accent, 0.9)
    S.tint(b.ring, S.C.bright, 1)
  else
    S.tint(b.fill, color, item.kind == "act" and 1 or (hasLine and 0.3 or 0.14))
    S.tint(b.ring, color, 1)
  end
  b.ring:SetDesaturated(item.heard and not active and true or false)
  local dim = (item.heard or item.disabled) and not active
  local silent = not hasLine and (item.kind == "quest" or item.kind == "zone" or item.kind == "area")
  b:SetAlpha(dim and 0.5 or (silent and 0.6 or 1))
  S.ink(b.label, active and S.C.bg or (item.kind == "act" and S.C.bright or S.C.text))
  if hasLine and not item.heard then
    b.mark:SetTexture(B.UI.GLYPH_PATHS.voice)
    -- Spoken's line in full colour, the game's voice (text to speech) dimmer
    S.tint(b.mark, active and S.C.bg or (item.line.tts and S.C.dim or S.C.text))
    b.mark:Show()
  elseif hasLine and item.heard then
    b.mark:SetTexture(B.UI.GLYPH_PATHS.done)
    S.tint(b.mark, active and S.C.bg or S.C.dim)
    b.mark:Show()
  else
    b.mark:Hide()
  end
end

-- Puts a bubble at its slot: at once when it is new to the orbit, gliding from where it stands
-- when it moves (Orbit.OnUpdate advances the glide with an ease out).
-- A conversation's words sit outside their bubble, away from the hub (
-- "the dialog options are overlapping"): left of a bubble on the left, right of one on the right,
-- above or below at the top and bottom, wrapped at LABEL_WIDTH. Every other label stays centred.
local LABEL_WIDTH = 240
local function anchorLabel(b, x, y, outward)
  local label = b.label
  label:ClearAllPoints()
  if not outward then
    label:SetWidth(0)
    label:SetWordWrap(false)
    label:SetPoint("CENTER")
    label:SetJustifyH("CENTER")
    return
  end
  label:SetWidth(LABEL_WIDTH)
  label:SetWordWrap(true)
  if x < -30 then
    label:SetPoint("RIGHT", b, "LEFT", -4, 0)
    label:SetJustifyH("RIGHT")
  elseif x > 30 then
    label:SetPoint("LEFT", b, "RIGHT", 4, 0)
    label:SetJustifyH("LEFT")
  elseif y >= 0 then
    label:SetPoint("BOTTOM", b, "TOP", 0, 2)
    label:SetJustifyH("CENTER")
  else
    label:SetPoint("TOP", b, "BOTTOM", 0, -2)
    label:SetJustifyH("CENTER")
  end
end

local function place(b, x, y)
  if b.cx ~= nil and b:IsShown() and math.abs(b.cx - x) + math.abs(b.cy - y) > 0.5 then
    b.fx, b.fy, b.tx, b.ty, b.glide = b.cx, b.cy, x, y, 0
    gliding[b] = true
    return
  end
  gliding[b] = nil
  b.cx, b.cy = x, y
  b:ClearAllPoints()
  b:SetPoint("CENTER", frame, "CENTER", x, y)
end

-- How many bubbles are gliding right now (tests).
function Orbit.Gliding()
  local n = 0
  for _ in pairs(gliding) do
    n = n + 1
  end
  return n
end

local function bubble(item, x, y, r, playing)
  local key = itemKey(item)
  local b = byKey[key]
  if not b then
    b = table.remove(free) or newBubble()
    byKey[key] = b
    b.key = key
  end
  b.item = item
  local size = r * 2
  b:SetSize(size, size)
  place(b, x, y)
  b.mark:SetSize(math.max(8, size * 0.38), math.max(8, size * 0.38))
  paint(b, item, playing)
  b.glyph:Hide()
  b.label:Hide()
  b.badge:Hide()
  local wantsFace = (item.kind == "npc" or item.kind == "object") and item.creature and faceCount < MAX_FACES
  if b.face and (not wantsFace or b.face.shownCreature ~= item.creature) then
    b.face:Hide()
  end
  local g = item.kind == "quest" and STATUS_GLYPH[item.status] or GLYPH[item.kind]
  if item.kind == "boss" then
    g = B.UI.MobKind()
  end
  if wantsFace then
    face(b, item.creature)
  elseif item.kind == "npc" or item.kind == "object" then
    local icon = item.ref and B:Entity(item.ref):Icon() or nil
    b.glyph:SetTexture(icon or B.UI.IconTexture(item.index and "item" or "service"))
    b.glyph:SetSize(size * 0.7, size * 0.7)
    b.glyph:Show()
  elseif (item.kind == "act" or item.kind == "say") and item.glyph then
    -- an answer as a symbol;
    -- its words are the tooltip's
    b.glyph:SetTexture(B.UI.GLYPH_PATHS[item.glyph])
    S.tint(b.glyph, item.kind == "act" and S.C.bg or S.C.text)
    b.glyph:SetSize(size * 0.6, size * 0.6)
    b.glyph:Show()
  elseif item.kind == "act" or item.kind == "say" or item.kind == "plus" then
    b.label:SetText(item.label or item.title) -- its ink is paint's (the active one reads in bg)
    anchorLabel(b, x, y, state.talk ~= nil and item.kind == "say")
    b.label:Show()
  elseif g then
    b.glyph:SetTexture(B.UI.IconTexture(g))
    b.glyph:SetSize(size * 0.75, size * 0.75)
    b.glyph:Show()
  end
  if item.more and item.more > 0 then
    b.badge:SetText("+" .. item.more)
    b.badge:Show()
  elseif item.quests and not state.wide then
    b.badge:SetText(tostring(#item.quests))
    b.badge:Show()
  end
  if not b:IsShown() then
    b:Show()
  end
  shown[#shown + 1] = b
  b.used = true
  return b
end

-- A round button with one of the suite's glyphs (the hub's controls).
local function iconButton(kind, size, run, tipText)
  local b = CreateFrame("Button", nil, hub)
  b:SetFrameLevel(hub:GetFrameLevel() + 4) -- above the creature's picture
  b:SetSize(size, size)
  b.disc = disc(b, S.C.panel, 1)
  b.ring = ring(b, S.C.line, 1, "BORDER", S.RingFor(size / 2))
  b.glyph = glyph(b, kind, size * 0.62, S.C.text)
  b.glyph:SetPoint("CENTER")
  b.tip = tipText
  b.kind = kind
  function b.SetGlyph(self, k)
    if self.kind ~= k then
      self.kind = k
      self.glyph:SetTexture(B.UI.GLYPH_PATHS[k] or B.UI.IconTexture(k))
      self.glyph.kind = k
    end
  end
  b:SetScript("OnClick", function()
    hideTip()
    run()
    Orbit.Refresh()
  end)
  b:SetScript("OnEnter", function(self)
    Orbit.Hover(true)
    S.tint(self.disc, S.C.faceHover)
    S.TipEnter(self)
  end)
  b:SetScript("OnLeave", function(self)
    Orbit.Hover(false)
    S.tint(self.disc, S.C.panel)
    S.TipLeave(self)
  end)
  return b
end

local function build()
  frame = CreateFrame("Frame", "BastiansVoiceOrbit", UIParent)
  frame:SetSize(BASE, BASE)
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame.innerRing = ring(frame, S.C.line, 0.6, "BACKGROUND", RING_XL)
  frame.innerRing:ClearAllPoints()
  frame.innerRing:SetPoint("CENTER")
  frame.innerRing:SetSize(Voice.RADII.inner * 2, Voice.RADII.inner * 2)
  frame.outerRing = ring(frame, S.C.line, 0.6, "BACKGROUND", RING_XL)
  frame.outerRing:ClearAllPoints()
  frame.outerRing:SetPoint("CENTER")
  frame.outerRing:SetSize(Voice.RADII.outer * 2, Voice.RADII.outer * 2)
  -- ~~the facing arrow above the ring~~ removed ("I don't understand
  -- its meaning, remove it"); up is still where the player faces, the bearings say so
  frame:SetScript("OnEnter", function()
    Orbit.Hover(true)
  end)
  frame:SetScript("OnLeave", function()
    Orbit.Hover(false)
  end)
  frame:SetScript("OnDragStart", function(self)
    if profile().lock then
      -- a locked ring says so ("I cannot move the orbiter anymore";
      -- the profile held lock = true and nothing on the screen said it)
      Orbit.Note(L["Locked in place. The lock on the ring unlocks it."])
      return
    end
    self:StartMoving()
    state.dragging = true
  end)
  frame:SetScript("OnDragStop", function(self)
    if not state.dragging then
      return
    end
    self:StopMovingOrSizing()
    state.dragging = false
    Orbit.SavePlace()
  end)
  frame:SetScript("OnUpdate", function(_, dt)
    Orbit.OnUpdate(dt or 0)
  end)
  frame:SetScript("OnHide", function()
    state.wide, state.k, state.target = false, COMPACT, COMPACT
  end)

  hub = CreateFrame("Frame", nil, frame)
  hub:SetSize(Voice.RADII.hub * 2 + 10, Voice.RADII.hub * 2 + 10)
  hub:SetPoint("CENTER")
  -- the hub drags the panel too ("when left clicking into the middle,
  -- outside the sound play buttons, its draggable"); its buttons take their clicks first
  hub:EnableMouse(true)
  hub:RegisterForDrag("LeftButton")
  hub:SetScript("OnDragStart", function()
    frame:GetScript("OnDragStart")(frame)
  end)
  hub:SetScript("OnDragStop", function()
    frame:GetScript("OnDragStop")(frame)
  end)
  hub:SetScript("OnEnter", function()
    Orbit.Hover(true)
  end)
  hub:SetScript("OnLeave", function()
    Orbit.Hover(false)
  end)
  hub.disc = disc(hub, S.C.panel, 0.98)
  hub.ring = ring(hub, S.C.line, 1, "BORDER", RING_XL)
  progress = CreateFrame("Cooldown", nil, hub, "CooldownFrameTemplate")
  progress:SetAllPoints(hub)
  progress:EnableMouse(false)
  if progress.SetDrawEdge then
    progress:SetDrawEdge(false)
  end
  if progress.SetDrawBling then
    progress:SetDrawBling(false)
  end
  if progress.SetHideCountdownNumbers then
    progress:SetHideCountdownNumbers(true)
  end
  if progress.SetReverse then
    progress:SetReverse(true)
  end
  if progress.SetSwipeColor then
    local c = S.C.accent
    progress:SetSwipeColor(c[1], c[2], c[3], 0.45)
  end
  hub.face = CreateFrame("Frame", nil, hub)
  hub.face:SetPoint("CENTER")
  hub.face:SetSize(Voice.RADII.hub * 2 - 6, Voice.RADII.hub * 2 - 6)
  hub.face:SetAlpha(0.6)
  hub.face:EnableMouse(false) -- the creature is a picture: the hub drags, the buttons click
  hub.face:SetFrameLevel(hub:GetFrameLevel() + 1)
  hub.face:Hide()
  hub.play = iconButton("play", 30, function()
    if Voice.Now() then
      Voice.TogglePause()
    else
      Orbit.SetWide(not state.wide)
    end
  end, L["Play or pause"])
  hub.play:SetPoint("CENTER")
  local d, dy = 21, 13
  hub.restart = iconButton("replay", 16, Voice.Restart, L["Jump to start"])
  hub.restart:SetPoint("CENTER", hub, "CENTER", -d, dy)
  hub.stop = iconButton("stop", 16, Voice.StopAll, L["Stop"])
  hub.stop:SetPoint("CENTER", hub, "CENTER", d, dy)
  hub.heard = iconButton("done", 16, function()
    local now = Voice.Now()
    if now and now.key then
      Voice.MarkHeard(now.key)
      Voice.StopAll()
      Orbit.Note(string.format(L["Marked heard: %s"], now.title or "?"))
    end
  end, L["Mark heard"])
  hub.heard:SetPoint("CENTER", hub, "CENTER", -d, -dy)
  hub.open = iconButton("open", 16, function()
    if state.talk then
      ns.Talk.ShowGameWindow()
      return
    end
    local now = Voice.Now()
    local ref = now and now.clip and now.clip.ref
    if ref and B:GetAction("browser.open") then
      B:RunAction("browser.open", ref, { source = "voice" })
    end
  end, L["Open in Browser"])
  hub.open:SetPoint("CENTER", hub, "CENTER", d, -dy)
  -- the lock ("a small lock symbol in Orbiter to toggle the ability to move it
  -- freely around"): under the play button, lit while the ring is locked in place
  hub.lock = iconButton("lock", 14, Orbit.ToggleLock, function()
    if profile().lock then
      return L["Locked in place"], L["Click to move the Orbiter freely."]
    end
    return L["Moves freely"], L["Drag the Orbiter where you want it. Click to lock it in place."]
  end)
  hub.lock:SetPoint("CENTER", hub, "CENTER", 0, -(Voice.RADII.hub - 7))
  hub.name = S.text(frame, 11, S.C.text)
  hub.name:SetPoint("TOP", hub, "BOTTOM", 0, -2)
  hub.name:SetJustifyH("CENTER")
  hub.name:SetWidth(Voice.RADII.inner * 2 - 16)
  hub.name:SetWordWrap(false)
  Orbit.frame, Orbit.hub = frame, hub
  frame:Hide()
end

-- ---------------------------------------------------------------------------------------------
-- Compact and wide, place and size (voice.md §5)
-- ---------------------------------------------------------------------------------------------

-- Keeps the centre where it is: the point is set again for the frame's scale.
local function placeAt()
  if not (frame and state.center) then
    return
  end
  local scale = frame:GetScale()
  frame:ClearAllPoints()
  frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", state.center.x / scale, state.center.y / scale)
end

-- The frame's scale: the auto size for the screen and the setting, times compact or wide; the
-- centre stays put.
function Orbit.ApplyScale()
  if not frame then
    return
  end
  local wide = Model.Size(UIParent:GetHeight(), profile().scale)
  frame:SetScale(wide / BASE * state.k)
  placeAt()
end

-- The presets, as shares of the screen (the wide orbit is 0.36 of its height across).
local PRESETS = {
  topright = function(w, h)
    return w - 0.22 * h, h - 0.26 * h
  end,
  bottomright = function(w, h)
    return w - 0.22 * h, 0.24 * h
  end,
  bottomcenter = function(w, h)
    return w / 2, 0.24 * h
  end,
}

-- Puts the panel where the profile says: a saved corner and offset, else the anchor preset.
function Orbit.ApplyPlace()
  if not frame then
    return
  end
  local db = orbitDB()
  local w, h = UIParent:GetWidth(), UIParent:GetHeight()
  local cx, cy
  if db.corner then
    cx, cy = Model.Place(db.corner, db.dx, db.dy, w, h)
  else
    local preset = PRESETS[profile().anchor or "topright"] or PRESETS.topright
    cx, cy = preset(w, h)
  end
  state.center = { x = cx, y = cy }
  placeAt()
end

-- Remembers the centre as the nearest corner plus an offset in UI units.
function Orbit.SavePlace()
  if not frame then
    return
  end
  local cx, cy = frame:GetCenter()
  if not cx then
    return
  end
  local scale = frame:GetScale()
  cx, cy = cx * scale, cy * scale
  local corner, dx, dy = Model.Corner(cx, cy, UIParent:GetWidth(), UIParent:GetHeight())
  local db = orbitDB()
  db.corner, db.dx, db.dy = corner, dx, dy
  Orbit.ApplyPlace()
end

function Orbit.ResetPlace()
  local db = orbitDB()
  db.corner, db.dx, db.dy = nil, nil, nil
  Orbit.ApplyPlace()
end

function Orbit.Center()
  return state.center
end

local function pointerOver()
  return state.hovering > 0
end

-- The pointer entered (true) or left (false) the panel or one of its bubbles.
function Orbit.Hover(entering)
  if entering then
    state.hovering = state.hovering + 1
    state.settle = nil
    if profile().hoverWide ~= false then
      Orbit.SetWide(true)
    end
  else
    state.hovering = math.max(0, state.hovering - 1)
    if state.hovering == 0 and not state.talk then
      state.settle = SETTLE
    end
  end
end

-- Grows or shrinks around the centre.
function Orbit.SetWide(on)
  state.wide = on and true or false
  state.target = on and 1 or COMPACT
  state.settle = nil
  if state.k ~= state.target then
    state.moving = true
  end
  if frame and frame:IsShown() then
    Orbit.Render(true)
  end
end

function Orbit.IsWide()
  return state.wide
end

function Orbit.OnUpdate(dt)
  if state.settle then
    state.settle = state.settle - dt
    if state.settle <= 0 then
      state.settle = nil
      if pointerOver() or menuOpen() then
        state.settle = SETTLE -- not yet: the menu or the pointer is still there
      else
        Orbit.SetWide(false)
      end
    end
  end
  if state.moving then
    local step = (1 - COMPACT) / GROW * dt
    if state.k < state.target then
      state.k = math.min(state.target, state.k + step)
    else
      state.k = math.max(state.target, state.k - step)
    end
    if state.k == state.target then
      state.moving = false
    end
    Orbit.ApplyScale()
  end
  if state.note then
    state.noteLeft = state.noteLeft - dt
    if state.noteLeft <= 0 then
      state.note = nil
      Orbit.RefreshHub()
    end
  end
  for b in pairs(gliding) do
    b.glide = math.min(1, b.glide + dt / GLIDE)
    local e = 1 - (1 - b.glide) ^ 3 -- ease out: quick off the mark, soft into the slot
    b.cx, b.cy = b.fx + (b.tx - b.fx) * e, b.fy + (b.ty - b.fy) * e
    b:ClearAllPoints()
    b:SetPoint("CENTER", frame, "CENTER", b.cx, b.cy)
    if b.glide >= 1 then
      gliding[b] = nil
    end
  end
  tick = tick + dt
  if tick >= TICK then
    tick = 0
    Orbit.Tick()
  elseif Voice.Now() and tick % 0.25 < dt then
    Orbit.RefreshHub()
  end
end

-- Twice a second while shown: a move of MOVED_YARDS or a turn of TURNED lays the cloud out again
-- and the bubbles glide to their new slots (never while a menu is open: the pointer is there).
function Orbit.Tick()
  if state.talk or InCombatLockdown() or menuOpen() then
    return
  end
  local _, wx, wy = B.Coords.Player()
  local facing = B.Compat.GetPlayerFacing()
  local last = lastPos
  local moved = false
  if last and wx and last.wx then
    local dx, dy = wx - last.wx, wy - last.wy
    moved = (dx * dx + dy * dy) >= MOVED_YARDS * MOVED_YARDS
  elseif last and (wx == nil) ~= (last.wx == nil) then
    moved = true
  end
  if facing and last and last.facing and math.abs(facing - last.facing) >= TURNED then
    moved = true
  end
  if moved then
    Orbit.Render()
  else
    Orbit.RefreshHub()
  end
end

-- ---------------------------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------------------------

-- The targeted player's roleplay name and title (Total RP 3, MyRolePlay: msp through Core, read
-- only; plan-launch-version L3), or nil; a missing profile is asked for.
function Orbit.RoleplayLine()
  if not (UnitExists("target") and UnitIsPlayer("target")) or UnitIsUnit("target", "player") then
    return nil
  end
  local rp = B.Compat.MspName("target")
  if not rp then
    B.Compat.MspRequest("target")
    return nil
  end
  return rp.title and (rp.name .. ", " .. rp.title) or rp.name
end

-- The hub: the play button's glyph, the progress ring, the line under the hub, the side buttons.
function Orbit.RefreshHub()
  if not hub then
    return
  end
  local now = Voice.Now()
  local on = now ~= nil
  hub.play:SetGlyph(on and not now.paused and "pause" or "play")
  for _, name in ipairs({ "restart", "stop", "heard", "open" }) do
    local b = hub[name]
    local show = state.wide
    if name == "open" then
      show = show and (state.talk ~= nil or B:GetAction("browser.open") ~= nil)
    end
    b:SetShown(show)
    local enabled = on or (name == "open" and state.talk ~= nil)
    b:SetAlpha(enabled and 1 or 0.35)
  end
  local locked = profile().lock == true
  hub.lock:SetShown(state.wide)
  S.tint(hub.lock.glyph, locked and S.C.accent or S.C.dim)
  hub.lock.locked = locked
  if progress then
    if on and now.progress and now.clip.length then
      local len = now.clip.length
      progress:SetCooldown(GetTime() - now.progress * len, len)
    else
      progress:Clear()
    end
  end
  local text
  if state.note then
    text = state.note
  elseif state.talk then
    text = state.talk.npc and state.talk.npc.name or ""
  elseif on then
    text = (now.paused and L["Paused: %s"] or L["Playing: %s"]):format(now.title or "")
  elseif Orbit.RoleplayLine() then
    text = Orbit.RoleplayLine()
  elseif not SD.Spoken() then
    text = S.H.muted .. Voice.NoSpokenNote() .. "|r"
  else
    text = ""
  end
  hub.name:SetText(text)
  hub.name:SetShown(text ~= "")
end

local function hubFace(creature)
  local f = hub.face
  if creature then
    if not f.model then
      f.model = CreateFrame("PlayerModel", nil, f)
      f.model:SetAllPoints(f)
      -- under the controls and never in the way of the mouse ("the NPC
      -- 3d is above the play controls - they are not clickable"; the drag by the hub too)
      f.model:EnableMouse(false)
      f.model:SetFrameLevel(f:GetFrameLevel())
    end
    if f.model.shownCreature ~= creature then
      f.model:SetCreature(creature)
      f.model.shownCreature = creature
    end
    if not f:IsShown() then
      f:Show()
    end
  elseif f:IsShown() then
    f:Hide()
  end
end

-- What a layout would draw, as one string: a render with the same one is skipped.
local function signature(layout)
  local parts = { state.wide and "w" or "c", state.talk and "t" or "" }
  for _, slot in ipairs(layout) do
    local item = slot.item
    parts[#parts + 1] = table.concat({
      itemKey(item),
      tostring(item.status),
      item.line and "l" or "-",
      item.heard and "h" or "-",
      item.chosen and "c" or "-",
      item.disabled and "d" or "-",
      string.format("%d,%d", slot.x, slot.y),
    }, ":")
  end
  return table.concat(parts, "|")
end

-- Lays out the cloud (or the conversation) from fresh data. `force` draws even when nothing changed.
function Orbit.Render(force)
  if not (frame and frame:IsShown()) then
    return
  end
  local places, outer, rest
  if state.talk then
    places, outer, rest = ns.Talk.OrbitItems(state.talk)
  else
    places, outer = Orbit.Collect()
    places, outer, rest = Model.Pick(places, outer)
  end
  if rest and #rest > 0 then
    outer[#outer + 1] = {
      kind = "plus",
      label = "+" .. #rest,
      title = string.format(L["%d more"], #rest),
      rest = rest,
      hint = L["Click lists the rest"],
      onClick = function(item)
        local items = {}
        for _, r in ipairs(item.rest) do
          items[#items + 1] = {
            label = r.title or "?",
            onClick = function()
              if r.line then
                Voice.Play(r.line)
                Orbit.Note(string.format(L["Playing: %s"], r.title or "?"))
              elseif r.ref and B:GetAction("browser.open") then
                B:RunAction("browser.open", r.ref, { source = "voice" })
              end
            end,
          }
        end
        B.UI.Menu(frame, L["More"], items, Voice.mod)
      end,
    }
  end
  Orbit.Items = { places = places, outer = outer, rest = rest }
  local layout = Model.Layout(places, outer)
  for _, slot in ipairs(layout) do
    if slot.kind == "quest" and slot.parent then
      slot.item.giver = slot.parent.title
    end
  end
  Orbit.Layout = layout
  local sig = signature(layout)
  if not force and sig == state.signature then
    Orbit.Refresh()
    return
  end
  state.signature = sig
  shown = {}
  faceCount = 0
  for _, b in pairs(byKey) do
    b.used = false
  end
  hubFace(state.talk and state.talk.npc and state.talk.npc.creature or nil)
  for _, slot in ipairs(layout) do
    local item = slot.item
    -- compact: the moons fold into their giver's badge
    local folded = item.kind == "quest" and not state.wide and not state.talk
    if not folded then
      bubble(item, slot.x, slot.y, slot.r, item.line and Voice.Playing(item.line))
    end
  end
  for key, b in pairs(byKey) do
    if not b.used then
      b:Hide()
      b.item = nil
      b.cx, b.cy = nil, nil -- a bubble back from the pool appears at its slot, it does not glide
      gliding[b] = nil
      byKey[key] = nil
      free[#free + 1] = b
    end
  end
  frame.innerRing:SetAlpha(state.wide and 0.6 or 0.3)
  frame.outerRing:SetAlpha(state.wide and 0.6 or 0.3)
  Orbit.RefreshHub()
  Orbit.ApplyScale()
end

-- The bubbles drawn, in layout order (tests).
function Orbit.Visible()
  local out = {}
  for i, b in ipairs(shown) do
    out[i] = b
  end
  return out
end

-- The play and heard states and the hub without collecting again.
function Orbit.Refresh()
  if not (frame and frame:IsShown()) then
    return
  end
  for _, b in ipairs(shown) do
    local item = b.item
    if item then
      item.heard = item.line ~= nil and Voice.IsHeard(item.line.key) or false
      paint(b, item, item.line and Voice.Playing(item.line))
    end
  end
  Orbit.RefreshHub()
end

-- ---------------------------------------------------------------------------------------------
-- Showing
-- ---------------------------------------------------------------------------------------------

function Orbit.Show()
  if not frame then
    build()
  end
  frame:Show()
  state.k = state.wide and 1 or COMPACT
  state.target = state.k
  state.signature = nil
  Orbit.ApplyPlace()
  Orbit.ApplyScale()
  Orbit.Render(true)
end

function Orbit.Hide()
  if frame then
    frame:Hide()
  end
end

function Orbit.Toggle()
  if frame and frame:IsShown() then
    Orbit.Hide()
    return false
  end
  Orbit.Show()
  return true
end

function Orbit.IsShown()
  return frame ~= nil and frame:IsShown()
end

function Orbit.IsDragging()
  return state.dragging == true
end

-- The clear-screen key (plan-round4 F1, BASTIANS_SUITE_HIDDEN): the panel goes with the suite and
-- comes back as it was.
function Orbit.HideByKey(hidden)
  if hidden then
    state.hiddenByKey = Orbit.IsShown() or nil
    if frame then
      frame:Hide()
    end
  elseif state.hiddenByKey then
    state.hiddenByKey = nil
    Orbit.Show()
  end
end

-- The conversation takes the orbit over (Talk.lua) and gives it back with nil.
function Orbit.SetTalk(talk)
  state.talk = talk
  state.signature = nil
  if talk then
    if not Orbit.IsShown() then
      Orbit.Show()
    end
    Orbit.SetWide(true)
  else
    state.settle = pointerOver() and nil or SETTLE
    if frame and frame:IsShown() then
      Orbit.Render(true)
    end
  end
end

function Orbit.Schedule()
  local mod = Voice.mod
  if mod and Orbit.IsShown() then
    mod:Coalesce("orbit", 0.2, function()
      Orbit.Render()
    end)
  end
end

function Orbit.Attach(mod)
  for _, event in ipairs({
    "ZONE_CHANGED_NEW_AREA",
    "ZONE_CHANGED",
    "ZONE_CHANGED_INDOORS",
    "QUEST_LOG_UPDATE",
  }) do
    mod:RegisterEvent(event, Orbit.Schedule)
  end
  -- the line under the hub follows the target's roleplay name (L3)
  mod:RegisterEvent("PLAYER_TARGET_CHANGED", function()
    Orbit.RefreshHub()
  end)
  mod:On("BASTIANS_RP_NAME", function()
    Orbit.RefreshHub()
  end)
  mod:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    Voice.loggedIn = true
    if profile().orbitShown ~= false and not Orbit.IsShown() then
      Orbit.Show()
    else
      Orbit.Schedule()
    end
  end)
  mod:RegisterEvent("PLAYER_REGEN_DISABLED", function()
    if frame and profile().fadeInCombat ~= false then
      frame:SetAlpha(0.4)
    end
  end)
  mod:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if frame then
      frame:SetAlpha(1)
      Orbit.Schedule()
    end
  end)
  mod:RegisterEvent("UI_SCALE_CHANGED", function()
    Orbit.ApplyPlace()
    Orbit.ApplyScale()
  end)
  mod:On("BASTIANS_VOICE_CHANGED", function()
    Orbit.Refresh()
  end)
  mod:On("BASTIANS_ENTITY_CHANGED", Orbit.Schedule)
  mod:On("BASTIANS_THEME_CHANGED", function()
    state.signature = nil
    Orbit.Schedule()
  end)
  mod:On("BASTIANS_SETTING_CHANGED", function(_, _, name)
    if name == "Voice" then
      Orbit.ApplyPlace()
      Orbit.ApplyScale()
      Orbit.Schedule()
    end
  end)
  if Voice.loggedIn and profile().orbitShown ~= false then
    Orbit.Show() -- switched on after the login: no PLAYER_ENTERING_WORLD comes
  end
end

function Orbit.Detach()
  Orbit.Hide()
end
