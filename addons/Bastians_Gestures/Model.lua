-- The pure model of Bastian's Gestures (gestures.md): the default rings, the placeholders, the
-- split of long lines, the wedge under the cursor. Plain tables in,
-- plain tables out; no WoW API.
local _, ns = ...
local L = ns.L

local Model = {}
ns.Model = Model

Model.WEDGES = 8
Model.RINGS = 3
Model.PART_BYTES = 255 -- one chat message of the client, in bytes
Model.MARK_BYTES = 8 -- room for " (12/15)"

-- The game's emotes the ring offers: the DoEmote token and the word (a curated sixty of the
-- client's slash emotes; the tokens are the retail family's, assumed on Forever).
Model.EMOTES = {
  { "WAVE", "Wave" },
  { "BOW", "Bow" },
  { "SALUTE", "Salute" },
  { "HAIL", "Hail" },
  { "CURTSEY", "Curtsey" },
  { "NOD", "Nod" },
  { "HUG", "Hug" },
  { "THANK", "Thank" },
  { "CHEER", "Cheer" },
  { "SIT", "Sit" },
  { "BYE", "Farewell" },
  { "APPLAUD", "Applaud" },
  { "LAUGH", "Laugh" },
  { "DANCE", "Dance" },
  { "KNEEL", "Kneel" },
  { "POINT", "Point" },
  { "SHRUG", "Shrug" },
  { "SIGH", "Sigh" },
  { "SMILE", "Smile" },
  { "GRIN", "Grin" },
  { "WINK", "Wink" },
  { "YAWN", "Yawn" },
  { "SLEEP", "Sleep" },
  { "FLEX", "Flex" },
  { "ROAR", "Roar" },
  { "CRY", "Cry" },
  { "COMFORT", "Comfort" },
  { "CONGRATULATE", "Congratulate" },
  { "GREET", "Greet" },
  { "WELCOME", "Welcome" },
  { "AGREE", "Agree" },
  { "NO", "No" },
  { "THINK", "Think" },
  { "LISTEN", "Listen" },
  { "FOLLOW", "Follow" },
  { "WAIT", "Wait" },
  { "STAND", "Stand" },
  { "EAT", "Eat" },
  { "DRINK", "Drink" },
  { "TOAST", "Toast" },
  { "CLAP", "Clap" },
  { "PRAY", "Pray" },
  { "BLESS", "Bless" },
  { "CALM", "Calm" },
  { "PONDER", "Ponder" },
  { "SURRENDER", "Surrender" },
  { "VICTORY", "Victory" },
  { "CHARGE", "Charge" },
  { "TALK", "Talk" },
  { "TALKEX", "Exclaim" },
  { "TALKQ", "Question" },
  { "WHISTLE", "Whistle" },
  { "PEER", "Peer" },
  { "GAZE", "Gaze" },
  { "BOGGLE", "Boggle" },
  { "MOURN", "Mourn" },
  { "TIRED", "Tired" },
  { "COWER", "Cower" },
  { "BORED", "Bored" },
  { "BECKON", "Beckon" },
}

-- The suite's actions a wedge may hold: id, the word, the kind tile, the app it needs (nil:
-- Core). ~~"Mark heard" and "toggle the tracker" wait for an action of the Orbiter and of Quests~~
-- (since plan-second-wave.md S6, 01.11.2026: `voice.heard`, `quests.tracker`, `route.home`): a
-- wedge can hold only what the registry offers.
Model.ACTIONS = {
  { id = "lore", label = "Lore here", kind = "voice", needs = "Orbiter", action = "voice.play" },
  { id = "screen", label = "Clear the screen", kind = "hide" },
  { id = "screenshot", label = "Screenshot without UI", kind = "scan" },
  { id = "note", label = "Note here", kind = "note", needs = "Notes", action = "notes.here" },
  { id = "spot", label = "Send my spot", kind = "spot", needs = "Notes", action = "notes.sendhere" },
  { id = "home", label = "Route home", kind = "innkeeper", needs = "Route", action = "route.home" },
  { id = "heard", label = "Mark heard", kind = "done", needs = "Orbiter", action = "voice.heard" },
  {
    id = "tracker",
    label = "Toggle the tracker",
    kind = "track",
    needs = "Quests",
    action = "quests.tracker",
  },
}

-- The game's own controls a wedge may hold: id, the
-- word, the kind tile. Safe for an addon out of combat; Compat.RunGame does the call (Model stays
-- free of the WoW API). ~~Walk or run (ToggleRun)~~ is left out: a movement call, protected in the
-- retail family (Blizzard calls it from its bindings only), so an addon's call is blocked.
Model.GAME = {
  { id = "screenshot", label = "Screenshot", kind = "scan" },
  { id = "ui", label = "Show or hide the interface", kind = "hide" },
  { id = "sheath", label = "Sheathe or draw weapons", kind = "mob_dagger" },
  { id = "dismount", label = "Dismount", kind = "flight" },
  { id = "sit", label = "Sit or stand", kind = "invite" },
  { id = "helm", label = "Show or hide the helm", kind = "cloth" },
  { id = "cloak", label = "Show or hide the cloak", kind = "cloth" },
  { id = "mount", label = "A random favourite mount", kind = "flight" },
}

function Model.GameDef(id)
  for _, g in ipairs(Model.GAME) do
    if g.id == id then
      return g
    end
  end
  return nil
end

function Model.ActionDef(id)
  for _, a in ipairs(Model.ACTIONS) do
    if a.id == id then
      return a
    end
  end
  return nil
end

function Model.EmoteWord(token)
  for _, e in ipairs(Model.EMOTES) do
    if e[1] == token then
      return e[2]
    end
  end
  return nil
end

-- The word of a game emote: the curated word, else its command without the slash, capitalised
-- ("/agree" -> "Agree"); the token in the same style when there is no command.
function Model.CommandWord(token, cmd)
  local word = Model.EmoteWord(token)
  if word then
    return word
  end
  local plain = type(cmd) == "string" and cmd:gsub("^/", "") or ""
  if plain == "" then
    plain = string.lower(token or "")
  end
  return string.upper(plain:sub(1, 1)) .. plain:sub(2)
end

-- Emotes whose word or token holds `text` (no case), all of them for an empty text.
function Model.FindEmotes(text)
  text = string.lower(text or "")
  local out = {}
  for _, e in ipairs(Model.EMOTES) do
    if
      text == ""
      or string.find(string.lower(e[2]), text, 1, true)
      or string.find(string.lower(e[1]), text, 1, true)
    then
      out[#out + 1] = e
    end
  end
  return out
end

-- Slots: { kind = "emote", token, label } | { kind = "line", title, text, channel, language } |
-- { kind = "command", title, text } (lines of a macro, editor v2) | { kind = "action", id } |
-- { kind = "game", id } (editor v2) | { kind = "macro", name } (a macro of the player's own, run
-- by a secure button on a click; follow-up of 01.11.2026) | { kind = "ring", name, slots } |
-- false (empty)
local function emote(token)
  return { kind = "emote", token = token, label = Model.EmoteWord(token) or token }
end

local function line(title, text, channel, language)
  return { kind = "line", title = title, text = text, channel = channel or "SAY", language = language }
end

local function action(id)
  return { kind = "action", id = id }
end

-- The three rings as shipped (the design of 01.11.2026).
function Model.DefaultRings()
  return {
    {
      id = "gestures",
      name = L["Gestures"],
      slots = {
        emote("WAVE"),
        emote("BOW"),
        emote("SALUTE"),
        {
          kind = "ring",
          name = L["Greetings"],
          slots = { emote("HAIL"), emote("CURTSEY"), emote("NOD"), emote("HUG"), false, false, false, false },
        },
        emote("THANK"),
        emote("CHEER"),
        emote("SIT"),
        emote("BYE"),
      },
    },
    {
      id = "lines",
      name = L["Lines"],
      slots = {
        line(L["Well met"], L["Well met, %t."], "SAY"),
        line(L["Long road"], L["looks up from the road. The way from %z was long."], "EMOTE"),
        line(L["Thanks, friend"], L["My thanks, friend."], "SAY"),
        line(L["Blessings"], L["Blessings on your road, %t."], "SAY"),
        line(L["Looks around"], L["looks around %a, taking it all in."], "EMOTE"),
        false,
        false,
        false,
      },
    },
    {
      id = "actions",
      name = L["Actions"],
      slots = {
        action("lore"),
        action("screen"),
        action("screenshot"),
        action("note"),
        action("spot"),
        action("home"),
        action("heard"),
        action("tracker"),
      },
    },
  }
end

-- The saved rings, made whole: three rings with eight slots each.
function Model.Ensure(global)
  if type(global.rings) ~= "table" or #global.rings ~= Model.RINGS then
    global.rings = Model.DefaultRings()
  end
  local shipped
  for n, ring in ipairs(global.rings) do
    if type(ring.name) ~= "string" or ring.name == "" then
      shipped = shipped or Model.DefaultRings()
      ring.name = shipped[n].name -- the player's name for a ring, else the shipped word (editor v2)
    end
    ring.slots = ring.slots or {}
    for i = 1, Model.WEDGES do
      if ring.slots[i] == nil then
        ring.slots[i] = false
      end
    end
  end
  return global.rings
end

-- The word and tile of a slot for a wedge.
function Model.Describe(slot)
  if not slot then
    return nil
  end
  if slot.kind == "emote" then
    return slot.label or Model.EmoteWord(slot.token) or slot.token, "invite"
  elseif slot.kind == "line" then
    return slot.title or slot.text, "service"
  elseif slot.kind == "action" then
    local def = Model.ActionDef(slot.id)
    return def and L[def.label] or slot.id, def and def.kind or "other"
  elseif slot.kind == "command" then
    return slot.title or slot.text, "settings"
  elseif slot.kind == "game" then
    local def = Model.GameDef(slot.id)
    return def and L[def.label] or slot.id, def and def.kind or "other"
  elseif slot.kind == "macro" then
    return slot.name, "bookmark"
  elseif slot.kind == "ring" then
    return slot.name, "more"
  end
  return nil
end

-- The ring kit's items of a ring: `available(slot) -> ok, why` says whether an action's app is
-- there. A line's tooltip is its text and language.
-- A macro wedge carries `secure` (Core's ring kit lays a secure button over it); with `hold` (the
-- key held, fired on its release) its tip says that only a click runs it. `secureText(slot)` gives
-- a command slot with a protected line its macro text (#24): it gets a secure button too.
function Model.Items(ring, available, hold, secureText)
  local items = {}
  for i = 1, Model.WEDGES do
    local slot = ring.slots[i]
    if slot then
      local label, kind = Model.Describe(slot)
      local item = { label = label, kind = kind, sub = slot.kind == "ring" or nil, slot = slot }
      if slot.kind == "line" then
        item.tip = slot.text .. (slot.language and (" (" .. slot.language .. ")") or "")
      elseif slot.kind == "command" then
        item.tip = slot.text
      end
      if available then
        local ok, why = available(slot)
        if not ok then
          item.disabled = true
          item.tip = why
        end
      end
      local text = not item.disabled and slot.kind == "command" and secureText and secureText(slot)
      if slot.kind == "macro" and not item.disabled then
        item.secure = { type = "macro", macro = slot.name }
      elseif text then
        item.secure = { type = "macro", macrotext = text }
      end
      if item.secure and hold then
        item.tip = L["Click the wedge (a macro runs only on a click)"]
      end
      items[i] = item
    else
      items[i] = false
    end
  end
  return items
end

-- Placeholders in a line: %t the target's name, %z the zone, %a the area, %r the target's race,
-- %c its class, %g its guild, %n my name, %rp the target's roleplay name; since the editor v2
-- %m my race, %k my class, %f my faction, %l my level, %e he or she
-- (my character), %h the time of day (morning, afternoon, evening, night). A known placeholder
-- without a value becomes nothing (never "0"); an unknown one stays as typed.
local KEYS = {
  t = "target",
  z = "zone",
  a = "area",
  r = "race",
  c = "class",
  g = "guild",
  n = "name",
  rp = "rp",
  m = "myRace",
  k = "myClass",
  f = "faction",
  l = "level",
  e = "sex",
  h = "daytime",
}
Model.PLACEHOLDERS = KEYS

-- The time of day of a game hour (0 to 23): morning from 5, afternoon from 12, evening from 17,
-- night from 21, as its English key; nil for no hour.
function Model.DayKey(hour)
  hour = tonumber(hour)
  if not hour then
    return nil
  end
  hour = math.floor(hour) % 24
  if hour >= 5 and hour < 12 then
    return "morning"
  elseif hour >= 12 and hour < 17 then
    return "afternoon"
  elseif hour >= 17 and hour < 21 then
    return "evening"
  end
  return "night"
end

-- The same in the player's language.
function Model.DayTime(hour)
  local key = Model.DayKey(hour)
  return key and L[key] or nil
end

-- The word of UnitSex's answer: 2 he, 3 she; nil for 1 (unknown) or nothing.
function Model.SexWord(sex)
  if sex == 2 then
    return L["he"]
  elseif sex == 3 then
    return L["she"]
  end
  return nil
end

function Model.Fill(text, ctx)
  ctx = ctx or {}
  return (
    string.gsub(text or "", "%%(%a+)", function(key)
      local field = KEYS[key]
      if field then
        return ctx[field] ~= nil and tostring(ctx[field]) or ""
      end
      local first, rest = key:sub(1, 1), key:sub(2)
      if KEYS[first] then
        return (ctx[KEYS[first]] ~= nil and tostring(ctx[KEYS[first]]) or "") .. rest
      end
      return "%" .. key
    end)
  )
end

-- ---------------------------------------------------------------------------------------------
-- The editor's picker: every choice for a slot in its
-- category, filtered as the player types. Plain tables in, plain tables out.
-- ---------------------------------------------------------------------------------------------

Model.PICK_CAP = 60 -- rows drawn per category; the rest waits for a narrower filter

-- The lines or commands (`kind`) already placed on any ring and sub-ring, each once: copies.
function Model.Placed(rings, kind)
  local out, seen = {}, {}
  local function walk(ring)
    for i = 1, Model.WEDGES do
      local slot = ring.slots and ring.slots[i]
      if slot and slot.kind == kind then
        local key = table.concat({ slot.text or "", slot.channel or "", slot.language or "" }, "|")
        if not seen[key] then
          seen[key] = true
          local copy = {}
          for k, v in pairs(slot) do
            copy[k] = v
          end
          out[#out + 1] = copy
        end
      elseif slot and slot.kind == "ring" then
        walk(slot)
      end
    end
  end
  for _, ring in ipairs(rings or {}) do
    walk(ring)
  end
  return out
end

local function row(label, kind, slot, find, extra)
  local r = { label = label, kind = kind, slot = slot, find = string.lower(label .. " " .. (find or "")) }
  for k, v in pairs(extra or {}) do
    r[k] = v
  end
  return r
end

-- The game's emotes: the curated sixty first ("favourites"), then every other token the client
-- knows ("all"); `game` = { { token, cmd, cmds } } (Compat.GameEmotes). The filter finds a gesture
-- by its word, its token and any of its commands.
local function gestureRows(game)
  local rows, favourite, cmds = {}, {}, {}
  for _, e in ipairs(game or {}) do
    cmds[e.token] = table.concat(e.cmds or { e.cmd }, " ")
  end
  for _, e in ipairs(Model.EMOTES) do
    favourite[e[1]] = true
    local slot = { kind = "emote", token = e[1], label = e[2] }
    rows[#rows + 1] = row(e[2], "invite", slot, e[1] .. " " .. (cmds[e[1]] or ""), { group = "favourites" })
  end
  for _, e in ipairs(game or {}) do
    if not favourite[e.token] then
      local word = Model.CommandWord(e.token, e.cmd)
      local slot = { kind = "emote", token = e.token, label = word }
      rows[#rows + 1] = row(word, "invite", slot, e.token .. " " .. (cmds[e.token] or ""), { group = "all" })
    end
  end
  return rows
end

-- The catalogue: { { id, label, kind, rows = { { label, kind, slot | open, find, group, tip, dim } } } }.
-- `game` = the client's emotes, `rings` the saved rings, `macros` the player's macros
-- (Compat.Macros), `needs(def)` -> why a suite action cannot run (nil: it can), `has(def)` ->
-- whether the client offers a game control. `open` names a form or a step: "line", "command",
-- "ring", "empty".
function Model.Catalogue(game, rings, needs, has, macros)
  local lines = { row(L["A new line..."], "plus", nil, nil, { open = "line" }) }
  for _, slot in ipairs(Model.Placed(rings, "line")) do
    lines[#lines + 1] = row(slot.title or slot.text, "service", slot, slot.text, { tip = slot.text })
  end
  local commands = { row(L["A command or macro..."], "plus", nil, nil, { open = "command" }) }
  for _, slot in ipairs(Model.Placed(rings, "command")) do
    commands[#commands + 1] = row(slot.title or slot.text, "settings", slot, slot.text, { tip = slot.text })
  end
  local mine = {}
  for _, m in ipairs(macros or {}) do
    local slot = { kind = "macro", name = m.name }
    local tip = m.character and L["A macro of this character"] or L["A macro of the account"]
    mine[#mine + 1] = row(m.name, "bookmark", slot, m.body, { tip = tip })
  end
  local suite = {}
  for _, def in ipairs(Model.ACTIONS) do
    local why = needs and needs(def) or nil
    local slot = { kind = "action", id = def.id }
    suite[#suite + 1] = row(L[def.label], def.kind, slot, def.id, { tip = why, dim = why })
  end
  local controls = {}
  for _, def in ipairs(Model.GAME) do
    local missing = has and not has(def) and L["Not in this client"] or nil
    local slot = { kind = "game", id = def.id }
    controls[#controls + 1] = row(L[def.label], def.kind, slot, def.id, { tip = missing, dim = missing })
  end
  local other = {
    row(L["A ring of its own"], "more", nil, nil, { open = "ring" }),
    row(L["Empty"], "clear", nil, nil, { open = "empty" }),
  }
  return {
    { id = "gestures", label = L["Gestures (the game's emotes)"], kind = "invite", rows = gestureRows(game) },
    { id = "lines", label = L["Lines (my own text)"], kind = "service", rows = lines },
    { id = "commands", label = L["Commands and macros"], kind = "settings", rows = commands },
    { id = "macros", label = L["My macros"], kind = "bookmark", rows = mine },
    { id = "suite", label = L["Bastian's Suite"], kind = "app_suite", rows = suite },
    { id = "game", label = L["The game"], kind = "scan", rows = controls },
    { id = "other", label = L["A ring or nothing"], kind = "more", rows = other },
  }
end

-- The catalogue under a filter: the same categories with the rows whose word (or token, command,
-- text) holds `text` (no case); an empty text keeps everything. `total` is the rows that match.
function Model.Filter(catalogue, text)
  text = string.lower(((text or ""):gsub("^%s+", ""):gsub("%s+$", "")))
  local out = {}
  for _, cat in ipairs(catalogue) do
    local rows = {}
    for _, r in ipairs(cat.rows) do
      if text == "" or string.find(r.find, text, 1, true) then
        rows[#rows + 1] = r
      end
    end
    out[#out + 1] = { id = cat.id, label = cat.label, kind = cat.kind, rows = rows, total = #rows }
  end
  return out
end

-- The category a slot belongs to (the picker opens it first); an empty slot of `ring` takes the
-- category most of the ring's slots are in (the Lines ring's empty slot wants a line).
local CATEGORY = {
  emote = "gestures",
  line = "lines",
  command = "commands",
  macro = "macros",
  action = "suite",
  game = "game",
}
function Model.CategoryOf(slot, ring)
  if slot then
    return CATEGORY[slot.kind] or "other"
  end
  local count, best, most = {}, "gestures", 0
  for i = 1, Model.WEDGES do
    local s = ring and ring.slots and ring.slots[i]
    local cat = s and CATEGORY[s.kind]
    if cat then
      count[cat] = (count[cat] or 0) + 1
      if count[cat] > most then
        best, most = cat, count[cat]
      end
    end
  end
  return best
end

-- Parts of at most `limit` bytes, never inside a UTF-8 character, at a space where one is near,
-- each marked " (i/n)" when there are several (the rule of Bastian's Chat).
function Model.Split(text, limit)
  limit = limit or Model.PART_BYTES
  if #text <= limit then
    return { text }
  end
  local room = limit - Model.MARK_BYTES
  local parts = {}
  while #text > room do
    local cut = room
    while cut > 1 and (text:byte(cut + 1) or 0) >= 128 and (text:byte(cut + 1) or 0) < 192 do
      cut = cut - 1
    end
    local space = text:sub(1, cut):match(".*() ")
    if space and space > room / 2 then
      cut = space - 1
    end
    parts[#parts + 1] = text:sub(1, cut)
    text = text:sub(cut + 1):gsub("^ +", "")
  end
  if #text > 0 then
    parts[#parts + 1] = text
  end
  for i = 1, #parts do
    parts[i] = string.format("%s (%d/%d)", parts[i], i, #parts)
  end
  return parts
end

-- The wedge under (dx, dy) from the hub: Core's rule (B.UI.Ring.Hovered), here without Core
-- for the tests of the model.
function Model.Hovered(dx, dy, n, r0, r1)
  local d = math.sqrt(dx * dx + dy * dy)
  if not n or n < 1 or d < r0 or d > r1 then
    return nil
  end
  local a = math.atan2(dx, dy)
  if a < 0 then
    a = a + 2 * math.pi
  end
  local step = 2 * math.pi / n
  return math.floor((a + step / 2) / step) % n + 1
end
