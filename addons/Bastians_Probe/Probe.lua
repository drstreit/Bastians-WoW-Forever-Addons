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
  display:SetFrameStrata("DIALOG")
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

local HELP = {
  "/bprobe all  - P1, P2, P3, P5, P6, P10 (automatic probes)",
  "/bprobe p1 | p2 | p3 | p5 [fileID or path] | p6 | p10  - one probe",
  "/bprobe p4 <label>  - record a landmark at your position (and your target: NPC, object, node)",
  "/bprobe alpha  - the Map_Art overview cells over red (transparency test)",
  "/bprobe mask [fdid name] - a native coast tile with its Map_Art sea mask over red",
  "/bprobe maskvariants - which of four test mask files the client loads",
  "P7, trainer and merchant record by themselves: open a flight map, take a flight,"
    .. " open a trainer or a vendor",
  "/bprobe status | hide | reset",
}

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
    return
  elseif cmd == "reset" then
    db.results = {}
    say("results cleared")
    return
  elseif cmd == "all" then
    return runAll()
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

local events = CreateFrame("Frame")
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
    if type(TakeTaxiNode) == "function" then
      hooksecurefunc("TakeTaxiNode", onTakeTaxiNode)
    end
    if C_Timer and C_Timer.NewTicker then
      C_Timer.NewTicker(1, pollTaxi)
    end
  elseif event == "PLAYER_LOGIN" then
    recordMeta()
    say("v%s loaded on %s %s. /bprobe help", VERSION, db.meta.client, tostring(db.meta.build))
  else
    local handlers = {
      TAXIMAP_OPENED = onTaxiMapOpened,
      PLAYER_CONTROL_GAINED = onControlGained,
      TRAINER_SHOW = onTrainerShow,
      MERCHANT_SHOW = onMerchantShow,
    }
    local ok, err = pcall(handlers[event])
    if not ok then
      say("%s handler failed: %s", event, tostring(err))
    end
  end
end)

SLASH_BASTIANSPROBE1 = "/bprobe"
SlashCmdList.BASTIANSPROBE = command

ns.Probe = { version = VERSION }
