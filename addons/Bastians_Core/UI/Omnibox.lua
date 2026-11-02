-- Omnibox (core.md): one search window over every search provider. A result opens in the Browser when
-- it is installed, otherwise its entity menu. Bound to a key (Bindings.xml) and reachable from the launcher.
local _, ns = ...
local B = ns.B
local L = ns.L
local S = ns.Style

local Omnibox = {}
B.UI.Omnibox = Omnibox

local LIMIT = 40
local win, box, tree, status, hint
local lastResults = {} -- the newest results, regrouped when the type filter changes
local typeFilter -- a type ("npc"), or nil for every type (Tab cycles, ADR 0038)
local TYPE_ORDER = { "npc", "quest", "item", "zone", "object", "node", "recipe", "spot", "chain" }

local function openResult(row)
  if not row.ref then
    if row.action then
      row.action()
    end
    return
  end
  B:Fire("BASTIANS_ENTITY_FOCUSED", row.ref, { source = "omnibox" })
  if B:GetAction("browser.open") then
    B:RunAction("browser.open", row.ref, { source = "omnibox" })
  else
    B.UI.EntityMenu(row.ref, tree.pool[1], { source = "omnibox" })
  end
end

-- The types of the results in a fixed order, the rest after them (for the Tab cycle).
local function typesOf(results)
  local seen, out = {}, {}
  for _, r in ipairs(results) do
    local typ = r.ref and B.Entity.Parse(r.ref) or nil
    if typ and not seen[typ] then
      seen[typ] = true
    end
  end
  for _, typ in ipairs(TYPE_ORDER) do
    if seen[typ] then
      out[#out + 1] = typ
      seen[typ] = nil
    end
  end
  local rest = {}
  for typ in pairs(seen) do
    rest[#rest + 1] = typ
  end
  table.sort(rest)
  for _, typ in ipairs(rest) do
    out[#out + 1] = typ
  end
  return out
end
Omnibox.TypesOf = typesOf

-- The rows of the palette (ADR 0038): the results grouped by type under a section row with the
-- type's tile and count, the actions (no ref) first; `filter` keeps one type. Pure.
function Omnibox.Rows(results, filter)
  local rows, byType, actions = {}, {}, {}
  for _, r in ipairs(results) do
    local typ = r.ref and B.Entity.Parse(r.ref) or nil
    local row = {
      id = r.ref or r.label,
      text = r.label,
      ref = r.ref,
      note = r.note,
      action = r.action,
      icon = r.ref and B:Entity(r.ref):Icon() or nil,
      onClick = function(row)
        openResult(row)
      end,
    }
    if not typ then
      actions[#actions + 1] = row -- a provider's offer, after the groups
    elseif filter == nil or filter == typ then
      if not byType[typ] then
        byType[typ] = {}
      end
      local list = byType[typ]
      list[#list + 1] = row
    end
  end
  for _, typ in ipairs(typesOf(results)) do
    local list = byType[typ]
    if list then
      rows[#rows + 1] = {
        id = "type:" .. typ,
        kind = "section",
        text = L[typ] .. "  " .. S.H.muted .. #list .. "|r",
        icon = B.UI.IconTexture(typ) or nil,
      }
      for _, row in ipairs(list) do
        rows[#rows + 1] = row
      end
    end
  end
  for _, row in ipairs(actions) do
    rows[#rows + 1] = row
  end
  return rows
end

local function hintText()
  local types = typesOf(lastResults)
  local words = typeFilter and L[typeFilter] or L["All"]
  if #types > 0 then
    return string.format("%s: %s   %s", L["Tab"], words, L["Enter: open   Esc: close"])
  end
  return L["Enter: open   Esc: close"]
end

local function showResults(results, done)
  lastResults = results
  local present = false
  for _, typ in ipairs(typesOf(results)) do
    if typ == typeFilter then
      present = true
    end
  end
  if typeFilter and not present then
    typeFilter = nil -- the type is gone from the results
  end
  tree:SetRows(Omnibox.Rows(results, typeFilter))
  if #results == 0 then
    status:SetText(done and L["No results"] or L["Searching..."])
  else
    status:SetText(string.format("%d %s", #results, done and L["results"] or L["results so far..."]))
  end
  if hint then
    hint:SetText(hintText())
  end
end

-- Tab: the next type of the results (All, then each type that has results), ADR 0038.
function Omnibox.NextType()
  local types = typesOf(lastResults)
  if #types == 0 then
    typeFilter = nil
    return nil
  end
  local at = 0
  for i, typ in ipairs(types) do
    if typ == typeFilter then
      at = i
    end
  end
  typeFilter = types[at + 1] -- past the last: nil, every type again
  tree:SetRows(Omnibox.Rows(lastResults, typeFilter))
  if hint then
    hint:SetText(hintText())
  end
  return typeFilter
end

function Omnibox.TypeFilter()
  return typeFilter
end

local function search(text)
  text = string.gsub(text or "", "^%s*(.-)%s*$", "%1")
  if text == "" then
    tree:SetRows({})
    status:SetText(L["Type to search quests, NPCs, items, zones..."])
    return
  end
  B:Search(text, { limit = LIMIT }, showResults)
end

local function build()
  win = B.UI.Window("BastiansOmniboxFrame", {
    module = "Core", -- the options button opens this page (R27.1)
    title = L["Search"],
    width = 420,
    height = 380,
    db = ns.core.db.profile.omnibox,
    onShow = function()
      box:SetFocus()
      search(box:GetText())
    end,
    onResize = function()
      tree:Refresh()
    end,
  })
  box = B.UI.Widgets.Edit(win.content, L["Search"], function()
    for _, row in ipairs(tree.flat) do
      if row.kind ~= "section" then -- Enter opens the first result, not a group's title
        openResult(row)
        return
      end
    end
  end)
  box.plainText = nil -- a search: the syntax on its tooltip (ADR 0045)
  box.queryFields = L["type (npc, item, quest, zone, ...)"]
  box:SetScript("OnTabPressed", function()
    Omnibox.NextType()
  end)
  box:SetPoint("TOPLEFT", 6, -6)
  box:SetPoint("RIGHT", -6, 0)
  box:HookScript("OnTextChanged", function(self)
    search(self:GetText())
  end)
  status = S.text(win.content, 11, S.C.dim)
  status:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 2, -4)
  status:SetPoint("RIGHT", -6, 0)
  tree = B.UI.Tree(win.content, { db = ns.core.db.profile.omniboxTree, ctx = { source = "omnibox" } })
  tree.scroll:ClearAllPoints()
  tree.scroll:SetPoint("TOPLEFT", status, "BOTTOMLEFT", -2, -4)
  tree.scroll:SetPoint("BOTTOMRIGHT", win.content, "BOTTOMRIGHT", -14, 20)
  hint = S.text(win.content, 11, S.C.muted) -- the keys, like a command palette's footer (ADR 0038)
  hint:SetPoint("BOTTOMLEFT", win.content, "BOTTOMLEFT", 8, 5)
  hint:SetPoint("RIGHT", -6, 0)
  hint:SetText(hintText())
  Omnibox.win, Omnibox.box, Omnibox.tree, Omnibox.status, Omnibox.hint = win, box, tree, status, hint
  status:SetText(L["Type to search quests, NPCs, items, zones..."])
end

function Omnibox.Open(text)
  if not win then
    build()
  end
  if text then
    box:SetText(text)
  end
  win:Show()
end

function Omnibox.Toggle()
  if win and win:IsShown() then
    win:Hide()
  else
    Omnibox.Open()
  end
end

-- Key binding names (the binding system reads these globals; see Bindings.xml)
BINDING_HEADER_BASTIANS = "Bastian's"
BINDING_NAME_BASTIANS_OMNIBOX = L["Open the search (omnibox)"]
BINDING_NAME_BASTIANS_HUB = L["Open the Bastian's hub"]

SLASH_BASTIANSSEARCH1 = "/bs"
SlashCmdList.BASTIANSSEARCH = function(msg)
  Omnibox.Open(msg ~= "" and msg or nil)
end
