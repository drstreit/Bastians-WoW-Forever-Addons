-- Bastian's Notes: the editor (notes.md "Writing"): title, text, symbol, colour, list, sharing and
-- the reminder of one note; Keep, Cancel, Remove.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Widgets = B.UI.Widgets
local Notes = ns.Notes

local Editor = {}
ns.Editor = Editor

Editor.SWATCH, Editor.GLYPH = 22, 22
local REMINDS = { { key = "", label = "Never" }, { key = "near", label = "When near" } }
local TARGET = { key = "target", label = "When I target it" }

local win, onWhat, title, body, listSelect, removeButton
local glyphButtons, colourButtons, shareButtons, remindButtons = {}, {}, {}, {}
local state -- { fields = { id, on, title, text, symbol, colour, share, remind }, list }

-- the model's fields of a note, copied (the editor never changes the note until Keep)
local function fieldsOf(note)
  return {
    id = note.id,
    on = note.on,
    title = note.title or "",
    text = note.text or "",
    symbol = note.symbol or (Notes.Model.IsSpot(note.on) and "spot" or "note"),
    colour = note.colour or "note1",
    share = note.share or "private",
    remind = note.remind,
  }
end

local function targetable(on)
  local typ = type(on) == "string" and on:match("^(%w+):")
  return typ and Notes.TARGETABLE[typ] or false
end

-- The toggles show the state: the chosen one accented.
local function mark(buttons, chosen)
  for key, b in pairs(buttons) do
    local col = key == chosen and S.C.accent or S.C.text
    b.label:SetTextColor(col[1], col[2], col[3])
  end
end

function Editor.Refresh()
  if not (win and state) then
    return
  end
  local f = state.fields
  onWhat:SetText(string.format(L["On %s"], Notes.Where(f)))
  for kind, b in pairs(glyphButtons) do
    b.tex:SetTexture(B.UI.GLYPH_PATHS[kind])
    S.tint(b.tex, kind == f.symbol and S.C[f.colour] or S.C.dim)
  end
  for token, b in pairs(colourButtons) do
    S.setEdges(b.ring, S.C.text, token == f.colour and 1 or 0) -- the chosen colour ringed
  end
  mark(shareButtons, f.share)
  mark(remindButtons, f.remind or "")
  remindButtons.target:SetShown(targetable(f.on))
  local values = {}
  for _, list in ipairs(Notes.Model.Lists(Notes.Global())) do
    values[list.id] = Notes.ListName(list)
  end
  listSelect:SetValues(values)
  listSelect:SetValue(state.list)
  removeButton:SetShown(f.id ~= nil)
end

local function toggleRow(parent, defs, buttons, width, onPick)
  local x = 0
  for _, d in ipairs(defs) do
    local b = S.button(parent, L[d.label], width, 20)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, 0)
    b:SetScript("OnClick", function()
      onPick(d.key)
    end)
    buttons[d.key] = b
    x = x + width + 4
  end
end

local function build()
  win = B.UI.Window("BastiansNotesEditor", {
    module = "Notes", -- the options button opens this page (R27.1)
    title = L["Note"],
    width = 380,
    height = 430,
    db = ns.mod.db.profile.editor,
  })
  local c = win.content
  onWhat = S.text(c, 11, S.C.dim)
  onWhat:SetPoint("TOPLEFT", c, "TOPLEFT", 8, -8)
  onWhat:SetPoint("TOPRIGHT", c, "TOPRIGHT", -8, -8)
  onWhat:SetJustifyH("LEFT")

  title = Widgets.Edit(c, L["Title"], function()
    Editor.Keep()
  end)
  title:SetPoint("TOPLEFT", c, "TOPLEFT", 8, -26)
  title:SetPoint("TOPRIGHT", c, "TOPRIGHT", -8, -26)
  title:SetMaxLetters(Notes.TITLE_MAX)
  title:SetScript("OnEscapePressed", function()
    Editor.Hide()
  end)

  local bodyBox = CreateFrame("Frame", nil, c)
  bodyBox:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  bodyBox:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -6)
  bodyBox:SetHeight(84)
  S.panel(bodyBox, S.C.panel)
  body = CreateFrame("EditBox", nil, bodyBox)
  body:SetMultiLine(true)
  body:SetAutoFocus(false)
  body:SetMaxLetters(Notes.TEXT_MAX)
  body:SetFont(S.font(), S.size(12), "")
  S.ink(body, S.C.text)
  body:SetPoint("TOPLEFT", bodyBox, "TOPLEFT", 6, -6)
  body:SetPoint("BOTTOMRIGHT", bodyBox, "BOTTOMRIGHT", -6, 6)
  body:SetScript("OnEscapePressed", function()
    Editor.Hide()
  end)

  local glyphs = CreateFrame("Frame", nil, c)
  glyphs:SetPoint("TOPLEFT", bodyBox, "BOTTOMLEFT", 0, -10)
  glyphs:SetSize(9 * (Editor.GLYPH + 4), 2 * (Editor.GLYPH + 4))
  for i, kind in ipairs(Notes.SYMBOLS) do
    local b = CreateFrame("Button", nil, glyphs)
    b:SetSize(Editor.GLYPH, Editor.GLYPH)
    local col, row = (i - 1) % 9, math.floor((i - 1) / 9)
    b:SetPoint("TOPLEFT", glyphs, "TOPLEFT", col * (Editor.GLYPH + 4), -row * (Editor.GLYPH + 4))
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b:SetScript("OnClick", function()
      state.fields.symbol = kind
      Editor.Refresh()
    end)
    glyphButtons[kind] = b
  end

  local colours = CreateFrame("Frame", nil, c)
  colours:SetPoint("TOPLEFT", glyphs, "BOTTOMLEFT", 0, -8)
  colours:SetSize(6 * (Editor.SWATCH + 6), Editor.SWATCH)
  for i, token in ipairs(Notes.COLOURS) do
    local b = CreateFrame("Button", nil, colours)
    b:SetSize(Editor.SWATCH, Editor.SWATCH)
    b:SetPoint("TOPLEFT", colours, "TOPLEFT", (i - 1) * (Editor.SWATCH + 6), 0)
    b.face = S.roundFill(b, S.C[token], "radiusSmall")
    b.ring = S.roundEdges(b, S.C.text, "radiusSmall")
    b:SetScript("OnClick", function()
      state.fields.colour = token
      Editor.Refresh()
    end)
    colourButtons[token] = b
  end

  listSelect = Widgets.Select(c, L["List"], {}, function(key)
    state.list = key
  end)
  listSelect:SetPoint("TOPLEFT", colours, "BOTTOMLEFT", 0, -10)
  listSelect:SetPoint("RIGHT", c, "RIGHT", -8, 0)

  local share = CreateFrame("Frame", nil, c)
  share:SetPoint("TOPLEFT", listSelect, "BOTTOMLEFT", 0, -8)
  share:SetSize(330, 20)
  toggleRow(
    share,
    {
      { key = "private", label = "Private" },
      { key = "shareable", label = "Goes with its list" },
    },
    shareButtons,
    150,
    function(key)
      state.fields.share = key
      Editor.Refresh()
    end
  )

  local remind = CreateFrame("Frame", nil, c)
  remind:SetPoint("TOPLEFT", share, "BOTTOMLEFT", 0, -8)
  remind:SetSize(340, 20)
  toggleRow(remind, { REMINDS[1], REMINDS[2], TARGET }, remindButtons, 108, function(key)
    state.fields.remind = key ~= "" and key or nil
    Editor.Refresh()
  end)

  local keep = S.button(c, L["Keep"], 80, 22, true)
  keep:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -8, 8)
  keep:SetScript("OnClick", function()
    Editor.Keep()
  end)
  local cancel = S.button(c, L["Cancel"], 80, 22)
  cancel:SetPoint("RIGHT", keep, "LEFT", -6, 0)
  cancel:SetScript("OnClick", function()
    Editor.Hide()
  end)
  removeButton = S.button(c, L["Remove"], 80, 22)
  removeButton:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 8, 8)
  removeButton:SetScript("OnClick", function()
    Editor.RemoveShown()
  end)
  Editor.win, Editor.title, Editor.body = win, title, body
  Editor.glyphButtons, Editor.colourButtons = glyphButtons, colourButtons
  Editor.shareButtons, Editor.remindButtons = shareButtons, remindButtons
end

-- Opens the editor on a note (with an id: a change) or on new fields ({ on = ref or spot }).
function Editor.Open(note)
  if not (ns.mod and ns.mod:IsEnabled()) then
    return false
  end
  if not win then
    build()
  end
  local list
  if note.id then
    list = select(2, Notes.Model.Find(Notes.Global(), note.id))
  end
  state = { fields = fieldsOf(note), list = list and list.id or "my" }
  title:SetText(state.fields.title)
  body:SetText(state.fields.text)
  Editor.state = state
  Editor.Refresh()
  win:Show()
  title:SetFocus()
  return true
end

function Editor.Keep()
  if not state then
    return nil
  end
  state.fields.title = title:GetText() or ""
  state.fields.text = body:GetText() or ""
  local note, why = Notes.Save(state.fields, state.list)
  if not note then
    B:Say(why == "title" and L["A note needs a title."] or L["The note could not be kept (%s)."], why)
    return nil
  end
  Editor.Hide()
  return note
end

function Editor.RemoveShown()
  if state and state.fields.id then
    Notes.Remove(state.fields.id)
  end
  Editor.Hide()
end

function Editor.Hide()
  if win then
    win:Hide()
  end
  state = nil
  Editor.state = nil
end

function Editor.IsShown()
  return win ~= nil and win:IsShown()
end

ns.mod.Editor = Editor -- for the tests and /bastians debug
