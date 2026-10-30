-- UI kit: the skin's scenery (ADR 0034, core.md "The skin"): places as cuts of the zone's
-- painting, the painting behind a creature, creatures that greet, faces in the rows of NPCs, the
-- page sounds. The dossier, the stage and the tree call it; each part only while its switch
-- (S.Skin) is on. The loot grid is gone.
local _, ns = ...
local B = ns.B
local S = ns.Style

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
    local e = B:Entity(row.ref)
    S.TipLine(GameTooltip, e:Name() or row.text or row.ref, "tipText")
    local summary = e:Summary()
    if summary then
      S.TipLine(GameTooltip, summary, "tipDim")
    end
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
