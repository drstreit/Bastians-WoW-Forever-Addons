-- The search bar at the top of the map: from the second
-- character Core's search providers are asked (a type word first narrows: "npc wel"); the results
-- drop down under the box, a click flies the map to the entity (the map.show action) and the
-- "Route" button beside it asks Route (the route.to action) without the Map knowing Route.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style

local Search = {}
ns.Search = Search
ns.mod.Search = Search -- for tests and /dump, like the other map layers

Search.MIN = 2
Search.LIMIT = 10
local ROW_H = 20

local box, list, handle
local rows = {}
Search.results = {}

local function closeList()
  if list then
    list:Hide()
  end
end

local function flyTo(ref)
  closeList()
  B:RunAction("map.show", ref, { source = "map.search" })
end

local function routeTo(ref)
  closeList()
  B:RunAction("route.to", ref, { source = "map.search" })
end

local function row(i)
  local r = rows[i]
  if r then
    return r
  end
  r = CreateFrame("Button", nil, list)
  r:SetHeight(ROW_H)
  r:SetPoint("LEFT", 1, 0)
  r:SetPoint("RIGHT", -1, 0)
  r.hl = S.fill(r, S.C.hover, "ARTWORK")
  r.hl:Hide()
  r.label = S.text(r, 12)
  r.label:SetPoint("LEFT", 8, 0)
  r.label:SetPoint("RIGHT", -64, 0)
  r.label:SetJustifyH("LEFT")
  r.route = S.button(r, L["Route"], 54, ROW_H - 2)
  r.route.tip = L["Plan a route there."]
  r.route:SetPoint("RIGHT", -2, 0)
  r.route:SetScript("OnClick", function()
    routeTo(r.ref)
  end)
  r:SetScript("OnEnter", function(me)
    me.hl:Show()
  end)
  r:SetScript("OnLeave", function(me)
    me.hl:Hide()
  end)
  r:SetScript("OnClick", function(me)
    flyTo(me.ref)
  end)
  rows[i] = r
  return r
end

-- Whether Route (or another app) offers a route action for the entity.
local function routeAvailable(ref)
  for _, action in ipairs(B:GetActions(ref, { source = "map.search" })) do
    if action.id == "route.to" then
      return true
    end
  end
  return false
end

local function showResults(results)
  Search.results = results
  local n = math.min(#results, Search.LIMIT)
  for i = 1, n do
    local r = row(i)
    local res = results[i]
    local entityType = B.Entity.Parse(res.ref)
    r.ref = res.ref
    r.label:SetText((res.label or res.ref) .. "  " .. S.H.muted .. L[entityType or "?"] .. "|r")
    r.route:SetShown(routeAvailable(res.ref))
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 1, -(1 + (i - 1) * ROW_H))
    r:SetPoint("RIGHT", -1, 0)
    r:Show()
  end
  for i = n + 1, #rows do
    rows[i]:Hide()
  end
  if n == 0 then
    local r = row(1)
    r.ref = nil
    r.label:SetText(S.H.muted .. L["No matches."] .. "|r")
    r.route:Hide()
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 1, -1)
    r:SetPoint("RIGHT", -1, 0)
    r:Show()
    n = 1
  end
  list:SetHeight(2 + n * ROW_H)
  list:Show()
end

-- Runs the search for the box text; results arrive through the Core job.
function Search.Run(text)
  if handle then
    handle:Cancel()
    handle = nil
  end
  local query, types = B.ParseSearch(text or "")
  if #query < Search.MIN then
    Search.results = {}
    closeList()
    return
  end
  handle = B:Search(query, { limit = Search.LIMIT, types = types }, function(results, done)
    if done or #results > 0 then
      showResults(results)
    end
  end)
end

function Search.Attach(toolbar)
  box = S.search(toolbar, L["Search the world ..."])
  box:SetPoint("LEFT", toolbar.player, "RIGHT", 8, 0)
  box:SetPoint("RIGHT", toolbar, "RIGHT", -190, 0)
  box:SetScript("OnTextChanged", function(me)
    local text = me:GetText() or ""
    if text == "" then
      me.hint:Show()
      me.clear:Hide()
    else
      me.hint:Hide()
      me.clear:Show()
    end
    Search.Run(text)
  end)
  box:SetScript("OnEscapePressed", function(me)
    me:SetText("")
    me:ClearFocus()
    closeList()
  end)
  box:SetScript("OnEnterPressed", function()
    local first = Search.results[1]
    if first then
      flyTo(first.ref)
    end
  end)
  list = CreateFrame("Frame", nil, box)
  list:SetFrameStrata("TOOLTIP")
  list:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -1)
  list:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -1)
  S.panel(list, S.C.panel)
  list:Hide()
  list:SetScript("OnShow", function(me)
    me:RegisterEvent("GLOBAL_MOUSE_DOWN")
  end)
  list:SetScript("OnHide", function(me)
    me:UnregisterEvent("GLOBAL_MOUSE_DOWN")
  end)
  list:SetScript("OnEvent", function(me)
    if not (me:IsMouseOver() or box:IsMouseOver()) then
      me:Hide()
    end
  end)
  toolbar.search = box
  Search.box, Search.list = box, list
end
