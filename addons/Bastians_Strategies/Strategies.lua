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
  local level = B.Compat.GetPlayerFacts and B.Compat.GetPlayerFacts().level or nil
  local entered = ns.mod.db.char.entered
  for _, p in ipairs(Strategies.Placed()) do
    if Book.IsOpen(p, level, entered) then -- a sealed page keeps its place to itself (SB3)
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

-- The zones the character has set foot in (SB3: entering a page's zone unseals it).
local function enter(map)
  if map then
    local entered = ns.mod.db.char.entered
    if not entered[map] then
      entered[map] = true
      B:Fire("BASTIANS_LAYER_CHANGED", "strategies.rumours")
      Window.Schedule()
    end
  end
end

local mod = B:NewModule("Strategies", {
  addon = ADDON,
  open = function()
    Window.Toggle()
  end,
  title = L["Strategies"],
  icon = B.UI.IconTexture("ledger"),
  apiVersion = 1,
  data = { "book", "world", "items" }, -- the pages; the loot tables and items for the live boxes
  defaults = {
    profile = { window = {} },
    char = { bookmarks = {}, entered = {} }, -- bookmarks by page id, the zones set foot in
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
      title = L["In Bastian's book"],
      types = { "npc", "item", "object", "zone" },
      order = 70,
      block = { limit = 5 },
      build = pagesRows,
    })
    B:RegisterSearchProvider(self, {
      id = "strategies.pages",
      label = L["Bastian's Gold Rumours"],
      priority = 60,
      search = function(query, limit, yield)
        local d = data()
        local out = {}
        if not d then
          return out
        end
        for _, hit in ipairs(d:Find("page", query, limit, yield)) do
          out[#out + 1] =
            { ref = "page:" .. hit.id, label = hit.name, score = hit.score, note = L["the book"] }
        end
        return out
      end,
    })
    B:RegisterMapLayer(self, {
      id = "strategies.rumours",
      label = L["Rumours (Bastian's book)"],
      defaultOn = true,
      minLevel = 1,
      query = rumourPins,
    })
    self:On("BASTIANS_DATA_LOADED", function()
      placed = nil
      B:Fire("BASTIANS_LAYER_CHANGED", "strategies.rumours")
      Window.Schedule()
    end)
    self:On("BASTIANS_PLAYER_MOVED_ZONE", function(_, _, map)
      enter(map)
    end)
    self:RegisterEvent("PLAYER_LEVEL_UP", function()
      B:Fire("BASTIANS_LAYER_CHANGED", "strategies.rumours")
      Window.Schedule()
    end)
    self:On("BASTIANS_PRICES_UPDATED", Window.Schedule)
    self:On("BASTIANS_THEME_CHANGED", Window.Schedule)
    enter(B.Coords.PlayerMap())
  end,
  OnDisable = function()
    Window.Hide()
  end,
})
ns.mod = mod
mod.Strategies = Strategies
mod.Book = Book
mod.Window = Window

SLASH_BASTIANSSTRATEGIES1 = "/bbook"
SlashCmdList.BASTIANSSTRATEGIES = function(msg)
  if not mod:IsEnabled() then
    B:Say(L["Strategies is disabled"])
    return
  end
  local cmd = string.lower(strtrim(msg or ""))
  if cmd == "" then
    Window.Toggle()
  elseif cmd == "contents" or cmd == "index" or cmd == "bookmarks" or cmd == "title" then
    Window.Show({ kind = cmd })
  elseif cmd == "news" then
    Window.Show({ kind = "title" })
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
    B:Say(L["No page %s in the book. /bbook index lists them."], cmd)
  end
end
