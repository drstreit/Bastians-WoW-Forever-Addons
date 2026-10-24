-- Bastian's Strategies: the book's logic (strategies-design.md section 6), plain tables in and out.
local _, ns = ...

local Book = {}
ns.Book = Book

local CUT = 0.95 -- the auction house keeps 5 % of a sale
Book.CUT = CUT
Book.UNSEAL_EARLY = 2 -- a page opens this many levels before its band starts (SB3)

-- What one turns through, in reading order: each chapter's active pages (index book.toc), then
-- the chapter's Rumour mill when hasMill(chapter) says it has one. -> { { kind, id } }, kind
-- "page" (id the page) or "mill" (id the chapter).
function Book.Order(toc, hasMill)
  local out = {}
  for _, chapter in ipairs(toc and toc.chapters or {}) do
    for _, id in ipairs(toc.pages and toc.pages[chapter] or {}) do
      out[#out + 1] = { kind = "page", id = id }
    end
    if hasMill and hasMill(chapter) then
      out[#out + 1] = { kind = "mill", id = chapter }
    end
  end
  return out
end

-- Sealed or open (SB3): open from the band's first level minus UNSEAL_EARLY, or once one of the
-- page's zones was entered (`entered[uiMapID] = true`). A page without a band is always open.
function Book.IsOpen(page, level, entered)
  if not (page and page.levelMin) then
    return true
  end
  if level and level >= page.levelMin - Book.UNSEAL_EARLY then
    return true
  end
  for _, zone in ipairs(page.zones or {}) do
    if entered and entered[zone] then
      return true
    end
  end
  return false
end

-- The text with its tokens drawn: {item:ID}, {npc:ID}, {object:ID}, {zone:ID} through
-- ctx.name(kind, id), {price:ID} through ctx.price(id), {vendor:ID} through ctx.vendor(id).
function Book.Expand(text, ctx)
  return (
    string.gsub(text or "", "{(%a+):(%d+)}", function(kind, id)
      id = tonumber(id)
      if kind == "price" then
        return ctx.price(id)
      elseif kind == "vendor" then
        return ctx.vendor(id)
      end
      return ctx.name(kind, id)
    end)
  )
end

-- The farm box: what one kill of `npcs` brings in loot after the auction house's cut.
-- loot(id) -> { {item, chance}, ... } or nil; price(item) -> copper or nil (unknown, never 0).
-- -> { perKill (copper, nil when no item has a price), items = { {item, chance, price, value} } the
-- most valuable first, unknown = items without a price }, or nil without loot.
function Book.Farm(npcs, loot, price)
  local chances, n = {}, 0
  for _, id in ipairs(npcs or {}) do
    local list = loot(id)
    if list then
      n = n + 1
      for _, l in ipairs(list) do
        chances[l[1]] = (chances[l[1]] or 0) + (l[2] or 0)
      end
    end
  end
  if n == 0 then
    return nil
  end
  local items, total, known, unknown = {}, 0, false, 0
  for item, sum in pairs(chances) do
    local chance = sum / n -- the npcs of one camp share their loot table, mostly
    local p = price(item)
    local value
    if p then
      value = p * chance / 100 * CUT
      total = total + value
      known = true
    else
      unknown = unknown + 1
    end
    items[#items + 1] = { item = item, chance = chance, price = p, value = value }
  end
  table.sort(items, function(a, b)
    local va, vb = a.value or -1, b.value or -1
    if va ~= vb then
      return va > vb
    end
    return a.item < b.item
  end)
  return { perKill = known and math.floor(total + 0.5) or nil, items = items, unknown = unknown }
end

-- The flip box: buy one item on the auction house (buyPrice, nil unknown), sell what it becomes to a
-- vendor (vendorPrice per item made, `per` made from one bought). -> { sale, margin, open, ownAH }:
-- margin and open nil while the buying price is unknown; ownAH what the bought item itself brings
-- on the auction house after the cut (for a player's own stock). nil without a vendor price.
function Book.Flip(buyPrice, vendorPrice, per)
  if not vendorPrice then
    return nil
  end
  local sale = vendorPrice * (per or 1)
  if not buyPrice then
    return { sale = sale }
  end
  return {
    sale = sale,
    margin = sale - buyPrice,
    open = sale > buyPrice,
    ownAH = math.floor(buyPrice * CUT + 0.5),
  }
end

-- The craft box: a recipe's margin. product = AH copper of the product (nil unknown), count made
-- per craft, reagents = { {item, n} }, costOf(item) -> copper (the AH, else a vendor) or nil.
-- -> { cost (nil when a reagent's price is unknown), sale (after the cut), margin, missing = n }.
function Book.Craft(product, count, reagents, costOf)
  local cost, missing = 0, 0
  for _, r in ipairs(reagents or {}) do
    local p = costOf(r[1])
    if p then
      cost = cost + p * (r[2] or 1)
    else
      missing = missing + 1
    end
  end
  local sale = product and math.floor(product * (count or 1) * CUT + 0.5) or nil
  if missing > 0 then
    return { sale = sale, missing = missing }
  end
  return { cost = cost, sale = sale, margin = sale and (sale - cost) or nil, missing = 0 }
end

-- The vendor pairs table (the bandage page): rows { from, made, per } with sellOf(item) -> copper.
-- -> { {from, made, fromSell, madeSell, gain} }, gain the share more (or less) the made item brings
-- than the `per` items it is made of; nil where a price is missing.
function Book.Pairs(rows, sellOf)
  local out = {}
  for _, r in ipairs(rows or {}) do
    local from, made, per = r[1], r[2], r[3] or 1
    local a, b = sellOf(from), sellOf(made)
    local gain
    if a and b and a > 0 then
      gain = b / (a * per) - 1
    end
    out[#out + 1] = { from = from, made = made, per = per, fromSell = a, madeSell = b, gain = gain }
  end
  return out
end

-- The index (A-Z): every page by its name (with its shelf) and every place, item or creature a page
-- names, each with the pages that name it. pages = { [id] = record }; nameOf(ref) -> name or nil.
function Book.Index(pages, nameOf)
  local out, byRef = {}, {}
  for id, p in pairs(pages) do
    out[#out + 1] = { text = p.name or id, kind = "page", page = id, shelf = p.shelf }
    for _, ref in ipairs(p.refs or {}) do
      local entry = byRef[ref]
      if not entry then
        entry = { text = nameOf(ref) or ref, kind = "ref", ref = ref, pages = {} }
        byRef[ref] = entry
        out[#out + 1] = entry
      end
      entry.pages[#entry.pages + 1] = id
    end
  end
  for _, entry in pairs(byRef) do
    table.sort(entry.pages)
  end
  table.sort(out, function(a, b)
    local x, y = string.lower(a.text), string.lower(b.text)
    if x ~= y then
      return x < y
    end
    return (a.page or a.ref) < (b.page or b.ref)
  end)
  return out
end

-- The pages that name an entity (the "In Bastian's book" block on Browser pages): refs -> ids.
function Book.PagesOf(pages, ref)
  local out = {}
  for id, p in pairs(pages) do
    if p.shelf ~= "retired" then
      for _, r in ipairs(p.refs or {}) do
        if r == ref then
          out[#out + 1] = id
          break
        end
      end
    end
  end
  table.sort(out)
  return out
end

-- Bookmarks are page ids per character (strategies-design.md section 7: ids are permanent, so a
-- bookmark survives every rotation of the book). Returns true when `id` is kept afterwards.
function Book.ToggleBookmark(list, id)
  for i, kept in ipairs(list) do
    if kept == id then
      table.remove(list, i)
      return false
    end
  end
  list[#list + 1] = id
  return true
end

function Book.IsBookmarked(list, id)
  for _, kept in ipairs(list or {}) do
    if kept == id then
      return true
    end
  end
  return false
end

-- What's new: an entry is new when it is newer than the date the reader saw last ("YYYY-MM-DD"),
-- or of that date and not among `seenToday` (the texts of that date the reader saw), so a second
-- update on the same day is new too. seenToday nil (saved variables of 1.0.0-beta.8): the whole
-- date was seen.
function Book.IsNew(entry, seen, seenToday)
  if not seen or entry.date > seen then
    return true
  end
  return entry.date == seen and seenToday ~= nil and not seenToday[entry.text]
end

function Book.Unread(news, seen, seenToday)
  local n = 0
  for _, entry in ipairs(news or {}) do
    if Book.IsNew(entry, seen, seenToday) then
      n = n + 1
    end
  end
  return n
end

-- The book in the suite's What's new (ADR 0021): one line a day at most, newest first, the last
-- `days` days that have entries. A day with a hand-written entry leads with it ("... And 3
-- more."); a day of the build's entries only counts them ("2 new rumours, 1 updated page."). ->
-- { { id, date, text, target } }, `target` = { kind = "page" | "mill", id } when the day names one
-- place only, else nil (the book's own What's new lists the day with its links). `L` translates
-- the counting words; the entries' own texts are the book's English.
function Book.Fold(news, L, days)
  local byDate, dates = {}, {}
  for _, e in ipairs(news or {}) do
    if not byDate[e.date] then
      byDate[e.date] = {}
      dates[#dates + 1] = e.date
    end
    table.insert(byDate[e.date], e)
  end
  table.sort(dates, function(a, b)
    return a > b
  end)
  local out = {}
  for i = 1, math.min(days or 10, #dates) do
    local day = byDate[dates[i]]
    local authored, pages, rumours, more = nil, {}, 0, 0
    local npages = 0
    for _, e in ipairs(day) do
      if e.kind == nil and not authored then
        authored = e
      elseif e.kind == "travellers" or e.kind == "stamp" then
        if e.page and not pages[e.page] then
          pages[e.page] = true
          npages = npages + 1
        end
      elseif e.kind == "mill" then
        rumours = rumours + (e.n or 1)
      elseif e.kind == "more" then
        more = more + (e.n or 1)
      end
    end
    local text
    if authored then
      text = authored.text
      if #day > 1 then
        text = text .. " " .. string.format(L["And %d more."], #day - 1)
      end
    else
      local parts = {}
      if rumours > 0 then
        parts[#parts + 1] = rumours == 1 and L["1 new rumour"] or string.format(L["%d new rumours"], rumours)
      end
      if npages > 0 then
        parts[#parts + 1] = npages == 1 and L["1 updated page"]
          or string.format(L["%d updated pages"], npages)
      end
      if more > 0 then
        parts[#parts + 1] = string.format(L["%d more changes"], more)
      end
      text = table.concat(parts, ", ") .. "."
    end
    local target
    if #day == 1 and day[1].page then
      target = { kind = "page", id = day[1].page }
    elseif #day == 1 and day[1].mill then
      target = { kind = "mill", id = day[1].mill }
    end
    out[#out + 1] = { id = dates[i] .. ":" .. text, date = dates[i], text = text, target = target }
  end
  return out
end

-- "1:25" from a link's t= parameter (the moment in the video), nil without one.
function Book.Moment(link)
  local t = tonumber(string.match(link or "", "[?&]t=(%d+)"))
  if not t then
    return nil
  end
  return string.format("%d:%02d", math.floor(t / 60), t % 60)
end
