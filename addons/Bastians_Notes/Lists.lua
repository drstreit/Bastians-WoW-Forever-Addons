-- Bastian's Notes: the Lists window (notes.md "The Lists window"): every list with its notes as a
-- tree; a note row opens the editor, a list row's button shows or hides the list on the map; New
-- list, Rename and Remove at the bottom.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Widgets = B.UI.Widgets
local Notes = ns.Notes

local Lists = {}
ns.Lists = Lists

local win, tree, nameBox, newButton, renameButton, removeButton
local selected = "my" -- the list the buttons act on

-- The tree's rows: the lists, "My notes" first, each with its notes.
function Lists.Rows()
  local rows = {}
  for _, list in ipairs(Notes.Model.Lists(Notes.Global())) do
    local children = {}
    local notes = {}
    for _, n in pairs(list.notes) do
      notes[#notes + 1] = n
    end
    table.sort(notes, function(a, b)
      return a.title:lower() < b.title:lower()
    end)
    for _, n in ipairs(notes) do
      -- a note on an entity carries it:
      -- the entity's tooltip on the row, a right click its menu (Open in Browser, ...)
      local ref = type(n.on) == "string" and not Notes.Model.IsSpot(n.on) and n.on or nil
      children[#children + 1] = {
        id = "note:" .. n.id,
        text = Notes.Coloured(n),
        icon = Notes.Glyph(n),
        meta = Notes.Where(n) .. (ref and ("  " .. L["(right click: open it)"]) or ""),
        ref = ref,
        -- not `note`: the tree draws a row's `note` as a text column, and a table there stopped
        -- the tree at the first note row
        entry = n,
        onClick = function(_, button)
          if button == "RightButton" and ref then
            B.UI.EntityMenu(ref, nil, { source = "notes" })
          else
            ns.Editor.Open(n)
          end
        end,
      }
    end
    local marks = {}
    for _, b in pairs(list.bookmarks or {}) do
      marks[#marks + 1] = b
    end
    table.sort(marks, function(a, b)
      return (a.created or 0) < (b.created or 0)
    end)
    for _, b in ipairs(marks) do
      children[#children + 1] = {
        id = "bookmark:" .. b.id,
        text = b.name,
        icon = B.UI.IconTexture("zone"),
        meta = L["Bookmark: a click shows it on the map, a right click renames it"],
        bookmark = b,
        onClick = function(_, button)
          if button == "RightButton" then
            Lists.AskName(b.name, function(value)
              if Notes.Model.RenameBookmark(Notes.Global(), b.id, value) then
                Notes.Changed()
              end
            end)
          else
            local map = B.Coords.BestMap(b.continent, b.wx, b.wy)
            B:RunAction("map.show", map and ("zone:" .. map) or nil, {
              source = "notes",
              point = { b.continent, b.wx, b.wy, b.name },
            })
          end
        end,
      }
    end
    local id = list.id
    rows[#rows + 1] = {
      id = "list:" .. id,
      text = string.format("%s  %s(%d)|r", Notes.ListName(list), S.H.muted, #notes + #marks),
      list = list,
      children = children,
      button = {
        label = list.hidden and L["off"] or L["on"],
        onClick = function()
          list.hidden = not list.hidden or nil
          Notes.Changed()
        end,
      },
      onClick = function(row)
        selected = id
        tree:ToggleFold(row)
        Lists.RenderButtons()
      end,
    }
  end
  return rows
end

function Lists.RenderButtons()
  if not win then
    return
  end
  local list = Notes.Global().lists[selected]
  if not list then
    selected = "my"
  end
  renameButton:SetShown(selected ~= "my")
  removeButton:SetShown(selected ~= "my")
end

function Lists.Render()
  if not (win and win:IsShown()) then
    return
  end
  tree:SetRows(Lists.Rows())
  Lists.RenderButtons()
end

-- The name box above the buttons: Enter keeps, Esc cancels; onDone(text).
local function askName(text, onDone)
  nameBox.onDone = onDone
  nameBox:SetText(text or "")
  nameBox:Show()
  nameBox:SetFocus()
end
Lists.AskName = askName

local function build()
  win = B.UI.Window("BastiansNotesLists", {
    module = "Notes", -- the options button opens this page (R27.1)
    title = L["Notes"],
    width = 420,
    height = 460,
    db = ns.mod.db.profile.lists,
    onShow = function()
      Lists.Render()
    end,
    onResize = function()
      if tree then
        tree:Refresh()
      end
    end,
  })
  local c = win.content
  tree = B.UI.Tree(c, {
    db = ns.mod.db.profile.tree,
    ctx = { source = "notes" },
    onClick = function(row, button)
      if row.button and button == "RightButton" then
        row.button.onClick(row)
      elseif row.onClick then
        row.onClick(row, button)
      end
    end,
  })
  tree.chips:ClearAllPoints()
  tree.chips:SetPoint("TOPLEFT", c, "TOPLEFT", 6, -6)
  tree.chips:SetPoint("TOPRIGHT", c, "TOPRIGHT", -20, -6)
  tree.scroll:ClearAllPoints()
  tree.scroll:SetPoint("TOPLEFT", tree.chips, "BOTTOMLEFT", 0, -2)
  tree.scroll:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -20, 58)

  nameBox = Widgets.Edit(c, L["List name"], function(value)
    nameBox:Hide()
    if nameBox.onDone then
      nameBox.onDone(value)
    end
  end)
  nameBox:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 8, 32)
  nameBox:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -8, 32)
  nameBox:SetMaxLetters(Notes.TITLE_MAX)
  nameBox:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    self:Hide()
  end)
  nameBox:Hide()

  newButton = S.button(c, L["New list"], 76, 22)
  newButton:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 8, 6)
  newButton:SetScript("OnClick", function()
    askName("", function(value)
      local list = Notes.Model.NewList(Notes.Global(), value)
      if list then
        selected = list.id
        Notes.Changed()
      end
    end)
  end)
  renameButton = S.button(c, L["Rename"], 76, 22)
  renameButton:SetPoint("LEFT", newButton, "RIGHT", 4, 0)
  renameButton:SetScript("OnClick", function()
    local list = Notes.Global().lists[selected]
    askName(list and list.name, function(value)
      if Notes.Model.RenameList(Notes.Global(), selected, value) then
        Notes.Changed()
      end
    end)
  end)
  removeButton = S.button(c, L["Remove list"], 80, 22)
  removeButton:SetPoint("LEFT", renameButton, "RIGHT", 4, 0)
  removeButton:SetScript("OnClick", function()
    if Notes.Model.RemoveList(Notes.Global(), selected) then
      selected = "my"
      Notes.Changed()
    end
  end)
  -- sharing (N3): the list the buttons act on, and a pasted text
  local import = S.button(c, L["Import"], 76, 22)
  import:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -8, 6)
  import:SetScript("OnClick", function()
    ns.Share.OpenImport()
  end)
  local share = S.button(c, L["Share"], 76, 22, true)
  share:SetPoint("RIGHT", import, "LEFT", -4, 0)
  share:SetScript("OnClick", function()
    ns.Share.Open(selected)
  end)
  Lists.win, Lists.tree, Lists.nameBox = win, tree, nameBox
end

function Lists.Open()
  if not (ns.mod and ns.mod:IsEnabled()) then
    return false
  end
  if not win then
    build()
  end
  win:Show()
  Lists.Render()
  return true
end

function Lists.Toggle()
  if win and win:IsShown() then
    win:Hide()
  else
    Lists.Open()
  end
end

function Lists.Hide()
  if win then
    win:Hide()
  end
end

-- Which list the buttons act on (the last list row clicked).
function Lists.Select(id)
  selected = id
  Lists.RenderButtons()
end

ns.mod.Lists = Lists -- for the tests and /bastians debug
