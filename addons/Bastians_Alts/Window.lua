-- The Alts window (alts.md "The window", "make this one window - the
-- alts are on the top, then a search, then one large window"): the characters as pills on top,
-- the chosen one lit; a search over everything they hold; the views of the chosen character as
-- tabs (Overview, Equipment, Bags, Bank, Mail, Requests); and one wide list under them, the view's
-- rows or the search's hits across every character. The rows are the pages' sections (Alts.lua),
-- so the Browser's character page and this window never drift apart.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Widgets = B.UI.Widgets
local Alts = ns.Alts
local Model = Alts.Model

local W = {}
ns.Window = W

-- the views, in tab order: the section of the character's page each shows, its kind tile
W.VIEWS = {
  { "overview", "Overview", "ledger" },
  { "equipment", "Equipment", "item" },
  { "bags", "Bags", "keep" },
  { "bank", "Bank", "banker" },
  { "mail", "Mail", "share" },
  { "requests", "Requests", "invite" },
}
-- what a view says when its section has no rows
W.EMPTY = {
  overview = "Nothing recorded yet.",
  equipment = "Nothing worn recorded yet.",
  bags = "The bags were not read yet.",
  bank = "The bank was not read yet: open it once on this character.",
  mail = "The mailbox was not read yet: open one on this character.",
  requests = "No requests.",
}
W.RENDER_DELAY = 0.05
-- The one look (ADR 0084, W9; alts.md "The one look"): the views are the head's tabs, the
-- characters chips in a band with the search at its end, the line of what is shown, a foot.
W.SEARCH_MIN, W.SEARCH_MAX = 150, 260 -- the search in the band (the board: 260 at most)
local SIDE, SUM_TOP, SUM_H, SUM_FOOT = 15, 8, 14, 6
local TREE_LEFT, TREE_RIGHT = 6, 20 -- the rows' room beside the fold marks and the scroll bar

local mod, win, tree, summary, hint, search, bar, band
local pills = {}

local function db()
  return mod.db.profile
end

local function global()
  return mod.db.global
end

local function view()
  return db().view or "overview"
end

-- The chosen character's key: the one kept, else this character.
function W.Character()
  local key = db().character
  if key and global().characters[key] then
    return key
  end
  return Alts.Key()
end

-- The search's text, trimmed; "" without one.
local function query()
  local text = search and search:GetText() or ""
  return string.gsub(text, "^%s*(.-)%s*$", "%1")
end

-- ---------------------------------------------------------------------------------------------
-- The characters on top: this character's realm first, the character itself first in it
-- ---------------------------------------------------------------------------------------------

local function className(c)
  local classes = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
  return c.class and (type(classes) == "table" and classes[c.class] or L[c.class]) or nil
end

-- { { realm, chars = { key } } } in the order shown (`keys` would shadow lupa's table method).
function W.Groups()
  local me, myKey = Alts.Me()
  local byRealm, order = {}, {}
  for key, c in pairs(global().characters) do
    if type(c) == "table" then
      local realm = c.realm or "?"
      if not byRealm[realm] then
        byRealm[realm] = {}
        order[#order + 1] = realm
      end
      byRealm[realm][#byRealm[realm] + 1] = key
    end
  end
  table.sort(order, function(a, b)
    if (a == me.realm) ~= (b == me.realm) then
      return a == me.realm
    end
    return a < b
  end)
  local out = {}
  for _, realm in ipairs(order) do
    local chars = byRealm[realm]
    table.sort(chars, function(a, b)
      if (a == myKey) ~= (b == myKey) then
        return a == myKey
      end
      local ca, cb = global().characters[a], global().characters[b]
      return (ca.name or a) < (cb.name or b)
    end)
    out[#out + 1] = { realm = realm, chars = chars }
  end
  return out
end

local function pillTip(key)
  return function()
    local c = global().characters[key]
    if not c then
      return nil
    end
    local parts = {}
    if c.level then
      parts[#parts + 1] = L["Level"] .. " " .. c.level .. (className(c) and (" " .. className(c)) or "")
    end
    local zone = c.zone and B:Entity("zone:" .. c.zone):Name()
    if zone then
      parts[#parts + 1] = zone
    end
    if c.money then
      parts[#parts + 1] = B.UI.Money(c.money)
    end
    local seen = Alts.Age(c.seen)
    return c.name or key,
      table.concat(parts, ", ") .. (seen and ("\n" .. L["Last seen"] .. " " .. seen) or "")
  end
end

-- The characters as chips in the band, in rows across the window's width, a realm's name in
-- small capitals before its characters when there is more than one realm; the search at the
-- first row's end. Returns the band's height.
function W.LayoutPills()
  if not win then
    return 0
  end
  local width = (win.frame:GetWidth() or 0) - 2 -- the frame: its width is known at once
  local groups = W.Groups()
  local several = #groups > 1
  local chosen = W.Character()
  local top = bar:Room() -- under the head, or under the tabs' own row
  band.frame:ClearAllPoints()
  band.frame:SetPoint("TOPLEFT", win.content, "TOPLEFT", 0, -top)
  band.frame:SetPoint("TOPRIGHT", win.content, "TOPRIGHT", 0, -top)
  band:Begin(width)
  local sw = math.max(W.SEARCH_MIN, math.min(W.SEARCH_MAX, math.floor(width * 0.4)))
  search:SetWidth(sw)
  band:PlaceRight(search, sw, search:GetHeight() or 22)
  local n = 0
  for gi, g in ipairs(groups) do
    if several then
      band:Group(g.realm, gi == 1)
    end
    for _, key in ipairs(g.chars) do
      n = n + 1
      local p = pills[n]
      if not p then
        p = S.pill(band.frame, {
          small = true,
          onClick = function(self)
            W.Open(self.key)
          end,
        })
        pills[n] = p
      end
      local c = global().characters[key]
      p.key = key
      p.tip = pillTip(key)
      p.spec.label = c.name or key
      p.spec.count = c.level
      p.spec.on = key == chosen or nil
      S.Draw(p)
      band:Place(p, p:GetWidth() or 60, p:GetHeight() or 22)
      p:Show()
    end
  end
  for i = n + 1, #pills do
    pills[i]:Hide()
  end
  return band:End()
end

-- ---------------------------------------------------------------------------------------------
-- The rows: the chosen character's view, or the search's hits
-- ---------------------------------------------------------------------------------------------

local function sectionOf(ref, id)
  for _, s in ipairs(B:GetDetailSections(ref)) do
    if s.id == id then
      return s
    end
  end
  return nil
end

-- The rows and the summary line of the chosen character's view.
function W.ViewRows(key, which)
  local ref = "character:" .. key
  local section = sectionOf(ref, "alts." .. which)
  local rows = section and section.rows
  local title = section and section.title or L[W.VIEWS[1][2]]
  if type(title) == "function" then
    title = title(ref)
  end
  if not rows or #rows == 0 then
    return { { text = S.H.muted .. L[W.EMPTY[which]] .. "|r", kind = "para" } }, title
  end
  local out = {}
  for i, r in ipairs(rows) do
    local row = {}
    for k, v in pairs(r) do
      row[k] = v
    end
    row.id = row.id or (which .. ":" .. tostring(row.ref or i))
    out[i] = row
  end
  return out, string.format("%s  %s%s|r", title, S.H.muted, string.format(L["%d rows"], #out))
end

-- The holders' words of an item: "Bankalt: bags 40, bank 15; Burlina: worn".
local function holderWords(itemID)
  local parts = {}
  for _, h in ipairs(Model.Holders(global(), itemID)) do
    local places = {}
    for _, place in ipairs(Alts.PLACES) do
      if h[place] > 0 then
        places[#places + 1] = place == "worn" and L["worn"]
          or (string.lower(L[Alts.PLACE_WORDS[place]]) .. " " .. h[place])
      end
    end
    parts[#parts + 1] = (h.char.name or h.key) .. ": " .. table.concat(places, ", ")
  end
  return table.concat(parts, "; ")
end

-- Every item any character holds whose name matches, with who holds it and how many in all.
function W.SearchRows(text)
  local q = B.Query.Compile(text)
  local totals, chars = {}, {}
  for key, c in pairs(global().characters) do
    if type(c) == "table" then
      for id, e in pairs(Model.Places(c)) do
        totals[id] = (totals[id] or 0) + e.bags + e.bank + e.mail + e.worn
        chars[id] = chars[id] or {}
        chars[id][key] = true
      end
    end
  end
  local out, holders = {}, {}
  for id, total in pairs(totals) do
    local ref = "item:" .. id
    local name = B:Entity(ref):Name() or (L["Item"] .. " " .. id)
    if q:Match(name) then
      out[#out + 1] = {
        id = "search:" .. id,
        ref = ref,
        icon = B:Entity(ref):Icon(),
        text = name .. "  " .. S.H.muted .. holderWords(id) .. "|r",
        value = total,
        valueKind = "number",
      }
      for key in pairs(chars[id]) do
        holders[key] = true
      end
    end
  end
  table.sort(out, function(a, b)
    return a.text < b.text
  end)
  local n = 0
  for _ in pairs(holders) do
    n = n + 1
  end
  if #out == 0 then
    return { { text = S.H.muted .. L["Nothing matches."] .. "|r", kind = "para" } }, L["Nothing matches."]
  end
  return out, string.format(L["%d items on %d characters"], #out, n)
end

-- The head's filled tab: the shown view; none while a search shows.
local function setTabs(searching)
  bar.tabs:SetValue(not searching and view() or nil)
end

function W.Render()
  if not (win and win:IsShown()) then
    return
  end
  W.LayoutPills() -- the line and the rows hang under the band
  local text = query()
  local rows, words
  if text ~= "" then
    rows, words = W.SearchRows(text)
  else
    rows, words = W.ViewRows(W.Character(), view())
  end
  setTabs(text ~= "")
  summary:SetText(words or "")
  tree:SetRows(rows)
end

function W.Schedule()
  if mod and win and win:IsShown() then
    mod:Coalesce("render", W.RENDER_DELAY, W.Render)
  end
end

-- ---------------------------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------------------------

local function build()
  win = B.UI.Window("BastiansAltsFrame", {
    head = "tall", -- a window opened to read (ADR 0084 decision 3)
    module = "Alts", -- the options button opens this page (R27.1)
    title = L["Characters"],
    width = 640,
    height = 520,
    minWidth = 420,
    db = db().window,
    onShow = function()
      W.Render()
    end,
    onResize = function()
      W.Render() -- the pills flow with the width
    end,
  })
  local content = win.content
  -- the views as the head's tabs (ADR 0084 decision 3)
  local items = {}
  for _, t in ipairs(W.VIEWS) do
    items[#items + 1] = { id = t[1], label = L[t[2]] }
  end
  bar = win:Bar({
    tabs = {
      items = items,
      value = view(),
      onChange = function(id)
        W.Open(nil, id)
      end,
    },
    onLayout = function()
      if band and win:IsShown() then
        W.Schedule() -- the tabs took or left their own row: the band moves
      end
    end,
  })
  -- the band: the characters as chips, the search over everything they hold at its end
  band = B.UI.Band(content, { labels = false })
  search = S.search(band.frame, L["Search everything your characters hold"])
  search:SetScript("OnTextChanged", function(self)
    local text = self:GetText() or ""
    if text == "" then
      self.hint:Show()
      self.clear:Hide()
    else
      self.hint:Hide()
      self.clear:Show()
    end
    W.Schedule()
  end)
  summary = S.text(content, 13, S.C.dim) -- what is shown, in the text size (the board)
  summary:SetPoint("TOPLEFT", band.frame, "BOTTOMLEFT", SIDE, -SUM_TOP)
  summary:SetPoint("TOPRIGHT", band.frame, "BOTTOMRIGHT", -SIDE, -SUM_TOP)
  summary:SetHeight(SUM_H)
  summary:SetJustifyH("LEFT")
  summary:SetWordWrap(false)
  hint = Widgets.Foot(content) -- the window's last line, on the band's ground
  hint:SetText(L["Click a line: its page. Right click: its entity menu."])
  tree = B.UI.Tree(content, { db = db().tree, ctx = { source = "alts" }, capsSections = true })
  tree.chips:ClearAllPoints()
  tree.chips:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", TREE_LEFT - SIDE, -SUM_FOOT)
  tree.chips:SetPoint("TOPRIGHT", summary, "BOTTOMRIGHT", SIDE - TREE_RIGHT, -SUM_FOOT)
  tree.scroll:ClearAllPoints()
  tree.scroll:SetPoint("TOPLEFT", tree.chips, "BOTTOMLEFT", 0, 0)
  tree.scroll:SetPoint("BOTTOMRIGHT", hint, "TOPRIGHT", -TREE_RIGHT, 0)
  W.win, W.tree, W.summary, W.pills, W.search = win, tree, summary, pills, search
  W.bar, W.band, W.hint = bar, band, hint
end

-- Opens the window on a character (nil keeps the chosen one) and a view (nil keeps it).
function W.Open(key, which)
  if not (mod and mod:IsEnabled()) then
    return false
  end
  if not win then
    build()
  end
  if key and global().characters[key] then
    db().character = key
  end
  if which then
    db().view = which
  end
  if win:IsShown() then
    win:Show() -- to the front
    W.Render()
  else
    win:Show()
  end
  return true
end

function W.Toggle()
  if win and win:IsShown() then
    win:Hide()
    return false
  end
  return W.Open()
end

function W.IsShown()
  return win ~= nil and win:IsShown()
end

function W.Register(self)
  mod = self
  self.Window = W -- reachable through the module (tests)
  self:On("BASTIANS_ALTS_CHANGED", W.Schedule)
  self:On("BASTIANS_THEME_CHANGED", W.Schedule)
end
