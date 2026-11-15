-- Bastian's Chat version 3, the proposed answers (plan-chat-v3.md §5, V12; "No
-- answer should ever be send automatically - just propose a clickable plate"): for a conversation's
-- last line from the partner, the plates the player may click, built from what was asked (where are
-- you, item level, level, a recipe, an invite, a price), from the player's situation (a fight, a
-- dungeon, dead), from how the player knows the partner, and the player's own lines kept as
-- answers. Each plate is a template the player may change on the settings page (§5.3); the plates
-- used most for a question come first (counted here, per question, never other players' words). A
-- plate whose fact is unknown is left out, never filled with 0 (golden rule 2). The facts come from
-- the client (Compat) and the suite's services, each optional.
local _, ns = ...
local B = Bastians
local L = ns.L
local Model, Compat, Record, Intent = ns.Model, ns.Compat, ns.Record, ns.Intent

local Answers = {}
ns.Answers = Answers

Answers.MAX = 5 -- plates at most
Answers.OWN_MAX = 12 -- the player's own lines kept as answers
local CLOSE = { friend = true, bnet = true, guild = true, group = true }

-- The plates' slots (§5.3), in the order they are offered: `ask` the question that offers it,
-- `situation` the player's state, `close` friends, the guild and the group, `stranger` everyone
-- else; `when` a further test of the facts. `text` is the English line (the locale's key), the
-- player's own words for it are kept in the profile (`answers.templates`; "" switches it off).
-- Placeholders: {zone} {subzone} {coords} {ilvl} {level} {alt} {count} {price} {name}, and since
-- V23 {courtesy} (a line of Courtesy's), {dest} and {eta} (Route's flight). A part in
-- square brackets goes when a placeholder in it has no value; a template with an unknown value
-- outside them is not offered.
Answers.SLOTS = {
  {
    id = "where",
    ask = "where",
    label = "Where are you?",
    text = "I'm in {zone}[, {subzone}][ ({coords})].",
  },
  { id = "ilvl", ask = "ilvl", label = "Your item level?", text = "My item level is {ilvl}." },
  { id = "level", ask = "level", label = "Your level?", text = "I'm level {level}." },
  {
    id = "recipeYes",
    ask = "recipe",
    label = "A recipe you can make",
    text = "Yes, I can make that.",
    when = function(f)
      return f.known ~= nil and f.known.me == true
    end,
  },
  {
    id = "recipeAlt",
    ask = "recipe",
    label = "A recipe one of your characters can make",
    text = "Not on this character, but my {alt} can.",
    when = function(f)
      return not (f.known and f.known.me == true)
    end,
  },
  {
    id = "recipeNo",
    ask = "recipe",
    label = "A recipe none of yours can make",
    text = "No, sorry, I can't make that.",
    when = function(f)
      return f.known ~= nil and f.known.me == false and not (f.known.alts and f.known.alts[1])
    end,
  },
  { id = "recipeCheck", ask = "recipe", label = "A recipe, not sure yet", text = "Let me check." },
  {
    id = "invite",
    ask = "invite",
    label = "Asked for an invite",
    text = "Sure, sending an invite.",
    invites = true, -- the plate also invites
    when = function(f)
      return not f.full
    end,
  },
  {
    id = "full",
    ask = "invite",
    label = "Asked for an invite, the group is full",
    text = "Sorry, the group is full.",
    when = function(f)
      return f.full == true
    end,
  },
  {
    id = "priceHave",
    ask = "price",
    label = "Still selling? The count and the price",
    text = "I have {count}, {price} each.",
  },
  {
    id = "priceStill",
    ask = "price",
    label = "Still selling? Yes",
    text = "Still there.",
    when = function(f)
      return type(f.count) == "number" and f.count > 0
    end,
  },
  {
    id = "priceSold",
    ask = "price",
    label = "Still selling? Sold",
    text = "Sold, sorry.",
    when = function(f)
      return f.count == 0
    end,
  },
  -- thanks, congratulations, greetings (V23): a line of Courtesy's, and a plain one
  { id = "thanksCourtesy", ask = "thanks", label = "Thanked: a line of Courtesy's", text = "{courtesy}" },
  { id = "thanks", ask = "thanks", label = "Thanked", text = "You're welcome." },
  { id = "gzCourtesy", ask = "gz", label = "Congratulated: a line of Courtesy's", text = "{courtesy}" },
  { id = "gz", ask = "gz", label = "Congratulated", text = "Thank you!" },
  { id = "hiCourtesy", ask = "hi", label = "Greeted: a line of Courtesy's", text = "{courtesy}" },
  { id = "hi", ask = "hi", label = "Greeted", text = "Hi {name}!" },
  { id = "fight", situation = "combat", label = "In a fight", text = "In a fight, one moment." },
  {
    id = "flight",
    situation = "flight",
    label = "On a flight",
    text = "On a flight[ to {dest}][, there in {eta}].",
  },
  { id = "dead", situation = "dead", label = "Dead", text = "Dead right now, give me a minute." },
  { id = "dungeon", situation = "instance", label = "In a dungeon", text = "In a dungeon right now, later?" },
  { id = "omw", close = true, label = "Friends, the guild and the group: on my way", text = "omw" },
  { id = "sure", close = true, label = "Friends, the guild and the group: yes", text = "sure" },
  { id = "busy", stranger = true, label = "Strangers", text = "Sorry, busy right now." },
  { id = "moment", label = "Always", text = "One moment." },
}
local SLOT = {}
for _, slot in ipairs(Answers.SLOTS) do
  SLOT[slot.id] = slot
end

function Answers.Slot(id)
  return SLOT[id]
end

-- The profile's part: { templates = { [slot] = text }, own = { text }, uses = { [ask] = { [key] = n } } }.
function Answers.Settings()
  local p = ns.mod.db.profile
  p.answers = type(p.answers) == "table" and p.answers or {}
  local s = p.answers
  for _, key in ipairs({ "templates", "own", "uses" }) do
    s[key] = type(s[key]) == "table" and s[key] or {}
  end
  return s
end

-- A slot's template: the player's own words, else the line in the client's language.
function Answers.Template(id)
  local own = Answers.Settings().templates[id]
  if type(own) == "string" then
    return own
  end
  return SLOT[id] and L[SLOT[id].text] or nil
end

-- The player's words for a slot; nil or the default's words put the default back, "" switches
-- the plate off.
function Answers.SetTemplate(id, text)
  if not SLOT[id] then
    return
  end
  if type(text) == "string" then
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
  end
  if text == nil or text == L[SLOT[id].text] then
    Answers.Settings().templates[id] = nil
  else
    Answers.Settings().templates[id] = text
  end
end

-- A template filled with the values (pure): nil when a placeholder outside square brackets has no
-- value or the template is empty.
function Answers.Fill(template, values)
  if type(template) ~= "string" or not template:find("%S") then
    return nil
  end
  values = values or {}
  local function sub(text)
    local missing = false
    local out = text:gsub("{(%a+)}", function(key)
      local v = values[key]
      if v == nil then
        missing = true
        return ""
      end
      return tostring(v)
    end)
    return out, missing
  end
  local outer = template:gsub("%[(.-)%]", function(part)
    local filled, missing = sub(part)
    return missing and "" or filled
  end)
  local out, missing = sub(outer)
  if missing or not out:find("%S") then
    return nil
  end
  return out
end

-- The placeholders' values from the facts, each nil when unknown (pure).
function Answers.Values(f)
  f = f or {}
  local known = f.known
  return {
    zone = f.zone,
    subzone = f.subzone,
    coords = (type(f.x) == "number" and type(f.y) == "number") and ("%.0f, %.0f"):format(f.x, f.y) or nil,
    ilvl = f.ilvl,
    level = f.level,
    alt = known and known.alts and known.alts[1] or nil,
    count = f.count,
    price = f.price,
    name = f.partner and Model.ShortName(f.partner) or nil,
    courtesy = f.courtesy,
    dest = f.dest,
    eta = type(f.etaSecs) == "number" and L["%d min"]:format(math.max(1, math.ceil(f.etaSecs / 60))) or nil,
  }
end

-- What a line asks (Intent's question), or nil: the line as a whisper record.
function Answers.Asked(text)
  if type(text) ~= "string" then
    return nil
  end
  local rec = {
    chatType = "WHISPER",
    body = text,
    plain = Model.Strip(text):lower(),
    links = Record.Links(text),
  }
  local it = Intent.Parse(rec, ns.Chat.Facts().words)
  return it and it.kind == "ask" and it or nil
end

local function add(out, seen, plate)
  if plate and plate.text and not seen[plate.text] then
    seen[plate.text] = true
    out[#out + 1] = plate
  end
end

local function slotPlate(slot, facts, values)
  if slot.when and not slot.when(facts) then
    return nil
  end
  local text = Answers.Fill(Answers.Template(slot.id), values)
  return text and { text = text, id = slot.id, invites = slot.invites } or nil
end

-- The candidates (pure but for the profile's templates and own lines): it the question or nil,
-- facts as Answers.Facts gives them, s = { combat, dead, instance }, rel the partner's relation.
-- In the order offered before the counts sort them: the question's, the player's own lines, the
-- situation's, the relation's, "One moment".
function Answers.Candidates(it, facts, s, rel)
  local out, seen = {}, {}
  facts, s = facts or {}, s or {}
  local values = Answers.Values(facts)
  if it then
    for _, slot in ipairs(Answers.SLOTS) do
      if slot.ask == it.ask then
        add(out, seen, slotPlate(slot, facts, values))
      end
    end
  end
  for _, text in ipairs(Answers.Settings().own) do
    if type(text) == "string" and text ~= "" then
      add(out, seen, { text = text, own = true })
    end
  end
  for _, slot in ipairs(Answers.SLOTS) do
    if slot.situation and s[slot.situation] then
      add(out, seen, slotPlate(slot, facts, values))
    end
  end
  for _, slot in ipairs(Answers.SLOTS) do
    local fits = (slot.close and CLOSE[rel]) or (slot.stranger and not CLOSE[rel])
    if fits or (not slot.ask and not slot.situation and not slot.close and not slot.stranger) then
      add(out, seen, slotPlate(slot, facts, values))
    end
  end
  return out
end

-- A plate's key for the counts: its slot, or the player's own line.
function Answers.Key(plate)
  return plate.id or ("own:" .. tostring(plate.text))
end

-- The candidates the player used most for this question first (a stable sort), at most MAX.
function Answers.Rank(plates, ask)
  local uses = Answers.Settings().uses[ask or "none"] or {}
  local order = {}
  for i, plate in ipairs(plates) do
    order[plate] = i
  end
  table.sort(plates, function(a, b)
    local ua, ub = uses[Answers.Key(a)] or 0, uses[Answers.Key(b)] or 0
    if ua ~= ub then
      return ua > ub
    end
    return order[a] < order[b]
  end)
  while #plates > Answers.MAX do
    table.remove(plates)
  end
  return plates
end

-- A plate was used for this question (a click or Shift+click).
function Answers.Used(plate, ask)
  local uses = Answers.Settings().uses
  local key = ask or "none"
  uses[key] = uses[key] or {}
  local k = Answers.Key(plate)
  uses[key][k] = (uses[key][k] or 0) + 1
end

-- The player's own line kept as an answer (a sent bubble's "Keep as an answer"); false when it was
-- kept already or the list is full.
function Answers.Keep(text)
  if type(text) ~= "string" or not text:find("%S") then
    return false
  end
  local own = Answers.Settings().own
  for _, t in ipairs(own) do
    if t == text then
      return false
    end
  end
  if #own >= Answers.OWN_MAX then
    return false
  end
  own[#own + 1] = text
  return true
end

function Answers.IsKept(text)
  for _, t in ipairs(Answers.Settings().own) do
    if t == text then
      return true
    end
  end
  return false
end

function Answers.Forget(text)
  local own = Answers.Settings().own
  for i = #own, 1, -1 do
    if own[i] == text then
      table.remove(own, i)
    end
  end
  for _, counts in pairs(Answers.Settings().uses) do
    counts["own:" .. tostring(text)] = nil
  end
end

-- The facts the client gives for a question (each nil when unknown).
function Answers.Facts(it, partner)
  local f = {}
  if it and it.ask == "where" then
    f.zone, f.subzone, f.x, f.y = Compat.Where()
  elseif it and it.ask == "ilvl" then
    f.ilvl = Compat.ItemLevel()
  elseif it and it.ask == "level" then
    f.level = Compat.PlayerLevel()
  elseif it and it.ask == "recipe" and it.link and it.link.id then
    local knowledge = B:GetService("knowledge")
    if knowledge and (it.link.kind == "spell" or it.link.kind == "enchant") then
      local ok, known = pcall(knowledge.Known, knowledge, it.link.id)
      f.known = ok and known or nil
    end
  elseif it and it.ask == "invite" then
    f.full = Compat.GroupFull()
  elseif it and it.ask == "price" and it.item then
    f.count = Compat.ItemCount(it.item)
    local prices = B:GetService("prices")
    if prices then
      local ok, p = pcall(prices.Price, prices, it.item)
      f.price = ok and p and p.median and B.UI.MoneyShort(p.median) or nil
    end
  end
  if it and (it.ask == "thanks" or it.ask == "gz" or it.ask == "hi") then
    local courtesy = B:GetService("courtesy") -- V23: a line of the player's moods
    if courtesy and type(courtesy.Line) == "function" then
      local ok, line = pcall(courtesy.Line, courtesy, it.ask, partner)
      f.courtesy = ok and type(line) == "string" and line ~= "" and line or nil
    end
  end
  if Compat.Situation().flight then
    local route = B:GetService("route") -- V23: where the flight goes and when it lands
    if route and type(route.Flight) == "function" then
      local ok, fl = pcall(route.Flight, route)
      if ok and type(fl) == "table" then
        f.dest, f.etaSecs = fl.to, fl.seconds
      end
    end
  end
  f.partner = partner
  return f
end

-- The plates for a conversation: { { text, id or own, invites }, ask = the question or nil }.
function Answers.For(convo)
  if not convo or not convo.lines then
    return {}
  end
  local last = convo.lines[#convo.lines]
  if not last or last.out then
    return {} -- nothing yet, or the player answered already
  end
  local it = Answers.Asked(last.text)
  local rel = convo.name and ns.Chat.Relation(convo.name) or nil
  local plates = Answers.Candidates(it, Answers.Facts(it, convo.name), Compat.Situation(), rel)
  plates = Answers.Rank(plates, it and it.ask)
  plates.ask = it and it.ask or nil
  return plates
end

-- The settings page's rows (§5.3): one line per plate, Enter keeps it, empty switches the plate
-- off; a button puts every plate back to its first words.
function Answers.Options()
  local rows = {
    { type = "header", label = L["Proposed answers"] },
    {
      type = "note",
      text = L["Each plate's words. {zone} {subzone} {coords} {ilvl} {level} {alt} {count} {price} {name} are filled in; a part in [brackets] goes when its value is unknown. Empty: the plate is not offered."], -- luacheck: ignore 631 (a locale key stays one literal)
    },
  }
  for _, slot in ipairs(Answers.SLOTS) do
    rows[#rows + 1] = {
      type = "edit",
      label = L[slot.label],
      get = function()
        return Answers.Template(slot.id)
      end,
      set = function(text)
        Answers.SetTemplate(slot.id, text)
        ns.People.DrawPlates()
      end,
    }
  end
  rows[#rows + 1] = {
    type = "execute",
    label = L["Answers: back to their first words"],
    desc = L["Every plate's words as they came; your kept lines and the counts stay."],
    func = function()
      Answers.Settings().templates = {}
      ns.People.DrawPlates()
    end,
  }
  rows[#rows + 1] = {
    type = "note",
    text = function()
      local n = #Answers.Settings().own
      return n > 0 and L["Kept as answers: %d of your lines (right click a plate to forget one)."]:format(n)
        or L["Right click a line you sent in a conversation to keep it as an answer."]
    end,
  }
  return rows
end
