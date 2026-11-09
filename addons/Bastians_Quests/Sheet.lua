-- The quest sheet (ADR 0053): one parchment page with what the game's quest window holds, the task
-- first and the rewards large, the giver and the target as figures. My quests and the map open it, a
-- quest mark of the Orbiter shows it on hover through the `questSheet` service.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Logic, State, R, V = ns.Logic, ns.State, ns.Rows, ns.Views

local Sheet = {}
ns.Sheet = Sheet

local NAME = "BastiansQuestSheet"
local WIDTH, PAD, GAP = 390, 18, 6
local TILE_H, BUTTON_H, FIGURE_H = 30, 22, 130
local FIGURE_MAX_W = 180 -- a figure is no wider, however wide the page
local RENDER_DELAY = 0.05
local HERE_YARDS = 40 -- closer than this, a direction says nothing

local HEAD_ACTIONS = { "voice.play" } -- the chain is the strip under the name
local WHERE_ACTIONS = { "map.show", "route.to" }
local FOOT_ACTIONS = { "quests.track", "quests.untrack", "quests.abandon", "browser.open" }
local CHAIN_ACTIONS = { "quests.chain.follow" }
local CTX = { source = "sheet" }

local mod, frame
local own -- the canvas of the sheet's own window (see "The drawing")
local shown -- { qid, detail, title, preview } of what the frame draws now
local pinned -- the sheet the player opened, back after a hover ends
local questOf

-- ---------------------------------------------------------------------------------------------
-- The words (pure over their arguments)
-- ---------------------------------------------------------------------------------------------

local COMPASS = { "East", "North-east", "North", "North-west", "West", "South-west", "South", "South-east" }

-- The direction of a step on a map, in map fractions: x grows east, y grows south.
function Sheet.Compass(dx, dy)
  local degrees = math.deg(math.atan2(-dy, dx)) % 360
  return COMPASS[math.floor((degrees + 22.5) / 45) % 8 + 1]
end

-- Where a place lies from the player, in a few words, or nil when one of the two is unknown.
-- from, to = { map, x, y } (map fractions); yards nil when the distance is unknown.
function Sheet.WhereWords(from, to, yards)
  if not (to and to.map) then
    return nil
  end
  if not (from and from.map) or from.map ~= to.map then
    return string.format(L["In %s"], R.zoneName(to.map))
  end
  if not (from.x and to.x) then
    return nil
  end
  if yards and yards < HERE_YARDS then
    return L["Right here"]
  end
  local direction = L[Sheet.Compass(to.x - from.x, to.y - from.y)]
  if yards then
    return string.format(L["%s, about %d yards"], direction, math.floor(yards / 10 + 0.5) * 10)
  end
  return direction
end

-- "210 XP, 3s 50c, +25 Stormwind", or nil when nothing is known.
function Sheet.RewardWords(rw)
  local parts = {}
  if rw and rw.xp and rw.xp > 0 then
    parts[#parts + 1] = rw.xp .. " " .. L["XP"]
  end
  if rw and rw.money and rw.money > 0 then
    parts[#parts + 1] = B.UI.Money(rw.money)
  end
  for _, rep in ipairs(rw and rw.rep or {}) do
    local value = rep[2] or 0
    parts[#parts + 1] = (value > 0 and "+" or "") .. value .. " " .. (R.factionName(rep[1]) or "?")
  end
  return #parts > 0 and table.concat(parts, ", ") or nil
end

local function nameOf(ref)
  return ref and B:Entity(ref):Name() or nil
end

local function creatureOf(ref)
  local typ, id = B.Entity.Parse(ref or "")
  return typ == "npc" and tonumber(id) or nil
end

-- Who the quest is about: the first creature among its objectives, the kill or the loot's source.
function Sheet.TargetOf(q)
  for _, o in ipairs(q and q.objectives or {}) do
    local id = creatureOf(o[2]) or creatureOf(o[4])
    if id then
      return id, nameOf("npc:" .. id)
    end
  end
  return nil
end

-- The task and the story: the client's for a log quest, the pack's, what the giver shows now.
local function texts_of(qid, detail)
  local story, task
  if State.log[qid] then
    story, task = B.Compat.GetQuestText(qid)
  end
  local d = B:GetService("data")
  local t = d and d:PackLoaded("text") and d:Get("questText", qid) or nil
  story = story or (t and t.details) or (detail and detail.text)
  task = task or (t and t.objectives) or (detail and detail.objectives)
  if task == "" then
    task = nil
  end
  return task, story
end

-- A quest's place in its chain, for the strip under its name (quests.md "On a quest, on a zone,
-- in the list"): { root, name, words ("Step 2 of 3"), step (nil off the main line), kinds = the
-- state of every main step (Sheet.StepState), done, prev, next (quest ids, nil at an end) with
-- prevStep and nextStep }. A side quest's `prev` is the main step it hangs under. Nil outside a
-- chain.
function Sheet.Strip(qid, state)
  local place = Logic.chainPlace(qid, state)
  local c = place and Logic.chainSheet(place.root, state)
  if not c then
    return nil
  end
  local strip = {
    root = place.root,
    name = ns.Chains.Name(c),
    step = place.step,
    done = c.done,
    kinds = {},
  }
  for i = 1, #c.main do
    strip.kinds[i] = Sheet.StepState(c, i, state)
  end
  if place.step then
    strip.words = string.format(L["Step %d of %d"], place.step, #c.main)
    if place.step > 1 then
      strip.prev, strip.prevStep = c.main[place.step - 1], place.step - 1
    end
    if place.step < #c.main then
      strip.next, strip.nextStep = c.main[place.step + 1], place.step + 1
    end
  elseif place.after > 0 then
    strip.words = string.format(L["Side quest after step %d of %d"], place.after, #c.main)
    strip.prev, strip.prevStep = c.main[place.after], place.after
  else
    strip.words = L["Another way into the chain"]
  end
  return strip
end

-- Everything the sheet draws of a quest. opts = { detail = { text, objectives } }, what the giver's
-- window says of a quest that is not in the log yet.
function Sheet.Model(qid, opts)
  opts = opts or {}
  local q = Logic.quest(qid)
  local e = State.log[qid]
  local state = State.ForLogic()
  local task, story = texts_of(qid, opts.detail)
  local giver = q and q.starts and nameOf(q.starts[1]) or nil
  local start = q and Logic.startMap(q)
  local target, targetName = Sheet.TargetOf(q)
  local model = {
    qid = qid,
    title = (e and e.title) or R.questName(qid, opts.title),
    level = (e and e.level) or (q and q.level),
    giver = giver,
    giverID = q and q.starts and creatureOf(q.starts[1]) or nil,
    target = target,
    targetName = targetName,
    zone = start and R.zoneName(start) or nil,
    task = task,
    story = story,
    rewards = Logic.rewards(qid),
    ready = e ~= nil and e.isComplete == true,
    inLog = e ~= nil,
    objectives = {},
  }
  model.strip = q and Sheet.Strip(qid, state) or nil
  for _, o in ipairs(e and e.objectives or {}) do
    model.objectives[#model.objectives + 1] = {
      text = R.objectiveLabel(o),
      have = o.fulfilled,
      need = o.required,
      done = o.finished == true,
    }
  end
  if e then
    local map, px, py = ns.Window.PlayerPlace()
    local place = V.PlaceOf(e, q, map, px, py)
    local yards = place.x and px and ns.Window.Yards(map, px, py, place.map, place.x, place.y) or nil
    local where = Sheet.WhereWords({ map = map, x = px, y = py }, place, yards)
    model.where = where
    if model.ready then
      model.handIn = R.handInWords(q, map)
    end
  end
  return model
end

-- ---------------------------------------------------------------------------------------------
-- The frame
-- ---------------------------------------------------------------------------------------------

local function savedPlace()
  local p = mod.db.profile
  p.sheet = p.sheet or {}
  return p.sheet
end

-- The side of `anchor` a preview opens on: "LEFT" when the anchor's middle is in the right
-- half of the screen, else "RIGHT" (the Orbiter can stand anywhere,
-- so the sheet may not always open to its right). Both in screen pixels; pure.
function Sheet.Side(anchorX, screenWidth)
  if anchorX and screenWidth and anchorX > screenWidth / 2 then
    return "LEFT"
  end
  return "RIGHT"
end

local function place(anchor, side)
  frame:ClearAllPoints()
  if anchor then
    if side ~= "LEFT" and side ~= "RIGHT" then -- the caller did not say: by the anchor's place
      local cx = anchor:GetCenter()
      side = Sheet.Side(
        cx and cx * (anchor:GetEffectiveScale() or 1),
        UIParent:GetWidth() * (UIParent:GetEffectiveScale() or 1)
      )
    end
    if side == "LEFT" then
      frame:SetPoint("RIGHT", anchor, "LEFT", -12, 0)
    else
      frame:SetPoint("LEFT", anchor, "RIGHT", 12, 0)
    end
    return
  end
  local pos = savedPlace().pos
  if pos then
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos[1], pos[2])
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", -180, 40)
  end
end

local function build()
  frame = CreateFrame("Frame", NAME, UIParent)
  frame:SetSize(WIDTH, 300)
  -- the suite's windows' strata (Window.STRATA): over the Browser it is hovered from (owner,
  -- Forever 07.11.2026: "the details for each quest open behind the browser window")
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:SetClampedToScreen(true)
  frame:SetToplevel(true)
  frame:Hide()
  local paper = frame:CreateTexture(nil, "BACKGROUND")
  paper:SetTexture(S.PARCHMENT, "REPEAT", "REPEAT")
  paper:SetHorizTile(true)
  paper:SetVertTile(true)
  paper:SetAllPoints()
  S.border(frame, S.C.sheetTitle)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self)
    if not (shown and shown.preview) then
      self:StartMoving()
    end
  end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    savedPlace().pos = { self:GetLeft(), self:GetTop() }
  end)
  frame:SetScript("OnHide", function()
    shown, pinned = nil, nil
  end)
  frame.close = S.action(frame, {
    icon = "never",
    only = true,
    label = L["Close"],
    boxed = true,
    onClick = function()
      frame:Hide()
    end,
  })
  frame.close:SetPoint("TOPRIGHT", -6, -6)
  table.insert(UISpecialFrames, NAME) -- Esc closes it, as the game's quest window
  Sheet.frame = frame
end

function questOf(ref)
  local typ, id = B.Entity.Parse(ref)
  return typ == "quest" and id or nil
end

-- ---------------------------------------------------------------------------------------------
-- The drawing (ADR 0056: one quest sheet). The sheet is drawn onto a canvas: its own window, or
-- a frame a host gives (the Browser's page tile, through Bastians:RegisterSheet). A canvas keeps
-- its pooled parts and its colours; `C` is the one being drawn, `y` the next free line.
-- ---------------------------------------------------------------------------------------------

-- the sheet's own paper, the same in every theme
local OWN = {
  ink = "sheetInk",
  dim = "sheetDim",
  title = "sheetTitle",
  good = "sheetGood",
  tile = "sheetTile",
  tileText = "sheetTileText",
  xp = "sheetXp",
  -- a chain's steps by their state
  done = "sheetGood",
  now = "sheetTitle",
  take = "sheetXp",
  later = "sheetTile",
}
-- on a host's page the colours are the page's own (its palette: the paper's or the theme's)
local HOSTED = {
  ink = "text",
  dim = "dim",
  title = "accent",
  good = "good",
  tile = "card",
  tileText = "text",
  xp = "rare",
  done = "good",
  now = "accent",
  take = "svcQuest",
  later = "card",
}
local HOSTED_MIN, HOSTED_MAX = 260, 640 -- a hosted sheet's width: a line stays readable

local function newCanvas(parent, colours)
  return {
    frame = parent,
    width = WIDTH,
    colours = colours,
    ctx = CTX,
    texts = {},
    tiles = {},
    figures = {},
    buttons = {},
    steps = {}, -- a chain's step tiles
    arrows = {}, -- and the arrows between them
    dots = {}, -- the strip of a quest in a chain: a dot per step
    links = {}, -- and its words to click, by key
    used = {},
  }
end

local C
local y, left

local function col(name)
  return S.C[C.colours[name or "ink"]]
end

local function nextText()
  local used = C.used
  used.text = used.text + 1
  local fs = C.texts[used.text]
  if not fs then
    fs = S.text(C.frame, 13, col("ink"))
    fs:SetShadowOffset(0, 0) -- ink has no shadow
    fs:SetWordWrap(true)
    C.texts[used.text] = fs
  end
  return fs
end

-- A text across the page. opts = { size, color (a name of the canvas' colours), serif, indent, gap }.
local function line(text, opts)
  opts = opts or {}
  local fs = nextText()
  local size = S.size(opts.size or 13)
  S.fonts[fs] = nil -- the font is the sheet's, a font switch leaves it
  fs:SetFont(opts.serif and S.SERIF_FONT or S.font(), size, "")
  S.ink(fs, col(opts.color))
  fs:SetWidth(C.width - 2 * PAD - (opts.indent or 0) - (opts.right or 0))
  fs:ClearAllPoints()
  fs:SetPoint("TOPLEFT", C.frame, "TOPLEFT", PAD + (opts.indent or 0), -y)
  fs:SetText(text)
  fs:Show()
  y = y + (fs:GetStringHeight() or size) + (opts.gap or GAP)
  return fs
end

local function heading(text)
  y = y + 4
  line(text, { size = 15, serif = true, color = "title", gap = 3 })
end

-- The giver and the target as 3D figures, side by side; a slot without a creature stays out.
local function figure(i, creature, caption, width, x)
  local f = C.figures[i]
  if not f then
    f = CreateFrame("Frame", nil, C.frame)
    f.face = S.fill(f, col("tile"), "BACKGROUND")
    f.model = CreateFrame("PlayerModel", nil, f)
    f.model:SetPoint("TOPLEFT", 2, -2)
    f.model:SetPoint("BOTTOMRIGHT", -2, 18)
    f.caption = S.text(f, 11, col("tileText"))
    f.caption:SetPoint("BOTTOMLEFT", 4, 3)
    f.caption:SetPoint("BOTTOMRIGHT", -4, 3)
    f.caption:SetJustifyH("CENTER")
    f.caption:SetWordWrap(false)
    C.figures[i] = f
  end
  S.tint(f.face, col("tile"))
  S.ink(f.caption, col("tileText"))
  f:SetSize(width, FIGURE_H)
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", C.frame, "TOPLEFT", x, -y)
  f.caption:SetText(caption)
  if f.creature ~= creature then -- the same creature keeps its model: no flicker on a render
    f.model:SetCreature(creature)
    f.creature = creature
  end
  f:Show()
end

local giverRoute -- the button under the figures, set where the buttons are defined

local function drawFigures(m)
  local list = {}
  if m.giverID then
    list[#list + 1] = { m.giverID, L["Given by"] .. ": " .. (m.giver or "?") }
  end
  if m.target and m.target ~= m.giverID then
    list[#list + 1] = { m.target, L["Target"] .. ": " .. (m.targetName or "?") }
  end
  C.used.figure = #list
  if #list == 0 then
    return
  end
  -- on a wide page a figure keeps a figure's width: two side by side, not two bands
  local width = math.min(FIGURE_MAX_W, (C.width - 2 * PAD - (#list - 1) * GAP) / #list)
  for i, one in ipairs(list) do
    figure(i, one[1], one[2], width, PAD + (i - 1) * (width + GAP))
  end
  y = y + FIGURE_H + GAP
  giverRoute(m)
end

local function nextTile()
  local used = C.used
  used.tile = used.tile + 1
  local t = C.tiles[used.tile]
  if not t then
    t = CreateFrame("Button", nil, C.frame)
    t.face = S.fill(t, col("tile"), "BACKGROUND")
    t.badge = S.fill(t, col("xp"), "BORDER")
    t.badge:ClearAllPoints()
    t.badge:SetPoint("LEFT", 3, 0)
    t.badge:SetSize(TILE_H - 6, TILE_H - 6)
    t.badgeText = S.text(t, 11, S.InkOn(col("xp")))
    t.badgeText:SetPoint("CENTER", t.badge, "CENTER", 0, 0)
    t.icon = t:CreateTexture(nil, "ARTWORK")
    t.icon:SetPoint("LEFT", 3, 0)
    t.icon:SetSize(TILE_H - 6, TILE_H - 6)
    t.label = S.text(t, 14, col("tileText"))
    t.label:SetPoint("LEFT", TILE_H + 2, 0)
    t:SetScript("OnEnter", function(self)
      if self.itemID and GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetItemByID then
          GameTooltip:SetItemByID(self.itemID)
        end
        GameTooltip:Show()
      end
    end)
    t:SetScript("OnLeave", function()
      if GameTooltip then
        GameTooltip:Hide()
      end
    end)
    C.tiles[used.tile] = t
  end
  -- a pooled tile takes the canvas' colours of this draw (a host's page may change its paper)
  S.tint(t.face, col("tile"))
  S.tint(t.badge, col("xp"))
  S.ink(t.badgeText, S.InkOn(col("xp")))
  S.ink(t.label, col("tileText"))
  return t
end

-- One reward. spec = { badge, icon, text, itemID }; laid out left to right, wrapping.
local function tile(spec)
  local t = nextTile()
  t.itemID = spec.itemID
  if spec.icon then
    t.icon:SetTexture(spec.icon)
    t.icon:Show()
    t.badge:Hide()
    t.badgeText:Hide()
  else
    t.icon:Hide()
    t.badge:Show()
    t.badgeText:SetText(spec.badge or "")
    t.badgeText:Show()
  end
  t.label:SetText(spec.text)
  local w = TILE_H + 10 + (t.label:GetStringWidth() or #spec.text * 7)
  if left > PAD and left + w > C.width - PAD then
    left, y = PAD, y + TILE_H + 4
  end
  t:SetSize(w, TILE_H)
  t:ClearAllPoints()
  t:SetPoint("TOPLEFT", C.frame, "TOPLEFT", left, -y)
  t:EnableMouse(spec.itemID ~= nil)
  t:Show()
  left = left + w + 5
end

local function itemTiles(list)
  for _, it in ipairs(list or {}) do
    local ref = "item:" .. it[1]
    local name = nameOf(ref) or (L["Item"] .. " " .. it[1])
    tile({
      icon = B:Entity(ref):Icon(),
      text = name .. ((it[2] or 1) > 1 and (" x" .. it[2]) or ""),
      itemID = it[1],
    })
  end
end

local function rewards(rw)
  if not rw then
    line(L["The giver tells you the rewards when you speak to them."], { color = "dim" })
    return
  end
  left = PAD
  local any = false
  if rw.xp and rw.xp > 0 then
    tile({ badge = L["XP"], text = tostring(rw.xp) })
    any = true
  end
  if rw.money and rw.money > 0 then
    tile({ icon = B.UI.IconTexture("gold"), text = B.UI.Money(rw.money) })
    any = true
  end
  for _, rep in ipairs(rw.rep or {}) do
    local value = rep[2] or 0
    tile({
      icon = B.UI.IconTexture("banker"),
      text = (value > 0 and "+" or "") .. value .. " " .. (R.factionName(rep[1]) or "?"),
    })
    any = true
  end
  itemTiles(rw.items)
  any = any or #(rw.items or {}) > 0
  if any then
    y = y + TILE_H + GAP
  end
  if rw.choices and #rw.choices > 0 then
    line(L["Choose one:"], { size = 12, color = "dim", gap = 3 })
    left = PAD
    itemTiles(rw.choices)
    y = y + TILE_H + GAP
  end
end

-- The registered actions among `ids` that apply to the quest now, in that order.
local function actionsOf(ref, ids)
  local out = {}
  local all = B:GetActions(ref, C.ctx)
  for _, id in ipairs(ids) do
    for _, def in ipairs(all) do
      if def.id == id then
        out[#out + 1] = def
      end
    end
  end
  return out
end

local function nextButton(key)
  local b = C.buttons[key]
  if not b then
    b = S.action(C.frame, { label = "", boxed = true, row = true })
    b:SetScript("OnClick", function(self)
      if self.run then
        self.run(self)
      end
    end)
    C.buttons[key] = b
  end
  C.used.buttons[key] = true
  return b
end

-- A row of buttons: { key, label, icon, run }. Nothing on a hover: the mouse cannot reach them.
local function buttonRow(list)
  if #list == 0 or C.preview then
    return
  end
  local x = PAD
  for _, spec in ipairs(list) do
    local b = nextButton(spec.key)
    b.spec.label = spec.label
    b.spec.icon = spec.icon
    b.tip = spec.tip
    b.run = spec.run
    if b.SetLabel then
      b:SetLabel(spec.label)
    end
    if b.Fit then
      b:Fit()
    end
    local w = b:GetWidth() or 60
    if x > PAD and x + w > C.width - PAD then
      x, y = PAD, y + BUTTON_H + 3
    end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", C.frame, "TOPLEFT", x, -y)
    b:Show()
    x = x + w + 5
  end
  y = y + BUTTON_H + GAP
end

local function actionButtons(ref, ids)
  local list = {}
  local ctx = C.ctx
  for _, def in ipairs(actionsOf(ref, ids)) do
    local active = def.active and def.active(ref) or false
    list[#list + 1] = {
      key = def.id,
      label = (active and def.activeShort) or def.short or def.label,
      tip = def.label,
      run = function()
        B:RunAction(def.id, ref, ctx)
        Sheet.Schedule()
      end,
    }
  end
  return list
end

-- The way to the one who gives the quest: under the figures, while Route
-- is there. The other Route to on the sheet goes to the objective.
giverRoute = function(m)
  if not m.giverID then
    return
  end
  local ref, ctx = "npc:" .. m.giverID, C.ctx
  local def = actionsOf(ref, { "route.to" })[1]
  if def then
    buttonRow({
      {
        key = "route.giver",
        label = L["Route to the giver"],
        tip = def.label,
        run = function()
          B:RunAction(def.id, ref, ctx)
          Sheet.Schedule()
        end,
      },
    })
  end
end

-- ---------------------------------------------------------------------------------------------
-- The strip of a quest in a chain (ADR 0055): under the name, how far the chain is as dots (a
-- bar beyond twelve steps), the step and the chain's name (a click opens the chain), then the
-- step before and the step after (a click opens that quest).
-- ---------------------------------------------------------------------------------------------

local DOT, DOT_HERE, DOT_GAP, DOTS_MAX, BAR_W = 7, 11, 3, 12, 96
local STRIP_H = 16
local DOT_COLOUR = { done = "good", now = "title", take = "dim", later = "dim" }

local function nextDot()
  local used = C.used
  used.dot = used.dot + 1
  local d = C.dots[used.dot]
  if not d then
    d = C.frame:CreateTexture(nil, "ARTWORK")
    C.dots[used.dot] = d
  end
  return d
end

-- Words to click. spec = { size, color, tip, run }; on a hover the mouse cannot reach them.
-- Returns the width they took.
local function link(key, text, x, top, room, spec)
  local b = C.links[key]
  if not b then
    local canvas = C
    b = CreateFrame("Button", nil, C.frame)
    b.text = S.text(b, 12, col("ink"))
    b.text:SetShadowOffset(0, 0)
    b.text:SetPoint("LEFT", 0, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    b:SetScript("OnEnter", function(self)
      S.ink(self.text, S.C[canvas.colours.title])
      S.TipEnter(self)
    end)
    b:SetScript("OnLeave", function(self)
      S.ink(self.text, S.C[canvas.colours[self.color]])
      S.TipLeave(self)
    end)
    b:SetScript("OnClick", function(self)
      if self.run then
        self.run()
      end
    end)
    C.links[key] = b
  end
  C.used.links[key] = true
  S.fonts[b.text] = nil -- the font is the sheet's, a font switch leaves it
  b.text:SetFont(S.font(), S.size(spec.size or 12), "")
  b.color = spec.color or "ink"
  S.ink(b.text, col(b.color))
  b.text:SetWidth(0)
  b.text:SetText(text)
  local width = math.min(b.text:GetStringWidth() or (#text * 6), room)
  b.text:SetWidth(width)
  b.tip, b.run = spec.tip, spec.run
  b:SetSize(width, STRIP_H)
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", C.frame, "TOPLEFT", x, -top)
  b:EnableMouse(not C.preview)
  b:Show()
  return width
end

local function stripBar(x, width, colour)
  local bar = nextDot()
  bar:SetTexture(S.WHITE)
  S.tint(bar, col(colour))
  bar:SetSize(math.max(1, width), 4)
  bar:ClearAllPoints()
  bar:SetPoint("LEFT", C.frame, "TOPLEFT", x, -(y + STRIP_H / 2))
  bar:Show()
end

local function drawStrip(m)
  local strip = m.strip
  local canvas = C
  local ref = "quest:" .. m.qid
  local x = PAD
  local steps = #strip.kinds
  if steps <= DOTS_MAX then
    for i, kind in ipairs(strip.kinds) do
      local d = nextDot()
      local size = i == strip.step and DOT_HERE or DOT -- the quest of this sheet stands out
      d:SetTexture(S.DISC)
      S.tint(d, col(DOT_COLOUR[kind]))
      d:SetSize(size, size)
      d:ClearAllPoints()
      d:SetPoint("CENTER", C.frame, "TOPLEFT", x + size / 2, -(y + STRIP_H / 2))
      d:Show()
      x = x + size + DOT_GAP
    end
  else
    stripBar(x, BAR_W, "dim")
    if strip.done > 0 then
      stripBar(x, BAR_W * strip.done / steps, "good")
    end
    x = x + BAR_W + DOT_GAP
  end
  x = x + 5
  link("strip.chain", strip.words .. " - " .. strip.name, x, y, C.width - PAD - x, {
    size = 13,
    color = "title",
    tip = L["Show the quest chain"],
    run = function()
      Sheet.EndPreview()
      if canvas.open then
        canvas.open("chain:" .. strip.root)
      else
        B:RunAction("quests.chain", ref, canvas.ctx)
      end
    end,
  })
  y = y + STRIP_H + 1
  if not (strip.prev or strip.next) then
    y = y + GAP - 1
    return
  end
  -- the step before at the left, the step after behind it (under it when the page is narrow)
  x = PAD
  local function step(key, qid, text, tip)
    if x > PAD and x + 80 > C.width - PAD then
      x, y = PAD, y + STRIP_H
    end
    local width = link(key, text, x, y, C.width - PAD - x, {
      size = 12,
      color = "dim",
      tip = tip,
      run = function()
        if canvas.open then
          canvas.open("quest:" .. qid)
        else
          Sheet.Open(qid)
        end
      end,
    })
    x = x + width + 14
  end
  if strip.prev then
    step(
      "strip.prev",
      strip.prev,
      "< " .. strip.prevStep .. ". " .. R.questName(strip.prev),
      L["The step before"]
    )
  end
  if strip.next then
    step(
      "strip.next",
      strip.next,
      strip.nextStep .. ". " .. R.questName(strip.next) .. " >",
      L["The step after"]
    )
  end
  y = y + STRIP_H + GAP
end

local function drawQuest(m)
  local ref = "quest:" .. m.qid
  line(m.title, { size = 20, serif = true, color = "title", right = 30, gap = 2 })
  local sub = {}
  if m.giver and not m.giverID then
    sub[#sub + 1] = m.giver
  end
  if m.zone then
    sub[#sub + 1] = m.zone
  end
  if m.level then
    sub[#sub + 1] = L["Level"] .. " " .. m.level
  end
  if #sub > 0 then
    line(table.concat(sub, " - "), { size = 12, color = "dim" })
  end
  if m.strip then
    drawStrip(m)
  end
  drawFigures(m)
  buttonRow(actionButtons(ref, HEAD_ACTIONS))
  if m.ready then
    line(L["Done."] .. (m.handIn and (" " .. m.handIn) or ""), { size = 14, color = "good" })
  end
  heading(L["What to do"])
  if m.task then
    line(table.concat(R.paragraphs(m.task), " "), { size = 14 })
  elseif #m.objectives == 0 then
    line(L["The giver tells you when you speak to them."], { color = "dim" })
  end
  for _, o in ipairs(m.objectives) do
    local count = (o.need and o.need > 0) and ((o.have or 0) .. "/" .. o.need .. " ") or ""
    line(count .. o.text, { color = o.done and "good" or "ink", indent = 8, gap = 2 })
  end
  if m.where then
    y = y + 3
    line(m.where, { size = 13 })
  end
  buttonRow(actionButtons(ref, WHERE_ACTIONS))
  local story = R.paragraphs(m.story)
  if #story > 0 then
    heading(L["The story"])
    for _, p in ipairs(story) do
      line(p)
    end
  end
  heading(m.ready and L["You receive"] or L["You will receive"])
  rewards(m.rewards)
  -- the foot: the quest's own buttons, then the host's (a page's Bookmark and More)
  local foot = actionButtons(ref, FOOT_ACTIONS)
  for _, spec in ipairs(C.extra or {}) do
    foot[#foot + 1] = spec
  end
  buttonRow(foot)
end

-- ---------------------------------------------------------------------------------------------
-- The chain's sheet (ADR 0056: "colored tiles with arrows between them, and clicking or hovering
-- on them shows our standard new quest window"): the name, where the character is, then the way
-- as step tiles in the colour of their state, joined by arrows and flowing into rows.
-- ---------------------------------------------------------------------------------------------

local STEP_W, STEP_H, ARROW_W = 156, 40, 18

-- A step's state on the way: "done", "now" (where the player is on a chain they are on),
-- "take" (can be taken now: also the first step of a chain not begun), "later".
function Sheet.StepState(c, i, state)
  local status = Logic.status(c.main[i], state)
  if status == "done" then
    return "done"
  elseif c.now == i and c.state == "on" then
    return "now"
  elseif status == "available" or status == "log" then
    return "take"
  end
  return "later"
end

local STEP_WORDS = { done = "Done", now = "You are here", take = "You can take it now" }
local DASH, DASH_GAP = 8, 5

-- The outline of a tile without a face, as dashes along its edges (ADR 0056: a step the
-- character cannot take is dashed). `on` false takes them away.
local function dashes(t, on, colour)
  local pool = t.dashes or {}
  t.dashes = pool
  local n = 0
  local function dash(point, x, top, w, h)
    n = n + 1
    local d = pool[n]
    if not d then
      d = S.fill(t, colour, "BORDER")
      pool[n] = d
    end
    S.tint(d, colour)
    d:ClearAllPoints()
    d:SetPoint(point, t, point, x, top)
    d:SetSize(w, h)
    d:Show()
  end
  if on then
    local x = 0
    while x < STEP_W do
      local w = math.min(DASH, STEP_W - x)
      dash("TOPLEFT", x, 0, w, 1)
      dash("BOTTOMLEFT", x, 0, w, 1)
      x = x + DASH + DASH_GAP
    end
    local down = 0
    while down < STEP_H do
      local h = math.min(DASH, STEP_H - down)
      dash("TOPLEFT", 0, -down, 1, h)
      dash("TOPRIGHT", 0, -down, 1, h)
      down = down + DASH + DASH_GAP
    end
  end
  for i = n + 1, #pool do
    pool[i]:Hide()
  end
end

local function stepTile()
  local used = C.used
  used.step = used.step + 1
  local t = C.steps[used.step]
  if not t then
    local canvas = C
    t = CreateFrame("Button", nil, C.frame)
    t.face = S.roundFill(t, col("later"), "radiusSmall")
    t.name = S.text(t, 12, col("tileText"))
    t.name:SetPoint("TOPLEFT", 7, -5)
    t.name:SetPoint("TOPRIGHT", -7, -5)
    t.name:SetJustifyH("LEFT")
    t.name:SetWordWrap(false)
    t.sub = S.text(t, 11, col("tileText"))
    t.sub:SetPoint("BOTTOMLEFT", 7, 5)
    t.sub:SetPoint("BOTTOMRIGHT", -7, 5)
    t.sub:SetJustifyH("LEFT")
    t.sub:SetWordWrap(false)
    -- the mouse on a step shows its quest sheet, a click opens it (ADR 0056)
    t:SetScript("OnEnter", function(self)
      if self.qid and not canvas.preview then
        Sheet.Preview(self.qid, { anchor = self })
      end
    end)
    t:SetScript("OnLeave", function()
      Sheet.EndPreview()
    end)
    t:SetScript("OnClick", function(self)
      if self.qid and canvas.open then
        Sheet.EndPreview()
        canvas.open("quest:" .. self.qid)
      end
    end)
    C.steps[used.step] = t
  end
  return t
end

-- One tile of the way at (x, top). spec = { qid, step (its number on the main line, nil off
-- it), kind (the state: its colour), name, words (the second line), why (the character cannot
-- take it: no face, a dashed outline, dim words) }.
local function placeStep(x, top, spec)
  local t = stepTile()
  local ink
  if spec.why then
    t.face:Hide()
    dashes(t, true, col("dim"))
    ink = col("dim")
  else
    local ground = col(spec.kind)
    S.tint(t.face, ground)
    dashes(t, false)
    ink = spec.kind == "later" and col("tileText") or S.InkOn(ground)
  end
  S.ink(t.name, ink)
  S.ink(t.sub, ink)
  t.qid, t.step, t.kind, t.why = spec.qid, spec.step, spec.kind, spec.why
  t.name:SetText(spec.name)
  t.sub:SetText(table.concat(spec.words, " - "))
  t:SetSize(STEP_W, STEP_H)
  t:ClearAllPoints()
  t:SetPoint("TOPLEFT", C.frame, "TOPLEFT", x, -top)
  if not spec.why then
    t.face:Show() -- lays the corners out
  end
  t:Show()
  return t
end

local function arrow(x, top)
  local used = C.used
  used.arrow = used.arrow + 1
  local fs = C.arrows[used.arrow]
  if not fs then
    fs = S.text(C.frame, 14, col("dim"))
    fs:SetShadowOffset(0, 0)
    C.arrows[used.arrow] = fs
  end
  S.ink(fs, col("dim"))
  fs:SetText(">")
  fs:ClearAllPoints()
  fs:SetPoint("TOPLEFT", C.frame, "TOPLEFT", x + 5, -(top + STEP_H / 2 - 7))
  fs:Show()
end

local WHY_WORDS = { race = "for another race", class = "for another class" }

-- What hangs on the way (quests.md "The chain's sheet"): the side quests and the quests of
-- other races and classes, by the main step they hang under. Returns under = { [step] = { spec } }
-- and entry = { spec } for the other ways into the chain (under no step).
function Sheet.Hanging(c, state)
  local under, entry = {}, {}
  local function add(list, cannot)
    for _, h in ipairs(list) do
      local q = Logic.quest(h.id)
      local status = Logic.status(h.id, state)
      local kind = (status == "done" and "done")
        or (status == "log" and "now")
        or (status == "available" and "take")
        or "later"
      local words = {}
      if q and q.level and q.level > 0 then
        words[#words + 1] = L["Level"] .. " " .. q.level
      end
      local why = cannot and (h.why or "race") or nil
      if why then
        words[#words + 1] = L[WHY_WORDS[why]]
      elseif kind == "now" then
        words[#words + 1] = L["In your log"]
      elseif STEP_WORDS[kind] then
        words[#words + 1] = L[STEP_WORDS[kind]]
      end
      local spec = { qid = h.id, kind = kind, name = R.questName(h.id), words = words, why = why }
      if h.after > 0 then
        under[h.after] = under[h.after] or {}
        table.insert(under[h.after], spec)
      else
        entry[#entry + 1] = spec
      end
    end
  end
  add(c.side, false)
  add(c.others, true)
  return under, entry
end

-- The way: one tile per main step, left to right, wrapping; an arrow leads from each to the
-- next. Under a step hang its side quests and what other races and classes take there; the other
-- ways into the chain stand in a row of their own before it.
local function stepTiles(c)
  local state = State.ForLogic()
  local under, entry = Sheet.Hanging(c, state)
  if #entry > 0 then
    line(L["Another way into the chain"], { size = 12, color = "dim", gap = 3 })
    local x = PAD
    for _, spec in ipairs(entry) do
      if x > PAD and x + STEP_W > C.width - PAD then
        x, y = PAD, y + STEP_H + GAP
      end
      placeStep(x, y, spec)
      x = x + STEP_W + ARROW_W
    end
    y = y + STEP_H + GAP + 2
  end
  local x = PAD
  local deep = 0 -- the tallest column of hanging tiles in this row
  for i, id in ipairs(c.main) do
    if x > PAD and x + STEP_W > C.width - PAD then
      x, y, deep = PAD, y + STEP_H + deep + GAP, 0
    end
    local kind = Sheet.StepState(c, i, state)
    local q = Logic.quest(id)
    local words = {}
    if q and q.level then
      words[#words + 1] = L["Level"] .. " " .. q.level
    end
    local e = State.log[id]
    if kind == "now" and e and e.isComplete then
      words[#words + 1] = L["You are here: hand it in"]
    elseif kind == "now" and not e then
      words[#words + 1] = L["You can take it now"] -- the next step, not in the log yet
    elseif STEP_WORDS[kind] then
      words[#words + 1] = L[STEP_WORDS[kind]]
    end
    placeStep(x, y, { qid = id, step = i, kind = kind, name = i .. ". " .. R.questName(id), words = words })
    local down = STEP_H
    for _, spec in ipairs(under[i] or {}) do
      placeStep(x, y + down + 3, spec)
      down = down + STEP_H + 3
    end
    deep = math.max(deep, down - STEP_H)
    x = x + STEP_W
    if i < #c.main then
      arrow(x, y)
      x = x + ARROW_W
    end
  end
  y = y + STEP_H + deep + GAP
end

-- Where the character is on a chain, in one sentence.
function Sheet.ChainWords(c)
  if c.state == "finished" then
    return string.format(L["Finished: all %d steps are done."], #c.main)
  elseif c.state == "on" and c.now then
    return string.format(L["You are on step %d of %d: %s."], c.now, #c.main, R.questName(c.main[c.now]))
  elseif c.now then
    return string.format(L["Not started. It begins with %s."], R.questName(c.main[c.now]))
  end
  return L["Not open to you yet."]
end

local function drawChain(c)
  line(ns.Chains.Name(c), { size = 20, serif = true, color = "title", right = 30, gap = 2 })
  local sub = { ns.Chains.Summary(c) }
  for _, map in ipairs(c.zones) do
    sub[#sub + 1] = R.zoneName(map)
  end
  line(table.concat(sub, " - "), { size = 12, color = "dim" })
  line(Sheet.ChainWords(c), { size = 14, color = c.state == "finished" and "good" or "ink" })
  local ahead = c.state ~= "finished" and Sheet.RewardWords(c.ahead) or nil
  if ahead then
    line(string.format(L["Still ahead: %s."], ahead), { size = 12, color = "dim" })
  end
  heading(L["The way"])
  stepTiles(c)
  -- the chain's own button (Follow), then the host's (a page's Bookmark and More)
  local foot = actionButtons("chain:" .. c.id, CHAIN_ACTIONS)
  for _, spec in ipairs(C.extra or {}) do
    foot[#foot + 1] = spec
  end
  buttonRow(foot)
end

-- Draws `what` ({ qid, detail, title, preview } for a quest, { chain = the model } for a chain)
-- onto a canvas; returns the height it took.
local function draw(canvas, what)
  local before = C
  C = canvas
  canvas.preview = what.preview or nil
  y, left = PAD, PAD
  local used = canvas.used
  used.text, used.tile, used.figure, used.buttons = 0, 0, 0, {}
  used.step, used.arrow, used.dot, used.links = 0, 0, 0, {}
  if what.chain then
    drawChain(what.chain)
  else
    drawQuest(Sheet.Model(what.qid, { detail = what.detail, title = what.title }))
  end
  for i = used.step + 1, #canvas.steps do
    canvas.steps[i]:Hide()
  end
  for i = used.arrow + 1, #canvas.arrows do
    canvas.arrows[i]:Hide()
  end
  for i = used.dot + 1, #canvas.dots do
    canvas.dots[i]:Hide()
  end
  for key, b in pairs(canvas.links) do
    if not used.links[key] then
      b:Hide()
    end
  end
  for i = used.text + 1, #canvas.texts do
    canvas.texts[i]:Hide()
  end
  for i = used.tile + 1, #canvas.tiles do
    canvas.tiles[i]:Hide()
  end
  for i = used.figure + 1, #canvas.figures do
    canvas.figures[i]:Hide()
  end
  for key, b in pairs(canvas.buttons) do
    if not used.buttons[key] then
      b:Hide()
    end
  end
  C = before
  return y + PAD - GAP
end

-- Draws what `shown` says into the sheet's own window.
function Sheet.Render()
  if not (frame and shown) then
    return
  end
  local height = draw(own, shown)
  frame.close:SetShown(not shown.preview)
  frame:EnableMouse(not shown.preview)
  frame:SetHeight(height)
end

-- The quest of `ref` drawn into a host's frame (ADR 0056: one quest sheet; the Browser's page
-- tile through Bastians:RegisterSheet). host = { frame, width, ctx, buttons = { { key, label,
-- tip, run } }, refresh = fn (the host draws again) }. In the host's own colours: the call runs
-- inside the page's palette. Returns the height it took, 0 for no quest.
local hosted = {} -- host frame -> canvas

function Sheet.DrawInto(ref, host)
  local qid = questOf(ref)
  if not (qid and host and host.frame) then
    return 0
  end
  local canvas = hosted[host.frame]
  if not canvas then
    local page = CreateFrame("Frame", nil, host.frame)
    page:SetPoint("TOPLEFT", host.frame, "TOPLEFT", 0, 0)
    canvas = newCanvas(page, HOSTED)
    hosted[host.frame] = canvas
  end
  canvas.width = math.max(HOSTED_MIN, math.min(host.width or WIDTH, HOSTED_MAX))
  canvas.ctx = host.ctx or CTX
  canvas.extra = host.buttons
  canvas.refresh = host.refresh
  canvas.open = host.open
  canvas.qid, canvas.chain = qid, nil
  local height = draw(canvas, { qid = qid })
  canvas.frame:SetSize(canvas.width, height)
  canvas.frame:Show()
  return height
end

-- A chain's sheet in a host's frame (the same canvas as a quest's: a page shows one of the two).
-- It takes the page's width: the step tiles flow in it. host.open(ref) opens a step.
function Sheet.DrawChainInto(ref, host)
  local typ, chainRoot = B.Entity.Parse(ref)
  local c = typ == "chain" and ns.Chains.Sheet(chainRoot) or nil
  if not (c and host and host.frame) then
    return 0
  end
  local canvas = hosted[host.frame]
  if not canvas then
    local page = CreateFrame("Frame", nil, host.frame)
    page:SetPoint("TOPLEFT", host.frame, "TOPLEFT", 0, 0)
    canvas = newCanvas(page, HOSTED)
    hosted[host.frame] = canvas
  end
  canvas.width = math.max(HOSTED_MIN, host.width or WIDTH)
  canvas.ctx = host.ctx or CTX
  canvas.extra = host.buttons
  canvas.refresh = host.refresh
  canvas.open = host.open
  canvas.qid, canvas.chain = nil, chainRoot
  local height = draw(canvas, { chain = c })
  canvas.frame:SetSize(canvas.width, height)
  canvas.frame:Show()
  return height
end

-- The canvas a host's frame holds (the sheet's own window: its own), or nil (the tests and the
-- perf scripts read what it drew).
function Sheet.Canvas(hostFrame)
  if hostFrame ~= nil and hostFrame == frame then
    return own
  end
  return hosted[hostFrame]
end

-- The host shows something else: the sheet's parts go.
function Sheet.HideIn(host)
  local canvas = host and host.frame and hosted[host.frame]
  if canvas then
    canvas.frame:Hide()
    canvas.qid, canvas.chain = nil, nil
  end
end

-- The hosted sheets on screen draw again (their hosts do it: a page lays itself out).
function Sheet.RefreshHosted()
  for _, canvas in pairs(hosted) do
    if (canvas.qid or canvas.chain) and canvas.refresh and canvas.frame:IsVisible() then
      canvas.refresh()
    end
  end
end

local function show(what, anchor, side)
  if not frame then
    build()
    own = newCanvas(frame, OWN)
  end
  shown = what
  place(anchor, side)
  Sheet.Render()
  frame:Show()
  frame:Raise() -- over the window it came from, in the same strata
end

-- ---------------------------------------------------------------------------------------------
-- What the rest of the addon and the service use
-- ---------------------------------------------------------------------------------------------

function Sheet.Open(qid)
  pinned = { qid = qid }
  show(pinned)
  return true
end

-- A click on a quest: one opens its sheet, the next closes it.
function Sheet.Toggle(qid)
  if Sheet.IsShown() and pinned and pinned.qid == qid then
    Sheet.Close()
    return false
  end
  return Sheet.Open(qid)
end

-- A look on hover: no buttons, no mouse, gone when the hover ends; the opened sheet comes back.
-- opts = { anchor, side, detail, title }: beside `anchor`, on its `side` ("LEFT" or "RIGHT")
-- when the caller knows where the room is, else on the side the anchor's place leaves free.
function Sheet.Preview(qid, opts)
  opts = opts or {}
  show({ qid = qid, preview = true, detail = opts.detail, title = opts.title }, opts.anchor, opts.side)
  return true
end

function Sheet.EndPreview()
  if not (shown and shown.preview) then
    return
  end
  if pinned then
    local keep = pinned
    show(keep)
  else
    frame:Hide()
  end
end

function Sheet.IsShown()
  return frame ~= nil and frame:IsShown()
end

function Sheet.Close()
  if frame then
    frame:Hide()
  end
end

-- The quest or its rewards changed: the page follows, coalesced like every Quests view; so do
-- the sheets a host shows.
function Sheet.Schedule()
  if not mod then
    return
  end
  if Sheet.IsShown() then
    mod:Coalesce("sheet", RENDER_DELAY, Sheet.Render)
  end
  for _, canvas in pairs(hosted) do
    if (canvas.qid or canvas.chain) and canvas.refresh then
      mod:Coalesce("sheet-hosted", RENDER_DELAY, Sheet.RefreshHosted)
      break
    end
  end
end

function Sheet.Register(self)
  mod = self
  B:RegisterAction(self, {
    id = "quests.sheet",
    label = L["Open the quest sheet"],
    short = L["Sheet"],
    icon = B.UI.IconTexture("ledger"),
    types = { "quest" },
    order = 70,
    run = function(ref)
      return Sheet.Toggle(questOf(ref))
    end,
  })
  B:RegisterAction(self, {
    id = "quests.chain",
    main = true, -- a button of the sheet (ADR 0054)
    label = L["Show the quest chain"],
    short = L["Chain"],
    icon = B.UI.IconTexture("chain"),
    types = { "quest" },
    order = 35,
    when = function(ref)
      local id = questOf(ref)
      return id ~= nil and Logic.chainFor(id, State.ForLogic()) ~= nil
    end,
    -- the chain is a subject (ADR 0055): its page, in the host that shows pages
    run = function(ref)
      local id = questOf(ref)
      local chainRoot = id and Logic.chainFor(id, State.ForLogic())
      return chainRoot ~= nil and B:ShowPage("chain:" .. chainRoot)
    end,
  })
  -- one quest sheet (ADR 0056): a page of a quest, wherever a host shows one, is this drawing.
  -- It says the task, the story and the rewards; the host draws the quest's other parts
  B:RegisterSheet(self, {
    types = { "quest" },
    covers = { "quests.objectives", "quests.rewards", "quests.text" },
    draw = function(ref, host)
      return Sheet.DrawInto(ref, host)
    end,
    hide = function(host)
      Sheet.HideIn(host)
    end,
  })
  -- a chain's page is its way as step tiles (ADR 0056); its other parts stay cards, and it can
  -- still be stepped into (`inside`)
  B:RegisterSheet(self, {
    types = { "chain" },
    inside = true,
    -- the way with what hangs on it; "Where it goes" stays a card
    covers = { "quests.chain.steps", "quests.chain.side", "quests.chain.others" },
    draw = function(ref, host)
      return Sheet.DrawChainInto(ref, host)
    end,
    hide = function(host)
      Sheet.HideIn(host)
    end,
  })
  B:ProvideService(self, "questSheet", {
    Preview = function(_, ref, opts)
      local id = questOf(ref)
      return id ~= nil and Sheet.Preview(id, opts)
    end,
    EndPreview = function()
      Sheet.EndPreview()
    end,
    Open = function(_, ref)
      local id = questOf(ref)
      return id ~= nil and Sheet.Open(id)
    end,
  }, { priority = 100 })
end
