-- Bastian's Chat, the saved searches' store (plan-chat-one-window.md §2.4, V29; the named views of
-- plan-chat-v3.md §7.3, V8): words kept under a name with the streams they were saved over and a
-- sound; the Inbox shows them under Saved on its rail (the pills and their form went in V29 and
-- V31). Once per profile the tabs of version 2 become such searches: their kinds, channels and
-- keywords the query, the streams their kinds land in, their sound. Pure but for the sounds.
local _, ns = ...
local L = ns.L
local Model = ns.Model

local Views = {}
ns.Views = Views

Views.MAX = 30 -- views kept at most
Views.SOUND_GAP = 2 -- seconds between two sounds of one view
-- the streams the lines of a tab's kinds land in (plan §2.1)
Views.CAT_STREAMS = {
  say = { "world" },
  whisper = { "direct" },
  guild = { "guild" },
  officer = { "guild" },
  group = { "group" },
  channel = { "world", "market", "lfg" },
  npc = { "world" },
  loot = { "mine" },
  progress = { "mine" },
  system = { "mine", "addons" },
  addon = { "addons" },
  bnet = { "direct" },
}

function Views.List()
  local p = ns.mod.db.profile
  p.views = type(p.views) == "table" and p.views or {}
  return p.views
end

function Views.Find(name)
  for i, v in ipairs(Views.List()) do
    if v.name == name then
      return v, i
    end
  end
  return nil
end

-- ---------------------------------------------------------------------------------------------
-- From a tab (pure)
-- ---------------------------------------------------------------------------------------------

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function sameSet(a, b)
  a, b = a or {}, b or {}
  for k, v in pairs(a) do
    if v and not b[k] then
      return false
    end
  end
  for k, v in pairs(b) do
    if v and not a[k] then
      return false
    end
  end
  return true
end

-- A tab of the defaults the player never changed: its stream pills say the same already.
function Views.IsPlainDefault(def)
  for _, d in ipairs(Model.TABS) do
    if d.id == def.id then
      return sameSet(d.cats, def.cats)
        and next(def.channels or {}) == nil
        and not def.words
        and not def.sound
        and not def.named
    end
  end
  return false
end

-- A tab's definition as a view: { name, query, streams, sound, only, from }, nil for a whisper
-- tab (its partner is a conversation already) or a tab that takes nothing.
function Views.FromTab(def, name)
  if type(def) ~= "table" or def.whisper then
    return nil
  end
  local terms, streams = {}, {}
  for _, cat in ipairs(Model.CATS) do
    if def.cats and def.cats[cat] then
      terms[#terms + 1] = "cat:" .. cat
      for _, s in ipairs(Views.CAT_STREAMS[cat] or {}) do
        streams[s] = true
      end
    end
  end
  local channels = {}
  for channel, on in pairs(def.channels or {}) do
    if on == true and type(channel) == "string" then
      channels[#channels + 1] = channel
    end
  end
  table.sort(channels)
  for _, channel in ipairs(channels) do
    terms[#terms + 1] = 'in:"' .. channel:gsub('"', ""):lower() .. '"'
    for _, s in ipairs(Views.CAT_STREAMS.channel) do
      streams[s] = true
    end
  end
  if #terms == 0 then
    return nil
  end
  local query = #terms == 1 and terms[1] or ("(" .. table.concat(terms, " OR ") .. ")")
  local words = {}
  for entry in tostring(def.words or ""):gmatch("[^,\n]+") do
    entry = trim(entry)
    if entry:sub(1, 1) == "~" and #entry > 1 then
      entry = "/" .. entry:sub(2) .. "/" -- the old pattern form (ADR 0045)
    end
    if entry ~= "" then
      words[#words + 1] = "(" .. entry .. ")"
    end
  end
  if #words > 0 then
    query = query .. " " .. (#words == 1 and words[1] or ("(" .. table.concat(words, " OR ") .. ")"))
  end
  return {
    name = name or def.title or def.id,
    query = query,
    streams = streams,
    sound = def.sound,
    only = def.only or nil, -- "only here": for the watch list, which is not built yet (§10.3)
    from = def.id,
  }
end

-- Once per profile (plan §11, a line in the log): every tab the player made or changed becomes a
-- view, and the main window takes the Inbox. Returns how many views it made, nil when this
-- profile was migrated before.
function Views.Migrate(p)
  if p.viewsFromTabs then
    return nil
  end
  p.viewsFromTabs = true
  p.views = type(p.views) == "table" and p.views or {}
  local list, have = p.views, {}
  for _, v in ipairs(list) do
    have[v.name] = true
  end
  local order, ids = {}, {}
  for i, d in ipairs(Model.TABS) do
    order[d.id] = i
  end
  for id in pairs(type(p.tabs) == "table" and p.tabs or {}) do
    ids[#ids + 1] = id
  end
  table.sort(ids, function(a, b)
    local oa, ob = order[a] or 100, order[b] or 100
    return oa < ob or (oa == ob and tostring(a) < tostring(b))
  end)
  local made = 0
  for _, id in ipairs(ids) do
    local def = p.tabs[id]
    if type(def) == "table" and not def.whisper and not Views.IsPlainDefault(def) then
      local name = def.named and def.title or L[def.title or tostring(id)]
      local v = Views.FromTab(def, name)
      if v and not have[v.name] and #list < Views.MAX then
        list[#list + 1] = v
        have[v.name] = true
        made = made + 1
      end
    end
  end
  if rawget(p, "layoutKind") == nil or p.layoutKind == "tabs" then
    p.layoutKind = "inbox"
  end
  return made
end

-- ---------------------------------------------------------------------------------------------
-- Matching
-- ---------------------------------------------------------------------------------------------

local compiled = {} -- [query text] = the compiled query

function Views.Query(view)
  local text = view and view.query
  if type(text) ~= "string" or text == "" then
    return nil
  end
  local q = compiled[text]
  if q == nil then
    q = ns.Rows.Query(text) or false
    compiled[text] = q
  end
  return q or nil
end

-- Does a record belong to the view (its streams, its query)?
function Views.Matches(view, rec)
  if view.streams and next(view.streams) and not view.streams[rec.stream] then
    return false
  end
  local q = Views.Query(view)
  return q == nil or q:Match(rec) == true
end

-- Does a view fit a panel of these streams (none named: every panel)?
function Views.Fits(view, streams)
  if not (view.streams and next(view.streams)) then
    return true
  end
  for s in pairs(view.streams) do
    if not streams[s] then
      return false
    end
  end
  return true
end

-- A view's sound on a new line of it, as the tab's was (not for the player's own lines, two
-- seconds apart); only while a version 3 layout shows, the tabs play their own.
local lastSound = {}
function Views.OnStore(what, rec)
  if what ~= "add" or rec.own or ns.View.LayoutKind() == "tabs" then
    return
  end
  for _, view in ipairs(Views.List()) do
    if view.sound and view.sound ~= "none" and Views.Matches(view, rec) then
      local now = GetTime()
      if now - (lastSound[view.name] or -100) >= Views.SOUND_GAP then
        lastSound[view.name] = now
        ns.Compat.PlaySound(view.sound)
      end
    end
  end
end

function Views.Attach()
  if not Views.attached then
    Views.attached = true
    ns.Chat.Store():On(Views.OnStore)
  end
end

-- A new view from what a panel shows now; false when the name is taken or the list is full.
function Views.Keep(view)
  if not view or type(view.query) ~= "string" or view.query == "" then
    return false
  end
  local list = Views.List()
  if #list >= Views.MAX then
    return false
  end
  local name = view.name
  if not name or name == "" or Views.Find(name) then
    local base = (view.query:gsub("%s+", " ")):sub(1, 24)
    name = base
    local n = 2
    while Views.Find(name) do
      name = base .. " " .. n
      n = n + 1
    end
  end
  view.name = name
  list[#list + 1] = view
  return view
end

function Views.Rename(name, new)
  local v = Views.Find(name)
  new = type(new) == "string" and trim(new) or ""
  if not v or new == "" or (new ~= name and Views.Find(new)) then
    return false
  end
  v.name = new
  return true
end

function Views.Delete(name)
  local _, i = Views.Find(name)
  if i then
    table.remove(Views.List(), i)
  end
  return i ~= nil
end
