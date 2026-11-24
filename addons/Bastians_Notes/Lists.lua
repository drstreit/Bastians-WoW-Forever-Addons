-- Bastian's Notes: the Lists window (notes.md "The Lists window"): every list with its notes as a
-- tree; a note row opens the editor, a list row's button shows or hides the list on the map. In
-- the one look (ADR 0084, W9; notes.md "The one look"): New list, Import and Share are the
-- head's tools, the chosen list with Rename and Remove list stands in the foot.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Widgets = B.UI.Widgets
local Notes = ns.Notes

local Lists = {}
ns.Lists = Lists

local TREE_LEFT, TREE_RIGHT = 6, 20 -- the rows' room beside the fold marks and the scroll bar

local win, tree, nameBox, renameButton, removeButton, foot
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
      kind = "section", -- a quiet heading with its count (the board)
      title = Notes.ListName(list),
      count = #notes + #marks,
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
  -- the foot names the list its tools act on
  list = Notes.Global().lists[selected]
  foot:SetText(list and Notes.ListName(list) or "")
  foot:Layout()
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
    head = "tall", -- a window opened to read (ADR 0084 decision 3)
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
  -- the head's tools (the board): New list and Import as words in an outline, Share the one
  -- filled plate (sharing, N3: the chosen list; Import takes a pasted text)
  local head = win:Bar({
    tools = {
      {
        id = "new",
        label = L["New list"],
        onClick = function()
          Lists.AskName("", function(value)
            local list = Notes.Model.NewList(Notes.Global(), value)
            if list then
              selected = list.id
              Notes.Changed()
            end
          end)
        end,
      },
      {
        id = "import",
        label = L["Import"],
        onClick = function()
          ns.Share.OpenImport()
        end,
      },
      {
        id = "share",
        label = L["Share"],
        primary = true,
        onClick = function()
          ns.Share.Open(selected)
        end,
      },
    },
  })
  -- the foot: the chosen list, and what can be done with it
  foot = Widgets.Foot(c)
  renameButton = foot:Tool({
    label = L["Rename"],
    onClick = function()
      local list = Notes.Global().lists[selected]
      Lists.AskName(list and list.name, function(value)
        if Notes.Model.RenameList(Notes.Global(), selected, value) then
          Notes.Changed()
        end
      end)
    end,
  })
  removeButton = foot:Tool({
    label = L["Remove list"],
    onClick = function()
      if Notes.Model.RemoveList(Notes.Global(), selected) then
        selected = "my"
        Notes.Changed()
      end
    end,
  })
  tree = B.UI.Tree(c, {
    db = ns.mod.db.profile.tree,
    ctx = { source = "notes" },
    capsSections = true, -- a list's name as a quiet heading with its count
    onClick = function(row, button)
      if row.button and button == "RightButton" then
        row.button.onClick(row)
      elseif row.onClick then
        row.onClick(row, button)
      end
    end,
  })
  tree.chips:ClearAllPoints()
  tree.chips:SetPoint("TOPLEFT", c, "TOPLEFT", TREE_LEFT, -4)
  tree.chips:SetPoint("TOPRIGHT", c, "TOPRIGHT", -TREE_RIGHT, -4)
  tree.scroll:ClearAllPoints()
  tree.scroll:SetPoint("TOPLEFT", tree.chips, "BOTTOMLEFT", 0, 0)
  tree.scroll:SetPoint("BOTTOMRIGHT", foot, "TOPRIGHT", -TREE_RIGHT, 30) -- the name box's room

  -- the name box over the foot: Enter keeps, Esc cancels
  nameBox = Widgets.Edit(c, L["List name"], function(value)
    nameBox:Hide()
    if nameBox.onDone then
      nameBox.onDone(value)
    end
  end)
  nameBox:SetPoint("BOTTOMLEFT", foot, "TOPLEFT", 8, 4)
  nameBox:SetPoint("BOTTOMRIGHT", foot, "TOPRIGHT", -8, 4)
  nameBox:SetMaxLetters(Notes.TITLE_MAX)
  nameBox:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    self:Hide()
  end)
  nameBox:Hide()
  Lists.newButton, Lists.importButton, Lists.shareButton = head.tools.new, head.tools.import, head.tools.share
  Lists.renameButton, Lists.removeButton, Lists.foot = renameButton, removeButton, foot
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
