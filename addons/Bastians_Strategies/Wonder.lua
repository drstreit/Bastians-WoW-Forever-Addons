-- Bastian's Book: one page, one wonder (book.md "The details page"): the plate and what it gives
-- on the left; the kind, the title, Bastian's line, the source's, the steps in Nixie's envelope,
-- the other characters, the acts (show on map, route there, done, bookmark) on the right.
local _, ns = ...
local B = Bastians
local S = B.UI.Style
local L = ns.L
local Record, Picture = ns.Record, ns.Picture

local Wonder = {}
ns.Wonder = Wonder

Wonder.PLATE = 0.68 -- the plate's height over its width

-- A heading in the book's small capitals (ADR 0081; plain capitals where the client keeps its font).
local function caps(text)
  return ns.Front.SmallCaps(text)
end

local function zoneName(z)
  local info = z and ns.Front.ZoneOf(z)
  return info and info.name or nil
end

local function placeLine(place)
  local name = zoneName(place[1])
  if not name then
    return nil
  end
  return string.format("%s, %d, %d", name, math.floor(place[2] * 100 + 0.5), math.floor(place[3] * 100 + 0.5))
end

local function sideWord(side)
  return side == "A" and L["Alliance"] or side == "H" and L["Horde"] or nil
end

local function metaLine(e)
  local parts = {}
  if e.levelMin then
    parts[#parts + 1] = e.levelMax
        and e.levelMax ~= e.levelMin
        and string.format(L["level %d to %d"], e.levelMin, e.levelMax)
      or string.format(e.levelMax and L["level %d"] or L["level %d+"], e.levelMin)
  end
  local names = {}
  for i, z in ipairs(e.zones or {}) do
    if i > 3 then
      break
    end
    names[#names + 1] = zoneName(z)
  end
  if names[1] then
    parts[#parts + 1] = table.concat(names, ", ")
  end
  parts[#parts + 1] = sideWord(e.side)
  if ns.Shelf.Unconfirmed(e) then
    parts[#parts + 1] = L["nobody has reported it in Forever yet"] -- E2, "unknown"
  end
  return table.concat(parts, "  /  ")
end

-- The plate on the left page, its own frame on the page's content (kept on the page).
local function plate(K, page, e)
  local pic = page.wonderPic
  if not pic then
    pic = Picture.New(page.content, true) -- framed: a model needs its border (16.11.2026)
    page.wonderPic = pic
  end
  local w = page.width
  local h = math.floor(w * Wonder.PLATE)
  pic:ClearAllPoints()
  pic:SetPoint("TOPLEFT", page.content, "TOPLEFT", 0, -page.y)
  local drew = Picture.Draw(pic, e, w, h)
  pic:Show()
  page.y = page.y + h + 6
  local caption
  if drew == "art" then
    caption = L["Drawn by Bastian, in the evenings, at whatever inn would have him."]
  elseif drew == "model" then
    caption = e.place and placeLine(e.place) or nil
  elseif drew == "painting" then
    caption = e.place and placeLine(e.place) or zoneName(e.zones and e.zones[1])
  end
  if caption then
    K.text(page, caption, 11, S.C.dim)
  end
end

local function gives(K, page, e)
  if not e.gives then
    return
  end
  K.space(page, 4)
  K.text(
    page,
    caps(e.chapter == "rares" and L["It drops"] or L["It gives"]),
    11,
    S.C.accent,
    0,
    3,
    "bookCaps"
  )
  for _, item in ipairs(e.gives) do
    local ent = B:Entity("item:" .. item)
    K.row(page, ent:Name() or string.format(L["item %d"], item), function()
      ns.Window.OpenRef("item:" .. item)
    end, { icon = ent:Icon(), ref = "item:" .. item, tip = L["Opens it in Bastian's Browser."] })
  end
end

local function acts(K, page, e)
  K.space(page, 6)
  local p = e.place
  if p and ns.Plate.CanShow(p, e.title) then
    K.row(page, L["Show on map"], function()
      ns.Plate.ShowOnMap(p, e.title)
    end, { icon = B.UI.IconTexture("zone"), color = S.C.accent })
  end
  if p and B:GetService("route") then
    K.row(page, L["Route there"], function()
      ns.Plate.RouteTo(p, e.title)
    end, { icon = B.UI.IconTexture("route"), color = S.C.accent })
  end
  local mine = Record.Entry(e.id)
  if mine then
    local when = date and date("%d.%m.%Y", mine.at or 0) or ""
    K.text(
      page,
      string.format(
        mine.how == "found" and L["Found done in the game on %s."] or L["Marked done on %s."],
        when
      ),
      13,
      S.C.good
    )
    K.row(page, L["Not done yet"], function()
      Record.Unmark(e.id)
      ns.Front.Invalidate()
      ns.Window.Render()
    end, { icon = B.UI.IconTexture("replay"), color = S.C.muted })
  else
    K.row(page, L["Mark done"], function()
      Record.Mark(e.id, "mark", nil, e.title)
      ns.Window.Render()
    end, {
      icon = B.UI.IconTexture("done"),
      color = S.C.accent,
      tip = L["It leaves the shelves and stands in Your record."],
    })
  end
  local alts = Record.Alts(e.id)
  if alts[1] then
    K.text(page, string.format(L["Done by %s"], table.concat(alts, ", ")), 13, S.C.gold)
  end
end

-- Nixie's envelope: the steps, sealed until opened (per account).
local function envelope(K, page, e)
  if not e.steps then
    return
  end
  K.space(page, 6)
  K.text(page, caps(L["Nixie's envelope"]), 11, S.C.accent, 0, 3, "bookCaps")
  if not Record.IsOpened(e.id) then
    K.text(
      page,
      string.format(
        L["%d steps, sealed. Nixie charges two silver for a rumour; this one is on the house."],
        #e.steps
      ),
      13,
      S.C.muted
    )
    K.row(page, L["Break the seal"], function()
      Record.Open(e.id)
      ns.Window.Render()
    end, { icon = B.UI.IconTexture("open"), color = S.C.gold })
    return
  end
  for i, step in ipairs(e.steps) do
    local head = step.title and (step.title .. ": ") or ""
    local side = sideWord(step.side)
    K.text(
      page,
      string.format("%d. %s%s%s", i, head, step.text or "", side and ("  (" .. side .. ")") or ""),
      13,
      S.C.text
    )
    if step.tip then
      K.text(page, step.tip, 11, S.C.dim, 14)
    end
    if step.place and ns.Plate.CanShow(step.place, step.title or e.title) then
      local where = placeLine(step.place) or L["Show on map"]
      K.row(page, where, function()
        ns.Plate.ShowOnMap(step.place, step.title or e.title)
      end, { icon = B.UI.IconTexture("zone"), color = S.C.accent, indent = 14 })
    end
  end
end

-- Renders the wonder `id` on the two pages -> its title. K: the window's page kit.
function Wonder.Render(K, left, right, id)
  local e = ns.Front.Find(id)
  if not e then
    K.text(left, L["This wonder is not in the book any more."], 13, S.C.dim)
    return id
  end
  plate(K, left, e)
  if e.start then
    K.space(left, 2)
    K.text(left, caps(L["Where it starts"]), 11, S.C.accent, 0, 3, "bookCaps")
    K.text(left, e.start, 13, S.C.text)
  end
  gives(K, left, e)
  -- the right page: the words
  K.text(right, caps(ns.Front.KindLabel(e)), 11, S.C.accent, 0, 2, "bookCaps")
  K.text(right, e.title, 18, S.C.bright, 0, 4, "bookDisplay")
  local meta = metaLine(e)
  if meta ~= "" then
    K.text(right, meta, 11, S.C.dim)
  end
  if e.hook then
    K.space(right, 4)
    K.text(right, e.hook, 13, S.C.text, nil, nil, "bookItalic")
  end
  if e.tale then
    K.space(right, 4)
    if e.hook then
      K.text(right, caps(L["What the travellers say"]), 11, S.C.accent, 0, 3, "bookCaps")
    end
    K.text(right, e.tale, 13, e.hook and S.C.muted or S.C.text)
  end
  if e.note then
    K.text(right, e.note, 11, S.C.dim)
  end
  envelope(K, right, e)
  acts(K, right, e)
  return e.title
end

-- The plate is the page's own frame: hidden when the page shows something else.
function Wonder.Hide(page)
  if page.wonderPic then
    Picture.Clear(page.wonderPic)
    page.wonderPic:Hide()
  end
end
