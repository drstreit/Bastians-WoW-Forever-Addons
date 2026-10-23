-- Omnibox (core.md): one search window over every search provider. A result opens in the Browser when
-- it is installed, otherwise its entity menu. Bound to a key (Bindings.xml) and reachable from the launcher.
local _, ns = ...
local B = ns.B
local L = ns.L
local S = ns.Style

local Omnibox = {}
B.UI.Omnibox = Omnibox

local LIMIT = 40
local win, box, tree, status

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

local function showResults(results, done)
  local rows = {}
  for _, r in ipairs(results) do
    rows[#rows + 1] = {
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
  end
  tree:SetRows(rows)
  if #results == 0 then
    status:SetText(done and L["No results"] or L["Searching..."])
  else
    status:SetText(string.format("%d %s", #results, done and L["results"] or L["results so far..."]))
  end
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
    local first = tree.flat[1]
    if first then
      openResult(first)
    end
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
  tree.scroll:SetPoint("BOTTOMRIGHT", win.content, "BOTTOMRIGHT", -14, 6)
  Omnibox.win, Omnibox.box, Omnibox.tree, Omnibox.status = win, box, tree, status
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
