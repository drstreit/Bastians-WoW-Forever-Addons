-- Bastian's Notes (notes.md): notes on things and spots, kept in lists. The model (pure, over the
-- saved table), the module, its registrations (the page and tooltip section, the actions, the map
-- layer, the search) and the reminders.
local ADDON, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
local L = ns.L
local S = B.UI.Style

local Notes = {}
ns.Notes = Notes

Notes.TITLE_MAX, Notes.TEXT_MAX = 60, 500
Notes.NEAR_YARDS = 50 -- a reminder speaks this close
Notes.AWAY_YARDS = 150 -- ... and again only after the character was this far away
Notes.TICK = 2 -- seconds between the near checks, only while near reminders exist here
Notes.COLOURS = { "note1", "note2", "note3", "note4", "note5", "note6" }
-- the suite's glyphs a note may wear (J), tinted with the note's colour
Notes.SYMBOLS = {
  "note",
  "spot",
  "quest",
  "herb",
  "mine",
  "treasure",
  "fish",
  "mob",
  "rare",
  "vendor",
  "innkeeper",
  "trainer",
  "flight",
  "keep",
  "gold",
  "grave",
  "other",
}
-- every type, as "Add note" (a note added on a dungeon's page was nowhere
-- to see, the list missed the types that came later)
Notes.TYPES = "*"
Notes.TARGETABLE = { npc = true, object = true }

local mod

-- a note was kept, changed or removed (core-contracts §16)
B:DeclareMessage("BASTIANS_NOTES_CHANGED")

-- ---------------------------------------------------------------------------------------------
-- The model: plain tables in and out (the saved `global` table is handed in), no WoW API
-- ---------------------------------------------------------------------------------------------

local Model = {}
Notes.Model = Model

local COLOUR_OK, SYMBOL_OK = {}, {}
for _, c in ipairs(Notes.COLOURS) do
  COLOUR_OK[c] = true
end
for _, s in ipairs(Notes.SYMBOLS) do
  SYMBOL_OK[s] = true
end
local REMIND_OK = { near = true, target = true }

local function trim(text)
  return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function Model.Ensure(g)
  g.lists = g.lists or {}
  g.lists.my = g.lists.my or { id = "my", notes = {} }
  -- every list has its notes table: a bookmarks list saved by an earlier build had only its
  -- bookmarks
  for id, list in pairs(g.lists) do
    list.id = list.id or id
    list.notes = list.notes or {}
  end
  g.nextId = g.nextId or 1
  return g
end

function Model.NewId(g, prefix)
  local id = prefix .. g.nextId
  g.nextId = g.nextId + 1
  return id
end

-- The note with this id and its list, or nil.
function Model.Find(g, id)
  for _, list in pairs(g.lists) do
    local n = list.notes[id]
    if n then
      return n, list
    end
  end
  return nil
end

local function isSpot(on)
  return type(on) == "table" and on.map ~= nil and on.wx ~= nil and on.wy ~= nil
end
Model.IsSpot = isSpot

-- Keeps a note: a new one (no id) or a change; moves it to `listId`. -> note, or nil and why.
function Model.Save(g, fields, listId, now)
  local title = trim(fields.title)
  if title == "" then
    return nil, "title"
  end
  local on = fields.on
  if not (isSpot(on) or (type(on) == "string" and on:find(":", 1, true))) then
    return nil, "place"
  end
  local list = g.lists[listId or "my"]
  if not list then
    return nil, "list"
  end
  local note = fields.id and Model.Find(g, fields.id) or nil
  if not note then
    note = { id = Model.NewId(g, "n"), created = now }
  end
  local _, old = Model.Find(g, note.id)
  if old and old ~= list then
    old.notes[note.id] = nil
  end
  note.on = isSpot(on) and { map = on.map, wx = on.wx, wy = on.wy } or on
  note.title = title:sub(1, Notes.TITLE_MAX)
  note.text = trim(fields.text):sub(1, Notes.TEXT_MAX)
  note.symbol = SYMBOL_OK[fields.symbol] and fields.symbol or (isSpot(on) and "spot" or "note")
  note.colour = COLOUR_OK[fields.colour] and fields.colour or "note1"
  note.share = fields.share == "shareable" and "shareable" or "private"
  note.remind = REMIND_OK[fields.remind] and fields.remind or nil
  note.changed = now
  list.notes[note.id] = note
  return note
end

function Model.Remove(g, id)
  local note, list = Model.Find(g, id)
  if note then
    list.notes[id] = nil
  end
  return note ~= nil
end

local function byCreated(a, b)
  if (a.created or 0) ~= (b.created or 0) then
    return (a.created or 0) < (b.created or 0)
  end
  return a.id < b.id
end

-- The notes on a thing, oldest first.
function Model.On(g, ref)
  local out = {}
  for _, list in pairs(g.lists) do
    for _, n in pairs(list.notes) do
      if n.on == ref then
        out[#out + 1] = n
      end
    end
  end
  table.sort(out, byCreated)
  return out
end

-- The spot notes on a continent of the lists not hidden (all lists with `all`).
function Model.Spots(g, map, all)
  local out = {}
  for _, list in pairs(g.lists) do
    if all or not list.hidden then
      for _, n in pairs(list.notes) do
        if isSpot(n.on) and n.on.map == map then
          out[#out + 1] = n
        end
      end
    end
  end
  table.sort(out, byCreated)
  return out
end

-- Every note with a reminder.
function Model.Reminders(g)
  local out = {}
  for _, list in pairs(g.lists) do
    for _, n in pairs(list.notes) do
      if n.remind then
        out[#out + 1] = n
      end
    end
  end
  table.sort(out, byCreated)
  return out
end

-- Notes whose title and text match the query (the suite's search syntax, ADR 0045; a text or a
-- compiled query): { note, score }.
function Model.Search(g, query)
  local q = B.Query.Of(query)
  local out = {}
  if q.empty then
    return out
  end
  for _, list in pairs(g.lists) do
    for _, n in pairs(list.notes) do
      local title, text = n.title:lower(), (n.text or ""):lower()
      if q:MatchLower(title .. "\n" .. text) then
        local score = title == q.joined and 1 or q:MatchLower(title) and 0.8 or 0.5
        out[#out + 1] = { note = n, score = score }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.score ~= b.score then
      return a.score > b.score
    end
    return byCreated(a.note, b.note)
  end)
  return out
end

function Model.NewList(g, name)
  name = trim(name)
  if name == "" then
    return nil
  end
  local id = Model.NewId(g, "l")
  g.lists[id] = { id = id, name = name:sub(1, Notes.TITLE_MAX), notes = {} }
  return g.lists[id]
end

function Model.RenameList(g, id, name)
  local list = g.lists[id]
  name = trim(name)
  if not list or id == "my" or name == "" then
    return false
  end
  list.name = name:sub(1, Notes.TITLE_MAX)
  return true
end

-- Removes a list; its notes move to "My notes".
function Model.RemoveList(g, id)
  local list = g.lists[id]
  if not list or id == "my" then
    return false
  end
  for nid, n in pairs(list.notes) do
    g.lists.my.notes[nid] = n
  end
  g.lists[id] = nil
  return true
end

-- --- bookmarks (E, N2): map views kept in lists; new ones go to the list "Bookmarks" ---------

Model.BOOKMARKS = "bookmarks" -- the list new bookmarks go to (made on first use)

function Model.AddBookmark(g, mark, now)
  local name = trim(mark.name)
  if name == "" or not (mark.continent and mark.wx and mark.wy) then
    return nil
  end
  local list = g.lists[Model.BOOKMARKS]
  if not list then
    list = { id = Model.BOOKMARKS, notes = {} }
    g.lists[Model.BOOKMARKS] = list
  end
  list.bookmarks = list.bookmarks or {}
  local b = {
    id = Model.NewId(g, "b"),
    name = name:sub(1, Notes.TITLE_MAX),
    continent = mark.continent,
    wx = mark.wx,
    wy = mark.wy,
    level = mark.level,
    created = now,
  }
  list.bookmarks[b.id] = b
  return b
end

function Model.FindBookmark(g, id)
  for _, list in pairs(g.lists) do
    local b = list.bookmarks and list.bookmarks[id]
    if b then
      return b, list
    end
  end
  return nil
end

function Model.RenameBookmark(g, id, name)
  local b = Model.FindBookmark(g, id)
  name = trim(name)
  if not b or name == "" then
    return false
  end
  b.name = name:sub(1, Notes.TITLE_MAX)
  return true
end

function Model.RemoveBookmark(g, id)
  local b, list = Model.FindBookmark(g, id)
  if b then
    list.bookmarks[id] = nil
  end
  return b ~= nil
end

-- The bookmarks of the lists not hidden (all with `all`), oldest first.
function Model.Bookmarks(g, all)
  local out = {}
  for _, list in pairs(g.lists) do
    if all or not list.hidden then
      for _, b in pairs(list.bookmarks or {}) do
        out[#out + 1] = b
      end
    end
  end
  table.sort(out, byCreated)
  return out
end

-- --- sharing (G, H, I, N3): what goes, what comes, checked strictly ---------------------------

Model.OFFER_VERSION = 1
Model.OFFER_NOTES, Model.OFFER_BOOKMARKS = 200, 100 -- what a received list may hold at most

-- The value a list is shared as: its shareable notes (private ones stay) and its bookmarks.
-- -> offer, the number of private notes left home.
function Model.SharePayload(g, listId, name)
  local list = g.lists[listId]
  if not list then
    return nil, 0
  end
  local offer = { v = Model.OFFER_VERSION, name = name, notes = {}, bookmarks = {} }
  local private = 0
  local ids = {}
  for id in pairs(list.notes) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local n = list.notes[id]
    if n.share == "shareable" then
      offer.notes[#offer.notes + 1] = {
        on = n.on,
        title = n.title,
        text = n.text,
        symbol = n.symbol,
        colour = n.colour,
      }
    else
      private = private + 1
    end
  end
  for _, b in ipairs(Model.Bookmarks({ lists = { list } }, true)) do
    offer.bookmarks[#offer.bookmarks + 1] =
      { name = b.name, continent = b.continent, wx = b.wx, wy = b.wy, level = b.level }
  end
  return offer, private
end

local function isNumber(v)
  return type(v) == "number" and v == v and v > -1e9 and v < 1e9
end

local function validOn(on)
  if type(on) == "string" then
    return on:match("^%a+:[%w%-]+$") ~= nil and #on <= 64
  end
  return type(on) == "table" and isNumber(on.map) and isNumber(on.wx) and isNumber(on.wy)
end

-- A received offer, cleaned: only known fields, lengths cut, counts capped; nil and why when it
-- is not a list of ours.
function Model.CleanOffer(offer)
  if type(offer) ~= "table" or offer.v ~= Model.OFFER_VERSION then
    return nil, "version"
  end
  local name = trim(type(offer.name) == "string" and offer.name or "")
  if name == "" then
    return nil, "name"
  end
  local out = { name = name:sub(1, Notes.TITLE_MAX), notes = {}, bookmarks = {} }
  for _, n in ipairs(type(offer.notes) == "table" and offer.notes or {}) do
    if #out.notes >= Model.OFFER_NOTES then
      break
    end
    local title = type(n) == "table" and type(n.title) == "string" and trim(n.title) or ""
    if title ~= "" and validOn(n.on) then
      out.notes[#out.notes + 1] = {
        on = type(n.on) == "table" and { map = n.on.map, wx = n.on.wx, wy = n.on.wy } or n.on,
        title = title:sub(1, Notes.TITLE_MAX),
        text = type(n.text) == "string" and n.text:sub(1, Notes.TEXT_MAX) or "",
        symbol = SYMBOL_OK[n.symbol] and n.symbol or nil,
        colour = COLOUR_OK[n.colour] and n.colour or nil,
      }
    end
  end
  for _, b in ipairs(type(offer.bookmarks) == "table" and offer.bookmarks or {}) do
    if #out.bookmarks >= Model.OFFER_BOOKMARKS then
      break
    end
    local bname = type(b) == "table" and type(b.name) == "string" and trim(b.name) or ""
    if bname ~= "" and isNumber(b.continent) and isNumber(b.wx) and isNumber(b.wy) then
      out.bookmarks[#out.bookmarks + 1] = {
        name = bname:sub(1, Notes.TITLE_MAX),
        continent = b.continent,
        wx = b.wx,
        wy = b.wy,
        level = isNumber(b.level) and b.level or nil,
      }
    end
  end
  if #out.notes == 0 and #out.bookmarks == 0 then
    return nil, "empty"
  end
  return out
end

-- An accepted offer becomes a list of its own: the sender and the day kept here only (CLAUDE.md
-- §8); its notes are private until the player shares them again.
function Model.AddReceived(g, offer, from, now)
  local id = Model.NewId(g, "l")
  local list = { id = id, name = offer.name, from = from, date = now, notes = {}, bookmarks = {} }
  g.lists[id] = list
  for i, n in ipairs(offer.notes) do
    local note = Model.Save(g, {
      on = n.on,
      title = n.title,
      text = n.text,
      symbol = n.symbol,
      colour = n.colour,
    }, id, (now or 0) + i / 1000)
    if note then
      note.from = from
    end
  end
  for i, b in ipairs(offer.bookmarks) do
    local mark = { id = Model.NewId(g, "b"), created = (now or 0) + i / 1000 }
    mark.name, mark.continent, mark.wx, mark.wy, mark.level = b.name, b.continent, b.wx, b.wy, b.level
    list.bookmarks[mark.id] = mark
  end
  return list
end

-- The lists, "My notes" first, then by name.
function Model.Lists(g)
  local out = {}
  for _, list in pairs(g.lists) do
    out[#out + 1] = list
  end
  table.sort(out, function(a, b)
    if (a.id == "my") ~= (b.id == "my") then
      return a.id == "my"
    end
    return (a.name or "") < (b.name or "")
  end)
  return out
end

-- ---------------------------------------------------------------------------------------------
-- The module's view of the model
-- ---------------------------------------------------------------------------------------------

function Notes.Global()
  return Model.Ensure(mod.db.global)
end

function Notes.ListName(list)
  if list.id == "my" then
    return L["My notes"]
  end
  return list.name or (list.id == Model.BOOKMARKS and L["Bookmarks"]) or "?"
end

function Notes.Glyph(note)
  return B.UI.GLYPH_PATHS[note.symbol] or B.UI.GLYPH_PATHS.note
end

-- The title in the note's colour, for text.
function Notes.Coloured(note)
  return (S.H[note.colour] or "") .. note.title .. "|r"
end

-- Where a note is, in words: the thing's name or the zone and map percent of a spot.
function Notes.Where(note)
  if Model.IsSpot(note.on) then
    local map = B.Coords.BestMap(note.on.map, note.on.wx, note.on.wy)
    local x, y
    if map then
      x, y = B.Coords.ToMap(note.on.map, note.on.wx, note.on.wy, map)
    end
    local zone = map and B:Entity("zone:" .. map):Name()
    if zone and x then
      return string.format("%s %d, %d", zone, x * 100, y * 100)
    end
    return L["a spot"]
  end
  return B:Entity(note.on):Name() or note.on
end

-- Something changed: the section, the map layer and the Lists window catch up.
function Notes.Changed()
  B:Fire("BASTIANS_NOTES_CHANGED")
  B:Fire("BASTIANS_LAYER_CHANGED", "notes.spots")
  if ns.Lists then
    ns.Lists.Render()
  end
  Notes.ArmReminders()
end

function Notes.Save(fields, listId)
  local note, why = Model.Save(Notes.Global(), fields, listId, time())
  if note then
    Notes.Changed()
  end
  return note, why
end

function Notes.Remove(id)
  local ok = Model.Remove(Notes.Global(), id)
  if ok then
    Notes.Changed()
  end
  return ok
end

-- ---------------------------------------------------------------------------------------------
-- Sharing (N3): a list goes out through Bastians.Comm or as a text; what comes in asks first
-- ---------------------------------------------------------------------------------------------

Notes.KIND = "notes.list" -- the Comm kind of a shared list

function Notes.Payload(listId)
  local list = Notes.Global().lists[listId]
  return Model.SharePayload(Notes.Global(), listId, list and Notes.ListName(list))
end

-- Sends a list to PARTY, RAID, GUILD or WHISPER (target); -> true, or nil and why.
function Notes.Share(listId, channel, target)
  local offer, private = Notes.Payload(listId)
  if not offer or (#offer.notes == 0 and #offer.bookmarks == 0) then
    return nil, "empty"
  end
  local parts, why = B.Comm.Send(Notes.KIND, offer, channel, target)
  if not parts then
    return nil, why
  end
  B:Say(L["Sent: %s (%d notes, %d bookmarks)."], offer.name, #offer.notes, #offer.bookmarks)
  if private > 0 then
    B:Say(L["%d private notes stayed here."], private)
  end
  return true
end

function Notes.ExportText(listId)
  local offer = Notes.Payload(listId)
  return offer and B.Comm.Encode(offer) or nil
end

-- A received or pasted list: checked, then the player decides (I). -> the cleaned offer or nil.
function Notes.Offer(value, from)
  local offer, why = Model.CleanOffer(value)
  if not offer then
    return nil, why
  end
  ns.Share.Ask(offer, from)
  return offer
end

function Notes.ImportText(text)
  local value, why = B.Comm.Decode(text)
  if value == nil then
    return nil, why
  end
  return Notes.Offer(value, L["a pasted text"])
end

function Notes.Accept(offer, from)
  local list = Model.AddReceived(Notes.Global(), offer, from, time())
  Notes.Changed()
  B:Say(L["Kept: %s (%d notes, %d bookmarks)."], list.name, #offer.notes, #offer.bookmarks)
  return list
end

-- ---------------------------------------------------------------------------------------------
-- Location sharing (R26.9, N4): a spot, a thing's place or where I stand, sent to the group; what
-- comes in is a pin for SHARED_MINUTES, kept in memory only (the sender's name never saved)
-- ---------------------------------------------------------------------------------------------

Notes.PIN_KIND = "notes.pin"
Notes.SHARED_MINUTES = 30
Notes.shared = {} -- { { from, at, name, continent, wx, wy, ref } }, newest last

function Model.CleanPin(v)
  if type(v) ~= "table" or v.v ~= Model.OFFER_VERSION then
    return nil
  end
  local name = type(v.name) == "string" and trim(v.name) or ""
  local ok = name ~= "" and isNumber(v.continent) and isNumber(v.wx) and isNumber(v.wy)
  if not ok then
    return nil
  end
  local ref = type(v.ref) == "string" and validOn(v.ref) and v.ref or nil
  return { name = name:sub(1, Notes.TITLE_MAX), continent = v.continent, wx = v.wx, wy = v.wy, ref = ref }
end

-- Sends { name, continent, wx, wy, ref } to the group (default), the guild or one player
-- (channel "WHISPER" with target; R26.16); -> true, or nil and why.
function Notes.SendPin(pin, channel, target)
  channel = channel or B.Compat.GroupChannel()
  if not channel then
    B:Say(L["You are not in a group."])
    return nil, "group"
  end
  if channel == "WHISPER" and not (type(target) == "string" and target ~= "") then
    return nil, "target"
  end
  local value =
    { v = Model.OFFER_VERSION, name = pin.name, continent = pin.continent, wx = pin.wx, wy = pin.wy }
  value.ref = pin.ref
  local parts, why = B.Comm.Send(Notes.PIN_KIND, value, channel, target)
  if parts then
    if channel == "WHISPER" then
      B:Say(L["Sent to %s: %s"], target, pin.name)
    elseif channel == "GUILD" then
      B:Say(L["Sent to your guild: %s"], pin.name)
    else
      B:Say(L["Sent to your group: %s"], pin.name)
    end
  end
  return parts and true or nil, why
end

-- The pins still fresh.
function Notes.SharedPins()
  local now, keep = GetTime(), {}
  for _, p in ipairs(Notes.shared) do
    if now - p.at < Notes.SHARED_MINUTES * 60 then
      keep[#keep + 1] = p
    end
  end
  Notes.shared = keep
  return keep
end

function Notes.ReceivePin(value, from)
  local pin = Model.CleanPin(value)
  if not pin then
    return nil
  end
  pin.from, pin.at = from, GetTime()
  table.insert(Notes.shared, pin)
  B:Say(L["[%s] %s: %s (on your map)"], L["Notes"], from or "?", pin.name)
  B:Fire("BASTIANS_LAYER_CHANGED", "notes.shared", "show")
  return pin
end

-- Where the character stands, as a pin.
function Notes.HerePin()
  local c, wx, wy = B.Coords.Player()
  if not c then
    return nil
  end
  return { name = string.format(L["%s is here"], UnitName("player") or "?"), continent = c, wx = wx, wy = wy }
end

local function sharedPins(view)
  local pins = {}
  for _, p in ipairs(Notes.SharedPins()) do
    if p.continent == view.continent then
      local map = B.Coords.BestMap(p.continent, p.wx, p.wy)
      local minutes = math.floor((GetTime() - p.at) / 60)
      pins[#pins + 1] = {
        ref = p.ref or (map and ("zone:" .. map)) or nil,
        wx = p.wx,
        wy = p.wy,
        icon = B.UI.GLYPH_PATHS.spot,
        color = S.C.accent,
        label = p.name,
        priority = 90,
        cluster = false,
        size = 22,
        card = function()
          return {
            title = p.name,
            lines = {
              { text = string.format(L["From %s, %d min ago"], p.from or "?", minutes), color = "dim" },
            },
            hint = L["Click for a route there"],
          }
        end,
        onClick = function()
          local ctx = { source = "notes", point = { p.continent, p.wx, p.wy, p.name } }
          if B:GetAction("route.here") then
            B:RunAction("route.here", map and ("zone:" .. map) or nil, ctx)
          else
            B:RunAction("map.show", map and ("zone:" .. map) or nil, ctx)
          end
        end,
      }
    end
  end
  return pins
end
Notes.SharedPinsLayer = sharedPins

-- ---------------------------------------------------------------------------------------------
-- Reminders (D): near (a ticker only while such notes exist on this continent) and target
-- ---------------------------------------------------------------------------------------------

local ticker
local spoken = {} -- note id -> true while the character has not been AWAY_YARDS away since

-- A reminder: the chat line, or the voice (Core's Words, plan-launch-review R5.3: the Wanderer
-- hears the note's title and text).
local function say(note)
  local words = note.title .. (note.text ~= "" and (". " .. note.text) or "")
  B:Tell(mod, "reminder", words, function()
    B:Say("[%s] %s%s", L["Notes"], Notes.Coloured(note), note.text ~= "" and (": " .. note.text) or "")
  end)
end

-- The places of a note on a continent in world yards: its spot, or its thing's places.
local function placesOf(note, continent)
  if Model.IsSpot(note.on) then
    return note.on.map == continent and { note.on } or {}
  end
  local out = {}
  for _, p in ipairs(B:Entity(note.on):Places()) do
    if p.map == continent and p.wx then
      out[#out + 1] = { map = p.map, wx = p.wx, wy = p.wy }
    end
  end
  return out
end
Notes.PlacesOf = placesOf

-- One near check: speaks the notes within NEAR_YARDS once, forgets those AWAY_YARDS away.
function Notes.CheckNear()
  local c, px, py = B.Coords.Player()
  if not c then
    return
  end
  for _, note in ipairs(Model.Reminders(Notes.Global())) do
    if note.remind == "near" then
      local nearest
      for _, p in ipairs(placesOf(note, c)) do
        local d = math.sqrt((p.wx - px) ^ 2 + (p.wy - py) ^ 2)
        nearest = (not nearest or d < nearest) and d or nearest
      end
      if nearest and nearest <= Notes.NEAR_YARDS and not spoken[note.id] then
        spoken[note.id] = true
        say(note)
      elseif not nearest or nearest > Notes.AWAY_YARDS then
        spoken[note.id] = nil
      end
    end
  end
end

-- The ticker runs only while a near reminder exists on the character's continent (and reminders
-- are on).
function Notes.ArmReminders()
  local on = mod and mod:IsEnabled() and mod.db.profile.reminders ~= false
  local c = on and B.Coords.Player()
  local needed = false
  for _, note in ipairs(c and Model.Reminders(Notes.Global()) or {}) do
    if note.remind == "near" and #placesOf(note, c) > 0 then
      needed = true
      break
    end
  end
  if needed and not ticker then
    ticker = C_Timer.NewTicker(Notes.TICK, Notes.CheckNear)
  elseif not needed and ticker then
    ticker:Cancel()
    ticker = nil
  end
  return needed
end

local lastTarget
function Notes.OnTarget()
  local ref = B.Compat.TargetEntity()
  if ref == lastTarget then
    return
  end
  lastTarget = ref
  for _, note in ipairs(ref and Model.On(Notes.Global(), ref) or {}) do
    if note.remind == "target" then
      say(note)
    end
  end
end

-- ---------------------------------------------------------------------------------------------
-- The map layer: spot notes
-- ---------------------------------------------------------------------------------------------

local function spotPins(view)
  local pins = {}
  for _, note in ipairs(Model.Spots(Notes.Global(), view.continent)) do
    local map = B.Coords.BestMap(note.on.map, note.on.wx, note.on.wy)
    pins[#pins + 1] = {
      ref = map and ("zone:" .. map) or nil, -- the card's subject: the zone it lies in
      wx = note.on.wx,
      wy = note.on.wy,
      icon = Notes.Glyph(note),
      color = S.C[note.colour],
      label = note.title,
      priority = 70,
      size = 20,
      card = function()
        return {
          title = note.title,
          titleColor = note.colour,
          lines = note.text ~= "" and { { text = note.text, color = "text" } } or {},
          hint = L["Click to edit"],
        }
      end,
      onClick = function()
        ns.Editor.Open(note)
      end,
    }
  end
  return pins
end
Notes.SpotPins = spotPins

-- ---------------------------------------------------------------------------------------------
-- The module
-- ---------------------------------------------------------------------------------------------

local function sectionRows(ref)
  local rows = {}
  for _, note in ipairs(Model.On(Notes.Global(), ref)) do
    rows[#rows + 1] = {
      text = Notes.Coloured(note),
      meta = note.text ~= "" and note.text or nil,
      icon = Notes.Glyph(note),
      onClick = function()
        ns.Editor.Open(note)
      end,
    }
  end
  return rows
end

mod = B:NewModule("Notes", {
  news = ns.NEWS, -- What's new (ADR 0021)
  addon = ADDON,
  open = function()
    ns.Lists.Toggle()
  end,
  title = L["Notes"],
  apiVersion = 1,
  optional = { "Bastians_Data", "Bastians_Map" },
  defaults = {
    profile = { reminders = true, editor = {}, lists = {}, tree = {} },
    global = { lists = {}, nextId = 1 },
  },
  options = {
    { type = "header", label = L["Notes"] },
    {
      type = "toggle",
      key = "reminders",
      label = L["Reminders: say a note when near it or when its NPC is targeted"],
    },
  },
  OnEnable = function(self)
    Model.Ensure(self.db.global)
    B:RegisterDetailSection(self, {
      id = "notes.mine",
      title = L["My notes"],
      types = Notes.TYPES,
      order = 1,
      block = { wide = true, limit = 5, twoLine = true },
      build = sectionRows,
      invalidateOn = { "BASTIANS_NOTES_CHANGED" },
      tooltip = {
        types = Notes.TYPES,
        max = 2,
        build = function(ref)
          local rows = {}
          for _, note in ipairs(Model.On(Notes.Global(), ref)) do
            rows[#rows + 1] = { text = Notes.Coloured(note), icon = Notes.Glyph(note) }
          end
          return rows
        end,
      },
    })
    B:RegisterAction(self, {
      id = "notes.add",
      label = L["Add note"],
      icon = B.UI.IconTexture("open"),
      types = "*",
      order = 60,
      when = function(ref)
        return type(ref) == "string" and ref:find(":", 1, true) ~= nil
      end,
      run = function(ref)
        ns.Editor.Open({ on = ref })
      end,
    })
    -- the map's right click on empty ground: the zone's menu with the point in the context
    B:RegisterAction(self, {
      id = "notes.here",
      label = L["Add note here"],
      icon = B.UI.IconTexture("spot"),
      types = { "zone" },
      order = 61,
      when = function(_, ctx)
        return ctx ~= nil and type(ctx.point) == "table"
      end,
      run = function(_, ctx)
        local pt = ctx.point
        ns.Editor.Open({ on = { map = pt[1], wx = pt[2], wy = pt[3] } })
      end,
    })
    B:RegisterMapLayer(self, {
      id = "notes.spots",
      icon = "note", -- the layer bar shows its icon (R27.8)
      label = L["Notes"],
      tip = L["Your notes on spots; notes on NPCs and quests show on their tooltips."],
      defaultOn = true,
      minLevel = 0,
      query = spotPins,
    })
    B:RegisterSearchProvider(self, {
      id = "notes.titles",
      label = L["Notes"],
      priority = 120,
      search = function(query, limit, _, q)
        local out = {}
        for _, hit in ipairs(Model.Search(Notes.Global(), q or query)) do
          if #out >= (limit or 50) then
            break
          end
          local note = hit.note
          local spot = Model.IsSpot(note.on)
          out[#out + 1] = {
            ref = not spot and note.on or nil,
            label = note.title,
            score = hit.score,
            note = L["Note"] .. " - " .. Notes.Where(note),
            action = spot and function()
              ns.Editor.Open(note)
            end or nil,
          }
        end
        return out
      end,
    })
    -- lists shared by friends (N3): every one asks Accept or Decline first
    B.Comm.Register(self, Notes.KIND, function(value, sender)
      Notes.Offer(value, sender)
    end)
    -- places shared by the group (R26.9, N4)
    B.Comm.Register(self, Notes.PIN_KIND, function(value, sender)
      Notes.ReceivePin(value, sender)
    end)
    B:RegisterMapLayer(self, {
      id = "notes.shared",
      icon = "chain", -- the layer bar shows its icon (R27.8)
      label = L["From others"],
      tip = L["Places your group, your guild or a friend sent you, for half an hour."],
      defaultOn = true,
      minLevel = 0,
      query = sharedPins,
    })
    B:RegisterAction(self, {
      id = "notes.sendhere",
      label = L["Send this spot to my group"],
      icon = B.UI.IconTexture("spot"),
      types = { "zone" },
      order = 62,
      when = function(_, ctx)
        return ctx ~= nil and type(ctx.point) == "table" and B.Compat.GroupChannel() ~= nil
      end,
      run = function(_, ctx)
        local pt = ctx.point
        Notes.SendPin({
          name = pt[4] or Notes.Where({ on = { map = pt[1], wx = pt[2], wy = pt[3] } }),
          continent = pt[1],
          wx = pt[2],
          wy = pt[3],
        })
      end,
    })
    B:RegisterAction(self, {
      id = "notes.send",
      label = L["Send to my group"],
      icon = B.UI.IconTexture("spot"),
      types = "*",
      order = 63,
      when = function(ref)
        return B.Compat.GroupChannel() ~= nil and type(ref) == "string" and ref:find(":", 1, true) ~= nil
      end,
      run = function(ref)
        local c, px, py = B.Coords.Player()
        local best, bd
        for _, p in ipairs(B:Entity(ref):Places()) do
          if p.wx then
            local d = (c and p.map == c) and ((p.wx - px) ^ 2 + (p.wy - py) ^ 2) or math.huge
            if not bd or d < bd then
              best, bd = p, d
            end
          end
        end
        if not best then
          B:Say(L["No place to send."])
          return
        end
        Notes.SendPin({
          name = B:Entity(ref):Name() or ref,
          continent = best.map,
          wx = best.wx,
          wy = best.wy,
          ref = ref,
        })
      end,
    })
    -- the notes service (core-contracts §11): the map's bookmarks live in the lists (E, N2)
    B:ProvideService(self, "notes", {
      -- the spot notes on a continent as plain copies { title, text, wx, wy } (Bastians.API.NotesNear)
      Spots = function(_, continent)
        local out = {}
        for _, note in ipairs(Model.Spots(Notes.Global(), continent)) do
          out[#out + 1] = { title = note.title, text = note.text, wx = note.on.wx, wy = note.on.wy }
        end
        return out
      end,
      Bookmarks = function()
        return Model.Bookmarks(Notes.Global())
      end,
      AddBookmark = function(_, mark)
        local b = Model.AddBookmark(Notes.Global(), mark, time())
        if b then
          Notes.Changed()
        end
        return b
      end,
      RenameBookmark = function(_, id, name)
        local ok = Model.RenameBookmark(Notes.Global(), id, name)
        if ok then
          Notes.Changed()
        end
        return ok
      end,
      RemoveBookmark = function(_, id)
        local ok = Model.RemoveBookmark(Notes.Global(), id)
        if ok then
          Notes.Changed()
        end
        return ok
      end,
      -- where I stand, or a pin, to the group, the guild or a player (R26.16: the Map's player button)
      SendHere = function(_, channel, target)
        local pin = Notes.HerePin()
        if not pin then
          B:Say(L["No map position here (instance?)"])
          return nil, "position"
        end
        return Notes.SendPin(pin, channel, target)
      end,
      SendPin = function(_, pin, channel, target)
        return Notes.SendPin(pin, channel, target)
      end,
      -- the map's own bookmarks, handed over once (oldest first, their order kept)
      Import = function(_, marks)
        local g, n = Notes.Global(), 0
        for i, mark in ipairs(marks or {}) do
          if Model.AddBookmark(g, mark, i) then
            n = n + 1
          end
        end
        Notes.Changed()
        return n
      end,
    }, { priority = 100 })
    self:RegisterEvent("PLAYER_TARGET_CHANGED", function()
      if self.db.profile.reminders ~= false then
        Notes.OnTarget()
      end
    end)
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
      Notes.ArmReminders()
    end)
    self:On("BASTIANS_SETTING_CHANGED", function(_, _, name, key)
      if name == self.name and key == "reminders" then
        Notes.ArmReminders()
      end
    end)
    C_Timer.After(1, Notes.ArmReminders)
    ns.Feed.Register(self) -- the broker displays' feed (ADR 0043)
  end,
  OnDisable = function()
    if ticker then
      ticker:Cancel()
      ticker = nil
    end
    if ns.Editor then
      ns.Editor.Hide()
    end
    if ns.Lists then
      ns.Lists.Hide()
    end
  end,
})
ns.mod = mod
mod.Notes, mod.Model = Notes, Model

SLASH_BASTIANSNOTES1 = "/bnotes"
SlashCmdList.BASTIANSNOTES = function(msg)
  msg = strtrim(msg or "")
  local cmd, arg = string.match(msg, "^(%S*)%s*(.*)$")
  cmd = string.lower(cmd or "")
  if cmd == "" then
    ns.Lists.Toggle()
  elseif cmd == "add" then
    local target = B.Compat.TargetEntity()
    local on = target
    if not on then
      local c, wx, wy = B.Coords.Player()
      on = c and { map = c, wx = wx, wy = wy } or nil
    end
    if not on then
      B:Say(L["No map position here (instance?)"])
      return
    end
    if arg ~= "" then
      local note = Notes.Save({ on = on, title = arg })
      if note then
        B:Say(L["Note kept: %s"], Notes.Coloured(note))
      end
    else
      ns.Editor.Open({ on = on })
    end
  elseif cmd == "here" then
    local pin = Notes.HerePin()
    if pin then
      Notes.SendPin(pin)
    else
      B:Say(L["No map position here (instance?)"])
    end
  else
    B:Say("/bnotes [add <title> | here]")
  end
end
