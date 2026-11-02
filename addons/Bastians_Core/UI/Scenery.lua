-- UI kit: the skin's scenery (ADR 0034, core.md "The skin"): places as cuts of the zone's
-- painting, the painting behind a creature, creatures that greet, faces in the rows of NPCs, the
-- page sounds. The dossier, the stage and the tree call it; each part only while its switch
-- (S.Skin) is on. The loot grid is gone.
local _, ns = ...
local B = ns.B
local S = ns.Style
local L = ns.L

local Scenery = {}
B.UI.Scenery = Scenery

Scenery.CELL_GAP = 4 -- between two place cuts
Scenery.CUT_W, Scenery.CUT_H, Scenery.CUT_CAPTION = 132, 80, 16 -- a place cut and its caption
Scenery.CUT_SPAN = 0.3 -- a cut shows this share of the painting's width
Scenery.DIORAMA_SPAN = 0.22 -- the stage's painting: a closer cut around the creature
Scenery.DIORAMA_ALPHA = 0.55
Scenery.FACES = 48 -- models per list (row portraits)
Scenery.SOUND_GAP = 0.2 -- seconds between two page sounds

-- The animations (assumed, AnimationData ids of the retail family, ADR 0034).
Scenery.ANIM = {
  stand = 0,
  talk = 60,
  exclaim = 64,
  question = 65,
  bow = 66,
  wave = 67,
  cheer = 68,
  dance = 69,
  laugh = 70,
  roar = 74,
  applaud = 80,
  shout = 81,
  flex = 82,
  point = 84,
}
-- The greeting by the NPC's services (Data's flags), the first that matches.
Scenery.GREETINGS = {
  { "vendor", "wave" },
  { "innkeeper", "wave" },
  { "repair", "wave" },
  { "flightmaster", "wave" },
  { "banker", "wave" },
  { "trainer", "bow" },
  { "questgiver", "exclaim" },
}

-- ---------------------------------------------------------------------------------------------
-- Pure helpers (tested alone)
-- ---------------------------------------------------------------------------------------------

-- Cells of `cellW` with `gap` in a row of `width` px: -> per row, rows, the height of `n` cells.
function Scenery.GridShape(n, width, cellW, cellH, gap)
  local perRow = math.max(1, math.floor((width + gap) / (cellW + gap)))
  local rows = math.ceil(n / perRow)
  return perRow, rows, rows > 0 and (rows * cellH + (rows - 1) * gap) or 0
end

-- The window of a cut around (x, y) (map fractions) on a painting of `aw` x `ah` px: `span` of its
-- width, as tall as `aspect` (height / width) asks, kept on the painting. -> x0, y0, w, h in
-- painting px and the point's place in the window (px).
function Scenery.CutWindow(x, y, aw, ah, span, aspect)
  local w = math.min(aw, aw * span)
  local h = math.min(ah, w * aspect)
  local cx, cy = x * aw, y * ah
  local x0 = math.max(0, math.min(aw - w, cx - w / 2))
  local y0 = math.max(0, math.min(ah - h, cy - h / 2))
  local px = math.max(0, math.min(w, cx - x0))
  local py = math.max(0, math.min(h, cy - y0))
  return x0, y0, w, h, px, py
end

-- The tile's part inside the window, as texture coordinates and a place: nil when outside.
function Scenery.Crop(t, x0, y0, w, h)
  local ix1, iy1 = math.max(t.px1, x0), math.max(t.py1, y0)
  local ix2, iy2 = math.min(t.px2, x0 + w), math.min(t.py2, y0 + h)
  if ix2 <= ix1 or iy2 <= iy1 then
    return nil
  end
  local tw, th = t.px2 - t.px1, t.py2 - t.py1
  local tr, tb = t.tcRight or 1, t.tcBottom or 1
  return (ix1 - t.px1) / tw * tr,
    (ix2 - t.px1) / tw * tr,
    (iy1 - t.py1) / th * tb,
    (iy2 - t.py1) / th * tb,
    ix1,
    iy1,
    ix2,
    iy2
end

-- The greeting of an NPC record: the animation's name.
function Scenery.Greeting(record)
  local flags = record and record.flags
  if type(flags) ~= "table" then
    flags = flags and { flags } or {}
  end
  local has = {}
  for _, f in ipairs(flags) do
    has[tostring(f)] = true
  end
  for _, g in ipairs(Scenery.GREETINGS) do
    if has[g[1]] then
      return g[2]
    end
  end
  return "roar"
end

-- ---------------------------------------------------------------------------------------------
-- The painting cut: the zone's art tiles (and the explored areas) inside a window, cropped by
-- texture coordinates (no clipping frame needed) into `frame` at `w` x `h` px.
-- ---------------------------------------------------------------------------------------------

-- The painting's window x0, y0, cw, ch (painting px) into `frame` at `w` x `h` px from the frame's
-- top left; -> the textures used. Parts of the window beyond the painting stay empty.
local function drawWindow(frame, pool, art, x0, y0, cw, ch, w, h, alpha)
  local n = 0
  local kx, ky = w / cw, h / ch
  local function draw(t, sublevel)
    local u1, u2, v1, v2, ix1, iy1, ix2, iy2 = Scenery.Crop(t, x0, y0, cw, ch)
    if not u1 then
      return
    end
    n = n + 1
    local tex = pool[n]
    if not tex then
      tex = frame:CreateTexture(nil, "BACKGROUND")
      pool[n] = tex
    end
    tex:SetTexture(t.file)
    tex:SetTexCoord(u1, u2, v1, v2)
    tex:SetDrawLayer("BACKGROUND", sublevel)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", frame, "TOPLEFT", (ix1 - x0) * kx, -(iy1 - y0) * ky)
    tex:SetSize(math.max(1, (ix2 - ix1) * kx), math.max(1, (iy2 - iy1) * ky))
    tex:SetAlpha(alpha or 1)
    tex:Show()
  end
  for _, t in ipairs(art.tiles) do
    draw(t, 1)
  end
  for _, t in ipairs(art.explored or {}) do
    draw(t, t.top and 3 or 2)
  end
  return n
end

local function hideFrom(pool, n)
  for i = n + 1, #pool do
    pool[i]:Hide()
  end
end

-- Draws the cut and returns the pin's place in px (x right, y down), or nil without art.
function Scenery.DrawCut(frame, pool, uiMapID, x, y, w, h, span, alpha)
  local art = uiMapID and B.Coords.MapArt(tonumber(uiMapID))
  local n = 0
  local px, py
  if art and x and y then
    local x0, y0, cw, ch, ppx, ppy = Scenery.CutWindow(x, y, art.width, art.height, span, h / w)
    n = drawWindow(frame, pool, art, x0, y0, cw, ch, w, h, alpha)
    px, py = ppx * w / cw, ppy * h / ch
  end
  hideFrom(pool, n)
  return px, py
end

-- The painting of the map box fx0, fy0 .. fx1, fy1 (map fractions) exactly into `w` x `h` px of
-- `frame` (the Strategies plates, 29.10.2026: the dots must sit where the painting shows them, so
-- the box is never moved onto the painting as a cut is). -> true when there was art.
function Scenery.DrawBox(frame, pool, uiMapID, fx0, fy0, fx1, fy1, w, h, alpha)
  local art = uiMapID and B.Coords.MapArt(tonumber(uiMapID))
  local n = 0
  if art and fx0 and fx1 > fx0 and fy1 > fy0 then
    local aw, ah = art.width, art.height
    n = drawWindow(frame, pool, art, fx0 * aw, fy0 * ah, (fx1 - fx0) * aw, (fy1 - fy0) * ah, w, h, alpha)
  end
  hideFrom(pool, n)
  return n > 0
end

-- The first place of an entity: { map, x, y } from Data's spawns, or nil.
function Scenery.FirstPlace(ref)
  local d = B:GetService("data")
  local list = d and d.Spawns and d:Spawns(ref)
  local s = type(list) == "table" and list[1]
  if s and s.map and s.x and s.y then
    return s
  end
  return nil
end

-- ---------------------------------------------------------------------------------------------
-- Cells: a dossier block drawn as loot cells or place cuts instead of rows
-- ---------------------------------------------------------------------------------------------

-- The mode a block's rows ask for under the skin: "places" (every row carries a place) or nil
-- (rows).
function Scenery.BlockMode(block)
  local rows = block.rows or {}
  if #rows == 0 then
    return nil
  end
  -- a dungeon's floors (data.md "Dungeons", DG2): every row carries a floor, drawn as a plate of
  -- the client's tiles with the boss pins, whatever the skin's switches say
  local floors = true
  for _, row in ipairs(rows) do
    if type(row.floor) ~= "table" then
      floors = false
      break
    end
  end
  if floors then
    return "floors"
  end
  if S.Skin("placeCuts") then
    local all = true
    for _, row in ipairs(rows) do
      if type(row.place) ~= "table" then
        all = false
        break
      end
    end
    if all then
      return "places"
    end
  end
  return nil
end

-- The size of a cell in a mode.
function Scenery.CellSize(_mode)
  return Scenery.CUT_W, Scenery.CUT_H + Scenery.CUT_CAPTION
end

-- The height `n` cells of a mode take at `width`.
function Scenery.CellsHeight(mode, n, width)
  local cw, ch = Scenery.CellSize(mode)
  local _, _, h = Scenery.GridShape(n, width, cw, ch, Scenery.CELL_GAP)
  return h
end

local function rowTooltip(cell)
  local row, host = cell.row, cell.host
  if not (row and GameTooltip) then
    return
  end
  GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
  if row.tooltip then
    row.tooltip(GameTooltip, row)
  elseif host and host.opts.tooltip then
    host.opts.tooltip(GameTooltip, row)
  elseif row.ref then
    S.EntityTip(GameTooltip, row.ref, row.text)
  else
    S.TipLine(GameTooltip, row.text or "", "tipText")
  end
  GameTooltip:Show()
end

local function newCell(bf, host)
  local cell = CreateFrame("Button", nil, bf)
  cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  cell.host = host
  cell.hl = S.fill(cell, S.C.hover, "HIGHLIGHT")
  cell.cut = CreateFrame("Frame", nil, cell) -- a place's painting, the plate under it
  cell.cut:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, 0)
  cell.cut:SetSize(Scenery.CUT_W, Scenery.CUT_H)
  cell.cut.plate = S.roundFill(cell.cut, S.C.header, "radiusSmall", "BACKGROUND")
  cell.cut:EnableMouse(false)
  cell.art = {}
  cell.pin = cell.cut:CreateTexture(nil, "OVERLAY")
  cell.pin:SetTexture(S.DISC)
  cell.pin:SetSize(9, 9)
  S.tint(cell.pin, S.C.waypointLoud)
  cell.caption = S.text(cell, 10, S.C.dim)
  cell.caption:SetJustifyH("CENTER")
  cell.caption:SetWordWrap(false)
  cell:SetScript("OnEnter", rowTooltip)
  cell:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  cell:SetScript("OnClick", function(self, button)
    if self.row then
      self.host:RowClick(self.row, button)
    end
  end)
  return cell
end

-- ---------------------------------------------------------------------------------------------
-- A dungeon's floor as a plate (DG2c, 30.10.2026; owner: "the actual dungeon maps, not our
-- physical"): the client's own map of the floor laid out in floor pixels and scaled to the
-- plate's width, the bosses as numbered pins that open the boss (a click) and the door as a pin
-- of its own; a click on the plate opens the floor enlarged in a window of its own with the
-- dungeon's other floors as tabs. The art comes from the client: on retail the floor's UiMap art
-- (C_Map through Coords.MapArt), on Forever the same files by name (`floor.art` .. 1 to 12, the
-- way the DungeonJournal addon draws them; assumed from that addon, to verify on Forever), else
-- ForeverDB's minimap tiles (`floor.tiles`, Forever's own dungeons); a floor without any is the
-- bare plate with its pins.
-- ---------------------------------------------------------------------------------------------

Scenery.FLOOR_MAX_ASPECT = 1.0 -- a plate is never taller than wide
Scenery.FLOOR_CAPTION = 16 -- the floor's name under the plate
Scenery.FLOOR_GAP = 6
Scenery.FLOOR_TILE = 256 -- the art files' tiles (a 4 x 3 grid, 1002 x 668 of it visible)
Scenery.FLOOR_WIN_W, Scenery.FLOOR_WIN_H = 820, 620 -- the enlarged floor's window
Scenery.FLOOR_CREDIT = 24 -- the artist's line under the enlarged floor (ADR 0048)
Scenery.FLOOR_LINK_W = 240 -- the box with the artist's address to copy

-- The artist of a hand-drawn floor (`floor.by`, ADR 0048): { name, work, url } or nil.
function Scenery.FloorArtist(floor)
  local about = B.UI.About
  return floor and floor.by and about and about.ARTISTS and about.ARTISTS[floor.by] or nil
end

local artCache = {} -- [uiMapID] = the client's art or false

-- The art of a floor as the client gives it: { w, h, tiles = { {file, x, y, w, h, q, tcRight,
-- tcBottom} } } in floor pixels, or nil. Retail's UiMap art is asked once per map.
function Scenery.FloorArt(floor)
  if floor.uiMap and B.Coords and B.Coords.MapArt then
    local art = artCache[floor.uiMap]
    if art == nil then
      local got = B.Coords.MapArt(floor.uiMap)
      art = false
      if got and got.tiles and #got.tiles > 0 then
        local tiles = {}
        for _, t in ipairs(got.tiles) do
          tiles[#tiles + 1] = { t.file, t.px1, t.py1, t.px2 - t.px1, t.py2 - t.py1, 0, t.tcRight, t.tcBottom }
        end
        art = { w = got.width, h = got.height, tiles = tiles }
      end
      artCache[floor.uiMap] = art
    end
    if art then
      return art
    end
  end
  if floor.art and floor.cols and floor.rows then
    local tiles, size = {}, Scenery.FLOOR_TILE
    for r = 0, floor.rows - 1 do
      for c = 0, floor.cols - 1 do
        tiles[#tiles + 1] = { floor.art .. (r * floor.cols + c + 1), c * size, r * size, size, size, 0 }
      end
    end
    return { w = floor.w, h = floor.h, tiles = tiles }
  end
  if floor.tiles and #floor.tiles > 0 then
    return { w = floor.w, h = floor.h, tiles = floor.tiles }
  end
  return nil
end

-- The plate of `floor` ({ w, h, uiMap, art, cols, rows, tiles, bosses = { {order, x, y, name,
-- ref} }, door = { x, y } }) at `width` px: its height, the tiles in plate px (file, x, y, w, h,
-- q, tcRight, tcBottom), the pins in plate px (x, y, label, kind "boss" | "door", name, ref).
-- Pure but for the client's art.
function Scenery.FloorLayout(floor, width)
  local art = Scenery.FloorArt(floor)
  local fw = math.max(1, art and art.w or floor.w or 1)
  local fh = math.max(1, art and art.h or floor.h or 1)
  local aspect = math.min(Scenery.FLOOR_MAX_ASPECT, fh / fw)
  local height = math.floor(width * aspect + 0.5)
  local k = width / fw
  local tiles, pins = {}, {}
  for _, t in ipairs(art and art.tiles or {}) do
    tiles[#tiles + 1] =
      { t[1], t[2] * k, t[3] * k, math.max(1, t[4] * k), math.max(1, t[5] * k), t[6] or 0, t[7], t[8] }
  end
  for _, b in ipairs(floor.bosses or {}) do
    pins[#pins + 1] = { b[2] / 100 * width, b[3] / 100 * height, tostring(b[1]), "boss", b[4], b[5] }
  end
  if floor.door then
    pins[#pins + 1] = { floor.door[1] / 100 * width, floor.door[2] / 100 * height, "", "door" }
  end
  return height, tiles, Scenery.SpreadPins(pins), art ~= nil
end

Scenery.PIN_GAP = 17 -- px between two pins' centres (a pin is 16 px)

-- Pins that would overlap
-- move onto a small circle around their middle, in their order, the first on top; everything
-- within `gap` of a pin of the group joins it. Pure: the pins' x and y change in place.
function Scenery.SpreadPins(pins, gap)
  gap = gap or Scenery.PIN_GAP
  local taken = {}
  for i = 1, #pins do
    if not taken[i] then
      local group = { i }
      taken[i] = true
      local k = 1
      while k <= #group do
        local a = pins[group[k]]
        for j = i + 1, #pins do
          local b = pins[j]
          if not taken[j] and (a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 < gap * gap then
            taken[j] = true
            group[#group + 1] = j
          end
        end
        k = k + 1
      end
      local n = #group
      if n > 1 then
        table.sort(group)
        local cx, cy = 0, 0
        for _, g in ipairs(group) do
          cx, cy = cx + pins[g][1], cy + pins[g][2]
        end
        cx, cy = cx / n, cy / n
        local r = gap / (2 * math.sin(math.pi / n))
        for m, g in ipairs(group) do
          local angle = -math.pi / 2 + (m - 1) * 2 * math.pi / n
          pins[g][1] = cx + r * math.cos(angle)
          pins[g][2] = cy + r * math.sin(angle)
        end
      end
    end
  end
  return pins
end

-- The height `rows` of floors take at `width`: each plate, its caption, the gaps.
function Scenery.FloorsHeight(rows, width)
  local h = 0
  for _, row in ipairs(rows) do
    local plate = Scenery.FloorLayout(row.floor or {}, width)
    h = h + plate + Scenery.FLOOR_CAPTION + Scenery.FLOOR_GAP
  end
  return h
end

local function pinTooltip(pin)
  if not (GameTooltip and pin.name) then
    return
  end
  GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
  GameTooltip:SetText(pin.name)
  if pin.ref then
    GameTooltip:AddLine(L["Click: open"], 1, 1, 1)
  end
  GameTooltip:Show()
end

local function newPin(cut, cell)
  local pin = CreateFrame("Button", nil, cut)
  pin:SetSize(16, 16)
  pin:SetFrameLevel((cut:GetFrameLevel() or 0) + 2)
  pin.disc = pin:CreateTexture(nil, "OVERLAY")
  pin.disc:SetTexture(S.DISC)
  pin.disc:SetAllPoints(pin)
  pin.label = S.text(pin, 10, S.C.bright)
  pin.label:SetPoint("CENTER")
  pin.label:SetJustifyH("CENTER")
  pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  pin:SetScript("OnEnter", pinTooltip)
  pin:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  pin:SetScript("OnClick", function(self, button)
    if self.ref and cell.host and cell.host.RowClick then
      cell.host:RowClick({ ref = self.ref, text = self.name, kind = "pin" }, button)
    end
  end)
  return pin
end

-- Lays a floor's plate into `cell` (a cell of newCell) at `width` px; returns the cell's height.
local function layoutFloorCell(cell, row, width, bare)
  local floor = row.floor or {}
  local height, tiles, pins, hasArt = Scenery.FloorLayout(floor, width)
  cell:SetSize(width, height + (bare and 0 or Scenery.FLOOR_CAPTION))
  cell.cut:Show()
  cell.cut:SetSize(width, height)
  if cell.cut.SetClipsChildren then
    cell.cut:SetClipsChildren(true) -- a tile that reaches past the floor is cropped
  end
  local n = 0
  for _, t in ipairs(tiles) do
    n = n + 1
    local tex = cell.art[n]
    if not tex then
      tex = cell.cut:CreateTexture(nil, "BACKGROUND")
      cell.art[n] = tex
    end
    tex:SetTexture(t[1])
    tex:SetTexCoord(0, t[7] or 1, 0, t[8] or 1)
    tex:SetDrawLayer("BACKGROUND", 1)
    if tex.SetRotation then
      tex:SetRotation(t[6] * math.pi / 2)
    end
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", cell.cut, "TOPLEFT", t[2], -t[3])
    tex:SetSize(t[4], t[5])
    tex:SetAlpha(1)
    tex:Show()
  end
  for i = n + 1, #cell.art do
    cell.art[i]:Hide()
  end
  cell.pin:Hide()
  cell.pins = cell.pins or {}
  for i, p in ipairs(pins) do
    local pin = cell.pins[i]
    if not pin then
      pin = newPin(cell.cut, cell)
      cell.pins[i] = pin
    end
    S.tint(pin.disc, p[4] == "door" and S.C.good or S.C.bad)
    pin.label:SetText(p[3])
    pin.name = p[5]
    pin.ref = p[6]
    pin:EnableMouse(p[5] ~= nil)
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", cell.cut, "TOPLEFT", p[1], -p[2])
    pin:Show()
  end
  for i = #pins + 1, #(cell.pins or {}) do
    cell.pins[i]:Hide()
  end
  if bare then
    cell.caption:Hide()
    return height
  end
  cell.caption:Show()
  cell.caption:ClearAllPoints()
  cell.caption:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, -(height + 2))
  cell.caption:SetWidth(width)
  S.ink(cell.caption, S.C.dim)
  local note = (not hasArt and ("  " .. L["(the client has no map of this floor)"])) or ""
  local artist = Scenery.FloorArtist(floor)
  if artist then
    note = note .. "  -  " .. string.format(L["Map by %s"], artist.name)
  end
  if floor.note then
    note = note .. "  " .. floor.note
  end
  cell.caption:SetText((row.text or "") .. note)
  return height + Scenery.FLOOR_CAPTION
end

-- The enlarged floor: one window for
-- the suite, the dungeon's floors as tabs on top, the plate below as wide as the window allows.
local floorWin

local function floorTabs(rows, index)
  local tabs = floorWin.tabs
  local x = 0
  for i, row in ipairs(rows) do
    local tab = tabs[i]
    if not tab then
      tab = S.button(floorWin.bar, "", 120, 22)
      tab:SetScript("OnClick", function(self)
        Scenery.OpenFloor(floorWin.rows, self.index, floorWin.host)
      end)
      tabs[i] = tab
    end
    tab.index = i
    -- the kit's button draws its own label ("two buttons without any
    -- text": SetText wrote to a font string the button does not have)
    tab:SetLabel(row.text or tostring(i))
    tab:SetWidth(math.max(60, math.min(180, (tab.label:GetStringWidth() or 100) + 24)))
    tab:ClearAllPoints()
    tab:SetPoint("LEFT", floorWin.bar, "LEFT", x, 0)
    tab:SetAlpha(i == index and 1 or 0.6)
    tab:Show()
    x = x + tab:GetWidth() + 4
  end
  for i = #rows + 1, #tabs do
    tabs[i]:Hide()
  end
end

local function floorRender()
  if not (floorWin and floorWin.rows) then
    return
  end
  local row = floorWin.rows[floorWin.index]
  if not row then
    return
  end
  local content = floorWin.win.content
  local artist = Scenery.FloorArtist(row.floor)
  local credit = artist and Scenery.FLOOR_CREDIT or 0
  local width = math.max(100, (content:GetWidth() or Scenery.FLOOR_WIN_W) - 2 * 8)
  local avail = math.max(100, (content:GetHeight() or Scenery.FLOOR_WIN_H) - 30 - 2 * 8 - credit)
  -- the plate fits the window: as wide as it can be without growing taller than the room
  local h = Scenery.FloorLayout(row.floor or {}, width)
  if h > avail then
    width = math.floor(width * avail / h)
  end
  local cell = floorWin.cell
  cell.row, cell.host = row, floorWin.host
  local height = layoutFloorCell(cell, row, width, true)
  cell:ClearAllPoints()
  cell:SetPoint("TOP", content, "TOP", 0, -(30 + 8 + math.max(0, (avail - height) / 2)))
  cell:Show()
  -- "Dungeon: floor", the dungeon alone when the floor is named after it (02.11.2026: "City of
  -- Dalaran: City of Dalaran")
  local dungeon = row.floor and row.floor.dungeon or ""
  local floorName = row.text or ""
  if dungeon ~= "" and floorName ~= "" and floorName ~= dungeon then
    floorWin.win:SetTitle(dungeon .. ": " .. floorName)
  else
    floorWin.win:SetTitle(dungeon ~= "" and dungeon or (row.text or L["Dungeon map"]))
  end
  floorTabs(floorWin.rows, floorWin.index)
  -- the artist's thanks under the map, the address in a box to copy ("clearly
  -- state this with a thank you, directly under the maps, with a link to his site")
  if artist then
    floorWin.credit:SetText(
      string.format(L["Map by %s (%s), used with kind permission. Thank you!"], artist.name, artist.work)
    )
    floorWin.link.address = artist.url
    floorWin.link:SetText(artist.url)
    floorWin.link:SetCursorPosition(0)
    floorWin.credit:Show()
    floorWin.link:Show()
  else
    floorWin.credit:Hide()
    floorWin.link:Hide()
  end
end

-- The read-only box with an artist's address: a click selects it for Ctrl+C, a change is undone.
local function newLinkBox(parent)
  local box = CreateFrame("EditBox", nil, parent)
  box:SetSize(Scenery.FLOOR_LINK_W, 20)
  box:SetAutoFocus(false)
  box:SetFont(S.font(), S.size(11), "")
  S.fonts[box] = 11
  S.ink(box, S.C.accent)
  box:SetTextInsets(6, 6, 0, 0)
  box.face = S.roundFill(box, S.C.panel, "radiusSmall")
  box:SetScript("OnEditFocusGained", function(self)
    self:HighlightText()
  end)
  box:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)
  box:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
  end)
  box:SetScript("OnTextChanged", function(self, byUser)
    if byUser and self.address then
      self:SetText(self.address)
      self:HighlightText()
    end
  end)
  box:SetScript("OnEnter", function(self)
    if GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(L["Click, then Ctrl+C to copy the address"])
      GameTooltip:Show()
    end
  end)
  box:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  return box
end

-- Opens the floor `index` of `rows` (the floor rows of one dungeon page) enlarged; `host` is the
-- dossier the pins report their clicks to.
function Scenery.OpenFloor(rows, index, host)
  if not floorWin then
    local win = B.UI.Window("BastiansFloorFrame", {
      title = L["Dungeon map"],
      width = Scenery.FLOOR_WIN_W,
      height = Scenery.FLOOR_WIN_H,
      minWidth = 360,
      minHeight = 300,
      db = ns.core and ns.core.db and ns.core.db.profile and ns.core.db.profile.floorWindow,
      onResize = floorRender,
    })
    floorWin = { win = win, tabs = {} }
    floorWin.bar = CreateFrame("Frame", nil, win.content)
    floorWin.bar:SetPoint("TOPLEFT", 8, -4)
    floorWin.bar:SetPoint("TOPRIGHT", -8, -4)
    floorWin.bar:SetHeight(22)
    floorWin.cell = newCell(win.content, host)
    floorWin.cell:SetScript("OnClick", nil) -- the enlarged plate is the end of the road
    floorWin.cell.hl:Hide()
    floorWin.link = newLinkBox(win.content)
    floorWin.link:SetPoint("BOTTOMRIGHT", win.content, "BOTTOMRIGHT", -8, 6)
    floorWin.credit = S.text(win.content, 11, S.C.dim)
    floorWin.credit:SetPoint("BOTTOMLEFT", win.content, "BOTTOMLEFT", 8, 10)
    floorWin.credit:SetPoint("RIGHT", floorWin.link, "LEFT", -8, 0)
    floorWin.credit:SetJustifyH("LEFT")
    floorWin.credit:SetWordWrap(false)
    win.credit, win.link = floorWin.credit, floorWin.link
    win.floor = floorWin -- the tabs and the rows shown (tests)
  end
  floorWin.rows, floorWin.index, floorWin.host = rows, index or 1, host
  floorWin.win:Show()
  floorRender()
end

function Scenery.FloorWindow()
  return floorWin and floorWin.win or nil
end

local function renderFloors(bf, rows, width, top, host)
  bf.cells = bf.cells or {}
  local y = top
  for i, row in ipairs(rows) do
    local cell = bf.cells[i]
    if not cell then
      cell = newCell(bf, host)
      cell:SetScript("OnClick", function(self, button)
        if self.row and button ~= "RightButton" then
          Scenery.OpenFloor(self.rows, self.index, self.host)
        elseif self.row then
          self.host:RowClick(self.row, button)
        end
      end)
      bf.cells[i] = cell
    end
    cell.row, cell.host, cell.rows, cell.index = row, host, rows, i
    cell:ClearAllPoints()
    cell:SetPoint("TOPLEFT", bf, "TOPLEFT", 0, -y)
    y = y + layoutFloorCell(cell, row, width) + Scenery.FLOOR_GAP
    cell:Show()
  end
  for i = #rows + 1, #bf.cells do
    bf.cells[i]:Hide()
    bf.cells[i].row = nil
  end
end

local function layoutPlaceCell(cell, row)
  local w, h = Scenery.CUT_W, Scenery.CUT_H
  cell.cut:Show()
  local p = row.place or {}
  local px, py = Scenery.DrawCut(cell.cut, cell.art, p.map, p.x, p.y, w, h, Scenery.CUT_SPAN)
  if px then
    cell.pin:ClearAllPoints()
    cell.pin:SetPoint("CENTER", cell.cut, "TOPLEFT", px, -py)
    cell.pin:Show()
  else
    cell.pin:Hide()
  end
  cell.caption:ClearAllPoints()
  cell.caption:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, -(h + 2))
  cell.caption:SetWidth(w)
  if row.kind == "more" then
    cell.pin:Hide()
    cell.caption:ClearAllPoints()
    cell.caption:SetPoint("CENTER")
    S.ink(cell.caption, S.C.accent)
  else
    S.ink(cell.caption, S.C.dim)
  end
  cell.caption:SetText(row.text or "")
end

-- Lays `rows` out as cells of `mode` in the block frame `bf` from `top` px down at `width`; the
-- host is the dossier (its RowClick and tooltip).
function Scenery.RenderCells(bf, mode, rows, width, top, host)
  if mode == "floors" then
    return renderFloors(bf, rows, width, top, host)
  end
  bf.cells = bf.cells or {}
  local cw, ch = Scenery.CellSize(mode)
  local gap = Scenery.CELL_GAP
  local perRow = Scenery.GridShape(#rows, width, cw, ch, gap)
  for i, row in ipairs(rows) do
    local cell = bf.cells[i]
    if not cell then
      cell = newCell(bf, host)
      bf.cells[i] = cell
    end
    cell.row, cell.host = row, host
    local col, line = (i - 1) % perRow, math.floor((i - 1) / perRow)
    cell:ClearAllPoints()
    cell:SetPoint("TOPLEFT", bf, "TOPLEFT", col * (cw + gap), -(top + line * (ch + gap)))
    cell:SetSize(cw, ch)
    layoutPlaceCell(cell, row)
    cell:Show()
  end
  for i = #rows + 1, #bf.cells do
    bf.cells[i]:Hide()
    bf.cells[i].row = nil
  end
end

function Scenery.HideCells(bf)
  for _, cell in ipairs(bf.cells or {}) do
    cell:Hide()
    cell.row = nil
  end
end

-- ---------------------------------------------------------------------------------------------
-- Creatures that greet and live (modelMotion; "a random animation for
-- everything that supports it"): the greeting once when the model has loaded, then every
-- IDLE_MIN to IDLE_MAX seconds a random emote the model has, each played once before it stands
-- again; they talk while the mouse rests on them. Timers only while the model shows, a new
-- subject cancels them (golden rule 7: no OnUpdate).
-- ---------------------------------------------------------------------------------------------

Scenery.IDLE = {
  "talk",
  "exclaim",
  "question",
  "bow",
  "wave",
  "cheer",
  "dance",
  "laugh",
  "roar",
  "applaud",
  "shout",
  "flex",
  "point",
}
Scenery.IDLE_MIN, Scenery.IDLE_MAX = 6, 14 -- seconds between two emotes
Scenery.ONCE_MAX = 5 -- seconds an emote may run before the creature stands again
Scenery.random = math.random -- tests replace it

function Scenery.GreetingFor(npcID)
  local d = B:GetService("data")
  local r = d and d:Get("npc", tonumber(npcID))
  return Scenery.ANIM[Scenery.Greeting(r)]
end

-- Whether the model has an animation: false only when the client says so (unknown counts as yes).
local function supports(model, id)
  return B.Compat.HasAnimation(model, id) ~= false
end

-- A random emote the model has, not the one it played last: its name, or nil.
function Scenery.PickIdle(model, last)
  local list = {}
  for _, name in ipairs(Scenery.IDLE) do
    if name ~= last and supports(model, Scenery.ANIM[name]) then
      list[#list + 1] = name
    end
  end
  if #list == 0 then
    return nil
  end
  return list[Scenery.random(1, #list)]
end

local function stand(model)
  model.greeting = nil
  B.Compat.Animate(model, Scenery.ANIM.stand)
end

-- Plays an animation once: OnAnimFinished (or ONCE_MAX seconds) brings the stand and the next
-- emote's wait.
function Scenery.PlayOnce(model, id)
  model.greeting = id
  B.Compat.Animate(model, id)
  local token = model.motionToken
  C_Timer.After(Scenery.ONCE_MAX, function()
    if model.motionToken == token and model.greeting == id then
      stand(model)
      Scenery.QueueIdle(model)
    end
  end)
end

-- Waits for the next random emote while the model shows its creature.
function Scenery.QueueIdle(model)
  if not S.Skin("modelMotion") then
    return
  end
  model.motionToken = (model.motionToken or 0) + 1
  local token = model.motionToken
  local delay = Scenery.random(Scenery.IDLE_MIN, Scenery.IDLE_MAX)
  C_Timer.After(delay, function()
    if model.motionToken ~= token or not (model.isCreature and S.Skin("modelMotion")) then
      return
    end
    if not model:IsVisible() then
      return -- the next subject or the next show starts it again
    end
    if model.hovered then
      Scenery.QueueIdle(model) -- talking to the mouse; try again later
      return
    end
    local name = Scenery.PickIdle(model, model.lastIdle)
    if name then
      model.lastIdle = name
      Scenery.PlayOnce(model, Scenery.ANIM[name])
    end
  end)
end

-- A new subject: whatever waits for the old one is cancelled.
function Scenery.StopMotion(model)
  model.motionToken = (model.motionToken or 0) + 1
  model.greeting, model.pendingGreeting, model.hovered = nil, nil, nil
end

-- Arms a model of the stage: once on load the greeting, then the idle emotes; talk on hover.
function Scenery.Animate(model)
  if model.sceneryArmed then
    return
  end
  model.sceneryArmed = true
  model:SetScript("OnAnimFinished", function(m)
    if m.greeting then
      stand(m)
      Scenery.QueueIdle(m)
    end
  end)
  model:SetScript("OnEnter", function(m)
    if m.isCreature and S.Skin("modelMotion") then
      m.hovered, m.greeting = true, nil
      B.Compat.Animate(m, Scenery.ANIM.talk)
    end
  end)
  model:SetScript("OnLeave", function(m)
    if m.isCreature and m.hovered then
      m.hovered = nil
      stand(m)
      Scenery.QueueIdle(m)
    end
  end)
end

-- The model reported it loaded: the greeting it waits for (a random emote when the model lacks
-- it), then the idle emotes.
function Scenery.Greet(model)
  local anim = model.pendingGreeting
  model.pendingGreeting = nil
  if not (anim and S.Skin("modelMotion")) then
    return
  end
  if not supports(model, anim) then
    local name = Scenery.PickIdle(model)
    anim = name and Scenery.ANIM[name]
  end
  if anim then
    Scenery.PlayOnce(model, anim)
  else
    Scenery.QueueIdle(model)
  end
end

-- ---------------------------------------------------------------------------------------------
-- Faces in the rows of NPCs (rowPortraits): one model per creature, kept in a pool per list and
-- re-anchored while the list scrolls, so a face loads once.
-- ---------------------------------------------------------------------------------------------

local FacePool = {}
FacePool.__index = FacePool

function Scenery.FacePool(parent)
  return setmetatable({ parent = parent, byNpc = {}, models = {}, round = 0 }, FacePool)
end

-- A render starts: faces not placed until End() hide.
function FacePool:Begin()
  self.round = self.round + 1
end

-- The face of creature `npcID` on `anchor` at `size` px, or nil (no model frames, the pool full).
function FacePool:Place(npcID, anchor, size, left)
  local m = self.byNpc[npcID]
  if not m then
    if #self.models < Scenery.FACES then
      m = B.Compat.NewModel(self.parent)
      if not m then
        return nil
      end
      m:EnableMouse(false) -- the row takes the clicks
      self.models[#self.models + 1] = m
    else
      -- the face placed longest ago and not in this render
      for _, cand in ipairs(self.models) do
        if cand.faceRound ~= self.round and (not m or (cand.faceRound or 0) < (m.faceRound or 0)) then
          m = cand
        end
      end
      if not m then
        return nil
      end
      self.byNpc[m.faceNpc] = nil
    end
    m.faceNpc = npcID
    self.byNpc[npcID] = m
    m:SetSize(size, size)
    if not B.Compat.ShowCreature(m, npcID) then
      m:Hide()
      return nil
    end
    if type(m.SetPortraitZoom) == "function" then
      m:SetPortraitZoom(1)
    end
  end
  m.faceRound = self.round
  m:ClearAllPoints()
  m:SetSize(size, size)
  m:SetPoint("LEFT", anchor, "LEFT", left or 0, 0)
  m:SetFrameLevel((anchor:GetFrameLevel() or 1) + 2)
  m:Show()
  return m
end

function FacePool:End()
  for _, m in ipairs(self.models) do
    if m.faceRound ~= self.round then
      m:Hide()
    end
  end
end

function FacePool:HideAll()
  self.round = self.round + 1
  self:End()
end

-- ---------------------------------------------------------------------------------------------
-- Page sounds (pageSounds): the page turn, the quest log's sound for a quest; never two within
-- SOUND_GAP seconds.
-- ---------------------------------------------------------------------------------------------

local lastSound = -1

function Scenery.PageSound(ref)
  if not S.Skin("pageSounds") then
    return false
  end
  local now = GetTime()
  if now - lastSound < Scenery.SOUND_GAP then
    return false
  end
  local kits = rawget(_G, "SOUNDKIT")
  if type(kits) ~= "table" then
    return false
  end
  local kind = B.Entity.Parse(ref)
  local id = kind == "quest" and kits.IG_QUEST_LOG_OPEN or kits.IG_ABILITY_PAGE_TURN
  if not id then
    return false
  end
  lastSound = now
  B.Compat.PlayKit(id)
  return true
end
