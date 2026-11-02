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
W.GAP = 4 -- between the pills
W.PAD = 6 -- the window's inner margin
W.RENDER_DELAY = 0.05

local mod, win, tree, summary, hint, search
local pills, tabs, realmLabels = {}, {}, {}

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

-- The pills laid out in rows across the window's width, a realm's name in grey before its
-- characters when there is more than one realm; returns the height used.
function W.LayoutPills()
  if not win then
    return 0
  end
  local content = win.content
  local width = (win.frame:GetWidth() or 0) - 2 - 2 * W.PAD -- the frame: its width is known at once
  local groups = W.Groups()
  local several = #groups > 1
  local x, y, n, nl = 0, 0, 0, 0
  local rowH = S.G.pill or 26
  local chosen = W.Character()
  local function place(widget, w)
    if x > 0 and x + w > width then
      x, y = 0, y + rowH + W.GAP
    end
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", content, "TOPLEFT", W.PAD + x, -(W.PAD + y))
    widget:Show()
    x = x + w + W.GAP
  end
  for _, g in ipairs(groups) do
    if several then
      nl = nl + 1
      local label = realmLabels[nl]
      if not label then
        label = S.text(content, 11, S.C.dim)
        label:SetHeight(rowH)
        realmLabels[nl] = label
      end
      label:SetText(g.realm)
      place(label, (label:GetStringWidth() or 0) + 2)
    end
    for _, key in ipairs(g.chars) do
      n = n + 1
      local p = pills[n]
      if not p then
        p = S.pill(content, {
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
      place(p, p:GetWidth() or 60)
    end
  end
  for i = n + 1, #pills do
    pills[i]:Hide()
  end
  for i = nl + 1, #realmLabels do
    realmLabels[i]:Hide()
  end
  return y + rowH
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

local function setTabs(searching)
  local v = view()
  for _, t in ipairs(tabs) do
    t:SetOn(not searching and t.view == v)
    t:SetAlpha(searching and 0.5 or 1)
  end
end

function W.Render()
  if not (win and win:IsShown()) then
    return
  end
  local height = W.LayoutPills()
  search:ClearAllPoints()
  search:SetPoint("TOPLEFT", win.content, "TOPLEFT", W.PAD, -(W.PAD + height + W.GAP))
  search:SetPoint("TOPRIGHT", win.content, "TOPRIGHT", -W.PAD, -(W.PAD + height + W.GAP))
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
  -- the search over everything they hold, under the pills (placed by Render)
  search = S.search(content, L["Search everything your characters hold"])
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
  -- the views as tabs under the search
  local x = W.PAD
  for i, t in ipairs(W.VIEWS) do
    local tab = S.tab(content, {
      kind = t[3],
      label = L[t[2]],
      onClick = function()
        W.Open(nil, t[1])
      end,
    })
    tab.view = t[1]
    tab:SetPoint("TOPLEFT", search, "BOTTOMLEFT", x - W.PAD, -W.GAP)
    tabs[i] = tab
    x = x + (tab:GetWidth() or 60) + 2
  end
  summary = S.text(content, 11, S.C.dim)
  summary:SetPoint("TOPLEFT", tabs[1], "BOTTOMLEFT", 2, -W.GAP)
  summary:SetPoint("RIGHT", content, "RIGHT", -W.PAD, 0)
  summary:SetHeight(14)
  summary:SetJustifyH("LEFT")
  hint = S.text(content, 10, S.C.dim)
  hint:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", W.PAD + 2, 4)
  hint:SetText(L["Click a line: its page. Right click: its entity menu."])
  tree = B.UI.Tree(content, { db = db().tree, ctx = { source = "alts" } })
  tree.chips:ClearAllPoints()
  tree.chips:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", -2, -2)
  tree.chips:SetPoint("TOPRIGHT", content, "TOPRIGHT", -20, 0)
  tree.scroll:ClearAllPoints()
  tree.scroll:SetPoint("TOPLEFT", tree.chips, "BOTTOMLEFT", 0, -2)
  tree.scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -20, 18)
  W.win, W.tree, W.summary, W.tabs, W.pills, W.search = win, tree, summary, tabs, pills, search
  W.realmLabels = realmLabels
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
