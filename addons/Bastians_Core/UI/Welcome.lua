-- Welcome v2: five
-- panes in one window for both ways: choose your way (two equal cards with their pictures), your
-- pack, your first five minutes (steps that tick from the suite's own events), roleplay with
-- Bastian's, where things are. It shows at every login until "Don't show again" (the General
-- page turns it back on), never in combat, and after an update What's new speaks first.
local _, ns = ...
local B = ns.B
local L = ns.L
local S = ns.Style
local W = B.UI.Widgets

local Welcome = {}
B.UI.Welcome = Welcome

Welcome.PANES = 5
Welcome.page = 1
Welcome.WIDTH, Welcome.HEIGHT = 760, 540

local ART = "Interface\\AddOns\\Bastians_Core\\Media\\Welcome\\"

local win, canvas, scroll, bar, footer

local function settings()
  return B.UI.Settings
end

-- The story, in the owner's words (01.11.2026), on the welcome, the Suite page and the website.
Welcome.STORY = B.UI.Settings.STORY

-- ---------------------------------------------------------------------------------------------
-- The two ways (pure data): the picture, the frame's colour token, the sentence, what you get,
-- the pack's settings, the three steps of the first five minutes and a bonus.
-- ---------------------------------------------------------------------------------------------

Welcome.WAYS = {
  wanderer = {
    id = "wanderer",
    tone = "wayWanderer",
    sentence = L["Explore Azeroth on your own, guided by its voices."],
    gets = {
      L["The land tells its stories as you walk (the Orbiter with Spoken)"],
      L["Talk to people without quest windows"],
      L["Your gestures on a ring, thanks in your own words"],
      L["One key clears the screen for the view"],
    },
    settings = {
      { module = "Core", key = "wordsReminder", label = L["The suite's words"], values = "words" },
      { module = "Voice.Talk", key = "enabled", label = L["Conversations without windows"] },
      { module = "Map", key = "minimapPins", label = L["Pins on the minimap"] },
      { module = "Gestures", key = "courtesy", label = L["Courtesy"], values = "courtesy" },
    },
    steps = {
      { id = "hear", label = L["Hear this place"], tip = L["The Orbiter plays the zone's story."] },
      { id = "greet", label = L["Greet someone"], tip = L["A gesture of the ring: a wave, a bow, a line."] },
      {
        id = "clear",
        label = L["Clear the screen"],
        tip = L["One key hides the interface but the action bars."],
      },
    },
    bonus = { id = "talk", label = L["Talk to a quest giver with the conversation on"] },
  },
  scholar = {
    id = "scholar",
    tone = "wayScholar",
    sentence = L["Every quest, creature, item and place one click away."],
    gets = {
      L["A page for everything, with where and how"],
      L["The way there, by road, flight and boat"],
      L["Prices, and who of your characters has what"],
      L["A tracker that says what to do here"],
    },
    settings = {
      { module = "Map", key = "minimapPins", label = L["Pins on the minimap"] },
      { module = "Core", key = "wordsStep", label = L["Route steps"], values = "words" },
      { module = "Core", key = "tooltipLines", label = L["Extra tooltip lines"], values = "lines" },
    },
    steps = {
      { id = "lookup", label = L["Look something up"], tip = L["The search opens a page for anything."] },
      { id = "route", label = L["Find the way"], tip = L["Route there on anything: road, flight, boat."] },
      {
        id = "worth",
        label = L["Know what it is worth"],
        tip = L["Hover an item in your bags: its price line."],
      },
    },
  },
}
Welcome.KEYS = {
  { action = "BASTIANS_VOICE_ORBIT", label = L["The Orbiter"] },
  { action = "BASTIANS_GESTURES_RING", label = L["The Gestures ring"] },
  { action = "BASTIANS_CLEAR_SCREEN", label = L["Clear the screen"] },
  { action = "BASTIANS_OMNIBOX", label = L["Search"] },
}

-- The pictures by race:
-- the original game's eight races by the client's race file; any other race falls back to its
-- faction's first (human, orc); nil and nil: human. -> the picture's race key.
Welcome.RACES = {
  Human = "human",
  Dwarf = "dwarf",
  NightElf = "nightelf",
  Gnome = "gnome",
  Orc = "orc",
  Scourge = "undead",
  Tauren = "tauren",
  Troll = "troll",
}
function Welcome.RaceKey(raceFile, faction)
  return Welcome.RACES[raceFile or ""] or (faction == "Horde" and "orc") or "human"
end

local function raceKey()
  local _, raceFile = UnitRace("player")
  return Welcome.RaceKey(raceFile, (UnitFactionGroup("player")))
end

-- The picture of a way for this character: one 512 x 256 texture per race and way, the scene
-- cut to 2:1 from its middle (tools/welcome_art.py textures); the cards show it whole, the
-- headers a band of it.
function Welcome.Picture(way)
  return ART .. raceKey() .. "_" .. way
end

-- The Scholar's information layer ("draw it cleanly, anyway easier to change
-- later; stay close to our actual symbols"; "make the symbols much smaller"): drawn by the addon
-- over the clean picture with the suite's own tiles, in the player's language. Positions are
-- fractions of the generated scene (16:9) and hold for every race, because each race's picture
-- keeps the same landscape (`LANDSCAPE`). Heights and distances are the picture's, in yards.
Welcome.LANDSCAPE = 3 -- the autumn forest
Welcome.SCENE = { y0 = 0.052, y1 = 0.948 } -- the part of the 16:9 scene the 2:1 texture holds
Welcome.INFO = {
  { kind = "peak", x = 0.35, y = 0.08, name = L["Highpeak"], high = 1860, away = 4200 },
  { kind = "peak", x = 0.44, y = 0.19, name = L["Greenback Ridge"], high = 940, away = 2900 },
  { kind = "herb", x = 0.30, y = 0.68, name = L["Peacebloom"], away = 210 },
  { kind = "quest", x = 0.47, y = 0.71 },
  { kind = "flight", x = 0.52, y = 0.37 },
  {
    kind = "route",
    points = {
      { 0.22, 0.95 },
      { 0.30, 0.88 },
      { 0.36, 0.82 },
      { 0.41, 0.77 },
      { 0.44, 0.74 },
      { 0.47, 0.71 },
    },
  },
}

-- The label of an information item, pure: "Highpeak  1860 yd high, 4200 yd away".
function Welcome.InfoLabel(item)
  if item.kind == "peak" then
    return item.name .. "  " .. string.format(L["%d yd high, %d yd away"], item.high, item.away)
  elseif item.kind == "herb" then
    return item.name .. "  " .. string.format(L["%d yd away"], item.away)
  end
  return nil
end

-- Where a scene point falls in a picture region that shows the scene's part `view` ({ x0, x1,
-- y0, y1 } in scene fractions): px, py from the region's top left, or nil outside.
function Welcome.Place(x, y, view, w, h)
  local u = (x - view.x0) / (view.x1 - view.x0)
  local v = (y - view.y0) / (view.y1 - view.y0)
  if u < 0 or u > 1 or v < 0 or v > 1 then
    return nil
  end
  return u * w, v * h
end

-- The way the player chose: "wanderer", "scholar", or nil before a choice ("everything" and a
-- custom choice read as the Scholar's table, the Wanderer only when chosen).
function Welcome.Way()
  local id = settings().PlayId()
  if id == "wanderer" then
    return "wanderer"
  elseif id ~= nil then
    return "scholar"
  end
  return nil
end

-- The cards of the first pane, pure: the two ways, equal (owner, decision C).
function Welcome.Cards()
  local Settings_ = settings()
  local chosen = Settings_.PlayId()
  local out = {}
  for _, id in ipairs({ "wanderer", "scholar" }) do
    local preset, way = Settings_.PlayPreset(id), Welcome.WAYS[id]
    out[#out + 1] = {
      id = id,
      name = preset.name,
      sentence = way.sentence,
      gets = way.gets,
      chosen = chosen == id,
      picture = Welcome.Picture(id),
      tone = way.tone,
    }
  end
  return out
end

-- The swatches of the look row, pure: every built-in look preset with the colours of its scheme.
function Welcome.Swatches()
  local Settings_ = settings()
  local current = ns.core.db.profile.preset
  local out = {}
  for _, preset in ipairs(Settings_.PRESETS) do
    local colors = S.ThemeColors(preset.values.theme) or {}
    out[#out + 1] = {
      id = preset.id,
      name = preset.name,
      ground = colors.bg,
      panel = colors.panel,
      text = colors.text,
      accent = colors.accent,
      chosen = current == preset.id,
    }
  end
  return out
end

-- ---------------------------------------------------------------------------------------------
-- The first five minutes: the steps' state (per character) and the events that tick them
-- ---------------------------------------------------------------------------------------------

local function stepState()
  local char = ns.core and ns.core.db and ns.core.db.char
  if not char then
    return {}
  end
  if type(rawget(char, "welcomeSteps")) ~= "table" then
    rawset(char, "welcomeSteps", {})
  end
  return char.welcomeSteps
end

-- The steps of a way with their state, pure but for the saved ticks: { id, label, tip, done,
-- bonus }.
function Welcome.Steps(way)
  local def = Welcome.WAYS[way or "scholar"]
  local done = stepState()
  local out = {}
  for _, step in ipairs(def.steps) do
    out[#out + 1] = { id = step.id, label = step.label, tip = step.tip, done = done[step.id] == true }
  end
  if def.bonus then
    out[#out + 1] =
      { id = def.bonus.id, label = def.bonus.label, done = done[def.bonus.id] == true, bonus = true }
  end
  return out
end

-- Whether every step (not the bonus) of the way is done.
function Welcome.AllDone(way)
  for _, step in ipairs(Welcome.Steps(way)) do
    if not step.bonus and not step.done then
      return false
    end
  end
  return true
end

-- A step happened: ticked for this character, the pane drawn again when it shows. -> whether it
-- was new.
function Welcome.Mark(id)
  local done = stepState()
  if done[id] then
    return false
  end
  done[id] = true
  if Welcome.IsShown() and Welcome.page == 3 then
    Welcome.Render()
  end
  return true
end

-- What a step's "Try it" does: the same thing the player would do, through Core and the
-- registry only (CLAUDE.md §4.3).
function Welcome.Try(id)
  if id == "hear" then
    local map = B.Coords.PlayerMap() or C_Map.GetBestMapForUnit("player")
    return map ~= nil and B:RunAction("voice.play", "zone:" .. map, { source = "welcome" }) or false
  elseif id == "greet" then
    local done = B.Compat.Emote("WAVE", UnitExists("target") and "target" or nil)
    if done then
      Welcome.Mark("greet")
    end
    return done
  elseif id == "clear" then
    B.UI.Screen.Toggle()
    return true
  elseif id == "lookup" then
    B.UI.Omnibox.Open()
    return true
  elseif id == "route" then
    return B:RunAction("route.home", "zone:" .. (B.Coords.PlayerMap() or 0), { source = "welcome" }) or false
  elseif id == "worth" then
    B:Say(L["Hover an item in your bags: Bastian's adds its price line."])
    return true
  end
  return false
end

-- The suite's events that tick the steps (no polling): registered once at load.
local STEP_EVENTS = {
  BASTIANS_VOICE_CHANGED = "hear",
  BASTIANS_GESTURE_FIRED = "greet",
  BASTIANS_PAGE_SHOWN = "lookup",
}
for msg, id in pairs(STEP_EVENTS) do
  ns.on(msg, function()
    Welcome.Mark(id)
  end)
end
ns.on("BASTIANS_SUITE_HIDDEN", function(_, _, hidden)
  if hidden then
    Welcome.Mark("clear")
  end
end)
ns.on("BASTIANS_ROUTE_CHANGED", function(_, _, route)
  if route then
    Welcome.Mark("route")
  end
end)
ns.on("BASTIANS_VOICE_TALK", function(_, _, step)
  if step then
    Welcome.Mark("talk")
  end
end)

-- ---------------------------------------------------------------------------------------------
-- The roleplay pane and the places pane (pure)
-- ---------------------------------------------------------------------------------------------

local function appOn(name)
  local mod = ns.modules[name]
  return mod ~= nil and mod:IsEnabled()
end

-- What the suite offers for roleplay: { id, title, text, app, on, needs }; `on` says whether the
-- app that gives it is installed and enabled, `needs` names it when not (plan 2.6).
function Welcome.Roleplay()
  local rows = {
    {
      id = "voice",
      title = L["The land speaks"],
      text = L["The Orbiter plays Spoken's voices for quests, places, books and bosses, and the game's voice where Spoken has none."], -- luacheck: ignore 631 (a locale key stays one literal)
      app = "Voice",
    },
    {
      id = "talk",
      title = L["Conversations without windows"],
      text = L["Quest givers' words around the Orbiter, your answers as symbols."],
      app = "Voice",
    },
    {
      id = "gestures",
      title = L["Gestures"],
      text = L["Rings of your emotes, lines and macros on one key; a thank-you when someone buffs or resurrects you; a bow or a polite no to a duel or a trade."], -- luacheck: ignore 631 (a locale key stays one literal)
      app = "Gestures",
    },
    {
      id = "screen",
      title = L["The screen for the view"],
      text = L["One key hides the interface but the action bars."],
    },
    {
      id = "chat",
      title = L["Chat for roleplay"],
      text = L["A Roleplay tab (say, emotes, whispers, the NPCs) and a Messenger for whispers."],
      app = "Chat",
    },
    {
      id = "campfire",
      title = L["The campfire"],
      text = L["Sit by a fire together, share it with your group, a camp ring for the evening."],
      app = "Campfire",
    },
  }
  for _, row in ipairs(rows) do
    if row.app then
      row.on = appOn(row.app)
      if not row.on then
        local app = settings().AppByModule(row.app)
        local installed = app and C_AddOns.DoesAddOnExist(app.addon)
        row.needs = string.format(
          installed and L["Switch on %s on the Suite page."] or L["Needs %s."],
          (ns.modules[row.app] and ns.modules[row.app].title) or row.app
        )
      end
    else
      row.on = true
    end
  end
  return rows
end

-- Where things are: { kind, title, text } rows of the last pane.
function Welcome.Places()
  return {
    {
      icon = B.UI.SUITE_ICON,
      title = L["The suite's button at the minimap"],
      text = L["A click opens the search, a right click lists every app."],
    },
    {
      icon = "app_quests",
      title = L["Each app's button"],
      text = L["Every app has a button with its own mark; the Suite page hides the ones you do not want."],
    },
    {
      icon = "settings",
      title = "/bastians",
      text = L["The hub: every app's settings, the Suite page, Help."],
    },
    {
      icon = "note",
      title = L["What's new"],
      text = L["After an update: a dot on the button and /bastians news."],
    },
    { icon = "help", title = L["Help"], text = L["The story, the two ways to play, every command and key."] },
  }
end

-- ---------------------------------------------------------------------------------------------
-- The choices
-- ---------------------------------------------------------------------------------------------

function Welcome.Choose(playId)
  if settings().ApplyPlay(playId) then
    Welcome.Render()
  end
end

function Welcome.PickLook(presetId)
  settings().ApplyPreset(ns.core, presetId)
  Welcome.Render()
end

-- "Don't show again": the welcome stays away at login until the General page says otherwise.
function Welcome.Off()
  ns.core.db.global.welcomeAtLogin = false
  Welcome.Hide()
end

-- ---------------------------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------------------------

local CARD_H, PIC_H, SWATCH_W, SWATCH_H, GAP = 350, 172, 96, 74, 10
local TILE, RING, LABEL = 11, 8, 9 -- the information layer's sizes: small
local HEADER_H = 112

local function clear()
  for _, w in ipairs(canvas.widgets or {}) do
    w:Hide()
    w:SetParent(nil)
  end
  canvas.widgets = {}
end

local function add(w)
  canvas.widgets[#canvas.widgets + 1] = w
  return w
end

local function heading(text, y, size)
  local f = add(CreateFrame("Frame", nil, canvas))
  f:SetPoint("TOPLEFT", canvas, "TOPLEFT", 12, y)
  f:SetPoint("RIGHT", canvas, "RIGHT", -12, 0)
  f:SetHeight(22)
  f.label = S.heading(f, size or 15)
  f.label:SetPoint("LEFT", 0, 0)
  f.label:SetText(text)
  f.text, f.kind = text, "header"
  return f
end

local function note(text, y, color, x)
  local f = add(W.Note(canvas, text, color))
  f:SetPoint("TOPLEFT", canvas, "TOPLEFT", x or 12, y)
  f:SetPoint("RIGHT", canvas, "RIGHT", -12, 0)
  f.text, f.kind = text, "note"
  return f
end

-- Draws the Scholar's information layer on `region` (a frame over a picture that shows the
-- scene's part `view`): a dotted route, small tiles, rings on the peaks with a short leader up to
-- a one-line label on a dark plate. Only what falls inside is drawn; labels when `labels`.
local function info(region, view, labels)
  local w, h = region:GetWidth() or 1, region:GetHeight() or 1
  region.marks = {}
  local function mark(o)
    region.marks[#region.marks + 1] = o
    return o
  end
  for _, item in ipairs(Welcome.INFO) do
    if item.kind == "route" then
      for i = 1, #item.points - 1 do
        local a, b = item.points[i], item.points[i + 1]
        for k = 0, 2 do
          local t = k / 3
          local px, py = Welcome.Place(a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, view, w, h)
          if px then
            local dot = mark(region:CreateTexture(nil, "OVERLAY"))
            dot:SetTexture(S.DISC)
            dot:SetSize(3, 3)
            dot:SetPoint("CENTER", region, "TOPLEFT", px, -py)
            S.tint(dot, S.C.bright, 0.85)
          end
        end
      end
    else
      local px, py = Welcome.Place(item.x, item.y, view, w, h)
      if px then
        local m = mark(region:CreateTexture(nil, "OVERLAY"))
        if item.kind == "peak" then
          m:SetTexture(S.RINGS.S)
          m:SetSize(RING, RING)
          S.tint(m, S.C.bright, 0.9)
        else
          m:SetTexture(B.UI.IconTexture(item.kind))
          m:SetSize(TILE, TILE)
        end
        m:SetPoint("CENTER", region, "TOPLEFT", px, -py)
        m.kind = item.kind
        local text = labels and Welcome.InfoLabel(item)
        if text then
          local up = py > 24 -- the label above the mark, below it near the top edge
          local lead = mark(region:CreateTexture(nil, "OVERLAY"))
          lead:SetTexture(S.WHITE)
          lead:SetSize(1, 8)
          lead:SetPoint(up and "BOTTOM" or "TOP", m, up and "TOP" or "BOTTOM", 0, 0)
          S.tint(lead, S.C.bright, 0.7)
          local plate = mark(CreateFrame("Frame", nil, region))
          plate.label = S.text(plate, LABEL, S.C.text)
          plate.label:SetPoint("CENTER", 0, 0)
          plate.label:SetText(text)
          plate.bg = S.fill(plate, S.C.bg)
          plate.bg:SetAlpha(0.72)
          plate:SetSize((plate.label:GetStringWidth() or (#text * 5)) + 8, LABEL + 5)
          plate:SetPoint(up and "BOTTOM" or "TOP", lead, up and "TOP" or "BOTTOM", 0, 0)
          plate.text = text
        end
      end
    end
  end
end
Welcome.DrawInfo = info

-- The chosen way's picture as the pane's header, in a thin frame of the way's colour.
local function header(y, width)
  local way = Welcome.WAYS[Welcome.Way() or "scholar"]
  local f = add(CreateFrame("Frame", nil, canvas))
  f:SetPoint("TOPLEFT", canvas, "TOPLEFT", 12, y)
  f:SetSize(width - 24, HEADER_H)
  S.panel(f, S.C.card)
  S.setEdges(f.edges, S.C[way.tone], 1)
  f.picture = f:CreateTexture(nil, "ARTWORK")
  f.picture:SetPoint("TOPLEFT", 1, -1)
  f.picture:SetPoint("BOTTOMRIGHT", -1, 1)
  f.picture:SetTexture(Welcome.Picture(way.id))
  local aspect = (width - 26) / (HEADER_H - 2) -- the 2:1 picture cut to the band from its middle
  local h = math.min(1, 2 / aspect)
  f.picture:SetTexCoord(0, 1, 0.5 - h / 2, 0.5 + h / 2)
  f.way = way.id
  if way.id == "scholar" then
    local span = Welcome.SCENE.y1 - Welcome.SCENE.y0
    local view = { x0 = 0, x1 = 1, y0 = Welcome.SCENE.y0 + (0.5 - h / 2) * span }
    view.y1 = Welcome.SCENE.y0 + (0.5 + h / 2) * span
    f.layer = CreateFrame("Frame", nil, f)
    f.layer:SetAllPoints(f.picture)
    f.layer:SetSize(width - 26, HEADER_H - 2)
    info(f.layer, view, false) -- a thin band: the marks without their labels
  end
  return y - HEADER_H - 10
end

-- A card: the picture, the way's name, its sentence, what you get, Choose.
local function card(spec, x, y, width)
  local f = add(CreateFrame("Button", nil, canvas))
  f:SetPoint("TOPLEFT", canvas, "TOPLEFT", x, y)
  f:SetSize(width, CARD_H)
  S.panel(f, S.C.card)
  S.setEdges(f.edges, spec.chosen and S.C.accent or S.C[spec.tone], spec.chosen and 2 or 1)
  f.picture = f:CreateTexture(nil, "ARTWORK")
  f.picture:SetPoint("TOPLEFT", 1, -1)
  f.picture:SetPoint("TOPRIGHT", -1, -1)
  f.picture:SetHeight(PIC_H)
  f.picture:SetTexture(spec.picture)
  if spec.id == "scholar" then
    -- the whole scene: the Scholar sees what the Wanderer does not
    f.layer = CreateFrame("Frame", nil, f)
    f.layer:SetPoint("TOPLEFT", f.picture, "TOPLEFT")
    f.layer:SetSize(width - 2, PIC_H)
    info(f.layer, { x0 = 0, x1 = 1, y0 = Welcome.SCENE.y0, y1 = Welcome.SCENE.y1 }, true)
  end
  f.title = S.heading(f, 16, nil, spec.chosen and S.C.accent or nil)
  f.title:SetPoint("TOPLEFT", f.picture, "BOTTOMLEFT", 10, -8)
  f.title:SetPoint("RIGHT", -10, 0)
  f.title:SetJustifyH("LEFT")
  f.title:SetText(spec.name)
  f.sentence = S.text(f, 12, S.C.text)
  f.sentence:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
  f.sentence:SetPoint("RIGHT", -10, 0)
  f.sentence:SetJustifyH("LEFT")
  f.sentence:SetWordWrap(true)
  f.sentence:SetText(spec.sentence)
  f.getsTitle = S.text(f, 11, S.C.dim)
  f.getsTitle:SetPoint("TOPLEFT", f.sentence, "BOTTOMLEFT", 0, -8)
  f.getsTitle:SetText(L["What you get"])
  local lines = {}
  for _, line in ipairs(spec.gets) do
    lines[#lines + 1] = "- " .. line
  end
  f.gets = S.text(f, 11, S.C.text)
  f.gets:SetPoint("TOPLEFT", f.getsTitle, "BOTTOMLEFT", 0, -4)
  f.gets:SetPoint("RIGHT", -10, 0)
  f.gets:SetJustifyH("LEFT")
  f.gets:SetWordWrap(true)
  f.gets:SetText(table.concat(lines, "\n"))
  f.choose = S.action(f, {
    icon = spec.chosen and "done" or "arrow",
    label = spec.chosen and L["Chosen"] or L["Choose"],
    primary = not spec.chosen,
    boxed = spec.chosen,
  })
  f.choose:SetPoint("BOTTOMRIGHT", -10, 10)
  f.choose:SetScript("OnClick", function()
    Welcome.Choose(spec.id)
  end)
  f.spec = spec
  f:SetScript("OnClick", function()
    Welcome.Choose(spec.id)
  end)
  f:SetScript("OnEnter", function(self)
    S.setEdges(self.edges, S.C.accent, 2)
  end)
  f:SetScript("OnLeave", function(self)
    S.setEdges(
      self.edges,
      self.spec.chosen and S.C.accent or S.C[self.spec.tone],
      self.spec.chosen and 2 or 1
    )
  end)
  return f
end

-- A swatch: a small window of the preset's colours (ground, header, two text bars, the accent).
local function swatch(spec, x, y)
  local f = add(CreateFrame("Button", nil, canvas))
  f:SetPoint("TOPLEFT", canvas, "TOPLEFT", x, y)
  f:SetSize(SWATCH_W, SWATCH_H)
  S.panel(f, S.C.card)
  if spec.chosen then
    S.setEdges(f.edges, S.C.accent, 2)
  end
  local function strip(color, px, py, w, h)
    local t = f:CreateTexture(nil, "ARTWORK")
    t:SetPoint("TOPLEFT", px, -py)
    t:SetSize(w, h)
    if color then
      t:SetColorTexture(color[1], color[2], color[3], 1) -- another theme's token, not a raw colour
    else
      S.tint(t, S.C.dim)
    end
    return t
  end
  f.ground = strip(spec.ground, 6, 6, SWATCH_W - 12, 40)
  f.header = strip(spec.panel, 6, 6, SWATCH_W - 12, 9)
  f.line1 = strip(spec.text, 12, 20, SWATCH_W - 24, 4)
  f.accent = strip(spec.accent, 12, 32, 24, 6)
  f.label = S.text(f, 10, spec.chosen and S.C.accent or S.C.text)
  f.label:SetPoint("BOTTOM", 0, 6)
  f.label:SetText(spec.name)
  f.spec = spec
  f.tip = spec.name
  f:SetScript("OnClick", function()
    Welcome.PickLook(spec.id)
  end)
  f:SetScript("OnEnter", S.TipEnter)
  f:SetScript("OnLeave", S.TipLeave)
  return f
end

-- One row with a title, its words, and on the right a button or a state word.
local function row(y, title, text, action, state, icon)
  local f = add(CreateFrame("Frame", nil, canvas))
  f:SetPoint("TOPLEFT", canvas, "TOPLEFT", 12, y)
  f:SetPoint("RIGHT", canvas, "RIGHT", -12, 0)
  local x = 0
  if icon then
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(18, 18)
    f.icon:SetPoint("TOPLEFT", 0, -2)
    f.icon:SetTexture(B.UI.IconTexture(icon))
    x = 26
  end
  f.title = S.text(f, 12, S.C.text)
  f.title:SetPoint("TOPLEFT", x, 0)
  f.title:SetPoint("RIGHT", -150, 0)
  f.title:SetJustifyH("LEFT")
  f.title:SetText(title)
  f.body = S.text(f, 11, S.C.dim)
  f.body:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -2)
  f.body:SetPoint("RIGHT", -150, 0)
  f.body:SetJustifyH("LEFT")
  f.body:SetWordWrap(true)
  f.body:SetText(text or "")
  if action then
    f.action = action
    action:SetParent(f)
    action:ClearAllPoints()
    action:SetPoint("TOPRIGHT", 0, 0)
  elseif state then
    f.state = S.text(f, 11, S.C.dim)
    f.state:SetPoint("TOPRIGHT", 0, -2)
    f.state:SetText(state)
  end
  local h = 18 + (f.body:GetStringHeight() or 12)
  f:SetHeight(math.max(26, h))
  f.text = title
  return f, y - math.max(26, h) - 8
end

local function pane1(width)
  local y = -10
  heading(L["Choose your way"], y)
  y = y - 26
  local story = note(Welcome.STORY, y, S.C.text)
  y = y - (story:GetHeight() or 30) - 10
  local cards = Welcome.Cards()
  local cardW = math.floor((width - 24 - GAP) / 2)
  for i, spec in ipairs(cards) do
    card(spec, 12 + (i - 1) * (cardW + GAP), y, cardW)
  end
  y = y - CARD_H - 10
  local all = add(S.action(canvas, { icon = "plus", label = L["Or switch everything on"] }))
  all:SetPoint("TOPLEFT", canvas, "TOPLEFT", 12, y)
  all.tip = L["Every app on, the Orbiter too; decide later on the Suite page."]
  all:SetScript("OnClick", function()
    Welcome.Choose("everything")
  end)
  return y - 34
end

local VALUES = {
  words = function()
    return { text = L["Text"], voice = L["Voice"], both = L["Both"] }
  end,
  courtesy = function()
    return { ask = L["Ask"], auto = L["Automatic"], off = L["Off"] }
  end,
  lines = function()
    return { [0] = "0", [3] = "3", [6] = "6", [10] = "10" }
  end,
}

-- The pack's settings that exist here: { def, mod } of the way's list.
function Welcome.PackSettings(way)
  local out = {}
  for _, def in ipairs(Welcome.WAYS[way].settings) do
    local mod = def.module == "Core" and ns.core or ns.modules[def.module]
    if mod and mod.db and (def.key == "enabled" or mod.db.profile[def.key] ~= nil) then
      out[#out + 1] = { def = def, mod = mod }
    end
  end
  return out
end

local function pane2(width)
  local way = Welcome.Way() or "scholar"
  local y = header(-10, width)
  heading(L["Your pack"], y)
  y = y - 26
  local Settings_ = settings()
  local preset = Settings_.PlayPreset(way)
  for _, app in ipairs(Settings_.Apps()) do
    if app.module ~= "Data" and preset and preset.apps[app.module] then
      local mod = ns.modules[app.module]
      local box = W.Checkbox(canvas, "", function(on)
        if mod then
          if on then
            mod:Enable()
          else
            mod:Disable()
          end
          Settings_.PlayCustom()
        end
      end)
      box:SetWidth(20)
      box:SetChecked(mod ~= nil and mod:IsEnabled())
      local _
      _, y = row(y, (mod and mod.title) or app.module, app.about, box)
    end
  end
  heading(L["What matters for this way"], y, 13)
  y = y - 24
  for _, s in ipairs(Welcome.PackSettings(way)) do
    local def, mod = s.def, s.mod
    local f
    if def.values then
      f = add(W.Select(canvas, def.label, VALUES[def.values](), function(v)
        mod.db.profile[def.key] = v
        B:Fire("BASTIANS_SETTING_CHANGED", mod.name, def.key, v)
      end))
      f:SetValue(mod.db.profile[def.key])
    else
      local on = def.key == "enabled" and mod:IsEnabled() or mod.db.profile[def.key]
      f = add(W.Checkbox(canvas, def.label, function(v)
        if def.key == "enabled" then
          if v then
            mod:Enable()
          else
            mod:Disable()
          end
        else
          mod.db.profile[def.key] = v
          B:Fire("BASTIANS_SETTING_CHANGED", mod.name, def.key, v)
        end
      end))
      f:SetChecked(on and true or false)
    end
    f:SetPoint("TOPLEFT", canvas, "TOPLEFT", 12, y)
    f:SetPoint("RIGHT", canvas, "RIGHT", -12, 0)
    y = y - 26
  end
  heading(L["Your keys"], y, 13)
  y = y - 24
  for _, k in ipairs(Welcome.KEYS) do
    local key = B.Compat.BindingKey(k.action)
    local _
    _, y = row(y, k.label, nil, nil, key or L["not set"])
  end
  local set = add(S.action(canvas, { icon = "settings", label = L["Set the keys"], boxed = true }))
  set:SetPoint("TOPLEFT", canvas, "TOPLEFT", 12, y)
  set.tip = L["Opens the game's Key Bindings, where every key of Bastian's is set."]
  set:SetScript("OnClick", function()
    B.Compat.OpenKeyBindings()
  end)
  y = y - 36
  heading(L["Look"], y, 13)
  y = y - 24
  local perRow = math.max(1, math.floor((width - 24 + GAP) / (SWATCH_W + GAP)))
  for i, spec in ipairs(Welcome.Swatches()) do
    local col, r = (i - 1) % perRow, math.floor((i - 1) / perRow)
    swatch(spec, 12 + col * (SWATCH_W + GAP), y - r * (SWATCH_H + GAP))
  end
  return y - math.ceil(#Welcome.Swatches() / perRow) * (SWATCH_H + GAP)
end

local function pane3(width)
  local way = Welcome.Way() or "scholar"
  local y = header(-10, width)
  heading(L["Your first five minutes"], y)
  y = y - 26
  for _, step in ipairs(Welcome.Steps(way)) do
    local try = S.action(canvas, {
      icon = step.done and "done" or "play",
      label = step.done and L["Done"] or L["Try it"],
      boxed = true,
    })
    add(try)
    try:SetScript("OnClick", function()
      Welcome.Try(step.id)
    end)
    local title = (step.bonus and (L["Bonus"] .. ": ") or "") .. step.label
    local _
    _, y = row(y, title, step.tip, try, nil, step.done and "done" or "waiting")
  end
  if Welcome.AllDone(way) then
    note(L["You know the way."], y, S.C.good)
    y = y - 22
  end
  return y
end

local function pane4(width)
  local y = header(-10, width)
  heading(L["Roleplay with Bastian's"], y)
  y = y - 26
  for _, r in ipairs(Welcome.Roleplay()) do
    local _
    _, y =
      row(y, r.title, r.needs and (r.text .. " " .. r.needs) or r.text, nil, r.on and L["on"] or L["off"])
  end
  return y
end

local function pane5(width)
  local y = header(-10, width)
  heading(L["Where things are"], y)
  y = y - 26
  for _, p in ipairs(Welcome.Places()) do
    local _
    _, y = row(y, p.title, p.text, nil, nil, p.icon)
  end
  return y
end

local function updateFooter()
  local page = Welcome.page
  footer.back:SetShown(page > 1)
  footer.dots:SetText(string.format(L["%d of %d"], page, Welcome.PANES))
  footer.next:SetShown(page < Welcome.PANES)
  footer.done:SetShown(page == Welcome.PANES)
  local glow = page == 3 and Welcome.AllDone(Welcome.Way())
  footer.next:SetOn(glow)
end

function Welcome.Render()
  if not canvas then
    return
  end
  clear()
  canvas:SetWidth(math.max(100, (scroll:GetWidth() or 700)))
  local width = canvas:GetWidth() or 700
  local panes = { pane1, pane2, pane3, pane4, pane5 }
  local y = panes[Welcome.page](width)
  canvas.contentHeight = -y + 10
  canvas:SetHeight(canvas.contentHeight)
  bar.SetTotal(canvas.contentHeight)
  updateFooter()
end

function Welcome.ShowPane(n)
  Welcome.page = math.max(1, math.min(Welcome.PANES, n))
  Welcome.Render()
end

local function build()
  win = B.UI.Window("BastiansWelcomeFrame", {
    title = L["Welcome to Bastian's Suite"],
    width = Welcome.WIDTH,
    height = Welcome.HEIGHT,
    db = ns.core.db.profile.welcome,
    onResize = Welcome.Render,
  })
  footer = CreateFrame("Frame", nil, win.content)
  footer:SetPoint("BOTTOMLEFT", 0, 0)
  footer:SetPoint("BOTTOMRIGHT", 0, 0)
  footer:SetHeight(34)
  footer.off = S.action(footer, { icon = "close", label = L["Don't show again"] })
  footer.off:SetPoint("LEFT", 12, 0)
  footer.off.tip = L["The welcome stays away at login; the General page brings it back."]
  footer.off:SetScript("OnClick", function()
    Welcome.Off()
  end)
  footer.back = S.action(footer, { icon = "back", label = L["Back"], boxed = true })
  footer.back:SetPoint("LEFT", footer.off, "RIGHT", 10, 0)
  footer.back:SetScript("OnClick", function()
    Welcome.ShowPane(Welcome.page - 1)
  end)
  footer.dots = S.text(footer, 11, S.C.dim)
  footer.dots:SetPoint("CENTER", 0, 0)
  footer.next = S.action(footer, { icon = "arrow", label = L["Next"], primary = true })
  footer.next:SetPoint("RIGHT", -12, 0)
  footer.next:SetScript("OnClick", function()
    Welcome.ShowPane(Welcome.page + 1)
  end)
  footer.done = S.action(footer, { icon = "done", label = L["Into the world"], primary = true })
  footer.done:SetPoint("RIGHT", -12, 0)
  footer.done:SetScript("OnClick", function()
    win:Hide()
  end)
  scroll = CreateFrame("ScrollFrame", nil, win.content)
  scroll:SetPoint("TOPLEFT", 0, 0)
  scroll:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -14, 0)
  canvas = CreateFrame("Frame", nil, scroll)
  canvas:SetSize(700, 1)
  canvas.widgets = {}
  scroll:SetScrollChild(canvas)
  bar = S.scrollbar(scroll, win.content)
  Welcome.win, Welcome.canvas, Welcome.footer = win, canvas, footer
end

-- Shows the window on `page`; without one, a player who chose a way opens on the first five
-- minutes (plan 2.2: a returning player sees progress, not the choice again).
function Welcome.Show(page)
  if not win then
    build()
  end
  Welcome.page = page or (Welcome.Way() and 3 or 1)
  win:Show()
  Welcome.Render()
end

function Welcome.Hide()
  if win then
    win:Hide()
  end
end

function Welcome.IsShown()
  return win ~= nil and win:IsShown()
end

-- At login (News.Check, a few seconds after PLAYER_LOGIN): the window unless switched off, never in
-- combat (then as soon as the combat ends), and not after an update with news (What's new speaks
-- first; the welcome comes the next login). -> whether it was shown.
local waiter
function Welcome.AtLogin(updated)
  local g = ns.core and ns.core.db and ns.core.db.global
  if not g or g.welcomeAtLogin == false or updated then
    return false
  end
  if InCombatLockdown and InCombatLockdown() then
    if not waiter then
      waiter = CreateFrame("Frame")
      waiter:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        Welcome.AtLogin()
      end)
    end
    waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
    return false
  end
  Welcome.Show()
  return true
end
