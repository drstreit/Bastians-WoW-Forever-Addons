-- The search bar at the top of the map: from the second
-- character Core's search providers are asked (a type word first narrows: "npc wel"); the results
-- drop down under the box, a click flies the map to the entity (the map.show action) and the
-- "Route" button beside it asks Route (the route.to action) without the Map knowing Route. The
-- arrow keys (and Tab) move the selection, Enter takes it; a choice clears the box (owner,
-- retail 25.10.2026). Search.New makes one more box with its own list for another target: the
-- minimap's bar jumps the minimap; the map's box is Search itself.
-- The minimap's box narrows what it offers through the hooks below.
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

-- The map's own target: a click flies the big map; a zone has no place of its own, its action fits
-- the map to it.
local function mapTarget(ref)
  local action = B.Entity.Parse(ref) == "zone" and "map.zone" or "map.show"
  B:RunAction(action, ref, { source = "map.search" })
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

-- Fills `inst` with one search box on `parent` and its result list: inst.box, inst.list,
-- inst.results, inst.selected, inst:Run(text), inst:Move(delta). `onChoose(ref, result)` takes a
-- result. Hooks a caller may set on `inst` before (the minimap's box, map.md "The minimap search";
-- the map's own box sets none):
--   inst.keep(result) -> result or nil: the results it keeps, maybe as a new table
--   inst.extra(query, types) -> results of its own (the bookmarks), listed first
--   inst.blocked(types) -> a line shown instead of searching (a type word it cannot show), or nil
--   inst.onRun(query), inst.onEscape(): a new search starts, Esc in the box
-- A result without a ref is taken when it carries a `point` ({ continent, wx, wy }).
function Search.New(inst, parent, hint, onChoose)
  local box, list, handle
  local rows = {}
  inst.results = {}
  inst.selected = 0 -- the result the arrow keys point at (0: none yet)

  local function closeList()
    if list then
      list:Hide()
    end
  end

  -- A choice is made: the list goes and the box is empty again.
  local function finishChoice()
    closeList()
    if box and (box:GetText() or "") ~= "" then
      box:SetText("")
    end
    if box then
      box:ClearFocus()
    end
  end

  local function choose(res)
    finishChoice()
    onChoose(res.ref, res)
  end

  local function routeTo(ref)
    finishChoice()
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
    r.route = S.action(r, { icon = "route", label = L["Route"], row = true, boxed = true })
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
      if me.res and (me.ref or me.res.point) then
        choose(me.res)
      end
    end)
    rows[i] = r
    return r
  end

  -- Highlights the selected row (the arrow keys) or none.
  local function markSelected()
    for i, r in ipairs(rows) do
      if i == inst.selected and r:IsShown() and (r.ref or (r.res and r.res.point)) then
        r.hl:Show()
      elseif not r:IsMouseOver() then
        r.hl:Hide()
      end
    end
  end

  -- Moves the selection by delta through the results shown, wrapping around.
  function inst.Move(delta)
    local n = math.min(#inst.results, Search.LIMIT)
    if n == 0 then
      return
    end
    inst.selected = ((inst.selected - 1 + delta) % n) + 1
    markSelected()
  end

  -- The results in the list; `empty` is the line when there are none (default "No matches.").
  local function showResults(results, empty)
    inst.results = results
    inst.selected = 0
    local n = math.min(#results, Search.LIMIT)
    for i = 1, n do
      local r = row(i)
      local res = results[i]
      local entityType = B.Entity.Parse(res.ref)
      r.ref, r.res = res.ref, res
      local kind = res.kindLabel or L[entityType or "?"]
      r.label:SetText((res.label or res.ref) .. "  " .. S.H.muted .. kind .. "|r")
      r.route:SetShown(res.ref ~= nil and routeAvailable(res.ref))
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
      r.ref, r.res = nil, nil
      r.label:SetText(S.H.muted .. (empty or L["No matches."]) .. "|r")
      r.route:Hide()
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", 1, -1)
      r:SetPoint("RIGHT", -1, 0)
      r:Show()
      n = 1
    end
    list:SetHeight(2 + n * ROW_H)
    list:Show()
    markSelected()
  end

  -- Runs the search for the box text; results arrive through the Core job.
  function inst.Run(text)
    if handle then
      handle:Cancel()
      handle = nil
    end
    local query, types = B.ParseSearch(text or "")
    if #query < Search.MIN then
      inst.results = {}
      closeList()
      return
    end
    if inst.onRun then
      inst.onRun(query)
    end
    local note = inst.blocked and inst.blocked(types)
    if note then
      showResults({}, note)
      return
    end
    local own = inst.extra and inst.extra(query, types) or {}
    handle = B:Search(query, { limit = Search.LIMIT, types = types }, function(results, done)
      if inst.keep or #own > 0 then
        local out = {}
        for _, res in ipairs(own) do
          out[#out + 1] = res
        end
        for _, res in ipairs(results) do
          local kept = res
          if inst.keep then
            kept = inst.keep(res)
          end
          if kept then
            out[#out + 1] = kept
          end
        end
        results = out
      end
      if done or #results > 0 then
        showResults(results)
      end
    end)
  end

  box = S.search(parent, hint)
  box.queryFields = L["type (npc, item, quest, zone, ...)"] -- the world search's (ADR 0045)
  box:SetScript("OnTextChanged", function(me)
    local text = me:GetText() or ""
    if text == "" then
      me.hint:Show()
      me.clear:Hide()
    else
      me.hint:Hide()
      me.clear:Show()
    end
    inst.Run(text)
  end)
  box:SetScript("OnEscapePressed", function(me)
    me:SetText("")
    me:ClearFocus()
    closeList()
    if inst.onEscape then
      inst.onEscape()
    end
  end)
  box:SetScript("OnEnterPressed", function()
    local chosen = inst.results[inst.selected > 0 and inst.selected or 1]
    if chosen then
      choose(chosen)
    end
  end)
  if box.SetAltArrowKeyMode then
    box:SetAltArrowKeyMode(false) -- the arrow keys reach OnArrowPressed without Alt
  end
  box:SetScript("OnArrowPressed", function(_, key)
    if key == "DOWN" then
      inst.Move(1)
    elseif key == "UP" then
      inst.Move(-1)
    end
  end)
  box:SetScript("OnTabPressed", function()
    inst.Move(IsShiftKeyDown and IsShiftKeyDown() and -1 or 1)
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
  inst.box, inst.list = box, list
  return inst
end

-- The map's box on its toolbar (Map.LayoutToolbar places it).
function Search.Attach(toolbar)
  Search.New(Search, toolbar, L["Search the world ..."], mapTarget)
  toolbar.search = Search.box
end
