-- Bastian's Strategies (strategies.md): the module: the book window, pages as entities ("page:<id>"),
-- the "Open in the book" action, the Rumours map layer, the "In Bastian's book" block on the pages
-- of the places, items and creatures a page names, the search over the pages, /bbook.
local ADDON, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
local L = ns.L
local Book, Window = ns.Book, ns.Window

local Strategies = {}
ns.Strategies = Strategies

local function data()
  return B:GetService("data")
end

local function page(id)
  local d = data()
  return d and d:Get("page", id) or nil
end

local function pageID(ref)
  local typ, id = B.Entity.Parse(ref)
  return typ == "page" and id or nil
end

-- The pages with a place, for the map layer: { id, map, x, y, name, levelMin, zones }, built once
-- per pack load (the layer's query must not decode records, core-contracts §6).
local placed
function Strategies.Placed()
  if placed then
    return placed
  end
  placed = {}
  for id, p in pairs(Window.Pages()) do
    local place = p.shelf == "active" and p.plate and p.plate.place
    if place then
      placed[#placed + 1] = {
        id = id,
        map = place[1],
        x = place[2],
        y = place[3],
        name = p.name,
        levelMin = p.levelMin,
        zones = p.zones,
      }
    end
  end
  table.sort(placed, function(a, b)
    return a.id < b.id
  end)
  return placed
end

local function rumourPins(view)
  local pins = {}
  for _, p in ipairs(Strategies.Placed()) do
    local continent, wx, wy = B.Coords.ToWorld(p.map, p.x, p.y)
    if
      continent
      and continent == view.continent
      and wx >= view.x1
      and wx <= view.x2
      and wy >= view.y1
      and wy <= view.y2
    then
      pins[#pins + 1] = {
        ref = "page:" .. p.id,
        wx = wx,
        wy = wy,
        icon = B.UI.IconTexture("ledger"),
        label = p.name,
        priority = 45,
        cluster = true,
      }
    end
  end
  return pins
end
Strategies.RumourPins = rumourPins

-- "In Bastian's book" on the Browser page of a place, item or creature the book names.
local function pagesRows(ref)
  local ids = Book.PagesOf(Window.Pages(), ref)
  if #ids == 0 then
    return nil
  end
  local rows = {}
  for _, id in ipairs(ids) do
    local p = page(id)
    rows[#rows + 1] = {
      text = p and p.name or id,
      ref = "page:" .. id,
      icon = B.UI.IconTexture("ledger"),
      onClick = function()
        Window.Show({ kind = "page", id = id })
      end,
    }
  end
  return rows
end

-- The stories of a farm spot: the
-- pages that name an item of the spot, else the farming pages of its zone. The data has no link
-- between the two. -> page ids, sorted.
function Strategies.SpotPages(ref)
  local typ, id = B.Entity.Parse(ref)
  local d = data()
  local s = typ == "spot" and d and d:Get("spot", id) or nil
  if not s then
    return {}
  end
  local out, seen = {}, {}
  local pages = Window.Pages()
  for _, it in ipairs(s.items or {}) do
    for _, pid in ipairs(Book.PagesOf(pages, "item:" .. tostring(it[1]))) do
      if not seen[pid] then
        seen[pid] = true
        out[#out + 1] = pid
      end
    end
  end
  if #out == 0 then
    for pid, p in pairs(pages) do
      for _, z in ipairs(p.zones or {}) do
        if tonumber(z) == s.map and p.chapter == "farming" and p.shelf ~= "retired" then
          out[#out + 1] = pid
          break
        end
      end
    end
  end
  table.sort(out)
  return out
end

local function spotRows(ref)
  local ids = Strategies.SpotPages(ref)
  if #ids == 0 then
    return nil
  end
  local rows = {}
  for i, id in ipairs(ids) do
    local p = page(id)
    -- a row opens the story's page here: its picture and the way into the book
    rows[i] = { text = p and p.name or id, ref = "page:" .. id, icon = B.UI.IconTexture("ledger") }
  end
  return rows
end

-- A story's page in a host (ADR 0056: Bastians:RegisterSheet): the title, the meta line, the way
-- into the book as the first and largest button, the page's picture (its plate).
local SHEET_PAD, SHEET_PLATE_MAX = 16, 560
local sheets = {} -- host frame -> its parts

local function storySheet(host)
  local sheet = sheets[host.frame]
  if sheet then
    return sheet
  end
  local frame = CreateFrame("Frame", nil, host.frame)
  frame:SetPoint("TOPLEFT", host.frame, "TOPLEFT", 0, 0)
  sheet = { frame = frame, buttons = {} }
  sheet.title = B.UI.Style.text(frame, 20, B.UI.Style.C.accent)
  sheet.title:SetPoint("TOPLEFT", frame, "TOPLEFT", SHEET_PAD, -SHEET_PAD)
  sheet.title:SetJustifyH("LEFT")
  sheet.meta = B.UI.Style.text(frame, 12, B.UI.Style.C.dim)
  sheet.meta:SetJustifyH("LEFT")
  sheet.read = B.UI.Style.action(frame, { icon = "ledger", label = L["Open in the book"], primary = true })
  sheet.plate = ns.Plate.New(frame)
  sheets[host.frame] = sheet
  return sheet
end

function Strategies.DrawStory(ref, host)
  local id = pageID(ref)
  local p = id and page(id)
  if not (p and host and host.frame) then
    return 0
  end
  local S = B.UI.Style
  local sheet = storySheet(host)
  local width = host.width or 400
  local inner = width - 2 * SHEET_PAD
  S.ink(sheet.title, S.C.accent)
  S.ink(sheet.meta, S.C.dim)
  sheet.title:SetWidth(inner)
  sheet.title:SetText(p.name or id)
  sheet.meta:SetWidth(inner)
  sheet.meta:ClearAllPoints()
  sheet.meta:SetPoint("TOPLEFT", sheet.title, "BOTTOMLEFT", 0, -4)
  sheet.meta:SetText(table.concat(p.meta or {}, " - "))
  local y = SHEET_PAD + (sheet.title:GetStringHeight() or 20) + 4 + (sheet.meta:GetStringHeight() or 12) + 10
  sheet.read:ClearAllPoints()
  sheet.read:SetPoint("TOPLEFT", sheet.frame, "TOPLEFT", SHEET_PAD, -y)
  sheet.read:SetScript("OnClick", function()
    Window.Show({ kind = "page", id = id })
  end)
  local x = SHEET_PAD + (sheet.read:GetWidth() or 120) + 6
  for i, spec in ipairs(host.buttons or {}) do
    local b = sheet.buttons[i]
    if not b then
      b = S.action(sheet.frame, { label = "", boxed = true, row = true })
      sheet.buttons[i] = b
    end
    b.spec.label = spec.label
    b.tip = spec.tip
    if b.SetLabel then
      b:SetLabel(spec.label)
    end
    if b.Fit then
      b:Fit()
    end
    b:SetScript("OnClick", function(self)
      spec.run(self)
    end)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", sheet.frame, "TOPLEFT", x, -(y + 2))
    b:Show()
    x = x + (b:GetWidth() or 60) + 6
  end
  for i = #(host.buttons or {}) + 1, #sheet.buttons do
    sheet.buttons[i]:Hide()
  end
  y = y + (sheet.read:GetHeight() or 26) + 12
  if p.plate then
    local h = sheet.plate:Draw(p.plate, math.min(inner, SHEET_PLATE_MAX), {})
    sheet.plate.frame:ClearAllPoints()
    sheet.plate.frame:SetPoint("TOPLEFT", sheet.frame, "TOPLEFT", SHEET_PAD, -y)
    sheet.plate.frame:Show()
    y = y + h + 8
  else
    sheet.plate.frame:Hide()
  end
  sheet.frame:SetSize(width, y)
  sheet.frame:Show()
  return y
end

-- The page's own block on its Browser page (a pin's click lands there): what it is about.
local function pageRows(ref)
  local p = page(pageID(ref))
  if not p then
    return nil
  end
  local rows = {}
  for _, item in ipairs(p.meta or {}) do
    rows[#rows + 1] = { text = item }
  end
  local opening = p.blocks and p.blocks[1] and p.blocks[1][1] == "opening" and p.blocks[1][2]
  if opening then
    rows[#rows + 1] = { kind = "para", text = Window.Expand(opening) }
  end
  return rows
end

-- The settings page's line: what the installed book holds.
function Strategies.Note()
  local d = data()
  if not (d and d:PackLoaded("book")) then
    return L["The book's pages are not installed: Bastian's Data: Strategies brings them."]
  end
  local active, back = 0, 0
  for _, p in pairs(Window.Pages()) do
    if p.shelf == "active" then
      active = active + 1
    elseif p.shelf == "back" then
      back = back + 1
    end
  end
  local news = Window.News()
  return string.format(
    L["%d pages in the book, %d on the back shelf. Last update: %s."],
    active,
    back,
    news[1] and news[1].date or L["unknown"]
  )
end

local mod = B:NewModule("Strategies", {
  addon = ADDON,
  open = function()
    Window.Toggle()
  end,
  title = L["Strategies"],
  icon = B.UI.IconTexture("ledger"),
  -- What's new (ADR 0021): the app's release notes, and the book's entries folded to a line a day;
  -- a line opens its page or mill, or the book's own What's new where each entry links on
  news = function()
    local out = {}
    for _, e in ipairs(ns.NEWS) do
      out[#out + 1] = e
    end
    for _, day in ipairs(Book.Fold(Window.News(), L)) do
      out[#out + 1] = {
        id = "book:" .. day.id,
        date = day.date,
        source = L["The book"],
        text = day.text,
        open = function()
          Window.Show(day.target or { kind = "title" })
        end,
      }
    end
    return out
  end,
  apiVersion = 1,
  data = { "book", "world", "items" }, -- the pages; the loot tables and items for the live boxes
  defaults = {
    profile = { window = {} },
    char = { bookmarks = {} }, -- bookmarks by page id
    global = { notes = {} }, -- the reader's notes by page id, for every character
  },
  options = {
    {
      type = "note",
      text = function()
        return Strategies.Note()
      end,
    },
  },
  OnEnable = function(self)
    B:RegisterEntityType(self, {
      type = "page",
      priority = 100,
      name = function(id)
        local p = page(id)
        return p and p.name or nil
      end,
      icon = function()
        return B.UI.IconTexture("ledger")
      end,
      summary = function(id)
        local p = page(id)
        if not p then
          return nil
        end
        local c = p.chapter and data() and data():Get("chapter", p.chapter)
        local band = p.levelMin and string.format(L["level %d-%d"], p.levelMin, p.levelMax) or nil
        if c and band then
          return c.name .. ", " .. band
        end
        return c and c.name or band
      end,
      locations = function(id)
        local p = page(id)
        local place = p and p.plate and p.plate.place
        if not place then
          return nil
        end
        return { { map = place[1], x = place[2], y = place[3], kind = "page", src = "book" } }
      end,
      fields = function(id)
        return page(id)
      end,
    })
    B:RegisterAction(self, {
      id = "strategies.open",
      main = true, -- a button of the sheet (ADR 0054)
      label = L["Open in the book"],
      short = L["Read"],
      icon = B.UI.IconTexture("ledger"),
      types = { "page" },
      order = 5, -- a page's first action: read it
      run = function(ref)
        local id = pageID(ref)
        return id and Window.Show({ kind = "page", id = id }) or false
      end,
    })
    B:RegisterAction(self, {
      id = "strategies.spot",
      main = true, -- a spot's first button: its story
      label = L["Open in the book"],
      short = L["Read"],
      icon = B.UI.IconTexture("ledger"),
      types = { "spot" },
      order = 5,
      when = function(ref)
        return Strategies.SpotPages(ref)[1] ~= nil
      end,
      run = function(ref)
        local id = Strategies.SpotPages(ref)[1]
        return id and Window.Show({ kind = "page", id = id }) or false
      end,
    })
    B:RegisterSheet(self, {
      types = { "page" },
      draw = Strategies.DrawStory,
      hide = function(host)
        local sheet = sheets[host.frame]
        if sheet then
          sheet.frame:Hide()
        end
      end,
    })
    -- the Browser's list of the stories ("Gold Stories ... with zone,
    -- maybe category"): the category is the book's chapter
    B:RegisterList(self, {
      type = "page",
      label = "Gold Stories",
      glyph = "ledger",
      facet = "chapter",
      groupBy = "chapter",
      -- the chapters as a row to pick from
      chips = true,
      ids = function()
        local d = data()
        return d and d:Each("page") or {}
      end,
      record = function(id)
        local p = page(id)
        if not p or p.shelf == "retired" then
          return nil
        end
        local d = data()
        local c = p.chapter and d and d:Get("chapter", p.chapter)
        local map = p.zones and tonumber(p.zones[1]) or nil
        local z = map and d and d:Get("zone", map) or nil
        return {
          name = p.name,
          level = p.levelMin,
          zone = map,
          zoneName = z and z.name or nil,
          chapterName = c and c.name or nil,
        }
      end,
      value = function(r)
        return r.chapterName
      end,
    })
    -- a story's tile (, R7: "tiles on left with symbol (bastian picture
    -- and short text)"): its picture cut to the tile's slot, the opening's first words as its line
    B:RegisterFacet(self, {
      facet = "tile",
      types = { "page" },
      priority = 60,
      invalidateOn = { "BASTIANS_DATA_LOADED" },
      rule = function(ref)
        local _, id = B.Entity.Parse(ref)
        local p = id and page(id)
        if not p then
          return nil
        end
        local facts = {}
        if p.art then
          -- the 2:1 picture in a 3:2 slot: an eighth off each side
          facts.picture = { path = ns.Window.ART .. tostring(id), coords = { left = 0.125, right = 0.875 } }
        end
        facts.line = ns.Book.Lead(p, 70)
        return next(facts) ~= nil and facts or nil
      end,
    })
    B:RegisterFilter(self, {
      id = "strategies.zone",
      kind = "facet",
      types = { "page" },
      label = L["Zone"],
      value = function(_, r)
        return r and r.zoneName or nil
      end,
      order = function(key)
        return key
      end,
    })
    B:RegisterDetailSection(self, {
      id = "strategies.spot",
      chapter = "book",
      title = L["In Bastian's book"],
      types = { "spot" },
      order = 5,
      block = { limit = 5 },
      build = spotRows,
    })
    B:RegisterDetailSection(self, {
      id = "strategies.page",
      title = L["In the book"],
      types = { "page" },
      order = 10,
      block = { wide = true, limit = 8 },
      build = pageRows,
    })
    B:RegisterDetailSection(self, {
      id = "strategies.pages",
      chapter = "book", -- on the sheet (ADR 0054)
      title = L["In Bastian's book"],
      types = { "npc", "item", "object", "zone" },
      order = 70,
      block = { limit = 5 },
      build = pagesRows,
    })
    B:RegisterSearchProvider(self, {
      id = "strategies.pages",
      label = L["Bastian's Gold Adventures"],
      priority = 60,
      search = function(query, limit, yield, q)
        local d = data()
        local out = {}
        if not d then
          return out
        end
        for _, hit in ipairs(d:Find("page", q or query, limit, yield)) do
          out[#out + 1] =
            { ref = "page:" .. hit.id, label = hit.name, score = hit.score, note = L["the book"] }
        end
        return out
      end,
    })
    B:RegisterMapLayer(self, {
      id = "strategies.rumours",
      icon = "ledger", -- the layer bar shows its icon (R27.8)
      label = L["Gold stories (Bastian's book)"],
      defaultOn = true,
      minLevel = 1,
      query = rumourPins,
    })
    self:On("BASTIANS_DATA_LOADED", function()
      placed = nil
      B:Fire("BASTIANS_LAYER_CHANGED", "strategies.rumours")
      Window.Schedule()
    end)
    self:On("BASTIANS_PRICES_UPDATED", Window.Schedule)
    self:On("BASTIANS_THEME_CHANGED", Window.Schedule)
    ns.Feed.Register(self) -- the broker displays' feed (ADR 0043)
  end,
  OnDisable = function()
    Window.Hide()
  end,
})
ns.mod = mod
mod.Strategies = Strategies
mod.Book = Book
mod.Window = Window
mod.Plate = ns.Plate

SLASH_BASTIANSSTRATEGIES1 = "/bbook"
SlashCmdList.BASTIANSSTRATEGIES = function(msg)
  if not mod:IsEnabled() then
    B:Say(L["Strategies is disabled"])
    return
  end
  local cmd = string.lower(strtrim(msg or ""))
  if cmd == "" then
    Window.Toggle()
  elseif cmd == "contents" or cmd == "bookmarks" or cmd == "title" then
    Window.Show({ kind = cmd })
  elseif cmd == "map" then
    Window.Show({ kind = "atlas" }) -- the story map (ADR 0057)
  elseif cmd == "search" or cmd == "index" then
    Window.Show({ kind = "search", id = "" }) -- the search page took the index's place (30.10.2026)
  elseif cmd == "news" then
    Window.Show({ kind = "title" })
  elseif cmd == "web" then
    -- /bbook web: the open page's address on bastians.dev into the chat box, else the diary's
    local now = Window.Current()
    B.Compat.OpenChat(Book.WebURL(now and now.kind == "page" and page(now.id) and now.id or nil))
  elseif string.match(cmd, "^mill") then
    -- /bbook mill [chapter]: a chapter's Rumour mill, the first one with rumours without a chapter
    local chapter = string.match(cmd, "^mill%s+(%S+)$")
    if not chapter then
      for _, entry in ipairs(Window.Order()) do
        if entry.kind == "mill" then
          chapter = entry.id
          break
        end
      end
    end
    Window.Show(chapter and { kind = "mill", id = chapter } or { kind = "contents" })
  elseif page(cmd) then
    Window.Show({ kind = "page", id = cmd })
  else
    -- /bbook <words>: the full-text search
    Window.Search(strtrim(msg))
  end
end
