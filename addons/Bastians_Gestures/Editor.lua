-- The editor of Bastian's Gestures (gestures.md): a window with the three rings, their names and
-- their eight slots; a click on a slot opens the picker beside the rings (below them in a narrow
-- window): a filter box and the categories (the game's emotes, my lines, commands, the suite's
-- actions, the game's controls, a sub-ring or nothing), filtered as the player types (the editor
-- v2, ). Default rings restores the shipped ones.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local W = B.UI.Widgets
local Model = ns.Model

local Editor = {}
ns.Editor = Editor

local win, canvas, scroll, bar
local path = {} -- the sub-rings entered in the editor, innermost last
local form -- the line or command being edited: { kind, ring, index, title, text, channel, language }
local picker -- the picker of a slot: { ring, index, first, open = { [category] = true | false } }
local filterText = "" -- the picker's filter, kept while the window is open
local pool = {} -- the picker's row buttons, reused (a frame is never freed)
local used = 0 -- the pooled buttons drawn now
local listTop, listX, listWidth = 0, 12, 400 -- where the picker's list starts
local fixedBottom = 0 -- the lowest y of everything but the list

local ROW = 26
local RING_COLUMN = 340 -- the rings' column when the picker stands beside them
local WIDE = 720 -- from this width on the picker stands beside the rings

local function mod()
  return ns.Gestures.mod
end

local function rings()
  return Model.Ensure(mod().db.global)
end

local function changed()
  B:Fire("BASTIANS_GESTURES_CHANGED")
  Editor.Render()
end

local function trim(text)
  return ((text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function copy(slot)
  local out = {}
  for k, v in pairs(slot) do
    out[k] = v
  end
  return out
end

-- The ring shown: the entered sub-ring, else every ring.
function Editor.Path()
  return path
end

-- Sets slot `i` of `ring` and tells the suite.
function Editor.SetSlot(ring, i, slot)
  ring.slots[i] = slot or false
  changed()
end

-- A ring's name (editor v2): the player's words; an empty name keeps the old one.
function Editor.RenameRing(ring, text)
  text = trim(text)
  if not ring or text == "" then
    return false
  end
  ring.name = text
  changed()
  return true
end

function Editor.Enter(sub)
  path[#path + 1] = sub
  form, picker = nil, nil
  Editor.Render()
end

function Editor.Back()
  path[#path] = nil
  form, picker = nil, nil
  Editor.Render()
end

function Editor.Defaults()
  mod().db.global.rings = Model.DefaultRings()
  path = {}
  form, picker = nil, nil
  changed()
end

-- The words of a slot for its row.
local function slotWords(slot)
  if not slot then
    return L["empty"]
  end
  local words = Model.Describe(slot)
  if slot.kind == "line" then
    local channels = { SAY = L["say"], EMOTE = L["emote"], YELL = L["yell"] }
    words = words
      .. "  ("
      .. (channels[slot.channel] or slot.channel or "")
      .. (slot.language and (", " .. slot.language) or "")
      .. ")"
  elseif slot.kind == "ring" then
    words = words .. "  " .. L["(a ring)"]
  elseif slot.kind == "macro" then
    if ns.Compat.MacroExists(slot.name) then
      words = words .. "  " .. L["(a macro)"]
    else
      words = string.format(L["Macro not found: %s"], slot.name or "")
    end
  end
  return words
end

-- ---------------------------------------------------------------------------------------------
-- The picker and its forms
-- ---------------------------------------------------------------------------------------------

-- Opens the picker for slot `i` of `ring` (the filter stays as the player left it).
function Editor.Choose(ring, i)
  local slot = ring.slots[i]
  local first = Model.CategoryOf(slot, ring)
  if slot and slot.kind == "macro" and not ns.Compat.MacroExists(slot.name) then
    first = "other" -- a gone macro: the Empty row clears it (the slot is never cleared by itself)
  end
  picker = { ring = ring, index = i, first = first, open = {} }
  form = nil
  Editor.Render()
  return picker
end

local function needs(def)
  if def.action and not B:GetAction(def.action) then
    return string.format(L["Needs Bastian's %s"], def.needs or "")
  end
  return nil
end

local function has(def)
  return ns.Compat.HasGame(def.id)
end

-- The picker's categories under the filter (Model.Catalogue, Model.Filter).
function Editor.Catalogue()
  local all = Model.Catalogue(ns.Compat.GameEmotes(), rings(), needs, has, ns.Compat.Macros())
  return Model.Filter(all, filterText)
end

function Editor.Filter()
  return filterText
end

-- Sets the filter as if typed: the list follows at once.
function Editor.SetFilter(text)
  filterText = text or ""
  if Editor.filterBox and (Editor.filterBox:GetText() or "") ~= filterText then
    Editor.filterBox:SetText(filterText)
  end
  Editor.RenderList()
end

-- A category's header was clicked: open or closed.
function Editor.Toggle(id)
  if not picker then
    return
  end
  picker.open[id] = not Editor.Expanded(id)
  Editor.RenderList()
end

local function lineForm(ring, i)
  local slot = ring.slots[i]
  local own = slot and slot.kind == "line" and slot or nil
  return {
    kind = "line",
    ring = ring,
    index = i,
    title = own and own.title or "",
    text = own and own.text or "",
    channel = own and own.channel or "SAY",
    language = own and own.language or nil,
  }
end

local function commandForm(ring, i)
  local slot = ring.slots[i]
  local own = slot and slot.kind == "command" and slot or nil
  return {
    kind = "command",
    ring = ring,
    index = i,
    title = own and own.title or "",
    text = own and own.text or "",
  }
end

-- A row of the picker was chosen: its slot goes in, or its form or step opens.
function Editor.Pick(row)
  if not (picker and row) then
    return false
  end
  local ring, i = picker.ring, picker.index
  if row.slot then
    picker = nil
    Editor.SetSlot(ring, i, copy(row.slot))
  elseif row.open == "line" then
    picker, form = nil, lineForm(ring, i)
    Editor.Render()
  elseif row.open == "command" then
    picker, form = nil, commandForm(ring, i)
    Editor.Render()
  elseif row.open == "ring" then
    picker = nil
    local sub =
      { kind = "ring", name = L["Ring"], slots = { false, false, false, false, false, false, false, false } }
    Editor.SetSlot(ring, i, sub)
    Editor.Enter(sub)
  elseif row.open == "empty" then
    picker = nil
    Editor.SetSlot(ring, i, false)
  else
    return false
  end
  return true
end

-- The gesture picker chose a token.
function Editor.PickEmote(token)
  if not picker then
    return false
  end
  local word = Model.EmoteWord(token)
  if not word then
    for _, e in ipairs(ns.Compat.GameEmotes()) do
      if e.token == token then
        word = Model.CommandWord(e.token, e.cmd)
      end
    end
  end
  return Editor.Pick({ slot = { kind = "emote", token = token, label = word or token } })
end

-- The line form was saved.
function Editor.SaveLine()
  if not form or form.kind ~= "line" then
    return false
  end
  local text = trim(form.text)
  if text == "" then
    return false
  end
  local title = trim(form.title)
  if title == "" then
    title = text:sub(1, 18)
  end
  local done = form
  form = nil
  Editor.SetSlot(done.ring, done.index, {
    kind = "line",
    title = title,
    text = text,
    channel = done.channel or "SAY",
    language = done.language,
  })
  return true
end

-- The command form was saved: the title and the lines of the macro.
function Editor.SaveCommand()
  if not form or form.kind ~= "command" then
    return false
  end
  local text = trim(form.text)
  if text == "" then
    return false
  end
  local title = trim(form.title)
  if title == "" then
    title = (text:match("^[^\n]*") or text):sub(1, 18)
  end
  local ring, index = form.ring, form.index
  form = nil
  Editor.SetSlot(ring, index, { kind = "command", title = title, text = text })
  return true
end

function Editor.Form()
  return form
end

function Editor.Picker()
  return picker
end

-- ---------------------------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------------------------

local function clear()
  for _, w in ipairs(canvas.widgets or {}) do
    w:Hide()
    w:SetParent(nil)
  end
  canvas.widgets = {}
  for i = 1, #pool do
    pool[i]:Hide()
  end
  used = 0
  Editor.filterBox, Editor.textBox, Editor.titleBox, Editor.nameBoxes = nil, nil, nil, {}
end

local function add(w)
  canvas.widgets[#canvas.widgets + 1] = w
  return w
end

local function header(text, y, x, width)
  local h = add(W.Header(canvas, text))
  h:SetPoint("TOPLEFT", canvas, "TOPLEFT", x or 12, y)
  if width then
    h:SetWidth(width)
  else
    h:SetPoint("RIGHT", canvas, "RIGHT", -12, 0)
  end
  return y - (h:GetHeight() or 20) - 4
end

local function button(spec, x, y)
  local b = add(S.action(canvas, spec))
  b:SetPoint("TOPLEFT", canvas, "TOPLEFT", x, y)
  return b
end

-- The kit's hint of a box (W.Edit) stays right under the editor's own OnTextChanged: hidden while
-- the box holds text or has the focus, the clear button only with text (
-- the hint was drawn over the typed "Reload"). `fn(box)` follows the text.
local function syncHint(box)
  local text = box:GetText() or ""
  if box.hint then
    box.hint:SetShown(text == "" and not box:HasFocus())
  end
  if box.clear then
    box.clear:SetShown(text ~= "")
  end
end

local function onText(box, fn)
  box:SetScript("OnTextChanged", function(self, ...)
    syncHint(self)
    fn(self, ...)
  end)
  if not box.hintFollows then
    box.hintFollows = true
    box:HookScript("OnEditFocusGained", syncHint)
    box:HookScript("OnEditFocusLost", syncHint)
  end
  syncHint(box)
end

local function edit(hint, x, y, width, onEnter)
  local box = add(W.Edit(canvas, hint, onEnter))
  box:SetPoint("TOPLEFT", canvas, "TOPLEFT", x, y)
  box:SetWidth(width)
  return box
end

local function note(text, x, y, width)
  local n = add(W.Note(canvas, text))
  n:SetPoint("TOPLEFT", canvas, "TOPLEFT", x, y)
  n:SetWidth(width)
  return y - (n:GetHeight() or 16) - 4
end

local function drawRing(ring, y, depth)
  for i = 1, Model.WEDGES do
    local slot = ring.slots[i]
    local _, kind = Model.Describe(slot)
    local chosen = picker and picker.ring == ring and picker.index == i or nil
    local b = button({
      icon = kind or "plus",
      label = string.format("%d  %s", i, slotWords(slot)),
      boxed = true,
      on = chosen,
    }, 12 + depth * 16, y)
    b.slot, b.ring, b.index = slot, ring, i
    b.tip = slot and (slot.kind == "line" or slot.kind == "command") and slot.text
      or L["Click: set this slot"]
    if slot and slot.kind == "macro" and not ns.Compat.MacroExists(slot.name) then
      b.tip = L["The macro is gone: choose Empty or another entry for this slot."]
      b:SetEnabledFlat(false)
    end
    b:SetScript("OnClick", function()
      Editor.Choose(ring, i)
    end)
    if slot and slot.kind == "ring" then
      local enter = button({ icon = "rename", label = L["Edit the ring"], row = true }, 260, y)
      enter:SetScript("OnClick", function()
        Editor.Enter(slot)
      end)
    end
    y = y - ROW
  end
  return y
end

-- A pooled row button of the picker, set to `spec`; `onPick` runs on its click.
local function take(spec, x, y, onPick, tip, dim)
  used = used + 1
  local b = pool[used]
  if not b then
    b = S.action(canvas, {})
    b:SetScript("OnClick", function(self)
      if self.onPick then
        self.onPick()
      end
    end)
    pool[used] = b
  end
  b.spec = spec
  b.onPick, b.tip, b.cat, b.row = onPick, tip, nil, nil
  b:Fit()
  b:SetEnabledFlat(not dim)
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", canvas, "TOPLEFT", x, y)
  b:Show()
  return b
end

-- Whether a category of the picker is open: as the player left it, else open while the filter
-- finds something in it, else the category of the slot's own kind.
function Editor.Expanded(id)
  if not picker then
    return false
  end
  if picker.open[id] ~= nil then
    return picker.open[id]
  end
  if trim(filterText) ~= "" then
    return true
  end
  return id == picker.first
end

local function setHeight(bottom)
  canvas.contentHeight = -math.min(bottom, fixedBottom) + 10
  canvas:SetHeight(canvas.contentHeight)
  bar.SetTotal(canvas.contentHeight)
end

-- The picker's list under its filter box: the categories, their rows in columns, at most
-- Model.PICK_CAP per category. Only the list is drawn again as the player types.
function Editor.RenderList()
  if not (canvas and picker) then
    return
  end
  for i = 1, #pool do
    pool[i]:Hide()
  end
  used = 0
  local cols = math.max(1, math.floor(listWidth / 170))
  local colW = math.floor(listWidth / cols)
  local y = listTop
  for _, cat in ipairs(Editor.Catalogue()) do
    local open = Editor.Expanded(cat.id) and cat.total > 0
    local id = cat.id
    local head = take(
      {
        icon = cat.kind,
        label = string.format("%s %s (%d)", open and "-" or "+", cat.label, cat.total),
        on = open,
      },
      listX,
      y,
      function()
        Editor.Toggle(id)
      end
    )
    head.cat = id
    y = y - ROW
    if open then
      local col, group = 0, nil
      for n, r in ipairs(cat.rows) do
        if n > Model.PICK_CAP then
          if col > 0 then
            y = y - ROW
          end
          col = 0
          take(
            { label = string.format(L["%d more: type to narrow the list"], cat.total - Model.PICK_CAP) },
            listX + 8,
            y
          )
          y = y - ROW
          break
        end
        if r.group and r.group ~= group then
          if col > 0 then
            y = y - ROW
          end
          col, group = 0, r.group
          local words = r.group == "favourites" and L["Favourites"] or L["All the game's emotes"]
          take({ label = words, row = true }, listX + 8, y, nil, nil, true)
          y = y - ROW
        end
        local row = r
        local b = take(
          { icon = r.kind, label = r.label, boxed = true, width = colW - 6 },
          listX + 8 + col * colW,
          y,
          function()
            Editor.Pick(row)
          end,
          r.tip,
          r.dim
        )
        b.row = r
        b.cat = id
        col = col + 1
        if col == cols then
          col = 0
          y = y - ROW
        end
      end
      if col > 0 then
        y = y - ROW
      end
    end
  end
  setHeight(y - 8)
end

-- The picker's head: which slot, the filter box, Cancel; the list follows below it.
local function drawPicker(x, y, width)
  local ringName = picker.ring.name or ""
  y = header(string.format(L["Slot %d of %s"], picker.index, ringName), y, x, width)
  local box = edit(L["Filter: a word or a command (/dance)"], x, y, math.max(160, width - 110))
  box:SetText(filterText)
  onText(box, function(self)
    local text = self:GetText() or ""
    if text ~= filterText then
      filterText = text
      Editor.RenderList()
    end
  end)
  Editor.filterBox = box
  local cancel = button({ icon = "close", label = L["Cancel"] }, x + math.max(160, width - 110) + 8, y)
  cancel:SetScript("OnClick", function()
    picker = nil
    Editor.Render()
  end)
  listTop, listX, listWidth = y - 30, x, width
  Editor.RenderList()
end

local function drawLineForm(y)
  y = header(string.format(L["A line for slot %d"], form.index), y)
  local title = edit(L["A short title for the wedge"], 12, y, 240)
  title:SetText(form.title or "")
  Editor.titleBox = title
  onText(title, function(self)
    form.title = self:GetText() or ""
  end)
  y = y - 28
  local text = add(W.Edit(canvas, L["The line"], nil))
  text:SetPoint("TOPLEFT", canvas, "TOPLEFT", 12, y)
  text:SetPoint("RIGHT", canvas, "RIGHT", -12, 0)
  text:SetText(form.text or "")
  onText(text, function(self)
    form.text = self:GetText() or ""
  end)
  Editor.textBox = text
  y = y - 26
  y = note(
    L["%t the target, %r its race, %c its class, %g its guild, %rp its roleplay name; %n me, %m my race, %k my class, %f my faction, %l my level, %e he or she; %z the zone, %a the area, %h the time of day"], -- luacheck: ignore 631 (a locale key stays one literal)
    12,
    y,
    (canvas:GetWidth() or 500) - 24
  )
  local channel = add(
    W.Select(canvas, L["Spoken as"], { SAY = L["Say"], EMOTE = L["Emote"], YELL = L["Yell"] }, function(key)
      form.channel = key
    end)
  )
  channel:SetPoint("TOPLEFT", canvas, "TOPLEFT", 12, y)
  channel:SetPoint("RIGHT", canvas, "RIGHT", -12, 0)
  channel:SetValue(form.channel or "SAY")
  y = y - 28
  local languages = { none = L["The common tongue"] }
  for _, lang in ipairs(ns.Compat.Languages()) do
    languages[lang.name] = lang.name
  end
  local language = add(W.Select(canvas, L["In the language"], languages, function(key)
    form.language = key ~= "none" and key or nil
  end))
  language:SetPoint("TOPLEFT", canvas, "TOPLEFT", 12, y)
  language:SetPoint("RIGHT", canvas, "RIGHT", -12, 0)
  language:SetValue(form.language or "none")
  y = y - 32
  local save = button({ icon = "done", label = L["Save"], primary = true }, 12, y)
  save:SetScript("OnClick", Editor.SaveLine)
  return y
end

local function drawCommandForm(y)
  y = header(string.format(L["A command for slot %d"], form.index), y)
  local title = edit(L["A short title for the wedge"], 12, y, 240)
  title:SetText(form.title or "")
  Editor.titleBox = title
  onText(title, function(self)
    form.title = self:GetText() or ""
  end)
  y = y - 28
  local text = add(W.Edit(canvas, L["The commands, one per line"], nil))
  text:SetMultiLine(true)
  text:SetHeight(66)
  text:SetTextInsets(8, 22, 5, 5)
  if text.hint then
    text.hint:ClearAllPoints()
    text.hint:SetPoint("TOPLEFT", 8, -5) -- the hint where the first line is typed
  end
  text:SetPoint("TOPLEFT", canvas, "TOPLEFT", 12, y)
  text:SetPoint("RIGHT", canvas, "RIGHT", -12, 0)
  text:SetText(form.text or "")
  onText(text, function(self)
    form.text = self:GetText() or ""
  end)
  text:SetScript("OnEnterPressed", function(self)
    if self.Insert then
      self:Insert("\n") -- a new line of the macro, not the end of the edit
    end
  end)
  Editor.textBox = text
  y = y - 70
  y = note(
    L["One command per line: /dance, /say Hello %t, /wave, /e smiles, or an addon's own command. The placeholders of a line work here too. /cast, /use and /target are the game's own: it runs them from its own macros and buttons only, never from an addon."], -- luacheck: ignore 631 (a locale key stays one literal)
    12,
    y,
    (canvas:GetWidth() or 500) - 24
  )
  y = y - 4
  local save = button({ icon = "done", label = L["Save"], primary = true }, 12, y)
  save:SetScript("OnClick", Editor.SaveCommand)
  return y
end

local function drawForm(y)
  y = form.kind == "command" and drawCommandForm(y) or drawLineForm(y)
  local cancel = button({ icon = "close", label = L["Cancel"] }, 110, y)
  cancel:SetScript("OnClick", function()
    form = nil
    Editor.Render()
  end)
  return y - ROW - 8
end

local function drawRings(y, width)
  for n, ring in ipairs(rings()) do
    y = header(string.format(L["Ring %d: %s"], n, ring.name or ""), y, 12, width)
    local box = edit(L["The ring's name"], 12, y, 220, function(text)
      Editor.RenameRing(ring, text)
    end)
    box:SetText(ring.name or "")
    box.tip = L["Press Enter to keep the name."]
    Editor.nameBoxes[n] = box
    y = y - 28
    y = drawRing(ring, y, 0)
    y = y - 6
  end
  local defaults = button({ icon = "replay", label = L["Default rings"], boxed = true }, 12, y - 4)
  defaults.tip = L["Back to the three rings as shipped; your lines are lost."]
  defaults:SetScript("OnClick", Editor.Defaults)
  return y - ROW - 8
end

local function drawSubRing(y)
  local sub = path[#path]
  local back = button({ icon = "back", label = L["Back"], boxed = true }, 12, y)
  back:SetScript("OnClick", Editor.Back)
  local name = add(W.Edit(canvas, L["The ring's name"], function(text)
    Editor.RenameRing(sub, text)
  end))
  name:SetPoint("LEFT", back, "RIGHT", 8, 0)
  name:SetWidth(200)
  name:SetText(sub.name or "")
  y = y - 30
  return drawRing(sub, y, 0)
end

function Editor.Render()
  if not canvas then
    return
  end
  clear()
  local width = math.max(100, scroll:GetWidth() or (win:GetWidth() and win:GetWidth() - 14) or 500)
  canvas:SetWidth(width)
  local wide = width >= WIDE
  local y = -10
  if form then
    y = drawForm(y)
  else
    y = #path > 0 and drawSubRing(y) or drawRings(y, wide and RING_COLUMN or nil)
  end
  fixedBottom = y
  if picker and not form then
    if wide then
      drawPicker(RING_COLUMN + 24, -10, width - RING_COLUMN - 36)
    else
      drawPicker(12, y - 4, width - 24)
    end
  else
    setHeight(y)
  end
end

local function build()
  win = B.UI.Window("BastiansGesturesEditor", {
    title = L["Bastian's Gestures"],
    module = "Gestures",
    width = 860,
    height = 600,
    db = mod().db.profile.editor,
    onResize = Editor.Render,
    onHide = function()
      picker, form, filterText = nil, nil, "" -- the window's own close button too
    end,
  })
  scroll = CreateFrame("ScrollFrame", nil, win.content)
  scroll:SetPoint("TOPLEFT", 0, 0)
  scroll:SetPoint("BOTTOMRIGHT", -14, 0)
  canvas = CreateFrame("Frame", nil, scroll)
  canvas:SetSize(480, 1)
  canvas.widgets = {}
  scroll:SetScrollChild(canvas)
  bar = S.scrollbar(scroll, win.content)
  Editor.win, Editor.canvas = win, canvas
end

function Editor.Open()
  if not win then
    build()
  end
  win:Show()
  Editor.Render()
  return true
end

function Editor.Close()
  if win then
    win:Hide()
  end
  picker, form, filterText = nil, nil, ""
end

function Editor.IsShown()
  return win ~= nil and win:IsShown()
end

-- The slot buttons drawn (tests): { { ring, index, slot } }
function Editor.Rows()
  local out = {}
  for _, w in ipairs(canvas and canvas.widgets or {}) do
    if w.index then
      out[#out + 1] = { ring = w.ring, index = w.index, slot = w.slot, button = w }
    end
  end
  return out
end

-- The picker's buttons drawn (tests): { { label, cat, row, button } }; a category's header has no row.
function Editor.Choices()
  local out = {}
  for i = 1, used do
    local b = pool[i]
    if b.cat then
      out[#out + 1] = { label = b.spec.label, cat = b.cat, row = b.row, button = b }
    end
  end
  return out
end
