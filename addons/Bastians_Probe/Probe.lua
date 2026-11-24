-- Developer-only API probe: records what the running client really offers (docs/forever-api.md, probe plan).
-- luacheck: ignore 113 143
-- The probe deliberately calls unverified APIs directly; every probe step runs in pcall and records errors.
local ADDON, ns = ...

local VERSION = "0.1.0"
local SLICE_MS = 8 -- per-frame time budget for sliced work
local MAX_MAP_ID = 3000 -- P3 scans uiMapIDs 1..MAX_MAP_ID
local MAX_DEPTH = 4 -- depth limit when copying API results into saved variables

local db -- BastiansProbeDB, set on ADDON_LOADED
local running = false

-- ---------------------------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------------------------

local function say(fmt, ...)
  local msg = select("#", ...) > 0 and string.format(fmt, ...) or fmt
  DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffBastians Probe:|r " .. msg)
end

local function now()
  return date("!%Y-%m-%dT%H:%M:%SZ")
end

-- Copy a value into something saved variables can hold: plain tables, strings, numbers, booleans.
local function clean(v, depth)
  local isSecret = rawget(_G, "issecretvalue")
  if v ~= nil and isSecret and isSecret(v) then
    return "<secret>" -- an addon may not read it (the retail family's restriction)
  end
  local t = type(v)
  if t == "string" or t == "number" or t == "boolean" or t == "nil" then
    return v
  end
  if t == "table" then
    depth = depth or 0
    if depth >= MAX_DEPTH then
      return "<table, depth limit>"
    end
    local out = {}
    for k, val in pairs(v) do
      local kt = type(k)
      if kt == "string" or kt == "number" then
        out[k] = clean(val, depth + 1)
      end
    end
    return out
  end
  return "<" .. t .. ">"
end

-- Pack all return values, including trailing nils, as a saved-variable friendly table.
local function pack(...)
  local n = select("#", ...)
  local out = { n = n }
  for i = 1, n do
    local v = select(i, ...)
    out[i] = clean(v)
    if v == nil then
      out[i] = "<nil>"
    end
  end
  return out
end

local function finish(ok, ...)
  if ok then
    return { ok = true, ret = pack(...) }
  end
  return { ok = false, err = tostring((...)) }
end

-- Call fn(...) protected; returns { ok = true, ret = packed returns } or { ok = false, err = message }.
local function try(fn, ...)
  if type(fn) ~= "function" then
    return { ok = false, err = "missing (" .. type(fn) .. ")" }
  end
  return finish(pcall(fn, ...))
end

-- obj:name(...) protected, the lookup too: a frame may lack a method, and looking it up can raise.
local function tryMethod(obj, name, ...)
  local ok, fn = pcall(function()
    return obj[name]
  end)
  if not ok then
    return { ok = false, err = tostring(fn) }
  end
  return try(fn, obj, ...)
end

local function result(id)
  db.results[id] = db.results[id] or {}
  return db.results[id]
end

-- Sliced work: step() is called repeatedly until it returns true; each frame gets SLICE_MS.
local function runSliced(label, step, onDone)
  local frame = 0
  local function tick()
    frame = frame + 1
    local start = debugprofilestop()
    local ok, finished
    repeat
      ok, finished = pcall(step)
      if not ok then
        say("%s failed: %s", label, tostring(finished))
        if onDone then
          onDone(false, finished)
        end
        return
      end
    until finished or debugprofilestop() - start > SLICE_MS
    if finished then
      if onDone then
        onDone(true, frame)
      end
    else
      C_Timer.After(0, tick)
    end
  end
  C_Timer.After(0, tick)
end

-- ---------------------------------------------------------------------------------------------
-- Meta: who and what was probed (never other players' names; own character name is not stored)
-- ---------------------------------------------------------------------------------------------

local function recordMeta()
  local version, build, buildDate, interface = GetBuildInfo()
  local _, englishClass = UnitClass("player")
  local _, englishRace = UnitRace("player")
  db.meta = {
    probeVersion = VERSION,
    version = version,
    build = build,
    buildDate = buildDate,
    interface = interface,
    client = interface == 16001 and "forever" or (interface and interface >= 100000) and "retail" or "other",
    locale = GetLocale(),
    realm = GetRealmName(),
    region = try(GetCurrentRegion),
    faction = UnitFactionGroup("player"),
    level = UnitLevel("player"),
    class = englishClass,
    race = englishRace,
    updated = now(),
  }
end

-- ---------------------------------------------------------------------------------------------
-- P1: API presence. Full dump of _G by type, every C_* namespace, Enum names.
-- ---------------------------------------------------------------------------------------------

local function probeP1(onDone)
  local keys = {}
  for k in pairs(_G) do
    if type(k) == "string" then
      keys[#keys + 1] = k
    end
  end
  table.sort(keys)
  local out = {
    started = now(),
    count = #keys,
    functions = {},
    tables = {},
    namespaces = {},
    other = {},
    enums = {},
  }
  local i = 0
  runSliced("P1", function()
    i = i + 1
    local k = keys[i]
    if not k then
      return true
    end
    local v = rawget(_G, k)
    local t = type(v)
    if t == "function" then
      out.functions[#out.functions + 1] = k
    elseif t == "table" then
      if string.match(k, "^C_") then
        local fns = {}
        for name, f in pairs(v) do
          if type(name) == "string" and type(f) == "function" then
            fns[#fns + 1] = name
          end
        end
        table.sort(fns)
        out.namespaces[k] = fns
      elseif k ~= "_G" then
        out.tables[#out.tables + 1] = k
      end
    elseif t ~= "nil" then
      out.other[#out.other + 1] = k .. ":" .. t
    end
    return false
  end, function(ok)
    if type(Enum) == "table" then
      for name in pairs(Enum) do
        out.enums[#out.enums + 1] = name
      end
      table.sort(out.enums)
      if type(Enum.TooltipDataType) == "table" then
        out.tooltipDataType = clean(Enum.TooltipDataType)
      end
    end
    out.finished = now()
    db.results.P1 = out
    say(
      "P1 done: %d globals, %d functions, %d C_ namespaces",
      out.count,
      #out.functions,
      (function()
        local n = 0
        for _ in pairs(out.namespaces) do
          n = n + 1
        end
        return n
      end)()
    )
    if onDone then
      onDone(ok)
    end
  end)
end

-- ---------------------------------------------------------------------------------------------
-- P2: quest log shape, both API families, completed quest count.
-- ---------------------------------------------------------------------------------------------

local function probeP2()
  local out = { at = now(), modern = {}, legacy = {} }
  local num = try(C_QuestLog and C_QuestLog.GetNumQuestLogEntries)
  out.modernCount = num
  if num.ok then
    local n = tonumber(num.ret[1]) or 0
    for i = 1, math.min(n, 40) do
      local info = try(C_QuestLog.GetInfo, i)
      local entry = { index = i, info = info }
      local qid = info.ok and type(info.ret[1]) == "table" and info.ret[1].questID
      if qid and qid ~= 0 then
        entry.idForIndex = try(C_QuestLog.GetQuestIDForLogIndex, i)
        entry.objectives = try(C_QuestLog.GetQuestObjectives, qid)
        entry.isComplete = try(C_QuestLog.IsComplete, qid)
        entry.readyForTurnIn = try(C_QuestLog.ReadyForTurnIn, qid)
        entry.tagInfo = try(C_QuestLog.GetQuestTagInfo, qid)
        entry.isElite = try(C_QuestLog.IsEliteQuest, qid)
        -- what the client says a quest pays, by id and with the quest selected (ADR 0053)
        entry.rewardByID = { money = try(GetQuestLogRewardMoney, qid), xp = try(GetQuestLogRewardXP, qid) }
        try(C_QuestLog.SetSelectedQuest, qid)
        entry.rewardSelected = {
          money = try(GetQuestLogRewardMoney, qid),
          xp = try(GetQuestLogRewardXP, qid),
          items = try(GetNumQuestLogRewards, qid),
          choices = try(GetNumQuestLogChoices, qid, true),
        }
      end
      out.modern[#out.modern + 1] = entry
    end
  end
  local legacyNum = try(GetNumQuestLogEntries)
  out.legacyCount = legacyNum
  if legacyNum.ok then
    local n = tonumber(legacyNum.ret[1]) or 0
    for i = 1, math.min(n, 40) do
      out.legacy[#out.legacy + 1] = {
        index = i,
        title = try(GetQuestLogTitle, i),
        leaderBoard1 = try(GetQuestLogLeaderBoard, 1, i),
      }
    end
  end
  local completed = try(C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs)
  out.completedModern = completed.ok and type(completed.ret[1]) == "table" and #completed.ret[1] or completed
  local legacyDone = try(GetQuestsCompleted)
  if legacyDone.ok and type(legacyDone.ret[1]) == "table" then
    local n = 0
    for _ in pairs(legacyDone.ret[1]) do
      n = n + 1
    end
    out.completedLegacy = n
  else
    out.completedLegacy = legacyDone
  end
  out.questTimers = try(C_QuestLog and C_QuestLog.GetQuestTimers)
  out.questBlobFrame = try(CreateFrame, "QuestPOIFrame") -- may an addon draw the game's zone?
  out.questTrivialRange = try(rawget(_G, "UnitQuestTrivialLevelRange"), "player")
  out.calendarTime = try(C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime)
  db.results.P2 = out
  say("P2 done: %d modern entries, %d legacy entries", #out.modern, #out.legacy)
end

-- ---------------------------------------------------------------------------------------------
-- P3: map table. GetMapInfo, world corners, art layers and textures for every uiMapID.
-- ---------------------------------------------------------------------------------------------

local function worldCorner(mapID, x, y)
  if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then
    return nil
  end
  local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
  if not ok then
    return { err = tostring(continent) }
  end
  if not pos then
    return nil
  end
  local wx, wy = pos:GetXY()
  return { continent = continent, x = wx, y = wy }
end

local function probeP3(onDone)
  local maps = {}
  local id = 0
  local found = 0
  runSliced("P3", function()
    id = id + 1
    if id > MAX_MAP_ID then
      return true
    end
    local ok, info = pcall(C_Map.GetMapInfo, id)
    if ok and info then
      found = found + 1
      local m = {
        name = info.name,
        mapType = info.mapType,
        parent = info.parentMapID,
        flags = info.flags,
        c00 = worldCorner(id, 0, 0),
        c11 = worldCorner(id, 1, 1),
        c10 = worldCorner(id, 1, 0), -- third corner: fixes the axis orientation of the affine transform
      }
      local okGroup, group = pcall(C_Map.GetMapGroupID, id)
      if okGroup then
        m.group = group
      end
      local okLayers, layers = pcall(C_Map.GetMapArtLayers, id)
      if okLayers and type(layers) == "table" then
        m.layers = clean(layers)
        local okTex, tex = pcall(C_Map.GetMapArtLayerTextures, id, 1)
        if okTex and type(tex) == "table" then
          m.textures = clean(tex)
        end
      end
      maps[id] = m
    end
    return false
  end, function(ok)
    db.results.P3 = { at = now(), maxMapID = MAX_MAP_ID, found = found, maps = maps }
    say("P3 done: %d maps", found)
    if onDone then
      onDone(ok)
    end
  end)
end

-- ---------------------------------------------------------------------------------------------
-- P4: landmarks. /bprobe p4 <label> at a known place. With something targeted, the target's kind,
-- id and name go into the record too (since 21.10.2026, B4.4): the build then checks that the
-- packs place that NPC, object or gather node where the player stood (probetruth.py).
-- ---------------------------------------------------------------------------------------------

-- The target as { kind = "npc" | "object" | "vehicle" | "pet" | "player" | guid type, id, name, guid }, or
-- nil without a target. GUIDs read "Creature-0-<server>-<instance>-<zone>-<npcID>-<spawn>"; the kind
-- is the first field, the id the sixth, as on retail.
local function targetRecord()
  local guid = try(UnitGUID, "target")
  guid = guid.ok and guid.ret[1] or nil
  if type(guid) ~= "string" or guid == "<nil>" then
    return nil -- no target (try() packs a nil return as the string "<nil>"; seen 21.10.2026)
  end
  local kind, id = string.match(guid, "^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  local kinds = { Creature = "npc", GameObject = "object", Vehicle = "vehicle", Pet = "pet" }
  local name = try(UnitName, "target")
  return {
    guid = guid,
    kind = kind and (kinds[kind] or string.lower(kind)) or string.match(guid, "^(%a+)") or "?",
    id = id and tonumber(id) or nil,
    name = name.ok and name.ret[1] ~= "<nil>" and name.ret[1] or nil,
  }
end

local function playerPosition()
  local pos = {}
  local up = try(UnitPosition, "player")
  pos.unitPosition = up -- x, y, z, instanceID in world yards when present (measured 20.10.2026: x first)
  local okMap, mapID = pcall(C_Map.GetBestMapForUnit, "player")
  if okMap and mapID then
    pos.mapID = mapID
    local okPos, mp = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if okPos and mp then
      pos.mapX, pos.mapY = mp:GetXY()
    end
  end
  pos.zone = GetZoneText()
  pos.subzone = GetSubZoneText()
  return pos
end

local function probeP4(label)
  local list = result("P4")
  local entry = playerPosition()
  entry.label = label ~= "" and label or ("landmark " .. (#list + 1))
  entry.target = targetRecord()
  entry.at = now()
  list[#list + 1] = entry
  local t = entry.target
  say(
    "P4 #%d '%s': map %s %.4f %.4f%s",
    #list,
    entry.label,
    tostring(entry.mapID),
    entry.mapX or -1,
    entry.mapY or -1,
    t and string.format(", target %s %s (%s)", t.kind, tostring(t.id), tostring(t.name)) or ""
  )
end

-- ---------------------------------------------------------------------------------------------
-- Display frame for P5 and P10 (screenshots)
-- ---------------------------------------------------------------------------------------------

local display

local function getDisplay()
  if display then
    display:Show()
    return display
  end
  display = CreateFrame("Frame", "BastiansProbeDisplay", UIParent)
  display:SetSize(720, 520)
  display:SetPoint("CENTER")
  -- above every window of the suite (FULLSCREEN_DIALOG, and TOOLTIP at its lowest level for a
  -- window on top): Forever 17.11.2026, the open book covered the model and the reveal panels in
  -- their screenshots
  display:SetFrameStrata("TOOLTIP")
  display:SetFrameLevel(100)
  display:SetMovable(true)
  display:EnableMouse(true)
  display:RegisterForDrag("LeftButton")
  display:SetScript("OnDragStart", display.StartMoving)
  display:SetScript("OnDragStop", display.StopMovingOrSizing)
  local bg = display:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.05, 0.05, 0.08, 0.92)
  display.title = display:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  display.title:SetPoint("TOPLEFT", 10, -8)
  display.cells = {}
  return display
end

local function clearDisplay(title)
  local d = getDisplay()
  d.title:SetText(title .. "   (/bprobe hide)")
  for _, key in ipairs({ "tech", "models", "reveal", "portraits" }) do
    local part = rawget(d, key) -- rawget: a stub frame answers every name
    if part then
      part:Hide()
    end
  end
  for _, cell in ipairs(d.cells) do
    cell.tex:Hide()
    cell.label:Hide()
    if cell.bg then
      cell.bg:Hide()
    end
  end
  return d
end

local function cell(d, i, size, perRow)
  local c = d.cells[i]
  if not c then
    c = {}
    c.tex = d:CreateTexture(nil, "ARTWORK")
    c.label = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d.cells[i] = c
  end
  local col = (i - 1) % perRow
  local row = math.floor((i - 1) / perRow)
  c.tex:ClearAllPoints()
  c.tex:SetSize(size, size)
  c.tex:SetPoint("TOPLEFT", 10 + col * (size + 60), -30 - row * (size + 22))
  c.label:ClearAllPoints()
  c.label:SetPoint("TOPLEFT", c.tex, "BOTTOMLEFT", 0, -2)
  c.label:SetWidth(size + 56)
  c.label:SetJustifyH("LEFT")
  c.tex:Show()
  c.label:Show()
  return c
end

-- Set a texture and report what the client did with it.
local function textureTest(c, source, labelText)
  local ok, ret = pcall(c.tex.SetTexture, c.tex, source)
  local okGet, got = pcall(c.tex.GetTexture, c.tex)
  c.label:SetText(labelText)
  return {
    source = source,
    ok = ok,
    setReturned = clean(ret),
    getTexture = okGet and clean(got) or nil,
  }
end

-- ---------------------------------------------------------------------------------------------
-- P5: imagery. Map art textures of the current map; any minimap tile given as argument.
-- ---------------------------------------------------------------------------------------------

local P5_PATH_CANDIDATES = {
  "Interface\\WorldMap\\Elwynn\\Elwynn1",
  "World\\Minimaps\\Azeroth\\map32_48",
  "Textures\\Minimap\\Azeroth\\map32_48",
}

local function probeP5(arg)
  local out = { at = now(), tests = {} }
  local d = clearDisplay("P5 imagery")
  local i = 0
  local okMap, mapID = pcall(C_Map.GetBestMapForUnit, "player")
  out.mapID = okMap and mapID or nil
  if out.mapID then
    local okTex, tex = pcall(C_Map.GetMapArtLayerTextures, out.mapID, 1)
    if okTex and type(tex) == "table" then
      for j = 1, math.min(#tex, 6) do
        i = i + 1
        out.tests[#out.tests + 1] = textureTest(cell(d, i, 96, 6), tex[j], "art " .. tostring(tex[j]))
      end
    else
      out.artError = tostring(tex)
    end
  end
  local sources = {}
  for _, p in ipairs(P5_PATH_CANDIDATES) do
    sources[#sources + 1] = p
  end
  if arg and arg ~= "" then
    sources[#sources + 1] = tonumber(arg) or arg
  end
  for _, s in ipairs(sources) do
    i = i + 1
    out.tests[#out.tests + 1] = textureTest(cell(d, i, 96, 6), s, tostring(s))
  end
  db.results.P5 = out
  say("P5 done: %d textures tested, take a screenshot of the probe window", #out.tests)
end

-- /bprobe alpha: the Map_Art overview cells over a red square. Red around the land means the client
-- honours the cell's transparency; black means it does not (map.md B8.5 b, 20.10.2026).
local ALPHA_TILES = "Interface\\AddOns\\Bastians_Map_Art\\Generated\\Tiles\\"

local function probeAlpha()
  local out = { at = now(), tests = {} }
  local d = clearDisplay("Alpha test: red sea = transparency honoured, black sea = not")
  for i, name in ipairs({ "test_dxt5", "0_3_6" }) do
    local c = cell(d, i, 256, 2)
    if not c.bg then
      c.bg = d:CreateTexture(nil, "BACKGROUND")
      c.bg:SetColorTexture(1, 0, 0)
    end
    c.bg:ClearAllPoints()
    c.bg:SetAllPoints(c.tex)
    c.bg:Show()
    out.tests[#out.tests + 1] =
      textureTest(c, ALPHA_TILES .. name, name .. (i == 1 and " (DXT5)" or " (DXT1)"))
  end
  db.results.alpha = out
  say("alpha test shown: left DXT5, right DXT1; say which has red sea. /bprobe hide")
end

-- /bprobe mask [fdid maskName]: a native coast tile masked with its Map_Art sea mask over red. Red where
-- the sea was means mask textures work (the Map's close-zoom coast, map.md 22.10.2026). Default: Azeroth
-- tile 29/48 west of Stormwind (FileDataID 204373, 57 % sea), mask 0_29_48.
local MASK_PATH = "Interface\\AddOns\\Bastians_Map_Art\\Generated\\Masks\\"

local function probeMask(arg)
  local fdid, name = string.match(arg or "", "^%s*(%d+)%s+(%S+)")
  fdid, name = tonumber(fdid) or 204373, name or "0_29_48"
  local out = { at = now(), tests = {}, fdid = fdid, mask = name }
  local d = clearDisplay("Mask test: red where the sea was = mask textures work")
  out.createMaskTexture = type(d.CreateMaskTexture) == "function"
  local plain = cell(d, 1, 256, 3)
  out.tests[1] = textureTest(plain, fdid, "tile " .. fdid .. " unmasked")
  local masked = cell(d, 2, 256, 3)
  if not masked.bg then
    masked.bg = d:CreateTexture(nil, "BACKGROUND")
    masked.bg:SetColorTexture(1, 0, 0)
  end
  masked.bg:ClearAllPoints()
  masked.bg:SetAllPoints(masked.tex)
  masked.bg:Show()
  out.tests[2] = textureTest(masked, fdid, "tile " .. fdid .. " masked with " .. name)
  local ok, m = pcall(function() -- the raw API, as Bastians.Compat.AddMask uses it
    local mt = masked.mask or d:CreateMaskTexture()
    masked.mask = mt
    mt:SetTexture(MASK_PATH .. name, "CLAMP", "CLAMP")
    mt:ClearAllPoints()
    mt:SetAllPoints(masked.tex)
    if not masked.masked then
      masked.tex:AddMaskTexture(mt)
      masked.masked = true
    end
    return mt
  end)
  out.addMask = ok and m ~= nil
  out.addMaskError = not ok and tostring(m) or nil
  if ok and m then
    local okGet, got = pcall(m.GetTexture, m)
    out.maskGetTexture = okGet and clean(got) or nil -- nil = the mask file did not load
  end
  local shown = cell(d, 3, 256, 3)
  out.tests[3] = textureTest(shown, MASK_PATH .. name, "the mask itself (white = kept)")
  -- the overview cell of the same addon as a control: it loads (20.10.2026), so a nil above is the mask file
  local control = cell(d, 4, 128, 3)
  out.tests[4] = textureTest(control, ALPHA_TILES .. "0_3_6", "control: overview cell 0_3_6")
  out.cellGetTexture = out.tests[4].getTexture
  db.results.mask = out
  say(
    "mask test: CreateMaskTexture %s, AddMask %s, mask GetTexture %s, mask as texture %s / %s, cell as"
      .. " texture %s%s. /bprobe hide",
    tostring(out.createMaskTexture),
    tostring(out.addMask),
    tostring(out.maskGetTexture),
    tostring(out.tests[3].setReturned),
    tostring(out.tests[3].getTexture),
    tostring(out.cellGetTexture),
    out.addMaskError and (" (" .. out.addMaskError .. ")") or ""
  )
end

-- /bprobe maskvariants: which of four mask files the client loads (22.10.2026: the coast masks did
-- not load while the overview cells of the same addon do). Each is drawn over blue; GetTexture says.
local MAP_ART = "Interface\\AddOns\\Bastians_Map_Art\\Generated\\"
local MASK_VARIANTS = {
  { "Tiles\\v_tiles_mask", "the mask in the Tiles folder" },
  { "Masks\\v_masks_cell", "a cell in the Masks folder" },
  { "Masks\\v_masks_py64", "the mask re-encoded, 64 px" },
  { "Masks\\v_masks_py512", "the mask scaled, 512 px" },
}

local function probeMaskVariants()
  local out = { at = now(), tests = {} }
  local d = clearDisplay("Mask files: which load? (white/land shown = loaded)")
  local parts = {}
  for i, v in ipairs(MASK_VARIANTS) do
    local c = cell(d, i, 200, 4)
    if not c.bg then
      c.bg = d:CreateTexture(nil, "BACKGROUND")
      c.bg:SetColorTexture(0, 0, 1)
    end
    c.bg:ClearAllPoints()
    c.bg:SetAllPoints(c.tex)
    c.bg:Show()
    local t = textureTest(c, MAP_ART .. v[1], v[2])
    out.tests[i] = t
    parts[#parts + 1] = string.format("%d %s", i, tostring(t.getTexture))
  end
  db.results.maskvariants = out
  say("mask variants (GetTexture, nil = not loaded): %s. /bprobe hide", table.concat(parts, ", "))
end

-- ---------------------------------------------------------------------------------------------
-- P6: settings registration and tooltip hooks. Counters fill while you mouse over things.
-- ---------------------------------------------------------------------------------------------

local p6Hooked = false

local function probeP6()
  local out = result("P6")
  out.at = now()
  out.settingsAPI = type(Settings) == "table" and type(Settings.RegisterCanvasLayoutCategory) == "function"
  out.interfaceOptionsAPI = type(InterfaceOptions_AddCategory) == "function"
  if not out.settingsRegistered and out.settingsAPI then
    local panel = CreateFrame("Frame")
    local text = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOPLEFT", 16, -16)
    text:SetText("Bastians Probe: settings registration works (P6)")
    local okCat, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, "Bastians Probe")
    out.settingsCategory = okCat and "created" or tostring(category)
    if okCat then
      out.settingsRegistered = pcall(Settings.RegisterAddOnCategory, category)
    end
  end
  out.processor = type(TooltipDataProcessor) == "table"
    and type(TooltipDataProcessor.AddTooltipPostCall) == "function"
  out.fired = out.fired or {}
  if not p6Hooked then
    p6Hooked = true
    if out.processor and type(Enum) == "table" and type(Enum.TooltipDataType) == "table" then
      for name, value in pairs(Enum.TooltipDataType) do
        pcall(TooltipDataProcessor.AddTooltipPostCall, value, function(_, data)
          local key = "processor:" .. tostring(name)
          local f = out.fired[key] or { count = 0 }
          f.count = f.count + 1
          if data and f.count <= 3 then
            f.samples = f.samples or {}
            f.samples[f.count] = { type = data.type, id = data.id, guid = data.guid and "<guid>" or nil }
          end
          out.fired[key] = f
        end)
      end
    end
    for _, script in ipairs({ "OnTooltipSetUnit", "OnTooltipSetItem", "OnTooltipSetSpell" }) do
      local okHas, has = pcall(GameTooltip.HasScript, GameTooltip, script)
      out["hasScript:" .. script] = okHas and has or false
      if okHas and has then
        GameTooltip:HookScript(script, function()
          local key = "script:" .. script
          local f = out.fired[key] or { count = 0 }
          f.count = f.count + 1
          out.fired[key] = f
        end)
      end
    end
  end
  say(
    "P6: settings API %s, processor %s. Open the settings panel, mouse over a unit, an item, an object;"
      .. " then /bprobe p6 again to save counts.",
    tostring(out.settingsAPI),
    tostring(out.processor)
  )
end

-- ---------------------------------------------------------------------------------------------
-- P7: taxi. Dumps on TAXIMAP_OPENED; times one flight from TakeTaxiNode to landing.
-- ---------------------------------------------------------------------------------------------

local flight

local function onTaxiMapOpened()
  local out = result("P7")
  out.opens = out.opens or {}
  local entry = { at = now(), position = playerPosition() }
  local okMap, mapID = pcall(C_Map.GetBestMapForUnit, "player")
  if C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and okMap and mapID then
    entry.modern = try(C_TaxiMap.GetAllTaxiNodes, mapID)
  end
  local num = try(NumTaxiNodes)
  entry.legacyCount = num
  if num.ok then
    entry.legacy = {}
    for i = 1, math.min(tonumber(num.ret[1]) or 0, 80) do
      entry.legacy[i] = {
        name = try(TaxiNodeName, i),
        position = try(TaxiNodePosition, i),
        nodeType = try(TaxiNodeGetType, i),
        cost = try(TaxiNodeCost, i),
      }
    end
  end
  out.opens[#out.opens + 1] = entry
  say("P7: taxi map recorded (%d so far)", #out.opens)
end

local function onTakeTaxiNode(index)
  local okName, name = pcall(TaxiNodeName, index)
  flight = {
    index = index,
    to = okName and name or nil,
    startAt = GetTime(),
    started = now(),
    from = playerPosition(),
  }
end

local function finishFlight(how)
  if not flight then
    return
  end
  local out = result("P7")
  out.flights = out.flights or {}
  flight.seconds = GetTime() - flight.startAt
  flight.startAt = nil
  flight.landed = playerPosition()
  flight.endedBy = how
  out.flights[#out.flights + 1] = flight
  say("P7: flight to %s took %.1f s (%s)", tostring(flight.to), flight.seconds, how)
  flight = nil
end

local function onControlGained()
  if UnitOnTaxi and UnitOnTaxi("player") then
    return
  end
  finishFlight("PLAYER_CONTROL_GAINED")
end

-- The beta dump of 20.10.2026 held no flight although one was flown: the hook or the event did not
-- fire. A one-second poll of UnitOnTaxi catches take-off (no destination name then; the landing
-- position gives it) and landing regardless of hooks and events.
local onTaxi = false
local function pollTaxi()
  local now_ = UnitOnTaxi and UnitOnTaxi("player") and true or false
  if now_ and not onTaxi then
    if not flight then
      flight = { startAt = GetTime(), started = now(), from = playerPosition(), detectedBy = "UnitOnTaxi" }
      say("P7: take-off seen by UnitOnTaxi")
    end
  elseif onTaxi and not now_ then
    finishFlight("UnitOnTaxi")
  end
  onTaxi = now_
end

-- ---------------------------------------------------------------------------------------------
-- Trainer and merchant shapes (passive, on TRAINER_SHOW and MERCHANT_SHOW)
-- ---------------------------------------------------------------------------------------------

local function npcID()
  local guid = UnitGUID("npc")
  return guid and tonumber(string.match(guid, "^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)")) or nil
end

local function onTrainerShow()
  local out = result("trainer")
  if #out >= 5 then
    return
  end
  local entry = { at = now(), npc = npcID(), position = playerPosition() }
  entry.trainerType = try(C_Trainer and C_Trainer.GetTrainerType)
  local num = try(GetNumTrainerServices)
  entry.count = num
  if num.ok then
    entry.services = {}
    for i = 1, math.min(tonumber(num.ret[1]) or 0, 12) do
      entry.services[i] = {
        info = try(GetTrainerServiceInfo, i),
        cost = try(GetTrainerServiceCost, i),
        skill = try(GetTrainerServiceSkillReq, i),
        level = try(GetTrainerServiceLevelReq, i),
      }
    end
  end
  out[#out + 1] = entry
  say("trainer recorded (%d)", #out)
end

local function onMerchantShow()
  local out = result("merchant")
  if #out >= 5 then
    return
  end
  local entry = { at = now(), npc = npcID(), position = playerPosition() }
  local num = try(GetMerchantNumItems)
  entry.count = num
  if num.ok then
    entry.items = {}
    for i = 1, math.min(tonumber(num.ret[1]) or 0, 8) do
      entry.items[i] = {
        modern = try(C_MerchantFrame and C_MerchantFrame.GetItemInfo, i),
        legacy = try(GetMerchantItemInfo, i),
        link = try(GetMerchantItemLink, i),
      }
    end
  end
  out[#out + 1] = entry
  say("merchant recorded (%d)", #out)
end

-- ---------------------------------------------------------------------------------------------
-- P10: icons and glyphs (screenshot)
-- ---------------------------------------------------------------------------------------------

local P10_ICONS = {
  "Interface\\Minimap\\Tracking\\Banker",
  "Interface\\Minimap\\Tracking\\Auctioneer",
  "Interface\\Minimap\\Tracking\\FlightMaster",
  "Interface\\Minimap\\Tracking\\Innkeeper",
  "Interface\\Minimap\\Tracking\\Mailbox",
  "Interface\\Minimap\\Tracking\\Repair",
  "Interface\\Minimap\\Tracking\\Class",
  "Interface\\Minimap\\Tracking\\Profession",
  "Interface\\Minimap\\Tracking\\Food",
  "Interface\\Minimap\\Tracking\\Reagents",
  "Interface\\Minimap\\Tracking\\StableMaster",
  "Interface\\Minimap\\Tracking\\BattleMaster",
  "Interface\\Minimap\\Tracking\\Ammunition",
  "Interface\\Minimap\\Tracking\\Poisons",
  "Interface\\Minimap\\Tracking\\TrivialQuests",
  "Interface\\Minimap\\Tracking\\None",
  "Interface\\GossipFrame\\AvailableQuestIcon",
  "Interface\\GossipFrame\\ActiveQuestIcon",
  "Interface\\Icons\\INV_Misc_QuestionMark",
  "Interface\\Icons\\INV_Misc_Herb_07",
  "Interface\\Icons\\INV_Ore_Copper_01",
  "Interface\\Icons\\Ability_Mount_RidingHorse",
  "Interface\\TaxiFrame\\UI-Taxi-Icon-Green",
  "Interface\\WorldMap\\WorldMapArrow",
}

local glyphText -- font string of the P10 glyph line, created once

local P10_GLYPHS =
  { "> < - + * # o x | / \\", "\226\150\182 \226\150\160 \226\156\147 \226\128\162 \194\183 \226\128\166" }

local function probeP10()
  local out = { at = now(), icons = {} }
  local d = clearDisplay("P10 icons and glyphs")
  for i, path in ipairs(P10_ICONS) do
    local short = string.match(path, "([^\\]+)$")
    out.icons[i] = textureTest(cell(d, i, 32, 8), path, short)
  end
  glyphText = glyphText or d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  glyphText:ClearAllPoints()
  glyphText:SetPoint("BOTTOMLEFT", 10, 12)
  glyphText:SetText("ASCII: " .. P10_GLYPHS[1] .. "\nUnicode: " .. P10_GLYPHS[2])
  glyphText:Show()
  out.glyphs = P10_GLYPHS
  db.results.P10 = out
  say("P10 done: take a screenshot of the probe window")
end

-- ---------------------------------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------------------------------

local function status()
  local ids = {}
  for id in pairs(db.results) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  say(
    "client %s, build %s (%s). Results: %s",
    tostring(db.meta and db.meta.client),
    tostring(db.meta and db.meta.build),
    tostring(db.meta and db.meta.interface),
    #ids > 0 and table.concat(ids, ", ") or "none"
  )
end

local function runAll()
  if running then
    say("already running")
    return
  end
  running = true
  recordMeta()
  say("running P1, P2, P3, P5, P6, P10. Do not /reload until it says 'all done'.")
  probeP1(function()
    probeP3(function()
      local ok, err = pcall(probeP2)
      if not ok then
        say("P2 failed: %s", tostring(err))
      end
      ok, err = pcall(probeP5)
      if not ok then
        say("P5 failed: %s", tostring(err))
      end
      ok, err = pcall(probeP6)
      if not ok then
        say("P6 failed: %s", tostring(err))
      end
      ok, err = pcall(probeP10)
      if not ok then
        say("P10 failed: %s", tostring(err))
      end
      running = false
      db.meta.updated = now()
      say(
        "all done. Screenshot the probe window, mouse over a unit/item/object,"
          .. " then /bprobe p6 and /reload to save."
      )
    end)
  end)
end

-- /bprobe books: the Library books of Forever (ADR 0058, PH8; catalog review A3.2). Which API
-- tells that a book was read? The probe lists every global that names a library, a book or a
-- readable, then listens: every book opened (ITEM_TEXT_BEGIN/READY) is recorded with its title,
-- its length and the object under the mouse, and every event whose name holds BOOK, LIBRARY or
-- READABLE. /reload saves; the dump goes to data/probe and forever-api.md.
-- /bprobe wonders: what Bastian's Book asks the game to find a wonder done (book.md "The record",
-- ADR 0080): the quest history, the bags and the bank, a known spell, a known title. Presence of
-- each call and its answer for ids every character can answer (no name, no other player).
local function probeWonders()
  db.results = db.results or {}
  local out = { at = now() }
  db.results.wonders = out
  out.isTitleKnown = type(rawget(_G, "IsTitleKnown"))
  out.title1 = try(rawget(_G, "IsTitleKnown"), 1)
  out.numTitles = try(rawget(_G, "GetNumTitles"))
  out.questFlag = try(C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted, 783)
  local all = try(C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs)
  out.questsDone = all.ok and type(all.ret[1]) == "table" and #all.ret[1] or all
  out.hearthstone = try(C_Item and C_Item.GetItemCount, 6948, true)
  out.spellBrownHorse = try(C_SpellBook and C_SpellBook.IsSpellKnown, 458)
  out.mountJournal = type(rawget(_G, "C_MountJournal"))
  out.petJournal = type(rawget(_G, "C_PetJournal"))
  out.numCompanions = try(rawget(_G, "GetNumCompanions"), "CRITTER")
  say("wonders: title api %s, quests done %s; /reload to save", out.isTitleKnown, tostring(out.questsDone))
end

local booksListening = false
local function probeBooks()
  db.results = db.results or {}
  local out = db.results.books or { at = now(), globals = {}, opened = {}, events = {} }
  db.results.books = out
  out.at = now()
  out.globals = {}
  for name, value in pairs(_G) do
    if type(name) == "string" and (name:find("Librar") or name:find("Book") or name:find("Readable")) then
      out.globals[#out.globals + 1] = name .. ":" .. type(value)
    end
  end
  table.sort(out.globals)
  say("books: %d globals name a library, a book or a readable (saved on /reload)", #out.globals)
  if booksListening then
    say("books: listening already; open a book in the Stormwind library, then /reload")
    return
  end
  booksListening = true
  local f = CreateFrame("Frame")
  f:RegisterEvent("ITEM_TEXT_BEGIN")
  f:RegisterEvent("ITEM_TEXT_READY")
  f:RegisterEvent("ITEM_TEXT_CLOSED")
  pcall(f.RegisterAllEvents, f)
  f:SetScript("OnEvent", function(_, event, ...)
    if event == "ITEM_TEXT_BEGIN" or event == "ITEM_TEXT_READY" then
      local okItem, title = pcall(ItemTextGetItem)
      local okText, text = pcall(ItemTextGetText)
      local okGuid, guid = pcall(UnitGUID, "mouseover")
      out.opened[#out.opened + 1] = {
        at = now(),
        event = event,
        title = okItem and title or nil,
        length = okText and type(text) == "string" and #text or nil,
        mouseover = okGuid and guid or nil,
        target = select(2, pcall(UnitGUID, "target")),
      }
      say("books: %s '%s' (%s chars)", event, tostring(title), tostring(okText and text and #text or "?"))
    elseif
      type(event) == "string" and (event:find("BOOK") or event:find("LIBRAR") or event:find("READABLE"))
    then
      local args = {}
      for i = 1, select("#", ...) do
        args[i] = tostring((select(i, ...)))
      end
      out.events[#out.events + 1] = { at = now(), event = event, args = args }
      say("books: event %s", event)
    end
  end)
  say("books: listening. Open a book in the Stormwind library, read it to the end, then /reload")
end

-- ---------------------------------------------------------------------------------------------
-- /bprobe chat and /bprobe combatlog: what Chat version 3 leans on (plan-chat-v3.md §13, X1 to
-- X11). Counts, types and flags only, never another player's name or words (CLAUDE.md §8).
-- ---------------------------------------------------------------------------------------------

local CHAT_CALLS = {
  "ChatFrameUtil.SendTell",
  "ChatFrame_SendTell",
  "ChatFrameUtil.OpenChat",
  "ChatEdit_ActivateChat",
  "AcceptGroup",
  "DeclineGroup",
  "AcceptDuel",
  "CancelDuel",
  "CancelTrade",
  "ConfirmReadyCheck",
  "AcceptResurrect",
  "DeclineResurrect",
  "C_SummonInfo.ConfirmSummon",
  "BNSendWhisper",
  "GetAverageItemLevel",
  "C_Item.GetDetailedItemLevelInfo",
  "GetInventoryItemLink",
  "UnitIsAFK",
  "UnitIsDND",
  "CombatLogGetCurrentEventInfo",
  "issecretvalue",
}
local CHAT_EVENTS = {
  "CHAT_MSG_WHISPER",
  "CHAT_MSG_WHISPER_INFORM",
  "CHAT_MSG_BN_WHISPER",
  "CHAT_MSG_AFK",
  "CHAT_MSG_DND",
}
-- the worn slots of the item level's mean: not the shirt (4) nor the tabard (19)
local WORN_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

local function resolve(path)
  local v = _G
  for part in string.gmatch(path, "[^%.]+") do
    if type(v) ~= "table" then
      return nil
    end
    v = v[part]
  end
  return v
end

local chatListening = false

local CHAT_EVENT_SET = {}
for _, event in ipairs(CHAT_EVENTS) do
  CHAT_EVENT_SET[event] = true
end

local function onChatProbeEvent(out, event, ...)
  if not CHAT_EVENT_SET[event] then
    return
  end
  local text, flags, guid = (select(1, ...)), (select(6, ...)), (select(12, ...))
  local e = out.events[event] or { count = 0, flags = {}, secret = 0, guid = {}, errors = 0 }
  out.events[event] = e
  e.count = e.count + 1
  local ok = pcall(function()
    if type(issecretvalue) == "function" and issecretvalue(text) then
      e.secret = e.secret + 1
    end
    local flag = "none"
    if type(issecretvalue) == "function" and issecretvalue(flags) then
      flag = "secret"
    elseif type(flags) == "string" and flags ~= "" then
      flag = flags
    end
    e.flags[flag] = (e.flags[flag] or 0) + 1
    local kind = type(guid) == "string" and guid:match("^(%a+)%-") or type(guid)
    e.guid[kind] = (e.guid[kind] or 0) + 1
  end)
  if not ok then
    e.errors = e.errors + 1
  end
end

local function probeChat()
  local out = db.results.chat or { events = {} }
  db.results.chat = out
  out.at = now()
  out.calls = {}
  for _, path in ipairs(CHAT_CALLS) do
    out.calls[path] = type(resolve(path))
  end
  out.average = try(GetAverageItemLevel)
  local levels, sum, n = {}, 0, 0
  for _, slot in ipairs(WORN_SLOTS) do
    local okLink, link = pcall(GetInventoryItemLink, "player", slot)
    if okLink and type(link) == "string" then
      local r = try(C_Item and C_Item.GetDetailedItemLevelInfo, link)
      local level = r.ok and r.ret[1]
      if type(level) == "number" then
        levels[slot] = level
        sum, n = sum + level, n + 1
      end
    end
  end
  out.worn = { levels = levels, count = n, mean = n > 0 and sum / n or nil }
  local average = out.average.ok and out.average.ret[1] or nil
  say(
    "chat: %d calls checked; item level %s by the client, %s as the mean of %d worn items",
    #CHAT_CALLS,
    tostring(average),
    tostring(out.worn.mean),
    n
  )
  if chatListening then
    say("chat: listening already; whisper and be whispered, also by a character that is AFK, then /reload")
    return
  end
  chatListening = true
  local f = CreateFrame("Frame")
  for _, event in ipairs(CHAT_EVENTS) do
    pcall(f.RegisterEvent, f, event)
  end
  f:SetScript("OnEvent", function(_, event, ...)
    onChatProbeEvent(out, event, ...)
  end)
  say("chat: listening to whispers and automatic replies (counts and flags only); then /reload")
end

local combatListening = false
local COMBAT_SECONDS = 60
-- where a sub-event's amount stands in CombatLogGetCurrentEventInfo's answer (the retail family)
local AMOUNT_AT = {
  SWING_DAMAGE = 12,
  RANGE_DAMAGE = 15,
  SPELL_DAMAGE = 15,
  SPELL_PERIODIC_DAMAGE = 15,
  SPELL_HEAL = 15,
  SPELL_PERIODIC_HEAL = 15,
}

local function onCombatProbeEvent(out, me)
  local ok = pcall(function()
    local info = { CombatLogGetCurrentEventInfo() }
    local sub, source, dest = info[2], info[4], info[8]
    out.count = out.count + 1
    out.subevents[sub] = (out.subevents[sub] or 0) + 1
    local at = AMOUNT_AT[sub]
    local amount = at and info[at]
    if type(amount) == "number" then
      local kind = sub:find("HEAL", 1, true) and "heal" or "damage"
      if source == me then
        out.done[kind] = out.done[kind] + amount
      end
      if dest == me then
        out.taken[kind] = out.taken[kind] + amount
      end
    end
  end)
  if not ok then
    out.errors = out.errors + 1
  end
end

-- X11. Forever only: retail refuses the registration with a popup no pcall catches.
local function probeCombatLog()
  if combatListening then
    say("combatlog: listening already; fight something, then /reload")
    return
  end
  local out = {
    at = now(),
    count = 0,
    errors = 0,
    subevents = {},
    done = { damage = 0, heal = 0 },
    taken = { damage = 0, heal = 0 },
  }
  db.results.combatlog = out
  local f = CreateFrame("Frame")
  local ok, err = pcall(f.RegisterEvent, f, "COMBAT_LOG_EVENT_UNFILTERED")
  out.registered = ok
  if not ok then
    out.err = tostring(err)
    say("combatlog: the client refused the event: %s", out.err)
    return
  end
  combatListening = true
  local me = UnitGUID("player")
  local started = GetTime()
  f:SetScript("OnEvent", function(_, event)
    if event ~= "COMBAT_LOG_EVENT_UNFILTERED" then
      return
    end
    if GetTime() - started > COMBAT_SECONDS then
      f:UnregisterAllEvents()
      out.closed = now()
      return
    end
    onCombatProbeEvent(out, me)
  end)
  say("combatlog: registered; fight for up to %d seconds, then /reload", COMBAT_SECONDS)
end

-- /bprobe tracking: what the game's tracking says and what the minimap's tooltip answers over its
-- dots ("track beasts and track humanoids are not working on our
-- minimap"; map.md "Tracked creatures"). Records every tracking type as the client answers it (the
-- shape of GetTrackingInfo is assumed in forever-api.md), Compat.CreatureTrackingOn, the Map's own
-- sweep (style, stats, the dots it keeps), and one sweep of its own over the whole game minimap:
-- every text the tooltip answered, how many points answered it, the first answer's whole tooltip
-- data and what the Data knows of each name. A name the Data does not know is kept only as its
-- shape (letters as A and a): it may be another player's (CLAUDE.md §8). Out of combat; /reload saves.
local TRACK_STEP = 4 -- minimap pixels between two points of the sweep
local TRACK_PER_FRAME = 120 -- points per frame
local trackingRunning = false

local function letterShape(text)
  return (string.gsub(string.gsub(string.gsub(text, "%u", "A"), "%l", "a"), "[\128-\255]+", "?"))
end

local function splitNames(text)
  local out = {}
  text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
  text = string.gsub(text, "|r", "")
  text = string.gsub(text, "|T.-|t", "")
  text = string.gsub(text, "|A.-|a", "")
  for line in string.gmatch(text, "[^\r\n]+") do
    local name = string.match(line, "^%s*(.-)%s*$")
    if name ~= "" then
      out[#out + 1] = name
    end
  end
  return out
end

-- What the Data knows of a name: the NPCs and nodes of exactly that name, an NPC's flags.
local function dataOf(d, name)
  local out = { npc = {}, node = {} }
  local key = string.lower(name)
  for _, typ in ipairs({ "npc", "node" }) do
    local ok, hits = pcall(d.Find, d, typ, name, 8)
    for _, hit in ipairs(ok and hits or {}) do
      if type(hit.name) == "string" and string.lower(hit.name) == key then
        local r = d:Get(typ, hit.id)
        out[typ][#out[typ] + 1] = { id = hit.id, flags = clean(r and r.flags), kind = r and r.kind }
      end
    end
  end
  out.known = #out.npc > 0 or #out.node > 0
  return out
end

local function trackingTypes(out)
  out.types = {}
  if not (C_Minimap and type(C_Minimap.GetNumTrackingTypes) == "function") then
    out.typesErr = "no C_Minimap.GetNumTrackingTypes"
    return
  end
  local ok, n = pcall(C_Minimap.GetNumTrackingTypes)
  out.numTypes = clean(n)
  for i = 1, (ok and type(n) == "number") and n or 0 do
    out.types[i] = {
      info = try(C_Minimap.GetTrackingInfo, i),
      filter = try(C_Minimap.GetTrackingFilter, i),
    }
  end
end

-- The Map's own sweep, read through Core's module registry.
local function mapSweep(out)
  local core = rawget(_G, "Bastians")
  local ok, map = pcall(function()
    return core and core:GetModule("Map")
  end)
  local T = ok and map and map.Tracked
  if not T then
    out.map = { err = "no Map module or no Tracked" }
    return nil
  end
  local m = {}
  out.map = m
  m.style = try(map.Mini and map.Mini.Style)
  m.active = try(T.Active)
  m.available = try(T.Available)
  m.running = try(T.Running)
  m.stats = clean(T.stats)
  m.known = {}
  for i, k in ipairs(T.Known() or {}) do
    m.known[i] = { name = k.name, kind = k.kind, missed = k.missed, fine = k.fine }
  end
  return T
end

-- The minimap and the screen as the sweep finds them: is the game's minimap drawn and reachable,
-- at which zoom, and how the screen's units relate (UpdateMouseoverAtPoint's units are not
-- documented; Lueur, Mapzeroth and SilverDragon pass frame units times the effective scale).
local function trackingState(out)
  local st = {}
  out.state = st
  local core = rawget(_G, "Bastians")
  st.position = core and core.Coords and try(core.Coords.Player) -- continent, wx, wy, map, x, y
  st.visible = tryMethod(Minimap, "IsVisible")
  st.alpha = tryMethod(Minimap, "GetEffectiveAlpha")
  st.mouse = tryMethod(Minimap, "IsMouseEnabled")
  st.zoom = tryMethod(Minimap, "GetZoom")
  st.strata = tryMethod(Minimap, "GetFrameStrata")
  st.level = tryMethod(Minimap, "GetFrameLevel")
  st.uiScale = tryMethod(UIParent, "GetEffectiveScale")
  st.uiSize = tryMethod(UIParent, "GetSize")
  st.screen = { try(rawget(_G, "GetScreenWidth")), try(rawget(_G, "GetScreenHeight")) }
  st.physical = try(rawget(_G, "GetPhysicalScreenSize"))
  local util = rawget(_G, "InputUtil")
  st.gamepad = util and tryMethod(util, "IsGamepadUIEnabled") or "no InputUtil"
  local soft = rawget(_G, "SoftCursor")
  st.softCursorFrame = soft and tryMethod(soft, "IsShown") or "no SoftCursor frame"
end

-- The ways to write a point for UpdateMouseoverAtPoint: frame units times the effective scale (the
-- others' way and Tracked.lua's), plain UI units, physical pixels.
local function conventions(scale)
  local list = {
    { name = "scaled", step = TRACK_STEP, f = scale },
    { name = "ui", step = 2 * TRACK_STEP, f = 1 },
  }
  local physical = rawget(_G, "GetPhysicalScreenSize")
  local ok, _, ph = pcall(physical or error)
  local rootH = (UIParent:GetHeight() or 0) * (UIParent:GetEffectiveScale() or 0)
  if ok and type(ph) == "number" and rootH > 0 then
    list[#list + 1] = { name = "physical", step = 2 * TRACK_STEP, f = scale * ph / rootH }
  end
  return list
end

-- What a tooltip of the minimap says, read alike by the sweeps and the hover: each name with what
-- the Data knows of it; a name it does not know only as its shape (it may be another player's).
local function newEar(T)
  local core = rawget(_G, "Bastians")
  local d = core and core.GetService and core:GetService("data")
  local me, pet = UnitName("player"), UnitName("pet")
  local isSecret = rawget(_G, "issecretvalue")
  local splitter = T and T.Names or splitNames
  local verdicts = {} -- name -> what the Data knows of it, asked once
  local ear = {}

  function ear.verdict(name)
    local v = verdicts[name]
    if not v then
      v = (name ~= me and name ~= pet and d) and dataOf(d, name) or { known = false, npc = {}, node = {} }
      verdicts[name] = v
    end
    return v
  end

  -- A copy of the tooltip's data to keep: a text naming anything the Data does not know becomes its
  -- shape, and then no guid is kept either.
  function ear.scrubbed(data)
    local copy = clean(data)
    local masked = false
    for _, line in pairs(type(copy) == "table" and type(copy.lines) == "table" and copy.lines or {}) do
      for _, field in ipairs({ "leftText", "rightText" }) do
        local text = line[field]
        if type(text) == "string" then
          for _, name in ipairs(splitter(text)) do
            if not ear.verdict(name).known then
              line[field] = letterShape(text)
              masked = true
              break
            end
          end
        end
      end
    end
    if masked then
      copy.guid = nil
      for _, line in pairs(copy.lines) do
        line.guid = nil
      end
    end
    return copy
  end

  local function heard(sw, text, line, data, p)
    for _, name in ipairs(splitter(text)) do
      local e = sw.names[name]
      if not e then
        local v = ear.verdict(name)
        if v.known then
          e = { points = 0, data = v, tooltip = ear.scrubbed(data), text = text }
          e.first = p and { u = p[1], v = p[2] } or nil
          for _, other in ipairs(splitter(text)) do
            if not ear.verdict(other).known then
              e.text = letterShape(text) -- the raw line as the client wrote it, unless it names more
              break
            end
          end
          sw.names[name] = e
          sw.order[#sw.order + 1] = name
        elseif name == me then
          sw.player = (sw.player or 0) + 1
        elseif name == pet then
          sw.pet = (sw.pet or 0) + 1
        else
          local shape = letterShape(name)
          sw.shapes[shape] = (sw.shapes[shape] or 0) + 1
          sw.lineTypes = sw.lineTypes or {}
          sw.lineTypes[shape] = clean(line.type)
        end
      end
      if e then
        e.points = e.points + 1
      end
    end
  end

  -- One answer of the tooltip into `sw`; whether it said anything.
  function ear.read(sw, data, p)
    local lines = data and data.lines
    local any = false
    for j = 1, lines and #lines or 0 do
      local raw = lines[j].leftText
      if raw ~= nil and isSecret and isSecret(raw) then
        sw.secret = sw.secret + 1
        any = true
      elseif type(raw) == "string" and raw ~= "" then
        any = true
        heard(sw, raw, lines[j], data, p)
      end
    end
    if any then
      sw.answered = sw.answered + 1
    end
    return any
  end

  return ear
end

local function heardText(sw)
  local heard = {}
  for _, name in ipairs(sw.order) do
    local e = sw.names[name]
    local tag = #e.data.npc > 0 and "npc" or "node"
    heard[#heard + 1] = string.format("%s x%d [%s]", string.gsub(name, "|", "||"), e.points, tag)
    if #heard >= 12 then
      break
    end
  end
  local others = 0
  for _, n in pairs(sw.shapes) do
    others = others + n
  end
  if sw.player then
    heard[#heard + 1] = string.format("you x%d", sw.player)
  end
  if others > 0 then
    heard[#heard + 1] = string.format("unknown names x%d", others)
  end
  return #heard > 0 and table.concat(heard, ", ") or "nothing"
end

local function first(r)
  if r and r.ok and r.ret then
    return r.ret[1]
  end
  return nil
end

-- A recorded answer for the chat: "?" when the call failed or was missing.
local function answer(r)
  if r and r.ok and r.ret then
    return tostring(r.ret[1])
  end
  return "?"
end

local function trackingSummary(out)
  local on = {}
  for _, t in ipairs(out.types) do
    local info = t.info.ok and t.info.ret or {}
    local a = info[1]
    if type(a) == "table" and a.active == true then
      on[#on + 1] = string.format(
        "%s (%s/%s/%s)",
        tostring(a.name),
        tostring(a.type),
        tostring(a.subType),
        tostring(a.spellID)
      )
    elseif type(a) == "string" and info[3] == true then
      on[#on + 1] = string.format("%s (%s/%s/%s)", a, tostring(info[4]), tostring(info[5]), tostring(info[6]))
    end
  end
  local creature = out.creatureTrackingOn
  say(
    "tracking: %s types, on: %s; CreatureTrackingOn = %s",
    tostring(out.numTypes),
    #on > 0 and table.concat(on, ", ") or "none",
    creature and creature.ok and tostring(creature.ret[1]) or tostring(creature and creature.err)
  )
  local m = out.map
  if m.err then
    say("map: %s", m.err)
  else
    local s = m.stats or {}
    say(
      "map: style %s, active %s, running %s; sweeps %s, last answered %s, dots %s, kept %d",
      answer(m.style),
      answer(m.active),
      answer(m.running),
      tostring(s.sweeps),
      tostring(s.answered),
      tostring(s.dots),
      #m.known
    )
  end
  local st = out.state
  local physical = st.physical and st.physical.ok and st.physical.ret or {}
  say(
    "minimap: visible %s, alpha %s, mouse %s, zoom %s; ui scale %s, physical %sx%s",
    answer(st.visible),
    answer(st.alpha),
    answer(st.mouse),
    answer(st.zoom),
    answer(st.uiScale),
    tostring(physical[1]),
    tostring(physical[2])
  )
  for _, conv in ipairs(out.conventions) do
    local sw = out.sweeps[conv]
    say(
      "sweep %s (x%.3f, step %d): %d points, %d answered, %d secret%s; heard: %s",
      conv,
      sw.f,
      sw.step,
      sw.points,
      sw.answered,
      sw.secret,
      sw.err and (", error " .. sw.err) or "",
      heardText(sw)
    )
  end
  say("tracking: /reload to save the record")
end

-- One sweep of the whole game minimap in one way of writing the point, a share per frame.
local function sweepWith(ear, conv, geo, onDone)
  local sw = {
    f = conv.f,
    step = conv.step,
    points = 0,
    answered = 0,
    secret = 0,
    names = {},
    order = {},
    shapes = {},
  }
  local points = {}
  local row = -geo.h / 2 + conv.step / 2
  while row < geo.h / 2 do
    local col = -geo.w / 2 + conv.step / 2
    while col < geo.w / 2 do
      points[#points + 1] = { col, row }
      col = col + conv.step
    end
    row = row + conv.step
  end
  sw.points = #points
  local i = 1
  local function tick()
    if InCombatLockdown() then
      sw.cut = i
      onDone(sw, true)
      return
    end
    local last = math.min(i + TRACK_PER_FRAME - 1, #points)
    Minimap:SetUsingSoftCursor(true)
    local ok, err = pcall(function()
      for k = i, last do
        local p = points[k]
        Minimap:UpdateMouseoverAtPoint((geo.cx + p[1]) * conv.f, (geo.cy + p[2]) * conv.f)
        ear.read(sw, C_TooltipInfo.GetMinimapMouseover(), p)
      end
    end)
    pcall(Minimap.SetUsingSoftCursor, Minimap, false) -- never left on between two frames
    i = last + 1
    if not ok then
      sw.err = tostring(err)
      onDone(sw)
    elseif i > #points then
      sw.done = now()
      onDone(sw)
    else
      C_Timer.After(0, tick)
    end
  end
  C_Timer.After(0, tick)
end

local function probeTracking()
  if trackingRunning then
    say("tracking: running already")
    return
  end
  if InCombatLockdown() then
    say("tracking: not in combat (the tooltip's texts may be secret there)")
    return
  end
  local out = { at = now(), combat = false, sweeps = {}, conventions = {} }
  db.results.tracking = out
  db.results.trackingRuns = db.results.trackingRuns or {} -- every run: our style and the game's
  table.insert(db.results.trackingRuns, out)
  local _, class = UnitClass("player")
  out.class = class
  out.rotateMinimap = clean(GetCVar("rotateMinimap"))
  trackingTypes(out)
  local compat = rawget(_G, "Bastians") and Bastians.Compat
  out.creatureTrackingOn = compat and try(compat.CreatureTrackingOn)
    or { ok = false, err = "no Bastians.Compat" }
  local T = mapSweep(out)
  trackingState(out)
  local ear = newEar(T)

  local w, h = Minimap:GetWidth(), Minimap:GetHeight()
  local left, bottom, scale = Minimap:GetLeft(), Minimap:GetBottom(), Minimap:GetEffectiveScale()
  if not (w and w > 0 and h and h > 0 and left and bottom and scale and scale > 0) then
    out.err = "the minimap has no place on the screen"
    say("tracking: %s", out.err)
    return
  end
  out.size, out.scale = { w, h }, scale
  local radius = C_Minimap and C_Minimap.GetViewRadius and try(C_Minimap.GetViewRadius)
  out.viewRadius = first(radius)
  local geo = { w = w, h = h, cx = left + w / 2, cy = bottom + h / 2 }
  local list = conventions(scale)
  trackingRunning = true
  local n = 1
  local function nextSweep()
    local conv = list[n]
    sweepWith(ear, conv, geo, function(sw, combat)
      out.sweeps[conv.name] = sw
      out.conventions[#out.conventions + 1] = conv.name
      n = n + 1
      if combat then
        out.combat = true
      end
      if combat or n > #list then
        out.sweep = out.sweeps.scaled -- the way Tracked.lua asks
        out.done = now()
        trackingRunning = false
        trackingSummary(out)
      else
        nextSweep()
      end
    end)
  end
  say("tracking: sweeping the game minimap %d ways; stand still", #list)
  nextSweep()
end

-- /bprobe tracking hover: for HOVER_SECONDS, what the minimap's tooltip says under the real mouse
-- (no soft cursor), and which frame the mouse is over. Shows whether the tooltip's data answers at
-- all on this build: in the game's style, move the mouse over the dots.
local HOVER_SECONDS = 15
local hoverFrame
local function trackingHover()
  if trackingRunning then
    say("tracking: running already")
    return
  end
  local out = { at = now(), seconds = HOVER_SECONDS, frames = 0, answered = 0, secret = 0 }
  out.names, out.order, out.shapes, out.foci = {}, {}, {}, {}
  db.results.trackingHover = out
  local core = rawget(_G, "Bastians")
  local ok, map = pcall(function()
    return core and core:GetModule("Map")
  end)
  local ear = newEar(ok and map and map.Tracked or nil)
  local started = GetTime()
  local foci = rawget(_G, "GetMouseFoci")
  hoverFrame = hoverFrame or CreateFrame("Frame")
  trackingRunning = true
  hoverFrame:SetScript("OnUpdate", function(self)
    if GetTime() - started > HOVER_SECONDS then
      self:SetScript("OnUpdate", nil)
      trackingRunning = false
      out.done = now()
      say("tracking hover: %d frames, %d answered; heard: %s", out.frames, out.answered, heardText(out))
      local where = {}
      for name, count in pairs(out.foci) do
        where[#where + 1] = string.format("%s x%d", name, count)
      end
      table.sort(where)
      say("tracking hover: the mouse was over %s; /reload to save", table.concat(where, ", "))
      return
    end
    out.frames = out.frames + 1
    local okRead, err = pcall(function()
      ear.read(out, C_TooltipInfo.GetMinimapMouseover())
    end)
    if not okRead then
      out.err = tostring(err)
    end
    local okFoci, name = pcall(function()
      local list = foci and foci()
      local top = list and list[1]
      return top and top.GetName and top:GetName() or (top and "<unnamed>" or "<none>")
    end)
    if okFoci then
      out.foci[name] = (out.foci[name] or 0) + 1
    else
      out.fociErr = tostring(name)
    end
  end)
  say("tracking hover: move the mouse over the dots on the game's minimap for %d seconds", HOVER_SECONDS)
end

-- /bprobe ground: the game's minimap with its ground switched off (bring the
-- tracking dots back to Bastian's styles another way, since Forever answers no addon's point).
-- Blizzard's HybridMinimap does it on Forever too: its own map canvas, a child of the Minimap in
-- the BACKGROUND strata, under the dots, C_Minimap.SetDrawGroundTextures(false), the canvas zoomed
-- by C_Minimap.GetViewRadius(). Does Forever honour the call, is what is left see-through, do the
-- dots and the player's arrow stay? In one of Bastian's styles the game's minimap is lifted above
-- our tiles while its ground is off, so its dots lie on our map (at the game's zoom, not ours: they
-- line up only where both zooms agree). The view radius at every zoom of the game's minimap is the
-- scale our tiles would need. A second call puts everything back. Out of combat.
local groundSaved -- what /bprobe ground changed: { strata, level, camLevel }
local groundTicker -- keeps Bastian's view on the game minimap's centre and scale while the ground is off

-- The game's dots sit where the game's minimap puts them: around its centre (the player), at its
-- own scale, half its width for C_Minimap.GetViewRadius() yards. Bastian's tiles show the same
-- ground under them only while our view follows the player and draws at that scale (owner, Forever
-- 14.11.2026: a node stood 88 px beside its place with the view dragged away). Sets both; returns
-- what it measured, or nil and why.
local function fitToGame(mini)
  local cam, view = mini.Camera(), mini.View()
  local radius = C_Minimap.GetViewRadius()
  if not (cam and view and type(radius) == "number" and radius > 0) then
    return nil, "no camera, view or radius"
  end
  -- half the game's minimap in our view's pixels
  local half = Minimap:GetWidth() / 2 * Minimap:GetEffectiveScale() / view:GetEffectiveScale()
  local base = cam:Scale() / 2 ^ cam.level -- pixels per yard at level 0
  local level = math.log(half / radius / base) / math.log(2)
  local fit = {
    radius = radius,
    half = half,
    was = cam.level,
    level = level,
    following = mini.Following(),
    minimap = Minimap:GetWidth(),
    view = view:GetWidth(),
  }
  if not fit.following or math.abs(cam.level - level) > 0.001 then
    cam.level = level
    mini.Recentre() -- follows the player again and draws
    fit.changed = true
  end
  return fit
end

-- /bprobe ground level: where the game's minimap goes in our view's stack, and which clicks reach
-- it there (counted by button while the ground is off; a pin of ours above it takes its own).
local GROUND_LEVEL = 12
local groundClicks, groundHooked

local function hookGroundClicks()
  if groundHooked then
    return
  end
  groundHooked = pcall(Minimap.HookScript, Minimap, "OnMouseUp", function(_, button)
    if groundClicks and type(button) == "string" then
      groundClicks[button] = (groundClicks[button] or 0) + 1
    end
  end)
end

-- The type of a frame's method, the lookup protected: a frame may lack it, and looking can raise.
local function methodType(obj, name)
  local ok, fn = pcall(function()
    return obj[name]
  end)
  return ok and type(fn) or "error"
end

local function stopGroundTicker()
  if groundTicker then
    groundTicker:Cancel()
    groundTicker = nil
  end
end

local function zoomRadii()
  local out = {}
  local zoom = first(tryMethod(Minimap, "GetZoom"))
  local levels = first(tryMethod(Minimap, "GetZoomLevels")) or 6
  for z = 0, levels - 1 do
    local set = tryMethod(Minimap, "SetZoom", z)
    out[#out + 1] = { zoom = z, set = set.ok, radius = first(try(C_Minimap.GetViewRadius)) }
  end
  if zoom then
    tryMethod(Minimap, "SetZoom", zoom)
  end
  return out, levels
end

local function probeGround(arg)
  if InCombatLockdown() then
    say("ground: not in combat")
    return
  end
  local api = rawget(_G, "C_Minimap")
  if not (api and type(api.SetDrawGroundTextures) == "function") then
    say("ground: this client has no C_Minimap.SetDrawGroundTextures")
    return
  end
  local core = rawget(_G, "Bastians")
  local ok, map = pcall(function()
    return core and core:GetModule("Map")
  end)
  -- the Map's own dots layer (ADR 0078) holds the same switch: one owner at a time
  local held = ok and map and map.Mini and type(map.Mini.DotsShown) == "function" and map.Mini.DotsShown()
  if held and not groundSaved then
    say("ground: Bastian's minimap holds the ground (its dots layer); switch its tracking setting off first")
    return
  end
  local out = db.results.ground or { runs = {} }
  db.results.ground = out
  local run = { at = now(), indoors = try(rawget(_G, "IsIndoors")) }
  out.runs[#out.runs + 1] = run
  run.before = try(api.GetDrawGroundTextures)
  run.style = ok and map and map.Mini and first(try(map.Mini.Style)) or "no Map"
  -- off now, by this session's call or one before a /reload: put it back
  if groundSaved or first(run.before) == false then
    run.action = "back on"
    run.set = try(api.SetDrawGroundTextures, true)
    stopGroundTicker()
    groundClicks = nil
    if groundSaved then
      tryMethod(Minimap, "SetFrameStrata", groundSaved.strata)
      tryMethod(Minimap, "SetFrameLevel", groundSaved.level)
      if groundSaved.camLevel and ok and map and map.Mini then
        pcall(function()
          map.Mini.Camera().level = groundSaved.camLevel
          map.Mini.Render()
        end)
      end
    end
    groundSaved = nil
    run.after = try(api.GetDrawGroundTextures)
    say(
      "ground: back on (the client says %s); the game's minimap is where it was",
      tostring(first(run.after))
    )
    return
  end
  run.action = "off"
  local radii, levels = zoomRadii()
  run.zooms, run.levels = radii, levels
  run.set = try(api.SetDrawGroundTextures, false)
  run.after = try(api.GetDrawGroundTextures)
  groundSaved = {
    strata = first(tryMethod(Minimap, "GetFrameStrata")),
    level = first(tryMethod(Minimap, "GetFrameLevel")),
  }
  run.saved = { strata = groundSaved.strata, level = groundSaved.level }
  run.zoom = first(tryMethod(Minimap, "GetZoom"))
  run.mouse = {
    enabled = first(tryMethod(Minimap, "IsMouseEnabled")),
    propagateClicks = methodType(Minimap, "SetPropagateMouseClicks"),
    propagateMotion = methodType(Minimap, "SetPropagateMouseMotion"),
    passThrough = methodType(Minimap, "SetPassThroughButtons"),
  }
  if run.style ~= "game" and run.style ~= "no Map" then
    if arg == "level" then
      -- ADR 0078, G1 and G2: above our tiles by frame level inside our view, not by strata, so
      -- that Bastian's pins stay above the game's minimap and keep their mouse. The view's tiles
      -- sit 10 levels above the view, the pins' overlay 15 (Mini.lua, Minimap.lua).
      local okView, viewLevel = pcall(function()
        return map.Mini.View():GetFrameLevel()
      end)
      run.variant = "level"
      run.viewLevel = okView and viewLevel or nil
      run.raised = okView and tryMethod(Minimap, "SetFrameLevel", viewLevel + GROUND_LEVEL).ok or false
      run.clicks = {}
      groundClicks = run.clicks
      hookGroundClicks()
    else
      run.raised = tryMethod(Minimap, "SetFrameStrata", "HIGH").ok
    end
    -- our view onto the game minimap's centre and scale, and kept there: a wheel or a drag would
    -- part the dots from the ground again
    local mini = map.Mini
    if type(mini.Camera) == "function" and type(mini.Recentre) == "function" then
      local okFit, fit, why = pcall(fitToGame, mini)
      run.fit = okFit and (fit or { err = why }) or { err = tostring(fit) }
      if okFit and fit then
        groundSaved.camLevel = fit.was
        run.refits = 0
        groundTicker = C_Timer.NewTicker(0.5, function()
          local okAgain, again = pcall(fitToGame, mini)
          if okAgain and again and again.changed then
            run.refits = run.refits + 1
          end
        end)
      end
    end
  end
  local list = {}
  for _, r in ipairs(radii) do
    list[#list + 1] = string.format("%d=%s", r.zoom, r.radius and string.format("%.0f", r.radius) or "?")
  end
  say(
    "ground: off (the client said %s before, %s now)%s",
    tostring(first(run.before)),
    tostring(first(run.after)),
    run.raised and "; the game's minimap lies over Bastian's tiles" or ""
  )
  if run.variant == "level" then
    say("ground: by frame level, under Bastian's pins. Hover a dot, click a pin of ours, click the")
    say("ground: map, right click it, turn the wheel; the clicks the game's minimap got are counted")
  end
  if run.fit and not run.fit.err then
    say(
      "ground: Bastian's view follows you at the game's scale (%.0f yards to the edge, level %.2f, was %.2f)",
      run.fit.radius,
      run.fit.level,
      run.fit.was
    )
  elseif run.fit then
    say("ground: could not fit Bastian's view to the game's: %s", tostring(run.fit.err))
  end
  say("ground: view radius in yards per zoom: %s", table.concat(list, ", "))
  say("ground: look, take a screenshot, then /bprobe ground puts it back; /reload saves the record")
end

-- ---------------------------------------------------------------------------------------------
-- /bprobe chatbasics <log | settings [n] | menus [channels | emotes] | meter | whisper>: what the
-- Chat's two decks lean on (plan-chat-two-decks.md §13, X15 to X19; the
-- game's combat log as the live window, the fight's summary inside ours, nothing of the game's
-- chat lost). Frame states, types, counts and the player's own numbers only, never another
-- player's name or words (CLAUDE.md §8).
-- ---------------------------------------------------------------------------------------------

local function parentName(f)
  local ok, parent = pcall(f.GetParent, f)
  if not ok or type(parent) ~= "table" then
    return "<none>"
  end
  local okName, name = pcall(parent.GetName, parent)
  return okName and type(name) == "string" and name or "<unnamed>"
end

-- What a frame says of itself; { missing = true } for a global that is no frame.
local function frameState(f)
  if type(f) ~= "table" or type(f.GetParent) ~= "function" then
    return { missing = true }
  end
  return {
    shown = first(tryMethod(f, "IsShown")),
    visible = first(tryMethod(f, "IsVisible")),
    parent = parentName(f),
    lines = first(tryMethod(f, "GetNumMessages")),
    children = first(tryMethod(f, "GetNumChildren")),
  }
end

local function basicsRun(id)
  local out = db.results[id] or { runs = {} }
  db.results[id] = out
  local run = { at = now(), combat = InCombatLockdown() and true or false }
  out.runs[#out.runs + 1] = run
  return run
end

-- X15. The game's combat log as a window of its own: the frame and its tab out of whatever parent
-- hides them (Bastian's Chat keeps the game's chat frames under a hidden parent), onto the
-- screen's middle, shown. Showing it runs the game's own OnShow, which switches the client's
-- stream on and shows the filter buttons (Blizzard_CombatLog.lua). A second call puts both back.
local logSaved -- what the first call moved: { { frame, parent, points, shown } }
local LOG_LOOKS = { 15, 45 } -- seconds after the show at which the frame's line count is read

local function takeOut(f)
  local saved = { frame = f, parent = f:GetParent(), shown = f:IsShown(), points = {} }
  for i = 1, f:GetNumPoints() do
    saved.points[i] = { f:GetPoint(i) }
  end
  if #saved.points < 2 then
    saved.width, saved.height = f:GetWidth(), f:GetHeight()
  end
  return saved
end

local function putBack(saved)
  local f = saved.frame
  f:SetParent(saved.parent)
  f:ClearAllPoints()
  for _, p in ipairs(saved.points) do
    f:SetPoint(p[1], p[2], p[3], p[4], p[5])
  end
  if saved.width then
    f:SetSize(saved.width, saved.height)
  end
  if not saved.shown then
    f:Hide() -- as the game's dock does with a tab that is not selected
  end
end

local function combatLogParts()
  local frame = rawget(_G, "COMBATLOG") or rawget(_G, "ChatFrame2")
  if type(frame) ~= "table" or type(frame.GetParent) ~= "function" then
    return nil
  end
  local okName, name = pcall(frame.GetName, frame)
  local tab = okName and type(name) == "string" and rawget(_G, name .. "Tab") or nil
  return frame, tab, rawget(_G, "CombatLogQuickButtonFrame_Custom")
end

local function logStates(frame, tab, quick)
  return { frame = frameState(frame), tab = frameState(tab), quick = frameState(quick) }
end

local function probeChatLog()
  local frame, tab, quick = combatLogParts()
  if not frame then
    say("chatbasics log: this client has no combat log frame (COMBATLOG, ChatFrame2)")
    return
  end
  local run = basicsRun("chatlog")
  run.loaded = try(resolve("C_AddOns.IsAddOnLoaded"), "Blizzard_CombatLog")
  run.restricted = try(resolve("C_CombatLog.IsCombatLogRestricted"))
  run.before = logStates(frame, tab, quick)
  if logSaved then
    run.action = "back"
    for i = #logSaved, 1, -1 do
      local ok, err = pcall(putBack, logSaved[i])
      if not ok then
        run.err = tostring(err)
      end
    end
    logSaved = nil
    run.after = logStates(frame, tab, quick)
    say("chatbasics log: the combat log is back where it was%s", run.err and " (with an error)" or "")
    return
  end
  run.action = "out"
  logSaved = {}
  local ok, err = pcall(function()
    logSaved[#logSaved + 1] = takeOut(frame)
    frame:SetParent(UIParent)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -40)
    frame:SetSize(430, 180)
    if type(tab) == "table" and type(tab.SetParent) == "function" then
      logSaved[#logSaved + 1] = takeOut(tab)
      tab:SetParent(UIParent)
      tab:ClearAllPoints()
      tab:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 26) -- over the row of filter buttons
      tab:Show()
    end
    frame:Show()
  end)
  run.moved = ok
  run.err = not ok and tostring(err) or nil
  run.after = logStates(frame, tab, quick)
  run.looks = {}
  for _, seconds in ipairs(LOG_LOOKS) do
    C_Timer.After(seconds, function()
      if not logSaved then
        return -- put back before the look
      end
      local look = logStates(frame, tab, quick)
      look.seconds = seconds
      look.combat = InCombatLockdown() and true or false
      run.looks[#run.looks + 1] = look
      say(
        "chatbasics log: after %d s the combat log holds %s lines, its buttons are %s",
        seconds,
        tostring(look.frame.lines),
        look.quick.visible and "visible" or "not visible"
      )
    end)
  end
  if not ok then
    say("chatbasics log: moving the combat log failed: %s", run.err)
    return
  end
  say(
    "chatbasics log: the game's combat log stands in the middle (%s, its filter buttons %s)",
    run.after.frame.visible and "visible" or "NOT visible",
    run.after.quick.visible and "visible" or "not visible"
  )
  say("chatbasics log: fight, click its filter buttons, cast a spell from the chat line with /cast;")
  say("chatbasics log: then /bprobe chatbasics log puts it back, and /reload saves the record")
end

-- X16. The game's Chat Settings from addon code. With a window number the dialog is first told
-- which chat window to edit (the global the game's tab menu sets), which is the riskier way.
local SETTINGS_CALLS = {
  "ChatConfigFrame",
  "ShowUIPanel",
  "HideUIPanel",
  "CURRENT_CHAT_FRAME_ID",
  "FCF_GetCurrentChatFrame",
  "FCF_GetCurrentChatFrameID",
  "ChatConfigFrame_OnShow",
  "ChatConfig_UpdateChatSettings",
}

local function probeChatSettings(arg)
  local run = basicsRun("chatsettings")
  run.calls = {}
  for _, path in ipairs(SETTINGS_CALLS) do
    run.calls[path] = type(resolve(path))
  end
  run.current = clean(rawget(_G, "CURRENT_CHAT_FRAME_ID"))
  local dialog = rawget(_G, "ChatConfigFrame")
  if type(dialog) ~= "table" then
    say("chatbasics settings: this client has no ChatConfigFrame")
    return
  end
  local window = tonumber(arg)
  if window then
    run.window = window
    rawset(_G, "CURRENT_CHAT_FRAME_ID", window)
  end
  run.before = frameState(dialog)
  run.panel = try(rawget(_G, "ShowUIPanel"), dialog)
  if not (run.panel.ok and first(tryMethod(dialog, "IsShown"))) then
    run.show = tryMethod(dialog, "Show")
  end
  run.after = frameState(dialog)
  local okFrame, edited = pcall(function()
    return FCF_GetCurrentChatFrame():GetName()
  end)
  run.edits = okFrame and edited or nil
  say(
    "chatbasics settings: the game's Chat Settings are %s (editing %s%s)",
    run.after.shown and "open" or "NOT open",
    tostring(run.edits),
    window and ", set by the probe" or ""
  )
  say("chatbasics settings: switch a message type off and on, close, /cast a spell, then /reload")
end

-- X19. The emote and language menu and the channel list, whose buttons Bastian's Chat hides.
local MENU_CALLS = {
  "ChatFrameMenuButton",
  "ChatFrameChannelButton",
  "ChannelFrame",
  "ToggleChannelFrame",
  "ChatMenu",
  "EmoteMenu",
  "LanguageMenu",
  "VoiceMacroMenu",
  "ChatFrameMenuButtonMixin",
  "Menu.GetManager",
  "MenuUtil.CreateContextMenu",
}

local function probeChatMenus(arg)
  local run = basicsRun("chatmenus")
  run.calls = {}
  for _, path in ipairs(MENU_CALLS) do
    run.calls[path] = type(resolve(path))
  end
  local menuButton = rawget(_G, "ChatFrameMenuButton")
  local channelButton = rawget(_G, "ChatFrameChannelButton")
  local channels = rawget(_G, "ChannelFrame")
  run.before = {
    menuButton = frameState(menuButton),
    channelButton = frameState(channelButton),
    channels = frameState(channels),
  }
  run.tried = arg
  if arg == "channels" then
    run.toggle = try(rawget(_G, "ToggleChannelFrame"))
    if not run.toggle.ok and type(channelButton) == "table" then
      run.click = tryMethod(channelButton, "Click")
    end
  elseif arg == "emotes" then
    run.click = type(menuButton) == "table" and tryMethod(menuButton, "Click") or nil
    run.menuOpen = type(menuButton) == "table" and tryMethod(menuButton, "IsMenuOpen") or nil
  end
  run.after = {
    menuButton = frameState(menuButton),
    channelButton = frameState(channelButton),
    channels = frameState(rawget(_G, "ChannelFrame")),
  }
  if arg == "channels" then
    say("chatbasics menus: the channel list is %s", run.after.channels.shown and "open" or "NOT open")
  elseif arg == "emotes" then
    say(
      "chatbasics menus: clicked the game's chat menu button (%s); is a menu on the screen?",
      run.click and run.click.ok and "no error" or "an error, or no button"
    )
  else
    say("chatbasics menus: recorded what exists; '... menus channels' or '... menus emotes' opens one")
  end
end

-- X17. What the game's whisper handling keeps while its frames are hidden. Never the name: only
-- whether there is one.
local WHISPER_CALLS = {
  "ChatFrameUtil.ReplyTell",
  "ChatFrameUtil.ReplyTell2",
  "ChatFrameUtil.GetLastTellTarget",
  "ChatFrameUtil.GetLastToldTarget",
  "ChatFrame_ReplyTell",
  "ChatEdit_GetLastTellTarget",
  "ChatEdit_GetLastToldTarget",
  "BNToastFrame",
  "ChatAlertFrame",
  "C_ChatInfo.InChatMessagingLockdown",
}
local WHISPER_CVARS = { "whisperMode", "chatStyle", "showToastWindow", "showToastOnline", "chatBubbles" }

local function hasTarget(fn)
  if type(fn) ~= "function" then
    return "missing"
  end
  local ok, name = pcall(fn)
  if not ok then
    return "error"
  end
  local isSecret = rawget(_G, "issecretvalue")
  if name ~= nil and isSecret and isSecret(name) then
    return "secret"
  end
  return type(name) == "string" and name ~= "" and "yes" or "no"
end

local function probeChatWhisper()
  local run = basicsRun("chatwhisper")
  run.calls = {}
  for _, path in ipairs(WHISPER_CALLS) do
    run.calls[path] = type(resolve(path))
  end
  run.cvars = {}
  for _, name in ipairs(WHISPER_CVARS) do
    run.cvars[name] = first(try(resolve("C_CVar.GetCVar") or rawget(_G, "GetCVar"), name))
  end
  run.lastTell =
    hasTarget(resolve("ChatFrameUtil.GetLastTellTarget") or rawget(_G, "ChatEdit_GetLastTellTarget"))
  run.lastTold =
    hasTarget(resolve("ChatFrameUtil.GetLastToldTarget") or rawget(_G, "ChatEdit_GetLastToldTarget"))
  run.toast = frameState(rawget(_G, "BNToastFrame"))
  run.alert = frameState(rawget(_G, "ChatAlertFrame"))
  run.lockdown = try(resolve("C_ChatInfo.InChatMessagingLockdown"))
  say(
    "chatbasics whisper: the game knows someone to reply to: %s; someone you wrote to: %s",
    run.lastTell,
    run.lastTold
  )
  say("chatbasics whisper: after a whisper from a second character try the reply key, /r and Tab")
end

-- X18. The client's own meter after a fight: which sessions, which numbers, and when they stop
-- being secret. Of a session only the field names, its numbers and the player's own row are kept:
-- the other rows carry other players' names.
local METER_TYPES = { "DamageDone", "Dps", "HealingDone", "DamageTaken", "Deaths" }
local METER_EVENTS = {
  "PLAYER_REGEN_DISABLED",
  "PLAYER_REGEN_ENABLED",
  "DAMAGE_METER_COMBAT_SESSION_UPDATED",
  "DAMAGE_METER_RESET",
  "ADDON_RESTRICTION_STATE_CHANGED",
}
local METER_AFTER = { 0, 1, 3, 10, 30 } -- seconds after the fight's end at which the meter is read
local METER_SNAPSHOTS = 60
local meterListening = false

-- The numbers and booleans of a table, a secret one as "<secret>", and every field's type.
local function plainFields(t)
  local out = { fields = {}, values = {} }
  local isSecret = rawget(_G, "issecretvalue")
  for k, v in pairs(t) do
    if type(k) == "string" then
      if v ~= nil and isSecret and isSecret(v) then
        out.fields[k] = "secret"
        out.values[k] = "<secret>"
      else
        out.fields[k] = type(v)
        if type(v) == "number" or type(v) == "boolean" then
          out.values[k] = v
        end
      end
    end
  end
  return out
end

local function meterSummary(session)
  local isSecret = rawget(_G, "issecretvalue")
  if session ~= nil and isSecret and isSecret(session) then
    return { secret = true }
  end
  if type(session) ~= "table" then
    return { type = type(session) }
  end
  local out = plainFields(session)
  local sources = session.combatSources
  if type(sources) == "table" and not (isSecret and isSecret(sources)) then
    out.sources = #sources
    for _, source in ipairs(sources) do
      local okMine, mine = pcall(function()
        return source.isLocalPlayer == true
      end)
      if okMine and mine then
        out.me = plainFields(source)
        break
      end
    end
  end
  return out
end

local function meterSnapshot(out, label)
  if #out.snapshots >= METER_SNAPSHOTS then
    return nil
  end
  local api = C_DamageMeter
  local snap = { at = now(), label = label, combat = InCombatLockdown() and true or false }
  out.snapshots[#out.snapshots + 1] = snap
  snap.available = try(api.IsDamageMeterAvailable)
  local kinds = resolve("Enum.AddOnRestrictionType")
  snap.restricted = try(resolve("C_RestrictedActions.GetAddOnRestrictionState"), kinds and kinds.Combat)
  local okSessions, sessions = pcall(function()
    return #api.GetAvailableCombatSessions()
  end)
  snap.sessions = okSessions and sessions or tostring(sessions)
  local sessionTypes, meterTypes = resolve("Enum.DamageMeterSessionType"), resolve("Enum.DamageMeterType")
  local current = sessionTypes and sessionTypes.Current
  snap.duration = try(api.GetSessionDurationSeconds, current)
  snap.types = {}
  for _, name in ipairs(METER_TYPES) do
    local id = meterTypes and meterTypes[name]
    if id ~= nil then
      -- the summary inside the pcall too: a secret among the fields raises when it is touched
      local ok, summary = pcall(function()
        return meterSummary(api.GetCombatSessionFromType(current, id))
      end)
      snap.types[name] = ok and summary or { err = tostring(summary) }
    end
  end
  local okRecap, recap = pcall(function()
    return C_DeathRecap.GetRecapEvents()
  end)
  snap.recapEvents = okRecap and type(recap) == "table" and #recap or nil
  return snap
end

local function meterLine(snap)
  local done = snap.types.DamageDone
  local mine = done and done.me and done.me.values.totalAmount
  return string.format(
    "chatbasics meter: %s: %s sessions, duration %s, my damage %s",
    snap.label,
    tostring(snap.sessions),
    tostring(first(snap.duration)),
    tostring(mine)
  )
end

local function probeChatMeter()
  local api = rawget(_G, "C_DamageMeter")
  if type(api) ~= "table" then
    say("chatbasics meter: this client has no C_DamageMeter")
    return
  end
  local out = db.results.chatmeter or { snapshots = {}, events = {} }
  db.results.chatmeter = out
  out.at = now()
  out.functions = {}
  for name, v in pairs(api) do
    out.functions[name] = type(v)
  end
  out.meterTypes = clean(resolve("Enum.DamageMeterType"))
  out.sessionTypes = clean(resolve("Enum.DamageMeterSessionType"))
  out.recap = type(resolve("C_DeathRecap.GetRecapEvents"))
  local snap = meterSnapshot(out, "now")
  if snap then
    say(meterLine(snap))
  end
  if meterListening then
    say("chatbasics meter: listening already; fight alone and in a group, then /reload")
    return
  end
  meterListening = true
  local f = CreateFrame("Frame")
  out.registered = {}
  for _, event in ipairs(METER_EVENTS) do
    out.registered[event] = pcall(f.RegisterEvent, f, event)
  end
  f:SetScript("OnEvent", function(_, event)
    out.events[event] = (out.events[event] or 0) + 1
    if event == "PLAYER_REGEN_DISABLED" then
      C_Timer.After(3, function()
        meterSnapshot(out, "in the fight")
      end)
    elseif event == "PLAYER_REGEN_ENABLED" then
      for _, seconds in ipairs(METER_AFTER) do
        C_Timer.After(seconds, function()
          local after = meterSnapshot(out, seconds .. " s after the fight")
          if after and (seconds == 0 or seconds == 10) then
            say(meterLine(after))
          end
        end)
      end
    end
  end)
  say("chatbasics meter: listening; fight once alone and once in a group, wait 30 s, then /reload")
end

local function probeChatBasics(arg)
  local part, rest = string.match(arg or "", "^(%S*)%s*(.-)%s*$")
  if rest == "" then
    rest = nil
  end
  if part == "log" then
    probeChatLog()
  elseif part == "settings" then
    probeChatSettings(rest)
  elseif part == "menus" then
    probeChatMenus(rest)
  elseif part == "whisper" then
    probeChatWhisper()
  elseif part == "meter" then
    probeChatMeter()
  else
    say("chatbasics: log | settings [window] | menus [channels | emotes] | whisper | meter")
  end
end

local HELP = {
  "/bprobe all  - P1, P2, P3, P5, P6, P10 (automatic probes)",
  "/bprobe resize - the drags of a window's corner recorded by themselves (the resize jump); resize clear",
  "/bprobe booktech - a turned word, a gradient, a line: do they draw on this client (the book's look)",
  "/bprobe portrait - a creature's display from its model and the game's portrait of it (ADR 0090)",
  "/bprobe booklook - Bastian's Book measured at three widths against book-look.md, with screenshots",
  "/bprobe booklook small - the same at the scale of a 1,920 x 1,080 screen (768 units high)",
  "/bprobe bookmodel - an object's model in a model frame, a model as a dark shape (R4.9, the album)",
  "/bprobe bookreveal [uiMapID] - a zone as you explored it beside the zone with every overlay (R4.5)",
  "/bprobe perf - Core's performance snapshot (taken by itself 30 s after every login)",
  "/bprobe w2 - bookmodel, bookreveal, booklook and booklook small in a row (once by themselves)",
  "/bprobe windows - every app's window opened in turn, photographed, its head measured, what"
    .. " overflows named, at three widths and the small screen's scale (W4, W5)",
  "/bprobe chat - Chat version 3: the calls it needs, the item level, whisper flags (counts only)",
  "/bprobe combatlog - Forever only: may addons read the combat log, a minute of it (X11)",
  "/bprobe books - the Library books: the globals that name them, every book opened, their events (A3.2)",
  "/bprobe tracking - the game's tracking and what the minimap's tooltip says over its dots (Track Beasts)",
  "/bprobe tracking hover - 15 s of what the minimap's tooltip says under the real mouse",
  "/bprobe ground - the game's minimap without its ground, over Bastian's tiles; again puts it back",
  "/bprobe ground level - the same by frame level, under Bastian's pins (ADR 0078, G1 and G2)",
  "/bprobe chatbasics log - the game's combat log as a window of its own; again puts it back (X15)",
  "/bprobe chatbasics settings [n] | menus [channels | emotes] | whisper | meter - the game's Chat"
    .. " Settings, its menus, what it keeps of whispers, its meter after a fight (X16 to X19)",
  "/bprobe p1 | p2 | p3 | p5 [fileID or path] | p6 | p10  - one probe",
  "/bprobe p4 <label>  - record a landmark at your position (and your target: NPC, object, node)",
  "/bprobe alpha  - the Map_Art overview cells over red (transparency test)",
  "/bprobe mask [fdid name] - a native coast tile with its Map_Art sea mask over red",
  "/bprobe maskvariants - which of four test mask files the client loads",
  "/bprobe minimaps [uiMapID] [style] - a zone drawn small from a map style's cells (PA6)",
  "P7, trainer and merchant record by themselves: open a flight map, take a flight,"
    .. " open a trainer or a vendor",
  "/bprobe buttons [n] - n fake minimap buttons (default 50) for the button box; 0 removes them",
  "/bprobe status | hide | reset",
}

-- Fake minimap buttons in LibDBIcon's shape ("simulate up to 50 icons" in the
-- box of Bastian's minimap): named LibDBIcon10_BastiansTest<n>, 31 px, a tinted icon, a tooltip.
local fakeButtons = {}
local function makeFakeButtons(n)
  for _, b in ipairs(fakeButtons) do
    b:Hide()
  end
  for i = 1, n do
    local b = fakeButtons[i]
    if not b then
      b = CreateFrame("Button", "LibDBIcon10_BastiansTest" .. i, Minimap)
      b:SetSize(31, 31)
      b:SetFrameStrata("MEDIUM")
      b:SetFrameLevel(8)
      local icon = b:CreateTexture(nil, "ARTWORK")
      icon:SetSize(20, 20)
      icon:SetPoint("CENTER")
      icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
      icon:SetVertexColor(0.4 + 0.6 * ((i * 7) % 10) / 10, 0.4 + 0.6 * ((i * 3) % 10) / 10, 0.5)
      local ring = b:CreateTexture(nil, "OVERLAY")
      ring:SetSize(53, 53)
      ring:SetPoint("TOPLEFT")
      ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
      b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Test button " .. i)
        GameTooltip:Show()
      end)
      b:SetScript("OnLeave", function()
        GameTooltip:Hide()
      end)
      b:SetScript("OnClick", function()
        say("test button %d clicked", i)
      end)
      fakeButtons[i] = b
    end
    local angle = math.rad(i * 360 / math.max(1, n))
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(angle), 80 * math.sin(angle))
    b:Show()
  end
  say("%d fake minimap buttons; hover the box's opener on Bastian's minimap", n)
end

-- ---------------------------------------------------------------------------------------------
-- /bprobe minimaps [uiMapID] [style]: a zone drawn small from a map style's cells (ADR 0056, PA6:
-- "the mini map is the button, in the chosen map style"; unproven: the styles' tiles drawn small,
-- cost and sharpness). The zone (default: where the player stands) at three sizes, each from
-- the style's far cells (8 x 8 ADT tiles in 512 px) and near cells (4 x 4 tiles in 1024 px),
-- with the client's default filter and with TRILINEAR; beside them the client's own painting of
-- the zone; under them 24 zones at once from the far cells. A cell is cut to the zone by its
-- texture coordinates, so nothing is clipped by a frame. Recorded: the textures per picture, the
-- cells the client did not load, the time to build, and the frames before and after.
-- ---------------------------------------------------------------------------------------------

local MINI_ZONES = { -- Eastern Kingdoms, then Kalimdor: the uiMapIDs of the old world's zones
  1429,
  1436,
  1433,
  1431,
  1426,
  1432,
  1437,
  1424,
  1417,
  1425,
  1422,
  1423,
  1420,
  1421,
  1416,
  1418,
  1427,
  1428,
  1430,
  1434,
  1435,
  1419,
  1411,
  1412,
  1413,
  1438,
  1439,
  1440,
  1441,
  1442,
  1443,
  1444,
  1445,
  1446,
  1447,
  1448,
  1449,
  1450,
  1451,
  1452,
}
-- rows of sizes; the window fits a 1080p screen (1365 by 768 units)
local MINI_ROWS = { { { 250, 167, "large" } }, { { 140, 93, "medium" }, { 56, 37, "tile" } } }
local MINI_STRESS = 24
local MINI_SAMPLE = 2 -- seconds of frames before and after

local mini

local function miniWindow()
  if not mini then
    mini = CreateFrame("Frame", "BastiansProbeMinimaps", UIParent)
    mini:SetSize(1340, 670)
    mini:SetPoint("CENTER")
    mini:SetFrameStrata("DIALOG")
    mini:SetMovable(true)
    mini:EnableMouse(true)
    mini:RegisterForDrag("LeftButton")
    mini:SetScript("OnDragStart", mini.StartMoving)
    mini:SetScript("OnDragStop", mini.StopMovingOrSizing)
    local bg = mini:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.08, 0.96)
    mini.title = mini:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mini.title:SetPoint("TOPLEFT", 10, -8)
    mini.textures, mini.labels = {}, {}
  end
  mini.usedTextures, mini.usedLabels = 0, 0
  for _, t in ipairs(mini.textures) do
    t:Hide()
  end
  for _, l in ipairs(mini.labels) do
    l:Hide()
  end
  mini:SetScript("OnUpdate", nil)
  mini:Show()
  return mini
end

local function miniTexture(win)
  win.usedTextures = win.usedTextures + 1
  local t = win.textures[win.usedTextures]
  if not t then
    t = win:CreateTexture(nil, "ARTWORK")
    win.textures[win.usedTextures] = t
  end
  t:SetTexCoord(0, 1, 0, 1)
  return t
end

local function miniLabel(win, left, top, width, text)
  win.usedLabels = win.usedLabels + 1
  local l = win.labels[win.usedLabels]
  if not l then
    l = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l:SetJustifyH("LEFT")
    win.labels[win.usedLabels] = l
  end
  l:ClearAllPoints()
  l:SetPoint("TOPLEFT", win, "TOPLEFT", left, -top)
  l:SetWidth(width)
  l:SetText(text)
  l:Show()
end

-- The zone's rectangle in world yards: north and south edge (wx), west and east edge (wy; west
-- is the larger one), and its continent. nil when the client does not place the map.
local function miniZoneRect(mapID)
  local coords = Bastians and Bastians.Coords
  if not (coords and coords.ToWorld) then
    return nil
  end
  local ok1, c1, n, w = pcall(coords.ToWorld, mapID, 0, 0)
  local ok2, c2, sEdge, e = pcall(coords.ToWorld, mapID, 1, 1)
  if not (ok1 and ok2 and c1 and c1 == c2 and n and w and sEdge and e and n > sEdge and w > e) then
    return nil
  end
  return { continent = c1, north = n, south = sEdge, west = w, east = e }
end

-- Draws the zone from the cells of `part` into the rectangle (left, top, w, h) of the window.
-- Returns the textures used, how many of them the client did not load, and the first error of
-- SetTexture with a filter (nil when the client took it).
local function miniDraw(win, styles, part, zone, left, top, w, h, filter)
  local cells = styles.Visible(part, zone.continent, zone.south, zone.east, zone.north, zone.west, 0)
  local used, missing, filterError = 0, 0, nil
  local high, wide = zone.north - zone.south, zone.west - zone.east
  for _, c in ipairs(cells) do
    local x1, x2 = math.max(c.x1, zone.south), math.min(c.x2, zone.north) -- north-south, in wx
    local y1, y2 = math.max(c.y1, zone.east), math.min(c.y2, zone.west) -- east-west, in wy
    if x2 > x1 and y2 > y1 then
      local t = miniTexture(win)
      local ok, err
      if filter then
        ok, err = pcall(t.SetTexture, t, c.path, nil, nil, filter)
        if not ok then
          filterError = filterError or tostring(err)
          pcall(t.SetTexture, t, c.path)
        end
      else
        pcall(t.SetTexture, t, c.path)
      end
      -- a cell's picture has north up and west left
      local cw, ch = c.y2 - c.y1, c.x2 - c.x1
      t:SetTexCoord((c.y2 - y2) / cw, (c.y2 - y1) / cw, (c.x2 - x2) / ch, (c.x2 - x1) / ch)
      local sx1, sx2 = (zone.west - y2) / wide * w, (zone.west - y1) / wide * w
      local sy1, sy2 = (zone.north - x2) / high * h, (zone.north - x1) / high * h
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", win, "TOPLEFT", left + sx1, -(top + sy1))
      t:SetSize(sx2 - sx1, sy2 - sy1)
      t:Show()
      used = used + 1
      local okGet, got = pcall(t.GetTexture, t)
      if not (okGet and got) then
        missing = missing + 1 -- SetTexture is true for a file the client does not have
      end
    end
  end
  return used, missing, filterError
end

-- The client's own painting of the zone (the art layer's 256 px tiles), for the eye.
local function miniPainting(win, mapID, left, top, w, h)
  local okLayers, layers = pcall(C_Map.GetMapArtLayers, mapID)
  local okTex, files = pcall(C_Map.GetMapArtLayerTextures, mapID, 1)
  local layer = okLayers and type(layers) == "table" and layers[1] or nil
  if not (layer and okTex and type(files) == "table" and #files > 0) then
    return 0
  end
  local lw, lh = layer.layerWidth or 1002, layer.layerHeight or 668
  local tw, th = layer.tileWidth or 256, layer.tileHeight or 256
  local cols = math.ceil(lw / tw)
  for i, file in ipairs(files) do
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    local px, py = math.min(tw, lw - col * tw), math.min(th, lh - row * th)
    if px > 0 and py > 0 then
      local t = miniTexture(win)
      pcall(t.SetTexture, t, file)
      t:SetTexCoord(0, px / tw, 0, py / th)
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", win, "TOPLEFT", left + col * tw / lw * w, -(top + row * th / lh * h))
      t:SetSize(px / lw * w, py / lh * h)
      t:Show()
    end
  end
  return #files
end

-- Frames for `seconds`: { frames, avgMs, worstMs }, handed to onDone.
local function miniSample(win, seconds, onDone)
  local frames, total, worst = 0, 0, 0
  win:SetScript("OnUpdate", function(self, elapsed)
    frames = frames + 1
    total = total + elapsed
    worst = math.max(worst, elapsed)
    if total >= seconds then
      self:SetScript("OnUpdate", nil)
      onDone({
        frames = frames,
        avgMs = math.floor(total / frames * 100000 + 0.5) / 100,
        worstMs = math.floor(worst * 100000 + 0.5) / 100,
      })
    end
  end)
end

local function probeMinimaps(arg)
  local mapMod = Bastians and Bastians.GetModule and Bastians:GetModule("Map")
  local styles = mapMod and mapMod.Styles
  if not (styles and styles.Get and styles.Visible and styles.List) then
    say("minimaps: Bastian's Map is not loaded, or it has no map styles")
    return
  end
  local wantMap, wantStyle = string.match(arg or "", "^(%d*)%s*(%S*)$")
  local okMap, here = pcall(C_Map.GetBestMapForUnit, "player")
  local mapID = tonumber(wantMap) or (okMap and here) or nil
  local zone = mapID and miniZoneRect(mapID)
  if not zone then
    say("minimaps: map %s has no place in the world; give a zone's uiMapID (Elwynn: 1429)", tostring(mapID))
    return
  end
  local key = wantStyle ~= "" and wantStyle or (mapMod.Map and mapMod.Map.Style and mapMod.Map.Style())
  local style = key and styles.Get(key)
  if not style then
    style = styles.List()[1] -- the physical map is chosen: the first style there is
  end
  if not (style and style.far) then
    say("minimaps: no map style of Bastian's is installed (Modern, Pencil, Parchment, Blizzard)")
    return
  end
  local out = {
    at = now(),
    map = mapID,
    style = style.key,
    zoneYards = { math.floor(zone.west - zone.east), math.floor(zone.north - zone.south) },
    variants = {},
  }
  local okScale, scale = pcall(UIParent.GetEffectiveScale, UIParent)
  local okScreen, sw, sh = pcall(GetPhysicalScreenSize)
  out.uiScale = okScale and scale or nil
  out.screen = okScreen and { sw, sh } or nil
  local win = miniWindow()
  win.title:SetText("Mini maps: map " .. mapID .. " in the style '" .. style.key .. "'   (/bprobe hide)")
  win:Hide() -- the frames before are measured without it
  local sampler = CreateFrame("Frame")
  miniSample(sampler, MINI_SAMPLE, function(before)
    out.before = before
    win:Show()
    local started = debugprofilestop()
    local parts = {
      { "far", style.far, nil },
      { "far trilinear", style.far, "TRILINEAR" },
      { "near", style.near, nil },
      { "near trilinear", style.near, "TRILINEAR" },
    }
    local top = 30
    for _, row in ipairs(MINI_ROWS) do
      local left, tallest = 10, 0
      for _, size in ipairs(row) do
        local w, h = size[1], size[2]
        tallest = math.max(tallest, h)
        for _, part in ipairs(parts) do
          if part[2] then
            local t0 = debugprofilestop()
            local used, missing, filterError = miniDraw(win, styles, part[2], zone, left, top, w, h, part[3])
            out.variants[#out.variants + 1] = {
              name = part[1] .. ", " .. size[3],
              width = w,
              textures = used,
              missing = missing,
              ms = debugprofilestop() - t0,
              filterError = filterError,
            }
            miniLabel(win, left, top + h + 2, math.max(w, 110), part[1] .. "  " .. used .. " tex")
            left = left + math.max(w, 110) + 12
          end
        end
        if size[3] == "large" then
          out.painting = miniPainting(win, mapID, left, top, w, h)
          miniLabel(win, left, top + h + 2, w, "the client's painting  " .. out.painting .. " tex")
        end
      end
      top = top + tallest + 26
    end
    -- many at once: the zones of this continent from the far cells, as a list of tiles would
    local t0 = debugprofilestop()
    local shown, textures, missingAll = 0, 0, 0
    local w, h, perRow = 120, 80, 10
    for _, id in ipairs(MINI_ZONES) do
      local z = shown < MINI_STRESS and miniZoneRect(id)
      if z and z.continent == zone.continent then
        local left = 10 + (shown % perRow) * (w + 12)
        local rowTop = top + math.floor(shown / perRow) * (h + 20)
        local used, missing = miniDraw(win, styles, style.far, z, left, rowTop, w, h, nil)
        miniLabel(win, left, rowTop + h + 2, w, id .. "  " .. used .. " tex")
        shown, textures, missingAll = shown + 1, textures + used, missingAll + missing
      end
    end
    out.many = { zones = shown, textures = textures, missing = missingAll, ms = debugprofilestop() - t0 }
    out.buildMs = debugprofilestop() - started
    out.texturesShown = win.usedTextures
    miniSample(win, MINI_SAMPLE, function(after)
      out.after = after
      db.results.minimaps = out -- the last run
      db.results.minimapRuns = db.results.minimapRuns or {} -- and every run: styles, zones, screens
      table.insert(db.results.minimapRuns, out)
      say(
        "minimaps: map %d, style %s, %d textures in %.1f ms; %d zones at once: %d textures, %d not loaded",
        mapID,
        style.key,
        out.texturesShown,
        out.buildMs,
        shown,
        textures,
        missingAll
      )
      say(
        "minimaps: frames before %.2f ms (worst %.2f), with the window %.2f ms (worst %.2f)",
        before.avgMs,
        before.worstMs,
        after.avgMs,
        after.worstMs
      )
      say("minimaps: take a screenshot now, then /reload so the numbers are saved")
    end)
  end)
end

-- ---------------------------------------------------------------------------------------------
-- Resize: what a suite window does when its grip is taken (plan-book-round3.md R3.1; owner,
-- Forever 17.11.2026: "it jumps to full screen when starting to change the size"). Armed by
-- itself: each window's grip records the frame before StartSizing, right after it, at the first
-- size changes, when the mouse is up and half a second later; along the drag its path, every
-- step the cursor does not explain, and each call of Lua's on the frame with its caller (the
-- first four drags, 17.11.2026, began smoothly; in two the top left corner moved later). The
-- last RESIZE_KEEP drags stay.
-- ---------------------------------------------------------------------------------------------

local RESIZE_KEEP = 12 -- drags kept
local RESIZE_EVENTS = 8 -- size changes recorded while the grip is held
local RESIZE_LATE = 4 -- and after the mouse is up
local RESIZE_JUMP = 40 -- a first step larger than this, or a top left corner that moves, is a jump
local RESIZE_TRAIL = 80 -- the drag's path: a point every RESIZE_TRAIL_S
local RESIZE_TRAIL_S = 0.2
local RESIZE_STEPS = 6 -- steps the cursor does not explain, kept with the state before
local RESIZE_CALLS = 30 -- Lua's own calls on the frame, with their callers
local RESIZE_METHODS =
  { "SetSize", "SetWidth", "SetHeight", "SetPoint", "ClearAllPoints", "SetAllPoints", "SetScale" }
local resizeArmed = {} -- [window name] = true

-- obj:name() -> its first answer, nil when the call fails or answers nil.
local function one(obj, name)
  local r = tryMethod(obj, name)
  if not r.ok or r.ret[1] == "<nil>" then
    return nil
  end
  return r.ret[1]
end

local function windowState(win)
  local f = win.frame
  local out = { t = GetTime(), points = {} }
  for i = 1, tonumber(one(f, "GetNumPoints")) or 0 do
    local ok, point, rel, relPoint, x, y = pcall(f.GetPoint, f, i)
    if ok then
      local relName = "<nil>"
      if type(rel) == "table" then
        local okName, name = pcall(rel.GetName, rel)
        relName = okName and name or "<unnamed>"
      end
      out.points[i] = { point = point, rel = relName, relPoint = relPoint, x = x, y = y }
    end
  end
  out.left, out.top = one(f, "GetLeft"), one(f, "GetTop")
  out.width, out.height = one(f, "GetWidth"), one(f, "GetHeight")
  out.scale, out.effective = one(f, "GetScale"), one(f, "GetEffectiveScale")
  local okCursor, cx, cy = pcall(GetCursorPosition)
  if okCursor then
    out.cursorX, out.cursorY = cx, cy
  end
  out.sizing = win.sizing == true
  out.full = win.full ~= nil
  out.docked = win.dock ~= nil and win.dock ~= false
  out.gameFramed = win.gameFramed == true
  return out
end

-- Marks the drag when `state` is far from where the window stood before the grip was taken.
local function resizeJump(rec, state, step)
  local b = rec.before
  if rec.jump or not (b.width and b.height and b.left and b.top) then
    return
  end
  if not (state.width and state.height and state.left and state.top) then
    return
  end
  local dw, dh = state.width - b.width, state.height - b.height
  local dl, dt = state.left - b.left, state.top - b.top
  local grew = math.abs(dw) > RESIZE_JUMP or math.abs(dh) > RESIZE_JUMP
  local moved = math.abs(dl) > 2 or math.abs(dt) > 2
  if grew or moved then
    rec.jump = { step = step, dw = dw, dh = dh, dl = dl, dt = dt, grew = grew, moved = moved }
    say(
      "resize: %s jumped at %s: %.0f x %.0f -> %.0f x %.0f, corner moved %.0f, %.0f",
      tostring(rec.window),
      step,
      b.width,
      b.height,
      state.width,
      state.height,
      dl,
      dt
    )
  end
end

local function resizeBegin(win)
  local res = result("resize")
  res.drags = res.drags or {}
  local f = win.frame
  local rec = {
    at = now(),
    window = win.name,
    screen = {
      width = one(UIParent, "GetWidth"),
      height = one(UIParent, "GetHeight"),
      scale = one(UIParent, "GetScale"),
      effective = one(UIParent, "GetEffectiveScale"),
    },
    bounds = tryMethod(f, "GetResizeBounds"),
    clamped = tryMethod(f, "IsClampedToScreen"),
    userPlaced = tryMethod(f, "IsUserPlaced"),
    before = windowState(win),
    sizes = {},
    late = {},
    trail = {},
    calls = {},
  }
  table.insert(res.drags, rec)
  while #res.drags > RESIZE_KEEP do
    table.remove(res.drags, 1)
  end
  win.probeDrag = rec
  return rec
end

-- The drag's path, thinned: where the frame and the cursor were.
local function trailPoint(s)
  return {
    t = s.t,
    left = s.left,
    top = s.top,
    width = s.width,
    height = s.height,
    cursorX = s.cursorX,
    cursorY = s.cursorY,
  }
end

-- A size change the cursor does not explain: the top left corner moved under a grip that drags
-- the bottom right one, or the size changed by more than the cursor went.
local function resizeStep(rec, prev, state)
  if not (prev.width and prev.height and prev.left and prev.top) then
    return
  end
  if not (state.width and state.height and state.left and state.top) then
    return
  end
  local eff = state.effective or 1
  local dw, dh = state.width - prev.width, state.height - prev.height
  local cx = math.abs((state.cursorX or 0) - (prev.cursorX or 0)) / eff
  local cy = math.abs((state.cursorY or 0) - (prev.cursorY or 0)) / eff
  local moved = math.abs(state.left - prev.left) > 1 or math.abs(state.top - prev.top) > 1
  local grew = math.abs(dw) > cx + RESIZE_JUMP or math.abs(dh) > cy + RESIZE_JUMP
  if not (moved or grew) then
    return
  end
  rec.steps = rec.steps or {}
  if #rec.steps < RESIZE_STEPS then
    rec.steps[#rec.steps + 1] = { from = prev, to = state, moved = moved, grew = grew }
  end
  if not rec.said then
    rec.said = true
    say(
      "resize: %s jumped while dragged: %.0f x %.0f at %.0f, %.0f -> %.0f x %.0f at %.0f, %.0f",
      tostring(rec.window),
      prev.width,
      prev.height,
      prev.left,
      prev.top,
      state.width,
      state.height,
      state.left,
      state.top
    )
  end
end

-- An argument as the record keeps it: a frame by its name.
local function callArg(v)
  local kind = type(v)
  if kind == "number" or kind == "string" or kind == "boolean" then
    return v
  elseif kind == "table" then
    local ok, name = pcall(function()
      return v:GetName()
    end)
    return "<" .. tostring(ok and name or "table") .. ">"
  end
  return "<" .. kind .. ">"
end

local function armResizeWindow(win)
  local grip, frame = win.grip, win.frame
  local down, up = grip:GetScript("OnMouseDown"), grip:GetScript("OnMouseUp")
  local last -- the state at the size change before
  grip:SetScript("OnMouseDown", function(self, ...)
    local ok, rec = pcall(resizeBegin, win)
    last = ok and rec and rec.before or nil
    if down then
      down(self, ...)
    end
    if ok and rec then
      pcall(function()
        rec.after = windowState(win)
        resizeJump(rec, rec.after, "grip down")
      end)
    end
  end)
  grip:SetScript("OnMouseUp", function(self, ...)
    local rec = win.probeDrag
    if rec then
      pcall(function()
        rec.release = windowState(win) -- before the window's own handler runs
      end)
    end
    if up then
      up(self, ...)
    end
    if not rec then
      return
    end
    pcall(function()
      rec.up = windowState(win)
    end)
    C_Timer.After(0.5, function()
      pcall(function()
        rec.settled = windowState(win)
      end)
      if win.probeDrag == rec then
        win.probeDrag = nil
      end
      if db and db.meta then
        db.meta.updated = now()
      end
    end)
  end)
  frame:HookScript("OnSizeChanged", function()
    local rec = win.probeDrag
    if not rec then
      return
    end
    pcall(function()
      local state = windowState(win)
      local list = rec.up and rec.late or rec.sizes
      if #list < (rec.up and RESIZE_LATE or RESIZE_EVENTS) then
        list[#list + 1] = state
        if list == rec.sizes and #list == 1 then
          resizeJump(rec, state, "the first size change")
        end
      end
      if rec.release then
        return -- the mouse is up: what follows is the window's own doing, kept in `late` and `calls`
      end
      if last then
        resizeStep(rec, last, state)
      end
      last = state
      if #rec.trail < RESIZE_TRAIL and (not rec.trailAt or state.t - rec.trailAt >= RESIZE_TRAIL_S) then
        rec.trailAt = state.t
        rec.trail[#rec.trail + 1] = trailPoint(state)
      end
    end)
  end)
  -- Lua's own calls on the frame while a drag is recorded, with their callers: the client's
  -- sizing does not come through here, so each one is code of ours (or of another addon)
  for _, name in ipairs(RESIZE_METHODS) do
    pcall(hooksecurefunc, frame, name, function(_, ...)
      local rec = win.probeDrag
      if not rec or #rec.calls >= RESIZE_CALLS then
        return
      end
      local args = {}
      for i = 1, select("#", ...) do
        args[i] = callArg((select(i, ...)))
      end
      local okStack, stack = pcall(debugstack, 3, 8, 0)
      rec.calls[#rec.calls + 1] = {
        t = GetTime(),
        fn = name,
        args = args,
        phase = rec.up and "after" or (rec.release and "up handler" or "drag"),
        stack = okStack and stack and string.sub(tostring(stack), 1, 900) or nil,
      }
    end)
  end
end

-- Arms every suite window that exists by now (they are built when first opened).
local function armResize()
  local suite = rawget(_G, "Bastians")
  local windows = suite and suite.UI and suite.UI.Windows
  if type(windows) ~= "table" then
    return 0
  end
  local n = 0
  for name, win in pairs(windows) do
    if type(win) == "table" and win.grip and win.frame then
      if not resizeArmed[name] then
        resizeArmed[name] = true
        local ok, err = pcall(armResizeWindow, win)
        if not ok then
          say("resize: %s not armed: %s", tostring(name), tostring(err))
        end
      end
      n = n + 1
    end
  end
  return n
end

local function probeResize(arg)
  local n = armResize()
  local res = result("resize")
  if arg == "clear" then
    res.drags = {}
    say("resize: the recorded drags are cleared")
    return
  end
  local drags = res.drags or {}
  say("resize: %d windows armed, %d drags recorded (the last %d are kept)", n, #drags, RESIZE_KEEP)
  for i = math.max(1, #drags - 3), #drags do
    local d = drags[i]
    local b, e = d.before or {}, d.settled or d.up or d.after or {}
    say(
      "  %s %s: %s x %s -> %s x %s%s",
      tostring(d.at),
      tostring(d.window),
      tostring(b.width and math.floor(b.width + 0.5)),
      tostring(b.height and math.floor(b.height + 0.5)),
      tostring(e.width and math.floor(e.width + 0.5)),
      tostring(e.height and math.floor(e.height + 0.5)),
      (d.jump or d.steps) and ", JUMPED" or ""
    )
  end
  say("resize: drag a window's corner as usual; /reload or log out saves the record")
end

-- ---------------------------------------------------------------------------------------------
-- Booktech: the drawing calls Bastian's Book would like and nobody has seen on Forever
-- (docs/addons/book-look.md section 8): a turned font string (the stamp), a gradient without a
-- texture, a line. Each is called in pcall and shown; a screenshot is taken by itself.
-- ---------------------------------------------------------------------------------------------

local function probeBookTech()
  local out = { at = now() }
  db.results.booktech = out
  local d = clearDisplay("Book techniques: a turned word, a gradient, a line")
  local tech = rawget(d, "tech")
  if not tech then
    tech = CreateFrame("Frame", nil, d)
    tech:SetAllPoints(d)
    d.tech = tech
    tech.word = tech:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    tech.word:SetPoint("TOPLEFT", 60, -90)
    tech.word:SetText("UNSOLVED")
    tech.plain = tech:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    tech.plain:SetPoint("TOPLEFT", 60, -180)
    tech.plain:SetText("UNSOLVED (not turned)")
    tech.grad = tech:CreateTexture(nil, "ARTWORK")
    tech.grad:SetSize(260, 120)
    tech.grad:SetPoint("TOPLEFT", 330, -60)
    tech.note = tech:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tech.note:SetPoint("BOTTOMLEFT", 10, 10)
    tech.note:SetJustifyH("LEFT")
  end
  tech:Show()
  -- 1. a font string turned 12 degrees (the board's "unsolved" stamp)
  out.rotation = {
    set = tryMethod(tech.word, "SetRotation", math.rad(12)),
    get = tryMethod(tech.word, "GetRotation"),
  }
  -- 2. a gradient on a plain colour texture (the bar: #2a2119 over #1a140f)
  local okColor, top, foot = pcall(function()
    return CreateColor(0.165, 0.129, 0.098, 1), CreateColor(0.102, 0.078, 0.059, 1)
  end)
  tryMethod(tech.grad, "SetColorTexture", 1, 1, 1, 1)
  out.gradient = {
    colors = okColor,
    set = okColor and tryMethod(tech.grad, "SetGradient", "VERTICAL", foot, top)
      or { ok = false, err = "CreateColor: " .. tostring(top) },
  }
  -- 3. a line (the Atlas' trails)
  local line = rawget(tech, "line")
  if not line then
    local okLine, obj = pcall(function()
      return tech:CreateLine(nil, "OVERLAY")
    end)
    out.lineCreate = { ok = okLine and obj ~= nil, err = not okLine and tostring(obj) or nil }
    line = okLine and obj or nil
    tech.line = line
  end
  if line then
    out.line = {
      color = tryMethod(line, "SetColorTexture", 0.64, 0.2, 0.17, 1),
      thickness = tryMethod(line, "SetThickness", 3),
      start = tryMethod(line, "SetStartPoint", "TOPLEFT", tech, 60, -320),
      finish = tryMethod(line, "SetEndPoint", "TOPLEFT", tech, 600, -420),
    }
  end
  local function word(r)
    return r and r.ok and "ok" or ("no: " .. tostring(r and r.err))
  end
  local lineOk = out.line and out.line.start.ok and out.line.finish.ok
  tech.note:SetText(
    string.format(
      "SetRotation %s   SetGradient %s   CreateLine %s",
      word(out.rotation.set),
      word(out.gradient.set),
      lineOk and "ok" or "no"
    )
  )
  say(
    "booktech: rotation %s, gradient %s, line %s",
    word(out.rotation.set),
    word(out.gradient.set),
    lineOk and "ok" or "no"
  )
  -- the picture is the proof: a call can succeed and draw nothing
  C_Timer.After(0.5, function()
    out.screenshot = try(rawget(_G, "Screenshot"))
    say("booktech: screenshot taken; /bprobe hide closes the panel, /reload saves the record")
  end)
end

-- ---------------------------------------------------------------------------------------------
-- Portrait (ADR 0090, the book's Portrait.lua): a creature's round portrait needs its display, which
-- the client learns from the game. Six rares, one of them new in Forever: each on a model that is
-- seen and on one nobody sees (1 by 1, alpha 0, as the kit's). Recorded per creature: the display
-- right after SetCreature, whether and when OnModelLoaded came, the display then; whether
-- SetPortraitTextureFromCreatureDisplayID took it and what the texture answers. The picture is
-- the proof: the model above, the portrait call's result under it. Once by itself after a login.
-- ---------------------------------------------------------------------------------------------

local PORTRAIT_WAIT = 5 -- seconds for the models to load before the record is closed
local PORTRAIT_NPCS = {
  { 521, "Lupos" },
  { 100, "Gruff Swiftbite" },
  { 276180, "Elder Finseer (new in Forever)" },
  { 5808, "Warlord Kolkanis" },
  { 3270, "Elder Mystic Razorsnout" },
  { 10356, "Bayne" },
}

local function probePortrait(_, onDone)
  local started = GetTime()
  local draw = rawget(_G, "SetPortraitTextureFromCreatureDisplayID")
  local out = { at = now(), call = type(draw), tests = {} }
  db.results.portrait = out
  local d = clearDisplay("Portraits: a creature's display from its model, and the game's portrait of it")
  local holder = rawget(d, "portraits")
  if not holder then
    holder = CreateFrame("Frame", nil, d)
    holder:SetAllPoints(d)
    d.portraits = holder
    holder.cells = {}
  end
  holder:Show()
  local function displayOf(model)
    local ok, id = pcall(function()
      return model:GetDisplayInfo()
    end)
    if ok then
      return id
    end
    return "error: " .. tostring(id)
  end
  local portrayOf = {} -- per creature: draws its portrait once its display is there
  for i, pair in ipairs(PORTRAIT_NPCS) do
    local npc, name = pair[1], pair[2]
    local rec = { name = name, seen = {}, unseen = {} }
    out.tests[tostring(npc)] = rec
    local c = holder.cells[i]
    if not c then
      c = {}
      holder.cells[i] = c
      local left = 10 + (i - 1) * 110
      c.bg = holder:CreateTexture(nil, "BACKGROUND")
      c.bg:SetColorTexture(0.9, 0.84, 0.7, 1) -- the book's paper
      c.bg:SetSize(100, 100)
      c.bg:SetPoint("TOPLEFT", left, -30)
      c.tex = holder:CreateTexture(nil, "ARTWORK")
      c.tex:SetSize(64, 64)
      c.tex:SetPoint("TOP", c.bg, "BOTTOM", 0, -10)
      c.small = holder:CreateTexture(nil, "ARTWORK") -- at the Atlas's size
      c.small:SetSize(33, 33)
      c.small:SetPoint("TOP", c.tex, "BOTTOM", 0, -8)
      c.label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      c.label:SetPoint("TOP", c.small, "BOTTOM", 0, -6)
      c.label:SetWidth(104)
      for _, kind in ipairs({ "seen", "unseen" }) do
        local okMake, model = pcall(CreateFrame, "PlayerModel", nil, holder)
        if okMake and model then
          -- placed and sized before its creature is set (the FacePool lesson)
          if kind == "seen" then
            model:SetSize(100, 100)
            model:SetPoint("TOPLEFT", left, -30)
          else
            model:SetSize(1, 1)
            model:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
            model:SetAlpha(0)
          end
          model:Show()
          c[kind] = model
        end
      end
    end
    c.tex:SetTexture(nil)
    c.small:SetTexture(nil)
    c.label:SetText(name)
    local function portray(id)
      if rec.portrait or type(id) ~= "number" or id <= 0 then
        return
      end
      local r = try(draw, c.tex, id)
      try(draw, c.small, id)
      local okTex, path = pcall(c.tex.GetTexture, c.tex)
      rec.portrait = { display = id, ok = r.ok, err = r.err, texture = okTex and tostring(path) or nil }
    end
    portrayOf[i] = portray
    for _, kind in ipairs({ "seen", "unseen" }) do
      local model, r = c[kind], rec[kind]
      r.made = model ~= nil
      if model then
        tryMethod(model, "SetScript", "OnModelLoaded", function(m)
          if r.loadedAfter then
            return
          end
          r.loadedAfter = GetTime() - started
          r.atLoaded = displayOf(m)
          portray(r.atLoaded)
        end)
        r.clear = tryMethod(model, "ClearModel").ok
        r.set = tryMethod(model, "SetCreature", npc)
        r.atOnce = displayOf(model)
        portray(r.atOnce)
      end
    end
  end
  C_Timer.After(PORTRAIT_WAIT, function()
    local loaded, unseen, drawn = 0, 0, 0
    for i, pair in ipairs(PORTRAIT_NPCS) do
      local rec, c = out.tests[tostring(pair[1])], holder.cells[i]
      for _, kind in ipairs({ "seen", "unseen" }) do
        if c[kind] then
          rec[kind].atEnd = displayOf(c[kind]) -- when OnModelLoaded never came
          portrayOf[i](rec[kind].atEnd)
        end
      end
      loaded = loaded + ((rec.seen.loadedAfter or (tonumber(rec.seen.atEnd) or 0) > 0) and 1 or 0)
      unseen = unseen + ((rec.unseen.loadedAfter or (tonumber(rec.unseen.atEnd) or 0) > 0) and 1 or 0)
      drawn = drawn + ((rec.portrait and rec.portrait.ok) and 1 or 0)
    end
    out.summary =
      { creatures = #PORTRAIT_NPCS, seenLoaded = loaded, unseenLoaded = unseen, portraits = drawn }
    say(
      "portrait: of %d creatures %d loaded seen, %d unseen; the portrait call took %d",
      #PORTRAIT_NPCS,
      loaded,
      unseen,
      drawn
    )
    C_Timer.After(0.5, function()
      out.screenshot = try(rawget(_G, "Screenshot"))
      db.meta.updated = now()
      say("portrait: screenshot taken; /reload or log out saves the record")
      if onDone then
        C_Timer.After(1.5, onDone)
      end
    end)
  end)
end

-- ---------------------------------------------------------------------------------------------
-- Booklook: Bastian's Book measured as the client lays it out (plan-book-round3.md M5; the owner
-- saw every result before its author did: the mock lays no frame out from its anchors). Opens a
-- chapter's page, sets the window to three widths and records, for each, where the head, the bar,
-- its tabs and tools, the filter band, its chips, the slider, the switch, the result line and the
-- first tiles stand, the faces and sizes in use and the grounds' colours; a screenshot per width.
-- tools/book_look.py holds the record against docs/addons/book-look.md.
-- ---------------------------------------------------------------------------------------------

local BOOKLOOK_WIDTHS = { 1100, 1532, 2100 }
local BOOKLOOK_HEIGHT = 843
local BOOKLOOK_WAIT = 0.6 -- seconds for the book to lay itself out before it is measured
-- `booklook small` (plan-book-round4.md D3; the owner plays at 5,120 x 2,160): a 1,920 x 1,080
-- screen at UI scale 1 is 768 units high and about 1,365 wide. The book's window is scaled so this
-- screen holds as many of ITS units, then measured at the widths that room allows. The layout is
-- the small screen's; the sharpness is not (this screen draws more pixels per unit).

local function probeBookLook(arg, onDone)
  local small = arg == "small"
  local name = small and "booklook small" or "booklook"
  local function done()
    if onDone then
      onDone()
    end
  end
  local suite = rawget(_G, "Bastians")
  local okMod, mod = pcall(function()
    return suite:GetModule("Strategies")
  end)
  local Window, Front = okMod and mod and mod.Window, okMod and mod and mod.Front
  if not (Window and Front and Window.Show) then
    say("%s: Bastian's Book is not loaded", name)
    return done()
  end
  local out = { at = now(), runs = {} }
  db.results[small and "booklookSmall" or "booklook"] = out
  Window.Show({ kind = "shelf", id = "rares" })
  local win, bar, view = Window.win, Window.bar, Front.view
  if not (win and bar and view) then
    say("%s: the book's window is not built", name)
    return done()
  end
  local frame = win.frame
  local SMALL_HEIGHT = 768
  local widths = small and { 1100, 1365 } or BOOKLOOK_WIDTHS
  local savedScale = one(frame, "GetScale") or 1
  if small then
    local factor = (one(UIParent, "GetHeight") or SMALL_HEIGHT) / SMALL_HEIGHT
    out.small = { factor = factor, scaleBefore = savedScale, height = SMALL_HEIGHT }
    out.small.set = tryMethod(frame, "SetScale", savedScale * factor)
  end
  -- the screen's room in the window's own units (a scaled window's units are larger)
  local per = (one(frame, "GetEffectiveScale") or 1) / (one(UIParent, "GetEffectiveScale") or 1)
  if per <= 0 then
    per = 1
  end
  local roomW = (one(UIParent, "GetWidth") or 1920) / per
  local roomH = (one(UIParent, "GetHeight") or 1080) / per
  out.room = { width = roomW, height = roomH, unitsPerScreenUnit = per }
  local style = suite.UI and suite.UI.Style
  out.look = style and try(style.LookOf, frame) or nil
  out.gameFramed = win.gameFramed == true
  out.effective = one(frame, "GetEffectiveScale")
  out.screen = { width = one(UIParent, "GetWidth"), height = one(UIParent, "GetHeight") }
  local saved = { size = win.db.size, pos = win.db.pos }

  -- a region's rect from the window's top left corner: left, top (down), width, height
  local function rect(region)
    if type(region) ~= "table" then
      return nil
    end
    local l, tp = one(region, "GetLeft"), one(region, "GetTop")
    local fl, ft = one(frame, "GetLeft"), one(frame, "GetTop")
    if not (l and tp and fl and ft) then
      return { shown = one(region, "IsShown") }
    end
    return {
      left = l - fl,
      top = ft - tp,
      width = one(region, "GetWidth"),
      height = one(region, "GetHeight"),
      shown = one(region, "IsShown"),
    }
  end
  local function face(fs)
    if type(fs) ~= "table" then
      return nil
    end
    local ok, font, size = pcall(fs.GetFont, fs)
    return ok and { font = font, size = size, text = one(fs, "GetText") } or nil
  end
  local function colour(tex)
    if type(tex) ~= "table" then
      return nil
    end
    local ok, r, g, b, a = pcall(tex.GetVertexColor, tex)
    return ok and { r = r, g = g, b = b, a = a, shown = one(tex, "IsShown") } or nil
  end

  local function measure(width)
    local run = { width = width }
    run.frame = rect(frame)
    run.head = rect(win.head)
    run.content = rect(win.content)
    run.oneBar = bar.oneBar == true
    run.bar = rect(bar)
    run.tabs = rect(bar.tabs)
    run.tab = bar.front and rect(bar.front) or nil
    run.search = rect(bar.search)
    run.tools = {
      mark = rect(bar.mark),
      record = rect(bar.record),
      atlas = rect(bar.atlas),
      -- the pictogram itself: Core's button is its 20 with 5 of room on each side, and the
      -- first run held the button's 30 against the 20 (23.11.2026)
      gear = rect(bar.gear and rawget(bar.gear, "icon") or bar.gear),
      logo = rect(bar.logo),
      portrait = rect(win.portraitButton),
    }
    run.barGround = rect(bar.ground)
    run.band = rect(view.filters)
    run.body = rect(view.body)
    run.chips = {}
    for _, chip in ipairs(view.pills or {}) do
      if #run.chips < 40 and one(chip, "IsShown") then
        local r = rect(chip)
        r.radius = chip.face and chip.face.r
        r.label = chip.spec and chip.spec.label
        r.on = chip.spec and chip.spec.on and true or nil
        run.chips[#run.chips + 1] = r
      end
    end
    run.labels = {}
    for _, fs in ipairs(view.labels or {}) do
      if #run.labels < 12 and one(fs, "IsShown") then
        local r = rect(fs)
        r.text = one(fs, "GetText")
        run.labels[#run.labels + 1] = r
      end
    end
    run.separators = 0
    for _, line in ipairs(view.seps or {}) do
      if one(line, "IsShown") then
        run.separators = run.separators + 1
      end
    end
    run.slider = rect(view.slider)
    run.hide = rect(view.hide)
    run.done = rect(view.done)
    -- the front table's cabinet at this width (W6, book-look.md 10.2): the cells as the game
    -- laid them, each tile's place in the cabinet's row and what it drew; then the shelf again
    local okCab, cab = pcall(function()
      Window.Show({ kind = "front" })
      local found
      for _, row in ipairs(Front.list:Rows()) do
        if row.layout and row.tiles then
          found = row
        end
      end
      if not found then
        return { error = "no cabinet on the front table" }
      end
      local at = rect(found)
      local c = {
        row = at,
        cols = found.layout.cols,
        c = found.layout.c,
        h = found.layout.h,
        height = found.layout.height,
        tiles = {},
      }
      for i, t in ipairs(found.tiles) do
        if one(t, "IsShown") then
          local r = rect(t)
          r.slot, r.kind, r.drew = i - 1, t.kind, t.drew
          if r.left and at.left then
            r.x, r.y = r.left - at.left, r.top - at.top
          end
          c.tiles[#c.tiles + 1] = r
        end
      end
      return c
    end)
    run.cabinet = okCab and cab or { error = tostring(cab) }
    pcall(Window.Show, { kind = "shelf", id = "rares" })
    run.rows = {}
    local okRows, rows = pcall(function()
      return Front.list:Rows()
    end)
    for _, row in ipairs(okRows and rows or {}) do
      if #run.rows < 3 then
        local r = rect(row)
        r.kind = row.vlKind
        r.tiles = {}
        for i, tile in ipairs(row.tiles or {}) do
          if i <= 4 and one(tile, "IsShown") then
            r.tiles[#r.tiles + 1] = rect(tile)
          end
        end
        run.rows[#run.rows + 1] = r
      end
    end
    run.fonts = {
      title = face(win.title),
      tab = bar.front and face(bar.front.label) or nil,
      tool = face(bar.record and bar.record.label),
      atlas = face(bar.atlas and bar.atlas.label),
      chip = view.pills and view.pills[1] and face(view.pills[1].label) or nil,
      label = view.labels and face(view.labels[1]) or nil,
    }
    run.colours = { band = colour(view.band), rule = colour(view.rule), table = colour(view.table) }
    return run
  end

  local i = 0
  local function step()
    i = i + 1
    local width = widths[i]
    if not width then
      -- back to the reader's own scale, size and place
      if small then
        tryMethod(frame, "SetScale", savedScale)
      end
      win.db.size, win.db.pos = saved.size, saved.pos
      pcall(function()
        win:RestorePlace()
        Window.Render()
      end)
      db.meta.updated = now()
      say(
        "%s: %d widths measured, a screenshot of each; /reload or log out saves the record",
        name,
        #out.runs
      )
      return done()
    end
    local w = math.min(width, math.floor(roomW - 40))
    local ok, err = pcall(function()
      frame:ClearAllPoints()
      frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -60)
      frame:SetSize(w, math.min(BOOKLOOK_HEIGHT, math.floor(roomH - 80)))
      Window.Render()
    end)
    if not ok then
      out.error = tostring(err)
    end
    C_Timer.After(BOOKLOOK_WAIT, function()
      local okRun, run = pcall(measure, w)
      out.runs[#out.runs + 1] = okRun and run or { width = w, error = tostring(run) }
      out.runs[#out.runs].asked = width
      out.runs[#out.runs].screenshot = try(rawget(_G, "Screenshot"))
      C_Timer.After(BOOKLOOK_WAIT, step) -- the screenshot is taken at the frame's end
    end)
  end
  say("%s: measuring Bastian's Book at %d widths, hands off the mouse for a few seconds", name, #widths)
  step()
end

-- The probes of the one look (plan-suite-waves.md W2) in a block of their own: Lua 5.1 allows a
-- chunk 200 local variables, and this file had them. W2 carries what the rest needs.
local W2 = { waiting = false }
local W4 = { waiting = false } -- the windows probe (W4), made below
local events -- the probe's event frame, made below
do
  -- ---------------------------------------------------------------------------------------------
  -- Perf: Core's own snapshot (`/bastians perf`, Perf.lua) taken by the probe a little after every
  -- login, before anything is opened, so tools/perf_report.py has Core's memory in the game without
  -- the owner typing anything (ADR 0082 decision 9: the baseline before the one look, again after W5).
  -- ---------------------------------------------------------------------------------------------

  local PERF_DELAY = 30 -- seconds after the login: the suite has started, nothing is open yet
  local PERF_KEPT = 10

  local function probePerf(note)
    local suite = rawget(_G, "Bastians")
    local perf = suite and rawget(suite, "Perf")
    if not (perf and type(perf.Snapshot) == "function") then
      say("perf: Bastian's Core is not loaded")
      return nil
    end
    local ok, snap = pcall(perf.Snapshot)
    if not (ok and type(snap) == "table") then
      say("perf: the snapshot failed: %s", tostring(snap))
      return nil
    end
    snap.by, snap.note = "probe", note -- the same table Core keeps in its saved variables
    local total, addons = 0, 0
    for _, kb in pairs(snap.memoryKB or {}) do
      total = total + (tonumber(kb) or 0)
      addons = addons + 1
    end
    local core = snap.memoryKB and tonumber(snap.memoryKB.Bastians_Core)
    local list = db.results.perf or {}
    db.results.perf = list
    list[#list + 1] = {
      at = now(),
      note = note,
      build = db.meta and db.meta.build,
      uptime = snap.uptime,
      coreKB = core,
      totalKB = total,
      addons = addons,
      memoryKB = clean(snap.memoryKB),
    }
    while #list > PERF_KEPT do
      table.remove(list, 1)
    end
    say(
      "perf: %s, Core %s KB, the suite %.0f KB in %d addons; saved for tools/perf_report.py",
      note or "a snapshot",
      core and string.format("%.0f", core) or "?",
      total,
      addons
    )
    return list[#list]
  end

  -- ---------------------------------------------------------------------------------------------
  -- Bookmodel (plan-book-round4.md R4.9 and the album of R4.11): can a model frame show a game
  -- object's model, and a model as a dark shape? The camp items place objects whose templates the
  -- server holds: their entries (612122, the Tanning Rack's) are not in the client's GameObjects
  -- table (measured 17.11.2026, build 1.60.1.70938), so which file a camp item's object draws is not
  -- known from the client. What the probe answers is the technique, on object models every client
  -- has (files from GameObjectDisplayInfo), on the creature a camp item summons, and on its item.
  -- Every call in pcall; the screenshot is the proof (a call can succeed and draw nothing).
  -- ---------------------------------------------------------------------------------------------

  local MODEL_CELL = 165
  local MODEL_WAIT = 2.5 -- seconds: a model loads over a few frames
  local MODEL_TESTS = {
    { key = "file", label = "SetModel(file 197466)\na sharpening wheel", call = "SetModel", arg = 197466 },
    {
      key = "fileFar",
      label = "SetModel(file 198338)\na loom, the camera back",
      call = "SetModel",
      arg = 198338,
      far = true,
    },
    { key = "scene", label = "ModelScene actor\nfile 219412, a forge", scene = true, arg = 219412 },
    { key = "item", label = "SetItem(279941)\nthe Tanning Rack's item", call = "SetItem", arg = 279941 },
    { key = "creature", label = "SetCreature(254695)\nthe Repair Bot", call = "SetCreature", arg = 254695 },
    {
      key = "light",
      label = "the same, lit black\n(SetLight)",
      call = "SetCreature",
      arg = 254695,
      dark = "light",
    },
    {
      key = "fog",
      label = "the same, in black fog\n(SetFogColor, Near, Far)",
      call = "SetCreature",
      arg = 254695,
      dark = "fog",
    },
    {
      key = "grey",
      label = "the same, grey\n(SetDesaturation)",
      call = "SetCreature",
      arg = 254695,
      dark = "grey",
    },
  }

  local function darken(model, how)
    if how == "light" then
      -- the retail family's table form first, the older list form second
      local okNew, light = pcall(function()
        return {
          omnidirectional = false,
          point = CreateVector3D(0, 0, 0),
          ambientIntensity = 0,
          ambientColor = CreateColor(0, 0, 0),
          diffuseIntensity = 0,
          diffuseColor = CreateColor(0, 0, 0),
        }
      end)
      local out = {
        table = okNew and tryMethod(model, "SetLight", true, light) or { ok = false, err = tostring(light) },
      }
      if not out.table.ok then
        out.list = tryMethod(model, "SetLight", true, false, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
      end
      return out
    elseif how == "fog" then
      return {
        color = tryMethod(model, "SetFogColor", 0, 0, 0),
        near = tryMethod(model, "SetFogNear", 0),
        far = tryMethod(model, "SetFogFar", 0.01),
      }
    elseif how == "grey" then
      return { set = tryMethod(model, "SetDesaturation", 1) }
    end
    return nil
  end

  local function probeBookModel(_, onDone)
    local out = { at = now(), tests = {} }
    db.results.bookmodel = out
    local d = clearDisplay("Book models: an object's model in a model frame; a model as a dark shape")
    local holder = rawget(d, "models")
    if not holder then
      holder = CreateFrame("Frame", nil, d)
      holder:SetAllPoints(d)
      d.models = holder
      holder.cells = {}
    end
    holder:Show()
    for i, test in ipairs(MODEL_TESTS) do
      local rec = { label = test.label, arg = test.arg }
      out.tests[test.key] = rec
      local c = holder.cells[i]
      if not c then
        c = {}
        holder.cells[i] = c
        local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
        local left, top = 10 + col * (MODEL_CELL + 10), -30 - row * (MODEL_CELL + 44)
        c.bg = holder:CreateTexture(nil, "BACKGROUND")
        c.bg:SetColorTexture(0.9, 0.84, 0.7, 1) -- the paper: a dark shape must be seen against it
        c.bg:SetSize(MODEL_CELL, MODEL_CELL)
        c.bg:SetPoint("TOPLEFT", left, top)
        c.label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        c.label:SetPoint("TOPLEFT", c.bg, "BOTTOMLEFT", 0, -2)
        c.label:SetWidth(MODEL_CELL)
        c.label:SetJustifyH("LEFT")
        -- the frame is placed and sized before its subject is set (the FacePool lesson)
        local okMake, model = pcall(CreateFrame, test.scene and "ModelScene" or "PlayerModel", nil, holder)
        rec.created = okMake and model ~= nil
        if rec.created then
          model:SetSize(MODEL_CELL, MODEL_CELL)
          model:SetPoint("TOPLEFT", left, top)
          model:Show()
          c.model = model
        else
          rec.error = tostring(model)
        end
      end
      c.label:SetText(test.label)
      local model = c.model
      if model and test.scene then
        rec.camera = {
          position = tryMethod(model, "SetCameraPosition", 4, 0, 1),
          orientation = tryMethod(model, "SetCameraOrientationByYawPitchRoll", math.pi, 0, 0),
          fov = tryMethod(model, "SetCameraFieldOfView", 0.9),
          light = tryMethod(model, "SetLightDirection", -0.5, 0.5, -0.7),
        }
        local actor = rawget(c, "actor")
        if not actor then
          local okActor, obj = pcall(function()
            return model:CreateActor()
          end)
          rec.actor = { ok = okActor and obj ~= nil, err = not okActor and tostring(obj) or nil }
          actor = okActor and obj or nil
          c.actor = actor
        end
        if actor then
          rec.set = tryMethod(actor, "SetModelByFileID", test.arg)
          rec.place = tryMethod(actor, "SetPosition", 0, 0, 0)
        end
      elseif model then
        tryMethod(model, "ClearModel")
        rec.set = tryMethod(model, test.call, test.arg)
        if test.far then
          rec.zoom = tryMethod(model, "SetPortraitZoom", 0)
          rec.distance = tryMethod(model, "SetCamDistanceScale", 2)
        end
        rec.dark = darken(model, test.dark)
      end
    end
    C_Timer.After(MODEL_WAIT, function()
      local shown = 0
      for i, test in ipairs(MODEL_TESTS) do
        local c, rec = holder.cells[i], out.tests[test.key]
        local subject = rawget(c, "actor") or c.model
        if subject then
          rec.file = tryMethod(subject, "GetModelFileID")
          local id = rec.file.ok and rec.file.ret[1]
          if type(id) == "number" and id > 0 then
            shown = shown + 1
          end
        end
      end
      out.withFile = shown
      out.screenshot = try(rawget(_G, "Screenshot"))
      db.meta.updated = now()
      say(
        "bookmodel: %d of %d cells name a model file; the screenshot says what is drawn",
        shown,
        #MODEL_TESTS
      )
      if onDone then
        C_Timer.After(BOOKLOOK_WAIT, onDone) -- the screenshot is taken at the frame's end
      end
    end)
  end

  -- ---------------------------------------------------------------------------------------------
  -- Bookreveal: a
  -- zone drawn once as this character explored it (Core's Coords.MapArt) and once with every
  -- overlay of the client's tables (WorldMapOverlay and WorldMapOverlayTile, build 1.60.1.70938,
  -- through tools/mapstyle/blizzard.py), cut by Core's own Coords.OverlayTiles. Assumed until this
  -- runs: the overlay files load by their ids as the explored ones do. Per tile the record says
  -- whether the client holds the file (SetTexture answers true for a file it lacks; GetTexture
  -- stays nil then, CLAUDE.md section 12).
  -- { offsetX, offsetY, textureWidth, textureHeight, the tiles' files row by row }
  -- ---------------------------------------------------------------------------------------------

  local REVEAL_ORDER = { 1420, 1411, 1412 } -- Horde lands: the zone the character saw least of is drawn
  local REVEAL = {
    [1420] = { -- Tirisfal Glades: art 2126, layer 1002 x 668
      { 335, 139, 256, 256, 7958233 },
      { 630, 326, 256, 256, 7958234 },
      { 584, 139, 256, 288, 7958235, 7958236 },
      { 537, 299, 128, 256, 7958237 },
      { 474, 327, 256, 128, 7958238 },
      { 694, 289, 256, 128, 7958239 },
      { 227, 328, 256, 256, 7958240 },
      { 497, 145, 256, 256, 7958241 },
      { 746, 125, 256, 256, 7958242 },
      { 363, 349, 256, 256, 7958243 },
      { 463, 361, 320, 256, 7958244, 7958245 },
      { 689, 104, 256, 256, 7958246 },
      { 239, 250, 256, 256, 7958247 },
      { 395, 277, 256, 128, 7958248 },
      { 698, 362, 256, 256, 7958249 },
      { 757, 205, 245, 256, 7958262 },
      { 4, 198, 335, 424, 7958263, 7958264, 7958265, 7958266 },
    },
    [1411] = { -- Durotar: art 2169, layer 1002 x 668
      { 427, 78, 256, 256, 8073637 },
      { 549, 427, 256, 241, 8074089 },
      { 413, 476, 256, 128, 8074090 },
      { 244, 0, 512, 256, 8074091, 8074092 },
      { 432, 170, 256, 256, 8074093 },
      { 301, 189, 256, 256, 8074094 },
      { 474, 384, 256, 256, 8074095 },
      { 464, 33, 128, 128, 8074096 },
      { 327, 60, 256, 256, 8074097 },
      { 462, 286, 256, 256, 8074098 },
      { 355, 320, 256, 256, 8074099 },
    },
    [1412] = { -- Mulgore: art 1200, layer 1002 x 668
      { 277, 448, 462, 210, 7938948, 7938949 },
      { 262, 349, 171, 231, 7938946 },
      { 357, 328, 238, 206, 7938945 },
      { 458, 389, 121, 136, 7938961 },
      { 494, 381, 253, 151, 7938954 },
      { 509, 279, 227, 214, 7938955 },
      { 451, 289, 143, 139, 7938947 },
      { 419, 170, 220, 214, 7938953 },
      { 369, 266, 151, 158, 7938958 },
      { 270, 265, 194, 164, 7938944 },
      { 250, 131, 284, 204, 7938956, 7938957 },
      { 339, 71, 159, 157, 7938959 },
      { 496, 119, 180, 181, 7938950 },
      { 416, 50, 190, 183, 7938960 },
      { 218, 0, 303, 225, 7938951, 7938952 },
    },
  }
  local REVEAL_W = 345

  local function revealInfos(mapID)
    local infos = {}
    for _, o in ipairs(REVEAL[mapID] or {}) do
      local ids = {}
      for i = 5, #o do
        ids[#ids + 1] = o[i]
      end
      infos[#infos + 1] =
        { offsetX = o[1], offsetY = o[2], textureWidth = o[3], textureHeight = o[4], fileDataIDs = ids }
    end
    return infos
  end

  local function revealPanel(holder, index, art, overlays, caption)
    local panel = holder.panels[index]
    if not panel then
      panel = CreateFrame("Frame", nil, holder)
      panel.pool = {}
      panel.caption = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      panel.caption:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, -4)
      panel.caption:SetWidth(REVEAL_W)
      panel.caption:SetJustifyH("LEFT")
      holder.panels[index] = panel
    end
    local k = REVEAL_W / art.width
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", holder, "TOPLEFT", 10 + (index - 1) * (REVEAL_W + 10), -34)
    panel:SetSize(REVEAL_W, art.height * k)
    local n, loaded, missing = 0, 0, {}
    local function draw(t, sublevel, counted)
      n = n + 1
      local tex = panel.pool[n]
      if not tex then
        tex = panel:CreateTexture(nil, "ARTWORK")
        panel.pool[n] = tex
      end
      local okSet = pcall(tex.SetTexture, tex, t.file)
      tex:SetTexCoord(0, t.tcRight, 0, t.tcBottom)
      tex:SetDrawLayer("ARTWORK", sublevel)
      tex:ClearAllPoints()
      tex:SetPoint("TOPLEFT", panel, "TOPLEFT", t.px1 * k, -t.py1 * k)
      tex:SetSize(math.max(1, (t.px2 - t.px1) * k), math.max(1, (t.py2 - t.py1) * k))
      tex:Show()
      if counted then
        local okGet, got = pcall(tex.GetTexture, tex)
        if okSet and okGet and got ~= nil then
          loaded = loaded + 1
        elseif #missing < 30 then
          missing[#missing + 1] = t.file
        end
      end
    end
    for _, t in ipairs(art.tiles) do
      draw(t, 1, false)
    end
    for _, t in ipairs(overlays) do
      draw(t, t.top and 3 or 2, true)
    end
    for i = n + 1, #panel.pool do
      panel.pool[i]:Hide()
    end
    panel.caption:SetText(string.format("%s: %d overlay tiles, %d loaded", caption, #overlays, loaded))
    return { tiles = #overlays, loaded = loaded, missing = missing }
  end

  local function probeBookReveal(arg, onDone)
    local function done()
      if onDone then
        onDone()
      end
    end
    local suite = rawget(_G, "Bastians")
    local coords = suite and rawget(suite, "Coords")
    if not (coords and type(coords.MapArt) == "function" and type(coords.OverlayTiles) == "function") then
      say("bookreveal: Bastian's Core is not loaded")
      return done()
    end
    local out = { at = now(), zones = {} }
    db.results.bookreveal = out
    -- the zone this character saw least of (a zone given by hand first)
    local mapID, art, fewest
    local asked = tonumber(arg)
    for _, id in ipairs(asked and REVEAL[asked] and { asked } or REVEAL_ORDER) do
      local okArt, a = pcall(coords.MapArt, id)
      local seen = okArt and type(a) == "table" and #(a.explored or {}) or nil
      out.zones[id] = { art = okArt and type(a) == "table", exploredTiles = seen }
      if seen and (fewest == nil or seen < fewest) then
        mapID, art, fewest = id, a, seen
      end
    end
    if not art then
      say("bookreveal: no painting for any of the probe's zones")
      return done()
    end
    out.map = mapID
    local okName, info = pcall(C_Map.GetMapInfo, mapID)
    out.name = okName and type(info) == "table" and info.name or nil
    out.layer = { width = art.width, height = art.height, baseTiles = #art.tiles }
    local okCut, every = pcall(coords.OverlayTiles, revealInfos(mapID))
    if not okCut then
      out.error = tostring(every)
      say("bookreveal: the overlays could not be cut: %s", tostring(every))
      return done()
    end
    local d = clearDisplay(string.format("Book reveal: %s (map %d)", tostring(out.name), mapID))
    local holder = rawget(d, "reveal")
    if not holder then
      holder = CreateFrame("Frame", nil, d)
      holder:SetAllPoints(d)
      d.reveal = holder
      holder.panels = {}
    end
    holder:Show()
    out.explored = revealPanel(holder, 1, art, art.explored or {}, "as this character explored it")
    out.revealed = revealPanel(holder, 2, art, every, "every overlay of the client's tables")
    C_Timer.After(1.5, function()
      out.screenshot = try(rawget(_G, "Screenshot"))
      db.meta.updated = now()
      say(
        "bookreveal: %s, %d of %d overlay tiles loaded (this character had %d); screenshot taken",
        tostring(out.name),
        out.revealed.loaded,
        out.revealed.tiles,
        out.explored.tiles
      )
      if onDone then
        C_Timer.After(BOOKLOOK_WAIT, onDone)
      end
    end)
  end

  -- ---------------------------------------------------------------------------------------------
  -- W2's probes on one restart (plan-suite-waves.md W2, package 5): the models, the reveal, the
  -- book at three widths and at the small screen's scale, one after the other, once, a little after
  -- the login's perf snapshot. `/bprobe w2` runs them again by hand.
  -- ---------------------------------------------------------------------------------------------

  local W2_KEY = "w2-1"

  local function w2Due()
    return not (db.sequences and db.sequences[W2_KEY])
  end

  local function runW2()
    if running then
      C_Timer.After(5, runW2) -- the new build's own probes first
      return
    end
    if InCombatLockdown and InCombatLockdown() then
      W2.waiting = true
      events:RegisterEvent("PLAYER_REGEN_ENABLED") -- after the fight
      return
    end
    running = true
    say("the one look's probes run by themselves for about half a minute: hands off the mouse")
    local steps = {
      function(next)
        probeBookModel(nil, next)
      end,
      function(next)
        probeBookReveal(nil, next)
      end,
      function(next)
        if display then
          display:Hide()
        end
        probeBookLook(nil, next)
      end,
      function(next)
        probeBookLook("small", next)
      end,
    }
    local i = 0
    local function next()
      i = i + 1
      local step = steps[i]
      if not step then
        running = false
        db.sequences = db.sequences or {}
        db.sequences[W2_KEY] = { at = now(), build = db.meta and db.meta.build }
        db.meta.updated = now()
        say("the one look's probes are done: /reload or log out saves the records")
        if W4.due() then
          C_Timer.After(1, W4.run) -- the windows next, once (W4)
        end
        return
      end
      local ok, err = pcall(step, next)
      if not ok then
        say("a probe failed: %s", tostring(err))
        next()
      end
    end
    next()
  end

  W2.perf, W2.model, W2.reveal, W2.run, W2.due = probePerf, probeBookModel, probeBookReveal, runW2, w2Due
  W2.PERF_DELAY = PERF_DELAY
end

-- ---------------------------------------------------------------------------------------------
-- Windows (W4 of plan-suite-waves.md, ADR 0084: "a probe photographs every app's window and names
-- what overflows; no app changed to make it fit"): every app with a window opened in turn as the
-- hub opens it (Bastians:OpenApp), each window that comes up measured and photographed, then
-- closed again; the windows open before are opened again at the end. Named per window: a label
-- the kit cut (an action's `cutTip`), a text the client cut or that is wider than its room, a part
-- standing outside the window. tools/look_windows.py prints the record. Runs once by itself
-- after the first login with the one look (after W2's sequence); `/bprobe windows` by hand.
-- ---------------------------------------------------------------------------------------------

do
  -- "w9-2": the fixes of W9's run (24.11.2026, evening) run it once more by itself; "w9-1"
  -- was W9's first (Quests on the board's spacing, 24.11.2026), "w5-1"
  -- was the frame's run (23.11.2026), "w4-1" the kit's
  local W4_KEY = "w9-2"
  local OPEN_WAIT = 1.2 -- seconds for a window to build and lay itself out
  local SHOT_WAIT = 0.4 -- seconds for the screenshot before the window closes
  local SIZE_WAIT = 0.35 -- seconds for a window to lay itself out at another width
  local NAMED = 25 -- of each kind per window, at most
  -- W5's acceptance: every window at three widths and on the small screen's scale (a 1,920 x
  -- 1,080 screen holds 768 units of height; book-look.md 10.7)
  local WIDTHS = { 1100, 1532, 2100 }
  local SMALL_HEIGHT, SMALL_WIDTH = 768, 1100

  local function rectOf(f)
    local ok, l, r, t, b = pcall(function()
      return f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
    end)
    if not (ok and l and r and t and b) then
      return nil
    end
    return { l = l, r = r, t = t, b = b }
  end

  -- A frame by its name, else where it stands: it and up to three frames above it, each by its
  -- name or its kind and the kit's spec (a chip's kind) until a named one (24.11.2026: two texts
  -- of the Browser could not be found from their words alone, "Button in ?" on the Map).
  local function nameOf(f)
    local parts = {}
    local cur = f
    for _ = 1, 4 do
      if not cur then
        break
      end
      local name = cur.GetName and cur:GetName()
      if name then
        parts[#parts + 1] = name
        break
      end
      local kind = cur.GetObjectType and cur:GetObjectType() or "?"
      local spec = type(cur.spec) == "table" and cur.spec or nil
      local said = spec and (spec.kind or spec.shape) or nil
      parts[#parts + 1] = said and (kind .. ":" .. tostring(said)) or kind
      cur = cur.GetParent and cur:GetParent() or nil
    end
    return table.concat(parts, " < ")
  end

  local function textOf(fs)
    local t = fs.GetText and fs:GetText()
    if type(t) ~= "string" then
      return nil
    end
    t = string.gsub(t, "|c%x%x%x%x%x%x%x%x", "")
    t = string.gsub(t, "|r", "")
    return string.sub(t, 1, 60)
  end

  -- A text the client cut, or one wider than its room on one line.
  local function tooWide(fs)
    local text = textOf(fs)
    if not text or text == "" then
      return nil
    end
    -- IsTruncated and CanWordWrap are retail's; not verified on Forever, so asked protected
    local cut = tryMethod(fs, "IsTruncated")
    local wrap = tryMethod(fs, "CanWordWrap")
    local truncated = cut.ok and cut.ret[1] == true
    local wraps = wrap.ok and wrap.ret[1] == true
    local w, sw = fs:GetWidth(), fs:GetStringWidth()
    if truncated or (not wraps and w and sw and w > 0 and sw > w + 1) then
      return { text = text, room = w, needs = sw }
    end
    return nil
  end

  -- What overflows under `frame`: { cut = { label }, wide = { { text, room, needs, where } },
  -- outside = { { what, l, r, t, b } } } (outside: units past the window's edge on each side).
  -- A scroll frame clips its content, so nothing under one counts as outside; nor does a part of
  -- `own` (the game's frame around a window: its close button stands 3 over the top and its ring
  -- over the corner by the template, which the first run named on every window, 23.11.2026).
  local function overflows(frame, own)
    local out = { cut = {}, wide = {}, outside = {} }
    local box = rectOf(frame)
    local function add(list, v)
      if #list < NAMED then
        list[#list + 1] = v
      end
    end
    local function visit(f, clipped, depth)
      if depth > 30 or not (f.IsShown and f:IsShown()) then
        return
      end
      if type(f.cutTip) == "string" then
        add(out.cut, f.cutTip)
      end
      if box and not clipped and f ~= frame then
        local r = rectOf(f)
        if r and (r.l < box.l - 1 or r.r > box.r + 1 or r.t > box.t + 1 or r.b < box.b - 1) then
          add(out.outside, {
            what = nameOf(f),
            l = r.l - box.l,
            r = r.r - box.r,
            t = r.t - box.t,
            b = r.b - box.b,
          })
        end
      end
      if f.GetRegions then
        for _, region in ipairs({ f:GetRegions() }) do
          if region.GetObjectType and region:GetObjectType() == "FontString" and region:IsShown() then
            -- a cut on purpose: the frame's tip says the whole words (the hub's rail cuts each
            -- app's description to one line, 16 names on every hub window, 24.11.2026)
            local whole = type(f.tip) == "string" and f.tip == region:GetText()
            local wide = not whole and tooWide(region)
            if wide then
              wide.where = nameOf(f)
              add(out.wide, wide)
            end
          end
        end
      end
      local clips = clipped or f == own or (f.GetObjectType and f:GetObjectType() == "ScrollFrame")
      if f.GetChildren then
        for _, child in ipairs({ f:GetChildren() }) do
          visit(child, clips, depth + 1)
        end
      end
    end
    visit(frame, false, 0)
    return out
  end

  local function shownWindows(suite)
    local out = {}
    for name, win in pairs(suite.UI.Windows or {}) do
      if win.frame and win.frame:IsShown() then
        out[name] = win
      end
    end
    return out
  end

  -- The head as the game drew it (W5, ADR 0084 decisions 2 to 4): its kind, where it lies in the
  -- window and how high it is, where the content starts, the name's face and size, the mark.
  local function headOf(win)
    local f, h, c = rectOf(win.frame), win.head and rectOf(win.head), win.content and rectOf(win.content)
    local out = {
      kind = win.headKind,
      bare = type(win.IsBare) == "function" and win:IsBare() or nil,
      shown = win.head and win.head:IsShown() or false,
      portraitGone = win.portraitGone,
      barRow = win.headBar and win.headBar.row == true or nil,
    }
    if f and h then
      out.left, out.top, out.height = h.l - f.l, f.t - h.t, h.t - h.b
    end
    if f and c then
      out.contentTop, out.contentLeft = f.t - c.t, c.l - f.l
    end
    if win.title then
      local ok, font, size = pcall(win.title.GetFont, win.title)
      if ok then
        out.nameFont, out.nameSize = font, size
      end
      out.nameShown = win.title:IsShown()
    end
    if win.mark then
      out.mark, out.markShown = win.mark:GetWidth(), win.mark:IsShown()
    end
    return out
  end

  local function measure(app, name, win)
    local r = rectOf(win.frame)
    local o = overflows(win.frame, win.chrome or nil)
    return {
      app = app,
      window = name,
      width = r and (r.r - r.l) or nil,
      height = r and (r.t - r.b) or nil,
      gameFramed = win.gameFramed == true,
      head = headOf(win),
      cut = o.cut,
      wide = o.wide,
      outside = o.outside,
    }
  end

  -- The other layouts of one window (W5): the three widths its bounds and the screen allow, then
  -- the small screen's scale at 1,100. Each is { width, small, head, cut, wide, outside } with
  -- the counts of what overflows and the first names; `done()` when the window stands as before.
  local function variants(win, record, done)
    local frame = win.frame
    local w0, h0 = frame:GetWidth(), frame:GetHeight()
    local scale0 = frame:GetScale() or 1
    local minW = win.opts and win.opts.minWidth or 300
    local maxW = win.opts and win.opts.maxWidth or 1200
    local screenW = UIParent:GetWidth() or 1920
    local todo = {}
    for _, w in ipairs(WIDTHS) do
      if w >= minW and w <= maxW and w <= screenW - 40 and math.abs(w - w0) > 1 then
        todo[#todo + 1] = { width = w }
      end
    end
    local factor = (UIParent:GetHeight() or SMALL_HEIGHT) / SMALL_HEIGHT
    if factor > 1.01 and SMALL_WIDTH >= minW then
      todo[#todo + 1] = { width = math.min(SMALL_WIDTH, maxW), small = factor }
    end
    record.variants = {}
    local i = 0
    local function restore()
      frame:SetScale(scale0)
      frame:SetSize(w0, h0)
      if win.opts and win.opts.onResize then
        pcall(win.opts.onResize, win, false)
      end
      done()
    end
    local function nextVariant()
      i = i + 1
      local v = todo[i]
      if not v or not frame:IsShown() then
        return restore()
      end
      frame:SetScale(scale0 * (v.small or 1))
      frame:SetWidth(v.width)
      if v.small then
        frame:SetHeight(math.min(h0, SMALL_HEIGHT - 80))
      end
      if win.opts and win.opts.onResize then
        pcall(win.opts.onResize, win, false)
      end
      C_Timer.After(SIZE_WAIT, function()
        local ok, o = pcall(overflows, frame, win.chrome or nil)
        local okH, head = pcall(headOf, win)
        local r = rectOf(frame)
        record.variants[#record.variants + 1] = {
          width = v.width,
          small = v.small,
          got = r and (r.r - r.l) or nil,
          head = okH and head or nil,
          cut = ok and #o.cut or nil,
          wide = ok and #o.wide or nil,
          outside = ok and #o.outside or nil,
          first = ok and (o.cut[1] or (o.wide[1] and o.wide[1].text) or (o.outside[1] and o.outside[1].what))
            or nil,
        }
        nextVariant()
      end)
    end
    nextVariant()
  end

  local function w4Due()
    return not (db.sequences and db.sequences[W4_KEY])
  end

  -- The city map's pins per sheet ("on the separate city map, some
  -- trainers are missing - example is Daryl Riknussum"): what its query gives per layer, what the
  -- cap leaves out, and every trainer the Trainers layer knows on the sheet that is not drawn
  -- (asked whether the layer is on in that window or not). No window needs to be open.
  local function cityPins(suite)
    local mod = suite:GetModule("Map")
    local City = mod and mod.City
    local cities = suite.Map and suite.Map.cities
    if not (City and City.Query and cities) then
      return { why = "no city map (Bastians_Map or its art not loaded)" }
    end
    local out = {}
    for _, city in ipairs(cities) do
      local rec = { ui = city.ui, name = city.name, byLayer = {}, missing = {} }
      local ok, pins = pcall(City.Query, city)
      if not ok then
        rec.why = tostring(pins)
      else
        rec.total = #pins
        rec.cap = City.MAX_PINS
        local drawn = {}
        for i, pin in ipairs(pins) do
          rec.byLayer[pin.layer or "?"] = (rec.byLayer[pin.layer or "?"] or 0) + 1
          if i <= (City.MAX_PINS or #pins) and pin.ref then
            drawn[pin.ref] = true
          end
        end
        local view = {
          continent = city.continent,
          x1 = city.wx[1],
          y1 = city.wy[1],
          x2 = city.wx[2],
          y2 = city.wy[2],
          level = City.QUERY_LEVEL or 6,
        }
        local okT, trainerPins = pcall(suite.QueryLayer, suite, "map.trainers", view)
        if not okT then
          rec.trainersWhy = tostring(trainerPins)
        end
        for _, def in ipairs(suite:GetMapLayers()) do
          if def.id == "map.trainers" then
            rec.trainersOn = City.IsLayerOn(def)
          end
        end
        local found, seen = 0, {}
        for _, pin in ipairs(okT and type(trainerPins) == "table" and trainerPins or {}) do
          if type(pin) == "table" and pin.ref and pin.kind ~= "path" and not seen[pin.ref] then
            seen[pin.ref] = true
            found = found + 1
            if not drawn[pin.ref] and #rec.missing < NAMED then
              rec.missing[#rec.missing + 1] = pin.label or pin.ref
            end
          end
        end
        rec.trainers = found
      end
      out[#out + 1] = rec
    end
    return out
  end

  local function runW4()
    local suite = rawget(_G, "Bastians")
    if not (suite and suite.UI and suite.UI.Windows and suite.IterateModules) then
      say("windows: Bastian's Core is not loaded")
      return
    end
    if running then
      C_Timer.After(5, runW4) -- another probe first
      return
    end
    if InCombatLockdown and InCombatLockdown() then
      W4.waiting = true
      events:RegisterEvent("PLAYER_REGEN_ENABLED") -- after the fight
      return
    end
    running = true
    local S = suite.UI.Style
    local out = {
      at = now(),
      build = db.meta and db.meta.build,
      theme = S and S.ThemeId and S.ThemeId() or nil,
      gameFrames = S and S.Skin and S.Skin("gameFrames") or nil,
      look = S and S.LookId and S.LookId() or nil,
      windows = {},
      skipped = {},
    }
    db.results.windows = out
    -- the windows open now are closed for the run and opened again at its end
    local before = shownWindows(suite)
    for _, win in pairs(before) do
      win.frame:Hide()
    end
    local apps = {}
    for _, mod in suite:IterateModules() do
      if mod.IsEnabled and mod:IsEnabled() and mod.def and type(mod.def.open) == "function" then
        apps[#apps + 1] = mod.name
      end
    end
    say("windows: %d apps open in turn for about %d s: hands off the mouse", #apps, #apps * 4)
    local i = 0
    local function step()
      i = i + 1
      local app = apps[i]
      if not app then
        for _, win in pairs(before) do
          win.frame:Show()
        end
        local okC, cities = pcall(cityPins, suite)
        out.cities = okC and cities or { why = tostring(cities) }
        running = false
        db.sequences = db.sequences or {}
        db.sequences[W4_KEY] = { at = now(), build = db.meta and db.meta.build }
        db.meta.updated = now()
        local troubled = 0
        for _, w in ipairs(out.windows) do
          if #w.cut + #w.wide + #w.outside > 0 then
            troubled = troubled + 1
          end
        end
        say(
          "windows: %d windows of %d apps photographed, %d name something that overflows;"
            .. " /reload saves the record (tools/look_windows.py)",
          #out.windows,
          #apps,
          troubled
        )
        return
      end
      local open = shownWindows(suite)
      local opened = try(function()
        return suite:OpenApp(app)
      end)
      if not (opened.ok and opened.ret and opened.ret[1]) then
        out.skipped[#out.skipped + 1] = { app = app, why = opened.err or "no window" }
        return step()
      end
      C_Timer.After(OPEN_WAIT, function()
        local new = {}
        for name, win in pairs(shownWindows(suite)) do
          if not open[name] then
            local ok, m = pcall(measure, app, name, win)
            if ok then
              out.windows[#out.windows + 1] = m
              new[#new + 1] = { m = m, win = win }
            else
              out.skipped[#out.skipped + 1] = { app = app, window = name, why = tostring(m) }
            end
          end
        end
        if #new == 0 then
          out.skipped[#out.skipped + 1] = { app = app, why = "no new window showed" }
          return step()
        end
        local shot = try(rawget(_G, "Screenshot"))
        for _, n in ipairs(new) do
          n.m.screenshot = shot
        end
        C_Timer.After(SHOT_WAIT, function()
          -- each new window at the other widths and the small scale, one after the other
          local k = 0
          local function nextWindow()
            k = k + 1
            local n = new[k]
            if not n then
              for _, m in ipairs(new) do
                m.win.frame:Hide()
              end
              return step()
            end
            local okV = pcall(variants, n.win, n.m, nextWindow)
            if not okV then
              nextWindow()
            end
          end
          nextWindow()
        end)
      end)
    end
    step()
  end

  W4.run, W4.due, W4.overflows = runW4, w4Due, overflows
end

local function command(msg)
  local cmd, arg = string.match(msg or "", "^%s*(%S*)%s*(.-)%s*$")
  cmd = string.lower(cmd or "")
  if cmd == "" or cmd == "help" then
    for _, line in ipairs(HELP) do
      say(line)
    end
    return
  end
  if cmd == "status" then
    return status()
  elseif cmd == "hide" then
    if display then
      display:Hide()
    end
    if mini then
      mini:Hide()
    end
    return
  elseif cmd == "reset" then
    db.results = {}
    say("results cleared")
    return
  elseif cmd == "all" then
    return runAll()
  elseif cmd == "buttons" then
    return makeFakeButtons(tonumber(arg) or 50)
  end
  recordMeta()
  local probes = {
    p1 = function()
      probeP1()
    end,
    p2 = probeP2,
    p3 = function()
      probeP3()
    end,
    p4 = function()
      probeP4(arg)
    end,
    p5 = function()
      probeP5(arg)
    end,
    p6 = probeP6,
    p10 = probeP10,
    alpha = probeAlpha,
    mask = function()
      probeMask(arg)
    end,
    maskvariants = probeMaskVariants,
    minimaps = function()
      probeMinimaps(arg)
    end,
    books = probeBooks,
    wonders = probeWonders,
    ground = function()
      probeGround(arg)
    end,
    tracking = function()
      if arg == "hover" then
        trackingHover()
      else
        probeTracking()
      end
    end,
    chat = probeChat,
    combatlog = probeCombatLog,
    chatbasics = function()
      probeChatBasics(arg)
    end,
    resize = function()
      probeResize(arg)
    end,
    booktech = probeBookTech,
    portrait = probePortrait,
    booklook = function()
      probeBookLook(arg)
    end,
    bookmodel = function()
      W2.model()
    end,
    bookreveal = function()
      W2.reveal(arg)
    end,
    perf = function()
      W2.perf("by hand")
    end,
    w2 = W2.run,
    windows = function()
      W4.run()
    end,
  }
  local fn = probes[cmd]
  if not fn then
    say("unknown command '%s', see /bprobe help", cmd)
    return
  end
  local ok, err = pcall(fn)
  if not ok then
    say("%s failed: %s", cmd, tostring(err))
  end
end

-- ---------------------------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------------------------

events = CreateFrame("Frame")

-- The truth that grows (plan-data-quality.md E6; "we can stuff my session
-- with automatic probes where it helps"): what the client tells in play, per build, as checks for
-- the packs. Every NPC or object one talks to (its id, name, map and world position) and every
-- merchant's whole stock (item, price for the vendor's stack, the stack, how many). Bounded; an
-- NPC's or object's name only, never a player's. The current build and the one before are kept.
local TRUTH_NPCS = 3000 -- per build
local TRUTH_ITEMS = 200 -- per merchant

local function truth()
  local build = db.meta and db.meta.build or "?"
  db.truth = db.truth or {}
  local t = db.truth[build]
  if not t then
    local older = {}
    for b in pairs(db.truth) do
      older[#older + 1] = b
    end
    table.sort(older, function(a, b)
      return (tonumber(a) or 0) > (tonumber(b) or 0)
    end)
    for i = 2, #older do -- keep the newest build before this one, drop the rest
      db.truth[older[i]] = nil
    end
    t = { npcs = {}, merchants = {}, count = 0 }
    db.truth[build] = t
  end
  return t
end

local function seeNpc(kind)
  local guid = UnitGUID("npc")
  local guidType, id = nil, nil
  if type(guid) == "string" then
    guidType = string.match(guid, "^(%a+)%-")
    id = tonumber(string.match(guid, "^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)"))
  end
  if not id or (guidType ~= "Creature" and guidType ~= "GameObject" and guidType ~= "Vehicle") then
    return nil
  end
  local t = truth()
  local key = (guidType == "GameObject" and "object:" or "npc:") .. id
  local rec = t.npcs[key]
  if not rec then
    if t.count >= TRUTH_NPCS then
      return nil
    end
    local pos = playerPosition()
    local up = pos.unitPosition
    local okName, name = pcall(UnitName, "npc")
    rec = {
      name = okName and name or nil,
      map = pos.mapID,
      x = pos.mapX,
      y = pos.mapY,
      wx = up and up.ok and up.ret[1] or nil,
      wy = up and up.ok and up.ret[2] or nil,
      instance = up and up.ok and up.ret[4] or nil,
      at = now(),
      seen = 0,
      kinds = {},
    }
    t.npcs[key] = rec
    t.count = t.count + 1
  end
  rec.seen = rec.seen + 1
  rec.kinds[kind] = true
  return key
end

local function seeMerchant()
  local key = seeNpc("merchant")
  if not key then
    return
  end
  local okNum, num = pcall(GetMerchantNumItems)
  local count = okNum and tonumber(num) or 0
  local items = {}
  for i = 1, math.min(count, TRUTH_ITEMS) do
    local okInfo, info = pcall(C_MerchantFrame.GetItemInfo, i)
    local okLink, link = pcall(GetMerchantItemLink, i)
    if okInfo and type(info) == "table" then
      items[#items + 1] = {
        item = okLink and type(link) == "string" and tonumber(string.match(link, "item:(%d+)")) or nil,
        price = info.price, -- copper for the vendor's stack (CLAUDE.md, the merchant trap)
        stack = info.stackCount,
        available = info.numAvailable, -- -1: without limit
        extended = info.hasExtendedCost or nil,
      }
    end
  end
  truth().merchants[key] = { at = now(), count = count, items = items }
end

local TRUTH_EVENTS = {
  MERCHANT_SHOW = seeMerchant,
  TRAINER_SHOW = function()
    seeNpc("trainer")
  end,
  TAXIMAP_OPENED = function()
    seeNpc("flight")
  end,
  GOSSIP_SHOW = function()
    seeNpc("gossip")
  end,
  QUEST_DETAIL = function()
    seeNpc("quest")
  end,
  QUEST_PROGRESS = function()
    seeNpc("quest")
  end,
  QUEST_COMPLETE = function()
    seeNpc("quest")
  end,
}

-- The automatic probe on a new build (plan-data-quality.md E5; "yes, should
-- run automatically. we can stuff my session with automatic probes where it helps"). At the first
-- login on a build it holds no record of, the parts that need nobody run by themselves: P1 (the
-- API surface), P3 (the map corners) and P2 (the quest log), sliced and out of combat, a little
-- after the login. A /reload or a logout saves the record; tools/probe_import.py keeps it per build.
local AUTO_DELAY = 20 -- seconds: the loading screen and the suite's own start come first
local AUTO_PARTS = "P1, P3, P2"

local function autoDue()
  local build = db and db.meta and db.meta.build
  return build ~= nil and not (db.auto and db.auto.build == build)
end

local function runAuto()
  if running or not autoDue() then
    return
  end
  if InCombatLockdown and InCombatLockdown() then
    events:RegisterEvent("PLAYER_REGEN_ENABLED") -- after the fight
    return
  end
  running = true
  say("build %s is new to the probe: %s run by themselves", tostring(db.meta.build), AUTO_PARTS)
  probeP1(function()
    probeP3(function()
      local ok, err = pcall(probeP2)
      if not ok then
        say("P2 failed: %s", tostring(err))
      end
      running = false
      db.auto = { build = db.meta.build, at = now(), parts = AUTO_PARTS }
      db.meta.updated = now()
      say("build %s recorded by itself: /reload or log out saves it", tostring(db.meta.build))
    end)
  end)
end

events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then
      return
    end
    BastiansProbeDB = BastiansProbeDB or {}
    db = BastiansProbeDB
    db.results = db.results or {}
    events:UnregisterEvent("ADDON_LOADED")
    events:RegisterEvent("PLAYER_LOGIN")
    events:RegisterEvent("TAXIMAP_OPENED")
    events:RegisterEvent("PLAYER_CONTROL_GAINED")
    events:RegisterEvent("TRAINER_SHOW")
    events:RegisterEvent("MERCHANT_SHOW")
    for name in pairs(TRUTH_EVENTS) do -- the truth that grows (E6)
      events:RegisterEvent(name)
    end
    if type(TakeTaxiNode) == "function" then
      hooksecurefunc("TakeTaxiNode", onTakeTaxiNode)
    end
    if C_Timer and C_Timer.NewTicker then
      C_Timer.NewTicker(1, pollTaxi)
    end
  elseif event == "PLAYER_LOGIN" then
    recordMeta()
    if db.results.ground then
      -- does the ground's switch outlive a /reload or a login? (asked before anything sets it)
      local logins = db.results.ground.logins or {}
      db.results.ground.logins = logins
      if #logins < 20 then
        logins[#logins + 1] = { at = now(), ground = try(resolve("C_Minimap.GetDrawGroundTextures")) }
      end
    end
    say("v%s loaded on %s %s. /bprobe help", VERSION, db.meta.client, tostring(db.meta.build))
    -- the resize recorder (R3.1): windows are built when first opened, so look again now and then
    if C_Timer and C_Timer.NewTicker then
      C_Timer.NewTicker(2, armResize)
    end
    if autoDue() and C_Timer and C_Timer.After then
      C_Timer.After(AUTO_DELAY, runAuto)
    end
    if C_Timer and C_Timer.After then
      -- Core's memory before anything is opened, at every login; then, once, the one look's probes
      C_Timer.After(W2.PERF_DELAY, function()
        local ok, err = pcall(W2.perf, W2.PERF_DELAY .. " s after login")
        if not ok then
          say("perf failed: %s", tostring(err))
        end
        if W2.due() then
          W2.run()
        elseif W4.due() then
          W4.run()
        end
      end)
      -- the portrait's probe (ADR 0090): once by itself, when nothing else runs, out of combat;
      -- its panel closes again after the picture
      local tries = 0 -- in a fight or behind another probe it looks again, four times; then next login
      local function portraitOnce()
        if db.results.portrait then
          return
        end
        if running or (InCombatLockdown and InCombatLockdown()) then
          tries = tries + 1
          if tries <= 4 then
            C_Timer.After(30, portraitOnce)
          end
          return
        end
        local ok, err = pcall(probePortrait, nil, function()
          if display then
            display:Hide()
          end
        end)
        if not ok then
          say("portrait failed: %s", tostring(err))
        end
      end
      C_Timer.After(W2.PERF_DELAY + 45, portraitOnce)
    end
  elseif event == "PLAYER_REGEN_ENABLED" then
    events:UnregisterEvent("PLAYER_REGEN_ENABLED")
    runAuto()
    if W2.waiting then
      W2.waiting = false
      W2.run()
    end
    if W4.waiting then
      W4.waiting = false
      W4.run()
    end
  else
    local handlers = {
      TAXIMAP_OPENED = onTaxiMapOpened,
      PLAYER_CONTROL_GAINED = onControlGained,
      TRAINER_SHOW = onTrainerShow,
      MERCHANT_SHOW = onMerchantShow,
    }
    if not (handlers[event] or TRUTH_EVENTS[event]) then
      return -- an event of another probe's frame
    end
    for _, handler in ipairs({ handlers[event] or false, TRUTH_EVENTS[event] or false }) do
      if handler then
        local ok, err = pcall(handler)
        if not ok then
          say("%s handler failed: %s", event, tostring(err))
        end
      end
    end
  end
end)

SLASH_BASTIANSPROBE1 = "/bprobe"
SlashCmdList.BASTIANSPROBE = command

ns.Probe = { version = VERSION }
